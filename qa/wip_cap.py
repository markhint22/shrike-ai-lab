#!/usr/bin/env python3
"""wip_cap.py - Phase 5 WIP-cap observer (docs/QA_PLAN_2026-10-01.md section 6, policy item 2). SHADOW: a log and one alert line, nothing else.

    wip_cap.py run      [--no-record] [--days 30]     compute, append rows to state/qa_shadow/wip_cap.jsonl, alert when over a cap
    wip_cap.py report   [--days 30] [--json]          the same computation, printed (per repo: counts by class, median/oldest age, state), writes nothing
    wip_cap.py eligible --repo R [--class A|B|C] [--area PATH]   the dispatcher's QUESTION ("may repo R pick a new behavioral item?"), see below

What is counted ("landed but not yet through its gates"): the FEATURES (landed records of state/qa_ledger.jsonl grouped by repo + feat tag; a record
without a tag is its own feature) that are NOT yet cleared. A feature is cleared when
  * a ledger event {type: "gated"|"promoted", rec: <record key>} exists (hook for later gates), or
  * every commit attributed to it is an ancestor of the repo's PROD ref (origin/main by default, env OVN_QA_WIP_PROD_REF) - the promote is the
    gate that matters while the per-feature gates are still shadow.
A feature with no attributed commit (ledger flag no-commit) cannot be placed: it is reported as `unattributed`, never counted. A repo whose clone or
prod ref is missing is reported as `unknown` (never counted, never alerted): infra gaps must not look like a WIP breach. Age = now - landing time.
Class = the highest risk class of the feature's records (A auth/paywall/billing/migrations/prod config, B other source, C tests/docs/deletes), DOWNGRADED to C when every commit
subject is docs/style/test/chore (e.g. "docs: add docstring to ...": qa_ledger classes it by path, but it changes no behavior) or, with no subjects, the records' category is docs-like.
Only BEHAVIORAL features (A and B) count toward a cap; class C (tests-hardening, docs) is reported but never throttled (plan: "test-hardening, bug and
QA-lane items continue").

Starting caps (plan section 6, guesses to tune from data):  billwatch / iptv_apps / gitlark 8, test-automation-agent 12, every other repo 15,
global 40, and 8 per class A AREA (area = the first two path components of the feature's first non-test, non-doc file).
Scope: OVN_QA_WIP_CAP_SCOPE="billwatch,iptv_apps" counts ONLY those repos (default unset = every repo). Repos the daily promote never promotes (xlite, shrike-monitor, ...) never reach
origin/main, so they could never clear and would alert every UTC day; the Phase 5 cron line scopes the observer to the promoted repos.
Override without a deploy: OVN_QA_WIP_CAP_REPOS="billwatch=6,xlite=20"  OVN_QA_WIP_CAP_DEFAULT=15  OVN_QA_WIP_CAP_GLOBAL=40  OVN_QA_WIP_CAP_AREA=8.
State per scope: UNDER (< cap), AT (== cap: the plan's "at the cap a repo stops picking new behavioral items"), OVER (> cap: the alert).

Flag OVN_QA_WIP_CAP=off|shadow|soft|hard (default shadow; any other value falls back to shadow):
  off     nothing is computed, written or alerted.
  shadow  rows + the alert line; `eligible` ALWAYS answers eligible (and reports would_hold).
  soft / hard  PARSED, but NOT WIRED to the dispatcher in this package: only the `eligible` query honours them (soft: hold class A/B items of a repo AT or
          OVER its own cap; hard: also hold when the global cap or the item's class A area cap is reached). Nothing calls `eligible` yet.
Dispatcher hook point (ships later, documented in qa/wip_cap.README.md): scripts/lib_item_select.sh, right after the `ovn_bug_first_order` filter inside
ovn_resolve_top_item and the other selectors: drop behavioral lines when `wip_cap.py eligible --repo <r>` prints HOLD. Bug / QA-lane / test-hardening lines are
never dropped, and a manual override file state/wip_cap_override_<repo> (any content) makes the answer eligible.

Never touches a live clone for writing (read-only git), never takes run.lock, always exits 0.
"""
import json
import os
import re
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import qa_common as qc  # noqa: E402
import qa_ledger as ql  # noqa: E402
import phase5_common as p5  # noqa: E402

ENV = "OVN_QA_WIP_CAP"
MODES = ("off", "shadow", "soft", "hard")
REPO_CAPS = {"billwatch": 8, "iptv_apps": 8, "gitlark": 8, "test-automation-agent": 12}
DEFAULT_REPO_CAP = 15
GLOBAL_CAP = 40
AREA_CAP = 8
BEHAVIORAL = ("A", "B")
RISK_ORDER = {"A": 3, "B": 2, "C": 1}
CLEARING_EVENTS = ("gated", "promoted")
HOUR = 3600.0
# Commits that change no behavior whatever files they touch (docstring / comment / formatting / test / chore churn). qa_ledger labels them A/B by PATH; the cap must not.
NON_BEHAVIORAL_SUBJECT = re.compile(r"^(docs?|style|test|tests|chore|ci|build)(\([^)]*\))?!?:", re.I)
NON_BEHAVIORAL_CATEGORY = ("docs", "doc", "documentation", "style", "test", "tests", "chore")


def non_behavioral(f):
    """True when EVERY commit subject of the feature is docs/style/test/chore, or (no subjects) its records' category is docs-like. Pure."""
    subs = f.get("subjects") or []
    if subs:
        return all(NON_BEHAVIORAL_SUBJECT.match(s.strip()) for s in subs if isinstance(s, str)) and all(isinstance(s, str) for s in subs)
    cats = f.get("categories") or []
    return bool(cats) and all(str(c).lower() in NON_BEHAVIORAL_CATEGORY for c in cats)


def effective_risk(f):
    return "C" if f["risk"] in BEHAVIORAL and non_behavioral(f) else f["risk"]


def mode():
    return p5.flag(ENV, MODES, "shadow")[0]


def _int_env(name, default):
    try:
        v = int(os.environ.get(name, ""))
        return v if v > 0 else default
    except ValueError:
        return default


def caps():
    """-> (repo_caps dict, default_repo_cap, global_cap, area_cap) after env overrides."""
    rc = dict(REPO_CAPS)
    for part in os.environ.get("OVN_QA_WIP_CAP_REPOS", "").split(","):
        if "=" in part:
            k, v = part.split("=", 1)
            try:
                if int(v) > 0 and ql.safe_name(k.strip()):
                    rc[k.strip()] = int(v)
            except ValueError:
                pass
    return rc, _int_env("OVN_QA_WIP_CAP_DEFAULT", DEFAULT_REPO_CAP), _int_env("OVN_QA_WIP_CAP_GLOBAL", GLOBAL_CAP), _int_env("OVN_QA_WIP_CAP_AREA", AREA_CAP)


def scope_repos():
    """Repos the observer counts (OVN_QA_WIP_CAP_SCOPE, comma list); None = all repos."""
    names = [x.strip() for x in os.environ.get("OVN_QA_WIP_CAP_SCOPE", "").split(",") if x.strip() and ql.safe_name(x.strip())]
    return set(names) if names else None


def cap_state(n, cap):
    """UNDER | AT | OVER. Pure."""
    if n > cap:
        return "OVER"
    if n == cap:
        return "AT"
    return "UNDER"


def area_of(files):
    """First two path components of the first non-test, non-doc file ('' when there is none)."""
    for f in files or []:
        if not isinstance(f, str) or ql.TEST_PATH.search(f) or ql.DOC_PATH.search(f):
            continue
        return "/".join(f.split("/")[:2])
    return ""


def build_features(recs):
    """Group landed records into features -> list of dicts {repo, key, risk, epoch (first landing), commits, files, rec_keys}."""
    by = {}
    for r in recs:
        k = (r["repo"], r["feat_tag"]) if r.get("feat_tag") else (r["repo"], "rec:" + r["key"])
        f = by.setdefault(k, {"repo": r["repo"], "key": k[1], "risk": "C", "epoch": r["epoch"], "commits": [], "files": [], "rec_keys": [], "subjects": [], "categories": []})
        for s in r.get("subjects", []) or []:
            if s not in f["subjects"]:
                f["subjects"].append(s)
        if r.get("category") and r["category"] not in f["categories"]:
            f["categories"].append(r["category"])
        if RISK_ORDER.get(r.get("risk"), 0) > RISK_ORDER.get(f["risk"], 0):
            f["risk"] = r["risk"]
        f["epoch"] = min(f["epoch"], r["epoch"])
        for c in r.get("commits", []):
            if c not in f["commits"]:
                f["commits"].append(c)
        for p in r.get("files", []):
            if p not in f["files"]:
                f["files"].append(p)
        f["rec_keys"].append(r["key"])
    return list(by.values())


def median(xs):
    xs = sorted(xs)
    if not xs:
        return None
    m = len(xs) // 2
    return xs[m] if len(xs) % 2 else (xs[m - 1] + xs[m]) / 2.0


def compute(recs, evs, now, is_cleared, max_age_days=30):
    """Pure (git is injected). is_cleared(repo, commits) -> True | False | None(unknown: no clone / no prod ref).
    -> report dict {repos: {repo: {...}}, global: {...}, areas: {area-key: {...}}}."""
    rc, dflt, gcap, acap = caps()
    cleared_recs = set(e["rec"] for e in evs if e.get("type") in CLEARING_EVENTS and e.get("rec"))
    scope = scope_repos()
    feats = [f for f in build_features([r for r in recs if now - r["epoch"] <= max_age_days * 86400 and (scope is None or r["repo"] in scope)])]
    repos = {}
    pending = []
    for f in feats:
        rp = repos.setdefault(f["repo"], {"cap": rc.get(f["repo"], dflt), "by_class": {"A": 0, "B": 0, "C": 0}, "ages_h": [], "unattributed": 0, "unknown": 0,
                                          "cleared": 0, "features": 0, "areas": {}})
        rp["features"] += 1
        if any(k in cleared_recs for k in f["rec_keys"]):
            rp["cleared"] += 1
            continue
        if not f["commits"]:
            rp["unattributed"] += 1
            continue
        cl = is_cleared(f["repo"], f["commits"])
        if cl is None:
            rp["unknown"] += 1
            continue
        if cl:
            rp["cleared"] += 1
            continue
        age_h = max(0.0, (now - f["epoch"]) / HOUR)
        er = effective_risk(f)
        rp["by_class"][er if er in rp["by_class"] else "B"] += 1
        rp["ages_h"].append((age_h, er))
        if er == "A":
            ar = area_of(f["files"]) or "(root)"
            rp["areas"][ar] = rp["areas"].get(ar, 0) + 1
        pending.append((f, age_h))
    out_repos = {}
    for name, rp in sorted(repos.items()):
        beh = [a for a, c in rp["ages_h"] if c in BEHAVIORAL]
        allages = [a for a, c in rp["ages_h"]]
        n = rp["by_class"]["A"] + rp["by_class"]["B"]
        out_repos[name] = {"cap": rp["cap"], "behavioral": n, "by_class": rp["by_class"], "pending_total": len(allages), "state": cap_state(n, rp["cap"]),
                           "median_age_h": None if median(beh) is None else round(median(beh), 1), "oldest_age_h": None if not beh else round(max(beh), 1),
                           "median_age_all_h": None if median(allages) is None else round(median(allages), 1),
                           "unattributed": rp["unattributed"], "unknown": rp["unknown"], "cleared": rp["cleared"], "features": rp["features"],
                           "class_a_areas": dict(sorted(rp["areas"].items()))}
    gn = sum(r["behavioral"] for r in out_repos.values())
    areas = {}
    for name, r in out_repos.items():
        for ar, n in r["class_a_areas"].items():
            areas["%s:%s" % (name, ar)] = {"repo": name, "area": ar, "count": n, "cap": acap, "state": cap_state(n, acap)}
    return {"repos": out_repos, "global": {"cap": gcap, "count": gn, "state": cap_state(gn, gcap)}, "areas": areas}


def over_scopes(rep):
    """[(scope, count, cap)] for every OVER scope. The ONLY thing that alerts."""
    out = [(("repo:" + n), r["behavioral"], r["cap"]) for n, r in rep["repos"].items() if r["state"] == "OVER"]
    if rep["global"]["state"] == "OVER":
        out.append(("global", rep["global"]["count"], rep["global"]["cap"]))
    out += [("area:" + k, a["count"], a["cap"]) for k, a in rep["areas"].items() if a["state"] == "OVER"]
    return out


# ---------------------------------------------------------------- git (read-only)
class GitClearing(object):
    """is_cleared() backed by the repos' PROD ref: one `git rev-list <ref> --since` per repo (a set), then membership tests."""

    def __init__(self, since_epoch):
        self.since = since_epoch
        self.sets = {}
        self.ref = os.environ.get("OVN_QA_WIP_PROD_REF", "origin/main")

    def _set(self, repo):
        if repo in self.sets:
            return self.sets[repo]
        s = None
        rd = qc.repo_dir(repo) if ql.safe_name(repo) else None
        if rd and qc.git(rd, "rev-parse", "--verify", "-q", self.ref + "^{commit}")[0] == 0:
            rc, out, _ = qc.git(rd, "rev-list", "--since=@%d" % max(0, self.since - 86400), self.ref, timeout=180)
            if rc == 0:
                s = set(out.split())
        self.sets[repo] = s
        return s

    def __call__(self, repo, commits):
        s = self._set(repo)
        if s is None:
            return None
        return all(c in s for c in commits)


# ---------------------------------------------------------------- eligibility (the dispatcher's question; NOT called by anything yet)
def eligibility(rep, repo, cls, area, m, override=False):
    """Pure. -> {eligible, would_hold, reason}. shadow/off: always eligible. soft/hard semantics are documented in the module docstring."""
    r = rep["repos"].get(repo)
    why = ""
    if cls in BEHAVIORAL:
        if r is not None and r["state"] in ("AT", "OVER"):
            why = "repo %s at/over cap (%d/%d)" % (repo, r["behavioral"], r["cap"])
        elif m == "hard" and rep["global"]["state"] in ("AT", "OVER"):
            why = "global WIP at/over cap (%d/%d)" % (rep["global"]["count"], rep["global"]["cap"])
        elif m == "hard" and cls == "A" and area:
            a = rep["areas"].get("%s:%s" % (repo, area))
            if a and a["state"] in ("AT", "OVER"):
                why = "class A area %s at/over cap (%d/%d)" % (area, a["count"], a["cap"])
    would = bool(why)
    hold = would and m in ("soft", "hard") and not override
    return {"eligible": not hold, "would_hold": would, "reason": why if would else "", "mode": m, "override": bool(override)}


# ---------------------------------------------------------------- commands
def run_compute(now, days):
    recs, evs = ql.load_ledger()
    return compute(recs, evs, now, GitClearing(now - days * 86400), days)


def rows_of(rep, now, m):
    ts = ql.iso(int(now))
    rows = []
    for name, r in rep["repos"].items():
        rows.append(dict(r, kind="repo", repo=name, ts=ts, mode=m))
    rows.append(dict(rep["global"], kind="global", ts=ts, mode=m))
    for k, a in rep["areas"].items():
        rows.append(dict(a, kind="area", ts=ts, mode=m))
    return rows


def cmd_run(argv, now=None):
    now = time.time() if now is None else now
    m, note = p5.flag(ENV, MODES, "shadow")
    if m == "off":
        return {"mode": "off", "wrote": 0, "alerts": 0, "over": []}
    days = int(p5.opt(argv, "--days", "30") or 30)
    rep = run_compute(now, days)
    over = over_scopes(rep)
    wrote = alerts = 0
    if "--no-record" not in argv:
        for row in rows_of(rep, now, m):
            wrote += int(p5.append_jsonl(p5.shadow_path("wip_cap.jsonl"), row))
        for scope, n, cap in over:
            if p5.alert_once("WARN", "wip-cap:" + scope, "landed-but-ungated behavioral features %d > cap %d (mode=%s; shadow = alert only, nothing throttled)" % (n, cap, m),
                             "wip-cap|" + scope, now):
                alerts += 1
    return {"mode": m, "note": note, "wrote": wrote, "alerts": alerts, "over": [o[0] for o in over], "global": rep["global"],
            "repos": {n: {"state": r["state"], "behavioral": r["behavioral"], "cap": r["cap"], "median_age_h": r["median_age_h"]} for n, r in rep["repos"].items()}}


def render(rep):
    L = ["WIP (landed, not yet in prod) - behavioral = class A+B; caps are the plan's starting guesses",
         "%-24s %4s %4s %4s | %5s %4s %-5s | %9s %9s | %s" % ("repo", "A", "B", "C", "behav", "cap", "state", "median_h", "oldest_h", "unattr/unknown")]
    for n, r in rep["repos"].items():
        L.append("%-24s %4d %4d %4d | %5d %4d %-5s | %9s %9s | %d/%d" % (n, r["by_class"]["A"], r["by_class"]["B"], r["by_class"]["C"], r["behavioral"], r["cap"], r["state"],
                                                                    r["median_age_h"], r["oldest_age_h"], r["unattributed"], r["unknown"]))
    g = rep["global"]
    L.append("global: %d / %d %s" % (g["count"], g["cap"], g["state"]))
    for k, a in rep["areas"].items():
        L.append("class A area %s: %d / %d %s" % (k, a["count"], a["cap"], a["state"]))
    return "\n".join(L)


def main(argv):
    cmd = argv[0] if argv else "run"
    rest = argv[1:]
    try:
        if cmd == "run":
            print(json.dumps(cmd_run(rest), sort_keys=True))
        elif cmd == "report":
            m = mode()
            if m == "off":
                print("wip_cap: OVN_QA_WIP_CAP=off")
                return 0
            rep = run_compute(time.time(), int(p5.opt(rest, "--days", "30") or 30))
            print(json.dumps(rep, indent=1, sort_keys=True) if "--json" in rest else render(rep))
        elif cmd == "eligible":
            repo = p5.opt(rest, "--repo")
            m = mode()
            if m == "off" or not ql.safe_name(repo):
                print(json.dumps({"eligible": True, "mode": m, "reason": "off or bad repo"}))
                print("ELIGIBLE")
                return 0
            ov = os.path.exists(os.path.join(qc.state_dir(), "wip_cap_override_" + repo))
            res = eligibility(run_compute(time.time(), 30), repo, p5.opt(rest, "--class", "B"), p5.opt(rest, "--area"), m, ov)
            print(json.dumps(res, sort_keys=True))
            print("ELIGIBLE" if res["eligible"] else "HOLD")
        else:
            print(__doc__)
    except Exception as ex:  # noqa: BLE001 - an observer never fails its caller
        print(json.dumps({"error": "%s: %s" % (type(ex).__name__, str(ex)[:200]), "mode": mode()}))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
