#!/usr/bin/env python3
"""qa_replay.py - replay a QA gate over historical commits to measure its flag rate / false positives WITHOUT new dev traffic.

usage: qa_replay.py <gate_script.py> <repo> [--days 14] [--limit 200] [--branch origin/develop] [--author SUBSTR]
                    [--sample 15] [--extra "--flag value"]

For every non-merge commit on <branch> in the window, runs
    python3 <gate_script> check --repo <repo> --base <commit>^ --head <commit> --no-record
and aggregates the verdicts. Prints a summary and writes every result to state/qa_replay/<gate>-<repo>.jsonl.
Read-only: it never modifies a repo. Gate stderr is discarded; a gate that crashes or times out counts as UNVERIFIED.
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


def main(argv):
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
