//
//  SumEscapeFitTests.swift
//  Role: the optional sum-peak and common-escape-fraction components of the EDS fit (SpectroKit 0.10.0). There is no Python
//        reference (eXSpy's EDSModel has neither), so every test is against PLANTED truth: a spectrum built from the fit's own line
//        columns with known areas, a known pile-up coefficient c and a known escape fraction f, noise-free and with seeded
//        Poisson counts. The model is `validation: "none"`.
//

import Foundation
import Testing
import SpectroTestSupport
import SpectroCore
import SpectroEDX

struct SumEscapeFitTests {

    private static let axis = EnergyAxis(offset: 0, scale: 0.01, size: 2000)   // 0 to 20 keV
    private static let elements = ["Al", "Ag", "Fe"]
    private static let areas: [String: Double] = ["Al_Ka": 300_000, "Ag_La": 2_000, "Fe_Ka": 100_000]
    private static let trueC = 1e-8
    private static let trueF = 0.01

    private static func settings() -> FitSettings {
        FitSettings.standard(elements: elements, axis: axis, resolutionMnKaEV: 130, beamEnergy: 200)
    }

    /// The planted mean spectrum: a Kramers-type continuum, the three line groups, their escape copies (fraction f of each parent
    /// group above the Si K edge) and the pile-up peaks (c m A_i A_j at E_i + E_j) of the parents `Al_Ka`, `Fe_Ka`.
    private static func planted(c: Double = trueC, f: Double = trueF) -> [Double] {
        let energies = (0..<axis.size).map { axis.energy(ofChannel: $0) }
        var mu = energies.map { e -> Double in
            let x = max(e, 0.05)
            return e >= 0.2 ? 2.0 * max(200 - e, 0) / x * exp(-pow(0.3 / x, 3)) / 40 : 0
        }
        let model = EDSLineModel.build(elements: elements, axis: axis, beamEnergy: 200, resolutionMnKaEV: 130, escapePeaks: true)
        for g in model.groups {
            guard let a = areas[g.id] else { continue }
            let col = EDSLineModel.column(of: g.lines, energies: energies, scale: axis.scale)
            for i in mu.indices { mu[i] += a * col[i] }
            if !g.escapes.isEmpty {
                let ec = EDSLineModel.column(of: g.escapes, energies: energies, scale: axis.scale)
                for i in mu.indices { mu[i] += f * a * ec[i] }
            }
        }
        let parents = ["Al_Ka", "Fe_Ka"]
        for (a, ia) in parents.enumerated() { for ib in a..<parents.count {
            let ga = model.groups.first { $0.id == ia }!, gb = model.groups.first { $0.id == parents[ib] }!
            let e = ga.lines[0].energy + gb.lines[0].energy
            let w = XRayLines.fwhm(resolutionMnKaEV: 130, atEnergy: e)!
            let col = EDSLineModel.column(of: [FitLine(id: "s", energy: e, weight: 1, fwhm: w)], energies: energies, scale: axis.scale)
            let amp = c * (a == ib ? 1 : 2) * areas[ia]! * areas[parents[ib]]!
            for i in mu.indices { mu[i] += amp * col[i] }
        } }
        return mu
    }

    private static func poisson(_ mu: [Double], seed: UInt64) -> [Double] {
        var rng = Xoshiro256StarStar(seed: seed)
        return mu.map { rng.poisson($0) }
    }

    @Test func offByDefaultIsTheBaselineBitForBit() throws {
        let y = Self.planted()
        let s = Self.settings()
        let r = try EDSSumEscapeFit.run(counts: y, axis: Self.axis, settings: s, model: SumEscapeModel())
        let plain = try EDSFit.run(counts: y, axis: Self.axis, settings: s)
        #expect(r.fit.values == plain.values)
        #expect(r.fit.model == plain.model)
        #expect(r.fit.covariance.map(\.bitPattern) == plain.covariance.map(\.bitPattern))
        #expect(r.sumCoefficient == nil && r.escapeFraction == nil && r.validation == "none")
    }

    @Test func noiseFreePlantedCoefficientsAreRecoveredAndTheWeakLineIsFixed() throws {
        let y = Self.planted()
        let s = Self.settings()
        let r = try EDSSumEscapeFit.run(counts: y, axis: Self.axis, settings: s, model: .both)
        #expect(r.converged)
        let c = try #require(r.sumCoefficient), f = try #require(r.escapeFraction)
        #expect(abs(c - Self.trueC) / Self.trueC < 0.02, "c \(c)")
        #expect(abs(f - Self.trueF) / Self.trueF < 0.02, "f \(f)")
        let ag = try #require(r.fit.groupIDs.firstIndex(of: "Ag_La"))
        let truth = Self.areas["Ag_La"]!
        let before = abs(r.baseline.values[ag] - truth), after = abs(r.fit.values[ag] - truth)
        #expect(before > 0.2 * truth, "the baseline should be biased by the Al+Al sum peak; it is off by \(before)")
        #expect(after < 0.02 * truth, "with the model the Ag area is off by \(after)")
        #expect(r.sumPeaks.contains { $0.label == "Al_Ka + Al_Ka" })
        #expect(r.validation == "none")
        #expect(!r.parameters.isEmpty)
    }

    @Test func noisyPlantedCoefficientsAndNetCountsImprove() throws {
        let s = Self.settings()
        var improved = 0
        var cs: [Double] = [], sigmas: [Double] = []
        let truth = Self.areas["Ag_La"]!
        for seed in 1...20 {
            let y = Self.poisson(Self.planted(), seed: UInt64(seed))
            let r = try EDSSumEscapeFit.run(counts: y, axis: Self.axis, settings: s, model: .both)
            let ag = try #require(r.fit.groupIDs.firstIndex(of: "Ag_La"))
            if abs(r.fit.values[ag] - truth) < abs(r.baseline.values[ag] - truth) { improved += 1 }
            cs.append(try #require(r.sumCoefficient))
            sigmas.append(try #require(r.sumCoefficientSigma))
        }
        #expect(improved == 20)
        let mean = cs.reduce(0, +) / Double(cs.count)
        let sd = (cs.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(cs.count - 1)).squareRoot()
        let meanSigma = sigmas.reduce(0, +) / Double(sigmas.count)
        #expect(abs(meanSigma / sd - 1) < 0.25, "sigma_c \(meanSigma) against the spread \(sd)")
        #expect(abs(mean - Self.trueC) / Self.trueC < 0.05, "mean c \(mean)")
    }

    @Test func fixedCoefficientsAreUsedAsGiven() throws {
        let y = Self.planted()
        let r = try EDSSumEscapeFit.run(counts: y, axis: Self.axis, settings: Self.settings(),
                                        model: SumEscapeModel(sumPeaks: true, sumCoefficient: Self.trueC, commonEscapeFraction: true, escapeFraction: Self.trueF))
        #expect(r.sumCoefficient == Self.trueC && r.escapeFraction == Self.trueF)
        let ag = try #require(r.fit.groupIDs.firstIndex(of: "Ag_La"))
        #expect(abs(r.fit.values[ag] - 2000) < 20)
    }

    @Test func noSumPeaksInTheDataGivesZeroCoefficient() throws {
        let y = Self.planted(c: 0, f: 0)
        let r = try EDSSumEscapeFit.run(counts: y, axis: Self.axis, settings: Self.settings(), model: .both)
        #expect((r.sumCoefficient ?? 1) < 1e-10)
        #expect((r.escapeFraction ?? 1) < 1e-4)
    }

    @Test func refusals() {
        let y = Self.planted()
        #expect(throws: SumEscapeError.self) {
            _ = try EDSSumEscapeFit.run(counts: y, axis: Self.axis, settings: Self.settings(), model: SumEscapeModel(sumPeaks: true, parentCount: 0))
        }
        #expect(throws: SumEscapeError.self) {
            _ = try EDSSumEscapeFit.run(counts: y, axis: Self.axis, settings: Self.settings(), model: SumEscapeModel(sumPeaks: true, sumCoefficient: -1))
        }
        #expect(throws: SumEscapeError.self) {
            _ = try EDSSumEscapeFit.run(counts: y, axis: Self.axis, settings: Self.settings(), model: SumEscapeModel(commonEscapeFraction: true, escapeFraction: 1.5))
        }
    }

    @Test func theQuantifyRunTakesTheModelAndNamesItInTheFooter() throws {
        let y = Self.planted().map { UInt64($0.rounded()) }
        var m = QuantificationMethod()
        m.elements = Self.elements.map { QuantificationMethod.ElementState(symbol: $0, role: .quantify, isManual: false) }
        m.beamEnergyKeV = 200
        m.lockEnergyAxis = true
        let meta = SpectrumImageMetadata(fileName: "planted", filePath: "", scanWidth: 1, scanHeight: 1, channelCount: Self.axis.size,
                                         energyOffsetEV: 0, energyDispersionEV: 10)
        let tables = QuantificationTables.bundled()
        var input = PooledQuantificationInput(counts: y, axis: Self.axis, method: m, metadata: meta, regionName: "planted", pixelCount: 1)
        let plain = try PooledQuantifier.run(input, tables: tables)
        #expect(!plain.footerLines.contains { $0.hasPrefix("sum peaks") })
        input.sumEscape = .both
        let on = try PooledQuantifier.run(input, tables: tables)
        #expect(on.footerLines.contains { $0.hasPrefix("sum peaks") })
        let truth = Self.areas["Ag_La"]!
        let ag = try #require(on.rows.first { $0.element == "Ag" }), agPlain = try #require(plain.rows.first { $0.element == "Ag" })
        #expect(abs(ag.net - truth) < 0.1 * abs(agPlain.net - truth))
    }
}
