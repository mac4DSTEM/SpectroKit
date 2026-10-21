#!/bin/zsh
# SpectroKit consumer check: build tools/consumer-check (a separate package that depends on SpectroKit by path) in DEBUG and
# run it against the committed fixtures. Debug is what a consumer's Debug build does with a dependency that may carry no
# unsafe flags (SpectroKit's manifest has none). Nothing is set up first: the file readers are FormatoKit's (0.4.0) and
# FormatoKit ships libhdf5 as three binary xcframeworks (FormatoLibHDF5, FormatoLibSZ, FormatoLibAEC), so MAC4DSTEM_HDF5_PATH is
# unset before the run. Exit 0 only if the build has no warning but FormatoKit's prints for those signed xcframeworks
# ("not stripping binary because it is signed"), SpectroKit_SpectroEELS.bundle (the GOS tables) and the three frameworks
# (loaded via @rpath, checked with otool -L) sit next to the binary, every check passed, no test-only target was built, and the
# process exited normally with the quit barrier installed (the Velox open installs FormatoKit's).
#
# Then (readme/, a second package) the README's own code: check-readme.py fails if README.md and the programs built from its marked
# code blocks (Examples/QuantifyEDX, readme/Sources/readme-consumer) differ; the second consumer is built in Debug with no
# warning but those notices and run on its planted spectrum: Mg, Al and Si proposed and quantified, t/lambda 0.5 within 0.01.
#
#   run.sh
#
#   (no flag)   build, run the checks, print "consumer-check: all passed — N checks ..." and exit 0.
set -euo pipefail
here=${0:A:h}
root=${here:h:h}

die() { print -u2 "consumer-check: $*"; exit 1 }

for arg in "$@"; do
  case $arg in
    -h|--help) sed -n '2,/^set /p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown argument $arg (usage: run.sh)" ;;
  esac
done
cd $here

# No setup: FormatoKit's shipped libhdf5 must be found without a path in the environment.
unset MAC4DSTEM_HDF5_PATH

# Zero warnings in a build log, except the three FormatoKit prints for its signed dylibs. Used for both consumers below. (The three prints may be absent on a warm build.)
build_warnings() {
python3 -I -B - $1 <<'PY'
import re, sys
text = re.sub(r"\x1b\[[0-9;]*m", "", open(sys.argv[1], encoding="utf-8", errors="replace").read())
allowed = re.compile(r"^warning: not stripping binary because it is signed: .*"
                     r"/FormatoLib(HDF5|SZ|AEC)/FormatoLib(?:HDF5|SZ|AEC)\.xcframework/")
seen, other = [], []
for fragment in text.split("warning:")[1:]:
    fragment = "warning:" + fragment
    m = allowed.match(fragment)
    if m:
        seen.append(m.group(1))
    else:
        other.append(fragment.splitlines()[0][:300])
if other or len(set(seen)) > 3:
    for line in other[:10] or ["more than the three FormatoLib xcframework names: " + ", ".join(sorted(set(seen)))]:
        print(line, file=sys.stderr)
    sys.exit(1)
print("consumer-check: build warnings: %d, all FormatoKit's signed-dylib notices (%s)" % (len(seen), ", ".join(sorted(set(seen))) or "none"))
PY
}

# 1. Build, DEBUG. The log is kept: it shows what a consumer builds.
mkdir -p .build
log=.build/consumer-check-build.log
# --disable-dependency-cache: SwiftPM's shared repository cache can print a 'skipping cache' warning on a CI runner,
# which the warning count would take for the kit's own (DiffractoKit 0.4.1's CI).
if ! swift build --disable-dependency-cache -c debug >$log 2>&1; then
  { grep -E "error" $log | head -20 >&2; } || true
  die "BUILD FAILED (full log: $here/$log)"
fi
# Zero warnings, except the three Swift Build prints for FormatoKit's signed dylibs (it cannot strip a signed binary). The lines
# may arrive glued together, so the log is stripped of colour codes and split on "warning:" before each is matched.
build_warnings $log || die "unexpected warning(s) in the build (full log: $here/$log)"

# 2. A consumer must not build the test-only targets: not SpectroKit's or FormatoKit's test targets, not the barrier's child process.
bin=$(swift build --disable-dependency-cache -c debug --show-bin-path) || die "swift build --show-bin-path failed"
[[ -d $bin ]] || die "the build's bin path does not exist: $bin"
# (.build/checkouts holds FormatoKit's sources, test directories included: not built, so not searched.)
leaked=$(find $bin .build -path .build/checkouts -prune -o \( -iname '*ExitProbe*' -o -iname '*SpectroKitTests*' \
         -o -iname '*SpectroCoreTests*' -o -iname '*SpectroGoldenTests*' -o -iname '*SpectroKitParityTests*' -o -iname '*SpectroTestSupport*' -o -iname '*SpectroEDXTests*' \
         -o -iname '*SpectroEELSTests*' -o -iname 'Formato*Tests*' \) -print 2>/dev/null | head -5 || true)
[[ -z $leaked ]] || die "test-only target built for a consumer: $leaked"
if grep -qE "ExitProbe|SpectroKitTests|SpectroCoreTests|SpectroGoldenTests|SpectroKitParityTests|SpectroTestSupport|SpectroEDXTests|SpectroEELSTests|Formato[A-Za-z0-9]*Tests" $log; then
  die "the build log names a test-only target"
fi
# Each optional backend directory may be absent. Guard each find: a trailing true in the group does not stop zsh -e
# from exiting at the first failed find, before that true is reached.
built=$({ find .build/out/Intermediates.noindex -mindepth 3 -maxdepth 3 -type d -name '*.build' 2>/dev/null || true   # Swift Build
          find .build/debug -maxdepth 1 -type d -name '*.build' 2>/dev/null || true; } | sed 's|.*/||; s|\.build$||; s|-[a-z]$||' | sort -u | tr '\n' ' ')
print "consumer-check: targets built: ${built}"

# SpectroEELS's GOS tables are its Bundle.module resources: the bundle must sit next to the consumer binary, with the three
# tables (C, N, O K) inside; without it the cross section cannot load and Bundle.module traps at run time.
gosbundle=$bin/SpectroKit_SpectroEELS.bundle
[[ -d $gosbundle ]] || die "SpectroKit_SpectroEELS.bundle was not produced next to the consumer binary ($bin)"
for el in C N O; do
  [[ -n $(find $gosbundle -type f -name "dft-${el}-K1.json" -size +1k 2>/dev/null | head -1) ]] \
    || die "SpectroKit_SpectroEELS.bundle has no GOS table dft-${el}-K1.json"
done
print "consumer-check: SpectroKit_SpectroEELS.bundle next to the binary, with the C, N and O K GOS tables"

# FormatoKit (0.4.0 on) ships libhdf5, libsz and libaec as binary xcframeworks: the consumer binary must load
# FormatoLibHDF5 through @rpath, and each framework must sit next to the binary, or the Velox open finds no library at run time.
otool -L $bin/consumer-check | grep -q "@rpath/FormatoLibHDF5.framework/" \
  || die "the consumer binary does not load @rpath/FormatoLibHDF5.framework (otool -L)"
for fw in FormatoLibHDF5 FormatoLibSZ FormatoLibAEC; do
  [[ -f $bin/$fw.framework/Versions/A/$fw || -f $bin/$fw.framework/$fw ]] \
    || die "$fw.framework was not produced next to the consumer binary ($bin)"
done
print "consumer-check: the binary loads @rpath/FormatoLibHDF5.framework; FormatoLibHDF5, FormatoLibSZ and FormatoLibAEC frameworks next to it (no MAC4DSTEM_HDF5_PATH)"

# 3. Run. Exit status: the checks' (0 / 1), then the process's own end through `exit` (FormatoKit's barrier handler: not 70).
out=.build/consumer-check-run.log
set +e
$bin/consumer-check $root/Tests >$out 2>&1
rc=$?
set -e
cat $out
(( rc == 0 )) || die "FAILED (exit $rc)"
if grep -q "quit barrier passed its bound" $out; then die "the quit barrier fired"; fi

summary=$(grep "^consumer-check summary:" $out) || die "the run printed no summary line"
checks=${${summary#consumer-check summary: }%% checks*}
head=$(git -C $root --no-optional-locks rev-parse --short HEAD 2>/dev/null || print unknown)
print "consumer-check: all passed — $checks checks through SpectroCore's and SpectroEELS's public API only, Debug build, no warnings" \
      "but FormatoKit's signed-dylib notices, no test-only target built, exit 0 with the quit barrier installed (SpectroKit $head," \
      "FormatoKit's shipped libhdf5, no setup)"

# 3b. The README consumer (tools/consumer-check/readme): a second package, built from the README's code blocks and nothing else.
# (i) The README and the two programs made from it must not differ (check-readme.py; `--write` regenerates them from the README).
# (ii) Debug build, zero warnings (the same filter). (iii) Run with no argument, the planted spectrum: exit 0, Mg, Al and Si
# proposed and each given an at.% line, the validation note printed, and the EELS t/lambda within 0.01 of the planted 0.5.
readme=$here/readme
python3 -I -B $readme/check-readme.py $root || die "the README's code and the programs built from it differ (python3 -I -B $readme/check-readme.py --write $root rewrites them from the README)"
cd $readme
mkdir -p .build
rlog=.build/readme-consumer-build.log
if ! swift build --disable-dependency-cache -c debug >$rlog 2>&1; then
  { grep -E "error" $rlog | head -20 >&2; } || true
  die "README CONSUMER BUILD FAILED (full log: $readme/$rlog)"
fi
build_warnings $rlog || die "unexpected warning(s) in the README consumer's build (full log: $readme/$rlog)"
rbin=$(swift build --disable-dependency-cache -c debug --show-bin-path)
rout=.build/readme-consumer-run.log
set +e
$rbin/readme-consumer >$rout 2>&1
rrc=$?
set -e
cat $rout
(( rrc == 0 )) || die "README CONSUMER FAILED (exit $rrc, full log: $readme/$rout)"
python3 -I -B - $rout <<'PY' || die "the README consumer printed no sane planted result (full log: $readme/$rout)"
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"^proposed elements: (.*)$", text, re.M)
proposed = set(m.group(1).split()) if m else set()
if proposed != {"Mg", "Al", "Si"}:
    sys.exit("proposed elements %s, planted Mg Al Si" % sorted(proposed))
for el in ("Mg", "Al", "Si"):
    if not re.search(r"^%s [0-9.]+ at\.%% \+- [0-9.]+$" % el, text, re.M):
        sys.exit("no at.%% line with a sigma for %s" % el)
if not re.search(r"^validation: none ", text, re.M):
    sys.exit("no 'validation: none' line")
t = re.search(r"^t/lambda = ([0-9.eE+-]+) \+- ([0-9.eE+-]+) \(planted 0\.5, validation: none\)$", text, re.M)
if not t or abs(float(t.group(1)) - 0.5) > 0.01 or not 0 < float(t.group(2)) < 0.01:
    sys.exit("t/lambda line missing or not 0.5 within 0.01")
print("consumer-check: README consumer: Mg Al Si proposed with at.%% and sigma, validation none, t/lambda %s +- %s" % (t.group(1)[:6], t.group(2)[:6]))
PY
cd $here
