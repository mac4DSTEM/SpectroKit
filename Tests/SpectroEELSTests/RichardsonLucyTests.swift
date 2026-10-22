//
//  RichardsonLucyTests.swift
//  Role: SpectroKit 0.10.0, fast target: Richardson-Lucy deconvolution against planted truth (blurred peaks come back sharper, flux is kept, a
//        delta PSF is the identity, zero iterations return the input), a hand-computed iteration, the pixel reasons and the refusals.
//        The exSpy pins are in SpectroKitParityTests/RichardsonLucyPinsTests.
//

import Foundation
import Testing
import SpectroEELS

struct RichardsonLucyTests {

    private func gaussian(_ n: Int, centre: Double, sigma: Double) -> [Double] {
        let g = (0 ..< n).map { exp(-0.5 * pow((Double($0) - centre) / sigma, 2)) }
        let sum = g.reduce(0, +)
        return g.map { $0 / sum }
    }

    /// np.convolve(psf, x)[imax : imax + n]
    private func blur(_ x: [Double], psf: [Double]) -> [Double] {
        let n = x.count
        let imax = psf.indices.max { psf[$0] < psf[$1] }!
        var full = [Double](repeating: 0, count: 2 * n - 1)
        for i in 0 ..< n { for j in 0 ..< n { full[i + j] += psf[i] * x[j] } }
        return Array(full[imax ..< imax + n])
    }

    private func lowLoss(_ rows: [[Double]], nx: Int, ny: Int) throws -> LowLossSpectrumImage {
        try LowLossSpectrumImage(nx: nx, ny: ny, channels: rows[0].count, counts: rows.flatMap { $0 }, energyOffsetEV: -5, energyScaleEV: 0.1)
    }

    /// Two peaks 10 channels apart (sigma 2), blurred by a 3-channel-sigma PSF into one hump: the iteration pulls them apart again and keeps the flux.
    @Test func testBlurredPeaksComeBackSharper() throws {
        let n = 200
        let truth: [Double] = (0 ..< n).map { c in
            let x = Double(c)
            return 1 + 400 * exp(-0.5 * pow((x - 90) / 2, 2)) + 600 * exp(-0.5 * pow((x - 100) / 2, 2))
        }
        let psf = gaussian(n, centre: 60, sigma: 3)
        let blurred = blur(truth, psf: psf)
        let out = try EELSDeconvolution.richardsonLucy(try lowLoss([blurred], nx: 1, ny: 1), psf: try lowLoss([psf], nx: 1, ny: 1),
                                                       options: RichardsonLucyOptions(iterations: 300))
        #expect(out.unavailable == [nil] && out.fftSize == 0 && out.taperedChannels == 0)
        let r = out.image.counts
        // the height of the stronger peak rises a lot, and the valley between the peaks opens
        #expect(r[100] > 1.5 * blurred[100])
        #expect(abs(r[100] - truth[100]) < 0.1 * truth[100])
        #expect(r[100] > 2 * r[95])
        // against the truth the error shrinks compared with the blurred spectrum
        func error(_ x: [Double]) -> Double { zip(x, truth).map { abs($0 - $1) }.reduce(0, +) }
        #expect(error(r) < 0.2 * error(blurred), Comment(rawValue: "\(error(r)) against \(error(blurred))"))
        // Richardson-Lucy conserves the total (unit-area PSF, interior spectrum)
        let fluxOut: Double = r.reduce(0, +), fluxIn: Double = blurred.reduce(0, +)
        #expect(abs(fluxOut - fluxIn) < 1e-6 * fluxIn)
        #expect(r.allSatisfy { $0 >= 0 })
        #expect(out.image.energyOffsetEV == -5 && out.image.energyScaleEV == 0.1 && out.image.channels == n)
    }

    /// One iteration by hand on a four-channel spectrum (exSpy's two slices of the full convolutions).
    @Test func testOneIterationByHand() throws {
        let signal = [2.0, 4.0, 3.0, 1.0]
        let psf = [0.25, 0.5, 0.25, 0.0]              // imax = 1
        // first = conv(psf, signal)[1:5]
        let first = [0.25 * 4 + 0.5 * 2, 0.25 * 3 + 0.5 * 4 + 0.25 * 2, 0.25 * 1 + 0.5 * 3 + 0.25 * 4, 0.5 * 1 + 0.25 * 3]
        let ratio = zip(signal, first).map { $0 / $1 }
        // conv(psf reversed = [0, .25, .5, .25], ratio)[mimax = 2 : 6]
        let rev = [0.0, 0.25, 0.5, 0.25]
        var full = [Double](repeating: 0, count: 7)
        for i in 0 ..< 4 { for j in 0 ..< 4 { full[i + j] += rev[i] * ratio[j] } }
        let want = (0 ..< 4).map { signal[$0] * full[2 + $0] }
        let out = try EELSDeconvolution.richardsonLucy(try lowLoss([signal], nx: 1, ny: 1), psf: try lowLoss([psf], nx: 1, ny: 1),
                                                       options: RichardsonLucyOptions(iterations: 1))
        for c in 0 ..< 4 { #expect(abs(out.image.counts[c] - want[c]) < 1e-14, Comment(rawValue: "channel \(c): \(out.image.counts[c]) vs \(want[c])")) }
    }

    @Test func testDeltaPSFAndZeroIterationsAreTheIdentity() throws {
        let signal = (0 ..< 50).map { 3 + 2 * sin(Double($0) / 4) }
        var delta = [Double](repeating: 0, count: 50); delta[7] = 1
        let image = try lowLoss([signal], nx: 1, ny: 1)
        let viaDelta = try EELSDeconvolution.richardsonLucy(image, psf: try lowLoss([delta], nx: 1, ny: 1), options: RichardsonLucyOptions(iterations: 25))
        for c in 0 ..< 50 { #expect(abs(viaDelta.image.counts[c] - signal[c]) < 1e-12) }
        let psf = gaussian(50, centre: 20, sigma: 2)
        let zero = try EELSDeconvolution.richardsonLucy(image, psf: try lowLoss([psf], nx: 1, ny: 1), options: RichardsonLucyOptions(iterations: 0))
        #expect(zero.image.counts == signal)
    }

    /// A shared one-pixel PSF and one PSF per pixel agree when the PSFs are the same; pixels are independent.
    @Test func testSharedAndPerPixelPSF() throws {
        let n = 80
        let psf = gaussian(n, centre: 30, sigma: 2.5)
        let rows = (0 ..< 6).map { p in blur((0 ..< n).map { 2 + Double(p) + 50 * exp(-0.5 * pow((Double($0) - 40) / 2, 2)) }, psf: psf) }
        let image = try lowLoss(rows, nx: 3, ny: 2)
        let shared = try EELSDeconvolution.richardsonLucy(image, psf: try lowLoss([psf], nx: 1, ny: 1))
        let each = try EELSDeconvolution.richardsonLucy(image, psf: try lowLoss([[Double]](repeating: psf, count: 6), nx: 3, ny: 2))
        #expect(shared.image.counts == each.image.counts)
        #expect(shared.methodName.contains("15 iterations"))
        // one pixel on its own gives the same numbers
        let single = try EELSDeconvolution.richardsonLucy(try lowLoss([rows[4]], nx: 1, ny: 1), psf: try lowLoss([psf], nx: 1, ny: 1))
        #expect(Array(shared.image.counts[4 * n ..< 5 * n]) == single.image.counts)
    }

    /// A zero denominator over a zero signal (0 / 0) is NaN in exSpy; here the pixel is zeros with its reason, and the others are untouched.
    @Test func testNonFinitePixelIsUnavailable() throws {
        let n = 120
        var psfValues = (0 ..< n).map { exp(-0.5 * pow((Double($0) - 30) / 1.0, 2)) }     // underflows to exactly 0 far from the centre
        let s = psfValues.reduce(0, +); psfValues = psfValues.map { $0 / s }
        var bad = blur((0 ..< n).map { 5 + Double($0 % 3) }, psf: psfValues)
        for c in 60 ..< n { bad[c] = 0 }
        let good = blur((0 ..< n).map { 5 + Double($0 % 3) }, psf: psfValues)
        let out = try EELSDeconvolution.richardsonLucy(try lowLoss([bad, good], nx: 2, ny: 1), psf: try lowLoss([psfValues], nx: 1, ny: 1))
        #expect(out.unavailable[0] == .divisionByZero)
        #expect(out.unavailable[1] == nil)
        #expect(out.image.counts[0 ..< n].allSatisfy { $0 == 0 })
        #expect(out.image.counts[n ..< 2 * n].allSatisfy { $0.isFinite && $0 > 0 })
    }

    @Test func testRefusals() throws {
        let image = try lowLoss([[1, 2, 3, 4, 5, 6], [1, 2, 3, 4, 5, 6]], nx: 2, ny: 1)
        let psf = try lowLoss([[0, 1, 0, 0, 0, 0]], nx: 1, ny: 1)
        #expect(throws: EELSDeconvolutionError.invalidIterations(-1)) {
            try EELSDeconvolution.richardsonLucy(image, psf: psf, options: RichardsonLucyOptions(iterations: -1))
        }
        let short = try lowLoss([[0, 1, 0, 0, 0]], nx: 1, ny: 1)
        #expect(throws: EELSDeconvolutionError.kernelSizeMismatch(expected: 6, got: 5)) {
            try EELSDeconvolution.richardsonLucy(image, psf: short)
        }
        let three = try lowLoss([[0, 1, 0, 0, 0, 0], [0, 1, 0, 0, 0, 0], [0, 1, 0, 0, 0, 0]], nx: 3, ny: 1)
        #expect(throws: EELSDeconvolutionError.shapeMismatch(expected: 2, got: 3)) {
            try EELSDeconvolution.richardsonLucy(image, psf: three)
        }
    }

    /// Cancellation between waves is honoured.
    @Test func testCancellation() throws {
        let n = 64
        let psf = gaussian(n, centre: 20, sigma: 2)
        let rows = [[Double]](repeating: (0 ..< n).map { 1 + Double($0 % 5) }, count: 600)
        let image = try lowLoss(rows, nx: 600, ny: 1)
        #expect(throws: (any Error).self) {
            try EELSDeconvolution.richardsonLucy(image, psf: try lowLoss([psf], nx: 1, ny: 1), cancelled: { true })
        }
    }
}
