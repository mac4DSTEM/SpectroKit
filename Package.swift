// swift-tools-version: 6.2
// SpectroKit — the macEM suite's spectroscopy library (a Swift port of exSpy), extracted from mac4DSTEM 5ba712a0.
//
// One target for now, `SpectroCore`; the SpectroEDX split comes later. Swift 6 language mode, nonisolated by default
// (no `.defaultIsolation`), as macTEM's TEMCore. The six EPQ / FFAST / Krause tables are `Bundle.module` resources
// (`QuantificationTables.bundled()`); test fixtures are read by `#filePath` and are not resources.
import PackageDescription

let package = Package(
    name: "SpectroKit",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "SpectroCore", targets: ["SpectroCore"]),
    ],
    targets: [
        .target(
            name: "SpectroCore",
            resources: [.copy("Resources/Spectroscopy")],
            swiftSettings: [
                // S2 only, carried from mac4DSTEM's DSTEMCore: `FitLinearAlgebra` needs Accelerate's current LAPACK
                // interface (`__LAPACK_int`), and the Debug build is optimised (Gate D 2026-09-30). `unsafeFlags` make
                // SwiftPM refuse SpectroKit as a versioned dependency; S3 replaces the first with a C shim and decides
                // the second (ADR 064 amendment a). No 0.1.0 tag while either line exists.
                .unsafeFlags(["-Xcc", "-DACCELERATE_NEW_LAPACK"]),
                .unsafeFlags(["-O"], .when(configuration: .debug)),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
                .enableUpcomingFeature("MemberImportVisibility"),
            ]
        ),
        // The 258 tests that moved from mac4DSTEM, by name (its docs/archive/v5/spectrokit-test-partition-2026-10-13.md).
        .testTarget(
            name: "SpectroCoreTests",
            dependencies: ["SpectroCore"],
            exclude: ["Fixtures"],
            swiftSettings: [
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
                .enableUpcomingFeature("MemberImportVisibility"),
            ]
        ),
        // G-golden: mac4DSTEM's byte-for-byte baseline (recorded at its 71929a01) for the scenarios the library reaches.
        // Its own target so the moved-name count stays exactly 258.
        .testTarget(
            name: "SpectroGoldenTests",
            dependencies: ["SpectroCore"],
            swiftSettings: [
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
                .enableUpcomingFeature("MemberImportVisibility"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
