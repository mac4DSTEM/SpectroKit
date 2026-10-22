//
//  MLLSPinsTests.swift
//  Role: SpectroKit 0.10.0 against HyperSpy 2.4.0 / exSpy 0.3.2 (Fixtures/eelsrm-pins.json, tools/eels-rl-mlls/pins.py): the multiple linear
//        least squares fit, `Model1D.fit(optimizer="lstsq")` of the EELS model with the power-law exponent fixed, per pixel: A, the edge
//        intensities, their standard errors (`p_std`), the residual sum of squares, the degrees of freedom, the fit window and the model
//        curve, on noise-free and Poisson-noisy images, with and without the low-loss convolution, over the whole axis and an explicit
//        window, with the exponent planted ("given") or from `two_area_background_estimation()`.
//        Tolerance: HyperSpy's own tests compare lstsq against Levenberg-Marquardt with `assert_allclose` defaults (rtol 1e-7, atol 0) on
//        the values and on `p_std` (`exspy/tests/models/test_linear_model.py::test_convolved_and_std_error`); the same defaults here.
//        One exception, a kit decision: where the residual is rounding noise (the noise-free image with the planted exponent, RSS ~ 1e-28 of
//        the data's sum of squares) the residual and the standard errors that follow from it are not comparable between two LAPACKs; there
//        both must sit at the noise floor (RSS < 1e-20 of the data's sum of squares, standard error < 1e-9 of its amplitude).
//

import Foundation
import Testing
import SpectroTestSupport
import SpectroEELS

struct MLLSPinsTests {

    struct Case {
        let key: String
        let edges: [CoreLossEdge]
        let masters: [String]
        let microscope: EELSMicroscope
        let core: CoreLossSpectrumImage
        let low: LowLossSpectrumImage?
        let record: [String: Any]
    }

    static func cases() throws -> [Case] {
        let all = EelsRMPins.pins["mlls"] as! [String: [String: Any]]
        return try all.keys.sorted().map { key in
            let c = all[key]!
            let edges = (c["edges"] as! [String]).map { s -> CoreLossEdge in
                let parts = s.split(separator: "_").map(String.init)
                return CoreLossEdge.bundled(parts[0], parts[1] == "K" ? "K1" : parts[1])!
            }
            let mic = EelsRMPins.numbers(c["microscope"])
            let ax = c["axis"] as! [String: Any]
            let nx = c["nx"] as! Int, ny = c["ny"] as! Int
            let core = try CoreLossSpectrumImage(nx: nx, ny: ny, channels: ax["size"] as! Int, counts: EelsRMPins.array(c["coreFile"] as! String),
                                                 energyOffsetEV: EelsRMPins.number(ax["offsetEV"]), energyScaleEV: EelsRMPins.number(ax["scaleEV"]))
            var low: LowLossSpectrumImage?
            if let f = c["lowLossFile"] as? String {
                let la = c["lowLossAxis"] as! [String: Any]
                low = try LowLossSpectrumImage(nx: nx, ny: ny, channels: la["size"] as! Int, counts: EelsRMPins.array(f),
                                               energyOffsetEV: EelsRMPins.number(la["offsetEV"]), energyScaleEV: EelsRMPins.number(la["scaleEV"]))
            }
            return Case(key: key, edges: edges, masters: c["masters"] as! [String],
                        microscope: EELSMicroscope(beamEnergyKeV: mic[0], convergenceMrad: mic[1], collectionMrad: mic[2]),
                        core: core, low: low, record: c)
        }
    }

    static func options(_ c: Case) -> EELSMLLSOptions {
        let w = c.record["window"] as! [String: Any]
        let start = (w["startEV"] as? NSNumber)?.doubleValue, end = (w["endEV"] as? NSNumber)?.doubleValue
        let exponent: EELSBackgroundExponent = (c.record["mode"] as! String) == "twoArea" ? .twoArea : .perPixel(EelsRMPins.numbers(c.record["r"]))
        return EELSMLLSOptions(exponent: exponent, startEnergyEV: start, endEnergyEV: end)
    }

    /// error / (rtol 1e-7 |want|): at most 1 is agreement.
    static func ratio(_ got: Double, _ want: Double) -> Double {
        let allowed = 1e-7 * abs(want), error = abs(got - want)
        return allowed > 0 ? error / allowed : (error == 0 ? 0 : .infinity)
    }

    @Test func testMLLSEqualsHyperSpyLstsq() throws {
        let cases = try Self.cases()
        #expect(cases.count == 14)
        var overall: [String: Double] = [:]
        func note(_ what: String, _ v: Double) { overall[what] = max(overall[what] ?? 0, v) }
        for c in cases {
            let result = try EELSMLLS.fit(coreLoss: c.core, edges: c.edges, microscope: c.microscope, lowLoss: c.low, options: Self.options(c))
            let rec = c.record
            // the window, exactly
            let w = rec["window"] as! [String: Any]
            #expect(result.windowChannels.lowerBound == w["i1"] as! Int && result.windowChannels.upperBound + 1 == w["i2"] as! Int, Comment(rawValue: c.key))
            #expect(result.edges.map { $0.element + "_" + ($0.subshell == "K1" ? "K" : $0.subshell) } == rec["order"] as! [String], Comment(rawValue: c.key))
            let np = c.core.pixelCount, n = c.core.channels
            let dof = rec["dof"] as! [Int]
            let a = EelsRMPins.numbers(rec["A"]), aStd = EelsRMPins.numbers(rec["AStd"]), r = EelsRMPins.numbers(rec["r"]), rss = EelsRMPins.numbers(rec["rss"])
            let intensity = rec["intensity"] as! [String: Any], intensityStd = rec["intensityStd"] as! [String: Any]
            let curve = EelsRMPins.array(rec["curveFile"] as! String)
            var worst: [String: Double] = [:]
            let data = c.core.counts
            func add(_ what: String, _ v: Double) { worst[what] = max(worst[what] ?? 0, v) }
            for p in 0 ..< np {
                let px = result.pixels[p]
                let sumSquares = data[p * n ..< (p + 1) * n].reduce(0) { $0 + $1 * $1 }
                let atNoiseFloor = rss[p] < 1e-20 * sumSquares
                #expect(px.unavailable == nil, Comment(rawValue: "\(c.key) pixel \(p)"))
                #expect(px.degreesOfFreedom == dof[p], Comment(rawValue: "\(c.key) pixel \(p): dof"))
                add("exponent", Self.ratio(px.exponent!, r[p]))
                add("A", Self.ratio(px.background!.value, a[p]))
                if atNoiseFloor {
                    // fraction of the noise-floor bound, so that "at most 1" still means agreement
                    add("A std (noise floor)", px.background!.standardError! / (1e-9 * abs(px.background!.value)))
                    add("RSS (noise floor)", px.residualSumOfSquares! / (1e-20 * sumSquares))
                } else {
                    add("A std", Self.ratio(px.background!.standardError!, aStd[p]))
                    add("RSS", Self.ratio(px.residualSumOfSquares!, rss[p]))
                }
                for (g, edge) in result.edges.enumerated() {
                    let key = edge.element + "_" + (edge.subshell == "K1" ? "K" : edge.subshell)
                    add("intensity", Self.ratio(px.intensities[g].value, EelsRMPins.numbers(intensity[key])[p]))
                    if atNoiseFloor {
                        add("intensity std (noise floor)", px.intensities[g].standardError! / (1e-9 * abs(px.intensities[g].value)))
                    } else {
                        add("intensity std", Self.ratio(px.intensities[g].standardError!, EelsRMPins.numbers(intensityStd[key])[p]))
                    }
                }
                let mine = try #require(result.modelCurve(pixel: p))
                for k in 0 ..< n { add("curve", Self.ratio(mine[k], curve[p * n + k])) }
            }
            for (what, v) in worst.sorted(by: { $0.key < $1.key }) {
                #expect(v <= 1, Comment(rawValue: "\(c.key) \(what): \(v) of the rtol 1e-7 allowance"))
                note(what, v)
            }
            print("MLLS \(c.key): " + worst.sorted { $0.key < $1.key }.map { "\($0.key) \(String(format: "%.2g", $0.value))" }.joined(separator: ", "))
        }
        print("MLLS worst of all (fractions of the rtol 1e-7 allowance): " + overall.sorted { $0.key < $1.key }.map { "\($0.key) \(String(format: "%.2g", $0.value))" }.joined(separator: ", "))
    }
}
