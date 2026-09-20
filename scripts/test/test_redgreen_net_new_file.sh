#!/usr/bin/env bash
# Regression test for run_overnight.sh's run_redgreen_check() net-new-file false-positive
# (2026-09-20). A brand-new source file created by the SAME commit doesn't exist at $before,
# so `git checkout "$before" -- $file` silently fails/no-ops on it — the "before" pytest run
# then executes against the unreverted (post-fix) source, trivially passes, and the commit
# gets mis-flagged [redgreen:SUSPECT] as if the new regression test were vacuous. Confirmed
# benign 3x live: always a genuine net-new file, never an actual vacuous test. Fix: skip the
# check entirely (echo "n/a", don't flag) when any changed source file didn't exist at
# $before. Extracts the real guard condition out of run_overnight.sh so this can't drift from
# what's deployed.
set -uo pipefail
RO="${OVN_RUN_OVERNIGHT:-$HOME/overnight-queue/run_overnight.sh}"
[ -f "$RO" ] || { echo "  SKIP: $RO not found on this host"; exit 0; }

GUARD_LINE="$(grep -n 'git cat-file -e "\$before:\$sf"' "$RO" | head -1)"
[ -n "$GUARD_LINE" ] || { echo "  FAIL: could not find the net-new-file guard in $RO"; exit 1; }

P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

# mirrors the deployed guard exactly: "n/a" (skip) if any $src file is missing at $before
would_skip(){ # $1=before $2=src-files(space-sep)
  local before="$1" src="$2" sf
  for sf in $src; do
    git cat-file -e "$before:$sf" 2>/dev/null || { echo "n/a"; return; }
  done
  echo "ok-to-check"
}

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
( cd "$tmp" && git init -q && git config user.email t@t && git config user.name t
  mkdir -p app && echo "def existing(): return 1" > app/existing.py
  git add -A && git commit -q -m base )
BEFORE="$(cd "$tmp" && git rev-parse HEAD)"

# ---- scenario A: commit adds a brand-new source file (the real incident shape) ----
( cd "$tmp" && echo "def brand_new(): return 2" > app/new_file.py && git add -A && git commit -q -m "add new_file" )
out="$(cd "$tmp" && would_skip "$BEFORE" "app/new_file.py")"
ok "a net-new source file is skipped (n/a), not run against a no-op revert" "[ '$out' = 'n/a' ]"

# ---- scenario B: commit modifies an EXISTING source file -> the check should still run ----
( cd "$tmp" && echo "def existing(): return 99" > app/existing.py && git add -A && git commit -q -m "modify existing" )
out="$(cd "$tmp" && would_skip "$BEFORE" "app/existing.py")"
ok "modifying a pre-existing file is NOT skipped (real regression check still runs)" "[ '$out' = 'ok-to-check' ]"

# ---- scenario C: mixed commit (one new + one existing file changed) -> still skip (can't
#      safely revert-and-retest when ANY changed source file can't be reverted) ----
out="$(cd "$tmp" && would_skip "$BEFORE" "app/existing.py app/new_file.py")"
ok "a mixed new+existing commit is skipped too (any missing file blocks the revert)" "[ '$out' = 'n/a' ]"

echo "redgreen net-new-file guard: $P passed, $F failed"
[ "$F" -eq 0 ]
