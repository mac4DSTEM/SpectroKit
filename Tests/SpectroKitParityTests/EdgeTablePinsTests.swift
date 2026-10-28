//
//  EdgeTablePinsTests.swift
//  Role: EELS task 16 step 3 (docs/design/eels-task-16.md section 6.1): the K and L edges added to the bundled GOS tables against
//        exSpy 7185a4d1's pins in Fixtures/eels16-edges-pins.json (tools/eels-chain/edges.py). The tables are bit-exact
//        (sha256 of the float32 bytes); qint, the effective angle and function(E) follow the registered edge bounds
//        (EdgePinsTests: angle 1e-14, qint 1e-12, function 1e-10).
//

import CryptoKit
import Foundation
import Testing
import SpectroTestSupport
import SpectroEELS

struct EdgeTablePinsTests {
    nonisolated(unsafe) private static let pins: [String: Any] = {
        let url = FixtureDirs.fixtures(of: "SpectroEELSTests").appendingPathComponent("eels16-edges-pins.json")
        return try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    }()

    private static func sha256(_ floats: [Float]) -> String {
        var bytes = Data()
        for f in floats { withUnsafeBytes(of: f.bitPattern.littleEndian) { bytes.append(contentsOf: $0) } }
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    private static func number(_ any: Any?) -> Double { (any as! NSNumber).doubleValue }

    @Test func testBundledTablesAreBitExact() throws {
        let tables = Self.pins["tables"] as! [String: [String: Any]]
        #expect(tables.count == 13)
        for (key, t) in tables {
            let parts = key.split(separator: "/").map(String.init)
            let edge = try #require(CoreLossEdge.bundled.first { $0.element == parts[0] && $0.table == (parts[1] == "L23" ? "L23" : parts[1]) })
            let table = try #require(GOSTable.bundled(edge))
            #expect(Self.sha256(table.gos.flatMap { $0 }) == t["gosSHA256"] as! String, Comment(rawValue: key))
            #expect(Self.sha256(table.q) == t["qSHA256"] as! String, Comment(rawValue: key))
        }
    }

    @Test func testNewEdgesEqualExSpy() throws {
        let edges = Self.pins["edges"] as! [String: [String: Any]]
        #expect(edges.count == 17)
        var worstFn = 0.0, worstQ = 0.0, worstAngle = 0.0
        for (name, rec) in edges {
            let edge = try #require(CoreLossEdge.bundled(rec["element"] as! String, rec["subshell"] as! String), Comment(rawValue: name))
            #expect(edge.onsetEV == Self.number(rec["onsetEV"]), Comment(rawValue: name))
            let table = try #require(GOSTable.bundled(edge))
            #expect(Double(table.occupancyRatio) == Self.number(rec["subshellFactor"]), Comment(rawValue: name))
            for s in rec["settings"] as! [[String: Any]] {
                let xs = try #require(EdgeCrossSection(table: table, beamEnergyKeV: Self.number(s["beamEnergyKeV"]),
                                                        convergenceMrad: Self.number(s["convergenceMrad"]),
                                                        collectionMrad: Self.number(s["collectionMrad"])), Comment(rawValue: name))
                worstAngle = max(worstAngle, relativeDifference(xs.effectiveAngleMrad, Self.number(s["effectiveAngleMrad"])))
                for (p, e) in zip(xs.qint, (s["qint"] as! [Any]).map(Self.number)) { worstQ = max(worstQ, relativeDifference(p, e)) }
                let ax = s["axis"] as! [String: Any]
                let n = ax["size"] as! Int, off = Self.number(ax["offsetEV"]), scale = Self.number(ax["scaleEV"])
                let f = xs.differential((0 ..< n).map { off + scale * Double($0) })
                let data = try Data(contentsOf: FixtureDirs.fixtures(of: "SpectroEELSTests").appendingPathComponent(s["file"] as! String))
                let ref = data.withUnsafeBytes { r in (0 ..< n).map { r.loadUnaligned(fromByteOffset: $0 * 8, as: Double.self) } }
                for (p, e) in zip(f, ref) { worstFn = max(worstFn, relativeDifference(p, e)) }
            }
        }
        print("task-16 edge pins: angle \(worstAngle), qint \(worstQ), function \(worstFn)")
        #expect(worstAngle <= 1e-14)
        #expect(worstQ <= 1e-12)
        #expect(worstFn <= 1e-10)
    }
}
