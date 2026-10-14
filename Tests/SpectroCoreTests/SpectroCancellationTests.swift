import XCTest
import SpectroCore
import SpectroEDX

/// SpectroKit S0 (ADR 064 amendment 2 §2): the long spectroscopy calls take `cancelled` (default `SpectroCancellation.task`) and an
/// optional `progress`. Per family: cancel at the first step and cancel INSIDE the call both throw `SpectroCancelled` and return
/// nothing; progress is monotone and ends at 1; the default arguments reproduce the plain call's numbers. Each test names its mutation.
@MainActor
final class SpectroCancellationTests: XCTestCase {

    /// A cancel closure that answers true exactly on its `at`-th call (1-based), counting every call. A one-shot answer, so a
    /// mutation that stops forwarding the closure to an inner step is not caught by the later boundaries.
    private nonisolated final class Flip: @unchecked Sendable {
        private let lock = NSLock()
        private var calls = 0
        let at: Int
        init(at: Int) { self.at = at }
        var count: Int { lock.lock(); defer { lock.unlock() }; return calls }
        var closure: @Sendable () -> Bool { { [self] in lock.lock(); defer { lock.unlock() }; calls += 1; return calls == at } }
    }

    private nonisolated final class Reports: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [Double] = []
        var all: [Double] { lock.lock(); defer { lock.unlock() }; return values }
        var closure: @Sendable (Double) -> Void { { [self] v in lock.lock(); values.append(v); lock.unlock() } }
    }

    private func assertMonotoneEndingAtOne(_ r: Reports, minimum: Int = 2, file: StaticString = #filePath, line: UInt = #line) {
        let v = r.all
        XCTAssertGreaterThanOrEqual(v.count, minimum, "progress reported \(v)", file: file, line: line)
        XCTAssertEqual(v.last, 1, "progress ends at 1: \(v)", file: file, line: line)
        XCTAssertTrue(zip(v, v.dropFirst()).allSatisfy { $0 <= $1 }, "progress is monotone: \(v)", file: file, line: line)
        XCTAssertTrue(v.allSatisfy { (0...1).contains($0) }, "\(v)", file: file, line: line)
    }

    private func assertCancels<T>(_ body: () throws -> T, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        do { _ = try body(); XCTFail("\(what): expected SpectroCancelled", file: file, line: line) }
        catch is SpectroCancelled {}
        catch { XCTFail("\(what): threw \(error), not SpectroCancelled", file: file, line: line) }
    }

    // MARK: Spectrum images

    private static let n = 9000   // three 4096-pixel blocks
    private static func dense() -> DenseSpectrumImage {
        DenseSpectrumImage(ny: 90, nx: 100, channels: 4, counts: (0..<(n * 4)).map { UInt32($0 % 7) })
    }
    private static func sparse() throws -> SparseSpectrumImage {
        var offsets = [0], idx: [UInt16] = [], cnt: [UInt32] = []
        for p in 0..<n { idx += [UInt16(p % 2), 3]; cnt += [UInt32(p % 5 + 1), 2]; offsets.append(idx.count) }
        return try SparseSpectrumImage(ny: 90, nx: 100, channels: 4, rowOffsets: offsets, channelIndex: idx, counts: cnt)
    }

    /// Mutation: the `check` at the top of the block loop of `sum`/`windowSums`/`densified` removed (Dense and Sparse) - red.
    func testImageLoopsCancelAtTheFirstAndAtALaterBlockAndReportProgress() throws {
        let dense = Self.dense(), sparse = try Self.sparse()
        for at in [1, 2, 3] {
            assertCancels({ try dense.sum(mask: nil, cancelled: Flip(at: at).closure) }, "dense sum \(at)")
            assertCancels({ try dense.windowSums([0..<2], cancelled: Flip(at: at).closure) }, "dense windowSums \(at)")
            assertCancels({ try sparse.sum(mask: nil, cancelled: Flip(at: at).closure) }, "sparse sum \(at)")
            assertCancels({ try sparse.windowSums([0..<2], cancelled: Flip(at: at).closure) }, "sparse windowSums \(at)")
            assertCancels({ try sparse.densified(cancelled: Flip(at: at).closure) }, "densified \(at)")
        }
        // Through the source and through the protocol requirement.
        let source = LoadedSpectrumImage(
            image: dense, metadata: SpectrumImageMetadata(fileName: "t", filePath: "", scanWidth: 100, scanHeight: 90, channelCount: 4,
                                                          energyOffsetEV: 0, energyDispersionEV: 10),
            energyAxis: EnergyAxis(offset: 0, scale: 0.01, size: 4))
        assertCancels({ try source.sum(mask: nil, cancelled: Flip(at: 2).closure) }, "source sum")
        assertCancels({ try (source as any SpectrumImage).windowSums([0..<2], cancelled: Flip(at: 2).closure, progress: nil) }, "protocol windowSums")
        // Progress, and the defaults reproduce the plain calls.
        let r1 = Reports(), r2 = Reports(), r3 = Reports()
        XCTAssertEqual(try dense.sum(mask: nil, cancelled: { false }, progress: r1.closure), dense.sum(mask: nil))
        XCTAssertEqual(try sparse.windowSums([0..<2, 2..<4], cancelled: { false }, progress: r2.closure), sparse.windowSums([0..<2, 2..<4]))
        XCTAssertEqual(try sparse.densified(cancelled: { false }, progress: r3.closure).counts, sparse.densified().counts)
        for r in [r1, r2, r3] { assertMonotoneEndingAtOne(r, minimum: 3) }
        XCTAssertEqual(try dense.sum(mask: nil, cancelled: SpectroCancellation.task), dense.sum(mask: nil), "task-default form")
    }

    /// Mutation: `ElementWindows.maps`/`integratedMaps` passing `{ false }` instead of `cancelled` to the window sums - red.
    func testElementWindowMapsForwardTheCancel() throws {
        let axis = EnergyAxis(offset: 0, scale: 0.01, size: 1100)
        let windows = ElementWindows.build(elements: [("Al", nil), ("Si", nil)], axis: axis, beamEnergyKeV: 200)
        XCTAssertTrue(windows.allSatisfy { $0.window != nil })
        let n = Self.n, ch = axis.size
        let image = DenseSpectrumImage(ny: 90, nx: 100, channels: ch, counts: (0..<(n * ch)).map { UInt32($0 % 3) })
        assertCancels({ try ElementWindows.maps(image: image, windows: windows, cancelled: Flip(at: 2).closure) }, "maps")
        assertCancels({ try ElementWindows.integratedMaps(image: image, windows: windows, cancelled: Flip(at: 2).closure) }, "integratedMaps")
        assertCancels({ try WindowIntensity.maps(image: image, windows: windows.compactMap(\.window), cancelled: Flip(at: 1).closure) }, "resolved maps")
        let r = Reports()
        let a = try ElementWindows.maps(image: image, windows: windows, cancelled: { false }, progress: r.closure)
        XCTAssertEqual(a, ElementWindows.maps(image: image, windows: windows))
        XCTAssertEqual(try ElementWindows.integratedMaps(image: image, windows: windows, cancelled: { false }),
                       ElementWindows.integratedMaps(image: image, windows: windows))
        assertMonotoneEndingAtOne(r, minimum: 3)
    }

    // MARK: Openers

    private static let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")

    /// Mutation: the `check` calls of `openGMSEDS` / `openVelox` / `open` removed - red.
    func testOpenersCancelBeforeAndBetweenSteps() throws {
        let dm4 = Self.dir.appendingPathComponent("demo-edx-tiny.dm4").path
        let velox = Self.dir.appendingPathComponent("velox-tiny.emd").path
        for at in [1, 2, 3] {
            assertCancels({ try SpectrumImageOpener.openGMSEDS(path: dm4, cancelled: Flip(at: at).closure) }, "gms \(at)")
            assertCancels({ try SpectrumImageOpener.open(path: dm4, kind: .gmsEDSOnly, cancelled: Flip(at: at).closure) }, "open gms \(at)")
        }
        for at in [1, 2, 3] {
            assertCancels({ try SpectrumImageOpener.openVelox(path: velox, cancelled: Flip(at: at).closure) }, "velox \(at)")
        }
        assertCancels({ try SpectrumImageOpener.open(path: velox, kind: .veloxSpectrumImage, cancelled: Flip(at: 1).closure) }, "open velox")
        let r1 = Reports(), r2 = Reports()
        let g = try XCTUnwrap(try SpectrumImageOpener.openGMSEDS(path: dm4, cancelled: { false }, progress: r1.closure))
        let v = try SpectrumImageOpener.open(path: velox, kind: .veloxSpectrumImage, cancelled: { false }, progress: r2.closure)
        assertMonotoneEndingAtOne(r1, minimum: 3); assertMonotoneEndingAtOne(r2, minimum: 3)
        // Defaults reproduce the plain open.
        let g2 = try XCTUnwrap(try SpectrumImageOpener.openGMSEDS(path: dm4))
        XCTAssertEqual(g.sum(mask: nil), g2.sum(mask: nil))
        XCTAssertEqual(v.sum(mask: nil), try SpectrumImageOpener.openVelox(path: velox).sum(mask: nil))
    }

    /// The opener forwards its cancel and progress INTO the Velox read (supervisor's follow-up to lanes C and L): progress strictly
    /// between 0 and 0.9 can only come from inside the read, and only the read calls the cancel closure more than three times.
    /// Mutation: call `readSpectrumImage()` without the two arguments - red.
    func testOpenVeloxForwardsCancelAndProgressIntoTheRead() throws {
        let velox = Self.dir.appendingPathComponent("velox-tiny.emd").path
        let r = Reports()
        _ = try SpectrumImageOpener.openVelox(path: velox, cancelled: { false }, progress: r.closure)
        XCTAssertTrue(r.all.contains { $0 > 0 && $0 < 0.9 }, "progress from inside the read: \(r.all)")
        // Cancel: the read polls the same closure, so it is called more than the opener's own three checks.
        let flip = Flip(at: Int.max)
        _ = try SpectrumImageOpener.openVelox(path: velox, cancelled: flip.closure)
        XCTAssertGreaterThan(flip.count, 3, "the read polled the opener's cancel closure")
    }

    // MARK: Fits

    private static let axis = EnergyAxis(offset: 0, scale: 0.02, size: 1600)   // to 32 keV: past the 20 keV default fit range

    /// A noiseless synthetic spectrum: smooth continuum, K-alpha Gaussians for `peaks` (keV, amplitude).
    private static func counts(_ peaks: [(Double, Double)]) -> [UInt64] {
        (0..<axis.size).map { i in
            let e = axis.energy(ofChannel: i)
            var v = 40 * exp(-e / 5)
            for (c, a) in peaks { let s = (0.06 + 0.0025 * c) / 2.355; v += a * exp(-0.5 * pow((e - c) / s, 2)) }
            return UInt64(v.rounded())
        }
    }

    private static func input(listed: [(String, QuantificationMethod.ElementRole)], peaks: [(Double, Double)]) -> PooledQuantificationInput {
        var m = QuantificationMethod()
        m.elements = listed.map { .init(symbol: $0.0, role: $0.1, isManual: false) }
        m.beamEnergyKeV = 200; m.absorptionCorrection = false
        let meta = SpectrumImageMetadata(fileName: "synthetic", filePath: "", scanWidth: 1, scanHeight: 1, channelCount: axis.size,
                                         energyOffsetEV: 0, energyDispersionEV: 20)
        return PooledQuantificationInput(counts: counts(peaks), axis: axis, method: m, metadata: meta, regionName: "synthetic", pixelCount: 1)
    }

    private static let peaks: [(Double, Double)] = [(1.4867, 4000), (1.7399, 3000), (4.5108, 2500), (8.0478, 3500)]
    private static let listed: [(String, QuantificationMethod.ElementRole)] = [("Al", .quantify), ("Si", .quantify), ("Ti", .quantify)]

    /// Mutation: `PooledQuantifier.run` passing `{ false }` to `EnergyAxisRefinement.refine` (the refinement is never cancelled
    /// at call 2 or in its simplex loop) - red at 2 and 4; the `catch let c as SpectroCancelled { throw c }` removed - red at 2 and 4
    /// (the cancel becomes a warning and the run finishes); the check before the fit removed - red at the later call.
    func testPooledQuantifierCancelsAtTheEntryInsideTheRefinementAndAtTheLaterBoundaries() throws {
        let input = Self.input(listed: Self.listed, peaks: Self.peaks)
        for at in [1, 2, 4, 5] {
            assertCancels({ try PooledQuantifier.run(input, tables: nil, cancelled: Flip(at: at).closure) }, "run \(at)")
        }
        // The refinement is skipped when given: the boundaries after it still cancel (the entry, the fit, the rows, the end).
        var given = input
        given.refinement = try EnergyAxisRefinement.refine(counts: input.counts.map { Double($0) }, fileAxis: input.axis,
                                                           fileResolutionMnKaEV: input.resolutionMnKaEV,
                                                           settings: FitSettings.standard(elements: ["Al", "Si", "Ti"], axis: input.axis,
                                                                                          resolutionMnKaEV: input.resolutionMnKaEV, beamEnergy: 200))
        for at in 1...4 { assertCancels({ try PooledQuantifier.run(given, tables: nil, cancelled: Flip(at: at).closure) }, "given \(at)") }
        let flip = Flip(at: -1)
        let r = Reports()
        let q = try PooledQuantifier.run(input, tables: nil, cancelled: flip.closure, progress: r.closure)
        assertMonotoneEndingAtOne(r, minimum: 4)
        XCTAssertGreaterThan(flip.count, 6, "the simplex loop asks once per iteration")
        let plain = try PooledQuantifier.run(input, tables: nil)
        XCTAssertEqual(q.rows.map(\.net), plain.rows.map(\.net))
        XCTAssertEqual(q.rows.map(\.sigma), plain.rows.map(\.sigma))
    }

    /// Mutation: the `check` per iteration in `nelderMead` removed - red (the one-shot answer at call 5 is never seen).
    func testAxisRefinementCancelsPerSimplexIterationAndReportsProgress() throws {
        let input = Self.input(listed: Self.listed, peaks: Self.peaks)
        let counts = input.counts.map { Double($0) }
        let settings = FitSettings.standard(elements: ["Al", "Si", "Ti"], axis: input.axis, resolutionMnKaEV: input.resolutionMnKaEV, beamEnergy: 200)
        func refine(_ c: @escaping @Sendable () -> Bool, _ p: (@Sendable (Double) -> Void)? = nil) throws -> AxisRefinementResult {
            try EnergyAxisRefinement.refine(counts: counts, fileAxis: input.axis, fileResolutionMnKaEV: input.resolutionMnKaEV,
                                            settings: settings, cancelled: c, progress: p)
        }
        for at in [1, 2, 5] { assertCancels({ try refine(Flip(at: at).closure) }, "refine \(at)") }
        let r = Reports()
        let a = try refine({ false }, r.closure)
        assertMonotoneEndingAtOne(r, minimum: 3)
        let b = try EnergyAxisRefinement.refine(counts: counts, fileAxis: input.axis, fileResolutionMnKaEV: input.resolutionMnKaEV, settings: settings)
        XCTAssertEqual(a, b)
    }

    /// Mutation: `FitRangeSensitivityCheck.run` passing `{ false }` to the refit (call 3 never seen) - red; the
    /// `catch let c as SpectroCancelled` removed - red (the cancel becomes `failure`, a value, at call 3).
    func testFitRangeSensitivityCancelsAndIsNeverFoldedIntoFailure() throws {
        let input = Self.input(listed: Self.listed, peaks: Self.peaks)
        let q = try PooledQuantifier.run(input, tables: nil)
        XCTAssertNotNil(FitRangeSensitivityCheck.alternative(for: q), "the axis runs past the 20 keV default")
        for at in [1, 3] { assertCancels({ try FitRangeSensitivityCheck.run(input: input, quantification: q, cancelled: Flip(at: at).closure) }, "range \(at)") }
        let r = Reports()
        let s = try XCTUnwrap(FitRangeSensitivityCheck.run(input: input, quantification: q, cancelled: { false }, progress: r.closure))
        assertMonotoneEndingAtOne(r, minimum: 3)
        XCTAssertNil(s.failure)
        XCTAssertEqual(s, try XCTUnwrap(FitRangeSensitivityCheck.run(input: input, quantification: q)))
    }

    /// Mutation: `UnlistedLineChecker.check` passing `{ false }` to its refit, or the `catch let c as SpectroCancelled` removed - red.
    func testUnlistedLineCheckCancelsInsideTheRefit() throws {
        let input = Self.input(listed: [("Al", .quantify), ("Si", .quantify)], peaks: Self.peaks)
        let q = try PooledQuantifier.run(input, tables: nil)
        let counts = input.counts.map { Double($0) }
        let proposal = try UnlistedLineChecker.propose(counts: counts, quantification: q)
        XCTAssertFalse(proposal.candidates.filter { $0.isProposed }.isEmpty, "Ti and Cu are strong and unlisted")
        for at in [1, 2, 3] {
            assertCancels({ try UnlistedLineChecker.check(proposal: proposal, input: input, quantification: q, cancelled: Flip(at: at).closure) }, "check \(at)")
        }
        let r = Reports()
        let c = try UnlistedLineChecker.check(proposal: proposal, input: input, quantification: q, cancelled: { false }, progress: r.closure)
        assertMonotoneEndingAtOne(r, minimum: 3)
        XCTAssertNil(c.failure)
        XCTAssertEqual(c.summary, UnlistedLineChecker.check(proposal: proposal, input: input, quantification: q).summary)
    }

    /// Mutation: `ElementProposer.propose` reading `Task.isCancelled` instead of the closure - red (no throw); the closure not
    /// forwarded by `UnlistedLineChecker.propose` - red. DECISION: the proposer keeps `ProposerError.cancelled`.
    func testProposerCancelsThroughTheClosureAndReportsProgress() throws {
        let input = Self.input(listed: [("Al", .quantify), ("Si", .quantify)], peaks: Self.peaks)
        let counts = input.counts.map { Double($0) }
        let st = FitSettings.standard(elements: ["Al", "Si"], axis: Self.axis, resolutionMnKaEV: 130, beamEnergy: 200)
        for at in [1, 3] {
            do { _ = try ElementProposer().propose(counts: counts, axis: Self.axis, settings: st, cancelled: Flip(at: at).closure)
                 XCTFail("expected cancel at \(at)") }
            catch { XCTAssertEqual(error as? ProposerError, .cancelled) }
        }
        let q = try PooledQuantifier.run(input, tables: nil)
        do { _ = try UnlistedLineChecker.propose(counts: counts, quantification: q, cancelled: Flip(at: 2).closure); XCTFail("expected cancel") }
        catch { XCTAssertEqual(error as? ProposerError, .cancelled) }
        let r = Reports()
        let a = try ElementProposer().propose(counts: counts, axis: Self.axis, settings: st, cancelled: { false }, progress: r.closure)
        assertMonotoneEndingAtOne(r, minimum: 4)
        XCTAssertLessThan(r.all.dropLast().max() ?? 0, 1)
        let b = try ElementProposer().propose(counts: counts, axis: Self.axis, settings: st)
        XCTAssertEqual(a.candidates.map(\.element), b.candidates.map(\.element))
        XCTAssertEqual(a.candidates.map(\.net), b.candidates.map(\.net))
    }

    // MARK: E7

    /// E7: the tables' bundle is injectable; the default is SpectroKit's own (`Bundle.module`). Mutation: the parameter ignored - red on the
    /// bundle that holds the files.
    func testBundledTablesTakeTheBundleTheyAreGiven() throws {
        let empty = FileManager.default.temporaryDirectory.appendingPathComponent("spk-empty-\(UUID().uuidString).bundle")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: empty) }
        XCTAssertNil(QuantificationTables.bundled(in: try XCTUnwrap(Bundle(url: empty))))
        // A bundle that holds the files (Spectroscopy/ beside them) yields the tables.
        let full = FileManager.default.temporaryDirectory.appendingPathComponent("spk-full-\(UUID().uuidString).bundle")
        defer { try? FileManager.default.removeItem(at: full) }
        try FileManager.default.createDirectory(at: full, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: SpectroscopyQuantifySpectro.resources, to: full.appendingPathComponent("Spectroscopy"))
        XCTAssertNotNil(QuantificationTables.bundled(in: try XCTUnwrap(Bundle(url: full))))
        XCTAssertNotNil(QuantificationTables.bundled(), "the default is the library's own copy (Bundle.module), not the host app's")
    }
}
