//
//  GOSPackTests.swift
//  Role: every bundled edge loads from the pack (dft-gos-tables.bin with dft-gos-index.json), and `GOSTable.bundled` returns the
//        pack's table unchanged. While the 16 per-table JSON files shipped beside the pack, this compared the pack with them bit
//        for bit; the values themselves are pinned by sha256 in EdgeTablePinsTests and EdgePackPinsTests (parity target).
//

import Testing
import SpectroEELS

struct GOSPackTests {
    @Test func testEveryBundledEdgeLoadsFromThePack() throws {
        let pack = try #require(GOSPack.shared)
        #expect(CoreLossEdge.bundled.count == 383)
        for edge in CoreLossEdge.bundled {
            let bundled = try #require(GOSTable.bundled(edge), Comment(rawValue: edge.description))
            let packed = try #require(pack.table(for: edge), Comment(rawValue: edge.description))
            #expect(packed.occupancyRatio.bitPattern == bundled.occupancyRatio.bitPattern, Comment(rawValue: edge.description))
            #expect(packed.energyAxis.map(\.bitPattern) == bundled.energyAxis.map(\.bitPattern), Comment(rawValue: edge.description))
            #expect(packed.q.map(\.bitPattern) == bundled.q.map(\.bitPattern), Comment(rawValue: edge.description))
            #expect(packed.gos.map { $0.map(\.bitPattern) } == bundled.gos.map { $0.map(\.bitPattern) }, Comment(rawValue: edge.description))
        }
    }

    @Test func testNamedEdgesAreInThePack() {
        let named: [CoreLossEdge] = [
            .carbonK, .nitrogenK, .oxygenK, .magnesiumK, .aluminiumK, .siliconK,
            .magnesiumL1, .magnesiumL2, .magnesiumL3, .aluminiumL1, .aluminiumL23, .siliconL1, .siliconL2, .siliconL3,
            .ironL1, .ironL2, .ironL3, .copperL1, .copperL2, .copperL3,
        ]
        for edge in named { #expect(GOSPack.shared?.table(for: edge) != nil, Comment(rawValue: edge.description)) }
    }
}
