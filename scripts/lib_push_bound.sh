#!/usr/bin/env bash
# scripts/lib_push_bound.sh - SOURCE this. Z7-B (2026-11-09): bounded git network calls + cycle phase timestamps.
#
# Incident 2026-11-08 23:25Z: an xlite cycle took 5826 s (max before: 3560 s). aider ran ~80 s, verify 22 s, the cycle log's LAST line was "Successfully rebased" after a rejected push, and
# nothing ran for 97 minutes (the whole single-threaded run loop with it). The main push path was already `timeout 30`, but the commands that run right after a landing were not:
# ovn_item_guard.sh / lib_landing_gates.sh / the stage runner push and fetch with NO timeout, NO terminal-prompt protection and NO stdin redirect, so one stalled connection (or a
# credential helper waiting on a tty) blocks the loop forever. Nothing in the log carried a timestamp, so the stalled step could not even be named.
#
#   ovn_gitb [-C dir] <git args...>          git with `timeout -k 5 $OVN_GIT_NET_TIMEOUT` (default 120), GIT_TERMINAL_PROMPT=0, GIT_ASKPASS=true, </dev/null, ssh BatchMode. rc 124 = timed out.
#   ovn_gitb_pull_rebase [-C dir] <args...>  `ovn_gitb pull --rebase <args>`; a failed or killed rebase is ALWAYS aborted (never leaves .git/rebase-merge behind).
#   ovn_push_rebase_retry <branch> [log]     the push-rejected self-heal: bounded `pull --rebase` + push, at most OVN_PUSH_RETRY_N (3) rebase attempts and OVN_PUSH_RETRY_CAP_S (300) s of
#                                            wall clock for the whole phase. rc 0 = pushed (OVN_PUSH_REBASED=1), rc 1 = not pushed: logs `push-retry exhausted (...)`, any half-done rebase is aborted,
#                                            and the caller keeps its EXISTING failure path (run_overnight: error-transient(push-diverged - resynced...)). The rebase is a `pull --rebase` exactly as before.
#   ovn_phase <name> start|end [note]        one line `[HH:MM:SS] phase=<name> start` / `... end dur=Ns` appended to $OVN_PHASE_LOG, else $task_log, else $TASK_LOG (never stdout: callers
#                                            capture stdout). dur comes from $SECONDS (monotonic, immune to a clock step). OVN_PHASE_LOG_ON=off silences it. Never fails.
# Kill switch for the bounds: OVN_GIT_BOUND=off runs plain git (the old behaviour).

_ovn_gb_ssh() {   # export a non-interactive ssh command unless the operator/repo already chose one
  [ -n "${GIT_SSH_COMMAND:-}" ] || [ -n "${GIT_SSH:-}" ] && return 0
  [ -n "$(git config --get core.sshCommand </dev/null 2>/dev/null)" ] && return 0
  export GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=20 -o ServerAliveInterval=15 -o ServerAliveCountMax=3"
}

ovn_gitb() {
  local t="${OVN_GIT_NET_TIMEOUT:-120}" tb
  case "$t" in ''|*[!0-9]*) t=120;; esac
  if [ "${OVN_GIT_BOUND:-on}" = off ]; then git "$@"; return $?; fi
  tb="$(type -P timeout 2>/dev/null || type -P gtimeout 2>/dev/null)"
  if [ -z "$tb" ]; then GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=true git "$@" </dev/null; return $?; fi
  ( _ovn_gb_ssh; GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=true SSH_ASKPASS=true exec "$tb" -k 5 "$t" git "$@" </dev/null )
}

ovn_gitb_pull_rebase() {
  local dir="" rc
  if [ "${1:-}" = "-C" ]; then dir="$2"; shift 2; fi
  if [ -n "$dir" ]; then ovn_gitb -C "$dir" pull --rebase "$@"; else ovn_gitb pull --rebase "$@"; fi
  rc=$?
  if [ "$rc" -ne 0 ]; then
    if [ -n "$dir" ]; then git -C "$dir" rebase --abort >/dev/null 2>&1 || true; else git rebase --abort >/dev/null 2>&1 || true; fi
  fi
  return "$rc"
}

ovn_phase() {
  [ "${OVN_PHASE_LOG_ON:-on}" = off ] && return 0
  local name="${1:-?}" ev="${2:-start}" note="${3:-}" log key t0 line
  log="${OVN_PHASE_LOG:-${task_log:-${TASK_LOG:-}}}"
  [ -n "$log" ] && [ -w "$(dirname "$log")" ] || return 0
  key="_ovn_ph_t0_$(printf '%s' "$name" | tr -c 'A-Za-z0-9' '_')"
  line="[$(date +%H:%M:%S 2>/dev/null)] phase=${name} ${ev}"
  case "$ev" in
    start) printf -v "$key" '%s' "$SECONDS" 2>/dev/null ;;
    *) t0="${!key:-}"; [ -n "$t0" ] && line="${line} dur=$((SECONDS - t0))s" ;;
  esac
  [ -n "$note" ] && line="${line} ${note}"
  printf '%s\n' "$line" >> "$log" 2>/dev/null || true
  return 0
}

# Per-command timeout for the retry loop: min(OVN_GIT_NET_TIMEOUT|120, remaining cap budget). Prints it; returns 1 when the budget is spent. Makes the cap HARD (+ the -k 5 grace)
# instead of checked only at the top of an attempt (2 git commands x 120 s per attempt could overrun a 300 s cap to ~750 s).
_ovn_pr_budget() {
  local t0="$1" cap="$2" base="${OVN_GIT_NET_TIMEOUT:-120}" rem
  case "$base" in ''|*[!0-9]*|0) base=120;; esac
  rem=$((cap - (SECONDS - t0)))
  [ "$rem" -ge 1 ] || return 1
  [ "$rem" -lt "$base" ] && base="$rem"
  printf '%s' "$base"
}

ovn_push_rebase_retry() {
  local branch="${1:?branch}" tl="${2:-/dev/null}" n cap t0 i=0 rc why="" tm
  n="${OVN_PUSH_RETRY_N:-3}"; cap="${OVN_PUSH_RETRY_CAP_S:-300}"
  case "$n" in ''|*[!0-9]*|0) n=3;; esac
  case "$cap" in ''|*[!0-9]*|0) cap=300;; esac
  t0=$SECONDS; OVN_PUSH_REBASED=0
  while [ "$i" -lt "$n" ]; do
    tm="$(_ovn_pr_budget "$t0" "$cap")" || { why="wall-clock cap ${cap}s"; break; }
    i=$((i + 1))
    if declare -F ovn_tree_dirty_note >/dev/null 2>&1; then ovn_tree_dirty_note "$PWD" "$tl" "the cycle (before the push-retry rebase)"; ovn_reset_dirty_lockfiles "$PWD" "$tl" "push-retry"; fi   # 2026-10-13 (iptv F9)
    ovn_phase rebase start "attempt=${i}/${n}"
    OVN_GIT_NET_TIMEOUT="$tm" ovn_gitb_pull_rebase origin "$branch" >>"$tl" 2>&1; rc=$?
    ovn_phase rebase end "rc=${rc}"
    if [ "$rc" -ne 0 ]; then
      # a conflict is deterministic (retrying repeats it); a timeout is a stalled connection and IS retried inside the cap
      if [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; then why="pull --rebase timed out"; continue; fi
      why="rebase did not apply (rc=${rc})"; break
    fi
    tm="$(_ovn_pr_budget "$t0" "$cap")" || { why="wall-clock cap ${cap}s"; break; }
    ovn_phase push start "retry=${i}/${n}"
    OVN_GIT_NET_TIMEOUT="$tm" ovn_gitb push origin "$branch" --quiet 2>>"$tl"; rc=$?
    ovn_phase push end "rc=${rc}"
    if [ "$rc" -eq 0 ]; then OVN_PUSH_REBASED=1; return 0; fi
    why="push rejected again (rc=${rc})"
  done
  [ -n "$why" ] || why="${n} attempts"
  git rebase --abort >/dev/null 2>&1 || true
  git merge --abort >/dev/null 2>&1 || true
  echo "--- push-retry exhausted (${i} rebase attempt(s), $((SECONDS - t0))s, cap ${n}x/${cap}s: ${why}); falling back to the push-failed path ---" >> "$tl" 2>/dev/null || true
  return 1
}
