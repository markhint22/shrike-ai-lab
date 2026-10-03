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
           "provider": "", "summary": "", "unverified": True, "reason": "", "evidence": "", "alembic_verdict": "", "alembic_summary": ""}
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
    except Exception as ex:  # noqa: BLE001 - never block (or crash a promote) on our own bug
        out.update(block=False, staging_verdict="UNVERIFIED", summary="promote_gate crashed: %s: %s" % (type(ex).__name__, ex))
    return out


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
