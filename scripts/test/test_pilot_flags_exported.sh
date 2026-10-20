#!/usr/bin/env bash
# 2026-10-20: run_overnight.sh sourced state/pilot_flags.env with a plain '.', so the flags were shell variables only and
# never reached child processes (ovn_stage_runner.sh etc). Every flag in that file was silently ignored. This proves a flag
# written to the file is visible to a child process, and that the sourcing block exports (set -a).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; QUEUE="$HERE/../.."; RUN="$QUEUE/run_overnight.sh"
P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
source "$HERE/lib_safe_tmp.sh" || { echo "cannot source lib_safe_tmp.sh" >&2; exit 2; }
T="$(safe_mktemp_dir pflag)" || exit 1
cleanup(){ safe_rm_rf "$T"; }
trap cleanup EXIT
mkdir -p "$T/state"; printf 'OVN_STAGE_SCOPE_LEARN=on\nOVN_STAGE_SAME_SIG_STOP=on\n' > "$T/state/pilot_flags.env"

# the EXACT sourcing block as shipped in run_overnight.sh
block="$(grep 'pilot_flags.env' "$RUN" | grep -E '^(if |\[ -f )' | head -1)"
[ -n "$block" ] || { echo "cannot find the shipped sourcing block in run_overnight.sh" >&2; exit 2; }
echo "== the shipped block exports the flags to child processes"
ok "the sourcing block uses set -a (every assignment is exported)" "printf '%s' '$block' | grep -q 'set -a'"
child_sees(){  # run the shipped block in a shell with SCRIPT_DIR set, then ask a CHILD process for the variable
  ( SCRIPT_DIR="$T"; eval "$block"; bash -c "printf '%s' \"\${$1:-UNSET}\"" ) }
ok "a child process sees OVN_STAGE_SCOPE_LEARN=on" "[ \"\$(child_sees OVN_STAGE_SCOPE_LEARN)\" = on ]"
ok "a child process sees OVN_STAGE_SAME_SIG_STOP=on" "[ \"\$(child_sees OVN_STAGE_SAME_SIG_STOP)\" = on ]"
echo "== mutant: the old plain-dot sourcing must FAIL the child check"
old_block='[ -f "$SCRIPT_DIR/state/pilot_flags.env" ] && . "$SCRIPT_DIR/state/pilot_flags.env" || true'
old_child="$( ( SCRIPT_DIR="$T"; eval "$old_block"; bash -c 'printf "%s" "${OVN_STAGE_SCOPE_LEARN:-UNSET}"' ) )"
ok "the old plain-dot block does NOT reach a child (got '$old_child')" "[ \"$old_child\" = UNSET ]"
ok "no flags file means no error (the block is a no-op)" "( SCRIPT_DIR=$T/none; eval \"$block\" )"
echo "pilot_flags_exported: $P passed, $F failed"
[ "$F" -eq 0 ]
