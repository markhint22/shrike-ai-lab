#!/usr/bin/env bash
# Regression test for ovn_stage_runner.sh's step "no-edit" detector (2026-09-09).
#
# The detector used to be `git diff --quiet "$base" HEAD && git diff --quiet`, which is BLIND to
# untracked files - `git diff` never shows a brand-new file until it's `git add`ed. Verified live:
# 63% (179/282) of all historical "no-edit" failures were "Create a new file" steps where aider had
# actually created the file successfully (log showed "Applied edit to <newfile>") but the detector
# still called it a no-op, reverted the real work, and the step retried/blocked for nothing. This is
# the single largest false-negative in the higher-tier pipeline. Fixed to `git status --porcelain`
# (which DOES see untracked files). Extracts the real condition out of ovn_stage_runner.sh so this
# can't drift from what's deployed.
set -uo pipefail
SR="${OVN_STAGE_RUNNER:-$HOME/overnight-queue/ovn_stage_runner.sh}"
[ -f "$SR" ] || { echo "  SKIP: $SR not found on this host"; exit 0; }

DETECT_LINE="$(grep -E 'elif.*status --porcelain' "$SR" | head -1)"
[ -n "$DETECT_LINE" ] || { echo "  FAIL: could not find the no-edit detection line in $SR"; exit 1; }
case "$DETECT_LINE" in
  *'status --porcelain'*) : ;;
  *) echo "  FAIL: no-edit detector doesn't look like the expected fix:"; echo "    $DETECT_LINE"; exit 1 ;;
esac

P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

is_no_edit(){ # $1 = worktree dir; mirrors the real (fixed) detector exactly
  local wt="$1"
  [ -z "$(git -C "$wt" status --porcelain 2>/dev/null)" ]
}

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
git init -q "$tmp/wt"; ( cd "$tmp/wt"; git config user.email t@t; git config user.name t
  echo base > existing.py; git add -A; git commit -q -m base )

# ---- scenario A: a brand-new untracked file (the exact incident shape) ----
( cd "$tmp/wt"; echo 'def parse_bearer(): pass' > new_file.py )
ok "a new UNTRACKED file is correctly detected as a real edit (not no-edit)" \
   "! is_no_edit '$tmp/wt'"
( cd "$tmp/wt"; git clean -qfd )

# ---- scenario B: modifying an existing tracked file (must still work, no regression) ----
( cd "$tmp/wt"; echo modified >> existing.py )
ok "modifying an existing tracked file is still detected as a real edit" \
   "! is_no_edit '$tmp/wt'"
( cd "$tmp/wt"; git checkout -q -- existing.py )

# ---- scenario C: genuinely nothing changed -> still correctly flagged as no-edit ----
ok "a truly unchanged worktree IS flagged as no-edit" \
   "is_no_edit '$tmp/wt'"

# ---- scenario D: a STAGED (git add'ed but uncommitted) new file counts as a real edit too ----
( cd "$tmp/wt"; echo staged > staged_file.py; git add staged_file.py )
ok "a staged new file is detected as a real edit" \
   "! is_no_edit '$tmp/wt'"
( cd "$tmp/wt"; git reset -q; git clean -qfd )

echo "Stage untracked-file detection: $P passed, $F failed"
[ "$F" -eq 0 ]
