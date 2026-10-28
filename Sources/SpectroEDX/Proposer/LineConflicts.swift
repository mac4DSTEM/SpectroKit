//
//  LineConflicts.swift
//  Role: The named conflicts the element proposer attaches to a candidate ("Al sum or Ar?",
//        "Ga L from FIB?", "Cu from the grid or the Q phase?") and the elements it refuses.
//        Data only: it decides nothing and edits nothing.
//
//  Round 3 (rebuilt on the WP3 fit): the round-2 table is kept where it was sound (sum peaks, Ga, Cu, the refusals).
//  Dropped: the generic "overlap" conflict and the Mg-beside-Ga one. Overlapping lines are resolved by the joint fit
//  itself and its covariance, so an overlap is no longer a reason to doubt a proposal; what remains are the causes a
//  fit cannot tell apart from an element: a pile-up peak, a contaminant from the preparation, a grid.
//  Sum peaks are no longer a fixed list: every pair of detected parents is a candidate sum energy.
//  Sources: docs/archive/v5/edx-dossier-2026-10-05.md section 6 (spurious peaks), ADR 054 (V5-Q6). Energies in keV.
//

import Foundation

public nonisolated struct LineConflict: Equatable, Sendable {
    public enum Kind: String, Sendable { case sumPeak, fibContamination, gridOrSample }

    public let id: String
    public let kind: Kind
    /// The candidate the conflict is attached to: element symbol and the line group's name.
    public let element: String
    public let line: String?
    /// Peak positions the conflict is about.
    package let energiesKeV: [Double]
    /// Elements that must be detected for the conflict to apply (a sum peak's parents).
    package let requires: [String]
    /// The question shown to the owner.
    public let question: String
    /// What can settle it.
    package let remedy: String

    /// Public memberwise initialiser (0.8.0): a consumer can build a conflict, for example to test a view of one.
    public init(id: String, kind: Kind, element: String, line: String?, energiesKeV: [Double], requires: [String],
                question: String, remedy: String) {
        self.id = id; self.kind = kind; self.element = element; self.line = line
        self.energiesKeV = energiesKeV; self.requires = requires; self.question = question; self.remedy = remedy
    }
}

/// A detected line that can be a parent of a pile-up peak: its element and its alpha-line energy.
package nonisolated struct SumParent: Equatable, Sendable {
    package let element: String
    package let energyKeV: Double
    package init(element: String, energyKeV: Double) { self.element = element; self.energyKeV = energyKeV }
}

public nonisolated enum LineConflicts {
    /// A candidate's alpha line counts as "on" a sum-peak energy within this many keV (about half the
    /// Mn K-alpha FWHM of a Super-X detector). A sum energy with no candidate within it gets its own column in
    /// the fit instead (ElementProposer), so it can neither be missed nor be mistaken for an element.
    package static let sumPeakToleranceKeV = ProposerPolicy.defaultSumPeakToleranceKeV

    /// Every pair (self-pairs included) of detected parents, as (label, energy, the two elements).
    package static func sumEnergies(parents: [SumParent]) -> [(label: String, energyKeV: Double, elements: [String])] {
        var out: [(String, Double, [String])] = []
        let p = parents.sorted { $0.element < $1.element }
        for i in p.indices { for j in i..<p.count {
            let label = p[i].element == p[j].element ? "\(p[i].element)+\(p[i].element) sum" : "\(p[i].element)+\(p[j].element) sum"
            out.append((label, p[i].energyKeV + p[j].energyKeV, [p[i].element, p[j].element]))
        } }
        return out
    }

    /// All conflicts that apply to `element` whose alpha line sits at `lineEnergyKeV`, given the detected parents.
    package static func conflicts(element: String, line: String, lineEnergyKeV: Double, parents: [SumParent],
                                  toleranceKeV: Double = sumPeakToleranceKeV, context: ElementContext = .default) -> [LineConflict] {
        var out: [LineConflict] = []
        for s in sumEnergies(parents: parents) where abs(lineEnergyKeV - s.energyKeV) <= toleranceKeV {
            let near = abs(lineEnergyKeV - s.energyKeV) < 0.02
            out.append(LineConflict(
                id: "sum-\(s.label)-\(element)", kind: .sumPeak, element: element, line: line,
                energiesKeV: [s.energyKeV, lineEnergyKeV], requires: Array(Set(s.elements)).sorted(),
                question: "\(s.label) peak (\(String(format: "%.3f", s.energyKeV)) keV) or \(ElementWindows.label(ofLineID: line)) (\(String(format: "%.3f", lineEnergyKeV)) keV)?"
                    + (near ? " They are \(String(format: "%.0f", abs(lineEnergyKeV - s.energyKeV) * 1000)) eV apart, far inside the detector resolution." : ""),
                remedy: "Acquire two spectrum images at different beam currents: a sum peak scales with the square of the count rate, an element does not."))
        }
        if context.implantedElements.contains(element) {
            if element == "Ga" {
                out.append(LineConflict(
                    id: "ga-fib", kind: .fibContamination, element: "Ga", line: line,
                    energiesKeV: [1.098, 1.254], requires: [],
                    question: "Ga from FIB? Ga is implanted by FIB milling; its L\u{03B1} (1.098 keV) sits 156 eV below Mg K\u{03B1} (1.254 keV).",
                    remedy: "Ga K\u{03B1} (9.25 keV) present? Check a thin or unmilled region; keep Ga fitted but excluded from Quantify."))
            } else {
                out.append(LineConflict(
                    id: "\(element.lowercased())-fib", kind: .fibContamination, element: element, line: line,
                    energiesKeV: [lineEnergyKeV], requires: [],
                    question: "\(element) from ion milling? \(element) can be implanted by FIB milling.",
                    remedy: "Check a thin or unmilled region; keep \(element) fitted but excluded from Quantify."))
            }
        }
        if context.gridElements.contains(element) {
            if element == "Cu" {
                out.append(LineConflict(
                    id: "cu-grid", kind: .gridOrSample, element: "Cu", line: line,
                    energiesKeV: [lineEnergyKeV], requires: [],
                    question: "Cu from the grid or from the Q phase?",
                    remedy: "Measure Cu on a hole region (no sample): net Cu there is grid and holder signal."))
            } else {
                out.append(LineConflict(
                    id: "\(element.lowercased())-grid", kind: .gridOrSample, element: element, line: line,
                    energiesKeV: [lineEnergyKeV], requires: [],
                    question: "\(element) from the grid or from the sample?",
                    remedy: "Measure \(element) on a hole region (no sample): net \(element) there is grid and holder signal."))
            }
        }
        return out
    }

    /// Elements the app refuses, with the reason shown in the picker.
    package static func refusal(for element: String) -> String? {
        switch element {
        case "H", "He":
            return "\(element) has no characteristic X-ray line: it cannot be detected by EDX."
        case "Li":
            return "Li K (about 54 eV) lies below the detector's energy range and is absorbed in its window; it cannot be quantified by EDX."
        case "Be":
            return "Be K (about 109 eV) lies below the detector's energy range and is absorbed in its window; it cannot be quantified by EDX."
        default:
            return nil
        }
    }

    /// The elements `refusal` covers: always reported with their reasons.
    public static let refusedElements = ["H", "He", "Li", "Be"]
}
