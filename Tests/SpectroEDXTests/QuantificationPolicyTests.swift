//
//  QuantificationPolicyTests.swift
//  Role: docs/generality-0.5.0-registration.md, family 2 (F1-F13, Q3-Q7): `FitPolicy` and `AbundancePolicy` on planted,
//        noise-free spectra (the fit's own line model plus a Kramers-type continuum, rounded to integer counts). The default
//        policy reproduces the call that names none; each non-default field moves the result as section 5 of the registration
//        predicted before the code was written.
//

import Foundation
import Testing
import SpectroCore
import SpectroEDX

struct QuantificationPolicyTests {

    private static let resources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Sources/SpectroEDX/Resources/Spectroscopy")
    private static let tables = try! QuantificationTables(directory: resources)
    private static let sdd = SDDEfficiency(table: try! MassAbsorptionTable(contentsOf: resources.appendingPathComponent("FFastMAC.csv")))

    private static let axis = EnergyAxis(offset: 0, scale: 0.01, size: 1500)   // 0 to 15 keV

    /// Kramers x low-energy window absorption, E0 = 200 keV, counts per channel.
    private static let kramers: @Sendable (Double) -> Double = { e in
        let x = max(e, 0.05)
        return 0.4 * max(200 - e, 0) / x * exp(-pow(0.3 / x, 3))
    }

    /// Integer counts: the continuum plus the named line groups (areas in counts, `Al_Ka` ...), each with a Si-escape copy of
    /// `escape[group]` times its area when asked, on the fit's own Gaussian columns (width from the detector law at `resolution`).
    private static func counts(areas: [String: Double], escape: [String: Double] = [:], continuum: (Double) -> Double = kramers,
                               axis: EnergyAxis = axis, resolution: Double = 130, beam: Double = 200) -> [UInt64] {
        let energies = (0..<axis.size).map { axis.energy(ofChannel: $0) }
        var mu = energies.map { $0 >= 0.2 ? continuum($0) : 0 }
        let elements = Array(Set(areas.keys.map { String($0.split(separator: "_")[0]) }))
        let model = EDSLineModel.build(elements: elements, axis: axis, beamEnergy: beam, resolutionMnKaEV: resolution, escapePeaks: true)
        for g in model.groups {
            guard let area = areas[g.id] else { continue }
            let col = EDSLineModel.column(of: g.lines, energies: energies, scale: axis.scale)
            for i in mu.indices { mu[i] += area * col[i] }
            if let f = escape[g.id], !g.escapes.isEmpty {
                let ec = EDSLineModel.column(of: g.escapes, energies: energies, scale: axis.scale)
                for i in mu.indices { mu[i] += f * area * ec[i] }
            }
        }
        return mu.map { UInt64($0.rounded()) }
    }

    private static func metadata(_ axis: EnergyAxis) -> SpectrumImageMetadata {
        SpectrumImageMetadata(fileName: "planted", filePath: "", scanWidth: 1, scanHeight: 1, channelCount: axis.size,
                              energyOffsetEV: axis.offset * 1000, energyDispersionEV: axis.scale * 1000)
    }

    private static func method(_ elements: [(String, QuantificationMethod.ElementRole)], locked: Bool = true) -> QuantificationMethod {
        var m = QuantificationMethod()
        m.elements = elements.map { QuantificationMethod.ElementState(symbol: $0.0, role: $0.1, isManual: false) }
        m.beamEnergyKeV = 200
        m.lockEnergyAxis = locked
        return m
    }

    private static func input(_ counts: [UInt64], axis: EnergyAxis = axis, method: QuantificationMethod,
                              policy: QuantificationPolicy? = nil, resolution: Double = 130,
                              metadata meta: SpectrumImageMetadata? = nil) -> PooledQuantificationInput {
        var i = PooledQuantificationInput(counts: counts, axis: axis, method: method, metadata: meta ?? metadata(axis),
                                          regionName: "planted", pixelCount: 1, resolutionMnKaEV: resolution)
        if let policy { i.policy = policy }
        return i
    }

    private static let threeAreas: [String: Double] = ["Al_Ka": 30000, "Mg_Ka": 4000, "Si_Ka": 12000]
    private static let threeElements: [(String, QuantificationMethod.ElementRole)] = [("Al", .quantify), ("Mg", .quantify), ("Si", .quantify)]

    private static func run(_ counts: [UInt64], elements: [(String, QuantificationMethod.ElementRole)] = threeElements,
                            axis: EnergyAxis = axis, policy: QuantificationPolicy = .default, locked: Bool = true,
                            resolution: Double = 130) throws -> PooledQuantification {
        try PooledQuantifier.run(input(counts, axis: axis, method: method(elements, locked: locked), policy: policy, resolution: resolution),
                                 tables: tables)
    }

    private static func fit(_ f: FitPolicy) -> QuantificationPolicy { QuantificationPolicy(fit: f) }
    private static func abundance(_ a: AbundancePolicy) -> QuantificationPolicy { QuantificationPolicy(abundance: a) }

    // MARK: The default is the old behaviour

    @Test func testDefaultPolicyEqualsTheCallWithoutOne() throws {
        let c = Self.counts(areas: Self.threeAreas)
        let plain = try PooledQuantifier.run(Self.input(c, method: Self.method(Self.threeElements, locked: false)), tables: Self.tables)
        let named = try Self.run(c, policy: .default, locked: false)
        #expect(plain.rows == named.rows)
        #expect(plain.footerLines == named.footerLines)
        #expect(plain.fit.values.map(\.bitPattern) == named.fit.values.map(\.bitPattern))
        #expect(plain.fit.covariance.map(\.bitPattern) == named.fit.covariance.map(\.bitPattern))
        #expect(plain.plotModel.map(\.bitPattern) == named.plotModel.map(\.bitPattern))
        #expect(plain.refinement == named.refinement && plain.warnings == named.warnings)
        #expect(!plain.footerLines.contains { $0.hasPrefix("policy") })
        // The policy is not in the method.
        #expect(!plain.method.canonicalJSON.contains("policy"))
        // The default policy's values, its JSON round trip and its footer.
        let d = QuantificationPolicy.default
        #expect(d.isDefault && d.problem == nil && d.footerLine == nil)
        #expect(d.fit.fitFromKeV == 0.2 && d.fit.defaultUpperLimitKeV == 20 && d.fit.continuumOrders == [9, 5]
                && d.fit.continuumEdges == [1.5596] && d.fit.continuumNonNegative && d.fit.continuumEfficiency == nil
                && d.fit.escapePeaks && d.fit.maximumPolynomialOrder == 8 && d.fit.escapeRatioWarning == 0.05
                && d.fit.irls == IRLSSettings() && d.fit.axisRefinement == AxisRefinementSettings())
        #expect(d.abundance.fallbackReference == "Al" && d.abundance.detector == DetectorLayers(goldNm: 0, aluminiumNm: 10, deadLayerMicrons: 0, siliconMicrons: 450)
                && d.abundance.absorptionConvergencePercent == 1e-7 && d.abundance.absorptionMaxIterations == 200
                && d.abundance.derivativeRelativeStep == 0.01 && d.abundance.singleLine == .refuse)
        let odd = QuantificationPolicy(fit: FitPolicy(fitFromKeV: 1, escapePeaks: false), abundance: AbundancePolicy(fallbackReference: nil))
        #expect(try JSONDecoder().decode(QuantificationPolicy.self, from: JSONEncoder().encode(odd)) == odd)
        #expect(odd.canonicalJSON == (try JSONDecoder().decode(QuantificationPolicy.self, from: Data(odd.canonicalJSON.utf8))).canonicalJSON)
        #expect(odd.footerLine == "policy (non-default): abundance.fallbackReference = nil, fit.escapePeaks = false, fit.fitFromKeV = 1")
        // A policy that cannot run is refused with the reason, not trapped.
        #expect(throws: QuantificationRefusal.self) { try Self.run(c, policy: Self.fit(FitPolicy(continuumOrders: [9]))) }
    }

    // MARK: F1 the fit start

    @Test func testFitStartMovesTheFittedChannelsAndTheRefusalBound() throws {
        let c = Self.counts(areas: Self.threeAreas)
        let a = try Self.run(c), b = try Self.run(c, policy: Self.fit(FitPolicy(fitFromKeV: 1.0)))
        #expect(a.fit.channels.lowerBound == Self.axis.fitChannels(from: 0.2, to: 15).lowerBound)
        #expect(b.fit.channels.lowerBound == Self.axis.fitChannels(from: 1.0, to: 15).lowerBound)
        #expect(a.fit.channels.count - b.fit.channels.count == 80)                       // 0.8 keV / 10 eV
        #expect(b.footerLines.contains { $0.hasPrefix("fit range 1\u{2013}") }, "\(b.footerLines)")
        #expect(a.footerLines.contains { $0.hasPrefix("fit range 0.2\u{2013}") })
        // A non-default policy is named in the footer, one line; a default one adds none.
        let named = b.footerLines.filter { $0.hasPrefix("policy (non-default): ") }
        #expect(named.count == 1 && named[0].contains("fit.fitFromKeV = 1"), "\(b.footerLines)")
        #expect(!a.footerLines.contains { $0.hasPrefix("policy") })
        // The typed end must lie above the start: 0.5 keV is fine at 0.2 and refused at 1.0.
        var m = Self.method(Self.threeElements); m.fitToKeV = 0.5
        _ = try PooledQuantifier.run(Self.input(c, method: m), tables: Self.tables)
        #expect(throws: QuantificationRefusal.self) {
            try PooledQuantifier.run(Self.input(c, method: m, policy: Self.fit(FitPolicy(fitFromKeV: 1.0))), tables: Self.tables)
        }
        let polynomial: QuantificationMethod = {
            var p = Self.method(Self.threeElements); p.background = .wholeRangePolynomial6; return p
        }()
        let pa = try PooledQuantifier.run(Self.input(c, method: polynomial), tables: Self.tables)
        let pb = try PooledQuantifier.run(Self.input(c, method: polynomial, policy: Self.fit(FitPolicy(fitFromKeV: 1.0))), tables: Self.tables)
        #expect(pa.fit.channels.lowerBound == a.fit.channels.lowerBound && pb.fit.channels.lowerBound == b.fit.channels.lowerBound)
    }

    // MARK: F2 the default upper limit

    @Test func testDefaultUpperLimit() {
        let wide = EnergyAxis(offset: 0, scale: 0.04, size: 2001)               // 0 to 80 keV
        let m = Self.method(Self.threeElements)
        func choice(_ limit: Double, axis: EnergyAxis = wide) -> FitRangeChoice {
            FitRangeChoice(method: m, fileAxis: axis, usedAxis: axis, beamEnergy: 200, policy: FitPolicy(defaultUpperLimitKeV: limit))
        }
        #expect(FitRangeChoice(method: m, fileAxis: wide, usedAxis: wide, beamEnergy: 200).toKeV == 20)
        #expect(choice(20).toKeV == 20 && choice(20).source == .defaultLimit)
        #expect(choice(40).toKeV == 40 && choice(40).source == .defaultLimit)
        #expect(choice(100).toKeV == wide.highValue && choice(100).source == .defaultReach)
        #expect(FitSettings.defaultFitTo(axis: wide, beamEnergy: 200, upperLimitKeV: 40) == 40)
        #expect(FitSettings.standard(elements: ["Al"], axis: wide, resolutionMnKaEV: 130, beamEnergy: 200,
                                     policy: FitPolicy(defaultUpperLimitKeV: 40)).fitTo == 40)
    }

    // MARK: F3 - F6 the continuum

    /// Roll-off of the planted continuum that a (5, 4) form cannot follow and a (9, 5) form can.
    private static let rolled: @Sendable (Double) -> Double = { e in
        let x = max(e, 0.05)
        return 0.4 * max(200 - e, 0) / x * (1 - exp(-pow(x / 0.5, 2.4)))
    }

    @Test func testContinuumOrdersEdgesAndBasis() throws {
        let stepped: @Sendable (Double) -> Double = { e in Self.rolled(e) * (e >= 1.5596 ? 0.4 : 1) }
        let c = Self.counts(areas: Self.threeAreas, continuum: stepped)
        let base = try Self.run(c)
        #expect(base.fit.backgroundNames.count == 16)
        let low = try Self.run(c, policy: Self.fit(FitPolicy(continuumOrders: [5, 4])))
        #expect(low.fit.backgroundNames.count == 11)
        #expect(low.fit.pearsonReducedChiSquared > base.fit.pearsonReducedChiSquared)
        let noStep = try Self.run(c, policy: Self.fit(FitPolicy(continuumOrders: [9], continuumEdges: [])))
        #expect(noStep.fit.backgroundNames.count == 10)
        #expect(noStep.fit.pearsonReducedChiSquared > base.fit.pearsonReducedChiSquared)
        // Free-sign monomials span the same space as the Bernstein basis: the residual cannot be larger.
        let free = try Self.run(c, policy: Self.fit(FitPolicy(continuumNonNegative: false)))
        #expect(free.fit.backgroundLabel.contains("poly") && base.fit.backgroundLabel.contains("Bernstein"))
        let freeSS: Double = free.fit.residual.reduce(0.0) { $0 + $1 * $1 }
        let baseSS: Double = base.fit.residual.reduce(0.0) { $0 + $1 * $1 }
        let slack: Double = 1 + 1e-9
        #expect(freeSS <= baseSS * slack)
    }

    @Test func testContinuumEfficiencyIsFittedAndNamed() throws {
        let shaped: @Sendable (Double) -> Double = { e in Self.kramers(e) * Self.sdd.efficiency(energyKeV: max(e, 0.2)) }
        let c = Self.counts(areas: Self.threeAreas, continuum: shaped)
        let plain = try Self.run(c)
        let eps = try Self.run(c, policy: Self.fit(FitPolicy(continuumEfficiency: DetectorLayers())))
        #expect(eps.fit.backgroundLabel.contains("\u{03B5}") && !plain.fit.backgroundLabel.contains("\u{03B5}"))
        // Registered: chi2 falls. At the default orders (9, 5) it does not (0.01064 against 0.01052 here): the polynomial already
        // absorbs the roll-off, so both fit to the counts' rounding. It holds where the polynomial cannot: orders (3, 2).
        let lowPlain = try Self.run(c, policy: Self.fit(FitPolicy(continuumOrders: [3, 2])))
        let lowEps = try Self.run(c, policy: Self.fit(FitPolicy(continuumOrders: [3, 2], continuumEfficiency: DetectorLayers())))
        #expect(lowEps.fit.pearsonReducedChiSquared < lowPlain.fit.pearsonReducedChiSquared,
                "eps \(lowEps.fit.pearsonReducedChiSquared) plain \(lowPlain.fit.pearsonReducedChiSquared)")
    }

    // MARK: F7 and F10 the escape columns

    @Test func testEscapePeaksOffAndTheirRatioWarning() throws {
        let c = Self.counts(areas: ["Al_Ka": 30000, "Cu_Ka": 20000], escape: ["Cu_Ka": 0.03])
        let els: [(String, QuantificationMethod.ElementRole)] = [("Al", .quantify), ("Cu", .quantify)]
        let on = try Self.run(c, elements: els)
        let off = try Self.run(c, elements: els, policy: Self.fit(FitPolicy(escapePeaks: false)))
        #expect(on.fit.escapeValues.contains { $0 != nil } && off.fit.escapeValues.allSatisfy { $0 == nil })
        let cu = try #require(on.fit.groupIDs.firstIndex(of: "Cu_Ka"))
        #expect(abs(try #require(on.fit.escapeRatios[cu]) - 0.03) < 0.003)
        #expect(off.fit.pearsonReducedChiSquared > on.fit.pearsonReducedChiSquared)
        #expect(off.fit.escapeLabel != on.fit.escapeLabel)
        // The 5 % flag: 3 % does not trip it; at a level of 0.1 % it does, and the message names that level.
        #expect(!on.fit.warnings.contains { $0.contains("Si-escape/parent ratio") })
        let tight = try Self.run(c, elements: els, policy: Self.fit(FitPolicy(escapeRatioWarning: 0.001)))
        let w = try #require(tight.fit.warnings.first { $0.contains("Si-escape/parent ratio") })
        #expect(w.contains("exceeds 0.1 %"), "\(w)")
        // And at the default level the message still reads "5 %" when a 20 % escape is planted.
        let heavy = Self.counts(areas: ["Al_Ka": 30000, "Cu_Ka": 20000], escape: ["Cu_Ka": 0.2])
        let hw = try #require(try Self.run(heavy, elements: els).fit.warnings.first { $0.contains("Si-escape/parent ratio") })
        #expect(hw.contains("exceeds 5 %") && hw.contains("the 5 % flag"), "\(hw)")
    }

    @Test func testSumEscapeKeepsTheEscapeWarningLevelAndTheTypedErrorText() throws {
        let c = Self.counts(areas: ["Al_Ka": 30000, "Cu_Ka": 20000], escape: ["Cu_Ka": 0.03])
        let els: [(String, QuantificationMethod.ElementRole)] = [("Al", .quantify), ("Cu", .quantify)]
        var inp = Self.input(c, method: Self.method(els, locked: true), policy: Self.fit(FitPolicy(escapeRatioWarning: 0.001)))
        inp.sumEscape = SumEscapeModel(sumPeaks: true)
        let q = try PooledQuantifier.run(inp, tables: Self.tables)
        let w = try #require(q.fit.warnings.first { $0.contains("Si-escape/parent ratio") })
        #expect(w.contains("exceeds 0.1 %"), "\(w)")
        // A refused sum/escape model says why in words, not as an enum case dump.
        inp.sumEscape = SumEscapeModel(sumPeaks: true, parentCount: 0)
        do { _ = try PooledQuantifier.run(inp, tables: Self.tables); Issue.record("expected a refusal") }
        catch { #expect(error.localizedDescription.contains("at least one parent line group"), "\(error.localizedDescription)") }
    }

    // MARK: F8 - F9 the polynomial bound and the Poisson iteration

    @Test func testPolynomialOrderBoundAndPoissonIteration() throws {
        let c = Self.counts(areas: Self.threeAreas)
        var poly = Self.method(Self.threeElements); poly.background = .wholeRangePolynomial6; poly.polynomialOrder = 6
        let a = try PooledQuantifier.run(Self.input(c, method: poly), tables: Self.tables)
        let b = try PooledQuantifier.run(Self.input(c, method: poly, policy: Self.fit(FitPolicy(maximumPolynomialOrder: 4))), tables: Self.tables)
        #expect(a.fit.backgroundLabel.contains("order 6") && b.fit.backgroundLabel.contains("order 4"), "\(a.fit.backgroundLabel) | \(b.fit.backgroundLabel)")
        var ml = Self.method(Self.threeElements); ml.estimator = .poissonMaximumLikelihood
        let d = try PooledQuantifier.run(Self.input(c, method: ml), tables: Self.tables)
        let loose = try PooledQuantifier.run(Self.input(c, method: ml, policy: Self.fit(FitPolicy(irls: IRLSSettings(tolerance: 1e-3)))), tables: Self.tables)
        let capped = try PooledQuantifier.run(Self.input(c, method: ml, policy: Self.fit(FitPolicy(irls: IRLSSettings(maxIterations: 2)))), tables: Self.tables)
        #expect(loose.fit.iterations <= d.fit.iterations)
        #expect(capped.fit.iterations <= 2 && !capped.fit.converged && capped.fit.exit == "cap reached", "\(capped.fit.exit) \(capped.fit.iterations)")
        #expect(d.fit.irls == IRLSSettings() && capped.fit.irls?.maxIterations == 2 && loose.fit.irls?.tolerance == 1e-3)
    }

    // MARK: F11 - F12 the axis refinement

    @Test func testAxisRefinementOptions() throws {
        // Planted on a 5 eV shifted axis at 150 eV width; the file says offset 0 and 130 eV.
        let shifted = EnergyAxis(offset: 0.005, scale: 0.01, size: 1500)
        let c = Self.counts(areas: Self.threeAreas, axis: shifted, resolution: 150)
        func refined(_ o: AxisRefinementSettings) throws -> AxisRefinementResult {
            try #require(try Self.run(c, policy: Self.fit(FitPolicy(axisRefinement: o)), locked: false).refinement)
        }
        let d = try refined(AxisRefinementSettings())
        #expect(d.resolutionMnKaEV > 140, "\(d.resolutionMnKaEV)")
        let noGain = try refined(AxisRefinementSettings(refineGain: false))
        #expect(noGain.gainShift == 0)
        #expect(d.gainShift != 0)
        let capped = try refined(AxisRefinementSettings(maxIterations: 3))
        #expect(!capped.converged && capped.iterations == 3 && capped.rssRefined >= d.rssRefined)
        let loose = try refined(AxisRefinementSettings(tolerance: 1e-3))
        #expect(loose.iterations <= d.iterations)
        let bounded = try refined(AxisRefinementSettings(minimumResolutionEV: 20, maximumResolutionEV: 140))
        #expect(bounded.resolutionMnKaEV < 140 && bounded.resolutionMnKaEV < d.resolutionMnKaEV, "\(bounded.resolutionMnKaEV) \(d.resolutionMnKaEV)")
    }

    // MARK: F13 the range-sensitivity alternative

    @Test func testRangeSensitivityAlternative() throws {
        let wide = EnergyAxis(offset: 0, scale: 0.04, size: 2000)               // to 79.96 keV
        let c = Self.counts(areas: ["Al_Ka": 30000, "Si_Ka": 12000, "Mg_Ka": 4000], axis: wide, resolution: 130)
        let els = Self.threeElements
        let inp = Self.input(c, axis: wide, method: Self.method(els))
        let q = try PooledQuantifier.run(inp, tables: Self.tables)
        #expect(q.fitRange.source == .defaultLimit)
        let reach = try #require(FitRangeSensitivityCheck.run(input: inp, quantification: q))
        #expect(abs(reach.alternativeToKeV - wide.highValue) < 1e-9)
        let forty = try #require(FitRangeSensitivityCheck.run(input: inp, quantification: q, alternativeToKeV: 40))
        #expect(forty.alternativeToKeV == 40 && forty.failure == nil && forty.line.contains("if fitted to 40 keV"), "\(forty.line)")
        // Not above the reported fit, or past the reach: nothing / the reach.
        #expect(FitRangeSensitivityCheck.run(input: inp, quantification: q, alternativeToKeV: 20) == nil)
        let past = try #require(FitRangeSensitivityCheck.run(input: inp, quantification: q, alternativeToKeV: 500))
        #expect(abs(past.alternativeToKeV - wide.highValue) < 1e-9)
    }

    // MARK: Q3 the reference element

    @Test func testFallbackReference() throws {
        let c = Self.counts(areas: ["Al_Ka": 20000, "Mg_Ka": 4000, "Si_Ka": 30000])
        let d = try Self.run(c)
        #expect(d.referenceElement == "Al")
        let n = try Self.run(c, policy: Self.abundance(AbundancePolicy(fallbackReference: nil)))
        #expect(n.referenceElement == "Si")
        let mg = try #require(n.rows.first { $0.element == "Mg" }), mgD = try #require(d.rows.first { $0.element == "Mg" })
        let si = try #require(n.rows.first { $0.element == "Si" }), al = try #require(d.rows.first { $0.element == "Al" })
        #expect(mg.kFreeRatio == mg.net / si.net && mgD.kFreeRatio == mgD.net / al.net)
        let mgFirst = try Self.run(c, policy: Self.abundance(AbundancePolicy(fallbackReference: "Mg")))
        #expect(mgFirst.referenceElement == "Mg")
    }

    // MARK: Q4 the computed-k detector

    @Test func testDetectorLayersMoveTheComputedK() throws {
        let c = Self.counts(areas: Self.threeAreas)
        let thin = try Self.run(c), thick = try Self.run(c, policy: Self.abundance(AbundancePolicy(detector: DetectorLayers(deadLayerMicrons: 1))))
        let alThick = try Self.run(c, policy: Self.abundance(AbundancePolicy(detector: DetectorLayers(aluminiumNm: 1000))))
        func ratio(_ q: PooledQuantification) throws -> Double {
            let k = try #require(q.kSet)
            return try #require(k.k("Mg")) / (try #require(k.k("Si")))
        }
        let rThick = try ratio(thick), rThin = try ratio(thin)
        #expect(rThick > rThin, "\(rThick) \(rThin)")
        #expect(alThick.method.kSource.contains("1000") && !thin.method.kSource.contains("1000"), "\(thin.method.kSource) | \(alThick.method.kSource)")
        // Registered: a thicker Al layer RAISES k_Mg / k_Si. It lowers it: the Al K edge (1.560 keV) lies between Mg K-alpha
        // (1.254) and Si K-alpha (1.740), so the layer absorbs Si K-alpha more. A silicon dead layer (Si K edge 1.839 keV, above
        // both lines) absorbs the lower line more, and raises it as predicted.
        let rAl = try ratio(alThick)
        #expect(rAl < rThin, "\(rAl) \(rThin)")
        let mgThin = try #require(thin.rows.first { $0.element == "Mg" }?.atomicPercent), mgThick = try #require(thick.rows.first { $0.element == "Mg" }?.atomicPercent)
        #expect(mgThick > mgThin)
    }

    // MARK: Q5 absorption iteration, Q6 derivative step

    private static func geometryMetadata() -> SpectrumImageMetadata {
        var m = metadata(axis)
        m.origin = .veloxEMD
        m.alphaTiltDegrees = -16.87; m.betaTiltDegrees = 0
        m.detectors = [(45.0, 0.4), (135.0, 0.2), (225.0, 0.1), (315.0, 0.3)].enumerated().map { i, a in
            SpectrumDetectorSegment(name: "SuperXG1\(i + 1)", azimuthDegrees: a.0, elevationDegrees: 22, solidAngle: a.1)
        }
        return m
    }

    @Test func testAbsorptionIterationAndDerivativeStep() throws {
        let c = Self.counts(areas: ["Al_Ka": 30000, "Mg_Ka": 9000, "Si_Ka": 12000])
        var m = Self.method(Self.threeElements)
        m.thickness = QuantificationMethod.Thickness(nanometres: 200, sigmaNanometres: 20)
        func run(_ p: QuantificationPolicy) throws -> PooledQuantification {
            try PooledQuantifier.run(Self.input(c, method: m, policy: p, metadata: Self.geometryMetadata()), tables: Self.tables)
        }
        let d = try run(.default)
        guard case .applied = d.absorption else { Issue.record("absorption not applied: \(d.absorption)"); return }
        let loose = try run(Self.abundance(AbundancePolicy(absorptionConvergencePercent: 0.5)))
        for (x, y) in zip(d.rows, loose.rows) {
            let a = try #require(x.atomicPercent), b = try #require(y.atomicPercent)
            #expect(a != b && abs(a - b) / a < 0.005, "\(x.element) \(a) \(b)")
        }
        let capped = try run(Self.abundance(AbundancePolicy(absorptionMaxIterations: 1)))
        #expect(capped.abundanceRefusal != nil && d.abundanceRefusal == nil)
        // The step of the counting term: the composition is untouched, the counting sigma moves by a little.
        let coarse = try run(Self.abundance(AbundancePolicy(derivativeRelativeStep: 0.1)))
        for (x, y) in zip(d.rows, coarse.rows) {
            #expect(x.atomicPercent == y.atomicPercent)
            let a = try #require(x.atomicTerms?[.counting]), b = try #require(y.atomicTerms?[.counting])
            #expect(a != b && abs(a - b) / a < 0.05, "\(x.element) \(a) \(b)")
        }
    }

    // MARK: Q7 one line above the floor

    @Test func testSingleLinePolicy() throws {
        let c = Self.counts(areas: ["Al_Ka": 30000], continuum: { _ in 0 })   // no background: Si's window holds exact zeros
        let els: [(String, QuantificationMethod.ElementRole)] = [("Al", .quantify), ("Si", .quantify)]
        let refuse = try Self.run(c, elements: els)
        #expect(refuse.abundanceRefusal != nil, "nets \(refuse.rows.map(\.net)) refusal \(String(describing: refuse.abundanceRefusal)) at% \(refuse.rows.map { $0.atomicPercent })")
        let parity = try Self.run(c, elements: els, policy: Self.abundance(AbundancePolicy(singleLine: .exspyHundredPercent)))
        #expect(parity.abundanceRefusal == nil)
        #expect(parity.rows.first { $0.element == "Al" }?.atomicPercent == 100)
        #expect(parity.rows.first { $0.element == "Si" }?.atomicPercent == 0)
    }
}
