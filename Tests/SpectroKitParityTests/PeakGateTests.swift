//
//  PeakGateTests.swift
//  Role: EDX stage gate G-P (docs/edx-stage-gates-registration.md section 3): peak identification.
//
//  exSpy offers no automatic identification (a table lookup and HyperSpy's generic find_peaks1D_ohaver), so the proposer's
//  reference is planted truth (section 5.2), not exSpy. P1: the lookup against exSpy's `get_xray_lines_near_energy`.
//  P2: `ElementProposer.propose` on the planted spectra, matched set M with pass criteria, mismatched sets as a table.
//  P3: find_peaks1D_ohaver (pins) as an independent eye, reported.
//

import Foundation
import Testing
import SpectroTestSupport
import SpectroCore
import SpectroEDX

struct PeakGateTests {

    // MARK: P1

    /// exSpy's `get_xray_lines_near_energy(energy, width, only_lines)` over the line table `XRayLines.all`
    /// (`_xray_lines.py:92-135`): lines within [E - w/2, E + w/2] (inclusive), `only_lines` "a" adds Ka, La, Ma, ordered by
    /// |dE| and, for exactly tied |dE|, by name (the pins' canonical order: amendment 1 item 1).
    ///
    /// REGISTRATION DEVIATION: the registration asks for a new `package` function `XRayLines.near(energy:width:onlyLines:)`.
    /// Sources/ is frozen for this slice (tests only), so the port lives here and the gate tests the TABLE (energies,
    /// element and line names, H and He as shipped) through exSpy's selection rule. The function itself is not in Sources/.
    private func near(_ energy: Double, width: Double, only: [String]?) -> [String] {
        var allowed = only
        if let o = only { for x in o { if x == "a" { allowed!.append(contentsOf: ["Ka", "La", "Ma"]) } else if x == "b" { allowed!.append(contentsOf: ["Kb", "Lb1", "Mb"]) } } }
        let lo = energy - width / 2.0, hi = energy + width / 2.0
        var valid: [(String, Double)] = []
        for l in XRayLines.all {
            if let a = allowed, !a.isEmpty, !a.contains(l.name) { continue }
            if lo <= l.energy && l.energy <= hi { valid.append((l.id, abs(l.energy - energy))) }
        }
        return valid.sorted { ($0.1, $0.0) < ($1.1, $1.0) }.map(\.0)
    }

    @Test func testP1LineLookupEqualsExSpy() throws {
        let near = EDXFixtures.pins.d("lines").d("near")
        let cases = near.l("cases")
        #expect(cases.count == 360)
        var tiedPairs = 0, nonEmpty = 0
        for c in cases {
            let only = (c["only_lines"] as? [String])
            let got = self.near(c.x("energy"), width: c.x("width"), only: only)
            #expect(got == (c["lines"] as! [String]), "E \(c.x("energy")) width \(c.x("width")) only \(String(describing: only))")
            tiedPairs += c.i("tied_adjacent_pairs")
            if !got.isEmpty { nonEmpty += 1 }
        }
        #expect(tiedPairs > 0, "ties are in the grid")
        #expect(nonEmpty > 200)
        // the example in the registration: Mg Ka at width 0.2 finds 33 lines (every line, only_lines nil)
        #expect(self.near(1.2536, width: 0.2, only: nil).count == 33)
        #expect(self.near(1.2536, width: 0.2, only: nil).first == "Mg_Ka")
        gateNote("EDX P1: \(cases.count) lookups equal exSpy (tied |dE| compared in canonical name order; \(tiedPairs) tied adjacent pairs)")
    }

    /// P1 widths: `XRayLines.fwhm` (the Fiori-Newbury law) and the line energies exSpy's `_get_line_energy` gives for Mg, Al, Si
    /// at R_MnKa 125 to 150 (pins.lines.line_energy), relative 1e-14.
    @Test func testP1LineEnergyAndWidthEqualExSpy() throws {
        for e in EDXFixtures.pins.d("lines")["line_energy"] as! [[String: Any]] {
            let line = try #require(XRayLines.line(e.s("line")))
            #expect(line.energy == e.x("energy"))
            let f = try #require(XRayLines.fwhm(resolutionMnKaEV: e.x("R_MnKa"), atEnergy: line.energy))
            #expect(isEqual(f, e.x("fwhm"), accuracy: 1e-14 * e.x("fwhm")), "\(e.s("line")) R \(e.x("R_MnKa"))")
        }
    }
}

// MARK: - P3

extension PeakGateTests {

    /// P3, the independent eye: HyperSpy's `find_peaks1D_ohaver` on the first five realisations of U130 / family L (N_Al 1e5,
    /// 1e6, 1e7 x rho_Mg 0.002, 0.01, 0.05), two settings (pins.peaks), beside the shipped proposer on the SAME spectra.
    /// Positions only, reported, no bound (registration). Asserted: the registered readings of the pins (defaults find only Al Ka;
    /// amp_thresh 0.2 % of max with medfilt 3 finds Mg within 20 eV in 5 of 5 at rho >= 0.01 and at rho 0.002 for N_Al >= 1e6, and
    /// 2 of 5 at 1e5 / 0.002, with 7 to 25 peaks) and that each pinned Al peak sits where the rebuilt spectrum peaks.
    @Test func testP3PeakFinderIsTheRegisteredIndependentEye() throws {
        let cases = EDXFixtures.pins.d("peaks").l("cases")
        #expect(cases.count == 90)
        var mgFound: [String: Int] = [:], total: [String: Int] = [:]
        for c in cases {
            let id = c.s("cell"), setting = c.s("setting"), j = c.i("realisation") - 1
            let peaks = (c["peaks"] as! [[Any]]).map { ($0[0] as! NSNumber).doubleValue }
            let key = "\(id) \(setting)"
            total[key, default: 0] += 1
            if peaks.contains(where: { abs($0 - 1.2536) <= 0.02 }) { mgFound[key, default: 0] += 1 }
            #expect(peaks.contains(where: { abs($0 - 1.4865) <= 0.02 }), "\(key) #\(j + 1): Al Ka found")
            if setting == "default" { #expect(peaks.count == 1, "\(key): the defaults find one peak") }
            else { #expect((7...25).contains(peaks.count), "\(key): \(peaks.count) peaks") }
            // the rebuilt spectrum peaks where the pin says
            let spec = EDXFixtures.realisation(EDXFixtures.cellByID[id]!, j)
            let lo = try EDXFixtures.axis.index(of: 1.40), hi = try EDXFixtures.axis.index(of: 1.57)
            let top = (lo...hi).max { spec[$0] < spec[$1] }!
            let alPeak = peaks.min { abs($0 - 1.4865) < abs($1 - 1.4865) }!
            #expect(isEqual(EDXFixtures.axis.energy(ofChannel: top), alPeak, accuracy: 0.02), "\(key) #\(j + 1)")
        }
        for (key, n) in total.sorted(by: { $0.key < $1.key }) where key.hasSuffix("amp0.002max_med3") {
            let id = String(key.split(separator: " ")[0])
            let c = EDXFixtures.cellByID[id]!
            let found = mgFound[key, default: 0]
            let swift = RunStore.shared.single(id)
            gateNote("EDX P3 \(id): find_peaks1D_ohaver (0.2 % of max, medfilt 3) finds Mg in \(found) of \(n); default settings in \(mgFound[id + " default", default: 0]) of \(n); Swift proposer proposes Mg in \(swift.reals.prefix(5).filter(\.proposed).count) of 5 (net/truth \(String(format: "%.2f", swift.reals.prefix(5).map(\.net).reduce(0, +) / 5 / c.truth["Mg"]!)))")
            if c.rho >= 0.01 || c.nAl >= 1e6 { #expect(found == n, "\(id)") }
            if id == "U130.L.N5.rho0p002" { #expect(found == 2) }
        }
        #expect(mgFound.filter { $0.key.hasSuffix("default") }.values.reduce(0, +) == 0, "the defaults never find Mg")
    }
}

// MARK: - P2

extension PeakGateTests {

    private func mCells(family: String) -> [EDXFixtures.Cell] {
        EDXFixtures.cells.filter { $0.set == "M" && $0.family == family && $0.nReal > 0 }
    }

    private func logMatched(_ rows: [String]) { rows.forEach { gateNote($0) } }

    /// Per-cell summary lines of the matched set (shared by the three criteria).
    private struct MSummary { let cell: EDXFixtures.Cell; let mean: MgRun; let reals: [MgRun]
        var truthMg: Double { cell.truth["Mg"]! }
        /// rho N >= 3 L_D(M), with L_D(M) from the noise-free sandwich of the same design (the run on the mean).
        var detectable: Bool { truthMg >= 3 * mean.ld }
    }

    private func matchedSummaries(full: Bool) -> [MSummary] {
        (mCells(family: "s") + mCells(family: "L")).map { c in
            let r = full ? RunStore.shared.full(c.id, reals: 10) : RunStore.shared.single(c.id)
            return MSummary(cell: c, mean: r.mean, reals: r.reals)
        }
    }

    /// P2 criterion 1, false alarm: at rho_Mg = 0, Mg is proposed in at most 10 % of the realisations at each N_Al
    /// (100 realisations in family s, 20 in L). Single-candidate design, the whole grid.
    @Test func testP2MatchedSetFalseAlarmAtMostTenPercent() throws {
        let zero = matchedSummaries(full: false).filter { $0.cell.rho == 0 }
        #expect(zero.count == 6, "rho 0 cells with realisations: family s at N 1e4 to 1e7, family L at 1e6 and 1e7")
        for s in zero {
            gateNote(String(format: "EDX P2 M %@ (single): false alarm %d of %d (%.0f %%), mean net %.1f, mean L_D %.1f",
                            s.cell.id, s.reals.filter(\.proposed).count, s.reals.count, 100 * s.reals.pProposed, s.reals.meanNet,
                            s.reals.map(\.ld).reduce(0, +) / Double(s.reals.count)))
            #expect(s.reals.pProposed <= 0.10, "\(s.cell.id): Mg proposed in \(s.reals.filter(\.proposed).count) of \(s.reals.count) at rho 0")
        }
    }

    /// P2 criterion 2, detection: where rho_Mg N_Al >= 3 L_D(M), Mg is proposed in at least 90 % of the realisations.
    @Test func testP2MatchedSetDetectsWhereThreeLDHolds() throws {
        let all = matchedSummaries(full: false)
        let det = all.filter { $0.detectable }
        #expect(det.count > 0, "some cell satisfies rho N >= 3 L_D(M)")
        for s in all where s.cell.rho > 0 {
            gateNote(String(format: "EDX P2 M %@ (single): truth %.0f, noise-free net %.0f L_D(M) %.0f (3 L_D %.0f, %@); P(proposed) %.2f of %d; mean net %.0f mean sigma %.0f",
                            s.cell.id, s.truthMg, s.mean.net, s.mean.ld, 3 * s.mean.ld, s.detectable ? "criterion applies" : "below 3 L_D",
                            s.reals.pProposed, s.reals.count, s.reals.meanNet, s.reals.meanSigma))
        }
        for s in det { #expect(s.reals.pProposed >= 0.90, "\(s.cell.id): P(proposed) where truth >= 3 L_D(M)") }
    }

    /// P2 criterion 3, bias: for those cells, |mean net - truth| <= 3 x the proposer's own sigma (mean over realisations).
    @Test func testP2MatchedSetBiasWithinThreeSigma() throws {
        let det = matchedSummaries(full: false).filter { $0.detectable }
        #expect(det.count > 0)
        for s in det {
            let bias = s.reals.meanNet - s.truthMg
            gateNote(String(format: "EDX P2 M %@ (single): bias %.0f counts = %.2f sigma (mean sigma %.0f, misfit %.2f)", s.cell.id, bias,
                            bias / s.reals.meanSigma, s.reals.meanSigma, s.reals.map(\.misfit).reduce(0, +) / Double(s.reals.count)))
            #expect(abs(bias) <= (3 * s.reals.meanSigma), "\(s.cell.id): |net - truth| vs 3 sigma")
        }
    }

    /// P2 on the shipped full pool (about 90 candidate elements, Al and Si current), first ten realisations of every M cell:
    /// the same three criteria (false alarm at most 10 %, which on ten realisations is one; detection where truth >= 3 L_D(M),
    /// L_D(M) now from the full pool's own noise-free run; bias within 3 sigma). Other elements proposed are counted and
    /// reported (the registration sets no bound on them).
    @Test func testP2MatchedSetFullPool() throws {
        let all = matchedSummaries(full: true)
        var elsewhere: [String] = []
        for s in all {
            let n = s.reals.count
            for r in s.reals + [s.mean] where !r.other.isEmpty { elsewhere.append("\(s.cell.id): \(r.other)") }
            if s.cell.rho == 0 {
                #expect((Double(s.reals.filter(\.proposed).count) / Double(n)) <= 0.10, "\(s.cell.id): false alarm (full pool)")
            } else if s.detectable {
                #expect(s.reals.pProposed >= 0.90, "\(s.cell.id): detection (full pool)")
                #expect(abs(s.reals.meanNet - s.truthMg) <= (3 * s.reals.meanSigma), "\(s.cell.id): bias (full pool)")
            }
            gateNote(String(format: "EDX P2 M %@ (full pool, %d reals): truth %.0f noise-free net %.0f L_D %.0f; P %.2f; mean net %.0f",
                            s.cell.id, n, s.truthMg, s.mean.net, s.mean.ld, s.reals.pProposed, s.reals.meanNet))
        }
        // Not a registered criterion: reported. The proposer's own notes state a look-elsewhere rate of chance proposals
        // per spectrum; elements other than Al, Si and Mg on matched Al-Mg-Si data are such chance proposals.
        let spectra = all.reduce(0) { $0 + $1.reals.count + 1 }
        gateNote("EDX P2 M full pool: other elements proposed on matched data in \(elsewhere.count) of \(spectra) spectra (not a registered criterion): \(elsewhere.prefix(40))")
    }

    /// P2 mismatched sets (U, S, T, C, HALF, B, W, X): no pass or fail, a table (registration P2): net/truth on the noise-free
    /// mean and P(proposed), single-candidate and full pool, written to the gate log. Asserted: the runs return.
    @Test func testP2MismatchedSetsTable() throws {
        let cells = EDXFixtures.cells.filter { $0.set != "M" }
        var lines: [String] = []
        for c in cells.sorted(by: { $0.id < $1.id }) {
            let s = RunStore.shared.single(c.id)
            #expect(s.mean.present, "\(c.id)")
            let truth = c.truth["Mg"]!
            lines.append(String(format: "EDX P2 table %@ single: truth %.0f net/truth(noise-free) %@ L_D %.0f P %@ (n %d)", c.id, truth,
                                truth > 0 ? String(format: "%.2f", s.mean.net / truth) : "n/a (net \(String(format: "%.0f", s.mean.net)))", s.mean.ld,
                                s.reals.isEmpty ? "n/a" : String(format: "%.2f", s.reals.pProposed), s.reals.count))
        }
        logMatched(lines)
    }
}
