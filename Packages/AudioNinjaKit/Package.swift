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
    dependencies: [
        // The LAME MP3 encoder (LGPL), prebuilt as a dynamic xcframework. Apple ships an MP3
        // decoder but no encoder. Dynamic is deliberate: LAME stays a separate, replaceable
        // library, which is how LAME's licence asks commercial users to ship it. Pinned exactly
        // so the shipped binary only changes on purpose. See THIRD-PARTY-LICENSES.md.
        .package(url: "https://github.com/BB9z/LAME-xcframework.git", exact: "3.100.3"),
    ],
    targets: [
        .target(
            name: "AudioNinjaKit",
            dependencies: [.product(name: "LAME", package: "LAME-xcframework")]
        ),
        .testTarget(
            name: "AudioNinjaKitTests",
            dependencies: ["AudioNinjaKit"],
            // An MP3 made by another encoder, so decoding is not only ever tested against
            // files this app wrote.
            resources: [.copy("Resources")]
        ),
    ]
)
