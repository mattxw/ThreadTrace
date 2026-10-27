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

/// A lock-protected container used to hand a capture from a watchdog thread
/// back to the test that started it.
private final class TraceBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storedTrace: Backtrace?
    private var storedFailure: String?

    func store(_ result: Result<Backtrace, any Error>) {
        lock.lock()
        defer { lock.unlock() }
        switch result {
        case .success(let trace):
            storedTrace = trace
        case .failure(let error):
            storedFailure = String(describing: error)
        }
    }

    func load() -> (trace: Backtrace?, failure: String?) {
        lock.lock()
        defer { lock.unlock() }
        return (storedTrace, storedFailure)
    }
}

/// Blocks the calling thread so a watchdog can observe a stable stack.
@inline(never)
private func blockMainThread(on semaphore: DispatchSemaphore) {
    _ = semaphore.wait(timeout: .now() + 5)
}

@Suite(.serialized)
struct BacktraceTests {
    @Test
    func currentThreadReturnsResolvedFrames() throws {
        let trace = try Backtrace.currentThread()

        #expect(!trace.frames.isEmpty)
        #expect(trace.frames.first?.index == 0)
        #expect(trace.frames.map(\.index) == Array(0..<trace.frames.count))
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
    func asyncTaskIncludesContinuationFrames() async throws {
        let trace = try Backtrace.currentThread(maximumFrameCount: 1_024)

        // `backtrace_async` marks continuation addresses with the low bit, so
        // an async task reports the frames that awaited or resumed it.
        #expect(
            trace.frames.contains { frame in
                (frame.address & 1) == 1
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
    func mainThreadCanBeCapturedWhileBlocked() async throws {
        let box = TraceBox()
        let startCapture = DispatchSemaphore(value: 0)
        let captureFinished = DispatchSemaphore(value: 0)

        let watchdog = Thread {
            startCapture.wait()
            // Let the main thread reach the blocking call before sampling it.
            usleep(150_000)
            box.store(Result { try Backtrace.mainThread() })
            captureFinished.signal()
        }
        watchdog.start()

        await MainActor.run {
            startCapture.signal()
            blockMainThread(on: captureFinished)
        }

        let (trace, failure) = box.load()
        #expect(failure == nil, "capture failed: \(failure ?? "")")
        let captured = try #require(trace)
        #expect(!captured.frames.isEmpty)
        // The main thread is parked in `blockMainThread`, which a capture of
        // the watchdog's own thread could not contain. The mangled symbol
        // abbreviates the module name, so match the distinctive prefix.
        #expect(
            captured.frames.contains { frame in
                (frame.symbol ?? "").contains("blockMain")
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
    func extremeFrameCountsAreClamped() throws {
        let unbounded = try Backtrace.currentThread(maximumFrameCount: .max)
        #expect(unbounded.frames.count <= 1_024)

        let minimum = try Backtrace.currentThread(maximumFrameCount: .min)
        #expect(minimum.frames.count == 1)
    }

    @Test
    func renderingUsesDocumentedFormat() throws {
        let text = try Backtrace.currentThread().description

        #expect(text.contains("frames:"))
        #expect(text.contains("#0"))
    }

    @Test
    func partialTraceIsMarkedInDescription() throws {
        let text = try captureWithTinyLimit().description

        #expect(text.contains("(partial trace)"))
    }

    @Test
    func repeatedCapturesStayStable() throws {
        for _ in 0..<10 {
            let trace = try Backtrace.currentThread()
            #expect(!trace.frames.isEmpty)
        }
    }
}
