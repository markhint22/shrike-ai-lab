#!/usr/bin/env python3
"""Tests for qa/gate_antigaming.py (S3). Exercises the REAL entry point exactly as cron would: absolute path and relative path from
scripts/overnight-queue, under `env -i` with a minimal PATH and NTFY_SERVER set. Every rule has a seeded negative fixture
(-> FAIL/FLAG) and the legitimate-refactor controls must PASS. No network, no ntfy, never touches a real clone (temp git repos)."""
import json
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
OVN = os.path.abspath(os.path.join(HERE, "..", ".."))
GATE_ABS = os.path.join(OVN, "qa", "gate_antigaming.py")
GATE_REL = os.path.join("qa", "gate_antigaming.py")
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


T = tempfile.mkdtemp(prefix="qa-antigaming-test-")
REPOS = os.path.join(T, "repos")
STATE = os.path.join(T, "state")
os.makedirs(REPOS)
os.makedirs(STATE)
ENV = {"PATH": "/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin", "HOME": T, "NTFY_SERVER": "http://127.0.0.1:9/relay-does-not-exist",
       "OVN_DIR": T, "OVN_REPOS_DIR": REPOS, "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1"}


def sh(cmd, cwd=None, env=None):
    p = subprocess.run(cmd, cwd=cwd, env=env or ENV, capture_output=True, text=True)
    return p.returncode, p.stdout, p.stderr


_n = [0]


def mkrepo(before, after, msg="after"):
    """Create a repo with two commits (before, after). Values None in `after` delete the file. Returns repo name."""
    _n[0] += 1
    name = "r%d" % _n[0]
    d = os.path.join(REPOS, name)
    os.makedirs(d)
    g = lambda *a: sh(["git", "-C", d, "-c", "user.name=t", "-c", "user.email=t@t", *a])  # noqa: E731
    g("init", "-q")
    for path, txt in before.items():
        os.makedirs(os.path.dirname(os.path.join(d, path)) or d, exist_ok=True)
        open(os.path.join(d, path), "w").write(txt)
    g("add", *before.keys())
    g("commit", "-q", "-m", "before")
    for path, txt in after.items():
        full = os.path.join(d, path)
        if txt is None:
            g("rm", "-q", path)
        else:
            os.makedirs(os.path.dirname(full), exist_ok=True)
            open(full, "w").write(txt)
            g("add", path)
    g("commit", "-q", "-m", msg)
    return name


def run_gate(repo, base="HEAD~1", head="HEAD", extra=(), env=None, rel=False):
    e = dict(ENV)
    if env:
        e.update(env)
    script = GATE_REL if rel else GATE_ABS
    cmd = ["env", "-i"] + ["%s=%s" % kv for kv in e.items()] + [PY, script, "check", "--repo", repo, "--base", base, "--head", head, "--no-record"] + list(extra)
    p = subprocess.run(cmd, cwd=OVN if rel else T, capture_output=True, text=True)
    try:
        res = json.loads(p.stdout.strip().splitlines()[-1])
    except Exception:  # noqa: BLE001
        res = {"verdict": "NOJSON", "summary": (p.stdout + p.stderr)[-300:], "details": {}}
    res["_rc"] = p.returncode
    return res


def rules(res):
    return {f["rule"] for f in res.get("details", {}).get("findings", [])}


def case(name, before, after, want_verdict, want_rule=None, forbid_rule=None, msg="after"):
    r = mkrepo(before, after, msg)
    res = run_gate(r)
    good = res["verdict"] == want_verdict and (want_rule is None or want_rule in rules(res)) and (forbid_rule is None or forbid_rule not in rules(res))
    ok(name, good, "verdict=%s rules=%s %s" % (res["verdict"], sorted(rules(res)), res.get("summary", "")[:120]))
    return res


# ---------------------------------------------------------------------------------------------------------------- entry-point contract
r0 = mkrepo({"app/a.py": "def f():\n    return 1\n"}, {"app/a.py": "def f():\n    return 2\n"})
for rel in (False, True):
    res = run_gate(r0, rel=rel)
    ok("entry point runs (%s path, env -i, minimal PATH): single JSON line, PASS on a benign edit" % ("relative" if rel else "absolute"),
       res["verdict"] == "PASS" and res["_rc"] == 0 and res["gate"] == "antigaming", str(res))
ok("benign edit: runtime well under the 5 s budget", (res.get("ms") or 0) < 5000, str(res.get("ms")))
ok("empty diff -> NA", run_gate(r0, base="HEAD", head="HEAD")["verdict"] == "NA")
ok("docs-only diff with no code files -> NA", case("docs only", {"README.md": "a\n"}, {"README.md": "b\n"}, "NA")["verdict"] == "NA")
ok("unknown ref -> UNVERIFIED (exit 0)", (lambda x: x["verdict"] == "UNVERIFIED" and x["_rc"] == 0)(run_gate(r0, base="nope-ref")))
ok("unknown repo -> UNVERIFIED", run_gate("no-such-repo-xyz")["verdict"] == "UNVERIFIED")
ok("git missing from PATH -> UNVERIFIED, never PASS/FAIL", run_gate(r0, env={"PATH": "/nonexistent"})["verdict"] == "UNVERIFIED")
ok("missing args -> UNVERIFIED usage", subprocess.run(["env", "-i", PY, GATE_ABS, "check", "--no-record"], capture_output=True, text=True,
                                                      env=ENV).stdout.count('"verdict": "UNVERIFIED"') == 1)

# deadline reached with no findings => UNVERIFIED (not PASS)
rd = mkrepo({"app/a.py": "def f():\n    return 1\n", "tests/test_a.py": "def test_a():\n    assert 1 == 1\n"},
            {"app/a.py": "def f():\n    return 2\n", "tests/test_a.py": "def test_a():\n    assert 2 == 2\n"})
res = run_gate(rd, env={"QA_ANTIGAMING_DEADLINE": "-1"})
ok("deadline exhausted before analysis, no findings -> UNVERIFIED", res["verdict"] == "UNVERIFIED", str(res["verdict"]))

# ---------------------------------------------------------------------------------------------------------------- A / E : python tests
BASE_PY = ('import pytest\nfrom app.calc import add\n\n\ndef test_add():\n    assert add(1, 2) == 3\n    assert add(0, 0) == 0\n\n\n'
           'def test_other():\n    assert add(2, 2) == 4\n')
CALC = {"app/calc.py": "def add(a, b):\n    return a + b\n", "app/use.py": "from app.calc import add\n\n\ndef total(xs):\n    return add(xs[0], xs[1])\n"}


def pyt(body_after, base=BASE_PY):
    return dict(CALC, **{"tests/test_calc.py": base}), dict(CALC, **{"tests/test_calc.py": body_after})


b, a = pyt(BASE_PY.replace("    assert add(1, 2) == 3\n    assert add(0, 0) == 0\n", "    add(1, 2)\n"))
res = case("E: all assertions removed from a surviving test -> FAIL E_ZERO_ASSERTS", b, a, "FAIL", "E_ZERO_ASSERTS")
ok("E: evidence carries file:line", any(f["file"] == "tests/test_calc.py" and f["line"] for f in res["details"]["findings"]))
b, a = pyt(BASE_PY.replace("assert add(1, 2) == 3", "assert True"))
case("A: assert x==3 turned into `assert True` (no-op) -> FAIL A_ASSERT_NOOP", b, a, "FAIL", "A_ASSERT_NOOP")
b, a = pyt(BASE_PY.replace("assert add(1, 2) == 3", "assert add(1, 2) == 3 or True"))
case("A: `... or True` tautology -> FAIL", b, a, "FAIL")
b, a = pyt(BASE_PY.replace("assert add(1, 2) == 3", "assert add(1, 2) is not None"))
case("A: exact value -> `is not None` -> FLAG A_ASSERT_WEAKENED", b, a, "FLAG", "A_ASSERT_WEAKENED")
b, a = pyt(BASE_PY.replace("assert add(1, 2) == 3", "assert add(1, 2)"))
case("A: exact value -> bare truthiness -> FLAG", b, a, "FLAG", "A_ASSERT_WEAKENED")
b, a = pyt("import pytest\nfrom app.calc import add\n\n\ndef test_add():\n    assert add(1, 2) == 3\n    assert add(0, 0) == 0\n\n\n"
           "def test_other():\n    assert add(2, 2) > 0\n")
case("A: `== 4` -> `> 0` -> FLAG A_ASSERT_WEAKENED", b, a, "FLAG", "A_ASSERT_WEAKENED")
b, a = pyt(BASE_PY.replace("    assert add(0, 0) == 0\n", ""))
case("A: one of two assertions silently dropped -> FLAG A_ASSERT_DROPPED", b, a, "FLAG", "A_ASSERT_DROPPED")
b, a = pyt(BASE_PY.replace("\n\ndef test_other():\n    assert add(2, 2) == 4\n", ""))
case("A: whole test function deleted, subject still present -> FLAG A_TEST_DELETED", b, a, "FLAG", "A_TEST_DELETED")
UT = ("import unittest\nfrom app.calc import add\n\n\nclass T(unittest.TestCase):\n    def test_add(self):\n        self.assertEqual(add(1, 2), 3)\n")
b, a = pyt(UT.replace("self.assertEqual(add(1, 2), 3)", "self.assertTrue(add(1, 2))"), base=UT)
case("A: unittest assertEqual -> assertTrue -> FLAG weakened", b, a, "FLAG", "A_ASSERT_WEAKENED")
b, a = pyt(UT.replace("self.assertEqual(add(1, 2), 3)", "self.assertTrue(True)"), base=UT)
case("A: unittest assertEqual -> assertTrue(True) -> FAIL (zero effective asserts)", b, a, "FAIL", "E_ZERO_ASSERTS")
RAISES = "import pytest\n\n\ndef test_r():\n    with pytest.raises(ValueError):\n        int('x')\n"
b, a = pyt(RAISES.replace("ValueError", "Exception"), base=RAISES)
case("A: pytest.raises(ValueError) broadened to Exception -> FLAG", b, a, "FLAG", "A_ASSERT_WEAKENED")
PARAM = "import pytest\n\n\n@pytest.mark.parametrize('x', [1, 2, 3, 4])\ndef test_p(x):\n    assert x > 0\n"
b, a = pyt(PARAM.replace("[1, 2, 3, 4]", "[1]"), base=PARAM)
case("A: parametrize cases 4 -> 1 -> FLAG A_PARAM_CASES_DROPPED", b, a, "FLAG", "A_PARAM_CASES_DROPPED")

# benign controls (legitimate refactors must PASS)
HELPER_BASE = "def test_a():\n    assert 1 + 1 == 2\n    assert 2 + 2 == 4\n"
HELPER_AFTER = ("def _check(v):\n    assert v + v == v * 2\n    assert v > 0\n\n\ndef test_a():\n    _check(2)\n")
case("benign: assertions moved into a new helper that the test calls -> PASS", {"tests/test_h.py": HELPER_BASE}, {"tests/test_h.py": HELPER_AFTER}, "PASS")
case("benign: test renamed, same body -> PASS", {"tests/test_h.py": HELPER_BASE}, {"tests/test_h.py": HELPER_BASE.replace("test_a", "test_renamed_a")}, "PASS")
case("benign: assertion strengthened + new test added -> PASS", {"tests/test_h.py": HELPER_BASE},
     {"tests/test_h.py": HELPER_BASE.replace("assert 2 + 2 == 4", "assert 2 + 2 == 4\n    assert 3 + 3 == 6") + "\n\ndef test_new():\n    assert 5 == 5 + 0\n"}, "PASS")
case("benign: assertEqual(True, x) -> assertTrue(x) is equivalent -> PASS",
     {"tests/test_h.py": "import unittest\n\n\nclass T(unittest.TestCase):\n    def test_a(self):\n        self.assertEqual(True, 1 < 2)\n"},
     {"tests/test_h.py": "import unittest\n\n\nclass T(unittest.TestCase):\n    def test_a(self):\n        self.assertTrue(1 < 2)\n"}, "PASS")
case("benign: test file deleted TOGETHER with its subject module -> PASS",
     {"app/calc.py": "def add(a, b):\n    return a + b\n", "tests/test_calc.py": "from app.calc import add\n\n\ndef test_add():\n    assert add(1, 2) == 3\n"},
     {"app/calc.py": None, "tests/test_calc.py": None}, "PASS")
case("benign: test of an already-undefined subject deleted (dead test) -> PASS",
     {"app/other.py": "x = 1\n", "tests/test_gone.py": "from app.other import vanished_helper\n\n\ndef test_v():\n    assert vanished_helper() == 1\n"},
     {"tests/test_gone.py": None}, "PASS")
case("benign: duplicate test removed while a same-body copy remains -> PASS",
     {"tests/test_d.py": "def test_dup():\n    assert 1 == 1\n\n\ndef test_dup_again():\n    assert 1 == 1\n"},
     {"tests/test_d.py": "def test_dup():\n    assert 1 == 1\n"}, "PASS")
case("syntax-error test file: no crash, and UNVERIFIED (could not be checked) rather than PASS", {"tests/test_bad.py": "def test_a():\n    assert 1 == 1\n"},
     {"tests/test_bad.py": "def test_a(:\n    assert 1 == 1\n"}, "UNVERIFIED")

# ---------------------------------------------------------------------------------------------------------------- B : suppressions
SK_B = {"tests/test_s.py": "import pytest\n\n\ndef test_s():\n    assert 1 == 1\n\n\ndef test_t():\n    assert 2 == 2\n"}
case("B: @pytest.mark.skip added above an existing test -> FLAG B_SKIP_ADDED", SK_B,
     {"tests/test_s.py": SK_B["tests/test_s.py"].replace("def test_s", "@pytest.mark.skip(reason='later')\ndef test_s")}, "FLAG", "B_SKIP_ADDED")
case("B: @pytest.mark.xfail added to an existing test -> FLAG", SK_B,
     {"tests/test_s.py": SK_B["tests/test_s.py"].replace("def test_t", "@pytest.mark.xfail\ndef test_t")}, "FLAG", "B_SKIP_ADDED")
case("B: pytest.skip() call inserted in an existing test -> FLAG", SK_B,
     {"tests/test_s.py": SK_B["tests/test_s.py"].replace("def test_s():\n", "def test_s():\n    pytest.skip('flaky')\n")}, "FLAG", "B_SKIP_ADDED")
case("B: skipif added to an existing test -> FLAG", SK_B,
     {"tests/test_s.py": SK_B["tests/test_s.py"].replace("def test_s", "@pytest.mark.skipif(True, reason='x')\ndef test_s")}, "FLAG", "B_SKIP_ADDED")
LINT = {"app/m.py": "import os\n\n\ndef f(x):\n    y = os.getcwd()\n    return x + y\n"}
case("B: `# noqa` appended to an existing line -> FLAG B_SUPPRESSION_ADDED", LINT,
     {"app/m.py": LINT["app/m.py"].replace("y = os.getcwd()", "y = os.getcwd()  # noqa: E501")}, "FLAG", "B_SUPPRESSION_ADDED")
case("B: `# type: ignore` appended to an existing line -> FLAG", LINT,
     {"app/m.py": LINT["app/m.py"].replace("return x + y", "return x + y  # type: ignore")}, "FLAG", "B_SUPPRESSION_ADDED")
case("B: `# pragma: no cover` added to an existing line -> FLAG B_COVERAGE_EXCLUDED", LINT,
     {"app/m.py": LINT["app/m.py"].replace("return x + y", "return x + y  # pragma: no cover")}, "FLAG", "B_COVERAGE_EXCLUDED")
case("benign: a brand-new line with `# noqa` (new code) -> PASS", LINT,
     {"app/m.py": LINT["app/m.py"] + "\n\ndef g():\n    import sys  # noqa: F401\n    return 1\n"}, "PASS")
case("benign: brand-new file with a skipped test -> PASS", LINT,
     {"tests/test_new.py": "import pytest\n\n\n@pytest.mark.skip\ndef test_n():\n    assert f(1) == 1\n"}, "PASS")

# ---------------------------------------------------------------------------------------------------------------- C : error handling in NON-test files
SCHED = ('import asyncio\nimport logging\nlogger = logging.getLogger(__name__)\n\n\nclass Sched:\n    async def tick(self):\n        return 1\n\n'
         '    async def run_forever(self) -> None:\n        """Loop tick() until cancelled."""\n        while True:\n            try:\n'
         '                await self.tick()\n            except Exception:\n                logger.exception("tick failed; continuing")\n'
         '            await asyncio.sleep(1)\n')
SCHED_BAD = SCHED.replace('            try:\n                await self.tick()\n            except Exception:\n                logger.exception("tick failed; continuing")\n',
                          '            await self.tick()\n')
res = case("C: INCIDENT SHAPE - run_forever loses its try/except guard -> FLAG C_ERRORHANDLING_REMOVED",
           {"backend/app/services/scheduler.py": SCHED}, {"backend/app/services/scheduler.py": SCHED_BAD}, "FLAG", "C_ERRORHANDLING_REMOVED")
ok("C: finding names the function and the file", any("run_forever" in f["msg"] and f["file"].endswith("scheduler.py") for f in res["details"]["findings"]))
VAL = ("def withdraw(bal, amt):\n    if amt <= 0:\n        raise ValueError('bad amount')\n    if amt > bal:\n        raise ValueError('insufficient')\n    return bal - amt\n")
case("C: validation raise removed from a non-test function -> FLAG C_VALIDATION_REMOVED", {"app/bank.py": VAL},
     {"app/bank.py": VAL.replace("    if amt > bal:\n        raise ValueError('insufficient')\n", "")}, "FLAG", "C_VALIDATION_REMOVED")
NARROW = "def load(p):\n    try:\n        return open(p).read()\n    except Exception:\n        return ''\n"
case("C: `except Exception` narrowed to `except KeyError` -> FLAG C_HANDLER_NARROWED", {"app/io.py": NARROW},
     {"app/io.py": NARROW.replace("except Exception", "except KeyError")}, "FLAG", "C_HANDLER_NARROWED")
TS = "export async function load(url: string) {\n  try {\n    const r = await fetch(url)\n    return await r.json()\n  } catch (e) {\n    return null\n  }\n}\n"
case("C: ts try/catch removed from a non-test file -> FLAG", {"web/src/load.ts": TS},
     {"web/src/load.ts": "export async function load(url: string) {\n  const r = await fetch(url)\n  return await r.json()\n}\n"}, "FLAG", "C_ERRORHANDLING_REMOVED")
KT = "fun load(): Int {\n    return try {\n        parse()\n    } catch (e: Exception) {\n        0\n    }\n}\n"
case("C: kotlin try/catch removed -> FLAG", {"app/src/main/Load.kt": KT}, {"app/src/main/Load.kt": "fun load(): Int {\n    return parse()\n}\n"}, "FLAG", "C_ERRORHANDLING_REMOVED")
case("benign: guard MOVED into a new helper with its own try/except -> PASS",
     {"app/m2.py": "def f(d):\n    try:\n        v = int(d['n'])\n    except ValueError:\n        v = 0\n    return v\n"},
     {"app/m2.py": "def _n(d):\n    try:\n        return int(d['n'])\n    except ValueError:\n        return 0\n\n\ndef f(d):\n    return _n(d)\n"}, "PASS")
case("benign: try/except added (more safety) -> PASS", {"app/m3.py": "def f(x):\n    return x\n"},
     {"app/m3.py": "def f(x):\n    try:\n        return int(x)\n    except ValueError:\n        return 0\n"}, "PASS")
case("benign: ts guard moved to a new helper in the same diff -> PASS", {"web/src/load.ts": TS},
     {"web/src/load.ts": "export async function load(url: string) {\n  return safe(url)\n}\nasync function safe(url: string) {\n  try {\n    const r = await fetch(url)\n"
      "    return await r.json()\n  } catch (e) {\n    return null\n  }\n}\n"}, "PASS")
case("benign: whole non-test module deleted -> PASS (not an error-handling removal)", {"app/old.py": NARROW}, {"app/old.py": None}, "PASS")

# ---------------------------------------------------------------------------------------------------------------- JS / TS tests
JS = ("import { describe, it, expect } from 'vitest'\nimport { add } from '../add'\n\ndescribe('add', () => {\n  it('adds', () => {\n"
      "    expect(add(1, 2)).toBe(3)\n    expect(add(0, 0)).toBe(0)\n  })\n\n  it('adds negatives', () => {\n    expect(add(-1, -1)).toBe(-2)\n  })\n})\n")
JSF = {"src/add.ts": "export const add = (a: number, b: number) => a + b\n", "src/use.ts": "import { add } from './add'\nexport const t = (a: number) => add(a, 1)\n"}


def jst(after, base=JS):
    return dict(JSF, **{"src/__tests__/add.test.ts": base}), dict(JSF, **{"src/__tests__/add.test.ts": after})


b, a = jst(JS.replace("it('adds negatives'", "it.skip('adds negatives'"))
case("B: it.skip added to an existing vitest test -> FLAG B_SKIP_ADDED", b, a, "FLAG", "B_SKIP_ADDED")
b, a = jst(JS.replace("it('adds negatives'", "xit('adds negatives'"))
case("B: xit added -> FLAG", b, a, "FLAG", "B_SKIP_ADDED")
b, a = jst(JS.replace("describe('add'", "describe.skip('add'"))
case("B: describe.skip added -> FLAG", b, a, "FLAG", "B_SKIP_ADDED")
b, a = jst(JS.replace("expect(add(-1, -1)).toBe(-2)", "expect(add(-1, -1)).toBeDefined()"))
case("A: expect().toBe(-2) -> toBeDefined() -> FLAG A_ASSERT_WEAKENED", b, a, "FLAG", "A_ASSERT_WEAKENED")
b, a = jst(JS.replace("expect(add(-1, -1)).toBe(-2)", "expect(true).toBe(true)"))
case("E: assertion replaced by expect(true).toBe(true) -> FAIL E_ZERO_ASSERTS", b, a, "FAIL", "E_ZERO_ASSERTS")
b, a = jst(JS.replace("    expect(add(1, 2)).toBe(3)\n    expect(add(0, 0)).toBe(0)\n", "    add(1, 2)\n"))
case("E: all expects removed from a surviving it() -> FAIL", b, a, "FAIL", "E_ZERO_ASSERTS")
b, a = jst(JS.replace("\n  it('adds negatives', () => {\n    expect(add(-1, -1)).toBe(-2)\n  })\n", ""))
case("A: it() case deleted -> FLAG A_TEST_DELETED", b, a, "FLAG", "A_TEST_DELETED")
b, a = jst(JS.replace("    expect(add(0, 0)).toBe(0)\n", ""))
case("A: one expect dropped -> FLAG A_ASSERT_DROPPED", b, a, "FLAG", "A_ASSERT_DROPPED")
b, a = jst(JS.replace("it('adds'", "it('adds numbers'"))
case("benign: it() title renamed -> PASS", b, a, "PASS")
b, a = jst(JS.replace("expect(add(0, 0)).toBe(0)", "expect(add(0, 0)).toBe(0)\n    expect(add(5, 5)).toBe(10)"))
case("benign: extra expect added -> PASS", b, a, "PASS")
b, a = jst(JS.replace("  it('adds', () => {", "  it('adds', () => {\n    // expect(nothing).toBe(1) in a comment\n    const s = \"expect(x).toBe(1)\"\n"))
case("benign: assertion-like text in comments/strings does not count (no change) -> PASS", b, a, "PASS")
case("benign: it.skip on a brand-new test -> PASS", dict(JSF), dict(JSF, **{"src/__tests__/new.test.ts":
     "import { it, expect } from 'vitest'\nit.skip('later', () => {\n  expect(f(1)).toBe(1)\n})\n"}), "PASS")
case("benign: eslint-disable on a brand-new line in a new file -> PASS", dict(JSF), dict(JSF, **{"src/z.ts": "// eslint-disable-next-line\nexport const z = 1\n"}), "PASS")
case("B: eslint-disable appended to an existing line -> FLAG", {"web/src/q.ts": "export const q = (x: any) => x.y\n"},
     {"web/src/q.ts": "export const q = (x: any) => x.y // eslint-disable-line\n"}, "FLAG", "B_SUPPRESSION_ADDED")

# ---------------------------------------------------------------------------------------------------------------- kotlin / gdscript / swift
KTT = ("import org.junit.Test\nimport kotlin.test.assertEquals\n\nclass AddTest {\n    @Test\n    fun adds() {\n        assertEquals(3, add(1, 2))\n    }\n\n"
       "    @Test\n    fun addsZero() {\n        assertEquals(0, add(0, 0))\n    }\n}\n")
KP = "app/src/test/java/AddTest.kt"
case("B: @Ignore added to an existing kotlin test -> FLAG B_SKIP_ADDED", {KP: KTT}, {KP: KTT.replace("    @Test\n    fun addsZero", "    @Test\n    @Ignore\n    fun addsZero")},
     "FLAG", "B_SKIP_ADDED")
case("A: kotlin assertEquals -> assertTrue -> FLAG weakened", {KP: KTT}, {KP: KTT.replace("assertEquals(3, add(1, 2))", "assertTrue(add(1, 2) > 0)")}, "FLAG", "A_ASSERT_WEAKENED")
case("E: kotlin test keeps its @Test but loses its assertion -> FAIL", {KP: KTT}, {KP: KTT.replace("        assertEquals(0, add(0, 0))\n", "        add(0, 0)\n")}, "FAIL", "E_ZERO_ASSERTS")
case("A: kotlin test method deleted -> FLAG A_TEST_DELETED", {KP: KTT},
     {KP: KTT.replace("\n    @Test\n    fun addsZero() {\n        assertEquals(0, add(0, 0))\n    }\n", "")}, "FLAG", "A_TEST_DELETED")
case("benign: kotlin assertEquals(false, x) -> assertFalse(x) -> PASS",
     {KP: "class T {\n    @Test\n    fun f() {\n        assertEquals(false, x())\n    }\n}\n"}, {KP: "class T {\n    @Test\n    fun f() {\n        assertFalse(x())\n    }\n}\n"}, "PASS")
GD = "extends GutTest\n\n\nfunc test_add():\n\tassert_eq(add(1, 2), 3)\n\tassert_eq(add(0, 0), 0)\n\n\nfunc test_neg():\n\tassert_eq(add(-1, -1), -2)\n"
case("A: gdscript assert_eq -> assert_true -> FLAG weakened", {"test/test_add.gd": GD}, {"test/test_add.gd": GD.replace("assert_eq(add(-1, -1), -2)", "assert_true(add(-1, -1) < 0)")}, "FLAG", "A_ASSERT_WEAKENED")
case("E: gdscript test loses all assert_* -> FAIL", {"test/test_add.gd": GD}, {"test/test_add.gd": GD.replace("\tassert_eq(add(-1, -1), -2)\n", "\tadd(-1, -1)\n")}, "FAIL", "E_ZERO_ASSERTS")
case("A: gdscript test deleted -> FLAG", {"test/test_add.gd": GD}, {"test/test_add.gd": GD.split("\n\n\nfunc test_neg")[0] + "\n"}, "FLAG", "A_TEST_DELETED")
SW = "import XCTest\n\nfinal class AddTests: XCTestCase {\n    func testAdd() {\n        XCTAssertEqual(add(1, 2), 3)\n    }\n}\n"
case("A: swift XCTAssertEqual -> XCTAssertTrue -> FLAG weakened", {"Tests/AddTests.swift": SW}, {"Tests/AddTests.swift": SW.replace("XCTAssertEqual(add(1, 2), 3)", "XCTAssertTrue(add(1, 2) > 0)")}, "FLAG", "A_ASSERT_WEAKENED")

# ---------------------------------------------------------------------------------------------------------------- D : frozen manifest
import hashlib  # noqa: E402

FROZEN_T = "def test_x():\n    assert 1 + 1 == 2\n"
rf = mkrepo({"tests/test_frozen.py": FROZEN_T, "app/a.py": "x = 1\n"}, {"tests/test_frozen.py": FROZEN_T + "\n\ndef test_y():\n    assert f(3) == 3\n", "app/a.py": "x = 2\n"})
res = run_gate(rf)
ok("D: manifest absent => frozen check reported NA (details), verdict unaffected", res["details"].get("frozen", "").startswith("NA") and res["verdict"] == "PASS", str(res["details"].get("frozen")))
man = {rf: {"tests/test_frozen.py": hashlib.sha256(FROZEN_T.encode()).hexdigest()}}
json.dump(man, open(os.path.join(STATE, "qa_frozen_tests.json"), "w"))
res = run_gate(rf)
ok("D: edit of a frozen test file -> FAIL D_FROZEN_EDIT (even though only an ADD)", res["verdict"] == "FAIL" and "D_FROZEN_EDIT" in rules(res), str(res["verdict"]))
rf2 = mkrepo({"tests/test_frozen.py": FROZEN_T, "app/a.py": "x = 1\n"}, {"app/a.py": "x = 2\n"})
json.dump({rf2: {"tests/test_frozen.py": hashlib.sha256(FROZEN_T.encode()).hexdigest()}}, open(os.path.join(STATE, "qa_frozen_tests.json"), "w"))
res = run_gate(rf2)
ok("D: frozen file untouched by the diff -> PASS", res["verdict"] == "PASS" and "checked 0" in res["details"]["frozen"], str(res["details"].get("frozen")))
rf3 = mkrepo({"tests/test_frozen.py": FROZEN_T}, {"tests/test_frozen.py": None})
json.dump({rf3: {"tests/test_frozen.py": hashlib.sha256(FROZEN_T.encode()).hexdigest()}}, open(os.path.join(STATE, "qa_frozen_tests.json"), "w"))
ok("D: frozen test file DELETED -> FAIL", run_gate(rf3)["verdict"] == "FAIL")
ok("D: repo not listed in manifest => NA for that check", run_gate(r0)["details"]["frozen"].startswith("NA"))
open(os.path.join(STATE, "qa_frozen_tests.json"), "w").write("{not json")
ok("D: corrupt manifest => NA, never a crash", run_gate(r0)["verdict"] == "PASS")
os.remove(os.path.join(STATE, "qa_frozen_tests.json"))

# ---------------------------------------------------------------------------------------------------------------- F : config
CFG = "[tool.coverage.report]\nfail_under = 80\n"
case("F: coverage threshold lowered 80 -> 50 -> FLAG F_COVERAGE_LOWERED", {"pyproject.toml": CFG}, {"pyproject.toml": CFG.replace("80", "50")}, "FLAG", "F_COVERAGE_LOWERED")
case("benign: coverage threshold raised -> no finding (NA: no code files)", {"pyproject.toml": CFG}, {"pyproject.toml": CFG.replace("80", "90")}, "NA")


# ---------------------------------------------------------------------------------------------------------------- reviewer repros (fix round 1)
# 1. file cap: 450 code files + a skipped test past the cap must never PASS
bf = {"a%d/m.py" % i: "x = %d\n" % i for i in range(450)}
bf["zz/test_last.py"] = "def test_last():\n    assert 1 + 1 == 2\n"
af = {"a%d/m.py" % i: "x = %d\n" % (i + 1) for i in range(450)}
af["zz/test_last.py"] = "import pytest\n\n\n@pytest.mark.skip\ndef test_last():\n    pass\n"
res = run_gate(mkrepo(bf, af))
ok("450 code files, skipped test beyond the 400-file cap -> never PASS (UNVERIFIED or a finding)", res["verdict"] in ("UNVERIFIED", "FLAG", "FAIL"), res["verdict"])
bf2 = {k: v for k, v in bf.items() if k != "zz/test_last.py"}
af2 = {k: v for k, v in af.items() if k != "zz/test_last.py"}
res = run_gate(mkrepo(bf2, af2))
ok("450 trivially edited code files, nothing found -> UNVERIFIED not PASS", res["verdict"] == "UNVERIFIED" and "unanalysed" in res["details"], res["verdict"])
# oversize blob
big = "x = 1\n" + "y = 2\n" * 200000
res = run_gate(mkrepo({"tests/test_big.py": "def test_a():\n    assert 1 == 1\n" + big}, {"tests/test_big.py": "def test_a():\n    pass\n" + big}))
ok("test file over the blob cap -> UNVERIFIED not PASS/false deletion", res["verdict"] == "UNVERIFIED", res["verdict"])

# 2. vacuous assertions in new / edited tests
VB = {"tests/test_v.py": "def test_ok():\n    assert 1 == 1\n"}
def vac(name, body, rule="A_VACUOUS", sev="FAIL"):
    case(name, VB, {"tests/test_v.py": "def test_ok():\n    assert 1 == 1\n\n\n" + body}, sev, rule)
# 2026-10-03: a NEW test whose ONLY assertions are tautologies is A_VACUOUS (FAIL; 3/3 true positives in the shadow data)
vac("new test with assertTrue(True) -> FAIL A_VACUOUS", "def test_new(self):\n    self.assertTrue(True)\n")
vac("new test with `assert 1` -> FAIL A_VACUOUS", "def test_new():\n    assert 1\n")
vac("new test with `assert x or not x` -> FAIL A_VACUOUS", "def test_new():\n    x = f()\n    assert x or not x\n")
vac("new test with try: assert / except AssertionError: pass -> FAIL A_VACUOUS", "def test_new():\n    try:\n        assert 1 == 2\n    except AssertionError:\n        pass\n")
# ... while a real assertion next to a stray tautology stays the weaker FLAG
vac("new test with a real assertion plus a stray `assert True` -> FLAG A_VACUOUS_ASSERT (NOT the FAIL rule)",
    "def test_new():\n    assert f(2) == 4\n    assert True\n", rule="A_VACUOUS_ASSERT", sev="FLAG")
case("assert foo() == 1 -> assert foo() == foo() -> FLAG A_ASSERT_WEAKENED (exact value became self-comparison)", {"tests/test_v.py": "def test_ok():\n    assert foo() == 1\n"},
     {"tests/test_v.py": "def test_ok():\n    assert foo() == foo()\n"}, "FLAG", "A_ASSERT_WEAKENED")
case("emptied pytest.raises body (bar() -> pass) -> FLAG",
     {"tests/test_v.py": "import pytest\n\n\ndef test_ok():\n    with pytest.raises(ValueError):\n        bar()\n"},
     {"tests/test_v.py": "import pytest\n\n\ndef test_ok():\n    with pytest.raises(ValueError):\n        pass\n"}, "FAIL", "E_ZERO_ASSERTS")
case("benign: a NEW determinism test (assert f('a') == f('a')) is legitimate -> PASS", VB,
     {"tests/test_v.py": "def test_ok():\n    assert 1 == 1\n\n\ndef test_det():\n    assert f('a') == f('a')\n    assert len(f('a')) == 8\n"}, "PASS")
case("benign: new test with a real assertion still PASSes", VB, {"tests/test_v.py": "def test_ok():\n    assert 1 == 1\n\n\ndef test_new():\n    assert f(2) == 4\n"}, "PASS")
case("benign: try/except that re-raises keeps the assertion effective", VB,
     {"tests/test_v.py": "def test_ok():\n    assert 1 == 1\n\n\ndef test_new():\n    try:\n        assert f(2) == 4\n    except AssertionError:\n        log()\n        raise\n"}, "PASS")

# 3. pytest.ini deselection shapes
PI = "[pytest]\naddopts = -q\n"
for nm, line in (("-k 'not test_x'", "addopts = -q -k 'not test_x'"), ("-m not slow", "addopts = -q -m 'not slow'"), ("--maxfail", "addopts = -q --maxfail=1"),
                 ("-p no:cacheprovider", "addopts = -q -p no:cov"), ("testpaths narrowing", "addopts = -q\ntestpaths = tests/unit")):
    case("F: pytest.ini %s -> FLAG F_TESTS_EXCLUDED" % nm, {"pytest.ini": PI}, {"pytest.ini": "[pytest]\n" + line + "\n"}, "FLAG", "F_TESTS_EXCLUDED")
case("benign: pytest.ini unrelated edit -> no finding", {"pytest.ini": PI}, {"pytest.ini": "[pytest]\naddopts = -q -ra\n"}, "NA")

# ---------------------------------------------------------------------------------------------------------------- modes / recording / secrets
res = run_gate(mkrepo({"tests/test_k.py": "def test_k():\n    assert 1 + 1 == 2\n"}, {"tests/test_k.py": "def test_k():\n    pass\n"}),
               env={"OVN_QA_ANTIGAMING": "enforce"}, extra=["--enforce-exit"])
ok("enforce mode + FAIL + --enforce-exit => exit 1", res["verdict"] == "FAIL" and res["_rc"] == 1, str(res["_rc"]))
res = run_gate(mkrepo({"tests/test_k.py": "def test_k():\n    assert 1 + 1 == 2\n"}, {"tests/test_k.py": "def test_k():\n    pass\n"}))
ok("shadow mode (default) + FAIL => exit 0", res["verdict"] == "FAIL" and res["_rc"] == 0 and res["mode"] == "shadow")
cmd = ["env", "-i"] + ["%s=%s" % kv for kv in ENV.items()] + [PY, GATE_ABS, "check", "--repo", r0, "--base", "HEAD~1", "--head", "HEAD"]
subprocess.run(cmd, capture_output=True, text=True)
logp = os.path.join(STATE, "qa_shadow", "antigaming.jsonl")
ok("without --no-record the result is appended to state/qa_shadow/antigaming.jsonl", os.path.exists(logp) and len(open(logp).read().splitlines()) == 1)
SECRET = "sk_live_" + "a1B2c3D4e5F6g7H8i9J0k1L2m3N4o5P6"
res = case("secret-looking literals are never echoed in evidence", {"app/s.py": "def f(x):\n    return x\n\n\ndef g(x):\n    y = '%s'\n    return y\n" % SECRET},
           {"app/s.py": "def f(x):\n    return x\n\n\ndef g(x):\n    y = '%s'  # noqa\n    return y\n" % SECRET}, "FLAG")
ok("redaction: the long literal is not in the JSON output", SECRET not in json.dumps(res))
res = run_gate(mkrepo({"app/big.py": "x = 1\n"}, {"app/big.py": "x = 1\n" + "".join("def f%d():\n    return %d\n" % (i, i) for i in range(2000))}))
ok("large diff stays fast (<5 s) and PASSes", res["verdict"] == "PASS" and (res["ms"] or 0) < 5000, str(res["ms"]))


# ---- 2026-10-02: a raise that MOVED into a helper defined elsewhere in the same change is delegated, not dropped (real FP: billwatch get_current_user) ----
AUTH_BEFORE = ("from fastapi import HTTPException\n\n\ndef check_user_active(user):\n    if not user.is_active:\n        raise HTTPException(status_code=401, detail='inactive')\n\n\n"
               "def get_current_user(user):\n    if user is None:\n        raise HTTPException(status_code=401, detail='nope')\n    if not user.is_active:\n        raise HTTPException(status_code=401, detail='inactive')\n    return user\n")
AUTH_AFTER = ("from fastapi import HTTPException\nfrom app.core.dependencies import check_user_active\n\n\n"
              "def get_current_user(user):\n    if user is None:\n        raise HTTPException(status_code=401, detail='nope')\n    check_user_active(user)\n    return user\n")
DEPS = "from fastapi import HTTPException\n\n\ndef check_user_active(user):\n    if not user.is_active:\n        raise HTTPException(status_code=401, detail='inactive')\n"
case("C: raise moved into a helper defined in another file of the same change -> NOT flagged C_VALIDATION_REMOVED",
     {"app/auth.py": AUTH_BEFORE, "app/core/dependencies.py": "X = 1\n"}, {"app/auth.py": AUTH_AFTER, "app/core/dependencies.py": DEPS}, "PASS", forbid_rule="C_VALIDATION_REMOVED")
case("C: NEGATIVE CONTROL - raise deleted while an UNRELATED raising helper is added in another file (never called) still FLAGs",
     {"app/bank.py": VAL, "app/other.py": "X = 1\n"},
     {"app/bank.py": VAL.replace("    if amt > bal:\n        raise ValueError('insufficient')\n", ""), "app/other.py": "def unrelated(v):\n    if v:\n        raise ValueError('x')\n"},
     "FLAG", "C_VALIDATION_REMOVED")

# ---- 2026-10-02: refs missing from the live clone are fetched from origin before giving up (8/65 real runs were UNVERIFIED 'cannot resolve ref') ----
_src = mkrepo({"app/a.py": "def f():\n    return 1\n"}, {"app/a.py": "def f():\n    return 2\n"})
_srcd = os.path.join(REPOS, _src)
_bare = os.path.join(T, "origin.git")
sh(["git", "clone", "-q", "--bare", _srcd, _bare])
_live = os.path.join(REPOS, "livecopy")
sh(["git", "clone", "-q", _bare, _live])
sh(["git", "-C", _srcd, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "--allow-empty", "-m", "x"])
open(os.path.join(_srcd, "app", "a.py"), "w").write("def f():\n    return 3\n")
sh(["git", "-C", _srcd, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-am", "three"])
sh(["git", "-C", _srcd, "push", "-q", _bare, "HEAD:refs/heads/master"])
_h = sh(["git", "-C", _srcd, "rev-parse", "HEAD"])[1].strip(); _b = sh(["git", "-C", _srcd, "rev-parse", "HEAD~1"])[1].strip()
res = run_gate("livecopy", base=_b, head=_h, env={"QA_FETCH_WAIT": "0"})
ok("refs only on origin (not yet in the live clone) are fetched -> PASS, not UNVERIFIED", res["verdict"] == "PASS", str(res.get("verdict")) + " " + str(res.get("summary"))[:120])
res = run_gate("livecopy", base="0" * 40, head="1" * 40, env={"QA_FETCH_WAIT": "0"})
ok("refs that exist nowhere stay UNVERIFIED after the fetch attempt", res["verdict"] == "UNVERIFIED", str(res.get("verdict")))


# ---- 2026-10-02: F_CLAIM_TEST_ONLY - a feat/fix/perf/refactor commit that changes only tests (iptv limiter incident) ----
LIM_SRC = "def make():\n    return 1\n"
LIM_T0 = "def test_a():\n    assert make() == 1\n"
LIM_T1 = "def test_a():\n    assert make() == 1\n\n\ndef test_b():\n    assert make() is not None\n"
case("F: 'fix: respect env var' that changes ONLY a test file -> FLAG F_CLAIM_TEST_ONLY (iptv limiter incident)",
     {"app/limiter.py": LIM_SRC, "tests/test_limiter.py": LIM_T0}, {"tests/test_limiter.py": LIM_T1}, "FLAG", "F_CLAIM_TEST_ONLY",
     msg="fix: respect RATE_LIMIT_ENABLED env var in limiter initialization")
case("F: subject that says it is a test change is honest -> NOT flagged",
     {"app/limiter.py": LIM_SRC, "tests/test_limiter.py": LIM_T0}, {"tests/test_limiter.py": LIM_T1}, "PASS", forbid_rule="F_CLAIM_TEST_ONLY",
     msg="fix: update limiter test to match default behavior")
case("F: fix touching source AND test -> NOT flagged",
     {"app/limiter.py": LIM_SRC, "tests/test_limiter.py": LIM_T0}, {"app/limiter.py": LIM_SRC.replace("1", "2"), "tests/test_limiter.py": LIM_T1}, "PASS",
     forbid_rule="F_CLAIM_TEST_ONLY", msg="fix: respect env var")
case("F: test:-prefixed test-only commit -> NOT flagged",
     {"app/limiter.py": LIM_SRC, "tests/test_limiter.py": LIM_T0}, {"tests/test_limiter.py": LIM_T1}, "PASS", forbid_rule="F_CLAIM_TEST_ONLY", msg="test: add limiter coverage")
case("F: pipeline staged step (test-first scaffolding) that only adds tests -> NOT flagged",
     {"app/limiter.py": LIM_SRC, "tests/test_limiter.py": LIM_T0}, {"tests/test_limiter.py": LIM_T1}, "PASS", forbid_rule="F_CLAIM_TEST_ONLY",
     msg="feat(billwatch): staged step 0 \u2014 Add check_user_active function to app/core/dependencies.py")
case("F: CamelCase test class in the subject (honest test fix) -> NOT flagged",
     {"app/limiter.py": LIM_SRC, "tests/test_limiter.py": LIM_T0}, {"tests/test_limiter.py": LIM_T1}, "PASS", forbid_rule="F_CLAIM_TEST_ONLY",
     msg="fix(android): correct Response import in FavoritesRepositoryTest")
case("F: docs-only 'fix:' commit -> NOT flagged (not this rule's business)",
     {"README.md": "a\n", "app/limiter.py": LIM_SRC}, {"README.md": "b\n"}, "NA", forbid_rule="F_CLAIM_TEST_ONLY", msg="fix: correct the readme")

shutil.rmtree(T, ignore_errors=True)
print("\nantigaming tests: %d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
