//
//  AbsorptionCorrection.swift
//  Role: Self-absorption in a thin film and the iterative correction that feeds
//        Cliff-Lorimer, zeta and cross-section quantification.
//
//  Port of eXSpy utils/eds/_quantification.py `get_abs_corr_zeta` (202-226) and
//  `get_abs_corr_cross_section` (293-343), and the loop in signals/_eds_tem.py
//  `quantification` (297-575, loop 468-531), 7185a4d1.
//
//  Physics (eXSpy's): x = (mu/rho)(rho t)/sin(take-off), transmission
//  T = (1 - e^-x)/x, correction factor 1/T = x/(1 - e^-x); the intensity is
//  multiplied by it. MACs are cm^2/g and are x0.1 to m^2/kg.
//
//  DEVIATIONS from eXSpy:
//   * x == 0 (zero thickness) is the limit T = 1; eXSpy divides 0 by 0 (nan).
//   * Convergence defaults to the ABSOLUTE largest change. eXSpy's loop takes
//     `np.max(new - old)` -- SIGNED -- and only then abs() (lines 512-518), so an
//     iteration in which every element's change is negative can stop at once.
//     `.exspySigned` reproduces it; the pins are asserted under both.
//     With 3 or more elements the two can differ (the changes sum to zero), so
//     parity with eXSpy for n >= 3 needs `.exspySigned`; on two elements they coincide.
//   * The geometry is a protocol so a four-detector sum (FourDetectorAbsorption)
//     drops in where eXSpy has one scalar take-off angle.
//

import Foundation

/// Mean transmission of an X-ray through a film, as seen by the detector system.
package nonisolated protocol AbsorptionGeometry: Sendable {
    /// `macM2PerKg`: mu/rho in m^2/kg; `massThickness`: rho t in kg/m^2. Returns T in (0, 1].
    func meanTransmission(macM2PerKg: Double, massThickness: Double) -> Double
    /// What the correction used, for the result and the footer.
    var segmentSummary: [(takeOffDegrees: Double, weight: Double)] { get }
}

package nonisolated enum Transmission {
    /// (1 - e^-x)/x with the x -> 0 limit; stable for small x.
    package static func slab(_ x: Double) -> Double {
        if x < 1e-8 { return 1 - x / 2 + x * x / 6 }
        return -expm1(-x) / x
    }
}

package nonisolated struct SingleDetectorGeometry: AbsorptionGeometry {
    package let takeOffDegrees: Double
    package init(takeOffDegrees: Double) { self.takeOffDegrees = takeOffDegrees }
    package var segmentSummary: [(takeOffDegrees: Double, weight: Double)] { [(takeOffDegrees, 1)] }

    package func meanTransmission(macM2PerKg: Double, massThickness: Double) -> Double {
        let csc = 1 / sin(takeOffDegrees * .pi / 180)
        return Transmission.slab(macM2PerKg * massThickness * csc)
    }
}

/// What the correction needs to know about the specimen's lines.
package nonisolated struct AbsorptionSetup: Sendable {
    package let elements: [String]
    /// keV, one per element, in the order of `elements` (the line that is measured).
    package let lineEnergiesKeV: [Double]
    package let geometry: any AbsorptionGeometry
    package let table: MassAbsorptionTable

    package init(elements: [String], lineEnergiesKeV: [Double], geometry: any AbsorptionGeometry, table: MassAbsorptionTable) {
        self.elements = elements; self.lineEnergiesKeV = lineEnergiesKeV
        self.geometry = geometry; self.table = table
    }

    /// Per-line factors 1/T from a composition given in weight PERCENT and a mass
    /// thickness in kg/m^2 (`get_abs_corr_zeta`).
    package func factors(weightPercent: [Double], massThickness: Double) throws -> [Double] {
        try lineEnergiesKeV.map { e in
            let mac = try table.mixture(elements: elements, weights: weightPercent, energyKeV: e) * 0.1
            return 1 / geometry.meanTransmission(macM2PerKg: mac, massThickness: massThickness)
        }
    }
}

package nonisolated struct AbsorptionIterationOptions: Sendable {
    package enum Criterion: Sendable { case absolute, exspySigned }
    package var convergence = 0.5       // percent, eXSpy `convergence_criterion`
    package var maxIterations = 30
    package var criterion: Criterion = .absolute
    package init(convergence: Double = 0.5, maxIterations: Int = 30, criterion: Criterion = .absolute) {
        self.convergence = convergence; self.maxIterations = maxIterations; self.criterion = criterion
    }
}

package nonisolated struct AbsorptionResult: Sendable {
    /// Percent. Weight percent for CL and zeta, atomic percent for cross-section.
    package let composition: [Double]
    package let massThickness: Double
    package let atoms: [Double]?
    package let factors: [Double]
    package let iterations: Int
    /// Per detector segment: take-off (deg) and effective weight (solid angle x (1 - shadow)).
    /// One entry for a single detector (weight 1).
    package let segments: [(takeOffDegrees: Double, weight: Double)]
}

package nonisolated enum AbsorptionCorrection {
    /// Cliff-Lorimer with absorption; `thicknessNm` is the known film thickness.
    package static func cliffLorimer(
        intensities: [Double], kFactors: [Double], setup: AbsorptionSetup, thicknessNm: Double,
        options: AbsorptionIterationOptions = .init(), singleLine: CliffLorimer.SingleLinePolicy = .refuse
    ) throws -> AbsorptionResult {
        try iterate(options: options, count: intensities.count, summary: setup.geometry.segmentSummary) { acf in
            let w = try CliffLorimer.weightFractions(intensities: intensities, kFactors: kFactors, absorption: acf, singleLine: singleLine)
            let pct = w.map { $0 * 100 }
            let mt = try CliffLorimer.massThickness(weightPercent: pct, elements: setup.elements, thicknessNm: thicknessNm)
            return (pct, mt, nil, try setup.factors(weightPercent: pct, massThickness: mt))
        }
    }

    /// Zeta-factor with absorption (thickness comes out of the zeta sum).
    package static func zeta(
        intensities: [Double], zetaFactors: [Double], dose: Double, setup: AbsorptionSetup,
        options: AbsorptionIterationOptions = .init()
    ) throws -> AbsorptionResult {
        try iterate(options: options, count: intensities.count, summary: setup.geometry.segmentSummary) { acf in
            let r = try ZetaFactor.quantify(intensities: intensities, zetaFactors: zetaFactors, dose: dose, absorption: acf)
            let pct = r.weightFractions.map { $0 * 100 }
            return (pct, r.massThickness, nil, try setup.factors(weightPercent: pct, massThickness: r.massThickness))
        }
    }

    /// Cross-section with absorption. `dose` from `ZetaFactor.doseCrossSection`.
    package static func crossSection(
        intensities: [Double], sectionsBarn: [Double], dose: Double, probeAreaNm2: Double, setup: AbsorptionSetup,
        options: AbsorptionIterationOptions = .init()
    ) throws -> AbsorptionResult {
        try iterate(options: options, count: intensities.count, summary: setup.geometry.segmentSummary) { acf in
            let r = try ZetaFactor.crossSection(intensities: intensities, sectionsBarn: sectionsBarn, dose: dose, absorption: acf)
            let pct = r.atomicFractions.map { $0 * 100 }
            // eXSpy get_abs_corr_cross_section: mass per m^2 from atoms, then the
            // mixture MAC at weight percent from the atomic composition.
            var totalMass = 0.0
            for (n, el) in zip(r.atoms, setup.elements) {
                guard let a = QuantElementData.entry(el)?.atomicWeight else { throw QuantError.unknownElement(el) }
                totalMass += n * a / ZetaFactor.avogadro / 1e3 / probeAreaNm2 / 1e-18
            }
            let wt = try CompositionConversion.atomicToWeight(pct, elements: setup.elements)
            return (pct, totalMass, r.atoms, try setup.factors(weightPercent: wt, massThickness: totalMass))
        }
    }

    /// The convergence measure. `.exspySigned` is eXSpy's `np.max(new - old)`.
    package static func change(new: [Double], old: [Double], criterion: AbsorptionIterationOptions.Criterion) -> Double {
        var m = -Double.infinity
        for i in new.indices {
            let d = new[i] - old[i]
            m = max(m, criterion == .absolute ? abs(d) : d)
        }
        return m
    }

    // The eXSpy loop. `step` maps the current factors (nil at the start) to
    // (composition %, mass thickness, atoms, next factors).
    private static func iterate(
        options: AbsorptionIterationOptions, count: Int, summary: [(takeOffDegrees: Double, weight: Double)],
        step: ([Double]?) throws -> ([Double], Double, [Double]?, [Double])
    ) throws -> AbsorptionResult {
        var factors: [Double]? = nil
        var old = [Double](repeating: 0, count: count)
        var it = 0
        while true {
            let (comp, mt, atoms, next) = try step(factors)
            factors = next
            let change = Self.change(new: comp, old: old, criterion: options.criterion)
            old = comp
            it += 1
            if abs(change) < options.convergence {
                return AbsorptionResult(composition: comp, massThickness: mt, atoms: atoms, factors: next, iterations: it, segments: summary)
            }
            if it >= options.maxIterations { throw QuantError.didNotConverge(iterations: options.maxIterations) }
        }
    }
}
