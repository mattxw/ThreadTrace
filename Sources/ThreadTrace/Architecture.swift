//
//  Architecture.swift
//  ThreadTrace
//

import Darwin

#if arch(arm64)
typealias NativeThreadState = arm_thread_state64_t
let nativeThreadStateFlavor: thread_state_flavor_t = ARM_THREAD_STATE64
#elseif arch(x86_64)
typealias NativeThreadState = x86_thread_state64_t
let nativeThreadStateFlavor: thread_state_flavor_t = x86_THREAD_STATE64
#else
#error("ThreadTrace supports arm64 and x86_64 targets only.")
#endif

/// The subset of CPU registers needed to reconstruct a call stack.
struct RegisterSnapshot {
    let programCounter: UInt
    let linkRegister: UInt
    let framePointer: UInt

    init(_ state: NativeThreadState) {
        #if arch(arm64)
        programCounter = Architecture.sanitize(UInt(state.__pc))
        linkRegister = Architecture.sanitize(UInt(state.__lr))
        framePointer = Architecture.sanitize(UInt(state.__fp))
        #else
        programCounter = Architecture.sanitize(UInt(state.__rip))
        linkRegister = 0
        framePointer = Architecture.sanitize(UInt(state.__rbp))
        #endif
    }
}

/// Platform details shared by the capture code.
enum Architecture {
    /// Removes pointer-authentication bits from a pointer-sized value.
    ///
    /// arm64e stores authentication bits in the upper 16 bits of a pointer.
    /// No valid user-space address uses those bits, so the mask is a no-op on
    /// plain arm64 and removes the signature on arm64e.
    static func sanitize(_ address: UInt) -> UInt {
        #if arch(arm64)
        address & 0x0000_FFFF_FFFF_FFFF
        #else
        address
        #endif
    }
}
