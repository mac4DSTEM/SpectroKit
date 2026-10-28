//
//  SpectrumOpsPinsTests.swift
//  Role: Power-law extrapolation and taper against exSpy 0.3.2 / HyperSpy 2.4.0 (Fixtures/eels16-pins.json): the power-law extrapolation (binned axis; A and r by
//        the two-area method, the continuation) and the Hanning taper (channels returned, data). Tolerances: A and r rtol 1e-7 (`test_power_law.py`
//        allclose defaults), the continuation rtol 1e-9, the taper exact to 1e-15 relative (a product with `np.hanning`'s own formula).
//        The UNBINNED power-law cases of the pins are not offered (the kit's spectra are per-channel counts); exSpy's two-area estimate on them
//        is a factor two from the exact power law, a quirk of its Simpson branch, recorded in docs/parity.md.
//

import Foundation
import Testing
import SpectroTestSupport
import SpectroEELS

struct SpectrumOpsPinsTests {

    private func relClose(_ a: [Double], _ b: [Double], rtol: Double, atol: Double = 0) -> Bool {
        guard a.count == b.count else { return false }
        return zip(a, b).allSatisfy { x, y in (x.isNaN && y.isNaN) || abs(x - y) <= atol + rtol * abs(y) }
    }

    @Test func testPowerLawExtrapolationPins() throws {
        let pl = Eels16.dict("powerLaw")
        let offset = Eels16.number(pl["offsetEV"]), scale = Eels16.number(pl["scaleEV"]), channels = pl["channels"] as! Int
        for (name, any) in pl["cases"] as! [String: Any] {
            let c = any as! [String: Any]
            guard c["binned"] as! Bool else { continue }                 // the unbinned branch is not offered
            let image = try LowLossSpectrumImage(nx: 3, ny: 2, channels: channels, counts: Eels16.array(c["inputFile"] as! String),
                                                 energyOffsetEV: offset, energyScaleEV: scale)
            let out = try EELSSpectrumOps.powerLawExtrapolation(image, windowChannels: c["windowChannels"] as! Int,
                                                                extrapolationChannels: c["extrapolationChannels"] as! Int,
                                                                fixNegativeR: c["fixNegativeR"] as! Bool)
            #expect(out.image.channels == c["channels"] as! Int, Comment(rawValue: name))
            #expect(out.image.energyOffsetEV == offset && out.image.energyScaleEV == scale)
            let a = Eels16.flat(c["A"]), r = Eels16.flat(c["r"])
            for p in 0..<6 {
                let fit = try #require(out.fits[p], Comment(rawValue: "\(name) pixel \(p)"))
                #expect(isEqual(fit.a, a[p], accuracy: abs(a[p]) * 1e-7), "\(name) A pixel \(p): \(fit.a) vs \(a[p])")
                #expect(isEqual(fit.r, r[p], accuracy: abs(r[p]) * 1e-7 + 1e-12), "\(name) r pixel \(p)")
            }
            #expect(relClose(out.image.counts, Eels16.array(c["file"] as! String), rtol: 1e-9), "\(name) data")
        }
    }

    @Test func testHanningTaperPins() throws {
        let t = Eels16.dict("taper")
        let input = (t["input"] as! [String: Any])
        let channels = input["channels"] as! Int, rows = input["rows"] as! Int
        let image = try LowLossSpectrumImage(nx: rows, ny: 1, channels: channels, counts: Eels16.array(input["file"] as! String), energyOffsetEV: 0, energyScaleEV: 1)
        for (name, any) in t["cases"] as! [String: Any] {
            let c = any as! [String: Any]
            let kw = c["kwargs"] as! [String: Any]
            if let n = c["n"] as? Int {                                  // the default-width cases: max(20, round(0.02 n))
                #expect(EELSSpectrumOps.defaultTaperChannels(forChannels: n) == c["taperedChannels"] as! Int, Comment(rawValue: name))
                continue
            }
            let side: TaperSide = (kw["side"] as? String).map { $0 == "left" ? .left : $0 == "right" ? .right : .both } ?? .both
            let out = try EELSSpectrumOps.hanningTaper(image, side: side, channels: kw["channels"] as? Int, offset: kw["offset"] as? Int ?? 0)
            #expect(out.taperedChannels == c["taperedChannels"] as! Int, Comment(rawValue: name))
            #expect(relClose(out.image.counts, Eels16.array(c["file"] as! String), rtol: 1e-15, atol: 1e-300), "\(name) data")
        }
    }
}
