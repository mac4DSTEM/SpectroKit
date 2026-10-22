//
//  RLMLLSSpeedTests.swift
//  Role: Timings for the nightly (printed, not asserted): Richardson-Lucy and the MLLS fit on images of the size the apps open.
//

import Foundation
import Testing
import SpectroTestSupport
import SpectroEELS

struct RLMLLSSpeedTests {
    /// 32 x 32 spectra of 2048 channels, a shared PSF, 15 iterations (exSpy's default).
    @Test func testRichardsonLucySpeed() throws {
        let n = 2048, pixels = 1024
        let psfValues = (0 ..< n).map { exp(-0.5 * pow((Double($0) - 100) / 4, 2)) }
        let sum = psfValues.reduce(0, +)
        let psf = try CoreLossSpectrumImage(nx: 1, ny: 1, channels: n, counts: psfValues.map { $0 / sum }, energyOffsetEV: 0, energyScaleEV: 0.1)
        var counts = [Double](); counts.reserveCapacity(pixels * n)
        for p in 0 ..< pixels { for c in 0 ..< n { counts.append(5 + Double(p % 7) + 300 * exp(-0.5 * pow((Double(c) - 700) / 6, 2))) } }
        let image = try CoreLossSpectrumImage(nx: 32, ny: 32, channels: n, counts: counts, energyOffsetEV: 0, energyScaleEV: 0.1)
        let start = Date()
        let out = try EELSDeconvolution.richardsonLucy(image, psf: psf)
        print("richardson_lucy, 32 x 32 x 2048 channels, 15 iterations, shared PSF: \(Date().timeIntervalSince(start)) s")
        #expect(out.unavailable.allSatisfy { $0 == nil })
    }

    /// The noisy Fe L image tiled to 64 x 64 pixels of 600 channels, exponent from the two-area method.
    @Test func testMLLSSpeed() throws {
        let c = try MLLSPinsTests.cases().first { $0.key == "fel.full.twoArea" }!
        var counts = [Double]()
        for p in 0 ..< 4096 { counts += c.core.counts[(p % 6) * 600 ..< (p % 6 + 1) * 600] }
        let image = try CoreLossSpectrumImage(nx: 64, ny: 64, channels: 600, counts: counts, energyOffsetEV: c.core.energyOffsetEV, energyScaleEV: c.core.energyScaleEV)
        let start = Date()
        let result = try EELSMLLS.fit(coreLoss: image, edges: c.edges, microscope: c.microscope)
        print("MLLS fit, 64 x 64 x 600 channels, one twin pair, two-area exponent: \(Date().timeIntervalSince(start)) s")
        #expect(result.pixels.count == 4096 && result.pixels.allSatisfy { $0.unavailable == nil })
    }
}
