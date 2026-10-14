// swift-tools-version: 6.2
// The Swift side of tools/velox-metadata-parity: a throwaway package that depends on SpectroKit BY PATH, so it sees
// only SpectroCore's public API (the six Velox metadata fields must be `public` to compile here, which is the point).
// `../../..` is the SpectroKit root; the dependency's name is taken from that directory, so a renamed or copied
// checkout (run.sh --controls builds against edited copies) resolves too.
import Foundation
import PackageDescription

let rootName = URL(fileURLWithPath: Context.packageDirectory).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().lastPathComponent

let package = Package(
    name: "velox-metadata-parity",
    platforms: [.macOS("27.0")],
    dependencies: [.package(path: "../../..")],
    targets: [
        .executableTarget(
            name: "velox-metadata-dump",
            dependencies: [.product(name: "SpectroCore", package: rootName)],
            path: "Sources/velox-metadata-dump"
        ),
    ],
    swiftLanguageModes: [.v6]
)
