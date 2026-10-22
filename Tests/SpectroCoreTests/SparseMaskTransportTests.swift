import Foundation
import Testing
import SpectroCore

/// `MaskTransport.regions` against the dense transport of each region alone (exact) and against the NumPy transcription pins.
struct SparseMaskTransportTests {

    static func registrations() throws -> [(String, GridRegistration)] {
        let c = cos(0.3), s = sin(0.3)
        return [
            ("identity", try GridRegistration(matrix: [1, 0, 0, 0, 1, 0], scanWidth: 20, scanHeight: 16, spectrumWidth: 20, spectrumHeight: 16)),
            ("rotated and scaled", try GridRegistration(matrix: [0.55 * c, -0.55 * s, 6.2, 0.55 * s, 0.55 * c, 1.1], scanWidth: 40, scanHeight: 30,
                                                       spectrumWidth: 24, spectrumHeight: 20)),
            ("shear and mirror", try GridRegistration(matrix: [-0.5, 0.2, 21.3, 0.1, 0.5, 0.7], scanWidth: 40, scanHeight: 30,
                                                     spectrumWidth: 24, spectrumHeight: 20)),
            ("2x binned with offset", try GridRegistration(matrix: [0.5, 0, 0.25, 0, 0.5, -0.25], scanWidth: 36, scanHeight: 24,
                                                          spectrumWidth: 18, spectrumHeight: 12)),
        ]
    }

    /// Planted regions: a block touching the top-left corner, a ragged diagonal band, a single pixel at the far corner,
    /// a column on the right edge, scattered pixels, and a region sharing pixels with another.
    static func regionIndices(sw: Int, sh: Int) -> [[Int]] {
        var band = [Int]()
        for y in 0..<sh { for x in 0..<sw where abs(x - y * sw / sh) <= 2 { band.append(y * sw + x) } }
        return [
            (0..<min(5, sh)).flatMap { y in (0..<min(7, sw)).map { y * sw + $0 } },
            band,
            [sw * sh - 1],
            (0..<sh).map { $0 * sw + sw - 1 },
            [3, 17, 90 % (sw * sh), 5 * sw + 11, (sh - 1) * sw + 4],
            band.filter { $0 % 3 != 0 },
        ]
    }

    @Test func eachRegionEqualsTheDenseTransportOfItsMask() throws {
        for (name, reg) in try Self.registrations() {
            let sw = reg.scanWidth, sh = reg.scanHeight
            let sets = Self.regionIndices(sw: sw, sh: sh)
            let sparse = try MaskTransport.regions(sets.map { SparseRegion(pixelIndices: $0) }, registration: reg)
            #expect(sparse.regionCount == sets.count)
            for (i, ix) in sets.enumerated() {
                let dense = try MaskTransport.transport(mask: MaskTransport.mask(pixelIndices: ix, width: sw, height: sh), registration: reg)
                let d = try sparse.dense(region: i)
                #expect(d.overlap == dense.overlap, "\(name) region \(i): overlap is bit for bit the dense value")
                #expect(d.footprintArea == dense.footprintArea && d.footprintOutside == dense.footprintOutside, "\(name) \(i)")
                // insideGrid: the touched pixels, to 1e-12 (a different summation than the dense one)
                for p in sparse.entries[i].pixels { #expect(abs(d.insideGrid[Int(p)] - dense.insideGrid[Int(p)]) < 1e-12, "\(name) \(i)") }
                let (mask, report) = try sparse.region(i)
                let (denseMask, denseReport) = try MaskTransport.region(dense)
                #expect(mask == denseMask, "\(name) \(i)")
                #expect(report == denseReport, "\(name) \(i): \(report) vs \(denseReport)")
                #expect(sparse.includedPixels(region: i) == denseMask.indices.filter { denseMask[$0] })
            }
        }
    }

    @Test func pooledSpectraEqualThePerRegionPoolsOfTheDensePath() throws {
        for (name, reg) in try Self.registrations() {
            let w = reg.spectrumWidth, h = reg.spectrumHeight, ch = 4
            var counts = [UInt32]()
            for p in 0..<(w * h) { for c in 0..<ch { counts.append(UInt32((p * 31 + c * 17) % 23)) } }
            let image = DenseSpectrumImage(ny: h, nx: w, channels: ch, counts: counts)
            let sets = Self.regionIndices(sw: reg.scanWidth, sh: reg.scanHeight)
            let sparse = try MaskTransport.regions(sets.map { SparseRegion(pixelIndices: $0) }, registration: reg)
            let pools = try PoolBuilder.pools(image: image, transported: sparse, names: sets.indices.map { "r\($0)" }, kind: "drawn", validation: "none")
            for (i, ix) in sets.enumerated() {
                let expected = try PoolBuilder.pool(image: image, scanMask: MaskTransport.mask(pixelIndices: ix, width: reg.scanWidth, height: reg.scanHeight),
                                                    registration: reg, name: "r\(i)", kind: "drawn", validation: "none")
                #expect(pools[i] == expected, "\(name) region \(i)")
            }
        }
    }

    @Test func runsUnsortedAndRepeatedPixelsGiveTheSameRegion() throws {
        let reg = try Self.registrations()[1].1
        let sw = reg.scanWidth
        let runs = [SparseRegion.Run(row: 4, column: 10, length: 6), SparseRegion.Run(row: 3, column: 8, length: 5), SparseRegion.Run(row: 4, column: 13, length: 6)]
        var ix = [Int]()
        for r in runs { ix += (0..<r.length).map { r.row * sw + r.column + $0 } }
        let a = try MaskTransport.regions([SparseRegion(runs: runs)], registration: reg)
        let b = try MaskTransport.regions([SparseRegion(pixelIndices: ix.reversed() + ix)], registration: reg)
        let mask = MaskTransport.mask(pixelIndices: ix, width: sw, height: reg.scanHeight)
        let c = try MaskTransport.regions([SparseRegion(mask: mask)], registration: reg)
        #expect(a == b && b == c)
        #expect(a.entries[0].footprintArea == Double(Set(ix).count) * abs(reg.determinant) || abs(a.entries[0].footprintArea - Double(Set(ix).count) * abs(reg.determinant)) < 1e-9)
    }

    @Test func regionsMatchTheNumpyTranscriptionPins() throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/registration-pins.json")
        let pins = try JSONDecoder().decode(RegistrationTests.Pins.self, from: Data(contentsOf: file))
        var gap = 0.0
        for c in pins.cases {
            let reg = try GridRegistration(matrix: c.matrix, scanWidth: c.sw, scanHeight: c.sh, spectrumWidth: c.w, spectrumHeight: c.h)
            let regions = (0..<c.classCount).map { cls in SparseRegion(pixelIndices: c.inputLabels.indices.filter { c.inputLabels[$0] == cls }) }
            let sparse = try MaskTransport.regions(regions, registration: reg)
            for cls in 0..<c.classCount {
                let d = try sparse.dense(region: cls)
                for (x, y) in zip(d.overlap[0], c.overlap[cls]) { gap = max(gap, abs(x - y)) }
                #expect(abs(d.footprintArea[0] - c.footprint[cls]) <= 2e-12 && abs(d.footprintOutside[0] - c.outside[cls]) <= 2e-12, "\(c.name)")
                let (mask, report) = try sparse.region(cls)
                #expect(mask == c.overlap[cls].map { $0 >= 0.5 - 1e-6 }, "\(c.name)")
                let e = c.regions[cls]
                #expect(report.pixelsIncluded == e.pixelsIncluded && report.partialIncluded == e.partialIncluded)
                #expect(report.edgeIncluded == e.edgeIncluded && report.touchedExcluded == e.touchedExcluded, "\(c.name)")
                #expect(abs(report.regionArea - e.regionArea) <= 2e-12 && abs(report.purity - e.purity) <= 2e-12)
            }
        }
        #expect(gap <= 2e-12)
    }

    @Test func refusals() throws {
        let reg = try Self.registrations()[0].1
        #expect(throws: MaskTransportError.self) { try MaskTransport.regions([SparseRegion(pixelIndices: [20 * 16])], registration: reg) }
        #expect(throws: MaskTransportError.self) { try MaskTransport.regions([SparseRegion(pixelIndices: [-1])], registration: reg) }
        #expect(throws: MaskTransportError.self) {
            try MaskTransport.regions([SparseRegion(runs: [.init(row: 0, column: 15, length: 6)])], registration: reg)
        }
        #expect(throws: MaskTransportError.self) {
            try MaskTransport.regions([SparseRegion(runs: [.init(row: 16, column: 0, length: 1)])], registration: reg)
        }
        #expect(try MaskTransport.regions([], registration: reg).regionCount == 0)
        let empty = try MaskTransport.regions([SparseRegion(pixelIndices: [])], registration: reg)
        #expect(empty.entries[0].pixels.isEmpty && empty.entries[0].footprintArea == 0)
        let (m, r) = try empty.region(0)
        #expect(!m.contains(true) && r.pixelsIncluded == 0)
        #expect(throws: MaskTransportError.self) { try empty.region(1) }
    }
}
