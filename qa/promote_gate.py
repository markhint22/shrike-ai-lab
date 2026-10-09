#!/usr/bin/env python3
"""promote_gate.py - promote-time view of the release candidate + staging evidence for ONE repo (used by promote_to_prod.sh).

  python3 qa/promote_gate.py check --repo <name> [--main origin/main] [--develop origin/develop]

Prints ONE JSON line and ALWAYS exits 0 (promote_to_prod.sh treats any crash / empty output / timeout as "no evidence" = never blocks):
  candidate, candidate_verdict, release_branch, ff_main_possible, held_back     from release_candidate.compute_plan (read-only, no fetch)
  relation, staging_verdict, staging_commit, provider, summary                  from staging_check (FILE provider only: the Mac's 10-minutely snapshot)
  mode     the staging_check gate mode (off|shadow|enforce)
  block    true ONLY when mode == enforce AND the repo has a staging backend AND either
             (a) staging_verdict == FAIL with relation MISMATCH_BEHIND|MISMATCH_DIVERGED|MISMATCH_FAILED (staging is not serving the candidate, or its
                 latest deploy FAILED - on 2026-10-03 the 09:00 smoke passed against a stale deploy while the new deploy failed), or
             (b) the exported staging_deploys file is STALE or MISSING/corrupt (fail CLOSED: with no evidence we cannot tell a failed deploy from a good one).
           (c) relation BUILDING: the latest staging deploy of the candidate (or a descendant) is still in progress (transient: daily_promote.sh retries once).
           PASS / NA (no staging backend) / UNVERIFIED for any other reason (commit unknown to the clone, no CLI/plan failure) / any internal error =>
           block false (infra problems never block), but `unverified` is true and the promote summary reports it.
  reason   why block / unverified is set (FAIL:<relation> | BUILDING | EVIDENCE_STALE | EVIDENCE_MISSING | NA | UNVERIFIED:<why>)
  alembic_verdict / alembic_summary   qa/prod_alembic_check.py on the candidate (SHADOW: logged + one alerts.log WARN per (repo, sha), never blocks)
  e2e_verdict / e2e_commit / e2e_age_s / e2e_match / e2e_mode / e2e_block   LIVE-STAGING e2e evidence (2026-10-09, QA-N1; iptv_apps only): the newest result of
           the box runner (state/staging_e2e_box.json, scripts/qa/e2e/chickadee_staging_e2e.py) and of the Mac RevenueCat lifecycle (state/qa_staging_e2e.json).
           e2e_match = the candidate equals, or is an ancestor of, the commit that result ran against (the same is_ancestor test staging_check uses).
           Gate key `staging_e2e` (qa_common.mode: env OVN_QA_STAGING_E2E > state/qa_gate_modes.json > SHADOW; `qa/qa_enforce.sh staging_e2e enforce|shadow`).
           SHADOW (default): logged on the third evidence line, never blocks. ENFORCE: blocks ONLY on FAIL with e2e_match true and e2e_age_s < 12 h
           (reason E2E_FAIL:<cells>). UNVERIFIED, no match, stale, a missing / corrupt file or any internal error NEVER block and never crash the promote.
           No e2e file at all => no e2e line (the log lines are byte-identical to before this feature existed).

Mode resolution (2026-10-03, A3: staging_check is ENFORCING by default at promote time):
  env OVN_PROMOTE_STAGING_GATE (shadow|enforce|off; the promote-specific rollback) > env OVN_QA_STAGING_CHECK > state/qa_gate_modes.json (when present;
  top-level key, or under "modes"/"gates") > qa_common.mode() when it has an explicit source > ENFORCE.
  Rollback without a deploy: `qa/qa_enforce.sh staging_check shadow` (writes the flip file) or OVN_PROMOTE_STAGING_GATE=shadow in the cron env.
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import qa_common as qc  # noqa: E402

GATE = "staging_check"
FAIL_RELATIONS = ("MISMATCH_BEHIND", "MISMATCH_DIVERGED", "MISMATCH_FAILED")


def gate_mode():
    env = os.environ.get("OVN_PROMOTE_STAGING_GATE")
    if env in qc.MODES:
        return env
    env = os.environ.get("OVN_QA_STAGING_CHECK")
    if env in qc.MODES:
        return env
    try:
        with open(os.path.join(qc.state_dir(), "qa_gate_modes.json")) as f:
            j = json.load(f)
        for scope in (j, j.get("modes") if isinstance(j, dict) else None, j.get("gates") if isinstance(j, dict) else None):
            v = scope.get(GATE) if isinstance(scope, dict) else None
            if isinstance(v, dict):
                v = v.get("mode")
            if v in qc.MODES:
                return v
    except (OSError, ValueError, AttributeError):
        pass
    m, src = qc.mode_source(GATE)
    return m if src != "default" else DEFAULT_MODE


DEFAULT_MODE = "enforce"  # 2026-10-03 (A3): nothing explicit anywhere => the promote staging gate enforces

# ---------------------------------------------------------------- live-staging e2e evidence (QA-N1, 2026-10-09; shadow by default)
E2E_GATE = "staging_e2e"
E2E_REPOS = ("iptv_apps",)               # repos whose staging backend the e2e drives
E2E_MAX_AGE_S = 12 * 3600                # older evidence never blocks (it says nothing about the candidate any more)
E2E_SOURCES = (("mac", "qa_staging_e2e.json"), ("box", "staging_e2e_box.json"))  # state/ files: Mac RevenueCat lifecycle, box runner


def parse_ts(v):
    """'2026-10-09T07:25:01Z' -> epoch seconds, None when unusable."""
    import calendar
    import time
    try:
        return float(calendar.timegm(time.strptime(str(v), "%Y-%m-%dT%H:%M:%SZ")))
    except (ValueError, TypeError, OverflowError):
        return None


def aggregate_cells(cells):
    """One verdict over a result's cells: FAIL > UNVERIFIED > FLAG (some cells N/A beside passing ones: PARTIAL) > PASS > NA. A PASS is never reported
    next to a cell that could not run, and an NA cell never turns into a PASS."""
    vs = [c.get("verdict") for c in cells if isinstance(c, dict)]
    if "FAIL" in vs:
        return "FAIL"
    if "UNVERIFIED" in vs or not vs:
        return "UNVERIFIED"
    if "PASS" in vs:
        return "FLAG" if "NA" in vs else "PASS"
    return "NA"


def normalize_e2e(raw):
    """Parsed e2e file -> {ts, commit, cells, verdict} or None when unusable (no/invalid ts, not an object). Accepts the v2 shape
    {ts, staging_commit, cells:[{cell, verdict, ms, detail}]} and the legacy Mac file {ts, staging_commit, passed, total, failed:[...]}."""
    import re
    if not isinstance(raw, dict):
        return None
    ts = parse_ts(raw.get("ts"))
    if ts is None:
        return None
    cells = []
    if isinstance(raw.get("cells"), list):
        for c in raw["cells"]:
            if isinstance(c, dict) and isinstance(c.get("cell"), str):
                v = c.get("verdict")
                cells.append({"cell": c["cell"][:40], "verdict": v if v in qc.VERDICTS else "UNVERIFIED", "ms": c.get("ms") if isinstance(c.get("ms"), (int, float)) else None,
                              "detail": str(c.get("detail", ""))[:300]})
    elif "passed" in raw or "total" in raw:
        failed = [str(x)[:60] for x in raw.get("failed") or []] if isinstance(raw.get("failed"), list) else []
        total = raw.get("total") if isinstance(raw.get("total"), int) else 0
        if "harness-error" in failed or total <= 0:
            v, d = "UNVERIFIED", "the lifecycle produced no result (harness error)"
        elif failed:
            v, d = "FAIL", "%d/%d checks failed: %s" % (len(failed), total, "; ".join(failed)[:200])
        else:
            v, d = "PASS", "all %d lifecycle checks passed" % total
        cells.append({"cell": "revenuecat_lifecycle", "verdict": v, "ms": None, "detail": d})
    commit = str(raw.get("staging_commit") or "").strip().lower()
    cl = raw.get("cleanup") if isinstance(raw.get("cleanup"), dict) else {}
    cleanup = {k: cl.get(k) for k in ("attempted", "failed") if isinstance(cl.get(k), int) and not isinstance(cl.get(k), bool)}
    return {"ts": ts, "commit": commit if re.fullmatch(r"[0-9a-f]{7,40}", commit) else "", "cells": cells, "verdict": aggregate_cells(cells), "cleanup": cleanup}


def read_e2e_sources(state_dir=None):
    """-> (sources, unreadable): every state/ e2e file that exists. Missing files are skipped silently; a file that exists but is corrupt / not an object / has no
    usable timestamp is counted in `unreadable` (never raises)."""
    import json as _json
    d = state_dir or qc.state_dir()
    out, bad = [], []
    for name, fname in E2E_SOURCES:
        path = os.path.join(d, fname)
        if not os.path.exists(path):
            continue
        try:
            with open(path, "rb") as f:
                n = normalize_e2e(_json.loads(f.read().decode("utf-8", "replace")))
        except (OSError, ValueError):
            n = None
        if n is None:
            bad.append(name)
        else:
            n["source"] = name
            out.append(n)
    return out, bad


def decide_e2e_block(mode, verdict, match, age_s, max_age_s=E2E_MAX_AGE_S):
    """Pure decision (unit-tested): the e2e blocks ONLY when enforcing, FAIL, evidence for THIS candidate (match true) and fresh (< 12 h)."""
    return bool(mode == "enforce" and verdict == "FAIL" and match is True and age_s is not None and 0 <= age_s < max_age_s)


def e2e_evaluate(sources, bad, candidate, is_anc, now, mode):
    """-> dict of e2e_* fields. A source COUNTS when it ran against the candidate (equal / ancestor) and is < 12 h old; among counting sources a FAIL wins,
    otherwise the newest counting one speaks; with none counting the newest source is reported (match false / stale) and can never block."""
    out = {"e2e_present": bool(sources or bad), "e2e_mode": mode, "e2e_verdict": "", "e2e_commit": "", "e2e_age_s": None, "e2e_match": None,
           "e2e_source": "", "e2e_cells": "", "e2e_fail_cells": [], "e2e_block": False, "e2e_summary": ""}
    if not sources:
        if bad:
            out.update(e2e_verdict="UNVERIFIED", e2e_summary="e2e evidence file unreadable (%s): ignored, never blocks" % ",".join(bad))
        return out
    for s in sources:
        c = s["commit"]
        s["age"] = max(0.0, now - s["ts"])
        s["match"] = bool(c and candidate and (candidate == c or c.startswith(candidate) or candidate.startswith(c) or is_anc(candidate, c) is True))
        s["counts"] = bool(s["match"] and s["age"] < E2E_MAX_AGE_S)
    counting = [s for s in sources if s["counts"]]
    pick = next((s for s in counting if s["verdict"] == "FAIL"), None) or (max(counting, key=lambda s: s["ts"]) if counting else max(sources, key=lambda s: s["ts"]))
    tally = {}
    for c in pick["cells"]:
        tally[c["verdict"]] = tally.get(c["verdict"], 0) + 1
    out.update(e2e_verdict=pick["verdict"], e2e_commit=pick["commit"], e2e_age_s=int(pick["age"]), e2e_match=pick["match"], e2e_source=pick["source"],
               e2e_cells=", ".join("%d %s" % (n, v) for v, n in sorted(tally.items())) or "no cells",
               e2e_fail_cells=[c["cell"] for c in pick["cells"] if c["verdict"] == "FAIL"])
    out["e2e_block"] = decide_e2e_block(mode, pick["verdict"], pick["match"], out["e2e_age_s"])
    if bad:
        out["e2e_summary"] = "unreadable file(s) ignored: %s" % ",".join(bad)
    return out


def _is_ancestor_in(rd, a, b):
    """True/False/None(unknown to the clone): the same test staging_check.cmd_check uses."""
    if not rd or qc.git(rd, "cat-file", "-e", a + "^{commit}")[0] != 0 or qc.git(rd, "cat-file", "-e", b + "^{commit}")[0] != 0:
        return None
    return qc.git(rd, "merge-base", "--is-ancestor", a, b)[0] == 0


def decide_block(mode, verdict, relation, staged, evidence):
    """Pure decision (unit-tested). -> (block, unverified, reason).
    staged: the repo has a staging backend. evidence: ok | stale | missing (state of the exported staging_deploys file)."""
    if verdict == "NA" or not staged:
        return False, True, "NA: repo has no staging backend (promoted UNVERIFIED)"
    if verdict == "FAIL" and relation in FAIL_RELATIONS:
        return mode == "enforce", False, "FAIL:" + relation
    if verdict == "UNVERIFIED" and evidence in ("stale", "missing"):
        return mode == "enforce", True, "EVIDENCE_" + evidence.upper()
    if verdict == "UNVERIFIED" and relation == "BUILDING":
        # the latest staging deploy of the candidate (or a descendant) is still in flight: the smoke would hit the OLD build. Transient hold.
        return mode == "enforce", True, "BUILDING"
    if verdict == "PASS":
        return False, False, ""
    return False, True, "UNVERIFIED"


def should_block(mode, verdict, relation, staged=True, evidence="ok"):
    """Back-compat wrapper: only an enforced, explicit staging FAIL (or fail-closed missing/stale evidence) blocks."""
    return decide_block(mode, verdict, relation, staged, evidence)[0]


def opt(argv, name, default):
    return argv[argv.index(name) + 1] if name in argv and argv.index(name) + 1 < len(argv) else default


def _check(argv):
    repo = opt(argv, "--repo", "")
    out = {"repo": repo, "mode": "shadow", "block": False, "candidate": "", "candidate_verdict": "", "release_branch": "",
           "ff_main_possible": None, "held_back": 0, "relation": "", "staging_verdict": "UNVERIFIED", "staging_commit": "",
           "provider": "", "summary": "", "unverified": True, "reason": "", "evidence": "", "alembic_verdict": "", "alembic_summary": "",
           "e2e_present": False, "e2e_mode": "", "e2e_verdict": "", "e2e_commit": "", "e2e_age_s": None, "e2e_match": None, "e2e_block": False}
    try:
        out["mode"] = gate_mode()
        import release_candidate as rc
        import staging_check as sc
        plan, err = rc.compute_plan(repo, {"main": opt(argv, "--main", "origin/main"), "develop": opt(argv, "--develop", "origin/develop"), "date": ""})
        if err or not plan:
            out["summary"] = "release plan failed: " + str((err or {}).get("summary", "?"))[:200]
            return out
        pv = rc.plan_verdict(plan, repo)
        out.update(candidate=plan["candidate"] or "", candidate_verdict=pv["verdict"], release_branch=plan.get("release_branch") or "",
                   ff_main_possible=plan.get("ff_main_possible"), held_back=len(plan.get("held_back") or []))
        if not plan["candidate"]:
            out["summary"] = "no candidate: " + pv["summary"][:200]
            return out
        res = sc.cmd_check(["--repo", repo, "--sha", plan["candidate"], "--provider", "file"])
        qc.record(res)  # the gate's own evidence trail, same file the 08:50 shadow job writes
        det = res.get("details") or {}
        out.update(staging_verdict=res["verdict"], relation=det.get("relation", ""), staging_commit=det.get("staging_commit") or "",
                   provider=det.get("provider", ""), summary=res["summary"][:240])
        staged = sc.has_staging(repo)
        ev, _age = sc.file_evidence_state(repo)
        out["evidence"] = ev
        out["block"], out["unverified"], out["reason"] = decide_block(out["mode"], res["verdict"], out["relation"], staged, ev)
        if out["reason"].startswith("UNVERIFIED"):
            out["reason"] += ": " + res["summary"][:120]
        try:  # prod alembic ancestry: SHADOW, never affects block
            import prod_alembic_check as pac
            a = pac.check_ref(repo, plan["candidate"])
            out["alembic_verdict"], out["alembic_summary"] = a["verdict"], a["summary"][:240]
        except Exception as ex:  # noqa: BLE001
            out["alembic_verdict"], out["alembic_summary"] = "UNVERIFIED", "prod_alembic_check crashed: %s" % type(ex).__name__
        try:  # live-staging e2e evidence: SHADOW unless `qa_enforce.sh staging_e2e enforce`; an error here never blocks and never crashes the promote
            _apply_e2e(out, repo, plan["candidate"])
        except Exception as ex:  # noqa: BLE001
            out.update(e2e_present=True, e2e_verdict="UNVERIFIED", e2e_block=False, e2e_summary="staging_e2e crashed: %s" % type(ex).__name__)
    except Exception as ex:  # noqa: BLE001 - never block (or crash a promote) on our own bug
        out.update(block=False, staging_verdict="UNVERIFIED", summary="promote_gate crashed: %s: %s" % (type(ex).__name__, ex))
    return out


def _apply_e2e(out, repo, candidate):
    import time
    if repo not in E2E_REPOS:
        return
    m = qc.mode(E2E_GATE)
    if m == "off":
        return
    sources, bad = read_e2e_sources()
    rd = qc.repo_dir(repo)
    out.update(e2e_evaluate(sources, bad, candidate, lambda a, b: _is_ancestor_in(rd, a, b), time.time(), m))
    if out["e2e_block"] and not out["block"]:
        out["block"] = True
        out["reason"] = "E2E_FAIL:" + (",".join(out["e2e_fail_cells"]) or "?")


def check(argv):
    out = _check(argv)
    out["log_lines"] = log_lines(out)  # also on the early-return paths (no plan / no candidate)
    return out


def log_lines(o):
    """The two evidence lines promote_to_prod.sh prints (and daily_promote.sh keeps in its log) so the morning read shows what was shipped and why."""
    if o["candidate"]:
        c = "  [candidate] %s %s, %d develop merge(s) held back, release branch %s, main fast-forwardable: %s" % (
            o["candidate"][:10], o["candidate_verdict"] or "?", o["held_back"], o["release_branch"] or "?",
            {True: "yes", False: "NO"}.get(o["ff_main_possible"], "unknown"))
    else:
        c = "  [candidate] none (%s)" % (o["summary"] or "no evidence")
    act = "BLOCK" if o["block"] else ("proceed UNVERIFIED" if o.get("unverified") else "proceed")
    s = "  [staging-gate] mode=%s staging_check=%s%s serving=%s provider=%s evidence=%s -> %s (%s)" % (
        o["mode"], o["staging_verdict"], "/" + o["relation"] if o["relation"] else "", (o["staging_commit"] or "?")[:10], o["provider"] or "?",
        o.get("evidence") or "?", act, (o["summary"] or "")[:140])
    out = [c, s]
    if o.get("e2e_present"):
        would = o.get("e2e_verdict") == "FAIL" and o.get("e2e_match") is True and o.get("e2e_mode") != "enforce" and (o.get("e2e_age_s") or 0) < E2E_MAX_AGE_S
        eact = "BLOCK" if o.get("e2e_block") else ("proceed (shadow: would block)" if would else "proceed")
        age = o.get("e2e_age_s")
        out.append("  [staging-e2e] mode=%s e2e=%s%s commit=%s age=%s match=%s source=%s -> %s%s" % (
            o.get("e2e_mode") or "?", o.get("e2e_verdict") or "?", (" fail=" + ",".join(o["e2e_fail_cells"])) if o.get("e2e_fail_cells") else "",
            (o.get("e2e_commit") or "?")[:10], ("%dm" % (age // 60)) if isinstance(age, int) else "?", {True: "yes", False: "no"}.get(o.get("e2e_match"), "?"),
            o.get("e2e_source") or "?", eact, (" (%s)" % o["e2e_cells"]) if o.get("e2e_cells") else (" (%s)" % o["e2e_summary"] if o.get("e2e_summary") else "")))
    if o.get("alembic_verdict"):
        out.append("  [prod-alembic] %s (shadow): %s" % (o["alembic_verdict"], o["alembic_summary"]))
    return out


def main(argv):
    if not argv or argv[0] != "check":
        print(__doc__)
        return 0
    print(json.dumps(check(argv[1:]), sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
