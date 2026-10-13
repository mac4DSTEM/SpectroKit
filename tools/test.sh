#!/bin/zsh
# SpectroKit S2 test gate: `swift test` with the host's libhdf5.
# The Velox reader loads libhdf5 at run time from the host (VeloxHDF5Library: MAC4DSTEM_HDF5_PATH, the host app's
# Frameworks, the loader path); a package test has no host bundle. Until S3 settles where the library's own tests get it,
# this takes mac4DSTEM's vendored copy (and its libsz, libaec) from the extraction commit, read-only by `git show`, into .build/.
set -euo pipefail
cd "${0:A:h}/.."
src=../mac4DSTEM pin=5ba712a0 dir=.build/hdf5
mkdir -p $dir
for f in libhdf5.dylib libsz.2.dylib libaec.0.dylib; do
  [[ -s $dir/$f ]] || git -C $src --no-optional-locks show $pin:$f > $dir/$f
done
MAC4DSTEM_HDF5_PATH=$PWD/$dir/libhdf5.dylib swift test "$@"
