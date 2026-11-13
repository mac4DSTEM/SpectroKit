//
//  EELSTrapRefusalTests.swift
//  Role: a NaN window, an overflowing size or a too-short spectrum reaching SpectroEELS gives no channel or a refusal, never a trap
//        (macEMSuite/SpectroKit#103). One test per site the review named.
//  Red before: `Int(NaN)` on a dragged background window; a reversed `ClosedRange` from a gap wider than the window; `n + extension` and
//  `c + offset` overflowed; a Savitzky-Golay window longer than the spectrum trapped in `precondition`.
//

import Foundation
import Testing
import SpectroEELS

struct EELSTrapRefusalTests {

    @Test func aWindowThatIsNotANumberOrFarPastTheAxisHasNoChannelOrIsClamped() {
        let nan = ClosedRange<Double>(uncheckedBounds: (lower: .nan, upper: .nan))
        #expect(EdgeWindows.rows(nan, offset: 0, scale: 1, size: 10).isEmpty)
        #expect(EdgeWindows.rows(0...5, offset: 0, scale: .nan, size: 10).isEmpty)
        #expect(EdgeWindows.rows(-1e300...1e300, offset: 0, scale: 1, size: 10) == 0..<10)
        #expect(EdgeWindows.rows(2...4, offset: 0, scale: 1, size: 10) == 2..<5)
        #expect(EdgeWindows.rows(2...4, offset: 0, scale: 1, size: 0).isEmpty)
    }

    @Test func aDefaultBackgroundWindowWithAGapWiderThanItIsOrderedAndANaNOnsetIsNone() {
        #expect(EELSEdgeQuantification.defaultBackgroundWindow(onsetEV: 100, belowOnsetEV: 2, gapEV: 10) == 90...98)
        #expect(EELSEdgeQuantification.defaultBackgroundWindow(onsetEV: .nan) == 0...0)
        #expect(EELSEdgeQuantification.defaultBackgroundWindow(onsetEV: 284) == 234...279)
    }

    private func image(channels: Int = 40) throws -> CoreLossSpectrumImage {
        try CoreLossSpectrumImage(nx: 1, ny: 1, channels: channels, counts: (0..<channels).map { 1000 / Double($0 + 1) },
                                  energyOffsetEV: 100, energyScaleEV: 0.5)
    }

    @Test func anExtrapolationPastIntIsRefused() throws {
        let img = try image()
        #expect(throws: EELSDeconvolutionError.self) {
            try EELSSpectrumOps.powerLawExtrapolation(img, windowChannels: 10, extrapolationChannels: Int.max)
        }
    }

    @Test func aTaperOffsetPastIntIsRefused() throws {
        let img = try image()
        #expect(throws: EELSDeconvolutionError.tooFewChannels(40)) { try EELSSpectrumOps.hanningTaper(img, channels: 5, offset: Int.max) }
        #expect(throws: EELSDeconvolutionError.tooFewChannels(40)) { try EELSSpectrumOps.hanningTaper(img, channels: 30, offset: 11) }
        #expect(try EELSSpectrumOps.hanningTaper(img, channels: 30, offset: 10).taperedChannels == 30)
    }

    @Test func aSavitzkyGolayWindowLongerThanTheSpectrumIsRefused() throws {
        let sg = try SavitzkyGolayFirstDerivative(windowLength: 7, polynomialOrder: 2, delta: 1)
        let row: [Double] = [1, 2, 3]
        row.withUnsafeBufferPointer { f in
            #expect(throws: EELSThicknessError.self) { try sg.edgeTable(nx: 1, ny: 1, row: { _ in f }) }
            var out = [Double](repeating: 0, count: 3)
            _ = out.withUnsafeMutableBufferPointer { o in
                #expect(throws: EELSThicknessError.self) { try sg.apply(f, into: o) }
            }
        }
    }
}
