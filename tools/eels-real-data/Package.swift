// swift-tools-version: 6.2
// SpectroKit's real-data check of EELS slice 1 (docs/eels-real-data-check-registration.md): a SEPARATE package that depends on
// SpectroKit by path and reads EELS scans from a data folder the caller names through the public API only. It writes numbers, never
// spectra; the logs go under docs/eels-real-data/. Not part of the gate (tools/test.sh); see README.md.
import Foundation
import PackageDescription

// A path dependency's identity is its directory's name; taken from two levels above this manifest (as tools/consumer-check).
let spectroKit = URL(fileURLWithPath: Context.packageDirectory).deletingLastPathComponent().deletingLastPathComponent()
    .lastPathComponent

let package = Package(
    name: "EELSRealData",
    platforms: [.macOS("27.0")],
    // FormatoKit (the DM4 reader since SpectroKit 0.4.0) at the tag SpectroKit pins.
    dependencies: [.package(path: "../.."), .package(url: "https://github.com/mac4DSTEM/FormatoKit", exact: "0.0.3")],
    targets: [
        .executableTarget(name: "eels-real-data", dependencies: [
            .product(name: "SpectroCore", package: spectroKit),
            .product(name: "SpectroEELS", package: spectroKit),
            .product(name: "FormatoDM", package: "FormatoKit"),
        ]),
    ],
    swiftLanguageModes: [.v6]
)
