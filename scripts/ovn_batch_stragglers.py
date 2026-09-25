#!/usr/bin/env python3
"""Chronically-F batch straggler finder (2026-09-25).

Companion to ovn_batch_scorecard.py's letter-grade view. The scorecard answers
"how is the research pipeline doing" (a reporting question); this script answers
a narrower, actionable one: "is there still-open, un-attempted work sitting under
a batch that has ALREADY shown a clear failure pattern, that will keep burning
fleet cycles one item at a time until ovn_item_guard.sh's PER-ITEM cap catches
each one individually?"

That gap is real: ovn_item_guard.sh bounds runaway spend on any ONE item (fail
streak, no-op streak, or token cap), but it has no visibility into a sibling
item's outcome — a 30-item batch that's already 80% reverted/no-op after its
first 10 attempts will still let each of its remaining ~20 untried siblings
independently burn through its own guard allowance before being capped, even
though the batch-level signal already predicts they're likely to fail the same
way (same research pass, same probable root cause — bad prompting/scoping/file
grounding for that batch, not each item's individual bad luck).

Trigger (deliberately conservative — this only ever flags, it's ovn_batch_park_
stragglers.sh's job to act, and only on caller confirmation of the SAME evidence
this script already re-derives from outcomes.jsonl):
  - grade F (land rate <25%, same scale as the scorecard)
  - at least MIN_SAMPLE (default 5) outcomes already recorded for the batch —
    a 1-of-3 batch just started badly and deserves more runway before judgment
  - at least min-age-hours (default 24, matching the scorecard's own default)

For each qualifying batch, finds the batch's remaining OPEN items (the literal
"[feat:<tag>]" trailer every batch item carries — confirmed convention, see
ovn_batch_scorecard.py's docstring) in that repo's OVERNIGHT_PROGRESS.md that
are not already AUTO-SKIP/HUMAN-ONLY/BLOCKED tagged, and reports them. This
script never writes anything — see ovn_batch_park_stragglers.sh for the
worktree-isolated, dedup-tracked apply step.

Usage: ovn_batch_stragglers.py [--min-age-hours=24] [--min-sample=5]
Prints one JSON object per qualifying batch, one per line (JSONL), to stdout.
Prints nothing if there are no qualifying batches.
"""
import calendar
import glob
import json
import os
import re
import sys
import time

P = os.path.expanduser("~/overnight-queue/state/outcomes.jsonl")
REPOS_DIR = os.path.expanduser("~/overnight-queue/repos")

min_age_hours = 24.0
min_sample = 5
for a in sys.argv[1:]:
    m = re.match(r'--min-age-hours=([\d.]+)', a)
    if m:
        min_age_hours = float(m.group(1))
    m = re.match(r'--min-sample=(\d+)', a)
    if m:
        min_sample = int(m.group(1))

now = time.time()


def parse_ts(ts):
    try:
        return calendar.timegm(time.strptime(ts, "%Y-%m-%dT%H:%M:%SZ"))
    except Exception:
        return None


batches = {}
try:
    with open(P) as f:
        for line in f:
            try:
                r = json.loads(line)
            except Exception:
                continue
            tag = r.get("feat_tag") or ""
            if not tag:
                continue
            t = parse_ts(r.get("ts", ""))
            if t is None:
                continue
            b = batches.setdefault(tag, {"rows": [], "repo": r.get("repo", "?")})
            b["rows"].append(r)
except FileNotFoundError:
    sys.exit(0)

SKIP_MARK = re.compile(r"AUTO-SKIP|HUMAN-ONLY|BLOCKED", re.I)

for tag, b in sorted(batches.items()):
    rows = b["rows"]
    repo = b["repo"]
    n = len(rows)
    if n < min_sample:
        continue
    first_ts = min(parse_ts(r.get("ts", "")) or now for r in rows)
    age_h = (now - first_ts) / 3600.0
    if age_h < min_age_hours:
        continue
    landed = sum(1 for r in rows if r.get("class") == "landed")
    pct = 100 * landed // n
    if pct >= 25:
        continue  # only grade F triggers a straggler check

    prog = os.path.join(REPOS_DIR, repo, "OVERNIGHT_PROGRESS.md")
    if not os.path.exists(prog):
        continue
    tag_marker = f"[feat:{tag}]"
    stragglers = []
    for ln in open(prog, encoding="utf-8", errors="replace"):
        ln = ln.rstrip("\n")
        if not ln.startswith("- [ ] "):
            continue
        if tag_marker not in ln:
            continue
        if SKIP_MARK.search(ln):
            continue
        stragglers.append(ln[len("- [ ] "):])

    if not stragglers:
        continue

    print(json.dumps({
        "repo": repo,
        "tag": tag,
        "landed": landed,
        "n": n,
        "pct": pct,
        "age_h": round(age_h, 1),
        "straggler_count": len(stragglers),
        "stragglers": stragglers,
    }))
