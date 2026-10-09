#!/usr/bin/env bash
# 2026-10-09 (harness-credit-integrity item 8): stage-runner billing.
# A staged cycle (status '... stage(higher-tier)') runs the item the STAGE RUNNER picked, not the top-of-file / scout-matched line record_outcome() and
# ovn_item_guard.sh resolve, so the top item used to be charged (fail/no-op streaks, lastfail, AUTO-SKIP parking, outcomes.jsonl item_hash) for work it never saw.
# run_overnight.sh now writes 'stage-item-hash <md5>' + 'stage-item-line <text>' into the task log after the stage sub-flow; record_outcome() and the guard use them,
# and a stage status WITHOUT them bills nothing (exit 0, like bug-handled). Tests: guard counters, parking, landing, record_outcome item_hash, kill switch, wiring,
# mutation controls.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
S="$HERE/.."; Q="$(cd "$HERE/../.." && pwd)"; RUN="$Q/run_overnight.sh"; GUARD="$S/ovn_item_guard.sh"
P=0; F=0
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
sedi(){ if sed --version >/dev/null 2>&1; then sed -i "$@"; else sed -i '' "$@"; fi; }   # portable in-place sed (BSD on the Mac, GNU on the box)
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
export HOME="$W/home"; mkdir -p "$HOME"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t.com GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
# shellcheck disable=SC1090
. "$S/lib_item_select.sh"

A='- [ ] [T2] app/top.py — the stuck top-of-file item that the stage runner never touches. VERIFY: `true`'
B='- [ ] [T4] [feat:iptv-20261009-stage-thing] app/stage_thing.py — the item the stage runner decomposed. VERIFY: `true`'
mkrepo(){ local r="$W/$1"; rm -rf "$r"; mkdir -p "$r"
  ( cd "$r" && git init -q -b main && git config user.email t@t && git config user.name t && printf '## Next Steps\n%s\n%s\n' "$A" "$B" > OVERNIGHT_PROGRESS.md && git add -A && git commit -q -m init ); printf '%s' "$r"; }
HA="$(ovn_item_hash "$A")"; HB="$(ovn_item_hash "$B")"
BTXT="${B#- \[ \] }"
mklog(){ # $1 = file ; $2 = with-marker(1/0)
  { echo 'Tokens: 5k sent, 100 received.'; echo 'stage runner noise'
    if [ "$2" = 1 ]; then echo "stage-item-hash $HB"; echo "stage-item-line $BTXT"; fi; } > "$1"; }
ST="status"
noopf(){ echo "$1/item_fails/itemS.$2.noopcount"; }
STG='no-op(stage-unverified) stage(higher-tier)'

# ---- a stage failure with the markers bills the STAGE item, not the top item ----
r="$(mkrepo r1)"; st="$W/st1"; mkdir -p "$st"; mklog "$W/l1.log" 1
bash "$GUARD" "$r" "$STG" "$st" itemS "$W/l1.log" >/dev/null 2>&1
ok "stage item B: its no-op counter is 1" "[ \"\$(cat '$(noopf "$st" "$HB")' 2>/dev/null)\" = 1 ]"
ok "top item A: NO counter of any kind (unchanged)" "[ -z \"\$(ls '$st/item_fails/' 2>/dev/null | grep \"\\.$HA\\.\")\" ]"
ok "the stage item's lastfail memory is keyed to B's hash, A has none" "[ -e '$st/item_fails/itemS.$HB.lastfail' ] || [ ! -e '$st/item_fails/itemS.$HA.lastfail' ]"
for i in 2 3 4; do bash "$GUARD" "$r" "$STG" "$st" itemS "$W/l1.log" >/dev/null 2>&1; done
ok "after NCAP=4 stage no-ops the STAGE item B is parked (AUTO-SKIP after 4 no-op cycles)" "grep -qF -- '- [ ] [AUTO-SKIP after 4 no-op cycles' '$r/OVERNIGHT_PROGRESS.md' && grep -F 'AUTO-SKIP' '$r/OVERNIGHT_PROGRESS.md' | grep -qF 'stage_thing.py'"
ok "the top item A is NOT parked and keeps its exact text" "grep -qxF -- '$A' '$r/OVERNIGHT_PROGRESS.md'"

# ---- the fail path (reverted-style stage status) is billed to B as well ----
r="$(mkrepo r2)"; st="$W/st2"; mkdir -p "$st"
bash "$GUARD" "$r" 'reverted(stage-gate) stage(higher-tier)' "$st" itemS "$W/l1.log" >/dev/null 2>&1
ok "a non-no-op stage failure increments B's FAIL counter (.count) and not A's" "[ \"\$(cat '$st/item_fails/itemS.$HB.count' 2>/dev/null)\" = 1 ] && [ ! -e '$st/item_fails/itemS.$HA.count' ]"

# ---- no markers => bill nothing ----
r="$(mkrepo r3)"; st="$W/st3"; mkdir -p "$st"; mklog "$W/l3.log" 0
for i in 1 2 3 4; do bash "$GUARD" "$r" "$STG" "$st" itemS "$W/l3.log" >/dev/null 2>&1; done
ok "stage status WITHOUT stage-item markers: no counter files at all and nothing parked (exit 0 like bug-handled)" "[ -z \"\$(ls '$st/item_fails/' 2>/dev/null)\" ] && [ \"\$(grep -c AUTO-SKIP '$r/OVERNIGHT_PROGRESS.md')\" = 0 ]"
# kill switch: old behaviour (top item billed)
r="$(mkrepo r4)"; st="$W/st4"; mkdir -p "$st"
OVN_STAGE_BILLING=off bash "$GUARD" "$r" "$STG" "$st" itemS "$W/l1.log" >/dev/null 2>&1
ok "OVN_STAGE_BILLING=off restores the old behaviour: the TOP item A is billed (control: proves the new code is what changed it)" "[ \"\$(cat '$(noopf "$st" "$HA")' 2>/dev/null)\" = 1 ] && [ ! -e '$(noopf "$st" "$HB")' ]"
# a plain (non-stage) no-op is still billed to the top item
r="$(mkrepo r5)"; st="$W/st5"; mkdir -p "$st"
bash "$GUARD" "$r" 'no-op(stage-unverified)' "$st" itemS "$W/l1.log" >/dev/null 2>&1
ok "control: a non-stage status is untouched by the markers (billed to the top item A)" "[ \"\$(cat '$(noopf "$st" "$HA")' 2>/dev/null)\" = 1 ] && [ ! -e '$(noopf "$st" "$HB")' ]"
# stage item line that no longer exists as an open line: nothing billed
r="$(mkrepo r6)"; st="$W/st6"; mkdir -p "$st"; sedi 's/^- \[ \] \[T4\]/- [x] [T4]/' "$r/OVERNIGHT_PROGRESS.md"
bash "$GUARD" "$r" "$STG" "$st" itemS "$W/l1.log" >/dev/null 2>&1
ok "stage item already ticked/gone: nothing billed to anyone" "[ -z \"\$(ls '$st/item_fails/' 2>/dev/null)\" ]"
# landing clears the stage item's counters (existing item-hash marker pattern matches the stage- prefix) and not A's
r="$(mkrepo r7)"; st="$W/st7"; mkdir -p "$st/item_fails"; printf '3' > "$st/item_fails/itemS.$HB.count"; printf '2' > "$st/item_fails/itemS.$HA.count"
bash "$GUARD" "$r" 'pushed(tests:pass) stage(higher-tier)' "$st" itemS "$W/l1.log" >/dev/null 2>&1
ok "stage LANDING clears B's counters and leaves A's counter alone" "[ ! -e '$st/item_fails/itemS.$HB.count' ] && [ \"\$(cat '$st/item_fails/itemS.$HA.count')\" = 2 ]"

# ---- record_outcome(): item_hash of a staged cycle is the stage item's ----
FN_SRC="$(sed -n '/^record_outcome(/,/^}/p' "$RUN")"; eval "$FN_SRC"
SCRIPT_DIR="$Q"; STATE_DIR="$W/ostate"; mkdir -p "$STATE_DIR"
row(){ # $1 status $2 log -> item_hash|tier
  : > "$STATE_DIR/outcomes.jsonl"; record_outcome id1 repo "$1" "" aider_fix 1 "$2" 5 "$ROW_REPO" "" 2>/dev/null
  jq -r '.item_hash + "|" + .tier' "$STATE_DIR/outcomes.jsonl" 2>/dev/null | head -1; }
ROW_REPO="$(mkrepo ro)"
ok "record_outcome: staged status + markers => item_hash is B's and the tier comes from B's text (T4)" "[ \"\$(row 'pushed(tests:pass) stage(higher-tier)' '$W/l1.log')\" = '$HB|4' ]"
ok "record_outcome: staged FAILURE + markers => item_hash is B's too" "[ \"\$(row '$STG' '$W/l1.log')\" = '$HB|4' ]"
ok "record_outcome: staged status WITHOUT markers keeps the old top-item hash (A) and its tier (T2)" "[ \"\$(row '$STG' '$W/l3.log')\" = '$HA|2' ]"
ok "record_outcome: a non-stage status ignores the markers (A)" "[ \"\$(row 'pushed(tests:pass)' '$W/l1.log')\" = '$HA|2' ]"
ok "record_outcome: OVN_STAGE_BILLING=off => A" "[ \"\$(OVN_STAGE_BILLING=off row '$STG' '$W/l1.log')\" = '$HA|2' ]"

# ---- run_overnight.sh wiring (code lines, not comments) ----
ok "run_overnight.sh writes stage-item-hash and stage-item-line after the stage sub-flow" "[ \"\$(grep -c '^            echo \"stage-item-hash \$(ovn_item_hash \"\$_stage_item_full\")\" >> \"\$task_log\"' '$RUN')\" = 1 ] && [ \"\$(grep -c '^            echo \"stage-item-line ' '$RUN')\" = 1 ]"
ok "the marker is decoded from the journal's decomposed event with jq (not the quote-truncating grep)" "[ \"\$(grep -c 'jq -r .select(.event==\"decomposed\") | .item. \"\$_STAGE_JSONL\"' '$RUN')\" = 1 ]"

# ---- MUTATION controls ----
mkdir -p "$W/mg"; cp "$S"/*.sh "$S"/*.py "$W/mg/" 2>/dev/null
python3 - "$GUARD" "$W/mg/m_guard.sh" "$W/mg/m_guard2.sh" <<'PY'
import sys
s = open(sys.argv[1]).read()
a = '      [ -n "$_stage_h" ] && [ -n "$_stage_txt" ] || exit 0\n'
assert s.count(a) == 1
open(sys.argv[2], "w").write(s.replace(a, '      :\n'))
b = '  [ -n "$_sl" ] || exit 0\n  top="${_sl}:- [ ] ${_stage_txt}"\n'
assert s.count(b) == 1
open(sys.argv[3], "w").write(s.replace(b, '  :\n'))
PY
r="$(mkrepo m1)"; st="$W/stm1"; mkdir -p "$st"
bash "$W/mg/m_guard.sh" "$r" "$STG" "$st" itemS "$W/l3.log" >/dev/null 2>&1
ok "MUTATION: without the 'no markers => exit 0' line a marker-less stage status bills the top item A again (the no-marker test would fail)" "[ -e '$(noopf "$st" "$HA")' ]"
r="$(mkrepo m2)"; st="$W/stm2"; mkdir -p "$st"
bash "$W/mg/m_guard2.sh" "$r" "$STG" "$st" itemS "$W/l1.log" >/dev/null 2>&1
ok "MUTATION: without the stage-line override the guard bills the top item A for a staged cycle (the B-billing test would fail)" "[ -e '$(noopf "$st" "$HA")' ] && [ ! -e '$(noopf "$st" "$HB")' ]"
echo "$P passed, $F failed"; [ "$F" -eq 0 ]
