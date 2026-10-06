//
//  PooledQuantification.swift
//  Role: The Quantify verb's computation (v5.0 R3, ADR 054): one pooled spectrum + a `QuantificationMethod`
//        -> the fit (EDSFit), the energy axis refinement, net areas with sigma, the k-free ratios, and, ONLY
//        when a k source exists, at%/wt% with sigma as named terms. Nothing here draws or reads a view; the
//        room's controller calls it off the main actor and puts the answer in the model.
//
//  What is refused, with the reason in the result (never a silent default):
//    * no beam energy in the file and none typed: the continuum needs it -> `QuantificationRefusal`;
//    * at%: fewer than two quantified elements, no K line for one of them (the computed k covers K lines
//      only), an incomplete typed k, or Cliff-Lorimer's own refusal (`needTwoLines`) -> `abundanceRefusal`;
//    * absorption (on by default): GMS files (the tilt and the four segments are not read yet, open-items),
//      a missing tilt or segment value, or no typed thickness -> `absorption == .refused(reason)`. The at%
//      is then computed WITHOUT the correction and the result says so; it never pretends.
//
//  DEVIATIONS (named, ADR 054 corrections):
//    * Absorption is iterated to 1e-7 % (eXSpy stops at 0.5 %): the sigma terms are finite differences of
//      the composition, and a loop that stops at 0.5 % would put steps into them.
//    * The absorption "model spread" is |at%(geometric-mean transmission) - at%(weighted-mean transmission)|. The
//      weighted mean is the method and the geometric mean only a comparison (ADR 054 corrections), so the spread is
//      a proxy for how much the averaging rule matters, NOT an uncertainty: it is printed beside the sigma as
//      "absorption model spread (AM vs GM)" and is kept OUT of `SigmaTerms.combined` and of the shown sigma. The real
//      absorption uncertainty would be a mass-absorption-coefficient term with a sourced sigma_mu; that is not in this lane.
//    * Counting term: the fit covariance of the quantified areas propagated through Cliff-Lorimer (+
//      absorption) by central differences. The k term: each non-reference k moved by +-sigma_k (20 % flat,
//      the reference carries 0), the effects added in quadrature. The thickness term: central difference
//      of the whole correction over thickness +- sigma (`ThicknessPropagation`).
//    * Live-time normalisation (ADR 054 item 5) is a REGION-COMPARISON control and is not applied here: every pixel's
//      lines share that pixel's live time and a pool is the counts-weighted mean of its pixels, so it does not change
//      the at% of a single pool.
//    * The k term moves each non-reference k independently by sigma_k; it ignores the correlation a computed set has
//      through its shared reference element (the factors are ratios to one k).
//
//  WHAT IS NOT ESTABLISHED (read before trusting a number):
//    * The axis refinement was REFUTED at low counts: on demo-edx-tiny (706 counts, 24 px) it found -3.0 eV / +0.58 %
//      gain against the planted +10 eV / -0.2 %. The sigma terms carry NO axis term, so a wrong refined axis is not in
//      the shown sigma. Its recovery against counts is unmeasured (open-items).
//    * The absorption test (`SpectroscopyQuantifyTests`) checks plumbing only (applied/refused, terms present, the
//      composition moves); it does not check the correction against a truth geometry (open-items).
//

import Foundation

/// Why the whole Quantify run produced no fit. Carries the sentence shown to the user.
package nonisolated struct QuantificationRefusal: LocalizedError, Equatable {
    package let reason: String
    package init(_ reason: String) { self.reason = reason }
    package var errorDescription: String? { reason }
}

/// The data files the computed k and the absorption correction read (EPQ / FFAST / Krause; Resources/Spectroscopy).
package nonisolated struct QuantificationTables: Sendable {
    package let mac: MassAbsorptionTable
    package let cross: BoteSalvatCrossSection
    package let krause: KrauseFluorescenceYield
    package let weights: EPQLineWeights

    package init(directory: URL) throws {
        mac = try MassAbsorptionTable(contentsOf: directory.appendingPathComponent("FFastMAC.csv"))
        cross = try BoteSalvatCrossSection(directory: directory)
        krause = try KrauseFluorescenceYield(contentsOf: directory.appendingPathComponent("Krause1979.csv"))
        weights = try EPQLineWeights(contentsOf: directory.appendingPathComponent("LineWeights.csv"))
    }

    /// The files shipped in the app bundle (Resources/Spectroscopy), nil when any is missing.
    package static func bundled(in bundle: Bundle = .main) -> QuantificationTables? {
        guard let url = bundle.url(forResource: "LineWeights", withExtension: "csv", subdirectory: "Spectroscopy")
            ?? bundle.url(forResource: "LineWeights", withExtension: "csv") else { return nil }
        return try? QuantificationTables(directory: url.deletingLastPathComponent())
    }
}

package nonisolated struct PooledQuantificationInput: Sendable {
    package var counts: [UInt64]
    package var axis: EnergyAxis
    package var method: QuantificationMethod
    package var metadata: SpectrumImageMetadata
    package var regionName: String
    package var pixelCount: Int
    package var resolutionMnKaEV: Double
    /// A refinement already computed for the same spectrum, elements and background (the controller caches it:
    /// it is the slow step and does not depend on the estimator, k or absorption).
    package var refinement: AxisRefinementResult?

    package init(counts: [UInt64], axis: EnergyAxis, method: QuantificationMethod, metadata: SpectrumImageMetadata,
                 regionName: String, pixelCount: Int, resolutionMnKaEV: Double = 130,
                 refinement: AxisRefinementResult? = nil) {
        self.counts = counts; self.axis = axis; self.method = method; self.metadata = metadata
        self.regionName = regionName; self.pixelCount = pixelCount
        self.resolutionMnKaEV = resolutionMnKaEV; self.refinement = refinement
    }
}

package nonisolated struct PooledQuantification: Sendable {
    package enum AbsorptionStatus: Sendable, Equatable {
        case off
        /// Applied: the segment summary for the footer ("4 segments, take-off 21.6-68.3 deg") and the thickness.
        case applied(String)
        case refused(String)
    }

    package struct Row: Sendable, Equatable {
        package var element: String
        package var groupID: String
        /// Fitted area of the group's alpha line, counts (>= 0).
        package var net: Double
        package var sigma: Double
        package var supported: Bool
        /// The non-negativity bound holds the area at 0: the number is an upper-limit region, not a measurement.
        package var atBound: Bool
        package var isReference: Bool
        /// Net / reference net; the reference row is 1 with no sigma.
        package var kFreeRatio: Double?
        package var kFreeSigma: Double?
        package var atomicPercent: Double?
        package var atomicSigma: Double?
        package var weightPercent: Double?
        package var weightSigma: Double?
        package var atomicTerms: SigmaTerms?
        package var weightTerms: SigmaTerms?
        /// "counting 0.6 % + k 20 % + ... = 21 % -> +-1.1 at%"
        /// Relative |GM - AM| of this row's at% / wt% (model spread, NOT an uncertainty and not in the terms or the sigma); nil when absorption was not applied.
        package var absorptionSpreadAtomic: Double?
        package var absorptionSpreadWeight: Double?
        package var atomicTermsText: String
        package var weightTermsText: String
        package var failure: String?
    }

    package var method: QuantificationMethod
    package var rows: [Row]
    package var referenceElement: String?
    package var fit: EDSFitResult
    package var fileAxis: EnergyAxis
    package var usedAxis: EnergyAxis
    package var axisLocked: Bool
    package var refinement: AxisRefinementResult?
    /// Full-length (axis) curves for the plot; zero outside `fit.channels`.
    package var plotModel: [Double]
    package var plotBackground: [Double]
    package var kSet: KFactorSet?
    /// nil when at% was computed; the reason otherwise.
    package var abundanceRefusal: String?
    package var absorption: AbsorptionStatus
    package var warnings: [String]
    /// "chi2_red 1.04 (Pearson)" or "reduced deviance 1.02".
    package var qualityLabel: String
    package var quality: Double
    /// One line per setting that shaped the number (the results footer).
    package var footerLines: [String]

    package var hasAbundance: Bool { abundanceRefusal == nil }
    /// "unvalidated" whenever an at% was produced (ADR 054 item 3): the cross-section source is validation "none".
    package static let abundanceValidation = "none"
}

package nonisolated enum PooledQuantifier {

    // MARK: Entry

    package static func run(_ input: PooledQuantificationInput, tables: QuantificationTables?) throws -> PooledQuantification {
        var method = input.method
        let active = method.elements.filter { $0.role != .off }.map(\.symbol)
        guard !active.isEmpty else { throw QuantificationRefusal("No element is switched on: pick elements in Elements & maps.") }
        guard let beam = method.beamEnergyKeV ?? input.metadata.beamEnergyKeV, beam > 0 else {
            throw QuantificationRefusal("The file does not state the beam energy and none is typed: the continuum model needs it. Type it in the Quantify inspector.")
        }
        let counts = input.counts.map { Double($0) }
        guard counts.count == input.axis.size else { throw QuantificationRefusal("The spectrum and the energy axis differ in length.") }
        guard counts.contains(where: { $0 > 0 }) else { throw QuantificationRefusal("This region holds no counts.") }

        func settings(axis: EnergyAxis) -> FitSettings {
            var s: FitSettings
            switch method.background {
            case .empiricalWithAlEdge:
                s = FitSettings.standard(elements: active, axis: axis, resolutionMnKaEV: input.resolutionMnKaEV, beamEnergy: beam)
            case .wholeRangePolynomial6:
                let order = min(max(method.polynomialOrder ?? 6, 0), 8)
                s = FitSettings(elements: active, resolutionMnKaEV: input.resolutionMnKaEV, beamEnergy: beam,
                                fitFrom: 0.2, fitTo: min(axis.highValue, beam), background: .polynomial(order: order))
            }
            s.method = method.estimator == .leastSquares ? .leastSquares : .poissonML(IRLSSettings())
            return s
        }

        var warnings: [String] = []
        // Axis: refine on the pooled spectrum unless locked; keep the file's values beside the refined ones.
        let locked = method.lockEnergyAxis == true
        var refinement: AxisRefinementResult?
        var axis = input.axis
        var resolution = input.resolutionMnKaEV
        if !locked {
            refinement = input.refinement
            if refinement == nil {
                do { refinement = try EnergyAxisRefinement.refine(counts: counts, fileAxis: input.axis,
                                                                  fileResolutionMnKaEV: input.resolutionMnKaEV, settings: settings(axis: input.axis)) }
                catch { warnings.append("axis refinement failed (\(error)); the file's axis is used") }
            }
            if let r = refinement {
                if r.rssRefined < r.rssFile { axis = r.refinedAxis; resolution = r.resolutionMnKaEV }
                else { warnings.append("axis refinement did not lower the residual; the file's axis is used") }
            }
        }
        var fitSettings = settings(axis: axis)
        fitSettings.resolutionMnKaEV = resolution
        fitSettings.fitTo = min(axis.highValue, beam)
        let fit: EDSFitResult
        do { fit = try EDSFit.run(counts: counts, axis: axis, settings: fitSettings) }
        catch { throw QuantificationRefusal("The fit could not run: \(error).") }
        // The fit appends the weak-line bias note to every continuum fit; it is a statement about a weak line beside Al K-alpha
        // (measured at Mg K-alpha on synthetic data), so it is kept only when that situation is in this result.
        warnings += fit.warnings.filter { $0 != ContinuumForm.weakLineBiasNote }
        if fit.warnings.contains(ContinuumForm.weakLineBiasNote),
           weakLineBiasApplies(groupIDs: fit.groupIDs, values: fit.values, quantified: method.elements.filter { $0.role == .quantify }.map(\.symbol)) {
            warnings.append(ContinuumForm.weakLineBiasNote)
        }

        // Plot curves: the model, and the background as the fitted continuum columns.
        let lineModel = EDSLineModel.build(elements: active, axis: axis, beamEnergy: beam, resolutionMnKaEV: resolution,
                                           escapePeaks: fitSettings.escapePeaks)
        let design = LinearDesign.build(model: lineModel, axis: axis, channels: fit.channels, background: fitSettings.background,
                                        shapes: fitSettings.referenceShapes, counts: counts)
        var plotModel = [Double](repeating: 0, count: axis.size), plotBackground = plotModel
        for (k, c) in fit.channels.enumerated() {
            plotModel[c] = fit.model[k]
            var b = 0.0
            for (col, coef) in zip(design.backgroundColumns, fit.backgroundCoefficients) { b += coef * col.values[k] }
            plotBackground[c] = b
        }

        // Rows: one per quantified element, on its K alpha group when it has one.
        let quantified = method.elements.filter { $0.role == .quantify }.map(\.symbol)
        var rows: [PooledQuantification.Row] = []
        var groupIndex: [Int?] = []
        for el in quantified {
            let ids = fit.groupIDs.indices.filter { fit.groupIDs[$0].hasPrefix(el + "_") }
            let gi = ids.first { fit.groupIDs[$0] == el + "_Ka" } ?? ids.first
            groupIndex.append(gi)
            guard let g = gi else {
                rows.append(emptyRow(el, "no line of \(el) lies in the fitted range (0.2 keV to the beam energy)"))
                continue
            }
            var row = emptyRow(el, nil)
            row.groupID = fit.groupIDs[g]
            row.supported = fit.supported[g]; row.atBound = fit.atBound[g]
            row.net = fit.values[g]; row.sigma = fit.sigma(at: g)
            if !fit.supported[g] { row.failure = "\(fit.groupIDs[g]) has no support in the fitted range" }
            rows.append(row)
        }

        // The k-free ratio: area / reference area (ADR 054 item 3: above at%, and independent of k). Reference: kReference, else Al when
        // it is quantified and measured, else the largest area.
        let valid = rows.indices.filter { rows[$0].failure == nil && rows[$0].net > 0 }
        var referenceIndex: Int?
        if let r = method.kReference, let i = rows.indices.first(where: { rows[$0].element == r && valid.contains($0) }) { referenceIndex = i }
        else if let al = rows.indices.first(where: { rows[$0].element == "Al" && valid.contains($0) }) { referenceIndex = al }
        else { referenceIndex = valid.max { rows[$0].net < rows[$1].net } }
        if let ri = referenceIndex, let gr = groupIndex[ri] {
            for i in rows.indices where rows[i].failure == nil {
                if i == ri { rows[i].isReference = true; rows[i].kFreeRatio = 1; continue }
                guard let g = groupIndex[i] else { continue }
                let ratio = rows[i].net / rows[ri].net
                rows[i].kFreeRatio = ratio
                if rows[i].net > 0 {
                    let rel = fit.ratioRelativeVariance(g, gr)
                    rows[i].kFreeSigma = rel.isFinite && rel >= 0 ? ratio * rel.squareRoot() : rows[i].sigma / rows[ri].net
                } else {
                    rows[i].kFreeSigma = rows[i].sigma / rows[ri].net
                }
            }
        }

        // at%: only with a k source.
        var kSet: KFactorSet?
        var abundanceRefusal: String?
        let absorptionPlan = absorptionPlan(method, input.metadata, tables)
        let absorption = absorptionPlan.status
        let referenceName = referenceIndex.map { rows[$0].element }
        do {
            try abundance(rows: &rows, groupIndex: groupIndex, fit: fit, quantified: quantified, method: &method,
                          plan: absorptionPlan, tables: tables, beam: beam, referenceElement: referenceName,
                          kSetOut: &kSet, warnings: &warnings)
        } catch let e as QuantificationRefusal {
            abundanceRefusal = e.reason
        } catch {
            abundanceRefusal = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }

        let isML = method.estimator == .poissonMaximumLikelihood
        let quality = isML ? fit.reducedDeviance : fit.pearsonReducedChiSquared
        let qualityLabel = isML ? "reduced deviance" : "\u{03C7}\u{00B2}\u{1D63} (Pearson)"

        var footer = ["\(fit.methodLabel) \u{00B7} \(fit.backgroundLabel) \u{00B7} \(fit.escapeLabel)"]
        if locked { footer.append("energy axis: the file's (locked)") }
        else if let r = refinement {
            footer.append(String(format: "energy axis: file %.3f keV + %.4f keV/ch \u{2192} refined %+.1f eV, gain %+.3f %%, FWHM(Mn K\u{03B1}) %.0f eV%@",
                                 r.fileOffset, r.fileScale, r.offsetShiftEV, r.gainShift * 100, r.resolutionMnKaEV,
                                 axis == r.refinedAxis ? "" : "; NOT used (residual not lower)"))
        }
        if let b = BeamEnergy.provenance(typedKeV: input.method.beamEnergyKeV, metadata: input.metadata) { footer.append(b) }
        footer.append("fit range 0.2 keV to \(String(format: "%g", min(axis.highValue, beam))) keV \u{00B7} \(input.pixelCount) px pooled (\(input.regionName))")
        if let k = kSet {
            footer.append("k: \(k.source) (\(k.date)); \(sigmaKDescription(k))")
            if let r = referenceName { footer.append("k-free ratio: net / net(\(r))") }
        } else if let why = abundanceRefusal {
            footer.append("at%: not computed \u{2014} \(why)")
        }
        switch absorption {
        case .off: footer.append("absorption correction: off")
        case .applied(let s): footer.append("absorption: \(s)")
        case .refused(let why): footer.append("absorption: not applied \u{2014} \(why)")
        }

        return PooledQuantification(
            method: method, rows: rows, referenceElement: referenceIndex.map { rows[$0].element }, fit: fit,
            fileAxis: input.axis, usedAxis: axis, axisLocked: locked, refinement: refinement,
            plotModel: plotModel, plotBackground: plotBackground, kSet: kSet, abundanceRefusal: abundanceRefusal,
            absorption: absorption, warnings: warnings, qualityLabel: qualityLabel, quality: quality, footerLines: footer)
    }

    /// The weak-line bias note applies when Al K-alpha is in the fit with a non-zero area AND a quantified Mg or Si K-alpha line
    /// (the neighbourhood the bias was measured in) is fitted: without Al there is no tail to bias the neighbour.
    package static func weakLineBiasApplies(groupIDs: [String], values: [Double], quantified: [String]) -> Bool {
        guard let al = groupIDs.firstIndex(of: "Al_Ka"), values[al] > 0 else { return false }
        return quantified.contains { ($0 == "Mg" || $0 == "Si") && groupIDs.contains($0 + "_Ka") }
    }

    /// The sigma_k sentence from the set itself: flat or per factor, and whether a reference carries 0.
    package static func sigmaKDescription(_ k: KFactorSet) -> String {
        let others = zip(k.elements, k.relativeSigma).filter { $0.0 != k.reference }
        let pct = { (v: Double) in String(format: "%.0f %%", v * 100) }
        let spread: String
        if let first = others.first?.1, others.allSatisfy({ $0.1 == first }) { spread = "\u{03C3}_k \(pct(first)) flat" }
        else { spread = "\u{03C3}_k " + others.map { "\($0.0) \(pct($0.1))" }.joined(separator: ", ") }
        return spread + (k.reference.map { ", 0 on the reference (\($0))" } ?? ", no reference (every factor independent)")
    }

    private static func emptyRow(_ el: String, _ failure: String?) -> PooledQuantification.Row {
        .init(element: el, groupID: "", net: 0, sigma: 0, supported: failure == nil, atBound: false, isReference: false,
              kFreeRatio: nil, kFreeSigma: nil, atomicPercent: nil, atomicSigma: nil, weightPercent: nil, weightSigma: nil,
              atomicTerms: nil, weightTerms: nil, absorptionSpreadAtomic: nil, absorptionSpreadWeight: nil, atomicTermsText: "", weightTermsText: "", failure: failure)
    }

    // MARK: Absorption preconditions

    private static func geometry(_ method: QuantificationMethod, _ meta: SpectrumImageMetadata) -> Result<FourDetectorGeometry, QuantificationRefusal> {
        if meta.origin == .gmsDM4 {
            return .failure(.init("GMS files: the stage tilt and the four detector segments are not read yet (open item), so the absorption geometry is unknown"))
        }
        let segs = meta.detectors.map {
            DetectorSegment(label: $0.name, azimuthDegrees: $0.azimuthDegrees, elevationDegrees: $0.elevationDegrees, solidAngleSr: $0.solidAngle)
        }
        do { return .success(try FourDetectorGeometry(segments: segs, tiltAlphaDegrees: meta.alphaTiltDegrees, tiltBetaDegrees: meta.betaTiltDegrees ?? 0)) }
        catch { return .failure(.init((error as? LocalizedError)?.errorDescription ?? "\(error)")) }
    }

    /// What the absorption correction will do for this method and file: the status for the footer and, when applied,
    /// the geometry and the thickness. Evaluated once, before the abundance, so a refused at% still names it.
    private struct AbsorptionPlan {
        var status: PooledQuantification.AbsorptionStatus
        var geometry: FourDetectorGeometry?
        var thickness: QuantificationMethod.Thickness?
    }

    private static func absorptionPlan(_ method: QuantificationMethod, _ meta: SpectrumImageMetadata,
                                       _ tables: QuantificationTables?) -> AbsorptionPlan {
        guard method.absorptionCorrection else { return AbsorptionPlan(status: .off) }
        let g: FourDetectorGeometry
        switch geometry(method, meta) {
        case .failure(let e): return AbsorptionPlan(status: .refused(e.reason))
        case .success(let ok): g = ok
        }
        guard let t = method.thickness, t.nanometres > 0, t.nanometres.isFinite, t.sigmaNanometres >= 0, t.sigmaNanometres.isFinite else {
            return AbsorptionPlan(status: .refused("no thickness is typed (nm): type one in the Quantify inspector"))
        }
        guard tables != nil else { return AbsorptionPlan(status: .refused("the mass-absorption table is not available")) }
        let toa = g.segments.map(\.takeOffDegrees)
        let s = String(format: "four-detector weighted transmission, %d segment%@ (take-off %.1f\u{2013}%.1f\u{00B0}), thickness %g \u{00B1} %g nm, badged",
                       g.segments.count, g.segments.count == 1 ? "" : "s", toa.min() ?? 0, toa.max() ?? 0, t.nanometres, t.sigmaNanometres)
        return AbsorptionPlan(status: .applied(s), geometry: g, thickness: t)
    }

    // MARK: at%

    private struct GeometricMeanGeometry: AbsorptionGeometry {
        let base: FourDetectorGeometry
        func meanTransmission(macM2PerKg: Double, massThickness: Double) -> Double {
            base.geometricMeanTransmission(macM2PerKg: macM2PerKg, massThickness: massThickness)
        }
        var segmentSummary: [(takeOffDegrees: Double, weight: Double)] { base.segmentSummary }
    }

    private static func abundance(
        rows: inout [PooledQuantification.Row], groupIndex: [Int?], fit: EDSFitResult, quantified: [String],
        method: inout QuantificationMethod, plan: AbsorptionPlan, tables: QuantificationTables?, beam: Double,
        referenceElement: String?, kSetOut: inout KFactorSet?, warnings: inout [String]
    ) throws {
        guard quantified.count >= 2 else { throw QuantificationRefusal("at% needs at least two quantified elements.") }
        if let bad = rows.first(where: { $0.failure != nil }) { throw QuantificationRefusal("\(bad.element): \(bad.failure!); every quantified element needs a fitted line.") }
        // Cliff-Lorimer is a K-line k here (the computed k covers K alpha only).
        let idsOK = rows.allSatisfy { $0.groupID == $0.element + "_Ka" }
        guard let ref = referenceElement ?? quantified.first else { throw QuantificationRefusal("No reference element.") }

        // 1. The k source.
        let kSet: KFactorSet
        switch method.kFactorSource {
        case .computed:
            guard let tables else { throw QuantificationRefusal("The computed-k data files are not available in this build.") }
            guard idsOK else {
                let bad = rows.first { $0.groupID != $0.element + "_Ka" }!
                throw QuantificationRefusal("The computed k covers K lines only; \(bad.element) has no fitted K\u{03B1} line (\(bad.groupID)). Type a k for it, or set it to Fit only.")
            }
            var lines: [LineIngredients] = []
            for r in rows {
                guard let e = XRayLines.line(r.groupID)?.energy,
                      let l = LineIngredients.kAlpha(element: r.element, energyKeV: e, weights: tables.weights) else {
                    throw QuantificationRefusal("No K line weights for \(r.element).")
                }
                lines.append(l)
            }
            let computer = ComputedKFactor(cross: tables.cross, yield: tables.krause, efficiency: SDDEfficiency(table: tables.mac), beamEnergyKeV: beam)
            let refIdx = lines.firstIndex { $0.element == ref } ?? 0
            let base = try computer.kFactorSet(lines: lines, reference: refIdx, date: QuantificationMethod.computedKTableIdentity)
            let sig = base.elements.map { $0 == base.reference ? 0 : method.sigmaK }
            guard let s = KFactorSet(kind: .computed, elements: base.elements, values: base.values, source: base.source, date: base.date,
                                     relativeSigma: sig, reference: base.reference) else {
                throw QuantificationRefusal("The computed k-factors could not form a set.")
            }
            kSet = s
            method.useComputedK(sourceDescription: computer.sourceDescription)
        case .typed:
            guard let s = method.typedKFactorSet() else {
                throw QuantificationRefusal("The typed k is incomplete: it needs a source, a date and a positive k for every quantified element.")
            }
            guard quantified.allSatisfy({ s.k($0) != nil }) else { throw QuantificationRefusal("The typed k lacks a value for a quantified element.") }
            kSet = s
        }
        kSetOut = kSet
        let q = rows.map(\.element)
        let kVals = q.map { kSet.k($0)! }
        let kSig = q.map { kSet.relSigma($0) ?? method.sigmaK }

        // 2. Absorption (decided by `absorptionPlan`).
        let geom = plan.geometry, thickness = plan.thickness
        let energies = rows.map { XRayLines.line($0.groupID)?.energy ?? 0 }

        func evaluate(_ I: [Double], _ k: [Double], t: Double?, geometry g: (any AbsorptionGeometry)?) throws -> (wt: [Double], at: [Double]) {
            let pos = I.map { max($0, 0) }
            let wt: [Double]
            if let g, let t, let tables {
                let setup = AbsorptionSetup(elements: q, lineEnergiesKeV: energies, geometry: g, table: tables.mac)
                let opts = AbsorptionIterationOptions(convergence: 1e-7, maxIterations: 200)
                wt = try AbsorptionCorrection.cliffLorimer(intensities: pos, kFactors: k, setup: setup, thicknessNm: t, options: opts).composition
            } else {
                wt = try CliffLorimer.weightFractions(intensities: pos, kFactors: k).map { $0 * 100 }
            }
            return (wt, try CompositionConversion.weightToAtomic(wt, elements: q))
        }

        let I0 = rows.map(\.net)
        let t0 = thickness?.nanometres
        let base: (wt: [Double], at: [Double])
        do { base = try evaluate(I0, kVals, t: t0, geometry: geom) }
        catch { throw QuantificationRefusal((error as? LocalizedError)?.errorDescription ?? "\(error)") }

        // 3. Terms. Covariance of the quantified areas (Poisson-only fallback when the fit's is not finite).
        let n = rows.count
        var cov = [Double](repeating: 0, count: n * n)
        var covOK = true
        for i in 0..<n { for j in 0..<n {
            let c = fit.covariance[groupIndex[i]! * fit.count + groupIndex[j]!]
            if !c.isFinite { covOK = false }
            cov[i * n + j] = c
        } }
        if !covOK {
            warnings.append("the fit covariance is not available; the counting term uses \u{221A}area only")
            cov = [Double](repeating: 0, count: n * n)
            for i in 0..<n { cov[i * n + i] = max(I0[i], 0) }
        }
        func f(_ I: [Double], _ k: [Double], t: Double? = t0, g: (any AbsorptionGeometry)? = geom) -> (wt: [Double], at: [Double])? {
            try? evaluate(I, k, t: t, geometry: g)
        }
        // counting: J C J^T by central differences on each area.
        var jAt = [[Double]](repeating: [Double](repeating: 0, count: n), count: n)   // [output i][input j]
        var jWt = jAt
        for j in 0..<n {
            let h = max(0.01 * max(I0[j], 1), 1e-9)
            var lo = I0, hi = I0
            lo[j] = max(I0[j] - h, 0); hi[j] = I0[j] + h
            guard let a = f(hi, kVals), let b = f(lo, kVals), hi[j] > lo[j] else { continue }
            for i in 0..<n {
                jAt[i][j] = (a.at[i] - b.at[i]) / (hi[j] - lo[j])
                jWt[i][j] = (a.wt[i] - b.wt[i]) / (hi[j] - lo[j])
            }
        }
        func quad(_ J: [Double]) -> Double {
            var s = 0.0
            for a in 0..<n { for b in 0..<n { s += J[a] * cov[a * n + b] * J[b] } }
            return max(s, 0).squareRoot()
        }
        // k: each non-reference k moved by its sigma, in quadrature.
        var kAt = [Double](repeating: 0, count: n), kWt = kAt
        for j in 0..<n where kSig[j] > 0 {
            var up = kVals, dn = kVals
            up[j] *= 1 + kSig[j]; dn[j] *= max(1 - kSig[j], 1e-6)
            guard let a = f(I0, up), let b = f(I0, dn) else { continue }
            for i in 0..<n {
                kAt[i] += pow((a.at[i] - b.at[i]) / 2, 2)
                kWt[i] += pow((a.wt[i] - b.wt[i]) / 2, 2)
            }
        }
        // absorption (weighted vs geometric mean) and thickness.
        var absAt = [Double](repeating: 0, count: n), absWt = absAt
        var thAt = absAt, thWt = absAt
        if let g = geom, let t = thickness {
            if let gm = f(I0, kVals, g: GeometricMeanGeometry(base: g)) {
                for i in 0..<n { absAt[i] = abs(gm.at[i] - base.at[i]); absWt[i] = abs(gm.wt[i] - base.wt[i]) }
            }
            for i in 0..<n {
                thAt[i] = (try? ThicknessPropagation.sigma(at: t.nanometres, sigmaNm: t.sigmaNanometres) { tt in try evaluate(I0, kVals, t: tt, geometry: g).at[i] }) ?? 0
                thWt[i] = (try? ThicknessPropagation.sigma(at: t.nanometres, sigmaNm: t.sigmaNanometres) { tt in try evaluate(I0, kVals, t: tt, geometry: g).wt[i] }) ?? 0
            }
        }
        let absorbed = geom != nil
        let thicknessSigmaTyped = (thickness?.sigmaNanometres ?? 0) > 0
        func text(_ terms: SigmaTerms, _ total: Double, _ unit: String, spread: Double?) -> String {
            var parts = ["counting \(pct(terms[.counting]))", "k \(pct(terms[.k]))"]
            if absorbed { parts.append(thicknessSigmaTyped ? "thickness \(pct(terms[.thickness]))" : "thickness \u{03C3} not typed") }
            var t = parts.joined(separator: " \u{2295} ") + " = \(pct(terms.combined)) \u{2192} \u{00B1}\(String(format: "%.2g", total)) \(unit)"
            if absorbed, let spread { t += " \u{00B7} absorption model spread (AM vs GM) \(pct(spread)), not in the total" }
            else { t += " \u{00B7} absorption not applied" }
            return t
        }
        for i in 0..<n {
            let a = base.at[i], w = base.wt[i]
            func rel(_ x: Double, _ v: Double) -> Double { v > 0 ? x / v : 0 }
            let aCount = quad(jAt[i]), wCount = quad(jWt[i])
            let aTerms = SigmaTerms(counting: rel(aCount, a), k: rel(kAt[i].squareRoot(), a), absorption: 0, thickness: rel(thAt[i], a))
            let wTerms = SigmaTerms(counting: rel(wCount, w), k: rel(kWt[i].squareRoot(), w), absorption: 0, thickness: rel(thWt[i], w))
            let aSig = aTerms.combined * a, wSig = wTerms.combined * w
            rows[i].atomicPercent = a; rows[i].atomicSigma = aSig; rows[i].atomicTerms = aTerms
            rows[i].weightPercent = w; rows[i].weightSigma = wSig; rows[i].weightTerms = wTerms
            if absorbed { rows[i].absorptionSpreadAtomic = rel(absAt[i], a); rows[i].absorptionSpreadWeight = rel(absWt[i], w) }
            rows[i].atomicTermsText = text(aTerms, aSig, "at%", spread: rows[i].absorptionSpreadAtomic)
            rows[i].weightTermsText = text(wTerms, wSig, "wt%", spread: rows[i].absorptionSpreadWeight)
        }
    }

    private static func pct(_ v: Double) -> String { String(format: "%.1f %%", v * 100) }
}
