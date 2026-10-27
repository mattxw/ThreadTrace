//
//  SystemUnwinder.swift
//  ThreadTrace
//

import Darwin

/// Captures the calling thread's stack with the system's stack unwinder.
///
/// Reading the calling thread's registers with `thread_get_state` observes the
/// mach call that performs the read, which yields a stack without useful
/// caller frames. The system unwinder does not have that limitation.
enum SystemUnwinder {
    /// Addresses captured from the calling thread, innermost first.
    struct Result {
        let addresses: [UInt]

        /// Whether a frame had to be dropped because of the frame limit.
        let isTruncated: Bool
    }

    /// Captures the calling thread's stack, returning at most `limit`
    /// addresses.
    ///
    /// `backtrace_async` is equivalent to `backtrace` outside a Swift
    /// concurrency context. Inside one, it continues past the executor frames
    /// and returns the async continuation chain as well, so the frames that
    /// resumed the current task appear in the trace. Continuation addresses
    /// carry a `+1` adjustment; the usual "subtract one" symbolication step
    /// in `Backtrace` therefore lands on the awaiting frame.
    static func capture(limit: Int) -> Result {
        // Request one address beyond the limit so that a buffer that filled up
        // can be told apart from a stack that ended exactly at the limit.
        let capacity = limit + 1
        var buffer = [UnsafeMutableRawPointer?](repeating: nil, count: capacity)
        let count = buffer.withUnsafeMutableBufferPointer { pointer -> Int in
            guard let baseAddress = pointer.baseAddress else {
                return 0
            }
            #if os(iOS) || os(macOS)
            return backtrace_async(baseAddress, pointer.count, nil)
            #else
            // Unsupported platforms keep the thread-only stack.
            return Int(backtrace(baseAddress, Int32(pointer.count)))
            #endif
        }

        let captured = min(max(count, 0), buffer.count)
        let addresses = buffer.prefix(captured).compactMap { address in
            address.map { UInt(bitPattern: $0) }
        }
        return Result(
            addresses: Array(addresses.prefix(limit)),
            isTruncated: captured > limit
        )
    }
}
