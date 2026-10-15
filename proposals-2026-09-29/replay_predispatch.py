#!/usr/bin/env python3
"""Replay ovn_predispatch.decide() over the last 7 days of outcomes (needs /tmp/g4.pkl from the
reconstruction step: per attempt -> repo, sha-before-cycle, reconstructed top item, status, dur).
Run from ~/overnight-queue:  python3 /tmp/proposals/replay_predispatch.py"""
import pickle, subprocess, collections, sys
sys.path.insert(0, "/tmp/proposals")
import ovn_predispatch as P
out = pickle.load(open("/tmp/g4.pkl", "rb"))
def git(repo, *a):
    return subprocess.run(["git", "-C", "repos/" + repo, *a], capture_output=True, text=True, errors="replace").stdout
class Tree:
    cache = {}
    def __init__(s, repo, sha):
        s.repo, s.sha = repo, sha
        k = (repo, sha)
        if k not in Tree.cache:
            Tree.cache[k] = set(git(repo, "ls-tree", "-r", "--name-only", sha).splitlines())
        s.files = Tree.cache[k]
    def __call__(s, p): return p in s.files
    def listdir(s, d):
        d = d.rstrip("/") + "/"
        return [f[len(d):] for f in s.files if f.startswith(d) and "/" not in f[len(d):]]
    def read(s, p): return git(s.repo, "show", "%s:%s" % (s.sha, p))
ad_first = {}
res = collections.defaultdict(list)
for o in out:
    o["landed"] = o["status"].startswith("pushed")
    if not (o["item"] and o["sha"] and o["conf"]):
        continue
    t = Tree(o["repo"], o["sha"])
    k = (o["repo"], P.item_key(o["item"]))
    seen = {k[1]} if k in ad_first else set()
    act, why = P.decide(o["item"], t, t.read, seen)
    if "ALREADY-DONE" in o["status"]:
        ad_first.setdefault(k, o["t"])
    if act != "ok":
        res[act + (':' + why.split(' ')[0] if act != 'delete' else '')].append(o)
last = out[-1]["t"]
print("attempts with confident item reconstruction:", sum(1 for o in out if o["conf"] and o["item"]))
for act, v in res.items():
    nl = [o for o in v if not o["landed"]]
    print("%-7s matched=%3d landed=%3d  non-landed min=%6.1f | last24h matched=%d min=%.1f" % (
        act, len(v), len(v) - len(nl), sum(o["dur"] for o in nl) / 60,
        sum(1 for o in v if o["t"] >= last - 86400), sum(o["dur"] for o in nl if o["t"] >= last - 86400) / 60))
    for o in v:
        if o["landed"] and '-v' in sys.argv:
            print("   landed-match:", o["repo"], o["ts"], o["status"], o["item"][:110])
