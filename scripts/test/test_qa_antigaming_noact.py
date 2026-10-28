#!/usr/bin/env python3
"""2026-10-28: gate_antigaming A_VACUOUS for a NEW python test that only builds mocks and never calls the code under test (no assertion, no act). Real case:
gitlark 94a78b4a test_sync_analysis_persists_data landed as pushed(tests:pass) with zero assertions and zero calls. QA_ANTIGAMING_NOACT=off is the old behaviour
(the mutation proof: every 'fires' case must go silent with it). Benign controls: smoke test that awaits/calls code, test with assertion, helper-only setup."""
import json, os, shutil, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
GATE = os.path.join(os.environ.get("QAGATE_QA_DIR") or os.path.join(HERE, "..", "..", "qa"), "gate_antigaming.py")
PY = sys.executable
T = os.path.realpath(tempfile.mkdtemp(prefix="qa-noact-test-"))
ENV = {"PATH": "/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin", "HOME": T, "NTFY_SERVER": "http://127.0.0.1:9/x", "OVN_DIR": T, "OVN_REPOS_DIR": T,
       "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1", "QA_FETCH_WAIT": "0"}
P = F = 0
def ok(n, c, x=""):
    global P, F
    if c: P += 1; print("  ok   " + n)
    else: F += 1; print("  FAIL " + n + " :: " + x)
def sh(*a, cwd=None): return subprocess.run(a, cwd=cwd, env=ENV, capture_output=True, text=True)
n = [0]
def run(new_src, env=None):
    n[0] += 1; d = os.path.join(T, "r%d" % n[0]); os.makedirs(os.path.join(d, "backend/tests"))
    g = lambda *a: sh("git", "-C", d, "-c", "user.name=t", "-c", "user.email=t@t", *a)
    g("init", "-q")
    open(os.path.join(d, "backend/tests/test_a.py"), "w").write("def test_old():\n    assert 1 + 1 == 2\n"); g("add", "-A"); g("commit", "-qm", "a")
    open(os.path.join(d, "backend/tests/test_a.py"), "a").write(new_src); g("add", "-A"); g("commit", "-qm", "b")
    e = dict(ENV); e.update(env or {})
    p = subprocess.run(["env", "-i"] + ["%s=%s" % kv for kv in e.items()] + [PY, GATE, "check", "--repo", d, "--base", "HEAD~1", "--head", "HEAD", "--no-record"],
                       cwd=T, capture_output=True, text=True)
    r = json.loads(p.stdout.strip().splitlines()[-1])
    return [f for f in r["details"].get("findings", []) if f["rule"] == "A_VACUOUS"], r
GHOST = '''

import pytest
@pytest.mark.asyncio
async def test_sync_persists():
    """doc"""
    mock_analysis = MagicMock(spec=object)
    mock_analysis.id = "x"
    mock_analysis.at = datetime.now(timezone.utc)
    mock_db = AsyncMock()
    mock_result = MagicMock()
    mock_result.scalar_one_or_none.return_value = mock_analysis
    mock_db.execute.return_value = mock_result

    async def override_get_db():
        yield mock_db
'''
f, r = run(GHOST); ok("ghost test (mocks only, no assertion, no act) -> A_VACUOUS FAIL", f and f[0]["sev"] == "FAIL", str(r["verdict"]))
f, r = run(GHOST, {"QA_ANTIGAMING_NOACT": "off"}); ok("MUTANT/old behaviour (NOACT=off): silent -> the rule is what catches it", not f)
f, r = run(GHOST + "    assert mock_db is not None\n"); ok("BENIGN: same body plus an assertion", not f)
f, r = run(GHOST + "    resp = await client.post('/x')\n"); ok("BENIGN: body awaits code under test (smoke) is not judged", not f)
f, r = run("\n\ndef test_calls():\n    m = MagicMock()\n    do_thing(m)\n"); ok("BENIGN: calls a non-mock function (smoke test)", not f)
f, r = run("\n\ndef test_ctx():\n    m = MagicMock()\n    with patch('a.b'):\n        pass\n"); ok("BENIGN: uses a with-block (not judged)", not f)
shutil.rmtree(T, ignore_errors=True)
print("\nantigaming noact tests: %d passed, %d failed" % (P, F)); sys.exit(1 if F else 0)
