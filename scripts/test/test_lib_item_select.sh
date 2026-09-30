#!/usr/bin/env bash
# Regression test for scripts/lib_item_select.sh's ovn_resolve_top_item() (2026-09-28).
#
# Root cause this guards against: every "find the real top item" selector in this pipeline
# (ovn_item_guard.sh's cap-tracking, run_overnight.sh's record_outcome() item_hash) used to
# independently re-grep OVERNIGHT_PROGRESS.md's literal TOPMOST unchecked line as a stand-in
# for "the item this cycle actually worked on". Confirmed live on test-automation-agent: an
# item failed 8 times across 2 hours while state/item_fails/ongoing-<repo>.count stayed at 1
# the whole time, because the guard kept hashing whatever unrelated item happened to be
# topmost that cycle instead of the one the model actually retried — completely decoupling
# the consecutive-fail auto-skip and the grounded-failure-memory safety net from reality.
#
# ovn_resolve_top_item() fixes this by preferring the item whose file the scout's own FILES:
# answer (in the cycle's task_log) names, falling back to the plain top-of-file line when
# there's no usable scout signal — verified here directly, not by re-implementing the logic.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
LIB="$HERE/../lib_item_select.sh"; [ -f "$LIB" ] || LIB="$HERE/lib_item_select.sh"
[ -f "$LIB" ] || { echo "  SKIP: lib_item_select.sh not found"; exit 0; }
# shellcheck source=/dev/null
source "$LIB"

P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# --- A: no task_log at all -> old top-of-file-only behavior (first doable, non-tagged line) ---
r="$tmp/repoA"; mkdir -p "$r"
printf -- '%s\n' \
  '- [ ] [AUTO-SKIP after 3 fails] `parked.py` — a parked item, must be skipped' \
  '- [ ] [T2] `real_top.py` — the real top item' \
  '- [ ] [T2] `second.py` — a second item' \
  > "$r/OVERNIGHT_PROGRESS.md"
line="$(ovn_resolve_top_item "$r")"
ok "no task_log: falls back to the first non-tagged doable line" \
   "printf '%s' \"\$line\" | grep -q 'real_top.py'"
ok "no task_log: AUTO-SKIP line is correctly excluded" \
   "! printf '%s' \"\$line\" | grep -q parked.py"

# --- B: a scout task_log names a file that is NOT the literal top line -> that line wins ---
r="$tmp/repoB"; mkdir -p "$r"
printf -- '%s\n' \
  '- [ ] [T2] `unrelated.py` — an item the scout was never asked about this cycle' \
  '- [ ] [T2] `actual_target.py` — the item the scout actually said it would work on' \
  > "$r/OVERNIGHT_PROGRESS.md"
tl="$tmp/repoB.log"
cat > "$tl" <<'EOF'
VERDICT: PROCEED
PLAN: fix the bug in actual_target.py
FILES: actual_target.py
EOF
line="$(ovn_resolve_top_item "$r" "$tl")"
ok "scout named a non-top file: that file's line wins, not the literal top line" \
   "printf '%s' \"\$line\" | grep -q actual_target.py"
ok "scout named a non-top file: the literal top line is NOT what's returned" \
   "! printf '%s' \"\$line\" | grep -q 'an item the scout was never asked'"

# --- C: same scenario, repeated 3x — the returned line (and thus its hash) is STABLE across
#     cycles even though the literal top-of-file line never changes and isn't the real target.
#     This is the exact property that was broken: a consecutive-fail counter keyed on this
#     value must see the SAME key every time so it can actually accumulate. ---
h1="$(printf '%s' "$(ovn_resolve_top_item "$r" "$tl")" | md5sum | cut -d' ' -f1)"
h2="$(printf '%s' "$(ovn_resolve_top_item "$r" "$tl")" | md5sum | cut -d' ' -f1)"
h3="$(printf '%s' "$(ovn_resolve_top_item "$r" "$tl")" | md5sum | cut -d' ' -f1)"
ok "repeated resolution of the same real target yields a STABLE hash across calls" \
   "[ '$h1' = '$h2' ] && [ '$h2' = '$h3' ]"

# --- D: the scouted file does not literally appear anywhere in the progress file -> falls
#     back to the plain top-of-file line (old behavior), not an empty/broken result ---
r="$tmp/repoD"; mkdir -p "$r"
printf -- '%s\n' '- [ ] [T2] `roadmap_path.py` — item, scout named a differently-spelled path' \
  > "$r/OVERNIGHT_PROGRESS.md"
tl2="$tmp/repoD.log"
cat > "$tl2" <<'EOF'
VERDICT: PROCEED
PLAN: fix it
FILES: scripts/utils/roadmap_path.py
EOF
line="$(ovn_resolve_top_item "$r" "$tl2")"
ok "scouted path not found verbatim in progress file: falls back to top-of-file line" \
   "printf '%s' \"\$line\" | grep -q roadmap_path.py"

# --- E: a scout VERDICT of BLOCKED/ALREADY-DONE (no FILES: line, no PROCEED/NEEDS-DECISION
#     match) has no usable scout signal -> falls back cleanly, same as no task_log at all ---
r="$tmp/repoE"; mkdir -p "$r"
printf -- '%s\n' '- [ ] [T2] `top_item.py` — the only doable item' > "$r/OVERNIGHT_PROGRESS.md"
tl3="$tmp/repoE.log"
printf 'VERDICT: BLOCKED\nPLAN: a human must provide credentials\n' > "$tl3"
line="$(ovn_resolve_top_item "$r" "$tl3")"
ok "BLOCKED verdict (no FILES:): falls back to top-of-file line" \
   "printf '%s' \"\$line\" | grep -q top_item.py"

# --- F: [CLAUDE]-escalated and HUMAN-ONLY lines are excluded regardless of path ---
r="$tmp/repoF"; mkdir -p "$r"
printf -- '%s\n' \
  '- [ ] [CLAUDE] `escalated.py` — needs a human, do not re-pick' \
  '- [ ] [HUMAN-ONLY BLOCKED ITEM] `blocked.py` — also excluded' \
  '- [ ] [T2] `pickme.py` — the only real doable item' \
  > "$r/OVERNIGHT_PROGRESS.md"
line="$(ovn_resolve_top_item "$r")"
ok "[CLAUDE]/HUMAN-ONLY lines excluded even with no task_log" \
   "printf '%s' \"\$line\" | grep -q pickme.py"

# --- G: no doable items at all -> empty result, not an error ---
r="$tmp/repoG"; mkdir -p "$r"
printf -- '%s\n' '- [ ] [AUTO-SKIP after 3 fails] `only.py` — the only item, parked' \
  > "$r/OVERNIGHT_PROGRESS.md"
line="$(ovn_resolve_top_item "$r")"
ok "nothing doable: returns empty" "[ -z '$line' ]"

echo "lib_item_select (ovn_resolve_top_item): $P passed, $F failed"
[ "$F" -eq 0 ]
