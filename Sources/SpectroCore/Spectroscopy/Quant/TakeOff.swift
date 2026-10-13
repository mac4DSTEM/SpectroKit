//
//  TakeOff.swift
//  Role: X-ray take-off angle of a detector for a tilted specimen.
//
//  Port of eXSpy utils/eds/_geometry.py `take_off_angle` (7185a4d1, lines 24-85).
//  Unlike eXSpy, which fills a missing tilt/azimuth/elevation with 0/0/35 deg in
//  `_defaults_parser.py`, a missing value here is a refusal (`QuantError.missingTilt`
//  / `missingGeometry`) -- DEVIATION, validation.md §1d item 7.
//

import Foundation

package nonisolated enum TakeOff {
    /// Degrees. `tiltAlpha`: stage alpha tilt (positive faces the detector);
    /// `azimuth`: 0 is perpendicular to the alpha-tilt axis; `elevation`: detector
    /// elevation; `tiltBeta`: stage beta tilt.
    package static func angle(
        tiltAlpha: Double, azimuth: Double, elevation: Double, tiltBeta: Double = 0
    ) -> Double {
        let alpha = tiltAlpha * .pi / 180
        let beta = -tiltBeta * .pi / 180
        let phi = azimuth * .pi / 180
        let theta = -elevation * .pi / 180
        let c = sin(alpha) * cos(beta) * cos(phi) * cos(theta)
            - sin(beta) * sin(phi) * cos(theta)
            - cos(alpha) * cos(beta) * sin(theta)
        // The argument is a dot product of unit vectors; rounding can push it a
        // hair outside [-1, 1] at exactly grazing/normal geometry.
        return 90 - acos(min(1, max(-1, c))) * 180 / .pi
    }
}
