#!/usr/bin/env bash
# QA harness-X X2 (2026-10-02): run_redgreen_check must restore the source ATOMICALLY and VERIFIABLY.
# Incident: 2026-10-02 13:14 CDT the restore half failed and left a half-reverted tree/INDEX (`git checkout $before -- $src` stages); the next
# bare `git commit` swept it into history and reverted verified billwatch source. Now: worktree-only revert/restore (index never touched), restore
# verified against AFTER for every path, fallbacks (direct write, hard reset), and an explicit verdict the caller acts on:
#   ok | suspect | n/a | restore-failed (tree confirmed at AFTER only via a fallback: flag + skip credit) | restore-failed-dirty (hold, do not push)
# Drives the real run_redgreen_check() with a stub venv pytest that can sabotage the restore.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_ro_aider2_fixture.sh"

# fixture: BEFORE (hello returns 1) -> AFTER (source fixed + test changed); stub pytest controlled by $CASE_DIR/pytest.mode
mk_rg() {
  mk_case "rg_$1"; scout_ok
  cd "$REPO" || exit 1
  git checkout -q claude/feature 2>/dev/null
  RG_BEFORE="$(git rev-parse HEAD)"
  printf 'def hello():\n    return 2\n' > app.py
  printf 'from app import hello\n\ndef test_hello():\n    assert hello() == 2\n' > tests/test_app.py
  git add -A; git commit -q -m "fix: hello returns 2 + regression test"
  RG_AFTER="$(git rev-parse HEAD)"
  mkdir -p .venv/bin
  cat > .venv/bin/pytest <<'PY'
#!/bin/bash
# records what the reverted source / the index looked like DURING the run, then behaves per mode
d="${CASE_DIR:?}"
cp app.py "$d/app.during" 2>/dev/null
git diff --cached --quiet && echo clean > "$d/index.during" || echo STAGED > "$d/index.during"
mode="$(cat "$d/pytest.mode" 2>/dev/null)"
case "$mode" in
  fail) exit 1;;
  pass) exit 0;;
  lock) touch .git/index.lock; chmod 444 app.py 2>/dev/null; [ "$(cat "$d/pytest.lockonly" 2>/dev/null)" = 1 ] && chmod 644 app.py; exit 1;;
esac
exit 0
PY
  chmod +x .venv/bin/pytest
  task_log="$TASK_LOG"; id="t-redgreen"; : > "$task_log"; : > "$TREE/state/alerts.log"
}
rg() { RGOUT="$(run_redgreen_check "$RG_BEFORE" "$RG_AFTER" 2>/dev/null)"; RGLOG="$(cat "$TASK_LOG")"; RGALERTS="$(cat "$TREE/state/alerts.log" 2>/dev/null)"; }
at_after() { git diff --quiet "$RG_AFTER" -- . && git diff --cached --quiet "$RG_AFTER" -- . && [ "$(git rev-parse HEAD)" = "$RG_AFTER" ]; }

# 1. the check works: new test FAILS on the pre-fix source -> ok; source really was reverted DURING the run, index never touched, tree restored
mk_rg ok; echo fail > "$CASE_DIR/pytest.mode"; rg
eq "A: test fails on pre-fix source -> ok" "$RGOUT" ok
ok "A: pytest saw the PRE-FIX source" 'grep -q "return 1" "$CASE_DIR/app.during"'
eq "A: the index was never staged during the run (worktree-only revert)" "$(cat "$CASE_DIR/index.during")" clean
ok "A: tree + index back at AFTER" at_after
ok "A: no alert" '[ -z "$RGALERTS" ]'
# 2. suspect: test passes without the fix
mk_rg suspect; echo pass > "$CASE_DIR/pytest.mode"; rg
eq "B: test passes without the fix -> suspect" "$RGOUT" suspect
ok "B: tree + index back at AFTER" at_after
# 3. the restore step FAILS (index.lock appears mid-run): the direct-write fallback confirms the tree, the cycle is flagged and credit skipped
mk_rg lockonly; echo lock > "$CASE_DIR/pytest.mode"; echo 1 > "$CASE_DIR/pytest.lockonly"; rg
eq "C: restore blocked by index.lock -> restore-failed (recovered via fallback)" "$RGOUT" restore-failed
ok "C: app.py content is AFTER (not the half-reverted BEFORE content)" 'grep -q "return 2" app.py && ! grep -q "return 1" app.py'
ok "C: tree vs AFTER equal on tracked paths (worktree)" 'git diff --quiet "$RG_AFTER" -- app.py'
ok "C: the cycle is flagged in alerts.log" 'printf "%s" "$RGALERTS" | grep -q "red-green restore could not be confirmed"'
ok "C: the log says the restore was NOT confirmed" 'printf "%s" "$RGLOG" | grep -q "RESTORE NOT CONFIRMED"'
rm -f .git/index.lock
# 4. restore fails AND nothing can repair it (lock + read-only file): dirty verdict so the caller holds the cycle
mk_rg dirty; echo lock > "$CASE_DIR/pytest.mode"; rg
eq "D: unrecoverable -> restore-failed-dirty" "$RGOUT" restore-failed-dirty
ok "D: alert says the hard reset did not restore the tree" 'printf "%s" "$RGALERTS" | grep -q "hard reset did not restore"'
chmod 644 app.py 2>/dev/null; rm -f .git/index.lock
# 5. git restore (restore step) fails but the hard reset heals it: a git wrapper simulates the failing restore, app.py is read-only so the direct write fails too
mk_rg hardreset; echo pass > "$CASE_DIR/pytest.mode"
git() { if [ "${1:-}" = restore ] && [[ "${2:-}" == "--source=$RG_AFTER" ]]; then return 128; fi; command git "$@"; }
printf '#!/bin/bash\nchmod 444 app.py; exit 0\n' > .venv/bin/pytest
rg; unset -f git
eq "E: restore fails, direct write blocked, hard reset heals -> restore-failed" "$RGOUT" restore-failed
ok "E: tree at AFTER (hard reset)" at_after
ok "E: flagged" 'printf "%s" "$RGALERTS" | grep -q "red-green restore could not be confirmed"'
chmod 644 app.py 2>/dev/null
# 6. net-new source file (nothing to revert) is still skipped without touching the tree
mk_rg netnew; git -C "$REPO" checkout -q "$RG_BEFORE" 2>/dev/null; git -C "$REPO" checkout -q claude/feature
printf 'def brand_new():\n    return 3\n' > brand_new.py; printf 'def test_n():\n    assert True\n' > tests/test_n.py; git add -A; git commit -q -m "feat: brand new"
RG_BEFORE="$RG_AFTER"; RG_AFTER="$(git rev-parse HEAD)"; echo fail > "$CASE_DIR/pytest.mode"; rg
eq "F: net-new source file -> n/a (guard preserved)" "$RGOUT" "n/a"
ok "F: tree at AFTER" at_after

# 6b. a bugfix commit that DELETES a source file (harness-X X2b): no spurious restore-failed, no zero-byte stray resurrected, tree at AFTER
mk_rg del; git -C "$REPO" checkout -q "$RG_BEFORE" 2>/dev/null; git -C "$REPO" checkout -q claude/feature
printf 'def legacy():\n    return 9\n' > legacy.py; git add legacy.py; git commit -q -m "chore: add legacy"
RG_BEFORE="$(git rev-parse HEAD)"
git rm -q legacy.py; printf 'def hello():\n    return 5\n' > app.py; printf 'def test_d():\n    assert True\n' > tests/test_d.py
git add app.py tests/test_d.py; git commit -q -m "fix: drop legacy, hello returns 5"
RG_AFTER="$(git rev-parse HEAD)"; echo fail > "$CASE_DIR/pytest.mode"; rg
eq "I: deleted source file -> ok (not restore-failed)" "$RGOUT" ok
ok "I: no stray legacy.py resurrected" '[ ! -e legacy.py ]'
ok "I: git status clean of untracked/changed source" '[ -z "$(git status --porcelain --untracked-files=all -- app.py legacy.py tests)" ]'
ok "I: tree + index back at AFTER" at_after
ok "I: no alert" '[ -z "$RGALERTS" ]'
ok "I: pytest saw the PRE-FIX app.py (return 2), not the fixed one" 'grep -q "return 2" "$CASE_DIR/app.during"'

# 8. end to end through run_aider_fix_task: a restore that cannot be confirmed skips EVERY credit path and flags the push; the tick never lands
cd "$W" || exit 1
mk_case rg_e2e; scout_ok
printf '.venv/\n' >> "$REPO/.git/info/exclude"; mkdir -p "$REPO/.venv/bin"
cat > "$REPO/.venv/bin/pytest" <<'PY'
#!/bin/bash
touch .git/index.lock; exit 1
PY
chmod +x "$REPO/.venv/bin/pytest"
aplan 2 "gc OVERNIGHT_PROGRESS.md '- [ ] app.py — Make hello return 2. VERIFY: \`grep -q \"return 2\" app.py\`' 'docs: queue item'
printf 'def hello():\n    return 2\n' > app.py; printf 'from app import hello\n\ndef test_hello():\n    assert hello() == 2\n' > tests/test_app.py; git add -A; git commit -q -m 'fix: hello returns 2

DONE: Make hello return 2'"
run_case
ok "H: the cycle still pushes, flagged RESTORE-FAILED" '[[ "$OUT" == *"[redgreen:RESTORE-FAILED]"* ]]'
ok "H: restore-failed logged by the caller" 'logged "RED-GREEN RESTORE not confirmed"'
ok "H: alert raised" 'printf "%s" "$ALERTS" | grep -q "red-green restore could not be confirmed"'
ok "H: NO item ticked (auto-credit skipped)" '! git -C "$ORIGIN" show claude/feature:OVERNIGHT_PROGRESS.md | grep -q "^- \[x\]"'
ok "H: no bookkeeping / auto-credit commit on origin (DONE: trailer path skipped too)" '! origin_has claude/feature "auto-credit" && ! origin_has claude/feature "progress bookkeeping"'
rm -f "$REPO/.git/index.lock"

# 7. the caller acts on the verdicts (static wiring in run_overnight.sh)
RO="$Q/run_overnight.sh"
ok "G: caller holds the cycle on restore-failed-dirty (no push)" 'grep -q "restore-failed-dirty)" "$RO" && grep -q "error(redgreen-restore-failed" "$RO"'
ok "G: caller skips credit paths on restore-failed" 'grep -q "_skip_credit=1" "$RO" && grep -q "\"\$_skip_credit\" = 0 \] && \[ -f \"OVERNIGHT_PROGRESS.md\"" "$RO"'
ok "G: red-green no longer uses index-writing git checkout" '! sed -n "/^run_redgreen_check()/,/^_redgreen_restored()/p" "$RO" | grep -q "git checkout"'
summary
