#!/usr/bin/env bash
# In-loop test feedback fix: after aider AUTO-COMMITS an edit the tree is clean, so ovn_autotest.sh (aider --test-cmd) saw no changed files and
# exited 0 - a failing new test sailed through. With OVN_BASE_SHA it must run the scoped tests and exit non-zero. Also covers the per-repo
# opt-in helper (scripts/lib_autotest_base.sh).
Q="$(cd "$(dirname "$0")/../.." && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
P=0; F=0; ok(){ if [ "$2" = 1 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
R="$T/repo"; mkdir -p "$R/backend/.venv/bin" "$R/backend/tests"
# stub pytest: exits 1 (and says which file) when a test file passed on its command line contains FAILME
cat > "$R/backend/.venv/bin/pytest" <<'S'
#!/usr/bin/env bash
for a in "$@"; do [ -f "$a" ] && grep -q FAILME "$a" && { echo "FAILED $a - assertion error"; exit 1; }; done
echo "1 passed"; exit 0
S
chmod +x "$R/backend/.venv/bin/pytest"
( cd "$R" && git init -q -b main && echo 'def f(): return 1' > backend/mod.py && git add -A && git -c core.hooksPath=/dev/null commit -q -m base )
BASE="$(git -C "$R" rev-parse HEAD)"
# the model's edit, AUTO-COMMITTED by aider (tree clean afterwards)
printf 'def test_f():\n    assert f() == 2  # FAILME\n' > "$R/backend/tests/test_mod.py"
( cd "$R" && git add backend/tests/test_mod.py && git commit -q -m "aider: add test" )
AT="$Q/scripts/ovn_autotest.sh"
( env -u OVN_BASE_SHA bash "$AT" "$R" >/dev/null 2>&1 ); rc_old=$?
ok "CHARACTERISATION of the old bug: committed failing test + clean tree + no OVN_BASE_SHA => autotest exits 0 (blind)" "$([ $rc_old = 0 ] && echo 1 || echo 0)"
out="$(OVN_BASE_SHA="$BASE" bash "$AT" "$R" 2>&1)"; rc_new=$?
ok "FIX: with OVN_BASE_SHA the committed failing test is run and the autotest exits NON-zero" "$([ $rc_new != 0 ] && echo 1 || echo 0)"
ok "the model sees the failing test name in the output (feedback it can act on)" "$(echo "$out" | grep -q 'FAILED backend/tests/test_mod.py\|FAILED tests/test_mod.py' && echo 1 || echo 0)"
printf 'def test_f():\n    assert f() == 1\n' > "$R/backend/tests/test_mod.py"
( cd "$R" && git add backend/tests/test_mod.py && git commit -q -m "aider: fix test" )
OVN_BASE_SHA="$BASE" bash "$AT" "$R" >/dev/null 2>&1; ok "with OVN_BASE_SHA and a PASSING committed test => exits 0" "$([ $? = 0 ] && echo 1 || echo 0)"
OVN_BASE_SHA="deadbeefdeadbeef" bash "$AT" "$R" >/dev/null 2>&1; ok "an invalid OVN_BASE_SHA falls back to the old behaviour (exit 0, no crash)" "$([ $? = 0 ] && echo 1 || echo 0)"
OVN_BASE_SHA="$(git -C "$R" rev-parse HEAD)" bash "$AT" "$R" >/dev/null 2>&1; ok "OVN_BASE_SHA == HEAD (nothing changed since) => exits 0" "$([ $? = 0 ] && echo 1 || echo 0)"
# ---- per-repo opt-in helper
. "$Q/scripts/lib_autotest_base.sh"
mkdir -p "$T/state"; cd "$R"
unset OVN_BASE_SHA; ovn_autotest_base_export billwatch "$BASE" "$T/state"; ok "no list file => OVN_BASE_SHA stays unset" "$([ -z "${OVN_BASE_SHA:-}" ] && echo 1 || echo 0)"
echo "gitlark" > "$T/state/autotest_basesha_repos.txt"; ovn_autotest_base_export billwatch "$BASE" "$T/state"; ok "repo not listed => unset" "$([ -z "${OVN_BASE_SHA:-}" ] && echo 1 || echo 0)"
printf 'gitlark\nbillwatch\n' > "$T/state/autotest_basesha_repos.txt"; ovn_autotest_base_export billwatch "$BASE" "$T/state"; ok "repo listed => exported" "$([ "${OVN_BASE_SHA:-}" = "$BASE" ] && echo 1 || echo 0)"
ovn_autotest_base_export gitlark "$BASE" "$T/state"; ovn_autotest_base_export shrike-monitor "$BASE" "$T/state"; ok "next repo not listed => the previous export is CLEARED (no leakage across cycles)" "$([ -z "${OVN_BASE_SHA:-}" ] && echo 1 || echo 0)"
echo "all" > "$T/state/autotest_basesha_repos.txt"; ovn_autotest_base_export anything "$BASE" "$T/state"; ok "'all' enables every repo" "$([ "${OVN_BASE_SHA:-}" = "$BASE" ] && echo 1 || echo 0)"
OVN_AUTOTEST_BASESHA=off ovn_autotest_base_export anything "$BASE" "$T/state"; ok "OVN_AUTOTEST_BASESHA=off kill switch wins even for 'all'" "$([ -z "${OVN_BASE_SHA:-}" ] && echo 1 || echo 0)"
ovn_autotest_base_export anything "notasha" "$T/state"; ok "a non-commit sha => unset" "$([ -z "${OVN_BASE_SHA:-}" ] && echo 1 || echo 0)"
ovn_autotest_base_export billwatch "" "$T/state"; ok "empty sha => unset, returns 0" "$([ -z "${OVN_BASE_SHA:-}" ] && echo 1 || echo 0)"
printf 'billwatch-extra\n' > "$T/state/autotest_basesha_repos.txt"; ovn_autotest_base_export billwatch "$BASE" "$T/state"; ok "whole-line match only ('billwatch-extra' does not enable 'billwatch')" "$([ -z "${OVN_BASE_SHA:-}" ] && echo 1 || echo 0)"
ok "run_overnight.sh calls the helper right before the implement loop" "$(grep -B1 -A1 'ovn_autotest_base_export "\$(basename' "$Q/run_overnight.sh" | grep -q 'ATTEMPT=1' && echo 1 || echo 0)"
echo "  $P passed, $F failed"; [ "$F" = 0 ]
