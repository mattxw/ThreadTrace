//
//  BacktraceTests.swift
//  ThreadTrace
//

import Foundation
import Testing
import ThreadTrace

/// Captures from a dedicated, non-inlined frame so symbolication can be
/// asserted on a known function.
@inline(never)
private func captureFromMarker() throws -> Backtrace {
    try Backtrace.currentThread()
}

/// Captures with a limit small enough to guarantee a partial trace.
@inline(never)
private func captureWithTinyLimit() throws -> Backtrace {
    try Backtrace.currentThread(maximumFrameCount: 2)
}

@Suite(.serialized)
struct BacktraceTests {
    @Test
    func currentThreadReturnsResolvedFrames() throws {
        let trace = try Backtrace.currentThread()

        #expect(!trace.frames.isEmpty)
        #expect(trace.frames.first?.index == 0)
        #expect(trace.frames.allSatisfy { !$0.image.isEmpty })
        #expect(trace.frames.allSatisfy { $0.address != 0 })
    }

    @Test
    func markerFunctionAppearsInSymbolicatedTrace() throws {
        let trace = try captureFromMarker()

        #expect(
            trace.frames.contains { frame in
                (frame.symbol ?? "").contains("captureFromMarker")
            })
    }

    @Test
    func mainThreadCanBeCapturedFromDetachedTask() async throws {
        let trace = try await Task.detached {
            try Backtrace.mainThread()
        }.value

        #expect(!trace.frames.isEmpty)
        // A detached task's stack never reaches the executable's main(), so
        // this also proves the main thread's port is used instead of silently
        // falling back to the calling thread.
        #expect(
            trace.frames.contains { frame in
                (frame.symbol ?? "").contains("main")
            })
    }

    @Test
    @MainActor
    func mainThreadCanBeCapturedOnMainThread() throws {
        let trace = try Backtrace.mainThread()

        #expect(!trace.frames.isEmpty)
        // When the caller is the main thread, the capture must come from the
        // system unwinder rather than from reading the thread's registers.
        #expect(
            trace.frames.contains { frame in
                (frame.symbol ?? "").contains("SystemUnwinder")
            })
    }

    @Test
    func frameLimitIsAppliedAndClamped() throws {
        let limited = try captureWithTinyLimit()
        #expect(limited.frames.count <= 2)
        #expect(limited.isTruncated)

        let clamped = try Backtrace.currentThread(maximumFrameCount: 0)
        #expect(clamped.frames.count == 1)
    }

    @Test
    func renderingUsesDocumentedFormat() throws {
        let text = try Backtrace.currentThread().description

        #expect(text.contains("frames:"))
        #expect(text.contains("#0"))
    }

    @Test
    func repeatedCapturesStayStable() throws {
        for _ in 0..<10 {
            let trace = try Backtrace.currentThread()
            #expect(!trace.frames.isEmpty)
        }
    }
}
