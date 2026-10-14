# eels-reader

Fixtures and truth for `DM4Experiment.readEELSSpectrumImage` (EELS slice 1b), compared in
`Tests/SpectroKitTests/DM4EELSSpectrumImageTests.swift`.

| file | what |
|---|---|
| `Fixtures/rsciio-EELS_SI.dm4` | RosettaSciIO 049e7d70's public `digitalmicrograph/3D/EELS_SI.dm4` (2 x 2 x 2048 float32, GMS 2.32), byte for byte; sha256 `f9b8203f...` is the one in `rsciio/tests/registry.txt` |
| `Fixtures/eels-planted.dm4` | `make_planted.py`: 21 objects, non-square 3 x 2 x 5 cubes of every converted type, absent tags, stack-builder tags (also a group that holds only a string), one row, each refusal (also a keV energy axis), an EELS object known only by `Meta Data.Signal`, and a last cube whose pixel block ends the file |
| `Fixtures/eels-refused-{zero,short,long,zerodim}.dm4` | `make_planted.py`: one-object files. The first three have a Data tag of 0, 29 and 31 elements for dims [3, 2, 5]: RosettaSciIO raises on each (so each is its own file), the reader throws `truncated`. `zerodim` is [3, 0, 5] with an empty Data tag: RosettaSciIO reads an empty (5, 0, 3) array, the reader refuses it |
| `Fixtures/*.truth.json` | `truth.py`: RosettaSciIO's own reading of each file (`rsciio.digitalmicrograph.file_reader`, from the pinned checkout; for the four refused files its exception or its empty shape): shape and axes, sha256 of the counts in SpectroKit's (y, x, channel) order, samples, E0 / alpha / beta as its mapping gives them, where the pixel block lies |

Regenerate (the `References/` folder is gitignored; a scratch clone has none, so pass the real one):

    References/python-venv/bin/python -I tools/eels-reader/make_planted.py
    References/exspy-venv/bin/python -I tools/eels-reader/truth.py --references /path/to/SpectroKit/References

Both are byte-reproducible (`truth.py` reads twice and stops if the outputs differ; `make_planted.py` has no clock or random
input). `truth.py` stops if `rsciio` is not imported from the pinned checkout.

Axis order, in one line: RosettaSciIO reverses DM's `Dimensions` (x, y, energy; fastest first) and reshapes in C order, so
its array is `[channel][y][x]`, the file's memory order; SpectroKit returns `counts[(y * nx + x) * channels + c]`, which is
`array.transpose(1, 2, 0)`.
