//
//  VeloxEMDReader.swift
//  Role: Read a Thermo Fisher Velox EMD spectrum image (EDX), headless. Decodes
//        `Data/SpectrumStream/<id>/Data` into a per-pixel sparse event store
//        (CSR: channel, count), reads the HAADF image stack on the spectrum grid,
//        and parses the acquisition metadata (energy axis, Super-X geometry,
//        stage, dose, scan).
//
//  The reference is rosettasciio at 049e7d70 (`rsciio/emd/_emd_velox.py`,
//  `rsciio/utils/_fei_stream_readers.py`); `tools/lib/fetch-rsciio.sh` pins it
//  and `tools/velox-parity` compares this reader to it count for count.
//  The stream format (docs/archive/v5/edx-research-2026-10-05/reports/formats.md
//  §2.2): uint16 values; 65535 ends a pixel; any other value is the channel of
//  one detected X-ray; pixels run row-major, and a frame is ny*nx markers.
//
//  Not read, by decision (ADR 053): Velox's derived element maps and its pruned
//  `SpectrumImage` cube. No AppState: nothing in the app sees this yet.
//

import Darwin
import Foundation

package enum VeloxEMDError: LocalizedError {
    case libraryUnavailable(String)
    case cannotOpen(String)
    case notVelox(String)
    /// A pruned file (no `SpectrumStream`, or an empty one): only Velox's own
    /// proprietary cube is left, which is not decoded.
    case noSpectrumStream
    case missingMetadata(String)
    case cannotDetermineGrid(String)
    case frameRangeInvalid(String)
    case readFailed(String)
    /// `startFramePosition` other than 1: its meaning is not established (all known files have 1).
    case unsupportedFramePosition(String)
    /// The stream does not fit the grid the metadata implies: refused, never decoded into a wrong cube.
    case gridInconsistent(String)

    package var errorDescription: String? {
        switch self {
        case .libraryUnavailable(let detail): return "Could not load the bundled HDF5 library: \(detail)"
        case .cannotOpen(let name): return "Could not open \(name) as an HDF5 file."
        case .notVelox(let name): return "\(name) is not a Velox EMD spectrum image."
        case .noSpectrumStream:
            return "This Velox file holds no spectrum stream: it has no spectrum image, or it was pruned or saved by "
                + "software other than Velox. A pruned spectrum image is stored in a proprietary format that is not read."
        case .missingMetadata(let what): return "The Velox file lacks \(what)."
        case .cannotDetermineGrid(let why): return "The spectrum-image grid could not be determined: \(why)."
        case .frameRangeInvalid(let why): return "Invalid frame range: \(why)."
        case .readFailed(let operation): return "HDF5 read failed: \(operation)."
        case .unsupportedFramePosition(let what): return "Unsupported frame position: \(what)."
        case .gridInconsistent(let why): return "The spectrum stream does not match its grid: \(why)."
        }
    }
}

// MARK: - Stream geometry, event store

/// The raster of one spectrum image: `ny` rows of `nx` pixels, `channels` per spectrum.
package nonisolated struct VeloxStreamGeometry: Equatable, Sendable {
    package let ny: Int
    package let nx: Int
    package let channels: Int
    package var pixelsPerFrame: Int { ny * nx }
    package init(ny: Int, nx: Int, channels: Int) {
        self.ny = ny; self.nx = nx; self.channels = channels
    }
}

/// Which frames of the stream are summed.
package nonisolated enum VeloxFrameSelection: Equatable, Sendable {
    /// rsciio's default: frames `0 ..< endFramePosition` of `SpectrumImageSettings`
    /// (all frames when that is absent). DEVIATION-free by construction, and equal
    /// to "every frame" on every public file and on the owner's file.
    case recordedDefault
    /// Every frame the stream holds, whatever `SpectrumImageSettings` says.
    case all
    case range(Range<Int>)
}

/// The per-pixel sparse spectrum image, frames summed: CSR over pixels (row-major,
/// `pixel = y * nx + x`). Channels inside a pixel ascend; each channel appears once.
package nonisolated struct VeloxEventStore: Sendable {
    package let geometry: VeloxStreamGeometry
    /// `pixelCount + 1` offsets into `channelIndex` / `counts`.
    package let rowOffsets: [Int]
    package let channelIndex: [UInt16]
    package let counts: [UInt32]
    /// The frames summed, as indices into the stream.
    package let frameRange: Range<Int>
    /// Frames whose every pixel was reached (inside `frameRange`).
    package let completeFrames: Int
    /// Pixels (from the first) that a further, partial frame also reached: those
    /// pixels carry `completeFrames + 1` frames of dose, the rest `completeFrames`.
    /// rsciio sums such a stopped acquisition without a flag; this reader reports it.
    package let partialFramePixels: Int
    /// Stream values >= `channels` that are not the marker: skipped and counted.
    /// DEVIATION: rsciio's jitted loop indexes past the array for them (undefined).
    package let outOfRangeValues: Int
    /// False when the streams of a multi-detector file did not all end in the same place.
    package let streamsAgreeOnCoverage: Bool

    package var pixelCount: Int { geometry.pixelsPerFrame }
    /// Total counts (events) in the store: the stream's non-marker value count
    /// inside the frame range (prediction P4).
    package var totalCounts: Int { counts.reduce(0) { $0 + Int($1) } }
    package var distinctEntries: Int { channelIndex.count }
    package var storageBytes: Int {
        rowOffsets.count * MemoryLayout<Int>.stride + channelIndex.count * 2 + counts.count * 4
    }

    /// Frames of dose that `pixel` received.
    package func framesCovering(pixel: Int) -> Int {
        completeFrames + (pixel < partialFramePixels ? 1 : 0)
    }

    /// One pixel's spectrum, dense.
    package func spectrum(pixel: Int) -> [UInt32] {
        var out = [UInt32](repeating: 0, count: geometry.channels)
        for k in rowOffsets[pixel]..<rowOffsets[pixel + 1] { out[Int(channelIndex[k])] = counts[k] }
        return out
    }

    /// The whole cube, dense, `(ny, nx, channels)` row-major. Small files only (tests, parity).
    package func denseCounts() -> [UInt32] {
        let c = geometry.channels
        var out = [UInt32](repeating: 0, count: pixelCount * c)
        for p in 0..<pixelCount {
            for k in rowOffsets[p]..<rowOffsets[p + 1] { out[p * c + Int(channelIndex[k])] = counts[k] }
        }
        return out
    }

    /// The summed spectrum over every pixel.
    package func summedSpectrum() -> [UInt64] {
        var out = [UInt64](repeating: 0, count: geometry.channels)
        for k in 0..<channelIndex.count { out[Int(channelIndex[k])] += UInt64(counts[k]) }
        return out
    }
}

/// The pure decode: the rsciio state machine, run over blocks of stream values.
/// It carries the pixel index and frame number across blocks, so a 408 M-value stream
/// is never held in memory (the owner's 1456 stream is 816 MB; this Mac panicked once
/// on a file bigger than RAM).
package nonisolated enum VeloxStreamDecoder {
    package static let pixelMarker: UInt16 = 65535

    /// A supplier of one stream's values, block by block. Called twice per build
    /// (count, then fill), so it must be restartable.
    /// The visitor answers whether it wants more blocks: a frame range that is done stops the read.
    package typealias BlockSource = ((UnsafeBufferPointer<UInt16>) throws -> Bool) throws -> Void

    private struct Cursor {
        var navigation = 0
        var frame = 0
        var done = false
    }

    private protocol EventVisitor {
        mutating func event(pixel: Int, channel: UInt16)
    }

    /// rsciio `_fill_array_with_stream_sum_frames`, line for line:
    ///
    ///     if navigation_index == ny*nx { navigation_index = 0; frame += 1; if frame == last_frame { break } }
    ///     if value != 65535 { if first_frame <= frame { count it } } else { navigation_index += 1 }
    ///
    /// The frame turnover is tested on the value AFTER a frame's last marker, so a
    /// stream that ends on its last marker never opens a further frame.
    @inline(__always)
    private static func scan<V: EventVisitor>(
        _ block: UnsafeBufferPointer<UInt16>, frameSize: Int, first: Int, last: Int,
        cursor: inout Cursor, visitor: inout V
    ) {
        var navigation = cursor.navigation
        var frame = cursor.frame
        for value in block {
            if navigation == frameSize {
                navigation = 0
                frame += 1
                if frame == last { cursor.done = true; break }
            }
            if value != pixelMarker {
                if first <= frame { visitor.event(pixel: navigation, channel: value) }
            } else {
                navigation += 1
            }
        }
        cursor.navigation = navigation
        cursor.frame = frame
    }

    private struct CountingVisitor: EventVisitor {
        var perPixel: UnsafeMutablePointer<Int>
        let channels: Int
        var outOfRange = 0
        mutating func event(pixel: Int, channel: UInt16) {
            if Int(channel) < channels { perPixel[pixel] += 1 } else { outOfRange += 1 }
        }
    }

    private struct FillVisitor: EventVisitor {
        var cursorPerPixel: UnsafeMutablePointer<Int>
        var events: UnsafeMutablePointer<UInt16>
        let channels: Int
        mutating func event(pixel: Int, channel: UInt16) {
            guard Int(channel) < channels else { return }
            events[cursorPerPixel[pixel]] = channel
            cursorPerPixel[pixel] += 1
        }
    }

    /// Builds the event store from one or more detector streams, summing them.
    /// `frames` must be a validated, non-empty range (the caller resolves `.recordedDefault`).
    package static func buildEventStore(
        streams: [BlockSource], geometry: VeloxStreamGeometry, frames: Range<Int>
    ) throws -> VeloxEventStore {
        guard !frames.isEmpty, frames.lowerBound >= 0 else {
            throw VeloxEMDError.frameRangeInvalid("\(frames) is empty or negative")
        }
        let pixels = geometry.pixelsPerFrame
        guard pixels > 0, geometry.channels > 0 else {
            throw VeloxEMDError.cannotDetermineGrid("\(geometry.ny) x \(geometry.nx) pixels, \(geometry.channels) channels")
        }
        let first = frames.lowerBound, last = frames.upperBound

        // Pass 1: events per pixel, over every stream.
        var perPixel = [Int](repeating: 0, count: pixels + 1)
        var outOfRange = 0
        var ends: [(frame: Int, navigation: Int, done: Bool)] = []
        try perPixel.withUnsafeMutableBufferPointer { counts in
            for stream in streams {
                var cursor = Cursor()
                var visitor = CountingVisitor(perPixel: counts.baseAddress!, channels: geometry.channels)
                try stream { block in
                    if cursor.done { return false }
                    scan(block, frameSize: pixels, first: first, last: last, cursor: &cursor, visitor: &visitor)
                    return !cursor.done
                }
                outOfRange += visitor.outOfRange
                ends.append((cursor.frame, cursor.navigation, cursor.done))
            }
        }

        // Bucket offsets (exclusive prefix sum), then pass 2: scatter the channels.
        var bucketStart = [Int](repeating: 0, count: pixels + 1)
        var running = 0
        for p in 0..<pixels { bucketStart[p] = running; running += perPixel[p] }
        bucketStart[pixels] = running
        let totalEvents = running

        let events = UnsafeMutablePointer<UInt16>.allocate(capacity: max(totalEvents, 1))
        defer { events.deallocate() }
        var fillCursor = Array(bucketStart[0..<pixels])
        try fillCursor.withUnsafeMutableBufferPointer { cursorPerPixel in
            for stream in streams {
                var cursor = Cursor()
                var visitor = FillVisitor(cursorPerPixel: cursorPerPixel.baseAddress!, events: events, channels: geometry.channels)
                try stream { block in
                    if cursor.done { return false }
                    scan(block, frameSize: pixels, first: first, last: last, cursor: &cursor, visitor: &visitor)
                    return !cursor.done
                }
            }
        }

        // Sort each pixel's channels in place, count the distinct ones, then compact to CSR.
        var rowOffsets = [Int](repeating: 0, count: pixels + 1)
        var distinct = 0
        for p in 0..<pixels {
            var segment = UnsafeMutableBufferPointer(start: events + bucketStart[p], count: perPixel[p])
            segment.sort()
            var n = 0
            var previous: UInt16?
            for value in segment where value != previous { n += 1; previous = value }
            distinct += n
            rowOffsets[p + 1] = distinct
        }
        var channelIndex = [UInt16](repeating: 0, count: distinct)
        var counts = [UInt32](repeating: 0, count: distinct)
        channelIndex.withUnsafeMutableBufferPointer { channelOut in
            counts.withUnsafeMutableBufferPointer { countOut in
                var w = 0
                for p in 0..<pixels {
                    let segment = UnsafeBufferPointer(start: events + bucketStart[p], count: perPixel[p])
                    var i = 0
                    while i < segment.count {
                        let channel = segment[i]
                        var j = i + 1
                        while j < segment.count && segment[j] == channel { j += 1 }
                        channelOut[w] = channel
                        countOut[w] = UInt32(j - i)
                        w += 1
                        i = j
                    }
                }
            }
        }

        // Coverage of the first stream: what a stopped acquisition left in its last frame.
        let head = ends.first ?? (0, 0, false)
        var complete = 0, partial = 0
        if head.done {
            complete = last - first
        } else if head.frame >= first {
            // A frame whose LAST pixel's marker is absent is complete: Velox streams may end on that pixel's
            // events with no closing 65535 (every stream of example_velox_EELS_EDS.emd: 319 markers for 320
            // pixels; rsciio `_fei_stream_readers.py` stores the trailing pixel, ceil(319 / 320) = 1 frame).
            // A stream that stops exactly one pixel short, with no events after the last marker, cannot be told
            // from that case and is read as complete too.
            if head.navigation == pixels || head.navigation == pixels - 1 {
                complete = head.frame - first + 1
            } else {
                complete = head.frame - first
                partial = head.navigation
            }
        }
        let agree = ends.allSatisfy { $0.frame == head.frame && $0.navigation == head.navigation && $0.done == head.done }
        return VeloxEventStore(
            geometry: geometry, rowOffsets: rowOffsets, channelIndex: channelIndex, counts: counts,
            frameRange: frames, completeFrames: complete, partialFramePixels: partial,
            outOfRangeValues: outOfRange, streamsAgreeOnCoverage: agree)
    }

    /// The same decode over in-memory arrays (tests, small files).
    package static func buildEventStore(
        arrays: [[UInt16]], geometry: VeloxStreamGeometry, frames: Range<Int>
    ) throws -> VeloxEventStore {
        let sources: [BlockSource] = arrays.map { array in
            { visit in try array.withUnsafeBufferPointer { _ = try visit($0) } }
        }
        return try buildEventStore(streams: sources, geometry: geometry, frames: frames)
    }
}

// MARK: - Metadata

private nonisolated func jsonDouble(_ value: Any?) -> Double? {
    if let s = value as? String { return Double(s) }
    if let n = value as? NSNumber { return n.doubleValue }
    return nil
}

private nonisolated func jsonBool(_ value: Any?) -> Bool? {
    if let s = value as? String { return s == "true" ? true : (s == "false" ? false : nil) }
    if let n = value as? NSNumber { return n.boolValue }
    return nil
}

private nonisolated func jsonInt(_ value: Any?) -> Int? {
    guard let d = jsonDouble(value) else { return nil }
    return Int(exactly: d.rounded()) ?? nil
}

/// One analytical (X-ray) detector segment: the Super-X is four of these.
package nonisolated struct VeloxDetectorInfo: Equatable, Sendable {
    package let index: Int
    package let name: String
    package let type: String
    package let enabled: Bool?
    package let inserted: Bool?
    /// Radians, as stored.
    package let azimuthRadians: Double?
    package let elevationRadians: Double?
    /// Key `CollectionAngle`, in steradians AS STORED. Whether it is the segment's or the whole detector's differs by
    /// file (0.225, 0.7 and 4.35 seen): use it only as a relative weight among ONE file's segments, never summed to a total.
    package let solidAngleSteradians: Double?
    package let dispersionEV: Double?
    package let offsetEnergyEV: Double?
    /// Column-0 values of the stream's per-frame metadata, recorded as read. SEMANTICS UNVERIFIED: the meaning
    /// differs by file (cumulative in one, per-frame in another, 0 on the owner's file: formats.md §2.2), so
    /// they are reported and never interpreted or used.
    package let realTimeColumn0: Double?
    package let liveTimeColumn0: Double?

    package var azimuthDegrees: Double? { azimuthRadians.map { $0 * 180 / .pi } }
    package var elevationDegrees: Double? { elevationRadians.map { $0 * 180 / .pi } }
    package var isAnalytical: Bool { type == "AnalyticalDetector" }
}

/// Energy of channel `k` is `offsetKeV + k * scaleKeV`.
package nonisolated struct VeloxEnergyAxis: Equatable, Sendable {
    package let offsetKeV: Double
    package let scaleKeV: Double
    package init(offsetKeV: Double, scaleKeV: Double) {
        self.offsetKeV = offsetKeV; self.scaleKeV = scaleKeV
    }
}

/// The 2x3 affine Velox records per frame when it drift-corrects the SI. RECORDED
/// ONLY: the stream is the raw detector order and this reader applies nothing.
package nonisolated struct VeloxScanTransformation: Equatable, Sendable {
    package let a11: Double, a12: Double, a13: Double
    package let a21: Double, a22: Double, a23: Double
    package init(a11: Double, a12: Double, a13: Double, a21: Double, a22: Double, a23: Double) {
        self.a11 = a11; self.a12 = a12; self.a13 = a13; self.a21 = a21; self.a22 = a22; self.a23 = a23
    }
}

package nonisolated struct VeloxMetadata: Sendable {
    package let detectors: [VeloxDetectorInfo]
    /// The detector whose events the first stream carries (`BinaryResult.Detector`).
    package let binaryResultDetector: String?
    package let binaryResultDetectorIndex: Int?
    package let energyAxis: VeloxEnergyAxis?
    /// `ScanSize`, the full raster, not the spectrum image (that is `ScanSize x ScanArea`).
    package let scanSizeWidth: Int?
    package let scanSizeHeight: Int?
    /// Fractions of the full raster: left, top, right, bottom.
    package let scanArea: (left: Double, top: Double, right: Double, bottom: Double)?
    package let scanRotationRadians: Double?
    package let dwellTimeSeconds: Double?
    package let frameTimeSeconds: Double?
    package let accelerationVoltageVolts: Double?
    package let screenCurrentAmperes: Double?
    package let stageAlphaRadians: Double?
    package let stageBetaRadians: Double?
    package let stagePositionMeters: (x: Double, y: Double, z: Double)?
    package let holderType: String?
    package let pixelSizeMeters: (width: Double, height: Double)?
    package let pixelUnit: String?
    package let instrumentModel: String?
    package let acquisitionStartUnixTime: Double?
    package let scanTransformation: VeloxScanTransformation?

    package var superXDetectors: [VeloxDetectorInfo] { detectors.filter { $0.isAnalytical } }
    package var alphaDegrees: Double? { stageAlphaRadians.map { $0 * 180 / .pi } }
    package var betaDegrees: Double? { stageBetaRadians.map { $0 * 180 / .pi } }

    /// The grid `ScanSize x ScanArea` implies, `(ny, nx)`; nil unless both are
    /// integers to within 1/100 of a pixel (the Velox rasters are exact binary fractions).
    package var derivedGrid: (ny: Int, nx: Int)? {
        guard let w = scanSizeWidth, let h = scanSizeHeight, let a = scanArea else { return nil }
        let nx = Double(w) * (a.right - a.left), ny = Double(h) * (a.bottom - a.top)
        guard abs(nx - nx.rounded()) < 0.01, abs(ny - ny.rounded()) < 0.01, nx >= 1, ny >= 1 else { return nil }
        return (Int(ny.rounded()), Int(nx.rounded()))
    }

    package static func parse(jsonData: Data) throws -> VeloxMetadata {
        guard let root = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw VeloxEMDError.missingMetadata("a JSON object as metadata")
        }
        return parse(root: root)
    }

    package static func parse(root: [String: Any]) -> VeloxMetadata {
        func dict(_ parent: [String: Any]?, _ key: String) -> [String: Any]? { parent?[key] as? [String: Any] }
        // `Detector-<n>` in file order. A JSON object has no order in Swift, but the
        // index in the key is the file's order (rsciio iterates insertion order).
        var detectors: [VeloxDetectorInfo] = []
        if let all = root["Detectors"] as? [String: Any] {
            for (key, value) in all {
                guard key.hasPrefix("Detector-"), let index = Int(key.dropFirst("Detector-".count)),
                      let d = value as? [String: Any] else { continue }
                detectors.append(VeloxDetectorInfo(
                    index: index, name: d["DetectorName"] as? String ?? "", type: d["DetectorType"] as? String ?? "",
                    enabled: jsonBool(d["Enabled"]), inserted: jsonBool(d["Inserted"]),
                    azimuthRadians: jsonDouble(d["AzimuthAngle"]), elevationRadians: jsonDouble(d["ElevationAngle"]),
                    solidAngleSteradians: jsonDouble(d["CollectionAngle"]),
                    dispersionEV: jsonDouble(d["Dispersion"]), offsetEnergyEV: jsonDouble(d["OffsetEnergy"]),
                    realTimeColumn0: jsonDouble(d["RealTime"]), liveTimeColumn0: jsonDouble(d["LiveTime"])))
            }
            detectors.sort { $0.index < $1.index }
        }
        let binary = root["BinaryResult"] as? [String: Any]
        let detectorName = binary?["Detector"] as? String

        // rsciio `_get_dispersion_offset`: the first detector (file order) whose name
        // CONTAINS BinaryResult.Detector; dispersion and offset are eV, reported keV.
        // DEVIATION: rsciio silently falls back to scale 1, offset 0 when this fails;
        // here the axis is nil, so a caller cannot mistake a missing calibration for 1 keV/channel.
        var energy: VeloxEnergyAxis?
        if let detectorName {
            for d in detectors where d.name.contains(detectorName) {
                if let dispersion = d.dispersionEV, let offset = d.offsetEnergyEV {
                    energy = VeloxEnergyAxis(offsetKeV: offset / 1000.0, scaleKeV: dispersion / 1000.0)
                }
                break
            }
        }

        let scan = dict(root, "Scan")
        let size = dict(scan, "ScanSize"), area = dict(scan, "ScanArea")
        var areaTuple: (Double, Double, Double, Double)?
        if let l = jsonDouble(area?["left"]), let t = jsonDouble(area?["top"]),
           let r = jsonDouble(area?["right"]), let b = jsonDouble(area?["bottom"]) { areaTuple = (l, t, r, b) }
        let stage = dict(root, "Stage"), position = dict(stage, "Position")
        var positionTuple: (Double, Double, Double)?
        if let x = jsonDouble(position?["x"]), let y = jsonDouble(position?["y"]), let z = jsonDouble(position?["z"]) {
            positionTuple = (x, y, z)
        }
        let pixelSize = dict(binary, "PixelSize")
        var pixelTuple: (Double, Double)?
        if let w = jsonDouble(pixelSize?["width"]), let h = jsonDouble(pixelSize?["height"]) { pixelTuple = (w, h) }

        // The per-frame drift-correction affine sits in CustomProperties, each
        // entry as {"type": "double", "value": "..."}.
        // The keys are FLAT dotted names: `CustomProperties["Scan.ScanTransformation.A11"]["value"]`
        // (verified on the owner's v9 file, five v4-v6 files, v11 and v13). A nested
        // CustomProperties.Scan.ScanTransformation.A11 is accepted as a fallback.
        var transformation: VeloxScanTransformation?
        let custom = dict(root, "CustomProperties")
        let nested = dict(dict(custom, "Scan"), "ScanTransformation")
        func entry(_ k: String) -> Double? {
            jsonDouble(dict(custom, "Scan.ScanTransformation." + k)?["value"]) ?? jsonDouble(dict(nested, k)?["value"])
        }
        if let a11 = entry("A11"), let a12 = entry("A12"), let a13 = entry("A13"),
           let a21 = entry("A21"), let a22 = entry("A22"), let a23 = entry("A23") {
            transformation = VeloxScanTransformation(a11: a11, a12: a12, a13: a13, a21: a21, a22: a22, a23: a23)
        }

        return VeloxMetadata(
            detectors: detectors, binaryResultDetector: detectorName, binaryResultDetectorIndex: jsonInt(binary?["DetectorIndex"]), energyAxis: energy,
            scanSizeWidth: jsonInt(size?["width"]), scanSizeHeight: jsonInt(size?["height"]),
            scanArea: areaTuple.map { (left: $0.0, top: $0.1, right: $0.2, bottom: $0.3) },
            scanRotationRadians: jsonDouble(scan?["ScanRotation"]),
            dwellTimeSeconds: jsonDouble(scan?["DwellTime"]), frameTimeSeconds: jsonDouble(scan?["FrameTime"]),
            accelerationVoltageVolts: jsonDouble(dict(root, "Optics")?["AccelerationVoltage"]),
            screenCurrentAmperes: jsonDouble(dict(root, "Optics")?["ScreenCurrent"]),
            stageAlphaRadians: jsonDouble(stage?["AlphaTilt"]), stageBetaRadians: jsonDouble(stage?["BetaTilt"]),
            stagePositionMeters: positionTuple.map { (x: $0.0, y: $0.1, z: $0.2) },
            holderType: stage?["HolderType"] as? String,
            pixelSizeMeters: pixelTuple.map { (width: $0.0, height: $0.1) },
            pixelUnit: binary?["PixelUnitX"] as? String,
            instrumentModel: dict(root, "Instrument")?["InstrumentModel"] as? String,
            acquisitionStartUnixTime: jsonDouble(dict(dict(root, "Acquisition"), "AcquisitionStartDatetime")?["DateTime"]),
            scanTransformation: transformation)
    }
}

// MARK: - HDF5 binding (Velox's own subset)

nonisolated private let veloxReadOnly: UInt32 = 0
nonisolated private let veloxDefaultProperty: hid_t = 0
nonisolated private let veloxSelectSet: Int32 = 0
nonisolated private let veloxIntegerClass: Int32 = 0

private nonisolated final class VeloxLinkCollector: @unchecked Sendable {
    var names: [String] = []
}

private nonisolated let collectVeloxLink: @convention(c)
    (hid_t, UnsafePointer<CChar>?, UnsafeRawPointer?, UnsafeMutableRawPointer?) -> herr_t = {
        _, name, _, context in
        guard let name, let context else { return 0 }
        let collector = Unmanaged<VeloxLinkCollector>.fromOpaque(context).takeUnretainedValue()
        collector.names.append(String(cString: name))
        return 0
    }

/// The HDF5 calls the Velox reader needs, loaded from the same bundled library
/// `H5Reader` uses. Why not `H5Reader`'s binding: it is `private` to that file, which
/// this work may not change, and it lacks the unsigned native types a uint16 stream
/// needs. Every entry runs under `HDF5Serial` (HDF5Types.swift): callers of this type
/// hold the lock across a whole logical operation.
private nonisolated struct VeloxHDF5: @unchecked Sendable {
    typealias H5open = @convention(c) () -> herr_t
    typealias H5EsetAuto2 = @convention(c) (hid_t, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> herr_t
    typealias H5Fopen = @convention(c) (UnsafePointer<CChar>?, UInt32, hid_t) -> hid_t
    typealias H5Close = @convention(c) (hid_t) -> herr_t
    typealias H5Dopen2 = @convention(c) (hid_t, UnsafePointer<CChar>?, hid_t) -> hid_t
    typealias H5DgetSpace = @convention(c) (hid_t) -> hid_t
    typealias H5DgetType = @convention(c) (hid_t) -> hid_t
    typealias H5Dread = @convention(c) (hid_t, hid_t, hid_t, hid_t, hid_t, UnsafeMutableRawPointer?) -> herr_t
    typealias H5SgetNdims = @convention(c) (hid_t) -> Int32
    typealias H5SgetDims = @convention(c) (hid_t, UnsafeMutablePointer<hsize_t>?, UnsafeMutablePointer<hsize_t>?) -> Int32
    typealias H5SselectHyperslab = @convention(c) (hid_t, Int32, UnsafePointer<hsize_t>?, UnsafePointer<hsize_t>?, UnsafePointer<hsize_t>?, UnsafePointer<hsize_t>?) -> herr_t
    typealias H5ScreateSimple = @convention(c) (Int32, UnsafePointer<hsize_t>?, UnsafePointer<hsize_t>?) -> hid_t
    typealias H5Tcopy = @convention(c) (hid_t) -> hid_t
    typealias H5TgetClass = @convention(c) (hid_t) -> Int32
    typealias H5TisVariableStr = @convention(c) (hid_t) -> Int32
    typealias H5Oopen = @convention(c) (hid_t, UnsafePointer<CChar>?, hid_t) -> hid_t
    typealias H5Literate = @convention(c) (hid_t, UnsafePointer<CChar>?, UnsafeRawPointer?, UnsafeMutableRawPointer?) -> herr_t
    typealias H5Lvisit2 = @convention(c) (hid_t, Int32, Int32, H5Literate, UnsafeMutableRawPointer?) -> herr_t
    typealias H5freeMemory = @convention(c) (UnsafeMutableRawPointer?) -> herr_t

    let h5open: H5open, h5eSetAuto2: H5EsetAuto2, h5fopen: H5Fopen, h5fclose: H5Close
    let h5dopen2: H5Dopen2, h5dclose: H5Close, h5dgetSpace: H5DgetSpace, h5dgetType: H5DgetType, h5dread: H5Dread
    let h5sclose: H5Close, h5sgetNdims: H5SgetNdims, h5sgetDims: H5SgetDims
    let h5sselectHyperslab: H5SselectHyperslab, h5screateSimple: H5ScreateSimple
    let h5tcopy: H5Tcopy, h5tclose: H5Close, h5tgetClass: H5TgetClass, h5tisVariableStr: H5TisVariableStr
    let h5oopen: H5Oopen, h5oclose: H5Close, h5lvisit2: H5Lvisit2, h5freeMemory: H5freeMemory
    let uint8: hid_t, uint16: hid_t, uint32: hid_t, uint64: hid_t

    static func load() throws -> VeloxHDF5 {
        let candidates: [String] = [
            ProcessInfo.processInfo.environment["MAC4DSTEM_HDF5_PATH"],
            Bundle.main.privateFrameworksURL?.appendingPathComponent("libhdf5.dylib").path,
            Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("../Frameworks/libhdf5.dylib").standardized.path,
            "libhdf5.dylib"
        ].compactMap { $0 }
        var failures: [String] = []
        var handle: UnsafeMutableRawPointer?
        for path in candidates where handle == nil {
            dlerror()
            handle = dlopen(path, RTLD_NOW | RTLD_LOCAL)
            if handle == nil { failures.append("\(path): \(dlerror().map { String(cString: $0) } ?? "unknown")") }
        }
        guard let handle else { throw VeloxEMDError.libraryUnavailable(failures.joined(separator: "\n")) }
        func symbol<T>(_ name: String, as: T.Type) throws -> T {
            guard let p = dlsym(handle, name) else { throw VeloxEMDError.libraryUnavailable("missing symbol \(name)") }
            return unsafeBitCast(p, to: T.self)
        }
        func global(_ name: String) throws -> hid_t {
            guard let p = dlsym(handle, name) else { throw VeloxEMDError.libraryUnavailable("missing symbol \(name)") }
            return p.assumingMemoryBound(to: hid_t.self).pointee
        }
        let open = try symbol("H5open", as: H5open.self)
        // After H5open, never before: it registers HDF5's atexit teardown (HDF5Types.swift).
        if open() >= 0 { HDF5Serial.installExitBarrier() }
        let auto = try symbol("H5Eset_auto2", as: H5EsetAuto2.self)
        _ = auto(veloxDefaultProperty, nil, nil)     // a probe that finds nothing is an answer, not a stack dump
        return VeloxHDF5(
            h5open: open, h5eSetAuto2: auto,
            h5fopen: try symbol("H5Fopen", as: H5Fopen.self), h5fclose: try symbol("H5Fclose", as: H5Close.self),
            h5dopen2: try symbol("H5Dopen2", as: H5Dopen2.self), h5dclose: try symbol("H5Dclose", as: H5Close.self),
            h5dgetSpace: try symbol("H5Dget_space", as: H5DgetSpace.self), h5dgetType: try symbol("H5Dget_type", as: H5DgetType.self),
            h5dread: try symbol("H5Dread", as: H5Dread.self),
            h5sclose: try symbol("H5Sclose", as: H5Close.self),
            h5sgetNdims: try symbol("H5Sget_simple_extent_ndims", as: H5SgetNdims.self),
            h5sgetDims: try symbol("H5Sget_simple_extent_dims", as: H5SgetDims.self),
            h5sselectHyperslab: try symbol("H5Sselect_hyperslab", as: H5SselectHyperslab.self),
            h5screateSimple: try symbol("H5Screate_simple", as: H5ScreateSimple.self),
            h5tcopy: try symbol("H5Tcopy", as: H5Tcopy.self), h5tclose: try symbol("H5Tclose", as: H5Close.self),
            h5tgetClass: try symbol("H5Tget_class", as: H5TgetClass.self),
            h5tisVariableStr: try symbol("H5Tis_variable_str", as: H5TisVariableStr.self),
            h5oopen: try symbol("H5Oopen", as: H5Oopen.self), h5oclose: try symbol("H5Oclose", as: H5Close.self),
            h5lvisit2: try symbol("H5Lvisit2", as: H5Lvisit2.self), h5freeMemory: try symbol("H5free_memory", as: H5freeMemory.self),
            uint8: try global("H5T_NATIVE_UINT8_g"), uint16: try global("H5T_NATIVE_UINT16_g"),
            uint32: try global("H5T_NATIVE_UINT32_g"), uint64: try global("H5T_NATIVE_UINT64_g"))
    }
}

/// One open file. A class so the handle closes with it; every method is called with
/// `HDF5Serial` held by the owning operation.
private nonisolated final class VeloxFile {
    let h5: VeloxHDF5
    let file: hid_t

    init(path: String) throws {
        let lib = try VeloxHDF5.load()
        let id = path.withCString { lib.h5fopen($0, veloxReadOnly, veloxDefaultProperty) }
        guard id >= 0 else { throw VeloxEMDError.cannotOpen(displayFileName(path)) }
        h5 = lib
        file = id
    }
    deinit { _ = h5.h5fclose(file) }

    func exists(_ path: String) -> Bool {
        let id = path.withCString { h5.h5oopen(file, $0, veloxDefaultProperty) }
        guard id >= 0 else { return false }
        _ = h5.h5oclose(id)
        return true
    }

    /// Names of the direct children of a group, sorted (h5py iterates by name, and rsciio
    /// takes "the last image" and "the first stream" in that order).
    func children(of group: String) -> [String] {
        let id = group.withCString { h5.h5oopen(file, $0, veloxDefaultProperty) }
        guard id >= 0 else { return [] }
        defer { _ = h5.h5oclose(id) }
        let collector = VeloxLinkCollector()
        let unmanaged = Unmanaged.passUnretained(collector)
        _ = h5.h5lvisit2(id, 0, 0, collectVeloxLink, unmanaged.toOpaque())
        return collector.names.filter { !$0.contains("/") }.sorted()
    }

    struct Dataset {
        let id: hid_t
        let dims: [Int]
        let isInteger: Bool
    }

    func open(_ path: String) throws -> Dataset {
        let id = path.withCString { h5.h5dopen2(file, $0, veloxDefaultProperty) }
        guard id >= 0 else { throw VeloxEMDError.readFailed("opening \(path)") }
        let space = h5.h5dgetSpace(id)
        defer { _ = h5.h5sclose(space) }
        let rank = Int(h5.h5sgetNdims(space))
        var dims = [hsize_t](repeating: 0, count: max(rank, 1))
        if rank > 0 { _ = h5.h5sgetDims(space, &dims, nil) }
        let type = h5.h5dgetType(id)
        defer { _ = h5.h5tclose(type) }
        return Dataset(id: id, dims: dims.prefix(rank).map { Int($0) }, isInteger: h5.h5tgetClass(type) == veloxIntegerClass)
    }

    func close(_ dataset: Dataset) { _ = h5.h5dclose(dataset.id) }

    /// A variable-length string dataset's first element (Version, AcquisitionSettings, ...).
    func readString(_ path: String) -> String? {
        guard let dataset = try? open(path) else { return nil }
        defer { close(dataset) }
        // One pointer is all the read below has room for: a dataset of several elements
        // (any other HDF5 file passes through `isVeloxEMD`) would write past it.
        guard dataset.dims.reduce(1, *) == 1 else { return nil }
        let fileType = h5.h5dgetType(dataset.id)
        defer { _ = h5.h5tclose(fileType) }
        guard h5.h5tisVariableStr(fileType) > 0 else { return nil }
        let memType = h5.h5tcopy(fileType)
        defer { _ = h5.h5tclose(memType) }
        var pointer: UnsafeMutablePointer<CChar>?
        // Element 0 of a (1,) dataset: the default selection would also read a (n,) one into one slot.
        let status = withUnsafeMutableBytes(of: &pointer) { h5.h5dread(dataset.id, memType, 0, 0, veloxDefaultProperty, $0.baseAddress) }
        guard status >= 0, let pointer else { return nil }
        defer { _ = h5.h5freeMemory(pointer) }
        return String(cString: pointer)
    }

    /// Reads `count` elements starting at `start` (one hyperslab), rank 1 to 3, into `buffer`.
    func readSlab(_ dataset: Dataset, type: hid_t, start: [Int], count: [Int], into buffer: UnsafeMutableRawPointer) throws {
        let space = h5.h5dgetSpace(dataset.id)
        defer { _ = h5.h5sclose(space) }
        let s = start.map { hsize_t($0) }, c = count.map { hsize_t($0) }
        guard h5.h5sselectHyperslab(space, veloxSelectSet, s, nil, c, nil) >= 0 else {
            throw VeloxEMDError.readFailed("selecting a hyperslab")
        }
        let memSpace = h5.h5screateSimple(Int32(c.count), c, nil)
        guard memSpace >= 0 else { throw VeloxEMDError.readFailed("creating the memory dataspace") }
        defer { _ = h5.h5sclose(memSpace) }
        guard h5.h5dread(dataset.id, type, memSpace, space, veloxDefaultProperty, buffer) >= 0 else {
            throw VeloxEMDError.readFailed("reading a hyperslab")
        }
    }

    /// One column of a `(60000, nFrames)` uint8 `Metadata` dataset: NUL-padded UTF-8 JSON.
    func readMetadataJSON(group: String, column: Int) throws -> Data {
        let dataset = try open(group + "/Metadata")
        defer { close(dataset) }
        guard dataset.dims.count == 2, column >= 0, column < dataset.dims[1] else {
            throw VeloxEMDError.missingMetadata("metadata column \(column) of \(group)")
        }
        var bytes = [UInt8](repeating: 0, count: dataset.dims[0])
        try bytes.withUnsafeMutableBytes {
            try readSlab(dataset, type: h5.uint8, start: [0, column], count: [dataset.dims[0], 1], into: $0.baseAddress!)
        }
        if let end = bytes.firstIndex(of: 0) { bytes.removeSubrange(end...) }
        return Data(bytes)
    }
}

// MARK: - The reader

/// The HAADF (or best available scan) image on the spectrum grid, frames summed.
package nonisolated struct VeloxScanImage: Sendable {
    package let ny: Int
    package let nx: Int
    /// `ny * nx` row-major, summed over `framesSummed` frames, in UInt32 so 1607 frames cannot wrap.
    package let sum: [UInt32]
    package let framesSummed: Int
    /// Frames the file holds for this image.
    package let framesInFile: Int
    package let detectorName: String
}

package nonisolated struct VeloxSpectrumImage: Sendable {
    package let eventStore: VeloxEventStore
    package let scanImage: VeloxScanImage?
    /// Metadata of the first stream (column 0).
    package let metadata: VeloxMetadata
    package let version: String
    /// Streams summed (4 for a Super-X, 6 for an UltraX, 1 otherwise).
    package let streamCount: Int
    /// `endFramePosition` of `SpectrumImageSettings` (end, 1-based inclusive) and `startFramePosition`.
    package let settingsFrames: (start: Int?, end: Int?)
    /// Every stream, in name order, with the detector it carries and the X-ray segments that detector name
    /// resolves to. The owner's Super-X file has ONE pre-summed stream "SuperXG1" = segments SuperXG11-14; the
    /// fei 4-detector file has one stream per segment; an UltraX file has six.
    package let streams: [VeloxStreamInfo]
    /// False when the segments the streams resolve to do not all share dispersion and offset: the summed
    /// spectrum would then mix energy scales, and `metadata.energyAxis` (the first stream's) fits only some of it.
    package let energyCalibrationAgrees: Bool
}

package nonisolated struct VeloxStreamInfo: Sendable {
    /// The stream's group id under Data/SpectrumStream.
    package let id: String
    /// `BinaryResult.Detector` and `DetectorIndex` of the stream's own metadata (column 0).
    package let detectorName: String?
    package let detectorIndex: Int?
    /// The analytical detectors whose name CONTAINS `detectorName` (rsciio's matching rule), in file order,
    /// each with its (azimuth, elevation) pair.
    package let segments: [VeloxDetectorInfo]
}

package nonisolated struct VeloxEMDReader: Sendable {
    package let path: String

    package init(path: String) { self.path = path }

    /// True for a Velox EMD that carries a spectrum stream or a spectrum image:
    /// root `Version` JSON with `format` "Velox", and `Data/SpectrumStream` or
    /// `Data/SpectrumImage`. False for anything else, including an unreadable file.
    package static func isVeloxEMD(path: String) -> Bool {
        HDF5Serial.run {
            guard let file = try? VeloxFile(path: path) else { return false }
            guard let version = file.readString("/Version"), parseVersion(version)?.format == "Velox" else { return false }
            return file.exists("/Data/SpectrumStream") || file.exists("/Data/SpectrumImage")
        }
    }

    private static func parseVersion(_ json: String) -> (version: String, format: String)? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let format = object["format"] as? String else { return nil }
        return (object["version"] as? String ?? "", format)
    }

    private struct StreamRef {
        let name: String
        var group: String { "/Data/SpectrumStream/" + name }
    }

    /// Reads the spectrum image: the stream summed over `frames`, the scan image on the
    /// same grid, and the metadata.
    package func readSpectrumImage(frames: VeloxFrameSelection = .recordedDefault) throws -> VeloxSpectrumImage {
        try HDF5Serial.run {
            let file = try VeloxFile(path: path)
            guard let versionText = file.readString("/Version"), let version = Self.parseVersion(versionText),
                  version.format == "Velox" else { throw VeloxEMDError.notVelox(displayFileName(path)) }
            let streams = file.children(of: "/Data/SpectrumStream").map(StreamRef.init)
            guard !streams.isEmpty else { throw VeloxEMDError.noSpectrumStream }

            // Metadata of the first stream, in name order: rsciio's `streams[0]`.
            let head = streams[0]
            let metadata = try VeloxMetadata.parse(jsonData: file.readMetadataJSON(group: head.group, column: 0))
            guard let settingsText = file.readString(head.group + "/AcquisitionSettings"),
                  let settings = try JSONSerialization.jsonObject(with: Data(settingsText.utf8)) as? [String: Any],
                  let channels = jsonInt(settings["bincount"]), channels > 0 else {
                throw VeloxEMDError.missingMetadata("AcquisitionSettings.bincount")
            }

            // SI settings: endFramePosition is rsciio's frame count and last_frame.
            var settingsStart: Int?, settingsEnd: Int?
            if let first = file.children(of: "/Data/SpectrumImage").first,
               let text = file.readString("/Data/SpectrumImage/\(first)/SpectrumImageSettings"),
               let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] {
                settingsStart = jsonInt(object["startFramePosition"])
                settingsEnd = jsonInt(object["endFramePosition"])
            }
            // startFramePosition is 1 in every file seen, where 1-based inclusive equals rsciio's first_frame 0.
            // Any other value would be a trimmed acquisition whose meaning nobody has established: refuse.
            if let start = settingsStart, start != 1 {
                throw VeloxEMDError.unsupportedFramePosition("startFramePosition is \(start); only 1 is understood")
            }
            if let end = settingsEnd, end < 1 {
                throw VeloxEMDError.frameRangeInvalid("endFramePosition is \(end)")
            }

            // The grid. DEVIATION: rsciio takes it from the LAST image group read (name order),
            // whatever that image is. In `example_velox_EELS_EDS.emd` that is a 128 x 128 image of a
            // 16 x 20 spectrum image, and every count lands in the first rows (formats.md §2.2,
            // reproduced by tools/velox-parity). Here the grid is ScanSize x ScanArea. Evidence it is the
            // right one: in that file the seven (16, 20, 1) images share the stream's ScanArea
            // (128 x 0.15625 = 20 columns, 128 x 0.125 = 16 rows); the non-square public 10 x 50 files' HAADF
            // is (50, 10); the owner's HAADF is (926, 215, 1607) with ScanArea 0.2100 x 0.9043 of 1024.
            // rsciio's last-image rule is the fallback when the metadata cannot say, and then it must be
            // an integer scan image, or the grid is refused.
            let imageNames = file.children(of: "/Data/Image")
            var imageShapes: [(name: String, ny: Int, nx: Int, frames: Int, isInteger: Bool)] = []
            for name in imageNames {
                let dataset = try file.open("/Data/Image/\(name)/Data")
                defer { file.close(dataset) }
                if dataset.dims.count == 3 {
                    imageShapes.append((name, dataset.dims[0], dataset.dims[1], dataset.dims[2], dataset.isInteger))
                }
            }
            let grid: (ny: Int, nx: Int)
            if let derived = metadata.derivedGrid {
                grid = derived
            } else if let last = imageShapes.last {
                guard last.isInteger, imageShapes.contains(where: { $0.ny == last.ny && $0.nx == last.nx && $0.isInteger }) else {
                    throw VeloxEMDError.cannotDetermineGrid("ScanArea is missing and the last image is not an integer scan image")
                }
                grid = (last.ny, last.nx)
            } else {
                throw VeloxEMDError.cannotDetermineGrid("neither ScanSize x ScanArea nor an image gives it")
            }
            let geometry = VeloxStreamGeometry(ny: grid.ny, nx: grid.nx, channels: channels)

            // The stream must fit the grid, BEFORE anything is allocated from it. One pass over the first stream.
            let (_, markers) = try Self.lengthAndMarkers(file: file, stream: head)
            let pixels = geometry.pixelsPerFrame
            guard pixels >= 1, pixels <= Self.maximumPixels, pixels <= markers + 1 else {   // + 1: the last pixel's marker may be absent
                throw VeloxEMDError.gridInconsistent("\(grid.ny) x \(grid.nx) pixels per frame against \(markers) pixel ends")
            }
            var tableFrames: Int?
            if file.exists(head.group + "/FrameLocationTable") {
                let table = try file.open(head.group + "/FrameLocationTable")
                defer { file.close(table) }
                tableFrames = table.dims.first
            }
            // ceil(markers / pixels): rsciio's own frame count. A stream may lack its LAST marker (the 16 x 20
            // EELS_EDS stream has 319 of 320), but never a whole frame's worth.
            let frameCountGuess = (markers + pixels - 1) / pixels
            if let n = tableFrames, n != frameCountGuess {
                throw VeloxEMDError.gridInconsistent("the FrameLocationTable lists \(n) frames; \(markers) pixel ends over \(grid.ny) x \(grid.nx) pixels make \(frameCountGuess)")
            }
            // Without a FrameLocationTable a grid SMALLER than the stream can pass this check (the grid comes from
            // ScanSize x ScanArea, not from the stream); the table is the only cross-check on the grid size.
            // A stopped acquisition (a partial last frame) is NOT refused: fei_emd_si.emd is one, and rsciio
            // reads it. It is reported in the store (`partialFramePixels`) instead.

            // Frame range: rsciio's first_frame = 0, last_frame = endFramePosition, else the
            // stream's own frame count. An explicit range may not pass endFramePosition (rsciio raises).
            let limit = settingsEnd ?? frameCountGuess
            let range: Range<Int>
            switch frames {
            case .recordedDefault: range = 0..<limit
            case .all: range = 0..<frameCountGuess
            case .range(let r):
                guard r.upperBound <= limit else {
                    throw VeloxEMDError.frameRangeInvalid("\(r) passes the \(limit) frames of this file")
                }
                range = r
            }

            // Sources: one restartable block reader per stream, over its own dataset handle.
            var sources: [VeloxStreamDecoder.BlockSource] = []
            for stream in streams {
                sources.append(Self.blockSource(file: file, dataset: stream.group + "/Data"))
            }
            let store = try VeloxStreamDecoder.buildEventStore(streams: sources, geometry: geometry, frames: range)

            // Which detector each stream carries, and whether the summed segments share an energy scale.
            var infos: [VeloxStreamInfo] = []
            for stream in streams {
                let m = stream.name == head.name ? metadata
                    : try VeloxMetadata.parse(jsonData: file.readMetadataJSON(group: stream.group, column: 0))
                let name = m.binaryResultDetector
                // `contains`, rsciio's rule, would also take a hypothetical SuperXG10 for SuperXG1 (or UltraX10 for UltraX1).
                let segments = name.map { n in m.detectors.filter { $0.isAnalytical && $0.name.contains(n) } } ?? []
                infos.append(VeloxStreamInfo(id: stream.name, detectorName: name, detectorIndex: m.binaryResultDetectorIndex, segments: segments))
            }
            var calibrations = Set<String>()
            for segment in infos.flatMap(\.segments) {
                calibrations.insert("\(segment.dispersionEV ?? .nan)|\(segment.offsetEnergyEV ?? .nan)")
            }

            let image = try Self.readScanImage(
                file: file, shapes: imageShapes, grid: grid, range: range, preferredDetector: metadata.binaryResultDetector)
            return VeloxSpectrumImage(
                eventStore: store, scanImage: image, metadata: metadata, version: version.version,
                streamCount: streams.count, settingsFrames: (settingsStart, settingsEnd),
                streams: infos, energyCalibrationAgrees: calibrations.count <= 1)
        }
    }

    /// A stream's length and pixel-marker count, in one pass.
    private static func lengthAndMarkers(file: VeloxFile, stream: StreamRef) throws -> (values: Int, markers: Int) {
        var values = 0, markers = 0
        let source = blockSource(file: file, dataset: stream.group + "/Data")
        try source { block in
            values += block.count
            for v in block where v == VeloxStreamDecoder.pixelMarker { markers += 1 }
            return true
        }
        return (values, markers)
    }

    /// A sanity cap on ny * nx (2^28 pixels): a corrupt ScanSize must throw, not allocate gigabytes.
    private static let maximumPixels = 1 << 28

    /// 32 M values (64 MB) a block: the stream is read in chunks, never whole.
    private static let blockValues = 32 << 20

    private static func blockSource(file: VeloxFile, dataset path: String) -> VeloxStreamDecoder.BlockSource {
        { visit in
            let dataset = try file.open(path)
            defer { file.close(dataset) }
            guard dataset.dims.count >= 1 else { throw VeloxEMDError.readFailed("the stream \(path) has no extent") }
            let total = dataset.dims[0]
            let width = dataset.dims.count == 2 ? dataset.dims[1] : 1
            guard width == 1 else { throw VeloxEMDError.readFailed("the stream \(path) is not one column") }
            let buffer = UnsafeMutablePointer<UInt16>.allocate(capacity: min(total, blockValues))
            defer { buffer.deallocate() }
            var at = 0
            while at < total {
                let n = min(blockValues, total - at)
                let start = dataset.dims.count == 2 ? [at, 0] : [at]
                let count = dataset.dims.count == 2 ? [n, 1] : [n]
                try file.readSlab(dataset, type: file.h5.uint16, start: start, count: count, into: buffer)
                if try !visit(UnsafeBufferPointer(start: buffer, count: n)) { return }
                at += n
            }
        }
    }

    /// The scan image on the spectrum grid: the stream's own detector when it is an image
    /// (never, for EDX), else HAADF, then any dark field, then bright field, then the first
    /// integer image; summed over the same frame range, clipped to the frames the image has.
    private static func readScanImage(
        file: VeloxFile, shapes: [(name: String, ny: Int, nx: Int, frames: Int, isInteger: Bool)],
        grid: (ny: Int, nx: Int), range: Range<Int>, preferredDetector: String?
    ) throws -> VeloxScanImage? {
        let onGrid = shapes.filter { $0.ny == grid.ny && $0.nx == grid.nx && $0.isInteger }
        guard !onGrid.isEmpty else { return nil }
        var named: [(entry: (name: String, ny: Int, nx: Int, frames: Int, isInteger: Bool), detector: String)] = []
        for entry in onGrid {
            let json = try file.readMetadataJSON(group: "/Data/Image/\(entry.name)", column: 0)
            let root = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any]
            let detector = (root?["BinaryResult"] as? [String: Any])?["Detector"] as? String ?? ""
            named.append((entry, detector))
        }
        func rank(_ detector: String) -> Int {
            let d = detector.uppercased()
            if d.contains("HAADF") { return 0 }
            if d.contains("DF") { return 1 }
            if d.contains("BF") { return 2 }
            return 3
        }
        guard let pick = named.enumerated().min(by: { (rank($0.element.detector), $0.offset) < (rank($1.element.detector), $1.offset) })?.element
        else { return nil }

        let upper = min(range.upperBound, pick.entry.frames)
        let lower = min(range.lowerBound, upper)
        let dataset = try file.open("/Data/Image/\(pick.entry.name)/Data")
        defer { file.close(dataset) }
        let pixels = grid.ny * grid.nx
        var sum = [UInt32](repeating: 0, count: pixels)
        var frame = [UInt32](repeating: 0, count: pixels)
        // One frame per read: Velox chunks each frame separately, and a whole-stack read scatters element-wise.
        for f in lower..<upper {
            try frame.withUnsafeMutableBytes {
                try file.readSlab(dataset, type: file.h5.uint32, start: [0, 0, f], count: [grid.ny, grid.nx, 1], into: $0.baseAddress!)
            }
            for p in 0..<pixels { sum[p] &+= frame[p] }
        }
        return VeloxScanImage(
            ny: grid.ny, nx: grid.nx, sum: sum, framesSummed: upper - lower,
            framesInFile: pick.entry.frames, detectorName: pick.detector)
    }

    /// Diagnostic: how many pixel markers fall in each frame window of the first stream, from its
    /// `FrameLocationTable` (versions >= 6; nil without one). Every entry equals ny*nx when the
    /// grid is right (prediction P2), and a stopped acquisition shows as a short last entry.
    package func markersPerFrame() throws -> [Int]? {
        try HDF5Serial.run {
            let file = try VeloxFile(path: path)
            guard let head = file.children(of: "/Data/SpectrumStream").first else { throw VeloxEMDError.noSpectrumStream }
            let group = "/Data/SpectrumStream/" + head
            guard file.exists(group + "/FrameLocationTable") else { return nil }
            let table = try file.open(group + "/FrameLocationTable")
            defer { file.close(table) }
            guard let n = table.dims.first, n > 0 else { return nil }
            var starts = [UInt64](repeating: 0, count: n)
            try starts.withUnsafeMutableBytes {
                try file.readSlab(table, type: file.h5.uint64, start: table.dims.count == 2 ? [0, 0] : [0],
                                  count: table.dims.count == 2 ? [n, 1] : [n], into: $0.baseAddress!)
            }
            // Walk the stream once, counting markers between consecutive frame starts.
            var perFrame = [Int](repeating: 0, count: n)
            var position: UInt64 = 0
            var frame = 0
            let source = Self.blockSource(file: file, dataset: group + "/Data")
            try source { block in
                for v in block {
                    while frame + 1 < n && position >= starts[frame + 1] { frame += 1 }
                    if v == VeloxStreamDecoder.pixelMarker { perFrame[frame] += 1 }
                    position += 1
                }
                return true
            }
            return perFrame
        }
    }

    /// Diagnostic: the first stream's length and its pixel-marker count.
    package func streamLengthAndMarkers() throws -> (values: Int, markers: Int) {
        try HDF5Serial.run {
            let file = try VeloxFile(path: path)
            guard let head = file.children(of: "/Data/SpectrumStream").first else { throw VeloxEMDError.noSpectrumStream }
            return try Self.lengthAndMarkers(file: file, stream: StreamRef(name: head))
        }
    }

    /// The per-frame `ScanTransformation`, one entry per metadata column of the first stream
    /// (nil where a column lacks it). Recorded only; never applied.
    package func readFrameTransformations() throws -> [VeloxScanTransformation?] {
        try HDF5Serial.run {
            let file = try VeloxFile(path: path)
            guard let head = file.children(of: "/Data/SpectrumStream").first else { throw VeloxEMDError.noSpectrumStream }
            let group = "/Data/SpectrumStream/" + head
            let dataset = try file.open(group + "/Metadata")
            let columns = dataset.dims.count == 2 ? dataset.dims[1] : 0
            file.close(dataset)
            var out: [VeloxScanTransformation?] = []
            out.reserveCapacity(columns)
            for column in 0..<columns {
                let json = try file.readMetadataJSON(group: group, column: column)
                out.append((try? VeloxMetadata.parse(jsonData: json))?.scanTransformation)
            }
            return out
        }
    }

    /// Per frame (metadata column), each X-ray segment's RealTime and LiveTime AS READ. SEMANTICS UNVERIFIED:
    /// cumulative in one file, per-frame in another, 0 on the owner's file; recorded, never interpreted.
    package func readFrameDetectorTimes() throws -> [[(name: String, realTime: Double?, liveTime: Double?)]] {
        try HDF5Serial.run {
            let file = try VeloxFile(path: path)
            guard let head = file.children(of: "/Data/SpectrumStream").first else { throw VeloxEMDError.noSpectrumStream }
            let group = "/Data/SpectrumStream/" + head
            let dataset = try file.open(group + "/Metadata")
            let columns = dataset.dims.count == 2 ? dataset.dims[1] : 0
            file.close(dataset)
            var out: [[(name: String, realTime: Double?, liveTime: Double?)]] = []
            for column in 0..<columns {
                let m = try VeloxMetadata.parse(jsonData: file.readMetadataJSON(group: group, column: column))
                out.append(m.superXDetectors.map { ($0.name, $0.realTimeColumn0, $0.liveTimeColumn0) })
            }
            return out
        }
    }
}
