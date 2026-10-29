//
//  DefaultWindowTests.swift
//  Role: the default pre-edge window of the ratio method as two numbers,
//        (50, 5) eV below the onset today. The default call is the old call; another pair moves the window and the answer.
//

import Foundation
import Testing
import SpectroEELS

struct DefaultWindowTests {

    @Test func testTheDefaultWindowIsTheOldOneAndTheOffsetsMoveIt() {
        #expect(EELSEdgeQuantification.defaultBackgroundWindow(onsetEV: 284) == 234...279)
        #expect(EELSEdgeQuantification.defaultBackgroundWindow(onsetEV: 284, belowOnsetEV: 50, gapEV: 5) == 234...279)
        #expect(EELSEdgeQuantification.defaultBackgroundWindow(onsetEV: 284, belowOnsetEV: 80, gapEV: 10) == 204...274)
        #expect(EELSEdgeQuantification.defaultBackgroundWindow(onsetEV: 401, belowOnsetEV: 40, gapEV: 0) == 361...401)
    }

    /// A one-pixel core-loss image: a power law plus an exponentially falling edge from 284 eV, with its low-loss.
    private func run(window: ClosedRange<Double>?) throws -> ArealDensityMap {
        let channels = 900, scale = 0.5, offset = 150.0
        let core = (0..<channels).map { i -> Double in
            let e = offset + scale * Double(i)
            return 2e9 * pow(e, -3.2) * scale + (e >= 284 ? 40 * exp(-(e - 284) / 60) : 0) + 0.3 * sin(e)   // ripple: the window matters
        }
        let ci = try CoreLossSpectrumImage(nx: 1, ny: 1, channels: channels, counts: core, energyOffsetEV: offset, energyScaleEV: scale)
        let low = (0..<200).map { i -> Double in 1e6 * exp(-pow((Double(i) - 20) / 3, 2)) + 50 }
        let li = try LowLossSpectrumImage(nx: 1, ny: 1, channels: 200, counts: low, energyOffsetEV: -10, energyScaleEV: 1)
        return try EELSEdgeQuantification.ratioMethod(
            coreLoss: ci, edge: .carbonK, microscope: EELSMicroscope(beamEnergyKeV: 200, convergenceMrad: 0, collectionMrad: 20),
            lowLoss: .integratedToWidth(li), backgroundWindowEV: window)
    }

    @Test func testTheRatioMethodUsesTheWindowItIsGiven() throws {
        let plain = try run(window: nil)
        let named = try run(window: EELSEdgeQuantification.defaultBackgroundWindow(onsetEV: 284))
        #expect(plain.pixels[0].atomsPerNM2 == named.pixels[0].atomsPerNM2 && plain.backgroundWindowEV == named.backgroundWindowEV)
        let far = try run(window: EELSEdgeQuantification.defaultBackgroundWindow(onsetEV: 284, belowOnsetEV: 80, gapEV: 10))
        #expect(abs(far.backgroundWindowEV.lowerBound - 204) <= 0.5 && abs(far.backgroundWindowEV.upperBound - 274) <= 0.5)
        #expect(far.pixels[0].atomsPerNM2 != plain.pixels[0].atomsPerNM2)
        #expect(abs(plain.backgroundWindowEV.lowerBound - 234) <= 0.5)
    }
}
