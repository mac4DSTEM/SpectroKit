// Numerical port of mac4DSTEM c809679c, PoolBuilder.swift (GPL-3.0).
import Foundation

/// An exact integer sum of whole spectrum pixels, with overlap diagnostics.
public struct PooledSpectrum: Sendable, Equatable {
    /// "Al", "beta''", "object 7", "Drawn 1" — the region's name.
    public let name: String
    /// `phase`, `object`, `drawn` or `wholeMap`.
    public let kind: String
    /// Summed counts per channel.
    public let counts: [UInt64]
    /// Spectrum pixels summed.
    public let pixelCount: Int
    /// Included pixels the region covers only partly (overlap < 1).
    public let partialPixels: Int
    /// Included pixels whose area reaches outside the 4D scan.
    public let edgePixels: Int
    /// Share of the region (on the 4D side) the spectrum image does not see.
    public let outsideFraction: Double
    /// The region's whole footprint in spectrum-pixel units: compare with `pixelCount` ("12 px of a
    /// 31.5-px footprint"). 0 for a pool from a mask drawn on the spectrum grid.
    public let footprintArea: Double
    /// Region area inside the pooled pixels / region area that landed on the spectrum grid.
    public let retainedFraction: Double
    /// Region area inside the pooled pixels / the pooled pixels' own area: 1 = every pooled pixel is
    /// wholly the region; lower means the pool is diluted by neighbours.
    public let purity: Double
    /// The source product's self-reported validation (`"none"` for a phase map); nil = no source product.
    public let validation: String?
    /// The spectrum-grid mask the pool was summed over (row-major, `true` = in).
    public let mask: PixelMask

    public var totalCounts: UInt64 { counts.reduce(0, &+) }
    public var isUnvalidated: Bool { validation == "none" }
}

/// Builds independent region pools or disjoint class pools.
public enum PoolBuilder {

    /// The badge a pool takes from a phase map: phase mapping self-reports `validation: "none"`.
    public static let phaseMapValidation = "none"

    /// One pool from a mask on the spectrum image's grid (a `TransportedLabels` class, or a mask the
    /// user drew on the spectrum map).
    public static func pool(image: some SpectrumImage, mask: PixelMask, name: String, kind: String,
                             partialPixels: Int = 0, edgePixels: Int = 0, outsideFraction: Double = 0,
                             footprintArea: Double = 0, retainedFraction: Double = 1, purity: Double = 1,
                             validation: String? = nil) throws -> PooledSpectrum {
        guard mask.count == image.ny * image.nx else {
            throw MaskTransportError(description: "Mask must be on the spectrum image grid.")
        }
        return PooledSpectrum(name: name, kind: kind, counts: image.sum(mask: mask),
                              pixelCount: mask.reduce(0) { $0 + ($1 ? 1 : 0) },
                              partialPixels: partialPixels, edgePixels: edgePixels,
                              outsideFraction: outsideFraction, footprintArea: footprintArea,
                              retainedFraction: retainedFraction, purity: purity, validation: validation, mask: mask)
    }

    /// One pool per class of a transported label map (`names[c]` for class c). A registration whose
    /// spectrum grid is not the image's is refused by name.
    public static func pools(image: some SpectrumImage, transported t: TransportedLabels,
                              names: [String], kind: String, validation: String?)
        throws -> [PooledSpectrum] {
        guard t.width == image.nx, t.height == image.ny else {
            throw MaskTransportError(description: "The registration maps onto a \(t.width) x \(t.height) grid; the spectrum image is \(image.nx) x \(image.ny).")
        }
        guard names.count == t.classCount else {
            throw MaskTransportError(description: "\(names.count) names for \(t.classCount) classes.")
        }
        // Phases partition the grid: each pixel goes to one class (`labels`), so no pixel is counted twice
        // — unlike independent per-class half-coverage masks, which a tie could put in two.
        let labels = t.labels
        return try (0..<t.classCount).map { c in
            let mask = labels.map { $0 == c }
            let (_, report) = try MaskTransport.region(t, class: c)
            var partial = 0, edge = 0, retained = 0.0, pixels = 0
            for p in 0..<t.pixelCount where mask[p] {
                pixels += 1; retained += t.overlap[c][p]
                if t.overlap[c][p] < 1 - TransportedLabels.tolerance { partial += 1 }
                if t.insideGrid[p] < 1 - TransportedLabels.tolerance { edge += 1 }
            }
            return try pool(image: image, mask: mask, name: names[c], kind: kind, partialPixels: partial,
                        edgePixels: edge, outsideFraction: report.outsideFraction,
                        footprintArea: report.footprintArea,
                        retainedFraction: report.regionArea > 0 ? retained / report.regionArea : 0,
                        purity: pixels > 0 ? retained / Double(pixels) : 0, validation: validation)
        }
    }

    /// One pool for a region given as a 4D-grid mask (an object's pixels, a drawn rectangle).
    public static func pool(image: some SpectrumImage, scanMask: [Bool], registration: GridRegistration,
                             name: String, kind: String, validation: String? = nil) throws -> PooledSpectrum {
        let t = try MaskTransport.transport(mask: scanMask, registration: registration)
        guard t.width == image.nx, t.height == image.ny else {
            throw MaskTransportError(description: "The registration maps onto a \(t.width) x \(t.height) grid; the spectrum image is \(image.nx) x \(image.ny).")
        }
        let (mask, report) = try MaskTransport.region(t)
        return try pool(image: image, mask: mask, name: name, kind: kind, partialPixels: report.partialIncluded,
                    edgePixels: report.edgeIncluded, outsideFraction: report.outsideFraction,
                    footprintArea: report.footprintArea, retainedFraction: report.retainedFraction,
                    purity: report.purity, validation: validation)
    }
}
