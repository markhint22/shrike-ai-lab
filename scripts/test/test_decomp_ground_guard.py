#!/usr/bin/env python3
"""Tests for scripts/ovn_decomp_ground_guard.py. Real flawed planner output from 2026-10-05 is the regression data.
Run: python3 test_decomp_ground_guard.py (exit 0 = all pass)."""
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
GUARD = os.environ.get("OVN_GUARD") or (
    os.path.join(HERE, "..", "ovn_decomp_ground_guard.py")
    if os.path.exists(os.path.join(HERE, "..", "ovn_decomp_ground_guard.py"))
    else os.path.expanduser("~/overnight-queue/scripts/ovn_decomp_ground_guard.py"))
P = F = 0


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
    else:
        F += 1
        print("  FAIL: %s  %s" % (name, extra))


def run(repo, lines):
    r = subprocess.run([sys.executable, GUARD, repo], input="\n".join(lines), capture_output=True, text=True)
    return r.returncode, [l for l in r.stdout.split("\n") if l.strip()], r.stderr


def mk(root, name, files):
    d = os.path.join(root, name)
    for rel, txt in files.items():
        p = os.path.join(d, rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        open(p, "w").write(txt)
    return d


def item(path, body, tier="T2"):
    return "- [ ] [%s] %s — %s VERIFY: `true`. (cat:python; multifile:no)" % (tier, path, body)


def main():
    root = tempfile.mkdtemp()
    try:
        iptv = mk(root, "iptv_apps", {
            "iptv-backend/app/services/url_safety.py": "async def assert_public_url(url):\n    pass\n\ndef create_safe_http_client():\n    pass\n",
            "iptv-backend/tests/test_url_safety.py": "def test_x():\n    pass\n",
            "iptv-backend/app/routers/streams.py": "async def check_stream_health():\n    pass\n",
        })
        a = item("iptv-backend/app/services/url_safety.py", "Implement `assert_public_url(url: str)` to raise SSRFError and `create_safe_http_client()` returning a client.", "T1")
        b = item("iptv-backend/tests/test_url_safety.py", "Create unit tests verifying `assert_public_url` rejects 127.0.0.1.")
        c = item("iptv-backend/app/routers/streams.py", "Modify `check_stream_health` to use `create_safe_http_client()` and catch SSRFError.", "T3")
        d = item("iptv-backend/tests/test_stream_ssrf.py", "Create integration test mocking the client.", "T4")
        rc, kept, err = run(iptv, [a, b, c, d])
        ok("exits 0", rc == 0)
        ok("drops Implement of an already-defined function", a not in kept and "already defined" in err, err)
        ok("drops Create of an already-existing test file", b not in kept and "already exists" in err, err)
        ok("keeps a Modify step on an existing function (benign control)", c in kept)
        ok("keeps a Create step for a genuinely new test file (benign control)", d in kept)
        ok("order preserved", kept == [c, d], kept)

        # Implement of a function that does NOT exist yet is a legitimate new-code step
        e = item("iptv-backend/app/services/url_safety.py", "Implement `brand_new_helper(x)` that returns x.")
        rc, kept, err = run(iptv, [e, c, d])
        ok("keeps Implement of a new symbol", e in kept, err)

        # test location: iptv tests next to app modules are never collected
        f = item("iptv-backend/app/routers/test_ghost.py", "Create a test for the router.")
        rc, kept, err = run(iptv, [f, c, d])
        ok("drops an iptv test placed under app/", f not in kept and "pytest testpaths" in err, err)

        xl = mk(root, "xlite", {"scripts/roster/roster_manager.gd": "func _load_roster() -> void:\n    pass\n",
                                "tests/test_roster_manager.gd": "extends GutTest\n"})
        g = item("test/battle/test_overwatch.gd", "Write unit test for overwatch.gd.")
        h = item("scripts/roster/roster_manager.gd", "Refactor `_load_roster()` to coerce credits.", "T3")
        i = item("tests/test_roster_load_hardening.gd", "Create a GUT test for load hardening.", "T1")
        rc, kept, err = run(xl, [g, h, i])
        ok("drops an xlite test under test/ (runner collects tests/ only)", g not in kept and "res://tests/" in err, err)
        ok("keeps Refactor of an existing function and a new tests/ file", h in kept and i in kept)

        # xlite func syntax: Implement of an existing GDScript func is dropped
        j = item("scripts/roster/roster_manager.gd", "Implement `_load_roster()` with coercion.", "T3")
        rc, kept, err = run(xl, [j, h, i])
        ok("drops Implement of an existing GDScript func", j not in kept, err)

        # fail-safe: filtering that would leave < 2 items passes everything through
        rc, kept, err = run(iptv, [a, b])
        ok("would-leave-<2 passes originals through unchanged", kept == [a, b] and "passing all" in err, (kept, err))

        # non-item lines (comments, blanks, prose) are untouched
        k = "# a comment line"
        rc, kept, err = run(iptv, [k, c, d])
        ok("non-item lines pass through", k in kept)

        # garbage / empty input never raises
        rc, kept, err = run(iptv, [])
        ok("empty input -> exit 0, no output", rc == 0 and kept == [])
        rc, kept, err = run("/definitely/not/a/dir", [a, c, d])
        ok("missing repo dir -> exit 0, items unchanged", rc == 0 and kept == [a, c, d], (rc, kept))
        rc, kept, err = run(iptv, ["- [ ] [T9] broken line", c, d])
        ok("malformed item line passes through", "- [ ] [T9] broken line" in kept)
    finally:
        shutil.rmtree(root, ignore_errors=True)
    print("decomp ground guard: %d passed, %d failed" % (P, F))
    return 1 if F else 0


if __name__ == "__main__":
    sys.exit(main())
