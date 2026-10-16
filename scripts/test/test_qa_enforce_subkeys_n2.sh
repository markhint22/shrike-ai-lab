#!/usr/bin/env bash
# 2026-10-13 (package qa): qa_enforce.sh can flip the two NEW second keys of gate_antigaming (antigaming_emptied = A_TESTFILE_EMPTIED alone, antigaming_newpath =
# N_NEWPATH_LOOKALIKE). End to end with the REAL gate: shadow => FLAG, after the CLI flip => FAIL, after the rollback => FLAG again; both show in `status`.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; Q="$(cd "$HERE/../.." && pwd)"
P=0; F=0
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
T="$(__d="$(mktemp -d)" && [ -n "$__d" ] && cd "$__d" && pwd -P)" || exit 1; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/state" "$T/gates" "$T/repos"
printf '#!/usr/bin/env python3\n' > "$T/gates/gate_antigaming.py"
QE(){ ( QA_STATE_DIR="$T/state" QA_GATES_DIR="$T/gates" OVN_DIR="$T" QA_ENFORCE_WHO=tester@box bash "$Q/qa/qa_enforce.sh" "$@" ); }
unset OVN_QA_ANTIGAMING OVN_QA_ANTIGAMING_TESTFILES OVN_QA_ANTIGAMING_FROZEN OVN_QA_ANTIGAMING_EMPTIED OVN_QA_ANTIGAMING_NEWPATH

ok "status lists antigaming_emptied (default shadow)" "QE status | grep -q 'antigaming_emptied .*shadow .*source=default'"
ok "status lists antigaming_newpath (default shadow)" "QE status | grep -q 'antigaming_newpath .*shadow .*source=default'"
for k in antigaming_emptied antigaming_newpath; do
  QE $k enforce > "$T/o_$k.txt" 2>&1; rc=$?
  ok "$k enforce is ACCEPTED (gate_antigaming.py installed) and says it is a second key" "[ $rc = 0 ] && grep -q \"ENFORCING the second key '$k'\" '$T/o_$k.txt'"
  ok "status then shows $k enforce, source=file" "QE status | grep '$k' | grep -q 'enforce .*source=file.*tester@box'"
  QE $k shadow >/dev/null 2>&1; rc=$?
  ok "rollback of $k is allowed and exits 0" "[ $rc = 0 ] && QE status | grep '$k' | grep -q 'shadow .*source=file'"
done
mkdir -p "$T/gates2"; QA_GATES_DIR="$T/gates2" QA_STATE_DIR="$T/state" OVN_DIR="$T" bash "$Q/qa/qa_enforce.sh" antigaming_newpath enforce >/dev/null 2>&1; rc=$?
ok "NEGATIVE: without gate_antigaming.py installed the new sub-keys cannot be enforced" "[ $rc = 2 ]"
QE antigaming_newpaths enforce >/dev/null 2>&1; rc=$?
ok "NEGATIVE: a typo'd sub-key name is still refused" "[ $rc = 2 ]"

# ---- end to end with the REAL gate
R="$T/repos/demo"; mkdir -p "$R"; ( cd "$R" || exit 1; git init -q && git config user.email t@t && git config user.name t
  mkdir -p app/routers tests
  printf 'def f():\n    return 1\n' > app/routers/billing.py
  printf 'from app.routers.billing import f\n\n\ndef test_f():\n    assert f() == 1\n' > tests/test_billing.py
  git add -A && git commit -q -m a
  mkdir -p app/routers/outers && printf '\n' > app/routers/outers/subscription.py && printf '\n' > tests/test_billing.py && git add -A && git commit -q -m b )
gate(){ ( cd "$T" && env -i PATH="$PATH" HOME="$T" OVN_DIR="$T" QA_STATE_DIR="$T/state" GIT_CONFIG_GLOBAL=/dev/null python3 "$Q/qa/gate_antigaming.py" check --repo "$R" --base HEAD~1 --head HEAD --no-record | tail -1 ); }
sevof(){ gate | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(','.join(sorted('%s:%s'%(f['rule'],f['sev']) for f in d['details']['findings'] if f['rule'] in ('A_TESTFILE_EMPTIED','N_NEWPATH_LOOKALIKE'))))"; }
ok "e2e shadow: both rules are FLAG" "[ \"\$(sevof)\" = 'A_TESTFILE_EMPTIED:FLAG,N_NEWPATH_LOOKALIKE:FLAG' ]"
QE antigaming_newpath enforce >/dev/null 2>&1
ok "e2e: antigaming_newpath enforce arms ONLY the new-path rule" "[ \"\$(sevof)\" = 'A_TESTFILE_EMPTIED:FLAG,N_NEWPATH_LOOKALIKE:FAIL' ]"
QE antigaming_newpath shadow >/dev/null 2>&1; QE antigaming_emptied enforce >/dev/null 2>&1
ok "e2e: antigaming_emptied enforce arms ONLY A_TESTFILE_EMPTIED" "[ \"\$(sevof)\" = 'A_TESTFILE_EMPTIED:FAIL,N_NEWPATH_LOOKALIKE:FLAG' ]"
QE antigaming_emptied shadow >/dev/null 2>&1
ok "e2e: after the rollbacks both are FLAG again" "[ \"\$(sevof)\" = 'A_TESTFILE_EMPTIED:FLAG,N_NEWPATH_LOOKALIKE:FLAG' ]"
echo "qa_enforce subkeys n2: $P passed, $F failed"; [ "$F" = 0 ]
