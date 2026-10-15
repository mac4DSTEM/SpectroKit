// swift-tools-version: 6.2
// The README consumer: a SEPARATE package that depends on SpectroKit by path and whose Sources/readme-consumer/main.swift is
// the README's code blocks and nothing else (README.md, the blocks marked <!-- readme-consumer --> and
// <!-- readme-consumer-eels -->; check-readme.py fails when they differ). It proves that a stranger who pastes the README's
// quick start into a package that lists the three products gets a program that compiles in Debug without a warning and prints
// the planted answer. See ../README.md.
import Foundation
import PackageDescription

// A path dependency's identity is its directory's name (lower-cased): "spectrokit" in the repository, but not in a scratch copy.
// `.product` needs that name, so it is taken from the directory three levels above this manifest.
let spectroKit = URL(fileURLWithPath: Context.packageDirectory).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().lastPathComponent

let package = Package(
    name: "ReadmeConsumer",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(path: "../../.."),
    ],
    targets: [
        .executableTarget(name: "readme-consumer", dependencies: [
            .product(name: "SpectroCore", package: spectroKit),
            .product(name: "SpectroEDX", package: spectroKit),
            .product(name: "SpectroEELS", package: spectroKit),
        ]),
    ],
    swiftLanguageModes: [.v6]
)
