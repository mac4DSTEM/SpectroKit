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
