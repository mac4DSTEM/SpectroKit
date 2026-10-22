# Status

SpectroKit 0.11.0 (2026-10-22, local main until tagged; 0.10.0 tagged), on FormatoKit `"0.4.0"..<"1.0.0"` and ImagoKit `"0.6.1"..<"1.0.0"`, against HyperSpy 2.4.0 and exSpy 0.3.2. Live: EDX (the line table, peak identification, net counts, Cliff-Lorimer, zeta and
cross-section quantification with the absorption iteration, per pixel over a spectrum image) and EELS (t/lambda thickness, zero-loss alignment, power-law extrapolation, Fourier-log and Fourier-ratio deconvolution, the multi-edge model fit on 20 K and L edges with at% and wt%, Richardson-Lucy deconvolution, the MLLS fit, region sums); in EDX also sum and escape peaks in the fit, k-factor import, sigma on wt% and at%, and the per-region result; in SpectroCore line-profile pooling, smoothing (display only) and sparse regions. Every quantification (including the sum/escape model, sigma and MLLS, none of which has a Python reference or a standard) says
`validation: "none"` until a standard of known composition is measured. Parity: `docs/parity.md`; timings against Python: `docs/benchmarks.md`; parity numbers (2026-10-22, recounted from the rows): 100 rows, 58 present, 11 partial, 23 missing, 8 not planned; study rows 52 of 67 present; what is open (EELS fine structure, Richardson-Lucy speed on large images, weighted MLLS, EDS
calibration, the t/lambda loop speed): `docs/open-items.md`.

Tests (2026-10-21): the pinned Python comparisons (golden baseline, exSpy/HyperSpy/pyEELSMODEL pins, benchmarks, the PeakGate and Gate D runs) sit in `SpectroKitParityTests`; helpers and fixture loaders shared with the fast targets are in `SpectroTestSupport`. 360 tests before and after the split (309 fast + 51 parity). Mac, release, `--parallel`: fast target (`--skip SpectroKitParityTests`) 30 s, full suite 1 min 54 s; before the split, 1 min 45 s for the one full suite. CI keeps running the full suite.

0.11.0 adds to the element proposer the confirmation-line rule (R4), the sum-peak plausibility bound and the end of the pool at Bi
(`FamilyConsistencyTests`; measured on three real spectrum images through macTEM's harness), and an opt-in low-energy tail of the line
shape (`LineTail`, `TailEstimate`, off by default) once that lands. Fast target green on 2026-10-23; the parity target runs before the tag.

EELS per-edge windows (0.11.0, unreleased): `EELSModelFit.fit(edgeWindows:)` fits each edge's power law on its own background window and its amplitude on its own signal window (`EdgeWindows.defaults` holds the field's rules); `EELSBackground.preview` is the live power-law estimate; planted tests only, `validation: "none"`.
