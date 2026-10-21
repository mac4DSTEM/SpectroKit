//
//  EELSFixtures.swift
//  Role: Loads the fixtures tools/eels-thickness/ wrote (raw float64 spectra, pins.json, planted-truth.json) and builds
//        the inputs of the thickness map from them. Shared by the test files of this target; no assertions here.
//
//  Floats in the JSON are Python reprs (the shortest string that reads back as the identical float64) and NaN is `null`;
//  JSONDecoder reads them back exactly.
//

import Foundation
import Testing
import SpectroEELS

// MARK: - Decodable views of pins.json (only what the tests read)

package struct PinsFile: Decodable {
    package let cases: [PinCase]
    package let iMFP: PinIMFP
    package let agreementRequired: PinAgreement
}

package struct PinAgreement: Decodable {
    package let i0AndItRelative: Double
    package let tOverLambdaAbsolute: Double
    package let lambdaAndAngularCorrectionRelative: Double
}

package struct PinIMFP: Decodable {
    package struct Table: Decodable { package let columns: [String]; package let rows: [[Double]] }
    package let iakoubovskii: Table
    package let angularCorrection: Table
}

package struct PinAxis: Decodable { package let offset: Double; package let scale: Double; package let size: Int }

package struct PinStability: Decodable {
    package let epsilonAbs: Double
    package let definesTolPixel: Int
    package let tolTie: Bool
    package let sensitivePixels: [Int]
    package let marginAtThreshold: [Double?]
    package let marginBeforeThreshold: [Double?]
}

package struct PinRecipe: Decodable { package let coefficients: [Double]?; package let fmaOrder: [Int]? }

package struct PinSubRange: Decodable { package let firstChannel: Int; package let endChannelExclusive: Int; package let channels: Int }

package struct PinEstimated: Decodable {
    package let windowLength: Int
    package let subRange: PinSubRange
    package let recipe: PinRecipe?
    package let tol: Double
    package let stability: PinStability
    package let minAbsDerivative: [Double]
    package let inflexionIndex: [Int]
    package let thresholdEV: [Double?]
    package let thresholdChannel: [Int?]
    package let i0: [Double?]
    package let it: [Double]
    package let tOverLambda: [Double?]
}

package struct PinStep: Decodable {
    package struct Pixel: Decodable { package let row: Int; package let col: Int; package let index: Int }
    package let pixel: Pixel
    package let firstChannel: Int
    package let channels: Int
    package let energyEV: [Double]
    package let derivative: [Double]
    package let minAbsDerivative: Double
    package let channelOfMinimum: Int
    package let tolGlobal: Double
    package let firstSubRangeIndexAtOrBelowTol: Int
    package let thresholdEV: Double
    package let thresholdChannel: Int
    package let gradientDerivative: [Double]
    package let gradientTolGlobal: Double
    package let gradientFirstSubRangeIndexAtOrBelowTol: Int
    package let gradientThresholdEV: Double
    package let gradientThresholdChannel: Int
}

package struct PinFixed: Decodable {
    package let thetaEV: Double
    package let channel: Int
    package let i0: [Double]
    package let it: [Double]
    package let tOverLambda: [Double]
}

package struct PinZeroLoss: Decodable { package let i0: [Double]; package let it: [Double]; package let tOverLambda: [Double] }

package struct PinAbsRoute: Decodable {
    package let route: String
    package let thetaEV: Double?
    package let tOverLambda: [Double?]
    package let thicknessNMDensityAndLambda: [Double?]
    package let thicknessNMDensityOnly: [Double?]
    package let thicknessNMLambdaOnly: [Double?]
}

package struct PinAbsolute: Decodable {
    package let densityGPerCm3: Double
    package let beamEnergyKeV: Double
    package let convergenceAngleMrad: Double
    package let collectionAngleMrad: Double
    package let lambdaGivenNM: Double
    package let lambdaIakoubovskiiNM: Double
    package let angularCorrection: Double
    package let routes: [PinAbsRoute]
}

package struct PinCase: Decodable {
    package let name: String
    package let file: String
    package let rows: Int
    package let cols: Int
    package let energyAxis: PinAxis
    package let truthTOverLambda: [Double]
    package let estimated: PinEstimated
    package let estimatedGradient: PinEstimated
    package let stepByStep: [PinStep]
    package let fixed: [PinFixed]
    package let zeroLoss: PinZeroLoss?
    package let absoluteThickness: PinAbsolute
}

// MARK: - planted-truth.json

package struct TruthFile: Decodable {
    package struct Image: Decodable { package let rows: Int; package let cols: Int; package let tau: [Double] }
    package struct Rule: Decodable { package let thresholdsEV: [Double]; package let channelIndex: [Int] }
    package struct Component: Decodable { package let theta: Double; package let index: Int; package let logRatio: Double; package let bias: Double }
    package struct BiasByChannel: Decodable { package let firstChannel: Int; package let bias: [Double] }
    package struct Pixel: Decodable {
        package let row: Int; package let col: Int; package let tau: Double
        package let components: [Component]
        package let biasByChannel: BiasByChannel
    }
    package let image: Image
    package let thresholdRule: Rule
    package let pixels: [Pixel]
}

// MARK: - the loader

package enum EELSFixtures {
    package static let directory = FixtureDirs.fixtures(of: "SpectroEELSTests")

    package static func url(_ name: String) -> URL { directory.appendingPathComponent(name) }

    /// Raw little-endian float64 file -> [Double].
    package static func doubles(_ name: String) throws -> [Double] {
        let data = try Data(contentsOf: url(name))
        precondition(data.count % 8 == 0)
        return data.withUnsafeBytes { raw in
            (0..<(data.count / 8)).map { Double(bitPattern: UInt64(littleEndian: raw.loadUnaligned(fromByteOffset: $0 * 8, as: UInt64.self))) }
        }
    }

    package static func decode<T: Decodable>(_ type: T.Type, _ name: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(contentsOf: url(name)))
    }

    package static let pins: PinsFile = {
        do { return try decode(PinsFile.self, "pins.json") } catch { fatalError("pins.json: \(error)") }
    }()

    package static let truth: TruthFile = {
        do { return try decode(TruthFile.self, "planted-truth.json") } catch { fatalError("planted-truth.json: \(error)") }
    }()

    package static func pinCase(_ name: String) -> PinCase { pins.cases.first { $0.name == name }! }

    /// A pinned image as the input type. The three fixtures: "planted-noiseless", "planted-noisy", "exspy-linescan".
    package static func image(_ name: String) throws -> LowLossSpectrumImage {
        let c = pinCase(name)
        return try LowLossSpectrumImage(nx: c.cols, ny: c.rows, channels: c.energyAxis.size, counts: try doubles(c.file),
                                        energyOffsetEV: c.energyAxis.offset, energyScaleEV: c.energyAxis.scale)
    }

    /// exSpy's line scan zero-loss twin (the only zero-loss spectrum image in the fixtures).
    package static func lineScanZeroLoss() throws -> LowLossSpectrumImage {
        let c = pinCase("exspy-linescan")
        return try LowLossSpectrumImage(nx: c.cols, ny: c.rows, channels: c.energyAxis.size,
                                        counts: try doubles("exspy-linescan-zlp.f64"),
                                        energyOffsetEV: c.energyAxis.offset, energyScaleEV: c.energyAxis.scale)
    }
}

// MARK: - small numeric helpers

package func relativeDifference(_ a: Double, _ b: Double) -> Double {
    if a == b { return 0 }
    return abs(a - b) / max(abs(a), abs(b))
}

package extension Optional where Wrapped == Double {
    /// Unwraps a result for a comparison; a nil is a failed assertion, not a crash that hides the tests after it.
    func orFail(fileID: String = #fileID, filePath: String = #filePath, line: Int = #line, column: Int = #column) -> Double {
        let sourceLocation = SourceLocation(fileID: fileID, filePath: filePath, line: line, column: column)
        if let v = self { return v }
        Issue.record("a value that should be present is nil", sourceLocation: sourceLocation)
        return .nan
    }
}

package extension Optional where Wrapped == Int {
    func orFail(fileID: String = #fileID, filePath: String = #filePath, line: Int = #line, column: Int = #column) -> Int {
        let sourceLocation = SourceLocation(fileID: fileID, filePath: filePath, line: line, column: column)
        if let v = self { return v }
        Issue.record("a value that should be present is nil", sourceLocation: sourceLocation)
        return -1
    }
}

/// The worst deviation seen so far, with where it was seen: tests record every pin's maximum and print it.
package final class Worst: @unchecked Sendable {
    package private(set) var value = 0.0
    package init() {}
    package private(set) var where_ = ""
    package func record(_ v: Double, _ at: @autoclosure () -> String) {
        if v > value || where_.isEmpty { if v >= value { value = v; where_ = at() } }
    }
}

/// SciPy derivatives with the portable auto-SG tie policy; raw exSpy pins stay in pins.json/refuter/.
package struct PortableThresholds: Decodable {
    package struct Route: Decodable {
        package let name: String
        package let routeIndex: Int
        package let firstChannel: Int
        package let channels: Int
        package let coefficientL1: Double
        package let tol: Double
        package let minAbsDerivative: [Double]
        package let slack: [Double]
        package let inflexionIndex: [Int]
        package let thresholdChannel: [Int?]
        package let thresholdEV: [Double?]
        package let i0: [Double?]
        package let it: [Double]
        package let tOverLambda: [Double?]
        package let changedFromRawExSpy: [Int]
    }
    package let routes: [Route]
    package static func route(_ name: String, index: Int = 0) throws -> Route {
        let file = try EELSFixtures.decode(Self.self, "portable-thresholds.json")
        return try #require(file.routes.first { $0.name == name && $0.routeIndex == index })
    }
}

/// Reports the raw-reference gap without pretending relative/ULP agreement near cancellation zeros.
package final class ReferenceGap {
    package init() {}
    private(set) var maxULPs: UInt64 = 0
    private(set) var maxRelative = 0.0
    private(set) var maxAbsolute = 0.0
    private(set) var maxScaledAbsolute = 0.0
    private func ordered(_ value: Double) -> UInt64 {
        let bits = value.bitPattern
        let sign: UInt64 = 1 << 63
        let magnitude = bits & (sign - 1)
        return bits & sign == 0 ? sign + magnitude : sign - magnitude
    }
    package func record(_ actual: Double, _ reference: Double, scale: Double) {
        guard actual.isFinite, reference.isFinite else { return }
        let a = ordered(actual), b = ordered(reference)
        maxULPs = max(maxULPs, a >= b ? a - b : b - a)
        let difference = abs(actual - reference)
        maxAbsolute = max(maxAbsolute, difference)
        if reference != 0 { maxRelative = max(maxRelative, difference / abs(reference)) }
        maxScaledAbsolute = max(maxScaledAbsolute, scale == 0 ? difference : difference / scale)
    }
    package func report(_ label: String) {
        print("EELS-REPORT \(label): maximum ULPs \(maxULPs), relative \(maxRelative) (nonzero reference), absolute \(maxAbsolute), scaled absolute \(maxScaledAbsolute)")
    }
}
