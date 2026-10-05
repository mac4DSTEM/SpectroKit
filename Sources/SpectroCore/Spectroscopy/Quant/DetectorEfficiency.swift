//
//  DetectorEfficiency.swift
//  Role: The detector's intrinsic efficiency epsilon(E) as a NAMED input to a
//        computed k-factor. No curve ships: the Super-X G1 window/contact/dead-
//        layer thicknesses are not in any file we hold (ADR 054, second opinion
//        C2), so a computed k carries whatever source the user or the supervisor
//        names, and the k badge shows `sourceName`.
//

import Foundation

package nonisolated protocol DetectorEfficiency: Sendable {
    /// Shown in the k badge, e.g. "typed table: Thermo Super-X datasheet 2024".
    var sourceName: String { get }
    /// 0...1 (relative values are fine: only ratios enter k).
    func efficiency(energyKeV: Double) -> Double
}

/// epsilon = 1 everywhere. Honest default for an "efficiency not applied" k.
package nonisolated struct UnityEfficiency: DetectorEfficiency {
    package let sourceName = "none (efficiency = 1)"
    package init() {}
    package func efficiency(energyKeV: Double) -> Double { 1 }
}

/// Piecewise log-linear (ln epsilon against ln E) interpolation of typed points,
/// ascending in energy. It never extrapolates or clamps: `efficiency` traps
/// outside the points, so callers check `covers(_:)` first.
package nonisolated struct TabulatedEfficiency: DetectorEfficiency {
    package let sourceName: String
    private let energies: [Double]
    private let values: [Double]

    package init?(points: [(energyKeV: Double, efficiency: Double)], sourceName: String) {
        guard points.count >= 2, !sourceName.isEmpty,
              zip(points, points.dropFirst()).allSatisfy({ $0.0.energyKeV < $0.1.energyKeV }),
              points.allSatisfy({ $0.energyKeV > 0 && $0.efficiency > 0 }) else { return nil }
        energies = points.map(\.energyKeV); values = points.map(\.efficiency)
        self.sourceName = sourceName
    }

    package func covers(_ energyKeV: Double) -> Bool {
        energyKeV >= energies[0] && energyKeV <= energies[energies.count - 1]
    }

    package func efficiency(energyKeV e: Double) -> Double {
        precondition(covers(e), "energy outside the tabulated efficiency")
        var i = 1
        while i < energies.count - 1 && energies[i] < e { i += 1 }
        let t = log(e / energies[i - 1]) / log(energies[i] / energies[i - 1])
        return exp(log(values[i - 1]) + t * log(values[i] / values[i - 1]))
    }
}
