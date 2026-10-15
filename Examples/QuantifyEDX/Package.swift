// swift-tools-version: 6.2
// QuantifyEDX: SpectroKit's first example, a SEPARATE package (the library's manifest knows nothing of it, and a package that
// depends on SpectroKit never builds it). It depends on the repository by path, two levels up.
//
//     cd Examples/QuantifyEDX
//     swift run -c release QuantifyEDX                  # a planted Mg, Al, Si spectrum it builds itself
//     swift run -c release QuantifyEDX path/to/file.emd # a Velox EDS spectrum image (or a GMS .dm4), all pixels summed
//
// Release matters: Debug is 20-50x slower on the fit (see the README).
import Foundation
import PackageDescription

// A path dependency's identity is its directory's name (lower-cased): "spectrokit" in a clone, but not in a copy under another
// name. `.product` needs that name, so it is taken from the directory two levels above this manifest.
let spectroKit = URL(fileURLWithPath: Context.packageDirectory).deletingLastPathComponent().deletingLastPathComponent()
    .lastPathComponent

let package = Package(
    name: "QuantifyEDX",
    platforms: [.macOS("27.0")],
    dependencies: [
        .package(path: "../.."),
    ],
    targets: [
        .executableTarget(name: "QuantifyEDX", dependencies: [
            .product(name: "SpectroCore", package: spectroKit),
            .product(name: "SpectroEDX", package: spectroKit),
        ]),
    ],
    swiftLanguageModes: [.v6]
)
