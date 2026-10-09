#!/usr/bin/env python3
"""replay_migrations.py - measure gate_migrations on REAL history: the last N non-merge commits of <branch> that touch a repo's
models / migrations (and optionally API surface), one gate run per commit (base = commit^, head = commit).

usage: replay_migrations.py <repo> [--n 20] [--branch origin/develop] [--paths models|api|both] [--extra "--prodshape stress"]
                            [--out FILE.jsonl]
(qa_replay.py replays by time window and cannot filter by path; this one picks commits by path so every run is a relevant one.)
Prints a table (sha, verdict, ms, per-step verdicts) and runtime p50/p90. Read-only: gates use detached worktrees + a throwaway
container. Writes results to --out (default state/qa_replay/gate_migrations-<repo>-paths.jsonl); nothing is recorded to the shadow log.
"""
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import qa_common as qc  # noqa: E402
import gate_migrations as gm  # noqa: E402


def pct(xs, p):
    xs = sorted(xs)
    return xs[min(len(xs) - 1, int(round(p * (len(xs) - 1))))] if xs else 0


def main(argv):
    if not argv:
        print(__doc__)
        return 2
    repo, o, i = argv[0], {"n": "20", "branch": "origin/develop", "paths": "models", "extra": "", "out": ""}, 1
    while i < len(argv):
        if argv[i].startswith("--") and argv[i][2:] in o and i + 1 < len(argv):
            o[argv[i][2:]] = argv[i + 1]
            i += 2
        else:
            i += 1
    cfg = gm.repos_config()[repo]
    rd = qc.repo_dir(cfg.get("clone", repo))
    bd = cfg["backend_dir"]
    specs = []
    if o["paths"] in ("models", "both"):
        specs += ["%s/app/models" % bd, "%s/app/models.py" % bd, "%s/alembic" % bd]
    if o["paths"] in ("api", "both"):
        specs += ["%s/app/schemas" % bd, "%s/app/routers" % bd, "%s/app/api" % bd, "%s/app/routes" % bd]
    rc, out, err = qc.git(rd, "log", "--no-merges", "--format=%H", "-n", o["n"], o["branch"], "--", *specs)
    shas = out.split()
    rows, times = [], []
    for sha in shas:
        cmd = [sys.executable, os.path.join(HERE, "gate_migrations.py"), "check", "--repo", repo, "--base", sha + "^", "--head", sha, "--no-record"]
        if o["extra"]:
            cmd += o["extra"].split()
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=1800)
        try:
            res = json.loads(r.stdout.strip().splitlines()[-1])
        except Exception:  # noqa: BLE001
            res = {"verdict": "UNVERIFIED", "summary": "no parsable output", "details": {}, "ms": 0}
        res["commit"] = sha
        res["subject"] = qc.git(rd, "log", "-1", "--format=%s", sha)[1].strip()[:80]
        rows.append(res)
        if res.get("verdict") != "NA":
            times.append(res.get("ms") or 0)
        steps = " ".join("%s=%s" % (s["step"][:5], s["verdict"][:4]) for s in res.get("details", {}).get("steps", []) if s["verdict"] != "NA")
        print("%s %-10s %6dms %s | %s" % (sha[:10], res["verdict"], res.get("ms") or 0, steps, res["subject"][:50]))
        if res["verdict"] in ("FAIL", "FLAG", "UNVERIFIED"):
            print("      -> " + res.get("summary", "")[:300])
        sys.stdout.flush()
    outp = o["out"] or os.path.join(qc.state_dir(), "qa_replay", "gate_migrations-%s-%s.jsonl" % (repo, o["paths"]))
    os.makedirs(os.path.dirname(outp), exist_ok=True)
    with open(outp, "w") as f:
        for r_ in rows:
            f.write(json.dumps(r_, sort_keys=True) + "\n")
    counts = {}
    for r_ in rows:
        counts[r_["verdict"]] = counts.get(r_["verdict"], 0) + 1
    print("replay %s %s (%s): %d commits %s; runtime p50=%.1fs p90=%.1fs max=%.1fs (non-NA runs: %d)" % (
        repo, o["paths"], o["branch"], len(rows), counts, pct(times, 0.5) / 1000, pct(times, 0.9) / 1000, max(times or [0]) / 1000, len(times)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
