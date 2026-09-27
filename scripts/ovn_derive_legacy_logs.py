#!/usr/bin/env python3
"""ovn_derive_legacy_logs.py — Phase 5 Step 1 (pipeline-hardening plan): strangler-fig
derivation of task_stats.log/cycle_summary.log FROM outcomes.jsonl.

WHY: 4 independent logs (task_stats.log, cycle_summary.log, outcomes.jsonl, alerts.log)
are written by 13+ different scripts, none of which treats any other as a source of
truth. outcomes.jsonl is already the most complete (tier, class, status, fail_reason,
tokens) - task_stats.log and cycle_summary.log are near-strict subsets of what it
already records, just reached via a much more convoluted, cross-script path (confirmed
by reading it: cycle_notify.sh's task_stats.log writer doesn't even use outcomes.jsonl -
it re-parses cycle_summary.log's OWN most recent line for this task id, which is itself
written by a completely separate run_overnight.sh code path using yet another set of
local variables).

THIS SCRIPT DOES NOT REPLACE OR MODIFY THE EXISTING WRITERS. Per the plan's own
"strangler fig, no rip-and-replace" instruction: run this ALONGSIDE the legacy writers,
diff the derived output against the real logs for several days, and only once they
track closely enough do the actual reader migration (ovn_stats.py first, then
cycle_notify.sh/digest_notify.sh) happen - as separate, later steps.

KNOWN, DOCUMENTED LOSSY FIELDS (found while building this, not swept under the rug):
  - outcomes.jsonl's "status" string IS the exact same field cycle_notify.sh's outcome-
    code case-statement already switches on - that mapping is ported here VERBATIM
    (see _outcome_code below) and should match the real logs with high fidelity, not
    just approximately.
  - The {lang·type·tier·verif} tag in the legacy logs has 4 independent axes computed
    by ovn_classify.py from the item's raw TEXT (a regex-classified "type" like
    validation/security/perf/docs/etc) - outcomes.jsonl only stores a single "category"
    field and "tier", not the original item text, so the derived tag can only
    approximate 2 of the 4 axes (category stands in for both lang and type; tier is
    exact). This is a REAL, inherent gap in what outcomes.jsonl records, not a bug in
    this script - flagging it plainly rather than faking precision.
  - outcomes.jsonl does not store the target file path at all (only a one-way
    item_hash) - the derived file field is always "?", which is ALSO already a
    legitimate real value in the existing logs (used whenever the higher-tier stage
    flow doesn't know the file), so this isn't as big a functional gap as it sounds.
  - cycle_summary.log's planfiles=[...] and verdict= are similarly not reconstructable
    (outcomes.jsonl records the OUTCOME of an attempt, not the scout's pre-attempt
    plan) - derived as verdict=PROCEED (every outcomes.jsonl record implies an attempt
    was made) and planfiles=[] (empty, honestly, not fabricated).

Usage: ovn_derive_legacy_logs.py [state_dir]  (defaults to ./state relative to cwd)
Incremental: tracks a byte-offset cursor (state/.derive_legacy_logs.cursor) so re-runs
only process NEW outcomes.jsonl records since the last run - safe to run frequently
(cron) without reprocessing the whole file every time.
"""
import json
import os
import sys
from datetime import datetime, timezone

STATE_DIR = sys.argv[1] if len(sys.argv) > 1 else "state"
OUTCOMES = os.path.join(STATE_DIR, "outcomes.jsonl")
CURSOR = os.path.join(STATE_DIR, ".derive_legacy_logs.cursor")
TASK_STATS_OUT = os.path.join(STATE_DIR, "task_stats.derived.log")
CYCLE_SUMMARY_OUT = os.path.join(STATE_DIR, "cycle_summary.derived.log")


def _outcome_code(status):
    """Ported VERBATIM from cycle_notify.sh's case statement (same source field -
    outcomes.jsonl's "status" IS the string that script switches on). Order matters:
    bash case patterns are first-match, replicated here as an ordered if/elif chain."""
    s = status or ""
    if "tests:pass" in s:
        return "pass"
    if "tests:FAIL" in s:
        return "fail"
    if s.startswith("reverted") or "build-gate" in s:
        return "revert"
    if s.startswith("error"):
        return "error"
    if "ALREADY-DONE" in s:
        return "noop:done"
    if "BLOCKED" in s or "NEEDS-DECISION" in s:
        return "noop:blocked"
    if s.startswith("no-op") and "revert" in s:
        return "noop:gate"
    if s.startswith("no-op"):
        return "noop:flail"
    return "skip"


def _epoch(ts):
    try:
        return int(datetime.fromisoformat(ts.replace("Z", "+00:00")).timestamp())
    except Exception:
        return 0


def _hms(ts):
    try:
        return datetime.fromisoformat(ts.replace("Z", "+00:00")).strftime("%H:%M:%S")
    except Exception:
        return "00:00:00"


def derive_task_stats_line(rec):
    epoch = _epoch(rec.get("ts", ""))
    repo = rec.get("repo", "?")
    oc = _outcome_code(rec.get("status", ""))
    category = rec.get("category") or "other"
    tier = rec.get("tier") or "?"
    # Approximation, documented above: category stands in for BOTH the lang and type
    # axes (outcomes.jsonl doesn't separately record ovn_classify.py's regex-derived
    # "type"); verif is not derivable at all here, always "?".
    tag = "{%s·%s·T%s·?}" % (category, category, tier)
    file_field = "?"  # outcomes.jsonl never records the target file path
    return "%d\t%s\t%s\t%s\t%s" % (epoch, repo, oc, tag, file_field)


def derive_cycle_summary_line(rec):
    hms = _hms(rec.get("ts", ""))
    task_id = rec.get("id", "?")
    category = rec.get("category") or "other"
    tier = rec.get("tier") or "?"
    tag = "{%s·%s·T%s·?}" % (category, category, tier)
    return "%s %s verdict=PROCEED planfiles=[] top_item=? class=%s" % (hms, task_id, tag)


def main():
    if not os.path.exists(OUTCOMES):
        return 0
    start_offset = 0
    if os.path.exists(CURSOR):
        try:
            with open(CURSOR) as f:
                start_offset = int(f.read().strip() or "0")
        except Exception:
            start_offset = 0

    n = 0
    with open(OUTCOMES, "rb") as f:
        f.seek(0, os.SEEK_END)
        end_offset = f.tell()
        if start_offset > end_offset:
            start_offset = 0  # file was rotated/truncated - restart from the top
        f.seek(start_offset)
        with open(TASK_STATS_OUT, "a") as ts_out, open(CYCLE_SUMMARY_OUT, "a") as cs_out:
            for raw in f:
                line = raw.decode("utf-8", errors="replace").strip()
                if not line:
                    continue
                try:
                    rec = json.loads(line)
                except Exception:
                    continue
                ts_out.write(derive_task_stats_line(rec) + "\n")
                cs_out.write(derive_cycle_summary_line(rec) + "\n")
                n += 1
        end_offset = f.tell()

    with open(CURSOR, "w") as f:
        f.write(str(end_offset))

    if n:
        print("derived %d new record(s) into task_stats.derived.log + cycle_summary.derived.log" % n)
    return 0


if __name__ == "__main__":
    sys.exit(main())
