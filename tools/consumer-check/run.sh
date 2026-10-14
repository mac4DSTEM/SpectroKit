#!/bin/zsh
# SpectroKit consumer check: build tools/consumer-check (a separate package that depends on SpectroKit by path) in DEBUG and
# run it against the committed fixtures. Debug is what a consumer's Debug build does with a dependency that may carry no
# unsafe flags (SpectroKit's manifest has none). Exit 0 only if the build is warning-free, every check passed, no test-only
# target was built, and the process exited normally with the quit barrier installed.
#
#   run.sh [--controls]
#
#   (no flag)   build, run the checks, print "consumer-check: all passed — N checks ..." and exit 0.
#   --controls  then the negative controls (controls.py, python3 standard library only): for each symbol SpectroKit 0.2.0
#               made public, an edited COPY of the repository (rsync into <root>/.build/consumer-check/mutants/, never the
#               working tree) has that one declaration reverted from `public` to `package`; the consumer is built against
#               the copy and must FAIL with a compiler error naming that symbol. Prints
#               "consumer-check: negative controls: N of N caught" and exits non-zero unless all are caught.
#
# libhdf5 (the Velox reader dlopens the host's), in order, as tools/test.sh does:
#   1. MAC4DSTEM_HDF5_PATH if already set;
#   2. <root>/.build/hdf5/libhdf5.dylib, if present (tools/test.sh and step 3 write it);
#   3. mac4DSTEM's vendored copy at 5ba712a0 by `git show` into <root>/.build/hdf5, when ../mac4DSTEM is checked out
#      beside this repo;
#   4. Homebrew's hdf5.
set -euo pipefail
here=${0:A:h}
root=${here:h:h}

die() { print -u2 "consumer-check: $*"; exit 1 }

controls=0
for arg in "$@"; do
  case $arg in
    --controls) controls=1 ;;
    -h|--help) sed -n '2,/^set /p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown argument $arg (usage: run.sh [--controls])" ;;
  esac
done
cd $here

if [[ -z ${MAC4DSTEM_HDF5_PATH:-} ]]; then
  src=$root/../mac4DSTEM pin=5ba712a0 dir=$root/.build/hdf5
  if [[ -s $dir/libhdf5.dylib ]]; then
    export MAC4DSTEM_HDF5_PATH=$dir/libhdf5.dylib
  elif git -C $src --no-optional-locks cat-file -e ${pin}:libhdf5.dylib 2>/dev/null; then
    mkdir -p $dir
    for f in libhdf5.dylib libsz.2.dylib libaec.0.dylib; do
      [[ -s $dir/$f ]] || git -C $src --no-optional-locks show ${pin}:$f > $dir/$f
    done
    export MAC4DSTEM_HDF5_PATH=$dir/libhdf5.dylib
  elif command -v brew >/dev/null && [[ -e $(brew --prefix hdf5 2>/dev/null)/lib/libhdf5.dylib ]]; then
    export MAC4DSTEM_HDF5_PATH=$(brew --prefix hdf5)/lib/libhdf5.dylib
  else
    die "no libhdf5 (set MAC4DSTEM_HDF5_PATH, check out ../mac4DSTEM, or brew install hdf5)"
  fi
fi
[[ -e $MAC4DSTEM_HDF5_PATH ]] || die "MAC4DSTEM_HDF5_PATH=$MAC4DSTEM_HDF5_PATH does not exist"
print "consumer-check: libhdf5 = $MAC4DSTEM_HDF5_PATH"

# 1. Build, DEBUG. The log is kept: it shows what a consumer builds.
mkdir -p .build
log=.build/consumer-check-build.log
if ! swift build -c debug >$log 2>&1; then
  grep -E "error" $log | head -20 >&2
  die "BUILD FAILED (full log: $here/$log)"
fi
warnings=$(grep -c "warning:" $log || true)
(( warnings == 0 )) || { grep "warning:" $log | head >&2; die "$warnings warning(s) in the build" }

# 2. A consumer must not build the test-only targets: not SpectroKit's test targets, not the barrier's child process.
bin=$(swift build -c debug --show-bin-path)
leaked=$(find $bin .build \( -iname '*SpectroHDF5ExitProbe*' -o -iname '*SpectroKitTests*' -o -iname '*SpectroCoreTests*' \
         -o -iname '*SpectroGoldenTests*' \) 2>/dev/null | head -5)
[[ -z $leaked ]] || die "test-only target built for a consumer: $leaked"
if grep -qE "SpectroHDF5ExitProbe|SpectroKitTests|SpectroCoreTests|SpectroGoldenTests" $log; then
  die "the build log names a test-only target"
fi
built=$({ find .build/out/Intermediates.noindex -mindepth 3 -maxdepth 3 -type d -name '*.build' 2>/dev/null   # Swift Build
          find .build/debug -maxdepth 1 -type d -name '*.build' 2>/dev/null; } | sed 's|.*/||; s|\.build$||; s|-[a-z]$||' | sort -u | tr '\n' ' ')
print "consumer-check: targets built: ${built}"

# 3. Run. Exit status: the checks' (0 / 1), then the process's own end through `exit` (barrier handler: not 70).
out=.build/consumer-check-run.log
set +e
$bin/consumer-check $root/Tests >$out 2>&1
rc=$?
set -e
cat $out
(( rc == 0 )) || die "FAILED (exit $rc)"
if grep -q "quit barrier passed its bound" $out; then die "the quit barrier fired"; fi

summary=$(grep "^consumer-check summary:" $out)
checks=${${summary#consumer-check summary: }%% checks*}
head=$(git -C $root --no-optional-locks rev-parse --short HEAD 2>/dev/null || print unknown)
print "consumer-check: all passed — $checks checks through SpectroCore's public API only, Debug build, no warnings," \
      "no test-only target built, exit 0 with the quit barrier installed (SpectroKit $head, libhdf5 ${MAC4DSTEM_HDF5_PATH:t})"
(( controls )) || exit 0

# 4. Negative controls. The repository is never edited: controls.py works in an rsync'd copy under .build.
PY=${CONSUMER_CHECK_PYTHON:-python3}
command -v $PY >/dev/null || die "no $PY for --controls (set CONSUMER_CHECK_PYTHON)"
exec $PY -I -B $here/controls.py $root
