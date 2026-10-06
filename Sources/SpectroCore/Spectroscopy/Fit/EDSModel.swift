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

package nonisolated struct FitLine: Sendable, Equatable {
    package let id: String        // "Fe_Ka"
    package let energy: Double    // keV
    package let weight: Double    // relative to the group's alpha line (1 for the alpha line)
    package let fwhm: Double      // keV
}

package nonisolated struct FitLineGroup: Sendable, Equatable {
    /// The alpha line's id, e.g. "Fe_Ka"; also the group's name.
    package let id: String
    package let element: String
    /// The alpha line first, then the family's other in-range lines in table order.
    package let lines: [FitLine]
    /// Si-escape copies of the lines above the Si K edge (energy shifted down); empty when none.
    package let escapes: [FitLine]
}

package nonisolated struct EDSLineModel: Sendable, Equatable {
    package static let siKEdge = 1.839
    package static let sigma2fwhm = 2 * (2 * log(2.0)).squareRoot()

    package let groups: [FitLineGroup]
    package let resolutionMnKaEV: Double
    package let beamEnergy: Double
    package let escapePeaks: Bool
    /// Lines the model could not place, with the reason (never a NaN width): `XRayLines.fwhm` is nil when the
    /// law's radicand is negative (a low line on a very good detector). A group whose alpha line is dropped is dropped.
    package let droppedLines: [String]

    /// Groups in alphabetical order of the alpha line (eXSpy `_get_lines_from_elements` sorts).
    package static func build(
        elements: [String], axis: EnergyAxis, beamEnergy: Double, resolutionMnKaEV: Double, escapePeaks: Bool = true
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
            for l in candidates where inRange.contains(l.id) { if let f = fl(l, weight: l.weight) { lines.append(f) } }
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
                            droppedLines: dropped)
    }

    /// Counts per channel of a unit-area Gaussian sum over `energies` (channel-centre sampling,
    /// binned axis: times `scale`).
    package static func column(of lines: [FitLine], energies: [Double], scale: Double) -> [Double] {
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
}
