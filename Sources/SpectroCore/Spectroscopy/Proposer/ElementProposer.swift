//
//  ElementProposer.swift
//  Role: Propose elements from a pooled spectrum with the landed model fit. It RETURNS candidates and never touches
//        an element list: nothing is added silently (ADR 054, V5-Q6). Round 3, rebuilt on lane F's `EDSFit`.
//
//  Why a joint fit (what rounds 1 and 2 got wrong, 2026-10-05, Fable's re-check): a window or sideband proposer has
//  no model of the neighbours, so an unlisted line reads as a signal or a deficit in every listed window beside it
//  (an unlisted O K-alpha biased Na, Mg and Si by up to -40 L_D; a Ga L-alpha tail made a false Mg at x100 dose) and
//  its own continuum polynomial cannot follow a realistic Kramers x window-absorption continuum with an Al K step.
//  Here:
//   * the continuum is the fit's own default (Kramers x non-negative Bernstein, split at the Al K edge), fitted with
//     the lines, never a second background of the proposer's;
//   * EVERY candidate element is a column of one non-negative least-squares fit together with the current element
//     set, so the fit itself tells overlapping lines apart (no windows, no sidebands, no shadow rule) and an
//     unlisted strong line is a column of its own instead of a bias on its neighbours. Chosen over "one candidate
//     at a time" because that is exactly the design that failed: with a candidate tested alone every other
//     unlisted line is unmodelled;
//   * the all-candidate fit has many collinear columns (Ga L, Na K, Mg K, Zn L ...), whose covariance is
//     inflated, so a candidate is first PRUNED when its net is below Currie's L_C and the fit is repeated with the
//     survivors, until the surviving set no longer changes (at most `maxPasses`). L_D is judged on the final fit;
//   * a pile-up (sum) peak is a column of its own where no candidate sits near its energy, so it cannot create a
//     phantom element; where a candidate does sit near it (Ar at the Al+Al sum, 15 eV apart) the two cannot be
//     separated by any fit and the candidate carries the named conflict instead;
//   * the detection bar is Currie's L_D (alpha = beta = 0.05, a convention reported with every result; L_C and
//     L_D are properties of the dataset) with sigma_0 the standard deviation of the candidate's area when it is
//     absent, from the fit's own variance (`FitNullVariance`): the continuum and every other line under its window.
//
//  DEVIATION (the fit's settings): the proposer always uses unweighted least squares (the named default); an
//  expert Poisson-ML choice is for the reported fit, not for screening, because the null variance is the LS sandwich.
//  DEVIATION (Currie): L_D assumes the variance at a true net L is sigma_0^2 + L; an efficient amplitude estimator
//  has a slightly LARGER one than the window sum Currie derived it for: for unweighted LS the own-line variance factor is
//  sum g^3 / (sum g^2)^2 = 2/sqrt(3) = 1.155 for a Gaussian. L_D is therefore a little optimistic (effect < 1 %, sigma_0^2 dominates).
//  The fit's weak-line warning (a weak line beside Al K-alpha reads low) is carried into `notes`.
//

import Foundation

package nonisolated struct ElementCandidate: Equatable, Sendable {
    package let element: String
    /// The line group with the largest net / L_D, e.g. "Mg_Ka".
    package let group: String
    /// Energy of the group's alpha line, keV.
    package let energyKeV: Double
    /// Fitted line area in counts (>= 0: the fit is non-negative).
    package let net: Double
    /// Standard deviation of the area at the fitted state (it contains the line's own Poisson variance).
    package let sigma: Double
    /// Standard deviation of the area with the candidate absent (the basis of L_C and L_D).
    package let sigmaZero: Double
    package let criticalLevel: Double
    package let detectionLimit: Double
    package let conflicts: [LineConflict]
    /// Cu defaults to Quantify (the Q phase); everything else to Fit only.
    package let suggestedRole: QuantificationMethod.ElementRole
    /// Cu only, when a hole spectrum was given: what the hole region said.
    package let holeRegionNote: String?
    /// The flank-misfit factor sigma_0 was multiplied by (>= 1; 1 = the fit's own variance unchanged).
    package let misfit: Double

    /// net >= L_D: the proposer's bar.
    package var aboveDetectionLimit: Bool { net >= detectionLimit }
    /// L_C < net < L_D: shown as "possible", never proposed.
    package var aboveCriticalLevel: Bool { net > criticalLevel }
    package var isProposed: Bool { aboveDetectionLimit }
    package var hasSumPeakQuestion: Bool { conflicts.contains { $0.kind == .sumPeak } }
    /// How many detection limits the net is (the order in which to show candidates).
    package var significance: Double { net / detectionLimit }

    /// Explicit so the room's tests can state a candidate (the memberwise one is internal).
    package init(element: String, group: String, energyKeV: Double, net: Double, sigma: Double, sigmaZero: Double,
                 criticalLevel: Double, detectionLimit: Double, conflicts: [LineConflict],
                 suggestedRole: QuantificationMethod.ElementRole, holeRegionNote: String?, misfit: Double) {
        self.element = element; self.group = group; self.energyKeV = energyKeV; self.net = net; self.sigma = sigma
        self.sigmaZero = sigmaZero; self.criticalLevel = criticalLevel; self.detectionLimit = detectionLimit
        self.conflicts = conflicts; self.suggestedRole = suggestedRole; self.holeRegionNote = holeRegionNote; self.misfit = misfit
    }
}

/// A pile-up peak the fit modelled as a column of its own (no candidate sat near its energy).
package nonisolated struct SumPeakFinding: Equatable, Sendable {
    package let label: String
    package let elements: [String]
    package let energyKeV: Double
    package let net: Double
    package let sigmaZero: Double
    package let detectionLimit: Double
    package var detected: Bool { net >= detectionLimit }
}

package nonisolated struct ProposalResult: Sendable {
    /// One per pool element with a line group in the fitted range, strongest first.
    package let candidates: [ElementCandidate]
    package let sumPeaks: [SumPeakFinding]
    package let refused: [(element: String, reason: String)]
    package let currie: Currie
    /// The fit settings and warnings that shaped the result, in plain words (the footer).
    package let notes: [String]
    package let passes: Int
    package let settled: Bool
    /// Pearson reduced chi-square of the settled fit these candidates came from (R7, wp3e F3.3: shown beside every suggestion;
    /// a read of the fit, nothing here changes it). nil for a hand-built result.
    package let reducedChiSquared: Double?
    /// At or above L_D and carrying NO sum-peak conflict: an element the data support.
    package var proposed: [ElementCandidate] { candidates.filter { $0.isProposed && !$0.hasSumPeakQuestion } }
    /// At or above L_D but sitting on a pile-up energy of the detected parents: "sum peak or this element?", not a finding.
    package var sumPeakQuestions: [ElementCandidate] { candidates.filter { $0.isProposed && $0.hasSumPeakQuestion } }
    package var possible: [ElementCandidate] { candidates.filter { $0.aboveCriticalLevel && !$0.isProposed } }

    /// Explicit so the room's tests can state a result (the memberwise one is internal).
    package init(candidates: [ElementCandidate], sumPeaks: [SumPeakFinding], refused: [(element: String, reason: String)],
                 currie: Currie, notes: [String], passes: Int, settled: Bool, reducedChiSquared: Double? = nil) {
        self.reducedChiSquared = reducedChiSquared
        self.candidates = candidates; self.sumPeaks = sumPeaks; self.refused = refused; self.currie = currie
        self.notes = notes; self.passes = passes; self.settled = settled
    }
}

package nonisolated enum ProposerError: Error, Equatable {
    case lengthMismatch
    case noChannels
    /// The joint design is numerically rank deficient: no covariance, so no limit can be stated.
    case rankDeficient
    /// The calling task was cancelled (checked before every fit, each a fraction of a second). Not a failure: the caller discards.
    case cancelled
}

package nonisolated struct ElementProposer: Sendable {
    package var currie: Currie
    /// The elements tested; nil is `defaultPool`.
    package var pool: [String]?
    package var maxPasses: Int
    /// The forward step stops after this many rounds (a joiner or a rejection each costs one): a spectrum that keeps producing
    /// candidates is a model failure, not a rich sample, and the room must not hang on it. Said in the notes when reached.
    package var maxForwardRounds: Int
    /// A candidate group is tested only if its alpha line is at or above this energy (keV). MEASURED, not a property of the
    /// method: on the Kramers x window-absorption generator the only false elements at x100 dose were C K, N K, Ca L and
    /// Sc L at 0.28-0.40 keV, where the detector window cuts the continuum steeply and the fit's continuum cannot follow
    /// it at 10^4 counts per channel (lane P report). 0.45 keV keeps O K-alpha (0.525). Reported in every result's notes;
    /// an element with lines in range but none above it is refused with this reason (the user can still list it by hand).
    package var minimumLineEnergyKeV: Double
    /// Scale sigma_0 by the flank misfit factor (see `flankMisfit`). On unless a test compares it off.
    package var flankScaling = true

    /// Elements the line table lists that no spectrum of a material shows or that the app has no use for:
    /// radioactive or absent from the table (Tc, Pm, Po, At, Rn, Fr, Ra, Ac, Pa, Np, Pu, Am), noble gases other than Ar
    /// (Ne, Kr, Xe; Ar is a named conflict). A reader may pass any `pool` instead.
    package static let defaultExcluded: Set<String> = ["Tc", "Pm", "Po", "At", "Rn", "Fr", "Ra", "Ac", "Pa", "Np", "Pu", "Am", "Ne", "Kr", "Xe"]

    /// Every element of the line table, minus the refused (H, He, Li, Be) and `defaultExcluded`.
    package static var defaultPool: [String] {
        var seen = Set<String>(), out: [String] = []
        for l in XRayLines.all where !seen.contains(l.element) {
            seen.insert(l.element)
            if LineConflicts.refusal(for: l.element) == nil, !defaultExcluded.contains(l.element) { out.append(l.element) }
        }
        return out
    }

    package init(currie: Currie = .standard, pool: [String]? = nil, maxPasses: Int = 5, maxForwardRounds: Int = 24, minimumLineEnergyKeV: Double = 0.45) {
        self.currie = currie; self.pool = pool; self.maxPasses = maxPasses; self.maxForwardRounds = maxForwardRounds; self.minimumLineEnergyKeV = minimumLineEnergyKeV
    }

    private struct Stat { var net: Double, sigma: Double, sigmaZero: Double, lc: Double, ld: Double, misfit: Double
        var significance: Double { net / ld } }

    private struct Pass {
        var model: EDSLineModel
        var result: EDSFitResult
        var variances: AmplitudeVariances
    }

    /// - Parameters:
    ///   - counts: the pooled spectrum, one value per channel of `axis`.
    ///   - settings: the fit as the room runs it. `elements` is the CURRENT set (always fitted, never changed);
    ///     range, background, escape setting and reference shapes are used as given, the method is forced to LS.
    ///   - holeCounts: optional pooled spectrum of a hole region on the same axis, for the Cu grid check.
    package func propose(counts: [Double], axis: EnergyAxis, settings: FitSettings,
                         holeCounts: [Double]? = nil) throws -> ProposalResult {
        guard counts.count == axis.size, holeCounts.map({ $0.count == axis.size }) ?? true else { throw ProposerError.lengthMismatch }
        var s = settings
        s.method = .leastSquares
        let channels = axis.fitChannels(from: s.fitFrom, to: s.fitTo)
        guard !channels.isEmpty else { throw ProposerError.noChannels }
        let lo = axis.energy(ofChannel: channels.lowerBound), hi = axis.energy(ofChannel: channels.upperBound - 1)
        let current = s.elements
        let requested = pool ?? Self.defaultPool

        var refused: [(element: String, reason: String)] = []
        var seenRefused = Set<String>()
        for el in LineConflicts.refusedElements + requested + current where !seenRefused.contains(el) {
            if let reason = LineConflicts.refusal(for: el) { refused.append((el, reason)); seenRefused.insert(el) }
        }
        let poolElements = requested.filter { LineConflicts.refusal(for: $0) == nil && !current.contains($0) }

        let base = EDSLineModel.build(elements: current + poolElements, axis: axis, beamEnergy: s.beamEnergy,
                                      resolutionMnKaEV: s.resolutionMnKaEV, escapePeaks: s.escapePeaks)
        let dropped = base.droppedLines.filter { l in current.contains { l.contains("\($0)_") } }
        let currentGroups = base.groups.filter { current.contains($0.element) }
        // A candidate group needs its alpha line inside the fitted range by half a width (its column must have support).
        let poolGroups = base.groups.filter { g in
            poolElements.contains(g.element) && g.lines[0].energy >= max(lo + g.lines[0].fwhm / 2, minimumLineEnergyKeV)
                && g.lines[0].energy <= hi - g.lines[0].fwhm / 2
        }
        for el in poolElements where !poolGroups.contains(where: { $0.element == el }) {
            if let low = base.groups.filter({ $0.element == el && $0.lines[0].energy < minimumLineEnergyKeV }).map({ $0.lines[0].energy }).max() {
                refused.append((el, String(format: "Its line at %.2f keV lies below the proposer's lowest tested line (%.2f keV): under the detector window the continuum is too model-dependent for a net area to be trusted. List it by hand if you know it is there.", low, minimumLineEnergyKeV)))
            }
        }

        func run(_ groups: [FitLineGroup], on data: [Double]) throws -> Pass {
            if Task.isCancelled { throw ProposerError.cancelled }
            let model = EDSLineModel(groups: groups, resolutionMnKaEV: s.resolutionMnKaEV, beamEnergy: s.beamEnergy,
                                     escapePeaks: s.escapePeaks, droppedLines: dropped)
            try EDSFit.validate(s.referenceShapes, axis: axis, model: model)
            let design = LinearDesign.build(model: model, axis: axis, channels: channels, background: s.background,
                                            shapes: s.referenceShapes, counts: data)
            let result = EDSFit.fit(design: design, model: model, counts: data, settings: s, computeCovariance: false)
            guard let v = FitNullVariance.compute(design: design, result: result) else { throw ProposerError.rankDeficient }
            return Pass(model: model, result: result, variances: v)
        }
        func stat(_ p: Pass, _ gi: Int) -> Stat? {
            guard p.result.supported[gi], let v0 = p.variances.null[gi], let vf = p.variances.atFit[gi] else { return nil }
            let f = flankScaling ? flankMisfit(p, gi) : 1
            let s0 = v0.squareRoot() * f
            return Stat(net: p.result.values[gi], sigma: vf.squareRoot() * f, sigmaZero: s0,
                        lc: currie.criticalLevel(sigmaZero: s0), ld: currie.detectionLimit(sigmaZero: s0), misfit: f)
        }
        /// sqrt(max(1, mean Z^2)) of the fit's residual summed in bins of one FWHM on both flanks of group `gi`
        /// (1.5 to 6.5 FWHM from its alpha line, ten bins at most). Z = sum(residual) / sqrt(sum(max(model, 1))) is N(0, 1) when
        /// the model is right; a smooth continuum misfit is correlated over the bins and shows up here although it hides in
        /// the per-channel chi-square. The flanks leave out the line itself, so a real line does not inflate its own limit.
        func flankMisfit(_ p: Pass, _ gi: Int) -> Double {
            let line = p.model.groups[gi].lines[0]
            let f = line.fwhm
            let first = p.result.channels.lowerBound
            var z2: [Double] = []
            for side in [-1.0, 1.0] { for b in 0..<5 {
                let a = line.energy + side * (1.5 + Double(b)) * f, c = line.energy + side * (2.5 + Double(b)) * f
                let lowE = min(a, c), highE = max(a, c)
                var r = 0.0, m = 0.0, n = 0
                for ch in p.result.channels {
                    let e = axis.energy(ofChannel: ch)
                    if e >= lowE && e < highE { r += p.result.residual[ch - first]; m += max(p.result.model[ch - first], EDSFitResult.standardizedFloor); n += 1 }
                }
                if n >= 3 { z2.append(r * r / m) }
            } }
            guard z2.count >= 3 else { return 1 }
            return max(1, z2.reduce(0, +) / Double(z2.count)).squareRoot()
        }

        var active = Set(poolGroups.map(\.id))
        var sumElements: [String: (label: String, elements: [String])] = [:]
        var last: [String: Stat] = [:]
        var parents: [SumParent] = []
        var passes = 0, trials = 0, settled = true

        /// The candidates that claim a pile-up energy: the active ones at or above L_D in their last fit. A candidate that is only
        /// "possible" must not claim it (it would swallow the sum peak through its inflated covariance and block the sum column).
        func claiming(_ active: Set<String>) -> Set<String> { active.filter { last[$0].map { $0.net >= $0.ld } ?? false } }

        /// The pile-up columns for a set of detected parents: every pair whose energy is in range and not claimed by a listed
        /// line or by a claiming candidate (a claimed energy is the candidate's: the two cannot be told apart). Pairs whose energies
        /// coincide in the line table (Dy+Ti and Cs+Ho at 11.0061 keV) share ONE column: two identical design columns make the
        /// joint design rank deficient (the whole run fails), and the fit cannot tell such pairs apart. The kept column's id and
        /// label name every pair it stands for; a lone pair keeps its plain id and label.
        /// Equality to rounding, not a tolerance: the line table carries four decimals, so only sums equal in the table merge
        /// (registration: docs/archive/v5/sum-column-exact-dedup-preregistration-2026-10-08.md).
        let exactSumToleranceKeV = 1e-9
        func sumColumns(_ parents: [SumParent], claiming claimers: Set<String>) -> [FitLineGroup] {
            var claimed = currentGroups.map { $0.lines[0].energy }
            claimed += poolGroups.filter { claimers.contains($0.id) }.map { $0.lines[0].energy }
            var pairs: [[(label: String, energyKeV: Double, elements: [String])]] = []
            for e in LineConflicts.sumEnergies(parents: parents) {
                guard e.energyKeV > lo, e.energyKeV < hi, e.energyKeV < s.beamEnergy,
                      !claimed.contains(where: { abs($0 - e.energyKeV) <= LineConflicts.sumPeakToleranceKeV }),
                      XRayLines.fwhm(resolutionMnKaEV: s.resolutionMnKaEV, atEnergy: e.energyKeV) != nil else { continue }
                // The first pair at an energy owns the column (its energy is the column's).
                if let k = pairs.firstIndex(where: { abs($0[0].energyKeV - e.energyKeV) <= exactSumToleranceKeV }) {
                    pairs[k].append(e)
                } else { pairs.append([e]) }
            }
            var out: [FitLineGroup] = []
            for group in pairs {
                let first = group[0]
                let id = "sum:" + group.map { $0.elements.joined(separator: "+") }.joined(separator: " / ")
                let label = group.count == 1 ? first.label : group.map { $0.label.replacingOccurrences(of: " sum", with: "") }.joined(separator: " / ") + " sum"
                let w = XRayLines.fwhm(resolutionMnKaEV: s.resolutionMnKaEV, atEnergy: first.energyKeV)!
                out.append(FitLineGroup(id: id, element: "sum", lines: [FitLine(id: id, energy: first.energyKeV, weight: 1, fwhm: w)], escapes: []))
                sumElements[id] = (label, group.count == 1 ? first.elements : Array(Set(group.flatMap(\.elements))).sorted())
            }
            return out
        }

        /// Backward step: fit everything active (with the pile-up columns the current parents imply), drop what is not above
        /// L_C, repeat until the active set and the parents are stable.
        func settle() throws -> Pass {
            var iteration = 0
            while true {
                iteration += 1; passes += 1
                let sums = sumColumns(parents, claiming: claiming(active))
                let p = try run(currentGroups + poolGroups.filter { active.contains($0.id) } + sums, on: counts)
                for (gi, g) in p.model.groups.enumerated() { if let st = stat(p, gi) { last[g.id] = st } }
                // Survivors: candidates above L_C.
                let nextActive = Set(p.model.groups.enumerated().compactMap { gi, g -> String? in
                    guard active.contains(g.id), let st = stat(p, gi), st.net > st.lc else { return nil }
                    return g.id
                })
                // Parents: the strongest detected group of each element, among the current set and the survivors. A survivor that sits
                // on a pile-up peak of the LISTED parents is the question, not a parent (Ar at the Al+Al sum must not make Ar+Al sums).
                var best: [String: (sig: Double, energy: Double, listed: Bool)] = [:]
                for (gi, g) in p.model.groups.enumerated() where g.element != "sum" {
                    guard let st = stat(p, gi), st.net >= st.ld, nextActive.contains(g.id) || !active.contains(g.id) else { continue }
                    if best[g.element].map({ st.significance > $0.sig }) ?? true {
                        best[g.element] = (st.significance, g.lines[0].energy, current.contains(g.element))
                    }
                }
                let listed = best.filter { $0.value.listed }.map { SumParent(element: $0.key, energyKeV: $0.value.energy) }
                let listedSums = LineConflicts.sumEnergies(parents: listed).map(\.energyKeV)
                let found = best.filter { entry in
                    !entry.value.listed && !listedSums.contains { abs($0 - entry.value.energy) <= LineConflicts.sumPeakToleranceKeV }
                }.map { SumParent(element: $0.key, energyKeV: $0.value.energy) }
                let nextParents = (listed + found).sorted { $0.element < $1.element }
                let stable = nextActive == active && sumColumns(nextParents, claiming: claiming(nextActive)).map(\.id) == sums.map(\.id)
                parents = nextParents
                if stable { return p }
                if iteration >= maxPasses { settled = false; return p }
                active = nextActive
            }
        }

        // Forward step: every pruned candidate is tested ALONE against the settled model (the all-candidate fit has
        // collinear columns, whose inflated covariance can prune a real weak line); the most significant one at or
        // above L_D joins, and the model settles again. A candidate that was pruned after joining, or displaced by a joiner,
        // stays out.
        var banned = Set<String>()
        var fit = try settle()
        // The single-candidate tests depend on the settled model (its active set; the parents move little). After a joiner was
        // pruned again the active set is unchanged and the other tests are reused (otherwise a crowded spectrum costs a full
        // round per rejected joiner).
        var cache: [String: Stat] = [:]
        var cacheKey = ""
        var rounds = 0, forwardCapped = false
        while true {
            if rounds >= maxForwardRounds { forwardCapped = true; break }
            rounds += 1
            let key = active.sorted().joined(separator: ",")
            if key != cacheKey { cache = [:]; cacheKey = key }
            var best: (id: String, significance: Double)?
            for g in poolGroups where !active.contains(g.id) && !banned.contains(g.id) {
                if cache[g.id] == nil {
                    trials += 1
                    let p = try run(currentGroups + poolGroups.filter { active.contains($0.id) || $0.id == g.id } + sumColumns(parents, claiming: claiming(active).union([g.id])), on: counts)
                    guard let gi = p.model.groups.firstIndex(where: { $0.id == g.id }), let st = stat(p, gi) else { continue }
                    cache[g.id] = st
                    last[g.id] = st
                }
                if let st = cache[g.id], st.net >= st.ld, st.significance > (best?.significance ?? 0) { best = (g.id, st.significance) }
            }
            guard let b = best else { break }
            active.insert(b.id)
            let before = active
            fit = try settle()
            // Whatever the settled fit dropped (the joiner itself or a rival it displaced) stays out: this ends the loop.
            banned.formUnion(before.subtracting(active))
        }

        // Candidates: one per pool element, its best group.
        var candidates: [ElementCandidate] = []
        for el in poolElements {
            let gs = poolGroups.filter { $0.element == el }.compactMap { g in last[g.id].map { (g, $0) } }
            guard let (g, st) = gs.max(by: { $0.1.significance < $1.1.significance }) else { continue }
            let alpha = g.lines[0].energy
            let conflicts = LineConflicts.conflicts(element: el, line: g.id, lineEnergyKeV: alpha, parents: parents)
            var note: String?
            if el == "Cu" {
                if let hole = holeCounts {
                    let hp = try run(currentGroups + poolGroups.filter { $0.element == "Cu" }, on: hole)
                    if let gi = hp.model.groups.firstIndex(where: { $0.id == g.id }), let hs = stat(hp, gi) {
                        note = hs.net >= hs.ld
                            ? String(format: "Cu is also detected on the hole region (net %.0f \u{2265} L_D %.0f): part of it is grid.", hs.net, hs.ld)
                            : String(format: "No Cu on the hole region (net %.0f < L_D %.0f): the Cu belongs to the sample.", hs.net, hs.ld)
                    }
                } else { note = "No hole region available: Cu grid and Q phase cannot be separated." }
            }
            candidates.append(ElementCandidate(
                element: el, group: g.id, energyKeV: alpha, net: st.net, sigma: st.sigma, sigmaZero: st.sigmaZero,
                criticalLevel: st.lc, detectionLimit: st.ld, conflicts: conflicts,
                suggestedRole: el == "Cu" ? .quantify : .fitOnly, holeRegionNote: note, misfit: st.misfit))
        }
        candidates.sort { $0.significance > $1.significance }

        var sumPeaks: [SumPeakFinding] = []
        for (gi, g) in fit.model.groups.enumerated() where g.element == "sum" {
            guard let st = stat(fit, gi), let info = sumElements[g.id] else { continue }
            sumPeaks.append(SumPeakFinding(label: info.label, elements: info.elements, energyKeV: g.lines[0].energy,
                                           net: st.net, sigmaZero: st.sigmaZero, detectionLimit: st.ld))
        }

        var notes = [
            String(format: "Lines below %.2f keV are not tested (a measured limit of the continuum model, not a property of the method).", minimumLineEnergyKeV),
            String(format: "Detection: fitted net \u{2265} Currie L_D (\u{03B1} = \u{03B2} = %.2f, a convention; L_C and L_D are properties of this spectrum), \u{03C3}\u{2080} from the fit's own variance with the candidate absent.", currie.alpha),
            "Fit: \(fit.result.methodLabel); \(fit.result.backgroundLabel); \(fit.result.escapeLabel); \(fit.result.referenceShapesLabel); \(poolGroups.count) candidate line groups: \(passes) joint fit\(passes == 1 ? "" : "s") pruned at L_C, then \(trials) single-candidate tests of the pruned ones against the settled model.",
        ]
        let near = candidates.filter { $0.significance >= 0.5 }
        let inflated = near.filter { $0.misfit > 1.005 }
        notes.append(inflated.isEmpty
            ? "Flank-misfit scaling: no proposed or near-miss candidate (net/L_D \u{2265} 0.5) had its \u{03C3}\u{2080} inflated."
            : "\u{03C3}\u{2080} was scaled by the flank-misfit factor (never below 1; a neighbour's misfit inflates every candidate within about \u{00B1}0.5 keV): "
                + inflated.map { String(format: "%@ \u{00D7}%.2f", $0.element, $0.misfit) }.joined(separator: ", ") + " (candidates at net/L_D \u{2265} 0.5).")
        let pChance = 0.5 * erfc((currie.zAlpha + currie.zBeta) / 2.0.squareRoot())
        notes.append(String(format: "Look-elsewhere: %d line groups were tested, so about %d \u{00D7} %.1e = %.2f chance proposals per spectrum are expected; a candidate near net/L_D = 1 is as likely chance as real.", poolGroups.count, poolGroups.count, pChance, Double(poolGroups.count) * pChance))
        if !settled { notes.append("The surviving set did not settle in \(maxPasses) passes: the last fit is shown.") }
        if forwardCapped { notes.append("The forward step stopped at \(maxForwardRounds) rounds: this spectrum keeps producing candidates, which points to a model misfit (continuum or line widths) rather than to that many elements.") }
        for w in fit.result.warnings where !notes.contains(w) { notes.append(w) }
        return ProposalResult(candidates: candidates, sumPeaks: sumPeaks, refused: refused, currie: currie,
                              notes: notes, passes: passes, settled: settled,
                              reducedChiSquared: fit.result.pearsonReducedChiSquared)
    }
}
