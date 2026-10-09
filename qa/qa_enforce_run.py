#!/usr/bin/env python3
"""qa_enforce_run.py - PRE-PUSH enforcement for branch_hygiene.sh (docs/QA_GATES_SPEC.md; written 2026-10-02).

    qa_enforce_run.py gates
    qa_enforce_run.py precheck --repo <clone path> --base <sha> --head <sha> --tip <sha> [--name N]

`gates` prints the gates whose EFFECTIVE mode is enforce (qa_common.mode), one per line. A gate in shadow/off is never listed, so it is
never run synchronously; it keeps running detached afterwards through qa_run_shadow.sh exactly as before. OVN_QA_ENFORCE=off is a global
kill switch (lists nothing).

`precheck` is called by branch_hygiene.sh AFTER the merge commit <head> (first parent <base> = the develop tip) exists in the temp clone and
the build/test gate is green, but BEFORE the push. It prints ONE JSON line and ALWAYS exits 0:
    {"action": "proceed"}                                  nothing to block (no enforce gate / all PASS-FLAG-NA-UNVERIFIED)
    {"action": "block", "clean_ref": "<sha>"|"", ...}      an enforce-mode gate said FAIL on base..head
Only a parsed FAIL verdict from a gate that is in enforce mode blocks. FLAG / NA / UNVERIFIED / PASS, a gate timeout (rc 124), a crash, a
missing script, unparsable output: all proceed (infra problems must never block a merge; they are logged as unverified).

DEADLOCK SAFETY (hygiene lock-starvation was a real multi-day incident): when the range FAILs we locate the offending commit by running the
failing gate(s) over CUMULATIVE prefixes of the feature branch, oldest first, each prefix diffed from merge-base(develop, prefix) so only the
branch's own work is judged. The first failing prefix names the offender. clean_ref is the commit just before it in topological order (an
ancestor-closed set, so the offender is not reachable from it); hygiene merges ONLY that, so unrelated good work still lands and the offender
plus everything after stays on the feature branch. The search is bounded (QA_ENFORCE_SEARCH_BUDGET seconds, QA_ENFORCE_MAX_COMMITS
candidates); commits not reached in budget are held UNVERIFIED (never merged unchecked) and the next hourly pass resumes from the new tip.
If the range failed but no single prefix reproduces it (e.g. only the merge result differs), the tip commit is blamed so the rest lands.

Alerting: exactly ONE warn line per (repo, gate, offender) in state/alerts.log (the single alert channel; no ntfy here) and
state/qa_blocked/<repo>__<branch>.json (so an unchanged offender does not re-alert every hour). The file is removed again as soon as a pass proceeds.
It takes no lock, touches no live clone (reads objects only), and never writes anywhere but state/.
"""
import json
import os
import re
import sys
import tempfile
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import qa_common as qc  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))


def gates_dir():
    return os.environ.get("QA_GATES_DIR") or HERE


def all_gates():
    try:
        return sorted(f[5:-3] for f in os.listdir(gates_dir()) if re.match(r"^gate_[A-Za-z0-9_]+\.py$", f))
    except OSError:
        return []


def enforce_gates():
    if os.environ.get("OVN_QA_ENFORCE", "on") == "off":
        return []
    return [g for g in all_gates() if qc.mode(g) == "enforce"]


def _num(name, default):
    try:
        return float(os.environ.get(name, default))
    except ValueError:
        return float(default)


def run_gate(gate, repo, base, head, secs):
    """-> (verdict, summary). Anything other than a parsed FAIL from a gate that reports mode=enforce is a non-blocking verdict.
    --no-record: probing prefixes must not pollute state/qa_shadow stats."""
    py = sys.executable or "python3"
    script = os.path.join(gates_dir(), "gate_%s.py" % gate)
    if not os.path.isfile(script):
        return "UNVERIFIED", "gate script missing"
    secs = max(5.0, secs)
    rc, out, err = qc.run([py, os.path.join(HERE, "qa_timeout.py"), "%d" % secs, py, script, "check", "--repo", repo, "--base", base,
                           "--head", head, "--no-record", "--enforce-exit"], timeout=secs + 15)
    if rc in (124, 127):
        return "UNVERIFIED", "gate timed out / not runnable (rc=%s)" % rc
    last = [l for l in out.splitlines() if l.strip()]
    try:
        res = json.loads(last[-1])
        v, m, s = res.get("verdict"), res.get("mode"), str(res.get("summary", ""))
    except (IndexError, ValueError, AttributeError):
        return "UNVERIFIED", "no parsable gate output (rc=%s)" % rc
    if v == "FAIL" and m == "enforce":
        return "FAIL", s
    if v == "FAIL":
        return "UNVERIFIED", "gate said FAIL but is not in enforce mode (%s)" % m   # defensive: never block on a non-enforce gate
    return (v if v in qc.VERDICTS else "UNVERIFIED"), s


def _git(repo, *a, timeout=60):
    rc, out, _ = qc.git(repo, *a, timeout=timeout)
    return out.strip() if rc == 0 else ""


def _atomic_write(path, text):
    d = os.path.dirname(path)
    os.makedirs(d, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=".qa_blocked.", dir=d)
    try:
        with os.fdopen(fd, "w") as f:
            f.write(text)
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def blocked_key(name, branch=""):
    """2026-10-02: the record is keyed by repo AND feature branch. branch_hygiene.sh runs two passes per repo against the same state dir
    (overnight/feature at :00, claude/feature at :30); a repo-only key let the clean pass of one branch delete the other branch's record,
    so the next blocked pass re-alerted every hour. Must match the shell expansion ${FEAT//[^A-Za-z0-9._-]/_} in branch_hygiene.sh/qa_enforce.sh."""
    return name + ("__" + re.sub(r"[^A-Za-z0-9._-]", "_", branch) if branch else "")


def blocked_path(name, branch=""):
    return os.path.join(qc.state_dir(), "qa_blocked", blocked_key(name, branch) + ".json")


def clear_blocked(name, branch=""):
    try:
        os.unlink(blocked_path(name, branch))
    except OSError:
        pass


def note_blocked(name, gate, commit, subject, finding, held, branch=""):
    """Write state/qa_blocked/<repo>[__<branch>].json; append ONE alert line only when (gate, commit) differs from what is already recorded."""
    p = blocked_path(name, branch)
    now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    try:
        with open(p) as f:
            prev = json.load(f)
    except (OSError, ValueError):
        prev = {}
    new = not (prev.get("gate") == gate and prev.get("commit") == commit)
    rec = {"repo": name, "branch": branch, "gate": gate, "commit": commit, "subject": subject[:120], "finding": finding[:300], "held_commits": held,
           "since": now if new else prev.get("since", now), "last_seen": now}
    try:
        _atomic_write(p, json.dumps(rec, sort_keys=True, indent=1) + "\n")
        if new:
            line = "[%s] warn | qa-enforce:%s | gate=%s blocked commit %s (%s): %s - held %d commit(s) on the feature branch; clean prefix (if any) still lands%s" % (
                time.strftime("%Y-%m-%d %H:%M:%S"), name, gate, commit[:12], " ".join(subject.split())[:80], " ".join(finding.split())[:200], held, (" [branch %s]" % branch) if branch else "")
            with open(os.path.join(qc.state_dir(), "alerts.log"), "a") as f:
                f.write(line + "\n")
    except OSError:
        return False   # could not record: the block itself still stands, but we must not crash hygiene
    return new


def precheck(a):
    repo, base, head, tip = a["repo"], a["base"], a["head"], a["tip"]
    name = a.get("name") or os.path.basename(repo.rstrip("/"))
    branch = a.get("branch", "")
    gates = enforce_gates()
    if not gates:
        clear_blocked(name, branch)
        return {"action": "proceed", "reason": "no enforce-mode gates"}
    t_gate = _num("QA_ENFORCE_TIMEOUT", 120)
    failing = {}
    unverified = []
    for g in gates:
        v, s = run_gate(g, repo, base, head, t_gate)
        if v == "FAIL":
            failing[g] = s
        elif v == "UNVERIFIED":
            unverified.append(g)
    if not failing:
        clear_blocked(name, branch)
        return {"action": "proceed", "reason": "enforce gates did not FAIL", "unverified": unverified}

    # locate the offender: cumulative prefixes of the feature branch, oldest first
    order = _git(repo, "rev-list", "--topo-order", "--reverse", "%s..%s" % (base, tip), timeout=60).split()
    nomerge = set(_git(repo, "rev-list", "--no-merges", "%s..%s" % (base, tip), timeout=60).split())
    allc = [c for c in order if c in nomerge]
    cands = allc[: int(_num("QA_ENFORCE_MAX_COMMITS", 80))]
    truncated = len(allc) > len(cands)
    budget_end = time.time() + _num("QA_ENFORCE_SEARCH_BUDGET", 300)
    offender, gate_hit, finding, reason = "", "", "", ""
    for c in cands:
        left = budget_end - time.time()
        if left < 5:
            offender, gate_hit = c, sorted(failing)[0]
            finding = "search budget exhausted before this commit was checked; held UNVERIFIED (range FAIL: %s)" % failing[gate_hit]
            reason = "budget"
            break
        mb = _git(repo, "merge-base", base, c) or base
        hit = None
        for g in sorted(failing):
            v, s = run_gate(g, repo, mb, c, min(t_gate, left))
            if v == "FAIL":
                hit = (g, s)
                break
        if hit:
            offender, gate_hit, finding, reason = c, hit[0], hit[1], "prefix"
            break
    clean_override = None
    if not offender and truncated:
        # 2026-10-02: the cap was hit with no prefix failing. Commits past the cap were never examined, so blaming cands[-1] (which DID pass)
        # was misleading. Hold from the first unexamined commit on, UNVERIFIED; the examined prefix (each cumulative prefix passed) still lands.
        pos0 = (order.index(cands[-1]) + 1) if cands else 0
        offender = order[pos0] if pos0 < len(order) else tip
        clean_override = cands[-1] if cands else ""
        gate_hit = sorted(failing)[0]
        finding = "held unverified (candidate cap %d reached; later commits not examined individually; range FAIL: %s)" % (len(cands), failing[gate_hit])
        reason = "cap"
    if not offender:
        # range FAILed but no single prefix reproduces it: blame the tip so everything before it still lands
        offender = cands[-1] if cands else tip
        gate_hit = sorted(failing)[0]
        finding = "range FAIL not reproduced by any single prefix (merge-result effect): %s" % failing[gate_hit]
        reason = "tip"
    pos = order.index(offender) if offender in order else 0
    clean = order[pos - 1] if pos > 0 else ""
    if clean_override is not None:
        clean = clean_override
    subject = _git(repo, "log", "-1", "--format=%s", offender)
    held = len(order) - pos
    note_blocked(name, gate_hit, offender, subject, finding, held, branch)
    return {"action": "block", "gate": gate_hit, "offender": offender, "subject": subject, "finding": finding[:300],
            "clean_ref": clean, "held": held, "reason": reason, "unverified": unverified}


def main(argv):
    try:
        if not argv:
            print(__doc__)
            return 0
        if argv[0] == "gates":
            for g in enforce_gates():
                print(g)
            return 0
        if argv[0] == "precheck":
            a, i = {}, 1
            while i < len(argv):
                if argv[i] in ("--repo", "--base", "--head", "--tip", "--name", "--branch") and i + 1 < len(argv):
                    a[argv[i][2:]] = argv[i + 1]
                    i += 2
                else:
                    i += 1
            if not all(k in a for k in ("repo", "base", "head", "tip")):
                print(json.dumps({"action": "proceed", "reason": "usage error (unverified)"}))
                return 0
            print(json.dumps(precheck(a), sort_keys=True))
            return 0
    except Exception as ex:  # noqa: BLE001 - enforcement plumbing must never break a merge on its own bug
        print(json.dumps({"action": "proceed", "reason": "enforce helper crashed (unverified): %s: %s" % (type(ex).__name__, ex)}))
        return 0
    print(json.dumps({"action": "proceed", "reason": "unknown subcommand (unverified)"}))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
