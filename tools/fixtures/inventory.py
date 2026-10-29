#!/usr/bin/env python3
"""Write Tests/Fixtures/README.md: one row per committed fixture under Tests/*/Fixtures/, with its size and the script that writes it.

Run: python3 -I tools/fixtures/inventory.py            (standard library only; fails if a fixture matches no rule or a rule's script is missing)
     python3 -I tools/fixtures/inventory.py --check    (fails if the README is not what this script writes)
"""
import os
import re
import subprocess
import sys

REPO = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT = os.path.join(REPO, "Tests", "Fixtures", "README.md")
RSCIIO = "third party: RosettaSciIO public test data (GPL-3.0-or-later, commit 049e7d70), copied unchanged"
EXSPY = "third party: exSpy test data (GPL-3.0-or-later), re-encoded as raw float64"

# (path regex relative to Tests/, the generator, a note). First match wins. A generator is a script path under tools/ (checked to exist),
# or a sentence naming the exact origin.
RULES = [
    (r"SpectroCoreTests/Fixtures/eds-proposer-sim\.json", "tools/edx-sim/proposer_sim.py", ""),
    (r"SpectroCoreTests/Fixtures/eds-weakline-sim\.json", "tools/edx-sim/weakline_sim.py", ""),
    (r"SpectroCoreTests/Fixtures/eds-absorption-truth\.json", "tools/edx-sim/absorption_truth_sim.py", ""),
    (r"SpectroCoreTests/Fixtures/eds-realistic-l-sim\.json", "tools/edx-sim/realistic_l_sim.py", ""),
    (r"SpectroCoreTests/Fixtures/eds-unlisted-sim\.json", "tools/edx-sim/unlisted_sim.py", ""),
    (r"SpectroCoreTests/Fixtures/eds-pins-exspy-7185a4d1\.json", "tools/edx-exspy-pins/pins.py", ""),
    (r"SpectroCoreTests/Fixtures/eds-fit-exspy-7185a4d1\.json", "tools/edx-exspy-pins/fit_pins.py", "rewrites it to the last bit (BLAS order)"),
    (r"SpectroCoreTests/Fixtures/eds-quant-pins-exspy-7185a4d1\.json", "tools/edx-exspy-pins/quant_pins.py", ""),
    (r"SpectroCoreTests/Fixtures/registration-pins\.json", "tools/registration/pins.py", ""),
    (r"SpectroCoreTests/Fixtures/spectrum-tools-.*-pins\.json", "tools/spectrum-tools/pins.py", ""),
    (r"SpectroCoreTests/Fixtures/velox-tiny\.emd", "tools/edx-planted/make_velox_tiny.py", ""),
    (r"SpectroCoreTests/Fixtures/demo-edx-tiny\.(dm4|truth\.json)",
     "mac4DSTEM's tools/demo-edx/sim_edx.py --tiny --seed 42 (mac4DSTEM history before 7a0f727f)",
     "frozen input: the generator needs mac4DSTEM's 4D reflection export, so it is not carried here"),
    (r"SpectroCoreTests/Fixtures/qshape3\.mac4dstem\.h5", "copied from mac4DSTEM's test fixtures at extraction (commit 5ba712a0)",
     "any non-EDS HDF5 file serves: the test only checks the sniff calls it `.other`"),
    (r"SpectroCoreTests/Fixtures/spectro-golden/.*", "SpectroGoldenTests' recorder (`SPECTRO_GOLDEN_DIR=<dir> swift test --filter testRecordBaseline`; arrays: `SPECTRO_GOLDEN_ARRAYS_DIR=<dir> tools/test.sh --filter SpectroGoldenTests/testRecordPortableArrays`)", ""),
    (r"SpectroEDXTests/Fixtures/public/.*\.emd", "copied from References/rosettasciio (rsciio/tests/data/emd)", RSCIIO),
    (r"SpectroEDXTests/Fixtures/edx-0100-exspy\.json", "tools/edx-kfactor-import/pins.py", ""),
    (r"SpectroEDXTests/Fixtures/edx-quant-maps-exspy\.json", "tools/edx-quant-maps/pins.py", ""),
    (r"SpectroEDXTests/Fixtures/xray-lines-exspy-7185a4d1\.json", "tools/edx-lines/pins.py", ""),
    (r"SpectroEDXTests/Fixtures/edx-(planted|calibration).*", "tools/edx-planted/make_planted.py", ""),
    (r"SpectroEDXTests/Fixtures/velox-stream.*", "tools/edx-planted/make_velox_streams.py", ""),
    (r"SpectroEDXTests/Fixtures/(pins\.json|edx-axis-e2\.f64|edx-pins-intensity\.f64)", "tools/edx-planted/pins.py", ""),
    (r"SpectroEELSTests/Fixtures/eels16-model-.*", "tools/eels-chain/model.py", ""),
    (r"SpectroEELSTests/Fixtures/eels16-edges-pins\.json", "tools/eels-chain/edges.py", ""),
    (r"SpectroEELSTests/Fixtures/eelsall-.*", "tools/eels-chain/edges.py --all", ""),
    (r"SpectroEELSTests/Fixtures/eels16-.*", "tools/eels-chain/pins.py", ""),
    (r"SpectroEELSTests/Fixtures/eelsrm-.*", "tools/eels-rl-mlls/pins.py", ""),
    (r"SpectroEELSTests/Fixtures/edge-sigma-CK\.(f64|json)", "tools/eels-edge/pins.py --sigma-only", ""),
    (r"SpectroEELSTests/Fixtures/edge-pins\.json", "tools/eels-edge/pins.py", ""),
    (r"SpectroEELSTests/Fixtures/edge-.*", "tools/eels-edge/make_planted.py", ""),
    (r"SpectroEELSTests/Fixtures/exspy-linescan-.*", "tools/eels-thickness/pins.py", EXSPY),
    (r"SpectroEELSTests/Fixtures/planted-.*", "tools/eels-thickness/make_planted.py", ""),
    (r"SpectroEELSTests/Fixtures/pins\.json", "tools/eels-thickness/pins.py", ""),
    (r"SpectroEELSTests/Fixtures/portable-thresholds\.json", "tools/eels-thickness/make_portable_thresholds.py", ""),
    (r"SpectroEELSTests/Fixtures/sg-parity\.(f64|json)", "tools/eels-thickness/make_sg_parity.py", ""),
    (r"SpectroEELSTests/Fixtures/refuter/B\d.*", "tools/eels-thickness/edge_cases.py", "seed 777001; three of its cases"),
    (r"SpectroEELSTests/Fixtures/refuter/R\d.*", "tools/eels-thickness/random_cases.py", "seed 424242; four of its 60 cases"),
]


def size(n):
    return f"{n / 1e6:.1f} MB" if n >= 1e6 else f"{n / 1e3:.1f} KB"


def main():
    files = subprocess.run(["git", "-C", REPO, "ls-files", "Tests"], capture_output=True, text=True, check=True).stdout.split("\n")
    files = sorted(f[len("Tests/"):] for f in files if "/Fixtures/" in f and not f.endswith("Fixtures/README.md"))
    rows, missing, scripts = [], [], set()
    for f in files:
        rule = next((r for r in RULES if re.fullmatch(r[0], f)), None)
        if rule is None:
            missing.append(f)
            continue
        gen, note = rule[1], rule[2]
        if gen.startswith("tools/"):
            script = gen.split()[0]
            if not os.path.exists(os.path.join(REPO, script)):
                sys.exit(f"inventory: {f}: {script} is not in the repo")
            scripts.add(script)
            gen = f"`{gen}`"
        rows.append(f"| `{f}` | {size(os.path.getsize(os.path.join(REPO, 'Tests', f)))} | {gen} | {note} |")
    if missing:
        sys.exit("inventory: no rule for\n  " + "\n  ".join(missing))
    third = sum(1 for r in RULES for f in files if re.fullmatch(r[0], f) and r[2].startswith("third party"))
    text = "\n".join([
        "# Test fixtures",
        "",
        f"One row per committed fixture under `Tests/*/Fixtures/` ({len(files)} files): its size and what writes it. Written by",
        "`tools/fixtures/inventory.py`; do not edit by hand. Generators run in the Python reference `tools/reference/setup.sh` builds",
        "(`References/python`), from the repo root, as each script's header says.",
        "",
        "Licence: every fixture is generated from this kit's code and its pinned Python reference and ships under the kit's",
        f"GPL-3.0-only licence, except the {third} rows marked *third party*: keep their licence line when the files move. No",
        "fixture holds anyone's measured data; real datasets are read from `$MACEM_DATA` and never copied into the repo.",
        "",
        "A moved fixture is its own commit with the reason and a CHANGELOG line.",
        "",
        "| File | Size | Written by | Note |",
        "|---|---|---|---|",
        *rows,
        "",
    ])
    if "--check" in sys.argv:
        if open(OUT).read() != text:
            sys.exit("inventory: Tests/Fixtures/README.md is stale; run tools/fixtures/inventory.py")
        return
    with open(OUT, "w") as fh:
        fh.write(text)
    print(f"{len(files)} fixtures, {len(scripts)} generators: {OUT}")


if __name__ == "__main__":
    main()
