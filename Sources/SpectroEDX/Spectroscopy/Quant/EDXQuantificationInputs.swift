//
//  EDXQuantificationInputs.swift
//  Role: the three facts of a pooled fit that the per-pixel `EDXQuantification` needs and that were `package` before 0.8.2: the
//        k-factors the fit used (computed or typed), each row's line energy, and the take-off angle of a file's detector geometry.
//        An app builds `EDXQuantificationSetup` from them (`.cliffLorimer(kFactors:thicknessNm:)`, `EDXAbsorptionSetting`) so a
//        wt% / at% map uses the very k and geometry the pooled number used. No new numerics: the values are the fit's own.
//
//  DEVIATION: the pooled fit averages the transmission over the four detector segments; `EDXAbsorptionSetting` takes ONE take-off
//  angle. `takeOffDegrees(metadata:)` returns the solid-angle-weighted mean of the segments' angles (shadow fractions applied), so
//  a map with absorption differs slightly from the pooled fit's four-segment mean; both are `validation: "none"`.
//

import Foundation
import SpectroCore

/// One k-factor of a pooled fit.
public nonisolated struct PooledKFactor: Sendable, Equatable {
    public var element: String
    /// Relative to the fit's reference element (k = 1 there); the ratios are what Cliff-Lorimer uses.
    public var k: Double
    /// Relative 1-sigma (0.20 = 20 %); 0 on the reference.
    public var relativeSigma: Double
}

extension PooledQuantification {
    /// The k-factors this fit used, one per quantified row in the rows' order, whether computed or typed; nil when no at% was computed.
    /// Feed `k` to `EDXQuantificationMethod.cliffLorimer(kFactors:thicknessNm:)` in the same element order.
    public var kFactors: [PooledKFactor]? {
        guard let set = kSet else { return nil }
        var out: [PooledKFactor] = []
        for r in rows {
            guard let k = set.k(r.element) else { return nil }
            out.append(PooledKFactor(element: r.element, k: k, relativeSigma: set.relSigma(r.element) ?? 0))
        }
        return out
    }

    /// Where the k-factors came from, in words ("Brown-Powell ..." or the typed citation); nil with `kFactors`.
    public var kFactorSourceDescription: String? { kSet?.source }
}

extension PooledQuantification.Row {
    /// Energy of the line this row was fitted on (`groupID`, for example `Al_Ka`), keV; nil for a group the line table does not know.
    /// This is the `EDXAbsorptionSetting.lineEnergiesKeV` entry of the element.
    public var lineEnergyKeV: Double? { XRayLines.line(groupID)?.energy }
}

extension EDXQuantification {
    /// The take-off angle (degrees) of the file's detector geometry: the solid-angle-weighted mean of the segments' angles for the
    /// file's alpha and beta tilt, for `EDXAbsorptionSetting.takeOffDegrees`. Throws the reason (no tilt, a segment without
    /// azimuth, elevation or solid angle, a GMS file whose geometry is not read) in the pooled fit's own words.
    public static func takeOffDegrees(metadata: SpectrumImageMetadata) throws -> Double {
        switch PooledQuantifier.geometry(QuantificationMethod(), metadata) {
        case .failure(let why): throw why
        case .success(let g):
            let total = g.segments.reduce(0) { $0 + $1.weight }
            guard total > 0 else { throw QuantificationRefusal("Every detector segment is fully shadowed.") }
            return g.segments.reduce(0) { $0 + $1.weight * $1.takeOffDegrees } / total
        }
    }
}
