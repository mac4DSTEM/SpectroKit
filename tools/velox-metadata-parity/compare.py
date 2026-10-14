#!/usr/bin/env python3
"""The exact comparison of tools/velox-metadata-parity: reference.json (h5py + RosettaSciIO) against swift.json (the
reader).

    compare.py <reference.json> <swift.json> [--table <out.md>] [--print-table]

Per file: Velox in the reference <=> the reader lists entries; not Velox <=> the reader refuses it (`notVeloxFile`).
Per Velox file: the entry-id sets are equal. Per entry, exactly: `binaryResultDetector`, `operatingMode`,
`projectorMode` (string equal, null <=> nil); `nominalMagnification`, `stemMagnification`, `cameraLengthMeters`,
`exposureTimeSeconds` (the Double's IEEE-754 bit pattern equal to the reference's, null <=> nil); and every
`Detector-<n>` record (the index sets equal; name, type and exposure bits equal). Then every doc-comment claim in the
reference must hold with no counterexample.

One documented deviation is tolerated, and printed as `  deviation  ...`: `exposureTimeSeconds` where the entry stores
its `Detectors` keys out of `Detector-<n>` index order and the reader's value is the index-order one (RosettaSciIO takes
the first entry as stored; the reader cannot see the stored order). Any other difference is a FAIL.

A failure is one line `  FAIL  <file> | <entry id, 6 characters> | <field>: expected <x>, got <y>`. Exit 0 prints
`velox-metadata-parity: all passed - ...`, exit 1 prints the failure count; run.sh --controls matches on the FAIL lines.
"""
import json
import struct
import sys

STRING_FIELDS = ("binaryResultDetector", "operatingMode", "projectorMode")
NUMBER_FIELDS = ("nominalMagnification", "stemMagnification", "cameraLengthMeters", "exposureTimeSeconds")


def shown(v):
    """A comparison value as a short string: a Double by its repr and bit pattern, a string quoted, null as null."""
    if v is None:
        return "null"
    if isinstance(v, dict):
        return "%r (0x%s)" % (struct.unpack(">d", bytes.fromhex(v["bits"]))[0], v["bits"])
    return repr(v)


def same(a, b):
    if isinstance(a, dict) and isinstance(b, dict):
        return a["bits"] == b["bits"]
    return a == b


def short(v):
    if v is None:
        return "-"
    return repr(struct.unpack(">d", bytes.fromhex(v["bits"]))[0])


def main():
    args = sys.argv[1:]
    table_path = args[args.index("--table") + 1] if "--table" in args else None
    print_table = "--print-table" in args
    paths = [a for i, a in enumerate(args) if not a.startswith("--") and (i == 0 or args[i - 1] != "--table")]
    if len(paths) != 2:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    ref = json.load(open(paths[0], encoding="utf-8"))
    swift = json.load(open(paths[1], encoding="utf-8"))["files"]

    failures, deviations, checks = [], [], 0
    counts = {"files": 0, "velox": 0, "refused": 0, "entries": 0, "detectors": 0, "values": 0}

    def check(label, entry, field, want, got):
        nonlocal checks
        checks += 1
        counts["values"] += 1
        if not same(want, got):
            failures.append(f"  FAIL  {label} | {entry} | {field}: expected {shown(want)}, got {shown(got)}")

    rows = []
    for label, info in sorted(ref["files"].items()):
        counts["files"] += 1
        got = swift.get(info["path"])
        if got is None:
            failures.append(f"  FAIL  {label} | - | file: the reader's output has no record of {info['path']}")
            continue
        if not info["velox"]:
            counts["refused"] += 1
            checks += 1
            if got.get("error") != "notVeloxFile":
                failures.append(f"  FAIL  {label} | - | refusal: expected notVeloxFile, got {json.dumps(got)[:200]}")
            continue
        counts["velox"] += 1
        checks += 1
        if "entries" not in got:
            failures.append(f"  FAIL  {label} | - | listing: expected entries, got {json.dumps(got)[:200]}")
            continue
        want_ids, got_ids = set(info["entries"]), set(got["entries"])
        checks += 1
        if want_ids != got_ids:
            failures.append(f"  FAIL  {label} | - | entry ids: only in the reference {sorted(want_ids - got_ids)}, "
                            f"only in the reader {sorted(got_ids - want_ids)}")
        for eid in sorted(want_ids & got_ids):
            counts["entries"] += 1
            want, have, tag = info["entries"][eid], got["entries"][eid], eid[:6]
            for field in STRING_FIELDS + NUMBER_FIELDS:
                order = want["exposureInIndexOrder"]
                if (field == "exposureTimeSeconds" and not same(want[field], have.get(field))
                        and order["storedOutOfIndexOrder"] and same(order["value"], have.get(field))):
                    # RosettaSciIO takes the first entry as STORED, the reader the first by Detector-<n> index; they
                    # part only when the keys are stored out of index order, and then the reader's value is the
                    # index-order one.
                    checks += 1
                    deviations.append(f"  deviation  {label} | {tag} | {field}: RosettaSciIO takes the first entry as "
                                      f"stored ({shown(want[field])}), the reader the first by Detector-<n> index "
                                      f"({shown(have.get(field))}); this entry stores its Detectors keys out of "
                                      f"index order")
                    continue
                check(label, tag, field, want[field], have.get(field))
            want_det = {d["index"]: d for d in want["detectors"]}
            have_det = {d["index"]: d for d in have.get("detectors", [])}
            checks += 1
            if set(want_det) != set(have_det):
                failures.append(f"  FAIL  {label} | {tag} | detector indices: expected {sorted(want_det)}, "
                                f"got {sorted(have_det)}")
            for index in sorted(set(want_det) & set(have_det)):
                counts["detectors"] += 1
                for field in ("name", "type", "exposureTimeSeconds"):
                    check(label, tag, f"Detector-{index}.{field}", want_det[index][field], have_det[index].get(field))
            report = want["report"]
            stem = short(want["stemMagnification"])
            if report["storedStemMagnificationType"] is not None and want["stemMagnification"] is not None:
                stem += f" ({report['storedStemMagnificationType']})"
            elif report["storedStemMagnification"] is not None:
                stem = f"unparsed {report['storedStemMagnification']!r}"
            by_index = short(report["exposureByDetectorIndex"])
            if report["detectorIndexPointsAt"] not in (None, want["binaryResultDetector"]):
                by_index += f" (index {report['binaryResultDetectorIndex']} is {report['detectorIndexPointsAt']})"
            rows.append((label, tag, want["binaryResultDetector"] or "-", short(want["nominalMagnification"]), stem,
                         short(want["cameraLengthMeters"]), want["operatingMode"] or "-", want["projectorMode"] or "-",
                         short(want["exposureTimeSeconds"]), by_index))

    notes, held = [], 0
    for key, claim in sorted(ref["claims"].items()):
        checks += 1
        if claim["counterexamples"]:
            for c in claim["counterexamples"]:
                failures.append(f"  FAIL  {key} | - | claim '{claim['text']}': counterexample {c}")
        else:
            held += 1
            notes.append(f"  claim holds ({claim['checked']} checked): {claim['text']}")
            notes.extend(f"      {line}" for line in claim["detail"])

    if table_path or print_table:
        head = ("file", "entry", "BinaryResult.Detector", "NominalMagnification", "StemMagnification (stored type)",
                "CameraLength", "OperatingMode", "ProjectorMode", "exposure (by name)", "exposure (by DetectorIndex)")
        lines = ["| " + " | ".join(head) + " |", "|" + "|".join("---" for _ in head) + "|"]
        lines += ["| " + " | ".join(r) + " |" for r in rows]
        if table_path:
            open(table_path, "w", encoding="utf-8").write("\n".join(lines) + "\n")
        if print_table:
            print("\n".join(lines))

    for line in notes + deviations:
        print(line)
    if failures:
        print("\n".join(failures))
        print(f"velox-metadata-parity: {len(failures)} FAILURES in {checks} checks")
        sys.exit(1)
    n = len(deviations)
    deviation_note = f", {n} documented deviation{'' if n == 1 else 's'} (printed above)" if deviations else ""
    print(f"velox-metadata-parity: all passed — {counts['files']} files ({counts['velox']} Velox, {counts['refused']} "
          f"refused as not Velox), {counts['entries']} image entries, {counts['detectors']} detector records, "
          f"{counts['values']} values bit-identical to h5py + RosettaSciIO 049e7d70{deviation_note}, "
          f"{held} of {len(ref['claims'])} doc-comment claims hold")


if __name__ == "__main__":
    main()
