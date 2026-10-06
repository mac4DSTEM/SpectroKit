//
//  BrownPowellK.swift
//  Role: A THEORETICAL (computed) Cliff-Lorimer k-factor from an ionisation cross-
//        section, a fluorescence yield, a line weight, the detector efficiency and
//        the atomic weight, with every ingredient named.
//
//  STATUS (round 2, 2026-10-05): the shipped cross-section is Bote-Salvat 2008
//  (BoteSalvatCrossSection, from NIST EPQ), omega is Krause 1979
//  (KrauseFluorescenceYield) and epsilon the generic SDD model (SDDEfficiency). There
//  is NO Brown-Powell here -- no licence-clean source exists (ADR 054 addendum) -- so
//  nothing in this file is called Brown-Powell and Velox parity is not claimed. The
//  file name is kept from the WP3 plan. Any model that conforms to
//  `IonisationCrossSection` / `FluorescenceYield` plugs in.
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

    /// K-alpha: weight = (K-L3 + K-L2) / all K emission, from EPQ's line weights.
    package static func kAlpha(element: String, energyKeV: Double, weights: EPQLineWeights) -> LineIngredients? {
        guard let w = weights.fraction(element: element, shell: "K", transitions: ["K-L3", "K-L2"]) else { return nil }
        return LineIngredients(element: element, line: "Ka", energyKeV: energyKeV, lineWeight: w)
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

    /// The k set, reported "relative to <reference>", badged unvalidated, with its source
    /// string naming the cross-section, omega and epsilon models. The reference
    /// element carries sigma_k = 0 (it is 1 by definition).
    package func kFactorSet(lines: [LineIngredients], reference: Int = 0, date: String) throws -> KFactorSet {
        let k = try kFactors(lines: lines, reference: reference)
        let ref = lines[reference].element
        let src = "\(sourceDescription); relative to \(ref); beam \(beamEnergyKeV) keV; UNVALIDATED"
        guard let s = KFactorSet(kind: .computed, elements: lines.map(\.element), values: k, source: src, date: date, reference: ref) else {
            throw QuantError.invalid("The computed k-factors could not form a set (duplicate or non-positive).")
        }
        return s
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
