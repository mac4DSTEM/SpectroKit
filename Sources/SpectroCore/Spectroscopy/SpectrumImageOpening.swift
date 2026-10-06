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
    /// A GMS DM4 with an EDS spectrum image and no 4D object: opens as a spectrum image.
    case gmsEDSOnly
    /// Everything else, including a GMS file with a 4D cube (which opens as a cube, with its EDS attached after).
    case other
}

/// The 4D cube a GMS file's EDS object may be registered to.
package nonisolated struct GMSFourDIdentity: Equatable, Sendable {
    /// `ImageList.N` index of the opened 4D object, when known.
    package var objectIndex: Int?
    package var scanWidth: Int
    package var scanHeight: Int
    /// The cube's accelerating voltage in kV (the session's), the beam energy when the EDS object states none.
    package var voltageKV: Double?
    package init(objectIndex: Int?, scanWidth: Int, scanHeight: Int, voltageKV: Double? = nil) {
        self.objectIndex = objectIndex; self.scanWidth = scanWidth; self.scanHeight = scanHeight; self.voltageKV = voltageKV
    }
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
    package static func open(path: String, kind: SpectrumFileKind) throws -> LoadedSpectrumImage {
        switch kind {
        case .veloxSpectrumImage: return try openVelox(path: path)
        case .gmsEDSOnly:
            guard let image = try openGMSEDS(path: path, fourD: nil) else {
                throw SpectrumImageOpenError.notASpectrumImage(displayFileName(path))
            }
            return image
        case .other: throw SpectrumImageOpenError.notASpectrumImage(displayFileName(path))
        }
    }

    // MARK: Velox

    package static func openVelox(path: String) throws -> LoadedSpectrumImage {
        let name = displayFileName(path)
        let v = try VeloxEMDReader(path: path).readSpectrumImage()
        let store = v.eventStore
        let image = try SparseSpectrumImage(store)
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
        return LoadedSpectrumImage(image: image, metadata: meta, energyAxis: axis, scanImage: scan)
    }

    // MARK: GMS

    /// The EDS spectrum image of a GMS DM4, or nil when the file has none. With `fourD`, the image is registered to
    /// that cube BY IDENTITY when both objects carry the same Experiment ID and the EDS grid equals the cube's scan
    /// grid (`sameScanAs4DCube`); otherwise it is still attached, with the reason in `registrationNote`.
    package static func openGMSEDS(path: String, fourD: GMSFourDIdentity?) throws -> LoadedSpectrumImage? {
        let objects = try DM4Experiment.list(path: path)
        guard let eds = objects.first(where: { $0.role == .eds }) else { return nil }
        let name = displayFileName(path)
        let d = try DM4Experiment.readEDSSpectrumImage(path: path, index: eds.index)
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
        if let cube = fourD {
            let object = cube.objectIndex.flatMap { i in objects.first { $0.index == i } }
                ?? objects.first { $0.role == .diffraction }
            if let id = eds.experimentID, id == object?.experimentID, cube.scanWidth == d.nx, cube.scanHeight == d.ny {
                meta.sameScanAs4DCube = true
            } else if cube.scanWidth != d.nx || cube.scanHeight != d.ny {
                meta.registrationNote = "Not registered: the EDS scan is \(d.nx) × \(d.ny) px, the 4D scan \(cube.scanWidth) × \(cube.scanHeight)."
            } else {
                meta.registrationNote = "Not registered: the two objects do not share an Experiment ID."
            }
        }
        // DEVIATION from rosettasciio (which reads no beam energy for an EDS object): the object's own Microscope Info voltage,
        // else the 4D cube's when both are one run; the source is kept for the provenance line.
        if let b = BeamEnergy.resolve(rawObjectVoltage: eds.voltage, cubeKV: fourD?.voltageKV, sameRun: meta.sameScanAs4DCube) {
            meta.beamEnergyKeV = b.keV; meta.beamEnergySource = b.source
        }
        // The scan-grid HAADF of the same run, when it sits on the EDS grid.
        var scan: [Float]?
        if let s = objects.first(where: { $0.role == .scanSignal && $0.experimentID == eds.experimentID
            && $0.dimensions.filter { $0 > 1 } == [d.nx, d.ny] }),
           let img = try? DM4Experiment.readImage(path: path, index: s.index), img.width == d.nx, img.height == d.ny {
            scan = img.pixels
        }
        return LoadedSpectrumImage(image: DenseSpectrumImage(ny: d.ny, nx: d.nx, channels: d.channels, counts: d.counts),
                                   metadata: meta, energyAxis: axis, scanImage: scan)
    }
}
