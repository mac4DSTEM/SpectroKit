#!/bin/zsh
# One benchmark at a time, machine-wide (suite rule): run the Swift harness, then the Python side, then merge the JSON into a table.
#   tools/benchmarks/run.sh [small,typical]      sizes: small, typical, large (large is the nightly review's)
# Output: $TMPDIR-free, under .build/benchmarks/ (ignored). The table goes to stdout in docs/benchmarks.md's format.
set -eu
cd "$(dirname "$0")/../.."
sizes="${1:-small,typical}"
out="$PWD/.build/benchmarks"; mkdir -p "$out"
memcap="$PWD/../tools/memcap.sh"
SPECTRO_BENCH_OUT="$out" SPECTRO_BENCH_SIZES="$sizes" "$memcap" -- swift test -c release --filter 'Benchmark' >"$out/swift.log" 2>&1
"$memcap" -- ../refs/hyperspy/bin/python -I -B tools/benchmarks/bench.py "$out" "$sizes" >"$out/python.log" 2>&1
../refs/hyperspy/bin/python -I -B tools/benchmarks/table.py "$out"
