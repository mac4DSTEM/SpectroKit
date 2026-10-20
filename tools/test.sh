#!/bin/zsh
# SpectroKit test gate: `swift test -c release`.
#
# Release: the manifest carries no Debug `-O` (a versioned dependency cannot carry unsafe flags) and Debug at -Onone is
# 20-50x slower on every hot path (SpectroGoldenTests 26 s vs 1349 s; S3 timings in the archived history, ../_archive/SpectroKit/docs/history.md). `-Xswiftc -O` on a Debug
# build is not an option: it also optimises the test targets. The tests use `package` access, not @testable.
#
# libhdf5 (0.4.0 on): the Velox reader is FormatoKit's, and FormatoKit ships libhdf5 2.1.1 inside FormatoHDF5 (the binaries
# the first host app vendors at 5ba712a0, the ones the golden was recorded with), found after MAC4DSTEM_HDF5_PATH and before the bare
# name. So the gate sets nothing: it runs as a consumer's `swift test` does. MAC4DSTEM_HDF5_PATH, when set, still overrides
# (CI or a check on another libhdf5, as Homebrew's 2.2.0 was for 0.3.0).
#
# Warnings: none allowed, except the three Swift Build prints once per fresh build for the dylibs FormatoKit ships signed
# ("not stripping binary because it is signed", FormatoKit's registration step 1 A2 and its own gate's rule).
#
# Names: XCTest's lines are in the log; Swift Testing's results go to .build/test-results/xunit-swift-testing.xml (the xUnit
# file SwiftPM writes beside xunit.xml). tools/test-names.py <log> <that file> lists every test the run passed or skipped.
#
# Lock: the suite's machine-wide rule (../CLAUDE.md): a `drive` file means a session drives an app on screen, so no test run.
# SpectroKit's `swift test` takes no slot of its own.
#
# Stamp: a full run (no arguments) that passes without a warning, on a tree whose Sources/, Tests/, Package.swift and
# Package.resolved are clean, untracked files included (CuboKit's rule: a new file nobody committed ran but is in no commit),
# writes .build/last-green (HEAD sha, UTC time, libhdf5). Any argument or a dirty tree writes nothing and says why on stderr.
# tools/last-green.sh prints the stamp and whether HEAD still equals it.
# Never run `swift build --build-tests -c release` (fails on this toolchain); this script is the gate.
set -euo pipefail
cd "${0:A:h}/.."
locks=/private/tmp/claude-501/-Users-paullobpreis-GitHub-mac4DSTEM-Organization-mac4DSTEM/locks
if [[ -e $locks/drive ]]; then
  print -u2 "tools/test.sh: a session is driving an app on screen ($locks/drive): no test run now"
  exit 75
fi
hdf5=${MAC4DSTEM_HDF5_PATH:-"the copy FormatoKit ships (FormatoLibHDF5.xcframework)"}
print -u2 "tools/test.sh: libhdf5 = $hdf5"
mkdir -p .build/test-results
rm -f .build/test-results/xunit*.xml(N)
log=.build/test-results/test.log
set +e
swift test -c release --xunit-output .build/test-results/xunit.xml "$@" 2>&1 | tee $log
rc=${pipestatus[1]}
set -e
(( rc == 0 )) || { print -u2 "tools/test.sh: swift test failed (exit $rc)"; exit $rc }
other=$(sed 's/\x1b\[[0-9;]*m//g' $log | grep "warning:" | grep -vE "warning: not stripping binary because it is signed: .*/FormatoLib(HDF5|SZ|AEC)/FormatoLib(HDF5|SZ|AEC)\.xcframework/" || true)
if [[ -n $other ]]; then print -u2 "tools/test.sh: green, but the build warned:"; print -u2 -r -- "$other"; exit 1; fi
if (( $# > 0 )); then
  print -u2 "tools/test.sh: green, but arguments were given (not a full run): no stamp"
elif [[ -n $(git status --porcelain --untracked-files=all -- Sources Tests Package.swift Package.resolved) ]]; then
  print -u2 "tools/test.sh: green, but Sources/Tests/Package files are not clean (untracked files included): no stamp"
else
  print -r -- "commit $(git rev-parse HEAD)
time $(date -u +%Y-%m-%dT%H:%M:%SZ)
libhdf5 $hdf5" > .build/last-green
  print -u2 "tools/test.sh: stamped .build/last-green at $(git rev-parse --short HEAD)"
fi
