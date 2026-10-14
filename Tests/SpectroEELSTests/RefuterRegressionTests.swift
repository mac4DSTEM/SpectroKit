//
//  RefuterRegressionTests.swift
//  Role: Images on which the Gate B refuter (2026-10-14) found the estimated-threshold route picking another channel than exSpy
//        7185a4d1 (the port's Savitzky-Golay derivative was not bit-equal to SciPy's). Each case has the image (data.f64), the
//        routes asked (spec.json) and exSpy's answers at every pixel (exspy.json); the generators are
//        tools/eels-thickness/refuter_cases.py and refuter_cases_random.py. B1: negative counts; B3, B5: flat and ramp spectra, where
//        exSpy's threshold is NaN (no inflexion) and the port must say `.noInflexionFound`; R22, R26, R52, R58: random Poisson
//        images whose estimated thresholds were wrong before.
//
//  Required, at EVERY pixel: the threshold energy equal to exSpy's (so the same channel; `==`), NaN <-> `.noInflexionFound`,
//  I_0 and I_t within 1e-12 relative, t/lambda within 1e-12 absolute; exSpy's non-finite t/lambda is a nil t/lambda.
//

import Foundation
import XCTest
import SpectroEELS

final class RefuterRegressionTests: XCTestCase {

    private let cases = ["B1_negative_counts", "B3_flat_and_ramp", "B5_ramps", "R22", "R26", "R52", "R58"]

    private func doubles(_ url: URL) throws -> [Double] {
        try Data(contentsOf: url).withUnsafeBytes { Array($0.bindMemory(to: Double.self)) }
    }
    private func num(_ x: Any?) -> Double? { (x as? NSNumber)?.doubleValue }

    func testEveryRefuterImageMatchesExSpyAtEveryPixel() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/refuter")
        var routesChecked = 0, pixelsChecked = 0, nanPixels = 0, estimatedRoutes = 0
        for name in cases {
            let dir = root.appendingPathComponent(name)
            let spec = try JSONSerialization.jsonObject(with: Data(contentsOf: dir.appendingPathComponent("spec.json"))) as! [String: Any]
            let expected = try JSONSerialization.jsonObject(with: Data(contentsOf: dir.appendingPathComponent("exspy.json"))) as! [[String: Any]]
            let img = try LowLossSpectrumImage(nx: spec["cols"] as! Int, ny: spec["rows"] as! Int, channels: spec["size"] as! Int,
                                               counts: try doubles(dir.appendingPathComponent("data.f64")),
                                               energyOffsetEV: num(spec["offset"])!, energyScaleEV: num(spec["scale"])!)
            for entry in expected {
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
                default: XCTFail("route kind \(kind)"); continue
                }
                let map = try EELSThickness.logRatio(img, threshold: rule, zeroLoss: nil)
                let it = ex["it"] as! [Any], i0 = ex["i0"] as! [Any], tl = ex["tl"] as! [Any]
                XCTAssertEqual(map.pixels.count, it.count, tag)
                for (p, px) in map.pixels.enumerated() {
                    pixelsChecked += 1
                    if let thr = ex["thrEV"] as? [Any] {
                        if let e = num(thr[p]) {
                            XCTAssertEqual(px.thresholdEV?.bitPattern, e.bitPattern, "\(tag) pixel \(p): threshold energy")
                        } else {
                            nanPixels += 1
                            XCTAssertNil(px.thresholdEV, "\(tag) pixel \(p)")
                            XCTAssertEqual(px.unavailable, .noInflexionFound, "\(tag) pixel \(p)")
                        }
                    }
                    if let e = num(it[p]) { XCTAssertEqual(px.iTotal, e, accuracy: 1e-12 * abs(e), "\(tag) pixel \(p) I_t") }
                    else { XCTFail("\(tag) pixel \(p): exSpy I_t is not finite") }
                    if let e = num(tl[p]) {
                        guard let a = px.tOverLambda else { XCTFail("\(tag) pixel \(p): exSpy t/lambda \(e), port nil (\(String(describing: px.unavailable)))"); continue }
                        XCTAssertEqual(a, e, accuracy: 1e-12, "\(tag) pixel \(p) t/lambda")
                        if let e0 = num(i0[p]), let a0 = px.i0 { XCTAssertEqual(a0, e0, accuracy: 1e-12 * abs(e0), "\(tag) pixel \(p) I_0") }
                        else { XCTFail("\(tag) pixel \(p): I_0") }
                    } else {
                        XCTAssertNil(px.tOverLambda, "\(tag) pixel \(p): exSpy t/lambda is not finite")
                    }
                }
                routesChecked += 1
            }
        }
        print("EELS-REPORT refuter regression: \(cases.count) images, \(routesChecked) routes (\(estimatedRoutes) estimated), \(pixelsChecked) pixel-route answers, \(nanPixels) NaN-threshold pixels")
        XCTAssertGreaterThan(nanPixels, 0)
    }
}
