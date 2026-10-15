#!/usr/bin/env python3
"""The README's code cannot drift from the programs that are built from it.

README.md marks its Swift blocks: a ```swift fence directly after `<!-- readme-consumer -->` is a piece of the EDX quick start,
one directly after `<!-- readme-consumer-eels -->` is a piece of the EELS snippet. The pieces of each kind are joined in order,
with one blank line between two pieces. Then:

    Examples/QuantifyEDX/Sources/QuantifyEDX/main.swift              == the EDX pieces
    tools/consumer-check/readme/Sources/readme-consumer/main.swift   == the EDX pieces, a blank line, the EELS pieces

    check-readme.py [--write] [ROOT]

Without --write it compares and exits 1 with a unified diff on any difference (or on a README with no marked block). With --write
it overwrites the two files from the README, which is the source of truth. ROOT defaults to the repository this script is in.
Python standard library only; run it as `python3 -I -B`.
"""
import difflib
import re
import sys
from pathlib import Path

BLOCK = re.compile(r"<!-- (readme-consumer|readme-consumer-eels) -->\n```swift\n(.*?)\n```\n", re.S)


def pieces(readme: str) -> dict:
    out = {"readme-consumer": [], "readme-consumer-eels": []}
    for kind, code in BLOCK.findall(readme):
        out[kind].append(code + "\n")
    return out


def main(argv: list) -> int:
    write = "--write" in argv
    args = [a for a in argv[1:] if a != "--write"]
    root = Path(args[0]) if args else Path(__file__).resolve().parents[3]
    p = pieces((root / "README.md").read_text(encoding="utf-8"))
    edx, eels = "\n".join(p["readme-consumer"]), "\n".join(p["readme-consumer-eels"])
    if not edx or not eels:
        print("check-readme: README.md has no <!-- readme-consumer --> block or no <!-- readme-consumer-eels --> block", file=sys.stderr)
        return 1
    expected = {
        root / "Examples/QuantifyEDX/Sources/QuantifyEDX/main.swift": edx,
        root / "tools/consumer-check/readme/Sources/readme-consumer/main.swift": edx + "\n" + eels,
    }
    bad = 0
    for path, text in expected.items():
        if write:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text, encoding="utf-8")
            print("check-readme: wrote", path.relative_to(root))
            continue
        have = path.read_text(encoding="utf-8") if path.exists() else ""
        if have != text:
            bad += 1
            sys.stderr.writelines(difflib.unified_diff(text.splitlines(True), have.splitlines(True),
                                                       "README.md (blocks)", str(path.relative_to(root))))
            print("check-readme: %s differs from the README's code" % path.relative_to(root), file=sys.stderr)
    if not write and not bad:
        print("check-readme: README code == Examples/QuantifyEDX main.swift and tools/consumer-check/readme main.swift "
              "(%d EDX lines, %d EELS lines)" % (edx.count("\n"), eels.count("\n")))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
