# tools/eels-real-data: the registered real-data check of EELS slice 1

Runs `docs/eels-real-data-check-registration.md` on the owner's EELS scans, read from `$MACEM_DATA` (default `../data` from
the repository root) and never copied here. Everything written into the repository is numbers only (no spectra):
`docs/eels-real-data/`. The large per-pixel arrays go to a scratch directory and are not committed. Not part of the gate.

| piece | runs in | does |
|---|---|---|
| `eels-real-data` (Swift, this package; SpectroKit by path, public API only) | `swift run -c release --package-path tools/eels-real-data eels-real-data …` | `r1 <file> <out.json>`: every object, and for each EELS SI the reader's shape, energy axis, E0/α/β, sha256 of its float32 counts in (y, x, channel) order. `r2 <file> <index> <outdir>`: `EELSThickness.logRatio` with fixed 3.0 eV, fixed 5.0 eV and the estimated rule; per-pixel arrays and section 3's diagnostics |
| `r1_rsciio.py` | `References/exspy-venv/bin/python -I -B` | the pinned RosettaSciIO 049e7d70's reading, by `tools/eels-reader/truth.py`'s own `one_file` |
| `r2_exspy.py` | same | exSpy 7185a4d1 (HyperSpy 2.4.0, axis binned) on the same counts, the same three rules |
| `compare.py` | `python3 -I` | the R1 and R2 gates; prints a JSON summary |

The DM4 energy axis is `(c − origin) · scale`; HyperSpy's offset is `−origin · scale` (as RosettaSciIO maps it), and the
Swift side builds its `LowLossSpectrumImage` with that offset. libhdf5 is not needed (DM4 only).
