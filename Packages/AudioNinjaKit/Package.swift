// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "AudioNinjaKit",
    platforms: [
        .macOS(.v27),
        .iOS(.v27),
    ],
    products: [
        // No third-party code: everything here is built on Apple's frameworks.
        .library(name: "AudioNinjaKit", targets: ["AudioNinjaKit"]),
    ],
    targets: [
        .target(name: "AudioNinjaKit"),
        .testTarget(
            name: "AudioNinjaKitTests",
            dependencies: ["AudioNinjaKit"],
            // An MP3 made with LAME before it was removed. Apple can decode MP3 but not encode it,
            // so the tests cannot make one on the fly.
            resources: [.copy("Resources")]
        ),
    ]
)
