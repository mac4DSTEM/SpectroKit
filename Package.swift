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
        // Plain-C wrappers over the four Accelerate LAPACK routines `FitLinearAlgebra` calls. ACCELERATE_NEW_LAPACK is
        // defined for this C target only (a `cSettings` define, which SwiftPM accepts in a versioned dependency); its public
        // header includes no Accelerate. This replaces S2's `-Xcc -DACCELERATE_NEW_LAPACK` unsafe flag (ADR 064
        // amendment a): no unsafe flags anywhere in this manifest.
        .target(
            name: "CSpectroLAPACK",
            cSettings: [.define("ACCELERATE_NEW_LAPACK")],
            linkerSettings: [.linkedFramework("Accelerate")]
        ),
        .target(
            name: "SpectroCore",
            dependencies: ["CSpectroLAPACK"],
            resources: [.copy("Resources/Spectroscopy")],
            // No Debug `-O` (S2 carried mac4DSTEM's unsafe `-O` flag for the Debug configuration). Measured in S3:
            // Debug at -Onone is 20-50x slower on every hot path (936 MB Velox 24.5 s vs 1.05 s, proposer 956 s vs 19.8 s),
            // and `@_optimize(speed)` does not help at -Onone, but a versioned dependency cannot carry unsafe flags. So the
            // optimisation is the consumer's: tools/test.sh runs this package's tests with `-c release`.
            swiftSettings: [
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
        // SpectroKit's own tests, written after the extraction (0.2.0 on): the six new Velox metadata fields (macTEM's five
        // and StemMagnification) and the bounded quit barrier. Their own target, as the golden's, so SpectroCoreTests stays
        // the 258 moved names.
        .testTarget(
            name: "SpectroKitTests",
            dependencies: ["SpectroCore", "SpectroHDF5ExitProbe"],
            swiftSettings: [
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
                .enableUpcomingFeature("MemberImportVisibility"),
            ]
        ),
        // A child process for the quit-barrier tests: `exit` runs the atexit handlers, which a test cannot watch from
        // inside its own process. Not a product; SpectroKitTests depends on it only so `swift test` builds it.
        .executableTarget(
            name: "SpectroHDF5ExitProbe",
            dependencies: ["SpectroCore"],
            path: "Tests/SpectroHDF5ExitProbe",
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
