//
//  EnergyAxisRefinement.swift
//  Role: Refine the energy axis on the POOLED spectrum: an offset correction, a
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
import SpectroCore

/// Which of the energy axis's offset, gain and the detector width the refinement adjusts, and how long it searches. Defaults are the
/// library's choice (all three, 600 simplex iterations, tolerance 1e-12, widths between 20 and 500 eV, offset within +-200 eV and
/// gain within +-5 % of the file's).
///
/// THE OFFSET AND GAIN BOUNDS (0.13.2). A spectrum with one strong line fixes two numbers (its channel and its width in channels)
/// against three parameters, so the residual has a flat valley along which offset, gain and width trade; the simplex then walks
/// until a bound stops it (a synthetic one-line spectrum went to gain +444 %, offset -6.6 keV). +-200 eV and +-5 % are a stated
/// choice, far outside a working detector calibration (the tests plant up to +-12 eV and 0.2 %), and they keep the fitted
/// energies near or above zero from the 0.2 keV start. A refinement that ends against any bound is not a minimum: it is reported not
/// converged, with the parameter named, and the pooled fit uses the file's axis.
/// A policy stored before 0.13.2 has no offset or gain key and reads these defaults, not "no bound": unlike the rule for other new
/// `FitPolicy` keys, a re-run can differ from its stored run, and only where that run walked against the new bounds.
public nonisolated struct AxisRefinementSettings: Sendable, Equatable, Codable {
    /// Adjust the offset. Default true; false keeps the file's.
    public var refineOffset = true
    /// Adjust the gain (relative channel width). Default true.
    public var refineGain = true
    /// Adjust the detector width (FWHM at Mn K alpha). Default true.
    public var refineResolution = true
    /// The simplex iteration cap. Default 600.
    public var maxIterations = 600
    /// Stop when the simplex's RSS spread is below this fraction of the RSS. Default 1e-12.
    public var tolerance = 1e-12
    /// A trial width at or below this, eV, is rejected (the residual is taken as infinite). Default 20.
    public var minimumResolutionEV = 20.0
    /// A trial width at or above this, eV, is rejected. Default 500.
    public var maximumResolutionEV = 500.0
    /// A trial offset shift whose size is at or above this, eV, is rejected. Default 200.
    public var maximumOffsetShiftEV = 200.0
    /// A trial relative gain shift whose size is at or above this is rejected. Default 0.05 (5 %).
    public var maximumGainShift = 0.05

    public init(refineOffset: Bool = true, refineGain: Bool = true, refineResolution: Bool = true, maxIterations: Int = 600,
                tolerance: Double = 1e-12, minimumResolutionEV: Double = 20, maximumResolutionEV: Double = 500,
                maximumOffsetShiftEV: Double = 200, maximumGainShift: Double = 0.05) {
        self.refineOffset = refineOffset; self.refineGain = refineGain; self.refineResolution = refineResolution
        self.maxIterations = maxIterations; self.tolerance = tolerance
        self.minimumResolutionEV = minimumResolutionEV; self.maximumResolutionEV = maximumResolutionEV
        self.maximumOffsetShiftEV = maximumOffsetShiftEV; self.maximumGainShift = maximumGainShift
    }

    private enum CodingKeys: String, CodingKey {
        case refineOffset, refineGain, refineResolution, maxIterations, tolerance, minimumResolutionEV, maximumResolutionEV,
             maximumOffsetShiftEV, maximumGainShift
    }

    /// A policy stored before 0.13.2 has no offset or gain bound: it reads the defaults (see the type's note).
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AxisRefinementSettings()
        self.init(refineOffset: try c.decode(Bool.self, forKey: .refineOffset), refineGain: try c.decode(Bool.self, forKey: .refineGain),
                  refineResolution: try c.decode(Bool.self, forKey: .refineResolution),
                  maxIterations: try c.decode(Int.self, forKey: .maxIterations), tolerance: try c.decode(Double.self, forKey: .tolerance),
                  minimumResolutionEV: try c.decode(Double.self, forKey: .minimumResolutionEV),
                  maximumResolutionEV: try c.decode(Double.self, forKey: .maximumResolutionEV),
                  maximumOffsetShiftEV: try c.decodeIfPresent(Double.self, forKey: .maximumOffsetShiftEV) ?? defaults.maximumOffsetShiftEV,
                  maximumGainShift: try c.decodeIfPresent(Double.self, forKey: .maximumGainShift) ?? defaults.maximumGainShift)
    }
}

public nonisolated struct AxisRefinementResult: Sendable, Equatable {
    // The file's values, kept beside the refined ones.
    package let fileOffset: Double
    package let fileScale: Double
    package let fileResolutionMnKaEV: Double
    package let offset: Double
    package let scale: Double
    public let resolutionMnKaEV: Double
    package let rssFile: Double
    package let rssRefined: Double
    package let iterations: Int
    /// The simplex met its tolerance AND no refined parameter ended against its bound.
    package let converged: Bool
    /// The refined parameters that ended against their bound ("offset", "gain", "FWHM"), in that order; empty when none did.
    /// Not empty: the result is not a minimum of the residual and the pooled fit does not use it.
    public let parametersAtBound: [String]
    /// "gain +5.000 % (bound +-5 %)", one clause per parameter at its bound; empty when none is.
    package let boundText: String

    public var refinedAxis: EnergyAxis { EnergyAxis(offset: offset, scale: scale, size: size) }
    package let size: Int
    /// Offset correction in eV (refined - file).
    public var offsetShiftEV: Double { (offset - fileOffset) * 1000 }
    /// Relative gain correction (refined / file - 1).
    public var gainShift: Double { scale / fileScale - 1 }
}

package nonisolated enum EnergyAxisRefinement {

    package static func refine(
        counts: [Double], fileAxis: EnergyAxis, fileResolutionMnKaEV: Double, settings: FitSettings,
        options: AxisRefinementSettings = AxisRefinementSettings(),
        cancelled: @Sendable () -> Bool = SpectroCancellation.task,
        progress: (@Sendable (Double) -> Void)? = nil
    ) throws -> AxisRefinementResult {
        try SpectroCancellation.check(cancelled)
        guard counts.count == fileAxis.size else { throw EDSFitError.lengthMismatch }
        let channels = fileAxis.fitChannels(from: settings.fitFrom, to: settings.fitTo)
        guard !channels.isEmpty else { throw EDSFitError.noChannels }
        try EDSFit.validate(settings.referenceShapes, axis: fileAxis,
                            model: EDSLineModel.build(elements: settings.elements, axis: fileAxis, beamEnergy: settings.beamEnergy,
                                                      resolutionMnKaEV: fileResolutionMnKaEV, escapePeaks: settings.escapePeaks,
                                                      lineTail: settings.lineTail, lineWeights: settings.lineWeights))

        // Units: u0 = offset shift / 1 eV, u1 = gain shift / 1e-4, u2 = (R - R_file) / 1 eV.
        func rss(_ u: [Double]) -> Double {
            let d = (options.refineOffset ? u[0] : 0) * 1e-3
            let g = (options.refineGain ? u[1] : 0) * 1e-4
            let r = fileResolutionMnKaEV + (options.refineResolution ? u[2] : 0)
            guard r > options.minimumResolutionEV, r < options.maximumResolutionEV,
                  abs(d * 1000) < options.maximumOffsetShiftEV, abs(g) < options.maximumGainShift else { return .infinity }
            let axis = EnergyAxis(offset: fileAxis.offset + d, scale: fileAxis.scale * (1 + g), size: fileAxis.size)
            let model = EDSLineModel.build(elements: settings.elements, axis: axis, beamEnergy: settings.beamEnergy,
                                           resolutionMnKaEV: r, escapePeaks: settings.escapePeaks, lineTail: settings.lineTail,
                                           lineWeights: settings.lineWeights)
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
        let (best, iterations, converged) = try nelderMead(start: [0, 0, 0], free: free, steps: steps,
                                                           maxIterations: options.maxIterations,
                                                           tolerance: options.tolerance, f: rss,
                                                           cancelled: cancelled, progress: progress)
        let d = (options.refineOffset ? best[0] : 0) * 1e-3
        let g = (options.refineGain ? best[1] : 0) * 1e-4
        let r = fileResolutionMnKaEV + (options.refineResolution ? best[2] : 0)
        // A parameter within 1e-4 of its bound span of a bound ended against it (the simplex presses on a rejected region).
        var atBound: [String] = [], clauses: [String] = []
        func near(_ v: Double, _ lo: Double, _ hi: Double) -> Bool { min(v - lo, hi - v) <= 1e-4 * (hi - lo) }
        if options.refineOffset, near(d * 1000, -options.maximumOffsetShiftEV, options.maximumOffsetShiftEV) {
            atBound.append("offset")
            clauses.append(String(format: "offset %+.1f eV (bound \u{00B1}%g eV)", d * 1000, options.maximumOffsetShiftEV))
        }
        if options.refineGain, near(g, -options.maximumGainShift, options.maximumGainShift) {
            atBound.append("gain")
            clauses.append(String(format: "gain %+.3f %% (bound \u{00B1}%g %%)", g * 100, options.maximumGainShift * 100))
        }
        if options.refineResolution, near(r, options.minimumResolutionEV, options.maximumResolutionEV) {
            atBound.append("FWHM")
            clauses.append(String(format: "FWHM %.0f eV (bounds %g-%g eV)", r, options.minimumResolutionEV, options.maximumResolutionEV))
        }
        try SpectroCancellation.check(cancelled)
        progress?(1)
        return AxisRefinementResult(
            fileOffset: fileAxis.offset, fileScale: fileAxis.scale, fileResolutionMnKaEV: fileResolutionMnKaEV,
            offset: fileAxis.offset + d, scale: fileAxis.scale * (1 + g), resolutionMnKaEV: r,
            rssFile: rss([0, 0, 0]), rssRefined: rss(best), iterations: iterations, converged: converged && atBound.isEmpty,
            parametersAtBound: atBound, boundText: clauses.joined(separator: ", "),
            size: fileAxis.size)
    }

    /// Nelder-Mead (Nelder & Mead 1965; standard coefficients 1, 2, 0.5, 0.5) on the coordinates flagged
    /// `free`; the others stay at `start`.
    private static func nelderMead(
        start: [Double], free: [Bool], steps: [Double], maxIterations: Int, tolerance: Double,
        f: ([Double]) -> Double, cancelled: @Sendable () -> Bool, progress: (@Sendable (Double) -> Void)?
    ) throws -> (best: [Double], iterations: Int, converged: Bool) {
        let idx = (0..<start.count).filter { free[$0] }
        guard !idx.isEmpty else { return (start, 0, true) }
        var simplex: [[Double]] = [start]
        for j in idx { var p = start; p[j] += steps[j]; simplex.append(p) }
        var values = simplex.map(f)
        var it = 0
        while it < maxIterations {
            // One iteration is a handful of fits: the boundary the cancel check and the progress sit on (progress counts
            // iterations against the cap; the loop usually converges earlier, and the caller ends at 1).
            try SpectroCancellation.check(cancelled)
            progress?(Double(it) / Double(max(maxIterations, 1)))
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
