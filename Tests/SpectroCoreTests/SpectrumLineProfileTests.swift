import Foundation
import Testing
import SpectroCore

/// Planted truth for the line profile: spectra that encode their own pixel position (channel 0 = row, 1 = column, 2 = 1).
struct SpectrumLineProfileTests {

    static func cube(ny: Int = 20, nx: Int = 24) -> DenseSpectrumImage {
        var counts = [UInt32](); counts.reserveCapacity(ny * nx * 3)
        for r in 0..<ny { for c in 0..<nx { counts += [UInt32(r), UInt32(c), 1] } }
        return DenseSpectrumImage(ny: ny, nx: nx, channels: 3, counts: counts)
    }

    @Test func horizontalLineOfOddWidthPoolsTheColumnsItCrosses() throws {
        let p = try SpectrumLineProfile.compute(image: Self.cube(), path: [PixelPosition(row: 7, column: 2), PixelPosition(row: 7, column: 20)],
                                                width: 3)
        #expect(p.stepCount == 19)
        for k in 0..<19 {
            #expect(p.arcLengths[k] == Double(k))
            #expect(p.pixelCounts[k] == 3 && p.weightSums[k] == 3)
            #expect(abs(p.spectra[k][0] - 7) < 1e-12)            // rows 6, 7, 8
            #expect(abs(p.spectra[k][1] - Double(2 + k)) < 1e-12)
            #expect(abs(p.spectra[k][2] - 1) < 1e-12)
            #expect(p.rows[k] == 7 && p.columns[k] == Double(2 + k))
        }
    }

    @Test func sumIsMeanTimesCount() throws {
        let path = [PixelPosition(row: 2.3, column: 3.7), PixelPosition(row: 9.1, column: 8.2), PixelPosition(row: 16.4, column: 20.6)]
        let mean = try SpectrumLineProfile.compute(image: Self.cube(), path: path, width: 2.5, spacing: 1.7)
        let sum = try SpectrumLineProfile.compute(image: Self.cube(), path: path, width: 2.5, spacing: 1.7, reduction: .sum)
        #expect(mean.pixelCounts == sum.pixelCounts)
        for k in 0..<mean.stepCount where mean.pixelCounts[k] > 0 {
            // channel 2 is 1 everywhere: the sum is the pixel count, the mean is 1
            #expect(sum.spectra[k][2] == Double(sum.pixelCounts[k]))
            #expect(abs(mean.spectra[k][2] - 1) < 1e-12)
            #expect(abs(sum.spectra[k][0] - mean.spectra[k][0] * Double(mean.pixelCounts[k])) < 1e-9)
        }
        #expect(abs(mean.pathLength - (hypot(6.8, 4.5) + hypot(7.3, 12.4))) < 1e-12)
    }

    @Test func theStripIsPartitionedBetweenTheSteps() throws {
        // A straight strip of width 4 over columns 2 ... 20: every pixel of the 19 x 4 block is pooled once, none twice.
        let p = try SpectrumLineProfile.compute(image: Self.cube(), path: [PixelPosition(row: 7.5, column: 2), PixelPosition(row: 7.5, column: 20)],
                                                width: 4, reduction: .sum)
        #expect(p.pixelCounts.reduce(0, +) == 19 * 4)
        #expect(p.spectra.reduce(0.0) { $0 + $1[2] } == 76)
        // rows 6, 7, 8, 9 (distance 1.5, 0.5, 0.5, 1.5 from row 7.5)
        #expect(p.spectra.allSatisfy { $0[0] == 30 })
    }

    @Test func aPathOutsideTheGridGivesEmptySteps() throws {
        let p = try SpectrumLineProfile.compute(image: Self.cube(), path: [PixelPosition(row: -30, column: 0), PixelPosition(row: -30, column: 5)],
                                                width: 3)
        #expect(p.pixelCounts == [Int](repeating: 0, count: 6))
        #expect(p.spectra.allSatisfy { $0 == [0, 0, 0] })
    }

    @Test func aPathPartlyOffTheGridPoolsOnlyThePixelsThatExist() throws {
        let p = try SpectrumLineProfile.compute(image: Self.cube(), path: [PixelPosition(row: 0, column: -3), PixelPosition(row: 0, column: 3)],
                                                width: 3)
        // Steps at columns -3, -2, -1 have no pixel in the grid; at columns 0 .. 3 the strip is rows -1, 0, 1 and row -1 is off the grid.
        #expect(p.pixelCounts[0] == 0 && p.pixelCounts[2] == 0)
        #expect(p.pixelCounts[3] == 2 && p.pixelCounts[6] == 2)
    }

    @Test func bilinearOnAWholePixelPathEqualsTheHardPool() throws {
        let path = [PixelPosition(row: 4, column: 3), PixelPosition(row: 4, column: 15)]
        let h = try SpectrumLineProfile.compute(image: Self.cube(), path: path, width: 3)
        let b = try SpectrumLineProfile.compute(image: Self.cube(), path: path, width: 3, weighting: .bilinear)
        for k in 0..<h.stepCount {
            for c in 0..<3 { #expect(abs(h.spectra[k][c] - b.spectra[k][c]) < 1e-12) }
            #expect(b.weightSums[k] == 3 && b.pixelCounts[k] == 3)
        }
    }

    @Test func aSparseImageGivesTheDenseAnswer() throws {
        let dense = Self.cube(ny: 12, nx: 14)
        var offsets = [0], idx = [UInt16](), cnt = [UInt32]()
        for p in 0..<(12 * 14) {
            for c in 0..<3 where dense.counts[p * 3 + c] != 0 { idx.append(UInt16(c)); cnt.append(dense.counts[p * 3 + c]) }
            offsets.append(idx.count)
        }
        let sparse = try SparseSpectrumImage(ny: 12, nx: 14, channels: 3, rowOffsets: offsets, channelIndex: idx, counts: cnt)
        let path = [PixelPosition(row: 1.5, column: 1), PixelPosition(row: 8.2, column: 11.3)]
        for w in [LineProfileWeighting.hard, .bilinear] {
            let a = try SpectrumLineProfile.compute(image: dense, path: path, width: 3, weighting: w)
            let b = try SpectrumLineProfile.compute(image: sparse, path: path, width: 3, weighting: w)
            #expect(a == b)
        }
    }

    @Test func refusals() throws {
        let img = Self.cube()
        let a = PixelPosition(row: 1, column: 1), b = PixelPosition(row: 5, column: 5)
        #expect(throws: SpectrumLineProfileError.self) { try SpectrumLineProfile.compute(image: img, path: [a], width: 1) }
        #expect(throws: SpectrumLineProfileError.self) { try SpectrumLineProfile.compute(image: img, path: [a, a], width: 1) }
        #expect(throws: SpectrumLineProfileError.self) { try SpectrumLineProfile.compute(image: img, path: [a, b], width: 0) }
        #expect(throws: SpectrumLineProfileError.self) { try SpectrumLineProfile.compute(image: img, path: [a, b], width: .nan) }
        #expect(throws: SpectrumLineProfileError.self) { try SpectrumLineProfile.compute(image: img, path: [a, b], width: 1, spacing: 0) }
        #expect(throws: SpectrumLineProfileError.self) {
            try SpectrumLineProfile.compute(image: img, path: [a, PixelPosition(row: .infinity, column: 0)], width: 1)
        }
        #expect(throws: SpectrumLineProfileError.self) { try SpectrumLineProfile.compute(image: img, path: [a, b], width: 1, spacing: 1e-9) }
    }
}
