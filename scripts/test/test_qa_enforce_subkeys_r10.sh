#!/usr/bin/env bash
# 2026-10-10 (package qagate): qa_enforce.sh can flip the second keys of gate_antigaming (antigaming_frozen, antigaming_testfiles). The README promised
# `qa_enforce.sh antigaming_frozen enforce` but the CLI refused any enforce for a name without a gate_<name>.py. End to end: after the CLI flip the REAL gate gives
# FAIL for an emptied test file; before the flip (and after the rollback) it is FLAG.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; Q="$(cd "$HERE/../.." && pwd)"
P=0; F=0
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
T="$(__d="$(mktemp -d)" && [ -n "$__d" ] && cd "$__d" && pwd -P)" || exit 1; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/state" "$T/gates" "$T/repos/demo/tests"
printf '#!/usr/bin/env python3\n' > "$T/gates/gate_antigaming.py"
QE(){ ( QA_STATE_DIR="$T/state" QA_GATES_DIR="$T/gates" OVN_DIR="$T" QA_ENFORCE_WHO=tester@box bash "$Q/qa/qa_enforce.sh" "$@" ); }
unset OVN_QA_ANTIGAMING OVN_QA_ANTIGAMING_TESTFILES OVN_QA_ANTIGAMING_FROZEN

ok "status lists both second keys with their mode (default shadow)" "QE status | grep -q 'antigaming_testfiles .*shadow .*source=default' && QE status | grep -q 'antigaming_frozen .*shadow'"
QE antigaming_testfiles enforce > "$T/o1.txt" 2>&1; rc=$?
ok "antigaming_testfiles enforce is ACCEPTED when gate_antigaming.py is installed" "[ $rc = 0 ] && grep -q 'antigaming_testfiles: default(shadow) -> enforce (by tester@box)' '$T/o1.txt'"
ok "status then shows enforce, source=file, who" "QE status | grep 'antigaming_testfiles' | grep -q 'enforce .*source=file.*tester@box'"
ok "the flip is recorded in the mode history" "grep -q '\"gate\": \"antigaming_testfiles\".*\"to\": \"enforce\"' '$T/state/qa_gate_modes.history.jsonl'"
QE antigaming_frozen enforce >/dev/null 2>&1
ok "antigaming_frozen enforce is accepted too (the README's documented command now works)" "[ \"\$(QE status | grep -c 'antigaming_frozen .*enforce .*source=file')\" = 1 ]"
QE antigaming_bogus enforce > "$T/o2.txt" 2>&1; rc=$?
ok "NEGATIVE: an unknown antigaming_* name is still refused (a typo must not look like a flip)" "[ $rc = 2 ] && grep -q 'no such gate' '$T/o2.txt'"
QE nonexistent enforce >/dev/null 2>&1; rc=$?
ok "NEGATIVE: an unknown gate is still refused" "[ $rc = 2 ]"
QE antigaming_testfiles shadow >/dev/null 2>&1; rc=$?
ok "rollback (shadow) is always allowed and exits 0 (it used to exit 1 after a successful flip)" "[ $rc = 0 ] && QE status | grep 'antigaming_testfiles' | grep -q 'shadow .*source=file'"
mkdir -p "$T/gates2"; QA_GATES_DIR="$T/gates2" QA_STATE_DIR="$T/state" OVN_DIR="$T" bash "$Q/qa/qa_enforce.sh" antigaming_testfiles enforce >/dev/null 2>&1; rc=$?
ok "NEGATIVE: without gate_antigaming.py installed the sub-key cannot be enforced" "[ $rc = 2 ]"

# ---- end to end with the REAL gate
R="$T/repos/demo"; ( cd "$R" || exit 1; git init -q && git config user.email t@t && git config user.name t
  printf 'extends GutTest\n\nfunc test_a():\n\tassert_eq(f(), 1)\n' > tests/test_a.gd && git add -A && git commit -q -m a
  printf '\n' > tests/test_a.gd && git add -A && git commit -q -m b )
gate(){ ( cd "$T" && env -i PATH="$PATH" HOME="$T" OVN_DIR="$T" QA_STATE_DIR="$T/state" GIT_CONFIG_GLOBAL=/dev/null python3 "$Q/qa/gate_antigaming.py" check --repo "$R" --base HEAD~1 --head HEAD --no-record | tail -1 ); }
ok "e2e: sub-key shadow (rolled back above) => the emptied test file is a FLAG" "gate | grep -q '\"verdict\": \"FLAG\"' && gate | grep -q 'A_TESTFILE_EMPTIED'"
QE antigaming_testfiles enforce >/dev/null 2>&1
ok "e2e: after 'qa_enforce.sh antigaming_testfiles enforce' the real gate says FAIL for the same diff" "gate | grep -q '\"verdict\": \"FAIL\"'"
QE antigaming_testfiles shadow >/dev/null 2>&1
ok "e2e: after the rollback it is a FLAG again" "gate | grep -q '\"verdict\": \"FLAG\"'"
echo "qa_enforce subkeys r10: $P passed, $F failed"; [ "$F" = 0 ]
