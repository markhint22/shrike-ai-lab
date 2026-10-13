#!/usr/bin/env python3
"""Package `stage` (2026-10-13): unit tests for scripts/ovn_stage_guards.py - the deterministic guards the staged runner and the implement step use.

  xlite F3   step-mistarget / item-mistarget: the live item `[T5] scripts/mission/save_slot_select.gd - Verify no other suffixes are missing by checking codex_manager.gd usage.
             VERIFY: grep "CODEX_SAVE_NAME" scripts/mission/codex_manager.gd | grep -q "codex"` (the real module is scripts/codex/codex_manager.gd; the staged runner CREATED the wrong path)
  iptv F2    named-tests / resolve-tests: `Add test test_cancel_subscription_rate_limit` - the repair round deleted the test and the item was still credited
  xlite F7   create-exists: `Create a GDScript test file ...` whose target already exists with its test functions
  iptv F6    new-tests: the python test functions a diff added (input of the red-before shadow check)
Mutations are proved in a scratch copy (see the package report): each guard function replaced by `return None` / `(False, ...)` fails the matching block.
"""
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
import ovn_stage_guards as G  # noqa: E402

P = F = 0


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name + ((" :: " + str(extra)[:300]) if extra else ""))


def mk(root, rel, text=""):
    p = os.path.join(root, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w") as f:
        f.write(text)
    return p


ITEM_F3 = ('- [ ] [T5] scripts/mission/save_slot_select.gd — Verify no other suffixes are missing by checking codex_manager.gd usage. '
           'VERIFY: `grep "CODEX_SAVE_NAME" scripts/mission/codex_manager.gd | grep -q "codex"`. (cat:godot; multifile:no) [feat:xlite-20261013-fix-slot-deletion-leaving-codex-save-on-]')

wt = tempfile.mkdtemp(prefix="sg-")
mk(wt, "scripts/mission/save_slot_select.gd", "extends Node\n")
mk(wt, "scripts/codex/codex_manager.gd", 'const CODEX_SAVE_NAME := "codex"\n')

print("== xlite F3: a Verify step naming a file that does not exist is MIS-TARGETED")
r = G.step_mistarget(wt, "Verify the presence of the CODEX_SAVE_NAME constant", ["scripts/mission/codex_manager.gd"])
ok("Verify step + missing production file -> refused", bool(r) and "scripts/mission/codex_manager.gd" in r, r)
ok("Check / Confirm are read-only verbs too", bool(G.step_mistarget(wt, "Check the constant", ["nope.gd"])) and bool(G.step_mistarget(wt, "confirm the signature", ["nope.gd"])))
ok("Verify step on an EXISTING file -> fine", G.step_mistarget(wt, "Verify the presence of the constant", ["scripts/codex/codex_manager.gd"]) is None)
ok("an Add step naming a new file -> fine (creating is its job)", G.step_mistarget(wt, "Add the CODEX_SAVE_NAME constant", ["scripts/mission/codex_manager.gd"]) is None)
ok("a Verify step may add a TEST file (test path is exempt)", G.step_mistarget(wt, "Verify the cap with a test", ["tests/test_codex.gd"]) is None and G.step_mistarget(wt, "Verify X", ["backend/tests/test_x.py"]) is None)
ok("a Verify step with a missing source AND a new test is still refused", bool(G.step_mistarget(wt, "Verify X", ["scripts/gone.gd", "tests/test_x.gd"])))
ok("a Verify step with no files at all is not judged", G.step_mistarget(wt, "Verify X", []) is None)
ok("leading whitespace / lower case verb", bool(G.step_mistarget(wt, "  verify the thing", ["gone.py"])))

print("== xlite F3: an item whose VERIFY greps a non-existent target is mis-targeted")
r = G.item_mistarget(wt, ITEM_F3)
ok("live item -> mis-targeted (scripts/mission/codex_manager.gd does not exist)", bool(r) and "scripts/mission/codex_manager.gd" in r, r)
ok("same item aimed at the REAL path -> fine", G.item_mistarget(wt, ITEM_F3.replace("scripts/mission/codex_manager.gd", "scripts/codex/codex_manager.gd")) is None)
ITEM_CREATE = '- [ ] [T3] scripts/mission/codex_manager.gd — Add the CODEX_SAVE_NAME constant. VERIFY: `grep -q "CODEX_SAVE_NAME" scripts/mission/codex_manager.gd` (cat:godot)'
ok("an item that CREATES the grepped file is fine", G.item_mistarget(wt, ITEM_CREATE) is None)
ok("... but 'Update' (not a create verb) on a missing file is mis-targeted", bool(G.item_mistarget(wt, ITEM_CREATE.replace("Add the", "Update the"))))
ITEM_NEG = '- [ ] [T3] scripts/mission/gone.gd — Delete it. VERIFY: `grep -rn "Gone" scripts/mission/gone.gd` returns nothing.'
ok("a delete / absence item is never judged", G.item_mistarget(wt, ITEM_NEG) is None)
ok("an absence narration on a missing file is never judged (polarity neg)", G.item_mistarget(wt, '- [ ] [T3] a.gd — Fix. VERIFY: `grep -n X scripts/missing.gd` returns no matches.') is None)
ok("pytest / runner VERIFY is not judged", G.item_mistarget(wt, '- [ ] [T3] a.py — Fix. VERIFY: `pytest tests/test_gone.py -q` (cat:python)') is None)
ok("a glob / absolute path operand is never judged", G.item_mistarget(wt, '- [ ] [T3] a.py — Fix. VERIFY: `grep -rn X scripts/*/foo.gd` (cat:x)') is None and G.item_mistarget(wt, '- [ ] [T3] a.py — Fix. VERIFY: `grep -rn X /etc/hostname` (cat:x)') is None)
ok("cd <dir> && grep file: base directory honoured (exists)", G.item_mistarget(wt, '- [ ] [T3] a.py — Fix. VERIFY: `cd scripts/codex && grep -q CODEX codex_manager.gd` (cat:x)') is None)
ok("cd <dir> && grep file: base directory honoured (missing)", bool(G.item_mistarget(wt, '- [ ] [T3] a.py — Fix. VERIFY: `cd scripts/mission && grep -q CODEX codex_manager.gd` (cat:x)')))
ok("grep -e PATTERN file: the pattern is not an operand", G.item_mistarget(wt, '- [ ] [T3] a.py — Fix. VERIFY: `grep -rn -e CODEX_SAVE_NAME scripts/codex/` (cat:x)') is None)
ok("grep -rn PATTERN dir with a missing dir", bool(G.item_mistarget(wt, '- [ ] [T3] a.py — Fix. VERIFY: `grep -rn CODEX scripts/missing_dir/` (cat:x)')))
ok("no VERIFY -> not judged", G.item_mistarget(wt, "- [ ] [T3] a.py — Fix it. (cat:x)") is None)
ok("grep operands: options with args are skipped (-A 3, --include=*.py)", G.grep_file_operands("grep -rn -A 3 --include=*.py FOO src/ lib/") == ["src/", "lib/"], G.grep_file_operands("grep -rn -A 3 --include=*.py FOO src/ lib/"))
ok("grep operands: a pipeline stage without a file has none", G.grep_file_operands("grep -q codex") == [])

print("== reviewer defect 1: no false mis-target on narration / non-path tokens (replayed from the live queue)")
wt1 = tempfile.mkdtemp(prefix="sg1-")
mk(wt1, "scripts/battle/aoe_targeting.gd", "extends Node\n")
mk(wt1, "iptv-backend/app/services/stream_checker.py", "def f():\n    pass\n")
mk(wt1, "iptv-backend/tests/test_parental_controls.py", "def test_a():\n    pass\n")
# xlite 2122-2124: a BARE (not backticked) VERIFY whose narration words used to be read as file operands
BARE_2122 = '- [x] (already-done, scout-verified) [T2] scripts/battle/aoe_targeting.gd \u2014 Replace the call at line 36 with `GridDistance.chebyshev(...)`. VERIFY: grep -n "GridDistance" scripts/battle/aoe_targeting.gd shows a match near line 36. (cat:godot; multifile:no)'
BARE_2123 = '- [ ] [T3] scripts/battle/aoe_targeting.gd \u2014 Replace the call at line 41 with `GridDistance.chebyshev(...)`. VERIFY: grep -n "GridDistance" scripts/battle/aoe_targeting.gd shows a match near line 41. (cat:godot; multifile:no)'
BARE_2124 = '- [x] [T4] scripts/battle/aoe_targeting.gd \u2014 Ensure `GridDistance` is preloaded at the top. VERIFY: grep -n "preload.*grid_distance" scripts/battle/aoe_targeting.gd returns a match. (cat:godot; multifile:no)'
for nm, it in (("xlite 2122", BARE_2122), ("xlite 2123", BARE_2123), ("xlite 2124", BARE_2124)):
    ok(nm + ": bare VERIFY narration is never read as file operands", G.item_mistarget(wt1, it) is None, G.item_mistarget(wt1, it))
IPTV_924 = ('- [x] [T4] iptv-backend/app/services/stream_checker.py \u2014 Refactor existing retry logic to use `get_backoff_delay`. '
            'VERIFY: grep -c "time.sleep" iptv-backend/app/services/stream_checker.py returns 0 (non-retry sleeps only). (cat:python; multifile:no)')
ok("iptv 924: 'returns 0 (non-retry sleeps only)' is narration, not operands", G.item_mistarget(wt1, IPTV_924) is None, G.item_mistarget(wt1, IPTV_924))
IPTV_1220 = ('- [x] [T3] iptv-backend/app/services/stream_checker.py \u2014 Wire it. '
             'VERIFY: grep -n "get_similar_to" iptv-backend/app/services/stream_checker.py (currently 0 matches; expect 2 calls it matches). (cat:python; multifile:no)')
ok("iptv 1220: '(currently 0 matches; expect ...)' is narration", G.item_mistarget(wt1, IPTV_1220) is None, G.item_mistarget(wt1, IPTV_1220))
IPTV_1206 = '- [x] [T2] iptv-backend/app/services/parental.py \u2014 Fix it. VERIFY: grep -q "foo" iptv-backend/app/services/parental.py. (cat:python)'
ok("iptv 1206: a trailing-period bare operand is not judged", G.item_mistarget(wt1, IPTV_1206) is None, G.item_mistarget(wt1, IPTV_1206))
IPTV_1063 = ('- [x] [T3] iptv-backend/tests/test_parental_controls.py \u2014 Confirm no other test functions in the file. '
             'VERIFY: diff <(grep -o "^def test_" iptv-backend/tests/test_parental_controls.py) /dev/null (cat:python)')
ok("iptv 1063: a process-substitution fragment is not an operand", G.item_mistarget(wt1, IPTV_1063) is None, G.item_mistarget(wt1, IPTV_1063))
ok("looks_like_path: narration words / numbers / punctuation tokens are not paths", not any(G.looks_like_path(t) for t in ("41", "a", "line", "match", "returns", "(currently", "0", "<(grep", "parental.py.", "matches;", "non-retry")))
ok("looks_like_path: real operands are", all(G.looks_like_path(t) for t in ("a/b.gd", "codex_manager.gd", "src/", "Makefile.in", "iptv-backend/tests")))
ok("a BARE VERIFY on a really missing file is still not judged (only a backticked clause is)", G.item_mistarget(wt1, BARE_2122.replace("scripts/battle/aoe_targeting.gd shows", "scripts/mission/ghost.gd shows")) is None)
ok("a backticked clause naming a missing path with trailing narration is still caught",
   bool(G.item_mistarget(wt1, '- [ ] [T3] scripts/battle/aoe_targeting.gd \u2014 Fix it. VERIFY: `grep -n "X" scripts/mission/ghost.gd` shows a match near line 41. (cat:godot)')))
ok("count-based absence check (`| wc -l` returns 0) over a missing config file is not a mis-aim (xlite DONE:333)",
   G.item_mistarget(wt1, '- [x] [T5] tests/t.gd \u2014 Verify the config does not list it. VERIFY: `grep -r "test_loadout_preset" project.gut.cfg .gutconfig.yml 2>/dev/null | wc -l` returns 0. (cat:test)') is None)
ok("grep -s / 2>/dev/null tolerate a missing operand", G.item_mistarget(wt1, '- [ ] [T5] tests/t.gd \u2014 Check it. VERIFY: `grep -qs "x" gone/file.cfg` (cat:test)') is None and G.item_mistarget(wt1, '- [ ] [T5] tests/t.gd \u2014 Check it. VERIFY: `grep -q "x" gone/file.cfg 2>/dev/null` (cat:test)') is None)

print("== second review (minor 3): VERIFY shapes that are not mis-aims")
wt4 = tempfile.mkdtemp(prefix="sg6-")
mk(wt4, "app/b.py", "def f():\n    pass\n")
mk(wt4, "billwatch-backend/app/services/vote_sync_service.py", "def sync():\n    pass\n")
mk(wt4, "scripts/a.gd", "extends Node\n")
def _it(cmd, tgt="scripts/a.gd", verb="Fix it"):
    return '- [ ] [T3] %s \u2014 %s. VERIFY: `%s`. (cat:x)' % (tgt, verb, cmd)
ok("shape 1: `grep -q X app/a.py || grep -q X app/b.py` with a.py missing and b.py present is an alternative, not a mis-aim",
   G.item_mistarget(wt4, _it('grep -q X app/a.py || grep -q X app/b.py')) is None, G.item_mistarget(wt4, _it('grep -q X app/a.py || grep -q X app/b.py')))
ok("shape 1 (other order): the missing file second", G.item_mistarget(wt4, _it('grep -q X app/b.py || grep -q X app/a.py')) is None)
ok("shape 2a: `grep -q X missing.py && echo FAIL || echo PASS` is an absence check",
   G.item_mistarget(wt4, _it('grep -q X scripts/missing.gd && echo FAIL || echo PASS')) is None)
ok("shape 2b: `grep -q X missing.py; test $? -ne 0` inspects the exit status explicitly",
   G.item_mistarget(wt4, _it('grep -q X scripts/missing.gd; test $? -ne 0')) is None)
ok("shape 2c: a negated `! grep -q X missing.py`", G.item_mistarget(wt4, _it('! grep -q X scripts/missing.gd')) is None)
ok("shape 3: a package-relative VERIFY (item billwatch-backend/app/..., greps app/services/...) is not a mis-aim",
   G.item_mistarget(wt4, _it('grep -q sync app/services/vote_sync_service.py', tgt="billwatch-backend/app/services/vote_sync_service.py")) is None)
# controls: the guard still fires on the real mis-aims next to those shapes
ok("control: a plain presence check on a missing file still fires", bool(G.item_mistarget(wt4, _it('grep -q X scripts/missing.gd'))))
ok("control: `grep X missing && echo PASS || echo FAIL` (found = good) is a presence check and still fires",
   bool(G.item_mistarget(wt4, _it('grep -q X scripts/missing.gd && echo PASS || echo FAIL'))))
ok("control: `|| echo` is not an alternative GREP, a missing operand still fires", bool(G.item_mistarget(wt4, _it('grep -q X scripts/missing.gd || echo missing'))))
ok("documented limit: two grep alternatives that are BOTH missing are not judged (shadow log noise over a false park; the VERIFY itself fails and the item guard handles it)",
   G.item_mistarget(wt4, _it('grep -q X app/a.py || grep -q X app/c.py')) is None)
ok("control: the package-dir retry needs the file to exist there (app/services/gone.py is a mis-aim)",
   bool(G.item_mistarget(wt4, _it('grep -q sync app/services/gone.py', tgt="billwatch-backend/app/services/vote_sync_service.py"))))
ok("control: the live F3 item is unaffected by the package-dir retry", bool(G.item_mistarget(wt, ITEM_F3)))
ok("_split_ops keeps the operators", G._split_ops('a && b || c; d | e') == [("", "a"), ("&&", "b"), ("||", "c"), (";", "d"), ("|", "e")], G._split_ops('a && b || c; d | e'))

print("== iptv F2: named tests")
ITEM_F2 = ('[T4] iptv-backend/tests/test_subscription.py — Add test test_cancel_subscription_rate_limit that asserts the 6th cancel call in a minute returns 429. '
           'VERIFY: `pytest iptv-backend/tests/test_subscription.py::test_cancel_subscription_rate_limit` (cat:test)')
d2, v2 = G.item_desc(ITEM_F2), "pytest iptv-backend/tests/test_subscription.py::test_cancel_subscription_rate_limit"
ok("'Add test test_x' names test_x (once, even with the node id in the VERIFY)", G.named_tests(d2, v2) == ["test_cancel_subscription_rate_limit"], G.named_tests(d2, v2))
ok("the file name test_subscription.py is not a test function", "test_subscription" not in G.named_tests(d2, v2))
ok("'Add tests test_a and test_b'", G.named_tests("Add tests test_a and test_b to the module") == ["test_a", "test_b"], G.named_tests("Add tests test_a and test_b to the module"))
ok("'Add a regression test `test_x`'", G.named_tests("Add a regression test `test_x` for the limiter") == ["test_x"])
ok("a description that only MENTIONS a test as a reference promises nothing", G.named_tests("Rate limit cancel, mirroring test_content_identify_rate_limit") == [])
ok("'Add test coverage' + a node-id VERIFY yields the node id's name", G.named_tests("Add test coverage for the cancel limit", "pytest t/test_s.py::TestCancel::test_limit_429") == ["test_limit_429"])
ok("a description without an add-verb does not read the VERIFY node id", G.named_tests("Fix the cancel limit", "pytest t/test_s.py::test_limit") == [])
ok("a 'Remove test' item promises nothing", G.named_tests("Remove test test_old from the file") == [])

wt2 = tempfile.mkdtemp(prefix="sg2-")
mk(wt2, "iptv-backend/tests/test_subscription.py", "import time\n\n\ndef test_other():\n    assert 1\n\n\nclass TestCancel:\n    def test_in_class(self):\n        assert 1\n")
mk(wt2, "tests/test_x.gd", "extends GutTest\n\nfunc test_gd_one():\n\tassert_true(true)\n")
mk(wt2, "node_modules/pkg/test_hidden.py", "def test_hidden():\n    pass\n")
res = G.resolve_tests(wt2, ["test_cancel_subscription_rate_limit", "test_other", "test_in_class", "test_gd_one", "test_hidden"])
ok("deleted test -> missing (the live defect: repair left only `import time`)", "test_cancel_subscription_rate_limit" in res["missing"], res)
ok("top-level def found with its node id", any(x["name"] == "test_other" and x["node"] == "iptv-backend/tests/test_subscription.py::test_other" for x in res["found"]), res)
ok("class method found with Class:: in the node id", any(x["name"] == "test_in_class" and x["node"].endswith("::TestCancel::test_in_class") for x in res["found"]), res)
ok("GDScript func found (kind gd)", any(x["name"] == "test_gd_one" and x["kind"] == "gd" for x in res["found"]), res)
ok("node_modules is never searched", "test_hidden" in res["missing"], res)

print("== reviewer defect 3: promised Kotlin / Swift / TS tests are located (and unverifiable promises are never 'missing')")
wt3 = tempfile.mkdtemp(prefix="sg5-")
mk(wt3, "iptv-android/app/src/test/java/com/x/EpgRepositoryTest.kt", "class EpgRepositoryTest {\n    @Test\n    fun test_createSource_triggersAutoMap() {\n    }\n}\n")
mk(wt3, "iptv-ios/Tests/FavTests.swift", "final class FavTests: XCTestCase {\n    func test_swift_toggle() {\n    }\n}\n")
mk(wt3, "web/src/__tests__/foo.spec.ts", "describe('x', () => {\n  it('test_ts_case', () => {})\n})\n")
r3 = G.resolve_tests(wt3, ["test_createSource_triggersAutoMap", "test_swift_toggle", "test_ts_case", "test_nowhere"])
ok("Kotlin `fun test_x()` is found (kind kt), not missing", any(x["name"] == "test_createSource_triggersAutoMap" and x["kind"] == "kt" for x in r3["found"]) and "test_createSource_triggersAutoMap" not in r3["missing"], r3)
ok("Swift `func test_x()` is found", any(x["name"] == "test_swift_toggle" and x["kind"] == "swift" for x in r3["found"]), r3)
ok("TS `it('test_x')` is found", any(x["name"] == "test_ts_case" and x["kind"] == "js" for x in r3["found"]), r3)
ok("a name defined nowhere is still missing (no context)", r3["missing"] == ["test_nowhere"], r3)
r3b = G.resolve_tests(wt3, ["test_gone_kt"], "[T3] iptv-android/app/src/test/java/com/x/EpgRepositoryTest.kt \u2014 Add test test_gone_kt")
ok("second review: a name promised ONLY at a .kt file and defined nowhere is MISSING (it used to fail open as unverifiable)", r3b["missing"] == ["test_gone_kt"] and r3b["unverifiable"] == [], r3b)
r3s = G.resolve_tests(wt3, ["test_gone_sw"], "[T3] iptv-ios/Tests/FavTests.swift \u2014 Add test test_gone_sw")
ok("... and the same for a .swift promise", r3s["missing"] == ["test_gone_sw"], r3s)
r3j = G.resolve_tests(wt3, ["test_gone_j"], "[T3] app/src/test/FooTest.java \u2014 Add test test_gone_j")
ok("... and a .java promise", r3j["missing"] == ["test_gone_j"], r3j)
mk(wt3, "app/src/test/FooTest.java", "class FooTest {\n  @Test void test_java_case() {}\n  @Test public void test_java_pub() {}\n}\n")
mk(wt3, "app/src/test/BarTest.kt", "class BarTest {\n  @Test fun `test_bt_name`() {}\n}\n")
r3k = G.resolve_tests(wt3, ["test_java_case", "test_java_pub", "test_bt_name"])
ok("Java `void test_x(` / Kotlin backticked `fun \x60test_x\x60(` definitions are located", r3k["missing"] == [] and len(r3k["found"]) == 3, r3k)
r3t = G.resolve_tests(wt3, ["test_gone_ts"], "[T3] web/src/__tests__/foo.spec.ts \u2014 Add test test_gone_ts")
ok("a name promised only at a .ts file (a language read with less confidence) stays unverifiable, not missing", r3t["missing"] == [] and r3t["unverifiable"] == ["test_gone_ts"], r3t)
r3m = G.resolve_tests(wt3, ["test_gone_mix"], "[T3] a/FooTest.kt \u2014 Add test test_gone_mix (also web/foo.spec.ts)")
ok("a promise naming a .kt AND a .ts file stays unverifiable", r3m["missing"] == [] and r3m["unverifiable"] == ["test_gone_mix"], r3m)
r3c = G.resolve_tests(wt3, ["test_gone_py"], "[T3] backend/tests/test_x.py \u2014 Add test test_gone_py (and see EpgRepositoryTest.kt)")
ok("... a promise that also names a .py file stays judged (missing)", r3c["missing"] == ["test_gone_py"] and r3c["unverifiable"] == [], r3c)
ok("unverifiable_context: no path at all -> judged", not G.unverifiable_context("Add test test_x"))
ok("unverifiable_context: kotlin / swift / java only -> judged; ts only -> unverifiable", not G.unverifiable_context("x/FooTest.kt") and not G.unverifiable_context("Foo.swift") and G.unverifiable_context("x/foo.spec.ts"))
cli = os.path.join(HERE, "..", "ovn_stage_guards.py")
rc = subprocess.run([sys.executable, cli, "resolve-tests", wt3, "test_gone_kt"], capture_output=True, text=True, env=dict(os.environ, OVN_SG_CONTEXT="x/foo.spec.ts"))
ok("CLI: OVN_SG_CONTEXT reaches resolve_tests (unverifiable in JSON)", '"unverifiable": ["test_gone_kt"]' in rc.stdout and '"missing": []' in rc.stdout, rc.stdout)

print("== xlite F7: Create <test file> that already exists")
repo = tempfile.mkdtemp(prefix="sg3-")
mk(repo, "tests/test_orphan_save_manager.gd", 'extends GutTest\n\nfunc test_old_path_gone():\n\tassert_false(FileAccess.file_exists("res://scripts/battle/save_manager.gd"), "orphan")\n\nfunc test_new_path_present():\n\tpass\n')
ITEM_F7 = ('- [ ] [T1] tests/test_orphan_save_manager.gd — Create a GDScript test file that asserts `FileAccess.file_exists("res://scripts/battle/save_manager.gd") == false`. '
           'VERIFY: `cd tests && godot --headless -s test_orphan_save_manager.gd`. (cat:test; recovery:decomposed)')
ok_, path, names, why = G.create_exists(repo, ITEM_F7)
ok("live F7 item: target exists AND contains the asserted call -> already done", ok_ and path == "tests/test_orphan_save_manager.gd", (ok_, path, names, why))
ok_, path, names, why = G.create_exists(repo, ITEM_F7.replace("save_manager.gd\") == false", "other_manager.gd\") == false"))
ok("same item whose asserted call is NOT in the file -> NOT done", not ok_ and "does not contain" in why, (ok_, why))
ok_, path, names, why = G.create_exists(repo, ITEM_F7.replace("Create a GDScript test file that asserts", "Create tests test_old_path_gone and test_new_path_present that assert"))
ok("named functions all present -> already done", ok_ and names == ["test_old_path_gone", "test_new_path_present"], (ok_, names, why))
ok_, path, names, why = G.create_exists(repo, ITEM_F7.replace("Create a GDScript test file that asserts", "Create tests test_old_path_gone and test_brand_new that assert"))
ok("a named function missing from the file -> NOT done", not ok_ and "test_brand_new" in why, (ok_, why))
ok("target missing -> not done", not G.create_exists(repo, ITEM_F7.replace("test_orphan_save_manager.gd — ", "test_other.gd — "))[0])
ok("not a Create verb ('Fix') -> not judged", not G.create_exists(repo, ITEM_F7.replace("Create a GDScript", "Fix a GDScript"))[0])
ok("a non-test target (source file) is never short-circuited", not G.create_exists(repo, "- [ ] [T1] scripts/x.gd — Create the helper. VERIFY: `grep -q f scripts/x.gd`")[0])
mk(repo, "tests/test_empty.gd", "extends GutTest\n")
print("== reviewer defect 2: an existing file with OTHER tests proves nothing")
mk(repo, "tests/test_feedback.py", "def test_unrelated_one():\n    assert submit_feedback(5) == 200\n\n\ndef test_unrelated_two():\n    assert 1\n")
ITEM_ADD = '- [ ] [T2] tests/test_feedback.py \u2014 Add a test case verifying that `submit_feedback` returns 400 or 422 when the rating is out of range. (cat:test; multifile:no)'
ok("'Add a test case verifying X' (names no function) against a file with other tests -> NOT done", not G.create_exists(repo, ITEM_ADD)[0], G.create_exists(repo, ITEM_ADD))
ok("... the same with a bare backticked identifier that the file mentions -> NOT done", not G.create_exists(repo, ITEM_ADD.replace("`submit_feedback`", "`test_feedback`"))[0] and not G.create_exists(repo, ITEM_ADD.replace("Add a test case", "Create tests"))[0])
ok("... with a `Class.method()` empty-arg mention -> NOT done", not G.create_exists(repo, ITEM_ADD.replace("`submit_feedback`", "`Unit.display_name()`"))[0])
ok("a test file with unrelated tests and an item naming a function the file lacks -> NOT done", not G.create_exists(repo, ITEM_ADD.replace("Add a test case", "Add test test_rating_range"))[0])
ok("an item naming a function the file HAS -> done", G.create_exists(repo, ITEM_ADD.replace("Add a test case", "Add test test_unrelated_two"))[0])
ok("an item with an asserted call the file contains (`submit_feedback(5)`) -> done", G.create_exists(repo, ITEM_ADD.replace("`submit_feedback`", "`submit_feedback(5) == 200`"))[0])
ok("an existing test file with NO test function is not done", not G.create_exists(repo, ITEM_F7.replace("test_orphan_save_manager.gd — ", "test_empty.gd — "))[0])
ok("a Delete item is not a create item", not G.create_exists(repo, ITEM_F7.replace("Create a GDScript test file", "Delete the test file"))[0])

print("== iptv F6: new-tests (the test functions a diff added)")
g = tempfile.mkdtemp(prefix="sg4-")
def git(*a):
    return subprocess.run(["git", "-C", g, "-c", "user.email=t@t", "-c", "user.name=t"] + list(a), capture_output=True, text=True)
git("init", "-q"); mk(g, "tests/test_a.py", "def test_old():\n    pass\n"); git("add", "-A"); git("commit", "-q", "-m", "base")
base = git("rev-parse", "HEAD").stdout.strip()
mk(g, "tests/test_a.py", "def test_old():\n    pass\n\n\ndef test_added():\n    pass\n\n\nclass TestC:\n    def test_method_added(self):\n        pass\n")
git("add", "-A"); git("commit", "-q", "-m", "add")
nt = G.new_tests(g, base)
ok("added function + added method, not the old one", sorted(nt) == ["tests/test_a.py::TestC::test_method_added", "tests/test_a.py::test_added"], nt)
ok("no change -> none", G.new_tests(g, git("rev-parse", "HEAD").stdout.strip()) == [])

print("== CLI exit codes")
cli = os.path.join(HERE, "..", "ovn_stage_guards.py")
rc = subprocess.run([sys.executable, cli, "item-mistarget", wt, ITEM_F3], capture_output=True, text=True)
ok("item-mistarget: exit 0 + reason when it fires", rc.returncode == 0 and "codex_manager.gd" in rc.stdout, (rc.returncode, rc.stdout))
rc = subprocess.run([sys.executable, cli, "item-mistarget", wt, ITEM_CREATE], capture_output=True, text=True)
ok("item-mistarget: exit 1 when nothing to report", rc.returncode == 1, rc.returncode)
rc = subprocess.run([sys.executable, cli, "step-mistarget", wt, "Verify X", "gone.gd"], capture_output=True, text=True)
ok("step-mistarget: exit 0 + reason", rc.returncode == 0 and "gone.gd" in rc.stdout)
rc = subprocess.run([sys.executable, cli, "create-exists", repo, ITEM_F7], capture_output=True, text=True)
ok("create-exists: exit 0, tab separated path/names/why", rc.returncode == 0 and rc.stdout.split("\t")[0] == "tests/test_orphan_save_manager.gd", rc.stdout)
rc = subprocess.run([sys.executable, cli, "bogus"], capture_output=True, text=True)
ok("unknown subcommand: exit 2", rc.returncode == 2)

print("\n%d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
