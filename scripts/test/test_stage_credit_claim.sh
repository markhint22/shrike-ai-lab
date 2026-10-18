#!/usr/bin/env bash
# 2026-10-15 regression: a higher-tier stage run must be credited ONCE. The 2026-10-14 night showed the same stage summary re-read every
# cycle (2 items, 46 pushed rows in one hour, 2-4 s each, zero new commits). ovn_stage_credit_claim is the one gate; this test drives the
# real library and checks run_overnight.sh routes the stage credit through it.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }   # 2026-10-16: fail-closed sandbox helpers (see lint_unsafe_rm.py)
HERE="$(cd "$(dirname "$0")" && pwd)"
LIB="$HERE/../lib_stage_credit.sh"
RUN="$HERE/../../run_overnight.sh"
[ -f "$LIB" ] || { echo "  FAIL: $LIB missing"; exit 1; }
P=0; F=0
ok(){ if [ "$2" = 1 ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }
. "$LIB"
T="$(safe_mktemp_dir)" || exit 1; trap 'rm -rf "$T"' EXIT
L="$T/state/stage_credited.ledger"
A="$T/state/stage_runs/gitlark-20261013-190400.jsonl"
B="$T/state/stage_runs/gitlark-20261014-010000.jsonl"

echo "=== first claim of a stage run is allowed ==="
ovn_stage_credit_claim "$A" "$L"; RC=$?
ok "first claim of run A returns 0" "$([ "$RC" = 0 ] && echo 1 || echo 0)"
ok "ledger created under state/" "$([ -s "$L" ] && echo 1 || echo 0)"

echo "=== the same run read again (the false-credit loop) is refused ==="
ovn_stage_credit_claim "$A" "$L"; RC=$?
ok "second claim of run A returns 1 (no credit)" "$([ "$RC" = 1 ] && echo 1 || echo 0)"
for i in 1 2 3; do ovn_stage_credit_claim "$A" "$L"; done; RC=$?
ok "repeated re-reads stay refused" "$([ "$RC" = 1 ] && echo 1 || echo 0)"
ok "ledger holds run A exactly once" "$([ "$(grep -cxF -- "$A" "$L")" = 1 ] && echo 1 || echo 0)"

echo "=== a genuinely new stage run is credited ==="
ovn_stage_credit_claim "$B" "$L"; RC=$?
ok "claim of new run B returns 0" "$([ "$RC" = 0 ] && echo 1 || echo 0)"

echo "=== no path or no ledger never credits ==="
ovn_stage_credit_claim "" "$L"; RC=$?
ok "empty jsonl path returns 1" "$([ "$RC" = 1 ] && echo 1 || echo 0)"
ovn_stage_credit_claim "$A" ""; RC=$?
ok "empty ledger path returns 1" "$([ "$RC" = 1 ] && echo 1 || echo 0)"

echo "=== ledger stays bounded ==="
for i in $(seq 1 4300); do printf '%s\n' "$T/state/stage_runs/synthetic-$i.jsonl" >> "$L"; done
ovn_stage_credit_claim "$T/state/stage_runs/synthetic-final.jsonl" "$L"
ok "ledger trimmed below 4001 lines" "$([ "$(wc -l < "$L" | tr -d ' ')" -le 4001 ] && echo 1 || echo 0)"
ovn_stage_credit_claim "$T/state/stage_runs/synthetic-final.jsonl" "$L"; RC=$?
ok "newest claim still refused after trim" "$([ "$RC" = 1 ] && echo 1 || echo 0)"

echo "=== run_overnight.sh routes the stage credit through the claim ==="
ok "stage pushed branch calls ovn_stage_credit_claim" "$(grep -q '_STAGE_PUSHED\" -gt 0 \] && ovn_stage_credit_claim' "$RUN" && echo 1 || echo 0)"
ok "run_overnight sources lib_stage_credit.sh" "$(grep -q 'lib_stage_credit.sh' "$RUN" && echo 1 || echo 0)"

echo; echo "$P passed, $F failed"; [ "$F" -eq 0 ]
