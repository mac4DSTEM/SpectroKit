# Open items

Slowest against Python first. Diagnose before changing a number: state the cause and what would refute it, run the cheap experiment first.

1. **t/lambda with a fixed threshold is 2x slower than HyperSpy at 64 x 64 x 2048** (9.1 ms against 4.5 ms, `docs/benchmarks.md`). Hypothesis
   to test, not yet tested: the per-pixel pairwise sums (bit-faithful to NumPy, required by the pins) and the zero-loss-centre argmax run single-threaded,
   while NumPy sums the axis in one vectorised call. Cheapest experiment: parallelise the pixel loop over chunks as `EDXQuantification.quantifyMaps` does
   (the numbers cannot change: pixels are independent); refuted if the typical size does not drop below 4.5 ms. The estimated-threshold route is already 5x faster.
2. **Benchmarks missing**: EDX fit and auto ID on a Velox spectrum image, EELS power-law background fit, edge quantification, and every large size (nightly).
3. **EDX fit accuracy on real Al alloys** (Mg K alpha about 300 counts low, Si K alpha 20 % low on the simulated recipe-A pool, sigma 5 to 12 % small; Mg missed in 37 of 38 Al-Mg-Si files).
   The Si number is counted against the whole planted Si K alpha peak, the sample line plus the detector Si internal-fluorescence peak at the same
   energy, because that is what exSpy measures (one Gaussian per line, no internal-fluorescence term); against the sample line alone it is 10 %, and the
   absorption-truth test reported 8.7 % before it counted the internal fluorescence. The opt-in `.countsAboveEdge` reference shape would take the
   internal-fluorescence counts out; it is not measured per detector yet. The bias
   is diagnosed on the Al matrix of a real Al-Mg-Si map (the in-situ standard: pixels whose Mg and Si are below L_D), not on a pure-Al file. The known finding (offset and gain trade off on lines that span little of the axis,
   `AxisGateTests.testE3RefinementRecoversPlantedOffsetAndGain`) stays a known issue.
4. **EELS, what 0.9.0 left**: fine structure and a free onset energy in the model fit; Kramers-Kronig; counting sigma on the fitted intensities of the joint fit (the per-edge windows have it since 0.12.0) and on at% / wt%; the model fit on real data (no validation yet, badge `validation: "none"`); `power_law_extrapolation` on an unbinned axis (exSpy's Simpson branch is a factor two off the exact power law, not offered). Richardson-Lucy and the MLLS fit landed in 0.10.0; still open there: a Metal or FFT path for Richardson-Lucy at 64 x 64 x 2048 and more (the direct convolutions take 1.1 s for 32 x 32 x 2048 at 15 iterations on the Mac, about 4.4 s for 64 x 64), weighted MLLS (Poisson weights; the unweighted standard errors overstate the background's by 7x on the pinned spectrum), MLLS with a free onset or fine structure (shares the fine-structure item), and the MLLS and Richardson-Lucy on real data (badge `validation: "none"`). Line profile: weighting by partial pixel coverage (area) instead of hard membership is not offered; the hard cells overlap-free partition but a corner's inner side has a gap of at most a pixel.
5. **EDS calibration and operations**: `rebin`, `get_calibration_from`, `calibrate_xray_lines`, public window parameters (`line_width`, `windows_width`,
   `integration_window_factor`), free/fix of line parameters, `vacuum_mask` threshold and closing (a mask is an input now).
6. **App-side `@testable` reach**, done: 0.9.0 opened the window, segment, candidate and proposal-result initialisers and the `PooledQuantificationInput` fields (`axis`, `method`, `metadata`, `regionName`, `pixelCount` are public); the computed or typed k (`PooledQuantification.kFactors`), the line energy (`Row.lineEnergyKeV`) and the take-off angle (`EDXQuantification.takeOffDegrees`) are public since 0.8.2; the next release opens `UnlistedLineCheck.Candidate`, `.Move` and `UnlistedLineCheck.init` (SpectroKit#13).
7. **Validation**: every quantification stays `validation: "none"` until a standard of known composition is measured.
8. **EDS 0.10.0 asks, what is open**: the sum/escape model's pile-up coefficient is one number for the whole spectrum and the parents are the alpha lines of the strongest groups (family lines such as Kb are not parents); a real detector's escape fraction depends on energy, the common fraction is a first model. It is not tested on real data and has no standard: it needs one measured spectrum with a known sum peak (a thick pure Cu or Fe sample at a high rate) before the badge can change. `PooledQuantification.plotModel` includes the peaks, but the proposer and the unlisted-line check still use their own pile-up columns and do not know the model's.
9. **Sigma on wt% and at%**: the thickness sigma, the dose and the detector are not in the per-spectrum `quantifyWithSigma` (the pooled quantification has the thickness term); a per-pixel sigma map is not provided.
10. **k-factor import**: the table is taken in exSpy's convention (C_A/C_B = k_A/k_B I_A/I_B); a vendor table in the inverse convention is the caller's to invert. A real Velox export has not been read (none in the data folder); the layouts are the ones the task named.
11. **Auto ID, what 0.11.0 left**: the identification loop finds every true element on the three files; open: the method's
   overlap check (an element whose every peak sits under a modelled one leaves no residual peak and is not reported; the method reports
   such finds as possible only), Mn on the Al alloys (proposed at 22 and 70 L_D, a 6xxx minor element by the numbers, the alloy's
   specification not yet known), the line shape beside a dominant K line (the tail, opt-in in `LineTail`, to be measured per detector on the Al matrix and
   switched on by the consumer); the proposer's own axis refinement with a two-line guard (the app refines on its K picks today); the downward family rule
   (a K pick of Z ≥ 30 shows its L line) is in, opt-in (`ProposerPolicy.downwardFamilyMinimumZ`), and stays off until a run on the three files
   (Ge on the FIB lamella is the case) shows it keeps every true element; the uncorroborated tier is `ProposalResult.uncorroborated`; the self-pair half
   bound on sum peaks waits for planted sums that respect it; `AxisGateTests`' known issue (offset and gain trade off
   on lines that span little of the axis) stands.
