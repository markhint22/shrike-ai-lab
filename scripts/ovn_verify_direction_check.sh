#!/usr/bin/env bash
# ovn_verify_direction_check.sh — shadow-mode check for VERIFY commands that can never fail, or
# whose direction contradicts a delete/remove item's own intent (2026-09-22, revised 2026-09-23).
#
# Root cause this closes: queue_refill.py's already_satisfied() credits an item as done purely by
# the exit code of its own VERIFY: command. A VERIFY shaped like `grep -q X && echo OK || echo NO`
# always exits 0 (the final executed branch is always the echo/printf/true fallback), so it
# "verifies" as satisfied regardless of the real repo state — found live in shrike-monitor and
# gitlark, 2026-09-22.
#
# 2026-09-23 REVISION: the original version scanned EVERY line regardless of checkbox state, so it
# re-reported the same historical, already-[x]-checked matches every single hourly run forever -
# confirmed live: 71/71 "always-true" hits and 113/122 "direction-review" hits were on lines
# already checked off, giving ZERO new actionable signal each cycle (a user complaint: "I don't
# understand these ntfy messages... please clarify"). Fixed to only ever look at still-OPEN
# (`- [ ] `) lines - a checked-off line is history, not a live risk, and doesn't need re-alerting.
# Also now tracks which open items have already been reported once (state/verify_direction_seen.txt,
# keyed by a hash of the line) so the alert only fires on genuinely NEW findings, not the same
# handful of open items every hour until someone acts on them.
#
# Two independent checks:
#   1. always-true shape (HIGH confidence, purely mechanical - any `|| echo`/`|| printf`/`|| true`
#      fallback destroys the exit-code signal no matter what precedes it). If this is still open,
#      it means the item COULD get falsely auto-credited as done the next time the fleet picks it
#      up, even if it never actually landed real work.
#   2. delete/remove direction heuristic (LOWER confidence - only flags a RAW shell grep/test/ls
#      referencing the target without visible negation; deliberately skips any VERIFY that
#      delegates to a real test runner - pytest/godot/cargo/npm/vitest - since correctness there
#      lives in the test file, invisible to a static line check). If open, it MIGHT be checking the
#      wrong direction (e.g. checking a deleted thing still exists instead of confirming it's
#      gone) - worth a human/Claude glance, not a certain bug.
set -uo pipefail
cd "$HOME/overnight-queue" || exit 1
export PATH=/usr/local/bin:/usr/bin:/bin:${PATH:-}
LOG="logs/ovn_verify_direction_check.log"
say(){ echo "$(date '+%F %T') $*" >> "$LOG"; }
STATE_DIR="state"; mkdir -p "$STATE_DIR" 2>/dev/null
SEEN_FILE="$STATE_DIR/verify_direction_seen.txt"
touch "$SEEN_FILE"
NTFY_TOPIC_RESOLVED="${NTFY_TOPIC:-$(cat "$STATE_DIR/ntfy_topic" 2>/dev/null)}"
alert(){ [ -n "$NTFY_TOPIC_RESOLVED" ] && curl -fsS --max-time 8 -H "Title: $1" -H "Tags: $2" -d "$3" "https://ntfy.sh/$NTFY_TOPIC_RESOLVED" >/dev/null 2>&1; true; }

REPOS="${1:-billwatch gitlark iptv_apps test-automation-agent xlite shrike-notify shrike-monitor}"
NEW_ALWAYS_TRUE=0
NEW_DIRECTION=0
REPORT=""

for r in $REPOS; do
  for f in "backlog/$r.md" "repos/$r/OVERNIGHT_PROGRESS.md"; do
    [ -f "$f" ] || continue
    while IFS= read -r line; do
      # Only still-OPEN, still-PICKABLE items are a live risk - a checked-off line already
      # happened, and an AUTO-SKIP/[CLAUDE]/HUMAN-ONLY/retired-tagged line is parked and won't be
      # auto-picked again either, so neither needs re-alerting (matches the same exclusion the rest
      # of the pipeline already uses for "doable" counting).
      case "$line" in "- [ ]"*) ;; *) continue ;; esac
      case "$line" in *VERIFY:*) ;; *) continue ;; esac
      echo "$line" | grep -qiE 'HUMAN-ONLY|AUTO-SKIP|BLOCKED ITEM|retired-|\[CLAUDE\]' && continue

      line_hash="$(printf '%s' "$line" | md5 2>/dev/null || printf '%s' "$line" | md5sum | cut -d' ' -f1)"

      # Check 1: a `CMD && echo A || echo B` (or `|| printf`/`|| true`) shape whose final executed
      # branch always succeeds, making the whole line's exit code always 0.
      if echo "$line" | grep -qE '\|\|[[:space:]]*(echo|printf|true)\b'; then
        if ! grep -qF "$line_hash" "$SEEN_FILE"; then
          echo "$line_hash" >> "$SEEN_FILE"
          NEW_ALWAYS_TRUE=$((NEW_ALWAYS_TRUE+1))
          msg="$f: $(echo "$line" | cut -c1-160)"
          say "NEW always-true VERIFY (would false-credit if picked up): $msg"
          REPORT="${REPORT}[always-true] ${msg}
"
        fi
      fi

      # Check 2 (narrow, raw-shell-only heuristic): item text signals delete/remove/orphan intent,
      # its VERIFY is a bare shell grep/test/ls/find (not delegated to a real test runner), and that
      # bare check has no visible negation - the classic "checks presence when it should check
      # absence" direction bug. Skipped entirely when VERIFY hands off to pytest/godot/cargo/npm/
      # vitest, since correctness there is the test file's own job, invisible here.
      if echo "$line" | grep -qiE '\b(delete|remove|orphan(ed)?|dead code)\b' \
         && ! echo "$line" | grep -qiE 'VERIFY:.*(pytest|godot|cargo test|npm test|yarn test|vitest|go test)'; then
        verify_part="$(echo "$line" | grep -oE 'VERIFY:.*$')"
        if echo "$verify_part" | grep -qE '\b(grep|test|ls|find)\b' \
           && ! echo "$verify_part" | grep -qE '(! |test !|-z |grep -qv|grep -vq|! grep|! \[|!\[|! test|! ls|! find)'; then
          if ! grep -qF "d:$line_hash" "$SEEN_FILE"; then
            echo "d:$line_hash" >> "$SEEN_FILE"
            NEW_DIRECTION=$((NEW_DIRECTION+1))
            msg="$f: $(echo "$line" | cut -c1-160)"
            say "NEW direction-review (worth a glance, not certain): $msg"
            REPORT="${REPORT}[review] ${msg}
"
          fi
        fi
      fi
    done < "$f"
  done
done

if [ "$NEW_ALWAYS_TRUE" -gt 0 ] || [ "$NEW_DIRECTION" -gt 0 ]; then
  say "=== $NEW_ALWAYS_TRUE new always-true + $NEW_DIRECTION new direction-review item(s) this run (only counting still-open items, not historical/checked ones) ==="
  alert "Fleet: $NEW_ALWAYS_TRUE item(s) at risk of a false credit, $NEW_DIRECTION worth a glance" \
    "warning" \
"These are NEW open backlog items found since the last check (already-checked/historical items are never re-reported):

- always-true ($NEW_ALWAYS_TRUE): this item's VERIFY command can never fail, so if the fleet picks it up it may get marked done without any real work happening. Worth fixing the VERIFY text before it's attempted.
- direction-review ($NEW_DIRECTION): this is a delete/remove item whose VERIFY checks for the thing's presence, not its absence - possibly backwards, but this is a guess, not certain. Worth a quick look.

$(printf '%s' "$REPORT" | head -c 600)"
else
  say "clean run — no NEW open at-risk items found (checked/historical matches are not re-reported)"
fi
