#!/usr/bin/env bash
# scripts/ovn_gate_governor.sh - cron-ready wrapper for scripts/ovn_gate_governor.py (package L3, 2026-10-18). Runs on the GPU box, where the real journals are.
#
#   ovn_gate_governor.sh watch    auto-demote watchdog (every ~10 min): an ENFORCED gate that stalls a lane is flipped back to shadow in state/pilot_flags.env + ONE alert.
#   ovn_gate_governor.sh weekly   evidence report for every gate -> state/gate_governor/reports/<date>.{md,json} + one hourly-update note (Mon morning)
#   ovn_gate_governor.sh report|status|list ...   passthrough to the python tool (read-only)
#
# SHADOW BY DEFAULT: the mode is OVN_GATE_GOVERNOR env > state/gate_governor/mode > shadow. In shadow, `watch` only logs + alerts what it WOULD demote; nothing is ever written to
# pilot_flags.env. Switch on:  python3 scripts/ovn_gate_governor.py mode enforce      Roll back: python3 scripts/ovn_gate_governor.py mode shadow   (or `off`).
# Never breaks cron: always exits 0 for watch/weekly (a failure is logged to state/gate_governor/cron.log and alerts.log), 2 only for a usage error. Read-only against the queue,
# writes only state/gate_governor/* and (enforce mode, watch only) state/pilot_flags.env. Does not pause, stop or restart anything.
set -uo pipefail
SELF="${BASH_SOURCE[0]:-$0}"
case "$SELF" in /*) ;; *) SELF="$PWD/$SELF" ;; esac
HERE="$(cd "$(dirname "$SELF")" 2>/dev/null && pwd)" || { echo "ovn_gate_governor.sh: cannot resolve own dir" >&2; exit 2; }
OVN_DIR="${OVN_DIR:-$(cd "$HERE/.." && pwd)}"; export OVN_DIR
PY="$HERE/ovn_gate_governor.py"
[ -f "$PY" ] || { echo "ovn_gate_governor.sh: $PY missing" >&2; exit 2; }
STATE="${OVN_GG_STATE:-${QA_STATE_DIR:-$OVN_DIR/state}}"; export OVN_GG_STATE="$STATE"
GGD="$STATE/gate_governor"
mkdir -p "$GGD" 2>/dev/null || true
LOG="$GGD/cron.log"
PYBIN="$(command -v python3 || true)"
[ -n "$PYBIN" ] || { echo "ovn_gate_governor.sh: no python3" >&2; exit 2; }
TO=""; command -v timeout >/dev/null 2>&1 && TO="timeout ${OVN_GG_TIMEOUT:-300}"
cap_log(){ # keep the cron log bounded (2000 lines)
  [ -f "$LOG" ] || return 0
  n="$(wc -l < "$LOG" 2>/dev/null || echo 0)"
  if [ "${n:-0}" -gt 2000 ]; then tail -n 1000 "$LOG" > "$LOG.tmp.$$" 2>/dev/null && mv -f "$LOG.tmp.$$" "$LOG" 2>/dev/null; fi
  return 0
}
run(){ # run <label> <args...>: python tool, output appended to the cron log with a header; rc preserved
  local label="$1"; shift
  { echo "=== $(date -u +%FT%TZ) $label (mode=$(OVN_GG_STATE="$STATE" $PYBIN -I "$PY" mode 2>/dev/null | sed 's/^governor mode: //')) ==="; } >> "$LOG" 2>/dev/null
  # shellcheck disable=SC2086
  $TO $PYBIN -I "$PY" "$@" >> "$LOG" 2>&1
  return $?
}
case "${1:-}" in
  watch)
    run watchdog watchdog; rc=$?
    if [ "$rc" -ne 0 ]; then echo "$(date '+%F %T') warn | gate-governor | watchdog failed rc=$rc (see state/gate_governor/cron.log)" >> "$STATE/alerts.log" 2>/dev/null; fi
    cap_log; exit 0;;
  weekly)
    run weekly report --days "${OVN_GG_WEEKLY_DAYS:-7}" --write --note >/dev/null; rc=$?
    if [ "$rc" -ne 0 ]; then echo "$(date '+%F %T') warn | gate-governor | weekly report failed rc=$rc (see state/gate_governor/cron.log)" >> "$STATE/alerts.log" 2>/dev/null; fi
    cap_log; exit 0;;
  report|status|list|selfcheck|mode)
    exec $PYBIN -I "$PY" "$@";;
  *)
    echo "usage: ovn_gate_governor.sh watch|weekly|report [..]|status|list|selfcheck|mode [m]" >&2; exit 2;;
esac
