#!/usr/bin/env bash
# test_qa_gate_mutation.sh - wrapper for test_qa_gate_mutation.py (S7/S8, advisory gates). Pins the real CLI under env -i from an absolute AND a relative path
# (NTFY_SERVER set, private HOME/TMPDIR via lib_safe_tmp.sh), then runs the python suite. A missing python suite is a FAILURE, not a skip.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
. "$HERE/lib_safe_tmp.sh"
PY="${QA_TEST_PYTHON:-$(command -v python3.12 || command -v python3)}"
rc=0; ok(){ echo "  ok   $1"; }; fail(){ echo "  FAIL $1"; rc=1; }
tmp="$(safe_mktemp_dir)" || exit 1
trap 'safe_rm_rf "$tmp"' EXIT
mkdir -p "$tmp/state" "$tmp/home" "$tmp/tmp"
[ -f "$ROOT/qa/gate_mutation.py" ] || { echo "  FAIL qa/gate_mutation.py missing"; exit 1; }
[ -x "$ROOT/qa/gate_mutation.py" ] && ok "gate_mutation.py is executable (git mode 755)" || fail "gate_mutation.py not executable"
out="$(env -i PATH=/usr/bin:/bin NTFY_SERVER=http://127.0.0.1:9 HOME="$tmp/home" TMPDIR="$tmp/tmp" OVN_DIR="$tmp" QA_STATE_DIR="$tmp/state" QA_VENV="$tmp/none" "$PY" "$ROOT/qa/gate_mutation.py" check --repo nonexistent-repo --base a --head b --no-record 2>"$tmp/err")"
code=$?
[ "$code" -eq 0 ] && ok "absolute path, env -i, exit 0 on an unknown repo" || fail "absolute path exit $code"
echo "$out" | tail -1 | grep -q '"verdict": "UNVERIFIED"' && ok "UNVERIFIED (never FAIL/PASS) JSON line" || fail "no UNVERIFIED line: $out"
out2="$(cd "$ROOT" && env -i PATH=/usr/bin:/bin NTFY_SERVER=http://127.0.0.1:9 HOME="$tmp/home" TMPDIR="$tmp/tmp" OVN_DIR="$tmp" QA_STATE_DIR="$tmp/state" QA_VENV="$tmp/none" "$PY" qa/gate_mutation.py check --repo nonexistent-repo --base a --head b 2>/dev/null)"
[ $? -eq 0 ] && ok "relative path, env -i, exit 0" || fail "relative path failed"
[ "$(wc -l < "$tmp/state/qa_shadow/mutation.jsonl" 2>/dev/null | tr -d ' ')" = "1" ] && ok "one advisory row recorded in qa_shadow/mutation.jsonl" || fail "row count wrong"
env -i PATH=/usr/bin:/bin HOME="$tmp/home" OVN_DIR="$tmp" QA_STATE_DIR="$tmp/state" "$PY" "$ROOT/qa/gate_mutation.py" daily --repos nonexistent-repo --no-record 2>/dev/null | grep -q skipped && ok "daily on a repo without a clone is skipped, exit 0" || fail "daily did not skip"
"$PY" "$ROOT/scripts/test/lint_unsafe_rm.py" "$ROOT/qa" "$ROOT/scripts/test/test_qa_gate_mutation.sh" "$ROOT/scripts/test/test_qa_gate_precision.sh" >/dev/null && ok "lint_unsafe_rm.py passes on the new files" || fail "lint_unsafe_rm.py findings"
"$PY" "$HERE/test_qa_gate_mutation.py" || fail "python suite (test_qa_gate_mutation.py)"
exit $rc
