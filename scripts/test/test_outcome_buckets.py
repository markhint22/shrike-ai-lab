#!/usr/bin/env python3
"""Regression tests for scripts/ovn_outcome_buckets.py — the single canonical GOOD/
BAD/BENIGN pass-rate classifier shared by fleet_stats.py, scripts/ovn_stats.py,
scripts/ovn_tier_stats.py, and ovn_godot_report.sh (2026-09-28 metrics-integrity fix).
Run: python3 test_outcome_buckets.py (exit 0 = all pass). No pytest dependency.

Before this fix, those four scripts each computed a differently-wrong "pass rate" over
the same underlying fleet activity: the official dashboard (fleet_stats.py) excluded
noop:gate/noop:flail from the denominator entirely (~91% over a real 7d window),
scripts/ovn_tier_stats.py (feeding the hourly/3-hourly push notifications) wrongly
counted benign noop:done/noop:blocked/error as failures (~45-58%), and
ovn_godot_report.sh kept everything in the denominator (harshest of the four). The
honest, canonical number over the same window is ~50%. This file locks down the
definition so those four can never silently drift apart again:
    GOOD   (numerator)                    : pass
    BAD    (failure, in the denominator)  : revert, noop:gate, noop:flail
    BENIGN (excluded from both, tracked
            separately as a side-metric)  : noop:done, noop:blocked, skip, error
    pass_rate = GOOD / (GOOD + BAD)
"""
import os, sys

ROOT = os.environ.get("OVN_ROOT", os.path.expanduser("~/overnight-queue"))
sys.path.insert(0, os.path.join(ROOT, "scripts"))

P = F = 0
def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
    else:
        F += 1
        print("  FAIL: %s  %s" % (name, extra))


def test_all_eight_oc_values_bucket_correctly(m):
    # the canonical 8-value oc vocabulary written by cycle_notify.sh to state/task_stats.log
    ok("pass -> good",          m.bucket("pass") == "good")
    ok("revert -> bad",         m.bucket("revert") == "bad")
    ok("noop:gate -> bad (structurally identical to revert)", m.bucket("noop:gate") == "bad")
    ok("noop:flail -> bad (a full attempt that produced zero diff)", m.bucket("noop:flail") == "bad")
    ok("noop:done -> benign",   m.bucket("noop:done") == "benign")
    ok("noop:blocked -> benign", m.bucket("noop:blocked") == "benign")
    ok("skip -> benign",        m.bucket("skip") == "benign")
    ok("error -> benign (infra/API, not a quality signal)", m.bucket("error") == "benign")
    # legacy bare "noop" (pre-dates the noop:* subtype split, real historical data - see
    # scripts/ovn_stats.py's own noop_breakdown() for the same "legacy bare noop -> flail"
    # convention this module mirrors) must still land in BAD, not silently vanish to benign.
    ok("legacy bare noop -> bad (alias for noop:flail)", m.bucket("noop") == "bad")
    # unrecognized/future oc values fail safe to benign (excluded, not penalized) rather
    # than guessing at severity.
    ok("an unrecognized oc value defaults to benign, not bad", m.bucket("some-future-value") == "benign")
    ok("an unrecognized oc value defaults to benign, not good", m.bucket("some-future-value") != "good")


def test_pass_rate_computes_correctly_on_a_synthetic_dataset(m):
    # 2 good, 2 bad (1 revert + 1 gate + 0 flail... let's be explicit), 3 benign
    buckets = ["good", "good", "bad", "bad", "benign", "benign", "benign"]
    ok("pass_rate = 2/(2+2) = 50.0%", m.pass_rate(buckets) == 50.0, m.pass_rate(buckets))

    # all good, no bad -> 100%
    ok("all-good buckets -> 100.0%", m.pass_rate(["good", "good", "good"]) == 100.0)

    # all bad, no good -> 0%
    ok("all-bad buckets -> 0.0%", m.pass_rate(["bad", "bad"]) == 0.0)

    # only benign (no good-or-bad attempts at all) -> None, not a ZeroDivisionError or a
    # misleading 0%/100%
    ok("only-benign buckets -> None (nothing attempted, not a fake rate)",
       m.pass_rate(["benign", "benign"]) is None)
    ok("empty input -> None, does not raise", m.pass_rate([]) is None)

    # the real ~50% fleet-wide finding this fix was built around, expressed as oc rows
    rows = (
        [{"oc": "pass"}] * 1095
        + [{"oc": "revert"}] * 103
        + [{"oc": "noop:gate"}] * 245
        + [{"oc": "noop:flail"}] * 740
        + [{"oc": "noop:done"}] * 175
        + [{"oc": "noop:blocked"}] * 28
        + [{"oc": "skip"}] * 33
        + [{"oc": "error"}] * 26
    )
    rate = m.oc_pass_rate(rows)
    ok("real 7d fleet-wide fixture recomputes to ~50% (was 91% dashboard / 45-58% ntfy)",
       49.0 <= rate <= 51.0, rate)


def test_bad_and_benign_counts_are_both_surfaced(m):
    rows = (
        [{"oc": "pass"}] * 4
        + [{"oc": "revert"}] * 2
        + [{"oc": "noop:gate"}] * 3
        + [{"oc": "noop:flail"}] * 1
        + [{"oc": "noop:done"}] * 5
        + [{"oc": "noop:blocked"}] * 2
        + [{"oc": "skip"}] * 6
        + [{"oc": "error"}] * 1
    )
    s = m.summarize(rows)
    ok("summarize: good count", s["good"] == 4, s)
    ok("summarize: bad count (2 revert + 3 gate + 1 flail = 6)", s["bad"] == 6, s)
    ok("summarize: benign count (5 done + 2 blocked + 6 skip + 1 error = 14)", s["benign"] == 14, s)
    ok("summarize: pass_rate = 4/(4+6) = 40.0%", s["pass_rate"] == 40.0, s)
    # the wasted-attempt companion metric: BAD broken out by subtype, so "why is it bad"
    # is visible, not just the headline number
    bb = s["bad_breakdown"]
    ok("bad_breakdown surfaces revert count",     bb.get("revert") == 2, bb)
    ok("bad_breakdown surfaces noop:gate count",  bb.get("noop:gate") == 3, bb)
    ok("bad_breakdown surfaces noop:flail count", bb.get("noop:flail") == 1, bb)
    ok("bad_breakdown excludes benign oc values", "noop:done" not in bb and "skip" not in bb, bb)
    # the "excluded, not counted" companion metric: BENIGN broken out by subtype
    nb = s["benign_breakdown"]
    ok("benign_breakdown surfaces noop:done count",    nb.get("noop:done") == 5, nb)
    ok("benign_breakdown surfaces noop:blocked count", nb.get("noop:blocked") == 2, nb)
    ok("benign_breakdown surfaces skip count",         nb.get("skip") == 6, nb)
    ok("benign_breakdown surfaces error count",        nb.get("error") == 1, nb)
    ok("benign_breakdown excludes bad oc values", "revert" not in nb and "noop:gate" not in nb, nb)

    # standalone oc_bad_breakdown()/oc_benign_breakdown() helpers agree with summarize()'s
    ok("oc_bad_breakdown() standalone matches summarize()'s bad_breakdown",
       m.oc_bad_breakdown(rows) == bb)
    ok("oc_benign_breakdown() standalone matches summarize()'s benign_breakdown",
       m.oc_benign_breakdown(rows) == nb)


def test_oc_field_accepts_bare_strings_or_dicts(m):
    # both task_stats.log-style dict rows and bare oc strings must work identically -
    # fleet_stats.py/ovn_stats.py use dict rows; tests/ad-hoc callers may pass bare strings.
    ok("bucket() on a bare string", m.bucket("pass") == "good")
    ok("oc_pass_rate() on dict rows",   m.oc_pass_rate([{"oc": "pass"}, {"oc": "revert"}]) == 50.0)
    ok("oc_pass_rate() on bare-string rows", m.oc_pass_rate(["pass", "revert"]) == 50.0)
    # a custom oc_field name (defensive - not used in production today, but the helpers
    # accept it) must be honored
    ok("oc_pass_rate() honors a custom oc_field name",
       m.oc_pass_rate([{"outcome": "pass"}, {"outcome": "revert"}], oc_field="outcome") == 50.0)


def test_severity_based_bucket_for_outcomes_jsonl(m):
    # state/outcomes.jsonl carries no `oc` field - it has run_overnight.sh's own `severity`
    # axis (good/bad/neutral/expected/fixable/None), which lines up 1:1 with GOOD/BAD/BENIGN
    # once the 2026-09-28 ALREADY-DONE fix landed (see run_overnight.sh's record_outcome()).
    ok("severity=good -> good",     m.bucket_from_severity("good") == "good")
    ok("severity=bad -> bad",       m.bucket_from_severity("bad") == "bad")
    ok("severity=neutral -> benign", m.bucket_from_severity("neutral") == "benign")
    ok("severity=expected -> benign", m.bucket_from_severity("expected") == "benign")
    ok("severity=fixable -> benign", m.bucket_from_severity("fixable") == "benign")
    ok("severity=None -> benign",   m.bucket_from_severity(None) == "benign")

    # bucket_from_outcome_row(): prefers severity when present...
    ok("row with severity=bad -> bad regardless of class",
       m.bucket_from_outcome_row({"severity": "bad", "class": "landed"}) == "bad")
    # ...but falls back to class+status for older rows written before severity existed
    # (a real, non-trivial slice of history - ~628 rows fleet-wide as of 2026-09-28), so
    # historical/legacy rows and pre-severity test fixtures still classify sensibly.
    ok("no severity, class=landed -> good (fallback)",
       m.bucket_from_outcome_row({"class": "landed"}) == "good")
    ok("no severity, class=reverted -> bad (fallback)",
       m.bucket_from_outcome_row({"class": "reverted"}) == "bad")
    ok("no severity, class=noop, status=no-op(ALREADY-DONE) -> benign (fallback)",
       m.bucket_from_outcome_row({"class": "noop", "status": "no-op(ALREADY-DONE)"}) == "benign")
    ok("no severity, class=noop, status=no-op(BLOCKED) -> benign (fallback)",
       m.bucket_from_outcome_row({"class": "noop", "status": "no-op(BLOCKED)"}) == "benign")
    ok("no severity, class=noop, status=no-op(NEEDS-DECISION) -> benign (fallback)",
       m.bucket_from_outcome_row({"class": "noop", "status": "no-op(NEEDS-DECISION)"}) == "benign")
    ok("no severity, class=noop, bare no-op status -> bad (fallback, a real flailed attempt)",
       m.bucket_from_outcome_row({"class": "noop", "status": "no-op"}) == "bad")
    ok("no severity, class=noop, gate-reverted status -> bad (fallback)",
       m.bucket_from_outcome_row({"class": "noop", "status": "no-op(reverted-red)"}) == "bad")
    ok("no severity, class=skipped -> benign (fallback)",
       m.bucket_from_outcome_row({"class": "skipped"}) == "benign")
    ok("no severity, class=error -> benign (fallback)",
       m.bucket_from_outcome_row({"class": "error"}) == "benign")


if __name__ == "__main__":
    try:
        import ovn_outcome_buckets as m
    except ImportError as e:
        print("  SKIP: scripts/ovn_outcome_buckets.py not importable on this host (%s)" % e)
        print("outcome_buckets: 0 passed, 0 failed")
        sys.exit(0)
    for t in (test_all_eight_oc_values_bucket_correctly,
              test_pass_rate_computes_correctly_on_a_synthetic_dataset,
              test_bad_and_benign_counts_are_both_surfaced,
              test_oc_field_accepts_bare_strings_or_dicts,
              test_severity_based_bucket_for_outcomes_jsonl):
        print("== %s ==" % t.__name__)
        t(m)
    print("\noutcome_buckets: %d passed, %d failed" % (P, F))
    sys.exit(1 if F else 0)
