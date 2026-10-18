#!/usr/bin/env bash
# Regression test (intake package, reviewer minor 3): ovn_recover_parked.sh's lineage-file extraction.
#  * the lineage file comes from the text BEFORE `VERIFY:` (task_edit), so the GUT runner named in a VERIFY is not the lineage bucket;
#  * an item whose ONLY path sits inside its VERIFY (no path in the description) falls back to the whole item minus the -s/--script argument, so it keeps a per-FILE bucket
#    instead of the per-repo __unknown one;
#  * OVN_PARK_VERIFY_SCOPE=off (the kill switch) restores the old whole-item extraction.
# Evals the REAL block out of ovn_recover_parked.sh of this tree (as test_recover_parked_lineage_normalization.sh does).
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }   # 2026-10-16: fail-closed sandbox helpers (see lint_unsafe_rm.py)
HERE="$(cd "$(dirname "$0")" && pwd)"
QD="$(cd "$HERE/../.." && pwd)"
RP="${OVN_RECOVER_PARKED:-$QD/ovn_recover_parked.sh}"
PU="$QD/ovn_park_unworkable.py"
[ -f "$RP" ] && [ -f "$PU" ] || { echo "  SKIP: ovn_recover_parked.sh / ovn_park_unworkable.py not found"; exit 0; }
source "$QD/scripts/lib_path_normalize.sh"
BLOCK="$(sed -n '/^  lineage_file="\$(printf/,/^  lineage_key="\$(printf/p' "$RP")"
[ -n "$BLOCK" ] || { echo "  FAIL: could not extract the lineage block from $RP"; exit 1; }
P=0; F=0
ok(){ if [ "$2" = "$3" ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL: $1 (got '$2', want '$3')"; fi; }
tmp="$(safe_mktemp_dir)" || exit 1; trap 'rm -rf "$tmp"' EXIT
rd="$tmp/repo"; mkdir -p "$rd/scripts" "$rd/addons/gut"
( cd "$rd" && git init -q && git config user.email t@t.com && git config user.name t && echo x > scripts/real.gd && echo x > addons/gut/gut_cmdln.gd && git add -A && git commit -q -m init )

lineage(){ # $1 = task ; env OVN_PARK_VERIFY_SCOPE passes through
  local task="$1" lineage_file lineage_key task_edit
  task_edit="$(printf '%s' "$task" | python3 "$PU" --edit-text 2>/dev/null)"
  [ -n "$task_edit" ] || task_edit="${task%%VERIFY:*}"
  eval "$BLOCK" >/dev/null 2>&1
  printf '%s' "$lineage_file"
}
RUN='godot --headless -s addons/gut/gut_cmdln.gd'
ok "a path in the description wins" "$(rd="$rd" lineage "[T2] scripts/real.gd — fix it. VERIFY: \`grep -q x other/file.gd\`")" "scripts/real.gd"
ok "the GUT runner in the VERIFY is not the lineage file (description has a path)" "$(rd="$rd" lineage "[T2] scripts/real.gd — fix it. VERIFY: \`$RUN -gtest=res://tests/t.gd -gexit\`")" "scripts/real.gd"
ok "[mut] an item whose ONLY path is inside the VERIFY keeps a per-file bucket (not __unknown)" "$(rd="$rd" lineage "[T2] tidy up the helper. VERIFY: \`grep -q x scripts/real.gd\`")" "scripts/real.gd"
ok "[mut] ... and the GUT runner named after -s is not taken as that file" "$(rd="$rd" lineage "[T2] add a case. VERIFY: \`$RUN -gtest=res://tests/t.gd -gexit\`")" "tests/t.gd"
ok "no path anywhere: empty (the __unknown bucket)" "$(rd="$rd" lineage "[T2] do something vague. VERIFY: \`true\`")" ""
ok "[mut] kill switch OVN_PARK_VERIFY_SCOPE=off: the old whole-item extraction (first path wins, runner included)" "$(OVN_PARK_VERIFY_SCOPE=off rd="$rd" lineage "[T2] add a case. VERIFY: \`$RUN -gtest=res://tests/t.gd -gexit\`")" "addons/gut/gut_cmdln.gd"
echo "intake lineage scope: $P passed, $F failed"
[ "$F" -eq 0 ]
