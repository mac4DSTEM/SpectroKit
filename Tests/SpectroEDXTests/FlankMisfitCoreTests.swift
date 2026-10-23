//
//  FlankMisfitCoreTests.swift
//  Role: the flank-misfit factor measures continuum misfit, not a fitted neighbour's own peak shape. Planted, noise-free spectra whose
//        lines are 6 eV narrower than the model fits them (a core misfit like the real detector's): Mg Kα at 2 % of Al Kα beside such an
//        Al must be proposed (known red: a line-model item, see the test). Registered 2026-10-23 on the owner's file 1339, where Mg read
//        112 557 counts against a limit scaled ×32.8 by Al Kα's shape misfit (Al Kβ under-modelled, the continuum above the Al edge too
//        high) while Mg's own window fitted to ±3 σ. An Al-only guard joins it with the model fix.
//

import Foundation
import Testing
import SpectroCore
import SpectroEDX

struct FlankMisfitCoreTests {

    private static let axis = EnergyAxis(offset: 0, scale: 0.005, size: 4000)   // 0 to 20 keV, like the owner's files
    private static let energies = (0..<axis.size).map { axis.energy(ofChannel: $0) }
    /// No tail: on 1339 the measured tail is nil (f 0.000 on the refined axis); the misfit is the line core and the continuum beside it.
    private static let tail: LineTail? = nil

    /// The planted lines are 6 eV narrower than the model fits them (124 against 130 eV at Mn Kα): the real detector's peak is not the model's
    /// Gaussian either, and on 1339 the Al Kα core misfit is what the flank bins beside Mg see (χ²ᵣ 31 after the width refinement).
    private static func lines(_ id: String) -> [FitLine] {
        EDSLineModel.build(elements: [String(id.prefix { $0 != "_" })], axis: axis, beamEnergy: 200, resolutionMnKaEV: 124)
            .groups.first { $0.id == id }!.lines
    }

    /// Continuum like a thin Al foil at 200 kV, plus the lines with the tail; Poisson-free (the question is the model, not the noise).
    private static func spectrum(areas: [String: Double]) -> [Double] {
        var out = energies.map { e in e >= 0.2 ? 400 * max(20 - e, 0) / max(e, 0.05) * exp(-pow(0.30 / max(e, 0.05), 3)) * 0.02 + 2 : 0 }
        for (id, area) in areas {
            let col = EDSLineModel.column(of: lines(id), energies: energies, scale: axis.scale, tail: tail)
            for i in out.indices { out[i] += area * col[i] }
        }
        return out
    }

    private static func propose(_ counts: [Double]) throws -> ProposalResult {
        let settings = FitSettings.standard(elements: [], axis: axis, resolutionMnKaEV: 130, beamEnergy: 200)
        return try ElementProposer().propose(counts: counts, axis: axis, settings: settings)
    }

    @Test func testMgAtTwoPercentBesideAMisfitAlIsProposed() throws {
        let r = try Self.propose(Self.spectrum(areas: ["Al_Ka": 6_000_000, "Mg_Ka": 120_000, "Si_Ka": 100_000, "Cu_Ka": 250_000, "O_Ka": 80_000]))
        let mg = try #require(r.candidates.first { $0.element == "Mg" })
        print("FLANKCORE Mg beside Al: net \(Int(mg.net)) L_D \(Int(mg.detectionLimit)) sigma0 \(Int(mg.sigmaZero)) misfit x\(String(format: "%.1f", mg.misfit)) proposed \(mg.isProposed); proposed \(r.proposed.map(\.element))")
        // Known red (2026-10-23): the Al core misfit scales Mg's σ₀ about 180 times; leaving the fitted cores out of the flank bins made it worse
        // (×288, and rank-deficient fits), and a measured tail is nil on the real file. The fix is the line model at Al (Kβ and the continuum
        // above the Al edge), not the proposer's statistics; this stays registered until then.
        withKnownIssue("Mg beside a misfit Al: the limit is the neighbour's shape misfit, a line-model item") {
            #expect(mg.isProposed, "Mg at 2 % of Al reads \(Int(mg.net)) against L_D \(Int(mg.detectionLimit)) (misfit x\(mg.misfit))")
            #expect(abs(mg.net / 120_000 - 1) < 0.25, "Mg net \(mg.net) vs planted 120 000")
        }
    }
}
