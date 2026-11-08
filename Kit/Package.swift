// swift-tools-version: 6.0
// StreamenDVRKit — the shared wire contract (DTOs + coding) and a tiny async
// client for the StreamenDVR HTTP API. Foundation only: the Streamen app consumes
// this as a local package, so it must never add a dependency to the app graph.

import PackageDescription

let package = Package(
    name: "StreamenDVRKit",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
        .tvOS(.v18),
        .visionOS(.v2),
    ],
    products: [
        .library(name: "StreamenDVRKit", targets: ["StreamenDVRKit"]),
    ],
    targets: [
        .target(
            name: "StreamenDVRKit",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "StreamenDVRKitTests",
            dependencies: ["StreamenDVRKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
