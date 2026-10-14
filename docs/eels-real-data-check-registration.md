# The owner's EELS scans: a real-data check of EELS slice 1 (registration)

Registered 2026-10-14 by SpectroKit's session, before any run on these files (the owner's order: register them as a
real-data check before any run; suite `CLAUDE.md`: the data stay in the suite's `data/` folder, read as `$MACEM_DATA`,
never copied into this repository; numbers measured on them are cited with their log). Before this registration only
headers were read: a lazy RosettaSciIO 049e7d70 read of each file's object names, shapes, energy axes and tags, and the
files' sha256; no spectrum was summed, fitted or loaded.

This check measures, it does not validate: no thickness here is called right (`validation: "none"` stays; section 5). It
has one gate, the port's agreement with exSpy on real data (as slice 1's gate 1), and diagnostics that are reported, not
judged.

## 1. The files

Paths relative to `$MACEM_DATA`; sha256 and size in bytes, read 2026-10-14:

| File | sha256 | Bytes | Header (pixels nx × ny) |
|---|---|---|---|
| `eels/EELS_1/SI data (1)(9)/142_STEM SI.dm4` | `eab346e919fec5aa788c22b243d53b7238dc99baafc762999e948de02be9ea3e` | 209955225 | LL SI and HL SI, 112 × 111 px |
| `eels/EELS_2/SI data (2)(2)/143_STEM SI.dm4` | `f2f6babdf057cfdd08d75933dbc8b7ab26fb1652d91461a93008926971dc7e2b` | 1210551765 | LL SI and HL SI, 432 × 172 px |
| `eels/EELS_2/SI data (2)(2)/143_STEM SI_1.dm4` | `d6424d5577b32c1d0632cc5d7401f627d2ad0199795a95026baa2cdb03fbbf24` | 1210551793 | the same layout (a second save) |
| `eels/EELS_3/SI data (4)/145_STEM SI.dm4` | `7be109f81b68273a35c072c6f9c524faadd2506232b6eee6ccc8e83af55f76d0` | 1458091921 | LL SI and HL SI, 300 × 300 px |

Each is a Dual-EELS spectrum image: "EELS LL SI" (2020 channels, −150 eV + 0.75 eV per channel: the zero-loss peak and
the low-loss region) and "EELS HL SI" (2020 channels from 150 eV), float32, beside the survey and ADF images.
RosettaSciIO maps no E0, convergence or collection angle from these files. `EELS_2` also holds GMS's own C, N and O K
maps and models (`EELS Map (1)/`, and the "Picker" files); they are kept for slice 2's check and not used here. A file
whose sha256 differs when the check runs is not this registration's file: the check stops and reports it.

## 2. What runs, in order

Each run is logged with SpectroKit's commit, the file's sha256 and the exact command; the logs hold numbers only (no
spectra) and are committed under `docs/eels-real-data/` with a summary.

- **R1, the reader (tier 2).** `DM4Experiment.list` and `readEELSSpectrumImage` on every LL and HL SI; the counts
  compared with RosettaSciIO 049e7d70's reading of the same object (sha256 of the float32 counts in SpectroKit's (y, x,
  channel) order), and the energy axis. Gate: equal. E0, α, β: RosettaSciIO maps none; the reader's values are reported.
  `143_STEM SI.dm4` and `143_STEM SI_1.dm4`: whether their LL SIs' counts are identical is reported.
- **R2, t/λ, the port against exSpy (slice 1's gate 1 on real data).** `EELSThickness.logRatio` on each LL SI with the
  fixed thresholds 3.0 and 5.0 eV and with the estimated rule (exSpy's defaults); exSpy 7185a4d1 (HyperSpy 2.4.0, axis
  binned) on the same float32 counts. Gate: I_0 and I_t relative ≤ 1e-12, t/λ absolute ≤ 1e-12, threshold channels equal
  at every pixel that is not a tie (the tie rule of the slice-1 registration's amendments). A difference is a port
  failure, never a tolerance to widen.

## 3. Diagnostics (reported, not gates)

Per LL SI and rule: the zero-loss centre (`zlpCentre`) distribution (median, 1st and 99th percentile, the fraction of
pixels with |centre| > 0.75 eV, i.e. one channel); t/λ's median, 1st and 99th percentile; the nil pixels and their
reasons; σ_counting's median; the estimated threshold's distribution and its global `tol`; run times. Read now, before
the run:

- More than 5 % of pixels with |zlpCentre| > 0.75 eV: the t/λ maps are labelled "needs zero-loss alignment" (slice 1
  does not align; exSpy's method assumes the zero-loss peak at 0 eV), and their numbers are reported with that label.
- A t/λ below 0 or above 3 is reported as outside the log-ratio method's useful range, not as a thickness.
- The estimated threshold on real, noisy data is expected to wander (the slice-1 registration's first amendment); the
  fixed-threshold maps are the ones a reader should use.
- No thickness in nanometres: E0, α and β are not in these files' mapped tags; λ needs them, or the owner's values.

## 4. The manifest

When R1 first reads a file, its line is added to `$MACEM_DATA/README.md`'s manifest (file, technique, instrument and
mode, date, what it is for), from what the headers say; what they do not say is left for the owner.

## 5. What is not claimed

Agreement with exSpy on real data is a statement about the port, not about the specimen. The t/λ maps are not validated:
nothing in these files gives an independent thickness (a wedge, a FIB lamella measured another way, or a CBED thickness
would). That check is the owner's to supply and is registered then.
