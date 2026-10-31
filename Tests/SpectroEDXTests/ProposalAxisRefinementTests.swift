//
//  ProposalAxisRefinementTests.swift
//  Role: The proposer's own axis refinement with the two-line guard (`ElementProposer.proposeOnRefinedAxis`, `refinementAnchors`). Noise-free
//        planted spectra whose file axis is 15 eV off the axis the lines were planted on. Red before: the API did not exist (the apps held
//        the flow).
//

import Foundation
import Testing
import SpectroCore
import SpectroEDX

struct ProposalAxisRefinementTests {

    /// The lines are planted on `trueAxis`; the file states `fileAxis`, 15 eV higher.
    private static let trueAxis = EnergyAxis(offset: 0, scale: 0.01, size: 1100)   // 0 to 10.99 keV
    private static let fileAxis = EnergyAxis(offset: 0.015, scale: 0.01, size: 1100)
    private static let energies = (0..<trueAxis.size).map { trueAxis.energy(ofChannel: $0) }

    private static let kramers: @Sendable (Double) -> Double = { e in
        let x = max(e, 0.05)
        return 60 * max(200 - e, 0) / x * exp(-pow(0.30 / x, 3)) * 0.02 + 0.5
    }

    private static func planted(_ areas: [String: Double], dose k: Double = 10) -> [UInt64] {
        var out = energies.map { $0 >= 0.2 ? k * kramers($0) : 0 }
        for (id, area) in areas {
            let el = String(id.prefix { $0 != "_" })
            let g = EDSLineModel.build(elements: [el], axis: trueAxis, beamEnergy: 200, resolutionMnKaEV: 130).groups.first { $0.id == id }!
            let col = EDSLineModel.column(of: g.lines, energies: energies, scale: trueAxis.scale)
            for i in out.indices { out[i] += k * area * col[i] }
        }
        return out.map { UInt64($0.rounded()) }
    }

    private static let meta = SpectrumImageMetadata(fileName: "planted", filePath: "", scanWidth: 1, scanHeight: 1, channelCount: fileAxis.size,
                                                    energyOffsetEV: 15, energyDispersionEV: 10)

    /// A small pool keeps the test on the refinement: with every element a 15 eV shifted Al K line goes to Br L (the reason the axis is refined).
    private static let proposer = ElementProposer(pool: ["O", "Mg", "Al", "Si", "Fe", "Cu"])

    private static func run(_ s: [UInt64], metadata: SpectrumImageMetadata? = meta) throws -> AxisRefinedProposal {
        try Self.proposer.proposeOnRefinedAxis(spectrum: s, axis: fileAxis, beamEnergy: 200, listed: [], metadata: metadata,
                                                   regionName: "planted", tables: nil)
    }

    private static func plain(_ s: [UInt64]) throws -> ProposalResult {
        try Self.proposer.propose(counts: s.map { Double($0) }, axis: fileAxis,
                                      settings: FitSettings.standard(elements: [], axis: fileAxis, resolutionMnKaEV: 130, beamEnergy: 200))
    }

    @Test func testTwoKLinesSpanningTheAxisRefineItTowardsTheTruth() throws {
        let r = try Self.run(Self.planted(["Al_Ka": 9000, "Fe_Ka": 6000]))
        let refinement = try #require(r.refinement, "Al and Fe span 4.9 keV: the guard holds and the quantifier refines")
        #expect(Set(r.anchors).isSuperset(of: ["Al", "Fe"]), "\(r.anchors)")
        #expect(abs(r.axis.offset - Self.trueAxis.offset) < 0.005, "offset \(r.axis.offset * 1000) eV, planted 0")
        #expect(abs(r.axis.offset - Self.trueAxis.offset) < abs(Self.fileAxis.offset - Self.trueAxis.offset), "the refined axis is closer than the file's")
        #expect(r.axis == refinement.refinedAxis && r.settings.resolutionMnKaEV == refinement.resolutionMnKaEV)
        let note = try #require(r.note)
        #expect(note.hasPrefix("Energy axis refined on ") && note.contains("Fe"), "\(note)")
        #expect(r.result.proposed.contains { $0.element == "Al" } && r.result.proposed.contains { $0.element == "Fe" })
    }

    /// One K line cannot tell an offset from a gain: no refinement, the proposal is the plain one on the file's axis.
    @Test func testOneKLineDoesNotRefine() throws {
        let s = Self.planted(["Fe_Ka": 6000])
        let r = try Self.run(s)
        #expect(r.refinement == nil && r.anchors.isEmpty && r.note == nil && r.axis == Self.fileAxis)
        let p = try Self.plain(s)
        #expect(r.result.candidates == p.candidates)
    }

    /// Two K lines closer than 3 keV (Al and Si, 0.25 keV apart) do not anchor a refinement either.
    @Test func testTwoCloseKLinesDoNotRefine() throws {
        let s = Self.planted(["Al_Ka": 9000, "Si_Ka": 6000])
        #expect(ElementProposer.refinementAnchors(try Self.plain(s)) == nil)
        #expect(try Self.run(s).refinement == nil)
        // The span bar is a parameter: at 0.2 keV the same picks anchor.
        #expect(ElementProposer.refinementAnchors(try Self.plain(s), minimumSpanKeV: 0.2) != nil)
    }

    /// The note is the sentence the apps wrote: the refinement's own numbers in their own formats; `rounds: 0` refines nothing.
    @Test func testTheNoteAndTheRoundsCap() throws {
        let s = Self.planted(["Al_Ka": 9000, "Fe_Ka": 6000])
        let r = try Self.run(s)
        let x = try #require(r.refinement)
        #expect(r.note == String(format: "Energy axis refined on %@ before the proposal: offset %+.1f eV, gain %+.3f %%, FWHM(Mn K\u{03B1}) %.0f eV (file 130 eV).",
                                 r.anchors.joined(separator: ", "), x.offsetShiftEV, x.gainShift * 100, x.resolutionMnKaEV))
        #expect(r.fileResolutionMnKaEV == 130)
        let none = try Self.proposer.proposeOnRefinedAxis(spectrum: s, axis: Self.fileAxis, beamEnergy: 200, listed: [], metadata: Self.meta,
                                                          regionName: "planted", tables: nil, rounds: 0)
        #expect(none.refinement == nil && none.axis == Self.fileAxis)
    }

    @Test func testNoMetadataDoesNotRefine() throws {
        let s = Self.planted(["Al_Ka": 9000, "Fe_Ka": 6000])
        let r = try Self.run(s, metadata: nil)
        #expect(r.refinement == nil && r.axis == Self.fileAxis)
        #expect(r.result.candidates == (try Self.plain(s)).candidates)
    }
}
