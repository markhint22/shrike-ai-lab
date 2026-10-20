#!/usr/bin/env bash
# test_ovn_gate_governor.sh - package L3 (gate governor), 2026-10-18: scripts/ovn_gate_governor.py + .sh wrapper, ops/gate_registry.json, ops/install_gate_governor_cron.sh.
# Incident this guards: a SHADOW gate (OVN_STAGE_ITEM_VERIFY) let ~27 `refuse: item VERIFY RED` verdicts still credit and push; nothing told a human how many, there was no evidence-driven way to
# enforce, and no auto-demotion if an enforced gate stalled a lane. The python suite (test_ovn_gate_governor.py) proves, on the REAL journal shapes read from the GPU box and on synthetic
# journals: evidence report (would-block, credited-despite via stage_credited.ledger / summary.commits_pushed, later revert / re-open join), promote REFUSED unless every criterion is met
# (override logged), demote/rollback (byte-exact, verified), the watchdog (repeat-block + lane-stall triggers, shadow never writes, one alert), registry-vs-source selfcheck and 23 MUTANTS
# (each guard removed => its scenario fails). This wrapper also checks the shell side: syntax, exec bits, the cron wrapper, the installer, and that nothing under the repo is written.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OVN="$(cd "$HERE/../.." && pwd)"
. "$HERE/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
P=0; F=0
ok(){ if [ "$2" = 0 ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }
for f in scripts/ovn_gate_governor.sh ops/install_gate_governor_cron.sh; do
  bash -n "$OVN/$f" 2>/dev/null; ok "bash -n $f" $?
  [ -x "$OVN/$f" ]; ok "$f is executable" $?
done
python3 -I -m py_compile "$OVN/scripts/ovn_gate_governor.py" 2>/dev/null; ok "ovn_gate_governor.py compiles" $?
[ -x "$OVN/scripts/ovn_gate_governor.py" ]; ok "ovn_gate_governor.py is executable" $?
python3 -I -c "import json,sys; json.load(open(sys.argv[1]))" "$OVN/ops/gate_registry.json" 2>/dev/null; ok "gate_registry.json is valid JSON" $?
grep -q "ovn_gate_governor.sh watch" "$OVN/ops/cron.gate_governor.proposed.txt"; ok "cron proposal has the watch line" $?
grep -q "ovn_gate_governor.sh weekly" "$OVN/ops/cron.gate_governor.proposed.txt"; ok "cron proposal has the weekly line" $?
# the real tree: registry vs source (default values, env names) - fails when a gate's code default and the registry drift apart
OVN_DIR="$OVN" python3 -I "$OVN/scripts/ovn_gate_governor.py" selfcheck >/dev/null 2>&1; ok "registry matches the source tree (selfcheck)" $?
# nothing is written into the repo tree by the suite (state/ of the real tree must not appear)
BEFORE="$(ls "$OVN" | tr '\n' ' ')"
T="$(safe_mktemp_dir gg_sh)" || exit 1; trap 'rm -rf "$T"' EXIT
TMPDIR="$T" python3 -I "$HERE/test_ovn_gate_governor.py" > "$T/py.out" 2>&1; rc=$?
tail -n 3 "$T/py.out" | sed 's/^/    /'
ok "python suite (evidence, promote/demote/rollback, watchdog, mutants, wrapper, installer)" $rc
[ "$rc" = 0 ] || sed -n '1,60p' "$T/py.out"
AFTER="$(ls "$OVN" | tr '\n' ' ')"
[ "$BEFORE" = "$AFTER" ]; ok "the suite created nothing in the queue root" $?
python3 -I "$HERE/lint_unsafe_rm.py" "$OVN/scripts/ovn_gate_governor.sh" "$OVN/ops/install_gate_governor_cron.sh" "$HERE/test_ovn_gate_governor.sh" "$HERE/test_ovn_gate_governor.py" "$OVN/scripts/ovn_gate_governor.py" >/dev/null 2>&1; ok "lint_unsafe_rm clean on the new files" $?
echo "ovn_gate_governor: $P passed, $F failed"
[ "$F" = 0 ]
