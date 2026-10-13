//
//  SpectrumImageSource.swift
//  Role: One opened EDX spectrum image as the app holds it: its counts (`SpectrumImage`, dense or sparse),
//        its energy axis, the HAADF on its grid when the file has one, and what the file says about itself.
//        v5.0 WP2 R2 merged the session's old opaque `SpectrumImageSource` onto Core's `SpectrumImage`, so ONE
//        protocol carries dimensions, axis, metadata and the compute (decision of lane R, taken by R2).
//
//  The metadata is the file's own, as read. Live and real times are stored as recorded and are NOT interpreted:
//  their meaning differs by file (cumulative in one Velox file, per frame in another, 0 on the owner's:
//  formats.md §2.2), so nothing computes with them.
//

import Foundation

/// One analytical (X-ray) detector segment as the file records it. Every value is optional: a file writes what it writes.
public nonisolated struct SpectrumDetectorSegment: Equatable, Sendable {
    public var name: String
    public var azimuthDegrees: Double?
    public var elevationDegrees: Double?
    /// As stored: sr, whole detector or one segment depending on the file (Velox `CollectionAngle`). A relative weight
    /// among ONE file's segments, never summed to a total.
    public var solidAngle: Double?
    /// Seconds, as stored, semantics unverified.
    public var liveTime: Double?
    public var realTime: Double?

    package init(name: String, azimuthDegrees: Double? = nil, elevationDegrees: Double? = nil,
                 solidAngle: Double? = nil, liveTime: Double? = nil, realTime: Double? = nil) {
        self.name = name; self.azimuthDegrees = azimuthDegrees; self.elevationDegrees = elevationDegrees
        self.solidAngle = solidAngle; self.liveTime = liveTime; self.realTime = realTime
    }
}

public nonisolated enum SpectrumImageOrigin: String, Equatable, Sendable {
    case veloxEMD
    case gmsDM4
}

/// What the shell needs to know about an opened EDX spectrum image. The numbers are the file's own, as read.
public nonisolated struct SpectrumImageMetadata: Equatable, Sendable {
    public var fileName: String
    public var filePath: String
    /// Scan columns × rows of the spectrum image's own grid (M2: the native grid, never resampled onto the 4D scan's).
    public var scanWidth: Int
    public var scanHeight: Int
    /// Energy channels per spectrum.
    public var channelCount: Int
    /// The energy axis as the file states it: E(i) = offset + i · dispersion. Refinement on the pooled spectrum
    /// (ADR 054 item 4) is shown beside it, never written over it.
    public var energyOffsetEV: Double
    public var energyDispersionEV: Double
    /// Real-space pixel size, when the file carries one.
    public var scanPixelSize: Double?
    public var scanPixelUnit: String?

    public var origin: SpectrumImageOrigin?
    /// Frames summed into the counts (Velox); nil when the file has no frame notion (GMS).
    public var frames: Int?
    /// Pixels (from the first) that one more, partial frame also reached (Velox, a stopped acquisition).
    package var partialFramePixels: Int = 0
    public var detectors: [SpectrumDetectorSegment] = []
    public var alphaTiltDegrees: Double?
    public var betaTiltDegrees: Double?
    public var beamEnergyKeV: Double?
    /// Where `beamEnergyKeV` came from; said on the quantification's provenance line.
    public var beamEnergySource: BeamEnergySource = .file
    public var instrument: String?
    /// True when the caller registered this image by identity to another object of the same file (same Experiment ID, same
    /// scan grid; WP2 R2). The file read never sets it; false for everything else, including a mismatch.
    /// The stored name (and `registrationNote`'s position) is pinned by the S0 golden baseline, which dumps this struct by
    /// reflection; rename both at the freeze commit together with a re-baseline (SpectroKit plan, E5).
    public var sameScanAs4DCube = false
    /// Why the image was not registered to the object beside it, when the caller tried and it was not (shown, never hidden).
    public var registrationNote: String?

    public nonisolated init(
        fileName: String, filePath: String, scanWidth: Int, scanHeight: Int,
        channelCount: Int, energyOffsetEV: Double, energyDispersionEV: Double,
        scanPixelSize: Double? = nil, scanPixelUnit: String? = nil
    ) {
        self.fileName = fileName
        self.filePath = filePath
        self.scanWidth = scanWidth
        self.scanHeight = scanHeight
        self.channelCount = channelCount
        self.energyOffsetEV = energyOffsetEV
        self.energyDispersionEV = energyDispersionEV
        self.scanPixelSize = scanPixelSize
        self.scanPixelUnit = scanPixelUnit
    }

    public var pixelCount: Int { scanWidth * scanHeight }
}

/// An opened EDX spectrum image: the counts (`SpectrumImage`), the axis, the metadata, and the scan image on its grid.
public nonisolated protocol SpectrumImageSource: SpectrumImage, AnyObject {
    var metadata: SpectrumImageMetadata { get }
    var energyAxis: EnergyAxis { get }
    /// The HAADF (or best scan) image on the spectrum grid, `ny * nx` row-major, when the file has one.
    var scanImage: [Float]? { get }
}

/// The one concrete source: a `DenseSpectrumImage` or `SparseSpectrumImage` plus what the file said about it.
public nonisolated final class LoadedSpectrumImage: SpectrumImageSource {
    public let image: any SpectrumImage
    public let metadata: SpectrumImageMetadata
    public let energyAxis: EnergyAxis
    public let scanImage: [Float]?

    public init(image: any SpectrumImage, metadata: SpectrumImageMetadata, energyAxis: EnergyAxis, scanImage: [Float]? = nil) {
        precondition(metadata.scanWidth == image.nx && metadata.scanHeight == image.ny && metadata.channelCount == image.channels,
                     "LoadedSpectrumImage: the metadata must describe the image")
        precondition(scanImage == nil || scanImage!.count == image.ny * image.nx, "scanImage must be ny*nx")
        self.image = image; self.metadata = metadata; self.energyAxis = energyAxis; self.scanImage = scanImage
    }

    public var ny: Int { image.ny }
    public var nx: Int { image.nx }
    public var channels: Int { image.channels }
    public func sum(mask: PixelMask?) -> [UInt64] { image.sum(mask: mask) }
    public func windowSums(_ ranges: [Range<Int>]) -> [[UInt64]] { image.windowSums(ranges) }
    public func sum(mask: PixelMask?, cancelled: @Sendable () -> Bool = SpectroCancellation.task,
                     progress: (@Sendable (Double) -> Void)? = nil) throws -> [UInt64] {
        try image.sum(mask: mask, cancelled: cancelled, progress: progress)
    }
    public func windowSums(_ ranges: [Range<Int>], cancelled: @Sendable () -> Bool = SpectroCancellation.task,
                            progress: (@Sendable (Double) -> Void)? = nil) throws -> [[UInt64]] {
        try image.windowSums(ranges, cancelled: cancelled, progress: progress)
    }
}

/// Where a beam energy came from. The phrase is what the provenance line says after the value.
public nonisolated enum BeamEnergySource: Sendable, Equatable {
    /// The spectrum image's own metadata (a Velox file; the EDS object's Microscope Info in a GMS file).
    case file
    /// Typed in the Quantify inspector; it overrides every other.
    case typed
    /// Supplied by the caller when the file states none; `label` completes "from ...". The app's 4D cube is one
    /// (`BeamEnergySource.fourDCube`, defined in the app layer).
    case supplied(label: String)

    public var phrase: String {
        switch self {
        case .file: "from the file"
        case .typed: "typed"
        case .supplied(let label): "from \(label)"
        }
    }
}

/// Copy of `AcceleratingVoltage.kilovolts(fromAttribute:)` (Core/Data/FourDDataSource.swift) so the spectroscopy code needs
/// nothing from the 4D layer; keep the two in step (SpectroKit S1, plan E1). Values above 1000 are read as volts.
private nonisolated func spectroKilovolts(fromStored raw: Double) -> Double {
    raw > 1_000 ? raw / 1_000 : raw
}

public nonisolated enum BeamEnergy {
    /// The EDS object's own voltage first (`rawObjectVoltage` as stored: volts in GMS), else a supplied voltage in kV
    /// (`suppliedAs` names where it came from), counting only when it belongs to the same run (`sameRun`). Nil when neither is usable.
    public static func resolve(rawObjectVoltage: Double?, suppliedKV: Double?, suppliedAs: BeamEnergySource,
                                sameRun: Bool) -> (keV: Double, source: BeamEnergySource)? {
        if let raw = rawObjectVoltage {
            let kv = spectroKilovolts(fromStored: raw)
            if kv.isFinite, kv > 0 { return (kv, .file) }
        }
        if sameRun, let kv = suppliedKV, kv.isFinite, kv > 0 { return (kv, suppliedAs) }
        return nil
    }

    /// "beam 200 kV · from the 4D cube, same run": the value the fit used and where it came from; a typed value wins.
    package static func provenance(typedKeV: Double?, metadata: SpectrumImageMetadata) -> String? {
        if let t = typedKeV, t > 0 { return "beam \(String(format: "%g", t)) kV \u{00B7} \(BeamEnergySource.typed.phrase)" }
        guard let b = metadata.beamEnergyKeV, b > 0 else { return nil }
        return "beam \(String(format: "%g", b)) kV \u{00B7} \(metadata.beamEnergySource.phrase)"
    }
}
