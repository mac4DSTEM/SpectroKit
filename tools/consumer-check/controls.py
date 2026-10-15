#!/usr/bin/env python3
"""consumer-check negative controls (run through `run.sh --controls`; Python 3 standard library only).

The consumer package (tools/consumer-check) compiles only while every symbol it uses (SpectroEELS, and SpectroCore's spectrum-image opening) is public.
This proves it: for each such symbol, ONE declaration is reverted from `public` to `package` in a COPY of the repository
(rsync into <root>/.build/consumer-check/mutants/<name>, never the working tree), the consumer is built against the
copy (its Package.swift takes the dependency by path), and the build must FAIL with a compiler error that names that
symbol. A control is caught only when
  * the unedited copy builds (the baseline, so a failure is the edit's), and
  * the edit applied exactly once, and
  * the build exits non-zero, and the compiler's diagnostic is the expected one:
      "access": the consumer is refused, `error: '<member>' is inaccessible due to 'package' protection level`, and
                the note beside it points at the edited declaration (`SpectroCore.<Owner>.<member>: note: ... declared here`),
                so two declarations with one name are told apart;
      "overload": the reverted declaration is one of two overloads, so the compiler resolves the call to the public sibling and
                says so, naming the reverted labels: `error: incorrect argument label in call (have 'a:b:', expected 'c:d:')`
                (no control uses it since 0.4.0 moved the readers, which had the overloads, to FormatoKit);
      "type":   the library itself refuses the edit, because public members are typed with the now-package struct:
                `error: ... cannot be declared public because ... uses a package type`, at a source line that names the type.

usage: controls.py <repository root> [<symbol> ...]     (no symbol: all of them)
exit:  0 only when every control is caught.
"""
import hashlib
import os
import re
import shutil
import subprocess
import sys
import time

ROOT = os.path.abspath(sys.argv[1])
ONLY = sys.argv[2:]
NAME = os.path.basename(ROOT)
MUTANTS = os.path.join(ROOT, ".build", "consumer-check", "mutants")
COPY = os.path.join(MUTANTS, NAME)
LOGS = os.path.join(MUTANTS, "logs")
CONSUMER = os.path.join(COPY, "tools", "consumer-check")
CORE = "Sources/SpectroCore/Spectroscopy/"
OPENER = CORE + "SpectrumImageOpening.swift"
SOURCE = CORE + "SpectrumImageSource.swift"
AXIS = CORE + "EnergyAxis.swift"
CANCEL = CORE + "SpectroCancellation.swift"
EELS = "Sources/SpectroEELS/"
SDX = "Sources/SpectroEDX/Spectroscopy/"
LOWLOSS = EELS + "LowLossSpectrumImage.swift"
THICKNESS = EELS + "EELSThickness.swift"
THICKNESSMAP = EELS + "ThicknessMap.swift"
MFP = EELS + "MeanFreePath.swift"
EDGE = EELS + "EdgeQuantification.swift"
GOS = EELS + "GOSTable.swift"
LIBRARY_WITNESS = "must be declared public because it matches a requirement in public protocol"

ANSI = re.compile(r"\x1b\[[0-9;]*m")


def access(symbol, rel, old, owner, member, note=None, module="SpectroCore"):
    """A consumer-side control: the declaration `old` (its first `public`) becomes `package`."""
    return dict(kind="access", symbol=symbol, rel=rel, old=old, owner=owner, member=member, note=note or member,
                module=module)


def decl(symbol, rel, old, word):
    """A control on a whole type that the consumer names: the type becomes `package`. Caught by either diagnostic: the consumer is
    refused (`error: cannot find '<Type>' in scope`, also `cannot find type`, or `'<Type>' is inaccessible due to 'package' protection level`), or, when a
    public signature of the library itself mentions the type, the library no longer compiles (`... cannot be declared public
    because ... uses a package type`, the code frame under it naming the type)."""
    return dict(kind="decl", symbol=symbol, rel=rel, old=old, word=word)


def used(symbol, rel, old, pattern, file=None):
    """A control on a declaration whose refusal has no stable name in the diagnostic (an initialiser, a case-less label): the
    consumer's build must fail with an error, in one of the consumer's own source files (when `file` is given, in that file),
    matching `pattern`."""
    return dict(kind="used", symbol=symbol, rel=rel, old=old, pattern=pattern, file=file)


def library(symbol, rel, old, pattern, file):
    """A control the library itself refuses before any consumer compiles: the declaration is used by a public default argument
    (`carbonK`) or witnesses a public protocol requirement (`description`), so the edit cannot be made at all. Caught by an error
    in `file` (the edited library file) matching `pattern`."""
    return dict(kind="library", symbol=symbol, rel=rel, old=old, pattern=pattern, file=file)


def overload(symbol, rel, old, have, expected, word):
    """A control on one of two overloads: the compiler falls back on the other and objects to the labels."""
    return dict(kind="overload", symbol=symbol, rel=rel, old=old, have=have, expected=expected, word=word)


def struct(symbol, rel, old, word):
    """A type-level control: a public struct becomes `package`; the library's own public members then fail to compile."""
    return dict(kind="type", symbol=symbol, rel=rel, old=old, word=word)


# What a consumer reads across the package boundary: SpectroCore's spectrum-image opening (0.4.0: through FormatoKit, whose
# types are never named) and the whole SpectroEELS product. Each `old` occurs exactly once in its file (checked at run time).
CONTROLS = [
    # SpectroCore's spectrum-image opening (since 0.4.0 through FormatoKit)
    decl("SpectrumImageOpener", OPENER, "public nonisolated enum SpectrumImageOpener {", "SpectrumImageOpener"),
    access("SpectrumImageOpener.kind", OPENER, "public static func kind(ofFileAt path: String)", "SpectrumImageOpener", "kind",
           "kind(ofFileAt:)"),
    access("SpectrumImageOpener.open", OPENER, "public static func open(path: String, kind: SpectrumFileKind,", "SpectrumImageOpener", "open",
           "open(path:kind:cancelled:progress:)"),
    access("SpectrumImageOpener.openGMSEDS", OPENER, "public static func openGMSEDS(path: String,", "SpectrumImageOpener", "openGMSEDS",
           "openGMSEDS(path:cancelled:progress:)"),
    decl("SpectrumFileKind", OPENER, "public nonisolated enum SpectrumFileKind: Equatable, Sendable {", "SpectrumFileKind"),
    decl("SpectrumImageOpenError", OPENER, "public nonisolated enum SpectrumImageOpenError: LocalizedError, Equatable {", "SpectrumImageOpenError"),
    decl("SpectroCancelled", CANCEL, "public typealias SpectroCancelled = FormatoCancelled", "SpectroCancelled"),
    decl("LoadedSpectrumImage", SOURCE, "public nonisolated final class LoadedSpectrumImage: SpectrumImageSource {", "LoadedSpectrumImage"),
    library("LoadedSpectrumImage.ny", SOURCE, "public var ny: Int { image.ny }",
            LIBRARY_WITNESS, "SpectrumImageSource.swift"),
    library("LoadedSpectrumImage.nx", SOURCE, "public var nx: Int { image.nx }",
            LIBRARY_WITNESS, "SpectrumImageSource.swift"),
    library("LoadedSpectrumImage.channels", SOURCE, "public var channels: Int { image.channels }",
            LIBRARY_WITNESS, "SpectrumImageSource.swift"),
    library("LoadedSpectrumImage.metadata", SOURCE, "public let metadata: SpectrumImageMetadata\n    public let energyAxis",
            LIBRARY_WITNESS, "SpectrumImageSource.swift"),
    library("LoadedSpectrumImage.energyAxis", SOURCE, "public let energyAxis: EnergyAxis",
            LIBRARY_WITNESS, "SpectrumImageSource.swift"),
    library("LoadedSpectrumImage.scanImage", SOURCE, "public let scanImage: [Float]?",
            LIBRARY_WITNESS, "SpectrumImageSource.swift"),
    decl("SpectrumImageMetadata", SOURCE, "public nonisolated struct SpectrumImageMetadata: Equatable, Sendable {", "SpectrumImageMetadata"),
    access("SpectrumImageMetadata.scanWidth", SOURCE, "public var scanWidth: Int", "SpectrumImageMetadata", "scanWidth"),
    access("SpectrumImageMetadata.scanHeight", SOURCE, "public var scanHeight: Int", "SpectrumImageMetadata", "scanHeight"),
    access("SpectrumImageMetadata.channelCount", SOURCE, "public var channelCount: Int", "SpectrumImageMetadata", "channelCount"),
    access("SpectrumImageMetadata.scanPixelSize", SOURCE, "public var scanPixelSize: Double?", "SpectrumImageMetadata", "scanPixelSize"),
    access("SpectrumImageMetadata.scanPixelUnit", SOURCE, "public var scanPixelUnit: String?", "SpectrumImageMetadata", "scanPixelUnit"),
    access("SpectrumImageMetadata.origin", SOURCE, "public var origin: SpectrumImageOrigin?", "SpectrumImageMetadata", "origin"),
    access("SpectrumImageMetadata.frames", SOURCE, "public var frames: Int?", "SpectrumImageMetadata", "frames"),
    access("SpectrumImageMetadata.detectors", SOURCE, "public var detectors: [SpectrumDetectorSegment] = []", "SpectrumImageMetadata", "detectors"),
    access("SpectrumImageMetadata.beamEnergyKeV", SOURCE, "public var beamEnergyKeV: Double?", "SpectrumImageMetadata", "beamEnergyKeV"),
    decl("SpectrumImageOrigin", SOURCE, "public nonisolated enum SpectrumImageOrigin: String, Equatable, Sendable {", "SpectrumImageOrigin"),
    decl("SpectrumDetectorSegment", SOURCE, "public nonisolated struct SpectrumDetectorSegment: Equatable, Sendable {", "SpectrumDetectorSegment"),
    access("SpectrumDetectorSegment.name", SOURCE, "public var name: String", "SpectrumDetectorSegment", "name"),
    access("SpectrumDetectorSegment.solidAngle", SOURCE, "public var solidAngle: Double?", "SpectrumDetectorSegment", "solidAngle"),
    decl("EnergyAxis", AXIS, "public nonisolated struct EnergyAxis: Equatable, Sendable {", "EnergyAxis"),
    access("EnergyAxis.offset", AXIS, "public let offset: Double", "EnergyAxis", "offset"),
    access("EnergyAxis.scale", AXIS, "public let scale: Double", "EnergyAxis", "scale"),
    access("EnergyAxis.size", AXIS, "public let size: Int", "EnergyAxis", "size"),
    access("EnergyAxis.energy(ofChannel:)", AXIS, "public func energy(ofChannel i: Int)", "EnergyAxis", "energy", "energy(ofChannel:)"),
    # SpectroEELS (EELS slice 1): the thickness map
    decl("EELSThickness", THICKNESS, "public nonisolated enum EELSThickness {", "EELSThickness"),
    access("EELSThickness.methodName", THICKNESS, "public static let methodName", "EELSThickness", "methodName", module="SpectroEELS"),
    access("EELSThickness.logRatio", THICKNESS, "public static func logRatio(", "EELSThickness", "logRatio",
           "logRatio(_:threshold:zeroLoss:meanFreePath:cancelled:progress:)", module="SpectroEELS"),
    decl("LowLossSpectrumImage", LOWLOSS, "public nonisolated struct LowLossSpectrumImage: Sendable {", "LowLossSpectrumImage"),
    access("LowLossSpectrumImage.nx", LOWLOSS, "public let nx: Int", "LowLossSpectrumImage", "nx", module="SpectroEELS"),
    access("LowLossSpectrumImage.ny", LOWLOSS, "public let ny: Int", "LowLossSpectrumImage", "ny", module="SpectroEELS"),
    access("LowLossSpectrumImage.channels", LOWLOSS, "public let channels: Int", "LowLossSpectrumImage", "channels", module="SpectroEELS"),
    access("LowLossSpectrumImage.counts", LOWLOSS, "public let counts: [Double]", "LowLossSpectrumImage", "counts", module="SpectroEELS"),
    access("LowLossSpectrumImage.energyOffsetEV", LOWLOSS, "public let energyOffsetEV: Double", "LowLossSpectrumImage",
           "energyOffsetEV", module="SpectroEELS"),
    access("LowLossSpectrumImage.energyScaleEV", LOWLOSS, "public let energyScaleEV: Double", "LowLossSpectrumImage",
           "energyScaleEV", module="SpectroEELS"),
    used("LowLossSpectrumImage.init(counts: [Double])", LOWLOSS,
         "public init(nx: Int, ny: Int, channels: Int, counts: [Double], energyOffsetEV", r"\[Double\]|init\("),
    used("LowLossSpectrumImage.init(counts: [Float])", LOWLOSS,
         "public init(nx: Int, ny: Int, channels: Int, counts: [Float], energyOffsetEV", r"Float"),
    access("LowLossSpectrumImage.pixelCount", LOWLOSS, "public var pixelCount: Int", "LowLossSpectrumImage", "pixelCount", module="SpectroEELS"),
    access("LowLossSpectrumImage.energy(ofChannel:)", LOWLOSS, "public func energy(ofChannel c: Int)", "LowLossSpectrumImage", "energy",
           "energy(ofChannel:)", module="SpectroEELS"),
    decl("ThresholdRule", EELS + "ThresholdRule.swift", "public nonisolated enum ThresholdRule: Sendable, Equatable {", "ThresholdRule"),
    decl("MeanFreePathSource", MFP, "public nonisolated enum MeanFreePathSource: Sendable, Equatable {", "MeanFreePathSource"),
    decl("InelasticMeanFreePath", MFP, "public nonisolated enum InelasticMeanFreePath {", "InelasticMeanFreePath"),
    access("InelasticMeanFreePath.iakoubovskii", MFP, "public static func iakoubovskii(density: Double, beamEnergyKeV e0: Double)",
           "InelasticMeanFreePath", "iakoubovskii", "iakoubovskii(density:beamEnergyKeV:)", module="SpectroEELS"),
    access("InelasticMeanFreePath.angularCorrection", MFP, "public static func angularCorrection(density: Double",
           "InelasticMeanFreePath", "angularCorrection", "angularCorrection(density:beamEnergyKeV:convergenceMrad:collectionMrad:)",
           module="SpectroEELS"),
    decl("ThicknessUnavailable", THICKNESSMAP, "public nonisolated enum ThicknessUnavailable: String,", "ThicknessUnavailable"),
    decl("SigmaUnavailable", THICKNESSMAP, "public nonisolated enum SigmaUnavailable: String,", "SigmaUnavailable"),
    decl("ThicknessPixel", THICKNESSMAP, "public nonisolated struct ThicknessPixel: Sendable, Equatable {", "ThicknessPixel"),
    access("ThicknessPixel.tOverLambda", THICKNESSMAP, "public let tOverLambda: Double?", "ThicknessPixel", "tOverLambda", module="SpectroEELS"),
    access("ThicknessPixel.sigmaCounting", THICKNESSMAP, "public let sigmaCounting: Double?", "ThicknessPixel", "sigmaCounting", module="SpectroEELS"),
    access("ThicknessPixel.i0", THICKNESSMAP, "public let i0: Double?", "ThicknessPixel", "i0", module="SpectroEELS"),
    access("ThicknessPixel.iTotal", THICKNESSMAP, "public let iTotal: Double", "ThicknessPixel", "iTotal", module="SpectroEELS"),
    access("ThicknessPixel.thresholdEV", THICKNESSMAP, "public let thresholdEV: Double?", "ThicknessPixel", "thresholdEV", module="SpectroEELS"),
    access("ThicknessPixel.thresholdChannel", THICKNESSMAP, "public let thresholdChannel: Int?", "ThicknessPixel", "thresholdChannel",
           module="SpectroEELS"),
    access("ThicknessPixel.zlpCentreEV", THICKNESSMAP, "public let zlpCentreEV: Double", "ThicknessPixel", "zlpCentreEV", module="SpectroEELS"),
    access("ThicknessPixel.thicknessNM", THICKNESSMAP, "public let thicknessNM: Double?", "ThicknessPixel", "thicknessNM", module="SpectroEELS"),
    access("ThicknessPixel.unavailable", THICKNESSMAP, "public let unavailable: ThicknessUnavailable?", "ThicknessPixel", "unavailable",
           module="SpectroEELS"),
    access("ThicknessPixel.sigmaUnavailable", THICKNESSMAP, "public let sigmaUnavailable: SigmaUnavailable?", "ThicknessPixel",
           "sigmaUnavailable", module="SpectroEELS"),
    decl("ZeroLossSource", THICKNESSMAP, "public nonisolated enum ZeroLossSource: Sendable, Equatable {", "ZeroLossSource"),
    decl("ThicknessMap", THICKNESSMAP, "public nonisolated struct ThicknessMap: Sendable {", "ThicknessMap"),
    access("ThicknessMap.nx", THICKNESSMAP, "public let nx: Int", "ThicknessMap", "nx", module="SpectroEELS"),
    access("ThicknessMap.ny", THICKNESSMAP, "public let ny: Int", "ThicknessMap", "ny", module="SpectroEELS"),
    access("ThicknessMap.pixels", THICKNESSMAP, "public let pixels: [ThicknessPixel]", "ThicknessMap", "pixels", module="SpectroEELS"),
    access("ThicknessMap.method", THICKNESSMAP, "public let method: String", "ThicknessMap", "method", module="SpectroEELS"),
    access("ThicknessMap.zeroLoss", THICKNESSMAP, "public let zeroLoss: ZeroLossSource", "ThicknessMap", "zeroLoss", module="SpectroEELS"),
    access("ThicknessMap.meanFreePath", THICKNESSMAP, "public let meanFreePath: MeanFreePathSource?", "ThicknessMap", "meanFreePath",
           module="SpectroEELS"),
    access("ThicknessMap.meanFreePathNM", THICKNESSMAP, "public let meanFreePathNM: Double?", "ThicknessMap", "meanFreePathNM",
           module="SpectroEELS"),
    access("ThicknessMap.angularCorrection", THICKNESSMAP, "public let angularCorrection: Double?", "ThicknessMap", "angularCorrection",
           module="SpectroEELS"),
    access("ThicknessMap.estimatedTolerance", THICKNESSMAP, "public let estimatedTolerance: Double?", "ThicknessMap", "estimatedTolerance",
           module="SpectroEELS"),
    access("ThicknessMap.validation", THICKNESSMAP, "public let validation: String", "ThicknessMap", "validation", module="SpectroEELS"),
    access("ThicknessMap.subscript", THICKNESSMAP, "public subscript(x: Int, y: Int)", "ThicknessMap", "subscript", "subscript(_:_:)",
           module="SpectroEELS"),
    decl("EELSThicknessError", EELS + "EELSThicknessError.swift",
         "public nonisolated enum EELSThicknessError: Error, Equatable, Sendable {", "EELSThicknessError"),
    # SpectroEELS (EELS slice 2): the areal density by the ratio method
    decl('EELSEdgeQuantification', EDGE, 'public nonisolated enum EELSEdgeQuantification {', 'EELSEdgeQuantification'),
    access('EELSEdgeQuantification.methodName', EDGE, 'public static let methodName =', 'EELSEdgeQuantification', 'methodName', module="SpectroEELS"),
    access('EELSEdgeQuantification.defaultBackgroundWindow', EDGE, 'public static func defaultBackgroundWindow(onsetEV: Double,', 'EELSEdgeQuantification', 'defaultBackgroundWindow', 'defaultBackgroundWindow(onsetEV:belowOnsetEV:gapEV:)', module="SpectroEELS"),
    access('EELSEdgeQuantification.differentialCrossSection', EDGE, 'public static func differentialCrossSection(edge: CoreLossEdge', 'EELSEdgeQuantification', 'differentialCrossSection', 'differentialCrossSection(edge:microscope:energiesEV:)', module="SpectroEELS"),
    access('EELSEdgeQuantification.ratioMethod', EDGE, 'public static func ratioMethod(', 'EELSEdgeQuantification', 'ratioMethod', 'ratioMethod(coreLoss:edge:microscope:lowLoss:backgroundWindowEV:edgeOnsetEV:integrationWidthEV:coreLossToLowLossDose:cancelled:)', module="SpectroEELS"),
    decl('CoreLossSpectrumImage', EDGE, 'public nonisolated struct CoreLossSpectrumImage: Sendable {', 'CoreLossSpectrumImage'),
    access('CoreLossSpectrumImage.nx', EDGE, 'public let nx: Int\n    public let ny: Int\n    public let channels: Int\n    public let counts: [Double]', 'CoreLossSpectrumImage', 'nx', module="SpectroEELS"),
    access('CoreLossSpectrumImage.ny', EDGE, 'public let ny: Int\n    public let channels: Int', 'CoreLossSpectrumImage', 'ny', module="SpectroEELS"),
    access('CoreLossSpectrumImage.channels', EDGE, 'public let channels: Int\n    public let counts: [Double]', 'CoreLossSpectrumImage', 'channels', module="SpectroEELS"),
    access('CoreLossSpectrumImage.counts', EDGE, 'public let counts: [Double]\n    public let energyOffsetEV', 'CoreLossSpectrumImage', 'counts', module="SpectroEELS"),
    access('CoreLossSpectrumImage.energyOffsetEV', EDGE, 'public let energyOffsetEV: Double\n    public let energyScaleEV', 'CoreLossSpectrumImage', 'energyOffsetEV', module="SpectroEELS"),
    access('CoreLossSpectrumImage.energyScaleEV', EDGE, 'public let energyScaleEV: Double\n\n    public init', 'CoreLossSpectrumImage', 'energyScaleEV', module="SpectroEELS"),
    access('CoreLossSpectrumImage.pixelCount', EDGE, 'public var pixelCount: Int', 'CoreLossSpectrumImage', 'pixelCount', module="SpectroEELS"),
    used("CoreLossSpectrumImage.init(counts: [Double])", EDGE,
         "public init(nx: Int, ny: Int, channels: Int, counts: [Double], energyOffsetEV", r"\[Double\]|init\(", "EdgeQuantificationChecks.swift"),
    used("CoreLossSpectrumImage.init(counts: [Float])", EDGE,
         "public init(nx: Int, ny: Int, channels: Int, counts: [Float], energyOffsetEV", r"Float", "EdgeQuantificationChecks.swift"),
    decl('EELSMicroscope', EDGE, 'public nonisolated struct EELSMicroscope: Sendable, Equatable {', 'EELSMicroscope'),
    access('EELSMicroscope.beamEnergyKeV', EDGE, 'public let beamEnergyKeV: Double', 'EELSMicroscope', 'beamEnergyKeV', module="SpectroEELS"),
    access('EELSMicroscope.convergenceMrad', EDGE, 'public let convergenceMrad: Double', 'EELSMicroscope', 'convergenceMrad', module="SpectroEELS"),
    access('EELSMicroscope.collectionMrad', EDGE, 'public let collectionMrad: Double', 'EELSMicroscope', 'collectionMrad', module="SpectroEELS"),
    used("EELSMicroscope.init", EDGE, "public init(beamEnergyKeV: Double, convergenceMrad: Double, collectionMrad: Double)",
         r"inaccessible|cannot be constructed|no exact matches", "EdgeQuantificationChecks.swift"),
    decl('LowLossIntensity', EDGE, 'public nonisolated enum LowLossIntensity: Sendable {', 'LowLossIntensity'),
    decl('EdgeUnavailable', EDGE, 'public nonisolated enum EdgeUnavailable: String,', 'EdgeUnavailable'),
    decl('ArealDensityPixel', EDGE, 'public nonisolated struct ArealDensityPixel: Sendable, Equatable {', 'ArealDensityPixel'),
    access('ArealDensityPixel.atomsPerNM2', EDGE, 'public let atomsPerNM2: Double?', 'ArealDensityPixel', 'atomsPerNM2', module="SpectroEELS"),
    access('ArealDensityPixel.sigmaCounting', EDGE, 'public let sigmaCounting: Double?', 'ArealDensityPixel', 'sigmaCounting', module="SpectroEELS"),
    access('ArealDensityPixel.edgeCounts', EDGE, 'public let edgeCounts: Double?', 'ArealDensityPixel', 'edgeCounts', module="SpectroEELS"),
    access('ArealDensityPixel.backgroundCounts', EDGE, 'public let backgroundCounts: Double?', 'ArealDensityPixel', 'backgroundCounts', module="SpectroEELS"),
    access('ArealDensityPixel.powerLawR', EDGE, 'public let powerLawR: Double?', 'ArealDensityPixel', 'powerLawR', module="SpectroEELS"),
    access('ArealDensityPixel.powerLawA', EDGE, 'public let powerLawA: Double?', 'ArealDensityPixel', 'powerLawA', module="SpectroEELS"),
    access('ArealDensityPixel.lowLossIntensity', EDGE, 'public let lowLossIntensity: Double?', 'ArealDensityPixel', 'lowLossIntensity', module="SpectroEELS"),
    access('ArealDensityPixel.unavailable', EDGE, 'public let unavailable: EdgeUnavailable?', 'ArealDensityPixel', 'unavailable', module="SpectroEELS"),
    decl('ArealDensityMap', EDGE, 'public nonisolated struct ArealDensityMap: Sendable {', 'ArealDensityMap'),
    access('ArealDensityMap.nx', EDGE, 'public let nx: Int\n    public let ny: Int\n    public let pixels: [ArealDensityPixel]', 'ArealDensityMap', 'nx', module="SpectroEELS"),
    access('ArealDensityMap.ny', EDGE, 'public let ny: Int\n    public let pixels: [ArealDensityPixel]', 'ArealDensityMap', 'ny', module="SpectroEELS"),
    access('ArealDensityMap.pixels', EDGE, 'public let pixels: [ArealDensityPixel]', 'ArealDensityMap', 'pixels', module="SpectroEELS"),
    access('ArealDensityMap.edge', EDGE, 'public let edge: CoreLossEdge', 'ArealDensityMap', 'edge', module="SpectroEELS"),
    access('ArealDensityMap.microscope', EDGE, 'public let microscope: EELSMicroscope', 'ArealDensityMap', 'microscope', module="SpectroEELS"),
    access('ArealDensityMap.effectiveCollectionMrad', EDGE, 'public let effectiveCollectionMrad: Double', 'ArealDensityMap', 'effectiveCollectionMrad', module="SpectroEELS"),
    access('ArealDensityMap.crossSectionBarn', EDGE, 'public let crossSectionBarn: Double', 'ArealDensityMap', 'crossSectionBarn', module="SpectroEELS"),
    access('ArealDensityMap.backgroundWindowEV', EDGE, 'public let backgroundWindowEV: ClosedRange<Double>', 'ArealDensityMap', 'backgroundWindowEV', module="SpectroEELS"),
    access('ArealDensityMap.edgeWindowEV', EDGE, 'public let edgeWindowEV: Range<Double>', 'ArealDensityMap', 'edgeWindowEV', module="SpectroEELS"),
    access('ArealDensityMap.edgeChannels', EDGE, 'public let edgeChannels: Range<Int>', 'ArealDensityMap', 'edgeChannels', module="SpectroEELS"),
    access('ArealDensityMap.lowLossRoute', EDGE, 'public let lowLossRoute: String', 'ArealDensityMap', 'lowLossRoute', module="SpectroEELS"),
    access('ArealDensityMap.coreLossToLowLossDose', EDGE, 'public let coreLossToLowLossDose: Double', 'ArealDensityMap', 'coreLossToLowLossDose', module="SpectroEELS"),
    access('ArealDensityMap.method', EDGE, 'public let method: String', 'ArealDensityMap', 'method', module="SpectroEELS"),
    access('ArealDensityMap.validation', EDGE, 'public let validation: String', 'ArealDensityMap', 'validation', module="SpectroEELS"),
    access('ArealDensityMap.caveat', EDGE, 'public let caveat: String?', 'ArealDensityMap', 'caveat', module="SpectroEELS"),
    decl('EELSEdgeError', EDGE, 'public nonisolated enum EELSEdgeError: Error, Equatable, Sendable {', 'EELSEdgeError'),
    decl('CoreLossEdge', GOS, 'public nonisolated struct CoreLossEdge: Sendable, Equatable, CustomStringConvertible {', 'CoreLossEdge'),
    access('CoreLossEdge.element', GOS, 'public let element: String', 'CoreLossEdge', 'element', module="SpectroEELS"),
    access('CoreLossEdge.subshell', GOS, 'public let subshell: String', 'CoreLossEdge', 'subshell', module="SpectroEELS"),
    access('CoreLossEdge.onsetEV', GOS, 'public let onsetEV: Double', 'CoreLossEdge', 'onsetEV', module="SpectroEELS"),
    library("CoreLossEdge.carbonK", GOS, "public static let carbonK",
            "static property 'carbonK' is package and cannot be referenced from a default argument value", "EdgeQuantification.swift"),
    access('CoreLossEdge.nitrogenK', GOS, 'public static let nitrogenK', 'CoreLossEdge', 'nitrogenK', module="SpectroEELS"),
    access('CoreLossEdge.oxygenK', GOS, 'public static let oxygenK', 'CoreLossEdge', 'oxygenK', module="SpectroEELS"),
    access('CoreLossEdge.bundled', GOS, 'public static let bundled', 'CoreLossEdge', 'bundled', module="SpectroEELS"),
    library("CoreLossEdge.description", GOS, "public var description: String",
            "property 'description' must be declared public because it matches a requirement in public protocol 'CustomStringConvertible'", "GOSTable.swift"),
    # SpectroEDX policies and SpectroCore kernels (0.5.0): the types the new parameters are passed in
    decl("WindowRules", SDX + "WindowRules.swift", "public nonisolated struct WindowRules: Sendable, Equatable, Codable {", "WindowRules"),
    decl("FitPolicy", SDX + "Quant/QuantificationPolicy.swift", "public nonisolated struct FitPolicy: Sendable, Equatable, Codable {", "FitPolicy"),
    decl("AbundancePolicy", SDX + "Quant/QuantificationPolicy.swift", "public nonisolated struct AbundancePolicy: Sendable, Equatable, Codable {", "AbundancePolicy"),
    decl("QuantificationPolicy", SDX + "Quant/QuantificationPolicy.swift", "public nonisolated struct QuantificationPolicy: Sendable, Equatable, Codable {", "QuantificationPolicy"),
    decl("DetectorLayers", SDX + "Quant/QuantificationPolicy.swift", "public nonisolated struct DetectorLayers: Sendable, Equatable, Codable {", "DetectorLayers"),
    decl("SingleLineRule", SDX + "Quant/QuantificationPolicy.swift", "public nonisolated enum SingleLineRule: String, Sendable, Codable {", "SingleLineRule"),
    decl("ProposerPolicy", SDX + "Method/ProposerPolicy.swift", "public nonisolated struct ProposerPolicy: Sendable, Equatable {", "ProposerPolicy"),
    decl("FlankMisfitGeometry", SDX + "Method/ProposerPolicy.swift", "public nonisolated struct FlankMisfitGeometry: Sendable, Equatable, Codable {", "FlankMisfitGeometry"),
    decl("ElementContext", SDX + "Method/ProposerPolicy.swift", "public nonisolated struct ElementContext: Sendable, Equatable, Codable {", "ElementContext"),
    decl("UnlistedLineRules", SDX + "Method/ProposerPolicy.swift", "public nonisolated struct UnlistedLineRules: Sendable, Equatable, Codable {", "UnlistedLineRules"),
    decl("AxisRefinementSettings", SDX + "Fit/EnergyAxisRefinement.swift", "public nonisolated struct AxisRefinementSettings: Sendable, Equatable, Codable {", "AxisRefinementSettings"),
    decl("IRLSSettings", CORE + "Fit/PoissonMLFit.swift", "public nonisolated struct IRLSSettings: Sendable, Equatable, Codable {", "IRLSSettings"),
    decl("SmoothingKernel", CORE + "MapSmoothing.swift", "public nonisolated enum SmoothingKernel: Sendable, Equatable, Codable {", "SmoothingKernel"),
    access("PooledQuantificationInput.policy", SDX + "Quant/PooledQuantification.swift", "public var policy: QuantificationPolicy", "PooledQuantificationInput", "policy", module="SpectroEDX"),
    access("MapSmoothing.smoothingKernel", CORE + "MapSmoothing.swift", "public var smoothingKernel: SmoothingKernel?", "MapSmoothing", "smoothingKernel"),
]


def sha256(path):
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def build(log_name):
    """swift build -c debug of the consumer in the copy: (exit status, the output with colour codes removed)."""
    result = subprocess.run(["swift", "build", "-c", "debug"], cwd=CONSUMER, capture_output=True, text=True, timeout=900)
    text = ANSI.sub("", result.stdout + result.stderr)
    with open(os.path.join(LOGS, log_name + ".log"), "w", encoding="utf-8") as f:
        f.write(text)
    return result.returncode, text


def short(line):
    """A diagnostic line without the long path before the file name."""
    return re.sub(r"^\S*/([^/\s]+\.swift)", r"\1", line.strip())


def judge(control, status, text):
    """(caught, the evidence line, why not)."""
    if status == 0:
        return False, None, "the build SUCCEEDED with the declaration reverted to package"
    if control["kind"] == "access":
        member, owner, note = control["member"], control["owner"], control["note"]
        error = re.search(
            rf"^(\S+\.swift:\d+:\d+): error: '{re.escape(member)}' is inaccessible due to 'package' protection level$",
            text, re.M)
        declared = re.search(
            rf"^{re.escape(control['module'])}\.{re.escape(owner)}\.{re.escape(member)}\S*: note: '{re.escape(note)}' declared here$",
            text, re.M)
        if not error:
            return False, None, f"no `error: '{member}' is inaccessible due to 'package' protection level` line"
        if not declared:
            return False, None, f"no note `{control['module']}.{owner}.{member}...: note: '{note}' declared here` (a different declaration?)"
        return True, short(error.group(0)), None
    if control["kind"] == "overload":
        for m in re.finditer(
                rf"^(\S+\.swift):(\d+):\d+: error: incorrect argument label in call "
                rf"\(have '{re.escape(control['have'])}', expected '{re.escape(control['expected'])}'\)$", text, re.M):
            path, number = m.group(1), int(m.group(2))
            try:
                with open(path, encoding="utf-8") as f:
                    source = f.read().splitlines()[number - 1]
            except (OSError, IndexError):
                continue
            if control["word"] in source:
                return True, f"{short(m.group(0))}   [{os.path.basename(path)}:{number}: {source.strip()[:90]}]", None
        return False, None, (f"no `incorrect argument label in call (have '{control['have']}', expected "
                             f"'{control['expected']}')` error at a call of {control['word']}")
    if control["kind"] == "decl":
        word = control["word"]
        refused = re.search(rf"^(\S+\.swift:\d+:\d+): error: ('{re.escape(word)}' is inaccessible due to 'package' protection level"
                            rf"|cannot find (?:type )?'{re.escape(word)}' in scope)$", text, re.M)
        if refused:
            return True, short(refused.group(0)), None
        # else the library's own public signature mentions the type: the code frame under the error names it
        lines = text.splitlines()
        for i, line in enumerate(lines):
            if "uses a package type" in line and "cannot be declared public because" in line:
                frame = "\n".join(lines[max(0, i - 6):i + 8])
                if re.search(rf"\b{re.escape(word)}\b", frame):
                    return True, f"library: {line.strip()[:120]}  [frame names {word}]", None
        return False, None, f"neither the consumer refused `{word}` nor a public signature of the library naming it fails"
    if control["kind"] == "library":
        for m in re.finditer(r"^(\S+\.swift):\d+:\d+: error: (.*)$", text, re.M):
            if m.group(1).endswith("/" + control["file"]) and re.search(control["pattern"], m.group(2)):
                return True, f"library: {short(m.group(0))[:160]}", None
        return False, None, f"no library error in {control['file']} matching /{control['pattern']}/"
    if control["kind"] == "used":
        for m in re.finditer(r"^(\S+/tools/consumer-check/Sources/\S+\.swift:\d+:\d+): error: (.*)$", text, re.M):
            if control.get("file") and not m.group(1).split(":")[0].endswith("/" + control["file"]):
                continue
            if re.search(control["pattern"], m.group(2)):
                return True, short(m.group(0))[:200], None
        return False, None, f"no error in the consumer's sources matching /{control['pattern']}/"
    # kind == "type"
    for m in re.finditer(r"^(\S+\.swift):(\d+):\d+: error: .*cannot be declared public because .*uses a package type$",
                         text, re.M):
        path, number = m.group(1), int(m.group(2))
        try:
            with open(path, encoding="utf-8") as f:
                source = f.read().splitlines()[number - 1]
        except (OSError, IndexError):
            continue
        if control["word"] in source:
            return True, f"{short(m.group(0))}   [{os.path.basename(path)}:{number}: {source.strip()}]", None
    return False, None, f"no `cannot be declared public because ... uses a package type` error at a line naming {control['word']}"


def main():
    selected = [c for c in CONTROLS if not ONLY or c["symbol"] in ONLY]
    unknown = [s for s in ONLY if s not in {c["symbol"] for c in CONTROLS}]
    if unknown:
        print("consumer-check: unknown control(s): " + ", ".join(unknown), file=sys.stderr)
        return 2
    started = time.time()

    # The repository's own files are never written; their hashes are compared at the end.
    originals = {rel: sha256(os.path.join(ROOT, rel)) for rel in sorted({c["rel"] for c in CONTROLS})}

    # A fresh copy: a directory under <root>/.build only, then the sources without .build, .git and References.
    assert MUTANTS.startswith(os.path.join(ROOT, ".build") + os.sep) and NAME, MUTANTS
    shutil.rmtree(MUTANTS, ignore_errors=True)
    os.makedirs(COPY)
    os.makedirs(LOGS)
    subprocess.run(["rsync", "-a", "--exclude", ".build", "--exclude", ".git", "--exclude", "References",
                    ROOT + "/", COPY + "/"], check=True)

    status, text = build("baseline")
    if status != 0:
        print("consumer-check: the UNEDITED copy does not build, so no control means anything:", file=sys.stderr)
        print("\n".join(text.splitlines()[-25:]), file=sys.stderr)
        return 2
    print(f"consumer-check: controls build in {COPY} (baseline: the unedited copy builds)")

    caught = 0
    for number, control in enumerate(selected, 1):
        symbol, rel = control["symbol"], control["rel"]
        path = os.path.join(COPY, rel)
        with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
            pristine = f.read()
        if pristine.count(control["old"]) != 1:
            print(f"  FAIL  {symbol}: the edit target occurs {pristine.count(control['old'])} times in {rel}, not once"
                  f" (re-aim it): {control['old']!r}")
            continue
        edited = pristine.replace(control["old"], control["old"].replace("public", "package", 1))
        with open(path, "w", encoding="utf-8") as f:
            f.write(edited)
        try:
            status, text = build(f"{number:02d}-{re.sub(r'[^A-Za-z0-9]+', '-', symbol)}")
        finally:
            with open(path, "w", encoding="utf-8") as f:
                f.write(pristine)
        ok, evidence, why = judge(control, status, text)
        if ok:
            caught += 1
            print(f"  ok    {symbol}: {evidence}")
        else:
            print(f"  FAIL  {symbol}: {why} (build exit {status}; log {LOGS})")

    # The copy is restored and the repository untouched.
    for rel, digest in originals.items():
        if sha256(os.path.join(ROOT, rel)) != digest:
            print(f"  FAIL  the repository's {rel} changed during the controls")
            return 1
        if sha256(os.path.join(COPY, rel)) != digest:
            print(f"  FAIL  the copy's {rel} was not restored")
            return 1
    total = len(selected)
    print(f"consumer-check: negative controls: {caught} of {total} caught ({time.time() - started:.0f} s; "
          f"the repository's sources untouched, the copy restored)")
    return 0 if caught == total else 1


if __name__ == "__main__":
    sys.exit(main())
