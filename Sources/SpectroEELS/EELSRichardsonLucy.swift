//
//  EELSRichardsonLucy.swift
//  Role: exSpy's `EELSSpectrum.richardson_lucy_deconvolution` (`exspy/signals/eels.py:1099-1160` at 0.3.2) with a known point-spread
//        function, one spectrum or a whole spectrum image, per pixel on all cores (`EELSParallel`). CPU float64 only.
//
//  The arithmetic is exSpy's, line for line. With `imax = argmax(psf)` (the FIRST maximum), `mimax = N - 1 - imax`, and `result = signal`:
//      repeat `iterations` times:
//          first  = np.convolve(psf, result)[imax : imax + N]
//          result *= np.convolve(psf[::-1], signal / first)[mimax : mimax + N]
//  Both slices are of the full (length 2 N - 1) convolution, not numpy's "same" mode; the result has the spectrum's own axis (exSpy does not
//  touch it) and no trimming. A slice `[imax : imax + N]` of a convolution is one dot product per output channel, taken here directly (numpy
//  also convolves directly), on Accelerate's `vDSP_dotprD`: no FFT, so no circular wrap and no difference in the tails.
//
//  exSpy sizes the slice by the PSF (`psf_size`) and writes it into the spectrum, so the two must have the same number of channels (any
//  other length raises a broadcast error there); the kit throws `kernelSizeMismatch` up front. A pixel whose iterate leaves the real line
//  (a zero `first` over a zero signal, 0 / 0, or x / 0) is NaN in exSpy; here it is all zeros with its reason in `unavailable` (the kit's
//  rule: no answer, never NaN).
//

import Accelerate
import Foundation
import SpectroCore

/// `richardson_lucy_deconvolution(psf, iterations)`.
public struct RichardsonLucyOptions: Sendable, Equatable {
    /// Number of iterations; exSpy's default is 15. 0 returns the spectrum unchanged. More iterations amplify the noise.
    public var iterations: Int
    public init(iterations: Int = 15) { self.iterations = iterations }
}

extension EELSDeconvolution {

    /// Richardson-Lucy deconvolution of `spectrum` by `psf`, a one-pixel image (its single spectrum is the kernel of every pixel) or one with
    /// the spectrum's own `nx` and `ny` (one kernel per pixel). Both must have the same number of channels. Throws `invalidIterations`
    /// for a negative count, `shapeMismatch` for a PSF image that is neither of those, and `kernelSizeMismatch` for another channel count.
    ///
    /// The image keeps the spectrum's energy axis. `fftSize` and `taperedChannels` of the result are 0 (the convolutions are direct).
    public static func richardsonLucy<I: EELSSpectrumImage>(
        _ spectrum: I, psf: I, options: RichardsonLucyOptions = .init(),
        cancelled: @Sendable () -> Bool = SpectroCancellation.task, progress: (@Sendable (Double) -> Void)? = nil
    ) throws -> DeconvolvedSpectrumImage<I> {
        guard options.iterations >= 0 else { throw EELSDeconvolutionError.invalidIterations(options.iterations) }
        let n = spectrum.channels, pixels = spectrum.pixelCount
        guard psf.channels == n else { throw EELSDeconvolutionError.kernelSizeMismatch(expected: n, got: psf.channels) }
        let shared = psf.pixelCount == 1
        guard shared || (psf.nx == spectrum.nx && psf.ny == spectrum.ny) else {
            throw EELSDeconvolutionError.shapeMismatch(expected: pixels, got: psf.pixelCount)
        }
        let iterations = options.iterations
        var out = [Double](repeating: 0, count: pixels * n)
        let why = EELSSlots<EELSUnavailable?>(count: pixels, initial: nil)
        let kernels = psf.counts
        let signal = spectrum.counts
        try out.withUnsafeMutableBufferPointer { dst in
            nonisolated(unsafe) let target = dst
            try signal.withUnsafeBufferPointer { src in
                try kernels.withUnsafeBufferPointer { ker in
                    nonisolated(unsafe) let input = src, kernel = ker
                    try EELSParallel.forEachPixel(count: pixels, chunk: 16, cancelled: cancelled, progress: progress) { p in
                        let k = kernel.baseAddress! + (shared ? 0 : p * n)
                        let row = target.baseAddress! + p * n
                        let s = input.baseAddress! + p * n
                        let reason = iterate(signal: s, kernel: k, count: n, iterations: iterations, into: row)
                        if let reason {
                            for c in 0 ..< n { row[c] = 0 }
                            why.set(p, reason)
                        }
                    }
                }
            }
        }
        let image = try I(nx: spectrum.nx, ny: spectrum.ny, channels: n, counts: out,
                          energyOffsetEV: spectrum.energyOffsetEV, energyScaleEV: spectrum.energyScaleEV)
        return DeconvolvedSpectrumImage(image: image, unavailable: why.values, fftSize: 0, fwhmEV: nil, taperedChannels: 0,
                                        methodName: "Richardson-Lucy deconvolution, \(iterations) iterations")
    }

    /// One spectrum: exSpy's `deconv_function`. Writes `count` channels into `row`; returns nil, or why the result is not finite.
    private static func iterate(signal: UnsafePointer<Double>, kernel: UnsafePointer<Double>, count n: Int, iterations: Int,
                                into row: UnsafeMutablePointer<Double>) -> EELSUnavailable? {
        // imax: numpy's argmax, the first maximum (a NaN cannot occur: the images hold finite counts).
        var imax = 0
        for i in 1 ..< max(n, 1) where kernel[i] > kernel[imax] { imax = i }
        let mimax = n - 1 - imax
        for c in 0 ..< n { row[c] = signal[c] }
        guard iterations > 0, n > 0 else { return nil }
        var first = [Double](repeating: 0, count: n), ratio = first, update = first
        var sawZeroDenominator = false
        for _ in 0 ..< iterations {
            // first[c] = sum_j result[j] kernel[imax + c - j], j in [max(0, c - mimax), min(n - 1, c + imax)]
            for c in 0 ..< n {
                let j0 = max(0, c - mimax), j1 = min(n - 1, c + imax)
                var dot = 0.0
                // the kernel index imax + c - j falls as j rises: a negative stride from its first element
                vDSP_dotprD(row + j0, 1, kernel + (imax + c - j0), -1, &dot, vDSP_Length(j1 - j0 + 1))
                first[c] = dot
            }
            for c in 0 ..< n {
                if first[c] == 0 { sawZeroDenominator = true }
                ratio[c] = signal[c] / first[c]
            }
            // update[c] = sum_j ratio[j] kernel[imax - c + j], j in [max(0, c - imax), min(n - 1, c + mimax)] (np.convolve(psf[::-1], ratio))
            for c in 0 ..< n {
                let j0 = max(0, c - imax), j1 = min(n - 1, c + mimax)
                var dot = 0.0
                ratio.withUnsafeBufferPointer { r in
                    vDSP_dotprD(r.baseAddress! + j0, 1, kernel + (imax - c + j0), 1, &dot, vDSP_Length(j1 - j0 + 1))
                }
                update[c] = dot
            }
            var finite = true
            for c in 0 ..< n { row[c] *= update[c]; if !row[c].isFinite { finite = false } }
            if !finite { return sawZeroDenominator ? .divisionByZero : .nonFiniteResult }
        }
        return nil
    }
}
