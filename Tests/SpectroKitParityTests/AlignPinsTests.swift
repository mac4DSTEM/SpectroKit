//
//  AlignPinsTests.swift
//  Role: Task 16 step 1 (docs/design/eels-task-16.md sections 2 and 7) against exSpy 0.3.2 / HyperSpy 2.4.0 (tools/eels-task16/pins.py ->
//        Fixtures/eels16-pins.json): the zero-loss peak centre and mask, `estimate_shift1D`, `shift1D` and the eleven `align_zero_loss_peak`
//        variants (offset, size, scale, data, the shifts applied, `also_align`).
//
//  Tolerances: upstream's own (`test_eels.py::TestAlignZLP` assert_allclose defaults, `test_1D_tools.py` atol 1e-3 eV for shifts) are the
//  floor; the port repeats HyperSpy's arithmetic, so the pins are held tighter: centres and masks exact, shifts 1e-9 eV, data rtol 1e-7 with atol
//  1e-9 x max|pinned| (design section 7 for results that are sums of linear interpolation and cancel), offset and scale 1e-12.
//

import Foundation
import Testing
import SpectroTestSupport
import SpectroEELS
import SpectroCore

struct AlignPinsTests {

    private func close(_ a: [Double], _ b: [Double], rtol: Double = 1e-7, atolScale: Double = 1e-9) -> Bool {
        guard a.count == b.count else { return false }
        let m = b.filter { $0.isFinite }.map(\.magnitude).max() ?? 1
        return zip(a, b).allSatisfy { x, y in
            if x.isNaN || y.isNaN { return x.isNaN && y.isNaN }
            return abs(x - y) <= atolScale * m + rtol * abs(y)
        }
    }

    // MARK: centre and mask

    @Test func testZeroLossPeakCentrePins() throws {
        let centre = Eels16.dict("zlp", "centre")
        for (name, file, mask) in [("plain", "zlp-ll", nil), ("masked", "zlp-ll", Eels16.alignMask), ("spike", "zlp-ll-spike", nil)] as [(String, String, [Bool]?)] {
            let got = try EELSAlignment.zeroLossPeakCentre(try Eels16.lowLoss(file), mask: mask)
            let pin = Eels16.flat(centre[name])
            #expect(got.count == pin.count, "\(name)")
            for (g, p) in zip(got, pin) {
                if p.isNaN { #expect(g == nil, "\(name): masked pixel gives nil") } else { #expect(isEqual(g ?? .nan, p, accuracy: 1e-12), "\(name): \(String(describing: g)) vs \(p)") }
            }
        }
    }

    @Test func testZeroLossPeakMaskPinsAreExact() throws {
        let image = try Eels16.lowLoss()
        for (name, any) in Eels16.dict("zlp", "mask") {
            let record = any as! [String: Any]
            let signal = (record["signalMask"] as? [Any])?.map { ($0 as! NSNumber).boolValue }
            let width = name.hasPrefix("w2.0") ? 2.0 : 5.0
            let got = try EELSAlignment.zeroLossPeakMask(image, widthEV: width, signalMask: signal)
            let pin = (record["mask"] as! [Any]).map { ($0 as! NSNumber).boolValue }
            #expect(got == pin, "\(name)")
        }
    }

    // MARK: estimate_shift1D and shift1D

    @Test func testEstimateShiftPins() throws {
        let image = try Eels16.lowLoss()
        for (name, any) in Eels16.dict("zlp", "estimateShift") {
            let r = any as! [String: Any]
            let got = try EELSAlignment.estimateShift(image, fromEV: Eels16.number(r["fromEV"]), toEV: Eels16.number(r["toEV"]), referencePixel: 0,
                                                      interpolationPoints: r["interpolationPoints"] as! Int)
            let pin = Eels16.flat(r["shiftEV"])
            for (g, p) in zip(got, pin) { #expect(isEqual(g ?? .nan, p, accuracy: 1e-9), "\(name): \(String(describing: g)) vs \(p)") }
            // upstream's own tolerance (atol 1e-3 eV) is met with room to spare
            for (g, p) in zip(got, pin) { #expect(isEqual(g ?? .nan, p, accuracy: 1e-3)) }
        }
    }

    @Test func testShift1DPins() throws {
        let s = Eels16.dict("zlp", "shift1D")
        let input = Eels16.array(s["inputFile"] as! String)
        let image = try LowLossSpectrumImage(nx: 4, ny: 1, channels: 40, counts: input, energyOffsetEV: Eels16.number(s["offsetEV"]), energyScaleEV: Eels16.number(s["scaleEV"]))
        let shifts = Eels16.flat(s["shiftEV"]).map { Optional($0) }
        for (name, crop) in [("crop", true), ("nocrop", false)] {
            let pin = (s["cases"] as! [String: Any])[name] as! [String: Any]
            let (out, kept) = try EELSAlignment.shift(image, byEV: shifts, crop: crop)
            #expect(out.channels == pin["channels"] as! Int, "\(name)")
            #expect(isEqual(out.energyOffsetEV, Eels16.number(pin["offsetEV"]), accuracy: 1e-12), "\(name) offset")
            #expect(kept.count == out.channels)
            #expect(close(out.counts, Eels16.array(pin["file"] as! String), rtol: 1e-7, atolScale: 1e-12), "\(name) data")
        }
    }

    // MARK: align_zero_loss_peak, the eleven variants

    @Test func testAlignZeroLossPeakPins() throws {
        let image = try Eels16.lowLoss()
        let spike = try Eels16.lowLoss("zlp-ll-spike")
        let core = try Eels16.coreLoss()
        for (name, any) in Eels16.dict("zlp", "align") {
            let r = any as! [String: Any]
            let kw = r["kwargs"] as! [String: Any]
            var options = ZeroLossAlignmentOptions()
            if let v = kw["calibrate"] as? Bool { options.calibrate = v }
            if let v = kw["subpixel"] as? Bool { options.subpixel = v }
            if let v = kw["crop"] as? Bool { options.crop = v }
            if let v = kw["number_of_interpolation_points"] as? Int { options.interpolationPoints = v }
            if let v = kw["signal_range"] as? [Double] { options.signalRangeEV = v[0]...v[1] }
            let source = (r["kind"] as! String) == "ll" ? image : spike
            let useMask = r["maskUsed"] as! Bool
            let also = r["alsoAligned"] != nil ? [core] : []
            let got = try EELSAlignment.alignZeroLossPeak(source, alsoAlign: also, mask: useMask ? Eels16.alignMask : nil, options: options)
            #expect(got.aligned.channels == r["channels"] as! Int, "\(name) channels")
            #expect(isEqual(got.aligned.energyOffsetEV, Eels16.number(r["offsetEV"]), accuracy: 1e-12), "\(name) offset \(got.aligned.energyOffsetEV) vs \(Eels16.number(r["offsetEV"]))")
            #expect(isEqual(got.aligned.energyScaleEV, Eels16.number(r["scaleEV"]), accuracy: 1e-15), "\(name) scale")
            #expect(close(got.aligned.counts, Eels16.array(r["file"] as! String)), "\(name) data")
            // the shifts applied: the sum of the passes exSpy's shift1D received (a NaN entry is not shifted); with also_align exSpy records one
            // entry per signal per pass, so only the plain variants are summed here
            if also.isEmpty {
                let passes = (r["shiftPasses"] as! [Any]).map { Eels16.flat($0) }
                for p in 0..<12 where !passes[0][p].isNaN {
                    let total = passes.reduce(0.0) { $0 + ($1[p].isNaN ? 0 : $1[p]) }
                    #expect(isEqual(got.shiftEV[p] ?? .nan, total, accuracy: 1e-9), "\(name) shift pixel \(p)")
                }
            }
            if let a = r["alsoAligned"] as? [String: Any] {
                let aligned = got.alsoAligned[0]
                #expect(aligned.channels == a["channels"] as! Int, "\(name) also channels")
                #expect(isEqual(aligned.energyOffsetEV, Eels16.number(a["offsetEV"]), accuracy: 1e-12), "\(name) also offset")
                #expect(close(aligned.counts, Eels16.array(a["file"] as! String)), "\(name) also data")
            }
            // the re-estimated centre of the aligned image (exSpy's own check: mean and std of it, assert_allclose defaults)
            let pinCentre = Eels16.flat(r["reestimatedCentreEV"]).filter { !$0.isNaN }
            let ours = try EELSAlignment.zeroLossPeakCentre(got.aligned, mask: useMask ? Eels16.alignMask : nil).compactMap { $0 }
            #expect(ours.count == pinCentre.count)
            for (g, p) in zip(ours, pinCentre) { #expect(isEqual(g, p, accuracy: 1e-9), "\(name) re-estimated centre") }
        }
    }
}
