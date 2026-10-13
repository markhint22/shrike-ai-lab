#!/usr/bin/env python3
"""R14 verify package (2026-10-12): ovn_verify_audit.py classifies credited items by stated polarity vs a fresh re-run on a git-archive copy of the ref (fixture repo)."""
import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "..", "ovn_verify_audit.py")
P = F = 0


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name + ((" :: " + str(extra)[:300]) if extra else ""))


repo = os.path.join(tempfile.mkdtemp(prefix="audit-"), "xlite")
os.makedirs(os.path.join(repo, "scripts"))
os.makedirs(os.path.join(repo, "tests"))
open(os.path.join(repo, "scripts", "aoe.gd"), "w").write("static func is_destructible_type(x):\n\treturn true\n")
open(os.path.join(repo, "scripts", "cell_ring.gd"), "w").write("pass\n")
open(os.path.join(repo, "tests", "t.gd"), "w").write("CellRing\n")


def item(text, verify, x="x", extra=""):
    return "- [%s] %s[T2] scripts/a.gd — %s VERIFY: %s (cat:gd; multifile:no)\n" % (x, extra, text, verify)


PROBE = tempfile.mkdtemp(prefix="audprobe-")   # OUTSIDE the audited tree: nothing the audit runs may ever create a file here
NARR = " returns no matches."
prog = "".join([
    item("A false credit: symbol still present", '`grep -n "is_destructible_type" scripts/aoe.gd` returns no matches.', extra="(pre-verified: VERIFY already passed against current code) "),
    item("B true credit: symbol absent", '`grep -n "gone_symbol" scripts/aoe.gd` returns no matches.'),
    item("C false credit: file still exists", '`ls scripts/cell_ring.gd` fails with "No such file or directory".'),
    item("D true credit: file absent", '`ls scripts/gone.gd` fails with "No such file or directory".'),
    item("E positive ok", '`grep -n "is_destructible_type" scripts/aoe.gd`'),
    item("F positive but fails now", '`grep -n "vanished" scripts/aoe.gd`'),
    item("G runner", '`pytest tests/x.py`'),
    item("H gut without engine", '`godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/t.gd`'),
    item("I still open (not audited)", '`grep -n "is_destructible_type" scripts/aoe.gd` returns no matches.', x=" "),
    item("K stage error: earlier grep on a missing dir", '`grep -n "x" scripts/nodir | grep -v "y"` returns no lines.'),
    item("L cd into a missing dir then grep", '`cd nodir_zz && grep -n "x" aoe.gd` returns no matches.'),
    item("M grep on a missing file", '`grep -n "x" scripts/missing_file.gd` returns no matches.'),
    item("N self-referential recursive grep", '`grep -rn "SELFREFTOKEN_9f3a" .` returns no matches.'),
    item("Delete scripts/gone2.gd (the item deletes the file the grep names)", '`grep -n "x" scripts/gone2.gd` returns no matches.'),
    item("P tee escape", '`echo hi | tee %s/w_tee | grep -q hi`%s' % (PROBE, NARR)),
    item("Q touch escape", '`touch %s/w_touch; ls scripts/aoe.gd`%s' % (PROBE, NARR)),
    item("R sed -i escape", '`sed -i s/a/b/ scripts/aoe.gd; grep -c b scripts/aoe.gd`%s' % NARR),
    item("S find -delete escape", '`find scripts -name cell_ring.gd -delete; ls scripts/cell_ring.gd`%s' % NARR),
    item("T python escape", '`python3 -c "open(\'%s/w_py\',\'w\')"; ls scripts/aoe.gd`%s' % (PROBE, NARR)),
    item("U nc escape", '`nc -l 1 | grep x`%s' % NARR),
    item("V ssh escape", '`ssh localhost true; ls scripts/aoe.gd`%s' % NARR),
    item("W git checkout escape", '`git checkout -- scripts/aoe.gd; ls scripts/aoe.gd`%s' % NARR),
    item("X pytest escape", '`pytest --collect-only tests; ls scripts/aoe.gd`%s' % NARR),
    item("Y command substitution", '`ls $(touch %s/w_sub)`%s' % (PROBE, NARR)),
    item("Z redirect", '`ls scripts/aoe.gd > %s/w_redir`%s' % (PROBE, NARR)),
    "- [x] [T2] scripts/a.gd — J bare false credit. VERIFY: grep -n \"is_destructible_type\" scripts/aoe.gd returns no results. (cat:gd)\n",
])
open(os.path.join(repo, "OVERNIGHT_PROGRESS.md"), "w").write(prog)
open(os.path.join(repo, "OVERNIGHT_DONE.md"), "w").write(item("A false credit: symbol still present", '`grep -n "is_destructible_type" scripts/aoe.gd` returns no matches.', extra="(pre-verified: VERIFY already passed against current code) "))
G = ["git", "-C", repo, "-c", "user.name=t", "-c", "user.email=t@t"]
subprocess.run(G[:3] + ["init", "-q", "-b", "main"], check=True)
subprocess.run(G + ["add", "-A"], check=True)
subprocess.run(G + ["commit", "-qm", "x"], check=True)
out = os.path.join(os.path.dirname(repo), "out")
r = subprocess.run([sys.executable, TOOL, "--repo", "xlite=" + repo, "--ref", "main", "--md", out + ".md", "--json", out + ".json"], capture_output=True, text=True)
ok("exit 0", r.returncode == 0, r.stderr)
rows = json.load(open(out + ".json"))["rows"]
by = {("O" if x["item"].split("— ", 1)[1].startswith("Delete scripts/gone2") else x["item"].split("— ", 1)[1][:1]): x["class"] for x in rows}
ok("A (symbol present, 'returns no matches') = FALSE-CREDIT", by.get("A") == "FALSE-CREDIT", by)
ok("B (symbol absent) = OK", by.get("B") == "OK", by)
ok("C (file exists, 'fails with No such file') = FALSE-CREDIT", by.get("C") == "FALSE-CREDIT", by)
ok("D (file absent) = OK", by.get("D") == "OK", by)
ok("E (positive, passes) = OK", by.get("E") == "OK", by)
ok("F (positive, fails now) = FAILS-NOW (informational)", by.get("F") == "FAILS-NOW", by)
ok("G (pytest) = CANNOT-RUN", by.get("G") == "CANNOT-RUN", by)
ok("H (godot without an engine) = CANNOT-RUN", by.get("H") == "CANNOT-RUN", by)
ok("I (still open) is not audited", "I" not in by, by)
ok("J (bare 'returns no results', symbol present) = FALSE-CREDIT", by.get("J") == "FALSE-CREDIT", by)
for k, why in (("K", "earlier-stage grep error"), ("L", "cd into a missing dir"), ("M", "grep rc 2 on a missing file")):
    ok("%s (%s) is CANNOT-RUN, never a FALSE-CREDIT / OK" % (k, why), by.get(k) == "CANNOT-RUN", by)
ok("N (self-referential grep -r '.'): the queue files are excluded from the audited copy -> OK, not FALSE-CREDIT", by.get("N") == "OK", by)
ok("O (the item deletes the file the grep names, rc 2) = OK (satisfied-absent, no livelock)", by.get("O") == "OK", by)
for k in "PQRSTUVWXYZ":
    ok("%s (escape probe) is CANNOT-RUN and was never executed" % k, by.get(k) == "CANNOT-RUN", by)
ok("NOTHING was created outside the scratch by any probe", os.listdir(PROBE) == [], os.listdir(PROBE))
ok("the probe commands did not modify the repo either (sed -i / find -delete / git checkout)", open(os.path.join(repo, "scripts", "aoe.gd")).read().startswith("static func is_destructible_type") and os.path.exists(os.path.join(repo, "scripts", "cell_ring.gd")))
ok("an item present in PROGRESS and DONE is judged once", sum(1 for x in rows if "A false" in x["item"]) == 1, rows)
md = open(out + ".md").read()
ok("the markdown lists the false credits with their VERIFY and flags the pre-verified one", "FALSE-CREDIT (3)" in md and "is_destructible_type" in md and "| yes |" in md, md[:900])
ok("the repo was only read: its working tree is untouched", subprocess.run(["git", "-C", repo, "status", "--porcelain"], capture_output=True, text=True).stdout.strip() == "")
print("\n%d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
