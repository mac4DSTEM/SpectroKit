//
//  QuantificationPolicy.swift
//  Role: The choices behind a pooled quantification that the library made rather than took from the reference, as values with
//        the library's choice as the default. `FitPolicy` shapes the spectrum fit, `AbundancePolicy` the step from nets to
//        at% and its uncertainty terms. Since 0.5.0.
//
//  A policy is NOT part of `QuantificationMethod` (its canonical JSON and hash stay what they were for every method recorded
//  before). A non-default policy is named in the result's footer, one line, so a number never travels without the choice that
//  made it; the default adds no line.
//

import Foundation
import SpectroCore

/// The four layers of the silicon-drift-detector efficiency model (`eps(E)`): gold, aluminium, a silicon dead layer, and the
/// active silicon. The default is the generic SDD model's, not any one detector's calibration.
public nonisolated struct DetectorLayers: Sendable, Equatable, Codable {
    /// Gold contact layer, nm. Default 0 (EPQ `getDefaultSDDProperties`). More gold absorbs low-energy X-rays more.
    public var goldNm: Double
    /// Aluminium layer, nm. Default 10 (EPQ `getDefaultSDDProperties`). The Al K edge (1.560 keV) lies between Mg K alpha (1.254) and
    /// Si K alpha (1.740 keV), so a thicker layer absorbs Si K alpha more and lowers the computed k_Mg / k_Si (measured).
    public var aluminiumNm: Double
    /// Silicon dead layer in front of the active volume, micrometres. Default 0 (EPQ `getDefaultSDDProperties`). The Si K edge
    /// (1.839 keV) lies above both Mg and Si K alpha, so a thicker one raises the computed k_Mg / k_Si (measured).
    public var deadLayerMicrons: Double
    /// Active silicon thickness, micrometres. Default 450 (EPQ `getDefaultSDDProperties`). A thinner one lets
    /// more high-energy X-rays pass undetected, lowering the efficiency there.
    public var siliconMicrons: Double

    public init(goldNm: Double = 0, aluminiumNm: Double = 10, deadLayerMicrons: Double = 0, siliconMicrons: Double = 450) {
        self.goldNm = goldNm; self.aluminiumNm = aluminiumNm
        self.deadLayerMicrons = deadLayerMicrons; self.siliconMicrons = siliconMicrons
    }

    /// Au 0 nm, Al 10 nm, Si dead layer 0 µm, Si 450 µm.
    public static let `default` = DetectorLayers()
}

/// The optional detector Si dead-layer term of the EDX continuum (`FitPolicy.continuumDeadLayer`): the continuum form is multiplied
/// by the dead layer's transmission exp(-mu_Si(E) rho_Si t) (FFAST mu/rho, rho_Si 2.33 g/cm^3), which steps down at the Si K edge
/// (1.839 keV). A physical factor with one parameter, not a polynomial split. The thickness is typed (`microns`) or fitted in
/// `0...maximumMicrons` (`microns` nil). No reference models it (eXSpy has no detector efficiency); planted truth only.
public nonisolated struct ContinuumDeadLayer: Sendable, Equatable, Codable {
    /// The typed thickness, micrometres; nil fits it. A typed thickness enters every fit, the energy-axis refinement included; a
    /// fitted one is fitted after the refinement, which runs without it, so typing a fitted value back on an unlocked axis can
    /// give a different axis. It adds to `DetectorLayers.deadLayerMicrons` when `continuumEfficiency` is set as well.
    public var microns: Double?
    /// Upper end of the fitted thickness, micrometres (unused when `microns` is typed). Default 1.
    public var maximumMicrons: Double

    public init(microns: Double? = nil, maximumMicrons: Double = 1) {
        self.microns = microns; self.maximumMicrons = maximumMicrons
    }

    /// A typed thickness, micrometres.
    public static func given(microns: Double) -> ContinuumDeadLayer { ContinuumDeadLayer(microns: microns) }
    /// The thickness fitted in `0...maximumMicrons`.
    public static func fitted(maximumMicrons: Double = 1) -> ContinuumDeadLayer { ContinuumDeadLayer(maximumMicrons: maximumMicrons) }
}

/// What the library decided about the spectrum fit.
public nonisolated struct FitPolicy: Sendable, Equatable, Codable {
    /// Lower end of the fitted range, keV. Default 0.2: it keeps the zero-energy noise peak out (a stated choice, not a measurement).
    public var fitFromKeV: Double
    /// The default upper end of the fitted range is `min(axis end, beam energy, this)`, keV. Default 20, the width the continuum's
    /// orders were measured on: fitting the same form to the end of an 80 keV axis biased a weak line by -8 % on a synthetic spectrum.
    /// A longer range is `QuantificationMethod.fitToKeV`.
    public var defaultUpperLimitKeV: Double
    /// Polynomial order of each continuum segment, one more entry than `continuumEdges`. Default (9, 5), measured on one synthetic
    /// generator; lower orders left a misfit of up to 10 sigma at 0.2-0.5 keV there.
    public var continuumOrders: [Int]
    /// Energies, ascending, keV, where the continuum may step (absorption edges). Default the Al K edge, 1.5596 keV.
    public var continuumEdges: [Double]
    /// Bernstein basis with non-negative coefficients (the continuum cannot go negative). False: free-sign monomials.
    public var continuumNonNegative: Bool
    /// How the continuum steps at each edge. Default `.broadened`: the step blurred by the detector resolution, as a measured edge
    /// is. On a pure Al spectrum (Titan, Super-X) the sharp step left the model 39 % above the data in 1.65-2.2 keV, the broadened
    /// one 19 %; on a synthetic Al film with a broadened edge a weak Si K-alpha read -38.7 % sharp and -25.4 % broadened.
    /// `.sharp` is the form before `.broadened` became the default, value for value; a stored policy without the field reads it.
    public var continuumEdgeStep: ContinuumEdgeStep
    /// A detector efficiency multiplying the whole continuum form (its low-energy roll-off modelled instead of absorbed in the
    /// polynomial). Default nil: the Kramers-only form.
    public var continuumEfficiency: DetectorLayers?
    /// The detector Si dead-layer term of the continuum, typed or fitted (`ContinuumDeadLayer`); it multiplies
    /// `continuumEfficiency` when both are set. Default nil: off. It is not neutral: on the planted pool without a dead layer
    /// (`eds-absorption-truth.json`) a fitted thickness reads 0.21 um and moves Si K-alpha by -2.3 sigma (the step takes up part of
    /// the sample-side continuum misfit above the Al K edge); measured with sum peaks off, on the fit without the sum/escape model.
    /// A typed 0 is the default fit exactly.
    public var continuumDeadLayer: ContinuumDeadLayer?
    /// Fit a Si-escape copy of every line group above the Si K edge with an area of its own. Default true; false is the reference's.
    public var escapePeaks: Bool
    /// An opt-in low-energy tail on every line of the fit (`LineTail`). Default nil: Gaussians, every number unchanged.
    public var lineTail: LineTail?
    /// Largest order of the whole-range polynomial background (`QuantificationMethod.polynomialOrder` is clamped to 0...this). Default 8.
    public var maximumPolynomialOrder: Int
    /// Poisson maximum likelihood: iteration cap, tolerance and the floor of the model. Default 200, 1e-9, 1e-6.
    public var irls: IRLSSettings
    /// A line group whose Si-escape area exceeds this fraction of its parent is flagged in the fit's warnings. Default 0.05, a
    /// sanity bound; the Si escape of a silicon detector is about 1 % at Cu K alpha.
    public var escapeRatioWarning: Double
    /// The energy-axis refinement on the pooled spectrum: which of offset, gain and width, the cap, the tolerance and the width bounds.
    public var axisRefinement: AxisRefinementSettings
    /// Sum (pile-up) peaks of the four strongest alpha lines in the pooled fit (`EDSSumEscapeFit`), when the caller passes no
    /// `PooledQuantificationInput.sumEscape`. Default `.whenSignificant`: kept when the strongest line's self pair is
    /// `sumPeakSignificance` sigma above 0. `.off` is the fit before sum peaks were the default (one Gaussian per line, no sum peaks,
    /// exSpy's model): its numbers are bit for bit the old ones; as a non-default policy it adds the footer line
    /// `policy (non-default): fit.sumPeaks = off`.
    public var sumPeaks: SumPeakRule
    /// The c / sigma_c a pile-up coefficient needs under `.whenSignificant`, sigma_c scaled by the square root of the self-pair fit's
    /// reduced chi2 (or deviance) when that is above 1. Default 3: a stated choice, not a measured false-keep rate (c is clipped at 0,
    /// and the rate holds only for a model that fits; a real line under the self pair is read as pile-up whatever the level).
    public var sumPeakSignificance: Double
    /// The table tying each family's sub-lines to its alpha line (`EDSLineWeights`). Default `.exspy`, the parity path; `.epq` ties the K
    /// families at NIST EPQ's Kβ weights (Al Kβ 0.0315 of Kα against eXSpy's 0.0132). A stored policy without the field reads `.exspy`.
    public var lineWeights: EDSLineWeights

    public init(fitFromKeV: Double = 0.2, defaultUpperLimitKeV: Double = 20, continuumOrders: [Int] = [9, 5],
                continuumEdges: [Double] = [FitPolicy.alKEdgeKeV], continuumNonNegative: Bool = true,
                continuumEfficiency: DetectorLayers? = nil, escapePeaks: Bool = true, maximumPolynomialOrder: Int = 8,
                irls: IRLSSettings = IRLSSettings(), escapeRatioWarning: Double = 0.05,
                axisRefinement: AxisRefinementSettings = AxisRefinementSettings(),
                lineTail: LineTail? = nil, sumPeaks: SumPeakRule = .whenSignificant, sumPeakSignificance: Double = 3,
                continuumEdgeStep: ContinuumEdgeStep = .broadened, continuumDeadLayer: ContinuumDeadLayer? = nil,
                lineWeights: EDSLineWeights = .exspy) {
        self.continuumDeadLayer = continuumDeadLayer
        self.lineWeights = lineWeights
        self.fitFromKeV = fitFromKeV; self.defaultUpperLimitKeV = defaultUpperLimitKeV
        self.continuumOrders = continuumOrders; self.continuumEdges = continuumEdges
        self.continuumNonNegative = continuumNonNegative; self.continuumEfficiency = continuumEfficiency
        self.escapePeaks = escapePeaks; self.maximumPolynomialOrder = maximumPolynomialOrder
        self.irls = irls; self.escapeRatioWarning = escapeRatioWarning; self.axisRefinement = axisRefinement
        self.lineTail = lineTail; self.sumPeaks = sumPeaks; self.sumPeakSignificance = sumPeakSignificance
        self.continuumEdgeStep = continuumEdgeStep
    }

    /// The fit before sum peaks were the default (one Gaussian per line, no sum peaks): exSpy's line model. Its continuum is the
    /// default one (exSpy's polynomial has no edge at all), broadened step included.
    public static let exspyEquivalent = FitPolicy(sumPeaks: .off)

    private enum CodingKeys: String, CodingKey {
        case fitFromKeV, defaultUpperLimitKeV, continuumOrders, continuumEdges, continuumNonNegative, continuumEfficiency, escapePeaks,
             lineTail, maximumPolynomialOrder, irls, escapeRatioWarning, axisRefinement, sumPeaks, sumPeakSignificance, continuumEdgeStep,
             continuumDeadLayer, lineWeights
    }

    /// Every non-optional field is written, `sumPeaks`, `sumPeakSignificance`, `continuumEdgeStep` and `lineWeights` included,
    /// default or not. An optional that is nil (`continuumEfficiency`, `lineTail`, `continuumDeadLayer`) is left out, so the
    /// default policy has no `continuumDeadLayer` key. Key order is not fixed here; `QuantificationPolicy.canonicalJSON` sorts it.
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(fitFromKeV, forKey: .fitFromKeV)
        try c.encode(defaultUpperLimitKeV, forKey: .defaultUpperLimitKeV)
        try c.encode(continuumOrders, forKey: .continuumOrders)
        try c.encode(continuumEdges, forKey: .continuumEdges)
        try c.encode(continuumNonNegative, forKey: .continuumNonNegative)
        try c.encodeIfPresent(continuumEfficiency, forKey: .continuumEfficiency)
        try c.encode(escapePeaks, forKey: .escapePeaks)
        try c.encodeIfPresent(lineTail, forKey: .lineTail)
        try c.encode(maximumPolynomialOrder, forKey: .maximumPolynomialOrder)
        try c.encode(irls, forKey: .irls)
        try c.encode(escapeRatioWarning, forKey: .escapeRatioWarning)
        try c.encode(axisRefinement, forKey: .axisRefinement)
        try c.encode(sumPeaks, forKey: .sumPeaks)
        try c.encode(sumPeakSignificance, forKey: .sumPeakSignificance)
        try c.encode(continuumEdgeStep, forKey: .continuumEdgeStep)
        try c.encodeIfPresent(continuumDeadLayer, forKey: .continuumDeadLayer)
        try c.encode(lineWeights, forKey: .lineWeights)
    }

    /// A field added after policies were first stored reads, when its key is missing, the value that policy was run with: `sumPeaks`
    /// `.off` (the fit before sum peaks were the default; it gets the non-default footer line), `sumPeakSignificance` 3,
    /// `continuumEdgeStep` `.sharp`, `lineWeights` `.exspy`. A missing optional (`continuumEfficiency`, `lineTail`,
    /// `continuumDeadLayer`) reads nil. Every other field is required.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(fitFromKeV: try c.decode(Double.self, forKey: .fitFromKeV),
                  defaultUpperLimitKeV: try c.decode(Double.self, forKey: .defaultUpperLimitKeV),
                  continuumOrders: try c.decode([Int].self, forKey: .continuumOrders),
                  continuumEdges: try c.decode([Double].self, forKey: .continuumEdges),
                  continuumNonNegative: try c.decode(Bool.self, forKey: .continuumNonNegative),
                  continuumEfficiency: try c.decodeIfPresent(DetectorLayers.self, forKey: .continuumEfficiency),
                  escapePeaks: try c.decode(Bool.self, forKey: .escapePeaks),
                  maximumPolynomialOrder: try c.decode(Int.self, forKey: .maximumPolynomialOrder),
                  irls: try c.decode(IRLSSettings.self, forKey: .irls),
                  escapeRatioWarning: try c.decode(Double.self, forKey: .escapeRatioWarning),
                  axisRefinement: try c.decode(AxisRefinementSettings.self, forKey: .axisRefinement),
                  lineTail: try c.decodeIfPresent(LineTail.self, forKey: .lineTail),
                  sumPeaks: try c.decodeIfPresent(SumPeakRule.self, forKey: .sumPeaks) ?? .off,
                  sumPeakSignificance: try c.decodeIfPresent(Double.self, forKey: .sumPeakSignificance) ?? 3,
                  continuumEdgeStep: try c.decodeIfPresent(ContinuumEdgeStep.self, forKey: .continuumEdgeStep) ?? .sharp,
                  continuumDeadLayer: try c.decodeIfPresent(ContinuumDeadLayer.self, forKey: .continuumDeadLayer),
                  lineWeights: try c.decodeIfPresent(EDSLineWeights.self, forKey: .lineWeights) ?? .exspy)
    }

    /// The Al K absorption edge, keV (X-ray Data Booklet, Table 1-1): the default continuum split.
    public static let alKEdgeKeV = 1.5596

    public static let `default` = FitPolicy()

    /// Why this policy cannot run, in words; nil when it can. A quantification with such a policy is refused with this sentence.
    public var problem: String? {
        if !(fitFromKeV.isFinite && fitFromKeV >= 0) { return "The fit start (\(fitFromKeV) keV) must be a number of 0 or more." }
        if !(defaultUpperLimitKeV.isFinite && defaultUpperLimitKeV > fitFromKeV) {
            return "The default upper fit limit (\(defaultUpperLimitKeV) keV) must lie above the fit start (\(fitFromKeV) keV)."
        }
        if continuumOrders.count != continuumEdges.count + 1 { return "The continuum needs one polynomial order per segment: \(continuumEdges.count + 1) for \(continuumEdges.count) edge(s), got \(continuumOrders.count)." }
        if continuumOrders.contains(where: { $0 < 0 }) { return "A continuum order must be 0 or more." }
        if !zip(continuumEdges, continuumEdges.dropFirst()).allSatisfy({ $0 < $1 }) { return "The continuum edges must ascend." }
        if let d = continuumDeadLayer {
            if let t = d.microns, !(t.isFinite && t >= 0) { return "The typed Si dead layer (\(t) \u{00B5}m) must be 0 or more." }
            if d.microns == nil, !(d.maximumMicrons.isFinite && d.maximumMicrons > 0) {
                return "The upper end of the fitted Si dead layer (\(d.maximumMicrons) \u{00B5}m) must be positive."
            }
        }
        if maximumPolynomialOrder < 0 { return "The largest polynomial order must be 0 or more." }
        if !(escapeRatioWarning.isFinite && escapeRatioWarning > 0) { return "The escape-ratio warning level must be positive." }
        if !(sumPeakSignificance.isFinite && sumPeakSignificance >= 0) { return "The sum-peak significance level must be a number of 0 or more." }
        if irls.maxIterations < 1 || !(irls.tolerance > 0) || !(irls.muFloor > 0) { return "The Poisson iteration needs a cap of 1 or more, a positive tolerance and a positive floor." }
        if axisRefinement.maxIterations < 1 || !(axisRefinement.tolerance > 0)
            || !(axisRefinement.minimumResolutionEV < axisRefinement.maximumResolutionEV) {
            return "The axis refinement needs a cap of 1 or more, a positive tolerance and a width range with its lower bound below its upper."
        }
        if !(axisRefinement.maximumOffsetShiftEV.isFinite && axisRefinement.maximumOffsetShiftEV > 0)
            || !(axisRefinement.maximumGainShift.isFinite && axisRefinement.maximumGainShift > 0) {
            return "The axis refinement needs a finite, positive bound on the offset shift and on the gain shift."
        }
        return nil
    }
}

/// What the library decided about the step from fitted nets to composition and its uncertainty terms.
public nonisolated struct AbundancePolicy: Sendable, Equatable, Codable {
    /// The element the k-free ratios and the k-factor reference are taken against when none is typed (`QuantificationMethod.kReference`):
    /// this one if it is quantified and measured, otherwise the element with the largest net. Default "Al"; nil always takes the largest net.
    public var fallbackReference: String?
    /// The silicon-drift-detector layers of the computed k-factors' efficiency. Default the generic SDD model's.
    public var detector: DetectorLayers
    /// The absorption correction iterates until the composition changes by less than this, percent. Default 1e-7: the sigma terms are
    /// finite differences of the composition, which a loop stopping at the reference's 0.5 % would put steps into.
    public var absorptionConvergencePercent: Double
    /// The absorption iteration gives up (the at% is refused) after this many passes. Default 200 (the reference's is 30).
    public var absorptionMaxIterations: Int
    /// The counting term of the at% sigma is a central difference with a step of this fraction of each net (at least 1e-9 counts).
    /// Default 0.01.
    public var derivativeRelativeStep: Double
    /// Fewer than two lines above Cliff-Lorimer's intensity floor: refuse the at% (default), or report 100 % for the one line as the
    /// reference does.
    public var singleLine: SingleLineRule

    public init(fallbackReference: String? = "Al", detector: DetectorLayers = DetectorLayers(),
                absorptionConvergencePercent: Double = 1e-7, absorptionMaxIterations: Int = 200,
                derivativeRelativeStep: Double = 0.01, singleLine: SingleLineRule = .refuse) {
        self.fallbackReference = fallbackReference; self.detector = detector
        self.absorptionConvergencePercent = absorptionConvergencePercent
        self.absorptionMaxIterations = absorptionMaxIterations
        self.derivativeRelativeStep = derivativeRelativeStep; self.singleLine = singleLine
    }

    public static let `default` = AbundancePolicy()

    public var problem: String? {
        if !(absorptionConvergencePercent.isFinite && absorptionConvergencePercent > 0) { return "The absorption convergence level must be positive." }
        if absorptionMaxIterations < 1 { return "The absorption iteration needs a cap of 1 or more." }
        if !(derivativeRelativeStep.isFinite && derivativeRelativeStep > 0) { return "The derivative step must be positive." }
        if detector.goldNm < 0 || detector.aluminiumNm < 0 || detector.deadLayerMicrons < 0 || !(detector.siliconMicrons > 0) {
            return "The detector layers must be 0 or more, with a positive active silicon thickness."
        }
        return nil
    }
}

/// Whether the pooled fit models sum (pile-up) peaks (`FitPolicy.sumPeaks`).
///
/// Why it is the default: on the public synthetic AlMgSi demo (planted truth: the simulation recipe of `sim_edx.py` v2.0, not a
/// measurement) the fit without sum peaks read noise-free Si K-alpha 15-18 % low on the Al-rich map and fixture pools (57 % on
/// the highest-rate pool, 8 % on the precipitate pool) and held a planted Cu K-alpha at 0 at high rate, because the Al+Al sum peak
/// (2.97 keV) and its neighbours pull the continuum above the Al K edge. With sum peaks the same pools read Si within 4 % (8 % at the
/// highest rate) and recover the Cu (`DemoEDXPoolTests`). On the Poisson counts of every demo pool the self pair passes the test
/// (`DemoEDXPoolTests.reducedChiSquareOnThePoissonCounts` pins it); on the one noise-free spectrum without pile-up tested
/// (`eds-unlisted-sim.json`) the default keeps the fit without sum peaks bit for bit.
/// What it cannot tell apart: a real line under the self pair (Ar K-alpha 2.957 or Ag L-alpha 2.984 keV under Al+Al 2.973 keV) is
/// read as pile-up; the footer and the warnings name the alpha lines within one FWHM of it when the sum peaks are kept.
/// The Al K-alpha tail is NOT part of this rule: fitted together with the sum peaks on the demo's Poisson pools (256 to 2 897
/// pixels) it read 0 to a third of the planted fraction and left Mg K-alpha up to 25 % low on the map pools, so it is a detector
/// calibration (`FitPolicy.lineTail`, measured once with `TailEstimate` on a high-count spectrum).
public nonisolated enum SumPeakRule: String, Sendable, Codable, CaseIterable {
    /// No sum peaks: one Gaussian per line, the fit as it ran before (exSpy's line model).
    case off
    /// Test the sum peak of the strongest line with itself (Al K-alpha + Al K-alpha in an Al alloy) alone; when its pile-up coefficient
    /// is `FitPolicy.sumPeakSignificance` sigma above 0 (`significance(_:misfit:)`), fit and keep the sum peaks of the four strongest lines; otherwise the default
    /// fit, bit for bit. Either way the footer says which, with the number. The self pair is the test because the cross pairs can
    /// absorb an unlisted line at E_i + E_j: on a synthetic spectrum with no pile-up and Cu, Ga and Ge left out of the list, the
    /// four-parent model kept c at 48 sigma (Ni K-alpha + O K-alpha on Cu K-alpha) while the Si self pair read 0.
    case whenSignificant
    /// Fit and keep the sum peaks whatever the data say.
    case always

    /// c / (sigma_c sqrt(max(misfit, 1))) of a sum-peak fit: NaN when no pair lies in the fitted range (nothing was tested) or there
    /// is no sigma, 0 when c is held at 0. sigma_c is counting statistics (Var(data) = model); `misfit` (the fit's reduced chi2 or
    /// deviance) scales it, so a misfit near E_i + E_j does not pass as pile-up on a fit that is far from chi2_red = 1.
    package static func significance(_ r: SumEscapeResult, misfit: Double) -> Double {
        guard let c = r.sumCoefficient, !r.sumPeaks.isEmpty else { return .nan }
        if r.sumCoefficientAtBound || c == 0 { return 0 }
        guard let s = r.sumCoefficientSigma, s > 0, s.isFinite else { return .nan }
        let scale = misfit.isFinite ? max(misfit, 1).squareRoot() : 1
        return c / (s * scale)
    }

    /// The alpha lines of elements not in `listed` that lie within one FWHM of `energy`: a real line there is read as the sum peak.
    package static func coincidentLines(energy: Double, resolutionMnKaEV: Double, listed: [String]) -> [XRayLine] {
        let w = XRayLines.fwhm(resolutionMnKaEV: resolutionMnKaEV, atEnergy: energy) ?? 0.13
        return XRayLines.all.filter {
            ["Ka", "La", "Ma"].contains($0.name) && !XRayLines.notRealLines.contains($0.element) && !listed.contains($0.element)
                && abs($0.energy - energy) <= w
        }.sorted { abs($0.energy - energy) < abs($1.energy - energy) }
    }
}

/// Fewer than two lines above Cliff-Lorimer's intensity floor.
public nonisolated enum SingleLineRule: String, Sendable, Codable {
    /// Refuse the at% (a 100 % for one element is a property of dose and the floor, not of the specimen).
    case refuse
    /// Report 100 % for the one line above the floor and 0 for the rest, as the reference does.
    case exspyHundredPercent
}

/// The policy of a pooled quantification: `PooledQuantificationInput.policy`.
public nonisolated struct QuantificationPolicy: Sendable, Equatable, Codable {
    /// The spectrum fit's choices. Default `FitPolicy.default` (each field's default and origin are on `FitPolicy`).
    public var fit: FitPolicy
    /// The step from nets to composition and its uncertainty terms. Default `AbundancePolicy.default` (each field's default and
    /// origin are on `AbundancePolicy`).
    public var abundance: AbundancePolicy

    public init(fit: FitPolicy = .default, abundance: AbundancePolicy = .default) {
        self.fit = fit; self.abundance = abundance
    }

    public static let `default` = QuantificationPolicy()

    public var isDefault: Bool { self == .default }

    /// Why this policy cannot run; nil when it can.
    public var problem: String? { fit.problem ?? abundance.problem }

    /// Sorted-key JSON; encoding a decoded policy gives the same string.
    public var canonicalJSON: String {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return String(decoding: try! e.encode(self), as: UTF8.self)
    }

    /// The footer line for a non-default policy: every field that differs from the default, `path = value`, sorted by path. A field
    /// that is nil (`fallbackReference`, `continuumEfficiency`) while the default has a value is named as `path = nil`; an array is
    /// written `[5, 4]`, a Bool `true` or `false`. nil for the default.
    public var footerLine: String? {
        guard !isDefault else { return nil }
        let diffs = PolicyDifference.paths(try! JSONSerialization.jsonObject(with: JSONEncoder().encode(self)),
                                           try! JSONSerialization.jsonObject(with: JSONEncoder().encode(QuantificationPolicy.default)))
        return "policy (non-default): " + diffs.map { "\($0.path) = \($0.value)" }.joined(separator: ", ")
    }
}

/// The fields at which two encoded policies differ, one line each: used by the footer lines of `QuantificationPolicy` and
/// `ProposerPolicy`. An optional that is nil encodes as an absent key, so a key present on one side only is a difference whose
/// absent side reads `nil`.
package nonisolated enum PolicyDifference {
    package static func paths(_ mine: Any?, _ base: Any?, _ path: String = "") -> [(path: String, value: String)] {
        if let a = mine as? [String: Any], let b = base as? [String: Any] {
            return Set(a.keys).union(b.keys).sorted().flatMap { k in
                paths(a[k], b[k], path.isEmpty ? k : path + "." + k)
            }
        }
        let r = render(mine)
        return r == render(base) ? [] : [(path, r)]
    }

    package static func render(_ v: Any?) -> String {
        switch v {
        case nil: return "nil"
        case let d as [String: Any]: return "{" + d.keys.sorted().map { "\($0): \(render(d[$0]))" }.joined(separator: ", ") + "}"
        case let a as [Any]: return "[" + a.map { render($0) }.joined(separator: ", ") + "]"
        case let n as NSNumber:
            return String(cString: n.objCType) == "c" ? (n.boolValue ? "true" : "false") : "\(n)"
        default: return "\(v!)"
        }
    }
}
