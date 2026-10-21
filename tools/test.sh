#!/bin/zsh
# SpectroKit test gate: `swift test -c release`, then no warnings but the three Swift Build prints for FormatoKit's signed
# dylibs ("not stripping binary because it is signed"). Release because Debug is 20-50x slower on the numeric loops; never
# `swift build --build-tests -c release` (fails on this toolchain). Real-data tests return without checking when the file
# is absent (CI has none). libhdf5 comes with FormatoKit; MAC4DSTEM_HDF5_PATH, when set, overrides it.
set -euo pipefail
cd "${0:A:h}/.."
mkdir -p .build/test-results
log=.build/test-results/test.log
set +e
swift test -c release "$@" 2>&1 | tee $log
rc=${pipestatus[1]}
set -e
(( rc == 0 )) || { print -u2 "tools/test.sh: swift test failed (exit $rc)"; exit $rc }
other=$(sed 's/\x1b\[[0-9;]*m//g' $log | grep "warning:" | grep -vE "warning: not stripping binary because it is signed: .*/FormatoLib(HDF5|SZ|AEC)/FormatoLib(HDF5|SZ|AEC)\.xcframework/" || true)
if [[ -n $other ]]; then print -u2 "tools/test.sh: green, but the build warned:"; print -u2 -r -- "$other"; exit 1; fi
