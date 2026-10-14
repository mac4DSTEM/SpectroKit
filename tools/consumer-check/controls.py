#!/usr/bin/env python3
"""consumer-check negative controls (run through `run.sh --controls`; Python 3 standard library only).

The consumer package (tools/consumer-check) compiles only while every symbol SpectroKit 0.2.0 made public is public.
This proves it: for each such symbol, ONE declaration is reverted from `public` to `package` in a COPY of the repository
(rsync into <root>/.build/consumer-check/mutants/<name>, never the working tree), the consumer is built against the
copy (its Package.swift takes the dependency by path), and the build must FAIL with a compiler error that names that
symbol. A control is caught only when
  * the unedited copy builds (the baseline, so a failure is the edit's), and
  * the edit applied exactly once, and
  * the build exits non-zero, and the compiler's diagnostic is the expected one:
      "access": the consumer is refused, `error: '<member>' is inaccessible due to 'package' protection level`, and
                the note beside it points at the edited declaration (`SpectroCore.<Owner>.<member>: note: ... declared here`),
                so two declarations with one name (VeloxMetadata and VeloxDetectorInfo `exposureTimeSeconds`) are told apart;
      "overload": the reverted declaration is one of two overloads (readImage(path:index:) / readImage(data:index:)), so
                the compiler resolves the call to the public sibling and says so, naming the reverted labels:
                `error: incorrect argument label in call (have 'path:index:', expected 'data:index:')`, at a call of readImage;
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
DATA = "Sources/SpectroCore/Data/"
DM4 = DATA + "DM4Experiment.swift"
VELOX = DATA + "VeloxEMDReader.swift"
HDF5 = DATA + "HDF5Types.swift"
EELS = "Sources/SpectroEELS/"
LOWLOSS = EELS + "LowLossSpectrumImage.swift"
THICKNESS = EELS + "EELSThickness.swift"
THICKNESSMAP = EELS + "ThicknessMap.swift"
MFP = EELS + "MeanFreePath.swift"

ANSI = re.compile(r"\x1b\[[0-9;]*m")


def access(symbol, rel, old, owner, member, note=None, module="SpectroCore"):
    """A consumer-side control: the declaration `old` (its first `public`) becomes `package`."""
    return dict(kind="access", symbol=symbol, rel=rel, old=old, owner=owner, member=member, note=note or member,
                module=module)


def decl(symbol, rel, old, word):
    """A control on a whole type that the consumer names: the type becomes `package`. Caught by either diagnostic: the consumer is
    refused (`error: cannot find '<Type>' in scope` or `'<Type>' is inaccessible due to 'package' protection level`), or, when a
    public signature of the library itself mentions the type, the library no longer compiles (`... cannot be declared public
    because ... uses a package type`, the code frame under it naming the type)."""
    return dict(kind="decl", symbol=symbol, rel=rel, old=old, word=word)


def used(symbol, rel, old, pattern):
    """A control on a declaration whose refusal has no stable name in the diagnostic (an initialiser, a case-less label): the
    consumer's build must fail with an error, in one of the consumer's own source files, matching `pattern`."""
    return dict(kind="used", symbol=symbol, rel=rel, old=old, pattern=pattern)


def overload(symbol, rel, old, have, expected, word):
    """A control on one of two overloads: the compiler falls back on the other and objects to the labels."""
    return dict(kind="overload", symbol=symbol, rel=rel, old=old, have=have, expected=expected, word=word)


def struct(symbol, rel, old, word):
    """A type-level control: a public struct becomes `package`; the library's own public members then fail to compile."""
    return dict(kind="type", symbol=symbol, rel=rel, old=old, word=word)


# Everything SpectroKit 0.2.0 made public (git diff 0.1.0..): the DM4 API macTEM reads, the six VeloxMetadata fields and
# VeloxDetectorInfo's, and the barrier's bound. Each `old` occurs exactly once in its file (checked at run time).
CONTROLS = [
    # DM4Experiment (macTEM's ask 1)
    overload("DM4Experiment.readImage(path:index:)", DM4, "public static func readImage(path: String, index: Int)",
             "path:index:", "data:index:", "readImage"),
    access("DM4Experiment.tagTree", DM4, "public static func tagTree(data: Data)", "DM4Experiment", "tagTree",
           "tagTree(data:)"),
    overload("DM4Experiment.readImage(data:index:)", DM4, "public static func readImage(data: Data, index: Int)",
             "data:index:", "path:index:", "readImage"),
    struct("DM4Image", DM4, "public nonisolated struct DM4Image: Sendable, Equatable {", "DM4Image"),
    access("DM4Image.object", DM4, "public let object: DM4ImageObject\n    public let width: Int", "DM4Image", "object"),
    access("DM4Image.width", DM4, "public let width: Int\n    public let height: Int", "DM4Image", "width"),
    access("DM4Image.height", DM4, "public let height: Int", "DM4Image", "height"),
    access("DM4Image.pixels", DM4, "public let pixels: [Float]", "DM4Image", "pixels"),
    access("DM4Image.xAxis", DM4, "public let xAxis: DM4Axis?", "DM4Image", "xAxis"),
    access("DM4Image.yAxis", DM4, "public let yAxis: DM4Axis?", "DM4Image", "yAxis"),
    struct("DM4Axis", DM4, "public nonisolated struct DM4Axis: Sendable, Equatable {", "DM4Axis"),
    access("DM4Axis.origin", DM4, "public let origin: Double", "DM4Axis", "origin"),
    access("DM4Axis.scale", DM4, "public let scale: Double", "DM4Axis", "scale"),
    access("DM4Axis.units", DM4, "public let units: String", "DM4Axis", "units"),
    access("DM4ImageObject.name", DM4, "public let name: String", "DM4ImageObject", "name"),
    access("DM4ImageObject.dimensions", DM4, "public let dimensions: [Int]", "DM4ImageObject", "dimensions"),
    access("DM4ImageObject.axes", DM4, "public let axes: [DM4Axis?]", "DM4ImageObject", "axes"),
    access("DM4ImageObject.metaDataFormat", DM4, "public let metaDataFormat: String?", "DM4ImageObject",
           "metaDataFormat"),
    access("DM4ImageObject.imageTagNumbers", DM4, "public let imageTagNumbers: [String: Double]", "DM4ImageObject",
           "imageTagNumbers"),
    access("DM4ImageObject.imageTagStrings", DM4, "public let imageTagStrings: [String: String]", "DM4ImageObject",
           "imageTagStrings"),
    # VeloxMetadata and VeloxDetectorInfo (macTEM's ask 2 and the owner's StemMagnification)
    access("VeloxMetadata.nominalMagnification", VELOX, "public let nominalMagnification: Double?", "VeloxMetadata",
           "nominalMagnification"),
    access("VeloxMetadata.stemMagnification", VELOX, "public let stemMagnification: Double?", "VeloxMetadata",
           "stemMagnification"),
    access("VeloxMetadata.cameraLengthMeters", VELOX, "public let cameraLengthMeters: Double?", "VeloxMetadata",
           "cameraLengthMeters"),
    access("VeloxMetadata.operatingMode", VELOX, "public let operatingMode: String?", "VeloxMetadata", "operatingMode"),
    access("VeloxMetadata.projectorMode", VELOX, "public let projectorMode: String?", "VeloxMetadata", "projectorMode"),
    access("VeloxMetadata.exposureTimeSeconds", VELOX,
           "public let exposureTimeSeconds: Double?\n\n    public var superXDetectors", "VeloxMetadata",
           "exposureTimeSeconds"),
    access("VeloxDetectorInfo.exposureTimeSeconds", VELOX,
           "public let exposureTimeSeconds: Double?\n\n    public var azimuthDegrees", "VeloxDetectorInfo",
           "exposureTimeSeconds"),
    # EELS slice 1b: the DM4 EELS spectrum-image reader
    overload("DM4Experiment.readEELSSpectrumImage(path:index:)", DM4,
             "public static func readEELSSpectrumImage(path: String, index: Int)", "path:index:", "data:index:",
             "readEELSSpectrumImage"),
    overload("DM4Experiment.readEELSSpectrumImage(data:index:)", DM4,
             "public static func readEELSSpectrumImage(data: Data, index: Int)", "data:index:", "path:index:",
             "readEELSSpectrumImage"),
    struct("DM4EELSSpectrumImage", DM4, "public nonisolated struct DM4EELSSpectrumImage: Sendable, Equatable {",
           "DM4EELSSpectrumImage"),
    access("DM4EELSSpectrumImage.object", DM4, "public let object: DM4ImageObject\n    /// `ImageData.Dimensions` entry 1",
           "DM4EELSSpectrumImage", "object"),
    access("DM4EELSSpectrumImage.nx", DM4, "public let nx: Int\n    /// `ImageData.Dimensions` entry 2", "DM4EELSSpectrumImage", "nx"),
    access("DM4EELSSpectrumImage.ny", DM4, "public let ny: Int\n    /// `ImageData.Dimensions` entry 3", "DM4EELSSpectrumImage", "ny"),
    access("DM4EELSSpectrumImage.channels", DM4, "public let channels: Int\n    /// Row-major `(y, x, channel)`",
           "DM4EELSSpectrumImage", "channels"),
    access("DM4EELSSpectrumImage.counts", DM4, "public let counts: [Float]", "DM4EELSSpectrumImage", "counts"),
    access("DM4EELSSpectrumImage.energyAxis", DM4, "public let energyAxis: DM4Axis", "DM4EELSSpectrumImage", "energyAxis"),
    access("DM4EELSSpectrumImage.beamEnergyKeV", DM4, "public let beamEnergyKeV: Double?", "DM4EELSSpectrumImage",
           "beamEnergyKeV"),
    access("DM4EELSSpectrumImage.convergenceSemiAngleMrad", DM4, "public let convergenceSemiAngleMrad: Double?",
           "DM4EELSSpectrumImage", "convergenceSemiAngleMrad"),
    access("DM4EELSSpectrumImage.collectionSemiAngleMrad", DM4, "public let collectionSemiAngleMrad: Double?",
           "DM4EELSSpectrumImage", "collectionSemiAngleMrad"),
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
    # The bounded quit barrier (macTEM's ask 3)
    access("HDF5Serial.exitBarrierBound", HDF5, "public static var exitBarrierBound: TimeInterval {", "HDF5Serial",
           "exitBarrierBound"),
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
                            rf"|cannot find '{re.escape(word)}' in scope)$", text, re.M)
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
    if control["kind"] == "used":
        for m in re.finditer(r"^(\S+/tools/consumer-check/Sources/\S+\.swift:\d+:\d+): error: (.*)$", text, re.M):
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
