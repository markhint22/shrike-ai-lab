#!/usr/bin/env python3
"""Z7-A (2026-11-09): assert-weaken RECALL extension in scripts/ovn_landing_gates.py (kinds polarity-flip, status-flip-src, literal-swap, assertion-deleted, orphan-assert-deleted).
Fixtures are the real 2026-11-09 incident diffs (shrike-monitor deacf45, shrike-notify df2145b, iptv 61e0665d / 02064345, TAA 9d860b32) plus negative controls taken from the
7-day corpus run (iptv_apps 5965ca3f-style label rename, gitlark 42f32009, a de-duplication). test_z7_assert_recall.sh re-runs this file against mutated copies of the module
(Z7_MODULE_DIR=<dir with the mutated ovn_landing_gates.py>) and every mutant must be killed."""
import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MODDIR = os.environ.get("Z7_MODULE_DIR") or os.path.abspath(os.path.join(HERE, ".."))
spec = importlib.util.spec_from_file_location("ovn_landing_gates", os.path.join(MODDIR, "ovn_landing_gates.py"))
G = importlib.util.module_from_spec(spec)
spec.loader.exec_module(G)
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


def run(diffs, old=None, new=None, repair=False):
    fds = G.parse_diff("".join(diffs))
    return G.check_assert_weaken(fds, (lambda _p: old) if old is not None else None, (lambda _p: new) if new is not None else None, repair=repair)


def kinds(fs):
    return sorted(set(f["kind"] for f in fs))


print("== Z7-A polarity-flip (shrike-monitor deacf45)")
T = "backend/tests/test_redact_url_query_secrets.py"
SRC = fdiff("backend/app/utils/redact_url.py", ["    return urlunparse(p._replace(query=query))"], ["    return urlunparse(p._replace(query=parsed.query))"])
t = fdiff(T, ['    assert "secret=xyz" not in result', '    assert "other=val" not in result', '    assert "?***" in result'], ['    assert "secret=xyz" in result', '    assert "other=val" in result', '    assert "?secret=xyz&other=val" in result'])
f = run([SRC, t])
ok("A1 `assert \"secret=xyz\" not in out` -> `assert \"secret=xyz\" in out` (same literal) is flagged polarity-flip", "polarity-flip" in kinds(f), f)
ok("A1b ...with the strong tier and src_changed", all(x["tier"] == "strong" and x["src_changed"] for x in f if x["kind"] == "polarity-flip"), f)
f = run([t])
ok("A1c ...flagged also without a source change (test-only expectation flip)", "polarity-flip" in kinds(f), f)
f = run([fdiff("backend/tests/test_a.py", ["    assert a != b"], ["    assert a == b"])])
ok("A2 `!=` -> `==` on the same operands is flagged", "polarity-flip" in kinds(f), f)
f = run([fdiff("web/src/__tests__/a.test.ts", ["    expect(out).not.toContain('secret')"], ["    expect(out).toContain('secret')"])])
ok("A3 JS `.not.toContain('secret')` -> `.toContain('secret')` is flagged", "polarity-flip" in kinds(f), f)
f = run([fdiff("backend/tests/test_a.py", ["    assert x not in out"], ["    assert y in out"])])
ok("A4 a negative replaced by a positive on a DIFFERENT literal is not a polarity flip", "polarity-flip" not in kinds(f), f)
f = run([fdiff("backend/tests/test_a.py", ["def test_a():", '    assert "x" not in out'], ["def test_b():", '    assert "x" in out'])])
ok("A5 a test whose def line changed (rewritten test) is not judged", f == [], f)
os.environ["OVN_Z7_ASSERT_RECALL"] = "off"
f = run([SRC, t])
ok("A6 OVN_Z7_ASSERT_RECALL=off restores the Z5 behaviour (no polarity-flip)", "polarity-flip" not in kinds(f), f)
del os.environ["OVN_Z7_ASSERT_RECALL"]

print("== Z7-A literal-swap (shrike-notify df2145b)")
SRC = fdiff("backend/app/utils/publish_client.py", ["            return max_retry_after"], ["            return 0.0"])
T = "backend/tests/test_publish_client_retry_after_nonfinite.py"
t = fdiff(T, ["    assert sleep_calls[0] == 60.0"], ["    assert sleep_calls[0] == 0.5"])
f = run([SRC, t], repair=True)
ok("B1 `== 60.0` -> `== 0.5` with a source edit that does not contain 0.5 is flagged literal-swap", kinds(f) == ["literal-swap"], f)
ok("B1b ...strong tier for a repair commit, weak for a plain step", f[0]["tier"] == "strong" and run([SRC, t])[0]["tier"] == "weak", f)
f = run([t])
ok("B2 the same swap WITHOUT a source change is not flagged (a test-only literal fix)", f == [], f)
SRC2 = fdiff("backend/app/utils/publish_client.py", ["            return max_retry_after"], ["            return 0.5"])
f = run([SRC2, t])
ok("B3 the new value is introduced by the source diff itself (a deliberate change the test follows): not flagged", f == [], f)
f = run([fdiff("web/src/pages/P.vue", ['          aria-label="Test plan"'], ['          aria-label="Test plan (JSON)"']),
         fdiff("web/src/pages/__tests__/P.spec.js", ["    expect(w.find('textarea[aria-label=\"Test plan\"]').element.value).toBe('')"], ["    expect(w.find('textarea[aria-label=\"Test plan (JSON)\"]').element.value).toBe('')"])])
ok("B4 a label rename followed by the test (new text appears in the source diff): not flagged", f == [], f)
f = run([SRC, fdiff("backend/tests/test_a.py", ["    x = 60.0", "    assert sleep_calls[0] == 60.0"], ["    x = 60.0", "    assert sleep_calls[0] == x"])])
ok("B5 literal replaced by a name is not a literal swap", "literal-swap" not in kinds(f), f)
f = run([SRC, fdiff("backend/tests/test_a.py", ["# was 60.0"], ["# now 0.5"])])
ok("B6 comment-only changes are ignored", f == [], f)
f = run([SRC, fdiff("backend/tests/test_a.py", ["    assert r.json()['n'] > 3"], ["    assert r.json()['n'] > 5"])])
ok("B7 only equality-shaped assertions count (`>` thresholds are not swapped literals)", "literal-swap" not in kinds(f), f)

print("== Z7-A status-flip-src")
SRC = fdiff("iptv-backend/app/auth.py", ["    a"], ["    b"])
for code in ("401", "403", "404", "422"):
    f = run([SRC, fdiff("iptv-backend/tests/test_device_auth.py", ["    assert r.status_code == %s" % code], ["    assert r.status_code == 200"])])
    ok("C1 %s -> 200 with a source edit is flagged status-flip-src (strong)" % code, kinds(f) == ["status-flip-src"] and f[0]["tier"] == "strong", f)
f = run([SRC, fdiff("iptv-backend/tests/test_device_auth.py", ["    assert r.status_code == 404"], ["    assert r.status_code == 403"])])
ok("C2 404 -> 403 with a source edit is not a status flip (stays unflagged: the literal appears... not 2xx)", "status-flip-src" not in kinds(f), f)
f = run([fdiff("iptv-backend/tests/test_device_auth.py", ["    assert r.status_code == 404"], ["    assert r.status_code == 200"])])
ok("C3 without a source edit the Z5 status-flip applies, not status-flip-src", kinds(f) == ["status-flip"], f)

print("== Z7-A assertion-deleted / orphan-assert-deleted")
f = run([fdiff("backend/tests/test_assertion_prefix_parity.py", ["    # Should be valid", '    assert result["valid"] is True'], [])])
ok("D1 TAA 9d860b32: an assertion removed with nothing in its place is flagged assertion-deleted", kinds(f) == ["assertion-deleted"], f)
f = run([fdiff("backend/tests/test_a.py", ["    assert result is not None"], [])])
ok("D2 deleting a bare existence check is not flagged (low value)", f == [], f)
f = run([fdiff("backend/tests/test_a.py", ['    assert result["valid"] is True'], [])], new='def test_a():\n    assert result["valid"] is True\n')
ok("D3 an assertion that still exists elsewhere in the new file (de-duplication) is not flagged", f == [], f)
f = run([fdiff("backend/tests/test_a.py", ['    assert result["valid"] is True'], ['    assert result["valid"] is True'])])
ok("D4 an assertion moved (same text added) is not flagged", f == [], f)
f = run([fdiff("backend/tests/test_a.py", ['    assert x == 1'], ['    assert y == 1', '    assert z == 2'])])
ok("D5 an assertion replaced by assertions is not flagged", f == [], f)
rem = ["def test_register_with_73_byte_password_returns_422(client):", '    resp = client.post("/api/auth/register", json={})', "    assert resp.status_code == 422", '    assert data["pin_required"] is False']
f = run([fdiff("iptv-backend/tests/test_routers_auth.py", rem, [])], new="def test_login(client):\n    data = {}\n")
ok("D6 iptv 61e0665d: a block of removed tests also removes an assertion whose subject (`data`) belongs to a surviving test -> orphan-assert-deleted", kinds(f) == ["orphan-assert-deleted"] and "pin_required" in f[0]["text"], f)
rem = ["def test_dup(client):", '    resp = client.post("/x")', "    assert resp.status_code == 422", '    assert budget.remaining() == 1']
f = run([fdiff("billwatch-backend/tests/test_llm.py", rem, [])], new="def test_dup(client):\n    pass\n")
ok("D7 a removed test that is still defined elsewhere in the file (duplicate) is not judged orphan", f == [], f)
f = run([fdiff("billwatch-backend/tests/test_llm.py", ["def test_a(client):", "    thing = client.get('/')", "    assert thing.status_code == 422"], [])])
ok("D8 a removed whole test whose assertion subject is bound inside it is not an orphan", f == [], f)
f = run([fdiff("scripts/tests/test_mission.gd", ["func test_a() -> void:", "\tassert_eq(editor._x, 5)"], [])], new="")
ok("D9 orphan check is Python-only (a GDScript test retirement stays silent)", f == [], f)
f = run([fdiff("backend/tests/test_a.py", ['    assert "x" not in body', '    assert "y" not in body'], ['    assert resp.status_code == 200'])])
ok("D10 the more specific Z5 kind wins over assertion-deleted (no double report)", kinds(f) == ["negative-removed"], f)

print("== Z7-A analyse() wiring")
res = G.analyse(fdiff("backend/app/utils/redact_url.py", ["    return a"], ["    return b"]) + fdiff("backend/tests/test_r.py", ['    assert "s=1" not in out'], ['    assert "s=1" in out']), "tidy", "[T3] x", "repair", "")
ok("E1 analyse() carries the Z7 findings under 'assert-weaken' (tier + src_changed present)", [x["kind"] for x in res["assert-weaken"]] == ["polarity-flip"] and res["assert-weaken"][0]["src_changed"] is True, res["assert-weaken"])

print("\n%d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
