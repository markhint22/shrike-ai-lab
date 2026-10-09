#!/usr/bin/env python3
"""ovn_outcome_buckets.py — the ONE canonical GOOD/BAD/BENIGN classification for
overnight-queue outcome events, shared by every script that computes a "pass rate".

2026-09-28 metrics-integrity fix: four different places (fleet_stats.py,
scripts/ovn_stats.py, scripts/ovn_tier_stats.py, ovn_godot_report.sh) were each
computing their own "pass rate" with a different, disagreeing definition of what
counts as a failure. Fleet-wide over the same 7-day window: the official dashboard
said ~91%, the hourly/3-hourly push notifications said ~45-58%, and the honest
recomputed number is ~50%. All four now import (or, for the bash script, embed via
its existing Python heredoc) this module instead of re-deriving the split locally.

The bug in one sentence: `noop:gate` ("no-op(reverted-red)" in outcomes.jsonl) is a
*reverted* outcome — the model wrote real code, it built, tests went red, one bounded
fix-up attempt still failed, and it was rolled back — structurally identical to plain
`revert`, just spelled with a `noop:` prefix. Every consumer that did `oc == "revert"`
(or `class == "reverted"`) to find failures silently dropped this bucket, along with
`noop:flail` (a full implement pass that produced zero diff — real tokens, zero
output). Meanwhile the opposite bug existed too: consumers that did
"everything except skip/pass is bad" wrongly penalized `noop:done` / `noop:blocked`
(read-only scout verdicts that never touched code) as if they were failures.

Canonical definition:
    GOOD   (numerator)                    : pass
    BAD    (failure, in the denominator)  : revert, noop:gate, noop:flail
    BENIGN (excluded from both, tracked
            separately as a side-metric)  : noop:done, noop:blocked, skip, error

    pass_rate = GOOD / (GOOD + BAD)

Two data sources feed this, with two matching entry points:
  - state/task_stats.log (cycle_notify.sh) carries an explicit `oc` column with
    exactly the 8 values above (plus a legacy bare "noop", pre-dating the noop:*
    subtype split — see BAD's docstring below). Use bucket()/oc_pass_rate().
  - state/outcomes.jsonl (run_overnight.sh's record_outcome()) has no `oc` field,
    but its own `severity` axis (good/bad/neutral/expected/fixable/None) already
    asks the same "is this actually a problem?" question and — once record_outcome()
    correctly maps ALREADY-DONE to sev=neutral, matching BLOCKED/NEEDS-DECISION
    (fixed 2026-09-28) — lines up 1:1 with GOOD/BAD/BENIGN. Use
    bucket_from_severity().
"""

GOOD = frozenset({"pass"})

# noop:gate and noop:flail are STRUCTURALLY IDENTICAL to revert: the model wrote
# real code / burned a full implement pass, spent real tokens, and it was thrown
# away. Bare "noop" (no colon) is a legacy alias for noop:flail from before the
# noop:* subtype split existed — scripts/ovn_stats.py's own noop_breakdown() already
# treats it the same way ("legacy bare 'noop' -> flail"); kept here so every
# consumer agrees on it instead of each re-deriving the same convention.
BAD = frozenset({"revert", "noop:gate", "noop:flail", "noop"})

# Scout-only verdicts that never attempted an implementation (noop:done,
# noop:blocked), an idle repo with nothing doable (skip), and infra/API errors
# that aren't a quality signal about the attempt itself (error) — same philosophy
# as excluding lock-contention flakes from real failure counts elsewhere in this
# pipeline.
BENIGN = frozenset({"noop:done", "noop:blocked", "skip", "error"})


# 2026-10-09 (harness-credit-integrity item 4): record_outcome() writes class "landed-uncredited" (severity neutral) for a green push whose item the
# auto-credit refused to tick. It is its OWN bucket: neither a landing nor a failure, so it is excluded from good, bad and the pass rate, and reports
# show it as "N uncredited pushes". Every reader that counts `class == "landed"` already excludes it; use is_uncredited()/count_uncredited() to report it.
UNCREDITED_CLASS = "landed-uncredited"


def is_uncredited(row):
    """True for a state/outcomes.jsonl row recorded as a green push that was not credited."""
    return isinstance(row, dict) and row.get("class") == UNCREDITED_CLASS


def count_uncredited(rows):
    """Number of landed-uncredited rows in an iterable of outcomes.jsonl rows."""
    return sum(1 for r in rows if is_uncredited(r))


def uncredited_label(n):
    """'N uncredited pushes' (singular for 1), or '' when there are none - the one phrase every report uses."""
    return "" if not n else "%d uncredited push%s" % (n, "" if n == 1 else "es")


def bucket(oc):
    """state/task_stats.log's `oc` column -> "good" | "bad" | "benign".

    Unrecognized/future oc values fail safe to "benign" (excluded, not counted as
    a failure) rather than guessing at their severity.
    """
    if oc in GOOD:
        return "good"
    if oc in BAD:
        return "bad"
    return "benign"


def bucket_from_severity(severity):
    """state/outcomes.jsonl's `severity` field -> "good" | "bad" | "benign".

    severity is run_overnight.sh's own "is this actually a problem?" axis
    (good/bad/neutral/expected/fixable/None) and already matches this module's
    three buckets 1:1 once record_outcome()'s ALREADY-DONE case maps to
    sev=neutral (fixed 2026-09-28, see run_overnight.sh). NOTE: rows written
    before that fix landed may still carry a stale sev=bad for what was actually
    a benign already-satisfied scout verdict; this self-heals as that historical
    tail ages out of whatever window a caller is reporting over.
    """
    if severity == "good":
        return "good"
    if severity == "bad":
        return "bad"
    return "benign"


def bucket_from_outcome_row(row):
    """A full state/outcomes.jsonl row (dict) -> "good" | "bad" | "benign".

    Prefers the explicit `severity` field (bucket_from_severity()). For older
    rows written before severity existed (missing/None - a real, non-trivial
    slice of history: ~628 rows fleet-wide as of 2026-09-28), falls back to
    inferring from `class` + `status`, using the same NO-NEW-RED GUARD
    status-pattern convention already established elsewhere in this pipeline
    (see ovn_tier_stats.py's hidden_reverts / no-op(reverted-red) handling) to
    tell a genuine scout-only verdict (no-op(ALREADY-DONE)/no-op(BLOCKED)/
    no-op(NEEDS-DECISION)) apart from a real thrown-away attempt (bare no-op,
    no-op(reverted-red), no-op(stage-unverified)).
    """
    # 2026-10-03 (integrity A6): a cycle that died on ContextWindowExceededError produced nothing and burned a full model call: BAD, whatever its
    # status/severity said (it was recorded as error(...) = benign, which hid the overflow cycles from the pass rate).
    if row.get("fail_reason") == "context-exceeded" and row.get("class") != "landed":
        return "bad"
    if row.get("class") == UNCREDITED_CLASS:   # its own bucket (see is_uncredited): never a win, never a failure, whatever the severity field says
        return "benign"
    severity = row.get("severity")
    if severity is not None:
        return bucket_from_severity(severity)
    cls = row.get("class")
    if cls == "landed":
        return "good"
    if cls == "reverted":
        return "bad"
    if cls == "noop":
        status = str(row.get("status") or "").lower()
        if "already-done" in status or "blocked" in status or "needs-decision" in status or "needs_decision" in status or "scout-unworkable" in status or "ungrounded-plan" in status:
            return "benign"
        return "bad"  # bare no-op / gate-reverted / stage-unverified - a real thrown-away attempt
    return "benign"  # skipped, error, oversized, unknown, held, or an unrecognized class


def counts(buckets):
    """[bucket_label, ...] -> {"good": n, "bad": n, "benign": n}."""
    out = {"good": 0, "bad": 0, "benign": 0}
    for b in buckets:
        out[b] = out.get(b, 0) + 1
    return out


def pass_rate(buckets):
    """[bucket_label, ...] -> rounded % good-of-(good+bad), or None if there were
    no good-or-bad attempts in the window (all benign, or no data at all)."""
    c = counts(buckets)
    denom = c["good"] + c["bad"]
    if denom == 0:
        return None
    return round(100.0 * c["good"] / denom, 1)


def _oc_of(row, oc_field):
    return row[oc_field] if isinstance(row, dict) else row


def oc_pass_rate(rows, oc_field="oc"):
    """Convenience wrapper over task_stats.log-style rows (dicts with an `oc` key,
    or bare oc strings) -> canonical pass_rate()."""
    return pass_rate([bucket(_oc_of(r, oc_field)) for r in rows])


def oc_bad_breakdown(rows, oc_field="oc"):
    """{oc_value: count} restricted to the BAD subtypes — the wasted-attempt
    companion metric: how many of the "bad" bucket were plain reverts vs
    gate-reverted (noop:gate) vs flailed (noop:flail / legacy bare noop)."""
    out = {}
    for r in rows:
        oc = _oc_of(r, oc_field)
        if oc in BAD:
            out[oc] = out.get(oc, 0) + 1
    return out


def oc_benign_breakdown(rows, oc_field="oc"):
    """{oc_value: count} restricted to the BENIGN subtypes — the "excluded, not
    counted" companion metric, so it's visible these aren't being swept under
    the rug, just correctly not penalizing the score."""
    out = {}
    for r in rows:
        oc = _oc_of(r, oc_field)
        if oc in BENIGN:
            out[oc] = out.get(oc, 0) + 1
    return out


def summarize(rows, oc_field="oc"):
    """One-stop summary over task_stats.log-style rows: good/bad/benign counts,
    the canonical pass_rate, and both breakdowns. Used by fleet_stats.py so it
    only has to walk `rows` once per repo."""
    bkts = [bucket(_oc_of(r, oc_field)) for r in rows]
    c = counts(bkts)
    return {
        "good": c["good"],
        "bad": c["bad"],
        "benign": c["benign"],
        "pass_rate": pass_rate(bkts),
        "bad_breakdown": oc_bad_breakdown(rows, oc_field),
        "benign_breakdown": oc_benign_breakdown(rows, oc_field),
    }


def row_attempts(row):
    """Model attempts behind ONE state/outcomes.jsonl row (2026-10-02).

    A row is one finished item/cycle, but best-of-N runs several inner attempts inside it (iptv 'add last_event_ms column': 5 attempts, one row), so
    counting rows undercounts real model work. run_overnight.sh now writes an explicit `attempts` field (older rows only have `attempt`, same value);
    anything missing/garbled counts as 1. Use this wherever a dashboard reports "attempts" rather than "rows"."""
    for k in ("attempts", "attempt"):
        try:
            v = int(row.get(k))
            if v >= 1:
                return v
        except (TypeError, ValueError, AttributeError):
            continue
    return 1


def total_attempts(rows):
    """Sum of row_attempts() over outcome rows."""
    return sum(row_attempts(r) for r in rows)
