import XCTest
import SpectroCore
import SpectroEDX

/// Auto ID failed with `ProposerError.rankDeficient` on a pile-up pair whose energy equals a ONE-COMPONENT column of a candidate:
/// V K-alpha escape 3.2125 keV = Tb M-alpha + Ir M-alpha, on a spectral axis ending at 5.115 keV. There V's group is V K-alpha
/// alone, so its escape column is one Gaussian at 3.2125 keV, and the pile-up column is the same Gaussian. Registered fix:
/// `docs/archive/v5/sum-escape-only-preregistration-2026-10-12.md` (a pair is not added as a column when a group of the design the
/// fit serves has a one-component ESCAPE column at its energy; one-line LINE groups are not compared, owner card A1 option a). The spectra are generated from the fit's own line model with seeded
/// Gaussian-approximated counting noise, as in `SumColumnDedupTests`.
final class SumEscapeIdenticalTests: XCTestCase {

    private struct SplitMix64 {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
        mutating func uniform() -> Double { (Double(next() >> 11) + 0.5) / Double(1 << 53) }
        mutating func normal() -> Double { (-2 * log(uniform())).squareRoot() * cos(2 * Double.pi * uniform()) }
    }

    /// The 1500-channel test axis (0 to 14.99 keV) and the short axis that ends between V K-alpha and V K-beta (top 5.115 keV).
    private static let axis = EnergyAxis(offset: 0, scale: 0.01, size: 1500)
    private static let shortAxis = EnergyAxis(offset: 0, scale: 0.005, size: 1024)

    /// Kramers x window continuum (as SpectroscopyProposerTests), E0 = 200 keV, plus the planted line areas (counts) of the fit's own groups.
    /// `planted`: extra single Gaussians (energy keV, counts, FWHM keV), e.g. a real pile-up peak with the law's width.
    private static func spectrum(_ axis: EnergyAxis, areas: [String: Double], planted: [(energy: Double, area: Double, fwhm: Double)] = [],
                                 seed: UInt64) -> [Double] {
        let energies = (0..<axis.size).map { axis.energy(ofChannel: $0) }
        var mean = energies.map { e -> Double in
            guard e >= 0.2 else { return 0 }
            let x = max(e, 0.05)
            return (60 * max(200 - e, 0) / x * exp(-pow(0.30 / x, 3)) * 0.02 + 0.5) * 20
        }
        for (id, area) in areas {
            let el = String(id.prefix { $0 != "_" })
            let g = EDSLineModel.build(elements: [el], axis: axis, beamEnergy: 200, resolutionMnKaEV: 130).groups.first { $0.id == id }!
            let col = EDSLineModel.column(of: g.lines, energies: energies, scale: axis.scale)
            for i in mean.indices { mean[i] += area * col[i] }
        }
        for p in planted {
            // A unit-area Gaussian per channel, times the bin width (the same law as the model's columns, written out here).
            let sigma = p.fwhm / (2 * (2 * log(2.0)).squareRoot())
            for i in mean.indices {
                let d = energies[i] - p.energy
                mean[i] += p.area * axis.scale * exp(-d * d / (2 * sigma * sigma)) / (sigma * (2 * Double.pi).squareRoot())
            }
        }
        var rng = SplitMix64(state: seed)
        return mean.map { max(0, ($0 + $0.squareRoot() * rng.normal()).rounded()) }
    }

    private static func settings(_ axis: EnergyAxis) -> FitSettings {
        FitSettings.standard(elements: [], axis: axis, resolutionMnKaEV: 130, beamEnergy: 200)
    }

    // MARK: Case D: a pile-up pair equal to a one-component escape column

    /// V K-alpha escape 3.2125 keV = Tb M-alpha 1.2326 + Ir M-alpha 1.9799. Without the fix every amplitude throws `rankDeficient`
    /// (the pile-up column and V's escape column are identical design columns); with it the run scores. At 40 000 V claims the
    /// energy and no pile-up column sits there. At 0 and 300 V is not in the final design, so the pair is compared with nothing and
    /// keeps its own column (registration: docs/archive/v5/sum-escape-only-preregistration-2026-10-12.md, P1 and P2).
    func testVKaEscapeEqualToTbMaPlusIrMaScoresOnAShortAxis() throws {
        let sum = XRayLines.line("Tb_Ma")!.energy + XRayLines.line("Ir_Ma")!.energy
        let escape = XRayLines.line("V_Ka")!.energy - XRayLines.line("Si_Ka")!.energy
        XCTAssertEqual(sum, escape, accuracy: 1e-6, "the premise: the pile-up energy is V K-alpha's escape energy")
        let g = EDSLineModel.build(elements: ["V"], axis: Self.shortAxis, beamEnergy: 200, resolutionMnKaEV: 130).groups.first { $0.id == "V_Ka" }!
        XCTAssertEqual(g.lines.count, 1, "the premise: V K-alpha is the only line of its group on this axis")
        XCTAssertEqual(g.escapes.count, 1, "the premise: its escape column is one Gaussian")
        for amp in [0.0, 300, 40000] {
            let counts = Self.spectrum(Self.shortAxis, areas: ["Tb_Ma": 40000, "Ir_Ma": 40000, "V_Ka": amp], seed: 24)
            let r: ProposalResult
            do {
                r = try ElementProposer(pool: ["Tb", "Ir", "V", "Mg", "Al", "Fe"])
                    .propose(counts: counts, axis: Self.shortAxis, settings: Self.settings(Self.shortAxis))
            } catch {
                XCTFail("amplitude \(amp): the run must score, not throw: \(error) (old code: rankDeficient)")
                continue
            }
            // Only where V claims the energy: at 0 and 300 the pair has no identical column in its design (V is not in it).
            if amp == 40000 {
                XCTAssertFalse(r.sumPeaks.contains { abs($0.energyKeV - sum) <= LineConflicts.sumPeakToleranceKeV },
                               "amplitude \(amp): no pile-up column at the one-component escape energy: \(r.sumPeaks.map(\.label))")
            }
        }
    }

    // MARK: P2: V inactive, a real Tb + Ir pile-up planted at the one-component escape energy

    /// V is in the pool but inactive (amplitude 0), so V's one-component escape column is not in the design the fit serves and the
    /// pair is not compared with it. Tb and Ir are detected at 40 000 counts each; a real Tb + Ir pile-up (2 000 counts, one Gaussian
    /// at 3.2125 keV with the law's FWHM) is planted at the same energy. The final fit must keep a Tb + Ir sum column with a positive
    /// net there. A pool-wide comparison drops it (no identical column is in the design, so nothing justifies the drop).
    func testPileUpAtAnInactivePoolGroupsOneComponentEnergyKeepsItsSumColumn() throws {
        let sum = XRayLines.line("Tb_Ma")!.energy + XRayLines.line("Ir_Ma")!.energy
        let w = try XCTUnwrap(XRayLines.fwhm(resolutionMnKaEV: 130, atEnergy: sum), "the law's FWHM at the pile-up energy")
        let counts = Self.spectrum(Self.shortAxis, areas: ["Tb_Ma": 40000, "Ir_Ma": 40000, "V_Ka": 0],
                                   planted: [(energy: sum, area: 2000, fwhm: w)], seed: 25)
        let r = try ElementProposer(pool: ["Tb", "Ir", "V", "Mg", "Al", "Fe"])
            .propose(counts: counts, axis: Self.shortAxis, settings: Self.settings(Self.shortAxis))
        let pileUp = r.sumPeaks.filter { abs($0.energyKeV - sum) <= LineConflicts.sumPeakToleranceKeV }
        XCTAssertEqual(pileUp.count, 1, "one column at the Tb + Ir energy; sum peaks: \(r.sumPeaks.map { ($0.label, $0.net) })")
        let column = try XCTUnwrap(pileUp.first)
        XCTAssertEqual(Set(column.elements), ["Tb", "Ir"], "the column is the Tb + Ir pair, not V's escape")
        XCTAssertGreaterThan(column.net, 0, "the planted pile-up is fitted with a positive net")
    }

    // MARK: P3: a one-LINE group is not compared (La K-alpha = Cd K-alpha + Tl L-alpha)

    /// La K-alpha 33.4419 keV = Cd K-alpha 23.1737 + Tl L-alpha 10.2682, and La's K group is the single line K-alpha on an axis that
    /// tops out between K-alpha and K-beta (33.5 to 37.8 keV; here 35.98; the fit range must be the Expert one, to the axis top).
    /// The held patch's LINE branch would have dropped the pile-up pair at La's energy and let La's column take its counts (a false
    /// La); the owner chose against it (card A1, option a), so the rule compares ESCAPE columns only. Measured on HEAD before the
    /// change (registration, addendum): a planted pile-up of 120 to 200 counts, which La absorbs without reaching L_D (not claiming),
    /// throws `rankDeficient`; with the line branch the same runs complete with La at net 106 to 185. Pinned: 160 counts throws the
    /// clear error; with none planted the Cd + Tl pair keeps its column (net 0) beside La (net 54, below L_D); at 2 000 La claims
    /// the energy and is a sum-peak question. La is never in `proposed`.
    func testLaKaEqualToCdKaPlusTlLaIsNotDroppedAndNeverProposesLa() throws {
        let sum = XRayLines.line("Cd_Ka")!.energy + XRayLines.line("Tl_La")!.energy
        XCTAssertEqual(sum, XRayLines.line("La_Ka")!.energy, accuracy: 1e-6, "the premise: the pile-up energy is La K-alpha")
        let axis = EnergyAxis(offset: 0, scale: 0.02, size: 1800)
        XCTAssertLessThan(axis.energy(ofChannel: axis.size - 1), XRayLines.line("La_Kb")!.energy, "the premise: La K-beta is off the axis")
        let g = EDSLineModel.build(elements: ["La"], axis: axis, beamEnergy: 200, resolutionMnKaEV: 130).groups.first { $0.id == "La_Ka" }!
        XCTAssertEqual(g.lines.count, 1, "the premise: La's K group is one Gaussian on this axis")
        let w = try XCTUnwrap(XRayLines.fwhm(resolutionMnKaEV: 130, atEnergy: sum))
        // The default fit range stops at 20 keV, where La K-alpha is out of range; the coincidence needs the Expert range to the axis top.
        var settings = Self.settings(axis)
        settings.fitTo = axis.energy(ofChannel: axis.size - 1)
        func run(pileUp area: Double) throws -> ProposalResult {
            let counts = Self.spectrum(axis, areas: ["Cd_Ka": 40000, "Tl_La": 40000],
                                       planted: area > 0 ? [(energy: sum, area: area, fwhm: w)] : [], seed: 26)
            return try ElementProposer(pool: ["Cd", "Tl", "La", "Mg", "Al", "Fe"]).propose(counts: counts, axis: axis, settings: settings)
        }
        XCTAssertThrowsError(try run(pileUp: 160), "La active but not claiming: the pair stays a column identical to La's, a clear error") {
            XCTAssertEqual($0 as? ProposerError, .rankDeficient)
        }
        let none = try run(pileUp: 0)
        XCTAssertFalse(none.proposed.contains { $0.element == "La" }, "no pile-up: La is not proposed")
        XCTAssertTrue(none.sumPeaks.contains { abs($0.energyKeV - sum) <= LineConflicts.sumPeakToleranceKeV && Set($0.elements) == ["Cd", "Tl"] },
                      "no pile-up planted: the Cd + Tl pair keeps its column at La's energy; sum peaks: \(none.sumPeaks.map(\.label))")
        let big = try run(pileUp: 2000)
        XCTAssertFalse(big.proposed.contains { $0.element == "La" }, "La is never proposed from the Cd + Tl pile-up")
        XCTAssertTrue(big.sumPeakQuestions.contains { $0.element == "La" }, "La claims the energy and is a sum-peak question")
    }

    // MARK: Multi-line groups keep their pile-up column

    /// Tb L-alpha 6.2728 = Sr L-alpha + Ba L-alpha. Tb's group has nine lines, so its column is not one Gaussian and the
    /// pile-up column at its energy stays (Tb at 300 counts is in the window, not claiming). The rule must not fire here.
    func testSrPlusBaSumAtAMultiLineGroupsAlphaKeepsItsColumn() throws {
        let sum = XRayLines.line("Sr_La")!.energy + XRayLines.line("Ba_La")!.energy
        XCTAssertEqual(sum, XRayLines.line("Tb_La")!.energy, accuracy: 1e-6, "the premise")
        let counts = Self.spectrum(Self.axis, areas: ["Sr_La": 40000, "Ba_La": 40000, "Tb_La": 300], seed: 21)
        let r = try ElementProposer(pool: ["Sr", "Ba", "Tb", "Mg", "Al", "Fe"])
            .propose(counts: counts, axis: Self.axis, settings: Self.settings(Self.axis))
        let col = try XCTUnwrap(r.sumPeaks.first { abs($0.energyKeV - sum) <= LineConflicts.sumPeakToleranceKeV },
                                "a column at the Sr+Ba energy; labels: \(r.sumPeaks.map(\.label))")
        XCTAssertEqual(Set(col.elements), ["Sr", "Ba"])
    }
}
