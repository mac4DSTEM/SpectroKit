//
//  EdgeEdgeCaseTests.swift
//  Role: EELS slice 2's inputs the method refuses and pixels it cannot answer (registration section 1), the dose ratio, and
//        what every result says about itself.
//

import Foundation
import XCTest
import SpectroEELS

final class EdgeEdgeCaseTests: XCTestCase {

    func plantedR() throws -> (CoreLossSpectrumImage, LowLossSpectrumImage) {
        (try EdgeFixtures.core("edge-core-R-ss-noiseless.f64"), try EdgeFixtures.low("edge-low-R-ss-noiseless.f64"))
    }

    func testDoseRatioMultipliesILow() throws {
        let (core, low) = try plantedR()
        let m = EdgeFixtures.plantedMicroscope
        let one = try EELSEdgeQuantification.ratioMethod(coreLoss: core, microscope: m, lowLoss: .integratedToWidth(low))
        let two = try EELSEdgeQuantification.ratioMethod(coreLoss: core, microscope: m, lowLoss: .integratedToWidth(low),
                                                         coreLossToLowLossDose: 2)
        XCTAssertEqual(two.coreLossToLowLossDose, 2)
        for (a, b) in zip(one.pixels, two.pixels) {
            XCTAssertEqual(b.lowLossIntensity.orFail(), 2 * a.lowLossIntensity.orFail())
            XCTAssertEqual(b.atomsPerNM2.orFail(), a.atomsPerNM2.orFail() / 2)
            // The Poisson term of I_low is the counted low-loss (1/raw), not the dose-scaled I_low: σ_n halves exactly with n.
            XCTAssertEqual(b.sigmaCounting.orFail(), a.sigmaCounting.orFail() / 2)
        }
    }

    func testEveryResultSaysHowItWasMadeAndIsUnvalidated() throws {
        let (core, low) = try plantedR()
        let map = try EELSEdgeQuantification.ratioMethod(coreLoss: core, microscope: EdgeFixtures.plantedMicroscope,
                                                         lowLoss: .integratedToWidth(low))
        XCTAssertEqual(map.validation, "none")
        XCTAssertEqual(map.method, EELSEdgeQuantification.methodName)
        XCTAssertTrue(map.method.contains("dft GOS"))
        XCTAssertEqual(map.edge, .carbonK)
        XCTAssertEqual(map.edgeWindowEV, 284 ..< 334)
        XCTAssertEqual(map.backgroundWindowEV, 234...279)
        XCTAssertEqual(map.effectiveCollectionMrad, EdgeFixtures.pins.d("planted").x("effectiveAngleMrad"))
        XCTAssertTrue(map.lowLossRoute.contains("4.66"))
        XCTAssertNil(map.caveat)
        let o = try EELSEdgeQuantification.ratioMethod(coreLoss: core, edge: .oxygenK, microscope: EdgeFixtures.plantedMicroscope,
                                                       lowLoss: .integratedToWidth(low))
        XCTAssertTrue(o.caveat?.contains("preceding edge's tail") == true)
    }

    /// A caller's own onset moves the edge window and not the cross section's table onset (review, mutant M2).
    func testCallersOnsetMovesTheEdgeWindow() throws {
        let (core, low) = try plantedR()
        let m = try EELSEdgeQuantification.ratioMethod(coreLoss: core, microscope: EdgeFixtures.plantedMicroscope,
                                                       lowLoss: .integratedToWidth(low), edgeOnsetEV: 290)
        XCTAssertEqual(m.edgeWindowEV, 290 ..< 340)
        XCTAssertEqual(m.edgeChannels, 560 ..< 760)
        XCTAssertEqual(m.backgroundWindowEV, 240...285)
    }

    func testRefusals() throws {
        let (core, low) = try plantedR()
        let m = EdgeFixtures.plantedMicroscope
        XCTAssertThrowsError(try EELSEdgeQuantification.ratioMethod(coreLoss: core, microscope: m, lowLoss: .integratedToWidth(low),
                                                                    integrationWidthEV: 0)) {
            XCTAssertEqual($0 as? EELSEdgeError, .invalidIntegrationWidth(0))
        }
        XCTAssertThrowsError(try EELSEdgeQuantification.ratioMethod(coreLoss: core, microscope: m, lowLoss: .integratedToWidth(low),
                                                                    coreLossToLowLossDose: -1)) {
            XCTAssertEqual($0 as? EELSEdgeError, .invalidDoseRatio(-1))
        }
        XCTAssertThrowsError(try EELSEdgeQuantification.ratioMethod(
            coreLoss: core, microscope: EELSMicroscope(beamEnergyKeV: 200, convergenceMrad: 10, collectionMrad: 0),
            lowLoss: .integratedToWidth(low))) { XCTAssertEqual($0 as? EELSEdgeError, .invalidMicroscope) }
        // An edge window wholly above the axis (it ends at 650 eV) throws.
        XCTAssertThrowsError(try EELSEdgeQuantification.ratioMethod(coreLoss: core, microscope: m, lowLoss: .integratedToWidth(low),
                                                                    backgroundWindowEV: 234...279, edgeOnsetEV: 700)) {
            guard case .edgeWindowOutsideAxis = $0 as? EELSEdgeError else { return XCTFail("\($0)") }
        }
        let lowShape = try LowLossSpectrumImage(nx: 1, ny: 1, channels: low.channels, counts: Array(low.counts[0 ..< low.channels]),
                                                energyOffsetEV: low.energyOffsetEV, energyScaleEV: low.energyScaleEV)
        XCTAssertThrowsError(try EELSEdgeQuantification.ratioMethod(coreLoss: core, microscope: m, lowLoss: .integratedToWidth(lowShape))) {
            XCTAssertEqual($0 as? EELSEdgeError, .lowLossShapeMismatch(expected: 15, got: 1))
        }
        XCTAssertThrowsError(try CoreLossSpectrumImage(nx: 2, ny: 1, channels: 3, counts: [1, 2, 3, 4, 5, Double.nan],
                                                       energyOffsetEV: 0, energyScaleEV: 1)) {
            XCTAssertEqual($0 as? EELSEdgeError, .nonFiniteCounts(pixel: 1))
        }
        XCTAssertEqual(CoreLossEdge.bundled.map(\.element), ["C", "N", "O"])
        // An edge window wholly below the onset: σ_k = 0, refused (review R1), not n = ±inf.
        XCTAssertThrowsError(try EELSEdgeQuantification.ratioMethod(coreLoss: core, microscope: m, lowLoss: .integratedToWidth(low),
                                                                    backgroundWindowEV: 160...200, edgeOnsetEV: 210)) {
            XCTAssertEqual($0 as? EELSEdgeError, .crossSectionZero(edgeWindowFromEV: 210, toEV: 260))
        }
        // A background window not inside the axis: refused (review R2), where HyperSpy clamps it, below the axis to the whole
        // spectrum, a fit across the edge.
        let above = try CoreLossSpectrumImage(nx: 5, ny: 3, channels: 1000, counts: (0 ..< 15).flatMap { p in core.counts[(p * 2000 + 560) ..< (p * 2000 + 1560)] },
                                              energyOffsetEV: 290, energyScaleEV: 0.25)
        XCTAssertThrowsError(try EELSEdgeQuantification.ratioMethod(coreLoss: above, microscope: m, lowLoss: .integratedToWidth(low))) {
            XCTAssertEqual($0 as? EELSEdgeError, .backgroundWindowOutsideAxis(fromEV: 234, toEV: 279, axisFromEV: 290, axisToEV: 539.75))
        }
        XCTAssertThrowsError(try EELSEdgeQuantification.ratioMethod(coreLoss: core, microscope: m, lowLoss: .integratedToWidth(low),
                                                                    backgroundWindowEV: 140...279)) {
            guard case .backgroundWindowOutsideAxis = $0 as? EELSEdgeError else { return XCTFail("\($0)") }
        }
    }

    func testPixelsTheMethodCannotAnswer() throws {
        let (core, low) = try plantedR()
        var counts = core.counts
        // Pixel 0: no counts in the pre-edge window's first half -> I1 = 0.
        for c in 336 ..< 426 { counts[c] = 0 }
        // Pixel 1: its low-loss is all zero -> I_low = 0.
        var lowCounts = low.counts
        for c in 0 ..< low.channels { lowCounts[low.channels + c] = 0 }
        // Pixel 3: a negative low-loss (review mutant M3: `raw > 0`, not `raw != 0`).
        for c in 0 ..< low.channels { lowCounts[3 * low.channels + c] = -1 }
        let core2 = try CoreLossSpectrumImage(nx: 5, ny: 3, channels: core.channels, counts: counts,
                                              energyOffsetEV: core.energyOffsetEV, energyScaleEV: core.energyScaleEV)
        let low2 = try LowLossSpectrumImage(nx: 5, ny: 3, channels: low.channels, counts: lowCounts,
                                            energyOffsetEV: low.energyOffsetEV, energyScaleEV: low.energyScaleEV)
        let map = try EELSEdgeQuantification.ratioMethod(coreLoss: core2, microscope: EdgeFixtures.plantedMicroscope,
                                                         lowLoss: .integratedToWidth(low2))
        XCTAssertNil(map.pixels[0].atomsPerNM2)
        XCTAssertEqual(map.pixels[0].unavailable, .backgroundSumNotPositive)
        XCTAssertNil(map.pixels[1].atomsPerNM2)
        XCTAssertEqual(map.pixels[1].unavailable, .lowLossNotPositive)
        XCTAssertNotNil(map.pixels[1].powerLawR)
        XCTAssertEqual(map.pixels[3].unavailable, .lowLossNotPositive)
        XCTAssertNotNil(map.pixels[2].atomsPerNM2)
        XCTAssertNil(map.pixels[2].unavailable)
        // The I_0 route: a thickness map pixel without I_0 gives a nil with its reason.
        let tm = try EELSThickness.logRatio(low2, threshold: .fixed(4.5))
        let m0 = try EELSEdgeQuantification.ratioMethod(coreLoss: core2, microscope: EdgeFixtures.plantedMicroscope, lowLoss: .zeroLoss(tm))
        XCTAssertNotNil(m0.pixels[1].unavailable)
    }

    func testDifferentialCrossSectionIsZeroBelowTheOnsetAndAPowerLawBeyondTheTable() throws {
        let m = EdgeFixtures.plantedMicroscope
        let r = try EELSEdgeQuantification.differentialCrossSection(edge: .carbonK, microscope: m,
                                                                    energiesEV: [283.99, 284.0, 2500, 5000])
        XCTAssertEqual(r.barnPerEV[0], 0)
        XCTAssertGreaterThan(r.barnPerEV[1], 0)
        XCTAssertGreaterThan(r.barnPerEV[2], r.barnPerEV[3])     // beyond the last tabulated energy (284 + 1882 eV)
        XCTAssertGreaterThan(r.barnPerEV[3], 0)
    }
}

final class PowerLawWindowRuleTests: XCTestCase {
    /// HyperSpy's parity rule (`power_law.py:127-132`): i1 + i2 odd gives i2 − 1; the registered windows all have an even sum,
    /// so this window (234 to 279.25 eV on the planted axis: channels 336 and 517) is the one that exercises it.
    func testParityRuleAndMidpoint() throws {
        let axis = try EELSAxis(offset: 150, scale: 0.25, size: 2000)
        let w = try PowerLawWindow(axis: axis, from: 234.0, to: 279.25)
        XCTAssertEqual([w.i1, w.i2, w.i3], [336, 516, 426])
        XCTAssertEqual([w.x1, w.x2, w.x3], [234.0, 279.0, 256.5])
        let even = try PowerLawWindow(axis: axis, from: 234.0, to: 279.0)
        XCTAssertEqual([even.i1, even.i2, even.i3], [336, 516, 426])
        // i2 == i1 after the rule: i2 + 2 (`:133-134`).
        let narrow = try PowerLawWindow(axis: axis, from: 234.0, to: 234.0)
        XCTAssertEqual([narrow.i1, narrow.i2, narrow.i3], [336, 338, 337])
    }

    /// The left cutoff (`left_cutoff = 0`: the power law is 0 at x <= 0).
    func testLeftCutoff() {
        let f = PowerLawFit(i1Sum: 1, i2Sum: 1, r: 3, a: 1e9)
        XCTAssertEqual(f.counts(atEnergy: 0, scale: 0.25), 0)
        XCTAssertEqual(f.counts(atEnergy: -5, scale: 0.25), 0)
        XCTAssertGreaterThan(f.counts(atEnergy: 1e-3, scale: 0.25), 0)
    }
}
