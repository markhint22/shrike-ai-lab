#!/usr/bin/env python3
"""Tests for qa/qa_gate_precision.py (S8 label-bar tracker + monthly verdict-rule table). Hermetic: QA_STATE_DIR in a private temp dir.
Failure injection (M1..M4): the tool is copied with ONE line changed and the matching assertion must fail against the copy."""
import json
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
OQ = os.path.abspath(os.path.join(HERE, "..", ".."))
QA = os.path.join(OQ, "qa")
TOOL = os.path.join(QA, "qa_gate_precision.py")
P = F = 0


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name + (("  -> " + str(extra)[:400]) if extra else ""))


T = tempfile.mkdtemp(prefix="qa-gateprec-test-")
if not T or os.path.realpath(T) in ("/", os.path.realpath(os.path.expanduser("~"))):
    sys.exit("unsafe temp dir")
ST = os.path.join(T, "state")
os.makedirs(os.path.join(ST, "qa_shadow"))


def wr(rel, rows):
    with open(os.path.join(ST, rel), "w") as f:
        for r in rows:
            f.write(json.dumps(r) + "\n")


def run(args, script=TOOL, env=None):
    e = {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "HOME": T, "NTFY_SERVER": "http://127.0.0.1:9", "QA_STATE_DIR": ST, "TMPDIR": T}
    e.update(env or {})
    p = subprocess.run(["python3", script] + args, cwd=OQ, capture_output=True, text=True, env=e)
    return p.returncode, p.stdout, p.stderr


def mutant(tag, old, new, rel="qa_gate_precision.py"):
    dst = os.path.join(T, "mut_" + tag)
    shutil.copytree(QA, dst, ignore=shutil.ignore_patterns("__pycache__", "acceptance_pilot", "device_lane", "spikes"))
    p = os.path.join(dst, rel)
    s = open(p).read()
    assert s.count(old) == 1, (tag, s.count(old))
    open(p, "w").write(s.replace(old, new))
    return os.path.join(dst, "qa_gate_precision.py")


print("== qa_gate_precision")
# ---- empty state: bar NOT met, 0 labelled
rc, out, err = run([])
ok("empty state: exit 0, 0 labelled, bar NOT MET", rc == 0 and "labelled: 0" in out and "NOT MET" in out and "MET" != out.strip().split()[-1], out)
rc, out, _ = run(["precision", "--json"])
j = json.loads(out)
ok("json: labelled 0, bar_met false, no percentage", j["labelled"] == 0 and j["bar_met"] is False and j["precision"] is None and j["bar_labelled"] == 50 and j["bar_precision"] == 0.6, out)


def finding(i, repo="r"):
    return {"id": "%012x" % i, "file": "app/f%d.py" % i, "line": i, "claim": "c%d" % i, "severity": "medium"}


def reviewer_rows(n):
    return [{"ts": "2026-10-05T10:00:00Z", "gate": "reviewer", "repo": "r", "ref": "h%d" % i, "verdict": "FLAG", "ms": 60000,
             "details": {"findings": [finding(i)], "counts": {"proposed": 2, "verified": 1, "survived": 1}}} for i in range(n)]


def labels(tp, fp, un=0, start=0):
    rows = []
    for i in range(tp):
        rows.append({"ts": "2026-10-06T00:00:00Z", "id": "%012x" % (start + i), "label": "TP"})
    for i in range(fp):
        rows.append({"ts": "2026-10-06T00:00:00Z", "id": "%012x" % (start + tp + i), "label": "FP"})
    for i in range(un):
        rows.append({"ts": "2026-10-06T00:00:00Z", "id": "%012x" % (start + tp + fp + i), "label": "unclear"})
    return rows


def prec(tp, fp, un=0, env=None, script=TOOL):
    wr("qa_shadow/reviewer.jsonl", reviewer_rows(tp + fp + un + 3))
    wr("qa_reviewer_labels.jsonl", labels(tp, fp, un))
    rc, out, _ = run(["precision", "--json"], script=script, env=env)
    return json.loads(out)


r = prec(10, 5)
ok("15 decisive labels: below the 50 bar -> NOT MET even at 67% (insufficient sample, no percentage)", r["bar_met"] is False and r["precision"] is None and "insufficient" in r["status"], r)
r = prec(30, 20)
ok("50 decisive, 60% -> MET (boundary inclusive)", r["bar_met"] is True and r["precision"] == 0.6 and r["status"] == "MET", r)
r = prec(29, 21)
ok("50 decisive, 58% -> NOT MET (precision below 60%)", r["bar_met"] is False and r["precision"] == 0.58 and "precision" in r["status"], r)
r = prec(40, 5, un=30)
ok("unclear labels do not count toward the 50", r["decisive"] == 45 and r["labelled"] == 75 and r["bar_met"] is False, r)
r = prec(49, 0)
ok("49 labels all TP -> NOT MET (one short of the sample bar)", r["bar_met"] is False, r)
rc, out, _ = run(["precision"])
ok("text report states the bar plainly", "bar (>= 50 labelled AND >= 60% precision)" in out and "NOT MET" in out, out)

# ---- mutants of the bar logic
m1 = mutant("M1", "MIN_DECISIVE = 50", "MIN_DECISIVE = 0", rel="qa_reviewer_label.py")
r = prec(10, 5, script=m1)
ok("M1 (mutant: sample minimum of 50 removed) is caught", not (r["bar_met"] is False), r)
m2 = mutant("M2", "rep[\"precision\"] >= BAR_PRECISION)", "rep[\"precision\"] >= 0.0)")
r = prec(29, 21, script=m2)
ok("M2 (mutant: no precision threshold) is caught", not (r["bar_met"] is False), r)

# ---- verdict-rule table
def row(gate, verdict, ms, ts="2026-10-07T12:00:00Z", cpu=None):
    d = {"cpu_s": cpu} if cpu is not None else {}
    return {"ts": ts, "gate": gate, "repo": "r", "verdict": verdict, "ms": ms, "details": d}


wr("qa_shadow/reviewer.jsonl", reviewer_rows(3) + [row("reviewer", "PASS", 120000), row("reviewer", "UNVERIFIED", 60000)])
wr("qa_shadow/scanners.jsonl", [row("scanners", "FLAG", 30000)] * 3 + [row("scanners", "PASS", 30000)] * 30)
wr("qa_shadow/antigaming.jsonl", [row("antigaming", "PASS", 60000)] * 25)       # 25 minutes, 0 catches -> retire?
wr("qa_shadow/mutation.jsonl", [row("mutation", "FLAG", 900000, cpu=120)] * 2 + [row("mutation", "UNVERIFIED", 600000)])
wr("qa_shadow/oldmonth.jsonl", [row("oldmonth", "FLAG", 1000, ts="2026-09-30T23:59:59Z")])
rc, out, _ = run(["verdict-rule", "--month", "2026-10", "--json"])
v = json.loads(out)
g = {x["gate"]: x for x in v["gates"]}
ok("table has one row per gate active in the month; other months excluded", set(g) == {"reviewer", "scanners", "antigaming", "mutation"} and v["month"] == "2026-10", sorted(g))
ok("reviewer is a GPU gate: minutes from ms, catches = FLAG rows, UNVERIFIED counted apart", g["reviewer"]["kind"] == "GPU" and g["reviewer"]["catches"] == 3 and g["reviewer"]["unverified"] == 1
   and g["reviewer"]["minutes"] == 6.0 and g["reviewer"]["catches_per_min"] == 0.5, g["reviewer"])
ok("CPU gate: catches per CPU-minute from wall ms", g["scanners"]["kind"] == "CPU" and g["scanners"]["catches"] == 3 and g["scanners"]["minutes"] == 16.5 and g["scanners"]["catches_per_min"] == 0.182, g["scanners"])
ok("CPU gate with details.cpu_s: cpu seconds win over wall ms", g["mutation"]["minutes"] == round((120 + 120 + 600) / 60.0, 2), g["mutation"])
ok("rule: 25 minutes with 0 catches -> retire?; <20 scored runs -> insufficient data; healthy -> keep",
   g["antigaming"]["rule"] == "retire?" and g["mutation"]["rule"] == "insufficient data" and g["scanners"]["rule"] == "keep", {k: x["rule"] for k, x in g.items()})
wr("qa_shadow/slow.jsonl", [row("slow", "PASS", 60000)] * 19 + [row("slow", "FLAG", 60000)])
rc, out, _ = run(["verdict-rule", "--month", "2026-10", "--json"])
ok("rule: 1 catch in 20 minutes (0.05/min is the line; here 0.05 -> keep, so check just under)", {x["gate"]: x for x in json.loads(out)["gates"]}["slow"]["rule"] == "keep")
rc, out, _ = run(["verdict-rule", "--month", "2026-10", "--json"], env={"QA_RULE_MIN_RATE": "0.2"})
ok("rule: below the configured rate -> weak", {x["gate"]: x for x in json.loads(out)["gates"]}["slow"]["rule"] == "weak")
rc, out, _ = run(["verdict-rule", "--month", "2026-10"])
ok("text table has the header and every gate", "catches/min" in out and "antigaming" in out and "GPU" in out and rc == 0, out)
rc, out, err = run(["verdict-rule", "--month", "bogus"])
ok("bad --month -> usage, exit 2", rc == 2, out + err)
rc, out, _ = run(["verdict-rule", "--month", "2031-01"])
ok("empty month -> says so, exit 0", rc == 0 and "no shadow rows" in out)
rc, out, _ = run(["verdict-rule", "--month", "2026-10", "--json"], env={"OVN_QA_GPU_GATES": "reviewer mutation"})
ok("OVN_QA_GPU_GATES moves a gate to the GPU table", {x["gate"]: x for x in json.loads(out)["gates"]}["mutation"]["kind"] == "GPU")
# corrupt lines never crash it
with open(os.path.join(ST, "qa_shadow", "bad.jsonl"), "w") as f:
    f.write("not json\n{\"ts\": 5}\n\n")
rc, out, _ = run(["verdict-rule", "--month", "2026-10", "--json"])
ok("corrupt/odd rows are ignored, exit 0", rc == 0 and "bad" not in {x["gate"] for x in json.loads(out)["gates"]})

# M3: catches must be FLAG|FAIL, M4: UNVERIFIED must not be a catch
m3 = mutant("M3", 'r["verdict"] in ("FLAG", "FAIL"))\n        unver', 'r["verdict"] in ("FLAG", "FAIL", "PASS"))\n        unver')
rc, out, _ = run(["verdict-rule", "--month", "2026-10", "--json"], script=m3)
ok("M3 (mutant: PASS counted as a catch) is caught", {x["gate"]: x for x in json.loads(out)["gates"]}["scanners"]["catches"] != 3)
m4 = mutant("M4", 'return "retire?"', 'return "keep"')
rc, out, _ = run(["verdict-rule", "--month", "2026-10", "--json"], script=m4)
ok("M4 (mutant: retire rule removed) is caught", {x["gate"]: x for x in json.loads(out)["gates"]}["antigaming"]["rule"] != "retire?")

# ---- D7: an always-green gate is not "weak"; advisory gates get no retire?/weak; skipped passes are visible
def vr(env=None, script=TOOL):
    rc_, out_, _ = run(["verdict-rule", "--month", "2026-10", "--json"], script=script, env=env)
    return {x["gate"]: x for x in json.loads(out_)["gates"]}


wr("qa_shadow/greenish.jsonl", [row("greenish", "PASS", 1000)] * 25)                 # 25 scored runs, 0 catches, 0.4 minutes
wr("qa_shadow/tenmin.jsonl", [row("tenmin", "PASS", 30000)] * 20)                    # exactly 10.0 minutes, 0 catches
wr("qa_shadow/nineish.jsonl", [row("nineish", "PASS", 29900)] * 20)                  # 9.97 minutes, 0 catches
wr("qa_shadow/mutation.jsonl", [row("mutation", "FLAG", 600000, cpu=600)] * 12 + [row("mutation", "PASS", 600000, cpu=600)] * 12)
wr("qa_gate_skips.jsonl", [{"ts": "2026-10-08T08:50:00Z", "gate": "mutation", "reason": "mutmut is not installed"}] * 3 +
   [{"ts": "2026-10-08T08:50:00Z", "gate": "deadgate", "reason": "x"}] * 2 + [{"ts": "2026-09-08T08:50:00Z", "gate": "deadgate", "reason": "old month"}])
g = vr()
ok("D7: a gate that is simply always green (25 PASS, 0 catches, <10 min) is `keep`, not `weak`", g["greenish"]["rule"] == "keep", g["greenish"])
ok("D7: exactly QA_RULE_MIN_MINUTES (10.0) minutes with 0 catches -> retire? (boundary inclusive)", g["tenmin"]["minutes"] == 10.0 and g["tenmin"]["rule"] == "retire?", g["tenmin"])
ok("D7: just under 10 minutes with 0 catches -> keep", g["nineish"]["minutes"] < 10 and g["nineish"]["rule"] == "keep", g["nineish"])
ok("D7: mutation is advisory: FLAG = survivors, so no retire?/weak/keep suggestion", g["mutation"]["rule"].startswith("advisory") and g["mutation"]["catches"] == 12, g["mutation"])
ok("D1: the skipped column counts this month's qa_gate_skips.jsonl rows per gate", g["mutation"]["skipped"] == 3 and g["greenish"]["skipped"] == 0, g["mutation"])
ok("D1: a gate that ONLY skipped (no shadow rows) is still listed: 'no runs (2 skipped)'", g["deadgate"]["runs"] == 0 and g["deadgate"]["skipped"] == 2 and g["deadgate"]["rule"] == "no runs (2 skipped)", g.get("deadgate"))
ok("D7: OVN_QA_ADVISORY_GATES overrides the advisory set", not vr(env={"OVN_QA_ADVISORY_GATES": "none"})["mutation"]["rule"].startswith("advisory"))
rc, out, _ = run(["verdict-rule", "--month", "2026-10"])
ok("text table has the skipped column", "skipped" in out.splitlines()[1] and "no runs (2 skipped)" in out, out)
m5 = mutant("M5", 'minutes >= num("QA_RULE_MIN_MINUTES", 10)', 'minutes > num("QA_RULE_MIN_MINUTES", 10)')
ok("M5 (mutant: retire boundary `>` instead of `>=`) is caught", vr(script=m5)["tenmin"]["rule"] != "retire?")
m6 = mutant("M6", "if catches > 0 and minutes > 0 and catches / minutes", "if minutes > 0 and catches / minutes")
ok("M6 (mutant: 0-catch gate judged weak again) is caught", vr(script=m6)["greenish"]["rule"] != "keep")
m7 = mutant("M7", 'if gate in advisory and rule != "insufficient data":', "if False:")
ok("M7 (mutant: advisory handling removed) is caught", not vr(script=m7)["mutation"]["rule"].startswith("advisory"))
wr("qa_shadow/mutation.jsonl", [row("mutation", "FLAG", 1000)] * 2)
ok("D7: an advisory gate with <20 scored runs still says insufficient data", vr()["mutation"]["rule"] == "insufficient data")
m8 = mutant("M8", "if gate not in seen:", "if False:")
ok("M8 (mutant: skip-only gates dropped from the table) is caught", "deadgate" not in vr(script=m8))
m9 = mutant("M9", 'month_of(r.get("ts")) == month:\n            res[', "True:\n            res[")
ok("M9 (mutant: skips from other months counted) is caught", vr(script=m9)["deadgate"]["skipped"] != 2)

ok("tool is read-only: state dir has no file the tool created", sorted(os.listdir(ST)) == ["qa_gate_skips.jsonl", "qa_reviewer_labels.jsonl", "qa_shadow"])
shutil.rmtree(T, ignore_errors=True)
print("\n%d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
