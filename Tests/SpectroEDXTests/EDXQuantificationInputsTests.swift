//
//  EDXQuantificationInputsTests.swift
//  Role: 0.8.2 public accessors of a pooled fit: `kFactors`, `Row.lineEnergyKeV`, `EDXQuantification.takeOffDegrees(metadata:)`.
//        Planted, noise-free spectra as in QuantificationPolicyTests. The k set is checked by closure: the per-pixel
//        Cliff-Lorimer call fed with the fit's own nets and k gives the fit's own weight percent.
//

import Foundation
import Testing
import SpectroCore
import SpectroEDX

struct EDXQuantificationInputsTests {

    private static let resources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Sources/SpectroEDX/Resources/Spectroscopy")
    private static let tables = try! QuantificationTables(directory: resources)
    private static let axis = EnergyAxis(offset: 0, scale: 0.01, size: 1500)

    private static func counts(areas: [String: Double]) -> [UInt64] {
        let energies = (0..<axis.size).map { axis.energy(ofChannel: $0) }
        var mu = energies.map { e -> Double in
            let x = max(e, 0.05)
            return e >= 0.2 ? 0.4 * max(200 - e, 0) / x * exp(-pow(0.3 / x, 3)) : 0
        }
        let elements = Array(Set(areas.keys.map { String($0.split(separator: "_")[0]) }))
        let model = EDSLineModel.build(elements: elements, axis: axis, beamEnergy: 200, resolutionMnKaEV: 130, escapePeaks: true)
        for g in model.groups {
            guard let area = areas[g.id] else { continue }
            let col = EDSLineModel.column(of: g.lines, energies: energies, scale: axis.scale)
            for i in mu.indices { mu[i] += area * col[i] }
        }
        return mu.map { UInt64($0.rounded()) }
    }

    private static func metadata() -> SpectrumImageMetadata {
        SpectrumImageMetadata(fileName: "planted", filePath: "", scanWidth: 1, scanHeight: 1, channelCount: axis.size,
                              energyOffsetEV: 0, energyDispersionEV: 10)
    }

    private static func method(typed: Bool) -> QuantificationMethod {
        var m = QuantificationMethod()
        m.elements = ["Al", "Mg", "Si"].map { QuantificationMethod.ElementState(symbol: $0, role: .quantify, isManual: false) }
        m.beamEnergyKeV = 200
        m.lockEnergyAxis = true
        m.absorptionCorrection = false
        if typed {
            m.kFactorSource = .typed
            m.kSource = "planted"; m.kDate = "2026-10-21"; m.kReference = "Al"
            m.typedK = [.init(element: "Al", k: 1), .init(element: "Mg", k: 1.2), .init(element: "Si", k: 0.9)]
        }
        return m
    }

    private static func fit(typed: Bool) throws -> PooledQuantification {
        let c = counts(areas: ["Al_Ka": 30000, "Mg_Ka": 4000, "Si_Ka": 12000])
        let input = PooledQuantificationInput(counts: c, axis: axis, method: method(typed: typed), metadata: metadata(),
                                              regionName: "planted", pixelCount: 1)
        return try PooledQuantifier.run(input, tables: tables)
    }

    /// The pin: the k the fit exposes, in the rows' order, reproduces the fit's own weight percent through the public per-pixel call.
    @Test(arguments: [true, false]) func kFactorsReproduceTheFitsWeightPercent(typed: Bool) throws {
        let q = try Self.fit(typed: typed)
        let ks = try #require(q.kFactors)
        #expect(ks.map(\.element) == q.rows.map(\.element))
        #expect(try #require(q.kFactorSourceDescription).isEmpty == false)
        if typed {
            #expect(ks.map(\.k) == q.rows.map { ["Al": 1, "Mg": 1.2, "Si": 0.9][$0.element]! })
        } else {
            #expect(ks.first { $0.element == "Al" }?.k == 1)   // the reference
            #expect(ks.allSatisfy { $0.k > 0 && $0.k.isFinite })
        }
        let setup = EDXQuantificationSetup(elements: ks.map(\.element), method: .cliffLorimer(kFactors: ks.map(\.k), thicknessNm: nil))
        let one = try EDXQuantification.quantify(intensities: q.rows.map { max($0.net, 0) }, setup: setup)
        for (i, r) in q.rows.enumerated() {
            #expect(abs(one.weightPercent[i] - (try #require(r.weightPercent))) < 1e-6)
        }
    }

    @Test func noAbundanceNoKFactors() throws {
        var m = Self.method(typed: false)
        m.elements = [.init(symbol: "Al", role: .quantify, isManual: false)]
        let c = Self.counts(areas: ["Al_Ka": 30000])
        let q = try PooledQuantifier.run(PooledQuantificationInput(counts: c, axis: Self.axis, method: m, metadata: Self.metadata(),
                                                                  regionName: "planted", pixelCount: 1), tables: Self.tables)
        #expect(q.kFactors == nil)
    }

    @Test func rowLineEnergyIsTheFittedLines() throws {
        let q = try Self.fit(typed: true)
        let al = try #require(q.rows.first { $0.element == "Al" })
        #expect(al.lineEnergyKeV == XRayLines.line("Al_Ka")?.energy)
        #expect(abs(try #require(al.lineEnergyKeV) - 1.4865) < 1e-3)
    }

    private static func veloxMetadata(alpha: Double? = -16.87) -> SpectrumImageMetadata {
        var m = metadata()
        m.origin = .veloxEMD
        m.alphaTiltDegrees = alpha; m.betaTiltDegrees = 0
        m.detectors = [(45.0, 0.4), (135.0, 0.2), (225.0, 0.1), (315.0, 0.3)].enumerated().map { i, a in
            SpectrumDetectorSegment(name: "SuperXG1\(i + 1)", azimuthDegrees: a.0, elevationDegrees: 22, solidAngle: a.1)
        }
        return m
    }

    @Test func takeOffIsTheSolidAngleWeightedMeanOfTheSegments() throws {
        let segments = [(45.0, 0.4), (135.0, 0.2), (225.0, 0.1), (315.0, 0.3)]
        let angles = segments.map { EDXQuantification.takeOffAngle(tiltAlpha: -16.87, azimuth: $0.0, elevation: 22) }
        let expected = zip(angles, segments).reduce(0) { $0 + $1.0 * $1.1.1 } / segments.reduce(0) { $0 + $1.1 }
        #expect(abs(try EDXQuantification.takeOffDegrees(metadata: Self.veloxMetadata()) - expected) < 1e-12)
    }

    @Test func takeOffRefusesWithTheReason() {
        #expect(throws: (any Error).self) { try EDXQuantification.takeOffDegrees(metadata: Self.veloxMetadata(alpha: nil)) }
        var gms = Self.veloxMetadata(); gms.origin = .gmsDM4
        do { _ = try EDXQuantification.takeOffDegrees(metadata: gms); Issue.record("GMS has no geometry") }
        catch { #expect((error as? LocalizedError)?.errorDescription?.contains("GMS") == true) }
    }
}
