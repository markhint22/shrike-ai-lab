#!/usr/bin/env bash
# 2026-10-21 (package P2b): qa_tool_health write_note() fired on EVERY hourly run (24 high notes/24 h for the same 5 findings). Now: only when the finding set changes or
# after OVN_QA_TOOL_HEALTH_NOTE_REPEAT_H (24 h). Fixtures only (OVN_DIR in a sandbox); findings are recorded in tool_health.jsonl regardless.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_safe_tmp.sh" || exit 1
PY="${QA_TEST_PYTHON:-$(command -v python3.12 || command -v python3)}"
[ -n "$PY" ] || { echo "  SKIP: no python3"; exit 0; }
T="$(safe_mktemp_dir)" || exit 1
safe_set_sandbox_home "$T" || exit 1
export TQD_TMP="$T" TQD_QA="$HERE/../../qa"
"$PY" -I "$HERE/test_qa_tool_health_note_dedupe.py"; rc=$?
safe_rm_rf "$T" || rc=1
exit $rc
