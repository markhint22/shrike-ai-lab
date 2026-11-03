#!/usr/bin/env python3
"""K2 QA toolchain tests (package K2-qa-toolchain): qa_tool_health.json -> reason_code tool-missing in the scanner and mutation gates, diff-scoped mutation
(line scope + ranked test selection, wall cap), scanner selftest seeded positives (skip cleanly without tools). Hermetic: private HOME / OVN_DIR / state dir via mkdtemp,
no network, NTFY_SERVER pointed at a dead port. Real-mutmut controls need mutmut + pytest in $QA_VENV (or ~/qa-venv) and SKIP loudly otherwise (OVN_REQUIRE_QA_VENV=1 makes that a FAIL).
Every mutation proof copies the real file with ONE edit and the guarding assertion must FAIL against the copy."""
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
P = F = S = 0


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name + (("  -> " + str(extra)[:500]) if extra else ""))


def skip(name, why):
    global S
    S += 1
    print("  SKIP %s (%s)" % (name, why))


T = tempfile.mkdtemp(prefix="qa-k2-test-")
if not T or os.path.realpath(T) in ("/", os.path.realpath(os.path.expanduser("~"))):
    sys.exit("unsafe temp dir")
OVN, STATE, REPOS, TMP, HOME = (os.path.join(T, d) for d in ("ovn", "ovn/state", "repos", "tmp", "home"))
for d in (STATE, REPOS, TMP, HOME):
    os.makedirs(d, exist_ok=True)
GENV = dict(os.environ, GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t", GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@t")


def _qa_venv():
    if os.environ.get("QA_VENV"):
        return os.environ["QA_VENV"]
    for c in (os.path.expanduser("~/qa-venv"), os.path.expanduser("~/overnight-queue/qa-tools/.venv")):
        if os.path.exists(os.path.join(c, "bin", "mutmut")) and os.path.exists(os.path.join(c, "bin", "pytest")):
            return c
    return os.path.expanduser("~/qa-venv")


QA_VENV = _qa_venv()
HAVE = os.path.exists(os.path.join(QA_VENV, "bin", "mutmut")) and os.path.exists(os.path.join(QA_VENV, "bin", "pytest"))


def base_env(extra=None, path=None):
    e = {"PATH": path if path is not None else "/usr/bin:/bin", "HOME": HOME, "NTFY_SERVER": "http://127.0.0.1:9", "OVN_NOTIFY_DISABLE": "1", "TZ": "UTC",
         "OVN_DIR": OVN, "QA_STATE_DIR": STATE, "OVN_REPOS_DIR": REPOS, "TMPDIR": TMP}
    e.update(extra or {})
    return e


def run(script, args, env, timeout=300):
    p = subprocess.run([sys.executable, script] + list(args), cwd=OQ, capture_output=True, text=True, env=env, timeout=timeout)
    lines = [l for l in p.stdout.splitlines() if l.strip()]
    try:
        r = json.loads(lines[-1]) if lines else {}
    except ValueError:
        r = {"verdict": "NOT-JSON", "summary": (lines[-1] if lines else p.stderr)[:300]}
    return p.returncode, r


def clear_state():
    for f in os.listdir(STATE):
        fp = os.path.join(STATE, f)
        if os.path.isfile(fp):
            os.unlink(fp)


def mutant_copy(tag, rels, old, new):
    """Copy qa/ (python + spikes) to a private dir, apply ONE textual edit to rels[0], return the copy's qa dir."""
    dst = os.path.join(T, "mut-" + tag, "qa")
    shutil.copytree(QA, dst, ignore=shutil.ignore_patterns("__pycache__", "*.jsonl"))
    p = os.path.join(dst, rels)
    s = open(p).read()
    assert s.count(old) == 1, "mutant %s: %r found %d times in %s" % (tag, old, s.count(old), rels)
    open(p, "w").write(s.replace(old, new))
    return dst


print("== K2 qa toolchain (QA_VENV=%s, mutmut available: %s)" % (QA_VENV, HAVE))

# ------------------------------------------------------------------------------------------------ (a) qa_tool_health.json
STUBS = os.path.join(T, "stubs")
os.makedirs(STUBS)
for name in ("ruff", "bandit", "mypy", "semgrep", "pip-audit", "schemathesis", "docker", "flock"):
    p = os.path.join(STUBS, name)
    open(p, "w").write('#!/bin/sh\necho "%s 9.9.9"\n' % name)
    os.chmod(p, 0o755)
# gitleaks and mutmut deliberately absent
H = os.path.join(QA, "qa_tool_health.py")


def health(path_dirs):
    clear_state()
    rc, r = run(H, [], base_env(path=":".join(path_dirs + ["/usr/bin", "/bin"])))
    try:
        doc = json.load(open(os.path.join(STATE, "qa_tool_health.json")))
    except (OSError, ValueError):
        doc = {}
    return rc, r, doc


rc, r, doc = health([STUBS])
tools = doc.get("tools", {})
ok("qa_tool_health writes state/qa_tool_health.json {ts, tools}", rc == 0 and doc.get("ts") and tools, (rc, str(r)[:200]))
ok("present+working tool: installed, working, on_path, version", tools.get("ruff", {}).get("installed") and tools["ruff"].get("working") and tools["ruff"].get("on_path")
   and tools["ruff"].get("version") == "ruff 9.9.9", str(tools.get("ruff")))
ok("absent tool (gitleaks) is installed=False working=False status missing", tools.get("gitleaks", {}).get("status") == "missing" and tools["gitleaks"]["installed"] is False
   and tools["gitleaks"]["working"] is False, str(tools.get("gitleaks")))
ok("mutmut absent -> missing", tools.get("mutmut", {}).get("status") == "missing")
# a tool inside the qa venv is reported in_qa_venv
qv = os.path.join(HOME, "qa-venv", "bin")
os.makedirs(qv)
shutil.copy(os.path.join(STUBS, "ruff"), os.path.join(qv, "ruff"))
os.chmod(os.path.join(qv, "ruff"), 0o755)
rc, r, doc2 = health([STUBS])
ok("tool found in ~/qa-venv/bin reports in_qa_venv", doc2["tools"]["ruff"].get("in_qa_venv") is True, str(doc2["tools"]["ruff"]))
shutil.rmtree(os.path.join(HOME, "qa-venv"))
# MUTATION PROOF: remove a tool from PATH -> the report says missing
os.unlink(os.path.join(STUBS, "ruff"))
rc, r, doc3 = health([STUBS])
ok("remove ruff from PATH -> status missing, installed False (mutation proof for the report)", doc3["tools"]["ruff"]["status"] == "missing" and doc3["tools"]["ruff"]["installed"] is False,
   str(doc3["tools"]["ruff"]))
open(os.path.join(STUBS, "ruff"), "w").write('#!/bin/sh\necho "ruff 9.9.9"\n')
os.chmod(os.path.join(STUBS, "ruff"), 0o755)
rc, r, _ = health([STUBS])
# --no-record writes nothing
clear_state()
run(H, ["--no-record"], base_env(path=STUBS + ":/usr/bin:/bin"))
ok("--no-record does not write qa_tool_health.json", not os.path.exists(os.path.join(STATE, "qa_tool_health.json")))

# ------------------------------------------------------------------------------------------------ qa_common helpers
os.environ.update({"OVN_DIR": OVN, "QA_STATE_DIR": STATE, "OVN_REPOS_DIR": REPOS, "HOME": HOME, "PATH": "/usr/bin:/bin"})   # hermetic live probe (qc.tool_present)
sys.path.insert(0, QA)
import qa_common as qc  # noqa: E402

hp = os.path.join(STATE, "qa_tool_health.json")


def write_health(tools, ts=None):
    json.dump({"ts": ts if ts is not None else time.time(), "tools": tools}, open(hp, "w"))


write_health({"ruff": {"status": "missing"}, "bandit": {"status": "ok"}, "mypy": {"status": "broken"}})
ok("tool_unavailable: missing / broken / ok / unknown", (qc.tool_unavailable("ruff"), qc.tool_unavailable("mypy"), qc.tool_unavailable("bandit"), qc.tool_unavailable("nope")) == ("missing", "broken", "", ""))
write_health({"ruff": {"status": "missing"}}, ts=time.time() - 10 * 86400)
ok("a STALE report (10 days) never marks anything", qc.tool_health() == {} and qc.tool_unavailable("ruff") == "")
open(hp, "w").write("{not json")
ok("corrupt report -> {} (never raises)", qc.tool_health() == {})
os.unlink(hp)
ok("absent report -> {}", qc.tool_health() == {})


def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec)
    sys.path.insert(0, os.path.dirname(path))
    spec.loader.exec_module(m)
    return m


# ------------------------------------------------------------------------------------------------ gates mark tool-missing from the report
def scan_cells(gs):
    return {"ruff": {"status": "UNVERIFIED", "note": "ruff missing"},         # rc 127 style note: text matching alone cannot see this one
            "bandit": {"status": "UNVERIFIED", "note": "bandit timed out"},
            "gitleaks": {"status": "UNVERIFIED", "note": "gitleaks not installed"},
            "mypy": {"status": "OK", "note": ""}}


gs = load(os.path.join(QA, "gate_scanners.py"), "gate_scanners_k2")
write_health({"ruff": {"status": "missing"}, "bandit": {"status": "ok"}, "mypy": {"status": "missing"}})
cells = scan_cells(gs)
miss = gs.mark_tool_missing(cells)
ok("scanners: report says ruff missing -> reason_code tool-missing (source qa_tool_health)", cells["ruff"].get("reason_code") == "tool-missing" and cells["ruff"].get("reason_source") == "qa_tool_health", str(cells["ruff"]))
ok("scanners: a tool the report says is OK is not marked on a timeout", "reason_code" not in cells["bandit"])
ok("scanners: the old text match still works without a report entry", cells["gitleaks"].get("reason_code") == "tool-missing")
ok("scanners: a non-UNVERIFIED cell is never marked even when the report says missing", "reason_code" not in cells["mypy"] and miss == ["gitleaks", "ruff"], str(miss))
os.unlink(hp)
cells = scan_cells(gs)
gs.mark_tool_missing(cells)
ok("scanners: no report -> only the text match marks (behaviour unchanged)", "reason_code" not in cells["ruff"] and cells["gitleaks"].get("reason_code") == "tool-missing")
mc = mutant_copy("K2A", "gate_scanners.py", 'by_health = qc.tool_unavailable(t, health) == "missing"', "by_health = False")
write_health({"ruff": {"status": "missing"}})
gsm = load(os.path.join(mc, "gate_scanners.py"), "gate_scanners_k2_mut")
cells = scan_cells(gsm)
gsm.mark_tool_missing(cells)
ok("MUTANT (report ignored) is caught: ruff no longer marked", "reason_code" not in cells["ruff"])
os.unlink(hp)

# mutation gate: report says mutmut missing -> reason, skip row reason_code, UNVERIFIED row reason_code
gm = load(os.path.join(QA, "gate_mutation.py"), "gate_mutation_k2")
EMPTY_VENV = os.path.join(T, "empty-venv")        # hermetic: tool-missing assertions must hold on a box where mutmut IS installed (real ~/qa-venv is never consulted here)
os.makedirs(EMPTY_VENV, exist_ok=True)
os.environ["QA_VENV"] = EMPTY_VENV
os.environ["PATH"] = EMPTY_VENV                    # no mutmut/ruff on PATH either (qc.tool_present probes PATH + the venv)
write_health({"mutmut": {"status": "missing"}})
ok("mutation: tooling_reason cites qa_tool_health when the report says mutmut missing", "qa_tool_health: missing" in gm.tooling_reason(), gm.tooling_reason())
clear_state() if False else None
gm.record_skip(gm.tooling_reason(), "demo", True)
rows = [json.loads(l) for l in open(os.path.join(STATE, "qa_gate_skips.jsonl"))]
ok("mutation: the skip row carries reason_code tool-missing", rows and rows[-1].get("reason_code") == "tool-missing", str(rows[-1:]))
write_health({"mutmut": {"status": "ok"}})
ok("mutation: report says ok -> no health-based reason", "qa_tool_health" not in gm.tooling_reason())
os.unlink(hp)
mcg = mutant_copy("K2B", "gate_mutation.py", 'if qc.tool_unavailable("mutmut") == "missing":', "if False:")
write_health({"mutmut": {"status": "missing"}})
gmm = load(os.path.join(mcg, "gate_mutation.py"), "gate_mutation_k2_mut")
ok("MUTANT (report ignored in tooling_reason) is caught", "qa_tool_health" not in gmm.tooling_reason())
os.unlink(hp)


class Repo:
    def __init__(self, name):
        self.path = os.path.join(REPOS, name)
        os.makedirs(self.path)
        self.g("init", "-q", "-b", "develop")

    def g(self, *a):
        return subprocess.run(["git", "-C", self.path] + list(a), capture_output=True, text=True, env=GENV)

    def write(self, rel, body):
        p = os.path.join(self.path, rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        open(p, "w").write(body)

    def commit(self, msg):
        self.g("add", ".")
        self.g("commit", "-q", "-m", msg)
        return self.g("rev-parse", "HEAD").stdout.strip()


GATE = os.path.join(QA, "gate_mutation.py")

# UNVERIFIED row for a box without mutmut gets reason_code tool-missing (QA_VENV points at nothing)
rp = Repo("k2none")
rp.write("svc/app/__init__.py", "")
rp.write("svc/app/m.py", "def f(x):\n    return x + 1\n")
rp.write("svc/tests/test_m.py", "from app.m import f\n\n\ndef test_f():\n    assert f(1) == 2\n")
rp.write("svc/pytest.ini", "[pytest]\ntestpaths = tests\n")
b0 = rp.commit("base")
rp.write("svc/app/m.py", "def f(x):\n    return x + 2\n")
h0 = rp.commit("change")
rc, r = run(GATE, ["check", "--repo", "k2none", "--base", b0, "--head", h0, "--no-record"], base_env({"QA_VENV": os.path.join(T, "no-such-venv")}))
ok("mutation row without mutmut: UNVERIFIED + details.reason_code tool-missing", rc == 0 and r.get("verdict") == "UNVERIFIED" and r.get("details", {}).get("reason_code") == "tool-missing"
   and r["details"].get("missing_tools") == ["mutmut"], "%s | %s | %s" % (r.get("verdict"), r.get("summary"), r.get("details", {}).get("reason_code")))
mcr = mutant_copy("K2C", "gate_mutation.py", 'det["reason_code"] = "tool-missing"', 'det["reason_code"] = "other"')
rc, rm = run(os.path.join(mcr, "gate_mutation.py"), ["check", "--repo", "k2none", "--base", b0, "--head", h0, "--no-record"], base_env({"QA_VENV": os.path.join(T, "no-such-venv")}))
ok("MUTANT (wrong reason code) is caught", rm.get("details", {}).get("reason_code") != "tool-missing")

# ------------------------------------------------------------------------------------------------ (c) diff-scoped mutation, real mutmut
sp = load(os.path.join(QA, "spikes", "mutation_spike.py"), "mutation_spike_k2")
# test selection by changed-file mapping (no mutmut needed)
sd = os.path.join(T, "selsvc")
os.makedirs(os.path.join(sd, "tests"))
for fn, body in (("test_billing.py", "def test_a():\n    pass\n"),                       # name convention only
                 ("test_x.py", "from app.billing import plan_for\n"),                     # mention only
                 ("test_y.py", "from app.billing import plan_for\n"),                     # mention + changed in range
                 ("test_z.py", "def test_unrelated():\n    pass\n"),                      # changed but unrelated -> NOT selected
                 ("conftest.py", "import app.billing\n")):
    open(os.path.join(sd, "tests", fn), "w").write(body)
info = {}
sel = sp.select_tests(sd, ["app.billing"], ["plan_for"], changed_tests=["tests/test_y.py", "tests/test_z.py"], info=info)
ok("select_tests: name-convention, mention and changed+mention are selected; a changed unrelated test and conftest are not",
   sel == ["tests/test_billing.py", "tests/test_x.py", "tests/test_y.py"], str(sel))
sel2 = sp.select_tests(sd, ["app.billing"], ["plan_for"], limit=2, changed_tests=["tests/test_y.py"], info=info)
ok("select_tests: over the limit it truncates by rank (changed first) and records it, instead of falling back to the full suite",
   len(sel2) == 2 and "tests/test_y.py" in sel2 and info.get("truncated") == 1, "%s %s" % (sel2, info))
mcs = mutant_copy("K2D", "spikes/mutation_spike.py", 'return sorted(ranked[:limit])', 'return sorted(ranked) if len(ranked) <= limit else []')
spm = load(os.path.join(mcs, "spikes", "mutation_spike.py"), "mutation_spike_k2_mut")
ok("MUTANT (old over-limit -> full-suite fallback) is caught", spm.select_tests(sd, ["app.billing"], ["plan_for"], limit=2, changed_tests=["tests/test_y.py"], info={}) == [])

if not HAVE:
    if os.environ.get("OVN_REQUIRE_QA_VENV"):
        ok("real mutmut + pytest available in QA_VENV (OVN_REQUIRE_QA_VENV=1)", False, QA_VENV)
    for n in ("line scope: changed-line mutants only", "pragma pre-filter excluded count / post filter alone / both off", "comment-only -> NA", "scoping reduces real mutant count (8-line fixture)", "wall cap respected"):
        skip(n, "mutmut/pytest not installed in QA_VENV=%s" % QA_VENV)
else:
    r1 = Repo("k2demo")
    r1.write("svc/app/__init__.py", "")
    r1.write("svc/app/score.py", "def score(x):\n    base = x + 1\n    return base > 9\n")
    r1.write("svc/tests/test_score.py", "from app.score import score\n\n\ndef test_hit():\n    assert score(10) is True\n\n\ndef test_miss():\n    assert score(0) is False\n")
    r1.write("svc/pytest.ini", "[pytest]\ntestpaths = tests\n")
    kb = r1.commit("base")
    r1.write("svc/app/score.py", "def score(x):\n    base = x + 1\n    return base > 10\n")      # ONLY the return line changes
    kh = r1.commit("tighten threshold")
    env = base_env({"QA_VENV": QA_VENV, "OVN_MUT_CAP_S": "120"})

    def chk(repo, b_, h_, extra=None, script=GATE):
        rc_, r_ = run(script, ["check", "--repo", repo, "--base", b_, "--head", h_, "--no-record"], dict(env, **(extra or {})))
        return r_, r_.get("details", {}), r_.get("details", {}).get("yield", {})

    t0 = time.time()
    r, d, y = chk("k2demo", kb, kh)
    wall = time.time() - t0
    # REAL contract: the pragma PRE-filter already removed the unchanged-line mutants, so mutmut generates only the changed-line ones (2: `>` -> `>=` survives, `10` -> `11` killed)
    ok("line scope: exactly the changed-line mutants are judged: 2 mutants, 1 survives (>=), 1 killed", y.get("mutants") == 2 and y.get("survivors") == 1 and y.get("killed") == 1 and r.get("verdict") == "FLAG",
       str(r)[:600])
    ok("pragma pre-filter: the unchanged line (base = x + 1) was excluded BEFORE mutation (1 line), so the post-run filter has nothing left to drop (0) and mutmut saw only 2 mutants",
       d.get("pragma_scope", {}).get("unchanged_lines_excluded_before_mutation") == 1 and d.get("line_scope", {}).get("dropped_outside_changed_lines") == 0
       and d.get("line_scope", {}).get("mutants_total_in_changed_functions") == 2, str(d.get("pragma_scope")) + str(d.get("line_scope")))
    ok("wall cap: finished well inside the cap and the cap is in the row", wall < 120 and d.get("limits", {}).get("cap_s") == 120 and y.get("runtime_s", 999) < 120, "%.0fs %s" % (wall, d.get("limits")))
    # the post-run filter is the second line of defence (multi-line statements / compound headers): prove it on its own with the pre-filter off
    ro, dpo, ypo = chk("k2demo", kb, kh, {"OVN_MUT_PRAGMA_SCOPE": "0"})
    ok("post-run filter alone (OVN_MUT_PRAGMA_SCOPE=0): mutmut generates the unchanged-line mutants and the filter drops them (dropped >= 1), still 2 judged",
       dpo.get("pragma_scope", {}).get("enabled") is False and dpo.get("line_scope", {}).get("dropped_outside_changed_lines", 0) >= 1 and ypo.get("mutants") == 2, str(dpo.get("line_scope")) + str(ypo))
    rn0, dn0, yn0 = chk("k2demo", kb, kh, {"OVN_MUT_PRAGMA_SCOPE": "0", "OVN_MUT_LINE_SCOPE": "0"})
    ok("both scopes off (mutation proof): the unchanged-line mutants are judged too (more than 2 mutants)", yn0.get("mutants", 0) > 2, str(yn0))
    mcl = mutant_copy("K2E", "spikes/mutation_spike.py", "if hit and hit[0] in line_hunks", "if False and hit and hit[0] in line_hunks")
    rl, dl, yl = chk("k2demo", kb, kh, {"OVN_MUT_PRAGMA_SCOPE": "0"}, script=os.path.join(mcl, "gate_mutation.py"))
    ok("MUTANT (post-run line filter never drops) is caught (pre-filter off: more than 2 mutants)", yl.get("mutants", 0) > 2, str(yl))
    # a change that leaves NO mutable code on its lines: comment only -> NA (nothing to mutate), never UNVERIFIED (mutmut's "should be covered" error on 0 mutants) or FLAG
    r1.write("svc/app/score.py", "def score(x):\n    base = x + 1\n    # note\n    return base > 10\n")
    kh2 = r1.commit("comment only")
    rn, dn, yn = chk("k2demo", kh, kh2)
    ok("comment-only change inside a function: verdict NA with the zero-mutants reason (not UNVERIFIED, not FLAG)",
       rn.get("verdict") == "NA" and dn.get("zero_mutants_after_scoping") is True and "no mutable code" in rn.get("summary", ""), str(rn)[:500])
    mcn = mutant_copy("K2J", "spikes/mutation_spike.py", "if not res_rows and not timed_out and n_excl and zero_sig:", "if False:")
    rnm, dnm, _ = chk("k2demo", kh, kh2, script=os.path.join(mcn, "gate_mutation.py"))
    ok("MUTANT (zero-mutants -> NA branch removed) is caught: the comment-only range is no longer NA", rnm.get("verdict") != "NA", str(rnm)[:300])

    # (defect 2 proof, real mutmut) a function with MANY mutable lines of which ONE changed: scoping must reduce the mutant count mutmut really generates
    r2 = Repo("k2many")
    r2.write("svc/app/__init__.py", "")
    body = "def calc(x):\n    a = x + 1\n    b = a * 2\n    c = b - 3\n    d = c + a\n    e = d * b\n    f = e - c\n    g = f + d\n    return g > %d\n"
    r2.write("svc/app/calc.py", body % 100)
    r2.write("svc/tests/test_calc.py", "from app.calc import calc\n\n\ndef test_hit():\n    assert calc(20) is True\n\n\ndef test_miss():\n    assert calc(0) is False\n")
    r2.write("svc/pytest.ini", "[pytest]\ntestpaths = tests\n")
    mb = r2.commit("base")
    r2.write("svc/app/calc.py", body % 101)
    mh = r2.commit("one changed line")
    _, _, y_off = chk("k2many", mb, mh, {"OVN_MUT_PRAGMA_SCOPE": "0", "OVN_MUT_LINE_SCOPE": "0"})
    _, d_pre, y_pre = chk("k2many", mb, mh, {"OVN_MUT_LINE_SCOPE": "0"})
    _, d_def, y_def = chk("k2many", mb, mh)
    ok("scoping reduces the REAL mutant count: 8-line function, 1 changed line: no scope >= 10 mutants; pragma pre-filter alone (line scope off) <= 3; default == pre-filter (nothing left to drop)",
       y_off.get("mutants", 0) >= 10 and 0 < y_pre.get("mutants", 99) <= 3 and y_pre.get("mutants") == y_def.get("mutants") and d_pre.get("pragma_scope", {}).get("unchanged_lines_excluded_before_mutation") == 7,
       "off=%s pre=%s def=%s %s" % (y_off.get("mutants"), y_pre.get("mutants"), y_def.get("mutants"), d_pre.get("pragma_scope")))
    ok("scoping also reduces the work: mutmut runtime with the pre-filter does not exceed the unscoped runtime (informational bound, generous)", y_pre.get("runtime_s", 999) <= y_off.get("runtime_s", 0) + 5,
       "%s vs %s" % (y_pre.get("runtime_s"), y_off.get("runtime_s")))

# ------------------------------------------------------------------------------------------------ (c2) zero-mutants NA needs mutmut's REAL signature (fake mutmut, runs everywhere)
# A pragma pre-filter exclusion alone must never turn an arbitrary mutmut failure into NA (NA is a MEASURED verdict: the daily baseline advances).
FV = os.path.join(T, "fake-venv")
subprocess.run([sys.executable, "-m", "venv", "--without-pip", FV], capture_output=True)
FSP = [os.path.join(dp) for dp, dn, _ in os.walk(os.path.join(FV, "lib")) if os.path.basename(dp) == "site-packages"]
if not FSP:
    skip("fake-mutmut zero-mutants signature checks", "python venv could not be created")
else:
    os.makedirs(os.path.join(FSP[0], "mutmut"))
    open(os.path.join(FSP[0], "mutmut", "__init__.py"), "w").write("")
    open(os.path.join(FSP[0], "mutmut", "__main__.py"), "w").write(
        "import sys\n"
        "MODE = open(%r).read().strip()\n" % os.path.join(FV, "mode") +
        "def cli():\n"
        "    if MODE == 'zero':\n"
        "        print('Stopping early, because we could not find any test case for any mutant. It seems that the selected tests do not cover any code that we mutated.')\n"
        "        print('If some of the mutated code should be covered by the executed tests, consider opening an issue (with a MRE if possible).')\n"
        "        return 1\n"
        "    if MODE == 'zero-rc2':\n"
        "        print('Stopping early, because we could not find any test case for any mutant.')\n"
        "        return 2\n"
        "    if MODE == 'crash':\n"
        "        raise RuntimeError('boom: mutmut crashed')\n"
        "    if MODE == 'import':\n"
        "        import not_a_real_module_xyz\n"
        "    if MODE == 'config':\n"
        "        print('Error: could not parse setup.cfg [mutmut] section')\n"
        "        return 1\n"
        "    return 0\n"
        "if __name__ == '__main__':\n"
        "    sys.exit(cli())\n")
    for tool in ("mutmut", "pytest"):
        open(os.path.join(FV, "bin", tool), "w").write("#!/bin/sh\nexit 0\n")
        os.chmod(os.path.join(FV, "bin", tool), 0o755)
    rf = Repo("k2fake")
    rf.write("svc/app/__init__.py", "")
    rf.write("svc/app/score.py", "def score(x):\n    base = x + 1\n    return base > 9\n")
    rf.write("svc/tests/test_score.py", "from app.score import score\n\n\ndef test_hit():\n    assert score(10) is True\n")
    rf.write("svc/pytest.ini", "[pytest]\ntestpaths = tests\n")
    fb = rf.commit("base")
    rf.write("svc/app/score.py", "def score(x):\n    base = x + 1\n    # note\n    return base > 9\n")
    fh = rf.commit("comment only")
    fenv = base_env({"QA_VENV": FV, "OVN_MUT_CAP_S": "120"})

    def fchk(mode, script=GATE):
        open(os.path.join(FV, "mode"), "w").write(mode)
        _, r_ = run(script, ["check", "--repo", "k2fake", "--base", fb, "--head", fh, "--no-record"], fenv)
        return r_, r_.get("details", {})

    rz, dz = fchk("zero")
    ok("fake mutmut: real zero-mutants signature (message + rc=1) with n_excl>0 -> NA",
       rz.get("verdict") == "NA" and dz.get("zero_mutants_after_scoping") is True and dz.get("pragma_scope", {}).get("unchanged_lines_excluded_before_mutation", 0) > 0, str(rz)[:500])
    for mode, label in (("crash", "crash (Python traceback)"), ("import", "import error"), ("config", "config error with rc=1 but no zero-mutants message"),
                        ("zero-rc2", "zero-mutants text but unexpected rc=2")):
        rv, dv = fchk(mode)
        ok("fake mutmut: %s with n_excl>0 -> UNVERIFIED (never NA, no zero_mutants flag)" % label,
           rv.get("verdict") == "UNVERIFIED" and not dv.get("zero_mutants_after_scoping") and dv.get("pragma_scope", {}).get("unchanged_lines_excluded_before_mutation", 0) > 0
           and "mutmut failed (rc=" in rv.get("summary", ""), str(rv)[:500])
    mcz = mutant_copy("K2Z", "spikes/mutation_spike.py", "and n_excl and zero_sig:", "and n_excl:")
    rzm, _ = fchk("crash", script=os.path.join(mcz, "gate_mutation.py"))
    ok("MUTANT (signature check removed) is caught: a mutmut crash turns into NA", rzm.get("verdict") == "NA", str(rzm)[:300])
    mcr1 = mutant_copy("K2R", "spikes/mutation_spike.py", "zero_sig = (rc == 1 and", "zero_sig = (True and")
    rzr, _ = fchk("zero-rc2", script=os.path.join(mcr1, "gate_mutation.py"))
    ok("MUTANT (rc check removed) is caught: rc=2 with the message turns into NA", rzr.get("verdict") == "NA", str(rzr)[:300])

# ------------------------------------------------------------------------------------------------ (d) scanner selftest seeded positives
GS = os.path.join(QA, "gate_scanners.py")
rc, r = run(GS, ["selftest"], base_env(path="/usr/bin:/bin"))
ok("selftest without any scanner installed: UNVERIFIED (skips cleanly), exit 0, every seed UNMEASURED",
   rc == 0 and r.get("verdict") == "UNVERIFIED" and r.get("details", {}).get("measured") == 0
   and len(r["details"].get("seeds", [])) == 3 and all(s["status"] == "UNMEASURED" for s in r["details"]["seeds"]), str(r)[:500])
ok("selftest seeds are exactly the three required positives (secret, vulnerable pin, B602)", sorted(s["tool"] for s in r.get("details", {}).get("seeds", [])) == ["bandit", "gitleaks", "pip-audit"])
bandit = os.environ.get("QA_TOOL_BANDIT") or (os.path.join(QA_VENV, "bin", "bandit") if os.path.exists(os.path.join(QA_VENV, "bin", "bandit")) else "")
if not bandit:
    skip("selftest catches the seeded bandit B602 once bandit exists", "bandit not available (QA_VENV or QA_TOOL_BANDIT)")
else:
    rc, r = run(GS, ["selftest", "--tools", "bandit"], base_env({"QA_TOOL_BANDIT": bandit}))
    seeds = {s["tool"]: s["status"] for s in r.get("details", {}).get("seeds", [])}
    ok("selftest catches the seeded bandit B602 once bandit exists (CAUGHT, recall 1/1)", seeds.get("bandit") == "CAUGHT" and r.get("details", {}).get("recall") == 1.0, str(r)[:500])
    mcf = mutant_copy("K2F", "gate_scanners.py", 'caught = cell.get("new", 0) > 0 and res["verdict"] in ("FAIL", "FLAG")', "caught = False")
    rc, rm = run(os.path.join(mcf, "gate_scanners.py"), ["selftest", "--tools", "bandit"], base_env({"QA_TOOL_BANDIT": bandit}))
    ok("MUTANT (a seed is never counted caught) is caught: verdict becomes FLAG", rm.get("verdict") == "FLAG")


# ------------------------------------------------------------------------------------------------ stale/wrong "missing" report vs a tool that IS present (review defect 1)
sys.path.insert(0, QA)
gm = load(os.path.join(QA, "gate_mutation.py"), "gate_mutation_k2_stale")
os.environ["OVN_QA_TOOL_HEALTH_MAX_AGE_S"] = "7200"
write_health({"mutmut": {"status": "missing"}, "ruff": {"status": "missing"}}, ts=time.time() - 40 * 3600)
ok("a 40h-old report is ignored by default (max age 2h)", qc.tool_health() == {} and "missing" not in gm.tooling_reason())
os.environ.pop("OVN_QA_TOOL_HEALTH_MAX_AGE_S")
ok("default max age is 2h: a 3h-old report marks nothing", (write_health({"ruff": {"status": "missing"}}, ts=time.time() - 3 * 3600), qc.tool_unavailable("ruff"))[1] == "")
ok("default max age is 2h: a 30min-old report still marks", (write_health({"ruff": {"status": "missing"}}, ts=time.time() - 1800), qc.tool_unavailable("ruff"))[1] == "missing")
# a FRESH report that says missing while the tool is on disk (installed after the report) must not mark anything
write_health({"ruff": {"status": "missing"}, "mutmut": {"status": "missing"}})
qv2 = os.path.join(HOME, "qa-venv")
os.makedirs(os.path.join(qv2, "bin"))
for t in ("ruff", "mutmut"):
    open(os.path.join(qv2, "bin", t), "w").write("#!/bin/sh\n")
    os.chmod(os.path.join(qv2, "bin", t), 0o755)
sp2 = os.path.join(qv2, "lib", "python3.11", "site-packages", "mutmut")
os.makedirs(sp2)
ok("report says ruff missing but ~/qa-venv/bin/ruff exists -> tool_unavailable ''", qc.tool_unavailable("ruff") == "")
_oldqv = EMPTY_VENV
os.environ["QA_VENV"] = qv2
ok("tooling_reason(): report says mutmut missing but mutmut is installed in the QA venv -> '' (daily pass is NOT skipped)", gm.tooling_reason() == "", gm.tooling_reason())
cells = {"ruff": {"status": "UNVERIFIED", "note": "ruff timed out"}}
gs.mark_tool_missing(cells)
ok("scanners: report says missing but tool present -> no tool-missing tag", "reason_code" not in cells["ruff"], str(cells))
res = gm.finish({"verdict": "UNVERIFIED", "summary": "wall cap hit", "details": {}}, ["--repo", "x"], {"--cap": 60}, time.time())
ok("mutation finish(): UNVERIFIED (cap) with a wrong 'missing' report is NOT tagged tool-missing", "reason_code" not in res["details"], str(res["details"])[:200])
shutil.rmtree(qv2)
os.environ["QA_VENV"] = _oldqv
write_health({"ruff": {"status": "missing"}, "mutmut": {"status": "missing"}})
ok("control: tools really absent + fresh report -> still missing / tooling_reason names it", qc.tool_unavailable("ruff") == "missing" and "qa_tool_health: missing" in gm.tooling_reason(), gm.tooling_reason())
res = gm.finish({"verdict": "UNVERIFIED", "summary": "wall cap hit", "details": {}}, ["--repo", "x"], {"--cap": 60}, time.time())
ok("control: absent tool + fresh report -> finish tags tool-missing", res["details"].get("reason_code") == "tool-missing")
mc = mutant_copy("K2G", "qa_common.py", 'if st == "missing" and tool_present(name):', 'if False:')
qm = load(os.path.join(mc, "qa_common.py"), "qa_common_k2_mut")
os.makedirs(os.path.join(qv2, "bin"))
open(os.path.join(qv2, "bin", "ruff"), "w").write("#!/bin/sh\n")
os.chmod(os.path.join(qv2, "bin", "ruff"), 0o755)
ok("MUTANT (no live re-probe) is caught: it reports a present tool as missing", qm.tool_unavailable("ruff") == "missing" and qc.tool_unavailable("ruff") == "")
mc = mutant_copy("K2H", "qa_common.py", '"OVN_QA_TOOL_HEALTH_MAX_AGE_S", "7200"', '"OVN_QA_TOOL_HEALTH_MAX_AGE_S", "172800"')
qm = load(os.path.join(mc, "qa_common.py"), "qa_common_k2_mut2")
shutil.rmtree(qv2)
write_health({"ruff": {"status": "missing"}}, ts=time.time() - 40 * 3600)
ok("MUTANT (48h default max age) is caught: it trusts the 40h-old report", qm.tool_unavailable("ruff") == "missing" and qc.tool_unavailable("ruff") == "")
os.unlink(hp)

# ------------------------------------------------------------------------------------------------ (c) PRE-mutation line scope (review defect 2): pure, needs no mutmut
sp = load(os.path.join(QA, "spikes", "mutation_spike.py"), "mutation_spike_k2_pragma")
SRC = ('def f(x):\n    """doc"""\n    a = x + 1\n    b = a * 2\n    c = (a +\n         b)\n    if a > 3:\n        b = b - 1\n    return b + c\n')
pf = os.path.join(T, "pragma_target.py")
open(pf, "w").write(SRC)
n = sp.pragma_scope(pf, [(1, 9)], [(4, 4)])      # only line 4 (`b = a * 2`) is in the range
out = open(pf).read().split("\n")
ok("pragma scope: unchanged single-line statements are marked no-mutate (lines 3, 8, 9)", all(out[i - 1].endswith("# pragma: no mutate") for i in (3, 8, 9)) and n == 3, (n, out))
ok("pragma scope: the changed line, the def line, the docstring, multi-line statement and the `if` header are untouched",
   not any("pragma" in out[i - 1] for i in (1, 2, 4, 5, 6, 7)), out)
ok("pragma scope: line numbers do not move and the file still parses", len(out) == len(SRC.split("\n")) and compile(open(pf).read(), pf, "exec") is not None)
open(pf, "w").write(SRC)
ok("pragma scope: a function outside fn_spans is untouched", sp.pragma_scope(pf, [(100, 120)], [(4, 4)]) == 0 and open(pf).read() == SRC)
ok("pragma scope: idempotent (re-run marks nothing new)", (sp.pragma_scope(pf, [(1, 9)], [(4, 4)]), sp.pragma_scope(pf, [(1, 9)], [(4, 4)]))[1] == 0)
mc = mutant_copy("K2I", "spikes/mutation_spike.py", "if any(x <= a <= y for x, y in hs):", "if False:")
spm = load(os.path.join(mc, "spikes", "mutation_spike.py"), "mutation_spike_k2_pragma_mut")
open(pf, "w").write(SRC)
ok("MUTANT (changed lines also marked) is caught: it would hide the changed line from mutmut", spm.pragma_scope(pf, [(1, 9)], [(4, 4)]) > 3 and "pragma" in open(pf).read().split("\n")[3])
ok("gate wires it: the spike calls pragma_scope on the worktree copy before mutmut runs (env OVN_MUT_PRAGMA_SCOPE=0 disables)",
   "pragma_scope(os.path.join(sdir, rel), spans, line_hunks[rel])" in open(os.path.join(QA, "spikes", "mutation_spike.py")).read() and "OVN_MUT_PRAGMA_SCOPE" in open(os.path.join(QA, "spikes", "mutation_spike.py")).read())

shutil.rmtree(T, ignore_errors=True)
print("%d passed, %d failed, %d skipped" % (P, F, S))
sys.exit(1 if F else 0)
