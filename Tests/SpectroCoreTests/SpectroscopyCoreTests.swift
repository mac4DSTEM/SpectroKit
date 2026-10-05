import XCTest
import DSTEMCore

/// v5.0 WP2 lane C: the spectral basics ported from eXSpy 7185a4d1 / HyperSpy 2.4.0.
/// Every expected number in `Fixtures/eds-pins-exspy-7185a4d1.json` was produced by RUNNING eXSpy
/// (generator: the lane's `gen/pins.py`), together with the two bundled spectra they were computed
/// from (EDS_TEM_FePt_nanoparticles, EDS_SEM_TM002; both GPL-3.0 eXSpy test data, 992 / 1024 channels).
/// Integer pins are compared exactly; the FWHM to float32 as pre-registered (C1), in fact to 1e-15.
final class SpectroscopyCoreTests: XCTestCase {

    // MARK: Fixture

    private struct Spectrum {
        let axis: EnergyAxis
        let resolution: Double
        let beam: Double
        let counts: [UInt64]
    }

    private static let pins: [String: Any] = {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/eds-pins-exspy-7185a4d1.json")
        // JSONDecoder, not JSONSerialization: the latter parses 17-digit doubles up to 1 ulp off
        // (found here: -0.042729661231195655 came back as ...565), which breaks exact window edges.
        let data = try! Data(contentsOf: url)
        return try! JSONDecoder().decode(JSONValue.self, from: data).any as! [String: Any]
    }()

    /// Numbers decode to `Double`, objects to `[String: Any]`, arrays to `[Any]`, null to `NSNull`.
    private enum JSONValue: Decodable {
        case num(Double), str(String), bool(Bool), arr([JSONValue]), obj([String: JSONValue]), null
        init(from d: Decoder) throws {
            let c = try d.singleValueContainer()
            if c.decodeNil() { self = .null }
            else if let v = try? c.decode(Bool.self) { self = .bool(v) }
            else if let v = try? c.decode(Double.self) { self = .num(v) }
            else if let v = try? c.decode(String.self) { self = .str(v) }
            else if let v = try? c.decode([JSONValue].self) { self = .arr(v) }
            else { self = .obj(try c.decode([String: JSONValue].self)) }
        }
        var any: Any {
            switch self {
            case .num(let v): return v
            case .str(let v): return v
            case .bool(let v): return v
            case .arr(let v): return v.map(\.any)
            case .obj(let v): return v.mapValues(\.any)
            case .null: return NSNull()
            }
        }
    }

    private func spectrum(_ name: String) -> Spectrum {
        let s = (Self.pins["spectra"] as! [String: Any])[name] as! [String: Any]
        let counts = (s["counts"] as! [Double]).map { UInt64($0) }
        return Spectrum(axis: EnergyAxis(offset: s["offset"] as! Double, scale: s["scale"] as! Double, size: counts.count),
                        resolution: s["resolutionMnKa"] as! Double, beam: s["beamEnergy"] as! Double, counts: counts)
    }

    private func pinCase(_ name: String) -> [String: Any] {
        (Self.pins["cases"] as! [[String: Any]]).first { $0["spectrum"] as? String == name }!
    }

    private func doubles(_ any: Any) -> [Double] { any as! [Double] }
    private func matrix(_ any: Any) -> [[Double]] { any as! [[Double]] }

    private func lines(_ names: [String], _ s: Spectrum) throws -> [SpectralLine] {
        try names.map { try SpectralLine(id: $0, resolutionMnKaEV: s.resolution) }
    }

    /// Net counts of `names` on `s` with the given background windows (nil = none).
    private func intensities(_ names: [String], _ s: Spectrum, integration: [[Double]]? = nil,
                             background: [[Double]]? = nil) throws -> [Double] {
        let ls = try lines(names, s)
        let iw = integration ?? WindowIntensity.integrationWindows(lines: ls)
        let resolved = try ls.indices.map { try WindowIntensity.resolve(integration: iw[$0], background: background?[$0], axis: s.axis) }
        return WindowIntensity.netCounts(spectrum: s.counts, windows: resolved)
    }

    // MARK: C1 — FWHM

    /// Pin: Al Kα at 130 eV = 0.07661266 keV (test_eds_sem.py:411-416), and 18 more (res, E) pairs run through eXSpy.
    /// Mutation: 2.5 -> 2.4 in `XRayLines.fwhm` -> red.
    func testFWHMLawMatchesExspy() throws {
        let alKa = try XCTUnwrap(XRayLines.line("Al_Ka")).energy
        XCTAssertEqual(try XCTUnwrap(XRayLines.fwhm(resolutionMnKaEV: 130, atEnergy: alKa)), 0.07661266, accuracy: 1e-8)
        XCTAssertEqual(try XCTUnwrap(XRayLines.fwhm(resolutionMnKaEV: 128, atEnergy: alKa)), 0.073167615787314, accuracy: 1e-14)
        for v in Self.pins["fwhm"] as! [[String: Double]] {
            let got = try XCTUnwrap(XRayLines.fwhm(resolutionMnKaEV: v["res"]!, atEnergy: v["E"]!))
            XCTAssertEqual(got, v["fwhm"]!, accuracy: 1e-15, "res \(v["res"]!) E \(v["E"]!)")
        }
    }

    // MARK: C1 — line table

    /// Mutation: parse the energy column from the weight column in `XRayLines.all` -> red.
    func testLineTableIsExspyVerbatim() throws {
        // test_eds.py:93-114 pins.
        XCTAssertEqual(XRayLines.line("Fe_Ka")?.energy, 6.4039)
        XCTAssertEqual(XRayLines.line("Fe_La")?.energy, 0.7045)
        XCTAssertEqual(XRayLines.line("Pt_Ka")?.energy, 66.8311)
        XCTAssertEqual(XRayLines.line("Pt_La")?.energy, 9.4421)
        XCTAssertEqual(XRayLines.line("Pt_Ma")?.energy, 2.0505)
        XCTAssertEqual(XRayLines.line("Pt_Mb")?.energy, 2.1276)
        XCTAssertEqual(try XCTUnwrap(XRayLines.line("Pt_Mb")).weight, 0.59443)
        XCTAssertEqual(XRayLines.line("Mn_Ka")?.energy, XRayLines.mnKaEnergy)
        XCTAssertEqual(XRayLines.line("Pt_M2N4")?.family, .M)
        XCTAssertEqual(XRayLines.line("Pt_Lb1")?.family, .L)
        XCTAssertEqual(XRayLines.line("Fe_Kb")?.family, .K)
        // 947 rows for Z = 1...92 (H and He included as shipped; Li carries none; Np, Pu, Am are beyond Z = 92 and none).
        XCTAssertEqual(XRayLines.all.count, 947)
        XCTAssertEqual(XRayLines.all.map(\.atomicNumber).max(), 92)
        XCTAssertEqual(XRayLines.line("U_Ma")?.atomicNumber, 92)
        // DEVIATION: H and He are shipped by eXSpy but are not X-ray lines.
        XCTAssertNotNil(XRayLines.line("H_Ka"))
        XCTAssertTrue(XRayLines.lines(of: "H").isEmpty)
        XCTAssertTrue(XRayLines.lines(of: "He").isEmpty)
        XCTAssertTrue(XRayLines.lines(of: "Li").isEmpty)
        XCTAssertEqual(XRayLines.lines(of: "Fe").map(\.name), ["Ka", "Kb", "La", "Lb3", "Ll", "Ln"])
    }

    /// The default line per element (`add_lines()`), against eXSpy on both axes and four beam energies.
    /// Mutation: `<` -> `<=`-free swap of `beam / 2` to `beam` in `defaultLines` -> red (Cu picks Ka at 10 keV).
    func testDefaultLineChoiceMatchesExspy() {
        let fept = spectrum("EDS_TEM_FePt_nanoparticles")
        for v in Self.pins["selection"] as! [[String: Any]] {
            let beam = v["beam"] as! Double
            let els = v["elements"] as! [String]
            XCTAssertEqual(XRayLines.defaultLines(elements: els, axis: fept.axis, beamEnergy: beam), v["only_one_a"] as! [String],
                           "only_one \(els) @\(beam)")
            XCTAssertEqual(XRayLines.defaultLines(elements: els, axis: fept.axis, beamEnergy: beam, onlyOne: false, onlyLines: nil),
                           v["all"] as! [String], "all \(els) @\(beam)")
        }
    }

    // MARK: C1 — the axis

    /// hyperspy `value2index` incl. ties, negatives and out-of-axis values (544 vectors run through hyperspy 2.4.0).
    /// Mutation: round half up (`rounded(.toNearestOrAwayFromZero)` for the non-negative branch) -> red on a tie.
    func testValue2IndexMatchesHyperspy() {
        let vecs = Self.pins["value2index"] as! [[String: Any]]
        var ties = 0, outside = 0
        for v in vecs {
            let axis = EnergyAxis(offset: v["offset"] as! Double, scale: v["scale"] as! Double,
                                  size: Int(v["size"] as! Double))
            let value = v["value"] as! Double
            let expect = (v["index"] as? Double).map { Int($0) }
            let got = try? axis.index(of: value)
            XCTAssertEqual(got, expect, "offset \(axis.offset) scale \(axis.scale) value \(value)")
            if expect == nil { outside += 1 }
            let frac = ((value - axis.offset) / axis.scale).truncatingRemainder(dividingBy: 1)
            if abs(abs(frac) - 0.5) < 1e-9 { ties += 1 }
        }
        XCTAssertGreaterThan(ties, 20, "the vector set must contain tie cases")
        XCTAssertGreaterThan(outside, 8)
    }

    func testSliceSemanticsMatchHyperspy() {
        let axis = EnergyAxis(offset: -0.2, scale: 0.01, size: 1000)
        for v in Self.pins["slices"] as! [[String: Any]] {
            let a = v["start"] as! Double, b = v["stop"] as! Double
            let got = try? axis.channelRange(from: a, to: b)
            if let expect = v["slice"] as? [Any] {
                // None (clamp) is NSNull; a reversed pair is an empty Python slice
                let lo = (expect[0] as? Double).map { Int($0) } ?? 0, hi = (expect[1] as? Double).map { Int($0) } ?? axis.size
                let py = lo <= hi ? lo..<hi : lo..<lo
                XCTAssertEqual(got, py, "\(a):\(b)")
            } else {
                XCTAssertNil(got, "\(a):\(b) must throw like hyperspy's IndexError")
            }
        }
    }

    // MARK: C1 — window intensities

    /// Pins: FePt Fe_Ka 3710, Pt_La 15872 (test_eds_tem.py:628-634); with background windows at line_width [5, 2]
    /// 2754 / 15090 (_eds.py:818-824); channel ranges [304,318) and [455,471).
    /// Mutation: round the window edge half up instead of towards zero, or scale = (i5-i4)/(i1-i0) -> red.
    func testFePtPins() throws {
        let s = spectrum("EDS_TEM_FePt_nanoparticles")
        let names = ["Fe_Ka", "Pt_La"]
        XCTAssertEqual(try intensities(names, s), [3710, 15872])
        let ls = try lines(names, s)
        let iw = WindowIntensity.integrationWindows(lines: ls)
        XCTAssertEqual(try WindowIntensity.resolve(integration: iw[0], background: nil, axis: s.axis).signal, 304..<318)
        XCTAssertEqual(try WindowIntensity.resolve(integration: iw[1], background: nil, axis: s.axis).signal, 455..<471)
        let bw52 = BackgroundWindows.estimate(lines: ls, lineWidth: [5, 2])
        XCTAssertEqual(try intensities(names, s, background: bw52), [2754, 15090])
        // and the whole fixture: integration windows, merged windows, default widths
        let c = pinCase("EDS_TEM_FePt_nanoparticles")
        XCTAssertEqual(iw, matrix(c["integrationWindows"]!))
        XCTAssertEqual(bw52, matrix((c["bg_5_2"] as! [String: Any])["windows"]!))
        XCTAssertEqual(try intensities(names, s, background: BackgroundWindows.estimate(lines: ls)),
                       doubles((c["bg_2_2"] as! [String: Any])["net"]!))
    }

    /// Pins: TM002 default intensities [84163, 89063, 96117, 96700, 99075] (test_eds_sem.py:346-351); background-subtracted
    /// values WITH the overlap merge at [2,2] and [5,2] (they differ from a merge-free run: 63805 vs 63831 for Al_Ka at [2,2]);
    /// Mn_Ka 2.1 FWHM window 53597 and Mn-only background-subtracted 46716 (_eds.py:619-631).
    /// Mutation: skip `BackgroundWindows.merge` -> red (Al_Ka 63805).
    func testTM002Pins() throws {
        let s = spectrum("EDS_SEM_TM002")
        let c = pinCase("EDS_SEM_TM002")
        let names = c["lines"] as! [String]
        XCTAssertEqual(names, ["Al_Ka", "C_Ka", "Cu_La", "Mn_La", "Zr_La"])
        XCTAssertEqual(XRayLines.defaultLines(elements: ["Al", "C", "Cu", "Mn", "Zr"], axis: s.axis, beamEnergy: s.beam), names)
        XCTAssertEqual(try intensities(names, s), [84163, 89063, 96117, 96700, 99075])
        XCTAssertEqual(try intensities(names, s), doubles(c["defaultIntensity"]!))
        let ls = try lines(names, s)
        XCTAssertEqual(WindowIntensity.integrationWindows(lines: ls), matrix(c["integrationWindows"]!))
        XCTAssertEqual(doubles(c["fwhm"]!), ls.map(\.fwhm))
        for key in ["bg_2_2", "bg_5_2"] {
            let d = c[key] as! [String: Any]
            let lw: [Double] = key == "bg_2_2" ? [2, 2] : [5, 2]
            let bw = BackgroundWindows.estimate(lines: ls, lineWidth: lw)
            XCTAssertEqual(bw, matrix(d["windows"]!), key)
            let net = try intensities(names, s, background: bw)
            XCTAssertEqual(net, doubles(d["net"]!), key)
        }
        // Mn_Ka alone
        let mn = [try SpectralLine(id: "Mn_Ka", resolutionMnKaEV: s.resolution)]
        let wide = WindowIntensity.integrationWindows(lines: mn, windowsWidth: 2.1)
        let r = try WindowIntensity.resolve(integration: wide[0], background: nil, axis: s.axis)
        XCTAssertEqual(WindowIntensity.netCounts(spectrum: s.counts, windows: [r]), [53597])
        let bw = BackgroundWindows.estimate(lines: mn)
        let r2 = try WindowIntensity.resolve(integration: WindowIntensity.integrationWindows(lines: mn)[0], background: bw[0], axis: s.axis)
        XCTAssertEqual(WindowIntensity.netCounts(spectrum: s.counts, windows: [r2]), [46716])
        XCTAssertEqual(WindowIntensity.netCounts(spectrum: s.counts, windows: [try WindowIntensity.resolve(
            integration: WindowIntensity.integrationWindows(lines: mn)[0], background: nil, axis: s.axis)]), [52773])
    }

    /// A window outside the axis: with a background eXSpy's value2index raises, so does this; without one it clamps.
    func testWindowOutsideAxis() throws {
        let axis = EnergyAxis(offset: 0, scale: 0.01, size: 100)   // 0 ... 0.99 keV
        XCTAssertThrowsError(try WindowIntensity.resolve(integration: [0.5, 0.6], background: [0.1, 0.2, 1.5, 1.6], axis: axis))
        XCTAssertEqual(try WindowIntensity.resolve(integration: [0.9, 1.5], background: nil, axis: axis).signal, 90..<100)
        XCTAssertThrowsError(try WindowIntensity.resolve(integration: [1.5, 1.6], background: nil, axis: axis))
    }

    // MARK: C2 — sparse vs dense

    private struct LCG {
        var s: UInt64
        mutating func next() -> UInt64 { s = s &* 6364136223846793005 &+ 1442695040888963407; return s >> 33 }
    }

    private func randomSparse(ny: Int, nx: Int, channels: Int, seed: UInt64, density: Int = 12) throws -> SparseSpectrumImage {
        var g = LCG(s: seed)
        var offsets = [0], idx: [UInt16] = [], cnt: [UInt32] = []
        for _ in 0..<(ny * nx) {
            var c = 0
            while true {
                c += Int(g.next() % UInt64(2 * density)) + 1
                if c >= channels { break }
                idx.append(UInt16(c)); cnt.append(UInt32(g.next() % 7) + 1)
            }
            offsets.append(idx.count)
        }
        return try SparseSpectrumImage(ny: ny, nx: nx, channels: channels, rowOffsets: offsets, channelIndex: idx, counts: cnt)
    }

    /// Window maps (incl. background-subtracted) from the sparse image equal those of the densified one bit for bit,
    /// and equal a naive per-pixel reference. Mutation: in `SparseSpectrumImage.windowSums` use `c <= his[r]` -> red.
    func testSparseAndDenseWindowMapsAreBitIdentical() throws {
        let sparse = try randomSparse(ny: 9, nx: 11, channels: 400, seed: 42)
        XCTAssertGreaterThan(sparse.counts.count, 500)
        let dense = sparse.densified()
        let axis = EnergyAxis(offset: -0.1, scale: 0.01, size: 400)   // channel c = c*0.01 - 0.1 keV
        let ls = [SpectralLine(id: "A", energy: 0.8, fwhm: 0.12), SpectralLine(id: "B", energy: 1.4, fwhm: 0.15),
                  SpectralLine(id: "C", energy: 1.55, fwhm: 0.15), SpectralLine(id: "D", energy: 3.0, fwhm: 0.2)]
        let bw = BackgroundWindows.estimate(lines: ls, lineWidth: [5, 2])
        let iw = WindowIntensity.integrationWindows(lines: ls)
        let resolved = try ls.indices.map { try WindowIntensity.resolve(integration: iw[$0], background: bw[$0], axis: axis) }
        XCTAssertTrue(bw[0][0] == bw[1][0] && bw[1][0] == bw[2][0], "sanity: lines A, B, C overlap in a chain, so the merge gave them one left window")
        let a = WindowIntensity.maps(image: sparse, windows: resolved)
        let b = WindowIntensity.maps(image: dense, windows: resolved)
        XCTAssertEqual(a.map { $0.map(\.bitPattern) }, b.map { $0.map(\.bitPattern) })
        XCTAssertEqual(sparse.sum(mask: nil), dense.sum(mask: nil))
        var mask = [Bool](repeating: false, count: 99)
        for p in stride(from: 3, to: 99, by: 4) { mask[p] = true }
        XCTAssertEqual(sparse.sum(mask: mask), dense.sum(mask: mask))
        XCTAssertEqual(sparse.sum(mask: mask).reduce(0, +) < sparse.sum(mask: nil).reduce(0, +), true)
        // naive reference, pixel by pixel, from the dense cube and the spectrum-level routine
        for p in 0..<99 {
            let spec = (0..<400).map { UInt64(dense.counts[p * 400 + $0]) }
            let ref = WindowIntensity.netCounts(spectrum: spec, windows: resolved)
            for w in 0..<ls.count { XCTAssertEqual(a[w][p].bitPattern, ref[w].bitPattern, "pixel \(p) window \(w)") }
        }
        // windows without background too
        let plain = try ls.indices.map { try WindowIntensity.resolve(integration: iw[$0], background: nil, axis: axis) }
        XCTAssertEqual(WindowIntensity.maps(image: sparse, windows: plain), WindowIntensity.maps(image: dense, windows: plain))
    }

    /// The real spectra as a 2 x 2 image (the same spectrum in every pixel): each pixel's map value is the spectrum's pin,
    /// and the summed spectrum of the whole image is 4x the spectrum.
    func testPerPixelMapOfAKnownSpectrumReproducesThePins() throws {
        let s = spectrum("EDS_TEM_FePt_nanoparticles")
        var rows = [0], idx: [UInt16] = [], cnt: [UInt32] = []
        for _ in 0..<4 {
            for (c, v) in s.counts.enumerated() where v > 0 { idx.append(UInt16(c)); cnt.append(UInt32(v)) }
            rows.append(idx.count)
        }
        let img = try SparseSpectrumImage(ny: 2, nx: 2, channels: s.counts.count, rowOffsets: rows, channelIndex: idx, counts: cnt)
        let ls = try lines(["Fe_Ka", "Pt_La"], s)
        let bw = BackgroundWindows.estimate(lines: ls, lineWidth: [5, 2])
        let iw = WindowIntensity.integrationWindows(lines: ls)
        let res = try ls.indices.map { try WindowIntensity.resolve(integration: iw[$0], background: bw[$0], axis: s.axis) }
        let m = WindowIntensity.maps(image: img, windows: res)
        XCTAssertEqual(m[0], [2754, 2754, 2754, 2754])
        XCTAssertEqual(m[1], [15090, 15090, 15090, 15090])
        XCTAssertEqual(img.sum(mask: nil), s.counts.map { $0 * 4 })
        XCTAssertEqual(img.sum(mask: [true, false, false, true]), s.counts.map { $0 * 2 })
    }

    // MARK: Review additions (Gate B round 1)

    /// S3. C Kα (0.2774 keV) at 110 eV: 2.5 (E - 5.8987) 1000 + 110² < 0, eXSpy's math.sqrt raises ValueError.
    /// Mutation: drop the `guard fwhmE >= 0` in `XRayLines.fwhm` -> NaN, red.
    func testWidthLawUndefinedIsNilNotNaN() {
        XCTAssertNil(XRayLines.fwhm(resolutionMnKaEV: 110, atEnergy: 0.2774))
        XCTAssertNotNil(XRayLines.fwhm(resolutionMnKaEV: 130, atEnergy: 0.2774))
        XCTAssertThrowsError(try SpectralLine(id: "C_Ka", resolutionMnKaEV: 110)) {
            XCTAssertEqual($0 as? SpectralLineError, .widthUndefined("C_Ka", resolutionMnKaEV: 110))
        }
        XCTAssertThrowsError(try SpectralLine(id: "Xx_Ka", resolutionMnKaEV: 130)) {
            XCTAssertEqual($0 as? SpectralLineError, .unknownLine("Xx_Ka"))
        }
    }

    /// S2. Mutation: drop the strict-ascent check (`c > previous` -> `c >= previous`) -> the duplicate case goes red.
    func testCSRContractIsValidated() throws {
        func make(_ idx: [UInt16], channels: Int = 10, offsets: [Int] = [0, 3]) throws -> SparseSpectrumImage {
            try SparseSpectrumImage(ny: 1, nx: 1, channels: channels, rowOffsets: offsets, channelIndex: idx, counts: idx.map { _ in 1 })
        }
        XCTAssertNoThrow(try make([1, 4, 9]))
        XCTAssertThrowsError(try make([4, 1, 9])) { XCTAssertEqual($0 as? CSRSpectrumError, .channelsNotAscending(pixel: 0, channel: 1)) }
        XCTAssertThrowsError(try make([1, 4, 4])) { XCTAssertEqual($0 as? CSRSpectrumError, .channelsNotAscending(pixel: 0, channel: 4)) }
        XCTAssertThrowsError(try make([1, 4, 10])) { XCTAssertEqual($0 as? CSRSpectrumError, .channelOutOfRange(pixel: 0, channel: 10)) }
        XCTAssertThrowsError(try make([1, 4, 9], offsets: [0, 2])) { XCTAssertEqual($0 as? CSRSpectrumError, .arraysDisagree) }
        XCTAssertThrowsError(try make([1, 4, 9], offsets: [0, 3, 3])) { XCTAssertEqual($0 as? CSRSpectrumError, .rowOffsetCount(expected: 2, got: 3)) }
        // two pixels whose offsets decrease
        XCTAssertThrowsError(try SparseSpectrumImage(ny: 1, nx: 2, channels: 10, rowOffsets: [0, 3, 2], channelIndex: [1, 2], counts: [1, 1])) {
            XCTAssertEqual($0 as? CSRSpectrumError, .offsetsDecrease(pixel: 0))
        }
    }

    /// N1: an empty `only_lines` is no filter in eXSpy (`if only_lines and ...`). Mutation: drop `!only.isEmpty` -> red.
    func testEmptyOnlyLinesIsNoFilter() {
        let tm = spectrum("EDS_SEM_TM002")
        let all = XRayLines.defaultLines(elements: ["Cu"], axis: tm.axis, beamEnergy: 30, onlyOne: false, onlyLines: nil)
        XCTAssertEqual(XRayLines.defaultLines(elements: ["Cu"], axis: tm.axis, beamEnergy: 30, onlyOne: false, onlyLines: []), all)
        XCTAssertGreaterThan(all.count, 3)
    }

    /// N2: DEVIATION 1 exercised. eXSpy returns H_Ka on the TM002 axis; this port returns no H / He line.
    /// Mutation: remove the H/He filter in `lines(of:)` -> red.
    func testHeliumAndHydrogenAreDroppedWhereExspyKeepsThem() {
        let tm = spectrum("EDS_SEM_TM002")
        XCTAssertEqual(Self.pins["hHeExspy"] as? [String], ["H_Ka", "He_Ka"], "what eXSpy returns, run")
        XCTAssertEqual(XRayLines.defaultLines(elements: ["H", "He"], axis: tm.axis, beamEnergy: tm.beam, onlyOne: false, onlyLines: nil), [])
    }

    // MARK: S1 — background-window conflicts

    private func conflictFixture(_ axis: EnergyAxis, _ names: [String], res: Double = 130) throws -> (lines: [SpectralLine], bw: [[Double]], c: [[WindowConflict]]) {
        let ls = try names.map { try SpectralLine(id: $0, resolutionMnKaEV: res) }
        let bw = BackgroundWindows.estimate(lines: ls)
        let cands = WindowIntensity.candidateLines(elements: ["Mg", "Al", "Si", "Fe", "Pt"], resolutionMnKaEV: res, axis: axis)
        return (ls, bw, WindowIntensity.conflicts(lines: ls, background: bw, candidates: cands))
    }

    /// Mg/Al/Si on a synthetic 10 eV axis: the merge chains Mg's right window to Al's, which lies on Si Kα's low flank
    /// (and on Al Kβ 1.5596 keV, an Al sub-line, for Mg too). Mutation: `c.energy - flank` -> `c.energy + flank`
    /// in `conflicts` -> Mg loses the Si flank, red.
    func testMgAlSiMergedBackgroundSitsOnSiliconsFlank() throws {
        let axis = EnergyAxis(offset: 0, scale: 0.01, size: 1000)
        let f = try conflictFixture(axis, ["Mg_Ka", "Al_Ka", "Si_Ka"])
        // the merge, by hand: Mg takes Al's own right window (1.640-1.716 keV), then Al and Si are rewritten with Si's
        let unmerged = try ["Al_Ka", "Si_Ka"].map { try SpectralLine(id: $0, resolutionMnKaEV: 130) }
        let own = BackgroundWindows.estimate(lines: [unmerged[0]])[0]
        XCTAssertEqual(Array(f.bw[0][2...3]), Array(own[2...3]), "Mg takes Al's right window")
        XCTAssertEqual(f.bw[1], f.bw[2], "Al and Si carry one pair of windows, ~0.8 keV apart")
        let mg = f.c[0]
        let si = try XCTUnwrap(mg.first { $0.other == "Si_Ka" }, "Mg's background must report Si Kα")
        XCTAssertEqual(si.side, .right)
        XCTAssertTrue(si.overlap.lowerBound >= 1.6 && si.overlap.upperBound <= 1.72, "\(si.overlap)")
        XCTAssertTrue(si.reachesIntegrationWindow, "Mg's right window ends inside Si Kα's integration window (1.659-1.820 keV)")
        XCTAssertTrue(mg.contains { $0.other == "Al_Kb" }, "sub-line Al Kb 1.5596 keV")
        XCTAssertTrue(mg.contains { $0.other == "Al_Ka" }, "Mg's chained right window reaches Al Ka's own window or flank")
        XCTAssertFalse(mg.contains { $0.other == "Mg_Ka" })
        // Al and Si: left window shared with Mg, right window Si's: both ~0.8 keV from the peaks
        XCTAssertEqual(f.bw[1][0], f.bw[0][0])
        // nothing in a clean case: Fe Kα alone on the FePt axis
        let fe = spectrum("EDS_TEM_FePt_nanoparticles")
        let g = try conflictFixture(fe.axis, ["Fe_Ka"], res: fe.resolution)
        XCTAssertEqual(g.c[0].map(\.other), ["Fe_Kb"], "Fe Kα on FePt: only its own Kβ (7.058 keV) flank lies in the right window")
        // Fe + Pt together on the FePt axis: no overlap between their windows either (6.4 vs 9.4 keV)
        let h = try conflictFixture(fe.axis, ["Fe_Ka", "Pt_La"], res: fe.resolution)
        XCTAssertEqual(h.c.map { $0.map(\.other) }, [["Fe_Kb"], ["Pt_Ln"]], "own sub-lines only (Pt Ln 9.977 keV)")
        // counts are untouched: the same windows give eXSpy's counts (parity pin, FePt)
        XCTAssertEqual(try intensities(["Fe_Ka", "Pt_La"], fe, background: BackgroundWindows.estimate(
            lines: try lines(["Fe_Ka", "Pt_La"], fe), lineWidth: [5, 2])), [2754, 15090])
    }
}
