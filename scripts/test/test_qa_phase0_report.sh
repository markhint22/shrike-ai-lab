#!/usr/bin/env bash
# test_qa_phase0_report.sh - wrapper for the phase0_report suite. Runs the Python suite, then pins the real CLI under env -i
# (absolute path and a relative path from scripts/overnight-queue, NTFY_SERVER set): exit 0 and an `overall` line on an empty state dir.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
[ -f "$ROOT/qa/phase0_report.py" ] || { echo "  SKIP: qa/phase0_report.py not found"; exit 0; }
PY="${QA_TEST_PYTHON:-$(command -v python3.12 || command -v python3)}"
rc=0; ok(){ echo "  ok   $1"; }; fail(){ echo "  FAIL $1"; rc=1; }
tmp="$(mktemp -d)" || exit 1; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/state"
"$PY" "$HERE/test_qa_phase0_report.py" || fail "python suite"
out="$(env -i PATH=/usr/bin:/bin NTFY_SERVER=http://127.0.0.1:9 HOME="$tmp" "$PY" "$ROOT/qa/phase0_report.py" --state-dir "$tmp/state" --now 1792000000 2>"$tmp/err")"
code=$?
[ "$code" -eq 0 ] && ok "absolute path, env -i, exit 0" || fail "absolute path exit $code"
echo "$out" | tail -1 | grep -q '"criterion": "overall"' && ok "overall line printed" || fail "no overall line"
out2="$(cd "$ROOT" && env -i PATH=/usr/bin:/bin NTFY_SERVER=http://127.0.0.1:9 HOME="$tmp" "$PY" qa/phase0_report.py --state-dir "$tmp/state" --now 1792000000 2>/dev/null)"
[ $? -eq 0 ] && ok "relative path, env -i, exit 0" || fail "relative path failed"
echo "$out2" | tail -1 | grep -q '"verdict": "UNVERIFIED"' && ok "empty state overall UNVERIFIED" || fail "empty state overall not UNVERIFIED"
[ -z "$(ls -A "$tmp/state")" ] && ok "empty state dir left empty" || fail "CLI wrote into state dir"
exit $rc
