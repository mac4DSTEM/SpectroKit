// swift-tools-version: 6.2
// SpectroKit — the macEM suite's spectroscopy library (a Swift port of exSpy), extracted from mac4DSTEM 5ba712a0.
//
// Two library targets (macTEM ADR 003: "Modules: SpectroCore (the shared part), SpectroEDX (first), SpectroEELS (later)"):
// `SpectroCore` is what EDS and EELS share (the spectrum image, the energy axis, the least-squares and Poisson fits, the
// counting statistics; the Velox and DM4 file readers moved to FormatoKit at 0.4.0); `SpectroEDX` is the X-ray part (lines, the continuum and EDS fit
// models, the element proposer, the quantification method, Cliff-Lorimer, absorption, the k-factor sources) and depends on
// SpectroCore. SpectroCore never depends on SpectroEDX; a future SpectroEELS will depend on SpectroCore only. Swift 6
// language mode, nonisolated by default (no `.defaultIsolation`), as macTEM's TEMCore. The six EPQ / FFAST / Krause tables
// are SpectroEDX's `Bundle.module` resources (`QuantificationTables.bundled()`, bundle `SpectroKit_SpectroEDX`); test
// fixtures are read by `#filePath` and are not resources. What one module needs from the other is `package`, never `public`.
//
// 0.4.0: the file readers (`DM4Experiment`, `VeloxEMDReader`, `HDF5Serial`) live in FormatoKit (the suite's RosettaSciIO port,
// docs/consumers-0.4.0.md), a package dependency pinned to an exact tag so a consumer's `swift build` resolves it alone. FormatoKit
// ships libhdf5 inside FormatoHDF5, so nothing here asks a consumer to supply one.
import PackageDescription

let package = Package(
    name: "SpectroKit",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "SpectroCore", targets: ["SpectroCore"]),
        .library(name: "SpectroEELS", targets: ["SpectroEELS"]),
        .library(name: "SpectroEDX", targets: ["SpectroEDX"]),
    ],
    dependencies: [
        .package(url: "https://github.com/mac4DSTEM/FormatoKit", exact: "0.0.2"),
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
            dependencies: [
                "CSpectroLAPACK",
                .product(name: "FormatoCore", package: "FormatoKit"),
                .product(name: "FormatoDM", package: "FormatoKit"),
                .product(name: "FormatoEMD", package: "FormatoKit"),
            ],
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
        // EELS slice 1 (docs/eels-slice-1-registration.md): the t/λ thickness map, a port of exSpy 7185a4d1's log-ratio
        // method. Depends on SpectroCore only (EnergyAxis's HyperSpy rounding, FitLinearAlgebra's least squares). Slice 2
        // (docs/eels-slice-2-registration.md): the C K edge by the ratio method; the dft GOS of the C, N and O K shells
        // (CC-BY-4.0, NOTICE) are its `Bundle.module` resources (bundle `SpectroKit_SpectroEELS`).
        .target(
            name: "SpectroEELS",
            dependencies: ["SpectroCore"],
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
        // The 258 tests that moved from mac4DSTEM, by name (its docs/archive/v5/spectrokit-test-partition-2026-10-13.md). They
        // stay in one target across the split (the names are the contract), so it depends on both modules. At 0.4.0 the 68 reader
        // tests among them moved to FormatoKit with the readers; the 190 others stay here, by name.
        .testTarget(
            name: "SpectroCoreTests",
            dependencies: [
                "SpectroCore", "SpectroEDX",
                .product(name: "FormatoDM", package: "FormatoKit"), .product(name: "FormatoEMD", package: "FormatoKit"),
            ],
            exclude: ["Fixtures"],
            swiftSettings: [
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
                .enableUpcomingFeature("MemberImportVisibility"),
            ]
        ),
        // SpectroKit's own tests, written after the extraction (0.2.0 on). Since 0.4.0 only the rank-threshold test: the Velox
        // metadata fields, the DM4 EELS reader and the quit barrier moved to FormatoKit with their readers.
        .testTarget(
            name: "SpectroKitTests",
            dependencies: ["SpectroCore"],
            swiftSettings: [
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
                .enableUpcomingFeature("MemberImportVisibility"),
            ]
        ),
        // EELS slice 1's tests: pins against exSpy, truth against planted spectra (Fixtures/, tools/eels-thickness/).
        .testTarget(
            name: "SpectroEELSTests",
            dependencies: ["SpectroEELS", "SpectroCore"],
            exclude: ["Fixtures"],
            swiftSettings: [
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
                .enableUpcomingFeature("MemberImportVisibility"),
            ]
        ),
        // EDX stage gates (docs/edx-stage-gates-registration.md): counts, energy axis and peak identification on pins (exSpy,
        // HyperSpy, RosettaSciIO) and planted truth (Fixtures/, tools/edx-stages/), and the Gate D diagnosis of the Mg auto-ID
        // miss. Its own target (registration Q6), so SpectroCoreTests stays the moved names (190 since 0.4.0).
        .testTarget(
            name: "SpectroEDXTests",
            dependencies: ["SpectroEDX", "SpectroCore", .product(name: "FormatoEMD", package: "FormatoKit")],
            exclude: ["Fixtures"],
            swiftSettings: [
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
                .enableUpcomingFeature("MemberImportVisibility"),
            ]
        ),
        // G-golden: mac4DSTEM's byte-for-byte baseline (recorded at its 71929a01) for the scenarios the library reaches.
        // Its own target so the moved-name count stays exact (190 since 0.4.0).
        .testTarget(
            name: "SpectroGoldenTests",
            dependencies: ["SpectroCore", "SpectroEDX", .product(name: "FormatoEMD", package: "FormatoKit")],
            swiftSettings: [
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
                .enableUpcomingFeature("MemberImportVisibility"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
