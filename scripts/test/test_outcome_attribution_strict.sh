#!/usr/bin/env bash
# 2026-10-10 (harness R10, BX-08 + IPTV-5): outcome rows are billed to the item the cycle WORKED (the line it ticked, else the scout-named item) and to NOBODY when that cannot be resolved.
#
# Live defects replayed:
#   BX-08   41 xlite `landed` rows between 00:15Z and 03:42Z carried item_hash 21566018 (coerce-captured-and-entries-to-arrays) although the commits were doc-comments on unrelated files:
#           record_outcome billed the TOP open line whenever the scout named no matching file.
#   IPTV-5  rows carried another item's feat_tag/hash (cycle 040001 worked test_device_auth_uri.py and credited line 2120, the row said supply-unused-import-device-au) and pure-python
#           cycles got category 'vue' (the repo map in the log listed .vue files).
# Drives the REAL record_outcome() and ovn_resolve_worked_item() extracted from the real files (same technique as test_record_outcome_item_hash_agrees.sh).
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }   # 2026-10-16: fail-closed sandbox helpers (see lint_unsafe_rm.py)
HERE="$(cd "$(dirname "$0")" && pwd)"
R="${OVN_RUNNER:-$HERE/../../run_overnight.sh}"; [ -f "$R" ] || R="$HOME/overnight-queue/run_overnight.sh"
LIB="$HERE/../lib_item_select.sh"; [ -f "$LIB" ] || LIB="$HERE/lib_item_select.sh"
[ -f "$R" ] || { echo "  SKIP: run_overnight.sh not found"; exit 0; }
[ -f "$LIB" ] || { echo "  SKIP: lib_item_select.sh not found"; exit 0; }
P=0; F=0
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }
# shellcheck source=/dev/null
source "$LIB"
FN_SRC="$(sed -n '/^record_outcome(/,/^}/p' "$R")"; [ -n "$FN_SRC" ] || { echo "  FAIL: could not extract record_outcome()"; exit 1; }
eval "$FN_SRC"
SCRIPT_DIR="$(cd "$(dirname "$R")" && pwd)"
tmp="$(safe_mktemp_dir)" || exit 1; trap 'rm -rf "$tmp"' EXIT
STATE_DIR="$tmp/state"; mkdir -p "$STATE_DIR"

# a progress file: line 1 '# progress'; the TOP open item (roster) is NOT what the cycles below work
TOP='- [ ] [T3] scripts/battle/roster.gd — Coerce captured and entries to arrays VERIFY: `grep -q coerce scripts/battle/roster.gd`. (cat:godot; multifile:no) [feat:xlite-20261009-coerce-roster]'
ITM_PY='- [ ] [T2] app/services/device_auth.py — Remove the unused os import VERIFY: `ruff check --select F401 app/services/device_auth.py`. (cat:python; multifile:no) [feat:iptv-20261010-supply-unused-import-device-auth]'
TICKED='- [x] (already-satisfied in code, implement-verified) [T1] scripts/battle/damage.gd — Add a doc comment to apply_damage VERIFY: `grep -q "##" scripts/battle/damage.gd`. (cat:godot; multifile:no) [feat:xlite-20261010-doc-damage]'
mkrepo(){ local d="$tmp/repo.$RANDOM"; mkdir -p "$d"; printf '# progress\n## Next Steps\n%s\n%s\n%s\n%s\n' "$TOP" "$ITM_PY" "$TICKED" "- [ ] [T2] web/src/App.vue — Fix the button VERIFY: \`grep -q type web/src/App.vue\`. (cat:vue)" > "$d/OVERNIGHT_PROGRESS.md"; echo "$d"; }
# rec <repo_dir> <task_log> [status]  -> "item_hash|feat_tag|category|tier"
rec(){ : > "$STATE_DIR/outcomes.jsonl"; record_outcome "t-$RANDOM" repo "${3:-pushed(tests:pass)}" "" aider_fix 1 "$2" 5 "$1" "" 2>/dev/null
  python3 -c "import json;r=json.loads(open('$STATE_DIR/outcomes.jsonl').readline());print('|'.join([r['item_hash'],r['feat_tag'],r['category'],r['tier']]))"; }
H_TOP="$(ovn_item_hash "$TOP")"; H_PY="$(ovn_item_hash "$ITM_PY")"; H_TICK="$(ovn_item_hash "$TICKED")"
LN_TICK=5     # line number of $TICKED in the file above (# progress, ## Next Steps, TOP, ITM_PY, TICKED)

echo "== A: the line the cycle ticked wins (implement-pass credit, scout credit, auto-credit)"
RD="$(mkrepo)"
printf 'repo map: web/src/App.vue web/src/Other.vue\nVERDICT: PROCEED\nFILES: scripts/battle/roster.gd\ncredited line %s (matched damage.gd)\nCREDITED=1\n' "$LN_TICK" > "$tmp/a1.log"
ok "A1 'credited line N' -> the TICKED item's hash, feat_tag, tier (not the top roster item the scout named)" "[ \"\$(rec '$RD' '$tmp/a1.log')\" = '$H_TICK|xlite-20261010-doc-damage|godot|1' ]"
printf -- '--- credited already-done item at line %s (matched damage.gd) ---\n' "$LN_TICK" > "$tmp/a2.log"
ok "A2 scout 'credited already-done item at line N'" "[ \"\$(rec '$RD' '$tmp/a2.log' 'no-op(ALREADY-DONE)' | cut -d'|' -f1)\" = '$H_TICK' ]"
printf -- '--- auto-credit: checked off line %s (green change touched its named file and its VERIFY passed) ---\n--- auto-credit: item-hash %s ---\n' "$LN_TICK" "$H_TICK" > "$tmp/a3.log"
ok "A3 auto-credit 'checked off line N'" "[ \"\$(rec '$RD' '$tmp/a3.log' | cut -d'|' -f1)\" = '$H_TICK' ]"
printf 'credited line 3 (matched roster.gd)\n' > "$tmp/a4.log"
ok "A4 a 'credited line N' whose line is still OPEN (not ticked) is not trusted -> nobody billed" "[ \"\$(rec '$RD' '$tmp/a4.log' | cut -d'|' -f1)\" = '' ]"

echo "== B: the scout-named item (open) when nothing was ticked"
printf 'VERDICT: PROCEED\nPLAN: remove the unused import\nFILES: app/services/device_auth.py\n' > "$tmp/b1.log"
ok "B1 scout FILES names device_auth.py -> that (second-from-top) open item, with ITS category (python)" "[ \"\$(rec '$RD' '$tmp/b1.log')\" = '$H_PY|iptv-20261010-supply-unused-import-device-auth|python|2' ]"

echo "== C: nothing resolvable -> NOBODY is billed (BX-08: not the top item)"
printf 'VERDICT: PROCEED\nPLAN: add doc comments\nFILES: scripts/battle/other_file.gd\n' > "$tmp/c1.log"
r="$(rec "$RD" "$tmp/c1.log")"
ok "C1 scout named a file that is in no open item -> item_hash and feat_tag EMPTY" "[ \"\$(printf '%s' '$r' | cut -d'|' -f1)\" = '' ] && [ \"\$(printf '%s' '$r' | cut -d'|' -f2)\" = '' ]"
ok "C2 ... the category still comes from the scout's own file (godot), not from nowhere" "[ \"\$(printf '%s' '$r' | cut -d'|' -f3)\" = godot ]"
ok "C3 no task log at all -> empty too" "[ \"\$(rec '$RD' /dev/null | cut -d'|' -f1)\" = '' ]"
# 41-landings replay: three doc-comment cycles on files no open item names must not pile onto the top roster item
for i in 1 2 3; do printf 'VERDICT: PROCEED\nFILES: scripts/battle/file_%s.gd\n' "$i" > "$tmp/c2_$i.log"; done
hs="$(for i in 1 2 3; do rec "$RD" "$tmp/c2_$i.log" | cut -d'|' -f1; done | sort -u | tr '\n' ',')"
ok "C4 REPLAY: 3 unrelated landings are billed to nobody (old: all three to the roster item $H_TOP)" "[ '$hs' = ',' ] || [ '$hs' = '' ]"

echo "== D: category comes from the worked item, not from log noise (IPTV-5)"
printf 'repo map: web/src/App.vue web/src/Other.vue web/src/Third.vue\nVERDICT: PROCEED\nFILES: app/services/device_auth.py\n' > "$tmp/d1.log"
ok "D1 a python item whose log lists .vue files is category python (strict)" "[ \"\$(rec '$RD' '$tmp/d1.log' | cut -d'|' -f3)\" = python ]"
ok "D2 MUTATION OVN_OUTCOME_ATTRIB=legacy: the same row is category 'vue' (the live defect)" "[ \"\$(OVN_OUTCOME_ATTRIB=legacy rec '$RD' '$tmp/d1.log' | cut -d'|' -f3)\" = vue ]"

echo "== E: legacy switch and the stage override"
ok "E1 OVN_OUTCOME_ATTRIB=legacy restores the top-of-file fallback (hash of the top roster item)" "[ \"\$(OVN_OUTCOME_ATTRIB=legacy rec '$RD' '$tmp/c1.log' | cut -d'|' -f1)\" = '$H_TOP' ]"
printf 'stage-item-hash %s\nstage-item-line %s\n' "$H_PY" "$ITM_PY" > "$tmp/e2.log"
ok "E2 a staged cycle still bills the stage item (markers win over every other signal)" "[ \"\$(rec '$RD' '$tmp/e2.log' 'pushed(tests:pass) stage(higher-tier)' | cut -d'|' -f1)\" = '$H_PY' ]"

echo "== F: ovn_resolve_worked_item directly"
ok "F1 returns 'N:line' for a ticked credit line" "[ \"\$(ovn_resolve_worked_item '$RD' '$tmp/a1.log' | cut -d: -f1)\" = '$LN_TICK' ]"
ok "F2 returns nothing for a log that resolves nothing" "[ -z \"\$(ovn_resolve_worked_item '$RD' '$tmp/c1.log')\" ]"
ok "F3 ovn_resolve_top_item with nofallback is empty where the plain call returns the top line (the guard keeps its fallback)" "[ -z \"\$(ovn_resolve_top_item '$RD' '$tmp/c1.log' nofallback)\" ] && [ -n \"\$(ovn_resolve_top_item '$RD' '$tmp/c1.log')\" ]"

echo "outcome attribution (strict): $P passed, $F failed"
[ "$F" -eq 0 ]
