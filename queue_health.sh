#!/usr/bin/env bash
# Two lightweight guardrails for the fast-moving overnight queue, both ntfy-alerting:
#   1. queue-depth monitor: warn if an ACTIVE repo drops below MIN_DOABLE items
#      (so it never silently goes idle unnoticed -> prompts a refill).
#   2. deploy health check: curl the known production endpoints and warn on non-2xx/3xx
#      (so a bad main-merge deploy is caught in minutes, per the fast merge cadence).
# Runs from the server (no Claude key needed). Alerts via the same ntfy topic as the digest.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="$DIR/state"
TOPIC="${NTFY_TOPIC:-$(cat "$STATE_DIR/ntfy_topic" 2>/dev/null)}"
SERVER="${NTFY_SERVER:-https://ntfy.sh}"
MIN_DOABLE="${MIN_DOABLE:-5}"
alert() { [ -n "$TOPIC" ] && curl -fsS --max-time 8 -H "Title: $1" -H "Tags: $2" -d "$3" "$SERVER/$TOPIC" >/dev/null 2>&1 || true; }

# ---- 1. queue-depth monitor ----
low=""
active="$(jq -r 'map(select(.enabled != false)) | .[].repo // empty' "$DIR/tasks.json" 2>/dev/null | xargs -n1 basename 2>/dev/null | sort -u)"
for r in $active; do
  prog="$DIR/repos/$r/OVERNIGHT_PROGRESS.md"
  [ -f "$prog" ] || continue
  d=$(grep -E '^- \[ \]' "$prog" 2>/dev/null | grep -viE 'HUMAN-ONLY|human/|AUTO-SKIP|BLOCKED ITEM|retired-' | wc -l | tr -d ' ')
  [ "${d:-0}" -lt "$MIN_DOABLE" ] && low="${low}${r}=${d} "
done
if [ -n "$low" ]; then
  # 24h cooldown: this is a no-urgency FYI (refill auto-tops-up), so don't spam it hourly.
  _cd="$STATE_DIR/lowqueue_alert_last"
  _now=$(date +%s); _last=$(cat "$_cd" 2>/dev/null || echo 0)
  if [ $(( _now - _last )) -ge 86400 ]; then
    echo "$_now" > "$_cd"
    alert "Queue running low on a few repos" "battery" "Under ${MIN_DOABLE} doable items: ${low}
No urgency — a Claude refill (shared/scripts/CLAUDE_REFILL_RUNBOOK.md) tops them back up whenever it's convenient. (This FYI is throttled to once/day.)"
  fi
fi

# ---- 1b. hygiene-stall check: feature far ahead of DEVELOP = hygiene not landing ----
# NOTE: measure feature vs DEVELOP, not main. Under the staging flow the fleet lands
# feature->develop continuously (branch_hygiene, hourly) and develop->main is promoted
# only ONCE A DAY (daily_promote). So feature being far ahead of *main* is NORMAL and
# grows every day until the 9am promote — measuring against main made this alert fire
# constantly (false positive). feature far ahead of *develop* is the real "hygiene is
# stalled" signal (gate red or hygiene broken). Promote failures are surfaced separately
# by daily_promote.sh's own ntfy summary, so we don't duplicate a main-lag alert here.
# 2026-09-07 root-cause fix: DON'T alert merely because feature is ahead of develop. The fleet is a
# continuous daemon; overnight/feature runs ahead of an hourly hygiene as a matter of course — that is
# NORMAL, not stalled, and firing on it produced the constant false "hygiene stalled" alerts. A REAL
# stall leaves a review flag: branch_hygiene writes state/branch_hygiene_review_<repo> whenever it TRIED
# and couldn't land (gate red, merge conflict, or push fail). So only alert when that flag is present
# AND the branch is genuinely piling up. No flag = hygiene is landing fine; reconcile keeps feature current.
stalled=""
for r in $active; do
  d="$DIR/repos/$r"
  [ -d "$d/.git" ] || continue
  flag="$STATE_DIR/branch_hygiene_review_${r}"
  [ -f "$flag" ] || continue                       # no gate-failure flag -> not stalled, skip
  git -C "$d" fetch -q origin 2>/dev/null
  ahead=$(git -C "$d" rev-list --count origin/develop..origin/overnight/feature 2>/dev/null || echo 0)
  [ "${ahead:-0}" -ge 25 ] && stalled="${stalled}${r}=+${ahead}(flagged: $(head -c 60 "$flag" 2>/dev/null)) "
done
if [ -n "$stalled" ]; then
  alert "Hygiene stalled — gate red on a feature branch" "warning" "branch_hygiene TRIED to land feature->develop and the GATE FAILED (red tests / conflict / push fail): ${stalled}
This is a real stall (a review flag is set), not normal fleet churn. Check branch_hygiene.log + state/branch_hygiene_review_*."
fi

# ---- 2. deploy health check ----
# name|url|expected-substring-in-body (empty = any 2xx/3xx is fine)
CHECKS=(
  "chickadee-backend|https://chickadeestream-production.up.railway.app/health|"
)
# 2026-09-09 FIX: comment/blank lines in health_endpoints.txt used to be fed straight into
# CHECKS with no filtering - a "# name|url|..." header line's "url" field parsed out as the
# literal string "url", curl'd it, got a bogus non-2xx/3xx result, and reported it as a FALSE
# "deploy health check FAILED" alert every run. Strip comments/blanks before loading.
[ -f "$STATE_DIR/health_endpoints.txt" ] && mapfile -t CHECKS < <(grep -vE '^\s*#|^\s*$' "$STATE_DIR/health_endpoints.txt")
# 2026-09-09 FIX: this used to re-alert EVERY hour for as long as an endpoint stayed down - no
# dedup at all, unlike deploy_watch.sh's proper state-change-only alerting. Populating
# health_endpoints.txt with all 6 production backends earlier today would have made this WORSE
# (6x the repeat-alert volume for any one real outage) if left as-is. Now: alert once when a
# surface FIRST goes bad, stay quiet while it's still down, and send one recovery confirmation
# when it comes back - exactly deploy_watch.sh's pattern, applied here too.
newly_bad=""; still_bad=""; recovered=""
for c in "${CHECKS[@]}"; do
  name="${c%%|*}"; rest="${c#*|}"; url="${rest%%|*}"; want="${rest#*|}"
  [ -n "$url" ] || continue
  marker="$STATE_DIR/qh_bad_${name}"
  code=$(curl -fsS -o /tmp/hc_body -w '%{http_code}' --max-time 12 "$url" 2>/dev/null || echo "000")
  reason=""
  if ! echo "$code" | grep -qE '^(2|3)[0-9][0-9]$'; then
    reason="HTTP ${code}"
  elif [ -n "$want" ] && ! grep -q "$want" /tmp/hc_body 2>/dev/null; then
    reason="missing '${want}'"
  fi
  if [ -n "$reason" ]; then
    if [ -f "$marker" ]; then still_bad="${still_bad}${name} ${reason}; "
    else echo "$reason" > "$marker"; newly_bad="${newly_bad}${name} ${reason}; "; fi
  elif [ -f "$marker" ]; then
    rm -f "$marker"; recovered="${recovered}${name} "
  fi
done
[ -n "$newly_bad" ] && alert "Deploy health check FAILED" "rotating_light" "$newly_bad
New failure(s) — checked after the merge-to-main wave. Will stay quiet on repeat checks while still down; you'll get one more ntfy when it recovers."
[ -n "$recovered" ] && alert "Deploy health check recovered" "white_check_mark" "Back to healthy: ${recovered}"
exit 0
