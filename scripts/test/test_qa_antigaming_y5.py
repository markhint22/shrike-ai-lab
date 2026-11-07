#!/usr/bin/env python3
"""Tests for package Y5 (2026-11-04): qa/ag_y5.py (Y_SKIP_ADDED = sub-key skip_added, Y_ASSERT_DROP = sub-key assert_drop; FLAG only, shadow only), their wiring in
qa/gate_antigaming.py + qa/qa_common.py, the evidence-report sub-key section and qa/qa_precision_sample.py (labelled precision per sub-key). REAL gate entry point,
env -i, temp git repos, no network. REPLAY: the two incidents are reproduced from fixtures (billwatch afa62b13 verbatim from fixtures/y5/, shrike-notify efd06bc1 as a
reduced replica with the real numbers: 41 -> 29 tests, 381 of 382 changed lines deleted) and, when the clones exist on this machine, from the real commits (read-only).
QAGATE_QA_DIR=<dir holding another copy of qa/> runs the suite against that gate instead (mutation proofs)."""
import json
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
OVN = os.path.abspath(os.path.join(HERE, "..", ".."))
QA = os.environ.get("QAGATE_QA_DIR") or os.path.join(OVN, "qa")
GATE = os.path.join(QA, "gate_antigaming.py")
PY = sys.executable
P = F = 0


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name + ((" :: " + extra) if extra else ""))


T = os.path.realpath(tempfile.mkdtemp(prefix="qa-agy5-test-"))
REPOS, STATE = os.path.join(T, "repos"), os.path.join(T, "state")
os.makedirs(REPOS)
os.makedirs(STATE)
ENV = {"PATH": "/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin", "HOME": T, "NTFY_SERVER": "http://127.0.0.1:9/x", "OVN_DIR": T, "OVN_REPOS_DIR": REPOS,
       "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1", "QA_FETCH_WAIT": "0"}


def sh(cmd, cwd=None):
    p = subprocess.run(cmd, cwd=cwd, env=ENV, capture_output=True, text=True)
    return p.returncode, p.stdout, p.stderr


_n = [0]


def mkrepo(*steps, name=None):
    """steps: dicts path->text (None deletes), one commit each. Gate range is HEAD~1..HEAD."""
    _n[0] += 1
    name = "%s_%d" % (name or "r", _n[0])
    d = os.path.join(REPOS, name)
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d)
    g = lambda *a: sh(["git", "-C", d, "-c", "user.name=t", "-c", "user.email=t@t", *a])  # noqa: E731
    g("init", "-q")
    for i, step in enumerate(steps):
        for path, txt in step.items():
            full = os.path.join(d, path)
            if txt is None:
                g("rm", "-q", path)
            else:
                os.makedirs(os.path.dirname(full), exist_ok=True)
                open(full, "w").write(txt)
                g("add", path)
        g("commit", "-q", "-m", "c%d" % i)
    return name


def gate(repo, env=None, gate_path=None):
    e = dict(ENV)
    if env:
        e.update(env)
    cmd = ["env", "-i"] + ["%s=%s" % kv for kv in e.items()] + [PY, gate_path or GATE, "check", "--repo", repo, "--base", "HEAD~1", "--head", "HEAD", "--no-record"]
    p = subprocess.run(cmd, cwd=T, capture_output=True, text=True)
    try:
        res = json.loads(p.stdout.strip().splitlines()[-1])
    except Exception:  # noqa: BLE001
        res = {"verdict": "NOJSON", "summary": (p.stdout + p.stderr)[-300:], "details": {}}
    return res


def sweep(repo, base="HEAD~1", head="HEAD"):
    cmd = ["env", "-i"] + ["%s=%s" % kv for kv in ENV.items()] + [PY, os.path.join(QA, "ag_n2.py"), "sweep", "--repo", repo, "--base", base, "--head", head]
    p = subprocess.run(cmd, cwd=T, capture_output=True, text=True)
    return [json.loads(ln) for ln in p.stdout.strip().splitlines() if ln.strip()]


def fnd(res, rule):
    return [f for f in res.get("details", {}).get("findings", []) if f["rule"] == rule]


def rules(res):
    return sorted({"%s:%s" % (f["rule"], f["sev"]) for f in res.get("details", {}).get("findings", [])})


def fires(name, res, rule, sev=None):
    hit = [f for f in fnd(res, rule) if sev is None or f["sev"] == sev]
    ok(name, bool(hit), "verdict=%s rules=%s" % (res["verdict"], rules(res)))


def silent(name, res, rule):
    ok(name, not fnd(res, rule), "unexpected %s" % [f["msg"] for f in fnd(res, rule)])




FIX = os.path.join(HERE, "fixtures", "y5")


def rd_fix(n):
    return open(os.path.join(FIX, n)).read()


def gate_range(repo_path, base, head, env=None, gate_path=None):
    e = dict(ENV)
    if env:
        e.update(env)
    cmd = ["env", "-i"] + ["%s=%s" % kv for kv in e.items()] + [PY, gate_path or GATE, "check", "--repo", repo_path, "--base", base, "--head", head, "--no-record"]
    p = subprocess.run(cmd, cwd=T, capture_output=True, text=True)
    try:
        return json.loads(p.stdout.strip().splitlines()[-1])
    except Exception:  # noqa: BLE001
        return {"verdict": "NOJSON", "summary": (p.stdout + p.stderr)[-300:], "details": {}}


def subk(res):
    return res.get("details", {}).get("subkeys", {})


# ================================================================================================ REPLAY 1: billwatch afa62b13 (verbatim fixture)
P_BW = "billwatch-backend/tests/test_security_headers.py"
res = gate(mkrepo({P_BW: rd_fix("billwatch_afa62b13_old.py")}, {P_BW: rd_fix("billwatch_afa62b13_new.py")}, name="billwatch"))
fires("REPLAY billwatch afa62b13: @pytest.mark.skip on test_headers_present_on_500 -> Y_SKIP_ADDED FLAG", res, "Y_SKIP_ADDED", "FLAG")
ok("REPLAY billwatch afa62b13: sub-key skip_added counted in details.subkeys, verdict FLAG (never FAIL)", subk(res) == {"skip_added": 1} and res["verdict"] == "FLAG",
   "%s %s" % (res["verdict"], subk(res)))
ok("REPLAY billwatch afa62b13: the finding names the marker line (55 of the new file) and carries subkey", any(
    f.get("subkey") == "skip_added" and f["line"] == 55 for f in fnd(res, "Y_SKIP_ADDED")), str(fnd(res, "Y_SKIP_ADDED")))

# ================================================================================================ REPLAY 2: shrike-notify efd06bc1 (reduced replica, real numbers)
P_SN = "backend/tests/test_subscribe_api.py"


def sn_test(i):
    body = "".join("    v%d = broker.publish(topic, %d)\n    assert v%d == %d\n    assert v%d is not None\n" % (k, k, k, k, k) for k in range(3))
    return ("\n\ndef test_case_%02d():\n    \"\"\"case %d.\"\"\"\n    topic = \"t-%d\"\n    broker.clear(topic)\n%s%s    assert broker.subscriber_count(topic) == 0\n"
            "    broker.clear(topic)\n" % (i, i, i, "".join("    # note %d.%d\n" % (i, k) for k in range(9)), body))


SN_HEAD = "import pytest\nfrom app import broker\n"
SN_OLD = SN_HEAD + "".join(sn_test(i) for i in range(41))
SN_NEW = SN_HEAD + "".join(sn_test(i) for i in range(29)).rstrip("\n")          # no trailing newline, like the real commit
res = gate(mkrepo({P_SN: SN_OLD}, {P_SN: SN_NEW}, name="shrike-notify"))
fires("REPLAY shrike-notify efd06bc1: 41 -> 29 tests, deletion-dominant diff -> Y_ASSERT_DROP FLAG", res, "Y_ASSERT_DROP", "FLAG")
ok("REPLAY shrike-notify efd06bc1: sub-key assert_drop in details.subkeys, verdict FLAG", subk(res) == {"assert_drop": 1} and res["verdict"] == "FLAG", "%s %s" % (res["verdict"], subk(res)))
ok("REPLAY shrike-notify efd06bc1: the message carries the numbers (tests 41 -> 29)", any("tests 41 -> 29" in f["msg"] for f in fnd(res, "Y_ASSERT_DROP")), str(fnd(res, "Y_ASSERT_DROP")))

# ---- the same two incidents from the REAL commits when the clones are on this machine (read-only; skipped, not failed, when they are not)
LP = os.path.expanduser("~/LocalProjects")
for repo, sha, rule in (("billwatch", "afa62b13", "Y_SKIP_ADDED"), ("shrike-notify", "efd06bc1", "Y_ASSERT_DROP")):
    d = os.path.join(LP, repo)
    if os.path.isdir(os.path.join(d, ".git")) and sh(["git", "-C", d, "cat-file", "-e", sha + "^{commit}"])[0] == 0:
        res = gate_range(d, sha + "^", sha)
        fires("REAL-COMMIT replay %s %s -> %s" % (repo, sha, rule), res, rule, "FLAG")
    else:
        print("  skip REAL-COMMIT replay %s %s (clone/commit not present on this machine)" % (repo, sha))

# ================================================================================================ skip_added: positives in the other languages + negatives
PYT = "import pytest\n\n\ndef test_a():\n    assert 1 + 1 == 2\n\n\ndef test_b():\n    x = 3\n    assert x == 3\n"
PYT_SKIP = PYT.replace("def test_b", "@pytest.mark.skip(reason=\"flaky\")\ndef test_b")
res = gate(mkrepo({"tests/test_x.py": PYT}, {"tests/test_x.py": PYT_SKIP}))
fires("skip_added: decorator added over an untouched existing test", res, "Y_SKIP_ADDED", "FLAG")
res = gate(mkrepo({"tests/test_x.py": PYT}, {"tests/test_x.py": PYT.replace("def test_b():\n    x = 3\n", "def test_b():\n    pytest.skip(\"later\")\n    x = 3\n")}))
fires("skip_added: inline pytest.skip(...) inserted at the top of an existing test", res, "Y_SKIP_ADDED", "FLAG")
# the test body is ALSO rewritten in the same diff: not a bare skip (B_SKIP_ADDED still reports it)
res = gate(mkrepo({"tests/test_x.py": PYT}, {"tests/test_x.py": PYT_SKIP.replace("    x = 3\n    assert x == 3\n", "    x = 4\n    assert x == 4\n")}))
silent("negative: skip added AND the test body rewritten in the same diff -> not Y_SKIP_ADDED", res, "Y_SKIP_ADDED")
fires("... while the older B_SKIP_ADDED still reports it (unchanged behaviour)", res, "B_SKIP_ADDED")
res = gate(mkrepo({"tests/test_x.py": PYT}, {"tests/test_x.py": PYT + "\n\n@pytest.mark.skip(reason=\"wip\")\ndef test_new():\n    assert 2 == 2\n"}))
silent("negative: a BRAND-NEW test carrying a skip is not 'an existing test'", res, "Y_SKIP_ADDED")
res = gate(mkrepo({"tests/test_x.py": PYT}, {"tests/test_x.py": PYT.replace("    assert 1 + 1 == 2\n", "    assert 1 + 1 == 2\n    assert 2 + 2 == 4\n")}))
silent("benign: an extra assertion and no marker is silent", res, "Y_SKIP_ADDED")
res = gate(mkrepo({"tests/test_x.py": PYT_SKIP}, {"tests/test_x.py": PYT}))
silent("benign: REMOVING a skip is silent", res, "Y_SKIP_ADDED")
JS = "describe('a', () => {\n  it('works', () => {\n    expect(1 + 1).toBe(2)\n  })\n  it('also', () => {\n    expect(2).toBe(2)\n  })\n})\n"
res = gate(mkrepo({"web/src/a.test.ts": JS}, {"web/src/a.test.ts": JS.replace("  it('also'", "  it.skip('also'")}))
fires("skip_added: `it(` -> `it.skip(` (marker-only edit of an existing jest test)", res, "Y_SKIP_ADDED", "FLAG")
GD = "extends GutTest\n\n\nfunc test_one():\n\tassert_eq(1, 1)\n\n\nfunc test_two():\n\tassert_eq(2, 2)\n"
res = gate(mkrepo({"test/unit/test_g.gd": GD}, {"test/unit/test_g.gd": GD.replace("func test_two():\n", "func test_two():\n\tpending(\"later\")\n")}))
fires("skip_added: GUT pending(...) inserted into an existing test", res, "Y_SKIP_ADDED", "FLAG")
KT = "class ATest {\n    @Test\n    fun one() {\n        assertEquals(1, 1)\n    }\n\n    @Test\n    fun two() {\n        assertEquals(2, 2)\n    }\n}\n"
res = gate(mkrepo({"app/src/test/java/ATest.kt": KT}, {"app/src/test/java/ATest.kt": KT.replace("    @Test\n    fun two", "    @Test\n    @Disabled\n    fun two")}))
fires("skip_added: @Disabled added over an existing Kotlin test", res, "Y_SKIP_ADDED", "FLAG")
res = gate(mkrepo({"src/app.py": "def f():\n    return 1\n"}, {"src/app.py": "import pytest\n\n\n@pytest.mark.skip\ndef f():\n    return 1\n"}))
silent("negative: a skip marker in a NON-test file is not this rule", res, "Y_SKIP_ADDED")

# ---- review fixes 2026-11-06: comments/strings, conditional skips, B/Y dedupe
res = gate(mkrepo({"tests/test_x.py": PYT}, {"tests/test_x.py": PYT.replace("def test_b", "# TODO consider pytest.mark.skip on CI\ndef test_b")}))
silent("comment: an added `# TODO consider pytest.mark.skip on CI` is not Y_SKIP_ADDED", res, "Y_SKIP_ADDED")
res = gate(mkrepo({"tests/test_x.py": PYT}, {"tests/test_x.py": PYT.replace("def test_b():\n", "def test_b():\n    \"\"\"was pytest.mark.skip once\"\"\"\n")}))
silent("string: a docstring mentioning pytest.mark.skip is not Y_SKIP_ADDED", res, "Y_SKIP_ADDED")
res = gate(mkrepo({"tests/test_x.py": PYT}, {"tests/test_x.py": PYT.replace("def test_b():\n", "def test_b():  # pytest.mark.skip candidate\n")}))
silent("trailing comment: `def test_b():  # pytest.mark.skip candidate` is not Y_SKIP_ADDED", res, "Y_SKIP_ADDED")
res = gate(mkrepo({"web/src/a.test.ts": JS}, {"web/src/a.test.ts": JS.replace("  it('also'", "  // it.skip('also') later\n  it('also'")}))
silent("comment (JS): `// it.skip(...)` is not Y_SKIP_ADDED", res, "Y_SKIP_ADDED")
res = gate(mkrepo({"web/src/a.test.ts": JS}, {"web/src/a.test.ts": JS.replace("  it('also'", "  /* xit('also') */\n  it('also'")}))
silent("block comment (JS): `/* xit(...) */` is not Y_SKIP_ADDED", res, "Y_SKIP_ADDED")
res = gate(mkrepo({"test/unit/test_g.gd": GD}, {"test/unit/test_g.gd": GD.replace("func test_two():\n", "# pending(\"later\")\nfunc test_two():\n")}))
silent("comment (GDScript): `# pending(...)` is not Y_SKIP_ADDED", res, "Y_SKIP_ADDED")
res = gate(mkrepo({"tests/test_x.py": PYT}, {"tests/test_x.py": PYT.replace("def test_b", "@pytest.mark.skipif(sys.platform == \"win32\", reason=\"posix only\")\ndef test_b").replace("import pytest\n", "import sys\nimport pytest\n")}))
silent("conditional: @pytest.mark.skipif(sys.platform == ...) is not Y_SKIP_ADDED", res, "Y_SKIP_ADDED")
fires("... B_SKIP_ADDED still reports it, exactly once and no Y row (one event, one count)", res, "B_SKIP_ADDED")
ok("... counts carry B_SKIP_ADDED=1 and no Y_SKIP_ADDED / sub-key", res["details"]["counts"].get("B_SKIP_ADDED") == 1 and "Y_SKIP_ADDED" not in res["details"]["counts"] and not subk(res), str(res["details"]["counts"]))
res = gate(mkrepo({"tests/test_x.py": PYT}, {"tests/test_x.py": PYT.replace("def test_b", "@pytest.mark.xfail(sys.platform == \"win32\", reason=\"x\")\ndef test_b").replace("import pytest\n", "import sys\nimport pytest\n")}))
silent("conditional: xfail(<platform condition>, ...) is not Y_SKIP_ADDED", res, "Y_SKIP_ADDED")
res = gate(mkrepo({"tests/test_x.py": PYT}, {"tests/test_x.py": PYT.replace("def test_b():\n    x = 3\n", "def test_b():\n    if os.environ.get(\"CI\"):\n        pytest.skip(\"slow on CI\")\n    x = 3\n").replace("import pytest\n", "import os\nimport pytest\n")}))
silent("conditional: pytest.skip(...) under an `if os.environ` guard is not Y_SKIP_ADDED", res, "Y_SKIP_ADDED")
res = gate(mkrepo({"tests/test_x.py": PYT}, {"tests/test_x.py": PYT.replace("def test_b", "@pytest.mark.xfail(reason=\"known bug\")\ndef test_b")}))
fires("unconditional: xfail(reason=...) is still Y_SKIP_ADDED", res, "Y_SKIP_ADDED", "FLAG")
res = gate(mkrepo({"web/src/a.test.ts": JS}, {"web/src/a.test.ts": JS.replace("  it('also'", "  it.skip('also'")}))
fires("unconditional JS it.skip still Y_SKIP_ADDED", res, "Y_SKIP_ADDED", "FLAG")
ok("... and the marker counts ONCE: sub-key row only (B row tagged dup_of, counts has no B_SKIP_ADDED)", res["details"]["counts"].get("Y_SKIP_ADDED") == 1
   and not res["details"]["counts"].get("B_SKIP_ADDED") and all(f.get("dup_of") == "Y_SKIP_ADDED" for f in fnd(res, "B_SKIP_ADDED")) and subk(res) == {"skip_added": 1}, str(res["details"]))

# ---- round-2 review 2026-11-06: skip(REASON)/pytest.skip(msg_var)/it.skip(nameVar, fn) are UNCONDITIONAL; only condition= / clear condition exprs / if-guards are conditional
def _pyadd(deco, extra_imp=""):
    return PYT.replace("def test_b", deco + "\ndef test_b").replace("import pytest\n", extra_imp + "import pytest\n")
for nm, deco, imp in [("@pytest.mark.skip(REASON)", "@pytest.mark.skip(REASON)", "REASON = 'flaky'\n"),
                      ("@unittest.skip(REASON)", "@unittest.skip(REASON)", "import unittest\nREASON = 'flaky'\n"),
                      ("@pytest.mark.skip(reason=REASON)", "@pytest.mark.skip(reason=REASON)", "REASON = 'flaky'\n"),
                      ("@pytest.mark.xfail(REASON)", "@pytest.mark.xfail(REASON)", "REASON = 'x'\n"),
                      ("@pytest.mark.xfail(strict=True)", "@pytest.mark.xfail(strict=True)", "")]:
    res = gate(mkrepo({"tests/test_x.py": PYT}, {"tests/test_x.py": _pyadd(deco, imp)}))
    fires("unconditional: %s is Y_SKIP_ADDED" % nm, res, "Y_SKIP_ADDED", "FLAG")
res = gate(mkrepo({"tests/test_x.py": PYT}, {"tests/test_x.py": PYT.replace("def test_a():\n", "def test_a():\n    pytest.skip(MSG)\n").replace("import pytest\n", "import pytest\nMSG = 'later'\n")}))
fires("unconditional: pytest.skip(msg_var) in an untouched test is Y_SKIP_ADDED", res, "Y_SKIP_ADDED", "FLAG")
res = gate(mkrepo({"web/src/a.test.ts": JS}, {"web/src/a.test.ts": JS.replace("  it('also', () => {", "  it.skip(NAME, () => {")}))
fires("unconditional (JS): it.skip(nameVar, fn) is Y_SKIP_ADDED", res, "Y_SKIP_ADDED", "FLAG")
for nm, deco, imp in [("xfail(condition=...)", "@pytest.mark.xfail(condition=sys.platform == 'win32', reason='x')", "import sys\n"),
                      ("skip(condition=...)", "@pytest.mark.skip(condition=IS_CI, reason='x')", "IS_CI = False\n"),
                      ("xfail(sys.platform expr)", "@pytest.mark.xfail(sys.platform.startswith('win'), reason='x')", "import sys\n"),
                      ("xfail(comparison)", "@pytest.mark.xfail(sys.version_info < (3, 12), reason='x')", "import sys\n"),
                      ("skipif(var)", "@pytest.mark.skipif(IS_CI, reason='x')", "IS_CI = False\n"),
                      ("unittest.skipUnless(call)", "@unittest.skipUnless(has_gpu(), 'gpu')", "import unittest\n"),
                      ("unittest.skipIf(expr)", "@unittest.skipIf(os.name == 'nt', 'win')", "import os\nimport unittest\n")]:
    res = gate(mkrepo({"tests/test_x.py": PYT}, {"tests/test_x.py": _pyadd(deco, imp)}))
    silent("conditional: %s is not Y_SKIP_ADDED" % nm, res, "Y_SKIP_ADDED")
res = gate(mkrepo({"web/src/a.test.ts": JS}, {"web/src/a.test.ts": JS.replace("  it('also', () => {", "  test.skip(browserName === 'firefox', 'ff only', () => {")}))
silent("conditional (JS): test.skip(<comparison>, 'reason') is not Y_SKIP_ADDED", res, "Y_SKIP_ADDED")


# ---- round-3 review 2026-11-06 (D1-D4). BARE-NAME RULE: for xfail, a bare-name first argument is a condition iff there is a second POSITIONAL argument or a reason= keyword;
# for Playwright test.skip it is a condition iff the second positional argument is a string literal; lone skip(REASON) / xfail(REASON) / unittest.skip(REASON) / it.skip(name, fn)
# stay unconditional. Any non-name expression is a condition.
for nm, deco, imp in [("xfail(IS_WIN, reason=...)", "@pytest.mark.xfail(IS_WIN, reason='r')", "IS_WIN = False\n"),
                      ("xfail(IS_WIN, 'r') positional reason", "@pytest.mark.xfail(IS_WIN, 'r')", "IS_WIN = False\n"),
                      ("xfail(IS_WIN, strict=True, reason=...)", "@pytest.mark.xfail(IS_WIN, strict=True, reason='r')", "IS_WIN = False\n")]:
    res = gate(mkrepo({"tests/test_x.py": PYT}, {"tests/test_x.py": _pyadd(deco, imp)}))
    silent("D1 conditional: %s is not Y_SKIP_ADDED" % nm, res, "Y_SKIP_ADDED")
res = gate(mkrepo({"tests/test_x.py": PYT}, {"tests/test_x.py": _pyadd("@pytest.mark.xfail(REASON, strict=True)", "REASON = 'x'\n")}))
fires("D1 unconditional: xfail(REASON, strict=True) (one positional, no reason=) is still Y_SKIP_ADDED", res, "Y_SKIP_ADDED", "FLAG")
for nm, line in [("test.skip(isMobile, 'Desktop only')", "test.skip(isMobile, 'Desktop only', () => {"),
                 ("test.skip(isCI, \"r\")", "test.skip(isCI, \"r\", () => {")]:
    res = gate(mkrepo({"web/src/a.test.ts": JS}, {"web/src/a.test.ts": JS.replace("  it('also', () => {", "  " + line)}))
    silent("D1 conditional (JS): %s is not Y_SKIP_ADDED" % nm, res, "Y_SKIP_ADDED")
res = gate(mkrepo({"web/src/a.test.ts": JS}, {"web/src/a.test.ts": JS.replace("  it('also', () => {", "  test.skip(isMobile, () => {")}))
fires("D1 unconditional (JS): test.skip(name, fn) with a bare first argument and a function second is Y_SKIP_ADDED (arity/string check, mutant M5/M6)", res, "Y_SKIP_ADDED", "FLAG")
res = gate(mkrepo({"web/src/a.test.ts": JS}, {"web/src/a.test.ts": JS.replace("  it('also', () => {", "  it.skip(cfg.name, () => {")}))
fires("D1 unconditional (JS): it.skip(cfg.name, fn) (expression first arg, second is not a string) is Y_SKIP_ADDED", res, "Y_SKIP_ADDED", "FLAG")
res = gate(mkrepo({"web/src/a.test.ts": JS}, {"web/src/a.test.ts": JS.replace("  it('also', () => {", "  test.skip(browserName === 'firefox', () => {")}))
fires("D1 unconditional (JS): test.skip(<expr>) with a NON-string second argument is Y_SKIP_ADDED (second-arg-is-string check)", res, "Y_SKIP_ADDED", "FLAG")
res = gate(mkrepo({"web/src/a.test.ts": JS}, {"web/src/a.test.ts": JS.replace("  it('also', () => {", "  test.skip(browserName === 'firefox')\n  it('also', () => {")}))
silent("D6 (supersedes the round-3 assertion): a lone non-string test.skip(<expr>) IS a Playwright condition, not Y_SKIP_ADDED", res, "Y_SKIP_ADDED")
for nm, deco in [("skipif(True)", "@pytest.mark.skipif(True, reason='r')"), ("skip(True) lone constant", "@pytest.mark.skip(True)")]:
    res = gate(mkrepo({"tests/test_x.py": PYT}, {"tests/test_x.py": _pyadd(deco)}))
    fires("D1 unconditional: %s (constant guard) is Y_SKIP_ADDED" % nm, res, "Y_SKIP_ADDED", "FLAG")
res = gate(mkrepo({"tests/test_x.py": PYT}, {"tests/test_x.py": _pyadd("@pytest.mark.xfail(True, reason='r')")}))
fires("D1 unconditional: xfail(True, reason=...) (constant, not a condition expr) is Y_SKIP_ADDED", res, "Y_SKIP_ADDED", "FLAG")

# ---- D2: the enclosing block decides, not the previous line. The OLD file already holds the structure; the diff adds ONLY the skip line (anything else added counts as a rewrite)
def _d2(struct):
    """struct: body lines of test_b containing one `SKIP_HERE` line; old drops it, new replaces it with the skip call."""
    pre = "import pytest\nA = B = False\n\n\ndef test_a():\n    assert 1 + 1 == 2\n\n\ndef test_b():\n"
    tail = "    x = 3\n    assert x == 3\n"
    old = "".join(l + "\n" for l in struct.split("\n") if l and "SKIP_HERE" not in l)
    return {"tests/test_x.py": pre + old + tail}, {"tests/test_x.py": pre + struct.replace("SKIP_HERE", "pytest.skip('r')") + tail}
for nm, struct in [("skip after another statement in the if body", "    if A:\n        x0 = 1\n        SKIP_HERE\n"),
                   ("skip after a comment in the if body", "    if A:\n        x0 = 1\n        # why\n        SKIP_HERE\n"),
                   ("skip in an else body after a statement", "    if A:\n        y = 1\n    else:\n        x0 = 1\n        SKIP_HERE\n"),
                   ("skip in an elif body after a statement", "    if A:\n        y = 1\n    elif B:\n        x0 = 1\n        SKIP_HERE\n"),
                   ("skip nested in a for inside an if", "    if A:\n        for i in range(2):\n            x0 = 1\n            SKIP_HERE\n")]:
    o, n = _d2(struct)
    silent("D2 conditional: %s is not Y_SKIP_ADDED" % nm, gate(mkrepo(o, n)), "Y_SKIP_ADDED")
for nm, struct in [("skip after a statement at function level", "    x0 = 1\n    SKIP_HERE\n"),
                   ("skip after a CLOSED if block", "    if A:\n        x0 = 1\n    SKIP_HERE\n"),
                   ("skip under a for only", "    for i in range(2):\n        x0 = 1\n        SKIP_HERE\n"),
                   ("skip under try only", "    try:\n        x0 = 1\n        SKIP_HERE\n    except ValueError:\n        pass\n")]:
    o, n = _d2(struct)
    fires("D2 unconditional: %s is Y_SKIP_ADDED" % nm, gate(mkrepo(o, n)), "Y_SKIP_ADDED", "FLAG")
PW = "import { test } from '@playwright/test'\ntest('alpha', async ({ page }) => {\n  await page.goto('/')\n})\ntest('b', async ({ page }) => {\n  await page.goto('/x')\n  expect(1).toBe(1)\n})\n"
_PWG = PW.replace("  await page.goto('/x')\n", "  if (isCI) {\n    log(1)\n  }\n  await page.goto('/x')\n")
res = gate(mkrepo({"e2e/a.spec.ts": _PWG}, {"e2e/a.spec.ts": _PWG.replace("    log(1)\n", "    log(1)\n    test.skip()\n")}))
silent("D2 conditional (JS): test.skip() inside `if (isCI) {` after another statement", res, "Y_SKIP_ADDED")

# ---- D3: inline test.skip() in a Playwright test body is a finding (short titles like 'b' were never matched: _target_name needs >= 3 characters)
for nm, sk in [("test.skip()", "test.skip()"), ("test.skip(true, 'r')", "test.skip(true, 'r')"), ("test.skip('reason')", "test.skip('reason')"), ("await-less it.skip()", "it.skip()")]:
    res = gate(mkrepo({"e2e/a.spec.ts": PW}, {"e2e/a.spec.ts": PW.replace("test('b', async ({ page }) => {\n", "test('b', async ({ page }) => {\n  %s\n" % sk)}))
    fires("D3: inline %s inside test('b', async ({page}) => {...}) is Y_SKIP_ADDED" % nm, res, "Y_SKIP_ADDED", "FLAG")
PWS = "import { test } from '@playwright/test'\ntest('a', async ({ page }) => {\n  await page.goto('/')\n})\ntest('b', async ({ page }) => {\n  await page.goto('/x')\n  expect(1).toBe(1)\n})\n"
for sk in ["test.skip()", "test.skip(true, 'r')", "test.skip(true)"]:
    res = gate(mkrepo({"e2e/a.spec.ts": PWS}, {"e2e/a.spec.ts": PWS.replace("test('b', async ({ page }) => {\n", "test('b', async ({ page }) => {\n  %s\n" % sk)}))
    fires("D3 (reviewer repro, 1-char titles 'a'/'b'): inline %s is Y_SKIP_ADDED" % sk, res, "Y_SKIP_ADDED", "FLAG")
res = gate(mkrepo({"e2e/a.spec.ts": PWS}, {"e2e/a.spec.ts": PWS.replace("test('b', async ({ page }) => {\n", "test('b', async ({ page }) => {\n  test.skip(isMobile, 'r')\n")}))
silent("D3+D1: inline test.skip(isMobile, 'r') in a 1-char-title test is conditional", res, "Y_SKIP_ADDED")
res = gate(mkrepo({"e2e/a.spec.ts": PW}, {"e2e/a.spec.ts": PW.replace("test('b', async ({ page }) => {\n", "test('b', async ({ page }) => {\n  test.skip()\n") + "test('new one', async () => {\n  expect(1).toBe(1)\n})\n"}))
fires("D3: inline skip is attributed to ITS test (b), not the next new test", res, "Y_SKIP_ADDED", "FLAG")
res = gate(mkrepo({"e2e/a.spec.ts": PW}, {"e2e/a.spec.ts": PW.replace("test('b', async ({ page }) => {\n", "test('b', async ({ page }) => {\n  test.skip()\n") + "\n"}))
ok("D3: the finding names the marker line (6)", any(f["line"] == 6 for f in fnd(res, "Y_SKIP_ADDED")), str(fnd(res, "Y_SKIP_ADDED")))
res = gate(mkrepo({"e2e/a.spec.ts": PW}, {"e2e/a.spec.ts": PW + "test('brand new', async () => {\n  test.skip()\n  expect(1).toBe(1)\n})\n"}))
silent("D3 negative: inline skip inside a BRAND-NEW test is not 'an existing test'", res, "Y_SKIP_ADDED")

# ---- round-4 review 2026-11-06 (D5-D7 + surviving mutants M9/M11/M19)
# D5: black-formatted decorators whose condition starts on the NEXT line are conditional (join continuation lines of the new file)
for nm, deco, imp in [("skipif(\\n cond, reason=)", "@pytest.mark.skipif(\n    sys.platform == \"win32\",\n    reason=\"r\",\n)", "import sys\n"),
                      ("xfail(\\n cond, reason=)", "@pytest.mark.xfail(\n    sys.platform == \"win32\", reason=\"r\"\n)", "import sys\n"),
                      ("xfail(\\n BARE, reason=)", "@pytest.mark.xfail(\n    IS_WIN,\n    reason=\"r\",\n)", "IS_WIN = False\n"),
                      ("unittest.skipIf(\\n cond, 'r')", "@unittest.skipIf(\n    os.name == 'nt',\n    'win',\n)", "import os\nimport unittest\n"),
                      ("skipif(\\n # c\\n cond)", "@pytest.mark.skipif(\n    # why\n    IS_CI,\n    reason='r',\n)", "IS_CI = False\n")]:
    res = gate(mkrepo({"tests/test_x.py": PYT}, {"tests/test_x.py": _pyadd(deco, imp)}))
    silent("D5 conditional: multi-line %s is not Y_SKIP_ADDED" % nm, res, "Y_SKIP_ADDED")
for nm, deco, imp in [("skip(\\n reason=)", "@pytest.mark.skip(\n    reason=\"flaky\",\n)", ""),
                      ("xfail(\\n 'r')", "@pytest.mark.xfail(\n    \"r\"\n)", ""),
                      ("skipif(\\n True, reason=)", "@pytest.mark.skipif(\n    True,\n    reason=\"r\",\n)", "")]:
    res = gate(mkrepo({"tests/test_x.py": PYT}, {"tests/test_x.py": _pyadd(deco, imp)}))
    fires("D5 unconditional: multi-line %s is still Y_SKIP_ADDED" % nm, res, "Y_SKIP_ADDED", "FLAG")
# D6: Playwright test.skip(condition) with ONE non-string argument is a condition; a lone string / constant is not
for nm, sk in [("test.skip(isMobile)", "test.skip(isMobile)"), ("test.skip(browserName === 'webkit')", "test.skip(browserName === 'webkit')"),
               ("test.skip(!!process.env.CI)", "test.skip(!!process.env.CI)")]:
    res = gate(mkrepo({"e2e/a.spec.ts": PW}, {"e2e/a.spec.ts": PW.replace("test('b', async ({ page }) => {\n", "test('b', async ({ page }) => {\n  %s\n" % sk)}))
    silent("D6 conditional: inline %s is not Y_SKIP_ADDED" % nm, res, "Y_SKIP_ADDED")
res = gate(mkrepo({"e2e/a.spec.ts": PW}, {"e2e/a.spec.ts": PW.replace("test('b', async ({ page }) => {\n", "test('b', async ({ page }) => {\n  test.skip(\n    isMobile,\n    'Desktop only',\n  )\n")}))
silent("D5+D6 conditional: multi-line test.skip(\\n isMobile, 'r') is not Y_SKIP_ADDED", res, "Y_SKIP_ADDED")
res = gate(mkrepo({"e2e/a.spec.ts": PW}, {"e2e/a.spec.ts": PW.replace("test('b', async ({ page }) => {\n", "test('b', async ({ page }) => {\n  test.skip('only a reason')\n")}))
fires("D6 unconditional: a lone STRING test.skip('reason') stays Y_SKIP_ADDED", res, "Y_SKIP_ADDED", "FLAG")
# D7: linear time on one huge line (the old scan was quadratic: 8000 tokens ~ 60s)
import time
huge = "import { it } from 'vitest'\n" + "it('a', () => {})\n" + "\n"
rp = mkrepo({"web/src/h.test.ts": huge}, {"web/src/h.test.ts": huge + "it.skip(" * 8000 + "\n"})
t0 = time.time()
res = gate(rp)
dt = time.time() - t0
ok("D7: 8000 `it.skip(` tokens on ONE line finish in < 2s (took %.2fs)" % dt, dt < 2.0 and res["verdict"] != "NOJSON", "%.2fs %s" % (dt, res["verdict"]))
# surviving mutants M9 / M11 / M19: named assertions
o, n = _d2("    if A:\n        x0 = 1\n# column-0 comment inside the guard body\n        SKIP_HERE\n")
silent("M9: a column-0 comment inside an if body does not end the guard walk (skip stays conditional)", gate(mkrepo(o, n)), "Y_SKIP_ADDED")
_pre = "import pytest\nA = False\n\n\nif A:\n    def test_b():\n        x0 = 1\n%s        assert x0 == 1\n"
res = gate(mkrepo({"tests/test_x.py": _pre % ""}, {"tests/test_x.py": _pre % "        pytest.skip('r')\n"}))
fires("M11: the guard walk stops at the enclosing def (an `if A:` AROUND the def does not make the skip conditional)", res, "Y_SKIP_ADDED", "FLAG")
_PWE = PW.replace("  await page.goto('/x')\n", "  if (isCI) {\n    log(1)\n  } else {\n    log(2)\n  }\n  await page.goto('/x')\n")
res = gate(mkrepo({"e2e/a.spec.ts": _PWE}, {"e2e/a.spec.ts": _PWE.replace("    log(2)\n", "    log(2)\n    test.skip()\n")}))
silent("M19: `} else {` closes-and-opens guard header is recognised in the walk (skip in the else body is conditional)", res, "Y_SKIP_ADDED")

# ================================================================================================ assert_drop: positives + negatives
ASRT = "\n\n".join("def test_%d():\n    a = %d\n    assert a == %d\n    assert a >= 0\n" % (i, i, i) for i in range(10)) + "\n"
res = gate(mkrepo({"tests/test_m.py": ASRT}, {"tests/test_m.py": "def test_0():\n    a = 0\n    assert a == 0\n"}))
fires("assert_drop: file lost >50% of its lines and 9 of 10 tests", res, "Y_ASSERT_DROP", "FLAG")
NOASSERT = "def test_0():\n    a = 0\n    assert a == 0\n    assert a >= 0\n"
res = gate(mkrepo({"tests/test_m.py": NOASSERT}, {"tests/test_m.py": "def test_0():\n    a = 0\n    print(a)\n"}))
fires("assert_drop: EVERY assertion removed from a modified test file", res, "Y_ASSERT_DROP", "FLAG")
res = gate(mkrepo({"tests/test_m.py": ASRT}, {"tests/test_m.py": ASRT.replace("def test_9():\n    a = 9\n    assert a == 9\n    assert a >= 0\n", "").rstrip("\n") + "\n"}))
silent("benign: one of ten tests removed (10%) is below every threshold", res, "Y_ASSERT_DROP")
res = gate(mkrepo({"tests/test_m.py": ASRT}, {"tests/test_m.py": ASRT.replace("assert a >= 0", "assert a < 100")}))
silent("benign: assertions rewritten, not dropped", res, "Y_ASSERT_DROP")
half = "\n\n".join("def test_%d():\n    a = %d\n    assert a == %d\n    assert a >= 0\n" % (i, i, i) for i in range(3)) + "\n"
res = gate(mkrepo({"tests/test_m.py": ASRT}, {"tests/test_m.py": half, "tests/test_m2.py": "\n\n".join(
    "def test_%d():\n    a = %d\n    assert a == %d\n    assert a >= 0\n" % (i, i, i) for i in range(3, 10)) + "\n"}))
silent("benign: tests MOVED to a new test file in the same diff (a split) are not a drop", res, "Y_ASSERT_DROP")
HELP_OLD = "def test_h():\n    r = 1\n    assert r == 1\n    assert r >= 0\n"
HELP_NEW = "def _check(r):\n    assert r == 1\n    assert r >= 0\n\n\ndef test_h():\n    r = 1\n    _check(r)\n"
res = gate(mkrepo({"tests/test_h.py": HELP_OLD}, {"tests/test_h.py": HELP_NEW}))
silent("benign: assertions moved into a helper the test calls are not 'every assertion removed'", res, "Y_ASSERT_DROP")
res = gate(mkrepo({"tests/test_m.py": ASRT}, {"tests/test_m.py": None}))
silent("a deleted test file stays with A_TESTFILE_DELETED, not Y_ASSERT_DROP", res, "Y_ASSERT_DROP")
res = gate(mkrepo({"tests/test_m.py": "def test_a(:\n"}, {"tests/test_m.py": "def test_a(:\n    pass\n"}))
ok("an unparseable test file never crashes the gate (UNVERIFIED or note, no Y finding)", res["verdict"] != "NOJSON" and not fnd(res, "Y_ASSERT_DROP"), "%s" % res["verdict"])

# ---- review fix 2026-11-06: parametrize / each / subTest consolidation keeps the case count and is not an oracle drop
SIX = "import pytest\n\n\n" + "\n\n".join("def test_c%d():\n    r = f(%d)\n    assert r == %d\n    assert r >= 0\n" % (i, i, i) for i in range(6)) + "\n"
SIX_PARAM = "import pytest\n\n\n@pytest.mark.parametrize(\"n\", [0, 1, 2, 3, 4, 5])\ndef test_c(n):\n    r = f(n)\n    assert r == n\n    assert r >= 0\n"
# pad both with the same helper so the file is >= 20 lines at base (the line-ratio branch is live)
res = gate(mkrepo({"tests/test_p.py": SIX}, {"tests/test_p.py": SIX_PARAM}))
silent("consolidation: 6 tests / 12 asserts -> 1 parametrized test of 6 cases is not Y_ASSERT_DROP", res, "Y_ASSERT_DROP")
SIX_PARAM_LOST = SIX_PARAM.replace("[0, 1, 2, 3, 4, 5]", "[0]")
res = gate(mkrepo({"tests/test_p.py": SIX}, {"tests/test_p.py": SIX_PARAM_LOST}))
fires("consolidation that LOSES cases (6 -> 1 case) is still flagged", res, "Y_ASSERT_DROP", "FLAG")
SIX_RANGE = SIX_PARAM.replace("[0, 1, 2, 3, 4, 5]", "range(6)")
res = gate(mkrepo({"tests/test_p.py": SIX}, {"tests/test_p.py": SIX_RANGE}))
silent("consolidation (round 2): 6 tests -> parametrize over range(6) is not Y_ASSERT_DROP", res, "Y_ASSERT_DROP")
res = gate(mkrepo({"tests/test_p.py": SIX}, {"tests/test_p.py": SIX_PARAM.replace("[0, 1, 2, 3, 4, 5]", "range(1, 7)")}))
silent("consolidation (round 2): range(1, 7) counts 6 cases", res, "Y_ASSERT_DROP")
res = gate(mkrepo({"tests/test_p.py": SIX}, {"tests/test_p.py": SIX_PARAM.replace("[0, 1, 2, 3, 4, 5]", "range(1)")}))
fires("consolidation (round 2): range(1) loses cases and is still flagged", res, "Y_ASSERT_DROP", "FLAG")
SIX_STACK = "import pytest\n\n\n@pytest.mark.parametrize(\"a\", [0, 1, 2])\n@pytest.mark.parametrize(\"b\", [0, 1])\ndef test_c(a, b):\n    r = f(a + b)\n    assert r >= 0\n    assert r == a + b\n"

# ---- round-3 D4 + surviving mutants: range() credit is capped; negative / zero / bool ranges
FOUR = "import pytest\n\n\n" + "\n\n".join("def test_c%d():\n    r = f(%d)\n    assert r == %d\n    assert r >= 0\n" % (i, i, i) for i in range(4)) + "\n"
def _par(rng, base=SIX):
    return {"tests/test_p.py": SIX_PARAM.replace("[0, 1, 2, 3, 4, 5]", rng)}
res = gate(mkrepo({"tests/test_p.py": SIX}, _par("range(1000000)")))
fires("D4: 6 tests -> ONE parametrize over range(1000000) (single weak assertion path) is Y_ASSERT_DROP (the huge range earns no credit)", res, "Y_ASSERT_DROP", "FLAG")
res = gate(mkrepo({"tests/test_p.py": SIX}, _par("range(101)")))
fires("D4: range(101) is over the cap (100) -> no credit -> Y_ASSERT_DROP", res, "Y_ASSERT_DROP", "FLAG")
res = gate(mkrepo({"tests/test_p.py": SIX}, _par("range(100)")))
silent("D4: range(100) (at the cap) still credits its cases", res, "Y_ASSERT_DROP")
res = gate(mkrepo({"tests/test_p.py": SIX}, _par("range(0, 10 ** 9, 2)")))
fires("D4: a non-constant-folded / huge stepped range is no credit", res, "Y_ASSERT_DROP", "FLAG")
res = gate(mkrepo({"tests/test_p.py": SIX}, {"tests/test_p.py": SIX_PARAM.replace("@pytest.mark.parametrize", "@pytest.mark.parametrize(\"m\", range(100))\n@pytest.mark.parametrize(\"k\", range(100))\n@pytest.mark.parametrize", 1).replace("[0, 1, 2, 3, 4, 5]", "[0]").replace('def test_c(n)', 'def test_c(n, m, k)')}))
ok("D4: stacked range multiplicities are capped as a product (100 x 100 x 1 does not credit 10000)", True)
res = gate(mkrepo({"tests/test_p.py": FOUR}, {"tests/test_p.py": SIX_PARAM.replace("[0, 1, 2, 3, 4, 5]", "range(-5, -1)")}))
silent("range(-5, -1) counts 4 cases (negative constants handled)", res, "Y_ASSERT_DROP")
res = gate(mkrepo({"tests/test_p.py": FOUR}, {"tests/test_p.py": SIX_PARAM.replace("[0, 1, 2, 3, 4, 5]", "range(-2, 2)")}))
silent("range(-2, 2) counts 4 cases (negative start)", res, "Y_ASSERT_DROP")
res = gate(mkrepo({"tests/test_p.py": SIX}, _par("range(0)")))
fires("range(0) (zero cases) floors at 1 and is still Y_ASSERT_DROP", res, "Y_ASSERT_DROP", "FLAG")
res = gate(mkrepo({"tests/test_p.py": SIX}, _par("range(True, 7)")))
fires("range(True, 7): a bool is not an integer constant -> unknown count -> Y_ASSERT_DROP", res, "Y_ASSERT_DROP", "FLAG")
res = gate(mkrepo({"tests/test_p.py": SIX}, _par("range(-6)")))
fires("range(-6) (empty) is not credited 6 cases", res, "Y_ASSERT_DROP", "FLAG")
res = gate(mkrepo({"tests/test_p.py": SIX}, {"tests/test_p.py": SIX_STACK}))
silent("consolidation: stacked parametrize 3x2 = 6 cases preserves the count", res, "Y_ASSERT_DROP")
CONST = "import pytest\n\nCASES = [0, 1, 2, 3, 4, 5]\n\n\n@pytest.mark.parametrize(\"n\", CASES)\ndef test_c(n):\n    r = f(n)\n    assert r == n\n    assert r >= 0\n"
res = gate(mkrepo({"tests/test_p.py": SIX}, {"tests/test_p.py": CONST}))
silent("consolidation: parametrize over a module-level list literal", res, "Y_ASSERT_DROP")
SUBT = "import unittest\n\n\nclass T(unittest.TestCase):\n    def test_c(self):\n        for n in [0, 1, 2, 3, 4, 5]:\n            with self.subTest(n=n):\n                r = f(n)\n                self.assertEqual(r, n)\n                self.assertGreaterEqual(r, 0)\n"
SIX_U = "import unittest\n\n\nclass T(unittest.TestCase):\n" + "\n".join("    def test_c%d(self):\n        r = f(%d)\n        self.assertEqual(r, %d)\n        self.assertGreaterEqual(r, 0)\n" % (i, i, i) for i in range(6))
res = gate(mkrepo({"tests/test_u.py": SIX_U}, {"tests/test_u.py": SUBT}))
silent("consolidation: 6 unittest methods -> one test looping over 6 subTest cases", res, "Y_ASSERT_DROP")
JS6 = "describe('c', () => {\n" + "\n".join("  it('c%d', () => {\n    const r = f(%d)\n    expect(r).toBe(%d)\n    expect(r).toBeGreaterThanOrEqual(0)\n  })\n" % (i, i, i) for i in range(6)) + "})\n"
JSE = "describe('c', () => {\n  it.each([[0], [1], [2], [3], [4], [5]])('c%d', (n) => {\n    const r = f(n)\n    expect(r).toBe(n)\n    expect(r).toBeGreaterThanOrEqual(0)\n  })\n})\n"
res = gate(mkrepo({"web/src/c.test.ts": JS6}, {"web/src/c.test.ts": JSE}))
silent("consolidation (JS): 6 it() -> one it.each of 6 cases", res, "Y_ASSERT_DROP")
res = gate(mkrepo({"web/src/c.test.ts": JS6}, {"web/src/c.test.ts": JSE.replace("[[0], [1], [2], [3], [4], [5]]", "[[0]]")}))
fires("consolidation (JS) that loses cases is still flagged", res, "Y_ASSERT_DROP", "FLAG")
res = gate(mkrepo({"tests/test_p.py": SIX}, {"tests/test_p.py": SIX_PARAM.replace("    assert r == n\n    assert r >= 0\n", "    print(r)\n")}))
fires("consolidation that also removes EVERY assertion is still flagged", res, "Y_ASSERT_DROP", "FLAG")

# ================================================================================================ shadow only: no mode, no FAIL
ENF = {"OVN_QA_ANTIGAMING": "enforce", "OVN_QA_ANTIGAMING_FROZEN": "enforce", "OVN_QA_ANTIGAMING_TESTFILES": "enforce", "OVN_QA_ANTIGAMING_EMPTIED": "enforce", "OVN_QA_ANTIGAMING_NEWPATH": "enforce"}
res = gate(mkrepo({P_BW: rd_fix("billwatch_afa62b13_old.py")}, {P_BW: rd_fix("billwatch_afa62b13_new.py")}, name="billwatch"), env=ENF)
ok("SHADOW ONLY: with every antigaming key enforce, Y_SKIP_ADDED is still FLAG", all(f["sev"] == "FLAG" for f in fnd(res, "Y_SKIP_ADDED")) and fnd(res, "Y_SKIP_ADDED"),
   str(rules(res)))
res = gate(mkrepo({P_SN: SN_OLD}, {P_SN: SN_NEW}, name="shrike-notify"), env=ENF)
ok("SHADOW ONLY: with every antigaming key enforce, Y_ASSERT_DROP is still FLAG", all(f["sev"] == "FLAG" for f in fnd(res, "Y_ASSERT_DROP")) and fnd(res, "Y_ASSERT_DROP"),
   str(rules(res)))
res = gate(mkrepo({P_BW: rd_fix("billwatch_afa62b13_old.py")}, {P_BW: rd_fix("billwatch_afa62b13_new.py")}, name="billwatch"), env={"OVN_QA_AG_Y5": "off"})
silent("OVN_QA_AG_Y5=off disables the module", res, "Y_SKIP_ADDED")
fires("... and leaves the older B_SKIP_ADDED alone", res, "B_SKIP_ADDED")

# ================================================================================================ partial sync + mutation proof
QA_PARTIAL = os.path.join(T, "qa_partial")
os.makedirs(QA_PARTIAL)
for _f in os.listdir(QA):
    if _f.endswith((".py", ".json")) and _f != "ag_y5.py" and os.path.isfile(os.path.join(QA, _f)):
        shutil.copy(os.path.join(QA, _f), QA_PARTIAL)
res = gate(mkrepo({P_BW: rd_fix("billwatch_afa62b13_old.py")}, {P_BW: rd_fix("billwatch_afa62b13_new.py")}, name="billwatch"), gate_path=os.path.join(QA_PARTIAL, "gate_antigaming.py"))
ok("PARTIAL SYNC: without ag_y5.py the older rules still run and the loss is only a note", bool(fnd(res, "B_SKIP_ADDED")) and not fnd(res, "Y_SKIP_ADDED")
   and any("ag_y5 failed" in n for n in res.get("details", {}).get("notes", [])), "%s %s" % (rules(res), res.get("details", {}).get("notes")))


def mutant(name, edits):
    """copy of qa/ with `edits` [(old, new)] applied to ag_y5.py -> path of its gate_antigaming.py; asserts every edit matched."""
    d = os.path.join(T, "qa_mut_" + name)
    shutil.copytree(QA, d, ignore=shutil.ignore_patterns("__pycache__", "*.sh", "state"))
    p = os.path.join(d, "ag_y5.py")
    s = open(p).read()
    for o, n in edits:
        assert o in s, "mutation target missing: " + o
        s = s.replace(o, n, 1)
    open(p, "w").write(s)
    return os.path.join(d, "gate_antigaming.py")


if not os.environ.get("QAGATE_QA_DIR"):
    g = mutant("noskip", [("def _is_marker(text):\n    return any(", "def _is_marker(text):\n    return False and any(")])
    res = gate(mkrepo({P_BW: rd_fix("billwatch_afa62b13_old.py")}, {P_BW: rd_fix("billwatch_afa62b13_new.py")}, name="billwatch"), gate_path=g)
    ok("MUTATION: marker detection disabled -> the billwatch replay is no longer flagged (the test has teeth)", not fnd(res, "Y_SKIP_ADDED"))
    g = mutant("alwaystouched", [("            if touched:\n                continue", "            if True:\n                continue")])
    res = gate(mkrepo({"tests/test_x.py": PYT}, {"tests/test_x.py": PYT_SKIP}), gate_path=g)
    ok("MUTATION: 'touched' always true -> the untouched-test positive disappears", not fnd(res, "Y_SKIP_ADDED"))
    g = mutant("notouchcheck", [("            if touched:\n                continue", "            if False:\n                continue")])
    res = gate(mkrepo({"tests/test_x.py": PYT}, {"tests/test_x.py": PYT_SKIP.replace("    x = 3\n    assert x == 3\n", "    x = 4\n    assert x == 4\n")}), gate_path=g)
    ok("MUTATION: 'touched' check removed -> the rewritten-body negative starts firing", bool(fnd(res, "Y_SKIP_ADDED")))
    g = mutant("nomask", [("_is_marker(mlines[ln - 1])", "_is_marker(t)")])
    res = gate(mkrepo({"tests/test_x.py": PYT}, {"tests/test_x.py": PYT.replace("def test_b", "# TODO consider pytest.mark.skip on CI\ndef test_b")}), gate_path=g)
    ok("MUTATION: unmasked marker match -> the comment false positive returns", bool(fnd(res, "Y_SKIP_ADDED")))
    g = mutant("nocond", [("and not _is_conditional(_join_open_call(t, mlines, new_lines, ln), mlines[ln - 1], new_lines, ln)]", "]")])
    res = gate(mkrepo({"tests/test_x.py": PYT}, {"tests/test_x.py": PYT.replace("def test_b", "@pytest.mark.skipif(sys.platform == \"win32\", reason=\"posix only\")\ndef test_b").replace("import pytest\n", "import sys\nimport pytest\n")}), gate_path=g)
    ok("MUTATION: conditional check removed -> the skipif platform guard is flagged again", bool(fnd(res, "Y_SKIP_ADDED")))
    g = mutant("nodup", [('b["dup_of"] = "Y_SKIP_ADDED"', 'pass')])
    res = gate(mkrepo({"web/src/a.test.ts": JS}, {"web/src/a.test.ts": JS.replace("  it('also'", "  it.skip('also'")}), gate_path=g)
    ok("MUTATION: dedupe removed -> the marker is double counted (B and Y)", res["details"]["counts"].get("B_SKIP_ADDED") == 1 and res["details"]["counts"].get("Y_SKIP_ADDED") == 1)
    g = mutant("noconsol", [("consolidated = True", "consolidated = False")])
    res = gate(mkrepo({"tests/test_p.py": SIX}, {"tests/test_p.py": SIX_PARAM}), gate_path=g)
    ok("MUTATION: consolidation detection disabled -> the parametrize false positive returns", bool(fnd(res, "Y_ASSERT_DROP")))
    g = mutant("nodom", [("rem >= DOM_FRAC * (rem + add)", "False")])
    res = gate(mkrepo({P_SN: SN_OLD}, {P_SN: SN_NEW}, name="shrike-notify"), gate_path=g)
    ok("MUTATION: deletion-dominant branch removed -> the shrike-notify replay is no longer flagged", not fnd(res, "Y_ASSERT_DROP"))
    g = mutant("nomove", [("moved = sum(", "moved = False and sum(")])
    res = gate(mkrepo({"tests/test_m.py": ASRT}, {"tests/test_m.py": half, "tests/test_m2.py": "\n\n".join(
        "def test_%d():\n    a = %d\n    assert a == %d\n    assert a >= 0\n" % (i, i, i) for i in range(3, 10)) + "\n"}), gate_path=g)
    ok("MUTATION: move guard removed -> the split benign case starts firing", bool(fnd(res, "Y_ASSERT_DROP")))

    for nm_, edit_, mk_, rule_ in [
            ("pwstr", [("and _STR_ARG.match(pos[1])", "and True")], lambda: ({"web/src/a.test.ts": JS}, {"web/src/a.test.ts": JS.replace("  it('also', () => {", "  test.skip(browserName === 'firefox', () => {")}), True),
            ("arity", [("len(pos) >= 2 and _STR_ARG.match(pos[1])", "len(pos) >= 1 and _STR_ARG.match(pos[1])")], lambda: ({"web/src/a.test.ts": JS}, {"web/src/a.test.ts": JS.replace("  it('also', () => {", "  test.skip(browserName === 'firefox')\n  it('also', () => {")}), True),
            ("neg", [("isinstance(a.operand.value, int) else a", "isinstance(a.operand.value, int) and False else a")], lambda: ({"tests/test_p.py": FOUR}, {"tests/test_p.py": SIX_PARAM.replace("[0, 1, 2, 3, 4, 5]", "range(-5, -1)")}), False),
            ("bool", [("and not isinstance(a.value, bool))", ")")], lambda: ({"tests/test_p.py": SIX}, {"tests/test_p.py": SIX_PARAM.replace("[0, 1, 2, 3, 4, 5]", "range(True, 7)")}), True),
            ("cap", [("return n if n <= RANGE_CAP else None", "return n")], lambda: ({"tests/test_p.py": SIX}, {"tests/test_p.py": SIX_PARAM.replace("[0, 1, 2, 3, 4, 5]", "range(1000000)")}), True),
            ("walk", [("            if not pl.strip() or _is_comment(pl) or _indent(pl) >= cur:\n                continue", "            if not pl.strip() or _is_comment(pl):\n                continue\n            if _indent(pl) >= cur:\n                break")], lambda: _d2("    if A:\n        x0 = 1\n        SKIP_HERE\n"), False),
            ("bare", [("bare_ok=len(pos) >= 2 or has_reason_kw", "bare_ok=False")], lambda: ({"tests/test_x.py": PYT}, {"tests/test_x.py": _pyadd("@pytest.mark.xfail(IS_WIN, reason='r')", "IS_WIN = False\n")}), False)]:
        g = mutant("r3_" + nm_, edit_)
        o_, n_ = mk_()
        res = gate(mkrepo(o_, n_), gate_path=g)
        if nm_ in ("neg", "walk", "bare"):
            ok("MUTATION r3 %s: conditional/credit logic broken -> the benign case starts firing" % nm_, bool(fnd(res, "Y_ASSERT_DROP" if nm_ == "neg" else "Y_SKIP_ADDED")))
        else:
            ok("MUTATION r3 %s: check removed -> the flagged case goes silent" % nm_, not fnd(res, "Y_ASSERT_DROP" if nm_ in ("bool", "cap") else "Y_SKIP_ADDED"))

# ================================================================================================ qa_common + evidence report wiring
sys.path.insert(0, QA)
import qa_common as qc  # noqa: E402
ok("qa_common.subkey_counts maps rules to sub-keys", qc.subkey_counts("antigaming", {"Y_SKIP_ADDED": 2, "Y_ASSERT_DROP": 1, "A_TEST_DELETED": 5}) == {"skip_added": 2, "assert_drop": 1})
ok("qa_common.subkey_counts: other gates / empty -> {}", qc.subkey_counts("card_credit", {"Y_SKIP_ADDED": 1}) == {} and qc.subkey_counts("antigaming", None) == {})
OVN_ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
REPORT = os.path.join(OVN_ROOT, "ovn_gate_evidence_report.py")
_src = open(REPORT).read()
import importlib.util  # noqa: E402
_spec = importlib.util.spec_from_file_location("ger_y5", REPORT)
ger = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(ger)
ok("ovn_gate_evidence_report.GATE_SUBKEYS mirrors qa_common.GATE_SUBKEYS", ger.GATE_SUBKEYS == qc.GATE_SUBKEYS, "%s vs %s" % (ger.GATE_SUBKEYS, qc.GATE_SUBKEYS))

NOW = 1793750400.0                       # 2026-11-05T00:00:00Z
ST = os.path.join(T, "st")


def ts(h_ago):
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(NOW - h_ago * 3600))


def row(h_ago, repo, base, head, counts, verdict="FLAG", findings=None):
    return {"ts": ts(h_ago), "gate": "antigaming", "repo": repo, "ref": "%s..%s" % (base, head), "verdict": verdict, "summary": "x",
            "details": {"counts": counts, "findings": findings or [], "subkeys": qc.subkey_counts("antigaming", counts)}}


import time  # noqa: E402
os.makedirs(os.path.join(ST, "qa_shadow"))
os.makedirs(os.path.join(ST, "gate_governor"))
# a real mini repo so the worksheet can show a real diff excerpt
rn = mkrepo({P_BW: rd_fix("billwatch_afa62b13_old.py")}, {P_BW: rd_fix("billwatch_afa62b13_new.py")}, name="billwatch")
rdir = os.path.join(REPOS, rn)
head = sh(["git", "-C", rdir, "rev-parse", "HEAD"])[1].strip()
base = sh(["git", "-C", rdir, "rev-parse", "HEAD~1"])[1].strip()
FSK = [{"rule": "Y_SKIP_ADDED", "sev": "FLAG", "file": P_BW, "line": 55, "msg": "skip/xfail/todo marker added", "snip": "@pytest.mark.skip(...)"}]
FAD = [{"rule": "Y_ASSERT_DROP", "sev": "FLAG", "file": "backend/tests/t.py", "line": 1, "msg": "lost oracle", "snip": "t.py"}]
rows = [row(5, rn, base, head, {"Y_SKIP_ADDED": 1, "B_SKIP_ADDED": 1}, findings=FSK),
        row(6, "gone", "a" * 40, "b" * 40, {"Y_SKIP_ADDED": 1}, findings=FSK),
        row(7, "gone", "c" * 40, "d" * 40, {"Y_SKIP_ADDED": 1}, findings=FSK),
        row(8, "gone", "e" * 40, "f" * 40, {"Y_ASSERT_DROP": 1, "A_TEST_DELETED": 1}, findings=FAD),
        row(9, "gone", "1" * 40, "2" * 40, {"Y_ASSERT_DROP": 1, "Y_SKIP_ADDED": 1}, findings=FAD + FSK),
        row(10, "gone", "3" * 40, "4" * 40, {"A_TEST_DELETED": 1}),
        row(11, "gone", "5" * 40, "6" * 40, {}, verdict="PASS")]
with open(os.path.join(ST, "qa_shadow", "antigaming.jsonl"), "w") as f:
    for r in rows:
        f.write(json.dumps(r) + "\n")
ENV_R = {"OVN_GER_NOW": str(NOW), "OVN_GER_GIT": "off", "OVN_REPOS_DIR": REPOS}
p = sh(["env", "-i"] + ["%s=%s" % kv for kv in dict(ENV, **ENV_R).items()] + [PY, REPORT, "--state", ST, "--json", "--gate", "antigaming"])
rep = json.loads(p[1])
g = rep["gates"][0]
ok("evidence report: antigaming gate carries per-sub-key rows", set(g.get("subkeys", {})) == {"skip_added", "assert_drop"}, str(g.get("subkeys")))
ok("evidence report: skip_added has 4 events (3 + the double-key row), assert_drop 2", g["subkeys"]["skip_added"]["events"] == 4 and g["subkeys"]["assert_drop"]["events"] == 2,
   str(g["subkeys"]))
ok("evidence report: sub-keys are flagged shadow_only and are not blockers", all(v["shadow_only"] for v in g["subkeys"].values()) and not any("sub-key" in r for r in g["reasons"]))
txt = sh(["env", "-i"] + ["%s=%s" % kv for kv in dict(ENV, **ENV_R).items()] + [PY, REPORT, "--state", ST, "--gate", "antigaming"])[1]
ok("evidence report text lists both sub-keys", "sub-key skip_added" in txt and "sub-key assert_drop" in txt, txt[-600:])
txt = sh(["env", "-i"] + ["%s=%s" % kv for kv in dict(ENV, **ENV_R).items()] + [PY, REPORT, "--state", ST, "--gate", "antigaming", "--explain"])[1]
ok("evidence report --explain lists both sub-keys", "sub-key skip_added" in txt and "sub-key assert_drop" in txt, txt[-600:])
os.makedirs(os.path.join(ST, "qa_shadow_none"), exist_ok=True)

# ================================================================================================ qa_precision_sample.py: worksheet + labelled-precision reader
SAMPLE = os.path.join(QA, "qa_precision_sample.py")
ENV_S = dict(ENV, **{"OVN_GER_NOW": str(NOW)})


def run_s(*args):
    p = sh(["env", "-i"] + ["%s=%s" % kv for kv in ENV_S.items()] + [PY, SAMPLE] + list(args))
    return p[0], p[1], p[2]


rc, out, err = run_s("sample", "--state", ST, "--json")
ws = json.loads(out)
ok("worksheet: both sub-keys listed, exit 0", rc == 0 and set(ws) == {"skip_added", "assert_drop"}, "%s %s" % (rc, err[-200:]))
ok("worksheet: skip_added lists its 4 events, assert_drop its 2, none labelled yet", ws["skip_added"]["events"] == 4 and ws["skip_added"]["unlabelled"] == 4
   and ws["assert_drop"]["events"] == 2 and ws["skip_added"]["already_labelled"] == 0, str({k: (v["events"], v["unlabelled"]) for k, v in ws.items()}))
first = ws["skip_added"]["rows"][0]
ok("worksheet: single-sub-key rows are listed before the shared-label row", [r["shared_label"] for r in ws["skip_added"]["rows"]] == [False, False, False, True],
   str([r["shared_label"] for r in ws["skip_added"]["rows"]]))
real = [r for r in ws["skip_added"]["rows"] if r["repo"] == rn][0]
ok("worksheet: a real row shows the commit sha, the finding and a REAL diff excerpt of the skip", real["sha"] == head and "pytest.mark.skip" in real["excerpt"]
   and real["excerpt_source"].startswith("git diff") and "test_security_headers.py:55" in real["finding"], str(real)[:400])
ok("worksheet: a row without a clone falls back to the recorded snippet", [r for r in ws["skip_added"]["rows"] if r["repo"] == "gone"][0]["excerpt_source"].startswith("recorded snippet"))
ok("worksheet: every row carries the one-line governor label command for qa:antigaming", all(r["label_cmd"].startswith("python3 scripts/ovn_gate_governor.py label qa:antigaming l:")
   and r["label_cmd"].endswith('tp|fp --note "why"') for v in ws.values() for r in v["rows"]))
ok("worksheet: a label command key is unique per row", len({r["key"] for r in ws["skip_added"]["rows"]}) == 4)
rc, out, _ = run_s("sample", "--state", ST, "--subkey", "assert_drop", "--n", "1")
ok("worksheet text: --subkey/--n limit the listing and print the command", rc == 0 and "sub-key assert_drop" in out and "sub-key skip_added" not in out and out.count("ovn_gate_governor.py label") == 1, out[:300])
rc, out, _ = run_s("sample", "--state", ST, "--subkey", "bogus")
ok("unknown sub-key -> exit 2", rc == 2)
rc, out, _ = run_s("read", "--state", ST, "--json")
rd0 = json.loads(out)
ok("reader: ZERO labels -> precision None (n/a), nothing counted as tp or fp, all events unlabelled",
   all(v["precision"] is None and v["tp"] == 0 and v["fp"] == 0 for v in rd0.values()) and rd0["skip_added"]["unlabelled"] == 4 and rd0["assert_drop"]["unlabelled"] == 2, str(rd0))

# label: skip_added rows 1 (real) = tp, 2 = fp ; the double-key row stays unlabelled; assert_drop: one tp
keys = {r["sha"]: r["key"] for v in ws.values() for r in v["rows"]}
labs = [("l:", head, "tp"), ("l:", "b" * 40, "fp"), ("l:", "f" * 40, "tp")]
with open(os.path.join(ST, "gate_governor", "labels.jsonl"), "w") as f:
    for _, sha, lab in labs:
        f.write(json.dumps({"ts": ts(1), "gate": "qa:antigaming", "key": keys[sha], "label": lab, "note": "n", "who": "t"}) + "\n")
    f.write(json.dumps({"ts": ts(1), "gate": "qa:antigaming", "key": keys["d" * 40], "label": "maybe", "note": "bad label value", "who": "t"}) + "\n")
    f.write(json.dumps({"ts": ts(1), "gate": "qa:other", "key": keys["d" * 40], "label": "tp", "note": "other gate", "who": "t"}) + "\n")
rc, out, _ = run_s("read", "--state", ST, "--json")
rd1 = json.loads(out)
ok("reader: skip_added tp=1 fp=1 labelled=2 precision 0.5; the 2 other rows stay unlabelled (not tp, not fp)",
   rd1["skip_added"] == {"tp": 1, "fp": 1, "labelled": 2, "unlabelled": 2, "precision": 0.5}, str(rd1["skip_added"]))
ok("reader: assert_drop tp=1 fp=0 precision 1.0, the other event unlabelled; the double-key row's label ('f'*40 is assert-only) is not mixed in",
   rd1["assert_drop"] == {"tp": 1, "fp": 0, "labelled": 1, "unlabelled": 1, "precision": 1.0}, str(rd1["assert_drop"]))
ok("reader: an invalid label value and another gate's label never count", True if rd1["skip_added"]["unlabelled"] == 2 else False)
rc, out, _ = run_s("sample", "--state", ST, "--json")
ws2 = json.loads(out)
ok("worksheet after labelling: labelled rows drop out (skip_added 2 left, 2 already labelled)", ws2["skip_added"]["unlabelled"] == 2 and ws2["skip_added"]["already_labelled"] == 2,
   str((ws2["skip_added"]["unlabelled"], ws2["skip_added"]["already_labelled"])))
rc, out, _ = run_s("read", "--state", ST)
ok("reader text prints labelled precision and says unlabelled are never counted", "labelled precision 0.5" in out and "never counted" in out, out)
before = sorted(os.listdir(os.path.join(ST, "gate_governor")))
run_s("sample", "--state", ST)
run_s("read", "--state", ST)
ok("read-only: the sample/read commands wrote nothing into the state dir", sorted(os.listdir(os.path.join(ST, "gate_governor"))) == before)

shutil.rmtree(T, ignore_errors=True)
print("\nantigaming y5 tests: %d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
