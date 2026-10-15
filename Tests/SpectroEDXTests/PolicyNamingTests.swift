//
//  PolicyNamingTests.swift
//  Role: docs/generality-0.5.0-registration.md, section 11 "Gate B fixes" (findings 1 and 2): a non-default policy is named in full,
//        nil fields and arrays included, on one line; the proposer names its Currie rates and its policy. The default adds nothing.
//

import Foundation
import Testing
import SpectroCore
import SpectroEDX

struct PolicyNamingTests {

    // MARK: Finding 1, QuantificationPolicy.footerLine

    @Test func testFooterNamesANilFieldAndWritesArraysAndBoolsOnOneLine() throws {
        // A field changed to nil is named (the encoder leaves a nil key out, which the first version took for "unchanged").
        let nilRef = QuantificationPolicy(abundance: AbundancePolicy(fallbackReference: nil))
        #expect(nilRef.footerLine == "policy (non-default): abundance.fallbackReference = nil")
        // An array is `[5, 4]` on one line; a Bool is true / false.
        let odd = QuantificationPolicy(fit: FitPolicy(continuumOrders: [5, 4], continuumNonNegative: false, escapePeaks: false))
        let line = odd.footerLine ?? ""
        #expect(line == "policy (non-default): fit.continuumNonNegative = false, fit.continuumOrders = [5, 4], fit.escapePeaks = false", Comment(rawValue: line))
        #expect(!line.contains("\n"))
        // A nil that becomes a value is named with the value: `{...}` for the detector layers; the unchanged fields stay out.
        let eff = QuantificationPolicy(fit: FitPolicy(continuumEfficiency: DetectorLayers(goldNm: 20)))
        let effLine = eff.footerLine ?? ""
        #expect(effLine.hasPrefix("policy (non-default): fit.continuumEfficiency = {"), Comment(rawValue: effLine))
        #expect(effLine.contains("goldNm: 20") && !effLine.contains("abundance") && !effLine.contains("\n"), Comment(rawValue: effLine))
        // A number inside a nested struct and a Bool together, in sorted order, nothing unchanged named.
        let mix = QuantificationPolicy(fit: FitPolicy(fitFromKeV: 1, escapePeaks: false),
                                       abundance: AbundancePolicy(detector: DetectorLayers(aluminiumNm: 30), singleLine: .exspyHundredPercent))
        #expect(mix.footerLine == "policy (non-default): abundance.detector.aluminiumNm = 30, abundance.singleLine = exspyHundredPercent, fit.escapePeaks = false, fit.fitFromKeV = 1")
        // The default adds no line.
        #expect(QuantificationPolicy.default.footerLine == nil && QuantificationPolicy().footerLine == nil)
    }

    // MARK: Finding 2, the proposer's notes

    private static let axis = EnergyAxis(offset: 0, scale: 0.01, size: 1100)
    private static let energies = (0..<axis.size).map { axis.energy(ofChannel: $0) }

    private static func counts() -> [Double] {
        var out = energies.map { e -> Double in
            let x = max(e, 0.05)
            return e >= 0.2 ? 10 * (60 * max(200 - e, 0) / x * exp(-pow(0.30 / x, 3)) * 0.02 + 0.5) : 0
        }
        let g = EDSLineModel.build(elements: ["Al"], axis: axis, beamEnergy: 200, resolutionMnKaEV: 130).groups.first { $0.id == "Al_Ka" }!
        let col = EDSLineModel.column(of: g.lines, energies: energies, scale: axis.scale)
        for i in out.indices { out[i] += 90000 * col[i] }
        return out
    }

    private static func notes(_ policy: ProposerPolicy) throws -> [String] {
        let s = FitSettings.standard(elements: ["Al"], axis: axis, resolutionMnKaEV: 130, beamEnergy: 200)
        return try ElementProposer(policy: policy).propose(counts: counts(), axis: axis, settings: s).notes
    }

    @Test func testDetectionNoteGivesBothCurieRatesAndTheDefaultTextIsUnchanged() throws {
        func detection(_ c: Currie) throws -> String { try #require(Self.notes(ProposerPolicy(currie: c)).first { $0.hasPrefix("Detection:") }) }
        let tail = ", a convention; L_C and L_D are properties of this spectrum), \u{03C3}\u{2080} from the fit's own variance with the candidate absent."
        let head = "Detection: fitted net \u{2265} Currie L_D ("
        // Today's text, character for character.
        #expect(try detection(.standard) == head + "\u{03B1} = \u{03B2} = 0.05" + tail)
        #expect(try detection(Currie(alpha: 0.01, beta: 0.01)) == head + "\u{03B1} = \u{03B2} = 0.01" + tail)
        // Two different rates are both named, with the digits the caller gave (0.005 was printed as 0.01; two decimals stay where they give the rate back, as today).
        #expect(try detection(Currie(alpha: 0.005, beta: 0.2)) == head + "\u{03B1} = 0.005, \u{03B2} = 0.20" + tail)
        #expect(try detection(Currie(alpha: 0.05, beta: 0.1)) == head + "\u{03B1} = 0.05, \u{03B2} = 0.10" + tail)
        // Equal rates that two decimals would round are not rounded.
        #expect(try detection(Currie(alpha: 0.005, beta: 0.005)) == head + "\u{03B1} = \u{03B2} = 0.005" + tail)
    }

    @Test func testNonDefaultProposerPolicyIsNamedOnceAndTheDefaultAddsNothing() throws {
        let plain = try Self.notes(.default)
        #expect(!plain.contains { $0.hasPrefix("policy") } && ProposerPolicy.default.noteLine == nil)
        let p = ProposerPolicy(currie: Currie(alpha: 0.005, beta: 0.2), pool: ["Al", "Mg"], excluded: ["Ne"], maxPasses: 3,
                               flankScaling: false, flank: FlankMisfitGeometry(binsPerSide: 4), rangeMarginFWHM: 1,
                               sumPeakToleranceKeV: 0.1, context: ElementContext(quantifyByDefault: ["Cu", "Fe"], implantedElements: []))
        let named = try Self.notes(p).filter { $0.hasPrefix("policy (non-default): ") }
        #expect(named.count == 1)
        #expect(named.first == "policy (non-default): currie = alpha 0.005 beta 0.2, pool = [Al, Mg], excluded = [Ne], maxPasses = 3, "
                + "flankScaling = false, flank.binsPerSide = 4, rangeMarginFWHM = 1.0, sumPeakToleranceKeV = 0.1, "
                + "context.quantifyByDefault = [Cu, Fe], context.implantedElements = []")
        // Each field class alone: a number, a Bool, a set, a list, a struct field; the unchanged ones stay out.
        #expect(ProposerPolicy(minimumLineEnergyKeV: 0.3).noteLine == "policy (non-default): minimumLineEnergyKeV = 0.3")
        #expect(ProposerPolicy(maxForwardRounds: 10).noteLine == "policy (non-default): maxForwardRounds = 10")
        #expect(ProposerPolicy(flank: FlankMisfitGeometry(minimumBins: 4)).noteLine == "policy (non-default): flank.minimumBins = 4")
        #expect(ProposerPolicy(context: ElementContext(gridElements: ["Ni"])).noteLine == "policy (non-default): context.gridElements = [Ni]")
    }
}
