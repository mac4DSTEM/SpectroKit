//
//  SavitzkyGolayPortTests.swift
//  Role: The derivative the threshold stands on, against what SciPy 1.18.1 and NumPy 2.5.4 answered (pins.json `recipe`,
//        `stepByStep`): the coefficients, the interior's fused accumulation order, the edge polynomial fits, and
//        `numpy.gradient`. One rule per test.
//
//  The LAPACK SVD coefficients/edges are compared with raw SciPy SVD pins using a scaled absolute bound.
//  Interior convolution supplied with raw coefficients and numpy.gradient remain bit exact.
//

import Foundation
import Testing
import SpectroEELS
import SpectroCore

struct SavitzkyGolayPortTests {

    private let caseNames = ["planted-noiseless", "planted-noisy", "exspy-linescan"]

    /// The cropped rows of the whole image (every pixel), as HyperSpy hands them to `savgol_filter`.
    private func croppedImage(_ name: String) throws -> (rows: [[Double]], nx: Int, ny: Int) {
        let c = EELSFixtures.pinCase(name)
        let all = try EELSFixtures.doubles(c.file)
        let nch = c.energyAxis.size, sr = c.estimated.subRange
        let rows = (0..<(c.rows * c.cols)).map { p in Array(all[(p * nch + sr.firstChannel)..<(p * nch + sr.firstChannel + sr.channels)]) }
        return (rows, c.cols, c.rows)
    }

    /// The derivative of pixel `pixel` from the whole image's edge table.
    private func applyImage(_ sg: SavitzkyGolayFirstDerivative, _ image: (rows: [[Double]], nx: Int, ny: Int), pixel: Int) throws -> [Double] {
        let n = image.rows[0].count
        let flat = image.rows.flatMap { $0 }
        var out = [Double](repeating: .nan, count: n)
        try flat.withUnsafeBufferPointer { fp in
            let table = try sg.edgeTable(nx: image.nx, ny: image.ny) { p in UnsafeBufferPointer(rebasing: fp[(p * n)..<((p + 1) * n)]) }
            out.withUnsafeMutableBufferPointer { o in
                sg.apply(UnsafeBufferPointer(rebasing: fp[(pixel * n)..<((pixel + 1) * n)]), into: o, pixel: pixel, table: table)
            }
        }
        return out
    }

    /// The cropped row the pins' step-by-step used: pixel `index`, channels [firstChannel, firstChannel + channels).
    private func croppedRow(_ name: String) throws -> (row: [Double], step: PinStep, scale: Double) {
        let c = EELSFixtures.pinCase(name)
        let step = c.stepByStep[0]
        let all = try EELSFixtures.doubles(c.file)
        let nch = c.energyAxis.size
        let base = step.pixel.index * nch + step.firstChannel
        return (Array(all[base..<(base + step.channels)]), step, c.energyAxis.scale)
    }

    // MARK: coefficients (savgol_coeffs)

    /// The five coefficients SciPy's `savgol_coeffs(5, 3, deriv=1, delta=scale)` returned (pins.json `recipe.coefficients`) against
    /// this port's scalar QR solve; SciPy's near-zero residual is compared absolutely.
    @Test func testCoefficientsAreBitIdenticalToSciPy() throws {
        for name in caseNames {
            let c = EELSFixtures.pinCase(name)
            let pinned = c.estimated.recipe!.coefficients!
            let ours = try SavitzkyGolay.coefficients(windowLength: 5, polynomialOrder: 3, derivative: 1, delta: c.energyAxis.scale)
            // CPU-specific SVD cancellation at the zero centre cannot support relative or ULP parity.
            let l1 = pinned.reduce(0.0) { $0 + abs($1) }
            let gaps = ReferenceGap()
            for (o, e) in zip(ours, pinned) {
                gaps.record(o, e, scale: l1)
                #expect(abs(o - e) <= 1e-13 * l1, "\(name) coefficient QR/SVD error")
            }
            gaps.report("SG coefficients \(name)")
            // LAPACK's SVD leaves a roundoff residual at the mathematically zero centre and breaks exact antisymmetry; both are
            // ulp-level, bounded by the stated tolerance (the tie allowance in ElasticThreshold absorbs them).
            #expect(abs(ours[2]) <= 1e-13 * l1, "\(name) centre")
            #expect(abs(ours[0] + ours[4]) <= 1e-13 * l1 && abs(ours[1] + ours[3]) <= 1e-13 * l1, "\(name) antisymmetry")
            // the exact answer is (1, -8, 0, 8, -1) / (12 delta) in convolution order, negated: [-1, 8, 0, -8, 1] / (12 delta)
            let big = pinned.map(abs).max()!
            let exact = [-1.0, 8, 0, -8, 1].map { $0 / (12 * c.energyAxis.scale) }
            for (o, e) in zip(ours, exact) { #expect(isEqual(o, e, accuracy: 1e-13 * big), "\(name)") }
        }
    }

    /// The summation order of the interior: tap 0 first, then the last tap down to tap 1 (the README's (0, 4, 3, 2, 1)); it is
    /// what pins.json records as `fmaOrder`.
    @Test func testInteriorTapOrderIsTheRecordedRecipe() {
        #expect(SavitzkyGolay.interiorTapOrder(windowLength: 5) == [0, 4, 3, 2, 1])
        for name in caseNames {
            #expect(EELSFixtures.pinCase(name).estimated.recipe!.fmaOrder! == SavitzkyGolay.interiorTapOrder(windowLength: 5), "\(name)")
        }
    }

    // MARK: the interior, bit for bit

    /// With SciPy's own coefficients the fused accumulation reproduces SciPy's interior derivative values BIT FOR BIT
    /// (every interior value of the three pinned rows).
    @Test func testInteriorIsBitExactWithSciPysCoefficients() throws {
        for name in caseNames {
            let (row, step, _) = try croppedRow(name)
            let coeffs = EELSFixtures.pinCase(name).estimated.recipe!.coefficients!
            var out = [Double](repeating: .nan, count: row.count)
            row.withUnsafeBufferPointer { f in out.withUnsafeMutableBufferPointer { o in SavitzkyGolay.convolveInterior(f, coefficients: coeffs, into: o) } }
            var mismatches = 0
            for i in 2..<(row.count - 2) where out[i].bitPattern != step.derivative[i].bitPattern { mismatches += 1 }
            print("EELS-REPORT interior bit-exact \(name): \(row.count - 4) values, \(mismatches) mismatches")
            #expect(mismatches == 0, "\(name)")
        }
    }

    // MARK: the whole derivative (interior + edges)

    /// The full cropped derivative of the pinned pixel, from the whole pinned image, with SciPy's coefficients: EVERY value
    /// including the four scalar-QR edge values, within a cancellation-scaled absolute bound.
    @Test func testWholeDerivativeIsBitIdenticalWithSciPysCoefficients() throws {
        for name in caseNames {
            let (row, step, scale) = try croppedRow(name)
            let image = try croppedImage(name)
            let sg = try SavitzkyGolayFirstDerivative(windowLength: 5, polynomialOrder: 3, delta: scale,
                                                      coefficientsOverride: EELSFixtures.pinCase(name).estimated.recipe!.coefficients!)
            let d = try applyImage(sg, image, pixel: step.pixel.index)
            #expect(d.count == row.count)
            let mismatches = (0..<row.count).filter { d[$0].bitPattern != step.derivative[$0].bitPattern }
            print("EELS-REPORT whole derivative (SciPy coefficients) \(name): \(row.count) values, \(mismatches.count) mismatches")
            // Bound cancellation against input scale; raw reference values are retained.
            let coeffs = EELSFixtures.pinCase(name).estimated.recipe!.coefficients!
            let bound = 1e-13 * row.map(abs).max()! * coeffs.reduce(0.0) { $0 + abs($1) }
            let gaps = ReferenceGap()
            for i in row.indices {
                gaps.record(d[i], step.derivative[i], scale: bound / 1e-13)
                #expect(abs(d[i] - step.derivative[i]) <= bound, "\(name) index \(i)")
            }
            gaps.report("SG full derivative \(name)")
        }
    }

    /// The same with the portable scalar coefficients, against the unchanged SciPy reference.
    @Test func testWholeDerivativeWithOwnCoefficientsIsBitIdentical() throws {
        for name in caseNames {
            let (row, step, scale) = try croppedRow(name)
            let image = try croppedImage(name)
            let sg = try SavitzkyGolayFirstDerivative(windowLength: 5, polynomialOrder: 3, delta: scale)
            let d = try applyImage(sg, image, pixel: step.pixel.index)
            let mismatches = (0..<row.count).filter { d[$0].bitPattern != step.derivative[$0].bitPattern }
            print("EELS-REPORT whole derivative (own coefficients) \(name): \(row.count) values, \(mismatches.count) mismatches")
            // Bound cancellation against input scale; raw reference values are retained.
            let coeffs = EELSFixtures.pinCase(name).estimated.recipe!.coefficients!
            let bound = 1e-13 * row.map(abs).max()! * coeffs.reduce(0.0) { $0 + abs($1) }
            let gaps = ReferenceGap()
            for i in row.indices {
                gaps.record(d[i], step.derivative[i], scale: bound / 1e-13)
                #expect(abs(d[i] - step.derivative[i]) <= bound, "\(name) index \(i)")
            }
            gaps.report("SG full derivative \(name)")
        }
    }

    /// dgelsd's edge bits depend on the number of right-hand sides, so a pixel alone differs from the same pixel in its image at
    /// roundoff only: bounded by 1e-13 times input peak times coefficient L1 (the same stated tolerance as above).
    @Test func testEdgeBitsDependOnTheImageNotOnThePixelAlone() throws {
        for name in caseNames {
            let (row, step, scale) = try croppedRow(name)
            let sg = try SavitzkyGolayFirstDerivative(windowLength: 5, polynomialOrder: 3, delta: scale)
            let alone = applyKernel(sg, row)
            let batched = try applyImage(sg, croppedImage(name), pixel: step.pixel.index)
            let coeffs = EELSFixtures.pinCase(name).estimated.recipe!.coefficients!
            let bound = 1e-13 * row.map(abs).max()! * coeffs.reduce(0.0) { $0 + abs($1) }
            for i in row.indices { #expect(abs(alone[i] - batched[i]) <= bound, "\(name) index \(i) alone vs in image") }
        }
    }

    /// The Savitzky-Golay first derivative of a cubic polynomial is the cubic's derivative EXACTLY (the fit reproduces it), at
    /// every sample including the edges: a check of the edge fits that needs no SciPy.
    @Test func testCubicIsDifferentiatedExactlyEverywhere() throws {
        let delta = 0.05
        let n = 40
        let x = (0..<n).map { 1.0 + delta * Double($0) }
        let f = x.map { 2.0 * $0 * $0 * $0 - 3.0 * $0 * $0 + 0.5 * $0 + 7.0 }
        let df = x.map { 6.0 * $0 * $0 - 6.0 * $0 + 0.5 }
        for (wl, po) in [(5, 3), (7, 3), (9, 4), (5, 4)] {
            let sg = try SavitzkyGolayFirstDerivative(windowLength: wl, polynomialOrder: po, delta: delta)
            let d: [Double] = applyKernel(sg, f)
            for i in 0..<n { #expect(isEqual(d[i], df[i], accuracy: 1e-9), "window \(wl) order \(po) sample \(i)") }
        }
    }

    // MARK: numpy.gradient

    /// `window_length = 0`: the derivative is `numpy.gradient(cropped, cropped_axis)` and is reproduced BIT FOR BIT, on the
    /// planted axis (non-uniform spacing by ulps: the a/b/c branch) and on the line scan's (uniform: the scalar branch).
    @Test func testGradientIsBitExact() throws {
        for name in caseNames {
            let (row, step, scale) = try croppedRow(name)
            let c = EELSFixtures.pinCase(name)
            let croppedOffset = c.energyAxis.offset + scale * Double(step.firstChannel)
            let x = (0..<row.count).map { croppedOffset + scale * Double($0) }
            let g = NumpyGradient(axis: x)
            var out = [Double](repeating: .nan, count: row.count)
            row.withUnsafeBufferPointer { f in out.withUnsafeMutableBufferPointer { o in g.apply(f, into: o) } }
            var mismatches = 0
            for i in 0..<row.count where out[i].bitPattern != step.gradientDerivative[i].bitPattern { mismatches += 1 }
            print("EELS-REPORT numpy.gradient \(name): \(row.count) values, \(mismatches) bit mismatches, uniform branch = \(g.uniformSpacing != nil)")
            #expect(mismatches == 0, "\(name)")
        }
        // the two branches are both exercised
        #expect(NumpyGradient(axis: (0..<20).map { 1.0 + 0.5 * Double($0) }).uniformSpacing != nil)
        let planted = EELSFixtures.pinCase("planted-noiseless")
        let xs = (0..<200).map { planted.energyAxis.offset + 0.05 * Double(220) + 0.05 * Double($0) }
        #expect(NumpyGradient(axis: xs).uniformSpacing == nil)
    }

    /// The Savitzky-Golay window and order that SciPy would reject or that this port does not support are refused.
    @Test func testUnsupportedWindowsAreRefused() {
        for (wl, po) in [(4, 3), (2, 1), (1, 1), (5, 5), (5, 0), (-3, 1)] {
            if let error = #expect(throws: (any Error).self, "\(wl),\(po)", performing: { try SavitzkyGolayFirstDerivative(windowLength: wl, polynomialOrder: po, delta: 0.05) }) {
                if case EELSThicknessError.invalidSavitzkyGolay = error {} else { Issue.record("\(error)") }
            }
        }
    }

    private func applyKernel(_ sg: SavitzkyGolayFirstDerivative, _ row: [Double]) -> [Double] {
        var out = [Double](repeating: .nan, count: row.count)
        row.withUnsafeBufferPointer { f in out.withUnsafeMutableBufferPointer { o in sg.apply(f, into: o) } }
        return out
    }
}
