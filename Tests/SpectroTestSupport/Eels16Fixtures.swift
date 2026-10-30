//
//  Eels16Fixtures.swift
//  Role: Loads the task-16 fixtures `tools/eels-chain/pins.py` wrote (Tests/SpectroEELSTests/Fixtures/eels16-pins.json and the
//        eels16-*.f64 arrays: float64 little-endian, C order, NaN kept). Shared by the fast and the parity targets; no assertions here.
//        The JSON is read as untyped values: its layout is the script's docstring, and a number that is `null` there is NaN here.
//

import Foundation
import SpectroEELS

package enum Eels16 {
    package static let directory = FixtureDirs.fixtures(of: "SpectroEELSTests")

    /// The whole pins file.
    nonisolated(unsafe) package static let pins: [String: Any] = {
        let data = try! Data(contentsOf: directory.appendingPathComponent("eels16-pins.json"))
        return try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    }()

    /// `pins["a"]["b"]…` as the dictionary at that path.
    package static func dict(_ path: String...) -> [String: Any] { value(path) as! [String: Any] }

    package static func value(_ path: [String]) -> Any {
        var node: Any = pins
        for key in path { node = (node as! [String: Any])[key]! }
        return node
    }

    package static func number(_ any: Any?) -> Double {
        if any == nil || any is NSNull { return .nan }
        return (any as! NSNumber).doubleValue
    }

    /// A (possibly nested) JSON array of numbers flattened row-major; `null` is NaN.
    package static func flat(_ any: Any?) -> [Double] {
        guard let any else { return [] }
        if let a = any as? [Any] { return a.flatMap { flat($0) } }
        return [number(any)]
    }

    /// `eels16-<name>.f64`.
    package static func array(_ name: String) -> [Double] {
        let data = try! Data(contentsOf: directory.appendingPathComponent("eels16-\(name).f64"))
        return data.withUnsafeBytes { raw in
            let n = raw.count / MemoryLayout<Double>.size
            return (0..<n).map { raw.loadUnaligned(fromByteOffset: $0 * 8, as: Double.self) }
        }
    }

    /// The shifted low-loss image (4 x 3 pixels, 600 channels from -20 eV at 0.1 eV) or its spike variant.
    package static func lowLoss(_ file: String = "zlp-ll") throws -> LowLossSpectrumImage {
        let ll = dict("zlp", "ll")
        return try LowLossSpectrumImage(nx: ll["nx"] as! Int, ny: ll["ny"] as! Int, channels: ll["channels"] as! Int, counts: array(file),
                                        energyOffsetEV: number(ll["offsetEV"]), energyScaleEV: number(ll["scaleEV"]))
    }

    /// The core-loss-like image (300 channels from 100 eV at 0.5 eV) that carries the same shifts.
    package static func coreLoss() throws -> CoreLossSpectrumImage {
        let ll = dict("zlp", "ll"), co = dict("zlp", "core")
        return try CoreLossSpectrumImage(nx: ll["nx"] as! Int, ny: ll["ny"] as! Int, channels: co["channels"] as! Int, counts: array(co["file"] as! String),
                                         energyOffsetEV: number(co["offsetEV"]), energyScaleEV: number(co["scaleEV"]))
    }

    /// The pixels the pins masked: (row 0, col 1) and (row 2, col 2) of the 3 x 4 image.
    package static let alignMask: PixelMaskValue = {
        var m = [Bool](repeating: false, count: 12)
        m[1] = true; m[10] = true
        return m
    }()
    package typealias PixelMaskValue = [Bool]
}
