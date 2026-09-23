#!/usr/bin/env bash
# ovn_research_trigger_check.sh — durable, always-on half of the automated research
# trigger (2026-09-23). Runs on the GPU box's own crontab (unlike CronCreate jobs,
# which only fire while a specific Claude Code chat session stays open and idle, and
# auto-expire after 7 days — this needed to be a real box-side cron to be reliable
# with nobody watching).
#
# ovn_planner.sh already logs "<repo>: backlog low (N) but no [ready] roadmap
# feature (needs Claude research?)" whenever a repo is thin on both backlog and
# roadmap - nothing previously watched for this PERSISTING (the exact incident
# behind ovn_backlog_format_check.sh/ovn_verify_direction_check.sh: a repo can sit
# starved for days before a human happens to notice). This does NOT itself spawn a
# research pass — only an actual interactive/API Claude session can research a repo
# and write grounded backlog items; a cron script has no such capability. It
# durably detects + alerts, and writes state/research_trigger_starving.json so a
# session-side poller (this session's own CronCreate job, while it is open) can act
# on it without re-deriving the log parsing.
set -uo pipefail
cd "$HOME/overnight-queue" || exit 1
export PATH=/usr/local/bin:/usr/bin:/bin:${PATH:-}
LOG="logs/ovn_research_trigger_check.log"
say(){ echo "$(date '+%F %T') $*" >> "$LOG"; }
STATE_DIR="state"; mkdir -p "$STATE_DIR" 2>/dev/null
NTFY_TOPIC_RESOLVED="${NTFY_TOPIC:-$(cat "$STATE_DIR/ntfy_topic" 2>/dev/null)}"
alert(){ [ -n "$NTFY_TOPIC_RESOLVED" ] && curl -fsS --max-time 8 -H "Title: $1" -H "Tags: $2" -d "$3" "https://ntfy.sh/$NTFY_TOPIC_RESOLVED" >/dev/null 2>&1; true; }
STARVE_HOURS="${OVN_STARVE_HOURS:-2}"

OUT="$(python3 scripts/ovn_research_trigger_check.py "$STARVE_HOURS" logs/ovn_planner.log 2>>"$LOG")"
[ -n "$OUT" ] && say "$OUT"

# Alert once per starvation STREAK, not once per cron tick — re-derive each starving
# repo's streak_start from the state file the python script just wrote, and only
# fire ntfy for repos whose streak_start is NEW since the last time this alerted.
NEW="$(python3 - "$STATE_DIR" <<'PYEOF'
import json, os, sys
state_dir = sys.argv[1]
try:
    with open(os.path.join(state_dir, "research_trigger_starving.json")) as f:
        data = json.load(f)
except Exception:
    sys.exit(0)
new_alerts = []
for r in data.get("starving", []):
    marker = os.path.join(state_dir, f"research_trigger_alerted_{r['repo']}")
    prev = None
    try:
        with open(marker) as f:
            prev = f.read().strip()
    except FileNotFoundError:
        pass
    cur = str(r["starving_since"])
    if prev != cur:
        new_alerts.append(r)
        with open(marker, "w") as f:
            f.write(cur)
for r in new_alerts:
    print(f"{r['repo']}: starving {r['hours']}h (no ready roadmap feature)")
PYEOF
)"

if [ -n "$NEW" ]; then
  n="$(printf '%s\n' "$NEW" | grep -c .)"
  say "=== $n repo(s) newly confirmed starving — alerting ==="
  alert "Research trigger: $n repo(s) need research" "warning" "$(printf '%s' "$NEW" | head -c 800)"
fi
