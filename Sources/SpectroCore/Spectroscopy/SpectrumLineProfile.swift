//
//  SpectrumLineProfile.swift
//  Role: The engine of an EDS or EELS line profile: one pooled spectrum per step along a polyline path of given width over
//        a spectrum image. Rows and columns; pixel (row, column) has its centre at the integer coordinates (row, column).
//
//  GEOMETRY. The path is a polyline of two or more points (fractional allowed, may leave the grid). Steps lie at arc
//  lengths 0, spacing, 2 spacing, ... up to the path length (the last step is the largest multiple of `spacing` not beyond
//  the end).
//
//  HARD weighting (default). A pixel belongs to the path when its centre is within `width / 2` of the path measured
//  perpendicular to it, and it lies between the path's two end points. Its foot point is the nearest point of the polyline
//  (a pixel nearer the outside of a corner is measured to the corner vertex: a round join); it goes to the step whose cell
//  [s - spacing/2, s + spacing/2) holds the arc length of its foot point. Every pixel is pooled at most once, so the cells
//  partition the strip, and on a straight path the cell of a step is the rectangle width x spacing about its point. The
//  perpendicular test is half-open on the signed offset, [-width/2, +width/2) with the sign of cross(tangent, pixel - foot)
//  (a 1e-9 px tolerance), so a pixel exactly on the edge is taken by one side only. A pixel whose foot point lies in the
//  last half cell beyond the final step is not pooled.
//
//  BILINEAR weighting. At each step point, `round(width)` (at least 1) points lie on the perpendicular one pixel apart and
//  centred on the path point (scikit-image `measure.profile_line` with `linewidth` = round(width), `order=1`); each point
//  reads the bilinear interpolation of the four pixel spectra around it. A point outside the grid (row outside
//  [0, ny - 1] or column outside [0, nx - 1]) is dropped. The weight of a step is the number of kept points.
//  With `spacing = length / (n - 1)` for n = ceil(length + 1) it reproduces `profile_line` sample for sample.
//
//  A step with no pixel (or no kept point) has zero pixels and a zero spectrum, mean or sum.
//
//  SPEED. A `DenseSpectrumImage` or `SparseSpectrumImage` is read pixel by pixel (cost: the bounding box of the strip plus
//  the pooled pixels). Any other conformer is read through `sum(mask:)` with a one-pixel mask (correct, but one pass over
//  the whole image per pixel read).
//

import Foundation

/// A refused line-profile request.
public struct SpectrumLineProfileError: Error, Equatable, CustomStringConvertible, Sendable {
    public let description: String
}

/// A position on the spectrum grid, in pixels: `row` down, `column` across; pixel centres at integers; fractions allowed.
public struct PixelPosition: Sendable, Equatable {
    public var row: Double
    public var column: Double
    public init(row: Double, column: Double) { self.row = row; self.column = column }
}

public enum LineProfileWeighting: Sendable, Equatable {
    /// A pixel is in or out (see the file header). Sums are exact.
    case hard
    /// Bilinear interpolation at points across the width (scikit-image `profile_line`, `order=1`).
    case bilinear
}

public enum LineProfileReduction: Sendable, Equatable {
    /// The pooled spectrum is the sum over the step's pixels (weighted for `.bilinear`).
    case sum
    /// The sum divided by the step's `weightSums` entry (its pixel count for `.hard`).
    case mean
}

/// The result of `SpectrumLineProfile.compute`: one entry per step, in order along the path.
public struct SpectrumLineProfile: Sendable, Equatable {
    /// Arc length of each step along the path, in pixels (0, spacing, ...).
    public let arcLengths: [Double]
    /// The path point of each step, in pixels.
    public let rows: [Double]
    public let columns: [Double]
    /// Pooled spectrum per step (`channels` values), as `reduction` says; a step with no pixel is all zeros.
    public let spectra: [[Double]]
    /// Spectrum pixels pooled in each step (for `.bilinear`: the distinct pixels with a nonzero weight).
    public let pixelCounts: [Int]
    /// Total weight of each step: the pixel count for `.hard`, the number of kept sample points for `.bilinear`.
    public let weightSums: [Double]
    public let reduction: LineProfileReduction
    public let weighting: LineProfileWeighting
    public let width: Double
    public let spacing: Double
    /// Length of the whole path in pixels.
    public let pathLength: Double

    public var stepCount: Int { arcLengths.count }

    /// One pooled spectrum per step along `path`, `width` pixels wide, a step every `spacing` pixels of arc length.
    /// Throws `SpectrumLineProfileError` for fewer than two points, a non-finite coordinate, a zero-length path,
    /// a width or spacing that is not positive and finite, more than 10 million steps or 2^28 values (steps x channels), or a
    /// `.bilinear` width over four times the scan's larger side.
    public static func compute(image: some SpectrumImage, path: [PixelPosition], width: Double, spacing: Double = 1,
                               weighting: LineProfileWeighting = .hard,
                               reduction: LineProfileReduction = .mean) throws -> SpectrumLineProfile {
        guard path.count >= 2 else { throw SpectrumLineProfileError(description: "A path needs at least two points.") }
        guard path.allSatisfy({ $0.row.isFinite && $0.column.isFinite && abs($0.row) < 1e9 && abs($0.column) < 1e9 }) else {
            throw SpectrumLineProfileError(description: "A path coordinate is not finite.")
        }
        guard width.isFinite, width > 0, width < 1e9 else {
            throw SpectrumLineProfileError(description: "The width must be positive and finite (got \(width)).")
        }
        guard spacing.isFinite, spacing > 0 else {
            throw SpectrumLineProfileError(description: "The spacing must be positive and finite (got \(spacing)).")
        }
        // Segments; coincident neighbours dropped.
        var pts = [path[0]]
        for p in path.dropFirst() where p != pts.last! { pts.append(p) }
        guard pts.count >= 2 else { throw SpectrumLineProfileError(description: "The path has zero length.") }
        var segs: [Segment] = []
        var cum = 0.0
        for i in 0..<(pts.count - 1) {
            let dr = pts[i + 1].row - pts[i].row, dc = pts[i + 1].column - pts[i].column
            let len = hypot(dr, dc)
            segs.append(Segment(r0: pts[i].row, c0: pts[i].column, ur: dr / len, uc: dc / len, length: len, start: cum))
            cum += len
        }
        let total = cum
        let stepsD = (total / spacing + 1e-9).rounded(.down) + 1
        guard stepsD <= 1e7 else { throw SpectrumLineProfileError(description: "More than 10 million steps.") }
        let nSteps = Int(stepsD)
        let reader = PixelReader(image)
        let ny = image.ny, nx = image.nx, ch = image.channels
        guard stepsD * Double(ch) <= Double(1 << 28) else {
            throw SpectrumLineProfileError(description: "\(nSteps) steps of \(ch) channels are more than 2^28 values; use a larger spacing.")
        }

        var acc = [[Double]](repeating: [Double](repeating: 0, count: ch), count: nSteps)
        var counts = [Int](repeating: 0, count: nSteps)
        var weights = [Double](repeating: 0, count: nSteps)

        // Step points.
        var rows = [Double](repeating: 0, count: nSteps), cols = rows, arcs = rows
        var stepSeg = [Int](repeating: 0, count: nSteps)
        var si = 0
        for k in 0..<nSteps {
            let s = min(Double(k) * spacing, total)
            while si < segs.count - 1, s >= segs[si + 1].start { si += 1 }
            let g = segs[si]
            let t = s - g.start
            rows[k] = g.r0 + g.ur * t; cols[k] = g.c0 + g.uc * t; arcs[k] = Double(k) * spacing
            stepSeg[k] = si
        }

        switch weighting {
        case .hard:
            let half = width / 2
            let pad = half + 1
            let rLo = max(Int((pts.map(\.row).min()! - pad).rounded(.down)), 0)
            let rHi = min(Int((pts.map(\.row).max()! + pad).rounded(.up)), ny - 1)
            let cLo = max(Int((pts.map(\.column).min()! - pad).rounded(.down)), 0)
            let cHi = min(Int((pts.map(\.column).max()! + pad).rounded(.up)), nx - 1)
            let tol = 1e-9
            if rLo <= rHi, cLo <= cHi {
                for r in rLo...rHi {
                    for c in cLo...cHi {
                        let qr = Double(r), qc = Double(c)
                        var best = -1, bestD2 = Double.infinity, bestT = 0.0, bestRaw = 0.0
                        for (i, g) in segs.enumerated() {
                            let dr = qr - g.r0, dc = qc - g.c0
                            let raw = dr * g.ur + dc * g.uc
                            let t = min(max(raw, 0), g.length)
                            let fr = dr - g.ur * t, fc = dc - g.uc * t
                            let d2 = fr * fr + fc * fc
                            if d2 < bestD2 - 1e-12 { best = i; bestD2 = d2; bestT = t; bestRaw = raw }
                        }
                        let g = segs[best]
                        if best == 0, bestRaw < 0 { continue }
                        if best == segs.count - 1, bestRaw > g.length { continue }
                        // Signed perpendicular offset: the sign of the cross product, the distance to the foot point.
                        let cross = g.ur * (qc - g.c0) - g.uc * (qr - g.r0)
                        let dist = bestD2.squareRoot()
                        let sd = cross < 0 ? -dist : dist
                        guard sd >= -half - tol, sd < half - tol else { continue }
                        let s = g.start + bestT
                        let k = Int((s / spacing + 0.5 + 1e-9).rounded(.down))
                        guard k < nSteps else { continue }
                        reader.add(pixel: r * nx + c, weight: 1, into: &acc[k])
                        counts[k] += 1
                        weights[k] += 1
                    }
                }
            }
        case .bilinear:
            guard width <= 4 * Double(max(ny, nx)) else {
                throw SpectrumLineProfileError(description: "The width \(width) is more than four times the larger side of the \(ny) x \(nx) scan.")
            }
            let n = max(1, Int(width.rounded()))
            for k in 0..<nSteps {
                let g = segs[stepSeg[k]]
                // Perpendicular unit vector (row, column) = (uc, -ur).
                var touched: [Int: Double] = [:]
                var kept = 0.0
                for j in 0..<n {
                    let off = Double(j) - Double(n - 1) / 2
                    let pr = rows[k] + off * g.uc, pc = cols[k] - off * g.ur
                    guard pr >= -1e-9, pr <= Double(ny - 1) + 1e-9, pc >= -1e-9, pc <= Double(nx - 1) + 1e-9 else { continue }
                    kept += 1
                    let r0 = min(max(Int(pr.rounded(.down)), 0), max(ny - 2, 0))
                    let c0 = min(max(Int(pc.rounded(.down)), 0), max(nx - 2, 0))
                    let fr = ny > 1 ? min(max(pr - Double(r0), 0), 1) : 0
                    let fc = nx > 1 ? min(max(pc - Double(c0), 0), 1) : 0
                    for (dr, wr) in [(0, 1 - fr), (1, fr)] where wr > 0 && r0 + dr < ny {
                        for (dc, wc) in [(0, 1 - fc), (1, fc)] where wc > 0 && c0 + dc < nx {
                            touched[(r0 + dr) * nx + c0 + dc, default: 0] += wr * wc
                        }
                    }
                }
                for (p, w) in touched.sorted(by: { $0.key < $1.key }) {
                    reader.add(pixel: p, weight: w, into: &acc[k])
                }
                counts[k] = touched.count
                weights[k] = kept
            }
        }
        if reduction == .mean {
            for k in 0..<nSteps where weights[k] > 0 {
                for c in 0..<ch { acc[k][c] /= weights[k] }
            }
        }
        return SpectrumLineProfile(arcLengths: arcs, rows: rows, columns: cols, spectra: acc, pixelCounts: counts,
                                   weightSums: weights, reduction: reduction, weighting: weighting, width: width,
                                   spacing: spacing, pathLength: total)
    }

    private struct Segment {
        let r0: Double, c0: Double, ur: Double, uc: Double, length: Double, start: Double
    }

    /// Reads one pixel's spectrum from whatever holds the image (resolved once).
    private struct PixelReader {
        enum Storage { case dense(DenseSpectrumImage), sparse(SparseSpectrumImage), other(any SpectrumImage) }
        let storage: Storage
        let channels: Int
        let nPixels: Int
        init(_ image: some SpectrumImage) {
            channels = image.channels; nPixels = image.ny * image.nx
            if let d = image as? DenseSpectrumImage { storage = .dense(d) }
            else if let s = image as? SparseSpectrumImage { storage = .sparse(s) }
            else { storage = .other(image) }
        }

        func add(pixel p: Int, weight w: Double, into acc: inout [Double]) {
            switch storage {
            case .dense(let d):
                let base = p * channels
                for c in 0..<channels { acc[c] += w * Double(d.counts[base + c]) }
            case .sparse(let s):
                for k in s.rowOffsets[p]..<s.rowOffsets[p + 1] { acc[Int(s.channelIndex[k])] += w * Double(s.counts[k]) }
            case .other(let image):
                var mask = PixelMask(repeating: false, count: nPixels)
                mask[p] = true
                let v = image.sum(mask: mask)
                for c in 0..<channels { acc[c] += w * Double(v[c]) }
            }
        }
    }
}
