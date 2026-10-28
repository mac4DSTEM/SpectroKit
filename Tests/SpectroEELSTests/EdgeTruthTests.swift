//
//  EdgeTruthTests.swift
//  Role: The ratio method against the
//        planted truth of tools/eels-edge/make_planted.py (NumPy only; the cross section's shape is exSpy's, so this tests
//        the background, the windows and the ratio), on the first planted set and set R.
//
//  Gate 3: noiseless single scattering, |n − (n_true + predicted bias)| ≤ 1e-9 n_true on both sets, every window and Δ;
//  set R: |n − n_true| ≤ 2 % n_true at Δ 50 with the default window. Gate 4: plural scattering, the same exact-bias clause
//  for I_low(Δ) and for the I_0 route. Gate 5: |n_noisy − n_noiseless| ≤ 4 σ_n per pixel on both sets; on set R over 200
//  realisations (seeds 1 to 200, drawn here) the standard deviation of n within 15 % of σ_n for n_true ≥ 500.
//

import Foundation
import Testing
import SpectroTestSupport
import SpectroEELS

struct EdgeTruthTests {

    struct Set { let tag: String; let truth: String; let prefix: String }
    static let sets = [Set(tag: "registered", truth: "edge-planted-truth.json", prefix: "edge-"),
                       Set(tag: "R", truth: "edge-planted-truth-R.json", prefix: "edge-")]

    static func files(_ set: Set, _ c: String, _ kind: String) -> (core: String, low: String) {
        let mid = set.tag == "R" ? "R-" : ""
        return ("edge-core-\(mid)\(c)-\(kind).f64", "edge-low-\(mid)\(c)-\(kind).f64")
    }

    static func run(core: CoreLossSpectrumImage, low: LowLossIntensity, window: [Double], delta: Double) throws -> ArealDensityMap {
        try EELSEdgeQuantification.ratioMethod(coreLoss: core, edge: .carbonK, microscope: EdgeFixtures.plantedMicroscope,
                                               lowLoss: low, backgroundWindowEV: window[0]...window[1],
                                               integrationWidthEV: delta)
    }

    // Gates 3 and 4: noiseless, every case, window and width, both routes, against the method's own predicted bias.
    @Test func testNoiselessRecoversTheTruthUpToThePredictedBias() throws {
        var worst = 0.0, worstAt = "", worstR2 = 0.0
        for set in Self.sets {
            let truth = EdgeFixtures.load(set.truth)
            let pixels = truth["pixels"] as! [[String: Any]]
            let nTrue = pixels.map { $0.x("nTrue") }
            for (c, cv) in truth.d("cases") {
                let cs = cv as! [String: Any]
                let f = Self.files(set, c, "noiseless")
                let core = try EdgeFixtures.core(f.core), low = try EdgeFixtures.low(f.low)
                for (wn, wv) in cs.d("windows") {
                    let w = wv as! [String: Any]
                    for (delta, dv) in w.d("byDelta") {
                        let dd = dv as! [String: Any]
                        let map = try Self.run(core: core, low: .integratedToWidth(low), window: w.a("valueRangeEV"),
                                               delta: Double(delta)!)
                        let pred = dd.a("nPredicted")
                        for p in 0 ..< 15 {
                            let n = map.pixels[p].atomsPerNM2.orFail()
                            let e = abs(n - pred[p]) / nTrue[p]
                            if e > worst { worst = e; worstAt = "\(set.tag) \(c) \(wn) Δ \(delta) px \(p)" }
                            if set.tag == "R", c == "ss", wn == "default", delta == "50" {
                                worstR2 = max(worstR2, abs(n - nTrue[p]) / nTrue[p])
                            }
                        }
                        for (theta, tv) in dd.d("i0Route") {
                            let t = tv as! [String: Any]
                            let tm = try EELSThickness.logRatio(low, threshold: .fixed(Double(theta)!))
                            let m0 = try Self.run(core: core, low: .zeroLoss(tm), window: w.a("valueRangeEV"), delta: Double(delta)!)
                            let p0 = t.a("nPredicted")
                            for p in 0 ..< 15 {
                                let e = abs(m0.pixels[p].atomsPerNM2.orFail() - p0[p]) / nTrue[p]
                                if e > worst { worst = e; worstAt = "\(set.tag) \(c) \(wn) Δ \(delta) θ \(theta) px \(p)" }
                            }
                        }
                    }
                }
            }
        }
        print("planted truth: worst |n − predicted| / n_true = \(worst) at \(worstAt); set R, Δ 50, default: worst |n/n_true − 1| = \(worstR2)")
        #expect(worst <= (1e-9), "\(worstAt)")
        #expect(worstR2 <= 0.02)
        #expect(worstR2 > 0)        // the bias exists; a zero would mean the port read the truth, not the counts
    }

    // Gate 5, per pixel: the noisy image within 4 σ_n of the noiseless one, both sets, every case, window and width; and the
    // port's σ_n equals the generator's (the same formula, the image's own counts).
    @Test func testNoisyWithinFourSigma() throws {
        var worstZ = 0.0, worstSigma = 0.0
        for set in Self.sets {
            let pins = EdgeFixtures.pins.d(set.tag == "R" ? "plantedR" : "planted")
            let images = pins["images"] as! [[String: Any]]
            let truth = EdgeFixtures.load(set.truth)
            for (c, _) in truth.d("cases") {
                let fq = Self.files(set, c, "noiseless"), fn = Self.files(set, c, "noisy")
                let q = (try EdgeFixtures.core(fq.core), try EdgeFixtures.low(fq.low))
                let n = (try EdgeFixtures.core(fn.core), try EdgeFixtures.low(fn.low))
                let pin = images.first { ($0["coreFile"] as! String) == fn.core }!
                for (wn, wv) in pin.d("windows") {
                    let w = wv as! [String: Any]
                    for (delta, dv) in w.d("byDelta") {
                        let dd = dv as! [String: Any]
                        let a = try Self.run(core: q.0, low: .integratedToWidth(q.1), window: w.a("valueRangeEV"), delta: Double(delta)!)
                        let b = try Self.run(core: n.0, low: .integratedToWidth(n.1), window: w.a("valueRangeEV"), delta: Double(delta)!)
                        for p in 0 ..< 15 {
                            let s = b.pixels[p].sigmaCounting.orFail()
                            worstSigma = max(worstSigma, relativeDifference(s, dd.a("sigmaN")[p]))
                            let z = abs(b.pixels[p].atomsPerNM2.orFail() - a.pixels[p].atomsPerNM2.orFail()) / s
                            worstZ = max(worstZ, z)
                            #expect(z <= 4, "\(set.tag) \(c) \(wn) Δ \(delta) px \(p)")
                        }
                    }
                }
            }
        }
        print("noisy: worst |Δn| / σ_n = \(worstZ); port σ_n vs generator's: \(worstSigma)")
        #expect(worstSigma <= (1e-9))
    }

    // Gate 5, the spread: set R, single scattering, Δ 50, default window, 200 Poisson realisations of the noiseless image.
    @Test func testTwoHundredRealisationsMatchSigma() throws {
        let f = Self.files(Self.sets[1], "ss", "noiseless")
        let core = try EdgeFixtures.core(f.core), low = try EdgeFixtures.low(f.low)
        let truth = EdgeFixtures.load(Self.sets[1].truth)
        let nTrue = (truth["pixels"] as! [[String: Any]]).map { $0.x("nTrue") }
        let window = EELSEdgeQuantification.defaultBackgroundWindow(onsetEV: 284)
        var samples = [[Double]](repeating: [], count: 15), sigmas = [[Double]](repeating: [], count: 15)
        for seed in 1 ... 200 {
            var g = Xoshiro256StarStar(seed: UInt64(seed))
            let cn = try CoreLossSpectrumImage(nx: 5, ny: 3, channels: core.channels, counts: core.counts.map { g.poisson($0) },
                                               energyOffsetEV: core.energyOffsetEV, energyScaleEV: core.energyScaleEV)
            let ln = try LowLossSpectrumImage(nx: 5, ny: 3, channels: low.channels, counts: low.counts.map { g.poisson($0) },
                                              energyOffsetEV: low.energyOffsetEV, energyScaleEV: low.energyScaleEV)
            let m = try Self.run(core: cn, low: .integratedToWidth(ln), window: [window.lowerBound, window.upperBound], delta: 50)
            for p in 0 ..< 15 {
                samples[p].append(m.pixels[p].atomsPerNM2.orFail()); sigmas[p].append(m.pixels[p].sigmaCounting.orFail())
            }
        }
        var lines = [String]()
        for p in 0 ..< 15 {
            let mean = samples[p].reduce(0, +) / 200
            let sd = (samples[p].map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / 199).squareRoot()
            let sigma = sigmas[p].reduce(0, +) / 200
            let ratio = sd / sigma
            lines.append("px \(p) n_true \(nTrue[p]): sd/σ_n = \(ratio)")
            if nTrue[p] >= 500 { #expect(isEqual(ratio, 1, accuracy: 0.15), "px \(p)") }
        }
        print("200 realisations (set R, ss, Δ 50, default window):\n" + lines.joined(separator: "\n"))
    }
}
