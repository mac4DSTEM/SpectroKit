//
//  DetectorBlur.swift
//  Role: A synthetic continuum seen through the detector, for the in-test EDX generators: every channel's counts spread as a
//        Gaussian of the line-width law's sigma at that channel's energy (`XRayLines.fwhm`, the fit's own resolution law), over
//        +-6 sigma, normalised over the channels reached (counts conserved). The same rule as tools/edx-sim/detector_blur.py.
//
//  Why: a detector records every photon with its resolution, so an absorption step in the continuum reaches the spectrum as a
//  blurred step (about 75 eV FWHM at the Al K edge for 130 eV at Mn K-alpha), never a jump between two channels.
//

import Foundation
import SpectroEDX

public enum DetectorBlur {
    /// `values` (one count per channel at `energies`, ascending, equally spaced) seen through a detector of `resolutionMnKaEV`.
    public static func blur(_ values: [Double], energies: [Double], resolutionMnKaEV: Double) -> [Double] {
        precondition(values.count == energies.count && energies.count > 1)
        let de = energies[1] - energies[0]
        func reach(_ j: Int) -> (Int, Double) {
            let fwhm = XRayLines.fwhm(resolutionMnKaEV: resolutionMnKaEV, atEnergy: max(energies[j], 0)) ?? resolutionMnKaEV / 1000
            let s = fwhm / (8 * log(2.0)).squareRoot()
            return (Int((6 * s / de).rounded(.up)), s)
        }
        var out = [Double](repeating: 0, count: values.count)
        for j in values.indices where values[j] != 0 {
            let (r, s) = reach(j)
            let lo = max(0, j - r), hi = min(values.count - 1, j + r)
            var w = [Double](repeating: 0, count: hi - lo + 1), sum = 0.0
            for i in lo...hi { let z = (energies[i] - energies[j]) / s; w[i - lo] = exp(-0.5 * z * z); sum += w[i - lo] }
            for i in lo...hi { out[i] += values[j] * w[i - lo] / sum }
        }
        // Within one kernel reach of an axis end the detector also receives counts from beyond the axis, which `values` does not
        // hold: there the input is kept as it is (a smooth continuum is its own blur to first order), so the ends do not roll off.
        let n = values.count
        for i in 0..<min(reach(0).0, n) { out[i] = values[i] }
        for i in max(0, n - reach(n - 1).0)..<n { out[i] = values[i] }
        return out
    }
}
