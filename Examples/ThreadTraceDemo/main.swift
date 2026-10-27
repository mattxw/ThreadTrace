//
//  main.swift
//  ThreadTraceDemo
//
//  Captures the main thread from a watchdog thread while the main thread is
//  busy.
//

import Foundation
import ThreadTrace

print("Current thread:")
do {
    print(try Backtrace.currentThread())
} catch {
    print("Failed to capture the current thread: \(error)")
}

print("\nSimulating a 2 second main-thread stall...\n")

let watchdog = Thread {
    Thread.sleep(forTimeInterval: 0.5)
    print("Main thread captured by the watchdog:")
    do {
        print(try Backtrace.mainThread())
    } catch {
        print("Failed to capture the main thread: \(error)")
    }
}
watchdog.name = "ThreadTraceDemo.watchdog"
watchdog.start()

stallMainThread(for: 2)

@inline(never)
func stallMainThread(for duration: TimeInterval) {
    let deadline = Date().addingTimeInterval(duration)
    while Date() < deadline {
        // Busy main thread, as in a real hang.
    }
}
