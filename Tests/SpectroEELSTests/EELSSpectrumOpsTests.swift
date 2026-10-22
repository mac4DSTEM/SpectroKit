//
//  EELSSpectrumOpsTests.swift
//  Role: Task 16 step 2, the fast target: hand-derived rules (np.hanning's values and symmetry, the default taper width with Python's round, the
//        taper's slices and offsets, an exact power law continued exactly, `fixNegativeR`, a window sum that is not positive) and the refusals.
//        The pins against exSpy are SpectroKitParityTests/SpectrumOpsPinsTests.
//

import Foundation
import Testing
import SpectroTestSupport
import SpectroEELS

struct EELSSpectrumOpsTests {

    private func image(_ rows: [[Double]], offset: Double = 100, scale: Double = 0.5) throws -> CoreLossSpectrumImage {
        try CoreLossSpectrumImage(nx: rows.count, ny: 1, channels: rows[0].count, counts: rows.flatMap { $0 }, energyOffsetEV: offset, energyScaleEV: scale)
    }

    // MARK: Hanning

    /// np.hanning(4) = [0, 0.75, 0.75, 0] and np.hanning(6) = [0, 0.3455, 0.9045, 0.9045, 0.3455, 0] (0.5 - 0.5 cos(2 pi k / (M - 1))).
    @Test func testHanningValues() {
        let h4 = EELSSpectrumOps.hanning(4)
        #expect(isEqual(h4[0], 0, accuracy: 1e-15) && isEqual(h4[1], 0.75, accuracy: 1e-15) && isEqual(h4[2], 0.75, accuracy: 1e-15) && isEqual(h4[3], 0, accuracy: 1e-15))
        let h6 = EELSSpectrumOps.hanning(6)
        #expect(isEqual(h6[1], 0.5 - 0.5 * cos(2 * Double.pi / 5), accuracy: 1e-15))
        #expect(isEqual(h6[2], 0.5 - 0.5 * cos(4 * Double.pi / 5), accuracy: 1e-15))
        for k in 0..<6 { #expect(isEqual(h6[k], h6[5 - k], accuracy: 1e-15), "symmetric") }
        #expect(EELSSpectrumOps.hanning(1) == [1])
    }

    /// Python's round is half to even: 0.02 * 1225 = 24.5 -> 24, but the floor of 20 holds below 1250 channels anyway; 2250 -> 45.0; 3125 -> 62.5 -> 62.
    @Test func testDefaultTaperWidthUsesPythonRound() {
        #expect(EELSSpectrumOps.defaultTaperChannels(forChannels: 600) == 20)
        #expect(EELSSpectrumOps.defaultTaperChannels(forChannels: 1250) == 25)
        #expect(EELSSpectrumOps.defaultTaperChannels(forChannels: 3125) == 62)
        #expect(EELSSpectrumOps.defaultTaperChannels(forChannels: 3175) == 64, "63.5 rounds to the even 64")
    }

    @Test func testTaperSlicesAndOffsets() throws {
        let ones = [Double](repeating: 1, count: 40)
        let img = try image([ones])
        let both = try EELSSpectrumOps.hanningTaper(img, side: .both, channels: 5, offset: 0)
        let w = EELSSpectrumOps.hanning(10)
        for k in 0..<5 { #expect(isEqual(both.image.counts[k], w[k], accuracy: 1e-15)); #expect(isEqual(both.image.counts[35 + k], w[5 + k], accuracy: 1e-15)) }
        for k in 5..<35 { #expect(both.image.counts[k] == 1) }
        #expect(both.taperedChannels == 5)
        // offset 3 zeroes 3 channels at each end and tapers the next 5
        let off = try EELSSpectrumOps.hanningTaper(img, side: .both, channels: 5, offset: 3)
        for k in 0..<3 { #expect(off.image.counts[k] == 0); #expect(off.image.counts[37 + k] == 0) }
        for k in 0..<5 { #expect(isEqual(off.image.counts[3 + k], w[k], accuracy: 1e-15)); #expect(isEqual(off.image.counts[40 - 3 - 5 + k], w[5 + k], accuracy: 1e-15)) }
        // one side only leaves the other alone
        let left = try EELSSpectrumOps.hanningTaper(img, side: .left, channels: 5)
        #expect(left.image.counts[39] == 1 && left.image.counts[0] == 0)
        #expect(throws: EELSDeconvolutionError.tooFewChannels(40)) { try EELSSpectrumOps.hanningTaper(img, channels: 41) }
        #expect(throws: EELSDeconvolutionError.tooFewChannels(40)) { try EELSSpectrumOps.hanningTaper(img, channels: 0) }
    }

    // MARK: Power-law extrapolation

    /// A counts spectrum that is the channel sum of a power law is continued by the same law to the two-area estimate's own accuracy (0.25 % on a
    /// set like the pins'); here a pure A x^-r sampled per channel: the continuation tracks the exact law within 0.5 %.
    @Test func testAPowerLawIsContinuedByItself() throws {
        let scale = 0.5, offset = 300.0
        let row = (0..<200).map { 1e9 * pow(offset + scale * Double($0), -3.0) * scale }
        let img = try image([row], offset: offset, scale: scale)
        let out = try EELSSpectrumOps.powerLawExtrapolation(img, windowChannels: 20, extrapolationChannels: 50)
        #expect(out.image.channels == 250)
        #expect(Array(out.image.counts[0..<200]) == row, "the original channels are untouched")
        let fit = try #require(out.fits[0])
        #expect(isEqual(fit.r, 3.0, accuracy: 0.01))
        for c in 200..<250 {
            let exact = 1e9 * pow(offset + scale * Double(c), -3.0) * scale
            #expect(abs(out.image.counts[c] - exact) <= 0.005 * exact, "channel \(c)")
        }
    }

    /// A rising spectrum (r <= 0) with fixNegativeR continues with zeros; without it the law is continued (and grows).
    @Test func testFixNegativeRContinuesWithZeros() throws {
        let row = (0..<60).map { 10 + 0.5 * Double($0) }                  // rising: r < 0
        let img = try image([row])
        let fixed = try EELSSpectrumOps.powerLawExtrapolation(img, windowChannels: 20, extrapolationChannels: 10, fixNegativeR: true)
        #expect(fixed.fits[0]!.r < 0)
        #expect(fixed.image.counts[60...].allSatisfy { $0 == 0 })
        let free = try EELSSpectrumOps.powerLawExtrapolation(img, windowChannels: 20, extrapolationChannels: 10)
        #expect(free.image.counts[60] > 0)
    }

    @Test func testAWindowSumThatIsNotPositiveGivesANilFitAndZeros() throws {
        let img = try image([[Double](repeating: 0, count: 60), (0..<60).map { 100 - Double($0) }])
        let out = try EELSSpectrumOps.powerLawExtrapolation(img, windowChannels: 20, extrapolationChannels: 10)
        #expect(out.fits[0] == nil)
        #expect(out.image.counts[60..<70].allSatisfy { $0 == 0 })
        #expect(out.fits[1] != nil)
    }

    @Test func testExtrapolationRefusals() throws {
        let img = try image([[Double](repeating: 1, count: 30)])
        #expect(throws: EELSDeconvolutionError.extrapolationWindowTooWide(window: 31, channels: 30)) { try EELSSpectrumOps.powerLawExtrapolation(img, windowChannels: 31) }
        #expect(throws: EELSDeconvolutionError.self) { try EELSSpectrumOps.powerLawExtrapolation(img, windowChannels: 2) }
        #expect(throws: EELSDeconvolutionError.self) { try EELSSpectrumOps.powerLawExtrapolation(img, extrapolationChannels: 0) }
    }
}
