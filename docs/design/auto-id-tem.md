# Auto ID for TEM EDS: the identification loop for thin foils (design note, 0.11.0)

`ElementProposer` identifies elements the way the one complete open implementation does it (AutoEMX, Giunto et al. 2025, Lawrence Berkeley National Laboratory; the loop is the NIST
Newbury–Ritchie "automatic qualitative analysis" loop), adapted to TEM thin foils. Written from the
published method and its documented default thresholds; no AutoEMX code is copied (its licence is non-commercial).

## 1. What the loop does (the method, step by step)

The fitter is a plug-in: it takes a set of elements and returns the model spectrum, its deviance, the fitted line areas
and the per-family peak components. Ours is `EDSFit` (joint non-negative least squares of the lines, the Si-escape columns
and the Kramers × Bernstein continuum on the refined axis). The loop around it:

1. **Start.** Fit the known elements (the user's picks, or none). Check the background's health in bands (1 to 2.5,
   2.5 to 5, 5 keV up): data over model in channels without peaks must stay within 0.8 to 1.25; a band outside is a
   warning on every later finding.
2. **Residual peaks.** Top-hat filter the residual (data − model), the hat's width from the detector's σ(E), and look for
   positive peaks at or above 5 σ of the filtered noise; below 1 keV the threshold is 1.5 × higher (edges and chemical
   effects leave structure there). Take the strongest first.
3. **Candidates.** Every element (B to Bi; not Tc, Pm, Ne, Kr, Xe, Rn) with a line of weight ≥ 0.1 within 2.5 σ + 25 eV
   of the peak. Screen each by its line families: a higher family whose overvoltage is high enough must be seen at 3 σ
   where the range holds it (the "missing confirmation line" rule, which we already have as R4).
4. **Test.** Add the candidate to the model. Accept it when the fit statistic Σ (y − μ)² / (μ + (0.01 μ)²) falls by at
   least 100, its area is at or above Currie's L_D, at least 20 % of the fall comes from peak regions (not from a
   background change), and no resolved peak the candidate predicts above its limit is contradicted by the data (a
   local worsening by 9 or more and by more than 5 % of the total gain). Candidates within 30 of the best are reported
   as ambiguous. Refit after each acceptance when the counts are high (summed spectra), so the next residual is
   searched with the fitter's own shapes.
5. **Repeat** from 2 with the accepted element in the model, at most 30 peaks and 10 new elements.
6. **Overlap check.** Elements whose peaks sit under peaks already in the model leave no residual peak; test the
   known overlap partners of the modelled elements directly (linear, tied shifts), and keep one only if two or more of
   its resolved peaks support it.
7. **Prune.** Refit without each identified element; drop any the final fit does not need (statistic falls by less than
   100 and its filtered peak gain is below 100).
8. **Tiers.** *Strong*: a clear peak of its own in the filtered residual, the filtered chi-square improves by ≥ 100 when
   it is added, the background is healthy, no other candidate explains the peak equally well. *Possible*: everything
   else that passed (reported, never added). Si is a detector artefact unless its main line holds ≥ 0.2 % of the counts.

The 1 % relative model term is the point: systematic shape errors grow with the counts while Poisson noise grows with
their root, so without it every small model imperfection becomes "significant" in a summed spectrum. It replaces our
flank-misfit factor, which multiplied a neighbour's detection limit by the misfit beside it (×33 for Mg beside Al on
1339) and which no reference tool has. **The flank-misfit factor goes.**

## 2. What changes for TEM thin foils at 200 to 300 kV

- **No bulk ZAF, no φ(ρz).** AutoEMX's fitter models a bulk SEM target (modified Duncumb continuum × absorption ×
  backscatter × efficiency) at 15 kV. Ours stays: Kramers × Bernstein with the Al K-edge split, the refined axis and
  width, Si escape columns. Thin-foil self-absorption was measured on 1339 and 1456 and keeps no mass thickness, so it is
  not in the model (benched with its tests).
- **Overvoltage.** At 200 kV every K line to 20 keV has an overvoltage above 10, so the confirmation rule can demand the
  K line of every element whose L or M line is proposed and whose K line is inside the fitted range; above the range
  (Au, Pt, Pb K at 70 to 80 keV) the rule cannot run and the pick stays "possible", as today.
- **Line weights.** The NIST/EPQ table (public domain): Al Kβ/Kα (K-M2 + K-M3 over K-L2 + K-L3) 0.0315 against eXSpy's
  0.0132. Measured with Kβ free in a local fit (1.10 to 1.98 keV, free shift and width) on the whole-map sums: 0.031 on 1339
  and 0.034 on 1840, so EPQ is right and eXSpy's table is low by half. (The 0.0174 quoted earlier on 2026-10-23 is EPQ's Mg,
  one row off.) The rest of the shape error is the 1 % model term's job, not a free Kβ.
- **Detector.** Four Super-X SDDs, no window: σ(E) from the Fiori–Newbury law at the refined Mn Kα width; the top hat's
  width follows it. No per-detector tail calibration yet (the measured tail on 1339 is nil on the refined axis).
- **Thresholds.** AutoEMX's defaults as published, unchanged, until the three real files say otherwise; a changed
  threshold is a stated departure in `docs/parity.md`.

## 3. Where Metal pays, and MLX

- The loop is sequential and small (tens of fits of a 4000-channel spectrum): CPU, Accelerate, as today.
- Metal pays where it already does: the per-pixel maps after the identification (net, wt%, at%), not in the loop.
- MLX has no place here: there is no learned part. A learned peak-shape or background model would need labelled
  spectra we do not have; it stays a later idea, not part of this.

## 4. Where it lives in the code

- **One loop, the old public call.** `ElementProposer.propose(counts:axis:settings:holeCounts:cancelled:progress:)` keeps its
  signature and its `ProposalResult`, so both apps call it unchanged; its body becomes the loop above. The all-candidate joint
  fit, its L_C pruning and the single-candidate forward step go (they are what the residual-peak search replaces). The loop
  lives in `Proposer/IdentificationLoop.swift` (top hat, residual peaks, candidates, test, prune) beside the proposer.
- **The flank-misfit factor goes.** `FlankMisfitGeometry`, `ProposerPolicy.flankScaling` and `.flank` are removed (Migration
  paragraph); `ElementCandidate.misfit` stays in the type and is always 1 for one minor, then goes. σ₀ is the fit's own null
  variance (`FitNullVariance`), unscaled; L_C and L_D stay Currie's on it.
- **The statistic.** χ²₁ = Σ (y − μ)² / max(μ + (0.01 μ)², 1) over the fitted channels, on the fit's own model. The local share
  is the part of Δχ²₁ in channels within 1.5 FWHM of the candidate's lines (and their escapes).
- **The top hat.** Centre width one FWHM at the peak's energy (odd number of channels), each side lobe half that, weights
  +1/n_c and −1/(2 n_s), so a straight background filters to zero; the noise of a filtered channel is
  √(Σ k_j² max(y_j, 1)). The width follows σ(E), so the filter is recomputed per channel from the law; at 4000 channels this
  is microseconds, CPU.
- **Line weights.** The identification fit uses the NIST EPQ weights (`LineWeights.csv`, already bundled for the k-factors)
  through a `lineWeights` choice on `EDSLineModel.build`; the quantification fit keeps eXSpy's table (the parity numbers
  do not move). Stated in the proposer's notes.
- **Thresholds.** Named constants in `IdentificationThresholds` (public, on `ProposerPolicy`): peak 5 σ, ×1.5 below 1 keV,
  candidate window 2.5 σ + 25 eV, weight ≥ 0.1, confirmation 3 σ, Δχ²₁ ≥ 100, local share ≥ 0.2, contradiction 9 and 5 %,
  ambiguity 30, prune 100, Si artefact 0.2 %, 30 peaks, 10 new elements, model term 0.01. One test each.
- **Kept as they are.** The lowest tested line (0.45 keV), the pile-up columns and sum-peak questions, R4's family check
  (it is step 3's confirmation rule; the loop runs it at candidate time instead of after), the Cu hole-region note, the
  shipped `ProposalRules` after the proposal, cancellation and progress. The axis refinement stays in the room (it needs the
  pooled quantifier and the file's metadata); the loop runs on whatever axis it is given.
- **Tiers on the result.** A strong element is proposed; a possible one is a candidate with a `possibleReason` (one sentence
  with the numbers) and is never proposed. `ElementCandidate.isProposed` becomes net ≥ L_D, no family note and no possible
  reason. Additive public API.

## 5. What the first runs changed (2026-10-23, measured)

Each a stated departure from the method as documented, with the case that forced it:

- **The fit inside the loop is weighted** by the statistic's own variance, w = 1/max(ȳ + (0.01 ȳ)², 1) with ȳ the data smoothed
  over one FWHM (raw y would down-weight every channel that fluctuates high, Neyman's bias of about a count per channel; fixed per
  spectrum, so every candidate is fitted on the same footing and the problem stays linear; σ₀ is the weighted estimator's null
  variance). Unweighted, a strong line's shape error dragged the continuum beside it (data over model 3.1 in 1 to 2.5 keV beside a
  planted Al 5 % narrower than the model) and the hump became an element (Os M). With the weights the planted bands read 1.00 to 1.12.
- **The candidate that explains the peak joins**, ranked by the statistic's fall within one FWHM of the peak, not over the whole
  spectrum: on 1456 W Mα (1.775 keV) took the Si Kα peak by total gain (80 M against 47 M) because its L lines also soaked up
  misfits elsewhere; Si wins at the peak. Ambiguity is judged on the same number.
- **A confirmation line is a residual peak of its own**: a local maximum of 3 σ within one Gaussian σ of the line. The bare window
  maximum let the flank of an unmodelled Cu Kα (106 eV away, 1.6 σ) confirm Ta Lα.
- **An L or M find whose confirmation line is out of range stays possible** (In Lα on 1456: In Kα 24.2 keV, past the 20 keV fit).
- **The background check demotes** a find whose peak lies in an unhealthy band, as the method's strong tier says; with the weighted fit
  no band of the three files is unhealthy.
- **Prune** drops a find only when both the final fit's statistic and the fall at its own peak (one FWHM) cost less than 100; a
  pile-up column whose parent was pruned goes with it.
- **Not yet:** the overlap check (step 6). Its finds are possible only, so it changes no proposal; an open item.

Result on three measured whole-map sums (two Al-Mg-Si alloys, files 1339 and 1840, and a FIB lamella, 1456), refined axis: 1339 and 1840 propose O, Mg, Al, Si, Cu plus Zr, Mn (and Fe on 1840); 1456
proposes O, Si, Ni, Ge, Pt plus Cu, Zr and Ga. Zr is on all three files (the instrument's); Mn reads 22 and 70 times its limit on
the Al alloys (a 6xxx minor element by the numbers; the alloy's specification is not yet known). Planted: Mg at 2 % beside a 5 %-misfit Al reads
121 509 of 120 000 and is proposed; without Mg nothing new is proposed.

## 6. The oracle and the tests (red-first)

- AutoEMX 1.8.0 run on the whole-map sums of 1339, 1840 and 1456 in a Python 3.12 environment (it refuses Python
  3.14). Run A, its own fitter at 200 keV: the fit returns NaN on all three files
  with and without the truth elements (its bulk SEM model and the Phenom XL detector calibration do not reach a
  200 kV thin foil); with SEM-like parameters (30 keV, range to 10 keV) it ran 11 minutes on 1339 without finishing.
  Run B, its loop with an exSpy EDS model as the plug-in fitter, finds every real peak (Mg at 100 to 120 σ, Si at 31 to
  40 σ) and then prunes them, because the exSpy fit (polynomial background, unconstrained) fails its own background check
  (0.52 in 1 to 2.5 keV on 1339). With exSpy underneath the pruning means nothing; with our fitter it is the test.
- The bar is therefore the known answers, not Run B's lists: 1339 and 1840 propose O, Mg, Al, Si, Cu (Fe and Zr allowed
  where found), 1456 proposes O, Si, Ni, Ge, Pt; nothing else is proposed on any of the three (`RealFileAutoIDTests`, opt-in with
  `SPECTRO_REAL_DATA=1` and the files under `$MACEM_DATA`).
- Planted (in the gate): Mg at 2 % beside a misfit Al is proposed (the former `FlankMisfitCoreTests` known issue became
  a plain expectation); the same spectrum without Mg proposes no Mg; the thresholds as named constants with one test each;
  the top hat filters a straight line to zero; χ²₁ of a perfect model is Σ 0.

## Sources

AutoEMX (github.com/CederGroupHub/AutoEMX; Giunto et al., "Accurate SEM-EDS quantification, automation and machine
learning enable high-throughput compositional characterization of powders", Research Square rs-7837297, 2025; the
identification thresholds as documented in the package, read for the method only). Newbury & Ritchie, "Quantitative
electron-excited X-ray microanalysis of borides, carbides, nitrides, oxides, and fluorides with scanning electron
microscopy/silicon drift detector energy-dispersive spectrometry (SEM/SDD-EDS) and NIST DTSA-II", and NIST EPQ
(github.com/usnistgov/EPQ, public domain) for the overvoltage and confirmation-line rules and the line table. Currie,
Anal. Chem. 40 (1968) 586, for L_C and L_D.
