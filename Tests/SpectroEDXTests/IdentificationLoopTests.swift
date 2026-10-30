//
//  IdentificationLoopTests.swift
//  Role: the identification loop of docs/design/auto-id-tem.md (the residual-peak loop with the 1 % model term) on planted spectra, its
//        filter and statistic, and its thresholds as named values. The planted pair is the case that hid Mg on a measured Al-alloy map:
//        Mg Kα at 2 % of Al Kα beside an Al whose lines are 5 % narrower than the model fits them (a core misfit like the real detector's).
//

import Foundation
import Testing
import SpectroCore
@testable import SpectroEDX

struct IdentificationLoopTests {

    private static let axis = EnergyAxis(offset: 0, scale: 0.005, size: 4000)   // 0 to 20 keV, like the measured files
    private static let energies = (0..<axis.size).map { axis.energy(ofChannel: $0) }

    /// The planted lines are 5 % narrower than the model fits them at every energy (Al Kα: 66 against 70 eV, as 124 against 130 eV at Mn Kα
    /// gives there; a constant 6 eV at Mn Kα would make O Kα 25 % narrower, which no refined detector shows), with the NIST EPQ Kβ weights
    /// the identification fit uses.
    private static func lines(_ id: String) -> [FitLine] {
        EDSLineModel.build(elements: [String(id.prefix { $0 != "_" })], axis: axis, beamEnergy: 200, resolutionMnKaEV: 130, lineWeights: .epqK)
            .groups.first { $0.id == id }!.lines.map { FitLine(id: $0.id, energy: $0.energy, weight: $0.weight, fwhm: 0.95 * $0.fwhm) }
    }

    /// Continuum like a thin Al foil at 200 kV, plus the lines; Poisson-free (the question is the model, not the noise).
    private static func spectrum(areas: [String: Double]) -> [Double] {
        var out = energies.map { e in e >= 0.2 ? 400 * max(20 - e, 0) / max(e, 0.05) * exp(-pow(0.30 / max(e, 0.05), 3)) * 0.02 + 2 : 0 }
        for (id, area) in areas {
            let col = EDSLineModel.column(of: lines(id), energies: energies, scale: axis.scale)
            for i in out.indices { out[i] += area * col[i] }
        }
        return out
    }

    private static func propose(_ counts: [Double]) throws -> ProposalResult {
        let settings = FitSettings.standard(elements: [], axis: axis, resolutionMnKaEV: 130, beamEnergy: 200)
        return try ElementProposer().propose(counts: counts, axis: axis, settings: settings)
    }

    private static let alloy: [String: Double] = ["Al_Ka": 6_000_000, "Mg_Ka": 120_000, "Si_Ka": 100_000, "Cu_Ka": 250_000, "O_Ka": 80_000]

    @Test func testMgAtTwoPercentBesideAMisfitAlIsProposed() throws {
        let r = try Self.propose(Self.spectrum(areas: Self.alloy))
        let mg = try #require(r.candidates.first { $0.element == "Mg" })
        #expect(mg.isProposed, "Mg at 2 % of Al reads \(Int(mg.net)) against L_D \(Int(mg.detectionLimit)): \(mg.possibleReason ?? mg.familyNote ?? "-")")
        #expect(abs(mg.net / 120_000 - 1) < 0.25, "Mg net \(mg.net) vs planted 120 000")
        #expect(Set(r.proposed.map(\.element)) == ["Al", "Mg", "Si", "Cu", "O"], "proposed \(r.proposed.map(\.element))")
    }

    @Test func testTheSameSpectrumWithoutMgProposesNoMg() throws {
        var areas = Self.alloy
        areas["Mg_Ka"] = nil
        let r = try Self.propose(Self.spectrum(areas: areas))
        #expect(!r.proposed.contains { $0.element == "Mg" }, "Mg proposed on an Al-only spectrum: \(r.candidates.first { $0.element == "Mg" }.map { "net \(Int($0.net)) L_D \(Int($0.detectionLimit))" } ?? "")")
        #expect(Set(r.proposed.map(\.element)) == ["Al", "Si", "Cu", "O"], "proposed \(r.proposed.map(\.element))")
    }

    @Test func testNoCandidateCarriesAMisfitFactor() throws {
        let r = try Self.propose(Self.spectrum(areas: Self.alloy))
        #expect(r.candidates.allSatisfy { $0.misfit == 1 })
    }

    // MARK: the filter and the statistic

    @Test func testTopHatFiltersAStraightLineToZero() {
        let n = 400
        let y = (0..<n).map { 50 + 0.3 * Double($0) }
        let f = IdentificationLoop.topHat(y, variance: y, widths: [Int](repeating: 7, count: n))
        for i in 20..<(n - 20) { #expect(abs(f.filtered[i]) < 1e-9, "channel \(i): \(f.filtered[i])") }
        // The noise of a filtered channel: sqrt(sum k^2 var) with k = 1/7 on 7 channels and -1/8 on 4 + 4.
        let expected = (7 * pow(1.0 / 7, 2) * y[200] + 8 * pow(1.0 / 8, 2) * y[200]).squareRoot()
        #expect(abs(f.sigma[200] / expected - 1) < 0.01, "\(f.sigma[200]) vs \(expected)")
    }

    @Test func testTopHatFindsAGaussianAtItsCentre() {
        let n = 400
        let y = (0..<n).map { i in 100 + 5000 * exp(-0.5 * pow((Double(i) - 200) / 3, 2)) }
        let f = IdentificationLoop.topHat(y, variance: y, widths: [Int](repeating: 7, count: n))
        let peak = f.filtered.indices.max { f.filtered[$0] < f.filtered[$1] }
        #expect(peak == 200)
    }

    @Test func testStatisticHasTheRelativeModelTerm() {
        // (110 - 100)^2 / (100 + (0.01 * 100)^2) = 100 / 101; a perfect model is 0.
        #expect(abs(IdentificationLoop.chiSquared(y: [110], mu: [100], relative: 0.01) - 100.0 / 101) < 1e-12)
        #expect(IdentificationLoop.chiSquared(y: [5, 7, 9], mu: [5, 7, 9], relative: 0.01) == 0)
        // At a million counts the model term dominates: a 1 % misfit costs about 1, not 100.
        let big = IdentificationLoop.chiSquared(y: [1_010_000], mu: [1_000_000], relative: 0.01)
        #expect(abs(big - 1e8 / (1e6 + 1e8)) < 1e-9)
    }

    // MARK: the thresholds, as published

    @Test func testThresholdsAreTheDocumentedDefaults() {
        let t = IdentificationThresholds.default
        #expect(t.peakSigma == 5)
        #expect(t.lowEnergyFactor == 1.5 && t.lowEnergyBelowKeV == 1)
        #expect(t.candidateWindowSigma == 2.5 && t.candidateWindowKeV == 0.025)
        #expect(t.minimumLineWeight == 0.1)
        #expect(t.confirmationSigma == 3)
        #expect(t.minimumGain == 100)
        #expect(t.minimumLocalShare == 0.2)
        #expect(t.contradictionGain == 9 && t.contradictionShare == 0.05)
        #expect(t.ambiguityGain == 30)
        #expect(t.pruneGain == 100)
        #expect(t.siliconArtefactFraction == 0.002)
        #expect(t.maximumPeaks == 30 && t.maximumNewElements == 10)
        #expect(t.relativeModelTerm == 0.01)
        #expect(ProposerPolicy.default.thresholds == t)
    }

    // MARK: the line weights of the identification fit

    @Test func testIdentificationFitUsesEPQKBetaWeights() {
        func kb(_ el: String, _ w: EDSLineWeights) -> Double? {
            EDSLineModel.build(elements: [el], axis: Self.axis, beamEnergy: 200, resolutionMnKaEV: 130, lineWeights: w)
                .groups.first { $0.id == "\(el)_Ka" }?.lines.first { $0.id == "\(el)_Kb" }?.weight
        }
        // eXSpy's table for the quantification fit (parity), NIST EPQ (K-M2 + K-M3 over K-L2 + K-L3) for identification:
        // Al 0.0474 / 1.505 = 0.0315, measured 0.031 and 0.034 on two measured Al-alloy map sums.
        #expect(kb("Al", .exspy) == 0.0132)
        #expect(abs((kb("Al", .epqK) ?? 0) - 0.0474 / 1.505) < 1e-4)
        #expect(abs((kb("Cu", .epqK) ?? 0) - 0.2417 / 1.653) < 1e-3)
        #expect(abs((kb("Mg", .epqK) ?? 0) - 0.0262 / 1.507) < 1e-4)
    }
}
