#!/usr/bin/env python3
"""ovn_supply_forecast.py - per-repo SUPPLY RUNWAY FORECAST and research request (2026-11-01, package K5-supply-engine). Read-only on queue data, no model calls.

Why: every active repo hits pullable 0 within ~2 days. Supply is bounded by the [ready] roadmap features (each decomposes into ~5 backlog items), the fleet burns ~11-18 landed items/day
per active app, and the Qwen lanes add only ~1-3 items/day. ovn_supply_report.py says WHY a repo is dry AFTER it ran dry; nothing said, 24 hours ahead, "this repo will be dry tomorrow
and needs N more features". This job does the arithmetic forward.

Per repo:
  burn_per_day   DISTINCT items that landed (outcomes.jsonl class landed / landed-uncredited, ovn_supply_ledger.PUSHED) over the trailing OVN_FORECAST_BURN_D days (default 7), / days covered
                 (the span from the oldest row in the window to now, at least 1 and at most the window: a repo whose history is 3 days old is not diluted by 4 empty days).
  pullable       what the fleet can take next now (ovn_supply_ledger.current_pullable)
  ready          [ready] roadmap features (same selector as ovn_planner.sh / ovn_supply_report.py)
  decomposable   ready * OVN_FORECAST_ITEMS_PER_FEATURE (default 5)
  supply         pullable + decomposable
  runway_h       supply / (burn_per_day / 24); None when nothing burns (no forecast, no request)
A repo is SHORT when runway_h < OVN_FORECAST_RUNWAY_H (default 24). For a short repo:
  shortfall_items     ceil(burn_per_day * OVN_FORECAST_TARGET_H / 24 - supply)   (target default 48 h of work in hand)
  shortfall_features  ceil(shortfall_items / items_per_feature)
  priority            high when runway_h < OVN_FORECAST_HIGH_H (default 6), else normal

Outputs: state/supply_forecast.json (atomic; every repo, always written unless --dry-run), one `hb` heartbeat row per run (K6: quiet != dead) + one log line per short repo to logs/supply_forecast.log (rotated at 1 MB).
MODE OVN_SUPPLY_FORECAST=shadow|on|off (default shadow):
  shadow  forecast + json + log only. The json says `would_request` per short repo; NO state/research_requests file and NO digest line.
  on      additionally writes state/research_requests/<repo>.json {repo, ts, priority, shortfall_items, shortfall_features, runway_h, burn_per_day, pullable, ready, ...} (atomic, rewritten each run
          while the repo stays short, REMOVED when it is no longer short) and ovn_notify's hourly update shows ONE bullet `Supply runway < 24h: ...` (digest text only, no push of its own).
  off     does nothing.
CONSUMERS (2026-11-03, K5): ovn_research_requests.py is the shared reader. ovn_local_research.py / ovn_work_supply.py bypass their "enough already" early-exit for a repo with a live request (cooldown,
daily cap, --max and validators still apply), ovn_research_trigger_check.py raises the roadmap-feature floor alert earlier. Consumption is logged to state/research_requests_consumed.log.
SHADOW -> ON (code default stays `shadow`): flip only after these SOAK CRITERIA hold in logs/supply_forecast.log over >= 7 consecutive days (the log first filled 2026-11-02 09:37; at review time
it held < 1 day: 23 lines, only test-automation-agent (a TRUE starve: pullable 0 for 8h) and iptv_apps (17.8-22.6h, borderline)): (a) at most 2 distinct repos would-request on any one run,
(b) every would-request repo is confirmed by an actual starve (pullable < 5 or an ovn_research_trigger_check starving row) within 24h, (c) no repo flaps short/not-short more than 4 times a day,
(d) no row for a non-repo. Then set OVN_SUPPLY_FORECAST=on in the forecast cron line (rollback: back to shadow / off; the request goes stale after 6h by itself).

usage:  ovn_supply_forecast.py [--print] [--json] [--dry-run] [--now EPOCH] [--repos a,b]
cron (proposed, NOT installed; box):  7,37 * * * * cd ~/overnight-queue && python3 scripts/ovn_supply_forecast.py >> logs/supply_forecast.cron.log 2>&1
      (flip to `env OVN_SUPPLY_FORECAST=on python3 ...` after a day of shadow lines in logs/supply_forecast.log looks right)
env:    OVN_DIR / OVN_NOTIFY_STATE, OVN_SUPPLY_FORECAST, OVN_FORECAST_RUNWAY_H (24), OVN_FORECAST_HIGH_H (6), OVN_FORECAST_TARGET_H (48), OVN_FORECAST_ITEMS_PER_FEATURE (5), OVN_FORECAST_BURN_D (7),
        OVN_FORECAST_REPOS (comma list; default = every repo with a roadmap file under $OVN_DIR/roadmap AND a clone under $OVN_DIR/repos/<name> that is not discontinued)
"""
import json
import math
import os
import re
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

ROOT = os.environ.get("OVN_DIR") or os.path.expanduser("~/overnight-queue")
STATE = os.environ.get("OVN_NOTIFY_STATE") or os.path.join(ROOT, "state")
READY_RE = re.compile(r"^- \[ \] \[P[1-4]\] \[ready\]", re.M)
DISCONTINUED = ("social-media-manager", "task-manager-platform", "shrike-labs-website")


def _envf(name, default):
    try:
        return float(os.environ.get(name, default))
    except ValueError:
        return float(default)


def mode():
    m = os.environ.get("OVN_SUPPLY_FORECAST", "shadow").strip().lower()
    return m if m in ("shadow", "on", "off") else "shadow"


def _read(path):
    try:
        with open(path, errors="replace") as f:
            return f.read()
    except OSError:
        return ""


def burn_per_day(rows, repo, now, window_d):
    """Distinct landed items per day for `repo` over the trailing window (see the module docstring). None when the repo has no row at all in the window (unknown, not zero)."""
    import ovn_supply_ledger as led
    lo = now - window_d * 86400.0
    mine = [r for r in rows if r.get("repo") == repo and r["_t"] >= lo]
    if not mine:
        return None
    oldest = min(r["_t"] for r in mine)
    days = min(float(window_d), max(1.0, (now - oldest) / 86400.0))
    landed = set()
    for r in mine:
        if led._is_skip(r) or r.get("class") not in led.PUSHED:
            continue
        landed.add(r.get("item_hash") or r.get("feat_tag") or ("%s@%s" % (r.get("item", ""), r.get("ts"))))
    return len(landed) / days


def forecast_repo(repo, pullable, ready, burn, items_per_feature, runway_floor, high_h, target_h):
    """Pure arithmetic -> record dict (also used by the tests)."""
    decomposable = ready * items_per_feature
    supply = (pullable or 0) + decomposable
    rec = {"repo": repo, "pullable": pullable, "ready": ready, "decomposable": decomposable, "supply": supply,
           "burn_per_day": None if burn is None else round(burn, 2), "runway_h": None, "short": False, "priority": None,
           "shortfall_items": 0, "shortfall_features": 0}
    if burn is None or burn <= 0 or pullable is None:
        return rec
    rec["runway_h"] = round(supply / (burn / 24.0), 1)
    if rec["runway_h"] < runway_floor:
        rec["short"] = True
        rec["priority"] = "high" if rec["runway_h"] < high_h else "normal"
        need = int(math.ceil(burn * target_h / 24.0 - supply))
        rec["shortfall_items"] = max(1, need)
        rec["shortfall_features"] = max(1, int(math.ceil(rec["shortfall_items"] / float(items_per_feature))))
    return rec


def default_repos(root):
    d = os.path.join(root, "roadmap")
    try:
        names = sorted(f[:-3] for f in os.listdir(d) if f.endswith(".md"))
    except OSError:
        names = []
    # 2026-11-03 (K5): roadmap/ also holds non-repo docs (README.md was forecast as a "repo": supply 0, runway None, one bogus row in every json). A forecast repo must have a
    # roadmap AND a clone under repos/<name> (the only repos the fleet can actually work).
    return [n for n in names if n not in DISCONTINUED and n.upper() != "README" and os.path.isdir(os.path.join(root, "repos", n))]


def collect(now=None, root=None, state=None, repos=None):
    import ovn_supply_ledger as led
    now = float(now if now is not None else time.time())
    root, state = root or ROOT, state or STATE
    window_d = _envf("OVN_FORECAST_BURN_D", 7)
    ipf = max(1.0, _envf("OVN_FORECAST_ITEMS_PER_FEATURE", 5))
    floor, high, target = _envf("OVN_FORECAST_RUNWAY_H", 24), _envf("OVN_FORECAST_HIGH_H", 6), _envf("OVN_FORECAST_TARGET_H", 48)
    if repos is None:
        env = os.environ.get("OVN_FORECAST_REPOS")
        repos = [x.strip() for x in env.split(",") if x.strip()] if env else default_repos(root)
    rows = led.read_rows(state, now - window_d * 86400.0)
    pull = led.current_pullable(root, repos)
    out = {"ts": now, "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(now)), "mode": mode(), "items_per_feature": ipf,
           "runway_floor_h": floor, "target_h": target, "repos": {}}
    for repo in repos:
        ready = len(READY_RE.findall(_read(os.path.join(root, "roadmap", repo + ".md"))))
        rec = forecast_repo(repo, pull.get(repo), ready, burn_per_day(rows, repo, now, window_d), ipf, floor, high, target)
        rec["line"] = repo_line(rec) if rec["short"] else None
        out["repos"][repo] = rec
    return out


def repo_line(rec):
    return "%s: runway %gh (pullable %s + %d ready x ~%g = %s items, burn %s/d); need ~%d more item(s) = %d feature(s), priority %s" % (
        rec["repo"], rec["runway_h"], rec["pullable"], rec["ready"], rec["decomposable"] / rec["ready"] if rec["ready"] else 0, rec["supply"], rec["burn_per_day"],
        rec["shortfall_items"], rec["shortfall_features"], rec["priority"])


def short_repos(fc):
    return [r for r, rec in sorted(fc["repos"].items()) if rec.get("short")]


def digest_lines(fc, max_lines=3):
    """ONE bullet for the hourly update (mode `on` only): `Supply runway < 24h: repo Xh (+N feat), ...`; [] otherwise."""
    if not fc or fc.get("mode") != "on":
        return []
    sh = short_repos(fc)
    if not sh:
        return []
    parts = ["%s %gh (need ~%d feat%s)" % (r, fc["repos"][r]["runway_h"], fc["repos"][r]["shortfall_features"], ", HIGH" if fc["repos"][r]["priority"] == "high" else "") for r in sh[:max_lines]]
    if len(sh) > max_lines:
        parts.append("+%d more" % (len(sh) - max_lines))
    return ["Supply runway < %gh: %s" % (fc.get("runway_floor_h", 24), "; ".join(parts))]


def fresh_forecast(now, state=None, max_age=3 * 3600):
    try:
        with open(os.path.join(state or STATE, "supply_forecast.json")) as f:
            d = json.load(f)
        if isinstance(d, dict) and 0 <= now - float(d.get("ts", 0)) < max_age:
            return d
    except (OSError, ValueError, TypeError):
        pass
    return None


def _atomic(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp.%d" % os.getpid()
    with open(tmp, "w") as f:
        json.dump(obj, f, indent=1, sort_keys=True)
    os.replace(tmp, path)


def write_outputs(fc, root=None, state=None, stamp=None):
    """state/supply_forecast.json + log lines always; research_requests/<repo>.json only in mode `on` (and stale requests of repos that recovered are removed in that mode)."""
    root, state = root or ROOT, state or STATE
    try:
        _atomic(os.path.join(state, "supply_forecast.json"), fc)
    except OSError:
        pass
    logp = os.path.join(root, "logs", "supply_forecast.log")
    try:
        os.makedirs(os.path.dirname(logp), exist_ok=True)
        if os.path.getsize(logp) > 1_000_000:
            keep = _read(logp).split("\n")[-2000:]
            with open(logp, "w") as f:
                f.write("\n".join(keep))
    except OSError:
        pass
    try:
        with open(logp, "a") as f:
            # K6 (2026-11-03): one heartbeat row per run. Before this the log only got a row per SHORT repo, so a healthy fleet (no repo short) left it silent for 15 h and
            # 'quiet by design' looked exactly like 'cron dead'. The row deliberately carries no "[mode]" tag (the per-repo rows own that token).
            f.write("%s hb mode=%s checked=%d short=%d floor_h=%g\n" % (stamp or time.strftime("%Y-%m-%d %H:%M:%S"), fc["mode"], len(fc["repos"]), len(short_repos(fc)), fc["runway_floor_h"]))
            for r in short_repos(fc):
                f.write("%s [%s] %s\n" % (stamp or time.strftime("%Y-%m-%d %H:%M:%S"), fc["mode"], fc["repos"][r]["line"]))
    except OSError:
        pass
    if fc["mode"] != "on":
        return
    rdir = os.path.join(state, "research_requests")
    for repo, rec in sorted(fc["repos"].items()):
        p = os.path.join(rdir, repo + ".json")
        try:
            if rec["short"]:
                _atomic(p, {"repo": repo, "ts": fc["ts"], "priority": rec["priority"], "shortfall_items": rec["shortfall_items"], "shortfall_features": rec["shortfall_features"],
                            "runway_h": rec["runway_h"], "burn_per_day": rec["burn_per_day"], "pullable": rec["pullable"], "ready": rec["ready"], "target_h": fc["target_h"],
                            "source": "ovn_supply_forecast"})
            elif os.path.isfile(p):
                os.unlink(p)
        except OSError:
            pass


def main(argv):
    if mode() == "off":
        print("supply forecast: OVN_SUPPLY_FORECAST=off - skip")
        return 0
    now = float(argv[argv.index("--now") + 1]) if "--now" in argv else None
    repos = argv[argv.index("--repos") + 1].split(",") if "--repos" in argv else None
    fc = collect(now=now, repos=repos)
    if "--dry-run" not in argv:
        write_outputs(fc)
    if "--json" in argv:
        print(json.dumps(fc, indent=1, sort_keys=True))
    else:
        sh = short_repos(fc)
        for r in sh:
            print("[%s] %s" % (fc["mode"], fc["repos"][r]["line"]))
        if not sh:
            print("supply forecast [%s]: no repo under %gh runway (%d checked)" % (fc["mode"], fc["runway_floor_h"], len(fc["repos"])))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
