//
//  VeloxChecks.swift
//  Role: ask 2 of macTEM (the Velox metadata fields; five from its ask of 2026-10-13, the sixth the owner's of
//        2026-10-14) through the public surface: `VeloxMetadata`'s `nominalMagnification`, `stemMagnification`,
//        `cameraLengthMeters`, `operatingMode`, `projectorMode`, `exposureTimeSeconds`, and
//        `VeloxDetectorInfo.exposureTimeSeconds`. The committed `velox-tiny.emd` carries none of them, so all are nil
//        on it; their values and rules are checked on metadata JSON through the public `VeloxMetadata.parse(jsonData:)`
//        (the rules are those of the doc comments on `VeloxMetadata` and of RosettaSciIO 049e7d70 `_emd_velox.py`),
//        and, in `veloxPlantedChecks`, end to end on the planted Velox file through `VeloxEMDReader(path:).images()`.
//

import Foundation
import SpectroCore

private func parse(_ json: String) throws -> VeloxMetadata {
    try VeloxMetadata.parse(jsonData: Data(json.utf8))
}

/// True when all six `VeloxMetadata` fields of this ask are nil.
private func allSixNil(_ m: VeloxMetadata) -> Bool {
    m.nominalMagnification == nil && m.stemMagnification == nil && m.cameraLengthMeters == nil
        && m.operatingMode == nil && m.projectorMode == nil && m.exposureTimeSeconds == nil
}

func veloxChecks(_ r: inout Report, _ fixtures: URL) throws {
    let path = fixtures.appendingPathComponent("velox-tiny.emd").path

    // The committed file, as macTEM reads it: VeloxEMDReader(path:).images()[*].metadata.
    r.check("VeloxEMDReader.isVeloxFile(path:) on velox-tiny.emd", VeloxEMDReader.isVeloxFile(path: path))
    let images = try VeloxEMDReader(path: path).images()
    r.check("VeloxEMDReader(path:).images() lists at least one image", !images.isEmpty)
    for image in images {
        let m = image.metadata
        let id = "velox-tiny '\(image.id)' (\(image.detectorName), \(image.width) x \(image.height))"
        r.check("\(id): the six VeloxMetadata fields are nil", allSixNil(m))
        r.equal("\(id): VeloxDetectorInfo.exposureTimeSeconds is nil on all \(m.detectors.count) detectors",
                m.detectors.compactMap(\.exposureTimeSeconds).count, 0)
    }

    // Velox stores every number as a string. A camera image carries both magnifications.
    let camera = try parse(#"""
        {"Optics": {"NominalMagnification": "8609.4279999999999", "CameraLength": "0.125", "OperatingMode": "1",
                    "ProjectorMode": "2", "AccelerationVoltage": "200000"},
         "CustomProperties": {"StemMagnification": {"type": "double", "value": "115000"}},
         "BinaryResult": {"Detector": "BM-Ceta", "DetectorIndex": "1"},
         "Detectors": {
           "Detector-0": {"DetectorName": "BM-Ceta-2", "DetectorType": "ImagingDetector", "ExposureTime": "9"},
           "Detector-1": {"DetectorName": "BM-Ceta", "DetectorType": "ImagingDetector", "ExposureTime": "0.5"},
           "Detector-2": {"DetectorName": "BM-Ceta", "DetectorType": "ImagingDetector", "ExposureTime": "7"}}}
        """#)
    r.equal("VeloxMetadata.nominalMagnification = Optics.NominalMagnification as stored",
            camera.nominalMagnification, 8609.4279999999999)
    r.equal("VeloxMetadata.stemMagnification = CustomProperties.StemMagnification.value as stored",
            camera.stemMagnification, 115_000)
    r.equal("VeloxMetadata.cameraLengthMeters = Optics.CameraLength as stored (metres, no conversion)",
            camera.cameraLengthMeters, 0.125)
    r.equal("VeloxMetadata.operatingMode = Optics.OperatingMode as stored (a string)", camera.operatingMode, "1")
    r.equal("VeloxMetadata.projectorMode = Optics.ProjectorMode as stored (a string)", camera.projectorMode, "2")
    r.equal("VeloxMetadata.exposureTimeSeconds = ExposureTime of the first entry whose name EQUALS BinaryResult.Detector"
            + " (not BM-Ceta-2, which contains it; not the duplicate after it)", camera.exposureTimeSeconds, 0.5)
    r.equal("VeloxDetectorInfo.exposureTimeSeconds per detector, each its own", camera.detectors.map(\.exposureTimeSeconds),
            [9, 0.5, 7])
    r.equal("the older fields are unchanged (AccelerationVoltage)", camera.accelerationVoltageVolts, 200_000)
    r.equal("the older fields are unchanged (BinaryResult.Detector)", camera.binaryResultDetector, "BM-Ceta")

    // A STEM image: the stem magnification is its magnification and is not copied to the nominal one; the binary
    // detector (HAADF) has no ExposureTime while another entry (BM-Ceta) has.
    let stem = try parse(#"""
        {"Optics": {"AccelerationVoltage": "200000", "CameraLength": "0.15", "OperatingMode": "1", "ProjectorMode": "1"},
         "CustomProperties": {"StemMagnification": {"type": "double", "value": "225000"}},
         "BinaryResult": {"Detector": "HAADF", "DetectorIndex": "0"},
         "Detectors": {
           "Detector-0": {"DetectorName": "HAADF", "DetectorType": "ScanningDetector"},
           "Detector-1": {"DetectorName": "BM-Ceta", "DetectorType": "ImagingDetector", "ExposureTime": "0.5"}}}
        """#)
    r.equal("a STEM-like image: stemMagnification 225000", stem.stemMagnification, 225_000)
    r.check("a STEM-like image: nominalMagnification is nil (StemMagnification is not copied into it)",
            stem.nominalMagnification == nil)
    r.check("a STEM-like image: exposureTimeSeconds is nil (the binary detector's entry has none)",
            stem.exposureTimeSeconds == nil)
    r.equal("a STEM-like image: the other detector keeps its own exposure", stem.detectors.map(\.exposureTimeSeconds),
            [nil, 0.5])

    // The two magnifications are different keys: neither is a fallback for the other.
    let onlyNominal = try parse(#"{"Optics": {"NominalMagnification": "60000"}}"#)
    r.check("nominalMagnification alone: stemMagnification is nil, not a copy",
            onlyNominal.nominalMagnification == 60_000 && onlyNominal.stemMagnification == nil)
    let noValue = try parse(#"""
        {"Optics": {"NominalMagnification": "60000"}, "CustomProperties": {"StemMagnification": {"type": "double"}}}
        """#)
    r.check("StemMagnification without a 'value' key: nil, though a nominal magnification is there to fall back on",
            noValue.stemMagnification == nil && noValue.nominalMagnification == 60_000)
    let bareString = try parse(#"""
        {"Optics": {"NominalMagnification": "70000"}, "CustomProperties": {"StemMagnification": "250000"}}
        """#)
    r.check("StemMagnification as a bare string (not the {type, value} object): nil",
            bareString.stemMagnification == nil && bareString.nominalMagnification == 70_000)
    for custom in [#""""#, #""225000""#] {
        let m = try parse(#"""
            {"Optics": {"NominalMagnification": "80000", "CameraLength": "0.2", "OperatingMode": "2"},
             "CustomProperties": \#(custom), "BinaryResult": {"Detector": "BM-Ceta"},
             "Detectors": {"Detector-0": {"DetectorName": "BM-Ceta", "ExposureTime": "1.25"}}}
            """#)
        r.check("CustomProperties that is the string \(custom): stem magnification and scan transformation nil, the rest read",
                m.stemMagnification == nil && m.scanTransformation == nil && m.nominalMagnification == 80_000
                && m.cameraLengthMeters == 0.2 && m.operatingMode == "2" && m.exposureTimeSeconds == 1.25)
    }
    let beside = try parse(#"""
        {"CustomProperties": {"Detectors[BM-Ceta].TimeStamp": {"type": "double", "value": "1.6e+015"},
                              "Scan.ScanTransformation.A11": {"type": "double", "value": "1.5"},
                              "Scan.ScanTransformation.A12": {"type": "double", "value": "0.25"},
                              "Scan.ScanTransformation.A13": {"type": "double", "value": "2"},
                              "Scan.ScanTransformation.A21": {"type": "double", "value": "-0.25"},
                              "Scan.ScanTransformation.A22": {"type": "double", "value": "1.5"},
                              "Scan.ScanTransformation.A23": {"type": "double", "value": "-3"},
                              "StemMagnification": {"type": "double", "value": "225000"}}}
        """#)
    r.check("StemMagnification beside the flat Scan.ScanTransformation entries: both read",
            beside.stemMagnification == 225_000 && beside.scanTransformation?.a13 == 2
            && beside.scanTransformation?.a23 == -3)

    // JSON numbers are read (the stem magnification's value too); a mode that is a JSON number is nil.
    let numbers = try parse(#"""
        {"Optics": {"NominalMagnification": 49000.5, "CameraLength": 0.0625, "OperatingMode": 1, "ProjectorMode": 2},
         "CustomProperties": {"StemMagnification": {"type": "double", "value": 62500.5}},
         "BinaryResult": {"Detector": "BM-Ceta"},
         "Detectors": {"Detector-0": {"DetectorName": "BM-Ceta", "ExposureTime": 0.25}}}
        """#)
    r.check("JSON numbers are read: nominal 49000.5, stem 62500.5, camera length 0.0625, exposure 0.25",
            numbers.nominalMagnification == 49_000.5 && numbers.stemMagnification == 62_500.5
            && numbers.cameraLengthMeters == 0.0625 && numbers.exposureTimeSeconds == 0.25
            && numbers.detectors.first?.exposureTimeSeconds == 0.25)
    r.check("a mode stored as a JSON number is nil, not \"1\"", numbers.operatingMode == nil && numbers.projectorMode == nil)

    // Not a number is nil; a JSON null is absent; a mode string is kept as stored, whatever it says.
    let unparsable = try parse(#"""
        {"Optics": {"NominalMagnification": "", "CameraLength": "abc", "OperatingMode": "TEM", "ProjectorMode": null},
         "CustomProperties": {"StemMagnification": {"type": "double", "value": "abc"}},
         "BinaryResult": {"Detector": "BM-Ceta"},
         "Detectors": {"Detector-0": {"DetectorName": "BM-Ceta", "ExposureTime": "n/a"}}}
        """#)
    r.check("\"\", \"abc\" and \"n/a\" are nil in every numeric field; null is absent; the mode \"TEM\" is kept as stored",
            unparsable.nominalMagnification == nil && unparsable.stemMagnification == nil
            && unparsable.cameraLengthMeters == nil && unparsable.exposureTimeSeconds == nil
            && unparsable.operatingMode == "TEM" && unparsable.projectorMode == nil)
    let nullStem = try parse(#"{"CustomProperties": {"StemMagnification": {"type": "double", "value": null}}}"#)
    r.check("StemMagnification.value that is JSON null: nil", nullStem.stemMagnification == nil)

    // The exponent forms Velox files store, with the leading zeros a C runtime's %e writes.
    let exponent = try parse(#"""
        {"Optics": {"NominalMagnification": "1e5", "CameraLength": "1.5e-1"},
         "CustomProperties": {"StemMagnification": {"type": "double", "value": "1.3e+006"}},
         "BinaryResult": {"Detector": "BM-Ceta"},
         "Detectors": {"Detector-0": {"DetectorName": "BM-Ceta", "ExposureTime": "2.5E-001"}}}
        """#)
    r.check("scientific notation as stored: 1e5, 1.5e-1, 1.3e+006, 2.5E-001",
            exponent.nominalMagnification == 100_000 && exponent.cameraLengthMeters == 0.15
            && exponent.stemMagnification == 1_300_000 && exponent.exposureTimeSeconds == 0.25)

    // Zero is a value, not an absence; the stem entry's "type" is not consulted (three public camera images store
    // {"type": "bool", "value": "0"}).
    let zeros = try parse(#"""
        {"Optics": {"NominalMagnification": "0", "CameraLength": "0", "OperatingMode": "0", "ProjectorMode": "0"},
         "CustomProperties": {"StemMagnification": {"type": "bool", "value": "0"}},
         "BinaryResult": {"Detector": "BM-Ceta"},
         "Detectors": {"Detector-0": {"DetectorName": "BM-Ceta", "ExposureTime": "0"}}}
        """#)
    r.check("\"0\" is 0 in every numeric field (stem entry typed bool), and the modes are the strings \"0\"",
            zeros.nominalMagnification == 0 && zeros.stemMagnification == 0 && zeros.cameraLengthMeters == 0
            && zeros.exposureTimeSeconds == 0 && zeros.operatingMode == "0" && zeros.projectorMode == "0")

    // The exposure rule: the first entry, in Detector-<n> index order, whose DetectorName equals BinaryResult.Detector.
    let wrongCase = try parse(#"""
        {"BinaryResult": {"Detector": "bm-ceta"},
         "Detectors": {"Detector-0": {"DetectorName": "BM-Ceta", "ExposureTime": "0.5"}}}
        """#)
    r.check("exposure: the name match is case-sensitive", wrongCase.exposureTimeSeconds == nil)
    let onlyContaining = try parse(#"""
        {"BinaryResult": {"Detector": "BM-Ceta"},
         "Detectors": {"Detector-0": {"DetectorName": "BM-Ceta-2", "ExposureTime": "9"}}}
        """#)
    r.check("exposure: a name that merely contains the binary detector's is not it", onlyContaining.exposureTimeSeconds == nil)
    let noName = try parse(#"""
        {"BinaryResult": {"DetectorIndex": "0"},
         "Detectors": {"Detector-0": {"DetectorName": "BM-Ceta", "ExposureTime": "0.5"}}}
        """#)
    r.check("exposure: BinaryResult without a Detector leaves it nil, the entry still reports its own 0.5",
            noName.exposureTimeSeconds == nil && noName.detectors.first?.exposureTimeSeconds == 0.5)
    let noBinary = try parse(#"{"Detectors": {"Detector-0": {"DetectorName": "BM-Ceta", "ExposureTime": "0.5"}}}"#)
    r.check("exposure: no BinaryResult section leaves it nil", noBinary.exposureTimeSeconds == nil)
    let emptyName = try parse(#"""
        {"BinaryResult": {"Detector": ""},
         "Detectors": {"Detector-0": {"DetectorType": "ImagingDetector", "ExposureTime": "0.75"},
                       "Detector-1": {"DetectorName": "BM-Ceta", "ExposureTime": "0.5"}}}
        """#)
    r.check("exposure: an empty BinaryResult.Detector matches no entry, not even an unnamed one (listed with name \"\")",
            emptyName.binaryResultDetector == "" && emptyName.detectors.first?.name == ""
            && emptyName.detectors.first?.exposureTimeSeconds == 0.75 && emptyName.exposureTimeSeconds == nil)
    let firstDecides = try parse(#"""
        {"BinaryResult": {"Detector": "BM-Ceta"},
         "Detectors": {"Detector-0": {"DetectorName": "BM-Ceta"},
                       "Detector-1": {"DetectorName": "BM-Ceta", "ExposureTime": "2"}}}
        """#)
    r.check("exposure: the first entry of the name decides even without an ExposureTime (nil, not 2)",
            firstDecides.exposureTimeSeconds == nil && firstDecides.detectors.map(\.exposureTimeSeconds) == [nil, 2])
    // Keys written 11 ... 0 (a JSON object has no order in Swift): "first" is the lowest Detector-<n> index, numerically.
    let descending = (0...11).reversed().map { i in
        i == 0 ? #""Detector-0": {"DetectorName": "HAADF"}"#
               : #""Detector-\#(i)": {"DetectorName": "BM-Ceta", "ExposureTime": "\#(i * 10)"}"#
    }.joined(separator: ", ")
    let byIndex = try parse(#"{"BinaryResult": {"Detector": "BM-Ceta"}, "Detectors": {"# + descending + "}}")
    r.check("exposure: keys written 11 ... 0, the first BM-Ceta is Detector-1 (ExposureTime 10), detectors sorted by index",
            byIndex.exposureTimeSeconds == 10 && byIndex.detectors.map(\.index) == Array(0...11))
    let numeric = try parse(#"""
        {"BinaryResult": {"Detector": "BM-Ceta"},
         "Detectors": {"Detector-11": {"DetectorName": "BM-Ceta", "ExposureTime": "11"},
                       "Detector-10": {"DetectorName": "BM-Ceta", "ExposureTime": "10"},
                       "Detector-9": {"DetectorName": "BM-Ceta", "ExposureTime": "9"},
                       "Detector-2": {"DetectorName": "HAADF"}}}
        """#)
    r.check("exposure: the index order is numeric (Detector-9 before Detector-10): [2, 9, 10, 11], exposure 9",
            numeric.detectors.map(\.index) == [2, 9, 10, 11] && numeric.exposureTimeSeconds == 9)

    // Nothing in the tree: every field nil.
    r.check("an empty metadata tree leaves the six fields nil", allSixNil(try parse("{}")))
    r.check("a tree with only BinaryResult.Detector leaves the six fields nil",
            allSixNil(try parse(#"{"BinaryResult": {"Detector": "BM-Ceta"}}"#)))
}

/// `Tests/SpectroKitTests/Fixtures/velox-metadata-planted.emd` through the public reader, against its `.truth.json`
/// (the values `tools/velox-metadata-parity/make_fixture.py` plants; column 0 of each image's Metadata holds them and
/// column 1 is a decoy with a different value in every field).
func veloxPlantedChecks(_ r: inout Report, _ plantedFixtures: URL) throws {
    let path = plantedFixtures.appendingPathComponent("velox-metadata-planted.emd").path
    let truth = try loadJSON(plantedFixtures.appendingPathComponent("velox-metadata-planted.truth.json"))
    r.check("VeloxEMDReader.isVeloxFile(path:) on velox-metadata-planted.emd", VeloxEMDReader.isVeloxFile(path: path))
    let images = try VeloxEMDReader(path: path).images()
    r.equal("the planted file lists the truth's \(truth.count) images (ids)", Set(images.map(\.id)), Set(truth.keys))

    for image in images {
        guard let want = truth[image.id] as? [String: Any] else { continue }
        let m = image.metadata
        var wrong: [String] = []
        func number(_ key: String, _ got: Double?) {
            let expected = want[key] as? Double   // a JSON null is NSNull: nil here
            if got != expected { wrong.append("\(key): got \(String(describing: got)), want \(String(describing: expected))") }
        }
        func string(_ key: String, _ got: String?) {
            let expected = want[key] as? String
            if got != expected { wrong.append("\(key): got \(String(describing: got)), want \(String(describing: expected))") }
        }
        string("binaryResultDetector", m.binaryResultDetector)
        number("nominalMagnification", m.nominalMagnification)
        number("stemMagnification", m.stemMagnification)
        number("cameraLengthMeters", m.cameraLengthMeters)
        string("operatingMode", m.operatingMode)
        string("projectorMode", m.projectorMode)
        number("exposureTimeSeconds", m.exposureTimeSeconds)
        let wantExposures = (want["detectorExposures"] as? [Any])?.map { $0 as? Double }
        if m.detectors.map(\.exposureTimeSeconds) != wantExposures {
            wrong.append("detectorExposures: got \(m.detectors.map(\.exposureTimeSeconds)), want \(String(describing: wantExposures))")
        }
        r.check("planted '\(image.id)': the six VeloxMetadata fields and each detector's exposure equal the truth",
                wrong.isEmpty, wrong.joined(separator: "; "))
    }
}
