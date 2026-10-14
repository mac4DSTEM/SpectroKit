//
//  ThicknessEdgeCaseTests.swift
//  Role: The cases the registration names as edge cases (a search window of fewer than 10 channels, a pixel with no inflexion,
//        I_0 = 0, a zero-loss spectrum image of the wrong shape) and the rest of the public contract: input validation, the
//        per-pixel and fixed rules, sigma_counting's formula, the lambda sources, the zero-loss centre, cancellation, layout.
//        One rule per test; a pixel the method cannot answer is nil with its reason, never a clipped or invented number.
//

import Foundation
import XCTest
import SpectroEELS
import SpectroCore

final class ThicknessEdgeCaseTests: XCTestCase {

    private func image(nx: Int = 1, ny: Int = 1, channels: Int, offset: Double = 0, scale: Double = 1, _ counts: [Double]) throws -> LowLossSpectrumImage {
        try LowLossSpectrumImage(nx: nx, ny: ny, channels: channels, counts: counts, energyOffsetEV: offset, energyScaleEV: scale)
    }

    // MARK: search window

    /// exSpy `_eels.py:713-714`: a search range of fewer than 10 channels is an error; exactly 10 is allowed.
    func testASearchWindowShorterThanTenChannelsThrows() throws {
        let planted = try EELSFixtures.image("planted-noiseless")                   // [1.0, 1.0 + window) at 0.05 eV: window 0.45 is 9 channels
        XCTAssertThrowsError(try EELSThickness.logRatio(planted, threshold: .estimated(window: 0.45))) {
            XCTAssertEqual($0 as? EELSThicknessError, .searchWindowTooShort(channels: 9))
        }
        XCTAssertThrowsError(try EELSThickness.logRatio(planted, threshold: .estimated(window: 0))) {
            XCTAssertEqual($0 as? EELSThicknessError, .searchWindowTooShort(channels: 0))
        }
        let ten = try EELSThickness.logRatio(planted, threshold: .estimated(window: 0.5))              // exactly 10 channels
        XCTAssertEqual(ten.pixels.count, 10)
        let lineScan = try EELSFixtures.image("exspy-linescan")                      // 0.5 eV per channel: window 4.5 is 9, window 5 is 10
        XCTAssertThrowsError(try EELSThickness.logRatio(lineScan, threshold: .estimated(window: 4.5))) {
            XCTAssertEqual($0 as? EELSThicknessError, .searchWindowTooShort(channels: 9))
        }
        XCTAssertNoThrow(try EELSThickness.logRatio(lineScan, threshold: .estimated(window: 5)))
    }

    func testSearchWindowAndSavitzkyGolayInputsAreValidated() throws {
        let planted = try EELSFixtures.image("planted-noiseless")
        for bad in [ThresholdRule.estimated(window: -1), .estimated(window: .nan), .estimated(start: .nan), .estimated(window: .infinity)] {
            XCTAssertThrowsError(try EELSThickness.logRatio(planted, threshold: bad)) {
                guard case EELSThicknessError.invalidSearchWindow = $0 else { return XCTFail("\($0)") }
            }
        }
        // a Savitzky-Golay window longer than the 10 channels searched (mode "interp" needs window_length <= n) / unsupported windows
        XCTAssertThrowsError(try EELSThickness.logRatio(planted, threshold: .estimated(window: 0.5, windowLength: 11))) {
            guard case EELSThicknessError.invalidSavitzkyGolay = $0 else { return XCTFail("\($0)") }
        }
        XCTAssertNoThrow(try EELSThickness.logRatio(planted, threshold: .estimated(window: 0.5, windowLength: 9)))
        for wl in [4, 2, -1] {
            XCTAssertThrowsError(try EELSThickness.logRatio(planted, threshold: .estimated(windowLength: wl)), "window \(wl)")
        }
        XCTAssertThrowsError(try EELSThickness.logRatio(planted, threshold: .estimated(polynomialOrder: 5)))
        XCTAssertThrowsError(try EELSThickness.logRatio(planted, threshold: .estimated(tolerance: -1))) {
            XCTAssertEqual($0 as? EELSThicknessError, .invalidTolerance(-1))
        }
        XCTAssertThrowsError(try EELSThickness.logRatio(planted, threshold: .estimated(tolerance: .nan)))
    }

    /// `start` and `window` bound the search (exSpy `_eels.py:712`): a search from 2 eV on cannot return a threshold below 2 eV or
    /// from 7 eV on; and a caller's `tol` equal to the image's own gives the same thresholds as no `tol`.
    func testStartWindowAndAGivenTolBehaveAsExSpys() throws {
        let planted = try EELSFixtures.image("planted-noiseless")
        let narrow = try EELSThickness.logRatio(planted, threshold: .estimated(window: 5, start: 2))
        for p in narrow.pixels {
            if let e = p.thresholdEV { XCTAssertTrue(e >= 2.0 - 1e-9 && e < 7.0, "threshold \(e) outside the search [2, 7)") } else { XCTAssertEqual(p.unavailable, .noInflexionFound) }
        }
        let normal = try EELSThickness.logRatio(planted, threshold: .estimated())
        XCTAssertNotEqual(narrow.pixels.map(\.thresholdChannel), normal.pixels.map(\.thresholdChannel))
        let withTol = try EELSThickness.logRatio(planted, threshold: .estimated(tolerance: normal.estimatedTolerance))
        XCTAssertEqual(withTol.pixels, normal.pixels)
        let looser = try EELSThickness.logRatio(planted, threshold: .estimated(tolerance: normal.estimatedTolerance.orFail() * 2))
        XCTAssertNotEqual(looser.pixels.map(\.thresholdChannel), normal.pixels.map(\.thresholdChannel), "a larger tol qualifies earlier channels")
    }

    /// exSpy crops `isig[min:max]` by INTEGER channels, so the cropped axis starts at that channel's energy, not at `start`: a start
    /// of 1.02 eV (rounds to channel 220, as 1.0 does) gives the same range and the same threshold energies, bit for bit.
    func testTheThresholdEnergyComesFromTheCroppedChannelNotFromStart() throws {
        let planted = try EELSFixtures.image("planted-noiseless")
        let a = try EELSThickness.logRatio(planted, threshold: .estimated(start: 1.0))
        let b = try EELSThickness.logRatio(planted, threshold: .estimated(start: 1.02))
        XCTAssertEqual(a.pixels.map(\.thresholdEV), b.pixels.map(\.thresholdEV))
        XCTAssertEqual(a.pixels.map(\.thresholdChannel), b.pixels.map(\.thresholdChannel))
        XCTAssertTrue(a.pixels.allSatisfy { $0.thresholdEV.orFail() == Double(($0.thresholdChannel.orFail() - 220)) * 0.05 + 1.0 || abs($0.thresholdEV.orFail() - (1.0 + 0.05 * Double($0.thresholdChannel.orFail() - 220))) < 1e-12 })
    }

    // MARK: no inflexion

    /// A pixel whose derivative is already at or below `tol` at the first channel of the search range has no inflexion (exSpy marks
    /// it NaN, `_eels.py:730-735`): nil with its reason, while its neighbour keeps its threshold. `tol` is the image's: the flat
    /// pixel does not move it.
    func testAPixelWithNoInflexionIsNilWithItsReason() throws {
        let all = try EELSFixtures.doubles("planted-noiseless.f64")
        let nch = 3400
        let good = Array(all[(4 * nch)..<(5 * nch)])                                 // tau = 0.5
        let flat = [Double](repeating: 5, count: nch)
        let img = try image(nx: 2, ny: 1, channels: nch, offset: -10, scale: 0.05, good + flat)
        let map = try EELSThickness.logRatio(img, threshold: .estimated())
        let alone = try EELSThickness.logRatio(try image(channels: nch, offset: -10, scale: 0.05, good), threshold: .estimated())
        XCTAssertNotNil(map.pixels[0].tOverLambda)
        XCTAssertNotNil(map.pixels[0].thresholdEV)
        let bad = map.pixels[1]
        XCTAssertNil(bad.tOverLambda); XCTAssertNil(bad.sigmaCounting); XCTAssertNil(bad.thicknessNM)
        XCTAssertNil(bad.thresholdEV); XCTAssertNil(bad.thresholdChannel); XCTAssertNil(bad.i0)
        XCTAssertEqual(bad.unavailable, .noInflexionFound)
        XCTAssertEqual(bad.iTotal, 5 * Double(nch))
        XCTAssertEqual(bad.zlpCentreEV, -10, "a flat spectrum's first maximum is channel 0")
        XCTAssertFalse((bad.unavailable?.description ?? "").isEmpty)
        // the same pixel alone sets tol from itself; with the flat pixel beside it tol is that of the good pixel
        XCTAssertEqual(map.estimatedTolerance, alone.estimatedTolerance)
    }

    /// A caller's `tol` below every |derivative|: no channel qualifies, so every pixel is nil (argmax of all-False is 0 in exSpy).
    func testATolBelowEveryDerivativeLeavesEveryPixelWithoutInflexion() throws {
        let map = try EELSThickness.logRatio(try EELSFixtures.image("planted-noiseless"), threshold: .estimated(tolerance: 1e-3))
        XCTAssertTrue(map.pixels.allSatisfy { $0.tOverLambda == nil && $0.unavailable == .noInflexionFound })
        XCTAssertEqual(map.estimatedTolerance, 1e-3)
        // and a huge tol qualifies the first channel, which is "no inflexion" too (index 0)
        let huge = try EELSThickness.logRatio(try EELSFixtures.image("planted-noiseless"), threshold: .estimated(tolerance: 1e12))
        XCTAssertTrue(huge.pixels.allSatisfy { $0.unavailable == .noInflexionFound })
    }

    // MARK: I_0 and I_t that cannot give a logarithm

    func testZeroLossIntensityOfZeroIsNilWithItsReason() throws {
        // nothing before the threshold channel: I_0 = 0
        let img = try image(channels: 20, offset: 0, scale: 1, [Double](repeating: 1, count: 20))
        let atFirstChannel = try EELSThickness.logRatio(img, threshold: .fixed(0))
        XCTAssertEqual(atFirstChannel.pixels[0].thresholdChannel, 0)
        XCTAssertEqual(atFirstChannel.pixels[0].i0, 0)
        XCTAssertNil(atFirstChannel.pixels[0].tOverLambda)
        XCTAssertEqual(atFirstChannel.pixels[0].unavailable, .zeroLossIntensityNotPositive)
        XCTAssertEqual(atFirstChannel.pixels[0].iTotal, 20)
        // zero counts where the zero-loss peak should be
        let zeros = try image(channels: 20, offset: 0, scale: 1, [Double](repeating: 0, count: 10) + [Double](repeating: 3, count: 10))
        let m = try EELSThickness.logRatio(zeros, threshold: .fixed(5))
        XCTAssertEqual(m.pixels[0].i0, 0); XCTAssertEqual(m.pixels[0].unavailable, .zeroLossIntensityNotPositive)
        XCTAssertNil(m.pixels[0].thicknessNM)
        // negative I_0 (background-subtracted counts)
        let negative = try image(channels: 20, offset: 0, scale: 1, [Double](repeating: -1, count: 10) + [Double](repeating: 3, count: 10))
        XCTAssertEqual(try EELSThickness.logRatio(negative, threshold: .fixed(5)).pixels[0].unavailable, .zeroLossIntensityNotPositive)
        // the same through the zero-loss spectrum route
        let zlp = try image(channels: 8, offset: 0, scale: 1, [Double](repeating: 0, count: 8))
        let viaZlp = try EELSThickness.logRatio(img, zeroLoss: zlp)
        XCTAssertEqual(viaZlp.pixels[0].unavailable, .zeroLossIntensityNotPositive)
        XCTAssertEqual(viaZlp.pixels[0].i0, 0)
        // and through a per-pixel threshold
        XCTAssertEqual(try EELSThickness.logRatio(img, threshold: .perPixel([0])).pixels[0].unavailable, .zeroLossIntensityNotPositive)
    }

    func testANonPositiveTotalIsNilAndATotalBelowTheZeroLossIsReportedNotClipped() throws {
        // I_0 = 5 * 100 = 500 > 0 and I_t = 500 - 15 * 40 < 0: no logarithm
        let negativeTotal = try image(channels: 20, offset: 0, scale: 1, [Double](repeating: 100, count: 5) + [Double](repeating: -40, count: 15))
        let a = try EELSThickness.logRatio(negativeTotal, threshold: .fixed(5)).pixels[0]
        XCTAssertEqual(a.unavailable, .totalIntensityNotPositive); XCTAssertNil(a.tOverLambda)
        // I_t = 500 - 15 * 30 = 50 < I_0 = 500: t/lambda = ln(50/500) < 0, reported as is; sigma needs nested counts
        let below = try image(channels: 20, offset: 0, scale: 1, [Double](repeating: 100, count: 5) + [Double](repeating: -30, count: 15))
        let b = try EELSThickness.logRatio(below, threshold: .fixed(5)).pixels[0]
        XCTAssertNil(b.unavailable)
        XCTAssertEqual(b.tOverLambda.orFail(), log(50.0 / 500.0), accuracy: 1e-15)
        XCTAssertLessThan(b.tOverLambda.orFail(), 0)
        XCTAssertNil(b.sigmaCounting); XCTAssertEqual(b.sigmaUnavailable, .totalBelowZeroLoss)
        XCTAssertFalse((b.sigmaUnavailable?.description ?? "").isEmpty)
    }

    // MARK: zero-loss spectrum image

    func testAZeroLossImageOfTheWrongShapeIsRefused() throws {
        let img = try image(nx: 3, ny: 2, channels: 10, [Double](repeating: 1, count: 60))
        let wrongNx = try image(nx: 2, ny: 2, channels: 10, [Double](repeating: 1, count: 40))
        let wrongNy = try image(nx: 3, ny: 1, channels: 10, [Double](repeating: 1, count: 30))
        let transposed = try image(nx: 2, ny: 3, channels: 10, [Double](repeating: 1, count: 60))
        for z in [wrongNx, wrongNy, transposed] {
            XCTAssertThrowsError(try EELSThickness.logRatio(img, zeroLoss: z)) {
                XCTAssertEqual($0 as? EELSThicknessError, .zeroLossShapeMismatch(expectedNx: 3, expectedNy: 2, gotNx: z.nx, gotNy: z.ny))
            }
        }
        // the channel count may differ: only the sum is used
        let otherChannels = try image(nx: 3, ny: 2, channels: 4, [Double](repeating: 2, count: 24))
        let m = try EELSThickness.logRatio(img, zeroLoss: otherChannels)
        XCTAssertTrue(m.pixels.allSatisfy { $0.i0 == 8 && $0.iTotal == 10 })
        XCTAssertEqual(m.zeroLoss, .zeroLossSpectrum)
        XCTAssertNil(m.estimatedTolerance)
    }

    /// With a zero-loss image the threshold rule is not used (exSpy: `zlp` takes precedence, `_eels.py:810-813`), even a rule that would throw.
    func testZeroLossImageTakesPrecedenceOverTheThresholdRule() throws {
        let img = try image(nx: 2, ny: 1, channels: 10, [Double](repeating: 1, count: 20))
        let zlp = try image(nx: 2, ny: 1, channels: 10, [Double](repeating: 1, count: 20))
        XCTAssertNoThrow(try EELSThickness.logRatio(img, threshold: .estimated(window: 0), zeroLoss: zlp))
        XCTAssertNoThrow(try EELSThickness.logRatio(img, threshold: .perPixel([1]), zeroLoss: zlp))
    }

    // MARK: input validation

    func testInputValidation() {
        func make(_ nx: Int, _ ny: Int, _ ch: Int, _ n: Int, _ off: Double = 0, _ scale: Double = 1, _ fill: Double = 1) throws -> LowLossSpectrumImage {
            try LowLossSpectrumImage(nx: nx, ny: ny, channels: ch, counts: [Double](repeating: fill, count: n), energyOffsetEV: off, energyScaleEV: scale)
        }
        XCTAssertThrowsError(try make(2, 2, 5, 19)) { XCTAssertEqual($0 as? EELSThicknessError, .invalidShape(nx: 2, ny: 2, channels: 5, counts: 19)) }
        XCTAssertThrowsError(try make(0, 2, 5, 0))
        XCTAssertThrowsError(try make(2, 2, 0, 0))
        XCTAssertThrowsError(try make(1, 1, 5, 5, 0, 0)) { XCTAssertEqual($0 as? EELSThicknessError, .invalidEnergyAxis(offsetEV: 0, scaleEV: 0)) }
        XCTAssertThrowsError(try make(1, 1, 5, 5, 0, -0.05))
        XCTAssertThrowsError(try make(1, 1, 5, 5, .nan, 0.05))
        XCTAssertThrowsError(try make(1, 1, 5, 5, 0, .infinity))
        XCTAssertThrowsError(try make(1, 1, 5, 5, 0, 1, .nan)) { XCTAssertEqual($0 as? EELSThicknessError, .nonFiniteCounts(pixel: 0)) }
        XCTAssertThrowsError(try LowLossSpectrumImage(nx: 2, ny: 1, channels: 3, counts: [1, 1, 1, 1, Double.infinity, 1] as [Double], energyOffsetEV: 0, energyScaleEV: 1)) {
            XCTAssertEqual($0 as? EELSThicknessError, .nonFiniteCounts(pixel: 1))
        }
    }

    /// Single-precision counts are widened exactly and give the same map.
    func testFloatCountsGiveTheSameMap() throws {
        let doubles = (0..<60).map { Double(($0 * 37) % 101) + 1 }
        let d = try image(nx: 2, ny: 1, channels: 30, offset: -5, scale: 0.5, doubles)
        let f = try LowLossSpectrumImage(nx: 2, ny: 1, channels: 30, counts: doubles.map { Float($0) }, energyOffsetEV: -5, energyScaleEV: 0.5)
        XCTAssertEqual(d.counts, f.counts)
        XCTAssertEqual(try EELSThickness.logRatio(d, threshold: .fixed(2)).pixels, try EELSThickness.logRatio(f, threshold: .fixed(2)).pixels)
    }

    // MARK: per-pixel and fixed rules

    func testPerPixelThresholds() throws {
        let img = try image(nx: 3, ny: 1, channels: 20, offset: 0, scale: 1, (0..<60).map { Double($0 % 20) + 1 })
        XCTAssertThrowsError(try EELSThickness.logRatio(img, threshold: .perPixel([1, 2]))) {
            XCTAssertEqual($0 as? EELSThicknessError, .perPixelThresholdCount(expected: 3, got: 2))
        }
        let m = try EELSThickness.logRatio(img, threshold: .perPixel([5, .nan, 1e6]))
        XCTAssertEqual(m.pixels[0].thresholdChannel, 5); XCTAssertEqual(m.pixels[0].i0, 15)
        XCTAssertEqual(m.pixels[1].unavailable, .thresholdNotANumber); XCTAssertNil(m.pixels[1].thresholdChannel)
        XCTAssertEqual(m.pixels[2].unavailable, .thresholdOutsideAxis); XCTAssertEqual(m.pixels[2].thresholdEV, 1e6)
        XCTAssertNil(m.pixels[2].i0)
        if case .threshold(.perPixel(let echoed)) = m.zeroLoss { XCTAssertEqual(echoed.count, 3); XCTAssertEqual(echoed[0], 5); XCTAssertTrue(echoed[1].isNaN) } else { XCTFail("the rule is echoed") }
        // per-pixel thresholds equal to the estimated ones reproduce the estimated map
        let planted = try EELSFixtures.image("planted-noiseless")
        let estimated = try EELSThickness.logRatio(planted, threshold: .estimated())
        let again = try EELSThickness.logRatio(planted, threshold: .perPixel(estimated.pixels.map { $0.thresholdEV.orFail() }))
        XCTAssertEqual(again.pixels.map(\.tOverLambda), estimated.pixels.map(\.tOverLambda))
        XCTAssertEqual(again.pixels.map(\.thresholdChannel), estimated.pixels.map(\.thresholdChannel))
    }

    /// A fixed threshold is reported as given (4.52 eV), and used as the channel it rounds to (290, the same as 4.5 eV).
    func testAFixedThresholdIsReportedAsGivenAndRoundedToAChannel() throws {
        let planted = try EELSFixtures.image("planted-noiseless")
        let on = try EELSThickness.logRatio(planted, threshold: .fixed(4.5))
        let off = try EELSThickness.logRatio(planted, threshold: .fixed(4.52))
        XCTAssertTrue(off.pixels.allSatisfy { $0.thresholdEV == 4.52 && $0.thresholdChannel == 290 })
        XCTAssertTrue(on.pixels.allSatisfy { $0.thresholdEV == 4.5 && $0.thresholdChannel == 290 })
        XCTAssertEqual(on.pixels.map(\.i0), off.pixels.map(\.i0))
        XCTAssertEqual(on.pixels.map(\.tOverLambda), off.pixels.map(\.tOverLambda))
    }

    func testFixedThresholdAtOrBeyondTheEndOfTheAxisGivesZeroThickness() throws {
        let img = try image(channels: 20, offset: 0, scale: 1, (0..<20).map { Double($0) + 1 })
        let m = try EELSThickness.logRatio(img, threshold: .fixed(1e6)).pixels[0]
        XCTAssertEqual(m.thresholdChannel, 20); XCTAssertEqual(m.i0, m.iTotal)
        XCTAssertEqual(m.tOverLambda, 0); XCTAssertEqual(m.sigmaCounting, 0)
        XCTAssertThrowsError(try EELSThickness.logRatio(img, threshold: .fixed(-5)))
        XCTAssertThrowsError(try EELSThickness.logRatio(img, threshold: .fixed(.nan)))
    }

    // MARK: sigma_counting and the zero-loss centre

    func testSigmaCountingIsTheSquareRootOfOneOverI0MinusOneOverIt() throws {
        let img = try image(channels: 8, offset: 0, scale: 1, [400, 300, 100, 40, 30, 20, 8, 2])      // I_0 = 800 at stop 3, I_t = 900
        let p = try EELSThickness.logRatio(img, threshold: .fixed(3)).pixels[0]
        XCTAssertEqual(p.i0, 800); XCTAssertEqual(p.iTotal, 900)
        XCTAssertEqual(p.sigmaCounting.orFail(), (1.0 / 800 - 1.0 / 900).squareRoot(), accuracy: 1e-18)
        XCTAssertEqual(p.sigmaCounting.orFail(), 0.011785113, accuracy: 1e-9)                                // not sqrt(1/800 + 1/900) = 0.048591
        XCTAssertEqual(p.tOverLambda.orFail(), log(900.0 / 800.0), accuracy: 1e-15)
        XCTAssertGreaterThan(p.tOverLambda.orFail(), 0)                                                      // ln(I_t / I_0), not the inverse
    }

    /// The energy of the spectrum's first maximum (numpy argmax takes the first of equal maxima).
    func testZeroLossCentreIsTheEnergyOfTheFirstMaximum() throws {
        let img = try image(nx: 2, ny: 1, channels: 6, offset: -1.5, scale: 0.5, [1, 5, 9, 9, 2, 1, 0, 3, 4, 8, 2, 1])
        let m = try EELSThickness.logRatio(img, threshold: .fixed(0))
        XCTAssertEqual(m.pixels[0].zlpCentreEV, -0.5, accuracy: 1e-15)                                // channel 2: -1.5 + 0.5 * 2
        XCTAssertEqual(m.pixels[1].zlpCentreEV, 0.0, accuracy: 1e-15)                                 // pixel 1 = [0, 3, 4, 8, 2, 1]: channel 3
        let planted = try EELSThickness.logRatio(try EELSFixtures.image("planted-noiseless"), threshold: .fixed(2.5))
        XCTAssertTrue(planted.pixels.allSatisfy { abs($0.zlpCentreEV) < 1e-12 })
    }

    // MARK: lambda sources

    func testMeanFreePathSources() throws {
        let img = try image(channels: 8, offset: 0, scale: 1, [400, 300, 100, 40, 30, 20, 8, 2])
        let t = log(900.0 / 800.0)
        let rho = 2.70, e0 = 200.0, alpha = 10.0, beta = 20.0
        let lambda = InelasticMeanFreePath.iakoubovskii(density: rho, beamEnergyKeV: e0)
        let correction = InelasticMeanFreePath.angularCorrection(density: rho, beamEnergyKeV: e0, convergenceMrad: alpha, collectionMrad: beta)
        XCTAssertEqual(lambda, 143.48821846111915, accuracy: 1e-11)
        XCTAssertEqual(correction, 1.0634407457337407, accuracy: 1e-14)

        let none = try EELSThickness.logRatio(img, threshold: .fixed(3))
        XCTAssertNil(none.pixels[0].thicknessNM); XCTAssertNil(none.meanFreePathNM); XCTAssertNil(none.angularCorrection)
        // lambda only: no correction
        let given = try EELSThickness.logRatio(img, threshold: .fixed(3), meanFreePath: .given(120))
        XCTAssertEqual(given.pixels[0].thicknessNM.orFail(), t * 120, accuracy: 1e-13)
        XCTAssertNil(given.angularCorrection); XCTAssertEqual(given.meanFreePathNM, 120)
        // density: corrected t/lambda times Iakoubovskii's lambda
        let density = try EELSThickness.logRatio(img, threshold: .fixed(3), meanFreePath: .iakoubovskii(density: rho, beamEnergyKeV: e0, convergenceMrad: alpha, collectionMrad: beta))
        XCTAssertEqual(density.pixels[0].thicknessNM.orFail(), t * correction * lambda, accuracy: 1e-12)
        XCTAssertEqual(density.angularCorrection, correction); XCTAssertEqual(density.meanFreePathNM, lambda)
        // both: the GIVEN lambda is still multiplied by the correction (exSpy _eels.py:828-838)
        let both = try EELSThickness.logRatio(img, threshold: .fixed(3), meanFreePath: .givenWithAngularCorrection(120, density: rho, beamEnergyKeV: e0, convergenceMrad: alpha, collectionMrad: beta))
        XCTAssertEqual(both.pixels[0].thicknessNM.orFail(), t * correction * 120, accuracy: 1e-12)
        XCTAssertNotEqual(both.pixels[0].thicknessNM.orFail(), given.pixels[0].thicknessNM.orFail(), accuracy: 1e-3)
        // the t/lambda field itself is never multiplied by the correction
        XCTAssertEqual(both.pixels[0].tOverLambda.orFail(), t, accuracy: 1e-15)
        XCTAssertEqual(density.pixels[0].tOverLambda, given.pixels[0].tOverLambda)
    }

    func testInvalidMeanFreePathSourcesAreRefused() throws {
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
            XCTAssertThrowsError(try EELSThickness.logRatio(img, threshold: .fixed(3), meanFreePath: source), "\(source)") {
                guard case EELSThicknessError.invalidMeanFreePath = $0 else { return XCTFail("\($0)") }
            }
        }
    }

    // MARK: layout, metadata, cancellation

    /// counts[(y * nx + x) * channels + c]: pixel (x, y) of a 3 x 2 image is found at y * 3 + x.
    func testPixelLayoutIsRowMajorInYThenXThenChannel() throws {
        var counts = [Double]()
        for y in 0..<2 { for x in 0..<3 { for c in 0..<4 { counts.append(Double(100 * y + 10 * x + c + 1)) } } }
        let m = try EELSThickness.logRatio(try image(nx: 3, ny: 2, channels: 4, counts), threshold: .fixed(2))
        XCTAssertEqual(m.nx, 3); XCTAssertEqual(m.ny, 2); XCTAssertEqual(m.pixels.count, 6)
        for y in 0..<2 { for x in 0..<3 {
            let base = Double(100 * y + 10 * x)
            XCTAssertEqual(m[x, y].iTotal, 4 * base + 10, "pixel (\(x), \(y))")
            XCTAssertEqual(m[x, y].i0, 2 * base + 3)
        } }
    }

    func testResultSaysHowItWasMade() throws {
        let planted = try EELSFixtures.image("planted-noiseless")
        let est = try EELSThickness.logRatio(planted)
        XCTAssertEqual(est.method, "log-ratio, exSpy 7185a4d1"); XCTAssertEqual(est.method, EELSThickness.methodName)
        XCTAssertEqual(est.validation, "none")
        XCTAssertEqual(est.zeroLoss, .threshold(.estimated()))
        XCTAssertNotNil(est.estimatedTolerance)
        let fixed = try EELSThickness.logRatio(planted, threshold: .fixed(4.5))
        XCTAssertEqual(fixed.zeroLoss, .threshold(.fixed(4.5))); XCTAssertNil(fixed.estimatedTolerance); XCTAssertEqual(fixed.validation, "none")
        XCTAssertEqual(ThresholdRule.estimated(), .estimated(window: 10, start: 1, windowLength: 5, polynomialOrder: 3, tolerance: nil))
    }

    func testCancellationAndProgress() throws {
        let planted = try EELSFixtures.image("planted-noiseless")
        XCTAssertThrowsError(try EELSThickness.logRatio(planted, cancelled: { true })) { XCTAssertTrue($0 is SpectroCancelled) }
        XCTAssertThrowsError(try EELSThickness.logRatio(planted, threshold: .fixed(2.5), cancelled: { true })) { XCTAssertTrue($0 is SpectroCancelled) }
        final class Log: @unchecked Sendable { let lock = NSLock(); var values = [Double](); func add(_ v: Double) { lock.lock(); values.append(v); lock.unlock() } }
        let log = Log()
        _ = try EELSThickness.logRatio(planted, progress: { log.add($0) })
        XCTAssertEqual(log.values.last, 1)
        XCTAssertEqual(log.values, log.values.sorted(), "progress is monotone")
        XCTAssertTrue(log.values.allSatisfy { $0 >= 0 && $0 <= 1 })
    }
}
