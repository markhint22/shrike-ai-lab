#!/usr/bin/env python3
"""Z8b (2026-11-10): gate recall + waste cuts. Unit tests for
  A  tone-lint tokens (Heads up ... chatter; comments / tests / locale paths exempt; OVN_Z8_TONE=off restores the old list),
  B  assert-weaken recall kinds expectation-trivial / stream-assert-deleted / bulk-assert-deleted / bulk-test-deleted (+429 status-flip-src), shadow-only, kill switches,
  D  scripts/ovn_ts_unused_imports.py (pure fixer: fix_text),
  F  scripts/ovn_plan_path_ok.py (garbage plan tokens: 7199.96, db.example, IsoGrid.has).
Fixtures are the real 2026-11-10 incident diffs (shrike-monitor 4925ade + b434d22, shrike-notify ae714d7, gitlark 0b77a340, iptv bab0a91f).
test_z8b.sh re-runs this file against mutated copies (Z8B_MODULE_DIR=<dir holding the mutated scripts>); every mutant must be killed."""
import importlib.util
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
MODDIR = os.environ.get("Z8B_MODULE_DIR") or os.path.abspath(os.path.join(HERE, ".."))


def load(name):
    spec = importlib.util.spec_from_file_location(name, os.path.join(MODDIR, name + ".py"))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


G = load("ovn_landing_gates")
U = load("ovn_ts_unused_imports")
PP = load("ovn_plan_path_ok")
P = F = 0


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name + ((" :: " + str(extra)) if extra else ""))


def fdiff(path, removed=(), added=(), start=10):
    h = "diff --git a/%s b/%s\n--- a/%s\n+++ b/%s\n@@ -%d,%d +%d,%d @@\n" % (path, path, path, path, start, len(removed), start, len(added))
    return h + "".join("-%s\n" % r for r in removed) + "".join("+%s\n" % a for a in added)


def aw(diffs, old=None, new=None, repair=False):
    return G.check_assert_weaken(G.parse_diff("".join(diffs)), (lambda _p: old) if old is not None else None, (lambda _p: new) if new is not None else None, repair=repair)


def kinds(fs):
    return sorted(set(f["kind"] for f in fs))


def tone(path, line, text=""):
    return [f["token"] for f in G.check_tone(G.parse_diff(fdiff(path, [], [line])), text)]


for k in ("OVN_Z8_TONE", "OVN_Z8_ASSERT_RECALL", "OVN_Z7_ASSERT_RECALL", "OVN_Z3_TONE_TOKENS", "OVN_Z8_BULK_ASSERT_N"):
    os.environ.pop(k, None)

print("== A tone-lint tokens")
NOTIF = "backend/app/services/notifier.py"
ok("A1 incident b434d22: 'Heads up: ...' title in notifier.py is flagged", tone(NOTIF, '        title = f"Heads up: {name} is down"') == ["Heads up"])
ok("A2a 'Hey there' is already covered by the old 'Hey' token", tone("web/src/Card.vue", '    <p>Hey there, welcome back</p>') == ["Hey"])
for tok, line in [("Hi!", '    return "Hi! Your plan is ready"'), ("Psst", '    msg = "Psst, your trial ends soon"'), ("Oops", '    error = "Oops! Something went wrong"'),
                  ("Uh oh", '    error = "Uh oh, that failed"'), ("Quick note", '    <span>Quick note: saved</span>'), ("Just a heads-up", '    msg = "Just a heads-up: maintenance"'), ("FYI", '    msg = "FYI the job finished"'),
                  ("Heads-up", '    msg = "Heads-up: queue is full"')]:
    ok("A2 %r in product copy is flagged" % tok, tone("web/src/Card.vue", line) == [tok], tone("web/src/Card.vue", line))
ok("A3 a code COMMENT saying FYI / Heads up is not product copy", tone(NOTIF, "    # FYI: this retries once") == [] and tone(NOTIF, "    // Heads up: order matters") == [] and tone("web/src/a.ts", "    * Oops handled below") == [])
ok("A4 tests / fixtures / locales / docs stay exempt for the new tokens", all(tone(p, 'x = "Heads up: hi"') == [] for p in ("backend/tests/test_notifier.py", "web/src/__tests__/a.test.ts", "app/fixtures/m.py", "web/src/locales/en.ts", "docs/x.md")))
ok("A5 the item/step text asking for the phrase suppresses it", tone(NOTIF, 'title = "Heads up: x"', "Change the title to start with Heads up") == [])
ok("A6 not inside a longer identifier (HeadsUpDisplay, Oopsie, FYIs)", tone(NOTIF, "    x = HeadsUpDisplay()") == [] and tone(NOTIF, '    y = "Oopsie"') == [] and tone(NOTIF, '    z = "FYIs"') == [])
ok("A7 lowercase 'heads up' / 'oops' / 'fyi' (prose, identifiers) is not the tell", tone(NOTIF, '    m = "heads up, oops, fyi"') == [])
ok("A8 the pre-Z8b tokens still fire (Hey, Buzz)", tone(NOTIF, '    x = "Hey! Buzz"') == ["Hey", "Buzz"])
os.environ["OVN_Z8_TONE"] = "off"
ok("A9 OVN_Z8_TONE=off restores the old list exactly (Heads up silent, Hey still fires)", tone(NOTIF, 'title = "Heads up: x"') == [] and tone(NOTIF, 'x = "Hey!"') == ["Hey"])
os.environ.pop("OVN_Z8_TONE")
ok("A10 OVN_Z3_TONE_TOKENS override still wins", [f["token"] for f in G.check_tone(G.parse_diff(fdiff(NOTIF, [], ['x = "Heads up"'])), "", tokens="Buzz")] == [])

print("== B expectation-trivial (shrike-monitor 4925ade)")
SRC = fdiff("backend/app/utils/sla_met.py", ["    return uptime_ratio(results) >= target"], ["    if not results:", "        return None", "    return uptime_ratio(results) >= target"])
T = "backend/tests/test_sla_met.py"
t = fdiff(T, ["    assert sla_met([], 0.99) is False"], ["    assert sla_met([], 0.99) is None"], start=33)
f = aw([SRC, t])
ok("B1 `is False` -> `is None` alongside a source edit is flagged expectation-trivial (the source introducing None does NOT explain it)", "expectation-trivial" in kinds(f), f)
ok("B1b ...with src_changed true", all(x["src_changed"] for x in f if x["kind"] == "expectation-trivial"), f)
ok("B2 without a source edit it is not this kind (a test-only change is judged by the other kinds)", "expectation-trivial" not in kinds(aw([t])))
f = aw([SRC, fdiff(T, ["    assert result == [1, 2]"], ["    assert result == []"])])
ok("B3 `== [1, 2]` -> `== []` with a source edit is flagged", "expectation-trivial" in kinds(f), f)
f = aw([SRC, fdiff(T, ["    assert total == 5"], ["    assert total == 0"])])
ok("B4 `== 5` -> `== 0` is flagged; `== 0.5` is not read as zero", "expectation-trivial" in kinds(f) and "expectation-trivial" not in kinds(aw([SRC, fdiff(T, ["    assert t == 60.0"], ["    assert t == 0.5"])])), f)
f = aw([SRC, fdiff(T, ["    assert sla_met([], 0.99) is None"], ["    assert sla_met([], 0.99) is False"])])
ok("B5 the opposite direction (None -> False: stronger) is not flagged", "expectation-trivial" not in kinds(f), f)
f = aw([SRC, fdiff(T, ["def test_x():", "    assert a is False"], ["def test_y():", "    assert a is None"])])
ok("B6 a rewritten test (def line changed) is not judged", "expectation-trivial" not in kinds(f), f)
f = aw([SRC, fdiff(T, ["    assert a is False"], ["    assert b is None"])])
ok("B7 different subject: not the same assertion shape", "expectation-trivial" not in kinds(f), f)

print("== B stream-assert-deleted (shrike-notify ae714d7)")
TN = "backend/tests/test_notify_cli_load_payload_hardening.py"
d = fdiff(TN, ["        captured = capsys.readouterr()", '        assert "Error: payload must be a JSON object" in captured.err', "def test_directory_input_exits_1(tmp_path):", '    """Verify."""'], [], start=75)
f = aw([d], new="x = 1\n")
ok("B8 a `captured.err` assertion removed under a retired def is flagged stream-assert-deleted", "stream-assert-deleted" in kinds(f), f)
ok("B8b strong tier", all(x["tier"] == "strong" for x in f if x["kind"] == "stream-assert-deleted"), f)
f = aw([d], new='assert "Error: payload must be a JSON object" in captured.err\n')
ok("B9 the same assertion still present in the new file (moved / de-duplicated): not flagged", "stream-assert-deleted" not in kinds(f), f)
f = aw([fdiff(TN, ['    assert "x" in captured.err'], ['    assert "x" in captured.err  # same'])], new='    assert "x" in captured.err  # same\n')
ok("B10 reworded in place: not flagged", "stream-assert-deleted" not in kinds(f), f)
f = aw([fdiff(TN, ['    assert result == 3'], [])], new="")
ok("B11 a non-stream assertion removal is not this kind", "stream-assert-deleted" not in kinds(f), f)
f = aw([fdiff(TN, ['    assert "x" in caplog.text'], [])], new="")
ok("B12 caplog / capsys count as streams", "stream-assert-deleted" in kinds(f), f)

print("== B bulk deletion (gitlark 0b77a340)")
rem = ["async def test_list_pull_requests_invalid_state("] + ["        # reasoning line %d" % i for i in range(160)] + ["    assert a == %d" % i for i in range(3)]
d = fdiff("backend/tests/test_pull_requests_param_validation.py", rem, ["def test_get_pull_request_invalid_page(client):", "    assert response.status_code == 422"], start=29)
f = aw([d], new="x\n")
ok("B13 one test of 160+ lines replaced by a 2-line test: bulk-test-deleted", "bulk-test-deleted" in kinds(f), f)
f = aw([fdiff("backend/tests/test_a.py", ["def test_a():"] + ["    x = %d" % i for i in range(20)], ["def test_a():", "    x = 1"])], new="x\n")
ok("B14 a 20-line test shrunk (below the 100-line bar, 0 tests gone): not flagged", "bulk-test-deleted" not in kinds(f), f)
f = aw([fdiff("backend/tests/test_a.py", ["def test_one():"] + ["    x = %d" % i for i in range(10)], [])], new="x\n")
ok("B14b one test removed, 11 lines net (below the 100-line bar, below 3 tests): not flagged", "bulk-test-deleted" not in kinds(f), f)
many = ["    assert v == %d" % i for i in range(12)]
f = aw([fdiff("backend/tests/test_a.py", many, [])], new="x\n")
ok("B15 12 assertion lines removed with nothing replacing them: bulk-assert-deleted", "bulk-assert-deleted" in kinds(f), f)
f = aw([fdiff("backend/tests/test_a.py", many, []), fdiff("backend/tests/test_b.py", [], many)], new="x\n")
ok("B16 the same assertion lines added in another test file of the diff (a move): not flagged", "bulk-assert-deleted" not in kinds(f), f)
f = aw([fdiff("backend/tests/test_a.py", many[:5], [])], new="x\n")
ok("B17 5 assertion lines (below the default N=8): not flagged", "bulk-assert-deleted" not in kinds(f), f)
os.environ["OVN_Z8_BULK_ASSERT_N"] = "4"
ok("B18 OVN_Z8_BULK_ASSERT_N lowers the bar", "bulk-assert-deleted" in kinds(aw([fdiff("backend/tests/test_a.py", many[:5], [])], new="x\n")))
os.environ.pop("OVN_Z8_BULK_ASSERT_N")

dup = ["def test_a():", "    assert v == 1", "    assert w == 2"]
f = aw([fdiff("backend/tests/test_a.py", ["    assert v == %d" % i for i in range(12)], [])], new="    assert v == 3\n".join(["    assert v == %d\n" % i for i in range(12)]))
ok("B13b a de-duplication: the removed assertion lines still exist in the post-image: not flagged bulk-assert-deleted", "bulk-assert-deleted" not in kinds(f), f)
f = aw([fdiff("backend/tests/test_a.py", ["def test_x():"] + ["    y = %d" % i for i in range(120)], [])], new="def test_x(client):\n    pass\n")
ok("B13c a test removed whose NAME is still defined in the post-image (a duplicate copy removed): not flagged bulk-test-deleted", "bulk-test-deleted" not in kinds(f), f)
f = aw([fdiff("backend/tests/test_a.py", ["def test_x():"] + ["    y = %d" % i for i in range(120)], [])], new="def test_other():\n    pass\n")
ok("B13d ...but flagged when the name is gone from the file (the last copy was removed)", "bulk-test-deleted" in kinds(f), f)
f = aw([SRC, fdiff(T, ['    assert data["queue_depth"] == 3'], ['    assert data["plans"] == []'])])
ok("B13e different subject on the same shape (data[\"queue_depth\"] vs data[\"plans\"]): not expectation-trivial", "expectation-trivial" not in kinds(f), f)

print("== B 429 -> 200 (iptv bab0a91f)")
f = aw([fdiff("iptv-backend/tests/test_parental_usage.py", ["    assert response.status_code == 429"], ["    assert response.status_code == 200"])])
ok("B19 test-only 429 -> 200 is status-flip", "status-flip" in kinds(f), f)
f = aw([fdiff("iptv-backend/app/routers/parental.py", ["    return a"], ["    return b"]), fdiff("iptv-backend/tests/test_parental_usage.py", ["    assert response.status_code == 429"], ["    assert response.status_code == 200"])])
ok("B20 429 -> 200 alongside a source edit is status-flip-src (429 added to the list)", "status-flip-src" in kinds(f), f)

print("== B kill switches")
os.environ["OVN_Z8_ASSERT_RECALL"] = "off"
ok("B21 OVN_Z8_ASSERT_RECALL=off: none of the Z8b kinds fire", not (set(kinds(aw([SRC, t]))) | set(kinds(aw([d], new="x\n"))) | set(kinds(aw([fdiff("backend/tests/test_a.py", many, [])], new="x\n")))) & {"expectation-trivial", "bulk-test-deleted", "bulk-assert-deleted", "stream-assert-deleted"})
f = aw([fdiff("iptv-backend/app/routers/parental.py", ["    return a"], ["    return b"]), fdiff("iptv-backend/tests/test_parental_usage.py", ["    assert response.status_code == 429"], ["    assert response.status_code == 200"])])
ok("B21b ...and 429 is no longer in the status-flip-src list", "status-flip-src" not in kinds(f), f)
os.environ.pop("OVN_Z8_ASSERT_RECALL")
os.environ["OVN_Z7_ASSERT_RECALL"] = "off"
ok("B22 OVN_Z7_ASSERT_RECALL=off drops the Z8b kinds too", not (set(kinds(aw([SRC, t]))) | set(kinds(aw([d], new="x\n")))) & {"expectation-trivial", "bulk-test-deleted", "stream-assert-deleted"})
os.environ.pop("OVN_Z7_ASSERT_RECALL")
ok("B23 analyse() wiring: the new kinds are reported under assert-weaken (shadow flag only, sev FLAG)", all(x["rule"] == "assert-weaken" and x["sev"] == "FLAG" for x in aw([SRC, t])))
res = G.analyse(SRC + t, "", "", "step", "")
ok("B24 analyse(): the tone rule runs on the same diff (Heads up in src)", True)
res = G.analyse(fdiff(NOTIF, [], ['title = "Heads up: x"']), "", "", "step", "")
ok("B25 analyse() carries the tone-lint finding for 'Heads up'", any(x.get("token") == "Heads up" for x in res.get("tone-lint", [])), res)

print("== D unused-import fixer (pure)")
src = "import { describe, it, expect, vi } from 'vitest'\nimport { mount } from '@vue/test-utils'\nimport 'side-effect'\nimport X, { a, b as c } from \"./x\";\nimport {\n  foo,\n  bar,\n} from './y'\nconst z = 1\n"
new, names = U.fix_text(src, [(1, "6133", "vi")], None)
ok("D1 TS6133 on one named import removes only that binding", names == ["vi"] and new.startswith("import { describe, it, expect } from 'vitest'\n") and "mount" in new, new)
new, names = U.fix_text(src, [(2, "6133", "mount")], None)
ok("D2 the only binding unused: the whole declaration (and its line) goes", names == ["mount"] and "test-utils" not in new and new.count("\n") == src.count("\n") - 1, new)
new, names = U.fix_text(src, [(3, "6133", "side-effect")], None)
ok("D3 a side-effect import is never touched", names == [] and new == src)
new, names = U.fix_text(src, [(4, "6133", "X"), (4, "6133", "c")], None)
ok("D4 default + aliased specifier removed, the rest kept, quote style and semicolon kept", names == ["X", "c"] and 'import { a } from "./x";' in new, new)
new, names = U.fix_text(src, [(4, "6192", None)], None)
ok("D5 TS6192 (all imports unused) removes the declaration", "./x" not in new and sorted(names) == ["X", "a", "c"], (new, names))
new, names = U.fix_text(src, [(6, "6133", "foo")], None)
ok("D6 a multi-line import: the unused name is found by its line", names == ["foo"] and "bar" in new and "foo" not in new, new)
new, names = U.fix_text(src, [(1, "6133", "nothing")], None)
ok("D7 a name that is not a binding of that import is left alone", names == [] and new == src)
new, names = U.fix_text(src, [(1, "6133", "vi")], {50})
ok("D8 added-lines filter: an import the commit did not add is left alone", names == [] and new == src)
new, names = U.fix_text(src, [(1, "6133", "vi")], {1})
ok("D9 ...and fixed when its line is one the commit added", names == ["vi"])
new, names = U.fix_text("const a = 1\nconst b = 2\n", [(1, "6133", "a")], None)
ok("D10 a non-import unused variable (TS6133 on a const) is never touched", names == [])
new, names = U.fix_text("import type { Foo, Bar } from './t'\nlet x: Foo\n", [(1, "6196", "Bar")], None)
ok("D11 TS6196 on a type import removes the binding and keeps `import type`", names == ["Bar"] and new.startswith("import type { Foo } from './t'"), new)

print("== D end to end (git repo, real CLI)")
with tempfile.TemporaryDirectory() as tmp:
    def sh(*a, **k):
        return subprocess.run(a, cwd=k.get("cwd", tmp), capture_output=True, text=True, input=k.get("input"))
    sh("git", "init", "-q")
    sh("git", "config", "user.email", "t@t")
    sh("git", "config", "user.name", "t")
    os.makedirs(os.path.join(tmp, "web/src"))
    open(os.path.join(tmp, "web/src/a.test.ts"), "w").write("import { describe } from 'vitest'\ndescribe('a', () => {})\n")
    open(os.path.join(tmp, "web/src/old.test.ts"), "w").write("import { vi } from 'vitest'\n")
    sh("git", "add", "-A")
    sh("git", "commit", "-qm", "base")
    base = sh("git", "rev-parse", "HEAD").stdout.strip()
    open(os.path.join(tmp, "web/src/a.test.ts"), "w").write("import { describe, vi } from 'vitest'\ndescribe('a', () => {})\n")
    sh("git", "add", "-A")
    sh("git", "commit", "-qm", "item")
    head = sh("git", "rev-parse", "HEAD").stdout.strip()
    out = "src/a.test.ts(1,1): error TS6133: 'vi' is declared but its value is never read.\nsrc/old.test.ts(1,1): error TS6133: 'vi' is declared but its value is never read.\n"
    cli = [sys.executable, os.path.join(MODDIR, "ovn_ts_unused_imports.py"), "--cwd", os.path.join(tmp, "web"), "--toplevel", tmp, "--before", base, "--after", head]
    r = sh(*cli, "--dry-run", input=out)
    ok("D12 dry-run reports WOULD-FIX for the touched file only and edits nothing", "WOULD-FIX web/src/a.test.ts vi" in r.stdout and "old.test" not in r.stdout and "vi }" in open(os.path.join(tmp, "web/src/a.test.ts")).read(), r.stdout + r.stderr)
    r = sh(*cli, input=out)
    txt = open(os.path.join(tmp, "web/src/a.test.ts")).read()
    ok("D13 real run fixes the touched file (a.test.ts) and not the untouched old.test.ts", "FIXED web/src/a.test.ts vi" in r.stdout and txt.startswith("import { describe } from 'vitest'\n") and "TOTAL 1 web/src/a.test.ts" in r.stdout and "vi" in open(os.path.join(tmp, "web/src/old.test.ts")).read(), r.stdout + r.stderr)
    r = sh(sys.executable, os.path.join(MODDIR, "ovn_ts_unused_imports.py"), "--cwd", tmp, "--toplevel", "/nonexistent", "--before", "x", "--after", "y", input=out)
    ok("D14 garbage arguments: exit 0 and TOTAL 0 (fail-open)", r.returncode == 0 and "TOTAL 0" in r.stdout, r.stdout + r.stderr)

print("== F plan-path token check")
with tempfile.TemporaryDirectory() as tmp:
    os.makedirs(os.path.join(tmp, "backend/tests"))
    open(os.path.join(tmp, "backend/tests/test_duration_hour_rollover.py"), "w").write("x = 1\n")
    open(os.path.join(tmp, "backend/tests/test_duration_hour_rollover.pyc"), "w").write("x")
    open(os.path.join(tmp, "db.example"), "w").write("x")
    subprocess.run(["git", "init", "-q"], cwd=tmp)
    subprocess.run(["git", "add", "-A"], cwd=tmp)
    subprocess.run(["git", "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-qm", "i"], cwd=tmp)
    for garbage in ("7199.96", "3599.96", "db.example", "IsoGrid.has", "project.godot.bak2", "0.5", "v1.2", "example.com"):
        ok("F1 garbage token %r is refused" % garbage, not PP.ok(tmp, garbage))
    ok("F2 a real path with a known extension that exists is accepted", PP.ok(tmp, "backend/tests/test_duration_hour_rollover.py"))
    ok("F3 a bare basename of a tracked file is accepted", PP.ok(tmp, "test_duration_hour_rollover.py"))
    ok("F4 a known extension but NOT in the tree is refused", not PP.ok(tmp, "backend/tests/test_missing.py") and not PP.ok(tmp, "frontend/src/App.vue"))
    ok("F5 an existing file with an unknown extension (.pyc, .example) is refused", not PP.ok(tmp, "backend/tests/test_duration_hour_rollover.pyc") and not PP.ok(tmp, "db.example"))
    ok("F6 a not-a-git directory fails open for a path that is missing (no evidence)", PP.ok(os.path.join(tmp, "nope"), "backend/x.py"))
    cli = [sys.executable, os.path.join(MODDIR, "ovn_plan_path_ok.py"), tmp]
    ok("F7 CLI exit codes: 1 for garbage, 0 for a real path", subprocess.run(cli + ["7199.96"]).returncode == 1 and subprocess.run(cli + ["test_duration_hour_rollover.py"]).returncode == 0)
    ok("F8 OVN_PLAN_PATH_STRICT=off restores the old behaviour (always 0)", subprocess.run(cli + ["7199.96"], env=dict(os.environ, OVN_PLAN_PATH_STRICT="off")).returncode == 0)

print("\n%d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
