//
//  DeadLayerFit.swift
//  Role: The optional detector Si dead-layer term of the EDX continuum: a physical transmission factor multiplying the
//        continuum form, with its thickness given or fitted. Off by default (`FitPolicy.continuumDeadLayer` nil).
//
//  FUNCTIONAL FORM:
//
//      B(E) = K(E) x eps(E) x T_dl(E) x P_s(E),      T_dl(E) = exp(-mu_Si(E) rho_Si t)
//
//  Beer-Lambert through the Si dead layer in front of the active detector volume; mu_Si/rho from the FFAST table
//  (`MassAbsorptionTable`, log-log interpolation), rho_Si = 2.33 g/cm^3 (`QuantElementData`). The same factor as the
//  dead-layer term of `SDDEfficiency` (EPQ `Detector/SiLiCalibration.java` getEfficiency()). The Si K edge (1.839 keV)
//  lies 0.1 keV above Si K-alpha: mu_Si rises by about x10 across it, so T_dl steps down there. The Bernstein segment above
//  the Al K edge (1.56-20 keV, order 5) cannot follow a step; a polynomial split at the edge can, but its short segment
//  then trades area with Si K-alpha. T_dl has one parameter, the thickness, and no freedom to trade with a line.
//
//  eXSpy (pinned 7185a4d1) models no detector efficiency and no dead layer: there is no reference to match. Planted
//  truth only (`tools/edx-sim/dead_layer_sim.py`); validation: "none".
//
//  FITTED THICKNESS: t minimises the fit's own objective (unweighted RSS under least squares, the Poisson deviance under
//  maximum likelihood) over [0, maximumMicrons], every line area and continuum coefficient re-fitted at each t (variable
//  projection on one nonlinear parameter): a grid of 21 points, then golden-section search in the bracket around the
//  grid minimum to 1e-4 um. The area sigmas are conditional on the fitted t (its uncertainty is not propagated).
//

import Foundation
import SpectroCore

/// The detector Si dead-layer transmission exp(-mu_Si(E) rho_Si t), t in micrometres.
package nonisolated struct SiliconDeadLayer: DetectorEfficiency {
    package let microns: Double
    package let table: MassAbsorptionTable
    /// QuantElementData's Si density, g/cm^3.
    package static let density = QuantElementData.entry("Si")!.density!

    package init(microns: Double, table: MassAbsorptionTable) { self.microns = microns; self.table = table }

    package var sourceName: String {
        String(format: "Si dead layer %.4f \u{00B5}m, exp(\u{2212}\u{00B5}\u{209B}\u{1D62} \u{03C1} t), FFAST", microns)
    }

    /// 0 outside the FFAST table (as `SDDEfficiency`).
    package func efficiency(energyKeV e: Double) -> Double {
        guard let mu = try? table.mac(element: "Si", energyKeV: e) else { return 0 }
        return exp(-mu * Self.density * microns * 1e-4)
    }
}

/// The product of detector efficiencies (the SDD layers and the dead-layer term together).
package nonisolated struct ProductEfficiency: DetectorEfficiency {
    package let parts: [any DetectorEfficiency]
    package init(_ parts: [any DetectorEfficiency]) { self.parts = parts }
    package var sourceName: String { parts.map(\.sourceName).joined(separator: " \u{00D7} ") }
    package func efficiency(energyKeV e: Double) -> Double { parts.reduce(1) { $0 * $1.efficiency(energyKeV: e) } }
}

package nonisolated enum DeadLayerFit {
    /// The continuum efficiency with the dead layer of `microns` multiplied in (`base` nil: the dead layer alone).
    package static func efficiency(base: (any DetectorEfficiency)?, microns: Double, table: MassAbsorptionTable) -> any DetectorEfficiency {
        let dl = SiliconDeadLayer(microns: microns, table: table)
        guard let base else { return dl }
        return ProductEfficiency([base, dl])
    }

    /// `settings` with the continuum's efficiency replaced by `base` x the dead layer of `microns`. A non-continuum background
    /// is returned unchanged.
    package static func settings(_ settings: FitSettings, base: (any DetectorEfficiency)?, microns: Double,
                                 table: MassAbsorptionTable) -> FitSettings {
        guard case .continuum(var form) = settings.background else { return settings }
        form.efficiency = efficiency(base: base, microns: microns, table: table)
        var s = settings
        s.background = .continuum(form)
        return s
    }

    package struct Result: Sendable {
        /// The fitted thickness, um.
        package var microns: Double
        /// The objective at the fitted thickness and at t = 0.
        package var objective: Double
        package var objectiveAtZero: Double
        /// The minimum sits at the upper bound (the bound, not the data, set t).
        package var atUpperBound: Bool
    }

    /// The thickness in [0, maximumMicrons] that minimises the fit objective (see the header).
    package static func fit(counts: [Double], axis: EnergyAxis, settings: FitSettings, base: (any DetectorEfficiency)?,
                            table: MassAbsorptionTable, maximumMicrons: Double,
                            cancelled: @Sendable () -> Bool = { false }) throws -> Result {
        precondition(maximumMicrons > 0 && maximumMicrons.isFinite, "the dead-layer bound must be positive")
        func objective(_ t: Double) throws -> Double {
            try SpectroCancellation.check(cancelled)
            let r = try EDSFit.run(counts: counts, axis: axis, settings: Self.settings(settings, base: base, microns: t, table: table),
                                   computeCovariance: false)
            let v: Double
            switch settings.method {
            case .leastSquares: v = r.residual.reduce(0) { $0 + $1 * $1 }
            case .poissonML: v = r.deviance
            }
            return v.isFinite ? v : .infinity      // a non-finite objective never wins the minimum
        }
        let n = 20
        let grid = (0...n).map { maximumMicrons * Double($0) / Double(n) }
        let values = try grid.map(objective)
        let best = values.indices.min { values[$0] < values[$1] }!
        var a = grid[max(best - 1, 0)], b = grid[min(best + 1, n)]
        let g = (5.0.squareRoot() - 1) / 2
        var c = b - g * (b - a), d = a + g * (b - a)
        var fc = try objective(c), fd = try objective(d)
        while b - a > 1e-4 {
            if fc < fd { b = d; d = c; fd = fc; c = b - g * (b - a); fc = try objective(c) }
            else { a = c; c = d; fc = fd; d = a + g * (b - a); fd = try objective(d) }
        }
        // The grid point itself may beat the bracket's interior (a minimum at a bound of [0, max]).
        var t = fc < fd ? c : d, f = min(fc, fd)
        if values[best] <= f { t = grid[best]; f = values[best] }
        return Result(microns: t, objective: f, objectiveAtZero: values[0], atUpperBound: best == n && t >= maximumMicrons - 1e-4)
    }
}
