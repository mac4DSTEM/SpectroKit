//
//  BrownPowellK.swift
//  Role: A THEORETICAL (computed) Cliff-Lorimer k-factor from an ionisation cross-
//        section, a fluorescence yield, a line weight, the detector efficiency and
//        the atomic weight, with every ingredient named.
//
//  STATUS -- OPEN (2026-10-05): the Brown-Powell ionisation cross-section itself is
//  NOT implemented. The instruction was to port it from the published paper with
//  equation numbers; the publication and its coefficients could not be located
//  and verified in this session (a web search found no source stating them), and
//  inventing them is refused. `IonisationCrossSection` is the seam: the supervisor
//  supplies a verified Brown-Powell (or any other) model that conforms to it, and
//  only then does a computed k carry the name "Brown-Powell". Likewise
//  `FluorescenceYield`: EPQ keeps omega in Java code (FluorescenceYield.java), not
//  in a table file; no omega is bundled here.
//
//  The k algebra below is derived, not ported. For a thin film the line intensity
//      I_A = N_A sigma_A omega_A a_A eps(E_A),   N_A = C_A / A_A
//  (C weight fraction, A atomic weight), so with the convention C_i ~ k_i I_i:
//      k_i = A_i / (sigma_i omega_i a_i eps(E_i))      (per element, up to one
//  common factor; `kFactors(reference:)` normalises the reference element to 1).
//  The ratio k_A/k_B = (A_A sigma_B omega_B a_B eps_B)/(A_B sigma_A omega_A a_A eps_A).
//  NOTE: the WP3 pre-registration prints this ratio with sigma_A and sigma_B
//  exchanged relative to this derivation; the closed-loop test (forward intensities
//  from a known composition, then Cliff-Lorimer) takes the version here.
//

import Foundation

package nonisolated protocol IonisationCrossSection: Sendable {
    /// e.g. "Brown-Powell, <citation>, eq. N".
    var sourceName: String { get }
    /// Cross-section (any consistent unit; only ratios enter k) for the line's
    /// shell at the beam energy, or nil when the model does not cover it.
    func sigma(element: String, line: String, beamEnergyKeV: Double) -> Double?
}

package nonisolated protocol FluorescenceYield: Sendable {
    var sourceName: String { get }
    func omega(element: String, line: String) -> Double?
}

/// One line's ingredients that are not the cross-section.
package nonisolated struct LineIngredients: Sendable {
    package var element: String
    package var line: String            // "Ka", "La", ...
    package var energyKeV: Double
    /// Relative weight of this line within its shell's emission (EPQ line weights).
    package var lineWeight: Double
    package init(element: String, line: String, energyKeV: Double, lineWeight: Double) {
        self.element = element; self.line = line; self.energyKeV = energyKeV; self.lineWeight = lineWeight
    }
}

package nonisolated struct ComputedKFactor: Sendable {
    package let cross: any IonisationCrossSection
    package let yield: any FluorescenceYield
    package let efficiency: any DetectorEfficiency
    package let beamEnergyKeV: Double

    package init(cross: any IonisationCrossSection, yield: any FluorescenceYield,
                 efficiency: any DetectorEfficiency, beamEnergyKeV: Double) {
        self.cross = cross; self.yield = yield; self.efficiency = efficiency; self.beamEnergyKeV = beamEnergyKeV
    }

    /// The text for the k badge.
    package var sourceDescription: String {
        "computed: \(cross.sourceName); omega: \(yield.sourceName); epsilon: \(efficiency.sourceName)"
    }

    /// Per-element k with `reference` (index into `lines`) normalised to 1.
    /// Throws when any ingredient is missing for any element.
    package func kFactors(lines: [LineIngredients], reference: Int = 0) throws -> [Double] {
        guard lines.indices.contains(reference) else { throw QuantError.invalid("Reference index out of range.") }
        var raw: [Double] = []
        for l in lines {
            guard let a = QuantElementData.entry(l.element)?.atomicWeight else { throw QuantError.unknownElement(l.element) }
            guard let s = cross.sigma(element: l.element, line: l.line, beamEnergyKeV: beamEnergyKeV), s > 0 else {
                throw QuantError.invalid("\(cross.sourceName) has no cross-section for \(l.element) \(l.line) at \(beamEnergyKeV) keV.")
            }
            guard let w = yield.omega(element: l.element, line: l.line), w > 0 else {
                throw QuantError.invalid("\(yield.sourceName) has no fluorescence yield for \(l.element) \(l.line).")
            }
            guard l.lineWeight > 0 else { throw QuantError.invalid("Line weight of \(l.element) \(l.line) must be positive.") }
            let eps = efficiency.efficiency(energyKeV: l.energyKeV)
            guard eps > 0 else { throw QuantError.invalid("Efficiency is zero at \(l.energyKeV) keV.") }
            raw.append(a / (s * w * l.lineWeight * eps))
        }
        return raw.map { $0 / raw[reference] }
    }
}
