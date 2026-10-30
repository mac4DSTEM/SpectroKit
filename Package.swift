// swift-tools-version: 6.2
// SPDX-License-Identifier: GPL-3.0-only
// SpectroKit: EDS and EELS spectroscopy for the TEM, a Swift port of exSpy.
//
// `SpectroCore` is what EDS and EELS share (the spectrum image, the energy axis, the least-squares and Poisson fits, the counting
// statistics); `SpectroEDX` (X-ray lines, the EDS fit, the element proposer, quantification, absorption) and `SpectroEELS`
// (thickness, alignment, deconvolution, core-loss edges) each depend on SpectroCore and never on each other. What one module needs
// from another is `package`, never `public`. Swift 6 language mode, nonisolated by default. The EDX tables and the EELS GOS tables
// are `Bundle.module` resources; test fixtures are read by `#filePath` and are not resources.
//
// The file readers are FormatoKit's (a Swift port of RosettaSciIO), on a minor range so a consumer's `swift build` resolves it alone;
// FormatoKit ships libhdf5 as binary xcframeworks, so nothing here asks a consumer to supply one.
import PackageDescription

let package = Package(
    name: "SpectroKit",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "SpectroCore", targets: ["SpectroCore"]),
        .library(name: "SpectroEELS", targets: ["SpectroEELS"]),
        .library(name: "SpectroEDX", targets: ["SpectroEDX"]),
    ],
    dependencies: [
        .package(url: "https://github.com/mac4DSTEM/FormatoKit", "0.4.0"..<"1.0.0"),
        // SpectroEELS runs its Fourier deconvolutions on ImagoCore's exact-length FFT; 0.6.1 is the first tag with it.
        .package(url: "https://github.com/mac4DSTEM/ImagoKit", "0.6.1"..<"1.0.0"),
    ],
    targets: [
        // Plain-C wrappers over the four Accelerate LAPACK routines `FitLinearAlgebra` calls. ACCELERATE_NEW_LAPACK is
        // defined for this C target only (a `cSettings` define, which SwiftPM accepts in a versioned dependency); its public
        // header includes no Accelerate, so the manifest needs no unsafe flag.
        .target(
            name: "CSpectroLAPACK",
            cSettings: [.define("ACCELERATE_NEW_LAPACK")],
            linkerSettings: [.linkedFramework("Accelerate")]
        ),
        .target(
            name: "SpectroCore",
            dependencies: [
                "CSpectroLAPACK",
                .product(name: "FormatoCore", package: "FormatoKit"),
                .product(name: "FormatoDM", package: "FormatoKit"),
                .product(name: "FormatoEMD", package: "FormatoKit"),
            ],
            // No Debug `-O`: a versioned dependency cannot carry unsafe flags. Debug at -Onone is 20-50x slower on the hot paths
            // (a 936 MB Velox file 24.5 s against 1.05 s, the proposer 956 s against 19.8 s), so optimising is the consumer's
            // choice; tools/test.sh runs the tests with `-c release`.
            swiftSettings: [
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
                .enableUpcomingFeature("MemberImportVisibility"),
            ]
        ),
        // EELS: thickness, alignment, deconvolution and core-loss edges, ported from exSpy 7185a4d1. The dft GOS tables (CC BY 4.0,
        // NOTICE) are its `Bundle.module` resources (bundle `SpectroKit_SpectroEELS`).
        .target(
            name: "SpectroEELS",
            dependencies: ["SpectroCore", .product(name: "ImagoCore", package: "ImagoKit")],
            resources: [.copy("Resources/GOS")],
            swiftSettings: [
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
                .enableUpcomingFeature("MemberImportVisibility"),
            ]
        ),
        // The X-ray half: SpectroCore plus the EDX-specific machinery. Calls only SpectroCore (not the C target) and carries the
        // six quantification tables as resources.
        .target(
            name: "SpectroEDX",
            dependencies: ["SpectroCore"],
            resources: [.copy("Resources/Spectroscopy")],
            swiftSettings: [
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
                .enableUpcomingFeature("MemberImportVisibility"),
            ]
        ),
        // The tests that came with the extraction from mac4DSTEM, most of them on SpectroEDX (issue #32 splits them by module).
        .testTarget(
            name: "SpectroCoreTests",
            dependencies: [
                "SpectroCore", "SpectroEDX", "SpectroTestSupport",
                .product(name: "FormatoDM", package: "FormatoKit"), .product(name: "FormatoEMD", package: "FormatoKit"),
            ],
            exclude: ["Fixtures"],
            swiftSettings: [
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
                .enableUpcomingFeature("MemberImportVisibility"),
            ]
        ),
        // Small package-wide tests: the CI scripts, the rank threshold, the smoothing kernel.
        .testTarget(
            name: "SpectroKitTests",
            dependencies: ["SpectroCore", "SpectroTestSupport"],
            swiftSettings: [
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
                .enableUpcomingFeature("MemberImportVisibility"),
            ]
        ),
        // SpectroEELS: pins against exSpy, truth against planted spectra (Fixtures/, written by tools/).
        .testTarget(
            name: "SpectroEELSTests",
            dependencies: ["SpectroEELS", "SpectroCore", "SpectroTestSupport"],
            exclude: ["Fixtures"],
            swiftSettings: [
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
                .enableUpcomingFeature("MemberImportVisibility"),
            ]
        ),
        // SpectroEDX: counts, energy axis and peak identification on pins (exSpy, HyperSpy, RosettaSciIO) and planted truth (Fixtures/).
        .testTarget(
            name: "SpectroEDXTests",
            dependencies: ["SpectroEDX", "SpectroCore", "SpectroTestSupport", .product(name: "FormatoEMD", package: "FormatoKit")],
            exclude: ["Fixtures"],
            swiftSettings: [
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
                .enableUpcomingFeature("MemberImportVisibility"),
            ]
        ),
        // Helpers and fixture loaders the fast and the parity targets share (EDXFixtures, EELSFixtures, PlantedRuns, SeededPoisson,
        // isEqual). `package` access; the fixtures stay beside the target that owns them (FixtureDirs).
        .target(
            name: "SpectroTestSupport",
            dependencies: ["SpectroCore", "SpectroEDX", "SpectroEELS"],
            path: "Tests/SpectroTestSupport",
            swiftSettings: [
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
                .enableUpcomingFeature("MemberImportVisibility"),
            ]
        ),
        // The pinned comparisons: the byte-for-byte golden baseline, the exSpy, HyperSpy and pyEELSMODEL pins and the minute-long
        // planted EDX runs. `swift test -c release --parallel
        // --skip SpectroKitParityTests` is the per-session gate; the plain `swift test -c release --parallel` runs both.
        .testTarget(
            name: "SpectroKitParityTests",
            dependencies: [
                "SpectroCore", "SpectroEDX", "SpectroEELS", "SpectroTestSupport",
                .product(name: "FormatoEMD", package: "FormatoKit"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
                .enableUpcomingFeature("MemberImportVisibility"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
