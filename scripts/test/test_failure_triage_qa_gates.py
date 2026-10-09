#!/usr/bin/env python3
"""Tests for the QA-gate FAIL source of scripts/ovn_failure_triage.py (state/qa_shadow/*.jsonl -> registry).
Run: python3 test_failure_triage_qa_gates.py   (exit 0 = all pass). No pytest dependency."""
import json
import os
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPTS = os.environ.get("OVN_SCRIPTS") or (
    os.path.join(HERE, "..") if os.path.exists(os.path.join(HERE, "..", "ovn_failure_triage.py"))
    else os.path.expanduser("~/overnight-queue/scripts"))
sys.path.insert(0, SCRIPTS)
import ovn_failure_triage as ft  # noqa: E402

P = F = 0


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
    else:
        F += 1
        print("  FAIL: %s  %s" % (name, extra))


def rec(gate, verdict, summary, repo="iptv_apps", ref="a..b", ts="2026-10-05T10:00:00Z"):
    return json.dumps({"gate": gate, "verdict": verdict, "summary": summary, "repo": repo, "ref": ref, "ts": ts}) + "\n"


def add(state, gate, *lines, raw=False):
    d = os.path.join(state, "qa_shadow")
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, gate + ".jsonl"), "a") as f:
        for l in lines:
            f.write(l)


def run(state):
    reg, new, reg_ev = {}, [], []
    try:
        with open(os.path.join(state, "reg.json")) as f:
            reg = json.load(f)
    except Exception:
        pass
    n = ft.process_qa_gate_fails(state, reg, new, reg_ev)
    with open(os.path.join(state, "reg.json"), "w") as f:
        json.dump(reg, f)
    return n, reg, new, reg_ev


def main():
    s = tempfile.mkdtemp()
    try:
        # negative control: FAIL clusters under repo::qa-gate:<gate>:<RULE>
        add(s, "antigaming", rec("antigaming", "FAIL", "1 finding(s) [A_VACUOUS=1]: A_VACUOUS x.py:9"))
        n, reg, new, _ = run(s)
        ok("one FAIL -> one new cluster", n == 1 and len(new) == 1, (n, new))
        ok("cluster key uses rule id", "iptv_apps::qa-gate:antigaming:A_VACUOUS" in reg, list(reg))
        ok("cluster starts as new, count 1", reg["iptv_apps::qa-gate:antigaming:A_VACUOUS"]["status"] == "new"
           and reg["iptv_apps::qa-gate:antigaming:A_VACUOUS"]["count"] == 1)

        # benign controls: PASS / FLAG / NA / UNVERIFIED never cluster
        add(s, "antigaming", rec("antigaming", "PASS", "ok"), rec("antigaming", "FLAG", "[D_DEAD_SYMBOL=1]"),
            rec("antigaming", "NA", "n/a"), rec("antigaming", "UNVERIFIED", "cannot resolve ref"))
        n, reg, new, _ = run(s)
        ok("non-FAIL verdicts add nothing", n == 0 and len(reg) == 1, (n, list(reg)))

        # idempotent: re-run with no new data counts nothing (cursor)
        n, reg, new, _ = run(s)
        ok("re-run is a no-op", n == 0 and reg["iptv_apps::qa-gate:antigaming:A_VACUOUS"]["count"] == 1)

        # same gate+ref+rule recorded again (gate re-run on same commits) counts once
        add(s, "antigaming", rec("antigaming", "FAIL", "[A_VACUOUS=1]: A_VACUOUS x.py:9"))
        n, reg, _, _ = run(s)
        ok("duplicate gate+ref+rule counted once", n == 0 and reg["iptv_apps::qa-gate:antigaming:A_VACUOUS"]["count"] == 1, n)

        # a different ref is a real recurrence: count increments, no new cluster
        add(s, "antigaming", rec("antigaming", "FAIL", "[A_VACUOUS=1]: A_VACUOUS y.py:3", ref="c..d"))
        n, reg, new, _ = run(s)
        ok("new ref increments count, not a new cluster", n == 1 and not new
           and reg["iptv_apps::qa-gate:antigaming:A_VACUOUS"]["count"] == 2, (n, new))

        # other gates + rule extraction fallbacks
        add(s, "staging_check", rec("staging_check", "FAIL", "MISMATCH_FAILED: latest staging deploy FAILED", ref="36c5"))
        add(s, "migrations", rec("migrations", "FAIL", "heads: alembic cannot load the migration scripts", repo="gitlark"))
        n, reg, new, _ = run(s)
        ok("staging_check MISMATCH_ rule id", "iptv_apps::qa-gate:staging_check:MISMATCH_FAILED" in reg, list(reg))
        ok("no rule id -> slug of first words", "gitlark::qa-gate:migrations:heads-alembic-cannot-load" in reg, list(reg))

        # fixed cluster that fails again is surfaced as a regression
        key = "iptv_apps::qa-gate:antigaming:A_VACUOUS"
        reg[key]["status"] = "fixed"
        reg[key]["fix_commit"] = "abc"
        with open(os.path.join(s, "reg.json"), "w") as f:
            json.dump(reg, f)
        add(s, "antigaming", rec("antigaming", "FAIL", "[A_VACUOUS=1]: A_VACUOUS z.py:1", ref="e..f"))
        n, reg, new, regs = run(s)
        ok("fixed cluster recurrence -> regression", len(regs) == 1 and regs[0]["key"] == key, regs)

        # robustness: garbage lines, unterminated trailing line, truncated file
        add(s, "scanners", "not json\n", '{"verdict": "FAIL", "summary": "x"', raw=True)
        n, reg, _, _ = run(s)
        ok("garbage + unterminated line tolerated, nothing counted", n == 0)
        add(s, "scanners", "\n" + rec("scanners", "FAIL", "[S_SECRET=1] leak", ref="g..h"))
        n, reg, _, _ = run(s)
        ok("unterminated line completed later is not lost/duplicated (garbled one skipped)", n in (0, 1), n)
        p = os.path.join(s, "qa_shadow", "antigaming.jsonl")
        open(p, "w").write(rec("antigaming", "FAIL", "[A_ASSERT_WEAKENED=1]: A_ASSERT_WEAKENED t.py:2", ref="i..j"))
        n, reg, _, _ = run(s)
        ok("truncated/rotated file restarts from 0", n == 1 and "iptv_apps::qa-gate:antigaming:A_ASSERT_WEAKENED" in reg, (n, list(reg)))

        # missing dir / files never raise
        s2 = tempfile.mkdtemp()
        try:
            n, _, _, _ = run(s2)
            ok("no qa_shadow dir -> 0, no exception", n == 0)
        finally:
            shutil.rmtree(s2, ignore_errors=True)

        # seeding: history before install is not reported
        s3 = tempfile.mkdtemp()
        try:
            add(s3, "antigaming", rec("antigaming", "FAIL", "[A_VACUOUS=1]: A_VACUOUS old"))
            ft.seed_qa_cursor(s3)
            n, reg, _, _ = run(s3)
            ok("seeded cursor skips history", n == 0 and not reg, (n, list(reg)))
            add(s3, "antigaming", rec("antigaming", "FAIL", "[A_VACUOUS=1]: A_VACUOUS new", ref="k..l"))
            n, reg, _, _ = run(s3)
            ok("seeded cursor still sees new FAILs", n == 1, n)
        finally:
            shutil.rmtree(s3, ignore_errors=True)

        # _extra_sources wires it in and is isolated from a broken source
        s4 = tempfile.mkdtemp()
        try:
            add(s4, "migrations", rec("migrations", "FAIL", "[M_DRIFT=1] drift", repo="billwatch"))
            reg, new, regs = {}, [], []
            n = ft._extra_sources(s4, reg, new, regs)
            ok("_extra_sources picks up the QA source", n >= 1 and "billwatch::qa-gate:migrations:M_DRIFT" in reg, (n, list(reg)))
        finally:
            shutil.rmtree(s4, ignore_errors=True)
    finally:
        shutil.rmtree(s, ignore_errors=True)
    print("failure triage qa-gate source: %d passed, %d failed" % (P, F))
    return 1 if F else 0


if __name__ == "__main__":
    sys.exit(main())
