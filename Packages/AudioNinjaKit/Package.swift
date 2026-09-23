// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "AudioNinjaKit",
    platforms: [
        .macOS(.v27),
        .iOS(.v27),
    ],
    products: [
        // Static, so LAME is statically linked into the app. A dynamic product was tried and the app
        // failed to launch without an embed-and-sign phase. That matters for LGPL 2.0 §6 once builds
        // are distributed; THIRD-PARTY-LICENSES.md says what switching to dynamic would take.
        .library(name: "AudioNinjaKit", targets: ["AudioNinjaKit"]),
    ],
    targets: [
        .target(
            name: "AudioNinjaKit",
            dependencies: ["CLame"]
        ),
        // The vendored LAME encoder. See Sources/CLame/VENDOR.txt and scripts/vendor-lame.sh.
        .target(
            name: "CLame",
            exclude: ["LICENSE", "LICENSE.LAME-NOTE", "VENDOR.txt"],
            sources: ["src"],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("."),        // config.h
                .headerSearchPath("include"),  // lame.h, included as "lame.h" from src/*.c
                .define("HAVE_CONFIG_H"),
                // Pinned rather than left to the toolchain default. LAME's sources predate C23's
                // removal of implicit function declarations and old-style definitions, and Clang's
                // default -std has been moving forward release to release (Xcode 27 defaults to
                // gnu17). Pinning makes the build independent of that drift.
                // -w: LAME's sources raise a few dozen warnings under current Clang (negative
                // shifts, fabs on ints, 64-to-32 narrowing). They are upstream's, the sources are
                // kept byte-identical on purpose (THIRD-PARTY-LICENSES.md), and leaving them on
                // buries any warning in this project's own code.
                .unsafeFlags(["-std=gnu11", "-w"]),
            ]
        ),
        .testTarget(
            name: "AudioNinjaKitTests",
            dependencies: ["AudioNinjaKit"]
        ),
    ]
)
