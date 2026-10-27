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
        var addresses: [UInt] = []
        addresses.reserveCapacity(limit)

        if registers.programCounter != 0 {
            addresses.append(registers.programCounter)
        }
        if addresses.count < limit, registers.linkRegister != 0 {
            addresses.append(registers.linkRegister)
        }

        let firstFrame = registers.framePointer
        guard firstFrame != 0 else {
            return Result(addresses: addresses, isTruncated: true)
        }

        var visitedFrames: Set<UInt> = []
        var frameAddress = firstFrame

        while addresses.count < limit {
            guard visitedFrames.insert(frameAddress).inserted else {
                return Result(addresses: addresses, isTruncated: true)
            }
            guard let link = readFrameLink(at: frameAddress) else {
                return Result(addresses: addresses, isTruncated: true)
            }
            guard link.returnAddress != 0 else {
                return Result(addresses: addresses, isTruncated: false)
            }

            addresses.append(link.returnAddress)

            guard link.callerFrame != 0 else {
                return Result(addresses: addresses, isTruncated: false)
            }
            frameAddress = link.callerFrame
        }

        return Result(addresses: addresses, isTruncated: true)
    }

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
