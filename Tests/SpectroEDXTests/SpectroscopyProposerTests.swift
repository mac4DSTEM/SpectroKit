import Foundation
import Testing
import SpectroTestSupport
import SpectroCore
import SpectroEDX

/// v5.0 WP3 lane P: the element proposer rebuilt on the model fit. The cases are Fable's round-2 failures
/// (`reviewT2/glm.py`: Kramers x window-absorption continuum, a Ga L-alpha tail, an unlisted O K-alpha, an Al K step),
/// generated here from the fit's own line model with Poisson noise, plus lane S's simulator pools
/// (`Fixtures/eds-proposer-sim.json`, generator `tools/edx-sim/proposer_sim.py`) for the sum-peak conflicts.
/// Statistical cells use a fixed seed list; each assertion states the cell it covers.
struct SpectroscopyProposerTests {

    // MARK: Notes for the lane report ($PROPOSER_NOTES via TEST_RUNNER_PROPOSER_NOTES)

    private func note(_ s: String) {
        guard let path = ProcessInfo.processInfo.environment["PROPOSER_NOTES"] else { return }
        if let h = FileHandle(forWritingAtPath: path) { h.seekToEndOfFile(); h.write((s + "\n").data(using: .utf8)!); try? h.close() }
        else { try? (s + "\n").write(toFile: path, atomically: false, encoding: .utf8) }
    }

    // MARK: Random numbers (as SpectroscopyFitTests: seeded, platform independent)

    private struct SplitMix64: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
        mutating func uniform() -> Double { Double(next() >> 11) / Double(1 << 53) }
    }

    private static func poisson(_ lam: Double, _ rng: inout SplitMix64) -> Double {
        if lam <= 0 { return 0 }
        if lam < 10 {
            let l = exp(-lam); var k = 0.0; var p = 1.0
            repeat { k += 1; p *= rng.uniform() } while p > l
            return k - 1
        }
        let slam = lam.squareRoot(), loglam = log(lam)
        let b = 0.931 + 2.53 * slam, a = -0.059 + 0.02483 * b
        let invalpha = 1.1239 + 1.1328 / (b - 3.4), vr = 0.9277 - 3.6224 / (b - 2)
        while true {
            let u = rng.uniform() - 0.5, v = rng.uniform()
            let us = 0.5 - abs(u)
            let k = ((2 * a / us + b) * u + lam + 0.43).rounded(.down)
            if us >= 0.07 && v <= vr { return k }
            if k < 0 || (us < 0.013 && v > us) { continue }
            if log(v) + log(invalpha) - log(a / (us * us) + b) <= -lam + k * loglam - lgamma(k + 1) { return k }
        }
    }
    private static func draw(_ expected: [Double], seed: UInt64) -> [Double] {
        var rng = SplitMix64(state: seed)
        return expected.map { poisson($0, &rng) }
    }

    // MARK: Fable's generator (reviewT2/glm.py), on the fit's own line model

    private static let axis = EnergyAxis(offset: 0, scale: 0.01, size: 1100)
    private static let energies = (0..<axis.size).map { axis.energy(ofChannel: $0) }

    /// glm.py `continuum_mu("kramers")`: Kramers x window absorption (thin: no edge), E0 = 200 keV, per channel at dose 1.
    private static func kramers(_ e: Double) -> Double {
        let x = max(e, 0.05)
        return 60 * max(200 - e, 0) / x * exp(-pow(0.30 / x, 3)) * 0.02 + 0.5
    }
    /// glm.py `continuum_mu("edge<f>")`: 25 exp(-E/2.5) + 2, stepping down by `step` above the Al K edge.
    private static func expStep(_ e: Double, step: Double) -> Double {
        let c = 25 * exp(-e / 2.5) + 2
        return e >= 1.56 ? c * (1 - step) : c
    }

    /// Expected counts: line areas (counts, by line-group id: "Al_Ka", "Ga_La", ...) x dose + the continuum x dose.
    /// The lines are the fit's own groups (Gaussian, the Fiori-Newbury width at 130 eV, the family tied by the table).
    private static func expected(areas: [String: Double], dose k: Double, continuum: (Double) -> Double,
                                 escapeFraction: Double = 0) -> [Double] {
        var out = energies.map { $0 >= 0.2 ? k * continuum($0) : 0 }
        for (id, area) in areas {
            let el = String(id.prefix { $0 != "_" })
            let g = EDSLineModel.build(elements: [el], axis: axis, beamEnergy: 200, resolutionMnKaEV: 130)
                .groups.first { $0.id == id }!
            let col = EDSLineModel.column(of: g.lines, energies: energies, scale: axis.scale)
            let esc = escapeFraction > 0 && !g.escapes.isEmpty
                ? EDSLineModel.column(of: g.escapes, energies: energies, scale: axis.scale) : nil
            for i in out.indices { out[i] += k * area * col[i] + (esc.map { k * area * escapeFraction * $0[i] } ?? 0) }
        }
        return out
    }

    private static func settings(_ current: [String]) -> FitSettings {
        FitSettings.standard(elements: current, axis: axis, resolutionMnKaEV: 130, beamEnergy: 200)
    }
    private static let doses: [Double] = [1, 10, 100]
    private static let seeds = 6

    private func run(_ counts: [Double], current: [String], pool: [String]? = nil, hole: [Double]? = nil) throws -> ProposalResult {
        let p = ElementProposer(pool: pool)
        return try p.propose(counts: counts, axis: Self.axis, settings: Self.settings(current), holeCounts: hole)
    }
    /// nil when the loop never found a residual peak for the element (0.11.0: not every pool element is a candidate).
    private func candidate(_ r: ProposalResult, _ el: String) -> ElementCandidate? { r.candidates.first { $0.element == el } }
    /// An element absent from the candidates is not proposed.
    private func isProposed(_ r: ProposalResult, _ el: String) -> Bool { candidate(r, el)?.isProposed ?? false }

    // MARK: 1. Realistic continuum: no false Mg at Mg = 0, the detection rate at 0.3 % and 1 %

    /// A joint fit tests ~115 line groups, so about one spectrum in twenty shows a chance element at L_D (alpha = beta = 0.05 per
    /// candidate, by rule; the proposal says so). Tests therefore assert on the NAMED elements (Mg, Si, Na, never
    /// proposed) and give chance elements a budget that a modelling fault (a continuum misfit) would exceed.
    private static let chanceBudgetPer50 = 5

    /// Fable's case 1: Mg at 0 / 0.3 / 1 % of Al on the Kramers x window-absorption continuum, x1 / x10 / x100 dose.
    /// Round 2 read a 0.3 % Mg as a large NEGATIVE net here. Asserted: no Mg at Mg = 0 at any dose, chance elements within budget
    /// (without the flank-misfit scaling there are 7-14 per 6 spectra at x100: the report has the comparison), and the 1 % x100
    /// cell is a candidate at or above L_D in every draw (proposed only when the fit gains 100, see the assertion). The detection rates are measured numbers, written to the notes, not asserted.
    @Test func testKramersContinuumNoFalseMgAndTheDetectionRate() throws {
        var chance = 0
        defer { #expect(chance <= (Self.chanceBudgetPer50 * 54 / 50), "chance elements over 54 spectra") }
        for k in Self.doses {
            for frac in [0.0, 0.003, 0.01] {
                var found = 0, seen = 0
                var others: [String] = []
                var nets: [Double] = [], lds: [Double] = []
                for s in 0..<Self.seeds {
                    let areas = ["Al_Ka": 9000, "Mg_Ka": 9000 * frac]
                    let counts = Self.draw(Self.expected(areas: areas, dose: k, continuum: Self.kramers), seed: UInt64(100 * Int(k) + s))
                    let r = try run(counts, current: ["Al"])
                    let mg = candidate(r, "Mg")
                    if isProposed(r, "Mg") { found += 1 }
                    if let mg, mg.aboveDetectionLimit, mg.isProposed || mg.possibleReason != nil { seen += 1 }
                    nets.append(mg?.net ?? 0); lds.append(mg?.detectionLimit ?? 0)   // absent = not detected
                    others += r.proposed.filter { $0.element != "Mg" }.map(\.group)
                }
                note("kramers x\(Int(k)) Mg \(frac * 100) %: proposed \(found)/\(Self.seeds), mean net \(Int(nets.reduce(0, +) / Double(Self.seeds))) (true \(Int(9000 * frac * k))), mean L_D \(Int(lds.reduce(0, +) / Double(Self.seeds))); other proposed: \(others)")
                chance += others.count
                if frac == 0 { #expect(found == 0, "false Mg at x\(Int(k)) with no Mg planted") }
                // 0.11.0 (moved bar, review before tag): the identification loop proposes only when the statistic with the 1 % model term falls by
                // 100; beside Al at x100 (9e5 counts) a 1 % Mg gains 44 to 71 although its net is about 3.7 L_D. It must be a candidate at or above
                // L_D in every draw (shown as possible, with the reason), never lost.
                if frac == 0.01 && k == 100 {
                    #expect(seen == Self.seeds, "1 % Mg at x100 is a candidate at or above L_D in every draw")
                }
            }
        }
    }

    // MARK: 2. A strong Ga L-alpha, Mg absent

    /// Fable's case 2 (the round-1/2 false Mg): Ga L-alpha 900 counts x dose (with its K family, 2700, as the family-consistency rule needs) beside an absent Mg. Ga is a column of the joint fit, so its
    /// tail is not read as Mg. Ga is found from x10 and carries the named FIB conflict.
    @Test func testGaLAlphaDoesNotMakeAFalseMg() throws {
        for k in Self.doses {
            var gaFound = 0
            for s in 0..<Self.seeds {
                let counts = Self.draw(Self.expected(areas: ["Al_Ka": 9000, "Ga_La": 900, "Ga_Ka": 2700], dose: k, continuum: Self.kramers), seed: UInt64(2000 + 100 * Int(k) + s))
                let r = try run(counts, current: ["Al"])
                #expect(!isProposed(r, "Mg"), "false Mg beside Ga L at x\(Int(k))")
                let ga = candidate(r, "Ga"), mg = candidate(r, "Mg")
                if let ga, ga.isProposed {
                    gaFound += 1
                    #expect(ga.conflicts.contains { $0.kind == .fibContamination }, "Ga carries the FIB question")
                }
                note("Ga x\(Int(k)) seed \(s): Ga \(ga.map { "\($0.group) net \(Int($0.net)) L_D \(Int($0.detectionLimit))" } ?? "no candidate"); Mg net \(Int(mg?.net ?? 0)) L_D \(Int(mg?.detectionLimit ?? 0)); proposed \(r.proposed.map(\.group))")
            }
            note("Ga x\(Int(k)): found \(gaFound)/\(Self.seeds)")
            if k >= 10 { #expect(gaFound == Self.seeds, "Ga L (\(Int(900 * k)) counts) is found at x\(Int(k))") }
        }
    }

    // MARK: 3. An unlisted O K-alpha

    /// Fable's case 3: O K-alpha 3000 counts x dose unlisted. Round 2's windows read Na, Mg and Si down by up to 40 L_D beside it.
    /// Here O is a candidate column: O is proposed at every dose and no neighbour (Na, Mg, Si) is, whether the neighbours are
    /// candidates or already listed.
    @Test func testUnlistedOxygenIsProposedAndBiasesNoNeighbour() throws {
        var chance = 0
        defer { #expect(chance <= (Self.chanceBudgetPer50 * 36 / 50 + 1), "chance elements over 36 proposals") }
        for k in Self.doses {
            for s in 0..<Self.seeds {
                let counts = Self.draw(Self.expected(areas: ["Al_Ka": 9000, "O_Ka": 3000], dose: k, continuum: Self.kramers), seed: UInt64(3000 + 100 * Int(k) + s))
                for current in [["Al"], ["Al", "Na", "Mg", "Si"]] {
                    let r = try run(counts, current: current)
                    #expect(isProposed(r, "O"), "O K-alpha (\(Int(3000 * k)) counts) proposed at x\(Int(k)), listed \(current)")
                    for el in ["Na", "Mg", "Si"] where !current.contains(el) {
                        #expect(!isProposed(r, el), "\(el) proposed beside an unlisted O at x\(Int(k))")
                        note("O x\(Int(k)) seed \(s): \(el) net/L_D \(String(format: "%.2f", candidate(r, el)?.significance ?? 0))")
                    }
                    let extra = r.proposed.map(\.element).filter { $0 != "O" }
                    chance += extra.count
                    #expect(extra.count <= 1, "at most one chance element at x\(Int(k)), listed \(current): \(extra)")
                }
            }
        }
    }

    // MARK: 4. The Al K edge step

    /// Fable's case 4: a 10 % and a 30 % step down at the Al K edge (1.56 keV), on his exponential continuum and on the Kramers one
    /// (times the step). The fit's continuum is split at 1.5596 keV, so the step produces no Mg (below the edge) and no Si (above it).
    @Test func testAlEdgeStepMakesNoFalseMgOrSi() throws {
        var chance = 0
        defer { #expect(chance <= (Self.chanceBudgetPer50 * 72 / 50 + 1), "chance elements over 72 spectra") }
        for step in [0.1, 0.3] {
            for kind in ["exp", "kramers"] {
                for k in Self.doses {
                    for s in 0..<Self.seeds {
                        let cont: (Double) -> Double = kind == "exp" ? { Self.expStep($0, step: step) }
                            : { $0 >= 1.56 ? Self.kramers($0) * (1 - step) : Self.kramers($0) }
                        let counts = Self.draw(Self.expected(areas: ["Al_Ka": 9000], dose: k, continuum: cont), seed: UInt64(4000 + 100 * Int(k) + s))
                        let r = try run(counts, current: ["Al"])
                        #expect(!isProposed(r, "Mg"), "false Mg, \(kind) step \(step) x\(Int(k))")
                        #expect(!isProposed(r, "Si"), "false Si, \(kind) step \(step) x\(Int(k))")
                        chance += r.proposed.count
                    }
                }
            }
        }
    }

    // MARK: 5. Lane S's simulator: the sum-peak conflicts

    private struct SimPools: Decodable {
        struct Region: Decodable { let label: String; let countsPerPixel: Double; let expected: [Double]; let components: [String: Double] }
        let offset: Double, scale: Double, size: Int
        let regions: [Region]
        var axis: EnergyAxis { EnergyAxis(offset: offset, scale: scale, size: size) }
    }
    private static let sim: SimPools = {
        let url = FixtureDirs.fixtures(of: "SpectroCoreTests").appendingPathComponent("eds-proposer-sim.json")
        return try! JSONDecoder().decode(SimPools.self, from: Data(contentsOf: url))
    }()

    /// "sum_Al_Ka+Mg_Ka" -> ("Al+Mg sum", ["Al", "Mg"], energy from the line table)
    private static func sumLabel(_ truthName: String) -> (label: String, energy: Double) {
        let parts = truthName.dropFirst(4).split(separator: "+").map(String.init)
        let els = parts.map { String($0.prefix { $0 != "_" }) }
        let e = parts.map { XRayLines.line($0)!.energy }.reduce(0, +)
        return (els[0] + "+" + els[1] + " sum", e)
    }

    private func simProposal(_ region: Int, seed: UInt64) throws -> (r: ProposalResult, truth: [String: Double]) {
        let axis = Self.sim.axis
        let counts = Self.draw(Self.sim.regions[region].expected, seed: seed)
        let st = FitSettings.standard(elements: ["Al", "Mg", "Si", "O"], axis: axis, resolutionMnKaEV: 130, beamEnergy: 200)
        let r = try ElementProposer().propose(counts: counts, axis: axis, settings: st)
        return (r, Self.sim.regions[region].components)
    }

    /// The T2 core, on the EDX forward model (tools/edx-sim) at 10, 100 and 300 counts/px: where the truth sum peak is above 1.5 L_D it is
    /// NAMED (a candidate on its energy carries the sum conflict, or the sum column itself is detected); where it is below
    /// 0.5 L_D nothing is named at its energy. L_D is the limit of whatever sits at that energy in the same proposal.
    @Test func testSumPeaksAreNamedExactlyWhereTruthExceedsTheDetectionLimit() throws {
        var namedAtDose: [Int: Int] = [:]
        var densest: ProposalResult?
        for region in 0..<Self.sim.regions.count {
            let (r, truth) = try simProposal(region, seed: UInt64(5000 + region))
            if region == 2 { densest = r }
            note("sim region \(Self.sim.regions[region].label) (passes \(r.passes), settled \(r.settled)): proposed \((r.proposed + r.sumPeakQuestions).map { "\($0.group)\($0.conflicts.isEmpty ? "" : "[" + $0.conflicts.map(\.id).joined(separator: ",") + "]")" }); sum columns \(r.sumPeaks.map { "\($0.label) \(Int($0.net))/\(Int($0.detectionLimit))" })")
            for (name, trueCounts) in truth.sorted(by: { $0.key < $1.key }) where name.hasPrefix("sum_") {
                let (label, e) = Self.sumLabel(name)
                let candidates = r.candidates.filter { abs($0.energyKeV - e) <= LineConflicts.sumPeakToleranceKeV }
                let named = r.sumPeakQuestions.contains { $0.conflicts.contains { $0.kind == .sumPeak && abs($0.energiesKeV[0] - e) < 1e-9 } }
                    || r.sumPeaks.contains { $0.label == label && $0.detected }
                let limit = r.sumPeaks.first { $0.label == label }?.detectionLimit ?? r.sumPeakQuestions.filter { c in c.conflicts.contains { $0.kind == .sumPeak && abs($0.energiesKeV[0] - e) < 1e-9 } }.map(\.detectionLimit).min()
                note("   \(label) \(String(format: "%.3f", e)) keV truth \(Int(trueCounts)) L_D \(limit.map { String(Int($0)) } ?? "none") named \(named) (candidates there: \(candidates.map(\.group)))")
                if let limit, trueCounts > 1.5 * limit { #expect(named, "\(label) (\(Int(trueCounts)) counts > 1.5 L_D \(Int(limit))) is named, region \(region)") }
                if let limit, trueCounts < 0.5 * limit { #expect(!named, "\(label) (\(Int(trueCounts)) counts < 0.5 L_D \(Int(limit))) is not named, region \(region)") }
                if limit == nil { #expect(!named) }
                if named { namedAtDose[region, default: 0] += 1 }
            }
        }
        #expect((namedAtDose[2] ?? 0) >= 3, "at 300 counts/px at least three of the six sum peaks are named")
        // 0.11.0: the proposer is the identification loop; "Ar proposed WITH the Al+Al question" (every pool element a candidate, then a
        // conflict attached) no longer exists. The contract now: the peak at the Al+Al energy is the sum column and it is detected, and no
        // phantom at a pile-up energy (Ar, Rh, Sn, Sr, Ag, Ru) is proposed, whether the loop made it a candidate or not.
        let dense = try #require(densest)
        #expect(dense.sumPeaks.contains { $0.label == "Al+Al sum" && $0.detected }, "the Al+Al sum is a detected column at 300 counts/px")
        for el in ["Rh", "Sn", "Sr", "Ar", "Ag", "Ru"] { #expect(!(dense.proposed.contains { $0.element == el }), "\(el) must not be in `proposed`") }
    }

    // MARK: 6. Structure: nothing is added silently

    /// The element list is data the proposer reads: it takes settings by value and returns candidates; the source of the
    /// Proposer folder has no `inout` and never writes an `elements` list.
    @Test func testTheProposerNeverMutatesTheElementList() throws {
        let counts = Self.draw(Self.expected(areas: ["Al_Ka": 9000, "Mg_Ka": 900], dose: 10, continuum: Self.kramers), seed: 6)
        let settings = Self.settings(["Al", "Si"])
        let r = try ElementProposer().propose(counts: counts, axis: Self.axis, settings: settings)
        #expect(r.proposed.contains { $0.element == "Mg" }, "Mg is proposed (so the proposer had every reason to add it)")
        #expect(settings.elements == ["Al", "Si"])
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/SpectroEDX/Proposer")
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".swift") }
        #expect(Set(files) == ["ElementProposer.swift", "FitNullVariance.swift", "IdentificationLoop.swift", "LineConflicts.swift", "ProposalRules.swift"])   // ProposalRules (WP4, lane L12) is a post-selection on a result, never an edit of an element list: the scan below covers it too
        for f in files {
            let src = try String(contentsOf: dir.appendingPathComponent(f), encoding: .utf8)
                .split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
            for forbidden in ["inout", ".elements.append", ".elements.insert", ".elements =", ".elements +=", ".elements.remove"] {
                #expect(!src.contains(forbidden), "\(f) contains `\(forbidden)`")
            }
        }
    }

    // MARK: 7. Refusals, Cu, notes

    @Test func testLightElementsAreRefusedWithTheirReasons() throws {
        let counts = Self.draw(Self.expected(areas: ["Al_Ka": 9000], dose: 10, continuum: Self.kramers), seed: 7)
        let r = try ElementProposer(pool: ["H", "He", "Li", "Be", "Mg", "Si"]).propose(counts: counts, axis: Self.axis, settings: Self.settings(["Al"]))
        #expect(Set(r.refused.map(\.element)) == ["H", "He", "Li", "Be"])
        #expect(r.refused.first { $0.element == "He" }!.reason.contains("no characteristic X-ray line"))
        #expect(r.refused.first { $0.element == "Be" }!.reason.contains("absorbed in its window"))
        // 0.11.0: only an element with a residual peak is a candidate, so Mg and Si need not appear; a refused one never does.
        #expect(Set(r.candidates.map(\.element)).isSubset(of: ["Mg", "Si"]), "a refused element is never a candidate")
        // The default pool's refusals are reported too, with C and N (lines below the lowest tested energy) named separately.
        let d = try ElementProposer().propose(counts: counts, axis: Self.axis, settings: Self.settings(["Al"]))
        #expect(Set(d.refused.map(\.element)).isSuperset(of: ["H", "He", "Li", "Be", "C", "N"]))
        #expect(d.refused.first { $0.element == "C" }!.reason.contains("lowest tested line"))
    }

    /// Cu defaults to Quantify and names the grid-or-Q question; the hole spectrum answers it.
    @Test func testCuDefaultsToQuantifyWithTheGridQuestionAndTheHoleCheck() throws {
        let sample = Self.draw(Self.expected(areas: ["Al_Ka": 9000, "Cu_Ka": 700], dose: 10, continuum: Self.kramers), seed: 8)
        let holeClean = Self.draw(Self.expected(areas: [:], dose: 10, continuum: Self.kramers), seed: 9)
        let holeCu = Self.draw(Self.expected(areas: ["Cu_Ka": 700], dose: 10, continuum: Self.kramers), seed: 10)
        let none = try run(sample, current: ["Al"])
        let cu = try #require(candidate(none, "Cu"))
        #expect(cu.isProposed)
        #expect(cu.suggestedRole == .quantify)
        #expect(cu.conflicts.contains { $0.kind == .gridOrSample })
        #expect(cu.holeRegionNote == "No hole region available: Cu grid and Q phase cannot be separated.")
        #expect(none.proposed.filter { $0.element != "Cu" }.map(\.element) == [])
        #expect((candidate(none, "Mg")?.suggestedRole ?? .fitOnly) == .fitOnly)   // Mg is absent from the candidates here; if it were one, it is Fit only
        let cuClean = try #require(candidate(try run(sample, current: ["Al"], hole: holeClean), "Cu"))
        #expect(try #require(cuClean.holeRegionNote).hasPrefix("No Cu on the hole region"))
        let cuHole = try #require(candidate(try run(sample, current: ["Al"], hole: holeCu), "Cu"))
        #expect(try #require(cuHole.holeRegionNote).hasPrefix("Cu is also detected on the hole region"))
    }

    /// The fit's weak-line warning, the lowest-line rule and the Currie convention are in every proposal's notes.
    @Test func testNotesCarryTheFitWarningsAndTheDetectionRule() throws {
        let counts = Self.draw(Self.expected(areas: ["Al_Ka": 9000], dose: 10, continuum: Self.kramers), seed: 11)
        let r = try run(counts, current: ["Al"])
        #expect(r.notes.contains(ContinuumForm.weakLineBiasNote), "the weak-line bias warning propagates")
        #expect(r.notes.contains { $0.contains("Currie L_D") && $0.contains("0.05") })
        #expect(r.notes.contains { $0.hasPrefix("Lines below 0.45 keV are not tested") })
        #expect(r.notes.contains { $0.contains("least squares, weighted by 1/(y + (0.01 y)\u{00B2})") })
        #expect(r.settled)
    }

    // MARK: 8. The null variance and Currie's false-positive rate

    private func nullVarianceFixture(counts: [Double]) throws -> (EDSLineModel, LinearDesign, EDSFitResult) {
        let st = Self.settings(["Al", "Mg"])
        let model = EDSLineModel.build(elements: st.elements, axis: Self.axis, beamEnergy: 200, resolutionMnKaEV: 130)
        let design = LinearDesign.build(model: model, axis: Self.axis, channels: Self.axis.fitChannels(from: 0.2, to: nil), background: st.background)
        return (model, design, EDSFit.fit(design: design, model: model, counts: counts, settings: st, computeCovariance: false))
    }

    @Test func testNullVarianceEqualsTheFittedOneForAnAbsentLineAndIsSmallerForAStrongOne() throws {
        let counts = Self.draw(Self.expected(areas: ["Al_Ka": 9000], dose: 10, continuum: Self.kramers), seed: 12)
        let (model, design, result) = try nullVarianceFixture(counts: counts)
        let v = try #require(FitNullVariance.compute(design: design, result: result))
        let mg = model.groups.firstIndex { $0.id == "Mg_Ka" }!, al = model.groups.firstIndex { $0.id == "Al_Ka" }!
        #expect(result.values[mg] == 0, "Mg is at the bound")
        #expect(isEqual(try #require(v.null[mg]), try #require(v.atFit[mg]), accuracy: 1e-9 * v.atFit[mg]!), "absent line: null = fitted variance")
        #expect((try #require(v.null[al])) < (0.9 * v.atFit[al]!), "a strong line carries its own Poisson variance only at the fitted state")
    }

    /// Currie's alpha: with only Al planted, the fraction of draws in which Mg's area exceeds L_C = z_alpha sigma_0 is at most
    /// about 5 % (one-sided: the fit's weak-line bias is negative, the area non-negative), and clearly above 0 (sigma_0 is not inflated away).
    @Test func testFalsePositiveRateAtTheCriticalLevelIsAboutAlpha() throws {
        let expected = Self.expected(areas: ["Al_Ka": 9000], dose: 10, continuum: Self.kramers)
        var above = 0
        let draws = 200
        for s in 0..<draws {
            let (model, design, result) = try nullVarianceFixture(counts: Self.draw(expected, seed: UInt64(8000 + s)))
            let mg = model.groups.firstIndex { $0.id == "Mg_Ka" }!
            let s0 = try #require(FitNullVariance.compute(design: design, result: result)?.null[mg]).squareRoot()
            if result.values[mg] > Currie.standard.criticalLevel(sigmaZero: s0) { above += 1 }
        }
        note("false-positive rate at L_C, Mg absent, Al x10: \(above)/\(draws)")
        #expect(above <= 16, "about alpha = 5 % of \(draws) or fewer")
        #expect(above >= 1, "sigma_0 is not so large that nothing ever reaches L_C")
    }

    // MARK: 9. The look-elsewhere rate is visible (the misfit factor is gone since 0.11.0)

    @Test func testNotesStateTheLookElsewhereRateAndNoMisfitFactor() throws {
        let counts = Self.draw(Self.expected(areas: ["Al_Ka": 9000, "Mg_Ka": 90], dose: 100, continuum: Self.kramers), seed: 31)
        let r = try run(counts, current: ["Al"])
        #expect(r.candidates.allSatisfy { $0.misfit == 1 })
        #expect(!r.notes.contains { $0.contains("flank-misfit") })
        let look = try #require(r.notes.first { $0.hasPrefix("Look-elsewhere:") })
        #expect(look.contains("candidates were tested"), "\(look)")
    }

    /// The REPORTED covariance is a passive-set sandwich, so the fit's own sigma predicts the scatter of the
    /// Al K-alpha area over 200 Poisson draws (the SD of an SD at 200 draws is 5 %). Before: the full-design pseudo-inverse counted the
    /// bound-active Mg column as free and gave ratio 0.81 (P9); predicted after: [0.85, 1.15], pinned [0.90, 1.15]; measured 1.03 (seeds 9000+s).
    /// NOT claimed: conservatism on weak lines. Fable's review measured empirical SD / sigma on a weak Mg line at 1.05 / 1.06 / 1.08 (LS, Mg 1/3/10 %),
    /// i.e. the passive-set sigma is 5-8 % SMALL there, and about 12 % small under Poisson-ML (1.13 / 1.11); Al is within 4 %. The old full-design sigma
    /// was 0.96-0.99 on the weak line. This test covers the strong line only.
    @Test func testFitSigmaPredictsTheScatterOfTheAlphaArea() throws {
        let expected = Self.expected(areas: ["Al_Ka": 9000], dose: 10, continuum: Self.kramers)
        var areas: [Double] = [], predicted = 0.0
        let draws = 200
        let st = Self.settings(["Al", "Mg"])
        let model = EDSLineModel.build(elements: st.elements, axis: Self.axis, beamEnergy: 200, resolutionMnKaEV: 130)
        let design = LinearDesign.build(model: model, axis: Self.axis, channels: Self.axis.fitChannels(from: 0.2, to: nil), background: st.background)
        let al = model.groups.firstIndex { $0.id == "Al_Ka" }!, mg = model.groups.firstIndex { $0.id == "Mg_Ka" }!
        let g = model.groups.count
        for s in 0..<draws {
            let result = EDSFit.fit(design: design, model: model, counts: Self.draw(expected, seed: UInt64(9000 + s)), settings: st)
            areas.append(result.values[al])
            predicted += result.covariance[al * g + al].squareRoot() / Double(draws)
            if result.atBound[mg] {
                #expect(result.covariance[al * g + mg] == 0, "a bound-active area carries no covariance")
                #expect(result.covariance[mg * g + mg] > 0, "...and the full-design marginal variance (as if freed)")
            }
        }
        let m = areas.reduce(0, +) / Double(draws)
        let sd = (areas.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(draws - 1)).squareRoot()
        note("Sigma: Al Ka area SD \(sd) vs reported sigma \(predicted) (ratio \(sd / predicted))")
        #expect((sd / predicted) > 0.90)   // 0.85 would not catch a x1.2 sigma (it measures 0.86)
        #expect((sd / predicted) < 1.15)
    }

    /// Lane Sigma: the proposer's null variance keeps the FULL design (the candidate is free under H0) and so does not move with the
    /// reported-covariance change: pinned values on a fixed spectrum (seed 12), measured before the change with the same FitNullVariance code,
    /// and independent of whether the fit computed its own covariance.
    @Test func testProposerNullVarianceKeepsTheFullDesign() throws {
        let counts = Self.draw(Self.expected(areas: ["Al_Ka": 9000], dose: 10, continuum: Self.kramers), seed: 12)
        let (model, design, result) = try nullVarianceFixture(counts: counts)
        let v = try #require(FitNullVariance.compute(design: design, result: result))
        let mg = model.groups.firstIndex { $0.id == "Mg_Ka" }!, al = model.groups.firstIndex { $0.id == "Al_Ka" }!
        #expect(isEqual(try #require(v.null[al]), 181677.5481505521, accuracy: 1e-9 * 181677.55))
        #expect(isEqual(try #require(v.atFit[al]), 592823.7630055768, accuracy: 1e-9 * 592823.76))
        #expect(isEqual(try #require(v.null[mg]), 59583.82281519766, accuracy: 1e-9 * 59583.82))
        let withCov = EDSFit.fit(design: design, model: model, counts: counts, settings: Self.settings(["Al", "Mg"]))
        let v2 = try #require(FitNullVariance.compute(design: design, result: withCov))
        #expect(v2.null[al] == v.null[al]); #expect(v2.atFit[mg] == v.atFit[mg])
        // The reported sigma of the strong line is the smaller, passive-set one; the proposer's atFit stays the full-design one.
        let g = model.groups.count
        #expect(withCov.covariance[al * g + al] < (0.8 * v.atFit[al]!))
    }

    /// Mutation: the `Task.isCancelled` check at the top of `run(_:on:)` removed — the proposal then finishes (or fails otherwise).
    @Test func testACancelledTaskThrowsCancelledBeforeFinishing() async {
        let axis = EnergyAxis(offset: 0, scale: 0.01, size: 1100)
        let counts = [Double](repeating: 20, count: axis.size)
        let st = FitSettings.standard(elements: ["Al"], axis: axis, resolutionMnKaEV: 130, beamEnergy: 200)
        let task = Task.detached { () -> Result<ProposalResult, Error> in
            while !Task.isCancelled { await Task.yield() }
            return Result { try ElementProposer().propose(counts: counts, axis: axis, settings: st) }
        }
        task.cancel()
        let r = await task.value
        guard case .failure(let e) = r else { Issue.record("a cancelled task must not return a proposal"); return }
        #expect((e as? ProposerError) == .cancelled)
    }
}
