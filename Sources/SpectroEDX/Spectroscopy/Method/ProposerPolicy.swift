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
    /// A bin with fewer channels than this is left out. Default 3.
    public var minimumChannelsPerBin: Int
    /// With fewer bins than this the factor is 1 (nothing to judge by). Default 3.
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
    /// Scale each candidate's null standard deviation by the flank-misfit factor. Default true.
    public var flankScaling: Bool
    public var flank: FlankMisfitGeometry
    /// A candidate's alpha line must lie this many FWHM inside the fitted range at each end, so its column has support. Default 0.5.
    public var rangeMarginFWHM: Double
    /// A candidate's alpha line counts as on a pile-up peak's energy within this many keV. Default 0.06, about half the Mn K alpha
    /// width of one detector.
    public var sumPeakToleranceKeV: Double
    public var context: ElementContext

    public init(currie: Currie = .standard, pool: [String]? = nil, excluded: Set<String> = ElementProposer.defaultExcluded,
                maxPasses: Int = 5, maxForwardRounds: Int = 24, minimumLineEnergyKeV: Double = 0.45, flankScaling: Bool = true,
                flank: FlankMisfitGeometry = .default, rangeMarginFWHM: Double = 0.5,
                sumPeakToleranceKeV: Double = ProposerPolicy.defaultSumPeakToleranceKeV, context: ElementContext = .default) {
        self.currie = currie; self.pool = pool; self.excluded = excluded; self.maxPasses = maxPasses
        self.maxForwardRounds = maxForwardRounds; self.minimumLineEnergyKeV = minimumLineEnergyKeV
        self.flankScaling = flankScaling; self.flank = flank; self.rangeMarginFWHM = rangeMarginFWHM
        self.sumPeakToleranceKeV = sumPeakToleranceKeV; self.context = context
    }

    /// 0.06 keV: about half the Mn K alpha width of one detector.
    public static let defaultSumPeakToleranceKeV = 0.06

    public static let `default` = ProposerPolicy()
}

/// The unlisted-line check's geometry and bar.
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
