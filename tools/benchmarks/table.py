import json, sys, pathlib, statistics
d = pathlib.Path(sys.argv[1])
py = json.loads((d / "python.json").read_text())
sw = json.loads((d / "swift-edx.json").read_text()) + json.loads((d / "swift-eels.json").read_text())
pr = {(r["function"], r["size"]): r["python_s"] for r in py["rows"]}
def fmt(ts):
    return f"{statistics.median(ts)*1e3:.2f} ({min(ts)*1e3:.2f}-{max(ts)*1e3:.2f})"
print("| function | size | pixels | Swift CPU, ms median (min-max) | Python, ms median (min-max) | Python / Swift |")
print("|---|---|---|---|---|---|")
for r in sw:
    p = pr.get((r["function"], r["size"]))
    ratio = f"{statistics.median(p)/statistics.median(r['swift_cpu_s']):.2f}" if p else ""
    print(f"| {r['function']} | {r['size']} | {r['pixels']} | {fmt(r['swift_cpu_s'])} | {fmt(p) if p else ''} | {ratio} |")
