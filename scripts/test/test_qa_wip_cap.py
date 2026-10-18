#!/usr/bin/env python3
"""qa/wip_cap.py (Phase 5, shadow): per repo / class counts and ages of landed-but-not-yet-prod features against the plan's caps.

Fixtures: ledger records written straight into a temp state dir (and a throwaway git repo where the real prod-ref clearing is exercised). Time is injected for the pure
cases. Covers under / AT / OVER a repo cap, the global cap, the class A area cap, class C exemption, cleared / unattributed / unknown handling, median age, flag parsing
(off / shadow / soft / hard / garbage), the eligibility query, alert dedupe, hostile ledger lines, the real CLI entry point, and a MUTANT: the cap raised (or the alert
removed) in a copy of the code must make the over-cap scenario fail."""
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
OQ = os.path.abspath(os.path.join(HERE, "..", ".."))
QA = os.path.join(OQ, "qa")
PY = sys.executable
if not os.path.isfile(os.path.join(QA, "wip_cap.py")):
    print("  SKIP: qa/wip_cap.py not installed here")
    sys.exit(0)

P = F = 0


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name + ((" :: " + str(extra)[:400]) if extra else ""))


T = os.path.realpath(tempfile.mkdtemp(prefix="wipcap-test-"))
for k in list(os.environ):
    if k.startswith("OVN_QA_") or k in ("QA_STATE_DIR", "OVN_DIR", "OVN_REPOS_DIR"):
        os.environ.pop(k, None)
STATE = os.path.join(T, "state")
os.makedirs(STATE)
os.environ["QA_STATE_DIR"] = STATE
os.environ["OVN_REPOS_DIR"] = os.path.join(T, "repos")
os.makedirs(os.environ["OVN_REPOS_DIR"])


def load(path, name):
    d = os.path.dirname(path)
    if d not in sys.path:
        sys.path.insert(0, d)
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


WC = load(os.path.join(QA, "wip_cap.py"), "wip_cap_under_test")
NOW = 1_800_000_000
H = 3600


def rec(repo, i, risk="B", age_h=1.0, files=None, tag=True, commits=None, now=NOW):
    return {"kind": "landed", "key": "k-%s-%s-%s" % (repo, risk, i), "repo": repo, "ts": "2026-10-17T00:00:00Z", "epoch": int(now - age_h * H), "risk": risk, "tier": "2",
            "status": "pushed", "risk_basis": "t", "commit_basis": "time-window", "feat_tag": ("%s-feat-%s-%s" % (repo, risk, i)) if tag else "",
            "commits": ["%040x" % (hash((repo, risk, i)) & (2 ** 160 - 1))] if commits is None else commits, "subjects": [], "files": files if files is not None else ["src/%s.py" % i],
            "flags": []}


def pending(repo, n, risk="B", **kw):
    return [rec(repo, i, risk, **kw) for i in range(n)]


NONE_CLEARED = lambda repo, commits: False  # noqa: E731


def comp(recs, evs=(), cleared=NONE_CLEARED, now=NOW):
    return WC.compute(recs, list(evs), now, cleared)


# ---------------------------------------------------------------- 1. repo cap: under / at / over (billwatch cap 8)
for n, want in ((7, "UNDER"), (8, "AT"), (9, "OVER")):
    r = comp(pending("billwatch", n))["repos"]["billwatch"]
    ok("billwatch %d pending -> %s (cap 8)" % (n, want), r["state"] == want and r["behavioral"] == n and r["cap"] == 8, r)
ok("caps: gitlark/iptv_apps 8, TAA 12, others 15", [WC.caps()[0].get(x) for x in ("gitlark", "iptv_apps", "test-automation-agent")] == [8, 8, 12] and WC.caps()[1] == 15)
ok("cap_state pure", [WC.cap_state(a, 8) for a in (0, 7, 8, 9)] == ["UNDER", "UNDER", "AT", "OVER"])
ok("TAA cap is 12 (12 AT, 13 OVER)", comp(pending("test-automation-agent", 12))["repos"]["test-automation-agent"]["state"] == "AT"
   and comp(pending("test-automation-agent", 13))["repos"]["test-automation-agent"]["state"] == "OVER")
ok("an unlisted repo gets the default 15", comp(pending("shrike-labs-website", 15))["repos"]["shrike-labs-website"]["state"] == "AT")

# ---------------------------------------------------------------- 2. global cap (each repo under its own cap)
recs = []
for rp in ("r1", "r2", "r3", "r4", "r5", "r6"):
    recs += pending(rp, 7)
rep = comp(recs)
ok("global cap: 6 repos x 7 = 42 > 40 -> global OVER while every repo is UNDER", rep["global"]["state"] == "OVER" and rep["global"]["count"] == 42
   and all(r["state"] == "UNDER" for r in rep["repos"].values()), rep["global"])
rep = comp(recs[:35] + [])
ok("global 35 -> UNDER", rep["global"]["state"] == "UNDER")
rep = comp(sum([pending(rp, 8) for rp in ("r1", "r2", "r3", "r4", "r5")], []))
ok("global exactly 40 -> AT (not OVER)", rep["global"]["state"] == "AT" and rep["global"]["count"] == 40)

# ---------------------------------------------------------------- 3. class A area cap (8 per area)
aA = lambda n: [rec("xlite", i, "A", files=["backend/app/auth/login.py"]) for i in range(n)]  # noqa: E731
rep = comp(aA(9))
ar = rep["areas"].get("xlite:backend/app")
ok("class A area: 9 features in one area -> area OVER while the repo (cap 15) is UNDER", ar and ar["state"] == "OVER" and ar["count"] == 9 and rep["repos"]["xlite"]["state"] == "UNDER", rep["areas"])
ok("class A area: exactly 8 -> AT, not over", comp(aA(8))["areas"]["xlite:backend/app"]["state"] == "AT")
mix = [rec("xlite", i, "A", files=["backend/app/auth/x.py"]) for i in range(6)] + [rec("xlite", 100 + i, "A", files=["web/src/pay.ts"]) for i in range(6)]
rep = comp(mix)
ok("class A areas are counted separately", {k: v["count"] for k, v in rep["areas"].items()} == {"xlite:backend/app": 6, "xlite:web/src": 6}, rep["areas"])
ok("class B features never create an area bucket", comp(pending("xlite", 5, "B"))["areas"] == {})
ok("area_of skips tests and docs", WC.area_of(["tests/test_a.py", "README.md", "app/svc/x.py"]) == "app/svc" and WC.area_of(["tests/t.py"]) == "")

# ---------------------------------------------------------------- 4. class C exempt, class mix, features grouping
rep = comp(pending("billwatch", 20, "C"))["repos"]["billwatch"]
ok("class C (tests/docs) is reported but never counted toward a cap", rep["state"] == "UNDER" and rep["behavioral"] == 0 and rep["by_class"]["C"] == 20, rep)
r = comp(pending("billwatch", 3, "A") + pending("billwatch", 4, "B") + pending("billwatch", 2, "C"))["repos"]["billwatch"]
ok("by_class counts A/B/C and behavioral = A+B", r["by_class"] == {"A": 3, "B": 4, "C": 2} and r["behavioral"] == 7, r)
two = [rec("billwatch", 1, "B"), dict(rec("billwatch", 2, "A"), feat_tag="billwatch-feat-B-1", key="k-second")]
r = comp(two)["repos"]["billwatch"]
ok("two records with one feat tag are ONE feature, class = the highest", r["behavioral"] == 1 and r["by_class"]["A"] == 1, r)
t1 = [dict(rec("billwatch", i, "B"), feat_tag="") for i in range(3)]
ok("records without a tag are separate features", comp(t1)["repos"]["billwatch"]["behavioral"] == 3)

# ---------------------------------------------------------------- 5. cleared / unattributed / unknown
r = comp(pending("billwatch", 5), cleared=lambda repo, c: True)["repos"]["billwatch"]
ok("features already in prod are not WIP", r["behavioral"] == 0 and r["cleared"] == 5, r)
r = comp(pending("billwatch", 5), cleared=lambda repo, c: None)["repos"]["billwatch"]
ok("unknown (no clone / no prod ref) is never counted and never OVER", r["behavioral"] == 0 and r["unknown"] == 5 and r["state"] == "UNDER", r)
r = comp([rec("billwatch", i, "B", commits=[]) for i in range(12)])["repos"]["billwatch"]
ok("no attributed commit -> unattributed, not counted", r["behavioral"] == 0 and r["unattributed"] == 12 and r["state"] == "UNDER", r)
rs = pending("billwatch", 9)
r = comp(rs, evs=[{"kind": "event", "type": "gated", "rec": rs[0]["key"], "key": "g1", "repo": "billwatch", "epoch": NOW}])["repos"]["billwatch"]
ok("a 'gated' ledger event clears its feature (9 -> 8 = AT)", r["behavioral"] == 8 and r["state"] == "AT" and r["cleared"] == 1, r)
r = comp(rs, evs=[{"kind": "event", "type": "revert", "rec": rs[0]["key"], "key": "g2", "repo": "billwatch", "epoch": NOW}])["repos"]["billwatch"]
ok("other event types do not clear", r["behavioral"] == 9)
old = [rec("billwatch", 1, "B", age_h=40 * 24)]
ok("records older than the window (30 d) are ignored", "billwatch" not in comp(old)["repos"])

# ---------------------------------------------------------------- 6. ages
r = comp([rec("billwatch", 1, "B", age_h=2), rec("billwatch", 2, "B", age_h=4), rec("billwatch", 3, "B", age_h=10)])["repos"]["billwatch"]
ok("median age 4.0 h, oldest 10.0 h", r["median_age_h"] == 4.0 and r["oldest_age_h"] == 10.0, r)
r = comp([rec("billwatch", 1, "B", age_h=2), rec("billwatch", 2, "B", age_h=4)])["repos"]["billwatch"]
ok("even count -> mean of the middle two", r["median_age_h"] == 3.0)
ok("no behavioral pending -> age None", comp(pending("billwatch", 2, "C"))["repos"]["billwatch"]["median_age_h"] is None)

# ---------------------------------------------------------------- 7. flag parsing + env overrides
def with_env(**kv):
    class C(object):
        def __enter__(s):
            s.old = {k: os.environ.get(k) for k in kv}
            for k, v in kv.items():
                if v is None:
                    os.environ.pop(k, None)
                else:
                    os.environ[k] = v

        def __exit__(s, *a):
            for k, v in s.old.items():
                if v is None:
                    os.environ.pop(k, None)
                else:
                    os.environ[k] = v
    return C()


for val, want in ((None, "shadow"), ("", "shadow"), ("off", "off"), ("shadow", "shadow"), ("soft", "soft"), ("hard", "hard"), ("HARD", "hard"), ("enforce", "shadow"), ("banana", "shadow")):
    with with_env(OVN_QA_WIP_CAP=val):
        ok("OVN_QA_WIP_CAP=%r -> %s" % (val, want), WC.mode() == want, WC.mode())
with with_env(OVN_QA_WIP_CAP_REPOS="billwatch=3,bad name=2,xlite=zzz", OVN_QA_WIP_CAP_GLOBAL="5", OVN_QA_WIP_CAP_AREA="2"):
    rep = comp(pending("billwatch", 4) + pending("xlite", 2))
    ok("env overrides: repo cap 3 (4 -> OVER), global 5 (6 -> OVER), junk entries ignored", rep["repos"]["billwatch"]["state"] == "OVER" and rep["repos"]["xlite"]["cap"] == 15
       and rep["global"]["state"] == "OVER" and rep["global"]["cap"] == 5, rep["global"])

# ---------------------------------------------------------------- 8. eligibility (the dispatcher's question; nothing calls it yet)
over = comp(pending("billwatch", 9))
at = comp(pending("billwatch", 8))
under = comp(pending("billwatch", 3))
ok("shadow: always eligible, would_hold reported", WC.eligibility(over, "billwatch", "B", "", "shadow")["eligible"] is True and WC.eligibility(over, "billwatch", "B", "", "shadow")["would_hold"] is True)
ok("off: always eligible", WC.eligibility(over, "billwatch", "B", "", "off")["eligible"] is True)
ok("soft: OVER holds class B", WC.eligibility(over, "billwatch", "B", "", "soft")["eligible"] is False)
ok("soft: AT holds class A", WC.eligibility(at, "billwatch", "A", "", "soft")["eligible"] is False)
ok("soft: UNDER is eligible", WC.eligibility(under, "billwatch", "B", "", "soft")["eligible"] is True)
ok("soft: class C is never held", WC.eligibility(over, "billwatch", "C", "", "soft")["eligible"] is True)
ok("soft: an unrelated repo is not held", WC.eligibility(over, "xlite", "B", "", "soft")["eligible"] is True)
ok("manual override lifts the hold", WC.eligibility(over, "billwatch", "B", "", "hard", override=True)["eligible"] is True)
g = comp(sum([pending(rp, 8) for rp in ("r1", "r2", "r3", "r4", "r5")], []))
ok("hard: global at cap holds an otherwise-under repo; soft does not", WC.eligibility(dict(g), "r1", "B", "", "hard")["eligible"] is False and WC.eligibility(under, "billwatch", "B", "", "soft")["eligible"] is True)
ok("hard: global cap holds a repo that is not in the report", WC.eligibility(g, "newrepo", "B", "", "hard")["eligible"] is False and WC.eligibility(g, "newrepo", "B", "", "soft")["eligible"] is True)
arep = comp(aA(8))
ok("hard: class A area at cap holds a class A item in that area only", WC.eligibility(arep, "xlite", "A", "backend/app", "hard")["eligible"] is False
   and WC.eligibility(arep, "xlite", "A", "web/src", "hard")["eligible"] is True and WC.eligibility(arep, "xlite", "A", "backend/app", "soft")["eligible"] is True)

# ---------------------------------------------------------------- 9. end to end through git (real prod-ref clearing), alerts, log rows, dedupe
RD = os.path.join(T, "repos", "billwatch")
os.makedirs(RD)


def git(*a):
    env = dict(os.environ, GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t", GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@t")
    return subprocess.run(["git", "-C", RD] + list(a), env=env, capture_output=True, text=True, check=True).stdout.strip()


git("init", "-q", "-b", "main")
open(os.path.join(RD, "a.txt"), "w").write("base\n")
git("add", "a.txt")
git("commit", "-q", "-m", "base")
BASE = git("rev-parse", "HEAD")
git("checkout", "-q", "-b", "dev")
shas = []
for i in range(10):
    open(os.path.join(RD, "f%d.txt" % i), "w").write("x%d\n" % i)
    git("add", "-A")
    git("commit", "-q", "-m", "feat: %d" % i)
    shas.append(git("rev-parse", "HEAD"))
git("checkout", "-q", "main")
os.environ["OVN_QA_WIP_PROD_REF"] = "main"
sys.path.insert(0, QA)
import qa_ledger as ql  # noqa: E402


def write_ledger(records):
    p = os.path.join(STATE, "qa_ledger.jsonl")
    if os.path.exists(p):
        os.unlink(p)
    ql.append_lines(records)


def e2e_recs(n, risk="B"):
    now = int(time.time())
    return [dict(rec("billwatch", i, risk, now=now, age_h=1 + i), commits=[shas[i]]) for i in range(n)]


def alerts():
    p = os.path.join(STATE, "alerts.log")
    return open(p).read().splitlines() if os.path.exists(p) else []


for n, want_alerts in ((7, 0), (8, 0), (9, 1)):
    for f in ("alerts.log", "phase5_alerted.json"):
        if os.path.exists(os.path.join(STATE, f)):
            os.unlink(os.path.join(STATE, f))
    write_ledger(e2e_recs(n))
    out = WC.cmd_run([])
    al = [l for l in alerts() if "wip-cap:repo:billwatch" in l]
    ok("e2e git: %d pending -> %d alert line(s), state %s" % (n, want_alerts, out["repos"]["billwatch"]["state"]), len(al) == want_alerts and out["mode"] == "shadow", (out, al))
ok("alert line format (WARN, tag, counts, says nothing is throttled)", al and al[0].split("] ", 1)[1].startswith("WARN | wip-cap:repo:billwatch | ") and "9 > cap 8" in al[0] and "nothing throttled" in al[0], al)
out = WC.cmd_run([])
ok("same-day rerun does not repeat the alert", len([l for l in alerts() if "wip-cap:repo:billwatch" in l]) == 1 and out["alerts"] == 0)
rows = [json.loads(l) for l in open(os.path.join(STATE, "qa_shadow", "wip_cap.jsonl"))]
rr = [r for r in rows if r["kind"] == "repo" and r["repo"] == "billwatch"][-1]
ok("log rows: repo row carries class counts, ages, cap, state, mode", rr["state"] == "OVER" and rr["by_class"]["B"] == 9 and rr["cap"] == 8 and rr["mode"] == "shadow" and rr["median_age_h"] is not None, rr)
ok("log rows: a global row is written", any(r["kind"] == "global" for r in rows))
# promote commits 0..4 to main: they are cleared
git("merge", "-q", "--ff-only", shas[4])
write_ledger(e2e_recs(9))
out = WC.cmd_run(["--no-record"])
ok("git clearing: 5 of 9 commits reachable from the prod ref -> 4 pending", out["repos"]["billwatch"]["behavioral"] == 4, out["repos"])
ok("--no-record writes no row and no alert", len(rows) == len([json.loads(l) for l in open(os.path.join(STATE, "qa_shadow", "wip_cap.jsonl"))]))
with with_env(OVN_QA_WIP_PROD_REF="no-such-ref"):
    out = WC.cmd_run(["--no-record"])
    ok("missing prod ref -> unknown, nothing counted", out["repos"]["billwatch"]["behavioral"] == 0 and out["over"] == [])
git("update-ref", "refs/heads/main", BASE)       # back to nothing promoted
git("reset", "-q", "--hard", "main")
write_ledger(e2e_recs(9))
for f in ("alerts.log", "phase5_alerted.json"):
    if os.path.exists(os.path.join(STATE, f)):
        os.unlink(os.path.join(STATE, f))
size = os.path.getsize(os.path.join(STATE, "qa_shadow", "wip_cap.jsonl"))
with with_env(OVN_QA_WIP_CAP="off"):
    out = WC.cmd_run([])
    ok("off: nothing computed, written or alerted", out["mode"] == "off" and not alerts() and os.path.getsize(os.path.join(STATE, "qa_shadow", "wip_cap.jsonl")) == size)
with with_env(OVN_QA_WIP_CAP="hard"):
    out = WC.cmd_run([])
    ok("hard is parsed but only alerts (no throttling side effect, still just a log + alert)", out["mode"] == "hard" and out["alerts"] >= 0 and not os.path.exists(os.path.join(STATE, "wip_cap_state.json")))

# ---------------------------------------------------------------- 10. hostile ledger
with open(os.path.join(STATE, "qa_ledger.jsonl"), "ab") as f:
    f.write(b'\x00\x00 not json\n[1,2]\n{"kind":"landed","key":5}\n{"kind":"landed"\n')
try:
    out = WC.cmd_run(["--no-record"])
    ok("hostile / torn ledger lines never crash the observer", "repos" in out)
except Exception as ex:  # noqa: BLE001
    ok("hostile / torn ledger lines never crash the observer", False, ex)

# ---------------------------------------------------------------- 11. real CLI entry points (env -i), always exit 0
env = {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "QA_STATE_DIR": STATE, "OVN_REPOS_DIR": os.environ["OVN_REPOS_DIR"], "OVN_QA_WIP_PROD_REF": "main", "HOME": T}
write_ledger(e2e_recs(9))
p = subprocess.run([PY, os.path.join(QA, "wip_cap.py"), "report"], env=env, capture_output=True, text=True)
ok("CLI report: exit 0, table lists billwatch OVER", p.returncode == 0 and "billwatch" in p.stdout and "OVER" in p.stdout, p.stdout + p.stderr)
p = subprocess.run([PY, os.path.join(QA, "wip_cap.py"), "eligible", "--repo", "billwatch"], env=env, capture_output=True, text=True)
ok("CLI eligible in shadow: last line ELIGIBLE although over cap, would_hold true", p.returncode == 0 and p.stdout.strip().splitlines()[-1] == "ELIGIBLE" and '"would_hold": true' in p.stdout, p.stdout)
p = subprocess.run([PY, os.path.join(QA, "wip_cap.py"), "eligible", "--repo", "billwatch"], env=dict(env, OVN_QA_WIP_CAP="soft"), capture_output=True, text=True)
ok("CLI eligible in soft: HOLD (query only, nothing wired)", p.returncode == 0 and p.stdout.strip().splitlines()[-1] == "HOLD", p.stdout)
open(os.path.join(STATE, "wip_cap_override_billwatch"), "w").write("x")
p = subprocess.run([PY, os.path.join(QA, "wip_cap.py"), "eligible", "--repo", "billwatch"], env=dict(env, OVN_QA_WIP_CAP="soft"), capture_output=True, text=True)
ok("CLI eligible: override file lifts the hold", p.stdout.strip().splitlines()[-1] == "ELIGIBLE", p.stdout)
p = subprocess.run([PY, os.path.join(QA, "wip_cap.py"), "eligible", "--repo", "../x"], env=env, capture_output=True, text=True)
ok("CLI eligible: a hostile repo name is answered ELIGIBLE, exit 0", p.returncode == 0 and p.stdout.strip().splitlines()[-1] == "ELIGIBLE")
p = subprocess.run([PY, os.path.join(QA, "wip_cap.py"), "run"], env=dict(env, QA_STATE_DIR=os.path.join(T, "nonexistent", "x")), capture_output=True, text=True)
ok("CLI run on an empty state dir: exit 0, valid JSON", p.returncode == 0 and isinstance(json.loads(p.stdout.strip().splitlines()[-1]), dict), p.stdout + p.stderr)

# ---------------------------------------------------------------- 11b. the cron wrapper (wip_cap + gpu_ledger), real entry point, always exit 0
OVN = os.path.join(T, "ovn_cron")
os.makedirs(os.path.join(OVN, "state"))
os.makedirs(os.path.join(OVN, "repos"))
shutil.copytree(os.path.join(os.environ["OVN_REPOS_DIR"], "billwatch"), os.path.join(OVN, "repos", "billwatch"), symlinks=True)
import qa_ledger as ql2  # noqa: E402
cenv = {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "OVN_DIR": OVN, "OVN_REPOS_DIR": os.path.join(OVN, "repos"), "OVN_QA_WIP_PROD_REF": "main", "HOME": T}
with with_env(QA_STATE_DIR=os.path.join(OVN, "state")):
    ql2.append_lines(e2e_recs(9))
cenv_run = dict(cenv, QA_STATE_DIR=os.path.join(OVN, "state"))
p = subprocess.run(["bash", os.path.join(QA, "phase5_cron.sh")], env=cenv_run, capture_output=True, text=True)
ok("phase5_cron.sh: exit 0, wip_cap row + alert and gpu_ledger rows written, log lines present",
   p.returncode == 0 and os.path.exists(os.path.join(OVN, "state", "qa_shadow", "wip_cap.jsonl")) and os.path.exists(os.path.join(OVN, "state", "qa_shadow", "gpu_ledger.jsonl"))
   and "wip-cap:repo:billwatch" in open(os.path.join(OVN, "state", "alerts.log")).read() and "wip_cap" in open(os.path.join(OVN, "logs", "phase5_cron.log")).read(), p.stdout + p.stderr)
p = subprocess.run(["bash", os.path.join(QA, "phase5_cron.sh")], env=dict(cenv_run, OVN_QA_WIP_CAP="off", OVN_QA_GPU_LEDGER="off"), capture_output=True, text=True)
ok("phase5_cron.sh with both flags off: exit 0", p.returncode == 0)
ok("phase5_cron.sh is executable in the tree (cron would fail with Permission denied otherwise)", os.access(os.path.join(QA, "phase5_cron.sh"), os.X_OK))

# ---------------------------------------------------------------- 11c. review fixes: docstring-only churn is not behavioral WIP
def drec(repo, i, subjects, category="", risk="B", files=None):
    return dict(rec(repo, i, risk), subjects=subjects, category=category, files=files if files is not None else ["src/mod%d.py" % i])


docs = [drec("gitlark", i, ["docs: add docstring to to_dict methods in connector models"]) for i in range(12)] + [drec("gitlark", 20 + i, ["style: tidy imports"], category="python") for i in range(5)]
r = comp(docs)["repos"]["gitlark"]
ok("17 docs:/style: docstring commits on source paths -> class C, behavioral 0, state UNDER (cap 8)", r["behavioral"] == 0 and r["by_class"]["C"] == 17 and r["state"] == "UNDER", r)
ok("no cap alert scope for docstring churn", WC.over_scopes(comp(docs)) == [])
mix = docs + [drec("gitlark", 40 + i, ["feat: add endpoint %d" % i]) for i in range(3)]
r = comp(mix)["repos"]["gitlark"]
ok("real behavioral commits still count next to the docstring churn (3 B)", r["behavioral"] == 3 and r["by_class"]["B"] == 3, r)
one = comp([drec("gitlark", 1, ["docs: add docstring", "fix: real bug in the same feature"])])["repos"]["gitlark"]
ok("a feature with ONE behavioral subject among docs commits stays behavioral", one["behavioral"] == 1, one)
ok("class A docstring commits (auth path) are not behavioral either", comp([drec("billwatch", 1, ["docs: document login flow"], risk="A", files=["backend/auth/login.py"])])["repos"]["billwatch"]["behavioral"] == 0)
ok("category docs with no commit subjects is non-behavioral; category endpoint with no subjects is behavioral",
   comp([drec("gitlark", 1, [], category="docs")])["repos"]["gitlark"]["behavioral"] == 0 and comp([drec("gitlark", 2, [], category="endpoint")])["repos"]["gitlark"]["behavioral"] == 1)
ok("conventional scoped / bang forms: docs(api): x, test!: y, chore(deps): z are non-behavioral; feat(x): is behavioral",
   all(WC.NON_BEHAVIORAL_SUBJECT.match(x) for x in ("docs(api): x", "test!: y", "chore(deps): z", "Docs: X")) and not WC.NON_BEHAVIORAL_SUBJECT.match("feat(x): y") and not WC.NON_BEHAVIORAL_SUBJECT.match("fix: docs typo"))
rep_docs = comp(docs)
with with_env(OVN_QA_WIP_CAP="soft"):
    ok("soft mode: docstring churn does NOT hold the repo's behavioral items", WC.eligibility(rep_docs, "gitlark", "B", "", "soft")["eligible"] is True)

# ---------------------------------------------------------------- 11d. survivors: git clearing needs ALL commits, the since window, min landing epoch
RDw = os.path.join(T, "repos", "wcgit")
os.makedirs(RDw)


def gitw(*a, date=None):
    env = dict(os.environ, GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t", GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@t")
    if date:
        env["GIT_COMMITTER_DATE"] = env["GIT_AUTHOR_DATE"] = "%d +0000" % date
    return subprocess.run(["git", "-C", RDw] + list(a), env=env, capture_output=True, text=True, check=True).stdout.strip()


SINCE = 1_700_000_000
gitw("init", "-q", "-b", "main")
open(os.path.join(RDw, "a"), "w").write("1")
gitw("add", "-A")
gitw("commit", "-q", "-m", "ancient", date=SINCE - 3 * 86400)         # older than the margin
open(os.path.join(RDw, "a"), "w").write("2")
gitw("add", "-A")
gitw("commit", "-q", "-m", "in prod", date=SINCE - 43200)             # 12 h BEFORE the window start: inside the 24 h safety margin
in_prod = gitw("rev-parse", "HEAD")
gc = WC.GitClearing(SINCE)
ok("GitClearing: a commit 12 h before the window start is still seen (the 24 h margin is subtracted, not added)", gc("wcgit", [in_prod]) is True, gc.sets)
gc2 = WC.GitClearing(SINCE)
gc2.sets["r"] = {"aaa"}
ok("GitClearing: a feature is cleared only when ALL its commits are in prod (a partial set is NOT cleared)", gc2("r", ["aaa", "bbb"]) is False and gc2("r", ["aaa"]) is True and gc2("zz-no-clone", ["aaa"]) is None)
two = [dict(rec("billwatch", 1, "B", age_h=10), feat_tag="same"), dict(rec("billwatch", 2, "B", age_h=2), feat_tag="same")]
feats = WC.build_features(two)
ok("a feature's landing epoch is the EARLIEST of its records (age counts from the first landing)", len(feats) == 1 and feats[0]["epoch"] == NOW - 10 * H and comp(two)["repos"]["billwatch"]["oldest_age_h"] == 10.0, feats)

# ---------------------------------------------------------------- 11e. alert_once: concurrent manual runs emit ONE line; atomic_write mode
import phase5_common as p5c  # noqa: E402
for f in ("alerts.log", "phase5_alerted.json"):
    if os.path.exists(os.path.join(STATE, f)):
        os.unlink(os.path.join(STATE, f))
code = "import sys, time; sys.path.insert(0, sys.argv[1]); import phase5_common as p; sys.stdout.write(str(p.alert_once('WARN', 'wip-cap:x', 'm', 'k-conc', 1800000000)))"
for f in ("alerts.log", "phase5_alerted.json"):
    if os.path.exists(os.path.join(STATE, f)):
        os.unlink(os.path.join(STATE, f))
procs = [subprocess.Popen([PY, "-I", "-c", code, QA], env={"PATH": os.environ.get("PATH", ""), "QA_STATE_DIR": STATE}, stdout=subprocess.PIPE, text=True) for _ in range(8)]
outs = [pr.communicate()[0] for pr in procs]
ok("8 concurrent alert_once calls for one dedupe key write exactly ONE alerts.log line", outs.count("True") == 1 and len(alerts()) == 1, (outs, alerts()))
import fcntl  # noqa: E402
os.unlink(os.path.join(STATE, "alerts.log")) if os.path.exists(os.path.join(STATE, "alerts.log")) else None
if os.path.exists(os.path.join(STATE, "phase5_alerted.json")):
    os.unlink(os.path.join(STATE, "phase5_alerted.json"))
lockf = open(os.path.join(STATE, "phase5_alerted.lock"), "a")
fcntl.flock(lockf, fcntl.LOCK_EX)
holder = subprocess.Popen([PY, "-I", "-c", code, QA], env={"PATH": os.environ.get("PATH", ""), "QA_STATE_DIR": STATE}, stdout=subprocess.PIPE, text=True)
time.sleep(1.5)
blocked = holder.poll() is None and not alerts()
fcntl.flock(lockf, fcntl.LOCK_UN)
lockf.close()
out_h = holder.communicate(timeout=30)[0]
ok("alert_once waits on the phase5_alerted.lock flock while another process holds it, then writes its one line", blocked and out_h == "True" and len(alerts()) == 1, (blocked, out_h, alerts()))
p5c.atomic_write(os.path.join(STATE, "mode_test.txt"), "x")
ok("atomic_write files are 0644 (not mkstemp's 0600)", oct(os.stat(os.path.join(STATE, "mode_test.txt")).st_mode & 0o777) == "0o644")

# ---------------------------------------------------------------- 11b. OVN_QA_WIP_CAP_SCOPE: repos that are never promoted must not alert forever
_mixed = pending("xlite", 21) + pending("billwatch", 3)
ok("scope unset: every repo counted (xlite OVER, global counts both)", comp(_mixed)["repos"]["xlite"]["state"] == "OVER" and comp(_mixed)["global"]["count"] == 24)
os.environ["OVN_QA_WIP_CAP_SCOPE"] = "billwatch,iptv_apps"
try:
    _rs = comp(_mixed)
    ok("scope set: xlite is not counted, not alerted, and not in the global count", "xlite" not in _rs["repos"] and _rs["global"]["count"] == 3 and WC.over_scopes(_rs) == [], _rs["global"])
    ok("scope set: an in-scope repo still alerts over its cap", WC.over_scopes(comp(pending("billwatch", 9) + pending("xlite", 30))) == [("repo:billwatch", 9, 8)])
    ok("scope set: eligibility of an out-of-scope repo is eligible (no row)", WC.eligibility(_rs, "xlite", "B", "", "soft")["eligible"] is True)
finally:
    del os.environ["OVN_QA_WIP_CAP_SCOPE"]
ok("scope garbage entries are ignored (falls back to all repos)", (os.environ.__setitem__("OVN_QA_WIP_CAP_SCOPE", "../x, ") or WC.scope_repos()) is None)
del os.environ["OVN_QA_WIP_CAP_SCOPE"]

# ---------------------------------------------------------------- 12. MUTANT: raise the cap / remove the alert in a COPY and the over-cap scenario must fail
SCEN = r'''
import os, sys, json
sys.path.insert(0, sys.argv[1])
import wip_cap as wc
def rec(i):
    return {"kind":"landed","key":"k%d"%i,"repo":"billwatch","ts":"2026-10-17T00:00:00Z","epoch":1799990000,"risk":"B","tier":"2","status":"p","risk_basis":"t","commit_basis":"t",
            "feat_tag":"f%d"%i,"commits":["%040x"%i],"subjects":[],"files":["a/b%d.py"%i],"flags":[]}
rep = wc.compute([rec(i) for i in range(9)], [], 1800000000, lambda r, c: False)
over = wc.over_scopes(rep)
print(json.dumps({"state": rep["repos"]["billwatch"]["state"], "over": [o[0] for o in over]}))
'''


def scenario(moddir):
    p = subprocess.run([PY, "-I", "-c", SCEN, moddir], capture_output=True, text=True, env={"PATH": os.environ.get("PATH", ""), "QA_STATE_DIR": STATE})
    try:
        d = json.loads(p.stdout.strip().splitlines()[-1])
    except (ValueError, IndexError):
        return None
    return d["state"] == "OVER" and d["over"] == ["repo:billwatch"]


def mutate(label, old, new):
    d = os.path.join(T, "mut_" + label)
    os.makedirs(d)
    for f in ("wip_cap.py", "qa_common.py", "qa_ledger.py", "phase5_common.py"):
        shutil.copy(os.path.join(QA, f), os.path.join(d, f))
    s = open(os.path.join(d, "wip_cap.py")).read()
    if old not in s:
        return None
    open(os.path.join(d, "wip_cap.py"), "w").write(s.replace(old, new, 1))
    return scenario(d)


ok("mutant control: the unmodified code passes the over-cap scenario", scenario(QA) is True)
ok("MUTANT cap raised (billwatch 8 -> 80): over-cap scenario FAILS", mutate("cap", '"billwatch": 8', '"billwatch": 80') is False)
ok("MUTANT comparison weakened (n > cap -> n > cap + 100): over-cap scenario FAILS", mutate("cmp", "    if n > cap:", "    if n > cap + 100:") is False)
ok("MUTANT over_scopes drops repos: alert scope list FAILS", mutate("scopes", 'if r["state"] == "OVER"]', 'if r["state"] == "NEVER"]') is False)
SCOPE_SCEN = SCEN.replace("rep = wc.compute(", "os.environ['OVN_QA_WIP_CAP_SCOPE'] = 'xlite'\nrep = wc.compute(").replace('rep["repos"]["billwatch"]["state"]', 'rep["repos"].get("billwatch", {}).get("state", "OUT")')


def scope_scenario(moddir):
    p = subprocess.run([PY, "-I", "-c", SCOPE_SCEN, moddir], capture_output=True, text=True, env={"PATH": os.environ.get("PATH", ""), "QA_STATE_DIR": STATE})
    try:
        d = json.loads(p.stdout.strip().splitlines()[-1])
    except (ValueError, IndexError):
        return None
    return d["state"] == "OUT" and d["over"] == []


ok("scope scenario control: billwatch out of scope -> not counted, no alert", scope_scenario(QA) is True)
_sd = os.path.join(T, "mut_scope"); os.makedirs(_sd)
for _f in ("wip_cap.py", "qa_common.py", "qa_ledger.py", "phase5_common.py"):
    shutil.copy(os.path.join(QA, _f), os.path.join(_sd, _f))
_src = open(os.path.join(_sd, "wip_cap.py")).read()
_needle = "(scope is None or r[\"repo\"] in scope)"
_ok_needle = _needle in _src
if _ok_needle:
    open(os.path.join(_sd, "wip_cap.py"), "w").write(_src.replace(_needle, "True", 1))
ok("MUTANT scope filter removed: the out-of-scope repo is counted again, scenario FAILS", _ok_needle and scope_scenario(_sd) is False)
ok("mutation strings really match the source (a stale needle would pass silently)", mutate("n1", '"billwatch": 8', '"billwatch": 8') is True)

shutil.rmtree(T, ignore_errors=True) if os.path.basename(T).startswith("wipcap-test-") else None
print("\nPASS=%d FAIL=%d" % (P, F))
sys.exit(1 if F else 0)
