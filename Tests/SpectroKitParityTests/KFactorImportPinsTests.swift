//
//  KFactorImportPinsTests.swift
//  Role: the k-factor importer against exSpy's CONVENTION (tools/edx-0100/pins.py): the planted table text in every layout parses to
//        the k list exSpy's `quantification_cliff_lorimer` documents (`[1, 1.47, 1.72]` for Al_Ka, Cr_Ka, Ni_Ka), and that list
//        drives the kit's Cliff-Lorimer to exSpy's own weight fractions. exSpy has no table of k-factors: only the convention is pinned.
//        Tolerance: exSpy's tests compare composition with atol 1e-3 on percent (`test_quant_lorimer*`); the measured difference
//        is recorded in docs/notes-eds-results.md.
//

import Foundation
import Testing
import SpectroTestSupport
import SpectroEDX

struct KFactorImportPinsTests {

    private struct Fixture: Decodable {
        struct Case: Decodable { var intensities: [Double]; var weight_fraction: [Double] }
        struct Set: Decodable { var name: String; var elements: [String]; var lines: [String]; var k: [Double]; var texts: [String: String]; var expected: [Case] }
        var sets: [Set]
    }

    private static func load() throws -> Fixture {
        let url = FixtureDirs.fixtures(of: "SpectroEDXTests").appendingPathComponent("edx-0100-exspy.json")
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    @Test func everyLayoutParsesToExspysKListAndDrivesItsCliffLorimer() throws {
        let fx = try Self.load()
        var worst = 0.0
        var runs = 0
        for set in fx.sets {
            for (layout, text) in set.texts.sorted(by: { $0.key < $1.key }) {
                let table = try KFactorImport.parse(text)
                let k = try KFactorImport.cliffLorimerFactors(from: table, elements: set.elements).k
                #expect(k == set.k, "\(set.name) \(layout)")
                for c in set.expected {
                    let setup = EDXQuantificationSetup(elements: set.elements, method: .cliffLorimer(kFactors: k, thicknessNm: nil))
                    let r = try EDXQuantification.quantify(intensities: c.intensities, setup: setup)
                    for (w, e) in zip(r.weightPercent, c.weight_fraction) {
                        worst = max(worst, abs(w - 100 * e))
                        #expect(abs(w - 100 * e) < 1e-3, "\(set.name) \(layout) \(c.intensities)")
                    }
                    runs += 1
                }
            }
        }
        #expect(runs == 2 * 4 * 4)
        #expect(worst < 1e-3)   // measured 0.0 (the same formula on the same k)
    }
}
