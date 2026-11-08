// swift-tools-version: 6.0
// StreamenDVR.app — menu-bar host that runs RecorderCore in-process.
// Build the .app bundle with `scripts/build-app.sh`; `swift run` works for development.

import PackageDescription

let package = Package(
    name: "StreamenDVRApp",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "StreamenDVRApp", targets: ["StreamenDVRApp"]),
    ],
    dependencies: [
        .package(name: "StreamenDVR", path: ".."),
        .package(path: "../Kit"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.15.0"),
        .package(url: "https://github.com/swift-server/swift-service-lifecycle.git", from: "2.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "StreamenDVRApp",
            dependencies: [
                .product(name: "RecorderCore", package: "StreamenDVR"),
                .product(name: "StreamenDVRKit", package: "Kit"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "ServiceLifecycle", package: "swift-service-lifecycle"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
