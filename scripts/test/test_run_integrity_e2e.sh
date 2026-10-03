#!/usr/bin/env bash
# test_run_integrity_e2e.sh - 2026-10-03, integrity track (A5/A6). END-TO-END through the real run_aider_fix_task (same hermetic fixture as
# test_run_overnight_aider2_gates.sh): a repo with a PRE-EXISTING red test, a commit that is reset away before the push, a GUT-free cycle marker.
# Every behaviour has a NEGATIVE control (the seeded defect is caught) and a BENIGN control (clean input passes).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_ro_aider2_fixture.sh"

reset_hd(){ git -C "$REPO" rev-parse origin/main; }
# every case starts with clean integrity state (baseline cache, per-item revert counters, cycle markers live under the shared fake tree)
eval "$(declare -f mk_case | sed '1s/mk_case/_mk_case_orig/')"
mk_case(){ _mk_case_orig "$@"; rm -rf "$TREE/state/nr_reverts" "$TREE"/state/baseline_fail_* "$TREE"/state/cycle_active_*; }

PRE='echo "FAILED tests/test_app.py::test_old - assert 1 == 2"; echo "== 1 failed, 4 passed in 0.50s =="'
NEWRED='echo "FAILED tests/test_app.py::test_old - assert 1 == 2"; echo "FAILED tests/test_vod.py::test_vod - assert 3 == 4"; echo "== 2 failed, 3 passed in 0.50s =="'
# verify snippet: BEFORE_SHA (subject "init") shows only the pre-existing failure; the model's commit adds a new one
vsplit(){ vplan default "if [ \"\$(git log -1 --format=%s)\" = init ]; then $1; else $2; fi; exit 1"; }

# ---------- A5 BENIGN: a pre-existing red test + a clean model commit => the commit LANDS (no revert)
mk_case pre_red
scout_ok
aplan 2 'gc app.py "def p(): return 1" "feat: p"'
vplan default "$PRE; exit 1"
run_case
ok "A5: pre-existing red + clean commit => pushed (not reverted)" '[[ "$OUT" == pushed* ]]'
ok "A5: status carries the baseline-red marker" '[[ "$OUT" == *"[baseline-red:1]"* ]]'
ok "A5: log says every failing test already failed at BEFORE_SHA" 'logged "NO-NEW-RED BASELINE: all 1 failing test(s) were ALREADY failing"'
ok "A5: commit is on origin" 'origin_has claude/feature "feat: p"'
ok "A5: alert tells a human the baseline is red" 'grep -q "baseline is red" <<< "$ALERTS"'
ok "A5: no revert logged" '! logged "NO-NEW-RED GUARD: commit left the suite red"'
ok "A5: baseline cache written for BEFORE_SHA" 'ls "$TREE"/state/baseline_fail_repo_*.txt >/dev/null 2>&1'
ok "A5: no Tier-2 fix-up wasted on a pre-existing failure" '! logged "Tier-2 fix-up: one bounded attempt"'

# ---------- A5 NEGATIVE: the commit adds a NEW failing test on top of the pre-existing one => still reverted
mk_case new_red
scout_ok
aplan 2 'gc app.py "def p(): return 1" "feat: p"'
vsplit "$PRE" "$NEWRED"
run_case
eq "A5 NEG: a new failing id => no-op(reverted-red)" "$OUT" "no-op(reverted-red)"
ok "A5 NEG: baseline status logged as subtracted with 1 new id" 'logged "NO-NEW-RED BASELINE: status=subtracted new=1 baseline=1"'
ok "A5 NEG: clone reset to the pre-commit state" '[ "$(repo_head)" = "$(reset_hd)" ]'
ok "A5 NEG: nothing pushed" '! origin_has claude/feature "feat: p"'

# ---------- A5: the fix-up prompt only carries the NEW failure, and only claims 'PASSED before' when a baseline proved it
mk_case prompt_verified
scout_ok
aplan 2 'gc app.py "def p(): return 1" "feat: p"'
aplan 3 'echo "no idea"'
vsplit "$PRE" "$NEWRED"
echo "tests/test_vod.py::test_vod - assert 3 == 4" > "$CASE_DIR/extract.out"
run_case
ok "A5: fix-up ran for the new failure" 'logged "Tier-2 fix-up: one bounded attempt"'
ok "A5: prompt names the NEW failing test" 'grep -q "tests/test_vod.py::test_vod" "$CASE_DIR/aider.args.3"'
ok "A5 NEG: prompt does NOT name the pre-existing failing test" '! grep -q "tests/test_app.py::test_old" "$CASE_DIR/aider.args.3"'
ok "A5: prompt tells the model other tests were already failing" 'grep -q "ALREADY failing before" "$CASE_DIR/aider.args.3"'
ok "A5: baseline verified => the PASSED-before direction is kept" 'grep -q "PASSED before the committed change" "$CASE_DIR/aider.args.3"'
mk_case prompt_unverified
scout_ok
aplan 2 'gc app.py "def p(): return 1" "feat: p"'
aplan 3 'echo "no idea"'
vplan default 'if [ "$(git log -1 --format=%s)" = init ]; then echo "ovn-verify: SKIPPED — venv lock contended, not treating as a failure"; exit 0; else echo "FAILED tests/test_vod.py::test_vod - assert"; echo "== 1 failed, 4 passed in 0.5s =="; exit 1; fi'
echo "tests/test_vod.py::test_vod - assert" > "$CASE_DIR/extract.out"
run_case
ok "A5: baseline could not run => baseline-unknown logged" 'logged "status=baseline-unknown"'
ok "A5 NEG: unverified baseline => the prompt does NOT claim the test PASSED before" '! grep -q "PASSED before" "$CASE_DIR/aider.args.3" && grep -q "may ALREADY have been failing" "$CASE_DIR/aider.args.3"'
eq "A5: unverified baseline => old behaviour, still reverted" "$OUT" "no-op(reverted-red)"

# ---------- A5: a GREEN baseline keeps the old behaviour (every failing id is new red)
mk_case green_base
scout_ok
aplan 2 'gc app.py "def p(): return 1" "feat: p"'
vplan default 'if [ "$(git log -1 --format=%s)" = init ]; then echo "5 passed in 0.5s"; exit 0; else echo "FAILED tests/test_vod.py::test_vod - assert"; echo "== 1 failed, 4 passed in 0.5s =="; exit 1; fi'
run_case
eq "A5: green baseline + red commit => reverted" "$OUT" "no-op(reverted-red)"
ok "A5: baseline-green logged" 'logged "status=baseline-green"'

# ---------- A5: same item reverted twice for the same OLDER failing test => NEEDS-DECISION, parked
mk_case needs_dec
scout_ok
aplan 2 'gc app.py "def p(): return 1" "feat: p"'
aplan 3 'scout PROCEED "change hello in app.py to return 2" "app.py"'
aplan 4 'gc app.py "def p2(): return 2" "feat: p2"'
vsplit "$PRE" "$NEWRED"
run_case
eq "A5 ND: first revert is an ordinary no-op(reverted-red)" "$OUT" "no-op(reverted-red)"
eq "A5 ND: ... and the item is NOT tagged yet" 0 "$(grep -c 'NEEDS-DECISION' "$REPO/OVERNIGHT_PROGRESS.md")"
run_case
eq "A5 ND: second revert, same item, same older failing test" "$OUT" "no-op(reverted-red)"
eq "A5 ND: the item is now tagged AUTO-SKIP NEEDS-DECISION (selectors skip it)" 1 "$(grep -c 'AUTO-SKIP NEEDS-DECISION' "$REPO/OVERNIGHT_PROGRESS.md")"
ok "A5 ND: log + alert say so" 'logged "item tagged NEEDS-DECISION" && grep -q "NEEDS-DECISION: item reverted" <<< "$ALERTS"'
ok "A5 ND: the model commit is still gone (only the tag commit is on top)" '! grep -q "def p2" "$REPO/app.py"'
mk_case needs_dec_ctl
scout_ok
aplan 2 'gc app.py "def p(): return 1" "feat: p"'
aplan 3 'scout PROCEED "change hello in app.py to return 2" "app.py"'
aplan 4 'gc app.py "def p2(): return 2" "feat: p2"'
vplan default 'if [ "$(git log -1 --format=%s)" = init ]; then '"$PRE"'; else echo "FAILED tests/test_app.py::test_old - x"; echo "FAILED tests/test_$(cat "$CASE_DIR/newid").py::t - y"; echo "== 2 failed, 3 passed in 0.5s =="; fi; exit 1'
echo vod > "$CASE_DIR/newid"; run_case
echo other > "$CASE_DIR/newid"; run_case
eq "A5 ND BENIGN control: reverts for DIFFERENT new failing tests never tag the item" 0 "$(grep -c 'NEEDS-DECISION' "$REPO/OVERNIGHT_PROGRESS.md")"

# ---------- A5 ND (reviewer major): the model's commit TICKS its own item [x]. The item to park must be resolved against the BEFORE tree, so the
# responsible item ("Fix hello") is tagged and the NEXT unchecked item ("Add a test for other.py") is NOT. The failing id carries & and \ (sed specials).
mk_case needs_dec_ticked
scout_ok
TICK='sed -i "s/^- \[ \] Fix .hello. in app.py to return 2/- [x] Fix hello done/" OVERNIGHT_PROGRESS.md'
aplan 2 "$TICK; gc app.py 'def p(): return 1' 'feat: p'"
aplan 3 'scout PROCEED "change hello in app.py to return 2" "app.py"'
aplan 4 "$TICK; gc app.py 'def p2(): return 2' 'feat: p2'"
NEWRED_SPEC='echo "FAILED tests/test_app.py::test_old - assert 1 == 2"; echo "FAILED tests/test_v&d\\x.py::test_vod - assert"; echo "== 2 failed, 3 passed in 0.50s =="'
vsplit "$PRE" "$NEWRED_SPEC"
run_case; run_case
eq "A5 ND ticked: both reverts are no-op(reverted-red)" "$OUT" "no-op(reverted-red)"
ok "A5 ND ticked: the RESPONSIBLE item (Fix hello) is tagged NEEDS-DECISION" 'grep -q "^- \[ \] \[AUTO-SKIP NEEDS-DECISION.*Fix .hello. in app.py" "$REPO/OVERNIGHT_PROGRESS.md"'
ok "A5 ND ticked NEGATIVE: the NEXT item (Add a test for other.py) is NOT tagged" '! grep -q "AUTO-SKIP.*Add a test for other.py" "$REPO/OVERNIGHT_PROGRESS.md" && grep -q "^- \[ \] Add a test for other.py" "$REPO/OVERNIGHT_PROGRESS.md"'
ok "A5 ND ticked: & and backslash in the failing id reach the tag verbatim (not sed-expanded)" 'grep -qF "test_v&d\\x.py" "$REPO/OVERNIGHT_PROGRESS.md"'
ok "A5 ND ticked: the revert counter was keyed on the BEFORE-tree item, so the 2nd revert (not a 3rd) parked it" 'logged "reverted 2x for the same older failing test"'

# ---------- A6 NEGATIVE: the commit is reset away mid-cycle (park sweep) before the push => NOT "landed"
mk_case lost
scout_ok
aplan 2 'gc app.py "def p(): return 1" "feat: p"'
vplan default 'echo ok; git reset -q --hard origin/claude/feature; exit 0'
run_case
eq "A6 NEG: commit lost before the push => error-transient(commit-lost-before-push)" "$OUT" "error-transient(commit-lost-before-push)"
ok "A6 NEG: not recorded as landed (no 'pushed' status)" '[[ "$OUT" != pushed* ]]'
ok "A6 NEG: log + alert name the lost commit" 'logged "LANDING CHECK" && grep -q "commit-lost-before-push" <<< "$ALERTS"'
ok "A6 NEG: the commit is not on origin" '! origin_has claude/feature "feat: p"'
# A6 BENIGN: an ordinary clean cycle still lands
mk_case landed_ok
scout_ok
aplan 2 'gc app.py "def p(): return 1" "feat: p"'
vplan default 'echo ok; exit 0'
run_case
ok "A6: clean cycle still lands as pushed(tests:pass)" '[[ "$OUT" == pushed* ]]'
ok "A6: ... and the commit really is on origin" 'origin_has claude/feature "feat: p"'
# A6 BENIGN: push rejected -> rebase path still lands when the commit is reachable
mk_case rebase_ok
scout_ok
aplan 2 'gc app.py "def p(): return 1" "feat: p"'
vplan default 'echo ok; ( cd "$CASE_DIR/other" && git fetch -q origin && git checkout -q -B tmp origin/claude/feature && echo z >> other.py && git add -A && git commit -q -m "concurrent push" && git push -q origin tmp:claude/feature ) >/dev/null 2>&1; exit 0'
run_case
eq "A6: rejected push + rebase + reachable => pushed(after-rebase)" "$OUT" "pushed(after-rebase)"
ok "A6: both the concurrent commit and ours are on origin" 'origin_has claude/feature "concurrent push" && origin_has claude/feature "feat: p"'

# ---------- A6: the per-repo cycle marker exists DURING the cycle and is gone after
mk_case marker
scout_ok
aplan 2 'gc app.py "def p(): return 1" "feat: p"'
vplan default 'cp "$CASE_DIR/../../tree/state/cycle_active_repo" "$CASE_DIR/marker.seen" 2>/dev/null; echo ok; exit 0'
rm -f "$TREE/state/cycle_active_repo"
run_case
ok "A6: marker state/cycle_active_<repo> existed while the cycle ran (park sweep / enqueue_fix key off it)" '[ -s "$CASE_DIR/marker.seen" ]'
ok "A6: marker content is a pid" 'grep -qE "^[0-9]+$" "$CASE_DIR/marker.seen"'
ok "A6: marker removed when the cycle ends" '[ ! -e "$TREE/state/cycle_active_repo" ]'
mk_case marker_noop
aplan 1 'scout ALREADY-DONE "nothing to do" "app.py"'
run_case
ok "A6: marker also removed on an early-exit (scout no-op) path" '[ ! -e "$TREE/state/cycle_active_repo" ]'

# ---------- A6: auto-credit runs identical VERIFY commands once (via the real runner path)
# (unit-level dedupe is covered in test_run_integrity_lib.sh; here: the runner sources the lib and the memo vars exist)
ok "A6: lib_auto_credit enables the per-call verify memo" 'grep -q "_VC_MEMO_ON=1" "$Q/scripts/lib_auto_credit.sh"'

summary
