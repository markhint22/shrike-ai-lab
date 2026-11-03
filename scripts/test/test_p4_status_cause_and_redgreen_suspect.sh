#!/usr/bin/env bash
# 2026-11-02 (P4 / outcomes F5 + F1 pipeline part):
#  F5  bucket reports group by STATUS, where 56 of 78 noops read 'no-op(stage-unverified) stage(higher-tier)' with the real cause only in fail_reason. ovn_stage_status_cause appends
#      ' cause:<tag>' (OVN_STAGE_FAILTAG_STATUS=on); default SHADOW leaves the status alone and logs the would-be status; the classifier prefix is untouched.
#  F1  red-green SUSPECT (the gitlark error-reporting cycle: new tests passed WITHOUT the fix, class landed-uncredited only by luck of a failing VERIFY) is tag-only today. New
#      OVN_REDGREEN_SUSPECT=shadow|enforce|off (default shadow): enforce makes the runner skip the credit and write an 'auto-credit: REFUSED' marker => ovn_landed_uncredited => not "landed".
# Mutation proof: the same assertions against copies of the lib/runner with the logic broken must go red.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"; S="$HERE/.."; ROOT="$(cd "$S/.." && pwd)"
. "$HERE/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
export TZ=UTC NTFY_SERVER=http://127.0.0.1:9
P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
tmp="$(safe_mktemp_dir)" || exit 1; trap 'safe_rm_rf "$tmp"' EXIT
LIB="$S/lib_p4_outcomes.sh"; RUNNER="$ROOT/run_overnight.sh"
ST='no-op(stage-unverified) stage(higher-tier)'
run(){ ( export OVN_P4_STATE_DIR="$tmp/state"; unset OVN_STAGE_FAILTAG_STATUS OVN_REDGREEN_SUSPECT; for kv in "${@:2}"; do export "$kv"; done; . "${LIBX:-$LIB}"; eval "$1" ); }

# ---- F5
ok "C1 default (shadow): the status text is unchanged" "[ \"\$(run 'ovn_stage_status_cause test-red \"$ST\"')\" = '$ST' ]"
ok "C2 default (shadow): the would-be status is logged" "grep -q 'would=no-op(stage-unverified) stage(higher-tier) cause:test-red' '$tmp/state/stage_status_tag_shadow.log'"
ok "C3 on: cause appended after stage(higher-tier)" "[ \"\$(run 'ovn_stage_status_cause no-edit \"$ST\"' OVN_STAGE_FAILTAG_STATUS=on)\" = 'no-op(stage-unverified) stage(higher-tier) cause:no-edit' ]"
ok "C4 on: a trailing bug-handled stays last and the classifier prefix is intact" "o=\"\$(run 'ovn_stage_status_cause timeout \"$ST\"; echo \" bug-handled\"' OVN_STAGE_FAILTAG_STATUS=on)\"; case \"\$o\" in 'no-op(stage-unverified) stage(higher-tier) cause:timeout bug-handled') true;; *) false;; esac"
ok "C5 on: the status still matches the glob every classifier uses" "case \"\$(run 'ovn_stage_status_cause test-red \"$ST\"' OVN_STAGE_FAILTAG_STATUS=on)\" in *'no-op(stage-unverified)'*) true;; *) false;; esac"
ok "C6 off: unchanged and silent" "rm -f '$tmp/state/stage_status_tag_shadow.log'; [ \"\$(run 'ovn_stage_status_cause test-red \"$ST\"' OVN_STAGE_FAILTAG_STATUS=off)\" = '$ST' ] && [ ! -e '$tmp/state/stage_status_tag_shadow.log' ]"
ok "C7 an empty / bare stage-unverified tag adds nothing" "[ \"\$(run 'ovn_stage_status_cause \"\" \"$ST\"' OVN_STAGE_FAILTAG_STATUS=on)\" = '$ST' ] && [ \"\$(run 'ovn_stage_status_cause stage-unverified \"$ST\"' OVN_STAGE_FAILTAG_STATUS=on)\" = '$ST' ]"
ok "C8 a status that is not the higher-tier one is untouched" "[ \"\$(run 'ovn_stage_status_cause test-red \"pushed(tests:pass)\"' OVN_STAGE_FAILTAG_STATUS=on)\" = 'pushed(tests:pass)' ]"
ok "C9 the runner passes the cause through the helper for both statuses" "[ \"\$(grep -c 'ovn_stage_status_cause \"\${_sft:-}\"' '$RUNNER')\" = 2 ]"
sed 's/^  local new="\${st\/"stage(higher-tier)"\/"stage(higher-tier) cause:\${tag}"}"/  local new="$st"/' "$LIB" > "$tmp/lib_mut1.sh"
ok "C10 mutant lib differs" "! cmp -s '$LIB' '$tmp/lib_mut1.sh'"
ok "C10 MUTANT (cause never inserted): C3 goes red" "[ \"\$(LIBX='$tmp/lib_mut1.sh' run 'ovn_stage_status_cause no-edit \"$ST\"' OVN_STAGE_FAILTAG_STATUS=on)\" != 'no-op(stage-unverified) stage(higher-tier) cause:no-edit' ]"

# ---- F1 red-green suspect
ok "R1 default (shadow): rc 1 (credit proceeds as today)" "! run 'ovn_redgreen_suspect_policy /nonexistent id1 gitlark'"
ok "R2 default (shadow): a row says what enforce would do" "grep -q 'gitlark.*id=id1.*would skip the credit' '$tmp/state/redgreen_suspect_shadow.log'"
ok "R3 enforce: rc 0 (skip credit)" "run 'ovn_redgreen_suspect_policy /nonexistent id1 gitlark' OVN_REDGREEN_SUSPECT=enforce"
ok "R4 off: rc 1 and silent" "rm -f '$tmp/state/redgreen_suspect_shadow.log'; ! run 'ovn_redgreen_suspect_policy /nonexistent id1 gitlark' OVN_REDGREEN_SUSPECT=off && [ ! -e '$tmp/state/redgreen_suspect_shadow.log' ]"
ok "R5 the runner calls the policy inside the SUSPECT block and skips every credit path" "awk '/REDGREEN\" = \"suspect\" \]; then/{f=1} f&&/ovn_redgreen_suspect_policy/{p=1} f&&p&&/_skip_credit=1; _rg_refuse=1/{print \"yes\"; exit}' '$RUNNER' | grep -q yes"
ok "R6 the REFUSED marker is written AFTER the landing marker (inside the segment ovn_landed_uncredited reads)" "awk '/--- landing: bookkeeping/{l=NR} /_rg_refuse:-0/{m=NR} END{exit !(l && m && m==l+1)}' '$RUNNER'"
# end-to-end of the class decision: the marker makes a pushed(tests:pass) cycle landed-uncredited; without it the row is a landing
: > "$tmp/tl.log"
{ echo "--- red-green SUSPECT ---"; echo "--- landing: bookkeeping + auto-credit + push phase ---"; echo "--- auto-credit: REFUSED - red-green SUSPECT: the new test(s) passed without the fix (OVN_REDGREEN_SUSPECT=enforce); nothing credited ---"; } > "$tmp/tl.log"
ok "R7 with the marker: pushed(tests:pass) => landed-uncredited" "( . '$S/lib_auto_credit.sh' 2>/dev/null; ovn_landed_uncredited '$tmp/tl.log' 'pushed(tests:pass) [redgreen:SUSPECT]' )"
{ echo "--- landing: bookkeeping + auto-credit + push phase ---"; } > "$tmp/tl2.log"
ok "R8 control: without the marker (shadow) the push is a plain landing" "( . '$S/lib_auto_credit.sh' 2>/dev/null; ! ovn_landed_uncredited '$tmp/tl2.log' 'pushed(tests:pass) [redgreen:SUSPECT]' )"
sed 's/    enforce) return 0 ;;/    enforce) return 1 ;;/' "$LIB" > "$tmp/lib_mut2.sh"
ok "R9 mutant lib differs" "! cmp -s '$LIB' '$tmp/lib_mut2.sh'"
ok "R9 MUTANT (enforce never skips): R3 goes red" "! LIBX='$tmp/lib_mut2.sh' run 'ovn_redgreen_suspect_policy /nonexistent id1 gitlark' OVN_REDGREEN_SUSPECT=enforce"
echo "  $P passed, $F failed"; [ "$F" = 0 ]
