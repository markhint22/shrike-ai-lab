#!/usr/bin/env python3
"""Tests for scripts/ovn_fleet_slo.py + its hourly-update feed (ovn_notify.py) + the Mac tip exporter (ovn_slo_export_tip.sh) - package L5-fleet-slo, 2026-10-18.

Incidents the SLO view must make loudly visible (see docs/FLEET_RUNBOOK.md): (a) fixes on claude/feature sat for hours while the box ran old code (deploy_lag); (b) the rebuilt box lacked venv
packages / SDK / QA tools and nothing flagged it (drift); (c) a stuck Mac checkout fed stale staging evidence to the enforcing promote gate (evidence); (d) shadow gates let false credits land with
no evidence trail (false_credit ledger); (e) supply starvation was noticed from an ntfy (runway); (f) a gated promote can ship a semantic regression (promote_lag + audit ledger).
Covered here (hermetic temp dirs, a REAL-SHAPED box fixture copied read-only over ssh on 2026-10-19 under test/fixtures/fleet_slo/box, synthetic edge cases, real git repos, a real local HTTP server):
  * every SLO at, just below and just above its threshold (a threshold names the FIRST bad value), small-sample guards, paused queue, held promote repo, 307 not followed
  * first-seen tracking across runs (survives a one-run green blip, resets after the grace), ranking, the one hourly line (only > 1 h, length cap, runbook anchor), stale/missing summary line
  * the switch: off does nothing, shadow writes files but the hourly update stays silent, on feeds ONE line; env beats the mode file; garbage = shadow
  * cron entry point (json + md + log, --dry-run writes nothing), audit/mark-deployed/mode CLIs, tip export against real repos + the Mac script against a local remote with a stub ssh
  * MUTANTS: each substitution below must make this suite fail (a suite that passes on a mutant proves nothing). Env SLO_PATH loads another copy of the module."""
import atexit
import importlib.util
import json
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPTS = os.path.abspath(os.path.join(HERE, ".."))
FIX = os.path.join(HERE, "fixtures", "fleet_slo", "box")
os.environ["TZ"] = "America/Chicago"    # the box's zone: hygiene streak files hold LOCAL time
time.tzset()
for k in list(os.environ):
    if k.startswith("OVN_SLO_") or k in ("OVN_FLEET_SLO", "OVN_DIR", "OVN_NOTIFY_STATE", "OVN_SUPPLY_LINE", "OVN_QA_STAGING_E2E", "QA_STAGING_MAX_AGE_S", "OVN_SUPPLY_RUNWAY_H"):
        os.environ.pop(k, None)
BASE = os.path.realpath(tempfile.mkdtemp(prefix="fleet-slo-"))
atexit.register(lambda: shutil.rmtree(BASE, ignore_errors=True) if os.path.basename(BASE).startswith("fleet-slo-") and os.path.dirname(BASE) == os.path.realpath(tempfile.gettempdir()) else None)
HQ = os.path.join(BASE, "hq")                       # the root ovn_notify is imported against
os.makedirs(os.path.join(HQ, "state"))
os.environ["OVN_DIR"] = HQ
os.environ["OVN_NOTIFY_STATE"] = os.path.join(HQ, "state")
os.environ["OVN_SLO_PROD_CHECK"] = "off"
sys.path.insert(0, SCRIPTS)
SRC = os.environ.get("SLO_PATH") or os.path.join(SCRIPTS, "ovn_fleet_slo.py")
MUTANT_RUN = bool(os.environ.get("SLO_PATH"))
spec = importlib.util.spec_from_file_location("ovn_fleet_slo", SRC)
slo = importlib.util.module_from_spec(spec)
sys.modules["ovn_fleet_slo"] = slo
spec.loader.exec_module(slo)
import ovn_notify as notify  # noqa: E402

NOW = 1792371700.0           # 2026-10-19T01:01:40Z, 20 min after the newest fixture outcomes row
H = 3600.0
FAILS = []
N = [0]


def check(name, cond, detail=""):
    N[0] += 1
    if not cond:
        FAILS.append("%s %s" % (name, detail))
        print("  FAIL: %s %s" % (name, detail))


_seq = [0]


def mk_root(fixture=False):
    _seq[0] += 1
    r = os.path.join(BASE, "r%d" % _seq[0])
    if fixture:
        shutil.copytree(FIX, r)
    else:
        os.makedirs(os.path.join(r, "state"))
        os.makedirs(os.path.join(r, "logs"))
    os.makedirs(os.path.join(r, "www"), exist_ok=True)
    os.makedirs(os.path.join(r, "bb"), exist_ok=True)
    return r


def env(root, **kw):
    """Point the module-independent env at a root; returns the state dir."""
    os.environ["OVN_SLO_BACKUP_DIR"] = os.path.join(root, "bb")
    for k, v in kw.items():
        if v is None:
            os.environ.pop(k, None)
        else:
            os.environ[k] = v
    return os.path.join(root, "state")


def collect(root, now=NOW, net=False, prev=None):
    return slo.collect(now=now, root=root, state=os.path.join(root, "state"), net=net, prev_tracker=prev)


def bs(rep, slo_name=None, scope=None):
    return [b for b in rep["breaches"] if (slo_name is None or b["slo"] == slo_name) and (scope is None or b["scope"] == scope)]


def sev(rep, slo_name, scope=None):
    x = bs(rep, slo_name, scope)
    return x[0]["severity"] if x else None


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(text)


def supply_report(root, repos, ts=NOW):
    write(os.path.join(root, "state", "supply_report.json"), json.dumps({"ts": ts, "repos": repos}))


def outcomes(root, rows):
    write(os.path.join(root, "state", "outcomes.jsonl"), "".join(json.dumps(r) + "\n" for r in rows))


def row(repo, cls, age_min=30, sev_=None, fail="", status=""):
    t = NOW - age_min * 60
    sv = sev_ or {"landed": "good", "noop": "bad", "reverted": "bad"}.get(cls, "neutral")
    return {"ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(t)), "repo": repo, "id": "i", "class": cls, "severity": sv, "fail_reason": fail, "status": status or cls, "item_hash": "h%d" % age_min}


def sh(args, cwd=None, extra_env=None, inp=None):
    e = dict(os.environ, GIT_CONFIG_GLOBAL="/dev/null", GIT_CONFIG_SYSTEM="/dev/null", GIT_TERMINAL_PROMPT="0")
    e.update(extra_env or {})
    return subprocess.run(args, cwd=cwd, env=e, capture_output=True, text=True, input=inp)


def git(root_dir, *a, date=None):
    ex = {"GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t"}
    if date is not None:
        ex["GIT_AUTHOR_DATE"] = ex["GIT_COMMITTER_DATE"] = "%d +0000" % int(date)
    r = sh(["git", "-c", "commit.gpgsign=false", "-c", "init.defaultBranch=main"] + list(a), cwd=root_dir, extra_env=ex)
    if r.returncode != 0:
        raise RuntimeError("git %s: %s" % (a, r.stderr))
    return r.stdout.strip()


# ================================================================================ 1. real-shaped box fixture
def t_real():
    r = mk_root(fixture=True)
    env(r)
    rep = collect(r)
    check("real: report version/mode", rep["version"] == 1 and rep["mode"] == "shadow")
    check("real: lanes are the enabled lanes minus discontinued", {"iptv_apps", "xlite"} <= set(rep["repos"]) and "social-media-manager" not in rep["repos"], str(sorted(rep["repos"])))
    ip = rep["repos"]["iptv_apps"]
    check("real: iptv landed/attempts counted from outcomes", ip["landed_24h"] == 19 and ip["attempts_24h"] == 44, str(ip))
    check("real: skipped rows never count as attempts", sum(v["attempts_24h"] for v in rep["repos"].values()) < 160)
    taa = bs(rep, "bad_share", "test-automation-agent")
    check("real: TAA bad share breach with a classifier hint", len(taa) == 1 and "stage-unverified" in taa[0]["hint"] and "cluster" in taa[0]["hint"], str(taa))
    check("real: backups fresh in the real heartbeat format", rep["backup"]["hourly"]["state"] == "ok" and rep["backup"]["daily"]["state"] == "ok", str(rep["backup"]))
    check("real: staging evidence fresh at NOW", all(v["state"] == "ok" for v in rep["evidence"].values()), str(rep["evidence"]))
    lane = [g for g in rep["lanes"] if g["repo"] == "shrike-notify"]
    check("real: the real merge-streak file is parsed (local time, 3 fields)", len(lane) == 1 and lane[0]["kind"] == "merge" and 0.4 < lane[0]["stall_h"] < 0.7 and lane[0]["state"] == "ok", str(lane))
    check("real: no data is SAID, not guessed", any("deploy_lag" in n for n in rep["nodata"]) and any("false_credit" in n for n in rep["nodata"]), str(rep["nodata"]))
    dr = bs(rep, "drift", "box")
    check("real: the real box_verify.json shape (items[], counts) is read: 14 findings, crit, first names + the human count + the first fix in the hint",
          len(dr) == 1 and dr[0]["severity"] == "crit" and dr[0]["value"] == 14 and "venv:billwatch:repo_missing" in dr[0]["hint"] and "7 need a human" in dr[0]["hint"] and "first fix:" in dr[0]["hint"] and "box_verify.sh --human --no-record" in dr[0]["hint"], str(dr))
    # 7 h later the same merge streak is a crit stall and the evidence is long stale
    late = collect(r, now=NOW + 7 * H)
    check("real: +7h the open merge streak is a crit gate stall", sev(late, "gate_stall") == "crit", str([b["key"] for b in late["breaches"]]))
    check("real: +7h the staging deploy export is crit-stale", sev(late, "evidence", "deploy_export") == "crit")
    check("real: promote repos without a checkout are nodata, not a breach", rep["deploy"]["promote"]["billwatch"]["state"] == "nodata" and not bs(rep, "promote_lag"))


# ================================================================================ 2. thresholds (boundary = first bad value)
def t_grade():
    g = slo.grade
    check("grade: below warn", g(2.99, 3, 6) is None)
    check("grade: at warn is warn", g(3, 3, 6) == "warn")
    check("grade: between", g(5.99, 3, 6) == "warn")
    check("grade: at crit is crit", g(6, 3, 6) == "crit")


def t_landing_and_bad():
    r = mk_root()
    env(r)
    supply_report(r, {"a": {"pullable": 10, "starving": False, "runway_h": 30}, "b": {"pullable": 10, "starving": False, "runway_h": 30}, "c": {"pullable": 0, "starving": True, "runway_h": 0, "cause_class": "cap", "causes": [{"class": "cap", "text": "daily cap used up"}]}})
    rows = [row("a", "noop", i + 1, fail="test-red") for i in range(8)]                 # a: 8 attempts, 0 landed, all bad
    rows += [row("b", "landed", 5), row("b", "noop", 6), row("b", "noop", 7)]            # b: landed 1, 2/3 bad but only 3 attempts -> small sample
    rows += [row("c", "noop", 8) for _ in range(6)]                                       # c: starving, nothing pullable
    outcomes(r, rows)
    rep = collect(r)
    check("landing: 0 landed with >= min attempts is crit", sev(rep, "landing_rate", "a") == "crit")
    check("landing: hint names the top fail_reason", "test-red x8" in bs(rep, "landing_rate", "a")[0]["hint"], bs(rep, "landing_rate", "a")[0]["hint"])
    check("landing: one landed meets the SLO (lane b)", not bs(rep, "landing_rate", "b"))
    check("bad share: small sample is not judged", rep["repos"]["b"]["bad_state"] == "small-sample" and not bs(rep, "bad_share", "b"))
    check("bad share: 100% bad with 8 attempts is crit", sev(rep, "bad_share", "a") == "crit")
    check("landing: a starving lane is the runway SLO's, not a second breach", not bs(rep, "landing_rate", "c") and sev(rep, "runway", "c") == "crit")
    check("runway: hint carries the supply cause", "cap" in bs(rep, "runway", "c")[0]["hint"] and "daily cap used up" in bs(rep, "runway", "c")[0]["hint"])
    # paused queue: no landing breach
    write(os.path.join(r, "state", "PAUSED"), "")
    check("landing: PAUSED queue reports nothing", not bs(collect(r), "landing_rate"))
    os.remove(os.path.join(r, "state", "PAUSED"))
    # zero attempts, work pullable: lane not running
    outcomes(r, [row("a", "skipped", 3 + i, status="idle") for i in range(9)])   # the idle loop's heartbeat is not an attempt
    z = collect(r)
    check("landing: skip heartbeat rows are not attempts", z["repos"]["a"]["attempts_24h"] == 0, str(z["repos"]["a"]))
    check("landing: pullable work and no attempt at all is a warn that says so", sev(z, "landing_rate", "a") == "warn" and "no attempt" in bs(z, "landing_rate", "a")[0]["hint"])
    # supply report unavailable (pullable unknown): "lane not running" would be a guess presented as a cause
    os.remove(os.path.join(r, "state", "supply_report.json"))
    write(os.path.join(r, "tasks.json"), json.dumps([{"repo": "/x/a", "enabled": True}, {"repo": "/x/b", "enabled": True}]))
    outcomes(r, [row("a", "skipped", 3, status="idle")])
    u = collect(r)
    check("landing: supply report unavailable + 0 attempts is NOT a 'lane not running' breach", not bs(u, "landing_rate", "a") and u["repos"]["a"]["landing"] == "unknown" and any("runway" in n for n in u["nodata"]), str((u["repos"]["a"], u["nodata"])))
    outcomes(r, [row("a", "noop", i + 1, fail="test-red") for i in range(8)])
    check("landing: supply unavailable but 8 real attempts with 0 landed is still a crit (evidence, not a guess)", sev(collect(r), "landing_rate", "a") == "crit")
    outcomes(r, [row("a", "noop", 2, fail="test-red")])
    check("landing: supply unavailable, 1 failed attempt, 0 landed: warn with the attempt count", sev(collect(r), "landing_rate", "a") == "warn" and "1 attempts" in bs(collect(r), "landing_rate", "a")[0]["hint"])
    supply_report(r, {"a": {"pullable": 10, "starving": False, "runway_h": 30}, "b": {"pullable": 10, "starving": False, "runway_h": 30}})
    os.remove(os.path.join(r, "tasks.json"))
    # bad share boundaries with 6 attempts: 3 bad = 0.5 warn, 2 bad = 0.333 none, 5 bad = .833 crit, 0.75 exactly (3 of 4 needs 5 attempts: use 4/... use 8 attempts, 6 bad)
    for nb, expect in ((2, None), (3, "warn"), (4, "warn"), (5, "crit")):
        outcomes(r, [row("a", "noop", i + 1) for i in range(nb)] + [row("a", "landed", 20 + i) for i in range(6 - nb)])
        check("bad share: 6 attempts, %d bad -> %s" % (nb, expect), sev(collect(r), "bad_share", "a") == expect, str(sev(collect(r), "bad_share", "a")))
    outcomes(r, [row("a", "noop", i + 1) for i in range(6)] + [row("a", "landed", 30), row("a", "landed", 31)])
    check("bad share: exactly 0.75 is crit (6 of 8)", sev(collect(r), "bad_share", "a") == "crit")
    outcomes(r, [row("a", "noop", i + 1) for i in range(4)] + [row("a", "landed", 30), row("a", "landed", 31)])
    check("bad share: 4 of 6 = 0.667 stays warn", sev(collect(r), "bad_share", "a") == "warn")
    outcomes(r, [row("a", "noop", i + 1) for i in range(4)] + [row("a", "landed", 30)])
    check("bad share: 5 attempts is enough (min is 5)", sev(collect(r), "bad_share", "a") == "crit")
    outcomes(r, [row("a", "noop", i + 1) for i in range(3)] + [row("a", "landed", 30)])
    check("bad share: 4 attempts is NOT enough", not bs(collect(r), "bad_share", "a"))
    # benign no-ops (already-done) are not bad
    outcomes(r, [row("a", "noop", i + 1, sev_="neutral", status="no-op(ALREADY-DONE)") for i in range(6)])
    check("bad share: benign scout no-ops are excluded", not bs(collect(r), "bad_share", "a"))
    # rows older than 24 h are outside the window
    outcomes(r, [row("a", "noop", 24 * 60 + 5 + i) for i in range(8)])
    check("window: rows older than 24h are ignored", rep is not None and not bs(collect(r), "bad_share", "a"))


def t_false_credit():
    r = mk_root()
    st = env(r)
    supply_report(r, {})
    for i in range(3):
        slo.append_audit(st, "billwatch", "sha%d" % i, "ok", now=NOW - 3600)
    rep = collect(r)
    check("false credit: 0/3 is fine and measured", not bs(rep, "false_credit") and rep["false_credit"]["billwatch"]["audited"] == 3)
    slo.append_audit(st, "billwatch", "sha9", "false-credit", gate="item-verify", now=NOW - 1800)
    rep = collect(r)    # 1 of 4 = 25% -> crit
    check("false credit: 1/4 is crit with the gate in the hint", sev(rep, "false_credit", "billwatch") == "crit" and "item-verify x1" in bs(rep, "false_credit")[0]["hint"], str(bs(rep, "false_credit")))
    r1 = mk_root()
    st1 = env(r1)
    supply_report(r1, {})
    for i in range(2):
        slo.append_audit(st1, "gitlark", "k%d" % i, "ok", now=NOW - 60)
    slo.append_audit(st1, "gitlark", "kf", "false-credit", now=NOW - 60)
    check("false credit: exactly the minimum sample (3) is judged", sev(collect(r1), "false_credit", "gitlark") == "crit")
    # sample guard: 2 audits, both false -> not judged
    r2 = mk_root()
    st2 = env(r2)
    supply_report(r2, {})
    slo.append_audit(st2, "gitlark", "x1", "false-credit", now=NOW - 60)
    slo.append_audit(st2, "gitlark", "x2", "false-credit", now=NOW - 60)
    check("false credit: below the sample minimum is not judged", not bs(collect(r2), "false_credit"))
    # exactly 5% (1 of 20) is warn; 1 of 21 is not
    for n, expect in ((20, "warn"), (21, None)):
        r3 = mk_root()
        st3 = env(r3)
        supply_report(r3, {})
        for i in range(n - 1):
            slo.append_audit(st3, "xlite", "o%d" % i, "ok", now=NOW - 60)
        slo.append_audit(st3, "xlite", "bad", "false-credit", now=NOW - 60)
        check("false credit: 1 of %d -> %s" % (n, expect), sev(collect(r3), "false_credit", "xlite") == expect)
    # last verdict wins (an audit corrected from false-credit to ok)
    r4 = mk_root()
    st4 = env(r4)
    supply_report(r4, {})
    for i in range(4):
        slo.append_audit(st4, "xlite", "o%d" % i, "ok", now=NOW - 100)
    slo.append_audit(st4, "xlite", "q", "false-credit", now=NOW - 90)
    slo.append_audit(st4, "xlite", "q", "ok", now=NOW - 80)
    check("false credit: the last verdict per (repo, ref) wins", not bs(collect(r4), "false_credit") and collect(r4)["false_credit"]["xlite"]["false"] == 0)
    # window: an 8-day-old false credit is out
    r5 = mk_root()
    st5 = env(r5)
    supply_report(r5, {})
    for i in range(3):
        slo.append_audit(st5, "xlite", "o%d" % i, "ok", now=NOW - 100)
    slo.append_audit(st5, "xlite", "old", "false-credit", now=NOW - 8 * 86400)
    check("false credit: older than the window is ignored", not bs(collect(r5), "false_credit"))
    # fleet level when no repo has enough audits alone: 2+2 audits, 2 false -> fleet 50%
    r6 = mk_root()
    st6 = env(r6)
    supply_report(r6, {})
    for rp in ("a", "b"):
        slo.append_audit(st6, rp, rp + "1", "false-credit", now=NOW - 5)
        slo.append_audit(st6, rp, rp + "2", "ok", now=NOW - 5)
    f = bs(collect(r6), "false_credit")
    check("false credit: fleet-level breach when no single repo has the sample", len(f) == 1 and f[0]["scope"] == "fleet", str(f))
    # CLI validation
    p = sh([sys.executable, SRC, "audit", "--repo", "a", "--ref", "r", "--verdict", "maybe"], extra_env={"OVN_NOTIFY_STATE": st6, "OVN_DIR": r6})
    check("false credit: CLI refuses an unknown verdict", p.returncode == 2 and "verdict" in p.stderr, p.stderr)
    p = sh([sys.executable, SRC, "audit", "--repo", "a", "--ref", "r9", "--verdict", "false-credit", "--gate", "g", "--note", "n", "--now", "1792371000"], extra_env={"OVN_NOTIFY_STATE": st6, "OVN_DIR": r6})
    last = json.loads(open(os.path.join(st6, "landing_audits.jsonl")).read().splitlines()[-1])
    check("false credit: CLI appends the documented ledger row", p.returncode == 0 and last["verdict"] == "false-credit" and last["gate"] == "g" and last["ts"] == 1792371000 and last["repo"] == "a" and last["ref"] == "r9", str(last))


def t_gate():
    r = mk_root()
    st = env(r)
    supply_report(r, {})
    from datetime import datetime

    def streak(name, hours_ago, n=2, kind="hygiene_gate_streak"):
        t = NOW - hours_ago * H
        write(os.path.join(st, kind, name), "%d 0 0 %s\n" % (n, time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(t))))
    streak("iptv_apps__claude_feature", 2.9)
    streak("billwatch__overnight_feature", 3.0)
    streak("xlite__claude_feature", 6.0)
    streak("shrike-notify__claude_feature", 7.0, kind="hygiene_merge_streak")
    write(os.path.join(st, "alerts.log"), "[2026-10-18 18:00:00] warn | hygiene-gate-streak:billwatch | hygiene gate FAILED 3 consecutive passes for billwatch overnight/feature - nothing; failing: tests/test_auth.py::test_refresh\n")
    rep = collect(r)
    check("gate: 2.9 h is below warn", sev(rep, "gate_stall", "iptv_apps/claude_feature(gate)") is None)
    check("gate: exactly 3 h is warn", sev(rep, "gate_stall", "billwatch/overnight_feature(gate)") == "warn")
    check("gate: exactly 6 h is crit", sev(rep, "gate_stall", "xlite/claude_feature(gate)") == "crit")
    check("gate: a merge streak is a lane stall too (repo name keeps its hyphen)", sev(rep, "gate_stall", "shrike-notify/claude_feature(merge)") == "crit")
    check("gate: the hint carries the failing tests from alerts.log", "tests/test_auth.py::test_refresh" in bs(rep, "gate_stall", "billwatch/overnight_feature(gate)")[0]["hint"])
    check("gate: a breach is already old when first seen (since = first failure + warn)", bs(rep, "gate_stall", "xlite/claude_feature(gate)")[0]["hours"] >= 3.0)
    # half-written files (atomic-write temp names) are never lanes
    for tmpname in ("phantom__claude_feature.tmp", "phantom2__claude_feature.tmp.123", "phantom3__claude_feature.tmp.9"):
        write(os.path.join(st, "hygiene_gate_streak", tmpname), "9 0 0 %s\n" % time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(NOW - 20 * H)))
    write(os.path.join(st, "hygiene_gate_streak", "notalane"), "9\n")
    check("gate: .tmp / .tmp.PID / no-separator files are not phantom stalled lanes", not [g for g in collect(r)["lanes"] if g["repo"].startswith("phantom") or g["repo"] == "notalane"] and not [b for b in bs(collect(r), "gate_stall") if "phantom" in b["scope"]])
    # unparseable streak file falls back to its mtime
    p = os.path.join(st, "hygiene_gate_streak", "gitlark__claude_feature")
    write(p, "garbage\n")
    os.utime(p, (NOW - 10 * H, NOW - 10 * H))
    check("gate: unreadable timestamp falls back to mtime", sev(collect(r), "gate_stall", "gitlark/claude_feature(gate)") == "crit")
    # a green gate removes the file -> no breach
    os.remove(os.path.join(st, "hygiene_gate_streak", "xlite__claude_feature"))
    check("gate: a recovered lane has no breach", sev(collect(r), "gate_stall", "xlite/claude_feature(gate)") is None)


def tip_file(root, commits, fetched=NOW - 600):
    write(os.path.join(root, "state", "claude_feature_tip.json"), json.dumps({"ref": "origin/claude/feature", "fetched_at": fetched, "commits": commits, "ok": True}))


def sha(n):
    return ("%02x" % n) * 20


def t_deploy_lag():
    r = mk_root()
    st = env(r)
    supply_report(r, {})
    commits = [[sha(5), NOW - 600], [sha(4), NOW - 1 * H], [sha(3), NOW - 5.9 * H], [sha(2), NOW - 30 * H], [sha(1), NOW - 40 * H]]
    tip_file(r, commits)
    check("deploy: nothing recorded -> nodata, says how to fix", collect(r)["deploy"]["box"]["state"] == "nodata" and "mark-deployed" in collect(r)["deploy"]["box"]["detail"])
    p = sh([sys.executable, SRC, "mark-deployed", "--sha", sha(5)], extra_env={"OVN_NOTIFY_STATE": st, "OVN_DIR": r})
    check("deploy: mark-deployed CLI writes the file", p.returncode == 0 and json.loads(open(os.path.join(st, "deployed_sha")).read())["sha"] == sha(5), p.stderr)
    check("deploy: at the tip -> ok, 0 behind", collect(r)["deploy"]["box"]["behind"] == 0 and not bs(collect(r), "deploy_lag"))
    write(os.path.join(st, "deployed_sha"), sha(4)[:12] + "\n")    # plain short sha is accepted
    d = collect(r)["deploy"]["box"]
    check("deploy: one commit behind, young -> ok", d["state"] == "ok" and d["behind"] == 1, str(d))
    write(os.path.join(st, "deployed_sha"), sha(3) + "\n")        # oldest undeployed = sha4, 1 h old
    check("deploy: 2 behind but oldest undeployed 1h old -> ok", not bs(collect(r), "deploy_lag"))
    write(os.path.join(st, "deployed_sha"), json.dumps({"sha": sha(2)}) + "\n")   # oldest undeployed = sha3 at 5.9 h
    check("deploy: oldest undeployed 5.9h is below warn", not bs(collect(r), "deploy_lag"))
    tip_file(r, [[sha(5), NOW - 600], [sha(4), NOW - 1 * H], [sha(3), NOW - 6.0 * H], [sha(2), NOW - 30 * H]])
    b = bs(collect(r), "deploy_lag")
    check("deploy: oldest undeployed exactly 6h is warn", len(b) == 1 and b[0]["severity"] == "warn" and "3 commit(s) behind" in b[0]["hint"], str(b))
    write(os.path.join(st, "deployed_sha"), sha(2) + "\n")
    tip_file(r, [[sha(5), NOW - 600], [sha(4), NOW - 24 * H], [sha(3), NOW - 25 * H], [sha(2), NOW - 30 * H]])
    check("deploy: exactly 24h is crit", sev(collect(r), "deploy_lag") == "crit")
    # the oldest UNDEPLOYED commit decides, not the tip: tip is young but the commit right after deployed is old
    tip_file(r, [[sha(5), NOW - 60], [sha(4), NOW - 60], [sha(3), NOW - 8 * H], [sha(2), NOW - 30 * H]])
    check("deploy: age is of the first undeployed commit, not the tip", sev(collect(r), "deploy_lag") == "warn")
    # deployed sha not within the tip window: NEVER a guessed crit (2026-10-18 review: a 906 h false crit for a box that had just deployed the real newest commit)
    big = [["%040x" % (1000 + i), NOW - (9 + i * 3) * H] for i in range(299)]        # 299 commits, 9h .. 900h old: the repro of the review
    tip_file(r, big, fetched=NOW - 50 * 60)
    for label, dep_line in (("plain sha newer than the export", sha(99) + "\n"), ("with a fresh deploy record", json.dumps({"sha": sha(99), "ts": NOW - 300}) + "\n")):
        write(os.path.join(st, "deployed_sha"), dep_line)
        rep = collect(r)
        d = rep["deploy"]["box"]
        check("deploy: sha not in a 299-commit tip (%s) is no breach at all" % label, not bs(rep, "deploy_lag") and d["state"] == "unknown-deployed" and d["lag_h"] is None, str(d))
        check("deploy: ... and the unknown is SAID as no-data, with no deploy breach and no deploy text in the notify line", any("deploy_lag" in n and "cannot be judged" in n for n in rep["nodata"]) and "deploy_lag" not in (rep["notify_line"] or "") and not any(b["slo"] == "deploy_lag" for b in rep["breaches"]), str(rep["nodata"]))
        later = collect(r, now=NOW + 2 * H, prev=rep["_tracker"])
        check("deploy: ... still nothing 2h later (a tracker never ages a breach that does not exist)", "deploy_lag" not in (later["notify_line"] or "") and not bs(later, "deploy_lag"))
    # an old deploy record that predates the whole window IS evidence the box is old: warn, never crit
    write(os.path.join(st, "deployed_sha"), json.dumps({"sha": sha(99), "ts": NOW - 2000 * H}) + "\n")
    b = bs(collect(r), "deploy_lag")
    check("deploy: a deploy record older than the whole window is a warn (not crit) that says so", len(b) == 1 and b[0]["severity"] == "warn" and "predates the whole window" in b[0]["hint"], str(b))
    # the Mac export carries the whole branch: a box on a commit that does not touch the queue path is placeable
    X = sha(60)   # a docs-only commit between sha(4) and sha(3)
    allc = [[sha(5), NOW - 600], [sha(4), NOW - 1 * H], [X, NOW - 2 * H], [sha(3), NOW - 5.9 * H], [sha(2), NOW - 30 * H], [sha(1), NOW - 40 * H]]
    def tip_all(commits, all_commits, head=None, fetched=NOW - 600):
        write(os.path.join(r, "state", "claude_feature_tip.json"), json.dumps({"ref": "origin/claude/feature", "fetched_at": fetched, "head": head, "commits": commits, "all_commits": all_commits, "ok": True}))
    tip_all(commits, allc)
    write(os.path.join(st, "deployed_sha"), X + "\n")
    d = collect(r)["deploy"]["box"]
    check("deploy: a non-queue commit is placed on the branch: the 2 newer queue commits are the lag", d["state"] == "ok" and d["behind"] == 2 and not bs(collect(r), "deploy_lag"), str(d))
    tip_all([[sha(5), NOW - 600], [sha(4), NOW - 1 * H], [sha(3), NOW - 8 * H], [sha(2), NOW - 30 * H]], [[sha(5), NOW - 600], [sha(4), NOW - 1 * H], [X, NOW - 2 * H], [sha(3), NOW - 8 * H], [sha(2), NOW - 30 * H]])
    write(os.path.join(st, "deployed_sha"), sha(2)[:12] + "\n")
    check("deploy: queue sha still uses the path list (3 behind, oldest undeployed 8h = warn)", sev(collect(r), "deploy_lag") == "warn")
    tip_all([[sha(5), NOW - 600], [sha(4), NOW - 1 * H], [sha(3), NOW - 8 * H], [sha(2), NOW - 30 * H]], [[sha(5), NOW - 600], [sha(4), NOW - 1 * H], [sha(3), NOW - 8 * H], [X, NOW - 9 * H], [sha(2), NOW - 30 * H]])
    write(os.path.join(st, "deployed_sha"), X + "\n")
    b = bs(collect(r), "deploy_lag")
    check("deploy: placed non-queue sha: oldest undeployed queue commit (8h) decides -> warn", len(b) == 1 and b[0]["severity"] == "warn" and collect(r)["deploy"]["box"]["behind"] == 3 and "8.0h" in b[0]["hint"], str(b))
    # the box deployed the newest commit and that commit is a HEAD that touches nothing under the queue path
    Y = sha(70)   # a docs-only commit newer than every queue commit, not the head of the export
    tip_all(commits, [[Y, NOW - 300]] + allc)
    write(os.path.join(st, "deployed_sha"), Y + "\n")
    d = collect(r)["deploy"]["box"]
    check("deploy: a placed sha newer than the last queue commit has nothing undeployed -> ok", d["state"] == "ok" and d["behind"] == 0 and not bs(collect(r), "deploy_lag"), str(d))
    tip_all(commits, [["%040x" % 7, NOW - 60]] + allc, head="%040x" % 7)
    write(os.path.join(st, "deployed_sha"), ("%040x" % 7) + "\n")
    d = collect(r)["deploy"]["box"]
    check("deploy: the deployed sha is the branch HEAD (touches no queue file) -> ok, not behind", d["state"] == "ok" and d["behind"] == 0 and not bs(collect(r), "deploy_lag"), str(d))
    tip_all(commits, [], head="%040x" % 7)    # an old export without all_commits: head still wins
    check("deploy: head match works without all_commits too", collect(r)["deploy"]["box"]["state"] == "ok")
    # a box AHEAD of the (older) export: its sha is newer than every exported commit -> unknown or ok, never crit
    tip_all(commits, allc, head=sha(5))
    write(os.path.join(st, "deployed_sha"), sha(98) + "\n")
    check("deploy: a box ahead of the export is never a crit", sev(collect(r), "deploy_lag") is None)
    # stale tip export (the Mac job died)
    write(os.path.join(st, "deployed_sha"), sha(4) + "\n")
    tip_file(r, [[sha(5), NOW - 600], [sha(4), NOW - 1 * H]], fetched=NOW - 7 * H)
    b = bs(collect(r), "deploy_lag")
    check("deploy: a stale tip export is itself a warn", len(b) == 1 and "tip export" in b[0]["hint"] and collect(r)["deploy"]["box"]["state"] == "stale-tip", str(b))
    tip_file(r, [[sha(5), NOW - 600]], fetched=NOW - 5.9 * H)
    check("deploy: tip export 5.9h old is still trusted", collect(r)["deploy"]["box"]["state"] != "stale-tip")


def t_promote_lag():
    if MUTANT_RUN and not os.environ.get("SLO_RUN_GIT"):
        return
    r = mk_root()
    st = env(r, OVN_SLO_PROMOTE_REPOS="billwatch iptv_apps gitlark", OVN_SLO_PROMOTE_HOLD="gitlark")
    supply_report(r, {})
    for name, kind, age_h in (("billwatch", "ahead", 40), ("iptv_apps", "identical", 100), ("gitlark", "ahead", 100)):
        o = os.path.join(BASE, name + ".origin.git")
        w = os.path.join(BASE, name + ".w")
        sh(["git", "init", "-q", "--bare", "-b", "main", o])
        os.makedirs(w)
        git(w, "init", "-q", "-b", "main")
        git(w, "remote", "add", "origin", o)
        write(os.path.join(w, "a.txt"), "1\n")
        git(w, "add", "-A")
        git(w, "commit", "-q", "-m", "base", date=NOW - 200 * H)
        git(w, "push", "-q", "origin", "main")
        git(w, "checkout", "-q", "-b", "develop")
        if kind == "identical":
            git(w, "commit", "-q", "--allow-empty", "-m", "empty", date=NOW - age_h * H)
        else:
            write(os.path.join(w, "b.txt"), "2\n")
            git(w, "add", "-A")
            git(w, "commit", "-q", "-m", "feat", date=NOW - age_h * H)
        git(w, "push", "-q", "origin", "develop")
        sh(["git", "clone", "-q", o, os.path.join(r, "repos", name)])
    write(os.path.join(r, "logs", "daily_promote.log"), "===== billwatch =====\n  smoke test FAILED: staging health 502 - promote BLOCKED\n  [prod-deploy] post-promote check started (detached): result in logs/promote_postcheck.log, FAILED => emergency push + alerts.log\n")
    with open(os.path.join(r, "logs", "daily_promote.log"), "a") as fh:
        fh.write("===== gitlark =====\n  smoke test FAILED: staging 502 - promote BLOCKED (old run)\n===== gitlark =====\n"
                 "  \u26a0\ufe0f  no staging URL configured (state/staging_url_gitlark) - smoke test SKIPPED.\n"
                 "  [candidate] 857f5bfd9f PASS, 0 develop merge(s) held back, release branch release/20261018, main fast-forwardable: yes\n"
                 "  [staging-e2e] mode=shadow e2e=UNVERIFIED commit=e017 -> proceed (2 PASS, 5 UNVERIFIED)\n"
                 "  [prod-alembic] UNVERIFIED (shadow): no read-only prod alembic snapshot\n")
    rep = collect(r)
    p = rep["deploy"]["promote"]
    os.environ["OVN_SLO_PROMOTE_HOLD"] = ""
    gh = bs(collect(r), "promote_lag", "gitlark")[0]["hint"]
    check("promote: benign lines of a successful run (0 held back, smoke SKIPPED, UNVERIFIED shadow) are NOT quoted as the last promote note, and the newer run replaced the old BLOCKED one",
          "held back" not in gh and "SKIPPED" not in gh and "UNVERIFIED" not in gh and "BLOCKED" not in gh and "none (no blocking line" in gh, gh)
    with open(os.path.join(r, "logs", "daily_promote.log"), "a") as fh:
        fh.write("  [candidate] 857f5bfd9f PASS, 2 develop merge(s) held back (red gate), release branch\n")
    check("promote: a REAL held-back count is quoted", "2 develop merge(s) held back" in bs(collect(r), "promote_lag", "gitlark")[0]["hint"])
    with open(os.path.join(r, "logs", "daily_promote.log"), "a") as fh:
        fh.write("  [candidate] 857f5bfd9f PASS, 10 develop merge(s) held back, release branch\n")
    check("promote: 10 held back is a blocker (only a literal 0 is benign)", "10 develop merge(s) held back" in bs(collect(r), "promote_lag", "gitlark")[0]["hint"])
    with open(os.path.join(r, "logs", "daily_promote.log"), "a") as fh:
        fh.write("  \u2705 PROMOTED gitlark develop -> main (+3). Prod deploy triggered.\n")
    check("promote: a PROMOTED line clears that repo's earlier blocker", "none (no blocking line" in bs(collect(r), "promote_lag", "gitlark")[0]["hint"])
    os.environ["OVN_SLO_PROMOTE_HOLD"] = "gitlark"
    b = bs(rep, "promote_lag", "billwatch")
    check("promote: 40h of unpromoted develop is warn (limit 36h) with the promote log note", len(b) == 1 and b[0]["severity"] == "warn" and "BLOCKED" in b[0]["hint"], str(b))
    check("promote: tree-identical develop is no lag", p["iptv_apps"]["state"] == "ok" and p["iptv_apps"]["lag_h"] == 0.0 and not bs(rep, "promote_lag", "iptv_apps"), str(p["iptv_apps"]))
    check("promote: a held repo is shown held, not breached", p["gitlark"]["state"] == "held" and not bs(rep, "promote_lag", "gitlark"), str(p["gitlark"]))
    os.environ["OVN_SLO_PROMOTE_HOLD"] = ""
    check("promote: without the hold it is a crit (100h > 72h)", sev(collect(r), "promote_lag", "gitlark") == "crit")
    write(os.path.join(st, "slo_promote_hold.txt"), "gitlark\n")
    check("promote: the hold file works like the env", collect(r)["deploy"]["promote"]["gitlark"]["state"] == "held")
    os.environ.pop("OVN_SLO_PROMOTE_REPOS", None)
    os.environ.pop("OVN_SLO_PROMOTE_HOLD", None)


def t_backup():
    r = mk_root()
    st = env(r)
    supply_report(r, {})
    bb = os.path.join(r, "bb")

    def hb(mode, hours_ago):
        t = NOW - hours_ago * H
        write(os.path.join(bb, "heartbeat-%s.log" % mode), "%s box_home_backup %s OK x\n" % (time.strftime("%Y-%m-%dT%H:%M:%S-0500", time.localtime(t - 0)) if False else time.strftime("%Y-%m-%dT%H:%M:%S+0000", time.gmtime(t)), mode))
    hb("hourly", 2.99)
    hb("daily", 25.9)
    rep = collect(r)
    check("backup: just inside the limits is ok", not bs(rep, "backup"))
    hb("hourly", 3.0)
    hb("daily", 26.0)
    rep = collect(r)
    check("backup: exactly at the limits is warn for both", sev(rep, "backup", "hourly") == "warn" and sev(rep, "backup", "daily") == "warn", str(bs(rep, "backup")))
    hb("hourly", 6.0)
    hb("daily", 50.0)
    check("backup: crit limits", sev(collect(r), "backup", "hourly") == "crit" and sev(collect(r), "backup", "daily") == "crit")
    write(os.path.join(bb, "heartbeat-hourly.log"), "garbage\n")
    b = bs(collect(r), "backup", "hourly")
    check("backup: unparseable heartbeat is crit", len(b) == 1 and b[0]["severity"] == "crit")
    write(os.path.join(r, "logs", "box_backup_alert.log"), "2026-10-16T17:07:55-0500 box_home_backup ALERT: destination does not exist (drive not mounted?)\n")
    check("backup: the last backup alert is in the hint", "drive not mounted" in bs(collect(r), "backup", "hourly")[0]["hint"])
    shutil.rmtree(bb)
    b = bs(collect(r), "backup")
    check("backup: a missing drive is crit", len(b) == 1 and b[0]["severity"] == "crit" and "missing" in b[0]["hint"], str(b))
    env(r, OVN_SLO_BACKUP_DIR="off")
    check("backup: OVN_SLO_BACKUP_DIR=off disables", not bs(collect(r), "backup"))


class _H(BaseHTTPRequestHandler):
    def do_GET(self):
        code = {"/ok": 200, "/redir": 307, "/bad": 503, "/nf": 404}.get(self.path, 200)
        self.send_response(code)
        if self.path == "/redir":
            self.send_header("Location", "/bad")
        self.end_headers()

    def log_message(self, *a):
        pass


def t_prod():
    srv = HTTPServer(("127.0.0.1", 0), _H)
    port = srv.server_address[1]
    th = threading.Thread(target=srv.serve_forever, daemon=True)
    th.start()
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    dead = s.getsockname()[1]
    s.close()
    r = mk_root()
    env(r)
    supply_report(r, {})
    urls = os.path.join(r, "urls.txt")
    write(urls, "# comment\nokay|http://127.0.0.1:%d/ok\nredirect|http://127.0.0.1:%d/redir\nbroken|http://127.0.0.1:%d/bad\nmissing|http://127.0.0.1:%d/nf|404\ndown|http://127.0.0.1:%d/ok\nbad_codes|http://127.0.0.1:%d/ok|201,204\n" % (port, port, port, port, dead, port))
    os.environ["OVN_SLO_PROD_URLS"] = urls
    os.environ.pop("OVN_SLO_PROD_CHECK", None)
    os.environ["OVN_SLO_HTTP_TIMEOUT"] = "3"
    try:
        rep = collect(r, net=True)
    finally:
        os.environ["OVN_SLO_PROD_CHECK"] = "off"
        os.environ.pop("OVN_SLO_PROD_URLS", None)
        srv.shutdown()
    by = {c["name"]: c for c in rep["prod"]["checks"]}
    check("prod: 200 is up", by["okay"]["ok"] and by["okay"]["code"] == 200)
    check("prod: 307 is a literal answer and up (redirect NOT followed)", by["redirect"]["code"] == 307 and by["redirect"]["ok"], str(by["redirect"]))
    check("prod: 503 is crit", sev(rep, "prod_health", "broken") == "crit" and bs(rep, "prod_health", "broken")[0]["value"] == 503)
    check("prod: a custom expected code (404) is honoured", by["missing"]["ok"] and not bs(rep, "prod_health", "missing"))
    check("prod: connection refused is crit with no response", sev(rep, "prod_health", "down") == "crit" and by["down"]["code"] is None and "no response" in bs(rep, "prod_health", "down")[0]["hint"])
    check("prod: 200 outside an explicit code list is a breach", sev(rep, "prod_health", "bad_codes") == "crit")
    # the shipped list: parseable, named, only http(s)
    urls_f, src = slo.load_prod_urls(os.path.join(SCRIPTS, ".."), os.path.join(r, "state"))
    check("prod: ops/slo_prod_urls.txt ships the known-good prod URLs", len(urls_f) >= 8 and all(u.startswith("https://") for _, u, _ in urls_f) and ("billwatch-backend" in [n for n, _, _ in urls_f]), str(src))
    check("prod: OVN_SLO_PROD_CHECK=off skips the probes", collect(r, net=True)["prod"]["state"] in ("disabled", "nodata"))


def t_evidence():
    r = mk_root(fixture=True)
    env(r)
    lim = 1800
    newest = max(json.load(open(os.path.join(r, "state", "staging_deploys", f)))["fetched_at"] for f in os.listdir(os.path.join(r, "state", "staging_deploys")))
    rep = collect(r, now=newest + lim - 1)
    check("evidence: 1s inside the limit is ok", rep["evidence"]["deploy_export"]["state"] == "ok")
    rep = collect(r, now=newest + lim)
    check("evidence: exactly at the limit is warn", sev(rep, "evidence", "deploy_export") == "warn" and "qa-staging-export" in bs(rep, "evidence", "deploy_export")[0]["hint"])
    rep = collect(r, now=newest + lim * 4)
    check("evidence: 4x the limit is crit", sev(rep, "evidence", "deploy_export") == "crit")
    rep = collect(r, now=newest + lim * 4 - 1)
    check("evidence: just under 4x stays warn", sev(rep, "evidence", "deploy_export") == "warn")
    os.remove(os.path.join(r, "state", "qa_staging_e2e.json"))
    b = bs(collect(r), "evidence", "e2e_mac")
    check("evidence: a missing e2e file counts as stale (crit)", len(b) == 1 and b[0]["severity"] == "crit")
    env(r, OVN_QA_STAGING_E2E="off")
    check("evidence: e2e sources are skipped when that gate is off", "e2e_mac" not in collect(r)["evidence"] and "e2e_box" not in collect(r)["evidence"])
    os.environ.pop("OVN_QA_STAGING_E2E", None)


def t_drift():
    r = mk_root()
    st = env(r)
    supply_report(r, {})
    check("drift: no box_verify.json is nodata", collect(r)["drift"]["state"] == "nodata")
    ts = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(NOW - 600))
    for body, n, expect in (({"ts": ts, "drift": []}, 0, None), ({"ts": ts, "drift": [{"name": "pytest-xdist missing in billwatch venv"}]}, 1, "warn"),
                            ({"ts": ts, "findings": ["a", "b", "c", "d"]}, 4, "warn"), ({"ts": ts, "findings": list("abcde")}, 5, "crit"),
                            ({"ts": ts, "drift_count": 2}, 2, "warn"), ({"ts": ts, "failed": 7}, 7, "crit"), ({"ts": ts, "ok": False}, 1, "warn"), ({"ts": ts, "ok": True}, 0, None)):
        write(os.path.join(st, "box_verify.json"), json.dumps(body))
        rep = collect(r)
        check("drift: %s -> %s" % (list(body.items())[1:], expect), rep["drift"]["count"] == n and sev(rep, "drift", "box") == expect, str(rep["drift"]))
    rv = lambda items, **k: json.dumps(dict({"ts": NOW - 600.0, "mode": "shadow", "ok": not items, "counts": {"drift": len(items)}, "items": items, "accepted": []}, **k))  # noqa: E731  (the real ops/box_verify.py shape)
    it = lambda key, sev_="warn", cls="code": {"key": key, "sev": sev_, "class": cls, "msg": "m", "fix": "fix " + key}  # noqa: E731
    write(os.path.join(st, "box_verify.json"), rv([]))
    check("drift: real shape, zero items -> ok", collect(r)["drift"]["count"] == 0 and not bs(collect(r), "drift"))
    write(os.path.join(st, "box_verify.json"), rv([it("a"), it("b")]))
    check("drift: real shape, 2 warn items -> warn", sev(collect(r), "drift", "box") == "warn")
    write(os.path.join(st, "box_verify.json"), rv([it("a"), it("b", "crit")]))
    check("drift: real shape, ONE crit item makes the breach crit, crit item named first", sev(collect(r), "drift", "box") == "crit" and "b, a" in bs(collect(r), "drift", "box")[0]["hint"])
    write(os.path.join(st, "box_verify.json"), rv([it("a")], counts={"drift": 4}))
    check("drift: counts.drift larger than the listed items is trusted", collect(r)["drift"]["count"] == 4)
    write(os.path.join(st, "box_verify.json"), rv([it("a")], mode="off"))
    check("drift: box_verify switched off is nodata, not a breach", collect(r)["drift"]["state"] == "nodata" and not bs(collect(r), "drift"))
    write(os.path.join(st, "box_verify.json"), rv([], ts=NOW - 27 * H))
    check("drift: real shape, epoch ts older than 26h -> stale warn", sev(collect(r), "drift", "box_verify_stale") == "warn")
    write(os.path.join(st, "box_verify.json"), json.dumps({"ts": ts, "drift": [{"name": "android-sdk missing"}]}))
    check("drift: the first finding names are in the hint", "android-sdk missing" in bs(collect(r), "drift", "box")[0]["hint"])
    old = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(NOW - 26 * H))
    write(os.path.join(st, "box_verify.json"), json.dumps({"ts": old, "drift": []}))
    check("drift: a box_verify older than 26h is a warn of its own", sev(collect(r), "drift", "box_verify_stale") == "warn")
    write(os.path.join(st, "box_verify.json"), json.dumps({"ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(NOW - 25.9 * H)), "drift": []}))
    check("drift: 25.9h old is still fresh enough", not bs(collect(r), "drift"))


# ================================================================================ 3. tracker, ranking, hourly line, switch
def t_tracker_rank_line():
    prev = None
    b = lambda **k: dict(dict(key="gate_stall:x", slo="gate_stall", scope="x", severity="warn", value=3, threshold=3, unit="h", hint="h", fix="docs/FLEET_RUNBOOK.md#gate-stall", since_ts=None), **k)  # noqa: E731
    trk, out = slo.track(None, [b()], NOW, 1200)
    check("tracker: first sight = now, 0 hours", out[0]["since"] == NOW and out[0]["hours"] == 0)
    t_ = NOW
    for _ in range(8):      # a run every 15 minutes for 2 hours
        t_ += 900
        trk, out = slo.track(trk, [b()], t_, 2400)
    check("tracker: first-seen survives between runs", out[0]["since"] == NOW and out[0]["hours"] == 2.0, str(out[0]))
    trk2, _ = slo.track(trk, [], t_ + 900, 2400)
    trk3, out = slo.track(trk2, [b()], t_ + 1800, 2400)
    check("tracker: one green run inside the grace keeps the clock", out[0]["since"] == NOW, str(out[0]))
    trk4, _ = slo.track(trk, [], t_ + 2401, 2400)
    check("tracker: absent longer than the grace is forgotten", b()["key"] not in trk4)
    trk5, out = slo.track(trk4, [b()], t_ + 3 * H, 2400)
    check("tracker: a new episode starts a new clock", out[0]["since"] == t_ + 3 * H)
    trk6, out = slo.track(None, [b(since_ts=NOW - 5 * H)], NOW, 2400)
    check("tracker: a natural start (since_ts) wins over first sight", out[0]["hours"] == 5.0)
    # ranking: crit first, then weight, then age
    items = [b(key="a", slo="bad_share", severity="warn", hours=9), b(key="b", slo="prod_health", severity="warn", hours=0), b(key="c", slo="runway", severity="crit", hours=1),
             b(key="d", slo="gate_stall", severity="crit", hours=0.5), b(key="e", slo="gate_stall", severity="crit", hours=5, scope="y")]
    order = [x["key"] for x in slo.rank(items)]
    check("rank: crit before warn, then SLO weight, then age", order == ["e", "d", "c", "b", "a"], str(order))
    # the one line
    rep = {"breaches": [dict(b(hint="x" * 400, severity="crit", value=7.5, unit="h", hours=2.5, scope="iptv_apps/claude_feature(gate)")), dict(b(hours=0.5, key="z"))], "thresholds": {}}
    ln = slo.notify_line(rep)
    check("line: one line, capped, with the runbook-visible dashboard pointer", ln and "\n" not in ln and len(ln) <= 240 and ln.endswith("-> www/fleet_slo.md") and "gate_stall" in ln and "(1 crit)" in ln, str(ln))
    check("line: shows the age", "(2.5h)" in ln)
    check("line: only the long breach is counted", "SLO breach >1h: 1 " in ln, ln)
    rep2 = {"breaches": [b(hours=1.0)], "thresholds": {}}
    check("line: exactly 1h is NOT yet > 1h", slo.notify_line(rep2) is None)
    rep2["breaches"][0]["hours"] = 1.01
    check("line: just over 1h is", slo.notify_line(rep2) is not None)
    check("line: nothing in breach -> no line", slo.notify_line({"breaches": []}) is None)


def t_switch_and_cli():
    r = mk_root(fixture=True)
    st = env(r)
    check("mode: default is shadow", slo.mode(st) == "shadow")
    write(os.path.join(st, "fleet_slo.mode"), "on\n")
    check("mode: the mode file is read", slo.mode(st) == "on")
    os.environ["OVN_FLEET_SLO"] = "off"
    check("mode: env beats the file", slo.mode(st) == "off")
    os.environ["OVN_FLEET_SLO"] = "banana"
    check("mode: garbage is shadow, never on", slo.mode(st) == "shadow")
    os.environ.pop("OVN_FLEET_SLO")
    write(os.path.join(st, "fleet_slo.mode"), "enable\n")
    check("mode: a garbage file is shadow", slo.mode(st) == "shadow")
    os.remove(os.path.join(st, "fleet_slo.mode"))
    # cron entry point in each mode
    www = os.path.join(r, "www")
    rep, m = slo.run(now=NOW, root=r, state=st, www=www, net=False, dry=True)
    check("run: --dry-run writes nothing", m == "shadow" and rep and not os.path.exists(os.path.join(st, "fleet_slo.json")) and not os.path.exists(os.path.join(www, "fleet_slo.md")))
    rep, m = slo.run(now=NOW, root=r, state=st, www=www, net=False)
    j = json.load(open(os.path.join(st, "fleet_slo.json")))
    md = open(os.path.join(www, "fleet_slo.md")).read()
    check("run: shadow writes json + markdown + tracker + log", j["mode"] == "shadow" and "# Fleet SLO summary" in md and "## Breaches (ranked)" in md and os.path.exists(os.path.join(st, "fleet_slo_state.json")) and os.path.exists(os.path.join(r, "logs", "fleet_slo.log")))
    check("run: markdown links every breach to a runbook anchor", all(("FLEET_RUNBOOK.md#" + slo.FIX[b["slo"]]) in md for b in j["breaches"]) and j["breaches"])
    check("run: json has the documented keys", all(k in j for k in ("repos", "lanes", "deploy", "backup", "prod", "evidence", "drift", "breaches", "nodata", "summary", "notify_line", "thresholds")))
    check("run: json holds no tracker internals", "_tracker" not in j and "_bad_rows" not in json.dumps(j))
    check("shadow: hourly update stays silent even with a long breach", slo.update_lines(st, NOW) == [])
    # a long breach, run twice 2h apart: line exists in the json (shadow) and in the update only when on
    write(os.path.join(st, "hygiene_gate_streak", "xlite__claude_feature"), "4 1 0 %s\n" % time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(NOW + 2 * H - 7 * H)))
    rep, _ = slo.run(now=NOW + 2 * H, root=r, state=st, www=www, net=False)
    check("run: a 7h-old gate stall makes the notify line (shadow: json only)", rep["notify_line"] and "gate_stall" in rep["notify_line"] and slo.update_lines(st, NOW + 2 * H) == [], str(rep["notify_line"]))
    write(os.path.join(st, "fleet_slo.mode"), "on\n")
    ul = slo.update_lines(st, NOW + 2 * H)
    check("on: the hourly update gets exactly that ONE line", ul == [rep["notify_line"]], str(ul))
    ul = slo.update_lines(st, NOW + 2 * H + 3 * H + 1)
    check("on: a summary older than 3h is itself reported (cron died)", len(ul) == 1 and "stale" in ul[0] and "FLEET_RUNBOOK" in ul[0], str(ul))
    ul = slo.update_lines(st, NOW + 2 * H + 3 * H - 1)
    check("on: a summary just under 3h old is trusted", len(ul) == 1 and "stale" not in ul[0])
    os.remove(os.path.join(st, "fleet_slo.json"))
    ul = slo.update_lines(st, NOW)
    check("on: a missing summary is reported", len(ul) == 1 and "missing" in ul[0])
    write(os.path.join(st, "fleet_slo.mode"), "off\n")
    before = os.path.getmtime(os.path.join(st, "fleet_slo_state.json"))
    rep, m = slo.run(now=NOW + 9 * H, root=r, state=st, www=www, net=False)
    check("off: the job does nothing and writes nothing", rep is None and m == "off" and not os.path.exists(os.path.join(st, "fleet_slo.json")) and os.path.getmtime(os.path.join(st, "fleet_slo_state.json")) == before)
    check("off: the hourly update adds nothing", slo.update_lines(st, NOW) == [])
    # CLI
    env_ = {"OVN_NOTIFY_STATE": st, "OVN_DIR": r, "OVN_SLO_PROD_CHECK": "off", "OVN_SLO_BACKUP_DIR": os.path.join(r, "bb")}
    p = sh([sys.executable, SRC, "mode", "on"], extra_env=env_)
    check("cli: mode on writes the file", p.returncode == 0 and open(os.path.join(st, "fleet_slo.mode")).read().strip() == "on", p.stderr)
    p = sh([sys.executable, SRC, "mode", "bogus"], extra_env=env_)
    check("cli: mode bogus is refused", p.returncode == 2)
    p = sh([sys.executable, SRC, "mode"], extra_env=env_)
    check("cli: mode shows the current one", p.stdout.strip() == "on")
    sh([sys.executable, SRC, "mode", "shadow"], extra_env=env_)
    p = sh([sys.executable, SRC, "--now", str(NOW + 2 * H)], extra_env=env_)
    check("cli: the cron entry point exits 0 and prints one summary line", p.returncode == 0 and p.stdout.startswith("fleet_slo: ") and "mode=shadow" in p.stdout, p.stdout + p.stderr)
    p = sh([sys.executable, SRC, "--json", "--dry-run", "--now", str(NOW)], extra_env=env_)
    check("cli: --json prints parseable json", p.returncode == 0 and json.loads(p.stdout)["version"] == 1)
    p = sh([sys.executable, SRC, "mark-deployed", "--sha", "zzz"], extra_env=env_)
    check("cli: mark-deployed refuses a non-hex sha", p.returncode == 2)
    # robustness: garbage state files never crash the run
    write(os.path.join(st, "outcomes.jsonl"), "not json\n\x00\x00\n{\"ts\": 1}\n")
    write(os.path.join(st, "failure_clusters.json"), "{")
    write(os.path.join(st, "box_verify.json"), "[1,")
    write(os.path.join(st, "landing_audits.jsonl"), "x\n{\"repo\":\"a\"}\n")
    p = sh([sys.executable, SRC, "--dry-run", "--json", "--now", str(NOW)], extra_env=env_)
    check("robust: garbage input files do not crash the run", p.returncode == 0 and json.loads(p.stdout)["version"] == 1, p.stderr[-300:])


def t_blip():
    """End to end through run(): breach seen, one clean run inside the grace, breach back: the clock did not restart."""
    r = mk_root()
    st = env(r)
    supply_report(r, {})
    www = os.path.join(r, "www")
    def go(t):
        supply_report(r, {"a": {"pullable": 5, "starving": False, "runway_h": 20}}, ts=t)
        return slo.run(now=t, root=r, state=st, www=www, net=False)[0]
    write(os.path.join(r, "tasks.json"), "[]")
    paused = os.path.join(st, "PAUSED")
    go(NOW)             # lane a: work pullable, no attempt -> landing_rate warn (no natural start time)
    write(paused, "")
    go(NOW + 900)              # one blip: paused queue reports no landing breach
    os.remove(paused)
    c = go(NOW + 1800)
    g = bs(c, "landing_rate", "a")
    check("blip: the clock survives a one-run blip (first seen at the first run, not the third)", len(g) == 1 and g[0]["hours"] == 0.5, str(g))
    go(NOW + 1800 + 2401)
    write(paused, "")
    go(NOW + 1800 + 2401 + 900)
    go(NOW + 1800 + 2401 + 1800)
    go(NOW + 1800 + 2401 + 2700)
    os.remove(paused)
    c = go(NOW + 1800 + 2401 + 3601)
    g = bs(c, "landing_rate", "a")
    check("blip: three clean runs in a row (longer than the grace) restart the clock", len(g) == 1 and g[0]["hours"] == 0.0, str(g))


def t_notify_integration():
    """The real ovn_notify.compose_update carries the line only in mode on."""
    st = os.path.join(HQ, "state")
    j = {"version": 1, "ts": NOW, "notify_line": "SLO breach >1h: 1 (1 crit) - gate_stall x (7h): hint -> www/fleet_slo.md", "breaches": []}
    write(os.path.join(st, "fleet_slo.json"), json.dumps(j))
    notify.now = lambda: NOW
    if os.path.exists(os.path.join(st, "fleet_slo.mode")):
        os.remove(os.path.join(st, "fleet_slo.mode"))
    _, body, _ = notify.compose_update(at=NOW)
    check("hourly: shadow mode adds no SLO line", "SLO breach" not in body, body)
    write(os.path.join(st, "fleet_slo.mode"), "on\n")
    _, body, _ = notify.compose_update(at=NOW)
    check("hourly: mode on adds the ONE line", body.count("SLO breach") == 1 and "gate_stall x (7h)" in body, body)
    write(os.path.join(st, "fleet_slo.mode"), "off\n")
    _, body, _ = notify.compose_update(at=NOW)
    check("hourly: mode off adds nothing", "SLO" not in body.replace("Shrike", ""), body)
    write(os.path.join(st, "fleet_slo.mode"), "on\n")
    j["ts"] = NOW - 5 * H
    write(os.path.join(st, "fleet_slo.json"), json.dumps(j))
    _, body, _ = notify.compose_update(at=NOW)
    check("hourly: a stale summary says so instead of repeating an old line", "SLO summary stale" in body and "gate_stall" not in body, body)
    j["ts"] = NOW
    j["notify_line"] = None
    write(os.path.join(st, "fleet_slo.json"), json.dumps(j))
    _, body, _ = notify.compose_update(at=NOW)
    check("hourly: no breach > 1h -> no SLO line", "SLO" not in body.replace("Shrike", ""), body)
    os.remove(os.path.join(st, "fleet_slo.mode"))


# ================================================================================ 4. git: tip export + Mac script
def t_export_tip():
    if MUTANT_RUN and not os.environ.get("SLO_RUN_GIT"):
        return
    w = os.path.join(BASE, "tipsrc")
    os.makedirs(w)
    git(w, "init", "-q", "-b", "claude/feature")
    for i, (p, age) in enumerate((("scripts/overnight-queue/a.sh", 50), ("docs/x.md", 40), ("scripts/overnight-queue/b.sh", 30), ("other/y.txt", 20))):
        write(os.path.join(w, p), "v%d\n" % i)
        git(w, "add", "-A")
        git(w, "commit", "-q", "-m", "c%d" % i, date=NOW - age * H)
    t = slo.export_tip(w, ref="claude/feature", now=NOW)
    check("tip: only commits touching the queue path, newest first, with committer epochs", t["ok"] and [c[1] for c in t["commits"]] == [int(NOW - 30 * H), int(NOW - 50 * H)], str(t))
    check("tip: head is the true branch head (even if it touches another path)", t["head"] == git(w, "rev-parse", "claude/feature"))
    t2 = slo.export_tip(w, ref="claude/feature", path="", now=NOW)
    check("tip: an empty path means every commit", len(t2["commits"]) == 4)
    check("tip: all_commits is the whole branch (4 commits, newest first), so a non-queue deployed sha can be placed", [c[1] for c in t["all_commits"]] == [int(NOW - 20 * H), int(NOW - 30 * H), int(NOW - 40 * H), int(NOW - 50 * H)], str(t["all_commits"]))
    check("tip: with no path filter all_commits == commits", t2["all_commits"] == t2["commits"])
    t3 = slo.export_tip(w, ref="no/such", now=NOW)
    check("tip: an unknown ref is ok=false, never an exception", t3["ok"] is False and t3["commits"] == [])
    # in-process mode used by OVN_SLO_GIT_DIR + deployed = second newest tip commit
    r = mk_root()
    st = env(r, OVN_SLO_GIT_DIR=w)
    supply_report(r, {})
    # the module resolves "origin/claude/feature"; point a remote-tracking ref at the branch
    git(w, "update-ref", "refs/remotes/origin/claude/feature", "claude/feature")
    write(os.path.join(st, "deployed_sha"), t["commits"][1][0] + "\n")
    rep = collect(r)
    check("tip: OVN_SLO_GIT_DIR computes lag in-process (30h undeployed -> crit)", rep["deploy"]["box"]["behind"] == 1 and sev(rep, "deploy_lag") == "crit", str(rep["deploy"]["box"]))
    write(os.path.join(st, "deployed_sha"), git(w, "rev-parse", "claude/feature") + "\n")      # HEAD = other/y.txt, touches no queue file
    check("tip: in-process, a box on the branch HEAD that touches no queue file is ok (not a false crit)", collect(r)["deploy"]["box"]["state"] == "ok" and not bs(collect(r), "deploy_lag"), str(collect(r)["deploy"]["box"]))
    write(os.path.join(st, "deployed_sha"), git(w, "rev-parse", "claude/feature~1") + "\n")  # docs-free: other/y.txt's parent is b.sh
    check("tip: in-process, the box one non-queue commit behind HEAD but on the last queue commit is ok", collect(r)["deploy"]["box"]["state"] == "ok")
    write(os.path.join(st, "deployed_sha"), git(w, "rev-parse", "claude/feature~2") + "\n")  # docs/x.md: after a.sh (50h), before b.sh (30h)
    d = collect(r)["deploy"]["box"]
    check("tip: in-process, a non-queue deployed commit (docs/x.md) is placed: b.sh (30h) is undeployed -> crit", d["state"] == "behind" and d["behind"] == 1 and sev(collect(r), "deploy_lag") == "crit", str(d))
    os.environ.pop("OVN_SLO_GIT_DIR", None)
    # the Mac script against a local remote and a stub ssh
    script = os.path.join(SCRIPTS, "ovn_slo_export_tip.sh")
    cache = os.path.join(BASE, "cache.git")
    stub = os.path.join(BASE, "stub_ssh.sh")
    out = os.path.join(BASE, "stub_out.json")
    write(stub, "#!/bin/sh\necho \"$@\" > \"%s.args\"\ncat > \"%s\"\n" % (out, out))
    os.chmod(stub, 0o755)
    e = {"OVN_SLO_TIP_REMOTE": w, "OVN_SLO_TIP_CACHE": cache, "OVN_SLO_BRANCH": "claude/feature", "OVN_SLO_SSH": stub, "OVN_SLO_BOX": "fakebox"}
    p = sh(["bash", script, "--stdout"], extra_env=e)
    j = json.loads(p.stdout or "{}")
    check("mac script: --stdout prints the export and sends nothing", p.returncode == 0 and j.get("ok") and len(j["commits"]) == 2 and not os.path.exists(out), p.stdout + p.stderr)
    write(os.path.join(w, "scripts/overnight-queue/c.sh"), "new\n")
    git(w, "add", "-A")
    git(w, "commit", "-q", "-m", "c9", date=NOW - 1 * H)
    p = sh(["bash", script], extra_env=e)
    sent = json.loads(open(out).read()) if os.path.exists(out) else {}
    check("mac script: fetches the new commit into its OWN bare clone and sends it through ssh", p.returncode == 0 and len(sent.get("commits", [])) == 3 and "state/claude_feature_tip.json" in open(out + ".args").read(), p.stdout + p.stderr)
    check("mac script: the temp name is moved into place (atomic)", ".claude_feature_tip.tmp" in open(out + ".args").read() and "mv -f" in open(out + ".args").read())
    os.remove(out)
    p = sh(["bash", script], extra_env=dict(e, OVN_SLO_BRANCH="nope"))
    check("mac script: a failing fetch sends nothing and fails loudly", p.returncode != 0 and not os.path.exists(out), p.stdout + p.stderr)
    p = sh(["bash", script], extra_env=dict(e, OVN_SLO_TIP_CACHE="relative/path"))
    check("mac script: a relative cache path is refused", p.returncode != 0 and "absolute" in p.stderr)
    failing = os.path.join(BASE, "fail_ssh.sh")
    write(failing, "#!/bin/sh\ncat >/dev/null\nexit 255\n")
    os.chmod(failing, 0o755)
    p = sh(["bash", script], extra_env=dict(e, OVN_SLO_SSH=failing))
    check("mac script: an unreachable box is a loud failure", p.returncode != 0 and "could not reach" in p.stderr, p.stderr)


# ================================================================================ 5. install + docs wiring
def t_wiring():
    if MUTANT_RUN:
        return
    root = os.path.abspath(os.path.join(SCRIPTS, ".."))
    prop = open(os.path.join(root, "ops", "cron.slo.proposed.txt")).read()
    live = [l for l in prop.splitlines() if l.strip() and not l.startswith("#")]
    check("cron: one live line, every 15 min, read-only job, appends to its own log", len(live) == 1 and live[0].startswith("*/15 ") and "scripts/ovn_fleet_slo.py" in live[0] and "fleet_slo.cron.log" in live[0], str(live))
    check("cron: no mode, no enforce, no push in the line", not any(x in live[0] for x in ("enforce", "mode on", "git push", "queue.sh", "OVN_FLEET_SLO=on")))
    rbp = os.path.join(root, "..", "..", "docs", "FLEET_RUNBOOK.md")
    if os.path.isfile(rbp) or os.environ.get("OVN_SLO_REQUIRE_DOCS"):
        rb = open(rbp).read()
        anchors = {a for a in slo.FIX.values()}
        miss = [a for a in anchors if "\n## %s\n" % a not in rb]
        check("runbook: every SLO anchor has a section", not miss, str(miss))
        check("runbook: the five named tools are mapped", all(x in rb for x in ("box_verify", "mac_jobs_health", "gate governor", "ovn_supply_report.py", "safe deploy")))
        check("runbook: the SLO-job section exists (stale/missing summary line points at it)", "\n## slo-job\n" in rb)
    else:
        print("  SKIP: docs/FLEET_RUNBOOK.md is not part of this tree (the deployed queue dir has no docs/); checked on the Mac and in git")
    # the fixture files must be TRACKED: .gitignore has *.json, *.log and logs/, so a plain `git add` silently drops most of them and the suite only passes on the author's disk
    fx = os.path.join(SCRIPTS, "test", "fixtures", "fleet_slo")
    on_disk = sorted(os.path.relpath(os.path.join(d, f), fx) for d, _, fs in os.walk(fx) for f in fs)
    lf = sh(["git", "ls-files", "--", "."], cwd=fx)
    if lf.returncode == 0 and lf.stdout.strip():
        tracked = sorted(os.path.relpath(os.path.join(fx, x), fx) for x in [os.path.join(os.path.dirname(l), os.path.basename(l)) for l in lf.stdout.split()])
        untracked = [f for f in on_disk if f not in tracked]
        check("fixtures: every fixture file is tracked by git (use `git add -f`)", not untracked, str(untracked))
    else:
        print("  SKIP: not a git checkout (deployed tree): fixture tracking cannot be checked here")
    inst = os.path.join(root, "ops", "install_slo_cron.sh")
    check("installer: shipped and uses its own markers", os.path.isfile(inst) and "SLO-LINES BEGIN" in open(inst).read() and "SUPPLY-LINES" not in open(inst).read())
    # dry-run install against a stub crontab: shows the block, changes nothing
    tmp = os.path.join(BASE, "inst")
    os.makedirs(os.path.join(tmp, "bin"))
    os.makedirs(os.path.join(tmp, "home"))
    write(os.path.join(tmp, "bin", "crontab"), "#!/bin/sh\nif [ \"$1\" = -l ]; then cat \"%s/cur\" 2>/dev/null; exit 0; fi\ncp \"$1\" \"%s/cur\"\n" % (tmp, tmp))
    os.chmod(os.path.join(tmp, "bin", "crontab"), 0o755)
    write(os.path.join(tmp, "cur"), "0 1 * * * echo keep\n")
    ovn = os.path.join(tmp, "q")
    os.makedirs(os.path.join(ovn, "scripts"))
    open(os.path.join(ovn, "scripts", "ovn_fleet_slo.py"), "w").write("#")
    os.makedirs(os.path.join(ovn, "scripts", "test"))
    shutil.copy(os.path.join(SCRIPTS, "test", "lib_safe_tmp.sh"), os.path.join(ovn, "scripts", "test"))
    ex = {"PATH": os.path.join(tmp, "bin") + ":" + os.environ["PATH"], "HOME": os.path.join(tmp, "home"), "OVN_DIR": ovn, "SLO_CRON_PROPOSAL": os.path.join(root, "ops", "cron.slo.proposed.txt")}
    p = sh(["bash", inst], extra_env=ex)
    check("installer: dry run shows the block and writes nothing", p.returncode == 0 and "DRY RUN" in p.stdout and "ON  fleet_slo" in p.stdout and open(os.path.join(tmp, "cur")).read() == "0 1 * * * echo keep\n", p.stdout + p.stderr)
    p = sh(["bash", inst, "--apply"], extra_env=ex)
    cur = open(os.path.join(tmp, "cur")).read()
    check("installer: --apply keeps the old lines and adds ONE marked block", p.returncode == 0 and "echo keep" in cur and cur.count("SLO-LINES BEGIN") == 1 and "ovn_fleet_slo.py" in cur, p.stdout + p.stderr)
    p = sh(["bash", inst, "--apply", "--remove"], extra_env=ex)
    check("installer: --remove is a byte-exact rollback", p.returncode == 0 and open(os.path.join(tmp, "cur")).read() == "0 1 * * * echo keep\n", p.stdout + p.stderr)
    # duplicate-run guard (2026-10-18 review: key_of needed a word after the script, so `ovn_fleet_slo.py >> log` never matched and a second */15 line was appended)
    def dry(installer, cur):
        write(os.path.join(tmp, "cur"), cur)
        os.makedirs(os.path.join(ovn, "ops"), exist_ok=True)
        shutil.copy(installer, os.path.join(ovn, "ops", "install_slo_cron.sh"))
        q = sh(["bash", os.path.join(ovn, "ops", "install_slo_cron.sh")], extra_env=ex)
        return q.stdout + q.stderr
    HANDS = (("redirect", "*/10 * * * * cd $HOME/overnight-queue && python3 scripts/ovn_fleet_slo.py >> logs/mine.log 2>&1\n"),
             ("run subcommand", "*/10 * * * * cd ~/overnight-queue; python3 scripts/ovn_fleet_slo.py run\n"),
             ("bare", "*/10 * * * * python3 scripts/ovn_fleet_slo.py\n"),
             ("2>&1 only", "*/10 * * * * python3 scripts/ovn_fleet_slo.py 2>&1 | logger\n"),
             ("semicolon", "*/10 * * * * python3 scripts/ovn_fleet_slo.py; echo x\n"))
    for label, hand in HANDS:
        o = dry(inst, hand + "0 1 * * * echo keep\n")
        check("installer dup guard: hand-installed '%s' line -> SKIP fleet_slo, nothing appended" % label, "SKIP fleet_slo" in o and "ON  fleet_slo" not in o and "REFUSED" in o and "nothing to install" in o, o)
    for label, hand in (("another subcommand (mark-deployed)", "*/10 * * * * python3 scripts/ovn_fleet_slo.py mark-deployed --sha abc\n"), ("a commented line", "# */10 * * * * python3 scripts/ovn_fleet_slo.py >> x\n"), ("another script", "*/10 * * * * python3 scripts/ovn_fleet_slo_other.py >> x\n"), ("mode", "*/10 * * * * python3 scripts/ovn_fleet_slo.py mode on\n")):
        o = dry(inst, hand)
        check("installer dup guard: %s is NOT a duplicate (installs)" % label, "ON  fleet_slo" in o and "SKIP" not in o, o)
    src_inst = open(inst).read()
    for mname, mold, mnew in (("dup guard always false", "dup = [l for l in live_outside if runs_same_job(l, kk)]", "dup = []"),
                              ("old key_of: needs a word after the script", '(?![A-Za-z0-9_.])(?:\\s+([A-Za-z0-9_-]+)(?![A-Za-z0-9_>]))?", line)', '\\s+([A-Za-z0-9_-]+)", line)'),
                              ("any subcommand counts as a duplicate", 'elif nxt == "" or nxt == "run" or not re.match(r"[A-Za-z-]", nxt): return True', "else: return True")):
        if src_inst.count(mold) != 1:
            check("installer mutant '%s': anchor present exactly once" % mname, False, str(src_inst.count(mold)))
            continue
        mp = os.path.join(BASE, "inst_mut.sh")
        write(mp, src_inst.replace(mold, mnew))
        bad = []
        for label, hand in HANDS:
            if "SKIP fleet_slo" not in dry(mp, hand + "0 1 * * * echo keep\n"):
                bad.append(label)
        for label, hand in (("sub", "*/10 * * * * python3 scripts/ovn_fleet_slo.py mark-deployed --sha abc\n"), ("mode", "*/10 * * * * python3 scripts/ovn_fleet_slo.py mode on\n")):
            if "SKIP fleet_slo" in dry(mp, hand):
                bad.append(label)
        check("installer mutant '%s' is killed by the dup-guard cases" % mname, bool(bad), "survived")
    dry(inst, "0 1 * * * echo keep\n")


# ================================================================================ mutants
MUTANTS = [
    ("grade: >= -> > on crit", 'return "crit" if value >= crit else ("warn" if value >= warn else None)', 'return "crit" if value > crit else ("warn" if value >= warn else None)'),
    ("grade: >= -> > on warn", '("warn" if value >= warn else None)\n    return', '("warn" if value > warn else None)\n    return'),
    ("notify window: > -> >=", 'if (b.get("hours") or 0) > c["notify_h"]]', 'if (b.get("hours") or 0) >= c["notify_h"]]'),
    ("landing: < -> <=", 'elif lo["landed"] < c["landed_min"]:', 'elif lo["landed"] <= c["landed_min"]:'),
    ("bad share min attempts: >= -> >", 'if lo["bad_share"] is not None and lo["attempts"] >= c["min_attempts"]:', 'if lo["bad_share"] is not None and lo["attempts"] > c["min_attempts"]:'),
    ("false credit sample: >= -> >", 'if n >= c["fc_min"] else None\n        if sev:\n            repo_breached', 'if n > c["fc_min"] else None\n        if sev:\n            repo_breached'),
    ("false credit: first verdict wins", 'last[(d["repo"], str(d.get("ref", "")))] = d', 'last.setdefault((d["repo"], str(d.get("ref", ""))), d)'),
    ("gate stall hours halved", '"stall_h": max(0.0, _h(now - first))', '"stall_h": max(0.0, _h(now - first) / 2)'),
    ("promote hold ignored", "        elif r in hold:", "        elif False:"),
    ("tracker grace disabled", 'if isinstance(v, dict) and now - float(v.get("last_seen", 0)) <= grace_s:', 'if isinstance(v, dict) and now - float(v.get("last_seen", 0)) < 0:'),
    ("rank: warn before crit", '-SEV_RANK[b["severity"]]', 'SEV_RANK[b["severity"]]'),
    ("mode default on", 'v = (v or "shadow").strip().lower()', 'v = (v or "on").strip().lower()'),
    ("mode garbage -> on", 'return v if v in ("off", "shadow", "on") else "shadow"', 'return v if v in ("off", "shadow", "on") else "on"'),
    ("update_lines ignores mode", 'if mode(state) != "on":\n            return []', 'if mode(state) == "off":\n            return []'),
    ("deploy lag uses the wrong commit", 'first_missing = tip["commits"][idx - 1]', 'first_missing = tip["commits"][idx]'),
    ("backup age halved", "age = _h(now - ts)\n            sev = grade(age, warn, crit)", "age = _h(now - ts) / 2\n            sev = grade(age, warn, crit)"),
    ("prod: 3xx not up", "200 <= code < 400", "200 <= code < 300"),
    ("prod: follow redirects", "urllib.request.build_opener(_NoRedirect)", "urllib.request.build_opener()"),
    ("evidence crit factor", 'grade(age, lim, lim * c["ev_crit_x"])', "grade(age, lim, lim * 100)"),
    ("landing counted while paused", "        if paused:\n            rec[\"landing\"] = \"paused\"", "        if False:\n            rec[\"landing\"] = \"paused\""),
    ("drift warn at 2", "grade(n, 1, c[\"drift_crit\"])", "grade(n, 2, c[\"drift_crit\"])"),
    ("stale summary trusted", 'if age > _f("OVN_SLO_STALE_H", 3):', 'if age > _f("OVN_SLO_STALE_H", 3000):'),
    ("skipped rows counted as attempts", 'r.get("class") not in ("skipped", "landed-late", "credit-only")', 'r.get("class") not in ("landed-late", "credit-only")'),
    ("redirected tip: path filter dropped", 'args += ["--", path]', "pass"),
    ("shadow writes the hourly line (notify reads shadow)", 'return [d["notify_line"]] if d.get("notify_line") else []', 'return [d["notify_line"]] if d.get("notify_line") else ["SLO ok"]'),
    ("promote note: post-check banner not filtered", 'BENIGN = re.compile(r"post-promote check started|FAILED\\s*=>|', 'BENIGN = re.compile(r"'),
    ("drift: a crit item does not make the breach crit", 'sev = "crit" if any_crit else grade(n, 1, c["drift_crit"])', 'sev = grade(n, 1, c["drift_crit"])'),
    ("drift: counts.drift ignored", "if isinstance(cn, int) and not isinstance(cn, bool) and cn > len(items):", "if False:"),
    ("deploy: sha equal to the branch head not ok (tip head)", 'if idx == 0 or same(tip.get("head"), dep["sha"]):', "if idx == 0:"),
    ("deploy: placed sha with nothing newer still lags", "            if not newer:", "            if False:"),
    ("deploy: unplaceable sha always warns (tip)", "if ts is not None and float(ts) < oldest and fa - float(ts) > c[\"deploy_warn\"] * 3600:", "if True:"),
    ("deploy: old record warn becomes crit (tip)", 'return rec, [breach("deploy_lag", "box", "warn", round(_h(now - float(ts)), 1)', 'return rec, [breach("deploy_lag", "box", "crit", round(_h(now - float(ts)), 1)'),
    ("deploy: unplaceable sha graded from the oldest tip commit (the old bug)", 'oldest = min(x[1] for x in (allc or tip["commits"]))\n        fa = float(tip.get("fetched_at") or 0)', 'oldest = min(x[1] for x in (allc or tip["commits"]))\n        return rec, [breach("deploy_lag", "box", "crit", round(_h(now - oldest), 1), c["deploy_warn"], "x", since_ts=oldest, unit="h")]\n        fa = 0'),
    ("tip export: whole-branch list dropped (tip)", "    all_commits = commits\n    if path:", "    all_commits = commits\n    if False:"),
    ("landing: unknown supply guessed as not running", 'elif lo["landed"] < c["landed_min"] and lo["attempts"] == 0 and pullable is None:', "elif False:"),
    ("gate: .tmp files become lanes", 'if name.endswith(".tmp") or ".tmp." in name or "__" not in name:', 'if "__" not in name:'),
    ("gate: no-separator names become lanes", 'if name.endswith(".tmp") or ".tmp." in name or "__" not in name:', 'if name.endswith(".tmp") or ".tmp." in name:'),
    ("promote: tree-identical shortcut dropped", 'if rec["ahead"] == 0 or _git(["diff", "--quiet", "origin/main", "origin/develop"], rd)[0] == 0:', 'if rec["ahead"] == 0:'),
    ("promote note: benign lines quoted", "if BLOCKER.search(l) and not BENIGN.search(l):", "if BLOCKER.search(l):"),
    ("promote note: PROMOTED does not clear (promote)", 'if cur and re.search(r"\\bPROMOTED\\b", l):', "if False:"),
    ("promote note: newer section does not replace older (promote)", "            cur = m.group(1)\n            notes.pop(cur, None)", "            cur = m.group(1)"),
    ("promote note: a count ending in 0 is benign (promote)", "|\\b0 develop merge\\(s\\) held back|", "|0 develop merge\\(s\\) held back|"),
    ("false-credit rate counts oks as false", 'per[a["repo"]][1] += 1 if a["_false"] else 0', "per[a[\"repo\"]][1] += 1"),
]


def run_mutants():
    me = os.path.abspath(__file__)
    src = open(SRC).read()
    killed, alive = 0, []
    for name, old, new in MUTANTS:
        if src.count(old) < 1:
            alive.append("%s (pattern not found: the mutant would be vacuous)" % name)
            continue
        mp = os.path.join(BASE, "mutant_%d.py" % (killed + len(alive)))
        write(mp, src.replace(old, new, 1))
        p = subprocess.run([sys.executable, me], env=dict(os.environ, SLO_PATH=mp, SLO_RUN_GIT="1" if ("tip" in name or "promote" in name) else ""), capture_output=True, text=True)
        if p.returncode != 0:
            killed += 1
        else:
            alive.append(name)
    return killed, alive


def main():
    for fn in (t_real, t_grade, t_landing_and_bad, t_false_credit, t_gate, t_deploy_lag, t_promote_lag, t_backup, t_prod, t_evidence, t_drift, t_tracker_rank_line, t_switch_and_cli, t_blip,
               t_notify_integration, t_export_tip, t_wiring):
        try:
            fn()
        except Exception as e:  # noqa: BLE001 - a crashing test is a failing test
            import traceback
            N[0] += 1
            FAILS.append("%s raised %r" % (fn.__name__, e))
            traceback.print_exc()
    if not MUTANT_RUN and not os.environ.get("SLO_SKIP_MUTANTS"):
        killed, alive = run_mutants()
        check("mutants: every one of %d is killed" % len(MUTANTS), not alive, "SURVIVED: %s" % alive)
        print("mutants killed %d/%d" % (killed, len(MUTANTS)))
    print("%d checks, %d failed" % (N[0], len(FAILS)))
    for f in FAILS:
        print("  - " + f)
    return 1 if FAILS else 0


if __name__ == "__main__":
    sys.exit(main())
