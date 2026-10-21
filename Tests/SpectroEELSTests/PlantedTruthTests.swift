//
//  PlantedTruthTests.swift
//  Role: Gates 2 and 3 of the registration (sections 7 and 9) against the PLANTED truth (tools/eels-thickness/make_planted.py,
//        NumPy only, no exSpy): t/lambda recovered from spectra whose t/lambda is known, and the claim sigma_counting makes about
//        noise. The numbers the method is held to are the generator's, committed before the code:
//         * noiseless: |t/lambda - tau| <= the method's own bias the generator predicts + 1e-9 (for each fixed threshold), and
//           for the estimated threshold the error equals the bias at the channel found (`biasByChannel`) and is <= 0.02;
//         * noisy, FIXED thresholds: per pixel |t/lambda_noisy - t/lambda_noiseless| <= 4 sigma_counting, and over 200 Poisson
//           realisations (seeds 1 to 200, generated here) the standard deviation of t/lambda is within 15 % of sigma_counting
//           for every tau;
//         * noisy, ESTIMATED threshold: no bound (amendment 1): the pins are reproduced elsewhere; here the 200-realisation
//           spread and the NaN count are reported.
//

import Foundation
import Testing
import SpectroTestSupport
import SpectroEELS

struct PlantedTruthTests {

    private let thresholds: [Double] = [2.5, 4.5, 6.0]

    private func truthComponent(_ pixel: Int, _ theta: Double) -> TruthFile.Component {
        EELSFixtures.truth.pixels[pixel].components.first { $0.theta == theta }!
    }

    // MARK: gate 2: noiseless

    @Test func testNoiselessFixedThresholdsRecoverTauToThePredictedBias() throws {
        let image = try EELSFixtures.image("planted-noiseless")
        #expect(EELSFixtures.truth.thresholdRule.thresholdsEV == thresholds)
        var worstVsBound = -Double.infinity, worstSigned = 0.0
        var table = [String]()
        for theta in thresholds {
            let map = try EELSThickness.logRatio(image, threshold: .fixed(theta))
            for p in 0..<10 {
                let truth = EELSFixtures.truth.pixels[p]
                let comp = truthComponent(p, theta)
                let t = map.pixels[p].tOverLambda.orFail()
                let error = t - truth.tau
                // the registered inequality
                #expect(abs(error) <= (abs(comp.bias) + 1e-9), "tau \(truth.tau) theta \(theta)")
                // and the signed equality (a sign error or a bias twice as large cannot hide under the inequality)
                #expect(isEqual(error, comp.bias, accuracy: 1e-9), "tau \(truth.tau) theta \(theta): error against the predicted bias")
                #expect(map.pixels[p].thresholdChannel == comp.index)
                worstVsBound = max(worstVsBound, abs(error) - abs(comp.bias))
                worstSigned = max(worstSigned, abs(error - comp.bias))
                table.append("tau \(truth.tau) theta \(theta): bias \(comp.bias) error \(error)")
            }
        }
        print("EELS-REPORT planted noiseless, fixed: worst |error| - |bias| = \(worstVsBound), worst |error - bias| = \(worstSigned)")
        for line in table { print("EELS-REPORT planted-table \(line)") }
    }

    @Test func testNoiselessEstimatedThresholdErrorEqualsTheBiasAtTheChannelFound() throws {
        let image = try EELSFixtures.image("planted-noiseless")
        let map = try EELSThickness.logRatio(image, threshold: .estimated())
        var worstError = 0.0, worstDiff = 0.0
        for p in 0..<10 {
            let truth = EELSFixtures.truth.pixels[p]
            let px = map.pixels[p]
            let channel = px.thresholdChannel.orFail()
            let bias = truth.biasByChannel.bias[channel - truth.biasByChannel.firstChannel]
            let error = px.tOverLambda.orFail() - truth.tau
            #expect(isEqual(error, bias, accuracy: 1e-9), "tau \(truth.tau) at channel \(channel)")
            #expect(abs(error) <= 0.02, "tau \(truth.tau)")
            worstError = max(worstError, abs(error)); worstDiff = max(worstDiff, abs(error - bias))
            print("EELS-REPORT planted-table tau \(truth.tau) estimated theta \(px.thresholdEV.orFail()) (channel \(channel)): bias at channel \(bias) error \(error)")
        }
        print("EELS-REPORT planted noiseless, estimated: max |error| = \(worstError) (gate 0.02), max |error - bias at channel| = \(worstDiff)")
    }

    // MARK: gate 3: noisy, fixed thresholds

    /// On the stored noisy image (NumPy seed 20261014): per pixel |t/lambda_noisy - t/lambda_noiseless| <= 4 sigma_counting, with
    /// sigma_counting of the noisy pixel's own counts.
    @Test func testStoredNoisyImageIsWithinFourSigmaOfTheNoiselessOneForFixedThresholds() throws {
        let noiseless = try EELSFixtures.image("planted-noiseless"), noisy = try EELSFixtures.image("planted-noisy")
        var worst = 0.0
        for theta in thresholds {
            let a = try EELSThickness.logRatio(noiseless, threshold: .fixed(theta)), b = try EELSThickness.logRatio(noisy, threshold: .fixed(theta))
            for p in 0..<10 {
                let sigma = b.pixels[p].sigmaCounting.orFail()
                let ratio = abs(b.pixels[p].tOverLambda.orFail() - a.pixels[p].tOverLambda.orFail()) / sigma
                worst = max(worst, ratio)
                #expect(ratio <= 4, "theta \(theta) pixel \(p)")
            }
        }
        print("EELS-REPORT planted noisy (stored), fixed thresholds: worst |noisy - noiseless| / sigma_counting = \(worst) (gate 4)")
    }

    private func realisation(seed: UInt64, from noiseless: LowLossSpectrumImage) throws -> LowLossSpectrumImage {
        var g = Xoshiro256StarStar(seed: seed)
        let counts = noiseless.counts.map { g.poisson($0) }
        return try LowLossSpectrumImage(nx: noiseless.nx, ny: noiseless.ny, channels: noiseless.channels, counts: counts,
                                        energyOffsetEV: noiseless.energyOffsetEV, energyScaleEV: noiseless.energyScaleEV)
    }

    private func standardDeviation(_ xs: [Double]) -> Double {
        let m = xs.reduce(0, +) / Double(xs.count)
        return (xs.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(xs.count - 1)).squareRoot()
    }

    /// 200 Poisson realisations of the noiseless image (seeds 1 to 200): for each fixed threshold and each tau, the standard
    /// deviation of t/lambda against sigma_counting of the noiseless image's expected counts. Within 15 %. And the estimated
    /// threshold on the same realisations, REPORTED without a bound (amendment 1).
    @Test func testTwoHundredRealisationsStandardDeviationAgainstSigmaCounting() throws {
        let noiseless = try EELSFixtures.image("planted-noiseless")
        var fixed = [[[Double]]](repeating: [[Double]](repeating: [], count: 10), count: 3)       // [threshold][pixel][realisation]
        var estimated = [[Double]](repeating: [], count: 10)
        var estimatedNaN = [Int](repeating: 0, count: 10)
        var estimatedThresholdRange = (low: Double.infinity, high: -Double.infinity)
        for seed in 1...200 {
            let image = try realisation(seed: UInt64(seed), from: noiseless)
            for (k, theta) in thresholds.enumerated() {
                let map = try EELSThickness.logRatio(image, threshold: .fixed(theta))
                for p in 0..<10 { fixed[k][p].append(map.pixels[p].tOverLambda.orFail()) }
            }
            let map = try EELSThickness.logRatio(image, threshold: .estimated())
            for p in 0..<10 {
                if let t = map.pixels[p].tOverLambda { estimated[p].append(t) } else { estimatedNaN[p] += 1 }
                if let e = map.pixels[p].thresholdEV {
                    estimatedThresholdRange = (min(estimatedThresholdRange.low, e), max(estimatedThresholdRange.high, e))
                }
            }
        }
        var worst = 0.0
        for (k, theta) in thresholds.enumerated() {
            let expected = try EELSThickness.logRatio(noiseless, threshold: .fixed(theta))
            for p in 0..<10 {
                let sigma = expected.pixels[p].sigmaCounting.orFail()
                let sd = standardDeviation(fixed[k][p])
                let ratio = sd / sigma
                worst = max(worst, abs(ratio - 1))
                print("EELS-REPORT sigma-table theta \(theta) tau \(EELSFixtures.truth.pixels[p].tau): sigma_counting \(sigma) sd over 200 \(sd) ratio \(ratio)")
                #expect(isEqual(ratio, 1, accuracy: 0.15), "theta \(theta) tau \(EELSFixtures.truth.pixels[p].tau)")
            }
        }
        print("EELS-REPORT sigma check, fixed thresholds: worst |sd / sigma_counting - 1| = \(worst) (gate 0.15)")
        // estimated threshold: reported only
        let reference = try EELSThickness.logRatio(noiseless, threshold: .fixed(4.5))
        for p in 0..<10 {
            let sigma = reference.pixels[p].sigmaCounting.orFail()
            let sd = estimated[p].count > 1 ? standardDeviation(estimated[p]) : .nan
            print("EELS-REPORT estimated-table tau \(EELSFixtures.truth.pixels[p].tau): sd of t/lambda over \(estimated[p].count) valid realisations \(sd), sigma_counting \(sigma), ratio \(sd / sigma), nil (no inflexion) in \(estimatedNaN[p]) of 200")
        }
        print("EELS-REPORT estimated thresholds over the 200 realisations ran from \(estimatedThresholdRange.low) to \(estimatedThresholdRange.high) eV")
    }
}
