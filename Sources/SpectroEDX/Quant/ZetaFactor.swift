//
//  ZetaFactor.swift
//  Role: zeta-factor and ionisation-cross-section quantification, doses, and the
//        zeta <-> cross-section conversion. Core only: ADR 054 keeps zeta out of
//        the menu; it is here for eXSpy parity.
//
//  Port of eXSpy utils/eds/_quantification.py `quantification_zeta_factor`
//  (153-199), `quantification_cross_section` (238-290), `cross_section_to_zeta`
//  and `zeta_to_cross_section` (346-408), and signals/_eds_tem.py `_get_dose`
//  (856-917), 7185a4d1. Constants are CODATA 2018 as scipy.constants carries them.
//

import Foundation

package nonisolated enum ZetaFactor {
    package static let elementaryCharge = 1.602176634e-19   // C
    package static let avogadro = 6.02214076e23              // 1/mol

    /// Electrons: live time [s] * beam current [nA] * 1e-9 / e.
    package static func dose(liveTime: Double, beamCurrentNA: Double) -> Double {
        liveTime * beamCurrentNA * 1e-9 / elementaryCharge
    }

    /// Electrons per nm^2 for the cross-section method.
    package static func doseCrossSection(liveTime: Double, beamCurrentNA: Double, probeAreaNm2: Double) -> Double {
        liveTime * beamCurrentNA * 1e-9 / (elementaryCharge * probeAreaNm2)
    }

    /// Weight fractions (sum 1) and mass thickness [kg/m^2].
    package static func quantify(
        intensities: [Double], zetaFactors: [Double], dose: Double, absorption: [Double]? = nil
    ) throws -> (weightFractions: [Double], massThickness: Double) {
        let n = intensities.count
        guard zetaFactors.count == n else { throw QuantError.countMismatch("One zeta-factor per intensity.") }
        let acf = absorption ?? [Double](repeating: 1, count: n)
        guard acf.count == n else { throw QuantError.countMismatch("One absorption factor per intensity.") }
        var sum = 0.0
        for i in 0..<n { sum += intensities[i] * zetaFactors[i] * acf[i] }
        let comp = (0..<n).map { intensities[$0] * zetaFactors[$0] * acf[$0] / sum }
        return (comp, sum / dose)
    }

    /// Atomic fractions (sum 1) and atoms per pixel; `sectionsBarn` in barns.
    package static func crossSection(
        intensities: [Double], sectionsBarn: [Double], dose: Double, absorption: [Double]? = nil
    ) throws -> (atomicFractions: [Double], atoms: [Double]) {
        let n = intensities.count
        guard sectionsBarn.count == n else { throw QuantError.countMismatch("One cross-section per intensity.") }
        let acf = absorption ?? [Double](repeating: 1, count: n)
        guard acf.count == n else { throw QuantError.countMismatch("One absorption factor per intensity.") }
        let atoms = (0..<n).map { intensities[$0] / (sectionsBarn[$0] * dose * 1e-10) * acf[$0] }
        let total = atoms.reduce(0, +)
        return (atoms.map { $0 / total }, atoms)
    }

    /// kg/m^2 from barns: A / (sigma * N_A * 1e-25).
    package static func zetaFromCrossSection(_ barns: [Double], elements: [String]) throws -> [Double] {
        guard barns.count == elements.count else { throw QuantError.countMismatch("One cross-section per element.") }
        return try zip(barns, elements).map { s, el in
            guard let a = QuantElementData.entry(el)?.atomicWeight else { throw QuantError.unknownElement(el) }
            return a / (s * avogadro * 1e-25)
        }
    }

    package static func crossSectionFromZeta(_ zetas: [Double], elements: [String]) throws -> [Double] {
        guard zetas.count == elements.count else { throw QuantError.countMismatch("One zeta-factor per element.") }
        return try zip(zetas, elements).map { z, el in
            guard let a = QuantElementData.entry(el)?.atomicWeight else { throw QuantError.unknownElement(el) }
            return a / (z * avogadro * 1e-25)
        }
    }
}
