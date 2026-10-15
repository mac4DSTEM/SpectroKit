#!/usr/bin/env python3
"""The test names a tools/test.sh run passed or skipped, one `Target.Suite.test` per line (a skip suffixed ` skipped`), sorted.

Reads XCTest's console lines (`Test Case '-[Target.Class testName]' passed`) from a test.sh log, and Swift Testing's results
from the xUnit file test.sh writes beside it (`.build/test-results/xunit-swift-testing.xml`, classname `Target.Suite`, name
`testName()`). The two together are the whole run, whichever framework a test is written in, so a migration from XCTest to
Swift Testing is checked by comparing this list before and after: same names, same count, the same skips, nothing failed.

usage: test-names.py <test.sh log> [<xunit xml> ...]     (prints the names; exits 1 if any test failed)
"""
import re
import sys
import xml.etree.ElementTree as ET

names, bad = set(), []
log = open(sys.argv[1], encoding="utf-8", errors="replace").read()
for target, cls, test, outcome in re.findall(r"Test Case '-\[(\w+)\.(\w+) (\w+)\]' (passed|failed|skipped)", log):
    name = f"{target}.{cls}.{test}"
    if outcome == "failed":
        bad.append(name + " failed")
    else:
        names.add(name + ("" if outcome == "passed" else " skipped"))
for path in sys.argv[2:]:
    for case in ET.parse(path).getroot().iter("testcase"):
        name = f"{case.get('classname')}.{re.sub(r'[(].*$', '', case.get('name'))}"
        if case.find("failure") is not None or case.find("error") is not None:
            bad.append(name + " failed")
        elif case.find("skipped") is not None:
            names.add(name + " skipped")
        else:
            names.add(name)
print("\n".join(sorted(names)))
if bad:
    print("\n".join(bad), file=sys.stderr)
    sys.exit(1)
