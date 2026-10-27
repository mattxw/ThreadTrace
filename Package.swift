// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ThreadTrace",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
    ],
    products: [
        .library(name: "ThreadTrace", targets: ["ThreadTrace"])
    ],
    targets: [
        .target(name: "ThreadTrace"),
        .executableTarget(
            name: "ThreadTraceDemo",
            dependencies: ["ThreadTrace"],
            path: "Examples/ThreadTraceDemo"
        ),
        .testTarget(
            name: "ThreadTraceTests",
            dependencies: ["ThreadTrace"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
