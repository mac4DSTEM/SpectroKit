# Benchmarks: SpectroKit against HyperSpy and exSpy

Written 2026-10-21 for 0.8.0. Harness: Swift `Tests/SpectroKitParityTests/BenchmarkQuantificationTests.swift` and
`Tests/SpectroKitParityTests/BenchmarkThicknessTests.swift` (built by `swift test -c release`, enabled by `SPECTRO_BENCH_OUT`), Python
`tools/benchmarks/bench.py`, merged by `tools/benchmarks/table.py`. The Swift side peaks at 1.3 GB at the typical size. Inputs are closed-form on both sides (formulas in the harness headers), float64.
One warm-up, then five runs, median and (min-max).

Machine: Apple M5 Pro, 64 GB, macOS 27.0.1 (26A434), Swift 6.4 (swiftlang-6.4.0.34.1), Python 3.12.14, NumPy 2.5.4, HyperSpy 2.4.0, exSpy 0.3.2
(no Numba). **Other jobs were running on the machine**, so the Python spreads are wide; read ratios within about 30 %.

Re-run from a fresh clone of the kit, on a quiet Mac, one benchmark at a time:

```sh
python3.12 -m venv .venv-bench && .venv-bench/bin/pip install hyperspy==2.4.0 exspy==0.3.2
OUT="$PWD/.build/benchmarks"; mkdir -p "$OUT"
SPECTRO_BENCH_OUT="$OUT" SPECTRO_BENCH_SIZES=small,typical swift test -c release --filter Benchmark   # Swift side
.venv-bench/bin/python -I -B tools/benchmarks/bench.py "$OUT" small,typical                         # Python side
.venv-bench/bin/python -I -B tools/benchmarks/table.py "$OUT"                                       # prints the table below
```

## Results

| function | size | pixels | Swift CPU, ms median (min-max) | Python, ms median (min-max) | Python / Swift |
|---|---|---|---|---|---|
| quantification maps: CL | small | 64 | 0.03 (0.03-0.04) | 24.25 (22.87-54.62) | 739.62 |
| quantification maps: CL+absorption | small | 64 | 0.20 (0.19-0.20) | 178.25 (160.09-233.19) | 913.51 |
| quantification maps: zeta | small | 64 | 0.02 (0.02-0.02) | 30.13 (26.23-77.22) | 1409.82 |
| quantification maps: zeta+absorption | small | 64 | 0.11 (0.10-0.12) | 107.16 (92.21-159.42) | 1002.64 |
| quantification maps: cross_section | small | 64 | 0.02 (0.02-0.03) | 61.30 (57.32-122.77) | 2464.49 |
| quantification maps: CL | typical | 65536 | 9.02 (8.63-9.50) | 312.23 (307.89-322.30) | 34.60 |
| quantification maps: CL+absorption | typical | 65536 | 39.38 (38.00-40.36) | 989.56 (933.26-1025.54) | 25.13 |
| quantification maps: zeta | typical | 65536 | 6.73 (6.38-7.32) | 38.62 (34.42-87.84) | 5.74 |
| quantification maps: zeta+absorption | typical | 65536 | 29.90 (29.16-39.16) | 129.60 (92.88-168.46) | 4.33 |
| quantification maps: cross_section | typical | 65536 | 9.99 (9.64-10.59) | 50.59 (43.01-90.63) | 5.06 |
| t/lambda log ratio: fixed 3 eV | small | 64 | 0.15 (0.15-0.17) | 3.62 (3.08-4.46) | 23.43 |
| t/lambda log ratio: estimated | small | 64 | 0.25 (0.24-0.32) | 12.10 (11.87-12.86) | 47.61 |
| t/lambda log ratio: fixed 3 eV | typical | 4096 | 9.90 (9.53-10.19) | 5.01 (4.71-8.40) | 0.51 |
| t/lambda log ratio: estimated | typical | 4096 | 16.34 (16.29-17.02) | 87.30 (82.73-123.58) | 5.34 |

Sizes: quantification small 8 x 8, typical 256 x 256 (3 elements), large 1024 x 1024; thickness small 8 x 8, typical 64 x 64 (2048 channels), large 256 x 256.
**Large: not measured yet** (`large` in the size list adds it).

## Backend decision per function

| function | decision | why |
|---|---|---|
| quantification maps, all methods (the Python column converts to weight percent only; Swift returns both) | CPU only (parallel over pixels since 0.8.0) | 9 to 40 ms for 65 536 pixels; per pixel the work is 10 to 500 ns of arithmetic, so a Metal dispatch pays only above about 1e6 pixels; the break-even is **not measured** (the large size is not measured yet). Not a work item until a large-size run shows a slow large image |
| t/lambda log ratio, fixed threshold | CPU only; **slower than Python on the typical size** (0.49x), first in `docs/open-items.md` | single-threaded scalar passes against NumPy's vectorised axis sums |
| t/lambda log ratio, estimated threshold | CPU only | 5x faster than Python at the typical size (Python's per-pixel Savitzky-Golay search dominates) |
| EDX line fit, auto ID, EELS background fit, edge quantification | not benchmarked in 0.8.0 | need a Velox spectrum image or a planted EELS image on both sides; listed in `docs/open-items.md` |
