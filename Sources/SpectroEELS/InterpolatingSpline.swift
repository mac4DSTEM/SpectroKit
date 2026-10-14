//
//  InterpolatingSpline.swift
//  Role: SciPy 1.18.1's `make_interp_spline(x, y, k=3)` with its default not-a-knot condition, and the resulting
//        `BSpline`'s evaluation with `extrapolate=True`, which exSpy uses for the energy-differential cross section between
//        the tabulated GOS energies (`base_gos.py`, end of `integrateq`). EELS slice 2, registration section 3.3.
//
//  Knots (`interpolate/_bsplines.py:1278-1297`, `_not_a_knot`, odd k): x[0] four times, x[2 ..< n-2], x[n-1] four times.
//  The collocation matrix (`_dierckx._coloc`): row j holds the k+1 non-zero B-splines at x[j] in the knot interval l
//  with t[l] <= x[j] < t[l+1] (the last data point in the last non-empty interval), by de Boor's recursion; it is solved in
//  LAPACK band storage by `dgbsv_` with kl = ku = k (`:1876-1909`), SpectroCore's `BandedLinearAlgebra`. Evaluation
//  (`_bspl.evaluate_spline`): the interval of x (extrapolating with the end intervals), the same recursion, sum of c * B.
//

import Foundation
import SpectroCore

package nonisolated struct InterpolatingSpline: Sendable {
    package static let degree = 3
    package let knots: [Double]
    package let coefficients: [Double]

    /// nil when the collocation system is singular (SciPy raises `LinAlgError`) or x is not strictly increasing.
    package init?(x: [Double], y: [Double]) {
        let k = Self.degree, n = x.count
        guard n == y.count, n >= k + 1, zip(x, x.dropFirst()).allSatisfy({ $0 < $1 }) else { return nil }
        var t = [Double](repeating: x[0], count: k + 1)
        t += x[2 ..< (n - 2)]
        t += [Double](repeating: x[n - 1], count: k + 1)
        let nt = t.count - k - 1                  // == n
        let kl = k, ku = k, ldab = 2 * kl + ku + 1
        var ab = [Double](repeating: 0, count: ldab * nt)
        for j in 0 ..< n {
            let l = Self.interval(t, k: k, x: x[j], coefficientCount: nt)
            let h = Self.basis(t, k: k, x: x[j], interval: l)
            for a in 0 ... k {
                let col = l - k + a
                ab[col * ldab + kl + ku + j - col] = h[a]
            }
        }
        guard let c = BandedLinearAlgebra.solve(n: nt, kl: kl, ku: ku, ab: ab, b: y) else { return nil }
        knots = t; coefficients = c
    }

    /// The spline's value at `x` (SciPy `BSpline.__call__`, `extrapolate=True`).
    package func callAsFunction(_ x: Double) -> Double {
        let k = Self.degree
        let l = Self.interval(knots, k: k, x: x, coefficientCount: coefficients.count)
        let h = Self.basis(knots, k: k, x: x, interval: l)
        var s = 0.0
        for a in 0 ... k { s += coefficients[l - k + a] * h[a] }
        return s
    }

    /// `_find_interval` (scipy `_bspl.pyx` / `__fitpack.h`) with extrapolation: l in [k, n-1] with t[l] <= x < t[l+1];
    /// x below t[k] gives k, x at or above t[n] gives n - 1.
    private static func interval(_ t: [Double], k: Int, x: Double, coefficientCount n: Int) -> Int {
        if x < t[k] { return k }
        if x >= t[n] { return n - 1 }
        var l = k
        while l < n - 1 && x >= t[l + 1] { l += 1 }
        return l
    }

    /// The k+1 B-splines non-zero on interval l at x (`_deBoor_D` with m = 0, fitpack's `fpbspl`).
    private static func basis(_ t: [Double], k: Int, x: Double, interval l: Int) -> [Double] {
        var h = [Double](repeating: 0, count: k + 1)
        var hh = [Double](repeating: 0, count: k + 1)
        h[0] = 1.0
        for j in 1 ... k {
            for i in 0 ..< j { hh[i] = h[i] }
            h[0] = 0.0
            for n in 1 ... j {
                let ind = l + n
                let xb = t[ind], xa = t[ind - j]
                if xb == xa { h[n] = 0.0; continue }
                let w = hh[n - 1] / (xb - xa)
                h[n - 1] += w * (xb - x)
                h[n] = w * (x - xa)
            }
        }
        return h
    }
}
