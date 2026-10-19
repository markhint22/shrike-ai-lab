#!/usr/bin/env bash
# 2026-10-18 (package D4, outcome accounting). Pins the three pieces, each with MUTANTS (a deliberately broken copy of the code must make the matching assertion fail):
#   A. record_outcome() stamps commits / head_before / head_after on every row (old 9/10-arg callers still produce valid rows).
#   B. the bounded verify-timeout hold (scripts/lib_outcome_acct.sh): off|shadow|enforce, default shadow, bounded by count and hours, zero-failing-id requirement.
#   C. the hold wired into run_overnight.sh (the real block extracted and run) and its status classification (held / neutral / verify-timeout).
#   D. scripts/ovn_outcome_acct.py reconcile: a held commit that reaches origin later becomes ONE landed-late row (idempotent, partial landings wait, landing rows ignored).
#   E. old-format rows (no commits field) and landed-late rows still parse in ovn_outcome_buckets / ovn_real_passrate / ovn_stats / cycle_walltime / qa_ledger.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
R="${OVN_RUNNER:-$ROOT/run_overnight.sh}"
LIB="$ROOT/scripts/lib_outcome_acct.sh"; RILIB="$ROOT/scripts/lib_run_integrity.sh"; ACCT="$ROOT/scripts/ovn_outcome_acct.py"; BUCKETS="$ROOT/scripts/ovn_outcome_buckets.py"
for f in "$R" "$LIB" "$RILIB" "$ACCT"; do [ -f "$f" ] || { echo "  SKIP: $f not found on this host"; exit 0; }; done
PY="${QA_TEST_PYTHON:-$(command -v python3.12 || command -v python3)}"
P=0; F=0
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }
nok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then F=$((F+1)); echo "  FAIL(expected-false): $1"; else P=$((P+1)); fi; }
tmp="$(safe_mktemp_dir d4acct)" || exit 1; trap 'rm -rf "$tmp"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
mutate(){ # <src> <old> <new> <out>: write a mutant copy; FAIL the whole suite loudly when <old> is not present exactly once (a mutant that changes nothing proves nothing)
  "$PY" - "$1" "$2" "$3" "$4" <<'EOF' || { F=$((F+1)); echo "  FAIL: mutant anchor not found: $2"; return 1; }
import sys
src, old, new, out = sys.argv[1:5]
s = open(src).read()
if s.count(old) != 1:
    sys.exit(1)
open(out, "w").write(s.replace(old, new))
EOF
}

# ============================== A. record_outcome commit fields ==============================
rd="$tmp/repoA"; mkdir -p "$rd"; git -C "$rd" init -q -b main
for n in 0 1 2; do echo "$n" > "$rd/f$n"; git -C "$rd" add -A; git -C "$rd" commit -q -m "c$n"; eval "c$n=$(git -C "$rd" rev-parse HEAD)"; done
rec_row(){ # <runner> <lib> [args to record_outcome...] -> the one row written (subshell: nothing leaks)
  local runner="$1" lib="$2"; shift 2
  (
    SCRIPT_DIR="$ROOT"; STATE_DIR="$tmp/stateA.$RANDOM"; mkdir -p "$STATE_DIR"
    # shellcheck source=/dev/null
    [ "$lib" != none ] && source "$lib"
    eval "$(sed -n '/^record_outcome(/,/^}/p' "$runner")"
    record_outcome "$@"
    cat "$STATE_DIR/outcomes.jsonl"
  )
}
rowq(){ printf '%s' "$1" | "$PY" -c "import json,sys; r=json.loads(sys.stdin.read()); print($2)"; }
RA="$(rec_row "$R" "$LIB" a1 repoA "pushed(tests:pass)" "" aider_fix 1 /dev/null 3600 "$rd" "" "$c0" "$c2")"
ok "A1 landing: commits = the two cycle commits, oldest first" "[ \"\$(rowq '$RA' 'r[\"commits\"]')\" = \"['$c1', '$c2']\" ]"
ok "A1 head_before / head_after recorded" "[ \"\$(rowq '$RA' 'r[\"head_before\"]+r[\"head_after\"]')\" = '$c0$c2' ]"
ok "A1 legacy fields untouched (class landed, severity good, status, item_hash key present)" "[ \"\$(rowq '$RA' '(r[\"class\"],r[\"severity\"],r[\"status\"],\"item_hash\" in r)')\" = \"('landed', 'good', 'pushed(tests:pass)', True)\" ]"
RB="$(rec_row "$R" "$LIB" a2 repoA "no-op(reverted-red)" "" aider_fix 1 /dev/null 5 "$rd" "" "$c1" "$c1")"
ok "A2 revert (head_after == head_before): commits = []" "[ \"\$(rowq '$RB' 'r[\"commits\"]')\" = '[]' ]"
RC="$(rec_row "$R" "$LIB" a3 repoA "skip(exhausted)" "" aider_fix 1 /dev/null 5 "$rd")"
ok "A3 legacy 9-arg call: valid row, head_after defaults to the repo HEAD, commits = [] (no base known)" "[ \"\$(rowq '$RC' '(r[\"commits\"], r[\"head_after\"]==\"$c2\", r[\"head_before\"])')\" = \"([], True, '')\" ]"
RD="$(rec_row "$R" "$LIB" a4 repoA "pushed(tests:pass)" "" aider_fix 1 /dev/null 5 "$rd" "" 'zz;rm -rf /' "$c2")"
ok "A4 a non-sha head_before is sanitised away (never reaches git as a revision): commits = []" "[ \"\$(rowq '$RD' 'r[\"commits\"]')\" = '[]' ]"
RE="$(rec_row "$R" none a5 repoA "pushed(tests:pass)" "" aider_fix 1 /dev/null 3600 "$rd" "" "$c0" "$c2")"
ok "A5 lib not loaded (partial deploy): the row is still valid JSON with commits = [] (fail-safe)" "[ \"\$(rowq '$RE' 'r[\"commits\"]')\" = '[]' ]"
BIG="$tmp/repoBig"; mkdir -p "$BIG"; git -C "$BIG" init -q -b main; echo 0 > "$BIG/f"; git -C "$BIG" add -A; git -C "$BIG" commit -q -m base; b0="$(git -C "$BIG" rev-parse HEAD)"
for n in $(seq 1 25); do echo $n >> "$BIG/f"; git -C "$BIG" commit -q -am "k$n"; done
RF="$(rec_row "$R" "$LIB" a6 repoA "pushed(tests:pass)" "" aider_fix 1 /dev/null 5 "$BIG" "" "$b0" "$(git -C "$BIG" rev-parse HEAD)")"
ok "A6 the commit list is capped (25 commits -> 20)" "[ \"\$(rowq '$RF' 'len(r[\"commits\"])')\" = 20 ]"
# mutants
mutate "$R" 'item_hash:$item_hash,feat_tag:$feat_tag,commits:$commits,head_before:$head_before,head_after:$head_after}' 'item_hash:$item_hash,feat_tag:$feat_tag,head_before:$head_before,head_after:$head_after}' "$tmp/mut_run1.sh" \
  && { M="$(rec_row "$tmp/mut_run1.sh" "$LIB" m1 repoA "pushed(tests:pass)" "" aider_fix 1 /dev/null 3600 "$rd" "" "$c0" "$c2" 2>/dev/null)"; nok "MUTANT jq row without commits is caught by A1" "[ \"\$(rowq '$M' 'r.get(\"commits\")')\" = \"['$c1', '$c2']\" ]"; }
mutate "$LIB" 'out="$(git -C "$rd" rev-list --reverse --max-count="$cap" "$a" --not "$b" 2>/dev/null)"' 'out="$(git -C "$rd" rev-list --reverse --max-count="$cap" "$a" 2>/dev/null)"' "$tmp/mut_lib1.sh" \
  && nok "MUTANT commit list ignoring head_before (legacy no-since path) is caught" "[ \"\$(bash -c 'source \"$tmp/mut_lib1.sh\"; ovn_oa_commits \"$rd\" \"$c0\" \"$c2\"' | '$PY' -c 'import json,sys; print(len(json.load(sys.stdin)))')\" = 2 ]"
mutate "$LIB" '--format='"'"'%H %at'"'"' "$a" --not "$b"' '--format='"'"'%H %at'"'"' "$a"' "$tmp/mut_lib1b.sh" \
  && { M="$(rec_row "$R" "$tmp/mut_lib1b.sh" m2b repoA "pushed(tests:pass)" "" aider_fix 1 /dev/null 3600 "$rd" "" "$c0" "$c2" 2>/dev/null)"; nok "MUTANT commit list (since path) ignoring head_before (whole history) is caught by A1" "[ \"\$(rowq '$M' 'r[\"commits\"]')\" = \"['$c1', '$c2']\" ]"; }

# ============================== B. bounded verify-timeout hold (lib) ==============================
L124="$tmp/pure124.log";  printf -- '--- verify-suite-red: repo-script in . rc=124 ---\n' > "$L124"
LMIX="$tmp/mixed.log";    printf -- '--- verify-suite-red: repo-script in . rc=124 ---\n--- verify-suite-red: gradle in android rc=1 ---\n' > "$LMIX"
LIDS="$tmp/ids.log";      printf -- 'FAILED tests/test_x.py::test_a - assert 1 == 2\n--- verify-suite-red: repo-script in . rc=124 ---\n' > "$LIDS"
LRED="$tmp/red.log";      printf -- '--- verify-suite-red: repo-script in . rc=1 ---\nFAILED tests/test_x.py::test_a\n1 failed, 3 passed in 4.00s\n' > "$LRED"
LDOT="$tmp/dot.log";      printf -- 'tests/test_x.py ..F.                  [ 50%%]\n--- verify-suite-red: repo-script in . rc=124 ---\n' > "$LDOT"
LDOT2="$tmp/dot2.log";    printf -- '...F..E......   [ 20%%]\n--- verify-suite-red: repo-script in . rc=124 ---\n' > "$LDOT2"
LJEST="$tmp/jest.log";    printf -- ' FAIL  src/a.test.ts\n--- verify-suite-red: repo-script in . rc=124 ---\n' > "$LJEST"
LGOOD="$tmp/good.log";    printf -- 'tests/test_x.py ......                [ 50%%]\n--- verify-suite-red: repo-script in . rc=124 ---\n' > "$LGOOD"
LGUT="$tmp/gut.log";      printf -- '--- GUT-FAIL-ID: res://tests/test_a.gd::test_x ---\n--- verify-suite-red: repo-script in . rc=124 ---\n' > "$LGUT"
LNONE="$tmp/none.log";    printf -- 'no verify marker here\n' > "$LNONE"
vt(){ # <lib> <state> <log> <offset> <before> [ENV=val ...] -> "<verdict> <count> <base>"
  local lib="$1" st="$2" log="$3" off="$4" before="$5"; shift 5
  ( env "$@" bash -c 'source "$1"; source "$2"; ovn_vt_decide "$3" r1 "$4" "$5" "$6"; printf "%s %s %s" "$OVN_VT_VERDICT" "$OVN_VT_COUNT" "$OVN_VT_BASE"' _ "$RILIB" "$lib" "$st" "$log" "$off" "$before" )
}
suiteB(){ # <lib> -> prints one line per failed expectation (empty = all hold)
  local lib="$1" s v o; s="$tmp/stB.$RANDOM"; mkdir -p "$s"
  v="$(vt "$lib" "$s" "$L124" 0 base1)";                                  [ "${v%% *}" = shadow-hold ] || echo "default mode must be shadow, got: $v"
  [ ! -e "$s/verify_timeout_holds/r1.state" ] || echo "shadow must not write the enforce state"
  [ "$(cut -d' ' -f1 "$s/verify_timeout_holds/r1.state.shadow" 2>/dev/null)" = 1 ] || echo "shadow must persist its OWN counter (r1.state.shadow)"
  v="$(vt "$lib" "$s" "$L124" 0 base1 OVN_VERIFY_TIMEOUT_HOLD=off)";       [ "${v%% *}" = off ] || echo "off must stay off, got: $v"
  v="$(vt "$lib" "$s" "$L124" 0 base1 OVN_VERIFY_TIMEOUT_HOLD=bogus)";     [ "${v%% *}" = shadow-hold ] || echo "a typo must never enforce, got: $v"
  v="$(vt "$lib" "$s" "$LMIX" 0 base1 OVN_VERIFY_TIMEOUT_HOLD=enforce)";   [ "${v%% *}" = not-timeout ] || echo "a mixed rc=124 + rc=1 verify is NOT a pure timeout, got: $v"
  v="$(vt "$lib" "$s" "$LIDS" 0 base1 OVN_VERIFY_TIMEOUT_HOLD=enforce)";   [ "${v%% *}" = not-timeout ] || echo "rc=124 WITH a failing test id must revert as before, got: $v"
  v="$(vt "$lib" "$s" "$LRED" 0 base1 OVN_VERIFY_TIMEOUT_HOLD=enforce)";   [ "${v%% *}" = not-timeout ] || echo "an ordinary red (rc=1) must revert as before, got: $v"
  v="$(vt "$lib" "$s" "$LNONE" 0 base1 OVN_VERIFY_TIMEOUT_HOLD=enforce)";  [ "${v%% *}" = not-timeout ] || echo "no marker at all is not a timeout, got: $v"
  v="$(vt "$lib" "$s" "$L124" 9999 base1 OVN_VERIFY_TIMEOUT_HOLD=enforce)"; [ "${v%% *}" = not-timeout ] || echo "an rc=124 marker BEFORE the verify offset must not count, got: $v"
  v="$(vt "$lib" "$s" "$LDOT" 0 base1 OVN_VERIFY_TIMEOUT_HOLD=enforce)";   [ "${v%% *}" = not-timeout ] || echo "rc=124 after pytest progress dots with an F is NOT a pure timeout, got: $v"
  v="$(vt "$lib" "$s" "$LDOT2" 0 base1 OVN_VERIFY_TIMEOUT_HOLD=enforce)";  [ "${v%% *}" = not-timeout ] || echo "rc=124 after an xdist F/E progress line is NOT a pure timeout, got: $v"
  v="$(vt "$lib" "$s" "$LJEST" 0 base1 OVN_VERIFY_TIMEOUT_HOLD=enforce)";  [ "${v%% *}" = not-timeout ] || echo "rc=124 after a jest/vitest FAIL line is NOT a pure timeout, got: $v"
  v="$(vt "$lib" "$s" "$LGUT" 0 base1 OVN_VERIFY_TIMEOUT_HOLD=enforce)";   [ "${v%% *}" = not-timeout ] || echo "rc=124 after a GUT failing id is NOT a pure timeout, got: $v"
  v="$(vt "$lib" "$s" "$LGOOD" 0 base1 OVN_VERIFY_TIMEOUT_HOLD=enforce)";  [ "${v%% *}" = hold ] || echo "rc=124 after all-green progress dots IS a pure timeout, got: $v"
  rm -f "$s/verify_timeout_holds/r1.state"
  v="$( env OVN_VERIFY_TIMEOUT_HOLD=enforce bash -c 'source "$1"; ovn_vt_decide "$2" r1 "$3" 0 base1; printf "%s" "$OVN_VT_VERDICT"' _ "$lib" "$s" "$L124" )"; [ "$v" = not-timeout ] || echo "without the failing-id parser the classifier must fail CLOSED (no hold), got: $v"
  # shadow persists its counter, so its bound/escalate path is observable: holds 1,2,3 then would-ESCALATE (count stays 3, state cleared), then a fresh streak
  local ss="$tmp/stBS.$RANDOM" seq="" i; mkdir -p "$ss"
  for i in 1 2 3 4 5; do v="$(vt "$lib" "$ss" "$L124" 0 b$i OVN_VERIFY_TIMEOUT_HOLD=shadow)"; seq="$seq $(echo "$v" | cut -d' ' -f1,2 | tr ' ' ':')"; done
  [ "$seq" = " shadow-hold:1 shadow-hold:2 shadow-hold:3 shadow-hold:3 shadow-hold:1" ] || echo "shadow must count 1,2,3, escalate (3), restart (1); got:$seq"
  [ ! -e "$ss/verify_timeout_holds/r1.state" ] || echo "shadow must never create the enforce streak"
  o="OVN_VERIFY_TIMEOUT_HOLD=enforce"
  v="$(vt "$lib" "$s" "$L124" 0 base1 $o)"; [ "$v" = "hold 1 base1" ] || echo "enforce hold 1 expected, got: $v"
  v="$(vt "$lib" "$s" "$L124" 0 base2 $o)"; [ "$v" = "hold 2 base1" ] || echo "enforce hold 2 must keep the streak base, got: $v"
  v="$(vt "$lib" "$s" "$L124" 0 base3 $o)"; [ "$v" = "hold 3 base1" ] || echo "enforce hold 3 expected, got: $v"
  v="$(vt "$lib" "$s" "$L124" 0 base4 $o)"; [ "${v%% *}" = escalate ] || echo "the 4th hold must ESCALATE (max 3), got: $v"
  [ "${v##* }" = base1 ] || echo "escalate must name the streak base (base1), got: $v"
  v="$(vt "$lib" "$s" "$L124" 0 base5 $o)"; [ "$v" = "hold 1 base5" ] || echo "after an escalation the next timeout starts a fresh streak, got: $v"
  vt "$lib" "$s" "$L124" 0 b OVN_VERIFY_TIMEOUT_HOLD=shadow >/dev/null
  [ "$(cut -d' ' -f1 "$s/verify_timeout_holds/r1.state" 2>/dev/null)" = 1 ] || echo "shadow must not touch an existing streak"
  # hour bound: a streak whose first hold is older than OVN_VT_HOLD_MAX_HOURS escalates even below the count cap
  local now; now="$(date +%s)"; mkdir -p "$s/verify_timeout_holds"; printf '1 %s %s old\n' "$((now - 8*3600))" "$((now - 60))" > "$s/verify_timeout_holds/r1.state"
  v="$(vt "$lib" "$s" "$L124" 0 b $o)"; [ "${v%% *}" = escalate ] || echo "a 8h-old streak must escalate (6h cap), got: $v"
  # idle reset: no hold for >12h starts fresh even at the count cap
  printf '3 %s %s old\n' "$((now - 30*3600))" "$((now - 13*3600))" > "$s/verify_timeout_holds/r1.state"
  v="$(vt "$lib" "$s" "$L124" 0 b9 $o)"; [ "$v" = "hold 1 b9" ] || echo "an idle (13h) streak must reset, got: $v"
  # a hold that cannot be bounded (state dir unwritable) must never happen
  : > "$tmp/notadir.$$"; v="$(vt "$lib" "$tmp/notadir.$$" "$L124" 0 b $o)"; [ "${v%% *}" = not-timeout ] || echo "unwritable state => no hold, got: $v"
  ( source "$RILIB"; source "$lib"; mkdir -p "$s/verify_timeout_holds"; echo "2 $now $now x" > "$s/verify_timeout_holds/r1.state"; ovn_vt_reset "$s" r1; [ ! -e "$s/verify_timeout_holds/r1.state" ] ) || echo "ovn_vt_reset must remove the streak"
  v="$(vt "$lib" "$s" "$L124" 0 b OVN_VERIFY_TIMEOUT_HOLD=enforce OVN_VT_HOLD_MAX=1)"; [ "${v%% *}" = hold ] || echo "MAX=1 first hold, got: $v"
  v="$(vt "$lib" "$s" "$L124" 0 b OVN_VERIFY_TIMEOUT_HOLD=enforce OVN_VT_HOLD_MAX=1)"; [ "${v%% *}" = escalate ] || echo "MAX=1 second must escalate, got: $v"
}
FB="$(suiteB "$LIB")"
ok "B real lib: every hold/escalate/shadow/off expectation holds${FB:+ ($FB)}" "[ -z \"\$FB\" ]"
[ -z "$FB" ] || echo "$FB" | sed 's/^/    /'
mutate "$LIB" '[ "$nall" -ge 1 ] && [ "$n124" = "$nall" ] || return 1' '[ "$n124" -ge 1 ] || return 1' "$tmp/mut_lib2.sh" && { M="$(suiteB "$tmp/mut_lib2.sh")"; nok "MUTANT any-rc=124-counts is caught (mixed verify)" "[ -z \"\$M\" ]"; }
mutate "$LIB" "-e '^([^ ]+" "-e 'ZZZ^([^ ]+" "$tmp/mut_lib8.sh" && { M="$(suiteB "$tmp/mut_lib8.sh")"; nok "MUTANT progress-line check broken is caught" "[ -z \"\$M\" ]"; }
mutate "$LIB" '  declare -F ovn_ri_failing_ids >/dev/null 2>&1 || return 1' '  declare -F ovn_ri_failing_ids >/dev/null 2>&1 || return 0' "$tmp/mut_lib9.sh" && { M="$(suiteB "$tmp/mut_lib9.sh")"; nok "MUTANT fail-open missing parser is caught" "[ -z \"\$M\" ]"; }
mutate "$LIB" '  [ "$mode" = shadow ] && f="$f.shadow"' '  :' "$tmp/mut_lib10.sh" && { M="$(suiteB "$tmp/mut_lib10.sh")"; nok "MUTANT shadow sharing the enforce file is caught" "[ -z \"\$M\" ]"; }
mutate "$LIB" '${OVN_VT_HOLD_RESET_HOURS:-12}' '${OVN_VT_HOLD_RESET_HOURS:-99999}' "$tmp/mut_lib11.sh" && { M="$(suiteB "$tmp/mut_lib11.sh")"; nok "MUTANT idle-reset window made huge is caught" "[ -z \"\$M\" ]"; }
mutate "$LIB" '  [ -z "$ids" ] || return 1' '  :' "$tmp/mut_lib3.sh" && { M="$(suiteB "$tmp/mut_lib3.sh")"; nok "MUTANT ignoring failing ids is caught" "[ -z \"\$M\" ]"; }
mutate "$LIB" 'if [ "$count" -ge "$max" ] || [ $(( now - first )) -gt $(( maxh * 3600 )) ]; then' 'if false; then' "$tmp/mut_lib4.sh" && { M="$(suiteB "$tmp/mut_lib4.sh")"; nok "MUTANT unbounded hold is caught" "[ -z \"\$M\" ]"; }
mutate "$LIB" '${OVN_VERIFY_TIMEOUT_HOLD:-shadow}' '${OVN_VERIFY_TIMEOUT_HOLD:-enforce}' "$tmp/mut_lib5.sh" && { M="$(suiteB "$tmp/mut_lib5.sh")"; nok "MUTANT default=enforce is caught" "[ -z \"\$M\" ]"; }
mutate "$LIB" 'case "$mode" in off|shadow|enforce) ;; *) mode=shadow;; esac' ':' "$tmp/mut_lib6.sh" && { M="$(suiteB "$tmp/mut_lib6.sh")"; nok "MUTANT typo-mode handling removed is caught" "[ -z \"\$M\" ]"; }
mutate "$LIB" 'if [ "$mode" = shadow ]; then
    OVN_VT_VERDICT=shadow-hold' 'if false; then
    OVN_VT_VERDICT=shadow-hold' "$tmp/mut_lib7.sh" && { M="$(suiteB "$tmp/mut_lib7.sh")"; nok "MUTANT shadow that enforces is caught" "[ -z \"\$M\" ]"; }

# ============================== C. wired into run_overnight.sh ==============================
BLK="$tmp/hold_block.sh"
"$PY" - "$R" "$BLK" <<'EOF' || { F=$((F+1)); echo "  FAIL: could not extract the hold block from run_overnight.sh"; }
import sys
s = open(sys.argv[1]).read()
a = s.index('      _ovn_vt_base=""\n      if [ "$VERIFY_RESULT" = "fail" ]; then\n        ovn_vt_decide')
b = s.index('      if [ "$VERIFY_RESULT" = "fail" ]; then\n        OVN_CHANGED_ALL=', a)
open(sys.argv[2], "w").write(s[a:b])
EOF
RESET="$tmp/reset_block.sh"
"$PY" - "$R" "$RESET" <<'EOF' || { F=$((F+1)); echo "  FAIL: could not extract the escalation reset block"; }
import sys
s = open(sys.argv[1]).read()
a = s.index('        git reset --hard "$BEFORE_SHA" --quiet\n        if [ -n "${_ovn_vt_base:-}" ] && ! ovn_vt_revert_held')
b = s.index('        git clean -fd --quiet', a)
open(sys.argv[2], "w").write(s[a:b])
EOF
runblk(){ # <block file> <mode> <log> [ENV=val ...] -> "<fallthrough|status> | base=<_ovn_vt_base>"
  local blk="$1" mode="$2" log="$3"; shift 3
  ( env OVN_VERIFY_TIMEOUT_HOLD="$mode" "$@" bash -c '
      source "$1"; source "$2"
      SCRIPT_DIR="$3"; task_log="$4"; id=ongoing-r1; BEFORE_SHA=beef; _ovn_voff=0; VERIFY_RESULT="${VR:-fail}"
      emit_alert(){ echo "$1|$3" >> "$SCRIPT_DIR/alerts.txt"; }
      f(){ '"$(cat "$blk")"'
        echo "FALLTHROUGH | base=${_ovn_vt_base:-}"; }
      cd "$5" && f' _ "$RILIB" "$LIB" "$tmp/stC" "$log" "$tmp/stC/r1" )
}
mkdir -p "$tmp/stC/state" "$tmp/stC/r1"; : > "$tmp/stC/alerts.txt"
cp "$L124" "$tmp/stC/tl1.log"
ok "C1 default (shadow): falls through to the revert, logs the shadow decision, no state, no alert" "[ \"\$(runblk '$BLK' '' '$tmp/stC/tl1.log' 2>&1 | tail -1)\" = 'FALLTHROUGH | base=' ] && grep -q 'VERIFY-TIMEOUT HOLD (shadow)' '$tmp/stC/tl1.log' && [ ! -e '$tmp/stC/state/verify_timeout_holds/r1.state' ] && [ ! -s '$tmp/stC/alerts.txt' ]"
cp "$L124" "$tmp/stC/tl2.log"
ok "C2 enforce: returns the held status (error class, names rc=124), raises an alert, writes the streak" "RESP=\"\$(runblk '$BLK' enforce '$tmp/stC/tl2.log' 2>&1)\"; case \"\$RESP\" in 'error(verify-timeout-held - rc=124 with no failing test, hold 1/3)') true;; *) echo \"\$RESP\" >&2; false;; esac && grep -q 'verify TIMED OUT' '$tmp/stC/alerts.txt' && [ -s '$tmp/stC/state/verify_timeout_holds/r1.state' ]"
cp "$L124" "$tmp/stC/tl3.log"; runblk "$BLK" enforce "$tmp/stC/tl3.log" >/dev/null 2>&1; runblk "$BLK" enforce "$tmp/stC/tl3.log" >/dev/null 2>&1
ok "C3 enforce, 4th timeout: falls through to the revert with the streak base set (escalate)" "[ \"\$(runblk '$BLK' enforce '$tmp/stC/tl3.log' 2>&1 | tail -1)\" = 'FALLTHROUGH | base=beef' ] && grep -q 'hold bound reached' '$tmp/stC/alerts.txt'"
cp "$LRED" "$tmp/stC/tl4.log"
ok "C4 enforce, ordinary red: untouched (falls through, no hold)" "[ \"\$(runblk '$BLK' enforce '$tmp/stC/tl4.log' 2>&1 | tail -1)\" = 'FALLTHROUGH | base=' ]"
cp "$L124" "$tmp/stC/tl5.log"
ok "C5 off: falls through silently" "[ \"\$(runblk '$BLK' off '$tmp/stC/tl5.log' 2>&1 | tail -1)\" = 'FALLTHROUGH | base=' ] && ! grep -q 'VERIFY-TIMEOUT' '$tmp/stC/tl5.log'"
ok "C6 enforce but VERIFY_RESULT=pass: the block does nothing" "[ \"\$(runblk '$BLK' enforce '$tmp/stC/tl5.log' VR=pass 2>&1 | tail -1)\" = 'FALLTHROUGH | base=' ]"
grep -q 'ovn_vt_decide.*BEFORE_SHA' "$R" && ok "C7 the hold block sits BEFORE the NO-NEW-RED revert" "[ \$(grep -n 'ovn_vt_decide \"\$SCRIPT_DIR/state\"' '$R' | head -1 | cut -d: -f1) -lt \$(grep -n 'NO-NEW-RED GUARD: commit left the suite red' '$R' | head -1 | cut -d: -f1) ]"
ok "C8 a verified landing ends the streak (ovn_vt_reset on VERIFY_RESULT=pass)" "grep -q 'ovn_vt_reset \"\$SCRIPT_DIR/state\"' '$R'"

# C8b behavioural: the real runner line, run with a streak on disk
RSTL="$tmp/reset_line.sh"; grep -m1 'ovn_vt_reset "\$SCRIPT_DIR/state"' "$R" | sed -E 's/^ +//; s/   # .*$//' > "$RSTL"
rstrun(){ # <line file> <VERIFY_RESULT> -> "gone"|"kept" for BOTH the enforce and shadow streak files
  local d="$tmp/stR.$RANDOM"; mkdir -p "$d/state/verify_timeout_holds" "$d/r1"; echo "2 1 1 x" > "$d/state/verify_timeout_holds/r1.state"; echo "2 1 1 x" > "$d/state/verify_timeout_holds/r1.state.shadow"
  ( cd "$d/r1" && source "$RILIB" && source "$LIB" && SCRIPT_DIR="$d" VERIFY_RESULT="$2" && source "$1" )
  [ ! -e "$d/state/verify_timeout_holds/r1.state" ] && [ ! -e "$d/state/verify_timeout_holds/r1.state.shadow" ] && echo gone || echo kept
}
ok "C8b a verified landing removes the enforce AND shadow streak" "[ \"\$(rstrun '$RSTL' pass)\" = gone ]"
ok "C8c a non-pass verify leaves the streak alone" "[ \"\$(rstrun '$RSTL' fail)\" = kept ]"
sed 's/ovn_vt_reset/:/' "$RSTL" > "$tmp/reset_line_mut.sh"
nok "MUTANT ovn_vt_reset call replaced by a no-op is caught by C8b" "[ \"\$(rstrun '$tmp/reset_line_mut.sh' pass)\" = gone ]"
# C14 the runner's reconcile throttle, extracted and run with a stub reconciler that counts invocations
THR="$tmp/throttle_block.sh"
"$PY" - "$R" "$THR" <<'EOF' || { F=$((F+1)); echo "  FAIL: could not extract the reconcile throttle block"; }
import sys
s = open(sys.argv[1]).read()
a = s.index('  if [ "${OVN_OUTCOME_RECONCILE:-on}" != off ]')
b = s.index('\n  fi\n', a) + len('\n  fi\n')
open(sys.argv[2], "w").write(s[a:b])
EOF
thr_run(){ # <block> <n runs> [ENV=val ...] -> number of reconcile invocations after n back-to-back runs (fresh stamp dir)
  local blk="$1" n="$2"; shift 2; local d="$tmp/thr.$RANDOM"; mkdir -p "$d/scripts" "$d/state" "$d/logs"
  printf 'open("%s", "a").write("x")\n' "$d/count" > "$d/scripts/ovn_outcome_acct.py"
  local i; for i in $(seq 1 "$n"); do ( env "$@" bash -c 'SCRIPT_DIR="$1"; STATE_DIR="$1/state"; LOG_DIR="$1/logs"; TYPE=aider_fix; source "$2"' _ "$d" "$blk" ); sleep 1; done
  sleep 1; if [ -f "$d/count" ]; then wc -c < "$d/count" | tr -d ' '; else echo 0; fi
}
ok "C14 throttle: 3 back-to-back cycles start exactly ONE reconcile" "[ \"\$(thr_run '$THR' 3 X=1)\" = 1 ]"
ok "C15 OVN_OUTCOME_RECONCILE=off starts none" "[ \"\$(thr_run '$THR' 2 OVN_OUTCOME_RECONCILE=off)\" = 0 ]"
mutate "$THR" '-mmin -"${OVN_OUTCOME_RECONCILE_MIN:-10}"' '-mmin -0' "$tmp/mut_thr.sh" && nok "MUTANT throttle window 0 is caught by C14" "[ \"\$(thr_run '$tmp/mut_thr.sh' 3 X=1)\" = 1 ]"
# escalation reset to the streak base
gb="$tmp/gb"; mkdir -p "$gb"; git -C "$gb" init -q -b main; echo a > "$gb/a"; git -C "$gb" add -A; git -C "$gb" commit -q -m base; g0="$(git -C "$gb" rev-parse HEAD)"
echo b > "$gb/b"; git -C "$gb" add -A; git -C "$gb" commit -q -m held1; echo c > "$gb/c"; git -C "$gb" add -A; git -C "$gb" commit -q -m held2; g2="$(git -C "$gb" rev-parse HEAD)"
rst(){ ( cd "$gb" || exit 1; git reset -q --hard "$g2"; git clean -fdq; task_log="$tmp/rst.log"; : > "$task_log"; : > "$tmp/rst.alerts"; BEFORE_SHA="$g2"; _ovn_vt_base="$1"; id=ongoing-gb
          emit_alert(){ echo "$1|$3" >> "$tmp/rst.alerts"; }; source "$LIB"
          [ -n "${2:-}" ] && { echo p > OVERNIGHT_PROGRESS.md; git add -A; git commit -q -m prog; BEFORE_SHA="$(git rev-parse HEAD)"; }
          [ "${2:-}" = unrelated ] && { git checkout -q --orphan other 2>/dev/null; git rm -rqf . ; echo z > z; git add z; git commit -q -m other; BEFORE_SHA="$(git rev-parse HEAD)"; }
          source "$RESET"; git rev-parse HEAD; ) 2>/dev/null; }
ok "C9 escalation resets to the streak base (held commits go too)" "[ \"\$(rst '$g0')\" = '$g0' ]"
ok "C10 no streak base: reset to BEFORE_SHA (held commits stay, old behaviour)" "[ \"\$(rst '')\" = '$g2' ]"
ok "C11 queue bookkeeping committed in between: do NOT reset past it" "[ \"\$(rst '$g0' prog)\" != '$g0' ]"
# C11b (review defect 5): in that case the held commits' CHANGES must still be undone (files b, c gone), the bookkeeping kept, and no 'could not revert' alert
rst_state(){ ( cd "$gb" && rst "$@" >/dev/null 2>&1; echo "b=$([ -e b ] && echo y || echo n) c=$([ -e c ] && echo y || echo n) prog=$([ -e OVERNIGHT_PROGRESS.md ] && echo y || echo n) a=$([ -e a ] && echo y || echo n) alerts=$(wc -l < "$tmp/rst.alerts" | tr -d ' ')" ); }
ok "C11b bookkeeping in between: held commits' files removed, bookkeeping + base kept, no alert" "[ \"\$(rst_state '$g0' prog)\" = 'b=n c=n prog=y a=y alerts=0' ]"
ok "C11c no bookkeeping: plain reset to base removes the held files, no alert" "[ \"\$(rst_state '$g0')\" = 'b=n c=n prog=n a=y alerts=0' ]"
ok "C11d streak base unreachable (unrelated history): held state is reported with an alert + log line, never claimed reverted" "rst_state '$g0' unrelated >/dev/null; [ \"\$(wc -l < '$tmp/rst.alerts' | tr -d ' ')\" = 1 ] && grep -q 'REMAIN in HEAD' '$tmp/rst.log'"
mutate "$RESET" 'ovn_vt_revert_held "$_ovn_vt_base" "$BEFORE_SHA" "$task_log"' 'true' "$tmp/reset_mut1.sh" && nok "MUTANT escalation revert call removed is caught by C11b/C9" "( RESET='$tmp/reset_mut1.sh'; [ \"\$(rst_state '$g0' prog)\" = 'b=n c=n prog=y a=y alerts=0' ] )"
mutate "$LIB" "git diff --binary \"\$base\" \"\$before\" -- . ':!OVERNIGHT_PROGRESS.md' ':!OVERNIGHT_DONE.md' 2>/dev/null | git apply -R --index 2>/dev/null" "false" "$tmp/mut_lib_rv.sh" && nok "MUTANT bookkeeping-case revert removed is caught by C11b" "( LIB='$tmp/mut_lib_rv.sh'; [ \"\$(rst_state '$g0' prog)\" = 'b=n c=n prog=y a=y alerts=0' ] )"
# status classification
RS="$(rec_row "$R" "$LIB" h1 repoA "error(verify-timeout-held - rc=124 with no failing test, hold 1/3)" "" aider_fix 1 "$L124" 3600 "$rd" "" "$c0" "$c2")"
ok "C12 held status => class held, severity neutral, fail_reason verify-timeout, commits kept" "[ \"\$(rowq '$RS' '(r[\"class\"],r[\"severity\"],r[\"fail_reason\"],len(r[\"commits\"]))')\" = \"('held', 'neutral', 'verify-timeout', 2)\" ]"
RS2="$(rec_row "$R" "$LIB" h2 repoA "error(verify-skipped - lock contended, retry next cycle)" "" aider_fix 1 /dev/null 3600 "$rd" "" "$c0" "$c2")"
ok "C13 legacy lock-skip status keeps class error (unchanged)" "[ \"\$(rowq '$RS2' 'r[\"class\"]')\" = error ]"
mutate "$R" '*verify-timeout-held*)         cls=held;      sev=neutral;;' '*verify-timeout-heldX*)        cls=held;      sev=neutral;;' "$tmp/mut_run2.sh" \
  && { M="$(rec_row "$tmp/mut_run2.sh" "$LIB" m3 repoA "error(verify-timeout-held - x)" "" aider_fix 1 /dev/null 3600 "$rd" "" "$c0" "$c2" 2>/dev/null)"; nok "MUTANT held-class pattern removed is caught by C12" "[ \"\$(rowq '$M' 'r[\"class\"]')\" = held ]"; }
mutate "$BLK" 'echo "error(verify-timeout-held' 'echo "no-op(reverted-red) (verify-timeout-held' "$tmp/mut_blk1.sh" \
  && nok "MUTANT hold block that reverts instead of holding is caught by C2" "RESP=\"\$(runblk '$tmp/mut_blk1.sh' enforce '$tmp/stC/tl2.log' 2>&1)\"; case \"\$RESP\" in 'error(verify-timeout-held - rc=124 with no failing test, hold '*) true;; *) false;; esac"
mutate "$BLK" '          hold)
' '          holdx)
' "$tmp/mut_blk2.sh" \
  && nok "MUTANT hold branch unreachable is caught by C2" "RESP=\"\$(runblk '$tmp/mut_blk2.sh' enforce '$tmp/stC/tl2.log' 2>&1)\"; case \"\$RESP\" in 'error(verify-timeout-held - rc=124 with no failing test, hold '*) true;; *) false;; esac"

# ============================== D. reconcile held commits ==============================
D="$tmp/D"; mkdir -p "$D/state" "$D/repos"
git init -q --bare -b overnight/feature "$D/origin.git"
git clone -q "$D/origin.git" "$D/repos/r1" 2>/dev/null; rr="$D/repos/r1"; git -C "$rr" checkout -q -b overnight/feature 2>/dev/null
echo 0 > "$rr/f"; git -C "$rr" add -A; git -C "$rr" commit -q -m base; git -C "$rr" push -q origin overnight/feature 2>/dev/null; d0="$(git -C "$rr" rev-parse HEAD)"
echo 1 >> "$rr/f"; git -C "$rr" commit -q -am held1; d1="$(git -C "$rr" rev-parse HEAD)"
echo 2 >> "$rr/f"; git -C "$rr" commit -q -am held2; d2="$(git -C "$rr" rev-parse HEAD)"
iso(){ "$PY" -c "import time;print(time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(time.time()-$1)))"; }
TS_HELD="$(iso 600)"; TS_HELD2="$(iso 500)"; TS_LAND="$(iso 400)"; TS_REV="$(iso 300)"; TS_OLD="$(iso $((10*86400)))"; TS_PART="$(iso 200)"
"$PY" - "$D/state/outcomes.jsonl" "$TS_HELD" "$TS_HELD2" "$TS_LAND" "$TS_REV" "$TS_OLD" "$TS_PART" "$d0" "$d1" "$d2" <<'EOF'
import json, sys
out, held, held2, land, rev, old, part, d0, d1, d2 = sys.argv[1:]
def row(ts, cls, status, commits, **kw):
    r = {"ts": ts, "repo": "r1", "id": "ongoing-r1", "type": "aider_fix", "tier": "2", "category": "python", "class": cls, "severity": "neutral", "attempt": 1, "attempts": 1,
         "bestn_stop": "", "fail_reason": "", "status": status, "tokens_sent": 0, "tokens_recv": 0, "duration_s": 60, "item_hash": "h-" + ts[-3:], "feat_tag": "feat-x",
         "commits": commits, "head_before": d0, "head_after": (commits or [d0])[-1]}
    r.update(kw); return r
rows = [
  row(held, "error", "error(verify-skipped - lock contended, retry next cycle)", [d1]),                         # D1: held, will land
  row(held2, "held", "error(verify-timeout-held - rc=124 with no failing test, hold 1/3)", [d1, d2]),           # D2: held, lands only when BOTH commits land
  row(land, "landed", "pushed(tests:pass)", [d1]),                                                              # a landing row: never reconciled
  row(rev, "noop", "no-op(reverted-red)", [d1]),                                                                # a revert row: ignored even with a commit list
  row(old, "error", "error(verify-skipped - lock contended, retry next cycle)", [d1]),                          # outside the window
  row(part, "held", "error(verify-timeout-held - x)", ["f" * 40]),                                              # sha unknown to the repo: cannot land
]
old_fmt = {"ts": held, "repo": "r1", "id": "ongoing-r1", "class": "error", "status": "error(verify-skipped)"}   # old-format row: no commits field at all
with open(out, "w") as f:
    f.write(json.dumps(old_fmt) + "\n"); f.write("{not json\n")
    for r in rows: f.write(json.dumps(r) + "\n")
EOF
OUT="$D/state/outcomes.jsonl"
nrows(){ grep -c '"class":"landed-late"' "$OUT" 2>/dev/null || true; }
rc_run(){ "$PY" "${1:-$ACCT}" reconcile --state-dir "$D/state" --repos-dir "$D/repos" "${@:2}"; }
rc_run >/dev/null 2>&1
ok "D1 nothing pushed yet: no landed-late row" "[ \"\$(nrows)\" = 0 ]"
git -C "$rr" push -q origin overnight/feature 2>/dev/null   # d1 AND d2 reach origin
rc_run "$ACCT" >/dev/null 2>&1
ok "D2 after the push: exactly the two held rows (within the window, known shas) get a landed-late row" "[ \"\$(nrows)\" = 2 ]"
LL="$(grep '"class":"landed-late"' "$OUT" | head -1)"
ok "D3 row shape: neutral severity, late_of_ts names the held row, commits + branch + copied item identity" "[ \"\$(rowq '$LL' '(r[\"severity\"],r[\"status\"],r[\"late_of_ts\"]==\"$TS_HELD\",r[\"commits\"]==[\"$d1\"],r[\"landed_branch\"],r[\"item_hash\"].startswith(\"h-\"),r[\"repo\"])')\" = \"('neutral', 'landed-late(held-commit)', True, True, 'overnight/feature', True, 'r1')\" ]"
rc_run "$ACCT" >/dev/null 2>&1
ok "D4 idempotent: a second pass writes nothing new" "[ \"\$(nrows)\" = 2 ]"
ok "D5 the landing row, the revert row, the out-of-window row and the unknown-sha row never produced a landed-late row" "[ \"\$(grep -c '\"late_of_ts\":\"$TS_LAND\"\\|\"late_of_ts\":\"$TS_REV\"\\|\"late_of_ts\":\"$TS_OLD\"\\|\"late_of_ts\":\"$TS_PART\"' '$OUT')\" = 0 ]"
ok "D6 the file is still parseable line by line except the one deliberately broken line (originals untouched)" "[ \"\$(grep -c 'not json' '$OUT')\" = 1 ] && [ \"\$(wc -l < '$OUT' | tr -d ' ')\" = 10 ]"
ok "D7 attribute lookup names the cycles that made a commit" "[ \"\$('$PY' '$ACCT' attribute --state-dir '$D/state' '$d1' | '$PY' -c 'import json,sys; print(len(json.load(sys.stdin)))')\" -ge 3 ]"
ok "D8 commits CLI agrees with the bash helper (same list, parsed)" "[ \"\$('$PY' '$ACCT' commits '$rr' '$d0' '$d2' | '$PY' -c 'import json,sys; print(json.load(sys.stdin))')\" = \"\$(bash -c 'source $LIB; ovn_oa_commits $rr $d0 $d2' | '$PY' -c 'import json,sys; print(json.load(sys.stdin))')\" ] && [ \"\$('$PY' '$ACCT' commits '$rr' '$d0' '$d2' | '$PY' -c 'import json,sys; print(len(json.load(sys.stdin)))')\" = 2 ]"
# partial landing waits: a fresh repo where only the first of two held commits is on origin
P1="$tmp/Dp"; mkdir -p "$P1/state" "$P1/repos"; git init -q --bare -b overnight/feature "$P1/origin.git"; git clone -q "$P1/origin.git" "$P1/repos/rp" 2>/dev/null; pr="$P1/repos/rp"
git -C "$pr" checkout -q -b overnight/feature 2>/dev/null; echo 0 > "$pr/f"; git -C "$pr" add -A; git -C "$pr" commit -q -m base; git -C "$pr" push -q origin overnight/feature 2>/dev/null; p0="$(git -C "$pr" rev-parse HEAD)"
echo 1 >> "$pr/f"; git -C "$pr" commit -q -am h1; p1="$(git -C "$pr" rev-parse HEAD)"; echo 2 >> "$pr/f"; git -C "$pr" commit -q -am h2; p2="$(git -C "$pr" rev-parse HEAD)"
git -C "$pr" push -q origin "$p1:refs/heads/overnight/feature" 2>/dev/null
"$PY" - "$P1/state/outcomes.jsonl" "$(iso 100)" "$p0" "$p1" "$p2" <<'EOF'
import json, sys
out, ts, p0, p1, p2 = sys.argv[1:]
open(out, "w").write(json.dumps({"ts": ts, "repo": "rp", "id": "ongoing-rp", "class": "held", "status": "error(verify-timeout-held - x)", "commits": [p1, p2], "head_before": p0, "head_after": p2}) + "\n")
EOF
partial(){ "$PY" "${1:-$ACCT}" reconcile --state-dir "$P1/state" --repos-dir "$P1/repos" >/dev/null 2>&1; grep -c landed-late "$P1/state/outcomes.jsonl" || true; }
ok "D9 only 1 of 2 held commits on origin: wait (no row)" "[ \"\$(partial)\" = 0 ]"
mutate "$ACCT" 'if own not in pids:' 'if False:' "$tmp/mut_acct1.py" && nok "MUTANT any-sha-counts (partial landing) is caught by D9" "[ \"\$(partial '$tmp/mut_acct1.py')\" = 0 ]"
git -C "$pr" push -q origin overnight/feature 2>/dev/null
ok "D10 both on origin: one row" "[ \"\$(partial)\" = 1 ]"
# mutants on the idempotence + candidate selection (fresh copies of the D fixture)
cp "$OUT" "$tmp/D.out.keep"
mutate "$ACCT" 'if (repo, ts) in done:' 'if False:' "$tmp/mut_acct2.py" && { rc_run "$tmp/mut_acct2.py" >/dev/null 2>&1; nok "MUTANT no idempotence is caught by D4 (second pass duplicates)" "[ \"\$(nrows)\" = 2 ]"; }
cp "$tmp/D.out.keep" "$OUT"
mutate "$ACCT" 'HELD_CLASSES = frozenset({"held", "error", "unknown"})' 'HELD_CLASSES = frozenset({"held", "error", "unknown", "landed", "noop"})' "$tmp/mut_acct3.py" && { rc_run "$tmp/mut_acct3.py" >/dev/null 2>&1; nok "MUTANT landing/revert rows treated as held is caught by D5" "[ \"\$(grep -c '\"late_of_ts\":\"$TS_LAND\"\\|\"late_of_ts\":\"$TS_REV\"' '$OUT')\" = 0 ]"; }
cp "$tmp/D.out.keep" "$OUT"
mutate "$ACCT" 'if t is None or now - t > window_h * 3600:' 'if t is None:' "$tmp/mut_acct4.py" && { rc_run "$tmp/mut_acct4.py" >/dev/null 2>&1; nok "MUTANT no age window is caught by D5" "[ \"\$(grep -c '\"late_of_ts\":\"$TS_OLD\"' '$OUT')\" = 0 ]"; }
cp "$tmp/D.out.keep" "$OUT"

# ============================== D2. repair round: readers, rebase, concurrency, short shas ==============================
# D2a. landed-late must not change a batch grade (scorecard) nor make an item that landed a "GPU sink" (daily digest)
H2="$tmp/H2"; mkdir -p "$H2/.h/overnight-queue/state" "$H2/state"
"$PY" - "$H2" "$(iso $((3*86400)))" "$(iso $((3*86400-60)))" "$(iso 3000)" <<'EOF'
import json, sys
h2, t1, t2, t3 = sys.argv[1:]
def row(ts, cls, status, dur, **kw):
    r = {"ts": ts, "repo": "iptv_apps", "id": "ongoing-iptv_apps", "type": "aider_fix", "tier": "2", "category": "python", "class": cls, "severity": "neutral", "attempt": 1, "attempts": 1,
         "bestn_stop": "", "fail_reason": "", "status": status, "tokens_sent": 1, "tokens_recv": 1, "duration_s": dur, "item_hash": "h1", "feat_tag": "iptv_apps-20261010-y",
         "commits": [], "head_before": "", "head_after": ""}
    r.update(kw); return r
landed = row(t1, "landed", "pushed(tests:pass)", 100)
held = row(t2, "error", "error(verify-skipped - lock contended, retry next cycle)", 300, commits=["a" * 40])
late = row(t3, "landed-late", "landed-late(held-commit)", 0, commits=["a" * 40], late_of_ts=t2, landed_branch="claude/feature")
def w(path, rows):
    open(path, "w").write("\n".join(json.dumps(r) for r in rows) + "\n")
w(h2 + "/.h/overnight-queue/state/outcomes.jsonl", [landed, held])
w(h2 + "/.h/overnight-queue/state/outcomes_late.jsonl", [landed, held, late])
w(h2 + "/state/outcomes.jsonl", [landed, held])
w(h2 + "/state/outcomes_nolanded.jsonl", [held, dict(held, ts=t1, duration_s=300)])
w(h2 + "/state/outcomes_nolanded_late.jsonl", [held, dict(held, ts=t1, duration_s=300), late])
EOF
SC="$ROOT/scripts/ovn_batch_scorecard.py"
sc_grade(){ # <outcomes file name> [scorecard] -> the grade(s) with at least one batch
  local f="$1" sc="${2:-$SC}"; mkdir -p "$H2/hh/overnight-queue/state"; cp "$H2/.h/overnight-queue/state/$f" "$H2/hh/overnight-queue/state/outcomes.jsonl"
  HOME="$H2/hh" "$PY" "$sc" 0 --min-age-hours=1 | grep -E '^ +[ABCDF] \(' | awk '$3 > 0 {print $1}' | tr -d '\n'
}
ok "D11 scorecard: 1 landed + 1 held(error) row grades C (50%)" "[ \"\$(sc_grade outcomes.jsonl)\" = C ]"
ok "D12 scorecard: adding the landed-late row leaves the grade at C (was D / 33%)" "[ \"\$(sc_grade outcomes_late.jsonl)\" = C ]"
mutate "$SC" 'if r.get("class") == "landed-late":' 'if False:' "$tmp/mut_sc.py" && nok "MUTANT scorecard counting landed-late rows is caught by D12" "[ \"\$(sc_grade outcomes_late.jsonl '$tmp/mut_sc.py')\" = C ]"
DG="$ROOT/scripts/ovn_daily_fail_digest.py"
dg(){ mkdir -p "$H2/dg"; cp "$H2/state/$1" "$H2/dg/outcomes.jsonl"; "$PY" "${2:-$DG}" --state-dir "$H2/dg" --hours 100000 --now "$(date +%s)" --json | "$PY" -c "import json,sys; d=json.load(sys.stdin); print(json.dumps([[s['item'],s['cycles']] for s in d['gpu_sinks']]))"; }
ok "D13 digest control: an item that has a landed row is not a sink" "[ \"\$(dg outcomes.jsonl)\" = '[]' ]"
ok "D14 digest control: an error-only item IS a sink with its 2 cycles" "[ \"\$(dg outcomes_nolanded.jsonl)\" = '[[\"iptv_apps-20261010-y\", 2]]' ]"
ok "D15 digest: error-only item + landed-late row is NOT a GPU sink (its commit reached origin)" "[ \"\$(dg outcomes_nolanded_late.jsonl)\" = '[]' ]"
mutate "$DG" 'if r.get("class") == LATE_CLASS:' 'if False:' "$tmp/mut_dg.py" && nok "MUTANT digest ignoring landed-late is caught by D15" "[ \"\$(dg outcomes_nolanded_late.jsonl '$tmp/mut_dg.py')\" = '[]' ]"

# D2b. a held commit rewritten by `git pull --rebase` is matched by patch-id
RB="$tmp/Drb"; mkdir -p "$RB/state" "$RB/repos"; git init -q --bare -b claude/feature "$RB/origin.git"; git clone -q "$RB/origin.git" "$RB/repos/rb" 2>/dev/null; rbr="$RB/repos/rb"
git -C "$rbr" checkout -q -b claude/feature 2>/dev/null; echo 0 > "$rbr/f"; git -C "$rbr" add -A; git -C "$rbr" commit -q -m base; git -C "$rbr" push -q origin claude/feature 2>/dev/null
echo held > "$rbr/h"; git -C "$rbr" add -A; git -C "$rbr" commit -q -m held2; rH="$(git -C "$rbr" rev-parse HEAD)"
# another agent moves the remote, then our next cycle's push rebases the held commit onto it
git clone -q "$RB/origin.git" "$RB/other" 2>/dev/null; git -C "$RB/other" checkout -q claude/feature 2>/dev/null; echo o > "$RB/other/o"; git -C "$RB/other" add -A; git -C "$RB/other" commit -q -m other; git -C "$RB/other" push -q origin claude/feature 2>/dev/null
"$PY" - "$RB/state/outcomes.jsonl" "$(iso 100)" "$rH" <<'EOF'
import json, sys
out, ts, h = sys.argv[1:]
open(out, "w").write(json.dumps({"ts": ts, "repo": "rb", "id": "ongoing-rb", "class": "held", "status": "error(verify-timeout-held - x)", "commits": [h], "head_before": h, "head_after": h}) + "\n")
EOF
cp "$RB/state/outcomes.jsonl" "$tmp/rb.in"
rbrun(){ cp "$tmp/rb.in" "$RB/state/outcomes.jsonl"; "$PY" "${1:-$ACCT}" reconcile --state-dir "$RB/state" --repos-dir "$RB/repos" --branches claude/feature >/dev/null 2>&1; grep -c landed-late "$RB/state/outcomes.jsonl" || true; }
git -C "$rbr" fetch -q origin; git -C "$rbr" pull -q --rebase origin claude/feature 2>/dev/null; git -C "$rbr" push -q origin claude/feature 2>/dev/null
nok "D16 precondition: the rebased commit has a NEW sha (the old one is not an ancestor of origin)" "git -C '$rbr' merge-base --is-ancestor '$rH' refs/remotes/origin/claude/feature"
ok "D17 rebased held commit: exactly one landed-late row (patch-id fallback)" "[ \"\$(rbrun)\" = 1 ]"
ok "D18 the row names the branch" "grep landed-late '$RB/state/outcomes.jsonl' | grep -q '\"landed_branch\":\"claude/feature\"'"
# control: a held commit that never landed stays unreconciled even with the fallback
RB2="$tmp/Drb2"; mkdir -p "$RB2/state" "$RB2/repos"; cp -R "$RB/origin.git" "$RB2/origin.git"; git clone -q "$RB2/origin.git" "$RB2/repos/rb" 2>/dev/null; rb2="$RB2/repos/rb"; git -C "$rb2" checkout -q claude/feature 2>/dev/null
echo unl > "$rb2/u"; git -C "$rb2" add -A; git -C "$rb2" commit -q -m unlanded; rU="$(git -C "$rb2" rev-parse HEAD)"
"$PY" - "$RB2/state/outcomes.jsonl" "$(iso 100)" "$rU" <<'EOF'
import json, sys
out, ts, h = sys.argv[1:]
open(out, "w").write(json.dumps({"ts": ts, "repo": "rb", "id": "ongoing-rb", "class": "held", "status": "error(verify-timeout-held - x)", "commits": [h], "head_before": h, "head_after": h}) + "\n")
EOF
cp "$RB2/state/outcomes.jsonl" "$tmp/rb2.in"
rb2run(){ cp "$tmp/rb2.in" "$RB2/state/outcomes.jsonl"; "$PY" "${1:-$ACCT}" reconcile --state-dir "$RB2/state" --repos-dir "$RB2/repos" --branches claude/feature >/dev/null 2>&1; grep -c landed-late "$RB2/state/outcomes.jsonl" || true; }
ok "D19 control: a never-pushed held commit is not matched by the patch-id fallback" "[ \"\$(rb2run)\" = 0 ]"
mutate "$ACCT" 'if own not in pids:' 'if False:' "$tmp/mut_acct5.py" && nok "MUTANT patch-id fallback that matches anything is caught by D19" "[ \"\$(rb2run '$tmp/mut_acct5.py')\" = 0 ]"
mutate "$ACCT" '                pids = _patch_ids(repo_dir, ref, lo, max_count=1500 if since_epoch is not None else 400)' '                pids = {}' "$tmp/mut_acct6.py" && nok "MUTANT patch-id fallback disabled (empty table) is caught by D17" "[ \"\$(rbrun '$tmp/mut_acct6.py')\" = 1 ]"

# D2c. concurrent reconcile runs write ONE row per held row
CC="$tmp/Dcc"; mkdir -p "$CC/state" "$CC/repos"; cp -R "$D/origin.git" "$CC/origin.git"; git clone -q "$CC/origin.git" "$CC/repos/r1" 2>/dev/null
"$PY" - "$CC/state/outcomes.jsonl" "$(iso 100)" "$d0" "$d1" <<'EOF'
import json, sys
out, ts, d0, d1 = sys.argv[1:]
open(out, "w").write(json.dumps({"ts": ts, "repo": "r1", "id": "ongoing-r1", "class": "error", "status": "error(verify-skipped - lock contended, retry next cycle)", "commits": [d1], "head_before": d0, "head_after": d1}) + "\n")
EOF
cp "$CC/state/outcomes.jsonl" "$tmp/cc.in"
conc(){ # <script> -> landed-late rows after 8 simultaneous reconciles
  cp "$tmp/cc.in" "$CC/state/outcomes.jsonl"; rm -f "$CC/state/outcome_reconcile.lock"; local i
  for i in 1 2 3 4 5 6 7 8; do "$PY" "$1" reconcile --state-dir "$CC/state" --repos-dir "$CC/repos" >/dev/null 2>&1 & done; wait
  grep -c landed-late "$CC/state/outcomes.jsonl" || true
}
ok "D20 8 concurrent reconciles: exactly ONE landed-late row" "[ \"\$(conc '$ACCT')\" = 1 ]"
mutate "$ACCT" 'fcntl.flock(lk, fcntl.LOCK_EX | fcntl.LOCK_NB)' 'pass' "$tmp/mut_acct7.py" && nok "MUTANT no flock is caught by D20 (duplicates)" "[ \"\$(conc '$tmp/mut_acct7.py')\" = 1 ]"

# D2d. surviving mutants of the first review: same-run dedupe, short shas, tail read
DU="$tmp/Ddu"; mkdir -p "$DU/state"; "$PY" - "$DU/state/outcomes.jsonl" "$(iso 100)" "$d0" "$d1" <<'EOF'
import json, sys
out, ts, d0, d1 = sys.argv[1:]
r = {"ts": ts, "repo": "r1", "id": "ongoing-r1", "class": "error", "status": "error(verify-skipped)", "commits": [d1], "head_before": d0, "head_after": d1}
open(out, "w").write(json.dumps(r) + "\n" + json.dumps(r) + "\n")   # two held rows with the same (repo, ts) in ONE pass
EOF
cp "$DU/state/outcomes.jsonl" "$tmp/du.in"
duprun(){ cp "$tmp/du.in" "$DU/state/outcomes.jsonl"; "$PY" "${1:-$ACCT}" reconcile --state-dir "$DU/state" --repos-dir "$D/repos" >/dev/null 2>&1; grep -c landed-late "$DU/state/outcomes.jsonl" || true; }
ok "D21 two held rows with the same (repo, ts) in one pass: one landed-late row (same-run dedupe)" "[ \"\$(duprun)\" = 1 ]"
mutate "$ACCT" '        done.add((repo, ts))
' '' "$tmp/mut_acct8.py" && nok "MUTANT done.add removed is caught by D21" "[ \"\$(duprun '$tmp/mut_acct8.py')\" = 1 ]"
SH="$tmp/Dsh"; mkdir -p "$SH/state"; "$PY" - "$SH/state/outcomes.jsonl" "$(iso 100)" "$d0" "$d1" <<'EOF'
import json, sys
out, ts, d0, d1 = sys.argv[1:]
open(out, "w").write(json.dumps({"ts": ts, "repo": "r1", "id": "ongoing-r1", "class": "error", "status": "error(verify-skipped)", "commits": [d1[:5]], "head_before": d0, "head_after": d1}) + "\n")   # a 5-char "sha" git would happily resolve
EOF
cp "$SH/state/outcomes.jsonl" "$tmp/sh.in"
shrun(){ cp "$tmp/sh.in" "$SH/state/outcomes.jsonl"; "$PY" "${1:-$ACCT}" reconcile --state-dir "$SH/state" --repos-dir "$D/repos" >/dev/null 2>&1; grep -c landed-late "$SH/state/outcomes.jsonl" || true; }
ok "D22 a too-short sha is never trusted (no landed-late row)" "[ \"\$(shrun)\" = 0 ]"
mutate "$ACCT" '7 <= len(s) <= 40' '1 <= len(s) <= 40' "$tmp/mut_acct9.py" && nok "MUTANT min sha length 1 is caught by D22" "[ \"\$(shrun '$tmp/mut_acct9.py')\" = 0 ]"
"$PY" - "$ROOT/scripts" "$tmp/tail.jsonl" <<'EOF' && ok "D23 read_rows keeps a line that starts exactly at the tail cut and drops a partial one" "true" || { F=$((F+1)); echo "  FAIL: D23 read_rows tail boundary"; }
import json, sys
sys.path.insert(0, sys.argv[1]); import ovn_outcome_acct as a
p = sys.argv[2]; L = [json.dumps({"n": i}) for i in range(3)]; open(p, "w").write("\n".join(L) + "\n")
exact = len(L[1]) + 1 + len(L[2]) + 1
assert [r["n"] for r in a.read_rows(p, exact)] == [1, 2], a.read_rows(p, exact)
assert [r["n"] for r in a.read_rows(p, exact + 3)] == [1, 2], a.read_rows(p, exact + 3)
EOF
# NOTE: removing the tail-read readline() (review item e) and the b==a early return in ovn_oa_commits (item f) are EQUIVALENT mutants: a cut line can never parse as a JSON
# object (a suffix of a valid object is not one), and `git rev-list A --not A` is empty so the helper prints [] either way. Not asserted.


# ============================== F. repair round 2 (review defects 1-8) ==============================
# F1 (defect 1): the backgrounded reconcile must NOT inherit run.lock (fd 200): flock belongs to the open file description, so a child keeps the lock after the runner closes its fd
fl_run(){ # <block> -> "free" when the lock is takeable right after the parent closed ITS fd while the (slow) reconcile child still runs, else "held"
  local blk="$1" d="$tmp/fl.$RANDOM"; mkdir -p "$d/scripts" "$d/state" "$d/logs"
  printf 'import time\ntime.sleep(4)\n' > "$d/scripts/ovn_outcome_acct.py"
  : > "$d/run.lock"
  ( exec 200>"$d/run.lock"; "$PY" -c 'import fcntl; fcntl.flock(200, fcntl.LOCK_EX)' 200>&200
    SCRIPT_DIR="$d"; STATE_DIR="$d/state"; LOG_DIR="$d/logs"; TYPE=aider_fix; source "$blk"
    exec 200>&- )
  "$PY" - "$d/run.lock" <<'EOF'
import fcntl, sys
f = open(sys.argv[1], "a")
try:
    fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB); print("free")
except OSError:
    print("held")
EOF
}
ok "F1 reconcile child does not inherit run.lock: takeable the moment the runner closes its fd" "[ \"\$(fl_run '$THR')\" = free ]"
mutate "$THR" ' 200>&- < /dev/null &' ' &' "$tmp/mut_fl.sh" && nok "MUTANT launch without 200>&- is caught by F1 (child keeps the lock)" "[ \"\$(fl_run '$tmp/mut_fl.sh')\" = free ]"

# F2 (defect 2): the main-loop plumbing of head_before / head_after. Extract the real lines from the runner and run them against a real task log + repo.
PLB="$tmp/plumb_block.sh"
"$PY" - "$R" "$PLB" <<'EOF' || { F=$((F+1)); echo "  FAIL: could not extract the head plumbing block"; }
import sys
s = open(sys.argv[1]).read()
a = s.index('  _oa_hb=""; [ -n "${TASK_LOG:-}" ]')
b = s.index('\n', s.index('  record_outcome "$ID" "${REPO_BASENAME:-}"', a)) + 1
open(sys.argv[2], "w").write(s[a:b])
EOF
MARK="$tmp/marker_line.sh"; grep -m1 -- 'ovn-head-before: ${BEFORE_SHA}' "$R" | sed -E 's/^ +//' > "$MARK"
[ -s "$MARK" ] || { F=$((F+1)); echo "  FAIL: marker echo line not found in the runner"; }
plumb(){ # <block> <marker line file|none> -> "<hb>|<ha>" as received by record_outcome
  local blk="$1" mk="$2" d="$tmp/pl.$RANDOM"; mkdir -p "$d"
  ( cd "$rd" && TASK_LOG="$d/task.log"; : > "$TASK_LOG"; BEFORE_SHA="$c0"; task_log="$TASK_LOG"; ID=x; TYPE=aider_fix; REPO="$rd"; REPO_BASENAME=repoA; STATUS=ok; PROMPT=""; _TASK_DURATION_S=1; _btry=1
    source "$LIB"
    [ "$mk" = none ] || source "$mk"
    record_outcome(){ printf '%s|%s' "${11:-}" "${12:-}" > "$d/args"; }
    source "$blk" ) >/dev/null 2>&1
  cat "$d/args" 2>/dev/null
}
ok "F2a plumbing: record_outcome receives the logged head_before and the repo HEAD" "[ \"\$(plumb '$PLB' '$MARK')\" = '$c0|$c2' ]"
nok "F2b control: without the marker echo head_before is empty (so the marker line is load-bearing)" "[ \"\$(plumb '$PLB' none)\" = '$c0|$c2' ]"
mutate "$PLB" '"$_oa_hb" "$_oa_ha"' '' "$tmp/mut_plb1.sh" && nok "MUTANT head args dropped from the record_outcome call is caught by F2a" "[ \"\$(plumb '$tmp/mut_plb1.sh' '$MARK')\" = '$c0|$c2' ]"
mutate "$PLB" 'ovn_oa_head "$REPO"' 'true "$REPO"' "$tmp/mut_plb2.sh" && nok "MUTANT head_after not read is caught by F2a" "[ \"\$(plumb '$tmp/mut_plb2.sh' '$MARK')\" = '$c0|$c2' ]"
mutate "$MARK" 'ovn-head-before' 'ovn-head-beforeX' "$tmp/mut_mark.sh" && nok "MUTANT renamed marker echo is caught by F2a" "[ \"\$(plumb '$PLB' '$tmp/mut_mark.sh')\" = '$c0|$c2' ]"
# the stage runner: its base sha capture and the row's commit derivation (text pins + mutants of the two lines)
SR="$ROOT/ovn_stage_runner.sh"
ok "F2c stage runner captures _ST_H0 from the stage worktree HEAD and derives commits from it" "grep -q '^_ST_H0=\"\$(git -C \"\$wt\" rev-parse -q --verify HEAD' '$SR' && grep -q 'ovn_oa_commits \"\$wt\" \"\$hb\" \"\$ha\"' '$SR'"
mutate "$SR" '_ST_H0="$(git -C "$wt" rev-parse -q --verify HEAD 2>/dev/null)"' '_ST_H0=""' "$tmp/mut_sr1.sh" && nok "MUTANT stage runner without _ST_H0 is caught by F2c" "grep -q '^_ST_H0=\"\$(git -C \"\$wt\" rev-parse -q --verify HEAD' '$tmp/mut_sr1.sh'"

# F3 (defect 3): a clone rebased mid-cycle must not claim the upstream commits
FR="$tmp/Fr"; mkdir -p "$FR"; git init -q --bare -b main "$FR/origin.git"; git clone -q "$FR/origin.git" "$FR/me" 2>/dev/null; git -C "$FR/me" checkout -q -b main 2>/dev/null
echo 0 > "$FR/me/f"; git -C "$FR/me" add -A; git -C "$FR/me" commit -q -m base; git -C "$FR/me" push -q origin main 2>/dev/null; f0="$(git -C "$FR/me" rev-parse HEAD)"
git clone -q "$FR/origin.git" "$FR/other" 2>/dev/null; git -C "$FR/other" checkout -q main 2>/dev/null
for n in 1 2 3; do echo "o$n" > "$FR/other/o$n"; git -C "$FR/other" add -A; GIT_AUTHOR_DATE="2020-01-0${n}T00:00:00" GIT_COMMITTER_DATE="2020-01-0${n}T00:00:00" git -C "$FR/other" commit -q -m "foreign$n"; done
git -C "$FR/other" push -q origin main 2>/dev/null
SINCE="$(( $(date +%s) - 120 ))"
echo mine > "$FR/me/m"; git -C "$FR/me" add -A; git -C "$FR/me" commit -q -m mine
git -C "$FR/me" push -q origin main 2>/dev/null; git -C "$FR/me" pull -q --rebase origin main 2>/dev/null; git -C "$FR/me" push -q origin main 2>/dev/null
fm="$(git -C "$FR/me" rev-parse HEAD)"
oac(){ bash -c 'source "$1"; ovn_oa_commits "$2" "$3" "$4" "$5"' _ "${1:-$LIB}" "$FR/me" "$f0" "$fm" "$SINCE" | "$PY" -c 'import json,sys; print(len(json.load(sys.stdin)))'; }
ok "F3 precondition: head_before IS still an ancestor, yet plain rev-list head_before..head_after holds 4 commits (3 upstream + mine)" "[ \"\$(git -C '$FR/me' rev-list --count '$f0..$fm')\" = 4 ]"
ok "F3a rebased/merged clone: commits = only the cycle's own commit (not the 3 upstream ones)" "[ \"\$(oac)\" = 1 ]"
ok "F3b python twin agrees (CLI --since)" "[ \"\$('$PY' '$ACCT' commits '$FR/me' '$f0' '$fm' --since '$SINCE' | '$PY' -c 'import json,sys; print(len(json.load(sys.stdin)))')\" = 1 ]"
mutate "$LIB" '  if [ -n "$since" ]; then' '  if false; then' "$tmp/mut_lib_oc.sh" && nok "MUTANT linear-only rev-list (the old behaviour) is caught by F3a" "[ \"\$(oac '$tmp/mut_lib_oc.sh')\" = 1 ]"
mutate "$ACCT" '    if since is None:
        r = _git(repo_dir, "rev-list"' '    if True:
        r = _git(repo_dir, "rev-list"' "$tmp/mut_acct_oc.py" && nok "MUTANT python twin without the diverged branch is caught by F3b" "[ \"\$('$PY' '$tmp/mut_acct_oc.py' commits '$FR/me' '$f0' '$fm' --since '$SINCE' | '$PY' -c 'import json,sys; print(len(json.load(sys.stdin)))')\" = 1 ]"
mutate "$LIB" "awk -v s=\"\$since\" '\$2 + 0 >= s + 0 { print \$1 }'" "cat" "$tmp/mut_lib_oc2.sh" && nok "MUTANT diverged branch without the since filter is caught by F3a" "[ \"\$(oac '$tmp/mut_lib_oc2.sh')\" = 1 ]"
ok "F3c a cycle that made 2 commits and was not rebased still names both (since = its start)" "[ \"\$(bash -c 'source \"$LIB\"; ovn_oa_commits \"$rd\" \"$c0\" \"$c2\" 1' | '$PY' -c 'import json,sys; print(len(json.load(sys.stdin)))')\" = 2 ]"
mutate "$ACCT" '        if len(parts) == 2 and int(parts[1]) >= since:' '        if len(parts) == 2:' "$tmp/mut_acct_oc3.py" && nok "MUTANT python twin without the since filter is caught by F3b" "[ \"\$('$PY' '$tmp/mut_acct_oc3.py' commits '$FR/me' '$f0' '$fm' --since '$SINCE' | '$PY' -c 'import json,sys; print(len(json.load(sys.stdin)))')\" = 1 ]"

# F4 (defect 4): every red marker format shows a red test, a pure timeout stays a pure timeout
cls(){ # <lib> <line> -> pure|red   (a log with the marker rc=124 after the given line)
  local lf="$tmp/cls.$RANDOM.log"; printf 'collecting ...\n%b\n--- verify-suite-red: repo-script in . rc=124 ---\n' "$2" > "$lf"
  ( source "$RILIB"; source "$1"; ovn_vt_classify "$lf" 0 && echo pure || echo red )
}
for fmt in '[gw3] [ 45%] FAILED tests/test_x.py::test_y' 'tests/test_x.py::test_y FAILED  [ 12%]' 'FAIL: test_a (mod.T)' 'ERROR: test_b (mod.T)' 'com.x.FooTest > bar FAILED' \
           'error TS2304: Cannot find name' '  [Failed]  test_x' "Test Case '-[A b]' failed (0.1 seconds)" '\033[31mF\033[0m' '\033[31mFAILED\033[0m tests/a.py' '\033[1;31m..F..\033[0m  [ 10%]'; do
  ok "F4 red format is NOT a pure timeout: $fmt" "[ \"\$(cls '$LIB' \"\$fmt\")\" = red ]"
done
ok "F4 control: all-green progress IS a pure timeout" "[ \"\$(cls '$LIB' 'tests/a.py ..s..  [ 10%]')\" = pure ]"
# NOTE: the gradle pattern (' > .+ FAILED$') is redundant with the generic ' FAILED' end-of-line pattern, so removing it alone is an EQUIVALENT mutant; the F4 gradle line is proven by the generic pattern.
mutate "$LIB" "    -e 'error TS[0-9]+' \\" "    -e 'ZZZerror TS[0-9]+' \\" "$tmp/mut_cls2.sh" && nok "MUTANT tsc pattern removed is caught" "[ \"\$(cls '$tmp/mut_cls2.sh' 'error TS2304: Cannot find name')\" = red ]"
mutate "$LIB" "sed \$'s/\\033\\\\[[0-9;]*[A-Za-z]//g'" "cat" "$tmp/mut_cls3.sh" && nok "MUTANT ANSI strip removed is caught" "[ \"\$(cls '$tmp/mut_cls3.sh' '\\033[1;31m..F..\\033[0m  [ 10%]')\" = red ]"
mutate "$LIB" "    -e '^(FAIL|ERROR): ' \\" "    -e 'ZZZ^(FAIL|ERROR): ' \\" "$tmp/mut_cls4.sh" && nok "MUTANT unittest pattern removed is caught" "[ \"\$(cls '$tmp/mut_cls4.sh' 'FAIL: test_a (mod.T)')\" = red ]"
mutate "$LIB" "    -e '^ *\\[Failed\\]' \\" "    -e 'ZZZ^ *\\[Failed\\]' \\" "$tmp/mut_cls5.sh" && nok "MUTANT GUT text pattern removed is caught" "[ \"\$(cls '$tmp/mut_cls5.sh' '  [Failed]  test_x')\" = red ]"
mutate "$LIB" "    -e '^Test Case .* failed' && return 1" "    -e 'ZZZ^Test Case .* failed' && return 1" "$tmp/mut_cls6.sh" && nok "MUTANT xcode pattern removed is caught" "[ \"\$(cls '$tmp/mut_cls6.sh' \"Test Case '-[A b]' failed (0.1 seconds)\")\" = red ]"

# F6 (defect 6): landed-late rows are not lane attempts in the idle-lane / supply readers
F6="$tmp/F6"; mkdir -p "$F6"
"$PY" - "$F6/outcomes.jsonl" "$(iso 7200)" "$(iso 60)" <<'EOF'
import json, sys
out, t_old, t_new = sys.argv[1:]
base = {"repo": "r1", "id": "ongoing-r1", "type": "aider_fix", "tier": "2", "category": "python", "attempt": 1, "attempts": 1, "fail_reason": "", "tokens_sent": 0, "tokens_recv": 0, "item_hash": "h1", "feat_tag": ""}
rows = [dict(base, ts=t_old, **{"class": "landed", "severity": "good", "status": "pushed(tests:pass)", "duration_s": 60}),
        dict(base, ts=t_new, **{"class": "landed-late", "severity": "neutral", "status": "landed-late(held-commit)", "duration_s": 0})]
open(out, "w").write("\n".join(json.dumps(r) for r in rows) + "\n")
EOF
lastreal(){ OVN_NOTIFY_STATE="$F6/st" "$PY" - "${1:-$ROOT/scripts/ovn_notify.py}" "$F6" <<'EOF'
import importlib.util, os, sys, shutil, calendar, time, json
src, d = sys.argv[1:]
t_old = json.loads(open(d + "/outcomes.jsonl").readline())["ts"]   # the OLD (real) row's own timestamp
os.makedirs(d + "/st", exist_ok=True); shutil.copy(d + "/outcomes.jsonl", d + "/st/outcomes.jsonl")
spec = importlib.util.spec_from_file_location("nt", src); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
last, first = m._last_real_attempts()
want = calendar.timegm(time.strptime(t_old, "%Y-%m-%dT%H:%M:%SZ"))
print("old" if last.get("r1") == want else "refreshed")
EOF
}
ok "F6a ovn_notify: a landed-late row does NOT refresh the lane's last real attempt" "[ \"\$(lastreal)\" = old ]"
mutate "$ROOT/scripts/ovn_notify.py" 'd.get("class") in ("skipped", "landed-late")' 'd.get("class") in ("skipped",)' "$tmp/mut_nt.py" && nok "MUTANT notify counting landed-late is caught by F6a" "[ \"\$(lastreal '$tmp/mut_nt.py')\" = old ]"
ledger_rows(){ "$PY" - "${1:-$ROOT/scripts/ovn_supply_ledger.py}" <<'EOF'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("sl", sys.argv[1]); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
print("late-is-work" if not m._is_skip({"class": "landed-late", "status": "landed-late(held-commit)"}) else "late-skipped", "skip-ok" if m._is_skip({"class": "skipped"}) else "skip-broken", "real-ok" if not m._is_skip({"class": "landed", "status": "pushed(x)"}) else "real-broken")
EOF
}
ok "F6b supply ledger: landed-late is not work; skip and real rows classify as before" "[ \"\$(ledger_rows)\" = 'late-skipped skip-ok real-ok' ]"
mutate "$ROOT/scripts/ovn_supply_ledger.py" 'r.get("class") in ("skipped", "landed-late")' 'r.get("class") in ("skipped",)' "$tmp/mut_sl.py" && nok "MUTANT ledger counting landed-late as work is caught by F6b" "[ \"\$(ledger_rows '$tmp/mut_sl.py')\" = 'late-skipped skip-ok real-ok' ]"

# F7 (defect 7): per-branch patch-id cache + incremental writes. 12 stale candidates must cost ONE patch-id window per (repo, branch), and a kill mid-run keeps rows already written
F7="$tmp/F7"; mkdir -p "$F7/state" "$F7/repos"; git init -q --bare -b overnight/feature "$F7/origin.git"; git clone -q "$F7/origin.git" "$F7/repos/r1" 2>/dev/null; f7="$F7/repos/r1"
git -C "$f7" checkout -q -b overnight/feature 2>/dev/null; echo 0 > "$f7/f"; git -C "$f7" add -A; git -C "$f7" commit -q -m base; git -C "$f7" push -q origin overnight/feature 2>/dev/null; g_0="$(git -C "$f7" rev-parse HEAD)"
echo landed > "$f7/l"; git -C "$f7" add -A; git -C "$f7" commit -q -m landable; g_l="$(git -C "$f7" rev-parse HEAD)"; git -C "$f7" push -q origin overnight/feature 2>/dev/null
shas=""; for n in 1 2 3 4 5 6 7 8 9 10 11 12; do git -C "$f7" checkout -q "$g_0" 2>/dev/null; echo "u$n" > "$f7/u$n"; git -C "$f7" add -A; git -C "$f7" commit -q -m "stale$n"; shas="$shas $(git -C "$f7" rev-parse HEAD)"; done
"$PY" - "$F7/state/outcomes.jsonl" "$g_0" "$g_l" $shas <<'EOF'
import json, sys, time
out, g0, gl = sys.argv[1:4]; stale = sys.argv[4:]
def iso(a): return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() - a))
base = {"repo": "r1", "id": "ongoing-r1", "type": "aider_fix", "tier": "2", "category": "python", "class": "error", "severity": "neutral", "attempt": 1, "attempts": 1, "status": "error(verify-skipped)", "head_before": g0}
rows = [dict(base, ts=iso(1000), commits=[gl], head_after=gl, item_hash="L")]   # the landable row is FIRST (file order = processing order)
rows += [dict(base, ts=iso(900 - i), commits=[sh], head_after=sh, item_hash="s%d" % i) for i, sh in enumerate(stale)]
open(out, "w").write("\n".join(json.dumps(r) for r in rows) + "\n")
EOF
cp "$F7/state/outcomes.jsonl" "$tmp/f7.in"
f7calls(){ cp "$tmp/f7.in" "$F7/state/outcomes.jsonl"; rm -f "$F7/state/outcome_reconcile.lock"; "$PY" - "${1:-$ACCT}" "$F7" <<'EOF'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("oa", sys.argv[1]); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
n = [0]; real = m._patch_ids
def counting(*a, **k): n[0] += 1; return real(*a, **k)
m._patch_ids = counting
rows = m.reconcile(sys.argv[2] + "/state", sys.argv[2] + "/repos", ("overnight/feature",))
print(n[0], len(rows))
EOF
}
ok "F7a 12 never-landing candidates + 1 landable: ONE patch-id window for the branch, the landable one still lands" "[ \"\$(f7calls)\" = '1 1' ]"
mutate "$ACCT" '    cache = {}
    out = []' '    cache = None
    out = []' "$tmp/mut_acct_c.py" && nok "MUTANT no per-run cache (patch-ids recomputed per candidate) is caught by F7a" "[ \"\$(f7calls '$tmp/mut_acct_c.py')\" = '1 1' ]"
f7kill(){ cp "$tmp/f7.in" "$F7/state/outcomes.jsonl"; rm -f "$F7/state/outcome_reconcile.lock"; "$PY" - "${1:-$ACCT}" "$F7" <<'EOF' >/dev/null 2>&1
import importlib.util, os, sys
spec = importlib.util.spec_from_file_location("oa", sys.argv[1]); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
real = m.landed_branch; calls = [0]
def killing(*a, **k):
    calls[0] += 1
    r = real(*a, **k)
    if calls[0] == 2:        # the landable row (candidate #1) is already written; the 60 s cap kills the process while the second candidate is being checked
        os._exit(9)
    return r
m.landed_branch = killing
m.reconcile(sys.argv[2] + "/state", sys.argv[2] + "/repos", ("overnight/feature",))
EOF
  grep -c landed-late "$F7/state/outcomes.jsonl" || true; }
ok "F7b incremental write: the row proven before the kill is on disk when the process dies mid-loop" "[ \"\$(f7kill)\" = 1 ]"
mutate "$ACCT" '                fh.flush()' '                pass' "$tmp/mut_acct_f.py" && nok "MUTANT row buffered (no flush) is lost by the kill and caught by F7b" "[ \"\$(f7kill '$tmp/mut_acct_f.py')\" = 1 ]"

# F8 (defect 8): the stage runner's unverified row (class noop, status no-op(stage-unverified)) is a reconcile candidate; a plain no-op revert still is not
F8="$tmp/F8"; mkdir -p "$F8/state" "$F8/repos"; cp -R "$D/origin.git" "$F8/origin.git"; git clone -q "$F8/origin.git" "$F8/repos/r1" 2>/dev/null
"$PY" - "$F8/state/outcomes.jsonl" "$(iso 100)" "$(iso 90)" "$d0" "$d1" <<'EOF'
import json, sys
out, t1, t2, d0, d1 = sys.argv[1:]
base = {"repo": "r1", "id": "ongoing-r1", "type": "aider_fix", "tier": "3", "category": "python", "class": "noop", "severity": "bad", "attempt": 1, "attempts": 1, "commits": [d1], "head_before": d0, "head_after": d1}
open(out, "w").write(json.dumps(dict(base, ts=t1, status="no-op(stage-unverified) stage(runner)", item_hash="su")) + "\n" + json.dumps(dict(base, ts=t2, status="no-op(reverted-red)", item_hash="rv")) + "\n")
EOF
cp "$F8/state/outcomes.jsonl" "$tmp/f8.in"
f8run(){ cp "$tmp/f8.in" "$F8/state/outcomes.jsonl"; "$PY" "${1:-$ACCT}" reconcile --state-dir "$F8/state" --repos-dir "$F8/repos" --branches overnight/feature >/dev/null 2>&1; grep -c 'landed-late(held-commit)' "$F8/state/outcomes.jsonl" || true; }
ok "F8a stage-unverified noop row with its commits on origin: ONE landed-late row (the plain no-op(reverted-red) row gets none)" "[ \"\$(f8run)\" = 1 ] && grep -q 'late_of_status\":\"no-op(stage-unverified)' '$F8/state/outcomes.jsonl'"
mutate "$ACCT" 'str(row.get("status", "")).startswith("no-op(stage-unverified)")' 'False' "$tmp/mut_acct_s.py" && nok "MUTANT stage-unverified rows not candidates is caught by F8a" "[ \"\$(f8run '$tmp/mut_acct_s.py')\" = 1 ]"

# ============================== E. old-format rows still parse in the readers ==============================
E="$tmp/E"; mkdir -p "$E/state" "$E/logs"
"$PY" - "$E/state/outcomes.jsonl" "$(iso 1800)" "$(iso 1200)" "$(iso 900)" "$(iso 600)" "$c0" "$c2" <<'EOF'
import json, sys
out, t1, t2, t3, t4, c0, c2 = sys.argv[1:]
base = {"repo": "repoA", "id": "ongoing-repoA", "type": "aider_fix", "tier": "2", "category": "python", "attempt": 1, "attempts": 1, "bestn_stop": "", "fail_reason": "", "tokens_sent": 1, "tokens_recv": 1, "duration_s": 100, "item_hash": "x", "feat_tag": ""}
rows = [dict(base, ts=t1, **{"class": "landed", "severity": "good", "status": "pushed(tests:pass)"}),                                   # OLD format: no commit fields
        dict(base, ts=t2, **{"class": "landed", "severity": "good", "status": "pushed(tests:pass)", "commits": [c2], "head_before": c0, "head_after": c2}),
        dict(base, ts=t3, **{"class": "held", "severity": "neutral", "status": "error(verify-timeout-held - x)", "commits": [c2], "head_before": c0, "head_after": c2}),
        dict(base, ts=t4, **{"class": "landed-late", "severity": "neutral", "status": "landed-late(held-commit)", "commits": [c2], "late_of_ts": t3, "landed_branch": "main"}),
        dict(base, ts=t4, **{"class": "landed", "severity": "good", "status": "pushed(tests:pass)", "commits": "garbage", "head_before": 7})]   # malformed new fields must not break a reader
open(out, "w").write("\n".join(json.dumps(r) for r in rows) + "\n")
EOF
ok "E1 buckets: landed-late is benign (never good, never bad); old rows bucket as before" "'$PY' -c \"
import sys,json; sys.path.insert(0,'$ROOT/scripts'); import ovn_outcome_buckets as b
rows=[json.loads(l) for l in open('$E/state/outcomes.jsonl')]
assert [b.bucket_from_outcome_row(r) for r in rows]==['good','good','benign','benign','good'], [b.bucket_from_outcome_row(r) for r in rows]
assert b.count_landed_late(rows)==1 and b.landed_late_label(1)=='1 landed-late' and b.landed_late_label(0)==''
assert b.bucket_from_outcome_row({'class':'landed-late','severity':'good'})=='benign'
\""
ok "E2 ovn_real_passrate: runs on mixed rows, counts the 3 landings + 0 bad (landed-late and held excluded)" "'$PY' '$ROOT/scripts/ovn_real_passrate.py' --state '$E/state' | grep -q '3 good+bad\\|100.0% (3 / 3\\|3 good'"
ok "E3 ovn_stats --real (the pass-rate section reading outcomes.jsonl): exit 0" "OVN_STATE_DIR='$E/state' '$PY' '$ROOT/scripts/ovn_stats.py' 24 --real"
ok "E4 ovn_cycle_walltime: exit 0 on mixed rows" "'$PY' '$ROOT/scripts/ovn_cycle_walltime.py' '$E/state' '$E/logs'"
mkdir -p "$E/repos"; cp -R "$rd" "$E/repos/repoA" 2>/dev/null; for r in origin/overnight/feature origin/develop origin/main; do git -C "$E/repos/repoA" update-ref "refs/remotes/$r" HEAD; done
run_qa(){ env -i PATH="/usr/bin:/bin:$(dirname "$PY")" HOME="$tmp" NTFY_SERVER=http://127.0.0.1:9 OVN_DIR="$E" OVN_REPOS_DIR="$E/repos" "$PY" "$ROOT/qa/qa_ledger.py" derive --no-record --no-events; }
ok "E5 qa_ledger derive: mixed old/new/malformed rows do not crash it" "run_qa"
ok "E6 qa_ledger: landed-late and held rows are not ledgered; the landed rows are (outcome_commits only where the row had valid shas)" "'$PY' -c \"
import json
recs=[json.loads(l) for l in open('$E/state/qa_ledger.jsonl')]
landed=[r for r in recs if r.get('kind')=='landed']
assert len(landed)==3, len(landed)
assert sum(1 for r in landed if 'outcome_commits' in r)==1, [r.get('outcome_commits') for r in landed]
\""

echo; echo "$P passed, $F failed"; [ "$F" = 0 ]
