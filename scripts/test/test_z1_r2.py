#!/usr/bin/env python3
"""Z1 review round 2 (2026-11-07) regression battery. Every group fails on the round-1 behaviour; each group also runs against an inline MUTANT of the code under test.

  A/B  ovn_retire_vague.classify: a test-creation item whose VERIFY names the SAME file in another spelling (`cd <dir> &&`), phrase forms (table-driven, parametrized, edge-case, tests for)
       and the must-NOT-be-creation forms (test case to <file>'s existing class, test data fixtures).
  C/D  ovn_placeholder_scan.py: tautologies are not real; asserts hidden in strings/comments/dead code are not real; multi-line signatures, one-liners, black-style asserts, kotlin backtick
       names / expression bodies, assertFailsWith, Swift Testing, XCTUnwrap, expect.soft, test.each templates are real; empty go/rs/java tests are not real.
  E    ovn_verify_shape_lint Q1: egrep/rg are ERE (`egrep -q '2|0'` is satisfiable), `-m1` blocks the rewrite.
  V    visibility: ovn_mutation_supply.supply_repo lints its specs (removing the call goes red); queue_refill._shape_lint_item announces a Z1 act on stderr.
"""
import contextlib
import importlib.util
import io
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SD = os.environ.get("VSL_DIR") or os.path.abspath(os.path.join(HERE, ".."))
TOP = os.path.abspath(os.path.join(SD, ".."))
sys.path.insert(0, HERE)
import tmp_track  # noqa: E402
tmp_track.install()
for _k in [k for k in os.environ if k.startswith("OVN_VERIFY_")]:
    del os.environ[_k]
WORK = tempfile.mkdtemp(prefix="z1r2-")
os.environ["OVN_DIR"] = os.path.join(WORK, "ovn")
os.environ["OVN_VERIFY_SHAPE_LOG"] = os.path.join(WORK, "state", "verify_shape_lint.log")
os.environ["OVN_VERIFY_ALERTS_LOG"] = os.path.join(WORK, "state", "alerts.log")
os.environ["OVN_VERIFY_QUARANTINE"] = os.path.join(WORK, "state", "q.md")
sys.path.insert(0, SD)
sys.path.insert(0, TOP)

PASS = FAIL = 0


def ok(name, cond, extra=""):
    global PASS, FAIL
    if cond:
        PASS += 1
    else:
        FAIL += 1
        print("  FAIL %s %s" % (name, extra))


def load(src_path, text=None, name="m"):
    """import a module from a file, optionally from mutated text"""
    p = src_path
    if text is not None:
        p = os.path.join(WORK, "%s_%d.py" % (name, abs(hash(text)) % 10 ** 8))
        open(p, "w").write(text)
    sp = importlib.util.spec_from_file_location(name, p)
    m = importlib.util.module_from_spec(sp)
    sp.loader.exec_module(m)
    return m


def mutate(path, old, new, count=1):
    s = open(path).read()
    if s.count(old) != 1:
        ok("mutant hunk applies once: %r" % old[:50], False, "count=%d" % s.count(old))
        return None
    return s.replace(old, new, 1)


# ============================ C / D: placeholder scanner ============================
SCAN = os.path.join(SD, "ovn_placeholder_scan.py")
PH = "Placeholder - the implement step fills this in."


def scan(path, src, scanner=SCAN):
    return subprocess.run([sys.executable, scanner, path, PH], input=src, capture_output=True, text=True, timeout=60).stdout.strip()


C=[]
def c(name,path,src,exp): C.append((name,path,src,exp))
P='"""'+PH+'"""\n'
# python real
c("py multiline sig","test_a.py",P+"def test_a(\n    a,\n    b,\n):\n    assert foo(a) == b\n","real")
c("py oneliner","test_a.py",P+"def test_a(): assert foo() == 3\n","real")
c("py black assert","test_a.py",P+"def test_a():\n    assert (\n        foo() == 3\n    )\n","real")
c("py raises","test_a.py",P+"def test_a():\n    with pytest.raises(ValueError):\n        foo()\n","real")
c("py self.assertEqual","test_a.py",P+"class T(unittest.TestCase):\n    def test_a(self):\n        self.assertEqual(foo(), 3)\n","real")
c("py async","test_a.py",P+"async def test_a():\n    assert await foo() == 3\n","real")
c("py marker code line","test_a.py","def test_a():\n    assert foo()==3  # "+PH+"\n","real")
c("py skipif cond real","test_a.py",P+"@pytest.mark.skipif(sys.platform=='win32', reason='x')\ndef test_a():\n    assert foo()==3\n","real")
# python stub
for nm,body in [("1==1","assert 1 == 1"),("x==x","assert x == x"),("[]==[]","assert [] == []"),("str==str","assert 'x' == 'x'"),("5 is not None","assert 5 is not None"),
  ("or True","assert foo or True"),("isinstance const","assert isinstance(1, int)"),("assertEqual 1,1","self.assertEqual(1, 1)"),("assertTrue(1==1)","self.assertTrue(1 == 1)"),
  ("assertIsNone(None)","self.assertIsNone(None)"),("assertTrue str",'self.assertTrue("x")'),("assert True","assert True"),("tuple","assert (x, 'm')"),("pass","pass"),
  ("if False","if False:\n        assert foo()==3"),("while 0","while 0:\n        assert foo()==3"),("after return","return\n    assert foo()==3"),
  ("docstring assert","'''\n    assert foo()==3\n    '''"),("comment","# assert foo()==3"),("str","x = 'assert foo()==3'"),("pytest.skip","pytest.skip('x')\n    assert foo()==3"),
  ("nested def never called","def helper():\n        assert foo()==3")]:
    pre="class T(unittest.TestCase):\n    pass\n" if False else ""
    c("py stub "+nm,"test_a.py",P+"def test_a(self):\n    "+body+"\n","stub")
c("py multi-line skip","test_a.py",P+"@pytest.mark.skip(\n    reason='x'\n)\ndef test_a():\n    assert foo()==3\n","stub")
c("py pytestmark","test_a.py",P+"pytestmark = pytest.mark.skip\ndef test_a():\n    assert foo()==3\n","stub")
c("py __test__","test_a.py",P+"__test__ = False\ndef test_a():\n    assert foo()==3\n","stub")
c("py unittest.skip cls","test_a.py",P+"@unittest.skip('x')\nclass T(unittest.TestCase):\n    def test_a(self):\n        self.assertEqual(foo(),3)\n","stub")
c("py nested called","test_a.py",P+"def test_a():\n    def h():\n        assert foo()==3\n    h()\n","real")
c("py only stub","test_a.py",P,"stub")
# ts
T="// "+PH+"\n"
c("ts expect.soft","a.spec.ts",T+"test('a', async () => {\n  expect.soft(f()).toBe(3)\n})\n","real")
c("ts test.each template","a.spec.ts",T+"test.each`\n a | b\n ${1} | ${2}\n`('x $a', ({a,b}) => {\n  expect(f(a)).toBe(b)\n})\n","real")
c("ts it placeholder title","a.spec.ts",T+"it('renders the placeholder text', () => {\n  expect(f()).toBe(3)\n})\n","real")
c("ts it.each arr","a.spec.ts",T+"it.each([[1,2]])('x %i', (a,b) => {\n  expect(f(a)).toBe(b)\n})\n","real")
c("ts one-liner","a.spec.ts",T+"it('a', () => expect(f()).toBe(3))\n","real")
for nm,body in [("x toBe x","expect(x).toBe(x)"),("1+1 toBe 2","expect(1+1).toBe(2)"),("false false","expect(false).toBe(false)"),("1 defined","expect(1).toBeDefined()"),
  ("true true","expect(true).toBe(true)"),("block comment","/* expect(f()).toBe(3) */"),("multi block","/*\n expect(f()).toBe(3)\n*/"),("string","const s = 'expect(f()).toBe(3)'"),
  ("template","const s = `expect(f()).toBe(3)`"),("if false","if (false) { expect(f()).toBe(3) }"),("bare expect","expect(f())")]:
    c("ts stub "+nm,"a.spec.ts",T+"it('a', () => {\n  "+body+"\n})\n","stub")
c("ts describe.skip","a.spec.ts",T+"describe.skip('a', () => { it('b', () => { expect(f()).toBe(3) }) })\n","stub")
c("ts it.skip","a.spec.ts",T+"it.skip('b', () => { expect(f()).toBe(3) })\n","stub")
c("ts test.todo","a.spec.ts",T+"test.todo('b')\n","stub")
c("ts expect outside","a.spec.ts",T+"expect(f()).toBe(3)\n","stub")
c("ts harness stub","a.test.ts",T+"import { describe, it } from 'vitest'\ndescribe.skip('placeholder x', () => {\n  it('placeholder', () => {})\n})\n","stub")
c("ts real after skipped","a.spec.ts",T+"describe.skip('a', () => { it('b', () => { expect(f()).toBe(3) }) })\nit('c', () => { expect(g()).toBe(1) })\n","real")
# gd
G="# "+PH+"\nextends GutTest\n"
c("gd real","test_a.gd",G+"func test_a():\n\tassert_eq(f(), 3)\n","real")
for nm,body in [("assert_eq 1 1","assert_eq(1,1)"),("assert_true 1==1","assert_true(1==1)"),("assert_false false","assert_false(false)"),("assert_not_null str","assert_not_null('x')"),
  ("assert_gt 1 0","assert_gt(1,0)"),("pass","pass"),("str","var s = 'assert_eq(f(),3)'"),("comment","# assert_eq(f(), 3)"),("if false","if false:\n\t\tassert_eq(f(),3)"),("pending","pending('x')\n\tassert_eq(f(),3)")]:
    c("gd stub "+nm,"test_a.gd",G+"func test_a():\n\t"+body+"\n","stub")
# kt
K="// "+PH+"\nimport org.junit.Test\nclass A {\n"
c("kt backtick","ATest.kt",K+"  @Test\n  fun `does a thing`() {\n    assertEquals(3, f())\n  }\n}\n","real")
c("kt expr body","ATest.kt",K+"  @Test fun a() = assertEquals(3, f())\n}\n","real")
c("kt assertFailsWith","ATest.kt",K+"  @Test\n  fun a() {\n    assertFailsWith<IllegalStateException> { f() }\n  }\n}\n","real")
c("kt mockk verify","ATest.kt",K+"  @Test\n  fun a() {\n    f()\n    verify { m.go() }\n  }\n}\n","real")
c("kt tautology","ATest.kt",K+"  @Test\n  fun a() {\n    assertEquals(1, 1)\n  }\n}\n","stub")
c("kt assertTrue(true)","ATest.kt",K+"  @Test\n  fun a() {\n    assertTrue(true)\n  }\n}\n","stub")
c("kt leak helper","ATest.kt",K+"  @Test\n  fun a() {\n    f()\n  }\n  fun helper() {\n    assertEquals(3, f())\n  }\n}\n","stub")
c("kt string","ATest.kt",K+"  @Test\n  fun a() {\n    val s = \"assertEquals(3, f())\"\n  }\n}\n","stub")
c("kt block comment","ATest.kt",K+"  @Test\n  fun a() {\n    /* assertEquals(3, f()) */\n  }\n}\n","stub")
c("kt @Ignore","ATest.kt",K+"  @Test @Ignore\n  fun a() {\n    assertEquals(3, f())\n  }\n}\n","stub")
c("kt class ignore","ATest.kt","// "+PH+"\n@Ignore\nclass A {\n  @Test\n  fun a() {\n    assertEquals(3, f())\n  }\n}\n","stub")
# swift
W="// "+PH+"\nimport XCTest\n"
c("swift XCTAssert","AFooTests.swift",W+"class A: XCTestCase {\n  func testA() {\n    XCTAssertEqual(f(), 1)\n  }\n}\n","real")
c("swift Testing @Test","AFooTests.swift",W+"struct A {\n  @Test func a() {\n    #expect(f() == 1)\n  }\n}\n","real")
c("swift Testing named","AFooTests.swift",W+"struct A {\n  @Test(\"x\") func `does it`() {\n    #expect(f() == 1)\n  }\n}\n","real")
c("swift XCTUnwrap","AFooTests.swift",W+"class A: XCTestCase {\n  func testA() throws {\n    _ = try XCTUnwrap(f())\n  }\n}\n","real")
c("swift XCTAssertEqual 1 1","AFooTests.swift",W+"class A: XCTestCase {\n  func testA() {\n    XCTAssertEqual(1, 1)\n  }\n}\n","stub")
c("swift NotNil str","AFooTests.swift",W+"class A: XCTestCase {\n  func testA() {\n    XCTAssertNotNil(\"x\")\n  }\n}\n","stub")
c("swift XCTAssert true","AFooTests.swift",W+"class A: XCTestCase {\n  func testA() {\n    XCTAssert(true)\n  }\n}\n","stub")
c("swift empty","AFooTests.swift",W+"class A: XCTestCase {\n  func testA() {\n  }\n}\n","stub")
c("swift XCTSkip","AFooTests.swift",W+"class A: XCTestCase {\n  func testA() throws {\n    throw XCTSkip(\"x\")\n    XCTAssertEqual(f(), 1)\n  }\n}\n","stub")
c("swift disabled","AFooTests.swift",W+"struct A {\n  @Test(.disabled(\"x\")) func a() {\n    #expect(f() == 1)\n  }\n}\n","stub")
# go/rs/java
c("go empty","a_test.go","// "+PH+"\npackage a\nimport \"testing\"\nfunc TestA(t *testing.T) {}\n","stub")
c("go real","a_test.go","// "+PH+"\npackage a\nimport \"testing\"\nfunc TestA(t *testing.T) {\n if f() != 3 {\n  t.Errorf(\"bad\")\n }\n}\n","real")
c("go skip","a_test.go","// "+PH+"\npackage a\nimport \"testing\"\nfunc TestA(t *testing.T) {\n t.Skip(\"x\")\n t.Error(\"x\")\n}\n","stub")
c("rs empty","tests/a.rs","// "+PH+"\nuse x;\n#[test]\nfn a() {}\n","stub")
c("rs assert true","tests/a.rs","// "+PH+"\nuse x;\n#[test]\nfn a() {\n assert!(true);\n}\n","stub")
c("rs real","tests/a.rs","// "+PH+"\nuse x;\n#[test]\nfn a() {\n assert_eq!(f(), 3);\n}\n","real")
c("rs ignore","tests/a.rs","// "+PH+"\nuse x;\n#[test]\n#[ignore]\nfn a() {\n assert_eq!(f(), 3);\n}\n","stub")
c("java empty","ATest.java","// "+PH+"\nimport org.junit.Test;\nclass ATest {\n @Test public void a() {}\n}\n","stub")
c("java assertTrue true","ATest.java","// "+PH+"\nimport org.junit.Test;\nclass ATest {\n @Test public void a() { assertTrue(true); }\n}\n","stub")
c("java real","ATest.java","// "+PH+"\nimport org.junit.Test;\nclass ATest {\n @Test public void a() { assertEquals(3, f()); }\n}\n","real")
c("java Ignore","ATest.java","// "+PH+"\nimport org.junit.Test;\nclass ATest {\n @Ignore @Test public void a() { assertEquals(3, f()); }\n}\n","stub")
c("java Test(expected)","ATest.java","// "+PH+"\nimport org.junit.Test;\nclass ATest {\n @Test(expected = X.class) public void a() { assertThat(f(), is(3)); }\n}\n","real")
# non-test 3 lines
c("src 3 lines","src.py",P+"x = 1\ny = 2\nz = 3\n","real")
c("src stub","src.py",P+"import os\npass\n","stub")


def battery(scanner):
    return [n for n, p, s, e in C if scan(p, s, scanner) != e]


bad = battery(SCAN)
ok("scanner battery: %d cases, wrong verdicts: %s" % (len(C), bad), not bad)
PASS += len(C) - len(bad) - 1   # per-case credit

MUT = [
    ("python ast scan disabled (line heuristic only)", "    try:\n        tree = ast.parse(text)", "    return None\n    try:\n        tree = ast.parse(text)", 8),
    ("tautology check disabled (non-python)", "    if _ALWAYS.search(stem):\n        return False\n    if not args:", "    if True:\n        return False\n    if not args:", 8),
    ("python tautology check disabled", "def _trivial_test(e):\n    if _no_source(e):", "def _trivial_test(e):\n    if e is None:\n        return True\n    if False:", 3),
    ("strings/comments not blanked", "def blank_src(text, lang):", "def blank_src(text, lang):\n    return text, text", 6),
    ("skipped ts regions not blanked", "        if (set(mods) & _TS_SKIP_MODS) or name.startswith(\"x\"):", "        if False:", 1),
    ("@Ignore/@Disabled/#[ignore]/.disabled headers not honoured", "        if ig and ig.search(header):", "        if False:", 3),
    ("go/java/rust not test kinds", "    if ext == \".go\" and b.endswith(\"_test.go\"):\n        return \"go\"", "    if False:\n        return \"go\"", 1),
]
base_src = open(SCAN).read()
for name, old, new, need in MUT:
    t = mutate(SCAN, old, new)
    if t is None:
        continue
    mp = os.path.join(WORK, "scan_mut.py")
    open(mp, "w").write(t)
    flips = battery(mp)
    ok("scanner mutant '%s' is caught (%d verdict(s) flip, need >= %d)" % (name, len(flips), need), len(flips) >= need)

# ============================ A / B: retire_vague ============================
RV = os.path.join(SD, "ovn_retire_vague.py")
_cwd = os.getcwd()
os.chdir(tempfile.mkdtemp(prefix="z1r2rv-", dir=WORK))
RCASES = [
    ("A backend cd subdir", "- [ ] [T2] backend/tests/test_flush_due_held.py - Add test case verifying x VERIFY: `cd backend && .venv/bin/pytest -q tests/test_flush_due_held.py::test_x` (cat:test; multifile:no)", None),
    ("A billwatch FollowingView (live item)", "- [ ] [T2] billwatch-web/src/views/__tests__/FollowingView.error.test.ts - Add test case ... VERIFY: `cd billwatch-web && npx vitest run src/views/__tests__/FollowingView.error.test.ts`", None),
    ("A TAA testRuns.spec (live item)", "- [ ] [T2] frontend/src/stores/__tests__/testRuns.spec.js - Add a test case ... VERIFY: `cd frontend && npx vitest run src/stores/__tests__/testRuns.spec.js`", None),
    ("A reverse spelling", "- [ ] [T2] tests/test_x.py - Add test case y VERIFY: `cd backend && pytest backend/tests/test_x.py`", None),
    ("A a DIFFERENT dead verify path still retires", "- [ ] [T2] tests/test_x.py - Add test case y VERIFY: `pytest other/dead_test.py`", "dead-path"),
    ("A impl item with a cd VERIFY still retires", "- [ ] [T2] src/impl.py - Add retry VERIFY: `cd src && pytest tests/test_x.py`", "dead-path"),
    ("B table-driven unit tests", "- [ ] [T2] tests/test_x.py - Add table-driven unit tests for y VERIFY: `pytest tests/test_x.py`", None),
    ("B parametrized tests", "- [ ] [T2] tests/test_x.py - Add parametrized tests for y", None),
    ("B edge-case tests", "- [ ] [T2] tests/test_x.py - Add edge-case tests for y", None),
    ("B Add tests for", "- [ ] [T2] tests/test_x.py - Add tests for y", None),
    ("B integration tests", "- [ ] [T2] tests/test_x.py - Add integration tests for y", None),
    ("B test case to existing class is NOT creation", "- [ ] [T2] tests/test_gone.py - Add a test case to test_gone.py's existing TestX class", "dead-path"),
    ("B test data fixtures is NOT creation", "- [ ] [T2] tests/test_gone.py - Add test data fixtures to the test module", "dead-path"),
    ("B missing assertion to existing test is NOT creation", "- [ ] [T2] tests/test_gone.py - Add a missing assertion to the existing test", "dead-path"),
    ("B co-listed dead non-test path", "- [ ] [T2] tests/test_x.py and src/dead.py - Add tests for y", "dead-path"),
]


def rv_battery(mod):
    return [n for n, l, e in RCASES if mod.classify(l) != e]


rv = load(RV, name="rv_real")
bad = rv_battery(rv)
ok("retire_vague battery: %d cases, wrong: %s" % (len(RCASES), bad), not bad)
PASS += len(RCASES) - len(bad) - 1
RMUT = [
    ("VERIFY-side spelling not excused", "excused = _excuse_spellings(slash_paths, made)", "excused = set(slash_paths) & made", 4),
    ("no hyphen/word modifiers", "|table[- ]driven|parametri[sz]ed|parameteri[sz]ed|edge[- ]cases?|boundary|happy[- ]path|negative|error[- ]path|async|snapshot|property[- ]based|component|api|end[- ]to[- ]end", "", 3),
    ("`test data` / fixtures allowed as creation", "|data|datas?|utils?|utilities|harness|infra|setup|config)", ")", 1),
    ("existing-class guard removed", "(?!\\s+(?:to|in|into|for|of|on)\\s+(?:[^\\s]+\\s+){0,3}?existing\\b)", "", 1),
    ("prefix guard removed (test case -> test)", "(?!\\s+(?:cases?|files?|suite|module)\\b)", "", 1),
]
for name, old, new, need in RMUT:
    t = mutate(RV, old, new)
    if t is None:
        continue
    flips = rv_battery(load(RV, t, "rv_mut"))
    ok("retire_vague mutant '%s' is caught (%d flip, need >= %d)" % (name, len(flips), need), len(flips) >= need)
os.chdir(_cwd)

# ============================ E: Q1 egrep / rg / -m ============================
import ovn_verify_shape_lint as L  # noqa: E402


def q1(clause):
    return [f for f in L.lint_verify(clause, None)["findings"] if f["code"] == "Q1"]


def q1_cases(mod):
    out = []
    for nm, cl, want in [
        ("egrep ERE", 'grep -q "x" f.py | wc -l | egrep -q \'2|0\'', False),
        ("rg ERE", 'grep -q "x" f.py | wc -l | rg -q \'2|0\'', False),
        ("plain grep BRE still flagged", 'grep -q "x" f.py | wc -l | grep -q \'2|0\'', True),
        ("grep -E not flagged", 'grep -q "x" f.py | wc -l | grep -E -q \'2|0\'', False),
        ("plain count still flagged", 'grep -q "x" f.py | wc -l | grep -q 2', True),
    ]:
        if bool([f for f in mod.lint_verify(cl, None)["findings"] if f["code"] == "Q1"]) != want:
            out.append(nm)
    for nm, cl in [("-m1", 'grep -q -m1 "x" f.py | wc -l | grep -q 1'), ("-m 1", 'grep -q -m 1 "x" f.py | wc -l | grep -q 1'), ("rg", 'rg -q "x" f.py | wc -l | grep -q 2')]:
        fs = [f for f in mod.lint_verify(cl, None)["findings"] if f["code"] == "Q1"]
        if not fs or fs[0].get("rewrite"):
            out.append("rewrite-blocked " + nm)
    fs = [f for f in mod.lint_verify('grep -q "x" f.py | wc -l | grep -q 2', None)["findings"] if f["code"] == "Q1"]
    if not fs or not fs[0].get("rewrite"):
        out.append("plain rewrite still offered")
    return out


bad = q1_cases(L)
ok("Q1 egrep/rg/-m battery wrong: %s" % bad, not bad)
VSL = os.path.join(SD, "ovn_verify_shape_lint.py")
for name, old, new in [
    ("egrep/rg not ERE", '    if prog in ("egrep", "rg"):\n        flags.add("E")', '    if False:\n        flags.add("E")'),
    ("-m not recorded", '                    flags.add("m")      #', '                    pass      #'),
    ("rewrite for non-grep programs", 'and g0["prog"] == "grep" and "m" not in g0["flags"]:', ":"),
]:
    t = mutate(VSL, old, new)
    if t is None:
        continue
    flips = q1_cases(load(VSL, t, "vsl_mut"))
    ok("Q1 mutant '%s' is caught (%s)" % (name, flips), bool(flips))

# ============================ V: visibility ============================
Q1LINE = '- [ ] [T2] scripts/units/a.gd \u2014 add a test. VERIFY: `grep -q "x_call" scripts/units/a.gd | wc -l | grep -q 2`. (cat:test; multifile:no; supply:gd-mutation-survivor) [feat:x]'
os.environ["OVN_VERIFY_Z1_Q1"] = "enforce"
os.makedirs(os.path.join(WORK, "ovn", "repos", "xlite"), exist_ok=True)
os.makedirs(os.path.join(WORK, "ovn", "backlog"), exist_ok=True)
import ovn_work_supply as ws  # noqa: E402
ws.render = lambda sp, repo: Q1LINE
ws.spec_check = lambda repo, lines: {i: "red" for i in range(len(lines))}
ws._filter = lambda *a, **k: None
ws.pullable_count = lambda *a, **k: 0
ws._load_banned = lambda root: []
ws.frozen_paths = lambda root: []
MS = os.path.join(SD, "ovn_mutation_supply.py")


def supply_with(mod):
    mod.survivor_specs = lambda root: [{"file": "scripts/units/a.gd", "text": "t", "verify": "v", "kind": "gd-mutation-survivor", "tier": "T2", "cat": "test"}]
    out = []
    got = mod.supply_repo("xlite", mode="shadow", now=1.0, out=lambda *a: None)
    return got


real_ms = load(MS, name="ms_real")
got = supply_with(real_ms)
ok("mutation supply: the Q1 spec is linted (rewritten to a count test): %r" % got, len(got) == 1 and "-eq 2" in got[0] and "wc -l" not in got[0])
t = mutate(MS, "keep = ws._shape_lint_keep(keep, root, repo)[:topn]", "keep = keep[:topn]")
if t is not None:
    got = supply_with(load(MS, t, "ms_mut"))
    ok("mutation supply mutant (lint call removed) is caught: %r" % got, len(got) == 1 and "wc -l" in got[0])

import queue_refill as QR  # noqa: E402


def refill_stderr(mod):
    buf = io.StringIO()
    with contextlib.redirect_stderr(buf):
        out = mod._shape_lint_item(Q1LINE, Q1LINE, SD, [], [])
    return buf.getvalue(), out


err, out = refill_stderr(QR)
ok("queue_refill: a Z1 rewrite is announced on stderr: %r" % err, "verify-lint(Z1): REWRITTEN" in err and "queue_refill" in err and out != Q1LINE)
QRP = os.path.join(TOP, "queue_refill.py")
t = mutate(QRP, '        _VSL.announce(l2, d, res, os.path.basename(os.path.abspath(repo_root)), "queue_refill")', "        pass")
if t is not None:
    qm = load(QRP, t, "qr_mut")
    err2, _ = refill_stderr(qm)
    ok("queue_refill mutant (announce removed) is caught", "verify-lint(Z1)" not in err2)

print("test_z1_r2: %d passed, %d failed" % (PASS, FAIL))
sys.exit(1 if FAIL else 0)
