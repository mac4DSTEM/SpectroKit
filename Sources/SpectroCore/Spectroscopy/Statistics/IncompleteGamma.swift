//
//  IncompleteGamma.swift
//  Role: The regularized incomplete gamma function P(a, x) and its inverse in x
//        (the gamma quantile). Accelerate has no chi-square / gamma inverse, and
//        the Garwood intervals of `CountingInterval` are exactly gamma quantiles
//        (chi2(p; k) / 2 = gammaQuantile(p, shape k/2)).
//
//  P(a, x) by the power series for x < a + 1 and by the modified-Lentz continued
//  fraction for Q = 1 - P otherwise (Numerical Recipes 6.2, re-derived, not
//  copied). The inverse is a bracketed Newton iteration that falls back to
//  bisection whenever a step leaves the bracket, so it cannot diverge.
//  Tolerances are stated at the call sites below and measured in the tests
//  (against scipy.stats.gamma.ppf, values quoted there).
//

import Foundation

package nonisolated enum IncompleteGamma {

    /// Series / continued-fraction convergence tolerance (relative).
    package static let seriesTolerance = 1e-15
    /// The quantile stops when the bracket is narrower than this relative width,
    /// or |P(a, x) - p| < `quantileResidual`.
    package static let quantileRelativeWidth = 1e-14
    package static let quantileResidual = 1e-15
    package static let maximumIterations = 500

    /// Regularized lower incomplete gamma P(a, x), a > 0, x >= 0.
    package static func lowerRegularized(a: Double, x: Double) -> Double {
        precondition(a > 0 && x >= 0, "IncompleteGamma needs a > 0, x >= 0")
        if x == 0 { return 0 }
        if x < a + 1 { return series(a: a, x: x) }
        return 1 - continuedFraction(a: a, x: x)
    }

    /// Regularized upper incomplete gamma Q(a, x) = 1 - P(a, x), computed without
    /// cancellation in the upper tail.
    package static func upperRegularized(a: Double, x: Double) -> Double {
        precondition(a > 0 && x >= 0, "IncompleteGamma needs a > 0, x >= 0")
        if x == 0 { return 1 }
        if x < a + 1 { return 1 - series(a: a, x: x) }
        return continuedFraction(a: a, x: x)
    }

    private static func logPrefactor(a: Double, x: Double) -> Double {
        -x + a * log(x) - lgamma(a)
    }

    private static func series(a: Double, x: Double) -> Double {
        var term = 1 / a
        var sum = term
        var n = a
        for _ in 0..<maximumIterations {
            n += 1
            term *= x / n
            sum += term
            if abs(term) < abs(sum) * seriesTolerance { break }
        }
        return sum * exp(logPrefactor(a: a, x: x))
    }

    /// Q(a, x) for x >= a + 1 (modified Lentz).
    private static func continuedFraction(a: Double, x: Double) -> Double {
        let tiny = 1e-300
        var b = x + 1 - a
        var c = 1 / tiny
        var d = 1 / b
        var h = d
        for i in 1...maximumIterations {
            let an = -Double(i) * (Double(i) - a)
            b += 2
            d = an * d + b
            if abs(d) < tiny { d = tiny }
            c = b + an / c
            if abs(c) < tiny { c = tiny }
            d = 1 / d
            let delta = d * c
            h *= delta
            if abs(delta - 1) < seriesTolerance { break }
        }
        return exp(logPrefactor(a: a, x: x)) * h
    }

    /// The x with P(a, x) = p, for 0 <= p < 1 (p == 0 gives 0; p == 1 is +inf).
    /// Newton on P with the exact derivative x^(a-1) e^-x / Gamma(a), kept inside
    /// a bracket that is grown from a Wilson-Hilferty start and shrunk on every
    /// evaluation; a step that leaves the bracket is replaced by its midpoint.
    package static func gammaQuantile(p: Double, shape a: Double) -> Double {
        precondition(a > 0 && p >= 0 && p <= 1, "gammaQuantile needs a > 0, 0 <= p <= 1")
        if p == 0 { return 0 }
        if p == 1 { return .infinity }
        // Wilson-Hilferty start: x ~ a (1 - 1/(9a) + z sqrt(1/(9a)))^3.
        let z = NormalQuantile.value(p)
        var x = a * pow(max(1 - 1 / (9 * a) + z * (1 / (9 * a)).squareRoot(), 0.05), 3)
        if !(x > 0) || !x.isFinite { x = a }
        // Bracket [lo, hi] with P(lo) <= p <= P(hi).
        var lo = 0.0
        var hi = x
        while lowerRegularized(a: a, x: hi) < p {
            lo = hi
            hi *= 2
            if hi > 1e300 { return .infinity }
        }
        if lo == 0 {
            var probe = x / 2
            while probe > 1e-300 && lowerRegularized(a: a, x: probe) > p {
                hi = probe
                probe /= 2
            }
            if probe > 1e-300 { lo = probe }
        }
        x = min(max(x, lo), hi)
        for _ in 0..<maximumIterations {
            let f = lowerRegularized(a: a, x: x) - p
            if abs(f) < quantileResidual { return x }
            if f > 0 { hi = x } else { lo = x }
            if hi - lo < quantileRelativeWidth * hi { return x }
            let logDensity = (a - 1) * log(x) - x - lgamma(a)
            let density = exp(logDensity)
            var next = x - f / density
            if !(next > lo && next < hi) || !next.isFinite { next = 0.5 * (lo + hi) }
            x = next
        }
        return x
    }

    /// Chi-square quantile with `degreesOfFreedom` d.o.f.: 2 * gammaQuantile(p, d/2).
    package static func chiSquareQuantile(p: Double, degreesOfFreedom k: Double) -> Double {
        2 * gammaQuantile(p: p, shape: k / 2)
    }
}

/// Standard normal quantile (inverse CDF). Acklam's rational start refined by
/// two Halley steps on erfc, good to ~1e-15 away from the extreme tails.
package nonisolated enum NormalQuantile {
    package static func value(_ p: Double) -> Double {
        precondition(p > 0 && p < 1, "NormalQuantile needs 0 < p < 1")
        let a = [-3.969683028665376e+01, 2.209460984245205e+02, -2.759285104469687e+02,
                 1.383577518672690e+02, -3.066479806614716e+01, 2.506628277459239e+00]
        let b = [-5.447609879822406e+01, 1.615858368580409e+02, -1.556989798598866e+02,
                 6.680131188771972e+01, -1.328068155288572e+01]
        let c = [-7.784894002430293e-03, -3.223964580411365e-01, -2.400758277161838e+00,
                 -2.549732539343734e+00, 4.374664141464968e+00, 2.938163982698783e+00]
        let d = [7.784695709041462e-03, 3.224671290700398e-01, 2.445134137142996e+00,
                 3.754408661907416e+00]
        let low = 0.02425
        var x: Double
        if p < low {
            let q = (-2 * log(p)).squareRoot()
            x = (((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5])
                / ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1)
        } else if p <= 1 - low {
            let q = p - 0.5
            let r = q * q
            x = (((((a[0] * r + a[1]) * r + a[2]) * r + a[3]) * r + a[4]) * r + a[5]) * q
                / (((((b[0] * r + b[1]) * r + b[2]) * r + b[3]) * r + b[4]) * r + 1)
        } else {
            let q = (-2 * log(1 - p)).squareRoot()
            x = -(((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5])
                / ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1)
        }
        for _ in 0..<2 {
            let e = 0.5 * erfc(-x / 2.0.squareRoot()) - p
            let u = e * (2 * Double.pi).squareRoot() * exp(x * x / 2)
            x -= u / (1 + x * u / 2)
        }
        return x
    }
}
