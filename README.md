# ThreadTrace

A small Swift library for capturing call stacks at runtime. It can inspect the
**calling thread** or the **main thread**, including while the main thread is
blocked, which makes it useful for main-thread hang diagnostics and watchdog
code.

The implementation is written from the behavior specification in
[SPEC.md](SPEC.md) and shares no source code with earlier Objective-C
implementations of similar functionality.

## Requirements

- iOS 15.0+ or macOS 12.0+
- Xcode 16+ (Swift 6 toolchain)
- 64-bit targets: `arm64`, `arm64e` or `x86_64`

## Installation

Add the package to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/mattxw/ThreadTrace.git", from: "1.0.0")
]
```

Then add the product to your target:

```swift
.target(
    name: "App",
    dependencies: [
        .product(name: "ThreadTrace", package: "ThreadTrace")
    ]
)
```

Or add it in Xcode with **File → Add Package Dependencies…**.

## Usage

```swift
import ThreadTrace

let current = try Backtrace.currentThread()
let main = try Backtrace.mainThread()

print(main)
```

Both methods return a `Backtrace` value. They throw a `BacktraceError` when
the thread's state cannot be read; there are no sentinel strings to check.

### Structured access

```swift
for frame in main.frames {
    print(frame.index, frame.image, frame.symbol ?? "<unknown>", frame.offset)
}
```

Each frame exposes:

| Property | Description |
| --- | --- |
| `index` | Position in the trace, `0` is the innermost frame. |
| `address` | Instruction address of the frame. |
| `image` | File name of the image containing the address. |
| `symbol` | Closest symbol, when the image exposes one. |
| `offset` | Distance from the symbol, or from the image base when `symbol` is `nil`. |

`Backtrace` conforms to `CustomStringConvertible`, so `print(main)` renders a
listing like this:

```text
3 frames:
  #0  0x1021fe4b8  ThreadTraceDemo  simulateWork + 216
  #1  0x1021fe008  ThreadTraceDemo  main + 868
  #2  0x19b947e80  dyld  start + 6688
```

Swift symbols are reported using their mangled names; pipe them through
`swift demangle` if you need a readable form. A capture that could not be
unwound to the end of the stack appends `(partial trace)` and sets
`isTruncated`.

### Capturing the main thread from a watchdog

```swift
let watchdog = Thread {
    do {
        let trace = try Backtrace.mainThread()
        print(trace)
    } catch {
        print("Failed to capture the main thread: \(error)")
    }
}
watchdog.name = "Watchdog"
watchdog.start()
```

Run the bundled demo to see this in action:

```sh
swift run ThreadTraceDemo
```

## How it works

- The calling thread is captured with the system stack unwinder, which works
  even when frame pointers are omitted.
- Other threads (including the main thread when called from a background
  thread) are captured by reading their registers and walking the frame
  pointer chain.
- The main thread's mach port is obtained with `pthread_main_thread_np()`, so
  no startup hook, cached port or main-queue hop is required.
- Addresses are resolved to images and symbols with `dladdr`.

## Limitations

- Only threads in the current process can be inspected.
- Capturing another thread follows frame pointers. Do not build with
  `-fomit-frame-pointer` if you rely on capturing threads other than the
  calling thread.
- Symbol names come from the loaded images. Stripped release builds may only
  provide the image name and an image-relative offset.
- Capture is not async-signal-safe. Do not call it from a signal handler.
- Symbolication walks the loaded images, so avoid calling this from
  performance-sensitive hot paths.
- Capturing a thread that is blocked inside a mach call may produce a short or
  partial stack for the innermost frames.

## Development

```sh
make build    # swift build
make test     # swift test
make demo     # swift run ThreadTraceDemo
make lint     # SwiftLint + swift-format lint
make format   # swift-format, in place
```

SwiftLint can be installed with `brew install swiftlint`; the `swift format`
linter ships with the Swift toolchain. The same checks run in CI on every push
and pull request.

## License

MIT. See [LICENSE](LICENSE).
