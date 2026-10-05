//
//  XRayLines.swift
//  Role: The X-ray line table (elements Z = 1...92, K/L/M families with their sub-lines,
//        energies in keV, relative weights) exactly as eXSpy ships it, the detector
//        line-width law, and eXSpy's default line choice for an element.
//
//  Ported from eXSpy at commit 7185a4d13d7d5c550b7bb8d1e9bd62af9cc4203e
//  (GPL-3.0-or-later, same licence as this app; NOTICE names it):
//    - exspy/material/xray_lines.json            -> XRayLineData.swift (verbatim, generated)
//    - exspy/utils/eds/_xray_lines.py:138-175    -> `fwhm(resolutionMnKaEV:atEnergy:)`
//    - exspy/utils/eds/_xray_lines.py:75-89      -> `parseOnlyLines`
//    - exspy/signals/_eds.py:143-173, 472-526    -> `linesInRange`, `defaultLines`
//

import Foundation

/// K, L or M family of an X-ray line (the first letter of its name).
package nonisolated enum XRayFamily: String, Sendable, Equatable {
    case K, L, M
}

/// One emission line: `Fe_Ka` is element "Fe", name "Ka".
package nonisolated struct XRayLine: Sendable, Equatable {
    package let atomicNumber: Int
    package let element: String
    package let name: String
    package let energy: Double      // keV
    package let weight: Double      // relative to the family's alpha line (eXSpy / EPQ)

    /// eXSpy's identifier, `Element_Line`.
    package var id: String { element + "_" + name }
    package var family: XRayFamily { XRayFamily(rawValue: String(name.prefix(1)))! }
}

package nonisolated enum XRayLines {
    /// Mn Kα, the reference of the line-width law (`_get_energy_xray_line("Mn_Ka")`).
    package static let mnKaEnergy: Double = 5.8987

    /// Every line of the table in file order (Z ascending, eXSpy's per-element order).
    package static let all: [XRayLine] = {
        var out: [XRayLine] = []
        for row in XRayLineData.rows.split(separator: "\n") {
            let f = row.split(separator: " ")
            guard f.count == 5, let z = Int(f[0]), let e = Double(f[3]), let w = Double(f[4]) else {
                preconditionFailure("XRayLineData row malformed: \(row)")
            }
            out.append(XRayLine(atomicNumber: z, element: String(f[1]), name: String(f[2]), energy: e, weight: w))
        }
        return out
    }()

    private static let byId: [String: XRayLine] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    /// DEVIATION: eXSpy lists H "Ka" (0.0013598 keV) and He "Ka" (0.0024587 keV), the ionisation
    /// energies, which are not X-ray lines (validation.md §1d.3). They stay in `all` as shipped;
    /// `lines(of:)` and the line choices below never return them.
    package static let notRealLines: Set<String> = ["H", "He"]

    /// `energy` of `Element_Line`, nil when the table has no such line (hyperspy: KeyError).
    package static func line(_ id: String) -> XRayLine? { byId[id] }

    /// The lines of `element` in eXSpy's file order (empty for H, He, and for Li, Np, Pu, Am which
    /// the table carries without lines: eXSpy drops them silently, validation.md §1d.4).
    package static func lines(of element: String) -> [XRayLine] {
        notRealLines.contains(element) ? [] : all.filter { $0.element == element }
    }

    // MARK: Line width

    /// eXSpy `get_FWHM_at_Energy` (`_xray_lines.py:138-175`): Fiori and Newbury, in keV.
    /// FWHM(E) = sqrt(2.5 (E - E_MnKα) * 1000 + FWHM_MnKα²) / 1000, with E in keV and
    /// the Mn Kα resolution in eV (eXSpy's constant `eV2keV = 1000.0`, a misleading name).
    /// The comment "In mrad" at line 175 is wrong; the value is keV.
    ///
    /// DEVIATION: eXSpy's `math.sqrt` raises ValueError when 2.5 (E - E_MnKα) 1000 + res² < 0 (a low
    /// line on a good detector, e.g. C Kα at 110 eV); this returns nil instead of NaN.
    package static func fwhm(resolutionMnKaEV: Double, atEnergy e: Double) -> Double? {
        let fwhmE = 2.5 * (e - mnKaEnergy) * 1000.0 + resolutionMnKaEV * resolutionMnKaEV
        guard fwhmE >= 0 else { return nil }
        return fwhmE.squareRoot() / 1000.0
    }

    // MARK: Line choice

    /// `_parse_only_lines`: "a" adds Ka, La, Ma; "b" adds Kb, Lb1, Mb. nil stays nil (all lines).
    package static func parseOnlyLines(_ only: [String]?) -> [String]? {
        guard var out = only else { return nil }
        for o in only! {
            if o == "a" { out.append(contentsOf: ["Ka", "La", "Ma"]) }
            else if o == "b" { out.append(contentsOf: ["Kb", "Lb1", "Mb"]) }
        }
        return out
    }

    /// `_get_xray_lines_in_spectral_range`: low < E < min(high, beam energy), strictly.
    package static func linesInRange(_ ids: [String], axis: EnergyAxis, beamEnergy: Double?) -> [String] {
        var high = axis.highValue
        if let b = beamEnergy, b < high { high = b }
        return ids.filter { id in
            guard let l = line(id) else { return false }
            return axis.lowValue < l.energy && l.energy < high
        }
    }

    /// `_get_lines_from_elements(elements, only_one, only_lines)` (`_eds.py:472-526`), the lines
    /// `add_lines()` stores: per element the lines in the spectral range; with `onlyOne` the first
    /// (alphabetical) line below beam energy / 2, else the alphabetically last one when none
    /// is (the `select_this = -1` start). Result alphabetically sorted.
    package static func defaultLines(
        elements: [String], axis: EnergyAxis, beamEnergy: Double?,
        onlyOne: Bool = true, onlyLines: [String]? = ["a"]
    ) -> [String] {
        let only = parseOnlyLines(onlyLines)
        var result: [String] = []
        for element in elements {
            var candidates: [String] = []
            for l in lines(of: element) {
                // eXSpy: `if only_lines and ...`, an empty list is no filter.
                if let only, !only.isEmpty, !only.contains(l.name) { continue }
                candidates.append(l.id)
            }
            var inRange = linesInRange(candidates, axis: axis, beamEnergy: beamEnergy)
            if onlyOne && !inRange.isEmpty {
                inRange.sort(by: pythonLess)
                // eXSpy falls back to the beam energy = axis high value when none is defined.
                let beam = beamEnergy ?? axis.highValue
                var pick = inRange.count - 1
                for (i, id) in inRange.enumerated() where line(id)!.energy < beam / 2 { pick = i; break }
                inRange = [inRange[pick]]
            }
            result.append(contentsOf: inRange)
        }
        result.sort(by: pythonLess)
        return result
    }

    /// Python's str ordering for ASCII (code point order), not Swift's locale-free-but-different `<`.
    package static func pythonLess(_ a: String, _ b: String) -> Bool {
        a.utf8.lexicographicallyPrecedes(b.utf8)
    }
}
