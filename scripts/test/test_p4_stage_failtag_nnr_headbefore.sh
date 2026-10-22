#!/usr/bin/env bash
# 2026-10-21 (package P4). Pins, each with a MUTANT that must break the matching assertion:
#   A. ovn_stage_fail_tag: no verify log + all-no-edit steps -> 'no-edit' (not the bare stage-unverified); verify log -> classified reason; default OFF prints nothing;
#      the status text prefix in run_overnight.sh is unchanged.
#   B. head_before: the marker survives the scout's `> "$task_log"` truncation (sidecar), and both landing paths (aider + inline stage) write it. Every recorded landed row
#      carries a non-empty head_before when a base sha is known.
#   C. NO-NEW-RED re-run-once: a stub that is green on re-run is saved (mode on), shadow only logs, red twice is reverted; _redkind label is right.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"
R="${OVN_RUNNER:-$ROOT/run_overnight.sh}"; LIB="${OVN_P4_LIB:-$ROOT/scripts/lib_p4_outcomes.sh}"; SR="$ROOT/ovn_stage_runner.sh"
P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }
nok(){ if eval "$2" >/dev/null 2>&1; then F=$((F+1)); echo "  FAIL(expected-false): $1"; else P=$((P+1)); fi; }
tmp="$(safe_mktemp_dir p4)" || exit 1; trap 'safe_rm_rf "$tmp"' EXIT
[ -f "$LIB" ] || { echo "  FAIL: $LIB missing"; exit 1; }
PY="$(command -v python3)"
mutate(){ "$PY" - "$1" "$2" "$3" "$4" <<'PYEOF' || { F=$((F+1)); echo "  FAIL: mutant anchor not found: $2"; return 1; }
import sys
src, old, new, out = sys.argv[1:5]
s = open(src).read()
if s.count(old) != 1: sys.exit(1)
open(out, "w").write(s.replace(old, new))
PYEOF
}
export OVN_P4_QDIR="$ROOT"

# ---- A. stage fail tag ----
J1="$tmp/noedit.jsonl"
for s in 0 1 2; do printf '{"run":"r","step":%s,"attempt":1,"verdict":"fail","fail_reason":"no-edit"}\n' "$s"; done > "$J1"
printf '{"run":"r","step":3,"attempt":1,"verdict":"fail","fail_reason":"timeout"}\n{"run":"r","event":"summary","passed":0,"total":4,"verified":false}\n' >> "$J1"
tag(){ ( source "$LIB"; OVN_STAGE_FAILTAG="${OVN_STAGE_FAILTAG-on}" ovn_stage_fail_tag "$@" ); }
ok "A1 no verify log, dominant failed-step reason -> no-edit" "[ \"\$(tag '$J1' '$tmp/none.verify.log')\" = no-edit ]"
J2="$tmp/blocked.jsonl"; printf '{"run":"r","step":0,"verdict":"blocked"}\n' > "$J2"
ok "A2 only blocked steps -> blocked" "[ \"\$(tag '$J2')\" = blocked ]"
J3="$tmp/empty.jsonl"; : > "$J3"
ok "A3 nothing known -> stage-unverified (bounded fallback)" "[ \"\$(tag '$J3')\" = stage-unverified ]"
VL="$tmp/x.verify.log"; printf 'FAILED tests/test_a.py::test_x - assert 1 == 2\n1 failed, 3 passed in 1.00s\n' > "$VL"
ok "A4 verify log present -> classified verify reason (test-red), never the bare label" "[ \"\$(tag '$J1' '$VL')\" = test-red ]"
nok "A5 default (switch unset/off) prints NOTHING so the old label stays" "[ -n \"\$(OVN_STAGE_FAILTAG= tag '$J1')\" ]"
ok "A6 status text prefix unchanged in the caller" "grep -q 'echo \"no-op(stage-unverified) stage(higher-tier)\"' '$R' && grep -q 'echo \"no-op(stage-unverified) stage(higher-tier) bug-handled\"' '$R'"
ok "A7 caller wires the tag to a sidecar read by record_outcome" "grep -q 'ovn_stage_fail_tag' '$R' && grep -q '\\.stagefr' '$R'"
mutate "$LIB" 'tag="$(jq -r '"'"'select(.step!=null and .verdict=="fail"' 'tag="$(jq -r '"'"'select(.step==99 and .verdict=="fail"' "$tmp/mutA.sh" \
  && nok "A-MUTANT step-reason scan disabled (single label) is caught by A1" "[ \"\$( source '$tmp/mutA.sh'; OVN_STAGE_FAILTAG=on ovn_stage_fail_tag '$J1' '$tmp/none.verify.log')\" = no-edit ]"

# ---- B. head_before ----
TL="$tmp/ongoing-x.log"; echo "preamble" > "$TL"
SHA="0123456789abcdef0123456789abcdef01234567"
( source "$LIB"; echo "--- ovn-head-before: $SHA ---" >> "$TL"; ovn_hb_write "$TL" "$SHA" )
: > "$TL"; echo "scout output" > "$TL"     # what the scout's `> "$task_log"` does
ok "B1 head_before survives the scout truncation of the task log" "[ \"\$( source '$LIB'; ovn_hb_read '$TL')\" = '$SHA' ]"
( source "$LIB"; ovn_hb_write "$TL" "ffffffffffffffffffffffffffffffffffffffff" )
ok "B2 first write wins (best-of-N retries reset to the same base)" "[ \"\$( source '$LIB'; ovn_hb_read '$TL')\" = '$SHA' ]"
TL2="$tmp/legacy.log"; printf -- '--- ovn-head-before: %s ---\n' "$SHA" > "$TL2"
ok "B3 legacy in-log marker still read when no sidecar" "[ \"\$( source '$LIB'; ovn_hb_read '$TL2')\" = '$SHA' ]"
ok "B4 aider path writes the sidecar at the marker site" "grep -q 'ovn_hb_write \"\${task_log' '$R'"
ok "B5 inline stage path records a base sha before running the runner" "awk '/_STAGE_OUT=\"\\\$\\(mktemp\\)\"/{f=1} f&&/ovn_hb_write/{print; exit}' '$R' | grep -q ovn_hb_write"
ok "B6 outcome call site reads via ovn_hb_read" "grep -q '_oa_hb=\"\$(ovn_hb_read' '$R'"
mutate "$LIB" 'printf '"'"'%s\n'"'"' "$sha" > "$tl.headbefore" 2>/dev/null' ': > /dev/null' "$tmp/mutB2.sh" \
  && nok "B-MUTANT sidecar never written is caught by B1" "( source '$tmp/mutB2.sh'; rm -f '$TL.headbefore'; ovn_hb_write '$TL' '$SHA'; [ \"\$(ovn_hb_read '$TL')\" = '$SHA' ] )"

# ---- C. NNR re-run-once ----
RD="$tmp/repo"; mkdir -p "$RD/backend/tests"; : > "$RD/backend/tests/test_flaky.py"
ST_OK="$tmp/py_ok.sh"; printf '#!/bin/sh\necho "stub pytest ran: $*" >> "%s/calls"\nexit 0\n' "$tmp" > "$ST_OK"; chmod +x "$ST_OK"
ST_RED="$tmp/py_red.sh"; printf '#!/bin/sh\nexit 1\n' > "$ST_RED"; chmod +x "$ST_RED"
IDS="tests/test_flaky.py::test_epg_activate_concurrent_leaves_one"
CL="$tmp/c.log"; : > "$CL"
nnr(){ ( source "$LIB"; OVN_NNR_RERUN="$1" OVN_NNR_PYTEST="$2" ovn_nnr_apply "$RD" "$CL" "$IDS" ); }
ok "C1 flaky (green on re-run), mode on -> saved (rc 0)" "nnr on '$ST_OK'"
ok "C1b only the failing id was re-run, from the dir that holds it" "grep -q 'test_epg_activate_concurrent_leaves_one' '$tmp/calls'"
nok "C2 red twice, mode on -> NOT saved (revert)" "nnr on '$ST_RED'"
nok "C3 shadow never saves, even when green" "nnr shadow '$ST_OK'"
ok "C3b shadow logs what it would have saved" "grep -q 'NNR-RERUN (shadow).*would have saved' '$CL'"
nok "C4 off does nothing" "nnr off '$ST_OK'"
nok "C5 default mode is off (never saves)" "( source '$LIB'; unset OVN_NNR_RERUN; OVN_NNR_PYTEST='$ST_OK' ovn_nnr_apply '$RD' '$CL' '$IDS' )"
rm -f "$tmp/calls"
( source "$LIB"; unset OVN_NNR_RERUN; OVN_NNR_PYTEST='$ST_OK' ovn_nnr_apply "$RD" "$CL" "$IDS" ) >/dev/null 2>&1
nok "C5b default (unset) runs NO pytest on the revert path (review: unflagged extra run)" "[ -s '$tmp/calls' ]"
nok "C6 non-pytest id (vitest/GUT) is never re-run" "( source '$LIB'; OVN_NNR_RERUN=on OVN_NNR_PYTEST='$ST_OK' ovn_nnr_apply '$RD' '$CL' 'res://tests/x.gd::t' )"
ok "C7 wired into the baseline-subtraction block of the NO-NEW-RED guard" "awk '/_ovn_apply_baseline_subtraction\\(\\) \\{/{f=1} f&&/ovn_nnr_apply/{print; exit} /^      _ovn_apply_baseline_subtraction\$/{exit}' '$R' | grep -q ovn_nnr_apply"
ok "C8 label: failing test the commit did not touch" "( source '$LIB'; ovn_nnr_redkind 'app/x.md' '' 'tests/test_flaky.py::t' | grep -q 'did not touch' )"
ok "C9 label: model changed that test file -> 'model added failing tests'" "( source '$LIB'; [ \"\$(ovn_nnr_redkind 'backend/tests/test_flaky.py' '' 'tests/test_flaky.py::t')\" = 'the model added failing tests' ] )"
ok "C10 label: source change -> source broke label" "( source '$LIB'; ovn_nnr_redkind 'app/a.py' 'app/a.py' 'tests/t.py::t' | grep -q 'source change broke' )"
ok "C11 run_overnight uses the helper for _redkind" "grep -q 'ovn_nnr_redkind' '$R'"
mutate "$LIB" 'py="${OVN_NNR_PYTEST:-}"' 'py="false"' "$tmp/mutC.sh" \
  && nok "C-MUTANT re-run replaced by a failing command is caught by C1" "( source '$tmp/mutC.sh'; OVN_NNR_RERUN=on OVN_NNR_PYTEST='$ST_OK' ovn_nnr_apply '$RD' '$CL' '$IDS' )"


# ---- D. record_outcome (REAL function) fail_reason from the stage sidecar ----
rec(){ ( SCRIPT_DIR="$ROOT"; STATE_DIR="$tmp/stateD.$RANDOM"; mkdir -p "$STATE_DIR"; source "$LIB"; source "$ROOT/scripts/lib_outcome_acct.sh" 2>/dev/null
         eval "$(sed -n '/^record_outcome(/,/^}/p' "${OVN_RUNNER:-$R}")"; record_outcome "$@"; cat "$STATE_DIR/outcomes.jsonl" ); }
DL="$tmp/ongoing-d.log"; printf -- '--- higher-tier sub-flow ---\n' > "$DL"; printf 'no-edit\n' > "$DL.stagefr"
ST="no-op(stage-unverified) stage(higher-tier)"
DR1="$(OVN_STAGE_FAILTAG=on rec d1 repoD "$ST" "" aider_fix 1 "$DL" 100 "$RD" "" "" "")"
ok "D1 on: stage-unverified row carries fail_reason no-edit, status text unchanged" "[ \"\$(printf '%s' '$DR1' | '$PY' -c 'import json,sys; r=json.load(sys.stdin); print(r[\"fail_reason\"]+\"|\"+r[\"status\"])')\" = 'no-edit|$ST' ]"
DR2="$(OVN_STAGE_FAILTAG=off rec d2 repoD "$ST" "" aider_fix 1 "$DL" 100 "$RD" "" "" "")"
ok "D2 off (default): the old bare stage-unverified reason" "printf '%s' '$DR2' | grep -q '\"fail_reason\":\"stage-unverified\"'"
mutate "$R" '[ -s "$tl.stagefr" ]' '[ -s "$tl.stagefr.zz" ]' "$tmp/mutD.sh" \
  && { DM="$(OVN_RUNNER="$tmp/mutD.sh" OVN_STAGE_FAILTAG=on rec d3 repoD "$ST" "" aider_fix 1 "$DL" 100 "$RD" "" "" "" 2>/dev/null)"; nok "D-MUTANT sidecar ignored (single label restored) is caught by D1" "printf '%s' '$DM' | grep -q '\"fail_reason\":\"no-edit\"'"; }

echo "p4: pass=$P fail=$F"; [ "$F" = 0 ]
