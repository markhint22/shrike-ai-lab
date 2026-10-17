#!/usr/bin/env bash
# test_qa_gate_precision.sh - wrapper for test_qa_gate_precision.py (S7/S8, advisory gates). Pins the real CLI under env -i from an absolute AND a relative path
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
[ -f "$ROOT/qa/qa_gate_precision.py" ] || { echo "  FAIL qa/qa_gate_precision.py missing"; exit 1; }
out="$(env -i PATH=/usr/bin:/bin NTFY_SERVER=http://127.0.0.1:9 HOME="$tmp/home" TMPDIR="$tmp/tmp" QA_STATE_DIR="$tmp/state" "$PY" "$ROOT/qa/qa_gate_precision.py" 2>"$tmp/err")"
code=$?
[ "$code" -eq 0 ] && ok "absolute path, env -i, exit 0 on an empty state dir" || fail "exit $code"
echo "$out" | grep -q "labelled: 0" && echo "$out" | grep -q "NOT MET" && ok "0 labelled findings -> bar NOT MET" || fail "wrong precision output: $out"
out2="$(cd "$ROOT" && env -i PATH=/usr/bin:/bin NTFY_SERVER=http://127.0.0.1:9 HOME="$tmp/home" TMPDIR="$tmp/tmp" QA_STATE_DIR="$tmp/state" "$PY" qa/qa_gate_precision.py verdict-rule 2>/dev/null)"
[ $? -eq 0 ] && echo "$out2" | grep -q "catches/min" && ok "relative path: verdict-rule table prints on an empty state dir" || fail "verdict-rule failed"
[ -z "$(ls -A "$tmp/state")" ] && ok "read-only: state dir left empty" || fail "CLI wrote into the state dir"
"$PY" "$HERE/test_qa_gate_precision.py" || fail "python suite (test_qa_gate_precision.py)"
exit $rc
