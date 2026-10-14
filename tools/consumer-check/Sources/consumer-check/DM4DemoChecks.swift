//
//  DM4DemoChecks.swift
//  Role: ask 1 of macTEM (the DM4 API public) on `demo-edx-tiny.dm4`, against its `.truth.json`:
//        `DM4Experiment.list`, `readImage(path:index:)`, `readImage(data:index:)`, `DM4Image` and `DM4Axis` field by
//        field, and the nine `DM4ImageObject` fields macTEM reads (`name`, `dimensions`, `axes`, `metaDataFormat`,
//        `imageTagNumbers`, `imageTagStrings` became public in 0.2.0; `index`, `role`, `voltage` already were). The
//        expectations are those of `DemoEDXFixtureSpectro` in SpectroCoreTests, made through the public surface only.
//

import CryptoKit
import Foundation
import SpectroCore

func dm4DemoChecks(_ r: inout Report, _ fixtures: URL) throws {
    let url = fixtures.appendingPathComponent("demo-edx-tiny.dm4")
    let truth = try loadJSON(fixtures.appendingPathComponent("demo-edx-tiny.truth.json"))
    let scan = try truth.object("scan"), edx = try truth.object("edx"), axisFile = try edx.object("axis_file")
    let nx = Int(try scan.number("nx")), ny = Int(try scan.number("ny")), pitch = try scan.number("pitch_nm")
    let dwell = try scan.number("dwell_s"), channels = Int(try edx.number("channels"))
    let dispersionEV = try axisFile.number("dispersion_eV"), originChannel = try axisFile.number("origin_channel")
    let hashes = try truth.object("array_sha256_of_written_arrays_C_order")

    // list(path:) and list(data:): the same five objects.
    let bytes = try Data(contentsOf: url)
    let objects = try DM4Experiment.list(path: url.path)
    r.equal("DM4Experiment.list(path:) lists 5 objects (index 1...5)", objects.map(\.index), [1, 2, 3, 4, 5])
    r.check("DM4Experiment.list(data:) equals list(path:)", try DM4Experiment.list(data: bytes) == objects)
    r.equal("DM4ImageObject.role", objects.map(\.role), [.thumbnail, .survey, .scanSignal, .diffraction, .eds])
    r.equal("DM4ImageObject.name", objects.map(\.name),
            ["Image Of demo-edx-tiny.dm4", "ADF Image (SI Survey)", "HAADF Image", "Diffraction SI", "EDS SI"])
    r.equal("DM4ImageObject.dimensions follow the truth scan (fastest first: nx, ny; 4D: 16 x 16, nx, ny; EDS: nx, ny, ch)",
            objects.map(\.dimensions), [[16, 12], [64, 64], [nx, ny], [16, 16, nx, ny], [nx, ny, channels]])
    r.equal("DM4ImageObject.metaDataFormat",
            objects.map(\.metaDataFormat), [nil, "Image", "Image", "Diffraction image", "Spectrum image"])

    // The first 2D non-thumbnail object is the survey, index 2.
    guard let first2D = objects.first(where: { $0.dimensions.count == 2 && $0.role != .thumbnail }) else {
        throw CheckError("no 2D non-thumbnail object")
    }
    r.equal("first 2D non-thumbnail object is the 64 x 64 survey, index 2",
            [first2D.index, first2D.dimensions[0], first2D.dimensions[1]], [2, 64, 64])

    // readImage(path:index:) == readImage(data:index:), DM4Image field by field.
    let image = try DM4Experiment.readImage(path: url.path, index: first2D.index)
    r.check("readImage(path:index:) equals readImage(data:index:) (survey)",
            image == (try DM4Experiment.readImage(data: bytes, index: first2D.index)))
    r.check("DM4Image.object is the listed object", image.object == first2D)
    r.equal("DM4Image.width / .height match DM4ImageObject.dimensions", [image.width, image.height], first2D.dimensions)
    r.equal("DM4Image.pixels holds width x height values", image.pixels.count, image.width * image.height)
    r.check("DM4Image.xAxis / .yAxis are the object's first two axes",
            image.xAxis == first2D.axes[0] && image.yAxis == first2D.axes[1])
    r.check("DM4Axis .origin .scale .units of the survey (0, 1, nm)",
            image.xAxis?.origin == 0 && image.xAxis?.scale == 1 && image.xAxis?.units == "nm"
            && image.yAxis?.units == "nm")
    r.equal("survey pixels are the written uint16 array (SHA-256 of the truth)",
            sha256(image.pixels.map { UInt16($0) }), try hashes.string("survey_uint16"))

    // The scan-grid HAADF image: not square, so an axis swap shows; calibrated at the truth's pitch.
    let haadfObject = try object(.scanSignal, in: objects)
    let haadf = try DM4Experiment.readImage(path: url.path, index: haadfObject.index)
    r.check("readImage(path:) equals readImage(data:) (HAADF)",
            haadf == (try DM4Experiment.readImage(data: bytes, index: haadfObject.index)))
    r.equal("HAADF DM4Image.width x .height are the truth's nx x ny", [haadf.width, haadf.height], [nx, ny])
    r.check("HAADF DM4Axis .origin .scale .units: 0, pitch_nm, nm, on both axes",
            [haadf.xAxis, haadf.yAxis].allSatisfy {
                $0?.origin == 0 && $0?.units == "nm" && abs(($0?.scale ?? -1) - pitch) < 1e-6
            })
    r.equal("HAADF pixels are the written float32 array (SHA-256 of the truth)",
            sha256(haadf.pixels.map(\.bitPattern)), try hashes.string("haadf_ny_nx_float32"))

    // The EDS spectrum image: the object's fields only (readImage refuses a 3D object).
    let eds = try object(.eds, in: objects)
    r.check("EDS DM4ImageObject.axes: nx, ny at pitch_nm (nm); energy in keV on the truth's file axis",
            eds.axes.count == 3 && eds.axes[0]?.units == "nm" && abs((eds.axes[0]?.scale ?? 0) - pitch) < 1e-6
            && eds.axes[2]?.units == "keV" && abs((eds.axes[2]?.scale ?? 0) - dispersionEV / 1000) < 1e-7
            && abs((eds.axes[2]?.origin ?? 0) - originChannel) < 1e-4)
    r.equal("DM4ImageObject.voltage is the truth's beam (200 keV in V)", eds.voltage, try edx.number("beam_keV") * 1000)

    // imageTagNumbers / imageTagStrings against the truth's planted values (its convention text gives alpha, theta, phi).
    let convention = try truth.object("forward_model").string("convention")
    let alpha = try capture(#"alpha = (-?[0-9.]+),"#, in: convention)
    let theta = try capture(#"theta = ([0-9.]+)"#, in: convention)
    let phi = try capture(#"for phi = \(([0-9.]+),"#, in: convention)
    let n = eds.imageTagNumbers
    r.near("EDS imageTagNumbers: Microscope Info.Voltage", n["Microscope Info.Voltage"], eds.voltage ?? .nan, 0)
    r.near("EDS imageTagNumbers: EDS.Acquisition.Channels", n["EDS.Acquisition.Channels"], Double(channels), 0)
    r.near("EDS imageTagNumbers: EDS.Acquisition.Dispersion (eV)", n["EDS.Acquisition.Dispersion (eV)"],
           dispersionEV, 1e-4)
    r.near("EDS imageTagNumbers: EDS.Real time = nx * ny * dwell", n["EDS.Real time"], Double(nx * ny) * dwell, 1e-6)
    r.near("EDS imageTagNumbers: SI.Acquisition.Pixel time (s) = dwell", n["SI.Acquisition.Pixel time (s)"], dwell, 1e-8)
    r.near("EDS imageTagNumbers: EDS.Detector Info.Stage tilt = alpha", n["EDS.Detector Info.Stage tilt"], alpha, 1e-4)
    r.near("EDS imageTagNumbers: EDS.Detector Info.Elevation angle = theta",
           n["EDS.Detector Info.Elevation angle"], theta, 0)
    r.near("EDS imageTagNumbers: EDS.Detector Info.Azimuthal angle = phi of segment 1",
           n["EDS.Detector Info.Azimuthal angle"], phi, 0)
    let s = eds.imageTagStrings
    r.equal("EDS imageTagStrings: Meta Data.Signal", s["Meta Data.Signal"], "X-ray")
    r.equal("EDS imageTagStrings: Meta Data.Format equals metaDataFormat", s["Meta Data.Format"], eds.metaDataFormat)
    r.equal("EDS imageTagStrings: EDS.Detector Info.Detector type", s["EDS.Detector Info.Detector type"], "SuperX")
    r.equal("EDS imageTagStrings: Meta Data.Experiment keywords.2.Label",
            s["Meta Data.Experiment keywords.2.Label"], "EDS")
    r.check("the thumbnail carries no tags (both maps empty)",
            objects[0].imageTagNumbers.isEmpty && objects[0].imageTagStrings.isEmpty)
    r.check("every other object's imageTagNumbers voltage equals DM4ImageObject.voltage",
            objects.dropFirst().allSatisfy { $0.imageTagNumbers["Microscope Info.Voltage"] == $0.voltage && $0.voltage != nil })
}

private func object(_ role: DM4ImageRole, in objects: [DM4ImageObject]) throws -> DM4ImageObject {
    guard let found = objects.first(where: { $0.role == role }) else { throw CheckError("no \(role) object") }
    return found
}

private func sha256<T: FixedWidthInteger>(_ values: [T]) -> String {
    var bytes = Data()
    for value in values { var v = value.littleEndian; withUnsafeBytes(of: &v) { bytes.append(contentsOf: $0) } }
    return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
}

/// The first capture group of `pattern` in `text`, as a number.
private func capture(_ pattern: String, in text: String) throws -> Double {
    guard let match = text.firstMatch(of: try Regex(pattern)), match.output.count > 1,
          let value = match.output[1].substring.flatMap({ Double($0) }) else {
        throw CheckError("truth's convention text has no \(pattern)")
    }
    return value
}
