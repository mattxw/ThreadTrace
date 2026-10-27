//
//  StackUnwinder.swift
//  ThreadTrace
//

import Darwin

/// Reconstructs instruction addresses of another thread from its registers.
enum StackUnwinder {
    /// Addresses captured before unwinding stopped, innermost first.
    struct Result {
        let addresses: [UInt]

        /// Whether unwinding stopped early because of the frame limit, a
        /// missing frame pointer or unreadable stack memory.
        let isTruncated: Bool
    }

    /// The two pointers stored at the start of a frame: the caller's frame
    /// pointer and the address to return to.
    private struct FrameLink {
        let callerFrame: UInt
        let returnAddress: UInt
    }

    /// Unwinds the stack described by `registers`, collecting at most `limit`
    /// instruction addresses.
    static func unwind(from registers: RegisterSnapshot, limit: Int) -> Result {
        // `reserveCapacity` traps on a negative value, so reject an exhausted
        // or nonsensical budget before allocating anything.
        guard limit > 0 else {
            return Result(addresses: [], isTruncated: true)
        }

        var addresses: [UInt] = []
        addresses.reserveCapacity(limit)

        if registers.programCounter != 0 {
            addresses.append(registers.programCounter)
        }
        guard addresses.count < limit else {
            return Result(addresses: addresses, isTruncated: true)
        }

        let firstFrame = registers.framePointer
        if firstFrame == 0 {
            appendLinkRegister(from: registers, link: nil, to: &addresses, limit: limit)
            return Result(addresses: addresses, isTruncated: true)
        }
        guard let firstLink = readFrameLink(at: firstFrame) else {
            appendLinkRegister(from: registers, link: nil, to: &addresses, limit: limit)
            return Result(addresses: addresses, isTruncated: true)
        }

        appendLinkRegister(from: registers, link: firstLink, to: &addresses, limit: limit)

        let isTruncated = appendFrames(
            startingAt: firstFrame,
            firstLink: firstLink,
            limit: limit,
            addresses: &addresses
        )
        return Result(addresses: addresses, isTruncated: isTruncated)
    }

    /// Appends the frame chain that starts at `firstFrame`, returning whether
    /// the budget, a cycle or an unreadable link ended the walk early.
    private static func appendFrames(
        startingAt firstFrame: UInt,
        firstLink: FrameLink,
        limit: Int,
        addresses: inout [UInt]
    ) -> Bool {
        var visitedFrames: Set<UInt> = []
        var frameAddress = firstFrame
        var pendingLink: FrameLink? = firstLink

        while addresses.count < limit {
            guard visitedFrames.insert(frameAddress).inserted else {
                return true
            }
            guard let link = pendingLink ?? readFrameLink(at: frameAddress) else {
                return true
            }
            pendingLink = nil

            guard link.returnAddress != 0 else {
                return false
            }
            addresses.append(link.returnAddress)

            guard link.callerFrame != 0 else {
                return false
            }
            frameAddress = link.callerFrame
        }

        return true
    }

    /// Adds the link register as the caller of a leaf frame, when the budget
    /// allows it and the register holds a usable address.
    ///
    /// A leaf function has no frame record of its own, so the link register is
    /// the only source for its caller. When the frame record already holds
    /// that same return address, the caller did establish a frame and adding
    /// the register would duplicate the next frame. A register that still
    /// points into the sampled function itself is stale and is rejected too.
    private static func appendLinkRegister(
        from registers: RegisterSnapshot,
        link: FrameLink?,
        to addresses: inout [UInt],
        limit: Int
    ) {
        guard addresses.count < limit, registers.linkRegister != 0 else {
            return
        }
        guard addresses.last != registers.linkRegister else {
            return
        }
        if let link {
            if link.returnAddress == registers.linkRegister {
                return
            }
            if Symbolication.isSameSymbol(registers.programCounter, registers.linkRegister) {
                return
            }
        }
        addresses.append(registers.linkRegister)
    }

    /// Copies a frame link out of the stack through the kernel instead of
    /// dereferencing `address` in-process. A stale or unmapped frame pointer
    /// therefore fails the read rather than trapping the process, which is
    /// essential when the target thread is still running.
    private static func readFrameLink(at address: UInt) -> FrameLink? {
        var link = FrameLink(callerFrame: 0, returnAddress: 0)
        var bytesRead: vm_size_t = 0

        let status = withUnsafeMutableBytes(of: &link) { buffer -> kern_return_t in
            guard let baseAddress = buffer.baseAddress else {
                return KERN_FAILURE
            }
            return vm_read_overwrite(
                mach_task_self_,
                vm_address_t(address),
                vm_size_t(buffer.count),
                vm_address_t(UInt(bitPattern: baseAddress)),
                &bytesRead
            )
        }

        guard status == KERN_SUCCESS, bytesRead == vm_size_t(MemoryLayout<FrameLink>.size) else {
            return nil
        }
        return FrameLink(
            callerFrame: Architecture.sanitize(link.callerFrame),
            returnAddress: Architecture.sanitize(link.returnAddress)
        )
    }
}
