//
//  PlantedRuns.swift
//  Role: Runs of the shipped `ElementProposer` on the planted Al-Mg-Si spectra (registration 5.2), shared by gate P2 and the
//        Gate D experiments. Cached per process: every (cell, realisation, design) runs once.
//

import Foundation
import SpectroCore
import SpectroEDX

/// What one proposer run says about Mg.
package struct MgRun: Sendable {
    package var net: Double, sigma: Double, sigmaZero: Double, lc: Double, ld: Double, misfit: Double
    package var proposed: Bool
    package var other: [String]       // other elements proposed (full pool)
    package var present: Bool         // Mg had a candidate at all
    /// Proposed, or at or above L_D and held back only by the identification loop's gain bar (its possible reason says so).
    package var reported: Bool
    package init(net: Double, sigma: Double, sigmaZero: Double, lc: Double, ld: Double, misfit: Double, proposed: Bool, other: [String], present: Bool,
                 reported: Bool = false) {
        self.net = net; self.sigma = sigma; self.sigmaZero = sigmaZero; self.lc = lc; self.ld = ld; self.misfit = misfit
        self.proposed = proposed; self.other = other; self.present = present; self.reported = reported || proposed
    }
}

package enum PlantedRuns {
    package static let axis = EDXFixtures.axis

    /// The design of the single-candidate test (registration P2): `pool: ["Mg"]`, `settings.elements = [Al, Si]`.
    /// Sets the Mn Ka resolution of the model (130 eV unless a Gate D experiment scans it) and the fit range.
    package static func run(_ counts: [Double], pool: [String]? = ["Mg"], current: [String] = ["Al", "Si"], resolution: Double = 130,
                    axis: EnergyAxis = PlantedRuns.axis, reference: ReferenceShapes = .none) -> MgRun {
        var settings = FitSettings.standard(elements: current, axis: axis, resolutionMnKaEV: resolution, beamEnergy: 200)
        settings.referenceShapes = reference
        guard let r = try? ElementProposer(pool: pool).propose(counts: counts, axis: axis, settings: settings),
              let c = r.candidates.first(where: { $0.element == "Mg" }) else {
            return MgRun(net: .nan, sigma: .nan, sigmaZero: .nan, lc: .nan, ld: .nan, misfit: .nan, proposed: false, other: [], present: false)
        }
        return MgRun(net: c.net, sigma: c.sigma, sigmaZero: c.sigmaZero, lc: c.criticalLevel, ld: c.detectionLimit, misfit: c.misfit,
                     proposed: r.proposed.contains { $0.element == "Mg" },
                     other: r.proposed.map(\.element).filter { $0 != "Mg" }, present: true,
                     reported: c.isProposed || (c.aboveDetectionLimit && c.familyNote == nil
                                                && (c.possibleReason?.hasPrefix("Adding it improves the fit by") ?? false)))
    }

    /// Single-candidate runs on the noise-free mean and on `reals` realisations (all when nil) of a cell.
    package static func cellRuns(_ id: String, reals: Int? = nil, resolution: Double = 130) -> (mean: MgRun, reals: [MgRun]) {
        let c = EDXFixtures.cellByID[id]!
        let n = min(reals ?? c.nReal, c.nReal)
        let mean = run(EDXFixtures.meanSpectrum(c), resolution: resolution)
        let rr = parallelMap(n) { run(EDXFixtures.realisation(c, $0), resolution: resolution) }
        return (mean, rr)
    }
}

package extension Array where Element == MgRun {
    var pProposed: Double { isEmpty ? .nan : Double(filter(\.proposed).count) / Double(count) }
    var pReported: Double { isEmpty ? .nan : Double(filter(\.reported).count) / Double(count) }
    var meanNet: Double { map(\.net).reduce(0, +) / Double(count) }
    var meanSigma: Double { map(\.sigma).reduce(0, +) / Double(count) }
    var sdNet: Double {
        let m = meanNet
        return (map { ($0.net - m) * ($0.net - m) }.reduce(0, +) / Double(Swift.max(count - 1, 1))).squareRoot()
    }
}

/// Runs cached for the process (the gates and the Gate D experiments read the same spectra; every run happens once).
package final class RunStore: @unchecked Sendable {
    package static let shared = RunStore()
    private let lock = NSLock()
    private var singles: [String: (mean: MgRun, reals: [MgRun])] = [:]
    private var fulls: [String: (mean: MgRun, reals: [MgRun])] = [:]

    /// Single-candidate design (`pool: ["Mg"]`, elements Al, Si) on the cell's noise-free mean and ALL its realisations.
    package func single(_ id: String) -> (mean: MgRun, reals: [MgRun]) {
        lock.lock(); if let r = singles[id] { lock.unlock(); return r }; lock.unlock()
        let r = PlantedRuns.cellRuns(id)
        lock.lock(); singles[id] = r; lock.unlock()
        return r
    }

    /// The shipped full pool (default pool, elements Al, Si current) on the mean and the first `reals` realisations.
    package func full(_ id: String, reals: Int = 10) -> (mean: MgRun, reals: [MgRun]) {
        let key = "\(id)#\(reals)"
        lock.lock(); if let r = fulls[key] { lock.unlock(); return r }; lock.unlock()
        let c = EDXFixtures.cellByID[id]!
        let mean = PlantedRuns.run(EDXFixtures.meanSpectrum(c), pool: nil)
        let rr = parallelMap(min(reals, c.nReal)) { PlantedRuns.run(EDXFixtures.realisation(c, $0), pool: nil) }
        lock.lock(); fulls[key] = (mean, rr); lock.unlock()
        return (mean, rr)
    }
}
