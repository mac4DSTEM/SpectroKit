# EDX stage gates (counts, energy axis, peak identification) and the Mg auto-ID diagnosis (registration)

Registered 2026-10-14 (overnight session), before any SpectroKit code or test for these gates. In force: G-C, G-E, G-P P1 to P3, the planted truth and the Gate D order; P4 waits on the owner's permission (Q4) and the real-data diagnostics of section 9 on the owner's files (Q1). Tier 1: a number a scientist
reads can move (which elements Auto ID proposes; a line area; an axis calibration). Order: suite `ROADMAP.md`, "Cross-repo
order" 4 ("the exSpy stage gates for EDX (counts, energy axis, peak ID) with the Mg auto-ID diagnosis. Then the first
real-truth check: a known standard (the owner's pure-Al foil)"); `docs/history.md`, "Then: the per-stage exSpy gates … which
are also the diagnosis of why Auto ID misses Mg in 37 of 38 Al-Mg-Si files". What is written here is fixed before the code; a
change after code starts is an amendment, dated, with its reason. The background, Cliff-Lorimer, ζ and absorption stages are
NOT in this registration (they follow it; the first real-truth check, the pure-Al foil, is its own later registration).
`validation: "none"` stays on every EDX quantity; nothing here calls anything validated.

**Before this registration** the only runs were Python probes in the session scratchpad (section 11), no SpectroKit code, no
Swift build or test, no real data read beyond HDF5 headers. Their numbers are quoted where they predict an outcome. One
of them is a surrogate of the proposer's test, not the proposer: it is labelled so, and the Swift proposer is what gate P2
and the Gate D experiments run.

## 1. What is made, and what already exists

Three stage gates on the pooled-spectrum path, each against a reference independent of the code under test, and a Gate D
diagnosis of the Mg miss. Nothing in `Sources/` changes unless a gate finds a defect (then a registered fix, separately).

| stage | code under test | what exSpy / HyperSpy offers | the reference used here |
|---|---|---|---|
| counts (G-C) | `SpectrumImage.sum(mask:)`, `windowSums`, `densified`, the Velox stream decode (`VeloxEMDReader`, `SpectrumImageOpener`) | `EDSTEMSpectrum.sum` (`_eds.py:175`), rsciio's `FeiSpectrumStream` (`_emd_velox.py:1057`) | the published test constants of RosettaSciIO, a NumPy decoder, planted streams (section 5.1) |
| energy axis (G-E) | `VeloxEnergyAxis` and `EnergyAxis`, `EnergyAxisRefinement` | `_get_dispersion_offset` (`_emd_velox.py:866`), `value2index` rules (already pinned), `EDSModel.calibrate_energy_axis` (`edsmodel.py:612`) | rsciio, exSpy's calibration on planted shifts, planted truth |
| peak ID (G-P) | `ElementProposer` (`propose`), `LineConflicts`, `ProposalRules`, `XRayLines` | **no automatic identification**: a table lookup (`get_xray_lines_near_energy`, `utils/eds/_xray_lines.py:92`) and HyperSpy's generic `find_peaks1D_ohaver` (`hyperspy/_signals/signal1d.py:1533`) | planted spectra with known elements and areas; exSpy's lookup; `find_peaks1D_ohaver` as an independent eye; DTSA-II's NIST Qual set (section 6, P4) |

Already pinned against exSpy by the 258 moved tests (`Fixtures/eds-pins-exspy-7185a4d1.json`: two exSpy spectra, 792
`value2index` cases, 18 FWHM values, 8 slicings, 4 line selections, the Mn Kα background windows): the window sums, the
integration and background windows with their merge, the Fiori-Newbury width law, the line table, HyperSpy's rounding. These
are not repeated; section 3 says what each stage gate adds to them.

## 2. The reference

exSpy `7185a4d13d7d5c550b7bb8d1e9bd62af9cc4203e`, HyperSpy 2.4.0, NumPy 2.5.4, SciPy 1.18.1, RosettaSciIO 0.14.0
(`References/exspy-venv`, Python 3.14.7, run as `References/exspy-venv/bin/python -I -B`); RosettaSciIO `049e7d70`
(`References/rosettasciio`, the same pin as `tools/velox-metadata-parity`). exSpy is not installed: its checkout is put first on
`sys.path` and the signal classes are built directly (as `tools/eels-thickness/pins.py`). `sparse` is NOT installed in the venv,
so RosettaSciIO's own Velox EDS loader cannot run there (`ModuleNotFoundError`, measured); installing it changes the reference
venv and is the owner's (section 12, Q3). Until then the Velox stream reference is the published constants plus a NumPy decoder
(section 5.1), which reproduces them exactly (measured, section 7).

### What exSpy does and does not offer for peak identification (read at the pin, 2026-10-14)

- exSpy has **no automatic EDS peak identification**. `grep -i peak exspy/signals/_eds*.py` returns nothing; `find_peaks1D_ohaver`
  appears only in an EELS docstring (`_eels.py:692`). The user chooses elements (`add_elements`, `_eds.py:268`), exSpy
  derives lines (`add_lines`, `only_one`, `only_lines`, the overvoltage-2 rule, already pinned) and measures them
  (`get_lines_intensity`, `_eds.py:549`; windows `_eds.py:744-838`; model fit `edsmodel.py`).
- Lookup only: `get_xray_lines_near_energy(energy, width=0.2, only_lines=None)` (`utils/eds/_xray_lines.py:92-135`): every
  table line within ±width/2, sorted by |ΔE|. Around Mg Kα (1.2536 keV) it returns 33 lines (Mg_Ka, Se_Ln, Tb_Mb, Pm_Mg …),
  around Al Kα (α only) 7 (measured). It decides nothing.
- HyperSpy's generic `Signal1D.find_peaks1D_ohaver(slope_thresh=0, amp_thresh=None [10 % of max], medfilt_radius=5, peakgroup=10,
  subchannel=True)` finds positive maxima by derivative zero-crossings (O'Haver). It knows no physics and no noise level.
- Therefore the peak-ID gate is NOT "agreement with exSpy". SpectroKit's Currie-test proposer is its own method (a joint
  non-negative fit, `ElementProposer.swift`); its reference is planted truth, with exSpy's lookup and `find_peaks1D_ohaver`
  as independent checks of position and candidate lines, and DTSA-II's Qual set as a public independent truth. Said in
  every result's footer already ("unvalidated"); unchanged.

## 3. The stage gates, defined

### G-C counts (SpectroCore, SpectroEDX window sums)

- **C1 stream to counts.** `VeloxEMDReader` / `SpectrumImageOpener` decode of an EDS stream equals an independent decode, per
  channel and per pixel: events are the uint16 words other than 65535, 65535 ends a pixel (`_emd_velox.py:1048`,
  `VeloxEMDReader.swift:161`), frames summed within `first..last`. Files: RosettaSciIO's public `fei_SI_EDS-HAADF-4detectors_2frames.emd`
  (4 streams, 256 pixels, 2 frames, 4096 channels: published sums 865236, 913682, 867647, 916174, total 3562739,
  `test_emd_velox.py:463-467`), `velox_emd_version11.zip`, `example_velox_EELS_EDS.emd` (an unterminated last pixel is in it,
  `VeloxEMDReader.swift:339`), `Fixtures/velox-tiny.emd`, and planted streams (5.1). Exact integer equality, no tolerance.
- **C2 sums.** `sum(mask: nil)`, `sum(mask:)` for rectangle/ellipse/arbitrary masks including the empty and full mask, `windowSums`
  and `densified` equal NumPy's sums of the independent decode: exact. Totals above 2^32 per channel (a planted pool of 6e9
  counts) stay exact (`UInt64`; `[Double]` conversion exact below 2^53). exSpy's `sum()` of unsigned 16-bit data is `uint64`
  and does not wrap (measured: 65535 + 65535 + … = 131077 in one channel).
- **C3 what is not carried.** exSpy's `sum` multiplies `live_time` by the navigation size (measured: 2.0 s over 20 pixels
  gives 40.0 s). SpectroKit carries no live time; Velox stores `LiveTime = 0`, `RealTime = 0` for every analytical detector in
  the owner's file (header read, section 9). Counts are raw events: no dead-time, no per-detector gain. Stated, not gated.

### G-E energy axis

- **E1 the file's axis.** `VeloxEnergyAxis` (`VeloxEMDReader.swift:550-558`) equals rsciio's `_get_dispersion_offset`
  (`_emd_velox.py:866-876`: first detector, in file order, whose name CONTAINS `BinaryResult.Detector`; dispersion and offset in eV
  stored, divided by 1000) bit for bit (`Double` bits) on every public Velox file and on planted headers with a decoy detector;
  `energyCalibrationAgrees` is false when the summed segments' calibrations differ (planted: 4 detectors, offsets
  −1000, −1000, −996, −1000 eV). Owner's file header (section 9): Dispersion 20, OffsetEnergy −1932.21348 eV, 4096 bins:
  channel k is `−1.93221348 + 0.020 k` keV, so channel 0 is below zero (the zero-energy peak sits near channel 96.6).
  The convention (channel k = a line's energy at k, not at the bin's lower edge) is rsciio's; if a half channel (10 eV) were
  the truth the Mg result moves (section 8, D2); G-E cannot decide it without a known line on the owner's detector (R1).
- **E2 channel and energy.** `EnergyAxis.index(of:)` and `channelRange` equal HyperSpy's `value2index` / `_get_array_slices` on
  the Velox axis (offset −1.93221348, scale 0.02, size 4096) at every table line energy of Z 5 to 50 (K, L, M families), at
  ±1e-13 around every channel midpoint (ties), at the ends. New pins only for this axis; the rule itself is pinned.
- **E3 calibration recovery (truth, not exSpy).** On planted spectra whose lines are shifted by Δ ∈ {−12, −5, −1, 0, +1, +5,
  +8, +12} eV (an axis-offset error), whose gain is off by g ∈ {−3, 0, +3}e-4, and whose widths follow the Fano law (5.2) at
  R_MnKa ∈ {125, 130, 140, 150} eV: `EnergyAxisRefinement.refine` recovers the planted offset and gain, and the FWHM at
  Al Kα. exSpy's `calibrate_energy_axis("offset"|"scale"|"resolution")` (`edsmodel.py:612-652`) is pinned beside it as a second
  estimate, not as the truth (its algorithm differs: one parameter at a time on alpha lines; the Swift refinement is joint, a
  documented DEVIATION in `EnergyAxisRefinement.swift`). Measured now for exSpy (N_Al = 1e6, ρ_Mg = 0.05, Fano widths,
  range 0.3 to 3 keV): planted shifts 0, +8, −12 eV → offset changed by 0.0, −8.0, +11.9 eV.
- **E4 sensitivity (a measurement, not a gate).** The Mg area from a joint fit as a function of axis error, width error, and
  tail (section 8). It is what makes E3's bounds matter.

### G-P peak identification (the proposer, on planted truth)

- **P1 lookup.** A new `package` function `XRayLines.near(energy:width:onlyLines:)` (a port of `get_xray_lines_near_energy`,
  pure table code) returns exSpy's list, same order including |ΔE| ties (pinned for a grid of 60 energies, widths 0.05, 0.2, 0.5,
  `only_lines` nil and ["a"]). Used by the Gate D tooling to list what can sit under a candidate; it is not a proposer change.
- **P2 planted detection and false alarms.** `ElementProposer.propose` on the planted Al-Mg-Si spectra (5.2). Two designs:
  *single-candidate* (`pool: ["Mg"]`, `settings.elements = [Al, Si]`: the forward step's test of one candidate against the
  settled model), the whole grid; and the *shipped full pool* (default pool, ~20 s a spectrum optimised) on a reduced grid.
  Pass criteria are on the **matched set M** only (the generator uses the model's own width law, line table, in-family continuum,
  no tail, no axis error):
  1. false alarm: at ρ_Mg = 0, Mg is proposed in at most 10 % of 100 realisations at each N_Al (Currie α = 0.05, slack for
     the one-sided test and the flank scaling);
  2. detection: where ρ_Mg·N_Al ≥ 3 L_D(M) (L_D(M) from the noise-free sandwich of the same design), Mg is proposed in at
     least 90 % of 100 realisations;
  3. bias: for those, |net − truth| ≤ 3 σ (the proposer's own σ) averaged over the realisations; the generator takes Kβ
     weights from the table so no planted-vs-model line-ratio difference enters.
  The **mismatched sets** (U widths, S shift, T tail, C continuum; 5.2) have no pass or fail: their results are the diagnosis
  (section 8) and are reported as a table of net/truth and P(proposed). A change of the proposer after seeing them is a new
  registration.
- **P3 independent eye.** `find_peaks1D_ohaver` on the same planted spectra (positions only; reported, no bound). Measured now:
  with its defaults (amp_thresh 10 % of max) it finds only Al Kα in all nine (N_Al, ρ) cells tried; with amp_thresh 0.2 % of max
  and medfilt_radius 3 it finds Mg at ρ ≥ 0.01 for N_Al ≥ 1e6 (within 3 to 7 eV) but also 4 to 10 noise peaks, and at
  ρ = 0.002 reports a peak at 1.2376 to 1.2388 keV (−15 eV): it cannot adjudicate a weak neighbour.
- **P4 public independent truth (conditional).** DTSA-II's QualSpectra (NIST, public domain; 31 EMSA glass spectra with
  `Qual answers.txt`, by difficulty class), already used by mac4DSTEM's WP4b (`tools/autoid-velox-check/qual_prep.py`; recorded
  there: baseline precision 53.9 %, R2 81.3 %, 8 hard-class hits lost). It is not on this Mac. If the owner approves the
  download (Q4), gate: SpectroKit's proposer's per-file candidate lists equal mac4DSTEM's recorded run (a port-parity gate), and
  precision / recall by class are reported against the answers; no pass bar on precision (thresholds are a property of the
  dataset until measured on every dataset they will touch).

## 4. Pins (`tools/edx-stages/pins.py`, written before the Swift tests)

Run as `References/exspy-venv/bin/python -I -B tools/edx-stages/pins.py [--out DIR]`; byte-identical on a second run; records
its own sha256, the pinned commits and versions. Outputs `Tests/.../Fixtures/edx-stages/pins.json` (floats as Python reprs;
big arrays as `.f64` / `.u64` with a manifest sha256, as `tools/eels-edge`):

1. `counts`: for each public file, the NumPy decode's per-stream per-channel sums and per-pixel totals; the published
   constants asserted at generation (the script fails if the decode differs); `sum` dtype and live-time factor of exSpy's
   `EDSTEMSpectrum.sum` on a planted 4 × 5 × 64 uint16 image.
2. `axis`: rsciio's `_get_dispersion_offset` applied to the planted headers (cut out by `ast` from the pinned file, sha256
   asserted, as `tools/velox-metadata-parity/reference.py`); `value2index` / `isig` slicing for the Velox axis at the grid of E2;
   exSpy `calibrate_energy_axis` for the three modes on the planted calibration set (offset, scale, resolution, and the
   resulting `energy_resolution_MnKa`).
3. `lines`: `get_xray_lines_near_energy` outputs (P1); `_get_line_energy(line, FWHM_MnKa)` for Mg_Ka, Al_Ka, Si_Ka at R = 125 to 150;
   `estimate_integration_windows` and `estimate_background_windows` for the planted line lists, merged and unmerged; `get_lines_intensity`
   with and without background windows on each planted spectrum (the window method's own bias, 7.2).
4. `peaks`: `find_peaks1D_ohaver` results (position, height, width) for the P3 settings.

Agreement required: integer counts exact; windows exact; `get_lines_intensity` relative ≤ 1e-12 (sums of integers, one
division); `get_xray_lines_near_energy` list equality; FWHM relative ≤ 1e-14 (already 1e-15 measured in the moved tests).
Nothing is widened to pass.

## 5. Truth (independent of exSpy's quantification; NumPy only, `tools/edx-stages/make_planted.py`, committed with its fixtures first)

### 5.1 Planted Velox streams (counts, axis)

A writer builds Velox-format EMD files with h5py (reference venv `References/python-venv`): `Data/SpectrumStream/<id>/{Data
(uint16 words), FrameLocationTable, Metadata (JSON, column 0), AcquisitionSettings}` and `Data/SpectrumImage/<id>`, from
event lists the generator draws itself, so the truth is the draw, not any reader. Cases: 1 stream (Super-X pre-summed) and 4
streams; 1 and 3 frames; pixel counts including a pixel with 0 events, a pixel with 70000 events in one channel (a uint16
count would wrap), channel 4095 and channel 0; an unterminated last pixel; detector metadata with a decoy, with differing
offsets (E1), with LiveTime 0. Axis: dispersion 20 eV, offset −1932.21348 eV (the owner's header), 4096 channels.

### 5.2 Planted Al-Mg-Si spectra (peak ID, calibration, the Mg diagnosis)

Expected counts per channel on the owner's Super-X axis (E_k = −1.93221348 + 0.02 k keV, k = 0..4095, a channel's mass taken
over [E_k − 0.01, E_k + 0.01)), then Poisson. Line energies from the X-ray Data Booklet, independent of exSpy's table:
Mg Kα 1.2536, Kβ 1.3022; Al Kα 1.4865, Kβ 1.5575; Si Kα 1.7400, Kβ 1.8359 keV; Kβ/Kα area ratios 0.02, 0.013, 0.02 (the
model's table has 0.01, 0.0132, 0.02779: a real mismatch, kept in the unmatched sets).

- **Areas.** N_Al = Al (Kα + Kβ) counts ∈ {1e4, 1e5, 1e6, 1e7} (the owner's whole-map pool is of the order 1e7: 1.4e6 pixels × 10.8 to
  18.7 counts × 0.7 Al Kα, `edx-dossier-2026-10-05.md` §counts); Mg = ρ_Mg N_Al with ρ_Mg ∈ {0, 0.001, 0.002, 0.005, 0.01, 0.02,
  0.05}; Si = 0.01 N_Al. (Al-Mg-Si 6xxx: Mg of 0.5 to 1 wt % puts the Mg Kα / Al Kα counts ratio of the order 0.005 to 0.01 before
  absorption; stated as an estimate, not a measurement; Q2.)
- **Widths.** Matched set M: the Fiori-Newbury law the model uses (exSpy `get_FWHM_at_Energy`, 72.7 / 76.6 / 80.6 eV at Mg / Al / Si for
  R_MnKa = 130). Unmatched set U: the Fano law FWHM² = 2.3548² (σ_n² + ε F E), ε = 3.76 eV, F = 0.11, σ_n² set so FWHM(Mn Kα) =
  R_MnKa: 79.0 / 82.3 / 85.8 eV at R = 130 (+8.7 %, +7.4 %, +6.5 %): physical and independent of the model's law. R_MnKa ∈ {125, 130, 140, 150}.
- **Continuum.** Kramers (E0 − E)/E, E0 = 200 keV, times a detector/window roll-off 1 − exp(−(E/0.30 keV)^2.5), scaled so its raw
  sum in ±1 FWHM around Mg Kα is ρ_c = 0.0008 of the Al window (set by a total of 0.03 N_Al over 0.2 to 20 keV) and, in the
  second family, ρ_c = 0.008 (0.3 N_Al). The owner's raw Mg/Al window ratio of 0.002 (median over his files, `autoid-velox-check` line 64;
  its definition is not committed in `tools/autoid-velox-check`) is an upper bound on ρ_c + the true Mg: the small family is
  the one consistent with it. Set C (continuum mismatch) replaces the roll-off by 1 − exp(−(E/0.5)^2.4) (the shape the
  Continuum.swift comment says orders (9,5) were tuned against) and, separately, adds an Al K absorption step of 8 %.
- **Misfit sets.** S: all lines shifted by Δ eV, Δ ∈ {−10, −5, −3, −2, −1, 0, +1, +2, +3, +5, +10} (the model keeps the file axis).
  T: an exponential incomplete-charge shelf below Al Kα (e-folding 0.15 keV) of 0, 1, 2, 5 % of the line area. U: above. Also
  a +0.5 channel (10 eV) set (the half-channel convention, E1). Also O Kα at 0.003 N_Al and Ar via the Al + Al pile-up
  (2.9730 keV) at 1e-3 N_Al, so the sum-peak conflict path is exercised.
- **Calibration set (E3):** as above with Δ, gain g, and R_MnKa.
- Seeds: `numpy.random.default_rng(20261017)`, one stream per (set, cell), realisations 1..100 (grid) or 1..5 (full pool).
  The generator writes the truth areas (Mg, Al, Si, O, Ar) per spectrum to `edx-planted-truth.json`.

## 6. Uncertainty

Counting statistics only for the planted spectra (Poisson; the truth areas are exact). For a proposer run the registered
uncertainty is the proposer's own σ and Currie L_C, L_D (α = β = 0.05; σ0 from the LS sandwich with the candidate absent, times the
flank-misfit factor). Its limits, said with it: L_D assumes a correct model; every misfit in section 8 enters as a bias the
reported σ does not contain except through the flank factor. The planted Fano law is one plausible truth, not a measurement of
the owner's detector (R1 measures it).

## 7. Measured now (before code; Python probes, section 11) and predicted outcomes

7.1 **Counts.** The NumPy decode of `fei_SI_EDS-HAADF-4detectors_2frames.emd` gives 916174 / 867647 / 913682 / 865236 events for
SuperXG21 / G22 / G24 / G23 and 3562739 in all (512 pixel markers = 2 frames × 256 pixels): equal to the published constants.
*Predicted:* C1, C2 met exactly (the moved tests already cover the readers; the gate adds the planted extremes).

7.2 **The window method's own bias (exSpy windows, Mg, Al, Si lines at R = 130 on the Velox axis, planted set U, 200 realisations).**
The default windows merge to `[1.0355, 1.1082, 1.901, 1.9816]` for Al, `[1.0355, 1.1082, 1.6397, 1.7163]` for Mg: Mg's right
background window (1.6397 to 1.7163) overlaps Si Kα's integration window (1.6591 to 1.8203). Mg net at ρ_Mg = 0 (mean ± sd):
−12.5 ± 13.6 (N_Al 1e4), −127 ± 39 (1e5), −1300 ± 136 (1e6), −12 893 ± 409 (1e7): a bias of −1.3e-3 N_Al that grows with N and, at
a 2 % Al tail, +2.2e-3 N_Al (+21 816 ± 480 at 1e7). Equivalent ρ_Mg of 0.0013 to 0.0022: the same size as the owner's 0.002. Above
N_Al ≈ 1e5 the window method's floor is a bias, not noise.

7.3 **Proposer-like fit, Python surrogate (not an oracle).** One candidate (Mg) against {Al, Si}, the same design family as
`ElementProposer` (Kramers × Bernstein (9,5) split at 1.5596 keV, 0.2 to 20 keV, the table's Kβ weights and Fiori-Newbury widths at 130 eV,
unweighted NNLS, σ0 from the LS sandwich with the candidate absent, flank-misfit factor, Currie L_D = 2.71 + 4.65 σ0). Omitted: escape
peaks, sum columns, the other 90 candidates. Noise-free, N_Al = 1e7, Mg net / truth (matched, shift ±1 to ±5 eV and width rows at ρ_c = 0.0008;
the ±10 eV, Fano and tail rows were measured at ρ_c = 0.008, in-family continuum for the tail; the P2 runs repeat all at both):

| planted vs model | ρ_Mg = 0.002 | ρ_Mg = 0.01 |
|---|---|---|
| matched (M) | 1.00 | 0.98 |
| axis shift +1 / +2 / +3 / +5 eV | 0.43 / 0.00 / 0.00 / 0.00 | 0.87 / 0.71 / 0.54 / 0.15 |
| axis shift +10 / −10 eV | 0.00 / 0.00 | 0.00 / 0.00 |
| Al width ×1.01 / 1.02 / 1.04 / 1.06 | 0.55 / 0.00 / 0.00 / 0.00 | 0.89 / 0.77 / 0.52 / 0.28 |
| Fano widths (U, +7 % at Al) | 0.00 | 0.39 |
| Al tail 2 % (matched widths, in-family continuum) | 0.14 | 0.81 |

Scanning the model's R_MnKa against Fano-planted data (N_Al 1e7, ρ_Mg 0.002, truth 20 000): Mg net 0 at R 120 to 130, 46 395 at 135 (the
RSS minimum), 68 595 at 138, 70 377 at 140; iterated-WLS 12 732 / 21 491 / 34 566: the estimate swings by a factor of 3 over ±5 eV of R.
Noisy, 20 seeds, set U, N_Al 1e7, ρ_c = 0.0008: net 9 681 ± 568 at ρ_Mg = 0.01 (truth 100 000), L_D = 90 708 (flank factor 41), P(net ≥ L_D) = 0;
0 at 0.002; 387 045 vs 500 000 at 0.05 with P = 1. At 1e6: net 980, L_D 9 096, P = 0 at 0.01; at 1e5: net 97, L_D 930, P = 0.
With ρ_c = 0.008: 1e7, ρ_Mg = 0.01: net 39 129, L_D 47 449, P = 0; 0.05: P = 1. **The detection limit in ρ_Mg does not improve
with counts: about 0.01 to 0.05 at every N_Al**, set by the Al Kα misfit, whereas the matched-model L_D at N_Al = 1e7 is 2.2e3 counts
(a Mg/Al counts ratio of 2.2e-4, of the order 0.02 wt % Mg before absorption).

*Predicted for P2 (stated as predictions with their refutation, section 8):* matched set M passes its three criteria; the mismatched
sets reproduce the table above within the Swift proposer's differences (escapes, sums, pool): net/truth within ±0.25 of the surrogate's
for the noise-free cells, P(proposed) 0 for ρ_Mg ≤ 0.01 at N_Al = 1e7 on set U, 1 at 0.05.
*Predicted for E3:* exSpy offset recovery within ±0.2 eV of the planted shift at N_Al ≥ 1e6 (measured ±0.1 eV at 1e6, ρ 0.05); the Swift
refinement within 1 eV for offset and 1e-4 relative for gain (NOT measured; it may fail, and then it is a finding).

## 8. The Mg diagnosis (Gate D: diagnosis, refuting observation, predicted outcome, written; then run)

**The finding as recorded.** mac4DSTEM `docs/archive/v5/autoid-velox-check-2026-10-07.md:64` (also `wp4-autoid-velox-preregistration-2026-10-07.md:7`,
`docs/open-items.md:315`): "Mg | 37 | 38 | net 0 in the fit (36 below L_C); the raw Mg Kα / Al Kα window ratio has a median of 0.002: at
most a trace in the pooled spectrum. Not shown to be a proposer fault; check by hand on one Al-Mg-Si file." Setting: `tools/autoid-velox-check/run.sh`,
each `SI *.emd` pooled whole map (`source.sum(mask: nil)`), `ElementProposer` as `runAutoID` runs it, `FitSettings.standard`, no listed
elements, the file's axis and beam, **Mn Kα resolution fixed at 130 eV, no axis refinement**, built from mac4DSTEM seam commit `77088f52`,
112 `.emd` files found, 88 scored, 78 distinct; files on `/Volumes/PL_SSD_2TB/NAS_Backup/01_projects`. H4 (Mg on the Mg-richest 1 % of pixels:
10 of 19 files against 0 of 19 on the whole map, `wp4-autoid-results-2026-10-07.md:125`) is selection-biased by its own account (`:15`) and carries no mechanism.
**A discrepancy to settle first:** the table's "37 of 38" is files whose Velox list holds Mg, of the 78 distinct; 26 of those 78 are
Al-Mg-Si (`autoid-velox-check:29`); `open-items.md:315` says "37 of 38 Al-Mg-Si files". Which 38 files, and which are Al-Mg-Si, is not recoverable
from the repo (Q1). The words "a pooling fault, not a proposer fault" were never tested.

**Facts that bound the explanations (arithmetic and header reads, not experiments).** Mg Kα to Al Kα is 233.0 eV = 3.2 FWHM at Mg (Fiori-Newbury,
R = 130: 72.7 eV); two Gaussians 3.2 FWHM apart overlap at e^−28: the line overlap itself is excluded as a cause by arithmetic. Mg Kα
sits at no pile-up energy of Al, Si, O (lowest sums: O + O 1.05, Al + Al 2.973 keV). The model's continuum edge (1.5596 keV) coincides with Al Kβ (1.5596 keV).
The matched-model counting limit at N_Al = 1e7 is L_D = 2.2e3 counts (7.3): an Mg/Al counts ratio of 2.2e-4, so a 6xxx matrix with 0.3 to 1
wt % Mg would be found with a margin of 20 to 50 times by counting statistics alone IF the model were right. The recorded non-detection
therefore points either at a model misfit that eats the Mg line or at Mg far below its nominal level in the pooled spectrum.

Hypotheses, in the order they are run (cheapest and most informative first). Each: the refuting observation, the experiment, the predicted outcome.

**D0 (the pool / pruning interplay).** The 90 other candidates' collinear columns (Ga L, Na K, Zn L) prune Mg at L_C in the backward step although a
single test would pass. *Refuted if* the single-candidate run (`pool: ["Mg"]`, current {Al, Si}) gives Mg net and a proposal outcome different
from the full pool's by more than 10 % of the net or by a decision, on the planted cells. *Experiment:* P2 both designs on the same spectra.
*Predicted:* the same Mg net (0 or the surrogate's) in both; D0 refuted (the surrogate is a single-candidate test and already gives net 0 at ρ = 0.002).

**D1 (Al Kα width mismatch leaks into Mg through the unweighted LS).** The model's line shapes follow Fiori-Newbury at a fixed 130 eV;
a real detector differs by a few percent; at N_Al ≈ 1e7 the residual of the dominant Al Kα (a few percent of 1e5 counts per channel) outweighs
the Mg line (tens to hundreds per channel), the NNLS sets Mg to 0, and the flank-misfit factor then multiplies σ0 by 20 to 40. *Refuted if*
on set U (Fano widths, +7 % at Al) at N_Al = 1e7, ρ_Mg = 0.01 the Swift proposer's Mg net is within ±20 % of the truth and Mg is proposed in at least 90 % of
realisations. *Experiment:* P2 on U and the R_MnKa scan (E4). *Predicted:* net/truth 0.39 noise-free (0.10 with noise and ρ_c = 0.0008), P(proposed) = 0 for ρ_Mg ≤ 0.01, flank factor 20 to 41.
A real-data observation that decides it (R1): the pooled Al Kα (and Si Kα) fitted with a Gaussian plus local linear background has FWHM within ±1 % of
Fiori-Newbury at the file's 130 eV and a centroid within ±0.5 eV of the table: then D1 and D2 are refuted for that file (the surrogate loses 45 % of Mg at 1 %).

**D2 (axis error: offset, gain, or the half channel).** *Refuted if* on set S a shift of ±3 eV leaves Mg net within ±20 % of the truth, or if on the
owner's data the Al Kα and Si Kα centroids are within ±0.5 eV of 1.4865 and 1.7400 keV and equal to within 0.5 eV in offset and gain terms. *Experiment:* S and the
half-channel set; then `EnergyAxisRefinement` first, proposer second, on the same cells (the refined axis is `AxisRefinementResult.refinedAxis`).
*Predicted:* net/truth 0.54 at +3 eV, 0.15 at +5 eV, 0 at ±10 eV (ρ_Mg = 0.01, noise-free); after refinement the planted cells recover to within ±30 % of the truth for
N_Al ≥ 1e6 on set M's widths and stay biased on set U (width law). Not measured for the Swift refinement.

**D3 (Al Kα incomplete-charge tail).** The code's own note (`Continuum.swift`, `weakLineBiasNote`) attributes the −300 counts weak-line bias to the tail
"unmodelled until the owner's pure-Al reference spectrum is supplied" (the bias there is for Al ≈ 3e5; the surrogate's scaling is proportional to the line, not
constant). *Refuted if* on set T a 2 % tail does not change Mg net by more than 10 % at ρ_Mg = 0.01, N_Al = 1e7 (predicted 0.81 of the matched result; 0.14 at ρ = 0.002).
*Experiment:* T at 0, 1, 2, 5 %; then with the tail supplied as a reference shape (`ReferenceShapes`, exists) to see how much is recovered (the code's note: −300 to +35 at 3e5).
It becomes decidable on real data only with the pure-Al foil (the later registration).

**D4 (too little Mg in the pooled spectrum, i.e. the recorded explanation).** *Refuted if* the planted spectra with a model that is right (set M) show detection at the level that
Mg/Al ratio 0.002 to 0.01 would deliver (they do, by 20 to 50 times), AND the owner's alloy is nominally at 0.3 wt % Mg or more, AND the real pooled
spectrum's Al Kα misfit (R1) is small. It stands only if D1, D2 and D3 are refuted on the real data and the alloy's Mg is nominally below about 0.05 wt % (Q2), or the foil is thick enough to absorb the Mg Kα
(Mg Kα is the weakest transmitted line in the set: its transmission is the first thing to compute from the thickness).
*Predicted:* D4 alone cannot explain a miss at 1e7 counts for a nominal 6xxx composition.

**D5 (the window method for the maps, a separate fault).** exSpy's default windows for {Al, Mg, Si} overlap each other (7.2) and carry an Al-tail-sensitive bias of the order of the owner's 0.002:
the Elements and maps window for Mg is biased the same way. *Refuted if* the SpectroKit window net for Mg at ρ_Mg = 0 is within ±2 sd of zero at 1e6 (exSpy's is −9.6 sd). *Predicted:* equals exSpy's (the
window code is a port); the bias is the method's, so the map and the proposer disagree about Mg for different reasons.

**D6 (real data, a registered diagnostic, never a gate).** *R1:* per pooled spectrum, the Al Kα and Si Kα centroid (eV from the table) and FWHM (against Fiori-Newbury at 130 eV), a Gaussian + local linear
background. *R2:* the Swift proposer on that file with the file's axis, and with `EnergyAxisRefinement` first. *R3:* the held-out selection control H4 lacked: select the Mg-richest 1 % of pixels from the
EVEN frames' Mg window counts and test Mg on the ODD frames (frames are in the stream: `FrameLocationTable`); under no clustering the odd-frame Mg falls to the control level, under real clustering it stays. Needs the files (Q1). *Predicted:* if D1/D2 hold, R2's refined axis finds Mg in more files than the file axis (counting
to be recorded against 0 of 38); if R3's odd-frame Mg stays above its control, Mg is real and clustered and the whole-map miss is a pooling effect AND a misfit one.

**What would end the diagnosis.** The Mg miss is *explained* when the Swift proposer on matched planted data detects what it should (P2 M), on mismatched data loses Mg by the mechanism with the registered size
(D1 to D3 within ±25 % of the table above), and a real file's R1/R2 measurements put the real Al Kα misfit inside the range that mechanism needs. It is *not* explained, and reported so, if the Swift proposer on U/S/T
keeps Mg where the surrogate loses it: then the surrogate is wrong about the proposer (the prediction fails), D1 to D3 fall, and D4/D6 are what remain.
The diagnosis does not change any code; whether to fix (a weighted or Poisson screening fit, a free Al Kα width, refine-then-propose, a tail reference) is a separate registration after the numbers exist (Q5).

## 9. Real data (diagnostic only; never a gate; no file is copied or committed)

- The owner's Al-Mg-Si files are **not on this Mac**. The mac4DSTEM run read `/Volumes/PL_SSD_2TB/NAS_Backup/01_projects` (not mounted now). `$MACEM_DATA/stem-edx/`
  holds one file: `SI HAADF 1456 77000 x 20260420.emd` (the manifest: SpectroKit's Velox reader; the dossier calls it Rh/SiO₂, 1739 MB, not Al-Mg-Si).
  `$MACEM_DATA/standards/` is empty (the pure-Al foil is not there yet). `mac4DSTEM/References/demo-edx` holds the synthetic Al-Mg-Si cube and ladder (planted Al, Mg, Si, O, Cu; truth JSON), a
  further independent planted truth for P2, unchanged since 2026-10-06 and read-only.
- Header of `SI HAADF 1456 …emd` (HDF5 attributes and the stream's column-0 JSON only; no event data read): Velox 9, one stream `SuperXG1` = SuperXG11 to G14 with identical Dispersion 20 and
  OffsetEnergy −1932.21348 eV, `bincount` 4096, uint16 stream, 1024 × 1024 raster, 1607 frames, `LiveTime` and `RealTime` 0, 200 kV, XFEG. Taken as the template for the planted axis.
- Per file used later a manifest line goes in `data/README.md` (name, technique, instrument, date, "SpectroKit EDX stage diagnostics"); numbers cited with their log.

## 10. What is not claimed

Agreement with exSpy's windows, lines and calibration, and recovery of planted areas on a matched model, do not make an EDX number right on a real specimen. Peak identification here is a statistical test of a model, not
a validated identification; the thresholds are registered conventions (Currie α = β = 0.05). The Fano width law, the continuum roll-off and the tail are plausible stand-ins. The surrogate of section 7.3 is not
the proposer and proves nothing about it until the Swift runs. The 37-of-38 count is taken from the record, unverified. `validation: "none"` on everything.

## 11. Pre-registration probes (`tools/edx-stages/probes/`, Python, committed with this registration)

`probe1.py` (planted generator, exSpy windows and FWHM), `probe2.py` (7.2), `probe3.py` / `probe4.py` / `probe5.py` / `probe6.py` / `probe11.py` / `probe14.py` (the surrogate, 7.3), `probe7.py` (P3, P1 lookup), `probe8.py` (E3 for exSpy),
`probe9.py` (exSpy `sum`), `probe10.py` (raw window ratios), `probe12.py` / `probe13.py` (rsciio loader; fails without `sparse`), the inline NumPy decode of the 4-detector file (7.1). Run with `References/exspy-venv/bin/python -I -B`.
Not yet run: any Swift code, `tools/edx-stages/pins.py`, `make_planted.py`, the writer of 5.1.

## 12. Open questions for the owner (park on the board)

- **Q1** Where are the Al-Mg-Si files? Copy 3 to 5 of them (the 190330 trio at α +7.3° and one 170330) into `$MACEM_DATA/stem-edx/` with manifest lines, or mount the drive for a session. And which 38 files, and how many of them Al-Mg-Si (`37 of 38`, `26 of 78`).
- **Q2** The alloy's nominal Mg and Si (wt %), foil thickness, and the SDD's measured Mn Kα FWHM; the location of the pure-Al foil spectrum and of any standard with known Mg (for the tail and the real-truth check).
- **Q3** Install `sparse` into `References/exspy-venv` (so RosettaSciIO's own Velox loader is an oracle for counts), or accept the NumPy decoder with the published constants?
- **Q4** Permission to download DTSA-II's QualSpectra (NIST, public domain) for P4, or leave P4 out.
- **Q5** After the numbers exist: which fix is worth a registration first (refine axis before proposing, a weighted or Poisson screening fit, free Al Kα width, a tail reference), or none and a documented limit.
- **Q6** (decided by the session, 2026-10-14): a new `SpectroEDXTests` target, so `SpectroCoreTests` stays the 258 moved names.

## 13. Amendments

### 2026-10-14, before any Swift test: what the generators found (`tools/edx-stages/README.md`, "Findings")

1. **P1 ties.** exSpy's `get_xray_lines_near_energy` returns lines at exactly the same |ΔE| in an order that changes between
   processes (it iterates a hash-ordered dict): "the same list, in the same order" cannot be a contract. The pins store
   the canonical order (|ΔE|, then name); P1 compares the list with tied runs as sets (45 tied adjacent pairs in 360 cases).
2. **E3's prediction is false when the gain is off.** exSpy's offset recovery on planted shifts: mean error +0.03 eV and
   at most 0.71 eV (N_Al 1e6, 288 fits), +0.02 / 0.62 eV (1e7, 96 fits); by gain −3e−4 / 0 / +3e−4 the mean is +0.46 /
   +0.03 / −0.41 eV. "Within ±0.2 eV at N_Al ≥ 1e6" holds only at the planted gain 0 and N 1e7. exSpy's calibration is a
   second estimate, not a pin (section 3), so no gate moves; the prediction is recorded as false. Its `"scale"` mode
   returns 0.0199577 for every planted gain (it does not recover gain here), and `"resolution"` raised in 2 of 384 fits.
3. **Readings the generators made:** set M uses exSpy's line table (energies and weights, asserted equal to exSpy's), as
   criterion 3 needs, the booklet lines being in sets U, B and the calibration set; the Fano width uses 8 ln 2 (it gives the
   registered 79.0 / 82.3 / 85.8 eV); the in-family continuum is the realistic shape projected on the model's Bernstein
   cone (NNLS equal to SciPy's to 2e−16); the reduced grid and realisation counts were chosen to keep the fixtures under
   15 MB (README); sets W1 to W6 and B were added. Counts are stored as noise-free means plus int16 residuals.
4. **Confirmed:** the NumPy decode of RosettaSciIO's 4-detector file equals its published constants (916174, 867647,
   913682, 865236; 3562739); the window method's Mg bias at zero Mg (−117 to −134 per 1e5 Al counts, as section 7.2); the
   surrogate's misfit table within 0.02 of section 7.3 (the 2 % tail row 0.77 against 0.81).
5. **To test (not run):** on a planted file whose detector keys are in the file order Detector-0, Detector-10, Detector-2,
   RosettaSciIO takes Detector-10's axis (file order) and `VeloxEMDReader` may take Detector-2's (it sorts by index). G-E
   decides; a difference is a finding about the reader, fixed only by its own registered change.

### 2026-10-14, while implementing the Swift tests (amendment 2; facts and readings, no gate loosened)

1. **Amendment 1 item 2 misread the `"scale"` pin.** exSpy's `calibrate_energy_axis("scale")` does not return 0.0199577 for every
   planted gain: that is the MEAN of two values it returns, 0.0198877 and 0.0201678 (both present at each of the gains −3e-4,
   0, +3e-4; asserted in `AxisGateTests`). Conclusion unchanged: it does not track the planted gain.
2. **P1 is tested on the table, the lookup lives in the test.** The registration asks for a new `package` function
   `XRayLines.near(energy:width:onlyLines:)`; this slice changes no `Sources/`, so the port of `get_xray_lines_near_energy`
   is a test helper over `XRayLines.all` (exSpy's selection rule, `only_lines` "a", canonical order of amendment 1 item 1).
   What is gated is the table (energies, names, H and He as shipped) through exSpy's rule. The function itself is not added.
3. **Set M is not matched at the line-shape level.** Registration 5.2 integrates each Gaussian over the channel
   ([E_k − 0.01, E_k + 0.01)); the fit model samples it at the channel centre (hyperspy's convention, `EDSModel.swift:16`).
   The relative peak difference is about (Δ/σ)²/24 = 1.7 % at Al Kα, invisible at N_Al ≤ 1e5 and decisive at 1e7. The P2
   criteria were evaluated exactly as registered, with L_D(M) taken from the shipped proposer's own noise-free run on the cell
   (so 3 L_D(M) is the threshold of criterion 2, not the surrogate's 2.2e3). An unregistered control (`GateDTests.testD4…`:
   the stored mean with its bin-integrated Mg, Al, Si lines replaced by the same lines centre-sampled) separates the two
   effects; results below.
4. **D0's wording contradicts its prediction** ("Refuted if … different"; "Predicted: the same … D0 refuted"). Read as: D0 is
   supported iff the full pool loses a Mg that the single-candidate test proposes (net lower by more than 10 %, or not
   proposed); equal results refute it.
5. **The full pool is not ~20 s a spectrum on this path.** Matched spectra take about 0.5 s, mismatched ones tens of seconds.
   The "reduced grid" of the full-pool design is: the noise-free mean and the first ten realisations of every M cell (396
   spectra), and, for D0, of every M and U130 cell with Mg (528 spectra).
6. **E3 has no registered bound for the FWHM at Al Kα**: it is reported (refined R_MnKa through the Fiori–Newbury law against
   the Fano truth), not gated. The offset and gain bounds of section 7 are gated and fail (a registered finding, below);
   the line positions on the refined axis (what a user sees) are reported and asserted at the measured 1.2 eV.
7. **P3** has nothing to run in Swift (the pins hold HyperSpy's results). The test asserts the registered readings of the pins,
   that the pinned Al peak is where the rebuilt spectrum peaks, and reports the Swift proposer on the same spectra beside them.
8. **G-C is partly conditional on `References/`.** Three small public Velox files are copied into `Fixtures/public/` (NOTICE);
   the 4-detector file (9 MB), the three 10x50 SuperX files and `example_velox_EELS_EDS.emd` are read from
   `References/rosettasciio` and their checks are skipped (with a message) when it is absent.

## 14. Results (Swift tests of 2026-10-14, release build, libhdf5 2.1.1; numbers from the gate log of the run)

`SpectroEDXTests`: 32 tests, 0 failures (the two registered findings are `XCTExpectFailure`); the full `tools/test.sh`: SpectroCoreTests 258 (the same names), SpectroGoldenTests green (one recorder test skipped, as before), SpectroKitTests 55, SpectroEELSTests 74, 0 warnings. Run time of the EDX target 227 s (D0 150 s of it).

| gate | outcome |
|---|---|
| C1 public files | 8 of 8 files (grid, channel sums, pixel totals, dense-cube hash) equal the NumPy decode; 4-detector file 3 562 739 events, streams 865 236 / 913 682 / 867 647 / 916 174 |
| C1 planted | 6 of 6 files equal the draw, every frame range (0..1 … 0..3) equal; extremes (channel 0 and 4095, empty pixel, 70 000 in one channel, unterminated last pixel) equal |
| C2 | masks (nil, rectangle, ellipse, arbitrary, empty, full, one pixel), overlapping and empty windows, `densified`: exact, sparse and dense; pool of 12 294 967 295 counts exact in UInt64 |
| C3 | no wrap (65 535 + 65 535 = 131 070), LiveTime 0 passed through as stored |
| E1 | 8 public files and 5 of 6 planted headers equal rsciio's rule bit for bit; `energyCalibrationAgrees` false on the 4-detector planted file. **Finding:** `axis-order` (keys Detector-0, Detector-10, Detector-2): the reader takes Detector-2 (0.01 keV/ch, −0.5 keV), rsciio Detector-10 (0.02, −1.9). `VeloxMetadata.parse` sorts by index. No public file and not the owner's header has out-of-order keys. Marked `XCTExpectFailure` |
| E2 | 12 573 `value2index` cases (3 raise in HyperSpy, all equal) and 52 slices equal |
| E3 | **Finding (the registered prediction "may fail"):** 349 of 384 fits have an offset error above 1 eV and 374 a gain error above 1e-4 (offset mean −3 to −4 eV, up to 14 eV; gain mean +1e-3, up to 4e-3): on lines spanning only 1.25 to 1.84 keV offset and gain trade off. The lines themselves land within 0.17 eV (Al Kα), 0.96 eV (Mg Kα), 1.06 eV (Si Kα) of the planted positions; FWHM at Al Kα +1.1 eV (mean) against the Fano truth; 384 of 384 converge. exSpy pinned: max 0.71 / 0.62 eV (as amendment 1) |
| P1 | 360 lookups equal exSpy (45 tied pairs in canonical order); line energies and widths equal |
| P2 M, single candidate | false alarm 0 of 100 / 20 at every N_Al (≤ 10 % met); detection ≥ 90 % met in every cell where ρN ≥ 3 L_D(M) (P = 1.00); bias within 3 σ met (worst −2.5 σ; Mg is read 17 to 18 % low at ρ 0.01 for N_Al ≥ 1e5, a constant ≈ 1.7e-3 N_Al deficit) |
| P2 M, full pool | the same three criteria met on 396 spectra; other elements proposed in 38 of 396 (Nd, Ce, Tb, Pr, Eu, La; Te, I, Sb, Cs, Ba, Cd, Th): unregistered, the proposer's own look-elsewhere rate |
| P2 mismatched | table in the gate log (430 cells); highlights below |
| P3 | pins hold (defaults: Al Kα only, 0 of 45 Mg; 0.2 %/medfilt 3: Mg in 5 of 5 at every cell but ρ 0.002 / 1e5 with 2 of 5). The Swift proposer on the same U130/L spectra proposes Mg only at ρ 0.05 (5 of 5) and not at ρ 0.002 or 0.01 at any N_Al, where the peak finder sees it |
| windows | integration and background windows (merged, unmerged) equal exSpy exactly; `get_lines_intensity` on 26 280 values (430 cells, means and realisations) within 4e-16 relative |

Mismatched-set highlights (N_Al 1e7, ρ_Mg 0.01, family s, noise-free net/truth; surrogate of 7.3 in brackets): M 0.83 (1.00 with
centre sampling); S+1 0.68 [0.87], S+2 0.53 [0.71], S+3 0.36 [0.54], S+5 0.00 [0.15], S−1 0.40, S−2 0.04, S−3 and beyond 0.00;
HALF 0.00; T1 0.90 / T2 0.77 / T5 0.36 of the matched net; U125 1.03, U130 0.00, U140 0.00, U150 0.00; C1, C2 and B 0.82 to 0.83
(the matched value) with P(proposed) 1.00; W1 0.70.

### Gate D outcomes (each against its registered refuting observation and prediction)

- **D0, pool interplay: SUPPORTED (reading 4).** 528 spectra (48 cells): the full pool loses a Mg the single test proposes on 9
  (for example M.L.N7 ρ 0.01: noise-free net 91 594 single, 23 426 full pool; L_D 119 891; P(proposed) over ten realisations 0.7;
  M.s.N4 ρ 0.05: 401 single, 177 full). Decisions differ in 6, nets by more than 10 % in 21. Prediction "same net in both" NOT met. The
  pool costs Mg on part of the family-L cells at 1e7 and some low-count cells; elsewhere the two agree.
- **D1, Al Kα width: NOT refuted; prediction partly met.** U130 at N_Al 1e7, ρ 0.01: net/truth 0.00 in the mean and in 20 of 20
  realisations (family s), 0.26 (family L); P(proposed) 0.00; flank factors 48 (s) and 25 (L), predicted 0.39 / 0.10 and 20 to 41.
  The loss is stronger than the surrogate's and depends sharply on how far the model's R_MnKa is from the truth: U125 keeps Mg
  (1.03, P = 1.00), U140 and U150 lose it (flank factor 139 and 236), and the model's R scan on U130 gives 0.00 at R ≤ 130 and
  1.04 to 1.11 at R 135 to 150 (flank factor 18.6 at 135, 85 to 165 beyond) at ρ 0.01.
- **D2, axis error: NOT refuted; prediction partly met.** S+3 0.36 and S−3 0.00 (ρ 0.01, noise-free; surrogate 0.54), P(proposed)
  0.00 for every S cell (5 realisations); the half-channel set HALF 0.00. After `EnergyAxisRefinement` first (elements Al, Si or
  Mg, Al, Si; file resolution) the shifted cells all read 0.82 to 0.84, i.e. the matched value, with Mg proposed; refining the
  resolution too (R refined) gives 0.99 on M, every S, HALF and U130 (0.98 on U130, which the prediction said would stay biased).
  Refinement of axis and R_MnKa before proposing recovers Mg in all planted mismatches here, including the half channel; on the
  Fano widths (U130) refining the axis alone leaves 0.00 and only the refined R_MnKa recovers it.
- **D3, tail: NOT refuted; prediction met.** A 2 % tail leaves 0.77 of the matched net at ρ 0.01 (predicted 0.81) and Mg is
  proposed in 0 of 5; at ρ 0.002 the net is 0 for 1 %, 2 % and 5 %. Supplying the true tail as a reference shape raises net/truth
  from 0.64 to 0.84 (2 %), 0.30 to 0.83 (5 %) and 0.75 to 0.83 (1 %), flank factor 24.5 → 6.6, L_D 84 584 → 22 481 (2 %).
- **D4, too little Mg: neither refuted nor confirmed (needs the owner and D6).** The measured fact that bears on it: on
  the registered matched set the margin truth / L_D(M) at N_Al 1e7 is 0.79 (ρ 0.002), 1.98 (0.005), 3.99 (0.01), not the 20 to 50
  predicted from the surrogate (L_D 2.2e3): the shipped proposer's L_D(M) at 1e7 is 2.5e4 (flank factor 7.7). With the same
  lines centre-sampled (the model's own convention, flank factor 1.00) L_D is 3.2e3 and the margin 6.2, 15.5, 31.1: the
  line-shape sampling convention alone costs a factor 8 in L_D at 1e7 (2.5 at 1e6, none at 1e5). A real detector integrates
  over the channel: the same effect applies to real pooled spectra at 1e7 counts and by itself puts the Mg/Al detection limit at
  about 2.5e-3, the size of the owner's raw Mg/Al window ratio of 0.002.
- **D5, window method: not refuted, prediction met.** The SpectroKit window net equals exSpy's on all 26 280 values; Mg net at
  ρ = 0, U130: −1 323 ± 55 (sd of a realisation, 20 realisations, N_Al 1e6, family s; −24 sd), −1 308 ± 111 (family L), −13 348 ± 212
  (1e7), −130 ± 15 (1e5): the bias is the method's (−1.3e-3 N_Al).
- **D6, real data: not run** (the owner's Al-Mg-Si files are not on this Mac).

**What this says about the miss, said with its limits.** On planted data the shipped proposer loses a weak Mg beside a
dominant Al Kα by three independent mechanisms of the registered size or larger (width mismatch, axis error, tail), each a model
misfit the reported σ contains only through the flank factor, and it recovers fully when the axis and R_MnKa are refined
first. Even a perfectly matched model, once the lines are integrated over the channel as a detector does, has L_D(M) of
2.5e-3 N_Al at 1e7 counts. None of this was run on a real file (D6). A fix (refine-then-propose with the resolution free, a
channel-integrated line shape, a tail reference) is a separate registration (Q5).

### Mutation record (each new test broken once in the scratch clone, `Sources/` restored after every run; 29 mutations)

Red = the named tests failed; every new test is red under at least one mutant. Runner: the scratch `mutants.py`, logs not committed.

| mutant (file) | red |
|---|---|
| stream decode skips frame 0 (`first <= frame` → `<`) | 6 of 8 CountsGate tests (C1 ×5, C2 sums) |
| decode drops channel 4095 | the same 6 |
| dense `sum` wraps at 16 bits / at UInt16 `&` | C2 pool above 2^32, C3 no-wrap |
| sparse `sum` ignores the mask | C2 sums, C2 pool |
| sparse `windowSums` upper bound inclusive | C2 window edges (the 8 earlier tests stayed green: the first version of C2 had no event on a window edge; the edge test was added) |
| `densified` halves | C1 planted ×2, C1 public, C2 sums |
| LiveTime altered in the opener | C3 |
| dispersion / 1000.5 | E1 public |
| calibration flag `<= 4` | E1 planted headers |
| detector sort descending | E1 planted headers, E1 axis-order (the expected failure is no longer a failure) |
| `index(of:)` tie rounding reversed | E2 value2index |
| `channelRange` start + 1 | E2 slices |
| refinement gain unit ×2 | E3 refinement |
| refinement offset not applied | D2 |
| table energy of Mg Kα / Se Ln moved | P1 line energy / P1 lookup |
| Fiori-Newbury slope 2.4 | P1 widths, windows ×2 |
| merged background window end + 0.001 | windows |
| net counts with the left window only | window intensities, D5 |
| proposer bar `net >= 0` | P2 false alarm, P2 full pool |
| proposer bar ×30 | P2 detection |
| flank scaling off | P2 bias, D4 |
| flank factor ×3 | D0 |
| Gaussian exponent ×1.2 | D1, D4 |
| everything pruned in the backward step | D0 |
| minimum line energy 1.3 keV (no Mg candidate) | P2 mismatched table |
| tail reference tie ×0 | D3 |
| expectation edited (fixtures only): peaks 7…25 → 30…40; exSpy offset max 0.71 → 0.5 | P3, E3 exSpy pins |
