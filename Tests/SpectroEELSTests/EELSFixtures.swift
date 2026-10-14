//
//  EELSFixtures.swift
//  Role: Loads the fixtures tools/eels-thickness/ wrote (raw float64 spectra, pins.json, planted-truth.json) and builds
//        the inputs of the thickness map from them. Shared by the test files of this target; no assertions here.
//
//  Floats in the JSON are Python reprs (the shortest string that reads back as the identical float64) and NaN is `null`;
//  JSONDecoder reads them back exactly.
//

import Foundation
import XCTest
import SpectroEELS

// MARK: - Decodable views of pins.json (only what the tests read)

struct PinsFile: Decodable {
    let cases: [PinCase]
    let iMFP: PinIMFP
    let agreementRequired: PinAgreement
}

struct PinAgreement: Decodable {
    let i0AndItRelative: Double
    let tOverLambdaAbsolute: Double
    let lambdaAndAngularCorrectionRelative: Double
}

struct PinIMFP: Decodable {
    struct Table: Decodable { let columns: [String]; let rows: [[Double]] }
    let iakoubovskii: Table
    let angularCorrection: Table
}

struct PinAxis: Decodable { let offset: Double; let scale: Double; let size: Int }

struct PinStability: Decodable {
    let epsilonAbs: Double
    let definesTolPixel: Int
    let tolTie: Bool
    let sensitivePixels: [Int]
    let marginAtThreshold: [Double?]
    let marginBeforeThreshold: [Double?]
}

struct PinRecipe: Decodable { let coefficients: [Double]?; let fmaOrder: [Int]? }

struct PinSubRange: Decodable { let firstChannel: Int; let endChannelExclusive: Int; let channels: Int }

struct PinEstimated: Decodable {
    let windowLength: Int
    let subRange: PinSubRange
    let recipe: PinRecipe?
    let tol: Double
    let stability: PinStability
    let minAbsDerivative: [Double]
    let inflexionIndex: [Int]
    let thresholdEV: [Double?]
    let thresholdChannel: [Int?]
    let i0: [Double?]
    let it: [Double]
    let tOverLambda: [Double?]
}

struct PinStep: Decodable {
    struct Pixel: Decodable { let row: Int; let col: Int; let index: Int }
    let pixel: Pixel
    let firstChannel: Int
    let channels: Int
    let energyEV: [Double]
    let derivative: [Double]
    let minAbsDerivative: Double
    let channelOfMinimum: Int
    let tolGlobal: Double
    let firstSubRangeIndexAtOrBelowTol: Int
    let thresholdEV: Double
    let thresholdChannel: Int
    let gradientDerivative: [Double]
    let gradientTolGlobal: Double
    let gradientFirstSubRangeIndexAtOrBelowTol: Int
    let gradientThresholdEV: Double
    let gradientThresholdChannel: Int
}

struct PinFixed: Decodable {
    let thetaEV: Double
    let channel: Int
    let i0: [Double]
    let it: [Double]
    let tOverLambda: [Double]
}

struct PinZeroLoss: Decodable { let i0: [Double]; let it: [Double]; let tOverLambda: [Double] }

struct PinAbsRoute: Decodable {
    let route: String
    let thetaEV: Double?
    let tOverLambda: [Double?]
    let thicknessNMDensityAndLambda: [Double?]
    let thicknessNMDensityOnly: [Double?]
    let thicknessNMLambdaOnly: [Double?]
}

struct PinAbsolute: Decodable {
    let densityGPerCm3: Double
    let beamEnergyKeV: Double
    let convergenceAngleMrad: Double
    let collectionAngleMrad: Double
    let lambdaGivenNM: Double
    let lambdaIakoubovskiiNM: Double
    let angularCorrection: Double
    let routes: [PinAbsRoute]
}

struct PinCase: Decodable {
    let name: String
    let file: String
    let rows: Int
    let cols: Int
    let energyAxis: PinAxis
    let truthTOverLambda: [Double]
    let estimated: PinEstimated
    let estimatedGradient: PinEstimated
    let stepByStep: [PinStep]
    let fixed: [PinFixed]
    let zeroLoss: PinZeroLoss?
    let absoluteThickness: PinAbsolute
}

// MARK: - planted-truth.json

struct TruthFile: Decodable {
    struct Image: Decodable { let rows: Int; let cols: Int; let tau: [Double] }
    struct Rule: Decodable { let thresholdsEV: [Double]; let channelIndex: [Int] }
    struct Component: Decodable { let theta: Double; let index: Int; let logRatio: Double; let bias: Double }
    struct BiasByChannel: Decodable { let firstChannel: Int; let bias: [Double] }
    struct Pixel: Decodable {
        let row: Int; let col: Int; let tau: Double
        let components: [Component]
        let biasByChannel: BiasByChannel
    }
    let image: Image
    let thresholdRule: Rule
    let pixels: [Pixel]
}

// MARK: - the loader

enum EELSFixtures {
    static let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")

    static func url(_ name: String) -> URL { directory.appendingPathComponent(name) }

    /// Raw little-endian float64 file -> [Double].
    static func doubles(_ name: String) throws -> [Double] {
        let data = try Data(contentsOf: url(name))
        precondition(data.count % 8 == 0)
        return data.withUnsafeBytes { raw in
            (0..<(data.count / 8)).map { Double(bitPattern: UInt64(littleEndian: raw.loadUnaligned(fromByteOffset: $0 * 8, as: UInt64.self))) }
        }
    }

    static func decode<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(contentsOf: url(name)))
    }

    static let pins: PinsFile = {
        do { return try decode(PinsFile.self, "pins.json") } catch { fatalError("pins.json: \(error)") }
    }()

    static let truth: TruthFile = {
        do { return try decode(TruthFile.self, "planted-truth.json") } catch { fatalError("planted-truth.json: \(error)") }
    }()

    static func pinCase(_ name: String) -> PinCase { pins.cases.first { $0.name == name }! }

    /// A pinned image as the input type. The three fixtures: "planted-noiseless", "planted-noisy", "exspy-linescan".
    static func image(_ name: String) throws -> LowLossSpectrumImage {
        let c = pinCase(name)
        return try LowLossSpectrumImage(nx: c.cols, ny: c.rows, channels: c.energyAxis.size, counts: try doubles(c.file),
                                        energyOffsetEV: c.energyAxis.offset, energyScaleEV: c.energyAxis.scale)
    }

    /// exSpy's line scan zero-loss twin (the only zero-loss spectrum image in the fixtures).
    static func lineScanZeroLoss() throws -> LowLossSpectrumImage {
        let c = pinCase("exspy-linescan")
        return try LowLossSpectrumImage(nx: c.cols, ny: c.rows, channels: c.energyAxis.size,
                                        counts: try doubles("exspy-linescan-zlp.f64"),
                                        energyOffsetEV: c.energyAxis.offset, energyScaleEV: c.energyAxis.scale)
    }
}

// MARK: - small numeric helpers

func relativeDifference(_ a: Double, _ b: Double) -> Double {
    if a == b { return 0 }
    return abs(a - b) / max(abs(a), abs(b))
}

extension Optional where Wrapped == Double {
    /// Unwraps a result for a comparison; a nil is a failed assertion, not a crash that hides the tests after it.
    func orFail(file: StaticString = #filePath, line: UInt = #line) -> Double {
        if let v = self { return v }
        XCTFail("a value that should be present is nil", file: file, line: line)
        return .nan
    }
}

extension Optional where Wrapped == Int {
    func orFail(file: StaticString = #filePath, line: UInt = #line) -> Int {
        if let v = self { return v }
        XCTFail("a value that should be present is nil", file: file, line: line)
        return -1
    }
}

/// The worst deviation seen so far, with where it was seen: tests record every pin's maximum and print it.
final class Worst: @unchecked Sendable {
    private(set) var value = 0.0
    private(set) var where_ = ""
    func record(_ v: Double, _ at: @autoclosure () -> String) {
        if v > value || where_.isEmpty { if v >= value { value = v; where_ = at() } }
    }
}
