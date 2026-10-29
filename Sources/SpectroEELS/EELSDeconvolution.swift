//
//  EELSDeconvolution.swift
//  Role: exSpy's Fourier-log and Fourier-ratio deconvolution (docs/design/eels-chain.md section 4; `_eels.py:870-1097` at 7185a4d1) on
//        ImagoCore's exact-length FFT, and HyperSpy's `estimate_peak_width` (`signal1d.py:1612-1725`) that the ratio method uses for its
//        Gaussian. CPU float64 only.
//
//  Quirks kept, because the pins show them: `irfft` returns 2 (m - 1) channels (one fewer than the FFT size when that is odd, as the
//  ratio method's complex `next_fast_len` can give); the ratio method's FFT size comes from the ORIGINAL core-loss length while the
//  FFT input is the extrapolated one (a longer input is truncated); `nan_to_num` turns an infinite logarithm into +-1.797e308.
//

import Foundation
import ImagoCore
import SpectroCore

/// `fourier_log_deconvolution(zlp, add_zlp, crop)`.
public struct FourierLogOptions: Sendable, Equatable {
    /// Add the zero-loss peak back to the deconvolved spectrum (its first channels).
    public var addZeroLoss = false
    /// Leave out the channels the Hanning taper modified at the end (`taperedChannels` of them).
    public var crop = false
    public init(addZeroLoss: Bool = false, crop: Bool = false) { self.addZeroLoss = addZeroLoss; self.crop = crop }
}

/// `fourier_ratio_deconvolution(low_loss, fwhm, threshold, extrapolate_lowloss, extrapolate_coreloss)`.
public struct FourierRatioOptions: Sendable, Equatable {
    /// The Gaussian's FWHM, eV. nil: `estimate_peak_width` of the first pixel of the extrapolated, tapered low loss (exSpy's "current" spectrum).
    public var fwhmEV: Double? = nil
    /// How I_0 is cut from the low loss. exSpy's default is `estimate_elastic_scattering_threshold()` on the original low loss.
    public var threshold: ThresholdRule = .estimated()
    /// Power-law continuation by 100 channels of the low loss (window 100) and the core loss (window 20), as exSpy.
    public var extrapolateLowLoss = true
    public var extrapolateCoreLoss = true
    public init(fwhmEV: Double? = nil, threshold: ThresholdRule = .estimated(), extrapolateLowLoss: Bool = true, extrapolateCoreLoss: Bool = true) {
        self.fwhmEV = fwhmEV; self.threshold = threshold
        self.extrapolateLowLoss = extrapolateLowLoss; self.extrapolateCoreLoss = extrapolateCoreLoss
    }
}

/// A deconvolved spectrum image. A pixel whose result is not finite is all zeros in `image` and has its reason in `unavailable`.
public struct DeconvolvedSpectrumImage<I: EELSSpectrumImage>: Sendable {
    public let image: I
    public let unavailable: [EELSUnavailable?]
    /// The transform length exSpy's `optimal_fft_size` chose.
    public let fftSize: Int
    /// The Gaussian's FWHM (Fourier ratio), eV.
    public let fwhmEV: Double?
    /// The channels the Hanning taper modified at each end (of the spectrum that was deconvolved).
    public let taperedChannels: Int
    public let methodName: String
}

/// A half-maximum interval (`estimate_peak_width`).
public struct PeakWidth: Sendable, Equatable {
    public let leftEV: Double
    public let rightEV: Double
    public var widthEV: Double { rightEV - leftEV }
}

public enum EELSDeconvolution {

    /// `scipy.fft.next_fast_len(n, real)`: the smallest 2,3,5-smooth (real) or 2,3,5,7,11-smooth (complex) integer >= n.
    public static func optimalFFTSize(_ n: Int, real: Bool) -> Int {
        let primes: [Int] = real ? [2, 3, 5] : [2, 3, 5, 7, 11]
        var m = max(n, 1)
        while true {
            var r = m
            for p in primes { while r % p == 0 { r /= p } }
            if r == 1 { return m }
            m += 1
        }
    }

    /// `estimate_peak_width(factor)` of one spectrum on `offsetEV + scaleEV * i`: the two roots of the cubic interpolating spline of
    /// `y - factor max(y)`, or nil unless there are exactly two (exSpy: NaN). The spectrum needs at least 4 channels.
    public static func peakWidth(_ y: [Double], offsetEV: Double, scaleEV: Double, factor: Double = 0.5) throws -> PeakWidth? {
        guard factor > 0, factor < 1 else { throw EELSDeconvolutionError.invalidPeakFactor(factor) }
        guard y.count >= 4 else { throw EELSDeconvolutionError.tooFewChannels(y.count) }
        let axis = try EELSAxis(offset: offsetEV, scale: scaleEV, size: y.count)
        guard let top = y.max(), top.isFinite else { return nil }
        let x = (0..<y.count).map { axis.energy(ofChannel: $0) }
        guard let spline = InterpolatingSpline(x: x, y: y.map { $0 - factor * top }) else { return nil }
        let roots = spline.roots()
        return roots.count == 2 ? PeakWidth(leftEV: roots[0], rightEV: roots[1]) : nil
    }

    // MARK: Fourier-log

    public static func fourierLog(
        _ spectrum: LowLossSpectrumImage, zeroLoss: LowLossSpectrumImage, options: FourierLogOptions = .init(),
        cancelled: @Sendable () -> Bool = SpectroCancellation.task, progress: (@Sendable (Double) -> Void)? = nil
    ) throws -> DeconvolvedSpectrumImage<LowLossSpectrumImage> {
        guard zeroLoss.nx == spectrum.nx, zeroLoss.ny == spectrum.ny else {
            throw EELSDeconvolutionError.shapeMismatch(expected: spectrum.pixelCount, got: zeroLoss.pixelCount)
        }
        let n = spectrum.channels, zn = zeroLoss.channels
        guard zn >= 2 else { throw EELSDeconvolutionError.tooFewChannels(zn) }
        let (tapered, taper) = try EELSSpectrumOps.hanningTaper(spectrum)
        let size = optimalFFTSize(zn + n - 1, real: true)
        let bins = size / 2 + 1, outLength = 2 * (bins - 1)
        guard let forward = FFT2DDouble(nx: size, ny: 1) else { throw EELSDeconvolutionError.fftSetup(size: size) }
        guard let inverse = outLength == size ? forward : FFT2DDouble(nx: outLength, ny: 1) else { throw EELSDeconvolutionError.fftSetup(size: outLength) }
        let pixels = spectrum.pixelCount
        let kept = options.crop ? n - taper : n
        guard kept >= 1 else { throw EELSDeconvolutionError.tooFewChannels(n) }
        var out = [Double](repeating: 0, count: pixels * kept)
        let why = EELSSlots<EELSUnavailable?>(count: pixels, initial: nil)
        let source = tapered.counts, zlp = zeroLoss.counts
        try out.withUnsafeMutableBufferPointer { dst in
            nonisolated(unsafe) let target = dst
            try source.withUnsafeBufferPointer { src in
                try zlp.withUnsafeBufferPointer { zsrc in
                    nonisolated(unsafe) let input = src, zinput = zsrc
                    try EELSParallel.forEachPixel(count: pixels, cancelled: cancelled, progress: progress) { p in
                        let z = realFFT(zinput.baseAddress! + p * zn, count: zn, size: size, plan: forward)
                        let j = realFFT(input.baseAddress! + p * n, count: n, size: size, plan: forward)
                        var re = [Double](repeating: 0, count: bins), im = re
                        for k in 0 ..< bins {
                            let q = complexDivide(j.re[k], j.im[k], z.re[k], z.im[k])
                            let lr = nanToNum(log(hypot(q.re, q.im))), li = nanToNum(atan2(q.im, q.re))
                            re[k] = z.re[k] * lr - z.im[k] * li
                            im[k] = z.re[k] * li + z.im[k] * lr
                        }
                        var s = inverseRealFFT(re: re, im: im, plan: inverse, length: outLength)
                        if options.addZeroLoss {
                            let zrow = zinput.baseAddress! + p * zn
                            for c in 0 ..< min(n, zn) { s[c] += zrow[c] }
                        }
                        let row = target.baseAddress! + p * kept
                        var finite = true
                        for c in 0 ..< kept { row[c] = s[c]; if !s[c].isFinite { finite = false } }
                        if !finite {
                            for c in 0 ..< kept { row[c] = 0 }
                            why.set(p, .nonFiniteResult)
                        }
                    }
                }
            }
        }
        let image = try LowLossSpectrumImage(nx: spectrum.nx, ny: spectrum.ny, channels: kept, counts: out,
                                              energyOffsetEV: spectrum.energyOffsetEV, energyScaleEV: spectrum.energyScaleEV)
        return DeconvolvedSpectrumImage(image: image, unavailable: why.values, fftSize: size, fwhmEV: nil, taperedChannels: taper,
                                        methodName: "Fourier-log deconvolution")
    }

    // MARK: Fourier-ratio

    public static func fourierRatio(
        coreLoss: CoreLossSpectrumImage, lowLoss: LowLossSpectrumImage, options: FourierRatioOptions = .init(),
        cancelled: @Sendable () -> Bool = SpectroCancellation.task, progress: (@Sendable (Double) -> Void)? = nil
    ) throws -> DeconvolvedSpectrumImage<CoreLossSpectrumImage> {
        guard lowLoss.nx == coreLoss.nx, lowLoss.ny == coreLoss.ny else {
            throw EELSDeconvolutionError.shapeMismatch(expected: coreLoss.pixelCount, got: lowLoss.pixelCount)
        }
        if let f = options.fwhmEV, !(f.isFinite && f > 0) { throw EELSDeconvolutionError.invalidFWHM(f) }
        let pixels = coreLoss.pixelCount
        let origin = coreLoss.channels

        // I_0 is cut on the ORIGINAL low loss (the threshold search sees neither extrapolation nor taper).
        let originalAxis = try EELSAxis(offset: lowLoss.energyOffsetEV, scale: lowLoss.energyScaleEV, size: lowLoss.channels)
        let stops = try zeroLossStops(options.threshold, lowLoss: lowLoss, axis: originalAxis, cancelled: cancelled,
                                      progress: progress.map { p in { @Sendable f in p(0.2 * f) } })

        let cl: CoreLossSpectrumImage
        if options.extrapolateCoreLoss {
            cl = try EELSSpectrumOps.powerLawExtrapolation(coreLoss, windowChannels: 20, extrapolationChannels: 100, cancelled: cancelled).image
        } else { cl = coreLoss }
        let ll: LowLossSpectrumImage
        if options.extrapolateLowLoss {
            ll = try EELSSpectrumOps.powerLawExtrapolation(lowLoss, windowChannels: 100, extrapolationChannels: 100, cancelled: cancelled).image
        } else { ll = lowLoss }
        let (llT, llTaper) = try EELSSpectrumOps.hanningTaper(ll)
        let (clT, _) = try EELSSpectrumOps.hanningTaper(cl)

        let llChannels = llT.channels, clChannels = clT.channels
        let size = optimalFFTSize(llChannels + origin - 1, real: false)
        let bins = size / 2 + 1, outLength = 2 * (bins - 1)
        guard outLength >= origin else { throw EELSDeconvolutionError.tooFewChannels(origin) }

        let fwhm: Double
        if let f = options.fwhmEV { fwhm = f } else {
            let first = Array(llT.counts[0 ..< llChannels])
            guard let w = try peakWidth(first, offsetEV: llT.energyOffsetEV, scaleEV: llT.energyScaleEV) else {
                throw EELSDeconvolutionError.noPeakWidth
            }
            fwhm = w.widthEV
            guard fwhm.isFinite, fwhm > 0 else { throw EELSDeconvolutionError.invalidFWHM(fwhm) }
        }
        // The Gaussian on np.linspace(offset, offset + scale (size - 1), size): A = 1, centre 0, sigma = fwhm / 2.3548.
        guard let forward = FFT2DDouble(nx: size, ny: 1) else { throw EELSDeconvolutionError.fftSetup(size: size) }
        guard let inverse = outLength == size ? forward : FFT2DDouble(nx: outLength, ny: 1) else { throw EELSDeconvolutionError.fftSetup(size: outLength) }
        let sigma = fwhm / 2.3548
        let start = llT.energyOffsetEV, stop = llT.energyOffsetEV + llT.energyScaleEV * Double(size - 1)
        let step = size > 1 ? (stop - start) / Double(size - 1) : 0
        let sqrt2pi = (2 * Double.pi).squareRoot()
        var gaussian = [Double](repeating: 0, count: size)
        for i in 0 ..< size {
            let x = i == size - 1 && size > 1 ? stop : Double(i) * step + start
            gaussian[i] = 1.0 * (1 / (sigma * sqrt2pi)) * exp(-(x * x) / (2 * sigma * sigma))
        }
        let z = gaussian.withUnsafeBufferPointer { realFFT($0.baseAddress!, count: size, size: size, plan: forward) }

        var out = [Double](repeating: 0, count: pixels * origin)
        let why = EELSSlots<EELSUnavailable?>(count: pixels, initial: nil)
        let clSource = clT.counts, llSource = llT.counts
        try out.withUnsafeMutableBufferPointer { dst in
            nonisolated(unsafe) let target = dst
            try clSource.withUnsafeBufferPointer { csrc in
                try llSource.withUnsafeBufferPointer { lsrc in
                    nonisolated(unsafe) let cinput = csrc, linput = lsrc
                    try EELSParallel.forEachPixel(count: pixels, cancelled: cancelled,
                                                  progress: progress.map { p in { @Sendable f in p(0.2 + 0.8 * f) } }) { p in
                        guard let stopChannel = stops[p], stopChannel <= llChannels else { why.set(p, .noThreshold); return }
                        let i0 = NumpySum.pairwise(linput.baseAddress! + p * llChannels, count: stopChannel)
                        let jk = realFFT(cinput.baseAddress! + p * clChannels, count: clChannels, size: size, plan: forward)
                        let jl = realFFT(linput.baseAddress! + p * llChannels, count: llChannels, size: size, plan: forward)
                        var re = [Double](repeating: 0, count: bins), im = re
                        var zeroDenominator = false
                        for k in 0 ..< bins {
                            let pr = z.re[k] * jk.re[k] - z.im[k] * jk.im[k], pi = z.re[k] * jk.im[k] + z.im[k] * jk.re[k]
                            if jl.re[k] == 0 && jl.im[k] == 0 { zeroDenominator = true }
                            let q = complexDivide(pr, pi, jl.re[k], jl.im[k])
                            re[k] = q.re; im[k] = q.im
                        }
                        let s = inverseRealFFT(re: re, im: im, plan: inverse, length: outLength)
                        let row = target.baseAddress! + p * origin
                        var finite = true
                        for c in 0 ..< origin { row[c] = s[c] * i0; if !row[c].isFinite { finite = false } }
                        if !finite {
                            for c in 0 ..< origin { row[c] = 0 }
                            why.set(p, zeroDenominator ? .divisionByZero : .nonFiniteResult)
                        }
                    }
                }
            }
        }
        let image = try CoreLossSpectrumImage(nx: coreLoss.nx, ny: coreLoss.ny, channels: origin, counts: out,
                                               energyOffsetEV: coreLoss.energyOffsetEV, energyScaleEV: coreLoss.energyScaleEV)
        return DeconvolvedSpectrumImage(image: image, unavailable: why.values, fftSize: size, fwhmEV: fwhm, taperedChannels: llTaper,
                                        methodName: "Fourier-ratio deconvolution")
    }

    // MARK: Helpers

    /// The end (exclusive) of the zero-loss sum per pixel, on `axis` (nil where there is no threshold).
    private static func zeroLossStops(
        _ rule: ThresholdRule, lowLoss: LowLossSpectrumImage, axis: EELSAxis,
        cancelled: @Sendable () -> Bool, progress: (@Sendable (Double) -> Void)?
    ) throws -> [Int?] {
        let np = lowLoss.pixelCount
        switch rule {
        case .fixed(let theta):
            let stop = try axis.zeroLossStop(forFixedThreshold: theta)
            return [Int?](repeating: stop, count: np)
        case .perPixel(let thetas):
            guard thetas.count == np else { throw EELSThicknessError.perPixelThresholdCount(expected: np, got: thetas.count) }
            return thetas.map { $0.isNaN ? nil : axis.channel(ofEnergy: $0) }
        case .estimated(let window, let start, let windowLength, let polynomialOrder, let tolerance):
            let found = try lowLoss.counts.withUnsafeBufferPointer { buf in
                try ElasticThreshold.estimate(
                    counts: buf, pixelCount: np, navigationWidth: lowLoss.nx, channels: lowLoss.channels, axis: axis, window: window, start: start,
                    windowLength: windowLength, polynomialOrder: polynomialOrder, tolerance: tolerance, cancelled: cancelled, progress: progress)
            }
            return found.thresholdEV.map { $0.isNaN ? nil : axis.channel(ofEnergy: $0) }
        }
    }

    /// `np.fft.rfft(x, n=size)`: the first `size/2 + 1` bins; a longer input is cut, a shorter one zero-padded.
    private static func realFFT(_ x: UnsafePointer<Double>, count: Int, size: Int, plan: FFT2DDouble) -> (re: [Double], im: [Double]) {
        var re = [Double](repeating: 0, count: size), im = re
        for c in 0 ..< min(count, size) { re[c] = x[c] }
        plan.transform(re: &re, im: &im, forward: true, scaleInverse: false)
        let bins = size / 2 + 1
        return (Array(re[0 ..< bins]), Array(im[0 ..< bins]))
    }

    /// `np.fft.irfft(a)` with the default length `2 (m - 1)`: the imaginary parts of bin 0 and of the last bin are dropped.
    private static func inverseRealFFT(re: [Double], im: [Double], plan: FFT2DDouble, length n: Int) -> [Double] {
        let m = re.count
        var fr = [Double](repeating: 0, count: n), fi = fr
        for k in 0 ..< m { fr[k] = re[k]; fi[k] = im[k] }
        fi[0] = 0
        if m - 1 < n { fi[m - 1] = 0 }
        if m > 2 { for k in 1 ..< (m - 1) { fr[n - k] = re[k]; fi[n - k] = -im[k] } }
        plan.transform(re: &fr, im: &fi, forward: false, scaleInverse: true)
        return fr
    }

    /// NumPy's complex division (Smith's algorithm, `npy_cdiv`), so a zero denominator gives the same inf / NaN pattern.
    private static func complexDivide(_ ar: Double, _ ai: Double, _ br: Double, _ bi: Double) -> (re: Double, im: Double) {
        let brAbs = abs(br), biAbs = abs(bi)
        if brAbs >= biAbs {
            if brAbs == 0 && biAbs == 0 { return (ar / brAbs, ai / brAbs) }
            let rat = bi / br, scl = 1.0 / (br + bi * rat)
            return ((ar + ai * rat) * scl, (ai - ar * rat) * scl)
        }
        let rat = br / bi, scl = 1.0 / (bi + br * rat)
        return ((ar * rat + ai) * scl, (ai * rat - ar) * scl)
    }

    /// `np.nan_to_num`: NaN to 0, +-inf to the largest finite magnitude.
    private static func nanToNum(_ v: Double) -> Double {
        if v.isNaN { return 0 }
        if v == .infinity { return .greatestFiniteMagnitude }
        if v == -.infinity { return -.greatestFiniteMagnitude }
        return v
    }
}
