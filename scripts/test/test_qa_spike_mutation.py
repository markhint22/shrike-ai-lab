#!/usr/bin/env python3
"""Tests for qa/spikes/mutation_spike.py (SPIKE W2a) - runs the REAL entry point (absolute path AND relative path from
scripts/overnight-queue) under `env -i` with a minimal PATH and NTFY_SERVER set, against a throwaway git repo.

Needs mutmut + pytest in a QA venv ($QA_VENV, default ~/qa-venv). Without them the real-run controls are SKIPPED (loudly) and
only the UNVERIFIED-on-missing-tool / NA controls run. No network is used by the tests themselves."""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
OQ = os.path.abspath(os.path.join(HERE, "..", ".."))               # scripts/overnight-queue
GATE_ABS = os.path.join(OQ, "qa", "spikes", "mutation_spike.py")
GATE_REL = os.path.join("qa", "spikes", "mutation_spike.py")
P = F = S = 0


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name + (("  -> " + extra) if extra else ""))


def skip(name, why):
    global S
    S += 1
    print("  SKIP %s (%s)" % (name, why))


T = tempfile.mkdtemp(prefix="qa-mutspike-test-")
OVN = os.path.join(T, "ovn")
REPOS = os.path.join(T, "repos")
os.makedirs(os.path.join(OVN, "state"))
os.makedirs(os.path.join(T, "tmp"))
R = os.path.join(REPOS, "mutdemo")
os.makedirs(R)
GENV = dict(os.environ, GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t", GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@t")


def g(*a):
    return subprocess.run(["git", "-C", R] + list(a), capture_output=True, text=True, env=GENV)


def write(rel, body):
    p = os.path.join(R, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    open(p, "w").write(body)


def commit(msg):
    g("add", ".")  # throwaway fixture repo only
    g("commit", "-q", "-m", msg)
    return g("rev-parse", "HEAD").stdout.strip()


QA_VENV = os.environ.get("QA_VENV") or os.path.expanduser("~/qa-venv")
HAVE = os.path.exists(os.path.join(QA_VENV, "bin", "mutmut")) and os.path.exists(os.path.join(QA_VENV, "bin", "pytest"))


def gate(script, repo, base, head, extra=(), qa_venv=None, timeout=300):
    """Run the gate exactly like cron would: env -i, minimal PATH, NTFY_SERVER set. Returns (rc, last-line JSON dict, stdout)."""
    env = ["env", "-i", "PATH=/usr/bin:/bin", "HOME=" + T, "NTFY_SERVER=http://127.0.0.1:9", "OVN_DIR=" + OVN,
           "OVN_REPOS_DIR=" + REPOS, "TMPDIR=" + os.path.join(T, "tmp"), "QA_VENV=" + (qa_venv if qa_venv is not None else QA_VENV)]
    cmd = env + ["python3", script, "check", "--repo", repo, "--base", base, "--head", head, "--no-record"] + list(extra)
    p = subprocess.run(cmd, cwd=OQ, capture_output=True, text=True, timeout=timeout)
    last = [l for l in p.stdout.splitlines() if l.strip()][-1] if p.stdout.strip() else "{}"
    try:
        return p.returncode, json.loads(last), p.stdout
    except ValueError:
        return p.returncode, {"verdict": "NOT-JSON", "summary": last[:200]}, p.stdout


def procs_under(root):
    """pids of live processes whose cwd is inside `root` (the fixture's temp dir). Other builders' processes on a shared box are
    ignored, unlike a global pgrep."""
    real = os.path.realpath(root)
    res = []
    if os.path.isdir("/proc/self"):  # Linux
        for pid in os.listdir("/proc"):
            if not pid.isnumeric():
                continue
            try:
                if os.path.realpath(os.readlink("/proc/%s/cwd" % pid)).startswith(real):
                    res.append(pid)
            except OSError:
                pass
        return res
    # macOS: ONE lsof over all processes (a per-pid call is far too slow and the process may be gone before we reach it)
    out = subprocess.run(["lsof", "-d", "cwd", "-Fpn"], capture_output=True, text=True).stdout
    pid = None
    for line in out.splitlines():
        if line.startswith("p"):
            pid = line[1:]
        elif line.startswith("n") and pid and os.path.realpath(line[1:]).startswith(real):
            res.append(pid)
    return res


# ---- fixture repo: service dir svc/ with package app/ and tests/ ---------------------------------------------------------
write("svc/app/__init__.py", "")
write("svc/app/calc.py", "def clamp(x, lo, hi):\n    if x < lo:\n        return lo\n    if x > hi:\n        return hi\n    return x\n")
write("svc/tests/test_calc.py", "from app.calc import clamp\n\n\ndef test_clamp():\n    assert clamp(5, 0, 10) == 5\n    assert clamp(-1, 0, 10) == 0\n    assert clamp(11, 0, 10) == 10\n    assert clamp(0, 0, 10) == 0\n    assert clamp(10, 0, 10) == 10\n")
write("svc/pytest.ini", "[pytest]\ntestpaths = tests\n")
write("svc/app/regdeco.py", "registry = {}\n\n\ndef route(name):\n    def deco(f):\n        registry[name] = f\n        return f\n    return deco\n")
write("README.md", "# demo\n")
g("init", "-q", "-b", "develop")
base = commit("base")

# 1. weak test: a new function whose only test asserts a loose property -> survivors (NEGATIVE control, expect FLAG)
write("svc/app/rules.py", "def tier(n):\n    if n >= 100:\n        return 'gold'\n    if n >= 10:\n        return 'silver'\n    return 'basic'\n")
write("svc/tests/test_rules.py", "from app.rules import tier\n\n\ndef test_tier_returns_str():\n    assert isinstance(tier(5), str)\n")
weak = commit("weak")

# 2. strong test: a new function with exact boundary tests -> all mutants killed (BENIGN control, expect PASS)
write("svc/app/money.py", "def cents(d):\n    return int(round(d * 100))\n")
write("svc/tests/test_money.py", "from app.money import cents\n\n\ndef test_cents():\n    assert cents(1.0) == 100\n    assert cents(0.0) == 0\n    assert cents(2.5) == 250\n    assert cents(0.01) == 1\n")
strong = commit("strong")

# 3. an untested function -> 'no tests' mutants (NEGATIVE control, expect FLAG with untested_functions)
write("svc/app/orphan.py", "def secret_gate(user):\n    if user == 'admin':\n        return True\n    return False\n")
orphan = commit("orphan")

# 4. test-only change -> NA ; 5. docs-only -> NA ; 6. module-level constant only -> NA
write("svc/tests/test_calc.py", open(os.path.join(R, "svc/tests/test_calc.py")).read() + "\n\ndef test_more():\n    assert clamp(3, 0, 10) == 3\n")
testonly = commit("testonly")
write("README.md", "# demo2\n")
docs = commit("docs")
write("svc/app/consts.py", "LIMIT = 5\n\n\ndef limit():\n    return LIMIT\n")
write("svc/tests/test_consts.py", "from app.consts import limit\n\n\ndef test_limit():\n    assert limit() == 5\n")
c1 = commit("consts")
write("svc/app/consts.py", "LIMIT = 6\n\n\ndef limit():\n    return LIMIT\n")
write("svc/tests/test_consts.py", "from app.consts import limit\n\n\ndef test_limit():\n    assert limit() == 6\n")
modlevel = commit("modlevel")  # constant changed, but `limit()` body untouched -> no changed function

# 7. a red (preexisting-failing) test elsewhere + a good function -> deselected, still measured
write("svc/tests/test_red.py", "def test_always_red():\n    assert False\n")
write("svc/app/money.py", "def cents(d):\n    return int(round(d * 100)) + 0\n")
red = commit("red")

# 8a. collection error in one test module -> that module is --ignore'd and reported, the rest still measured
write("svc/tests/test_broken.py", "import definitely_not_installed_pkg_xyz\n\n\ndef test_x():\n    pass\n")
write("svc/app/money.py", "def cents(d):\n    return int(round(d * 100)) + 1 - 1\n")
collerr = commit("collection-error")
os.remove(os.path.join(R, "svc/tests/test_broken.py"))
# 8b. a conftest that explodes at import -> nothing can run, unparseable -> UNVERIFIED
write("svc/tests/conftest.py", "raise RuntimeError('boom at conftest import')\n")
write("svc/app/money.py", "def cents(d):\n    return int(round(d * 100)) + 2 - 2\n")
broken = commit("broken-conftest")
os.remove(os.path.join(R, "svc/tests/conftest.py"))
os.remove(os.path.join(R, "svc/tests/test_red.py"))

# 8c. a decorated (route-style) function: mutmut 3.8 cannot mutate it
write("svc/app/reg.py", "from app.regdeco import route\n\n\n@route('double')\ndef handler(n):\n    return n * 2\n")
write("svc/tests/test_reg.py", "import app.reg  # noqa\nfrom app.regdeco import registry\n\n\ndef test_handler():\n    assert registry['double'](3) == 6\n    assert registry['double'](0) == 0\n")
decorated = commit("decorated")

# 10. a pure deletion inside a function (no added lines) must still count as a change to that function
write("svc/app/calc.py", "def clamp(x, lo, hi):\n    if x < lo:\n        return lo\n    return x\n")
deletion = commit("deletion")

# 9. timeout fixture: the only test sleeps far past the cap
write("svc/tests/test_slow.py", "import time\n\n\ndef test_slow():\n    time.sleep(120)\n")
write("svc/app/slow.py", "def slow(x):\n    return x + 1\n")
slow = commit("slow")

shas = {"weak": weak, "strong": strong, "orphan": orphan, "testonly": testonly, "docs": docs, "modlevel": modlevel,
        "red": red, "broken": broken, "slow": slow, "collerr": collerr, "decorated": decorated, "deletion": deletion}


def prev(sha):
    return sha + "^"


# ---- pure-function units (import the module directly) ---------------------------------------------------------------------
sys.path.insert(0, os.path.join(OQ, "qa", "spikes"))
sys.path.insert(0, os.path.join(OQ, "qa"))
import mutation_spike as ms  # noqa: E402
ok("classify: logging-call survivor is noise", ms.classify("-    logger.info('a')\n+    logger.info('XXaXX')").startswith("noise:logging"))
ok("classify: detail= message survivor is noise", ms.classify("-    detail='no'\n+    detail=None").startswith("noise:message"))
ok("classify: whitespace-only change is equivalent", ms.classify("-    )\n+        )").startswith("equivalent"))
ok("classify: a real condition flip stays a candidate", ms.classify("-    if x > 0:\n+    if x >= 0:") == "candidate")
fs = ms.functions_in("import x\n\n@dec\ndef a():\n    pass\n\nclass C:\n    def m(self):\n        pass\n    @staticmethod\n    def s():\n        pass\n")
ok("functions_in: decorated function flagged as skipped by mutmut, staticmethod not", [(f[0], f[5]) for f in fs] == [("a", True), ("C.m", False), ("C.s", False)], str(fs))
ok("mangled_globs: method vs function naming", ms.mangled_globs("app.m", fs[1]).endswith("\u01c1C\u01c1m__mutmut_*") and ms.mangled_globs("app.m", fs[0]).endswith(".x_a__mutmut_*"))
ok("redact: credential-looking literals never reach the JSON line", "ghp_" not in ms.redact("t = 'ghp_" + "a" * 36 + "'") and "[REDACTED]" in ms.redact("k = 'sk-" + "b" * 24 + "'"))
tmpf = os.path.join(T, "unwrap_sample.py")
open(tmpf, "w").write("@r.get('/x')\n@other\nasync def h(a):\n    return a\n\n\ndef k():\n    return 1\n")
ok("unwrap_decorators rewrites @dec def f into def f + f = dec(f)", ms.unwrap_decorators(tmpf, {"h"}) == 1 and "h = r.get('/x')(other(h))" in open(tmpf).read() and "@r.get" not in open(tmpf).read())
compile(open(tmpf).read(), tmpf, "exec")

if os.environ.get("QA_TEST_ONLY"):  # debugging aid: run ONE named fixture commit through the real entry point and print the verdict
    sha = shas[os.environ["QA_TEST_ONLY"]]
    t0 = time.time()
    rc, r, out = gate(GATE_ABS, "mutdemo", prev(sha), sha, extra=os.environ.get("QA_TEST_EXTRA", "").split())
    print(json.dumps(r, indent=1)[:3000])
    print("wall %.0fs, fixture kept at %s" % (time.time() - t0, T))
    sys.exit(0)

_sl = subprocess.Popen(["sleep", "20"], cwd=os.path.join(T, "tmp"))
time.sleep(0.5)
ok("orphan detector self-check: a live process in the fixture dir IS seen", str(_sl.pid) in procs_under(T))
_sl.kill()
_sl.wait()

print("== mutation_spike (QA_VENV=%s, mutmut available: %s)" % (QA_VENV, HAVE))

# ---- controls that need no mutmut ------------------------------------------------------------------------------------------
for label, script in (("absolute path", GATE_ABS), ("relative path", GATE_REL)):
    rc, r, _ = gate(script, "mutdemo", prev(testonly), testonly)
    ok("[%s] test-only change -> NA, exit 0, one JSON line" % label, rc == 0 and r.get("verdict") == "NA" and r.get("gate") == "mutation_spike", str(r))
rc, r, _ = gate(GATE_ABS, "mutdemo", prev(docs), docs)
ok("docs-only change -> NA", r.get("verdict") == "NA", str(r))
rc, r, _ = gate(GATE_ABS, "mutdemo", prev(modlevel), modlevel)
ok("constant-only change (no function body touched) -> NA, never a bogus PASS", r.get("verdict") == "NA", str(r))
rc, r, _ = gate(GATE_ABS, "no-such-repo", "HEAD^", "HEAD")
ok("unknown repo -> UNVERIFIED (not FAIL/PASS), exit 0", rc == 0 and r.get("verdict") == "UNVERIFIED", str(r))
rc, r, _ = gate(GATE_ABS, "mutdemo", prev(weak), weak, qa_venv="/nonexistent-qa-venv")
ok("missing mutmut / venv -> UNVERIFIED (never PASS), exit 0", rc == 0 and r.get("verdict") == "UNVERIFIED" and "venv" in r.get("summary", "") + "mutmut", str(r))
rc, r, _ = gate(GATE_ABS, "mutdemo", prev(weak), weak, extra=["--cap", "5"], qa_venv="/nonexistent-qa-venv")
ok("a tiny cap never produces PASS/FAIL", r.get("verdict") in ("UNVERIFIED", "NA"), str(r))

# ---- real mutmut runs ------------------------------------------------------------------------------------------------------
if not HAVE:
    for n in ("weak test -> FLAG with survivors", "strong test -> PASS", "untested function -> FLAG", "red test deselected",
              "conftest error -> UNVERIFIED", "timeout -> UNVERIFIED + no orphan workers"):
        skip(n, "mutmut/pytest not installed in QA_VENV=%s" % QA_VENV)
else:
    rc, r, out = gate(GATE_ABS, "mutdemo", prev(weak), weak)
    d = r.get("details", {})
    ok("NEG control: weak test -> FLAG (abs path)", rc == 0 and r.get("verdict") == "FLAG", str(r)[:400])
    ok("weak test: survivors listed with a diff and a label", d.get("survivors_total", 0) >= 2 and d.get("survivors_shown") and "diff" in d["survivors_shown"][0], str(d)[:300])
    ok("weak test: mutation score < 100 and counts present", d.get("mutation_score_pct") is not None and d["mutation_score_pct"] < 100 and d.get("counts", {}).get("survived", 0) >= 2)
    ok("weak test: changed function identified by ast+diff", d.get("functions") == ["app/rules.py:tier"], str(d.get("functions")))
    rc, r, _ = gate(GATE_REL, "mutdemo", prev(weak), weak)
    ok("NEG control repeated via the RELATIVE path -> FLAG", r.get("verdict") == "FLAG", str(r)[:300])

    rc, r, _ = gate(GATE_ABS, "mutdemo", prev(weak), weak, extra=["--select-tests"])
    d = r.get("details", {})
    ok("--select-tests runs only the tests that mention the changed module and still FLAGs the weak test", r.get("verdict") == "FLAG" and d.get("tests_selected") == ["tests/test_rules.py"], str(d.get("tests_selected")))
    rc, r, _ = gate(GATE_ABS, "mutdemo", prev(weak), weak, extra=["--pytest-arg", "-n", "--pytest-arg", "2"])
    ok("pytest-xdist args are refused (they hide mutmut's per-function stats -> false 'untested')", r.get("verdict") == "UNVERIFIED" and "xdist" in r.get("summary", ""), str(r)[:300])

    rc, r, _ = gate(GATE_ABS, "mutdemo", prev(strong), strong)
    d = r.get("details", {})
    ok("BENIGN control: strong boundary tests -> PASS, score 100", r.get("verdict") == "PASS" and d.get("mutation_score_pct") == 100.0, str(r)[:400])

    rc, r, _ = gate(GATE_ABS, "mutdemo", prev(orphan), orphan)
    d = r.get("details", {})
    ok("NEG control: function with no test at all -> FLAG listing it as untested", r.get("verdict") == "FLAG" and d.get("untested_functions"), str(r)[:400])

    rc, r, _ = gate(GATE_ABS, "mutdemo", prev(red), red)
    d = r.get("details", {})
    ok("red test in the suite is deselected + reported, run still completes", r.get("verdict") in ("PASS", "FLAG") and d.get("deselected_count") == 1, str(r)[:400])

    rc, r, _ = gate(GATE_ABS, "mutdemo", prev(broken), broken)
    ok("conftest that raises at import -> UNVERIFIED (not PASS)", r.get("verdict") == "UNVERIFIED", str(r)[:300])
    rc, r, _ = gate(GATE_ABS, "mutdemo", prev(collerr), collerr)
    d = r.get("details", {})
    ok("one module with a collection error is --ignore'd and reported; the rest is measured", r.get("verdict") in ("PASS", "FLAG") and any(x.startswith("--ignore=") for x in d.get("deselected_tests", [])), str(r)[:400])

    rc, r, _ = gate(GATE_ABS, "mutdemo", prev(decorated), decorated)
    ok("decorated (route-style) function -> UNVERIFIED with an explicit reason, not a bogus PASS", r.get("verdict") == "UNVERIFIED" and "decorated" in r.get("summary", ""), str(r)[:300])
    rc, r, _ = gate(GATE_ABS, "mutdemo", prev(decorated), decorated, extra=["--unwrap-decorators"])
    d = r.get("details", {})
    ok("--unwrap-decorators (experimental) makes the decorated function measurable", r.get("verdict") in ("PASS", "FLAG") and d.get("unwrapped_decorators") == 1 and d.get("mutants_total", 0) > 0, str(r)[:400])
    rc, r, _ = gate(GATE_ABS, "mutdemo", prev(deletion), deletion)
    ok("a pure deletion inside a function identifies that function as changed", r.get("details", {}).get("functions") == ["app/calc.py:clamp"], str(r)[:400])
    t0 = time.time()
    rc, r, _ = gate(GATE_ABS, "mutdemo", prev(slow), slow, extra=["--cap", "30"])
    wall = time.time() - t0
    ok("timeout -> UNVERIFIED mentioning the cap", rc == 0 and r.get("verdict") == "UNVERIFIED" and "cap" in r.get("summary", ""), str(r)[:300])
    ok("timeout: returned within cap + slack", wall < 30 + 45, "%.0fs" % wall)
    time.sleep(1)
    ok("timeout: no orphan mutmut/pytest processes left behind", not procs_under(T), str(procs_under(T)))

# worktrees always cleaned up
wl = g("worktree", "list", "--porcelain").stdout.count("worktree ")
ok("no worktree left registered in the clone", wl == 1, g("worktree", "list").stdout)
ok("the clone's tree is untouched", g("status", "--porcelain").stdout.strip() == "")

shutil.rmtree(T, ignore_errors=True)
print("\n%d passed, %d failed, %d skipped" % (P, F, S))
sys.exit(1 if F else 0)
