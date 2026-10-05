//
//  FourDetectorAbsorption.swift
//  Role: Self-absorption for a multi-segment EDS system (Super-X: four SDD
//        segments around the specimen) as ONE correction for the summed spectrum.
//
//  Not in eXSpy (it has one scalar take-off angle). Design: WP3 pre-registration
//  flag 1 / ADR 054 addendum. The summed stream is sum_d I0 * Omega_d * T_d(E),
//  so the exact correction for the sum is 1/Tbar with the SOLID-ANGLE-WEIGHTED
//  MEAN TRANSMISSION  Tbar = sum_d Omega_d' T_d / sum_d Omega_d'  (Omega_d' =
//  Omega_d (1 - holder shadow fraction)), T_d = (1 - e^-x_d)/x_d,
//  x_d = (mu/rho)(rho t)/sin(take-off_d). A geometric mean agrees only to first
//  order and runs away for a segment looking along the surface; it is computed
//  and reported as a comparison only.
//
//  Refusals (never guessed, unlike eXSpy's 0/0/35 deg defaults): a nil tilt, or a
//  segment with a nil azimuth, elevation or solid angle, or a take-off angle
//  within 1 deg of grazing.
//

import Foundation

package nonisolated struct DetectorSegment: Sendable {
    package var label: String
    package var azimuthDegrees: Double?
    package var elevationDegrees: Double?
    /// Collection solid angle of this segment, sr.
    package var solidAngleSr: Double?
    /// 0...1: the part of the segment's solid angle blocked by the holder.
    package var holderShadowFraction: Double

    package init(label: String, azimuthDegrees: Double?, elevationDegrees: Double?, solidAngleSr: Double?, holderShadowFraction: Double = 0) {
        self.label = label; self.azimuthDegrees = azimuthDegrees; self.elevationDegrees = elevationDegrees
        self.solidAngleSr = solidAngleSr; self.holderShadowFraction = holderShadowFraction
    }
}

package nonisolated struct FourDetectorGeometry: AbsorptionGeometry {
    package struct Resolved: Sendable {
        package let takeOffDegrees: Double
        package let weight: Double      // effective solid angle
    }
    package let segments: [Resolved]

    /// Resolves the geometry or refuses with the reason. `tiltAlpha` nil refuses.
    package init(segments input: [DetectorSegment], tiltAlphaDegrees: Double?, tiltBetaDegrees: Double = 0) throws {
        guard let tilt = tiltAlphaDegrees else { throw QuantError.missingTilt }
        guard !input.isEmpty else { throw QuantError.invalid("No detector segments.") }
        var out: [Resolved] = []
        for s in input {
            guard let az = s.azimuthDegrees else { throw QuantError.missingGeometry(segment: s.label, field: "azimuth") }
            guard let el = s.elevationDegrees else { throw QuantError.missingGeometry(segment: s.label, field: "elevation") }
            guard let om = s.solidAngleSr else { throw QuantError.missingGeometry(segment: s.label, field: "solid angle") }
            guard om > 0, (0...1).contains(s.holderShadowFraction) else {
                throw QuantError.invalid("Segment \(s.label): solid angle must be positive and the shadow fraction within 0...1.")
            }
            let toa = TakeOff.angle(tiltAlpha: tilt, azimuth: az, elevation: el, tiltBeta: tiltBetaDegrees)
            // The film is thin: an X-ray leaves through whichever face it meets,
            // the path is t/|sin(take-off)|, so a negative take-off is the same slab.
            guard abs(sin(toa * .pi / 180)) > sin(1 * Double.pi / 180) else {
                throw QuantError.grazingTakeOff(segment: s.label, degrees: toa)
            }
            out.append(Resolved(takeOffDegrees: toa, weight: om * (1 - s.holderShadowFraction)))
        }
        guard out.contains(where: { $0.weight > 0 }) else { throw QuantError.invalid("Every segment is fully shadowed.") }
        segments = out
    }

    private func transmissions(_ mac: Double, _ mt: Double) -> [Double] {
        segments.map { Transmission.slab(mac * mt / abs(sin($0.takeOffDegrees * .pi / 180))) }
    }

    /// The primary: solid-angle-weighted arithmetic mean.
    package func meanTransmission(macM2PerKg: Double, massThickness: Double) -> Double {
        let t = transmissions(macM2PerKg, massThickness)
        var num = 0.0, den = 0.0
        for (s, ti) in zip(segments, t) { num += s.weight * ti; den += s.weight }
        return num / den
    }

    /// The comparison: the same weights, geometric mean exp(sum w ln T / sum w).
    /// GM <= AM, equal only when every segment has the same T.
    package func geometricMeanTransmission(macM2PerKg: Double, massThickness: Double) -> Double {
        let t = transmissions(macM2PerKg, massThickness)
        var num = 0.0, den = 0.0
        for (s, ti) in zip(segments, t) { num += s.weight * log(ti); den += s.weight }
        return exp(num / den)
    }
}

package nonisolated enum ThicknessPropagation {
    /// sigma of any thickness-dependent result: |f(t+h) - f(t-h)| / (2h) * sigma_t,
    /// central difference with h = min(0.01 t, sigma_t) (> 0). `f` maps a
    /// thickness in nm to the quantity (e.g. an element's wt%).
    package static func sigma(at thicknessNm: Double, sigmaNm: Double, f: (Double) throws -> Double) throws -> Double {
        guard sigmaNm >= 0, thicknessNm > 0 else { throw QuantError.invalid("Thickness must be positive with a non-negative sigma.") }
        if sigmaNm == 0 { return 0 }
        let h = min(0.01 * thicknessNm, sigmaNm)
        let d = (try f(thicknessNm + h) - f(thicknessNm - h)) / (2 * h)
        return abs(d) * sigmaNm
    }
}
