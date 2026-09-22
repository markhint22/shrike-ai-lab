#!/usr/bin/env bash
# ovn_fleet_health.sh — Phase 4 of the pipeline hardening plan: daily fleet-health heartbeat
# (2026-09-22, see ~/.claude/plans/modular-zooming-lagoon.md).
#
# Problem this closes: the 2026-09-21 roadmap-starvation incident (all 7 active repos' roadmaps
# ran dry simultaneously, fleet crash-looped 5+ hours doing zero real work) had the same root shape
# as the earlier lock-contention bug this plan already fixed - a failure mode with ZERO alerting
# until a human went looking. ovn_planner.sh logs "backlog low, no [ready] feature" every cycle,
# but that's a per-repo line in a log file nobody tails, not a proactive, aggregate signal. This
# script asks explicitly, once a day, per active repo: real landings (7d, from the authoritative
# outcomes.jsonl), backlog/roadmap depth, and days-of-runway at the current burn rate (REUSING
# ovn_stats.py's existing runway() rather than reimplementing its doable-count + git-burn-rate
# math, per the plan's own instruction) - then alerts BEFORE runway hits zero, not only after.
set -uo pipefail
cd "$HOME/overnight-queue" || exit 1
export PATH=/usr/local/bin:/usr/bin:/bin:${PATH:-}
LOG="logs/ovn_fleet_health.log"
say(){ echo "$(date '+%F %T') $*" >> "$LOG"; }
STATE_DIR="state"; mkdir -p "$STATE_DIR" 2>/dev/null
NTFY_TOPIC_RESOLVED="${NTFY_TOPIC:-$(cat "$STATE_DIR/ntfy_topic" 2>/dev/null)}"
alert(){ [ -n "$NTFY_TOPIC_RESOLVED" ] && curl -fsS --max-time 8 -H "Title: $1" -H "Tags: $2" -d "$3" "https://ntfy.sh/$NTFY_TOPIC_RESOLVED" >/dev/null 2>&1; true; }

RUNWAY_ALERT_DAYS="${OVN_RUNWAY_ALERT_DAYS:-2}"
ACTIVE="$(jq -r 'map(select(.enabled != false)) | .[].repo' tasks.json 2>/dev/null | xargs -n1 basename 2>/dev/null | sort -u | tr '\n' ' ')"

# Real landings in the last 7d per repo, from the authoritative outcomes.jsonl (not a re-derivation
# of run_overnight.sh's own status strings - just a count of anything whose status names a push).
LANDED_7D_OUT="$(python3 -c "
import json, time, calendar
cutoff = time.time() - 7 * 86400
counts = {}

def parse_ts(v):
    # outcomes.jsonl's real format is an ISO-8601 UTC string ('2026-09-22T13:42:08Z'),
    # not epoch seconds - confirmed by reading a live record. calendar.timegm (not
    # time.mktime) treats the parsed struct as UTC, matching the trailing Z.
    if isinstance(v, (int, float)):
        return float(v)
    try:
        return calendar.timegm(time.strptime(str(v), '%Y-%m-%dT%H:%M:%SZ'))
    except Exception:
        return None

try:
    with open('state/outcomes.jsonl') as f:
        for line in f:
            try:
                r = json.loads(line)
            except Exception:
                continue
            ts = parse_ts(r.get('ts') or r.get('timestamp'))
            if ts is None:
                continue
            if ts > 1e12:
                ts = ts / 1000.0
            cls = str(r.get('class', '')).lower()
            repo = r.get('repo', '?')
            if cls == 'landed' and ts >= cutoff:
                counts[repo] = counts.get(repo, 0) + 1
except FileNotFoundError:
    pass
for repo, cnt in counts.items():
    print(repo, cnt)
" 2>/dev/null)"
declare -A LANDED_7D
while read -r repo cnt; do
  [ -n "$repo" ] && LANDED_7D["$repo"]="$cnt"
done <<< "$LANDED_7D_OUT"

# Runway: reuse ovn_stats.py's existing runway() function directly (import, not reimplement).
# Import-time prints from ovn_stats.py's own module-level code are suppressed so they don't
# corrupt the clean tab-separated output this script parses below.
RUNWAY_OUT="$(OVN_REPOS_DIR="$PWD/repos" OVN_ACTIVE_REPOS="$ACTIVE" python3 -c "
import sys, os
sys.argv = ['ovn_stats.py']
sys.path.insert(0, 'scripts')
_real_stdout = sys.stdout
sys.stdout = open(os.devnull, 'w')
import ovn_stats
sys.stdout = _real_stdout
for repo, doable, days, burn in ovn_stats.runway():
    print('%s\t%s\t%s\t%s' % (repo, doable, days, burn))
" 2>/dev/null)"

REPORT=""
LOW_RUNWAY=0
HEALTHY=0
while IFS=$'\t' read -r repo doable days burn; do
  [ -z "$repo" ] && continue
  landed7d="${LANDED_7D[$repo]:-0}"
  say "$repo: doable=$doable runway=$days burn24h=$burn landed_7d=$landed7d"
  case "$days" in
    0d|'stalled?'|'<1d')
      LOW_RUNWAY=$((LOW_RUNWAY+1))
      REPORT="${REPORT}${repo}: ${days} runway (doable=${doable}, burn/24h=${burn}, landed/7d=${landed7d})
"
      ;;
    *)
      num="$(echo "$days" | tr -dc '0-9')"
      if [ -n "$num" ] && [ "$num" -le "$RUNWAY_ALERT_DAYS" ]; then
        LOW_RUNWAY=$((LOW_RUNWAY+1))
        REPORT="${REPORT}${repo}: ${days} runway (doable=${doable}, burn/24h=${burn}, landed/7d=${landed7d})
"
      else
        HEALTHY=$((HEALTHY+1))
      fi
      ;;
  esac
done <<< "$RUNWAY_OUT"

if [ "$LOW_RUNWAY" -gt 0 ]; then
  say "=== $LOW_RUNWAY repo(s) at or under ${RUNWAY_ALERT_DAYS}d runway (of $((LOW_RUNWAY+HEALTHY)) active) ==="
  alert "Fleet health: $LOW_RUNWAY repo(s) low on runway" "warning" "$(printf '%s' "$REPORT" | head -c 800)"
else
  say "clean run — all $HEALTHY active repo(s) have runway > ${RUNWAY_ALERT_DAYS}d"
fi
