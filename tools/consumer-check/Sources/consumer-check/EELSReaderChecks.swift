//
//  EELSReaderChecks.swift
//  Role: EELS slice 1b through the public surface only: `DM4Experiment.readEELSSpectrumImage(path:index:)` and
//        `(data:index:)`, every field of `DM4EELSSpectrumImage` (object, nx, ny, channels, counts, energyAxis,
//        beamEnergyKeV, convergenceSemiAngleMrad, collectionSemiAngleMrad) and its `Equatable`, on `eels-planted.dm4`
//        and `rsciio-EELS_SI.dm4` against their `.truth.json` (RosettaSciIO's own reading, tools/eels-reader/truth.py),
//        and the refusals (`DM4Error`) on the planted refused objects and the three wrong-length-Data-tag files.
//

import CryptoKit
import Foundation
import SpectroCore

private func sha256(_ counts: [Float]) -> String {
    SHA256.hash(data: counts.withUnsafeBytes { Data($0) }).map { String(format: "%02x", $0) }.joined()
}

/// The truth file's objects by one-based index.
private func truthObjects(_ url: URL) throws -> [Int: [String: Any]] {
    guard let list = try loadJSON(url)["objects"] as? [[String: Any]] else { throw CheckError("\(url.lastPathComponent): no objects") }
    return Dictionary(uniqueKeysWithValues: try list.map { entry in
        guard let index = entry["index"] as? Int else { throw CheckError("truth object without index") }
        return (index, entry)
    })
}

private func optionalNumber(_ entry: [String: Any], _ key: String) -> Double? { entry[key] as? Double }

func eelsReaderChecks(_ r: inout Report, _ fixtures: URL) throws {
    let planted = fixtures.appendingPathComponent("eels-planted.dm4")
    let real = fixtures.appendingPathComponent("rsciio-EELS_SI.dm4")
    let plantedBytes = try Data(contentsOf: planted), realBytes = try Data(contentsOf: real)
    let plantedTruth = try truthObjects(fixtures.appendingPathComponent("eels-planted.truth.json"))
    let realTruth = try truthObjects(fixtures.appendingPathComponent("rsciio-EELS_SI.truth.json"))

    /// One file's read of one object, against rsciio's reading of it.
    func compare(_ label: String, path: URL, bytes: Data, index: Int, truth: [String: Any]) throws {
        let byPath = try DM4Experiment.readEELSSpectrumImage(path: path.path, index: index)
        let byData = try DM4Experiment.readEELSSpectrumImage(data: bytes, index: index)
        r.check("\(label): readEELSSpectrumImage(path:index:) equals (data:index:)  [DM4EELSSpectrumImage: Equatable]", byPath == byData)
        r.equal("\(label): .nx", byPath.nx, truth["nx"] as? Int ?? -1)
        r.equal("\(label): .ny", byPath.ny, truth["ny"] as? Int ?? -1)
        r.equal("\(label): .channels", byPath.channels, truth["channels"] as? Int ?? -1)
        r.equal("\(label): .counts holds nx * ny * channels values", byPath.counts.count, byPath.nx * byPath.ny * byPath.channels)
        r.equal("\(label): .counts equal rsciio's (SHA-256, (y, x, channel) float32)", sha256(byPath.counts),
                truth["counts_sha256"] as? String ?? "")
        if let samples = truth["samples"] as? [[String: Any]] {
            var bad = [String]()
            for s in samples {
                guard let y = s["y"] as? Int, let x = s["x"] as? Int, let c = s["c"] as? Int, let v = s["value"] as? Double else { continue }
                if Double(byPath.counts[(y * byPath.nx + x) * byPath.channels + c]) != v { bad.append("(\(y),\(x),\(c))") }
            }
            r.check("\(label): .counts at rsciio's \(samples.count) sample voxels", bad.isEmpty && !samples.isEmpty, bad.joined(separator: " "))
        }
        if let axes = truth["rsciio_axes"] as? [[String: Any]], let energy = axes.first {
            r.check("\(label): .energyAxis is rsciio's Energy loss axis (offset = -origin * scale, scale, eV)",
                    -byPath.energyAxis.origin * byPath.energyAxis.scale == energy["offset"] as? Double
                    && byPath.energyAxis.scale == energy["scale"] as? Double && byPath.energyAxis.units == energy["units"] as? String,
                    "\(byPath.energyAxis)")
        }
        r.check("\(label): .beamEnergyKeV equals rsciio's", byPath.beamEnergyKeV == optionalNumber(truth, "beam_energy_keV"),
                "\(String(describing: byPath.beamEnergyKeV))")
        r.check("\(label): .convergenceSemiAngleMrad equals rsciio's",
                byPath.convergenceSemiAngleMrad == optionalNumber(truth, "convergence_angle_mrad"))
        r.check("\(label): .collectionSemiAngleMrad equals rsciio's",
                byPath.collectionSemiAngleMrad == optionalNumber(truth, "collection_angle_mrad"))
        let listed = try DM4Experiment.list(path: path.path)
        r.check("\(label): .object is the listed object (index, name)",
                byPath.object.index == index && byPath.object.name == truth["name"] as? String && listed.contains(byPath.object))
    }

    // The real file (RosettaSciIO's EELS_SI.dm4: 2 x 2 x 2048, 200 kV, 21 / 62 mrad) and the planted one (non-square 3 x 2 x 5).
    try compare("rsciio EELS_SI object 2", path: real, bytes: realBytes, index: 2, truth: try unwrap(realTruth[2]))
    let realRead = try DM4Experiment.readEELSSpectrumImage(path: real.path, index: 2)
    r.check("EELS_SI literals: 200 keV, 21 and 62 mrad, energy axis origin -300 scale 1 eV",
            realRead.beamEnergyKeV == 200 && realRead.convergenceSemiAngleMrad == 21 && realRead.collectionSemiAngleMrad == 62
            && realRead.energyAxis.origin == -300 && realRead.energyAxis.scale == 1 && realRead.energyAxis.units == "eV")
    for (index, what) in [(2, "float32, E0 80 kV and both angles"), (3, "int16, only E0"), (4, "uint16, only convergence"),
                          (6, "int8, no tags"), (10, "stack-builder tags"), (11, "one row"),
                          (18, "EELS by Meta Data.Signal alone"), (20, "stack group with only a string: no tags"),
                          (21, "the last block of the file")] {
        try compare("planted object \(index) (\(what))", path: planted, bytes: plantedBytes, index: index, truth: try unwrap(plantedTruth[index]))
    }
    let float32 = try DM4Experiment.readEELSSpectrumImage(path: planted.path, index: 2)
    r.check("planted 2: a literal voxel (x 2, y 1, c 3 is -10 + 128/4 = 22) and the cube is 3 x 2 x 5",
            float32.counts[(1 * 3 + 2) * 5 + 3] == 22 && [float32.nx, float32.ny, float32.channels] == [3, 2, 5])
    r.check("planted 2: E0 80, convergence 17.5, collection 33.25",
            float32.beamEnergyKeV == 80 && float32.convergenceSemiAngleMrad == 17.5 && float32.collectionSemiAngleMrad == 33.25)
    let bare = try DM4Experiment.readEELSSpectrumImage(path: planted.path, index: 6)
    r.check("planted 6 (no tags): beam energy and both angles are nil",
            bare.beamEnergyKeV == nil && bare.convergenceSemiAngleMrad == nil && bare.collectionSemiAngleMrad == nil)
    r.check("DM4EELSSpectrumImage Equatable: two different objects are not equal", float32 != bare)
    r.equal("planted 18 is listed as an EELS object (role)", try DM4Experiment.list(path: planted.path)[17].role, .eels)

    let stringOnly = try DM4Experiment.readEELSSpectrumImage(path: planted.path, index: 20)
    r.check("planted 20: the string-only stack group hides the top-level 60 kV / 1 / 2 mrad (all nil, as rsciio)",
            stringOnly.beamEnergyKeV == nil && stringOnly.convergenceSemiAngleMrad == nil && stringOnly.collectionSemiAngleMrad == nil
            && stringOnly.object.voltage == 60_000)

    // Refusals, on both entry points. cannotOpen: keV axis (19), 2D (14), no calibration (15), the survey (1), the EDS object (17);
    // unsupportedDataType(14): the bool object (16).
    func throwsCannotOpen(_ label: String, index: Int, contains: [String]) {
        for (entry, read) in [("path", { try DM4Experiment.readEELSSpectrumImage(path: planted.path, index: index) }),
                              ("data", { try DM4Experiment.readEELSSpectrumImage(data: plantedBytes, index: index) })] {
            do { _ = try read(); r.check("\(label) (\(entry)) is refused", false, "read it") }
            catch DM4Error.cannotOpen(let message) {
                r.check("\(label) (\(entry)) is refused with cannotOpen naming \(contains)", contains.allSatisfy(message.contains), message)
            } catch { r.check("\(label) (\(entry)) is refused with cannotOpen", false, "threw \(error)") }
        }
    }
    throwsCannotOpen("planted 19, third axis in keV", index: 19, contains: ["keV", "eV"])
    throwsCannotOpen("planted 14, two dimensions", index: 14, contains: ["[4, 3]"])
    throwsCannotOpen("planted 15, no energy calibration", index: 15, contains: ["no energy calibration"])
    throwsCannotOpen("planted 1, the survey", index: 1, contains: ["not an EELS spectrum image"])
    throwsCannotOpen("planted 17, the EDS object", index: 17, contains: ["not an EELS spectrum image"])
    throwsCannotOpen("planted 99, no such object", index: 99, contains: ["no image object 99"])
    do { _ = try DM4Experiment.readEELSSpectrumImage(path: planted.path, index: 16); r.check("planted 16 (bool) is refused", false) }
    catch DM4Error.unsupportedDataType(let code) { r.equal("planted 16 (bool) throws unsupportedDataType(14)", code, 14) }
    catch { r.check("planted 16 (bool) throws unsupportedDataType", false, "\(error)") }

    // A Data tag whose length is not the cube's (0, 29 or 31 elements for [3, 2, 5]): truncated, never a cube from the bytes after
    // the tag. RosettaSciIO raises on each file (the truth files record it).
    let zeroDim = fixtures.appendingPathComponent("eels-refused-zerodim.dm4")
    do { _ = try DM4Experiment.readEELSSpectrumImage(path: zeroDim.path, index: 1); r.check("eels-refused-zerodim ([3, 0, 5]) is refused", false) }
    catch DM4Error.cannotOpen(let message) { r.check("eels-refused-zerodim ([3, 0, 5]) is refused with cannotOpen naming its dimensions", message.contains("[3, 0, 5]"), message) }
    catch { r.check("eels-refused-zerodim is refused with cannotOpen", false, "\(error)") }
    for name in ["zero", "short", "long"] {
        let file = fixtures.appendingPathComponent("eels-refused-\(name).dm4")
        let truth = try loadJSON(fixtures.appendingPathComponent("eels-refused-\(name).truth.json"))
        r.check("eels-refused-\(name): rsciio raises on it", truth["rsciio_raises"] as? Bool == true)
        let bytes = try Data(contentsOf: file)
        for (entry, read) in [("path", { try DM4Experiment.readEELSSpectrumImage(path: file.path, index: 1) }),
                              ("data", { try DM4Experiment.readEELSSpectrumImage(data: bytes, index: 1) })] {
            do { _ = try read(); r.check("eels-refused-\(name) (\(entry)) throws truncated", false, "read a cube") }
            catch DM4Error.truncated { r.check("eels-refused-\(name) (\(entry)) throws DM4Error.truncated", true) }
            catch { r.check("eels-refused-\(name) (\(entry)) throws DM4Error.truncated", false, "\(error)") }
        }
    }
}

private func unwrap<T>(_ value: T?) throws -> T {
    guard let value else { throw CheckError("truth is missing an object") }
    return value
}
