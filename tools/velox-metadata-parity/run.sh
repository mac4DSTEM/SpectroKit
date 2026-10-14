#!/bin/zsh
# tools/velox-metadata-parity — the six Velox metadata fields SpectroKit 0.2.0 added to `VeloxMetadata`
# (nominalMagnification, stemMagnification, cameraLengthMeters, operatingMode, projectorMode, exposureTimeSeconds, and
# each detector's exposureTimeSeconds) against what h5py reads from RosettaSciIO 049e7d70's public Velox files, bit for
# bit. A reference for every number: README.md says what is compared with what, the pins, and what this cannot show.
#
#   run.sh [--table] [--controls] [extra.emd ...]
#
#   (no flag)    lock check, unzip, reference.py (h5py + the pinned `_get_detector_metadata_dict`), build swift/ (a
#                package that depends on SpectroKit BY PATH, public API only), dump, compare.py. Exit 0 only when
#                everything agrees.
#   --table      also print the per-entry table (it is always written to .build/velox-metadata-parity/table.md).
#   --controls   then the negative controls: an edited COPY of the package per mutant, the Swift reader rebuilt against
#                it, and compare.py must FAIL on the case named for that mutant, or the harness is blind to it.
#   extra.emd    more files to read both ways. Tests/SpectroKitTests/Fixtures/velox-metadata-planted.emd is added
#                when it exists.
#
# Pass: "velox-metadata-parity: all passed — ..." (and, with --controls, "negative controls: N of N caught"), exit 0.
# Environment: SPECTROKIT_REFERENCES (default <root>/References: rosettasciio, python-venv), MAC4DSTEM_HDF5_PATH
# (libhdf5; default <root>/.build/hdf5, which tools/test.sh fills, else Homebrew's).
set -euo pipefail

HERE="${0:A:h}"
ROOT="${HERE:h:h}"
REFS="${SPECTROKIT_REFERENCES:-$ROOT/References}"
RSCIIO="$REFS/rosettasciio"
PY="$REFS/python-venv/bin/python"
PIN=049e7d7070e84779b499adaf3295beee9facb004
DATA="$RSCIIO/rsciio/tests/data/emd"
BUILD="$ROOT/.build/velox-metadata-parity"
WORK="$BUILD/work"
PLANTED="$ROOT/Tests/SpectroKitTests/Fixtures/velox-metadata-planted.emd"
ZIPS=(fei_emd_files.zip velox_EELS_EDS.zip velox_emd_v11_elementSelection.zip velox_emd_version11.zip)

die() { print -u2 "velox-metadata-parity: $*"; exit 66; }

controls=0 table=0
typeset -a extras
for arg in "$@"; do
  case $arg in
    --controls) controls=1 ;;
    --table) table=1 ;;
    -h|--help) sed -n '2,/^set /p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
    --*) die "unknown option $arg" ;;
    *) [[ -f $arg ]] || die "$arg is not a file"; extras+=("${arg:A}") ;;
  esac
done
[[ -f $PLANTED ]] && extras+=("$PLANTED")

# 1. The lock: rsciio at the pin, a clean tree, the venv Python.
[[ -e $RSCIIO/.git ]] || die "$RSCIIO is not a git checkout (set SPECTROKIT_REFERENCES)"
head=$(git -C "$RSCIIO" --no-optional-locks rev-parse HEAD)
[[ $head == $PIN ]] || die "rosettasciio HEAD is $head, not the pinned $PIN"
[[ -z $(git -C "$RSCIIO" --no-optional-locks status --porcelain --untracked-files=all) ]] \
  || die "rosettasciio checkout is not clean"
[[ -x $PY ]] || die "no reference Python at $PY"

# 2. libhdf5, which the reader dlopens from outside the library (tools/test.sh's order, without the git-show step).
if [[ -z ${MAC4DSTEM_HDF5_PATH:-} ]]; then
  if [[ -e $ROOT/.build/hdf5/libhdf5.dylib ]]; then
    export MAC4DSTEM_HDF5_PATH=$ROOT/.build/hdf5/libhdf5.dylib
  elif command -v brew >/dev/null && [[ -e $(brew --prefix hdf5 2>/dev/null)/lib/libhdf5.dylib ]]; then
    export MAC4DSTEM_HDF5_PATH=$(brew --prefix hdf5)/lib/libhdf5.dylib
  else
    die "no libhdf5 (set MAC4DSTEM_HDF5_PATH, run tools/test.sh once to fill .build/hdf5, or brew install hdf5)"
  fi
fi
[[ -e $MAC4DSTEM_HDF5_PATH ]] || die "MAC4DSTEM_HDF5_PATH=$MAC4DSTEM_HDF5_PATH does not exist"

# 3. A fresh scratch directory under .build; each zip is checked against registry.txt and unzipped into its own empty
#    directory there, never into References. (registry.txt names the four zips and the loose files, not the zips'
#    members; reference.py then checks every member against the verified archive.)
[[ -n $BUILD && $BUILD == $ROOT/.build/* ]] || die "refusing to clear $BUILD"
rm -rf "$WORK"
mkdir -p "$WORK/zips"
for zip in $ZIPS; do
  want=$(sed -n "s|^'emd/$zip' \([0-9a-f]\{64\}\)\$|\1|p" "$RSCIIO/rsciio/tests/registry.txt")
  [[ -n $want ]] || die "emd/$zip is not in registry.txt"
  have=$(shasum -a 256 "$DATA/$zip" | cut -d' ' -f1)
  [[ $have == $want ]] || die "$zip: sha256 $have is not the registry's $want"
  mkdir "$WORK/zips/${zip:r}"
  unzip -q "$DATA/$zip" -d "$WORK/zips/${zip:r}"
done

# 4. The reference, then the reader.
"$PY" -I -B "$HERE/reference.py" "$RSCIIO" "$WORK/zips" "$WORK/reference.json" "${extras[@]}"

typeset -a files
files=("${(@f)$("$PY" -I -B -c '
import json, sys
for info in json.load(open(sys.argv[1]))["files"].values():
    print(info["path"])
' "$WORK/reference.json")}")

build_dump() {   # build_dump <swift package dir> <log>: release build, prints the executable's path
  swift build -c release --package-path "$1" > "$2" 2>&1 || { tail -30 "$2" >&2; die "swift build failed ($2)"; }
  print -- "$(swift build -c release --package-path "$1" --show-bin-path)/velox-metadata-dump"
}
dump=$(build_dump "$HERE/swift" "$WORK/swift-build.log")
warnings=$(grep -c 'warning:' "$WORK/swift-build.log" || true)
print "swift: built $dump (${warnings} warnings in the build log)"
"$dump" "${files[@]}" > "$WORK/swift.json"

# 5. The comparison.
typeset -a compare_flags
compare_flags=(--table "$BUILD/table.md")
(( table )) && compare_flags+=(--print-table)
"$PY" -I -B "$HERE/compare.py" "$WORK/reference.json" "$WORK/swift.json" "${compare_flags[@]}"
print "table: $BUILD/table.md"
(( controls )) || exit 0

# 6. Negative controls. The package is never edited here: each mutant is an edited COPY of VeloxEMDReader.swift in a
#    scratch copy of the package, the Swift reader is rebuilt against it, and compare.py must exit 1 AND print a FAIL
#    line naming the case the mutant is aimed at. The edit must apply exactly once (a changed line makes the mutation
#    fail loudly, to be re-aimed). A mutant that only the planted fixture can catch counts as not caught while that
#    fixture is absent.
COPY="$WORK/mutants/${ROOT:t}"
mkdir -p "$COPY"
rsync -a --exclude .build --exclude .git --exclude References "$ROOT/" "$COPY/"
SOURCE_REL=Sources/SpectroCore/Data/VeloxEMDReader.swift
cp "$COPY/$SOURCE_REL" "$WORK/pristine.swift"
caught=0 total=0
planted_name=${PLANTED:t}

# mutant <name> <catcher> <old> <new> [<old> <new>]...; catcher: "public:<line prefix>" or "planted:<field>"
mutant() {
  local name=$1 catcher=$2; shift 2
  total=$(( total + 1 ))
  local dir="$WORK/mutant-$name" log pattern rc
  mkdir -p "$dir"
  cp "$WORK/pristine.swift" "$COPY/$SOURCE_REL"
  while (( $# >= 2 )); do
    "$PY" -I -B -c '
import sys
path, old, new = sys.argv[1:4]
text = open(path, encoding="utf-8").read()
if text.count(old) != 1:
    sys.exit("expected exactly one occurrence of the edit target, found %d: %s" % (text.count(old), old))
open(path, "w", encoding="utf-8").write(text.replace(old, new))
' "$COPY/$SOURCE_REL" "$1" "$2" || { print "  FAIL  mutation '$name' does not apply"; return; }
    shift 2
  done
  local mutated
  if ! mutated=$(build_dump "$COPY/tools/velox-metadata-parity/swift" "$dir/build.log" 2> "$dir/build.err"); then
    print "  FAIL  mutation '$name' does not compile (see $dir/build.log)"; return
  fi
  "$mutated" "${files[@]}" > "$dir/swift.json"
  log="$dir/compare.log"
  set +e
  "$PY" -I -B "$HERE/compare.py" "$WORK/reference.json" "$dir/swift.json" > "$log" 2>&1
  rc=$?
  set -e
  if [[ $catcher == planted:* ]]; then
    if [[ ! -f $PLANTED ]]; then
      print "  FAIL  mutation '$name': no public file catches it and $planted_name is absent, so nothing can"
      return
    fi
    pattern="  FAIL  planted/$planted_name | "
    if (( rc == 1 )) && grep -F "$pattern" "$log" | grep -qF "| ${catcher#planted:}"; then
      caught=$(( caught + 1 )); print "  ok    mutation '$name' is caught on $planted_name, field ${catcher#planted:}"
    else
      print "  FAIL  mutation '$name' exited $rc without failing $planted_name on ${catcher#planted:}"
    fi
  else
    pattern="  FAIL  ${catcher#public:}"
    if (( rc == 1 )) && grep -qF -- "$pattern" "$log"; then
      caught=$(( caught + 1 ))
      print "  ok    mutation '$name' is caught at: $(grep -F -- "$pattern" "$log" | head -1 | sed 's/^  FAIL  //')"
    else
      print "  FAIL  mutation '$name' exited $rc without a FAIL line starting '$pattern':"
      head -8 "$log" | sed 's/^/        /'
    fi
  fi
}

CETA_AT_1854='fei_emd_files.zip/1854 Camera Ceta.emd | b8c736'
mutant exposure-by-contains "planted:exposureTimeSeconds" \
  'exposure = detectors.first { $0.name == detectorName }?.exposureTimeSeconds' \
  'exposure = detectors.first { $0.name.contains(detectorName) }?.exposureTimeSeconds'
mutant exposure-from-last-match "planted:exposureTimeSeconds" \
  'exposure = detectors.first { $0.name == detectorName }?.exposureTimeSeconds' \
  'exposure = detectors.last { $0.name == detectorName }?.exposureTimeSeconds'
mutant exposure-by-detector-index "public:$CETA_AT_1854 | exposureTimeSeconds" \
  'exposure = detectors.first { $0.name == detectorName }?.exposureTimeSeconds' \
  'exposure = detectors.first { $0.index == jsonInt(binary?["DetectorIndex"]) }?.exposureTimeSeconds'
mutant camera-length-from-magnification "public:fei_emd_files.zip/1532 Camera Ceta.emd | 3d77c2 | cameraLengthMeters" \
  'cameraLengthMeters: jsonDouble(optics?["CameraLength"]),' \
  'cameraLengthMeters: jsonDouble(optics?["NominalMagnification"]),'
mutant operating-mode-always-nil "public:fei_emd_files.zip/fei_emd_image.emd | 23088c | operatingMode" \
  'operatingMode: optics?["OperatingMode"] as? String,' \
  'operatingMode: nil,'
mutant modes-swapped "public:fei_emd_files.zip/fei_emd_image.emd | 23088c | operatingMode" \
  'operatingMode: optics?["OperatingMode"] as? String, projectorMode: optics?["ProjectorMode"] as? String,' \
  'operatingMode: optics?["ProjectorMode"] as? String, projectorMode: optics?["OperatingMode"] as? String,'
mutant detector-exposure-dropped "public:$CETA_AT_1854 | Detector-8.exposureTimeSeconds" \
  'exposureTimeSeconds: jsonDouble(d["ExposureTime"])))' \
  'exposureTimeSeconds: nil))'
mutant stem-from-nominal "public:fei_emd_files.zip/fei_emd_image.emd | 23088c | stemMagnification" \
  'stemMagnification: jsonDouble(dict(custom, "StemMagnification")?["value"]),' \
  'stemMagnification: jsonDouble(optics?["NominalMagnification"]),'
mutant stem-without-value-key "public:fei_emd_files.zip/fei_emd_image.emd | 23088c | stemMagnification" \
  'stemMagnification: jsonDouble(dict(custom, "StemMagnification")?["value"]),' \
  'stemMagnification: jsonDouble(dict(custom, "StemMagnification")?["Value"]),'
mutant stem-zero-as-nil "public:loose/fei_example_complex_fft.emd | 127c4d | stemMagnification" \
  'stemMagnification: jsonDouble(dict(custom, "StemMagnification")?["value"]),' \
  'stemMagnification: jsonDouble(dict(custom, "StemMagnification")?["value"]).flatMap { $0 == 0 ? nil : $0 },'
mutant nominal-from-stem "public:fei_emd_files.zip/1854 Camera Ceta.emd | b8c736 | nominalMagnification" \
  'nominalMagnification: jsonDouble(optics?["NominalMagnification"]),' \
  'nominalMagnification: jsonDouble(dict(custom, "StemMagnification")?["value"]),'

print "velox-metadata-parity: negative controls: $caught of $total caught"
(( caught == total ))
