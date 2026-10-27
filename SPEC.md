# ThreadTrace specification

This document describes the observable behavior of the library. It contains no
implementation details; the implementation is written from this specification.

## Scope

ThreadTrace captures the call stack of a thread in the current process and
resolves each frame to an image and, when available, a symbol.

Two entry points are required:

1. Capture the stack of the **calling thread**.
2. Capture the stack of the **main thread**, callable from any thread,
   including while the main thread is blocked.

## API

```swift
public struct Backtrace: Sendable, CustomStringConvertible {
    public struct Frame: Sendable, Equatable {
        public let index: Int
        public let address: UInt
        public let image: String
        public let symbol: String?
        public let offset: UInt
    }

    public let frames: [Frame]
    public let isTruncated: Bool

    public static func currentThread(maximumFrameCount: Int = 128) throws -> Backtrace
    public static func mainThread(maximumFrameCount: Int = 128) throws -> Backtrace

    public var description: String
}

public enum BacktraceError: Error, Equatable, CustomStringConvertible {
    case mainThreadUnavailable
    case threadStateUnavailable(kernReturn: kern_return_t)
    case noFrames
}
```

## Behavior

### FR-1: Current thread

`Backtrace.currentThread()` returns the frames of the thread that calls it,
with the innermost frame at index `0`.

### FR-2: Main thread

`Backtrace.mainThread()` returns the frames of the process' main thread. It
must work from a background thread and must not require the main thread to be
running user code.

### FR-3: Frame contents

Each frame exposes:

- `index`: position in the trace, starting at `0`;
- `address`: the instruction address;
- `image`: the file name of the image that contains the address;
- `symbol`: the closest symbol name, or `nil` when the image has no usable
  symbol;
- `offset`: the distance from the symbol, or from the image base when `symbol`
  is `nil`.

Frames whose address cannot be resolved to a loaded image are omitted. Frame
indices are assigned after omitted frames are removed, so they are contiguous.

### FR-4: Frame limit

`maximumFrameCount` bounds the number of captured instruction addresses, not
the number of resolved frames. Values below `1` are treated as `1`; values
above `1024` are treated as `1024`. The default is `128`.

### FR-5: Partial traces

Unwinding stops when the outermost frame is reached or when the stack can no
longer be read. If it stops because of the frame limit, a missing frame
pointer, a cycle, or unreadable memory, `isTruncated` is `true` and the frames
captured so far are returned. `isTruncated` is `false` only for a trace that
reached the end of the frame chain.

### FR-6: Errors

- `mainThreadUnavailable` when the main thread cannot be resolved.
- `threadStateUnavailable(kernReturn:)` when the target thread's registers
  cannot be read.
- `noFrames` when the thread produced no instruction addresses.

### FR-7: Rendering

`description` renders a stable, human-readable listing:

```text
3 frames:
  #0  0x1021fe4b8  ThreadTraceDemo  main + 528
  #1  0x19b947e80  dyld  start + 6688
```

A partial trace appends `(partial trace)` as the final line.

### FR-8: Concurrency

- Capturing has no global mutable state and is safe to call from multiple
  threads concurrently.
- Capturing is not async-signal-safe and must not be called from a signal
  handler or an unsafe signal context.

## Platforms and constraints

- iOS 15.0+ and macOS 12.0+.
- 64-bit arm64, arm64e and x86_64 targets.
- Only threads in the current process can be captured.
- Frame pointers must be preserved by the compiler for a complete trace.
- Symbolication depends on the images' symbol tables; stripped images may
  only produce an image name and an image-relative offset.
