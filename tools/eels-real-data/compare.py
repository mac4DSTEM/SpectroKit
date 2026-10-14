#!/usr/bin/env python3
"""Compares the two sides of the registered real-data check (docs/eels-real-data-check-registration.md) and prints a
numbers-only summary as JSON.

    python3 -I tools/eels-real-data/compare.py r1 <swift-r1.json> <rsciio-r1.json>
    python3 -I tools/eels-real-data/compare.py r2 <outdir>        (outdir holds <rule>.f64/.json from eels-real-data r2 and
                                                                  <rule>.exspy.f64 / exspy.json from r2_exspy.py)
R1 gate: for every EELS spectrum image, the counts' sha256, shape and energy axis equal (offset = -origin * scale).
R2 gate (slice 1's gate 1 on real data): I_0, I_t relative <= 1e-12, t/lambda absolute <= 1e-12, threshold channels equal at
every pixel; nil (NaN) where exSpy gives NaN.
"""
import json
import math
import struct
import sys
from pathlib import Path


def r1(swift_path, rs_path):
    sw = json.loads(Path(swift_path).read_text())
    rs = json.loads(Path(rs_path).read_text())
    rs_by_index = {o["index"]: o for o in rs["objects"]}
    rows, ok = [], True
    for o in sw["objects"]:
        r = rs_by_index.get(o["index"])
        row = {"index": o["index"], "name": o["name"], "role": o["role"]}
        if "eels" in o:
            e = o["eels"]
            same = (r is not None and r.get("counts_sha256") == e["countsSha256"] and r["nx"] == e["nx"] and r["ny"] == e["ny"]
                    and r["channels"] == e["channels"])
            ax = [a for a in r["rsciio_axes"] if a["index_in_array"] == 0][0] if r else None
            off = -e["energyOrigin"] * e["energyScale"]
            axis_same = ax is not None and ax["scale"] == e["energyScale"] and ax["offset"] == off and ax["units"] == e["energyUnits"]
            row.update({"shape": [e["ny"], e["nx"], e["channels"]], "countsEqual": same, "energyAxisEqual": axis_same,
                        "energyOffsetEV": off, "energyScaleEV": e["energyScale"], "countsSha256": e["countsSha256"],
                        "beamEnergyKeV": e["beamEnergyKeV"], "convergenceMrad": e["convergenceMrad"],
                        "collectionMrad": e["collectionMrad"],
                        "rsciio": {k: r.get(k) for k in ("beam_energy_keV", "convergence_angle_mrad", "collection_angle_mrad")} if r else None,
                        "readSeconds": e["readSeconds"]})
            ok &= same and axis_same
        else:
            row["readEELS"] = "refused: " + o["notEELS"][:160]
            row["rsciioSignalType"] = r.get("signal_type") if r else None
            if r and r.get("signal_type") == "EELS" and len(r.get("rsciio_shape", [])) == 3:
                row["missedByReader"] = True
                ok = False
        rows.append(row)
    return {"gate": "R1", "pass": ok, "file": Path(sw["file"]).name, "fileSha256": rs["sha256"], "objects": rows}


def f64(path, width):
    b = Path(path).read_bytes()
    v = struct.unpack(f"<{len(b) // 8}d", b)
    return [v[i:i + width] for i in range(0, len(v), width)]


def r2(outdir):
    out = {"gate": "R2", "rules": {}}
    ok = True
    for rule in ("fixed3", "fixed5", "estimated"):
        sw = f64(Path(outdir, f"{rule}.f64"), 6)
        ex = f64(Path(outdir, f"{rule}.exspy.f64"), 4)
        diag = json.loads(Path(outdir, f"{rule}.json").read_text())
        assert len(sw) == len(ex)
        worst = {"i0": 0.0, "it": 0.0, "tl": 0.0}
        chan_diff, nan_mismatch, first = 0, 0, []
        for p, (s, e) in enumerate(zip(sw, ex)):
            for k, a, b in (("i0", s[0], e[0]), ("it", s[1], e[1])):
                if math.isnan(a) or math.isnan(b):
                    if math.isnan(a) != math.isnan(b):
                        nan_mismatch += 1
                    continue
                d = 0.0 if a == b else abs(a - b) / max(abs(a), abs(b))
                worst[k] = max(worst[k], d)
            if math.isnan(s[2]) != math.isnan(e[2]):
                nan_mismatch += 1
            elif not math.isnan(s[2]):
                worst["tl"] = max(worst["tl"], abs(s[2] - e[2]))
            if not (math.isnan(s[3]) and math.isnan(e[3])) and s[3] != e[3]:
                chan_diff += 1
                if len(first) < 5:
                    first.append({"pixel": p, "swiftChannel": s[3], "exspyChannel": e[3], "dTOverLambda": s[2] - e[2]})
        r_ok = worst["i0"] <= 1e-12 and worst["it"] <= 1e-12 and worst["tl"] <= 1e-12 and chan_diff == 0 and nan_mismatch == 0
        ok &= r_ok
        out["rules"][rule] = {"pass": r_ok, "pixels": len(sw), "worstRelativeI0": worst["i0"], "worstRelativeIt": worst["it"],
                              "worstAbsoluteTOverLambda": worst["tl"], "channelMismatches": chan_diff,
                              "nilMismatches": nan_mismatch, "firstMismatches": first, "diagnostics": diag}
    out["pass"] = ok
    return out


if __name__ == "__main__":
    if sys.argv[1] == "r1":
        res = r1(sys.argv[2], sys.argv[3])
    else:
        res = r2(sys.argv[2])
    print(json.dumps(res, indent=2, sort_keys=True))
