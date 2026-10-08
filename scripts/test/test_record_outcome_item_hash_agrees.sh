#!/usr/bin/env bash
# Regression test (Phase 6b straggler fix, 2026-09-29): the item_hash record_outcome() writes
# to outcomes.jsonl must be the SAME value the shared ovn_item_hash() (scripts/lib_item_select.sh)
# produces — because that is the key ovn_item_guard.sh and the lastfail lookup use for the same
# item's state/item_fails/ files.
#
# Before this fix record_outcome() md5'd the RAW feat tag (date stamp included) or the raw line
# (leading "- [ ] " checkbox included) inline, so the recorded hash could never equal the guard's
# key. Confirmed against real data for iptv_apps' concurrent-stream-limit-enforcement feature:
# recorded 8f632a43..., guard key 4d313914... — which is why "the recorded hash has no matching
# state file" surfaced as an unexplained anomaly in an investigation the same morning.
#
# Drives the REAL record_outcome() (extracted from the live runner, same technique as
# test_outcome_classification.sh) against a throwaway repo dir + state dir.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
R="${OVN_RUNNER:-$HOME/overnight-queue/run_overnight.sh}"
LIB="$HERE/../lib_item_select.sh"; [ -f "$LIB" ] || LIB="$HERE/lib_item_select.sh"
[ -f "$R" ] || { echo "  SKIP: $R not found on this host"; exit 0; }
[ -f "$LIB" ] || { echo "  SKIP: lib_item_select.sh not found"; exit 0; }

P=0; F=0
# 2026-10-08: assertions are evaluated with pipefail OFF - under pipefail `A | grep -q X` is flaky (grep -q exits at its first hit, A may take SIGPIPE: rc 141) and `! A | grep -q X` can mask a real failure
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

# shellcheck source=/dev/null
source "$LIB"
FN_SRC="$(sed -n '/^record_outcome(/,/^}/p' "$R")"
[ -n "$FN_SRC" ] || { echo "  FAIL: could not extract record_outcome() from $R"; exit 1; }
eval "$FN_SRC"
SCRIPT_DIR="$(cd "$(dirname "$R")" && pwd)"   # record_outcome references it for ovn_classify_fail.sh

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
STATE_DIR="$tmp/state"; mkdir -p "$STATE_DIR"

# record one outcome against a repo dir whose top doable item is $1; echo "<item_hash> <feat_tag>"
rec(){
  local rd="$tmp/repo.$RANDOM"; mkdir -p "$rd"
  printf '# progress\n%s\n' "$1" > "$rd/OVERNIGHT_PROGRESS.md"
  : > "$STATE_DIR/outcomes.jsonl"
  record_outcome "t-$RANDOM" repo "no-op" "" aider_fix 1 /dev/null 0 "$rd"
  python3 -c "import json;r=json.loads(open('$STATE_DIR/outcomes.jsonl').readline());print(r['item_hash'],r['feat_tag'])"
}

# --- A: feat-tagged item: recorded hash == the shared function's hash, and survives a date bump ---
L1='- [ ] [T2] `a.py` — wire it up [feat:demo-20260922-widget]. VERIFY: `true`.'
L2='- [ ] [T2] `a.py` — wire it up [feat:demo-20260929-widget]. VERIFY: `true`.'   # same feature, regenerated
read -r h1 t1 <<<"$(rec "$L1")"
read -r h2 t2 <<<"$(rec "$L2")"
exp1="$(ovn_item_hash "$L1")"
ok "A1 recorded item_hash equals the shared ovn_item_hash() for a feat-tagged item" "[ '$h1' = '$exp1' ]"
ok "A2 a date-only regeneration of the same feature records the SAME item_hash (not a fresh identity)" "[ '$h1' = '$h2' ]"
ok "A3 the raw feat_tag column still carries the dated tag (scorecards group on it)" "[ '$t1' = 'demo-20260922-widget' ] && [ '$t2' = 'demo-20260929-widget' ]"

# --- B: untagged item: the checkbox prefix must not change the identity ---
L3='- [ ] [T1] `b.py` — plain item with no feature tag. VERIFY: `true`.'
read -r h3 t3 <<<"$(rec "$L3")"
exp3="$(ovn_item_hash "$L3")"
ok "B1 recorded item_hash equals the shared ovn_item_hash() for an untagged item" "[ '$h3' = '$exp3' ]"
ok "B2 ...and equals the hash of the same text WITHOUT its leading checkbox" \
   "[ '$h3' = \"\$(ovn_item_hash '[T1] \`b.py\` — plain item with no feature tag. VERIFY: \`true\`.')\" ]"
ok "B3 untagged item has an empty feat_tag" "[ -z '${t3:-}' ]"

# --- C: different features / different items still get different identities ---
L4='- [ ] [T2] `a.py` — wire it up [feat:demo-20260922-other-feature]. VERIFY: `true`.'
read -r h4 t4 <<<"$(rec "$L4")"
ok "C1 a different feature slug gets a different item_hash" "[ '$h4' != '$h1' ]"
ok "C2 tagged vs untagged items get different item_hashes" "[ '$h3' != '$h1' ]"

echo "record_outcome item_hash agreement: $P passed, $F failed"
[ "$F" -eq 0 ]
