//
//  CoreTrapRefusalTests.swift
//  Role: a NaN or an out-of-range value reaching SpectroCore gives NaN (as scipy does), a refusal or an invalid kernel, never a trap
//        (macEMSuite/SpectroKit#103). One test per site the review named.
//  Red before: `precondition` in `CountingInterval.garwood`, `NetCounts.init`, `IncompleteGamma`; a Gaussian radius from a decoded
//  sigma of 1e300 overflowed `Int`; `Int32(p)` past 2^31 spectrum pixels; a file's counts that do not fill its box trapped in
//  `DenseSpectrumImage`.
//

import Foundation
import Testing
import SpectroCore

struct CoreTrapRefusalTests {

    @Test func aGarwoodIntervalOfANaNNegativeCountOrABadConfidenceIsNaN() {
        for (n, c) in [(Double.nan, 0.95), (-1, 0.95), (.infinity, 0.95), (5, 1), (5, 0), (5, .nan)] {
            let g = CountingInterval.garwood(count: n, confidence: c)
            #expect(g.lower.isNaN && g.upper.isNaN, "n \(n) confidence \(c)")
        }
        let ok = CountingInterval.garwood(count: 5)
        #expect(ok.lower > 0 && ok.upper > 5)
    }

    @Test func netCountsOfANegativeOrNaNWindowAreNone() {
        #expect(NetCounts(gross: -1, background: 1, scale: 1) == nil)
        #expect(NetCounts(gross: 1, background: .nan, scale: 1) == nil)
        #expect(NetCounts(gross: 1, background: 1, scale: 0) == nil)
        #expect(NetCounts(gross: 1, background: 1, scale: .infinity) == nil)
        #expect(NetCounts(gross: 10, background: 2, scale: 0.5)?.net == 9)
    }

    @Test func theIncompleteGammaOutsideItsDomainIsNaNAsScipy() {
        #expect(IncompleteGamma.lowerRegularized(a: 0, x: 1).isNaN)
        #expect(IncompleteGamma.lowerRegularized(a: 1, x: -1).isNaN)
        #expect(IncompleteGamma.lowerRegularized(a: .nan, x: 1).isNaN)
        #expect(IncompleteGamma.gammaQuantile(p: 2, shape: 1).isNaN)
        #expect(IncompleteGamma.gammaQuantile(p: 0.5, shape: -1).isNaN)
        #expect(IncompleteGamma.gammaQuantile(p: .nan, shape: 1).isNaN)
        #expect(abs(IncompleteGamma.lowerRegularized(a: 1, x: 1) - (1 - exp(-1))) < 1e-14)
    }

    @Test func aGaussianWiderThanAMillionPixelsIsNotAValidKernel() throws {
        let decoded = try JSONDecoder().decode(SmoothingKernel.self,
                                               from: JSONEncoder().encode(SmoothingKernel.gaussian(sigma: 1e300, truncation: 2)))
        #expect(!decoded.isValid)
        #expect(decoded.taps.isEmpty)
        #expect(SmoothingKernel.gaussian(sigma: 2, truncation: 2).taps.count == 9)
    }

    @Test func aSpectrumGridPast2To31PixelsIsRefused() throws {
        let reg = try GridRegistration(matrix: [1, 0, 0, 0, 1, 0], scanWidth: 4, scanHeight: 4, spectrumWidth: 50_000, spectrumHeight: 50_000)
        #expect(throws: MaskTransportError.self) { try MaskTransport.regions([SparseRegion(pixelIndices: [0])], registration: reg) }
    }

    @Test func countsThatDoNotFillTheirBoxAreNotASpectrumImage() {
        #expect(SpectrumImageOpener.holds(ny: 2, nx: 3, channels: 4, count: 24))
        #expect(!SpectrumImageOpener.holds(ny: 2, nx: 3, channels: 4, count: 23))
        #expect(!SpectrumImageOpener.holds(ny: 0, nx: 3, channels: 4, count: 0))
        #expect(!SpectrumImageOpener.holds(ny: -2, nx: -3, channels: 4, count: 24))
        #expect(!SpectrumImageOpener.holds(ny: Int.max, nx: 2, channels: 1, count: 0))
        #expect(!SpectrumImageOpener.holds(ny: 1 << 31, nx: 1 << 31, channels: 4, count: 0))
    }
}
