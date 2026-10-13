#!/bin/zsh
# SpectroKit test gate: `swift test -c release` with a libhdf5 from outside the library.
#
# Release: the manifest carries no Debug `-O` (a versioned dependency cannot carry unsafe flags) and Debug at -Onone is
# 20-50x slower on every hot path (SpectroGoldenTests 26 s vs 1349 s; S3 timings in CLAUDE.md). `-Xswiftc -O` on a Debug
# build is not an option: it also optimises the test targets, and swift-frontend crashes on DM4ExperimentTests+Spectro
# ("swifterror value can only be loaded and stored from"). The tests use `package` access, not @testable.
#
# libhdf5: the Velox reader dlopens the host's libhdf5 at run time (MAC4DSTEM_HDF5_PATH, the host app's Frameworks, the
# loader path); a package test has no host bundle, and the library ships none. In order:
#   1. MAC4DSTEM_HDF5_PATH if already set;
#   2. mac4DSTEM's vendored copy (HDF5 2.1.1 + libsz + libaec, the exact binaries the app ships), read-only by `git show`
#      at the extraction commit into .build/hdf5, when ../mac4DSTEM is checked out beside this repo;
#   3. Homebrew's hdf5 (`brew install hdf5`; same soname 320), for CI and machines without mac4DSTEM.
set -euo pipefail
cd "${0:A:h}/.."
if [[ -z ${MAC4DSTEM_HDF5_PATH:-} ]]; then
  src=../mac4DSTEM pin=5ba712a0 dir=.build/hdf5
  if git -C $src --no-optional-locks cat-file -e ${pin}:libhdf5.dylib 2>/dev/null; then
    mkdir -p $dir
    for f in libhdf5.dylib libsz.2.dylib libaec.0.dylib; do
      [[ -s $dir/$f ]] || git -C $src --no-optional-locks show ${pin}:$f > $dir/$f
    done
    export MAC4DSTEM_HDF5_PATH=$PWD/$dir/libhdf5.dylib
  elif command -v brew >/dev/null && [[ -e $(brew --prefix hdf5 2>/dev/null)/lib/libhdf5.dylib ]]; then
    export MAC4DSTEM_HDF5_PATH=$(brew --prefix hdf5)/lib/libhdf5.dylib
  else
    print -u2 "tools/test.sh: no libhdf5 (set MAC4DSTEM_HDF5_PATH, check out ../mac4DSTEM, or brew install hdf5)"; exit 1
  fi
fi
print -u2 "tools/test.sh: libhdf5 = $MAC4DSTEM_HDF5_PATH"
swift test -c release "$@"
