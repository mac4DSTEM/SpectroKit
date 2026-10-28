//
//  SpectroEELSChecks.swift
//  Role: the public surface of the SpectroEELS product (EELS thickness, the t/lambda thickness map) used from outside the
//        package: `EELSThickness.logRatio` and `.methodName`, `LowLossSpectrumImage` (both initialisers, every field),
//        `ThresholdRule`, `MeanFreePathSource`, `InelasticMeanFreePath.iakoubovskii` / `.angularCorrection`, `ThicknessMap` and
//        `ThicknessPixel` (every field), `ZeroLossSource`, `ThicknessUnavailable`, `SigmaUnavailable`, `EELSThicknessError`.
//        Values: (1) a one-pixel image whose answer is arithmetic (ln(23/7)); (2) exSpy's own line scan
//        (Tests/SpectroEELSTests/Fixtures, 17 spectra x 1024 channels) against `pins.json`, exSpy 7185a4d1's answers;
//        (3) the reasons a pixel has no answer and every error the call refuses with.
//

import Foundation
import SpectroCore
import SpectroEELS

private struct Pins: Decodable {
    struct Fixed: Decodable { let thetaEV: Double; let channel: Int; let i0: [Double]; let it: [Double]; let tOverLambda: [Double] }
    struct Zero: Decodable { let i0: [Double]; let it: [Double]; let tOverLambda: [Double] }
    struct Estimated: Decodable { let tol: Double; let thresholdChannel: [Int?]; let tOverLambda: [Double?] }
    struct Route: Decodable {
        let route: String
        let thicknessNMDensityAndLambda: [Double?]
        let thicknessNMDensityOnly: [Double?]
        let thicknessNMLambdaOnly: [Double?]
    }
    struct Absolute: Decodable {
        let densityGPerCm3: Double, beamEnergyKeV: Double, convergenceAngleMrad: Double, collectionAngleMrad: Double
        let lambdaGivenNM: Double, lambdaIakoubovskiiNM: Double, angularCorrection: Double
        let routes: [Route]
    }
    struct Case: Decodable {
        let name: String
        let fixed: [Fixed]
        let zeroLoss: Zero?
        let estimated: Estimated
        let absoluteThickness: Absolute
    }
    let cases: [Case]
}

/// A progress recorder that is `Sendable` for the call's `@Sendable` closure.
private final class Progress: @unchecked Sendable {
    private let lock = NSLock()
    private var values = [Double]()
    func add(_ v: Double) { lock.lock(); values.append(v); lock.unlock() }
    var all: [Double] { lock.lock(); defer { lock.unlock() }; return values }
}

private func doubles(_ url: URL) throws -> [Double] {
    let data = try Data(contentsOf: url)
    return data.withUnsafeBytes { raw in
        (0..<(data.count / 8)).map { Double(bitPattern: UInt64(littleEndian: raw.loadUnaligned(fromByteOffset: $0 * 8, as: UInt64.self))) }
    }
}

private func relative(_ a: Double, _ b: Double) -> Double { abs(a - b) / max(abs(b), Double.leastNormalMagnitude) }

func spectroEELSChecks(_ r: inout Report, _ eelsFixtures: URL) throws {
    // MARK: 1. A one-pixel image whose answer is arithmetic.
    // Energies -2 ... 5 eV (offset -2, scale 1). A fixed threshold of 1 eV is channel 3: I_0 = 1 + 2 + 4 = 7, I_t = 23.
    let counts: [Double] = [1, 2, 4, 8, 4, 2, 1, 1]
    let tiny = try LowLossSpectrumImage(nx: 1, ny: 1, channels: 8, counts: counts, energyOffsetEV: -2, energyScaleEV: 1)
    r.equal("LowLossSpectrumImage .nx .ny .channels .counts .energyOffsetEV .energyScaleEV .pixelCount",
            [tiny.nx, tiny.ny, tiny.channels, tiny.pixelCount], [1, 1, 8, 1])
    r.check("LowLossSpectrumImage .counts / .energyOffsetEV / .energyScaleEV as given",
            tiny.counts == counts && tiny.energyOffsetEV == -2 && tiny.energyScaleEV == 1)
    r.equal("LowLossSpectrumImage.energy(ofChannel:) is offset + scale * c", tiny.energy(ofChannel: 3), 1.0)
    let widened = try LowLossSpectrumImage(nx: 1, ny: 1, channels: 8, counts: counts.map { Float($0) }, energyOffsetEV: -2, energyScaleEV: 1)
    r.check("LowLossSpectrumImage.init(... counts: [Float] ...) widens exactly to Double", widened.counts == counts)

    let progress = Progress()
    let map = try EELSThickness.logRatio(tiny, threshold: .fixed(1), zeroLoss: nil, meanFreePath: nil,
                                         cancelled: { false }, progress: { progress.add($0) })
    r.equal("EELSThickness.methodName", EELSThickness.methodName, "log-ratio, exSpy 7185a4d1")
    r.equal("ThicknessMap .nx .ny .method .validation", [String(map.nx), String(map.ny), map.method, map.validation],
            ["1", "1", EELSThickness.methodName, "none"])
    r.equal("ThicknessMap.zeroLoss is .threshold(.fixed(1))  [ZeroLossSource, ThresholdRule: Equatable]", map.zeroLoss, .threshold(.fixed(1)))
    r.check("ThicknessMap .meanFreePath .meanFreePathNM .angularCorrection .estimatedTolerance are nil without a lambda source",
            map.meanFreePath == nil && map.meanFreePathNM == nil && map.angularCorrection == nil && map.estimatedTolerance == nil)
    let p = map[0, 0]
    r.check("ThicknessMap.pixels / subscript(x:y:) agree and hold one pixel", map.pixels.count == 1 && map.pixels[0] == p)
    r.near("ThicknessPixel.tOverLambda = ln(23 / 7) = 1.1895840668738364", p.tOverLambda, 1.1895840668738364, 1e-15)
    r.near("ThicknessPixel.sigmaCounting = sqrt(1/7 - 1/23) = 0.31524416249564025", p.sigmaCounting, 0.31524416249564025, 1e-15)
    r.check("ThicknessPixel .i0 = 7, .iTotal = 23, .thresholdEV = 1, .thresholdChannel = 3",
            p.i0 == 7 && p.iTotal == 23 && p.thresholdEV == 1 && p.thresholdChannel == 3)
    r.check("ThicknessPixel .zlpCentreEV (the maximum, channel 3, 1 eV), .thicknessNM nil, .unavailable nil, .sigmaUnavailable nil",
            p.zlpCentreEV == 1 && p.thicknessNM == nil && p.unavailable == nil && p.sigmaUnavailable == nil)
    let steps = progress.all
    r.check("the progress closure is monotone and ends at 1", steps.last == 1 && zip(steps, steps.dropFirst()).allSatisfy { $0 <= $1 })

    // The lambda sources, on that pixel: t = ln(23/7) * lambda (no correction) or * correction * lambda.
    let ln = 1.1895840668738364
    let given = try EELSThickness.logRatio(tiny, threshold: .fixed(1), meanFreePath: .given(120))
    r.equal("MeanFreePathSource.given(120): .meanFreePath, .meanFreePathNM, no correction",
            [given.meanFreePath == .given(120), given.meanFreePathNM == 120, given.angularCorrection == nil], [true, true, true])
    r.near("MeanFreePathSource.given(120): thicknessNM = ln(23/7) * 120", given[0, 0].thicknessNM, ln * 120, 1e-12)
    let density = 2.7, e0 = 200.0, alpha = 10.0, beta = 20.0
    let lambdaMFP = InelasticMeanFreePath.iakoubovskii(density: density, beamEnergyKeV: e0)
    let correction = InelasticMeanFreePath.angularCorrection(density: density, beamEnergyKeV: e0, convergenceMrad: alpha, collectionMrad: beta)

    // MARK: 2. exSpy's line scan against the pins.
    let pins = try JSONDecoder().decode(Pins.self, from: Data(contentsOf: eelsFixtures.appendingPathComponent("pins.json")))
    guard let pin = pins.cases.first(where: { $0.name == "exspy-linescan" }) else { throw CheckError("pins.json has no exspy-linescan") }
    let abs = pin.absoluteThickness
    r.check("InelasticMeanFreePath.iakoubovskii(2.7 g/cm3, 200 keV) = exSpy's \(abs.lambdaIakoubovskiiNM) nm, relative 1e-13",
            relative(lambdaMFP, abs.lambdaIakoubovskiiNM) < 1e-13, "\(lambdaMFP)")
    r.check("InelasticMeanFreePath.angularCorrection(2.7, 200, 10, 20 mrad) = exSpy's \(abs.angularCorrection), relative 1e-13",
            relative(correction, abs.angularCorrection) < 1e-13, "\(correction)")
    r.check("the pins' microscope numbers are the ones used", abs.densityGPerCm3 == density && abs.beamEnergyKeV == e0
            && abs.convergenceAngleMrad == alpha && abs.collectionAngleMrad == beta)

    let cols = 17, channels = 1024
    let ll = try doubles(eelsFixtures.appendingPathComponent("exspy-linescan-ll.f64"))
    let zl = try doubles(eelsFixtures.appendingPathComponent("exspy-linescan-zlp.f64"))
    let line = try LowLossSpectrumImage(nx: cols, ny: 1, channels: channels, counts: ll, energyOffsetEV: -100, energyScaleEV: 0.5)
    let zeroImage = try LowLossSpectrumImage(nx: cols, ny: 1, channels: channels, counts: zl, energyOffsetEV: -100, energyScaleEV: 0.5)

    // Fixed threshold 2.5 eV (channel 205): I_0, I_t, t/lambda, sigma, per pixel, and the three absolute routes.
    guard let fixed = pin.fixed.first(where: { $0.thetaEV == 2.5 }) else { throw CheckError("no fixed 2.5 pin") }
    let route = { (name: String) -> Pins.Route? in abs.routes.first { $0.route == name } }
    let densityOnly = try EELSThickness.logRatio(line, threshold: .fixed(2.5),
        meanFreePath: .iakoubovskii(density: density, beamEnergyKeV: e0, convergenceMrad: alpha, collectionMrad: beta))
    let both = try EELSThickness.logRatio(line, threshold: .fixed(2.5),
        meanFreePath: .givenWithAngularCorrection(abs.lambdaGivenNM, density: density, beamEnergyKeV: e0, convergenceMrad: alpha, collectionMrad: beta))
    let lambdaOnly = try EELSThickness.logRatio(line, threshold: .fixed(2.5), meanFreePath: .given(abs.lambdaGivenNM))
    let fixedRoute = route("fixed")
    var worst = (t: 0.0, i0: 0.0, it: 0.0, sigma: 0.0, nm1: 0.0, nm2: 0.0, nm3: 0.0)
    var structural = true
    for x in 0..<cols {
        let q = densityOnly[x, 0]
        worst.t = max(worst.t, Swift.abs((q.tOverLambda ?? .nan) - fixed.tOverLambda[x]))
        worst.i0 = max(worst.i0, relative(q.i0 ?? .nan, fixed.i0[x]))
        worst.it = max(worst.it, relative(q.iTotal, fixed.it[x]))
        worst.sigma = max(worst.sigma, Swift.abs((q.sigmaCounting ?? .nan) - (1 / fixed.i0[x] - 1 / fixed.it[x]).squareRoot()))
        worst.nm1 = max(worst.nm1, relative(q.thicknessNM ?? .nan, fixedRoute?.thicknessNMDensityOnly[x] ?? .nan))
        worst.nm2 = max(worst.nm2, relative(both[x, 0].thicknessNM ?? .nan, fixedRoute?.thicknessNMDensityAndLambda[x] ?? .nan))
        worst.nm3 = max(worst.nm3, relative(lambdaOnly[x, 0].thicknessNM ?? .nan, fixedRoute?.thicknessNMLambdaOnly[x] ?? .nan))
        structural = structural && q.thresholdChannel == fixed.channel && q.thresholdEV == fixed.thetaEV
            && q.unavailable == nil && q.sigmaUnavailable == nil && q.zlpCentreEV.isFinite
    }
    r.check("line scan, fixed 2.5 eV: .tOverLambda equals exSpy's at 17 pixels (worst abs \(worst.t), allowed 1e-12)", worst.t <= 1e-12)
    r.check("line scan, fixed 2.5 eV: .i0 and .iTotal equal exSpy's (relative \(worst.i0), \(worst.it); allowed 1e-12)", worst.i0 <= 1e-12 && worst.it <= 1e-12)
    r.check("line scan, fixed 2.5 eV: .sigmaCounting = sqrt(1/I_0 - 1/I_t) (worst abs \(worst.sigma))", worst.sigma <= 1e-12)
    r.check("line scan, fixed 2.5 eV: .thresholdChannel 205, .thresholdEV 2.5, .unavailable / .sigmaUnavailable nil, .zlpCentreEV finite", structural)
    r.check("MeanFreePathSource.iakoubovskii: .thicknessNM equals exSpy's (relative \(worst.nm1), allowed 1e-12)", worst.nm1 <= 1e-12)
    r.check("MeanFreePathSource.givenWithAngularCorrection: .thicknessNM equals exSpy's (relative \(worst.nm2), allowed 1e-12)", worst.nm2 <= 1e-12)
    r.check("MeanFreePathSource.given: .thicknessNM equals exSpy's (relative \(worst.nm3), allowed 1e-12)", worst.nm3 <= 1e-12)
    r.check("ThicknessMap.meanFreePathNM / .angularCorrection: the density route's are Iakoubovskii's and the correction; the given-lambda route's lambda",
            densityOnly.meanFreePathNM.map { relative($0, abs.lambdaIakoubovskiiNM) < 1e-13 } == true
            && densityOnly.angularCorrection.map { relative($0, abs.angularCorrection) < 1e-13 } == true
            && both.meanFreePathNM == abs.lambdaGivenNM && both.angularCorrection != nil && lambdaOnly.angularCorrection == nil
            && both.meanFreePath == .givenWithAngularCorrection(abs.lambdaGivenNM, density: density, beamEnergyKeV: e0, convergenceMrad: alpha, collectionMrad: beta)
            && densityOnly.meanFreePath == .iakoubovskii(density: density, beamEnergyKeV: e0, convergenceMrad: alpha, collectionMrad: beta)
            && densityOnly.meanFreePath != lambdaOnly.meanFreePath)

    // A separate zero-loss spectrum: I_0 is its sum; no threshold; sigma refused with its reason.
    if let zero = pin.zeroLoss {
        let viaZero = try EELSThickness.logRatio(line, zeroLoss: zeroImage)
        var worstZero = 0.0
        var shape = true
        for x in 0..<cols {
            let q = viaZero[x, 0]
            worstZero = max(worstZero, Swift.abs((q.tOverLambda ?? .nan) - zero.tOverLambda[x]))
            shape = shape && q.thresholdEV == nil && q.thresholdChannel == nil && q.sigmaCounting == nil
                && q.sigmaUnavailable == .zeroLossFromSeparateSpectrum && q.unavailable == nil
        }
        r.equal("zero-loss spectrum route: ThicknessMap.zeroLoss is .zeroLossSpectrum", viaZero.zeroLoss, .zeroLossSpectrum)
        r.check("zero-loss spectrum route: .tOverLambda equals exSpy's (worst abs \(worstZero))", worstZero <= 1e-12)
        r.check("zero-loss spectrum route: no threshold, no sigma, .sigmaUnavailable = .zeroLossFromSeparateSpectrum", shape)
    } else { r.check("the line scan's pins hold a zero-loss route", false) }

    // The estimated rule (the default): the global tolerance and the per-pixel thresholds are exSpy's.
    let estimated = try EELSThickness.logRatio(line)
    var worstEstimated = 0.0
    var channelsEqual = true
    for x in 0..<cols {
        if let want = pin.estimated.tOverLambda[x] { worstEstimated = max(worstEstimated, Swift.abs((estimated[x, 0].tOverLambda ?? .nan) - want)) }
        channelsEqual = channelsEqual && estimated[x, 0].thresholdChannel == pin.estimated.thresholdChannel[x]
    }
    r.equal("estimated rule (default): ThicknessMap.zeroLoss is .threshold(.estimated())", estimated.zeroLoss, .threshold(.estimated()))
    r.check("estimated rule: .estimatedTolerance equals exSpy's tol (relative 1e-9)", estimated.estimatedTolerance.map { relative($0, pin.estimated.tol) < 1e-9 } == true,
            "\(String(describing: estimated.estimatedTolerance)) vs \(pin.estimated.tol)")
    r.check("estimated rule: .thresholdChannel equals exSpy's at 17 pixels", channelsEqual)
    r.check("estimated rule: .tOverLambda equals exSpy's (worst abs \(worstEstimated))", worstEstimated <= 1e-12)

    // ThresholdRule: the cases and their defaults/equality; perPixel is a threshold per pixel (here the fixed one, 17 times).
    r.equal("ThresholdRule.estimated() defaults: window 10, start 1, windowLength 5, order 3, tolerance nil",
            ThresholdRule.estimated(), .estimated(window: 10, start: 1, windowLength: 5, polynomialOrder: 3, tolerance: nil))
    r.check("ThresholdRule cases differ: .fixed(2.5) != .perPixel([2.5]) != .estimated()",
            ThresholdRule.fixed(2.5) != .perPixel([2.5]) && ThresholdRule.perPixel([2.5]) != .estimated())
    let perPixel = try EELSThickness.logRatio(line, threshold: .perPixel(Array(repeating: 2.5, count: cols)))
    r.check("ThresholdRule.perPixel with 2.5 eV at every pixel equals the fixed rule's .tOverLambda",
            (0..<cols).allSatisfy { perPixel[$0, 0].tOverLambda == densityOnly[$0, 0].tOverLambda })
    let explicit = try EELSThickness.logRatio(line, threshold: .estimated(window: 10, start: 1, windowLength: 0, polynomialOrder: 3, tolerance: nil))
    r.check("ThresholdRule.estimated(windowLength: 0) (numpy.gradient) runs and gives an answer at every pixel", explicit.pixels.allSatisfy { $0.tOverLambda != nil })

    // MARK: 3. Why a pixel has no answer.
    func one(_ c: [Double], _ threshold: ThresholdRule) throws -> ThicknessPixel {
        try EELSThickness.logRatio(try LowLossSpectrumImage(nx: 1, ny: 1, channels: c.count, counts: c, energyOffsetEV: -2, energyScaleEV: 1),
                                   threshold: threshold)[0, 0]
    }
    let zeroI0 = try one([0, 0, 0, 5, 1, 1, 1, 1], .fixed(1))
    r.check("ThicknessUnavailable.zeroLossIntensityNotPositive (I_0 = 0): tOverLambda nil", zeroI0.unavailable == .zeroLossIntensityNotPositive && zeroI0.tOverLambda == nil)
    let negTotal = try one([5, 0, 0, -6, 0, 0, 0, 0], .fixed(1))
    r.check("ThicknessUnavailable.totalIntensityNotPositive (I_0 = 5, I_t = -1)", negTotal.unavailable == .totalIntensityNotPositive)
    let nanThreshold = try one([1, 2, 4, 8, 4, 2, 1, 1], .perPixel([.nan]))
    r.check("ThicknessUnavailable.thresholdNotANumber (a NaN per-pixel threshold)", nanThreshold.unavailable == .thresholdNotANumber)
    let outside = try one([1, 2, 4, 8, 4, 2, 1, 1], .perPixel([-50]))
    r.check("ThicknessUnavailable.thresholdOutsideAxis (-50 eV on an axis from -2 eV)", outside.unavailable == .thresholdOutsideAxis)
    let flat = try EELSThickness.logRatio(try LowLossSpectrumImage(nx: 1, ny: 1, channels: 40, counts: (0..<40).map { exp(0.3 * Double($0)) },
                                                                   energyOffsetEV: -5, energyScaleEV: 1))[0, 0]
    r.check("ThicknessUnavailable.noInflexionFound (a spectrum whose derivative only grows: the minimum |d| is the search range's first channel)", flat.unavailable == ThicknessUnavailable.noInflexionFound, "\(flat)")
    let below = try one([5, 5, 5, -3, 0, 0, 0, 0], .fixed(1))
    r.check("SigmaUnavailable.totalBelowZeroLoss (I_t = 12 < I_0 = 15): t/lambda present, sigma nil",
            below.sigmaUnavailable == .totalBelowZeroLoss && below.tOverLambda != nil && below.sigmaCounting == nil)
    r.check("ThicknessUnavailable / SigmaUnavailable: .rawValue and .description are non-empty",
            [ThicknessUnavailable.noInflexionFound, .thresholdNotANumber, .thresholdOutsideAxis, .zeroLossIntensityNotPositive,
             .totalIntensityNotPositive].allSatisfy { !$0.rawValue.isEmpty && !$0.description.isEmpty && ThicknessUnavailable(rawValue: $0.rawValue) == $0 }
            && [SigmaUnavailable.zeroLossFromSeparateSpectrum, .totalBelowZeroLoss].allSatisfy { !$0.rawValue.isEmpty && !$0.description.isEmpty })

    // MARK: 4. What the call refuses (EELSThicknessError, Equatable).
    func refuses(_ name: String, _ want: EELSThicknessError, _ body: () throws -> Void) {
        do { try body(); r.check("EELSThicknessError.\(name)", false, "did not throw") }
        catch let e as EELSThicknessError { r.check("EELSThicknessError.\(name)", e == want, "threw \(e)") }
        catch { r.check("EELSThicknessError.\(name)", false, "threw \(error)") }
    }
    func refusesCase(_ name: String, _ matches: (EELSThicknessError) -> Bool, _ body: () throws -> Void) {
        do { try body(); r.check("EELSThicknessError.\(name)", false, "did not throw") }
        catch let e as EELSThicknessError { r.check("EELSThicknessError.\(name)", matches(e), "threw \(e)") }
        catch { r.check("EELSThicknessError.\(name)", false, "threw \(error)") }
    }
    refuses("invalidShape(nx: 2, ny: 1, channels: 3, counts: 4)", .invalidShape(nx: 2, ny: 1, channels: 3, counts: 4)) {
        _ = try LowLossSpectrumImage(nx: 2, ny: 1, channels: 3, counts: [1, 2, 3, 4] as [Double], energyOffsetEV: 0, energyScaleEV: 1)
    }
    refuses("invalidEnergyAxis(offsetEV: 0, scaleEV: 0)", .invalidEnergyAxis(offsetEV: 0, scaleEV: 0)) {
        _ = try LowLossSpectrumImage(nx: 1, ny: 1, channels: 2, counts: [1, 2] as [Double], energyOffsetEV: 0, energyScaleEV: 0)
    }
    refuses("nonFiniteCounts(pixel: 1)", .nonFiniteCounts(pixel: 1)) {
        _ = try LowLossSpectrumImage(nx: 2, ny: 1, channels: 2, counts: [1, 2, 3, Double.nan], energyOffsetEV: 0, energyScaleEV: 1)
    }
    refusesCase("searchWindowTooShort", { if case .searchWindowTooShort = $0 { true } else { false } }) {
        _ = try EELSThickness.logRatio(try LowLossSpectrumImage(nx: 1, ny: 1, channels: 8, counts: counts, energyOffsetEV: -2, energyScaleEV: 1))
    }
    refusesCase("invalidSearchWindow", { if case .invalidSearchWindow = $0 { true } else { false } }) {
        _ = try EELSThickness.logRatio(line, threshold: .estimated(window: 10, start: .nan))
    }
    refusesCase("invalidSavitzkyGolay", { if case .invalidSavitzkyGolay(let why) = $0 { !why.isEmpty } else { false } }) {
        _ = try EELSThickness.logRatio(line, threshold: .estimated(windowLength: 4))
    }
    refuses("invalidTolerance(-1)", .invalidTolerance(-1)) { _ = try EELSThickness.logRatio(line, threshold: .estimated(tolerance: -1)) }
    refuses("perPixelThresholdCount(expected: 17, got: 2)", .perPixelThresholdCount(expected: 17, got: 2)) {
        _ = try EELSThickness.logRatio(line, threshold: .perPixel([1, 2]))
    }
    refuses("invalidFixedThreshold(-1000)", .invalidFixedThreshold(-1000)) { _ = try EELSThickness.logRatio(line, threshold: .fixed(-1000)) }
    refuses("zeroLossShapeMismatch(expectedNx: 17, expectedNy: 1, gotNx: 1, gotNy: 1)",
            .zeroLossShapeMismatch(expectedNx: 17, expectedNy: 1, gotNx: 1, gotNy: 1)) {
        _ = try EELSThickness.logRatio(line, zeroLoss: tiny)
    }
    refusesCase("invalidMeanFreePath", { if case .invalidMeanFreePath(let why) = $0 { !why.isEmpty } else { false } }) {
        _ = try EELSThickness.logRatio(line, threshold: .fixed(2.5), meanFreePath: .given(-1))
    }
    r.check("EELSThicknessError: Equatable distinguishes cases", EELSThicknessError.invalidTolerance(1) != .invalidTolerance(2)
            && EELSThicknessError.invalidTolerance(1) != .invalidFixedThreshold(1))
    var cancelledCalls = 0
    do { _ = try EELSThickness.logRatio(line, threshold: .fixed(2.5), cancelled: { true }); r.check("cancelled: { true } stops the call", false, "completed") }
    catch is SpectroCancelled { cancelledCalls += 1; r.check("cancelled: { true } throws SpectroCancelled (SpectroCore's)", true) }
    catch { r.check("cancelled: { true } throws SpectroCancelled", false, "\(error)") }
    _ = cancelledCalls
}
