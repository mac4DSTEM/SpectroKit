//
//  SigmaTerms.swift
//  Role: The uncertainty of a quantified number as NAMED relative terms
//        (counting, k, absorption, thickness) combined in quadrature, so the
//        interface can show which one dominates. Also the amplitude-covariance
//        protocol that the fit lane conforms to, and the delta-method ratio
//        variance it feeds.
//
//  k enters a Cliff-Lorimer ratio as k_A/k_B (ADR 054 addendum, flag 5), i.e. as
//  sqrt(sigma_kA^2 + sigma_kB^2) for independent k-factors (20 % each gives ~28 %).
//  In a RATIO OF RATIOS of two regions both ratios use the same k_A/k_B, so the
//  k term cancels exactly and `ratioOfRatios` carries it as 0.
//

import Foundation

package nonisolated struct SigmaTerms: Equatable, Sendable {
    package enum Name: String, CaseIterable, Sendable {
        case counting, k, absorption, thickness
    }

    /// Relative (fractional) standard uncertainty per term; missing = not applicable.
    package let relative: [Name: Double]

    package init(counting: Double = 0, k: Double = 0, absorption: Double = 0, thickness: Double = 0) {
        relative = [.counting: counting, .k: k, .absorption: absorption, .thickness: thickness]
    }

    package subscript(_ name: Name) -> Double { relative[name] ?? 0 }

    /// Quadrature sum of all terms.
    package var combined: Double {
        Name.allCases.reduce(0) { $0 + self[$1] * self[$1] }.squareRoot()
    }

    /// The largest term (ties resolved in declaration order).
    package var dominant: Name {
        Name.allCases.max { self[$0] < self[$1] } ?? .counting
    }

    /// "counting 12.0 % ⊕ k 28.3 % ⊕ ... = 31.0 %" with the terms in fixed order.
    package var summary: String {
        let parts = Name.allCases.map { String(format: "%@ %.1f %%", $0.rawValue, self[$0] * 100) }
        return parts.joined(separator: " ⊕ ") + String(format: " = %.1f %%", combined * 100)
    }

    /// Relative sigma of the counting term for the ratio I_A / I_B of two
    /// independent net counts.
    package static func countingRatio(netA: Double, varianceA: Double, netB: Double, varianceB: Double) -> Double {
        (varianceA / (netA * netA) + varianceB / (netB * netB)).squareRoot()
    }

    /// Terms of a Cliff-Lorimer ratio C_A/C_B = k_AB * I_A/I_B where the k-factor
    /// is carried as k_A/k_B with independent relative sigmas `kA`, `kB`.
    package static func cliffLorimerRatio(counting: Double, kA: Double, kB: Double,
                                          absorption: Double = 0, thickness: Double = 0) -> SigmaTerms {
        SigmaTerms(counting: counting, k: (kA * kA + kB * kB).squareRoot(),
                   absorption: absorption, thickness: thickness)
    }

    /// Terms of R1 / R2 for two Cliff-Lorimer ratios taken with the SAME k-factors
    /// in different regions: counting (and absorption, thickness, which are
    /// per-region) add in quadrature; the k term cancels and is 0.
    package static func ratioOfRatios(_ first: SigmaTerms, _ second: SigmaTerms) -> SigmaTerms {
        func q(_ n: Name) -> Double { (first[n] * first[n] + second[n] * second[n]).squareRoot() }
        return SigmaTerms(counting: q(.counting), k: 0, absorption: q(.absorption), thickness: q(.thickness))
    }
}

/// What the fit lane (F) hands over: amplitudes and their covariance, row-major
/// n x n, in the same order as `values`. T declares it; F conforms.
nonisolated package protocol FittedAmplitudes {
    var values: [Double] { get }
    var covariance: [Double] { get }
}

extension FittedAmplitudes {
    nonisolated package var count: Int { values.count }

    nonisolated package func variance(at i: Int) -> Double { covariance[i * count + i] }
    nonisolated package func sigma(at i: Int) -> Double { max(variance(at: i), 0).squareRoot() }

    /// Delta-method relative variance of a_i / a_j:
    /// Var_i/a_i^2 + Var_j/a_j^2 - 2 Cov_ij/(a_i a_j).
    nonisolated package func ratioRelativeVariance(_ i: Int, _ j: Int) -> Double {
        let ai = values[i], aj = values[j]
        return variance(at: i) / (ai * ai) + variance(at: j) / (aj * aj)
            - 2 * covariance[i * count + j] / (ai * aj)
    }
}
