#!/usr/bin/env bash
# Regression test (2026-10-14, review finding): suites that cannot run on a host (missing source file, no flock/timeout, bash < 4) used to print SKIP and exit 0, so run_all.sh reported
# them green without a single assertion (the hygiene infra-skip suite is vacuous on the default macOS bash 3.2 without flock). They now exit 77 (NOT RUN) and run_all.sh counts them.
# Every assertion here FAILS on the old code (rc 0 instead of 77). Copies of the real suites are run from a throwaway tree, so the real files are never touched.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }   # 2026-10-16: fail-closed sandbox helpers (see lint_unsafe_rm.py)
HERE="$(cd "$(dirname "$0")" && pwd)"
P=0; F=0
ok(){ if [ "$2" = "1" ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }
T="$(safe_mktemp_dir)" || exit 1; trap 'rm -rf "$T"' EXIT
safe_set_sandbox_home "$T" || exit 1; mkdir -p "$HOME"

# 1) source file missing next to a copied suite -> NOT RUN (77), not a silent green
mkdir -p "$T/nosrc/test"; cp "$HERE/test_auto_credit_lockfile.sh" "$HERE/lib_safe_tmp.sh" "$T/nosrc/test/"
( bash "$T/nosrc/test/test_auto_credit_lockfile.sh" >"$T/o1" 2>&1 ); rc1=$?
ok "1a auto-credit lockfile suite without lib_auto_credit.sh exits 77 (rc=$rc1)" "$([ "$rc1" = 77 ] && echo 1 || echo 0)"
ok "1b and says NOT RUN" "$(grep -q 'NOT RUN' "$T/o1" && echo 1 || echo 0)"

mkdir -p "$T/nogit/test"; cp "$HERE/test_git_sync_size_guard.sh" "$HERE/lib_safe_tmp.sh" "$T/nogit/test/"
( bash "$T/nogit/test/test_git_sync_size_guard.sh" >"$T/o2" 2>&1 ); rc2=$?
ok "1c git sync size guard suite without ovn_git_sync.sh exits 77 (rc=$rc2)" "$([ "$rc2" = 77 ] && echo 1 || echo 0)"

# 2) no flock on PATH (the macOS default) -> NOT RUN (77). PATH holds only git + dirname so the suite's own prerequisite check is what decides.
BIN="$T/bin"; mkdir -p "$BIN"
for t in git dirname; do p="$(command -v $t 2>/dev/null)"; [ -n "$p" ] && ln -sf "$p" "$BIN/$t"; done
( env -i HOME="$HOME" PATH="$BIN" /bin/bash "$HERE/test_hygiene_infra_skip.sh" >"$T/o3" 2>&1 ); rc3=$?
ok "2a hygiene infra-skip suite without flock/timeout exits 77 (rc=$rc3)" "$([ "$rc3" = 77 ] && echo 1 || echo 0)"
ok "2b and says it needs flock/timeout or bash 4, never a bare SKIP" "$(grep -q 'NOT RUN' "$T/o3" && ! grep -q 'SKIP:' "$T/o3" && echo 1 || echo 0)"

# 3) run_all.sh's wrapper (run_or_notrun) and verdict (finish) are the one place that decides. The REAL definitions are extracted from run_all.sh and run against fake
#    suites (exit 77 / 0 / 1), so a broken counter or a green banner over NOT RUN suites fails here (2026-10-14 review: the old grep-only check could not catch that).
R="$T/runall"; mkdir -p "$R"
{ grep '^run_or_notrun(' "$HERE/run_all.sh"; awk '/^finish\(\)\{/,/^\}$/' "$HERE/run_all.sh"; } > "$R/fns.sh"
printf 'exit 77\n' > "$R/nr.sh"; printf 'exit 0\n' > "$R/ok.sh"; printf 'exit 1\n' > "$R/bad.sh"
run_case(){   # $1 = output file, rest = fake suites run through run_or_notrun in order; records the final verdict's rc + counters
  local o="$1"; shift
  ( rc=0; NOTRUN=0; cd "$R" || exit 99; . "$R/fns.sh"
    for x in "$@"; do run_or_notrun "$x" >/dev/null 2>&1; done
    finish >"$o" 2>&1; echo "frc=$? rc=$rc notrun=$NOTRUN" >>"$o" )
}
run_case "$T/a.out" "$R/nr.sh"
ok "3a a NOT RUN (77) suite is counted, not a failure: rc stays 0, NOTRUN=1" "$(grep -q '^frc=1 rc=0 notrun=1$' "$T/a.out" && echo 1 || echo 0)"
ok "3b a run with only NOT RUN suites is NOT green: finish returns nonzero" "$(grep -q 'NOT VERIFIED' "$T/a.out" && echo 1 || echo 0)"
ok "3c and never prints ALL QUEUE TESTS PASS" "$(grep -q 'ALL QUEUE TESTS PASS' "$T/a.out" && echo 0 || echo 1)"
run_case "$T/b.out" "$R/ok.sh"
ok "3d an all-pass run is green: finish returns 0 and prints ALL QUEUE TESTS PASS" "$(grep -q '^frc=0 rc=0 notrun=0$' "$T/b.out" && grep -q 'ALL QUEUE TESTS PASS' "$T/b.out" && echo 1 || echo 0)"
run_case "$T/c.out" "$R/nr.sh" "$R/ok.sh"
ok "3e one NOT RUN plus one pass is still NOT verified (nonzero, never green)" "$(grep -q '^frc=1 rc=0 notrun=1$' "$T/c.out" && echo 1 || echo 0)"
run_case "$T/d.out" "$R/bad.sh" "$R/nr.sh"
ok "3f a failing suite wins over NOT RUN: rc=1 and SOME QUEUE TESTS FAILED" "$(grep -q '^frc=1 rc=1 notrun=1$' "$T/d.out" && grep -q 'SOME QUEUE TESTS FAILED' "$T/d.out" && echo 1 || echo 0)"
ok "3g run_all.sh routes the GNU-only stage suites through run_or_notrun" "$(grep -q 'run_or_notrun test_stage_file_feed.sh' "$HERE/run_all.sh" && grep -q 'run_or_notrun test_stage_retry_signature.sh' "$HERE/run_all.sh" && echo 1 || echo 0)"

echo "test_suite_notrun_exit: $P passed, $F failed"
[ "$F" = 0 ]
