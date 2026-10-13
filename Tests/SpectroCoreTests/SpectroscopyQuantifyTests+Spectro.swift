// SpectroKit S1 test partition (ADR 064 section 3.3): the methods of SpectroscopyQuantifyTests that move with the EDX core;
// the rest stay in SpectroscopyQuantifyTests.swift. Helpers are duplicated, not shared, across the split.
import XCTest
import DSTEMCore

/// v5.0 R3: the Quantify verb on the simulated tiny GMS fixture (`demo-edx-tiny.dm4` + truth): the pooled fit, its
/// sigma as named terms, at% only with a k source, absorption refused where the geometry is unknown.
@MainActor
final class SpectroscopyQuantifySpectro: XCTestCase {

    static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")
    static let resources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("mac4DSTEM/Resources/Spectroscopy")
    static let tables = try! QuantificationTables(directory: resources)

    static func image() throws -> LoadedSpectrumImage {
        try XCTUnwrap(try SpectrumImageOpener.openGMSEDS(path: fixtures.appendingPathComponent("demo-edx-tiny.dm4").path, fourD: nil))
    }

    /// Truth: the summed expected counts of the named component over the whole map.
    static func truthArea(_ component: String) throws -> Double {
        let data = try Data(contentsOf: fixtures.appendingPathComponent("demo-edx-tiny.truth.json"))
        let t = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let names = try XCTUnwrap(t["component_names"] as? [String])
        let arrays = try XCTUnwrap(t["arrays"] as? [String: Any])
        let comp = try XCTUnwrap(arrays["component_expected_counts"] as? [[[Double]]])
        let i = try XCTUnwrap(names.firstIndex(of: component))
        return comp[i].flatMap { $0 }.reduce(0, +)
    }

    static func method(elements: [(String, QuantificationMethod.ElementRole)] = [("Al", .quantify), ("Mg", .quantify), ("Si", .quantify), ("Cu", .quantify), ("O", .fitOnly), ("Ga", .fitOnly)]) -> QuantificationMethod {
        var m = QuantificationMethod()
        m.elements = elements.map { QuantificationMethod.ElementState(symbol: $0.0, role: $0.1, isManual: false) }
        m.beamEnergyKeV = 200          // the GMS EDS object does not state it
        return m
    }

    static func input(_ method: QuantificationMethod, image: LoadedSpectrumImage) -> PooledQuantificationInput {
        PooledQuantificationInput(counts: image.sum(mask: nil), axis: image.energyAxis, method: method, metadata: image.metadata,
                                  regionName: "Whole map", pixelCount: image.metadata.pixelCount)
    }

    // MARK: - R7 (wp3e item 2): the misfit is shown and exported

    /// "chi2_r 54.8 (Pearson)" beside the result and the footer line "sigma is counting statistics at chi2_r = 1; this fit is at <x>",
    /// which the export carries. Mutation: drop `footer.append(sigmaFitLine(...))` in `PooledQuantifier.run` - red.
    func testTheFitsChiSquaredIsShownAndExportedBesideTheSigmaScope() throws {
        let r = try PooledQuantifier.run(Self.input(Self.method(), image: try Self.image()), tables: Self.tables)
        let x = PooledQuantifier.qualityText(label: r.qualityLabel, value: r.quality)
        XCTAssertEqual(r.qualityText, x)
        XCTAssertTrue(x.hasPrefix("\u{03C7}\u{00B2}\u{1D63} ") && x.hasSuffix(" (Pearson)"), x)
        let value = x.dropFirst(4).dropLast(" (Pearson)".count)
        XCTAssertEqual(Double(value) ?? -1, r.quality, accuracy: 0.5)
        let line = try XCTUnwrap(r.footerLines.first { $0.hasPrefix("\u{03C3} is counting statistics at \u{03C7}\u{00B2}\u{1D63} = 1; this fit is at ") }, "\(r.footerLines)")
        XCTAssertTrue(line.hasSuffix(String(value) + " (Pearson)"), line)
        XCTAssertTrue(SpectroscopyExport.csv(r, regionName: "w").contains("# " + line))
        // The formatting: 2 decimals under 10, 1 under 100, none above; a deviance fit says so.
        XCTAssertEqual(PooledQuantifier.qualityText(label: "\u{03C7}\u{00B2}\u{1D63} (Pearson)", value: 54.83), "\u{03C7}\u{00B2}\u{1D63} 54.8 (Pearson)")
        XCTAssertEqual(PooledQuantifier.qualityText(label: "\u{03C7}\u{00B2}\u{1D63} (Pearson)", value: 3318.4), "\u{03C7}\u{00B2}\u{1D63} 3318 (Pearson)")
        XCTAssertEqual(PooledQuantifier.qualityText(label: "reduced deviance", value: 1.024), "reduced deviance 1.02")
        XCTAssertEqual(PooledQuantifier.sigmaFitLine(label: "reduced deviance", value: 1.024), "\u{03C3} is counting statistics at reduced deviance = 1; this fit is at 1.02")
    }

    // MARK: - The pooled fit against truth

    /// The fixture's pooled whole map (24 px, ~700 counts): every quantified area lies within 2 sigma of the planted truth.
    /// Measured 2026-10-06 (scratch run): Al 467.4 +- 46.7 vs 477.6; Mg 27.5 +- 9.7 vs 18.4; Si 48.5 +- 8.2 vs 41.4;
    /// Cu 4.7 +- 2.6 vs 0.34 (1.7 sigma), so 2 sigma is the bar, not 1.
    /// Mutation: the row's net multiplied by 1.5 in `PooledQuantifier.run` - red (Al is 47 sigma... 0.5 * 478 / 47 = 5 sigma off).
    func testPooledAreasAreWithinTwoSigmaOfTruth() throws {
        let image = try Self.image()
        let r = try PooledQuantifier.run(Self.input(Self.method(), image: image), tables: Self.tables)
        XCTAssertEqual(r.rows.map(\.element), ["Al", "Mg", "Si", "Cu"])
        for (el, comp) in [("Al", "Al_Ka"), ("Mg", "Mg_Ka"), ("Si", "Si_Ka"), ("Cu", "Cu_Ka")] {
            let row = try XCTUnwrap(r.rows.first { $0.element == el })
            let truth = try Self.truthArea(comp)
            XCTAssertGreaterThan(row.sigma, 0, el)
            XCTAssertLessThanOrEqual(abs(row.net - truth), 2 * row.sigma, "\(el): fit \(row.net) +- \(row.sigma), truth \(truth)")
        }
        // The k-free ratios are areas over the reference's (Al, the largest): the reference is exactly 1 with no sigma.
        XCTAssertEqual(r.referenceElement, "Al")
        let al = try XCTUnwrap(r.rows.first { $0.element == "Al" }), mg = try XCTUnwrap(r.rows.first { $0.element == "Mg" })
        XCTAssertEqual(al.kFreeRatio, 1); XCTAssertNil(al.kFreeSigma)
        XCTAssertEqual(try XCTUnwrap(mg.kFreeRatio), mg.net / al.net, accuracy: 1e-12)
        XCTAssertGreaterThan(try XCTUnwrap(mg.kFreeSigma), 0)
        // Fit quality and the plot curves: model and background exist where the fit ran and are zero elsewhere.
        XCTAssertEqual(r.qualityLabel, "\u{03C7}\u{00B2}\u{1D63} (Pearson)")
        XCTAssertTrue(r.quality.isFinite && r.quality > 0)
        XCTAssertEqual(r.plotModel.count, image.energyAxis.size)
        XCTAssertEqual(r.plotModel[0], 0); XCTAssertGreaterThan(r.plotModel[r.fit.channels.lowerBound + 40], 0)
        XCTAssertGreaterThan(r.plotBackground[r.fit.channels.lowerBound + 40], 0)
    }

    /// The Expert estimator is Poisson ML; the footer names it and the quality is a deviance.
    /// Mutation: `method.estimator` ignored in `settings(axis:)` - red.
    func testPoissonMLIsNamedAndReportsADeviance() throws {
        var m = Self.method(); m.estimator = .poissonMaximumLikelihood
        let r = try PooledQuantifier.run(Self.input(m, image: try Self.image()), tables: Self.tables)
        XCTAssertEqual(r.qualityLabel, "reduced deviance")
        XCTAssertTrue(r.footerLines[0].lowercased().contains("poisson"), r.footerLines[0])
    }

    // MARK: - Absorption

    private static func veloxMetadata(from m: SpectrumImageMetadata, tilt: Double? = -16.87) -> SpectrumImageMetadata {
        var v = m
        v.origin = .veloxEMD
        v.alphaTiltDegrees = tilt
        v.betaTiltDegrees = 0
        v.detectors = [(45.0, 0.4), (135.0, 0.2), (225.0, 0.1), (315.0, 0.3)].enumerated().map { i, a in
            SpectrumDetectorSegment(name: "SuperXG1\(i + 1)", azimuthDegrees: a.0, elevationDegrees: 22, solidAngle: a.1)
        }
        return v
    }

    /// GMS: refused with the reason (the tilt and the segments are not read yet), at% still produced without the
    /// correction and the footer says so. Mutation: the GMS guard in `geometry(_:_:)` removed - the single GMS segment
    /// then needs a tilt and the reason changes to the tilt's, red.
    func testAbsorptionIsRefusedOnAGMSFileWithTheReason() throws {
        let image = try Self.image()
        XCTAssertEqual(image.metadata.origin, .gmsDM4)
        var m = Self.method(); m.thickness = .init(nanometres: 80, sigmaNanometres: 15)   // a thickness does not rescue it
        let r = try PooledQuantifier.run(Self.input(m, image: image), tables: Self.tables)
        guard case .refused(let why) = r.absorption else { return XCTFail("\(r.absorption)") }
        XCTAssertTrue(why.contains("GMS") && why.contains("tilt"), why)
        XCTAssertTrue(r.hasAbundance, "at% is computed without the correction, never withheld silently")
        XCTAssertTrue(r.footerLines.contains { $0.hasPrefix("absorption: not applied") && $0.contains("GMS") })
        XCTAssertTrue(try XCTUnwrap(r.rows.first { $0.element == "Mg" }).atomicTermsText.contains("absorption not applied"))
    }

    /// Velox-style metadata: applied with its geometry summary, a thickness term and an absorption term; a missing tilt
    /// or a missing thickness is refused with its own reason; off is off.
    /// Mutation: the thickness term left 0 (the `ThicknessPropagation` call removed) - red.
    func testAbsorptionAppliesWithGeometryTiltAndThickness() throws {
        let image = try Self.image()
        let meta = Self.veloxMetadata(from: image.metadata)
        var input = Self.input({ var m = Self.method(); m.thickness = .init(nanometres: 80, sigmaNanometres: 15); return m }(), image: image)
        input.metadata = meta
        let withAbs = try PooledQuantifier.run(input, tables: Self.tables)
        guard case .applied(let s) = withAbs.absorption else { return XCTFail("\(withAbs.absorption)") }
        XCTAssertTrue(s.contains("4 segments") && s.contains("80 \u{00B1} 15 nm") && s.contains("badged"), s)
        let mg = try XCTUnwrap(withAbs.rows.first { $0.element == "Mg" })
        XCTAssertGreaterThan(try XCTUnwrap(mg.atomicTerms)[.thickness], 0)
        // The AM-vs-GM spread is a model spread, printed beside the sigma and kept OUT of the terms and the total.
        XCTAssertEqual(try XCTUnwrap(mg.atomicTerms)[.absorption], 0)
        XCTAssertGreaterThan(try XCTUnwrap(mg.absorptionSpreadAtomic), 0)
        XCTAssertTrue(mg.atomicTermsText.contains("thickness ") && mg.atomicTermsText.contains("absorption model spread (AM vs GM)")
                      && mg.atomicTermsText.contains("not in the total") && !mg.atomicTermsText.contains("not applied"), mg.atomicTermsText)
        let q = try XCTUnwrap(mg.atomicTerms)
        XCTAssertEqual(try XCTUnwrap(mg.atomicSigma), (pow(q[.counting], 2) + pow(q[.k], 2) + pow(q[.thickness], 2)).squareRoot() * mg.atomicPercent!, accuracy: 1e-9)
        // The correction raises the light elements relative to the uncorrected composition.
        var off = input; off.method.absorptionCorrection = false
        let without = try PooledQuantifier.run(off, tables: Self.tables)
        XCTAssertEqual(without.absorption, .off)
        XCTAssertNotEqual(try XCTUnwrap(mg.atomicPercent), try XCTUnwrap(without.rows.first { $0.element == "Mg" }?.atomicPercent))

        // No thickness sigma typed: said so, not "thickness 0.0 %".
        var noSigma = input; noSigma.method.thickness = .init(nanometres: 80, sigmaNanometres: 0)
        let ns = try XCTUnwrap(try PooledQuantifier.run(noSigma, tables: Self.tables).rows.first { $0.element == "Mg" })
        XCTAssertTrue(ns.atomicTermsText.contains("thickness \u{03C3} not typed"), ns.atomicTermsText)

        var noTilt = input; noTilt.metadata = Self.veloxMetadata(from: image.metadata, tilt: nil)
        guard case .refused(let a) = try PooledQuantifier.run(noTilt, tables: Self.tables).absorption else { return XCTFail() }
        XCTAssertTrue(a.lowercased().contains("tilt"), a)
        var noT = input; noT.method.thickness = nil
        guard case .refused(let b) = try PooledQuantifier.run(noT, tables: Self.tables).absorption else { return XCTFail() }
        XCTAssertTrue(b.contains("no thickness"), b)
    }

    func testARunWithoutABeamEnergyOrElementsIsRefused() throws {
        let image = try Self.image()
        var meta = image.metadata; meta.beamEnergyKeV = nil           // a file that states no beam energy (the simulated GMS file now does)
        let bare = LoadedSpectrumImage(image: image.image, metadata: meta, energyAxis: image.energyAxis, scanImage: image.scanImage)
        var m = Self.method(); m.beamEnergyKeV = nil
        XCTAssertThrowsError(try PooledQuantifier.run(Self.input(m, image: bare), tables: Self.tables)) {
            XCTAssertTrue(($0 as? QuantificationRefusal)?.reason.contains("beam energy") == true)
        }
        XCTAssertThrowsError(try PooledQuantifier.run(Self.input(Self.method(elements: []), image: image), tables: Self.tables))
    }

    // MARK: - Settings <-> method; the byte-stable hash

    /// The three new method fields are Optional so every earlier method keeps its bytes (and so its replay hash).
    /// Mutation: `lockEnergyAxis` made a plain Bool - the key appears in the default JSON, red.
    func testNewMethodFieldsDoNotChangeTheDefaultJSON() {
        let json = QuantificationMethod().canonicalJSON
        for key in ["beamEnergyKeV", "polynomialOrder", "lockEnergyAxis"] { XCTAssertFalse(json.contains(key), key) }
        var m = QuantificationMethod(); m.polynomialOrder = 4; m.lockEnergyAxis = true; m.beamEnergyKeV = 200
        XCTAssertEqual(QuantificationMethod.decode(m.canonicalJSON), m)
        XCTAssertNotEqual(m.hash, QuantificationMethod().hash)
    }

    /// The sigma_k sentence is built from the set: flat or per factor, with or without a reference.
    /// Mutation: the old hard-coded "flat, 0 on the reference" restored - red.
    func testTheKFooterDescribesTheSetItUsed() throws {
        let image = try Self.image()
        let computed = try PooledQuantifier.run(Self.input(Self.method(), image: image), tables: Self.tables)
        XCTAssertTrue(computed.footerLines.contains { $0.contains("\u{03C3}_k 20 % flat, 0 on the reference (Al)") }, "\(computed.footerLines)")
        var typed = Self.method(); typed.kFactorSource = .typed
        typed.kSource = "test"; typed.kDate = "2026-10-06"; typed.sigmaK = 0.1
        typed.typedK = [("Al", 1.0), ("Mg", 1.1), ("Si", 1.2), ("Cu", 1.9)].map { .init(element: $0.0, k: $0.1, relativeSigma: $0.0 == "Cu" ? 0.3 : nil) }
        let r = try PooledQuantifier.run(Self.input(typed, image: image), tables: Self.tables)
        let line = try XCTUnwrap(r.footerLines.first { $0.hasPrefix("k: test") })
        XCTAssertTrue(line.contains("no reference") && line.contains("Cu 30 %") && !line.contains("flat"), line)
    }
}
