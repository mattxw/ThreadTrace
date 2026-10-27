//
//  BacktraceError.swift
//  ThreadTrace
//

import Darwin

/// Errors thrown when a stack trace cannot be captured.
public enum BacktraceError: Error, Equatable, CustomStringConvertible {
    /// The process' main thread could not be resolved.
    case mainThreadUnavailable

    /// Reading the target thread's registers failed.
    case threadStateUnavailable(kernReturn: kern_return_t)

    /// The thread produced no instruction addresses.
    case noFrames

    public var description: String {
        switch self {
        case .mainThreadUnavailable:
            "The main thread could not be resolved."
        case .threadStateUnavailable(let kernReturn):
            "The thread state could not be read (kern_return_t \(kernReturn))."
        case .noFrames:
            "The thread has no readable frames."
        }
    }
}
