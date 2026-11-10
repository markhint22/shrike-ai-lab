#!/usr/bin/env python3
"""ovn_timeout_park_precision.py - Z7-C (2026-11-09): how good would OVN_STAGE_TIMEOUT_PARK=on be? Read-only, stdlib only (same idea as ovn_bb_park_precision.py).

REPLAY of the stage runner's rule over the journals (state/stage_runs/<repo>-<run>.jsonl): every step attempt row with fail_reason == "timeout" is counted per (repo, item text, declared file set);
the Nth (N >= --at, default 2) timeout of the same key is a WOULD-PARK EVENT (what stage_timeout_track decides; it counts across attempts, re-decompositions and cycles). The replay also covers runs from
before the shadow rule existed, so n is bigger than the `would_park_timeout` rows alone.

An event is a FALSE PARK when parking would have cost something the lane then achieved on its own: a LATER attempt on the SAME declared file set (same item) passed (verdict == pass; step level, the
decision the rule actually makes), or a later stage run of the same repo + item text pushed commits (item level). `--outcomes` adds the weaker proxy "a later outcomes row of the same item_hash landed" (item_hash is FEATURE level, so a sibling item can make it a false alarm: reported separately, never
used for the precision figure unless --proxy-outcomes). Precision = never-landed events (distinct ITEMS, first event each) / items. The flip rule: >= 80%.

  ovn_timeout_park_precision.py --state state [--days 7] [--at 2] [--outcomes] [--proxy-outcomes]   -> one JSON object on stdout
"""
import argparse
import collections
import datetime
import glob
import hashlib
import json
import os
import re
import sys

_RUN_RE = re.compile(r"(\d{8})-(\d{6})")


def _run_ts(run):
    m = _RUN_RE.search(run or "")
    if not m:
        return None
    return datetime.datetime.strptime(m.group(1) + m.group(2), "%Y%m%d%H%M%S")


def _ihash(item):
    return hashlib.md5((re.sub(r"\s+", " ", item or "").strip()).encode("utf-8", "replace")).hexdigest()[:8]


def load_runs(state):
    runs = []
    for p in glob.glob(os.path.join(state, "stage_runs", "*.jsonl")):
        if p.endswith(".verify.jsonl"):
            continue
        rows = []
        try:
            with open(p, encoding="utf-8", errors="replace") as fh:
                for ln in fh:
                    try:
                        rows.append(json.loads(ln))
                    except ValueError:
                        pass
        except OSError:
            continue
        if not rows:
            continue
        run = next((r.get("run") for r in rows if r.get("run")), None)
        ts = _run_ts(run)
        if ts is None:
            continue
        dec = next((r for r in rows if r.get("event") == "decomposed"), {})
        summ = next((r for r in rows if r.get("event") == "summary"), {})
        repo = dec.get("repo") or os.path.basename(p).split("-")[0]
        steps = [r for r in rows if r.get("event") is None and "attempt" in r]
        runs.append({"run": run, "ts": ts, "repo": repo, "item": dec.get("item", ""), "steps": steps,
                     "landed": int(summ.get("commits_pushed") or 0) > 0 or int(summ.get("passed") or 0) > 0 and int(summ.get("commits_pushed") or 0) > 0})
    runs.sort(key=lambda r: r["ts"])
    return runs


def load_outcomes(path):
    rows = []
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            for ln in fh:
                try:
                    r = json.loads(ln)
                except ValueError:
                    continue
                if r.get("ts") and r.get("item_hash"):
                    rows.append(r)
    except OSError:
        pass
    return rows


def analyse(runs, days=7, at=2, outcomes=None, proxy_outcomes=False, now=None):
    now = now or (runs[-1]["ts"] if runs else datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None))
    lo = now - datetime.timedelta(days=days)
    cnt = collections.Counter()
    passes = collections.defaultdict(list)   # key -> [seq] of later PASSING attempts on the same file set
    events = []     # (run, key, n, seq)
    seq = 0
    for r in runs:
        for s in r["steps"]:
            seq += 1
            files = sorted(set(f for f in re.split(r"[|\s,]+", s.get("files") or "") if f)) or ["(no-files)"]
            k = (r["repo"], _ihash(r["item"]), "|".join(files))
            if s.get("verdict") == "pass":
                passes[k].append(seq)
            if s.get("fail_reason") != "timeout":
                continue
            cnt[k] += 1
            if cnt[k] >= at and r["ts"] >= lo:
                events.append((r, k, cnt[k], seq))
    items = collections.OrderedDict()
    for r, k, n, sq in events:
        d = items.setdefault((k[0], k[1]), {"_seq": sq, "_key": k, "repo": k[0], "item_hash": k[1], "item": (r["item"] or "")[:110], "first_event": r["ts"].strftime("%Y-%m-%dT%H:%M:%SZ"), "events": 0, "max_count": 0, "files": k[2], "later_pass_same_files": False, "landed_later_stage": False, "landed_later_outcome": False, "_t": r["ts"]})
        d["events"] += 1
        d["max_count"] = max(d["max_count"], n)
    for (repo, h), d in items.items():
        d["later_pass_same_files"] = any(x > d["_seq"] for x in passes.get(d["_key"], []))
        d["landed_later_stage"] = any(x["ts"] > d["_t"] and x["repo"] == repo and _ihash(x["item"]) == h and x["landed"] for x in runs)
    # outcomes proxy is keyed on the feature-level item_hash: resolve it through the journal's own outcome rows when --outcomes is given
    if outcomes:
        by_feat = collections.defaultdict(list)
        for o in outcomes:
            by_feat[(o.get("repo"), o.get("feat_tag") or o.get("item_hash"))].append(o)
        for (repo, h), d in items.items():
            m = re.search(r"\[feat:([^\]]+)\]", d["item"])
            fk = (repo, m.group(1)[:48]) if m else None
            for (orepo, ofeat), rows in by_feat.items():
                if orepo == repo and fk and str(ofeat)[:48] == fk[1]:
                    d["landed_later_outcome"] = d["landed_later_outcome"] or any(str(o.get("class", "")).startswith("landed") and o["ts"] > d["first_event"] for o in rows)
    out = []
    false = 0
    for d in items.values():
        d.pop("_t", None); d.pop("_seq", None); d.pop("_key", None)
        landed = d["later_pass_same_files"] or d["landed_later_stage"] or (proxy_outcomes and d["landed_later_outcome"])
        d["false_park"] = bool(landed)
        false += bool(landed)
        out.append(d)
    n = len(out)
    return {"events": len(events), "items": n, "false_parks": false, "precision": (round((n - false) / float(n), 3) if n else None), "detail": out}


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--state", required=True)
    ap.add_argument("--days", type=float, default=7)
    ap.add_argument("--at", type=int, default=2)
    ap.add_argument("--outcomes", action="store_true", help="also report the weaker outcomes.jsonl proxy (feature-level item_hash)")
    ap.add_argument("--proxy-outcomes", action="store_true", help="count the outcomes proxy as a landing in the precision figure")
    a = ap.parse_args(argv)
    runs = load_runs(a.state)
    oc = load_outcomes(os.path.join(a.state, "outcomes.jsonl")) if (a.outcomes or a.proxy_outcomes) else None
    print(json.dumps(analyse(runs, a.days, a.at, oc, a.proxy_outcomes)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
