//
//  PoissonMLFit.swift
//  Role: Poisson maximum likelihood on the same linear design as the least-squares fit, by
//        iteratively reweighted least squares (Fisher scoring) with non-negative line areas. It sits
//        under Expert (ADR 054 V5-Q1); the cap and tolerance are recorded in every result.
//
//  The model is mu = D theta + offset (identity link), the data y_i ~ Poisson(mu_i). The score is
//  s_j = sum_i D_ij (y_i - mu_i) / mu_i and the expected information F_jk = sum_i D_ij D_ik / mu_i, so
//  one Fisher step is exactly the weighted least-squares solution with weights 1 / mu_i (Green 1984;
//  McCullagh & Nelder, Generalized Linear Models, section 2.5). Here that step is taken by
//  `LeastSquaresFit.solve` with `rowWeights`, so the line areas stay >= 0 (NNLS) and a free-sign
//  background stays free. The step is DAMPED, theta <- theta + alpha (theta_hat - theta) with alpha halved
//  from 1 until the deviance does not increase: the feasible set is convex, so every iterate is
//  feasible and the deviance is non-increasing by construction.
//
//  Deviance D = 2 sum [ y ln(y/mu) - (y - mu) ] (the y ln y term is 0 at y = 0). mu below `muFloor`
//  is clamped to it, in the weights and in D, so a channel the model has driven to zero cannot give an
//  infinite weight or an infinite deviance. The number of clamped channels is reported.
//
//  Convergence: relative decrease of D below `tolerance` or `maxIterations` reached.
//  The cap and tolerance are chosen by the session (pre-registration: "decides alone, recorded in the method").
//

import Foundation

package nonisolated struct IRLSSettings: Sendable, Equatable {
    package var maxIterations: Int = 200
    /// Stop when (D_old - D_new) / max(D_old, 1) falls below this.
    package var tolerance: Double = 1e-9
    /// mu is clamped below this (counts per channel).
    package var muFloor: Double = 1e-6
    package init(maxIterations: Int = 200, tolerance: Double = 1e-9, muFloor: Double = 1e-6) {
        self.maxIterations = maxIterations; self.tolerance = tolerance; self.muFloor = muFloor
    }
}

package nonisolated enum IRLSExit: String, Sendable {
    case converged = "converged"
    /// No deviance decrease in 40 halvings AND the Poisson score equations hold (KKT): a stationary point.
    case stationary = "stationary (no deviance decrease, KKT satisfied)"
    case capReached = "cap reached"
    /// No decrease but the KKT conditions are violated: the iteration is stuck, the result is not a maximum.
    case stalled = "stalled (no deviance decrease, KKT violated)"
}

package nonisolated enum PoissonMLFit {
    package static func label(_ s: IRLSSettings) -> String {
        "Poisson maximum likelihood (IRLS, cap \(s.maxIterations), tolerance \(s.tolerance))"
    }

    package struct Solution: Sendable {
        package var nonNegative: [Double]
        package var free: [Double]
        package var deviance: Double
        /// Deviance after each iteration, starting with the start point (index 0).
        package var devianceHistory: [Double]
        package var iterations: Int
        package var converged: Bool
        package var exit: IRLSExit
        /// Largest KKT violation |g_j| / sum|D_ij| (zero or active-bound sign violations count), at exit.
        package var kktResidual: Double
        package var clampedChannels: Int
    }

    /// Poisson deviance of `mu` against `y`, `mu` clamped at `floor`.
    package static func deviance(y: [Double], mu: [Double], floor: Double) -> Double {
        var d = 0.0
        for i in y.indices {
            let m = max(mu[i], floor)
            let yi = y[i]
            d += yi > 0 ? yi * log(yi / m) - (yi - m) : m
        }
        return 2 * d
    }

    package static func solve(
        nonNegative n: ColumnMatrix, free f: ColumnMatrix = ColumnMatrix(rows: 0, cols: 0),
        y: [Double], offset: [Double]? = nil, settings: IRLSSettings = IRLSSettings(),
        start: LeastSquaresFit.Solution? = nil
    ) -> Solution {
        let m = y.count
        let off = offset ?? [Double](repeating: 0, count: m)
        let target = (0..<m).map { y[$0] - off[$0] }

        func mu(_ x: [Double], _ b: [Double]) -> [Double] {
            var v = n.times(x)
            if f.cols > 0 { let g = f.times(b); for i in 0..<m { v[i] += g[i] } }
            for i in 0..<m { v[i] += off[i] }
            return v
        }

        // Start: weighted LS with Neyman weights 1 / max(y, 1) (positive even where mu0 would not be).
        var cur = start ?? LeastSquaresFit.solve(
            nonNegative: n, free: f, y: target, rowWeights: y.map { 1 / max($0, 1) })
        var x = cur.nonNegative, b = cur.free
        var mus = mu(x, b)
        var dev = deviance(y: y, mu: mus, floor: settings.muFloor)
        var history = [dev]
        var iterations = 0, converged = false
        var exit = IRLSExit.capReached

        while iterations < settings.maxIterations {
            iterations += 1
            let w = mus.map { 1 / max($0, settings.muFloor) }
            cur = LeastSquaresFit.solve(nonNegative: n, free: f, y: target, rowWeights: w)
            var alpha = 1.0
            var accepted = false
            var xNew = x, bNew = b, musNew = mus, devNew = dev
            for _ in 0..<40 {
                xNew = zip(x, cur.nonNegative).map { $0 + alpha * ($1 - $0) }
                bNew = zip(b, cur.free).map { $0 + alpha * ($1 - $0) }
                musNew = mu(xNew, bNew)
                devNew = deviance(y: y, mu: musNew, floor: settings.muFloor)
                if devNew <= dev { accepted = true; break }
                alpha /= 2
            }
            if !accepted { exit = .stationary; break }   // no decrease in 40 halvings: a stationary point if the score equations hold (checked below)
            let decrease = dev - devNew
            x = xNew; b = bNew; mus = musNew; dev = devNew
            history.append(dev)
            if decrease / max(dev, 1) < settings.tolerance { converged = true; exit = .converged; break }
        }
        let clamped = mus.reduce(0) { $0 + ($1 < settings.muFloor ? 1 : 0) }
        // KKT of the Poisson likelihood: g_j = sum_i D_ij (1 - y_i / mu_i) is 0 for a positive area and a free column,
        // and >= 0 where the area sits at 0.
        let wk = (0..<m).map { 1 - y[$0] / max(mus[$0], settings.muFloor) }
        var kkt = 0.0
        for j in 0..<n.cols {
            var g = 0.0, norm = 0.0
            for i in 0..<m { let d = n.data[j * m + i]; g += d * wk[i]; norm += abs(d) }
            if norm == 0 { continue }
            kkt = max(kkt, x[j] > 0 ? abs(g) / norm : max(-g, 0) / norm)
        }
        for j in 0..<f.cols {
            var g = 0.0, norm = 0.0
            for i in 0..<m { let d = f.data[j * m + i]; g += d * wk[i]; norm += abs(d) }
            if norm > 0 { kkt = max(kkt, abs(g) / norm) }
        }
        if exit == .stationary, kkt > 1e-5 { exit = .stalled }
        converged = (exit == .converged || exit == .stationary)
        return Solution(nonNegative: x, free: b, deviance: dev, devianceHistory: history,
                        iterations: iterations, converged: converged, exit: exit, kktResidual: kkt, clampedChannels: clamped)
    }
}
