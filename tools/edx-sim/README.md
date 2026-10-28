# tools/edx-sim: synthetic EDX spectra from a physical forward model

`forward.py` (absorption through four detector segments, escape, sum and tail peaks, Si internal fluorescence) over
`xray_model.py` (lines, continuum, detector efficiency) writes the expected, noise-free pooled spectra the EDX tests draw
Poisson counts from. NumPy only; the FFAST mass absorption table is SpectroEDX's own resource.

| script | writes `Tests/SpectroCoreTests/Fixtures/` |
|---|---|
| `proposer_sim.py` | `eds-proposer-sim.json` |
| `weakline_sim.py` | `eds-weakline-sim.json` |
| `absorption_truth_sim.py` | `eds-absorption-truth.json` |
| `realistic_l_sim.py` (standard library only) | `eds-realistic-l-sim.json` |
| `unlisted_sim.py` (standard library only) | `eds-unlisted-sim.json` |

Run each as `References/python/bin/python -I -B tools/edx-sim/<script>.py <out.json>` (`tools/reference/setup.sh` first). Every
output is byte-identical to the committed fixture (checked 2026-10-28).
