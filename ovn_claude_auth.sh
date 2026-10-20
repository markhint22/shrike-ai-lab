#!/usr/bin/env bash
# ovn_claude_auth.sh - sourced helper for MAC-side jobs that run a headless `claude -p` (ovn_auto_research.sh, ops/fleet_review/run_review.sh).
# 2026-10-19 incident: the OAuth session expired at ~01:34 CDT; every `claude -p` pass exited rc=1 within 4 s printing (on STDOUT, stderr is empty)
#     Not logged in · Please run /login
# (captured with: CLAUDE_CONFIG_DIR=<empty scratch dir> claude -p ok --max-budget-usd 0.05  ->  rc=1, stdout as above). The research lane counted each one as a failed pass
# (6/day cap + per-repo cooldowns), so it stayed locked out for the rest of the day AFTER the login recovered. An auth failure is not a failed pass: it must not consume
# those budgets; it is an outage of the credential, reported ONCE per outage, and the lane retries at the next tick.
#
#   ovn_claude_is_auth_failure <file>...   0 when the (tail of the) files look like an authentication failure (login / OAuth / expired / 401 / invalid API key)
#   ovn_claude_auth_probe <claude_bin> [timeout_bin] [model]   0 = authenticated, 1 = auth failure, 2 = some other probe failure (callers proceed: not an auth problem)
#   ovn_claude_auth_alert <state_dir> <job> <detail>   ONE urgent push per outage (marker file state_dir/auth_outage); later calls are silent
#   ovn_claude_auth_clear <state_dir> <job>            ends the outage (removes the marker; sends one low-priority "recovered" note when a marker existed)
# Alerts go through the ntfy relay the launchd jobs already use (NTFY_SERVER, topic NTFY_TOPIC); priority urgent = an emergency to ovn_notify.py's relay.

OVN_CLAUDE_AUTH_RE='not logged in|please run /login|run /login|/login to|invalid api key|failed to authenticate|could not authenticate|authentication[_ ]?(error|failed|required)|credentials? (have |has )?(expired|invalid)|(token|session|login) (has )?(expired|is expired)|expired (token|session|login)|^ *(error: )?401 unauthorized'

ovn_claude_is_auth_failure() {
  local f
  for f in "$@"; do
    [ -s "$f" ] || continue
    tail -c 400 "$f" 2>/dev/null | grep -qiE "$OVN_CLAUDE_AUTH_RE" && return 0   # the CLI's own short message only: a long model reply that merely mentions 'oauth' or '401' must never look like an outage
  done
  return 1
}

ovn_claude_auth_probe() {   # <claude_bin> [timeout_bin] [model]
  local bin="$1" tb="${2:-}" model="${3:-}" d rc
  d="$(mktemp -d 2>/dev/null)" || return 2
  [ -n "$d" ] && [ -d "$d" ] || return 2
  # shellcheck disable=SC2086
  ( cd "$d" && ${tb:+$tb ${OVN_CLAUDE_AUTH_PROBE_TIMEOUT_S:-90}} "$bin" -p ok ${model:+--model "$model"} --max-budget-usd 0.05 --permission-mode dontAsk --no-session-persistence > "$d/out" 2> "$d/err" ); rc=$?
  if [ "$rc" -eq 0 ]; then rm -rf "${d:?}"; return 0; fi
  if ovn_claude_is_auth_failure "$d/out" "$d/err"; then OVN_CLAUDE_AUTH_LAST="$(tr '\n' ' ' < "$d/out" | head -c 200)$(tr '\n' ' ' < "$d/err" | head -c 100)"; rm -rf "${d:?}"; return 1; fi
  OVN_CLAUDE_AUTH_LAST="probe rc=$rc: $(cat "$d/out" "$d/err" 2>/dev/null | tr '\n' ' ' | head -c 200)"; rm -rf "${d:?}"; return 2
}

_ovn_auth_push() {   # <title> <priority> <tags> <body>   best-effort, never fails the caller
  command -v curl >/dev/null 2>&1 || return 0
  curl -fsS --max-time 8 -H "Title: $1" -H "Priority: $2" -H "Tags: $3" -d "$4" "${NTFY_SERVER:-https://ntfy.sh}/${NTFY_TOPIC:-shrike_ovn_311380987a}" >/dev/null 2>&1 || true
}

ovn_claude_auth_alert() {   # <state_dir> <job> <detail>
  local sd="$1" job="$2" detail="${3:-}"
  [ -n "$sd" ] && [ -d "$sd" ] || return 0
  [ -e "$sd/auth_outage" ] && return 1   # already alerted for this outage
  date +%s > "$sd/auth_outage"
  _ovn_auth_push "HUMAN: claude login expired ($job)" urgent rotating_light "Headless claude -p on the Mac is not authenticated ($detail). HUMAN: run 'claude' and /login on the Mac. $job skips its ticks (no failed-pass budget is consumed) and resumes by itself on the next tick after login."
  return 0
}

ovn_claude_auth_clear() {   # <state_dir> <job>
  local sd="$1" job="$2"
  [ -n "$sd" ] && [ -e "$sd/auth_outage" ] || return 0
  rm -f "$sd/auth_outage"
  _ovn_auth_push "claude login recovered ($job)" low white_check_mark "Headless claude -p authenticates again; $job resumes."
  return 0
}
