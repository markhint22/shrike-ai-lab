#!/usr/bin/env bash
# shrike_notify_lib.sh — shared dual-publish helper: sourced by digest_notify.sh,
# deploy_watch.sh, and daily_promote.sh so every existing ntfy.sh alert ALSO goes
# to a self-hosted shrike-notify instance, once one is actually provisioned.
#
# Config (both env vars — see HUMAN_QUEUE.md for the provisioning step):
#   SHRIKE_NOTIFY_URL    base URL of a shrike-notify instance, e.g. https://shrike-notify.example.app
#                        Unset/empty -> shrike_notify_publish() is a silent no-op (same
#                        pattern as other optional cross-service integrations in this repo,
#                        e.g. deploy_watch.sh's `.env.railway` / RAILWAY_TOKEN gating).
#   SHRIKE_NOTIFY_TOKEN  optional bearer token, only needed if shrike-notify has
#                        NOTIFY_REQUIRE_AUTH=1. Unset -> published unauthenticated.
#
# Topic taxonomy (keep this list in sync with any new publisher). NOTE: shrike-notify
# validates topic names as 1..64 chars of [A-Za-z0-9_-] ONLY (no dots) — see
# shrike-notify/backend/app/models.py:validate_topic — so the taxonomy is underscore-
# separated, not dot-separated:
#   fleet_<repo>_deploy   deploy_watch.sh   — one topic per real repo (billwatch, iptv_apps,
#                                              gitlark, shrike-labs-website, ...), same
#                                              granularity as its existing per-surface alerts.
#   fleet_queue_task      digest_notify.sh  — the periodic fleet-wide cycle digest is a single
#                                              rolled-up message spanning many repos, so it uses
#                                              the repo-agnostic "queue" bucket instead of one
#                                              specific repo.
#   fleet_queue_promote   daily_promote.sh  — same reasoning: one aggregate summary per day
#                                              covering every promoted repo, not repo-specific.
#
# shrike-notify's publish API is POST /{topic} with JSON {"title","body","tags","priority"}
# (see shrike-notify/README.md). Topics don't need to pre-exist — publish creates history
# for a topic on first use.
set -uo pipefail

# shrike_notify_publish <topic> <title> <tags-csv> <body>
# Best-effort, fire-and-forget — never fails the caller (mirrors the existing
# `... || true` pattern every ntfy.sh call in these scripts already uses).
shrike_notify_publish() {
  local topic="$1" title="$2" tags="$3" body="$4"
  [ -n "${SHRIKE_NOTIFY_URL:-}" ] || return 0
  local base="${SHRIKE_NOTIFY_URL%/}"
  local hdr=(-H "Content-Type: application/json")
  [ -n "${SHRIKE_NOTIFY_TOKEN:-}" ] && hdr+=(-H "Authorization: Bearer ${SHRIKE_NOTIFY_TOKEN}")
  local payload
  payload="$(SN_TITLE="$title" SN_BODY="$body" SN_TAGS="$tags" python3 -c '
import json, os
tags = [t.strip() for t in os.environ.get("SN_TAGS", "").split(",") if t.strip()]
print(json.dumps({
    "title": os.environ.get("SN_TITLE", ""),
    "body": os.environ.get("SN_BODY", ""),
    "tags": tags,
    "priority": "default",
}))
' 2>/dev/null)"
  [ -n "$payload" ] || return 0
  curl -fsS --max-time 8 "${hdr[@]}" -d "$payload" "$base/$topic" >/dev/null 2>&1 || true
}

# shrike_monitor_heartbeat <job>
# Dead-man's-switch ping to a shrike-monitor heartbeat monitor on each SUCCESSFUL cycle of a
# pipeline script, so a stalled cron surfaces in shrike-monitor instead of only in incident
# review. <job> is one of: BRANCH_HYGIENE, RECONCILE, PROMOTE (any [A-Z_]+ token works).
#
# The full ping URL (".../heartbeat/<id>?token=<ping_token>") comes from, in order:
#   1. env var SHRIKE_HEARTBEAT_URL_<JOB>
#   2. a line "SHRIKE_HEARTBEAT_URL_<JOB>=<url>" in ${SHRIKE_HEARTBEAT_FILE:-<lib dir>/state/heartbeat_urls.env}
#      (written, mode 600, by `register_monitors.sh --heartbeats`)
# Neither set -> silent no-op. Best-effort: never fails the caller, short timeout. This is NOT a
# phone notification (nothing goes through ovn_notify.py / ntfy) - a ping is only a signal to
# shrike-monitor, which alerts on SILENCE, so the notification policy (emergencies + one hourly
# update) is unaffected and a healthy fleet generates zero pushes.
_SN_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
shrike_monitor_heartbeat() {
  local job="${1:-}" var url file
  case "$job" in ""|*[!A-Z_]*) return 0;; esac
  var="SHRIKE_HEARTBEAT_URL_${job}"
  url="${!var:-}"
  if [ -z "$url" ]; then
    file="${SHRIKE_HEARTBEAT_FILE:-$_SN_LIB_DIR/state/heartbeat_urls.env}"
    [ -f "$file" ] && url="$(sed -n "s/^${var}=//p" "$file" 2>/dev/null | tail -1)"
  fi
  [ -n "$url" ] || return 0
  curl -fsS --max-time 8 -X POST "$url" >/dev/null 2>&1 || true
  return 0
}
