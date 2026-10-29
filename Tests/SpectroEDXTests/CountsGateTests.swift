//
//  CountsGateTests.swift
//  Role: The Velox stream decode and the spectrum-image
//        sums equal an independent decode, exactly (integer equality, no tolerance).
//
//  C1: `SpectrumImageOpener` / `VeloxEMDReader` against pins.json's NumPy decode of RosettaSciIO's public files (the decode
//      is asserted equal to the published constants at generation) and against the planted streams' DRAW
//      (velox-streams-truth.json: the events the generator wrote, no reader consulted).
//  C2: `sum(mask:)`, `windowSums`, `densified` against sums of that draw; totals above 2^32 stay exact.
//  C3: what is not carried (live time, dead time) is stated; the one thing checkable (no live-time product, no wrap) is.
//

import Foundation
import Testing
import SpectroTestSupport
import SpectroCore
import SpectroEDX
import FormatoEMD

struct CountsGateTests {

    private var countsPins: [String: Any] { EDXFixtures.pins.d("counts") }

    // MARK: helpers

    private func sparseSums(_ pairs: [[Int]], channels: Int) -> [UInt64] {
        var out = [UInt64](repeating: 0, count: channels)
        for p in pairs { out[p[0]] += UInt64(p[1]) }
        return out
    }

    private func intPairs(_ v: Any) -> [[Int]] { (v as! [[NSNumber]]).map { $0.map(\.intValue) } }

    /// A spectrum image from the planted file's path.
    private func open(_ path: String) throws -> LoadedSpectrumImage {
        #expect(SpectrumImageOpener.kind(ofFileAt: path) == .veloxSpectrumImage, "\(path)")
        return try SpectrumImageOpener.open(path: path, kind: .veloxSpectrumImage)
    }

    private func denseSHA(_ image: LoadedSpectrumImage) throws -> String {
        let sparse = try #require(image.image as? SparseSpectrumImage)
        let counts = sparse.densified().counts
        let data = counts.withUnsafeBytes { Data($0) }
        return EDXFixtures.sha256(data)
    }

    /// Checks one opened file against a pins entry: channel sums and pixel totals summed over the streams, dense cube hash, grid.
    private func checkAgainstPins(_ image: LoadedSpectrumImage, entry: [String: Any], label: String,
                                  fileID: String = #fileID, filePath: String = #filePath, line: Int = #line, column: Int = #column) throws {
        let sourceLocation = SourceLocation(fileID: fileID, filePath: filePath, line: line, column: column)
        let grid = entry.d("grid_scansize_x_scanarea")
        #expect(image.ny == grid.i("ny"), "\(label) ny", sourceLocation: sourceLocation)
        #expect(image.nx == grid.i("nx"), "\(label) nx", sourceLocation: sourceLocation)
        let channels = entry.i("bincount")
        #expect(image.channels == channels, "\(label)", sourceLocation: sourceLocation)
        let streams = entry.l("streams")
        var expSum = [UInt64](repeating: 0, count: channels)
        var expPix = [UInt64](repeating: 0, count: image.ny * image.nx)
        for s in streams {
            let cs = sparseSums(intPairs(s["channel_sums"]!), channels: channels)
            for c in 0..<channels { expSum[c] += cs[c] }
            for (p, t) in (s["pixel_totals"] as! [NSNumber]).enumerated() { expPix[p] += UInt64(t.intValue) }
        }
        #expect(image.sum(mask: nil) == expSum, "\(label): summed spectrum", sourceLocation: sourceLocation)
        #expect(image.windowSums([0..<channels])[0] == expPix, "\(label): pixel totals", sourceLocation: sourceLocation)
        #expect((try denseSHA(image)) == entry.s("dense_sha256"), "\(label): dense cube hash", sourceLocation: sourceLocation)
    }

    // MARK: C1 public files

    /// RosettaSciIO's public Velox spectrum-stream files (pins.counts.files, status ok): grid, channel sums, pixel totals and the
    /// dense cube equal the NumPy decode. The 4-detector file's published constants (865236, 913682, 867647, 916174; 3562739).
    @Test func testC1PublicFilesEqualTheIndependentDecode() throws {
        let files = countsPins.d("files")
        let wanted = [
            "fei_emd_files.zip/fei_SI_EDS-HAADF-4detectors_2frames.emd",
            "fei_emd_files.zip/fei_SI_SuperX-HAADF_10frames_10x50.emd",
            "fei_emd_files.zip/fei_SI_SuperX-HAADF_20frames_10x50.emd",
            "fei_emd_files.zip/fei_SI_SuperX-HAADF_20frames_10x50_2ev.emd",
            "fei_emd_files.zip/fei_emd_si.emd",
            "velox_EELS_EDS.zip/example_velox_EELS_EDS.emd",
            "velox_emd_v11_elementSelection.zip/SI_empty selection.emd",
            "velox_emd_version11.zip/Test SI 16x16 215 kx.emd",
        ]
        var checked = 0
        var skipped: [String] = []
        for label in wanted {
            let entry = try #require(files[label] as? [String: Any], "\(label)")
            #expect(entry.s("status") == "ok", "\(label)")
            let path: String
            do { path = try EDXFixtures.publicVelox(label: label) } catch is FixtureAbsent { skipped.append(label); continue }
            let image = try open(path)
            try checkAgainstPins(image, entry: entry, label: label)
            checked += 1
        }
        if !skipped.isEmpty { print("EDX C1: \(checked) public files checked, \(skipped.count) skipped (References absent): \(skipped)") }
        if checked == 0 { print("EDX C1: no public Velox file available (References/rosettasciio absent): nothing checked") }
    }

    /// The published constants on the 4-detector file, per stream and in all, from the decode itself.
    @Test func testC1FourDetectorFileMatchesTheTestConstantsOfRosettaSciIO() throws {
        let label = "fei_emd_files.zip/fei_SI_EDS-HAADF-4detectors_2frames.emd"
        guard let path = try EDXFixtures.publicVeloxIfPresent(label: label) else { return }
        let image = try open(path)
        #expect(image.sum(mask: nil).reduce(0, +) == 3_562_739)
        // The reader reports the streams in name order; rsciio's test names the totals in its own order.
        let v = try VeloxEMDReader(path: path).readSpectrumImage()
        #expect(v.streamCount == 4)
        let published = Set([865_236, 913_682, 867_647, 916_174])
        let entry = countsPins.d("files").d(label)
        let perStream = entry.l("streams").map { $0.i("events") }
        #expect(Set(perStream) == published)
        #expect(v.eventStore.totalCounts == 3_562_739)
        #expect(v.eventStore.frameRange == (0..<2))
        #expect(v.streamsAgreeOnCoverageForGate)
    }

    // MARK: C1 / C2 planted streams

    private struct Draw {
        let ny: Int, nx: Int, channels: Int
        /// events summed over streams and the frame range: expected dense cube (pixel, channel).
        var cube: [UInt64]
    }

    private func draw(case name: String, frames: Range<Int>? = nil) -> Draw {
        let t = EDXFixtures.streamTruth.d("cases").d(name)
        let g = t.d("grid"); let ny = g.i("ny"), nx = g.i("nx"), channels = t.i("channels")
        let range = frames ?? 0..<t.i("frames")
        var cube = [UInt64](repeating: 0, count: ny * nx * channels)
        for s in t.l("streams") {
            let ev = s["events"] as! [[[[NSNumber]]]]     // [frame][pixel][event][channel, count]
            for f in range { for (p, pix) in ev[f].enumerated() { for e in pix { cube[p * channels + e[0].intValue] += UInt64(e[1].intValue) } } }
        }
        return Draw(ny: ny, nx: nx, channels: channels, cube: cube)
    }

    private let plantedCases = ["1stream-1frame", "1stream-3frames", "4streams-2frames", "axis-decoy", "axis-order", "unterminated"]

    private func plantedPath(_ name: String) -> String {
        EDXFixtures.url(EDXFixtures.streamTruth.d("cases").d(name).s("file")).path
    }

    /// C1: every planted file, opened as the app opens it, equals the draw (events per channel and per pixel) and the NumPy decode.
    @Test func testC1PlantedStreamsEqualTheDraw() throws {
        for name in plantedCases {
            let d = draw(case: name)
            let image = try open(plantedPath(name))
            #expect(image.ny == d.ny, "\(name)"); #expect(image.nx == d.nx, "\(name)")
            #expect(image.channels == d.channels, "\(name)")
            let sparse = try #require(image.image as? SparseSpectrumImage)
            let dense = sparse.densified().counts.map(UInt64.init)
            #expect(dense == d.cube, "\(name): the dense cube")
            // and the independent NumPy decode (pins.counts.planted)
            let entry = countsPins.d("planted").d(name)
            try checkAgainstPins(image, entry: entry, label: name)
        }
    }

    /// C1 frame ranges: every `first..<last` the pins decoded (sums over the streams) equals the reader's `.range` selection.
    @Test func testC1PlantedFrameRangesEqualTheDraw() throws {
        for name in plantedCases {
            let entry = countsPins.d("planted").d(name)
            let ranges = entry.d("frame_ranges")
            #expect(!ranges.isEmpty, "\(name)")
            for (key, value) in ranges {
                let ab = key.split(separator: ".").compactMap { Int($0) }   // "0..2" splits to [0, 2]
                let range = ab[0]..<ab[1]
                let d = draw(case: name, frames: range)
                let store = try VeloxEMDReader(path: plantedPath(name)).readSpectrumImage(frames: .range(range)).eventStore
                #expect(store.frameRange == range, "\(name) \(key)")
                #expect(store.denseCounts().map(UInt64.init) == d.cube, "\(name) frames \(key): the draw")
                // the NumPy decode of the same range
                var expSum = [UInt64](repeating: 0, count: d.channels)
                var expPix = [UInt64](repeating: 0, count: d.ny * d.nx)
                for s in value as! [[String: Any]] {
                    let cs = sparseSums(intPairs(s["channel_sums"]!), channels: d.channels)
                    for c in 0..<d.channels { expSum[c] += cs[c] }
                    for (p, t) in (s["pixel_totals"] as! [NSNumber]).enumerated() { expPix[p] += UInt64(t.intValue) }
                }
                #expect(store.summedSpectrum() == expSum, "\(name) frames \(key): channel sums")
                let pix = (0..<store.pixelCount).map { p in
                    (store.rowOffsets[p]..<store.rowOffsets[p + 1]).reduce(UInt64(0)) { $0 + UInt64(store.counts[$1]) } }
                #expect(pix == expPix, "\(name) frames \(key): pixel totals")
            }
        }
    }

    /// The extremes the generator planted (registration 5.1): channel 0 and 4095, an empty pixel, 70000 events in one channel
    /// (a uint16 count would wrap), an unterminated last pixel.
    @Test func testC1PlantedExtremesAreInTheFilesAndInTheReading() throws {
        let one = try open(plantedPath("1stream-1frame"))
        let sums = one.sum(mask: nil)
        #expect(sums[0] == 2); #expect(sums[4095] == 3)
        #expect(one.windowSums([0..<4096])[0][1] == 0, "pixel 1 holds zero events")
        let three = try open(plantedPath("1stream-3frames"))
        #expect(three.sum(mask: nil)[2000] == 70_000)
        let px = try #require(three.image as? SparseSpectrumImage).densified().counts
        #expect(px[7 * 4096 + 2000] == 70_000, "70000 events in one pixel and channel do not wrap")
        // the unterminated stream: the last pixel's events are counted
        let u = draw(case: "unterminated")
        let img = try open(plantedPath("unterminated"))
        let imageSums: [UInt64] = img.sum(mask: nil)
        let imageTotal: UInt64 = imageSums.reduce(0, +)
        let cubeTotal: UInt64 = u.cube.reduce(0, +)
        #expect(imageTotal == cubeTotal)
        #expect(img.windowSums([0..<4096])[0].last! > 0, "the unterminated last pixel keeps its events")
    }

    // MARK: C2

    private func masks(ny: Int, nx: Int) -> [(String, PixelMask)] {
        var rect = PixelMask(repeating: false, count: ny * nx)
        var ellipse = rect, arbitrary = rect
        for y in 0..<ny { for x in 0..<nx {
            if x >= 1 && x < nx - 1 && y >= 1 && y < ny { rect[y * nx + x] = true }
            let cx = Double(nx - 1) / 2, cy = Double(ny - 1) / 2
            let dx = (Double(x) - cx) / (Double(nx) / 2), dy = (Double(y) - cy) / (Double(ny) / 2)
            if dx * dx + dy * dy <= 1 { ellipse[y * nx + x] = true }
            if (x * 7 + y * 3) % 3 == 0 { arbitrary[y * nx + x] = true }
        } }
        return [("rectangle", rect), ("ellipse", ellipse), ("arbitrary", arbitrary),
                ("empty", PixelMask(repeating: false, count: ny * nx)), ("full", PixelMask(repeating: true, count: ny * nx)),
                ("first pixel only", (0..<(ny * nx)).map { $0 == 0 }), ("last pixel only", (0..<(ny * nx)).map { $0 == ny * nx - 1 })]
    }

    /// C2: `sum(mask:)` (nil and five mask shapes), `windowSums` (overlapping, empty, single-channel ranges) and `densified`, from
    /// the sparse store and from the same cube held densely, equal sums of the draw, exactly.
    @Test func testC2SumsWindowSumsAndDensifiedEqualTheDraw() throws {
        let ranges: [Range<Int>] = [0..<4096, 0..<1, 4095..<4096, 100..<200, 150..<250, 200..<200, 2000..<2001, 1000..<3000]
        for name in plantedCases {
            let d = draw(case: name)
            let image = try open(plantedPath(name))
            let dense = DenseSpectrumImage(ny: d.ny, nx: d.nx, channels: d.channels, counts: d.cube.map { UInt32($0) })
            func expectedSum(_ mask: PixelMask?) -> [UInt64] {
                var out = [UInt64](repeating: 0, count: d.channels)
                for p in 0..<(d.ny * d.nx) where mask?[p] ?? true { for c in 0..<d.channels { out[c] += d.cube[p * d.channels + c] } }
                return out
            }
            var cases: [(String, PixelMask?)] = [("nil", nil)]
            cases += masks(ny: d.ny, nx: d.nx).map { ($0.0, Optional($0.1)) }
            for (mname, mask) in cases {
                let exp = expectedSum(mask)
                #expect(image.sum(mask: mask) == exp, "\(name) \(mname): sparse sum")
                #expect(dense.sum(mask: mask) == exp, "\(name) \(mname): dense sum")
            }
            let expW = ranges.map { r in (0..<(d.ny * d.nx)).map { p in r.reduce(UInt64(0)) { $0 + d.cube[p * d.channels + $1] } } }
            #expect(image.windowSums(ranges) == expW, "\(name): sparse windowSums")
            #expect(dense.windowSums(ranges) == expW, "\(name): dense windowSums")
            let sparse = try #require(image.image as? SparseSpectrumImage)
            #expect(sparse.densified().counts.map(UInt64.init) == d.cube, "\(name): densified")
        }
    }

    /// C2 window edges: ranges are half-open, so an event at the upper bound is outside and one at the lower bound inside.
    /// Events at channels 99, 100, 199, 200 in each of two pixels, in the sparse store and in the same cube held densely.
    @Test func testC2WindowEdgesAreHalfOpen() throws {
        let channels = 300
        let sparse = try SparseSpectrumImage(ny: 1, nx: 2, channels: channels, rowOffsets: [0, 4, 8],
                                             channelIndex: [99, 100, 199, 200, 99, 100, 199, 200], counts: [1, 10, 100, 1000, 2, 20, 200, 2000])
        var cube = [UInt32](repeating: 0, count: 2 * channels)
        for (k, c) in sparse.channelIndex.enumerated() { cube[(k / 4) * channels + Int(c)] = sparse.counts[k] }
        let dense = DenseSpectrumImage(ny: 1, nx: 2, channels: channels, counts: cube)
        let ranges: [Range<Int>] = [100..<200, 99..<100, 200..<201, 0..<300, 100..<100]
        let want: [[UInt64]] = [[110, 220], [1, 2], [1000, 2000], [1111, 2222], [0, 0]]
        #expect(sparse.windowSums(ranges) == want)
        #expect(dense.windowSums(ranges) == want)
        #expect(sparse.sum(mask: nil)[199] == 300)
    }

    /// C2: totals above 2^32 per channel stay exact (UInt64). pins.counts.big_pool: three pixels with 4e9, 4e9 and 4294967295
    /// counts in channel 100; the sum 12294967295 exceeds 2^32 and 2^53 is not approached.
    @Test func testC2TotalsAbove2Pow32AreExact() throws {
        let bp = countsPins.d("big_pool")
        let pc = (bp["pixel_counts"] as! [NSNumber]).map { UInt32($0.intValue) }
        var counts = [UInt32](repeating: 0, count: 3 * 128)
        for (p, c) in pc.enumerated() { counts[p * 128 + 100] = c }
        let img = DenseSpectrumImage(ny: 1, nx: 3, channels: 128, counts: counts)
        #expect(img.sum(mask: nil)[100] == UInt64(bp.i("sum")))
        #expect(img.sum(mask: nil)[100] > (UInt64(1) << 32))
        #expect(img.sum(mask: [true, true, false])[100] == UInt64(bp.i("mask_first_two")))
        #expect(img.sum(mask: [false, false, true])[100] == UInt64(bp.i("mask_last")))
        #expect(img.windowSums([100..<101])[0] == pc.map(UInt64.init))
        // the sparse store takes the same pool
        let sparse = try SparseSpectrumImage(ny: 1, nx: 3, channels: 128, rowOffsets: [0, 1, 2, 3],
                                             channelIndex: [100, 100, 100], counts: pc)
        #expect(sparse.sum(mask: nil)[100] == UInt64(bp.i("sum")))
        #expect(sparse.sum(mask: [false, true, true])[100] == (4_000_000_000 + 4_294_967_295))
        // `[Double]` conversion of the exact total is exact (< 2^53)
        #expect(Double(img.sum(mask: nil)[100]) == 12_294_967_295.0)
    }

    // MARK: C3

    /// C3 (stated, not a gate): exSpy's `sum` of unsigned 16-bit data is uint64 and does not wrap (131077 from two 65535 and more;
    /// live_time x navigation size, 2.0 -> 40.0, is exSpy's and is not carried). What is checked: SpectroKit's sum is UInt64
    /// and two 65535 do not wrap; the Velox LiveTime of 0 is passed through as stored, never multiplied.
    @Test func testC3NoWrapAndNoLiveTimeProduct() throws {
        let es = countsPins.d("exspy_sum")
        #expect(es.s("dtype") == "uint64")
        #expect(es.i("max") == 131_077)
        var counts = [UInt32](repeating: 0, count: 2 * 8)
        counts[3] = 65_535; counts[8 + 3] = 65_535
        let s = DenseSpectrumImage(ny: 1, nx: 2, channels: 8, counts: counts).sum(mask: nil)
        #expect(s[3] == 131_070)
        #expect(type(of: s[3]) == UInt64.self)
        let img = try open(plantedPath("1stream-1frame"))
        #expect(!img.metadata.detectors.isEmpty)
        for d in img.metadata.detectors { #expect((d.liveTime ?? 0) == 0, "LiveTime 0 stored, passed through as stored"); #expect((d.realTime ?? 0) == 0) }
    }
}

extension VeloxSpectrumImage {
    /// True when the streams of a multi-detector file ended in the same place (the reader's own flag; every stream since
    /// FormatoKit 0.0.3).
    var streamsAgreeOnCoverageForGate: Bool { eventStore.streamsAgreeOnCoverage }
}
