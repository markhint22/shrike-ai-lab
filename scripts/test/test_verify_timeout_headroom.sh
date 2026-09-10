#!/usr/bin/env bash
# Regression test: the .ovn-verify.sh override timeout cap must have real headroom over a
# measured-slow repo-owned verify script (2026-09-09).
#
# Real incident: iptv_apps's .ovn-verify.sh runs the FULL backend suite unconditionally
# (intentional - a scoped verify once let a real full-suite break slip through, see the
# 2026-08-15 comment in run_overnight.sh). The suite grew from 657 tests (measured ~200s when
# the cap was set to 240s) to 1436 tests (measured 356s) - the cap was NEVER re-tuned as the
# suite grew, so EVERY cycle touching the backend was guaranteed to hit the 240s timeout, get
# misread as "tests red" by the NO-NEW-RED GUARD, and revert fully-green work. Confirmed 97+
# false reverts in under 2 days. This is the exact same class of bug as the T3+ no-edit
# detector: a hardcoded assumption silently invalidated by the pipeline's own growth. Raised to
# 600s. This test doesn't re-run the (356s) suite - it structurally asserts the deployed cap,
# so a future accidental revert back toward 240 fails loudly instead of silently reintroducing
# the false-revert bug.
set -uo pipefail
R="${OVN_RUNNER:-$HOME/overnight-queue/run_overnight.sh}"
[ -f "$R" ] || { echo "  SKIP: $R not found on this host"; exit 0; }
P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

MIN_TIMEOUT=400  # comfortably above the old 240s that caused the false-revert bug

ovnv_timeouts="$(grep -oE "timeout [0-9]+ bash \"\\\$\\(basename \"\\\$_ovnv\"\\)\"" "$R" | grep -oE '[0-9]+')"
dir_timeouts="$(grep -oE 'timeout [0-9]+ \./\.ovn-verify\.sh' "$R" | grep -oE '[0-9]+')"

ok "repo-root .ovn-verify.sh override has >=${MIN_TIMEOUT}s cap" \
   "[ -n \"\$ovnv_timeouts\" ] && [ \"\$ovnv_timeouts\" -ge $MIN_TIMEOUT ]"
ok "per-venv-dir .ovn-verify.sh override has >=${MIN_TIMEOUT}s cap" \
   "[ -n \"\$dir_timeouts\" ] && [ \"\$dir_timeouts\" -ge $MIN_TIMEOUT ]"

# sanity: not absurdly high either (a genuinely hung script should still get caught within a
# cycle's overall time budget, not block it for 20+ minutes)
MAX_SANE_TIMEOUT=1200
ok "repo-root cap isn't unreasonably high (would mask a genuinely hung script)" \
   "[ -z \"\$ovnv_timeouts\" ] || [ \"\$ovnv_timeouts\" -le $MAX_SANE_TIMEOUT ]"

# Same class of bug found again (2026-09-09) in a separate file: ovn_stage_runner.sh's
# full_verify() has its OWN independent "timeout 300" for the same full pytest suite, never
# covered by the check above (which only greps run_overnight.sh). Confirmed via verify.log
# (truncated mid-progress-bar at 81%) + start/FAILED log timestamps exactly 300s apart that
# EVERY T3+ iptv_apps stage-runner attempt was getting falsely reverted here too. Raised to 600s.
SR="${OVN_STAGE_RUNNER:-$HOME/overnight-queue/ovn_stage_runner.sh}"
if [ -f "$SR" ]; then
  sr_timeouts="$(grep -oE 'timeout [0-9]+ "\$HOME/overnight-queue/\$vp"' "$SR" | grep -oE '[0-9]+')"
  ok "ovn_stage_runner.sh pytest-FULL cap has >=${MIN_TIMEOUT}s headroom" \
     "[ -n \"\$sr_timeouts\" ] && [ \"\$sr_timeouts\" -ge $MIN_TIMEOUT ]"
  ok "ovn_stage_runner.sh pytest-FULL cap isn't unreasonably high" \
     "[ -z \"\$sr_timeouts\" ] || [ \"\$sr_timeouts\" -le $MAX_SANE_TIMEOUT ]"
else
  echo "  SKIP: $SR not found on this host"
fi

echo "Verify-timeout headroom: $P passed, $F failed"
[ "$F" -eq 0 ]
