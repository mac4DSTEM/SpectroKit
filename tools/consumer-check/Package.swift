// swift-tools-version: 6.2
// SpectroKit consumer check: a SEPARATE package that depends on SpectroKit by path and touches the symbols a consumer reads
// across the package boundary (SpectroEELS, and SpectroCore's spectrum-image opening). `package` access does not cross a
// package boundary, so this compiles only if each of those symbols is `public`. FormatoKit (the file readers, 0.4.0) is
// resolved through SpectroKit only; no FormatoKit product is named here. See README.md.
import Foundation
import PackageDescription

// A path dependency's identity is its directory's name (lower-cased): "spectrokit" in the repository, but not in a scratch copy.
// `.product` needs that name, so it is taken from the directory two levels above this manifest.
let spectroKit = URL(fileURLWithPath: Context.packageDirectory).deletingLastPathComponent().deletingLastPathComponent()
    .lastPathComponent

let package = Package(
    name: "ConsumerCheck",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(path: "../.."),
    ],
    targets: [
        .executableTarget(name: "consumer-check", dependencies: [
            .product(name: "SpectroCore", package: spectroKit),
            .product(name: "SpectroEELS", package: spectroKit),
            .product(name: "SpectroEDX", package: spectroKit),
        ]),
    ],
    swiftLanguageModes: [.v6]
)
