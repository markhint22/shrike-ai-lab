#!/usr/bin/env python3
"""Intake package (2026-10-13), platform P8: ovn_daily_fail_digest reports per (repo, cmd) the FINAL result and the count of distinct commands whose last result is FAIL.
state/verify_gate_shadow.log is every VERIFY EXECUTION, so raw FAIL rows inflate the picture (116 FAIL of 153 rows: ~54 of them three unwinnable clauses retried every 10-20 minutes, and
many commands go FAIL then PASS = a healthy red-before / green-after). Rows from non-fleet repo labels (a test run that wrote into the live state dir) are labelled, never counted.
Mutation proofs: ordering by (ts, seq) replaced by file order, the fleet filter removed, `last` taken from the first row."""
import atexit
import json
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SD = os.path.abspath(os.path.join(HERE, ".."))
sys.path.insert(0, SD)
import ovn_daily_fail_digest as D  # noqa: E402

P = F = 0


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name + ((" :: " + str(extra)[:400]) if extra else ""))


NOW = 1760000000.0


def iso(h_ago):
    return D.time.strftime("%Y-%m-%dT%H:%M:%SZ", D.time.gmtime(NOW - h_ago * 3600))


st = tempfile.mkdtemp(prefix="digest-intake-")
atexit.register(shutil.rmtree, st, True)   # 2026-10-17: both mkdtemp dirs were left behind
with open(os.path.join(st, "outcomes.jsonl"), "w") as f:
    f.write(json.dumps({"ts": iso(1), "repo": "xlite", "class": "landed", "status": "pushed(tests:pass)"}) + "\n")
G = "godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_x.gd -gexit"
rows = [
    # an unwinnable clause rechecked 5 times: ends on FAIL
    *[(10 - i, "xlite", "2812", "FAIL", "cd /path/to/xlite && godot --headless -s addons/gut/gut_cmdln.gd -gexit", " rc=1", " tail=bash: cd: /path/to/xlite: No such file") for i in range(5)],
    # healthy red-before then green-after
    (9, "iptv_apps", "2300", "FAIL", "test -f iptv-backend/x.py", " rc=1", " tail=x"),
    (3, "iptv_apps", "2300", "PASS", "test -f iptv-backend/x.py", "", ""),
    (9, "gitlark", "12", "FAIL", "pytest tests/test_b.py -q", " rc=1", " tail=x"),
    (3, "gitlark", "12", "PASS", "pytest tests/test_b.py -q", "", ""),
    # P-only
    *[(8 - i, "iptv_apps", "2310", "PASS", "grep -n _catalog_cache.clear() a.py", "", "") for i in range(4)],
    # PASS then FAIL (a regression): ends on FAIL
    (7, "billwatch", "11", "PASS", "pytest tests/test_a.py -q", "", ""),
    (2, "billwatch", "11", "FAIL", "pytest tests/test_a.py -q", " rc=1", " tail=boom"),
    # same command in ANOTHER repo is a separate key
    (6, "gitlark", "11", "PASS", "pytest tests/test_a.py -q", "", ""),
    # an indeterminate last result is neither PASS nor FAIL
    (5, "xlite", "40", "UNRUNNABLE", G, " rc=127", " tail=GUT-not-imported"),
    # test pollution: labels that are not fleet repos
    (4, "tmp.AbC123", "1", "FAIL", "pytest", " rc=1", " tail=x"),
    (4, "dbgcredit", "1", "PASS", "true", "", ""),
]
with open(os.path.join(st, "verify_gate_shadow.log"), "w") as f:
    for h, repo, ln, res, cmd, rc, tail in sorted(rows, key=lambda r: -r[0]):
        f.write("%s repo=%s line=%s result=%s%s cmd=%s%s\n" % (iso(h), repo, ln, res, rc, cmd, tail))
    f.write("%s repo=xlite line=9 path_gate=OK target=a.gd\n" % iso(2))
d = D.build(st, 24, NOW, 10)
vs = d["verify_shadow"]
print("== final result per (repo, cmd)")
ok("fleet rows only: 5 + 2 + 2 + 4 + 2 + 1 + 1 = 17 result rows + 1 path_gate row = 18", vs["rows"] == 18, vs["rows"])
ok("raw FAIL rows (5 + 1 + 1 + 1) overstate: 8 FAIL rows", vs["results"].get("result=FAIL") == 8, vs["results"])
ok("[P8] distinct commands = 7 (the same pytest line in two repos is two keys)", vs["distinct_cmds"] == 7, vs["distinct_cmds"])
ok("[P8] distinct commands whose LAST result is FAIL = 2 (the unwinnable cd clause, the billwatch regression)", vs["distinct_cmds_last_fail"] == 2, vs)
ok("[P8] final results: PASS 4 (iptv 2300, iptv 2310, gitlark x2), FAIL 2, UNRUNNABLE 1", vs["final"] == {"result=FAIL": 2, "result=PASS": 4, "result=UNRUNNABLE": 1}, vs["final"])
ok("[P8] FAIL then PASS (healthy red-before / green-after) = 2", vs["fail_then_pass"] == 2, vs["fail_then_pass"])
lf = {x["repo"]: x for x in vs["last_fail"]}
ok("the still-failing list is ordered by rows: the 5-row unwinnable clause first", vs["last_fail"][0]["repo"] == "xlite" and vs["last_fail"][0]["rows"] == 5 and vs["last_fail"][0]["fails"] == 5 and vs["last_fail"][0]["lines"] == ["2812"], vs["last_fail"])
bw = lf.get("billwatch", {})
ok("the regression (PASS then FAIL) is in the list with its last timestamp", bw.get("rows") == 2 and bw.get("fails") == 1 and bw.get("last_ts") == iso(2), bw)
ok("[mut] an item whose last row is PASS never appears in the still-failing list", "iptv_apps" not in lf)

print("== non-fleet repo labels are labelled, not counted")
ok("[P8] 2 foreign rows, by label", vs["foreign_rows"] == 2 and vs["foreign_labels"] == {"dbgcredit": 1, "tmp.AbC123": 1}, vs)
ok("[mut] the foreign FAIL row is not in the FAIL count and its command is not a distinct command", vs["results"].get("result=FAIL") == 8 and all(x["repo"] != "tmp.AbC123" for x in vs["last_fail"]))
ok("a repo seen in the outcomes is a fleet repo even when it is not in the built-in list",
   D.build(st, 24, NOW, 10)["verify_shadow"]["foreign_labels"].get("xlite") is None)
st2 = tempfile.mkdtemp(prefix="digest-intake2-")
atexit.register(shutil.rmtree, st2, True)
with open(os.path.join(st2, "outcomes.jsonl"), "w") as f:
    f.write(json.dumps({"ts": iso(1), "repo": "newrepo", "class": "landed", "status": "pushed(tests:pass)"}) + "\n")
with open(os.path.join(st2, "verify_gate_shadow.log"), "w") as f:
    f.write("%s repo=newrepo line=1 result=FAIL rc=1 cmd=pytest -q tail=x\n" % iso(2))
ok("... newrepo (only in outcomes) is counted", D.build(st2, 24, NOW, 10)["verify_shadow"]["rows"] == 1)

print("== markdown")
md = D.markdown(d, 10)
ok("markdown states that these are executions, the distinct-command final counts and the still-failing commands",
   "These are VERIFY executions, not items. 7 distinct command(s)" in md and "**2 end on FAIL**" in md and "2 went FAIL then PASS" in md and "cd /path/to/xlite && godot" in md, md)
ok("markdown warns about the non-fleet labels and says they are not counted", "WARNING: 2 row(s) from non-fleet repo labels (dbgcredit 1, tmp.AbC123 1), NOT counted above" in md, md)
r = subprocess.run([sys.executable, os.path.join(SD, "ovn_daily_fail_digest.py"), "--state-dir", st, "--now", str(NOW), "--json"], capture_output=True, text=True)
ok("--json carries distinct_cmds_last_fail", json.loads(r.stdout)["verify_shadow"]["distinct_cmds_last_fail"] == 2, r.stderr)

print("intake digest: %d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
