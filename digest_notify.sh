#!/usr/bin/env bash
# Every ~3h (cron): roll state/digest_buffer.log up into ONE human-readable ntfy
# message, then clear the buffer. Replaces the old per-cycle push. If nothing ran
# in the window, sends a short "quiet" heartbeat so you still know the box is alive.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="$DIR/state"
BUF="$STATE_DIR/digest_buffer.log"
TOPIC="${NTFY_TOPIC:-$(cat "$STATE_DIR/ntfy_topic" 2>/dev/null)}"
SERVER="${NTFY_SERVER:-https://ntfy.sh}"
DIGEST_HOURS=3
[ -n "$TOPIC" ] || exit 0

send() { curl -fsS --max-time 8 -H "Title: $1" -H "Tags: $2" -d "$3" "$SERVER/$TOPIC" >/dev/null 2>&1 || true; }

# 2026-09-09: an empty buffer only means "nothing since the last digest" — it does NOT imply
# idle-or-paused (that vague "or" read as alarming even when the queue was running fine the
# whole time; confirmed live when two manual digest runs a few minutes apart hit this exact
# branch on the second one purely because the first had just drained the buffer). Check the
# REAL state instead of guessing.
if [ ! -s "$BUF" ]; then
  if [ -f "$STATE_DIR/PAUSED" ]; then
    send "Overnight queue — PAUSED" "pause_button" "$(date '+%a %H:%M') · The queue IS paused (queue.sh resume to continue). Nothing ran since the last digest."
  elif systemctl is-active --quiet overnight-queue 2>/dev/null; then
    send "Overnight queue — quiet" "zzz" "$(date '+%a %H:%M') · Running normally — just nothing new since the last digest. NOT paused."
  else
    send "Overnight queue — NOT RUNNING" "rotating_light" "$(date '+%a %H:%M') · The systemd service is not active and nothing ran since the last digest. Check: systemctl status overnight-queue"
  fi
  exit 0
fi

cycles=0; NP=0; NF=0; NR=0; NN=0; NE=0
pass=""; fail=""; rev=""; err=""
while IFS=$'\t' read -r ts a b c d e P F R E; do
  [ -z "${a:-}" ] && continue
  cycles=$((cycles+1))
  NP=$((NP+a)); NF=$((NF+b)); NR=$((NR+c)); NN=$((NN+d)); NE=$((NE+e))
  pass="$pass,${P#PASS=}"; fail="$fail,${F#FAIL=}"; rev="$rev,${R#REV=}"; err="$err,${E#ERR=}"
done < "$BUF"

uniq_csv() { echo "$1" | tr ',' '\n' | grep -vE '^$' | sort -u | paste -sd', ' -; }
Praw="$(uniq_csv "$pass")"; Fraw="$(uniq_csv "$fail")"; Rraw="$(uniq_csv "$rev")"; Eraw="$(uniq_csv "$err")"
allrepos="$(uniq_csv "$pass,$fail,$rev,$err")"

items=$((NP+NF+NR+NN+NE))
body="Overnight queue · last ~${DIGEST_HOURS}h ($(date '+%a %H:%M'))
$items work items done across $cycles run(s), on: ${allrepos:-–}"
# 2026-09-09 FIX: this used to say "landed on main" - wrong since the staging-flow change (see
# CLAUDE.md "Staging flow restored"). Every landed item here pushes to overnight/feature; it only
# reaches develop via the next hourly branch_hygiene merge, and only reaches main/prod via the
# daily GATED promote. Saying "on main" made it look like production already had the change when
# it was still several steps away - actively misleading, not just imprecise.
[ "$NP" -gt 0 ] && body="$body

✅ $NP landed on the feature branch (tests passed) — reaches develop at the next hourly merge, prod only via the daily gated promote  [$Praw]"
[ "$NF" -gt 0 ] && body="$body

⚠️ $NF had a failing test — still being fixed, held off the feature branch, nothing broke  [$Fraw]"
[ "$NR" -gt 0 ] && body="$body

↩️ $NR auto-reverted (didn't compile) — safety gate, no action  [$Rraw]"
[ "$NE" -gt 0 ] && body="$body

⛔ $NE errored (network/timeout)  [$Eraw]"
[ "$NN" -gt 0 ] && body="$body

➖ $NN no change (item already done, or nothing to do)"
body="$body

Every line above is one work item. Only ✅ reaches the feature branch; ⚠️/↩️/⛔ never do."

# 2026-09-09: tier-sliced pass/no-op/timeout + token spend. outcomes.jsonl has the accurate,
# EXPLICIT tier per item (record_outcome's own [T#] tag parse), so this replaced the old
# ovn_stats.py "Tiers:" line below, which inferred tier from a separate classification tag and
# couldn't show no-op/timeout/token detail. See project memory
# project_27b-higher-tier-and-throughput for why tier-accuracy here matters.
if [ -x "$DIR/scripts/ovn_tier_stats.py" ]; then
  _TIERS="$(python3 "$DIR/scripts/ovn_tier_stats.py" "$DIGEST_HOURS" 2>/dev/null)"
  [ -n "$_TIERS" ] && body="$body

$_TIERS"
fi

# 2026-09-09: a rolling 24h token total alongside the ${DIGEST_HOURS}h tier breakdown above —
# the ${DIGEST_HOURS}h number alone doesn't answer "how much am I spending per day," and this
# digest fires every ${DIGEST_HOURS}h so a plain 24h call here would just repeat the same total
# ~8x/day; --tokens-only keeps it to one line instead of duplicating the whole tier table.
if [ -x "$DIR/scripts/ovn_tier_stats.py" ]; then
  _TOKENS_24H="$(python3 "$DIR/scripts/ovn_tier_stats.py" 24 --tokens-only 2>/dev/null)"
  [ -n "$_TOKENS_24H" ] && body="$body
$_TOKENS_24H"
fi

# classification pass-rate stats (2026-08-31): slice pass-rate by
# language/type/complexity/verifiability so failures are attributed to the RIGHT
# cause (a language like gdscript vs a complexity tier vs unverifiable gating).
if [ -x "$DIR/scripts/ovn_stats.py" ]; then
  _ACTIVE="$(jq -r 'map(select(.enabled != false)) | .[].repo' "$DIR/tasks.json" 2>/dev/null | xargs -n1 basename 2>/dev/null | sort -u | tr "\n" " ")"
  _STATS="$(OVN_REPOS_DIR="$DIR/repos" OVN_ACTIVE_REPOS="$_ACTIVE" python3 "$DIR/scripts/ovn_stats.py" "$DIGEST_HOURS" --ntfy 2>/dev/null)"
  [ -n "$_STATS" ] && body="$body

📈 By language/type (last ${DIGEST_HOURS}h):
$_STATS"
fi

# 2026-09-09: planner + refill activity, so it's visible when the queue is self-sustaining vs
# when a repo genuinely needs a human/Claude to add roadmap work (previously invisible unless you
# tailed logs/ovn_planner.log and logs/queue_refill.log by hand).
if [ -x "$DIR/scripts/ovn_planning_stats.py" ]; then
  _PLANNING="$(python3 "$DIR/scripts/ovn_planning_stats.py" "$DIGEST_HOURS" 2>/dev/null)"
  [ -n "$_PLANNING" ] && body="$body

$_PLANNING"
fi

send "Overnight queue" "robot" "$body"

# clear the buffer (keep one rotation for debugging)
cp "$BUF" "$BUF.last" 2>/dev/null || true
: > "$BUF"
