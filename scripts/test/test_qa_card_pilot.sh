#!/usr/bin/env bash
# test_qa_card_pilot.sh - shell side of the Phase 2 S0 card pilot: the S2 shadow hook in lib_auto_credit.sh (ovn_card_credit_shadow), its wiring into ovn_auto_credit,
# the OVN_QA_CARD_CREDIT flag, the cron proposal, tracked-executable/registration checks, lint_unsafe_rm on the new files, and a MUTANT (hook call removed).
# The python half (pilot run, caps, idle check, report, mutants) is test_qa_card_pilot.py (registered separately). Temp dirs only via lib_safe_tmp.sh.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
Q="$(cd "$HERE/../.." && pwd)"
. "$HERE/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
PY="${QA_TEST_PYTHON:-$(command -v python3.12 || command -v python3)}"
P=0; F=0
ok(){ if [ "$2" = 0 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
tmp="$(safe_mktemp_dir)" || { echo "  FAIL: cannot create a safe temp dir - aborting before touching anything"; exit 1; }
trap 'safe_rm_rf "$tmp"' EXIT

LIB="$Q/scripts/lib_auto_credit.sh"

echo "wiring"
n="$(grep -c 'ovn_card_credit_shadow "\$_ac_before_text" "\$after"' "$LIB")"
[ "$n" = 1 ]; ok "ovn_auto_credit calls the shadow hook exactly once, right after the tick (found $n)" $?
line="$(grep -n 'ovn_card_credit_shadow "\$_ac_before_text"' "$LIB" | head -1 | cut -d: -f1)"
sed -n "${line}p" "$LIB" | grep -q 'ovn_credit_twins'; ok "the hook sits inside the TICKED branch (same line as the twin credit)" $?
fnbody="$(awk '/^ovn_card_credit_shadow\(\)/,/^}/' "$LIB")"
printf '%s' "$fnbody" | grep -q 'OVN_QA_CARD_CREDIT:-shadow'; ok "default is shadow (OVN_QA_CARD_CREDIT:-shadow)" $?
printf '%s' "$fnbody" | grep -qiE 'enforce|reset|checkout|git (add|commit)|\bfail\b'; r=$?; [ "$r" != 0 ]; ok "the hook has no enforce/git-mutating path" $?
printf '%s' "$fnbody" | grep -q '200>&-'; ok "run.lock fd 200 is closed for the child" $?
grep -q 'card_pilot_run.py' "$Q/ops/cron.proposed.txt" && grep -qE '^# +35 3 \* \* \* .*card_pilot_run.py run' "$Q/ops/cron.proposed.txt"; ok "cron proposal present and COMMENTED OUT (off until Mark flips it)" $?
! grep -vE '^[[:space:]]*#' "$Q/ops/cron.proposed.txt" | grep -q card_pilot; ok "no ACTIVE cron line runs the pilot" $?
grep -q 'test_qa_card_pilot' "$HERE/run_all.sh"; ok "registered in run_all.sh" $?
[ "$(grep -c 'test_qa_card_pilot' "$HERE/run_all.sh")" -ge 2 ]; ok "both the .py and the .sh are registered" $?
"$PY" "$HERE/lint_unsafe_rm.py" "$Q/qa" "$LIB" "$HERE/test_qa_card_pilot.sh" "$HERE/test_qa_card_pilot.py" >/dev/null; ok "lint_unsafe_rm.py passes on the new files" $?

echo "hook behaviour (foreground variant, then the real detached one)"
REPOS="$tmp/repos"; REPO="test-automation-agent"; CLONE="$REPOS/$REPO"; STATE="$tmp/state"
mkdir -p "$CLONE/app" "$STATE/qa_shadow"
( cd "$CLONE" && git init -q -b develop && printf 'def existing():\n    return 1\n' > app/util.py && touch app/__init__.py \
  && git add -A && git -c user.name=t -c user.email=t@t commit -q -m base ) >/dev/null 2>&1
HEADSHA="$(git -C "$CLONE" rev-parse HEAD)"
ITEM='- [ ] [T2] app/util.py — Add `never_carded()` that returns 7'
CC="$STATE/qa_shadow/card_credit.jsonl"
runhook(){ env -i PATH="$PATH" HOME="$tmp" OVN_DIR="$tmp" OVN_REPOS_DIR="$REPOS" STATE_DIR="$STATE" "$@" bash -c 'cd "$1" && . "$2" && ovn_card_credit_shadow "$3" "$4"' _ "$CLONE" "$LIB" "$ITEM" "$HEADSHA"; }

runhook OVN_QA_CARD_CREDIT_SYNC=1; rc=$?
[ "$rc" = 0 ]; ok "hook returns 0" $?
[ -s "$CC" ] && grep -q '"credit_without_card": true' "$CC"; ok "shadow default: a card_credit row says credit_without_card (no card exists)" $?
grep -q '"mode": "shadow"' "$CC"; ok "row records mode shadow" $?
n0="$(wc -l < "$CC" | tr -d ' ')"
runhook OVN_QA_CARD_CREDIT_SYNC=1 OVN_QA_CARD_CREDIT=off
[ "$(wc -l < "$CC" | tr -d ' ')" = "$n0" ]; ok "OVN_QA_CARD_CREDIT=off: no row" $?
runhook OVN_QA_CARD_CREDIT_SYNC=1 OVN_QA_CARD_CREDIT=enforce; rc=$?
[ "$rc" = 0 ]; ok "an 'enforce' value changes nothing (still rc 0, no enforce path)" $?
n1="$(wc -l < "$CC" | tr -d ' ')"
runhook OVN_QA_CARD_CREDIT_SYNC=0
for _ in $(seq 1 100); do [ "$(wc -l < "$CC" | tr -d ' ')" -gt "$n1" ] && break; sleep 0.2; done
[ "$(wc -l < "$CC" | tr -d ' ')" -gt "$n1" ]; ok "the real (detached, niced) variant also logs, without blocking the caller" $?
# no state dir = nothing is created
NOSTATE="$tmp/nostate_home"; mkdir -p "$NOSTATE"
( cd "$CLONE" && env -i PATH="$PATH" HOME="$NOSTATE" bash -c ". '$LIB'; OVN_QA_CARD_CREDIT_SYNC=1 ovn_card_credit_shadow '$ITEM' '$HEADSHA'" ) >/dev/null 2>&1
[ ! -e "$NOSTATE/overnight-queue" ]; ok "with no state dir the hook creates nothing" $?
# a broken pilot never breaks the caller
( cd "$CLONE" && env -i PATH="/nonexistent" HOME="$tmp" STATE_DIR="$STATE" /bin/bash -c ". '$LIB'; OVN_QA_CARD_CREDIT_SYNC=1 ovn_card_credit_shadow '$ITEM' '$HEADSHA'; echo rc=\$?" ) 2>/dev/null | grep -q 'rc=0'; ok "python3 missing from PATH: still rc 0" $?

echo "mutant: hook call removed -> the wiring assertion must fail"
cp "$LIB" "$tmp/lib_mut.sh"
"$PY" - "$tmp/lib_mut.sh" <<'EOF'
import sys
p = sys.argv[1]
s = open(p).read()
old = ' ovn_card_credit_shadow "$_ac_before_text" "$after";'
assert s.count(old) == 1
open(p, "w").write(s.replace(old, ""))
EOF
n="$(grep -c 'ovn_card_credit_shadow "\$_ac_before_text" "\$after"' "$tmp/lib_mut.sh")"
[ "$n" != 1 ]; ok "[mutant] with the call removed the 'exactly once' assertion would fail (found $n)" $?
bash -n "$LIB"; ok "lib_auto_credit.sh still parses" $?

echo "test_qa_card_pilot.sh: $P passed, $F failed"
[ "$F" -eq 0 ]
