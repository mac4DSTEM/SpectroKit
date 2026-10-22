//
//  DeconvolutionPinsTests.swift
//  Role: Task 16 step 4 against exSpy 0.3.2 / HyperSpy 2.4.0 (Fixtures/eels16-pins.json): `optimal_fft_size`, `estimate_peak_width`, Fourier-log
//        and Fourier-ratio deconvolution. Upstream has no tolerance for the deconvolutions (`test_running` only runs), so the kit's decision
//        stands (docs/design/eels-task-16.md section 4): per pixel rtol 1e-7 + atol 1e-7 x max|pinned result|; sizes and channel counts exact.
//

import Foundation
import Testing
import SpectroTestSupport
import SpectroEELS

struct DeconvolutionPinsTests {

    /// rtol 1e-7 + atol 1e-7 x max|pinned| per pixel row of `channels` values; the worst ratio of error to allowance is returned.
    private func worstRatio(_ got: [Double], _ want: [Double], channels: Int) -> Double {
        guard got.count == want.count else { return .infinity }
        var worst = 0.0
        for row in 0 ..< want.count / channels {
            let range = row * channels ..< (row + 1) * channels
            let top = want[range].map { abs($0) }.max() ?? 0
            for i in range {
                let allowed = 1e-7 * abs(want[i]) + 1e-7 * top
                let error = abs(got[i] - want[i])
                worst = max(worst, allowed > 0 ? error / allowed : (error == 0 ? 0 : .infinity))
            }
        }
        return worst
    }

    @Test func testOptimalFFTSizeEqualsScipy() {
        let d = Eels16.dict("optimalFFTSize")
        let ns = d["ns"] as! [Int], real = d["real"] as! [Int], complex = d["complex"] as! [Int]
        #expect(ns.count == real.count && ns.count == complex.count && ns.count > 200)
        for (i, n) in ns.enumerated() {
            #expect(EELSDeconvolution.optimalFFTSize(n, real: true) == real[i], Comment(rawValue: "real \(n)"))
            #expect(EELSDeconvolution.optimalFFTSize(n, real: false) == complex[i], Comment(rawValue: "complex \(n)"))
        }
    }

    @Test func testPeakWidthEqualsExSpy() throws {
        let p = Eels16.dict("fourierRatio", "plural")
        let low = Eels16.array(p["lowLossFile"] as! String), n = p["channels"] as! Int
        let want = Eels16.flat(Eels16.dict("fourierRatio")["fwhmAllPixelsEV"])
        for px in 0 ..< want.count {
            let w = try #require(try EELSDeconvolution.peakWidth(Array(low[px * n ..< (px + 1) * n]), offsetEV: Eels16.number(p["offsetEV"]),
                                                                 scaleEV: Eels16.number(p["scaleEV"])), Comment(rawValue: "pixel \(px)"))
            #expect(abs(w.widthEV - want[px]) <= 1e-9, Comment(rawValue: "pixel \(px): \(w.widthEV) vs \(want[px])"))
        }
        // Noise makes more than two half-maximum crossings: no width (exSpy NaN).
        var noisy = Array(low[0 ..< n])
        for i in stride(from: 700, to: 800, by: 2) { noisy[i] += 0.8 * noisy.max()! }
        #expect(try EELSDeconvolution.peakWidth(noisy, offsetEV: -20, scaleEV: 0.1) == nil)
    }

    @Test func testFourierLogEqualsExSpy() throws {
        let fl = Eels16.dict("fourierLog")
        let p = fl["plural"] as! [String: Any]
        let n = p["channels"] as! Int
        func image(_ file: String) throws -> LowLossSpectrumImage {
            try LowLossSpectrumImage(nx: p["nx"] as! Int, ny: p["ny"] as! Int, channels: n, counts: Eels16.array(file),
                                     energyOffsetEV: Eels16.number(p["offsetEV"]), energyScaleEV: Eels16.number(p["scaleEV"]))
        }
        let ll = try image(p["lowLossFile"] as! String), zlp = try image(p["zlpFile"] as! String)
        for (name, any) in fl["cases"] as! [String: Any] {
            let c = any as! [String: Any], kw = c["kwargs"] as! [String: Any]
            let out = try EELSDeconvolution.fourierLog(ll, zeroLoss: zlp, options: FourierLogOptions(
                addZeroLoss: kw["add_zlp"] as? Bool ?? false, crop: kw["crop"] as? Bool ?? false))
            #expect(out.fftSize == c["fftSize"] as! Int && out.taperedChannels == c["taperedChannels"] as! Int, Comment(rawValue: name))
            #expect(out.image.channels == c["channels"] as! Int && out.image.energyOffsetEV == Eels16.number(c["offsetEV"]), Comment(rawValue: name))
            #expect(out.unavailable.allSatisfy { $0 == nil }, Comment(rawValue: name))
            let ratio = worstRatio(out.image.counts, Eels16.array(c["file"] as! String), channels: out.image.channels)
            print("fourier-log \(name): worst error / allowance \(ratio)")
            #expect(ratio <= 1, Comment(rawValue: "\(name): \(ratio)"))
        }
    }

    @Test func testFourierRatioEqualsExSpy() throws {
        let fr = Eels16.dict("fourierRatio")
        let p = fr["plural"] as! [String: Any], core = fr["core"] as! [String: Any]
        let ll = try LowLossSpectrumImage(nx: p["nx"] as! Int, ny: p["ny"] as! Int, channels: p["channels"] as! Int,
                                          counts: Eels16.array(p["lowLossFile"] as! String),
                                          energyOffsetEV: Eels16.number(p["offsetEV"]), energyScaleEV: Eels16.number(p["scaleEV"]))
        let cl = try CoreLossSpectrumImage(nx: p["nx"] as! Int, ny: p["ny"] as! Int, channels: core["channels"] as! Int,
                                           counts: Eels16.array(core["file"] as! String),
                                           energyOffsetEV: Eels16.number(core["offsetEV"]), energyScaleEV: Eels16.number(core["scaleEV"]))
        for (name, any) in fr["cases"] as! [String: Any] {
            let c = any as! [String: Any], kw = c["kwargs"] as! [String: Any]
            var options = FourierRatioOptions()
            options.fwhmEV = kw["fwhm"] as? Double
            if let t = kw["threshold"] as? Double { options.threshold = .fixed(t) }
            options.extrapolateLowLoss = kw["extrapolate_lowloss"] as? Bool ?? true
            options.extrapolateCoreLoss = kw["extrapolate_coreloss"] as? Bool ?? true
            let out = try EELSDeconvolution.fourierRatio(coreLoss: cl, lowLoss: ll, options: options)
            #expect(out.taperedChannels == c["taperedChannelsLowLoss"] as! Int && out.fftSize == c["fftSize"] as! Int, Comment(rawValue: name))
            #expect(out.image.channels == c["channels"] as! Int && out.image.energyOffsetEV == Eels16.number(c["offsetEV"]), Comment(rawValue: name))
            #expect(abs((out.fwhmEV ?? .nan) - Eels16.number(c["fwhmEV"])) <= 1e-9, Comment(rawValue: "\(name) fwhm \(out.fwhmEV ?? .nan)"))
            #expect(out.unavailable.allSatisfy { $0 == nil }, Comment(rawValue: name))
            let ratio = worstRatio(out.image.counts, Eels16.array(c["file"] as! String), channels: out.image.channels)
            print("fourier-ratio \(name): fft \(out.fftSize) (pin \(c["fftSize"]!)), worst error / allowance \(ratio)")
            #expect(ratio <= 1, Comment(rawValue: "\(name): \(ratio)"))
        }
    }
}
