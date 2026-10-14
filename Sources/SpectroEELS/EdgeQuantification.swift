//
//  EdgeQuantification.swift
//  Role: EELS slice 2 (docs/eels-slice-2-registration.md): the areal density of one element from a core-loss spectrum
//        image by the ratio method (Egerton, EELS in the Electron Microscope, 3rd ed., eqs. 4.65 and 4.66): the power-law
//        background (`PowerLawBackground`), the edge counts over [E_k, E_k + Δ), the partial cross section from exSpy's dft
//        GOS (`EdgeCrossSection`), and the low-loss intensity, per pixel; with the counting-statistics σ.
//

import Foundation
import SpectroCore

/// A core-loss EELS spectrum image: `ny x nx` pixels of `channels` counts each on a uniform energy axis in eV.
///
/// Layout and axis as `LowLossSpectrumImage`: `counts[(y * nx + x) * channels + c]`, channel c at `energyOffsetEV +
/// energyScaleEV * c`, counts per channel (a binned axis). Every count must be finite.
public nonisolated struct CoreLossSpectrumImage: Sendable {
    public let nx: Int
    public let ny: Int
    public let channels: Int
    public let counts: [Double]
    public let energyOffsetEV: Double
    public let energyScaleEV: Double

    public init(nx: Int, ny: Int, channels: Int, counts: [Double], energyOffsetEV: Double, energyScaleEV: Double) throws {
        guard nx > 0, ny > 0, channels > 0, nx <= Int.max / ny, nx * ny <= Int.max / channels,
              counts.count == nx * ny * channels else {
            throw EELSEdgeError.invalidShape(nx: nx, ny: ny, channels: channels, counts: counts.count)
        }
        guard energyOffsetEV.isFinite, energyScaleEV.isFinite, energyScaleEV > 0 else {
            throw EELSEdgeError.invalidEnergyAxis(offsetEV: energyOffsetEV, scaleEV: energyScaleEV)
        }
        if let bad = counts.firstIndex(where: { !$0.isFinite }) { throw EELSEdgeError.nonFiniteCounts(pixel: bad / channels) }
        self.nx = nx; self.ny = ny; self.channels = channels; self.counts = counts
        self.energyOffsetEV = energyOffsetEV; self.energyScaleEV = energyScaleEV
    }

    /// The same from single-precision counts (widened exactly).
    public init(nx: Int, ny: Int, channels: Int, counts: [Float], energyOffsetEV: Double, energyScaleEV: Double) throws {
        try self.init(nx: nx, ny: ny, channels: channels, counts: counts.map { Double($0) },
                      energyOffsetEV: energyOffsetEV, energyScaleEV: energyScaleEV)
    }

    public var pixelCount: Int { nx * ny }
}

/// The microscope parameters the cross section needs.
public nonisolated struct EELSMicroscope: Sendable, Equatable {
    /// Beam energy, keV.
    public let beamEnergyKeV: Double
    /// Convergence semi-angle α, mrad (0 for a parallel beam).
    public let convergenceMrad: Double
    /// Collection semi-angle β, mrad.
    public let collectionMrad: Double

    public init(beamEnergyKeV: Double, convergenceMrad: Double, collectionMrad: Double) {
        self.beamEnergyKeV = beamEnergyKeV; self.convergenceMrad = convergenceMrad; self.collectionMrad = collectionMrad
    }
}

/// Where I_low, the low-loss intensity of the ratio, comes from.
public nonisolated enum LowLossIntensity: Sendable {
    /// I_low(Δ): the low-loss counts from its first channel to the channel of energy Δ (end exclusive), Egerton eq. 4.66,
    /// the correction for plural scattering. The default route.
    case integratedToWidth(LowLossSpectrumImage)
    /// I_0 of slice 1's thickness map (the zero-loss sum), Egerton eq. 4.65, for single scattering only.
    case zeroLoss(ThicknessMap)
}

/// Why a pixel has no areal density.
public nonisolated enum EdgeUnavailable: String, Error, Sendable, Equatable, CustomStringConvertible {
    case backgroundSumNotPositive = "a background-window sum is not positive"
    case backgroundNotFinite = "the power law's A or r is not finite"
    case lowLossNotPositive = "I_low is not positive"
    case lowLossUnavailable = "the thickness map has no I_0 for this pixel"
    public var description: String { rawValue }
}

/// One pixel of an areal-density map.
public nonisolated struct ArealDensityPixel: Sendable, Equatable {
    /// Atoms per nm²; nil with `unavailable` set.
    public let atomsPerNM2: Double?
    /// Counting-statistics standard deviation of `atomsPerNM2` (registration section 6; not the model, cross-section,
    /// angle, dose-ratio or onset errors).
    public let sigmaCounting: Double?
    /// Background-subtracted edge counts I_k over the edge window (may be negative).
    public let edgeCounts: Double?
    /// Background counts I_b under the edge window.
    public let backgroundCounts: Double?
    /// The power law's r and A (A for the background per eV; times the channel width per channel).
    public let powerLawR: Double?
    public let powerLawA: Double?
    /// I_low as used, after the dose ratio.
    public let lowLossIntensity: Double?
    public let unavailable: EdgeUnavailable?
}

/// An areal-density map of one edge, with how it was made.
public nonisolated struct ArealDensityMap: Sendable {
    public let nx: Int
    public let ny: Int
    public let pixels: [ArealDensityPixel]
    public let edge: CoreLossEdge
    public let microscope: EELSMicroscope
    /// The effective collection angle the cross section used, mrad.
    public let effectiveCollectionMrad: Double
    /// The partial cross section σ_k(β, Δ) over the edge window's channels, barn.
    public let crossSectionBarn: Double
    /// The background window as HyperSpy's two-area method used it (channel energies x1 and x2), eV.
    public let backgroundWindowEV: ClosedRange<Double>
    /// The edge window [start, end), eV, as given (the channels are HyperSpy's value slicing of it).
    public let edgeWindowEV: Range<Double>
    public let edgeChannels: Range<Int>
    public let lowLossRoute: String
    public let coreLossToLowLossDose: Double
    public let method: String
    /// Always "none": agreement with exSpy and planted truth are not validation (registration section 9).
    public let validation: String
}

/// Inputs the method cannot start from (a pixel it cannot answer is a nil with a reason, not a throw).
public nonisolated enum EELSEdgeError: Error, Equatable, Sendable {
    case invalidShape(nx: Int, ny: Int, channels: Int, counts: Int)
    case invalidEnergyAxis(offsetEV: Double, scaleEV: Double)
    case nonFiniteCounts(pixel: Int)
    case noBundledCrossSection(element: String, subshell: String)
    case crossSectionFailed
    case invalidMicroscope
    case backgroundWindowTooNarrow(fromEV: Double, toEV: Double)
    case backgroundWindowNotPositive(fromEV: Double)
    case edgeWindowOutsideAxis(fromEV: Double, toEV: Double)
    case lowLossShapeMismatch(expected: Int, got: Int)
    case invalidIntegrationWidth(Double)
    case invalidDoseRatio(Double)
}

public nonisolated enum EELSEdgeQuantification {

    public static let methodName =
        "power law (two-area, HyperSpy 2.4.0) + ratio method (Egerton eq. 4.65/4.66), cross section exSpy 7185a4d1 dft GOS (Segger, Guzzinati and Kohl 1.5.0)"

    /// The registered default background window: [E_k − 50, E_k − 5] eV.
    public static func defaultBackgroundWindow(onsetEV: Double) -> ClosedRange<Double> { (onsetEV - 50)...(onsetEV - 5) }

    /// The energy-differential cross section of `edge` at `energiesEV`, barn/eV (exSpy's `EELSCLEdge.function` with
    /// intensity 1), and the effective collection angle used.
    public static func differentialCrossSection(edge: CoreLossEdge, microscope: EELSMicroscope, energiesEV: [Double])
        throws -> (barnPerEV: [Double], effectiveCollectionMrad: Double) {
        let xs = try crossSection(edge: edge, microscope: microscope)
        return (xs.differential(energiesEV), xs.effectiveAngleMrad)
    }

    /// Areal density n = I_k / (I_low σ_k) per pixel, atoms/nm² (σ in barn; 1 barn = 1e-10 nm²).
    ///
    /// - Parameters:
    ///   - coreLoss: the core-loss spectrum image (counts per channel).
    ///   - edge: one of `CoreLossEdge.bundled`.
    ///   - microscope: E0, α, β of the acquisition.
    ///   - lowLoss: where I_low comes from; its pixels must match `coreLoss`'s.
    ///   - backgroundWindowEV: the pre-edge window; default [E_k − 50, E_k − 5] eV.
    ///   - edgeOnsetEV: the window's start; default the edge's tabulated onset (the cross section always starts there).
    ///   - integrationWidthEV: Δ, default 50 eV.
    ///   - coreLossToLowLossDose: exposure(core loss) / exposure(low loss), multiplies I_low (Dual EELS). The caller's
    ///     number: no reader supplies it.
    public static func ratioMethod(
        coreLoss: CoreLossSpectrumImage,
        edge: CoreLossEdge = .carbonK,
        microscope: EELSMicroscope,
        lowLoss: LowLossIntensity,
        backgroundWindowEV: ClosedRange<Double>? = nil,
        edgeOnsetEV: Double? = nil,
        integrationWidthEV: Double = 50,
        coreLossToLowLossDose: Double = 1,
        cancelled: @Sendable () -> Bool = SpectroCancellation.task
    ) throws -> ArealDensityMap {
        guard integrationWidthEV > 0, integrationWidthEV.isFinite else { throw EELSEdgeError.invalidIntegrationWidth(integrationWidthEV) }
        guard coreLossToLowLossDose > 0, coreLossToLowLossDose.isFinite else { throw EELSEdgeError.invalidDoseRatio(coreLossToLowLossDose) }
        let np = coreLoss.pixelCount, nch = coreLoss.channels, scale = coreLoss.energyScaleEV
        let axis = try EELSAxis(offset: coreLoss.energyOffsetEV, scale: scale, size: nch)
        let onset = edgeOnsetEV ?? edge.onsetEV
        let bgRange = backgroundWindowEV ?? defaultBackgroundWindow(onsetEV: onset)
        let window = try PowerLawWindow(axis: axis, from: bgRange.lowerBound, to: bgRange.upperBound)
        let edgeEnd = onset + integrationWidthEV
        let channels: Range<Int>
        do { channels = try axis.rules.channelRange(from: onset, to: edgeEnd) } catch {
            throw EELSEdgeError.edgeWindowOutsideAxis(fromEV: onset, toEV: edgeEnd)
        }
        guard !channels.isEmpty else { throw EELSEdgeError.edgeWindowOutsideAxis(fromEV: onset, toEV: edgeEnd) }
        let energies = channels.map { axis.energy(ofChannel: $0) }

        let xs = try crossSection(edge: edge, microscope: microscope)
        let sigma = NumpySum.sum(xs.differential(energies).map { $0 * scale })   // np.sum(function[i0:i1] * scale)

        // I_low per pixel (before the dose ratio) and its route's name.
        let lowLossRaw: [Double?]
        let route: String
        switch lowLoss {
        case .integratedToWidth(let ll):
            guard ll.pixelCount == np else { throw EELSEdgeError.lowLossShapeMismatch(expected: np, got: ll.pixelCount) }
            let llAxis = try EELSAxis(offset: ll.energyOffsetEV, scale: ll.energyScaleEV, size: ll.channels)
            let stop = try llAxis.zeroLossStop(forFixedThreshold: integrationWidthEV)
            lowLossRaw = ll.counts.withUnsafeBufferPointer { b in
                (0 ..< np).map { p in NumpySum.pairwise(b.baseAddress! + p * ll.channels, count: stop) }
            }
            route = "I_low(Δ): low-loss sum to \(integrationWidthEV) eV (Egerton eq. 4.66)"
        case .zeroLoss(let map):
            guard map.pixels.count == np else { throw EELSEdgeError.lowLossShapeMismatch(expected: np, got: map.pixels.count) }
            lowLossRaw = map.pixels.map { $0.i0 }
            route = "I_0 from the thickness map (Egerton eq. 4.65)"
        }

        var pixels = [ArealDensityPixel]()
        pixels.reserveCapacity(np)
        try coreLoss.counts.withUnsafeBufferPointer { buf in
            for p in 0 ..< np {
                if p % 4096 == 0, cancelled() { throw SpectroCancelled() }
                let spectrum = UnsafeBufferPointer(rebasing: buf[(p * nch) ..< ((p + 1) * nch)])
                pixels.append(pixel(spectrum, window: window, channels: channels, energies: energies, scale: scale,
                                    sigma: sigma, lowLossRaw: lowLossRaw[p], dose: coreLossToLowLossDose))
            }
        }
        return ArealDensityMap(
            nx: coreLoss.nx, ny: coreLoss.ny, pixels: pixels, edge: edge, microscope: microscope,
            effectiveCollectionMrad: xs.effectiveAngleMrad, crossSectionBarn: sigma,
            backgroundWindowEV: window.x1...window.x2, edgeWindowEV: onset ..< edgeEnd, edgeChannels: channels,
            lowLossRoute: route, coreLossToLowLossDose: coreLossToLowLossDose, method: methodName, validation: "none")
    }

    private static func crossSection(edge: CoreLossEdge, microscope m: EELSMicroscope) throws -> EdgeCrossSection {
        guard m.beamEnergyKeV > 0, m.collectionMrad > 0, m.convergenceMrad >= 0,
              m.beamEnergyKeV.isFinite, m.collectionMrad.isFinite, m.convergenceMrad.isFinite else {
            throw EELSEdgeError.invalidMicroscope
        }
        guard let table = GOSTable.bundled(edge) else {
            throw EELSEdgeError.noBundledCrossSection(element: edge.element, subshell: edge.subshell)
        }
        guard let xs = EdgeCrossSection(table: table, beamEnergyKeV: m.beamEnergyKeV, convergenceMrad: m.convergenceMrad,
                                        collectionMrad: m.collectionMrad) else { throw EELSEdgeError.crossSectionFailed }
        return xs
    }

    private static func pixel(_ s: UnsafeBufferPointer<Double>, window: PowerLawWindow, channels: Range<Int>,
                              energies: [Double], scale: Double, sigma: Double, lowLossRaw: Double?, dose: Double)
        -> ArealDensityPixel {
        func none(_ why: EdgeUnavailable, r: Double? = nil, a: Double? = nil) -> ArealDensityPixel {
            ArealDensityPixel(atomsPerNM2: nil, sigmaCounting: nil, edgeCounts: nil, backgroundCounts: nil, powerLawR: r,
                              powerLawA: a, lowLossIntensity: nil, unavailable: why)
        }
        let fit: PowerLawFit
        switch PowerLawFit.estimate(s, window: window) {
        case .failure(let why): return none(why)
        case .success(let f): fit = f
        }
        // remove_background: signal − model per channel, then the window's sum (pairwise, as NumPy sums a slice).
        var net = [Double](), bg = [Double]()
        net.reserveCapacity(channels.count); bg.reserveCapacity(channels.count)
        for (j, c) in channels.enumerated() {
            let b = fit.counts(atEnergy: energies[j], scale: scale)
            bg.append(b); net.append(s[c] - b)
        }
        let ik = NumpySum.sum(net), ib = NumpySum.sum(bg)
        guard let raw = lowLossRaw else { return none(.lowLossUnavailable, r: fit.r, a: fit.a) }
        guard raw > 0 else { return none(.lowLossNotPositive, r: fit.r, a: fit.a) }
        let iLow = raw * dose
        let n = ik / (iLow * sigma) * 1e10
        let (d1, d2) = fit.backgroundSensitivity(window: window, energies: energies, scale: scale)
        let varIk = (ik + ib) + d1 * d1 * fit.i1Sum + d2 * d2 * fit.i2Sum
        let sigmaN: Double? = (ik != 0 && varIk >= 0) ? abs(n) * (varIk / (ik * ik) + 1 / raw).squareRoot() : nil
        return ArealDensityPixel(atomsPerNM2: n, sigmaCounting: sigmaN, edgeCounts: ik, backgroundCounts: ib,
                                 powerLawR: fit.r, powerLawA: fit.a, lowLossIntensity: iLow, unavailable: nil)
    }
}
