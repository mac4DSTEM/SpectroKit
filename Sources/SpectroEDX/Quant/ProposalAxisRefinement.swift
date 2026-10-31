//
//  ProposalAxisRefinement.swift
//  Role: The proposer's own energy-axis refinement with a two-line guard: propose on the file's axis, refine the axis on the
//        proposal's K picks with the pooled quantifier (as Quantify refines it), propose again on the refined axis. The flow
//        the apps ran before 0.14, moved here unchanged so both apps share one copy. It lives beside the pooled quantifier, not in
//        Proposer/: it builds a quantification method of its own for the refinement fit (the Proposer folder never writes an element
//        list); the caller's `listed` is never changed.
//

import Foundation
import SpectroCore

/// A proposal made on the energy axis refined on its own K picks (`ElementProposer.proposeOnRefinedAxis`).
public nonisolated struct AxisRefinedProposal: Sendable {
    /// The last proposal: on the refined axis when a refinement was accepted, else on the file's axis.
    public let result: ProposalResult
    /// The fit settings and the axis `result` ran with (a consumer reads the result against these).
    public let settings: FitSettings
    public let axis: EnergyAxis
    /// The accepted refinement; nil when the guard found no anchors, no metadata was given, or the quantifier kept the file's axis.
    public let refinement: AxisRefinementResult?
    /// The K picks the accepted refinement was fitted on; empty when there is none.
    public let anchors: [String]
    /// One sentence for the consumer's notes: what was refined, on which lines, by how much. nil without a refinement.
    public var note: String? {
        guard let r = refinement else { return nil }
        return String(format: "Energy axis refined on %@ before the proposal: offset %+.1f eV, gain %+.3f %%, FWHM(Mn K\u{03B1}) %.0f eV (file %.0f eV).",
                      anchors.joined(separator: ", "), r.offsetShiftEV, r.gainShift * 100, r.resolutionMnKaEV, fileResolutionMnKaEV)
    }
    /// The detector width the first proposal and the refinement started from, eV.
    public let fileResolutionMnKaEV: Double

    public init(result: ProposalResult, settings: FitSettings, axis: EnergyAxis, refinement: AxisRefinementResult?, anchors: [String],
                fileResolutionMnKaEV: Double) {
        self.result = result; self.settings = settings; self.axis = axis; self.refinement = refinement; self.anchors = anchors
        self.fileResolutionMnKaEV = fileResolutionMnKaEV
    }
}

extension ElementProposer {
    /// The two-line guard: the proposed K picks at or above `minimumSignificance` x L_D anchor a refinement only when there are at least
    /// two and they span at least `minimumSpanKeV` (one line cannot tell an offset from a gain; a refinement on Cu alone drifted by 46 eV on
    /// a measured file). nil: no refinement. Defaults 3 and 3 keV, the values the apps used.
    public static func refinementAnchors(_ result: ProposalResult, minimumSignificance: Double = 3, minimumSpanKeV: Double = 3) -> [String]? {
        let k = result.proposed.filter { XRayLines.line($0.group)?.family == .K && $0.significance >= minimumSignificance }
        guard k.count >= 2, let lo = k.map(\.energyKeV).min(), let hi = k.map(\.energyKeV).max(), hi - lo >= minimumSpanKeV else { return nil }
        return k.map(\.element)
    }

    /// Propose on the file's axis; when `refinementAnchors` holds and `metadata` is given, fit the listed elements and the anchors once with
    /// `PooledQuantifier` (the default method with the axis unlocked, so it refines offset, gain and detector width as Quantify does) and
    /// propose again on the refined axis. At most `rounds` refinements (default 2: the second proposal often adds a K line the first could
    /// not see at the file's width, and the refinement on the larger anchor set is the one Quantify would make); a round stops when the
    /// anchors repeat, the quantifier fails, or it keeps the file's axis. Every refinement starts from the file's axis.
    /// - Parameters:
    ///   - spectrum: the pooled counts, one per channel of `axis`.
    ///   - listed: the current set (always fitted, never changed), as in `propose`.
    ///   - resolutionMnKaEV: the file's detector width; the refined width replaces it after a refinement. Default 130 eV.
    ///   - tables: the quantifier's tables (`QuantificationTables.bundled()`); nil runs it without them, as `PooledQuantifier.run` does.
    public func proposeOnRefinedAxis(spectrum: [UInt64], axis fileAxis: EnergyAxis, beamEnergy: Double, listed: [String],
                                     metadata: SpectrumImageMetadata?, regionName: String, tables: QuantificationTables?,
                                     resolutionMnKaEV: Double = ElementWindows.defaultResolutionMnKaEV, rounds: Int = 2,
                                     cancelled: @Sendable () -> Bool = SpectroCancellation.task) throws -> AxisRefinedProposal {
        let counts = spectrum.map { Double($0) }
        var axis = fileAxis
        var settings = FitSettings.standard(elements: listed, axis: axis, resolutionMnKaEV: resolutionMnKaEV, beamEnergy: beamEnergy)
        var result = try propose(counts: counts, axis: axis, settings: settings, cancelled: cancelled)
        var refinement: AxisRefinementResult?
        var anchorsUsed: [String] = []
        for _ in 0..<max(rounds, 0) {
            guard let metadata, let anchors = Self.refinementAnchors(result), anchors != anchorsUsed else { break }
            var m = QuantificationMethod()
            m.elements = (listed + anchors.filter { !listed.contains($0) }).map { QuantificationMethod.ElementState(symbol: $0, role: .quantify, isManual: false) }
            m.beamEnergyKeV = beamEnergy
            let input = PooledQuantificationInput(counts: spectrum, axis: fileAxis, method: m, metadata: metadata, regionName: regionName, pixelCount: 1,
                                                  resolutionMnKaEV: resolutionMnKaEV,
                                                  sumEscape: SumEscapeModel())   // only the refinement is read: no sum-peak fits
                                                                                 // (the refinement itself runs without them)
            let fit: PooledQuantification
            do { fit = try PooledQuantifier.run(input, tables: tables, cancelled: cancelled) }
            catch let c as SpectroCancelled { throw c }
            catch { break }
            guard let r = fit.refinement, fit.usedAxis == r.refinedAxis else { break }
            anchorsUsed = anchors
            refinement = r
            axis = r.refinedAxis
            settings = FitSettings.standard(elements: listed, axis: axis, resolutionMnKaEV: r.resolutionMnKaEV, beamEnergy: beamEnergy)
            result = try propose(counts: counts, axis: axis, settings: settings, cancelled: cancelled)
        }
        return AxisRefinedProposal(result: result, settings: settings, axis: axis, refinement: refinement, anchors: anchorsUsed,
                                   fileResolutionMnKaEV: resolutionMnKaEV)
    }
}
