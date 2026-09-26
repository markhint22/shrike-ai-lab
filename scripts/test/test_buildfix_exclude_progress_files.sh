#!/usr/bin/env bash
# Regression test for run_overnight.sh's BUILD-GATE / Tier-2 fix-up file-list exclusion
# (2026-09-26). Both fix-up paths used to pass EVERY file touched by the broken commit as
# an editable `--file` arg to aider, with no exclusion. Since the scout's own commit
# always checks off the item in OVERNIGHT_PROGRESS.md as part of the SAME commit that can
# break the build, that append-only, 300KB+ file got pulled in unbounded (no read-only
# tail-cap the way the main scout/implement flow already protects it) - confirmed live on
# iptv_apps: "Added OVERNIGHT_PROGRESS.md to the chat" immediately followed by
# litellm.ContextWindowExceededError (93152 > 65536 tokens), 24 times in one overnight
# run, meaning the fix-up never even got a chance to see the real error before failing.
set -uo pipefail
RO="${OVN_RUN_OVERNIGHT:-$HOME/overnight-queue/run_overnight.sh}"
[ -f "$RO" ] || { echo "  SKIP: $RO not found on this host"; echo "buildfix exclude-progress-files: 0 passed, 0 failed"; exit 0; }

P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

ok "BUILD-GATE fix-up's touched-file list excludes OVERNIGHT_PROGRESS.md/OVERNIGHT_DONE.md" \
   "grep -A1 '_buildfix_touched=' '$RO' | grep -q 'OVERNIGHT_PROGRESS' && grep -A1 '_buildfix_touched=' '$RO' | grep -q 'OVERNIGHT_DONE'"
ok "Tier-2 fix-up's touched-file list excludes OVERNIGHT_PROGRESS.md/OVERNIGHT_DONE.md" \
   "grep -A1 '_fixup_touched=' '$RO' | grep -q 'OVERNIGHT_PROGRESS' && grep -A1 '_fixup_touched=' '$RO' | grep -q 'OVERNIGHT_DONE'"

# Mirror the deployed filter pipeline exactly (both fix-up paths now use the identical
# tail: `| grep -v '^$' | grep -vE '^(OVERNIGHT_PROGRESS|OVERNIGHT_DONE)\.md$'`) against a
# synthetic file list, so a future edit that subtly breaks the regex (e.g. drops the
# anchors and starts excluding real files with those words in a path) gets caught here
# instead of only in production.
filtered(){
  printf '%s\n' \
    "OVERNIGHT_PROGRESS.md" \
    "OVERNIGHT_DONE.md" \
    "" \
    "app/main.py" \
    "app/routers/vod.py" \
    "docs/OVERNIGHT_PROGRESS_NOTES.md" \
    | grep -v '^$' | grep -vE '^(OVERNIGHT_PROGRESS|OVERNIGHT_DONE)\.md$'
}
out="$(filtered)"
ok "OVERNIGHT_PROGRESS.md is excluded" "! printf '%s' \"\$out\" | grep -qx 'OVERNIGHT_PROGRESS.md'"
ok "OVERNIGHT_DONE.md is excluded" "! printf '%s' \"\$out\" | grep -qx 'OVERNIGHT_DONE.md'"
ok "a real touched source file (app/main.py) survives the filter" "printf '%s' \"\$out\" | grep -qx 'app/main.py'"
ok "a real touched source file (app/routers/vod.py) survives the filter" "printf '%s' \"\$out\" | grep -qx 'app/routers/vod.py'"
ok "a differently-named file that merely CONTAINS the excluded name is NOT wrongly excluded (anchored match)" \
   "printf '%s' \"\$out\" | grep -qx 'docs/OVERNIGHT_PROGRESS_NOTES.md'"

echo "buildfix exclude-progress-files: $P passed, $F failed"
[ "$F" -eq 0 ]
