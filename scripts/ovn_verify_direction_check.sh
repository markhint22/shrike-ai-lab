#!/usr/bin/env bash
# ovn_verify_direction_check.sh — shadow-mode check for VERIFY commands that can never fail, or
# whose direction contradicts a delete/remove item's own intent (2026-09-22).
#
# Root cause this closes: queue_refill.py's already_satisfied() credits an item as done purely by
# the exit code of its own VERIFY: command. A VERIFY shaped like `grep -q X && echo OK || echo NO`
# always exits 0 (the final executed command is always an echo/printf/true fallback), so it
# "verifies" as satisfied regardless of the real repo state — found live today in shrike-monitor (1
# instance) and gitlark (7 instances, all on delete/remove items whose VERIFY checked for the
# thing's PRESENCE instead of its absence). Shadow-mode only: this never blocks a credit or a push,
# it only logs/alerts so a human/Claude can review and correct the item's VERIFY text.
#
# Two independent checks:
#   1. always-true shape (HIGH confidence, purely mechanical - any `|| echo`/`|| printf`/`|| true`
#      fallback destroys the exit-code signal no matter what precedes it).
#   2. delete/remove direction heuristic (LOWER confidence - only flags a RAW shell grep/test/ls
#      referencing the target without visible negation; deliberately skips any VERIFY that
#      delegates to a real test runner (pytest/godot/cargo/npm test/vitest), since correctness
#      there lives inside the test file's own assertions, not the VERIFY line itself - the first
#      version of this check flagged those as false positives).
set -uo pipefail
cd "$HOME/overnight-queue" || exit 1
export PATH=/usr/local/bin:/usr/bin:/bin:${PATH:-}
LOG="logs/ovn_verify_direction_check.log"
say(){ echo "$(date '+%F %T') $*" >> "$LOG"; }
STATE_DIR="state"; mkdir -p "$STATE_DIR" 2>/dev/null
NTFY_TOPIC_RESOLVED="${NTFY_TOPIC:-$(cat "$STATE_DIR/ntfy_topic" 2>/dev/null)}"
alert(){ [ -n "$NTFY_TOPIC_RESOLVED" ] && curl -fsS --max-time 8 -H "Title: $1" -H "Tags: $2" -d "$3" "https://ntfy.sh/$NTFY_TOPIC_RESOLVED" >/dev/null 2>&1; true; }

REPOS="${1:-billwatch gitlark iptv_apps test-automation-agent xlite shrike-notify shrike-monitor}"
ALWAYS_TRUE=0
DIRECTION_SUSPECT=0
REPORT=""

for r in $REPOS; do
  for f in "backlog/$r.md" "repos/$r/OVERNIGHT_PROGRESS.md"; do
    [ -f "$f" ] || continue
    while IFS= read -r line; do
      case "$line" in *VERIFY:*) ;; *) continue ;; esac

      # Bug class 1: a `CMD && echo A || echo B` (or `|| printf`/`|| true`) shape whose final
      # executed branch always succeeds, making the whole line's exit code always 0.
      if echo "$line" | grep -qE '\|\|[[:space:]]*(echo|printf|true)\b'; then
        ALWAYS_TRUE=$((ALWAYS_TRUE+1))
        msg="$f: always-true VERIFY shape: $(echo "$line" | cut -c1-160)"
        say "SUSPECT(always-true): $msg"
        REPORT="${REPORT}[always-true] ${msg}
"
      fi

      # Bug class 2 (narrow, raw-shell-only heuristic): item text signals delete/remove/orphan
      # intent, its VERIFY is a bare shell grep/test/ls/find (not delegated to a real test runner),
      # and that bare check has no visible negation - the classic "checks presence when it should
      # check absence" direction bug. Skipped entirely when VERIFY hands off to pytest/godot/cargo/
      # npm-or-yarn-test/vitest, since correctness there is the test file's own job, invisible here.
      if echo "$line" | grep -qiE '\b(delete|remove|orphan(ed)?|dead code)\b' \
         && ! echo "$line" | grep -qiE 'VERIFY:.*(pytest|godot|cargo test|npm test|yarn test|vitest|go test)'; then
        verify_part="$(echo "$line" | grep -oE 'VERIFY:.*$')"
        if echo "$verify_part" | grep -qE '\b(grep|test|ls|find)\b' \
           && ! echo "$verify_part" | grep -qE '(! |test !|-z |grep -qv|grep -vq|! grep|! \[|!\[|! test|! ls|! find)'; then
          DIRECTION_SUSPECT=$((DIRECTION_SUSPECT+1))
          msg="$f: delete/remove item, raw shell VERIFY has no visible negation: $(echo "$line" | cut -c1-160)"
          say "REVIEW(direction): $msg"
          REPORT="${REPORT}[review] ${msg}
"
        fi
      fi
    done < "$f"
  done
done

if [ "$ALWAYS_TRUE" -gt 0 ] || [ "$DIRECTION_SUSPECT" -gt 0 ]; then
  say "=== $ALWAYS_TRUE always-true + $DIRECTION_SUSPECT direction-review VERIFY line(s) this run ==="
  alert "VERIFY-direction check: $ALWAYS_TRUE always-true, $DIRECTION_SUSPECT to review" "warning" "$(printf '%s' "$REPORT" | head -c 800)"
else
  say "clean run — no suspect VERIFY lines found"
fi
