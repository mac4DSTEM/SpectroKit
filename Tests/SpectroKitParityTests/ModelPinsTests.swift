//
//  ModelPinsTests.swift
//  Role: Task 16 step 5 against exSpy 0.3.2 (Fixtures/eels16-model-pins.json, tools/eels-task16/model.py): `two_area_background_estimation`,
//        `fit_background`, `smart_fit` (intensities, the model curve) and `quantify`, on noise-free and Poisson-noisy planted images, with
//        and without the low-loss convolution. Tolerances: two-area A and r at the allclose defaults; the fits within the kit's decision
//        (docs/design/eels-task-16.md section 6.2): rtol 1e-3 of exSpy's converged intensities (its LM stops 1e-4 short of the minimum).
//

import Foundation
import Testing
import SpectroTestSupport
import SpectroEELS

struct ModelPinsTests {
    nonisolated(unsafe) static let pins: [String: Any] = {
        let url = FixtureDirs.fixtures(of: "SpectroEELSTests").appendingPathComponent("eels16-model-pins.json")
        return try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    }()

    static func array(_ name: String) -> [Double] {
        let data = try! Data(contentsOf: FixtureDirs.fixtures(of: "SpectroEELSTests").appendingPathComponent("eels16-model-\(name).f64"))
        return data.withUnsafeBytes { raw in (0 ..< raw.count / 8).map { raw.loadUnaligned(fromByteOffset: $0 * 8, as: Double.self) } }
    }

    struct Case {
        let name: String
        let edges: [CoreLossEdge]
        let masters: [String]
        let microscope: EELSMicroscope
        let core: CoreLossSpectrumImage
        let low: LowLossSpectrumImage?
        let record: [String: Any]
    }

    static func cases() throws -> [Case] {
        let all = pins["cases"] as! [String: [String: Any]]
        return try all.keys.sorted().map { name in
            let c = all[name]!
            let edges = (c["edges"] as! [String]).map { s -> CoreLossEdge in
                let parts = s.split(separator: "_").map(String.init)
                return CoreLossEdge.bundled(parts[0], parts[1] == "K" ? "K1" : parts[1])!
            }
            let mic = (c["microscope"] as! [NSNumber]).map(\.doubleValue)
            let ax = c["axis"] as! [String: Any]
            let core = try CoreLossSpectrumImage(nx: c["nx"] as! Int, ny: c["ny"] as! Int, channels: ax["size"] as! Int, counts: array(c["coreFile"] as! String),
                                                 energyOffsetEV: (ax["offsetEV"] as! NSNumber).doubleValue, energyScaleEV: (ax["scaleEV"] as! NSNumber).doubleValue)
            var low: LowLossSpectrumImage?
            if let f = c["lowLossFile"] as? String {
                let la = c["lowLossAxis"] as! [String: Any]
                low = try LowLossSpectrumImage(nx: c["nx"] as! Int, ny: c["ny"] as! Int, channels: la["size"] as! Int, counts: array(f),
                                               energyOffsetEV: (la["offsetEV"] as! NSNumber).doubleValue, energyScaleEV: (la["scaleEV"] as! NSNumber).doubleValue)
            }
            return Case(name: name, edges: edges, masters: c["masters"] as! [String], microscope: EELSMicroscope(beamEnergyKeV: mic[0], convergenceMrad: mic[1], collectionMrad: mic[2]),
                        core: core, low: low, record: c)
        }
    }

    static func nums(_ any: Any?) -> [Double] { (any as! [NSNumber]).map(\.doubleValue) }

    @Test func testTwoAreaBackgroundEqualsExSpy() throws {
        for c in try Self.cases() {
            let got = try EELSModelFit.twoAreaBackground(coreLoss: c.core, edges: c.edges)
            let t = c.record["twoArea"] as! [String: Any]
            let a = Self.nums(t["A"]), r = Self.nums(t["r"])
            for p in 0 ..< a.count {
                let f = try #require(got[p], Comment(rawValue: "\(c.name) pixel \(p)"))
                #expect(abs(f.a - a[p]) <= 1e-7 * abs(a[p]) && abs(f.r - r[p]) <= 1e-7 * abs(r[p]), Comment(rawValue: "\(c.name) \(p): A \(f.a) vs \(a[p]), r \(f.r) vs \(r[p])"))
            }
        }
    }

    @Test func testFitBackgroundEqualsExSpy() throws {
        for c in try Self.cases() {
            let got = try EELSModelFit.fitBackground(coreLoss: c.core, edges: c.edges)
            let t = c.record["fitBackground"] as! [String: Any]
            let a = Self.nums(t["A"]), r = Self.nums(t["r"])
            var worstA = 0.0, worstR = 0.0
            for p in 0 ..< a.count {
                let f = try #require(got[p], Comment(rawValue: "\(c.name) pixel \(p)"))
                worstA = max(worstA, abs(f.a - a[p]) / abs(a[p])); worstR = max(worstR, abs(f.r - r[p]))
            }
            print("fit_background \(c.name): worst A rel \(worstA), r abs \(worstR)")
            if c.name == "fel-exact" {
                #expect(worstA <= 1e-6 && worstR <= 1e-6, Comment(rawValue: "exact data: A \(worstA), r \(worstR)"))
            } else {
                // On noisy data A and r trade off along a valley that exSpy's LM leaves early: the exponents agree to 0.02, A to 10 %.
                #expect(worstA <= 0.1 && worstR <= 0.02, Comment(rawValue: "\(c.name): A \(worstA), r \(worstR)"))
            }
        }
    }

    @Test func testSmartFitEqualsExSpy() throws {
        for c in try Self.cases() {
            let result = try EELSModelFit.fit(coreLoss: c.core, edges: c.edges, microscope: c.microscope, lowLoss: c.low)
            let t = c.record["smart"] as! [String: Any]
            #expect(result.edges.map { $0.element + "_" + $0.subshell } == (t["order"] as! [String]).map { $0.replacingOccurrences(of: "_K", with: "_K1") }, Comment(rawValue: c.name))
            let intensity = t["intensity"] as! [String: Any]
            let curve = Self.array((t["curveFile"] as! String))
            let n = c.core.channels
            var worstI = 0.0, worstCurve = 0.0, worstA = 0.0, worstR = 0.0
            for (g, edge) in result.edges.enumerated() {
                let key = edge.element + "_" + (edge.subshell == "K1" ? "K" : edge.subshell)
                let want = Self.nums(intensity[key])
                for p in 0 ..< want.count {
                    let got = try #require(result.pixels[p][g].intensity, Comment(rawValue: "\(c.name) \(p)"))
                    worstI = max(worstI, abs(got - want[p]) / abs(want[p]))
                }
            }
            let a = Self.nums(t["A"]), r = Self.nums(t["r"])
            for p in 0 ..< c.core.pixelCount {
                let bg = try #require(result.backgrounds[p])
                worstA = max(worstA, abs(bg.a - a[p]) / abs(a[p])); worstR = max(worstR, abs(bg.r - r[p]))
                let mine = try #require(result.modelCurve(pixel: p))
                let ref = Array(curve[p * n ..< (p + 1) * n]), top = ref.max()!
                for k in 0 ..< n { worstCurve = max(worstCurve, abs(mine[k] - ref[k]) / top) }
            }
            print("smart fit \(c.name): intensity rel \(worstI), curve / max \(worstCurve), A rel \(worstA), r abs \(worstR)")
            #expect(result.exponentAtBound.allSatisfy { !$0 }, Comment(rawValue: c.name))
            #expect(worstI <= 1e-3, Comment(rawValue: "\(c.name) intensity \(worstI)"))
            #expect(worstCurve <= 1e-4, Comment(rawValue: "\(c.name) curve \(worstCurve)"))
            if c.name == "fel-exact" { #expect(worstA <= 1e-6 && worstR <= 1e-6, Comment(rawValue: "exact data: A \(worstA), r \(worstR)")) }
            // quantify(): the same lines, the numbers within the intensity tolerance
            let want = (t["quantifyText"] as? String) ?? (c.record["quantifyText"] as! String)
            let got = result.quantifyText(pixel: 0)
            let wl = want.split(separator: "\n"), gl = got.split(separator: "\n")
            #expect(wl.count == gl.count && wl.prefix(2) == gl.prefix(2), Comment(rawValue: "\(c.name): \(got)"))
            for (a, b) in zip(wl.dropFirst(2), gl.dropFirst(2)) {
                let pa = a.split(separator: "\t"), pb = b.split(separator: "\t")
                #expect(pa[0] == pb[0] && abs(Double(pa[1])! - Double(pb[1])!) <= 1e-3 * abs(Double(pa[1])!), Comment(rawValue: "\(c.name): \(a) vs \(b)"))
            }
        }
    }

    /// Timing for the nightly (printed, not asserted): the noisy Fe L image tiled to 64 x 64 pixels of 600 channels.
    @Test func testModelFitSpeed() throws {
        let c = try Self.cases().first { $0.name == "fel" }!
        var counts = [Double]()
        for p in 0 ..< 4096 { counts += c.core.counts[(p % 6) * 600 ..< (p % 6 + 1) * 600] }
        let image = try CoreLossSpectrumImage(nx: 64, ny: 64, channels: 600, counts: counts, energyOffsetEV: c.core.energyOffsetEV, energyScaleEV: c.core.energyScaleEV)
        let start = Date()
        let result = try EELSModelFit.fit(coreLoss: image, edges: c.edges, microscope: c.microscope)
        print("edge model fit, 64 x 64 x 600 channels, one twin pair: \(Date().timeIntervalSince(start)) s")
        #expect(result.pixels.count == 4096)
    }
}
