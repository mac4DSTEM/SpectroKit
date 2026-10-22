//
//  ProposerPolicy.swift
//  Role: The choices behind the element proposer and the unlisted-line check, as values with the library's choice as the
//        default. Registered: docs/generality-0.5.0-registration.md (E1-E11, U1-U3).
//

import Foundation
import SpectroCore

/// How the proposer measures the misfit of the fit's smooth parts around a candidate line, which scales its null standard deviation
/// (and so L_C and L_D) up where the continuum does not follow the data. The residual is summed in bins on both flanks of the line,
/// the line itself left out; each bin gives Z = sum(residual) / sqrt(sum(max(model, 1))), N(0, 1) when the model is right, and the
/// factor is `sqrt(max(1, mean Z^2))`.
public nonisolated struct FlankMisfitGeometry: Sendable, Equatable, Codable {
    /// Distance from the line to the nearest edge of the first bin, in FWHM. Default 1.5.
    public var innerFWHM: Double
    /// Width of one bin, in FWHM. Default 1.
    public var binWidthFWHM: Double
    /// Bins on each side. Default 5 (so the flanks reach 6.5 FWHM).
    public var binsPerSide: Int
    /// A bin with fewer channels than this is left out. Default 3. At 40 on a summed spectrum of 4096 channels the
    /// proposer throws `ProposerError.rankDeficient` (measured by the Gate B refuter); a larger value needs wider bins.
    public var minimumChannelsPerBin: Int
    /// With fewer bins than this the factor is 1 (nothing to judge by). Default 3. At 11 on a 4096-channel summed spectrum the
    /// proposer throws `ProposerError.rankDeficient`.
    public var minimumBins: Int

    public init(innerFWHM: Double = 1.5, binWidthFWHM: Double = 1, binsPerSide: Int = 5, minimumChannelsPerBin: Int = 3, minimumBins: Int = 3) {
        self.innerFWHM = innerFWHM; self.binWidthFWHM = binWidthFWHM; self.binsPerSide = binsPerSide
        self.minimumChannelsPerBin = minimumChannelsPerBin; self.minimumBins = minimumBins
    }

    public static let `default` = FlankMisfitGeometry()
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
    /// The backward step stops after this many passes. Default 5.
    public var maxPasses: Int
    /// The forward step stops after this many rounds. Default 24.
    public var maxForwardRounds: Int
    /// A candidate group is tested only if its alpha line is at or above this energy, keV. Default 0.45, measured on one synthetic
    /// generator (carbon, nitrogen, calcium and scandium were false there at 0.28-0.40 keV).
    public var minimumLineEnergyKeV: Double
    /// Scale each candidate's null standard deviation by the flank-misfit factor. Default true (the library's choice). False makes
    /// every misfit exactly 1 and, on a 4096-channel summed spectrum, the proposer throws `ProposerError.rankDeficient`.
    public var flankScaling: Bool
    /// How the flank misfit is measured. Default `FlankMisfitGeometry.default` (flanks 1.5-6.5 FWHM from the line, 5 bins a side of
    /// 1 FWHM, at least 3 channels a bin and 3 bins; the library's choice).
    public var flank: FlankMisfitGeometry
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

    public init(currie: Currie = .standard, pool: [String]? = nil, excluded: Set<String> = ElementProposer.defaultExcluded,
                maxPasses: Int = 5, maxForwardRounds: Int = 24, minimumLineEnergyKeV: Double = 0.45, flankScaling: Bool = true,
                flank: FlankMisfitGeometry = .default, rangeMarginFWHM: Double = 0.5,
                sumPeakToleranceKeV: Double = ProposerPolicy.defaultSumPeakToleranceKeV, context: ElementContext = .default,
                familyConsistency: Bool = true, familyOvervoltage: Double = 2, sumPeakFraction: Double = 1) {
        self.currie = currie; self.pool = pool; self.excluded = excluded; self.maxPasses = maxPasses
        self.maxForwardRounds = maxForwardRounds; self.minimumLineEnergyKeV = minimumLineEnergyKeV
        self.flankScaling = flankScaling; self.flank = flank; self.rangeMarginFWHM = rangeMarginFWHM
        self.sumPeakToleranceKeV = sumPeakToleranceKeV; self.context = context
        self.familyConsistency = familyConsistency; self.familyOvervoltage = familyOvervoltage
        self.sumPeakFraction = sumPeakFraction
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
        add("maxPasses", "\(maxPasses)", "\(b.maxPasses)")
        add("maxForwardRounds", "\(maxForwardRounds)", "\(b.maxForwardRounds)")
        add("minimumLineEnergyKeV", "\(minimumLineEnergyKeV)", "\(b.minimumLineEnergyKeV)")
        add("flankScaling", "\(flankScaling)", "\(b.flankScaling)")
        add("flank.innerFWHM", "\(flank.innerFWHM)", "\(b.flank.innerFWHM)")
        add("flank.binWidthFWHM", "\(flank.binWidthFWHM)", "\(b.flank.binWidthFWHM)")
        add("flank.binsPerSide", "\(flank.binsPerSide)", "\(b.flank.binsPerSide)")
        add("flank.minimumChannelsPerBin", "\(flank.minimumChannelsPerBin)", "\(b.flank.minimumChannelsPerBin)")
        add("flank.minimumBins", "\(flank.minimumBins)", "\(b.flank.minimumBins)")
        add("rangeMarginFWHM", "\(rangeMarginFWHM)", "\(b.rangeMarginFWHM)")
        add("sumPeakToleranceKeV", "\(sumPeakToleranceKeV)", "\(b.sumPeakToleranceKeV)")
        add("context.quantifyByDefault", list(context.quantifyByDefault.sorted()), list(b.context.quantifyByDefault.sorted()))
        add("context.gridElements", list(context.gridElements.sorted()), list(b.context.gridElements.sorted()))
        add("context.implantedElements", list(context.implantedElements.sorted()), list(b.context.implantedElements.sorted()))
        add("familyConsistency", "\(familyConsistency)", "\(b.familyConsistency)")
        add("familyOvervoltage", "\(familyOvervoltage)", "\(b.familyOvervoltage)")
        add("sumPeakFraction", "\(sumPeakFraction)", "\(b.sumPeakFraction)")
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
