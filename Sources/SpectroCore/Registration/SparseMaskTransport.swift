//
//  SparseMaskTransport.swift
//  Role: `MaskTransport.regions(...)`, the transport of many regions at once for a large grid. `MaskTransport.transport(labels:...)`
//        returns a dense `overlap[class][pixel]` (classCount x spectrum pixels doubles: 630 MB for 300 regions on a 512 x 512
//        spectrum grid). Here each region is a list of scan pixels and its result a sorted list of the spectrum pixels it touches
//        with their overlap areas; nothing is sized by regions x grid.
//
//  SEMANTICS. Region r is exactly `MaskTransport.transport(mask:registration:)` of the mask holding the region's scan pixels: the
//  regions are independent (they may overlap or touch), unlike the classes of `transport(labels:)`, which partition the scan. The
//  scan pixels of a region are visited in ascending index order and each spectrum pixel's areas are added in that order, as the dense
//  transport does, so `overlap`, `footprintArea` and `footprintOutside` are bit for bit the dense values and every derived number
//  (membership, `MaskTransportReport`, a pooled spectrum) is equal. The one difference: the dense transport sums the clipped areas of
//  ALL scan pixels into `insideGrid`; here it is the area of the spectrum pixel inside the scan's own parallelogram, clipped in one
//  step per touched pixel (the same number to 1e-15; the 1e-6 threshold of the edge flag is far from it).
//

import Foundation

/// A region of the 4D (scan) grid: its pixels as row-major indices (`row * scanWidth + column`) or as runs along rows.
public struct SparseRegion: Sendable, Equatable {
    /// A run of `length` pixels of row `row` starting at column `column`.
    public struct Run: Sendable, Equatable {
        public var row: Int
        public var column: Int
        public var length: Int
        public init(row: Int, column: Int, length: Int) { self.row = row; self.column = column; self.length = length }
    }

    private enum Storage: Sendable, Equatable { case indices([Int]), runs([Run]) }
    private let storage: Storage

    /// Row-major scan-pixel indices, in any order, repeats allowed.
    public init(pixelIndices: [Int]) { storage = .indices(pixelIndices) }
    /// Runs of pixels along rows, in any order; runs may overlap.
    public init(runs: [Run]) { storage = .runs(runs) }
    /// The pixels of a boolean scan mask (`true` = in).
    public init(mask: [Bool]) { storage = .indices(mask.indices.filter { mask[$0] }) }

    /// Sorted, unique row-major indices on a `width x height` scan grid. Throws for a pixel outside it.
    func scanIndices(width: Int, height: Int) throws -> [Int] {
        var out: [Int]
        switch storage {
        case .indices(let ix):
            guard ix.allSatisfy({ $0 >= 0 && $0 < width * height }) else {
                throw MaskTransportError(description: "A region has a pixel outside the \(width) x \(height) scan grid.")
            }
            out = ix
        case .runs(let runs):
            out = []
            var expanded = 0
            let cap = width * height * 4
            for r in runs {
                guard r.length >= 0, r.row >= 0, r.row < height, r.column >= 0, r.column <= width, r.length <= width - r.column else {
                    throw MaskTransportError(description: "A run (row \(r.row), column \(r.column), length \(r.length)) leaves the \(width) x \(height) scan grid.")
                }
                expanded += r.length
                guard expanded <= cap else {
                    throw MaskTransportError(description: "The runs of a region expand to more than four times the \(width) x \(height) scan grid.")
                }
                out.append(contentsOf: (r.row * width + r.column)..<(r.row * width + r.column + r.length))
            }
        }
        out.sort()
        var unique: [Int] = []
        unique.reserveCapacity(out.count)
        for v in out where unique.last != v { unique.append(v) }
        return unique
    }
}

/// Many regions transported onto the spectrum grid, each as the sorted list of spectrum pixels it touches.
public struct TransportedRegions: Sendable, Equatable {
    /// One region: `pixels[k]` (row-major spectrum index, ascending) is overlapped by `overlap[k]` of its area
    /// (1 = the whole pixel); `insideGrid[k]` is the part of that pixel inside the scan.
    public struct Entry: Sendable, Equatable {
        public let pixels: [Int32]
        public let overlap: [Double]
        public let insideGrid: [Double]
        /// The region's area in spectrum-pixel units, and how much of it fell outside the spectrum grid.
        public let footprintArea: Double
        public let footprintOutside: Double
    }

    public let width: Int
    public let height: Int
    public let entries: [Entry]

    public var regionCount: Int { entries.count }
    public var pixelCount: Int { width * height }

    /// Pixels at least half covered by region `i` (`TransportedLabels.mask(forClass:)`'s rule), ascending spectrum indices.
    public func includedPixels(region i: Int) -> [Int] {
        guard entries.indices.contains(i) else { return [] }
        let e = entries[i]
        let cut = TransportedLabels.inclusionThreshold - TransportedLabels.tolerance
        return e.pixels.indices.filter { e.overlap[$0] >= cut }.map { Int(e.pixels[$0]) }
    }

    /// The membership of region `i` as a spectrum-grid mask plus its report: what `MaskTransport.region` returns for
    /// the dense transport of the same region.
    public func region(_ i: Int) throws -> (mask: PixelMask, report: MaskTransportReport) {
        guard entries.indices.contains(i) else { throw MaskTransportError(description: "Region index is outside the transported regions.") }
        let e = entries[i]
        let tol = TransportedLabels.tolerance
        let cut = TransportedLabels.inclusionThreshold - tol
        var mask = PixelMask(repeating: false, count: pixelCount)
        var included = 0, partial = 0, edge = 0, touched = 0
        var retained = 0.0, area = 0.0
        for k in e.pixels.indices {
            let o = e.overlap[k]
            area += o
            if o >= cut {
                mask[Int(e.pixels[k])] = true
                included += 1
                retained += o
                if o < 1 - tol { partial += 1 }
                if e.insideGrid[k] < 1 - tol { edge += 1 }
            } else if o > tol {
                touched += 1
            }
        }
        let report = MaskTransportReport(
            pixelsIncluded: included, partialIncluded: partial, edgeIncluded: edge, touchedExcluded: touched,
            regionArea: area,
            retainedFraction: area > 0 ? retained / area : 0,
            outsideFraction: e.footprintArea > 0 ? e.footprintOutside / e.footprintArea : 0,
            footprintArea: e.footprintArea, purity: included > 0 ? retained / Double(included) : 0)
        return (mask, report)
    }

    /// Region `i` as the dense single-class `TransportedLabels` (`overlap` and `insideGrid` over the whole spectrum grid):
    /// for comparison with `MaskTransport.transport(mask:)` and for small grids. `insideGrid` is 1 away from the scan's edge
    /// only at the touched pixels; elsewhere it is 0 (unknown to a sparse result).
    public func dense(region i: Int) throws -> TransportedLabels {
        guard entries.indices.contains(i) else { throw MaskTransportError(description: "Region index is outside the transported regions.") }
        let e = entries[i]
        var overlap = [Double](repeating: 0, count: pixelCount), inside = overlap
        for k in e.pixels.indices { overlap[Int(e.pixels[k])] = e.overlap[k]; inside[Int(e.pixels[k])] = e.insideGrid[k] }
        return TransportedLabels(width: width, height: height, classCount: 1, overlap: [overlap], insideGrid: inside,
                                 footprintArea: [e.footprintArea], footprintOutside: [e.footprintOutside])
    }

    /// Bytes held by the result (arrays only), for comparing with the dense `classCount * w * h * 8`.
    public var storageBytes: Int { entries.reduce(0) { $0 + $1.pixels.count * (4 + 8 + 8) + 16 } }
}

extension MaskTransport {

    /// Transports each region of the 4D grid onto the spectrum grid of `registration`, sparse. Region `i` of the result equals
    /// `transport(mask:registration:)` of the mask holding `regions[i]`'s scan pixels (see the file header). Regions are
    /// independent and run on all cores; the result does not depend on the schedule. Throws `MaskTransportError` for a singular
    /// registration or a region pixel/run outside the scan grid.
    public static func regions(_ regions: [SparseRegion], registration: GridRegistration) throws -> TransportedRegions {
        let sw = registration.scanWidth, sh = registration.scanHeight
        let w = registration.spectrumWidth, h = registration.spectrumHeight
        guard registration.matrix.allSatisfy({ $0.isFinite && abs($0) < 1e9 }) else {
            throw MaskTransportError(description: "The registration has non-finite or absurd entries.")
        }
        guard registration.isInvertible else {
            throw MaskTransportError(description: "The registration is singular (det = \(registration.determinant)).")
        }
        let indices = try regions.map { try $0.scanIndices(width: sw, height: sh) }
        let m = registration.matrix
        let pixelArea = abs(registration.determinant)
        let corners: [(Double, Double)] = [(-0.5, -0.5), (0.5, -0.5), (0.5, 0.5), (-0.5, 0.5)]
        // The scan's own footprint on the spectrum grid, for `insideGrid`.
        let scanPoly: [(Double, Double)] = [(-0.5, -0.5), (Double(sw) - 0.5, -0.5), (Double(sw) - 0.5, Double(sh) - 0.5), (-0.5, Double(sh) - 0.5)]
            .map { (m[0] * $0.0 + m[1] * $0.1 + m[2], m[3] * $0.0 + m[4] * $0.1 + m[5]) }

        let boxed = ResultBox(count: regions.count)
        let chunk = 4, chunks = (regions.count + chunk - 1) / chunk
        DispatchQueue.concurrentPerform(iterations: chunks) { ci in
            var area = [Double](repeating: 0, count: w * h)
            var stamp = [Int32](repeating: -1, count: w * h)
            for r in (ci * chunk)..<min(regions.count, (ci + 1) * chunk) {
                var touched: [Int32] = []
                var total = 0.0, outside = 0.0
                for idx in indices[r] {
                    let x = idx % sw, y = idx / sw
                    let poly = corners.map { c -> (Double, Double) in
                        let px = Double(x) + c.0, py = Double(y) + c.1
                        return (m[0] * px + m[1] * py + m[2], m[3] * px + m[4] * py + m[5])
                    }
                    let us = poly.map(\.0), vs = poly.map(\.1)
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
                                let p = v * w + u
                                if stamp[p] != Int32(r) { stamp[p] = Int32(r); touched.append(Int32(p)) }
                                area[p] += a
                            }
                        }
                    }
                    total += pixelArea; outside += max(pixelArea - landed, 0)
                }
                touched.sort()
                let overlap = touched.map { min(area[Int($0)], 1) }
                let inside = touched.map { p -> Double in
                    let u = Int(p) % w, v = Int(p) / w
                    return min(clippedArea(scanPoly, uLo: Double(u) - 0.5, uHi: Double(u) + 0.5,
                                           vLo: Double(v) - 0.5, vHi: Double(v) + 0.5), 1)
                }
                for p in touched { area[Int(p)] = 0 }
                boxed.set(r, TransportedRegions.Entry(pixels: touched, overlap: overlap, insideGrid: inside,
                                                      footprintArea: total, footprintOutside: outside))
            }
        }
        return TransportedRegions(width: w, height: h, entries: boxed.values)
    }
}

/// Slots that concurrent chunks fill at disjoint indices.
private final class ResultBox: @unchecked Sendable {
    private let slots: UnsafeMutablePointer<TransportedRegions.Entry?>
    private let count: Int
    init(count: Int) {
        self.count = count
        slots = .allocate(capacity: max(count, 1))
        slots.initialize(repeating: nil, count: max(count, 1))
    }
    deinit { slots.deinitialize(count: max(count, 1)); slots.deallocate() }
    func set(_ i: Int, _ e: TransportedRegions.Entry) { slots[i] = e }
    var values: [TransportedRegions.Entry] { (0..<count).map { slots[$0]! } }
}

extension PoolBuilder {

    /// One pool per region of a sparse transport (`names[i]` for region i): each is what `pool(image:scanMask:registration:...)`
    /// gives for that region alone. The regions are independent, so a spectrum pixel may be pooled by more than one.
    public static func pools(image: some SpectrumImage, transported t: TransportedRegions, names: [String], kind: String,
                             validation: String? = nil) throws -> [PooledSpectrum] {
        guard t.width == image.nx, t.height == image.ny else {
            throw MaskTransportError(description: "The registration maps onto a \(t.width) x \(t.height) grid; the spectrum image is \(image.nx) x \(image.ny).")
        }
        guard names.count == t.regionCount else {
            throw MaskTransportError(description: "\(names.count) names for \(t.regionCount) regions.")
        }
        return try (0..<t.regionCount).map { i in
            let (mask, report) = try t.region(i)
            return try pool(image: image, mask: mask, name: names[i], kind: kind, partialPixels: report.partialIncluded,
                            edgePixels: report.edgeIncluded, outsideFraction: report.outsideFraction,
                            footprintArea: report.footprintArea, retainedFraction: report.retainedFraction,
                            purity: report.purity, validation: validation)
        }
    }
}
