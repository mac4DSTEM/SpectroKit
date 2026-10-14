# tools/eels-thickness: truth and pins for EELS slice 1 (the t/λ thickness map)

Written before any Swift code, as `docs/eels-slice-1-registration.md` sections 4 and 5 fix them. Two generators, one
fixture directory, `Tests/SpectroEELSTests/Fixtures/` (written before the `SpectroEELS` target existed; `SpectroEELSTests` reads it).

**Agreement with exSpy is not truth.** `pins.json` is what exSpy 7185a4d1 answers; a port that equals it is a port, not a
measurement. The truth is `planted-truth.json`, made by `make_planted.py` from NumPy alone, with no exSpy, HyperSpy or SciPy
in it. The two answer different gates (registration section 7: gate 1 against the pins, gates 2 and 3 against the truth).
Nothing here makes a thickness validated: `validation: "none"` stays until a sample of known thickness is measured.

## Run

```
python3 tools/eels-thickness/make_planted.py          # NumPy only (the suite uses References/exspy-venv/bin/python -I)
References/exspy-venv/bin/python -I tools/eels-thickness/pins.py
```

Both take `--out`/`--fixtures` to write elsewhere (the reproducibility check does). `pins.py` needs the pinned exSpy checkout
(`References/exspy-7185a4d1`, gitignored, not installed: it is put first on `sys.path` and `exspy.signals.EELSSpectrum` is built
directly from the data, `EELSSpectrum(sig.data, axes=sig.axes_manager._get_axes_dicts(), metadata=sig.metadata.as_dictionary())`,
because HyperSpy's loader does not know exSpy's signal classes). Run `make_planted.py` first: `pins.py` reads its images and checks
their sha256 against their headers. Both are byte-reproducible: every output is identical on a second run (sha256 compared).
Floats in the JSON are Python `repr`s, the shortest string that reads back as the identical float64; `NaN` is written `null`.

## What is in the fixture directory

| file | made by | what |
|---|---|---|
| `planted-noiseless.f64` / `.json` | make_planted | 10 spectra, a 2 × 5 image, shape (2, 5, 3400), float64 little-endian, C order (rows, cols, channels), pixel index = row · 5 + col |
| `planted-noisy.f64` / `.json` | make_planted | the same, `numpy.random.default_rng(20261014).poisson(noiseless)` once on the whole array |
| `planted-truth.json` | make_planted | τ per pixel; per fixed threshold the log-ratio the planted components imply and its bias; the same bias for every channel of the default search range (`biasByChannel`); the sum-based value for the record |
| `exspy-linescan-ll.f64` / `.json` | pins | exSpy's `EELS_LL_linescan_simulated_thickness_variation.hspy`, 17 spectra × 1024 channels, stored as shape (1, 17, 1024) |
| `exspy-linescan-zlp.f64` / `.json` | pins | its zero-loss twin |
| `pins.json` | pins | everything exSpy answers (below) |

Each `.json` header gives shape, dtype, byte order, axis offset/scale/size/units/binned, the microscope parameters where known,
the byte count and sha256 of the raw file, and provenance. The line-scan headers also carry the sha256 of the source `.hspy`
(taken from the pinned checkout), exSpy's licence and the planted t/λ `numpy.arange(0.3, 2, 0.1)` as exSpy's tests write it.
The line scan is **exSpy's GPL-3.0-or-later test data** (Copyright 2007-2026 The eXSpy developers), re-encoded as raw float64 and
copied with attribution as a fixture of SpectroKit (GPL-3.0); it is the one third-party datum in the directory (`NOTICE`
already names exSpy).

## make_planted.py: the planted spectra (section 5.1)

Axis −10 eV + 0.05 eV · k, k = 0 … 3399 (−10 to 159.95 eV), binned counts, the 0 eV channel k = 200. The zero-loss peak is a
Gaussian at 0 eV, σ = 0.25 eV, **normalised to unit sum** (the registration does not say; it makes I_0 = N e^(−τ) exactly).
S(E) is the Drude loss function E Γ E_p² / ((E² − E_p²)² + (E Γ)²) for E > 0 (strict), E_p = 15.0 eV, Γ = 0.8 eV, unit sum over
the axis. Plural scattering by Poisson statistics, I = N Σ_n e^(−τ) τⁿ/n! · (Z ⊛ S^⊛n), N = 10⁶.

**How the convolution is aligned.** Z is an array on the channel grid (index k ↔ E = −10 + 0.05 k). S is held as a *loss-origin*
array S0 (index j ↔ a loss of j · 0.05 eV, S0[0] = 0, j = 0 … 3199, S0[3200:] = 0); S0^⊛n is S0 convolved n times, kept to j < 3400
(a loss of 3400 channels or more can never land on the axis); S0^⊛0 is a unit impulse at j = 0, so the n = 0 term is Z itself. The
n-th term is the plain discrete convolution `term_n[m] = Σ_k Z[k] · S0^⊛n[m − k]`, the first 3400 outputs, with no shift: its
energy is E_k + loss_j = (k − 200) · 0.05 + j · 0.05 = (m − 200) · 0.05 = E_m. So the zero-loss peak stays at 0 eV and S^⊛n lands at
its losses. What falls past channel 3399 (≥ 160 eV) is lost; Z and S0 have unit sum, so the loss of term n is `1 − sum(term_n)`.
The convolutions are explicit loops of NumPy vector adds (no BLAS, no FFT), deterministic. The image is stored as `zl + inel`
(`zl` = the n = 0 term, `inel` = the sum of the n ≥ 1 terms added in order). The sum over n stops before the first term n > 0
whose summed in-range intensity is below 1e-14 of the running total (the registration says "the first term below 1e-14 of the
total": here a term means its summed intensity on the axis, not its Poisson weight; the terms past n = 13 are almost wholly
scattered beyond 160 eV, so the spectrum is the same to 1e-13 relative). n_max per τ and the Poisson weight left out are in the
truth file.

**The bias, from the components.** For a fixed threshold θ the method sums the channels with E < θ (index `ind` = (θ + 10)/0.05 =
250, 290, 320 for 2.5, 4.5, 6.0 eV; the channel at θ is not in the sum) and takes ln(I_t / I_0) with I_t the sum of all
channels. The truth file gives, per pixel and θ, the zero-loss intensity, the zero-loss intensity at or above θ, the inelastic
intensity below θ, the intensity lost beyond the axis, and from them I_0 = (Z_0 − zero-loss above) + inelastic below,
I_t = (planted total) − lost, the log-ratio and its bias against τ. These are summed with `math.fsum` from the components and not
by running the method on the stored spectrum; the noiseless sum-based value (`np.sum` of the stored spectrum, the same ln) is
written next to it and the two agree to 5.6e-16 (asserted < 1e-12). The bias is the method's own and is negative here: the
plasmon intensity below θ is counted in I_0, and the Drude tail beyond the axis is missing from I_t; the zero-loss peak above θ
(positive) is about 1e-23 of the zero-loss intensity at 2.5 eV and about 1e-6 of it at 1.2 eV.

**`biasByChannel` (an addition to the registration).** The estimated threshold is exSpy's rule on the data and the generator does
not know it, so the truth file also holds, per pixel, the bias for every `ind` = 220 … 419, the channels
[value2index(1 eV), value2index(11 eV)) of the default search window. A port that finds channel c for a pixel looks up
`biasByChannel.bias[c − 220]`; then gate 2 is as tight for the estimated threshold as for the fixed ones.

## pins.py: what exSpy answers (section 4)

For each case (planted noiseless, planted noisy, exSpy's line scan; the line scan is the only one with a zero-loss spectrum),
per pixel in row-major order:

- `estimated`: exSpy's `estimate_elastic_scattering_threshold()` at its defaults (window 10, tol None, window_length 5,
  polynomial_order 3, start 1): the energy it returns, the **channel** exSpy turns that into (`value2index`), the index of the
  inflexion in the sub-range, I_0, I_t, t/λ; the global `tol`; the sub-range; each pixel's minimum |derivative|; `stability`
  (below); `recipe` (below).
- `estimatedGradient`: the same with `window_length = 0` (HyperSpy's `derivative`).
- `fixed`: thresholds 2.5, 4.5, 6.0 eV: channel, I_0, I_t, t/λ.
- `zeroLoss`: the zero-loss route (line scan only): I_0 = the sum of the twin spectrum, t/λ.
- `absoluteThickness`: ρ 2.70 g/cm³, E0 200 keV, α 10, β 20 mrad (set on the planted images with
  `set_microscope_parameters`; the line scan carries them), for every route above: with density and λ = 120 nm
  (`thicknessNMDensityAndLambda`), with density only (`thicknessNMDensityOnly`, λ from Iakoubovskii), with λ only
  (`thicknessNMLambdaOnly`, no density, no correction), and the λ (143.488… nm) and angular correction (1.0634…) used.
  Order of arithmetic: `(t/λ · correction) · λ`.
- `stepByStep`: for one pixel (planted (1, 1), line scan (0, 8)), the cropped energy axis, the Savitzky–Golay derivative and the
  `numpy.gradient` derivative on the cropped range, the minimum, the global tol, the first sub-range index at or below tol, the
  threshold and its channel.
- `iMFP`: `iMFP_Iakoubovskii` on ρ (1, 2.7, 7.9, 19.3) × E0 (60, 80, 120, 200, 300) and `iMFP_angular_correction` on that ×
  α (1, 10, 30) × β (5, 20, 100): 20 and 180 values, `[…inputs, value]` rows.
- `rules`: the rules below in words with file:line; `diagnostics`: not pins (below).

Agreement required of the port (registration section 4): the same threshold channel for every pixel; I_0 and I_t relative
≤ 1e-12; t/λ absolute ≤ 1e-12; λ and the correction relative ≤ 1e-13. A difference is a failure of the port, never a tolerance
to widen.

### The rules the port needs (HyperSpy 2.4.0, `References/exspy-venv/lib/python3.14/site-packages/hyperspy/…`)

**value → channel** (`axes.py:1283-1349`, `UniformDataAxis.value2index`, the default `rounding=round`):
`q = (value − offset)/scale`; `index = (1/1e12) · trunc(q · 1e12)` (`axes.py:1315-1318`: a *multiply* by 1e-12 of the
truncated value); then, for `value ≥ 0` (positive scale; the test is on the *energy*, not the index), round half *towards zero*
(`ceil(index − 0.5)`: a half goes down, 289.5 → 289; `misc/_array_tools.py:457`), for `value < 0` round half *away from zero*
(`floor(index + 0.5)`: a half goes up; `_array_tools.py:535`), both reached through `misc/array_tools.py:42`
(`axes.py:1320-1327`). A result outside 0 ≤ index < size raises `ValueError` (`axes.py:1344-1349`). The truncation to 12 decimals
makes a value within 1e-12 channels of a half-way point count as exactly half-way. `pins.py` ports this in pure Python
(`rule_value2index`) and checks it against HyperSpy's own on 54 000 values of the planted axis and 30 240 of the line-scan axis
(every channel energy, every half-way energy, those nudged by ±1e-13 and ±1e-9, 20 000 RNG values): 0 mismatches.

**sub-range** (`axes.py:648-691`, `value_range_to_indices`, called at `exspy/signals/_eels.py:712`): `i1 = value2index(v1)` only
if `low < v1 ≤ high`, else 0; `i2 = value2index(v2)` only if `high > v2 ≥ low`, else `size − 1` (`axes.py:667, 676-679`). The crop is
`isig[i1:i2]` with integers, so channels `[i1, i2)`, end exclusive; with the defaults `[value2index(1.0), value2index(11.0))` =
[220, 420) on the planted axis (1.0 … 10.95 eV, 200 channels) and [202, 222) on the line scan (1.0 … 10.5 eV, 20 channels). If `v2`
is at or above the last channel's energy the crop ends at `size − 1`, so the last channel is not in it. `i2 < i1 + 10` raises
(`_eels.py:713-714`).

**fixed threshold, `isig[:θ]`** (`exspy/signals/_eels.py:598`, `axes.py:401-471` `_get_array_slices`, stop at `:453-466`):
stop = `value2index(θ)` (above), end exclusive, so I_0 is the sum of channels `[0, value2index(θ))`; the channel nearest θ is
not in it. If `value2index` raises because θ is above the last energy the slice runs to the end (I_0 = I_t, `axes.py:462-466`);
θ below the first energy raises `IndexError` (`:457-461`); θ exactly at the last energy gives stop = `size − 1`. For the
registered 2.5, 4.5, 6.0 eV the channels are 250, 290, 320 (planted) and 205, 209, 212 (line scan).

**estimated threshold, per pixel** (`_eels.py:608-621`): NaN gives NaN; else `ind = axis.value2index(threshold)` and
`I_0 = data[:ind].sum()` (numpy pairwise sum of the float64 channels `[0, ind)`; `pins.py` asserts exSpy's I_0 equals exactly
that for every pixel, and the same for the fixed routes). Out-of-range raises here, it is not caught. Simpson's rule for an
unbinned axis is not ported. I_t is the sum of all channels (`_eels.py:805`, `hyperspy/signal.py:5092-5132`).

**tol and the threshold** (`_eels.py:725-736`): `tol = max over pixels of (min over the cropped channels of |d|)`, one number for
the image; `inflexion = argmax(|d| ≤ tol)` per pixel (the first such channel); `threshold = cropped_axis[inflexion]` with
`cropped_axis[i] = offset_c + scale · i`, `offset_c = (offset + scale · arange(size))[i1]` (`axes.py` `_slice_me` and
`update_axis`; `pins.py` asserts it), so the energy can differ from the full-axis value by an ulp (1.9500000000000002 eV on the
noisy image); `inflexion == 0` gives NaN. The channel exSpy then uses is `value2index(threshold)` = `i1 + inflexion`, asserted for
every pixel.

**Savitzky–Golay** (`_eels.py:717-722`, `_signals/signal1d.py:933-941`): `scipy.signal.savgol_filter(row, 5, 3, deriv=1,
delta=axis.scale)` with SciPy's default `mode='interp'` on the *cropped* rows. Reproducing it bit for bit: the coefficients are
`scipy.signal.savgol_coeffs(5, 3, deriv=1, delta=scale)`, five doubles that are *not* exactly (1, −8, 0, 8, −1)/(12 · scale)
(the centre one is −8.3e-15), written into `pins.json` under `recipe`. On this machine (Apple Silicon, SciPy's compiled
convolution with fused multiply-add) the interior values are reproduced **bit for bit** by a convolution
chain `acc = 0; for j in (0, 4, 3, 2, 1): acc = fma(f[i + 2 − j], coeffs[j], acc)`; `pins.py` checks it on every interior value
(4192 values over the three cases, 0 mismatches; a record, not an assertion, since another CPU or build may not fuse). The two
channels at each end of the cropped range are a cubic fit (`numpy.polyfit`, LAPACK least squares) evaluated for the derivative
(`scipy/signal/_savitzky_golay.py` `_fit_edge`): a port reproduces them to rounding (about 1e-12), not bit for bit.

**`window_length = 0`** (`_eels.py:723-724`, `hyperspy/signal.py:4846-4853`): `numpy.gradient(cropped, cropped_axis, axis=-1)`,
`edge_order = 1`. Rebuilt in plain IEEE arithmetic in `pins.py` (`gradient_recipe`, asserted bit-exact on all three cases,
`numpy/lib/_function_base_impl.py:1265-1357`): `dx = diff(x)`; if every `dx` is equal the spacing is a scalar and the interior is
`(f[i+1] − f[i−1])/(2 dx)` (the line scan, scale 0.5); otherwise with `dx1 = dx[i−1]`, `dx2 = dx[i]`, `a = −dx2/(dx1(dx1+dx2))`,
`b = (dx2 − dx1)/(dx1 dx2)`, `c = dx1/(dx2(dx1+dx2))`, `out[i] = a f[i−1] + b f[i] + c f[i+1]` left to right without fusing (the
planted axis, scale 0.05, whose spacings differ by ulps); the edges `(f[1] − f[0])/dx[0]` and `(f[−1] − f[−2])/dx[−1]`.

**ratio and thickness** (`_eels.py:817-851`): `t/λ = log(I_t/I_0)`; with a density `t/λ *= iMFP_angular_correction(...)` then
`λ =` the given or `iMFP_Iakoubovskii(density, beam_energy)`, then `t = (t/λ) · λ`; with λ and no density `t = (t/λ) · λ` and no
correction.

### `stability`: which pinned channels can flip on rounding

The pinned channel is the first with `|d| ≤ tol`. `stability` gives, per pixel, the margins `tol − |d|` at the pinned channel and
`min |d before it| − tol`, and lists the **sensitive pixels**: those with a margin within 2 · 1e-12 of the image's largest |d|, or
(`tolTie`) when the two largest per-pixel minima are that close. For a sensitive pixel the channel is decided by rounding of the
derivative. On integer counts this is routine: the 5-point Savitzky–Golay derivative of integers takes values k · 5/3 (delta 0.05),
so many channels sit mathematically *on* tol = 5/3 and only the rounding of SciPy's arithmetic says which side. **On the noisy
image 7 of 10 estimated-threshold pixels (0, 2, 3, 5, 6, 8, 9) and all 10 gradient-route pixels are sensitive**; the noiseless image
and the line scan have none (margins of 0.006 or more against ε at most 1.4e-8). Those noisy pins are reproducible only with the bit-exact
recipe above (interior channels) and are not evidence of a wrong port when they differ.

### `diagnostics`: not pins

How the routes compare with the planted truth, so the gates are known to be satisfiable before the port exists: the error against
τ per pixel and route; for the fixed routes the largest difference between exSpy's error and the generator's predicted bias on the
noiseless image (≤ 5.6e-16: the generator and exSpy agree to rounding); and `gate3Preview`: |t/λ_noisy − t/λ_noiseless| / σ_counting
per pixel and route, with the pixels above 4. For the estimated threshold it is **7.4 at the worst pixel (pixels 7 and 9 exceed 4)**,
for every fixed threshold at most 2.01: see the findings below.

## Findings while writing these (the registration is not amended here; these are for its amendment)

1. **Gate 3 as registered cannot hold for the estimated threshold.** With the estimated threshold the noisy image's thresholds
   differ from the noiseless ones (noiseless 1.2 to 1.35 eV; noisy 1.3 to 8.65 eV, because the global `tol` is set by the noisiest
   pixel), so |t/λ_noisy − t/λ_noiseless| is a threshold effect, not counting noise: 6.2 σ_counting at the τ = 1.3 pixel and 7.4 σ_counting
   at τ = 2.0 (gate: ≤ 4). Over 200 noise realisations (NumPy seeds 1 to 200, run once with exSpy, not stored) the standard
   deviation of the estimated-route t/λ is 1.08, 0.99, 1.47, 1.61, 2.22, 2.19, …, 3.21 times σ_counting (gate: within 15 %), and the
   threshold is NaN in 2 of 200 realisations at τ = 1.0, 1.6 and 2.0. With the fixed thresholds 2.5, 4.5, 6.0 eV both clauses
   hold: at most 2.01 σ per pixel on the stored noisy image, and standard deviations within 8.3 % of σ_counting for every τ. So gate 3
   should name the fixed thresholds (the counting-statistics claim is about I_0 and I_t at a given threshold, which is what σ
   describes); the estimated route's noise behaviour is a separate, honest finding about the method.
2. **The noisy image's estimated-threshold pins are decided by rounding** (see `stability`): reproducible only with the bit-exact
   Savitzky–Golay and gradient recipes above, which are for the interior of the cropped range only.
3. **`biasByChannel`** is an addition so that gate 2 can be exact for the estimated threshold too (the registration wanted "every
   pixel and route" but the generator cannot know the estimated channel).
4. The registration does not say how the zero-loss peak is normalised (here: unit sum) or what "a term below 1e-14 of the total"
   measures (here: the term's summed in-range intensity); neither changes any number at the 1e-13 level.
5. The planted images have no zero-loss twin, so the zero-loss route is pinned on the line scan only ("where a zero-loss spectrum
   exists").
6. A threshold the user passes for the fixed route is rounded by the rule above, so 4.52 eV and 4.5 eV give the same channel
   (290); a port that floors or truncates instead is wrong by up to one channel.
