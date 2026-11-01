//
//  ElementProposer.swift
//  Role: Propose elements from a pooled spectrum. It RETURNS candidates and never touches an element list: nothing is added silently.
//        Since 0.11.0 the search is the identification loop of docs/design/auto-id-tem.md, written from the published
//        method (Newbury and Ritchie's automatic qualitative analysis, as AutoEMX documents its defaults; no code copied):
//
//   1. fit the listed elements (the landed `EDSFit`: Kramers x Bernstein continuum with the Al K step, Si-escape columns, unweighted
//      non-negative least squares) with the NIST EPQ Kβ weights (`EDSLineWeights.epqK`; the quantification fit keeps eXSpy's by default, `FitPolicy.lineWeights`);
//   2. top-hat filter the residual and take its strongest peak at or above 5 σ (1.5 times that below 1 keV), the variance of a channel
//      being y + (0.01 mu)^2, so a strong line's small shape error is not a peak;
//   3. every pool element with a line of weight >= 0.1 within 2.5 σ + 25 eV of the peak is a candidate, and so is a pile-up pair of the
//      modelled elements; an element nominated by an L or M line needs its K or L alpha line at 3 σ in the residual where the range holds
//      it and the beam excites it (the confirmation rule, R4 before 0.11.0);
//   4. each candidate is fitted with the model; it may join when the statistic sum (y - mu)^2 / (mu + (0.01 mu)^2) falls by at least 100,
//      at least 20 % of that at its own lines, its area is at or above Currie's L_D (sigma_0 from the fit's own null variance) and no line
//      of it worsens its window by 9 and 5 % of the gain. The best joins; the others within 30 of it make it ambiguous;
//   5. repeat from 2 (30 peaks, 10 new elements at most); then leave each found element out of the final fit and drop it when that costs
//      less than 100.
//   Tiers: an element found from its own peak, unambiguous, needed by the final fit, Si above 0.2 % of the counts and its peak in a band
//   where the background is healthy (data over model 0.8 to 1.25 off the lines) is proposed; every other found or tested element is a
//   candidate with `possibleReason` (or `familyNote` for the confirmation rule) and is never proposed.
//
//  What went (0.11.0): the all-candidate joint fit with its L_C pruning and single-candidate forward step, and the flank-misfit factor that
//  scaled a candidate's sigma_0 by its neighbour's misfit (x33 for Mg beside Al on a measured Al-alloy map, where Mg's own window fitted to
//  ±3 σ). The 1 % model term does that job in the published way.
//  The method's overlap check (elements whose every peak sits under a modelled one leave no residual peak) is opt-in
//  (`ProposerPolicy.overlapCheck`): each such element is fitted once with the settled model and, when the fit needs it, reported as possible only.
//

import Foundation
import SpectroCore

public nonisolated struct ElementCandidate: Equatable, Sendable {
    public let element: String
    /// The line group with the largest net / L_D, e.g. "Mg_Ka".
    public let group: String
    /// Energy of the group's alpha line, keV.
    public let energyKeV: Double
    /// Fitted line area in counts (>= 0: the fit is non-negative).
    public let net: Double
    /// Standard deviation of the area at the fitted state (it contains the line's own Poisson variance).
    public let sigma: Double
    /// Standard deviation of the area with the candidate absent (the basis of L_C and L_D).
    public let sigmaZero: Double
    public let criticalLevel: Double
    public let detectionLimit: Double
    public let conflicts: [LineConflict]
    /// Cu defaults to Quantify (the Q phase); everything else to Fit only.
    public let suggestedRole: QuantificationMethod.ElementRole
    /// Cu only, when a hole spectrum was given: what the hole region said.
    public let holeRegionNote: String?
    /// Always 1 since 0.11.0: the flank-misfit factor is gone (docs/design/auto-id-tem.md); the field goes in the next minor.
    public let misfit: Double
    /// Why the family-consistency rule withheld the element (one sentence with the numbers); nil when it is consistent or the check
    /// could not judge. A withheld candidate keeps its numbers but is not proposed.
    public let familyNote: String?
    /// Why the identification loop reports the element as possible rather than proposing it (one sentence with the numbers): the fit did not
    /// gain enough, the gain was not at its lines, a line contradicted it, another candidate explains the peak as well, the final fit did not
    /// need it, or Si below the detector-artefact bar. nil for a proposed element.
    public let possibleReason: String?
    /// Found by an L or M line whose confirmation line (K for L, L for M) lies outside the fitted range or too close to the beam energy: the
    /// confirmation rule could not run, so the find is possible only (`possibleReason` says so). A consumer lists these as "uncorroborated".
    public let unconfirmable: Bool

    /// net >= L_D: the proposer's bar.
    public var aboveDetectionLimit: Bool { net >= detectionLimit }
    /// L_C < net < L_D: shown as "possible", never proposed.
    public var aboveCriticalLevel: Bool { net > criticalLevel }
    public var isProposed: Bool { aboveDetectionLimit && familyNote == nil && possibleReason == nil }
    public var hasSumPeakQuestion: Bool { conflicts.contains { $0.kind == .sumPeak } }
    /// How many detection limits the net is (the order in which to show candidates).
    public var significance: Double { net / detectionLimit }

    /// Explicit so the room's tests can state a candidate (the memberwise one is internal).
    public init(element: String, group: String, energyKeV: Double, net: Double, sigma: Double, sigmaZero: Double,
                 criticalLevel: Double, detectionLimit: Double, conflicts: [LineConflict],
                 suggestedRole: QuantificationMethod.ElementRole, holeRegionNote: String?, misfit: Double, familyNote: String? = nil,
                 possibleReason: String? = nil, unconfirmable: Bool = false) {
        self.element = element; self.group = group; self.energyKeV = energyKeV; self.net = net; self.sigma = sigma
        self.sigmaZero = sigmaZero; self.criticalLevel = criticalLevel; self.detectionLimit = detectionLimit
        self.conflicts = conflicts; self.suggestedRole = suggestedRole; self.holeRegionNote = holeRegionNote; self.misfit = misfit
        self.familyNote = familyNote; self.possibleReason = possibleReason; self.unconfirmable = unconfirmable
    }
}

/// A pile-up peak the fit modelled as a column of its own (no candidate sat near its energy).
public nonisolated struct SumPeakFinding: Equatable, Sendable {
    public let label: String
    public let elements: [String]
    public let energyKeV: Double
    public let net: Double
    public let sigmaZero: Double
    public let detectionLimit: Double
    public var detected: Bool { net >= detectionLimit }
}

public nonisolated struct ProposalResult: Sendable {
    /// Every element the identification loop tested (found, pruned, rejected or withheld), strongest first; an element with no residual peak was never a candidate.
    public let candidates: [ElementCandidate]
    public let sumPeaks: [SumPeakFinding]
    public let refused: [(element: String, reason: String)]
    public let currie: Currie
    /// The fit settings and warnings that shaped the result, in plain words (the footer).
    public let notes: [String]
    public let passes: Int
    public let settled: Bool
    /// Pearson reduced chi-square of the settled fit these candidates came from (R7, wp3e F3.3: shown beside every suggestion;
    /// a read of the fit, nothing here changes it). nil for a hand-built result.
    public let reducedChiSquared: Double?
    /// At or above L_D and carrying NO sum-peak conflict: an element the data support.
    public var proposed: [ElementCandidate] { candidates.filter { $0.isProposed && !$0.hasSumPeakQuestion } }
    /// At or above L_D but sitting on a pile-up energy of the detected parents: "sum peak or this element?", not a finding.
    public var sumPeakQuestions: [ElementCandidate] { candidates.filter { $0.isProposed && $0.hasSumPeakQuestion } }
    public var possible: [ElementCandidate] { candidates.filter { $0.aboveCriticalLevel && !$0.isProposed && $0.familyNote == nil } }
    /// At or above L_D but withheld by the family-consistency rule (`familyNote` says why).
    public var withheld: [ElementCandidate] { candidates.filter { $0.familyNote != nil } }
    /// The uncorroborated tier: found by an L or M line whose confirmation line the fitted range or the beam cannot hold (`unconfirmable`),
    /// strongest first. Possible only (`possibleReason` says why), never proposed; a consumer shows them and does not add them.
    public var uncorroborated: [ElementCandidate] { candidates.filter(\.unconfirmable) }

    /// Explicit so the room's tests can state a result (the memberwise one is internal).
    public init(candidates: [ElementCandidate], sumPeaks: [SumPeakFinding], refused: [(element: String, reason: String)],
                 currie: Currie, notes: [String], passes: Int, settled: Bool, reducedChiSquared: Double? = nil) {
        self.reducedChiSquared = reducedChiSquared
        self.candidates = candidates; self.sumPeaks = sumPeaks; self.refused = refused; self.currie = currie
        self.notes = notes; self.passes = passes; self.settled = settled
    }
}

public nonisolated enum ProposerError: Error, Equatable {
    case lengthMismatch
    case noChannels
    /// The fit of the listed elements is numerically rank deficient: no covariance, so no limit can be stated.
    case rankDeficient
    /// The calling task was cancelled (checked before every fit, each a fraction of a second). Not a failure: the caller discards.
    case cancelled
}

public nonisolated struct ElementProposer: Sendable {
    package var currie: Currie
    /// The elements tested; nil is `defaultPool`.
    package var pool: [String]?
    /// A candidate group is tested only if its alpha line is at or above this energy (keV). MEASURED, not a property of the
    /// method: on the Kramers x window-absorption generator the only false elements at x100 dose were C K, N K, Ca L and
    /// Sc L at 0.28-0.40 keV, where the detector window cuts the continuum steeply and the fit's continuum cannot follow
    /// it at 10^4 counts per channel (lane P report). 0.45 keV keeps O K-alpha (0.525). Reported in every result's notes;
    /// an element with lines in range but none above it is refused with this reason (the user can still list it by hand).
    package var minimumLineEnergyKeV: Double
    /// The identification loop's bars (see `IdentificationThresholds`).
    package var thresholds = IdentificationThresholds.default
    /// Elements left out of the default pool (see `defaultExcluded`); used when `pool` is nil.
    package var excluded: Set<String> = ElementProposer.defaultExcluded
    /// A candidate's alpha line must lie this many FWHM inside the fitted range at each end.
    package var rangeMarginFWHM = 0.5
    /// A candidate's alpha line counts as on a pile-up energy within this many keV.
    package var sumPeakToleranceKeV = LineConflicts.sumPeakToleranceKeV
    /// Which elements get the grid, implantation and quantify-by-default treatment.
    package var context = ElementContext.default
    /// The confirmation-line rule and its overvoltage, see `ProposerPolicy`.
    package var familyConsistency = true
    package var familyOvervoltage = 2.0
    /// The downward confirmation rule, see `ProposerPolicy.downwardFamilyMinimumZ`. nil: off.
    package var downwardFamilyMinimumZ: Int?
    package var sumPeakFraction = 1.0
    /// The overlap check, see `ProposerPolicy.overlapCheck`.
    package var overlapCheck = false

    /// Elements the line table lists that no spectrum of a material shows or that the app has no use for:
    /// radioactive or absent from the table (Tc, Pm and everything from Po up, as the field's auto IDs stop at Bi), noble gases other than Ar
    /// (Ne, Kr, Xe; Ar is a named conflict). A reader may pass any `pool` instead.
    public static let defaultExcluded: Set<String> = ["Tc", "Pm", "Po", "At", "Rn", "Fr", "Ra", "Ac", "Th", "Pa", "U", "Np", "Pu", "Am", "Ne", "Kr", "Xe"]

    /// Every element of the line table, minus the refused (H, He, Li, Be) and `defaultExcluded`.
    public static var defaultPool: [String] { defaultPool(excluding: defaultExcluded) }

    /// The default pool with another exclusion list: every element of the line table minus the refused (H, He, Li, Be) and `excluded`.
    public static func defaultPool(excluding excluded: Set<String>) -> [String] {
        var seen = Set<String>(), out: [String] = []
        for l in XRayLines.all where !seen.contains(l.element) {
            seen.insert(l.element)
            if LineConflicts.refusal(for: l.element) == nil, !excluded.contains(l.element) { out.append(l.element) }
        }
        return out
    }

    /// The proposer's choices as a value (what `init(policy:)` took, with any package-level change since).
    package var policy: ProposerPolicy {
        ProposerPolicy(currie: currie, pool: pool, excluded: excluded, minimumLineEnergyKeV: minimumLineEnergyKeV, thresholds: thresholds,
                       rangeMarginFWHM: rangeMarginFWHM, sumPeakToleranceKeV: sumPeakToleranceKeV, context: context,
                       familyConsistency: familyConsistency, familyOvervoltage: familyOvervoltage, sumPeakFraction: sumPeakFraction,
                       downwardFamilyMinimumZ: downwardFamilyMinimumZ, overlapCheck: overlapCheck)
    }

    /// The proposer with every choice named (`ProposerPolicy.default` is what the other initialiser builds).
    public init(policy: ProposerPolicy) {
        self.init(currie: policy.currie, pool: policy.pool, minimumLineEnergyKeV: policy.minimumLineEnergyKeV)
        thresholds = policy.thresholds; excluded = policy.excluded
        rangeMarginFWHM = policy.rangeMarginFWHM; sumPeakToleranceKeV = policy.sumPeakToleranceKeV; context = policy.context
        familyConsistency = policy.familyConsistency; familyOvervoltage = policy.familyOvervoltage; downwardFamilyMinimumZ = policy.downwardFamilyMinimumZ
        sumPeakFraction = policy.sumPeakFraction; overlapCheck = policy.overlapCheck
    }

    /// - Parameters:
    ///   - currie: the false-positive and false-negative rates of the detection limit. Default `.standard` (0.05 each), Currie's convention.
    ///   - pool: the elements tested; nil is `defaultPool`.
    ///   - minimumLineEnergyKeV: lines below this are not tested. Default 0.45 keV, measured on one synthetic generator where the
    ///     detector window cuts the continuum steeply (carbon, nitrogen, calcium and scandium were false there at 0.28-0.40 keV).
    public init(currie: Currie = .standard, pool: [String]? = nil, minimumLineEnergyKeV: Double = 0.45) {
        self.currie = currie; self.pool = pool; self.minimumLineEnergyKeV = minimumLineEnergyKeV
    }

    /// "α = β = 0.05" when the two rates are equal, "α = 0.005, β = 0.2" otherwise; two decimals when they give the rate back
    /// exactly (today's text), else the shortest digits that do.
    private static func rateText(_ c: Currie) -> String {
        func r(_ x: Double) -> String { let t = String(format: "%.2f", x); return Double(t) == x ? t : "\(x)" }
        return c.alpha == c.beta ? "\u{03B1} = \u{03B2} = \(r(c.alpha))" : "\u{03B1} = \(r(c.alpha)), \u{03B2} = \(r(c.beta))"
    }

    private struct Stat { var net: Double, sigma: Double, sigmaZero: Double, lc: Double, ld: Double
        var significance: Double { net / ld } }

    private struct Pass {
        var model: EDSLineModel
        var result: EDSFitResult
        /// nil when the design is numerically rank deficient (no limit can be stated for its groups).
        var variances: AmplitudeVariances?
        /// The statistic's terms per fitted channel.
        var terms: [Double]
        var statistic: Double
    }

    private struct ResultBox: @unchecked Sendable { var buffer: UnsafeMutableBufferPointer<Result<Pass, Error>?> }

    /// One fit of `groups` against `data`: no cancellation check, no progress, no shared state (safe to run concurrently).
    /// The fit is WEIGHTED by the statistic's own variance, w = 1 / max(ȳ + (r ȳ)^2, 1), ȳ the data smoothed over one FWHM (`widths`) so a channel
    /// that fluctuates high is not down-weighted for it (Neyman's bias, about one count per channel at low counts) (fixed, so every candidate is fitted on the
    /// same footing and the problem stays linear): least squares in the scaled rows minimises the statistic with y in place of mu. Unweighted, a
    /// strong line's shape error dragged the continuum beside it (data over model 3.1 in 1 to 2.5 keV beside a planted Al 6 eV narrower than the
    /// model) and the hump it left became an element (Os M). The pass's `result` is returned in counts (its model and residual unscaled).
    private static func fitPass(groups: [FitLineGroup], data: [Double], settings s: FitSettings, axis: EnergyAxis,
                                channels: Range<Int>, dropped: [String], relative: Double, widths: [Int], weighted: Bool = true,
                                explained: [Double]? = nil) throws -> Pass {
        let model = EDSLineModel(groups: groups, resolutionMnKaEV: s.resolutionMnKaEV, beamEnergy: s.beamEnergy,
                                 escapePeaks: s.escapePeaks, droppedLines: dropped, lineTail: s.lineTail)
        try EDSFit.validate(s.referenceShapes, axis: axis, model: model)
        var design = LinearDesign.build(model: model, axis: axis, channels: channels, background: s.background,
                                        shapes: s.referenceShapes, counts: data)
        // Counts the caller's model already explains (the sum and escape peaks of a sum/escape fit): a fixed part of the model.
        if let explained { for (k, ch) in channels.enumerated() { design.offset[k] += explained[ch] } }
        let y = channels.map { data[$0] }
        var prefix = [Double](repeating: 0, count: y.count + 1)
        for i in y.indices { prefix[i + 1] = prefix[i] + y[i] }
        let scale = y.indices.map { i -> Double in
            let h = widths[i] / 2, a = max(i - h, 0), b = min(i + h, y.count - 1)
            let ys = (prefix[b + 1] - prefix[a]) / Double(b - a + 1)
            return weighted ? 1 / max(ys + relative * relative * ys * ys, 1).squareRoot() : 1
        }
        for j in design.areaColumns.indices { for i in scale.indices { design.areaColumns[j].values[i] *= scale[i] } }
        for j in design.backgroundColumns.indices { for i in scale.indices { design.backgroundColumns[j].values[i] *= scale[i] } }
        for i in scale.indices { design.offset[i] *= scale[i] }
        var scaled = data
        for (i, ch) in channels.enumerated() { scaled[ch] = y[i] * scale[i] }
        var result = EDSFit.fit(design: design, model: model, counts: scaled, settings: s, computeCovariance: false)
        let variances = FitNullVariance.compute(design: design, result: result, rowScale: scale)
        result.model = zip(result.model, scale).map { $0 / $1 }
        result.residual = zip(y, result.model).map { $0 - $1 }
        result.standardizedResidual = zip(result.residual, result.model).map { $0 / max($1, EDSFitResult.standardizedFloor).squareRoot() }
        let pearson = zip(result.residual, result.model).reduce(0.0) { $0 + $1.0 * $1.0 / max($1.1, EDSFitResult.standardizedFloor) }
        let dof = result.degreesOfFreedom > 0 ? Double(result.degreesOfFreedom) : .nan
        result.pearsonReducedChiSquared = pearson / dof
        result.reducedChiSquared = result.residual.reduce(0) { $0 + $1 * $1 } / dof
        result.deviance = PoissonMLFit.deviance(y: y, mu: result.model, floor: 1e-6)
        result.reducedDeviance = result.deviance / dof
        if weighted { result.methodLabel = "least squares, weighted by 1/(y + (\(relative) y)\u{00B2})" }
        let terms = IdentificationLoop.chiSquaredTerms(y: y, mu: result.model, relative: relative)
        return Pass(model: model, result: result, variances: variances, terms: terms, statistic: terms.reduce(0, +))
    }

    /// `fitPass` for every job, concurrently; the results are in job order.
    private static func fitPasses(jobs: [[FitLineGroup]], data: [Double], settings s: FitSettings, axis: EnergyAxis,
                                  channels: Range<Int>, dropped: [String], relative: Double, widths: [Int],
                                  explained: [Double]?) -> [Result<Pass, Error>] {
        var out = [Result<Pass, Error>?](repeating: nil, count: jobs.count)
        out.withUnsafeMutableBufferPointer { buf in
            let box = ResultBox(buffer: buf)
            DispatchQueue.concurrentPerform(iterations: jobs.count) { i in
                box.buffer[i] = Result { try fitPass(groups: jobs[i], data: data, settings: s, axis: axis, channels: channels,
                                                     dropped: dropped, relative: relative, widths: widths, explained: explained) }
            }
        }
        return out.map { $0! }
    }

    /// A tested element (or pile-up column): what its fit with the model said.
    private struct Trial {
        var key: String
        var group: String
        var stat: Stat?
        var gain: Double
        /// The fall of the statistic within one FWHM of the peak that nominated it: which candidate explains THAT peak best.
        var peakGain: Double
        var localShare: Double
        /// nil: it may join. Otherwise one sentence with the numbers.
        var reason: String?
        var confirmation: String?
        /// An L or M nomination whose confirmation line lies outside the fitted range or above half the beam: it may join, but stays possible.
        var unconfirmable: String?
        var pass: Pass?
    }

    /// An element the loop added to the model.
    private struct Found {
        var peakKeV: Double
        var gain: Double
        var ambiguous: [String]
        var unconfirmable: String?
    }

    /// - Parameters:
    ///   - counts: the pooled spectrum, one value per channel of `axis`.
    ///   - settings: the fit as the room runs it. `elements` is the CURRENT set (always fitted, never changed);
    ///     range, background, escape setting and reference shapes are used as given, the method is forced to LS.
    ///   - holeCounts: optional pooled spectrum of a hole region on the same axis, for the Cu grid check.
    ///   - cancelled: asked before every round of fits; default Swift task cancellation. The proposer keeps
    ///     its own `ProposerError.cancelled`; nothing partial is returned.
    ///   - progress: monotone in 0...1, ends at 1. The number of fits is not known in advance, so it is fits done over fits done plus the
    ///     fits the current step still has planned, clamped never to fall.
    ///   - explained: counts per channel of `axis` that the caller's model already explains beyond line and continuum columns (the sum
    ///     and escape peaks of `EDSSumEscapeFit`, `SumEscapeResult.componentCounts`). They are a fixed part of every fit here, so a peak
    ///     they cover leaves no residual and is never proposed as an element. nil (the default) runs the proposer as before, bit for bit.
    public func propose(counts: [Double], axis: EnergyAxis, settings: FitSettings,
                         holeCounts: [Double]? = nil,
                         explained: [Double]? = nil,
                         cancelled: @Sendable () -> Bool = SpectroCancellation.task,
                         progress: (@Sendable (Double) -> Void)? = nil) throws -> ProposalResult {
        guard counts.count == axis.size, holeCounts.map({ $0.count == axis.size }) ?? true,
              explained.map({ $0.count == axis.size }) ?? true else { throw ProposerError.lengthMismatch }
        var s = settings
        s.method = .leastSquares
        let channels = axis.fitChannels(from: s.fitFrom, to: s.fitTo)
        guard !channels.isEmpty else { throw ProposerError.noChannels }
        let t = thresholds
        let lo = axis.energy(ofChannel: channels.lowerBound), hi = axis.energy(ofChannel: channels.upperBound - 1)
        let current = s.elements
        let requested = pool ?? Self.defaultPool(excluding: excluded)

        var refused: [(element: String, reason: String)] = []
        var seenRefused = Set<String>()
        for el in LineConflicts.refusedElements + requested + current where !seenRefused.contains(el) {
            if let reason = LineConflicts.refusal(for: el) { refused.append((el, reason)); seenRefused.insert(el) }
        }
        let poolElements = requested.filter { LineConflicts.refusal(for: $0) == nil && !current.contains($0) }

        let base = EDSLineModel.build(elements: current + poolElements, axis: axis, beamEnergy: s.beamEnergy,
                                      resolutionMnKaEV: s.resolutionMnKaEV, escapePeaks: s.escapePeaks, lineTail: s.lineTail,
                                      lineWeights: .epqK)
        let dropped = base.droppedLines.filter { l in current.contains { l.contains("\($0)_") } }
        let currentGroups = base.groups.filter { current.contains($0.element) }
        // A candidate group needs its alpha line inside the fitted range by half a width (its column must have support).
        let poolGroups = base.groups.filter { g in
            poolElements.contains(g.element) && g.lines[0].energy >= max(lo + rangeMarginFWHM * g.lines[0].fwhm, minimumLineEnergyKeV)
                && g.lines[0].energy <= hi - rangeMarginFWHM * g.lines[0].fwhm
        }
        for el in poolElements where !poolGroups.contains(where: { $0.element == el }) {
            if let low = base.groups.filter({ $0.element == el && $0.lines[0].energy < minimumLineEnergyKeV }).map({ $0.lines[0].energy }).max() {
                refused.append((el, String(format: "Its line at %.2f keV lies below the proposer's lowest tested line (%.2f keV): under the detector window the continuum is too model-dependent for a net area to be trusted. List it by hand if you know it is there.", low, minimumLineEnergyKeV)))
            }
        }
        let testable = Set(poolGroups.map(\.element))

        let y = channels.map { counts[$0] }
        let energies = channels.map { axis.energy(ofChannel: $0) }
        let widths = IdentificationLoop.widths(energies: energies, scale: axis.scale, resolutionMnKaEV: s.resolutionMnKaEV)
        let totalCounts = y.reduce(0, +)
        func fwhm(_ e: Double) -> Double { XRayLines.fwhm(resolutionMnKaEV: s.resolutionMnKaEV, atEnergy: max(e, 0)) ?? s.resolutionMnKaEV / 1000 }
        /// Fitted-channel indices within `half` keV of `e`.
        func window(_ e: Double, _ half: Double) -> Range<Int> {
            let a = Int(((e - half - energies[0]) / axis.scale).rounded(.up)), b = Int(((e + half - energies[0]) / axis.scale).rounded(.down))
            let lower = max(a, 0), upper = min(b + 1, energies.count)
            return lower < upper ? lower..<upper : 0..<0
        }

        var fitsDone = 0, fitsPlanned = 1, reported = 0.0
        func tick() {
            guard let progress else { return }
            let f = min(max(Double(fitsDone) / Double(max(fitsDone + fitsPlanned, 1)), reported), 0.99)
            reported = f
            progress(f)
        }
        func runAll(_ jobs: [[FitLineGroup]], on data: [Double]) throws -> [Result<Pass, Error>] {
            if cancelled() { throw ProposerError.cancelled }
            fitsPlanned = max(fitsPlanned, jobs.count)
            let out = Self.fitPasses(jobs: jobs, data: data, settings: s, axis: axis, channels: channels, dropped: dropped, relative: t.relativeModelTerm, widths: widths,
                                     explained: explained)
            fitsDone += jobs.count; tick()
            return out
        }
        func run(_ groups: [FitLineGroup], on data: [Double]) throws -> Pass { try runAll([groups], on: data)[0].get() }
        func stat(_ p: Pass, _ gi: Int) -> Stat? {
            guard p.result.supported[gi], let v = p.variances, let v0 = v.null[gi], let vf = v.atFit[gi] else { return nil }
            let s0 = v0.squareRoot()
            return Stat(net: p.result.values[gi], sigma: vf.squareRoot(), sigmaZero: s0,
                        lc: currie.criticalLevel(sigmaZero: s0), ld: currie.detectionLimit(sigmaZero: s0))
        }
        /// The strongest group of every modelled element, as pile-up parents, with its area.
        func parents(_ p: Pass) -> [(parent: SumParent, net: Double)] {
            var best: [String: (Double, Double)] = [:]
            for (gi, g) in p.model.groups.enumerated() where g.element != "sum" {
                let v = p.result.values[gi]
                if best[g.element].map({ v > $0.1 }) ?? true { best[g.element] = (g.lines[0].energy, v) }
            }
            return best.map { (SumParent(element: $0.key, energyKeV: $0.value.0), $0.value.1) }.sorted { $0.parent.element < $1.parent.element }
        }
        /// The filtered residual of a fit in standard deviations, the variance of a channel y + (r mu)^2.
        func residualZ(_ p: Pass) -> [Double] {
            let r = zip(y, p.result.model).map { $0 - $1 }
            let v = zip(y, p.result.model).map { yi, m in max(yi, 1) + pow(t.relativeModelTerm * max(m, 0), 2) }
            let f = IdentificationLoop.topHat(r, variance: v, widths: widths)
            return zip(f.filtered, f.sigma).map { $1.isFinite && $1 > 0 ? $0 / $1 : 0 }
        }
        /// Every fitted channel within 1.5 FWHM of one of the groups' lines or escapes.
        func near(_ groups: [FitLineGroup]) -> [Bool] {
            var m = [Bool](repeating: false, count: energies.count)
            for g in groups { for l in g.lines + g.escapes { for i in window(l.energy, 1.5 * l.fwhm) { m[i] = true } } }
            return m
        }

        var model = currentGroups
        var fit = try run(model, on: counts)
        // The listed elements' own fit must state limits (as before 0.11.0): a rank-deficient listed design is refused, not read.
        if !current.isEmpty, fit.variances == nil { throw ProposerError.rankDeficient }
        var found: [String: Found] = [:], foundOrder: [String] = []
        var trials: [String: Trial] = [:]
        var sumInfo: [String: (label: String, elements: [String])] = [:]
        var tried: [Double] = []
        var examined = 0, tested = 0
        var capped = false

        /// The confirmation rule for an element nominated by `line`: `withhold` says why it cannot be it; `unconfirmable` says why the rule
        /// could not run (its confirmation line is outside the fitted range or too close to the beam energy), which keeps a find possible.
        func confirmation(_ el: String, _ line: XRayLine, _ z: [Double]) -> (withhold: String?, unconfirmable: String?) {
            guard familyConsistency else { return (nil, nil) }
            // The downward rule (opt-in): a K nomination of an element at or above `downwardFamilyMinimumZ` needs its L alpha line. A K line
            // is the strong evidence, so an L line the range cannot hold (or below the tested energies) leaves the find as it is.
            if line.family == .K {
                let companionID = el + "_La"
                guard let minimumZ = downwardFamilyMinimumZ, line.atomicNumber >= minimumZ, let c = XRayLines.line(companionID),
                      c.energy >= max(lo, minimumLineEnergyKeV) + rangeMarginFWHM * fwhm(c.energy),
                      c.energy <= hi - rangeMarginFWHM * fwhm(c.energy) else { return (nil, nil) }
                return (companionPeak(el, line, companionID, c, z), nil)
            }
            let companionID = el + (line.family == .L ? "_Ka" : "_La")
            guard let c = XRayLines.line(companionID) else { return (nil, nil) }
            guard c.energy >= lo + rangeMarginFWHM * fwhm(c.energy), c.energy <= hi - rangeMarginFWHM * fwhm(c.energy),
                  s.beamEnergy >= familyOvervoltage * c.energy else {
                return (nil, String(format: "Found by its %@ alone: its %@ (%.2f keV) lies outside the fitted range (%.2f to %.2f keV) or too close to the beam energy, so the confirmation line cannot be checked.",
                                    Self.lineLabel(line.id), Self.lineLabel(companionID), c.energy, lo, hi))
            }
            return (companionPeak(el, line, companionID, c, z), nil)
        }

        /// nil when the companion line `c` has a residual peak of `confirmationSigma`; otherwise why the element cannot be it.
        func companionPeak(_ el: String, _ line: XRayLine, _ companionID: String, _ c: XRayLine, _ z: [Double]) -> String? {
            // A peak of its own: a local maximum of the filtered residual within one Gaussian sigma of the line (the flank of a neighbour's
            // unmodelled peak 1.6 sigma away, Cu Kα beside Ta Lα, is not a confirmation).
            let sigma = fwhm(c.energy) / EDSLineModel.sigma2fwhm
            let zc = window(c.energy, sigma).filter { i in
                let h = widths[i] / 2
                return !(max(0, i - h)...min(z.count - 1, i + h)).contains { $0 != i && z[$0] > z[i] }
            }.map { z[$0] }.max() ?? 0
            guard zc < t.confirmationSigma else { return nil }
            return String(format: "%@ %@ (%.2f keV) has a residual peak of %.1f \u{03C3}, below the %.0f \u{03C3} its %@ (%.2f keV) needs: not %@.",
                          el, Self.lineLabel(companionID), c.energy, zc, t.confirmationSigma, Self.lineLabel(line.id), line.energy, el)
        }

        // The loop: the strongest residual peak, its candidates, the best of them joins.
        while true {
            if examined >= t.maximumPeaks || foundOrder.count >= t.maximumNewElements { capped = true; break }
            let z = residualZ(fit)
            var peak: (i: Int, z: Double)?
            for i in z.indices {
                let e = energies[i]
                guard e >= minimumLineEnergyKeV, z[i] >= t.peakSigma * (e < t.lowEnergyBelowKeV ? t.lowEnergyFactor : 1),
                      z[i] > (peak?.z ?? -.infinity) else { continue }
                let h = widths[i] / 2
                guard !(max(0, i - h)...min(z.count - 1, i + h)).contains(where: { $0 != i && z[$0] > z[i] }),
                      !tried.contains(where: { abs($0 - e) <= fwhm(e) }) else { continue }
                peak = (i, z[i])
            }
            guard let peak else { break }
            examined += 1
            let ep = energies[peak.i]
            tried.append(ep)
            let reach = t.candidateWindowSigma * fwhm(ep) / EDSLineModel.sigma2fwhm + t.candidateWindowKeV

            // Candidates: the elements with a line there, then the pile-up pairs of the modelled elements.
            let inModel = Set(model.map(\.element))
            var jobs: [[FitLineGroup]] = [], keys: [(key: String, group: String, confirmation: String?, unconfirmable: String?)] = []
            for el in poolElements where testable.contains(el) && !inModel.contains(el) {
                let lines = XRayLines.lines(of: el).filter { $0.weight >= t.minimumLineWeight && abs($0.energy - ep) <= reach && $0.energy >= lo && $0.energy <= hi }
                guard let line = lines.min(by: { abs($0.energy - ep) < abs($1.energy - ep) }) else { continue }
                let groups = poolGroups.filter { $0.element == el }
                // The nominating family's group must be testable (its alpha line in range); otherwise the trial would report another family.
                guard let g = groups.first(where: { $0.id.dropFirst(el.count + 1).first == line.name.first }) else { continue }
                jobs.append(model + groups)
                let check = confirmation(el, line, z)
                keys.append((el, g.id, check.withhold, check.unconfirmable))
            }
            let columns = Set(model.map(\.id))
            var sumEnergiesSeen: [Double] = []
            for e in LineConflicts.sumEnergies(parents: parents(fit).map(\.parent)) {
                let id = "sum:" + e.elements.joined(separator: "+")
                guard abs(e.energyKeV - ep) <= reach, e.energyKeV < hi, e.energyKeV < s.beamEnergy, !columns.contains(id),
                      !sumEnergiesSeen.contains(where: { abs($0 - e.energyKeV) < 1e-9 }),
                      let w = XRayLines.fwhm(resolutionMnKaEV: s.resolutionMnKaEV, atEnergy: e.energyKeV) else { continue }
                sumEnergiesSeen.append(e.energyKeV)
                let g = FitLineGroup(id: id, element: "sum", lines: [FitLine(id: id, energy: e.energyKeV, weight: 1, fwhm: w)], escapes: [])
                sumInfo[id] = (e.label, e.elements)
                jobs.append(model + [g])
                keys.append((id, id, nil, nil))
            }
            guard !jobs.isEmpty else { continue }
            let results = try runAll(jobs, on: counts)
            tested += jobs.count

            var eligible: [Trial] = []
            for (k, r) in zip(keys, results) {
                guard let p = try? r.get(), let gi = p.model.groups.firstIndex(where: { $0.id == k.group }) else { continue }
                let new = p.model.groups.filter { !columns.contains($0.id) }
                let gain = fit.statistic - p.statistic
                let mask = near(new)
                let local = zip(mask.indices, mask).filter(\.1).reduce(0.0) { $0 + fit.terms[$1.0] - p.terms[$1.0] }
                let peakGain = window(ep, fwhm(ep)).reduce(0.0) { $0 + fit.terms[$1] - p.terms[$1] }
                var trial = Trial(key: k.key, group: k.group, stat: stat(p, gi), gain: gain, peakGain: peakGain, localShare: gain > 0 ? local / gain : 0,
                                  reason: nil, confirmation: k.confirmation, unconfirmable: k.unconfirmable, pass: p)
                // A line of the candidate that the data contradict: its window worsens by `contradictionGain` and by a share of the gain.
                var contradicted: String?
                for g in new { for l in g.lines where l.weight >= t.minimumLineWeight {
                    let d = window(l.energy, l.fwhm).reduce(0.0) { $0 + fit.terms[$1] - p.terms[$1] }
                    if d <= -t.contradictionGain && -d > t.contradictionShare * max(gain, 0) {
                        contradicted = String(format: "its %@ (%.2f keV) makes the fit worse there by %.0f", Self.lineLabel(l.id), l.energy, -d)
                        break
                    }
                } }
                if let c = k.confirmation { trial.reason = c }
                else if gain < t.minimumGain { trial.reason = String(format: "Adding it improves the fit by %.0f, below the %.0f a new line needs.", gain, t.minimumGain) }
                else if trial.localShare < t.minimumLocalShare { trial.reason = String(format: "Only %.0f %% of its gain %.0f is at its own lines (%.0f %% needed): it mostly reshapes the background.", 100 * trial.localShare, gain, 100 * t.minimumLocalShare) }
                else if let st = trial.stat, st.net < st.ld { trial.reason = String(format: "Its area %.0f is below its detection limit %.0f.", st.net, st.ld) }
                else if trial.stat == nil { trial.reason = "Its area has no stated limit (the fit with it is rank deficient)." }
                else if let c = contradicted { trial.reason = "The data contradict it: \(c)." }
                if trial.reason == nil { eligible.append(trial) }
                if !k.key.hasPrefix("sum:") && found[k.key] == nil { trials[k.key] = trial }
            }
            // The candidate that explains THIS peak best joins (its gain within one FWHM of the peak): a heavy element whose other families
            // also soak up misfits elsewhere must not take a peak that a K line sits on exactly (W Mα took Si Kα on a measured map by total gain).
            guard let best = eligible.max(by: { $0.peakGain < $1.peakGain }), let p = best.pass else { continue }
            let rivals = eligible.filter { $0.key != best.key && $0.peakGain >= best.peakGain - t.ambiguityGain }.map(\.key)
            for e in eligible where e.key != best.key && !e.key.hasPrefix("sum:") {
                trials[e.key]?.reason = String(format: "The peak at %.3f keV went to %@, which explains it better (gain there %.0f against %.0f).",
                                               ep, best.key.hasPrefix("sum:") ? (sumInfo[best.key]?.label ?? best.key) : best.key, best.peakGain, e.peakGain)
            }
            model = p.model.groups
            fit = p
            if !best.key.hasPrefix("sum:") {
                found[best.key] = Found(peakKeV: ep, gain: best.peakGain, ambiguous: rivals, unconfirmable: best.unconfirmable)
                foundOrder.append(best.key)
                trials[best.key] = nil
            }
        }

        // Prune: leave each found element out of the final fit; drop the cheapest while that costs less than `pruneGain`.
        var pruned: [String: Trial] = [:]
        while true {
            let inModel = foundOrder.filter { el in model.contains { $0.element == el } }
            guard !inModel.isEmpty else { break }
            let jobs = inModel.map { el in model.filter { $0.element != el } }
            let results = try runAll(jobs, on: counts)
            let costs = zip(inModel, results).compactMap { el, r in (try? r.get()).map { (el, $0.statistic - fit.statistic, $0) } }
            // Dropped only when the final fit does not need it AND its own peak does not either (the statistic's fall within one FWHM of the
            // peak it was found at, the filtered peak gain of the method's step 7).
            func peakCost(_ el: String, _ p: Pass) -> Double {
                guard let e = found[el]?.peakKeV else { return 0 }
                return window(e, fwhm(e)).reduce(0.0) { $0 + p.terms[$1] - fit.terms[$1] }
            }
            guard let cheapest = costs.filter({ peakCost($0.0, $0.2) < t.pruneGain }).min(by: { $0.1 < $1.1 }), cheapest.1 < t.pruneGain else { break }
            let gi = fit.model.groups.enumerated().filter { $0.element.element == cheapest.0 }
                .max { (stat(fit, $0.offset)?.significance ?? 0) < (stat(fit, $1.offset)?.significance ?? 0) }?.offset
            pruned[cheapest.0] = Trial(key: cheapest.0, group: gi.map { fit.model.groups[$0].id } ?? "", stat: gi.flatMap { stat(fit, $0) },
                                       gain: cheapest.1, peakGain: 0, localShare: 0,
                                       reason: String(format: "Leaving it out of the final fit costs %.0f, below the %.0f it needs to stay.", cheapest.1, t.pruneGain),
                                       confirmation: nil, unconfirmable: nil, pass: nil)
            model = cheapest.2.model.groups
            fit = cheapest.2
        }
        // A pile-up column whose parent was pruned goes with it.
        if model.contains(where: { g in g.element == "sum" && (sumInfo[g.id]?.elements ?? []).contains { pruned[$0] != nil } }) {
            model.removeAll { g in g.element == "sum" && (sumInfo[g.id]?.elements ?? []).contains { pruned[$0] != nil } }
            fit = try run(model, on: counts)
        }

        // The overlap check (opt-in): an element whose every line hides under a modelled one leaves no residual peak, so the loop never
        // nominated it. Each such element is fitted once with the settled model; it is reported possible when the fit needs it.
        var overlapFinds: [(element: String, trial: Trial)] = []
        if overlapCheck {
            let inModel = Set(model.map(\.element))
            // Every modelled line can host (a weak Kβ still carries model counts there); the fit then decides.
            let modelled = model.flatMap { g in g.lines.map { (g.element == "sum" ? (sumInfo[g.id]?.label ?? g.id) : g.element, $0.energy) } }
            var jobs: [[FitLineGroup]] = [], keys: [(element: String, hosts: [String])] = []
            for el in poolElements where testable.contains(el) && !inModel.contains(el) && trials[el] == nil && pruned[el] == nil && found[el] == nil {
                let lines = XRayLines.lines(of: el).filter { $0.weight >= t.minimumLineWeight && $0.energy >= max(lo, minimumLineEnergyKeV) && $0.energy <= hi }
                guard !lines.isEmpty else { continue }
                var hosts: [String] = []
                let hidden = lines.allSatisfy { l in
                    let reach = t.candidateWindowSigma * fwhm(l.energy) / EDSLineModel.sigma2fwhm + t.candidateWindowKeV
                    guard let h = modelled.filter({ abs($0.1 - l.energy) <= reach }).min(by: { abs($0.1 - l.energy) < abs($1.1 - l.energy) }) else { return false }
                    if !hosts.contains(h.0) { hosts.append(h.0) }
                    return true
                }
                guard hidden else { continue }
                jobs.append(model + poolGroups.filter { $0.element == el })
                keys.append((el, hosts))
            }
            if !jobs.isEmpty {
                let results = try runAll(jobs, on: counts)
                tested += jobs.count
                for (k, r) in zip(keys, results) {
                    guard let p = try? r.get() else { continue }
                    let gain = fit.statistic - p.statistic
                    let gs = p.model.groups.enumerated().filter { $0.element.element == k.element }.compactMap { gi, g in stat(p, gi).map { (g.id, $0) } }
                    guard gain >= t.minimumGain, let (gid, st) = gs.max(by: { $0.1.significance < $1.1.significance }), st.net >= st.ld else { continue }
                    // The loop's other bars: the gain must be at its own lines (not a reshaped host), and no line of it may worsen its window.
                    let new = p.model.groups.filter { $0.element == k.element }
                    let mask = near(new)
                    let local = zip(mask.indices, mask).filter(\.1).reduce(0.0) { $0 + fit.terms[$1.0] - p.terms[$1.0] }
                    guard local / gain >= t.minimumLocalShare else { continue }
                    let contradicted = new.contains { g in g.lines.contains { l in
                        guard l.weight >= t.minimumLineWeight else { return false }
                        let d = window(l.energy, l.fwhm).reduce(0.0) { $0 + fit.terms[$1] - p.terms[$1] }
                        return d <= -t.contradictionGain && -d > t.contradictionShare * gain
                    } }
                    guard !contradicted else { continue }
                    let reason = String(format: "Every line of it sits under a modelled line (%@), so it left no residual peak of its own and its confirmation lines cannot be read apart; the overlap check fitted it with the settled model: gain %.0f, area %.0f at or above its detection limit %.0f. Possible only.",
                                        k.hosts.joined(separator: ", "), gain, st.net, st.ld)
                    overlapFinds.append((k.element, Trial(key: k.element, group: gid, stat: st, gain: gain, peakGain: 0, localShare: 0, reason: reason,
                                                         confirmation: nil, unconfirmable: nil, pass: p)))
                }
            }
        }

        // Background health in bands, off the modelled lines: data over model within 0.8 to 1.25.
        let onLines = near(model)
        var unhealthy: [(lo: Double, hi: Double, ratio: Double)] = []
        for (a, b) in [(1.0, 2.5), (2.5, 5.0), (5.0, hi + 1)] {
            var d = 0.0, m = 0.0, n = 0
            for i in energies.indices where energies[i] >= a && energies[i] < b && !onLines[i] { d += y[i]; m += fit.result.model[i]; n += 1 }
            if n >= 10, m > 0, !(0.8...1.25).contains(d / m) { unhealthy.append((a, min(b, hi), d / m)) }
        }

        // The reported numbers of the final model (found elements, pile-up parents and sums, the hole region) come from the standard fit (unweighted least squares, as Quantify and the proposer before
        // 0.11.0): the weighted fit decides membership, its areas are not quantification-grade (a strong line's area reads low where the model's
        // shape is off, and the statistic's weights spare that misfit). σ₀ and L_D are that fit's own null variance. Pruned, rejected and withheld
        // candidates keep the numbers of the fit that decided them (they are not in the final model).
        let report = try Self.fitPass(groups: model, data: counts, settings: s, axis: axis, channels: channels, dropped: dropped,
                                      relative: t.relativeModelTerm, widths: widths, weighted: false, explained: explained)
        fitsDone += 1
        // Candidates: the found elements from the final fit, then the pruned, then the rest that were tested.
        let finalParents = parents(report)
        let parentNets = Dictionary(uniqueKeysWithValues: finalParents.map { ($0.parent.element, $0.net) })
        func conflicts(_ el: String, _ group: String, _ alpha: Double, _ net: Double) -> [LineConflict] {
            LineConflicts.conflicts(element: el, line: group, lineEnergyKeV: alpha, parents: finalParents.map(\.parent).filter { $0.element != el },
                                    toleranceKeV: sumPeakToleranceKeV, context: context).filter { c in
                // A self pair (one parent) spends two photons of its line per event: at most half that parent.
                let pairShare = c.requires.count == 1 ? 0.5 : 1.0
                return c.kind != .sumPeak || (c.requires.compactMap { parentNets[$0] }.min() ?? 0) * pairShare * sumPeakFraction >= net
            }
        }
        var candidates: [ElementCandidate] = []
        func append(_ el: String, group: String, stat st: Stat, familyNote: String? = nil, possibleReason: String? = nil,
                    unconfirmable: Bool = false) throws {
            let alpha = XRayLines.line(group)?.energy ?? 0
            var note: String?
            if context.gridElements.contains(el) {
                if let hole = holeCounts {
                    if cancelled() { throw ProposerError.cancelled }
                    let hp = try Self.fitPass(groups: currentGroups + poolGroups.filter { $0.element == el }, data: hole, settings: s, axis: axis,
                                              channels: channels, dropped: dropped, relative: t.relativeModelTerm, widths: widths, weighted: false)
                    if let gi = hp.model.groups.firstIndex(where: { $0.id == group }), let hs = stat(hp, gi) {
                        note = hs.net >= hs.ld
                            ? String(format: "%@ is also detected on the hole region (net %.0f \u{2265} L_D %.0f): part of it is grid.", el, hs.net, hs.ld)
                            : String(format: "No %@ on the hole region (net %.0f < L_D %.0f): the %@ belongs to the sample.", el, hs.net, hs.ld, el)
                    }
                } else { note = el == "Cu" ? "No hole region available: Cu grid and Q phase cannot be separated."
                                              : "No hole region available: \(el) from the grid and from the sample cannot be separated." }
            }
            candidates.append(ElementCandidate(
                element: el, group: group, energyKeV: alpha, net: st.net, sigma: st.sigma, sigmaZero: st.sigmaZero,
                criticalLevel: st.lc, detectionLimit: st.ld, conflicts: conflicts(el, group, alpha, st.net),
                suggestedRole: context.quantifyByDefault.contains(el) ? .quantify : .fitOnly, holeRegionNote: note, misfit: 1,
                familyNote: familyNote, possibleReason: possibleReason, unconfirmable: unconfirmable))
        }
        /// The numbers of a group whose limit cannot be stated: its area, no limit (never proposed).
        func unstated(_ p: Pass, _ gi: Int) -> Stat { Stat(net: p.result.values[gi], sigma: 0, sigmaZero: 0, lc: .infinity, ld: .infinity) }
        let noLimit = "Its area has no stated limit (the fit with it is rank deficient)."
        for el in foundOrder where model.contains(where: { $0.element == el }) {
            guard let f = found[el], let first = report.model.groups.firstIndex(where: { $0.element == el }) else { continue }
            let gs = report.model.groups.enumerated().filter { $0.element.element == el }.compactMap { gi, g in stat(report, gi).map { (g, $0) } }
            guard let (g, st) = gs.max(by: { $0.1.significance < $1.1.significance }) else {
                try append(el, group: report.model.groups[first].id, stat: unstated(report, first), possibleReason: noLimit)
                continue
            }
            var reason: String?
            if let u = f.unconfirmable {
                reason = u
            } else if !f.ambiguous.isEmpty {
                reason = String(format: "%@ explain%@ the peak at %.3f keV about as well (within %.0f of its gain there, %.0f).",
                                f.ambiguous.map { sumInfo[$0]?.label ?? $0 }.joined(separator: ", "), f.ambiguous.count == 1 ? "s" : "", f.peakKeV, t.ambiguityGain, f.gain)
            } else if el == "Si", let gi = report.model.groups.firstIndex(where: { $0.id == "Si_Ka" }), report.result.values[gi] < t.siliconArtefactFraction * totalCounts {
                reason = String(format: "Si K\u{03B1} holds %.2f %% of the counts, below the %.1f %% under which it is the detector's own Si.", 100 * report.result.values[gi] / totalCounts, 100 * t.siliconArtefactFraction)
            } else if st.net < st.ld {
                reason = String(format: "It joined on the identification fit, but in the standard fit its area %.0f is below its detection limit %.0f.", st.net, st.ld)
            } else if let band = unhealthy.first(where: { f.peakKeV >= $0.lo && f.peakKeV < $0.hi }) {
                reason = String(format: "Its peak (%.3f keV) lies where the background is off (data over model %.2f in %.1f to %.1f keV).", f.peakKeV, band.ratio, band.lo, band.hi)
            }
            try append(el, group: g.id, stat: st, possibleReason: reason, unconfirmable: f.unconfirmable != nil)
        }
        for el in foundOrder { if let p = pruned[el] {
            try append(el, group: p.group, stat: p.stat ?? Stat(net: 0, sigma: 0, sigmaZero: 0, lc: .infinity, ld: .infinity), possibleReason: p.reason)
        } }
        for (el, tr) in trials.sorted(by: { $0.key < $1.key }) where !candidates.contains(where: { $0.element == el }) {
            let st = tr.stat ?? tr.pass.flatMap { p in p.model.groups.firstIndex { $0.id == tr.group }.map { unstated(p, $0) } }
                ?? Stat(net: 0, sigma: 0, sigmaZero: 0, lc: .infinity, ld: .infinity)
            if let c = tr.confirmation { try append(el, group: tr.group, stat: st, familyNote: c) }
            else { try append(el, group: tr.group, stat: st, possibleReason: tr.reason ?? "Tested but not added.") }
        }
        for f in overlapFinds where !candidates.contains(where: { $0.element == f.element }) {
            if let st = f.trial.stat { try append(f.element, group: f.trial.group, stat: st, possibleReason: f.trial.reason) }
        }
        candidates.sort { $0.significance > $1.significance }

        var sumPeaks: [SumPeakFinding] = []
        for (gi, g) in report.model.groups.enumerated() where g.element == "sum" {
            guard let st = stat(report, gi), let info = sumInfo[g.id] else { continue }
            sumPeaks.append(SumPeakFinding(label: info.label, elements: info.elements, energyKeV: g.lines[0].energy,
                                           net: st.net, sigmaZero: st.sigmaZero, detectionLimit: st.ld))
        }

        var notes = [
            String(format: "Lines below %.2f keV are not tested (a measured limit of the continuum model, not a property of the method).", minimumLineEnergyKeV),
            String(format: "Identification (validation: none): the residual's peaks at or above %.0f \u{03C3} of its top-hat filter (%.1f \u{00D7} below %.0f keV); a candidate joins when \u{03A3}(y \u{2212} \u{03BC})\u{00B2}/(\u{03BC} + (%.2f \u{03BC})\u{00B2}) falls by at least %.0f, %.0f %% of that at its own lines, with its area at or above Currie L_D (\(Self.rateText(currie)), \u{03C3}\u{2080} from the fit's own variance with it absent) and no line against it; the final fit drops what it does not need (%.0f). K\u{03B2} weights from NIST EPQ in this fit.",
                   t.peakSigma, t.lowEnergyFactor, t.lowEnergyBelowKeV, t.relativeModelTerm, t.minimumGain, 100 * t.minimumLocalShare, t.pruneGain),
            "Fit: \(fit.result.methodLabel) to decide, \(report.result.methodLabel) for the numbers shown; \(fit.result.backgroundLabel); \(fit.result.escapeLabel); \(fit.result.referenceShapesLabel); \(examined) residual peak\(examined == 1 ? "" : "s") examined, \(tested) candidate fits, \(fitsDone) fits in all.",
        ]
        if let p = policy.noteLine { notes.insert(p, at: 3) }
        if EPQLineWeights.bundled == nil { notes.append("The NIST EPQ line weights are missing from this build: the identification fit used eXSpy's Kβ weights.") }
        if familyConsistency {
            notes.append("Confirmation lines (validation: none): an element nominated by an L or M line needs its K or L alpha line at \(String(format: "%.0f", t.confirmationSigma)) \u{03C3} in the residual where the fitted range holds it and the beam is at least \(familyOvervoltage) times its energy; otherwise it is withheld.")
            if let z = downwardFamilyMinimumZ {
                notes.append("Downward confirmation (validation: none): an element of Z \u{2265} \(z) nominated by a K line needs its L\u{03B1} line at \(String(format: "%.0f", t.confirmationSigma)) \u{03C3} in the residual where the fitted range holds it; otherwise it is withheld.")
            }
            notes += candidates.compactMap { c in c.familyNote.map { "Confirmation withheld \(c.element): \($0)" } }
        }
        if overlapCheck {
            notes.append(String(format: "Overlap check (validation: none): every element whose lines all sit under modelled lines was fitted once with the settled model; %d reached L_D with a gain of at least %.0f and are possible only.", overlapFinds.count, t.minimumGain))
        }
        for b in unhealthy { notes.append(String(format: "Background check: data over model %.2f off the lines in %.1f to %.1f keV (0.80 to 1.25 is healthy); a find there is only possible.", b.ratio, b.lo, b.hi)) }
        let pChance = 0.5 * erfc((currie.zAlpha + currie.zBeta) / 2.0.squareRoot())
        notes.append(String(format: "Look-elsewhere: %d candidates were tested, so about %.2f chance passes of the area bar alone are expected; the gain and confirmation bars stand beside it.", tested, Double(tested) * pChance))
        if capped && examined >= t.maximumPeaks { notes.append("The loop stopped after \(t.maximumPeaks) residual peaks: this spectrum keeps producing peaks, which points to a model misfit (continuum or line shapes) rather than to that many elements.") }
        if capped && foundOrder.count >= t.maximumNewElements { notes.append("The loop stopped at \(t.maximumNewElements) new elements.") }
        for w in report.result.warnings where !notes.contains(w) { notes.append(w) }
        progress?(1)
        return ProposalResult(candidates: candidates, sumPeaks: sumPeaks, refused: refused, currie: currie,
                              notes: notes, passes: fitsDone, settled: !(capped && examined >= t.maximumPeaks),
                              reducedChiSquared: report.result.pearsonReducedChiSquared)
    }

    /// "Ba_Lb1" -> "Lβ1".
    private static func lineLabel(_ id: String) -> String {
        let name = id.drop { $0 != "_" }.dropFirst()
        return String(name.prefix(1)) + name.dropFirst().map { c in ["a": "\u{03B1}", "b": "\u{03B2}", "g": "\u{03B3}"][c] ?? String(c) }.joined()
    }
}
