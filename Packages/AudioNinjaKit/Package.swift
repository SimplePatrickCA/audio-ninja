// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "AudioNinjaKit",
    platforms: [
        .macOS(.v27),
        .iOS(.v27),
    ],
    products: [
        .library(name: "AudioNinjaKit", targets: ["AudioNinjaKit"]),
    ],
    targets: [
        .target(name: "AudioNinjaKit"),
        .testTarget(
            name: "AudioNinjaKitTests",
            dependencies: ["AudioNinjaKit"]
        ),
    ]
)
