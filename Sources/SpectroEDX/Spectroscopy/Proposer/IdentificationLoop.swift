//
//  IdentificationLoop.swift
//  Role: The two measures the identification loop is built on (docs/design/auto-id-tem.md): the top-hat filter that finds the peaks the
//        fit leaves in its residual, and the fit statistic with the 1 % relative model term that decides whether a candidate earns its place.
//        Written from the published method (Newbury and Ritchie's automatic qualitative analysis, as AutoEMX documents it); no code copied.
//
//  The relative term is the point: a model's shape error grows with the counts while Poisson noise grows with their root, so without it
//  every small imperfection of a strong line becomes "significant" in a summed spectrum. With it a channel's variance is mu + (r mu)^2,
//  in the statistic and in the filtered residual's noise alike.
//

import Foundation

package nonisolated enum IdentificationLoop {

    /// Per channel (y - mu)^2 / max(mu + (r mu)^2, 1): the statistic's terms, so a sum over any window is that window's share.
    package static func chiSquaredTerms(y: [Double], mu: [Double], relative r: Double) -> [Double] {
        precondition(y.count == mu.count)
        return zip(y, mu).map { yi, m in
            let d = yi - m
            return d * d / max(m + r * r * m * m, 1)
        }
    }

    /// Sum (y - mu)^2 / max(mu + (r mu)^2, 1).
    package static func chiSquared(y: [Double], mu: [Double], relative r: Double) -> Double {
        chiSquaredTerms(y: y, mu: mu, relative: r).reduce(0, +)
    }

    /// The top-hat filter of `x` with a centre of `widths[i]` channels (odd, at least 3) at channel i and a side lobe of (w + 1) / 2 channels on each
    /// side, weights +1/w and -1/(w + 1), so a constant and a straight line filter to zero. `sigma` is the filtered value's standard deviation
    /// from the per-channel `variance` (sqrt(sum k^2 var)). Where the kernel would leave the array the value is 0 and its sigma infinite.
    package static func topHat(_ x: [Double], variance: [Double], widths: [Int]) -> (filtered: [Double], sigma: [Double]) {
        precondition(x.count == variance.count && x.count == widths.count)
        let n = x.count
        var px = [Double](repeating: 0, count: n + 1), pv = [Double](repeating: 0, count: n + 1)
        for i in 0..<n { px[i + 1] = px[i] + x[i]; pv[i + 1] = pv[i] + max(variance[i], 0) }
        var f = [Double](repeating: 0, count: n), s = [Double](repeating: .infinity, count: n)
        for i in 0..<n {
            var w = max(widths[i], 3)
            if w % 2 == 0 { w += 1 }
            let half = w / 2, side = (w + 1) / 2
            let lo = i - half - side, hi = i + half + side
            guard lo >= 0, hi < n else { continue }
            let centre = px[i + half + 1] - px[i - half], left = px[i - half] - px[lo], right = px[hi + 1] - px[i + half + 1]
            let cw = 1 / Double(w), sw = 1 / Double(2 * side)
            f[i] = cw * centre - sw * (left + right)
            let vc = pv[i + half + 1] - pv[i - half], vs = (pv[i - half] - pv[lo]) + (pv[hi + 1] - pv[i + half + 1])
            s[i] = (cw * cw * vc + sw * sw * vs).squareRoot()
        }
        return (f, s)
    }

    /// The filter's centre width at each energy: one FWHM of the detector law in channels, odd, at least 3.
    package static func widths(energies: [Double], scale: Double, resolutionMnKaEV: Double) -> [Int] {
        energies.map { e in
            let fw = XRayLines.fwhm(resolutionMnKaEV: resolutionMnKaEV, atEnergy: max(e, 0)) ?? resolutionMnKaEV / 1000
            var w = max(Int((fw / scale).rounded()), 3)
            if w % 2 == 0 { w += 1 }
            return w
        }
    }
}
