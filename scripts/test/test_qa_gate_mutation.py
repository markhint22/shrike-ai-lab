#!/usr/bin/env python3
"""Tests for qa/gate_mutation.py (S7: per-range mutation ADVISORY gate, registry key `mutation`) and its wiring.

Hermetic: throwaway git repos under a private temp dir, OVN_DIR / QA_STATE_DIR / OVN_REPOS_DIR all inside it, nothing under the real state dir.
Real mutmut runs need mutmut + pytest in $QA_VENV (default ~/qa-venv); without them those controls print SKIP (loudly) and the rest still runs.
Failure injection (M1..M6): the gate is copied with ONE line changed and the corresponding assertion must FAIL against the copy."""
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
GATE = os.path.join(QA, "gate_mutation.py")
P = F = S = 0


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name + (("  -> " + str(extra)[:400]) if extra else ""))


def skip(name, why):
    global S
    S += 1
    print("  SKIP %s (%s)" % (name, why))


T = tempfile.mkdtemp(prefix="qa-gatemut-test-")
if not T or os.path.realpath(T) in ("/", os.path.realpath(os.path.expanduser("~"))):
    sys.exit("unsafe temp dir")
OVN = os.path.join(T, "ovn")
STATE = os.path.join(OVN, "state")
REPOS = os.path.join(T, "repos")
TMP = os.path.join(T, "tmp")
for d in (STATE, REPOS, TMP):
    os.makedirs(d)
def _find_qa_venv():
    """QA_VENV if set, else the first of ~/qa-venv and the box's dedicated tool venv (ops/qa_tools_install.sh) that holds mutmut + pytest."""
    if os.environ.get("QA_VENV"):
        return os.environ["QA_VENV"]
    for c in (os.path.expanduser("~/qa-venv"), os.path.expanduser("~/overnight-queue/qa-tools/.venv")):
        if os.path.exists(os.path.join(c, "bin", "mutmut")) and os.path.exists(os.path.join(c, "bin", "pytest")):
            return c
    return os.path.expanduser("~/qa-venv")


QA_VENV = _find_qa_venv()
HAVE = os.path.exists(os.path.join(QA_VENV, "bin", "mutmut")) and os.path.exists(os.path.join(QA_VENV, "bin", "pytest"))
GENV = dict(os.environ, GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t", GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@t")
VALID = ("PASS", "FLAG", "UNVERIFIED", "NA")
SEEN = []   # every verdict any run below produced: the gate must never emit FAIL


class Repo:
    def __init__(self, name):
        self.name = name
        self.path = os.path.join(REPOS, name)
        os.makedirs(self.path)
        self.g("init", "-q", "-b", "develop")

    def g(self, *a, date=None):
        env = dict(GENV)
        if date:
            env["GIT_AUTHOR_DATE"] = env["GIT_COMMITTER_DATE"] = date
        return subprocess.run(["git", "-C", self.path] + list(a), capture_output=True, text=True, env=env)

    def write(self, rel, body):
        p = os.path.join(self.path, rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "w") as f:
            f.write(body)

    def commit(self, msg, date=None):
        self.g("add", ".", date=date)   # throwaway fixture repo only
        self.g("commit", "-q", "-m", msg, date=date)
        return self.g("rev-parse", "HEAD").stdout.strip()


def seed(repo, date=None):
    repo.write("svc/app/__init__.py", "")
    repo.write("svc/app/calc.py", "def clamp(x, lo, hi):\n    if x < lo:\n        return lo\n    if x > hi:\n        return hi\n    return x\n\n\ndef twice(x):\n    return x * 2\n")
    repo.write("svc/tests/test_calc.py", "from app.calc import clamp, twice\n\n\ndef test_clamp():\n    assert clamp(5, 0, 10) == 5\n    assert clamp(-1, 0, 10) == 0\n"
               "    assert clamp(11, 0, 10) == 10\n    assert clamp(0, 0, 10) == 0\n    assert clamp(10, 0, 10) == 10\n\n\ndef test_twice():\n    assert twice(3) == 6\n    assert twice(0) == 0\n")
    repo.write("svc/pytest.ini", "[pytest]\ntestpaths = tests\n")
    repo.write("svc/app/regdeco.py", "registry = {}\n\n\ndef route(name):\n    def deco(f):\n        registry[name] = f\n        return f\n    return deco\n")
    repo.write("README.md", "# demo\n")
    return repo.commit("base", date=date)


def env_for(extra=None, qa_venv=None):
    e = {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "HOME": T, "NTFY_SERVER": "http://127.0.0.1:9", "OVN_DIR": OVN, "OVN_REPOS_DIR": REPOS,
         "TMPDIR": TMP, "QA_VENV": qa_venv if qa_venv is not None else QA_VENV, "QA_STATE_DIR": STATE}
    e.update(extra or {})
    return e


def run_gate(script, args, extra_env=None, qa_venv=None, timeout=400):
    p = subprocess.run(["python3", script] + list(args), cwd=OQ, capture_output=True, text=True, env=env_for(extra_env, qa_venv), timeout=timeout)
    lines = [l for l in p.stdout.splitlines() if l.strip()]
    try:
        r = json.loads(lines[-1]) if lines else {}
    except ValueError:
        r = {"verdict": "NOT-JSON", "summary": (lines[-1] if lines else p.stderr)[:200]}
    if r.get("verdict"):
        SEEN.append(r["verdict"])
    return p.returncode, r


def check(repo, base, head, extra=(), extra_env=None, qa_venv=None, script=GATE):
    return run_gate(script, ["check", "--repo", repo, "--base", base, "--head", head, "--no-record"] + list(extra), extra_env, qa_venv)


def load_mod(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec)
    sys.path.insert(0, os.path.dirname(path))
    spec.loader.exec_module(m)
    return m


os.environ.update({"OVN_DIR": OVN, "QA_STATE_DIR": STATE, "OVN_REPOS_DIR": REPOS})
for k in ("OVN_QA_MUTATION", "OVN_MUT_UNWRAP", "OVN_MUT_SELECT_REPOS", "OVN_MUT_CAP_S", "OVN_MUT_LOAD_MAX", "OVN_MUT_RUN_LOCK", "OVN_MUT_LOCK_FILE",
          "OVN_MUT_DAILY_BUDGET_S", "OVN_MUT_MARGIN_S", "OVN_MUT_MAX_RANGE_COMMITS", "OVN_MUT_REF"):
    os.environ.pop(k, None)
os.environ["QA_VENV"] = QA_VENV
sys.path.insert(0, QA)
import gate_mutation as gm  # noqa: E402
import qa_common as qc  # noqa: E402


def mutant_copy(tag, rel, old, new):
    """Copy qa/ to a scratch dir with ONE substitution; returns the copy's dir (asserts the line to break exists exactly once)."""
    dst = os.path.join(T, "mut_" + tag)
    shutil.copytree(QA, dst, ignore=shutil.ignore_patterns("__pycache__", "acceptance_pilot", "device_lane"))
    p = os.path.join(dst, rel)
    s = open(p).read()
    assert s.count(old) == 1, "mutant %s: expected exactly one occurrence of %r in %s, found %d" % (tag, old, rel, s.count(old))
    open(p, "w").write(s.replace(old, new))
    return dst


print("== gate_mutation (QA_VENV=%s, mutmut available: %s)" % (QA_VENV, HAVE))

# ------------------------------------------------------------------------------------------------ registry / wiring invariants
src = open(GATE).read()
ok("registry key is `mutation` and the file is NOT a per-merge gate", gm.GATE == "mutation" and "mutation" in gm.DAILY_ONLY)
rs = open(os.path.join(QA, "qa_run_shadow.sh")).read()
ok("qa_run_shadow.sh skips daily-only `mutation` (never per merge)", 'case "$name" in mutation) continue ;; esac' in rs)
import qa_enforce_run as ER  # noqa: E402
os.environ["OVN_QA_MUTATION"] = "enforce"
ok("enforce runner never lists `mutation` even when its mode says enforce", "mutation" not in ER.enforce_gates() and "mutation" not in ER.all_gates())
del os.environ["OVN_QA_MUTATION"]
ok("gate never takes run.lock (observes it read-only)", "flock" not in src.replace("fuser", "") and "LOCK_EX" not in src)
ok("default mode is shadow", qc.mode("mutation") == "shadow")
ra = open(os.path.join(HERE, "run_all.sh")).read()
ok("both suites are registered in run_all.sh", "test_qa_gate_mutation.sh" in ra and "test_qa_gate_precision.sh" in ra)

# ------------------------------------------------------------------------------------------------ limits / switches (pure)
a, v = gm.build_argv(["--repo", "billwatch", "--cap", "99999", "--max-children", "64", "--survivors", "500", "--unwrap-decorators", "--select-tests"], "billwatch")
ok("limits are clamped: cap<=600, max-children<=4, survivors<=10", v == {"--cap": 600, "--max-children": 4, "--survivors": 10}, str(v))
ok("--unwrap-decorators from the caller is stripped without OVN_MUT_UNWRAP=1", "--unwrap-decorators" not in a)
os.environ["OVN_MUT_UNWRAP"] = "1"
a2, _ = gm.build_argv(["--repo", "billwatch"], "billwatch")
ok("OVN_MUT_UNWRAP=1 enables --unwrap-decorators", "--unwrap-decorators" in a2)
os.environ["OVN_MUT_UNWRAP"] = "0"
a2b, _ = gm.build_argv(["--repo", "billwatch"], "billwatch")
ok("OVN_MUT_UNWRAP=0 does not", "--unwrap-decorators" not in a2b)
del os.environ["OVN_MUT_UNWRAP"]
a3, _ = gm.build_argv(["--repo", "iptv_apps"], "iptv_apps")
ok("iptv_apps (over the cap) always runs with test selection by touched module, selection required", "--select-tests" in a3 and "--require-selection" in a3)
ok("other repos run the full suite", "--select-tests" not in gm.build_argv(["--repo", "billwatch"], "billwatch")[0])
ok("a smaller cap is honoured, a larger one is not", gm.build_argv(["--cap", "90"], "x")[1]["--cap"] == 90 and gm.build_argv(["--cap", "601"], "x")[1]["--cap"] == 600)
fin = gm.finish({"verdict": "FAIL", "summary": "x", "details": {}, "gate": "mutation", "mode": "shadow"}, ["--repo", "r", "--base", "a", "--head", "b"], {"--cap": 600}, time.time())
ok("a FAIL from the harness is mapped to FLAG: the gate never returns FAIL", fin["verdict"] == "FLAG" and fin["verdict"] in VALID, str(fin))
ok("yield block + skipped_decorated always present", set(fin["details"]["yield"]) >= {"survivors", "killed", "runtime_s"} and fin["details"]["skipped_decorated"] == [])
os.environ["OVN_QA_MUTATION"] = "enforce"
fin2 = gm.finish({"verdict": "FLAG", "summary": "x", "details": {}, "gate": "mutation", "mode": "enforce"}, [], {}, time.time())
ok("enforce is a documented no-op (row says so, verdict untouched)", "no-op" in fin2["details"].get("enforce_note", "") and fin2["verdict"] == "FLAG")
del os.environ["OVN_QA_MUTATION"]

# mutant outcome classification: timeouts / crashes are DETECTED (Mac measured: infinite-loop mutants of run_forever exit -24 and -11), never "suspicious"
ok("spike status map: -24/255 -> timeout, -11/-9 -> crashed, 0 -> survived", gm.load_spike().STATUS[-24] == "timeout" and gm.load_spike().STATUS[-11] == "crashed"
   and gm.load_spike().STATUS[-9] == "crashed" and gm.load_spike().STATUS[255] == "timeout" and gm.load_spike().STATUS[0] == "survived")
fin3 = gm.finish({"verdict": "PASS", "summary": "x", "details": {"counts": {"killed": 1, "timeout": 2, "crashed": 3}, "mutants_total": 6, "undecided_mutants": 0}, "gate": "mutation", "mode": "shadow"},
                 [], {}, time.time())
ok("yield.killed counts killed + timeout + crashed (all detected)", fin3["details"]["yield"]["killed"] == 6 and fin3["details"]["yield"]["survivors"] == 0, str(fin3["details"]["yield"]))
mdir = os.path.join(T, "metafix", "mutants", "app")
os.makedirs(mdir)
json.dump({"exit_code_by_key": {"app.x_f__mutmut_1": -11, "app.x_f__mutmut_2": 35, "app.x_f__mutmut_3": 0, "app.x_f__mutmut_4": -24, "app.x_f__mutmut_5": 1}}, open(os.path.join(mdir, "m.py.meta"), "w"))
rr = dict((k, st) for k, st, _ in gm.load_spike().read_results(os.path.join(T, "metafix"), ["app.x_f__mutmut_*"]))
ok("read_results classifies crash/suspicious/survived/timeout/killed", [rr["app.x_f__mutmut_%d" % i] for i in (1, 2, 3, 4, 5)] == ["crashed", "suspicious", "survived", "timeout", "killed"], str(rr))

# ------------------------------------------------------------------------------------------------ process group kill, no orphans
spike = gm.load_spike()
ok("spike verdicts are issued under key `mutation`", spike.GATE == "mutation")
ntag = "4%d" % (os.getpid() % 1000)
marker = "31%s7" % ntag
t0 = time.time()
rc, _tail, timed_out, _ph = spike.run_group(["sh", "-c", "sleep %s.1 & sleep %s.2 & sleep %s.3; wait" % (marker, marker, marker)], TMP, 2)
time.sleep(0.7)
left = subprocess.run(["ps", "-axo", "command"], capture_output=True, text=True).stdout.count("sleep %s." % marker)
ok("timeout kills the WHOLE process group (children included): none left", timed_out and rc == 124 and left == 0 and time.time() - t0 < 20, "left=%d rc=%s" % (left, rc))

# ------------------------------------------------------------------------------------------------ busy guard (load, run.lock)
os.environ["OVN_MUT_LOAD_MAX"] = "-1"
ok("busy: load above the threshold -> a reason", "load average" in gm.busy_reason())
os.environ["OVN_MUT_LOAD_MAX"] = "100000"
ok("not busy when load is under the threshold and no lock holder", gm.busy_reason() == "")
lockf = os.path.join(STATE, "run.lock")
holder = subprocess.Popen(["python3", "-c", "import sys,time; f=open(sys.argv[1],'a'); print('x', flush=True); time.sleep(60)", lockf], stdout=subprocess.PIPE, text=True)
holder.stdout.readline()
if shutil.which("fuser") or shutil.which("lsof"):
    ok("D1: DEFAULT policy ignores a held run.lock (the queue holds it all day): not busy", gm.busy_reason() == "", gm.busy_reason())
    os.environ["OVN_MUT_RUN_LOCK"] = "skip"
    ok("busy: OVN_MUT_RUN_LOCK=skip + run.lock held by another process -> a reason", "run.lock" in gm.busy_reason(), gm.busy_reason())
    os.environ["OVN_MUT_RUN_LOCK"] = "ignore"
    ok("OVN_MUT_RUN_LOCK=ignore relies on load only", gm.busy_reason() == "")
    del os.environ["OVN_MUT_RUN_LOCK"]
else:
    skip("run.lock holder detection", "neither fuser nor lsof on this host")
holder.kill()
holder.wait()
os.environ["OVN_MUT_RUN_LOCK"] = "skip"
ok("lock released -> not busy", gm.busy_reason() == "")
del os.environ["OVN_MUT_RUN_LOCK"]
del os.environ["OVN_MUT_LOAD_MAX"]
# fuser exit status: Linux prints holder pids and exits 1 when there are none -> a pid-looking output with a non-zero exit is NOT a holder
fakebin = os.path.join(T, "fakebin")
os.makedirs(fakebin)
with open(os.path.join(fakebin, "fuser"), "w") as f:
    f.write("#!/bin/sh\necho 1234\nexit 1\n")
os.chmod(os.path.join(fakebin, "fuser"), 0o755)
with open(lockf, "a"):
    pass
_path = os.environ["PATH"]
os.environ["PATH"] = fakebin
try:
    ok("lock_held: fuser exiting non-zero is not a holder even if it printed digits", gm.lock_held(lockf) is False)
finally:
    os.environ["PATH"] = _path
os.environ["OVN_MUT_LOAD_MAX"] = "abc"
ok("D6: a non-numeric OVN_MUT_LOAD_MAX falls back to 6 everywhere (one parser)", gm.load_max() == 6.0 and gm.busy_reason() in ("", gm.busy_reason()))
del os.environ["OVN_MUT_LOAD_MAX"]

# ------------------------------------------------------------------------------------------------ controls that need no mutmut
demo = Repo("mutdemo")
old = "2026-10-10T10:00:00"
base = seed(demo, old)
demo.write("svc/app/rules.py", "def tier(n):\n    if n >= 100:\n        return 'gold'\n    if n >= 10:\n        return 'silver'\n    return 'basic'\n")
demo.write("svc/tests/test_rules.py", "from app.rules import tier\n\n\ndef test_tier_returns_str():\n    assert isinstance(tier(5), str)\n")
weak = demo.commit("weak")
demo.write("svc/app/money.py", "def cents(d):\n    return int(round(d * 100))\n")
demo.write("svc/tests/test_money.py", "from app.money import cents\n\n\ndef test_cents():\n    assert cents(1.0) == 100\n    assert cents(0.0) == 0\n    assert cents(2.5) == 250\n    assert cents(0.01) == 1\n")
strong = demo.commit("strong")

rc, r = check("mutdemo", base, weak, extra_env={"OVN_QA_MUTATION": "off"})
ok("mode off -> NA, no run", rc == 0 and r.get("verdict") == "NA" and "off" in r.get("summary", ""), str(r))
rc, r = check("mutdemo", base, weak, qa_venv="/nonexistent-qa-venv")
ok("tool missing -> UNVERIFIED (never PASS), exit 0", rc == 0 and r.get("verdict") == "UNVERIFIED" and r.get("gate") == "mutation", str(r))
ok("tool missing: the row still carries yield + skipped_decorated + limits", "yield" in r.get("details", {}) and r["details"].get("limits", {}).get("cap_s") == 600, str(r)[:300])
rc, r = check("mutdemo", base, weak, qa_venv="/nonexistent-qa-venv", extra_env={"OVN_QA_MUTATION": "enforce"})
ok("enforce + tool missing: still UNVERIFIED, exit 0, flagged as no-op", rc == 0 and r.get("verdict") == "UNVERIFIED" and "enforce_note" in r.get("details", {}), str(r))
rc, r = check("no-such-repo", "HEAD^", "HEAD")
ok("unknown repo -> UNVERIFIED, exit 0", rc == 0 and r.get("verdict") == "UNVERIFIED", str(r))
rc, r = run_gate(GATE, ["check", "--repo", "mutdemo", "--no-record"])
ok("missing --base/--head -> UNVERIFIED usage, exit 0", rc == 0 and r.get("verdict") == "UNVERIFIED", str(r))
demo.write("svc/tests/test_calc.py", open(os.path.join(demo.path, "svc/tests/test_calc.py")).read() + "\n\ndef test_more():\n    assert twice(1) == 2\n")
testonly = demo.commit("testonly")
rc, r = check("mutdemo", strong, testonly)
ok("test-only range -> NA", r.get("verdict") == "NA", str(r))

# daily: range resolution
base_r, head_r, note = gm.resolve_range("mutdemo", 24, ref="develop", fetch=False)
ok("daily range: base = last commit older than the window, head = develop tip", base_r == base and head_r == testonly, "%s %s %s" % (base_r, head_r, note))
# range recording: ONE row per check, in qa_shadow/mutation.jsonl, key mutation
mj = os.path.join(STATE, "qa_shadow", "mutation.jsonl")
rc, r = run_gate(GATE, ["check", "--repo", "mutdemo", "--base", strong, "--head", testonly])
rows = [json.loads(l) for l in open(mj)] if os.path.exists(mj) else []
ok("exactly one row recorded for the range, gate=mutation, range in details", len(rows) == 1 and rows[0]["gate"] == "mutation" and rows[0]["details"]["range"]["base"] == strong
   and rows[0]["details"]["range"]["head"] == testonly, str(rows)[:300])
ok("a manual check row is source=manual (NA is a measured verdict, but manual rows never advance the daily baseline)",
   rows[0]["details"]["range"]["source"] == "manual" and rows[0]["details"]["range"]["measured"] is True, str(rows[0]["details"]["range"]))

os.environ["OVN_MUT_REF"] = "develop"


def wrow(repo, head, verdict, measured=True, source="daily", legacy=False):
    rg = {"base": "x", "head": head}
    if not legacy:
        rg.update({"source": source, "measured": measured})
    os.makedirs(os.path.dirname(mj), exist_ok=True)
    with open(mj, "a") as f:
        f.write(json.dumps({"ts": "2026-10-17T08:50:00Z", "gate": "mutation", "repo": repo, "ref": head, "verdict": verdict, "ms": 1, "details": {"range": rg}}) + "\n")


b2, h2, n2 = gm.resolve_range("mutdemo", 24, fetch=False)
ok("D3: after a MANUAL row the daily range still starts at the window base (manual rows do not advance the baseline)", b2 == base and h2 == testonly, "%s %s %s" % (b2, h2, n2))
wrow("mutdemo", strong, "UNVERIFIED", measured=False)
ok("D3: an UNVERIFIED daily row (measured=false) does not advance the baseline", gm.last_recorded_head("mutdemo") == "" and gm.resolve_range("mutdemo", 24, fetch=False)[0] == base)
wrow("mutdemo", strong, "PASS", measured=True, source="manual")
ok("D3: a manual PASS row does not advance it either", gm.last_recorded_head("mutdemo") == "")
wrow("mutdemo", strong, "FLAG", measured=False)
ok("D3: measured=false wins over a FLAG verdict (e.g. --paths partial)", gm.last_recorded_head("mutdemo") == "")
wrow("mutdemo", strong, "UNVERIFIED", legacy=True)
ok("D3: legacy row (no range.measured) is judged by its verdict: UNVERIFIED does not count", gm.last_recorded_head("mutdemo") == "")
wrow("mutdemo", testonly, "PASS", measured=True)
b2, h2, n2 = gm.resolve_range("mutdemo", 24, fetch=False)
ok("daily range: after a MEASURED daily row the next range starts at the recorded head -> nothing new", b2 is None and h2 == testonly and "no new" in n2, "%s %s %s" % (b2, h2, n2))
demo.write("svc/app/more.py", "def more(x):\n    return x + 1\n")
more = demo.commit("more")
b3, h3, n3 = gm.resolve_range("mutdemo", 24, fetch=False)
ok("daily range: a new commit after the recorded head -> base is the recorded head (not per commit, not a re-run)", b3 == testonly and h3 == more, "%s %s" % (b3, h3))
os.environ["OVN_MUT_MAX_RANGE_COMMITS"] = "1"
demo.write("svc/app/more2.py", "def more2(x):\n    return x + 2\n")
more2 = demo.commit("more2")
b3b, h3b, n3b = gm.resolve_range("mutdemo", 24, fetch=False)
ok("a measured base more than OVN_MUT_MAX_RANGE_COMMITS behind falls back to the time window (range cannot grow forever)", b3b == base and h3b == more2, "%s %s" % (b3b, h3b))
del os.environ["OVN_MUT_MAX_RANGE_COMMITS"]
more = more2          # the real-mutmut section below builds on develop's tip
# a recorded head that is NOT an ancestor of develop (force-moved branch) must not become the base
demo.g("checkout", "-q", "-b", "side", base)
demo.write("svc/app/side.py", "def side():\n    return 1\n")
side = demo.commit("side")
demo.g("checkout", "-q", "develop")
wrow("mutdemo", side, "PASS", measured=True)
b4, h4, n4 = gm.resolve_range("mutdemo", 24, fetch=False)
ok("a measured head that is not an ancestor of the current head is not used as a base", b4 == base and b4 != side and h4 == more2, "%s %s %s" % (b4, h4, n4))
os.remove(mj)
# the reviewer's repro: a manual `check --paths` marks nothing as done
rc, r = run_gate(GATE, ["check", "--repo", "mutdemo", "--base", base, "--head", more2, "--paths", "svc/app/rules.py"], qa_venv="/nonexistent-qa-venv")
rg = json.loads(open(mj).read().splitlines()[-1])["details"]["range"]
ok("D3: check --paths is recorded as partial and unmeasured", rg["measured"] is False and rg.get("partial") and rg["source"] == "manual", str(rg))
ok("D3: ...so resolve_range still wants the whole range", gm.resolve_range("mutdemo", 24, fetch=False)[0] == base)
fin_m = {}
for vd in ("PASS", "FLAG", "NA", "UNVERIFIED"):
    fin_m[vd] = gm.finish({"verdict": vd, "summary": "", "details": {}, "gate": "mutation", "mode": "shadow"}, ["--repo", "r", "--base", "a", "--head", "b"], {}, time.time())["details"]["range"]["measured"]
ok("finish(): measured = PASS|FLAG|NA only", fin_m == {"PASS": True, "FLAG": True, "NA": True, "UNVERIFIED": False}, str(fin_m))
ok("finish(): survivors_shown capped at 10", len(gm.finish({"verdict": "FLAG", "summary": "", "details": {"survivors_shown": [{"m": i} for i in range(15)]}, "gate": "mutation", "mode": "shadow"},
                                                           [], {}, time.time())["details"]["survivors_shown"]) == 10)
os.remove(mj)
del os.environ["OVN_MUT_REF"]

# the daily CLI + shell wiring under guards (no mutmut needed: every case is skipped before any run)
rc, p_out = 0, subprocess.run(["python3", GATE, "daily", "--repos", "mutdemo", "--no-record"], cwd=OQ, capture_output=True, text=True,
                              env=env_for({"OVN_MUT_LOAD_MAX": "-1", "OVN_MUT_REF": "develop"}))
ok("daily under load: one {skipped} line, exit 0, nothing recorded", p_out.returncode == 0 and '"skipped"' in p_out.stdout and "load average" in p_out.stdout, p_out.stdout)
p_out = subprocess.run(["python3", GATE, "daily", "--repos", "mutdemo"], cwd=OQ, capture_output=True, text=True, env=env_for({"OVN_QA_MUTATION": "off"}))
ok("daily with mode off: skipped", '"skipped"' in p_out.stdout and "off" in p_out.stdout, p_out.stdout)


def shell(args, extra):
    log = os.path.join(OVN, "logs", "qa_daily_shadow.log")
    if os.path.exists(log):
        os.remove(log)
    e = env_for(dict({"QA_DAILY_REPOS": "", "QA_DAILY_STAGING_REPOS": "", "QA_DAILY_SMOKE_REPOS": "", "OVN_MUT_REF": "develop"}, **extra))
    e["PATH"] = "/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin"
    p = subprocess.run(["bash", os.path.join(QA, "qa_daily_shadow.sh")] + args, cwd=OQ, capture_output=True, text=True, env=e, timeout=300)
    return p.returncode, (open(log).read() if os.path.exists(log) else "")


os.makedirs(os.path.join(OVN, "logs"), exist_ok=True)
rc, log = shell(["--mutation-only"], {"OVN_MUT_LOAD_MAX": "-1"})
ok("qa_daily_shadow.sh --mutation-only: load above threshold -> logged SKIPPED, exit 0", rc == 0 and "mutation: SKIPPED" in log and "load average" in log, log)
holder = subprocess.Popen(["python3", "-c", "import sys,time; f=open(sys.argv[1],'a'); print('x', flush=True); time.sleep(60)", lockf], stdout=subprocess.PIPE, text=True)
holder.stdout.readline()
if shutil.which("fuser") or shutil.which("lsof"):
    rc, log = shell(["--mutation-only"], {"OVN_MUT_LOAD_MAX": "100000", "OVN_MUT_RUN_LOCK": "skip"})
    ok("qa_daily_shadow.sh: OVN_MUT_RUN_LOCK=skip + run.lock held -> logged SKIPPED (run.lock), exit 0", rc == 0 and "mutation: SKIPPED" in log and "run.lock" in log, log)
    rc, log = shell(["--mutation-only"], {"OVN_MUT_LOAD_MAX": "100000", "QA_VENV": "/nonexistent-qa-venv"})
    ok("D1: qa_daily_shadow.sh with the DEFAULT policy and run.lock held never skips for run.lock", rc == 0 and "run.lock" not in log, log)
holder.kill()
holder.wait()
rc, log = shell(["--staging-only"], {"OVN_MUT_LOAD_MAX": "-1"})
ok("--staging-only (hourly) never touches the mutation pass", rc == 0 and "mutation" not in log, log)
rc, log = shell(["--mutation-only"], {"OVN_QA_MUTATION": "off"})
ok("OVN_QA_MUTATION=off through the shell wrapper: SKIPPED (mode off)", rc == 0 and "SKIPPED" in log and "off" in log, log)
dsh = open(os.path.join(QA, "qa_daily_shadow.sh")).read()
ok("D4: the shell wrapper gives the gate a SIGTERM grace period before the SIGKILL wall", "QA_TIMEOUT_TERM_GRACE_S" in dsh and "qa_timeout.py" in dsh)
ok("mutation block comes AFTER the smoke gates and before `done`", dsh.index("gate_mutation.py") > dsh.index("staging_smoke.py") and dsh.index("gate_mutation.py") < dsh.rindex('log "done"'))


# ------------------------------------------------------------------------------------------------ daily() scenarios (in-process, fake check + fake clock)
import contextlib  # noqa: E402
import io  # noqa: E402
import types  # noqa: E402


def daily_scenario(m, repos, env=None, calls_clock=0, load_seq=None, argv_extra=()):
    """Run m.daily() in-process with the tooling guard open and m.check replaced by a recorder; returns (calls, stdout, mutation.jsonl rows, skip rows)."""
    for f in (mj, os.path.join(STATE, "qa_gate_skips.jsonl")):
        if os.path.exists(f):
            os.remove(f)
    saved = {k: os.environ.get(k) for k in (env or {})}
    os.environ.update(env or {})
    os.environ["OVN_MUT_REF"] = "develop"
    os.environ["OVN_MUT_LOAD_MAX"] = os.environ.get("OVN_MUT_LOAD_MAX", "100000")
    clock = [1000.0]
    calls = []
    real_time, real_check, real_tool, real_load = m.time, m.check, m.tooling_reason, m.load_1m
    fake_time = types.SimpleNamespace(time=lambda: clock[0], strftime=time.strftime, gmtime=time.gmtime, sleep=time.sleep)

    def fake_check(argv):
        calls.append(m.opt(argv, "--repo"))
        clock[0] += calls_clock
        return qc.verdict("PASS", "mutation", m.opt(argv, "--repo"), m.opt(argv, "--head"), "fake")

    m.time, m.check, m.tooling_reason = fake_time, fake_check, (lambda: "")
    if load_seq is not None:
        seq = list(load_seq)
        m.load_1m = lambda: seq.pop(0) if len(seq) > 1 else seq[0]
    buf = io.StringIO()
    try:
        with contextlib.redirect_stdout(buf):
            m.daily(["--repos", repos, "--hours", "24"] + list(argv_extra))
    finally:
        m.time, m.check, m.tooling_reason, m.load_1m = real_time, real_check, real_tool, real_load
        for k, v in saved.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v
        os.environ.pop("OVN_MUT_REF", None)
        os.environ.pop("OVN_MUT_LOAD_MAX", None)
    rows_ = [json.loads(l) for l in open(mj)] if os.path.exists(mj) else []
    sk = os.path.join(STATE, "qa_gate_skips.jsonl")
    skips_ = [json.loads(l) for l in open(sk)] if os.path.exists(sk) else []
    return calls, buf.getvalue(), rows_, skips_


calls, out, rows_, skips_ = daily_scenario(gm, "mutdemo mutdemo mutdemo", calls_clock=700)
ok("D4: budget guard: a repo is started only if the remaining budget >= cap + margin (3rd of 3 skipped after two 700 s runs)", calls == ["mutdemo", "mutdemo"], "%s %s" % (calls, out))
ok("D4: the budget skip names the shortfall and is recorded in qa_gate_skips.jsonl", len(skips_) == 1 and "daily budget" in skips_[0]["reason"] and skips_[0]["repo"] == "mutdemo", str(skips_))
calls, out, rows_, skips_ = daily_scenario(gm, "mutdemo mutdemo", env={"OVN_MUT_DAILY_BUDGET_S": "60", "OVN_MUT_MARGIN_S": "0", "OVN_MUT_CAP_S": "30"}, calls_clock=40)
ok("D4: with a 60 s budget, 30 s cap, 0 margin: first repo runs (40 s), the second (20 s left < 30) does not", calls == ["mutdemo"], "%s %s" % (calls, out))
calls, out, rows_, skips_ = daily_scenario(gm, "mutdemo ../evil bad;name", calls_clock=1)
ok("D6: repo names are validated: only [A-Za-z0-9._-]+ reach resolve_range/check", calls == ["mutdemo"] and "evil" not in out and "bad" not in out, "%s %s" % (calls, out))
calls, out, rows_, skips_ = daily_scenario(gm, "mutdemo", env={"OVN_MUT_LOAD_MAX": "abc"}, calls_clock=1)
ok("D6: OVN_MUT_LOAD_MAX=abc does not crash daily(): the repo is still processed", calls == ["mutdemo"] and "crashed" not in out, "%s %s" % (calls, out))
calls, out, rows_, skips_ = daily_scenario(gm, "mutdemo", env={"OVN_MUT_LOAD_MAX": "6"}, load_seq=[0.1, 99.0])
ok("daily: load that rises after the first guard skips the repo (mid-loop re-check), recorded as a skip", calls == [] and "load rose" in out and skips_ and "load rose" in skips_[0]["reason"], "%s %s %s" % (calls, out, skips_))
calls, out, rows_, skips_ = daily_scenario(gm, "mutdemo", calls_clock=1, argv_extra=["--no-record"])
ok("daily --no-record writes no mutation row", calls == ["mutdemo"] and rows_ == [], str(rows_))
calls, out, rows_, skips_ = daily_scenario(gm, "mutdemo", calls_clock=1, env={"OVN_MUT_LOAD_MAX": "-1"}, argv_extra=["--no-record"])
ok("daily --no-record writes no skip row either", skips_ == [] and "load average" in out, str(skips_))
calls, out, rows_, skips_ = daily_scenario(gm, "mutdemo", calls_clock=1)
ok("daily without --no-record records the (fake) row", len(rows_) == 1 and rows_[0]["verdict"] == "PASS")

# D1/D2: skips are visible, tooling is checked up front, nothing is recorded as UNVERIFIED rows when the tool is missing
for f in (mj, os.path.join(STATE, "qa_gate_skips.jsonl")):
    if os.path.exists(f):
        os.remove(f)
p_out = subprocess.run(["python3", GATE, "daily", "--repos", "mutdemo"], cwd=OQ, capture_output=True, text=True,
                       env=env_for({"OVN_MUT_LOAD_MAX": "100000", "OVN_MUT_REF": "develop"}, qa_venv="/nonexistent-qa-venv"), timeout=120)
ok("D2: daily with no mutmut in the QA venv is skipped up front, naming ops/qa_tools_install.sh, exit 0", p_out.returncode == 0 and "qa_tools_install.sh" in p_out.stdout and '"skipped"' in p_out.stdout, p_out.stdout + p_out.stderr)
ok("D2: ...and writes NO mutation row (no worktree, no doomed UNVERIFIED run)", not os.path.exists(mj))
sk = [json.loads(l) for l in open(os.path.join(STATE, "qa_gate_skips.jsonl"))] if os.path.exists(os.path.join(STATE, "qa_gate_skips.jsonl")) else []
ok("D1/D2: ...but the skip is recorded in state/qa_gate_skips.jsonl (gate, ts, reason)", len(sk) == 1 and sk[0]["gate"] == "mutation" and "mutmut" in sk[0]["reason"] and sk[0]["ts"], str(sk))
st = subprocess.run(["python3", GATE, "status"], cwd=OQ, capture_output=True, text=True, env=env_for({"OVN_MUT_LOAD_MAX": "100000"}, qa_venv="/nonexistent-qa-venv"))
stj = json.loads(st.stdout.strip().splitlines()[-1])
ok("status: reports mutmut_installed=false, the reason, the lock policy and the recorded skip", st.returncode == 0 and stj["mutmut_installed"] is False and "qa_tools_install" in stj["tooling_reason"]
   and stj["run_lock_policy"] == "ignore" and stj["skips_total"] == 1, st.stdout)
# QA venv resolution: the dedicated tool venv under OVN_DIR is found when QA_VENV is unset (ops/qa_tools_install.sh puts mutmut there)
fv = os.path.join(OVN, "qa-tools", ".venv", "lib", "python3.12", "site-packages", "mutmut")
os.makedirs(fv)
env_nv = {k: v for k, v in env_for().items() if k != "QA_VENV"}
r_sp = subprocess.run(["python3", "-c", "import sys; sys.path.insert(0, %r); import gate_mutation as g; b, sp = g.load_spike().qa_site_packages(); print(b); print(sp); print(repr(g.tooling_reason()))" % QA],
                      capture_output=True, text=True, env=env_nv)
ok("D2: with QA_VENV unset the box's <OVN_DIR>/qa-tools/.venv (qa_tools_install.sh) is found and counts as 'mutmut installed'",
   r_sp.stdout.splitlines()[0].endswith(os.path.join("qa-tools", ".venv")) and r_sp.stdout.strip().endswith("''"), r_sp.stdout + r_sp.stderr)
shutil.rmtree(os.path.join(OVN, "qa-tools"))
if not HAVE and os.environ.get("OVN_REQUIRE_QA_VENV"):
    ok("OVN_REQUIRE_QA_VENV is set but %s has no mutmut/pytest: the real-mutmut tests below cannot be skipped" % QA_VENV, False)

# D4: SIGTERM must not leave mutmut (own session) or the worktree behind
mk2 = "55%s9" % (os.getpid() % 1000)
with open(os.path.join(T, "r1.py"), "w") as f:
    f.write("import sys\nsys.path.insert(0, %r)\nimport gate_mutation as g\nsp = g.load_spike()\nsp.run_group(['sleep', %r], '/', 300)\n" % (QA, mk2))
t0 = time.time()
pr = subprocess.run(["python3", os.path.join(QA, "qa_timeout.py"), "3", "python3", os.path.join(T, "r1.py")], capture_output=True, text=True,
                    env=env_for({"QA_TIMEOUT_TERM_GRACE_S": "10"}), timeout=60)
time.sleep(0.5)
left = subprocess.run(["ps", "-axo", "command"], capture_output=True, text=True).stdout.count("sleep " + mk2)
ok("D4: qa_timeout SIGTERM grace: run_group kills the (separate-session) child it launched; none left", pr.returncode == 124 and left == 0 and time.time() - t0 < 30, "rc=%s left=%d %s" % (pr.returncode, left, pr.stderr[-300:]))
if left:
    subprocess.run(["pkill", "-f", "sleep " + mk2])
mk3 = "56%s8" % (os.getpid() % 1000)
wtroot = os.path.join(T, "wtroot")
os.makedirs(wtroot)
with open(os.path.join(T, "r2.py"), "w") as f:
    f.write("import sys, signal\nsys.path.insert(0, %r)\nimport gate_mutation as g\nimport qa_common as qc\nsp = g.load_spike()\n"
            "signal.signal(signal.SIGTERM, g._on_sigterm)\nwith qc.worktree(%r, 'develop') as wt:\n    sp.run_group(['sleep', %r], wt, 300)\n" % (QA, demo.path, mk3))
pr = subprocess.run(["python3", os.path.join(QA, "qa_timeout.py"), "3", "python3", os.path.join(T, "r2.py")], capture_output=True, text=True,
                    env=env_for({"QA_TIMEOUT_TERM_GRACE_S": "10", "TMPDIR": wtroot}), timeout=60)
time.sleep(0.5)
left = subprocess.run(["ps", "-axo", "command"], capture_output=True, text=True).stdout.count("sleep " + mk3)
ok("D4: SIGTERM mid-run: child group killed AND the worktree is removed (no qa-wt-* dir, no registration)",
   pr.returncode == 124 and left == 0 and os.listdir(wtroot) == [] and demo.g("worktree", "list", "--porcelain").stdout.count("worktree ") == 1,
   "rc=%s left=%d dirs=%s wts=%s %s" % (pr.returncode, left, os.listdir(wtroot), demo.g("worktree", "list").stdout, pr.stderr[-300:]))
if left:
    subprocess.run(["pkill", "-f", "sleep " + mk3])
# the gate's own SIGTERM path: check() turns Terminated into an UNVERIFIED row (not measured), TERMINATED stops the daily loop
real_sc = gm.load_spike


class _Boom:
    GATE = "mutation"

    def check(self, argv):
        raise qc.Terminated("signal 15")


gm.load_spike = lambda: _Boom()
rt = gm.check(["--repo", "mutdemo", "--base", base, "--head", more])
gm.load_spike = real_sc
ok("D4: SIGTERM inside check -> UNVERIFIED 'terminated' row, range measured=false", rt["verdict"] == "UNVERIFIED" and "terminated" in rt["summary"] and rt["details"]["range"]["measured"] is False and gm.TERMINATED is True, str(rt))
gm.TERMINATED = False
# stale-worktree sweep (a SIGKILL skips every finally): qc.sweep_stale_scratch, pointed at a private temp root so nothing outside the test is touched
sweep_root = os.path.join(T, "sweeproot")
os.makedirs(sweep_root)
_old_td = tempfile.tempdir
tempfile.tempdir = sweep_root
try:
    stale = tempfile.mkdtemp(prefix="qa-wt-")
    demo.g("worktree", "add", "-q", "--detach", os.path.join(stale, "wt"), "develop")
    fresh = tempfile.mkdtemp(prefix="qa-wt-")
    demo.g("worktree", "add", "-q", "--detach", os.path.join(fresh, "wt"), "develop")
    os.utime(stale, (time.time() - 3 * 3600, time.time() - 3 * 3600))
    n_sw = qc.sweep_stale_scratch(repo_paths=[demo.path])
    ok("sweep_stale_scratch removes a 3 h old qa-wt-* dir + prunes its registration and keeps a fresh one",
       n_sw == 1 and not os.path.exists(stale) and os.path.exists(fresh) and demo.g("worktree", "list", "--porcelain").stdout.count("worktree ") == 2,
       "%s %s %s %s" % (n_sw, os.path.exists(stale), os.path.exists(fresh), demo.g("worktree", "list").stdout))
    demo.g("worktree", "remove", "--force", os.path.join(fresh, "wt"))
    shutil.rmtree(fresh, ignore_errors=True)
    demo.g("worktree", "prune")
finally:
    tempfile.tempdir = _old_td

# ------------------------------------------------------------------------------------------------ real mutmut runs
if not HAVE:
    for n in ("weak test -> survivors listed", "strong test -> all killed", "decorated handler skipped and listed", "unwrap behind OVN_MUT_UNWRAP",
              "changed-function scoping (M1)", "timeout -> UNVERIFIED, no orphans", "iptv_apps selection", "daily end to end"):
        skip(n, "mutmut/pytest not installed in QA_VENV=%s" % QA_VENV)
else:
    rc, r = check("mutdemo", base, weak)
    d = r.get("details", {})
    ok("weak test: FLAG, survivors listed with diffs, yield recorded", rc == 0 and r.get("verdict") == "FLAG" and d.get("survivors_shown") and d["yield"]["survivors"] >= 2
       and "diff" in d["survivors_shown"][0] and d["yield"]["runtime_s"] > 0, str(r)[:500])
    ok("weak test: <= 10 survivors named, only the changed function", len(d.get("survivors_shown", [])) <= 10 and d.get("functions") == ["app/rules.py:tier"], str(d.get("functions")))
    ok("weak test: limits recorded (cap 600, children 4)", d["limits"]["cap_s"] == 600 and d["limits"]["max_children"] == 4)
    rc, r = check("mutdemo", weak, strong)
    d = r.get("details", {})
    ok("strong test: PASS, zero survivors, all killed", r.get("verdict") == "PASS" and d["yield"]["survivors"] == 0 and d["yield"]["killed"] >= 3 and d["yield"]["mutants"] == d["yield"]["killed"], str(r)[:400])

    # decorated handler + undecorated function in ONE range: handler listed as skipped, the other measured
    demo.write("svc/app/reg.py", "from app.regdeco import route\n\n\n@route('double')\ndef handler(n):\n    return n * 2\n\n\ndef helper(n):\n    return n - 1\n")
    demo.write("svc/tests/test_reg.py", "import app.reg  # noqa\nfrom app.regdeco import registry\nfrom app.reg import helper\n\n\ndef test_handler():\n"
               "    assert registry['double'](3) == 6\n    assert registry['double'](0) == 0\n\n\ndef test_helper():\n    assert helper(5) == 4\n    assert helper(0) == -1\n")
    mixed = demo.commit("mixed")
    rc, r = check("mutdemo", more, mixed)
    d = r.get("details", {})
    ok("decorated handler skipped and LISTED; the undecorated helper is still measured", r.get("verdict") in ("PASS", "FLAG") and d.get("skipped_decorated") == ["app/reg.py:handler"]
       and d.get("functions") == ["app/reg.py:helper"], str(r)[:500])
    demo.write("svc/app/reg2.py", "from app.regdeco import route\n\n\n@route('triple')\ndef handler3(n):\n    return n * 3\n")
    demo.write("svc/tests/test_reg2.py", "import app.reg2  # noqa\nfrom app.regdeco import registry\n\n\ndef test_h3():\n    assert registry['triple'](2) == 6\n    assert registry['triple'](0) == 0\n")
    onlydeco = demo.commit("onlydeco")
    rc, r = check("mutdemo", mixed, onlydeco)
    ok("decorated-only range: UNVERIFIED with the reason and the skipped list (no bogus PASS)", r.get("verdict") == "UNVERIFIED" and r["details"]["skipped_decorated"] == ["app/reg2.py:handler3"]
       and "decorated" in r.get("summary", ""), str(r)[:400])
    rc, r = check("mutdemo", mixed, onlydeco, extra_env={"OVN_MUT_UNWRAP": "1"})
    ok("OVN_MUT_UNWRAP=1 makes the decorated handler measurable (experimental)", r.get("verdict") in ("PASS", "FLAG") and r["details"].get("unwrapped_decorators") == 1 and r["details"]["unwrap_decorators"] is True, str(r)[:400])
    rc, r = check("mutdemo", mixed, onlydeco, extra=["--unwrap-decorators"])
    ok("--unwrap-decorators on the command line alone is ignored", r.get("verdict") == "UNVERIFIED", str(r)[:300])

    # M1 scoping: two functions in one file, only `twice` changes -> exactly that one is mutated
    demo.write("svc/app/calc.py", open(os.path.join(demo.path, "svc/app/calc.py")).read().replace("return x * 2", "return x + x"))
    scoped = demo.commit("scoped")
    rc, r = check("mutdemo", onlydeco, scoped)
    ok("scoping: only the CHANGED function of a file is mutated", r.get("details", {}).get("functions") == ["app/calc.py:twice"], str(r.get("details", {}).get("functions")))
    mc = mutant_copy("M1", "spikes/mutation_spike.py", "hit = [f for f in funcs if any(not (b < f[3] or a > f[4]) for a, b in hs)]", "hit = list(funcs)")
    rc, rm = check("mutdemo", onlydeco, scoped, script=os.path.join(mc, "gate_mutation.py"))
    ok("M1 (mutant: scope = every function in the file) is caught by the scoping assertion", rm.get("details", {}).get("functions") != ["app/calc.py:twice"], str(rm.get("details", {}).get("functions")))

    # timeout: the process group dies and no worker survives
    demo.write("svc/tests/test_slow.py", "import time\n\n\ndef test_slow():\n    time.sleep(120)\n")
    demo.write("svc/app/slow.py", "def slow(x):\n    return x + 1\n")
    slow = demo.commit("slow")
    t0 = time.time()
    rc, r = check("mutdemo", scoped, slow, extra_env={"OVN_MUT_CAP_S": "30"})
    wall = time.time() - t0
    ok("timeout -> UNVERIFIED (reason names the cap), exit 0, within cap + slack", rc == 0 and r.get("verdict") == "UNVERIFIED" and "cap" in r.get("summary", "") and wall < 80, "%.0fs %s" % (wall, str(r)[:300]))
    time.sleep(1.5)
    live = subprocess.run(["ps", "-axo", "command"], capture_output=True, text=True).stdout
    ok("timeout: no orphaned mutmut/pytest workers from the fixture remain", ("mutants/" not in live or T not in live) and live.count(T) == 0, [l for l in live.splitlines() if T in l][:3])

    # iptv_apps: selection by touched module; nothing selectable -> UNVERIFIED with the reason, never a doomed full run
    ip = Repo("iptv_apps")
    ibase = seed(ip, old)
    ip.write("svc/app/billing.py", "def plan_for(n):\n    if n > 10:\n        return 'pro'\n    return 'free'\n")
    ip.write("svc/tests/test_other.py", "def test_unrelated():\n    assert 1 + 1 == 2\n")
    ihead = ip.commit("billing-untested")
    t0 = time.time()
    rc, r = check("iptv_apps", ibase, ihead)
    ok("iptv_apps, no test mentions the changed module -> UNVERIFIED naming test selection (and fast)", r.get("verdict") == "UNVERIFIED" and "test selection" in r.get("summary", "") and time.time() - t0 < 120, str(r)[:400])
    ip.write("svc/tests/test_billing.py", "from app.billing import plan_for\n\n\ndef test_plan():\n    assert plan_for(11) == 'pro'\n    assert plan_for(10) == 'free'\n    assert plan_for(0) == 'free'\n")
    ihead2 = ip.commit("billing-tested")
    rc, r = check("iptv_apps", ibase, ihead2)
    ok("iptv_apps with a covering test: measured with the selected test files only", r.get("verdict") in ("PASS", "FLAG") and r["details"].get("tests_selected") == ["tests/test_billing.py"], str(r)[:400])

    # daily end to end on a fresh fixture develop (no fetch): range since the day-old base, one recorded row, second pass has nothing new
    dd = Repo("dailydemo")
    dbase = seed(dd, old)
    dd.write("svc/app/rules.py", "def tier(n):\n    if n >= 100:\n        return 'gold'\n    return 'basic'\n")
    dd.write("svc/tests/test_rules.py", "from app.rules import tier\n\n\ndef test_tier_returns_str():\n    assert isinstance(tier(5), str)\n")
    dd.commit("weak")
    denv = env_for({"OVN_MUT_REF": "develop", "OVN_MUT_LOAD_MAX": "100000", "OVN_MUT_RUN_LOCK": "ignore"})
    if os.path.exists(mj):
        os.remove(mj)
    p_out = subprocess.run(["python3", GATE, "daily", "--repos", "dailydemo", "--hours", "24"], cwd=OQ, capture_output=True, text=True, env=denv, timeout=500)
    rows = [json.loads(l) for l in open(mj)] if os.path.exists(mj) else []
    ok("daily: ran the range since the base, wrote ONE advisory row (shadow mode), exit 0", p_out.returncode == 0 and len(rows) == 1 and rows[0]["mode"] == "shadow"
       and rows[0]["verdict"] == "FLAG" and rows[0]["details"]["range"]["base"] == dbase, p_out.stdout[-400:] + str(rows)[:200])
    SEEN.extend(r_["verdict"] for r_ in rows)
    p2 = subprocess.run(["python3", GATE, "daily", "--repos", "dailydemo", "--hours", "24"], cwd=OQ, capture_output=True, text=True, env=denv, timeout=60)
    ok("daily again: nothing new -> skipped, no second row", "no new commits" in p2.stdout and len([1 for _ in open(mj)]) == 1, p2.stdout)

# ------------------------------------------------------------------------------------------------ failure injection (pure-function mutants)
def mutant_fails(tag, rel, old, new, assertion):
    mc2 = mutant_copy(tag, rel, old, new)
    m = load_mod(os.path.join(mc2, "gate_mutation.py"), "gm_" + tag)
    try:
        good = assertion(m)
    except Exception:  # noqa: BLE001 - an exception in the assertion also means the mutant was caught
        good = False
    return not good


ok("M2 (mutant: wall cap not clamped to 600) is caught by the limits assertion",
   mutant_fails("M2", "gate_mutation.py", "CAP_MAX = 600 ", "CAP_MAX = 6000 ", lambda m: m.build_argv(["--cap", "99999"], "x")[1]["--cap"] == 600))
ok("M8 (mutant: crashes not counted as detected) is caught",
   mutant_fails("M8", "gate_mutation.py", '("killed", "caught_by_typecheck", "timeout", "crashed")', '("killed", "caught_by_typecheck", "timeout")',
                lambda m: m.finish({"verdict": "PASS", "summary": "", "details": {"counts": {"crashed": 3}}, "gate": "mutation", "mode": "shadow"}, [], {}, time.time())["details"]["yield"]["killed"] == 3))
ok("M3 (mutant: FAIL allowed through) is caught by the never-FAIL assertion",
   mutant_fails("M3", "gate_mutation.py", 'VALID = ("PASS", "FLAG", "UNVERIFIED", "NA")', 'VALID = ("PASS", "FLAG", "UNVERIFIED", "NA", "FAIL")',
                lambda m: m.finish({"verdict": "FAIL", "summary": "", "details": {}, "gate": "mutation", "mode": "shadow"}, [], {}, time.time())["verdict"] == "FLAG"))
ok("M4 (mutant: unwrap always on) is caught by the OVN_MUT_UNWRAP assertion",
   mutant_fails("M4", "gate_mutation.py", 'if os.environ.get("OVN_MUT_UNWRAP") == "1":\n        keep.append', 'if True:\n        keep.append',
                lambda m: "--unwrap-decorators" not in m.build_argv(["--repo", "r"], "r")[0]))
ok("M5 (mutant: iptv_apps not selection-limited) is caught",
   mutant_fails("M5", "gate_mutation.py", 'DEFAULT_SELECT_REPOS = "iptv_apps"', 'DEFAULT_SELECT_REPOS = ""', lambda m: "--select-tests" in m.build_argv(["--repo", "iptv_apps"], "iptv_apps")[0]))


def load_assert(m):
    os.environ["OVN_MUT_LOAD_MAX"] = "-1"
    try:
        return "load average" in m.busy_reason()
    finally:
        del os.environ["OVN_MUT_LOAD_MAX"]


ok("M6 (mutant: load guard disabled) is caught", mutant_fails("M6", "gate_mutation.py", "if load > lmax:", "if False:", load_assert))
ok("M7 (mutant: per-merge runner no longer skips mutation) is caught by the wiring assertion",
   'case "$name" in mutation) continue ;; esac' not in open(os.path.join(mutant_copy("M7", "qa_run_shadow.sh", 'case "$name" in mutation) continue ;; esac', ":"), "qa_run_shadow.sh")).read())


def _hold_lock_and(m):
    h = subprocess.Popen(["python3", "-c", "import sys,time; f=open(sys.argv[1],'a'); print('x', flush=True); time.sleep(60)", lockf], stdout=subprocess.PIPE, text=True)
    h.stdout.readline()
    os.environ["OVN_MUT_LOAD_MAX"] = "100000"
    try:
        return m.busy_reason() == ""
    finally:
        h.kill()
        h.wait()
        os.environ.pop("OVN_MUT_LOAD_MAX", None)


# ------------------------------------------------------------------------------------------------ failure injection round 2 (reviewer's surviving mutants + the new behaviour)
def mod_mutant(tag, rel, old, new):
    mc2 = mutant_copy(tag, rel, old, new)
    return load_mod(os.path.join(mc2, "gate_mutation.py"), "gm_" + tag)


def killed_by(tag, old, new, scenario, rel="gate_mutation.py"):
    """True when `scenario(mutant_module)` returns False / raises for the mutated copy (scenario is known good on the real module, asserted separately)."""
    m = mod_mutant(tag, rel, old, new)
    try:
        good = scenario(m)
    except Exception:  # noqa: BLE001
        good = False
    return not good


def sc_budget(m):
    return daily_scenario(m, "mutdemo mutdemo mutdemo", calls_clock=700)[0] == ["mutdemo", "mutdemo"]


def sc_lock_fuser(m):
    pth = os.environ["PATH"]
    os.environ["PATH"] = fakebin
    try:
        return m.lock_held(lockf) is False
    finally:
        os.environ["PATH"] = pth


def sc_ancestor(m):
    os.environ["OVN_MUT_REF"] = "develop"
    try:
        wrow("mutdemo", side, "PASS", measured=True)
        b_, h_, _n = m.resolve_range("mutdemo", 24, fetch=False)
        return b_ == base
    finally:
        os.environ.pop("OVN_MUT_REF", None)
        if os.path.exists(mj):
            os.remove(mj)


def sc_survivors_cap(m):
    return len(m.finish({"verdict": "FLAG", "summary": "", "details": {"survivors_shown": [{"m": i} for i in range(15)]}, "gate": "mutation", "mode": "shadow"}, [], {}, time.time())["details"]["survivors_shown"]) == 10


def sc_no_record(m):
    c_, o_, r_, s_ = daily_scenario(m, "mutdemo", calls_clock=1, argv_extra=["--no-record"])
    return r_ == []


def sc_repo_regex(m):
    c_, o_, r_, s_ = daily_scenario(m, "mutdemo ../evil", calls_clock=1)
    return "evil" not in o_


def sc_midloop(m):
    c_, o_, r_, s_ = daily_scenario(m, "mutdemo", env={"OVN_MUT_LOAD_MAX": "6"}, load_seq=[0.1, 99.0])
    return c_ == []


ok("control: the new scenarios pass on the real module", all(f(gm) for f in (sc_budget, sc_lock_fuser, sc_ancestor, sc_survivors_cap, sc_no_record, sc_repo_regex, sc_midloop)))
ok("M9 (mutant: daily budget guard removed) is caught", killed_by("M9", "if left < need:", "if False:", sc_budget))
ok("M10 (mutant: fuser exit status ignored in lock_held) is caught", killed_by("M10", "return p.returncode == 0 and re.search", "return re.search", sc_lock_fuser))
ok("M11 (mutant: merge-base --is-ancestor check skipped) is caught", killed_by("M11", 'if qc.git(rd, "merge-base", "--is-ancestor", last, head)[0] == 0:', "if True:", sc_ancestor))
ok("M12 (mutant: survivors_shown not capped at 10) is caught", killed_by("M12", 'det["survivors_shown"] = det["survivors_shown"][:SURVIVORS_MAX]', 'det["survivors_shown"] = det["survivors_shown"]', sc_survivors_cap))
ok("M13 (mutant: daily ignores --no-record) is caught", killed_by("M13", 'extra = ["--no-record"] if "--no-record" in argv else []', "extra = []", sc_no_record))
ok("M14 (mutant: repo-name filter removed) is caught", killed_by("M14", 'if not re.match(r"^[A-Za-z0-9._-]+$", r):', "if False:", sc_repo_regex))
ok("M15 (mutant: mid-loop load re-check removed) is caught", killed_by("M15", "if load_1m() > load_max():", "if False:", sc_midloop))
ok("M16 (mutant: non-numeric OVN_MUT_LOAD_MAX raises) is caught", killed_by("M16", "    except ValueError:\n        return 6.0", "    except ValueError:\n        raise",
                                                                                lambda m: (os.environ.__setitem__("OVN_MUT_LOAD_MAX", "abc"), m.load_max() == 6.0)[1]))
os.environ.pop("OVN_MUT_LOAD_MAX", None)
ok("M17 (mutant: default run.lock policy back to skip) is caught",
   killed_by("M17", 'os.environ.get("OVN_MUT_RUN_LOCK", "ignore") == "skip"', 'os.environ.get("OVN_MUT_RUN_LOCK", "skip") == "skip"',
             lambda m: (not shutil.which("fuser") and not shutil.which("lsof")) or (_hold_lock_and(m))))

mut_m = mod_mutant("M18", "gate_mutation.py", 'if rg.get("source", "daily") != "daily":', "if False:")
wrow("mutdemo", strong, "PASS", measured=True, source="manual")
ok("M18 (mutant: manual rows advance the baseline) is caught", mut_m.last_recorded_head("mutdemo") != "" and gm.last_recorded_head("mutdemo") == "")
os.remove(mj)
wrow("mutdemo", strong, "PASS", measured=False)
mut_m = mod_mutant("M19", "gate_mutation.py", 'if "measured" in rg:\n        return bool(rg["measured"])', "if False:\n        return True")
ok("M19 (mutant: range.measured ignored) is caught", mut_m.last_recorded_head("mutdemo") != "" and gm.last_recorded_head("mutdemo") == "")
os.remove(mj)
mut_m = mod_mutant("M20", "gate_mutation.py", 'MEASURED = ("PASS", "FLAG", "NA")', 'MEASURED = ("PASS", "FLAG", "NA", "UNVERIFIED")')
ok("M20 (mutant: UNVERIFIED counts as measured) is caught",
   mut_m.finish({"verdict": "UNVERIFIED", "summary": "", "details": {}, "gate": "mutation", "mode": "shadow"}, ["--repo", "r"], {}, time.time())["details"]["range"]["measured"] is True)

ok("the gate emitted only PASS/FLAG/UNVERIFIED/NA in every run above (never FAIL)", SEEN and all(v in VALID for v in SEEN), sorted(set(SEEN)))
ok("fixture clones left clean", demo.g("status", "--porcelain").stdout.strip() == "")
wl = demo.g("worktree", "list", "--porcelain").stdout.count("worktree ")
ok("no worktree left registered in the fixture clone", wl == 1, demo.g("worktree", "list").stdout)

shutil.rmtree(T, ignore_errors=True)
print("\n%d passed, %d failed, %d skipped" % (P, F, S))
sys.exit(1 if F else 0)
