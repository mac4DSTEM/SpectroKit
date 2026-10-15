//
//  LineScanTruthTests.swift
//  Role: Gate 4 of the registration (section 7, confirmed in section 9 item 5): exSpy's own simulated line scan
//        (EELS_LL_linescan_simulated_thickness_variation.hspy and its zero-loss twin, 17 spectra, planted t/lambda 0.3, 0.4,
//        ..., 1.9), axis binned. The port reproduces exSpy's values (gate 1), so it makes the same errors against the planted
//        truth; the numbers below were registered before any code (by running exSpy at the pin).
//

import Foundation
import Testing
import SpectroEELS

struct LineScanTruthTests {

    private var truth: [Double] { EELSFixtures.pinCase("exspy-linescan").truthTOverLambda }

    private func maxError(_ map: ThicknessMap) -> Double {
        (0..<17).map { abs(map.pixels[$0].tOverLambda.orFail() - truth[$0]) }.max()!
    }

    /// Estimated threshold: 4.5 eV for pixels 0 to 10 and 4.0 eV for 11 to 16; max |t/lambda - truth| 0.004116631.
    @Test func testEstimatedThresholdOnTheLineScan() throws {
        let map = try EELSThickness.logRatio(try EELSFixtures.image("exspy-linescan"), threshold: .estimated())
        let e = maxError(map)
        print("EELS-REPORT line scan, estimated: max |t/lambda - truth| = \(e) (registered 0.004116631)")
        #expect(isEqual(e, 0.004116631, accuracy: 1e-6))
        for p in 0..<17 { #expect(isEqual(map.pixels[p].thresholdEV.orFail(), p <= 10 ? 4.5 : 4.0, accuracy: 1e-12), "pixel \(p)") }
        #expect(isEqual(e, EELSFixtures.pins.cases[2].estimated.tOverLambda.enumerated().map { abs($0.element! - truth[$0.offset]) }.max()!, accuracy: 1e-12))
    }

    @Test func testFixedThresholdOnTheLineScan() throws {
        let map = try EELSThickness.logRatio(try EELSFixtures.image("exspy-linescan"), threshold: .fixed(4.5))
        let e = maxError(map)
        print("EELS-REPORT line scan, fixed 4.5 eV: max |t/lambda - truth| = \(e) (registered 0.004401503)")
        #expect(isEqual(e, 0.004401503, accuracy: 1e-6))
    }

    @Test func testZeroLossSpectrumRouteOnTheLineScan() throws {
        let map = try EELSThickness.logRatio(try EELSFixtures.image("exspy-linescan"), zeroLoss: try EELSFixtures.lineScanZeroLoss())
        let e = maxError(map)
        print("EELS-REPORT line scan, zero-loss spectrum: max |t/lambda - truth| = \(e) (registered 0.003760360)")
        #expect(isEqual(e, 0.003760360, accuracy: 1e-6))
    }

    /// The line scan is a 17 x 1 image of 1024 channels; the pixel order is the x order.
    @Test func testTheTruthRisesWithThePixelIndex() throws {
        let map = try EELSThickness.logRatio(try EELSFixtures.image("exspy-linescan"), threshold: .fixed(4.5))
        for p in 1..<17 { #expect(map.pixels[p].tOverLambda.orFail() > map.pixels[p - 1].tOverLambda.orFail()) }
        #expect(map.nx == 17); #expect(map.ny == 1)
    }
}
