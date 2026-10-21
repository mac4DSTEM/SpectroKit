//
//  EdgeFixtures.swift
//  Role: edge-pins.json and edge-planted.json (EELS slice 2) as plain dictionaries, and the planted core-loss and low-loss
//        images built from them. Shared by the edge edge-case tests and the edge pins.
//

import Foundation
import SpectroEELS

/// edge-pins.json and edge-planted.json as plain dictionaries (the file is large and deep; only what is asserted is read).
package enum EdgeFixtures {
    package nonisolated(unsafe) static let pins: [String: Any] = load("edge-pins.json")   // read-only after first load
    package nonisolated(unsafe) static let planted: [String: Any] = load("edge-planted.json")

    package static func load(_ name: String) -> [String: Any] {
        do {
            let data = try Data(contentsOf: EELSFixtures.url(name))
            return try JSONSerialization.jsonObject(with: data) as! [String: Any]
        } catch { fatalError("\(name): \(error)") }
    }

    package static func edge(_ element: String) -> CoreLossEdge {
        CoreLossEdge.bundled.first { $0.element == element }!
    }

    /// A planted core-loss image (3 x 5 pixels, 150 eV + 0.25 eV x 2000).
    package static func core(_ file: String) throws -> CoreLossSpectrumImage {
        let ax = planted["coreLossAxis"] as! [String: Any]
        return try CoreLossSpectrumImage(nx: 5, ny: 3, channels: ax["size"] as! Int, counts: EELSFixtures.doubles(file),
                                         energyOffsetEV: ax["offset"] as! Double, energyScaleEV: ax["scale"] as! Double)
    }

    /// A planted low-loss image (slice 1's axis, -10 eV + 0.05 eV x 3400).
    package static func low(_ file: String) throws -> LowLossSpectrumImage {
        let ax = planted["lowLossAxis"] as! [String: Any]
        return try LowLossSpectrumImage(nx: 5, ny: 3, channels: ax["size"] as! Int, counts: EELSFixtures.doubles(file),
                                        energyOffsetEV: ax["offset"] as! Double, energyScaleEV: ax["scale"] as! Double)
    }

    package static let plantedMicroscope = EELSMicroscope(beamEnergyKeV: 200, convergenceMrad: 10, collectionMrad: 20)
}
