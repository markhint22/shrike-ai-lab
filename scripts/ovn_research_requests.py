#!/usr/bin/env python3
"""scripts/ovn_research_requests.py - the CONSUMER side of state/research_requests/<repo>.json (2026-11-03, package K5-supply).

ovn_supply_forecast.py (OVN_SUPPLY_FORECAST=on) writes one request file per SHORT repo (runway < 24h) and removes it when the repo recovers. Until now nothing read it
(next.json F7). The readers are ovn_local_research.py, ovn_work_supply.py (both bypass their "this repo has enough" early-exit for a repo with a live request, but NOTHING else:
their cooldown, daily cap, per-pass --max and every validator still apply) and ovn_research_trigger_check.py (raises the roadmap-feature floor alert earlier).

A request is LIVE when: the file parses, names the repo, is younger than OVN_RR_MAX_AGE_H (default 6; the forecast cron rewrites it every 30 min, so an older file means the
forecast stopped), and the FRESH forecast (state/supply_forecast.json, < 3h old) does not say the repo is no longer short. A request whose repo is no longer short is REMOVED by
the first consumer that notices (the forecast removes it too on its next `on` run). One request per repo by construction (the file name is the repo).
Every consumption is logged to state/research_requests_consumed.log: `YYYY-MM-DD HH:MM:SS <consumer> <repo> <action> ...`.

env: OVN_RESEARCH_REQUESTS=on|off (default on: inert while no request file exists, i.e. while the forecast is in shadow), OVN_RR_MAX_AGE_H (6), OVN_NOTIFY_STATE / OVN_DIR (state dir).
"""
import json
import os
import re
import time

HERE = os.path.dirname(os.path.abspath(__file__))


def state_dir(state=None):
    if state:
        return state
    env = os.environ.get("OVN_NOTIFY_STATE")
    if env:
        return env
    return os.path.join(os.environ.get("OVN_DIR") or os.path.expanduser("~/overnight-queue"), "state")


def enabled():
    return os.environ.get("OVN_RESEARCH_REQUESTS", "on").strip().lower() != "off"


def _max_age_s():
    try:
        return float(os.environ.get("OVN_RR_MAX_AGE_H", "6")) * 3600.0
    except ValueError:
        return 6 * 3600.0


def _load(path):
    try:
        with open(path) as f:
            d = json.load(f)
        return d if isinstance(d, dict) else None
    except (OSError, ValueError):
        return None


def _forecast_says_not_short(repo, st, now, max_age=3 * 3600):
    """True only when a FRESH forecast json exists, lists the repo and says short=False."""
    d = _load(os.path.join(st, "supply_forecast.json"))
    if not d:
        return False
    try:
        if not (0 <= now - float(d.get("ts", 0)) < max_age):
            return False
    except (TypeError, ValueError):
        return False
    rec = (d.get("repos") or {}).get(repo)
    return isinstance(rec, dict) and rec.get("short") is False


def active(repo, now=None, state=None, remove=True):
    """The live request dict for `repo`, or None. Side effect: removes a request whose repo the fresh forecast says is no longer short (and a malformed / stale one is simply ignored)."""
    if not enabled() or not repo or not re.match(r"^[\w.-]+$", repo):
        return None
    now = time.time() if now is None else float(now)
    st = state_dir(state)
    p = os.path.join(st, "research_requests", repo + ".json")
    d = _load(p)
    if not d or d.get("repo") != repo:
        return None
    try:
        age = now - float(d.get("ts", 0))
    except (TypeError, ValueError):
        return None
    if age > _max_age_s() or age < -300:
        return None
    if _forecast_says_not_short(repo, st, now):
        if remove:  # a dry run reads the request but never touches state
            try:
                os.unlink(p)
            except OSError:
                pass
            log("request-reader", repo, "removed", "repo no longer short", now=now, state=st)
        return None
    return d


def log(consumer, repo, action, note="", now=None, state=None):
    """One line in state/research_requests_consumed.log. Never raises."""
    now = time.time() if now is None else float(now)
    try:
        st = state_dir(state)
        os.makedirs(st, exist_ok=True)
        with open(os.path.join(st, "research_requests_consumed.log"), "a") as f:
            f.write("%s %s %s %s%s\n" % (time.strftime("%Y-%m-%d %H:%M:%S", time.gmtime(now)), consumer, repo, action, (" " + note) if note else ""))
    except OSError:
        pass


def describe(req):
    return "priority %s, runway %sh, need ~%s item(s)/%s feature(s)" % (req.get("priority"), req.get("runway_h"), req.get("shortfall_items"), req.get("shortfall_features"))


def pending(now=None, state=None):
    """Live requests, high priority first then by runway: [(repo, request)]. For callers that loop over repos."""
    st = state_dir(state)
    out = []
    try:
        names = sorted(f[:-5] for f in os.listdir(os.path.join(st, "research_requests")) if f.endswith(".json"))
    except OSError:
        return []
    for n in names:
        r = active(n, now=now, state=st)
        if r:
            out.append((n, r))
    out.sort(key=lambda x: (0 if x[1].get("priority") == "high" else 1, x[1].get("runway_h") if isinstance(x[1].get("runway_h"), (int, float)) else 1e9, x[0]))
    return out


if __name__ == "__main__":      # operator view: live requests
    import sys
    for repo, r in pending():
        print("%s: %s" % (repo, describe(r)))
    sys.exit(0)
