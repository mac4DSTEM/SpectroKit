#!/bin/bash
# The audit workflow's nightly CPU benchmark (.github/workflows/audit.yml, the suite's template): runs the Swift side of
# tools/benchmarks/run.sh (the Benchmark* tests, SPECTRO_BENCH_OUT, sizes small and typical) and writes the timings to $1
# as a JSON list of {name, dtype, size, ms: [the timed runs]}. The Python side and the table stay local (run.sh); this
# run only compares the kit with its own previous night.
set -euo pipefail
out="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
dir="$(mktemp -d)"
SPECTRO_BENCH_OUT="$dir" SPECTRO_BENCH_SIZES=small,typical swift test -c release --filter Benchmark
python3 -I - "$dir" "$out" <<'PY'
import glob, json, os, sys
rows = []
for path in sorted(glob.glob(os.path.join(sys.argv[1], "swift-*.json"))):
    for r in json.load(open(path)):
        rows.append({"name": r["function"], "dtype": "float64", "size": r["size"], "ms": [t * 1000 for t in r["swift_cpu_s"]]})
if not rows:
    sys.exit("no swift-*.json written")
json.dump(rows, open(sys.argv[2], "w"), indent=1)
print(f"{len(rows)} cases")
PY
