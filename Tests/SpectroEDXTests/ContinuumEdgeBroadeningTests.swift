//
//  ContinuumEdgeBroadeningTests.swift
//  Role: The continuum's step at the Al K edge (sharp default, opt-in broadened) on a spectrum whose edge is seen through the detector, as a real one is: a
//        Kramers continuum absorbed by an Al film (FFAST mu/rho), then convolved with the detector's Gaussian, plus Al K (and a weak
//        Si K) line. Noise-free and generated here; no measured spectrum is committed.
//
//  Why: on a measured pure-Al spectrum (Titan, Super-X) the default fit dropped the continuum by about 770 counts between two
//  adjacent channels at the edge while the data were smooth, and sat 39 % above the data in 1.65-2.2 keV, under Si K-alpha.
//  A detector cannot record a sharp step: every channel is the incoming spectrum convolved with its resolution (about 75 eV FWHM
//  at 1.56 keV for 128 eV at Mn K-alpha), so the model's step has to be broadened the same way (`ContinuumEdgeStep.broadened`).
//

import Foundation
import Testing
import SpectroCore
@testable import SpectroEDX

struct ContinuumEdgeBroadeningTests {

    private static let axis = EnergyAxis(offset: 0, scale: 0.005, size: 4000)   // 0 to 19.995 keV
    private static let energies = (0..<axis.size).map { axis.energy(ofChannel: $0) }
    private static let resolution = 128.0
    private static let beam = 200.0

    /// The Al film's mass thickness, g/cm2: chi = m mu/rho is 0.36 just above the edge (a 30 % step) and 0.05 below it.
    private static let massThickness = 9e-5

    /// The continuum reaching the detector (before its resolution): Kramers x a smooth window roll-off x the film's transmission.
    private static func incoming(_ e: Double) -> Double {
        guard e >= 0.1 else { return 0 }
        let table = MassAbsorptionTable.bundled!
        let mu = (try? table.mac(element: "Al", energyKeV: e)) ?? 0
        return 9.0 * (beam - e) / e * exp(-pow(0.35 / e, 2.2)) * exp(-massThickness * mu)
    }

    /// `incoming` convolved with the detector's Gaussian, sigma from the line-width law at each energy (counts per channel).
    private static let continuum: [Double] = {
        let raw = energies.map(incoming)
        return energies.indices.map { i in
            let e = energies[i]
            let fwhm = XRayLines.fwhm(resolutionMnKaEV: resolution, atEnergy: max(e, 0.3)) ?? resolution / 1000
            let sigma = fwhm / (8 * log(2.0)).squareRoot()
            let reach = Int((5 * sigma / axis.scale).rounded(.up))
            var sum = 0.0, wsum = 0.0
            for j in max(0, i - reach)...min(axis.size - 1, i + reach) {
                let w = exp(-0.5 * pow((energies[j] - e) / sigma, 2))
                sum += w * raw[j]; wsum += w
            }
            return sum / wsum
        }
    }()

    private static func lineColumn(_ id: String) -> [Double] {
        let el = String(id.prefix { $0 != "_" })
        let g = EDSLineModel.build(elements: [el], axis: axis, beamEnergy: beam, resolutionMnKaEV: resolution).groups.first { $0.id == id }!
        return EDSLineModel.column(of: g.lines, energies: energies, scale: axis.scale)
    }

    private static let alArea = 3e5, siArea = 2e3

    private static func spectrum(si: Bool) -> [Double] {
        let al = lineColumn("Al_Ka"), s = lineColumn("Si_Ka")
        return energies.indices.map { continuum[$0] + alArea * al[$0] + (si ? siArea * s[$0] : 0) }
    }

    private static func fit(_ counts: [Double], elements: [String], step: ContinuumEdgeStep) throws -> EDSFitResult {
        var policy = FitPolicy()
        policy.continuumEdgeStep = step
        let s = FitSettings.standard(elements: elements, axis: axis, resolutionMnKaEV: resolution, beamEnergy: beam, policy: policy)
        return try EDSFit.run(counts: counts, axis: axis, settings: s, computeCovariance: false)
    }

    /// Data minus model summed over [lo, hi) keV, and the data there.
    private static func band(_ f: EDSFitResult, _ counts: [Double], _ lo: Double, _ hi: Double) -> (residual: Double, data: Double) {
        var r = 0.0, d = 0.0
        for (j, c) in f.channels.enumerated() where energies[c] >= lo && energies[c] < hi { r += f.residual[j]; d += counts[c] }
        return (r, d)
    }

    private static func worstChannel(_ f: EDSFitResult, _ counts: [Double]) -> Double {
        var worst = 0.0
        for (j, c) in f.channels.enumerated() where energies[c] >= 1.50 && energies[c] < 1.70 { worst = max(worst, abs(f.residual[j]) / counts[c]) }
        return worst
    }

    /// Pure Al, no Si. Broadened: the model in 1.65-2.2 keV (under Si K-alpha) within 0.3 % of the data, and no channel in
    /// 1.50-1.70 keV off by 4 % or more. The sharp step fails both on the same spectrum (measured: 0.95 % and 5.5 %), which is the
    /// defect this form exists for. Measured broadened: 0.06 % and 3.3 % (the rest is the order-5 segment above the edge).
    @Test func testTheBroadenedStepFollowsAResolutionBroadenedAlEdgeAndTheSharpDoesNot() throws {
        let counts = Self.spectrum(si: false)
        let broad = try Self.fit(counts, elements: ["Al"], step: .broadened)
        let sharp = try Self.fit(counts, elements: ["Al"], step: .sharp)
        let ab = Self.band(broad, counts, 1.65, 2.2), asharp = Self.band(sharp, counts, 1.65, 2.2)
        let wb = Self.worstChannel(broad, counts), ws = Self.worstChannel(sharp, counts)
        print(String(format: "EDGE pure Al 1.65-2.2 keV: broadened %+.2f %%, sharp %+.2f %%; worst channel 1.50-1.70: broadened %.2f %%, sharp %.2f %%",
                     ab.residual / ab.data * 100, asharp.residual / asharp.data * 100, wb * 100, ws * 100))
        #expect(abs(ab.residual) / ab.data < 0.003, "broadened 1.65-2.2 keV: \(ab.residual) of \(ab.data)")
        #expect(wb < 0.04, "broadened worst channel \(wb)")
        #expect(abs(asharp.residual) / asharp.data >= 0.003 || ws >= 0.04, "the sharp step misfits the broadened edge: \(asharp.residual), \(ws)")
    }

    /// A weak Si K-alpha (2000 counts against 3e5 Al K-alpha) above the broadened edge: the sharp step reads it 38.7 % low, the
    /// broadened one 25.4 % low (measured). Held: the broadened bias is at most 0.75 of the sharp one, and both are pinned within
    /// 2 points so a change either way is looked at. The remaining bias is the order-5 segment above the edge (orders (9, 9) read
    /// -8 %), stated, not asserted away; results stay unvalidated.
    @Test func testAWeakSiLineAboveTheBroadenedEdgeReadsCloserWithTheBroadenedStep() throws {
        let counts = Self.spectrum(si: true)
        func si(_ step: ContinuumEdgeStep) throws -> Double {
            let f = try Self.fit(counts, elements: ["Al", "Si"], step: step)
            return f.values[try #require(f.groupIDs.firstIndex(of: "Si_Ka"))] / Self.siArea - 1
        }
        let b = try si(.broadened), s = try si(.sharp)
        print(String(format: "EDGE Si bias: broadened %+.2f %%, sharp %+.2f %%", b * 100, s * 100))
        #expect(abs(b) <= 0.75 * abs(s), "broadened \(b) vs sharp \(s)")
        #expect(abs(b - -0.254) < 0.02, "broadened Si bias \(b)")
        #expect(abs(s - -0.387) < 0.02, "sharp Si bias \(s)")
    }

    /// `.sharp` is the default and the form without the broadening: the same columns as a call with no resolution.
    @Test func testTheSharpStepIsTheDefaultAndTheUnbroadenedForm() {
        let e = Array(Self.energies[40..<4000])
        let sharp = ContinuumForm(beamEnergy: Self.beam)
        let broad = ContinuumForm(beamEnergy: Self.beam, edgeStep: .broadened)
        #expect(sharp.edgeStep == .sharp)
        #expect(sharp.columns(energies: e, resolutionMnKaEV: Self.resolution).values == sharp.columns(energies: e).values)
        #expect(broad.columns(energies: e).values == sharp.columns(energies: e).values, "no resolution: the sharp form")
        #expect(sharp.columns(energies: e, resolutionMnKaEV: Self.resolution).values != broad.columns(energies: e, resolutionMnKaEV: Self.resolution).values)
        #expect(sharp != broad)
        #expect(!sharp.label.contains("broadened") && broad.label.contains("broadened"))
        // Without an edge inside the range the two forms are the same.
        let low = Array(Self.energies[40..<300])   // 0.2-1.5 keV
        #expect(sharp.columns(energies: low, resolutionMnKaEV: Self.resolution).values == broad.columns(energies: low, resolutionMnKaEV: Self.resolution).values)
    }

    /// With every coefficient 1 the Bernstein sums are 1 on both segments, so the broadened continuum equals the sharp one
    /// (Kramers / kRef): the weights sum to 1. Every column is non-negative and finite.
    @Test func testTheBroadenedWeightsSumToOne() {
        let e = Array(Self.energies[40..<4000])
        let broad = ContinuumForm(beamEnergy: Self.beam, edgeStep: .broadened).columns(energies: e, resolutionMnKaEV: Self.resolution).values
        let sharp = ContinuumForm(beamEnergy: Self.beam).columns(energies: e).values
        for i in e.indices {
            let b = broad.reduce(0) { $0 + $1[i] }, s = sharp.reduce(0) { $0 + $1[i] }
            #expect(abs(b - s) <= 1e-12 * max(abs(s), 1), "channel \(i): \(b) vs \(s)")
        }
        #expect(broad.allSatisfy { $0.allSatisfy { $0 >= 0 && $0.isFinite } })
    }

    /// Two close edges (90 eV apart, under three sigma): the weights still sum to 1 (they telescope; a product would over-count between).
    @Test func testTheBroadenedWeightsSumToOneWithTwoCloseEdges() {
        let e = Array(Self.energies[40..<4000])
        let edges = [1.5596, 1.65]
        let broad = ContinuumForm(beamEnergy: Self.beam, edges: edges, orders: [9, 3, 5], edgeStep: .broadened)
            .columns(energies: e, resolutionMnKaEV: Self.resolution).values
        let sharp = ContinuumForm(beamEnergy: Self.beam, edges: edges, orders: [9, 3, 5]).columns(energies: e).values
        for i in e.indices {
            let b = broad.reduce(0) { $0 + $1[i] }, s = sharp.reduce(0) { $0 + $1[i] }
            #expect(abs(b - s) <= 1e-12 * max(abs(s), 1), "channel \(i): \(b) vs \(s)")
        }
        #expect(broad.allSatisfy { $0.allSatisfy { $0 >= 0 && $0.isFinite } })
    }

    /// The policy: default `.sharp`, named in the footer when `.broadened`, and a stored policy without the field reads `.sharp`.
    @Test func testThePolicyDefaultsToSharpAndOldStoredPoliciesReadIt() throws {
        #expect(FitPolicy.default.continuumEdgeStep == .sharp)
        // The default policy's canonical JSON is what it was before the field existed: the key is written only when not the default.
        #expect(!QuantificationPolicy.default.canonicalJSON.contains("continuumEdgeStep"))
        var broad = QuantificationPolicy()
        broad.fit.continuumEdgeStep = .broadened
        #expect(broad.footerLine?.contains("continuumEdgeStep = broadened") == true, "\(broad.footerLine ?? "nil")")
        let round = try JSONDecoder().decode(QuantificationPolicy.self, from: Data(broad.canonicalJSON.utf8))
        #expect(round == broad)
        var json = try #require(try JSONSerialization.jsonObject(with: Data(QuantificationPolicy.default.canonicalJSON.utf8)) as? [String: Any])
        var fit = try #require(json["fit"] as? [String: Any])
        fit.removeValue(forKey: "continuumEdgeStep")
        json["fit"] = fit
        let old = try JSONDecoder().decode(QuantificationPolicy.self, from: try JSONSerialization.data(withJSONObject: json))
        #expect(old == .default)
        let settings = FitSettings.standard(elements: ["Al"], axis: Self.axis, resolutionMnKaEV: Self.resolution, beamEnergy: Self.beam,
                                            policy: broad.fit)
        guard case .continuum(let form) = settings.background else { Issue.record("no continuum"); return }
        #expect(form.edgeStep == .broadened)
    }
}
