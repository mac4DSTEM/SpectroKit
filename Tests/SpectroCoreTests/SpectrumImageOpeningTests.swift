// SpectroKit S1 test partition (ADR 064 section 3.3): the methods of SpectrumImageOpeningTests that move with the EDX core;
// the rest stay in SpectrumImageOpeningTests.swift. Helpers are duplicated, not shared, across the split.
import Foundation
import Testing
import SpectroTestSupport
import CoreGraphics
@testable import SpectroCore
import SpectroEDX
import FormatoDM
import FormatoEMD

/// v5.0 WP2 lane R2: from a file to a spectrum image in the room. Fixtures: `demo-edx-tiny.dm4` (6 x 4 scan, 512 channels,
/// truth beside it) and `velox-tiny.emd` (3 rows x 2 columns, 8 channels, 2 frames: the main file of
/// `tools/velox-parity/make-tiny-fixture.py`, the same bytes VeloxEMDReaderTests embeds). Each test names its mutation.
@MainActor
struct SpectrumImageOpeningTests {

    private static let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")
    private static var dm4: String { dir.appendingPathComponent("demo-edx-tiny.dm4").path }
    private static var velox: String { dir.appendingPathComponent("velox-tiny.emd").path }
    private static var h5: String { dir.appendingPathComponent("qshape3.mac4dstem.h5").path }

    private func truth() throws -> [String: Any] {
        let data = try Data(contentsOf: Self.dir.appendingPathComponent("demo-edx-tiny.truth.json"))
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: DM4 EDS decode

    /// The decoded cube against the truth, per recipe: the realised EDS counts the generator wrote for each recipe's
    /// pixels equal the sum of the decoded counts over that recipe's pixels in the map. nx = 6 != ny = 4, so a swapped
    /// pair of axes reads another recipe's pixels.
    /// Mutation: `nx`/`ny` swapped in `decodeEDS` (`dimensions[1], dimensions[0]`) — red.
    @Test func testTheDM4EDSDecodeMatchesTheTruthPerRecipe() throws {
        let t = try truth()
        let map = try #require(t["recipe_map"] as? [[Int]])
        let names = try #require(t["recipe_names_in_map_order"] as? [String])
        let recipes = try #require(t["recipes"] as? [String: [String: Any]])
        let image = try #require(try SpectrumImageOpener.openGMSEDS(path: Self.dm4))
        #expect([image.nx, image.ny, image.channels] as [Int] == [6, 4, 512])
        for (i, name) in names.enumerated() {
            var mask = PixelMask(repeating: false, count: 24)
            for y in 0..<4 { for x in 0..<6 where map[y][x] == i { mask[y * 6 + x] = true } }
            let expected = try #require(recipes[name]?["realised_total_eds_counts"] as? Int)
            #expect(image.sum(mask: mask).reduce(0, +) == UInt64(expected), "recipe \(name)")
        }
    }

    /// The layout itself, read independently: memory order (channel, y, x), x fastest, against the (y, x, channel) result.
    /// Mutation: the plane stride `j * np` in `scatterEDS` replaced by `j * nch` — red.
    @Test func testTheDM4EDSBlobIsTransposedFromEnergySlowest() throws {
        let objects = try DM4Experiment.list(path: Self.dm4)
        let eds = try #require(objects.first { $0.role == .eds })
        let d = try DM4Experiment.readEDSSpectrumImage(path: Self.dm4, index: eds.index)
        let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: Self.dm4))
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(eds.dataOffset))
        let raw = try #require(try handle.read(upToCount: eds.dataByteCount))
        let counts: [UInt32] = raw.withUnsafeBytes { Array($0.bindMemory(to: UInt32.self)) }
        for ch in [0, 1, 100, 511] { for y in 0..<4 { for x in 0..<6 {
            #expect(d.counts[(y * 6 + x) * 512 + ch] == counts[(ch * 4 + y) * 6 + x], "ch \(ch) y \(y) x \(x)")
        } } }
        #expect(eds.dataOrderSwapped == nil, "the simulator does not write the tag on the EDS object")
    }

    /// The axis the room shows is the FILE's (the perturbed one, truth `edx.axis_file`), never the generator's true axis:
    /// E(i) = (i - origin) * scale with the origin and dispersion as stored (float32, so 1e-5 keV). Elevation is the truth's.
    /// Mutation: the offset sign flipped (`offsetKeV = d.energyAxis.origin * …`) — red.
    @Test func testTheDM4EnergyAxisAndMetadataAreTheFiles() throws {
        let t = try truth()
        let edx = try #require(t["edx"] as? [String: Any])
        let file = try #require(edx["axis_file"] as? [String: Double])
        let offsetKeV = try #require(file["offset_keV"]), dispersionEV = try #require(file["dispersion_eV"])
        let elevation = try #require(((t["forward_model"] as? [String: Any])?["absorption"] as? [String: Any])?["elevation_deg"] as? Double)
        let image = try #require(try SpectrumImageOpener.openGMSEDS(path: Self.dm4))
        #expect(isEqual(image.energyAxis.offset, offsetKeV, accuracy: 1e-5))
        #expect(isEqual(image.energyAxis.scale, dispersionEV / 1000, accuracy: 1e-6))
        #expect(isEqual(image.energyAxis.energy(ofChannel: 24), offsetKeV + 24 * dispersionEV / 1000, accuracy: 1e-5))
        let m = image.metadata
        #expect(isEqual(m.energyOffsetEV, offsetKeV * 1000, accuracy: 1e-2))
        #expect(isEqual(m.energyDispersionEV, dispersionEV, accuracy: 1e-3))
        #expect(m.origin == .gmsDM4)
        #expect(m.scanPixelSize == 5)
        #expect(m.scanPixelUnit == "nm")
        #expect(m.detectors.first?.elevationDegrees == elevation)
        #expect(image.scanImage?.count == 24, "the scan-grid HAADF of the same run sits on the EDS grid")
        #expect(!m.sameScanAsCube, "no cube was named")
    }

    /// Only an EDS object is decoded, and a missing one is named.
    /// Mutation: the role guard in `decodeEDS` removed — red (the 4D object would be read as a 3D cube).
    @Test func testOnlyAnEDSObjectDecodes() throws {
        let objects = try DM4Experiment.list(path: Self.dm4)
        let diffraction = try #require(objects.first { $0.role == .diffraction })
        if let error = #expect(throws: (any Error).self, performing: { try DM4Experiment.readEDSSpectrumImage(path: Self.dm4, index: diffraction.index) }) {
            #expect(error.localizedDescription.contains("is not an EDS spectrum image"), "\(error.localizedDescription)")
        }
        if let error = #expect(throws: (any Error).self, performing: { try DM4Experiment.readEDSSpectrumImage(path: Self.dm4, index: 99) }) {
            #expect(error.localizedDescription.contains("no image object 99"), "\(error.localizedDescription)")
        }
    }

    // MARK: Velox join

    /// The store joined to Core's sparse image gives the sums a densified reference gives, windows and masks included.
    /// Mutation: `windowSums` of `SparseSpectrumImage` using `<=` on the upper bound — red.
    @Test func testTheVeloxStoreJoinsTheSparseImageAndSumsEqualADensifiedReference() throws {
        let store = try VeloxEMDReader(path: Self.velox).readSpectrumImage().eventStore
        let sparse = try SparseSpectrumImage(store)
        let dense = DenseSpectrumImage(ny: store.ny, nx: store.nx, channels: store.channels, counts: store.denseCounts())
        #expect([sparse.ny, sparse.nx, sparse.channels] as [Int] == [3, 2, 8])
        #expect(sparse.sum(mask: nil) == dense.sum(mask: nil))
        #expect(sparse.sum(mask: nil) == store.summedSpectrum())
        let mask: PixelMask = [true, false, true, true, false, false]
        #expect(sparse.sum(mask: mask) == dense.sum(mask: mask))
        let ranges = [0..<3, 2..<8, 7..<8, 4..<4, 1..<2]
        #expect(sparse.windowSums(ranges) == dense.windowSums(ranges))
        #expect(store.totalCounts == Int(sparse.sum(mask: nil).reduce(0, +)))
    }

    /// The opener's axis is the stream's, in keV, and the metadata the room shows is what the file stores.
    /// Mutation: `scaleKeV` doubled in `openVelox` — red.
    @Test func testTheVeloxOpenerCarriesTheFilesAxisAndMetadata() throws {
        let v = try VeloxEMDReader(path: Self.velox).readSpectrumImage()
        let image = try SpectrumImageOpener.openVelox(path: Self.velox)
        let axis = try #require(v.metadata.energyAxis)
        #expect(isEqual(image.energyAxis.offset, axis.offsetKeV, accuracy: 1e-12))
        #expect(isEqual(image.energyAxis.scale, axis.scaleKeV, accuracy: 1e-12))
        #expect(isEqual(image.metadata.energyDispersionEV, axis.scaleKeV * 1000, accuracy: 1e-9))
        #expect([image.ny, image.nx, image.channels] as [Int] == [3, 2, 8], "a non-square grid: 3 rows, 2 columns")
        #expect(image.metadata.origin == .veloxEMD)
        #expect(image.metadata.frames == 2)
        #expect(image.scanImage?.count == 6)
        #expect(!image.metadata.detectors.isEmpty)
        #expect(image.metadata.beamEnergyKeV == 200)
        #expect(image.sum(mask: nil) == v.eventStore.summedSpectrum())
    }

    // MARK: Routing

    /// What each file is. A Velox EMD is a spectrum image; a GMS file with a cube is not (it opens as a cube); neither is
    /// an HDF5 that is not Velox, nor a file merely NAMED .emd.
    /// Mutation: `kind` answering `.veloxSpectrumImage` for every .emd without asking `isVeloxEMD` — red.
    @Test func testTheRouterTellsASpectrumImageFromACube() throws {
        #expect(SpectrumImageOpener.kind(ofFileAt: Self.velox) == .veloxSpectrumImage)
        #expect(SpectrumImageOpener.kind(ofFileAt: Self.dm4) == .other, "it has a Diffraction SI: a cube opens, its EDS is attached after")
        #expect(SpectrumImageOpener.kind(ofFileAt: Self.h5) == .other)
        let fake = NSTemporaryDirectory() + "not-velox-\(UUID().uuidString).emd"
        try Data("not hdf5".utf8).write(to: URL(fileURLWithPath: fake))
        defer { try? FileManager.default.removeItem(atPath: fake) }
        #expect(SpectrumImageOpener.kind(ofFileAt: fake) == .other)
    }

    /// An ellipse keeps the pixels whose centres are inside it: 12 of a 4 x 4 box, the four corners out.
    /// Mutation: `<= 1` replaced by `<= 1.5` in `SpectrumRegionShape.mask` — red.
    @Test func testAnEllipseKeepsThePixelsWhoseCentresAreInside() {
        let mask = SpectrumRegionShape.ellipse(PixelRect(x0: 0, y0: 0, x1: 4, y1: 4)).mask(nx: 4, ny: 4)
        #expect(mask.filter { $0 }.count == 12)
        #expect(!(mask[0])); #expect(!(mask[3])); #expect(!(mask[12])); #expect(!(mask[15]))
    }

    /// net = G - s B and sigma^2 = G + s^2 B, from the window's own sums (counting statistics, independent Poisson counts).
    /// Mutation: the variance `G + s²B` written `G + s·B` — red.
    @Test func testNetCountsAndSigmaFollowThePoissonFormula() throws {
        // A window of known geometry whose scale is NOT 1 (eXSpy's windows are symmetric, so a real one has scale 1 and cannot
        // tell s from s^2): signal 10 channels, two background windows of 8 and 17 channels, scale 0.4.
        let window = ResolvedWindow(signal: 10..<20, background: .init(left: 2..<10, right: 30..<47, scale: 0.4))
        let lw = LineWindow(element: "Al", id: "Al_Ka", energy: 1.4865, fwhm: 0.07, window: window, failure: nil, conflicts: [])
        var spectrum = [UInt64](repeating: 0, count: 100)
        for c in 10..<20 { spectrum[c] = 7 }
        for c in 2..<10 { spectrum[c] = 3 }
        for c in 30..<47 { spectrum[c] = 5 }
        let g = 70.0, b = 3.0 * 8 + 5.0 * 17
        let c = try #require(ElementWindows.netCounts(spectrum: spectrum, windows: [lw]).first ?? nil)
        #expect(isEqual(c.net, g - 0.4 * b, accuracy: 1e-9))
        #expect(isEqual(c.sigma, (g + 0.4 * 0.4 * b).squareRoot(), accuracy: 1e-9))
        #expect(c.signal == 70); #expect(c.background == UInt64(b))
        // The same net count the per-pixel maps use, for a one-pixel image of this spectrum.
        let image = DenseSpectrumImage(ny: 1, nx: 1, channels: 100, counts: spectrum.map { UInt32($0) })
        #expect(isEqual(try #require(ElementWindows.maps(image: image, windows: [lw]).first ?? nil)[0], c.net, accuracy: 1e-9))
        // With no background window: net = G and sigma = sqrt(G).
        let bare = LineWindow(element: "Al", id: "Al_Ka", energy: 1.4865, fwhm: 0.07,
                              window: ResolvedWindow(signal: 10..<20, background: nil), failure: nil, conflicts: [])
        let n = try #require(ElementWindows.netCounts(spectrum: spectrum, windows: [bare]).first ?? nil)
        #expect(n.net == 70); #expect(isEqual(n.sigma, 70.0.squareRoot(), accuracy: 1e-12))
    }

    /// The conflict note names the line a background window sits on, in the table's own words, peaks before flanks.
    /// Mutation: the stable sort by `reachesIntegrationWindow` removed — red.
    @Test func testConflictNotesNameTheOtherLine() {
        #expect(ElementWindows.label(ofLineID: "Al_Ka") == "Al Kα")
        #expect(ElementWindows.label(ofLineID: "Cu_Lb1") == "Cu Lβ1")
        let c = WindowConflict(line: "Mg_Ka", side: .right, other: "Si_Ka", otherEnergy: 1.74, overlap: 1.5...1.6, reachesIntegrationWindow: false)
        #expect(ElementWindows.conflictNote([c]) == "background overlaps Si Kα")
        // A peak the background sits on is named before a flank it only touches, whatever the energy order.
        let flank = WindowConflict(line: "Mg_Ka", side: .left, other: "Cu_La", otherEnergy: 0.93, overlap: 1.03...1.06, reachesIntegrationWindow: false)
        let peak = WindowConflict(line: "Mg_Ka", side: .right, other: "Si_Ka", otherEnergy: 1.74, overlap: 1.65...1.7, reachesIntegrationWindow: true)
        #expect(ElementWindows.conflictNote([flank, peak]) == "background overlaps Si Kα, Cu Lα")
        #expect(ElementWindows.conflictNote([flank, peak, c]) == "background overlaps Si Kα, Cu Lα")
        #expect(ElementWindows.conflictNote([]) == nil)
    }

    /// s·B >= G is not a measurement: its own windows decide, whatever else is selected.
    /// Mutation: `>=` weakened to `>` with s·B == G in the data, or the property returning false — red.
    @Test func testABackgroundThatHoldsMoreThanTheSignalIsNotAMeasurement() throws {
        let window = ResolvedWindow(signal: 10..<20, background: .init(left: 2..<10, right: 30..<47, scale: 0.4))
        let lw = LineWindow(element: "Al", id: "Al_Ka", energy: 1.4865, fwhm: 0.07, window: window, failure: nil, conflicts: [])
        var spectrum = [UInt64](repeating: 0, count: 100)
        for c in 10..<20 { spectrum[c] = 1 }           // G = 10
        for c in 2..<10 { spectrum[c] = 4 }            // B = 32 + 4 * 17 = 100; s B = 40
        for c in 30..<47 { spectrum[c] = 4 }
        let bad = try #require(ElementWindows.netCounts(spectrum: spectrum, windows: [lw]).first ?? nil)
        #expect(bad.backgroundExceedsSignal)
        #expect(bad.notAMeasurementText == "not a measurement: the background windows (s·B = 40) hold more than the signal window (G = 10); they sit on neighbouring peaks")
        for c in 10..<20 { spectrum[c] = 4 }           // G = 40 = s B: equal counts as "not more", still refused (>=)
        #expect(try #require(ElementWindows.netCounts(spectrum: spectrum, windows: [lw]).first ?? nil).backgroundExceedsSignal)
        for c in 10..<20 { spectrum[c] = 9 }
        let good = try #require(ElementWindows.netCounts(spectrum: spectrum, windows: [lw]).first ?? nil)
        #expect(!good.backgroundExceedsSignal)
        #expect(good.notAMeasurementText == nil)
    }
}
