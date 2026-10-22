// Numerical port of mac4DSTEM c809679c, MaskTransport.swift (GPL-3.0).
// App phase-map adapters and provenance remain with the consumer.
import Foundation

/// A refused registration, label map, or pooling request.
public struct MaskTransportError: Error, Equatable, CustomStringConvertible, Sendable {
    public let description: String
}

/// The overlap of every spectrum pixel with each class of a 4D-grid label map.
/// Read-only area overlaps and membership on the target spectrum grid.
public struct TransportedLabels: Sendable, Equatable {
    public let width: Int
    public let height: Int
    public let classCount: Int
    /// `overlap[class][pixel]`: area of the spectrum pixel (1 = the whole pixel) covered by that class
    /// of the 4D map. Row-major pixels.
    public let overlap: [[Double]]
    /// Area of each spectrum pixel that lies inside the 4D grid (1 = fully inside).
    public let insideGrid: [Double]
    /// Per class: the area of the class's 4D footprint in spectrum-pixel units, and how much of it
    /// fell outside the spectrum grid: `footprintOutside` / `footprintArea` is the share of the class
    /// that the spectrum image does not see.
    public let footprintArea: [Double]
    public let footprintOutside: [Double]

    /// Geometric tolerance, in spectrum-pixel areas (~1e-6 px^2: a 1e-6 px shift of the registration),
    /// on the half-area test and on tie detection. A registration is known to far less than this, and on
    /// a 2x-binned grid every boundary pixel sits at exactly 1/2, so membership must not follow float
    /// noise (at 1e-9, a 1e-7 px offset moved 28 of 768 labels on the planted scene).
    public static let tolerance = 1e-6
    public static let inclusionThreshold = 0.5

    public var pixelCount: Int { width * height }

    /// Pixels at least half covered by `cls`: the region's membership, as a `PixelMask`.
    public func mask(forClass cls: Int) -> PixelMask {
        guard (0..<classCount).contains(cls) else { return [] }
        return overlap[cls].map { $0 >= Self.inclusionThreshold - Self.tolerance }
    }

    /// Per-pixel class: the single class with the largest overlap when that overlap is at least a half;
    /// -1 when it is below a half (including wholly outside the 4D grid) or tied between classes
    /// (`tiedExcluded` counts those).
    public var labels: [Int] { labelling().labels }

    /// Pixels left unlabelled because two or more classes share the largest overlap (at least a half).
    public var tiedExcluded: Int { labelling().tied.filter { $0 }.count }

    /// Which pixels are those (row-major).
    public var tiedPixels: [Bool] { labelling().tied }

    private func labelling() -> (labels: [Int], tied: [Bool]) {
        var out = [Int](repeating: -1, count: pixelCount)
        var tied = [Bool](repeating: false, count: pixelCount)
        for p in 0..<pixelCount {
            var best = -1, bestArea = 0.0
            for c in 0..<classCount where overlap[c][p] > bestArea + Self.tolerance {
                best = c; bestArea = overlap[c][p]
            }
            // A later class may exceed an earlier best by less than the tolerance; the best found is a
            // class within tolerance of the maximum either way, so look for any OTHER within tolerance.
            guard best >= 0, bestArea >= Self.inclusionThreshold - Self.tolerance else { continue }
            let rivals = (0..<classCount).filter { $0 != best && overlap[$0][p] >= bestArea - Self.tolerance }
            if rivals.isEmpty { out[p] = best } else { tied[p] = true }
        }
        return (out, tied)
    }

    /// Pixels that touch the edge of the 4D scan: part of their area lies outside it. These are the
    /// pixels a registration offset can mislabel, flagged whether or not they are in a region.
    public var edgePixels: [Bool] { insideGrid.map { $0 < 1 - Self.tolerance } }
}

/// How well a region survived the move onto the spectrum grid (what the Regions step shows).
public struct MaskTransportReport: Sendable, Equatable {
    /// Pixels of the spectrum grid in the region.
    public let pixelsIncluded: Int
    /// Included pixels that the region covers only partly (overlap < 1): the region's ragged rim.
    public let partialIncluded: Int
    /// Included pixels that are edge pixels (area partly outside the 4D scan).
    public let edgeIncluded: Int
    /// Pixels the region touches (overlap > 0) but covers by less than half: dropped.
    public let touchedExcluded: Int
    /// The region's own area in spectrum-pixel units.
    public let regionArea: Double
    /// Area of the included pixels covered by the region / regionArea (1 = nothing eroded away).
    public let retainedFraction: Double
    /// Share of the region's footprint that falls outside the spectrum grid.
    public let outsideFraction: Double
    /// The region's whole footprint in spectrum-pixel units (what a reader compares the pixel count with:
    /// "12 px of a 31.5-px footprint").
    public let footprintArea: Double
    /// Region area inside the included pixels / the pixels' own area: 1 = every included pixel is wholly
    /// the region.
    public let purity: Double
}

/// Transports whole-pixel masks by clipping affine pixel footprints.
public enum MaskTransport {

    /// Transport a class map of the 4D grid. `labels[y * scanWidth + x]` is the class (0..<classCount) or
    /// -1 for "none"; its length must be `scanWidth * scanHeight`. Throws for a singular registration or
    /// a wrong length.
    public static func transport(labels: [Int], classCount: Int, registration: GridRegistration)
        throws -> TransportedLabels {
        let sw = registration.scanWidth, sh = registration.scanHeight
        let w = registration.spectrumWidth, h = registration.spectrumHeight
        guard registration.matrix.allSatisfy({ $0.isFinite && abs($0) < 1e9 }) else {
            throw MaskTransportError(description: "The registration has non-finite or absurd entries.")
        }
        guard registration.isInvertible else {
            throw MaskTransportError(description: "The registration is singular (det = \(registration.determinant)).")
        }
        guard labels.count == sw * sh, classCount > 0,
              labels.allSatisfy({ $0 == -1 || (0..<classCount).contains($0) }),
              !classCount.multipliedReportingOverflow(by: w * h).overflow else {
            throw MaskTransportError(description: "The label map has \(labels.count) entries; the 4D grid is \(sw) x \(sh).")
        }
        let m = registration.matrix
        let pixelArea = abs(registration.determinant)   // area of one 4D pixel in spectrum-pixel units
        var overlap = [[Double]](repeating: [Double](repeating: 0, count: w * h), count: classCount)
        var inside = [Double](repeating: 0, count: w * h)
        var total = [Double](repeating: 0, count: classCount)
        var outside = total
        // The pixel's four corners, in order, in 4D centre coordinates.
        let corners: [(Double, Double)] = [(-0.5, -0.5), (0.5, -0.5), (0.5, 0.5), (-0.5, 0.5)]
        for y in 0..<sh {
            for x in 0..<sw {
                let cls = labels[y * sw + x]
                let poly = corners.map { c -> (Double, Double) in
                    let px = Double(x) + c.0, py = Double(y) + c.1
                    return (m[0] * px + m[1] * py + m[2], m[3] * px + m[4] * py + m[5])
                }
                let us = poly.map(\.0), vs = poly.map(\.1)
                // Clamp in Double before converting: a far-off map must not trap in Int().
                let u0d = max((us.min()! + 0.5).rounded(.down), 0), u1d = min((us.max()! + 0.5).rounded(.up), Double(w - 1))
                let v0d = max((vs.min()! + 0.5).rounded(.down), 0), v1d = min((vs.max()! + 0.5).rounded(.up), Double(h - 1))
                var landed = 0.0
                if u0d <= u1d, v0d <= v1d {
                    let (u0, u1, v0, v1) = (Int(u0d), Int(u1d), Int(v0d), Int(v1d))
                    for v in v0...v1 {
                        for u in u0...u1 {
                            let a = clippedArea(poly, uLo: Double(u) - 0.5, uHi: Double(u) + 0.5,
                                                vLo: Double(v) - 0.5, vHi: Double(v) + 0.5)
                            guard a > 0 else { continue }
                            landed += a
                            inside[v * w + u] += a
                            if cls >= 0 { overlap[cls][v * w + u] += a }
                        }
                    }
                }
                if cls >= 0 { total[cls] += pixelArea; outside[cls] += max(pixelArea - landed, 0) }
            }
        }
        // `inside` accumulated the 4D grid's footprint on every pixel; with pixelArea summing to 1 over a
        // pixel it is the fraction of the pixel inside the grid. Clamp float dust.
        for i in 0..<inside.count { inside[i] = min(inside[i], 1) }
        return TransportedLabels(width: w, height: h, classCount: classCount,
                                 overlap: overlap.map { $0.map { min($0, 1) } }, insideGrid: inside,
                                 footprintArea: total, footprintOutside: outside)
    }

    /// One boolean mask of the 4D grid (`true` = in the region).
    public static func transport(mask: [Bool], registration: GridRegistration) throws -> TransportedLabels {
        try transport(labels: mask.map { $0 ? 0 : -1 }, classCount: 1, registration: registration)
    }

    /// The membership of class `cls` as a spectrum-grid mask plus its report.
    public static func region(_ t: TransportedLabels, class cls: Int = 0) throws -> (mask: PixelMask, report: MaskTransportReport) {
        guard (0..<t.classCount).contains(cls) else {
            throw MaskTransportError(description: "Class index is outside the transported map.")
        }
        let mask = t.mask(forClass: cls)
        let tol = TransportedLabels.tolerance
        var included = 0, partial = 0, edge = 0, touched = 0
        var retained = 0.0
        for p in 0..<t.pixelCount {
            let o = t.overlap[cls][p]
            if mask[p] {
                included += 1
                retained += o
                if o < 1 - tol { partial += 1 }
                if t.insideGrid[p] < 1 - tol { edge += 1 }
            } else if o > tol {
                touched += 1
            }
        }
        let area = t.overlap[cls].reduce(0, +)
        let regionArea = area   // area that landed on the spectrum grid
        let footprint = t.footprintArea[cls], outside = t.footprintOutside[cls]
        let report = MaskTransportReport(
            pixelsIncluded: included, partialIncluded: partial, edgeIncluded: edge, touchedExcluded: touched,
            regionArea: regionArea,
            retainedFraction: regionArea > 0 ? retained / regionArea : 0,
            outsideFraction: footprint > 0 ? outside / footprint : 0,
            footprintArea: footprint, purity: included > 0 ? retained / Double(included) : 0)
        return (mask, report)
    }

    // MARK: - Mask builders for the 4D side

    /// An object's pixels (row-major indices into a `width x height` grid).
    public static func mask(pixelIndices: [Int], width: Int, height: Int) -> [Bool] {
        guard width > 0, height > 0, !width.multipliedReportingOverflow(by: height).overflow else { return [] }
        var out = [Bool](repeating: false, count: width * height)
        for i in pixelIndices where i >= 0 && i < out.count { out[i] = true }
        return out
    }

    /// A drawn rectangle in 4D pixel coordinates (inclusive, clipped to the grid).
    public static func mask(rectangle x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, width: Int, height: Int) -> [Bool] {
        guard width > 0, height > 0, !width.multipliedReportingOverflow(by: height).overflow else { return [] }
        var out = [Bool](repeating: false, count: width * height)
        let (xa, xb, ya, yb) = (max(x0, 0), min(x1, width - 1), max(y0, 0), min(y1, height - 1))
        guard xa <= xb, ya <= yb else { return out }
        for y in ya...yb { for x in xa...xb { out[y * width + x] = true } }
        return out
    }

    // MARK: - Convex polygon against an axis-aligned square

    /// Area of the intersection of a convex polygon (any winding) with [uLo, uHi] x [vLo, vHi].
    package static func clippedArea(_ polygon: [(Double, Double)], uLo: Double, uHi: Double,
                                    vLo: Double, vHi: Double) -> Double {
        var p = polygon
        // (axis, bound, keep-greater)
        let planes: [(Int, Double, Bool)] = [(0, uLo, true), (0, uHi, false), (1, vLo, true), (1, vHi, false)]
        for (axis, bound, keepGreater) in planes {
            guard !p.isEmpty else { return 0 }
            func value(_ q: (Double, Double)) -> Double { axis == 0 ? q.0 : q.1 }
            func inside(_ q: (Double, Double)) -> Bool { keepGreater ? value(q) >= bound : value(q) <= bound }
            var out: [(Double, Double)] = []
            for i in 0..<p.count {
                let a = p[i], b = p[(i + 1) % p.count]
                let ia = inside(a), ib = inside(b)
                if ia { out.append(a) }
                if ia != ib {
                    let t = (bound - value(a)) / (value(b) - value(a))
                    out.append((a.0 + t * (b.0 - a.0), a.1 + t * (b.1 - a.1)))
                }
            }
            p = out
        }
        guard p.count >= 3 else { return 0 }
        var s = 0.0
        for i in 0..<p.count {
            let a = p[i], b = p[(i + 1) % p.count]
            s += a.0 * b.1 - b.0 * a.1
        }
        return abs(s) / 2
    }
}
