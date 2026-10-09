#!/usr/bin/env bash
# 2026-10-09 (harness-credit-integrity item 4): outcome class `landed-uncredited` - a green push (status pushed(tests:pass)) whose item the auto-credit REFUSED to tick.
# Before: such rows were class=landed/sev=good, so the item stayed [ ] and was re-faced (7 landings on routers/subscription.py, 29 'path mismatch' refusals / 24h).
# Covers record_outcome() (the REAL function extracted from run_overnight.sh), the lib_auto_credit.sh classifier, ovn_outcome_buckets.py, work_summary.py and
# ovn_landed_detail.py, plus mutation controls. Log fixtures are cut from the real task_log line shapes (lib_auto_credit.sh `_ovn_ac_log`).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
Q="$(cd "$HERE/../.." && pwd)"
R="$Q/run_overnight.sh"; LIB="$Q/scripts/lib_auto_credit.sh"
P=0; F=0
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
# shellcheck disable=SC1090
source "$LIB" 2>/dev/null
FN_SRC="$(sed -n '/^record_outcome(/,/^}/p' "$R")"
[ -n "$FN_SRC" ] || { echo "  FAIL: could not extract record_outcome() from $R"; exit 1; }
eval "$FN_SRC"
SCRIPT_DIR="$Q"; STATE_DIR="$tmp/state"; mkdir -p "$STATE_DIR"

# ---- fixtures (task_log shapes) ----
MARK='--- landing: bookkeeping + auto-credit + push phase ---'
mk(){ printf '%s\n' "$@"; }
mk 'aider noise' "$MARK" '--- auto-credit: REFUSED line 12 - item names iptv-backend/app/routers/subscription.py (=iptv-backend/app/models/subscription.py), the commit touched iptv-backend/app/routers/subscription.py: path mismatch ---' > "$tmp/refused.log"
mk 'aider noise' "$MARK" '--- auto-credit: REFUSED line 12 (a.py) - item has no VERIFY: clause, so there is nothing to prove it is done ---' > "$tmp/noverify_prefixed.log"
mk 'aider noise' "$MARK" 'item has no VERIFY: clause' > "$tmp/noverify_bare.log"
mk 'aider noise' "$MARK" '--- auto-credit: REFUSED line 3 (b.py) - the item'"'"'s own VERIFY: clause FAILED ---' '--- auto-credit: VERIFY passed for line 5 (a.py) ---' '--- auto-credit: checked off line 5 (green change touched its named file and its VERIFY passed) ---' > "$tmp/refused_and_credited.log"
mk 'aider noise' "$MARK" '--- auto-credit: item-hash 0123abcd ---' > "$tmp/credited_hash.log"
mk 'attempt 1' "$MARK" '--- auto-credit: REFUSED line 2 - placeholder ---' 'attempt 2 reverted' "$MARK" 'clean second landing, nothing to credit' > "$tmp/old_attempt_refusal.log"
mk 'stage runner output' 'commits_pushed: 2' '--- auto-credit: REFUSED line 9 - path mismatch ---' > "$tmp/nomarker_refused.log"
mk 'no credit lines at all' "$MARK" > "$tmp/plain.log"

row(){  # $1=status $2=log -> prints "class|severity" of the one outcomes row
  : > "$STATE_DIR/outcomes.jsonl"
  record_outcome "id1" repo "$1" "" aider_fix 1 "$2" 5 "" "" 2>/dev/null
  jq -r '.class + "|" + .severity' "$STATE_DIR/outcomes.jsonl" 2>/dev/null | head -1
}
ok "pushed(tests:pass) + 'path mismatch' REFUSED after the landing marker => landed-uncredited|neutral" "[ \"\$(row 'pushed(tests:pass)' '$tmp/refused.log')\" = 'landed-uncredited|neutral' ]"
ok "pushed(tests:pass) + 'REFUSED ... item has no VERIFY: clause' => landed-uncredited" "[ \"\$(row 'pushed(tests:pass)' '$tmp/noverify_prefixed.log')\" = 'landed-uncredited|neutral' ]"
ok "pushed(tests:pass) + bare 'item has no VERIFY: clause' line => landed-uncredited" "[ \"\$(row 'pushed(tests:pass)' '$tmp/noverify_bare.log')\" = 'landed-uncredited|neutral' ]"
ok "REFUSED for one file but ANOTHER item was credited ('checked off line') => landed|good" "[ \"\$(row 'pushed(tests:pass)' '$tmp/refused_and_credited.log')\" = 'landed|good' ]"
ok "credited via the item-hash marker => landed|good" "[ \"\$(row 'pushed(tests:pass)' '$tmp/credited_hash.log')\" = 'landed|good' ]"
ok "a refusal from an EARLIER best-of-N attempt (before the last landing marker) does not count => landed|good" "[ \"\$(row 'pushed(tests:pass)' '$tmp/old_attempt_refusal.log')\" = 'landed|good' ]"
ok "no marker in the log (stage runner path) + REFUSED => landed-uncredited (whole log is the segment)" "[ \"\$(row 'pushed(tests:pass) stage(higher-tier)' '$tmp/nomarker_refused.log')\" = 'landed-uncredited|neutral' ]"
ok "pushed(tests:pass) with no refusal at all => landed|good" "[ \"\$(row 'pushed(tests:pass)' '$tmp/plain.log')\" = 'landed|good' ]"
ok "a reverted status is untouched by the log's REFUSED line => reverted|bad" "[ \"\$(row 'reverted(tests-failed)' '$tmp/refused.log')\" = 'reverted|bad' ]"
ok "pushed(after-rebase) is not 'pushed(tests:pass)': stays landed|good" "[ \"\$(row 'pushed(after-rebase)' '$tmp/refused.log')\" = 'landed|good' ]"
ok "pushed(tests:FAIL - see log) is not rewritten either (landed|good, as before)" "[ \"\$(row 'pushed(tests:FAIL - see log)' '$tmp/refused.log')\" = 'landed|good' ]"
ok "missing / empty task log path => landed|good (never crashes)" "[ \"\$(row 'pushed(tests:pass)' /nonexistent/log)\" = 'landed|good' ]"
ok "kill switch OVN_LANDED_UNCREDITED=off => landed|good for the refused fixture" "[ \"\$(OVN_LANDED_UNCREDITED=off row 'pushed(tests:pass)' '$tmp/refused.log')\" = 'landed|good' ]"
ok "classifier alone: ovn_landed_uncredited rc 0 for the refused fixture, rc 1 for the credited one" "ovn_landed_uncredited '$tmp/refused.log' 'pushed(tests:pass)' && ! ovn_landed_uncredited '$tmp/credited_hash.log' 'pushed(tests:pass)'"

# ---- wiring in run_overnight.sh (anchored code lines) ----
ok "record_outcome calls ovn_landed_uncredited with the cycle log and the raw status" "[ \"\$(grep -c '^  if \\[ \"\$cls\" = landed \\] && declare -F ovn_landed_uncredited .*ovn_landed_uncredited \"\$tl\" \"\$3\"; then cls=\"landed-uncredited\"; sev=neutral; fi' '$R')\" = 1 ]"
ok "the runner writes the '--- landing:' segment marker exactly once, before bookkeeping/credit/push" "[ \"\$(grep -c '^      echo \"--- landing: bookkeeping + auto-credit + push phase ---\" >> \"\$task_log\"' '$R')\" = 1 ]"

# ---- MUTATION controls ----
python3 - "$LIB" "$tmp" <<'PY'
import sys
s = open(sys.argv[1]).read()
def mut(a, b, name):
    assert s.count(a) == 1, a
    open(sys.argv[2] + "/" + name, "w").write(s.replace(a, b))
mut('  if [ -n "$n" ]; then seg="$(tail -n +$((n + 1)) "$tl" 2>/dev/null)"; else seg="$(cat "$tl" 2>/dev/null)"; fi',
    '  seg="$(cat "$tl" 2>/dev/null)"', "m_noseg.sh")
mut('  [ "${credited:-0}" -eq 0 ]', '  true', "m_nocredit.sh")
mut('  [ "${refused:-0}" -gt 0 ] || return 1\n', '', "m_norefuse.sh")
PY
mrow(){ ( source "$1" 2>/dev/null; $2 ); }
ok "MUTATION: whole-log scan (no segment) misclassifies the old-attempt-refusal fixture as uncredited" "( source '$tmp/m_noseg.sh'; ovn_landed_uncredited '$tmp/old_attempt_refusal.log' 'pushed(tests:pass)' )"
ok "MUTATION: without the credited check the refused+credited fixture is misclassified as uncredited" "( source '$tmp/m_nocredit.sh'; ovn_landed_uncredited '$tmp/refused_and_credited.log' 'pushed(tests:pass)' )"
ok "MUTATION: without the refusal requirement the plain fixture is misclassified as uncredited" "( source '$tmp/m_norefuse.sh'; ovn_landed_uncredited '$tmp/plain.log' 'pushed(tests:pass)' )"
ok "MUTATION sanity: the unmutated lib gets all three fixtures right" "! ovn_landed_uncredited '$tmp/old_attempt_refusal.log' 'pushed(tests:pass)' && ! ovn_landed_uncredited '$tmp/refused_and_credited.log' 'pushed(tests:pass)' && ! ovn_landed_uncredited '$tmp/plain.log' 'pushed(tests:pass)'"

# ---- ovn_outcome_buckets.py ----
B="$Q/scripts"
bk(){ python3 -c "
import sys, json
sys.path.insert(0, '$B')
import ovn_outcome_buckets as b
$1"; }
ok "bucket_from_outcome_row: landed-uncredited (neutral) => benign" "[ \"\$(bk \"print(b.bucket_from_outcome_row({'class':'landed-uncredited','severity':'neutral'}))\")\" = benign ]"
ok "bucket_from_outcome_row: landed-uncredited stays benign even if a stale severity says good" "[ \"\$(bk \"print(b.bucket_from_outcome_row({'class':'landed-uncredited','severity':'good'}))\")\" = benign ]"
ok "bucket_from_outcome_row: landed-uncredited with no severity => benign" "[ \"\$(bk \"print(b.bucket_from_outcome_row({'class':'landed-uncredited'}))\")\" = benign ]"
ok "control: a normal landed row is still good" "[ \"\$(bk \"print(b.bucket_from_outcome_row({'class':'landed','severity':'good'}))\")\" = good ]"
ok "pass rate excludes uncredited rows: 1 good + 1 bad + 3 uncredited => 50.0" "[ \"\$(bk \"rows=[{'class':'landed','severity':'good'},{'class':'reverted','severity':'bad'}]+[{'class':'landed-uncredited','severity':'neutral'}]*3; print(b.pass_rate([b.bucket_from_outcome_row(r) for r in rows]))\")\" = 50.0 ]"
ok "count_uncredited / uncredited_label: 3 rows => '3 uncredited pushes', 1 => '1 uncredited push', 0 => ''" "[ \"\$(bk \"r=[{'class':'landed-uncredited'}]*3; print(b.uncredited_label(b.count_uncredited(r)) + '|' + b.uncredited_label(1) + '|' + repr(b.uncredited_label(0)))\")\" = \"3 uncredited pushes|1 uncredited push|''\" ]"

# ---- work_summary.py ----
NOW="$(date -u +%FT%TZ)"
{ for c in landed landed landed-uncredited landed-uncredited landed-uncredited reverted; do printf '{"ts":"%s","repo":"iptv_apps","class":"%s","tier":"2"}\n' "$NOW" "$c"; done; } > "$tmp/outcomes_ws.jsonl"
WS="$(cd "$tmp" && OUTCOMES="$tmp/outcomes_ws.jsonl" OVN_LANDED_DETAIL_SCRIPT=/nonexistent python3 "$Q/work_summary.py" 24)"
ok "work_summary: headline counts only real landings and appends '3 uncredited pushes'" "case \"\$WS\" in *'2 landed · 1 reverted'*'3 uncredited pushes'*) true;; *) false;; esac"
printf '{"ts":"%s","repo":"iptv_apps","class":"landed","tier":"2"}\n' "$NOW" > "$tmp/outcomes_ws0.jsonl"
WS0="$(cd "$tmp" && OUTCOMES="$tmp/outcomes_ws0.jsonl" OVN_LANDED_DETAIL_SCRIPT=/nonexistent python3 "$Q/work_summary.py" 24)"
ok "work_summary: no uncredited rows => no 'uncredited' text (control)" "case \"\$WS0\" in *uncredited*) false;; *) true;; esac"

# ---- ovn_landed_detail.py ----
EPOCH="$(date +%s)"
printf '%s\tiptv_apps\tpass\t{python.endpoint.T2.verified}\tapp/routers/x.py\n' "$EPOCH" > "$tmp/task_stats.log"
{ for i in 1 2; do printf '{"ts":"%s","repo":"iptv_apps","class":"landed-uncredited"}\n' "$NOW"; done; printf '{"ts":"2020-01-01T00:00:00Z","repo":"xlite","class":"landed-uncredited"}\n'; } > "$tmp/outcomes.jsonl"
LD="$(TASK_STATS="$tmp/task_stats.log" OUTCOMES="$tmp/outcomes.jsonl" python3 "$Q/scripts/ovn_landed_detail.py" 3)"
ok "landed_detail: the landed line is shown and followed by '2 uncredited pushes' (the 2020 row is outside the window)" "case \"\$LD\" in *'app/routers/x.py'*'2 uncredited pushes'*'iptv_apps 2'*) true;; *) false;; esac"
: > "$tmp/task_stats_empty.log"
LD2="$(TASK_STATS="$tmp/task_stats_empty.log" OUTCOMES="$tmp/outcomes.jsonl" python3 "$Q/scripts/ovn_landed_detail.py" 3)"
ok "landed_detail: no landed rows but uncredited pushes => only the uncredited line (no empty header)" "case \"\$LD2\" in *'2 uncredited pushes'*) case \"\$LD2\" in *'Landed detail'*) false;; *) true;; esac;; *) false;; esac"
LD3="$(TASK_STATS="$tmp/task_stats_empty.log" OUTCOMES="$tmp/nonexistent.jsonl" python3 "$Q/scripts/ovn_landed_detail.py" 3)"
ok "landed_detail: nothing at all => empty output (control)" "[ -z \"\$LD3\" ]"
echo "$P passed, $F failed"; [ "$F" -eq 0 ]
