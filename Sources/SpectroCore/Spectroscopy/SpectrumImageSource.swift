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
package nonisolated struct SpectrumDetectorSegment: Equatable, Sendable {
    package var name: String
    package var azimuthDegrees: Double?
    package var elevationDegrees: Double?
    /// As stored: sr, whole detector or one segment depending on the file (Velox `CollectionAngle`). A relative weight
    /// among ONE file's segments, never summed to a total.
    package var solidAngle: Double?
    /// Seconds, as stored, semantics unverified.
    package var liveTime: Double?
    package var realTime: Double?

    package init(name: String, azimuthDegrees: Double? = nil, elevationDegrees: Double? = nil,
                 solidAngle: Double? = nil, liveTime: Double? = nil, realTime: Double? = nil) {
        self.name = name; self.azimuthDegrees = azimuthDegrees; self.elevationDegrees = elevationDegrees
        self.solidAngle = solidAngle; self.liveTime = liveTime; self.realTime = realTime
    }
}

package nonisolated enum SpectrumImageOrigin: String, Equatable, Sendable {
    case veloxEMD
    case gmsDM4
}

/// What the shell needs to know about an opened EDX spectrum image. The numbers are the file's own, as read.
package nonisolated struct SpectrumImageMetadata: Equatable, Sendable {
    package var fileName: String
    package var filePath: String
    /// Scan columns × rows of the spectrum image's own grid (M2: the native grid, never resampled onto the 4D scan's).
    package var scanWidth: Int
    package var scanHeight: Int
    /// Energy channels per spectrum.
    package var channelCount: Int
    /// The energy axis as the file states it: E(i) = offset + i · dispersion. Refinement on the pooled spectrum
    /// (ADR 054 item 4) is shown beside it, never written over it.
    package var energyOffsetEV: Double
    package var energyDispersionEV: Double
    /// Real-space pixel size, when the file carries one.
    package var scanPixelSize: Double?
    package var scanPixelUnit: String?

    package var origin: SpectrumImageOrigin?
    /// Frames summed into the counts (Velox); nil when the file has no frame notion (GMS).
    package var frames: Int?
    /// Pixels (from the first) that one more, partial frame also reached (Velox, a stopped acquisition).
    package var partialFramePixels: Int = 0
    package var detectors: [SpectrumDetectorSegment] = []
    package var alphaTiltDegrees: Double?
    package var betaTiltDegrees: Double?
    package var beamEnergyKeV: Double?
    package var instrument: String?
    /// True when this image came from the same GMS file as the 4D cube of the window, under one Experiment ID and on
    /// the same scan grid: registered by identity (WP2 R2). False for everything else, including a mismatch.
    package var sameScanAs4DCube = false
    /// Why a file's EDS object was not registered to the 4D cube beside it, when it was not (shown, never hidden).
    package var registrationNote: String?

    package nonisolated init(
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

    package var pixelCount: Int { scanWidth * scanHeight }
}

/// An opened EDX spectrum image: the counts (`SpectrumImage`), the axis, the metadata, and the scan image on its grid.
package nonisolated protocol SpectrumImageSource: SpectrumImage, AnyObject {
    var metadata: SpectrumImageMetadata { get }
    var energyAxis: EnergyAxis { get }
    /// The HAADF (or best scan) image on the spectrum grid, `ny * nx` row-major, when the file has one.
    var scanImage: [Float]? { get }
}

/// The one concrete source: a `DenseSpectrumImage` or `SparseSpectrumImage` plus what the file said about it.
package nonisolated final class LoadedSpectrumImage: SpectrumImageSource {
    package let image: any SpectrumImage
    package let metadata: SpectrumImageMetadata
    package let energyAxis: EnergyAxis
    package let scanImage: [Float]?

    package init(image: any SpectrumImage, metadata: SpectrumImageMetadata, energyAxis: EnergyAxis, scanImage: [Float]? = nil) {
        precondition(metadata.scanWidth == image.nx && metadata.scanHeight == image.ny && metadata.channelCount == image.channels,
                     "LoadedSpectrumImage: the metadata must describe the image")
        precondition(scanImage == nil || scanImage!.count == image.ny * image.nx, "scanImage must be ny*nx")
        self.image = image; self.metadata = metadata; self.energyAxis = energyAxis; self.scanImage = scanImage
    }

    package var ny: Int { image.ny }
    package var nx: Int { image.nx }
    package var channels: Int { image.channels }
    package func sum(mask: PixelMask?) -> [UInt64] { image.sum(mask: mask) }
    package func windowSums(_ ranges: [Range<Int>]) -> [[UInt64]] { image.windowSums(ranges) }
}
