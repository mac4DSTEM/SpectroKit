//
//  RealFileAutoIDTests.swift
//  Role: the known answers of Auto ID on the owner's three labelled spectrum images (opt-in: SPECTRO_REAL_DATA=1 and the files under
//        $MACEM_DATA/stem-edx; the files stay out of the repo). The whole-map sum is proposed on the file's axis, the axis is refined on
//        the first proposal's K lines as the apps do, and the proposal on the refined axis must name every true element and nothing
//        else. Allowed, never required: Cu (the grid), Zr (found on all three files at Zr Kα 15.8 keV, 5 000 to 30 000 counts: the
//        instrument's), Fe and Mn on the Al alloys (minor alloying elements of a 6xxx alloy: Mn reads 8 000 and 64 000 counts, 22 and 70 times
//        its limit; the owner's word on the alloy is pending), Ga on the FIB lamella.
//

import Foundation
import Testing
import SpectroCore
import SpectroEDX

struct RealFileAutoIDTests {
    private static let base = (ProcessInfo.processInfo.environment["MACEM_DATA"] ?? NSHomeDirectory() + "/GitHub/mac4DSTEM_Organization/data") + "/stem-edx/"
    private static let files: [(name: String, truth: Set<String>, allowed: Set<String>)] = [
        ("SI HAADF 1339 65000 x 20260508.emd", ["O", "Mg", "Al", "Si", "Cu"], ["Fe", "Mn", "Zr"]),
        ("SI HAADF 1840 23000 x 20260506.emd", ["O", "Mg", "Al", "Si", "Cu"], ["Fe", "Mn", "Zr"]),
        ("SI HAADF 1456 77000 x 20260420.emd", ["O", "Si", "Ni", "Ge", "Pt"], ["Cu", "Ga", "Zr"]),
    ]

    private static func line(_ r: ProposalResult) -> String {
        r.candidates.filter { $0.aboveCriticalLevel }.map { c in
            "\(c.element) \(c.group) \(Int(c.net))/\(Int(c.detectionLimit)) \(c.isProposed ? "P" : (c.familyNote != nil ? "W" : "p"))\(c.possibleReason.map { " (\($0.prefix(120)))" } ?? "")"
        }.joined(separator: "; ")
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["SPECTRO_REAL_DATA"] == "1", "set SPECTRO_REAL_DATA=1 with the owner's files"),
          arguments: 0..<3)
    func testKnownAnswers(_ index: Int) throws {
        let file = Self.files[index]
        let path = Self.base + file.name
        try #require(FileManager.default.fileExists(atPath: path), "absent: \(path)")
        let t0 = Date()
        let loaded = try SpectrumImageOpener.open(path: path, kind: .veloxSpectrumImage)
        let counts = loaded.sum(mask: nil)
        let spectrum = counts.map { Double($0) }
        let beam = loaded.metadata.beamEnergyKeV ?? 200
        let first = try ElementProposer().propose(counts: spectrum, axis: loaded.energyAxis,
                                                  settings: FitSettings.standard(elements: [], axis: loaded.energyAxis, resolutionMnKaEV: 130, beamEnergy: beam))
        print("AUTOID \(file.name) file axis: proposed \(first.proposed.map(\.element)) | \(Self.line(first))")
        // The apps' refinement: the first proposal's K picks at or above 3 L_D spanning 3 keV, fitted by the pooled quantifier.
        var result = first
        let k = first.proposed.filter { XRayLines.line($0.group)?.family == .K && $0.significance >= 3 }
        if k.count >= 2, let lo = k.map(\.energyKeV).min(), let hi = k.map(\.energyKeV).max(), hi - lo >= 3 {
            var m = QuantificationMethod()
            m.elements = k.map { QuantificationMethod.ElementState(symbol: $0.element, role: .quantify, isManual: false) }
            m.beamEnergyKeV = beam
            let input = PooledQuantificationInput(counts: counts, axis: loaded.energyAxis, method: m, metadata: loaded.metadata, regionName: "Whole map", pixelCount: 1)
            let fit = try PooledQuantifier.run(input, tables: QuantificationTables.bundled())
            if let r = fit.refinement, fit.usedAxis == r.refinedAxis {
                let s = FitSettings.standard(elements: [], axis: r.refinedAxis, resolutionMnKaEV: r.resolutionMnKaEV, beamEnergy: beam)
                result = try ElementProposer().propose(counts: spectrum, axis: r.refinedAxis, settings: s)
                print("AUTOID \(file.name) refined on \(k.map(\.element)) (\(String(format: "%+.1f eV, %+.3f %%, %.0f eV", r.offsetShiftEV, r.gainShift * 100, r.resolutionMnKaEV))): proposed \(result.proposed.map(\.element)) | \(Self.line(result))")
            }
        }
        for n in result.notes where n.hasPrefix("Background check") { print("AUTOID \(file.name) \(n)") }
        print("AUTOID \(file.name) in \(String(format: "%.0f", Date().timeIntervalSince(t0))) s; notes: \(result.notes.joined(separator: " | ").prefix(1500))")
        let proposed = Set(result.proposed.map(\.element))
        #expect(file.truth.isSubset(of: proposed), "missing \(file.truth.subtracting(proposed).sorted())")
        #expect(proposed.isSubset(of: file.truth.union(file.allowed)), "extra \(proposed.subtracting(file.truth.union(file.allowed)).sorted())")
    }
}
