//
//  SavitzkyGolay.swift
//  Role: The first derivative of a spectrum as SciPy 1.18.1's `savgol_filter(x, window_length, polyorder, deriv=1,
//        delta=scale)` computes it with its default `mode="interp"`, which is how HyperSpy 2.4.0
//        `smooth_savitzky_golay(differential_order=1)` calls it (`_signals/signal1d.py:933-941`, one spectrum at a time) and so
//        how exSpy's `estimate_elastic_scattering_threshold` finds the threshold (`exspy/signals/_eels.py:716-721`).
//
//  BIT FOR BIT the same as SciPy 1.18.1 / NumPy 2.5.4 on this machine (Apple Silicon, Accelerate LAPACK), for every odd
//  window_length >= 3 and 1 <= polyorder < window_length and every delta: tests compare the bit patterns against
//  SciPy's own output on whole images (Tests/SpectroEELSTests/SavitzkyGolayBitParityTests.swift; the fixture's generator is
//  tools/eels-thickness/make_sg_parity.py). Three parts, each SciPy's own:
//   * the coefficients, `savgol_coeffs` (`scipy/signal/_savitzky_golay.py:11-160`): `scipy.linalg.lstsq(A, y, cond=eps)`, whose
//     default driver is LAPACK `dgelsd` (the SVD; SpectroCore's `FitLinearAlgebra.leastSquaresSVD`), A the Vandermonde matrix of
//     the window positions, y[deriv] = deriv! / delta^deriv. (`dgelsy`, the other solver in SpectroCore, differs from `dgelsd` at
//     1.3e-15 and flipped tie channels; it is not used here.)
//   * the interior, `convolve1d(x, coeffs, mode="constant")` (`:385`), for the samples with a whole window. SciPy's compiled
//     `correlate1d` looks at the weights first (`NI_Correlate1D`): if every pair c[h - k], c[h + k] differs by at most DBL_EPSILON
//     the filter is "symmetric", else if every pair's SUM is at most DBL_EPSILON it is "anti-symmetric" (what a first-derivative
//     filter nearly always is), else general. The accumulation, found by search against SciPy's output and verified bit for
//     bit on every window (not read from the C source, which is not in the wheel), with fused multiply-adds:
//       general:        acc = x[i + h] * c[0]; for j in (wl-1, wl-2, ..., 1): acc = fma(x[i + h - j], c[j], acc)
//       anti-symmetric: acc = x[i] * c[h]; for k = h down to 1: acc = fma(x[i - k] - x[i + k], c[h + k], acc)
//       symmetric:      acc = x[i] * c[h]; for k = h down to 1: acc = fma(x[i - k] + x[i + k], c[h + k], acc)
//     (h = wl // 2), except that from h = 10 the compiled loop is vectorised and its first (h / 8) * 8 terms are NOT fused
//     (product rounded, then added; `unfusedTerms`). Which of the three applies depends on the coefficients, i.e. on delta and the window, so all three are here.
//   * the two edges, `_fit_edges_polyfit` / `_fit_edge` (`:189-258`): for the first and last `h` samples, a degree-`polyorder`
//     polynomial is fitted to the first (last) `wl` samples by `_polyutils.polyfit` (the Vandermonde matrix of 0..wl-1, columns
//     divided by the square root of their sum of squares, solved by `dgelsd` with rcond = wl * eps, the
//     coefficients divided by the scale), differentiated (`_polyder`: coefficient * power) and evaluated by Horner's rule
//     with separate multiply and add (`polyval`), divided by delta. All the pixels' windows go into ONE `dgelsd` call, as in SciPy
//     (see `SavitzkyGolayEdgeFit.derivatives`: the bits depend on the number of right-hand sides, so this is an image-level
//     operation and a pixel's threshold depends on the image's size; the fit is linear in the data only mathematically).
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
        let halflen = wl / 2
        let pos = Double(halflen)
        // x = arange(-pos, window_length - pos), flipped for "conv" (:140-144); A = x ** order, order = arange(polyorder + 1)
        // as a column (:146-149): A is (polyorder + 1) x wl, row r = x ** r.
        var a = ColumnMatrix(rows: po + 1, cols: wl)
        for col in 0..<wl {
            let x = pos - Double(col)                       // flip(arange(-pos, wl - pos))[col]
            for r in 0...po { a[r, col] = Libm.pow(x, Double(r)) }
        }
        // y = zeros(polyorder + 1); y[deriv] = factorial(deriv) / delta ** deriv (:152-155).
        var y = [Double](repeating: 0, count: po + 1)
        y[deriv] = factorial(deriv) / Libm.pow(delta, Double(deriv))
        // `_lstsq(A, y)`: scipy.linalg.lstsq(A, y, cond=eps) (`_polyutils.py:79-86`), default driver gelsd; minimum norm for the
        // wl > polyorder + 1 unknowns.
        guard let solved = FitLinearAlgebra.leastSquaresSVD(a, ColumnMatrix(rows: po + 1, cols: 1, data: y),
                                                            rcond: Double.ulpOfOne) else {
            throw EELSThicknessError.invalidSavitzkyGolay("least squares failed")
        }
        return Array(solved.x.data)
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

    private static func factorial(_ n: Int) -> Double {
        // scipy `float_factorial` (`_lib/_util.py:105-110`): float(math.factorial(n)).
        var f = 1.0
        if n >= 2 { for k in 2...n { f *= Double(k) } }
        return f
    }
}

/// `_polyutils.polyfit` of the window positions 0 ..< wl, as `_fit_edge` calls it, with its derivative evaluated: the left or
/// right edge values of ONE spectrum. The scaled Vandermonde matrix is the same for every window and made once.
package nonisolated struct SavitzkyGolayEdgeFit: Sendable {
    package let windowLength: Int
    package let polynomialOrder: Int
    package let delta: Double
    private let scale: [Double]
    private let base: SVDLeastSquaresProblem

    package init(windowLength wl: Int, polynomialOrder po: Int, delta: Double) throws {
        try SavitzkyGolay.validate(windowLength: wl, polynomialOrder: po)
        self.windowLength = wl; self.polynomialOrder = po; self.delta = delta
        let order = po + 1
        // x = arange(wl); powers = flip(arange(order)); lhs = x[:, None] ** powers[None, :];
        // scale = sqrt(sum(lhs * lhs, axis=0)); lhs /= scale  (`_polyutils.py:182-221`).
        var lhs = ColumnMatrix(rows: wl, cols: order)
        for r in 0..<wl { for c in 0..<order { lhs[r, c] = Libm.pow(Double(r), Double(po - c)) } }
        var scale = [Double](repeating: 0, count: order)
        for c in 0..<order {
            var s = 0.0                                      // an axis-0 reduction of a 2-D array: sequential adds
            for r in 0..<wl { s += lhs[r, c] * lhs[r, c] }
            scale[c] = s.squareRoot()
        }
        for c in 0..<order { for r in 0..<wl { lhs[r, c] /= scale[c] } }
        self.scale = scale
        guard let base = SVDLeastSquaresProblem(lhs, rhsCount: 1, rcond: Double(wl) * Double.ulpOfOne) else {
            throw EELSThicknessError.invalidSavitzkyGolay("least squares failed")
        }
        self.base = base
    }

    /// The derivative at window positions `positions` (within 0 ..< wl) of the polynomial fitted to each pixel's window, for a
    /// whole image at once: `_fit_edge`'s polyfit -> `_polyder` -> `polyval` -> `/ delta`. Result `[p * positions.count + o]`.
    ///
    /// ALL THE PIXELS ARE ONE LEAST-SQUARES CALL, as in SciPy: HyperSpy applies `savgol_filter` to the whole data array (`_map_all`,
    /// `hyperspy/signal.py:5674`), `_fit_edge` reshapes the edge to (wl, number of spectra) and `lstsq` solves with that many
    /// right-hand sides. `dgelsd`'s bits depend on the number of right-hand sides (below about 512 and, near it, on the window),
    /// so one pixel solved alone is NOT the same bits (measured: 1.8 % of rows differ). The column order does not matter (SciPy's is
    /// x * ny + y for 3-D data; a mutant with the pixel order gave the same 32.5 million values), only the count. Above 131072
    /// pixels the call is split into blocks of 65536 columns (a short tail joins the last block): with 512 or more right-hand
    /// sides the bits do not depend on the count (measured: 300000 spectra, blocks of 512 ... 100000, 0 rows differ from the
    /// single call).
    /// nil if LAPACK fails.
    package func derivatives(window: (Int) -> UnsafeBufferPointer<Double>, nx: Int, ny: Int, positions: Range<Int>) -> [Double]? {
        let wl = windowLength, order = polynomialOrder + 1, np = nx * ny, k = positions.count
        precondition(np > 0 && positions.upperBound <= wl)
        var out = [Double](repeating: 0, count: np * k)
        let maxSingle = 131072, block = 65536
        var start = 0
        while start < np {
            var end = np
            if np > maxSingle {
                end = min(start + block, np)
                if np - end < 4096 { end = np }
            }
            let nrhs = end - start
            guard let problem = SVDLeastSquaresProblem(base.a, rhsCount: nrhs, rcond: base.rcond) else { return nil }
            var b = [Double](repeating: 0, count: wl * nrhs)
            for c in start..<end {
                let p = c
                let w = window(p)
                for r in 0..<wl { b[(c - start) * wl + r] = w[r] }
            }
            guard let solved = problem.solve(b) else { return nil }
            var dp = [Double](repeating: 0, count: order - 1)
            for c in start..<end {
                let p = c
                // c = (c.T / scale).T; _polyder(c, 1): dp = c[:-1] * [order-1, ..., 1]  (`_savitzky_golay.py:172-185`).
                for m in 0..<(order - 1) {
                    let coefficient = solved.x[(c - start) * order + m] / scale[m]
                    dp[m] = coefficient * Double(order - 1 - m)
                }
                // polyval (`_polyutils.py:134-135`): y = zeros; for j: y = y * x + p[j] - a separate multiply and add, as NumPy does.
                for (o, i) in positions.enumerated() {
                    let x = Double(i)
                    var v = 0.0
                    for j in 0..<dp.count { let prod = v * x; v = prod + dp[j] }
                    out[p * k + o] = v / delta
                }
            }
            start = end
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

    /// `coefficientsOverride` replaces the least-squares coefficients (it exists so the tests can run the whole pipeline on
    /// SciPy's own five numbers, recorded in pins.json, and show it reproduces SciPy's derivatives bit for bit).
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
        guard let table = try? edgeTable(nx: 1, ny: 1, row: { _ in f }) else { preconditionFailure("dgelsd failed on a finite window") }
        apply(f, into: out, pixel: 0, table: table)
    }
}
