//
//  EELSComposition.swift
//  Role: atomic and weight percent from a fitted EELS model (the macTEM design 2.3 ask). The amount of an element is its master edge's
//        intensity, which is proportional to the areal density with the same factor for every edge of one image (the low-loss dose, or the
//        implicit unit without a low loss), so ratios of intensities are ratios of atoms.
//

import Foundation

/// One pixel's composition, in the order of the `symbols` it was asked for. A pixel with no answer has empty arrays and a reason.
public struct EELSCompositionPixel: Sendable, Equatable {
    public let atomicPercent: [Double]
    public let weightPercent: [Double]
    public let unavailable: EELSUnavailable?
}

public enum EELSQuantification {
    /// Standard atomic weights (g/mol) of the elements with a bundled cross section, as the kit's EDX tables use.
    public static let atomicMasses: [String: Double] = [
        "C": 12.0107, "N": 14.0067, "O": 15.9994, "Mg": 24.305, "Al": 26.9815386, "Si": 28.0855, "Fe": 55.845, "Cu": 63.546,
    ]

    /// at% and wt% of `symbols` at every pixel of `result` (a one-pixel result from a summed region works the same). An element with several
    /// independent edges (K and L) uses the first in fit order. A pixel is unavailable when an edge failed (its reason is kept), the amounts do
    /// not sum to a positive number (`noComposition`), or an amount is negative. Throws `symbolNotFitted` for a symbol with no edge in the model.
    /// There is no uncertainty on the percentages (open item).
    public static func composition(_ result: EELSModelResult, symbols: [String]) throws -> [EELSCompositionPixel] {
        var columns: [Int] = []
        if let dup = symbols.enumerated().first(where: { i, s in symbols[..<i].contains(s) })?.element { throw EELSModelError.symbolNotFitted(dup + " (listed twice)") }
        for s in symbols {
            guard let g = result.edges.firstIndex(where: { $0.element == s }), let _ = atomicMasses[s] else { throw EELSModelError.symbolNotFitted(s) }
            columns.append(g)
        }
        let masses = symbols.map { atomicMasses[$0]! }
        return result.pixels.map { pixel in
            var amounts: [Double] = []
            for g in columns {
                guard let v = pixel[g].intensity else {
                    return EELSCompositionPixel(atomicPercent: [], weightPercent: [], unavailable: pixel[g].unavailable ?? .fitFailed)
                }
                amounts.append(v)
            }
            let atoms = amounts.reduce(0, +)
            let weights = zip(amounts, masses).map { $0 * $1 }.reduce(0, +)
            guard atoms > 0, weights > 0, amounts.allSatisfy({ $0 >= 0 }) else {
                return EELSCompositionPixel(atomicPercent: [], weightPercent: [], unavailable: .noComposition)
            }
            return EELSCompositionPixel(atomicPercent: amounts.map { 100 * $0 / atoms },
                                        weightPercent: zip(amounts, masses).map { 100 * $0 * $1 / weights }, unavailable: nil)
        }
    }
}
