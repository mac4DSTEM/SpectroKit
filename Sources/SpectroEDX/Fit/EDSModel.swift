//
//  EDSModel.swift
//  Role: The line model of the spectrum fit, as eXSpy's `EDSModel` builds it: ONE GAUSSIAN PER
//        LINE with its centre and width FIXED (energy from the line table, width from the
//        Fiori-Newbury law at the detector's Mn K-alpha resolution), the lines of a family tied to
//        the family's alpha line by the database weights. The only free amplitude of a family is
//        its alpha line's area, so a spectrum is a LINEAR combination of columns (LinearDesign).
//
//  Ported from eXSpy 7185a4d1 (GPL-3.0-or-later; NOTICE) `models/edsmodel.py`:
//    - `add_family_lines` (183-299): one component per alpha line (Ka, La, Ma) of each element in the
//      spectral range, then every other line of the SAME family letter in range, tied "x * weight";
//    - `_get_line_energy(..., FWHM_MnKa="auto")` for the centre and FWHM (XRayLines.fwhm);
//    - hyperspy's `Gaussian` (area A, sigma = FWHM / 2.3548) on a BINNED axis: counts in channel i =
//      A * scale * N(E_i; c, sigma), so A is the line's area in COUNTS (hyperspy multiplies a binned
//      model by the channel width; that is why eXSpy's 2800.02 is a count total, not 28.0).
//      The Gaussian is sampled at the channel centre, as hyperspy does (not integrated over the channel).
//
//  DEVIATION (eXSpy): escape peaks. eXSpy models none (validation.md section 5, "spurious peaks").
//  Here, for every line group with a line above the Si K edge (1.839 keV), a second column holds the
//  Si-escape copy of the group: the same lines shifted down by the Si K-alpha energy, width from the
//  law at the shifted energy, with its OWN non-negative area (the escape fraction is detector- and
//  energy-dependent and is reported, not assumed). Mg, Al and Si (all <= 1.84 keV) produce none; the
//  footer names the setting. `escapePeaks: false` is eXSpy parity.
//

import Foundation
import SpectroCore

/// An opt-in low-energy tail on every line (and escape and sum peak) of the fit: PyMca's Hypermet short tail (the formula; MIT, NOTICE).
/// Per line at E0 with Gaussian sigma and total area A, the column is `A (G(E) + T(E)) / (1 + fraction)` with
/// `T(E) = fraction / (2 slope) exp((E - E0)/slope + sigma^2/(2 slope^2)) erfc((E - E0)/(sqrt2 sigma) + sigma/(sqrt2 slope))`, tied to the same A (no new free
/// parameter). The shelf (step) term of Hypermet is NOT included. No Python counterpart (exSpy fits Gaussians); `validation: "none"`.
public nonisolated struct LineTail: Sendable, Equatable, Codable {
    /// Tail area as a fraction of the Gaussian area (T integrates to this).
    public var fraction: Double
    /// Decay length of the tail towards low energy, keV.
    public var slopeKeV: Double
    /// Where the numbers come from (a measurement, a standard, a typed value); printed in the fit's footer.
    public var source: String

    /// A fraction below 0 reads as 0 (no tail) and a slope below 1 eV as 1 eV: the column must never be NaN (review 2026-10-23).
    public init(fraction: Double, slopeKeV: Double, source: String) {
        self.fraction = fraction.isFinite ? max(fraction, 0) : 0
        self.slopeKeV = slopeKeV.isFinite ? max(slopeKeV, 0.001) : 0.001
        self.source = source
    }

    /// The footer's words for the line shape.
    package static func label(_ tail: LineTail?) -> String {
        guard let t = tail else { return "line shape: Gaussian" }
        return "line shape: Gaussian + tail (f \(String(format: "%.3g", t.fraction)), \u{03B2} \(String(format: "%.3g", t.slopeKeV)) keV, \(t.source))"
    }
}

package nonisolated struct FitLine: Sendable, Equatable {
    package let id: String        // "Fe_Ka"
    package let energy: Double    // keV
    package let weight: Double    // relative to the group's alpha line (1 for the alpha line)
    package let fwhm: Double      // keV

    package init(id: String, energy: Double, weight: Double, fwhm: Double) {
        self.id = id; self.energy = energy; self.weight = weight; self.fwhm = fwhm
    }
}

public nonisolated struct FitLineGroup: Sendable, Equatable {
    /// The alpha line's id, e.g. "Fe_Ka"; also the group's name.
    package let id: String
    package let element: String
    /// The alpha line first, then the family's other in-range lines in table order.
    package let lines: [FitLine]
    /// Si-escape copies of the lines above the Si K edge (energy shifted down); empty when none.
    package let escapes: [FitLine]
}

/// Which table ties a family's sub-lines to its alpha line.
public nonisolated enum EDSLineWeights: Sendable, Equatable {
    /// eXSpy's `xray_lines.json` weights: the quantification fit (parity, D17).
    case exspy
    /// The identification fit (docs/design/auto-id-tem.md): the K family's Kβ from NIST EPQ `LineWeights.csv` (public domain), every K
    /// transition other than K-L2 and K-L3 over those two (Al 0.0315 against eXSpy's 0.0132; two measured Al-alloy map sums read 0.031 and
    /// 0.034 with Kβ free). L and M families keep eXSpy's weights (EPQ's are per subshell, with no clean map onto eXSpy's lines).
    case epqK
}

public nonisolated struct EDSLineModel: Sendable, Equatable {
    package static let siKEdge = 1.839
    package static let sigma2fwhm = 2 * (2 * log(2.0)).squareRoot()

    public let groups: [FitLineGroup]
    package let resolutionMnKaEV: Double
    package let beamEnergy: Double
    package let escapePeaks: Bool
    /// Lines the model could not place, with the reason (never a NaN width): `XRayLines.fwhm` is nil when the
    /// law's radicand is negative (a low line on a very good detector). A group whose alpha line is dropped is dropped.
    package let droppedLines: [String]
    /// The low-energy tail of every column of this model; nil = Gaussians only (every number of the default fit).
    package var lineTail: LineTail? = nil

    /// Groups in alphabetical order of the alpha line (eXSpy `_get_lines_from_elements` sorts).
    public static func build(
        elements: [String], axis: EnergyAxis, beamEnergy: Double, resolutionMnKaEV: Double, escapePeaks: Bool = true,
        lineTail: LineTail? = nil, lineWeights: EDSLineWeights = .exspy
    ) -> EDSLineModel {
        let mains = XRayLines.defaultLines(
            elements: elements, axis: axis, beamEnergy: beamEnergy, onlyOne: false, onlyLines: ["Ka", "La", "Ma"])
        let siKa = XRayLines.line("Si_Ka")!.energy
        var groups: [FitLineGroup] = []
        var dropped: [String] = []
        func fwhmReason(_ id: String, _ e: Double) -> String {
            "\(id) at \(e) keV: the line-width law has no real width at this energy for \(resolutionMnKaEV) eV at Mn K-alpha"
        }
        for id in mains {
            guard let alpha = XRayLines.line(id) else { continue }
            func fl(_ l: XRayLine, weight: Double) -> FitLine? {
                guard let w = XRayLines.fwhm(resolutionMnKaEV: resolutionMnKaEV, atEnergy: l.energy) else {
                    dropped.append(fwhmReason(l.id, l.energy)); return nil
                }
                return FitLine(id: l.id, energy: l.energy, weight: weight, fwhm: w)
            }
            guard let first = fl(alpha, weight: 1) else { dropped.append("group \(id) dropped with its alpha line"); continue }
            var lines = [first]
            let letter = alpha.name.first!
            // eXSpy: `if line[0] in li and line != li` over the element's lines (table order), in range.
            let candidates = XRayLines.lines(of: alpha.element).filter { $0.name.contains(letter) && $0.name != alpha.name }
            let inRange = Set(XRayLines.linesInRange(candidates.map(\.id), axis: axis, beamEnergy: beamEnergy))
            for l in candidates where inRange.contains(l.id) {
                var w = l.weight
                if lineWeights == .epqK, letter == "K", let epq = EPQLineWeights.bundled?.kBetaOverKAlpha(element: alpha.element) { w = epq }
                if let f = fl(l, weight: w) { lines.append(f) }
            }
            var esc: [FitLine] = []
            if escapePeaks {
                for l in lines where l.energy > siKEdge {
                    let e = l.energy - siKa
                    if let w = XRayLines.fwhm(resolutionMnKaEV: resolutionMnKaEV, atEnergy: e) {
                        esc.append(FitLine(id: l.id + "_esc", energy: e, weight: l.weight, fwhm: w))
                    } else { dropped.append(fwhmReason(l.id + "_esc", e)) }
                }
            }
            groups.append(FitLineGroup(id: id, element: alpha.element, lines: lines, escapes: esc))
        }
        return EDSLineModel(groups: groups, resolutionMnKaEV: resolutionMnKaEV, beamEnergy: beamEnergy,
                            escapePeaks: escapePeaks,
                            droppedLines: dropped, lineTail: lineTail)
    }

    /// Counts per channel of a unit-area Gaussian sum over `energies` (channel-centre sampling,
    /// binned axis: times `scale`).
    package static func column(of lines: [FitLine], energies: [Double], scale: Double) -> [Double] {
        column(of: lines, energies: energies, scale: scale, tail: nil)
    }

    /// As `column(of:energies:scale:)` with an optional low-energy tail. With `tail` nil this is the Gaussian column, the same code path
    /// and the same numbers. With a tail each line is `weight * scale * (G + T) / (1 + f)`: the tail adds area `f`, and dividing by `(1 + f)`
    /// keeps the line's weight (and so the fitted area A) its TOTAL area, tail included.
    package static func column(of lines: [FitLine], energies: [Double], scale: Double, tail: LineTail?) -> [Double] {
        if let tail, tail.fraction != 0 { return tailColumn(of: lines, energies: energies, scale: scale, tail: tail) }
        var out = [Double](repeating: 0, count: energies.count)
        for l in lines {
            let sigma = l.fwhm / sigma2fwhm
            let norm = l.weight * scale / (sigma * (2 * Double.pi).squareRoot())
            let inv = 1 / (2 * sigma * sigma)
            // Beyond 38 sigma exp underflows to 0 (and below 1e-300); skip the work.
            let reach = 38 * sigma
            for i in energies.indices {
                let d = energies[i] - l.energy
                if abs(d) > reach { continue }
                out[i] += norm * exp(-d * d * inv)
            }
        }
        return out
    }

    private static func tailColumn(of lines: [FitLine], energies: [Double], scale: Double, tail: LineTail) -> [Double] {
        var out = [Double](repeating: 0, count: energies.count)
        let f = tail.fraction, beta = tail.slopeKeV
        let total = 1 + f
        for l in lines {
            let sigma = l.fwhm / sigma2fwhm
            let gNorm = l.weight * scale / (total * sigma * (2 * Double.pi).squareRoot())
            let tNorm = l.weight * scale * f / (total * 2 * beta)
            let inv = 1 / (2 * sigma * sigma)
            let reach = 38 * sigma
            let lowReach = reach + 40 * beta
            let r2s = 1 / (2.0.squareRoot() * sigma)
            let shift = sigma / (2.0.squareRoot() * beta)
            let half = sigma * sigma / (2 * beta * beta)
            for i in energies.indices {
                let d = energies[i] - l.energy
                if d > reach || d < -lowReach { continue }
                var v = 0.0
                if abs(d) <= reach { v = gNorm * exp(-d * d * inv) }
                // exp overflows past about 709 where erfc has already underflowed (a small beta against sigma): the product is 0 there, never NaN.
                let exponent = d / beta + half
                if exponent < 700 { v += tNorm * exp(exponent) * erfc(d * r2s + shift) }
                out[i] += v
            }
        }
        return out
    }
}
