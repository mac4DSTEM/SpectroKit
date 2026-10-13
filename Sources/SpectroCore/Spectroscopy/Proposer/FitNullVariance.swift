//
//  FitNullVariance.swift
//  Role: The variance of a fitted line area UNDER THE NULL (the candidate absent), from the fit's own design.
//        Currie's L_C and L_D need sigma_0, the standard deviation of the net when there is no signal;
//        the covariance `EDSFit` reports is evaluated at the fitted state, so a strong line carries its own
//        Poisson variance in it and would inflate its own detection limit.
//
//  The estimator is the fit's unweighted least squares, theta = K y with K = (D^T D)^-1 D^T (QR, unit-norm
//  columns), and Var(y_i) = mu_i (Poisson), as `EDSFit` computes its sandwich covariance. For the area of group g
//      Var_fit(a_g)  = sum_i K_gi^2 mu_i,
//      Var_null(a_g) = sum_i K_gi^2 (mu_i - mu_i^(g)),
//  where mu^(g) is the group's own contribution (its line column times its area, plus its Si-escape column times
//  its area). What remains is the continuum and every OTHER line under the group's window, which is exactly
//  "the fitted background under the candidate's lines" propagated through the amplitude's own estimator, so an
//  overlapping neighbour or a continuum that the fit has to tell apart raises sigma_0 where it should.
//  `EDSFit` does not expose K, so the sandwich is rebuilt here (about thirty lines, the same algebra).
//  DELIBERATELY the FULL supported design, not the passive set `EDSFit` now reports (lane Sigma): under H0 the candidate
//  is a free parameter, so a bound-active column (the candidate's own, at 0) must count as free and correlated with its neighbours.
//

import Foundation

package nonisolated struct AmplitudeVariances: Sendable {
    /// Per model group; nil for a group without support in the fitted range.
    package var atFit: [Double?]
    package var null: [Double?]
}

package nonisolated enum FitNullVariance {
    /// nil when the design is numerically rank deficient (the same refusal as `EDSFit`'s covariance).
    package static func compute(design: LinearDesign, result: EDSFitResult) -> AmplitudeVariances? {
        let nn = design.nonNegative, ff = design.free
        let nAreas = design.areaColumns.count
        let supportedCols = (0..<nn.cols).filter { $0 >= nAreas || design.areaColumns[$0].supported }
        let k = supportedCols.count + ff.cols
        let n = design.channels.count
        guard k > 0, n >= k else { return nil }
        var cols: [[Double]] = supportedCols.map { Array(nn.column($0)) }
        for j in 0..<ff.cols { cols.append(Array(ff.column(j))) }
        let norms = cols.map { c in max(c.reduce(0) { $0 + $1 * $1 }.squareRoot(), 1e-300) }
        let scaled = ColumnMatrix(columns: cols.enumerated().map { (j, c) in c.map { $0 / norms[j] } })
        guard let (_, kmat) = FitLinearAlgebra.pseudoInverse(scaled) else { return nil }

        var escapeColumn: [Int: Int] = [:]
        for (j, c) in design.areaColumns.enumerated() { if case .escape(let g) = c.kind { escapeColumn[g] = j } }
        let g = result.values.count
        var atFit = [Double?](repeating: nil, count: g), null = [Double?](repeating: nil, count: g)
        let mu = result.model
        for (ia, ja) in supportedCols.enumerated() where ja < nAreas {
            guard case .line(let gi) = design.areaColumns[ja].kind else { continue }
            let own = design.areaColumns[ja].values, a = result.values[gi]
            let esc = escapeColumn[gi].map { design.areaColumns[$0].values }, ae = result.escapeValues[gi] ?? 0
            var vFit = 0.0, vOwn = 0.0
            for i in 0..<n {
                let kk = kmat.data[i * k + ia], w = kk * kk
                let m = max(mu[i], 0)
                vFit += w * m
                var o = a * own[i]
                if let esc { o += ae * esc[i] }
                vOwn += w * min(max(o, 0), m)
            }
            let s2 = norms[ia] * norms[ia]
            atFit[gi] = vFit / s2
            null[gi] = max(vFit - vOwn, 0) / s2
        }
        return AmplitudeVariances(atFit: atFit, null: null)
    }
}
