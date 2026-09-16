#!/usr/bin/env bash
# Structural guards for the 2026-09-01 merge-stall postmortem fixes. FAIL if any
# regresses. branch_hygiene.sh + queue_health.sh live server-side (like
# run_overnight.sh), so point at them via env or the default overnight-queue dir.
set -uo pipefail
OQ="${OVN_QUEUE_DIR:-$HOME/overnight-queue}"
H="${OVN_HYGIENE:-$OQ/branch_hygiene.sh}"
Q="${OVN_HEALTH:-$OQ/queue_health.sh}"
RO="${OVN_RUNNER:-$OQ/run_overnight.sh}"
SS="${OVN_STAGE_SWEEP:-$OQ/ovn_stage_sweep.sh}"
SR="${OVN_STAGE_RUNNER:-$OQ/ovn_stage_runner.sh}"
P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

if [ -f "$H" ]; then
  # 1) repo path resolved to absolute (else the found venv_pytest breaks after cd -> false red)
  ok "hygiene resolves \$repo to absolute" "grep -q 'resolve \$repo to ABSOLUTE' $H"
  # 2) pytest gate is pytest-cov-independent (no bare --no-cov that errors when the plugin is absent)
  ok "hygiene pytest not dependent on pytest-cov" "grep -q 'addopts=' $H && ! grep -qE 'venv_pytest.* --no-cov' $H"
  # 3) npm ci runs per package (so test-only packages like vscode-extension have deps)
  ok "hygiene npm-ci per package" "grep -q 'provision deps ONCE per package' $H"
  # 4) the VS Code extension harness (needs a display) is skipped for npm test
  ok "hygiene skips vscode-extension npm test" "grep -q 'vscode-extension' $H"
  # 5) 2026-09-10: billwatch gate-failed silently ~9x over 17h with zero diagnostic detail
  # beyond "gate FAILED (build/tests red)" — a real crash/traceback/hang on stderr had nowhere
  # to go. The pytest gate must merge stderr into the same stream as everything else (not
  # discard it), so a repeat is actually debuggable from the log instead of a dead end.
  ok "hygiene pytest gate does not discard stderr" \
     "! grep -E 'venv_pytest.*no:cacheprovider.*2>/dev/null' $H"
  # 2026-09-15: 40 historical "gate FAILED (build/tests red)" flags on billwatch, every
  # one investigated so far was TEST_TIMEOUT killing pytest at as little as 17% through
  # the suite (contention, not a real red test) — self-healed on the next cron cycle
  # every single time. Gate must distinguish timeout(1)'s exit 124 from a genuine
  # failure and retry once with a fresh worktree before flagging, instead of waiting
  # up to 3h for the next scheduled tick to do the same self-heal.
  ok "hygiene tracks timeout(124) separately from a real test failure" \
     "grep -q '_GATE_TIMEOUT_HIT' $H"
  ok "hygiene pytest gate checks for exit 124 specifically" \
     "grep -A2 'venv_pytest.* -q -o addopts' $H | grep -q '\"\$rc\" -eq 124'"
  ok "hygiene retries once on a timeout-caused gate failure before flagging" \
     "grep -q 'retrying once with a fresh worktree' $H"
else
  echo "  (skip: $H not present on this host)"
fi

if [ -f "$Q" ]; then
  # 5) stalled-merge alert exists (feature far ahead of main -> ntfy, caught same-day)
  ok "queue_health has stalled-merge alert" "grep -q 'Hygiene stalled' $Q"
else
  echo "  (skip: $Q not present on this host)"
fi

# 6) per-cycle gate scripts point at the real .venv (SpecPilot's checked the wrong
#    'venv' path -> ran zero tests -> full-suite red slipped through)
for v in "$OQ/repos/test-automation-agent/.ovn-verify.sh" "$OQ/repos/iptv_apps/.ovn-verify.sh"; do
  [ -f "$v" ] || continue
  ok "gate $(basename "$(dirname "$v")")/.ovn-verify uses .venv" "grep -q '\.venv/bin' $v"
done

# 7) 2026-09-16: the outer `timeout N bash ovn_stage_runner.sh` wrapper (in both
# run_overnight.sh's inline higher-tier call and ovn_stage_sweep.sh) must stay >= the
# inner OVN_STAGE_HARD_TIMEOUT it wraps. Plain `timeout N cmd` only SIGTERMs the direct
# child, not grandchildren — if the OUTER timeout is shorter, it fires first and kills
# the wrapper script (running its EXIT trap, which deletes the temp worktree) while a
# still-running grandchild (a full-verify pytest pass) is orphaned and keeps executing
# against a now-deleted directory, crashing near the end of an otherwise-passing run.
# Confirmed live: iptv_apps lost multiple genuinely-good multi-step attempts this way
# when the outer timeout (1500s) was shorter than the inner hard-watchdog (2000s
# default) — every real land got discarded and misreported as a verify failure.
if [ -f "$SR" ]; then
  _inner="$(grep -oE 'OVN_STAGE_HARD_TIMEOUT:-[0-9]+' "$SR" | head -1 | grep -oE '[0-9]+$')"
  _inner="${_inner:-2000}"
  if [ -f "$RO" ]; then
    _outer_ro="$(grep -oE 'timeout [0-9]+ bash ovn_stage_runner\.sh' "$RO" | head -1 | grep -oE '[0-9]+')"
    ok "run_overnight.sh's outer stage-runner timeout ($_outer_ro) >= inner hard-watchdog ($_inner)" \
       "[ -n \"\$_outer_ro\" ] && [ \"\$_outer_ro\" -ge \"\$_inner\" ]"
  fi
  if [ -f "$SS" ]; then
    _outer_ss="$(grep -oE 'timeout [0-9]+ bash ovn_stage_runner\.sh' "$SS" | head -1 | grep -oE '[0-9]+')"
    ok "ovn_stage_sweep.sh's outer stage-runner timeout ($_outer_ss) >= inner hard-watchdog ($_inner)" \
       "[ -n \"\$_outer_ss\" ] && [ \"\$_outer_ss\" -ge \"\$_inner\" ]"
  fi
fi

echo "Hygiene invariants: $P passed, $F failed"
[ "$F" -eq 0 ]
