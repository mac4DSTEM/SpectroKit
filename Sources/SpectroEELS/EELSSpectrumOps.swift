//
//  EELSSpectrumOps.swift
//  Role: Task 16 step 2 (docs/design/eels-task-16.md section 3): power-law extrapolation to the right and the Hanning taper, ports of exSpy 0.3.2
//        `EELSSpectrum.power_law_extrapolation` (`eels.py:1236-1331`) and HyperSpy 2.4.0 `Signal1D.hanning_taper` (`signal1d.py:1453-1531`),
//        the engines of the Fourier deconvolutions.
//
//  The extrapolation estimates A and r by HyperSpy's two-area method (`PowerLaw.estimate_parameters`, the existing `PowerLawFit`) over the last
//  `windowChannels` channels of each spectrum, adds `A * x^-r` times the channel width (a binned axis) at the new channels. Counts are per channel
//  (a BINNED axis); exSpy's UNBINNED branch (Simpson integral, no channel-width factor) is not offered. `add_noise` (a random draw) is not offered.
//  Departure registered: where a window sum is not positive or A, r are not finite, HyperSpy's `nan_to_num` (or its whole call failing) is replaced
//  by a nil fit and zeros at the new channels, as the rest of the kit does.
//

import Foundation
import SpectroCore

/// The power law `A * E^-r` of one pixel (HyperSpy `PowerLaw`'s A and r).
public nonisolated struct PowerLawParameters: Sendable, Equatable {
    public let a: Double
    public let r: Double
    public init(a: Double, r: Double) { self.a = a; self.r = r }
}

public nonisolated enum TaperSide: Sendable, Equatable { case left, right, both }

public nonisolated enum EELSSpectrumOps {

    // MARK: Power-law extrapolation

    /// exSpy `power_law_extrapolation(window_size, extrapolation_size, fix_neg_r)`: each spectrum is continued by `extrapolationChannels` channels
    /// of `A * x^-r`, with A and r from the two-area estimate over its last `windowChannels` channels. With `fixNegativeR` A is set to 0 where r <= 0
    /// (the continuation is then zero). `fits[p]` is nil where the estimate could not be made (the continuation is zero there).
    public static func powerLawExtrapolation<I: EELSSpectrumImage>(
        _ image: I, windowChannels: Int = 20, extrapolationChannels: Int = 1024, fixNegativeR: Bool = false,
        cancelled: @Sendable () -> Bool = SpectroCancellation.task, progress: (@Sendable (Double) -> Void)? = nil
    ) throws -> (image: I, fits: [PowerLawParameters?]) {
        let n = image.channels
        guard extrapolationChannels >= 1 else { throw EELSDeconvolutionError.extrapolationWindowTooWide(window: windowChannels, channels: n) }
        guard windowChannels >= 3, windowChannels <= n else { throw EELSDeconvolutionError.extrapolationWindowTooWide(window: windowChannels, channels: n) }
        let extended = n + extrapolationChannels
        let axis = try EELSAxis(offset: image.energyOffsetEV, scale: image.energyScaleEV, size: extended)
        // x1 = index2value(size - window), x2 = index2value(size - 1) on the ORIGINAL axis; the window indices come from the extended one.
        let x1 = axis.energy(ofChannel: n - windowChannels), x2 = axis.energy(ofChannel: n - 1)
        let window = try PowerLawWindow(axis: axis, from: x1, to: x2)
        let pixels = image.nx * image.ny
        var counts = [Double](repeating: 0, count: pixels * extended)
        let fits = EELSSlots<PowerLawParameters?>(count: pixels, initial: nil)
        let scale = image.energyScaleEV
        let source = image.counts
        try counts.withUnsafeMutableBufferPointer { dst in
            nonisolated(unsafe) let target = dst
            try source.withUnsafeBufferPointer { src in
                nonisolated(unsafe) let input = src
                try EELSParallel.forEachPixel(count: pixels, cancelled: cancelled, progress: progress) { p in
                    let row = input.baseAddress! + p * n
                    let out = target.baseAddress! + p * extended
                    for c in 0..<n { out[c] = row[c] }
                    guard case .success(let fit) = PowerLawFit.estimate(UnsafeBufferPointer(start: row, count: n), window: window) else { return }
                    fits.set(p, PowerLawParameters(a: fit.a, r: fit.r))
                    let a = fixNegativeR && fit.r <= 0 ? 0.0 : fit.a
                    for c in n..<extended {
                        let x = axis.energy(ofChannel: c)
                        // factor * A * x ** (-r), NumPy's order of operations
                        out[c] = (scale * a) * Libm.pow(x, -fit.r)
                    }
                }
            }
        }
        let result = try I(nx: image.nx, ny: image.ny, channels: extended, counts: counts, energyOffsetEV: image.energyOffsetEV, energyScaleEV: scale)
        return (result, fits.values)
    }

    // MARK: Hanning taper

    /// `np.hanning(m)`, NumPy's own formula: `0.5 + 0.5 cos(pi n / (m - 1))` for `n = 1 - m, 3 - m, ..., m - 1` (not `vDSP_hann_window`, whose
    /// normalisation differs).
    package static func hanning(_ m: Int) -> [Double] {
        if m < 1 { return [] }
        if m == 1 { return [1] }
        return (0..<m).map { k in
            let n = Double(1 - m + 2 * k)
            return 0.5 + 0.5 * cos(Double.pi * n / Double(m - 1))
        }
    }

    /// The default taper width, HyperSpy's `channels is None` rule: `max(20, round(0.02 n))`, Python's round (half to even).
    public static func defaultTaperChannels(forChannels n: Int) -> Int {
        max(20, Int((Double(n) * 0.02).rounded(.toNearestOrEven)))
    }

    /// HyperSpy `hanning_taper(side, channels, offset)` on every spectrum: the first and/or last `channels` channels (after `offset` channels that
    /// are zeroed) are multiplied by the rising / falling half of `np.hanning(2 channels)`. `channels == nil` is `max(20, round(0.02 n))`.
    public static func hanningTaper<I: EELSSpectrumImage>(_ image: I, side: TaperSide = .both, channels: Int? = nil, offset: Int = 0) throws -> (image: I, taperedChannels: Int) {
        let n = image.channels
        let c = channels ?? defaultTaperChannels(forChannels: n)
        guard c >= 1, offset >= 0 else { throw EELSDeconvolutionError.tooFewChannels(n) }
        // each side's slice must lie inside the spectrum (HyperSpy's broadcast fails otherwise)
        guard c + offset <= n else { throw EELSDeconvolutionError.tooFewChannels(n) }
        let window = hanning(2 * c)
        var counts = image.counts
        for p in 0..<(image.nx * image.ny) {
            let base = p * n
            if side == .left || side == .both {
                for k in 0..<c { counts[base + offset + k] *= window[k] }
                for k in 0..<offset { counts[base + k] *= 0.0 }
            }
            if side == .right || side == .both {
                for k in 0..<c { counts[base + n - offset - c + k] *= window[c + k] }
                for k in 0..<offset { counts[base + n - offset + k] *= 0.0 }
            }
        }
        let out = try I(nx: image.nx, ny: image.ny, channels: n, counts: counts, energyOffsetEV: image.energyOffsetEV, energyScaleEV: image.energyScaleEV)
        return (out, c)
    }
}
