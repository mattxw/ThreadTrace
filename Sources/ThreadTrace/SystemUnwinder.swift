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
    /// Addresses of the calling thread's stack, innermost first.
    static func capture(limit: Int) -> [UInt] {
        var buffer = [UnsafeMutableRawPointer?](repeating: nil, count: limit)
        let count = buffer.withUnsafeMutableBufferPointer { pointer -> Int32 in
            guard let baseAddress = pointer.baseAddress else {
                return 0
            }
            return backtrace(baseAddress, Int32(pointer.count))
        }
        return buffer.prefix(Int(max(count, 0))).compactMap { address in
            address.map { UInt(bitPattern: $0) }
        }
    }
}
