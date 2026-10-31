//
//  ProposerPolicy.swift
//  Role: The choices behind the element proposer and the unlisted-line check, as values with the library's choice as the
//        default (0.5.0).
//

import Foundation
import SpectroCore

/// The identification loop's thresholds (docs/design/auto-id-tem.md): the defaults of the published method (the Newbury-Ritchie loop as
/// AutoEMX documents it), read for the method only. A changed default is a stated departure in `docs/parity.md`.
public nonisolated struct IdentificationThresholds: Sendable, Equatable, Codable {
    /// A residual peak needs this many standard deviations of the top-hat filtered residual. Default 5.
    public var peakSigma: Double
    /// Below `lowEnergyBelowKeV` the peak bar is this many times higher (edges and chemical effects leave structure there). Default 1.5.
    public var lowEnergyFactor: Double
    /// Default 1 keV.
    public var lowEnergyBelowKeV: Double
    /// A candidate element has a line within this many Gaussian sigma of the peak, plus `candidateWindowKeV`. Default 2.5.
    public var candidateWindowSigma: Double
    /// Default 0.025 keV.
    public var candidateWindowKeV: Double
    /// Only lines of at least this weight within their family nominate a candidate. Default 0.1.
    public var minimumLineWeight: Double
    /// The confirmation line (K for an L pick, L for an M pick, where the range holds it and the beam excites it) must show this many sigma
    /// in the filtered residual. Default 3.
    public var confirmationSigma: Double
    /// A candidate joins when the statistic falls by at least this much. Default 100.
    public var minimumGain: Double
    /// ... and at least this share of the fall comes from channels near its own lines. Default 0.2.
    public var minimumLocalShare: Double
    /// A candidate's line window that worsens by this much ... Default 9.
    public var contradictionGain: Double
    /// ... and by more than this share of the total gain contradicts the candidate. Default 0.05.
    public var contradictionShare: Double
    /// Candidates whose gain is within this of the best explain the peak equally well (ambiguous). Default 30.
    public var ambiguityGain: Double
    /// A found element is pruned when leaving it out of the final fit costs less than this. Default 100.
    public var pruneGain: Double
    /// Si is a detector artefact unless its K alpha holds at least this fraction of the counts in range. Default 0.002.
    public var siliconArtefactFraction: Double
    /// At most this many residual peaks are examined. Default 30.
    public var maximumPeaks: Int
    /// At most this many elements are added. Default 10.
    public var maximumNewElements: Int
    /// The relative model term of the statistic: sum (y - mu)^2 / (mu + (r mu)^2). Default 0.01.
    public var relativeModelTerm: Double

    public init(peakSigma: Double = 5, lowEnergyFactor: Double = 1.5, lowEnergyBelowKeV: Double = 1, candidateWindowSigma: Double = 2.5,
                candidateWindowKeV: Double = 0.025, minimumLineWeight: Double = 0.1, confirmationSigma: Double = 3, minimumGain: Double = 100,
                minimumLocalShare: Double = 0.2, contradictionGain: Double = 9, contradictionShare: Double = 0.05, ambiguityGain: Double = 30,
                pruneGain: Double = 100, siliconArtefactFraction: Double = 0.002, maximumPeaks: Int = 30, maximumNewElements: Int = 10,
                relativeModelTerm: Double = 0.01) {
        self.peakSigma = peakSigma; self.lowEnergyFactor = lowEnergyFactor; self.lowEnergyBelowKeV = lowEnergyBelowKeV
        self.candidateWindowSigma = candidateWindowSigma; self.candidateWindowKeV = candidateWindowKeV; self.minimumLineWeight = minimumLineWeight
        self.confirmationSigma = confirmationSigma; self.minimumGain = minimumGain; self.minimumLocalShare = minimumLocalShare
        self.contradictionGain = contradictionGain; self.contradictionShare = contradictionShare; self.ambiguityGain = ambiguityGain
        self.pruneGain = pruneGain; self.siliconArtefactFraction = siliconArtefactFraction; self.maximumPeaks = maximumPeaks
        self.maximumNewElements = maximumNewElements; self.relativeModelTerm = relativeModelTerm
    }

    public static let `default` = IdentificationThresholds()

    private enum CodingKeys: String, CodingKey {
        case peakSigma, lowEnergyFactor, lowEnergyBelowKeV, candidateWindowSigma, candidateWindowKeV, minimumLineWeight, confirmationSigma, minimumGain,
             minimumLocalShare, contradictionGain, contradictionShare, ambiguityGain, pruneGain, siliconArtefactFraction, maximumPeaks,
             maximumNewElements, relativeModelTerm
    }

    /// A stored value missing a field (written before the field existed) reads that field's default.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self), d = IdentificationThresholds.default
        self.init(peakSigma: try c.decodeIfPresent(Double.self, forKey: .peakSigma) ?? d.peakSigma,
                  lowEnergyFactor: try c.decodeIfPresent(Double.self, forKey: .lowEnergyFactor) ?? d.lowEnergyFactor,
                  lowEnergyBelowKeV: try c.decodeIfPresent(Double.self, forKey: .lowEnergyBelowKeV) ?? d.lowEnergyBelowKeV,
                  candidateWindowSigma: try c.decodeIfPresent(Double.self, forKey: .candidateWindowSigma) ?? d.candidateWindowSigma,
                  candidateWindowKeV: try c.decodeIfPresent(Double.self, forKey: .candidateWindowKeV) ?? d.candidateWindowKeV,
                  minimumLineWeight: try c.decodeIfPresent(Double.self, forKey: .minimumLineWeight) ?? d.minimumLineWeight,
                  confirmationSigma: try c.decodeIfPresent(Double.self, forKey: .confirmationSigma) ?? d.confirmationSigma,
                  minimumGain: try c.decodeIfPresent(Double.self, forKey: .minimumGain) ?? d.minimumGain,
                  minimumLocalShare: try c.decodeIfPresent(Double.self, forKey: .minimumLocalShare) ?? d.minimumLocalShare,
                  contradictionGain: try c.decodeIfPresent(Double.self, forKey: .contradictionGain) ?? d.contradictionGain,
                  contradictionShare: try c.decodeIfPresent(Double.self, forKey: .contradictionShare) ?? d.contradictionShare,
                  ambiguityGain: try c.decodeIfPresent(Double.self, forKey: .ambiguityGain) ?? d.ambiguityGain,
                  pruneGain: try c.decodeIfPresent(Double.self, forKey: .pruneGain) ?? d.pruneGain,
                  siliconArtefactFraction: try c.decodeIfPresent(Double.self, forKey: .siliconArtefactFraction) ?? d.siliconArtefactFraction,
                  maximumPeaks: try c.decodeIfPresent(Int.self, forKey: .maximumPeaks) ?? d.maximumPeaks,
                  maximumNewElements: try c.decodeIfPresent(Int.self, forKey: .maximumNewElements) ?? d.maximumNewElements,
                  relativeModelTerm: try c.decodeIfPresent(Double.self, forKey: .relativeModelTerm) ?? d.relativeModelTerm)
    }
}

/// Which elements the proposer treats as special because of how a sample is prepared and held. Defaults are the library's choice.
public nonisolated struct ElementContext: Sendable, Equatable, Codable {
    /// Elements the proposer suggests quantifying rather than fitting only. Default Cu.
    public var quantifyByDefault: Set<String>
    /// Elements that can come from the sample holder or grid: a candidate gets a named conflict, and, when a spectrum of a hole region
    /// is given, a note on what that region says. Default Cu.
    public var gridElements: Set<String>
    /// Elements that can be implanted by ion milling: a candidate gets a named conflict. Default Ga.
    public var implantedElements: Set<String>

    public init(quantifyByDefault: Set<String> = ["Cu"], gridElements: Set<String> = ["Cu"], implantedElements: Set<String> = ["Ga"]) {
        self.quantifyByDefault = quantifyByDefault; self.gridElements = gridElements; self.implantedElements = implantedElements
    }

    public static let `default` = ElementContext()
}

/// The element proposer's choices. `ElementProposer(policy:)` runs with them.
public nonisolated struct ProposerPolicy: Sendable, Equatable {
    /// Currie's false-positive and false-negative rates. Default 0.05 each, a convention reported with every result.
    public var currie: Currie
    /// The elements tested; nil is every element of the line table except the refused and `excluded`.
    public var pool: [String]?
    /// Elements left out of the default pool: radioactive or absent from the table, and the noble gases other than Ar.
    public var excluded: Set<String>
    /// A candidate group is tested only if its alpha line is at or above this energy, keV. Default 0.45, measured on one synthetic
    /// generator (carbon, nitrogen, calcium and scandium were false there at 0.28-0.40 keV).
    public var minimumLineEnergyKeV: Double
    /// The identification loop's bars. Default `IdentificationThresholds.default`, the published method's.
    public var thresholds: IdentificationThresholds
    /// A candidate's alpha line must lie this many FWHM inside the fitted range at each end, so its column has support. Default 0.5.
    public var rangeMarginFWHM: Double
    /// A candidate's alpha line counts as on a pile-up peak's energy within this many keV. Default 0.06, about half the Mn K alpha
    /// width of one detector.
    public var sumPeakToleranceKeV: Double
    /// Which elements get the grid, implantation and quantify-by-default treatment. Default `ElementContext.default` (Cu, Cu, Ga:
    /// the elements of the sample preparation the library was first used with).
    public var context: ElementContext
    /// R4, the confirmation-line rule: withhold an element proposed by an L or M line whose K (or L) alpha line reads below its own L_D where the
    /// fitted range holds it. Default true. False skips the check and reproduces the run without it.
    public var familyConsistency: Bool
    /// The beam energy must be at least this many times the companion line's energy for R4 to demand it (the edge proxy; NIST EPQ's rule takes the
    /// first family whose edge is below half the beam energy). Default 2.
    public var familyOvervoltage: Double
    /// A candidate on a pile-up energy is a sum-peak question only when its net is at most this fraction of the smaller parent's net. Default 1: a pile-up
    /// peak can never exceed its smaller parent (the chance of a second photon within the shaping time is at most 1); a smaller value would be a measured
    /// dead-time fraction of one detector.
    public var sumPeakFraction: Double
    /// The downward confirmation rule: an element of at least this atomic number nominated by a K line must show its L alpha line at
    /// `IdentificationThresholds.confirmationSigma` in the residual where the fitted range holds it, or it is withheld (`familyNote`); acts only with
    /// `familyConsistency`. Default nil (off): the rule has not been run on measured spectra, so a consumer switches it on (30, from Zn, is the
    /// intended value: the L lines of lighter elements sit below 1 keV where the continuum model is weakest). Known limit, as for the upward rule:
    /// the check reads the residual without the element, so an L line that an element found earlier already explains (Zn Lα beside Na Kα, As Lα
    /// beside Mg Kα, Br Lα under Al Kα) reads as missing and the K pick is withheld.
    public var downwardFamilyMinimumZ: Int?

    public init(currie: Currie = .standard, pool: [String]? = nil, excluded: Set<String> = ElementProposer.defaultExcluded,
                minimumLineEnergyKeV: Double = 0.45, thresholds: IdentificationThresholds = .default, rangeMarginFWHM: Double = 0.5,
                sumPeakToleranceKeV: Double = ProposerPolicy.defaultSumPeakToleranceKeV, context: ElementContext = .default,
                familyConsistency: Bool = true, familyOvervoltage: Double = 2, sumPeakFraction: Double = 1, downwardFamilyMinimumZ: Int? = nil) {
        self.currie = currie; self.pool = pool; self.excluded = excluded
        self.minimumLineEnergyKeV = minimumLineEnergyKeV; self.thresholds = thresholds; self.rangeMarginFWHM = rangeMarginFWHM
        self.sumPeakToleranceKeV = sumPeakToleranceKeV; self.context = context
        self.familyConsistency = familyConsistency; self.familyOvervoltage = familyOvervoltage
        self.sumPeakFraction = sumPeakFraction; self.downwardFamilyMinimumZ = downwardFamilyMinimumZ
    }

    /// 0.06 keV: about half the Mn K alpha width of one detector.
    public static let defaultSumPeakToleranceKeV = 0.06

    public static let `default` = ProposerPolicy()

    /// The note for a non-default policy: every field that differs from the default, `path = value`, in declaration order
    /// (`currie` as `alpha 0.005 beta 0.2`, sets sorted, arrays as `[Al, Si]`). nil for the default. `ElementProposer` adds it
    /// to the notes of every proposal it makes, so a result never travels without the choices that made it.
    public var noteLine: String? {
        var d: [String] = []
        func add(_ name: String, _ mine: String, _ base: String) { if mine != base { d.append("\(name) = \(mine)") } }
        func list(_ a: [String]?) -> String { a.map { "[" + $0.joined(separator: ", ") + "]" } ?? "nil" }
        let b = ProposerPolicy.default
        add("currie", "alpha \(currie.alpha) beta \(currie.beta)", "alpha \(b.currie.alpha) beta \(b.currie.beta)")
        add("pool", list(pool), list(b.pool))
        add("excluded", list(excluded.sorted()), list(b.excluded.sorted()))
        add("minimumLineEnergyKeV", "\(minimumLineEnergyKeV)", "\(b.minimumLineEnergyKeV)")
        let t = thresholds, bt = b.thresholds
        for (name, mine, base) in [("peakSigma", t.peakSigma, bt.peakSigma), ("lowEnergyFactor", t.lowEnergyFactor, bt.lowEnergyFactor),
                                   ("lowEnergyBelowKeV", t.lowEnergyBelowKeV, bt.lowEnergyBelowKeV),
                                   ("candidateWindowSigma", t.candidateWindowSigma, bt.candidateWindowSigma),
                                   ("candidateWindowKeV", t.candidateWindowKeV, bt.candidateWindowKeV),
                                   ("minimumLineWeight", t.minimumLineWeight, bt.minimumLineWeight),
                                   ("confirmationSigma", t.confirmationSigma, bt.confirmationSigma), ("minimumGain", t.minimumGain, bt.minimumGain),
                                   ("minimumLocalShare", t.minimumLocalShare, bt.minimumLocalShare),
                                   ("contradictionGain", t.contradictionGain, bt.contradictionGain),
                                   ("contradictionShare", t.contradictionShare, bt.contradictionShare),
                                   ("ambiguityGain", t.ambiguityGain, bt.ambiguityGain), ("pruneGain", t.pruneGain, bt.pruneGain),
                                   ("siliconArtefactFraction", t.siliconArtefactFraction, bt.siliconArtefactFraction),
                                   ("maximumPeaks", Double(t.maximumPeaks), Double(bt.maximumPeaks)),
                                   ("maximumNewElements", Double(t.maximumNewElements), Double(bt.maximumNewElements)),
                                   ("relativeModelTerm", t.relativeModelTerm, bt.relativeModelTerm)] {
            add("thresholds.\(name)", "\(mine)", "\(base)")
        }
        add("rangeMarginFWHM", "\(rangeMarginFWHM)", "\(b.rangeMarginFWHM)")
        add("sumPeakToleranceKeV", "\(sumPeakToleranceKeV)", "\(b.sumPeakToleranceKeV)")
        add("context.quantifyByDefault", list(context.quantifyByDefault.sorted()), list(b.context.quantifyByDefault.sorted()))
        add("context.gridElements", list(context.gridElements.sorted()), list(b.context.gridElements.sorted()))
        add("context.implantedElements", list(context.implantedElements.sorted()), list(b.context.implantedElements.sorted()))
        add("familyConsistency", "\(familyConsistency)", "\(b.familyConsistency)")
        add("familyOvervoltage", "\(familyOvervoltage)", "\(b.familyOvervoltage)")
        add("sumPeakFraction", "\(sumPeakFraction)", "\(b.sumPeakFraction)")
        add("downwardFamilyMinimumZ", downwardFamilyMinimumZ.map { "\($0)" } ?? "nil", b.downwardFamilyMinimumZ.map { "\($0)" } ?? "nil")
        return d.isEmpty ? nil : "policy (non-default): " + d.joined(separator: ", ")
    }
}

/// The unlisted-line check's geometry and bar. `UnlistedLineCheck` does not store the rules it ran with (its stored fields are the
/// result a reader walks), so a caller that runs `UnlistedLineChecker.check(..., rules:)` with a non-default value records it
/// with the result itself, for example by printing `String(describing:)` of this value beside the check's `line`.
public nonisolated struct UnlistedLineRules: Sendable, Equatable, Codable {
    /// A candidate within this many FWHM (at its own energy) of a listed group's alpha line is an unexplained excess beside that
    /// line, not an element. Default 2, a geometry convention rather than a measured bar.
    public var besideLineFWHM: Double
    /// Likewise for a continuum split edge. Default 1.
    public var besideEdgeFWHM: Double
    /// A quantified net has moved when fitting the candidates changes it by more than this many of its reported sigma. Default 1.
    public var moveSigmaFactor: Double

    public init(besideLineFWHM: Double = 2, besideEdgeFWHM: Double = 1, moveSigmaFactor: Double = 1) {
        self.besideLineFWHM = besideLineFWHM; self.besideEdgeFWHM = besideEdgeFWHM; self.moveSigmaFactor = moveSigmaFactor
    }

    public static let `default` = UnlistedLineRules()
}
