//
//  ThicknessEdgeCaseTests.swift
//  Role: The cases the registration names as edge cases (a search window of fewer than 10 channels, a pixel with no inflexion,
//        I_0 = 0, a zero-loss spectrum image of the wrong shape) and the rest of the public contract: input validation, the
//        per-pixel and fixed rules, sigma_counting's formula, the lambda sources, the zero-loss centre, cancellation, layout.
//        One rule per test; a pixel the method cannot answer is nil with its reason, never a clipped or invented number.
//

import Foundation
import Testing
import SpectroEELS
import SpectroCore

struct ThicknessEdgeCaseTests {

    private func image(nx: Int = 1, ny: Int = 1, channels: Int, offset: Double = 0, scale: Double = 1, _ counts: [Double]) throws -> LowLossSpectrumImage {
        try LowLossSpectrumImage(nx: nx, ny: ny, channels: channels, counts: counts, energyOffsetEV: offset, energyScaleEV: scale)
    }

    // MARK: search window

    /// exSpy `_eels.py:713-714`: a search range of fewer than 10 channels is an error; exactly 10 is allowed.
    @Test func testASearchWindowShorterThanTenChannelsThrows() throws {
        let planted = try EELSFixtures.image("planted-noiseless")                   // [1.0, 1.0 + window) at 0.05 eV: window 0.45 is 9 channels
        if let error = #expect(throws: (any Error).self, performing: { try EELSThickness.logRatio(planted, threshold: .estimated(window: 0.45)) }) {
            #expect((error as? EELSThicknessError) == .searchWindowTooShort(channels: 9))
        }
        if let error = #expect(throws: (any Error).self, performing: { try EELSThickness.logRatio(planted, threshold: .estimated(window: 0)) }) {
            #expect((error as? EELSThicknessError) == .searchWindowTooShort(channels: 0))
        }
        let ten = try EELSThickness.logRatio(planted, threshold: .estimated(window: 0.5))              // exactly 10 channels
        #expect(ten.pixels.count == 10)
        let lineScan = try EELSFixtures.image("exspy-linescan")                      // 0.5 eV per channel: window 4.5 is 9, window 5 is 10
        if let error = #expect(throws: (any Error).self, performing: { try EELSThickness.logRatio(lineScan, threshold: .estimated(window: 4.5)) }) {
            #expect((error as? EELSThicknessError) == .searchWindowTooShort(channels: 9))
        }
        #expect(throws: Never.self) { try EELSThickness.logRatio(lineScan, threshold: .estimated(window: 5)) }
    }

    @Test func testSearchWindowAndSavitzkyGolayInputsAreValidated() throws {
        let planted = try EELSFixtures.image("planted-noiseless")
        for bad in [ThresholdRule.estimated(window: -1), .estimated(window: .nan), .estimated(start: .nan), .estimated(window: .infinity)] {
            if let error = #expect(throws: (any Error).self, performing: { try EELSThickness.logRatio(planted, threshold: bad) }) {
                if case EELSThicknessError.invalidSearchWindow = error {} else { Issue.record("\(error)") }
            }
        }
        // a Savitzky-Golay window longer than the 10 channels searched (mode "interp" needs window_length <= n) / unsupported windows
        if let error = #expect(throws: (any Error).self, performing: { try EELSThickness.logRatio(planted, threshold: .estimated(window: 0.5, windowLength: 11)) }) {
            if case EELSThicknessError.invalidSavitzkyGolay = error {} else { Issue.record("\(error)") }
        }
        #expect(throws: Never.self) { try EELSThickness.logRatio(planted, threshold: .estimated(window: 0.5, windowLength: 9)) }
        for wl in [4, 2, -1] {
            #expect(throws: (any Error).self, "window \(wl)") { try EELSThickness.logRatio(planted, threshold: .estimated(windowLength: wl)) }
        }
        #expect(throws: (any Error).self) { try EELSThickness.logRatio(planted, threshold: .estimated(polynomialOrder: 5)) }
        if let error = #expect(throws: (any Error).self, performing: { try EELSThickness.logRatio(planted, threshold: .estimated(tolerance: -1)) }) {
            #expect((error as? EELSThicknessError) == .invalidTolerance(-1))
        }
        #expect(throws: (any Error).self) { try EELSThickness.logRatio(planted, threshold: .estimated(tolerance: .nan)) }
    }

    /// `start` and `window` bound the search (exSpy `_eels.py:712`): a search from 2 eV on cannot return a threshold below 2 eV or
    /// from 7 eV on; and a caller's `tol` equal to the image's own gives the same thresholds as no `tol`.
    @Test func testStartWindowAndAGivenTolBehaveAsExSpys() throws {
        let planted = try EELSFixtures.image("planted-noiseless")
        let narrow = try EELSThickness.logRatio(planted, threshold: .estimated(window: 5, start: 2))
        for p in narrow.pixels {
            if let e = p.thresholdEV { #expect(e >= 2.0 - 1e-9 && e < 7.0, "threshold \(e) outside the search [2, 7)") } else { #expect(p.unavailable == .noInflexionFound) }
        }
        let normal = try EELSThickness.logRatio(planted, threshold: .estimated())
        #expect(narrow.pixels.map(\.thresholdChannel) != normal.pixels.map(\.thresholdChannel))
        let withTol = try EELSThickness.logRatio(planted, threshold: .estimated(tolerance: normal.estimatedTolerance))
        #expect(withTol.pixels == normal.pixels)
        let looser = try EELSThickness.logRatio(planted, threshold: .estimated(tolerance: normal.estimatedTolerance.orFail() * 2))
        #expect(looser.pixels.map(\.thresholdChannel) != normal.pixels.map(\.thresholdChannel), "a larger tol qualifies earlier channels")
    }

    /// exSpy crops `isig[min:max]` by INTEGER channels, so the cropped axis starts at that channel's energy, not at `start`: a start
    /// of 1.02 eV (rounds to channel 220, as 1.0 does) gives the same range and the same threshold energies, bit for bit.
    @Test func testTheThresholdEnergyComesFromTheCroppedChannelNotFromStart() throws {
        let planted = try EELSFixtures.image("planted-noiseless")
        let a = try EELSThickness.logRatio(planted, threshold: .estimated(start: 1.0))
        let b = try EELSThickness.logRatio(planted, threshold: .estimated(start: 1.02))
        #expect(a.pixels.map(\.thresholdEV) == b.pixels.map(\.thresholdEV))
        #expect(a.pixels.map(\.thresholdChannel) == b.pixels.map(\.thresholdChannel))
        #expect(a.pixels.allSatisfy { $0.thresholdEV.orFail() == Double(($0.thresholdChannel.orFail() - 220)) * 0.05 + 1.0 || abs($0.thresholdEV.orFail() - (1.0 + 0.05 * Double($0.thresholdChannel.orFail() - 220))) < 1e-12 })
    }

    // MARK: no inflexion

    /// A pixel whose derivative is already at or below `tol` at the first channel of the search range has no inflexion (exSpy marks
    /// it NaN, `_eels.py:730-735`): nil with its reason, while its neighbour keeps its threshold. `tol` is the image's: the flat
    /// pixel does not move it.
    @Test func testAPixelWithNoInflexionIsNilWithItsReason() throws {
        let all = try EELSFixtures.doubles("planted-noiseless.f64")
        let nch = 3400
        let good = Array(all[(4 * nch)..<(5 * nch)])                                 // tau = 0.5
        let flat = [Double](repeating: 5, count: nch)
        let img = try image(nx: 2, ny: 1, channels: nch, offset: -10, scale: 0.05, good + flat)
        let map = try EELSThickness.logRatio(img, threshold: .estimated())
        let alone = try EELSThickness.logRatio(try image(channels: nch, offset: -10, scale: 0.05, good), threshold: .estimated())
        #expect(map.pixels[0].tOverLambda != nil)
        #expect(map.pixels[0].thresholdEV != nil)
        let bad = map.pixels[1]
        #expect(bad.tOverLambda == nil); #expect(bad.sigmaCounting == nil); #expect(bad.thicknessNM == nil)
        #expect(bad.thresholdEV == nil); #expect(bad.thresholdChannel == nil); #expect(bad.i0 == nil)
        #expect(bad.unavailable == .noInflexionFound)
        #expect(bad.iTotal == (5 * Double(nch)))
        #expect(bad.zlpCentreEV == -10, "a flat spectrum's first maximum is channel 0")
        let badReason = bad.unavailable?.description ?? ""
        #expect(!badReason.isEmpty)
        // the same pixel alone sets tol from itself; with the flat pixel beside it tol is that of the good pixel
        #expect(map.estimatedTolerance == alone.estimatedTolerance)
    }

    /// A caller's `tol` below every |derivative|: no channel qualifies, so every pixel is nil (argmax of all-False is 0 in exSpy).
    @Test func testATolBelowEveryDerivativeLeavesEveryPixelWithoutInflexion() throws {
        let map = try EELSThickness.logRatio(try EELSFixtures.image("planted-noiseless"), threshold: .estimated(tolerance: 1e-3))
        #expect(map.pixels.allSatisfy { $0.tOverLambda == nil && $0.unavailable == .noInflexionFound })
        #expect(map.estimatedTolerance == (1e-3))
        // and a huge tol qualifies the first channel, which is "no inflexion" too (index 0)
        let huge = try EELSThickness.logRatio(try EELSFixtures.image("planted-noiseless"), threshold: .estimated(tolerance: 1e12))
        #expect(huge.pixels.allSatisfy { $0.unavailable == .noInflexionFound })
    }

    // MARK: I_0 and I_t that cannot give a logarithm

    @Test func testZeroLossIntensityOfZeroIsNilWithItsReason() throws {
        // nothing before the threshold channel: I_0 = 0
        let img = try image(channels: 20, offset: 0, scale: 1, [Double](repeating: 1, count: 20))
        let atFirstChannel = try EELSThickness.logRatio(img, threshold: .fixed(0))
        #expect(atFirstChannel.pixels[0].thresholdChannel == 0)
        #expect(atFirstChannel.pixels[0].i0 == 0)
        #expect(atFirstChannel.pixels[0].tOverLambda == nil)
        #expect(atFirstChannel.pixels[0].unavailable == .zeroLossIntensityNotPositive)
        #expect(atFirstChannel.pixels[0].iTotal == 20)
        // zero counts where the zero-loss peak should be
        let zeros = try image(channels: 20, offset: 0, scale: 1, [Double](repeating: 0, count: 10) + [Double](repeating: 3, count: 10))
        let m = try EELSThickness.logRatio(zeros, threshold: .fixed(5))
        #expect(m.pixels[0].i0 == 0); #expect(m.pixels[0].unavailable == .zeroLossIntensityNotPositive)
        #expect(m.pixels[0].thicknessNM == nil)
        // negative I_0 (background-subtracted counts)
        let negative = try image(channels: 20, offset: 0, scale: 1, [Double](repeating: -1, count: 10) + [Double](repeating: 3, count: 10))
        #expect((try EELSThickness.logRatio(negative, threshold: .fixed(5)).pixels[0].unavailable) == .zeroLossIntensityNotPositive)
        // the same through the zero-loss spectrum route
        let zlp = try image(channels: 8, offset: 0, scale: 1, [Double](repeating: 0, count: 8))
        let viaZlp = try EELSThickness.logRatio(img, zeroLoss: zlp)
        #expect(viaZlp.pixels[0].unavailable == .zeroLossIntensityNotPositive)
        #expect(viaZlp.pixels[0].i0 == 0)
        // and through a per-pixel threshold
        #expect((try EELSThickness.logRatio(img, threshold: .perPixel([0])).pixels[0].unavailable) == .zeroLossIntensityNotPositive)
    }

    @Test func testANonPositiveTotalIsNilAndATotalBelowTheZeroLossIsReportedNotClipped() throws {
        // I_0 = 5 * 100 = 500 > 0 and I_t = 500 - 15 * 40 < 0: no logarithm
        let negativeTotal = try image(channels: 20, offset: 0, scale: 1, [Double](repeating: 100, count: 5) + [Double](repeating: -40, count: 15))
        let a = try EELSThickness.logRatio(negativeTotal, threshold: .fixed(5)).pixels[0]
        #expect(a.unavailable == .totalIntensityNotPositive); #expect(a.tOverLambda == nil)
        // I_t = 500 - 15 * 30 = 50 < I_0 = 500: t/lambda = ln(50/500) < 0, reported as is; sigma needs nested counts
        let below = try image(channels: 20, offset: 0, scale: 1, [Double](repeating: 100, count: 5) + [Double](repeating: -30, count: 15))
        let b = try EELSThickness.logRatio(below, threshold: .fixed(5)).pixels[0]
        #expect(b.unavailable == nil)
        #expect(isEqual(b.tOverLambda.orFail(), log(50.0 / 500.0), accuracy: 1e-15))
        #expect(b.tOverLambda.orFail() < 0)
        #expect(b.sigmaCounting == nil); #expect(b.sigmaUnavailable == .totalBelowZeroLoss)
        let bReason = b.sigmaUnavailable?.description ?? ""
        #expect(!bReason.isEmpty)
    }

    // MARK: zero-loss spectrum image

    @Test func testAZeroLossImageOfTheWrongShapeIsRefused() throws {
        let img = try image(nx: 3, ny: 2, channels: 10, [Double](repeating: 1, count: 60))
        let wrongNx = try image(nx: 2, ny: 2, channels: 10, [Double](repeating: 1, count: 40))
        let wrongNy = try image(nx: 3, ny: 1, channels: 10, [Double](repeating: 1, count: 30))
        let transposed = try image(nx: 2, ny: 3, channels: 10, [Double](repeating: 1, count: 60))
        for z in [wrongNx, wrongNy, transposed] {
            if let error = #expect(throws: (any Error).self, performing: { try EELSThickness.logRatio(img, zeroLoss: z) }) {
                #expect((error as? EELSThicknessError) == .zeroLossShapeMismatch(expectedNx: 3, expectedNy: 2, gotNx: z.nx, gotNy: z.ny))
            }
        }
        // the channel count may differ: only the sum is used
        let otherChannels = try image(nx: 3, ny: 2, channels: 4, [Double](repeating: 2, count: 24))
        let m = try EELSThickness.logRatio(img, zeroLoss: otherChannels)
        #expect(m.pixels.allSatisfy { $0.i0 == 8 && $0.iTotal == 10 })
        #expect(m.zeroLoss == .zeroLossSpectrum)
        #expect(m.estimatedTolerance == nil)
    }

    /// With a zero-loss image the threshold rule is not used (exSpy: `zlp` takes precedence, `_eels.py:810-813`), even a rule that would throw.
    @Test func testZeroLossImageTakesPrecedenceOverTheThresholdRule() throws {
        let img = try image(nx: 2, ny: 1, channels: 10, [Double](repeating: 1, count: 20))
        let zlp = try image(nx: 2, ny: 1, channels: 10, [Double](repeating: 1, count: 20))
        #expect(throws: Never.self) { try EELSThickness.logRatio(img, threshold: .estimated(window: 0), zeroLoss: zlp) }
        #expect(throws: Never.self) { try EELSThickness.logRatio(img, threshold: .perPixel([1]), zeroLoss: zlp) }
    }

    // MARK: input validation

    @Test func testInputValidation() {
        func make(_ nx: Int, _ ny: Int, _ ch: Int, _ n: Int, _ off: Double = 0, _ scale: Double = 1, _ fill: Double = 1) throws -> LowLossSpectrumImage {
            try LowLossSpectrumImage(nx: nx, ny: ny, channels: ch, counts: [Double](repeating: fill, count: n), energyOffsetEV: off, energyScaleEV: scale)
        }
        if let error = #expect(throws: (any Error).self, performing: { try make(2, 2, 5, 19) }) { #expect((error as? EELSThicknessError) == .invalidShape(nx: 2, ny: 2, channels: 5, counts: 19)) }
        #expect(throws: (any Error).self) { try make(0, 2, 5, 0) }
        #expect(throws: (any Error).self) { try make(2, 2, 0, 0) }
        if let error = #expect(throws: (any Error).self, performing: { try make(1, 1, 5, 5, 0, 0) }) { #expect((error as? EELSThicknessError) == .invalidEnergyAxis(offsetEV: 0, scaleEV: 0)) }
        #expect(throws: (any Error).self) { try make(1, 1, 5, 5, 0, -0.05) }
        #expect(throws: (any Error).self) { try make(1, 1, 5, 5, .nan, 0.05) }
        #expect(throws: (any Error).self) { try make(1, 1, 5, 5, 0, .infinity) }
        if let error = #expect(throws: (any Error).self, performing: { try make(1, 1, 5, 5, 0, 1, .nan) }) { #expect((error as? EELSThicknessError) == .nonFiniteCounts(pixel: 0)) }
        if let error = #expect(throws: (any Error).self, performing: { try LowLossSpectrumImage(nx: 2, ny: 1, channels: 3, counts: [1, 1, 1, 1, Double.infinity, 1] as [Double], energyOffsetEV: 0, energyScaleEV: 1) }) {
            #expect((error as? EELSThicknessError) == .nonFiniteCounts(pixel: 1))
        }
    }

    /// Single-precision counts are widened exactly and give the same map.
    @Test func testFloatCountsGiveTheSameMap() throws {
        let doubles = (0..<60).map { Double(($0 * 37) % 101) + 1 }
        let d = try image(nx: 2, ny: 1, channels: 30, offset: -5, scale: 0.5, doubles)
        let f = try LowLossSpectrumImage(nx: 2, ny: 1, channels: 30, counts: doubles.map { Float($0) }, energyOffsetEV: -5, energyScaleEV: 0.5)
        #expect(d.counts == f.counts)
        #expect((try EELSThickness.logRatio(d, threshold: .fixed(2)).pixels) == (try EELSThickness.logRatio(f, threshold: .fixed(2)).pixels))
    }

    // MARK: per-pixel and fixed rules

    @Test func testPerPixelThresholds() throws {
        let img = try image(nx: 3, ny: 1, channels: 20, offset: 0, scale: 1, (0..<60).map { Double($0 % 20) + 1 })
        if let error = #expect(throws: (any Error).self, performing: { try EELSThickness.logRatio(img, threshold: .perPixel([1, 2])) }) {
            #expect((error as? EELSThicknessError) == .perPixelThresholdCount(expected: 3, got: 2))
        }
        let m = try EELSThickness.logRatio(img, threshold: .perPixel([5, .nan, 1e6]))
        #expect(m.pixels[0].thresholdChannel == 5); #expect(m.pixels[0].i0 == 15)
        #expect(m.pixels[1].unavailable == .thresholdNotANumber); #expect(m.pixels[1].thresholdChannel == nil)
        #expect(m.pixels[2].unavailable == .thresholdOutsideAxis); #expect(m.pixels[2].thresholdEV == 1e6)
        #expect(m.pixels[2].i0 == nil)
        if case .threshold(.perPixel(let echoed)) = m.zeroLoss { #expect(echoed.count == 3); #expect(echoed[0] == 5); #expect(echoed[1].isNaN) } else { Issue.record("the rule is echoed") }
        // per-pixel thresholds equal to the estimated ones reproduce the estimated map
        let planted = try EELSFixtures.image("planted-noiseless")
        let estimated = try EELSThickness.logRatio(planted, threshold: .estimated())
        let again = try EELSThickness.logRatio(planted, threshold: .perPixel(estimated.pixels.map { $0.thresholdEV.orFail() }))
        #expect(again.pixels.map(\.tOverLambda) == estimated.pixels.map(\.tOverLambda))
        #expect(again.pixels.map(\.thresholdChannel) == estimated.pixels.map(\.thresholdChannel))
    }

    /// A fixed threshold is reported as given (4.52 eV), and used as the channel it rounds to (290, the same as 4.5 eV).
    @Test func testAFixedThresholdIsReportedAsGivenAndRoundedToAChannel() throws {
        let planted = try EELSFixtures.image("planted-noiseless")
        let on = try EELSThickness.logRatio(planted, threshold: .fixed(4.5))
        let off = try EELSThickness.logRatio(planted, threshold: .fixed(4.52))
        #expect(off.pixels.allSatisfy { $0.thresholdEV == 4.52 && $0.thresholdChannel == 290 })
        #expect(on.pixels.allSatisfy { $0.thresholdEV == 4.5 && $0.thresholdChannel == 290 })
        #expect(on.pixels.map(\.i0) == off.pixels.map(\.i0))
        #expect(on.pixels.map(\.tOverLambda) == off.pixels.map(\.tOverLambda))
    }

    @Test func testFixedThresholdAtOrBeyondTheEndOfTheAxisGivesZeroThickness() throws {
        let img = try image(channels: 20, offset: 0, scale: 1, (0..<20).map { Double($0) + 1 })
        let m = try EELSThickness.logRatio(img, threshold: .fixed(1e6)).pixels[0]
        #expect(m.thresholdChannel == 20); #expect(m.i0 == m.iTotal)
        #expect(m.tOverLambda == 0); #expect(m.sigmaCounting == 0)
        #expect(throws: (any Error).self) { try EELSThickness.logRatio(img, threshold: .fixed(-5)) }
        #expect(throws: (any Error).self) { try EELSThickness.logRatio(img, threshold: .fixed(.nan)) }
    }

    // MARK: sigma_counting and the zero-loss centre

    @Test func testSigmaCountingIsTheSquareRootOfOneOverI0MinusOneOverIt() throws {
        let img = try image(channels: 8, offset: 0, scale: 1, [400, 300, 100, 40, 30, 20, 8, 2])      // I_0 = 800 at stop 3, I_t = 900
        let p = try EELSThickness.logRatio(img, threshold: .fixed(3)).pixels[0]
        #expect(p.i0 == 800); #expect(p.iTotal == 900)
        #expect(isEqual(p.sigmaCounting.orFail(), (1.0 / 800 - 1.0 / 900).squareRoot(), accuracy: 1e-18))
        #expect(isEqual(p.sigmaCounting.orFail(), 0.011785113, accuracy: 1e-9))                                // not sqrt(1/800 + 1/900) = 0.048591
        #expect(isEqual(p.tOverLambda.orFail(), log(900.0 / 800.0), accuracy: 1e-15))
        #expect(p.tOverLambda.orFail() > 0)                                                      // ln(I_t / I_0), not the inverse
    }

    /// The energy of the spectrum's first maximum (numpy argmax takes the first of equal maxima).
    @Test func testZeroLossCentreIsTheEnergyOfTheFirstMaximum() throws {
        let img = try image(nx: 2, ny: 1, channels: 6, offset: -1.5, scale: 0.5, [1, 5, 9, 9, 2, 1, 0, 3, 4, 8, 2, 1])
        let m = try EELSThickness.logRatio(img, threshold: .fixed(0))
        #expect(isEqual(m.pixels[0].zlpCentreEV, -0.5, accuracy: 1e-15))                                // channel 2: -1.5 + 0.5 * 2
        #expect(isEqual(m.pixels[1].zlpCentreEV, 0.0, accuracy: 1e-15))                                 // pixel 1 = [0, 3, 4, 8, 2, 1]: channel 3
        let planted = try EELSThickness.logRatio(try EELSFixtures.image("planted-noiseless"), threshold: .fixed(2.5))
        #expect(planted.pixels.allSatisfy { abs($0.zlpCentreEV) < 1e-12 })
    }

    // MARK: lambda sources

    @Test func testMeanFreePathSources() throws {
        let img = try image(channels: 8, offset: 0, scale: 1, [400, 300, 100, 40, 30, 20, 8, 2])
        let t = log(900.0 / 800.0)
        let rho = 2.70, e0 = 200.0, alpha = 10.0, beta = 20.0
        let lambda = InelasticMeanFreePath.iakoubovskii(density: rho, beamEnergyKeV: e0)
        let correction = InelasticMeanFreePath.angularCorrection(density: rho, beamEnergyKeV: e0, convergenceMrad: alpha, collectionMrad: beta)
        #expect(isEqual(lambda, 143.48821846111915, accuracy: 1e-11))
        #expect(isEqual(correction, 1.0634407457337407, accuracy: 1e-14))

        let none = try EELSThickness.logRatio(img, threshold: .fixed(3))
        #expect(none.pixels[0].thicknessNM == nil); #expect(none.meanFreePathNM == nil); #expect(none.angularCorrection == nil)
        // lambda only: no correction
        let given = try EELSThickness.logRatio(img, threshold: .fixed(3), meanFreePath: .given(120))
        #expect(isEqual(given.pixels[0].thicknessNM.orFail(), t * 120, accuracy: 1e-13))
        #expect(given.angularCorrection == nil); #expect(given.meanFreePathNM == 120)
        // density: corrected t/lambda times Iakoubovskii's lambda
        let density = try EELSThickness.logRatio(img, threshold: .fixed(3), meanFreePath: .iakoubovskii(density: rho, beamEnergyKeV: e0, convergenceMrad: alpha, collectionMrad: beta))
        #expect(isEqual(density.pixels[0].thicknessNM.orFail(), t * correction * lambda, accuracy: 1e-12))
        #expect(density.angularCorrection == correction); #expect(density.meanFreePathNM == lambda)
        // both: the GIVEN lambda is still multiplied by the correction (exSpy _eels.py:828-838)
        let both = try EELSThickness.logRatio(img, threshold: .fixed(3), meanFreePath: .givenWithAngularCorrection(120, density: rho, beamEnergyKeV: e0, convergenceMrad: alpha, collectionMrad: beta))
        #expect(isEqual(both.pixels[0].thicknessNM.orFail(), t * correction * 120, accuracy: 1e-12))
        #expect(!isEqual(both.pixels[0].thicknessNM.orFail(), given.pixels[0].thicknessNM.orFail(), accuracy: 1e-3))
        // the t/lambda field itself is never multiplied by the correction
        #expect(isEqual(both.pixels[0].tOverLambda.orFail(), t, accuracy: 1e-15))
        #expect(density.pixels[0].tOverLambda == given.pixels[0].tOverLambda)
    }

    @Test func testInvalidMeanFreePathSourcesAreRefused() throws {
        let img = try image(channels: 8, offset: 0, scale: 1, [400, 300, 100, 40, 30, 20, 8, 2])
        let bad: [MeanFreePathSource] = [
            .given(0), .given(-5), .given(.nan),
            .iakoubovskii(density: 0, beamEnergyKeV: 200, convergenceMrad: 10, collectionMrad: 20),
            .iakoubovskii(density: 2.7, beamEnergyKeV: -200, convergenceMrad: 10, collectionMrad: 20),
            .iakoubovskii(density: 2.7, beamEnergyKeV: 200, convergenceMrad: -1, collectionMrad: 20),
            .givenWithAngularCorrection(0, density: 2.7, beamEnergyKeV: 200, convergenceMrad: 10, collectionMrad: 20),
            .givenWithAngularCorrection(120, density: .nan, beamEnergyKeV: 200, convergenceMrad: 10, collectionMrad: 20),
        ]
        for source in bad {
            if let error = #expect(throws: (any Error).self, "\(source)", performing: { try EELSThickness.logRatio(img, threshold: .fixed(3), meanFreePath: source) }) {
                if case EELSThicknessError.invalidMeanFreePath = error {} else { Issue.record("\(error)") }
            }
        }
    }

    // MARK: layout, metadata, cancellation

    /// counts[(y * nx + x) * channels + c]: pixel (x, y) of a 3 x 2 image is found at y * 3 + x.
    @Test func testPixelLayoutIsRowMajorInYThenXThenChannel() throws {
        var counts = [Double]()
        for y in 0..<2 { for x in 0..<3 { for c in 0..<4 { counts.append(Double(100 * y + 10 * x + c + 1)) } } }
        let m = try EELSThickness.logRatio(try image(nx: 3, ny: 2, channels: 4, counts), threshold: .fixed(2))
        #expect(m.nx == 3); #expect(m.ny == 2); #expect(m.pixels.count == 6)
        for y in 0..<2 { for x in 0..<3 {
            let base = Double(100 * y + 10 * x)
            #expect(m[x, y].iTotal == (4 * base + 10), "pixel (\(x), \(y))")
            #expect(m[x, y].i0 == (2 * base + 3))
        } }
    }

    @Test func testResultSaysHowItWasMade() throws {
        let planted = try EELSFixtures.image("planted-noiseless")
        let est = try EELSThickness.logRatio(planted)
        #expect(est.method == "log-ratio, exSpy 7185a4d1"); #expect(est.method == EELSThickness.methodName)
        #expect(est.validation == "none")
        #expect(est.zeroLoss == .threshold(.estimated()))
        #expect(est.estimatedTolerance != nil)
        let fixed = try EELSThickness.logRatio(planted, threshold: .fixed(4.5))
        #expect(fixed.zeroLoss == .threshold(.fixed(4.5))); #expect(fixed.estimatedTolerance == nil); #expect(fixed.validation == "none")
        #expect(ThresholdRule.estimated() == .estimated(window: 10, start: 1, windowLength: 5, polynomialOrder: 3, tolerance: nil))
    }

    @Test func testCancellationAndProgress() throws {
        let planted = try EELSFixtures.image("planted-noiseless")
        if let error = #expect(throws: (any Error).self, performing: { try EELSThickness.logRatio(planted, cancelled: { true }) }) { #expect(error is SpectroCancelled) }
        if let error = #expect(throws: (any Error).self, performing: { try EELSThickness.logRatio(planted, threshold: .fixed(2.5), cancelled: { true }) }) { #expect(error is SpectroCancelled) }
        final class Log: @unchecked Sendable { let lock = NSLock(); var values = [Double](); func add(_ v: Double) { lock.lock(); values.append(v); lock.unlock() } }
        let log = Log()
        _ = try EELSThickness.logRatio(planted, progress: { log.add($0) })
        #expect(log.values.last == 1)
        #expect(log.values == log.values.sorted(), "progress is monotone")
        #expect(log.values.allSatisfy { $0 >= 0 && $0 <= 1 })
    }
}
