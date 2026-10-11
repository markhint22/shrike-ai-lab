# scripts/test/state_guard.sh - SOURCE this from a test runner (run_all.sh) to FAIL the run when a test writes into the LIVE queue state directory.
#
# 2026-10-11 (r11 acct, platform P9b): test_bash_helpers.sh ran the credit script against $HOME/overnight-queue/scripts with OVN_VERIFY_SHADOW_LOG unset, so every 3-hourly
# run_all.sh appended `repo=tmp.XXXX line=4 result=NO_VERIFY_CLAUSE` / `path_gate=OK target=app/foo.py` rows to the live state/verify_gate_shadow.log (387 rows by 10-11, inflating every
# shadow count). Same family as ntfy_guard.sh (tests must not reach production surfaces), but a pollution guard cannot swallow a file write, so it DETECTS: it measures the live log
# before and after and fails when rows from a repo that is not one of the live fleet repos appeared (the box's real cron/runner rows carry the repo dir name, e.g. repo=iptv_apps, and are ignored).
#
#   . state_guard.sh
#   ovn_state_guard_begin            # once, at the top of the suite   (records the live log's size)
#   ovn_state_guard_end || rc=1      # once, at the end                (prints the offending rows, rc 1)
#   ovn_state_guard_run bash test_x.sh   # or wrap ONE test: runs it, then fails (rc 1, test named) if it polluted
#
# ATTRIBUTION CAVEAT: the guard sees rows, not writers. Another suite running at the same time against the same live dir (the 6-hourly cron run_all.sh, a colleague, a deploy that has not
# yet picked up the OVN_VERIFY_SHADOW_LOG fix) is indistinguishable from the test being run, so use ovn_state_guard_run only when nothing else is testing the box, and prefer the suite-level
# begin/end pair; a flagged row's timestamp + repo label (repo=tmp.XXXX is mktemp's) names the writer when you look at the live log. (Seen 2026-10-11: a guarded test_h13_delete_already_gone.sh run was flagged for two repo=tmp.* rows written during it although that test writes 0 rows under a sandbox HOME; the label/row shape (`line=4 path_gate=OK target=app/foo.py`) is test_bash_helpers.sh's, most likely a concurrent suite run.)
# Env: OVN_GUARD_LIVE_DIR  the live queue dir (default $HOME/overnight-queue; the log is <dir>/state/verify_gate_shadow.log, the real repos are <dir>/repos/*)
#      OVN_GUARD_LIVE_REPOS  space list of repo labels that are legitimate in the live log (default: the names in <dir>/repos/)
#      OVN_STATE_GUARD=off   disables (a person deliberately running the real thing)
# Pure reads of the live dir; never writes there.
_ovn_sg_log() { printf '%s/state/verify_gate_shadow.log' "${OVN_GUARD_LIVE_DIR:-$HOME/overnight-queue}"; }
_ovn_sg_size() { local f; f="$(_ovn_sg_log)"; if [ -f "$f" ]; then wc -c < "$f" | tr -d ' '; else echo 0; fi; }
_ovn_sg_repos() {
  if [ -n "${OVN_GUARD_LIVE_REPOS:-}" ]; then printf '%s\n' $OVN_GUARD_LIVE_REPOS; return; fi
  local d; d="${OVN_GUARD_LIVE_DIR:-$HOME/overnight-queue}/repos"
  [ -d "$d" ] && ls -1 "$d" 2>/dev/null
  return 0
}
ovn_state_guard_begin() {
  [ "${OVN_STATE_GUARD:-on}" = off ] && return 0
  _OVN_SG_BASE="$(_ovn_sg_size)"
}
# prints the foreign rows appended since begin (max 5) and returns 1; returns 0 when none (or the guard is off / was never started)
ovn_state_guard_end() {
  [ "${OVN_STATE_GUARD:-on}" = off ] && return 0
  [ -n "${_OVN_SG_BASE:-}" ] || return 0
  local f cur new live bad
  f="$(_ovn_sg_log)"; cur="$(_ovn_sg_size)"
  [ "$cur" -gt "$_OVN_SG_BASE" ] 2>/dev/null || { _OVN_SG_BASE="$cur"; return 0; }
  new="$(tail -c +$((_OVN_SG_BASE + 1)) "$f" 2>/dev/null)"
  live="$(_ovn_sg_repos | tr '\n' ' ')"
  bad="$(printf '%s\n' "$new" | awk -v live=" $live" '
    NF == 0 { next }
    { r = ""; for (i = 1; i <= NF; i++) if ($i ~ /^repo=/) { r = substr($i, 6); break }
      if (r == "" || index(live, " " r " ") == 0) print }')"
  _OVN_SG_BASE="$cur"
  [ -n "$bad" ] || return 0
  printf 'STATE-GUARD FAIL: a test wrote %s foreign row(s) to the LIVE %s (set OVN_VERIFY_SHADOW_LOG to a temp path in that test):\n' "$(printf '%s\n' "$bad" | wc -l | tr -d ' ')" "$f" >&2
  printf '%s\n' "$bad" | head -5 | cut -c1-200 | sed 's/^/  /' >&2
  return 1
}
# ovn_state_guard_run <cmd...>: run one test and fail it (rc 1) if it polluted the live state; otherwise its own rc.
ovn_state_guard_run() {
  local rc
  ovn_state_guard_begin
  "$@"; rc=$?
  if ! ovn_state_guard_end; then echo "  (offender: $*)" >&2; return 1; fi
  return "$rc"
}
