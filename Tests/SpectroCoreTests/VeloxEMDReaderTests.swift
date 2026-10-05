import XCTest
import DSTEMCore

/// v5.0 WP1: the Velox EMD spectrum-image reader. None of these needs References data: the
/// decode is tested on synthetic streams, the metadata parser on a JSON literal, and the file
/// path on a 3 KB synthetic Velox EMD embedded below (`tools/velox-parity/make-tiny-fixture.py`
/// writes it). The count-for-count comparison with rosettasciio on the public files is
/// `tools/velox-parity`.
final class VeloxEMDReaderTests: XCTestCase {
    private let M = VeloxStreamDecoder.pixelMarker

    private func store(_ streams: [[UInt16]], ny: Int, nx: Int, channels: Int = 8, frames: Range<Int>) throws -> VeloxEventStore {
        try VeloxStreamDecoder.buildEventStore(
            arrays: streams, geometry: VeloxStreamGeometry(ny: ny, nx: nx, channels: channels), frames: frames)
    }

    // MARK: Decode

    /// A marker ends a pixel and is never a channel; two markers in a row are an EMPTY pixel,
    /// which must not shift the pixels after it. 1 x 2 grid, two frames.
    func testMarkersEndPixelsAndAnEmptyPixelIsTwoMarkersInARow() throws {
        let stream: [UInt16] = [3, 3, M, M,   1, M, 5, M]      // frame 0: p0 = 2 x ch3, p1 empty; frame 1: p0 = ch1, p1 = ch5
        let s = try store([stream], ny: 1, nx: 2, frames: 0..<2)
        XCTAssertEqual(s.spectrum(pixel: 0), [0, 1, 0, 2, 0, 0, 0, 0])
        XCTAssertEqual(s.spectrum(pixel: 1), [0, 0, 0, 0, 0, 1, 0, 0])
        XCTAssertEqual(s.totalCounts, 4, "the marker is not a count")
        XCTAssertEqual(s.completeFrames, 2)
        XCTAssertEqual(s.partialFramePixels, 0)
        XCTAssertEqual(s.outOfRangeValues, 0)
    }

    /// A frame range sums only those frames: frames 1..<2 of a 3-frame stream, and frames 0..<2.
    func testFrameRangeSumsOnlyThoseFrames() throws {
        // 1 x 1 grid: one marker per frame.
        let stream: [UInt16] = [2, M,   4, 4, M,   6, M]
        let middle = try store([stream], ny: 1, nx: 1, frames: 1..<2)
        XCTAssertEqual(middle.spectrum(pixel: 0), [0, 0, 0, 0, 2, 0, 0, 0])
        XCTAssertEqual(middle.completeFrames, 1)
        let head = try store([stream], ny: 1, nx: 1, frames: 0..<2)
        XCTAssertEqual(head.spectrum(pixel: 0), [0, 0, 1, 0, 2, 0, 0, 0])
        XCTAssertEqual(head.totalCounts, 3)
        let all = try store([stream], ny: 1, nx: 1, frames: 0..<3)
        XCTAssertEqual(all.totalCounts, 4)
        XCTAssertThrowsError(try store([stream], ny: 1, nx: 1, frames: 2..<2))
    }

    /// A sub-area raster (2 rows x 3 columns) is row-major, and a stopped acquisition leaves a
    /// partial last frame that is reported, not hidden.
    func testSubAreaRasterIsRowMajorAndAPartialFrameIsReported() throws {
        // frame 0: p0..p5 each one count of channel = pixel index (0 is ch0); frame 1 stops after 2 pixels.
        var stream: [UInt16] = []
        for p in 0..<6 { stream += [UInt16(p), M] }
        stream += [7, M, 7, M]
        let s = try store([stream], ny: 2, nx: 3, frames: 0..<2)
        XCTAssertEqual(s.geometry.pixelsPerFrame, 6)
        XCTAssertEqual(s.spectrum(pixel: 4)[4], 1, "pixel 4 is row 1, column 1")
        XCTAssertEqual(s.spectrum(pixel: 0)[7], 1, "frame 1's first pixel")
        XCTAssertEqual(s.spectrum(pixel: 1)[7], 1)
        XCTAssertEqual(s.spectrum(pixel: 2)[7], 0)
        XCTAssertEqual(s.completeFrames, 1)
        XCTAssertEqual(s.partialFramePixels, 2)
        XCTAssertEqual(s.framesCovering(pixel: 1), 2)
        XCTAssertEqual(s.framesCovering(pixel: 2), 1)
        // A stream that ends on its last marker opens no further frame.
        let exact = try store([Array(stream[0..<12])], ny: 2, nx: 3, frames: 0..<2)
        XCTAssertEqual(exact.completeFrames, 1)
        XCTAssertEqual(exact.partialFramePixels, 0)
    }

    /// The streams of a Super-X are summed; a channel the spectrum does not have is skipped and counted.
    func testDetectorsSumAndOutOfRangeChannelsAreCounted() throws {
        let a: [UInt16] = [1, M, 2, M]
        let b: [UInt16] = [1, M, 8, M]      // 8 is outside 8 channels
        let s = try store([a, b], ny: 1, nx: 2, frames: 0..<1)
        XCTAssertEqual(s.spectrum(pixel: 0)[1], 2)
        XCTAssertEqual(s.spectrum(pixel: 1)[2], 1)
        XCTAssertEqual(s.outOfRangeValues, 1)
        XCTAssertEqual(s.totalCounts, 3)
        XCTAssertEqual(s.denseCounts().count, 2 * 8)
    }

    // MARK: Metadata

    private let superXJSON = """
    {"Detectors": {
       "Detector-5": {"DetectorName": "HAADF", "DetectorType": "ScanningDetector", "Enabled": "true"},
       "Detector-6": {"DetectorName": "SuperXG11", "DetectorType": "AnalyticalDetector", "Enabled": "true",
                      "ElevationAngle": "0.38397244", "AzimuthAngle": "0.78539816339744828", "CollectionAngle": "0.225",
                      "Dispersion": "20", "OffsetEnergy": "-1932.21348"},
       "Detector-7": {"DetectorName": "SuperXG12", "DetectorType": "AnalyticalDetector", "Enabled": "true",
                      "ElevationAngle": "0.38397244", "AzimuthAngle": "2.3561944901923448",
                      "Dispersion": "20", "OffsetEnergy": "-1932.21348"},
       "Detector-8": {"DetectorName": "SuperXG13", "DetectorType": "AnalyticalDetector", "Enabled": "false",
                      "ElevationAngle": "0.38397244", "AzimuthAngle": "3.9269908169872414"},
       "Detector-9": {"DetectorName": "SuperXG14", "DetectorType": "AnalyticalDetector", "Enabled": "true",
                      "ElevationAngle": "0.38397244", "AzimuthAngle": "5.497787143782138"}},
     "BinaryResult": {"Detector": "SuperXG1", "PixelSize": {"width": "1.26953125e-09", "height": "1.26953125e-09"}, "PixelUnitX": "m"},
     "Scan": {"ScanSize": {"width": "1024", "height": "1024"}, "DwellTime": "6.25e-06", "FrameTime": "2.63910625",
              "ScanArea": {"left": "0.400390625", "top": "0.0615234375", "right": "0.6103515625", "bottom": "0.9658203125"},
              "ScanRotation": "-3.1066860685499069"},
     "Optics": {"AccelerationVoltage": "200000", "ScreenCurrent": "1.8299768652603883e-09"},
     "Stage": {"AlphaTilt": "-0.29458", "BetaTilt": "0", "HolderType": "FEI Double Tilt", "Position": {"x": "1", "y": "2", "z": "3"}},
     "CustomProperties": {"Scan.ScanTransformation.A11": {"type": "double", "value": "1"}, "Scan.ScanTransformation.A12": {"type": "double", "value": "0"},
       "Scan.ScanTransformation.A13": {"type": "double", "value": "-0.0002788"}, "Scan.ScanTransformation.A21": {"type": "double", "value": "0"},
       "Scan.ScanTransformation.A22": {"type": "double", "value": "1"}, "Scan.ScanTransformation.A23": {"type": "double", "value": "-0.0005182"}}}
    """

    /// The owner's Super-X: four segments at 45/135/225/315 degrees and 22 degrees elevation,
    /// read in radians as stored. Swapping azimuth and elevation, or losing the enabled flag, fails.
    func testSuperXGeometryAndTheEnergyAxisAreParsed() throws {
        let m = try VeloxMetadata.parse(jsonData: Data(superXJSON.utf8))
        let x = m.superXDetectors
        XCTAssertEqual(x.map(\.name), ["SuperXG11", "SuperXG12", "SuperXG13", "SuperXG14"], "the HAADF scanning detector is not an X-ray segment")
        for (d, azimuth) in zip(x, [45.0, 135, 225, 315]) { XCTAssertEqual(d.azimuthDegrees!, azimuth, accuracy: 1e-9) }
        for d in x { XCTAssertEqual(d.elevationDegrees!, 22.0, accuracy: 1e-4) }
        XCTAssertEqual(x.map(\.enabled), [true, true, false, true])
        // rsciio: the first detector whose name CONTAINS BinaryResult.Detector ("SuperXG1" is in "SuperXG11"); eV -> keV.
        XCTAssertEqual(m.energyAxis, VeloxEnergyAxis(offsetKeV: -1.93221348, scaleKeV: 0.02))
        XCTAssertEqual(m.alphaDegrees!, -16.87, accuracy: 0.01)
        XCTAssertEqual(m.betaDegrees, 0)
        XCTAssertEqual(m.holderType, "FEI Double Tilt")
        XCTAssertEqual(m.dwellTimeSeconds, 6.25e-06)
        XCTAssertEqual(m.screenCurrentAmperes!, 1.83e-9, accuracy: 1e-11)
        XCTAssertEqual(m.accelerationVoltageVolts, 200_000)
        XCTAssertEqual(m.scanSizeWidth, 1024)
        XCTAssertEqual(m.scanArea?.left, 0.400390625)
        XCTAssertEqual(m.scanRotationRadians!, -3.1066860685499069, accuracy: 1e-15)
        XCTAssertEqual(m.scanTransformation, VeloxScanTransformation(a11: 1, a12: 0, a13: -0.0002788, a21: 0, a22: 1, a23: -0.0005182),
                       "Velox writes FLAT dotted keys under CustomProperties")
        XCTAssertEqual(x[0].solidAngleSteradians, 0.225)
        // The spectrum image is ScanSize x ScanArea (215 columns, 926 rows), not the 1024 raster.
        XCTAssertEqual(m.derivedGrid?.ny, 926)
        XCTAssertEqual(m.derivedGrid?.nx, 215)
    }

    /// With no matching detector there is NO axis, not rsciio's silent 1 channel = 1 unit.
    func testAMissingEnergyCalibrationIsNilNotUnity() throws {
        let m = try VeloxMetadata.parse(jsonData: Data(#"{"BinaryResult": {"Detector": "SuperXG9"}, "Detectors": {"Detector-0": {"DetectorName": "SuperXG1", "Dispersion": "10", "OffsetEnergy": "0"}}}"#.utf8))
        XCTAssertNil(m.energyAxis)
        XCTAssertNil(m.derivedGrid)
    }

    /// The same affine under the nested layout is accepted as a fallback.
    func testNestedScanTransformationIsAFallback() throws {
        let json = #"{"CustomProperties": {"Scan": {"ScanTransformation": {"A11": {"value": "1"}, "A12": {"value": "0"}, "A13": {"value": "0.5"}, "A21": {"value": "0"}, "A22": {"value": "1"}, "A23": {"value": "0.25"}}}}}"#
        let m = try VeloxMetadata.parse(jsonData: Data(json.utf8))
        XCTAssertEqual(m.scanTransformation?.a13, 0.5)
        XCTAssertEqual(m.scanTransformation?.a23, 0.25)
    }

    // MARK: Synthetic files (tools/velox-parity/make-tiny-fixture.py)

    /// The main file: a NON-SQUARE 3-row x 2-column spectrum image, 8 channels, 2 frames, two streams with a
    /// FrameLocationTable, a (3, 2, 2) HAADF, Super-X segments with different elevations and dispersions.
    private static let mainBase64 = "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"
    /// The main file without ScanArea, and with ScanSize height 4 (`--no-scan-area`, `--wrong-height`).
    private static let noScanAreaBase64 = "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"
    private static let wrongHeightBase64 = "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"
    /// The bare file with ScanSize height 6000 (`--bare-huge-grid`): 3000 x 2 pixels per frame against 8 pixel ends.
    private static let hugeGridBase64 = "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"
    /// The main file with every stream lacking its final pixel marker (`--no-last-marker`), as in example_velox_EELS_EDS.emd.
    private static let noLastMarkerBase64 = "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"
    /// No FrameLocationTable, no SpectrumImage group, one stream stopped mid-frame (8 pixel ends of 6 per frame).
    private static let bareBase64 = "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"
    /// A Velox image file with no stream.
    private static let imageOnlyBase64 = "7ZkxTwIxFMfbHsQLifHcEAmejYODA2zGSeOhmBgxaoijNyCSiBAkhsSYOOLmR3BkdHR0ZOQb4dW2R1tBiJBIwvstj9c+2uPuf3+S15ecd7AYS8QQw7ZRBDlIpSfoUj2X81ciYhFbIraJHMffc3ExvizWN+suzrJZVt0zkPukIzzaCJhHctm9UxYvRS711CF6XaFYvy9X75DnN3xVl7t/3BejKF8Dy5zvjDHWdC+jFcyzzyvBPFO6E85x5UaDyHJC+LAt1rOwlLZjXEFrpp7D+Unew4iEV9mM6r//TeROXH9fXQs0rOtqsC+a92+UL7qr4IugowH/r2Kgnfj9+xtMa3b/HT7czx9jxYawUsd4pA/cYemOSzMZuuXS62q94jdYXijeVpv0SV3/YwmeEQAAAAAAAAAAAADMGmafVfb50nG97qjil4pKfyA34b6j+lybazxCnwt0qeqyY/S3ypVSGk1Rl7zfHTbn0ecCj+F515h9tnlnWJ/yNcnz99R4PvC8Dj4APvDTB7opvc48/5u2D9wkdR8wdQwM8wHzPHWbR4sPyONcgvT7O2zcChSAhQ6Iooj+OSsxzlk7dLCD1P7lfpi6qrmgkUn4Ag=="
    /// A Version dataset of three elements.
    private static let multiVersionBase64 = "6/RwcePlkuJiAAEODgYWBgEGZPAfCjpkUPkw+QQozQilO6D0CiaYOCNYTgIqLgg1H11dSJCrK0j1fzQAs8eABUJzMIyCkQg8XB0DQHQElA9LTyeYUNWFpRYVZ+bnMbgkliQip0sHMu1lZGCFmMEI40NsZmSECDBD1SFoCbBSSaA8KKULwLVCUi4rkAbxmZggwhxQ85gZYUnbAM0FHYMqHoL9/F0YGZjgpUQFK2r+XwDlG0ig5lcF5tE0jJqusJeL6OFHqFx0kB4tF0fTEWY6WgEVOCGFX78KKK1xIMowZD4TGh9kj7uzvw84rwug5nsVKF2tVAYpgZWsFJQMDZV0FJTS8otyE0tA/LDUnPwKpVqY2eToYyZTH7we4R9NM6NgFIyCUTAKRsEoGAWjYBSMglEwCkYBIYBrHDZAAlVdcEFqcklRaW5wSVFqYi7l47CQcTAGnONgo2A0XSKnS9h46Au08S9YOgygkr2Q8XD44D3DAXZUe4gdhxvpAAA="

    private func rawBytes(_ base64: String) throws -> Data {
        let compressed = try XCTUnwrap(Data(base64Encoded: base64))
        return try (compressed as NSData).decompressed(using: .zlib) as Data
    }

    private func write(_ raw: Data) throws -> String {
        let path = NSTemporaryDirectory() + "velox-tiny-\(UUID().uuidString).emd"
        try raw.write(to: URL(fileURLWithPath: path))
        addTeardownBlock { try? FileManager.default.removeItem(atPath: path) }
        return path
    }

    private func writeFile(_ base64: String? = nil) throws -> String { try write(rawBytes(base64 ?? Self.mainBase64)) }

    /// A same-length byte patch of the file's variable-length JSON strings (stored contiguously; the Metadata columns are strided, so they get their own fixtures).
    private func patched(_ old: String, _ new: String) throws -> String {
        XCTAssertEqual(old.utf8.count, new.utf8.count)
        var raw = try rawBytes(Self.mainBase64)
        let needle = Data(old.utf8), replacement = Data(new.utf8)
        var hits = 0
        var from = raw.startIndex
        while let r = raw.range(of: needle, in: from..<raw.endIndex) {
            raw.replaceSubrange(r, with: replacement)
            from = r.upperBound
            hits += 1
        }
        XCTAssertGreaterThan(hits, 0, "\(old) not found")
        return try write(raw)
    }

    /// Detection looks at the file's own markers: the Version JSON and the stream groups.
    func testDetectionRecognisesAVeloxEMDAndNothingElse() throws {
        XCTAssertTrue(VeloxEMDReader.isVeloxEMD(path: try writeFile()))
        let text = NSTemporaryDirectory() + "velox-not-\(UUID().uuidString).emd"
        try Data("not hdf5".utf8).write(to: URL(fileURLWithPath: text))
        addTeardownBlock { try? FileManager.default.removeItem(atPath: text) }
        XCTAssertFalse(VeloxEMDReader.isVeloxEMD(path: text))
        XCTAssertFalse(VeloxEMDReader.isVeloxEMD(path: NSTemporaryDirectory() + "velox-missing-file.emd"))
    }

    /// A Velox file that holds only images is a Velox file but not a spectrum image.
    func testAVeloxImageFileWithNoStreamIsNotASpectrumImage() throws {
        let path = try writeFile(Self.imageOnlyBase64)
        XCTAssertFalse(VeloxEMDReader.isVeloxEMD(path: path))
        XCTAssertThrowsError(try VeloxEMDReader(path: path).readSpectrumImage()) { error in
            guard case VeloxEMDError.noSpectrumStream = error else { return XCTFail("\(error)") }
        }
    }

    /// `isVeloxEMD` is asked about ARBITRARY HDF5 files: a Version dataset of several elements must be
    /// answered "no", not read into a one-pointer buffer.
    func testAVersionDatasetOfSeveralElementsIsNotVelox() throws {
        XCTAssertFalse(VeloxEMDReader.isVeloxEMD(path: try writeFile(Self.multiVersionBase64)))
    }

    /// Both detectors' streams, both frames, on a 3 x 2 grid (rows != columns), HAADF on the same grid.
    /// Counts cross-checked by hand and with rsciio's own stream function (11 counts, 7 cells).
    func testMainFileDecodesEndToEnd() throws {
        let result = try VeloxEMDReader(path: try writeFile()).readSpectrumImage()
        let s = result.eventStore
        XCTAssertEqual(s.geometry, VeloxStreamGeometry(ny: 3, nx: 2, channels: 8), "ScanSize 4 x 6 over ScanArea .25-.75 x 0-.5")
        XCTAssertEqual(s.frameRange, 0..<2)
        XCTAssertEqual(s.totalCounts, 11)
        XCTAssertEqual(s.distinctEntries, 7)
        XCTAssertEqual(s.spectrum(pixel: 0), [0, 3, 0, 0, 0, 0, 0, 0])
        XCTAssertEqual(s.spectrum(pixel: 1), [0, 0, 0, 2, 0, 0, 0, 0])
        XCTAssertEqual(s.spectrum(pixel: 2), [0, 0, 1, 0, 0, 1, 0, 0])
        XCTAssertEqual(s.spectrum(pixel: 3), [0, 0, 0, 0, 1, 0, 0, 0])
        XCTAssertEqual(s.spectrum(pixel: 4), [UInt32](repeating: 0, count: 8))
        XCTAssertEqual(s.spectrum(pixel: 5), [1, 0, 0, 0, 0, 0, 0, 2])
        XCTAssertEqual(s.completeFrames, 2)
        XCTAssertEqual(s.partialFramePixels, 0)
        XCTAssertEqual(result.streamCount, 2)
        XCTAssertEqual(result.version, "11")
        XCTAssertEqual(result.settingsFrames.end, 2)
        let image = try XCTUnwrap(result.scanImage)
        XCTAssertEqual(image.detectorName, "HAADF")
        XCTAssertEqual([image.ny, image.nx], [3, 2])
        XCTAssertEqual(image.sum, [11, 22, 33, 44, 55, 66], "(y, x, frame) summed over both frames")
        XCTAssertEqual(image.framesSummed, 2)
        XCTAssertEqual(image.framesInFile, 2)
    }

    /// Per-stream detector, the segments it resolves to (with their own elevations), and the calibration check:
    /// segment G22 has 20 eV/channel against 10 for G21, so the summed spectrum mixes scales and says so.
    func testStreamsSegmentsAndTheEnergyCalibrationCheck() throws {
        let result = try VeloxEMDReader(path: try writeFile()).readSpectrumImage()
        XCTAssertEqual(result.streams.map(\.detectorName), ["SuperXG21", "SuperXG22"])
        XCTAssertEqual(result.streams.map(\.detectorIndex), [8, 8])
        XCTAssertEqual(result.streams.map { $0.segments.map(\.name) }, [["SuperXG21"], ["SuperXG22"]])
        XCTAssertEqual(result.streams[0].segments[0].elevationDegrees!, 18.0, accuracy: 1e-4)
        XCTAssertEqual(result.streams[1].segments[0].elevationDegrees!, 30.0, accuracy: 1e-4)
        XCTAssertEqual(result.streams[1].segments[0].azimuthDegrees!, 135.0, accuracy: 1e-9)
        XCTAssertFalse(result.energyCalibrationAgrees)
        // The axis is the first stream's segment: 10 eV/channel from -250 eV.
        XCTAssertEqual(result.metadata.energyAxis, VeloxEnergyAxis(offsetKeV: -0.25, scaleKeV: 0.01))
        XCTAssertEqual(result.metadata.superXDetectors.map(\.enabled), [true, true, true, false])
    }

    /// Frames 1..<2 only, by the reader's own range argument; the HAADF is summed over the same range.
    func testMainFileFrameRange() throws {
        let path = try writeFile()
        let result = try VeloxEMDReader(path: path).readSpectrumImage(frames: .range(1..<2))
        XCTAssertEqual(result.eventStore.totalCounts, 4)
        XCTAssertEqual(result.eventStore.spectrum(pixel: 5), [1, 0, 0, 0, 0, 0, 0, 0])
        XCTAssertEqual(result.scanImage?.sum, [10, 20, 30, 40, 50, 60], "frame 1 of the HAADF only")
        XCTAssertThrowsError(try VeloxEMDReader(path: path).readSpectrumImage(frames: .range(0..<3)),
                             "rsciio refuses a last_frame past the file's frames")
    }

    /// The per-frame drift-correction affine (flat keys), recorded and never applied; and the frame windows.
    func testMainFileFrameTransformationsAndMarkerWindows() throws {
        let reader = VeloxEMDReader(path: try writeFile())
        let t = try reader.readFrameTransformations()
        XCTAssertEqual(t.count, 2)
        XCTAssertEqual(try XCTUnwrap(t[1]).a13, 0.001, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(t[1]).a23, -0.002, accuracy: 1e-12)
        XCTAssertEqual(try reader.markersPerFrame(), [6, 6])
        let times = try reader.readFrameDetectorTimes()
        XCTAssertEqual(times.count, 2)
        XCTAssertEqual(times[0].map(\.name), ["SuperXG21", "SuperXG22", "SuperXG23", "SuperXG24"])
        XCTAssertEqual(times[0][0].realTime, 0.5)
    }

    /// No FrameLocationTable and no SpectrumImage group: the frame count is ceil(markers / pixels) = ceil(8 / 6) = 2,
    /// and the stopped acquisition shows as a partial last frame, reported, not refused.
    func testTheCeilPathWithNoTableAndNoSettings() throws {
        let result = try VeloxEMDReader(path: try writeFile(Self.bareBase64)).readSpectrumImage()
        let s = result.eventStore
        XCTAssertEqual(s.frameRange, 0..<2)
        XCTAssertEqual(s.completeFrames, 1)
        XCTAssertEqual(s.partialFramePixels, 2)
        XCTAssertEqual(s.totalCounts, 6)
        XCTAssertEqual(s.spectrum(pixel: 0), [0, 3, 0, 0, 0, 0, 0, 0])
        XCTAssertEqual(s.spectrum(pixel: 1), [0, 0, 0, 1, 0, 0, 0, 0])
        XCTAssertEqual(s.framesCovering(pixel: 1), 2)
        XCTAssertEqual(s.framesCovering(pixel: 2), 1)
        XCTAssertNil(result.settingsFrames.end)
        XCTAssertEqual(try XCTUnwrap(result.scanImage).framesInFile, 2)
    }

    /// A frame whose last pixel's marker is absent is a COMPLETE frame (rsciio stores the trailing pixel): 11 markers of 12,
    /// two frames of dose for every pixel, nothing partial, and the same counts as the file with its markers.
    func testAFrameEndingWithoutItsLastMarkerIsComplete() throws {
        let s = try VeloxEMDReader(path: try writeFile(Self.noLastMarkerBase64)).readSpectrumImage().eventStore
        XCTAssertEqual(s.frameRange, 0..<2)
        XCTAssertEqual(s.completeFrames, 2)
        XCTAssertEqual(s.partialFramePixels, 0)
        XCTAssertEqual(s.framesCovering(pixel: 5), 2)
        XCTAssertEqual(s.totalCounts, 11)
    }

    /// Without a ScanArea the grid falls back to rsciio's last-image rule (3 x 2 here), and says nothing else.
    func testTheLastImageGridFallback() throws {
        let path = try writeFile(Self.noScanAreaBase64)
        let result = try VeloxEMDReader(path: path).readSpectrumImage()
        XCTAssertEqual(result.eventStore.geometry, VeloxStreamGeometry(ny: 3, nx: 2, channels: 8))
        XCTAssertEqual(result.eventStore.totalCounts, 11)
    }

    /// A grid the stream cannot fill is refused by name, before anything is allocated from it:
    /// ScanSize height 4 makes 2 x 2 pixels, the FrameLocationTable's 2 frames then disagree with 12 pixel ends.
    func testAGridInconsistentWithTheStreamIsRefused() throws {
        let path = try writeFile(Self.wrongHeightBase64)
        XCTAssertThrowsError(try VeloxEMDReader(path: path).readSpectrumImage()) { error in
            guard case VeloxEMDError.gridInconsistent = error else { return XCTFail("\(error)") }
        }
    }

    /// With no FrameLocationTable to catch it, a corrupt ScanSize still throws before pixels + 1 slots are allocated.
    func testAGridLargerThanTheStreamIsRefusedWithoutATable() throws {
        XCTAssertThrowsError(try VeloxEMDReader(path: try writeFile(Self.hugeGridBase64)).readSpectrumImage()) { error in
            guard case VeloxEMDError.gridInconsistent = error else { return XCTFail("\(error)") }
        }
    }

    /// Corrupt or unexplained frame positions throw a named error; they never trap.
    func testBadFramePositionsThrow() throws {
        let zeroEnd = try patched("\"endFramePosition\": \"2\"", "\"endFramePosition\": \"0\"")
        XCTAssertThrowsError(try VeloxEMDReader(path: zeroEnd).readSpectrumImage()) { error in
            guard case VeloxEMDError.frameRangeInvalid = error else { return XCTFail("\(error)") }
        }
        let start = try patched("\"startFramePosition\": \"1\"", "\"startFramePosition\": \"2\"")
        XCTAssertThrowsError(try VeloxEMDReader(path: start).readSpectrumImage()) { error in
            guard case VeloxEMDError.unsupportedFramePosition = error else { return XCTFail("\(error)") }
        }
    }

    /// A file cut in half is not a file: detection says no and a read throws.
    func testATruncatedFileThrows() throws {
        let raw = try rawBytes(Self.mainBase64)
        let path = try write(raw.prefix(raw.count / 2))
        XCTAssertFalse(VeloxEMDReader.isVeloxEMD(path: path))
        XCTAssertThrowsError(try VeloxEMDReader(path: path).readSpectrumImage())
    }
}
