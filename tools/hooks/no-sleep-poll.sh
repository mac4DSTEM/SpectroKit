#!/bin/bash
# PreToolUse hook (matcher "Bash"): refuses sleep and poll loops. Reads the hook JSON on stdin, takes .tool_input.command.
# Refused with exit 2 (stderr goes to the agent): (1) any `sleep` of 30 s or more (`sleep 45`, `sleep 1m`, `sleep 0.5h`,
# `/bin/sleep 120`, also inside && / ; chains); (2) a `while` or `until` loop with `sleep` anywhere in the command, any length.
# Everything else passes (`sleep 1`, `sleep 5`, `git log`). Matched as text, not parsed: a sleep right after a
# quote passes, a quoted sleep after a space is refused (accepted false positive).
# Also refused (2026-10-15, after two machine-wide kills of other sessions' test runs on the night of 2026-10-14):
# (3) `killall`, any form; (4) `pkill` unless it names a parent pid (`-P <pid>`) or its pattern is this session's own (holds
# a session uuid or a `scratchpad/` path). A plain `kill <pid>` passes.
# Wait on background-task notifications (Bash run_in_background) or the Monitor tool instead.
exec /usr/bin/python3 -I -c '
import json, re, sys
try:
    cmd = json.load(sys.stdin).get("tool_input", {}).get("command", "")
except Exception:
    sys.exit(0)
if not isinstance(cmd, str):
    sys.exit(0)
msg = ("Refused by tools/hooks/no-sleep-poll.sh: %s. Do not sleep or poll. Run the job with Bash run_in_background "
       "and wait for its completion notification, or use the Monitor tool (an until-loop inside Monitor is its job).")
sleeps = list(re.finditer(r"(?:^|[\s;&|()`{])(?:/\S*/)?sleep\s+([0-9]*\.?[0-9]+)([smhd]?)(?![\w.])", cmd))
if re.search(r"\b(?:while|until)\b", cmd) and re.search(r"(?:^|[\s;&|()`{])(?:/\S*/)?sleep\b", cmd):
    print(msg % "a while/until loop containing sleep", file=sys.stderr); sys.exit(2)
kills = r"(?:^|[\s;&|()`{])(?:/\S*/)?%s\b"
if re.search(kills % "killall", cmd):
    print(msg.split(". Do not")[0] % "killall kills by name, in every session" +
          ". Kill your own job by pid (kill <pid>), or let it finish.", file=sys.stderr); sys.exit(2)
if re.search(kills % "pkill", cmd) and not re.search(
        r"-P\s*\d+|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}|scratchpad/", cmd):
    print(msg.split(". Do not")[0] % "pkill without a pid or a session-specific pattern matches the processes of other sessions" +
          ". Use kill <pid>, pkill -P <pid>, or a pattern holding the session uuid or scratchpad path.", file=sys.stderr)
    sys.exit(2)
for m in sleeps:
    secs = float(m.group(1)) * {"": 1, "s": 1, "m": 60, "h": 3600, "d": 86400}[m.group(2)]
    if secs >= 30:
        print(msg % ("sleep of %g s (limit: under 30 s)" % secs), file=sys.stderr); sys.exit(2)
sys.exit(0)
'
