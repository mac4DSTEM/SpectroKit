//
//  Currie.swift
//  Role: Currie (1968) decision and detection limits for a net window count
//        N = G - s*B, with the window scale s carried through (the textbook
//        constants 2.33 and 2.71 + 4.65 sqrt(B) hold only at s = 1).
//
//  B is the background-window count, s scales it into the signal window. With no
//  net signal, Var(N) = s*B + s^2*B =: sigma0^2, so
//      L_C = z_alpha * sigma0.
//  At a true net L the variance is sigma0^2 + L, and requiring that the
//  probability of N > L_C is 1 - beta at L = L_D gives
//      (L_D - z_alpha*sigma0)^2 = z_beta^2 * (sigma0^2 + L_D),
//  whose larger root is returned. For alpha = beta = 0.05 and s = 1 this is
//  L_C = 2.33 sqrt(B) and L_D = 2.71 + 4.65 sqrt(B).
//

import Foundation

package nonisolated struct Currie: Equatable, Sendable {
    package let alpha: Double
    package let beta: Double

    /// Currie's convention (alpha = beta = 0.05): a choice, reported with every result. L_C and L_D
    /// that follow from it are the dataset's properties.
    package static let standard = Currie(alpha: 0.05, beta: 0.05)

    package init(alpha: Double, beta: Double) {
        precondition(alpha > 0 && alpha < 0.5 && beta > 0 && beta < 0.5, "alpha, beta in (0, 0.5)")
        self.alpha = alpha
        self.beta = beta
    }

    package var zAlpha: Double { NormalQuantile.value(1 - alpha) }
    package var zBeta: Double { NormalQuantile.value(1 - beta) }

    /// sigma0^2 = s*B + s^2*B.
    package static func sigmaZero(background b: Double, scale s: Double) -> Double {
        (s * b + s * s * b).squareRoot()
    }

    /// Critical level L_C: a net above it rejects "no signal" at false-positive rate alpha.
    package func criticalLevel(background b: Double, scale s: Double) -> Double {
        criticalLevel(sigmaZero: Self.sigmaZero(background: b, scale: s))
    }

    /// L_C for a given null standard deviation sigma0 (for backgrounds that are not a single scaled count).
    package func criticalLevel(sigmaZero s0: Double) -> Double { zAlpha * s0 }

    /// Detection limit L_D: the true net count detected with probability 1 - beta.
    package func detectionLimit(background b: Double, scale s: Double) -> Double {
        detectionLimit(sigmaZero: Self.sigmaZero(background: b, scale: s))
    }

    /// L_D for a given sigma0, assuming the variance at a true net L is sigma0^2 + L.
    package func detectionLimit(sigmaZero s0: Double) -> Double {
        let za = zAlpha, zb = zBeta
        let linear = 2 * za * s0 + zb * zb
        let disc = linear * linear - 4 * (za * za - zb * zb) * s0 * s0
        return (linear + disc.squareRoot()) / 2
    }
}
