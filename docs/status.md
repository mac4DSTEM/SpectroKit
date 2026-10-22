# Status

SpectroKit 0.9.0 (2026-10-22), on FormatoKit `"0.4.0"..<"1.0.0"` and ImagoKit `"0.6.1"..<"1.0.0"`, against HyperSpy 2.4.0 and exSpy 0.3.2. Live: EDX (the line table, peak identification, net counts, Cliff-Lorimer, zeta and
cross-section quantification with the absorption iteration, per pixel over a spectrum image) and EELS (t/lambda thickness, zero-loss alignment, power-law extrapolation, Fourier-log and Fourier-ratio deconvolution, the multi-edge model fit on 20 K and L edges with at% and wt%, region sums). Every quantification says
`validation: "none"` until a standard of known composition is measured. Parity: `docs/parity.md`; timings against Python: `docs/benchmarks.md`; what is open (Richardson-Lucy, EELS fine structure, EDS
calibration, the t/lambda loop speed): `docs/open-items.md`.

Tests (2026-10-21): the pinned Python comparisons (golden baseline, exSpy/HyperSpy/pyEELSMODEL pins, benchmarks, the PeakGate and Gate D runs) sit in `SpectroKitParityTests`; helpers and fixture loaders shared with the fast targets are in `SpectroTestSupport`. 360 tests before and after the split (309 fast + 51 parity). Mac, release, `--parallel`: fast target (`--skip SpectroKitParityTests`) 30 s, full suite 1 min 54 s; before the split, 1 min 45 s for the one full suite. CI keeps running the full suite.
