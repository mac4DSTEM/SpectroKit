import Foundation
import Testing
import SpectroCore

/// Planted truth for display smoothing; the SciPy / HyperSpy pins are in SpectroKitParityTests/SpectrumToolsPinsTests.
struct SpectrumSmoothingTests {

    @Test func savitzkyGolayReproducesAPolynomialOfItsOrderEverywhereIncludingTheEdges() throws {
        let x = (0..<80).map { Double($0) }
        let y = x.map { 3 - 0.2 * $0 + 0.015 * $0 * $0 }
        for (w, p) in [(5, 2), (9, 3), (21, 2), (7, 4)] {
            let out = try SpectrumSmoothing.savitzkyGolay(window: w, order: p).smooth(y)
            for i in 0..<y.count { #expect(abs(out[i] - y[i]) < 1e-9, "w \(w) p \(p) i \(i)") }
        }
        // an extended edge cannot: the first sample differs from a parabola's value for the reflect mode
        let reflected = try SpectrumSmoothing.savitzkyGolay(window: 9, order: 2, edge: .extend(.reflect)).smooth(y)
        #expect(abs(reflected[0] - y[0]) > 1e-3)
        for i in 4..<76 { #expect(abs(reflected[i] - y[i]) < 1e-9) }
    }

    @Test func everyFilterKeepsAConstant() throws {
        let y = [Double](repeating: 7.5, count: 40)
        let all: [SpectrumSmoothing] = [
            .savitzkyGolay(window: 7, order: 2), .savitzkyGolay(window: 7, order: 3, edge: .extend(.nearest)),
            .gaussian(sigma: 2), .gaussian(sigma: 1.3, boundary: .mirror), .movingAverage(width: 5), .movingAverage(width: 4, boundary: .wrap),
        ]
        for s in all { for v in try s.smooth(y) { #expect(abs(v - 7.5) < 1e-12) } }
        // constant(0) pulls the ends toward 0
        let c = try SpectrumSmoothing.movingAverage(width: 3, boundary: .constant(0)).smooth(y)
        #expect(abs(c[0] - 5) < 1e-12 && abs(c[1] - 7.5) < 1e-12)
    }

    @Test func gaussianOfADeltaIsTheNormalisedKernel() throws {
        var y = [Double](repeating: 0, count: 41); y[20] = 1
        let out = try SpectrumSmoothing.gaussian(sigma: 2).smooth(y)
        #expect(abs(out.reduce(0, +) - 1) < 1e-14)
        let radius = Int(4 * 2.0 + 0.5)
        let k = (-radius...radius).map { exp(-0.5 * Double($0 * $0) / 4) }
        let s = k.reduce(0, +)
        for d in -radius...radius { #expect(abs(out[20 + d] - k[d + radius] / s) < 1e-14) }
        #expect(out[20 + radius + 1] == 0 && out[20 - radius - 1] == 0)
    }

    @Test func movingAverageOfARampIsTheRampAndAnEvenWidthReachesOneMoreChannelLeft() throws {
        let y = (0..<20).map { Double($0) }
        let odd = try SpectrumSmoothing.movingAverage(width: 5).smooth(y)
        for i in 2..<18 { #expect(abs(odd[i] - y[i]) < 1e-12) }
        let even = try SpectrumSmoothing.movingAverage(width: 4).smooth(y)     // x[i-2 ... i+1]
        for i in 2..<18 { #expect(abs(even[i] - (y[i] - 0.5)) < 1e-12) }
    }

    @Test func batchIsTheSingleSpectrumCallPerSpectrum() throws {
        let n = 64, count = 130
        let data = (0..<(n * count)).map { Double(($0 * 37 + $0 / 7) % 101) }
        for s in [SpectrumSmoothing.savitzkyGolay(window: 9, order: 3), .gaussian(sigma: 1.7), .movingAverage(width: 6)] {
            let batch = try s.smoothBatch(data, spectrumLength: n)
            for p in [0, 1, 63, 64, 129] {
                #expect(batch[(p * n)..<((p + 1) * n)].elementsEqual(try s.smooth(Array(data[(p * n)..<((p + 1) * n)]))))
            }
            let lists = try s.smooth(spectra: (0..<count).map { Array(data[($0 * n)..<(($0 + 1) * n)]) })
            #expect(lists.flatMap { $0 } == batch)
        }
    }

    @Test func aSpectrumImageAndItsSparseFormSmoothAlike() throws {
        let ny = 3, nx = 4, ch = 30
        var counts = [UInt32]()
        for p in 0..<(ny * nx) { for c in 0..<ch { counts.append(UInt32((p * 7 + c * c) % 13)) } }
        let dense = DenseSpectrumImage(ny: ny, nx: nx, channels: ch, counts: counts)
        var offsets = [0], idx = [UInt16](), cnt = [UInt32]()
        for p in 0..<(ny * nx) {
            for c in 0..<ch where counts[p * ch + c] != 0 { idx.append(UInt16(c)); cnt.append(counts[p * ch + c]) }
            offsets.append(idx.count)
        }
        let sparse = try SparseSpectrumImage(ny: ny, nx: nx, channels: ch, rowOffsets: offsets, channelIndex: idx, counts: cnt)
        let s = SpectrumSmoothing.savitzkyGolay(window: 5, order: 2)
        let a = try s.smoothedSpectra(of: dense), b = try s.smoothedSpectra(of: sparse)
        #expect(a == b && a.count == ny * nx * ch)
        let pooled: [UInt64] = counts.prefix(ch).map { UInt64($0) }
        let single: [Double] = try s.smooth(pooled)
        #expect(single == Array(a[0..<ch]))
    }

    @Test func refusals() throws {
        let y = [Double](repeating: 1, count: 30)
        for bad: SpectrumSmoothing in [.savitzkyGolay(window: 4, order: 2), .savitzkyGolay(window: 1, order: 1), .savitzkyGolay(window: 5, order: 0),
                                       .savitzkyGolay(window: 5, order: 5), .gaussian(sigma: 0), .gaussian(sigma: .nan), .gaussian(sigma: 1, truncate: 0),
                                       .movingAverage(width: 0)] {
            #expect(throws: SpectrumSmoothingError.self) { try bad.smooth(y) }
        }
        #expect(throws: SpectrumSmoothingError.self) { try SpectrumSmoothing.savitzkyGolay(window: 31, order: 2).smooth(y) }
        #expect(throws: Never.self) { try SpectrumSmoothing.savitzkyGolay(window: 31, order: 2, edge: .extend(.reflect)).smooth(y) }
        #expect(throws: SpectrumSmoothingError.self) { try SpectrumSmoothing.gaussian(sigma: 1).smooth([1, .nan, 2]) }
        #expect(throws: SpectrumSmoothingError.self) { try SpectrumSmoothing.gaussian(sigma: 1).smoothBatch([1, 2, 3, 4, 5], spectrumLength: 2) }
    }
}
