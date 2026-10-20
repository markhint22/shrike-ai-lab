#!/usr/bin/env python3
"""ovn_fleet_slo.py - ONE fleet health view with explicit SLOs, breach states and a root-cause hint per breach (2026-10-18, package L5-fleet-slo). Read-only, cron-ready.

Why: five incidents in one week were each visible in some file for hours before a human saw them: fixes on claude/feature sat while the box ran old code; a rebuilt box lacked venv
packages/SDK/QA tools for hours; the Mac checkout stuck on a detached HEAD so launchd jobs ran old scripts and staging evidence went stale; shadow gates let false credits land with no
evidence trail; supply starvation was noticed from an ntfy. This module reads the box state that already exists and says, per repo / lane, which SLO is broken, since when, and why.

SLOs (every threshold is an env var; warn / crit):
  landing_rate   landed in the last 24 h per lane >= OVN_SLO_LANDED_MIN (1) while the lane HAS pullable work and the queue is not PAUSED (crit: >= OVN_SLO_MIN_ATTEMPTS attempts, 0 landed)
  bad_share      share of attempts that threw work away (reverted + no-op that ovn_outcome_buckets calls bad) 24 h:  warn 0.50, crit 0.75, needs >= OVN_SLO_MIN_ATTEMPTS (5) attempts
  false_credit   share of AUDITED landings that were false credits, 7 d, needs >= OVN_SLO_FC_MIN (3) audits: warn 0.05, crit 0.15. The evidence is the audit ledger state/landing_audits.jsonl
                 (append with:  ovn_fleet_slo.py audit --repo R --ref SHA|ITEM --verdict false-credit|ok [--audit NAME] [--gate item-verify] [--note TEXT]; the last verdict per (repo, ref) wins)
  gate_stall     hours a hygiene gate (state/hygiene_gate_streak) or merge (state/hygiene_merge_streak) has been red for a lane: warn 3 h, crit 6 h (the thresholds branch_hygiene.sh alerts at)
  runway         supply runway of a starving repo (ovn_supply_report): breach when starving (runway < OVN_SUPPLY_RUNWAY_H or nothing pullable); crit when nothing is pullable
  deploy_lag     age of the OLDEST claude/feature commit (under scripts/overnight-queue) the box does not run yet: warn 6 h, crit 24 h. Needs state/deployed_sha (the deploy step writes it:
                 `ovn_fleet_slo.py mark-deployed --sha SHA`) and state/claude_feature_tip.json (the Mac pipes `ovn_fleet_slo.py --export-tip` into it hourly). A missing/stale half is reported as such.
  promote_lag    age of the oldest commit on develop that is not on main (git, tree-identical = 0) for each promote repo: warn 36 h, crit 72 h. Repos in OVN_SLO_PROMOTE_HOLD / state/slo_promote_hold.txt are shown as held, not breached.
  backup         age of the newest box-backups heartbeat: hourly warn 3 h / crit 6 h, daily warn 26 h / crit 50 h; a missing drive or file is a breach
  prod_health    HTTP status of every URL in state/slo_prod_urls.txt (else ops/slo_prod_urls.txt; format name|url[|codes]); 200-399 is up; anything else (timeout included) is crit
  evidence       freshness of the promote gate's staging evidence (deploy_export 1800 s, e2e_mac/e2e_box 12 h; the limits qa/evidence_freshness_check.py uses); crit at 4x
  drift          findings in state/box_verify.json (ops/box_verify.py: items[] + counts.drift; any crit item or >= OVN_SLO_DRIFT_CRIT (5) findings is crit, else warn; other shapes with drift/findings/failed/issues lists or counts are tolerated); mode off = no data; a file older than 26 h is itself a warn

Outputs (atomic): state/fleet_slo.json, www/fleet_slo.md (served by the private fleet dashboard server), logs/fleet_slo.log (one line per run, rotated at 1 MB), state/fleet_slo_state.json (when each breach
was first seen, so "in breach for > 1 h" survives between runs and a one-run green blip does not reset it: OVN_SLO_CLEAR_GRACE_S, default 2400: one missed 15-minute run is tolerated, two are not).
Breaches are ranked: crit before warn, then by SLO weight (prod_health, gate_stall, false_credit, deploy_lag, evidence, drift, backup, promote_lag, runway, landing_rate, bad_share), then age.

The hourly update (ovn_notify.py update) gets ONE line from here (update_lines()), only when mode is `on` AND a breach has lasted > OVN_SLO_NOTIFY_H (1) hours; plus one line when the summary
itself has gone stale (the cron died). No alerter of its own.

SWITCH (default SHADOW): mode = env OVN_FLEET_SLO, else the first word of state/fleet_slo.mode, else shadow.
  off      do nothing (rollback: `ovn_fleet_slo.py mode off`, or OVN_FLEET_SLO=off, or remove the cron line)
  shadow   compute + write json/md/log; the would-be hourly line is written to the json/log only
  on       as shadow + the hourly update carries the line
  ovn_fleet_slo.py mode [off|shadow|on]     show / set (writes state/fleet_slo.mode)

usage:  ovn_fleet_slo.py [run] [--dry-run] [--print] [--json] [--now EPOCH] [--no-net]
        ovn_fleet_slo.py audit --repo R --ref REF --verdict false-credit|ok [--audit NAME] [--gate G] [--note T]
        ovn_fleet_slo.py mark-deployed --sha SHA [--ts EPOCH]
        ovn_fleet_slo.py --export-tip [--git-dir D] [--ref origin/claude/feature] [--path scripts/overnight-queue] [--limit 300] [--fetch]   # ON THE MAC; JSON to stdout
        ovn_fleet_slo.py mode [off|shadow|on]
cron (proposed, NOT installed; ops/cron.slo.proposed.txt + ops/install_slo_cron.sh):  */15 * * * * cd ~/overnight-queue && python3 scripts/ovn_fleet_slo.py >> logs/fleet_slo.cron.log 2>&1
env:    OVN_DIR / OVN_NOTIFY_STATE (queue root / state dir), OVN_SLO_WWW, the thresholds above (OVN_SLO_*), OVN_SLO_PROD_CHECK=off (skip the HTTP probes), OVN_SLO_BACKUP_DIR (default
        /run/media/mhintermeister/secondary_drive1/box-backups), OVN_SLO_PROMOTE_REPOS (billwatch iptv_apps), OVN_SLO_GIT_DIR (compute the tip in-process from this checkout),
        OVN_SLO_SCAN_MB (outcomes tail to read, 64), OVN_SLO_TIP_MAX_H (6: older tip export = stale), OVN_SLO_LINE_MAX (240 chars)
"""
import argparse
import calendar
import collections
import concurrent.futures
import datetime
import glob
import importlib.util
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

ROOT = os.environ.get("OVN_DIR") or os.path.expanduser("~/overnight-queue")
STATE = os.environ.get("OVN_NOTIFY_STATE") or os.path.join(ROOT, "state")
VERSION = 1
DISCONTINUED = ("social-media-manager", "task-manager-platform", "shrike-labs-website")
SEV_RANK = {"crit": 2, "warn": 1}
WEIGHT = {"prod_health": 100, "gate_stall": 90, "false_credit": 80, "deploy_lag": 75, "evidence": 70, "drift": 65, "backup": 60,
          "promote_lag": 55, "runway": 50, "landing_rate": 45, "bad_share": 40}
FIX = {   # slo -> docs/FLEET_RUNBOOK.md anchor
    "prod_health": "prod-health", "gate_stall": "gate-stall", "false_credit": "false-credit", "deploy_lag": "deploy-lag", "evidence": "staging-evidence",
    "drift": "box-drift", "backup": "backup", "promote_lag": "promote-lag", "runway": "supply-runway", "landing_rate": "landing-rate", "bad_share": "bad-share"}
STATIC_EVIDENCE_HINTS = {
    "deploy_export": "Mac qa-staging-export not running: launchctl kickstart gui/$(id -u)/com.shrike.qa-staging-export (log ~/.qa_staging_export.log; needs the Railway CLI login)",
    "e2e_mac": "Mac qa-staging-e2e not running: launchctl kickstart gui/$(id -u)/com.shrike.qa-staging-e2e (log ~/.qa_staging_e2e.log; needs the Railway CLI login)",
    "e2e_box": "box staging_e2e_run.sh produced no fresh result: check logs/staging_e2e.log and the cron line for qa/staging_e2e_run.sh"}


# ------------------------------------------------------------------------------------------------------------------ config
def _f(name, default):
    try:
        return float(os.environ.get(name, default))
    except ValueError:
        return float(default)


def cfg():
    """Every threshold, read from the environment at call time (tests and the mutant runner set them per case)."""
    return {
        "landed_min": _f("OVN_SLO_LANDED_MIN", 1), "min_attempts": _f("OVN_SLO_MIN_ATTEMPTS", 5),
        "bad_warn": _f("OVN_SLO_BAD_WARN", 0.50), "bad_crit": _f("OVN_SLO_BAD_CRIT", 0.75),
        "fc_warn": _f("OVN_SLO_FC_WARN", 0.05), "fc_crit": _f("OVN_SLO_FC_CRIT", 0.15), "fc_min": _f("OVN_SLO_FC_MIN", 3), "fc_days": _f("OVN_SLO_FC_DAYS", 7),
        "gate_warn": _f("OVN_SLO_GATE_WARN_H", 3), "gate_crit": _f("OVN_SLO_GATE_CRIT_H", 6),
        "deploy_warn": _f("OVN_SLO_DEPLOY_LAG_H", 6), "deploy_crit": _f("OVN_SLO_DEPLOY_LAG_CRIT_H", 24), "tip_max": _f("OVN_SLO_TIP_MAX_H", 6),
        "promote_warn": _f("OVN_SLO_PROMOTE_LAG_H", 36), "promote_crit": _f("OVN_SLO_PROMOTE_LAG_CRIT_H", 72),
        "bk_hourly_warn": _f("OVN_SLO_BACKUP_HOURLY_H", 3), "bk_hourly_crit": _f("OVN_SLO_BACKUP_HOURLY_CRIT_H", 6),
        "bk_daily_warn": _f("OVN_SLO_BACKUP_DAILY_H", 26), "bk_daily_crit": _f("OVN_SLO_BACKUP_DAILY_CRIT_H", 50),
        "ev_deploy_s": _f("QA_STAGING_MAX_AGE_S", 1800), "ev_e2e_s": _f("OVN_SLO_E2E_MAX_S", 12 * 3600), "ev_crit_x": _f("OVN_SLO_EVIDENCE_CRIT_X", 4),
        "drift_crit": _f("OVN_SLO_DRIFT_CRIT", 5), "drift_stale_h": _f("OVN_SLO_DRIFT_STALE_H", 26),
        "notify_h": _f("OVN_SLO_NOTIFY_H", 1), "grace_s": _f("OVN_SLO_CLEAR_GRACE_S", 2400), "line_max": int(_f("OVN_SLO_LINE_MAX", 240)),
        "scan_mb": _f("OVN_SLO_SCAN_MB", 64), "http_timeout": _f("OVN_SLO_HTTP_TIMEOUT", 8),
    }


def mode(state=None):
    """off | shadow | on. env OVN_FLEET_SLO wins, then state/fleet_slo.mode; anything unrecognised is shadow (never silently `on`)."""
    v = os.environ.get("OVN_FLEET_SLO")
    if not v:
        try:
            with open(os.path.join(state or STATE, "fleet_slo.mode")) as fh:
                v = (fh.read().split() or [""])[0]
        except OSError:
            v = ""
    v = (v or "shadow").strip().lower()
    return v if v in ("off", "shadow", "on") else "shadow"


# ------------------------------------------------------------------------------------------------------------------ small io
def _read(path, limit=None):
    try:
        with open(path, errors="replace") as fh:
            return fh.read() if limit is None else fh.read(limit)
    except OSError:
        return ""


def _tail(path, nbytes=262144):
    try:
        size = os.path.getsize(path)
        with open(path, "rb") as fh:
            fh.seek(max(0, size - nbytes))
            return fh.read().decode("utf-8", "replace")
    except OSError:
        return ""


def _json(path):
    try:
        with open(path) as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return None


def _atomic(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = "%s.tmp.%d" % (path, os.getpid())
    with open(tmp, "w") as fh:
        fh.write(text)
    os.replace(tmp, path)


def _utc(s):
    """'2026-10-18T19:13:37Z' (or with .123Z / +00:00 or a space) -> epoch, None when unparseable."""
    try:
        s = str(s).strip().replace(" ", "T")
        m = re.match(r"(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d)(?:\.\d+)?(Z|[+-]\d\d:?\d\d)?$", s)
        if not m:
            return None
        t = float(calendar.timegm(time.strptime(m.group(1), "%Y-%m-%dT%H:%M:%S")))
        z = m.group(2)
        if z and z != "Z":
            sign = 1 if z[0] == "+" else -1
            hh, mm = int(z[1:3]), int(z[-2:])
            t -= sign * (hh * 3600 + mm * 60)
        return t
    except (ValueError, OverflowError):
        return None


def _local(s):
    """'2026-10-18 19:30:21' in the box's local time -> epoch, None when unparseable."""
    try:
        return float(time.mktime(time.strptime(s, "%Y-%m-%d %H:%M:%S")))
    except (ValueError, OverflowError):
        return None


def _h(secs):
    return secs / 3600.0


def _fmt_h(h):
    return "%.1fh" % h if h < 100 else "%dh" % round(h)


# ------------------------------------------------------------------------------------------------------------------ breaches
def breach(slo, scope, sev, value, threshold, hint, since_ts=None, unit=""):
    return {"key": "%s:%s" % (slo, scope), "slo": slo, "scope": scope, "severity": sev, "value": value, "threshold": threshold, "unit": unit,
            "hint": hint, "fix": "docs/FLEET_RUNBOOK.md#" + FIX[slo], "since_ts": since_ts}


def grade(value, warn, crit, higher_is_worse=True):
    """'crit' | 'warn' | None. >= comparisons: a value exactly at the threshold is a breach (a threshold names the first bad value)."""
    if higher_is_worse:
        return "crit" if value >= crit else ("warn" if value >= warn else None)
    return "crit" if value <= crit else ("warn" if value <= warn else None)


# ------------------------------------------------------------------------------------------------------------------ outcomes (landing rate / bad share)
def read_outcomes(state, since, scan_mb):
    rows = []
    path = os.path.join(state, "outcomes.jsonl")
    try:
        size = os.path.getsize(path)
        with open(path, "rb") as fh:
            fh.seek(max(0, size - int(scan_mb * 1_000_000)))
            for line in fh:
                if b'"class":"skipped"' in line:
                    continue
                try:
                    d = json.loads(line)
                except ValueError:
                    continue
                t = _utc(d.get("ts")) if isinstance(d, dict) else None
                if t is not None and t >= since:
                    d["_t"] = t
                    rows.append(d)
    except OSError:
        pass
    return rows


def _buckets():
    try:
        import ovn_outcome_buckets as ob
        return ob
    except Exception:  # noqa: BLE001
        return None


def lane_outcomes(rows, repo):
    ob = _buckets()
    att = [r for r in rows if r.get("repo") == repo and r.get("class") not in ("skipped", "landed-late", "credit-only") and not str(r.get("status", "")).startswith("skip")]
    landed = sum(1 for r in att if r.get("class") == "landed")
    bad_rows = [r for r in att if (ob.bucket_from_outcome_row(r) == "bad" if ob else r.get("severity") == "bad") and r.get("class") != "landed"]
    return {"attempts": len(att), "landed": landed, "reverted": sum(1 for r in att if r.get("class") == "reverted"), "noop": sum(1 for r in att if r.get("class") == "noop"),
            "bad": len(bad_rows), "bad_share": (len(bad_rows) / float(len(att))) if att else None, "_bad_rows": bad_rows}


def failure_hint(repo, bad_rows, state, now):
    """Root-cause text from the existing classifiers: the fail_reason / status buckets of the lane's own bad rows (run_overnight.sh's classifier) and the top failure cluster
    (ovn_failure_triage, state/failure_clusters.json) seen in the last 24 h."""
    parts = []
    c = collections.Counter((r.get("fail_reason") or re.sub(r"[^a-z0-9()\-]+", "-", str(r.get("status", "")).lower())[:40] or "unknown") for r in bad_rows)
    if c:
        parts.append("top cause %s" % ", ".join("%s x%d" % kv for kv in c.most_common(2)))
    clusters = _json(os.path.join(state, "failure_clusters.json")) or {}
    best = None
    for k, v in clusters.items():
        if not isinstance(v, dict) or not k.startswith(repo + "::"):
            continue
        ls = _utc(v.get("last_seen"))
        if ls is not None and now - ls <= 24 * 3600 and (best is None or v.get("count", 0) > best[1]):
            best = (k.split("::", 1)[1], v.get("count", 0))
    if best:
        parts.append("cluster '%s' x%d" % (best[0][:60], best[1]))
    return "; ".join(parts)


# ------------------------------------------------------------------------------------------------------------------ audit ledger (false credits)
LEDGER = "landing_audits.jsonl"
FALSE_V = {"false-credit", "false_credit", "false", "bad"}
OK_V = {"ok", "true-credit", "true_credit", "good", "true"}


def append_audit(state, repo, ref, verdict, audit="", gate="", note="", now=None):
    v = verdict.strip().lower()
    if v not in FALSE_V | OK_V:
        raise ValueError("verdict must be false-credit or ok (got %r)" % verdict)
    t = float(now if now is not None else time.time())
    row = {"ts": t, "iso": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(t)), "repo": repo, "ref": ref, "verdict": "false-credit" if v in FALSE_V else "ok",
           "audit": audit, "gate": gate, "note": note}
    os.makedirs(state, exist_ok=True)
    with open(os.path.join(state, LEDGER), "a") as fh:
        fh.write(json.dumps(row, sort_keys=True) + "\n")
    return row


def read_audits(state, since):
    """Last verdict per (repo, ref) within the window."""
    last = {}
    for line in _read(os.path.join(state, LEDGER)).splitlines():
        try:
            d = json.loads(line)
            t = float(d.get("ts")) if d.get("ts") is not None else _utc(d.get("iso"))
        except (ValueError, TypeError):
            continue
        if t is None or t < since or not d.get("repo"):
            continue
        v = str(d.get("verdict", "")).lower()
        if v not in FALSE_V | OK_V:
            continue
        d["_t"], d["_false"] = t, v in FALSE_V
        last[(d["repo"], str(d.get("ref", "")))] = d
    return list(last.values())


def false_credit(audits, c):
    per = collections.defaultdict(lambda: [0, 0])
    for a in audits:
        per[a["repo"]][0] += 1
        per[a["repo"]][1] += 1 if a["_false"] else 0
    out, breaches = {}, []
    n_all, f_all = sum(v[0] for v in per.values()), sum(v[1] for v in per.values())
    repo_breached = False
    for repo, (n, f) in sorted(per.items()):
        rate = f / float(n)
        out[repo] = {"audited": n, "false": f, "rate": round(rate, 4)}
        sev = grade(rate, c["fc_warn"], c["fc_crit"]) if n >= c["fc_min"] else None
        if sev:
            repo_breached = True
            breaches.append(breach("false_credit", repo, sev, round(rate, 3), c["fc_warn"], _fc_hint([a for a in audits if a["repo"] == repo], f, n), unit="rate"))
    out["_fleet"] = {"audited": n_all, "false": f_all, "rate": round(f_all / float(n_all), 4) if n_all else None}
    if n_all and not repo_breached:
        sev = grade(f_all / float(n_all), c["fc_warn"], c["fc_crit"]) if n_all >= c["fc_min"] else None
        if sev:
            breaches.append(breach("false_credit", "fleet", sev, round(f_all / float(n_all), 3), c["fc_warn"], _fc_hint(audits, f_all, n_all), unit="rate"))
    return out, breaches


def _fc_hint(audits, f, n):
    fl = [a for a in audits if a["_false"]]
    gates = collections.Counter((a.get("gate") or "?") for a in fl)
    g = ", ".join("%s x%d" % kv for kv in gates.most_common(2))
    return "%d of %d audited landings were false credits (gate that should have caught: %s); run the evidence replay and flip that gate shadow->enforce, see runbook" % (f, n, g or "?")


# ------------------------------------------------------------------------------------------------------------------ gates
def read_streaks(state, now):
    out = []
    for kind, d in (("gate", "hygiene_gate_streak"), ("merge", "hygiene_merge_streak")):
        for p in sorted(glob.glob(os.path.join(state, d, "*"))):
            name = os.path.basename(p)
            if name.endswith(".tmp") or ".tmp." in name or "__" not in name:
                continue
            txt = _read(p, 4096)
            m = re.match(r"\s*(\d+)", txt)
            f = re.search(r"\d{4}-\d\d-\d\d \d\d:\d\d:\d\d", txt)
            first = _local(f.group(0)) if f else None
            if first is None:
                try:
                    first = os.path.getmtime(p)
                except OSError:
                    continue
            repo, branch = name.split("__", 1)
            out.append({"kind": kind, "repo": repo, "branch": branch, "count": int(m.group(1)) if m else 1, "first_ts": first, "stall_h": max(0.0, _h(now - first))})
    return out


def alert_detail(state, repo, tag):
    """Newest alerts.log line for this lane's streak alert: the 'failing: ...' part is the root cause the gate already computed."""
    best = ""
    for line in _tail(os.path.join(state, "alerts.log")).splitlines():
        if tag + ":" + repo in line:
            best = line
    if not best:
        return ""
    m = re.search(r"failing: (.*)$", best)
    return ("failing: " + m.group(1)[:140]) if m else re.sub(r"^.*? \| ", "", best)[:160]


# ------------------------------------------------------------------------------------------------------------------ supply
def supply(now, root, state):
    try:
        import ovn_supply_report as sr
        return sr.fresh_report(now, state) or sr.collect(now=now, root=root, state=state)
    except Exception:  # noqa: BLE001 - the SLO view must never die on a feeder
        return None


# ------------------------------------------------------------------------------------------------------------------ deploy / promote lag
def _git(args, cwd, timeout=20):
    try:
        r = subprocess.run(["git"] + args, cwd=cwd, capture_output=True, text=True, timeout=timeout, env=dict(os.environ, GIT_TERMINAL_PROMPT="0", LC_ALL="C"))
        return r.returncode, r.stdout
    except (OSError, subprocess.SubprocessError):
        return 127, ""


def export_tip(git_dir, ref="origin/claude/feature", path="scripts/overnight-queue", limit=300, fetch=False, now=None, all_limit=2000):
    """-> the claude_feature_tip.json dict for a checkout: newest-first [sha, committer epoch] of commits on `ref` touching `path`. Run ON THE MAC (the box has no checkout of this repo)."""
    if fetch:
        _git(["fetch", "-q", "origin", ref.split("/", 1)[-1]], git_dir, 90)
    args = ["log", "--format=%H %ct", "-n", str(int(limit)), ref]
    if path:
        args += ["--", path]
    rc, out = _git(args, git_dir, 60)
    commits = []
    for line in out.splitlines():
        p = line.split()
        if len(p) == 2 and p[1].isdigit():
            commits.append([p[0], int(p[1])])
    rc2, head = _git(["rev-parse", ref], git_dir)
    # every commit on the ref (not just the path-touching ones): a deployed sha that does not touch the queue path (a docs/other-subtree HEAD) is still placeable on the branch
    all_commits = commits
    if path:
        rc3, out3 = _git(["log", "--format=%H %ct", "-n", str(int(all_limit)), ref], git_dir, 60)
        parsed = []
        for line in out3.splitlines():
            p = line.split()
            if len(p) == 2 and p[1].isdigit():
                parsed.append([p[0], int(p[1])])
        all_commits = parsed if rc3 == 0 else []
    return {"ref": ref, "path": path, "fetched_at": float(now if now is not None else time.time()), "head": head.strip() if rc2 == 0 else None, "commits": commits, "all_commits": all_commits, "ok": rc == 0 and bool(commits)}


def read_deployed(state):
    txt = _read(os.path.join(state, "deployed_sha")).strip()
    if not txt:
        return None
    try:
        d = json.loads(txt)
        if isinstance(d, dict) and d.get("sha"):
            return {"sha": str(d["sha"]).strip(), "ts": d.get("ts")}
    except ValueError:
        pass
    p = txt.split()
    return {"sha": p[0], "ts": float(p[1]) if len(p) > 1 and p[1].replace(".", "", 1).isdigit() else None} if re.match(r"^[0-9a-f]{7,40}$", p[0]) else None


def deploy_lag(state, now, c):
    """-> (record, [breaches])"""
    rec = {"state": "nodata", "deployed": None, "tip": None, "behind": None, "lag_h": None, "detail": ""}
    dep = read_deployed(state)
    gd = os.environ.get("OVN_SLO_GIT_DIR")
    tip = export_tip(gd, now=now) if gd else _json(os.path.join(state, "claude_feature_tip.json"))
    if dep is None:
        rec["detail"] = "state/deployed_sha missing: the deploy step does not record what it deployed (run: ovn_fleet_slo.py mark-deployed --sha SHA)"
        return rec, []
    rec["deployed"] = dep["sha"][:12]
    if not tip or not tip.get("commits"):
        rec["detail"] = "state/claude_feature_tip.json missing/empty: the Mac tip export is not running"
        return rec, []
    age_h = _h(now - float(tip.get("fetched_at") or 0))
    rec["tip"] = tip["commits"][0][0][:12]
    rec["tip_age_h"] = round(age_h, 2)
    if age_h > c["tip_max"]:
        rec["state"], rec["detail"] = "stale-tip", "tip export is %s old (> %gh): Mac job not running, lag cannot be trusted" % (_fmt_h(age_h), c["tip_max"])
        return rec, [breach("deploy_lag", "box", "warn", round(age_h, 1), c["tip_max"], rec["detail"], since_ts=float(tip.get("fetched_at") or 0) + c["tip_max"] * 3600, unit="h tip age")]
    shas = [x[0] for x in tip["commits"]]

    def same(a, b):
        return bool(a and b) and (a.startswith(b) or b.startswith(a))
    idx = next((i for i, s in enumerate(shas) if same(s, dep["sha"])), None)
    if idx == 0 or same(tip.get("head"), dep["sha"]):
        rec.update(state="ok", behind=0, lag_h=0.0, detail="box runs the claude/feature tip")
        return rec, []
    allc = [x for x in (tip.get("all_commits") or []) if isinstance(x, list) and len(x) == 2]
    if idx is None and allc:
        # the deployed sha may be a branch commit that does not touch scripts/overnight-queue: place it on the whole branch, then the undeployed commits are the queue-touching ones newer than it
        ai = next((i for i, x in enumerate(allc) if same(x[0], dep["sha"])), None)
        if ai is not None:
            pos = {x[0]: i for i, x in enumerate(allc)}
            newer = [x for x in tip["commits"] if (pos[x[0]] < ai if x[0] in pos else x[1] > allc[ai][1])]
            if not newer:
                rec.update(state="ok", behind=0, lag_h=0.0, detail="box %s is newer than the last queue-touching commit (%s)" % (dep["sha"][:10], shas[0][:10]))
                return rec, []
            return _behind(rec, dep, shas, len(newer), newer[-1], now, c)   # tip["commits"] is newest-first, so newer[-1] is the oldest undeployed
    if idx is None:
        # not placeable: it is NEWER than the export (the export is up to tip_max old, so a box that just deployed the real newest commit lands here), a rollback to an old sha, or an
        # unrelated tree. That is "unknown", never a guessed crit. Only evidence that the record itself is old (the deploy was recorded before the oldest commit we can see) is a warn.
        oldest = min(x[1] for x in (allc or tip["commits"]))
        fa = float(tip.get("fetched_at") or 0)
        ts = dep.get("ts")
        rec.update(state="unknown-deployed", behind=None, lag_h=None, detail="box sha %s is not among the last %d branch commit(s) the Mac exported (newer than the export, or a rollback): lag cannot be judged" % (dep["sha"][:10], len(allc or shas)))
        if ts is not None and float(ts) < oldest and fa - float(ts) > c["deploy_warn"] * 3600:
            rec["detail"] += "; its deploy record (%s ago) predates the whole window, so it is old" % _fmt_h(_h(now - float(ts)))
            return rec, [breach("deploy_lag", "box", "warn", round(_h(now - float(ts)), 1), c["deploy_warn"], rec["detail"] + "; run the safe deploy", since_ts=float(ts) + c["deploy_warn"] * 3600, unit="h")]
        return rec, []
    first_missing = tip["commits"][idx - 1]
    return _behind(rec, dep, shas, idx, first_missing, now, c)


def _behind(rec, dep, shas, n, first_missing, now, c):
    lag = max(0.0, _h(now - first_missing[1]))
    rec.update(state="behind", behind=n, lag_h=round(lag, 1), detail="box %s is %d commit(s) behind tip %s; oldest undeployed is %s old" % (dep["sha"][:10], n, shas[0][:10], _fmt_h(lag)))
    sev = grade(lag, c["deploy_warn"], c["deploy_crit"])
    if not sev:
        rec["state"] = "ok"
        return rec, []
    return rec, [breach("deploy_lag", "box", sev, round(lag, 1), c["deploy_warn"], rec["detail"] + "; run the safe deploy", since_ts=first_missing[1] + c["deploy_warn"] * 3600, unit="h")]


def promote_lag(root, state, now, c):
    repos = (os.environ.get("OVN_SLO_PROMOTE_REPOS") or "billwatch iptv_apps").split()
    hold = set((os.environ.get("OVN_SLO_PROMOTE_HOLD") or "").split()) | set(_read(os.path.join(state, "slo_promote_hold.txt")).split())
    out, br = {}, []
    notes, cur = {}, None   # logs/daily_promote.log is sectioned: "===== <repo> =====" then lines that do not repeat the repo name
    # A "note" is a line that says WHY a promote did not happen. Benign lines of a SUCCESSFUL run also contain the trigger words ("0 develop merge(s) held back", "smoke test SKIPPED" when no
    # staging URL is configured, "UNVERIFIED (shadow)") and must not be quoted as a cause (2026-10-18 review). A repo's newer section replaces its older notes, and a PROMOTED line clears them.
    BLOCKER = re.compile(r"BLOCK|REFUS|FAIL|\bSKIP\b|[1-9]\d* develop merge\(s\) held back|\bstale\b|\bred\b|\bheld\b", re.I)
    BENIGN = re.compile(r"post-promote check started|FAILED\s*=>|\b0 develop merge\(s\) held back|smoke test SKIPPED|UNVERIFIED \(shadow\)|\bPROMOTED\b", re.I)
    for l in _read(os.path.join(root, "logs", "daily_promote.log"))[-40000:].splitlines():
        m = re.match(r"^=+\s*(\S+)\s*=+\s*$", l.strip())
        if m and m.group(1).strip("=") and re.search(r"[A-Za-z]", m.group(1)):
            cur = m.group(1)
            notes.pop(cur, None)
            continue
        if cur and re.search(r"\bPROMOTED\b", l):
            notes.pop(cur, None)
            continue
        if BLOCKER.search(l) and not BENIGN.search(l):
            for k in ([cur] if cur else []) + [x for x in repos if x in l]:
                notes[k] = l.strip()
    for r in repos:
        rd = os.path.join(root, "repos", r)
        rec = {"state": "nodata", "lag_h": None, "ahead": None, "held": r in hold}
        out[r] = rec
        if not os.path.isdir(rd):
            rec["detail"] = "no checkout at repos/%s" % r
            continue
        rc, ahead = _git(["rev-list", "--count", "origin/main..origin/develop"], rd)
        if rc != 0:
            rec["detail"] = "git: origin/main..origin/develop not resolvable"
            continue
        rec["ahead"] = int(ahead.strip() or 0)
        if rec["ahead"] == 0 or _git(["diff", "--quiet", "origin/main", "origin/develop"], rd)[0] == 0:
            rec.update(state="ok", lag_h=0.0, detail="develop == main (%d commit(s) but tree identical)" % rec["ahead"] if rec["ahead"] else "develop == main")
            continue
        rc, lines = _git(["log", "--format=%ct", "origin/main..origin/develop"], rd)
        cts = [int(x) for x in lines.split() if x.isdigit()]
        if not cts:
            continue
        oldest = min(cts)
        lag = _h(now - oldest)
        rec["lag_h"] = round(lag, 1)
        sev = grade(lag, c["promote_warn"], c["promote_crit"])
        why = [notes[r]] if r in notes else []
        hint = "develop is %d commit(s) ahead of main, oldest %s old; last promote note: %s" % (rec["ahead"], _fmt_h(lag), (why[-1][:140] if why else "none (no blocking line in the latest logs/daily_promote.log run)"))
        rec["detail"] = hint
        if not sev:
            rec["state"] = "ok"
        elif r in hold:
            rec["state"] = "held"
        else:
            rec["state"] = sev
            br.append(breach("promote_lag", r, sev, round(lag, 1), c["promote_warn"], hint + "; see runbook (promote)", since_ts=oldest + c["promote_warn"] * 3600, unit="h"))
    return out, br


# ------------------------------------------------------------------------------------------------------------------ backups / prod / evidence / drift
def backups(c, now, root=None):
    d = os.environ.get("OVN_SLO_BACKUP_DIR") or "/run/media/mhintermeister/secondary_drive1/box-backups"
    out, br = {}, []
    if d == "off":
        return {"state": "disabled"}, []
    if not os.path.isdir(d):
        rec = {"state": "crit", "detail": "backup dir %s missing (drive not mounted?)" % d}
        return {"dir": d, "hourly": rec, "daily": rec}, [breach("backup", "drive", "crit", None, None, rec["detail"], unit="")]
    for mode_, warn, crit in (("hourly", c["bk_hourly_warn"], c["bk_hourly_crit"]), ("daily", c["bk_daily_warn"], c["bk_daily_crit"])):
        line = ""
        for l in _read(os.path.join(d, "heartbeat-%s.log" % mode_)).splitlines():
            if l.strip():
                line = l.strip()
        ts = None
        m = re.match(r"^(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d[+-]\d{4})\s", line)
        if m:
            try:
                ts = datetime.datetime.strptime(m.group(1), "%Y-%m-%dT%H:%M:%S%z").timestamp()
            except ValueError:
                ts = None
        if ts is None:
            rec = {"state": "crit", "age_h": None, "detail": "heartbeat-%s.log missing or unparseable" % mode_}
            br.append(breach("backup", mode_, "crit", None, warn, rec["detail"] + backup_alert(c, root), unit=""))
        else:
            age = _h(now - ts)
            sev = grade(age, warn, crit)
            rec = {"state": sev or "ok", "age_h": round(age, 2), "last": m.group(1), "detail": line[:120]}
            if sev:
                br.append(breach("backup", mode_, sev, round(age, 1), warn, "newest %s heartbeat is %s old (limit %gh)%s" % (mode_, _fmt_h(age), warn, backup_alert(c, root)),
                                 since_ts=ts + warn * 3600, unit="h"))
        out[mode_] = rec
    out["dir"] = d
    return out, br


def backup_alert(c, root):
    line = ""
    for l in _tail(os.path.join(root or ROOT, "logs", "box_backup_alert.log"), 8192).splitlines():
        if l.strip():
            line = l.strip()
    return "; last backup alert: " + line[:130] if line else ""


def load_prod_urls(root, state):
    for p in (os.environ.get("OVN_SLO_PROD_URLS"), os.path.join(state, "slo_prod_urls.txt"), os.path.join(root, "ops", "slo_prod_urls.txt")):
        if p and os.path.isfile(p):
            out = []
            for l in _read(p).splitlines():
                l = l.strip()
                if not l or l.startswith("#"):
                    continue
                parts = [x.strip() for x in l.split("|")]
                if len(parts) >= 2 and parts[1].startswith("http"):
                    out.append((parts[0], parts[1], [int(x) for x in parts[2].split(",") if x.strip().isdigit()] if len(parts) > 2 else None))
            return out, p
    return [], None


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *a, **k):
        return None


def http_get(url, timeout):
    """-> (status or None, error text, ms). Redirects are NOT followed: 307 is a literal answer (the standards doc counts 200 and 307 as working)."""
    t0 = time.time()
    op = urllib.request.build_opener(_NoRedirect)
    try:
        with op.open(urllib.request.Request(url, headers={"User-Agent": "ovn-fleet-slo/1"}), timeout=timeout) as r:
            return r.status, "", int((time.time() - t0) * 1000)
    except urllib.error.HTTPError as e:
        return e.code, "", int((time.time() - t0) * 1000)
    except Exception as e:  # noqa: BLE001
        return None, type(e).__name__ + ": " + str(e)[:80], int((time.time() - t0) * 1000)


def prod_health(root, state, c, net=True):
    urls, src = load_prod_urls(root, state)
    if not urls:
        return {"state": "nodata", "source": src, "checks": []}, []
    if not net or os.environ.get("OVN_SLO_PROD_CHECK") == "off":
        return {"state": "disabled", "source": src, "checks": []}, []
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as ex:
        res = list(ex.map(lambda u: http_get(u[1], c["http_timeout"]), urls))
    checks, br = [], []
    for (name, url, codes), (code, err, ms) in zip(urls, res):
        ok = code is not None and ((code in codes) if codes else 200 <= code < 400)
        checks.append({"name": name, "url": url, "code": code, "ok": ok, "ms": ms, "error": err})
        if not ok:
            br.append(breach("prod_health", name, "crit", code if code is not None else 0, 200, "%s answered %s (%s); open the runtime log (Railway/Vercel/Fly) before anything else" % (url, code if code is not None else "no response", err or "HTTP"), unit="http"))
    return {"state": "crit" if br else "ok", "source": src, "checks": checks}, br


def _evidence_meta(root):
    """The hint texts of qa/evidence_freshness_check.py when it can be loaded (single source of truth), else the static copies."""
    p = os.path.join(root, "qa", "evidence_freshness_check.py")
    try:
        sys.path.insert(0, os.path.dirname(p))
        spec = importlib.util.spec_from_file_location("_slo_evidence", p)
        m = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(m)
        h = getattr(m, "HINTS", None)
        if isinstance(h, dict) and h:
            return dict(STATIC_EVIDENCE_HINTS, **h)
    except Exception:  # noqa: BLE001
        pass
    finally:
        if sys.path and sys.path[0] == os.path.dirname(p):
            sys.path.pop(0)
    return STATIC_EVIDENCE_HINTS


def evidence(root, state, now, c):
    hints = _evidence_meta(root)
    src = {}
    fetched = []
    for p in glob.glob(os.path.join(state, "staging_deploys", "*.json")):
        d = _json(p)
        if isinstance(d, dict) and d.get("fetched_at") is not None:
            try:
                fetched.append(float(d["fetched_at"]))
            except (TypeError, ValueError):
                pass
    src["deploy_export"] = (max(fetched) if fetched else None, c["ev_deploy_s"])
    on = os.environ.get("OVN_QA_STAGING_E2E", "on") != "off"
    for k, fn in (("e2e_mac", "qa_staging_e2e.json"), ("e2e_box", "staging_e2e_box.json")):
        if on:
            d = _json(os.path.join(state, fn))
            src[k] = (_utc(d.get("ts")) if isinstance(d, dict) else None, c["ev_e2e_s"])
    out, br = {}, []
    for k, (ts, lim) in src.items():
        if ts is None:
            out[k] = {"state": "crit", "age_s": None, "limit_s": lim}
            br.append(breach("evidence", k, "crit", None, lim, "no usable timestamp (file missing/unreadable); " + hints.get(k, ""), unit="s"))
            continue
        age = max(0.0, now - ts)
        sev = grade(age, lim, lim * c["ev_crit_x"])
        out[k] = {"state": sev or "ok", "age_s": int(age), "limit_s": lim}
        if sev:
            br.append(breach("evidence", k, sev, int(age), lim, "%s is %s old (max %s): %s" % (k, _fmt_h(_h(age)), _fmt_h(_h(lim)), hints.get(k, "")), since_ts=ts + lim, unit="s"))
    return out, br


def drift(state, now, c):
    p = os.path.join(state, "box_verify.json")
    d = _json(p)
    if d is None:
        return {"state": "nodata", "count": None, "detail": "state/box_verify.json absent (box_verify not run yet)"}, []
    items = []
    real = isinstance(d, dict) and isinstance(d.get("items"), list)       # ops/box_verify.py: {ts, mode, ok, counts{drift,crit,human,...}, items[{key,sev,class,msg,fix}], accepted[]}
    if isinstance(d, dict) and d.get("mode") == "off":
        return {"state": "nodata", "count": None, "detail": "box_verify is switched off (OVN_BOX_VERIFY=off)"}, []
    if real:
        items = d["items"]
        cn = (d.get("counts") or {}).get("drift")
        if isinstance(cn, int) and not isinstance(cn, bool) and cn > len(items):
            items = items + [None] * (cn - len(items))
    elif isinstance(d, dict):
        for k in ("drift", "findings", "failed", "issues", "failures", "problems"):
            v = d.get(k)
            if isinstance(v, list):
                items = v
                break
            if isinstance(v, int) and not isinstance(v, bool):
                items = [None] * v
                break
        else:
            if isinstance(d.get("drift_count"), int):
                items = [None] * d["drift_count"]
            elif d.get("ok") is False:
                items = [None]
    elif isinstance(d, list):
        items = d
    n = len(items)
    real_items = sorted([x for x in items if isinstance(x, dict)], key=lambda x: (x.get("sev") != "crit", str(x.get("key") or x.get("name") or "")))
    names = [str(x.get("key") or x.get("name") or x.get("check") or x.get("id") or x)[:60] for x in real_items][:3] or [str(x)[:60] for x in items if x is not None][:3]
    first_fix = next((str(x.get("fix"))[:110] for x in real_items if x.get("fix")), "")
    human = sum(1 for x in real_items if x.get("class") == "human")
    any_crit = any(x.get("sev") == "crit" for x in real_items)
    rec = {"state": "ok", "count": n, "examples": names}
    br = []
    ts = None
    if isinstance(d, dict):
        ts = _utc(d.get("ts") or d.get("generated_at") or d.get("checked_at"))
        if ts is None and isinstance(d.get("ts"), (int, float)):
            ts = float(d["ts"])
    if ts is None:
        try:
            ts = os.path.getmtime(p)
        except OSError:
            ts = None
    if n:
        sev = "crit" if any_crit else grade(n, 1, c["drift_crit"])
        rec["state"] = sev
        br.append(breach("drift", "box", sev, n, 0, "%d drift finding(s) on the box%s%s%s; run `bash ops/box_verify.sh --human --no-record` and the runbook" % (
            n, (": " + ", ".join(names)) if names else "", (" (%d need a human)" % human) if human else "", ("; first fix: " + first_fix) if first_fix else ""), since_ts=ts, unit="findings"))
    if ts is not None and _h(now - ts) >= c["drift_stale_h"]:
        rec["stale_h"] = round(_h(now - ts), 1)
        br.append(breach("drift", "box_verify_stale", "warn", round(_h(now - ts), 1), c["drift_stale_h"], "box_verify has not run for %s (cron missing?)" % _fmt_h(_h(now - ts)), since_ts=ts + c["drift_stale_h"] * 3600, unit="h"))
        if rec["state"] == "ok":
            rec["state"] = "warn"
    return rec, br


# ------------------------------------------------------------------------------------------------------------------ tracker (first-seen)
def track(prev, breaches, now, grace_s):
    """Return (new tracker dict, breaches annotated with since/hours). A key stays in the tracker for `grace_s` after it was last seen, so one green run in between does not restart its clock."""
    out = {}
    for k, v in (prev or {}).items():
        if isinstance(v, dict) and now - float(v.get("last_seen", 0)) <= grace_s:
            out[k] = dict(v)
    for b in breaches:
        t = out.get(b["key"])
        first = float(t["first_seen"]) if t and "first_seen" in t else now
        if b.get("since_ts") is not None:
            first = min(first, float(b["since_ts"]))
        out[b["key"]] = {"first_seen": first, "last_seen": now}
        b["since"] = first
        b["hours"] = round(max(0.0, _h(now - first)), 2)
    return out, breaches


def rank(breaches):
    return sorted(breaches, key=lambda b: (-SEV_RANK[b["severity"]], -WEIGHT.get(b["slo"], 0), -(b.get("hours") or 0), b["scope"]))


# ------------------------------------------------------------------------------------------------------------------ collect
def collect(now=None, root=None, state=None, net=True, prev_tracker=None):
    """The whole report (pure function of the files, the clock and, when net, the prod URLs)."""
    now = float(now if now is not None else time.time())
    root, state = root or ROOT, state or STATE
    c = cfg()
    paused = os.path.exists(os.path.join(state, "PAUSED"))
    rows = read_outcomes(state, now - 24 * 3600, c["scan_mb"])
    sup = supply(now, root, state)
    sup_repos = (sup or {}).get("repos") or {}
    try:
        enabled = {os.path.basename(str(t.get("repo", ""))) for t in json.load(open(os.path.join(root, "tasks.json"))) if t.get("enabled") is True} or None
    except Exception:  # noqa: BLE001 - no tasks.json: every lane the supply report knows
        enabled = None
    lanes = sorted(set(sup_repos) | (enabled or set()))
    if not lanes:
        lanes = sorted({r.get("repo") for r in rows if r.get("repo")} - set(DISCONTINUED))
    if enabled:
        lanes = [l for l in lanes if l in enabled]
    lanes = [l for l in lanes if l not in DISCONTINUED]
    breaches, repos, nodata = [], {}, []
    for repo in lanes:
        lo = lane_outcomes(rows, repo)
        sr = sup_repos.get(repo) or {}
        pullable = sr.get("pullable")
        rec = {"landed_24h": lo["landed"], "attempts_24h": lo["attempts"], "reverted_24h": lo["reverted"], "noop_24h": lo["noop"], "bad_24h": lo["bad"],
               "bad_share": None if lo["bad_share"] is None else round(lo["bad_share"], 3), "pullable": pullable, "runway_h": sr.get("runway_h"), "starving": bool(sr.get("starving"))}
        hint = failure_hint(repo, lo["_bad_rows"], state, now)
        # landing rate
        if paused:
            rec["landing"] = "paused"
        elif pullable == 0 or rec["starving"]:
            rec["landing"] = "supply"           # the runway SLO owns this one; do not double-report
        elif lo["landed"] < c["landed_min"] and lo["attempts"] == 0 and pullable is None:
            rec["landing"] = "unknown"          # "lane not running" needs the supply report to say work is pullable; without it that is a guess (the runway nodata line says why)
        elif lo["landed"] < c["landed_min"]:
            sev = "crit" if lo["attempts"] >= c["min_attempts"] else "warn"
            rec["landing"] = sev
            breaches.append(breach("landing_rate", repo, sev, lo["landed"], c["landed_min"],
                                   ("%d attempts, 0 landed in 24h: " % lo["attempts"] + hint) if lo["attempts"] else "no attempt at all in 24h with %s item(s) pullable: lane not running (check the lane enable flag / queue state)" % pullable, unit="landed/24h"))
        else:
            rec["landing"] = "ok"
        # bad share
        if lo["bad_share"] is not None and lo["attempts"] >= c["min_attempts"]:
            sev = grade(lo["bad_share"], c["bad_warn"], c["bad_crit"])
            rec["bad_state"] = sev or "ok"
            if sev:
                breaches.append(breach("bad_share", repo, sev, round(lo["bad_share"], 3), c["bad_warn"], "%d of %d attempts thrown away (%d reverted, %d no-op); %s" % (lo["bad"], lo["attempts"], lo["reverted"], lo["noop"], hint or "no classifier evidence"), unit="share"))
        else:
            rec["bad_state"] = "small-sample"
        # runway
        if rec["starving"]:
            sev = "crit" if pullable == 0 else "warn"
            rec["runway_state"] = sev
            cl = sr.get("cause_class")
            why = "; ".join(x.get("text", "") for x in (sr.get("causes") or [])[:2]) or "no cause on record"
            breaches.append(breach("runway", repo, sev, sr.get("runway_h"), _f("OVN_SUPPLY_RUNWAY_H", 6), "%s%s (pullable %s, burn %s/d)" % (("[%s] " % cl) if cl else "", why, pullable, sr.get("burn_per_day")), unit="h"))
        else:
            rec["runway_state"] = "ok" if sr else "nodata"
        repos[repo] = rec
    if lanes and not any(r in sup_repos for r in lanes):
        nodata.append("runway: supply report unavailable for %d lane(s) (ovn_supply_report could not run)" % len(lanes))
    # false credits
    audits = read_audits(state, now - c["fc_days"] * 86400)
    fc, fcb = false_credit(audits, c)
    breaches += fcb
    for repo, v in fc.items():
        if repo in repos:
            repos[repo]["false_credit"] = v
    if not audits:
        nodata.append("false_credit: no audits recorded in the ledger (state/%s)" % LEDGER)
    # gates
    lane_rows = []
    for s in read_streaks(state, now):
        sev = grade(s["stall_h"], c["gate_warn"], c["gate_crit"])
        s["state"] = sev or "ok"
        lane_rows.append(s)
        if sev:
            tag = "hygiene-gate-streak" if s["kind"] == "gate" else "hygiene-merge-streak"
            detail = alert_detail(state, s["repo"], tag)
            breaches.append(breach("gate_stall", "%s/%s(%s)" % (s["repo"], s["branch"], s["kind"]), sev, round(s["stall_h"], 1), c["gate_warn"],
                                   "hygiene %s red for %d pass(es) since %s%s; nothing from this lane reaches develop" % (s["kind"], s["count"], time.strftime("%H:%M", time.localtime(s["first_ts"])), ("; " + detail) if detail else ""),
                                   since_ts=s["first_ts"] + c["gate_warn"] * 3600, unit="h"))
    # deploy / promote
    dl, dlb = deploy_lag(state, now, c)
    breaches += dlb
    if dl["state"] in ("nodata", "unknown-deployed"):
        nodata.append("deploy_lag: " + dl["detail"])
    pl, plb = promote_lag(root, state, now, c)
    breaches += plb
    bk, bkb = backups(c, now, root)
    breaches += bkb
    ph, phb = prod_health(root, state, c, net)
    breaches += phb
    if ph["state"] == "nodata":
        nodata.append("prod_health: no URL list (ops/slo_prod_urls.txt)")
    ev, evb = evidence(root, state, now, c)
    breaches += evb
    dr, drb = drift(state, now, c)
    breaches += drb
    if dr["state"] == "nodata":
        nodata.append("drift: " + dr["detail"])
    tracker, breaches = track(prev_tracker, breaches, now, c["grace_s"])
    breaches = rank(breaches)
    rep = {"version": VERSION, "ts": now, "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(now)), "mode": mode(state), "paused": paused,
           "thresholds": {k: v for k, v in c.items()}, "repos": repos, "false_credit": fc, "lanes": lane_rows,
           "deploy": {"box": dl, "promote": pl}, "backup": bk, "prod": ph, "evidence": ev, "drift": dr, "breaches": breaches, "nodata": nodata,
           "summary": {"crit": sum(1 for b in breaches if b["severity"] == "crit"), "warn": sum(1 for b in breaches if b["severity"] == "warn"), "nodata": len(nodata)}}
    rep["summary"]["status"] = "crit" if rep["summary"]["crit"] else ("warn" if rep["summary"]["warn"] else "ok")
    rep["notify_line"] = notify_line(rep, c)
    rep["_tracker"] = tracker
    return rep


# ------------------------------------------------------------------------------------------------------------------ hourly line
def notify_line(rep, c=None):
    """ONE concise line, or None: only breaches that have lasted MORE than notify_h hours are mentioned."""
    c = c or cfg()
    long_ = [b for b in rep["breaches"] if (b.get("hours") or 0) > c["notify_h"]]
    if not long_:
        return None
    top = long_[0]
    val = "" if top["value"] is None else " %s%s" % (top["value"], ("" if not top["unit"] or top["unit"] in ("rate", "share", "http") else top["unit"].split()[0]))
    line = "SLO breach >%gh: %d (%d crit) - %s %s%s (%s): %s" % (c["notify_h"], len(long_), sum(1 for b in long_ if b["severity"] == "crit"), top["slo"], top["scope"], val, _fmt_h(top["hours"]), top["hint"])
    if len(long_) > 1:
        line += " [+%d more]" % (len(long_) - 1)
    line = re.sub(r"\s+", " ", line)
    mx = c["line_max"]
    tail = " -> www/fleet_slo.md"
    if len(line) + len(tail) > mx:
        line = line[:max(0, mx - len(tail) - 3)].rstrip() + "..."
    return line + tail


def update_lines(state, now=None):
    """What ovn_notify.py update adds: [] unless mode is `on`. One line for a breach older than the notify window, one line when the summary itself went stale or is missing."""
    try:
        if mode(state) != "on":
            return []
        now = float(now if now is not None else time.time())
        d = _json(os.path.join(state, "fleet_slo.json"))
        if not isinstance(d, dict):
            return ["SLO summary missing: fleet_slo cron is not producing state/fleet_slo.json (see docs/FLEET_RUNBOOK.md#slo-job)"]
        age = _h(now - float(d.get("ts", 0)))
        if age > _f("OVN_SLO_STALE_H", 3):
            return ["SLO summary stale (%s old): fleet_slo cron stopped (see docs/FLEET_RUNBOOK.md#slo-job)" % _fmt_h(age)]
        return [d["notify_line"]] if d.get("notify_line") else []
    except Exception:  # noqa: BLE001 - the hourly update must never break on this
        return []


# ------------------------------------------------------------------------------------------------------------------ markdown
def _cell(v):
    return str(v).replace("|", "/").replace("\n", " ")


def render_md(rep):
    L = []
    s = rep["summary"]
    L.append("# Fleet SLO summary")
    L.append("")
    L.append("Generated %s UTC - mode **%s**%s - status **%s** (%d crit, %d warn, %d with no data)" % (rep["generated_at"], rep["mode"], " - queue PAUSED" if rep["paused"] else "", s["status"].upper(), s["crit"], s["warn"], s["nodata"]))
    L.append("")
    L.append("## Breaches (ranked)")
    L.append("")
    if rep["breaches"]:
        L.append("| # | sev | SLO | scope | value (limit) | for | root cause / hint | fix |")
        L.append("|---|---|---|---|---|---|---|---|")
        for i, b in enumerate(rep["breaches"], 1):
            L.append("| %d | %s | %s | %s | %s (%s) %s | %s | %s | [%s](../%s) |" % (i, b["severity"].upper(), b["slo"], _cell(b["scope"]), "-" if b["value"] is None else b["value"], "-" if b["threshold"] is None else b["threshold"], b["unit"], _fmt_h(b.get("hours") or 0), _cell(b["hint"]), FIX[b["slo"]], b["fix"]))
    else:
        L.append("No SLO is in breach.")
    L.append("")
    L.append("## Per repo / lane (24 h)")
    L.append("")
    L.append("| repo | landed | attempts | bad share | pullable | runway h | landing | bad | runway | false credit (7 d) |")
    L.append("|---|---|---|---|---|---|---|---|---|---|")
    for r, v in sorted(rep["repos"].items()):
        fc = v.get("false_credit")
        L.append("| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |" % (r, v["landed_24h"], v["attempts_24h"], "-" if v["bad_share"] is None else "%d%%" % round(v["bad_share"] * 100), "?" if v["pullable"] is None else v["pullable"], "-" if v["runway_h"] is None else v["runway_h"],
                                                                      v.get("landing"), v.get("bad_state"), v.get("runway_state"), "%d/%d" % (fc["false"], fc["audited"]) if fc else "no audits"))
    L.append("")
    L.append("## Gates (hygiene streaks)")
    L.append("")
    if rep["lanes"]:
        L.append("| lane | kind | red passes | stalled | state |")
        L.append("|---|---|---|---|---|")
        for g in rep["lanes"]:
            L.append("| %s/%s | %s | %d | %s | %s |" % (g["repo"], g["branch"], g["kind"], g["count"], _fmt_h(g["stall_h"]), g["state"]))
    else:
        L.append("No gate or merge streak is open.")
    L.append("")
    L.append("## Deploy and promote lag")
    L.append("")
    b = rep["deploy"]["box"]
    L.append("- box vs claude/feature tip: **%s** - %s" % (b["state"], b.get("detail") or "-"))
    for r, p in sorted(rep["deploy"]["promote"].items()):
        L.append("- develop -> main %s: **%s**%s - %s" % (r, p["state"], " (held on purpose)" if p.get("held") else "", p.get("detail") or "-"))
    L.append("")
    L.append("## Backups")
    L.append("")
    bk = rep["backup"]
    for k in ("hourly", "daily"):
        v = bk.get(k)
        if v:
            L.append("- %s: **%s**%s %s" % (k, v["state"], "" if v.get("age_h") is None else " (%sh old)" % v["age_h"], v.get("detail", "")))
    L.append("")
    L.append("## Prod health")
    L.append("")
    if rep["prod"]["checks"]:
        L.append("| service | HTTP | ms | ok |")
        L.append("|---|---|---|---|")
        for k in rep["prod"]["checks"]:
            L.append("| %s | %s | %s | %s |" % (k["name"], k["code"] if k["code"] is not None else "none", k["ms"], "yes" if k["ok"] else "NO"))
    else:
        L.append("State: %s." % rep["prod"]["state"])
    L.append("")
    L.append("## Staging evidence and drift")
    L.append("")
    for k, v in sorted(rep["evidence"].items()):
        L.append("- %s: **%s**%s (limit %s)" % (k, v["state"], "" if v["age_s"] is None else ", %s old" % _fmt_h(_h(v["age_s"])), _fmt_h(_h(v["limit_s"]))))
    L.append("- box_verify drift: **%s**%s" % (rep["drift"]["state"], "" if rep["drift"].get("count") is None else " (%d finding(s))" % rep["drift"]["count"]))
    if rep["nodata"]:
        L.append("")
        L.append("## No data (cannot be judged yet)")
        L.append("")
        for n in rep["nodata"]:
            L.append("- " + n)
    L.append("")
    L.append("Runbook: `docs/FLEET_RUNBOOK.md`. Raw data: `state/fleet_slo.json`. Hourly line: %s" % (rep["notify_line"] or "none (nothing in breach > %gh)" % rep["thresholds"]["notify_h"]))
    return "\n".join(L) + "\n"


# ------------------------------------------------------------------------------------------------------------------ run / cli
def log(root, line):
    p = os.path.join(root, "logs", "fleet_slo.log")
    try:
        os.makedirs(os.path.dirname(p), exist_ok=True)
        if os.path.getsize(p) > 1_000_000:
            keep = _read(p).splitlines()[-2000:]
            _atomic(p, "\n".join(keep) + "\n")
    except OSError:
        pass
    try:
        with open(p, "a") as fh:
            fh.write(line + "\n")
    except OSError:
        pass


def run(now=None, root=None, state=None, www=None, dry=False, net=True):
    root, state = root or ROOT, state or STATE
    www = www or os.environ.get("OVN_SLO_WWW") or os.path.join(root, "www")
    m = mode(state)
    if m == "off":
        return None, "off"
    prev = (_json(os.path.join(state, "fleet_slo_state.json")) or {}).get("breaches")
    rep = collect(now=now, root=root, state=state, net=net, prev_tracker=prev)
    tracker = rep.pop("_tracker")
    rep["mode"] = m
    if not dry:
        _atomic(os.path.join(state, "fleet_slo.json"), json.dumps(rep, indent=1, sort_keys=True, default=str))
        _atomic(os.path.join(state, "fleet_slo_state.json"), json.dumps({"ts": rep["ts"], "breaches": tracker}, indent=1, sort_keys=True))
        _atomic(os.path.join(www, "fleet_slo.md"), render_md(rep))
        s = rep["summary"]
        log(root, "%s status=%s crit=%d warn=%d nodata=%d mode=%s line=%s" % (rep["generated_at"], s["status"], s["crit"], s["warn"], s["nodata"], m, ("[%s] %s" % ("sent-to-hourly" if m == "on" else "shadow-only", rep["notify_line"])) if rep["notify_line"] else "none"))
    return rep, m


def main(argv=None):
    ap = argparse.ArgumentParser(prog="ovn_fleet_slo.py", add_help=True)
    ap.add_argument("cmd", nargs="?", default="run", choices=["run", "audit", "mark-deployed", "mode", "line"])
    ap.add_argument("value", nargs="?")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--print", dest="prt", action="store_true")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--no-net", action="store_true")
    ap.add_argument("--now", type=float)
    ap.add_argument("--repo")
    ap.add_argument("--ref")
    ap.add_argument("--verdict")
    ap.add_argument("--audit", default="")
    ap.add_argument("--gate", default="")
    ap.add_argument("--note", default="")
    ap.add_argument("--sha")
    ap.add_argument("--ts", type=float)
    ap.add_argument("--export-tip", action="store_true")
    ap.add_argument("--git-dir", default=os.getcwd())
    ap.add_argument("--path", default="scripts/overnight-queue")
    ap.add_argument("--limit", type=int, default=300)
    ap.add_argument("--fetch", action="store_true")
    a = ap.parse_args(argv)
    if a.export_tip:
        print(json.dumps(export_tip(a.git_dir, a.ref or "origin/claude/feature", a.path, a.limit, a.fetch, a.now), sort_keys=True))
        return 0
    if a.cmd == "mode":
        if a.value is None:
            print(mode())
            return 0
        if a.value not in ("off", "shadow", "on"):
            print("mode must be off|shadow|on", file=sys.stderr)
            return 2
        _atomic(os.path.join(STATE, "fleet_slo.mode"), a.value + "\n")
        print("fleet_slo mode: %s (env OVN_FLEET_SLO, if set, still wins)" % a.value)
        return 0
    if a.cmd == "audit":
        if not (a.repo and a.ref and a.verdict):
            print("audit needs --repo --ref --verdict", file=sys.stderr)
            return 2
        try:
            row = append_audit(STATE, a.repo, a.ref, a.verdict, a.audit, a.gate, a.note, a.now)
        except ValueError as e:
            print(str(e), file=sys.stderr)
            return 2
        print(json.dumps(row, sort_keys=True))
        return 0
    if a.cmd == "mark-deployed":
        if not a.sha or not re.match(r"^[0-9a-f]{7,40}$", a.sha):
            print("mark-deployed needs --sha <hex sha>", file=sys.stderr)
            return 2
        _atomic(os.path.join(STATE, "deployed_sha"), json.dumps({"sha": a.sha, "ts": a.ts if a.ts is not None else time.time()}) + "\n")
        print("deployed_sha = %s" % a.sha)
        return 0
    if a.cmd == "line":
        for l in update_lines(STATE, a.now):
            print(l)
        return 0
    rep, m = run(now=a.now, dry=a.dry_run, net=not a.no_net)
    if rep is None:
        print("fleet_slo: mode off, nothing done")
        return 0
    if a.json:
        print(json.dumps(rep, indent=1, sort_keys=True, default=str))
    elif a.prt or a.dry_run:
        print(render_md(rep))
    else:
        s = rep["summary"]
        print("fleet_slo: %s crit=%d warn=%d nodata=%d mode=%s%s" % (s["status"], s["crit"], s["warn"], s["nodata"], m, (" line: " + rep["notify_line"]) if rep["notify_line"] else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
