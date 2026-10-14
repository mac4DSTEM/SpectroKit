//
//  main.swift
//  Role: dump what SpectroCore's public Velox reader says about every image of the .emd files named on the command
//        line, as JSON, for tools/velox-metadata-parity/compare.py. Public API only (`VeloxEMDReader(path:).images()`):
//        this package depends on SpectroKit by path, so a field that is not `public` does not compile here.
//
//  Output: {"files": {<path>: {"entries": {<image id>: {...}}} | {"error": <kind>, "detail": <text>}}}. A Double is
//  {"bits": 16 hex digits of its IEEE-754 pattern, "text": "%.17g"}; nil is null; strings are verbatim.
//

import Foundation
import SpectroCore

func number(_ x: Double?) -> Any {
    guard let x else { return NSNull() }
    return ["bits": String(format: "%016llx", x.bitPattern), "text": String(format: "%.17g", x)]
}

func string(_ s: String?) -> Any { s ?? NSNull() }

func entry(_ image: VeloxImageInfo) -> [String: Any] {
    let m = image.metadata
    let detectors = m.detectors.map { d -> [String: Any] in
        ["index": d.index, "name": d.name, "type": d.type, "exposureTimeSeconds": number(d.exposureTimeSeconds)]
    }
    return [
        "binaryResultDetector": string(m.binaryResultDetector),
        "nominalMagnification": number(m.nominalMagnification),
        "stemMagnification": number(m.stemMagnification),
        "cameraLengthMeters": number(m.cameraLengthMeters),
        "operatingMode": string(m.operatingMode),
        "projectorMode": string(m.projectorMode),
        "exposureTimeSeconds": number(m.exposureTimeSeconds),
        "detectors": detectors,
    ]
}

var files: [String: Any] = [:]
for path in CommandLine.arguments.dropFirst() {
    do {
        var entries: [String: Any] = [:]
        for image in try VeloxEMDReader(path: path).images() { entries[image.id] = entry(image) }
        files[path] = ["entries": entries]
    } catch VeloxEMDError.notVeloxFile {
        files[path] = ["error": "notVeloxFile"]
    } catch {
        files[path] = ["error": "other", "detail": "\(error)"]
    }
}
let data = try JSONSerialization.data(withJSONObject: ["files": files], options: [.sortedKeys])
FileHandle.standardOutput.write(data)
FileHandle.standardOutput.write(Data("\n".utf8))
