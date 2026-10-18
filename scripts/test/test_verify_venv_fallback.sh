#!/usr/bin/env bash
# 2026-10-18: stage worktrees have no .venv, so a bare `pytest` VERIFY clause was rc=127 (UNRUNNABLE). OVN_VERIFY_VENV_FALLBACK (set by stage_item_verify_run)
# resolves pytest from the live clone's venv. Mutant: with the fallback block removed the 'fallback' assertion fails; without the env it must NOT leak.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
LIB="${OVN_LIB_VERIFY_CLAUSE:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)/lib_verify_clause.sh}"
GUARDS="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)/lib_stage_guards.sh"
P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }
T="$(safe_mktemp_dir vfb)" || exit 1
mkdir -p "$T/fleet/backend/.venv/bin" "$T/wt/backend"
printf '#!/bin/sh\necho stub\n' > "$T/fleet/backend/.venv/bin/pytest"; chmod +x "$T/fleet/backend/.venv/bin/pytest"
set +u
. "$LIB" 2>/dev/null
declare -F _resolve_tool_paths >/dev/null || { echo "  FAIL: _resolve_tool_paths not defined"; exit 1; }
out_fb="$(cd "$T/wt" && OVN_VERIFY_VENV_FALLBACK="$T/fleet" _resolve_tool_paths 'pytest backend/tests/test_x.py -v')"
out_no="$(cd "$T/wt" && unset OVN_VERIFY_VENV_FALLBACK; _resolve_tool_paths 'pytest backend/tests/test_x.py -v')"
ok "fallback resolves bare pytest to the fleet clone venv" "case '$out_fb' in *'$T/fleet/backend/.venv/bin/pytest backend/tests/test_x.py -v'*) true;; *) false;; esac"
ok "without the env a bare pytest stays bare (no leak)" "[ '$out_no' = 'pytest backend/tests/test_x.py -v' ]"
ok "stage_item_verify_run exports the fallback" "grep -q 'OVN_VERIFY_VENV_FALLBACK=' '$GUARDS'"
safe_rm_rf "$T"
echo "  passed=$P failed=$F"; [ "$F" = 0 ]
