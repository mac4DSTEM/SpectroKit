# The owner's EELS scans: results of the registered real-data check (2026-10-14)

Run by the overnight session of 2026-10-14 as `docs/eels-real-data-check-registration.md` registers it, and the slice-2
diagnostic of `docs/eels-slice-2-registration.md` section 8. SpectroKit at `d4f7b7e` (the port as committed: the reader
after its review fixes, the Savitzky–Golay derivative bit-identical to SciPy, slice 2). The files were read from
`$MACEM_DATA` (`../data`) and never copied; these logs hold numbers only. Tools: `tools/eels-real-data` (README there).
Every file's sha256 equalled the registration's before anything was read (`r1-*.json`, `fileSha256`).

## R1, the reader (gate: equal) — pass

All four files, every EELS spectrum image (LL and HL, eight in all): the float32 counts' sha256 in (y, x, channel) order,
the shape and the energy axis (offset −origin · scale, scale, units) equal RosettaSciIO 049e7d70's reading. The survey,
ADF and thumbnail objects are refused as not EELS, as they should be. Reads take 0.08 to 0.86 s. `143_STEM SI.dm4` and
`143_STEM SI_1.dm4` hold identical counts in both SIs (the same sha256).

**A correction to the registration's section 1:** RosettaSciIO does map E0, α and β for these files (its metadata
mapping, which the header-only read before registration did not apply): 200 keV, 10.5 mrad, 25.647 mrad, and the reader
gives the same three values. No gate depends on it.

## R2, t/λ against exSpy (gate: I_0, I_t ≤ 1e−12 relative, t/λ ≤ 1e−12 absolute, same channel) — pass

On every low-loss SI (251 040 pixels with the duplicate save), with the fixed thresholds 3.0 and 5.0 eV and the estimated
rule: I_0, I_t and t/λ equal exSpy's bit for bit (worst difference 0.0), every threshold channel equal, the one pixel
where exSpy's estimated threshold is NaN (EELS_3) nil here with `noInflexionFound`. (The same held before the
Savitzky–Golay fix: these spectra have no ties.)

Diagnostics (section 3; reported, not judged): the zero-loss peak sits at 0 eV in every pixel but one (EELS_3: 1 of 90 000
beyond one channel), so no map needs zero-loss alignment. t/λ medians (fixed 5 eV): EELS_1 0.60 (1st–99th percentile 0.35
to 1.06), EELS_2 0.69 (0.38 to 1.14), EELS_3 1.02 (0.63 to 1.30; one pixel above 3). σ_counting medians 3.8e−4 to 5.1e−4.
The estimated thresholds run 6 to 9 eV; the estimated-rule t/λ is 0.05 to 0.08 below the 3 eV one. No thickness in nm:
λ needs the owner's material.

## Slice 2 on EELS_2 (diagnostic, never a gate)

`143_STEM SI.dm4`, C, N and O K by the ratio method, default windows (onset − 50 to onset − 5 eV), Δ = 50 eV, E0, α, β from
the tags (effective collection angle 24.5 mrad), the dose ratio exposure(HL) / exposure(LL) = 0.0199005 s / 9.95025e−5 s
= 200.0, from the files' `EELS.Acquisition.Exposure (s)` tags. `validation: "none"`.

| edge | route | median n (atoms/nm²) | 1st–99th pct | negative pixels | median σ_n / n | r (median) |
|---|---|---|---|---|---|---|
| C K | I_low(Δ) | 7260 | 4266–11336 | 0 | 0.1 % | 4.00 |
| C K | I_0 | 12356 | 5824–25787 | 0 | 0.1 % | |
| N K | I_low(Δ) | −157 | −1561–352 | 54 705 of 74 304 | 12 % | 3.12 |
| O K | I_low(Δ) | 344 | −286–1103 | 6 651 | 9 % | 3.81 |

The C K map against GMS's own C K signal map (`EELS Map (1)/C K Signal (EELS).dm4`, GMS's units, not an areal density):
Pearson 0.985, Spearman 0.992 over all 74 304 pixels, the ratio GMS / port 0.00253 with quartiles 0.00247 to 0.00257 (the
I_0 route: 0.951). So the spatial pattern agrees closely and the scale factor is nearly constant. N K: GMS's own map is 0
at most pixels (median 0), and the port's is negative at 74 %: neither finds N above the background under the C K tail,
which is the registered reason N and O K are labelled "background under a preceding edge's tail". O K: Pearson 0.61.

What this does not say: that 7260 C atoms/nm² is right. The dft cross section, the power-law background and the ratio
method are not checked against a specimen of known composition and thickness here (registration section 9).
