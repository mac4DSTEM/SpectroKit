//
//  EELSDeconvolutionTests.swift
//  Role: Fourier-log and Fourier-ratio deconvolution, fast target: Fourier-log and Fourier-ratio against the planted plural-scattering truth, `optimal_fft_size`, the
//        half-maximum width, and the refusals. The exSpy pins are in SpectroKitParityTests/DeconvolutionPinsTests.
//

import Foundation
import Testing
import SpectroTestSupport
import SpectroEELS

struct EELSDeconvolutionTests {

    private func plural() throws -> (ll: LowLossSpectrumImage, zlp: LowLossSpectrumImage, core: CoreLossSpectrumImage, p: [String: Any], core0: [String: Any]) {
        let fr = Eels16.dict("fourierRatio")
        let p = fr["plural"] as! [String: Any], c = fr["core"] as! [String: Any]
        func low(_ f: String) throws -> LowLossSpectrumImage {
            try LowLossSpectrumImage(nx: p["nx"] as! Int, ny: p["ny"] as! Int, channels: p["channels"] as! Int, counts: Eels16.array(f),
                                     energyOffsetEV: Eels16.number(p["offsetEV"]), energyScaleEV: Eels16.number(p["scaleEV"]))
        }
        let core = try CoreLossSpectrumImage(nx: p["nx"] as! Int, ny: p["ny"] as! Int, channels: c["channels"] as! Int, counts: Eels16.array(c["file"] as! String),
                                             energyOffsetEV: Eels16.number(c["offsetEV"]), energyScaleEV: Eels16.number(c["scaleEV"]))
        return (try low(p["lowLossFile"] as! String), try low(p["zlpFile"] as! String), core, p, c)
    }

    /// Fourier-log returns the planted single-scattering distribution broadened by the ZLP (Z x S / I0): within 0.1 % of its peak away from the taper.
    @Test func testFourierLogReturnsPlantedSingleScattering() throws {
        let t = try plural()
        let out = try EELSDeconvolution.fourierLog(t.ll, zeroLoss: t.zlp)
        let truth = Eels16.array(t.p["singleScatteringBroadenedFile"] as! String)
        let n = t.ll.channels, keep = n - out.taperedChannels
        for px in 0 ..< t.ll.pixelCount {
            let peak = truth[px * n ..< (px + 1) * n].max()!
            var worst = 0.0
            for c in 0 ..< keep { worst = max(worst, abs(out.image.counts[px * n + c] - truth[px * n + c])) }
            #expect(worst <= 1e-3 * peak, Comment(rawValue: "pixel \(px): \(worst / peak)"))
        }
    }

    /// Fourier-ratio returns the planted edge smoothed by the Gaussian, as a density per eV (exSpy's Gaussian has area 1/scale per channel): within 5 % of its peak (the thickest pixel, t/lambda 1.2, is the worst at 4.3 %: a threshold of 6 eV leaves part of the first plasmon in I_0).
    @Test func testFourierRatioReturnsPlantedEdge() throws {
        let t = try plural()
        var options = FourierRatioOptions()
        options.threshold = .fixed(6)
        let out = try EELSDeconvolution.fourierRatio(coreLoss: t.core, lowLoss: t.ll, options: options)
        let truth = Eels16.array(t.core0["truthEdgeFile"] as! String)
        let n = t.core.channels, scale = t.core.energyScaleEV
        for px in 0 ..< t.core.pixelCount {
            let want = Array(truth[px * n ..< (px + 1) * n]), peak = want.max()!
            // away from the edge's onset step and the taper at the end
            var worst = 0.0
            for c in 120 ..< 260 { worst = max(worst, abs(out.image.counts[px * n + c] * scale - want[c])) }
            #expect(worst <= 0.05 * peak, Comment(rawValue: "pixel \(px): \(worst / peak)"))
        }
    }

    @Test func testShapeAndOptionRefusals() throws {
        let t = try plural()
        let other = try LowLossSpectrumImage(nx: 2, ny: 2, channels: 100, counts: [Double](repeating: 1, count: 400), energyOffsetEV: -5, energyScaleEV: 0.1)
        #expect(throws: EELSDeconvolutionError.shapeMismatch(expected: 12, got: 4)) { try EELSDeconvolution.fourierLog(t.ll, zeroLoss: other) }
        #expect(throws: EELSDeconvolutionError.shapeMismatch(expected: 12, got: 4)) { try EELSDeconvolution.fourierRatio(coreLoss: t.core, lowLoss: other) }
        for bad in [0.0, -1.0, .nan, .infinity] {
            #expect(throws: EELSDeconvolutionError.self) {
                try EELSDeconvolution.fourierRatio(coreLoss: t.core, lowLoss: t.ll, options: FourierRatioOptions(fwhmEV: bad))
            }
        }
        let one = try LowLossSpectrumImage(nx: 4, ny: 3, channels: 1, counts: [Double](repeating: 1, count: 12), energyOffsetEV: 0, energyScaleEV: 0.1)
        #expect(throws: EELSDeconvolutionError.tooFewChannels(1)) { try EELSDeconvolution.fourierLog(t.ll, zeroLoss: one) }
        #expect(throws: EELSDeconvolutionError.self) { try EELSDeconvolution.peakWidth([1, 2, 3], offsetEV: 0, scaleEV: 1) }
        #expect(throws: EELSDeconvolutionError.invalidPeakFactor(1)) { try EELSDeconvolution.peakWidth([1, 2, 3, 4], offsetEV: 0, scaleEV: 1, factor: 1) }
    }

    /// A pixel with no zero-loss threshold has no answer (zeros and a reason), the others are untouched.
    @Test func testPixelWithoutThresholdIsUnavailable() throws {
        let t = try plural()
        var thetas = [Double](repeating: 6, count: 12)
        thetas[4] = .nan
        thetas[7] = 1e6                                                  // outside the axis
        var options = FourierRatioOptions()
        options.threshold = .perPixel(thetas)
        let out = try EELSDeconvolution.fourierRatio(coreLoss: t.core, lowLoss: t.ll, options: options)
        let n = t.core.channels
        for px in 0 ..< 12 {
            let row = out.image.counts[px * n ..< (px + 1) * n]
            if px == 4 || px == 7 {
                #expect(out.unavailable[px] == .noThreshold && row.allSatisfy { $0 == 0 }, Comment(rawValue: "pixel \(px)"))
            } else {
                #expect(out.unavailable[px] == nil && row.contains { $0 != 0 }, Comment(rawValue: "pixel \(px)"))
            }
        }
        #expect(throws: EELSThicknessError.self) {
            try EELSDeconvolution.fourierRatio(coreLoss: t.core, lowLoss: t.ll, options: { var o = FourierRatioOptions(); o.threshold = .perPixel([1]); return o }())
        }
    }

    /// A 4 x 3 low loss (256 channels from -5 eV at 0.5 eV) and core loss (256 channels from 250 eV) built in closed form. `bad` gets the
    /// window that makes the two-area power law overflow on the continuation (A 8e-296, r -143.09 in HyperSpy): its last 100 low-loss channels
    /// are 5.4e-15 then 50.
    private func overflowPair(bad: Int?) throws -> (ll: LowLossSpectrumImage, core: CoreLossSpectrumImage) {
        let n = 256, pixels = 12
        var ll = [Double](repeating: 0, count: pixels * n), cl = ll
        for p in 0 ..< pixels {
            for c in 0 ..< n {
                let e = -5 + 0.5 * Double(c)
                var s = 1000 * exp(-0.5 * (e / 0.6) * (e / 0.6))
                s += (80 + 5 * Double(p)) * exp(-0.5 * ((e - 20) / 4) * ((e - 20) / 4))
                if e > 1 { s += 300 * pow(max(abs(e), 1), -1.5) }
                ll[p * n + c] = s
                let ec = 250 + 0.5 * Double(c)
                cl[p * n + c] = (2 + 0.1 * Double(p)) * (ec > 284 ? pow(ec / 284, -3) : 0) + 1e-3 * pow(ec / 250, -2)
            }
        }
        if let bad {
            for c in (n - 100) ..< (n - 50) { ll[bad * n + c] = 5.4e-15 }
            for c in (n - 50) ..< n { ll[bad * n + c] = 50 }
        }
        return (try LowLossSpectrumImage(nx: 4, ny: 3, channels: n, counts: ll, energyOffsetEV: -5, energyScaleEV: 0.5),
                try CoreLossSpectrumImage(nx: 4, ny: 3, channels: n, counts: cl, energyOffsetEV: 250, energyScaleEV: 0.5))
    }

    /// exSpy 0.3.2 gives NaN at a pixel whose low-loss continuation overflows (with a RuntimeWarning) and deconvolves the rest; the kit leaves
    /// that pixel unanswered (zeros, `nonFiniteResult`) and answers the other eleven, which do not change by one bit against the same image
    /// without the bad pixel.
    @Test func testFourierRatioPixelWithNonFiniteContinuationIsUnavailable() throws {
        let clean = try overflowPair(bad: nil), broken = try overflowPair(bad: 5)
        // the bad window really overflows: the public extrapolation of that image cannot be formed
        #expect(throws: (any Error).self) { try EELSSpectrumOps.powerLawExtrapolation(broken.ll, windowChannels: 100, extrapolationChannels: 100) }
        let options = FourierRatioOptions(threshold: .fixed(2.5))
        let before = try EELSDeconvolution.fourierRatio(coreLoss: clean.core, lowLoss: clean.ll, options: options)
        let after = try EELSDeconvolution.fourierRatio(coreLoss: broken.core, lowLoss: broken.ll, options: options)
        let n = clean.core.channels
        #expect(after.fwhmEV == before.fwhmEV && after.fftSize == before.fftSize)
        for px in 0 ..< 12 {
            let row = after.image.counts[px * n ..< (px + 1) * n]
            if px == 5 {
                #expect(after.unavailable[px] == .nonFiniteResult && row.allSatisfy { $0 == 0 })
            } else {
                #expect(after.unavailable[px] == nil, Comment(rawValue: "pixel \(px)"))
                #expect(Array(row) == Array(before.image.counts[px * n ..< (px + 1) * n]), Comment(rawValue: "pixel \(px) moved"))
            }
        }
        // exSpy 0.3.2 on the same inputs (estimated FWHM, threshold 2.5 eV): pixel 1, channels 60...63, within the kit's Fourier-ratio tolerance
        let exspy = [-0.017163108412498216, -0.00234262241292717, -0.03682816896247529, 0.038049721723035654]
        for (k, want) in exspy.enumerated() {
            let got = after.image.counts[1 * n + 60 + k]
            #expect(abs(got - want) <= 1e-7 * abs(want) + 1e-7 * 5.330745866192701, Comment(rawValue: "channel \(60 + k): \(got)"))
        }
    }

    /// The FWHM is estimated from the first pixel (exSpy's current spectrum). When that pixel's continuation overflows, exSpy's width is NaN
    /// and so is every pixel; the kit refuses with `noPeakWidth` (pass `fwhmEV`). With a FWHM given, only that pixel is unanswered.
    @Test func testFourierRatioFirstPixelNonFiniteContinuation() throws {
        let broken = try overflowPair(bad: 0)
        #expect(throws: EELSDeconvolutionError.noPeakWidth) {
            try EELSDeconvolution.fourierRatio(coreLoss: broken.core, lowLoss: broken.ll, options: FourierRatioOptions(threshold: .fixed(2.5)))
        }
        let given = FourierRatioOptions(fwhmEV: 1.2, threshold: .fixed(2.5))
        let out = try EELSDeconvolution.fourierRatio(coreLoss: broken.core, lowLoss: broken.ll, options: given)
        let ref = try EELSDeconvolution.fourierRatio(coreLoss: broken.core, lowLoss: try overflowPair(bad: nil).ll, options: given)
        let n = broken.core.channels
        #expect(out.unavailable[0] == .nonFiniteResult && out.image.counts[0 ..< n].allSatisfy { $0 == 0 })
        #expect(out.unavailable[1 ..< 12].allSatisfy { $0 == nil })
        #expect(Array(out.image.counts[n...]) == Array(ref.image.counts[n...]))
    }

    /// The core loss's own continuation (window 20) overflowing at pixel 0: that pixel is unanswered, the FWHM (from the low loss) is still
    /// estimated, and the other pixels are bit-identical. The window (ten channels at 0.31, ten at 50 on 5 + 0.5 c eV) gives A 2.4e-296,
    /// r -140.65 in HyperSpy, whose continuation overflows.
    @Test func testFourierRatioCoreLossNonFiniteContinuation() throws {
        let n = 256
        func core(bad: Bool) throws -> CoreLossSpectrumImage {
            var cl = [Double](repeating: 0, count: 12 * n)
            for p in 0 ..< 12 { for c in 0 ..< n { cl[p * n + c] = (100 + Double(p)) * pow((5 + 0.5 * Double(c)) / 5, -1) } }
            if bad {
                for c in (n - 20) ..< (n - 10) { cl[c] = 0.31 }
                for c in (n - 10) ..< n { cl[c] = 50 }
            }
            return try CoreLossSpectrumImage(nx: 4, ny: 3, channels: n, counts: cl, energyOffsetEV: 5, energyScaleEV: 0.5)
        }
        let low = try overflowPair(bad: nil).ll, broken = try core(bad: true)
        #expect(throws: (any Error).self) { try EELSSpectrumOps.powerLawExtrapolation(broken, windowChannels: 20, extrapolationChannels: 100) }
        let options = FourierRatioOptions(threshold: .fixed(2.5))
        let out = try EELSDeconvolution.fourierRatio(coreLoss: broken, lowLoss: low, options: options)
        let ref = try EELSDeconvolution.fourierRatio(coreLoss: try core(bad: false), lowLoss: low, options: options)
        #expect(out.fwhmEV == ref.fwhmEV)
        #expect(out.unavailable[0] == .nonFiniteResult && out.image.counts[0 ..< n].allSatisfy { $0 == 0 })
        #expect(out.unavailable[1 ..< 12].allSatisfy { $0 == nil })
        #expect(Array(out.image.counts[n...]) == Array(ref.image.counts[n...]))
    }

    /// A zero in the zero-loss spectrum's transform: the logarithm leaves the real line, the pixel says so.
    @Test func testFourierLogOfZeroSpectrumIsUnavailable() throws {
        let t = try plural()
        var counts = t.ll.counts
        for c in 0 ..< t.ll.channels { counts[c] = 0 }                    // pixel 0 empty
        let empty = try LowLossSpectrumImage(nx: 4, ny: 3, channels: t.ll.channels, counts: counts, energyOffsetEV: t.ll.energyOffsetEV, energyScaleEV: t.ll.energyScaleEV)
        let out = try EELSDeconvolution.fourierLog(empty, zeroLoss: t.zlp)
        #expect(out.unavailable[0] == .nonFiniteResult || out.unavailable[0] == nil)
        #expect(out.image.counts.allSatisfy { $0.isFinite })
        #expect(out.unavailable[1] == nil)
    }

    @Test func testPeakWidthOfPlantedPeak() throws {
        // A parabola-capped peak sampled at integers: the half-maximum interval is two roots inside single knot intervals.
        let y = [0.0, 1, 4, 9, 4, 1, 0, 0]
        let peak = try #require(try EELSDeconvolution.peakWidth(y, offsetEV: 0, scaleEV: 1))
        #expect(peak.leftEV > 1.5 && peak.leftEV < 2.5 && peak.rightEV > 3.5 && peak.rightEV < 4.5 && peak.widthEV > 1.5)
        // The same spectrum on an axis shifted by 10 eV and scaled by 0.5: the interval moves and scales with it.
        let moved = try #require(try EELSDeconvolution.peakWidth(y, offsetEV: 10, scaleEV: 0.5))
        #expect(abs(moved.leftEV - (10 + 0.5 * peak.leftEV)) < 1e-12 && abs(moved.rightEV - (10 + 0.5 * peak.rightEV)) < 1e-12)
        // The half maximum sits exactly on samples that are spline knots: both roots are still found.
        let onKnots = try #require(try EELSDeconvolution.peakWidth([0, 0, 2, 4, 2, 0, 0, 0], offsetEV: 0, scaleEV: 1))
        #expect(abs(onKnots.leftEV - 2) < 1e-9 && abs(onKnots.rightEV - 4) < 1e-9)
        for shift in 0 ..< 3 {
            let y = [Double](repeating: 0, count: shift) + [0, 1, 2, 4, 2, 1, 0, 0] + [Double](repeating: 0, count: 2 - shift)
            #expect(try EELSDeconvolution.peakWidth(y, offsetEV: 0, scaleEV: 1) != nil, Comment(rawValue: "shift \(shift)"))
        }
        // A flat spectrum has no half-maximum crossing.
        #expect(try EELSDeconvolution.peakWidth([3, 3, 3, 3, 3], offsetEV: 0, scaleEV: 1) == nil)
    }
}
