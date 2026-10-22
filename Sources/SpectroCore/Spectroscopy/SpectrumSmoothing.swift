//
//  SpectrumSmoothing.swift
//  Role: Smoothing of a spectrum FOR DISPLAY: Savitzky-Golay, Gaussian and moving average, on one spectrum or on a spectrum
//        image (one call per spectrum, in parallel).
//
//  DISPLAY ONLY. A smoothed spectrum is not counts: its noise is correlated between channels and no longer Poisson, so it is
//  never to be fed to a fit, a net-count window, a quantification or any counting statistic. Fit the raw counts.
//
//  References, each at its own convention (docs/parity.md):
//   * Savitzky-Golay: `scipy.signal.savgol_filter(x, window_length, polyorder, mode=...)`, polyorder >= 1, odd window_length >= 3,
//     deriv 0. HyperSpy 2.4.0 `Signal1D.smooth_savitzky_golay(polynomial_order, window_length)` calls it with its default mode
//     "interp" one spectrum at a time (the axis scale only enters the derivative). The smoothing coefficients are the middle row
//     of the hat matrix of the least-squares polynomial fit to the window (SciPy solves for them with `lstsq`: the same numbers
//     to rounding); mode "interp" (`.polynomialFit`) fits one polynomial to the first and to the last window and evaluates it at
//     the edge samples, as SciPy's `_fit_edges_polyfit`; the other modes extend the signal. Unlike SciPy's derivative path
//     this is not bit for bit (agreement is ~1e-12, the test tolerance is SciPy's `assert_allclose`).
//   * Gaussian: `scipy.ndimage.gaussian_filter1d(x, sigma, truncate=4, mode)`: sigma in channels, radius int(truncate * sigma + 0.5),
//     weights exp(-x^2 / (2 sigma^2)) normalised to a sum of 1.
//   * Moving average: `scipy.ndimage.uniform_filter1d(x, size, mode)`: output i is the mean of x[i - size/2 ... i + (size-1)/2]
//     (integer division), so an even width is centred half a channel to the right of i.
//  Boundary modes are SciPy ndimage's: reflect (d c b a | a b c d | d c b a), mirror (d c b | a b c d | c b a), nearest, wrap,
//  constant (a value beyond the ends; 0 unless given).
//
//  CPU float64 only.
//

import Foundation

/// A refused smoothing request.
public struct SpectrumSmoothingError: Error, Equatable, CustomStringConvertible, Sendable {
    public let description: String
}

/// How a filter reads beyond the ends of a spectrum (SciPy ndimage mode names).
public enum SpectrumBoundary: Sendable, Equatable {
    case reflect
    case mirror
    case nearest
    case wrap
    case constant(Double)

    /// The index inside 0 ..< n that sample `i` of the extended signal reads, nil for a constant.
    @inline(__always) func index(_ i: Int, count n: Int) -> Int? {
        if i >= 0, i < n { return i }
        switch self {
        case .constant: return nil
        case .nearest: return i < 0 ? 0 : n - 1
        case .wrap:
            let m = i % n
            return m < 0 ? m + n : m
        case .reflect:
            let period = 2 * n
            var m = i % period
            if m < 0 { m += period }
            return m >= n ? period - 1 - m : m
        case .mirror:
            if n == 1 { return 0 }
            let period = 2 * n - 2
            var m = i % period
            if m < 0 { m += period }
            return m >= n ? period - m : m
        }
    }

    var constantValue: Double { if case .constant(let v) = self { return v } else { return 0 } }
}

/// How a Savitzky-Golay filter treats the first and last `window / 2` samples.
public enum SavitzkyGolayEdge: Sendable, Equatable {
    /// SciPy / HyperSpy default (`mode="interp"`): a polynomial fitted to the first (last) window gives the edge samples.
    /// Needs the window not longer than the spectrum.
    case polynomialFit
    /// Extend the signal and apply the filter everywhere.
    case extend(SpectrumBoundary)
}

/// A smoothing for display. See the file header: never feed a smoothed spectrum to a fit.
public enum SpectrumSmoothing: Sendable, Equatable {
    /// `scipy.signal.savgol_filter` (deriv 0): odd `window` >= 3, 1 <= `order` < `window`.
    case savitzkyGolay(window: Int, order: Int, edge: SavitzkyGolayEdge = .polynomialFit)
    /// `scipy.ndimage.gaussian_filter1d`: `sigma` in channels (> 0), kernel radius int(`truncate` * sigma + 0.5).
    case gaussian(sigma: Double, truncate: Double = 4, boundary: SpectrumBoundary = .reflect)
    /// `scipy.ndimage.uniform_filter1d`: `width` channels (>= 1).
    case movingAverage(width: Int, boundary: SpectrumBoundary = .reflect)

    /// Checks the parameters (the same checks `smooth` makes).
    public func validate() throws {
        switch self {
        case .savitzkyGolay(let w, let p, _):
            guard w >= 3 else { throw SpectrumSmoothingError(description: "Savitzky-Golay window \(w) is below 3.") }
            guard w % 2 == 1 else { throw SpectrumSmoothingError(description: "Savitzky-Golay window \(w) is even; it must be odd.") }
            guard w <= 4097 else { throw SpectrumSmoothingError(description: "Savitzky-Golay window \(w) is above the limit of 4097.") }
            guard p >= 1 else { throw SpectrumSmoothingError(description: "Savitzky-Golay polynomial order \(p) is below 1.") }
            guard p < w else { throw SpectrumSmoothingError(description: "Savitzky-Golay polynomial order \(p) must be less than the window \(w).") }
        case .gaussian(let s, let t, _):
            guard s.isFinite, s > 0, s < 1e6 else { throw SpectrumSmoothingError(description: "Gaussian sigma must be positive and finite (got \(s)).") }
            guard t.isFinite, t > 0, t * s < 1e7 else { throw SpectrumSmoothingError(description: "Gaussian truncate must be positive and finite (got \(t)).") }
            guard t * s + 0.5 < Double(1 << 19) else {
                throw SpectrumSmoothingError(description: "Gaussian kernel radius \(t * s) channels is above the limit of \((1 << 19) - 1).")
            }
        case .movingAverage(let w, _):
            guard w >= 1, w < 1 << 24 else { throw SpectrumSmoothingError(description: "Moving-average width \(w) is below 1.") }
        }
    }

    /// The smoothed spectrum (same length). Throws `SpectrumSmoothingError` for bad parameters, a non-finite sample, or a
    /// Savitzky-Golay `.polynomialFit` window longer than the spectrum.
    public func smooth(_ spectrum: [Double]) throws -> [Double] {
        try validate()
        guard spectrum.allSatisfy(\.isFinite) else { throw SpectrumSmoothingError(description: "A sample is not finite.") }
        let plan = try Plan(self, length: spectrum.count)
        return plan.apply(spectrum)
    }

    /// The same for summed counts (a pooled spectrum).
    public func smooth(_ counts: [UInt64]) throws -> [Double] { try smooth(counts.map { Double($0) }) }

    /// The same for each spectrum of a list (a line profile's `spectra`), all of one length.
    public func smooth(spectra: [[Double]]) throws -> [[Double]] {
        guard let n = spectra.first?.count else { return [] }
        guard spectra.allSatisfy({ $0.count == n }) else { throw SpectrumSmoothingError(description: "The spectra differ in length.") }
        let flat = try smoothBatch(spectra.flatMap { $0 }, spectrumLength: n)
        return (0..<spectra.count).map { Array(flat[($0 * n)..<(($0 + 1) * n)]) }
    }

    /// The same for a spectrum image held as one array, `spectrumLength` channels per spectrum, spectrum after spectrum
    /// (`[pixel * spectrumLength + channel]`, pixels row-major); one call per spectrum, on all cores.
    public func smoothBatch(_ data: [Double], spectrumLength n: Int) throws -> [Double] {
        try validate()
        guard n > 0, data.count % n == 0 else {
            throw SpectrumSmoothingError(description: "\(data.count) values are not a whole number of spectra of \(n) channels.")
        }
        guard data.allSatisfy(\.isFinite) else { throw SpectrumSmoothingError(description: "A sample is not finite.") }
        let plan = try Plan(self, length: n)
        let count = data.count / n
        var out = [Double](repeating: 0, count: data.count)
        let chunk = 64, chunks = (count + chunk - 1) / chunk
        out.withUnsafeMutableBufferPointer { o in
            let shared = SharedOutput(base: o.baseAddress!)
            data.withUnsafeBufferPointer { d in
                let input = SharedInput(base: d.baseAddress!)
                DispatchQueue.concurrentPerform(iterations: chunks) { ci in
                    for p in (ci * chunk)..<min(count, (ci + 1) * chunk) {
                        plan.apply(input.base + p * n, count: n, into: shared.base + p * n)
                    }
                }
            }
        }
        return out
    }

    /// The same for every pixel of a `DenseSpectrumImage` or `SparseSpectrumImage`: `ny * nx * channels` values, pixel-major
    /// (`[(row * nx + column) * channels + channel]`). Any other conformer is refused.
    public func smoothedSpectra(of image: some SpectrumImage) throws -> [Double] {
        let flat: [Double]
        if let d = image as? DenseSpectrumImage { flat = d.counts.map { Double($0) } }
        else if let s = image as? SparseSpectrumImage { flat = s.densified().counts.map { Double($0) } }
        else { throw SpectrumSmoothingError(description: "This spectrum image type cannot be read pixel by pixel.") }
        return try smoothBatch(flat, spectrumLength: image.channels)
    }

    private struct SharedOutput: @unchecked Sendable { let base: UnsafeMutablePointer<Double> }
    private struct SharedInput: @unchecked Sendable { let base: UnsafePointer<Double> }

    // MARK: - The prepared filter for one spectrum length

    private struct Plan: Sendable {
        enum Kind: Sendable {
            /// weights w[0 ..< m], tap k reads x[i - left + k]; boundary for the ends.
            case kernel(weights: [Double], left: Int, boundary: SpectrumBoundary)
            /// SG interior weights (odd, centred) and the hat matrix rows for the edge samples (`hat[j * wl + m]`).
            case savgolFit(weights: [Double], hat: [Double], window: Int)
        }
        let kind: Kind

        init(_ s: SpectrumSmoothing, length n: Int) throws {
            switch s {
            case .movingAverage(let w, let b):
                let left = w / 2
                kind = .kernel(weights: [Double](repeating: 1 / Double(w), count: w), left: left, boundary: b)
            case .gaussian(let sigma, let truncate, let b):
                let radius = Int(truncate * sigma + 0.5)
                // radius 0 (sigma so small the kernel is one tap) is the identity, as scipy's gaussian_filter1d; avoids 0 * inf
                var k = radius == 0 ? [1.0] : (-radius...radius).map { exp(-0.5 / (sigma * sigma) * Double($0 * $0)) }
                let total = k.reduce(0, +)
                k = k.map { $0 / total }
                kind = .kernel(weights: k, left: radius, boundary: b)
            case .savitzkyGolay(let wl, let po, let edge):
                if case .polynomialFit = edge, wl > n {
                    throw SpectrumSmoothingError(description: "Savitzky-Golay window \(wl) is longer than the spectrum (\(n) channels).")
                }
                let hat = try Self.hatMatrix(window: wl, order: po)
                let h = wl / 2
                let centre = (0..<wl).map { hat[h * wl + $0] }
                switch edge {
                case .polynomialFit: kind = .savgolFit(weights: centre, hat: hat, window: wl)
                case .extend(let b): kind = .kernel(weights: centre, left: h, boundary: b)
                }
            }
        }

        /// H = V V^+ for V[j, k] = ((j - h) / h)^k, j in 0 ..< window, k in 0 ... order (scaled for conditioning): row j maps a
        /// window of samples to the polynomial fit at position j. `hat[j * window + m]`.
        static func hatMatrix(window wl: Int, order po: Int) throws -> [Double] {
            let h = wl / 2
            var v = ColumnMatrix(rows: wl, cols: po + 1)
            for j in 0..<wl {
                let x = Double(j - h) / Double(h)
                var p = 1.0
                for k in 0...po { v[j, k] = p; p *= x }
            }
            var eye = ColumnMatrix(rows: wl, cols: wl)
            for j in 0..<wl { eye[j, j] = 1 }
            guard let solved = FitLinearAlgebra.leastSquaresSVD(v, eye, rcond: Double(wl) * Double.ulpOfOne) else {
                throw SpectrumSmoothingError(description: "The Savitzky-Golay least squares failed.")
            }
            var hat = [Double](repeating: 0, count: wl * wl)
            for j in 0..<wl {
                for m in 0..<wl {
                    var s = 0.0
                    for k in 0...po { s += v[j, k] * solved.x[k, m] }
                    hat[j * wl + m] = s
                }
            }
            return hat
        }

        func apply(_ x: [Double]) -> [Double] {
            var out = [Double](repeating: 0, count: x.count)
            x.withUnsafeBufferPointer { xp in out.withUnsafeMutableBufferPointer { op in
                if let b = xp.baseAddress, let o = op.baseAddress { apply(b, count: x.count, into: o) }
            } }
            return out
        }

        func apply(_ x: UnsafePointer<Double>, count n: Int, into out: UnsafeMutablePointer<Double>) {
            guard n > 0 else { return }
            switch kind {
            case .kernel(let w, let left, let boundary):
                let m = w.count
                let cval = boundary.constantValue
                w.withUnsafeBufferPointer { wp in
                    for i in 0..<n {
                        var acc = 0.0
                        let first = i - left
                        if first >= 0, first + m <= n {
                            for k in 0..<m { acc += wp[k] * x[first + k] }
                        } else {
                            for k in 0..<m {
                                if let j = boundary.index(first + k, count: n) { acc += wp[k] * x[j] } else { acc += wp[k] * cval }
                            }
                        }
                        out[i] = acc
                    }
                }
            case .savgolFit(let w, let hat, let wl):
                let h = wl / 2
                for i in h..<(n - h) {
                    var acc = 0.0
                    for k in 0..<wl { acc += w[k] * x[i - h + k] }
                    out[i] = acc
                }
                for j in 0..<h {
                    var a = 0.0, b = 0.0
                    for m in 0..<wl {
                        a += hat[j * wl + m] * x[m]
                        b += hat[(wl - 1 - j) * wl + m] * x[n - wl + m]
                    }
                    out[j] = a
                    out[n - 1 - j] = b
                }
            }
        }
    }
}
