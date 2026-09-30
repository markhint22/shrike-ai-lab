#!/usr/bin/env python3
"""Register every scripts/test/test_*.sh that run_all.sh does not yet call (inserted just before the final summary line).
usage: register_new_tests.py [--check]   (--check: only report; exit 1 if any test is unregistered)"""
import os, re, sys
here = os.path.dirname(os.path.abspath(__file__))
p = os.path.join(here, "run_all.sh")
txt = open(p).read()
reg = set(re.findall(r"bash (test_[A-Za-z0-9_.-]+\.sh)", txt))
missing = sorted(f for f in os.listdir(here) if f.startswith("test_") and f.endswith(".sh") and f not in reg)
if "--check" in sys.argv:
    print("unregistered:", " ".join(missing) or "none"); sys.exit(1 if missing else 0)
if missing:
    lines = txt.rstrip("\n").split("\n")
    # drop any misplaced lines after the final `exit $rc`
    idx = max(i for i, l in enumerate(lines) if l.strip() == "exit $rc")
    tail = lines[idx + 1:]
    lines = lines[:idx + 1]
    summary = next(i for i, l in enumerate(lines) if "ALL QUEUE TESTS PASS" in l)
    add = ['echo; echo "===== %s ====="; bash %s || rc=1' % (f[5:-3].replace("_", " "), f) for f in missing]
    lines[summary:summary] = add + [l for l in tail if "bash test_" in l]
    open(p, "w").write("\n".join(lines) + "\n")
print("registered:", " ".join(missing) or "nothing new")
