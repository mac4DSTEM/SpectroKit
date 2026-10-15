//
//  QuantificationPolicy.swift
//  Role: The choices behind a pooled quantification that the library made rather than took from the reference, as values with
//        the library's choice as the default. `FitPolicy` shapes the spectrum fit, `AbundancePolicy` the step from nets to
//        at% and its uncertainty terms. Registered: docs/generality-0.5.0-registration.md (F1-F13, Q3-Q7).
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
    public var goldNm: Double
    public var aluminiumNm: Double
    public var deadLayerMicrons: Double
    public var siliconMicrons: Double

    public init(goldNm: Double = 0, aluminiumNm: Double = 10, deadLayerMicrons: Double = 0, siliconMicrons: Double = 450) {
        self.goldNm = goldNm; self.aluminiumNm = aluminiumNm
        self.deadLayerMicrons = deadLayerMicrons; self.siliconMicrons = siliconMicrons
    }

    /// Au 0 nm, Al 10 nm, Si dead layer 0 µm, Si 450 µm.
    public static let `default` = DetectorLayers()
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
    /// A detector efficiency multiplying the whole continuum form (its low-energy roll-off modelled instead of absorbed in the
    /// polynomial). Default nil: the Kramers-only form.
    public var continuumEfficiency: DetectorLayers?
    /// Fit a Si-escape copy of every line group above the Si K edge with an area of its own. Default true; false is the reference's.
    public var escapePeaks: Bool
    /// Largest order of the whole-range polynomial background (`QuantificationMethod.polynomialOrder` is clamped to 0...this). Default 8.
    public var maximumPolynomialOrder: Int
    /// Poisson maximum likelihood: iteration cap, tolerance and the floor of the model. Default 200, 1e-9, 1e-6.
    public var irls: IRLSSettings
    /// A line group whose Si-escape area exceeds this fraction of its parent is flagged in the fit's warnings. Default 0.05, a
    /// sanity bound; the Si escape of a silicon detector is about 1 % at Cu K alpha.
    public var escapeRatioWarning: Double
    /// The energy-axis refinement on the pooled spectrum: which of offset, gain and width, the cap, the tolerance and the width bounds.
    public var axisRefinement: AxisRefinementSettings

    public init(fitFromKeV: Double = 0.2, defaultUpperLimitKeV: Double = 20, continuumOrders: [Int] = [9, 5],
                continuumEdges: [Double] = [FitPolicy.alKEdgeKeV], continuumNonNegative: Bool = true,
                continuumEfficiency: DetectorLayers? = nil, escapePeaks: Bool = true, maximumPolynomialOrder: Int = 8,
                irls: IRLSSettings = IRLSSettings(), escapeRatioWarning: Double = 0.05,
                axisRefinement: AxisRefinementSettings = AxisRefinementSettings()) {
        self.fitFromKeV = fitFromKeV; self.defaultUpperLimitKeV = defaultUpperLimitKeV
        self.continuumOrders = continuumOrders; self.continuumEdges = continuumEdges
        self.continuumNonNegative = continuumNonNegative; self.continuumEfficiency = continuumEfficiency
        self.escapePeaks = escapePeaks; self.maximumPolynomialOrder = maximumPolynomialOrder
        self.irls = irls; self.escapeRatioWarning = escapeRatioWarning; self.axisRefinement = axisRefinement
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
        if maximumPolynomialOrder < 0 { return "The largest polynomial order must be 0 or more." }
        if !(escapeRatioWarning.isFinite && escapeRatioWarning > 0) { return "The escape-ratio warning level must be positive." }
        if irls.maxIterations < 1 || !(irls.tolerance > 0) || !(irls.muFloor > 0) { return "The Poisson iteration needs a cap of 1 or more, a positive tolerance and a positive floor." }
        if axisRefinement.maxIterations < 1 || !(axisRefinement.tolerance > 0)
            || !(axisRefinement.minimumResolutionEV < axisRefinement.maximumResolutionEV) {
            return "The axis refinement needs a cap of 1 or more, a positive tolerance and a width range with its lower bound below its upper."
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

/// Fewer than two lines above Cliff-Lorimer's intensity floor.
public nonisolated enum SingleLineRule: String, Sendable, Codable {
    /// Refuse the at% (a 100 % for one element is a property of dose and the floor, not of the specimen).
    case refuse
    /// Report 100 % for the one line above the floor and 0 for the rest, as the reference does.
    case exspyHundredPercent
}

/// The policy of a pooled quantification: `PooledQuantificationInput.policy`.
public nonisolated struct QuantificationPolicy: Sendable, Equatable, Codable {
    public var fit: FitPolicy
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

    /// The footer line for a non-default policy: every field that differs from the default, `path = value`. nil for the default.
    public var footerLine: String? {
        guard !isDefault else { return nil }
        func flat(_ v: Any, _ path: String, _ out: inout [String: String]) {
            if let d = v as? [String: Any] { for (k, x) in d { flat(x, path.isEmpty ? k : path + "." + k, &out) } }
            else { out[path] = "\(v)" }
        }
        func fields(_ p: QuantificationPolicy) -> [String: String] {
            var out: [String: String] = [:]
            let obj = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(p))
            flat(obj, "", &out)
            return out
        }
        let mine = fields(self), base = fields(.default)
        let diffs = mine.keys.sorted().filter { mine[$0] != base[$0] }.map { "\($0) = \(mine[$0]!)" }
        return "policy (non-default): " + diffs.joined(separator: ", ")
    }
}
