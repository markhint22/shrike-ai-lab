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
