//
//  KFactorSource.swift
//  Role: A set of k-factors with where they came from and how uncertain they are,
//        and the sigma_k term of an at% ratio (WP3 flag 5).
//
//  k convention is CliffLorimer's: C_i proportional to k_i * I_i.
//

import Foundation

package nonisolated struct KFactorSet: Sendable, Equatable {
    package enum Kind: String, Sendable, Equatable { case computed, typed }

    package var kind: Kind
    /// One k per element, in the order of `elements`.
    package var elements: [String]
    package var values: [Double]
    /// "Brown-Powell (computed) + epsilon: ..." or "Williams & Carter table 4" etc.
    /// Required and non-empty: a k without a source is refused at construction.
    package var source: String
    /// ISO date the factors were typed/computed ("2026-10-05").
    package var date: String
    /// Relative 1-sigma per factor (0.20 = 20 %), one per element. Velox's rule and
    /// the pre-registered default; editable.
    package var relativeSigma: [Double]

    package static let defaultRelativeSigma = 0.20

    package init?(kind: Kind, elements: [String], values: [Double], source: String, date: String, relativeSigma: [Double]? = nil) {
        guard !elements.isEmpty, elements.count == values.count,
              !source.trimmingCharacters(in: .whitespaces).isEmpty, !date.isEmpty,
              values.allSatisfy({ $0 > 0 && $0.isFinite }) else { return nil }
        let sig = relativeSigma ?? [Double](repeating: Self.defaultRelativeSigma, count: elements.count)
        guard sig.count == elements.count, sig.allSatisfy({ $0 >= 0 && $0.isFinite }) else { return nil }
        self.kind = kind; self.elements = elements; self.values = values
        self.source = source; self.date = date; self.relativeSigma = sig
    }

    package func k(_ element: String) -> Double? { elements.firstIndex(of: element).map { values[$0] } }
    package func relSigma(_ element: String) -> Double? { elements.firstIndex(of: element).map { relativeSigma[$0] } }
}

package nonisolated enum RatioSigma {
    /// Relative sigma that the k-factors add to the A:B composition ratio
    /// (C_A/C_B = (k_A/k_B)(I_A/I_B), the mass ratio M_B/M_A is exact):
    /// independent factors -> sqrt(sA^2 + sB^2), 28.3 % at 20 % each.
    /// A ratio of two such ratios taken with the SAME k set (the same phase pair
    /// in two regions) has the k factors cancel: 0.
    package static func kTerm(_ set: KFactorSet, numerator a: String, denominator b: String, sameKSetInBothRatios: Bool = false) -> Double? {
        guard let sa = set.relSigma(a), let sb = set.relSigma(b) else { return nil }
        return sameKSetInBothRatios ? 0 : (sa * sa + sb * sb).squareRoot()
    }
}
