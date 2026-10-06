//
//  QuantError.swift
//  Role: The reasons quantification refuses to produce a number. Every case
//        carries enough to be shown to the user as the reason.
//

import Foundation

package nonisolated enum QuantError: LocalizedError, Equatable {
    case countMismatch(String)
    case unknownElement(String)
    /// Fewer than two lines above `minIntensity`: Cliff-Lorimer is a ratio method.
    /// DEVIATION from eXSpy `quantification_cliff_lorimer`, which reports 100 % of
    /// the one element that has a line (and all zeros when none has).
    case needTwoLines(linesAbove: Int)
    case missingTilt
    case missingGeometry(segment: String, field: String)
    case grazingTakeOff(segment: String, degrees: Double)
    case didNotConverge(iterations: Int)
    case noDensity(String)
    case outsideTable(String, energyKeV: Double)
    case invalid(String)

    package var errorDescription: String? {
        switch self {
        case .countMismatch(let s): return s
        case .unknownElement(let e): return "No atomic data for element \(e)."
        case .needTwoLines(let n):
            return "Cliff-Lorimer needs at least two lines above the intensity floor; this spectrum has \(n)."
        case .missingTilt:
            return "The stage tilt is not known, so the absorption geometry cannot be computed."
        case .missingGeometry(let seg, let field):
            return "Detector segment \(seg) has no \(field); absorption is refused rather than guessed."
        case .grazingTakeOff(let seg, let deg):
            return "Detector segment \(seg) has no valid take-off angle (\(deg)°): its X-rays do not leave the film towards the detector, so the path length is undefined."
        case .didNotConverge(let n):
            return "Absorption correction did not converge after \(n) iterations."
        case .noDensity(let e): return "No bulk density for \(e); mass thickness cannot be computed."
        case .outsideTable(let e, let k): return "\(e) has no tabulated absorption at \(k) keV."
        case .invalid(let s): return s
        }
    }
}
