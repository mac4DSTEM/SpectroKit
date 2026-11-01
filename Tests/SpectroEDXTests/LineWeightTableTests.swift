//
//  LineWeightTableTests.swift
//  Role: The opt-in NIST EPQ line-weight table of the spectrum fit (`EDSLineWeights.epq`, `FitPolicy.lineWeights`) next to
//        eXSpy's (the default, the parity path), on PLANTED TRUTH ON SYNTHETIC DATA: a noise-free Al film generated here with its
//        K-beta lines planted at either table (EPQ by default), and the demo absorption-truth pool re-planted at EPQ's K-beta.
//
//  Why: eXSpy ties Al K-beta at 0.0132 of K-alpha, NIST EPQ at 0.0315. On the public Leeds pure-Al wedge (Snelson, Collins,
//  MacArthur; DOI 10.5518/1826; CC BY 4.0) the EPQ tie lowers chi2/n over 0.8-2.6 keV from 3.15 to 2.51 and the data excess at
//  1.53-1.65 keV from +893 to -228 counts. A fit tied at one table on a spectrum planted at the other misreads a weak line beside
//  Al K-alpha by tens of percent, so the table is a choice the footer names.
//

import Foundation
import Testing
import SpectroCore
@testable import SpectroEDX

struct LineWeightTableTests {

    // MARK: the table and the policy

    @Test func epqIsTheEPQTableAndEncodesAsEpq() throws {
        #expect(EDSLineWeights.epq == .epqK)
        #expect(EDSLineWeights.epq.rawValue == "epq" && EDSLineWeights.exspy.rawValue == "exspy")
        #expect(try JSONDecoder().decode(EDSLineWeights.self, from: Data("\"epq\"".utf8)) == .epq)
    }

    @Test func theDefaultStaysExspyAndTheModelTiesEachTable() {
        #expect(FitPolicy.default.lineWeights == .exspy)
        #expect(FitPolicy.exspyEquivalent.lineWeights == .exspy)
        let axis = EnergyAxis(offset: 0, scale: 0.005, size: 4000)
        #expect(FitSettings.standard(elements: ["Al"], axis: axis, resolutionMnKaEV: 128, beamEnergy: 200).lineWeights == .exspy)
        #expect(FitSettings.standard(elements: ["Al"], axis: axis, resolutionMnKaEV: 128, beamEnergy: 200,
                                     policy: FitPolicy(lineWeights: .epq)).lineWeights == .epq)
        func kb(_ el: String, _ t: EDSLineWeights) -> Double? {
            EDSLineModel.build(elements: [el], axis: axis, beamEnergy: 200, resolutionMnKaEV: 128, lineWeights: t)
                .groups.first { $0.id == el + "_Ka" }?.lines.first { $0.id == el + "_Kb" }?.weight
        }
        #expect(kb("Al", .exspy) == 0.0132)                       // eXSpy xray_lines.json, unchanged (parity)
        #expect(abs((kb("Al", .epq) ?? 0) - 0.0474 / 1.505) < 1e-12)   // EPQ K-M3 + K-M2 + ... over K-L3 + K-L2
        #expect(abs((kb("Mg", .epq) ?? 0) - 0.017386) < 1e-5)
        #expect(abs((kb("Si", .epq) ?? 0) - 0.057143) < 1e-5)
    }

    @Test func aNonDefaultTableIsNamedInTheFooterAndOldPoliciesReadExspy() throws {
        let epq = QuantificationPolicy(fit: FitPolicy(lineWeights: .epq))
        #expect(QuantificationPolicy.default.footerLine == nil)
        #expect(epq.footerLine == "policy (non-default): fit.lineWeights = epq", "\(epq.footerLine ?? "nil")")
        #expect(epq.canonicalJSON.contains("\"lineWeights\":\"epq\""))
        #expect(try JSONDecoder().decode(QuantificationPolicy.self, from: Data(epq.canonicalJSON.utf8)) == epq)
        // A policy stored before the field existed reads eXSpy's table, the one it was run with.
        var json = try JSONSerialization.jsonObject(with: Data(QuantificationPolicy.default.canonicalJSON.utf8)) as! [String: Any]
        var fit = json["fit"] as! [String: Any]
        fit["lineWeights"] = nil
        json["fit"] = fit
        let old = try JSONDecoder().decode(QuantificationPolicy.self, from: try JSONSerialization.data(withJSONObject: json))
        #expect(old == .default)
    }

    // MARK: a synthetic Al film, K-beta planted at either table

    private static let axis = EnergyAxis(offset: 0, scale: 0.005, size: 4000)
    private static let energies = (0..<axis.size).map { axis.energy(ofChannel: $0) }
    private static let resolution = 128.0

    /// Kramers continuum through 9e-5 g/cm2 of Al (FFAST mu/rho), convolved with the detector's Gaussian (the generator of
    /// `ContinuumEdgeBroadeningTests`).
    private static let continuum: [Double] = {
        let raw = energies.map { e -> Double in
            guard e >= 0.1 else { return 0 }
            let mu = (try? MassAbsorptionTable.bundled!.mac(element: "Al", energyKeV: e)) ?? 0
            return 9.0 * (200 - e) / e * exp(-pow(0.35 / e, 2.2)) * exp(-9e-5 * mu)
        }
        return energies.indices.map { i in
            let e = energies[i]
            let sigma = (XRayLines.fwhm(resolutionMnKaEV: resolution, atEnergy: max(e, 0.3)) ?? resolution / 1000) / (8 * log(2.0)).squareRoot()
            let reach = Int((5 * sigma / axis.scale).rounded(.up))
            var sum = 0.0, ws = 0.0
            for j in max(0, i - reach)...min(axis.size - 1, i + reach) {
                let w = exp(-0.5 * pow((energies[j] - e) / sigma, 2)); sum += w * raw[j]; ws += w
            }
            return sum / ws
        }
    }()

    /// Al K 3e5 counts, Si K and Mg K 2e3 each (K-alpha areas), every K-beta planted at `planted` (default the physical EPQ weights).
    private static func film(planted: EDSLineWeights = .epq) -> [Double] {
        func column(_ el: String) -> [Double] {
            let g = EDSLineModel.build(elements: [el], axis: axis, beamEnergy: 200, resolutionMnKaEV: resolution, lineWeights: planted)
                .groups.first { $0.id == el + "_Ka" }!
            return EDSLineModel.column(of: g.lines, energies: energies, scale: axis.scale)
        }
        let al = column("Al"), si = column("Si"), mg = column("Mg")
        return energies.indices.map { continuum[$0] + 3e5 * al[$0] + 2e3 * si[$0] + 2e3 * mg[$0] }
    }

    private static func siBias(_ counts: [Double], fit table: EDSLineWeights) throws -> (si: Double, al: Double) {
        let s = FitSettings.standard(elements: ["Al", "Si", "Mg"], axis: axis, resolutionMnKaEV: resolution, beamEnergy: 200,
                                     policy: FitPolicy(lineWeights: table))
        let f = try EDSFit.run(counts: counts, axis: axis, settings: s, computeCovariance: false)
        return (f.values[f.groupIDs.firstIndex(of: "Si_Ka")!] / 2e3 - 1, f.values[f.groupIDs.firstIndex(of: "Al_Ka")!] / 3e5 - 1)
    }

    /// Red before `FitPolicy.lineWeights` reached the fit: the fit tied eXSpy's 0.0132 whatever the policy, and read Si K-alpha
    /// -43.6 % on the film planted at EPQ's weights. Tied at the planted table the fit reads the same -25.4 to -25.8 % on either film
    /// (the broadened-edge bias of this film, `ContinuumEdgeBroadeningTests`), so what is left is not the K-beta.
    @Test func theFitTiedAtThePlantedTableReadsAWeakSiLineAsWellOnEitherFilm() throws {
        let onEPQ = try Self.siBias(Self.film(), fit: .epq)
        let mismatched = try Self.siBias(Self.film(), fit: .exspy)
        let onExspy = try Self.siBias(Self.film(planted: .exspy), fit: .exspy)
        FileHandle.standardError.write(Data(String(format: "KBETA film: EPQ-planted fit epq Si %+.4f (Al %+.5f), fit exspy %+.4f (Al %+.5f); exspy-planted fit exspy %+.4f\n",
                                                   onEPQ.si, onEPQ.al, mismatched.si, mismatched.al, onExspy.si).utf8))
        #expect(abs(onEPQ.si - onExspy.si) < 0.01, "matched ties: \(onEPQ.si) vs \(onExspy.si)")
        #expect(mismatched.si < -0.40, "the eXSpy tie on an EPQ film: \(mismatched.si)")
        // Al K-alpha: -0.09 % tied at the planted table, -0.91 % with the eXSpy tie (the missing K-beta area moves into the continuum).
        #expect(abs(onEPQ.al) < 0.003 && mismatched.al < -0.006, "Al K-alpha: \(onEPQ.al) vs \(mismatched.al)")
    }

    // MARK: the demo absorption-truth pool, K-beta re-planted at EPQ's weights

    /// The pool's noise-free expected spectrum plus (w_EPQ - w_eXSpy) x the K-alpha area of Al, Mg and Si in a Gaussian at each
    /// K-beta, Cu included (the generator planted eXSpy's weights; the areas are the noise-free default fit's, within 1 % of the
    /// planted ones; no K-beta here is above the Si K edge but Cu's, whose escape copy is not re-planted: 1 % of a weak line).
    private static func replantedAtEPQ(_ c: DemoEDXPoolTests.Case) throws -> DemoEDXPoolTests.Case {
        let base = try PooledQuantifier.run(DemoEDXPoolTests.input(c, noiseFree: true), tables: DemoEDXPoolTests.tables)
        let e = (0..<c.axis.size).map { c.axis.energy(ofChannel: $0) }
        var extra = [Double](repeating: 0, count: e.count)
        for el in ["Al", "Mg", "Si", "Cu"] {
            let a = base.fit.values[base.fit.groupIDs.firstIndex(of: el + "_Ka")!] / 100
            let kb = XRayLines.line(el + "_Kb")!
            let w = EPQLineWeights.bundled!.kBetaOverKAlpha(element: el)! - kb.weight
            let col = EDSLineModel.column(of: [FitLine(id: kb.id, energy: kb.energy, weight: w,
                                                       fwhm: XRayLines.fwhm(resolutionMnKaEV: 130, atEnergy: kb.energy)!)],
                                          energies: e, scale: c.axis.scale)
            for i in extra.indices { extra[i] += a * col[i] }
        }
        return DemoEDXPoolTests.Case(name: c.name, axis: c.axis, npix: c.npix, thicknessNm: c.thicknessNm, quantified: c.quantified,
                                     trueK: c.trueK, expected: zip(c.expected, extra).map { $0 + $1 }, counts: nil,
                                     mg: c.mg, si: c.si, cu: c.cu)
    }

    /// The pooled fit with `.epq` on the pool re-planted at EPQ reads Si K-alpha as the default reads the pool as generated
    /// (-1.5 %); the default eXSpy tie on it reads -23 %.
    @Test func thePooledFitWithTheEPQTableRecoversSiOnAPoolPlantedAtEPQ() throws {
        let c = try Self.replantedAtEPQ(DemoEDXPoolTests.named("absorption-truth"))
        let epq = try PooledQuantifier.run(DemoEDXPoolTests.input(c, noiseFree: true, policy: QuantificationPolicy(fit: FitPolicy(lineWeights: .epq))),
                                           tables: DemoEDXPoolTests.tables)
        let ex = try PooledQuantifier.run(DemoEDXPoolTests.input(c, noiseFree: true), tables: DemoEDXPoolTests.tables)
        let siEPQ = DemoEDXPoolTests.net(epq, "Si_Ka") / 100 / c.si - 1, siEx = DemoEDXPoolTests.net(ex, "Si_Ka") / 100 / c.si - 1
        FileHandle.standardError.write(Data(String(format: "KBETA demo absorption-truth at EPQ: fit epq Si %+.4f, fit exspy %+.4f\n", siEPQ, siEx).utf8))
        #expect(abs(siEPQ) < 0.05, "EPQ tie: \(siEPQ)")
        #expect(siEx < -0.15, "eXSpy tie on an EPQ pool: \(siEx)")
        #expect(epq.fitSettings.lineWeights == .epq && ex.fitSettings.lineWeights == .exspy)
        #expect(epq.footerLines.contains { $0.contains("fit.lineWeights = epq") })
        #expect(epq.quality < ex.quality)
    }
}
