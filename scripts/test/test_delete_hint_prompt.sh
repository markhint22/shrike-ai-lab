#!/usr/bin/env bash
# Regression test for run_overnight.sh's deletion-hint prompt guidance (2026-09-20).
# aider's udiff edit format has no way to express "delete a file" — a "--- x / +++
# /dev/null" hunk always fails here with "'/dev/null' is not in the subpath of ..."
# (confirmed live: iptv_apps's test_dvr_sweep_job.py deletion item burned a full failed
# udiff attempt + a multi-paragraph self-argument, 92k-172k tokens, before falling back
# to the working DELETE: trailer on a LATER cycle). Mirrors the deployed detection regex
# exactly so this can't drift; asserts it's purely additive (only fires on delete-shaped
# item text, real non-deletion item text is completely unaffected).
set -uo pipefail
RO="${OVN_RUN_OVERNIGHT:-$HOME/overnight-queue/run_overnight.sh}"
[ -f "$RO" ] || { echo "  SKIP: $RO not found on this host"; exit 0; }

DETECT_LINE="$(grep -n 'Deletion-hint prompt guidance' "$RO" | head -1)"
[ -n "$DETECT_LINE" ] || { echo "  FAIL: deletion-hint prompt guidance not found in $RO"; exit 1; }
REGEX="$(grep -oE "grep -qiE '[^']+'" "$RO" | grep -F 'delete' | head -1 | sed -E "s/^grep -qiE '//; s/'\$//")"
[ -n "$REGEX" ] || { echo "  FAIL: could not extract the deployed detection regex from $RO"; exit 1; }

P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

is_delete_shaped(){ printf '%s' "$1" | grep -qiE "$REGEX"; }

# ---- real observed failure case (2026-09-20, iptv_apps) ----
ok "real delete item text is detected" \
  'is_delete_shaped "Delete the obsolete test file iptv-backend/tests/test_dvr_sweep_job.py as it is replaced by test_downloads_expiry_sweep_job.py."'

# ---- other plausible delete phrasings ----
ok "\"remove ... file\" phrasing is detected" \
  'is_delete_shaped "Remove the unused config file iptv-backend/config/legacy.yaml."'
ok "\"file ... should be deleted\" (reversed order) is detected" \
  'is_delete_shaped "The file utils/old_helper.py should be deleted, superseded by new_helper.py."'

# ---- non-deletion items must NOT be affected (this is purely additive guidance) ----
ok "a plain test-writing item is unaffected" \
  '! is_delete_shaped "Add a new unit test for PaywallViewModel covering loadOfferings()."'
ok "an in-place bugfix mentioning removal of a value (not a file) is unaffected" \
  '! is_delete_shaped "Fix the off-by-one error in mark_for_deletion() so pending_deletion items are removed correctly."'
ok "removing an unused import (editing a file, not deleting one) is unaffected" \
  '! is_delete_shaped "Remove the unused import from api_usage.py"'
ok "a refactor that removes duplicate code (not a file) is unaffected" \
  '! is_delete_shaped "Refactor BillingRepositoryTest.kt to remove duplicate mock setup"'

echo "delete-hint prompt guidance: $P passed, $F failed"
[ "$F" -eq 0 ]
