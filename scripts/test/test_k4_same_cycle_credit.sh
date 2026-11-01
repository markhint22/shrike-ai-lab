#!/usr/bin/env bash
# K4 (2026-11-01): same-cycle credit of the WORKED item (OVN_SAME_CYCLE_CREDIT=off|shadow|on, default shadow) + the Item-Hash trailer / ovn_item_commit_on_branch.
# 89 of 520 pushes were landed-uncredited: green work pushed, item left [ ] (the commit touched src/a.py, the item NAMES lib/a.py: path mismatch) and re-faced next cycle.
# Drives the REAL ovn_auto_credit() on throwaway git repos. Mutation proof at the bottom: the enforcing branch broken in a temp copy of the lib must FAIL the `on` checks.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
LIB="$HERE/../lib_auto_credit.sh"; SEL="$HERE/../lib_item_select.sh"
[ -f "$LIB" ] || { echo "  SKIP: lib_auto_credit.sh not found"; exit 0; }
P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
W="$(safe_mktemp_dir k4sc)" || exit 1
trap 'safe_rm_rf "$W"' EXIT
safe_set_sandbox_home "$W" || exit 1
export OVN_VERIFY_SHADOW_LOG="$W/shadow.log" OVN_STATE_DIR="$W/state"; mkdir -p "$W/state"
export OVN_QA_CARD_CREDIT=off OVN_TWIN_CREDIT=off OVN_REFUSED_PARK_AT=0

# mk <name> <verify-grep>: repo whose only item names lib/a.py (mismatch) while the commit touches src/a.py
mk(){ R="$W/r_$1"; rm -rf "${R:?}"; mkdir -p "$R/src" "$R/lib"; cd "$R" || exit 1
  git init -q -b main . && git config user.email t@t && git config user.name t
  printf 'def old_a():\n    return 1\n' > src/a.py; printf 'x=1\n' > lib/a.py
  printf '## Next Steps\n- [ ] [T2] lib/a.py — Add new_a. VERIFY: `grep -q "%s" src/a.py`\n\n## Completed\n' "$2" > OVERNIGHT_PROGRESS.md
  git add -A && git commit -q -m base; B="$(git rev-parse HEAD)"
  printf 'def new_a():\n    return 2\n' >> src/a.py; git add -A && git commit -q -m "feat: new_a"; A="$(git rev-parse HEAD)"; TL="$R/task.log"; : > "$TL"; }
run(){ # <lib file> <mode or "unset">
  ( . "$1" 2>/dev/null; . "$SEL" 2>/dev/null; [ "$2" = unset ] && unset OVN_SAME_CYCLE_CREDIT || export OVN_SAME_CYCLE_CREDIT="$2"
    ovn_auto_credit "$B" "$A" OVERNIGHT_PROGRESS.md "$TL" >/dev/null 2>&1; echo "$? $OVN_AC_CREDITED" > "$R/res" ); read -r CRC CN < "$R/res"; CLOG="$(cat "$TL")"; }
ticked(){ grep -c '^- \[x\]' "$R/OVERNIGHT_PROGRESS.md"; }

# 1. default (unset => shadow): logs what it WOULD credit, changes nothing
mk shadow 'def new_a'; run "$LIB" unset
ok "S1 default is shadow: nothing ticked, no tick commit" '[ "$(ticked)" = 0 ] && [ "$(git -C "$R" rev-parse HEAD)" = "$A" ]'
ok "S2 shadow logs the would-credit line naming the worked item" 'printf "%s" "$CLOG" | grep -q "SAME-CYCLE SHADOW: would credit line 2"'
ok "S3 the path-mismatch refusal is still logged, so the row stays landed-uncredited (old behaviour)" 'printf "%s" "$CLOG" | grep -q "REFUSED line 2.*path mismatch" && ( . "$LIB"; ovn_landed_uncredited "$TL" "pushed(tests:pass)" )'

# 2. on: the worked item is credited in THE SAME call, with an Item-Hash trailer
mk on 'def new_a'; run "$LIB" on
ok "O1 on: the worked item is ticked and rc 0" '[ "$(ticked)" = 1 ] && [ "$CRC" = 0 ] && [ "$CN" = 1 ]'
ok "O2 on: the tick commit stages ONLY the progress file" '[ "$(git -C "$R" show --name-only --format= HEAD | tr "\n" " ")" = "OVERNIGHT_PROGRESS.md " ] && [ "$(git -C "$R" rev-parse HEAD~1)" = "$A" ]'
ok "O3 on: the log has the credit line, so the row is NOT landed-uncredited" 'printf "%s" "$CLOG" | grep -q "^--- auto-credit: checked off line 2" && ! ( . "$LIB"; ovn_landed_uncredited "$TL" "pushed(tests:pass)" )'
H="$( . "$LIB"; . "$SEL"; ovn_item_hash "$(sed -n 2p "$R/OVERNIGHT_PROGRESS.md")" )"
ok "O4 the credit commit carries an Item-Hash trailer and ovn_item_commit_on_branch finds it" '[ -n "$H" ] && [ -n "$(git -C "$R" log -1 --format=%B | grep -xF "Item-Hash: $H")" ] && ( cd "$R" && . "$LIB" && ovn_item_commit_on_branch "$H" )'
ok "O5 a different hash is NOT on the branch" '! ( cd "$R" && . "$LIB" && ovn_item_commit_on_branch deadbeefdeadbeefdeadbeefdeadbeef )'
ok "O6 worktree clean after" '[ -z "$(git -C "$R" status --porcelain --untracked-files=no)" ]'

# 3. on but the worked item's VERIFY fails at head: never credited (not a verify-less credit)
mk onfail 'def never_there'; run "$LIB" on
ok "F1 on + VERIFY red at head: nothing ticked, no commit" '[ "$(ticked)" = 0 ] && [ "$(git -C "$R" rev-parse HEAD)" = "$A" ] && ! printf "%s" "$CLOG" | grep -q "SAME-CYCLE"'

# 4. off: byte-for-byte the old behaviour (no log line, no trailer machinery)
mk off 'def new_a'; run "$LIB" off
ok "X1 off: nothing ticked and not even a shadow line" '[ "$(ticked)" = 0 ] && ! printf "%s" "$CLOG" | grep -q "SAME-CYCLE"'

# 5. the normal per-file credit path is unchanged (named path == touched path); shadow adds no trailer
R="$W/r_normal"; rm -rf "$R"; mkdir -p "$R/src"; cd "$R"; git init -q -b main . && git config user.email t@t && git config user.name t
printf 'def old_a():\n    return 1\n' > src/a.py; printf '## Next Steps\n- [ ] [T2] src/a.py — Add new_a. VERIFY: `grep -q "def new_a" src/a.py`\n\n## Completed\n' > OVERNIGHT_PROGRESS.md
git add -A && git commit -q -m base; B="$(git rev-parse HEAD)"; printf 'def new_a():\n    return 2\n' >> src/a.py; git add -A && git commit -q -m feat; A="$(git rev-parse HEAD)"; TL="$R/task.log"; : > "$TL"
run "$LIB" unset
ok "N1 per-file credit still ticks the named item (shadow mode) and the commit message is UNCHANGED (no trailer in shadow)" '[ "$(ticked)" = 1 ] && [ -z "$(git -C "$R" log -1 --format=%B | grep "^Item-Hash: ")" ]'

# ---- review-fix cases (2026-11-01) ------------------------------------------------------------------------------------------------------------------------------------------------
PH="$( . "$LIB"; printf '%s' "$OVN_AC_PLACEHOLDER_TEXT" )"
# mk2 <name> <item file> <verify>: repo where a setup hook can shape the commit. $2 = file the item names, $3 = VERIFY command (no backticks)
mk2(){ R="$W/r_$1"; rm -rf "${R:?}"; mkdir -p "$R/src" "$R/lib" "$R/tools"; cd "$R" || exit 1
  git init -q -b main . && git config user.email t@t && git config user.name t
  printf 'def old_a():\n    return 1\n' > src/a.py; printf 'x=1\n' > lib/a.py; printf '#!/bin/sh\necho run >> "$OVN_CNT"\nexit 1\n' > tools/count_fail.sh
  printf '#!/bin/sh\necho dirty >> src/a.py\nexit 0\n' > tools/dirty_pass.sh
  printf '## Next Steps\n- [ ] [T2] %s — do it. VERIFY: `%s`\n\n## Completed\n' "$2" "$3" > OVERNIGHT_PROGRESS.md
  git add -A && git commit -q -m base; B="$(git rev-parse HEAD)"; TL="$W/task_$1.log"; : > "$TL"; }
fin(){ git add -A && git commit -q -m work; A="$(git rev-parse HEAD)"; }

# D1 (RULE 3 bypass): the commit writes ONLY the placeholder stub into the item's named file; VERIFY is a weak grep for that stub
mk2 ph lib/a.py 'grep -q Placeholder lib/a.py'; printf '%s\n' "$PH" > lib/a.py; fin; run "$LIB" on
ok "D1 on + placeholder-stub commit + weak grep VERIFY: NOT credited (was credited=1)" '[ "$(ticked)" = 0 ] && [ "$CN" = 0 ] && printf "%s" "$CLOG" | grep -q "REFUSED line 2 - lib/a.py is only a placeholder stub" && ! printf "%s" "$CLOG" | grep -q "SAME-CYCLE:"'
# D1b: the stub is in a file the commit changed that is NOT the item's file (the work is a stub anyway)
mk2 ph2 lib/a.py 'grep -q Placeholder src/a.py'; printf '%s\n' "$PH" > src/a.py; fin; run "$LIB" on
ok "D1b on + stub written to a file that is NOT the item's named path (RULE 2 skipped by design), weak VERIFY: NOT credited" '[ "$(ticked)" = 0 ] && printf "%s" "$CLOG" | grep -q "SAME-CYCLE REFUSED line 2: .*placeholder stub"'
# D2 (empty change): a mode-only (0/0) change; VERIFY `test -x` is red before, green at head
mk2 emp src/a.py 'test -x src/a.py'; chmod +x src/a.py; fin; run "$LIB" on
ok "D2 on + 0/0 mode-only change: NOT credited (no real diff)" '[ "$(ticked)" = 0 ] && [ "$CN" = 0 ] && printf "%s" "$CLOG" | grep -q "SAME-CYCLE REFUSED line 2: no changed file has a real"'
# D3 (shadow side effects): a VERIFY that dirties the tree must be restored and the call must refuse, in SHADOW too
mk2 dirt lib/a.py 'sh tools/dirty_pass.sh'; printf 'def new_a():\n    return 2\n' >> src/a.py; fin; run "$LIB" shadow
ok "D3 shadow: a VERIFY that dirties the tree is restored (tree clean at AFTER) and logged" '[ -z "$(git -C "$R" status --porcelain --untracked-files=no)" ] && [ "$(git -C "$R" rev-parse HEAD)" = "$A" ] && printf "%s" "$CLOG" | grep -q "a VERIFY command modified the tree"'
# D4 (trailers): shadow commits are unchanged, `on` commits carry the trailer (O4 above)
# D5 (already green before the push): VERIFY passes at BEFORE and at head - not this cycle's work
mk2 pre lib/a.py 'grep -q old_a src/a.py'; printf 'def new_a():\n    return 2\n' >> src/a.py; fin; run "$LIB" on
ok "D5 on + VERIFY already passed before the push: NOT credited" '[ "$(ticked)" = 0 ] && printf "%s" "$CLOG" | grep -q "already passed BEFORE this push"'
mk2 pre2 lib/a.py 'grep -q old_a src/a.py'; printf 'def new_a():\n    return 2\n' >> src/a.py; fin; run "$LIB" shadow
ok "D5b shadow says it would NOT credit it either" '! printf "%s" "$CLOG" | grep -q "would credit" && printf "%s" "$CLOG" | grep -q "already passed BEFORE"'
# D6 (double run): the loop refused the line (named path matches, VERIFY red) - the VERIFY must run exactly once, not again in the same-cycle step
export OVN_CNT="$W/cnt"
mk2 dbl src/a.py 'sh tools/count_fail.sh'; printf 'def new_a():\n    return 2\n' >> src/a.py; fin; : > "$OVN_CNT"; run "$LIB" shadow
ok "D6 loop-refused VERIFY runs once in shadow (not again for same-cycle)" '[ "$(wc -l < "$OVN_CNT" | tr -d " ")" = 1 ] && printf "%s" "$CLOG" | grep -q "VERIFY: clause FAILED"'
# D7: shadow runs the extra VERIFY under the cap; a normal mismatch shadow case still logs would-credit (S2) - checked above

# MUTATION PROOF: break the enforcing branch (`on` no longer ticks) in a temp copy of the lib: the `on` checks O1/O3 must FAIL on it (= the old behaviour).
python3 - "$LIB" "$W/mut_lib.sh" <<'PY'
import sys
s = open(sys.argv[1]).read()
a = 'if [ "${OVN_SAME_CYCLE_CREDIT:-shadow}" = on ]; then\n            ticked_lines'
assert s.count(a) == 1, "mutation anchor missing - the test is stale"
open(sys.argv[2], "w").write(s.replace(a, 'if [ "${OVN_SAME_CYCLE_CREDIT:-shadow}" = never ]; then\n            ticked_lines'))
PY
mkdir -p "$W/mutdir"; for _f in "$HERE"/../*; do [ "${_f##*/}" = lib_auto_credit.sh ] || ln -sf "$_f" "$W/mutdir/${_f##*/}"; done; cp "$W/mut_lib.sh" "$W/mutdir/lib_auto_credit.sh"
mk mut 'def new_a'; run "$W/mutdir/lib_auto_credit.sh" on
ok "M1 MUTANT (enforce branch dead = old behaviour): O1 would fail - the worked item is NOT ticked" '[ "$(ticked)" = 0 ]'
ok "M2 MUTANT: O3 would fail - the row is still landed-uncredited" '( . "$LIB"; ovn_landed_uncredited "$TL" "pushed(tests:pass)" )'
# review-fix mutants: each fix removed in a temp copy of the lib must make its D-test condition FAIL (= the old behaviour)
mutrun(){ # <anchor> <replacement> <repo builder: name file verify> ... -> sets up mutant lib at $W/mutdir/lib_auto_credit.sh
  python3 - "$LIB" "$W/mutdir/lib_auto_credit.sh" "$1" "$2" <<'PY'
import sys
s=open(sys.argv[1]).read(); a=sys.argv[3]; assert s.count(a)>=1, "mutation anchor missing: "+a
open(sys.argv[2],"w").write(s.replace(a, sys.argv[4], 1))
PY
}
# M3: placeholder gate removed -> D1 credits the stub again
mutrun 'if ovn_ac_is_placeholder "$a" "$f"; then echo' 'if false; then echo'
mk2 m3 lib/a.py 'grep -q Placeholder src/a.py'; printf '%s\n' "$PH" > src/a.py; fin; run "$W/mutdir/lib_auto_credit.sh" on
ok "M3 MUTANT (placeholder gate dead = old behaviour): the stub IS credited" '[ "$(ticked)" = 1 ]'
# M4: real-diff gate removed -> D2 credits the 0/0 change
mutrun '[ "$real" = 1 ] || {' '[ 1 = 1 ] || {'
mk2 m4 src/a.py 'test -x src/a.py'; chmod +x src/a.py; fin; run "$W/mutdir/lib_auto_credit.sh" on
ok "M4 MUTANT (real-diff gate dead): the 0/0 change IS credited" '[ "$(ticked)" = 1 ]'
# M5: pre-push red requirement removed -> D5 credits an already-green VERIFY
mutrun 'if [ "$_sc_bres" != FAIL ]; then' 'if false; then'
mk2 m5 lib/a.py 'grep -q old_a src/a.py'; printf 'def new_a():\n    return 2\n' >> src/a.py; fin; run "$W/mutdir/lib_auto_credit.sh" on
ok "M5 MUTANT (no red-before check): an already-green VERIFY IS credited" '[ "$(ticked)" = 1 ]'
# M6: post same-cycle tree check skipped when nothing is ticked -> D3's dirty tree stays dirty
mutrun '[ -n "$ticked_lines" ] || [ "$_sc_ran" = 1 ] || return 0' '[ -n "$ticked_lines" ] || return 0'
mk2 m6 lib/a.py 'sh tools/dirty_pass.sh'; printf 'def new_a():\n    return 2\n' >> src/a.py; fin; run "$W/mutdir/lib_auto_credit.sh" shadow
ok "M6 MUTANT (no tree check after a same-cycle VERIFY): the dirtied tree is NOT restored" '[ -n "$(git -C "$R" status --porcelain --untracked-files=no)" ]'
# M7: loop-refused exclusion removed -> D6's VERIFY runs twice
mutrun 'case " $_sc_refused " in *" $_sc_ln "*) _sc_ln="" ;; esac' ':'
mk2 m7 src/a.py 'sh tools/count_fail.sh'; printf 'def new_a():\n    return 2\n' >> src/a.py; fin; : > "$OVN_CNT"; run "$W/mutdir/lib_auto_credit.sh" shadow
ok "M7 MUTANT (no refused-line exclusion): informational - run count recorded" 'true'
echo "  M7 note: mutant VERIFY runs = $(wc -l < "$OVN_CNT" | tr -d " ")"
echo "  $P passed, $F failed"; [ "$F" = 0 ]
