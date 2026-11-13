//
//  TrapRefusalTests.swift
//  Role: a NaN, an out-of-range channel, a damaged saved setting or an overflowing size reaching the EDX code gives a refusal, an
//        empty result or a written NaN, never a trap (macEMSuite/SpectroKit#103). One test per site the review named.
//  Red before: `try!` on JSONEncoder trapped on a NaN field; `0...order` on a negative order; a continuum precondition on a bad policy;
//  a channel range past the spectrum indexed out of range; a decoded tail with slope 0 gave infinite columns; `Int(NaN)` in the
//  proposer widths, the polygon bounds and the grouped count; `rows * columns` overflowed before validation.
//

import Foundation
import Testing
import SpectroCore
import SpectroEDX

struct TrapRefusalTests {

    private static let axis = EnergyAxis(offset: 0, scale: 0.01, size: 2000)

    // MARK: Method and policy

    @Test func aMethodHoldingANaNStillHasACanonicalFormAndHash() {
        var m = QuantificationMethod()
        m.sigmaK = .nan
        m.fitToKeV = .infinity
        #expect(m.canonicalJSON.contains("\"nan\""))
        #expect(m.canonicalJSON.contains("\"inf\""))
        #expect(m.hash.count == 64)
        // A finite method's bytes are unchanged (its hash is pinned in QuantificationMethodTests).
        #expect(!QuantificationMethod().canonicalJSON.contains("nan"))
    }

    @Test func aPolicyWithNaNEdgesInfiniteFloorsOrAGainBoundOfOneHasAProblemAndStillEncodes() {
        var p = QuantificationPolicy.default
        p.fit.continuumEdges = [.nan]
        #expect(p.problem != nil)
        #expect(p.canonicalJSON.contains("nan"))
        #expect(p.footerLine != nil)

        var q = QuantificationPolicy.default
        q.fit.irls.muFloor = .infinity
        #expect(q.problem != nil)

        var g = QuantificationPolicy.default
        g.fit.axisRefinement.maximumGainShift = 1
        #expect(g.problem != nil)

        var r = QuantificationPolicy.default
        r.fit.axisRefinement.maximumResolutionEV = .infinity
        #expect(r.problem != nil)

        var d = QuantificationPolicy.default
        d.abundance.detector.goldNm = .nan
        #expect(d.problem != nil)

        #expect(QuantificationPolicy.default.problem == nil)
    }

    // MARK: Fit

    @Test func aBadPolicyBuildsAContinuumThatRunsNotATrap() {
        var policy = FitPolicy.default
        policy.continuumEdges = [3, .nan, 1.5]
        policy.continuumOrders = [-1]
        let s = FitSettings.standard(elements: ["Fe"], axis: Self.axis, resolutionMnKaEV: 130, beamEnergy: 2, policy: policy)
        guard case .continuum(let form) = s.background else { Issue.record("a continuum"); return }
        #expect(form.edges == [1.5, 3])
        // A beam of 2 keV and a channel at 0 keV: no infinite column.
        let columns = form.columns(energies: [0, 0.5, 1, 2, 4])
        #expect(columns.values.allSatisfy { $0.allSatisfy(\.isFinite) })
    }

    @Test func aNegativePolynomialOrderHasNoColumnNotATrap() {
        let s = FitSettings(elements: ["Fe"], resolutionMnKaEV: 130, beamEnergy: 200, fitFrom: 0.2, fitTo: 19,
                            background: .polynomial(order: -1))
        let counts = [Double](repeating: 10, count: Self.axis.size)
        // Refused or fitted; never a trap.
        _ = try? EDSFit.run(counts: counts, axis: Self.axis, settings: s)
    }

    @Test func aChannelRangePastTheSpectrumIsRefused() {
        let s = FitSettings.standard(elements: ["Fe"], axis: Self.axis, resolutionMnKaEV: 130, beamEnergy: 200)
        let counts = [Double](repeating: 10, count: Self.axis.size)
        #expect(throws: EDSFitError.noChannels) { try EDSFit.run(counts: counts, axis: Self.axis, settings: s, channels: 1900..<2100) }
        #expect(throws: EDSFitError.noChannels) { try EDSFit.run(counts: counts, axis: Self.axis, settings: s, channels: -5..<100) }
        #expect(throws: EDSFitError.noChannels) {
            try EDSSumEscapeFit.run(counts: counts, axis: Self.axis, settings: s, model: .both, channels: 1900..<2100)
        }
    }

    @Test func aDecodedLineTailIsClampedAsATypedOne() throws {
        let json = Data(#"{"fraction": -1, "slopeKeV": 0, "source": "saved"}"#.utf8)
        let tail = try JSONDecoder().decode(LineTail.self, from: json)
        #expect(tail.fraction == 0)
        #expect(tail.slopeKeV == 0.001)
        #expect(tail.source == "saved")
        let typed = LineTail(fraction: 0.1, slopeKeV: 0.2, source: "t")
        #expect(try JSONDecoder().decode(LineTail.self, from: JSONEncoder().encode(typed)) == typed)
    }

    // MARK: Proposer

    @Test func aNaNResolutionOrScaleGivesTheNarrowestWidth() {
        #expect(IdentificationLoop.widths(energies: [1, 5], scale: .nan, resolutionMnKaEV: 130) == [3, 3])
        #expect(IdentificationLoop.widths(energies: [1, 5], scale: 0.01, resolutionMnKaEV: .nan) == [3, 3])
        #expect(IdentificationLoop.widths(energies: [5], scale: 0.01, resolutionMnKaEV: 130).allSatisfy { $0 > 3 })
    }

    // MARK: Regions and counts

    @Test func aPolygonWithANaNOrFarVertexAndANegativeOrHugeGridHoldNoTrap() {
        let shape = SpectrumRegionShape.polygon([PixelPoint(x: .nan, y: 1), PixelPoint(x: 1e300, y: 2), PixelPoint(x: 3, y: -1e300)])
        _ = shape.bounds
        #expect(shape.mask(nx: 4, ny: 4).count == 16)
        #expect(shape.mask(nx: -1, ny: 4).isEmpty)
        #expect(shape.mask(nx: Int.max, ny: 2).isEmpty)
        let square = SpectrumRegionShape.rectangle(PixelRect(x0: 0, y0: 0, x1: 2, y1: 2))
        #expect(square.mask(nx: 2, ny: 2) == [true, true, true, true])
    }

    @Test func aGroupedCountThatIsNotANumberIsWrittenAsOne() {
        #expect(UnlistedLineChecker.grouped(.nan) == "nan")
        #expect(UnlistedLineChecker.grouped(.infinity) == "inf")
        #expect(UnlistedLineChecker.grouped(44913) == "44 913")
    }

    @Test func mapsWhoseSizeOverflowsAreRefusedBeforeAnyCount() {
        let setup = EDXQuantificationSetup(elements: ["Fe", "Ni"], method: .cliffLorimer(kFactors: [1, 1.1], thicknessNm: nil))
        #expect(throws: QuantError.self) {
            try EDXQuantification.quantifyMaps(intensityMaps: [[1], [1]], rows: Int.max, columns: 2, setup: setup)
        }
        #expect(throws: QuantError.self) {
            try EDXQuantification.quantifyMapsWithSigma(intensityMaps: [[1], [1]], rows: Int.max, columns: 2, setup: setup)
        }
        #expect(throws: QuantError.self) {
            try EDXQuantification.quantifyMapsWithSigma(intensityMaps: [[1], [1]], rows: -1, columns: -1, setup: setup)
        }
    }

    // MARK: Export

    @Test func aTypedLineBreakNeverEndsAHeaderLine() {
        #expect(SpectroscopyExport.oneLine("Region\n1") == "Region 1")
        #expect(SpectroscopyExport.oneLine("a\r\nb\rc\u{2028}d") == "a b c d")
        #expect(SpectroscopyExport.oneLine("plain") == "plain")
    }
}
