#!/usr/bin/env python3
"""Tests for qa/baseline_verify.py (gate S4). Exercises the REAL entry point as cron would run it: absolute path AND path relative
to scripts/overnight-queue, under `env -i` with a minimal PATH and NTFY_SERVER set, OVN_DIR pointing at a temp dir.
Negative controls (new failure -> FAIL, growth -> alert not widen, hard gate failure -> FAIL), benign controls (pre-existing red ->
PASS), and UNVERIFIED cases (no/expired baseline, truncated log, missing file, timeout, runner-failed-unparseable)."""
import json, os, shutil, stat, subprocess, sys, tempfile, time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))          # scripts/overnight-queue
QA = os.path.join(ROOT, "qa")
SCRIPT = os.path.join(QA, "baseline_verify.py")
FIX = os.path.join(HERE, "fixtures", "qa_baseline")
sys.path.insert(0, QA)
import baseline_verify as bv  # noqa: E402

P = F = 0


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name + (("  :: " + str(extra)[:300]) if extra else ""))


T = tempfile.mkdtemp(prefix="qa-baseline-test-")
OVN = os.path.join(T, "ovn")
os.makedirs(os.path.join(OVN, "state"))
PYDIR = os.path.dirname(os.path.realpath(sys.executable))
CLEAN_ENV = {"PATH": PYDIR + ":/usr/bin:/bin", "HOME": T, "NTFY_SERVER": "http://127.0.0.1:9", "OVN_DIR": OVN, "LANG": "C"}


def cli(args, env_extra=None, rel=False, cwd=None):
    """Run the gate exactly as cron would. Returns (rc, parsed-last-json-line, stdout)."""
    env = dict(CLEAN_ENV)
    env.update(env_extra or {})
    exe = [sys.executable, "qa/baseline_verify.py"] if rel else [sys.executable, SCRIPT]
    p = subprocess.run(["env", "-i"] + ["%s=%s" % kv for kv in env.items()] + exe + args + ["--no-record"],
                       cwd=cwd or (ROOT if rel else T), capture_output=True, text=True, timeout=120)
    last = [l for l in p.stdout.splitlines() if l.strip()]
    try:
        js = json.loads(last[-1])
    except Exception:  # noqa: BLE001
        js = None
    if js is None:
        js = {"verdict": "NO-JSON", "summary": "", "details": {}}   # a contract violation; callers' asserts fail instead of crashing
    js.setdefault("details", {})
    return p.returncode, js, p.stdout + p.stderr


def w(name, text):
    p = os.path.join(T, name)
    with open(p, "w") as f:
        f.write(text)
    return p


def pytest_log(failed, passed=50, extra=""):
    ids = "\n".join("FAILED %s - AssertionError: x" % i for i in failed)
    summ = "=========================== short test summary info ============================\n%s\n" % ids if failed else ""
    tail = ("%d failed, " % len(failed) if failed else "") + "%d passed, 3 warnings in 12.34s" % passed
    return ".........F.... [100%%]\n%s%s=== %s ===\n" % (extra, summ, tail)


# ------------------------------------------------------------------------------------------------------------- 1. parsers
print("== parsers")
p = bv.parse_pytest(pytest_log(["tests/a.py::test_1", "tests/b.py::TestX::test_2[p - q]"]))
ok("pytest: ids parsed, bracket-aware msg cut", p["ids"] == ["tests/a.py::test_1", "tests/b.py::TestX::test_2[p - q]"] and p["complete"], p)
p = bv.parse_pytest(pytest_log([]))
ok("pytest: green run complete with no ids", p["ids"] == [] and p["complete"])
p = bv.parse_pytest("........ [ 13%]\n........ [ 40%]\n.......")
ok("pytest: truncated (timeout) run is INCOMPLETE", not p["complete"])
p = bv.parse_pytest("=== short test summary info ===\nERROR tests/test_x.py\n=== 1 error in 0.50s ===\n")
ok("pytest: collection ERROR file is an id", p["ids"] == ["tests/test_x.py"] and p["complete"], p)
p = bv.parse_pytest("FAILED tests/a.py::t - boom\n=== 2 failed, 5 passed in 1.00s ===\n")
ok("pytest: id count below summary count => incomplete", not p["complete"], p)
p = bv.parse_pytest("\x1b[31mFAILED\x1b[0m tests/a.py::t\n=== 1 failed in 1.0s ===")
ok("pytest: ANSI stripped", p["ids"] == ["tests/a.py::t"], p)

vt = """ FAIL  src/a.test.ts > Suite one > does it 12ms
 FAIL  src/b.test.tsx [ src/b.test.tsx ]
 ✓ src/c.test.ts (3 tests) 5ms
 Test Files  2 failed | 1 passed (3)
      Tests  1 failed | 9 passed (10)
"""
p = bv.parse_vitest(vt)
ok("vitest: failing file+name and file-level failures", p["ids"] == ["src/a.test.ts > Suite one > does it", "src/b.test.tsx"] and p["complete"], p)
ok("vitest: no summary => incomplete", not bv.parse_vitest(" FAIL  src/a.test.ts > x\n")["complete"])

g = open(os.path.join(FIX, "iptv_gradle_compile_red.verify.txt")).read()
p = bv.parse_verify_log(g)
ok("verify-log/gradle real log: task + per-file kotlinc ids", any(i.endswith("task:app:compileFireTvDebugUnitTestKotlin") for i in p["ids"]) and any("kotlinc:" in i and "FavoritesRepositoryTest.kt" in i for i in p["ids"]) and p["complete"], p)
ok("gradle kotlinc id has no /tmp/stage path or line number", all("/tmp/" not in i and not i.rstrip().split(":")[-1].isdigit() for i in p["ids"]), p["ids"])
p = bv.parse_gradle("> Task :app:test\nFavoritesTest > addFavorite FAILED\n    java.lang.AssertionError\nBUILD FAILED in 3s\n")
ok("gradle: failed test method id", p["ids"] == ["FavoritesTest > addFavorite"] and p["complete"], p)
ok("gradle: no BUILD line => incomplete (timeout)", not bv.parse_gradle("> Task :app:compile\n")["complete"])

GUT = ("res://tests/test_scar.gd\n- test_a\n    [Failed]:  [0] expected to equal [6]:  \n      at line -1\n- test_b\n    [Failed]:  \n\n"
       "---- Totals ----\nScripts 3\nTests 10\n  Passing 8\n  Failing 2\n\n")
GUT = "= Run Summary\n==\n" + GUT
p = bv.parse_gut(GUT)
ok("GUT: Run Summary failures -> file::test ids", p["ids"] == ["res://tests/test_scar.gd::test_a", "res://tests/test_scar.gd::test_b"] and p["complete"], p)
ok("GUT: parse error lines become ids", "godot-parse:Preload file" in " ".join(bv.parse_gut("SCRIPT ERROR: Parse Error: Preload file x\n---- Totals ----\n")["ids"]))
ok("GUT: no Totals => incomplete", not bv.parse_gut("Run Summary\n")["complete"])

q = open(os.path.join(FIX, "billwatch_quality_fail.verify.txt")).read()
p = bv.parse_verify_log(q)
ok("verify-log real: QUALITY FAIL is a HARD failure", any("QUALITY FAIL" in h for h in p["hard"]), p["hard"])
t5 = bv.parse_verify_log(open(os.path.join(FIX, "taa_stale_pricing_5red.verify.txt")).read())
ok("verify-log real (TAA 02:16): 5 stale-pricing failures, complete, prefixed by package", len(t5["ids"]) == 5 and t5["complete"] and all(i.startswith("[backend] tests/test_llm_service.py") for i in t5["ids"]), t5["ids"])
tr = bv.parse_verify_log(open(os.path.join(FIX, "iptv_truncated_300s.verify.txt")).read())
ok("verify-log real: 300s-truncated pytest is INCOMPLETE", not tr["complete"], tr)
fc = bv.parse_verify_log("2026-09-30 11:46:00 independent full-verify (combined result)\n-- python tests exist but no venv pytest found: CANNOT verify (fail-closed) --\n")
ok("verify-log: fail-closed line is HARD", fc["hard"] and "fail-closed" in fc["hard"][0], fc)
ok("auto-detect picks the right parser", bv.detect_format(g) == "verify-log" and bv.detect_format(vt) == "vitest" and bv.detect_format(pytest_log(["a.py::t"])) == "pytest")

# ----------------------------------------------------------------------------------------- 2. CLI: baseline-relative compare
print("== CLI compare/snapshot (env -i, abs + rel path)")
base_ids = ["tests/test_pricing.py::test_haiku", "tests/test_pricing.py::test_sonnet", "tests/test_pricing.py::test_partial"]
f_base = w("base.log", pytest_log(base_ids))
rc, js, out = cli(["snapshot", "--repo", "demo", "--failing-file", f_base, "--commit", "abc123", "--source", "deterministic:test"])
ok("snapshot stores baseline (PASS, stored_fresh)", rc == 0 and js and js["verdict"] == "PASS" and js["details"]["status"] == "stored_fresh", out)
ok("snapshot wrote state/qa_baselines/verify/demo.json under OVN_DIR only", os.path.isfile(os.path.join(OVN, "state", "qa_baselines", "verify", "demo.json")))
st = json.load(open(os.path.join(OVN, "state", "qa_baselines", "verify", "demo.json")))
ok("stored baseline has ts/commit/ids/ttl", st["commit"] == "abc123" and st["count"] == 3 and st["ttl_s"] == 86400 and st["ts"] > 0)

f_pre = w("pre.log", pytest_log(base_ids[:2]))
for rel in (False, True):
    rc, js, out = cli(["compare", "--repo", "demo", "--failing-file", f_pre, "--base-sha", "abc123"], rel=rel)
    tag = "relative" if rel else "absolute"
    ok("benign control (%s path): only pre-existing red => PASS" % tag, rc == 0 and js and js["verdict"] == "PASS" and len(js["details"]["preexisting"]) == 2 and js["details"]["new_failures"] == []
       and js["details"]["fixed"] == [base_ids[2]], out)
f_new = w("new.log", pytest_log(base_ids[:1] + ["tests/test_other.py::test_new"]))
for rel in (False, True):
    rc, js, out = cli(["compare", "--repo", "demo", "--failing-file", f_new], rel=rel)
    ok("negative control (%s path): a NEW failing test => FAIL" % ("relative" if rel else "absolute"), js and js["verdict"] == "FAIL" and js["details"]["new_failures"] == ["tests/test_other.py::test_new"], out)
ok("FAIL still exits 0 in shadow mode", rc == 0)
f_green = w("green.log", pytest_log([]))
rc, js, out = cli(["compare", "--repo", "demo", "--failing-file", f_green])
ok("fully green run => PASS and reports fixed set", js["verdict"] == "PASS" and len(js["details"]["fixed"]) == 3, out)
rc, js, out = cli(["compare", "--repo", "no-such-repo", "--failing-file", f_green])
ok("green run with no baseline => PASS (nothing to tolerate)", js["verdict"] == "PASS", out)
rc, js, out = cli(["compare", "--repo", "no-such-repo", "--failing-file", f_new])
ok("failures + NO baseline => UNVERIFIED (never guess)", js["verdict"] == "UNVERIFIED" and "no baseline" in js["summary"], out)

# expiry
bp = os.path.join(OVN, "state", "qa_baselines", "verify", "demo.json")
st = json.load(open(bp))
st["ts"] = time.time() - 25 * 3600
json.dump(st, open(bp, "w"))
rc, js, out = cli(["compare", "--repo", "demo", "--failing-file", f_pre])
ok("baseline older than 24h EXPIRES => UNVERIFIED (not PASS)", js["verdict"] == "UNVERIFIED" and js["details"]["baseline"]["expired"] is True, out)
st["ts"] = time.time() - 23 * 3600
json.dump(st, open(bp, "w"))
rc, js, out = cli(["compare", "--repo", "demo", "--failing-file", f_pre])
ok("baseline 23h old still valid => PASS", js["verdict"] == "PASS", out)

# hard failures are never baseline-tolerated
hard_log = w("hard.log", "-- pytest FULL in backend --\n" + pytest_log([]).replace("tests/", "") + "-- QUALITY FAIL: app/x.py is a stub/placeholder --\n")
rc, js, out = cli(["compare", "--repo", "demo", "--failing-file", hard_log])
ok("QUALITY FAIL (non-baselineable) => FAIL even though suite has no red", js["verdict"] == "FAIL" and "non-baselineable" in js["summary"], out)
rc, js, out = cli(["compare", "--repo", "demo", "--failing-file", os.path.join(FIX, "billwatch_quality_fail.verify.txt")])
ok("real billwatch QUALITY FAIL log => FAIL", js["verdict"] == "FAIL", out)

# unverified cases
rc, js, out = cli(["compare", "--repo", "demo", "--failing-file", os.path.join(FIX, "iptv_truncated_300s.verify.txt")])
ok("truncated (300s timeout) log => UNVERIFIED", js["verdict"] == "UNVERIFIED" and "truncated" in js["summary"], out)
rc, js, out = cli(["compare", "--repo", "demo", "--failing-file", os.path.join(T, "nope.log")])
ok("missing failing file => UNVERIFIED, exit 0", rc == 0 and js["verdict"] == "UNVERIFIED", out)
rc, js, out = cli(["compare", "--repo", "demo", "--failing-file", f_green, "--runner-failed"])
ok("runner said failed but nothing parseable => UNVERIFIED", js["verdict"] == "UNVERIFIED", out)
rc, js, out = cli(["compare", "--repo", "../../etc", "--failing-file", f_green])
ok("path-traversal repo name => UNVERIFIED (no crash, no write)", rc == 0 and js["verdict"] == "UNVERIFIED", out)
rc, js, out = cli(["compare", "--failing-file", f_green])
ok("missing --repo => UNVERIFIED", js["verdict"] == "UNVERIFIED", out)
rc, js, out = cli(["bogus-subcommand"])
ok("bad subcommand never crashes the caller (exit 0 or argparse usage, no traceback in JSON path)", "Traceback" not in out)

# -------------------------------------------------------------------------------- 3. growth: alert, never auto-widen
print("== growth alert / deterministic-only writes")
f_big = w("big.log", pytest_log(base_ids + ["tests/test_grow.py::test_g1", "tests/test_grow.py::test_g2"]))
st = json.load(open(bp)); st["ts"] = time.time(); json.dump(st, open(bp, "w"))
rc, js, out = cli(["snapshot", "--repo", "demo", "--failing-file", f_big, "--commit", "def456", "--source", "deterministic:test"])
ok("growing red set => FLAG growth alert", js["verdict"] == "FLAG" and "GROWTH" in js["summary"] and len(js["details"]["added"]) == 2, out)
st = json.load(open(bp))
ok("baseline was NOT auto-widened", st["count"] == 3 and len(st["failing"]) == 3 and st["pending_growth"] and len(st["pending_growth"]["added"]) == 2)
ok("growth alert logged", os.path.isfile(os.path.join(OVN, "state", "qa_baselines", "verify", "growth_alerts.jsonl")))
rc, js, out = cli(["compare", "--repo", "demo", "--failing-file", f_pre])
ok("compare surfaces the pending growth alert", js["details"]["growth"] and js["details"]["growth"]["kind"] == "pending" and "GROWTH ALERT" in js["summary"], out)
rc, js, out = cli(["compare", "--repo", "demo", "--failing-file", w("g.log", pytest_log(["tests/test_grow.py::test_g1"]))])
ok("a growth candidate id is still a NEW failure for compare (not tolerated)", js["verdict"] == "FAIL", out)
rc, js, out = cli(["snapshot", "--repo", "demo", "--failing-file", f_big, "--source", "deterministic:test", "--accept-growth"])
ok("--accept-growth (explicit) widens", js["verdict"] == "PASS" and json.load(open(bp))["count"] == 5, out)
rc, js, out = cli(["snapshot", "--repo", "demo", "--failing-file", f_pre, "--source", "deterministic:test"])
st = json.load(open(bp))
ok("a SHRINKING red set is accepted automatically", js["verdict"] == "PASS" and js["details"]["status"] == "stored_shrunk" and st["count"] == 2, out)
rc, js, out = cli(["snapshot", "--repo", "demo2", "--failing-file", os.path.join(FIX, "iptv_truncated_300s.verify.txt")])
ok("truncated log is REFUSED as a snapshot source (no half-baseline)", js["verdict"] == "UNVERIFIED" and "refused_incomplete" in js["details"]["status"] and not os.path.exists(os.path.join(OVN, "state", "qa_baselines", "verify", "demo2.json")), out)
rc, js, out = cli(["snapshot", "--repo", "demo3", "--failing-file", hard_log])
ok("log with QUALITY FAIL refused as snapshot source", js["details"]["status"] == "refused_hard", out)
f_ids = w("ids.txt", "tests/x.py::t1\ntests/x.py::t2\n")
rc, js, out = cli(["snapshot", "--repo", "demo4", "--failing-file", f_ids, "--format", "ids"])
ok("hand-fed id list refused without a deterministic source tag (no LLM-written baselines)", js["details"]["status"] == "refused_hand_fed", out)
rc, js, out = cli(["snapshot", "--repo", "demo4", "--failing-file", f_ids, "--format", "ids", "--source", "deterministic:cron"])
ok("same id list accepted with deterministic:<tool> source", js["verdict"] == "PASS", out)
rc, js, out = cli(["snapshot", "--repo", "demo5", "--failing-file", f_big], env_extra={"OVN_QA_BASELINE_MAX": "3"})
ok("mostly-red suite (over OVN_QA_BASELINE_MAX) refused", js["details"]["status"] == "refused_too_red", out)

# --------------------------------------------------------------------------------------------- 4. overlap risk
print("== masked-risk overlap")
cli(["snapshot", "--repo", "ov", "--failing-file", w("ov.log", pytest_log(["tests/test_llm_service.py::T::t1", "tests/test_other.py::t"])), "--source", "deterministic:t"])
rc, js, out = cli(["compare", "--repo", "ov", "--failing-file", w("ov2.log", pytest_log(["tests/test_llm_service.py::T::t1"])), "--changed-file", "backend/app/services/llm_service.py"])
ok("pre-existing red in the touched area => PASS with RISK note", js["verdict"] == "PASS" and js["details"]["masked_risk"] and "RISK" in js["summary"], out)
rc, js, out = cli(["compare", "--repo", "ov", "--failing-file", w("ov3.log", pytest_log(["tests/test_llm_service.py::T::t1"])), "--changed-file", "backend/app/services/llm_service.py", "--strict-overlap"])
ok("--strict-overlap turns that into UNVERIFIED", js["verdict"] == "UNVERIFIED", out)
rc, js, out = cli(["compare", "--repo", "ov", "--failing-file", w("ov4.log", pytest_log(["tests/test_other.py::t"])), "--changed-file", "backend/app/services/llm_service.py", "--strict-overlap"])
ok("unrelated pre-existing red with --strict-overlap still PASS", js["verdict"] == "PASS" and not js["details"]["masked_risk"], out)

# -------------------------------------------------------------------------------------------- 5. refresh (box-style repo)
print("== refresh (fake clone + fake venv pytest)")
REPOS = os.path.join(T, "repos")
rp = os.path.join(REPOS, "fakerepo")
os.makedirs(os.path.join(rp, "backend", ".venv", "bin"))
os.makedirs(os.path.join(rp, "backend", "tests"))
fake = os.path.join(rp, "backend", ".venv", "bin", "pytest")
with open(fake, "w") as f:
    f.write("#!/bin/sh\nif [ -f SLOW ]; then sleep 30; fi\necho '.F. [100%]'\necho 'FAILED tests/test_a.py::test_x - assert 1 == 2'\necho '1 failed, 2 passed in 0.10s'\nexit 1\n")
os.chmod(fake, 0o755)
open(os.path.join(rp, "backend", "tests", "test_a.py"), "w").write("def test_x():\n    assert 1 == 2\n")
open(os.path.join(rp, ".gitignore"), "w").write(".venv/\n")
gi = lambda *a: subprocess.run(["git", "-C", rp] + list(a), capture_output=True, text=True)  # noqa: E731
gi("init", "-q", "-b", "main"); gi("config", "user.email", "t@t"); gi("config", "user.name", "t")
gi("add", "backend/tests/test_a.py", ".gitignore"); gi("commit", "-q", "-m", "init")
gi("update-ref", "refs/remotes/origin/overnight/feature", "HEAD")
rc, js, out = cli(["refresh", "--repo", "fakerepo"], env_extra={"OVN_REPOS_DIR": REPOS})
ok("refresh runs the suite in a detached worktree and snapshots the red set", js["verdict"] == "PASS" and js["details"]["count"] == 1, out)
bl = json.load(open(os.path.join(OVN, "state", "qa_baselines", "verify", "fakerepo.json")))
ok("refresh baseline id is package-prefixed like the staged runner's verify.log ids", bl["failing"] == ["[backend] tests/test_a.py::test_x"] and bl["source"] == "deterministic:refresh", bl)
wt_left = subprocess.run(["git", "-C", rp, "worktree", "list"], capture_output=True, text=True).stdout.strip().splitlines()
ok("refresh left no worktree behind and the live clone is clean", len(wt_left) == 1 and not subprocess.run(["git", "-C", rp, "status", "--porcelain"], capture_output=True, text=True).stdout.strip())
rc, js, out = cli(["compare", "--repo", "fakerepo", "--failing-file", w("fr.log", "-- pytest FULL in backend --\n.F. [100%]\nFAILED tests/test_a.py::test_x - assert\n=== 1 failed, 2 passed in 1.0s ===\n"), "--changed-file", "backend/app/other.py"])
ok("refresh-written baseline matches a runner verify.log (PASS)", js["verdict"] == "PASS", out)
os.makedirs(os.path.join(rp, "backend", ".venv", "bin"), exist_ok=True)
open(os.path.join(rp, "backend", "SLOW"), "w").write("")
gi("add", "-f", "backend/SLOW"); gi("commit", "-q", "-m", "slow"); gi("update-ref", "refs/remotes/origin/overnight/feature", "HEAD")
before = open(os.path.join(OVN, "state", "qa_baselines", "verify", "fakerepo.json")).read()
rc, js, out = cli(["refresh", "--repo", "fakerepo", "--timeout", "2"], env_extra={"OVN_REPOS_DIR": REPOS})
ok("suite timeout => UNVERIFIED and baseline untouched", js["verdict"] == "UNVERIFIED" and "timed out" in js["summary"] and open(os.path.join(OVN, "state", "qa_baselines", "verify", "fakerepo.json")).read() == before, out)
rc, js, out = cli(["refresh", "--repo", "ghost-repo"], env_extra={"OVN_REPOS_DIR": REPOS})
ok("unknown repo => UNVERIFIED", js["verdict"] == "UNVERIFIED", out)
os.makedirs(os.path.join(REPOS, "nopy", ".git"))
rc, js, out = cli(["refresh", "--repo", "nopy"], env_extra={"OVN_REPOS_DIR": REPOS})
ok("repo without a venv pytest => NA (missing tool is not PASS)", js["verdict"] == "NA", out)

# --------------------------------------------------------------------------------------------------- 6. replay (synthetic)
print("== replay (synthetic stage_runs)")
SR = os.path.join(T, "stage_runs")
os.makedirs(SR)


def mkrun(repo, stamp, item, verified, log=None, passed=1):
    base = "%s-%s-111" % (repo, stamp)
    with open(os.path.join(SR, base + ".jsonl"), "w") as f:
        f.write(json.dumps({"run": stamp + "-111", "repo": repo, "tier": 3, "item": item, "event": "decomposed", "steps": 1,
                            "plan": [{"desc": "d", "files": ["app/%s.py" % item.split()[0]], "verify": "v"}]}) + "\n")
        f.write(json.dumps({"run": stamp + "-111", "event": "verify", "verified": verified}) + "\n")
    if log is not None:
        open(os.path.join(SR, base + ".verify.log"), "w").write("2026-10-01 00:00:00 independent full-verify\n-- pytest FULL in backend --\n" + log)


RED = ["tests/test_red.py::test_a", "tests/test_red.py::test_b"]
mkrun("r2", "20261001-010000", "one thing", False, pytest_log(["tests/t.py::x"]))   # C: rescued by the NEXT run's evidence
mkrun("r2", "20261001-020000", "two thing", False, pytest_log(["tests/t.py::x"]))   # A and C: rescued by the previous run
mkrun("r1", "20261001-010000", "alpha thing", True, pytest_log([]))
mkrun("r1", "20261001-020000", "beta thing", False, pytest_log(RED))             # first red: no evidence before -> UNVERIFIED under A
mkrun("r1", "20261001-030000", "gamma thing", False, pytest_log(RED[:1]))        # subset of earlier red from other item -> rescued
mkrun("r1", "20261001-040000", "delta thing", False, pytest_log(RED[:1] + ["tests/test_new.py::test_n"]))  # new id -> FAIL
mkrun("r1", "20261001-050000", "eps thing", False, pytest_log([]) + "-- QUALITY FAIL: app/x.py is a stub --\n")  # hard
mkrun("r1", "20261001-060000", "zeta thing", False, "........ [ 40%]\n")           # truncated
mkrun("r1", "20261001-070000", "eta thing", False, None)                          # never reached full_verify
mkrun("r1", "20261001-080000", "theta thing", True, pytest_log([]))               # green resets evidence
mkrun("r1", "20261001-090000", "iota thing", False, pytest_log(RED[:1]))          # after green: no prior evidence
N_SR = len(os.listdir(SR))
rc, js, out = cli(["replay", "--logs-dir", SR])
d = js["details"] if js else {}
ok("replay counts runs", d.get("runs_total") == 11 and d.get("verified_true") == 2 and d.get("verified_false") == 9, d)
ok("replay: never_reached_full_verify counted separately", d.get("never_reached_full_verify") == 1, d)
cl = d.get("classes", {})
ok("replay classes: 6 test-failure runs (beta,gamma,delta,iota,r2 x2), 1 gate fail, 1 incomplete", cl.get("test_failures_only") == 6 and cl.get("gate_fail_only_quality_semantic_other") == 1 and cl.get("incomplete_log") == 1, cl)
pa = d.get("proxy_A", {})
ok("replay proxy A: gamma rescued, delta FAIL, beta+iota UNVERIFIED (no evidence), green run resets evidence",
   pa.get("test_failures_only:PASS") == 2 and pa.get("test_failures_only:FAIL") == 1 and pa.get("test_failures_only:UNVERIFIED") == 3, pa)
pc = d.get("proxy_C", {})
ok("replay proxy C (also looks at the NEXT run) rescues strictly more than A (r2 first run)", pc.get("test_failures_only:PASS") == pa.get("test_failures_only:PASS") + 1, (pa, pc))
ok("replay proxy B needs >=2 distinct other items: rescues nothing here", d["proxy_B"].get("test_failures_only:PASS", 0) == 0, d["proxy_B"])
ok("replay is read-only wrt the logs dir", len(os.listdir(SR)) == N_SR)

# ------------------------------------------------------------------------------------ 7. real-log fixtures through CLI
print("== real logs (2026-10-01 TAA stale-pricing episode)")
ok_snap = cli(["snapshot", "--repo", "taa", "--failing-file", os.path.join(FIX, "taa_stale_pricing_21red.verify.txt"), "--commit", "x", "--source", "deterministic:t"])[1]
ok("snapshot from the real 21-red log", ok_snap["verdict"] == "PASS" and ok_snap["details"]["count"] == 21, ok_snap)
rc, js, out = cli(["compare", "--repo", "taa", "--failing-file", os.path.join(FIX, "taa_stale_pricing_5red.verify.txt"), "--changed-file", "backend/app/other.py"])
ok("real 02:16 verify (5 of the same stale-pricing tests) => PASS; the old runner discarded it", js["verdict"] == "PASS" and len(js["details"]["preexisting"]) == 5, out)


# ------------------------------------------------------------------------- 9. FIX round (adversarial review of 1e6eab1)
print("== fix round: skipped stages, CLI contract, parser-level failed build, growth-after-expiry, redaction, java/old-kotlin ids")
RED1 = "tests/test_pre.py::test_old"
PYRED = "-- pytest FULL in backend --\n.F. [100%%]\nFAILED %s - assert\n=== 1 failed, 2 passed in 1.0s ===\n" % RED1
cli(["snapshot", "--repo", "skp", "--failing-file", w("skp_base.log", PYRED), "--format", "verify-log", "--commit", "b", "--source", "deterministic:t"])
f_py = w("skp.log", PYRED)
rc, js, out = cli(["compare", "--repo", "skp", "--failing-file", f_py, "--format", "verify-log", "--runner-failed"])
ok("REVIEW-1 pre-existing pytest red + later stages skipped + changed files unknown => UNVERIFIED (was PASS)", js["verdict"] == "UNVERIFIED" and "skipped" in js["summary"], out)
ok("REVIEW-1 skipped stage list is reported", set(js["details"].get("skipped_stages", [])) >= {"gradle", "gut", "vitest", "shell", "docker"} or js["details"].get("skipped_stages") is None, js["details"])
rc, js, out = cli(["compare", "--repo", "skp", "--failing-file", f_py, "--format", "verify-log", "--runner-failed", "--changed-file", "backend/app/x.py"])
ok("REVIEW-1 control: python-only change, skipped stages irrelevant => still PASS (gate keeps its value)", js["verdict"] == "PASS" and js["details"].get("skipped_stages"), out)
for fname, what in (("tools/run.sh", "shell"), ("backend/Dockerfile", "docker"), ("app/src/Main.kt", "gradle"), ("tests/a.gd", "gut"), ("web/a.ts", "vitest")):
    rc, js, out = cli(["compare", "--repo", "skp", "--failing-file", f_py, "--format", "verify-log", "--runner-failed", "--changed-file", fname])
    ok("REVIEW-1 %s change with %s stage skipped => UNVERIFIED, not PASS" % (fname, what), js["verdict"] == "UNVERIFIED", out)
wt = os.path.join(T, "wt_sh")
os.makedirs(os.path.join(wt, "tools"))
open(os.path.join(wt, "tools", "bad.sh"), "w").write("#!/bin/bash\nif then fi (\n")
open(os.path.join(wt, "tools", "good.sh"), "w").write("#!/bin/bash\necho hi\n")
rc, js, out = cli(["compare", "--repo", "skp", "--failing-file", f_py, "--format", "verify-log", "--runner-failed", "--changed-file", "tools/bad.sh", "--worktree", wt])
ok("REVIEW-1 skipped shell stage is run independently: syntax error => FAIL", js["verdict"] == "FAIL", out)
rc, js, out = cli(["compare", "--repo", "skp", "--failing-file", f_py, "--format", "verify-log", "--runner-failed", "--changed-file", "tools/good.sh", "--worktree", wt])
ok("REVIEW-1 skipped shell stage independently checked clean => PASS", js["verdict"] == "PASS", out)
GRADLE_RED = "-- pytest FULL in backend --\n.. [100%]\n=== 2 passed in 1.0s ===\n-- gradlew test FULL in app --\n> Task :app:compileDebugUnitTestKotlin FAILED\nBUILD FAILED in 3s\n"
cli(["snapshot", "--repo", "gk", "--failing-file", w("gk_base.log", GRADLE_RED), "--format", "verify-log", "--commit", "b", "--source", "deterministic:t"])
rc, js, out = cli(["compare", "--repo", "gk", "--failing-file", w("gk.log", GRADLE_RED), "--format", "verify-log", "--runner-failed", "--changed-file", "app/src/test/A.kt"])
ok("REVIEW-1 gradle red baselined but this change edits Kotlin and GUT/vitest/etc never ran => UNVERIFIED", js["verdict"] == "UNVERIFIED", out)
rc, js, out = cli(["compare", "--repo", "gk", "--failing-file", w("gk.log", GRADLE_RED), "--format", "verify-log", "--runner-failed", "--changed-file", "backend/a.py"])
ok("REVIEW-1 gradle red baselined, python-only change => PASS", js["verdict"] == "PASS", out)
rc, js, out = cli(["compare", "--repo", "skp", "--failing-file", f_py, "--format", "verify-log", "--runner-failed", "--changed-file", "backend/app/x.py", "--changed-file", "backend/Dockerfile"])
ok("REVIEW-1 python + Dockerfile change => UNVERIFIED (docker build never ran)", js["verdict"] == "UNVERIFIED", out)

for args, name in ((["compare", "--bogus"], "unknown flag"), ([], "no args"), (["compare", "--repo", "x", "--days", "abc"], "bad int"), (["nosuchcmd"], "bad subcommand"),
                   (["--help"], "--help"), (["compare", "--repo"], "missing value")):
    rc, js, out = cli(args)
    ok("REVIEW-2 CLI contract: %s => rc 0 + UNVERIFIED JSON (was rc 2, no JSON)" % name, rc == 0 and js["verdict"] == "UNVERIFIED", (rc, out))

f_gb = w("gb.log", "-- gradlew test FULL in app --\nFAILURE: Build failed with an exception.\nBUILD FAILED in 3s\n")
rc, js, out = cli(["compare", "--repo", "gk", "--failing-file", f_gb, "--format", "verify-log"])
ok("REVIEW-3 gradle BUILD FAILED with no ids, no --runner-failed => UNVERIFIED (was PASS 'no failing tests')", js["verdict"] == "UNVERIFIED", out)
rc, js, out = cli(["compare", "--repo", "gk", "--failing-file", f_gb, "--format", "gradle"])
ok("REVIEW-3 same via --format gradle", js["verdict"] == "UNVERIFIED", out)
rc, js, out = cli(["compare", "--repo", "gk", "--failing-file", w("empty.log", ""), "--format", "verify-log"])
ok("REVIEW-3 empty verify-log without --runner-failed => UNVERIFIED (was PASS)", js["verdict"] == "UNVERIFIED", out)
rc, js, out = cli(["compare", "--repo", "gk", "--failing-file", w("ie.log", "INTERNALERROR> Traceback boom\n=== no tests ran in 0.1s ===\n"), "--format", "pytest"])
ok("REVIEW-3 pytest INTERNALERROR => UNVERIFIED", js["verdict"] == "UNVERIFIED", out)
ok("REVIEW-3 green gradle still complete + empty ids", bv.parse_gradle("BUILD SUCCESSFUL in 2s\n")["complete"])

# growth hidden by waiting out the TTL
bv_store = os.path.join(OVN, "state", "qa_baselines", "verify")
cli(["snapshot", "--repo", "gexp", "--failing-file", w("g1.ids", "tests/a.py::t1\n"), "--format", "ids", "--source", "deterministic:t"])
bp = os.path.join(bv_store, "gexp.json")
bl = json.load(open(bp))
bl["ts"] -= 25 * 3600
json.dump(bl, open(bp, "w"))
ga = os.path.join(bv_store, "growth_alerts.jsonl")
n0 = len(open(ga).read().splitlines()) if os.path.exists(ga) else 0
rc, js, out = cli(["snapshot", "--repo", "gexp", "--failing-file", w("g2.ids", "tests/a.py::t1\ntests/a.py::t2\ntests/a.py::t3\n"), "--format", "ids", "--source", "deterministic:t"])
rows = open(ga).read().splitlines()[n0:] if os.path.exists(ga) else []
ok("NONBLOCK growth after TTL expiry is logged to growth_alerts.jsonl (was silent)", any(json.loads(r).get("kind") == "growth_accepted_after_expiry" and json.loads(r).get("n_added") == 2 for r in rows), (rows, out))

# secrets in param ids
sec = "FAILED tests/t.py::test_s[postgres://u:SECRETPW@h/db] - boom\n=== 1 failed in 1.0s ===\n"
rc, js, out = cli(["parse", "--failing-file", w("sec.log", sec), "--format", "pytest"])
ok("NONBLOCK url credentials in a param id are redacted in stdout", "SECRETPW" not in out and "***" in out, out)
cli(["snapshot", "--repo", "secrepo", "--failing-file", w("sec2.log", sec), "--format", "pytest", "--commit", "c"])
cli(["snapshot", "--repo", "secrepo", "--failing-file", w("sec3.log", sec.replace("::test_s[", "::test_s2[")), "--format", "pytest", "--commit", "c"])
blob = open(os.path.join(bv_store, "secrepo.json")).read() + open(ga).read()
ok("NONBLOCK redacted in the baseline json and growth_alerts.jsonl too", "SECRETPW" not in blob)
rc, js, out = cli(["parse", "--failing-file", w("sec4.log", "FAILED tests/t.py::test_k[token=abcdef123456XYZ] - x\nFAILED tests/t.py::test_plain_but_long_function_name_with_many_words_in_it - y\n=== 2 failed in 1.0s ===\n"), "--format", "pytest"])
ok("NONBLOCK token= redacted but a long ordinary test name is untouched", "abcdef123456XYZ" not in out and "test_plain_but_long_function_name_with_many_words_in_it" in out, out)

rc, js, out = cli(["parse", "--failing-file", w("sec5.log", "FAILED tests/test_auth_tokens.py::test_authentication_flow_works - x\nFAILED app/AuthViewModelTest.kt::t[Authorization: Bearer abcdef123456] - y\n=== 2 failed in 1.0s ===\n"), "--format", "pytest"])
ok("NONBLOCK redaction does not mangle ordinary ids containing auth/token words; bearer redacted", "test_auth_tokens.py::test_authentication_flow_works" in out and "AuthViewModelTest.kt" in out and "abcdef123456" not in out, out)
# javac + legacy kotlin ids
jl = "> Task :app:compileDebugJavaWithJavac FAILED\n/tmp/stage-1/app/src/main/java/com/x/A.java:12: error: cannot find symbol\ne: /tmp/stage-1/app/src/Old.kt: (3, 4): Unresolved reference: q\nBUILD FAILED in 2s\n"
pg = bv.parse_gradle(jl)
ok("NONBLOCK javac and legacy-kotlin compile errors get per-file ids", "javac:app/src/main/java/com/x/A.java" in pg["ids"] and "kotlinc:app/src/Old.kt" in pg["ids"], pg["ids"])

# ------------------------------------------------------------------------------------------------------ 8. recording
print("== shadow recording")
env = dict(CLEAN_ENV)
p = subprocess.run(["env", "-i"] + ["%s=%s" % kv for kv in env.items()] + [sys.executable, SCRIPT, "compare", "--repo", "taa", "--failing-file", f_green],
                   cwd=T, capture_output=True, text=True)
rows = open(os.path.join(OVN, "state", "qa_shadow", "baseline.jsonl")).read().splitlines()
ok("without --no-record a result row is appended to state/qa_shadow/baseline.jsonl", len(rows) == 1 and json.loads(rows[0])["gate"] == "baseline")

shutil.rmtree(T, ignore_errors=True)
print("\nqa_baseline: %d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
