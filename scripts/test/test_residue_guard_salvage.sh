#!/usr/bin/env bash
# Regression test for run_overnight.sh's working-tree-residue salvage check (2026-09-28).
#
# aider is invoked with --auto-test (edit -> run the test command -> commit only if it
# passes), wrapped in `timeout "$aider_timeout" aider ...`. When the test step itself is
# slow, the outer timeout can fire AFTER the test genuinely passed but BEFORE aider's own
# commit step runs, leaving a real, currently-passing change sitting uncommitted - which
# the residue guard used to silently discard and score as a bad no-op. Confirmed live on
# billwatch (logs/20260923-121347/ongoing-billwatch.log): a vitest run showed a clean
# "2 passed (2)" result, then the log ended immediately - no commit line, no error, no
# further turn, unlike every other successful flow.
#
# The fix never trusts the log text alone to decide whether to keep the residue - it
# always independently re-runs run_repo_verification() against the CURRENT working tree
# and only salvages on an explicit fresh "pass". The log-text check is purely a cheap
# gate deciding whether it's even worth paying for that re-verification.
#
# Extracts the real block out of run_overnight.sh (not a reimplementation) so this can't
# silently drift from what's deployed.
set -uo pipefail
RO="${OVN_RUN_OVERNIGHT:-$HOME/overnight-queue/run_overnight.sh}"
[ -f "$RO" ] || { echo "  SKIP: $RO not found on this host"; exit 0; }

BLOCK="$(sed -n '/if \[ "\$AFTER_SHA" = "\$BEFORE_SHA" \] && \[ -n "\$(git status --porcelain)" \]; then/,/^    fi$/p' "$RO")"
[ -n "$BLOCK" ] || { echo "  FAIL: could not extract the residue-guard salvage block from $RO"; exit 1; }
case "$BLOCK" in
  *'run_repo_verification'*'_RESIDUE_SALVAGED'*) : ;;
  *) echo "  FAIL: extracted block doesn't look like the expected salvage check:"; printf '%s\n' "$BLOCK"; exit 1 ;;
esac

P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

new_repo(){ # $1=name -> echoes repo dir with a committed baseline file
  local r="$tmp/$1"; mkdir -p "$r"
  ( cd "$r" && git init -q && git config user.email t@t.com && git config user.name t \
    && echo base > base.txt && git add -A && git commit -q -m init )
  echo "$r"
}

run_case(){ # $1=repo $2=task_log-content $3=verify-stub-result($none|pass|fail) $4=leave-residue(1|0)
  local rd="$1" logtext="$2" verify_result="$3" leave_residue="${4:-1}"
  local AFTER_SHA BEFORE_SHA task_log
  ( cd "$rd"
    BEFORE_SHA="$(git rev-parse HEAD)"
    if [ "$leave_residue" -eq 1 ]; then
      echo "residue content" > leftover.txt
      git add leftover.txt
    fi
    AFTER_SHA="$(git rev-parse HEAD)"   # nothing committed -> still equals BEFORE_SHA
    task_log="$(mktemp)"
    printf '%s\n' "$logtext" > "$task_log"
    # stub the real verification function - the test controls what "fresh re-verify"
    # would find, independent of anything the log claims
    run_repo_verification(){ echo "$verify_result"; }
    eval "$BLOCK" >/dev/null 2>&1
    echo "AFTER_SHA=$AFTER_SHA"
    echo "STATUS_PORCELAIN:[$(git status --porcelain)]"
    if git ls-files --error-unmatch leftover.txt >/dev/null 2>&1; then echo "LEFTOVER_COMMITTED"; fi
    [ -f leftover.txt ] && echo "LEFTOVER_ON_DISK"
    git log --oneline -1
  )
}

# --- A: no "passed" signal in the log at all -> unconditional discard (base case unchanged) ---
r="$(new_repo repoA)"
out="$(run_case "$r" 'model gave up, no test ever ran' none 1)"
ok "no test-passed signal: residue file is gone entirely (discarded)" "! printf '%s' \"\$out\" | grep -q LEFTOVER_ON_DISK"
ok "no test-passed signal: working tree is clean after discard" "printf '%s' \"\$out\" | grep -q 'STATUS_PORCELAIN:\[\]'"
ok "no test-passed signal: no salvage commit created (HEAD is still the init commit)" "printf '%s' \"\$out\" | grep -q init"

# --- B: log shows a passing test AND a fresh independent re-verify also says pass ->
#     SALVAGED (the exact bug this fix closes) - the file survives, COMMITTED ---
r2="$(new_repo repoB)"
out2="$(run_case "$r2" 'Test Files  1 passed (1)
Tests  2 passed (2)' pass 1)"
ok "clean pass + fresh re-verify PASS: residue file is committed, not discarded" \
   "printf '%s' \"\$out2\" | grep -q LEFTOVER_COMMITTED"
ok "clean pass + fresh re-verify PASS: working tree is clean (fully committed, nothing left dangling)" \
   "printf '%s' \"\$out2\" | grep -q 'STATUS_PORCELAIN:\[\]'"
ok "clean pass + fresh re-verify PASS: a real salvage commit was created" \
   "printf '%s' \"\$out2\" | grep -qi 'salvage'"

# --- C: log CLAIMS a pass, but the FRESH independent re-verify says fail -> the log text
#     is never trusted alone, so this still discards (safety net holds) ---
r3="$(new_repo repoC)"
out3="$(run_case "$r3" 'Tests  2 passed (2)' fail 1)"
ok "stale/misleading pass claim + fresh re-verify FAIL: residue file is gone (discarded)" \
   "! printf '%s' \"\$out3\" | grep -q LEFTOVER_ON_DISK"
ok "stale/misleading pass claim + fresh re-verify FAIL: no salvage commit" \
   "printf '%s' \"\$out3\" | grep -q init"

# --- D: log claims a pass, but fresh re-verify finds no test infra to run at all ->
#     conservative default, discard ---
r4="$(new_repo repoD)"
out4="$(run_case "$r4" 'Tests  2 passed (2)' none 1)"
ok "pass claim + fresh re-verify finds nothing to run: conservative discard" \
   "! printf '%s' \"\$out4\" | grep -q LEFTOVER_ON_DISK"

# --- E: no residue at all (clean tree) -> guard's outer condition never fires, no-op ---
r5="$(new_repo repoE)"
out5="$(run_case "$r5" 'Tests  2 passed (2)' pass 0)"
ok "clean working tree: guard does not fire at all (nothing to salvage or discard)" \
   "printf '%s' \"\$out5\" | grep -q init && ! printf '%s' \"\$out5\" | grep -qi 'salvage'"

echo "residue-guard salvage check: $P passed, $F failed"
[ "$F" -eq 0 ]
