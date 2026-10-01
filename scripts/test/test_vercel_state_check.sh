#!/usr/bin/env bash
# vercel_state_check.py: prod not-live -> emergency push once; failing previews -> one note/day; healthy -> silent.
cd "$(dirname "$0")/../.." || exit 1
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
python3 - "$T" <<'PY'
import importlib.util, json, os, sys, time
T = sys.argv[1]
spec = importlib.util.spec_from_file_location("vsc", "vercel_state_check.py"); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
fails = []
def check(name, cond):
    print(("ok   " if cond else "FAIL ") + name); 
    if not cond: fails.append(name)
os.makedirs(T + "/p/.vercel"); json.dump({"projectId": "p1", "orgId": "o1"}, open(T + "/p/.vercel/project.json", "w"))
m.LOCAL, m.PROJECTS, m.STATE = T, ["p"], T + "/state.json"
m.token = lambda: "tok"
pushed = []
m.push = lambda title, body, urgent, dry: pushed.append((title, urgent))
now = int(time.time() * 1000)
def deps(*rows): return {"deployments": [dict(uid=u, createdAt=now, target=t, readyState=s, errorMessage="blocked: no git account") for u, t, s in rows]}
m.api = lambda tok, path: deps(("d1", "production", "READY"), ("d2", None, "READY"))
m.main(); check("healthy -> no push", pushed == [])
m.api = lambda tok, path: deps(("d3", "production", "ERROR"), ("d4", None, "BLOCKED"))
m.main(); check("prod ERROR -> urgent push + preview note", ("Vercel PRODUCTION p: ERROR", True) in pushed and any(not u for _, u in pushed))
n = len(pushed); m.main(); check("same state again -> no duplicate pushes (dedupe)", len(pushed) == n)
sys.exit(1 if fails else 0)
PY
