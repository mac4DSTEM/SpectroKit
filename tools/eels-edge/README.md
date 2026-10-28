# tools/eels-edge: truth and pins for EELS slice 2 (power-law background, C K areal density)

Written before the Swift code, as the EELS slice 2 design note (archived in the suite's private folder) sections 3.3, 4 and 5 fix them. Four scripts:

| script | needs | writes |
|---|---|---|
| `extract_gos.py` (h5py) | `References/gos-dft-1.5.0.gosh` (md5 checked), exSpy's `eels_binding_energies.json` | `Sources/SpectroEELS/Resources/GOS/dft-gos-tables.bin` (231 tables, float32 as stored, gos[iEnergy][iQ] as exSpy's `np.squeeze(gos.T)`) and `dft-gos-index.json` |
| `pins.py --sigma-only` (phase A) | exSpy venv | `edge-sigma-CK.f64/.json`: exSpy's `function(E)` for C K, 200 keV / 10 / 20 mrad, 0.25 eV, E = 150 + 0.25 k, 2040 channels |
| `make_planted.py` (NumPy only) | phase A's fixture, slice 1's `planted-noiseless.f64` | `edge-{core,low}-{ss,ps03,ps07,ps13}-{noiseless,noisy}.f64`, `edge-planted.json` (manifest), `edge-planted-truth.json`; and the R set: `edge-{core,low}-R-*.f64`, `edge-planted-R.json`, `edge-planted-truth-R.json` |
| `pins.py` (phase B) | everything above, pinned exSpy / pyEELSMODEL / HyperSpy | `edge-pins.json` (14.8 MB) |

## Run (order matters)

```
../References/python/hyperspy/bin/python -I -B tools/eels-edge/extract_gos.py
../References/python/hyperspy/bin/python -I -B tools/eels-edge/pins.py --sigma-only
../References/python/hyperspy/bin/python -I -B tools/eels-edge/make_planted.py      # any Python with NumPy
../References/python/hyperspy/bin/python -I -B tools/eels-edge/pins.py
```
All take `--out`/`--fixtures` to write elsewhere. Every output is byte-identical on a second run (checked by sha256, see the
lead's report). `pins.py` records the script's own sha256, both GOS md5s, commits and versions.
Each phase-B fixture is checked against its manifest sha256 before use.

The agreement of exSpy with the port is agreement, not truth: the truth is `edge-planted-truth.json` (NumPy only; the one
thing taken from exSpy is the cross-section SHAPE, so this truth tests background, windows and ratio, not the GOS).

## Units (get this right)

1 barn = 1e-10 nm^2. `function(E)` is barn/eV; per channel sigma_ch = function(E) * scale (barn). Edge counts per channel =
`I_low * n[atoms/nm^2] * sigma_ch[barn] * 1e-10`. The ratio: `n = I_k * 1e10 / (I_low * sigma_k)`.
(The registration's text in section 5, "n_true * I_low * sigma(E) * scale", leaves the 1e-10 implicit.)

## Layout of the fixtures

Core-loss images shape (3, 5, 2000), low-loss (3, 5, 3400), float64 little-endian C order; row = background
[(1e9, 3.0), (5e8, 2.5), (2e10, 3.5)], column = n_true [2, 5, 10, 20, 50]; pixel p = row * 5 + col. Axes: core
150 + 0.25 k eV; low-loss -10 + 0.05 k eV (slice 1's). Cases: `ss` (low-loss = a delta of 1e7 at 0 eV), `ps03/07/13`
(slice 1's planted low-loss pixels of tau 0.3 / 0.7 / 1.3, normalised to their own total, scaled to a total of 1e7).
Noisy copies: `default_rng(20261015)`, per case poisson(core) then poisson(low). One manifest (`edge-planted.json`) instead of a
`.json` sidecar per `.f64` (32 sidecars would be clutter). `edge-planted-truth.json`: per case, per window, per Delta, per
pixel: iLow, ikEdge, ibTrue, ibEst, nPredicted, bias (and its background and edge parts), the I_0 route for 2.5/4.5/6.0 eV, plus the
two-area estimate's I1, I2, r, A computed from the components.

## Readings made (the registration is silent)

1. **Channel bin.** E_k is the LEFT edge of channel k (bin [E_k, E_k + 0.25)); `--bin centre` gives the centred bin. HyperSpy's
   two-area formula treats the sum over [i1, i3) as the integral from x1 to x3, which is the left-edge reading. (Both readings
   give nearly the same bias, see Findings; the fixtures use `left`.)
2. **Low-loss total.** For the plural-scattering cases the TOTAL low-loss counts are 1e7 (the registration fixes I_0 = 1e7 for
   single scattering only). The single-scattering low-loss is a delta of 1e7 at 0 eV, so I_low(Delta) = I_0 = 1e7 for every Delta.
3. **0.05 -> 0.25 eV mapping.** 0 eV is aligned to the centre of a coarse channel; coarse c = (j - 198) // 5 (exact rebin by 5, mass
   conserved), then a plain convolution on the core-loss grid; the predicted bias uses the same arrays. The sigma fixture
   therefore has 2040 channels (the zero-loss peak's negative-energy tail reaches channels beyond 650 eV).
4. **Grid scale axes.** Phase B's function(E) runs over onset-10 .. onset+160 eV INCLUSIVE: n = round(170/scale) + 1 channels.
   sigma_k = `np.sum(function[i0:i1] * scale)`; windows by HyperSpy's own `isig[onset : onset + Delta]`.
5. **Dirac 4.4 grid** = the full E0 x alpha x beta grid of 4.1, scale 0.25, Delta 50/100/150 (192 values).
6. **I_0 route in the pins/truth** uses fixed thresholds 2.5, 4.5, 6.0 eV (channels [0, value2index(theta)) of the fine low-loss).
7. **pyEELSMODEL** axes run from 150 eV to 750 eV (600 channels at 1.0 eV, 2400 at 0.25 eV) so that O K + 150 eV fits.

## Findings

**1. Registered prediction false: the single-scattering bias is not below 1 %.** (Gate 3 predicted "the bias is below 1 %".)
The bias is absolute (atoms/nm^2) and, for single scattering, independent of n_true: `(I_b,true - I_b,est) * 1e10 / (I_0 sigma_k)`.
Default window, Delta 50, sigma_k = 3850.67 barn, I_0 = 1e7: bias -0.428 (A=1e9, r=3.0), -3.548 (A=5e8, r=2.5), -0.494 (A=2e10, r=3.5)
atoms/nm^2. In units of n_true the 15 pixels read (row by row, n = 2, 5, 10, 20, 50):
-21.4, -8.56, -4.28, -2.14, -0.86 %;  -177.4, -71.0, -35.5, -17.7, -7.1 %;  -24.7, -9.9, -4.9, -2.5, -0.99 %.
So the clause "|n - n_true| / n_true <= 2 % at Delta 50, default window" holds for 2 of 15 pixels only (row 1 and row 3 at n = 50).
Range over all windows and Delta 30-150 (ss): -3.9 to +0.70 atoms/nm^2 (the wide window at Delta 150 is positive: +0.70). Cause: the
edge is tiny against the background. sigma_k = 3850 barn gives 7.7 counts (n = 2) to 192 counts (n = 50) over 50 eV on
a background of 1717 to 15038 counts, and the two-area method's own error is ~0.1 % in the background (r_est = 3.0019 for r = 3: the
midpoint x3 is arithmetic, not geometric, plus the point-for-integral term): a few counts, i.e. a few atoms/nm^2. The bias
scales as 1/I_0 at fixed (A, r) (the edge counts scale with I_0 too, the background does not), so I_0 = 1e9 would put every pixel's
bias at 0.71 % or less for n >= 5 and 1.8 % at n = 2 (worst row), but that is the lead's amendment to write, not mine.
`--bin centre` changes this little (ss default Delta 50: min -3.478, max -0.418 atoms/nm^2 against -3.548 and -0.428 left).

**2. Plural scattering (gate 4), predicted bias of the I_low(Delta) route, default window.** The plural-scattering part of the bias
(`biasEdge`, the same fraction of n_true for every pixel) is, at Delta 50: -7.6 % (tau 0.3), -17.6 % (0.7), -30.7 % (1.3); at Delta
150: -1.6 %, -3.7 %, -7.1 %. The background part (finding 1, slightly changed by I_low) adds to it: total relative bias at Delta 50
for the best pixel (n = 50, row 1): -8.5 %, -18.4 %, -31.6 %; at Delta 150: -2.1 %, -4.2 %, -7.6 %; for n = 2 up to about -3 times n_true.
The I_0 route (theta 4.5 eV) over-estimates instead: n = 50 pixel +23 % (0.3), +63 % (0.7),
+137 % (1.3) at Delta 50: its bias does grow with tau, as the registration says. Prediction holds: Egerton eq. 4.66 is far better
than I_0 at every tau, but it is not unbiased at Delta 50 (the cumulative cross section rising over the window is why).
Edge intensity inside the pre-edge windows from the zero-loss peak's tails: at most 3e-98 of the background, so the plural
cases' pre-edge window sums equal the single-scattering ones.

**3. Check of the generator against HyperSpy.** On the 8 images x 3 windows x 4 Delta x 15 pixels (720 noiseless values) HyperSpy's
`remove_background` + ratio gives n equal to the generator's `nPredicted` to 4.7e-13 of n_true (largest), and the generator's two-area
r, A equal HyperSpy's exactly (relative difference 0.0) with identical i1, i2, i3. So the predicted biases are the method's, to rounding.

**4. pyEELSMODEL against exSpy (gate 2, 3 %).** Over the whole 4.3 grid (C, N, O; Delta 50/100/150; 4 settings): scale 1.0 eV
-2.496 % (N) to +1.066 % (O); scale 0.25 eV -2.352 % (N) to +1.058 % (O). Per edge at 1.0: C -1.10 / +0.60, N -2.50 / +0.22,
O -0.38 / +1.07. The 3 % gate is met by the pins with margin 0.5 %.

**5. Dirac / dft sigma_k, C K** (192 values): 0.9724 to 0.9820 (Delta 50: 0.9747-0.9820; 100: 0.9724-0.9788; 150: 0.9737-0.9796).

**6. A float32 trap in exSpy (important for the port).** The GOSH arrays are float32. exSpy keeps `gos_array`, `qaxis`, `rel_energy_axis`
and `energy_axis` as float32 (NumPy 2 keeps float32 + Python float float32), and `subshell_factor` as a `np.float32`.
`integrateq` therefore evaluates `E = energy_axis[i] + shift`, `E**2 / (4 R T)` etc. as float32 scalar ops, and the final
factor `4 pi a0^2 R^2 / E / T * subshell_factor * 1e28` is a float32 array; only `qint` itself (and everything after the
`searchsorted`/interpolation, which mix float32 data with float64 `qmin`/`qmax`) is float64. Replacing the arrays by their float64
widenings gives `qint` and `function(E)` that differ from exSpy's by up to 1.9e-7 and 1.0e-7 relative. A Double port will
miss the registered 1e-12 / 1e-10 bounds by five orders of magnitude unless it reproduces exSpy's float32 steps in the same places
(or the bounds are amended). The pins hold `tabulatedEnergies` (the float32 axis, widened), `qint`, and for C K 200/10/20 the
`qmin`/`qmax` passed to `get_qaxis_and_gos` per energy (`splineC.integrateq`), to help find the first divergent step.

**7. exSpy quirk, no effect here.** `set_microscope_parameters` re-integrates only if the effective angle changed; an edge object
reused across E0 at alpha = 0 (effective angle = beta) keeps a stale `qint`. The pins make a fresh edge per (edge, E0, alpha, beta).
The effective angle is computed with `GOS.onset_energy` (the table's onset), not the editable onset.

**8. Counting statistics, first set.** The noisy images (seed 20261015) have the edge (7.7 to 192 counts over 50 eV) on 1717 to 15038 background counts: the
ss default-window Delta-50 n of the 15 noisy pixels runs from -141.7 to +138.3 atoms/nm^2 for n_true 2-50 (sigma_n ~ 36-130 atoms/nm^2). The first set stays as registered; the
realistic set below is the one the bias and noise gates can meaningfully use.

## The second, realistic set (R): n_true 200, 500, 1000, 2000, 5000 atoms/nm^2 (a ~2-50 nm carbon film)

Added by the lead's decision (to be amended into the registration). Same (A, r) rows, axes, I_0 = 1e7, low-loss and cases; seed 20261016.
Files: `edge-{core,low}-R-{ss,ps03,ps07,ps13}-{noiseless,noisy}.f64`, manifest `edge-planted-R.json`, truth in a SEPARATE file
`edge-planted-truth-R.json` (same structure as the first set's), pins under the new key `plantedR` of `edge-pins.json` (same structure as `planted`,
plus `varIk` and `sigmaN` per Delta in both sets). The first set's `.f64` files are byte-identical to before; its manifest and truth JSON lost their
`generatorSha256` field (a script hash in a fixture changes whenever the script does; `edge-pins.json` records the script's sha256 instead).
Both sets are produced by one run of `make_planted.py` and `pins.py`; every `edge-*` file is identical on a second run.

**R1. Single-scattering bias (gate 3), predicted from the components.** The absolute bias is unchanged (-0.428 .. -3.548 atoms/nm^2 at Delta 50 default);
relative to n_true, default window, Delta 50, by row (n = 200, 500, 1000, 2000, 5000):
-0.214, -0.086, -0.043, -0.021, -0.009 %;  -1.774, -0.71, -0.355, -0.177, -0.071 %;  -0.247, -0.099, -0.049, -0.025, -0.010 %.
Min/max -1.774 % / -0.0086 %: **"<= 2 % for Delta 50 with the default window" holds at every pixel** (worst: A = 5e8, r = 2.5, n = 200). It holds for all
three windows and every Delta 30-150 too (worst -1.951 %, narrow window, Delta 30; default window: -1.827 % at Delta 30 ... -1.547 % at Delta 150).
The registered "below 1 %" fails at that one pixel only, at Delta 50 default (by 0.8 percentage points).

**R2. Plural scattering (gate 4), I_low(Delta) route, default window, Delta 50**, relative bias (min .. max over the 15 pixels):
tau 0.3: -9.40 % .. -7.64 %;  tau 0.7: -19.35 % .. -17.57 %;  tau 1.3: -32.57 % .. -30.70 %.
Delta 150: -3.12 .. -1.57 %, -5.23 .. -3.68 %, -8.64 .. -7.09 %. Delta 30: -14.0 .. -12.1 %, -26.0 .. -24.0 %, -38.9 .. -36.5 %.
Most of it is the plural-scattering edge-window mismatch (-7.6, -17.6, -30.7 % at Delta 50, identical for every pixel). The I_0 route (theta 4.5 eV)
over-estimates: +22.1 .. +24.5 % (0.3), +60.8 .. +64.3 % (0.7), +134 .. +141 % (1.3) at Delta 50.

**R3. Noisy copies against sigma_n** (registration section 6 first-order estimate; implemented in `pins.py` from each image's own counts:
Var(I_k) = (I_k + I_b) + (dI_b/dI1)^2 I1 + (dI_b/dI2)^2 I2, sigma_n = |n| sqrt(Var/I_k^2 + 1/I_low); dI_b/dI_j analytic through r, k, A and the window
sum of E^-r, checked against a central finite difference: relative difference 9e-11). Default window, Delta 50, z = (n_noisy - n_noiseless) / sigma_n(noisy image):
- ss: sigma_n/n runs from 1.1 % (n = 5000) to 60 % (n = 200, row 2); sigma_n about 39-55 (row 1, 3) and 117-128 (row 2) atoms/nm^2;
  max |z| 1.77, rms z 0.94 over the 15 pixels (with the noiseless image's sigma_n: 1.86, 0.96).
- ps03: max |z| 1.50, rms 0.78; ps07: 2.35, 1.07; ps13: 2.03, 1.09.
- Over all 720 values (4 cases x 3 windows x 4 Delta x 15 pixels): rms z = 1.002, max |z| = 2.79. So the estimate reproduces the realised spread to about 0.2 % in rms,
  and the 4 sigma_n gate holds with margin (largest 2.79). The 200-realisation "std within 15 %" test itself is the Swift side's.
At n_true = 200 sigma_n/n is 20-60 %, so the R set's low densities are noise-limited by design (a 2 nm film at I_0 = 1e7).
