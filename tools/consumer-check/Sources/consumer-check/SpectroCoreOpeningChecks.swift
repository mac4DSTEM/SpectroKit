//
//  SpectroCoreOpeningChecks.swift
//  Role: SpectroCore's spectrum-image opening used from outside the package, since 0.4.0 through FormatoKit: the file readers
//        moved there, and FormatoKit ships its own libhdf5, so a Debug consumer that sets nothing up must still open a Velox
//        EMD. Only SpectroCore's public API is named (`SpectrumImageOpener.kind(ofFileAt:)`, `.open(path:kind:cancelled:)`,
//        `.openGMSEDS(path:)`, `LoadedSpectrumImage`, `EnergyAxis`, `SpectrumImageMetadata`, `SpectroCancelled`); no FormatoKit
//        type is named. Expected values are those SpectroKit's own tests assert for the same two fixtures
//        (SpectrumImageOpeningTests+Spectro.swift; spectro-golden/velox-tiny.txt and demo-edx-tiny-dm4.txt).
//

import Foundation
import Synchronization
import SpectroCore

/// Answers false `limit` times, then true: the Nth question of a long call is where the call is cancelled.
private final class CancelAfter: Sendable {
    private let asked = Mutex(0)
    let limit: Int
    init(_ limit: Int) { self.limit = limit }
    func cancelled() -> Bool { asked.withLock { $0 += 1; return $0 > limit } }
}

func spectroCoreOpeningChecks(_ r: inout Report, _ dir: URL) throws {
    let velox = dir.appendingPathComponent("velox-tiny.emd").path
    let dm4 = dir.appendingPathComponent("demo-edx-tiny.dm4").path

    // Routing (Velox: one HDF5 open through FormatoKit's shipped libhdf5; DM4: header only).
    r.check("kind(velox-tiny.emd) is .veloxSpectrumImage", SpectrumImageOpener.kind(ofFileAt: velox) == .veloxSpectrumImage)
    r.check("kind(demo-edx-tiny.dm4) is .other (it has a Diffraction SI: a cube opens, its EDS is attached after)",
            SpectrumImageOpener.kind(ofFileAt: dm4) == .other)
    r.check("kind of a path that is neither is .other", SpectrumImageOpener.kind(ofFileAt: dir.appendingPathComponent("nothing.txt").path) == .other)

    // Velox: velox-tiny.emd is 3 rows x 2 columns, 8 channels, 2 frames; 11 counts in all.
    let v = try SpectrumImageOpener.open(path: velox, kind: .veloxSpectrumImage)
    r.equal("Velox [ny, nx, channels]", [v.ny, v.nx, v.channels], [3, 2, 8])
    r.equal("Velox total counts", v.sum(mask: nil).reduce(0, +), UInt64(11))
    r.equal("Velox summed spectrum", v.sum(mask: nil), [1, 3, 1, 2, 1, 1, 0, 2] as [UInt64])
    func pixel(_ p: Int) -> [UInt64] { v.sum(mask: (0..<6).map { $0 == p }) }
    r.equal("Velox pixel 0 spectrum", pixel(0), [0, 3, 0, 0, 0, 0, 0, 0] as [UInt64])
    r.equal("Velox pixel 1 spectrum", pixel(1), [0, 0, 0, 2, 0, 0, 0, 0] as [UInt64])
    r.equal("Velox pixel 2 spectrum", pixel(2), [0, 0, 1, 0, 0, 1, 0, 0] as [UInt64])
    r.equal("Velox pixel 4 spectrum (no counts)", pixel(4), [UInt64](repeating: 0, count: 8))
    r.equal("Velox pixel 5 spectrum", pixel(5), [1, 0, 0, 0, 0, 0, 0, 2] as [UInt64])
    r.equal("Velox energy axis offset (keV)", v.energyAxis.offset, -0.25)
    r.near("Velox energy axis scale (keV)", v.energyAxis.scale, 0.01, 1e-15)
    r.equal("Velox energy axis size", v.energyAxis.size, 8)
    r.near("Velox energy of channel 5 (keV)", v.energyAxis.energy(ofChannel: 5), -0.2, 1e-12)
    let vm = v.metadata
    r.equal("Velox metadata scan [width, height, channels]", [vm.scanWidth, vm.scanHeight, vm.channelCount], [2, 3, 8])
    r.check("Velox metadata origin is .veloxEMD", vm.origin == .veloxEMD)
    r.equal("Velox metadata frames", vm.frames, 2)
    r.equal("Velox metadata beam energy (keV)", vm.beamEnergyKeV, 200)
    r.equal("Velox metadata scan pixel", [vm.scanPixelSize.map { String($0) }, vm.scanPixelUnit], ["1.0", "nm"])
    r.equal("Velox detector names", vm.detectors.map(\.name), ["SuperXG21", "SuperXG22"])
    r.near("Velox detector 0 solid angle", vm.detectors.first?.solidAngle, 0.225, 1e-15)
    r.equal("Velox scan image (the HAADF sum, per pixel)", v.scanImage, [11, 22, 33, 44, 55, 66] as [Float])

    // GMS DM4: demo-edx-tiny.dm4 is 6 x 4, 512 channels, 706 EDS counts (the truth file's totals_written.eds_counts).
    let g = try need(SpectrumImageOpener.openGMSEDS(path: dm4), "openGMSEDS found no EDS object")
    r.equal("DM4 [nx, ny, channels]", [g.nx, g.ny, g.channels], [6, 4, 512])
    r.equal("DM4 total EDS counts", g.sum(mask: nil).reduce(0, +), UInt64(706))
    r.near("DM4 energy axis offset (keV)", g.energyAxis.offset, -0.48895599811115176, 1e-12)
    r.near("DM4 energy axis scale (keV)", g.energyAxis.scale, 0.020039999857544899, 1e-12)
    r.equal("DM4 energy axis size", g.energyAxis.size, 512)
    let gm = g.metadata
    r.check("DM4 metadata origin is .gmsDM4", gm.origin == .gmsDM4)
    r.equal("DM4 metadata beam energy (keV)", gm.beamEnergyKeV, 200)
    r.equal("DM4 metadata scan pixel", [gm.scanPixelSize.map { String($0) }, gm.scanPixelUnit], ["5.0", "nm"])
    r.equal("DM4 metadata detector", gm.detectors.map(\.name), ["EDS"])
    r.equal("DM4 scan image has one value per scan pixel", g.scanImage?.count, 24)
    let viaOpen = try SpectrumImageOpener.open(path: dm4, kind: .gmsEDSOnly)
    r.equal("open(kind: .gmsEDSOnly) equals openGMSEDS", viaOpen.sum(mask: nil), g.sum(mask: nil))
    r.equal("open(kind: .gmsEDSOnly) axis equals openGMSEDS", viaOpen.energyAxis, g.energyAxis)

    // A kind that is not a spectrum image is refused by the public error.
    do {
        _ = try SpectrumImageOpener.open(path: dm4, kind: .other)
        r.check("open(kind: .other) throws", false)
    } catch let e as SpectrumImageOpenError {
        r.check("open(kind: .other) throws notASpectrumImage", e == .notASpectrumImage("demo-edx-tiny.dm4"), "\(e)")
    }

    // Cancellation: the error is FormatoKit's, SpectroCore's `SpectroCancelled` names it, so one `catch is` serves both kits.
    for (label, path, kind) in [("Velox", velox, SpectrumFileKind.veloxSpectrumImage), ("DM4", dm4, .gmsEDSOnly)] {
        for limit in [0, 3] {
            let counter = CancelAfter(limit)
            do {
                _ = try SpectrumImageOpener.open(path: path, kind: kind, cancelled: { counter.cancelled() })
                r.check("\(label) open cancelled after \(limit) questions throws", false, "it returned an image")
            } catch is SpectroCancelled {
                r.check("\(label) open cancelled after \(limit) questions throws SpectroCancelled", true)
            } catch {
                r.check("\(label) open cancelled after \(limit) questions throws SpectroCancelled", false, "threw \(error)")
            }
        }
    }
    do {
        _ = try SpectrumImageOpener.open(path: velox, kind: .veloxSpectrumImage, cancelled: { true })
    } catch let e as SpectroCancelled {
        r.check("SpectroCancelled is Equatable and has a public init", e == SpectroCancelled())
    }
}

private func need<T>(_ value: T?, _ message: String) throws -> T {
    guard let value else { throw CheckError(message) }
    return value
}
