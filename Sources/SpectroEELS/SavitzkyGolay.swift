//
//  SavitzkyGolay.swift
//  Role: The first derivative of a spectrum as SciPy 1.18.1's `savgol_filter(x, window_length, polyorder, deriv=1,
//        delta=scale)` computes it with its default `mode="interp"`, which is how HyperSpy 2.4.0
//        `smooth_savitzky_golay(differential_order=1)` calls it (`_signals/signal1d.py:933-941`, one spectrum at a time) and so
//        how exSpy's `estimate_elastic_scattering_threshold` finds the threshold (`exspy/signals/_eels.py:716-721`).
//
//  Coefficients and edge fits use a scalar, twice-reorthogonalized QR of a centered, normalized Vandermonde matrix.
//  Its operation order is fixed: no Accelerate/LAPACK dispatch, SIMD reduction or implicit fused multiply-add is used.
//  Center coefficients are explicitly symmetric (even derivative) or antisymmetric (odd derivative). Edge dot products
//  use explicit fused multiply-add in ascending sample order and do not depend on the number of spectra in the image.
//  This intentionally differs from SciPy's platform-dependent LAPACK rounding. The original SciPy fixtures remain as
//  deviation evidence; Python-oracle fixtures specify the deterministic threshold tie policy. Interior convolution keeps the
//  three SciPy accumulation paths, including their explicit fused and unfused operations, for supplied coefficients.
//
//  Restrictions against SciPy, all refused with an error: an even window (SciPy computes it with a half-integer position;
//  exSpy's docstring says odd), a window below 3, a polynomial order below 1 (SciPy returns zeros), a polynomial order of
//  `windowLength` or more (SciPy raises).
//

import Foundation
import SpectroCore

package nonisolated enum SavitzkyGolay {

    /// `scipy.signal.savgol_coeffs(window_length, polyorder, deriv, delta)` with `pos=None`, `use="conv"` (`_savitzky_golay.py:11-160`),
    /// for an odd window. The coefficients are in convolution order (the window position reversed).
    package static func coefficients(windowLength wl: Int, polynomialOrder po: Int, derivative deriv: Int = 1,
                                     delta: Double = 1.0) throws -> [Double] {
        try validate(windowLength: wl, polynomialOrder: po)
        guard deriv >= 0 else { throw EELSThicknessError.invalidSavitzkyGolay("derivative order below 0") }
        // `if deriv > polyorder: return zeros` (:132-134).
        if deriv > po { return [Double](repeating: 0, count: wl) }
        let fit = try SavitzkyGolayQR(windowLength: wl, polynomialOrder: po)
        var weights = fit.weights(position: wl / 2, derivative: deriv, delta: delta)
        let h = wl / 2
        // The exact centered functional has this parity. Removing the QR roundoff asymmetry also prevents tiny
        // coefficient changes from selecting different convolution paths on different CPUs.
        for k in 1...h {
            if deriv % 2 == 1 {
                let pair = (weights[h - k] - weights[h + k]) * 0.5
                weights[h - k] = pair; weights[h + k] = -pair
            } else {
                let pair = (weights[h - k] + weights[h + k]) * 0.5
                weights[h - k] = pair; weights[h + k] = pair
            }
        }
        if deriv % 2 == 1 { weights[h] = 0 }
        return Array(weights.reversed())
    }

    /// How SciPy's `correlate1d` accumulates a filter, decided by its weights (see the header).
    package nonisolated enum InteriorPath: Sendable, Equatable { case general, antisymmetric, symmetric }

    /// `NI_Correlate1D`'s test of the (centred) weights: symmetric when `|c[h-k] - c[h+k]| <= DBL_EPSILON` for every k >= 1, else
    /// anti-symmetric when `|c[h-k] + c[h+k]| <= DBL_EPSILON` for every k, else general.
    package static func interiorPath(coefficients c: [Double]) -> InteriorPath {
        let wl = c.count, h = wl / 2
        guard wl % 2 == 1 else { return .general }
        let eps = Double.ulpOfOne
        if (1...max(h, 1)).allSatisfy({ h == 0 || abs(c[h - $0] - c[h + $0]) <= eps }) { return .symmetric }
        if (1...max(h, 1)).allSatisfy({ h == 0 || abs(c[h - $0] + c[h + $0]) <= eps }) { return .antisymmetric }
        return .general
    }

    /// The order in which the general path accumulates the taps: tap 0 first, then the last tap down to tap 1.
    package static func interiorTapOrder(windowLength wl: Int) -> [Int] {
        [0] + Array((1..<wl).reversed())
    }

    /// In the symmetric and anti-symmetric paths SciPy's compiled loop is vectorised once it has 10 or more terms (h >= 10): the
    /// first (h / 8) * 8 terms of the descending sweep are computed as a product, rounded, and then added (NOT fused); the
    /// remaining terms are fused. Found by probing (a term whose exact product cancels the running sum shows fused or not), then
    /// verified bit for bit for h = 1 ... 40 on all three paths. The general path is always fused.
    package static func unfusedTerms(halfLength h: Int) -> Int { h >= 10 ? (h / 8) * 8 : 0 }

    /// `convolve1d(x, coeffs, mode="constant")` for the samples whose whole window lies inside `f` (`:385`):
    /// `out[i]` for `halflen <= i < n - halflen`. Other entries of `out` are not written.
    package static func convolveInterior(_ f: UnsafeBufferPointer<Double>, coefficients c: [Double],
                                         into out: UnsafeMutableBufferPointer<Double>) {
        let n = f.count, wl = c.count, h = wl / 2
        guard n >= wl else { return }
        let path = interiorPath(coefficients: c)
        let order = interiorTapOrder(windowLength: wl)
        let unfused = unfusedTerms(halfLength: h)
        c.withUnsafeBufferPointer { cp in
            order.withUnsafeBufferPointer { op in
                for i in h..<(n - h) {
                    switch path {
                    case .general:
                        var acc = f[i + h] * cp[0]            // a first product, not 0 + product: keeps the sign of an exact zero
                        for j in op.dropFirst() { acc = acc.addingProduct(f[i + h - j], cp[j]) }
                        out[i] = acc
                    case .antisymmetric:
                        var acc = f[i] * cp[h]
                        var k = h
                        while k >= 1 {
                            if h - k < unfused { let p = (f[i - k] - f[i + k]) * cp[h + k]; acc = acc + p }
                            else { acc = acc.addingProduct(f[i - k] - f[i + k], cp[h + k]) }
                            k -= 1
                        }
                        out[i] = acc
                    case .symmetric:
                        var acc = f[i] * cp[h]
                        var k = h
                        while k >= 1 {
                            if h - k < unfused { let p = (f[i - k] + f[i + k]) * cp[h + k]; acc = acc + p }
                            else { acc = acc.addingProduct(f[i - k] + f[i + k], cp[h + k]) }
                            k -= 1
                        }
                        out[i] = acc
                    }
                }
            }
        }
    }

    package static func validate(windowLength wl: Int, polynomialOrder po: Int) throws {
        guard wl >= 3 else { throw EELSThicknessError.invalidSavitzkyGolay("window_length \(wl) is below 3") }
        guard wl % 2 == 1 else {
            throw EELSThicknessError.invalidSavitzkyGolay("window_length \(wl) is even (exSpy: it must be an odd integer)")
        }
        guard po >= 1 else { throw EELSThicknessError.invalidSavitzkyGolay("polynomial_order \(po) is below 1") }
        guard po < wl else {
            throw EELSThicknessError.invalidSavitzkyGolay("polynomial_order \(po) must be less than window_length \(wl)")
        }
    }

}

/// Deterministic least-squares polynomial functional. Columns are ascending powers of x = (row - h) / h.
/// Two modified Gram-Schmidt sweeps retain orthogonality without a platform-dependent LAPACK implementation.
private nonisolated struct SavitzkyGolayQR: Sendable {
    let windowLength: Int
    let order: Int
    let q: [[Double]]
    let r: [[Double]]

    init(windowLength wl: Int, polynomialOrder po: Int) throws {
        let order = po + 1, h = wl / 2
        let x = (0..<wl).map { Double($0 - h) / Double(h) }
        var q = [[Double]]()
        var r = [[Double]](repeating: [Double](repeating: 0, count: order), count: order)
        for j in 0..<order {
            var v = [Double](repeating: 1, count: wl)
            for _ in 0..<j { for i in 0..<wl { v[i] = v[i] * x[i] } }
            for _ in 0..<2 {
                for k in 0..<j {
                    var dot = 0.0
                    for i in 0..<wl { let product = q[k][i] * v[i]; dot = dot + product }
                    r[k][j] = r[k][j] + dot
                    for i in 0..<wl { let product = q[k][i] * dot; v[i] = v[i] - product }
                }
            }
            var squaredNorm = 0.0
            for i in 0..<wl { let product = v[i] * v[i]; squaredNorm = squaredNorm + product }
            let norm = squaredNorm.squareRoot()
            guard norm.isFinite, norm > 0 else {
                throw EELSThicknessError.invalidSavitzkyGolay("scalar QR is rank deficient")
            }
            r[j][j] = norm
            q.append(v.map { $0 / norm })
        }
        self.windowLength = wl; self.order = order; self.q = q; self.r = r
    }

    /// Weights in ascending sample order for the derivative functional at one window position.
    func weights(position: Int, derivative: Int, delta: Double) -> [Double] {
        let h = windowLength / 2
        let t = Double(position - h) / Double(h)
        let step = Double(h) * delta
        var denominator = 1.0
        for _ in 0..<derivative { denominator = denominator * step }
        var y = [Double](repeating: 0, count: order)
        var power = 1.0
        for j in derivative..<order {
            var factor = 1.0
            for k in 0..<derivative { factor = factor * Double(j - k) }
            y[j] = (factor * power) / denominator
            power = power * t
        }
        // R^T z = y, then weights = Qz; all reductions have a specified scalar order.
        var z = [Double](repeating: 0, count: order)
        for j in 0..<order {
            var value = y[j]
            for k in 0..<j { let product = r[k][j] * z[k]; value = value - product }
            z[j] = value / r[j][j]
        }
        var weights = [Double](repeating: 0, count: windowLength)
        for i in 0..<windowLength {
            var value = 0.0
            for j in 0..<order { let product = q[j][i] * z[j]; value = value + product }
            weights[i] = value
        }
        return weights
    }
}

/// Scalar polynomial edge derivatives, independent of image shape and the number of right-hand sides.
/// This deliberately replaces SciPy's LAPACK edge rounding with the reproducible QR functional above.
package nonisolated struct SavitzkyGolayEdgeFit: Sendable {
    package let windowLength: Int
    package let polynomialOrder: Int
    package let delta: Double
    private let fit: SavitzkyGolayQR

    package init(windowLength wl: Int, polynomialOrder po: Int, delta: Double) throws {
        try SavitzkyGolay.validate(windowLength: wl, polynomialOrder: po)
        self.windowLength = wl; self.polynomialOrder = po; self.delta = delta
        self.fit = try SavitzkyGolayQR(windowLength: wl, polynomialOrder: po)
    }

    /// Derivatives at window positions `positions`, in `[pixel * positions.count + output]` order.
    /// The same weights and ascending fused dot product apply to each spectrum, including a spectrum processed alone.
    package func derivatives(window: (Int) -> UnsafeBufferPointer<Double>, nx: Int, ny: Int, positions: Range<Int>) -> [Double]? {
        let wl = windowLength, np = nx * ny, k = positions.count
        precondition(np > 0 && positions.lowerBound >= 0 && positions.upperBound <= wl)
        let weights = positions.map { fit.weights(position: $0, derivative: 1, delta: delta) }
        var out = [Double](repeating: 0, count: np * k)
        for p in 0..<np {
            let samples = window(p)
            for o in 0..<k {
                var value = 0.0
                for i in 0..<wl { value = value.addingProduct(samples[i], weights[o][i]) }
                out[p * k + o] = value
            }
        }
        return out
    }
}

/// The edge values of every pixel of an image: the first `halflen` and last `halflen` outputs of `savgol_filter`.
package nonisolated struct SavitzkyGolayEdgeTable: Sendable {
    package let halfLength: Int
    package let left: [Double]
    package let right: [Double]
}

/// The first derivative of the spectra of an image, `savgol_filter(data, wl, po, deriv=1, delta, mode="interp")` on the whole
/// data array along the last axis, as HyperSpy's `smooth_savitzky_golay` calls it.
package nonisolated struct SavitzkyGolayFirstDerivative: Sendable {
    package let windowLength: Int
    package let polynomialOrder: Int
    package let delta: Double
    package let coefficients: [Double]
    package let edges: SavitzkyGolayEdgeFit

    /// `coefficientsOverride` supplies the original SciPy coefficients for convolution-path regression tests.
    /// Edge fits retain the reproducible scalar backend even when the interior coefficients are overridden.
    package init(windowLength: Int, polynomialOrder: Int, delta: Double, coefficientsOverride: [Double]? = nil) throws {
        self.windowLength = windowLength; self.polynomialOrder = polynomialOrder; self.delta = delta
        if let o = coefficientsOverride, o.count != windowLength {
            throw EELSThicknessError.invalidSavitzkyGolay("coefficient override has \(o.count) values for a window of \(windowLength)")
        }
        self.coefficients = try coefficientsOverride ?? SavitzkyGolay.coefficients(
            windowLength: windowLength, polynomialOrder: polynomialOrder, derivative: 1, delta: delta)
        self.edges = try SavitzkyGolayEdgeFit(windowLength: windowLength, polynomialOrder: polynomialOrder, delta: delta)
    }

    /// The edge values of all `nx * ny` spectra (`row(p)` is pixel `p = y * nx + x`'s spectrum, all of one length `>= wl`;
    /// `mode="interp"` needs `window_length <= n`, `_savitzky_golay.py:378-381`). `_fit_edges_polyfit` (:244-258): the first `wl`
    /// samples give outputs 0 ..< halflen; the last `wl` samples give outputs n - halflen ..< n (window positions wl - halflen ..< wl).
    package func edgeTable(nx: Int, ny: Int, row: (Int) -> UnsafeBufferPointer<Double>) throws -> SavitzkyGolayEdgeTable {
        let wl = windowLength, h = wl / 2
        let n = row(0).count
        precondition(n >= wl, "savgol_filter: window_length must be <= the number of samples")
        guard let left = edges.derivatives(window: { p in UnsafeBufferPointer(rebasing: row(p)[0..<wl]) },
                                           nx: nx, ny: ny, positions: 0..<h),
              let right = edges.derivatives(window: { p in UnsafeBufferPointer(rebasing: row(p)[(n - wl)..<n]) },
                                            nx: nx, ny: ny, positions: (wl - h)..<wl) else {
            throw EELSThicknessError.invalidSavitzkyGolay("least squares failed")
        }
        return SavitzkyGolayEdgeTable(halfLength: h, left: left, right: right)
    }

    /// One spectrum of the image whose edge table is `table`: interior by `convolve1d`, edges from the table.
    package func apply(_ f: UnsafeBufferPointer<Double>, into out: UnsafeMutableBufferPointer<Double>,
                       pixel p: Int, table: SavitzkyGolayEdgeTable) {
        let n = f.count, h = windowLength / 2
        precondition(n >= windowLength && out.count == n, "savgol_filter: window_length must be <= the number of samples")
        SavitzkyGolay.convolveInterior(f, coefficients: coefficients, into: out)
        for o in 0..<h {
            out[o] = table.left[p * h + o]
            out[n - h + o] = table.right[p * h + o]
        }
    }

    /// A single spectrum on its own (an image of one pixel: a 1-D `savgol_filter` call).
    package func apply(_ f: UnsafeBufferPointer<Double>, into out: UnsafeMutableBufferPointer<Double>) {
        guard let table = try? edgeTable(nx: 1, ny: 1, row: { _ in f }) else { preconditionFailure("scalar edge fit failed on a finite window") }
        apply(f, into: out, pixel: 0, table: table)
    }
}
