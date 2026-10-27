//
//  MachThread.swift
//  ThreadTrace
//

import Darwin

/// Returns the main thread's `pthread_t`.
///
/// `pthread_main_thread_np` is exported by libsystem_pthread but is not
/// declared in the public `<pthread.h>` header, so it is declared explicitly.
/// Unlike `pthread_main_np()`, which reports whether the *calling* thread is
/// the main thread, this works from any thread.
@_silgen_name("pthread_main_thread_np")
private func mainThreadPthread() -> pthread_t

/// Access to mach thread ports and their register state.
enum MachThread {
    typealias Port = thread_t

    /// The port of the process' main thread.
    static var main: Port? {
        let port = pthread_mach_thread_np(mainThreadPthread())
        return port == MACH_PORT_NULL ? nil : port
    }

    /// Reads the registers of `port`.
    static func registers(of port: Port) throws -> RegisterSnapshot {
        var state = NativeThreadState()
        var count = mach_msg_type_number_t(MemoryLayout<NativeThreadState>.size / MemoryLayout<natural_t>.size)

        let status = withUnsafeMutablePointer(to: &state) { pointer in
            pointer.withMemoryRebound(to: natural_t.self, capacity: Int(count)) { statePointer in
                thread_get_state(port, nativeThreadStateFlavor, statePointer, &count)
            }
        }

        guard status == KERN_SUCCESS else {
            throw BacktraceError.threadStateUnavailable(kernReturn: status)
        }
        return RegisterSnapshot(state)
    }
}
