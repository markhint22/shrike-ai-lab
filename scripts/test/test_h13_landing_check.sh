#!/usr/bin/env bash
# test_h13_landing_check.sh - 2026-10-04 (h13 task 2). LANDING CHECK bookkeeping in run_aider_fix_task:
#  (a) the log/alert names the sha that actually failed (not always AFTER_SHA);
#  (b) a Tier-2 fix-up that REWRITES the verified commit (amend) supersedes the pre-fix-up sha: the landed work must be counted as landed
#      (00:47 CDT incident: a landed commit was recorded error-transient while it was on origin). The true-loss case (commit reset away
#      before the push) must stay caught, including a reset AFTER a fix-up.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_ro_aider2_fixture.sh"
eval "$(declare -f mk_case | sed '1s/mk_case/_mk_case_orig/')"
mk_case(){ _mk_case_orig "$@"; rm -rf "$TREE/state/nr_reverts" "$TREE"/state/baseline_fail_* "$TREE"/state/cycle_active_*; }

FAILOUT='echo "FAILED tests/test_vod.py::test_vod - assert 3 == 4"; echo "== 1 failed, 4 passed in 0.50s =="'
# verify: BEFORE tree (init) green; the model's commit "feat: p" is red; the amended commit "feat: p fixed" is green
FIXV='s="$(git log -1 --format=%s)"; case "$s" in "feat: p") '"$FAILOUT"'; exit 1;; esac; exit 0'

# ---- (b) BENIGN-for-the-fix: fix-up amends the commit (pre-fix-up sha no longer reachable) => the landed work counts as pushed
mk_case amend_ok
scout_ok
aplan 2 'gc app.py "def p(): return 1" "feat: p"'
aplan 3 'printf "def p(): return 2\n" >> app.py; git add -A; git commit -q --amend -m "feat: p fixed"'
vplan default "$FIXV"
echo "tests/test_vod.py::test_vod - assert 3 == 4" > "$CASE_DIR/extract.out"
run_case
ok "h13b: Tier-2 fix-up ran and re-verified green" 'logged "Tier-2 fix-up re-verify: pass"'
ok "h13b: fix-up rewrote the commit => cycle is recorded as pushed, not commit-lost" '[[ "$OUT" == pushed* ]]'
ok "h13b: the fixed commit is on origin" 'origin_has claude/feature "feat: p fixed"'
ok "h13b: the superseded pre-fix-up commit is NOT on origin (it really was rewritten)" '! origin_has claude/feature "feat: p"$'
ok "h13b: no landing-check alert" '! grep -q "commit-lost-before-push" <<< "$ALERTS"'

# ---- (b) NEGATIVE control: fix-up amends, then the fixed commit is reset away before the push => still caught (true loss not weakened)
mk_case amend_then_lost
scout_ok
aplan 2 'gc app.py "def p(): return 1" "feat: p"'
aplan 3 'printf "def p(): return 2\n" >> app.py; git add -A; git commit -q --amend -m "feat: p fixed"'
vplan default 's="$(git log -1 --format=%s)"; case "$s" in "feat: p") '"$FAILOUT"'; exit 1;; "feat: p fixed") git reset -q --hard origin/claude/feature; exit 0;; esac; exit 0'
echo "tests/test_vod.py::test_vod - assert 3 == 4" > "$CASE_DIR/extract.out"
run_case
eq "h13b NEG: commit reset away after the fix-up => error-transient(commit-lost-before-push)" "$OUT" "error-transient(commit-lost-before-push)"
ok "h13b NEG: the fixed commit is not on origin" '! origin_has claude/feature "feat: p fixed"'

# ---- (a) the logged / alerted sha is the lost one. Pre-existing true-loss shape (no fix-up): record the sha, reset it away.
mk_case lost_sha
scout_ok
aplan 2 'gc app.py "def p(): return 1" "feat: p"'
vplan default 'git rev-parse HEAD > "$CASE_DIR/lost.sha"; git reset -q --hard origin/claude/feature; exit 0'
run_case
eq "h13a NEG: lost commit => error-transient(commit-lost-before-push)" "$OUT" "error-transient(commit-lost-before-push)"
LS="$(cut -c1-12 "$CASE_DIR/lost.sha")"
ok "h13a: LANDING CHECK log names the lost sha" 'logged "LANDING CHECK: ${LS} is NOT reachable"'
ok "h13a: alert names the lost sha" 'grep -q "commit ${LS} not reachable" <<< "$ALERTS"'

# ---- benign control: ordinary clean cycle still lands
mk_case clean
scout_ok
aplan 2 'gc app.py "def p(): return 1" "feat: p"'
vplan default 'exit 0'
run_case
ok "h13: clean cycle still lands" '[[ "$OUT" == pushed* ]] && origin_has claude/feature "feat: p"'
summary
