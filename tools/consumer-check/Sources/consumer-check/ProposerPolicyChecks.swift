//
//  ProposerPolicyChecks.swift
//  Role: family 3 of docs/generality-0.5.0-registration.md used from outside the package: `ProposerPolicy` (with `Currie`,
//        `IdentificationThresholds`, `ElementContext`), `ElementProposer(policy:)`, the now public `ProposalRules` fields and
//        `UnlistedLineRules` with `UnlistedLineChecker.neighbour`. Only public API is named.
//

import Foundation
import SpectroCore
import SpectroEDX

func proposerPolicyChecks(_ r: inout Report) throws {
    let axis = EnergyAxis(offset: 0, scale: 0.01, size: 1100)
    let energies = (0..<axis.size).map { axis.energy(ofChannel: $0) }
    func expected(_ areas: [String: Double], dose k: Double = 10) -> [Double] {
        var out = energies.map { e -> Double in
            let x = max(e, 0.05)
            return e >= 0.2 ? k * (60 * max(200 - e, 0) / x * exp(-pow(0.30 / x, 3)) * 0.02 + 0.5) : 0
        }
        for (id, area) in areas {
            guard let line = XRayLines.line(id), let fwhm = XRayLines.fwhm(resolutionMnKaEV: 130, atEnergy: line.energy) else { continue }
            let sigma = fwhm / (2 * (2 * log(2.0)).squareRoot())
            for i in out.indices {
                let d = energies[i] - line.energy
                if abs(d) < 12 * sigma { out[i] += k * area * axis.scale * exp(-d * d / (2 * sigma * sigma)) / (sigma * (2 * Double.pi).squareRoot()) }
            }
        }
        return out
    }
    let settings = FitSettings.standard(elements: ["Al"], axis: axis, resolutionMnKaEV: 130, beamEnergy: 200)
    // Ga Ka with its La: since 0.11.0 the confirmation-line rule withholds an L-line nomination whose K alpha is in range and absent.
    let counts = expected(["Al_Ka": 9000, "Mg_Ka": 90, "Ga_La": 900, "Ga_Ka": 900])
    func propose(_ p: ProposerPolicy) throws -> ProposalResult { try ElementProposer(policy: p).propose(counts: counts, axis: axis, settings: settings) }
    let plain = try ElementProposer().propose(counts: counts, axis: axis, settings: settings)
    let named = try propose(.default)
    r.check("ProposerPolicy.default builds the proposer that ElementProposer() is", plain.proposed == named.proposed && plain.notes == named.notes)
    let d = ProposerPolicy.default
    r.check("ProposerPolicy defaults are the values the proposer has always used",
            d.currie == .standard && d.pool == nil && d.excluded == ElementProposer.defaultExcluded
            && d.minimumLineEnergyKeV == 0.45 && d.thresholds == IdentificationThresholds()
            && d.rangeMarginFWHM == 0.5 && d.sumPeakToleranceKeV == 0.06 && d.context == ElementContext())
    let strict = try propose(ProposerPolicy(currie: Currie(alpha: 0.01, beta: 0.01)))
    let both = plain.proposed.compactMap { p in strict.proposed.first { $0.element == p.element }.map { (p, $0) } }
    r.check("a stricter Currie lowers every shared candidate's net / L_D", !plain.proposed.isEmpty && both.allSatisfy { $0.1.significance < $0.0.significance })
    let pooled = try propose(ProposerPolicy(pool: ["Mg", "Si"]))
    r.check("a pool restricts the candidates", pooled.proposed.allSatisfy { ["Mg", "Si"].contains($0.element) })
    r.check("the default pool and its exclusions are readable",
            !ElementProposer.defaultPool.contains("Ne") && ElementProposer.defaultPool(excluding: []).contains("Ne")
            && ElementProposer.defaultExcluded.contains("Ne"))
    let ga = plain.proposed.first { $0.element == "Ga" }
    let noCtx = try propose(ProposerPolicy(context: ElementContext(quantifyByDefault: [], gridElements: [], implantedElements: [])))
    r.check("the element context decides which candidates carry the implantation question",
            ga?.conflicts.contains { $0.kind == .fibContamination } == true
            && noCtx.proposed.first { $0.element == "Ga" }?.conflicts.isEmpty == true)
    let off = try propose(ProposerPolicy(thresholds: IdentificationThresholds(peakSigma: 6, maximumPeaks: 20)))
    r.check("identification thresholds are accepted and named", off.notes.contains { $0.contains("thresholds.peakSigma = 6.0") })
    var rules = ProposalRules.shipped
    rules.actinideZ = 80; rules.besideKFWHM = 2; rules.lineMinimumSignificance = 4; rules.releaseSignificance = 12
    rules.hygiene = true; rules.besideK = true; rules.besideKGuard = true; rules.corroboration = true; rules.release = true
    let ruled = ProposalRules(hygiene: true, corroboration: false, release: false).apply(plain)
    r.check("ProposalRules fields and initialiser are public", rules.actinideZ == 80 && !rules.isNone && ruled.picks.count <= plain.proposed.count + plain.sumPeakQuestions.count
            && ProposalRules.none.isNone && !ProposalRules.registered.isNone)
    // The unlisted-line geometry.
    let al = EDSLineModel.build(elements: ["Al"], axis: axis, beamEnergy: 200, resolutionMnKaEV: 130).groups
    let ka = XRayLines.line("Al_Ka")!.energy
    let e = ka + XRayLines.fwhm(resolutionMnKaEV: 130, atEnergy: ka + 0.08)!
    r.check("UnlistedLineRules: the beside-line distance decides what a candidate is called",
            UnlistedLineChecker.neighbour(energyKeV: e, listedGroups: al, resolutionMnKaEV: 130, edges: [])?.line == "Al K\u{03B1}"
            && UnlistedLineChecker.neighbour(energyKeV: e, listedGroups: al, resolutionMnKaEV: 130, edges: [], rules: UnlistedLineRules(besideLineFWHM: 0.5)) == nil)
    let codedRules = try JSONDecoder().decode(UnlistedLineRules.self, from: JSONEncoder().encode(UnlistedLineRules(moveSigmaFactor: 3)))
    let codedFlank = try JSONDecoder().decode(IdentificationThresholds.self, from: JSONEncoder().encode(IdentificationThresholds(minimumGain: 50)))
    let codedContext = try JSONDecoder().decode(ElementContext.self, from: JSONEncoder().encode(ElementContext(gridElements: ["Ni"])))
    r.check("UnlistedLineRules, IdentificationThresholds and ElementContext round-trip through JSON",
            codedRules == UnlistedLineRules(moveSigmaFactor: 3) && codedFlank == IdentificationThresholds(minimumGain: 50)
            && codedContext == ElementContext(gridElements: ["Ni"]))
}
