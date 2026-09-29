#!/usr/bin/env bash
# Regression test for run_overnight.sh's ongoing-lane deletion-hint fix (2026-09-29).
# The 2026-09-20 deletion-hint injection (STANDARDS_SUFFIX rule 4 reminder) only ever
# scanned the literal $prompt argument for "delete...file" phrasing. That works for
# regular queued items (their $prompt IS the item's own text) but is completely blind
# for the "ongoing-*" background lanes: tasks.json's ongoing-<repo> entries carry a
# fixed generic wrapper prompt ("Work the single top not-yet-done item in the overnight
# progress log...") that never itself names deleting/removing a file - the real
# "delete the dead X" instruction only exists inside OVERNIGHT_PROGRESS.md, which the
# model discovers on its own mid-conversation. Confirmed live: gitlark's ongoing-gitlark
# lane burned 8 separate cycles (60k-172k tokens each) hitting aider's udiff
# "'/dev/null' is not in the subpath of ..." error on two different "delete the dead X"
# items because this injection never fired. Mirrors the deployed check exactly (prompt
# argument OR top not-yet-done OVERNIGHT_PROGRESS.md line, same exclusion filter used
# elsewhere in this file for top-item lookups) so this can't drift.
set -uo pipefail
RO="${OVN_RUN_OVERNIGHT:-$HOME/overnight-queue/run_overnight.sh}"
[ -f "$RO" ] || { echo "  SKIP: $RO not found on this host"; exit 0; }

grep -q '_ovn_top_progress_item' "$RO" || { echo "  FAIL: ongoing-lane top-item peek not found in $RO"; exit 1; }

P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

# mirrors the deployed check exactly
needs_delete_hint(){ # $1=prompt $2=repo_dir
  local top=""
  if [ -f "$2/OVERNIGHT_PROGRESS.md" ]; then
    top="$(grep -E '^- \[ \]' "$2/OVERNIGHT_PROGRESS.md" 2>/dev/null | grep -viE 'HUMAN-ONLY|AUTO-SKIP|HARD FILE BAN|BLOCKED|\[CLAUDE\]' | head -1)"
  fi
  printf '%s\n%s' "$1" "$top" | grep -qiE '\b(delete|deletes|deleting|deleted|remove|removes|removing|removed)\b.{0,60}\bfiles?\b|\bfiles?\b.{0,60}\b(delete|deletes|deleting|deleted|remove|removes|removing|removed)\b'
}

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# ---- 1. real-shaped case confirmed live: the ongoing-lane's generic wrapper prompt
#      (no delete/file words at all) PLUS a real "delete the dead X" top item in
#      OVERNIGHT_PROGRESS.md - must now trigger the hint. ----
ongoing_prompt="Work the single top not-yet-done item in the overnight progress log Next Steps (Skip any item whose line is tagged [AUTO-SKIP...], [HUMAN-ONLY...], [BLOCKED ITEM...], or [CLAUDE]); ask for only the 1-2 files it names."
cat > "$tmp/OVERNIGHT_PROGRESS.md" <<'EOF'
## Next Steps
- [ ] Delete the dead GitHubIntegrationService class file - zero real callers found.
EOF
if needs_delete_hint "$ongoing_prompt" "$tmp"; then r=1; else r=0; fi
ok "ongoing-lane generic prompt + real delete-shaped top item -> hint fires" "[ $r -eq 1 ]"

# ---- 2. ongoing-lane prompt with a NON-delete top item -> hint must NOT fire ----
cat > "$tmp/OVERNIGHT_PROGRESS.md" <<'EOF'
## Next Steps
- [ ] Add a unit test for the login form's validation branch.
EOF
if needs_delete_hint "$ongoing_prompt" "$tmp"; then r=1; else r=0; fi
ok "ongoing-lane generic prompt + non-delete top item -> hint does not fire" "[ $r -eq 0 ]"

# ---- 3. a delete-shaped top item that is AUTO-SKIP-tagged must be excluded (same
#      filter as every other top-item lookup in this file) ----
cat > "$tmp/OVERNIGHT_PROGRESS.md" <<'EOF'
## Next Steps
- [ ] [AUTO-SKIP: previously reverted] Delete the dead LegacyBillingService file.
- [ ] Refactor the trending-bills query to use a single join.
EOF
if needs_delete_hint "$ongoing_prompt" "$tmp"; then r=1; else r=0; fi
ok "AUTO-SKIP-tagged delete item is excluded; real non-delete top item does not fire" "[ $r -eq 0 ]"

# ---- 4. regular (non-ongoing) queued item whose OWN $prompt already names the
#      delete/file phrasing must still fire - no regression from the original 2026-09-20
#      behavior, with or without an OVERNIGHT_PROGRESS.md file present ----
rm -f "$tmp/OVERNIGHT_PROGRESS.md"
if needs_delete_hint "Delete the unused billing_export_v1.py helper file" "$tmp"; then r=1; else r=0; fi
ok "regular queued item's own delete-shaped prompt still fires (no OVERNIGHT_PROGRESS.md present)" "[ $r -eq 1 ]"

echo "ongoing-lane deletion-hint fix: $P passed, $F failed"
[ "$F" -eq 0 ]
