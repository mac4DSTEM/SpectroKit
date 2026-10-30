//
//  EDXFixtures.swift
//  Role: Loaders for the EDX pins and planted fixtures: pins.json, the planted Velox streams and
//        their truth, the planted Al-Mg-Si spectra (means plus int16 residuals), the calibration set, and RosettaSciIO's
//        public Velox files. Formats: tools/edx-planted/README.md. Nothing here is the code under test.
//

import CryptoKit
import Foundation
import Testing
import SpectroCore
import SpectroEDX

package enum EDXFixtures {
    package static let dir: URL = FixtureDirs.fixtures(of: "SpectroEDXTests")
    package static let repoRoot: URL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    package static func url(_ name: String) -> URL { dir.appendingPathComponent(name) }

    package static func jsonObject(_ name: String) -> [String: Any] {
        do {
            var data = try Data(contentsOf: url(name))
            // Python's json.dump wrote a bare NaN (a line on its own: find_peaks1D_ohaver widths); JSON has none, so it reads as null.
            if name == "pins.json" {
                var text = String(decoding: data, as: UTF8.self)
                text = text.replacingOccurrences(of: "\n      NaN", with: "\n      null")
                data = Data(text.utf8)
            }
            return try JSONSerialization.jsonObject(with: data) as! [String: Any]
        } catch { fatalError("\(name): \(error)") }
    }

    // Read-only after first load.
    package nonisolated(unsafe) static let pins: [String: Any] = jsonObject("pins.json")
    package nonisolated(unsafe) static let planted: [String: Any] = jsonObject("edx-planted.json")
    package nonisolated(unsafe) static let plantedTruth: [String: Any] = jsonObject("edx-planted-truth.json")
    package nonisolated(unsafe) static let calibration: [String: Any] = jsonObject("edx-calibration.json")
    package nonisolated(unsafe) static let streamTruth: [String: Any] = jsonObject("velox-streams-truth.json")

    package static func data<T>(_ name: String, as: T.Type) -> [T] {
        let d = try! Data(contentsOf: url(name))
        return d.withUnsafeBytes { Array($0.bindMemory(to: T.self)) }   // little-endian host (arm64)
    }

    /// The planted window: 1056 channels from channel 96 of 4096; E_k = -1.93221348 + 0.02 k keV.
    package static let k0 = 96, nwin = 1056, nch = 4096
    package static let axis = EnergyAxis(offset: -1.93221348, scale: 0.02, size: 4096)
    package static let means: [Double] = data("edx-planted-means.f64", as: Double.self)
    package static let resid: [Int16] = data("edx-planted-resid.i16", as: Int16.self)

    package struct Cell: Sendable {
        package let id: String, set: String, family: String
        package let nAl: Double, rho: Double
        package let meanRow: Int, residRow0: Int, nReal: Int
        package let truth: [String: Double]
    }

    package static let cells: [Cell] = {
        let tr = plantedTruth
        return (planted["cells"] as! [[String: Any]]).map { c in
            let id = c["id"] as! String
            let areas = (tr[id] as! [String: Any])["areas"] as! [String: String]
            return Cell(id: id, set: c["set"] as! String, family: c["family"] as! String,
                        nAl: Double(c["N_Al"] as! String)!, rho: Double(c["rho_Mg"] as! String)!,
                        meanRow: c["mean_row"] as! Int, residRow0: (c["resid_row0"] as? Int) ?? -1, nReal: c["n_real"] as! Int,
                        truth: areas.mapValues { Double($0)! })
        }
    }()
    package static let cellByID: [String: Cell] = Dictionary(uniqueKeysWithValues: cells.map { ($0.id, $0) })

    /// The noise-free mean of a cell as a full 4096-channel spectrum (zero outside the stored window).
    package static func meanSpectrum(_ c: Cell) -> [Double] {
        var out = [Double](repeating: 0, count: nch)
        for j in 0..<nwin { out[k0 + j] = means[c.meanRow * nwin + j] }
        return out
    }

    /// Realisation `j` (0-based): rint(mean) + residual, round half to even, in a 4096-channel spectrum.
    package static func realisation(_ c: Cell, _ j: Int) -> [Double] {
        var out = [Double](repeating: 0, count: nch)
        for k in 0..<nwin {
            out[k0 + k] = means[c.meanRow * nwin + k].rounded(.toNearestOrEven) + Double(resid[(c.residRow0 + j) * nwin + k])
        }
        return out
    }

    package static func sha256(_ bytes: Data) -> String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }

    // MARK: RosettaSciIO's public Velox files

    /// Small public files are copied into Fixtures/public (NOTICE); the others are read from the gitignored
    /// References/rosettasciio checkout (zip member, extracted once per process) and the test is skipped when it is absent:
    /// `FixtureAbsent` (XCTSkip before the Swift Testing migration) is caught by the loops that go on, and turned into
    /// a printed note and an early return by `publicVeloxIfPresent` where the test needs the one file.
    package static func publicVelox(label: String) throws -> String {
        let parts = label.split(separator: "/", maxSplits: 1).map(String.init)
        let member = parts[1]
        let copy = dir.appendingPathComponent("public").appendingPathComponent(member)
        if FileManager.default.fileExists(atPath: copy.path) { return copy.path }
        let zip = repoRoot.appendingPathComponent("References/rosettasciio/rsciio/tests/data/emd").appendingPathComponent(parts[0])
        guard FileManager.default.fileExists(atPath: zip.path) else {
            throw FixtureAbsent(reason: "References/rosettasciio is absent: \(label) is read from it (registration C1; the gate is partly conditional on References)")
        }
        return try extractLock.withLock { cache in
            if let p = cache[label] { return p }
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("edx-stage-public-\(getpid())")
            try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
            let out = tmp.appendingPathComponent(member.replacingOccurrences(of: "/", with: "_"))
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            p.arguments = ["-p", zip.path, member]
            FileManager.default.createFile(atPath: out.path, contents: nil)
            let h = try FileHandle(forWritingTo: out)
            p.standardOutput = h
            try p.run(); p.waitUntilExit(); try h.close()
            guard p.terminationStatus == 0 else { throw FixtureAbsent(reason: "unzip of \(label) failed") }
            cache[label] = out.path
            return out.path
        }
    }
    private static let extractLock = NSMutex()

    /// `publicVelox`, or nil (a note printed) when the file is absent: the test returns without checking. `Test.cancel` (a real
    /// skip) is missing from Xcode 26.0's Swift Testing, the toolchain of the macOS 15 CI job.
    package static func publicVeloxIfPresent(label: String) throws -> String? {
        do { return try publicVelox(label: label) } catch let absent as FixtureAbsent { print("skipped, nothing checked: \(absent.reason)"); return nil }
    }
}

/// A fixture the test reads is not on this machine (the References checkout): the test skips, it does not fail.
package struct FixtureAbsent: Error { let reason: String }

/// A lock around a dictionary cache (strings to strings), for the extracted public files.
package final class NSMutex: @unchecked Sendable {
    private let lock = NSLock()
    private var cache: [String: String] = [:]
    package func withLock<T>(_ body: (inout [String: String]) throws -> T) rethrows -> T {
        lock.lock(); defer { lock.unlock() }
        return try body(&cache)
    }
}

package extension Dictionary where Key == String, Value == Any {
    func d(_ k: String) -> [String: Any] { self[k] as! [String: Any] }
    func a(_ k: String) -> [Double] { (self[k] as! [Any]).map { ($0 as? NSNumber)?.doubleValue ?? .nan } }
    func l(_ k: String) -> [[String: Any]] { self[k] as! [[String: Any]] }
    func x(_ k: String) -> Double { (self[k] as! NSNumber).doubleValue }
    func i(_ k: String) -> Int { (self[k] as! NSNumber).intValue }
    func s(_ k: String) -> String { self[k] as! String }
}

// MARK: parallel helper (at most 8 workers, so heavy CPU work leaves the machine usable)

package final class ResultBox<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [T?]
    package init(_ n: Int) { items = [T?](repeating: nil, count: n) }
    package func set(_ i: Int, _ v: T) { lock.lock(); items[i] = v; lock.unlock() }
    package var values: [T] { items.map { $0! } }
}

/// `body(0..<n)` on at most 8 threads; results in order.
package func parallelMap<T: Sendable>(_ n: Int, _ body: @Sendable (Int) -> T) -> [T] {
    let box = ResultBox<T>(n)
    let workers = min(8, max(n, 1))
    DispatchQueue.concurrentPerform(iterations: workers) { w in
        var i = w
        while i < n { box.set(i, body(i)); i += workers }
    }
    return box.values
}

/// Lines of `EDX_GATE_LOG` (if set) and stdout: the numbers the EDX checks and the Mg diagnosis report.
package func gateNote(_ s: String) {
    print(s)
    guard let path = ProcessInfo.processInfo.environment["EDX_GATE_LOG"] else { return }
    if let h = FileHandle(forWritingAtPath: path) { h.seekToEndOfFile(); h.write((s + "\n").data(using: .utf8)!); try? h.close() }
    else { try? (s + "\n").write(toFile: path, atomically: false, encoding: .utf8) }
}
