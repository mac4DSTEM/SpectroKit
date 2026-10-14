//
//  main.swift (eels-real-data)
//  Role: The Swift side of the registered real-data check (docs/eels-real-data-check-registration.md section 2):
//
//    eels-real-data r1 <file.dm4> <out.json>
//        Every image object of the file: name, index, role, dimensions; for every object `readEELSSpectrumImage` accepts:
//        shape, energy axis, E0, α, β, the sha256 of its float32 counts in SpectroKit's (y, x, channel) order (little-endian),
//        their sum, and the read time. RosettaSciIO's side is r1_rsciio.py; compare.py compares.
//    eels-real-data r2 <file.dm4> <index> <outdir>
//        `EELSThickness.logRatio` on that low-loss SI with fixed 3.0 eV, fixed 5.0 eV and the estimated rule (exSpy's
//        defaults): per rule <outdir>/<rule>.f64 (per pixel: I_0, I_t, t/λ, threshold channel, zlpCentre, σ; NaN where nil;
//        float64 little-endian, 6 values per pixel in row-major (y, x) order) and <outdir>/<rule>.json (diagnostics of
//        section 3: percentiles, nil reasons, tol, times). The f64 files are scratch (not committed); exSpy's side is
//        r2_exspy.py.
//    eels-real-data edge <file.dm4> <lowLossIndex> <coreLossIndex> <dose> <outdir>
//        EELS slice 2's diagnostic (docs/eels-slice-2-registration.md section 8; never a gate): `EELSEdgeQuantification
//        .ratioMethod` for C, N and O K with the default windows and Δ = 50 eV, I_low(Δ) and I_0 (fixed 5 eV) routes, E0, α, β
//        from the file's tags, `dose` = exposure(core loss) / exposure(low loss) as read from the tags by the caller.
//        Per edge and route <outdir>/<edge>-<route>.f64 (per pixel, row-major: n, σ_n, I_k, I_b, r; NaN where nil) and .json
//        (percentiles, nil reasons, the cross section, the effective angle, the windows, times).
//

import CryptoKit
import Foundation
import SpectroCore
import SpectroEELS

func fail(_ s: String) -> Never { FileHandle.standardError.write(Data((s + "\n").utf8)); exit(1) }

func writeJSON(_ obj: Any, _ path: String) throws {
    let data = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: URL(fileURLWithPath: path))
}

func j(_ v: Double?) -> Any { v ?? NSNull() }

func now() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e9 }

func sha256(_ counts: [Float]) -> String {
    var h = SHA256()
    counts.withUnsafeBufferPointer { b in
        // Float's in-memory layout is little-endian IEEE single on this platform.
        h.update(bufferPointer: UnsafeRawBufferPointer(b))
    }
    return h.finalize().map { String(format: "%02x", $0) }.joined()
}

func percentile(_ v: [Double], _ p: Double) -> Double? {
    let s = v.filter { $0.isFinite }.sorted()
    guard !s.isEmpty else { return nil }
    let pos = p / 100 * Double(s.count - 1)                     // NumPy's default "linear" percentile
    let lo = Int(pos.rounded(.down)), hi = min(lo + 1, s.count - 1)
    return s[lo] + (s[hi] - s[lo]) * (pos - Double(lo))
}

func r1(_ path: String, _ out: String) throws {
    let objects = try DM4Experiment.list(path: path)
    var rows = [[String: Any]]()
    for o in objects {
        var row: [String: Any] = ["index": o.index, "name": o.name, "role": o.role.rawValue, "dimensions": o.dimensions]
        let t0 = now()
        do {
            let si = try DM4Experiment.readEELSSpectrumImage(path: path, index: o.index)
            row["eels"] = [
                "nx": si.nx, "ny": si.ny, "channels": si.channels,
                "energyOrigin": si.energyAxis.origin, "energyScale": si.energyAxis.scale, "energyUnits": si.energyAxis.units,
                "beamEnergyKeV": j(si.beamEnergyKeV), "convergenceMrad": j(si.convergenceSemiAngleMrad),
                "collectionMrad": j(si.collectionSemiAngleMrad),
                "countsSha256": sha256(si.counts), "countsSum": si.counts.reduce(0.0) { $0 + Double($1) },
                "readSeconds": now() - t0,
            ] as [String: Any]
        } catch {
            row["notEELS"] = "\(error)"
        }
        rows.append(row)
    }
    try writeJSON(["file": path, "objects": rows, "tool": "eels-real-data r1"], out)
}

func r2(_ path: String, _ index: Int, _ outdir: String) throws {
    let t0 = now()
    let si = try DM4Experiment.readEELSSpectrumImage(path: path, index: index)
    let readSeconds = now() - t0
    guard si.energyAxis.units == "eV" else { fail("energy axis in \(si.energyAxis.units)") }
    // DM4 energy axis: E = (c - origin) * scale (the DM convention RosettaSciIO maps to offset = -origin * scale).
    let offset = -si.energyAxis.origin * si.energyAxis.scale
    let image = try LowLossSpectrumImage(nx: si.nx, ny: si.ny, channels: si.channels, counts: si.counts,
                                         energyOffsetEV: offset, energyScaleEV: si.energyAxis.scale)
    try FileManager.default.createDirectory(atPath: outdir, withIntermediateDirectories: true)
    for (name, rule) in [("fixed3", ThresholdRule.fixed(3.0)), ("fixed5", .fixed(5.0)), ("estimated", .estimated())] {
        let t1 = now()
        let map = try EELSThickness.logRatio(image, threshold: rule)
        let secs = now() - t1
        var flat = [Double]()
        flat.reserveCapacity(map.pixels.count * 6)
        var reasons = [String: Int]()
        for p in map.pixels {
            flat += [p.i0 ?? .nan, p.iTotal, p.tOverLambda ?? .nan, p.thresholdChannel.map(Double.init) ?? .nan,
                     p.zlpCentreEV, p.sigmaCounting ?? .nan]
            if let u = p.unavailable { reasons[u.rawValue, default: 0] += 1 }
        }
        let data = flat.withUnsafeBufferPointer { Data(buffer: $0) }
        try data.write(to: URL(fileURLWithPath: "\(outdir)/\(name).f64"))
        let t = map.pixels.compactMap(\.tOverLambda), z = map.pixels.map(\.zlpCentreEV)
        let s = map.pixels.compactMap(\.sigmaCounting), th = map.pixels.compactMap(\.thresholdEV)
        let off = Double(z.filter { abs($0) > 0.75 }.count) / Double(z.count)
        let diag: [String: Any] = [
            "rule": name, "pixels": map.pixels.count, "nil": map.pixels.count - t.count, "nilReasons": reasons,
            "tOverLambda": ["p1": j(percentile(t, 1)), "median": j(percentile(t, 50)), "p99": j(percentile(t, 99)),
                            "below0": t.filter { $0 < 0 }.count, "above3": t.filter { $0 > 3 }.count],
            "zlpCentreEV": ["p1": percentile(z, 1)!, "median": percentile(z, 50)!, "p99": percentile(z, 99)!,
                            "fractionBeyondOneChannel": off, "needsZeroLossAlignment": off > 0.05],
            "sigmaCountingMedian": j(percentile(s, 50)),
            "thresholdEV": ["p1": j(percentile(th, 1)), "median": j(percentile(th, 50)), "p99": j(percentile(th, 99))],
            "estimatedTolerance": j(map.estimatedTolerance), "validation": map.validation, "method": map.method,
            "seconds": secs, "readSeconds": readSeconds, "energyOffsetEV": offset, "energyScaleEV": si.energyAxis.scale,
            "nx": si.nx, "ny": si.ny, "channels": si.channels,
        ]
        try writeJSON(diag, "\(outdir)/\(name).json")
    }
}

func edge(_ path: String, _ llIndex: Int, _ hlIndex: Int, _ dose: Double, _ outdir: String) throws {
    let ll = try DM4Experiment.readEELSSpectrumImage(path: path, index: llIndex)
    let hl = try DM4Experiment.readEELSSpectrumImage(path: path, index: hlIndex)
    guard ll.energyAxis.units == "eV", hl.energyAxis.units == "eV" else { fail("energy axis not in eV") }
    guard let e0 = hl.beamEnergyKeV, let alpha = hl.convergenceSemiAngleMrad, let beta = hl.collectionSemiAngleMrad else {
        fail("E0, alpha or beta missing from the tags")
    }
    let low = try LowLossSpectrumImage(nx: ll.nx, ny: ll.ny, channels: ll.channels, counts: ll.counts,
                                       energyOffsetEV: -ll.energyAxis.origin * ll.energyAxis.scale, energyScaleEV: ll.energyAxis.scale)
    let core = try CoreLossSpectrumImage(nx: hl.nx, ny: hl.ny, channels: hl.channels, counts: hl.counts,
                                         energyOffsetEV: -hl.energyAxis.origin * hl.energyAxis.scale, energyScaleEV: hl.energyAxis.scale)
    let microscope = EELSMicroscope(beamEnergyKeV: e0, convergenceMrad: alpha, collectionMrad: beta)
    try FileManager.default.createDirectory(atPath: outdir, withIntermediateDirectories: true)
    let thickness = try EELSThickness.logRatio(low, threshold: .fixed(5.0))
    for e in CoreLossEdge.bundled {
        for (route, ilow) in [("ilowDelta", LowLossIntensity.integratedToWidth(low)), ("i0", .zeroLoss(thickness))] {
            let t0 = now()
            let map = try EELSEdgeQuantification.ratioMethod(coreLoss: core, edge: e, microscope: microscope, lowLoss: ilow,
                                                             coreLossToLowLossDose: dose)
            let secs = now() - t0
            var flat = [Double]()
            var reasons = [String: Int]()
            for p in map.pixels {
                flat += [p.atomsPerNM2 ?? .nan, p.sigmaCounting ?? .nan, p.edgeCounts ?? .nan, p.backgroundCounts ?? .nan,
                         p.powerLawR ?? .nan]
                if let u = p.unavailable { reasons[u.rawValue, default: 0] += 1 }
            }
            try flat.withUnsafeBufferPointer { Data(buffer: $0) }.write(to: URL(fileURLWithPath: "\(outdir)/\(e.element)K-\(route).f64"))
            let n = map.pixels.compactMap(\.atomsPerNM2), s = map.pixels.compactMap(\.sigmaCounting)
            let r = map.pixels.compactMap(\.powerLawR)
            let rel = zip(map.pixels.compactMap(\.sigmaCounting), map.pixels.compactMap(\.atomsPerNM2)).map { abs($0 / $1) }
            let diag: [String: Any] = [
                "edge": e.description, "route": route, "lowLossRoute": map.lowLossRoute, "pixels": map.pixels.count,
                "nil": map.pixels.count - n.count, "nilReasons": reasons,
                "atomsPerNM2": ["p1": j(percentile(n, 1)), "median": j(percentile(n, 50)), "p99": j(percentile(n, 99)),
                                "negative": n.filter { $0 < 0 }.count],
                "sigmaCountingMedian": j(percentile(s, 50)), "relativeSigmaMedian": j(percentile(rel, 50)),
                "powerLawR": ["p1": j(percentile(r, 1)), "median": j(percentile(r, 50)), "p99": j(percentile(r, 99))],
                "crossSectionBarn": map.crossSectionBarn, "effectiveCollectionMrad": map.effectiveCollectionMrad,
                "backgroundWindowEV": [map.backgroundWindowEV.lowerBound, map.backgroundWindowEV.upperBound],
                "edgeWindowEV": [map.edgeWindowEV.lowerBound, map.edgeWindowEV.upperBound],
                "beamEnergyKeV": e0, "convergenceMrad": alpha, "collectionMrad": beta, "coreLossToLowLossDose": dose,
                "validation": map.validation, "method": map.method, "seconds": secs, "nx": hl.nx, "ny": hl.ny,
            ]
            try writeJSON(diag, "\(outdir)/\(e.element)K-\(route).json")
        }
    }
}

let args = CommandLine.arguments
do {
    switch args.dropFirst().first {
    case "r1" where args.count == 4: try r1(args[2], args[3])
    case "r2" where args.count == 5:
        guard let index = Int(args[3]) else { fail("index") }
        try r2(args[2], index, args[4])
    case "edge" where args.count == 7:
        guard let li = Int(args[3]), let hi = Int(args[4]), let dose = Double(args[5]) else { fail("indices or dose") }
        try edge(args[2], li, hi, dose, args[6])
    default: fail("usage: eels-real-data r1 <file> <out.json> | r2 <file> <index> <outdir>")
    }
} catch { fail("eels-real-data: \(error)") }
