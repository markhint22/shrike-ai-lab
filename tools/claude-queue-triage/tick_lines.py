#!/usr/bin/env python3
"""Apply per-line queue decisions to OVERNIGHT_PROGRESS.md by TEXT ANCHOR (never by line number: the fleet edits the file constantly).
Pushed non-force to overnight/feature via a temp worktree (same mechanics as drop_features.py).
usage: tick_lines.py <repo> <decisions.json> dry|apply
decisions.json: {"tick": [{"anchor": "<substring of the open line>", "reason": "..."}], "drop": [...]}
  tick  -> '- [x] (already-satisfied 2026-10-09: <reason>) ...'   (the work exists; verified by the caller)
  drop  -> '- [x] (dropped 2026-10-09: <reason>) ...'              (obsolete / contradicts current code / harmful to land)
An anchor must match 1..3 OPEN lines ('- [ ] '); 0 matches (already handled) is reported and skipped, >3 is refused (too ambiguous)."""
import json, os, re, shutil, subprocess, sys, time
repo, dec_path, mode = sys.argv[1], sys.argv[2], sys.argv[3]
dry = mode != "apply"
dec = json.load(open(dec_path))
CLONE = "/Users/mhintermeister/LocalProjects/" + repo
WT = "/tmp/wt-tick-" + repo


def sh(*a, cwd=None, check=True):
    r = subprocess.run(a, cwd=cwd, capture_output=True, text=True)
    if check and r.returncode:
        raise SystemExit("%s -> %s" % (" ".join(a), r.stderr[:200]))
    return r.stdout


for attempt in range(5):
    sh("git", "-C", CLONE, "fetch", "-q", "origin", "overnight/feature")
    sh("git", "-C", CLONE, "worktree", "remove", "--force", WT, check=False); shutil.rmtree(WT, ignore_errors=True)
    sh("git", "-C", CLONE, "worktree", "add", "-q", "--detach", WT, "origin/overnight/feature")
    p = os.path.join(WT, "OVERNIGHT_PROGRESS.md")
    L = open(p, "rb").read().decode("utf-8", "surrogateescape").split("\n")
    changed, report = 0, []
    for kind, label in (("tick", "already-satisfied"), ("drop", "dropped")):
        for d in dec.get(kind, []):
            idx = [i for i, l in enumerate(L) if l.startswith("- [ ] ") and d["anchor"] in l]
            if not idx:
                report.append("SKIP (no open match) %s: %s" % (kind, d["anchor"][:60])); continue
            if len(idx) > 3:
                report.append("REFUSED (%d matches) %s: %s" % (len(idx), kind, d["anchor"][:60])); continue
            for i in idx:
                L[i] = "- [x] (%s 2026-10-09: %s) %s" % (label, d.get("reason", "owner decision"), L[i][6:])
                changed += 1
            report.append("%s x%d: %s" % (kind, len(idx), d["anchor"][:60]))
    print("\n".join(report)); print("%s: %d line(s) would change" % (repo, changed))
    if dry or not changed:
        break
    open(p, "wb").write("\n".join(L).encode("utf-8", "surrogateescape"))
    nums = sh("git", "diff", "--numstat", cwd=WT).split()
    if nums[:2] != [str(changed)] * 2:
        raise SystemExit("unexpected diff %s" % nums)
    sh("git", "add", "OVERNIGHT_PROGRESS.md", cwd=WT)
    sh("git", "-c", "user.name=shrike-fleet", "-c", "user.email=22970726+markhint22@users.noreply.github.com", "-c", "commit.gpgsign=false", "commit", "-q", "-m",
       "chore(queue): %d line decision(s) by anchor (tick/drop) - Claude triage 2026-10-09\n\nCo-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>" % changed, cwd=WT)
    r = subprocess.run(["git", "push", "-q", "origin", "HEAD:overnight/feature"], cwd=WT, capture_output=True, text=True)
    if r.returncode == 0:
        print("pushed", sh("git", "rev-parse", "--short", "HEAD", cwd=WT).strip()); break
    print("push rejected, retrying"); time.sleep(3)
sh("git", "-C", CLONE, "worktree", "remove", "--force", WT, check=False); sh("git", "-C", CLONE, "worktree", "prune", check=False)
