#!/usr/bin/env python3
"""qa/evidence_freshness_check.py (QA-N1 / folded QA-N4, 2026-10-09): stale promote evidence is turned into ONE alerts.log WARN per stale source per 6 h, with the fix in the line.

Time is INJECTED (run(state, now=...), EVIDENCE_FRESHNESS_NOW for the CLI): nothing sleeps, nothing depends on the wall clock. Sources: the Mac deploy export (30 min),
one repo's export file, the Mac e2e result and the box e2e result (12 h). Negative controls: every stale source alerts; fresh sources are silent; the alert is NOT repeated
inside 6 h and IS repeated after; a recovered source is forgotten (the next outage alerts at once); hostile files never crash it. A mutation section breaks each piece of
logic in a temp copy and shows the scenario then fails."""
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
OQ = os.path.abspath(os.path.join(HERE, "..", ".."))
QA = os.path.join(OQ, "qa")
PY = sys.executable
if not os.path.isfile(os.path.join(QA, "evidence_freshness_check.py")):
    print("  SKIP: qa/evidence_freshness_check.py not installed here")
    sys.exit(0)

P = F = 0


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name + ((" :: " + str(extra)[:400]) if extra else ""))


T = os.path.realpath(tempfile.mkdtemp(prefix="evfresh-test-"))
for k in ("OVN_QA_STAGING_E2E", "QA_STAGING_MAX_AGE_S", "EVIDENCE_FRESHNESS_NOW", "OVN_EVIDENCE_FRESHNESS", "QA_STATE_DIR", "OVN_DIR"):
    os.environ.pop(k, None)


def load(path, name):
    d = os.path.dirname(path)
    if d not in sys.path:
        sys.path.insert(0, d)
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


FM = load(os.path.join(QA, "evidence_freshness_check.py"), "fresh_under_test")
NOW = 1_800_000_000.0
H = 3600.0


def iso(t):
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(t))


def mkstate(name, deploy_ages=None, mac_age=0.0, box_age=0.0):
    """deploy_ages: {repo: seconds old} (None = no staging_deploys dir); mac_age / box_age: seconds old (None = file missing)."""
    d = os.path.join(T, name)
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d)
    if deploy_ages is not None:
        os.makedirs(os.path.join(d, "staging_deploys"))
        for repo, age in deploy_ages.items():
            json.dump({"repo": repo, "fetched_at": NOW - age, "deployments": [{"id": "x", "status": "SUCCESS"}]}, open(os.path.join(d, "staging_deploys", repo + ".json"), "w"))
    if mac_age is not None:
        json.dump({"ts": iso(NOW - mac_age), "passed": 17, "total": 17, "failed": []}, open(os.path.join(d, "qa_staging_e2e.json"), "w"))
    if box_age is not None:
        json.dump({"ts": iso(NOW - box_age), "cells": []}, open(os.path.join(d, "staging_e2e_box.json"), "w"))
    return d


def keys(d, mod=None, **kw):
    return sorted(k for k, _ in (mod or FM).stale_sources(d, NOW, **kw))


ALL3 = {"billwatch": 100.0, "gitlark": 200.0, "iptv_apps": 300.0}
print("# 1. what counts as stale")
ok("everything fresh => nothing stale", keys(mkstate("fresh", ALL3, 3 * H, 2 * H)) == [])
ok("boundaries: deploy export 29 min and e2e 11 h 59 min are fresh", keys(mkstate("edge_ok", {"iptv_apps": 1740.0}, 12 * H - 60, 12 * H - 60)) == [])
ok("boundaries: deploy export 31 min and e2e 12 h 1 min are stale", keys(mkstate("edge_bad", {"iptv_apps": 1860.0}, 12 * H + 60, 12 * H + 60)) == ["deploy_export", "e2e_box", "e2e_mac"])
st = FM.stale_sources(mkstate("export_down", {"billwatch": 4000.0, "gitlark": 4100.0, "iptv_apps": 5000.0}, 1 * H, 1 * H), NOW)
ok("Mac export not running (EVERY snapshot old): ONE deploy_export entry (no per-repo noise) carrying the exact fix", [k for k, _ in st] == ["deploy_export"]
   and "Mac qa-staging-export not running: launchctl kickstart gui/$(id -u)/com.shrike.qa-staging-export" in st[0][1] and "min old" in st[0][1], st)
st = FM.stale_sources(mkstate("one_repo", {"billwatch": 100.0, "gitlark": 100.0, "iptv_apps": 9000.0}, 1 * H, 1 * H), NOW)
ok("ONE repo's snapshot old while the others are fresh: deploy_file:<repo> only, pointing at the per-repo export", [k for k, _ in st] == ["deploy_file:iptv_apps"] and "iptv_apps" in st[0][1] and "Railway" in st[0][1], st)
st = FM.stale_sources(mkstate("no_dir", None, 1 * H, 1 * H), NOW)
ok("no staging_deploys directory at all => deploy_export 'MISSING' with the fix", [k for k, _ in st] == ["deploy_export"] and "MISSING" in st[0][1] and "launchctl kickstart" in st[0][1], st)
st = FM.stale_sources(mkstate("mac_old", ALL3, 13 * H, 1 * H), NOW)
ok("Mac e2e result 13 h old => e2e_mac with 'Mac qa-staging-e2e not running: launchctl kickstart gui/$(id -u)/com.shrike.qa-staging-e2e'",
   [k for k, _ in st] == ["e2e_mac"] and "Mac qa-staging-e2e not running: launchctl kickstart gui/$(id -u)/com.shrike.qa-staging-e2e" in st[0][1] and "13.0 h" in st[0][1], st)
st = FM.stale_sources(mkstate("box_old", ALL3, 1 * H, 20 * H), NOW)
ok("box e2e result 20 h old => e2e_box with the cron/log hint", [k for k, _ in st] == ["e2e_box"] and "staging_e2e_run.sh" in st[0][1] and "logs/staging_e2e.log" in st[0][1], st)
st = FM.stale_sources(mkstate("missing_e2e", ALL3, None, None), NOW)
ok("e2e result files never produced => both reported MISSING", sorted(k for k, _ in st) == ["e2e_box", "e2e_mac"] and all("MISSING" in m for _, m in st), st)
ok("the staging_e2e gate switched off => the two e2e sources are skipped, deploy sources still checked", keys(mkstate("off", {"iptv_apps": 9999.0}, 50 * H, 50 * H), e2e_on=False) == ["deploy_export"])
d = mkstate("hostile", ALL3, 1 * H, 1 * H)
open(os.path.join(d, "staging_deploys", "billwatch.json"), "w").write("{corrupt")
json.dump([1, 2], open(os.path.join(d, "staging_deploys", "gitlark.json"), "w"))
json.dump({"fetched_at": None}, open(os.path.join(d, "staging_deploys", "iptv_apps.json"), "w"))
open(os.path.join(d, "qa_staging_e2e.json"), "w").write("not json")
json.dump({"ts": "not a time"}, open(os.path.join(d, "staging_e2e_box.json"), "w"))
st = keys(d)
ok("hostile files (corrupt json, a list, null timestamp, bad ts) never raise and count as stale", st == ["deploy_export", "e2e_box", "e2e_mac"], st)

print("# 2. alerting: one WARN per stale source per 6 h (injected clock)")
def alerts(d):
    p = os.path.join(d, "alerts.log")
    return open(p).read().splitlines() if os.path.exists(p) else []


def scenario(mod, label):
    """The full alerting scenario against a module (original or mutated). -> list of failed expectations."""
    bad = []
    d = mkstate("sc_" + label, {"billwatch": 4000.0, "gitlark": 4000.0, "iptv_apps": 4000.0}, 13 * H, 1 * H)
    os.environ["QA_STATE_DIR"] = d
    st1, al1 = mod.run(d, NOW)
    if st1 != ["deploy_export", "e2e_mac"] or al1 != ["deploy_export", "e2e_mac"] or len(alerts(d)) != 2:
        bad.append("first run: two stale sources must produce two alerts, got %s %s %d lines" % (st1, al1, len(alerts(d))))
    mod.run(d, NOW + 1 * H)
    mod.run(d, NOW + 5 * H + 3599)
    if len(alerts(d)) != 2:
        bad.append("inside 6 h nothing is repeated, got %d lines" % len(alerts(d)))
    mod.run(d, NOW + 6 * H)
    if len(alerts(d)) != 4:
        bad.append("at 6 h each still-stale source alerts again (4 lines), got %d" % len(alerts(d)))
    # both recover (a fresh export and a fresh Mac result)
    for repo in ("billwatch", "gitlark", "iptv_apps"):
        json.dump({"repo": repo, "fetched_at": NOW + 6 * H + 100, "deployments": [{"id": "x", "status": "SUCCESS"}]}, open(os.path.join(d, "staging_deploys", repo + ".json"), "w"))
    json.dump({"ts": iso(NOW + 6 * H + 100), "passed": 17, "total": 17, "failed": []}, open(os.path.join(d, "qa_staging_e2e.json"), "w"))
    st3, al3 = mod.run(d, NOW + 6 * H + 120)
    if st3 or len(alerts(d)) != 4:
        bad.append("recovered sources are no longer stale and silent, got %s / %d lines" % (st3, len(alerts(d))))
    # the export dies again 31 min later - well inside 6 h of its last alert: a recovered source was forgotten, so this alerts AT ONCE
    st4, al4 = mod.run(d, NOW + 6 * H + 100 + 1860)
    if al4 != ["deploy_export"] or len(alerts(d)) != 5:
        bad.append("a relapse right after a recovery alerts at once, got %s / %d lines" % (al4, len(alerts(d))))
    return bad
fails = scenario(FM, "orig")
ok("original: 1st run alerts per stale source, silent inside 6 h, alerts again at 6 h, recovery clears, relapse alerts at once", not fails, fails)
d = os.path.join(T, "sc_orig")
lines = alerts(d)
ok("alert line format: [YYYY-mm-dd HH:MM:SS] WARN | evidence-freshness | <source text with the fix>",
   all(__import__("re").match(r"^\[\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\] WARN \| evidence-freshness \| ", l) for l in lines) and any("launchctl kickstart gui/$(id -u)/com.shrike.qa-staging-export" in l for l in lines), lines[:2])
d = mkstate("fresh_run", ALL3, 1 * H, 1 * H)
os.environ["QA_STATE_DIR"] = d
FM.run(d, NOW)
FM.run(d, NOW + 600)  # 10 minutes later everything is still inside its limit
ok("fresh sources: silent across runs, no alerts.log is even created", alerts(d) == [] and not os.path.exists(os.path.join(d, "alerts.log")))
d = mkstate("two_sources", {"iptv_apps": 9000.0}, 20 * H, 20 * H)
os.environ["QA_STATE_DIR"] = d
s1, a1 = FM.run(d, NOW)
ok("three stale sources => three independent alerts in one run", sorted(a1) == ["deploy_export", "e2e_box", "e2e_mac"] and len(alerts(d)) == 3, (a1, alerts(d)))
json.dump({"deploy_export": "garbage", "e2e_mac": None}, open(os.path.join(d, "evidence_freshness_alerted.json"), "w"))
FM.run(d, NOW + 60)
ok("a dedupe file with garbage values never crashes and simply re-alerts", len(alerts(d)) >= 3)
open(os.path.join(d, "evidence_freshness_alerted.json"), "w").write("{not json")
r = FM.run(d, NOW + 120)
ok("a corrupt dedupe file never crashes (treated as empty)", isinstance(r, tuple))

print("# 3. CLI: injected clock, kill switches, exit code")
d = mkstate("cli", {"iptv_apps": 9000.0}, 20 * H, 20 * H)
env = dict(os.environ, QA_STATE_DIR=d, EVIDENCE_FRESHNESS_NOW=str(NOW))
p = subprocess.run([PY, os.path.join(QA, "evidence_freshness_check.py")], capture_output=True, text=True, env=env, timeout=60)
j = json.loads(p.stdout)
ok("CLI exits 0, prints one JSON line {stale, alerted}, writes the alerts", p.returncode == 0 and sorted(j["alerted"]) == ["deploy_export", "e2e_box", "e2e_mac"] and len(alerts(d)) == 3, (p.stdout, p.stderr[-200:]))
p = subprocess.run([PY, os.path.join(QA, "evidence_freshness_check.py")], capture_output=True, text=True, env=env, timeout=60)
ok("CLI second run (same injected time): nothing new", json.loads(p.stdout)["alerted"] == [] and len(alerts(d)) == 3)
d = mkstate("cli_off", {"iptv_apps": 9000.0}, 20 * H, 20 * H)
p = subprocess.run([PY, os.path.join(QA, "evidence_freshness_check.py")], capture_output=True, text=True, env=dict(os.environ, QA_STATE_DIR=d, EVIDENCE_FRESHNESS_NOW=str(NOW), OVN_QA_STAGING_E2E="off"), timeout=60)
ok("OVN_QA_STAGING_E2E=off: only the deploy export is judged", json.loads(p.stdout)["stale"] == ["deploy_export"])
d = mkstate("cli_kill", {"iptv_apps": 9000.0}, 20 * H, 20 * H)
p = subprocess.run([PY, os.path.join(QA, "evidence_freshness_check.py")], capture_output=True, text=True, env=dict(os.environ, QA_STATE_DIR=d, EVIDENCE_FRESHNESS_NOW=str(NOW), OVN_EVIDENCE_FRESHNESS="off"), timeout=60)
ok("OVN_EVIDENCE_FRESHNESS=off: disabled, nothing written", json.loads(p.stdout) == {"disabled": True} and alerts(d) == [])
d = os.path.join(T, "cli_missing_state")
p = subprocess.run([PY, os.path.join(QA, "evidence_freshness_check.py")], capture_output=True, text=True, env=dict(os.environ, QA_STATE_DIR=d, EVIDENCE_FRESHNESS_NOW=str(NOW)), timeout=60)
ok("state dir that does not exist yet: exit 0, everything MISSING reported (and the dir is created)", p.returncode == 0 and len(alerts(d)) == 3, (p.stdout, p.stderr[-200:]))
os.environ.pop("QA_STATE_DIR", None)

print("# 4. mutation checks: break the logic in a temp copy => the scenario above fails")
MUT = os.path.join(T, "mut")
def mutated(old, new, tag):
    d_ = os.path.join(MUT, tag)
    os.makedirs(d_, exist_ok=True)
    shutil.copy(os.path.join(QA, "qa_common.py"), d_)
    s = open(os.path.join(QA, "evidence_freshness_check.py")).read()
    assert s.count(old) == 1, (old, s.count(old))
    open(os.path.join(d_, "evidence_freshness_check.py"), "w").write(s.replace(old, new))
    return load(os.path.join(d_, "evidence_freshness_check.py"), "fresh_mut_" + tag)
for label, old, new in (
    ("dedupe never recorded (alerts on every run)", "        seen[key] = now  # only after the line is on disk\n", "        pass\n"),
    ("re-alert window ignored", "if isinstance(last, (int, float)) and now - last < REALERT_S:", "if False:"),
    ("recovered sources not forgotten", "    seen = {k: v for k, v in seen.items() if k in keys}  # fresh again => forgotten: the next outage alerts at once\n", ""),
    ("deploy export threshold never trips", "elif min(known) > deploy_max:", "elif False:"),
    ("e2e age limit never trips", "elif a > E2E_MAX_S:", "elif False:"),
):
    m = mutated(old, new, "m%d" % abs(hash(label)))
    bad = scenario(m, "mut%d" % abs(hash(label)))
    ok("mutation [%s]: the alerting scenario FAILS (%d expectation(s) broken)" % (label, len(bad)), len(bad) > 0)
m = mutated("                out.append((\"deploy_file:\" + repo,", "                out.append((\"deploy_export\", ", "mfile")
st = m.stale_sources(mkstate("mut_file", {"billwatch": 100.0, "gitlark": 100.0, "iptv_apps": 9000.0}, 1 * H, 1 * H), NOW)
ok("mutation [per-repo stale reported under the wrong key]: the per-repo expectation FAILS", [k for k, _ in st] != ["deploy_file:iptv_apps"])

shutil.rmtree(T, ignore_errors=True)
print("%d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
