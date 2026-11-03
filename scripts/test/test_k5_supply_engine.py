#!/usr/bin/env python3
"""Tests for package K5-supply-engine (2026-11-01): the supply-runway forecast, the explorer lens yield cap, the fresh local-research evidence, the planner small-decomposition marker slug
handling, and the configurable mutation-scan repo list. Hermetic temp dirs, no box, no model, no network.

K5_SCRIPTS=<dir> runs the same checks against a different copy of scripts/ (the mutant runner below: every mutant must make at least one check fail).
--no-mutants skips the mutant runner (the mutant children use it)."""
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPTS = os.environ.get("K5_SCRIPTS") or os.path.abspath(os.path.join(HERE, ".."))
os.environ["TZ"] = "UTC"      # 2026-11-02 (P3): NOW and every date derived from it are timezone-independent (same pin as lib_test_tz.sh)
time.tzset()
BASE = os.path.realpath(tempfile.mkdtemp(prefix="k5-supply-"))
import atexit  # noqa: E402
atexit.register(lambda: shutil.rmtree(BASE, ignore_errors=True) if os.path.basename(BASE).startswith("k5-supply-") else None)
ROOT = os.path.join(BASE, "q")
STATE = os.path.join(ROOT, "state")
os.makedirs(STATE)
for k in list(os.environ):
    if k.startswith(("OVN_FORECAST", "OVN_SUPPLY_FORECAST", "OVN_QE_YIELD", "OVN_LR_", "OVN_MUT_")):
        del os.environ[k]
os.environ["OVN_DIR"] = ROOT
os.environ["OVN_NOTIFY_STATE"] = STATE
sys.path.insert(0, SCRIPTS)

P = F = 0


def check(name, cond):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name)


def load(name):
    spec = importlib.util.spec_from_file_location(name + "_k5", os.path.join(SCRIPTS, name + ".py"))
    m = importlib.util.module_from_spec(spec)
    sys.modules[name] = m          # sibling imports (ovn_supply_ledger from the forecast) resolve to THIS copy
    spec.loader.exec_module(m)
    return m


def w(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "w").write(text)


NOW = float(time.mktime((2026, 11, 1, 12, 0, 0, 0, 0, -1)))


def iso(t):
    return time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(t))


# =========================================================================== 1. supply forecast
sf = load("ovn_supply_forecast")
rows = []


def landed(repo, n, oldest_days_ago):
    for i in range(n):
        t = NOW - oldest_days_ago * 86400 + i * (oldest_days_ago * 86400 - 600) / max(1, n - 1)
        rows.append({"ts": iso(t), "repo": repo, "class": "landed", "status": "landed", "item_hash": "%s-%d" % (repo, i), "duration_s": 60, "feat_tag": "x"})


landed("ra", 28, 7)      # 4/day
landed("rb", 28, 7)      # 4/day, nothing in hand
landed("rd", 28, 7)      # 4/day, 2 pullable
rows.append({"ts": iso(NOW - 3600), "repo": "rc", "class": "skipped", "status": "skip(exhausted)", "item_hash": "", "duration_s": 0})   # only a heartbeat: burn must be 0 -> no forecast
rows.append({"ts": iso(NOW - 3600), "repo": "ra", "class": "reverted", "status": "reverted", "item_hash": "ra-rev", "duration_s": 60})      # a revert is not burn
w(os.path.join(STATE, "outcomes.jsonl"), "\n".join(json.dumps(r) for r in rows) + "\n")


def mk(repo, n_pull, n_ready):
    os.makedirs(os.path.join(ROOT, "repos", repo), exist_ok=True)
    w(os.path.join(ROOT, "backlog", repo + ".md"), "# b\n" + "".join("- [ ] [T1] scripts/f%d.py - change %d. VERIFY: `true`\n" % (i, i) for i in range(n_pull)))
    w(os.path.join(ROOT, "roadmap", repo + ".md"), "# r\n" + "".join("- [ ] [P2] [ready] Feature %d for %s\n" % (i, repo) for i in range(n_ready)) + "- [ ] [P2] [decomposed] Old one\n- [ ] [P3] [needs-research] Maybe\n")


mk("ra", 3, 1)      # supply 3+5=8 -> 48 h
mk("rb", 0, 0)      # supply 0 -> 0 h
mk("rc", 0, 0)
mk("rd", 2, 0)      # supply 2 -> 12 h
fc = sf.collect(now=NOW, root=ROOT, state=STATE, repos=["ra", "rb", "rc", "rd"])
R = fc["repos"]
check("F1 burn is distinct landed items per day over the covered span (4/d)", abs(R["ra"]["burn_per_day"] - 4.0) < 0.05)
check("F2 a repo with plenty of supply is not short (runway 48h)", R["ra"]["short"] is False and R["ra"]["runway_h"] == 48.0)
check("F3 decomposable yield is ready x 5", R["ra"]["decomposable"] == 5 and R["ra"]["supply"] == 8 and R["rb"]["ready"] == 0)
check("F4 dry repo with burn is short, high priority, runway 0", R["rb"]["short"] and R["rb"]["priority"] == "high" and R["rb"]["runway_h"] == 0.0)
check("F5 shortfall covers 48h of burn: ceil(4*48/24 - 0) = 8 items = 2 features", R["rb"]["shortfall_items"] == 8 and R["rb"]["shortfall_features"] == 2)
check("F6 12h runway is short with normal priority", R["rd"]["short"] and R["rd"]["priority"] == "normal" and R["rd"]["runway_h"] == 12.0 and R["rd"]["shortfall_items"] == 6)
check("F7 a repo that burns nothing has no runway and no request (unknown, not zero)", R["rc"]["runway_h"] is None and R["rc"]["short"] is False)
check("F8 a revert row is not counted as burn (ra still 4/d)", R["ra"]["burn_per_day"] < 4.1)
check("F9 pure arithmetic: exactly at the floor is not short", not sf.forecast_repo("x", 24, 0, 24.0, 5, 24.0, 6.0, 48.0)["short"] and sf.forecast_repo("x", 23, 0, 24.0, 5, 24.0, 6.0, 48.0)["short"])

# shadow (default): outputs json + log, NO research_requests, NO digest line
check("F10 default mode is shadow", sf.mode() == "shadow" and fc["mode"] == "shadow")
sf.write_outputs(fc, root=ROOT, state=STATE, stamp="T")
check("F11 shadow writes state/supply_forecast.json", os.path.isfile(os.path.join(STATE, "supply_forecast.json")))
check("F12 shadow writes NO research_requests", not os.path.isdir(os.path.join(STATE, "research_requests")) or not os.listdir(os.path.join(STATE, "research_requests")))
log = open(os.path.join(ROOT, "logs", "supply_forecast.log")).read()
check("F13 shadow logs one line per short repo, tagged [shadow]", log.count("[shadow]") == 2 and "rb: runway 0h" in log)
check("F14 shadow produces no digest bullet", sf.digest_lines(fc) == [])
# on
os.environ["OVN_SUPPLY_FORECAST"] = "on"
fc_on = sf.collect(now=NOW, root=ROOT, state=STATE, repos=["ra", "rb", "rc", "rd"])
sf.write_outputs(fc_on, root=ROOT, state=STATE, stamp="T")
rq = os.path.join(STATE, "research_requests")
check("F15 mode on writes a request per short repo only", sorted(os.listdir(rq)) == ["rb.json", "rd.json"])
req = json.load(open(os.path.join(rq, "rb.json")))
check("F16 request carries priority + shortfall + runway", req["priority"] == "high" and req["shortfall_items"] == 8 and req["shortfall_features"] == 2 and req["runway_h"] == 0.0 and req["repo"] == "rb")
dl = sf.digest_lines(fc_on)
check("F17 mode on gives exactly one digest bullet naming the short repos", len(dl) == 1 and "rb 0h" in dl[0] and "rd 12h" in dl[0] and "HIGH" in dl[0])
mk("rd", 30, 0)      # rd recovers
fc2 = sf.collect(now=NOW, root=ROOT, state=STATE, repos=["ra", "rb", "rc", "rd"])
sf.write_outputs(fc2, root=ROOT, state=STATE, stamp="T")
check("F18 a recovered repo's stale request is removed", sorted(os.listdir(rq)) == ["rb.json"])
os.environ["OVN_SUPPLY_FORECAST"] = "off"
check("F19 mode off is a no-op entry point", sf.main(["x"]) == 0 and sf.mode() == "off")
del os.environ["OVN_SUPPLY_FORECAST"]
check("F20 fresh_forecast respects max age", sf.fresh_forecast(NOW + 60, STATE) is not None and sf.fresh_forecast(NOW + 4 * 3600, STATE) is None)

# hourly-update hook in ovn_notify
sys.modules.pop("ovn_notify", None)
import ovn_notify as notify  # noqa: E402
notify.now = lambda: NOW
os.environ["OVN_SUPPLY_FORECAST"] = "on"
fcn = sf.collect(now=NOW, root=ROOT, state=STATE, repos=["rb"])
sf.write_outputs(fcn, root=ROOT, state=STATE, stamp="T")
del os.environ["OVN_SUPPLY_FORECAST"]
check("F21 ovn_notify.forecast_lines shows the bullet from a fresh mode-on forecast", len(notify.forecast_lines(NOW + 60)) == 1)
os.environ["OVN_FORECAST_LINE"] = "0"
check("F22 OVN_FORECAST_LINE=0 silences it", notify.forecast_lines(NOW + 60) == [])
del os.environ["OVN_FORECAST_LINE"]

# =========================================================================== 2. explorer lens yield cap
qx = load("ovn_qwen_explore")
YL = "performance"
check("Y1 default mode is shadow", qx.yield_cap_mode() == "shadow")
L = {"lenses": {}, "files": {}}


def passes(lens, n, written=0, dialect=False, calls=3, repo="rq"):
    for _ in range(n):
        qx.update_yield(repo, L, lens, written, dialect, calls, NOW)


passes(YL, 3)
check("Y2 three empty passes: not yet parked", YL not in qx.yield_skip_set(L, NOW) and L["empty_streak"][YL] == 3)
passes(YL, 1)
check("Y3 the 4th consecutive empty pass parks the lens for today", YL in qx.yield_skip_set(L, NOW))
check("Y4 ...but not tomorrow (rest of the day only)", YL not in qx.yield_skip_set(L, NOW + 86400))
L2 = {"lenses": {}, "files": {}}
for lens in ("feature-ideation", "bug-hunt", "completeness"):
    for _ in range(9):
        qx.update_yield("rq", L2, lens, 0, False, 3, NOW)
check("Y5 feature-ideation, bug-hunt and completeness are never parked", qx.yield_skip_set(L2, NOW) == set() and "empty_streak" not in L2)
passes(YL, 1, written=2)
check("Y6 a productive pass resets the streak and un-parks", L["empty_streak"][YL] == 0 and YL not in qx.yield_skip_set(L, NOW))
L3 = {"lenses": {}, "files": {}}
for _ in range(6):
    qx.update_yield("rq", L3, "a11y-ux", 0, True, 3, NOW)
for _ in range(6):
    qx.update_yield("rq", L3, "a11y-ux", 0, False, 0, NOW)
check("Y7 verify-dialect-only passes and zero-model-call passes do not count as empty", "a11y-ux" not in qx.yield_skip_set(L3, NOW) and not L3.get("empty_streak"))
# accepted in the last 7 days protects the lens
os.makedirs(os.path.join(STATE, "qwen_explore"), exist_ok=True)
w(os.path.join(STATE, "qwen_explore", "accepted.jsonl"), json.dumps({"ts_epoch": NOW - 2 * 86400, "repo": "rq", "lens": "dead-code", "title": "t"}) + "\n"
  + json.dumps({"ts_epoch": NOW - 9 * 86400, "repo": "rq", "lens": "type-safety", "title": "old"}) + "\n")
L4 = {"lenses": {}, "files": {}}
for lens in ("dead-code", "type-safety"):
    for _ in range(5):
        qx.update_yield("rq", L4, lens, 0, False, 3, NOW)
check("Y8 a lens with an accepted item in the last 7 days is NOT parked", "dead-code" not in qx.yield_skip_set(L4, NOW))
check("Y9 an accepted item older than 7 days does not protect it", "type-safety" in qx.yield_skip_set(L4, NOW))
check("Y10 another repo's accepts do not protect it", qx.lens_accepts_in_window("other", "dead-code", NOW) == 0 and qx.lens_accepts_in_window("rq", "dead-code", NOW) == 1)
cfg = qx.DEFAULT_CFG
names = qx.applicable_lenses(cfg)
Lp = {"lenses": {}, "files": {}}
first, _w = qx.pick_lens(cfg, Lp, NOW)
nxt, _w = qx.pick_lens(cfg, Lp, NOW, skip={first})
check("Y11 pick_lens(skip=...) steps over the parked lens", first in names and nxt != first and nxt in names)
check("Y12 pick_lens without skip is unchanged", qx.pick_lens(cfg, Lp, NOW)[0] == first)
check("Y13 a forced lens ignores skip", qx.pick_lens(cfg, Lp, NOW, forced=first, skip={first})[0] == first)
os.environ["OVN_QE_YIELD_CAP"] = "off"
L5 = {"lenses": {}, "files": {}}
for _ in range(8):
    qx.update_yield("rq", L5, YL, 0, False, 3, NOW)
check("Y14 OVN_QE_YIELD_CAP=off records nothing and skips nothing", not L5.get("empty_streak") and qx.yield_skip_set(L, NOW) == set())
del os.environ["OVN_QE_YIELD_CAP"]
os.environ["OVN_QE_YIELD_N"] = "2"
qy = load("ovn_qwen_explore")
L6 = {"lenses": {}, "files": {}}
for _ in range(2):
    qy.update_yield("rq", L6, YL, 0, False, 3, NOW)
check("Y15 OVN_QE_YIELD_N is configurable", YL in qy.yield_skip_set(L6, NOW))
del os.environ["OVN_QE_YIELD_N"]
# ledger integration: _ledger_pass persists the streak/skip
os.environ["OVN_DIR"] = ROOT
qz = load("ovn_qwen_explore")
os.makedirs(os.path.join(STATE, "qwen_explore"), exist_ok=True)
Lz = qz.load_ledger("rz")
# 2026-11-02 (P3): _ledger_pass stamps lens_skip with today_str(now_ts()) = the REAL date. The test compared it with today_str(NOW) (a fixed 2026-11-01), so Y16 passed only on 11-01
# (the day it was written) and failed in every cron run after midnight. The clock the code reads is now pinned to NOW.
qz.now_ts = lambda: NOW
for _ in range(4):
    qz._ledger_pass("rz", Lz, YL, ["f.py"], 0, False, NOW, False, 3)
saved = json.load(open(os.path.join(STATE, "qwen_explore", "ledger_rz.json")))
check("Y16 _ledger_pass persists empty_streak and lens_skip in the ledger", saved["empty_streak"][YL] == 4 and saved["lens_skip"][YL] == qz.today_str(NOW))

# =========================================================================== 3. fresh local-research evidence
lr = load("ovn_local_research")
rr = os.path.join(BASE, "lrq", "repos", "rl")
os.makedirs(os.path.join(rr, "app"))
os.makedirs(os.path.join(rr, "tests"))
body = "".join("    x%d = compute(%d)\n" % (i, i) for i in range(10))
w(os.path.join(rr, "app", "svc.py"), "def covered_one(a):\n    return a\n\n\ndef hot_gap(a, b):\n" + body + "    return a + b\n\n\ndef _private_gap():\n" + body + "    return 1\n")
w(os.path.join(rr, "tests", "test_svc.py"), "def test_a():\n    pass\n")
w(os.path.join(rr, "app", "todo_mod.py"), "# TODO: handle retries\nX = 1\n")
subprocess.run(["git", "init", "-q"], cwd=rr, check=True)
subprocess.run(["git", "-c", "user.email=t@t", "-c", "user.name=t", "add", "-A"], cwd=rr, check=True)
subprocess.run(["git", "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-qm", "init"], cwd=rr, check=True)
lst = os.path.join(BASE, "lrq", "state")
w(os.path.join(lst, "coverage_latest_rl.json"), json.dumps({"files": {"/home/x/overnight-queue/repos/rl/app/svc.py": {"missing_lines": list(range(6, 17)) + list(range(20, 31))},
                                                                      "app/todo_mod.py": {"missing_lines": []}}}))
w(os.path.join(lst, "ruff_rl.json"), json.dumps([{"code": "F841", "filename": "app/svc.py", "location": {"row": 7, "column": 1}, "message": "local variable unused"},
                                                 {"code": "F841", "filename": "app/svc.py", "location": {"row": 9, "column": 1}, "message": "dup code same file"},
                                                 {"code": "E501", "filename": "tests/test_svc.py", "location": {"row": 1}, "message": "test file ignored"}]))
w(os.path.join(lst, "tsc_rl.txt"), "app/svc.py(3,5): error TS2345: Argument of type x\nnoise line\n")
fresh = lr.collect_fresh(rr, "rl", lst)
kinds = sorted({e["kind"] for e in fresh})
check("L1 fresh sources yield coverage, lint and todo evidence", kinds == ["lint-finding", "todo", "uncovered-function"])
unc = [e for e in fresh if e["kind"] == "uncovered-function"]
check("L2 uncovered public function found; private one and covered one are not", [e["text"].split("`")[1] for e in unc] == ["hot_gap"])
check("L3 absolute report paths are mapped to the repo-relative file", unc[0]["file"] == "app/svc.py" and unc[0]["line"] == 5)
lint = [e for e in fresh if e["kind"] == "lint-finding"]
check("L4 ruff + tsc findings, one per (file, code), test files dropped", len(lint) == 2 and {e["text"].split(":")[0] for e in lint} == {"ruff F841", "tsc TS2345"})
todo = [e for e in fresh if e["kind"] == "todo"]
check("L5 the TODO comes from the origin tree scan", len(todo) == 1 and todo[0]["file"] == "app/todo_mod.py" and todo[0]["line"] == 1)
only_cov = lr.collect_fresh(rr, "rl", lst, skip=lambda e: e["kind"] != "uncovered-function")
check("L6 skip() (covered / dup memory) filters fresh evidence too", [e["kind"] for e in only_cov] == ["uncovered-function"])
have = lr.collect_fresh(rr, "rl", lst, have=[{"file": "app/todo_mod.py", "line": 1}])
check("L7 evidence already collected (same file:line) is not repeated", not any(e["kind"] == "todo" for e in have))
check("L8 no report files and no git history = no fresh evidence, no crash", lr.collect_fresh(os.path.join(BASE, "nope"), "rl", os.path.join(BASE, "nostate")) == [])
check("L9 default mode is shadow", lr.fresh_mode() == "shadow")
# end-to-end through main(--evidence-only): the normal collectors are dry for this tiny repo (nothing but the todo)
lroot = os.path.join(BASE, "lrq")
w(os.path.join(lroot, "roadmap", "rl.md"), "# roadmap\n- [x] [P2] [done] old thing\n")


def run_main(mode):
    env = dict(os.environ, OVN_DIR=lroot, OVN_LR_FRESH_EVIDENCE=mode, OVN_LR_ORIGIN_REF="HEAD")
    r = subprocess.run([sys.executable, os.path.join(SCRIPTS, "ovn_local_research.py"), "rl", "--evidence-only"], capture_output=True, text=True, env=env, timeout=60)
    return r.stdout, r.stderr


out_s, err_s = run_main("shadow")
check("L10 shadow: evidence unchanged (no fresh kinds printed) but the fresh pieces are reported on stderr + log",
      "uncovered-function" not in out_s and "fresh-evidence[shadow]" in err_s and os.path.isfile(os.path.join(lroot, "state", "local_research_fresh.log")))
out_o, err_o = run_main("on")
check("L11 on: the fresh evidence is part of the evidence", "[uncovered-function] app/svc.py:5" in out_o and "[lint-finding]" in out_o)
out_f, err_f = run_main("off")
check("L12 off: nothing fresh, nothing reported", "uncovered-function" not in out_f and "fresh-evidence" not in err_f)

# =========================================================================== 4. small-decomposition marker never changes a feature slug
MARKED = "Fix the thing - tiny [small-decomposition n=2]"
fg = load("ovn_feature_groups")
led = load("ovn_supply_ledger")
check("S1 all four slug functions ignore the planner's small-decomposition marker",
      fg._slugify(MARKED) == fg._slugify("Fix the thing - tiny") == "fix-the-thing-tiny"
      and led._slug(MARKED) == "fix-the-thing-tiny" and lr.feat_slug(MARKED) == "fix-the-thing-tiny" and qx.feat_slug(MARKED) == "fix-the-thing-tiny")

# =========================================================================== 5. configurable mutation-scan repos
mu = load("ovn_mutation_supply")
check("M1 OVN_MUT_REPOS defaults to xlite", mu.mut_repos() == ["xlite"])
os.environ["OVN_MUT_REPOS"] = " xlite, iptv_apps ,billwatch,xlite,../evil,,gitlark "
check("M2 OVN_MUT_REPOS parses a comma list (trimmed, deduped, path-like names dropped)", mu.mut_repos() == ["xlite", "iptv_apps", "billwatch", "gitlark"])
mroot = os.path.join(BASE, "mq")
os.environ["OVN_MUT_REPOS"] = "godo,pyrepo,ghost"
mu = load("ovn_mutation_supply")
mu.OVN_DIR = mroot
for nm, godot in (("godo", True), ("pyrepo", False)):
    d = os.path.join(mroot, "repos", nm)
    os.makedirs(d)
    w(os.path.join(d, "project.godot" if godot else "main.py"), "x\n")
    subprocess.run(["git", "init", "-q"], cwd=d, check=True)
    subprocess.run(["git", "-c", "user.email=t@t", "-c", "user.name=t", "add", "-A"], cwd=d, check=True)
    subprocess.run(["git", "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-qm", "i"], cwd=d, check=True)
called = []
mu.scan = lambda rd, mx, js=False: called.append((os.path.basename(rd), mx)) or 0
import io, contextlib  # noqa: E401,E402
buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    rc = mu.scan_all(7)
out = buf.getvalue()
check("M3 scan-all scans only the Godot repo, with the per-repo budget", called == [("godo", 7)] and rc == 0)
check("M4 a non-Godot repo and a missing checkout are skipped with a log line, not a failure", "skip pyrepo: no project.godot" in out and "skip ghost: no checkout" in out)
mu.scan = lambda rd, mx, js=False: (_ for _ in ()).throw(RuntimeError("boom"))
buf = io.StringIO()
with contextlib.redirect_stdout(buf):
    rc = mu.scan_all(7)
check("M5 a crash in one repo's scan is logged and does not escape", rc == 0 and "godo failed: RuntimeError: boom" in buf.getvalue())
os.environ.pop("OVN_MUT_REPOS", None)

print("\n  %d passed, %d failed" % (P, F))
if F:
    sys.exit(1)

# =========================================================================== mutants (each must make this suite fail)
if "--no-mutants" in sys.argv or os.environ.get("K5_SCRIPTS"):
    sys.exit(0)
MUT = [
    ("forecast: runway floor off by one (<= instead of <)", "ovn_supply_forecast.py", 'if rec["runway_h"] < runway_floor:', 'if rec["runway_h"] <= runway_floor:'),
    ("forecast: items per feature ignored (ready counts 1)", "ovn_supply_forecast.py", "decomposable = ready * items_per_feature", "decomposable = ready * 1"),
    ("forecast: shadow also writes requests", "ovn_supply_forecast.py", 'if fc["mode"] != "on":\n        return', 'if fc["mode"] == "off":\n        return'),
    ("forecast: reverts count as burn", "ovn_supply_forecast.py", 'r.get("class") not in led.PUSHED', 'r.get("class") not in led.PUSHED + ("reverted",)'),
    ("forecast: stale request kept", "ovn_supply_forecast.py", "elif os.path.isfile(p):\n                os.unlink(p)", "elif False:\n                pass"),
    ("explorer: yield streak threshold ignored", "ovn_qwen_explore.py", "if st[lens] >= YIELD_N and", "if st[lens] >= 1 and"),
    ("explorer: always-eligible lenses can be parked", "ovn_qwen_explore.py", 'YIELD_ALWAYS = ("feature-ideation", "bug-hunt", "completeness")', "YIELD_ALWAYS = ()"),
    ("explorer: 7-day accepts do not protect a lens", "ovn_qwen_explore.py", "and lens_accepts_in_window(repo, lens, now) == 0:", ":"),
    ("explorer: dialect-only passes count as empty", "ovn_qwen_explore.py", "or dialect_only or (calls", "or (calls"),
    ("explorer: pick_lens ignores skip", "ovn_qwen_explore.py", "names = [n for n in names if n not in skip] or names", "pass"),
    ("explorer: parked lens stays parked tomorrow", "ovn_qwen_explore.py", "if d == today and n not in YIELD_ALWAYS", "if n not in YIELD_ALWAYS"),
    ("local research: origin TODO scan returns nothing", "ovn_local_research.py", "FRESH_COLLECTORS = [fresh_uncovered_functions, fresh_lint_findings, fresh_origin_todos]", "FRESH_COLLECTORS = [fresh_uncovered_functions, fresh_lint_findings]"),
    ("local research: fresh shadow mode appends evidence", "ovn_local_research.py", 'if fresh_mode() == "on":\n                evidence', 'if fresh_mode() != "off":\n                evidence'),
    ("local research: private functions reported", "ovn_local_research.py", "def ([a-z][A-Za-z0-9_]*)\\(\")", "def ([A-Za-z_][A-Za-z0-9_]*)\\(\")"),
    ("local research: fresh skip() ignored", "ovn_local_research.py", "and not (skip and skip(e))]", "]"),
    ("slug: lr feat_slug keeps the marker", "ovn_local_research.py", 'feature_text = re.sub(r"\\s*\\[small-decomposition[^\\]]*\\]", "", feature_text)', "pass"),
    ("slug: ledger _slug keeps the marker", "ovn_supply_ledger.py", 'text = re.sub(r"\\s*\\[small-decomposition[^\\]]*\\]", "", text)', "pass"),
    ("mutation: scan-all scans non-Godot repos", "ovn_mutation_supply.py", "if not is_godot_repo(rd):", "if False:"),
    ("mutation: scan-all lets one crash escape", "ovn_mutation_supply.py", "except Exception as e:     # one repo's failure", "except KeyboardInterrupt as e:     # one repo's failure"),
    ("mutation: OVN_MUT_REPOS not deduped", "ovn_mutation_supply.py", "if n and n not in out and", "if n and"),
]
tmpd = tempfile.mkdtemp(prefix="k5-mut-")
bad = 0
try:
    for fn in os.listdir(SCRIPTS):
        if fn.endswith(".py"):
            shutil.copy(os.path.join(SCRIPTS, fn), tmpd)
    for name, f, old, new in MUT:
        src = open(os.path.join(SCRIPTS, f)).read()
        if old not in src:
            print("  MUTANT SETUP FAIL (pattern not found): " + name)
            bad += 1
            continue
        open(os.path.join(tmpd, f), "w").write(src.replace(old, new, 1))
        r = subprocess.run([sys.executable, os.path.abspath(__file__), "--no-mutants"], env=dict(os.environ, K5_SCRIPTS=tmpd), capture_output=True, text=True, timeout=300)
        killed = r.returncode != 0
        print("  %s MUTANT %s" % ("killed  " if killed else "SURVIVED", name))
        bad += 0 if killed else 1
        shutil.copy(os.path.join(SCRIPTS, f), tmpd)
finally:
    shutil.rmtree(tmpd, ignore_errors=True)
print("  mutants: %d of %d survived" % (bad, len(MUT)))
sys.exit(1 if bad else 0)
