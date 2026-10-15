//
//  QuantificationPolicyChecks.swift
//  Role: family 2 of docs/generality-0.5.0-registration.md used from outside the package: `QuantificationPolicy` (`FitPolicy`,
//        `AbundancePolicy`, `DetectorLayers`, `SingleLineRule`, `IRLSSettings`, `AxisRefinementSettings`) through
//        `PooledQuantificationInput.policy` and `PooledQuantifier.run`, and `FitRangeSensitivityCheck.run(alternativeToKeV:)`.
//        Only public API is named.
//

import Foundation
import SpectroCore
import SpectroEDX

func quantificationPolicyChecks(_ r: inout Report) throws {
    let axis = EnergyAxis(offset: 0, scale: 0.01, size: 1500)
    // Planted counts from public pieces only: a Kramers-type continuum plus Gaussian K-alpha lines at the detector's width.
    func counts(_ areas: [(String, Double)], continuum: Bool = true) -> [UInt64] {
        var mu = (0..<axis.size).map { i -> Double in
            let e = max(axis.energy(ofChannel: i), 0.05)
            return !continuum || e < 0.2 ? 0 : 0.4 * max(200 - e, 0) / e * exp(-pow(0.3 / e, 3))
        }
        for (id, area) in areas {
            guard let line = XRayLines.line(id), let fwhm = XRayLines.fwhm(resolutionMnKaEV: 130, atEnergy: line.energy) else { continue }
            let sigma = fwhm / (2 * (2 * log(2.0)).squareRoot())
            for i in 0..<axis.size {
                let d = axis.energy(ofChannel: i) - line.energy
                if abs(d) < 12 * sigma { mu[i] += area * axis.scale * exp(-d * d / (2 * sigma * sigma)) / (sigma * (2 * Double.pi).squareRoot()) }
            }
        }
        return mu.map { UInt64($0.rounded()) }
    }
    var method = QuantificationMethod()
    method.elements = ["Al", "Mg", "Si"].map { QuantificationMethod.ElementState(symbol: $0, role: .quantify, isManual: false) }
    method.beamEnergyKeV = 200
    method.lockEnergyAxis = true
    let meta = SpectrumImageMetadata(fileName: "planted", filePath: "", scanWidth: 1, scanHeight: 1, channelCount: axis.size,
                                     energyOffsetEV: 0, energyDispersionEV: 10)
    func input(_ c: [UInt64], _ policy: QuantificationPolicy? = nil, method m: QuantificationMethod? = nil) -> PooledQuantificationInput {
        var i = PooledQuantificationInput(counts: c, axis: axis, method: m ?? method, metadata: meta, regionName: "planted", pixelCount: 1)
        if let policy { i.policy = policy }
        return i
    }
    let tables = QuantificationTables.bundled()
    let c = counts([("Al_Ka", 30000), ("Mg_Ka", 4000), ("Si_Ka", 12000)])
    let plain = try PooledQuantifier.run(input(c), tables: tables)
    let named = try PooledQuantifier.run(input(c, .default), tables: tables)
    r.check("the default policy equals the input that names none", plain.rows == named.rows && plain.footerLines == named.footerLines
            && plain.fit.values == named.fit.values && QuantificationPolicy.default.isDefault && QuantificationPolicy.default.problem == nil)
    r.check("a default policy adds no footer line and the method's JSON does not mention one",
            !plain.footerLines.contains { $0.hasPrefix("policy") } && !plain.method.canonicalJSON.contains("policy"))
    let start = try PooledQuantifier.run(input(c, QuantificationPolicy(fit: FitPolicy(fitFromKeV: 1.0))), tables: tables)
    r.check("a later fit start fits fewer channels and the footer names the policy",
            start.fit.channels.count == plain.fit.channels.count - 80
            && start.footerLines.contains { $0.hasPrefix("policy (non-default): ") && $0.contains("fit.fitFromKeV = 1") })
    let low = try PooledQuantifier.run(input(c, QuantificationPolicy(fit: FitPolicy(continuumOrders: [5, 4]))), tables: tables)
    r.check("continuum orders reach the fit's label", plain.fit.backgroundLabel.contains("(9,5)") && low.fit.backgroundLabel.contains("(5,4)"))
    let noEscape = try PooledQuantifier.run(input(c, QuantificationPolicy(fit: FitPolicy(escapePeaks: false))), tables: tables)
    r.check("escape peaks off is named", noEscape.footerLines[0] != plain.footerLines[0])
    var poisson = method; poisson.estimator = .poissonMaximumLikelihood
    let capped = try PooledQuantifier.run(input(c, QuantificationPolicy(fit: FitPolicy(irls: IRLSSettings(maxIterations: 2))), method: poisson), tables: tables)
    r.check("the Poisson iteration cap is honoured", capped.footerLines[0].contains("cap 2"))
    let noGain = QuantificationPolicy(fit: FitPolicy(axisRefinement: AxisRefinementSettings(refineGain: false)))
    var open = method; open.lockEnergyAxis = false
    let refined = try PooledQuantifier.run(input(c, noGain, method: open), tables: tables)
    r.check("axis refinement options reach the refinement", refined.refinement?.gainShift == 0)
    r.check("a policy that cannot run is refused with its reason",
            QuantificationPolicy(fit: FitPolicy(continuumOrders: [9])).problem != nil
            && (try? PooledQuantifier.run(input(c, QuantificationPolicy(fit: FitPolicy(continuumOrders: [9]))), tables: tables)) == nil)
    let si = counts([("Al_Ka", 20000), ("Mg_Ka", 4000), ("Si_Ka", 30000)])
    let al = try PooledQuantifier.run(input(si), tables: tables)
    let largest = try PooledQuantifier.run(input(si, QuantificationPolicy(abundance: AbundancePolicy(fallbackReference: nil))), tables: tables)
    r.check("the fallback reference is Al, or the largest net when nil",
            al.rows.first { $0.isReference }?.element == "Al" && largest.rows.first { $0.isReference }?.element == "Si")
    let thick = try PooledQuantifier.run(input(c, QuantificationPolicy(abundance: AbundancePolicy(detector: DetectorLayers(deadLayerMicrons: 1)))), tables: tables)
    r.check("the detector layers reach the computed k (a different k source line)", thick.method.kSource != plain.method.kSource)
    let only = counts([("Al_Ka", 30000)], continuum: false)
    var two = method; two.elements = ["Al", "Si"].map { QuantificationMethod.ElementState(symbol: $0, role: .quantify, isManual: false) }
    let refuse = try PooledQuantifier.run(input(only, method: two), tables: tables)
    let parity = try PooledQuantifier.run(input(only, QuantificationPolicy(abundance: AbundancePolicy(singleLine: .exspyHundredPercent)), method: two), tables: tables)
    r.check("one line above the floor: refused, or 100 % as the reference does",
            refuse.abundanceRefusal != nil && parity.abundanceRefusal == nil && parity.rows.first { $0.element == "Al" }?.atomicPercent == 100)
    let wide = EnergyAxis(offset: 0, scale: 0.04, size: 2000)
    let wInput = PooledQuantificationInput(
        counts: [UInt64](repeating: 100, count: wide.size), axis: wide, method: method,
        metadata: SpectrumImageMetadata(fileName: "w", filePath: "", scanWidth: 1, scanHeight: 1, channelCount: wide.size,
                                        energyOffsetEV: 0, energyDispersionEV: 40),
        regionName: "w", pixelCount: 1)
    let wq = try PooledQuantifier.run(wInput, tables: tables)
    r.check("the range-sensitivity alternative: the reach by default, a request, nothing at or below the fit",
            FitRangeSensitivityCheck.run(input: wInput, quantification: wq) != nil
            && FitRangeSensitivityCheck.run(input: wInput, quantification: wq, alternativeToKeV: 40) != nil
            && FitRangeSensitivityCheck.run(input: wInput, quantification: wq, alternativeToKeV: 20) == nil)
    let coded = try JSONDecoder().decode(QuantificationPolicy.self, from: JSONEncoder().encode(noGain))
    r.check("QuantificationPolicy round-trips through JSON", coded == noGain && coded.canonicalJSON == noGain.canonicalJSON)
}
