//
//  EnergyAxisRefinement.swift
//  Role: Refine the energy axis on the POOLED spectrum (ADR 054 V5-Q4): an offset correction, a
//        relative gain correction and the detector resolution (FWHM at Mn K-alpha), keeping the
//        file's values beside the refined ones.
//
//  Method (variable projection). For a trial (d, g, R) the axis becomes
//      E'_i = (offset + d) + scale * (1 + g) * i,
//  the line model is rebuilt on E' with the width law at resolution R, and all amplitudes and
//  background coefficients are solved by the SAME unweighted non-negative least squares as the fit.
//  Only the residual sum of squares of that solve is minimised over the three nonlinear parameters,
//  by Nelder-Mead in units of (1 eV, 0.01 %, 1 eV) so one simplex step is comparable in each. The
//  channel range is held fixed on the FILE axis, so the data set does not change between trials.
//
//  DEVIATION (eXSpy): eXSpy's `calibrate_energy_axis` refines ONE of resolution / scale / offset at a
//  time on the alpha lines with a bounded nonlinear fit. Here the three are refined together, on
//  every line of the model, because offset and gain are strongly correlated when only one is free.
//  They are well determined only when the lines span the range (the test uses 1.25-8 keV).
//

import Foundation

package nonisolated struct AxisRefinementSettings: Sendable, Equatable {
    package var refineOffset = true
    package var refineGain = true
    package var refineResolution = true
    package var maxIterations = 600
    /// Stop when the simplex's RSS spread is below this fraction of the RSS.
    package var tolerance = 1e-12
    package init() {}
}

package nonisolated struct AxisRefinementResult: Sendable, Equatable {
    // The file's values, kept beside the refined ones.
    package let fileOffset: Double
    package let fileScale: Double
    package let fileResolutionMnKaEV: Double
    package let offset: Double
    package let scale: Double
    package let resolutionMnKaEV: Double
    package let rssFile: Double
    package let rssRefined: Double
    package let iterations: Int
    package let converged: Bool

    package var refinedAxis: EnergyAxis { EnergyAxis(offset: offset, scale: scale, size: size) }
    package let size: Int
    /// Offset correction in eV (refined - file).
    package var offsetShiftEV: Double { (offset - fileOffset) * 1000 }
    /// Relative gain correction (refined / file - 1).
    package var gainShift: Double { scale / fileScale - 1 }
}

package nonisolated enum EnergyAxisRefinement {

    package static func refine(
        counts: [Double], fileAxis: EnergyAxis, fileResolutionMnKaEV: Double, settings: FitSettings,
        options: AxisRefinementSettings = AxisRefinementSettings()
    ) throws -> AxisRefinementResult {
        guard counts.count == fileAxis.size else { throw EDSFitError.lengthMismatch }
        let channels = fileAxis.fitChannels(from: settings.fitFrom, to: settings.fitTo)
        guard !channels.isEmpty else { throw EDSFitError.noChannels }
        try EDSFit.validate(settings.referenceShapes, axis: fileAxis,
                            model: EDSLineModel.build(elements: settings.elements, axis: fileAxis, beamEnergy: settings.beamEnergy,
                                                      resolutionMnKaEV: fileResolutionMnKaEV, escapePeaks: settings.escapePeaks))

        // Units: u0 = offset shift / 1 eV, u1 = gain shift / 1e-4, u2 = (R - R_file) / 1 eV.
        func rss(_ u: [Double]) -> Double {
            let d = (options.refineOffset ? u[0] : 0) * 1e-3
            let g = (options.refineGain ? u[1] : 0) * 1e-4
            let r = fileResolutionMnKaEV + (options.refineResolution ? u[2] : 0)
            guard r > 20, r < 500 else { return .infinity }
            let axis = EnergyAxis(offset: fileAxis.offset + d, scale: fileAxis.scale * (1 + g), size: fileAxis.size)
            let model = EDSLineModel.build(elements: settings.elements, axis: axis, beamEnergy: settings.beamEnergy,
                                           resolutionMnKaEV: r, escapePeaks: settings.escapePeaks)
            let design = LinearDesign.build(model: model, axis: axis, channels: channels,
                                            background: settings.background, shapes: settings.referenceShapes,
                                            counts: counts)
            let y = channels.map { counts[$0] }
            let target = (0..<y.count).map { y[$0] - design.offset[$0] }
            let s = LeastSquaresFit.solve(nonNegative: design.nonNegative, free: design.free, y: target)
            var mu = design.nonNegative.times(s.nonNegative)
            if design.free.cols > 0 { let f = design.free.times(s.free); for i in 0..<mu.count { mu[i] += f[i] } }
            var sum = 0.0
            for i in 0..<y.count { let e = target[i] - (mu[i]); sum += e * e }
            return sum
        }

        let free = [options.refineOffset, options.refineGain, options.refineResolution]
        let steps = [5.0, 10.0, 5.0]   // initial simplex edges in the units above
        let (best, iterations, converged) = nelderMead(start: [0, 0, 0], free: free, steps: steps,
                                                       maxIterations: options.maxIterations,
                                                       tolerance: options.tolerance, f: rss)
        let d = (options.refineOffset ? best[0] : 0) * 1e-3
        let g = (options.refineGain ? best[1] : 0) * 1e-4
        let r = fileResolutionMnKaEV + (options.refineResolution ? best[2] : 0)
        return AxisRefinementResult(
            fileOffset: fileAxis.offset, fileScale: fileAxis.scale, fileResolutionMnKaEV: fileResolutionMnKaEV,
            offset: fileAxis.offset + d, scale: fileAxis.scale * (1 + g), resolutionMnKaEV: r,
            rssFile: rss([0, 0, 0]), rssRefined: rss(best), iterations: iterations, converged: converged,
            size: fileAxis.size)
    }

    /// Nelder-Mead (Nelder & Mead 1965; standard coefficients 1, 2, 0.5, 0.5) on the coordinates flagged
    /// `free`; the others stay at `start`.
    private static func nelderMead(
        start: [Double], free: [Bool], steps: [Double], maxIterations: Int, tolerance: Double,
        f: ([Double]) -> Double
    ) -> (best: [Double], iterations: Int, converged: Bool) {
        let idx = (0..<start.count).filter { free[$0] }
        guard !idx.isEmpty else { return (start, 0, true) }
        var simplex: [[Double]] = [start]
        for j in idx { var p = start; p[j] += steps[j]; simplex.append(p) }
        var values = simplex.map(f)
        var it = 0
        while it < maxIterations {
            it += 1
            let order = values.indices.sorted { values[$0] < values[$1] }
            simplex = order.map { simplex[$0] }; values = order.map { values[$0] }
            let spread = values.last! - values.first!
            if spread <= tolerance * max(values.first!, 1e-300) && it > 10 { return (simplex[0], it, true) }
            var centroid = [Double](repeating: 0, count: start.count)
            for p in simplex.dropLast() { for j in idx { centroid[j] += p[j] / Double(simplex.count - 1) } }
            func along(_ t: Double) -> [Double] {
                var p = centroid
                for j in idx { p[j] = centroid[j] + t * (simplex.last![j] - centroid[j]) }
                return p
            }
            let xr = along(-1), fr = f(xr)
            if fr < values[0] {
                let xe = along(-2), fe = f(xe)
                if fe < fr { simplex[simplex.count - 1] = xe; values[values.count - 1] = fe }
                else { simplex[simplex.count - 1] = xr; values[values.count - 1] = fr }
            } else if fr < values[values.count - 2] {
                simplex[simplex.count - 1] = xr; values[values.count - 1] = fr
            } else {
                let outside = fr < values.last!
                let xc = outside ? along(-0.5) : along(0.5), fc = f(xc)
                if fc < min(fr, values.last!) { simplex[simplex.count - 1] = xc; values[values.count - 1] = fc }
                else {
                    for k in 1..<simplex.count {
                        for j in idx { simplex[k][j] = simplex[0][j] + 0.5 * (simplex[k][j] - simplex[0][j]) }
                        values[k] = f(simplex[k])
                    }
                }
            }
        }
        let b = values.indices.min { values[$0] < values[$1] }!
        return (simplex[b], it, false)
    }
}
