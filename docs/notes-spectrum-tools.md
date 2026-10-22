# Notes for the merge: SpectroKit 0.10.0, spectrum tools

For the session that merges CHANGELOG.md, docs/parity.md, docs/status.md, docs/open-items.md and README.md. This slice touched none of them
(nor Package.swift). Shared-file edit: `MaskTransport.clippedArea` went from `private` to `package` (one word) so the sparse transport reuses it.

## New files

- `Sources/SpectroCore/Spectroscopy/SpectrumLineProfile.swift`, `SpectrumSmoothing.swift`; `Sources/SpectroCore/Registration/SparseMaskTransport.swift`.
- Tests: `Tests/SpectroCoreTests/{SpectrumLineProfileTests,SpectrumSmoothingTests,SparseMaskTransportTests}.swift` (20 tests, fast);
  `Tests/SpectroKitParityTests/SpectrumToolsPinsTests.swift` (6 pinned tests), `BenchmarkSparseRegionsTests.swift` (runs only with `SPECTRO_BENCH_SPARSE=1`).
- Pins: `tools/spectrum-tools/pins.py` (two parts, one per venv; seed 20261022; asserts scikit-image 0.26.0, HyperSpy 2.4.0, SciPy 1.18.1, NumPy 2.5.4;
  a second run is byte-identical), fixtures `Tests/SpectroCoreTests/Fixtures/spectrum-tools-{lineprofile,smoothing}-pins.json` beside `registration-pins.json`.

## New public names (all in SpectroCore)

`SpectrumLineProfile` (`compute(image:path:width:spacing:weighting:reduction:)`, fields `arcLengths rows columns spectra pixelCounts weightSums reduction weighting width spacing pathLength stepCount`),
`PixelPosition`, `LineProfileWeighting` (`.hard`, `.bilinear`), `LineProfileReduction` (`.sum`, `.mean`), `SpectrumLineProfileError`;
`SpectrumSmoothing` (`.savitzkyGolay(window:order:edge:)`, `.gaussian(sigma:truncate:boundary:)`, `.movingAverage(width:boundary:)`; `validate()`, `smooth([Double])`, `smooth([UInt64])`,
`smooth(spectra:)`, `smoothBatch(_:spectrumLength:)`, `smoothedSpectra(of:)`), `SpectrumBoundary` (`reflect mirror nearest wrap constant(Double)`), `SavitzkyGolayEdge` (`.polynomialFit`, `.extend(_)`), `SpectrumSmoothingError`;
`SparseRegion` (`init(pixelIndices:)`, `init(runs:)`, `init(mask:)`, `Run`), `TransportedRegions` (+ `Entry`; `includedPixels(region:)`, `region(_:)`, `dense(region:)`, `storageBytes`),
`MaskTransport.regions(_:registration:)`, `PoolBuilder.pools(image:transported:names:kind:validation:)` (the `TransportedRegions` overload).

## CHANGELOG bullets (0.10.0, spectrum tools)

- SpectroCore: `SpectrumLineProfile.compute` pools a spectrum image along a polyline of given width, one spectrum per step of arc length (hard pixel membership by default, `.bilinear` as scikit-image `profile_line(order=1)`), with per-step pixel counts, weights, arc length and sum or mean. Hard membership equals `profile_line(order=0)` exactly where the geometries coincide; bilinear equals `profile_line(order=1)` to 2.4e-15.
- SpectroCore: `SpectrumSmoothing`, smoothing for display only (never for a fit): Savitzky-Golay (SciPy `savgol_filter` and HyperSpy `smooth_savitzky_golay`, all edge modes), Gaussian (`gaussian_filter1d`, sigma in channels, truncate 4) and moving average (`uniform_filter1d`), on one spectrum, a list, or a whole image in one parallel call. Agreement 5.8e-13 (Savitzky-Golay), 3e-15 (others).
- SpectroCore: `MaskTransport.regions(...)`, the sparse transport for many regions (scan-pixel indices or runs per region), equal to the dense transport of each region (overlap and footprints bit for bit), with `PoolBuilder.pools(image:transported:...)`. 300 regions on a 512 x 512 grid: 0.11 s and 5 MB against 0.70 s and 600 MB for the dense `transport(labels:)`.

## parity.md rows (columns as in the file: function | state | note)

Change the `MaskTransport`/`PoolBuilder` row note by appending: `; sparse form MaskTransport.regions equal to the dense transport of each region (overlap, footprints exact; inside-grid area 1e-12), SparseMaskTransportTests`.
Add:

| Line-profile pooling (`SpectrumLineProfile`, hard) | pinned | scikit-image 0.26.0 `measure.profile_line(order=0, linewidth=w)` on axis-parallel lines, odd width on a pixel line and even width on a half-pixel line: exact (gap 0); oblique, polyline, fractional and off-grid paths pinned to a NumPy transcription of the kit's geometry (gap 0); `SpectrumToolsPinsTests` |
| Line-profile pooling (`.bilinear`) | pinned | `profile_line(order=1, linewidth=w)`, integer width, oblique line inside the image, `spacing = length / (n - 1)`: 2.4e-15 relative (bound 1e-12) |
| Savitzky-Golay smoothing (`SpectrumSmoothing.savitzkyGolay`) | pinned | `scipy.signal.savgol_filter(x, w, p, mode)` for interp, mirror, nearest, constant, wrap and HyperSpy 2.4.0 `smooth_savitzky_golay`: 5.8e-13 relative (bound 1e-9, SciPy `assert_allclose` default rtol is 1e-7); derivatives not offered; not bit for bit (unlike the EELS threshold derivative) |
| Gaussian smoothing | pinned | `scipy.ndimage.gaussian_filter1d(sigma, truncate=4, mode)` all five modes: 8e-16 relative |
| Moving average | pinned | `scipy.ndimage.uniform_filter1d(size, mode)` all five modes, odd and even sizes: 2.9e-15 relative |
| Sparse region transport (`MaskTransport.regions`) | regression tested | equals the dense `transport(mask:)` of each region: overlap, footprints, reports, pooled spectra exact; also against `registration-pins.json` (2e-12) |

## open-items.md

In item 4 delete "a sparse `MaskTransport.regions(...)` for large region sets". Add (one line, optional): "Line profile: weighting by partial pixel coverage (area) instead of hard membership is not offered; the hard cells overlap-free partition but a corner's inner side has a gap of at most a pixel."

## Deviations and decisions

- Line profile is not a copy of `profile_line`: hard membership (a pixel is in or out by its centre) is the default as specified; `.bilinear` is the `profile_line(order=1)` semantics. Even `width` on a pixel-centred line is a tie the two conventions resolve differently (kit: signed offset in [-w/2, +w/2), so w=2 on a pixel row pools the rows at offsets -1 and 0); they coincide on a half-pixel line. Not pinned against skimage there.
- Corners: a pixel goes to the nearest point of the polyline (round join on the outside of a corner); every pixel is pooled at most once (a partition into cells of `spacing`), so a sharp inner corner can leave a small gap. Pixels beyond the two end points are not pooled.
- Smoothing is in SpectroCore, with its own Savitzky-Golay (hat-matrix of the polynomial fit, dgelsd), not a reuse of `SpectroEELS/SavitzkyGolay.swift`: that file is `package` in SpectroEELS (SpectroEDX does not depend on it) and implements the first-derivative path bit for bit. Derivative order, `delta`, and even windows are not offered. SpectroEELS' file is unchanged.
- Smoothing refuses a non-finite sample, and a `.polynomialFit` window longer than the spectrum (SciPy raises too).
- `TransportedRegions.dense(region:)` fills `insideGrid` only at the touched pixels; the sparse form computes the inside-scan area per touched pixel by one clip against the scan's parallelogram (equal to the dense sum to 1e-12; the edge flag threshold is 1e-6). Everything else is the dense arithmetic in the dense order.
- Sparse regions are independent (like `PoolBuilder.pool(scanMask:...)`), not a partition like `transport(labels:)`; no tie or `labels` logic. `PooledSpectrum.mask` stays a dense `[Bool]` per pool (type unchanged), so 300 pools hold 300 x w x h bools (78 MB at 512 x 512).
- A `SpectrumImage` that is not `DenseSpectrumImage`/`SparseSpectrumImage` is read through `sum(mask:)` per pixel in the line profile (correct, slow); `smoothedSpectra(of:)` refuses it.

## Measured

Line profile: hard vs skimage order 0 gap 0.0 (9 lines, widths 1 to 6); bilinear vs order 1 2.4e-15 relative (5 lines); hard vs NumPy transcription gap 0.0 (5 paths). Smoothing: SciPy Savitzky-Golay 5.8e-13 relative over 6 window/order pairs x 5 modes x 2 spectra; HyperSpy `smooth_savitzky_golay` same; Gaussian 8.2e-16; moving average 2.9e-15.
Sparse speed (Mac, 18 cores, release, `SPECTRO_BENCH_SPARSE=1 swift test -c release --filter BenchmarkSparseRegionsTests`; scan and spectrum grids 512 x 512, rotation 0.02 rad, 300 disjoint 25 x 34 blocks, best of 3): sparse 0.111 s, 5.1 MB result, peak resident 129 MB (42 MB at start); dense `transport(labels:classCount: 300)` 0.696 s, 600 MB overlap, peak resident 1924 MB. 6.3x faster and a ~90x smaller result. The sparse path runs the regions on all cores, the dense one single-threaded, so the ratio is not a per-core one. Under `tools/memcap.sh` the dense path needs about 2 GB.

## Migration

None: everything is new API. `MaskTransport.clippedArea` is `package` (not visible to consumers). Bump with the other 0.10.0 slices (minor, new API only).
