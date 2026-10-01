#!/usr/bin/env python3
"""release_candidate.py - gate S10: pick the release candidate SHA and cut release/<YYYYMMDD> (SHADOW ONLY).

  python3 qa/release_candidate.py plan --repo <name> [--main origin/main] [--develop origin/develop] [--date YYYYMMDD] [--no-record]
  python3 qa/release_candidate.py cut  --repo <name> [--run-gates] [--keep] [--really-push] [...plan flags]
  python3 qa/release_candidate.py check ...   (alias of plan, so qa_replay.py can drive it)

Flow it models (docs: qa/release_candidate.README.md, qa/patches/daily_promote_release_flow.md):
  develop --(gates, hygiene green merge)--> release/YYYYMMDD --(gates again, staging smoke)--> fast-forward main + tag prod-<ts>-<repo>
  hotfix/* is cut from main and merged to main AND develop.

Candidate rule (plan): walk develop's FIRST-PARENT history newest -> oldest back to main. A commit is the candidate when
  1. it CONTAINS main (so main can fast-forward to it - the reason a stale back-merge would otherwise break ff),
  2. it is a green hygiene merge ("gate=tests-green" in the subject; "reconcile main -> develop" back-merges inherit the status of
     the nearest older non-sync commit; "gate=no-tests" and direct/ungated commits are NOT green), and
  3. no commit in main..candidate (any parent) has a FAIL in state/qa_shadow/*.jsonl for this repo.
If nothing qualifies the develop tip is returned and marked UNVERIFIED (never PASS).

Verdicts: PASS = develop tip is a fully qualified candidate; FLAG = a qualified candidate exists but newer develop commits were held
back; UNVERIFIED = fallback to the tip / could not compute; NA = nothing to release. Exit code is always 0 (shadow).

Safety: plan is read-only (no fetch - the clones are kept fresh by the pipeline; pass --fetch to opt in). cut works in a throwaway
`git clone --shared` under /tmp so the live clone never gains a branch/worktree; it NEVER pushes unless --really-push AND the gate
mode is `enforce` (then it pushes ONLY the new release branch, non-forced - never main, never a tag).
"""
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import qa_common as qc  # noqa: E402

GATE = "release_candidate"
NON_CODE_GATES = {"release_candidate", "staging_check", "staging_smoke"}  # their FAILs describe environments, not commits
MAX_WALK = int(os.environ.get("QA_RELEASE_MAX_WALK", "60"))
GREEN_RE = re.compile(r"gate=tests-green")
NOGATE_RE = re.compile(r"gate=no-tests")
SYNC_RE = re.compile(r"reconcile main -> develop|reconcile main into develop|Merge branch 'main' into develop", re.I)
SHA_RE = re.compile(r"\b[0-9a-f]{7,40}\b")


# ---------------------------------------------------------------- pure helpers (unit-tested)
def classify(subject, is_merge=True):
    """green | nogate | sync | other.  'green' needs a MERGE commit: a direct commit whose message merely contains the text is forged/ungated."""
    if GREEN_RE.search(subject):
        if not is_merge:
            return "other"
        return "green"
    if NOGATE_RE.search(subject):
        return "nogate"
    if SYNC_RE.search(subject):
        return "sync"
    return "other"


def effective_status(chain):
    """chain = [(sha, subject)] newest -> oldest (first-parent). Returns {sha: 'green'|'nogate'|'other'}.
    A `sync` commit (main->develop back-merge) adds no new feature content, so it takes the status of the nearest OLDER
    non-sync commit; if there is none (the sync sits directly on main) it is green (it is main's own content)."""
    out = {}
    nxt = "green"
    for item in reversed(chain):  # oldest first
        sha, subj = item[0], item[1]
        k = classify(subj, item[2] if len(item) > 2 else True)
        if k == "sync":
            out[sha] = nxt
        else:
            out[sha] = k
            nxt = k
    return out


def fail_tokens(record_rows, repo):
    """Hex tokens (7-40 chars) from FAIL rows for `repo` of code-facing gates: ref, details.head/commit, commit."""
    toks = []
    for r in record_rows:
        if r.get("verdict") != "FAIL" or r.get("gate") in NON_CODE_GATES:
            continue
        if r.get("repo") not in (repo, None, "?", ""):
            continue
        cand = []
        for field in ("ref", "commit", "head", "head_sha"):
            v = r.get(field)
            if isinstance(v, str):
                cand.append(v)
        d = r.get("details")
        if isinstance(d, dict):
            for field in ("head", "head_sha", "commit", "sha"):
                v = d.get(field)
                if isinstance(v, str):
                    cand.append(v)
        for c in cand:
            c = c.split("..")[-1]  # "base..head" -> only the HEAD can be the failing commit, never the base
            for t in SHA_RE.findall(c):
                toks.append((t, r.get("gate", "?")))
    return toks


def fail_rows(record_rows, repo):
    """FAIL rows of code-facing gates for `repo` (same filter as fail_tokens)."""
    return [r for r in record_rows if r.get("verdict") == "FAIL" and r.get("gate") not in NON_CODE_GATES
            and r.get("repo") in (repo, None, "?", "")]


def pick_release_name(date, existing):
    """release/YYYYMMDD, or release/YYYYMMDD-2, -3 ... if that name is already taken (existing = set of names)."""
    base = "release/" + date
    if base not in existing:
        return base
    n = 2
    while "%s-%d" % (base, n) in existing:
        n += 1
    return "%s-%d" % (base, n)


# ---------------------------------------------------------------- git plumbing
def _g(rd, *a, timeout=60):
    rc, out, err = qc.git(rd, *a, timeout=timeout)
    return rc, out.strip(), err.strip()


def read_shadow_rows(state=None):
    d = os.path.join(state or qc.state_dir(), "qa_shadow")
    rows = []
    try:
        names = sorted(os.listdir(d))
    except OSError:
        return rows
    for n in names:
        if not n.endswith(".jsonl"):
            continue
        try:
            with open(os.path.join(d, n), errors="replace") as f:
                for line in f:
                    try:
                        j = json.loads(line)
                        if isinstance(j, dict):
                            rows.append(j)
                    except ValueError:
                        continue
        except OSError:
            continue
    return rows


def flags(argv):
    o = {"repo": "", "main": "origin/main", "develop": "origin/develop", "date": "", "base": "", "head": ""}
    bools = {"--no-record": "no_record", "--run-gates": "run_gates", "--keep": "keep", "--really-push": "really_push", "--fetch": "fetch"}
    pos, i = [], 0
    while i < len(argv):
        a = argv[i]
        if a in bools:
            o[bools[a]] = True
            i += 1
        elif a.startswith("--") and a[2:] in o and i + 1 < len(argv):
            o[a[2:]] = argv[i + 1]
            i += 2
        else:
            pos.append(a)
            i += 1
    return pos, o


def compute_plan(repo, o):
    """Returns (plan_dict, error_verdict_or_None)."""
    rd = qc.repo_dir(repo)
    if not rd:
        return None, qc.verdict("UNVERIFIED", GATE, repo, "?", "no clone for repo %s" % repo)
    if o.get("fetch"):
        qc.git(rd, "fetch", "-q", "origin", timeout=60)
    main, dev = o["main"], o["develop"]
    rcm, main_sha, _ = _g(rd, "rev-parse", "--verify", "-q", main + "^{commit}")
    rcd, dev_sha, _ = _g(rd, "rev-parse", "--verify", "-q", dev + "^{commit}")
    if rcd != 0:
        return None, qc.verdict("UNVERIFIED", GATE, repo, dev, "ref %s not found in %s" % (dev, rd))
    if rcm != 0:
        return None, qc.verdict("UNVERIFIED", GATE, repo, main, "ref %s not found in %s" % (main, rd))
    ahead = int(_g(rd, "rev-list", "--count", main + ".." + dev)[1] or 0)
    plan = {"repo": repo, "main_sha": main_sha, "develop_tip": dev_sha, "develop_ahead_of_main": ahead,
            "candidate": None, "fallback": False, "held_back": [], "skipped": [], "release_branch": None,
            "commits": [], "features": [], "coverage": {}}
    if ahead == 0:
        return plan, None
    rc, out, _ = _g(rd, "log", "--first-parent", "--format=%H\x1f%P\x1f%s", "-n", str(MAX_WALK), main + ".." + dev)
    chain = []
    for line in out.splitlines():
        parts = line.split("\x1f", 2)
        if len(parts) == 3:
            chain.append((parts[0], parts[2], len(parts[1].split()) >= 2))
    status = effective_status(chain)
    rows = read_shadow_rows()
    # the gate's own rows (and other environment gates) say nothing about commit quality, so they never count as coverage
    repo_rows = [r for r in rows if r.get("repo") in (repo, None, "?", "") and r.get("gate") not in NON_CODE_GATES]
    fail_commits = {}
    unresolved = []
    for r in fail_rows(rows, repo):
        resolved = False
        for tok, gate in fail_tokens([dict(r, repo=repo)], repo):
            rcv, full, _ = _g(rd, "rev-parse", "--verify", "-q", tok + "^{commit}")
            if rcv == 0 and full:
                fail_commits.setdefault(full, set()).add(gate)
                resolved = True
        if not resolved:  # branch name / HEAD~2 / unknown sha / no ref at all: we cannot tell which commit it condemns
            unresolved.append("%s@%s" % (r.get("gate", "?"), str(r.get("ref", ""))[:30]))
    plan["unresolved_fail_rows"] = unresolved[:20]
    plan["coverage"] = {"shadow_rows_total": len(rows), "shadow_rows_for_repo": len(repo_rows), "fail_commits_known": len(fail_commits),
                        "unresolved_fail_rows": len(unresolved), "no_fail_check_vacuous": not repo_rows}
    for idx, (sha, subj, is_merge) in enumerate(chain):
        why = None
        if status[sha] != "green":
            why = "not a green hygiene merge (%s)" % ("gate=no-tests" if classify(subj) == "nogate" else "direct/ungated commit")
            if classify(subj, is_merge) == "sync":
                why = "back-merge inherits non-green status"
        elif _g(rd, "merge-base", "--is-ancestor", main_sha, sha)[0] != 0:
            why = "does not contain main (main could not fast-forward to it)"
        else:
            rng = set(_g(rd, "rev-list", main_sha + ".." + sha, timeout=120)[1].split())
            bad = sorted(set(rng) & set(fail_commits))
            if bad:
                why = "QA FAIL in range: %s@%s" % ("/".join(sorted(fail_commits[bad[0]])), bad[0][:10])
        if why is None:
            plan["candidate"] = sha
            plan["held_back"] = [{"sha": c[0][:10], "subject": c[1][:90]} for c in chain[:idx]]
            break
        plan["skipped"].append({"sha": sha[:10], "subject": subj[:90], "reason": why})
    if plan["candidate"] is None:
        plan["candidate"], plan["fallback"] = dev_sha, True
    cand = plan["candidate"]
    # release branch name (local + remote branches considered)
    _, refs, _ = _g(rd, "for-each-ref", "--format=%(refname:short)", "refs/heads/release", "refs/remotes/origin/release")
    existing = set()
    for r in refs.splitlines():
        existing.add(r[len("origin/"):] if r.startswith("origin/") else r)
    date = o.get("date") or time.strftime("%Y%m%d")
    # an existing branch for today pointing at the candidate is reused (idempotent re-plan)
    same = None
    for name in sorted(existing):
        if name == "release/" + date or name.startswith("release/%s-" % date):
            for pref in ("origin/", ""):
                rcx, sx, _ = _g(rd, "rev-parse", "--verify", "-q", pref + name + "^{commit}")
                if rcx == 0 and sx == cand:
                    same = name
    plan["release_branch"] = same or pick_release_name(date, existing)
    plan["release_branch_exists"] = bool(same)
    # content since main
    rc, out, _ = _g(rd, "log", "--no-merges", "--format=%h\x1f%s", "-n", "300", main_sha + ".." + cand, timeout=120)
    commits = [l.split("\x1f", 1) for l in out.splitlines() if "\x1f" in l]
    plan["commits_total"] = int(_g(rd, "rev-list", "--no-merges", "--count", main_sha + ".." + cand)[1] or 0)
    plan["commits"] = [{"sha": s, "subject": sj[:100]} for s, sj in commits[:60]]
    plan["features"] = [sj[:100] for s, sj in commits if re.match(r"feat(\(|:)", sj)][:40]
    plan["fixes"] = sum(1 for s, sj in commits if re.match(r"fix(\(|:)", sj))
    plan["ff_main_possible"] = _g(rd, "merge-base", "--is-ancestor", main_sha, cand)[0] == 0
    return plan, None


def plan_verdict(plan, repo):
    if plan["develop_ahead_of_main"] == 0:
        return qc.verdict("NA", GATE, repo, plan["develop_tip"][:10], "nothing to release: develop == main", plan)
    cand = plan["candidate"][:10]
    unres = plan.get("unresolved_fail_rows") or []
    if plan["fallback"]:
        return qc.verdict("UNVERIFIED", GATE, repo, cand, "no qualified candidate (%d develop commits examined, none green+contains-main+no-FAIL): "
                          "falling back to develop tip %s as %s" % (len(plan["skipped"]), cand, plan["release_branch"]), plan)
    if plan["held_back"]:
        return qc.verdict("FLAG", GATE, repo, cand, ("[%d unresolved QA FAIL rows] " % len(unres) if unres else "") + "candidate %s is %d develop merge(s) behind the tip (held back: %s); would cut %s" % (
            cand, len(plan["held_back"]), plan["held_back"][0]["sha"], plan["release_branch"]), plan)
    if unres:
        return qc.verdict("UNVERIFIED", GATE, repo, cand, "%d QA FAIL row(s) for this repo cannot be resolved to a commit (%s): the no-FAIL-in-range check "
                          "cannot be trusted for candidate %s (never PASS)" % (len(unres), ", ".join(unres[:3]), cand), plan)
    vac = "" if plan["coverage"].get("shadow_rows_for_repo") else " [no QA shadow rows for this repo yet: the no-FAIL check is vacuous]"
    return qc.verdict("PASS", GATE, repo, cand, "candidate %s (develop tip, green hygiene merge, no QA FAIL in range); would cut %s with %d commits%s" % (
        cand, plan["release_branch"], plan.get("commits_total", 0), vac), plan)


# ---------------------------------------------------------------- commands
def cmd_plan(argv):
    pos, o = flags(argv)
    repo = o["repo"]
    if not repo:
        return qc.verdict("UNVERIFIED", GATE, "?", "?", "usage: plan --repo <name>")
    plan, err = compute_plan(repo, o)
    if err:
        return err
    return plan_verdict(plan, repo)


def run_gates_on(repo, base_sha, head_sha):
    """Run every sibling qa/gate_*.py (check --no-record) against main..candidate. Returns {gate: {verdict, summary}}."""
    here = os.path.dirname(os.path.abspath(__file__))
    gdir = os.environ.get("QA_GATES_DIR") or here
    out = {}
    try:
        names = sorted(n for n in os.listdir(gdir) if n.startswith("gate_") and n.endswith(".py"))
    except OSError:
        names = []
    for n in names:
        rc, so, se = qc.run([sys.executable, os.path.join(gdir, n), "check", "--repo", repo, "--base", base_sha, "--head", head_sha, "--no-record"],
                            timeout=int(os.environ.get("QA_RELEASE_GATE_TIMEOUT", "600")))
        try:
            j = json.loads(so.strip().splitlines()[-1])
            v = j.get("verdict", "UNVERIFIED")
            if v not in ("PASS", "NA", "FLAG", "FAIL", "UNVERIFIED"):
                v = "UNVERIFIED"
            if rc not in (0, 1) and v in ("PASS", "NA"):  # exit code says it crashed/timed out after printing something
                v = "UNVERIFIED"
            out[n[:-3]] = {"verdict": v, "summary": str(j.get("summary", ""))[:160]}
        except Exception:  # noqa: BLE001
            out[n[:-3]] = {"verdict": "UNVERIFIED", "summary": "no parsable output (rc=%s)" % rc}
    return out


def cmd_cut(argv):
    pos, o = flags(argv)
    repo = o["repo"]
    if not repo:
        return qc.verdict("UNVERIFIED", GATE, "?", "?", "usage: cut --repo <name>")
    plan, err = compute_plan(repo, o)
    if err:
        return err
    if plan["develop_ahead_of_main"] == 0:
        return plan_verdict(plan, repo)
    rd = qc.repo_dir(repo)
    cand, branch, main_sha = plan["candidate"], plan["release_branch"], plan["main_sha"]
    mode = qc.mode(GATE)
    details = dict(plan)
    details["would_push"] = [
        "git push origin %s            # new branch, non-force; gates + staging smoke run against it" % branch,
        "git push origin %s:main       # fast-forward ONLY (rejected if not ff); after gates+smoke are green" % branch,
        "git tag prod-<ts>-%s %s && git push origin prod-<ts>-%s" % (repo, cand[:10], repo),
    ]
    details["pushed"] = False
    tmp = tempfile.mkdtemp(prefix="qa-release-")
    clone = os.path.join(tmp, "clone")
    keep = bool(o.get("keep"))
    try:
        rc, _, err2 = qc.run(["git", "clone", "-q", "--shared", "--no-checkout", rd, clone], timeout=180, polite=False)[0:3]
        if rc != 0:
            return qc.verdict("UNVERIFIED", GATE, repo, cand[:10], "could not create scratch clone", details)
        rcb = qc.git(clone, "checkout", "-q", "-b", branch, cand, timeout=120)
        if rcb[0] != 0:
            return qc.verdict("UNVERIFIED", GATE, repo, cand[:10], "could not create %s in scratch clone: %s" % (branch, rcb[2][:120]), details)
        head = _g(clone, "rev-parse", "HEAD")[1]
        # prove main fast-forwards to the release branch (simulated in the scratch clone, detached)
        sim_ok = False
        if _g(clone, "checkout", "-q", "--detach", main_sha)[0] == 0:
            sim_ok = _g(clone, "merge", "--ff-only", "-q", branch)[0] == 0 and _g(clone, "rev-parse", "HEAD")[1] == head
        details.update({"scratch_branch": branch, "scratch_head": head[:10], "ff_main_simulation": "ok" if sim_ok else "FAILED",
                        "scratch_dir": clone if keep else None})
        if head != cand:
            return qc.verdict("UNVERIFIED", GATE, repo, cand[:10], "scratch branch head %s != candidate" % head[:10], details)
        if o.get("run_gates"):
            details["gates"] = run_gates_on(repo, main_sha, cand)
        v, summary = "PASS" if sim_ok else "FAIL", "scratch %s @ %s cut OK; main would fast-forward (simulated); NOT pushed (shadow)" % (branch, cand[:10])
        if not sim_ok:
            summary = "main CANNOT fast-forward to %s (main has commits the candidate lacks) - NOT pushed" % cand[:10]
        gates = details.get("gates") or {}
        if v == "PASS" and any(g["verdict"] == "FAIL" for g in gates.values()):
            v, summary = "FAIL", "gate FAIL on release candidate: " + ", ".join(k for k, g in gates.items() if g["verdict"] == "FAIL")
        elif v == "PASS" and o.get("run_gates") and not gates:
            v, summary = "UNVERIFIED", "--run-gates found ZERO gate scripts to run (check QA_GATES_DIR): nothing was actually gated; " + summary
        elif v == "PASS" and any(g["verdict"] not in ("PASS", "NA", "FLAG") for g in gates.values()):
            v, summary = "UNVERIFIED", "gate(s) could not check the candidate: " + ", ".join(
                "%s=%s" % (k, g["verdict"]) for k, g in gates.items() if g["verdict"] not in ("PASS", "NA", "FLAG"))
        elif v == "PASS" and any(g["verdict"] == "FLAG" for g in gates.values()):
            v, summary = "FLAG", "gate FLAG on release candidate: " + ", ".join(k for k, g in gates.items() if g["verdict"] == "FLAG")
        elif v == "PASS" and plan.get("unresolved_fail_rows"):
            v, summary = "UNVERIFIED", "%d QA FAIL row(s) cannot be resolved to a commit; " % len(plan["unresolved_fail_rows"]) + summary
        elif v == "PASS" and plan["fallback"]:
            v, summary = "UNVERIFIED", "cut from develop tip (no qualified candidate); " + summary
        elif v == "PASS" and plan["held_back"]:
            v, summary = "FLAG", "cut older candidate (%d merges held back); %s" % (len(plan["held_back"]), summary)
        if o.get("really_push"):
            if mode != "enforce":
                details["push_refused"] = "mode is %s (needs enforce)" % mode
                summary += " | --really-push REFUSED: mode=%s" % mode
            elif v not in ("PASS", "FLAG"):
                details["push_refused"] = "verdict %s" % v
                summary += " | --really-push REFUSED: verdict %s" % v
            else:
                url = _g(rd, "config", "--get", "remote.origin.url")[1]
                rcp = qc.git(clone, "push", "-q", url, "%s:refs/heads/%s" % (branch, branch), timeout=120)  # no force, branch only
                details["pushed"] = rcp[0] == 0
                if rcp[0] != 0:
                    details["push_error"] = rcp[2][:160]
                    v, summary = "UNVERIFIED", "push of %s failed (%s)" % (branch, rcp[2][:80])
                else:
                    summary += " | PUSHED %s (branch only; main untouched)" % branch
        return qc.verdict(v, GATE, repo, cand[:10], summary, details)
    finally:
        if not keep:
            shutil.rmtree(tmp, ignore_errors=True)


def cmd_history(argv):
    """history --repo X [--n 14]: retrospective on REAL promotes. For each 'release: promote develop -> main' merge on main, re-run the
    candidate rule with main=<parent1> develop=<parent2> and report whether the rule would have picked what was actually promoted, and
    whether a fast-forward of main would have been possible. Measurement only."""
    pos, o = flags(argv)
    n = 14
    if "--n" in argv:
        try:
            n = int(argv[argv.index("--n") + 1])
        except (ValueError, IndexError):
            pass
    repo = o["repo"]
    rd = qc.repo_dir(repo) if repo else None
    if not rd:
        return qc.verdict("UNVERIFIED", GATE, repo or "?", "?", "usage: history --repo <name> (clone not found)")
    _, out, _ = _g(rd, "log", "--first-parent", "--merges", "--format=%H %P", "-n", str(n), o["main"])
    rows = []
    for line in out.splitlines():
        parts = line.split()
        if len(parts) != 3:
            continue
        m, p1, p2 = parts
        subj = _g(rd, "log", "-1", "--format=%s", m)[1]
        if not subj.startswith("release: promote"):
            continue
        oo = dict(o)
        oo["main"], oo["develop"] = p1, p2
        plan, err = compute_plan(repo, oo)
        if err or not plan:
            continue
        rows.append({"promote": m[:10], "subject": subj[:60], "ahead": plan["develop_ahead_of_main"],
                     "candidate_is_tip": plan["candidate"] == plan["develop_tip"] and not plan["fallback"],
                     "fallback": plan["fallback"], "held_back": len(plan["held_back"]), "skipped": len(plan["skipped"]),
                     "skip_reasons": sorted({s["reason"].split(":")[0][:50] for s in plan["skipped"]}),
                     "ff_possible": plan.get("ff_main_possible")})
    t = len(rows)
    det = {"promotes": rows, "n": t, "tip_ok": sum(1 for r in rows if r["candidate_is_tip"]), "fallback": sum(1 for r in rows if r["fallback"]),
           "held_back": sum(1 for r in rows if r["held_back"]), "ff_impossible": sum(1 for r in rows if r["ff_possible"] is False)}
    return qc.verdict("NA", GATE, repo, "history", "%d promotes: tip==candidate %d, held-back %d, fallback %d, ff-impossible %d" % (
        t, det["tip_ok"], det["held_back"], det["fallback"], det["ff_impossible"]), det)


def main(argv):
    if argv and argv[0] == "history":
        return qc.main_guard(GATE, cmd_history, argv[1:] + ["--no-record"])
    if not argv or argv[0] not in ("plan", "cut", "check"):
        print(__doc__)
        return 2
    sub, rest = argv[0], argv[1:]
    fn = cmd_cut if sub == "cut" else cmd_plan
    return qc.main_guard(GATE, fn, rest)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
