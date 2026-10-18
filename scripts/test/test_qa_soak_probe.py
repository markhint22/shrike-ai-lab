#!/usr/bin/env python3
"""Tests for qa/soak_probe.py (Phase 4 soak probe + per-candidate summary) and the shadow soak read in qa/promote_gate.py. Stdlib only, hermetic: a loopback stub
server with scripted failure modes stands in for staging; HOME/TMPDIR/QA_STATE_DIR are private temp dirs (the .sh wrapper sets TMPDIR via lib_safe_tmp.sh)."""
import json, os, subprocess, sys, tempfile, time
import os as _o, sys as _s; _s.path.insert(0, _o.path.dirname(_o.path.abspath(__file__))); import tmp_track; tmp_track.install()   # 2026-10-17: every mkdtemp() below is removed at exit (the suite leaked these dirs)

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
QA = os.path.join(ROOT, "qa")
sys.path.insert(0, QA)
P = F = 0


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name + ((" :: " + str(extra)[:300]) if extra else ""))


T = tempfile.mkdtemp(prefix="soak-test-")
STATE = os.path.join(T, "state")
os.makedirs(STATE)
os.environ.update({"QA_STATE_DIR": STATE, "OVN_DIR": T, "HOME": T, "QA_SMOKE_ALLOW_LOCAL": "1"})
for k in ("OVN_QA_SOAK", "OVN_QA_SOAK_MIN_HOURS", "OVN_QA_SOAK_ENFORCE_REPOS", "OVN_SOAK_SLOW_MS"):
    os.environ.pop(k, None)

import qa_common as qc            # noqa: E402
import staging_smoke as ss        # noqa: E402
import soak_probe as sp           # noqa: E402
import promote_gate as pg         # noqa: E402
import deploy_drill as dd         # noqa: E402

EMAIL, PW = "soak-test@example.com", "S0ak-Test-Pw-" + str(os.getpid())
os.environ["QA_SMOKE_DRILL_EMAIL"], os.environ["QA_SMOKE_DRILL_PASSWORD"] = EMAIL, PW
CONF = dd.drill_config()
CFG, DFL = CONF["repos"][dd.REPO], CONF["defaults"]
stub = dd.StubStaging(EMAIL, PW).start()


def probe(mode, candidate="", slow_ms=None, **kw):
    stub.mode = mode
    return sp.sample(dd.REPO, stub.base, CFG, DFL, candidate=candidate, slow_threshold_ms=slow_ms, **kw)


print("== one sample per scripted staging mode: PASS only on the clean stub")
r = probe("clean", CAND := dd.CAND_SHA)
ok("clean stub: PASS", r["verdict"] == "PASS", r["summary"])
names = [s["name"] for s in r["details"]["steps"]]
ok("steps: health, provenance, login, ONE business endpoint, write_read, cors", names[0] == "health" and "provenance" in names and "login" in names
   and sum(1 for n in names if n.startswith("business")) == 1 and any(n.startswith("write_read") for n in names) and any(n.startswith("cors") for n in names), names)
ok("latency recorded per request (p50/max/n_requests), no 5xx", r["details"]["n_requests"] >= 8 and r["details"]["latency_max_ms"] is not None and r["details"]["n_5xx"] == 0, r["details"])
ok("every synthetic write is tagged soak-<hhmmss>-<hex> and was cleaned up", r["details"]["marker"].startswith("soak-") and stub.notes == {}, (r["details"]["marker"], stub.notes))
ok("served build recorded from /health", r["details"]["sha"] == dd.CAND_SHA and r["details"]["sha_source"] == "health")
ok("no anonymous-guard / frontend step in a probe (one business endpoint only)", not any("anonymous" in n or n == "frontend" for n in names), names)
for mode, why in (("stale_sha", "STALE"), ("health_500", "HTTP 500"), ("cors_missing", "allow-origin"), ("bad_readback", "read-back")):
    r = probe(mode, CAND)
    ok("%s: FAIL (shadow-recorded verdict, never PASS)" % mode, r["verdict"] == "FAIL" and why in r["summary"], r["summary"])
    ok("%s: at least one error signature recorded" % mode, len(r["details"]["signatures"]) >= 1, r["details"]["signatures"])
r = probe("health_500", CAND)
ok("health_500: the 5xx is counted and signed as METHOD path -> 5xx", r["details"]["n_5xx"] >= 1 and "GET /health -> 5xx" in r["details"]["signatures"], r["details"])
r = probe("boom", CAND)
ok("a 5xx on the business endpoint is counted", r["verdict"] == "FAIL" and r["details"]["n_5xx"] == 1 and "GET /api/items -> 5xx" in r["details"]["signatures"], r["details"])
r = probe("slow", CAND, slow_ms=60)
ok("slow: FLAG (not PASS) with details.slow", r["verdict"] in ("FLAG", "FAIL") and r["verdict"] != "PASS" and r["details"]["slow"], (r["verdict"], r["summary"]))
ok("slow: FLAG specifically, and the summary names the slowest request", r["verdict"] == "FLAG" and "SLOW" in r["summary"], r["summary"])
r = probe("slow", CAND)
ok("the slow threshold default (8000ms) does not flag a 0.12s stub", r["verdict"] == "PASS" and not r["details"]["slow"], r["summary"])
r = probe("clean", "")
ok("no --candidate: no provenance step, still PASS", r["verdict"] == "PASS" and "provenance" not in [s["name"] for s in r["details"]["steps"]])
ok("skip={cors}: the preflight is not sent (drill mutant hook)", "cors" not in " ".join(s["name"] for s in probe("clean", CAND, skip=("cors",))["details"]["steps"]))

print("== credentials never printed or recorded")
stub.mode = "clean"
res = probe("clean", CAND)
blob = json.dumps(res)
ok("password and bearer token are absent from the result", PW not in blob and "stub-token-" not in blob and "stub-token" not in blob, blob[:200])
env = {"PATH": os.environ["PATH"], "HOME": T, "TMPDIR": os.environ.get("TMPDIR", T), "QA_STATE_DIR": STATE, "OVN_DIR": T, "QA_SMOKE_ALLOW_LOCAL": "1",
       "QA_SMOKE_DRILL_EMAIL": EMAIL, "QA_SMOKE_DRILL_PASSWORD": PW}
cfgp = os.path.join(T, "smoke.conf")
json.dump(CONF, open(cfgp, "w"))
p = subprocess.run([sys.executable, os.path.join(QA, "soak_probe.py"), "probe", "--repo", dd.REPO, "--base-url", stub.base, "--config", cfgp, "--candidate", dd.CAND_SHA],
                   env=env, capture_output=True, text=True, timeout=60)
logtxt = open(sp.log_path()).read() if os.path.exists(sp.log_path()) else ""
ok("CLI probe: exit 0, one JSON line, PASS", p.returncode == 0 and json.loads(p.stdout.strip().splitlines()[-1])["verdict"] == "PASS", p.stdout[-300:] + p.stderr[-300:])
ok("CLI probe: stdout, stderr and state/qa_shadow/soak.jsonl contain neither the password nor a token", PW not in p.stdout + p.stderr + logtxt and "stub-token" not in p.stdout + p.stderr + logtxt)
rows = sp.read_rows(dd.REPO)
ok("CLI probe: exactly one row recorded, gate=soak, timestamped", len(rows) == 1 and rows[0]["gate"] == "soak" and rows[0]["_t"] > 0, rows)

print("== URL allow-list: no write (or any request) to a non-staging host")
before = len(stub.hits)
os.environ["QA_SMOKE_ALLOW_LOCAL"] = "0"
r = sp.sample(dd.REPO, stub.base, CFG, DFL)
ok("loopback without QA_SMOKE_ALLOW_LOCAL=1 is REFUSED, UNVERIFIED, and the stub saw zero requests", r["verdict"] == "UNVERIFIED" and "REFUSING" in r["summary"] and len(stub.hits) == before, r["summary"])
os.environ["QA_SMOKE_ALLOW_LOCAL"] = "1"
calls = []
orig = ss.http
ss.http = lambda *a, **k: (calls.append(a[:2]) or (0, {}, "", "Boom"))
try:
    for host in ("https://app-production.up.railway.app", "https://api.production.example.com", "https://example-staging.example.com", "https://staging.up.railway.app.evil.example",
                 "https://billwatch.vercel.app", "http://169.254.169.254"):
        r = sp.sample(dd.REPO, host, CFG, DFL)
        ok("refused: %s (UNVERIFIED, no request attempted)" % host, r["verdict"] == "UNVERIFIED" and "REFUSING" in r["summary"] and r["details"].get("refused"), r["summary"])
    ok("no HTTP call at all was made for any refused URL", calls == [], calls)
finally:
    ss.http = orig
import contextlib, io
with contextlib.redirect_stdout(io.StringIO()):
    sp.main(["probe", "--repo", dd.REPO, "--base-url", "https://app-production.up.railway.app", "--config", cfgp])
ok("a refused CLI probe is not recorded in soak.jsonl", len(sp.read_rows(dd.REPO)) == 1)
ok("an accepted Railway staging host passes the allow-list check", ss.is_staging("https://billwatch-staging.up.railway.app"))

print("== no credentials => UNVERIFIED (never PASS)")
for k in ("QA_SMOKE_DRILL_EMAIL", "QA_SMOKE_DRILL_PASSWORD"):
    os.environ.pop(k)
r = probe("clean", CAND)
ok("no creds: UNVERIFIED", r["verdict"] == "UNVERIFIED" and "credentials not provisioned" in r["summary"], r["summary"])
os.environ["QA_SMOKE_DRILL_EMAIL"], os.environ["QA_SMOKE_DRILL_PASSWORD"] = EMAIL, PW
r = sp.sample(dd.REPO, "http://127.0.0.1:1", CFG, DFL)
ok("nothing listening: UNVERIFIED (infra is never FAIL)", r["verdict"] == "UNVERIFIED", r["summary"])

print("== probe: dependent steps, the prod frontend, the shared-account race, the restore, the candidate")
os.environ["OVN_SOAK_RETRY_SLEEP_S"] = "0"
stub.hits.clear()
r = probe("health_500", CAND)
ok("a failed health skips every dependent step and sends NOTHING else (login/business/write/cors)", [h[1] for h in stub.hits] == ["/health"]
   and {x["name"] for x in r["details"]["steps"]} >= {"health", "login", "business", "write_read", "cors"}
   and all(x["status"] == "skip" for x in r["details"]["steps"] if x["name"] != "health"), (stub.hits, r["details"]["steps"]))
cfg_fe = json.loads(json.dumps(CFG))
cfg_fe["frontend"] = {"url": stub.base + "/prod-frontend-asset", "contains": "x"}
stub.hits.clear(); stub.mode = "clean"
r = sp.sample(dd.REPO, stub.base, cfg_fe, DFL, candidate=dd.CAND_SHA)
ok("the PROD frontend asset is never requested by a probe (the probe has no frontend step; cfg 'frontend' is dropped as defence in depth)", not any("prod-frontend-asset" in h[1] for h in stub.hits) and "frontend" not in [x["name"] for x in r["details"]["steps"]], stub.hits)
ok("norm_detail strips shas, long numbers and soak tags: the same failure signs the same across samples",
   sp.norm_detail("soak-101010-ab12 write lost 1234567 deadbeef1234") == sp.norm_detail("soak-202020-cd34 write lost 7654321 cafebabe5678") and "<sha>" in sp.norm_detail("sha deadbeef1234") and sp.norm_detail("soak-101010-ab12 x") == "soak-<tag> x", sp.norm_detail("soak-101010-ab12 x"))
ok("norm_detail collapses 4-6 digit numbers (ports, ids, ms) to N", sp.norm_detail("timed out after 12345 ms on port 8080") == sp.norm_detail("timed out after 54321 ms on port 9090") == "timed out after N ms on port N")
s1 = sp.step_signatures([{"name": "write_read: x", "status": "fail", "detail": "write NOT visible soak-111111-aaaa 1234567"}], [])
s2 = sp.step_signatures([{"name": "write_read: x", "status": "fail", "detail": "write NOT visible soak-222222-bbbb 7654321"}], [])
ok("step_signatures: per-sample markers/ids do not make a new signature each time", s1 == s2 and len(s1) == 1, (s1, s2))
# an overlapping QA writer loses OUR read-back once: one retry with a fresh marker recovers; a real read-back failure fails twice
stub.mode = "readback_once"; stub.lost_left = 1; stub.hits.clear()
r = probe("readback_once", CAND)
ok("a read-back lost to one overlapping writer is retried ONCE and the sample is PASS (recorded in write_read_retry)", r["verdict"] == "PASS" and (r["details"]["write_read_retry"] or {}).get("recovered") is True, (r["verdict"], r["summary"], r["details"]["write_read_retry"]))
stub.hits.clear()
r = probe("bad_readback", CAND)
ok("a REAL read-back failure fails twice: still FAIL, retried exactly once (2 writes)", r["verdict"] == "FAIL" and sum(1 for h in stub.hits if h == ("POST", "/api/notes")) == 2
   and r["details"]["write_read_retry"]["recovered"] is False, (r["summary"], stub.hits))
orig_retry = sp._retry_write_read_race
sp._retry_write_read_race = lambda *a, **k: None
stub.mode = "readback_once"; stub.lost_left = 1
r = sp.sample(dd.REPO, stub.base, CFG, DFL, candidate=dd.CAND_SHA)
sp._retry_write_read_race = orig_retry
ok("mutant (retry removed): the same overlap is a FAIL, so the retry test above is not vacuous", r["verdict"] == "FAIL", r["summary"])
# the billwatch write restores the canonical display name; the cleanup carries a body
bw = ss.load_config(os.path.join(QA, "staging_smoke.conf"))["repos"]["billwatch"]["write_read"]
ok("staging_smoke.conf billwatch write_read has a restore cleanup (PATCH display_name back to 'QA Smoke')", bw.get("cleanup", {}).get("body") == {"display_name": "QA Smoke"} and bw["cleanup"]["method"] == "PATCH", bw)
cfg_cl = json.loads(json.dumps(CFG))
cfg_cl["write_read"]["cleanup"] = {"method": "PATCH", "path": "/api/notes/{id}", "body": {"display_name": "QA Smoke"}}
seen = []
real_http = ss.http
ss.http = lambda m, u, *a, **k: (seen.append((m, u.rsplit("/", 2)[-2:], k.get("body"))) or real_http(m, u, *a, **k))
stub.mode = "clean"
sp.sample(dd.REPO, stub.base, cfg_cl, DFL)
ss.http = real_http
ok("a cleanup 'body' is actually sent (the restore reaches the server)", any(m == "PATCH" and b == {"display_name": "QA Smoke"} for m, _, b in seen), seen)
# candidate: auto = develop head of the repo clone
import shutil
RP = os.path.join(T, "repos")
os.makedirs(os.path.join(RP, "autorepo"))
gitenv = dict(os.environ, GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@e.x", GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@e.x", HOME=T)
subprocess.run("git init -q . && git commit -q --allow-empty -m x && git update-ref refs/remotes/origin/develop HEAD", shell=True, cwd=os.path.join(RP, "autorepo"), env=gitenv, check=True)
head = subprocess.run(["git", "rev-parse", "HEAD"], cwd=os.path.join(RP, "autorepo"), capture_output=True, text=True).stdout.strip()
os.environ["OVN_REPOS_DIR"] = RP
ok("resolve_candidate('auto') = origin/develop head of the repo clone", sp.resolve_candidate("autorepo", "auto") == head and len(head) == 40, (sp.resolve_candidate("autorepo", "auto"), head))
ok("an explicit SHA wins; no flag means no candidate (back-compat); unknown repo / OVN_SOAK_CANDIDATE_REF=off give no candidate",
   sp.resolve_candidate("autorepo", "abc1234") == "abc1234" and sp.resolve_candidate("autorepo", "") == "" and sp.resolve_candidate("nope", "auto") == "")
os.environ["OVN_SOAK_CANDIDATE_REF"] = "off"
ok("OVN_SOAK_CANDIDATE_REF=off disables auto", sp.resolve_candidate("autorepo", "auto") == "")
os.environ.pop("OVN_SOAK_CANDIDATE_REF"); os.environ.pop("OVN_REPOS_DIR")
# the outage repro from the review, end to end through real probe rows
print("-- end to end: clean samples, then a dead staging, through the real probe")
T0 = 1_800_000_000.0
rows_e2e = []
for i in range(9):
    stub.mode = "clean"
    x = sp.sample(dd.REPO, stub.base, CFG, DFL, candidate=dd.CAND_SHA, ts=T0 + i * 900)
    x["_t"] = T0 + i * 900
    rows_e2e.append(x)
for i in range(2):
    x = sp.sample(dd.REPO, "http://127.0.0.1:1", CFG, DFL, candidate=dd.CAND_SHA, ts=T0 + (9 + i) * 900)
    x["_t"] = T0 + (9 + i) * 900
    rows_e2e.append(x)
ok("probe of a dead staging records UNVERIFIED with no served sha (the shape the review reproduced)", rows_e2e[-1]["verdict"] == "UNVERIFIED" and rows_e2e[-1]["details"]["sha"] == "", rows_e2e[-1])
sm = sp.summarize(rows_e2e, dd.REPO, dd.CAND_SHA, now=T0 + 8 * 900 + 3 * 3600, is_anc=lambda a, b: a == b, min_h=2.0)
ok("summary over those REAL rows 3 h after the last clean sample: not PASS, HOLD, stale", sm["verdict"] == "FLAG" and sm["decision"] == "HOLD" and sm["stale"], sm)
sm = sp.summarize(rows_e2e[:9], dd.REPO, dd.CAND_SHA, now=T0 + 8 * 900 + 60, is_anc=lambda a, b: a == b, min_h=2.0)
ok("the same clean rows read right away: PASS", sm["verdict"] == "PASS", sm)

print("== summary: per-candidate soak over synthetic rows")
C, OLD = "c" * 40, "d" * 40
T0 = 1_800_000_000.0


def row(i, verdict="PASS", sha=C, cand="", sigs=(), slow=False, repo="r", step=900):
    return {"gate": "soak", "repo": repo, "verdict": verdict, "_t": T0 + i * step, "ts": "x",
            "details": {"sha": sha, "candidate": cand, "signatures": list(sigs), "slow": slow}}


def summ(rows, **k):
    # `now` = one minute after the newest row unless given: a soak is judged while it is current (the recency tests pass `now` explicitly)
    now = k.pop("now", (max([r["_t"] for r in rows]) + 60) if rows else T0)
    return sp.summarize(rows, "r", k.pop("sha", C), now=now, is_anc=k.pop("is_anc", lambda a, b: None), min_h=k.pop("min_h", 2.0), **k)


s = summ([row(i) for i in range(9)])
ok("9 clean samples 15 min apart = 2.0 h -> PASS / OK", s["verdict"] == "PASS" and s["decision"] == "OK" and s["clean_hours"] == 2.0, s)
s = summ([row(i) for i in range(5)])
ok("1.0 h clean of 2.0 -> FLAG / HOLD (still soaking)", s["verdict"] == "FLAG" and s["decision"] == "HOLD" and s["clean_hours"] == 1.0, s)
s = summ([row(i) for i in range(4)] + [row(4, "FAIL", sigs=["GET /x -> 5xx"])] + [row(i) for i in range(5, 8)])
ok("a FAIL inside the window -> FAIL / HOLD and the streak restarts", s["verdict"] == "FAIL" and s["decision"] == "HOLD" and s["bad_samples"] == 1, s)
s = summ([row(0, "FAIL", sigs=["a"])] + [row(i) for i in range(1, 20)])
ok("a failure long ago followed by >= min hours clean -> PASS again (history is reported, not held forever)", s["verdict"] == "PASS" and s["bad_samples"] == 1, s)
s = summ([row(i) for i in range(5)] + [row(i) for i in range(20, 25)])
ok("a coverage hole > 3 intervals breaks the streak (no coverage = no soak)", s["clean_hours"] == 1.0 and s["decision"] == "HOLD", s)
s = summ([row(i) for i in range(9)] + [row(4.5, "UNVERIFIED")])
ok("UNVERIFIED samples carry no signal: they neither extend nor break a streak", s["verdict"] == "PASS" and s["unverified_samples"] == 1, s)
s = summ([row(i) for i in range(9)] + [row(9, "FLAG", slow=True)])
ok("a slow sample is not clean: it breaks the streak -> FAIL/HOLD", s["decision"] == "HOLD" and s["bad_samples"] == 1, s)
s = summ([row(i, "FLAG") for i in range(9)])
ok("FLAG that is only 'N/A by design' (e.g. gitlark) counts as clean", s["verdict"] == "PASS", s)
print("-- recency: a clean streak must be CURRENT (no coverage now = no soak)")
clean9 = [row(i) for i in range(9)]
outage = [row(9 + i, "UNVERIFIED", sha="") for i in range(12)]          # what an unreachable staging records: no served sha, so not attributable to any build
s = summ(clean9 + outage)
ok("2 h clean then 3 h of unreachable staging (12 UNVERIFIED, no sha): NOT PASS, FLAG/HOLD, stale, trailing UNVERIFIED counted",
   s["verdict"] == "FLAG" and s["decision"] == "HOLD" and s["stale"] and s["trailing_unverified"] == 12 and s["last_clean_age_s"] == 12 * 900 + 60, s)
ok("... and the summary names the outage", "no current coverage" in s["summary"] and "12 UNVERIFIED" in s["summary"], s["summary"])
s = summ(clean9, now=T0 + 8 * 900 + 5 * 86400)
ok("a 2 h clean streak that ended 5 days ago is NOT a PASS (stale)", s["verdict"] == "FLAG" and s["decision"] == "HOLD" and s["stale"], s)
s = summ(clean9, now=T0 + 8 * 900 + 2 * 900)
ok("newest clean sample 2 intervals old: still current -> PASS", s["verdict"] == "PASS" and not s["stale"], s)
s = summ(clean9, now=T0 + 8 * 900 + 3 * 900 + 1)
ok("newest clean sample just over 3 intervals old: stale", s["stale"] and s["decision"] == "HOLD", s)
s = summ(clean9 + [row(9, "UNVERIFIED", sha="")])
ok("one UNVERIFIED blip after the streak (inside 3 intervals) does not undo a current PASS", s["verdict"] == "PASS" and s["trailing_unverified"] == 1, s)
s = summ(clean9 + outage + [row(30 + i) for i in range(9)])
ok("staging recovers: a new full clean streak after the outage is a PASS again", s["verdict"] == "PASS" and not s["stale"], s)
save_sf = sp.STALE_FACTOR
sp.STALE_FACTOR = 10 ** 9
s = summ(clean9 + outage)
sp.STALE_FACTOR = save_sf
ok("mutant (recency check removed) turns the outage into PASS: the tests above are not vacuous", s["verdict"] == "PASS" and s["decision"] == "OK", s)
print("-- the soak minimum is pinned (a lower default would pass a build after minutes)")
ok("DEFAULT_MIN_HOURS is 2.0 and min_hours() uses it when the env is unset", sp.DEFAULT_MIN_HOURS == 2.0 and sp.min_hours() == 2.0)
s = sp.summarize([row(i) for i in range(7)], "r", C, now=T0 + 6 * 900 + 60, is_anc=lambda a, b: None)
ok("1.5 h of clean samples with the DEFAULT minimum is FLAG/HOLD, not PASS", s["verdict"] == "FLAG" and s["min_hours"] == 2.0 and s["clean_hours"] == 1.5, s)
os.environ["OVN_QA_SOAK_MIN_HOURS"] = "1.0"
ok("OVN_QA_SOAK_MIN_HOURS overrides it", sp.min_hours() == 1.0)
os.environ.pop("OVN_QA_SOAK_MIN_HOURS")
print("-- stale-deploy rows (staging still deploying the candidate) break the streak but do not FAIL once staging serves the candidate")
lag = [row(i, "FAIL", sha=OLD, cand=C, sigs=["provenance: staging serves <sha> but the candidate is <sha>: healthy but STALE deploy"]) for i in range(3)]
s = summ(lag + [row(3 + i, cand=C) for i in range(5)])
ok("deploy lag then clean: FLAG still soaking (streak restarted), not a 2 h FAIL", s["verdict"] == "FLAG" and s["decision"] == "HOLD" and s["clean_hours"] == 1.0, s)
s = summ(lag + [row(3 + i, cand=C) for i in range(9)])
ok("deploy lag then 2 h clean: PASS (no new-signature false FAIL from the lag rows)", s["verdict"] == "PASS", s)
s = summ(lag)
ok("staging STILL on the old build: FAIL/HOLD", s["verdict"] == "FAIL" and s["decision"] == "HOLD", s)
print("-- readiness from real rows")
bld = lambda c, n, t: [dict(row(i, sha=c), _t=t + i * 900) for i in range(n)]
rd = sp.readiness(bld("a" * 40, 9, T0) + bld("b" * 40, 3, T0 + 20000) + bld("c" * 40, 9, T0 + 40000), "r")
ok("readiness: 2 of 3 builds reached 2 h clean before being replaced", rd["builds"] == 3 and rd["reached_pass"] == 2 and rd["never_soaked"] == 1 and rd["verdict"] == "PASS", rd)
rd = sp.readiness(bld("a" * 40, 3, T0) + bld("b" * 40, 3, T0 + 20000) + bld("c" * 40, 9, T0 + 40000), "r")
ok("readiness: most builds replaced within 2 h -> FLAG 'do NOT enforce yet'", rd["verdict"] == "FLAG" and "do NOT enforce" in rd["summary"], rd)
ok("readiness: no rows -> UNVERIFIED", sp.readiness([], "r")["verdict"] == "UNVERIFIED")
print("-- no signal is UNVERIFIED, never PASS")
s = summ([])
ok("no rows at all: UNVERIFIED / UNVERIFIED (not PASS, never holds)", s["verdict"] == "UNVERIFIED" and s["decision"] == "UNVERIFIED" and "no traffic" in s["summary"], s)
s = summ([row(i, "UNVERIFIED") for i in range(12)])
ok("only UNVERIFIED samples: UNVERIFIED, not PASS", s["verdict"] == "UNVERIFIED" and s["decision"] == "UNVERIFIED" and s["informative"] == 0, s)
s = summ([row(i, sha=OLD) for i in range(12)])
ok("samples of ANOTHER build do not soak this candidate: UNVERIFIED", s["verdict"] == "UNVERIFIED" and s["samples"] == 0, s)
s = summ([row(i, sha="") for i in range(12)])
ok("samples with an unknown served build are not attributable: UNVERIFIED", s["verdict"] == "UNVERIFIED" and s["samples"] == 0, s)
s = summ([row(i, sha=OLD) for i in range(12)], is_anc=lambda a, b: (a, b) == (C, OLD))
ok("a build that CONTAINS the candidate (descendant) soaks it", s["verdict"] == "PASS" and s["samples"] == 12, s)
s = summ([row(i, sha=OLD, cand=C, verdict="FAIL", sigs=["provenance: stale"]) for i in range(3)])
ok("samples that were asked to verify the candidate and caught a stale build count against it", s["decision"] == "HOLD" and s["verdict"] == "FAIL", s)
print("-- new error signatures")
base = [row(i, sha=OLD, sigs=["GET /legacy -> 5xx"], verdict="PASS", step=60) for i in range(3)]
s = summ(base + [row(100 + i, sigs=["GET /new -> 5xx"]) for i in range(10)])
ok("a signature no earlier build showed is NEW and holds even with PASS verdicts", s["new_signatures"] == ["GET /new -> 5xx"] and s["decision"] == "HOLD" and s["verdict"] == "FAIL", s)
s = summ(base + [row(100 + i, sigs=["GET /legacy -> 5xx"]) for i in range(10)])
ok("a signature the previous build already had is not new", s["new_signatures"] == [] and s["verdict"] == "PASS", s)
print("-- mutant: if clean/bad were not decided from the verdict, a failing series would PASS (the assertions above would catch it)")
save = (sp.is_bad, sp.is_clean)
sp.is_bad, sp.is_clean = (lambda r: False), (lambda r: True)
s = summ([row(i, "FAIL") for i in range(9)])
sp.is_bad, sp.is_clean = save
s_real = summ([row(i, "FAIL") for i in range(9)])
ok("mutant (is_bad/is_clean neutered) turns an all-FAIL series into PASS; the real code HOLDs it", s["decision"] == "OK" and s_real["decision"] == "HOLD", (s, s_real))

print("== log plumbing")
lp = os.path.join(T, "big.jsonl")
with open(lp, "w") as f:
    f.write("not json\n")
    for i in range(400):
        f.write(json.dumps({"gate": "soak", "repo": "r", "ts": "2026-10-17T00:00:00Z", "verdict": "PASS", "details": {"pad": "x" * 100}}) + "\n")
    f.write('{"gate": "soak", "repo": "r", "ts": "2026-10-17T00:0')
ok("read_rows tolerates a corrupt line and a truncated tail", len(sp.read_rows("r", lp)) == 400)
big = os.path.getsize(lp)
ok("trim_log shrinks an oversized log and keeps whole lines", sp.trim_log(lp, max_bytes=big // 2) and os.path.getsize(lp) <= big // 2 + 10 and all(json.loads(l) for l in open(lp).read().splitlines()[:-1]))
ok("trim_log leaves a small log alone", sp.trim_log(lp, max_bytes=10 ** 9) is False)

print("== promote_gate: shadow soak read, enforce only for an explicit allow-list")
ok("decide_soak_block: shadow never holds", pg.decide_soak_block("shadow", "HOLD", "r", ["r"]) is False)
ok("decide_soak_block: enforce + HOLD + repo in allow-list holds", pg.decide_soak_block("enforce", "HOLD", "r", ["r"]) is True)
ok("decide_soak_block: enforce + EMPTY allow-list does NOT hold (default)", pg.decide_soak_block("enforce", "HOLD", "r", []) is False and pg.decide_soak_block("enforce", "HOLD", "r", None) is False)
ok("decide_soak_block: enforce + repo outside the allow-list does not hold", pg.decide_soak_block("enforce", "HOLD", "r", ["other"]) is False)
ok("decide_soak_block: UNVERIFIED / OK / off never hold", not any(pg.decide_soak_block(m, d, "r", ["r"]) for m, d in (("enforce", "UNVERIFIED"), ("enforce", "OK"), ("off", "HOLD"))))
ok("allow-list default is empty", pg.soak_allow_list() == set())
os.environ["OVN_QA_SOAK_ENFORCE_REPOS"] = "a, b"
open(os.path.join(STATE, "qa_soak_enforce_repos"), "w").write("c  # comment\n\n# only a comment\nd\n")
ok("allow-list reads env + state file (comments ignored)", pg.soak_allow_list() == {"a", "b", "c", "d"}, pg.soak_allow_list())
os.environ.pop("OVN_QA_SOAK_ENFORCE_REPOS")
os.remove(os.path.join(STATE, "qa_soak_enforce_repos"))

SOAKLOG = sp.log_path()


def seed(rows):
    os.makedirs(os.path.dirname(SOAKLOG), exist_ok=True)
    with open(SOAKLOG, "w") as f:
        for r in rows:
            f.write(json.dumps({"gate": "soak", "repo": r["repo"], "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(r["_t"])), "verdict": r["verdict"], "details": r["details"]}) + "\n")


def gate_out():
    return {"block": False, "reason": "", "candidate": C}


NOW = time.time()
bad_rows = [dict(row(0, "FAIL", sigs=["GET /health -> 5xx"], repo="r"), _t=NOW - 600 + i) for i in range(2)]
seed(bad_rows)
o = gate_out()
pg._apply_soak(o, "r", C, lambda a, b: None)
ok("shadow default: soak FAIL is read, decision HOLD, but block stays False", o["soak_present"] and o["soak_mode"] == "shadow" and o["soak_decision"] == "HOLD" and o["soak_block"] is False and o["block"] is False, o)
o["candidate"], o.update(staging_verdict="PASS", relation="MATCH", staging_commit="x", provider="file", summary="", mode="shadow", unverified=False, e2e_present=False, alembic_verdict="", held_back=0,
                         candidate_verdict="PASS", release_branch="", ff_main_possible=True)
lines = pg.log_lines(o)
ok("log line says 'soak would HOLD (shadow)' and the promote proceeds", any("[staging-soak]" in l and "soak would HOLD (shadow)" in l for l in lines), lines)
os.environ["OVN_QA_SOAK"] = "enforce"
o = gate_out(); pg._apply_soak(o, "r", C, lambda a, b: None)
ok("enforce with the DEFAULT empty allow-list still only logs", o["soak_block"] is False and o["block"] is False and o["soak_decision"] == "HOLD", o)
o.update(candidate=C, staging_verdict="PASS", relation="MATCH", staging_commit="x", provider="file", summary="", mode="shadow", unverified=False, e2e_present=False, alembic_verdict="", held_back=0,
         candidate_verdict="PASS", release_branch="", ff_main_possible=True)
ok("... and says so in the log line", any("enforce, repo not in the allow-list" in l for l in pg.log_lines(o)))
os.environ["OVN_QA_SOAK_ENFORCE_REPOS"] = "r"
o = gate_out(); pg._apply_soak(o, "r", C, lambda a, b: None)
ok("enforce + repo in the allow-list: HOLD (block true, reason SOAK_HOLD)", o["soak_block"] is True and o["block"] is True and o["reason"].startswith("SOAK_HOLD"), o)
o.update(candidate=C, staging_verdict="PASS", relation="MATCH", staging_commit="x", provider="file", summary="", mode="shadow", unverified=False, e2e_present=False, alembic_verdict="", held_back=0,
         candidate_verdict="PASS", release_branch="", ff_main_possible=True)
ok("the enforced log line is a plain HOLD", any("[staging-soak]" in l and "-> HOLD " in l for l in pg.log_lines(o)), pg.log_lines(o))
os.environ["OVN_QA_SOAK"] = "off"
o = gate_out(); pg._apply_soak(o, "r", C, lambda a, b: None)
ok("OVN_QA_SOAK=off: no read, no fields", "soak_present" not in o)
os.environ.pop("OVN_QA_SOAK"); os.environ.pop("OVN_QA_SOAK_ENFORCE_REPOS")
os.remove(SOAKLOG)
o = gate_out(); pg._apply_soak(o, "r", C, lambda a, b: None)
ok("no soak.jsonl at all: nothing added (log output byte-identical to before)", "soak_present" not in o)
seed([row(i, "UNVERIFIED", repo="r") for i in range(5)])
os.environ["OVN_QA_SOAK"] = "enforce"; os.environ["OVN_QA_SOAK_ENFORCE_REPOS"] = "r"
o = gate_out(); pg._apply_soak(o, "r", C, lambda a, b: None)
ok("no-signal soak is UNVERIFIED, shown as such, and never holds even enforced + allow-listed", o["soak_verdict"] == "UNVERIFIED" and o["soak_decision"] == "UNVERIFIED" and o["block"] is False, o)
os.environ.pop("OVN_QA_SOAK"); os.environ.pop("OVN_QA_SOAK_ENFORCE_REPOS")
chk = pg.check(["--repo", "no-such-repo"])
ok("promote_gate.check on an unknown repo still returns the evidence dict and never blocks (soak keys present)", chk["block"] is False and chk["soak_present"] is False and "log_lines" in chk, chk)

print("== soak_probe_cron.sh")
cron = os.path.join(QA, "soak_probe_cron.sh")
ok("cron wrapper is executable in the tree", os.access(cron, os.X_OK))
env2 = dict(env, OVN_SOAK_REPOS="billwatch", QA_STATE_DIR=os.path.join(T, "cstate"))
env2.pop("QA_SMOKE_DRILL_EMAIL"); env2.pop("QA_SMOKE_DRILL_PASSWORD")
p = subprocess.run(["bash", cron], env=env2, capture_output=True, text=True, timeout=120)
ok("cron wrapper: exit 0; with no staging URL the row is UNVERIFIED (the honest signal), nothing else happens", p.returncode == 0 and "UNVERIFIED" in p.stdout, p.stdout + p.stderr)
p = subprocess.run(["bash", cron], env=dict(env2, OVN_QA_SOAK="off"), capture_output=True, text=True, timeout=60)
ok("cron wrapper: OVN_QA_SOAK=off is a no-op that says so", p.returncode == 0 and "disabled" in p.stdout, p.stdout)
p = subprocess.run(["bash", cron], env=dict(env2, OVN_SOAK_REPOS="bad;name"), capture_output=True, text=True, timeout=60)
ok("cron wrapper: a malformed repo name is skipped, exit 0", p.returncode == 0 and "bad repo name" in p.stdout, p.stdout)

print("== cron wrappers, behaviourally (a fake probe records how the wrapper calls it)")
import fcntl, shutil as _sh
def fake_qa(name, wrapper, fake_name, extra_files=()):
    d = os.path.join(T, name)
    os.makedirs(os.path.join(d, "qa"), exist_ok=True)
    _sh.copy(os.path.join(QA, wrapper), os.path.join(d, "qa", wrapper))
    open(os.path.join(d, "qa", fake_name), "w").write('import sys,json\nopen(sys.argv[0]+".argv","a").write(" ".join(sys.argv[1:])+"\\n")\nprint(json.dumps({"verdict":"PASS","summary":"fake"}))\n')
    for f in extra_files:
        open(os.path.join(d, "qa", f), "w").write("")
    return d
cenv = {"PATH": os.environ["PATH"], "HOME": T, "TMPDIR": os.environ.get("TMPDIR", T)}
d = fake_qa("cron_soak", "soak_probe_cron.sh", "soak_probe.py")
st = os.path.join(d, "state")
p = subprocess.run(["bash", os.path.join(d, "qa", "soak_probe_cron.sh")], env=dict(cenv, OVN_SOAK_REPOS="billwatch", QA_STATE_DIR=st), capture_output=True, text=True, timeout=60)
argv = open(os.path.join(d, "qa", "soak_probe.py.argv")).read() if os.path.exists(os.path.join(d, "qa", "soak_probe.py.argv")) else ""
ok("soak cron calls the probe WITH --candidate auto (stale-build detection reachable in production)", p.returncode == 0 and "probe --repo billwatch --candidate auto" in argv, (argv, p.stdout, p.stderr))
os.remove(os.path.join(d, "qa", "soak_probe.py.argv"))
flock_bin = _sh.which("flock", path="/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin")
os.makedirs(st, exist_ok=True)
if flock_bin:
    fh = open(os.path.join(st, "soak_probe.lock"), "w")
    fcntl.flock(fh, fcntl.LOCK_EX | fcntl.LOCK_NB)
else:
    os.makedirs(os.path.join(st, "soak_probe.lock.d"))
p = subprocess.run(["bash", os.path.join(d, "qa", "soak_probe_cron.sh")], env=dict(cenv, OVN_SOAK_REPOS="billwatch", QA_STATE_DIR=st), capture_output=True, text=True, timeout=60)
ok("a second soak cron run while one holds the lock is skipped, exit 0, the probe is not called (%s)" % ("flock" if flock_bin else "mkdir lock"),
   p.returncode == 0 and "still holds" in p.stdout and not os.path.exists(os.path.join(d, "qa", "soak_probe.py.argv")), (p.stdout, p.stderr))
if flock_bin:
    fh.close()
print("== soak cron serialises on state/staging_e2e.lock (the lock e2e + daily smoke take)")
def soak_run(d, st, script=None, **env):
    argvf = os.path.join(d, "qa", "soak_probe.py.argv")
    if os.path.exists(argvf):
        os.remove(argvf)
    pr = subprocess.run(["bash", script or os.path.join(d, "qa", "soak_probe_cron.sh")], env=dict(cenv, OVN_SOAK_REPOS="billwatch", QA_STATE_DIR=st, OVN_SOAK_E2E_LOCK_WAIT_S="2", **env), capture_output=True, text=True, timeout=60)
    return pr, os.path.exists(argvf)
d2 = fake_qa("cron_soak_e2e", "soak_probe_cron.sh", "soak_probe.py")
st2 = os.path.join(d2, "state"); lk = os.path.join(st2, "staging_e2e.lock")
os.makedirs(lk, exist_ok=True); open(os.path.join(lk, "pid"), "w").write("99999\n")
pr, called = soak_run(d2, st2)
ok("e2e lock held by another job: the sample is SKIPPED (logged), the probe is NOT called, exit 0, and the other job's lock is left alone",
   pr.returncode == 0 and not called and "SKIPPED" in pr.stdout and "staging_e2e.lock busy" in pr.stdout and os.path.isdir(lk) and open(os.path.join(lk, "pid")).read().strip() == "99999", (pr.stdout, pr.stderr))
old = time.time() - 2 * 3600
os.utime(lk, (old, old))
pr, called = soak_run(d2, st2)
ok("a STALE e2e lock (2 h old) is taken over: the probe runs and the lock is released afterwards", pr.returncode == 0 and called and not os.path.exists(lk), (pr.stdout, pr.stderr))
pr, called = soak_run(d2, st2)
ok("free lock: the probe runs and the lock is released afterwards (the e2e run is not blocked)", pr.returncode == 0 and called and not os.path.exists(lk), (pr.stdout, pr.stderr))
pr, called = soak_run(d2, st2, OVN_SOAK_E2E_LOCK="off")
ok("OVN_SOAK_E2E_LOCK=off: no lock is taken", pr.returncode == 0 and called and not os.path.exists(lk), (pr.stdout, pr.stderr))
msrc = open(os.path.join(QA, "soak_probe_cron.sh")).read()
tgt = 'e2e_take || {'
assert tgt in msrc
open(os.path.join(d2, "qa", "soak_probe_cron.mutant.sh"), "w").write(msrc.replace(tgt, 'true || {', 1))
os.makedirs(lk, exist_ok=True); open(os.path.join(lk, "pid"), "w").write("99999\n")
pr, called = soak_run(d2, st2, script=os.path.join(d2, "qa", "soak_probe_cron.mutant.sh"))
ok("MUTANT (lock not taken) is caught: it runs the probe while the e2e lock is held", called and "SKIPPED" not in pr.stdout, (pr.stdout, pr.stderr))
for f in os.listdir(lk):
    os.remove(os.path.join(lk, f))
os.rmdir(lk)
d = fake_qa("cron_fuzz", "contract_fuzz_cron.sh", "contract_fuzz.py", extra_files=("qa_common.py",))
p = subprocess.run(["bash", os.path.join(d, "qa", "contract_fuzz_cron.sh")], env=dict(cenv, QA_STATE_DIR=os.path.join(d, "state"), OVN_FUZZ_LOAD_MAX="100000"), capture_output=True, text=True, timeout=60)
fa = open(os.path.join(d, "qa", "contract_fuzz.py.argv")).read().splitlines() if os.path.exists(os.path.join(d, "qa", "contract_fuzz.py.argv")) else []
ok("fuzz cron with no OVN_FUZZ_REPOS fuzzes the whole registry, in order: iptv_apps billwatch gitlark", [l.split()[2] for l in fa] == ["iptv_apps", "billwatch", "gitlark"], (fa, p.stdout, p.stderr))

print("== qa_enforce.sh knows the soak key (flip + rollback, no deploy)")
enf = os.path.join(QA, "qa_enforce.sh")
est = os.path.join(T, "enf_state")
os.makedirs(est)
ee = {"PATH": os.environ["PATH"], "HOME": T, "OVN_DIR": T, "QA_STATE_DIR": est}
p = subprocess.run(["bash", enf, "soak", "enforce"], env=ee, capture_output=True, text=True, timeout=60)
ok("soak enforce is accepted and says it needs the allow-list", p.returncode == 0 and "allow-list" in p.stdout, p.stdout + p.stderr)
os.environ["QA_STATE_DIR"] = est
ok("... it is then the resolved mode for the gate key `soak` (and the empty allow-list still holds nothing)", qc.mode("soak") == "enforce" and not pg.decide_soak_block("enforce", "HOLD", "r", pg.soak_allow_list()))
p = subprocess.run(["bash", enf, "soak", "shadow"], env=ee, capture_output=True, text=True, timeout=60)
ok("rollback: soak shadow, exit 0", p.returncode == 0 and qc.mode("soak") == "shadow", p.stdout + p.stderr)
os.environ["QA_STATE_DIR"] = STATE
p = subprocess.run(["bash", enf, "nosuchgate", "enforce"], env=ee, capture_output=True, text=True, timeout=60)
ok("an unknown gate is still refused for enforce", p.returncode == 2, p.stdout + p.stderr)

stub.stop()
print("\n%d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
