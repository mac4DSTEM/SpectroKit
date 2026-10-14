//
//  SavitzkyGolayPortTests.swift
//  Role: The derivative the threshold stands on, against what SciPy 1.18.1 and NumPy 2.5.4 answered (pins.json `recipe`,
//        `stepByStep`): the coefficients, the interior's fused accumulation order, the edge polynomial fits, and
//        `numpy.gradient`. One rule per test.
//
//  What is asserted and what is only recorded: with SciPy's own five coefficients the interior is BIT-EXACT (the recipe).
//  With this port's coefficients (LAPACK dgelsy; SciPy used dgelsd) the interior agrees to the bound below, which is
//  derived, not fitted: coefficient noise of 1e-14 absolute times the counts in the window.
//

import Foundation
import XCTest
import SpectroEELS
import SpectroCore

final class SavitzkyGolayPortTests: XCTestCase {

    private let caseNames = ["planted-noiseless", "planted-noisy", "exspy-linescan"]

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

    /// The five coefficients SciPy's `savgol_coeffs(5, 3, deriv=1, delta=scale)` returned (pins.json `recipe.coefficients`)
    /// against this port's. Agreement to 1e-14 of the largest (dgelsy against dgelsd: both solve the same 4 x 5 system; SciPy's
    /// centre coefficient is -8.3e-15 instead of 0).
    func testCoefficientsAgreeWithSciPyToTheirNoise() throws {
        for name in caseNames {
            let c = EELSFixtures.pinCase(name)
            let pinned = c.estimated.recipe!.coefficients!
            let ours = try SavitzkyGolay.coefficients(windowLength: 5, polynomialOrder: 3, derivative: 1, delta: c.energyAxis.scale)
            let big = pinned.map(abs).max()!
            let worst = zip(ours, pinned).map { abs($0 - $1) }.max()! / big
            print("EELS-REPORT coefficients \(name): max |ours - SciPy| / max|coeff| = \(worst)")
            XCTAssertLessThan(worst, 1e-14, name)
            // the exact answer is (1, -8, 0, 8, -1) / (12 delta) in convolution order, negated: [-1, 8, 0, -8, 1] / (12 delta)
            let exact = [-1.0, 8, 0, -8, 1].map { $0 / (12 * c.energyAxis.scale) }
            for (o, e) in zip(ours, exact) { XCTAssertEqual(o, e, accuracy: 1e-13 * big, name) }
        }
    }

    /// The summation order of the interior: tap 0 first, then the last tap down to tap 1 (the README's (0, 4, 3, 2, 1)); it is
    /// what pins.json records as `fmaOrder`.
    func testInteriorTapOrderIsTheRecordedRecipe() {
        XCTAssertEqual(SavitzkyGolay.interiorTapOrder(windowLength: 5), [0, 4, 3, 2, 1])
        for name in caseNames {
            XCTAssertEqual(EELSFixtures.pinCase(name).estimated.recipe!.fmaOrder!, SavitzkyGolay.interiorTapOrder(windowLength: 5), name)
        }
    }

    // MARK: the interior, bit for bit

    /// With SciPy's own coefficients the fused accumulation reproduces SciPy's interior derivative values BIT FOR BIT
    /// (every interior value of the three pinned rows).
    func testInteriorIsBitExactWithSciPysCoefficients() throws {
        for name in caseNames {
            let (row, step, _) = try croppedRow(name)
            let coeffs = EELSFixtures.pinCase(name).estimated.recipe!.coefficients!
            var out = [Double](repeating: .nan, count: row.count)
            row.withUnsafeBufferPointer { f in out.withUnsafeMutableBufferPointer { o in SavitzkyGolay.convolveInterior(f, coefficients: coeffs, into: o) } }
            var mismatches = 0
            for i in 2..<(row.count - 2) where out[i].bitPattern != step.derivative[i].bitPattern { mismatches += 1 }
            print("EELS-REPORT interior bit-exact \(name): \(row.count - 4) values, \(mismatches) mismatches")
            XCTAssertEqual(mismatches, 0, name)
        }
    }

    // MARK: the whole derivative (interior + edges)

    /// The full cropped derivative of the pinned pixel with SciPy's coefficients: interior bit-exact (above), the four edge
    /// values (two at each end, a cubic fit) to rounding. Relative to the largest |derivative| of the row.
    func testEdgesAgreeWithSciPyToRounding() throws {
        for name in caseNames {
            let (row, step, scale) = try croppedRow(name)
            let sg = try SavitzkyGolayFirstDerivative(windowLength: 5, polynomialOrder: 3, delta: scale,
                                                      coefficientsOverride: EELSFixtures.pinCase(name).estimated.recipe!.coefficients!)
            let d: [Double] = applyKernel(sg, row)
            let big = step.derivative.map(abs).max()!
            var worstEdge = 0.0
            for i in [0, 1, row.count - 2, row.count - 1] {
                let dev = abs(d[i] - step.derivative[i]) / max(abs(step.derivative[i]), 1e-6 * big)
                worstEdge = max(worstEdge, dev)
            }
            print("EELS-REPORT edges \(name): max relative |ours - SciPy| over the 4 edge values = \(worstEdge)")
            XCTAssertLessThan(worstEdge, 1e-11, name)
            for i in 2..<(row.count - 2) { XCTAssertEqual(d[i].bitPattern, step.derivative[i].bitPattern, "\(name) interior \(i)") }
        }
    }

    /// The same with THIS port's coefficients (no override): the derivative differs from SciPy's only through the coefficient
    /// noise (and rounding in the edge fits). Bound, stated before measuring: each coefficient is off by at most 3e-15 times the
    /// largest coefficient (measured 1.3e-15 above), so a value is off by at most that times the sum of |f| over its window,
    /// plus 1e-12 of the value itself.
    func testWholeDerivativeWithOwnCoefficientsAgreesToTheCoefficientNoise() throws {
        for name in caseNames {
            let (row, step, scale) = try croppedRow(name)
            let sg = try SavitzkyGolayFirstDerivative(windowLength: 5, polynomialOrder: 3, delta: scale)
            let d: [Double] = applyKernel(sg, row)
            var worstAbs = 0.0, worstRel = 0.0, worstRatio = 0.0
            let largestCoefficient = EELSFixtures.pinCase(name).estimated.recipe!.coefficients!.map(abs).max()!
            for i in 0..<row.count {
                let lo = max(0, i - 2), hi = min(row.count - 1, i + 2)
                let windowSum = row[lo...hi].map(abs).reduce(0, +)
                let bound = 3e-15 * largestCoefficient * windowSum + 1e-12 * abs(step.derivative[i])
                let diff = abs(d[i] - step.derivative[i])
                worstAbs = max(worstAbs, diff)
                worstRel = max(worstRel, diff / max(abs(step.derivative[i]), 1e-6))
                worstRatio = max(worstRatio, diff / bound)
                XCTAssertLessThanOrEqual(diff, bound, "\(name) value \(i)")
            }
            print("EELS-REPORT derivative with own coefficients \(name): max abs \(worstAbs), max rel \(worstRel), max diff/bound \(worstRatio)")
        }
    }

    /// The Savitzky-Golay first derivative of a cubic polynomial is the cubic's derivative EXACTLY (the fit reproduces it), at
    /// every sample including the edges: a check of the edge fits that needs no SciPy.
    func testCubicIsDifferentiatedExactlyEverywhere() throws {
        let delta = 0.05
        let n = 40
        let x = (0..<n).map { 1.0 + delta * Double($0) }
        let f = x.map { 2.0 * $0 * $0 * $0 - 3.0 * $0 * $0 + 0.5 * $0 + 7.0 }
        let df = x.map { 6.0 * $0 * $0 - 6.0 * $0 + 0.5 }
        for (wl, po) in [(5, 3), (7, 3), (9, 4), (5, 4)] {
            let sg = try SavitzkyGolayFirstDerivative(windowLength: wl, polynomialOrder: po, delta: delta)
            let d: [Double] = applyKernel(sg, f)
            for i in 0..<n { XCTAssertEqual(d[i], df[i], accuracy: 1e-9, "window \(wl) order \(po) sample \(i)") }
        }
    }

    // MARK: numpy.gradient

    /// `window_length = 0`: the derivative is `numpy.gradient(cropped, cropped_axis)` and is reproduced BIT FOR BIT, on the
    /// planted axis (non-uniform spacing by ulps: the a/b/c branch) and on the line scan's (uniform: the scalar branch).
    func testGradientIsBitExact() throws {
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
            XCTAssertEqual(mismatches, 0, name)
        }
        // the two branches are both exercised
        XCTAssertNotNil(NumpyGradient(axis: (0..<20).map { 1.0 + 0.5 * Double($0) }).uniformSpacing)
        let planted = EELSFixtures.pinCase("planted-noiseless")
        let xs = (0..<200).map { planted.energyAxis.offset + 0.05 * Double(220) + 0.05 * Double($0) }
        XCTAssertNil(NumpyGradient(axis: xs).uniformSpacing)
    }

    /// The Savitzky-Golay window and order that SciPy would reject or that this port does not support are refused.
    func testUnsupportedWindowsAreRefused() {
        for (wl, po) in [(4, 3), (2, 1), (1, 1), (5, 5), (5, 0), (-3, 1)] {
            XCTAssertThrowsError(try SavitzkyGolayFirstDerivative(windowLength: wl, polynomialOrder: po, delta: 0.05), "\(wl),\(po)") { error in
                guard case EELSThicknessError.invalidSavitzkyGolay = error else { return XCTFail("\(error)") }
            }
        }
    }

    private func applyKernel(_ sg: SavitzkyGolayFirstDerivative, _ row: [Double]) -> [Double] {
        var out = [Double](repeating: .nan, count: row.count)
        row.withUnsafeBufferPointer { f in out.withUnsafeMutableBufferPointer { o in sg.apply(f, into: o) } }
        return out
    }
}
