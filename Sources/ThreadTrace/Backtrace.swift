//
//  Backtrace.swift
//  ThreadTrace
//

import Darwin

/// A stack trace captured from a thread.
///
/// ```swift
/// let trace = try Backtrace.currentThread()
/// print(trace)
/// ```
public struct Backtrace: Sendable, CustomStringConvertible {
    /// One resolved frame in a captured stack.
    public struct Frame: Sendable, Equatable {
        /// Position in the trace, `0` being the innermost frame.
        public let index: Int

        /// Instruction address of the frame.
        public let address: UInt

        /// Name of the image that contains the address.
        public let image: String

        /// Closest symbol, when the image exposes one.
        public let symbol: String?

        /// Offset of `address` from `symbol` or, when `symbol` is `nil`, from
        /// the start of the image.
        public let offset: UInt
    }

    /// Resolved frames, innermost first.
    public let frames: [Frame]

    /// Whether the capture may be incomplete. This is `true` when the frame
    /// limit was reached or when the stack could not be read to its end.
    public let isTruncated: Bool

    /// Captures the stack trace of the calling thread.
    ///
    /// - Parameter maximumFrameCount: Upper bound for the number of captured
    ///   instruction addresses. Values below `1` are treated as `1`; values
    ///   above `1024` as `1024`.
    public static func currentThread(maximumFrameCount: Int = 128) throws -> Backtrace {
        let limit = clamp(maximumFrameCount)
        let result = SystemUnwinder.capture(limit: limit)
        guard !result.addresses.isEmpty else {
            throw BacktraceError.noFrames
        }
        return build(addresses: result.addresses, isTruncated: result.isTruncated)
    }

    /// Captures the stack trace of the process' main thread.
    ///
    /// This can be called from any thread, including while the main thread is
    /// blocked.
    ///
    /// - Parameter maximumFrameCount: Upper bound for the number of captured
    ///   instruction addresses. Values below `1` are treated as `1`; values
    ///   above `1024` as `1024`.
    public static func mainThread(maximumFrameCount: Int = 128) throws -> Backtrace {
        let limit = clamp(maximumFrameCount)

        // Capturing the calling thread through thread_get_state would observe
        // the mach call itself, so use the system unwinder when the caller is
        // the main thread.
        if pthread_main_np() != 0 {
            return try currentThread(maximumFrameCount: limit)
        }

        guard let port = MachThread.main else {
            throw BacktraceError.mainThreadUnavailable
        }
        let registers = try MachThread.registers(of: port)
        let result = StackUnwinder.unwind(from: registers, limit: limit)
        guard !result.addresses.isEmpty else {
            throw BacktraceError.noFrames
        }
        return build(addresses: result.addresses, isTruncated: result.isTruncated)
    }

    /// A multi-line rendering of the trace.
    public var description: String {
        var lines = ["\(frames.count) frame\(frames.count == 1 ? "" : "s"):"]
        for frame in frames {
            let address = "0x" + String(frame.address, radix: 16)
            lines.append("  #\(frame.index)  \(address)  \(frame.image)  \(Self.symbolText(for: frame))")
        }
        if isTruncated {
            lines.append("  (partial trace)")
        }
        return lines.joined(separator: "\n")
    }

    private static func build(addresses: [UInt], isTruncated: Bool) -> Backtrace {
        var frames: [Frame] = []
        frames.reserveCapacity(addresses.count)
        for (position, address) in addresses.enumerated() {
            guard let resolved = Symbolication.resolve(address: address, isReturnAddress: position > 0) else {
                continue
            }
            frames.append(
                Frame(
                    index: frames.count,
                    address: address,
                    image: resolved.image,
                    symbol: resolved.symbol,
                    offset: resolved.offset
                )
            )
        }
        return Backtrace(frames: frames, isTruncated: isTruncated)
    }

    private static func clamp(_ frameCount: Int) -> Int {
        min(max(frameCount, 1), 1_024)
    }

    private static func symbolText(for frame: Frame) -> String {
        guard let symbol = frame.symbol else {
            return "<unknown> + \(frame.offset)"
        }
        return "\(symbol) + \(frame.offset)"
    }
}
