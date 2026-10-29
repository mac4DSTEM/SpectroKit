# Status

SpectroKit 0.12.0 (tagged 2026-10-23), on FormatoKit `"0.4.0"..<"1.0.0"` and ImagoKit `"0.6.1"..<"1.0.0"`, against HyperSpy 2.4.0 and
exSpy 0.3.2 / 7185a4d1. macOS 15 and later.

Live:
- **EDX**: the line table, element identification (the published identification loop, `ElementProposer`), net counts, the EDS fit with
  sum and escape peaks, Cliff-Lorimer, zeta and cross-section quantification with the absorption iteration, per pixel over a spectrum
  image, k-factor import, sigma on wt% and at%, the per-region result.
- **EELS**: t/lambda thickness, zero-loss alignment, power-law extrapolation, Fourier-log, Fourier-ratio and Richardson-Lucy
  deconvolution, the edge model fit (joint, or per-edge windows with a 1σ per edge intensity) on 383 bundled K, L and M edges, the MLLS
  fit, composition in at% and wt%, region sums.
- **SpectroCore**: line-profile pooling, display smoothing, sparse regions.

Every quantification says `validation: "none"` until a standard of known composition is measured. Parity row by row: `docs/parity.md`;
timings against Python: `docs/benchmarks.md`; what is open: `docs/open-items.md`; fixtures and their generators: `Tests/Fixtures/README.md`.

Tests: the fast targets run per change (`swift test -c release --parallel --skip SpectroKitParityTests`); the pinned Python comparisons
(golden baseline, exSpy/HyperSpy/pyEELSMODEL pins, the planted EDX runs) are `SpectroKitParityTests`, run in CI on every push and before a tag.
