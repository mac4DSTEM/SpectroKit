//
//  RefuterRegressionTests.swift
//  Role: Images on which an independent review (2026-10-14) found the estimated-threshold route picking another channel than exSpy
//        7185a4d1 (the port's Savitzky-Golay derivative was not bit-equal to SciPy's). Each case has the image (data.f64), the
//        routes asked (spec.json) and exSpy's answers at every pixel (exspy.json); the generators are
//        tools/eels-thickness/edge_cases.py and random_cases.py. B1: negative counts; B3, B5: flat and ramp spectra, where
//        exSpy's threshold is NaN (no inflexion) and the port must say `.noInflexionFound`; R22, R26, R52, R58: random Poisson
//        images whose estimated thresholds were wrong before.
//
//  Auto-SG uses the separately generated portable-thresholds.json numerical-tie policy; raw pins are retained.
//  Required, at EVERY pixel: the threshold energy equal to its reference (portable for auto-SG, raw exSpy otherwise), NaN <-> `.noInflexionFound`,
//  I_0 and I_t within 1e-12 relative, t/lambda within 1e-12 absolute; exSpy's non-finite t/lambda is a nil t/lambda.
//

import Foundation
import Testing
import SpectroTestSupport
import SpectroEELS

struct RefuterRegressionTests {

    private let cases = ["B1_negative_counts", "B3_flat_and_ramp", "B5_ramps", "R22", "R26", "R52", "R58"]

    private func doubles(_ url: URL) throws -> [Double] {
        try Data(contentsOf: url).withUnsafeBytes { Array($0.bindMemory(to: Double.self)) }
    }
    private func num(_ x: Any?) -> Double? { (x as? NSNumber)?.doubleValue }

    @Test func testEveryRefuterImageMatchesExSpyAtEveryPixel() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/refuter")
        var routesChecked = 0, pixelsChecked = 0, nanPixels = 0, estimatedRoutes = 0
        for name in cases {
            let dir = root.appendingPathComponent(name)
            let spec = try JSONSerialization.jsonObject(with: Data(contentsOf: dir.appendingPathComponent("spec.json"))) as! [String: Any]
            let expected = try JSONSerialization.jsonObject(with: Data(contentsOf: dir.appendingPathComponent("exspy.json"))) as! [[String: Any]]
            let img = try LowLossSpectrumImage(nx: spec["cols"] as! Int, ny: spec["rows"] as! Int, channels: spec["size"] as! Int,
                                               counts: try doubles(dir.appendingPathComponent("data.f64")),
                                               energyOffsetEV: num(spec["offset"])!, energyScaleEV: num(spec["scale"])!)
            for (routeIndex, entry) in expected.enumerated() {
                let r = entry["route"] as! [String: Any], ex = entry["exspy"] as! [String: Any]
                let kind = r["kind"] as! String
                let tag = "\(name) \(r)"
                let rule: ThresholdRule
                switch kind {
                case "estimated":
                    rule = .estimated(window: num(r["window"]) ?? 10.0, start: num(r["start"]) ?? 1.0,
                                      windowLength: (r["windowLength"] as? Int) ?? 5, polynomialOrder: (r["polynomialOrder"] as? Int) ?? 3,
                                      tolerance: num(r["tolerance"]))
                    estimatedRoutes += 1
                case "fixed": rule = .fixed(num(r["value"])!)
                default: Issue.record("route kind \(kind)"); continue
                }
                let portable = kind == "estimated" && ((r["windowLength"] as? Int) ?? 5) != 0 && num(r["tolerance"]) == nil
                    ? try PortableThresholds.route(name, index: routeIndex) : nil
                let map = try EELSThickness.logRatio(img, threshold: rule, zeroLoss: nil)
                let it: [Any] = portable?.it.map { $0 as Any } ?? (ex["it"] as! [Any])
                let i0: [Any] = portable?.i0.map { $0.map { $0 as Any } ?? NSNull() } ?? (ex["i0"] as! [Any])
                let tl: [Any] = portable?.tOverLambda.map { $0.map { $0 as Any } ?? NSNull() } ?? (ex["tl"] as! [Any])
                let thresholds: [Any]? = portable?.thresholdEV.map { $0.map { $0 as Any } ?? NSNull() } ?? (ex["thrEV"] as? [Any])
                #expect(map.pixels.count == it.count, "\(tag)")
                for (p, px) in map.pixels.enumerated() {
                    pixelsChecked += 1
                    if let portable, !portable.changedFromRawExSpy.contains(p), let raw = ex["thrEV"] as? [Any] {
                        #expect(px.thresholdEV == num(raw[p]), "\(tag) unambiguous raw exSpy threshold")
                    }
                    if let thr = thresholds {
                        if let e = num(thr[p]) {
                            #expect(px.thresholdEV?.bitPattern == e.bitPattern, "\(tag) pixel \(p): threshold energy")
                        } else {
                            nanPixels += 1
                            #expect(px.thresholdEV == nil, "\(tag) pixel \(p)")
                            #expect(px.unavailable == .noInflexionFound, "\(tag) pixel \(p)")
                        }
                    }
                    if let e = num(it[p]) { #expect(isEqual(px.iTotal, e, accuracy: 1e-12 * abs(e)), "\(tag) pixel \(p) I_t") }
                    else { Issue.record("\(tag) pixel \(p): exSpy I_t is not finite") }
                    if let e = num(tl[p]) {
                        guard let a = px.tOverLambda else { Issue.record("\(tag) pixel \(p): exSpy t/lambda \(e), port nil (\(String(describing: px.unavailable)))"); continue }
                        #expect(isEqual(a, e, accuracy: 1e-12), "\(tag) pixel \(p) t/lambda")
                        if let e0 = num(i0[p]), let a0 = px.i0 { #expect(isEqual(a0, e0, accuracy: 1e-12 * abs(e0)), "\(tag) pixel \(p) I_0") }
                        else { Issue.record("\(tag) pixel \(p): I_0") }
                    } else {
                        #expect(px.tOverLambda == nil, "\(tag) pixel \(p): exSpy t/lambda is not finite")
                    }
                }
                routesChecked += 1
            }
        }
        print("EELS-REPORT threshold regression: \(cases.count) images, \(routesChecked) routes (\(estimatedRoutes) estimated), \(pixelsChecked) pixel-route answers, \(nanPixels) NaN-threshold pixels")
        #expect(nanPixels > 0)
    }
}
