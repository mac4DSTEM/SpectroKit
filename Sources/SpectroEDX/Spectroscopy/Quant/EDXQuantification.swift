//
//  EDXQuantification.swift
//  Role: the public thin-film EDX quantification: Cliff-Lorimer with typed k-factors, zeta-factor and ionisation
//        cross-section, with or without the absorption correction, on one spectrum's line intensities or per pixel over a
//        spectrum image (navigation mask, weight and atomic percent maps, live-time normalised dose).
//
//  Port of eXSpy signals/eds_tem.py `EDSTEMSpectrum.quantification` (297-575) over _misc/eds/utils.py
//  `quantification_cliff_lorimer`, `quantification_zeta_factor`, `quantification_cross_section`, `get_abs_corr_zeta`,
//  `get_abs_corr_cross_section` (exspy 0.3.2 with HyperSpy 2.4.0). The numbers come from the same package-level functions that
//  the pooled path uses (`CliffLorimer`, `ZetaFactor`, `AbsorptionCorrection`); this file only gives them a neutral public form.
//
//  DEVIATIONS from eXSpy:
//   * Each pixel iterates the absorption correction to its own convergence; eXSpy iterates the whole image together and stops
//     when the largest change anywhere is below the criterion. A pixel can therefore stop one iteration earlier or later than
//     eXSpy's: the two agree within the criterion (0.5 percentage points by default), which is the bound the tests use.
//   * A pixel that cannot be quantified (fewer than two lines above the floor for Cliff-Lorimer under `.refuse`, zero dose,
//     the correction did not converge) comes back as NaN with a `failure` string, never as a number. `singleLine:
//     .exspyHundredPercent` gives eXSpy's 100 % for one element.
//   * The dose is per pixel when `liveTimesSeconds` is given (live-time normalisation: a pixel that recorded less exposure is
//     not read as less matter); eXSpy has one live time for the whole image.
//   * `navigationMask` excludes a pixel (composition 0) for every method; exSpy applies its mask to Cliff-Lorimer only. exSpy's default
//     `navigation_mask=1.0` builds a vacuum mask itself (`vacuum_mask`); here the caller passes the mask.
//   * Cross section without absorption also returns the mass thickness (exSpy does not).
//   * Factors, thickness and the convergence settings must be finite and positive; negative or non-finite intensities fail the pixel.
//   * Quantification is `validation: "none"` (`EDXQuantification.validation`) until a standard of known composition is
//     measured; agreement with eXSpy is agreement, not truth.
//

import Foundation
import SpectroCore

/// Which quantification method, with its factors in the order of `EDXQuantificationSetup.elements`.
public nonisolated enum EDXQuantificationMethod: Sendable, Equatable {
    /// Cliff-Lorimer. `kFactors` are relative to any common element (only ratios enter). `thicknessNm` is required when
    /// `absorption` is set; with it the result carries the mass thickness (exSpy `CL_get_mass_thickness`).
    case cliffLorimer(kFactors: [Double], thicknessNm: Double?)
    /// Zeta-factor method; `zetaFactors` in kg/m^2 per electron-count unit as eXSpy takes them (`quantification_zeta_factor`).
    /// The dose is live time x beam current / e. The mass thickness (kg/m^2) comes out of the zeta sum.
    case zeta(zetaFactors: [Double])
    /// Ionisation cross sections in barns. The dose is live time x beam current / (e x probe area).
    case crossSection(sectionsBarn: [Double], probeAreaNm2: Double)
}

public nonisolated struct EDXAbsorptionSetting: Sendable, Equatable {
    /// Take-off angle in degrees (`EDXQuantification.takeOffAngle`).
    public var takeOffDegrees: Double
    /// The measured line's energy in keV, one per element, in the order of `elements`.
    public var lineEnergiesKeV: [Double]
    /// Largest change of any composition between two iterations, in percentage points, below which the loop stops.
    public var convergencePercent: Double
    public var maxIterations: Int
    /// eXSpy takes the SIGNED maximum of the change; `false` (default) takes the absolute one. Same fixed point.
    public var exspySignedCriterion: Bool

    public init(takeOffDegrees: Double, lineEnergiesKeV: [Double], convergencePercent: Double = 0.5,
                maxIterations: Int = 30, exspySignedCriterion: Bool = false) {
        self.takeOffDegrees = takeOffDegrees; self.lineEnergiesKeV = lineEnergiesKeV
        self.convergencePercent = convergencePercent; self.maxIterations = maxIterations
        self.exspySignedCriterion = exspySignedCriterion
    }
}

public nonisolated struct EDXQuantificationSetup: Sendable, Equatable {
    /// Element symbols, one per intensity, in the order the factors and intensities use.
    public var elements: [String]
    public var method: EDXQuantificationMethod
    public var absorption: EDXAbsorptionSetting?
    /// Probe current in nA (zeta and cross section).
    public var beamCurrentNA: Double?
    /// One live time in seconds for every pixel (zeta and cross section); `liveTimesSeconds` of the call overrides it.
    public var liveTimeSeconds: Double?
    public var singleLine: SingleLineRule

    public init(elements: [String], method: EDXQuantificationMethod, absorption: EDXAbsorptionSetting? = nil,
                beamCurrentNA: Double? = nil, liveTimeSeconds: Double? = nil, singleLine: SingleLineRule = .refuse) {
        self.elements = elements; self.method = method; self.absorption = absorption
        self.beamCurrentNA = beamCurrentNA; self.liveTimeSeconds = liveTimeSeconds; self.singleLine = singleLine
    }
}

/// One spectrum (or pixel).
public nonisolated struct EDXQuantificationPixel: Sendable, Equatable {
    public var weightPercent: [Double]
    public var atomicPercent: [Double]
    /// kg/m^2: from the zeta sum, from the cross-section atoms, or from the composition and the given thickness (CL with absorption).
    public var massThickness: Double?
    /// Atoms per pixel (cross section only).
    public var atoms: [Double]?
    /// Absorption iterations run (0 without correction).
    public var iterations: Int
    /// "none": see the file header.
    public var validation: String

    public init(weightPercent: [Double], atomicPercent: [Double], massThickness: Double? = nil, atoms: [Double]? = nil,
                iterations: Int = 0, validation: String = EDXQuantification.validation) {
        self.weightPercent = weightPercent; self.atomicPercent = atomicPercent; self.massThickness = massThickness
        self.atoms = atoms; self.iterations = iterations; self.validation = validation
    }
}

/// A spectrum image, rows x columns, row-major. NaN where `failures[i] != nil`; 0 where `navigationMask[i]`.
public nonisolated struct EDXQuantificationMaps: Sendable, Equatable {
    public var elements: [String]
    public var rows: Int
    public var columns: Int
    /// One map per element.
    public var weightPercent: [[Double]]
    public var atomicPercent: [[Double]]
    public var massThickness: [Double]?
    public var atoms: [[Double]]?
    public var iterations: [Int]
    public var failures: [String?]
    public var validation: String
}

public nonisolated enum EDXQuantification {
    public static let validation = "none"

    /// eXSpy `utils.eds.take_off_angle`, degrees (unlike eXSpy there are no defaults for a missing tilt: the caller states it).
    public static func takeOffAngle(tiltAlpha: Double, azimuth: Double, elevation: Double, tiltBeta: Double = 0) -> Double {
        TakeOff.angle(tiltAlpha: tiltAlpha, azimuth: azimuth, elevation: elevation, tiltBeta: tiltBeta)
    }

    /// eXSpy `material.weight_to_atomic`; percent in, percent out (sums to 100).
    public static func weightToAtomic(_ weight: [Double], elements: [String]) throws -> [Double] {
        try CompositionConversion.weightToAtomic(weight, elements: elements)
    }

    /// eXSpy `material.atomic_to_weight`.
    public static func atomicToWeight(_ atomic: [Double], elements: [String]) throws -> [Double] {
        try CompositionConversion.atomicToWeight(atomic, elements: elements)
    }

    /// eXSpy `utils.eds.cross_section_to_zeta` (barn to kg/m^2) and its inverse.
    public static func zetaFactors(fromCrossSectionsBarn s: [Double], elements: [String]) throws -> [Double] {
        try ZetaFactor.zetaFromCrossSection(s, elements: elements)
    }
    public static func crossSectionsBarn(fromZetaFactors z: [Double], elements: [String]) throws -> [Double] {
        try ZetaFactor.crossSectionFromZeta(z, elements: elements)
    }

    /// One spectrum's line intensities (counts or counts/s, any consistent unit for CL; counts for zeta and cross section).
    public static func quantify(intensities: [Double], setup: EDXQuantificationSetup,
                                liveTimeSeconds: Double? = nil) throws -> EDXQuantificationPixel {
        try validate(setup, count: intensities.count)
        return try solve(intensities, setup: setup, liveTime: liveTimeSeconds ?? setup.liveTimeSeconds)
    }

    /// Per-pixel quantification. `intensityMaps[e][pixel]` is element e's net intensity at a pixel (row-major, rows x columns).
    /// `navigationMask[pixel] == true` excludes the pixel (composition 0, as eXSpy's mask); `liveTimesSeconds[pixel]` is the
    /// pixel's live time (zeta and cross section; a pixel with live time <= 0 recorded nothing and fails).
    /// `takeOffDegreesPerPixel[pixel]` replaces `setup.absorption.takeOffDegrees` at that pixel (a tilted or curved specimen, a tilt
    /// series): it needs an absorption setting, one angle per pixel, and a pixel whose angle is not in (0, 90] degrees fails.
    public static func quantifyMaps(intensityMaps: [[Double]], rows: Int, columns: Int, setup: EDXQuantificationSetup,
                                    navigationMask: [Bool]? = nil, liveTimesSeconds: [Double]? = nil,
                                    takeOffDegreesPerPixel: [Double]? = nil) throws -> EDXQuantificationMaps {
        let n = intensityMaps.count
        try validate(setup, count: n)
        let pixels = rows * columns
        guard rows > 0, columns > 0, intensityMaps.allSatisfy({ $0.count == pixels }) else {
            throw QuantError.countMismatch("Each intensity map must hold rows x columns values.")
        }
        if let m = navigationMask, m.count != pixels { throw QuantError.countMismatch("The navigation mask must hold rows x columns values.") }
        if let t = liveTimesSeconds, t.count != pixels { throw QuantError.countMismatch("One live time per pixel.") }
        if let a = takeOffDegreesPerPixel {
            guard setup.absorption != nil else { throw QuantError.invalid("A take-off angle per pixel needs an absorption setting.") }
            guard a.count == pixels else { throw QuantError.countMismatch("One take-off angle per pixel.") }
        }

        var weight = [[Double]](repeating: [Double](repeating: 0, count: pixels), count: n)
        var atomic = weight
        var atoms: [[Double]]? = nil
        if case .crossSection = setup.method { atoms = weight }
        var mass: [Double]? = nil
        switch setup.method {
        case .cliffLorimer(_, let t): if t != nil { mass = [Double](repeating: 0, count: pixels) }
        default: mass = [Double](repeating: 0, count: pixels)
        }
        var iterations = [Int](repeating: 0, count: pixels)
        var failures = [String?](repeating: nil, count: pixels)

        // Pixels are independent, so the loop runs in chunks on all cores; each chunk writes its own slots, and the maps are
        // assembled afterwards in pixel order, so the result does not depend on the schedule.
        enum Outcome { case skipped, ok(EDXQuantificationPixel), failed(String) }
        final class Slots: @unchecked Sendable { var outcomes: [Outcome]; init(_ n: Int) { outcomes = [Outcome](repeating: .skipped, count: n) } }
        let slots = Slots(pixels)
        let chunk = 2048
        let chunks = (pixels + chunk - 1) / chunk
        slots.outcomes.withUnsafeMutableBufferPointer { buffer in
            nonisolated(unsafe) let out = buffer
            DispatchQueue.concurrentPerform(iterations: chunks) { ci in
                for p in (ci * chunk)..<min(pixels, (ci + 1) * chunk) {
                    if navigationMask?[p] == true { continue }
                    do {
                        out[p] = .ok(try solve((0..<n).map { intensityMaps[$0][p] }, setup: setup,
                                               liveTime: liveTimesSeconds?[p] ?? setup.liveTimeSeconds,
                                               takeOffDegrees: takeOffDegreesPerPixel?[p]))
                    } catch {
                        out[p] = .failed((error as? LocalizedError)?.errorDescription ?? "\(error)")
                    }
                }
            }
        }
        for p in 0..<pixels {
            switch slots.outcomes[p] {
            case .skipped: continue
            case .ok(let r):
                for e in 0..<n {
                    weight[e][p] = r.weightPercent[e]; atomic[e][p] = r.atomicPercent[e]
                    if let a = r.atoms { atoms?[e][p] = a[e] }
                }
                if let m = r.massThickness { mass?[p] = m }
                iterations[p] = r.iterations
            case .failed(let why):
                for e in 0..<n {
                    weight[e][p] = .nan; atomic[e][p] = .nan
                    if atoms != nil { atoms?[e][p] = .nan }
                }
                mass?[p] = .nan
                failures[p] = why
            }
        }
        return EDXQuantificationMaps(elements: setup.elements, rows: rows, columns: columns, weightPercent: weight,
                                     atomicPercent: atomic, massThickness: mass, atoms: atoms, iterations: iterations,
                                     failures: failures, validation: validation)
    }

    // MARK: -

    private static func validate(_ s: EDXQuantificationSetup, count: Int) throws {
        guard count > 1 else { throw QuantError.invalid("Several X-ray line intensities are required.") }
        guard s.elements.count == count else { throw QuantError.countMismatch("One element per intensity.") }
        let factors: Int
        switch s.method {
        case .cliffLorimer(let k, let t):
            factors = k.count
            if s.absorption != nil, t == nil { throw QuantError.invalid("Cliff-Lorimer with absorption needs the film thickness.") }
        case .zeta(let z): factors = z.count
        case .crossSection(let c, let area):
            factors = c.count
            guard area > 0 else { throw QuantError.invalid("The probe area must be positive.") }
        }
        func good(_ v: [Double]) -> Bool { v.allSatisfy { $0.isFinite && $0 > 0 } }
        switch s.method {
        case .cliffLorimer(let k, let t):
            guard good(k), t.map({ $0.isFinite && $0 > 0 }) ?? true else { throw QuantError.invalid("k-factors and the thickness must be finite and positive.") }
        case .zeta(let z): guard good(z) else { throw QuantError.invalid("Zeta-factors must be finite and positive.") }
        case .crossSection(let c, _): guard good(c) else { throw QuantError.invalid("Cross sections must be finite and positive.") }
        }
        guard factors == count else { throw QuantError.countMismatch("The number of factors must match the number of intensities.") }
        if let a = s.absorption {
            guard a.lineEnergiesKeV.count == count else { throw QuantError.countMismatch("One line energy per intensity.") }
            guard good(a.lineEnergiesKeV), a.convergencePercent.isFinite, a.convergencePercent > 0, a.maxIterations >= 1 else {
                throw QuantError.invalid("Line energies must be positive, the convergence criterion positive and at least one iteration allowed.")
            }
            guard a.takeOffDegrees > 0, a.takeOffDegrees <= 90 else { throw QuantError.grazingTakeOff(segment: "detector", degrees: a.takeOffDegrees) }
        }
        for el in s.elements where QuantElementData.entry(el) == nil { throw QuantError.unknownElement(el) }
    }

    private static func solve(_ intensities: [Double], setup s: EDXQuantificationSetup, liveTime: Double?,
                              takeOffDegrees: Double? = nil) throws -> EDXQuantificationPixel {
        guard intensities.allSatisfy({ $0.isFinite && $0 >= 0 }) else { throw QuantError.invalid("Intensities must be finite and not negative.") }
        var absSetup: AbsorptionSetup? = nil
        var options = AbsorptionIterationOptions()
        if let a = s.absorption {
            guard let table = MassAbsorptionTable.bundled else { throw QuantError.invalid("The mass-absorption table is missing from the bundle.") }
            let toa = takeOffDegrees ?? a.takeOffDegrees
            guard toa > 0, toa <= 90 else { throw QuantError.grazingTakeOff(segment: "detector", degrees: toa) }
            absSetup = AbsorptionSetup(elements: s.elements, lineEnergiesKeV: a.lineEnergiesKeV,
                                       geometry: SingleDetectorGeometry(takeOffDegrees: toa), table: table)
            options = AbsorptionIterationOptions(convergence: a.convergencePercent, maxIterations: a.maxIterations,
                                                 criterion: a.exspySignedCriterion ? .exspySigned : .absolute)
        }
        func dose(area: Double?) throws -> Double {
            guard let i = s.beamCurrentNA, let t = liveTime, i > 0, t > 0 else {
                throw QuantError.invalid("The dose needs a positive beam current and live time.")
            }
            return area == nil ? ZetaFactor.dose(liveTime: t, beamCurrentNA: i)
                               : ZetaFactor.doseCrossSection(liveTime: t, beamCurrentNA: i, probeAreaNm2: area!)
        }
        var wPct: [Double], mass: Double?, atoms: [Double]? = nil, iterations = 0
        switch s.method {
        case .cliffLorimer(let k, let thickness):
            if let setup = absSetup, let t = thickness {
                let r = try AbsorptionCorrection.cliffLorimer(intensities: intensities, kFactors: k, setup: setup, thicknessNm: t,
                                                              options: options, singleLine: s.singleLine)
                wPct = r.composition; mass = r.massThickness; iterations = r.iterations
            } else {
                wPct = try CliffLorimer.weightFractions(intensities: intensities, kFactors: k, singleLine: s.singleLine).map { $0 * 100 }
                // exSpy `CL_get_mass_thickness`: the weight-fraction mean of the pure-element densities times the thickness.
                mass = try thickness.map { try CliffLorimer.massThickness(weightPercent: wPct, elements: s.elements, thicknessNm: $0) }
            }
        case .zeta(let z):
            let d = try dose(area: nil)
            if let setup = absSetup {
                let r = try AbsorptionCorrection.zeta(intensities: intensities, zetaFactors: z, dose: d, setup: setup, options: options)
                wPct = r.composition; mass = r.massThickness; iterations = r.iterations
            } else {
                let r = try ZetaFactor.quantify(intensities: intensities, zetaFactors: z, dose: d)
                wPct = r.weightFractions.map { $0 * 100 }; mass = r.massThickness
            }
        case .crossSection(let c, let area):
            let d = try dose(area: area)
            let aPct: [Double]
            if let setup = absSetup {
                let r = try AbsorptionCorrection.crossSection(intensities: intensities, sectionsBarn: c, dose: d, probeAreaNm2: area,
                                                              setup: setup, options: options)
                aPct = r.composition; mass = r.massThickness; atoms = r.atoms; iterations = r.iterations
            } else {
                let r = try ZetaFactor.crossSection(intensities: intensities, sectionsBarn: c, dose: d)
                aPct = r.atomicFractions.map { $0 * 100 }; atoms = r.atoms
                var m = 0.0
                for (a, el) in zip(r.atoms, s.elements) {
                    m += a * QuantElementData.entry(el)!.atomicWeight / ZetaFactor.avogadro / 1e3 / area / 1e-18
                }
                mass = m
            }
            guard aPct.allSatisfy({ $0.isFinite }), (mass ?? 0).isFinite else { throw QuantError.invalid("The composition is not finite (zero dose or intensity).") }
            let w = try CompositionConversion.atomicToWeight(aPct, elements: s.elements)
            return EDXQuantificationPixel(weightPercent: w, atomicPercent: aPct, massThickness: mass, atoms: atoms,
                                          iterations: iterations, validation: validation)
        }
        guard wPct.allSatisfy({ $0.isFinite }) else { throw QuantError.invalid("The composition is not finite (zero dose or intensity).") }
        let atomic = try CompositionConversion.weightToAtomic(wPct, elements: s.elements)
        return EDXQuantificationPixel(weightPercent: wPct, atomicPercent: atomic, massThickness: mass, atoms: atoms,
                                      iterations: iterations, validation: validation)
    }
}
