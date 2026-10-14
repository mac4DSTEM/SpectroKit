//
//  ScipySimpson.swift
//  Role: SciPy 1.18.1's `scipy.integrate.simpson(y, x=x)` for one vector on a non-uniform grid (`integrate/_quadrature.py:
//        358-388` `_basic_simpson`, `:392-527` `simpson`), which exSpy's GOS integration over ln((a0 q)^2) calls
//        (`exspy/_misc/eels/base_gos.py`, `integrateq`). EELS slice 2 (docs/eels-slice-2-registration.md, section 3.3).
//
//  An odd number of points: the composite rule over pairs of intervals. An even number: the composite rule over the first
//  N - 3 points and Cartwright's correction for the last interval (`:486-524`); two points: the trapezoid. The per-pair
//  terms are formed in NumPy's order and summed by NumPy's pairwise sum (`xp.sum` over a contiguous temporary).
//

import Foundation

package nonisolated enum ScipySimpson {

    /// `simpson(y, x=x)`; `y.count == x.count`, at least 2 points (SciPy integrates 1 point to 0, never needed here).
    package static func integrate(_ y: [Double], x: [Double]) -> Double {
        let n = y.count
        precondition(n == x.count && n >= 2)
        if n == 2 { return 0.0 + 0.5 * (x[1] - x[0]) * (y[1] + y[0]) }
        if n % 2 == 1 { return basic(y, x: x, stop: n - 2) }
        var result = basic(y, x: x, stop: n - 3)
        let h0 = x[n - 2] - x[n - 3], h1 = x[n - 1] - x[n - 2]
        let aDen = 6 * (h1 + h0), bDen = 6 * h0, eDen = 6 * h0 * (h0 + h1)
        let alpha = aDen != 0 ? (2 * (h1 * h1) + 3 * h0 * h1) / aDen : 0   // h are 0-d arrays: ** 2 squares
        let beta = bDen != 0 ? (h1 * h1 + 3.0 * h0 * h1) / bDen : 0
        let eta = eDen != 0 ? (1 * Libm.pow(h1, 3)) / eDen : 0
        result += alpha * y[n - 1] + beta * y[n - 2] - eta * y[n - 3]
        return result + 0.0
    }

    /// `_basic_simpson(y, 0, stop, x, ...)`: the pairs starting at 0, 2, ... below `stop`.
    private static func basic(_ y: [Double], x: [Double], stop: Int) -> Double {
        var tmp = [Double]()
        tmp.reserveCapacity(stop / 2 + 1)
        var i = 0
        while i < stop {
            let h0 = x[i + 1] - x[i], h1 = x[i + 2] - x[i + 1]
            let hsum = h0 + h1, hprod = h0 * h1
            let h0divh1 = h1 != 0 ? h0 / h1 : 0
            let inv = h0divh1 != 0 ? 1.0 / h0divh1 : 0
            let sOverP = hprod != 0 ? hsum / hprod : 0
            let a = y[i] * (2.0 - inv)
            let b = y[i + 1] * (hsum * sOverP)
            let c = y[i + 2] * (2.0 - h0divh1)
            tmp.append(hsum / 6.0 * (a + b + c))
            i += 2
        }
        return NumpySum.sum(tmp)
    }
}
