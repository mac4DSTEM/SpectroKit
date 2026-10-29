//
//  ThicknessPinsTests.swift
//  Role: The thickness port against what exSpy
//        7185a4d1 answered (tools/eels-thickness/pins.py -> Fixtures/pins.json), on the planted noiseless and noisy images and
//        exSpy's own line scan: thresholds, I_0, I_t, t/lambda for every route, absolute thicknesses, lambda and the angular
//        correction.
//
//  Auto-SG thresholds use portable-thresholds.json (pinned SciPy plus a documented numerical tie rule).
//  Raw exSpy answers remain as deviation evidence; gradient, fixed and zero-loss routes retain their original pins.
//  Integration tolerances remain I0/It relative 1e-12, t/lambda absolute 1e-12.
//

import Foundation
import Testing
import SpectroTestSupport
import SpectroEELS
import SpectroCore

struct ThicknessPinsTests {

    private let caseNames = ["planted-noiseless", "planted-noisy", "exspy-linescan"]

    // MARK: helpers

    private func thresholds(_ name: String, gradient: Bool = false, override: [Double]? = nil) throws -> EstimatedThresholds {
        let image = try EELSFixtures.image(name)
        let axis = try EELSAxis(offset: image.energyOffsetEV, scale: image.energyScaleEV, size: image.channels)
        return try image.counts.withUnsafeBufferPointer { buf in
            try ElasticThreshold.estimate(
                counts: buf, pixelCount: image.pixelCount, navigationWidth: image.nx, channels: image.channels, axis: axis, window: 10, start: 1,
                windowLength: gradient ? 0 : 5, polynomialOrder: 3, tolerance: nil, coefficientsOverride: override,
                cancelled: { false }, progress: nil)
        }
    }

    // MARK: the estimated threshold (SG)

    /// The search range, tol, the per-pixel minimum, and the threshold of every pixel (tie pixels included); all through the
    /// public map as well. Records the worst deviation of each quantity.
    @Test func testEstimatedThresholdPins() throws {
        let worstTol = Worst(), worstMin = Worst(), worstI0 = Worst(), worstIt = Worst(), worstT = Worst(), worstEnergy = Worst()
        for name in caseNames {
            let pin = EELSFixtures.pinCase(name)
            let route = try PortableThresholds.route(name)
            let image = try EELSFixtures.image(name)
            let found = try thresholds(name)
            #expect(found.firstChannel == route.firstChannel, "\(name)")
            #expect(found.channels == route.channels, "\(name)")
            worstTol.record(relativeDifference(found.tolerance, route.tol), "\(name) tol \(found.tolerance) vs \(route.tol)")
            #expect(abs(found.tolerance - route.tol) <= route.slack.max()!, "\(name) auto tolerance: CPU solver residuals bounded in derivative units")
            let map = try EELSThickness.logRatio(image, threshold: .estimated())
            #expect(map.estimatedTolerance == found.tolerance)
            var ties = 0
            for p in 0..<pin.rows * pin.cols {
                // a minimum near zero is rounding noise (SciPy 1e-14, here another 1e-14): compare absolutely, at the pins' own epsilon
                worstMin.record(abs(found.minAbsDerivative[p] - route.minAbsDerivative[p]), "\(name) pixel \(p)")
                #expect(abs(found.minAbsDerivative[p] - route.minAbsDerivative[p]) <= route.slack[p], "\(name) pixel \(p) min |d|: QR/SVD cancellation noise")
                let px = map.pixels[p]
                if route.changedFromRawExSpy.contains(p) { ties += 1 }
                else { #expect(route.thresholdChannel[p] == pin.estimated.thresholdChannel[p], "unambiguous raw exSpy channel") }
                // Every pixel follows the portable first-tie channel and the corresponding NumPy sums.
                #expect(found.inflexionIndex[p] == route.inflexionIndex[p], "\(name) pixel \(p) inflexion index")
                #expect(px.thresholdChannel == route.thresholdChannel[p], "\(name) pixel \(p) channel")
                if let e = route.thresholdEV[p] {
                    #expect(px.thresholdEV == e, "\(name) pixel \(p) threshold energy")
                    worstEnergy.record(abs(px.thresholdEV.orFail() - e), "\(name) pixel \(p)")
                    worstI0.record(relativeDifference(px.i0.orFail(), route.i0[p]!), "\(name) pixel \(p)")
                    worstIt.record(relativeDifference(px.iTotal, route.it[p]), "\(name) pixel \(p)")
                    worstT.record(abs(px.tOverLambda.orFail() - route.tOverLambda[p]!), "\(name) pixel \(p)")
                    #expect(relativeDifference(px.i0.orFail(), route.i0[p]!) <= (1e-12), "\(name) pixel \(p) I0")
                    #expect(relativeDifference(px.iTotal, route.it[p]) <= (1e-12), "\(name) pixel \(p) It")
                    #expect(abs(px.tOverLambda.orFail() - route.tOverLambda[p]!) <= (1e-12), "\(name) pixel \(p) t/lambda")
                } else {
                    #expect(px.unavailable == .noInflexionFound, "\(name) pixel \(p)")
                }
            }
            print("EELS-REPORT estimated(SG) \(name): \(pin.rows * pin.cols) pixels, \(ties) tie pixels, all with portable policy channel, tol \(found.tolerance) vs pinned \(route.tol)")
        }
        print("EELS-REPORT estimated(SG) worst deviations over all pixels: tol rel \(worstTol.value) (\(worstTol.where_)); minAbsDerivative abs \(worstMin.value) (\(worstMin.where_)); threshold energy abs \(worstEnergy.value); I0 rel \(worstI0.value); It rel \(worstIt.value); t/lambda abs \(worstT.value)")
    }

    /// Numerical ties choose the same first channel with raw SciPy coefficients and signed centre perturbations.
    /// The original exact comparison changes six noisy-image channels; this regression fails on that implementation.
    @Test func testEstimatedThresholdPinsAreExactWithSciPysCoefficients() throws {
        for name in caseNames {
            let pin = EELSFixtures.pinCase(name)
            let route = try PortableThresholds.route(name)
            for sign in [-1.0, 0.0, 1.0] {
                var coeffs = pin.estimated.recipe!.coefficients!
                coeffs[coeffs.count / 2] += sign * 8 * Double.ulpOfOne * route.coefficientL1
                let found = try thresholds(name, override: coeffs)
                #expect(abs(found.tolerance - route.tol) <= 2 * route.slack.max()!, "\(name) tol")
                #expect(found.inflexionIndex == route.inflexionIndex, "\(name) signed rounding perturbation \(sign)")
                for p in route.thresholdEV.indices {
                    if let energy = route.thresholdEV[p] { #expect(found.thresholdEV[p] == energy) }
                    else { #expect(found.thresholdEV[p].isNaN) }
                }
            }
        }
    }

    // MARK: the estimated threshold (numpy.gradient)

    @Test func testEstimatedGradientThresholdPins() throws {
        for name in caseNames {
            let pin = EELSFixtures.pinCase(name)
            let route = pin.estimatedGradient
            let image = try EELSFixtures.image(name)
            let found = try thresholds(name, gradient: true)
            #expect(found.firstChannel == route.subRange.firstChannel, "\(name)")
            #expect(found.channels == route.subRange.channels, "\(name)")
            #expect(found.tolerance == route.tol, "\(name) tol (the gradient recipe is bit-exact)")
            let map = try EELSThickness.logRatio(image, threshold: .estimated(windowLength: 0))
            var worstT = 0.0, worstI0 = 0.0
            for p in 0..<pin.rows * pin.cols {
                #expect(found.minAbsDerivative[p] == route.minAbsDerivative[p], "\(name) pixel \(p) min |d|")
                #expect(found.inflexionIndex[p] == route.inflexionIndex[p], "\(name) pixel \(p) inflexion index")
                let px = map.pixels[p]
                #expect(px.thresholdChannel == route.thresholdChannel[p], "\(name) pixel \(p) channel")
                if let e = route.thresholdEV[p] {
                    #expect(px.thresholdEV == e, "\(name) pixel \(p)")
                    worstI0 = max(worstI0, relativeDifference(px.i0.orFail(), route.i0[p]!))
                    worstT = max(worstT, abs(px.tOverLambda.orFail() - route.tOverLambda[p]!))
                    #expect(relativeDifference(px.i0.orFail(), route.i0[p]!) <= (1e-12), "\(name) pixel \(p) I0")
                    #expect(relativeDifference(px.iTotal, route.it[p]) <= (1e-12), "\(name) pixel \(p) It")
                    #expect(abs(px.tOverLambda.orFail() - route.tOverLambda[p]!) <= (1e-12), "\(name) pixel \(p) t/lambda")
                } else {
                    #expect(px.unavailable == .noInflexionFound)
                }
            }
            print("EELS-REPORT estimated(gradient) \(name): tol \(found.tolerance) (bit-equal), every channel equal; worst I0 rel \(worstI0), t/lambda abs \(worstT)")
        }
    }

    // MARK: fixed thresholds

    @Test func testFixedThresholdPins() throws {
        let worstI0 = Worst(), worstIt = Worst(), worstT = Worst()
        for name in caseNames {
            let pin = EELSFixtures.pinCase(name)
            let image = try EELSFixtures.image(name)
            #expect(pin.fixed.map(\.thetaEV) == [2.5, 4.5, 6.0])
            for fixed in pin.fixed {
                let map = try EELSThickness.logRatio(image, threshold: .fixed(fixed.thetaEV))
                for p in 0..<pin.rows * pin.cols {
                    let px = map.pixels[p]
                    #expect(px.thresholdChannel == fixed.channel, "\(name) \(fixed.thetaEV) pixel \(p)")
                    worstI0.record(relativeDifference(px.i0.orFail(), fixed.i0[p]), "\(name) \(fixed.thetaEV) pixel \(p)")
                    worstIt.record(relativeDifference(px.iTotal, fixed.it[p]), "\(name) \(fixed.thetaEV) pixel \(p)")
                    worstT.record(abs(px.tOverLambda.orFail() - fixed.tOverLambda[p]), "\(name) \(fixed.thetaEV) pixel \(p)")
                    #expect(relativeDifference(px.i0.orFail(), fixed.i0[p]) <= (1e-12), "\(name) \(fixed.thetaEV) pixel \(p) I0")
                    #expect(relativeDifference(px.iTotal, fixed.it[p]) <= (1e-12), "\(name) \(fixed.thetaEV) pixel \(p) It")
                    #expect(abs(px.tOverLambda.orFail() - fixed.tOverLambda[p]) <= (1e-12), "\(name) \(fixed.thetaEV) pixel \(p) t/lambda")
                }
            }
        }
        print("EELS-REPORT fixed 2.5/4.5/6.0 eV, 3 cases: worst I0 rel \(worstI0.value), It rel \(worstIt.value), t/lambda abs \(worstT.value)")
    }

    /// exSpy's zero-loss route: I_0 is the sum of the twin spectrum (line scan only).
    @Test func testZeroLossSpectrumRoutePins() throws {
        let pin = EELSFixtures.pinCase("exspy-linescan")
        let zlp = pin.zeroLoss!
        let map = try EELSThickness.logRatio(try EELSFixtures.image("exspy-linescan"), zeroLoss: try EELSFixtures.lineScanZeroLoss())
        var worstI0 = 0.0, worstT = 0.0
        for p in 0..<17 {
            let px = map.pixels[p]
            worstI0 = max(worstI0, relativeDifference(px.i0.orFail(), zlp.i0[p]))
            worstT = max(worstT, abs(px.tOverLambda.orFail() - zlp.tOverLambda[p]))
            #expect(relativeDifference(px.i0.orFail(), zlp.i0[p]) <= (1e-12), "pixel \(p) I0")
            #expect(relativeDifference(px.iTotal, zlp.it[p]) <= (1e-12), "pixel \(p) It")
            #expect(abs(px.tOverLambda.orFail() - zlp.tOverLambda[p]) <= (1e-12), "pixel \(p) t/lambda")
            #expect(px.thresholdEV == nil); #expect(px.thresholdChannel == nil)
            #expect(px.sigmaUnavailable == .zeroLossFromSeparateSpectrum)
        }
        #expect(map.zeroLoss == .zeroLossSpectrum)
        print("EELS-REPORT zero-loss spectrum route (line scan): worst I0 rel \(worstI0), t/lambda abs \(worstT)")
    }

    // MARK: absolute thickness

    @Test func testAbsoluteThicknessPins() throws {
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
                    for p in 0..<pin.rows * pin.cols {
                        let portableT = route.route == "estimated" ? try PortableThresholds.route(name).tOverLambda[p] : nil
                        let reference = route.route == "estimated" ? portableT.map { $0 * scaleFactor } : route[keyPath: key][p]
                        guard let expected = reference else { continue }
                        let got = map.pixels[p].thicknessNM.orFail()
                        // bound: t/lambda to 1e-12 absolute, times the factor lambda * correction; plus 1e-13 relative for lambda and correction
                        let bound = 1e-12 * scaleFactor + 1e-13 * expected
                        worst = max(worst, Swift.abs(got - expected))
                        #expect(Swift.abs(got - expected) <= bound, "\(name) \(route.route) \(route.thetaEV ?? 0) \(label) pixel \(p)")
                    }
                    #expect(isEqual(map.meanFreePathNM.orFail(), label == "lambda only" || label == "density and lambda" ? abs_.lambdaGivenNM : abs_.lambdaIakoubovskiiNM, accuracy: 1e-13 * abs_.lambdaIakoubovskiiNM), "\(name) \(label) lambda")
                    if label == "lambda only" { #expect(map.angularCorrection == nil) } else {
                        #expect(isEqual(map.angularCorrection.orFail(), abs_.angularCorrection, accuracy: 1e-13 * abs_.angularCorrection), "\(name) \(label) correction")
                    }
                }
            }
        }
        print("EELS-REPORT absolute thickness (3 cases, estimated/fixed/zero-loss routes, 3 lambda sources): worst |thickness - pin| = \(worst) nm")
    }

    /// lambda (Iakoubovskii eq. 9) on 4 densities x 5 beam energies and the angular correction on that x 3 convergence x 3 collection angles.
    @Test func testMeanFreePathAndAngularCorrectionPins() {
        let pins = EELSFixtures.pins.iMFP
        var worstLambda = 0.0, worstCorrection = 0.0
        for row in pins.iakoubovskii.rows {
            let got = InelasticMeanFreePath.iakoubovskii(density: row[0], beamEnergyKeV: row[1])
            worstLambda = max(worstLambda, relativeDifference(got, row[2]))
            #expect(relativeDifference(got, row[2]) <= (1e-13), "lambda \(row)")
        }
        for row in pins.angularCorrection.rows {
            let got = InelasticMeanFreePath.angularCorrection(density: row[0], beamEnergyKeV: row[1], convergenceMrad: row[2], collectionMrad: row[3])
            worstCorrection = max(worstCorrection, relativeDifference(got, row[4]))
            #expect(relativeDifference(got, row[4]) <= (1e-13), "correction \(row)")
        }
        #expect(pins.iakoubovskii.rows.count == 20); #expect(pins.angularCorrection.rows.count == 180)
        print("EELS-REPORT lambda (20 values) worst relative \(worstLambda); angular correction (180 values) worst relative \(worstCorrection)")
    }
}
