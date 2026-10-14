// swift-tools-version: 6.2
// SpectroKit's real-data check of EELS slice 1 (docs/eels-real-data-check-registration.md): a SEPARATE package that depends on
// SpectroKit by path and reads the owner's EELS scans from $MACEM_DATA through the public API only. It writes numbers, never
// spectra; the logs go under docs/eels-real-data/. Not part of the gate (tools/test.sh); see README.md.
import Foundation
import PackageDescription

// A path dependency's identity is its directory's name; taken from two levels above this manifest (as tools/consumer-check).
let spectroKit = URL(fileURLWithPath: Context.packageDirectory).deletingLastPathComponent().deletingLastPathComponent()
    .lastPathComponent

let package = Package(
    name: "EELSRealData",
    platforms: [.macOS("27.0")],
    dependencies: [.package(path: "../..")],
    targets: [
        .executableTarget(name: "eels-real-data", dependencies: [
            .product(name: "SpectroCore", package: spectroKit),
            .product(name: "SpectroEELS", package: spectroKit),
        ]),
    ],
    swiftLanguageModes: [.v6]
)
