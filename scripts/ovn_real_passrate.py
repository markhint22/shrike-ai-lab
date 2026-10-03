#!/usr/bin/env python3
"""ovn_real_passrate.py — the HONEST pass rate over state/outcomes.jsonl (2026-10-03).

WHY: the 2026-10-03 diagnosis showed a 43.2% headline pass rate while the post-deploy iptv_apps
lane was 2 of 31, and xlite "landed" rows had no commit behind them at all. The headline
(ovn_outcome_buckets: good / (good + bad)) counts a `landed` row as a win whether or not a
commit exists, and counts a revert caused by an already-red repo as the model's failure.

Three numbers, always shown together so none can hide another:
  headline          what the dashboards say: good / (good + bad), every row counted.
  real              phantom landings removed: a `landed` row whose state/qa_ledger.jsonl entry
                    (joined on repo+ts) has commit_basis "none" (clone found, no commit in the
                    cycle window) is NOT a landing. Excluded from numerator AND denominator and
                    reported as its own count. No ledger row / "no-clone" = cannot tell = kept.
  model-attributable real, minus SUSPECTED pre-existing-red reverts, i.e. bad rows that are not
                    evidence about the model. A bad row is suspected pre-existing-red when it
                    names a baseline/pre-existing failure explicitly, or is part of a run of
                    >= 4 consecutive bad rows in one repo (no good row in between) spanning
                    >= 3 distinct items: one broken repo, not four bad attempts. SUSPECTED only:
                    these stay in `real`'s denominator, and are shown separately.

Optional --since T (epoch | ISO | 'YYYY-MM-DD[ HH:MM]', UTC): splits the window at T and prints
pre vs post per repo (the post-deploy comparison). The headline is flagged NOT HONEST when the
phantoms/baseline noise move it by >= 3 points, or any repo's post-T rate fell >= 15 points.

Pure functions + a CLI:  ovn_real_passrate.py [hours=24] [--since T] [--state DIR]
"""
import json
import os
import re
import sys
import time
from datetime import datetime, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ovn_outcome_buckets import bucket_from_outcome_row  # noqa: E402

STREAK_MIN_ROWS = 4
STREAK_MIN_ITEMS = 3
HEADLINE_GAP_PTS = 3.0
POST_DROP_PTS = 15.0
POST_MIN_ATTEMPTS = 10
_PREEXIST_RE = re.compile(r"pre-?existing|baseline[-_ ]?(red|fail)|already[-_ ]red", re.I)


def parse_since(s):
    """epoch | ISO-8601 | 'YYYY-MM-DD[ HH:MM[:SS]]' (UTC unless an offset is given) -> epoch or None."""
    if s is None:
        return None
    s = str(s).strip()
    try:
        return float(s)
    except ValueError:
        pass
    try:
        dt = datetime.fromisoformat(s.replace("Z", "+00:00").replace(" ", "T"))
    except ValueError:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.timestamp()


def _epoch(ts):
    try:
        return datetime.fromisoformat(str(ts).replace("Z", "+00:00")).timestamp()
    except Exception:
        return 0.0


def load_outcomes(state_dir):
    rows = []
    try:
        with open(os.path.join(state_dir, "outcomes.jsonl"), encoding="utf-8", errors="replace") as f:
            for ln in f:
                try:
                    r = json.loads(ln)
                except Exception:
                    continue  # tolerate the odd malformed row
                if isinstance(r, dict) and r.get("ts"):
                    r["_epoch"] = _epoch(r["ts"])
                    rows.append(r)
    except OSError:
        pass
    return rows


def load_commit_evidence(state_dir):
    """{(repo, ts): True if commits found | False if looked and found none} from qa_ledger.jsonl.
    Rows with no clone/other basis are left out (unknown)."""
    ev = {}
    try:
        with open(os.path.join(state_dir, "qa_ledger.jsonl"), encoding="utf-8", errors="replace") as f:
            for ln in f:
                try:
                    r = json.loads(ln)
                except Exception:
                    continue
                if not isinstance(r, dict) or r.get("kind") != "landed":
                    continue
                basis = r.get("commit_basis")
                # a stage(higher-tier) handoff row legitimately has no commit (the stage runner
                # commits later): only a "pushed..." status asserts a commit should exist
                if not str(r.get("status") or "").startswith("pushed"):
                    continue
                if basis == "none" and not r.get("commits"):
                    ev[(r.get("repo"), r.get("ts"))] = False
                elif r.get("commits"):
                    ev[(r.get("repo"), r.get("ts"))] = True
    except OSError:
        pass
    return ev


def annotate(rows, evidence):
    """Set r['_bucket'], r['_phantom'], r['_preexisting'] on every row (in place)."""
    for r in rows:
        r["_bucket"] = bucket_from_outcome_row(r)
        r["_phantom"] = (r["_bucket"] == "good" and evidence.get((r.get("repo"), r.get("ts"))) is False)
        txt = "%s %s" % (r.get("fail_reason") or "", r.get("status") or "")
        r["_preexisting"] = (r["_bucket"] == "bad" and bool(_PREEXIST_RE.search(txt)))
    # streak heuristic, per repo, over good/bad rows in time order (benign rows do not break a streak)
    by_repo = {}
    for r in sorted(rows, key=lambda x: x["_epoch"]):
        if r["_bucket"] != "benign" and not r["_phantom"]:
            by_repo.setdefault(r.get("repo"), []).append(r)
    for seq in by_repo.values():
        run = []
        for r in seq + [None]:
            if r is not None and r["_bucket"] == "bad":
                run.append(r)
                continue
            items = {x.get("item_hash") for x in run if x.get("item_hash")}
            if len(run) >= STREAK_MIN_ROWS and len(items) >= STREAK_MIN_ITEMS:
                for x in run:
                    x["_preexisting"] = True
            run = []
    return rows


def rates(rows):
    """-> dict(headline, real, attrib (each pct or None), good, bad, phantom, preexisting)."""
    good = sum(1 for r in rows if r["_bucket"] == "good")
    bad = sum(1 for r in rows if r["_bucket"] == "bad")
    ph = sum(1 for r in rows if r["_phantom"])
    pre = sum(1 for r in rows if r["_preexisting"])

    def pct(g, b):
        return round(100.0 * g / (g + b), 1) if (g + b) else None
    return {
        "good": good, "bad": bad, "phantom": ph, "preexisting": pre,
        "headline": pct(good, bad),
        "real": pct(good - ph, bad),
        "attrib": pct(good - ph, bad - pre),
        "real_good": good - ph, "real_den": good - ph + bad,
    }


def _fmt(p):
    return "n/a" if p is None else "%g%%" % p


def build(state_dir, hours=24.0, since=None, now=None):
    now = now if now is not None else time.time()
    rows = load_outcomes(state_dir)
    annotate(rows, load_commit_evidence(state_dir))
    cutoff = now - hours * 3600.0
    win = [r for r in rows if r["_epoch"] >= cutoff]
    tot = rates(win)
    lines, flags = [], []
    lines.append("REAL pass rate, last %gh (outcomes.jsonl, %d rows)" % (hours, len(win)))
    lines.append("  headline %s (%d good / %d good+bad)   real %s (%d / %d, %d phantom landing(s) excluded)   "
                 "model-attributable(SUSPECTED, heuristic) %s" % (_fmt(tot["headline"]), tot["good"], tot["good"] + tot["bad"],
                                           _fmt(tot["real"]), tot["real_good"], tot["real_den"],
                                           tot["phantom"], _fmt(tot["attrib"])))
    if tot["phantom"]:
        lines.append("  landed WITHOUT a commit: %d (counted as wins by the headline, excluded here)" % tot["phantom"])
    if tot["preexisting"]:
        lines.append("  suspected pre-existing-red reverts: %d (kept in real, excluded from the SUSPECTED model-attributable figure; do not use it as a headline until explicit tagging exists)"
                     % tot["preexisting"])
    if tot["headline"] is not None and tot["real"] is not None and tot["headline"] - tot["real"] >= HEADLINE_GAP_PTS:
        flags.append("headline overstates by %.1f pts (%d phantom landings)" % (tot["headline"] - tot["real"], tot["phantom"]))
    result = {"window": tot, "since": None, "per_repo": {}, "flags": flags}
    if since is not None:
        pre_rows = [r for r in win if r["_epoch"] < since]
        post_rows = [r for r in win if r["_epoch"] >= since]
        stamp = time.strftime("%Y-%m-%d %H:%MZ", time.gmtime(since))
        lines.append("  post-deploy comparison, split at %s (real rates, pre -> post):" % stamp)
        repos = sorted({r.get("repo") for r in win if r["_bucket"] != "benign"} - {None})
        for repo in [None] + repos:
            a = rates([r for r in pre_rows if repo is None or r.get("repo") == repo])
            b = rates([r for r in post_rows if repo is None or r.get("repo") == repo])
            if not (a["real_den"] or b["real_den"]):
                continue
            name = "ALL" if repo is None else repo
            lines.append("    %-22s pre %s (%d/%d) -> post %s (%d/%d)" % (
                name, _fmt(a["real"]), a["real_good"], a["real_den"], _fmt(b["real"]), b["real_good"], b["real_den"]))
            result["per_repo"][name] = {"pre": a, "post": b}
            if (repo is not None and a["real"] is not None and b["real"] is not None
                    and b["real_den"] >= POST_MIN_ATTEMPTS and a["real"] - b["real"] >= POST_DROP_PTS):
                flags.append("%s fell %.0f pts after the split (%s -> %s, %d post attempts)" % (
                    repo, a["real"] - b["real"], _fmt(a["real"]), _fmt(b["real"]), b["real_den"]))
        result["since"] = since
    if flags:
        lines.append("  WARNING HEADLINE NOT HONEST: " + "; ".join(flags))
    else:
        lines.append("  headline consistent with the real rate")
    return lines, result


def main(argv):
    hours, since, state = 24.0, None, os.environ.get("OVN_STATE_DIR") or os.path.expanduser("~/overnight-queue/state")
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--since" and i + 1 < len(argv):
            since = parse_since(argv[i + 1]); i += 2
        elif a == "--state" and i + 1 < len(argv):
            state = argv[i + 1]; i += 2
        elif not a.startswith("--"):
            hours = float(a); i += 1
        else:
            i += 1
    print("\n".join(build(state, hours, since)[0]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
