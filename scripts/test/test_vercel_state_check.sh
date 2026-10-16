#!/usr/bin/env bash
# vercel_state_check.py: prod not-live -> emergency push once; failing previews -> one note/day; healthy -> silent.
cd "$(dirname "$0")/../.." || exit 1
T=$(mktemp -d) || exit 1; trap 'rm -rf "$T"' EXIT
python3 - "$T" <<'PY'
import importlib.util, json, os, sys, time
T = sys.argv[1]
spec = importlib.util.spec_from_file_location("vsc", "vercel_state_check.py"); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
fails = []
def check(name, cond):
    print(("ok   " if cond else "FAIL ") + name); 
    if not cond: fails.append(name)
m.PROJECTS, m.STATE = ["p"], T + "/state.json"
m.token = lambda: "tok"
pushed = []
m.push = lambda title, body, urgent, dry: pushed.append((title, urgent))
now = int(time.time() * 1000)
def deps(*rows): return {"deployments": [dict(uid=u, createdAt=now, target=t, readyState=s, errorMessage="blocked: no git account") for u, t, s in rows]}
def mk(*rows):
    d = deps(*rows)
    return lambda tok, path: {"projects": [{"name": "p", "id": "p1"}]} if "/v9/projects" in path else d
m.api = mk(("d1", "production", "READY"), ("d2", None, "READY"))
m.main(); check("healthy -> no push", pushed == [])
m.api = mk(("d3", "production", "ERROR"), ("d4", None, "BLOCKED"))
m.main(); check("prod ERROR -> urgent push + preview note", ("Vercel PRODUCTION p: ERROR", True) in pushed and any(not u for _, u in pushed))
n = len(pushed); m.main(); check("same state again -> no duplicate pushes (dedupe)", len(pushed) == n)

# ---- 2026-10-12: transient GitHub secondary-rate-limit failures (git_info_fail) are retried, superseded/noise ones are silent -------------------------
redeployed = []
m.redeploy = lambda d, dry: (redeployed.append(d["uid"]) or True)
def D(uid, branch, state, age_s=600, target=None, code="", msg=""):
    return dict(uid=uid, url=uid + ".vercel.app", createdAt=int(time.time() * 1000 - age_s * 1000), target=target, readyState=state,
                errorCode=code, errorMessage=msg, meta={"githubCommitRef": branch, "githubCommitSha": uid})
RL = dict(code="git_info_fail", msg="GitHub fetch error - status: 403 ... You have exceeded a secondary rate limit")
def run(*rows, state=None):
    pushed.clear(); redeployed.clear()
    open(m.STATE, "w").write(json.dumps(state or {}))
    rows = list(rows)
    m.api = lambda tok, path: {"projects": [{"name": "p", "id": "p1"}]} if "/v9/projects" in path else {"deployments": rows}
    m.main()
    return json.load(open(m.STATE))
m.RETRY, m.MAX_RETRIES, m.RETRY_MIN_AGE_S = True, 2, 180
st_ = run(D("t1", "develop", "ERROR", 600, **RL))
check("transient ERROR on the newest develop deployment -> redeployed once, silent", redeployed == ["t1"] and pushed == [] and st_.get("retry_p_develop_t1") == 1)
run(D("t2", "develop", "ERROR", 600, **RL), D("ok", "develop", "READY", 300))
check("transient ERROR superseded by a later develop deployment -> NOT redeployed (an old sha would move the alias backwards), silent", redeployed == [] and pushed == [])
run(D("t3", "claude/feature", "ERROR", 600, **RL), D("t4", "overnight/feature", "ERROR", 600, msg="boom"))
check("failed previews of fleet-only branches are never reported or retried", redeployed == [] and pushed == [])
run(D("t5", "develop", "ERROR", 600, **RL), state={"retry_p_develop_t5": 2})
check("retries exhausted -> no further redeploy, ONE preview note", redeployed == [] and len(pushed) == 1 and not pushed[0][1])
run(D("t6", "develop", "ERROR", 60, **RL))
check("a fresh failure (< RETRY_MIN_AGE_S) is left alone for now: silent, no redeploy yet", redeployed == [] and pushed == [])
run(D("t7", "develop", "ERROR", 600, msg="Build failed: npm run build exited 1", code="build_failed"))
check("a real build failure on develop is NOT retried and IS reported", redeployed == [] and len(pushed) == 1)
run(D("t8", "main", "ERROR", 600, target="production", **RL))
check("production transient failure -> redeployed, NO emergency push while retries remain", redeployed == ["t8"] and pushed == [])
run(D("t9", "main", "ERROR", 600, target="production", **RL), state={"retry_p_production_t9": 2})
check("production transient failure with retries exhausted -> urgent push", redeployed == [] and len(pushed) == 1 and pushed[0][1])
run(D("t10", "main", "ERROR", 600, target="production", code="build_failed", msg="build broke"))
check("production real failure -> urgent push, never auto-redeployed", redeployed == [] and len(pushed) == 1 and pushed[0][1])
m.RETRY = False
run(D("t11", "develop", "ERROR", 600, **RL))
check("VSC_RETRY=off kill switch: no redeploy", redeployed == [])
m.RETRY = True
run(D("t12", "develop", "ERROR", 600, **RL), D("t13", "develop", "ERROR", 700, **RL))
check("two transient errors on one branch: only the newest is redeployed", redeployed == ["t12"])
# the redeploy chain: a redeploy gets a NEW uid but the same commit sha; if it fails with the same error the counter must carry over (bounded chain)
def D2(uid, sha, age_s, state_="ERROR"):
    d = D(uid, "develop", state_, age_s, **RL); d["meta"]["githubCommitSha"] = sha; return d
st_ = run(D2("c1", "shaX", 900))
check("chain step 1: first failure of sha X is redeployed", redeployed == ["c1"])
st_ = run(D2("c2", "shaX", 600), state=st_)
check("chain step 2: the redeploy (new uid, same sha) failed again -> second and LAST redeploy", redeployed == ["c2"])
st_ = run(D2("c3", "shaX", 600), state=st_)
check("chain step 3: a third failure of the same sha is NOT redeployed (bounded) and now raises the note", redeployed == [] and len(pushed) == 1)
st_ = run(D2("c4", "shaY", 600), state=st_)
check("a different commit gets its own retry budget", redeployed == ["c4"])
sys.exit(1 if fails else 0)
PY
