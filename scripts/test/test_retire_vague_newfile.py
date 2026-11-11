#!/usr/bin/env python3
"""scripts/ovn_retire_vague.py: package q-deadpath-newfile (2026-11-10).

Incident (box log, shrike-monitor eb5faca 18:53 CST): two NEW-FILE test items
  "[T2] backend/tests/test_auth_bearer_whitespace.py - Add pure unit tests for `_extract_bearer_token` ..."
  "[T3] backend/tests/test_auth_bearer_whitespace.py - Add TestClient integration test ..."
were retired as dead-path because the test file they were asked to CREATE does not exist yet, while the behaviour was still unfixed.
  (1) a new-file TEST creation item (all missing paths are test files whose directory exists) is never dead-path. OVN_DEADPATH_NEWFILE=off restores the old rule.
  (4) stale-create SHADOW detector: a create/build item whose every named path ALREADY exists journals `would-skip stale-create` and changes nothing.
Mutants (rule call reverted) must fail the same batteries."""
import json
import os
import re
import sys
import tempfile
import os as _tt_os, sys as _tt_sys
_tt_sys.path.insert(0, _tt_os.path.dirname(_tt_os.path.abspath(__file__)))
import tmp_track
tmp_track.install()

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPTS = os.path.abspath(os.path.join(HERE, ".."))
sys.path.insert(0, SCRIPTS)
import ovn_retire_vague as RV  # noqa: E402

P = F = 0


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name + ((" :: " + str(extra)[:300]) if extra else ""))


T2 = '- [ ] [T2] backend/tests/test_auth_bearer_whitespace.py — Add pure unit tests for `_extract_bearer_token` verifying "Bearer abc", "bearer abc", "BEARER abc", "Bearer  abc", "Bearer\\tabc", "Bearer abc " all return "abc", and None, "", "Bearer", "Bearer ", "Basic abc" return "". VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_auth_bearer_whitespace.py::TestExtractBearerToken`. (cat:test; multifile:no) [feat:shrike-monitor-20261106-extract-bearer-token-mis-parses-harmless]'
T3 = '- [ ] [T3] backend/tests/test_auth_bearer_whitespace.py — Add TestClient integration test verifying that a request with header "Bearer  <valid_token>" (two spaces) returns 200 and "Bearer wrong" returns 401. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_auth_bearer_whitespace.py::TestClientBearerWhitespace`. (cat:test; multifile:no) [feat:shrike-monitor-20261106-extract-bearer-token-mis-parses-harmless]'
EXISTING_GUARD = "- [ ] [T2] backend/tests/test_gone2.py \u2014 Add pure assertions to the existing tests in the file. One file."
MODIFY_MISSING_TEST = "- [ ] [T2] backend/tests/test_gone.py — Update the existing assertions in the file to use pytest.approx. One file."
SRC_MISSING = "- [ ] [T2] backend/app/ghost.py — fix the off-by-one in paginate(). One file."
TEST_ITEM_SRC_MISSING = "- [ ] [T2] backend/tests/test_new.py — Add tests for backend/app/ghost.py paginate(). One file."
TEST_ITEM_NO_DIR = "- [ ] [T2] old/layout/tests/test_new.py — Add pure unit tests for paginate(). One file."
TREE = {"backend/tests/test_existing.py": "x\n", "backend/app/main.py": "x\n"}
# TAA healing_event.py: the target of a 'build X' item already exists
STALE = "- [ ] [T1] backend/app/utils/healing_event.py — Create a new helper `build_healing_event(a, b, confidence, n)` that clamps confidence to [0,1]. VERIFY: `cd backend && python3 -m pytest tests/test_healing_event.py -q`. (cat:python; multifile:no)"
STALE_TREE = {"backend/app/utils/healing_event.py": "def build_healing_event(*a): pass\n", "backend/tests/test_healing_event.py": "x\n"}
FRESH = "- [ ] [T1] backend/app/utils/brand_new.py — Create a new helper `f()`. One file."
FOLLOWUP = "- [ ] [T1] backend/tests/test_healing_event.py \u2014 Add a test case to the new file that asserts clamping. One file."
MODIFY_EXISTING = "- [ ] [T1] backend/app/utils/healing_event.py — Modify `build_healing_event` to clamp NaN. One file."


def in_tree(files, fn, env=None):
    old = os.getcwd()
    d = tempfile.mkdtemp(prefix="rvnf-")
    saved = {}
    try:
        os.chdir(d)
        for k, v in (env or {}).items():
            saved[k] = os.environ.get(k)
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v
        for rp, body in files.items():
            os.makedirs(os.path.dirname(rp) or ".", exist_ok=True)
            open(rp, "w").write(body)
        return fn()
    finally:
        os.chdir(old)
        for k, v in saved.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v


def battery(mod, tag):
    bad = 0

    def chk(name, cond, extra=""):
        nonlocal bad
        if not cond:
            bad += 1
            if tag == "real":
                ok(name, False, extra)

    c = in_tree(TREE, lambda: mod.classify(T2))
    chk("T2 new-file test item (dir exists, file missing) kept, not dead-path", c is None, c)
    c = in_tree(TREE, lambda: mod.classify(T3))
    chk("T3 new-file test item kept", c is None, c)
    c = in_tree(TREE, lambda: mod.classify(T2), {"OVN_DEADPATH_NEWFILE": "off"})
    chk("OVN_DEADPATH_NEWFILE=off restores the old dead-path retirement", c == "dead-path", c)
    c = in_tree(TREE, lambda: mod.classify(MODIFY_MISSING_TEST))
    chk("'Update the existing ...' item whose test file is missing is still dead-path", c == "dead-path", c)
    c = in_tree(TREE, lambda: mod.classify(EXISTING_GUARD))
    chk("loose phrasing that says `existing` is a modify item, not a creation: still dead-path", c == "dead-path", c)
    c = in_tree(TREE, lambda: mod.classify(SRC_MISSING))
    chk("modify item with a missing source file still dead-path", c == "dead-path", c)
    c = in_tree(TREE, lambda: mod.classify(TEST_ITEM_SRC_MISSING))
    chk("test item naming a MISSING source file too stays dead-path (not only new test files)", c == "dead-path", c)
    c = in_tree(TREE, lambda: mod.classify(TEST_ITEM_NO_DIR))
    chk("new test whose directory does not exist here (stale clone) stays dead-path", c == "dead-path", c)
    c = in_tree({"backend/tests/test_auth_bearer_whitespace.py": "x\n", **TREE}, lambda: mod.classify(T2))
    chk("target test already exists -> kept (unchanged)", c is None, c)
    return bad


bad = battery(RV, "real")
ok("real module passes every new-file assertion", bad == 0, "failed=%d" % bad)


def e2e():
    open("Q.md", "w").write("# q\n" + T2 + "\n" + SRC_MISSING + "\n")
    RV.process("Q.md")
    return open("Q.md").read()


out = in_tree(TREE, e2e)
ok("process(): the new-file test item stays an open line; the missing-source item is retired",
   T2 in out.splitlines() and "(retired-dead-path) [T2] backend/app/ghost.py" in out and "(retired-dead-path) [T2] backend/tests/test_auth" not in out, out)

# ---- stale-create shadow detector ----
def stale(mod, item, tree, env=None):
    sd = tempfile.mkdtemp(prefix="rvsd-")
    e = {"OVN_STATE_DIR": sd}
    e.update(env or {})
    def run():
        open("Q.md", "w").write("# q\n" + item + "\n")
        mod.process("Q.md")
        body = open("Q.md").read()
        lf = os.path.join(sd, "stale_create_shadow.log")
        rows = [json.loads(l) for l in open(lf)] if os.path.exists(lf) else []
        return body, rows, "# q\n" + item + "\n"
    return in_tree(tree, run, e)


def sbattery(mod, tag):
    bad = 0

    def chk(name, cond, extra=""):
        nonlocal bad
        if not cond:
            bad += 1
            if tag == "real":
                ok(name, False, extra)
    try:
        body, rows, orig = stale(mod, STALE, STALE_TREE)
        chk("stale-create: journals one `would-skip stale-create` row (default shadow)", len(rows) == 1 and rows[0].get("rule") == "would-skip stale-create", rows)
        chk("stale-create: shadow changes NOTHING in the progress file", body == orig, body)
        body, rows2, orig = stale(mod, STALE, STALE_TREE, {"OVN_STALE_CREATE": "off"})
        chk("stale-create: OVN_STALE_CREATE=off journals nothing", rows2 == [], rows2)
        body, rows, orig = stale(mod, FRESH, {"backend/app/utils/x.py": "x\n"})
        chk("create item whose target does NOT exist: no row", rows == [], rows)
        body, rows, orig = stale(mod, MODIFY_EXISTING, STALE_TREE)
        chk("modify item on an existing file: no row", rows == [], rows)
        body, rows, orig = stale(mod, FOLLOWUP, STALE_TREE)
        chk("follow-up `Add a test case to the new file` on an existing file: no stale row", rows == [], rows)
        body, rows, orig = stale(mod, T2, TREE)
        chk("new-file test item (target missing): no stale row", rows == [], rows)
        body, rows, orig = stale(mod, STALE, STALE_TREE, {"OVN_STALE_CREATE": "enforce"})
        chk("stale-create has no enforce mode: 'enforce' still only journals, file untouched", body == orig and len(rows) == 1, (body, rows))
    except Exception as e:  # a mutant lacking the feature must count as a bite, not crash the suite
        bad += 1
        if tag == "real":
            ok("stale battery crashed", False, repr(e))
    return bad


sb = sbattery(RV, "real")
ok("real module passes every stale-create assertion", sb == 0, "failed=%d" % sb)

# ---- mutation: revert each rule at its call site; the same batteries must fail ----
src = open(os.path.join(SCRIPTS, "ovn_retire_vague.py")).read()
call1 = "return _loose_new_test_target(head)"
call2 = "stale_create_reason("
ok("found the new-file call site to mutate", call1 in src)
ok("found the stale-create call site to mutate", call2 in src)
if call1 in src:
    ns = {"__name__": "mutant_newfile"}
    exec(compile(src.replace(call1, "return set()"), "mutant_newfile.py", "exec"), ns)

    class M:
        classify = staticmethod(ns["classify"])
    mb = battery(M, "mutant")
    ok("mutation: new-file rule reverted fails the battery (%d bite)" % mb, mb > 0)
if call2 in src:
    ns2 = {"__name__": "mutant_stale"}
    exec(compile(src.replace("reason = stale_create_reason(", "reason = (lambda *a, **k: None)(", 1), "mutant_stale.py", "exec"), ns2)

    class M2:
        process = staticmethod(ns2["process"])
    mb2 = sbattery(M2, "mutant")
    ok("mutation: stale-create detector reverted fails its battery (%d bite)" % mb2, mb2 > 0)


# ---- review fixes (advisories 1-3) ----
RETRIES = "- [ ] [T2] backend/tests/test_new.py \u2014 Add retries so the flaky tests pass. One file."
IMPORTFIX = "- [ ] [T2] backend/tests/test_new.py \u2014 Add missing import to the test module and fix the failing test. One file."
NEWCOV = "- [ ] [T2] backend/tests/test_new.py \u2014 Add brand new regression coverage as tests for paginate(). One file."
CREATE_OK = "- [ ] [T2] backend/tests/test_new.py \u2014 Create a new test file for paginate(). One file."


def tighten_battery(mod, tag):
    bad = 0

    def chk(name, cond, extra=""):
        nonlocal bad
        if not cond:
            bad += 1
            if tag == "real":
                ok(name, False, extra)
    for nm, it in (("retries-so-tests-pass", RETRIES), ("missing-import-to-test-module", IMPORTFIX)):
        c = in_tree(TREE, lambda it=it: mod.classify(it))
        chk("tightened: %s is NOT a new-file creation (dead-path again)" % nm, c == "dead-path", c)
    for nm, it in (("new-test-file", CREATE_OK), ("named test file + new", NEWCOV), ("T2", T2), ("T3", T3)):
        c = in_tree(TREE, lambda it=it: mod.classify(it))
        chk("tightened: %s still kept" % nm, c is None, c)
    return bad


tb = tighten_battery(RV, "real")
ok("real module passes the tightened _LOOSE_NOUN battery", tb == 0, "failed=%d" % tb)
if "_loose_create_phrase(rest)" in src:
    ns3 = {"__name__": "mutant_loose"}
    exec(compile(src.replace("if not _loose_create_phrase(rest):", "if not _LOOSE_NOUN.search(rest):", 1), "mutant_loose.py", "exec"), ns3)

    class M3:
        classify = staticmethod(ns3["classify"])
    mb3 = tighten_battery(M3, "mutant")
    ok("mutation: bare _LOOSE_NOUN search restored fails the tighten battery (%d bite)" % mb3, mb3 > 0)
else:
    ok("found the _loose_create_phrase call to mutate", False)


def journal_run(mod, setup, n=1, env=None):
    """run mod.process n times on a STALE item with `setup(logpath)` pre-filling the shadow log; returns (sizes, log path content bytes, exception)"""
    sd = tempfile.mkdtemp(prefix="rvjl-")
    lf = os.path.join(sd, "stale_create_shadow.log")
    setup(lf)
    e = {"OVN_STATE_DIR": sd}
    e.update(env or {})
    sizes, exc = [], None

    def run():
        nonlocal exc
        open("Q.md", "w").write("# q\n" + STALE + "\n")
        for _ in range(n):
            try:
                mod.process("Q.md")
            except Exception as ex:  # noqa: BLE001
                exc = ex
            sizes.append(os.path.getsize(lf) if os.path.exists(lf) else 0)
    in_tree(STALE_TREE, run, e)
    return sizes, (open(lf, "rb").read() if os.path.exists(lf) else b""), exc


def garbage_log(lf):
    open(lf, "wb").write(b'\xff\xfe\x80garbage\n{"hash": "other"}\n')


def big_log(lf):
    with open(lf, "w") as fh:
        row = json.dumps({"rule": "would-skip stale-create", "hash": "x" * 16, "item": "y" * 150}) + "\n"
        for i in range(int(2100000 / len(row)) + 1):
            fh.write(row)


def jbattery(mod, tag):
    bad = 0

    def chk(name, cond, extra=""):
        nonlocal bad
        if not cond:
            bad += 1
            if tag == "real":
                ok(name, False, extra)
    sizes, data, exc = journal_run(mod, garbage_log)
    chk("non-UTF-8 bytes in the shadow log: process() does not raise", exc is None, repr(exc))
    chk("non-UTF-8 bytes in the shadow log: the row is still journalled", data.count(b"would-skip stale-create") == 1, data[-300:])
    sizes, data, exc = journal_run(mod, big_log, n=3)
    chk("2.1 MB log x3 process(): no exception", exc is None, repr(exc))
    chk("2.1 MB log x3: rotated to the tail at the cap (<= 2 MB after the first pass)", sizes and sizes[0] <= 2000000, sizes)
    chk("2.1 MB log x3: growth stops (later passes add nothing)", len(sizes) == 3 and sizes[1] == sizes[0] == sizes[2], sizes)
    chk("2.1 MB log x3: the item is journalled exactly once (no per-cycle re-append)", data.count(b'"rule": "would-skip stale-create", "mode": "shadow"') == 1, data.count(b"would-skip stale-create"))
    return bad


jb = jbattery(RV, "real")
ok("real module passes the journal robustness battery", jb == 0, "failed=%d" % jb)
for label, old, new in (
    ("strict decode of the tail", '.decode("utf-8", "replace")', '.decode("utf-8")'),
    ("no tail dedupe (seen empty)", "seen = _journal_tail(lf)", 'seen = ""'),
    ("no rotation at the cap", "        _journal_cap(lf)\n", "        pass\n"),
):
    if old not in src:
        ok("found %s call to mutate" % label, False)
        continue
    nsj = {"__name__": "mutant_journal"}
    exec(compile(src.replace(old, new, 1), "mutant_journal.py", "exec"), nsj)

    class MJ:
        process = staticmethod(nsj["process"])
    mj = jbattery(MJ, "mutant")
    ok("mutation: %s fails the journal battery (%d bite)" % (label, mj), mj > 0)

# the whole detector never raises into process(): a detector bug (stale_create_reason raising) is swallowed
nsr = {"__name__": "real_copy"}
exec(compile(src, "real_copy.py", "exec"), nsr)
nsr["stale_create_reason"] = lambda line: (_ for _ in ()).throw(UnicodeDecodeError("utf-8", b"\xff", 0, 1, "boom"))


def detector_raises(namespace):
    def run():
        open("Q.md", "w").write("# q\n" + STALE + "\n")
        try:
            namespace["process"]("Q.md")
            return None
        except Exception as ex:  # noqa: BLE001
            return ex
    return in_tree(STALE_TREE, run, {"OVN_STATE_DIR": tempfile.mkdtemp(prefix="rvjx-")})


ok("a raising detector never escapes process()", detector_raises(nsr) is None)
nsm = {"__name__": "mutant_try"}
exec(compile(src.replace("    except Exception:\n        pass   # the shadow detector must never raise", "    except ZeroDivisionError:\n        pass   # the shadow detector must never raise", 1), "mutant_try.py", "exec"), nsm)
nsm["stale_create_reason"] = nsr["stale_create_reason"]
ok("mutation: outer try/except removed => the raise escapes (test catches it)", detector_raises(nsm) is not None)

print("retire_vague newfile: %d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
