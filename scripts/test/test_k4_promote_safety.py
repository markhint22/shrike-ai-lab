#!/usr/bin/env python3
"""K4 promote safety (2026-11-03): prod alembic 4-state verdict + snapshot file, migration note, staging-URL reader (+ OVN_STAGING_URL_REQUIRED),
promote_postcheck prod /health provenance + Vercel PRODUCTION state (ERROR => emergency path). Hermetic: temp git repo, injected fetchers, no network, no push.
Mutation proof: each rule is broken in a temp copy of qa/ and the scenarios must then FAIL.
  python3 test_k4_promote_safety.py [--qa DIR]    (the temp root comes from env K4_TMP, set by test_k4_promote_safety.sh)"""
import json
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OQ = os.path.abspath(os.path.join(HERE, "..", ".."))
QA = os.path.join(OQ, "qa")
if "--qa" in sys.argv:
    QA = sys.argv[sys.argv.index("--qa") + 1]
T = os.environ.get("K4_TMP", "")
if not T or not os.path.isdir(T):
    print("  FAIL: K4_TMP not set (run via test_k4_promote_safety.sh)")
    sys.exit(1)
os.environ.update(TZ="UTC", NTFY_SERVER="http://127.0.0.1:9", OVN_NOTIFY_DISABLE="1")
sub = os.path.join(T, "run_" + str(os.getpid()))
STATE, REPOS = os.path.join(sub, "state"), os.path.join(sub, "repos")
os.makedirs(STATE)
os.makedirs(REPOS)
os.makedirs(os.path.join(sub, "logs"))
os.environ.update(QA_STATE_DIR=STATE, OVN_DIR=sub, OVN_REPOS_DIR=REPOS)
sys.path.insert(0, QA)
import prod_alembic_check as pac  # noqa: E402
import prod_alembic_snapshot as pas  # noqa: E402
import promote_gate as pg  # noqa: E402
import promote_postcheck as pp  # noqa: E402
import vercel_prod_state as vps  # noqa: E402

P = F = 0


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
    else:
        F += 1
        print("  FAIL " + name + ((" :: " + str(extra)[:300]) if extra else ""))


def g(*a, cwd=None):
    r = subprocess.run(["git"] + list(a), cwd=cwd, capture_output=True, text=True,
                       env=dict(os.environ, GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t", GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@t"))
    return r.stdout.strip()


MIG = 'revision = "%s"\ndown_revision = %s\n'
# ---- temp repo "iptv_apps": main has 0001; candidate adds 0002
rd = os.path.join(REPOS, "iptv_apps")
os.makedirs(os.path.join(rd, "alembic", "versions"))
g("init", "-q", "-b", "main", cwd=rd)
open(os.path.join(rd, "alembic", "versions", "0001_a.py"), "w").write(MIG % ("0001_a", "None"))
g("add", "-A", cwd=rd)
g("commit", "-qm", "base", cwd=rd)
base = g("rev-parse", "HEAD", cwd=rd)
open(os.path.join(rd, "alembic", "versions", "0002_b.py"), "w").write(MIG % ("0002_b", '"0001_a"'))
open(os.path.join(rd, "app.py"), "w").write("x = 1\n")
g("add", "-A", cwd=rd)
g("commit", "-qm", "cand", cwd=rd)
cand = g("rev-parse", "HEAD", cwd=rd)

# ---- 1. classify (4 states)
revs = {"0001_a": [], "0002_b": ["0001_a"]}
ok("classify MATCH", pac.classify("0002_b", revs, [])[0] == "MATCH")
ok("classify BEHIND", pac.classify("0001_a", revs, [])[0] == "BEHIND", pac.classify("0001_a", revs, []))
ok("classify MISMATCH (prod not in history)", pac.classify("0099_x", revs, [])[0] == "MISMATCH")
ok("classify MISMATCH (revisionless file)", pac.classify("0001_a", revs, ["x.py"])[0] == "MISMATCH")
ok("classify UNVERIFIED (no prod)", pac.classify(None, revs, [])[0] == "UNVERIFIED")

# ---- 2. check_ref writes state/prod_alembic_snapshot_<repo>.json
os.makedirs(os.path.join(STATE, "prod_alembic"))
pac.cmd_record(["--repo", "iptv_apps", "--revision", "0001_a"])
r = pac.check_ref("iptv_apps", cand)
vp = os.path.join(STATE, "prod_alembic_snapshot_iptv_apps.json")
v = json.load(open(vp)) if os.path.exists(vp) else {}
ok("check_ref still PASS in the legacy verdict (shadow gate unchanged)", r["verdict"] == "PASS", r)
ok("verdict file BEHIND with head+prod", v.get("state") == "BEHIND" and v.get("candidate_head") == "0002_b" and v.get("prod_revision") == "0001_a", v)
pac.cmd_record(["--repo", "iptv_apps", "--revision", "0002_b"])
pac.check_ref("iptv_apps", cand)
ok("verdict file MATCH after prod catches up", json.load(open(vp)).get("state") == "MATCH")
pac.cmd_record(["--repo", "iptv_apps", "--revision", "9999_z"])
pac.check_ref("iptv_apps", cand)
ok("verdict file MISMATCH for a foreign prod revision", json.load(open(vp)).get("state") == "MISMATCH")
os.remove(os.path.join(STATE, "prod_alembic", "iptv_apps.json"))
pac.check_ref("iptv_apps", cand)
ok("verdict file UNVERIFIED without snapshot", json.load(open(vp)).get("state") == "UNVERIFIED")

# ---- 3. other repos skip with a reason
# Z6 (2026-11-09): billwatch is in PRODUCTION_URLS (6dba0c6), so it is no longer skipped: it fetches /health. The fetch is STUBBED here (no network, ever).
_calls = []
_orig_fetch = pas.fetch_health


def _fetch_down(url, timeout=15):
    _calls.append(url)
    return None, "request failed: URLError"


pas.fetch_health = _fetch_down
okb, msg = pas.refresh("billwatch")
ok("billwatch snapshot is attempted (handled, not skipped): fetch down => snapshot left untouched / UNVERIFIED",
   (not okb) and "health-has-no-revision" not in msg and "snapshot left untouched" in msg and len(_calls) == 1 and "billwatch" in _calls[0], (msg, _calls))
ok("billwatch fetch failure left NO snapshot file", not os.path.exists(os.path.join(STATE, "prod_alembic", "billwatch.json")))
pas.fetch_health = lambda url, timeout=15: ({"status": "ok"}, "ok")
okb, msg = pas.refresh("billwatch")
ok("billwatch /health without db_revision: untouched, reason named", (not okb) and "no db_revision" in msg and "snapshot left untouched" in msg, msg)
pas.fetch_health = lambda url, timeout=15: ({"db_revision": "b1_rev"}, "ok")
okb, msg = pas.refresh("billwatch", dry=True)
ok("billwatch /health with db_revision: dry run reports the revision, records nothing", okb and "b1_rev" in msg and "dry-run" in msg, msg)
_calls.clear()
okg, msgg = pas.refresh("zz_unknown_repo")
ok("an unknown repo is still skipped (health-has-no-revision) and never fetches", (not okg) and "health-has-no-revision" in msgg and not _calls, (msgg, _calls))
pas.fetch_health = _orig_fetch

# ---- 4. migration note
mig = pg.migrations_in_range(pac.qc.git, rd, base, cand)
ok("migrations_in_range lists the added revision", mig == ["alembic/versions/0002_b.py"], mig)
ok("migrations_in_range empty for a non-migration range", pg.migrations_in_range(pac.qc.git, rd, cand, cand) == [])
ll = pg.log_lines({"candidate": cand, "candidate_verdict": "PASS", "held_back": 0, "release_branch": "", "ff_main_possible": True, "mode": "enforce",
                   "staging_verdict": "PASS", "relation": "", "staging_commit": "", "provider": "", "summary": "", "block": False, "unverified": False,
                   "migrations_added": mig, "staging_url_note": "no state/staging_url_x: explained once"})
ok("log_lines carries [migrations] and [staging-url]", any(l.startswith("  [migrations] +1") and "0002_b.py" in l for l in ll) and any(l.startswith("  [staging-url]") for l in ll), ll)

# ---- 5. staging URL reader
sd = os.path.join(sub, "su")
os.makedirs(sd)
p1, n1 = pg.staging_url_state("iptv_apps", repos={"iptv_apps"}, state_dir=sd)
p2, n2 = pg.staging_url_state("iptv_apps", repos={"iptv_apps"}, state_dir=sd)
ok("absent URL: explained ONCE, not per run", (not p1) and "SKIPPED" in n1 and (not p2) and n2 == "", (n1, n2))
ok("repo without smoke config: no note", pg.staging_url_state("zzz", repos={"iptv_apps"}, state_dir=sd) == (False, ""))
open(os.path.join(sd, "staging_url_billwatch"), "w").write("https://x.up.railway.app\n")
ok("present URL is used", pg.staging_url_state("billwatch", repos={"billwatch"}, state_dir=sd) == (True, ""))
ok("required + absent + smoke repo => block", pg.url_blocks(False, True, "iptv_apps", {"iptv_apps"}) is True)
ok("required but present => no block", pg.url_blocks(True, True, "iptv_apps", {"iptv_apps"}) is False)
ok("not required (default) => never blocks", pg.url_blocks(False, False, "iptv_apps", {"iptv_apps"}) is False)
os.environ.pop("OVN_STAGING_URL_REQUIRED", None)
ok("flag default off", pg.staging_url_required() is False)
os.environ["OVN_STAGING_URL_REQUIRED"] = "1"
ok("flag on", pg.staging_url_required() is True)
os.environ.pop("OVN_STAGING_URL_REQUIRED")

# ---- 6. /health provenance (fixtures)
H_OK = {"status": "healthy", "commit": cand[:12], "db_revision": "0002_b", "alembic_head": "0002_b"}
H_OLD = {"status": "healthy", "commit": base[:12], "db_revision": "0001_a"}
H_NOFIELDS = {"status": "ok"}
ok("health OK", pp.health_compare(H_OK, cand, "0002_b")[0] == "OK")
st, msg = pp.health_compare(H_OLD, cand, "0002_b")
ok("health MISMATCH on stale commit AND db_revision", st == "MISMATCH" and "commit" in msg and "db_revision" in msg, msg)
ok("health MISMATCH on db_revision only", pp.health_compare({"commit": cand[:12], "db_revision": "0001_a"}, cand, "0002_b")[0] == "MISMATCH")
ok("health without fields is UNVERIFIED, never a mismatch", pp.health_compare(H_NOFIELDS, cand, "0002_b")[0] == "UNVERIFIED")
ok("candidate_head from the candidate tree", pp.candidate_head("iptv_apps", cand) == "0002_b")
pushes = []
pp.push_emergency = lambda t, b: pushes.append((t, b))
open(os.path.join(STATE, "alerts.log"), "w").close()
ok("health_stage: stale prod => MISMATCH + WARN, no push (shadow)",
   pp.health_stage("iptv_apps", cand, once=True, fetch=lambda u: (H_OLD, "ok")) == "MISMATCH"
   and "WARN" in open(os.path.join(STATE, "alerts.log")).read() and not pushes)
ok("health_stage: match => OK", pp.health_stage("iptv_apps", cand, once=True, fetch=lambda u: (H_OK, "ok")) == "OK")
ok("health_stage: unreachable => UNVERIFIED", pp.health_stage("iptv_apps", cand, once=True, fetch=lambda u: (None, "HTTP 502")) == "UNVERIFIED")
ok("health_stage: repo with no /health URL => NA", pp.health_stage("zz_unknown_repo", cand, once=True, fetch=lambda u: (H_OK, "ok")) == "NA")
# Z6: billwatch has a prod /health URL now (6dba0c6): it is judged (injected fetch, no network), no longer NA
ok("health_stage: billwatch is judged (unreachable => UNVERIFIED, not NA)", pp.health_stage("billwatch", cand, once=True, fetch=lambda u: (None, "HTTP 502")) == "UNVERIFIED")
os.environ["OVN_POSTCHECK_HEALTH_EMERGENCY"] = "on"
pp.health_stage("iptv_apps", cand, once=True, fetch=lambda u: (H_OLD, "ok"))
ok("health emergency flag on => push", len(pushes) == 1)
os.environ.pop("OVN_POSTCHECK_HEALTH_EMERGENCY")

# ---- 7. Vercel PRODUCTION state (fixture = Vercel /v6/deployments rows)
RAW = [{"uid": "dpl_new", "state": "ERROR", "created": 2_000_000_000_000, "target": "production", "meta": {"githubCommitSha": cand}},
       {"uid": "dpl_old", "state": "READY", "created": 1_000_000_000_000, "target": "production", "meta": {"githubCommitSha": base}}]
N = vps.normalize(RAW)
ok("normalize: newest first, sha/state parsed", N[0]["id"] == "dpl_new" and N[0]["state"] == "ERROR" and N[0]["sha"] == cand, N)
ok("evaluate ERROR => FAILED", vps.evaluate(N, cand)[0] == "FAILED")
ok("evaluate READY => SUCCESS", vps.evaluate(vps.normalize([dict(RAW[0], state="READY")]), cand)[0] == "SUCCESS")
ok("evaluate BUILDING => keep polling", vps.evaluate(vps.normalize([dict(RAW[0], state="BUILDING")]), cand)[0] is None)
ok("evaluate ignores another sha's ERROR", vps.evaluate(N, "f" * 40)[0] is None)
ok("evaluate ignores a pre-promote ERROR (since)", vps.evaluate(N, cand, since=2_000_000_100)[0] is None)
ok("evaluate: CANCELED (ignored build) is not an emergency", vps.evaluate(vps.normalize([dict(RAW[0], state="CANCELED")]), cand)[0] is None)
import time as _t
t_now = lambda: 2_000_000_000.0  # noqa: E731 - fixture clock: deployment created at that second
pushes.clear()
open(os.path.join(STATE, "alerts.log"), "w").close()
res = pp.vercel_stage("iptv_apps", cand, once=True, gather=lambda r: (N, "fixture"), now=t_now)
alog = open(os.path.join(STATE, "alerts.log")).read()
ok("vercel ERROR => FAILED + alerts.log ERROR + emergency push", res == "FAILED" and "ERROR" in alog and "VERCEL PRODUCTION" in alog and len(pushes) == 1 and "Vercel PROD" in pushes[0][0], (res, alog, pushes))
res2 = pp.vercel_stage("iptv_apps", cand, once=True, gather=lambda r: (N, "fixture"), now=t_now)
ok("vercel report deduped per (repo, sha)", res2 == "SKIP" and len(pushes) == 1)
pushes.clear()
ready = vps.normalize([dict(RAW[0], state="READY")])
ok("vercel READY => SUCCESS, no push", pp.vercel_stage("billwatch", "a" * 40, once=True, gather=lambda r: (vps.normalize([dict(RAW[0], state="READY", meta={"githubCommitSha": "a" * 40})]), "f"), now=t_now) == "SUCCESS" and not pushes)
ok("vercel not seen => UNVERIFIED (WARN, no push)", pp.vercel_stage("gitlark", "b" * 40, once=True, gather=lambda r: ([], "fixture"), now=t_now) == "UNVERIFIED" and not pushes)
ok("vercel: no evidence at all => UNVERIFIED", pp.vercel_stage("shrike-labs-website", "c" * 40, once=True, gather=lambda r: (None, "no file"), now=t_now) == "UNVERIFIED")
ok("vercel: repo without a Vercel project => NA", pp.vercel_stage("xlite", "d" * 40, once=True, gather=lambda r: (N, "f"), now=t_now) == "NA")

# regression: Vercel ERROR created at promote time must still be FAILED when the stage starts >SKEW after it (long Railway wait)
pushes.clear()
os.remove(os.path.join(STATE, "promote_postcheck", "iptv_apps_%s.done.vercel" % cand[:10])) if os.path.exists(os.path.join(STATE, "promote_postcheck", "iptv_apps_%s.done.vercel" % cand[:10])) else None
late = lambda: 2_000_000_000.0 + 1200  # noqa: E731 - stage starts 1200s after the ERROR deploy was created
pp.PROCESS_START = 2_000_000_000.0 - 5
res = pp.vercel_stage("iptv_apps", cand, once=True, gather=lambda r: (N, "fixture"), now=late)
ok("vercel: ERROR created 1200s before stage start (long Railway wait) is still FAILED + push", res == "FAILED" and len(pushes) == 1, (res, pushes))
pp.PROCESS_START = None
pushes.clear()

# ---- 8. main() wiring: stages run after the deploy check; kill switches; a Vercel-only repo does not wait on Railway
calls = []
_h, _v, _w = pp.health_stage, pp.vercel_stage, pp.watch
import threading as _th
pp.health_stage = lambda repo, sha, once=False: calls.append("health") or "OK"
pp.vercel_stage = lambda repo, sha, once=False: calls.append("vercel") or "SUCCESS"
pp.watch = lambda *a, **k: calls.append("railway") or "SUCCESS"
# concurrency: Vercel stage must start BEFORE a slow Railway watch finishes
ev = []
pp.vercel_stage = lambda repo, sha, once=False: ev.append("vercel") or "SUCCESS"
pp.watch = lambda *a, **k: (__import__("time").sleep(0.3), ev.append("railway_done"))[1] or "SUCCESS"
pp.main(["watch", "--repo", "iptv_apps", "--sha", "e" * 40, "--once"])
ok("main: Vercel stage runs concurrently with (not after) the Railway watch", ev == ["vercel", "railway_done"], ev)
calls.clear()
pp.vercel_stage = lambda repo, sha, once=False: calls.append("vercel") or "SUCCESS"
pp.watch = lambda *a, **k: calls.append("railway") or "SUCCESS"
pp.main(["watch", "--repo", "shrike-labs-website", "--sha", "e" * 40, "--once"])
ok("main: Vercel-only repo => health + vercel stages, NO Railway wait", sorted(calls) == ["health", "vercel"], calls)
calls.clear()
pp.main(["watch", "--repo", "iptv_apps", "--sha", "e" * 40, "--once"])
ok("main: Railway repo => railway first, then health, then vercel", calls.index("railway") < calls.index("health") and sorted(calls) == ["health", "railway", "vercel"], calls)
calls.clear()
os.environ["OVN_POSTCHECK_VERCEL"] = "off"
pp.main(["watch", "--repo", "iptv_apps", "--sha", "e" * 40, "--once"])
os.environ.pop("OVN_POSTCHECK_VERCEL")
ok("main: OVN_POSTCHECK_VERCEL=off skips only the vercel stage", sorted(calls) == ["health", "railway"], calls)
pp.health_stage, pp.vercel_stage, pp.watch = _h, _v, _w

print("test_k4_promote_safety: pass=%d fail=%d" % (P, F))
sys.exit(1 if F else 0)
