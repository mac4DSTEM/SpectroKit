//
//  WindowGateTests.swift
//  Role: The window method against exSpy (registration section 4, item 3 "lines", and Gate D5): integration and background
//        windows, merged and unmerged, and `get_lines_intensity` on every planted spectrum (430 noise-free means and 3950
//        realisations), with and without background windows. Agreement required: windows exact, intensities relative <= 1e-12.
//

import Foundation
import Testing
import SpectroTestSupport
import SpectroCore
import SpectroEDX

struct WindowGateTests {

    private func lines(_ ids: [String], r: Double) throws -> [SpectralLine] { try ids.map { try SpectralLine(id: $0, resolutionMnKaEV: r) } }

    /// estimate_integration_windows (factor 2.0) and estimate_background_windows (merged and one line at a time) for the
    /// planted line lists at R_MnKa 125 / 130 / 140 / 150: equal to exSpy's, as stored (Python reprs round-trip).
    @Test func testWindowsEqualExSpy() throws {
        let wins = EDXFixtures.pins.d("lines").l("windows")
        #expect(wins.count == 16)
        var worst = 0.0
        for w in wins {
            let ids = w["lines"] as! [String]
            let ls = try lines(ids, r: w.x("R_MnKa"))
            func flat(_ a: Any) -> [[Double]] { (a as! [[NSNumber]]).map { $0.map(\.doubleValue) } }
            let tag = "R \(w.x("R_MnKa")) \(ids)"
            let integ = WindowIntensity.integrationWindows(lines: ls)
            let merged = BackgroundWindows.estimate(lines: ls)
            let unmerged = ls.map { BackgroundWindows.estimate(lines: [$0])[0] }
            for (got, want, what) in [(integ, flat(w["integration"]!), "integration"), (merged, flat(w["background_merged"]!), "merged"),
                                      (unmerged, flat(w["background_unmerged"]!), "unmerged")] {
                #expect(got.count == want.count, "\(tag) \(what)")
                for (g, e) in zip(got, want) {
                    #expect(g.count == e.count)
                    for (a, b) in zip(g, e) {
                        worst = max(worst, abs(a - b))
                        #expect(a == b, "\(tag) \(what)")
                    }
                }
            }
        }
        gateNote("EDX windows: 16 line lists x (integration, merged, unmerged) equal exSpy, max |difference| \(worst) keV")
    }

    /// One spectrum's six intensities as exSpy's `get_lines_intensity`: with the merged background windows (Al, Mg, Si), then
    /// the plain integration windows. Integer spectra go through the shipped `netCounts`; the float noise-free mean through the
    /// same window resolution and a plain double sum (netCounts takes counts).
    private struct Windows {
        let withBG: [ResolvedWindow], without: [ResolvedWindow]
        init() throws {
            let axis = EDXFixtures.axis
            let ls = try ["Al_Ka", "Mg_Ka", "Si_Ka"].map { try SpectralLine(id: $0, resolutionMnKaEV: 130) }
            let integ = WindowIntensity.integrationWindows(lines: ls)
            let bg = BackgroundWindows.estimate(lines: ls)
            withBG = try ls.indices.map { try WindowIntensity.resolve(integration: integ[$0], background: bg[$0], axis: axis) }
            without = try ls.indices.map { try WindowIntensity.resolve(integration: integ[$0], background: nil, axis: axis) }
        }
        func intensities(_ counts: [Double], integer: Bool) -> [Double] {
            if integer {
                let u = counts.map { UInt64($0) }
                return WindowIntensity.netCounts(spectrum: u, windows: withBG) + WindowIntensity.netCounts(spectrum: u, windows: without)
            }
            func net(_ w: ResolvedWindow) -> Double {
                func sum(_ r: Range<Int>) -> Double { r.reduce(0.0) { $0 + counts[$1] } }
                guard let b = w.background else { return sum(w.signal) }
                return sum(w.signal) - (sum(b.left) + sum(b.right)) * b.scale
            }
            return withBG.map(net) + without.map(net)
        }
    }

    /// get_lines_intensity on every planted spectrum: relative 1e-12 (integer spectra: sums of integers and one division).
    @Test func testLineIntensitiesEqualExSpyOnEveryPlantedSpectrum() throws {
        let w = try Windows()
        let pin = EDXFixtures.pins.d("lines").d("intensity")
        #expect(EDXFixtures.sha256(try Data(contentsOf: EDXFixtures.url("edx-pins-intensity.f64"))) == pin.s("sha256"))
        let values = EDXFixtures.data("edx-pins-intensity.f64", as: Double.self)
        let shape = (pin["shape"] as! [NSNumber]).map(\.intValue)
        #expect(values.count == (shape[0] * shape[1]))
        struct Entry: Sendable { let cell: String, row0: Int, n: Int }
        let map = pin.l("cells").map { Entry(cell: $0.s("cell"), row0: $0.i("row0"), n: $0.i("n")) }
        #expect(map.count == EDXFixtures.cells.count)
        var n = 0
        var worstRel = 0.0
        let results = parallelMap(map.count) { ci -> (Int, Double) in
            let m = map[ci]
            let c = EDXFixtures.cellByID[m.cell]!
            var worst = 0.0, count = 0
            for j in 0..<m.n {
                let spec = j == 0 ? EDXFixtures.meanSpectrum(c) : EDXFixtures.realisation(c, j - 1)
                let got = w.intensities(spec, integer: j > 0)
                for col in 0..<6 {
                    let want = values[(m.row0 + j) * 6 + col]
                    let scale = max(abs(want), 1e-9 * max(1.0, abs(got[col])))   // float means: summation order, see below
                    worst = max(worst, abs(got[col] - want) / (j > 0 ? max(abs(want), 1e-300) : scale))
                    count += 1
                }
            }
            return (count, worst)
        }
        for (c, wr) in results { n += c; worstRel = max(worstRel, wr) }
        gateNote("EDX window intensities: \(n) values (430 cells, means and realisations, 6 columns) vs exSpy, worst relative difference \(worstRel)")
        #expect(n == (shape[0] * 6))
        #expect(worstRel <= (1e-12))
    }

    // MARK: D5

    /// Gate D5 (the window method for the maps, a separate fault): the window net for Mg at rho_Mg = 0 on set U130 at N_Al 1e6.
    /// Registration: "Refuted if the SpectroKit window net for Mg at rho_Mg = 0 is within +-2 sd of zero at 1e6 (exSpy's is
    /// -9.6 sd). Predicted: equals exSpy's". The numbers are reported; the equality with exSpy is the assertion
    /// (testLineIntensitiesEqualExSpyOnEveryPlantedSpectrum), here the per-cell mean and sd.
    @Test func testD5WindowBiasOfMgAtZeroMg() throws {
        let w = try Windows()
        for (id, label) in [("U130.s.N6.rho0p0", "U130 s 1e6"), ("U130.L.N6.rho0p0", "U130 L 1e6"), ("U130.s.N7.rho0p0", "U130 s 1e7"),
                            ("U130.s.N5.rho0p0", "U130 s 1e5")] {
            let c = EDXFixtures.cellByID[id]!
            let nets = (0..<c.nReal).map { w.intensities(EDXFixtures.realisation(c, $0), integer: true)[1] }
            let mean = nets.reduce(0, +) / Double(nets.count)
            let sd = (nets.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(nets.count - 1)).squareRoot()
            let meanSpec = w.intensities(EDXFixtures.meanSpectrum(c), integer: false)[1]
            gateNote("EDX D5 \(label): Mg window net at rho 0: mean \(mean) sd \(sd) (n \(nets.count)); mean/sd \(mean / sd); noise-free \(meanSpec); mean/(sd) of the mean \(mean / (sd / Double(nets.count).squareRoot()))")
            if id == "U130.s.N6.rho0p0" {
                #expect(mean < (-2 * sd), "the Mg window net is biased low by more than 2 sd of a realisation at 1e6 (exSpy's: -9.6 sd of the mean)")
            }
        }
    }
}
