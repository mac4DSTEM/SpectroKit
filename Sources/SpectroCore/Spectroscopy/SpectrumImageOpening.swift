//
//  SpectrumImageOpening.swift
//  Role: From a file to a `LoadedSpectrumImage`, headless: a Velox EMD (the event store joined to Core's sparse
//        image) or the EDS object of a GMS DM4 (a dense image), plus the cheap question "is this file a spectrum
//        image?" the open path asks before it picks a reader. No AppState, no UI.
//
//  Joining Velox: `VeloxEventStore` conforms to `CSRSpectrumStore` (below) and `SparseSpectrumImage(store)`
//  validates the CSR contract and shares the arrays copy-on-write; nothing is densified.
//

import Foundation

extension VeloxEventStore: CSRSpectrumStore {
    package nonisolated var ny: Int { geometry.ny }
    package nonisolated var nx: Int { geometry.nx }
    package nonisolated var channels: Int { geometry.channels }
}

package nonisolated enum SpectrumImageOpenError: LocalizedError, Equatable {
    case notASpectrumImage(String)
    case noEnergyAxis(String)
    case unsupportedEnergyUnits(String)

    package var errorDescription: String? {
        switch self {
        case .notASpectrumImage(let name): return "\(name) is not an EDX spectrum image."
        case .noEnergyAxis(let name): return "\(name) carries no usable energy axis (offset and a positive dispersion)."
        case .unsupportedEnergyUnits(let units): return "The energy axis is in '\(units)'; only keV and eV are read."
        }
    }
}

/// What a file is, for the open path.
package nonisolated enum SpectrumFileKind: Equatable, Sendable {
    /// A Velox EMD with a spectrum stream: opens as a spectrum image, never as a cube.
    case veloxSpectrumImage
    /// A GMS DM4 with an EDS spectrum image and no diffraction-stack object: opens as a spectrum image.
    case gmsEDSOnly
    /// Everything else, including a GMS file with a diffraction stack (which the app opens as a 4D cube, with its EDS attached after).
    case other
}

package nonisolated enum SpectrumImageOpener {

    /// Header-only for a DM4 (the tag walk seeks past every blob), one HDF5 open for an EMD. Run off the main actor.
    package static func kind(ofFileAt path: String) -> SpectrumFileKind {
        switch URL(fileURLWithPath: path).pathExtension.lowercased() {
        case "emd":
            return VeloxEMDReader.isVeloxEMD(path: path) ? .veloxSpectrumImage : .other
        case "dm4":
            guard let objects = try? DM4Experiment.list(path: path), objects.contains(where: { $0.role == .eds }),
                  !objects.contains(where: { $0.role == .diffraction }) else { return .other }
            return .gmsEDSOnly
        default:
            return .other
        }
    }

    /// Opens a file of a spectrum kind. For `.other` it throws `notASpectrumImage`.
    /// Cancellable (ADR 064 amendment 2 §2): `SpectroCancelled` at a step boundary with nothing kept; `progress` 0...1, ends at 1.
    package static func open(path: String, kind: SpectrumFileKind,
                             cancelled: @Sendable () -> Bool = SpectroCancellation.task,
                             progress: (@Sendable (Double) -> Void)? = nil) throws -> LoadedSpectrumImage {
        try SpectroCancellation.check(cancelled)
        switch kind {
        case .veloxSpectrumImage: return try openVelox(path: path, cancelled: cancelled, progress: progress)
        case .gmsEDSOnly:
            guard let image = try openGMSEDS(path: path, cancelled: cancelled, progress: progress) else {
                throw SpectrumImageOpenError.notASpectrumImage(spectroDisplayFileName(path))
            }
            return image
        case .other: throw SpectrumImageOpenError.notASpectrumImage(spectroDisplayFileName(path))
        }
    }

    // MARK: Velox

    package static func openVelox(path: String, cancelled: @Sendable () -> Bool = SpectroCancellation.task,
                                  progress: (@Sendable (Double) -> Void)? = nil) throws -> LoadedSpectrumImage {
        let name = spectroDisplayFileName(path)
        try SpectroCancellation.check(cancelled)
        progress?(0)
        // The read is the long step (three passes over the stream): its cancel is ours, its progress maps to 0...0.9.
        let readProgress: (@Sendable (Double) -> Void)? = progress.map { p in { @Sendable f in p(f * 0.9) } }
        let v = try VeloxEMDReader(path: path).readSpectrumImage(cancelled: cancelled, progress: readProgress)
        try SpectroCancellation.check(cancelled)
        progress?(0.9)
        let store = v.eventStore
        let image = try SparseSpectrumImage(store)
        try SpectroCancellation.check(cancelled)
        let m = v.metadata
        // The axis the stream's own metadata states; the first analytical segment's, when that is absent.
        let segments0 = v.streams.first?.segments.first ?? m.superXDetectors.first
        let offsetKeV: Double, scaleKeV: Double
        if let a = m.energyAxis {
            offsetKeV = a.offsetKeV; scaleKeV = a.scaleKeV
        } else if let d = segments0?.dispersionEV {
            offsetKeV = (segments0?.offsetEnergyEV ?? 0) / 1000; scaleKeV = d / 1000
        } else {
            throw SpectrumImageOpenError.noEnergyAxis(name)
        }
        guard scaleKeV > 0, scaleKeV.isFinite, offsetKeV.isFinite else { throw SpectrumImageOpenError.noEnergyAxis(name) }
        let axis = EnergyAxis(offset: offsetKeV, scale: scaleKeV, size: store.channels)

        var meta = SpectrumImageMetadata(
            fileName: name, filePath: path, scanWidth: store.nx, scanHeight: store.ny, channelCount: store.channels,
            energyOffsetEV: offsetKeV * 1000, energyDispersionEV: scaleKeV * 1000)
        meta.origin = .veloxEMD
        meta.frames = store.frameRange.count
        meta.partialFramePixels = store.partialFramePixels
        if let size = m.pixelSizeMeters, size.width > 0 {
            meta.scanPixelSize = size.width * 1e9; meta.scanPixelUnit = "nm"   // Velox stores metres
        }
        var seen = Set<String>()
        let segments = v.streams.flatMap(\.segments).isEmpty ? m.superXDetectors : v.streams.flatMap(\.segments)
        meta.detectors = segments.filter { seen.insert($0.name).inserted }.map {
            SpectrumDetectorSegment(name: $0.name, azimuthDegrees: $0.azimuthDegrees, elevationDegrees: $0.elevationDegrees,
                                    solidAngle: $0.solidAngleSteradians, liveTime: $0.liveTimeColumn0, realTime: $0.realTimeColumn0)
        }
        meta.alphaTiltDegrees = m.alphaDegrees
        meta.betaTiltDegrees = m.betaDegrees
        meta.beamEnergyKeV = m.accelerationVoltageVolts.map { $0 / 1000 }
        meta.instrument = m.instrumentModel
        var scan: [Float]?
        if let s = v.scanImage, s.ny == store.ny, s.nx == store.nx { scan = s.sum.map { Float($0) } }
        progress?(1)
        return LoadedSpectrumImage(image: image, metadata: meta, energyAxis: axis, scanImage: scan)
    }

    // MARK: GMS

    /// The EDS spectrum image of a GMS DM4, or nil when the file has none. Pure: it never registers the image to another
    /// object of the file (`sameScanAs4DCube` stays false); a caller that knows one does so from `DM4Experiment.list`
    /// (the app does, in `Core/Data/GMSFourDRegistration.swift`).
    package static func openGMSEDS(path: String,
                                   cancelled: @Sendable () -> Bool = SpectroCancellation.task,
                                   progress: (@Sendable (Double) -> Void)? = nil) throws -> LoadedSpectrumImage? {
        try SpectroCancellation.check(cancelled)
        progress?(0)
        let objects = try DM4Experiment.list(path: path)
        guard let eds = objects.first(where: { $0.role == .eds }) else { return nil }
        let name = spectroDisplayFileName(path)
        try SpectroCancellation.check(cancelled)
        progress?(0.1)
        // The blob read is one call into Core/Data (pass-through only there): cancellation takes effect before and after it.
        let d = try DM4Experiment.readEDSSpectrumImage(path: path, index: eds.index)
        try SpectroCancellation.check(cancelled)
        progress?(0.9)
        let toKeV: Double
        switch d.energyAxis.units.trimmingCharacters(in: .whitespaces).lowercased() {
        case "kev": toKeV = 1
        case "ev": toKeV = 1e-3
        default: throw SpectrumImageOpenError.unsupportedEnergyUnits(d.energyAxis.units)
        }
        // GMS: the value at pixel i is (i - origin) * scale.
        let scaleKeV = d.energyAxis.scale * toKeV
        let offsetKeV = -d.energyAxis.origin * d.energyAxis.scale * toKeV
        guard scaleKeV > 0, scaleKeV.isFinite, offsetKeV.isFinite else { throw SpectrumImageOpenError.noEnergyAxis(name) }
        let axis = EnergyAxis(offset: offsetKeV, scale: scaleKeV, size: d.channels)

        var meta = SpectrumImageMetadata(
            fileName: name, filePath: path, scanWidth: d.nx, scanHeight: d.ny, channelCount: d.channels,
            energyOffsetEV: offsetKeV * 1000, energyDispersionEV: scaleKeV * 1000)
        meta.origin = .gmsDM4
        if let x = eds.axes[0], x.scale > 0, !x.units.isEmpty { meta.scanPixelSize = x.scale; meta.scanPixelUnit = x.units }
        if let t = eds.eds {
            meta.detectors = [SpectrumDetectorSegment(
                name: "EDS", azimuthDegrees: t.azimuthDegrees, elevationDegrees: t.elevationDegrees,
                solidAngle: t.solidAngle, liveTime: t.liveTime, realTime: t.realTime)]
        }
        // DEVIATION from rosettasciio (which reads no beam energy for an EDS object): the object's own Microscope Info voltage;
        // the source is kept for the provenance line. A caller may supply another when the object states none.
        if let b = BeamEnergy.resolve(rawObjectVoltage: eds.voltage, suppliedKV: nil, suppliedAs: .file, sameRun: false) {
            meta.beamEnergyKeV = b.keV; meta.beamEnergySource = b.source
        }
        // The scan-grid HAADF of the same run, when it sits on the EDS grid.
        try SpectroCancellation.check(cancelled)
        var scan: [Float]?
        if let s = objects.first(where: { $0.role == .scanSignal && $0.experimentID == eds.experimentID
            && $0.dimensions.filter { $0 > 1 } == [d.nx, d.ny] }),
           let img = try? DM4Experiment.readImage(path: path, index: s.index), img.width == d.nx, img.height == d.ny {
            scan = img.pixels
        }
        try SpectroCancellation.check(cancelled)
        progress?(1)
        return LoadedSpectrumImage(image: DenseSpectrumImage(ny: d.ny, nx: d.nx, channels: d.channels, counts: d.counts),
                                   metadata: meta, energyAxis: axis, scanImage: scan)
    }
}
