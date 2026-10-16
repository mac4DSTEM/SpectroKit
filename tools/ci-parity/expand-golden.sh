#!/bin/sh
# Expand original golden [Double] hashes into element-wise pins on the original developer CPU.
# The recorder refuses every output unless all six raw scenario dumps still match their committed baselines byte for byte.
set -eu
cd "$(dirname "$0")/../.."
output=${1:-Tests/SpectroCoreTests/Fixtures/spectro-golden}
SPECTRO_GOLDEN_ARRAYS_DIR="$output" tools/test.sh --filter SpectroGoldenTests/testRecordPortableArrays
