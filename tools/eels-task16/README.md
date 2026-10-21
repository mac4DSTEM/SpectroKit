# tools/eels-task16: exSpy / HyperSpy pins for EELS task 16, sections 2, 3 and 4

Written before the Swift code, so the Mac session that implements `docs/design/eels-task-16.md` starts with numbers.
Covers zero-loss alignment and mask (design section 2), power-law extrapolation and Hanning taper (section 3), Fourier-log,
Fourier-ratio and `optimal_fft_size` (section 4). Not covered: GOS tables, the edge model fit (section 6), Richardson-Lucy.

```
python -m venv v && v/bin/pip install hyperspy==2.4.0 exspy==0.3.2      # the design's pins; NumPy 2.5.4, SciPy 1.18.1 were used
v/bin/python -I -B tools/eels-task16/pins.py                             # --out DIR to write elsewhere
```
The script asserts the two versions. Output: `Tests/SpectroEELSTests/Fixtures/eels16-pins.json` (the layout is the script's
docstring) and 58 `eels16-*.f64` arrays (float64 little-endian, C order, NaN kept; shape and sha256 under `files` in the JSON), 2.8 MB.
A second run is byte-identical (sha256 over all files checked). HyperSpy ran without numba (non-accelerated paths).
The pins use exSpy 0.3.2 from PyPI, not the `7185a4d1` checkout the older EELS pins use; the design note names 0.3.2.

## Inputs (all synthetic, deterministic, images are 3 x 4 pixels, pixel p = row * 4 + col)

- **Alignment**: low loss 600 ch, -20 eV + 0.1 k; ZLP FWHM 0.9 eV at a per-pixel centre (global 0.37 eV plus -1.46 .. +1.43 eV,
  none on a channel), plasmon at 15 eV, power-law tail. A second image with a spike larger than the ZLP at 12 eV, and a core-loss-like
  image (300 ch, 100 eV + 0.5 k) for `also_align`. Truth: the planted centres.
- **Power law**: A in 4e5 .. 3e12, r in -0.4 .. 4 (one pixel r < 0 for `fix_neg_r`), 200 ch from 300 eV at 0.5 eV, binned and unbinned.
- **Plural scattering**: ZLP at 0 eV (FWHM 0.9), single-scattering shape S (peaks 12 and 24 eV), t/lambda 0.1 .. 1.1 per pixel,
  I0 = 1e6, 1600 ch from -20 eV at 0.1 eV: J = I0 ifft(fft(Z/I0) exp(fft(S)/I0)) on an 8192 circular grid, cropped. Core loss: a
  step-plus-exponential edge convolved with J/I0, 300 ch from 280 eV. Truth: S, S broadened by the ZLP, the edge.

## Findings the port must know

1. **`max_shift` is not tested here** (a no-op in `estimate_shift1D`, as the design says). `estimateShift` pins `estimate_shift1D`
   with reference pixel 0, `number_of_interpolation_points` 0, 5 and 9, two windows.
2. **A navigation mask given as an ndarray must have shape (nx, ny)**, the reverse of the data's (ny, nx), or exSpy raises; the pins pass it
   as a signal (`BaseSignal(mask).T`), which is what the kit's `PixelMask` (row-major ny x nx) means. Masked pixels give NaN centres.
3. **`align_zero_loss_peak` without `signal_range` on a spectrum with a spike** above the ZLP aligns on the spike (offset -32.0 eV, case
   `spike-no-range`); with `signal_range=(-5, 5)` it does not. Both are pinned as exSpy behaves.
4. **`shiftPasses`** hold the shift arrays `shift1D` received, in order: pass 1 is the coarse shift (`mean(zlpc) - zlpc`), pass 2 the
   `align1D` subpixel shift (absent with `subpixel=False`; four entries with `also_align`, one per signal per pass).
5. **Fourier-log returns S x Z/I0, not S**: `z * log(j/z)` is the single-scattering distribution broadened by the ZLP. Against that
   truth the interior (outside the tapered channels) agrees to 5.6e-4 of the peak; the planted-truth test must compare with `plural-single-broadened`.
   It needs the spectrum to decay inside the axis: with a truncated plural tail (first try) the error was 20 %.
6. **Fourier-ratio carries a factor 1/scale**: exSpy's Gaussian is a density per eV (A = 1), so the result is the edge smoothed by the
   Gaussian times 1/scale (10 here). The interior of `fr-fixed-threshold-6` equals smoothed truth / scale to 3 %. The port reproduces
   exSpy, not the physics (parity row note).
7. **Taper default**: `channels = max(20, round(0.02 n))`: 20 for every n < 1250, 40 at n = 2000, 100 at n = 5000 (cases `default-n*`).
8. **`power_law_extrapolation` `fix_neg_r`** zeroes A where r <= 0: the JSON has `A` (estimate) and `AUsed`. A, r come from
   `PowerLaw.estimate_parameters` on the zero-extended signal, so they depend on the window only, not on the extrapolation size (checked).

## Not pinned here (left to the implementing session)

`estimate_peak_width` on pathological spectra (not exactly two roots gives NaN; only the planted ZLP is pinned, in `fwhmAllPixelsEV`
and each Fourier-ratio case's `fwhmEV`); `richardson_lucy_deconvolution`; the lazy (dask) code paths; Poisson-noisy inputs (the old
slices' noisy pins hold counting statistics; deconvolution of noisy data is dominated by the `log`/division in Fourier space and is
not a useful agreement test).
