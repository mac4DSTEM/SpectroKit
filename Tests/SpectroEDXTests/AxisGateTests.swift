//
//  AxisGateTests.swift
//  Role: EDX stage gate G-E (docs/edx-stage-gates-registration.md section 3 and amendment 1): the energy axis.
//
//  E1: `VeloxEnergyAxis` / the opener's `EnergyAxis` equal RosettaSciIO's `_get_dispersion_offset` bit for bit on every public
//      Velox file and on planted headers (decoy detector, differing offsets, detector keys out of index order);
//      `energyCalibrationAgrees` is false when the summed segments' calibrations differ.
//  E2: `EnergyAxis.index(of:)` / `channelRange` equal HyperSpy 2.4.0's `value2index` / `_get_array_slices` on the Velox axis
//      (offset -1.93221348, scale 0.02, 4096) at every table line energy of Z 5 to 50, at +-1e-13 around every channel
//      midpoint (ties) and at the ends.
//  E3: `EnergyAxisRefinement.refine` against the planted offset and gain (truth), with exSpy's `calibrate_energy_axis` pinned
//      beside it as a second estimate (never as the truth).
//
//  DEVIATION (0.4.0, approved by the suite coordinator 2026-10-15; docs/consumers-0.4.0.md section 7): FormatoKit 0.0.2 keeps
//  `VeloxStreamInfo.id` and `VeloxSpectrumImage.energyCalibrationAgrees` `package`. This file reads the pinned stream ids in
//  name order (the reader's order) and the calibration flag recomputed from the public segments by the reader's rule
//  (`swiftAxes`) instead. Reverts to the reader's own members at the next FormatoKit pin that makes them public (asked of
//  FormatoKit 0.0.3).
//

import Foundation
import Testing
import SpectroCore
import SpectroEDX
import FormatoEMD

struct AxisGateTests {

    private var rule: [String: Any] { EDXFixtures.pins.d("axis").d("rsciio_rule") }

    private struct Cal: Equatable { let dispersionKeV: Double, offsetKeV: Double }

    private func pinned(_ list: Any) -> [(stream: String, cal: Cal)] {
        (list as! [[String: Any]]).map { ($0.s("stream"), Cal(dispersionKeV: $0.x("dispersion_keV"), offsetKeV: $0.x("offset_keV"))) }
    }

    /// Swift's reading per stream (by stream id) and the file-level axis (first stream) and the agreement flag.
    ///
    /// 0.4.0 (FormatoKit 0.0.2, docs/consumers-0.4.0.md "Deviations"): `VeloxStreamInfo.id` and
    /// `VeloxSpectrumImage.energyCalibrationAgrees` are `package` in FormatoKit, out of reach from here. The reader lists the
    /// streams in name order (HDF5's name index), so the stream ids are the pinned ids sorted, paired with `streams` in order
    /// (the counts must match); the flag is the reader's rule recomputed from the public segments (one distinct
    /// dispersion|offset over every segment of every stream, FormatoEMD VeloxEMDReader.swift's `calibrations.count <= 1`).
    /// Both go back to the reader's own members when FormatoKit makes them public.
    private func swiftAxes(_ path: String, ids: [String]) throws -> (perStream: [String: Cal?], first: Cal?, agrees: Bool) {
        let v = try VeloxEMDReader(path: path).readSpectrumImage()
        #expect(v.streams.count == Set(ids).count, "\(path): one pinned id per stream")
        var per: [String: Cal?] = [:]
        for (id, s) in zip(Set(ids).sorted(), v.streams) {
            if let seg = s.segments.first, let d = seg.dispersionEV, let o = seg.offsetEnergyEV {
                per[id] = Cal(dispersionKeV: d / 1000, offsetKeV: o / 1000)
            } else { per[id] = .some(nil) }
        }
        let first = v.metadata.energyAxis.map { Cal(dispersionKeV: $0.scaleKeV, offsetKeV: $0.offsetKeV) }
        let calibrations = Set(v.streams.flatMap(\.segments).map { "\($0.dispersionEV ?? .nan)|\($0.offsetEnergyEV ?? .nan)" })
        return (per, first, calibrations.count <= 1)
    }

    // MARK: E1

    /// E1 on every public file RosettaSciIO's test data holds with a stream: the axis of every stream, and of the file (the first
    /// stream), equal rsciio's rule bit for bit; the calibration flag equals "all streams equal".
    @Test func testE1PublicFilesAxisEqualsRosettaSciIOsRule() throws {
        let files = rule.d("files")
        let skipLabels: Set<String> = []
        var checked = 0
        for (label, list) in files.sorted(by: { $0.key < $1.key }) where !skipLabels.contains(label) {
            let expected = pinned(list)
            let path: String
            do { path = try EDXFixtures.publicVelox(label: label) } catch is FixtureAbsent { continue }
            let got = try swiftAxes(path, ids: expected.map(\.stream))
            for (id, cal) in expected {
                let g = try #require(got.perStream[id], "\(label): stream \(id)")
                #expect(g?.dispersionKeV.bitPattern == cal.dispersionKeV.bitPattern, "\(label) \(id) dispersion")
                #expect(g?.offsetKeV.bitPattern == cal.offsetKeV.bitPattern, "\(label) \(id) offset")
            }
            #expect(got.first?.offsetKeV.bitPattern == expected[0].cal.offsetKeV.bitPattern, "\(label): metadata axis")
            #expect(got.first?.dispersionKeV.bitPattern == expected[0].cal.dispersionKeV.bitPattern, "\(label): metadata axis")
            #expect(got.agrees == (Set(expected.map { [$0.cal.dispersionKeV, $0.cal.offsetKeV] }).count == 1), "\(label): agreement flag")
            // the opener's axis is the first stream's
            let image = try SpectrumImageOpener.open(path: path, kind: .veloxSpectrumImage)
            #expect(image.energyAxis.offset.bitPattern == expected[0].cal.offsetKeV.bitPattern, "\(label): opener")
            #expect(image.energyAxis.scale.bitPattern == expected[0].cal.dispersionKeV.bitPattern, "\(label): opener")
            checked += 1
        }
        if checked == 0 { try Test.cancel("no public Velox file available") }
        gateNote("EDX E1: \(checked) public files, every stream's axis equal to rsciio's rule bit for bit")
    }

    private func plantedPath(_ name: String) -> String {
        EDXFixtures.url(EDXFixtures.streamTruth.d("cases").d(name).s("file")).path
    }

    /// E1 on the planted headers where the reader and rsciio's rule must agree: 1 stream, 3 frames, 4 streams with offsets
    /// -1000/-1000/-996/-1000 eV (the calibration flag must be false), the decoy (rsciio takes the FIRST detector whose name
    /// contains BinaryResult.Detector, in file order).
    @Test func testE1PlantedHeadersEqualTheRule() throws {
        for name in ["1stream-1frame", "1stream-3frames", "4streams-2frames", "axis-decoy", "unterminated"] {
            let expected = pinned(rule.d("planted")[name]!)
            let truth = EDXFixtures.streamTruth.d("cases").d(name)
            let got = try swiftAxes(plantedPath(name), ids: expected.map(\.stream))
            for (id, cal) in expected {
                let g = try #require(got.perStream[id], "\(name) \(id)")
                #expect(g?.dispersionKeV.bitPattern == cal.dispersionKeV.bitPattern, "\(name) \(id) dispersion")
                #expect(g?.offsetKeV.bitPattern == cal.offsetKeV.bitPattern, "\(name) \(id) offset")
            }
            #expect(got.first?.offsetKeV.bitPattern == expected[0].cal.offsetKeV.bitPattern, "\(name)")
            #expect(got.agrees == (truth["expect_calibration_agrees"] as? Bool), "\(name): energyCalibrationAgrees")
        }
        // 4 detectors: the summed spectrum mixes scales, so the flag is false (offsets differ by 4 eV)
        let four = try swiftAxes(plantedPath("4streams-2frames"), ids: pinned(rule.d("planted")["4streams-2frames"]!).map(\.stream))
        #expect(!four.agrees)
    }

    /// E1 file order. Registration amendment 1, item 5: keys in file order Detector-0, Detector-10, Detector-2.
    /// RosettaSciIO takes Detector-10 (20 eV, -1900 eV) by FILE order; `VeloxMetadata.parse` sorts the detectors by index (a JSON
    /// object has no order in Swift), which takes Detector-2 (10 eV, -500 eV). REGISTERED FINDING: the reader deviates from the
    /// rule on a file whose keys are not in index order (no public file and not the owner's header is such a file).
    @Test func testE1DetectorKeysOutOfIndexOrderFollowTheFileOrder() throws {
        let expected = pinned(rule.d("planted")["axis-order"]!)
        #expect(expected[0].cal == Cal(dispersionKeV: 0.02, offsetKeV: -1.9), "rsciio's rule takes Detector-10")
        let got = try swiftAxes(plantedPath("axis-order"), ids: expected.map(\.stream))
        withKnownIssue("registered finding (amendment 1 item 5): VeloxEMDReader sorts Detector-<n> by index, so on a file with keys Detector-0, Detector-10, Detector-2 it takes Detector-2's axis; rsciio takes the first in file order, Detector-10") {
            #expect(got.first?.offsetKeV == expected[0].cal.offsetKeV)
            #expect(got.first?.dispersionKeV == expected[0].cal.dispersionKeV)
        }
        gateNote("EDX E1 axis-order: reader takes dispersion \(String(describing: got.first?.dispersionKeV)) keV, offset \(String(describing: got.first?.offsetKeV)) keV; rsciio takes 0.02, -1.9")
    }

    // MARK: E2

    private var e2: [String: Any] { EDXFixtures.pins.d("axis").d("e2") }

    @Test func testE2ValueToIndexEqualsHyperSpyOnTheWholeGrid() throws {
        let pin = e2
        let values = EDXFixtures.data("edx-axis-e2.f64", as: Double.self)
        #expect(EDXFixtures.sha256(try Data(contentsOf: EDXFixtures.url("edx-axis-e2.f64"))) == pin.s("sha256"))
        let idx = pin["index"] as! [Any]
        #expect(values.count == pin.i("count")); #expect(idx.count == values.count)
        let ax = pin.d("axis")
        let axis = EnergyAxis(offset: ax.x("offset"), scale: ax.x("scale"), size: ax.i("size"))
        #expect(axis == EDXFixtures.axis)
        var raised = 0, wrong: [String] = []
        for (i, v) in values.enumerated() {
            if let want = (idx[i] as? NSNumber)?.intValue {
                if (try? axis.index(of: v)) != want { wrong.append("\(v): got \(String(describing: try? axis.index(of: v))) want \(want)") }
            } else {
                raised += 1
                if (try? axis.index(of: v)) != nil { wrong.append("\(v): HyperSpy raises, got an index") }
            }
        }
        #expect(wrong.isEmpty, "\(wrong.count) of \(values.count): \(wrong.prefix(5))")
        #expect(raised > 0, "the pins include values HyperSpy raises on (the ends)")
        // the table lines in Z 5 to 50 are covered
        #expect(pin.i("n_lines") == (pin["line_names"] as! [Any]).count)
        #expect(pin.i("n_midpoints") == 4095)
        gateNote("EDX E2: \(values.count) value2index cases, \(raised) raise in HyperSpy, all equal")
    }

    @Test func testE2SlicesEqualHyperSpyArraySlices() throws {
        let axis = EDXFixtures.axis
        let slices = EDXFixtures.pins.d("axis")["slices"] as! [[String: Any]]
        #expect(slices.count > 40)
        for s in slices {
            let lo = s.x("lo"), hi = s.x("hi")
            if s["error"] != nil {
                #expect(throws: (any Error).self, "\(s.s("line")) [\(lo), \(hi)]") { try axis.channelRange(from: lo, to: hi) }
            } else {
                #expect((try axis.channelRange(from: lo, to: hi)) == (s.i("i1")..<s.i("i2")), "\(s.s("line")) [\(lo), \(hi)]")
            }
        }
    }

    // MARK: E3

    private struct CalRow { let cell: [String: Any]; let counts: [Double] }

    private func calibrationRows() -> [(id: String, delta: Double, gain: Double, r: Double, nAl: Double, real: Int, trueOffset: Double, trueScale: Double, counts: [Double])] {
        let cal = EDXFixtures.calibration
        let nwin = cal.i("nwin"), k0 = cal.i("k0")
        let u = EDXFixtures.data("edx-calibration-counts.u32", as: UInt32.self)
        var out: [(String, Double, Double, Double, Double, Int, Double, Double, [Double])] = []
        for c in cal.l("cells") {
            let ta = c.d("true_axis")
            for j in 0..<c.i("n_real") {
                var full = [Double](repeating: 0, count: 4096)
                let row = c.i("row0") + j
                for k in 0..<nwin { full[k0 + k] = Double(u[row * nwin + k]) }
                out.append((c.s("id"), Double(c.s("delta_eV"))!, Double(c.s("gain"))!, Double(c.s("R_MnKa"))!, Double(c.s("N_Al"))!, j + 1,
                            Double(ta.s("offset_keV"))!, Double(ta.s("scale_keV"))!, full))
            }
        }
        return out
    }

    /// The Fano truth's FWHM at `e` keV for `r` = FWHM(Mn Ka) in eV (make_planted.fwhm_fano), eV.
    private static func fanoFWHM(_ e: Double, _ r: Double) -> Double {
        let c8ln2 = 8 * log(2.0), mn = 5898.7
        let s2n = r * r / c8ln2 - 3.76 * 0.11 * mn
        return (c8ln2 * (s2n + 3.76 * 0.11 * e * 1000)).squareRoot()
    }

    /// E3: the Swift refinement recovers the planted offset and gain. Registered bounds (section 7, "Predicted for E3"):
    /// within 1 eV for the offset and 1e-4 relative for the gain at N_Al >= 1e6, every shift in {-12 ... +12} eV, every gain in
    /// {-3, 0, +3}e-4 and every R_MnKa in {125 ... 150}. Fit range 0.3 to 3 keV, lines Mg, Al, Si, the model at 130 eV.
    ///
    /// REGISTERED FINDING (the prediction "may fail, and then it is a finding"): it fails. On these spectra (lines only from
    /// Mg Ka 1.25 to Si Kb 1.84 keV, the `EnergyAxisRefinement` header says offset and gain are well determined only when the
    /// lines span the range) offset and gain trade off: the joint estimate has an offset error of about -3 to -4 eV and a gain
    /// error of about +1e-3, which nearly cancel at the lines. The positions of the three alpha lines on the refined axis are
    /// reported (they are what a user sees). The failing bounds are in `withKnownIssue` (XCTExpectFailure before the Swift Testing migration); the run-level facts that hold today
    /// (all 384 converge, positions within the bounds below) are asserted outside it.
    @Test func testE3RefinementRecoversPlantedOffsetAndGain() throws {
        let rows = calibrationRows()
        #expect(rows.count == 384)
        let axis = EDXFixtures.axis
        struct Out: Sendable { var offErr: Double, gainErr: Double, fwhmErr: Double, converged: Bool, posErr: [Double] }
        let nominal = [1.2536, 1.4865, 1.7400]   // Mg Ka, Al Ka, Si Ka (booklet = table)
        let results: [Out] = parallelMap(rows.count) { i in
            let r = rows[i]
            var settings = FitSettings.standard(elements: ["Mg", "Al", "Si"], axis: axis, resolutionMnKaEV: 130, beamEnergy: 200)
            settings.fitFrom = 0.3; settings.fitTo = 3.0
            guard let res = try? EnergyAxisRefinement.refine(counts: r.counts, fileAxis: axis, fileResolutionMnKaEV: 130, settings: settings) else {
                return Out(offErr: .nan, gainErr: .nan, fwhmErr: .nan, converged: false, posErr: [])
            }
            let fw = XRayLines.fwhm(resolutionMnKaEV: res.resolutionMnKaEV, atEnergy: 1.4865)! * 1000
            let pos = nominal.map { e -> Double in
                let k = (e - r.trueOffset) / r.trueScale          // the channel the planted line sits in
                return (res.refinedAxis.offset + res.refinedAxis.scale * k - e) * 1000
            }
            return Out(offErr: (res.refinedAxis.offset - r.trueOffset) * 1000, gainErr: res.refinedAxis.scale / r.trueScale - 1,
                       fwhmErr: fw - AxisGateTests.fanoFWHM(1.4865, r.r), converged: res.converged, posErr: pos)
        }
        #expect(results.allSatisfy { $0.offErr.isFinite }, "every refinement returned")
        #expect(results.filter { $0.converged }.count == 384, "every refinement converged")
        func stats(_ sel: (Int) -> Bool, _ f: (Out) -> Double) -> String {
            let v = results.indices.filter(sel).map { f(results[$0]) }
            return String(format: "n %d mean %+.3g max|.| %.3g", v.count, v.reduce(0, +) / Double(v.count), v.map { abs($0) }.max() ?? .nan)
        }
        for g in [-3e-4, 0, 3e-4] {
            for n in [1e6, 1e7] {
                let sel: (Int) -> Bool = { rows[$0].gain == g && rows[$0].nAl == n }
                gateNote("EDX E3 swift gain \(g) N \(n): offset(eV) \(stats(sel) { $0.offErr }); gain \(stats(sel) { $0.gainErr }); FWHM(Al Ka) eV \(stats(sel) { $0.fwhmErr })")
            }
        }
        for (j, name) in ["Mg Ka", "Al Ka", "Si Ka"].enumerated() {
            gateNote("EDX E3 swift position error at \(name) (eV, refined axis against the planted line): \(stats({ _ in true }) { $0.posErr[j] })")
        }
        let badOff = results.indices.filter { abs(results[$0].offErr) > 1.0 }
        let badGain = results.indices.filter { abs(results[$0].gainErr) > 1e-4 }
        gateNote("EDX E3 swift outside 1 eV: \(badOff.count) of \(results.count); outside 1e-4 gain: \(badGain.count)")
        // What holds today and is asserted: the lines land within 5 eV on the refined axis (measured max below) and the
        // refinement improves the fit. Not registered bounds: they guard the measured behaviour against a regression.
        let worstPos = results.flatMap { $0.posErr.map(abs) }.max()!
        gateNote("EDX E3 swift worst line position error \(worstPos) eV")
        #expect(worstPos < 1.2, "measured worst line position error on the refined axis")
        withKnownIssue("registered finding (section 7, Predicted for E3): offset and gain are not recovered within 1 eV and 1e-4 on spectra whose lines span 1.25-1.84 keV; they trade off") {
            #expect(badOff.isEmpty, "offset outside 1 eV: \(badOff.count) of 384, e.g. \(badOff.prefix(3).map { "\(rows[$0].id)#\(rows[$0].real) \(String(format: "%.2f", results[$0].offErr)) eV" })")
            #expect(badGain.isEmpty, "gain outside 1e-4: \(badGain.count) of 384, e.g. \(badGain.prefix(3).map { "\(rows[$0].id)#\(rows[$0].real) \(String(format: "%.2e", results[$0].gainErr))" })")
        }
    }

    /// E3 second estimate: exSpy's `calibrate_energy_axis("offset")` on the same spectra (pins), error = offset change + planted
    /// shift. Amendment 1 item 2 recorded: mean +0.03 eV and at most 0.71 eV at N_Al 1e6 (288 fits), +0.02 / 0.62 at 1e7 (96),
    /// and that "scale" returns 0.0199577 for every planted gain. These readings are asserted so the fixture cannot drift;
    /// exSpy is the second estimate, not the truth, and no gate bound rests on it.
    @Test func testE3ExSpyCalibrationPinsAreTheRecordedSecondEstimate() throws {
        let rows = EDXFixtures.pins.d("axis").d("calibration").l("rows")
        let cells = Dictionary(uniqueKeysWithValues: EDXFixtures.calibration.l("cells").map { ($0.s("id"), $0) })
        var errs: [Double: [Double]] = [:]
        var scaleValues = Set<Double>(), resolutionRaised = 0
        for r in rows {
            let c = cells[r.s("cell")]!
            let modes = r.d("modes")
            let o = modes.d("offset")
            if o["error"] == nil {
                let change = (o.x("offset_after") - o.x("offset_before")) * 1000
                errs[Double(c.s("N_Al"))!, default: []].append(change + Double(c.s("delta_eV"))!)
            }
            let s = modes.d("scale")
            if s["error"] == nil { scaleValues.insert((s.x("scale_after") * 1e7).rounded() / 1e7) }
            if modes.d("resolution")["error"] != nil { resolutionRaised += 1 }
        }
        let e6 = errs[1e6]!, e7 = errs[1e7]!
        #expect(e6.count == 288); #expect(e7.count == 96)
        #expect(isEqual(e6.map { abs($0) }.max()!, 0.71, accuracy: 0.005))
        #expect(isEqual(e7.map { abs($0) }.max()!, 0.62, accuracy: 0.005))
        #expect(isEqual(e6.reduce(0, +) / 288, 0.03, accuracy: 0.005))
        // Amendment 1 item 2 said `"scale"` returns 0.0199577 for every planted gain; 0.0199577 is the MEAN of two values,
        // 0.0198877 and 0.0201678 (corrected in amendment 2): the same two values at every planted gain, so it does not track gain.
        #expect(scaleValues == [0.0198877, 0.0201678], "scale mode returns one of two scales whatever the planted gain")
        for g in ["-0.0003", "0.0", "0.0003"] {
            let v = Set(rows.filter { cells[$0.s("cell")]!.s("gain") == g }.compactMap { r -> Double? in
                let m = r.d("modes").d("scale"); return m["error"] == nil ? (m.x("scale_after") * 1e7).rounded() / 1e7 : nil })
            #expect(v == [0.0198877, 0.0201678], "gain \(g)")
        }
        #expect(resolutionRaised == 2)
        // the registered prediction "within +-0.2 eV at N_Al >= 1e6" is FALSE for exSpy (amendment 1 item 2):
        #expect(e6.map { abs($0) }.max()! > 0.2)
    }
}
