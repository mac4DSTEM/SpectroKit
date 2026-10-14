#!/usr/bin/env python3
"""R1 of docs/eels-real-data-check-registration.md, RosettaSciIO's side: the pinned RosettaSciIO 049e7d70's reading of one of the
owner's DM4 files, by tools/eels-reader/truth.py's own `one_file` (the same reading the reader's fixtures are pinned to): per
object index, name, shape, axes, E0/alpha/beta as rsciio maps them, and for every EELS spectrum image the sha256 of its counts as
float32 little-endian in SpectroKit's (y, x, channel) order. Numbers only.

    References/exspy-venv/bin/python -I -B tools/eels-real-data/r1_rsciio.py <file.dm4> <out.json> [--references DIR]
"""
import argparse
import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ap = argparse.ArgumentParser()
ap.add_argument("file")
ap.add_argument("out")
ap.add_argument("--references", default=str(ROOT / "References"))
a = ap.parse_args()

spec = importlib.util.spec_from_file_location("truth", ROOT / "tools" / "eels-reader" / "truth.py")
truth = importlib.util.module_from_spec(spec)
spec.loader.exec_module(truth)
file_reader, DigitalMicrographReader, pinned = truth.load_rsciio(a.references)
import numpy as np  # noqa: E402

entry = truth.one_file(Path(a.file), a.references, np, file_reader, DigitalMicrographReader)
entry["reference"] = f"RosettaSciIO {truth.RSCIIO_COMMIT} (pinned checkout), numpy {np.__version__}"
for o in entry["objects"]:
    o.pop("samples", None)
Path(a.out).write_text(json.dumps(entry, indent=2, sort_keys=True) + "\n")
print(f"{a.out}: {len(entry['objects'])} objects")
