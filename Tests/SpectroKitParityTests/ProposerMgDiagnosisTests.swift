//
//  ProposerMgDiagnosisTests.swift
//  Role: The diagnosis of the Mg auto-ID miss, experiments D0 to D5, run in that order against the SHIPPED `ElementProposer`
//        on the planted spectra. D6 (measured files) is not run here.
//
//  These are experiments, not gates: each prints (EDX_GATE_LOG) the observation, the refuting observation stated beforehand and the
//  prediction, and the verdict computed from them. The assertions are the structural facts an experiment rests on
//  (the runs return; the matched control behaves as a control), so a broken proposer or loader still fails them. The method of
//  every number is in the test; the outcomes are in the log it prints.
//

import Foundation
import Testing
import SpectroTestSupport
import SpectroCore
import SpectroEDX

struct ProposerMgDiagnosisTests {

    private func ratio(_ r: MgRun, _ truth: Double) -> Double { truth > 0 ? r.net / truth : .nan }
    private func f(_ x: Double, _ digits: Int = 2) -> String { String(format: "%.\(digits)f", x) }
    private func cell(_ id: String) -> EDXFixtures.Cell { EDXFixtures.cellByID[id]! }

    // MARK: D0 the pool / pruning interplay

    /// D0. The 90 other candidates' collinear columns prune Mg at L_C in the backward step although a single test would pass.
    /// REGISTRATION WORDING: "Refuted if the single-candidate run gives Mg net and a proposal outcome different from the full
    /// pool's by more than 10 % of the net or by a decision" contradicts its own prediction ("the same Mg net in both; D0
    /// refuted"). Read here as: D0 is SUPPORTED if the full pool loses Mg (net lower by more than 10 %, or not proposed) where
    /// the single-candidate test proposes it; equal results refute it. Amendment 2 says so.
    /// Experiment: every cell of M (s, L) and U130 (s, L) with realisations, the noise-free mean and the first ten realisations.
    @Test func testD0PoolPruningInterplay() throws {
        let ids = EDXFixtures.cells.filter { ($0.set == "M" || $0.set == "U130") && $0.nReal > 0 && $0.truth["Mg"]! > 0 }.map(\.id)
        var spectra = 0, decisionDiffers = 0, netDiffers = 0, fullLoses = 0
        var examples: [String] = []
        for id in ids {
            let s = RunStore.shared.single(id), fu = RunStore.shared.full(id, reals: 10)
            let pairs = [(s.mean, fu.mean)] + Array(zip(s.reals.prefix(fu.reals.count), fu.reals))
            for (a, b) in pairs {
                spectra += 1
                let dec = a.proposed != b.proposed
                let net = abs(a.net - b.net) > 0.1 * max(abs(a.net), 1e-9) && !(a.net == 0 && b.net == 0)
                if dec { decisionDiffers += 1 }
                if net { netDiffers += 1 }
                if a.proposed && (!b.proposed || b.net < 0.9 * a.net) { fullLoses += 1 }
                if (dec || net) && examples.count < 6 { examples.append("\(id): single net \(f(a.net, 0)) \(a.proposed), full net \(f(b.net, 0)) \(b.proposed)") }
            }
        }
        gateNote("EDX D0: \(ids.count) cells, \(spectra) spectra (noise-free mean + first 10 realisations): single and full pool differ by a decision in \(decisionDiffers), by more than 10 % of the net in \(netDiffers); full pool loses a Mg the single test proposes in \(fullLoses). \(examples)")
        gateNote("EDX D0 verdict: \(fullLoses == 0 ? "REFUTED (no pruning loss: the full pool and the single-candidate design agree where it matters)" : "SUPPORTED on \(fullLoses) spectra")  [registered prediction: same net in both, D0 refuted: \(netDiffers == 0 && decisionDiffers == 0 ? "met" : "NOT met in \(netDiffers + decisionDiffers) cases")]")
        #expect(spectra > 100)
        // measured outcome guarded (not an upstream bound): the full pool loses Mg on some spectra the single test proposes (9 here)
        #expect(fullLoses >= 1, "D0 measured: pruning by the pool costs Mg on some spectra")
        // the control: on matched, strongly detectable data both designs find Mg
        let ctl = RunStore.shared.full("M.s.N6.rho0p05", reals: 10)
        #expect(ctl.mean.proposed && ctl.reals.allSatisfy(\.proposed), "M.s.N6.rho0p05 is detected by the full pool")
    }

    // MARK: D1 Al Ka width mismatch

    /// D1. Al Ka width mismatch leaks into Mg. Refuted if, on set U (Fano widths, +7 % at Al) at N_Al = 1e7 and rho_Mg = 0.01, the
    /// Swift proposer's Mg net is within +-20 % of the truth AND Mg is proposed in at least 90 % of the realisations.
    /// Predicted: net/truth 0.39 noise-free (0.10 with noise and rho_c = 0.0008), P(proposed) = 0 for rho_Mg <= 0.01, flank factor 20 to 41.
    /// Plus the R_MnKa scan of E4 (the model's resolution against Fano-planted data).
    @Test func testD1AlKaWidthMismatch() throws {
        var refuted = false
        for fam in ["s", "L"] {
            for r in ["U125", "U130", "U140", "U150"] {
                for rho in ["0p01", "0p002"] {
                    let id = "\(r).\(fam).N7.rho\(rho)"
                    guard let c = EDXFixtures.cellByID[id] else { continue }
                    let s = RunStore.shared.single(id)
                    let truth = c.truth["Mg"]!
                    gateNote("EDX D1 \(id): noise-free net/truth \(f(ratio(s.mean, truth))), L_D \(f(s.mean.ld, 0)), flank factor \(f(s.mean.misfit, 1)); " + (s.reals.isEmpty ? "no realisations" : "realisations (n \(s.reals.count)): mean net/truth \(f(s.reals.meanNet / truth)), P(proposed) \(f(s.reals.pProposed))"))
                    if r == "U130" && rho == "0p01" && !s.reals.isEmpty {
                        let within = abs(s.reals.meanNet / truth - 1) <= 0.2
                        if within && s.reals.pProposed >= 0.9 { refuted = true }
                    }
                }
            }
        }
        // E4: the model's R_MnKa against Fano-planted data (U130, N 1e7)
        for (id, label) in [("U130.s.N7.rho0p002", "rho 0.002"), ("U130.s.N7.rho0p01", "rho 0.01")] {
            let c = cell(id), truth = c.truth["Mg"]!
            var row: [String] = []
            for r in stride(from: 120.0, through: 150.0, by: 5.0) {
                let m = PlantedRuns.run(EDXFixtures.meanSpectrum(c), resolution: r)
                row.append("R\(Int(r)): \(f(ratio(m, truth))) (x\(f(m.misfit, 1)))")
            }
            gateNote("EDX D1 R scan (\(label), U130 s, N 1e7, noise-free, net/truth (flank factor)): " + row.joined(separator: ", "))
        }
        let m = RunStore.shared.single("M.s.N7.rho0p01")
        #expect(ratio(m.mean, 100_000) > 0.7, "control: matched widths keep Mg at rho 0.01")
        let u = RunStore.shared.single("U130.s.N7.rho0p01")
        #expect(ratio(u.mean, 100_000) < ratio(m.mean, 100_000), "Fano widths lose Mg relative to matched widths")
        gateNote("EDX D1 verdict: \(refuted ? "REFUTED (U130 s N 1e7 rho 0.01 keeps Mg within 20 % and proposes it in >= 90 %)" : "NOT refuted: at U130 s N 1e7 rho 0.01 Mg net/truth is \(f(ratio(u.reals.isEmpty ? u.mean : MgRun(net: u.reals.meanNet, sigma: 0, sigmaZero: 0, lc: 0, ld: 0, misfit: 0, proposed: false, other: [], present: true), 100_000))) and P(proposed) \(f(u.reals.pProposed))")")
    }

    // MARK: D2 axis error

    private func refineThenPropose(_ counts: [Double], elements: [String], useRefinedResolution: Bool) -> MgRun? {
        var settings = FitSettings.standard(elements: elements, axis: EDXFixtures.axis, resolutionMnKaEV: 130, beamEnergy: 200)
        settings.fitFrom = 0.3; settings.fitTo = 3.0
        guard let res = try? EnergyAxisRefinement.refine(counts: counts, fileAxis: EDXFixtures.axis, fileResolutionMnKaEV: 130, settings: settings) else { return nil }
        return PlantedRuns.run(counts, resolution: useRefinedResolution ? res.resolutionMnKaEV : 130, axis: res.refinedAxis)
    }

    /// D2. Axis error: offset, gain, or the half channel. Refuted if on set S a shift of +-3 eV leaves Mg net within +-20 % of the
    /// truth. Predicted: net/truth 0.54 at +3 eV, 0.15 at +5, 0 at +-10 (rho_Mg = 0.01, noise-free, surrogate); after refinement the
    /// planted cells recover to within +-30 % of the truth for N_Al >= 1e6 on set M's widths and stay biased on set U.
    @Test func testD2AxisError() throws {
        let surrogate: [String: Double] = ["S+1": 0.87, "S+2": 0.71, "S+3": 0.54, "S+5": 0.15, "S+10": 0, "S-10": 0]
        var refutedAt3 = false
        for rho in ["0p01", "0p002"] {
            var line: [String] = []
            for name in ["M", "S-10", "S-5", "S-3", "S-2", "S-1", "S+1", "S+2", "S+3", "S+5", "S+10", "HALF"] {
                let id = "\(name).s.N7.rho\(rho)"
                guard let c = EDXFixtures.cellByID[id] else { continue }
                let s = RunStore.shared.single(id)
                let q = ratio(s.mean, c.truth["Mg"]!)
                line.append("\(name): \(f(q))" + (rho == "0p01" ? (surrogate[name].map { " [surrogate \($0)]" } ?? "") : ""))
                if rho == "0p01" && (name == "S+3" || name == "S-3") && abs(q - 1) <= 0.2 { refutedAt3 = true }
            }
            gateNote("EDX D2 rho \(rho) N 1e7 family s, noise-free net/truth: " + line.joined(separator: ", "))
        }
        // realisations: P(proposed) and mean net/truth at N 1e7, rho 0.01
        for name in ["M", "S-5", "S-3", "S-1", "S+1", "S+3", "S+5", "HALF"] {
            let id = "\(name).s.N7.rho0p01"
            guard let s = Optional(RunStore.shared.single(id)), !s.reals.isEmpty else { continue }
            gateNote("EDX D2 \(id) (n \(s.reals.count)): mean net/truth \(f(s.reals.meanNet / 100_000)), P(proposed) \(f(s.reals.pProposed))")
        }
        // refine first, propose second (noise-free mean and the first three realisations)
        for name in ["M", "S-10", "S-5", "S-3", "S+1", "S+3", "S+5", "S+10", "HALF", "U130"] {
            for n in ["N6", "N7"] {
                let id = "\(name).s.\(n).rho0p01"
                guard let c = EDXFixtures.cellByID[id] else { continue }
                let truth = c.truth["Mg"]!
                let before = RunStore.shared.single(id)
                var parts: [String] = ["file axis \(f(ratio(before.mean, truth)))"]
                for (label, elements, refR) in [("refine(Al,Si)", ["Al", "Si"], false), ("refine(Mg,Al,Si)", ["Mg", "Al", "Si"], false), ("refine(Mg,Al,Si)+R", ["Mg", "Al", "Si"], true)] {
                    guard let m = refineThenPropose(EDXFixtures.meanSpectrum(c), elements: elements, useRefinedResolution: refR) else { parts.append("\(label): failed"); continue }
                    var tail = ""
                    if c.nReal > 0 {
                        let rr = (0..<min(3, c.nReal)).compactMap { refineThenPropose(EDXFixtures.realisation(c, $0), elements: elements, useRefinedResolution: refR) }
                        tail = " (realisations: " + rr.map { f(ratio($0, truth)) + ($0.proposed ? "P" : "") }.joined(separator: ", ") + ")"
                    }
                    parts.append("\(label): \(f(ratio(m, truth)))\(m.proposed ? "P" : "")\(tail)")
                }
                gateNote("EDX D2 refine-then-propose \(id), net/truth (P = proposed): " + parts.joined(separator: "; "))
            }
        }
        // measured outcome guarded (not an upstream bound): refining axis and R_MnKa first brings Mg back on a +3 eV axis error
        let c3 = cell("S+3.s.N7.rho0p01")
        let refined = try #require(refineThenPropose(EDXFixtures.meanSpectrum(c3), elements: ["Mg", "Al", "Si"], useRefinedResolution: true))
        #expect(ratio(refined, c3.truth["Mg"]!) > 0.9, "refine-then-propose recovers Mg on S+3 (measured 0.99)")
        #expect(refined.proposed)
        let m = RunStore.shared.single("M.s.N7.rho0p01"), p3 = RunStore.shared.single("S+3.s.N7.rho0p01")
        #expect(ratio(m.mean, 100_000) > ratio(p3.mean, 100_000), "a +3 eV axis error costs Mg relative to the matched axis")
        gateNote("EDX D2 verdict (refuting observation: S +-3 eV keeps Mg within 20 %): \(refutedAt3 ? "REFUTED" : "NOT refuted: both S+3 and S-3 move Mg net by more than 20 % at rho 0.01, N 1e7")")
    }

    // MARK: D3 tail

    /// An exponential shelf below Al Ka (e-folding 0.15 keV) on the 4096-channel axis, unit area: the planted tail's shape.
    private func tailShape() -> [Double] {
        let ax = EDXFixtures.axis
        var sh = (0..<ax.size).map { k -> Double in let e = ax.energy(ofChannel: k); return e < 1.4865 ? exp((e - 1.4865) / 0.15) : 0 }
        let t = sh.reduce(0, +)
        sh = sh.map { $0 / t }
        return sh
    }

    /// D3. Al Ka incomplete-charge tail. Refuted if on set T a 2 % tail does not change Mg net by more than 10 % at
    /// rho_Mg = 0.01, N_Al = 1e7. Predicted 0.81 of the matched result (0.14 at rho 0.002). Then the tail supplied as a reference
    /// shape (ReferenceShapes, `.lineAmplitude` tied to Al_Ka): how much is recovered.
    @Test func testD3AlKaTail() throws {
        var changed2 = false
        for rho in ["0p01", "0p002"] {
            let base = RunStore.shared.single("M.s.N7.rho\(rho)").mean.net
            var line: [String] = ["M net \(f(base, 0))"]
            for t in ["T1", "T2", "T5"] {
                let id = "\(t).s.N7.rho\(rho)"
                let m = RunStore.shared.single(id)
                line.append("\(t): net \(f(m.mean.net, 0)) = \(f(m.mean.net / max(base, 1e-9))) of matched" + (m.reals.isEmpty ? "" : " (n \(m.reals.count) mean \(f(m.reals.meanNet, 0)), P \(f(m.reals.pProposed)))"))
                if rho == "0p01" && t == "T2" && abs(m.mean.net / base - 1) > 0.10 { changed2 = true }
            }
            gateNote("EDX D3 N 1e7 rho \(rho) family s, noise-free: " + line.joined(separator: "; "))
        }
        // with the tail as a reference shape (fraction of the Al_Ka group area: the generator moves `tail` of the Ka area, Ka = N/(1+0.0132))
        let shape = tailShape()
        for (t, frac) in [("T1", 0.01), ("T2", 0.02), ("T5", 0.05)] {
            for rho in ["0p01", "0p002"] {
                let id = "\(t).s.N7.rho\(rho)"
                let c = cell(id), truth = c.truth["Mg"]!
                let ref = ReferenceShapes([ReferenceShape(name: "Al Ka tail", profile: shape, tie: .lineAmplitude(group: "Al_Ka", fraction: frac / 1.0132))])
                let withRef = PlantedRuns.run(EDXFixtures.meanSpectrum(c), reference: ref)
                let without = RunStore.shared.single(id).mean
                if t == "T2" && rho == "0p01" {
                    // measured outcome guarded (not an upstream bound): the true tail as a reference shape brings Mg back (0.64 -> 0.84)
                    #expect(ratio(withRef, truth) > (ratio(without, truth) + 0.1), "the true tail supplied as a reference shape recovers Mg")
                }
                gateNote("EDX D3 reference shape \(id): net/truth without \(f(ratio(without, truth))) with the true tail supplied \(f(ratio(withRef, truth))) (flank factor \(f(without.misfit, 1)) -> \(f(withRef.misfit, 1)), L_D \(f(without.ld, 0)) -> \(f(withRef.ld, 0)))")
            }
        }
        #expect(RunStore.shared.single("M.s.N7.rho0p01").mean.net > 0)
        gateNote("EDX D3 verdict (refuting observation: a 2 % tail changes Mg net by <= 10 % at rho 0.01, N 1e7): \(changed2 ? "NOT refuted (a 2 % tail changes Mg net by more than 10 %)" : "REFUTED")")
    }

    // MARK: D4 too little Mg

    /// A noise-free matched spectrum whose line shapes are sampled at the channel centre (the fit model's convention, hyperspy's)
    /// instead of integrated over the channel (the generator's, registration 5.2): the stored mean with its bin-integrated Mg, Al
    /// and Si lines taken out and the same lines, same areas and widths, put back centre-sampled. The continuum is the generator's.
    /// Not a planted set of the diagnosis: the control that separates the line-shape sampling convention from every other misfit.
    private func centreSampledMatched(_ c: EDXFixtures.Cell) -> [Double] {
        var out = EDXFixtures.meanSpectrum(c)
        let table: [(String, [(Double, Double)], Double)] = [
            ("Mg", [(1.2536, 1.0), (1.305, 0.01)], c.truth["Mg"]!),
            ("Al", [(1.4865, 1.0), (1.5596, 0.0132)], c.truth["Al"]!),
            ("Si", [(1.7397, 1.0), (1.8389, 0.02779)], c.truth["Si"]!)]
        let ax = EDXFixtures.axis
        for (_, lines, area) in table {
            let tot = lines.reduce(0) { $0 + $1.1 }
            for (e, w) in lines {
                let a = area * w / tot
                let fwhm = XRayLines.fwhm(resolutionMnKaEV: 130, atEnergy: e)!
                let sigma = fwhm / (2 * (2 * log(2.0)).squareRoot())
                let s2 = sigma * 2.0.squareRoot()
                for k in 0..<ax.size {
                    let ek = ax.energy(ofChannel: k)
                    if abs(ek - e) > 10 * sigma + 0.02 { continue }
                    let integrated = a * 0.5 * (erf((ek + 0.01 - e) / s2) - erf((ek - 0.01 - e) / s2))
                    let sampled = a * ax.scale / (sigma * (2 * Double.pi).squareRoot()) * exp(-(ek - e) * (ek - e) / (2 * sigma * sigma))
                    out[k] += sampled - integrated
                }
            }
        }
        return out
    }

    /// D4. Too little Mg in the pooled spectrum (the recorded explanation). Registration: refuted if the planted spectra with a
    /// right model (set M) detect at the level a Mg/Al ratio of 0.002 to 0.01 would deliver (by 20 to 50 times), AND the measured
    /// alloy is nominally >= 0.3 wt % Mg, AND the real Al Ka misfit is small. The last two need measured files (D6) and are not run.
    /// What is measured here: the margin (planted Mg / L_D(M)) of the shipped proposer on set M, and the same on the centre-sampled
    /// control, which separates the line-shape sampling convention of the model from the rest.
    @Test func testD4TooLittleMgMargin() throws {
        for n in ["N5", "N6", "N7"] {
            for rho in ["0p002", "0p005", "0p01"] {
                let id = "M.s.\(n).rho\(rho)"
                let c = cell(id), truth = c.truth["Mg"]!
                let m = RunStore.shared.single(id).mean
                let m0 = PlantedRuns.run(centreSampledMatched(c))
                gateNote("EDX D4 \(id): truth \(f(truth, 0)) | generator (bin-integrated lines): net \(f(m.net, 0)) L_D(M) \(f(m.ld, 0)) margin truth/L_D \(f(truth / m.ld)) flank factor \(f(m.misfit, 1)) | centre-sampled control: net \(f(m0.net, 0)) L_D \(f(m0.ld, 0)) margin \(f(truth / m0.ld)) flank factor \(f(m0.misfit, 2)) proposed \(m0.proposed)")
            }
        }
        let c = cell("M.s.N7.rho0p002")
        let m0 = PlantedRuns.run(centreSampledMatched(c))
        // 0.11.0: the flank factor is gone; what the bin integration does shows in the net itself (Mg reads about 0.3 % of N_Al low beside the
        // bin-integrated Al, as the P2 bias cells print).
        let truth = c.truth["Mg"]!
        #expect(abs(RunStore.shared.single("M.s.N7.rho0p002").mean.net - truth) > abs(m0.net - truth),
                "the generator's bin integration is what moves the Mg net (centre-sampled control: \(m0.net) of \(truth))")
        gateNote("EDX D4 verdict: registration predicts a margin of 20 to 50 at N_Al 1e7 (L_D(M) = 2.2e3); the generator-matched set gives the margin printed above; D6 and the alloy's nominal Mg (Q2) are not available, so D4 can be neither refuted nor confirmed on real data")
    }
}
