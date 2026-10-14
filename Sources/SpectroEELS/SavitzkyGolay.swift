//
//  SavitzkyGolay.swift
//  Role: The first derivative of a spectrum as SciPy 1.18.1's `savgol_filter(x, window_length, polyorder, deriv=1,
//        delta=scale)` computes it with its default `mode="interp"`, which is how HyperSpy 2.4.0
//        `smooth_savitzky_golay(differential_order=1)` calls it (`_signals/signal1d.py:933-941`) and so how exSpy's
//        `estimate_elastic_scattering_threshold` finds the threshold (`exspy/signals/_eels.py:716-721`).
//
//  Three parts, each SciPy's own:
//   * the coefficients, `savgol_coeffs` (`scipy/signal/_savitzky_golay.py:11-160`): the least-squares (minimum-norm)
//     solution of A c = y, A the Vandermonde matrix of the window positions, y[deriv] = deriv! / delta^deriv;
//   * the interior, `convolve1d(x, coeffs, mode="constant")` (`:385`), for the samples with a whole window: the sum
//     is accumulated with fused multiply-adds in the order the README's recipe records (tools/eels-thickness/README.md,
//     "Savitzky-Golay"): acc = 0; for j in (0, wl-1, wl-2, ..., 1): acc = fma(f[i + halflen - j], c[j], acc);
//   * the two edges, `_fit_edges_polyfit` / `_fit_edge` (`:189-258`): for the first and last `halflen` samples, a degree-
//     `polyorder` polynomial is fitted to the first (last) `wl` samples (`polyfit`, `_polyutils.py:182-221`, a column-scaled
//     Vandermonde solved by least squares), differentiated (`_polyder`, `:163-186`) and evaluated (`polyval`,
//     `_polyutils.py:125-136`, Horner) at the sample's position, divided by delta^deriv (`:226`).
//
//  What is the same as SciPy bit for bit and what is not: the FMA order is SciPy's on this machine (the pinned interior
//  values are reproduced bit for bit when SciPy's own five coefficients are used, tested). SciPy solves the two least-squares
//  problems with LAPACK's `dgelsd`; SpectroCore's `FitLinearAlgebra` has `dgelsy`, a different algorithm, so the
//  coefficients agree with SciPy's to about 1e-15 relative to the largest (not bit for bit: SciPy's centre coefficient is
//  -8.3e-15, not 0) and the derivative of the pinned rows differs from SciPy's by at most 8e-12 absolute (5e-14 relative).
//  That never moves a threshold except at a TIE pixel (a channel whose |derivative| equals `tol` to rounding, registration
//  section 9 item 2): on the registered noisy image 3 of its 7 tie pixels pick another tie channel than exSpy. Measured in a
//  scratch copy, not made here (it edits SpectroCore): a `dgelsd` wrapper next to `sk_dgelsy` in CSpectroLAPACK, called for these
//  two problems, gives SciPy's five coefficients bit for bit and exSpy's channel at all 7 tie pixels.
//
//  Restrictions against SciPy, all refused with an error: an even window (SciPy computes it with a half-integer
//  position; exSpy's docstring says odd), a window below 3, a polynomial order below 1 (SciPy returns zeros), a polynomial
//  order of `windowLength` or more (SciPy raises).
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
        let halflen = wl / 2
        let pos = Double(halflen)
        // x = arange(-pos, window_length - pos), flipped for "conv" (:140-144); A = x ** order, order = arange(polyorder + 1)
        // as a column (:146-149): A is (polyorder + 1) x wl, row r = x ** r.
        var a = ColumnMatrix(rows: po + 1, cols: wl)
        for col in 0..<wl {
            let x = pos - Double(col)                       // flip(arange(-pos, wl - pos))[col]
            for r in 0...po { a[r, col] = pow(x, Double(r)) }
        }
        // y = zeros(polyorder + 1); y[deriv] = factorial(deriv) / delta ** deriv (:152-155).
        var y = [Double](repeating: 0, count: po + 1)
        y[deriv] = factorial(deriv) / pow(delta, Double(deriv))
        // `_lstsq(A, y)`: scipy.linalg.lstsq(A, y, cond=eps) (`_polyutils.py:79-86`), minimum norm for the wl > polyorder + 1 unknowns.
        guard let solved = FitLinearAlgebra.leastSquares(a, ColumnMatrix(rows: po + 1, cols: 1, data: y),
                                                         rcond: Double.ulpOfOne) else {
            throw EELSThicknessError.invalidSavitzkyGolay("least squares failed")
        }
        return Array(solved.x.data)
    }

    /// Weights `W[position][k]` such that the edge derivative at window position `position` (0 ..< wl) is
    /// `sum_k W[position][k] * window[k]`: `_fit_edge`'s polyfit -> `_polyder` -> `polyval` -> `/ delta^deriv`
    /// (`_savitzky_golay.py:189-240`) applied to each of the `wl` unit vectors. `polyfit` is linear in its data, so this
    /// is the same map SciPy applies to a window, solved once instead of once per row (differs at rounding level only).
    /// The left edge uses positions `0 ..< halflen` of the first `wl` samples; the right edge positions `wl - halflen ..< wl`
    /// of the last `wl` samples (`_fit_edges_polyfit`, `:244-258`).
    package static func edgeWeights(windowLength wl: Int, polynomialOrder po: Int, delta: Double) throws -> [[Double]] {
        try validate(windowLength: wl, polynomialOrder: po)
        let order = po + 1
        // polyfit (`_polyutils.py:182-221`): x = arange(wl); powers = flip(arange(order)); lhs = x[:, None] ** powers[None, :];
        // scale = sqrt(sum(lhs * lhs, axis=0)); lhs /= scale; c = lstsq(lhs, y, cond=wl * eps); c = c.T / scale.
        var lhs = ColumnMatrix(rows: wl, cols: order)
        for r in 0..<wl {
            for c in 0..<order { lhs[r, c] = pow(Double(r), Double(po - c)) }
        }
        var scale = [Double](repeating: 0, count: order)
        for c in 0..<order {
            var s = 0.0                                      // axis-0 reduction of a 2-D array: sequential adds
            for r in 0..<wl { s += lhs[r, c] * lhs[r, c] }
            scale[c] = s.squareRoot()
        }
        for c in 0..<order { for r in 0..<wl { lhs[r, c] /= scale[c] } }
        var identity = ColumnMatrix(rows: wl, cols: wl)
        for k in 0..<wl { identity[k, k] = 1 }
        guard let solved = FitLinearAlgebra.leastSquares(lhs, identity, rcond: Double(wl) * Double.ulpOfOne) else {
            throw EELSThicknessError.invalidSavitzkyGolay("least squares failed")
        }
        // coefficient m (highest power first) of the fit to unit vector k: solved.x[m, k] / scale[m].
        // _polyder(p, 1): dp = p[:-1] * [order-1, ..., 1] (:172-185); polyval(dp, i) Horner (_polyutils.py:134-135); / delta ** 1.
        let deltaPow = pow(delta, 1.0)
        var weights = [[Double]](repeating: [Double](repeating: 0, count: wl), count: wl)
        for k in 0..<wl {
            var dp = [Double](repeating: 0, count: order - 1)
            for m in 0..<(order - 1) {
                let coefficient = solved.x[m, k] / scale[m]
                dp[m] = coefficient * Double(order - 1 - m)
            }
            for i in 0..<wl {
                var v = 0.0
                for j in 0..<dp.count { let prod = v * Double(i); v = prod + dp[j] }
                weights[i][k] = v / deltaPow
            }
        }
        return weights
    }

    /// The order in which the interior sum is accumulated: tap 0 first, then the last tap down to tap 1 (the README's recipe
    /// (0, 4, 3, 2, 1) for the registered window of 5; for other windows this is the same pattern, not pinned).
    package static func interiorTapOrder(windowLength wl: Int) -> [Int] {
        [0] + Array((1..<wl).reversed())
    }

    /// `convolve1d(x, coeffs, mode="constant")` for the samples whose whole window lies inside `f` (`:385`):
    /// `out[i]` for `halflen <= i < n - halflen`, accumulated as `acc = fma(f[i + halflen - j], coeffs[j], acc)` over `j` in
    /// `interiorTapOrder`. Other entries of `out` are not written.
    package static func convolveInterior(_ f: UnsafeBufferPointer<Double>, coefficients c: [Double],
                                         into out: UnsafeMutableBufferPointer<Double>) {
        let n = f.count, wl = c.count, halflen = wl / 2
        let order = interiorTapOrder(windowLength: wl)
        guard n >= wl else { return }
        c.withUnsafeBufferPointer { cp in
            order.withUnsafeBufferPointer { op in
                for i in halflen..<(n - halflen) {
                    var acc = 0.0
                    for j in op { acc = acc.addingProduct(f[i + halflen - j], cp[j]) }
                    out[i] = acc
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

    private static func factorial(_ n: Int) -> Double {
        // scipy `float_factorial` (`_lib/_util.py:105-110`): float(math.factorial(n)).
        var f = 1.0
        if n >= 2 { for k in 2...n { f *= Double(k) } }
        return f
    }
}

/// The first derivative of one spectrum, `savgol_filter(row, wl, po, deriv=1, delta, mode="interp")`.
package nonisolated struct SavitzkyGolayFirstDerivative: Sendable {
    package let windowLength: Int
    package let polynomialOrder: Int
    package let delta: Double
    package let coefficients: [Double]
    package let edgeWeights: [[Double]]

    /// `coefficientsOverride` replaces the least-squares coefficients (it exists so the tests can run the whole pipeline on
    /// SciPy's own five numbers, recorded in pins.json, and show it reproduces SciPy's derivatives bit for bit).
    package init(windowLength: Int, polynomialOrder: Int, delta: Double, coefficientsOverride: [Double]? = nil) throws {
        self.windowLength = windowLength; self.polynomialOrder = polynomialOrder; self.delta = delta
        if let o = coefficientsOverride, o.count != windowLength {
            throw EELSThicknessError.invalidSavitzkyGolay("coefficient override has \(o.count) values for a window of \(windowLength)")
        }
        self.coefficients = try coefficientsOverride ?? SavitzkyGolay.coefficients(
            windowLength: windowLength, polynomialOrder: polynomialOrder, derivative: 1, delta: delta)
        self.edgeWeights = try SavitzkyGolay.edgeWeights(windowLength: windowLength, polynomialOrder: polynomialOrder, delta: delta)
    }

    /// `mode="interp"` needs `window_length <= n` (`_savitzky_golay.py:378-381`, a `ValueError` in SciPy).
    package func apply(_ f: UnsafeBufferPointer<Double>, into out: UnsafeMutableBufferPointer<Double>) {
        let n = f.count, wl = windowLength, halflen = wl / 2
        precondition(n >= wl && out.count == n, "savgol_filter: window_length must be <= the number of samples")
        SavitzkyGolay.convolveInterior(f, coefficients: coefficients, into: out)
        for i in 0..<halflen {
            var left = 0.0, right = 0.0
            let wLeft = edgeWeights[i], wRight = edgeWeights[wl - halflen + i]
            for k in 0..<wl {
                let pl = wLeft[k] * f[k]; left += pl
                let pr = wRight[k] * f[n - wl + k]; right += pr
            }
            out[i] = left
            out[n - halflen + i] = right
        }
    }
}
