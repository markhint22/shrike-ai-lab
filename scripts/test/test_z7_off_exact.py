#!/usr/bin/env python3
"""Z7 review fix 1: OVN_Z7_ASSERT_RECALL=off must restore the pre-Z7 assert-weaken output EXACTLY (the `!=` alternative in the negative-assert regex, the `!=`->`==` polarity
fold, and the extra `src_changed`/`tier` keys are all behind the switch). fixtures/z7_off_exact/preZ7_assert_weaken.py is the verbatim pre-Z7 slice of ovn_landing_gates.py
(_NEG_ASSERT_RE .. check_assert_weaken at origin/claude/feature 5c0b4118); it is exec'd on top of the live module's helpers and its output is diffed against the live off-mode output
on a corpus of diffs. Z7_MODULE_DIR=<dir> runs the same check against a mutant copy."""
import importlib.util, json, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
MODDIR = os.environ.get("Z7_MODULE_DIR") or os.path.abspath(os.path.join(HERE, ".."))
spec = importlib.util.spec_from_file_location("ovn_landing_gates", os.path.join(MODDIR, "ovn_landing_gates.py"))
G = importlib.util.module_from_spec(spec)
spec.loader.exec_module(G)
ns = dict(G.__dict__)
exec(compile(open(os.path.join(HERE, "fixtures", "z7_off_exact", "preZ7_assert_weaken.py")).read(), "preZ7", "exec"), ns)
PRE = ns["check_assert_weaken"]
P = F = 0


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1; print("  ok   " + name)
    else:
        F += 1; print("  FAIL " + name + ((" :: " + str(extra)) if extra else ""))


def fdiff(path, removed=(), added=(), start=10):
    h = "diff --git a/%s b/%s\n--- a/%s\n+++ b/%s\n@@ -%d,%d +%d,%d @@\n" % (path, path, path, path, start, len(removed), start, len(added))
    return h + "".join("-%s\n" % r for r in removed) + "".join("+%s\n" % a for a in added)


T = "backend/tests/test_a.py"
SRC = fdiff("backend/app/x.py", ["    return 1"], ["    return 2"])
CORPUS = [
    [fdiff(T, ["    assert a != b"], ["    assert a == b"])],
    [fdiff(T, ["    assert a != b"], ["    assert c == d"])],
    [fdiff(T, ["    assert a != b"], ["    assert a"])],
    [fdiff(T, ["    assert a != b", "    assert c != d"], [])],
    [fdiff(T, ["    assert x != y"], ["    pass"])],
    [fdiff(T, ['    assert "s" not in out'], ['    assert "s" in out'])],
    [fdiff(T, ['    assert "s" not in out'], ['    assert out'])],
    [SRC, fdiff(T, ['    assert "s" not in out'], ['    assert "s" in out'])],
    [SRC, fdiff(T, ["    assert r.status_code == 404"], ["    assert r.status_code == 200"])],
    [SRC, fdiff(T, ["    assert t == 60.0"], ["    assert t == 0.5"])],
    [SRC, fdiff(T, ["    assert t == 60.0", "    assert u == 1"], [])],
    [fdiff(T, ["def test_a():", "    assert t == 1"], [])],
    [fdiff(T, ["    assert assertNotEqual(a, b)", "    self.assertNotEqual(a, b)"], ["    self.assertEqual(a, b)"])],
    [fdiff("web/src/__tests__/a.test.ts", ["    expect(o).not.toContain('s')"], ["    expect(o).toContain('s')"])],
    [fdiff(T, ["    assert x == 1", "    assert y == 2"], ["    assert x"])],
    [fdiff(T, ["    assert len(x) == 3"], ["    assert x"])],
    [fdiff(T, ["    assert r.status_code == 200"], ["    assert r.status_code == 500"])],
]
OLD = "@pytest.mark.parametrize('a', [1, 2])\ndef test_a(a):\n    assert a\n"
try:
    for i, c in enumerate(CORPUS):
        for old_fn in (None, (lambda _p: OLD)):
            for env in ("off", "OFF"):
                os.environ["OVN_Z7_ASSERT_RECALL"] = env
                try:
                    fds = G.parse_diff("".join(c))
                    live = G.check_assert_weaken(fds, old_fn)
                    pre = PRE(G.parse_diff("".join(c)), old_fn)
                finally:
                    del os.environ["OVN_Z7_ASSERT_RECALL"]
                ok("case %d off(%s) == pre-Z7 output" % (i, env), json.dumps(live, sort_keys=True) == json.dumps(pre, sort_keys=True), (live, pre))
                if env == "off" and old_fn is None:
                    ok("case %d off: no src_changed/tier keys" % i, all("src_changed" not in f and "tier" not in f for f in live), live)
    # `!=` -> `==` is only a pre-Z7 hit when Z7 is on: the corpus must actually exercise the difference
    os.environ.pop("OVN_Z7_ASSERT_RECALL", None)
    on = G.check_assert_weaken(G.parse_diff("".join(CORPUS[0])), None)
    ok("sanity: on-mode differs for the `!=` flip (the corpus exercises the switch)", on and on[0]["kind"] == "polarity-flip" and "tier" in on[0], on)
    ok("sanity: polarity key folds != only when on", G._polarity_key("assert a != b") == G._polarity_key("assert a == b"))
    os.environ["OVN_Z7_ASSERT_RECALL"] = "off"
    ok("polarity key does NOT fold != when off", G._polarity_key("assert a != b") != G._polarity_key("assert a == b"))
    ok("neg-assert regex ignores `assert a != b` when off", not G._NEG_ASSERT_RE.search("    assert a != b"))
    del os.environ["OVN_Z7_ASSERT_RECALL"]
    ok("neg-assert regex matches `assert a != b` when on", bool(G._NEG_ASSERT_RE.search("    assert a != b")))
finally:
    os.environ.pop("OVN_Z7_ASSERT_RECALL", None)
print("passed=%d failed=%d" % (P, F))
sys.exit(1 if F else 0)
