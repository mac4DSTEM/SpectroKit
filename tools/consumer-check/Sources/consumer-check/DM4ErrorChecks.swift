//
//  DM4ErrorChecks.swift
//  Role: `DM4Error`'s six cases are public (since 0.1.0; a consumer can match them), and the ones SpectroCore itself throws are
//        thrown for the reasons the unit tests give (`DM4ExperimentTests+Spectro`,
//        `testOnlyA2DImageIsReadAndEachRefusalSaysWhy`).
//

import Foundation
import SpectroCore

/// An exhaustive switch over `DM4Error`: it compiles only while all six cases are visible to a consumer.
private func caseName(_ error: DM4Error) -> String {
    switch error {
    case .cannotOpen: "cannotOpen"
    case .notLittleEndian: "notLittleEndian"
    case .noDatacube: "noDatacube"
    case .unsupportedDataType: "unsupportedDataType"
    case .truncated: "truncated"
    case .volumeGone: "volumeGone"
    }
}

/// The `DM4Error` a call throws, nil if it throws nothing or another error.
private func thrown(_ body: () throws -> Void) -> DM4Error? {
    do { try body(); return nil } catch let error as DM4Error { return error } catch { return nil }
}

func dm4ErrorChecks(_ r: inout Report, _ fixtures: URL) throws {
    let url = fixtures.appendingPathComponent("demo-edx-tiny.dm4")
    let whole = try Data(contentsOf: url)

    // The cases a consumer can construct and read: all six, with their payloads.
    let constructed: [DM4Error] = [
        .cannotOpen("x"), .notLittleEndian, .noDatacube, .unsupportedDataType(23), .truncated, .volumeGone("d")]
    r.equal("DM4Error: six cases, matched exhaustively by a consumer", constructed.map(caseName),
            ["cannotOpen", "notLittleEndian", "noDatacube", "unsupportedDataType", "truncated", "volumeGone"])
    r.equal("DM4Error.errorDescription (LocalizedError) of unsupportedDataType(23)",
            constructed[3].errorDescription, "Unsupported DM image data type 23.")
    r.check("DM4Error.errorDescription of volumeGone names the volume",
            constructed[5].errorDescription?.hasPrefix("d is no longer reachable") == true)
    r.equal("DM4Error.errorDescription of cannotOpen carries the detail",
            constructed[0].errorDescription, "Could not open DM file: x")

    // The cases SpectroCore throws, each thrown by a public call.
    if case .unsupportedDataType(23)? = thrown({ _ = try DM4Experiment.readImage(path: url.path, index: 1) }) {
        r.check("readImage of the RGBA thumbnail throws .unsupportedDataType(23)", true)
    } else {
        r.check("readImage of the RGBA thumbnail throws .unsupportedDataType(23)", false)
    }
    if case .cannotOpen(let m)? = thrown({ _ = try DM4Experiment.readImage(path: url.path, index: 5) }) {
        r.check("readImage of the 3D EDS object throws .cannotOpen('... only a 2D image ...')",
                m.contains("only a 2D image"), m)
    } else {
        r.check("readImage of the 3D EDS object throws .cannotOpen", false)
    }
    if case .cannotOpen(let m)? = thrown({ _ = try DM4Experiment.readImage(data: whole, index: 9) }) {
        r.check("readImage of object 9 throws .cannotOpen('... no image object 9 ...')",
                m.contains("no image object 9"), m)
    } else {
        r.check("readImage of object 9 throws .cannotOpen", false)
    }
    let missing = fixtures.appendingPathComponent("no-such-file.dm4").path
    if case .cannotOpen? = thrown({ _ = try DM4Experiment.list(path: missing) }) {
        r.check("list(path:) of a missing file throws .cannotOpen", true)
    } else {
        r.check("list(path:) of a missing file throws .cannotOpen", false)
    }
    // Version 4, root length 0 (8 bytes), byte-order field 0 (big-endian): the header the walker refuses.
    let bigEndian = Data([0, 0, 0, 4] + [UInt8](repeating: 0, count: 8) + [0, 0, 0, 0])
    if case .notLittleEndian? = thrown({ _ = try DM4Experiment.list(data: bigEndian) }) {
        r.check("list(data:) of a big-endian header throws .notLittleEndian", true)
    } else {
        r.check("list(data:) of a big-endian header throws .notLittleEndian", false)
    }
    if case .truncated? = thrown({ _ = try DM4Experiment.list(data: whole.prefix(1000)) }) {
        r.check("list(data:) of the fixture cut at 1000 bytes throws .truncated", true)
    } else {
        r.check("list(data:) of the fixture cut at 1000 bytes throws .truncated", false)
    }
}
