#!/usr/bin/env bash
# Regression test for run_overnight.sh's implement-time ALREADY-DONE fix (2026-09-28).
#
# The scout's strict VERDICT: line already gets ALREADY-DONE short-circuited to
# no-op(ALREADY-DONE) (benign, per ovn_outcome_buckets.py's canonical classifier). But
# when the scout says PROCEED and the IMPLEMENT pass then independently concludes
# mid-attempt that the target is already correct and makes no change, that fell through
# to a bare "no-op" - bucketed BAD (a real flail) even though it's the same benign
# situation discovered one step later. Confirmed live on iptv_apps.
#
# Extracts the real grep pattern out of run_overnight.sh (not a reimplementation) so this
# can't silently drift from what's deployed.
set -uo pipefail
RO="${OVN_RUN_OVERNIGHT:-$HOME/overnight-queue/run_overnight.sh}"
[ -f "$RO" ] || { echo "  SKIP: $RO not found on this host"; exit 0; }

PATTERN="$(grep -oE 'tail -c 4000 "\$task_log" 2>/dev/null \| grep -qiE "[^"]+"' "$RO" | head -1 | sed -E 's/^.*grep -qiE "//; s/"$//')"
[ -n "$PATTERN" ] || { echo "  FAIL: could not extract the implement-time already-done pattern from $RO"; exit 1; }

P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# classify <log-text> -> "already-done" or "plain-noop", mirroring the deployed
# `tail -c 4000 "$task_log" | grep -qiE "$PATTERN"` decision exactly.
classify(){
  local f="$tmp/log.txt"
  printf '%s' "$1" > "$f"
  if tail -c 4000 "$f" | grep -qiE "$PATTERN"; then
    echo "already-done"
  else
    echo "plain-noop"
  fi
}

# --- A: a genuine implement-time already-done conclusion -> benign, not a flail ---
ok "already be satisfied -> already-done" \
   "[ \"\$(classify 'Looking at this closely, the function already be satisfied by the existing check.')\" = already-done ]"
ok "already fully implemented -> already-done" \
   "[ \"\$(classify 'dashboard_metrics is already fully implemented in the code provided, no edit needed.')\" = already-done ]"
ok "No further changes are needed -> already-done" \
   "[ \"\$(classify 'The current content is correct from my previous edit. No further changes are needed.')\" = already-done ]"
ok "does not need any changes -> already-done" \
   "[ \"\$(classify 'Looking at this closely, the file does not need any changes.')\" = already-done ]"

# --- B: a genuine flail (no already-done language at all) -> stays plain no-op (BAD) ---
ok "generic non-committal reply -> plain-noop (real flail, stays BAD)" \
   "[ \"\$(classify 'I am not sure how to proceed with this task, let me think about it more.')\" = plain-noop ]"
ok "empty/garbage log -> plain-noop (conservative default)" \
   "[ \"\$(classify '')\" = plain-noop ]"

# --- C: the phrase appears ONLY early in the log (e.g. quoted in a file dump), far
#     outside the tail -c 4000 window -> must NOT be misclassified as already-done ---
early_phrase="This file already handles the edge case correctly, see the comment above."
padding="$(python3 -c "print('x' * 5000)")"
far_log="${early_phrase}
${padding}
I could not figure out how to make this change work, giving up for now."
ok "already-done phrase far outside the tail window does not leak into the classification" \
   "[ \"\$(classify \"\$far_log\")\" = plain-noop ]"

echo "implement-time already-done classification: $P passed, $F failed"
[ "$F" -eq 0 ]
