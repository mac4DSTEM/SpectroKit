import Foundation
import Testing
import SpectroTestSupport
import SpectroCore
import SpectroEDX

/// SpectroEDX's `SpectrumQuantities`: a region's pixel mask, `ElementWindows` net counts, their sigma and the conflict notes, on
/// hand-built shapes and windows. Split out of SpectroCoreTests' SpectrumImageOpeningTests (issue #32): these are SpectroEDX types,
/// not the opening of a file. Each test names its mutation.
@MainActor
struct SpectrumQuantitiesTests {

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
