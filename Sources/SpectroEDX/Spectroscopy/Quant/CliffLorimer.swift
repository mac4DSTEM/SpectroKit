//
//  CliffLorimer.swift
//  Role: Cliff-Lorimer thin-film quantification and the mass thickness it needs
//        for absorption correction.
//
//  Port of eXSpy utils/eds/_quantification.py `quantification_cliff_lorimer` and
//  `_quantification_cliff_lorimer` (lines 33-150) and signals/_eds_tem.py
//  `CL_get_mass_thickness` (922-965), 7185a4d1. Convention (eXSpy's): C_i is
//  proportional to k_i * I_i, so the weight ratio C_A/C_B = (k_A/k_B)(I_A/I_B).
//
//  DEVIATIONS from eXSpy:
//   * Fewer than two lines above `minIntensity` is a refusal (`needTwoLines`).
//     eXSpy reports 100 % of the single element (and zeros for none), a number
//     that is a property of dose and the 0.1 floor, not of the specimen
//     (validation.md §1d items 1-2: at <= 3 counts/pixel 30-51 % of pixels do
//     this). `SingleLinePolicy.exspyHundredPercent` reproduces eXSpy for the
//     parity pins only.
//   * No vacuum mask here; masking belongs to the caller's region definition.
//

import Foundation

package nonisolated enum CliffLorimer {
    /// eXSpy's threshold on the denominator intensity (`min_intensity`, line 61).
    /// A dataset property per the threshold rule; the caller may not change it
    /// here, the constant is named so the DEVIATION review can find it.
    package static let minIntensity = 0.1

    package enum SingleLinePolicy: Sendable { case refuse, exspyHundredPercent }

    /// Weight fractions (sum 1) in the order of `intensities`.
    /// `absorption` multiplies each intensity before the ratio (factor >= 1).
    package static func weightFractions(
        intensities: [Double], kFactors: [Double], absorption: [Double]? = nil,
        singleLine: SingleLinePolicy = .refuse
    ) throws -> [Double] {
        let n = intensities.count
        guard kFactors.count == n else {
            throw QuantError.countMismatch("The number of k-factors must match the number of intensities.")
        }
        let acf = absorption ?? [Double](repeating: 1, count: n)
        guard acf.count == n else { throw QuantError.countMismatch("One absorption factor per intensity.") }

        let above = intensities.indices.filter { intensities[$0] > minIntensity }
        guard above.count > 1 else {
            switch singleLine {
            case .refuse: throw QuantError.needTwoLines(linesAbove: above.count)
            case .exspyHundredPercent:
                var z = [Double](repeating: 0, count: n)
                if let i = above.first { z[i] = 1 }
                return z
            }
        }
        let ref = above[0], ref2 = above[1]

        // ab[i] = C_ref / C_i. Division by a zero intensity gives +inf, which the
        // formulas below turn into a zero composition for that element -- the
        // same IEEE behaviour numpy shows in eXSpy's zero-handling pin.
        var ab = [Double](repeating: 0, count: n)
        var composition = [Double](repeating: 1, count: n)
        let others = (0..<n).filter { $0 != ref }
        for i in others {
            ab[i] = (intensities[ref] * acf[ref]) / (intensities[i] * acf[i]) * (kFactors[ref] / kFactors[i])
        }
        for i in others {
            if i == ref2 { composition[ref] += ab[ref2] } else { composition[ref] += ab[ref2] / ab[i] }
        }
        composition[ref] = ab[ref2] / composition[ref]
        for i in others { composition[i] = composition[ref] / ab[i] }
        return composition
    }

    /// Mass thickness in kg/m^2 from weight PERCENT, element symbols and a
    /// thickness in nm: sum_i wt%_i * t * rho_i * 1e-8 (eXSpy lines 950-964; the
    /// weight-fraction mean of the pure-element densities).
    package static func massThickness(weightPercent: [Double], elements: [String], thicknessNm: Double) throws -> Double {
        guard weightPercent.count == elements.count else {
            throw QuantError.countMismatch("One weight percent per element.")
        }
        var mt = 0.0
        for (w, el) in zip(weightPercent, elements) {
            guard let e = QuantElementData.entry(el) else { throw QuantError.unknownElement(el) }
            guard let rho = e.density else { throw QuantError.noDensity(el) }
            mt += w * thicknessNm * rho * 1e-8
        }
        return mt
    }
}
