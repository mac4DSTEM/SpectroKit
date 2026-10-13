//
//  SpectroGoldenTests.swift
//  SpectroKit slot S0, gate G-golden (docs/archive/v5/spectrokit-slot-plan-2026-10-13.md §9): "no number moves". A baseline of
//  the Spectroscopy core's outputs, recorded at 71929a01 BEFORE the Velox reader's per-block HDF5 lock and the cancel/progress
//  contract, and compared byte for byte afterwards. Every Double is its exact bit pattern (hex of `bitPattern`) with a readable
//  %.17g beside it; large arrays are listed by count, a bit-exact sum and an FNV-1a hash of every element's bits. No tolerance anywhere.
//
//  Inputs are the committed fixtures only (velox-tiny.emd, demo-edx-tiny.dm4, the eds-*.json pools, the demo spectrum image
//  of `--demo-spectrum-fixture`), so CI runs it. The dump is a reflection walk (Mirror) of the result values, so a field added to
//  a result is a new line and fails the comparison until the baseline is re-recorded on purpose.
//
//  Record (from a copy of the commit to be baselined, with only this file added):
//    TEST_RUNNER_SPECTRO_GOLDEN_DIR=<dir> xcodebuild test ... -only-testing:mac4DSTEMTests/SpectroGoldenTests CODE_SIGNING_ALLOWED=NO
//  then copy <dir>/*.txt to mac4DSTEMTests/Fixtures/spectro-golden/. Without the variable `testOutputsAreByteIdenticalToTheBaseline` compares.
//
//  SpectroKit S2: the same file, run against the extracted library and compared with mac4DSTEM's committed baseline
//  (Tests/SpectroCoreTests/Fixtures/spectro-golden, copied at 5ba712a0, unchanged). Six of its seven scenarios: the seventh,
//  `demo-spectrum-fixture`, opens the app's `DemoSpectrumImageSource` (4D demo data), which stays in mac4DSTEM and is compared
//  there. `Q` is a copy of the statics of `SpectroscopyQuantifySpectro` (another test target). Record with
//  `SPECTRO_GOLDEN_DIR=<dir> swift test --filter SpectroGoldenTests.testRecordBaseline`.
//

import XCTest
import Foundation
import SpectroCore

// MARK: - The dump

/// Reflection walk that writes one line per scalar: `path = value`. Deterministic: dictionaries and sets are sorted, absolute
/// paths keep their last component, numeric arrays above 8 elements are summarised by count, exact sum and bit hash.
enum GoldenDump {
    static func fnv(_ words: some Sequence<UInt64>) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        for w in words {
            for i in 0..<8 { h ^= (w >> (8 * UInt64(i))) & 0xff; h = h &* 0x100000001b3 }
        }
        return h
    }

    static func hex(_ d: Double) -> String { String(format: "%016llx", d.bitPattern) + String(format: " %.17g", d) }
    static func hex(_ f: Float) -> String { String(format: "%08x", f.bitPattern) + String(format: " %.9g", f) }

    private static func normalised(_ s: String) -> String {
        s.hasPrefix("/") ? "<abs>/" + (s as NSString).lastPathComponent : s
    }

    static func dump(_ path: String, _ value: Any, into out: inout [String], depth: Int = 0) {
        if depth > 16 { out.append("\(path) = <depth>"); return }
        switch value {
        case let d as Double: out.append("\(path) = \(hex(d))"); return
        case let f as Float: out.append("\(path) = \(hex(f))"); return
        case let b as Bool: out.append("\(path) = \(b)"); return
        case let i as Int: out.append("\(path) = \(i)"); return
        case let i as Int32: out.append("\(path) = \(i)"); return
        case let i as Int64: out.append("\(path) = \(i)"); return
        case let i as UInt8: out.append("\(path) = \(i)"); return
        case let i as UInt16: out.append("\(path) = \(i)"); return
        case let i as UInt32: out.append("\(path) = \(i)"); return
        case let i as UInt64: out.append("\(path) = \(i)"); return
        case let s as String: out.append("\(path) = \"\(normalised(s))\""); return
        case let data as Data: out.append("\(path) = Data(\(data.count), fnv \(String(fnv(data.map { UInt64($0) }), radix: 16)))"); return
        case let a as [Double]: numeric(path, a.map { $0.bitPattern }, sumBits: a.reduce(0, +).bitPattern, &out) { hex($0) }; return
        case let a as [Float]: numeric(path, a.map { UInt64($0.bitPattern) }, sumBits: UInt64(a.reduce(0, +).bitPattern), &out) { hex($0) }; return
        case let a as [Int]: numeric(path, a.map { UInt64(bitPattern: Int64($0)) }, sumBits: UInt64(bitPattern: Int64(a.reduce(0, +))), &out); return
        case let a as [Int32]: numeric(path, a.map { UInt64(bitPattern: Int64($0)) }, sumBits: UInt64(bitPattern: a.reduce(0) { $0 + Int64($1) }), &out); return
        case let a as [UInt8]: numeric(path, a.map { UInt64($0) }, sumBits: a.reduce(0) { $0 + UInt64($1) }, &out); return
        case let a as [UInt16]: numeric(path, a.map { UInt64($0) }, sumBits: a.reduce(0) { $0 + UInt64($1) }, &out); return
        case let a as [UInt32]: numeric(path, a.map { UInt64($0) }, sumBits: a.reduce(0) { $0 + UInt64($1) }, &out); return
        case let a as [UInt64]: numeric(path, a, sumBits: a.reduce(0, &+), &out); return
        case let a as [Bool]: numeric(path, a.map { $0 ? 1 : 0 }, sumBits: UInt64(a.filter { $0 }.count), &out); return
        case let n as NSNumber where type(of: value) is AnyClass: out.append("\(path) = NSNumber(\(n))"); return
        case let d as NSDictionary where type(of: value) is AnyClass:   // a Swift dictionary also bridges: only real NS objects
            out.append("\(path): dict \(d.count)")
            for k in d.allKeys.map({ "\($0)" }).sorted() { dump("\(path).\(k)", d["\(k)"] ?? d.object(forKey: k) as Any, into: &out, depth: depth + 1) }
            return
        case let a as NSArray where type(of: value) is AnyClass:
            out.append("\(path): array \(a.count)")
            for (i, e) in a.enumerated() { dump("\(path)[\(i)]", e, into: &out, depth: depth + 1) }
            return
        default: break
        }
        let m = Mirror(reflecting: value)
        switch m.displayStyle {
        case .optional:
            if let c = m.children.first { dump(path, c.value, into: &out, depth: depth) } else { out.append("\(path) = nil") }
        case .collection:
            let items = m.children.map { $0.value }
            if items.count > 400 {
                var sub: [String] = []
                for (i, e) in items.enumerated() { dump("[\(i)]", e, into: &sub, depth: depth + 1) }
                out.append("\(path): array \(items.count) fnv \(String(fnv(sub.joined(separator: "\n").utf8.map { UInt64($0) }), radix: 16))")
            } else {
                out.append("\(path): array \(items.count)")
                for (i, e) in items.enumerated() { dump("\(path)[\(i)]", e, into: &out, depth: depth + 1) }
            }
        case .set:
            let items = m.children.map { $0.value }.sorted { "\($0)" < "\($1)" }
            out.append("\(path): set \(items.count)")
            for (i, e) in items.enumerated() { dump("\(path){\(i)}", e, into: &out, depth: depth + 1) }
        case .dictionary:
            let entries = m.children.map { c -> (String, Any) in
                let kv = Array(Mirror(reflecting: c.value).children)
                return ("\(kv[0].value)", kv[1].value)
            }.sorted { $0.0 < $1.0 }
            out.append("\(path): dict \(entries.count)")
            for (k, v) in entries { dump("\(path).\(k)", v, into: &out, depth: depth + 1) }
        case .struct, .class, .tuple:
            if m.children.isEmpty { out.append("\(path) = \(normalised("\(value)"))"); return }
            for (i, c) in m.children.enumerated() {
                let label = c.label ?? ".\(i)"
                if label == "filePath" { out.append("\(path).\(label) = <omitted: machine path>"); continue }
                dump("\(path).\(label)", c.value, into: &out, depth: depth + 1)
            }
        case .enum:
            if m.children.isEmpty { out.append("\(path) = .\(value)"); return }
            for (i, c) in m.children.enumerated() { dump("\(path).\(c.label ?? "\(i)")", c.value, into: &out, depth: depth + 1) }
        default:
            out.append("\(path) = \(normalised("\(value)"))")
        }
    }

    private static func numeric(_ path: String, _ words: [UInt64], sumBits: UInt64, _ out: inout [String]) {
        out.append("\(path): n \(words.count) sum-bits \(String(sumBits, radix: 16)) fnv \(String(fnv(words), radix: 16))")
    }
    private static func numeric(_ path: String, _ words: [UInt64], sumBits: UInt64, _ out: inout [String], _ show: (Double) -> String) {
        let sum = Double(bitPattern: sumBits)
        out.append("\(path): n \(words.count) sum \(show(sum)) fnv \(String(fnv(words), radix: 16))")
        if words.count <= 8 { for (i, w) in words.enumerated() { out.append("\(path)[\(i)] = \(show(Double(bitPattern: w)))") } }
    }
}

// MARK: - Scenarios

/// The statics of `SpectroscopyQuantifySpectro` (= mac4DSTEM's `SpectroscopyQuantifyTests`) that the scenarios use, verbatim
/// apart from the paths.
@MainActor
enum GoldenQ {
    static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("SpectroCoreTests/Fixtures")
    static let resources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/SpectroCore/Resources/Spectroscopy")
    static let tables = try! QuantificationTables(directory: resources)

    static func image() throws -> LoadedSpectrumImage {
        try XCTUnwrap(try SpectrumImageOpener.openGMSEDS(path: fixtures.appendingPathComponent("demo-edx-tiny.dm4").path))
    }

    static func method(elements: [(String, QuantificationMethod.ElementRole)] = [("Al", .quantify), ("Mg", .quantify), ("Si", .quantify), ("Cu", .quantify), ("O", .fitOnly), ("Ga", .fitOnly)]) -> QuantificationMethod {
        var m = QuantificationMethod()
        m.elements = elements.map { QuantificationMethod.ElementState(symbol: $0.0, role: $0.1, isManual: false) }
        m.beamEnergyKeV = 200          // the GMS EDS object does not state it
        return m
    }

    static func input(_ method: QuantificationMethod, image: LoadedSpectrumImage) -> PooledQuantificationInput {
        PooledQuantificationInput(counts: image.sum(mask: nil), axis: image.energyAxis, method: method, metadata: image.metadata,
                                  regionName: "Whole map", pixelCount: image.metadata.pixelCount)
    }
}

@MainActor
enum SpectroGolden {
    typealias Q = GoldenQ

    static let fixtures = Q.fixtures

    struct SplitMix64: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
        mutating func uniform() -> Double { Double(next() >> 11) / Double(1 << 53) }
    }

    nonisolated static func poisson(_ lam: Double, _ rng: inout SplitMix64) -> Double {
        if lam <= 0 { return 0 }
        if lam < 10 {
            let l = exp(-lam); var k = 0.0; var p = 1.0
            repeat { k += 1; p *= rng.uniform() } while p > l
            return k - 1
        }
        let slam = lam.squareRoot(), loglam = log(lam)
        let b = 0.931 + 2.53 * slam, a = -0.059 + 0.02483 * b
        let invalpha = 1.1239 + 1.1328 / (b - 3.4), vr = 0.9277 - 3.6224 / (b - 2)
        while true {
            let u = rng.uniform() - 0.5, v = rng.uniform()
            let us = 0.5 - abs(u)
            let k = ((2 * a / us + b) * u + lam + 0.43).rounded(.down)
            if us >= 0.07 && v <= vr { return k }
            if k < 0 || (us < 0.013 && v > us) { continue }
            if log(v) + log(invalpha) - log(a / (us * us) + b) <= -lam + k * loglam - lgamma(k + 1) { return k }
        }
    }

    nonisolated static func draw(_ expected: [Double], seed: UInt64) -> [UInt64] {
        var rng = SplitMix64(state: seed)
        return expected.map { UInt64(poisson($0, &rng)) }
    }

    static func method(_ quantify: [String], fitOnly: [String] = [], beam: Double = 200, lock: Bool = false) -> QuantificationMethod {
        var m = QuantificationMethod()
        m.elements = quantify.map { .init(symbol: $0, role: .quantify, isManual: false) } + fitOnly.map { .init(symbol: $0, role: .fitOnly, isManual: false) }
        m.beamEnergyKeV = beam
        m.absorptionCorrection = false
        if lock { m.lockEnergyAxis = true }
        return m
    }

    static func pooledInput(counts: [UInt64], axis: EnergyAxis, method: QuantificationMethod, name: String) -> PooledQuantificationInput {
        let meta = SpectrumImageMetadata(fileName: name, filePath: "", scanWidth: 1, scanHeight: 1, channelCount: axis.size,
                                         energyOffsetEV: axis.offset * 1000, energyDispersionEV: axis.scale * 1000)
        return PooledQuantificationInput(counts: counts, axis: axis, method: method, metadata: meta, regionName: "synthetic", pixelCount: 1)
    }

    /// The fit, its CSV, the range-sensitivity statement, the proposer on the fit's own settings and the unlisted-line check.
    static func quantify(_ tag: String, _ input: PooledQuantificationInput, tables: QuantificationTables?, into out: inout [String],
                         unlisted: Bool = true) throws {
        let q = try PooledQuantifier.run(input, tables: tables)
        GoldenDump.dump("\(tag).quantification", q, into: &out)
        out.append("\(tag).csv-fnv = \(String(GoldenDump.fnv(SpectroscopyExport.csv(q, regionName: input.regionName).utf8.map { UInt64($0) }), radix: 16))")
        GoldenDump.dump("\(tag).rangeSensitivity", FitRangeSensitivityCheck.run(input: input, quantification: q) as Any, into: &out)
        guard unlisted else { return }
        let proposal = try UnlistedLineChecker.propose(counts: input.counts.map { Double($0) }, quantification: q)
        GoldenDump.dump("\(tag).unlistedProposal", proposal, into: &out)
        let check = UnlistedLineChecker.check(proposal: proposal, input: input, quantification: q)
        GoldenDump.dump("\(tag).unlistedCheck", check, into: &out)
        let shown = UnlistedLineChecker.withholding(q, check)
        GoldenDump.dump("\(tag).withholding", [shown.rows.map(\.atomicPercent), shown.rows.map(\.net)] as [Any], into: &out)
        GoldenDump.dump("\(tag).withholding.caveat", shown.abundanceCaveat as Any, into: &out)
        out.append("\(tag).csv-withholding-fnv = \(String(GoldenDump.fnv(SpectroscopyExport.csv(shown, regionName: input.regionName).utf8.map { UInt64($0) }), radix: 16))")
    }

    static func windows(_ tag: String, _ image: LoadedSpectrumImage, _ symbols: [String], into out: inout [String]) {
        let ws = ElementWindows.build(elements: symbols.map { ($0, nil) }, axis: image.energyAxis, beamEnergyKeV: 200)
        GoldenDump.dump("\(tag).windows", ws, into: &out)
        let maps = ElementWindows.maps(image: image, windows: ws)
        GoldenDump.dump("\(tag).netMaps", maps, into: &out)
        let integrated = ElementWindows.integratedMaps(image: image, windows: ws)
        GoldenDump.dump("\(tag).integratedMaps", integrated, into: &out)
        let whole = image.sum(mask: nil)
        GoldenDump.dump("\(tag).netCountsWhole", ElementWindows.netCounts(spectrum: whole, windows: ws), into: &out)
    }

    static func imageSummary(_ tag: String, _ image: LoadedSpectrumImage, into out: inout [String]) {
        GoldenDump.dump("\(tag).dims", [image.ny, image.nx, image.channels], into: &out)
        GoldenDump.dump("\(tag).energyAxis", image.energyAxis, into: &out)
        GoldenDump.dump("\(tag).metadata", image.metadata, into: &out)
        GoldenDump.dump("\(tag).scanImage", image.scanImage as Any, into: &out)
        GoldenDump.dump("\(tag).sumWhole", image.sum(mask: nil), into: &out)
        let n = image.nx * image.ny
        var mask = PixelMask(repeating: false, count: n)
        for p in stride(from: 0, to: n, by: 3) { mask[p] = true }
        GoldenDump.dump("\(tag).sumEveryThirdPixel", image.sum(mask: mask), into: &out)
        let ch = image.channels
        GoldenDump.dump("\(tag).windowSums", image.windowSums([0..<ch / 4, ch / 4..<ch / 2, ch / 2..<ch, 3..<4, 5..<5]), into: &out)
    }

    // MARK: Scenario list

    static var times: [String] = []

    static func scenarios() async throws -> [(name: String, text: String)] {
        var all: [(String, String)] = []
        func add(_ name: String, _ body: (inout [String]) throws -> Void) rethrows {
            var out: [String] = ["# SpectroGolden \(name)"]
            let t0 = Date()
            try body(&out)
            times.append("\(name) \(String(format: "%.1f", Date().timeIntervalSince(t0))) s")
            all.append((name, out.joined(separator: "\n") + "\n"))
        }

        try add("velox-tiny") { out in
            let path = fixtures.appendingPathComponent("velox-tiny.emd").path
            let v = try VeloxEMDReader(path: path).readSpectrumImage()
            GoldenDump.dump("readSpectrumImage", v, into: &out)
            let s = v.eventStore
            out.append("store: totalCounts \(s.totalCounts) completeFrames \(s.completeFrames) partialFramePixels \(s.partialFramePixels) outOfRange \(s.outOfRangeValues)")
            GoldenDump.dump("store.summedSpectrum", s.summedSpectrum(), into: &out)
            GoldenDump.dump("store.denseCounts", s.denseCounts(), into: &out)
            for p in 0..<s.geometry.pixelsPerFrame {
                out.append("pixel \(p): framesCovering \(s.framesCovering(pixel: p)) spectrum \(s.spectrum(pixel: p))")
            }
            let part = try VeloxEMDReader(path: path).readSpectrumImage(frames: .range(1..<2))
            out.append("frames 1..<2: totalCounts \(part.eventStore.totalCounts) complete \(part.eventStore.completeFrames) summed \(part.eventStore.summedSpectrum())")
            let image = try SpectrumImageOpener.openVelox(path: path)
            imageSummary("openVelox", image, into: &out)
            windows("openVelox", image, ["O", "Si"], into: &out)
        }

        try add("demo-edx-tiny-dm4") { out in
            let image = try Q.image()
            imageSummary("openGMSEDS", image, into: &out)
            windows("openGMSEDS", image, ["Al", "Mg", "Si", "Cu", "O", "Ga"], into: &out)
            let whole = Q.input(Q.method(), image: image)
            try quantify("whole", whole, tables: Q.tables, into: &out)
            var region = Q.input(Q.method(elements: [("Al", .quantify), ("Si", .quantify), ("Cu", .fitOnly)]), image: image)
            region.method.lockEnergyAxis = true
            region.counts = image.sum(mask: SpectrumRegionShape.rectangle(PixelRect(x0: 1, y0: 1, x1: 4, y1: 3)).mask(nx: image.nx, ny: image.ny))
            try quantify("region-locked-axis", region, tables: nil, into: &out, unlisted: false)
        }

        // "demo-spectrum-fixture" (the app's DemoSpectrumImageSource) stays in mac4DSTEM.

        // eds-realistic-l-sim: 80 keV axis, the range-sensitivity statement applies.
        try add("eds-realistic-l-sim") { out in
            struct Fixture: Decodable {
                let offset: Double, scale: Double, size: Int, beam: Double, fwhmMnKa: Double
                let continuum: [Double]; let areas: [String: Double]; let planted: [String]
                let listedFour: [String]; let listedSeven: [String]; let seeds: [UInt64]
                var axis: EnergyAxis { EnergyAxis(offset: offset, scale: scale, size: size) }
            }
            let fx = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: fixtures.appendingPathComponent("eds-realistic-l-sim.json")))
            func counts(seed: UInt64) -> [UInt64] {
                let axis = fx.axis
                var mu = fx.continuum
                let energies = (0..<axis.size).map { axis.energy(ofChannel: $0) }
                let model = EDSLineModel.build(elements: fx.planted, axis: axis, beamEnergy: fx.beam, resolutionMnKaEV: fx.fwhmMnKa, escapePeaks: false)
                for g in model.groups { if let area = fx.areas[g.id] {
                    let col = EDSLineModel.column(of: g.lines, energies: energies, scale: axis.scale)
                    for i in mu.indices { mu[i] += area * col[i] }
                } }
                var rng = SplitMix64(state: seed)
                return mu.map { UInt64(poisson($0, &rng)) }
            }
            for seed in fx.seeds.prefix(1) {
                let c = counts(seed: seed)
                out.append("seed \(seed): counts fnv \(String(GoldenDump.fnv(c), radix: 16))")
                let seven = pooledInput(counts: c, axis: fx.axis, method: method(fx.listedSeven, beam: fx.beam, lock: true), name: "eds-realistic-l-sim.json")
                try quantify("seed\(seed).seven", seven, tables: nil, into: &out, unlisted: false)
                var fitTo60 = seven; fitTo60.method.fitToKeV = 60
                try quantify("seed\(seed).seven-60keV", fitTo60, tables: nil, into: &out, unlisted: false)
            }
            let four = pooledInput(counts: counts(seed: fx.seeds[0]), axis: fx.axis, method: method(fx.listedFour, beam: fx.beam, lock: true), name: "eds-realistic-l-sim.json")
            try quantify("seed\(fx.seeds[0]).four", four, tables: Q.tables, into: &out)
        }

        try add("eds-unlisted-sim") { out in
            let o = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: fixtures.appendingPathComponent("eds-unlisted-sim.json"))) as? [String: Any])
            let e = o["expected"] as! [Double]
            let axis = EnergyAxis(offset: o["offset"] as! Double, scale: o["scale"] as! Double, size: e.count)
            let beam = o["beam"] as! Double
            let four = ["O", "Si", "Ti", "Ni"]
            for seed: UInt64 in [0] {
                let c = draw(e, seed: seed)
                out.append("seed \(seed): counts fnv \(String(GoldenDump.fnv(c), radix: 16))")
                try quantify("seed\(seed).four", pooledInput(counts: c, axis: axis, method: method(four, beam: beam), name: "eds-unlisted-sim.json"),
                             tables: Q.tables, into: &out)
            }
            let seven = method(four, fitOnly: ["Ge", "Cu", "Ga"], beam: beam)
            try quantify("seed0.seven", pooledInput(counts: draw(e, seed: 0), axis: axis, method: seven, name: "eds-unlisted-sim.json"), tables: Q.tables, into: &out)
        }

        try add("eds-proposer-sim") { out in
            struct Sim: Decodable {
                struct Region: Decodable { let label: String; let expected: [Double] }
                let offset: Double, scale: Double, size: Int
                let regions: [Region]
            }
            let sim = try JSONDecoder().decode(Sim.self, from: Data(contentsOf: fixtures.appendingPathComponent("eds-proposer-sim.json")))
            let axis = EnergyAxis(offset: sim.offset, scale: sim.scale, size: sim.size)
            let st = FitSettings.standard(elements: ["Al", "Mg", "Si", "O"], axis: axis, resolutionMnKaEV: 130, beamEnergy: 200)
            for (i, r) in sim.regions.enumerated() where i == 2 {   // the densest region (sum peaks); the Debug proposer costs ~9 s a region
                let counts = draw(r.expected, seed: UInt64(5000 + i)).map { Double($0) }
                let result = try ElementProposer().propose(counts: counts, axis: axis, settings: st)
                GoldenDump.dump("region\(i)(\(r.label)).proposal", result, into: &out)
                let fit = try EDSFit.run(counts: counts, axis: axis, settings: st)
                GoldenDump.dump("region\(i).fit", fit, into: &out)
            }
        }

        try add("eds-weakline-sim") { out in
            let o = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: fixtures.appendingPathComponent("eds-weakline-sim.json"))) as? [String: Any])
            let axis = EnergyAxis(offset: o["offset"] as! Double, scale: o["scale"] as! Double, size: o["size"] as! Int)
            for (i, level) in (o["levels"] as! [[String: Any]]).enumerated() where i == 0 || i == 4 {
                let c = draw(level["expected"] as! [Double], seed: 2)
                let input = pooledInput(counts: c, axis: axis, method: method(["Al", "Mg", "Si"], fitOnly: ["O"]), name: "eds-weakline-sim.json")
                try quantify("level\(i)", input, tables: nil, into: &out, unlisted: false)
            }
        }
        return all
    }

    static var baselineDirectory: URL {
        GoldenQ.fixtures.appendingPathComponent("spectro-golden")
    }
}

@MainActor
final class SpectroGoldenTests: XCTestCase {
    private var recordDir: String? { ProcessInfo.processInfo.environment["SPECTRO_GOLDEN_DIR"] }

    /// RECORDER: with `TEST_RUNNER_SPECTRO_GOLDEN_DIR` set, writes one file per scenario there. Skipped otherwise.
    func testRecordBaseline() async throws {
        try XCTSkipIf(recordDir == nil, "set TEST_RUNNER_SPECTRO_GOLDEN_DIR to record")
        let dir = try XCTUnwrap(recordDir) 
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for s in try await SpectroGolden.scenarios() { try s.text.write(toFile: dir + "/" + s.name + ".txt", atomically: true, encoding: .utf8) }
        try SpectroGolden.times.joined(separator: "\n").write(toFile: dir + "/times.log", atomically: true, encoding: .utf8)   // not part of the baseline
    }

    /// COMPARISON: recomputes every scenario and compares each against the committed baseline, byte for byte, reporting the
    /// first differing line. Mutation: one bit of any fitted net flipped (net * (1 + 1e-15)) - red on that scenario's file.
    func testOutputsAreByteIdenticalToTheBaseline() async throws {
        try XCTSkipIf(recordDir != nil, "recording run")
        let scenarios = try await SpectroGolden.scenarios()
        XCTAssertEqual(scenarios.count, 6)   // mac4DSTEM's 7 minus demo-spectrum-fixture
        for s in scenarios {
            let url = SpectroGolden.baselineDirectory.appendingPathComponent(s.name + ".txt")
            let recorded = try String(contentsOf: url, encoding: .utf8)
            if s.text == recorded { continue }
            let a = s.text.split(separator: "\n", omittingEmptySubsequences: false), b = recorded.split(separator: "\n", omittingEmptySubsequences: false)
            let i = (0..<min(a.count, b.count)).first { a[$0] != b[$0] } ?? min(a.count, b.count)
            XCTFail("\(s.name) moved at line \(i + 1): now \(i < a.count ? String(a[i]) : "<end>") | baseline \(i < b.count ? String(b[i]) : "<end>")")
        }
    }
}
