// swift-tools-version: 6.2
// SpectroKit consumer check: a SEPARATE package that depends on SpectroKit by path and touches every symbol macTEM reads
// across the package boundary (macTEM's asks of 2026-10-13/14, SpectroKit 0.2.0). `package` access does not cross a package
// boundary, so this compiles only if each of those symbols is `public`. See README.md.
import Foundation
import PackageDescription

// A path dependency's identity is its directory's name (lower-cased): "spectrokit" in the repository, but not in a scratch copy.
// `.product` needs that name, so it is taken from the directory two levels above this manifest.
let spectroKit = URL(fileURLWithPath: Context.packageDirectory).deletingLastPathComponent().deletingLastPathComponent()
    .lastPathComponent

let package = Package(
    name: "ConsumerCheck",
    platforms: [.macOS("27.0")],
    dependencies: [
        .package(path: "../.."),
    ],
    targets: [
        .executableTarget(name: "consumer-check", dependencies: [.product(name: "SpectroCore", package: spectroKit)]),
    ],
    swiftLanguageModes: [.v6]
)
