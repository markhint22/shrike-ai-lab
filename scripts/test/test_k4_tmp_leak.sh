#!/usr/bin/env bash
# K4 (2026-11-01): the 04:27 coverage run reported "tmp-leak: 545 entries" with five 44-50 entry 'ovn.*' top dirs. test_aider_commit_rescue.sh made 7 throwaway git repos per run and removed none:
# (1) its mk() registered them in an array from inside $(...) (lost with the subshell), (2) safe_rm_rf refuses a git checkout root and the error was swallowed. This runs the suite in a private
# TMPDIR and asserts nothing is left behind; the mutant (the old cleanup: no .git removal) must leave repos behind, proving the check has teeth.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
W="$(safe_mktemp_dir k4leak)" || exit 1
case "$W" in /*/k4leak.??????) ;; *) echo "unsafe scratch dir '$W': abort" >&2; exit 2;; esac
cleanup(){ case "$W" in /*/k4leak.??????) find "$W" -mindepth 1 -depth -delete 2>/dev/null; rmdir "$W" 2>/dev/null;; esac; }   # find -delete removes .git dirs too (safe_rm_rf refuses checkout roots)
trap cleanup EXIT
SUITE="$HERE/test_aider_commit_rescue.sh"
leftover(){ find "$1" -mindepth 1 -not -path "$1/home*" 2>/dev/null | wc -l | tr -d ' '; }
run_in(){ # <suite> <private tmpdir>
  ( safe_set_sandbox_home "$2" || exit 1; export TMPDIR="$2" OVN_TEST_ISOLATE=off; bash "$1" </dev/null >"$2/out.log" 2>&1 ); }
mkdir -p "$W/clean"; run_in "$SUITE" "$W/clean"
ok "L1 the suite still passes" 'grep -q "^9 passed, 0 failed" "$W/clean/out.log"'
ok "L2 nothing is left in its private TMPDIR (was 7 repos, ~320 entries)" '[ "$(leftover "$W/clean" | tr -d " ")" = 1 ]'   # out.log itself
# MUTANT: the old cleanup (the .git directory is not removed first)
python3 - "$SUITE" "$W/mut_suite.sh" "$HERE" <<'PY'
import sys
s = open(sys.argv[1]).read()
a = 'rm_repo(){ [ -n "$1" ] || return 0; safe_rm_rf "$1/.git" >/dev/null 2>&1; safe_rm_rf "$1" >/dev/null 2>&1; }'
assert s.count(a) == 1, "mutation anchor missing - the test is stale"
s = s.replace(a, 'rm_repo(){ [ -n "$1" ] || return 0; safe_rm_rf "$1" >/dev/null 2>&1; }')
s = s.replace('HERE="$(cd "$(dirname "$0")" && pwd)"', 'HERE="%s"' % sys.argv[3], 1)
open(sys.argv[2], "w").write(s)
PY
mkdir -p "$W/mut"; run_in "$W/mut_suite.sh" "$W/mut"
ok "M1 MUTANT (old cleanup, .git not removed first) leaves the repos behind: L2 would fail" '[ "$(leftover "$W/mut" | tr -d " ")" -gt 100 ]'
echo "  $P passed, $F failed"; [ "$F" = 0 ]
