"""Full X-ray line table pin: every (Z, element, line, energy, weight) row exSpy's own loader builds.

Run: References/python/bin/python -I -B tools/edx-lines/pins.py
Writes Tests/SpectroEDXTests/Fixtures/xray-lines-exspy-7185a4d1.json. Reference: exSpy 7185a4d1, HyperSpy 2.4.0.
exSpy is not installed in the venv, so exspy/material/_elements.py is executed from the pinned checkout
(it needs only hyperspy.misc.utils); the rows are what `exspy.material.elements` holds.
"""
import importlib.util, json, sys
from pathlib import Path

root = Path(__file__).resolve().parents[2]
src = root / "References/exspy-7185a4d1/exspy/material/_elements.py"
spec = importlib.util.spec_from_file_location("exspy_elements", src)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
els = mod.elements.as_dictionary()

rows = []
for sym, props in els.items():
    if sym == "__doc__":
        continue
    xl = props.get("Atomic_properties", {}).get("Xray_lines", {})
    z = props["General_properties"]["Z"]
    for name, v in xl.items():
        rows.append([z, sym, name, repr(float(v["energy (keV)"])), repr(float(v["weight"]))])
rows.sort(key=lambda r: r[0])  # stable: keeps exSpy's per-element line order
out = root / "Tests/SpectroEDXTests/Fixtures/xray-lines-exspy-7185a4d1.json"
json.dump({"exspy": "7185a4d1", "hyperspy": "2.4.0", "rows": rows}, open(out, "w"), indent=0)
print(len(rows), "rows ->", out, file=sys.stderr)
