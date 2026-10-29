//
//  InterpolatingSpline.swift
//  Role: SciPy 1.18.1's `make_interp_spline(x, y, k=3)` with its default not-a-knot condition, and the resulting
//        `BSpline`'s evaluation with `extrapolate=True`, which exSpy uses for the energy-differential cross section between
//        the tabulated GOS energies (`base_gos.py`, end of `integrateq`).
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

    /// All zeros of the spline inside [x[0], x[n-1]], increasing (FITPACK `sproot` on a cubic: the roots of each knot interval's polynomial,
    /// those shared by two intervals once). Each interval's cubic is rebuilt from four evaluations, split at its critical points and bisected,
    /// so a pair of roots inside one interval is found as well as a single crossing. A tangent touch (double root) is not a crossing and is missed.
    package func roots() -> [Double] {
        let k = Self.degree, nt = coefficients.count
        var found = [Double]()
        for l in k ..< nt where knots[l + 1] > knots[l] {
            let a = knots[l], h = knots[l + 1] - a
            func value(_ u: Double) -> Double {
                let hh = Self.basis(knots, k: k, x: a + u * h, interval: l)
                var sum = 0.0
                for i in 0 ... k { sum += coefficients[l - k + i] * hh[i] }
                return sum
            }
            // The two knot values are computed once per knot (`self(x)`), so the neighbouring intervals see the same number and a root
            // sitting on a knot cannot fall between two rounding errors.
            let f0 = self(a), f1 = value(1.0 / 3), f2 = value(2.0 / 3), f3 = self(knots[l + 1])
            let c1 = (-11 * f0 + 18 * f1 - 9 * f2 + 2 * f3) / 2
            let c2 = (18 * f0 - 45 * f1 + 36 * f2 - 9 * f3) / 2
            let c3 = (-9 * f0 + 27 * f1 - 27 * f2 + 9 * f3) / 2
            func p(_ u: Double) -> Double { f0 + u * (c1 + u * (c2 + u * c3)) }
            var cuts = [0.0]
            let qa = 3 * c3, qb = 2 * c2, qc = c1
            if qa != 0 {
                let disc = qb * qb - 4 * qa * qc
                if disc > 0 {
                    let r = disc.squareRoot()
                    for u in [(-qb - r) / (2 * qa), (-qb + r) / (2 * qa)].sorted() where u > 0 && u < 1 { cuts.append(u) }
                }
            } else if qb != 0 {
                let u = -qc / qb
                if u > 0 && u < 1 { cuts.append(u) }
            }
            cuts.append(1)
            for i in 0 ..< cuts.count - 1 {
                var lo = cuts[i], hi = cuts[i + 1]
                var plo = i == 0 ? f0 : p(lo), phi = i == cuts.count - 2 ? f3 : p(hi)
                if plo == 0 { found.append(a + lo * h); continue }
                if phi == 0 { found.append(a + hi * h); continue }
                guard (plo < 0) != (phi < 0) else { continue }
                for _ in 0 ..< 200 {
                    let mid = 0.5 * (lo + hi)
                    if mid == lo || mid == hi { break }
                    let pm = p(mid)
                    if pm == 0 { lo = mid; hi = mid; break }
                    if (pm < 0) == (plo < 0) { lo = mid; plo = pm } else { hi = mid; phi = pm }
                }
                found.append(a + 0.5 * (lo + hi) * h)
            }
        }
        found.sort()
        var unique = [Double]()
        let span = knots[nt] - knots[0]
        for r in found where unique.last.map({ r - $0 > 1e-12 * span }) ?? true { unique.append(r) }
        return unique
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
