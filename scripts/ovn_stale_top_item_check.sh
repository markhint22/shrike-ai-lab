#!/usr/bin/env bash
# ovn_stale_top_item_check.sh — shadow-mode check for a doable top item that the
# model keeps ignoring in favor of other work (2026-09-23).
#
# Root cause this closes: every cycle's prompt tells the model to "pick the single
# top not-yet-done item", and the context-budget logic guarantees that item stays
# visible — but nothing verifies the model actually complies. ovn_item_guard.sh's
# own fail/no-op streak counters are structurally blind to this exact failure mode:
# they only accumulate on attempts that WERE against the top item, so an item that
# is simply never picked leaves its counters empty forever, no matter how long it
# sits there. Found live: gitlark's #1 doable item (a trivial one-file delete, well
# within context budget) sat untouched 27.6h while ~500k+ tokens/cycle went to
# unrelated work; xlite's #1 item (a never-created test file) sat 27.7h with zero
# git history at all. Neither had tripped any existing alert.
#
# Shadow-mode, alert-only — never edits a backlog file, never tags/skips an item,
# never blocks a cycle. Unlike the sibling shadow checks, this one RE-alerts every
# STALE_HOURS the item remains stuck (not just once) — an item silently burning
# fleet cycles for days is worse the longer it goes unnoticed, so going quiet after
# one alert would undersell the ongoing cost.
set -uo pipefail
cd "$HOME/overnight-queue" || exit 1
export PATH=/usr/local/bin:/usr/bin:/bin:${PATH:-}
LOG="logs/ovn_stale_top_item_check.log"
say(){ echo "$(date '+%F %T') $*" >> "$LOG"; }
STATE_DIR="state"; mkdir -p "$STATE_DIR" 2>/dev/null
NTFY_TOPIC_RESOLVED="${NTFY_TOPIC:-$(cat "$STATE_DIR/ntfy_topic" 2>/dev/null)}"
alert(){ [ -n "$NTFY_TOPIC_RESOLVED" ] && curl -fsS --max-time 8 -H "Title: $1" -H "Tags: $2" -d "$3" "https://ntfy.sh/$NTFY_TOPIC_RESOLVED" >/dev/null 2>&1; true; }
STALE_HOURS="${OVN_STALE_TOP_ITEM_HOURS:-12}"

OUT="$(python3 scripts/ovn_stale_top_item_check.py "$PWD" "$STALE_HOURS" 2>>"$LOG")"

if [ -z "$OUT" ]; then
  say "clean run — no stale top items found"
  exit 0
fi

REPORT=""
FOUND=0
while IFS=$'\t' read -r repo age lineno text; do
  [ -z "$repo" ] && continue
  # Re-alert every STALE_HOURS of continued staleness, not once-ever — key the
  # marker on (repo, item line) so a DIFFERENT item becoming stale next always
  # alerts fresh, but re-check the age gap for the SAME item.
  marker="$STATE_DIR/stale_top_item_alerted_${repo}"
  key="${lineno}:${text:0:60}"
  prev="$(cat "$marker" 2>/dev/null || true)"
  prev_key="${prev%%|*}"
  prev_age="${prev##*|}"
  should_alert=1
  if [ "$prev_key" = "$key" ] && [ -n "$prev_age" ]; then
    # only re-alert once another full STALE_HOURS has passed since the last alert
    delta="$(awk -v a="$age" -v p="$prev_age" 'BEGIN{print (a-p)}')"
    if awk -v d="$delta" -v s="$STALE_HOURS" 'BEGIN{exit !(d < s)}'; then
      should_alert=0
    fi
  fi
  if [ "$should_alert" = "1" ]; then
    FOUND=$((FOUND+1))
    msg="$repo: top item stale ${age}h (line $lineno) — ${text}"
    say "SUSPECT: $msg"
    REPORT="${REPORT}${repo}: stale ${age}h — ${text:0:100}
"
    printf '%s|%s' "$key" "$age" > "$marker"
  fi
done <<< "$OUT"

if [ "$FOUND" -gt 0 ]; then
  say "=== $FOUND stale top item(s) newly alerted this run ==="
  alert "Stale top item: $FOUND repo(s) ignoring their #1 doable item" "warning" "$(printf '%s' "$REPORT" | head -c 800)"
else
  say "stale items found but all within their re-alert cooldown — no new alert"
fi
