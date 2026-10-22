//
//  RichardsonLucyPinsTests.swift
//  Role: SpectroKit 0.10.0 against exSpy 0.3.2 (Fixtures/eelsrm-pins.json, tools/eels-rl-mlls/pins.py): `richardson_lucy_deconvolution` with a
//        shared and with a per-pixel PSF, a flat-topped PSF (argmax tie), an off-centre PSF, 0 / 5 / 15 / 40 iterations, and a spectrum
//        whose iterate is 0 / 0 (exSpy NaN; here zeros and a reason).
//        Tolerance: upstream has no numeric test for the function (only that it is refused on a non-uniform axis), so `assert_allclose`
//        defaults for float64: rtol 1e-7, atol 0, per channel.
//

import Foundation
import Testing
import SpectroTestSupport
import SpectroEELS

enum EelsRMPins {
    static let directory = FixtureDirs.fixtures(of: "SpectroEELSTests")

    nonisolated(unsafe) static let pins: [String: Any] = {
        let data = try! Data(contentsOf: directory.appendingPathComponent("eelsrm-pins.json"))
        return try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    }()

    static func array(_ name: String) -> [Double] {
        let data = try! Data(contentsOf: directory.appendingPathComponent("eelsrm-\(name).f64"))
        return data.withUnsafeBytes { raw in (0 ..< raw.count / 8).map { raw.loadUnaligned(fromByteOffset: $0 * 8, as: Double.self) } }
    }

    static func number(_ any: Any?) -> Double {
        if any == nil || any is NSNull { return .nan }
        return (any as! NSNumber).doubleValue
    }

    static func numbers(_ any: Any?) -> [Double] { (any as! [Any]).map { number($0) } }
}

struct RichardsonLucyPinsTests {

    @Test func testRichardsonLucyEqualsExSpy() throws {
        let cases = EelsRMPins.pins["rl"] as! [String: [String: Any]]
        #expect(cases.count == 10)
        var overall = 0.0
        for name in cases.keys.sorted() {
            let c = cases[name]!
            let nx = c["nx"] as! Int, ny = c["ny"] as! Int, n = c["channels"] as! Int, iterations = c["iterations"] as! Int
            let scale = EelsRMPins.number(c["scaleEV"])
            let signal = EelsRMPins.array(c["signalFile"] as! String)
            let psfCounts = EelsRMPins.array(c["psfFile"] as! String)
            let want = EelsRMPins.array(c["resultFile"] as! String)
            let shared = c["psfShared"] as! Bool
            let image = try CoreLossSpectrumImage(nx: nx, ny: ny, channels: n, counts: signal, energyOffsetEV: 0, energyScaleEV: scale)
            let psf = try CoreLossSpectrumImage(nx: shared ? 1 : nx, ny: shared ? 1 : ny, channels: n, counts: psfCounts,
                                                 energyOffsetEV: 0, energyScaleEV: scale)
            let out = try EELSDeconvolution.richardsonLucy(image, psf: psf, options: RichardsonLucyOptions(iterations: iterations))
            #expect(out.image.channels == n && out.image.energyScaleEV == scale && out.image.energyOffsetEV == 0, Comment(rawValue: name))
            let nan = Set(c["nanPixels"] as! [Int])
            var worst = 0.0
            for p in 0 ..< nx * ny {
                if nan.contains(p) {
                    #expect(out.unavailable[p] != nil, Comment(rawValue: "\(name) pixel \(p) is NaN in exSpy, must be unavailable"))
                    #expect(out.image.counts[p * n ..< (p + 1) * n].allSatisfy { $0 == 0 }, Comment(rawValue: "\(name) pixel \(p)"))
                    continue
                }
                #expect(out.unavailable[p] == nil, Comment(rawValue: "\(name) pixel \(p): \(String(describing: out.unavailable[p]))"))
                for k in p * n ..< (p + 1) * n {
                    let allowed = 1e-7 * abs(want[k])
                    let error = abs(out.image.counts[k] - want[k])
                    worst = max(worst, allowed > 0 ? error / allowed : (error == 0 ? 0 : .infinity))
                }
            }
            print("richardson_lucy \(name): \(iterations) iterations, worst error / allowance (rtol 1e-7) = \(worst)")
            #expect(worst <= 1, Comment(rawValue: "\(name): \(worst) of the allowance"))
            overall = max(overall, worst)
        }
        print("richardson_lucy: worst of all cases \(overall) of the allowance")
    }
}
