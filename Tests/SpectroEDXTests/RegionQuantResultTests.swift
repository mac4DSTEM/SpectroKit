//
//  RegionQuantResultTests.swift
//  Role: the per-region quantification result (SpectroKit 0.10.0): built from a finished pooled quantification of a planted
//        spectrum (typed k imported from text), it carries every number of the pooled rows unchanged plus the region, the k source
//        and values, the absorption note, the method hash, the unlisted-line outcome and the validation; it survives a Codable round
//        trip, and its CSV row lines up with its header. Planted truth only: the sums of the fit's own Gaussian columns.
//

import Foundation
import Testing
import SpectroCore
import SpectroEDX

struct RegionQuantResultTests {

    private static let axis = EnergyAxis(offset: 0, scale: 0.01, size: 1500)

    private static func planted() -> [UInt64] {
        let energies = (0..<axis.size).map { axis.energy(ofChannel: $0) }
        var mu = energies.map { e -> Double in
            let x = max(e, 0.05)
            return e >= 0.2 ? 0.4 * max(200 - e, 0) / x * exp(-pow(0.3 / x, 3)) : 0
        }
        let areas = ["Al_Ka": 30000.0, "Mg_Ka": 4000.0, "Si_Ka": 12000.0]
        let model = EDSLineModel.build(elements: ["Al", "Mg", "Si"], axis: axis, beamEnergy: 200, resolutionMnKaEV: 130, escapePeaks: true)
        for g in model.groups {
            guard let a = areas[g.id] else { continue }
            let col = EDSLineModel.column(of: g.lines, energies: energies, scale: axis.scale)
            for i in mu.indices { mu[i] += a * col[i] }
        }
        return mu.map { UInt64($0.rounded()) }
    }

    private static func quantification(region: String = "Matrix, left") throws -> PooledQuantification {
        var m = QuantificationMethod()
        m.elements = ["Al", "Mg", "Si"].map { QuantificationMethod.ElementState(symbol: $0, role: .quantify, isManual: false) }
        m.beamEnergyKeV = 200
        m.lockEnergyAxis = true
        let table = try KFactorImport.parse("Element\tLine\tk\tSigma\nAl\tKa\t1.00\t0\nMg\tKa\t1.20\t0.12\nSi\tKa\t1.10\t0.055\n")
        try KFactorImport.apply(table, to: &m, source: "Velox export, planted", date: "2026-10-22", reference: "Al")
        let meta = SpectrumImageMetadata(fileName: "planted", filePath: "", scanWidth: 1, scanHeight: 1, channelCount: axis.size,
                                         energyOffsetEV: 0, energyDispersionEV: 10)
        let input = PooledQuantificationInput(counts: planted(), axis: axis, method: m, metadata: meta, regionName: region, pixelCount: 24)
        return try PooledQuantifier.run(input, tables: QuantificationTables.bundled())
    }

    @Test func carriesTheRowsTheKSourceTheHashAndTheValidation() throws {
        let q = try Self.quantification()
        let r = RegionQuantResult.make(from: q, regionName: "Matrix, left", pixelCount: 24)
        #expect(r.regionName == "Matrix, left" && r.pixelCount == 24)
        #expect(r.elements == ["Al", "Mg", "Si"])
        #expect(r.validation == "none")
        for (l, row) in zip(r.lines, q.rows) {
            #expect(l.netCounts == row.net && l.netSigma == row.sigma && l.line == row.groupID)
            #expect(l.weightPercent == row.weightPercent && l.weightSigma == row.weightSigma)
            #expect(l.atomicPercent == row.atomicPercent && l.atomicSigma == row.atomicSigma)
            #expect(l.weightPercent != nil && (l.weightSigma ?? -1) >= 0 && (l.atomicSigma ?? -1) >= 0)
            #expect(!l.weightSigmaText.isEmpty)
        }
        #expect(r.kKind == "typed" && r.kSource == "Velox export, planted" && r.kDate == "2026-10-22" && r.kReference == "Al")
        #expect(r.lines.map(\.k) == [1.0, 1.2, 1.1])
        #expect(r.lines[0].kRelativeSigma == 0 && abs(r.lines[1].kRelativeSigma! - 0.1) < 1e-12 && abs(r.lines[2].kRelativeSigma! - 0.05) < 1e-12)
        #expect(r.lines[0].isReference == q.rows[0].isReference)
        #expect(r.methodHash == q.method.hash && r.methodHashShort == String(q.method.hash.prefix(8)))
        #expect(r.absorptionNote.hasPrefix("absorption: not applied"), "\(r.absorptionNote)")   // no stage tilt in the planted file
        #expect(r.unlistedLineCheck == "not run" && r.unlistedElements.isEmpty)
        #expect(r.footerLines == q.footerLines)
        #expect(r.abundanceRefusal == nil)
    }

    @Test func theUnlistedLineOutcomeTravels() throws {
        var q = try Self.quantification()
        q.unlistedCheck = .failed("planted failure")
        let r = RegionQuantResult.make(from: q, regionName: "x", pixelCount: 1)
        #expect(r.unlistedLineCheck == "not checked: planted failure")
    }

    @Test func aRefusedAtomicPercentLeavesTheNetCountsAndSaysWhy() throws {
        var m = QuantificationMethod()
        m.elements = [.init(symbol: "Al", role: .quantify, isManual: false)]   // one element: no ratio
        m.beamEnergyKeV = 200
        m.lockEnergyAxis = true
        let meta = SpectrumImageMetadata(fileName: "planted", filePath: "", scanWidth: 1, scanHeight: 1, channelCount: Self.axis.size,
                                         energyOffsetEV: 0, energyDispersionEV: 10)
        let q = try PooledQuantifier.run(PooledQuantificationInput(counts: Self.planted(), axis: Self.axis, method: m, metadata: meta,
                                                                    regionName: "r", pixelCount: 3), tables: QuantificationTables.bundled())
        let r = RegionQuantResult.make(from: q, regionName: "r", pixelCount: 3)
        #expect(r.abundanceRefusal != nil && r.kKind == nil && r.lines[0].weightPercent == nil && (r.lines[0].netCounts ?? 0) > 0)
    }

    @Test func roundTripsThroughCodable() throws {
        let r = RegionQuantResult.make(from: try Self.quantification(), regionName: "Matrix, left", pixelCount: 24)
        let data = try JSONEncoder().encode(r)
        let back = try JSONDecoder().decode(RegionQuantResult.self, from: data)
        #expect(back == r)
    }

    @Test func aNonFiniteNetCountEncodesAsNilAndTwoLinesOfOneElementAreBothExported() throws {
        var r = RegionQuantResult.make(from: try Self.quantification(), regionName: "R", pixelCount: 24)
        var nan = r.lines[0]
        nan.netCounts = nil; nan.netSigma = nil
        r.lines[0] = nan
        let back = try JSONDecoder().decode(RegionQuantResult.self, from: try JSONEncoder().encode(r))
        #expect(back == r && back.lines[0].netCounts == nil)
        #expect(r.reportRow(elements: ["Al"])[9] == "")
        // a second fitted line of Al: the wide row sums the element's lines and names both
        var second = r.lines[0]
        second.line = "Al_La"; second.netCounts = 100; second.weightPercent = 1.5; second.atomicPercent = 2.5
        var first = r.lines[0]
        first.netCounts = 900; first.weightPercent = 10; first.atomicPercent = 20
        r.lines = [first, second] + r.lines.dropFirst()
        let row = r.reportRow(elements: ["Al"])
        #expect(row[8] == "Al_Ka+Al_La" && row[9] == "1000" && row[12] == "11.5" && row[14] == "22.5")
        #expect(row[10] == "" && row[11] == "" && row[13] == "" && row[15] == "")
        #expect(r.csvLongRows.count == 4)
    }

    @Test func csvRowsLineUpWithTheirHeaders() throws {
        let r = RegionQuantResult.make(from: try Self.quantification(), regionName: "Matrix, left", pixelCount: 24)
        let els = ["Al", "Mg", "Si", "Fe"]   // Fe is not in the region: empty fields
        let header = RegionQuantResult.csvHeader(elements: els).split(separator: ",", omittingEmptySubsequences: false)
        let row = r.reportRow(elements: els)
        #expect(header.count == row.count && row.count == 8 + 8 * 4)
        #expect(row[0] == "Matrix, left" && row[1] == "24" && row[2] == "none")
        #expect(r.csvRow(elements: els).hasPrefix("\"Matrix, left\",24,none,"))
        let alNet = row[8 + 1]
        #expect(Double(alNet) != nil && Double(alNet)! > 20000)
        #expect(row[(8 + 8 * 3)...].allSatisfy { $0.isEmpty })
        #expect(header[8 + 1] == "Al_net_counts")
        // Long form: one row per element, same number of columns as its header.
        let longs = r.csvLongRows
        #expect(longs.count == 3)
        let cols = RegionQuantResult.csvLongHeader.split(separator: ",", omittingEmptySubsequences: false).count
        for l in longs {
            // The region name is quoted and holds a comma: count the fields outside quotes.
            var n = 1, quoted = false
            for ch in l { if ch == "\"" { quoted.toggle() } else if ch == ",", !quoted { n += 1 } }
            #expect(n == cols)
        }
    }
}
