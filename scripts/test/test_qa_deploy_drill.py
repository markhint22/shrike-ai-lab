#!/usr/bin/env python3
"""Tests for qa/deploy_drill.py (Phase 4 broken-deploy drill). Hermetic: the drill itself only talks to a loopback stub. The acceptance bar:
4 of 4 injected failure classes would hold the promote with the gate in ENFORCE mode on fixtures; the control (clean) must not be held; removing the CORS check from the
probe must make the drill report 'would not hold'; nothing real (staging, prod, state dir, credentials) is touched or printed."""
import contextlib, io, json, os, sys, tempfile
import os as _o, sys as _s; _s.path.insert(0, _o.path.dirname(_o.path.abspath(__file__))); import tmp_track; tmp_track.install()   # 2026-10-17: every mkdtemp() below is removed at exit (the suite leaked these dirs)

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
QA = os.path.join(ROOT, "qa")
sys.path.insert(0, QA)
P = F = 0


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name + ((" :: " + str(extra)[:300]) if extra else ""))


T = tempfile.mkdtemp(prefix="drill-test-")
REAL_STATE = os.path.join(T, "realstate")      # stands for the box's state dir: the drill must leave it untouched
os.makedirs(REAL_STATE)
os.environ.update({"QA_STATE_DIR": REAL_STATE, "OVN_DIR": T, "HOME": T})
for k in ("QA_SMOKE_ALLOW_LOCAL", "OVN_QA_SOAK", "OVN_QA_SOAK_MIN_HOURS", "OVN_QA_SOAK_ENFORCE_REPOS", "QA_SMOKE_DRILL_EMAIL", "QA_SMOKE_DRILL_PASSWORD"):
    os.environ.pop(k, None)

import staging_smoke as ss        # noqa: E402
import promote_gate as pg         # noqa: E402
import deploy_drill as dd         # noqa: E402

# every HTTP request the drill makes must go to loopback: a guard under the probe's own tracing wrapper
seen_hosts = []
orig_http = ss.http


def guarded_http(method, url, *a, **k):
    import urllib.parse
    seen_hosts.append(urllib.parse.urlparse(url).hostname)
    if urllib.parse.urlparse(url).hostname != "127.0.0.1":
        raise AssertionError("drill tried to reach %s" % url)
    return orig_http(method, url, *a, **k)


ss.http = guarded_http

print("== default drill (min 2.0 h, 12 samples, 15 min apart)")
rep = dd.run_drill()
by = {c["class"]: c for c in rep["classes"]}
ok("verdict PASS: 4 of 4 injected failure classes would hold the promote", rep["verdict"] == "PASS" and rep["classes_held"] == 4 and rep["classes_required"] == 4 and rep["not_held"] == [], rep["summary"])
for n in dd.REQUIRED:
    ok("%s: held with the gate in ENFORCE mode (soak and/or staging_check)" % n, by[n]["held"] and by[n]["expected_held"], by[n])
    ok("%s: the soak summary says FAIL/HOLD on the last sample and the promote never passed" % n, by[n]["last_decision"] == "HOLD" and by[n]["promote_passes_at_sample"] is None, by[n])
ok("control (clean stub) is NOT held: promote proceeds once min hours of clean samples exist", by["control_clean"]["promote_passes_at_sample"] == 8 and rep["control_proceeds"], by["control_clean"])
ok("control: every sample PASS (no false positive from the probe itself)", set(by["control_clean"]["sample_verdicts"]) == {"PASS"}, by["control_clean"]["sample_verdicts"])
ok("stale_sha is ALSO held by the real staging_check -> promote_gate.decide_block (MISMATCH_BEHIND, block true)",
   by["stale_sha"]["staging_check"]["relation"] == "MISMATCH_BEHIND" and by["stale_sha"]["staging_check"]["block"] is True, by["stale_sha"]["staging_check"])
ok("slow (informational) is held too", by["slow"]["held"])
ok("late_onset (failure after 1.25 h) is held at the 2.0 h minimum, detected after 1.25 h", by["late_onset"]["held"] and by["late_onset"]["detected_after_h"] == 1.25 and rep["late_onset_held_at_min"], by["late_onset"])
ok("recommended minimum = slowest detection + one interval, rounded up to 15 min = 1.5 h (and the default 2.0 covers it)", rep["recommended_min_hours"] == 1.5 and rep["min_hours"] >= rep["recommended_min_hours"], rep["recommended_min_hours"])
pc = {c["case"][:20]: c for c in rep["postcheck"]}
ok("postcheck: a FAILED prod deploy of the promoted sha is detected (FAILED), the missing deploy is never SUCCESS, the healthy control is SUCCESS",
   rep["postcheck"][0]["status"] == "FAILED" and rep["postcheck"][0]["detects"] and rep["postcheck"][1]["status"] is None and rep["postcheck"][1]["detects"]
   and rep["postcheck"][2]["status"] == "SUCCESS" and not rep["postcheck"][2]["detects"], rep["postcheck"])

print("== unreachable staging / dead probe after a clean streak (the PASS-during-outage hole)")
oc, dp = by["outage_after_clean"], by["dead_probe"]
ok("outage_after_clean: 9 clean samples, then 7 UNVERIFIED (staging drops every connection) - the promote attempted after the outage is HELD",
   oc["sample_verdicts"][:9] == ["PASS"] * 9 and set(oc["sample_verdicts"][9:]) == {"UNVERIFIED"} and oc["blocked_at_end"] and oc["held"] and oc["last_decision"] == "HOLD" and oc["stale"], oc)
ok("outage_after_clean: the promote legitimately passed BEFORE the outage (2 h clean at sample 8), so the class is judged at the end of the replay", oc["promote_passes_at_sample"] == 8)
ok("dead_probe: 2 h clean, then the cron stops writing rows - the summary read 1.75 h later is HELD (stale)", dp["blocked_at_end"] and dp["held"] and dp["stale"] and dp["last_decision"] == "HOLD", dp)
ok("both outage classes are reported and counted: rep['outage_not_held'] is empty", rep["outage_not_held"] == [], rep["outage_not_held"])
r7 = dd.run_drill(mutant="recency")
ok("mutant: remove the recency check from the summary -> the drill reports 'would not hold: outage_after_clean, dead_probe', verdict FAIL",
   r7["verdict"] == "FAIL" and r7["outage_not_held"] == ["outage_after_clean", "dead_probe"] and "would not hold" in r7["summary"] and "outage_after_clean" in r7["summary"], r7["summary"])
ok("the recency mutant leaves the 4 required classes held (it points at the missing check only)", r7["classes_held"] == 4)
import soak_probe as _sp
ok("the mutant restores the real STALE_FACTOR afterwards", _sp.STALE_FACTOR == 3)

print("== remove_own_state only deletes the drill's own private temp dir")
good = tempfile.mkdtemp(prefix="drill-state-")
ok("own drill-state-* dir directly under the temp root is removed", dd.remove_own_state(good) is True and not os.path.exists(good))
other = tempfile.mkdtemp(prefix="keepme-")
ok("a dir with another name is refused and kept", dd.remove_own_state(other) is False and os.path.isdir(other))
ok("a relative path is refused", dd.remove_own_state("drill-state-x") is False)
nested = os.path.join(other, "drill-state-nested")
os.makedirs(nested)
ok("a drill-state-* dir that is NOT a direct child of the temp root is refused and kept", dd.remove_own_state(nested) is False and os.path.isdir(nested))
victim = tempfile.mkdtemp(prefix="victim-")
link = os.path.join(tempfile.gettempdir(), "drill-state-link-%d" % os.getpid())
os.symlink(victim, link)
ok("a symlink named drill-state-* is refused (its target survives)", dd.remove_own_state(link) is False and os.path.isdir(victim))
os.unlink(link)
ok("a path that does not exist is refused", dd.remove_own_state(os.path.join(tempfile.gettempdir(), "drill-state-nope-%d" % os.getpid())) is False)
leftovers = [n for n in os.listdir(tempfile.gettempdir()) if n.startswith("drill-state-") and "link" not in n]
ok("a full drill leaves no drill-state-* dir behind in the temp root", not any(os.path.getmtime(os.path.join(tempfile.gettempdir(), n)) > __import__("time").time() - 600 for n in leftovers), leftovers[:3])

print("== safety: loopback only, no real state, no secrets")
ok("every request went to 127.0.0.1", set(seen_hosts) == {"127.0.0.1"} and len(seen_hosts) > 50, set(seen_hosts))
ok("report says it touched neither real staging nor prod", rep["touched_real_staging_or_prod"] is False)
ok("the drill wrote nothing into the caller's QA_STATE_DIR", os.listdir(REAL_STATE) == [], os.listdir(REAL_STATE))
ok("QA_SMOKE_ALLOW_LOCAL / QA_STATE_DIR / creds env are restored after the drill", "QA_SMOKE_ALLOW_LOCAL" not in os.environ and os.environ["QA_STATE_DIR"] == REAL_STATE
   and "QA_SMOKE_DRILL_PASSWORD" not in os.environ)
blob = json.dumps(rep)
ok("no password / token / email of the stub run appears in the report", "stub-token" not in blob and "@example.com" not in blob and ss.SECRETS and all(s not in blob for s in ss.SECRETS if len(s) >= 6), [s for s in ss.SECRETS if s in blob][:2])
ok("synthetic timestamps: the drill does not depend on the wall clock", rep["classes"][0]["sample_verdicts"] == ["PASS"] * 12)
ok("outside a drill the probe still refuses loopback (the allow-list is only opened inside the drill)", not ss.is_staging("http://127.0.0.1:9"))

print("== the gate chain is what holds: break it and the drill must notice")
real = pg.decide_soak_block
pg.decide_soak_block = lambda *a, **k: False
try:
    r2 = dd.run_drill(mutant="")
finally:
    pg.decide_soak_block = real
ok("mutant: promote_gate.decide_soak_block never blocking -> the soak-only classes would NOT hold, verdict FAIL",
   r2["verdict"] == "FAIL" and set(r2["not_held"]) >= {"health_500", "cors_failure", "readback_failure"}, r2["summary"])
ok("mutant: stale_sha is still held by the staging_check layer (defence in depth)", "stale_sha" not in r2["not_held"], r2["not_held"])

print("== mutant: remove the CORS check from the probe")
r3 = dd.run_drill(mutant="cors")
ok("drill reports 'would not hold: cors_failure', 3 of 4, verdict FAIL", r3["verdict"] == "FAIL" and "would not hold" in r3["summary"] and r3["not_held"] == ["cors_failure"]
   and r3["classes_held"] == 3, r3["summary"])
r4 = dd.run_drill(mutant="write_read")
ok("mutant: remove the write/read-back: 'would not hold: readback_failure'", r4["verdict"] == "FAIL" and r4["not_held"] == ["readback_failure"] and "would not hold" in r4["summary"], r4["summary"])
ok("the other three classes are still held under each mutant (the drill points at the missing check, nothing else)", r3["classes_held"] == 3 and r4["classes_held"] == 3)

print("== the soak minimum matters: too short and a late-onset failure slips through")
r5 = dd.run_drill(min_h=1.0)
ok("min 1.0 h: FLAG, the promote passes at sample 4 (before the 1.25 h onset), recommends >= 1.5 h", r5["verdict"] == "FLAG" and not r5["late_onset_held_at_min"]
   and {c["class"]: c for c in r5["classes"]}["late_onset"]["promote_passes_at_sample"] == 4 and "1.50" in r5["summary"], r5["summary"])
r6 = dd.run_drill(min_h=4.0, samples=12)
ok("min 4.0 h with only 3 h of samples: even the control is blocked -> FAIL (a gate that never lets anything through is reported as a false positive)", r6["verdict"] == "FAIL" and not r6["control_proceeds"], r6["summary"])

print("== CLI")
import subprocess
env = {"PATH": os.environ["PATH"], "HOME": T, "TMPDIR": os.environ.get("TMPDIR", T), "QA_STATE_DIR": os.path.join(T, "cli_state"), "OVN_DIR": T}
p = subprocess.run([sys.executable, os.path.join(QA, "deploy_drill.py"), "run"], env=env, capture_output=True, text=True, timeout=180)
out = json.loads(p.stdout.strip().splitlines()[-1])
ok("CLI: exit 0, verdict PASS, one JSON line", p.returncode == 0 and out["verdict"] == "PASS", p.stdout[-200:] + p.stderr[-200:])
rows = [json.loads(l) for l in open(os.path.join(T, "cli_state", "qa_shadow", "deploy_drill.jsonl"))]
ok("CLI: the result is shadow-recorded (gate deploy_drill, mode shadow)", len(rows) == 1 and rows[0]["gate"] == "deploy_drill" and rows[0]["mode"] == "shadow" and rows[0]["verdict"] == "PASS", rows)
p = subprocess.run([sys.executable, os.path.join(QA, "deploy_drill.py"), "run", "--mutant", "cors"], env=env, capture_output=True, text=True, timeout=180)
out = json.loads(p.stdout.strip().splitlines()[-1])
ok("CLI --mutant cors: exit 0, FAIL, 'would not hold', NOT recorded (a mutant run never pollutes the shadow log)", p.returncode == 0 and out["verdict"] == "FAIL" and "would not hold" in out["summary"]
   and len(open(os.path.join(T, "cli_state", "qa_shadow", "deploy_drill.jsonl")).readlines()) == 1, out.get("summary"))
p = subprocess.run([sys.executable, os.path.join(QA, "deploy_drill.py"), "run", "--no-record"], env=dict(env, QA_STATE_DIR=os.path.join(T, "nr_state")), capture_output=True, text=True, timeout=180)
ok("CLI --no-record writes no state", p.returncode == 0 and not os.path.exists(os.path.join(T, "nr_state")))
p = subprocess.run([sys.executable, os.path.join(QA, "deploy_drill.py")], env=env, capture_output=True, text=True, timeout=30)
ok("CLI without arguments prints the usage and exits 0", p.returncode == 0 and "BROKEN-DEPLOY DRILL" in p.stdout)

print("\n%d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
