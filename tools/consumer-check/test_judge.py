#!/usr/bin/env python3
"""Self-test of controls.judge: the 'declared here' note is accepted in the Swift 6.4 form (module-qualified) and the Swift 6.3
form (a path ending in the edited file), and refused when it points at another file.   test_judge.py <repository root>"""
import importlib.util, os, sys

root = os.path.abspath(sys.argv[1])
sys.argv = ["controls.py", root, "SpectrumImageOpener.kind"]
spec = importlib.util.spec_from_file_location("controls", os.path.join(os.path.dirname(os.path.abspath(__file__)), "controls.py"))
controls = importlib.util.module_from_spec(spec)
spec.loader.exec_module(controls)
c = next(x for x in controls.CONTROLS if x["symbol"] == "SpectrumImageOpener.kind")
error = "Sources/X.swift:5:3: error: 'kind' is inaccessible due to 'package' protection level\n"
cases = [
    ("SpectroCore.SpectrumImageOpener.kind:2:13: note: 'kind(ofFileAt:)' declared here", True),
    ("/Users/runner/SpectroKit/" + c["rel"] + ":40:5: note: 'kind(ofFileAt:)' declared here", True),
    ("/Users/runner/SpectroKit/Sources/Other.swift:40:5: note: 'kind(ofFileAt:)' declared here", False),
]
bad = [note for note, want in cases if controls.judge(c, 1, error + note + "\n")[0] != want]
why = controls.judge(c, 1, error + "/r/Sources/Other.swift:4:5: note: 'kind(ofFileAt:)' declared here\n")[2]
if "compiler notes naming kind: Other.swift:4:5: note: 'kind(ofFileAt:)' declared here" not in why:
    bad.append("the miss message does not show the compiler's notes: " + why)
if bad:
    print("test_judge: FAIL", *bad, sep="\n  ")
    sys.exit(1)
print("test_judge: ok (3 cases)")
