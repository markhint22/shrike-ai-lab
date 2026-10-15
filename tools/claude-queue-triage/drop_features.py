#!/usr/bin/env python3
"""Drop whole features by [feat:...] slug regex: tick every OPEN line of those features in OVERNIGHT_PROGRESS.md (via a temp worktree pushed non-force to
overnight/feature), so no sibling step stays eligible for the fleet. Backlog/roadmap copies on the box are handled by drop_features_box.py.
usage: drop_features.py <repo> <slug-regex> "<reason>" dry|apply"""
import os, re, shutil, subprocess, sys, time
repo, rx, reason, mode = sys.argv[1], re.compile(sys.argv[2]), sys.argv[3], sys.argv[4]
dry = mode != "apply"
CLONE = "/Users/mhintermeister/LocalProjects/" + repo
WT = "/tmp/wt-drop-" + repo


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
    hits, feats = [], {}
    for i, l in enumerate(L):
        if not l.startswith("- [ ] "):
            continue
        m = re.search(r"\[feat:([^\]]+)\]", l)
        if m and rx.search(m.group(1)):
            hits.append(i); feats[m.group(1)] = feats.get(m.group(1), 0) + 1
    print("%s: %d open line(s) in %d feature(s) match" % (repo, len(hits), len(feats)))
    for f, n in feats.items():
        print("   %d  %s" % (n, f[:70]))
    if dry or not hits:
        break
    for i in hits:
        L[i] = "- [x] (dropped 2026-10-07 by Mark's decision: %s) %s" % (reason, L[i][6:])
    open(p, "wb").write("\n".join(L).encode("utf-8", "surrogateescape"))
    nums = sh("git", "diff", "--numstat", cwd=WT).split()
    if nums[:2] != [str(len(hits))] * 2:
        raise SystemExit("unexpected diff %s" % nums)
    sh("git", "add", "OVERNIGHT_PROGRESS.md", cwd=WT)
    sh("git", "-c", "user.name=shrike-fleet", "-c", "user.email=22970726+markhint22@users.noreply.github.com", "-c", "commit.gpgsign=false", "commit", "-q", "-m",
       "chore(queue): drop %d line(s) in %d feature(s) by owner decision (%s)\n\nCo-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>" % (len(hits), len(feats), reason), cwd=WT)
    r = subprocess.run(["git", "push", "-q", "origin", "HEAD:overnight/feature"], cwd=WT, capture_output=True, text=True)
    if r.returncode == 0:
        print("pushed", sh("git", "rev-parse", "--short", "HEAD", cwd=WT).strip()); break
    print("push rejected, retrying"); time.sleep(3)
sh("git", "-C", CLONE, "worktree", "remove", "--force", WT, check=False); sh("git", "-C", CLONE, "worktree", "prune", check=False)
