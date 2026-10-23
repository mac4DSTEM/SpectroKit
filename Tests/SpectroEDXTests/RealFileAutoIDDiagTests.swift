//
//  RealFileAutoIDDiagTests.swift
//  Role: opt-in diagnostic on the owner's three labelled spectrum images (SPECTRO_REAL_DATA=1 and the files under $MACEM_DATA/stem-edx):
//        what the proposer, the shipped rules and the axis refinement say about the true elements, so a miss can be read as numbers.
//        Prints only; never part of the gate. The files stay out of the repo.
//

import Foundation
import Testing
import SpectroCore
import SpectroEDX

struct RealFileAutoIDDiagTests {
    private static let base = (ProcessInfo.processInfo.environment["MACEM_DATA"] ?? NSHomeDirectory() + "/GitHub/mac4DSTEM_Organization/data") + "/stem-edx/"
    private static let files: [(name: String, truth: [String])] = [
        ("SI HAADF 1339 65000 x 20260508.emd", ["Al", "Mg", "Si"]),
        ("SI HAADF 1456 77000 x 20260420.emd", ["O", "Si", "Ni", "Ge", "Pt"]),
    ]

    private func n(_ x: Double) -> String { x.isFinite ? String(Int(x.rounded())) : "nan" }

    private func describe(_ tag: String, _ r: ProposalResult, truth: [String], resolution: Double) {
        for e in truth {
            guard let c = r.candidates.first(where: { $0.element == e }) else { print("DIAG \(tag) \(e): no candidate"); continue }
            let state = c.isProposed ? "PROPOSED" : (c.familyNote != nil ? "withheld" : (c.aboveCriticalLevel ? "possible" : "below L_C"))
            print("DIAG \(tag) \(e) \(c.group) net \(n(c.net)) L_D \(n(c.detectionLimit)) sigma0 \(n(c.sigmaZero)) misfit x\(String(format: "%.1f", c.misfit)) \(state) conflicts \(c.conflicts.map(\.id)) sumQ \(c.hasSumPeakQuestion)")
        }
        let ruled = ProposalRules.shipped.apply(r, resolutionMnKaEV: resolution)
        print("DIAG \(tag) proposed \(r.proposed.map(\.element)) | rules: picks \(ruled.picks.map(\.element)) held \(ruled.heldQuestions.map { "\($0.element):\($0.conflicts.map(\.id))" }) withheld \(ruled.withheld.map { "\($0.candidate.element) (\($0.rule.rawValue))" }) family \(ruled.familyWithheld.map(\.element))")
        for note in r.notes where note.contains("misfit factor") || note.contains("Settled again") || note.hasPrefix("The surviving") { print("DIAG \(tag) note: \(note.prefix(260))") }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["SPECTRO_REAL_DATA"] == "1", "set SPECTRO_REAL_DATA=1 with the owner's files"))
    func diagnoseTheMisses() throws {
        for file in Self.files {
            let path = Self.base + file.name
            guard FileManager.default.fileExists(atPath: path) else { print("DIAG absent: \(path)"); continue }
            let t0 = Date()
            let loaded = try SpectrumImageOpener.open(path: path, kind: .veloxSpectrumImage)
            let counts = loaded.sum(mask: nil)
            let spectrum = counts.map { Double($0) }
            let axis = loaded.energyAxis, beam = loaded.metadata.beamEnergyKeV ?? 200
            print("DIAG ==== \(file.name): \(loaded.nx) x \(loaded.ny), \(Int(spectrum.reduce(0, +))) counts, beam \(beam) keV, opened in \(String(format: "%.0f", Date().timeIntervalSince(t0))) s")
            let settings = FitSettings.standard(elements: [], axis: axis, resolutionMnKaEV: 130, beamEnergy: beam)
            let first = try ElementProposer().propose(counts: spectrum, axis: axis, settings: settings)
            describe("file-axis", first, truth: file.truth, resolution: 130)

            // The room's refinement: the first proposal's K picks at or above 3 L_D spanning 3 keV, fitted by the pooled quantifier.
            let k = first.proposed.filter { XRayLines.line($0.group)?.family == .K && $0.significance >= 3 }
            if k.count >= 2, let lo = k.map(\.energyKeV).min(), let hi = k.map(\.energyKeV).max(), hi - lo >= 3 {
                var m = QuantificationMethod()
                m.elements = k.map { QuantificationMethod.ElementState(symbol: $0.element, role: .quantify, isManual: false) }
                m.beamEnergyKeV = beam
                let input = PooledQuantificationInput(counts: counts, axis: axis, method: m, metadata: loaded.metadata, regionName: "Whole map", pixelCount: 1)
                do {
                    let fit = try PooledQuantifier.run(input, tables: QuantificationTables.bundled())
                    if let r = fit.refinement {
                        print("DIAG refinement on \(k.map(\.element)): offset \(String(format: "%+.1f", r.offsetShiftEV)) eV, gain \(String(format: "%+.3f", r.gainShift * 100)) %, FWHM \(String(format: "%.0f", r.resolutionMnKaEV)) eV, used \(fit.usedAxis == r.refinedAxis); warnings \(fit.warnings)")
                        if fit.usedAxis == r.refinedAxis {
                            let s2 = FitSettings.standard(elements: [], axis: r.refinedAxis, resolutionMnKaEV: r.resolutionMnKaEV, beamEnergy: beam)
                            let second = try ElementProposer().propose(counts: spectrum, axis: r.refinedAxis, settings: s2)
                            describe("refined-axis", second, truth: file.truth, resolution: r.resolutionMnKaEV)
                            // Where the misfit beside Mg sits: the residual of the listed fit (the room's picks plus Mg) in 20 eV steps from 1.10 to 1.90 keV.
                            if file.truth.contains("Mg") {
                                let sl = FitSettings.standard(elements: ["Al", "Mg", "Si", "Cu", "O", "Zr", "Fe"], axis: r.refinedAxis, resolutionMnKaEV: r.resolutionMnKaEV, beamEnergy: beam)
                                let fit = try EDSFit.run(counts: spectrum, axis: r.refinedAxis, settings: sl, computeCovariance: false)
                                let first = fit.channels.lowerBound
                                var line = "DIAG residual 1339 (keV: data model z):"
                                var e = 1.10
                                while e < 1.90 {
                                    var d = 0.0, m = 0.0
                                    for ch in fit.channels { let x = r.refinedAxis.energy(ofChannel: ch); if x >= e && x < e + 0.02 { d += spectrum[ch]; m += fit.model[ch - first] } }
                                    line += String(format: " %.2f:%.0f/%.0f/%+.0f", e, d, m, (d - m) / max(m, 1).squareRoot())
                                    e += 0.02
                                }
                                print(line)
                                print("DIAG listed fit: chi2 \(String(format: "%.1f", fit.pearsonReducedChiSquared)) groups \(fit.groupIDs) values \(fit.values.map { Int($0) })")
                            }
                            // The measured Hypermet tail on the strong lines, then the proposal with it (the line shape the Gaussian lacks).
                            do {
                                let strong = second.proposed.filter { XRayLines.line($0.group)?.family == .K && $0.significance >= 10 }.map(\.element)
                                let sm = FitSettings.standard(elements: strong, axis: r.refinedAxis, resolutionMnKaEV: r.resolutionMnKaEV, beamEnergy: beam)
                                let m = try TailEstimate.measure(counts: spectrum, axis: r.refinedAxis, settings: sm, elements: strong)
                                print("DIAG tail measured on \(strong): f \(String(format: "%.3f", m.tail.fraction)) beta \(String(format: "%.2f", m.tail.slopeKeV)) keV, residual \(String(format: "%.3g", m.residualNormWithout)) -> \(String(format: "%.3g", m.residualNorm))")
                                var s3 = s2; s3.lineTail = m.tail
                                let third = try ElementProposer().propose(counts: spectrum, axis: r.refinedAxis, settings: s3)
                                describe("refined-tail", third, truth: file.truth, resolution: r.resolutionMnKaEV)
                            } catch { print("DIAG tail: \(error)") }
                        }
                    } else { print("DIAG refinement: none (warnings \(fit.warnings))") }
                } catch { print("DIAG refinement: pooled fit threw \(error)") }
            } else { print("DIAG refinement: no anchors (K picks \(k.map(\.element)))") }
            if let u = try? ElementProposer(policy: ProposerPolicy(flankScaling: false)).propose(counts: spectrum, axis: axis, settings: settings) {
                describe("file-unscaled", u, truth: file.truth, resolution: 130)
            } else { print("DIAG file-unscaled: refused (rank deficient)") }
        }
    }
}
