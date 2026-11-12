#!/usr/bin/env bash
# 2026-11-11 (pkg q-xlite-verify): run_repo_verification must run stdlib-unittest python tests when no .venv/bin/pytest exists (the xlite case:
# tools/tests/test_tres_format.py made EVERY xlite cycle end error(verify-skipped - lock contended)); a genuinely runner-less python test still
# fails closed (skip) but the status says so; a genuine repo-owned lock-contention skip still says "lock contended".
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_ro_core.sh"
ro_init
ro_tasks '[]'
ro_source
set +e

task_log="$T/vut.task.log"; : > "$task_log"
V="$T/v"
newrepo(){ rm -rf "${V:?}"; mkdir -p "$V"; cd "$V" || exit 1; git init -q; echo base > README; git add -A; git commit -q -m base; BEFORE_SHA="$(git rev-parse HEAD)"; : > "$task_log"; }
commit_files(){ git add -A; git commit -q -m c; }

UT_OK='import unittest
class T(unittest.TestCase):
    def test_a(self):
        self.assertEqual(1, 1)
if __name__ == "__main__":
    unittest.main()
'
UT_RED='import unittest
class T(unittest.TestCase):
    def test_a(self):
        self.assertEqual(1, 2)
'

echo "--- xlite replay: unittest test, no .venv ---"
newrepo; mkdir -p tools/tests; printf '%s' "$UT_OK" > tools/tests/test_x.py; commit_files
r="$(run_repo_verification)"
eq "unittest-only repo, no venv, green -> pass (was skip)" pass "$r"
has "log names the unittest runner" "$(cat "$task_log")" "verify: unittest tools/tests/test_x.py"

echo "--- red unittest is a real fail ---"
newrepo; mkdir -p tools/tests; printf '%s' "$UT_RED" > tools/tests/test_x.py; commit_files
eq "red unittest -> fail" fail "$(run_repo_verification)"
has "red mark recorded" "$(cat "$task_log")" "verify-suite-red: unittest"

echo "--- pytest-style test, no runner: still fail-closed, status names the path ---"
newrepo; mkdir -p tools/tests; printf 'def test_a():\n    assert True\n' > tools/tests/test_p.py; commit_files
off="$(wc -c < "$task_log" | tr -d ' ')"
eq "pytest-style test without pytest -> skip" skip "$(run_repo_verification)"
st="$(ovn_verify_skip_status "$off")"
eq "status names the missing runner and path" "error(verify-skipped - no python test runner for tools/tests/test_p.py, retry next cycle)" "$st"
ok "no-runner status does not say lock contended" "$(case "$st" in *"lock contended"*) echo 0;; *) echo 1;; esac)"

echo "--- genuine lock contention still reports the lock message ---"
newrepo; printf '#!/bin/bash\necho "SKIPPED — venv lock contended, not treating as a failure"\nexit 0\n' > .ovn-verify.sh; chmod +x .ovn-verify.sh; commit_files
off="$(wc -c < "$task_log" | tr -d ' ')"
eq "lock-contended repo script -> skip" skip "$(run_repo_verification)"
eq "lock status unchanged" "error(verify-skipped - lock contended, retry next cycle)" "$(ovn_verify_skip_status "$off")"

echo "--- a stale no-runner marker from an EARLIER verify run does not leak ---"
newrepo; echo '--- verify: NO PYTHON TEST RUNNER for old/path.py ---' >> "$task_log"
off="$(wc -c < "$task_log" | tr -d ' ')"
eq "marker before offset ignored" "error(verify-skipped - lock contended, retry next cycle)" "$(ovn_verify_skip_status "$off")"

echo "--- unittest detection requires a real TestCase; 0 tests ran fails closed (skip, never pass/red) ---"
newrepo; mkdir -p tools/tests; printf 'from unittest import mock\ndef test_a():\n    with mock.patch("os.getcwd"):\n        assert True\n' > tools/tests/test_m.py; commit_files
eq "pytest-style file importing unittest.mock -> skip (not pass, not fail)" skip "$(run_repo_verification)"
has "status names the path" "$(ovn_verify_skip_status 0)" "no python test runner for tools/tests/test_m.py"
newrepo; mkdir -p tools/tests; printf 'import unittest\nclass T(unittest.TestCase):\n    pass\n' > tools/tests/test_z.py; commit_files
eq "TestCase file with 0 tests -> skip" skip "$(run_repo_verification)"
newrepo; mkdir -p tools/tests; printf 'from unittest import TestCase\nclass T(TestCase):\n    def helper(self):\n        pass\n' > tools/tests/test_z.py; commit_files
eq "from-unittest-import-TestCase with 0 tests -> skip" skip "$(run_repo_verification)"
newrepo; mkdir -p tools/tests; printf 'from unittest import TestCase\nclass T(TestCase):\n    def test_a(self):\n        self.assertTrue(True)\n' > tools/tests/test_z.py; commit_files
eq "from-unittest-import-TestCase with a test -> pass" pass "$(run_repo_verification)"
echo "--- sibling module import (tools/helper.py from tools/tests) works ---"
newrepo; mkdir -p tools/tests; printf 'VALUE = 7\n' > tools/helper.py
printf 'import unittest\nimport helper\nclass T(unittest.TestCase):\n    def test_a(self):\n        self.assertEqual(helper.VALUE, 7)\n' > tools/tests/test_s.py; commit_files
eq "TestCase with sibling import -> runs and passes" pass "$(run_repo_verification)"
has "log shows it ran" "$(cat "$task_log")" "Ran 1 test"

echo "--- kill switch ---"
newrepo; mkdir -p tools/tests; printf '%s' "$UT_OK" > tools/tests/test_x.py; commit_files
eq "OVN_VERIFY_UNITTEST=0 restores the fail-closed skip" skip "$(OVN_VERIFY_UNITTEST=0 run_repo_verification)"

echo "--- both VERIFY-SKIP guard call sites use the computed status (no hardcoded lock message) ---"
eq "no hardcoded lock-contended status echo left in run_overnight.sh" 0 "$(grep -c '^ *echo "error(verify-skipped - lock contended' "$RO_SCRIPT")"
eq "first-verify and post-fixup guards both call ovn_verify_skip_status" 2 "$(grep -c '^        ovn_verify_skip_status ' "$RO_SCRIPT")"

ro_summary
