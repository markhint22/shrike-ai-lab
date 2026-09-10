#!/usr/bin/env bash
# Structural guards for the 2026-09-01 merge-stall postmortem fixes. FAIL if any
# regresses. branch_hygiene.sh + queue_health.sh live server-side (like
# run_overnight.sh), so point at them via env or the default overnight-queue dir.
set -uo pipefail
OQ="${OVN_QUEUE_DIR:-$HOME/overnight-queue}"
H="${OVN_HYGIENE:-$OQ/branch_hygiene.sh}"
Q="${OVN_HEALTH:-$OQ/queue_health.sh}"
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

echo "Hygiene invariants: $P passed, $F failed"
[ "$F" -eq 0 ]
