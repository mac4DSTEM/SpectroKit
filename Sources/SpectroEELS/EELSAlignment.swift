//
//  EELSAlignment.swift
//  Role: Zero-loss peak alignment and mask, a port of exSpy 0.3.2
//        `align_zero_loss_peak` (`eels.py:318-483`), `estimate_zero_loss_peak_centre` (`:275-316`), `get_zero_loss_peak_mask`
//        (`:485-511`) and HyperSpy 2.4.0 `Signal1D.shift1D` (`signal1d.py:423-551`, `_shift1D :252-274`), `estimate_shift1D`
//        (`:626-736`, `_estimate_shift1D :236-249`, `interpolate1D :220-233`) and `align1D` (`:738-853`).
//
//  Faithful details (each pinned against exSpy, Tests/SpectroEELSTests/Fixtures/eels16-*):
//   - the coarse pass shifts every pixel to the MEAN centre, not to zero; `calibrate` then subtracts the new nan-mean centre from the offset;
//   - the subpixel pass (`subpixel`, only for more than one pixel) cross-correlates the mean-subtracted, linearly x(ip) upsampled window of
//     each pixel with pixel 0's, `np.correlate(ref, data, "full")`, argmax to the first index, shift = (argmax - len + 1) / ip * scale;
//   - `shift1D` is linear interpolation at `axis - shift` with LINEAR EXTRAPOLATION beyond the ends (scipy `make_interp_spline(k=1)` extrapolates);
//     the design note's "outside the axis NaN" is not what exSpy does and the pins (eels16 `shift1D` cases) say so; a NaN or zero shift leaves
//     the pixel unchanged; `crop` keeps channels `[ceil(offset + max shift), floor(high + min shift)]`, as `shift1D`'s ilow and ihigh.
//   - `max_shift` is a no-op in `estimate_shift1D` (clip without assignment) and `add_noise`-like options do not exist here: not offered.
//  DEVIATION: none in the numbers. The correlation is the direct dot-product form (`vDSP_dotprD` per lag), the order NumPy's `correlate` uses.
//

import Foundation
import Accelerate
import SpectroCore

public nonisolated struct ZeroLossAlignmentOptions: Sendable, Equatable {
    /// Subtract the nan-mean centre from the offset after each pass, so the zero-loss peak ends at 0 eV (exSpy `calibrate`).
    public var calibrate: Bool = true
    /// Follow the coarse pass with the cross-correlation pass (`align1D`), only when there is more than one pixel.
    public var subpixel: Bool = true
    /// Search window for the maximum, in eV (HyperSpy float `isig[a:b]`: end exclusive); also the window of the correlation. nil: the whole axis,
    /// and the correlation over (-3, 3) eV.
    public var signalRangeEV: ClosedRange<Double>? = nil
    /// Drop the channels any shift left undefined (`shift1D` crop); false keeps the size and extrapolates linearly. Either way a shift larger than the
    /// axis span is refused (`emptyAfterCrop`): HyperSpy computes the crop indices before it looks at `crop` and raises there too.
    public var crop: Bool = true
    /// HyperSpy `number_of_interpolation_points` (the upsampling factor is this plus one).
    public var interpolationPoints: Int = 5

    public init(calibrate: Bool = true, subpixel: Bool = true, signalRangeEV: ClosedRange<Double>? = nil, crop: Bool = true,
                interpolationPoints: Int = 5) {
        self.calibrate = calibrate; self.subpixel = subpixel; self.signalRangeEV = signalRangeEV; self.crop = crop
        self.interpolationPoints = interpolationPoints
    }
}

public nonisolated struct ZeroLossAlignment: Sendable {
    /// The aligned image: new offset and channel count.
    public let aligned: LowLossSpectrumImage
    /// The `also` images, shifted by the same amounts and calibrated by the same offset change.
    public let alsoAligned: [CoreLossSpectrumImage]
    /// The centre of each pixel's zero-loss peak before anything moved (the app's diagnostic); nil where masked.
    public let initialCentreEV: [Double?]
    /// The total shift applied per pixel (coarse plus subpixel), eV; nil where masked.
    public let shiftEV: [Double?]
    /// The input channels that survive (after both crops), of the INPUT image's axis.
    public let keptChannels: Range<Int>
    /// The same for each `also` image, on its own axis (they are cropped by the same shifts, each on its own scale).
    public let alsoKeptChannels: [Range<Int>]
    public let methodName: String
}

public nonisolated enum EELSAlignment {

    public static let methodName = "align_zero_loss_peak, exSpy 0.3.2 / HyperSpy 2.4.0"

    // MARK: Zero-loss peak centre and mask

    /// exSpy `estimate_zero_loss_peak_centre(mask)` per pixel: the energy of the maximum (the first, on a tie), nil where masked. With
    /// `signalRangeEV` only the channels of `isig[a:b]` are searched (the energy is of the channel found).
    public static func zeroLossPeakCentre(_ image: LowLossSpectrumImage, mask: PixelMask? = nil, signalRangeEV: ClosedRange<Double>? = nil) throws -> [Double?] {
        let spectra = RawSpectra(image)
        return try centres(spectra, mask: mask, range: signalRangeEV).map { $0.isNaN ? nil : $0 }
    }

    /// exSpy `get_zero_loss_peak_mask(width, signal_mask)`: per channel, true where the axis lies within `widthEV / 2` of the mean centre,
    /// OR-ed with `signalMask`.
    public static func zeroLossPeakMask(_ image: LowLossSpectrumImage, widthEV: Double = 5.0, signalMask: [Bool]? = nil) throws -> [Bool] {
        if let signalMask, signalMask.count != image.channels {
            throw EELSAlignmentError.maskShapeMismatch(expected: image.channels, got: signalMask.count)
        }
        guard widthEV.isFinite else { throw EELSAlignmentError.invalidOption("the mask width must be finite") }
        let spectra = RawSpectra(image)
        let c = try centres(spectra, mask: nil, range: nil)
        let mean = c.withUnsafeBufferPointer { NumpySum.pairwise($0.baseAddress!, count: c.count) } / Double(c.count)
        let low = mean - widthEV / 2, high = mean + widthEV / 2
        return (0..<image.channels).map { i in
            let e = image.energyOffsetEV + image.energyScaleEV * Double(i)
            let inside = low <= e && e <= high
            return inside || (signalMask?[i] ?? false)
        }
    }

    // MARK: Shifts

    /// HyperSpy `estimate_shift1D(start, end, reference_indices=(pixel), number_of_interpolation_points)` in eV (the argmax of the full
    /// cross-correlation of the mean-subtracted, upsampled windows, over `ip`, times the scale). nil where masked. `fromEV` / `toEV` nil: the whole
    /// axis; a float bound is `value2index` (round, an out-of-axis value is refused) and the window is `[i1, i2)`.
    public static func estimateShift(_ image: LowLossSpectrumImage, fromEV: Double?, toEV: Double?, referencePixel: Int = 0,
                                     interpolationPoints: Int = 5, mask: PixelMask? = nil,
                                     cancelled: @Sendable () -> Bool = SpectroCancellation.task,
                                     progress: (@Sendable (Double) -> Void)? = nil) throws -> [Double?] {
        let spectra = RawSpectra(image)
        try validate(mask: mask, pixels: spectra.pixels)
        guard referencePixel >= 0, referencePixel < spectra.pixels else {
            throw EELSAlignmentError.invalidOption("the reference pixel \(referencePixel) is outside the image")
        }
        let shifts = try estimate(spectra, fromEV: fromEV, toEV: toEV, referencePixel: referencePixel, interpolationPoints: interpolationPoints,
                                  mask: mask, cancelled: cancelled, progress: progress)
        return shifts.map { $0.isNaN ? nil : $0 }
    }

    /// HyperSpy `shift1D(shift_array, crop)` with linear interpolation: each pixel shifted by `shiftsEV[p]` (nil or 0: unchanged), cropped to
    /// the channels every shift leaves defined when `crop` (the offset moves with it).
    public static func shift<I: EELSSpectrumImage>(_ image: I, byEV shifts: [Double?], crop: Bool = true) throws -> (image: I, keptChannels: Range<Int>) {
        let spectra = RawSpectra(image)
        guard shifts.count == spectra.pixels else { throw EELSAlignmentError.shiftCountMismatch(expected: spectra.pixels, got: shifts.count) }
        if let bad = shifts.firstIndex(where: { $0 != nil && !$0!.isFinite }) { throw EELSAlignmentError.nonFiniteShift(pixel: bad) }
        let moved = try shifted(spectra, by: shifts.map { $0 ?? .nan }, crop: crop)
        let out = try I(nx: image.nx, ny: image.ny, channels: moved.spectra.channels, counts: moved.spectra.counts,
                        energyOffsetEV: moved.spectra.offset, energyScaleEV: moved.spectra.scale)
        return (out, moved.kept)
    }

    // MARK: Alignment

    /// exSpy `align_zero_loss_peak(calibrate, also_align, subpixel, mask, signal_range, crop, number_of_interpolation_points)`.
    public static func alignZeroLossPeak(
        _ image: LowLossSpectrumImage, alsoAlign: [CoreLossSpectrumImage] = [], mask: PixelMask? = nil,
        options: ZeroLossAlignmentOptions = .init(),
        cancelled: @Sendable () -> Bool = SpectroCancellation.task, progress: (@Sendable (Double) -> Void)? = nil
    ) throws -> ZeroLossAlignment {
        let pixels = image.nx * image.ny
        try validate(mask: mask, pixels: pixels)
        for (i, a) in alsoAlign.enumerated() where a.nx != image.nx || a.ny != image.ny { throw EELSAlignmentError.alsoAlignShapeMismatch(index: i) }
        try validate(interpolationPoints: options.interpolationPoints, channels: image.channels)
        if let r = options.signalRangeEV, !(r.lowerBound < r.upperBound) { throw EELSAlignmentError.invalidOption("the search window is empty") }

        var main = RawSpectra(image)
        var also = alsoAlign.map { RawSpectra($0) }
        var total = [Double](repeating: 0, count: pixels)       // NaN where masked
        var keptLow = 0, keptHigh = image.channels             // in INPUT channels
        var alsoLow = [Int](repeating: 0, count: alsoAlign.count)

        // exSpy: zlpc = estimate_zero_loss_peak_centre(self, mask, signal_range); mean_ = nanmean(zlpc).
        let zlpc0 = try centres(main, mask: mask, range: options.signalRangeEV, cancelled: cancelled)
        let mean0 = nanMean(zlpc0)
        if mean0.isNaN {
            // Every pixel masked (or none finite): nothing to align; shift1D of an all-NaN array changes nothing.
            return ZeroLossAlignment(aligned: image, alsoAligned: alsoAlign, initialCentreEV: zlpc0.map { $0.isNaN ? nil : $0 },
                                     shiftEV: [Double?](repeating: nil, count: pixels), keptChannels: 0..<image.channels,
                                     alsoKeptChannels: alsoAlign.map { 0..<$0.channels }, methodName: methodName)
        }
        progress?(0.05)
        try SpectroCancellation.check(cancelled)

        // Coarse pass: every signal shifted by mean - zlpc (also_align first, then self; each cropped on its own axis).
        let coarse = zlpc0.map { $0.isNaN ? Double.nan : -$0 + mean0 }
        for i in also.indices {
            let moved = try shifted(also[i], by: coarse, crop: options.crop, cancelled: cancelled)
            also[i] = moved.spectra; alsoLow[i] += moved.kept.lowerBound
        }
        let firstMain = try shifted(main, by: coarse, crop: options.crop, cancelled: cancelled)
        main = firstMain.spectra
        keptLow += firstMain.kept.lowerBound; keptHigh = keptLow + main.channels
        for p in 0..<pixels where !coarse[p].isNaN { total[p] += coarse[p] }
        progress?(0.25)

        func calibrateOffsets() throws {
            let z = try centres(main, mask: mask, range: options.signalRangeEV, cancelled: cancelled)
            let value = nanMean(z)
            guard !value.isNaN else { return }
            main.offset -= value
            for i in also.indices { also[i].offset -= value }
        }
        if options.calibrate { try calibrateOffsets() }
        progress?(0.4)

        if options.subpixel {
            var (start, end) = options.signalRangeEV.map { ($0.lowerBound, $0.upperBound) } ?? (-3.0, 3.0)
            if !options.calibrate { start += mean0; end += mean0 }
            let axis = try axisOf(main)
            if !(start > axis.lowValue) { start = axis.lowValue }
            if !(end < axis.highValue) { end = axis.highValue }
            if pixels > 1 {
                let fine = try estimate(main, fromEV: start, toEV: end, referencePixel: 0, interpolationPoints: options.interpolationPoints,
                                        mask: mask, cancelled: cancelled, progress: progress.map { p in { @Sendable f in p(0.4 + 0.4 * f) } })
                let moved = try shifted(main, by: fine, crop: options.crop, cancelled: cancelled)
                main = moved.spectra
                keptLow += moved.kept.lowerBound; keptHigh = keptLow + main.channels
                for i in also.indices {
                    let moved = try shifted(also[i], by: fine, crop: options.crop, cancelled: cancelled)
                    also[i] = moved.spectra; alsoLow[i] += moved.kept.lowerBound
                }
                for p in 0..<pixels where !fine[p].isNaN { total[p] += fine[p] }
            }
            if options.calibrate { try calibrateOffsets() }
        }
        progress?(1)

        let aligned = try LowLossSpectrumImage(nx: image.nx, ny: image.ny, channels: main.channels, counts: main.counts,
                                               energyOffsetEV: main.offset, energyScaleEV: main.scale)
        let alsoOut = try zip(also, alsoAlign).map { raw, original in
            try CoreLossSpectrumImage(nx: original.nx, ny: original.ny, channels: raw.channels, counts: raw.counts,
                                      energyOffsetEV: raw.offset, energyScaleEV: raw.scale)
        }
        return ZeroLossAlignment(aligned: aligned, alsoAligned: alsoOut, initialCentreEV: zlpc0.map { $0.isNaN ? nil : $0 },
                                 shiftEV: (0..<pixels).map { coarse[$0].isNaN ? nil : total[$0] },
                                 keptChannels: keptLow..<keptHigh,
                                 alsoKeptChannels: zip(alsoLow, also).map { $0..<($0 + $1.channels) }, methodName: methodName)
    }

    // MARK: - Internals

    /// The raw arrays of one spectrum image and its axis (the generic operations work on this, not on the public types).
    package struct RawSpectra: Sendable {
        package var counts: [Double]
        package let pixels: Int
        package var channels: Int
        package var offset: Double
        package let scale: Double

        package init<I: EELSSpectrumImage>(_ image: I) {
            counts = image.counts; pixels = image.nx * image.ny; channels = image.channels
            offset = image.energyOffsetEV; scale = image.energyScaleEV
        }
    }

    /// The cross-correlation is O((channels x points)^2) per pixel: more than 1000 interpolation points is refused (HyperSpy's own docstring warns it
    /// "can saturate the memory"), and a count that would overflow the upsampled length cannot start.
    package static let maximumInterpolationPoints = 1000

    private static func validate(interpolationPoints: Int, channels: Int) throws {
        guard interpolationPoints >= 0, interpolationPoints <= maximumInterpolationPoints else {
            throw EELSAlignmentError.invalidOption("interpolationPoints must be between 0 and \(maximumInterpolationPoints)")
        }
        _ = channels
    }

    private static func validate(mask: PixelMask?, pixels: Int) throws {
        if let mask, mask.count != pixels { throw EELSAlignmentError.maskShapeMismatch(expected: pixels, got: mask.count) }
    }

    private static func axisOf(_ s: RawSpectra) throws -> EELSAxis { try EELSAxis(offset: s.offset, scale: s.scale, size: s.channels) }

    /// `np.nanmean`: NaN replaced by 0, summed by NumPy's pairwise sum, divided by the count of the others (NaN when there are none). The order of
    /// the sum matters: a mean one ulp off turns a pixel sitting on the mean into a tiny non-zero shift, and an integer number of channels into
    /// a neighbouring crop index.
    private static func nanMean(_ a: [Double]) -> Double {
        var t = a
        var n = 0
        for i in t.indices { if t[i].isNaN { t[i] = 0 } else { n += 1 } }
        guard n > 0 else { return .nan }
        return t.withUnsafeBufferPointer { NumpySum.pairwise($0.baseAddress!, count: $0.count) } / Double(n)
    }

    /// The channel window `isig[a:b]` of a float range (end exclusive, an end beyond the axis clamps), or the whole axis.
    private static func window(_ s: RawSpectra, _ range: ClosedRange<Double>?) throws -> Range<Int> {
        guard let range else { return 0..<s.channels }
        let axis = try axisOf(s)
        do {
            let r = try axis.rules.channelRange(from: range.lowerBound, to: range.upperBound)
            guard !r.isEmpty else { throw EELSAlignmentError.signalRangeOutsideAxis(fromEV: range.lowerBound, toEV: range.upperBound) }
            return r
        } catch is EnergyAxisError {
            throw EELSAlignmentError.signalRangeOutsideAxis(fromEV: range.lowerBound, toEV: range.upperBound)
        }
    }

    /// `valuemax` per pixel over the window: the axis value of the first maximum; NaN where masked.
    private static func centres(_ s: RawSpectra, mask: PixelMask?, range: ClosedRange<Double>?,
                                cancelled: @Sendable () -> Bool = { false }) throws -> [Double] {
        try validate(mask: mask, pixels: s.pixels)
        let w = try window(s, range)
        let subOffset = s.offset + s.scale * Double(w.lowerBound)
        let out = EELSSlots<Double>(count: s.pixels, initial: .nan)
        try s.counts.withUnsafeBufferPointer { buf in
            nonisolated(unsafe) let data = buf
            try EELSParallel.forEachPixel(count: s.pixels, cancelled: cancelled, progress: nil) { p in
                if mask?[p] == true { return }
                let row = data.baseAddress! + p * s.channels
                var best = row[w.lowerBound], at = 0
                var k = 1
                while k < w.count { let v = row[w.lowerBound + k]; if v > best { best = v; at = k }; k += 1 }
                out.set(p, subOffset + s.scale * Double(at))
            }
        }
        return out.values
    }

    /// HyperSpy `interpolate1D(ip, data)`: linear, `n * ip - (ip - 1)` points over the same span.
    private static func upsample(_ x: UnsafeBufferPointer<Double>, ip: Int) -> [Double] {
        let n = x.count
        if ip == 1 || n < 2 { return Array(x) }
        let m = n * ip - (ip - 1)
        var out = [Double](repeating: 0, count: m)
        for j in 0..<m {
            let u = Double(j) / Double(ip)
            var i = Int(u.rounded(.down))
            if i > n - 2 { i = n - 2 }
            let w = u - Double(i)
            out[j] = x[i] * (1 - w) + x[i + 1] * w
        }
        return out
    }

    /// `np.argmax(np.correlate(ref, data, "full")) - len(ref) + 1`, ties to the first index; `ref` and `data` have the same length.
    private static func correlationLag(ref: [Double], data: [Double]) -> Double {
        let n = ref.count
        var best = -Double.infinity
        var lag = 0
        ref.withUnsafeBufferPointer { a in
            data.withUnsafeBufferPointer { v in
                var m = 0
                while m <= 2 * n - 2 {
                    let k = m - (n - 1)                              // c[m] = sum_i a[i + k] * v[i]
                    let i0 = max(0, -k), i1 = min(n, n - k)
                    var c = 0.0
                    if i1 > i0 { vDSP_dotprD(a.baseAddress! + (i0 + k), 1, v.baseAddress! + i0, 1, &c, vDSP_Length(i1 - i0)) }
                    if c > best { best = c; lag = k }
                    m += 1
                }
            }
        }
        return Double(lag)
    }

    private static func estimate(_ s: RawSpectra, fromEV: Double?, toEV: Double?, referencePixel: Int, interpolationPoints: Int, mask: PixelMask?,
                                 cancelled: @Sendable () -> Bool, progress: (@Sendable (Double) -> Void)?) throws -> [Double] {
        try validate(interpolationPoints: interpolationPoints, channels: s.channels)
        let ip = interpolationPoints + 1
        let axis = try axisOf(s)
        func index(_ v: Double?) throws -> Int? {
            guard let v else { return nil }
            guard let i = axis.channel(ofEnergy: v) else { throw EELSAlignmentError.signalRangeOutsideAxis(fromEV: fromEV ?? axis.lowValue, toEV: toEV ?? axis.highValue) }
            return i
        }
        let i1 = try index(fromEV) ?? 0
        let i2 = try index(toEV) ?? s.channels
        guard i2 - i1 >= 2 else { throw EELSAlignmentError.signalRangeOutsideAxis(fromEV: fromEV ?? axis.lowValue, toEV: toEV ?? axis.highValue) }
        let refRaw = s.counts[(referencePixel * s.channels + i1)..<(referencePixel * s.channels + i2)]
        var ref = refRaw.withUnsafeBufferPointer { upsample($0, ip: ip) }
        let refMean = ref.withUnsafeBufferPointer { NumpySum.pairwise($0.baseAddress!, count: $0.count) } / Double(ref.count)
        for j in ref.indices { ref[j] -= refMean }
        let out = EELSSlots<Double>(count: s.pixels, initial: .nan)
        let refCopy = ref
        try s.counts.withUnsafeBufferPointer { buf in
            nonisolated(unsafe) let data = buf
            try EELSParallel.forEachPixel(count: s.pixels, chunk: 8, cancelled: cancelled, progress: progress) { p in
                if mask?[p] == true { return }
                let slice = UnsafeBufferPointer(start: data.baseAddress! + (p * s.channels + i1), count: i2 - i1)
                var d = upsample(slice, ip: ip)
                let mean = d.withUnsafeBufferPointer { NumpySum.pairwise($0.baseAddress!, count: $0.count) } / Double(d.count)
                for j in d.indices { d[j] -= mean }
                out.set(p, correlationLag(ref: refCopy, data: d) / Double(ip) * s.scale)
            }
        }
        return out.values
    }

    /// HyperSpy `shift1D(shift_array, crop=…)`: linear interpolation at `axis - shift` (linear extrapolation at the ends), a NaN or zero shift
    /// leaves a pixel alone; with `crop` the channels `[ilow, ihigh)` that every shift leaves defined are kept and the offset follows.
    private static func shifted(_ s: RawSpectra, by shifts: [Double], crop: Bool,
                                cancelled: @Sendable () -> Bool = { false }) throws -> (spectra: RawSpectra, kept: Range<Int>) {
        // `if not np.any(shift_array): return` (an all-zero array; NaN counts as non-zero).
        if !shifts.contains(where: { $0 != 0 }) { return (s, 0..<s.channels) }
        let axis = try axisOf(s)
        var minimum = Double.infinity, maximum = -Double.infinity
        for v in shifts where !v.isNaN { minimum = min(minimum, v); maximum = max(maximum, v) }
        var ihigh = s.channels, ilow = 0
        if minimum < 0 {
            guard let i = axis.channel(ofEnergy: axis.highValue + minimum, rounding: .down) else { throw EELSAlignmentError.emptyAfterCrop }
            ihigh = 1 + i
        }
        if maximum > 0 {
            guard let i = axis.channel(ofEnergy: axis.offset + maximum, rounding: .up) else { throw EELSAlignmentError.emptyAfterCrop }
            ilow = i
        }
        let n = s.channels
        var out = [Double](repeating: 0, count: s.counts.count)
        try out.withUnsafeMutableBufferPointer { dst in
            nonisolated(unsafe) let target = dst
            try s.counts.withUnsafeBufferPointer { src in
                nonisolated(unsafe) let source = src
                try EELSParallel.forEachPixel(count: s.pixels, cancelled: cancelled, progress: nil) { p in
                    let row = source.baseAddress! + p * n
                    let to = target.baseAddress! + p * n
                    let shift = shifts[p]
                    if shift.isNaN || shift == 0 || n < 2 {
                        for c in 0..<n { to[c] = row[c] }
                        return
                    }
                    for c in 0..<n {
                        let x = (s.offset + s.scale * Double(c)) - shift          // original_axis - shift, as the array arithmetic does
                        let u = (x - s.offset) / s.scale
                        var j = Int(u.rounded(.down))
                        if j < 0 { j = 0 } else if j > n - 2 { j = n - 2 }
                        let t0 = s.offset + s.scale * Double(j), t1 = s.offset + s.scale * Double(j + 1)
                        let w = (x - t0) / (t1 - t0)
                        to[c] = row[j] * (1 - w) + row[j + 1] * w
                    }
                }
            }
        }
        var result = s
        result.counts = out
        guard crop else { return (result, 0..<n) }
        guard ilow < ihigh else { throw EELSAlignmentError.emptyAfterCrop }
        let kept = ilow..<ihigh
        if kept.count != n {
            var cropped = [Double](repeating: 0, count: s.pixels * kept.count)
            for p in 0..<s.pixels {
                for c in 0..<kept.count { cropped[p * kept.count + c] = out[p * n + ilow + c] }
            }
            result.counts = cropped
            result.channels = kept.count
            result.offset = s.offset + s.scale * Double(ilow)
        }
        return (result, kept)
    }
}
