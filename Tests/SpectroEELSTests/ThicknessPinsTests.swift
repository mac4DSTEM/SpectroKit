//
//  ThicknessPinsTests.swift
//  Role: Gate 1 of the registration (docs/eels-slice-1-registration.md sections 4, 7 and 9): the port against what exSpy
//        7185a4d1 answered (tools/eels-thickness/pins.py -> Fixtures/pins.json), on the planted noiseless and noisy images and
//        exSpy's own line scan: thresholds, I_0, I_t, t/lambda for every route, absolute thicknesses, lambda and the angular
//        correction.
//
//  Agreement required (section 4): the same threshold channel for every pixel; I_0 and I_t relative <= 1e-12; t/lambda absolute
//  <= 1e-12; lambda and the correction relative <= 1e-13. A difference is a failure of the port, never a tolerance to widen.
//  Amendment 2 (tie pixels): where a pixel has channels whose |derivative| equals `tol` to rounding, the first channel is
//  decided by rounding. The pins list those pixels (`stability.sensitivePixels`; the noisy image's 0, 2, 3, 5, 6, 8, 9). At such
//  a pixel the port passes if its channel is one whose |derivative| is within 1e-9 relative of the pinned `tol`, and its I_0, I_t
//  and t/lambda equal the sums at its own channel.
//  READING (reported): the amendment's words cover the tie channels but not exSpy's own channel when rounding rejected the tie
//  channel and exSpy took the next one, whose |derivative| is far below `tol` (the pins' pixel 0: |d| = 0 at the pinned
//  channel, the tie channel before it rejected by 1.5e-14). The rule tested is the one the amendment's reason implies: the port's
//  channel is a first hit under SOME rounding, i.e. its |d| is at most tol(1 + 1e-9) and no earlier channel has |d| below
//  tol(1 - 1e-9). exSpy's own channel always satisfies it; so does every tie channel that precedes it.
//  pins.json does not hold the derivative of every channel, so the test evaluates it EXACTLY from the integer counts: the
//  5-point cubic stencil (f[c-2] - 8 f[c-1] + 8 f[c+1] - f[c+2]) / (12 delta) for the interior, which is the Savitzky-Golay
//  coefficient set before SciPy's rounding noise (the two edge channels at each end use the port's own fit: they are not ties).
//

import Foundation
import XCTest
import SpectroEELS
import SpectroCore

final class ThicknessPinsTests: XCTestCase {

    private let caseNames = ["planted-noiseless", "planted-noisy", "exspy-linescan"]

    // MARK: helpers

    private func thresholds(_ name: String, gradient: Bool = false, override: [Double]? = nil) throws -> EstimatedThresholds {
        let image = try EELSFixtures.image(name)
        let axis = try EELSAxis(offset: image.energyOffsetEV, scale: image.energyScaleEV, size: image.channels)
        return try image.counts.withUnsafeBufferPointer { buf in
            try ElasticThreshold.estimate(
                counts: buf, pixelCount: image.pixelCount, channels: image.channels, axis: axis, window: 10, start: 1,
                windowLength: gradient ? 0 : 5, polynomialOrder: 3, tolerance: nil, coefficientsOverride: override,
                cancelled: { false }, progress: nil)
        }
    }

    /// Neumaier compensated sum: independent of the port's pairwise sum, correct to the last bit for these magnitudes.
    private func exactSum(_ values: ArraySlice<Double>) -> Double {
        var sum = 0.0, c = 0.0
        for v in values {
            let t = sum + v
            c += abs(sum) >= abs(v) ? (sum - t) + v : (v - t) + sum
            sum = t
        }
        return sum + c
    }

    /// The derivative of the cropped row with the interior replaced by the exact stencil (integer counts), edges from the port.
    private func checkedDerivative(pixel p: Int, image: LowLossSpectrumImage, route: PinEstimated, scale: Double) throws -> [Double] {
        let nch = image.channels
        let first = route.subRange.firstChannel, length = route.subRange.channels
        let f = Array(image.counts[(p * nch + first)..<(p * nch + first + length)])
        let sg = try SavitzkyGolayFirstDerivative(windowLength: 5, polynomialOrder: 3, delta: scale)
        var d = [Double](repeating: 0, count: length)
        f.withUnsafeBufferPointer { fp in d.withUnsafeMutableBufferPointer { dp in sg.apply(fp, into: dp) } }
        for j in 2..<(length - 2) { d[j] = (f[j - 2] - 8 * f[j - 1] + 8 * f[j + 1] - f[j + 2]) / (12 * scale) }
        return d
    }

    // MARK: the estimated threshold (SG)

    /// The search range, tol, the per-pixel minimum, and the threshold of every pixel that is not a tie pixel; all through the
    /// public map as well. Records the worst deviation of each quantity.
    func testEstimatedThresholdPins() throws {
        let worstTol = Worst(), worstMin = Worst(), worstI0 = Worst(), worstIt = Worst(), worstT = Worst(), worstEnergy = Worst()
        for name in caseNames {
            let pin = EELSFixtures.pinCase(name)
            let route = pin.estimated
            let image = try EELSFixtures.image(name)
            let found = try thresholds(name)
            XCTAssertEqual(found.firstChannel, route.subRange.firstChannel, name)
            XCTAssertEqual(found.channels, route.subRange.channels, name)
            worstTol.record(relativeDifference(found.tolerance, route.tol), "\(name) tol \(found.tolerance) vs \(route.tol)")
            XCTAssertLessThanOrEqual(relativeDifference(found.tolerance, route.tol), 1e-11, "\(name) tol")
            let map = try EELSThickness.logRatio(image, threshold: .estimated())
            XCTAssertEqual(map.estimatedTolerance, found.tolerance)
            let nch = image.channels
            var ties = 0, sameAsExSpy = 0
            for p in 0..<pin.rows * pin.cols {
                // a minimum near zero is rounding noise (SciPy 1e-14, here another 1e-14): compare absolutely, at the pins' own epsilon
                worstMin.record(abs(found.minAbsDerivative[p] - route.minAbsDerivative[p]), "\(name) pixel \(p)")
                XCTAssertLessThanOrEqual(abs(found.minAbsDerivative[p] - route.minAbsDerivative[p]), route.stability.epsilonAbs, "\(name) pixel \(p) min |d|")
                let px = map.pixels[p]
                let tie = route.stability.sensitivePixels.contains(p)
                if tie {
                    ties += 1
                    // amendment 2 (as read above): a first hit under some rounding; sums at the port's own channel.
                    guard let ch = px.thresholdChannel else { XCTFail("\(name) pixel \(p): no threshold at a tie pixel"); continue }
                    let j = ch - route.subRange.firstChannel
                    let d = try checkedDerivative(pixel: p, image: image, route: route, scale: pin.energyAxis.scale)
                    XCTAssertLessThanOrEqual(abs(d[j]), route.tol * (1 + 1e-9), "\(name) pixel \(p): channel \(ch) has |d| = \(abs(d[j])), tol \(route.tol)")
                    for earlier in 0..<j {
                        XCTAssertGreaterThanOrEqual(abs(d[earlier]), route.tol * (1 - 1e-9),
                                                    "\(name) pixel \(p): channel \(route.subRange.firstChannel + earlier) is definitely below tol and before \(ch)")
                    }
                    if px.thresholdChannel == route.thresholdChannel[p] { sameAsExSpy += 1 }
                    let f = Array(image.counts[(p * nch)..<((p + 1) * nch)])
                    let i0 = exactSum(f[0..<ch]), it = exactSum(f[0..<nch])
                    XCTAssertLessThanOrEqual(relativeDifference(px.i0.orFail(), i0), 1e-12, "\(name) pixel \(p) I0 at own channel")
                    XCTAssertLessThanOrEqual(relativeDifference(px.iTotal, it), 1e-12, "\(name) pixel \(p) It")
                    XCTAssertLessThanOrEqual(abs(px.tOverLambda.orFail() - log(it / i0)), 1e-12, "\(name) pixel \(p) t/lambda at own channel")
                    continue
                }
                // not a tie: the same channel and the same sums as exSpy
                XCTAssertEqual(found.inflexionIndex[p], route.inflexionIndex[p], "\(name) pixel \(p) inflexion index")
                XCTAssertEqual(px.thresholdChannel, route.thresholdChannel[p], "\(name) pixel \(p) channel")
                if let e = route.thresholdEV[p] {
                    XCTAssertEqual(px.thresholdEV, e, "\(name) pixel \(p) threshold energy")
                    worstEnergy.record(abs(px.thresholdEV.orFail() - e), "\(name) pixel \(p)")
                    worstI0.record(relativeDifference(px.i0.orFail(), route.i0[p]!), "\(name) pixel \(p)")
                    worstIt.record(relativeDifference(px.iTotal, route.it[p]), "\(name) pixel \(p)")
                    worstT.record(abs(px.tOverLambda.orFail() - route.tOverLambda[p]!), "\(name) pixel \(p)")
                    XCTAssertLessThanOrEqual(relativeDifference(px.i0.orFail(), route.i0[p]!), 1e-12, "\(name) pixel \(p) I0")
                    XCTAssertLessThanOrEqual(relativeDifference(px.iTotal, route.it[p]), 1e-12, "\(name) pixel \(p) It")
                    XCTAssertLessThanOrEqual(abs(px.tOverLambda.orFail() - route.tOverLambda[p]!), 1e-12, "\(name) pixel \(p) t/lambda")
                } else {
                    XCTAssertEqual(px.unavailable, .noInflexionFound, "\(name) pixel \(p)")
                }
            }
            print("EELS-REPORT estimated(SG) \(name): \(pin.rows * pin.cols) pixels, \(ties) tie pixels (amendment 2; \(sameAsExSpy) with exSpy's own channel), tol \(found.tolerance) vs pinned \(route.tol)")
        }
        print("EELS-REPORT estimated(SG) worst deviations over the non-tie pixels: tol rel \(worstTol.value) (\(worstTol.where_)); minAbsDerivative abs \(worstMin.value) (\(worstMin.where_)); threshold energy abs \(worstEnergy.value); I0 rel \(worstI0.value); It rel \(worstIt.value); t/lambda abs \(worstT.value)")
    }

    /// The whole pipeline, run on SciPy's own five coefficients, reproduces EVERY pinned channel, including the tie pixels of the
    /// noisy image, and tol and the per-pixel minima (to rounding where the minimum is at an edge of the range): the difference
    /// above is therefore the coefficient noise of dgelsy against dgelsd and nothing else.
    func testEstimatedThresholdPinsAreExactWithSciPysCoefficients() throws {
        for name in caseNames {
            let pin = EELSFixtures.pinCase(name)
            let route = pin.estimated
            let found = try thresholds(name, override: route.recipe!.coefficients!)
            XCTAssertEqual(found.tolerance, route.tol, "\(name) tol bit-exact")
            var edgeMinima = 0
            for p in 0..<pin.rows * pin.cols {
                XCTAssertEqual(found.inflexionIndex[p], route.inflexionIndex[p], "\(name) pixel \(p) inflexion index")
                if found.minAbsDerivative[p] != route.minAbsDerivative[p] {
                    edgeMinima += 1
                    XCTAssertLessThanOrEqual(relativeDifference(found.minAbsDerivative[p], route.minAbsDerivative[p]), 1e-11, "\(name) pixel \(p) edge minimum")
                }
                if let e = route.thresholdEV[p] { XCTAssertEqual(found.thresholdEV[p], e, "\(name) pixel \(p)") } else { XCTAssertTrue(found.thresholdEV[p].isNaN) }
            }
            print("EELS-REPORT estimated(SG, SciPy coefficients) \(name): tol bit-exact, all inflexion indices equal, \(edgeMinima) per-pixel minima not bit-equal (their minimum sits on an edge fit)")
        }
    }

    // MARK: the estimated threshold (numpy.gradient)

    func testEstimatedGradientThresholdPins() throws {
        for name in caseNames {
            let pin = EELSFixtures.pinCase(name)
            let route = pin.estimatedGradient
            let image = try EELSFixtures.image(name)
            let found = try thresholds(name, gradient: true)
            XCTAssertEqual(found.firstChannel, route.subRange.firstChannel, name)
            XCTAssertEqual(found.channels, route.subRange.channels, name)
            XCTAssertEqual(found.tolerance, route.tol, "\(name) tol (the gradient recipe is bit-exact)")
            let map = try EELSThickness.logRatio(image, threshold: .estimated(windowLength: 0))
            var worstT = 0.0, worstI0 = 0.0
            for p in 0..<pin.rows * pin.cols {
                XCTAssertEqual(found.minAbsDerivative[p], route.minAbsDerivative[p], "\(name) pixel \(p) min |d|")
                XCTAssertEqual(found.inflexionIndex[p], route.inflexionIndex[p], "\(name) pixel \(p) inflexion index")
                let px = map.pixels[p]
                XCTAssertEqual(px.thresholdChannel, route.thresholdChannel[p], "\(name) pixel \(p) channel")
                if let e = route.thresholdEV[p] {
                    XCTAssertEqual(px.thresholdEV, e, "\(name) pixel \(p)")
                    worstI0 = max(worstI0, relativeDifference(px.i0.orFail(), route.i0[p]!))
                    worstT = max(worstT, abs(px.tOverLambda.orFail() - route.tOverLambda[p]!))
                    XCTAssertLessThanOrEqual(relativeDifference(px.i0.orFail(), route.i0[p]!), 1e-12, "\(name) pixel \(p) I0")
                    XCTAssertLessThanOrEqual(relativeDifference(px.iTotal, route.it[p]), 1e-12, "\(name) pixel \(p) It")
                    XCTAssertLessThanOrEqual(abs(px.tOverLambda.orFail() - route.tOverLambda[p]!), 1e-12, "\(name) pixel \(p) t/lambda")
                } else {
                    XCTAssertEqual(px.unavailable, .noInflexionFound)
                }
            }
            print("EELS-REPORT estimated(gradient) \(name): tol \(found.tolerance) (bit-equal), every channel equal; worst I0 rel \(worstI0), t/lambda abs \(worstT)")
        }
    }

    // MARK: fixed thresholds

    func testFixedThresholdPins() throws {
        let worstI0 = Worst(), worstIt = Worst(), worstT = Worst()
        for name in caseNames {
            let pin = EELSFixtures.pinCase(name)
            let image = try EELSFixtures.image(name)
            XCTAssertEqual(pin.fixed.map(\.thetaEV), [2.5, 4.5, 6.0])
            for fixed in pin.fixed {
                let map = try EELSThickness.logRatio(image, threshold: .fixed(fixed.thetaEV))
                for p in 0..<pin.rows * pin.cols {
                    let px = map.pixels[p]
                    XCTAssertEqual(px.thresholdChannel, fixed.channel, "\(name) \(fixed.thetaEV) pixel \(p)")
                    worstI0.record(relativeDifference(px.i0.orFail(), fixed.i0[p]), "\(name) \(fixed.thetaEV) pixel \(p)")
                    worstIt.record(relativeDifference(px.iTotal, fixed.it[p]), "\(name) \(fixed.thetaEV) pixel \(p)")
                    worstT.record(abs(px.tOverLambda.orFail() - fixed.tOverLambda[p]), "\(name) \(fixed.thetaEV) pixel \(p)")
                    XCTAssertLessThanOrEqual(relativeDifference(px.i0.orFail(), fixed.i0[p]), 1e-12, "\(name) \(fixed.thetaEV) pixel \(p) I0")
                    XCTAssertLessThanOrEqual(relativeDifference(px.iTotal, fixed.it[p]), 1e-12, "\(name) \(fixed.thetaEV) pixel \(p) It")
                    XCTAssertLessThanOrEqual(abs(px.tOverLambda.orFail() - fixed.tOverLambda[p]), 1e-12, "\(name) \(fixed.thetaEV) pixel \(p) t/lambda")
                }
            }
        }
        print("EELS-REPORT fixed 2.5/4.5/6.0 eV, 3 cases: worst I0 rel \(worstI0.value), It rel \(worstIt.value), t/lambda abs \(worstT.value)")
    }

    /// exSpy's zero-loss route: I_0 is the sum of the twin spectrum (line scan only).
    func testZeroLossSpectrumRoutePins() throws {
        let pin = EELSFixtures.pinCase("exspy-linescan")
        let zlp = pin.zeroLoss!
        let map = try EELSThickness.logRatio(try EELSFixtures.image("exspy-linescan"), zeroLoss: try EELSFixtures.lineScanZeroLoss())
        var worstI0 = 0.0, worstT = 0.0
        for p in 0..<17 {
            let px = map.pixels[p]
            worstI0 = max(worstI0, relativeDifference(px.i0.orFail(), zlp.i0[p]))
            worstT = max(worstT, abs(px.tOverLambda.orFail() - zlp.tOverLambda[p]))
            XCTAssertLessThanOrEqual(relativeDifference(px.i0.orFail(), zlp.i0[p]), 1e-12, "pixel \(p) I0")
            XCTAssertLessThanOrEqual(relativeDifference(px.iTotal, zlp.it[p]), 1e-12, "pixel \(p) It")
            XCTAssertLessThanOrEqual(abs(px.tOverLambda.orFail() - zlp.tOverLambda[p]), 1e-12, "pixel \(p) t/lambda")
            XCTAssertNil(px.thresholdEV); XCTAssertNil(px.thresholdChannel)
            XCTAssertEqual(px.sigmaUnavailable, .zeroLossFromSeparateSpectrum)
        }
        XCTAssertEqual(map.zeroLoss, .zeroLossSpectrum)
        print("EELS-REPORT zero-loss spectrum route (line scan): worst I0 rel \(worstI0), t/lambda abs \(worstT)")
    }

    // MARK: absolute thickness

    func testAbsoluteThicknessPins() throws {
        var worst = 0.0
        for name in caseNames {
            let pin = EELSFixtures.pinCase(name)
            let abs_ = pin.absoluteThickness
            let image = try EELSFixtures.image(name)
            let zero = name == "exspy-linescan" ? try EELSFixtures.lineScanZeroLoss() : nil
            let sources: [(String, MeanFreePathSource, KeyPath<PinAbsRoute, [Double?]>, Double)] = [
                ("density and lambda", .givenWithAngularCorrection(abs_.lambdaGivenNM, density: abs_.densityGPerCm3, beamEnergyKeV: abs_.beamEnergyKeV,
                    convergenceMrad: abs_.convergenceAngleMrad, collectionMrad: abs_.collectionAngleMrad),
                 \.thicknessNMDensityAndLambda, abs_.lambdaGivenNM * abs_.angularCorrection),
                ("density only", .iakoubovskii(density: abs_.densityGPerCm3, beamEnergyKeV: abs_.beamEnergyKeV,
                    convergenceMrad: abs_.convergenceAngleMrad, collectionMrad: abs_.collectionAngleMrad),
                 \.thicknessNMDensityOnly, abs_.lambdaIakoubovskiiNM * abs_.angularCorrection),
                ("lambda only", .given(abs_.lambdaGivenNM), \.thicknessNMLambdaOnly, abs_.lambdaGivenNM),
            ]
            for route in abs_.routes {
                let rule: ThresholdRule? = route.route == "estimated" ? .estimated() : route.thetaEV.map { .fixed($0) }
                for (label, source, key, scaleFactor) in sources {
                    let map: ThicknessMap
                    if route.route == "zeroLoss" {
                        map = try EELSThickness.logRatio(image, zeroLoss: zero, meanFreePath: source)
                    } else {
                        map = try EELSThickness.logRatio(image, threshold: rule!, meanFreePath: source)
                    }
                    let tie = Set(pin.estimated.stability.sensitivePixels)
                    for p in 0..<pin.rows * pin.cols {
                        if route.route == "estimated" && tie.contains(p) { continue }      // channel decided by rounding (amendment 2)
                        guard let expected = route[keyPath: key][p] else { continue }
                        let got = map.pixels[p].thicknessNM.orFail()
                        // bound: t/lambda to 1e-12 absolute, times the factor lambda * correction; plus 1e-13 relative for lambda and correction
                        let bound = 1e-12 * scaleFactor + 1e-13 * expected
                        worst = max(worst, Swift.abs(got - expected))
                        XCTAssertLessThanOrEqual(Swift.abs(got - expected), bound, "\(name) \(route.route) \(route.thetaEV ?? 0) \(label) pixel \(p)")
                    }
                    XCTAssertEqual(map.meanFreePathNM.orFail(), label == "lambda only" || label == "density and lambda" ? abs_.lambdaGivenNM : abs_.lambdaIakoubovskiiNM,
                                   accuracy: 1e-13 * abs_.lambdaIakoubovskiiNM, "\(name) \(label) lambda")
                    if label == "lambda only" { XCTAssertNil(map.angularCorrection) } else {
                        XCTAssertEqual(map.angularCorrection.orFail(), abs_.angularCorrection, accuracy: 1e-13 * abs_.angularCorrection, "\(name) \(label) correction")
                    }
                }
            }
        }
        print("EELS-REPORT absolute thickness (3 cases, estimated/fixed/zero-loss routes, 3 lambda sources): worst |thickness - pin| = \(worst) nm")
    }

    /// lambda (Iakoubovskii eq. 9) on 4 densities x 5 beam energies and the angular correction on that x 3 convergence x 3 collection angles.
    func testMeanFreePathAndAngularCorrectionPins() {
        let pins = EELSFixtures.pins.iMFP
        var worstLambda = 0.0, worstCorrection = 0.0
        for row in pins.iakoubovskii.rows {
            let got = InelasticMeanFreePath.iakoubovskii(density: row[0], beamEnergyKeV: row[1])
            worstLambda = max(worstLambda, relativeDifference(got, row[2]))
            XCTAssertLessThanOrEqual(relativeDifference(got, row[2]), 1e-13, "lambda \(row)")
        }
        for row in pins.angularCorrection.rows {
            let got = InelasticMeanFreePath.angularCorrection(density: row[0], beamEnergyKeV: row[1], convergenceMrad: row[2], collectionMrad: row[3])
            worstCorrection = max(worstCorrection, relativeDifference(got, row[4]))
            XCTAssertLessThanOrEqual(relativeDifference(got, row[4]), 1e-13, "correction \(row)")
        }
        XCTAssertEqual(pins.iakoubovskii.rows.count, 20); XCTAssertEqual(pins.angularCorrection.rows.count, 180)
        print("EELS-REPORT lambda (20 values) worst relative \(worstLambda); angular correction (180 values) worst relative \(worstCorrection)")
    }
}
