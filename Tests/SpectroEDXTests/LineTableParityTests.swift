//
//  LineTableParityTests.swift
//  Role: the whole X-ray line table against exSpy: all 947 rows (Z, element, line, energy, weight), in order, exact (table data).
//        Fixture `xray-lines-exspy-7185a4d1.json` from `tools/edx-lines/pins.py`, which runs exSpy's own loader
//        (`exspy.material.elements`, exSpy 7185a4d1, HyperSpy 2.4.0). Before this the table was compared on about 12 rows.
//

import Foundation
import Testing
import SpectroCore
import SpectroEDX

struct LineTableParityTests {

    private struct Pins: Decodable {
        let rows: [[Cell]]
        enum Cell: Decodable {
            case int(Int), text(String)
            init(from d: Decoder) throws {
                let c = try d.singleValueContainer()
                if let i = try? c.decode(Int.self) { self = .int(i) } else { self = .text(try c.decode(String.self)) }
            }
            var int: Int { if case .int(let i) = self { return i }; preconditionFailure() }
            var text: String { if case .text(let s) = self { return s }; preconditionFailure() }
        }
    }

    /// Every row of `XRayLines.all` equals exSpy's: same count, same order, energy and weight `==` (Python reprs round-trip).
    /// H and He rows are in both (exSpy ships them; `lines(of:)` filters them, see the DEVIATION in XRayLines).
    /// Mutation: change one digit of one energy in XRayLineData -> red on that row's id.
    @Test func testEveryLineOfTheTableEqualsExSpy() throws {
        let url = EDXFixtures.dir.appendingPathComponent("xray-lines-exspy-7185a4d1.json")
        let pins = try JSONDecoder().decode(Pins.self, from: Data(contentsOf: url))
        #expect(pins.rows.count == 947)
        #expect(XRayLines.all.count == pins.rows.count)
        for (row, line) in zip(pins.rows, XRayLines.all) {
            let id = row[1].text + "_" + row[2].text
            #expect(line.id == id, "order at \(id)")
            #expect(line.atomicNumber == row[0].int, "Z of \(id)")
            #expect(line.energy == Double(row[3].text)!, "energy of \(id)")
            #expect(line.weight == Double(row[4].text)!, "weight of \(id)")
        }
    }
}
