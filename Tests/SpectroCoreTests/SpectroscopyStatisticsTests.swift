import XCTest
import DSTEMCore

/// v5.0 WP3 lane T: the counting-statistics layer (Garwood, Currie, named sigma
/// terms, live-time normalisation, coverage). Reference values for the gamma and
/// chi-square quantiles were computed with scipy 1.18.0 (`scipy.stats.gamma.ppf`,
/// `chi2.ppf`) in the py4dstem conda env on 2026-10-05; the Garwood pins are also
/// the printed values of Garwood (1936) as tabulated at 95 %.
final class SpectroscopyStatisticsTests: XCTestCase {

    private func assertRelative(_ a: Double, _ b: Double, _ tol: Double, _ msg: String = "",
                                file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a, b, accuracy: tol * max(abs(b), 1e-300), msg, file: file, line: line)
    }

    // MARK: gamma / normal quantiles

    func testGammaQuantileMatchesScipy() {
        // gamma.ppf(p, a), scipy 1.18.0.
        let table: [(a: Double, p: Double, x: Double)] = [
            (0.5, 0.025, 0.0004910345585876278), (2.5, 0.5, 2.1757300955477636),
            (50, 0.975, 64.7805985929183), (1000, 0.01, 927.9081597966425),
            (3, 1e-6, 0.01825428296327929), (0.2, 0.3, 0.0015877907243441144),
        ]
        for t in table {
            assertRelative(IncompleteGamma.gammaQuantile(p: t.p, shape: t.a), t.x, 1e-10, "a=\(t.a) p=\(t.p)")
        }
    }

    func testGammaQuantileRoundTripsThroughP() {
        for a in [0.3, 1, 7.5, 40, 400] {
            for p in [1e-8, 0.025, 0.5, 0.975, 1 - 1e-9] {
                let x = IncompleteGamma.gammaQuantile(p: p, shape: a)
                XCTAssertEqual(IncompleteGamma.lowerRegularized(a: a, x: x), p, accuracy: 1e-12, "a=\(a) p=\(p)")
            }
        }
    }

    func testNormalQuantile() {
        assertRelative(NormalQuantile.value(0.95), 1.644853626951472, 1e-13)
        assertRelative(NormalQuantile.value(0.9999), 3.7190164854557084, 1e-12)
        XCTAssertEqual(NormalQuantile.value(0.5), 0, accuracy: 1e-15)
    }

    // MARK: Garwood

    func testGarwoodPins95() {
        // Printed digits (Garwood 1936 / chi-square tables): n=0 [0, 3.689], n=1 [0.0253, 5.572], n=5 [1.623, 11.668].
        let g0 = CountingInterval.garwood(count: 0)
        XCTAssertEqual(g0.lower, 0)
        XCTAssertEqual(g0.upper, 3.689, accuracy: 5e-4)
        let g1 = CountingInterval.garwood(count: 1)
        XCTAssertEqual(g1.lower, 0.0253, accuracy: 5e-5)
        XCTAssertEqual(g1.upper, 5.572, accuracy: 5e-4)
        let g5 = CountingInterval.garwood(count: 5)
        XCTAssertEqual(g5.lower, 1.623, accuracy: 5e-4)
        XCTAssertEqual(g5.upper, 11.668, accuracy: 5e-4)
        // Full digits (scipy chi2.ppf / 2).
        assertRelative(g0.upper, 3.688879454113936, 1e-11)
        assertRelative(g1.lower, 0.025317807984289876, 1e-10)
        assertRelative(g1.upper, 5.571643390938898, 1e-11)
        assertRelative(g5.lower, 1.6234863901184204, 1e-11)
        assertRelative(g5.upper, 11.66833207932267, 1e-11)
    }

    func testGarwoodAtOtherCountsAndConfidence() {
        let g100 = CountingInterval.garwood(count: 100)
        assertRelative(g100.lower, 81.36399125092314, 1e-10)
        assertRelative(g100.upper, 121.62679379242638, 1e-10)
        let g = CountingInterval.garwood(count: 5, confidence: 0.68)
        assertRelative(g.lower, 2.8487844589326654, 1e-10)
        assertRelative(g.upper, 8.365492747939102, 1e-10)
        // No threshold: n = 30 uses the same exact formula.
        let g30 = CountingInterval.garwood(count: 30, confidence: 0.68)
        assertRelative(g30.lower, 24.580041883935312, 1e-10)
        assertRelative(g30.upper, 36.503621192541644, 1e-10)
    }

    func testNetCounts() {
        let n = NetCounts(gross: 140, background: 100, scale: 0.4)
        XCTAssertEqual(n.net, 100, accuracy: 1e-12)
        XCTAssertEqual(n.variance, 140 + 0.16 * 100, accuracy: 1e-12)   // G + s^2 B, not G + s B
        XCTAssertEqual(n.sigma, n.variance.squareRoot(), accuracy: 1e-15)
        XCTAssertEqual(CountingInterval.roomCaption, "68 % exact Poisson interval; conservative below ~10 counts")
    }

    // MARK: Currie

    func testCurrieClassicConstantsAtScaleOne() {
        let c = Currie.standard
        for b in [4.0, 100.0, 2500.0] {
            let root = b.squareRoot()
            // L_C = 2.33 sqrt(B), L_D = 2.71 + 4.65 sqrt(B) to the published rounding.
            XCTAssertEqual(c.criticalLevel(background: b, scale: 1), 2.33 * root, accuracy: 0.005 * root + 1e-9)
            XCTAssertEqual(c.detectionLimit(background: b, scale: 1), 2.71 + 4.65 * root, accuracy: 0.005 * root + 0.005)
        }
        XCTAssertEqual(c.zAlpha, 1.6449, accuracy: 5e-5)
        // Exactly: L_D = z^2 + 2 z sqrt(2B) at alpha = beta, s = 1.
        let z = c.zAlpha
        assertRelative(c.detectionLimit(background: 100, scale: 1), z * z + 2 * z * 200.0.squareRoot(), 1e-12)
    }

    func testCurrieUsesTheWindowScale() {
        let c = Currie.standard
        // s = 0.25, B = 100: sigma0^2 = sB + s^2 B = 25 + 6.25.
        let s0 = 31.25.squareRoot()
        assertRelative(c.criticalLevel(background: 100, scale: 0.25), c.zAlpha * s0, 1e-12)
        assertRelative(c.detectionLimit(background: 100, scale: 0.25), c.zAlpha * c.zAlpha + 2 * c.zAlpha * s0, 1e-12)
        XCTAssertNotEqual(c.criticalLevel(background: 100, scale: 0.25), c.criticalLevel(background: 100, scale: 1), accuracy: 1)
    }

    func testCurrieDetectionLimitSolvesItsDefiningEquation() {
        // Unequal alpha/beta: (L_D - z_a s0)^2 = z_b^2 (s0^2 + L_D).
        let c = Currie(alpha: 0.01, beta: 0.10)
        for (b, s) in [(50.0, 0.3), (400.0, 1.0), (0.0, 1.0)] {
            let s0 = Currie.sigmaZero(background: b, scale: s)
            let ld = c.detectionLimit(background: b, scale: s)
            let lhs = (ld - c.zAlpha * s0) * (ld - c.zAlpha * s0)
            let rhs = c.zBeta * c.zBeta * (s0 * s0 + ld)
            XCTAssertEqual(lhs, rhs, accuracy: 1e-9 * max(rhs, 1))
        }
        // B = 0: L_C = 0 and L_D = z_beta^2.
        XCTAssertEqual(Currie.standard.criticalLevel(background: 0, scale: 1), 0)
        assertRelative(Currie.standard.detectionLimit(background: 0, scale: 1), Currie.standard.zBeta * Currie.standard.zBeta, 1e-12)
    }

    // MARK: sigma terms

    func testSigmaTermsQuadratureAndNames() {
        let t = SigmaTerms(counting: 0.03, k: 0.04, absorption: 0, thickness: 0)
        XCTAssertEqual(t.combined, 0.05, accuracy: 1e-15)
        XCTAssertEqual(t.dominant, .k)
        XCTAssertTrue(t.summary.contains("counting 3.0 %"))
        XCTAssertTrue(t.summary.contains("k 4.0 %"))
        XCTAssertTrue(t.summary.hasSuffix("= 5.0 %"))
    }

    func testKTermCarriedAsRatioAndCancelsForRatioOfRatios() {
        // Twenty percent per k-factor gives about 28 % on a ratio.
        let r1 = SigmaTerms.cliffLorimerRatio(counting: 0.05, kA: 0.2, kB: 0.2)
        XCTAssertEqual(r1[.k], 0.2 * 2.0.squareRoot(), accuracy: 1e-15)
        XCTAssertEqual(r1[.k], 0.283, accuracy: 5e-4)
        let r2 = SigmaTerms.cliffLorimerRatio(counting: 0.12, kA: 0.2, kB: 0.2)
        let rr = SigmaTerms.ratioOfRatios(r1, r2)
        XCTAssertEqual(rr[.k], 0)
        XCTAssertEqual(rr[.counting], (0.05 * 0.05 + 0.12 * 0.12).squareRoot(), accuracy: 1e-15)
        XCTAssertEqual(rr.combined, rr[.counting], accuracy: 1e-15)
    }

    private struct Amplitudes: FittedAmplitudes {
        let values: [Double]
        let covariance: [Double]
    }

    func testAmplitudeCovarianceRatioVariance() {
        // a = [10, 5], Var = [4, 1], Cov = 0.5: relative variance of a0/a1
        // = 4/100 + 1/25 - 2*0.5/50 = 0.06.
        let a = Amplitudes(values: [10, 5], covariance: [4, 0.5, 0.5, 1])
        XCTAssertEqual(a.sigma(at: 0), 2, accuracy: 1e-15)
        XCTAssertEqual(a.ratioRelativeVariance(0, 1), 0.06, accuracy: 1e-15)
    }

    // MARK: live time

    /// SplitMix64 with exact Poisson sampling by inversion (mean up to a few hundred is enough here).
    struct Rng {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        mutating func uniform() -> Double { (Double(next() >> 11) + 0.5) / 9007199254740992.0 }
        mutating func gaussian() -> Double {
            (-2 * log(uniform())).squareRoot() * cos(2 * Double.pi * uniform())
        }
        mutating func poisson(_ lambda: Double) -> Double {
            if lambda > 500 { return max((lambda + lambda.squareRoot() * gaussian()).rounded(), 0) }
            let u = uniform()
            var k = 0.0
            var p = exp(-lambda)
            var cdf = p
            while cdf < u && k < 10_000 { k += 1; p *= lambda / k; cdf += p }
            return k
        }
    }

    /// One region of equal composition: Al Kα 500 /s and Mg Kα 20 /s of LIVE time, over `pixels`
    /// pixels of 0.1 s real time at the given dead-time fraction. Per-pixel live time jitters.
    private func region(dead: Double, pixels: Int, rng: inout Rng, noisy: Bool)
        -> (alNet: Double, mgNet: Double, live: [Double]) {
        let live = (0..<pixels).map { _ in 0.1 * (1 - dead) * (1 + 0.1 * (rng.uniform() - 0.5)) }
        let t = live.reduce(0, +)
        let al = 500 * t, mg = 20 * t
        return noisy ? (rng.poisson(al), rng.poisson(mg), live) : (al, mg, live)
    }

    func testLiveTimeRoutesAgreeAcrossDeadTimeNoiseFree() {
        var rng = Rng(state: 7)
        let a = region(dead: 0.3, pixels: 1000, rng: &rng, noisy: false)
        let b = region(dead: 0.6, pixels: 1000, rng: &rng, noisy: false)
        let ra = LiveTimeNormalisation.normalise(net: a.mgNet, variance: a.mgNet, liveTimes: a.live, referenceNet: a.alNet, referenceVariance: a.alNet)!
        let rb = LiveTimeNormalisation.normalise(net: b.mgNet, variance: b.mgNet, liveTimes: b.live, referenceNet: b.alNet, referenceVariance: b.alNet)!
        XCTAssertEqual(ra.route, .perPixelLiveTime)
        XCTAssertEqual(ra.value, 20, accuracy: 1e-9)
        XCTAssertEqual(rb.value, 20, accuracy: 1e-9)
        let fa = LiveTimeNormalisation.normalise(net: a.mgNet, variance: a.mgNet, liveTimes: nil, referenceNet: a.alNet, referenceVariance: a.alNet)!
        let fb = LiveTimeNormalisation.normalise(net: b.mgNet, variance: b.mgNet, liveTimes: nil, referenceNet: b.alNet, referenceVariance: b.alNet)!
        XCTAssertEqual(fa.route.label, "Al Kα internal reference")
        XCTAssertEqual(fa.value, 0.04, accuracy: 1e-12)
        XCTAssertEqual(fb.value, 0.04, accuracy: 1e-12)
        // Raw counts differ by the live-time ratio (0.7/0.4): the normalisation is doing the work.
        XCTAssertGreaterThan(a.mgNet / b.mgNet, 1.7)
    }

    func testLiveTimeRoutesAgreeWithinOneSigmaUnderPoissonNoise() {
        var within = [0, 0]
        var zSum = [0.0, 0.0]
        let trials = 400
        for seed in 0..<trials {
            var rng = Rng(state: UInt64(1000 + seed))
            let a = region(dead: 0.3, pixels: 1000, rng: &rng, noisy: true)
            let b = region(dead: 0.6, pixels: 1000, rng: &rng, noisy: true)
            for (i, useLive) in [true, false].enumerated() {
                let ra = LiveTimeNormalisation.normalise(net: a.mgNet, variance: a.mgNet, liveTimes: useLive ? a.live : nil, referenceNet: a.alNet, referenceVariance: a.alNet)!
                let rb = LiveTimeNormalisation.normalise(net: b.mgNet, variance: b.mgNet, liveTimes: useLive ? b.live : nil, referenceNet: b.alNet, referenceVariance: b.alNet)!
                if LiveTimeNormalisation.agree(ra, rb, withinSigmas: 1) { within[i] += 1 }
                zSum[i] += (ra.value - rb.value) / (ra.sigma * ra.sigma + rb.sigma * rb.sigma).squareRoot()
                XCTAssertTrue(LiveTimeNormalisation.agree(ra, rb, withinSigmas: 4.5), "route \(i) seed \(seed)")
            }
        }
        for i in 0..<2 {
            let frac = Double(within[i]) / Double(trials)
            // Equal composition: |difference| <= 1 combined sigma ~68 % of the time, mean z ~ 0.
            XCTAssertEqual(frac, 0.683, accuracy: 0.09, "route \(i) fraction within 1 sigma")
            XCTAssertEqual(zSum[i] / Double(trials), 0, accuracy: 0.2, "route \(i) mean z")
        }
    }

    func testLiveTimeFallbackIsNamedAndReasoned() {
        // A pixel with live time 0 recorded no exposure: it is left out, the region stays on the live-time route.
        let z = LiveTimeNormalisation.normalise(net: 10, variance: 12, liveTimes: [0.1, 0, 0.1], referenceNet: 100, referenceVariance: 100)!
        XCTAssertEqual(z.route, .perPixelLiveTime)
        XCTAssertEqual(z.value, 10 / 0.2, accuracy: 1e-12)
        // All zero, or a non-finite value (corrupt): fall back and say why.
        XCTAssertNil(LiveTimeNormalisation.pooledLiveTime(perPixel: [0, 0]))
        let r1 = LiveTimeNormalisation.normalise(net: 10, variance: 12, liveTimes: [0.1, .nan], referenceNet: 100, referenceVariance: 100)!
        guard case .alKAlphaInternalReference(let reason) = r1.route else { return XCTFail("NaN live time must fall back") }
        XCTAssertTrue(reason.contains("not finite and positive"))
        let r2 = LiveTimeNormalisation.normalise(net: 10, variance: 12, liveTimes: nil, referenceNet: 100, referenceVariance: 100)!
        guard case .alKAlphaInternalReference(let reason2) = r2.route else { return XCTFail() }
        XCTAssertTrue(reason2.contains("no per-pixel live time"))
        XCTAssertNil(LiveTimeNormalisation.normalise(net: 10, variance: 12, liveTimes: nil, referenceNet: 0, referenceVariance: 0))
    }

    // MARK: coverage (T1 scaffold)

    private struct Coverage { var full: Double; var halved: Double }

    /// Fraction of Poisson(lambda) draws whose Garwood interval (confidence 0.68) covers lambda,
    /// and the same for the interval halved about the observed count. Intervals are cached per count.
    private func coverage(lambda: Double, trials: Int, seed: UInt64) -> Coverage {
        var rng = Rng(state: seed)
        var cache: [Double: CountingInterval] = [:]
        var full = 0, halved = 0
        for _ in 0..<trials {
            let n = rng.poisson(lambda)
            let iv = cache[n] ?? CountingInterval.garwood(count: n, confidence: 0.68)
            cache[n] = iv
            if iv.contains(lambda) { full += 1 }
            if iv.scaled(by: 0.5).contains(lambda) { halved += 1 }
        }
        return Coverage(full: Double(full) / Double(trials), halved: Double(halved) / Double(trials))
    }

    func testCoverageAcrossTheCountLadder() {
        // Measured, not assumed (see the lane report): exact intervals over-cover a discrete
        // Poisson, grossly so below a few counts. The contract tested is: never under 68 %,
        // inside 68-80 % where the counts are large enough for the discreteness to matter little
        // (N >= 10), and the halved interval falls below 50 % from N = 1 up.
        var line = ""
        for lambda in [0.3, 1, 3, 10, 30, 100] {
            let c = coverage(lambda: lambda, trials: 40_000, seed: UInt64(lambda * 1000) + 5)
            line += String(format: "N=%g full=%.3f halved=%.3f; ", lambda, c.full, c.halved)
            // Sanity check only: an exact interval cannot under-cover, so this cannot catch a wrong variance.
            XCTAssertGreaterThanOrEqual(c.full, 0.68 - 0.01, "sanity: never under-covers at N=\(lambda)")
            if lambda >= 10 { XCTAssertLessThanOrEqual(c.full, 0.80, "N=\(lambda)") }
            // Measured 2026-10-05: below 50 % from N = 1 up; at N = 0.3 the n = 0 interval [0, 0.92]
            // still covers (74 %), a discreteness property, so the claim starts at N = 1.
            if lambda >= 1 { XCTAssertLessThan(c.halved, 0.50, "halving must drop coverage below 50 % at N=\(lambda)") }
        }
        print("COVERAGE " + line)
    }
}
