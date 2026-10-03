#!/usr/bin/env python3
"""qa_replay.py - replay a QA gate over historical commits to measure its flag rate / false positives WITHOUT new dev traffic.

usage: qa_replay.py <gate_script.py> <repo> [--days 14] [--limit 200] [--branch origin/develop] [--author SUBSTR]
                    [--sample 15] [--extra "--flag value"]
       qa_replay.py --gold [--gold-file qa/gold_set.json] [--only G1,G7] [--gates antigaming,reviewer] [--live-model] [--json] [--strict]

For every non-merge commit on <branch> in the window, runs
    python3 <gate_script> check --repo <repo> --base <commit>^ --head <commit> --no-record
and aggregates the verdicts. Prints a summary and writes every result to state/qa_replay/<gate>-<repo>.jsonl.
Read-only: it never modifies a repo. Gate stderr is discarded; a gate that crashes or times out counts as UNVERIFIED.

--gold replays every row of qa/gold_set.json (real incidents + real false positives, exact base/head SHAs) through the gate the row names and reports,
per row and per gate, CAUGHT / MISSED (true positives), CLEAN / FALSE_POSITIVE (benign + fixed-FP rows), EXPECTED_AFTER_MERGE (a miss on a row whose
`pending` check does not exist yet), UNCOVERED (known gaps with no gate), UNMEASURED (infra: no clone, no docker, gate UNVERIFIED). The reviewer runs
WITHOUT the model unless --live-model (its model-free pattern pass is what the gold rows exercise; the model would burn GPU). Nothing is recorded to
state/qa_shadow. Exit 0 unless --strict and a true positive was MISSED or a benign row was FLAGGED/FAILed.
"""
import collections
import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import qa_common as qc  # noqa: E402


def parse(argv):
    o = {"days": 14, "limit": 200, "branch": "origin/develop", "author": "", "sample": 15, "extra": ""}
    pos = []
    i = 0
    while i < len(argv):
        a = argv[i]
        if a.startswith("--") and a[2:] in o and i + 1 < len(argv):
            o[a[2:]] = type(o[a[2:]])(argv[i + 1]) if not isinstance(o[a[2:]], str) else argv[i + 1]
            i += 2
        else:
            pos.append(a)
            i += 1
    return pos, o


# ------------------------------------------------------------------------------------------------------------------- gold set
HERE = os.path.dirname(os.path.abspath(__file__))
SEV_RANK = {"low": 0, "medium": 1, "high": 2}


def gold_rows(path):
    with open(path) as f:
        d = json.load(f)
    return d.get("rows", []) if isinstance(d, dict) else []


def run_gold_gate(row, rd, live_model):
    """-> result dict {verdict, summary, details} or None when the row has no runnable gate (kind decided by the caller)."""
    gate = row.get("gate") or "none"
    if gate == "none" or gate.startswith("pending:"):
        return None
    if gate.startswith("landing:"):
        script = os.path.join(HERE, "..", "scripts", gate.split(":", 1)[1] + ".py")
        if not os.path.isfile(script):
            return {"verdict": "UNVERIFIED", "summary": "landing check %s not present" % gate.split(":", 1)[1], "details": {}}
        with qc.worktree(rd, row["head"]) as wt:
            if not wt:
                return {"verdict": "UNVERIFIED", "summary": "could not create worktree at head", "details": {}}
            rc, so, se = qc.run([sys.executable, script, wt], timeout=120, polite=True)
        if rc == 124 or rc == 127:
            return {"verdict": "UNVERIFIED", "summary": "landing check could not run (rc=%d)" % rc, "details": {}}
        return {"verdict": "FAIL" if rc == 1 else ("PASS" if rc == 0 else "UNVERIFIED"), "summary": (so + se).strip()[:160], "details": {}}
    script = os.path.join(HERE, "gate_%s.py" % gate)
    if not os.path.isfile(script):
        return {"verdict": "UNVERIFIED", "summary": "no gate script gate_%s.py" % gate, "details": {}}
    env = {}
    if gate == "reviewer" and not live_model:
        env = {"QA_REVIEWER_URL": "http://127.0.0.1:9", "QA_REVIEWER_DEADLINE": "30", "QA_REVIEWER_CALL_TIMEOUT": "5"}
    rc, so, _ = qc.run([sys.executable, script, "check", "--repo", row["repo"], "--base", row["base"], "--head", row["head"], "--no-record"],
                       timeout=int(os.environ.get("QA_REPLAY_TIMEOUT", "300")), polite=True, env=env or None)
    try:
        return json.loads(so.strip().splitlines()[-1])
    except Exception:  # noqa: BLE001
        return {"verdict": "UNVERIFIED", "summary": "no parsable output (rc=%s)" % rc, "details": {}}


def judge_gold(row, res):
    """-> (status, note). Pure: unit-tested with canned results."""
    kind, gate = row.get("kind", "true_positive"), row.get("gate", "none")
    pending = row.get("pending")
    if res is None:
        if kind == "known_gap" or gate == "none":
            return "UNCOVERED", "no gate covers this yet"
        return "EXPECTED_AFTER_MERGE", pending or "check not built yet"
    v = res.get("verdict", "UNVERIFIED")
    if v == "UNVERIFIED":
        if pending and gate.startswith("landing:") and "not present" in str(res.get("summary")):
            return "EXPECTED_AFTER_MERGE", pending
        return "UNMEASURED", str(res.get("summary", ""))[:100]
    det = res.get("details") or {}
    if kind in ("benign", "false_positive_fixed"):
        return ("FALSE_POSITIVE", "%s: %s" % (v, str(res.get("summary", ""))[:100])) if v in ("FAIL", "FLAG") else ("CLEAN", v)
    if kind == "borderline":
        return "BORDERLINE", v
    if kind == "known_gap":
        return "UNCOVERED", v
    catch = row.get("catch_verdicts") or ["FAIL", "FLAG"]
    ok = v in catch
    why = ""
    exp = row.get("expect") or []
    if ok and exp:
        got = {f.get("rule") for f in (det.get("findings") or [])}
        miss = [e for e in exp if e not in got]
        if miss:
            ok, why = False, "verdict %s but rule(s) %s not reported (got %s)" % (v, ",".join(miss), ",".join(sorted(x for x in got if x)) or "none")
    for ef in (row.get("expect_findings") or []):
        if not ok:
            break
        import re as _re
        hit = [f for f in (det.get("findings") or []) if _re.search(ef.get("file_re", ""), str(f.get("file", "")))
               and SEV_RANK.get(f.get("severity"), 1) >= SEV_RANK.get(ef.get("min_severity", "low"), 0)]
        if not hit:
            ok, why = False, "no finding on /%s/ with severity >= %s" % (ef.get("file_re"), ef.get("min_severity", "low"))
    if ok:
        return "CAUGHT", "%s %s" % (v, str(res.get("summary", ""))[:90])
    if pending:
        return "EXPECTED_AFTER_MERGE", pending
    return "MISSED", why or "verdict %s not in %s" % (v, catch)


def gold_main(argv):
    o = {"gold-file": os.path.join(HERE, "gold_set.json"), "only": "", "gates": ""}
    flags = {"--live-model", "--json", "--strict", "--gold"}
    i = 0
    while i < len(argv):
        if argv[i].startswith("--") and argv[i][2:] in o and i + 1 < len(argv):
            o[argv[i][2:]] = argv[i + 1]
            i += 2
        else:
            i += 1
    try:
        rows = gold_rows(o["gold-file"])
    except (OSError, ValueError) as ex:
        print("cannot read gold set %s: %s" % (o["gold-file"], ex))
        return 2
    only = set(x for x in o["only"].split(",") if x)
    gates = set(x for x in o["gates"].split(",") if x)
    out, by_gate = [], {}
    for row in rows:
        if only and row.get("id") not in only:
            continue
        if gates and (row.get("gate", "none").split(":")[-1] not in gates):
            continue
        gate = row.get("gate", "none")
        res = None
        rd = qc.repo_dir(row["repo"]) if row.get("repo") else None
        if gate not in ("none",) and not gate.startswith("pending:"):
            if not rd:
                res = {"verdict": "UNVERIFIED", "summary": "no clone for repo %s" % row.get("repo"), "details": {}}
            else:
                res = run_gold_gate(row, rd, "--live-model" in argv)
        status, note = judge_gold(row, res)
        out.append({"id": row.get("id"), "gate": gate, "kind": row.get("kind"), "repo": row.get("repo"), "status": status, "note": note,
                    "verdict": (res or {}).get("verdict")})
        by_gate.setdefault(gate, {}).setdefault(status, 0)
        by_gate[gate][status] += 1
    print("gold replay (%s): %d row(s)" % (os.path.basename(o["gold-file"]), len(out)))
    for r in out:
        print("  %-4s %-26s %-21s %s" % (r["id"], r["gate"], r["status"], str(r["note"])[:110]))
    print("per gate:")
    for g, c in sorted(by_gate.items()):
        print("  %-26s %s" % (g, ", ".join("%s=%d" % kv for kv in sorted(c.items()))))
    tot = {}
    for r in out:
        tot[r["status"]] = tot.get(r["status"], 0) + 1
    summary = {"rows": len(out), "totals": tot, "by_gate": by_gate, "results": out}
    if "--json" in argv:
        print(json.dumps(summary, sort_keys=True))
    bad = tot.get("MISSED", 0) + tot.get("FALSE_POSITIVE", 0)
    return 1 if ("--strict" in argv and bad) else 0


def main(argv):
    if "--gold" in argv:
        return gold_main(argv)
    pos, o = parse(argv)
    if len(pos) != 2:
        print(__doc__)
        return 2
    gate_script, repo = pos
    rd = qc.repo_dir(repo)
    if not rd:
        print("no clone for repo %s" % repo)
        return 2
    gate = os.path.splitext(os.path.basename(gate_script))[0]
    args = ["log", "--no-merges", "--since=%d.days" % o["days"], "--format=%H", "-n", str(o["limit"]), o["branch"]]
    if o["author"]:
        args.insert(1, "--author=" + o["author"])
    rc, out, err = qc.git(rd, *args)
    if rc != 0:
        print("git log failed: " + err[:200])
        return 2
    shas = [s for s in out.split() if s]
    counts = collections.Counter()
    flagged, rows = [], []
    for sha in shas:
        base = sha + "^"
        if qc.git(rd, "rev-parse", "--verify", "-q", base)[0] != 0:
            continue
        cmd = [sys.executable, gate_script, "check", "--repo", repo, "--base", base, "--head", sha, "--no-record"] + (o["extra"].split() if o["extra"] else [])
        rc2, so, _ = qc.run(cmd, timeout=int(os.environ.get("QA_REPLAY_TIMEOUT", "300")), polite=True)
        try:
            res = json.loads(so.strip().splitlines()[-1])
        except Exception:  # noqa: BLE001
            res = {"verdict": "UNVERIFIED", "summary": "no parsable output (rc=%s)" % rc2, "details": {}}
        res["commit"] = sha
        counts[res.get("verdict", "UNVERIFIED")] += 1
        rows.append(res)
        if res.get("verdict") in ("FAIL", "FLAG"):
            subj = qc.git(rd, "log", "-1", "--format=%s", sha)[1].strip()
            flagged.append((sha[:10], res.get("verdict"), subj[:70], res.get("summary", "")[:110]))
    d = os.path.join(qc.state_dir(), "qa_replay")
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, "%s-%s.jsonl" % (gate, repo)), "w") as f:
        for r in rows:
            f.write(json.dumps(r, sort_keys=True) + "\n")
    n = sum(counts.values())
    print("replay %s on %s (%s, last %dd): %d commits" % (gate, repo, o["branch"], o["days"], n))
    for v in qc.VERDICTS:
        if counts[v]:
            print("  %-10s %4d  (%.1f%%)" % (v, counts[v], 100.0 * counts[v] / max(1, n)))
    for sha, v, subj, summ in flagged[: o["sample"]]:
        print("  %s %-5s %s | %s" % (sha, v, subj, summ))
    if len(flagged) > o["sample"]:
        print("  ... %d more flagged (full results: state/qa_replay/%s-%s.jsonl)" % (len(flagged) - o["sample"], gate, repo))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
