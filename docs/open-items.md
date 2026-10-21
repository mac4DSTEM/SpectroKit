# Open items

Slowest against Python first (diagnose before changing a number, `../CLAUDE.md`).

1. **t/lambda with a fixed threshold is 2x slower than HyperSpy at 64 x 64 x 2048** (9.1 ms against 4.5 ms, `docs/benchmarks.md`). Hypothesis
   to test, not yet tested: the per-pixel pairwise sums (bit-faithful to NumPy, required by the pins) and the zero-loss-centre argmax run single-threaded,
   while NumPy sums the axis in one vectorised call. Cheapest experiment: parallelise the pixel loop over chunks as `EDXQuantification.quantifyMaps` does
   (the numbers cannot change: pixels are independent); refuted if the typical size does not drop below 4.5 ms. The estimated-threshold route is already 5x faster.
2. **Benchmarks missing**: EDX fit and auto ID on a Velox spectrum image, EELS power-law background fit, edge quantification, and every large size (nightly).
3. **EDX fit accuracy on real Al alloys** (Mg K alpha about 300 counts low, Si 8.7 % low, sigma 5 to 12 % small; Mg missed in 37 of 38 Al-Mg-Si files):
   needs the pure-Al standard from Paul; nothing is diagnosed without it. The old registered finding (offset and gain trade off on lines that span little of the axis,
   `AxisGateTests.testE3RefinementRecoversPlantedOffsetAndGain`) stays a known issue.
4. **EELS model fit** (study row 4): multi-edge K and L with the dft GOS tables, fine structure, low-loss convolution, `quantify`; then Fourier-log, zero-loss alignment, Kramers-Kronig.
   Its own large session; the 0.8.0 session did not start it.
5. **EDS calibration and operations**: `rebin`, `get_calibration_from`, `calibrate_xray_lines`, public window parameters (`line_width`, `windows_width`,
   `integration_window_factor`), free/fix of line parameters, `vacuum_mask` threshold and closing (a mask is an input now).
6. **App-side `@testable` reach**: `PooledQuantificationInput` keeps `axis`, `method`, `metadata`, `regionName`, `pixelCount` as `package`; the apps that need the pooled path still
   reach them. The neutral per-pixel API (`EDXQuantification`) does not.
7. **Validation**: every quantification stays `validation: "none"` until a standard of known composition is measured.
