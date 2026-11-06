# Status

SpectroKit 0.13.2 (2026-11-06), on FormatoKit `"0.12.0"..<"1.0.0"` and ImagoKit `"0.6.1"..<"1.0.0"`, against HyperSpy 2.4.0 and
exSpy 0.3.2 / 7185a4d1. macOS 15 and later (iOS was dropped from `Package.swift` in 0.13.0; it never built there).

Live:
- **EDX**: the line table, element identification (the published identification loop, `ElementProposer`, which refines the energy
  axis on its own K picks; the opt-in downward confirmation rule and the uncorroborated tier), net counts, the EDS fit with
  escape peaks and, by default where the data support them, sum peaks; the continuum step at absorption edges broadened by the
  detector by default, an optional Si dead-layer term, the opt-in NIST EPQ line weights; Cliff-Lorimer, zeta and cross-section
  quantification with the absorption iteration, per pixel over a spectrum image, k-factor import, sigma on wt% and at% (with
  take-off angle, thickness and dose terms) and per-pixel sigma maps, the per-region result.
- **EELS**: t/lambda thickness, zero-loss alignment, power-law extrapolation, Fourier-log, Fourier-ratio and Richardson-Lucy
  deconvolution, the edge model fit (joint, or per-edge windows with a 1σ per edge intensity) on 383 bundled K, L and M edges, the MLLS
  fit, composition in at% and wt%, region sums.
- **SpectroCore**: line-profile pooling, display smoothing, sparse regions.

Since 0.12.0: 0.13.0 (2026-11-01) added the EDX items above, removed `sameScanAs4DCube`, `elementsLine` and the duplicate GOS JSON,
and made the kit texts name the method without a validation tag (a standard of known composition has not been measured; the
parity rows say what each number is checked against); 0.13.1 and 0.13.2 (2026-11-01) fixed Fourier-ratio on a pixel with a
non-finite continuation, MLLS with a negative amount and the energy-axis refinement at its bounds. Details and the migration
notes: `CHANGELOG.md`.

Parity row by row: `docs/parity.md` (92 rows: 58 present, 11 partial, 23 missing);
timings against Python: `docs/benchmarks.md`; what is open: the GitHub issues; known limits: `docs/parity.md`; fixtures and their generators: `Tests/Fixtures/README.md`.

Tests: the fast targets run per change (`swift test -c release --parallel --skip SpectroKitParityTests`); the pinned Python comparisons
(golden baseline, exSpy/HyperSpy/pyEELSMODEL pins, the planted EDX runs) are `SpectroKitParityTests`, run in CI on every push and before a tag.
