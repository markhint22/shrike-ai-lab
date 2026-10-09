#!/usr/bin/env bash
# Scout file guard (2026-10-02): the planner's FILES: must never force-load a hard-banned or oversize file into aider.
# Live incident (xlite): item "tests/test_battle_persistence.gd - add a test" -> planner FILES: scripts/battle/battle.gd (227KB, on
# .queue-hard-banned-files) -> 80,456-token request vs a 65,536 context -> ContextWindowExceededError 4 cycles in a row.
# Runs the REAL run_aider_fix_task via lib_ro_aider1_driver.sh scenarios sg_* (hermetic fake tree + stub aider), plus the pure
# --scout-guard / --park-line modes of ovn_park_unworkable.py and the downstream consumers of the new no-op(scout-unworkable) status.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
DRV="$HERE/lib_ro_aider1_driver.sh"
Q="$(cd "$HERE/../.." && pwd)"
pass=0; fail=0
ok(){ if [ "$2" = "1" ]; then pass=$((pass+1)); echo "  ok   $1"; else fail=$((fail+1)); echo "  FAIL $1"; fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
run(){ timeout 150 bash "$DRV" "$1" "$T/$1" > "$T/$1.out" 2>&1; }
res(){ cat "$T/$1/result" 2>/dev/null; }
rd(){ echo "$T/$1/repos/ro_aider1_repo"; }
tlog(){ cat "$T/$1/task.log" 2>/dev/null; }
implcall(){ cat "$T/$1/scn/calls/2.impl" 2>/dev/null; }
has(){ grep -qF -- "$2" <<<"$1" && echo 1 || echo 0; }
hasline(){ grep -qxF -- "$2" <<<"$1" && echo 1 || echo 0; }
b2i(){ [ "$1" = 0 ] && echo 1 || echo 0; }
noimpl(){ [ ! -f "$T/$1/scn/calls/2.impl" ] && echo 1 || echo 0; }

echo "== pure --scout-guard / --park-line modes =="
mkdir -p "$T/u/app" "$T/u/tests"; printf 'app/banned.py\nscripts/battle/\n' > "$T/u/.queue-hard-banned-files"
mkdir -p "$T/u/scripts/battle"; python3 -c "open('$T/u/scripts/battle/battle.gd','w').write('a'*230000)"
python3 -c "open('$T/u/app/big.py','w').write('a'*130000)"; echo x > "$T/u/app/banned.py"; echo x > "$T/u/app/ok.py"
printf -- '- [ ] [T2] tests/test_battle_persistence.gd — add a test that autosave resumes\n' > "$T/u/item.txt"
g(){ printf '%s\n' "$@" | python3 "$Q/ovn_park_unworkable.py" --scout-guard "$T/u" 120000 "$T/u/item.txt"; }
out="$(g scripts/battle/battle.gd)"
ok "xlite incident: banned+oversize battle.gd alone -> dropped AND unworkable" "$([ "$(grep -c '^DROP' <<<"$out")" = 1 ] && grep -q '^UNWORKABLE' <<<"$out" && echo 1 || echo 0)"
out="$(g scripts/battle/battle.gd tests/test_battle_persistence.gd)"
ok "battle.gd + the (new) test file -> battle.gd dropped, item still workable" "$([ "$(grep -c '^DROP' <<<"$out")" = 1 ] && ! grep -q '^UNWORKABLE' <<<"$out" && echo 1 || echo 0)"
out="$(g app/big.py app/ok.py)"
ok "oversize (>120000 bytes) but not banned is dropped; small sibling keeps it workable" "$(grep -q 'DROP.app/big.py.*KB' <<<"$out" && ! grep -q UNWORKABLE <<<"$out" && echo 1 || echo 0)"
out="$(g app/banned.py)"
ok "banned small file is dropped (ban list prefix match, not size)" "$(grep -q 'DROP.app/banned.py.hard-banned' <<<"$out" && grep -q UNWORKABLE <<<"$out" && echo 1 || echo 0)"
out="$(g app/ok.py tests/new_test.py datetime.now)"
ok "benign: small existing + new file + junk token -> nothing dropped, nothing unworkable" "$([ -z "$out" ] && echo 1 || echo 0)"
printf -- '- [ ] [T2] app/big.py — add a helper\n' > "$T/u/item.txt"
out="$(g app/big.py app/ok.py)"
ok "item's OWN target is the dropped file -> unworkable even though a small sibling survives" "$(grep -q UNWORKABLE <<<"$out" && echo 1 || echo 0)"
out="$(g app/ok.py)"
ok "target not planned at all -> no drop, no verdict" "$([ -z "$out" ] && echo 1 || echo 0)"
printf -- '# P\n- [ ] [T2] a\n- [ ] [CLAUDE] [unworkable: x] b\n- [x] c\n' > "$T/u/P.md"
ok "--park-line tags an open line with the sweep's tag format" "$([ "$(python3 "$Q/ovn_park_unworkable.py" --park-line "$T/u/P.md" 2 'why here')" = PARKED=1 ] && grep -q '^- \[ \] \[CLAUDE\] \[unworkable: why here\] \[T2\] a$' "$T/u/P.md" && echo 1 || echo 0)"
ok "--park-line is idempotent / refuses parked + done lines" "$([ "$(python3 "$Q/ovn_park_unworkable.py" --park-line "$T/u/P.md" 2 w)$(python3 "$Q/ovn_park_unworkable.py" --park-line "$T/u/P.md" 3 w)$(python3 "$Q/ovn_park_unworkable.py" --park-line "$T/u/P.md" 4 w)$(python3 "$Q/ovn_park_unworkable.py" --park-line "$T/u/P.md" 99 w)" = PARKED=0PARKED=0PARKED=0PARKED=0 ] && echo 1 || echo 0)"
ok "the sweep's own CLI is unchanged (PARKED=<n> for a progress file)" "$([ "$(python3 "$Q/ovn_park_unworkable.py" "$T/u/P.md" "$T/u")" = PARKED=0 ] && echo 1 || echo 0)"

echo "== run_aider_fix_task end to end =="
run sg_banned
ok "planner lists only a banned file -> no-op(scout-unworkable), aider implement NEVER called" "$([ "$(res sg_banned)" = 'no-op(scout-unworkable)' ] && echo "$(noimpl sg_banned)" || echo 0)"
ok "drop is logged with the reason" "$(has "$(tlog sg_banned)" 'scout-guard: dropped planned file app/banned.py (hard-banned file app/banned.py)')"
ok "item parked with the sweep's tag" "$(grep -q '^- \[ \] \[CLAUDE\] \[unworkable: hard-banned file app/banned.py\] \[T2\] tests/test_persist.py' "$(rd sg_banned)/OVERNIGHT_PROGRESS.md" && echo 1 || echo 0)"
ok "the next item is untouched" "$(grep -q '^- \[ \] \[T1\] app/bar.py' "$(rd sg_banned)/OVERNIGHT_PROGRESS.md" && echo 1 || echo 0)"
ok "park commit pushed to origin" "$(git -C "$T/sg_banned/origin.git" log ovn/t1 --format=%s -1 2>/dev/null | grep -q 'park unworkable item' && echo 1 || echo 0)"
run sg_oversize
ok "oversize file (60000 lines, >120000 bytes) -> no-op(scout-unworkable), no implement call" "$([ "$(res sg_oversize)" = 'no-op(scout-unworkable)' ] && echo "$(noimpl sg_oversize)" || echo 0)"
ok "oversize reason mentions the context" "$(has "$(tlog sg_oversize)" 'exceeds the model context')"
run sg_target
ok "item's own target (app/huge.py) dropped -> unworkable although app/foo.py is planned too" "$([ "$(res sg_target)" = 'no-op(scout-unworkable)' ] && echo "$(noimpl sg_target)" || echo 0)"
run sg_partial
ok "huge file dropped but the test file + app/foo.py remain -> implement RUNS" "$([ -f "$T/sg_partial/scn/calls/2.impl" ] && echo 1 || echo 0)"
ok "dropped file is not loaded by ANY path (force-load loop or the task_log scan)" "$(b2i "$(hasline "$(implcall sg_partial)" 'app/huge.py')")"
ok "workable planned file is still loaded (--file app/foo.py)" "$(hasline "$(implcall sg_partial)" 'app/foo.py')"
ok "plan text pasted in the implement prompt has the dropped path token broken (aider would auto-add it)" "$([ "$(has "$(implcall sg_partial)" 'app/huge.py')" = 0 ] && [ "$(has "$(implcall sg_partial)" 'app/huge_py')" = 1 ] && echo 1 || echo 0)"
ok "nothing parked" "$(b2i "$(has "$(cat "$(rd sg_partial)/OVERNIGHT_PROGRESS.md")" 'unworkable')")"
run sg_benign
ok "benign plan (small files) -> implement runs with app/foo.py loaded, no guard output" "$([ -f "$T/sg_benign/scn/calls/2.impl" ] && [ "$(hasline "$(implcall sg_benign)" 'app/foo.py')" = 1 ] && [ "$(has "$(tlog sg_benign)" 'scout-guard')" = 0 ] && echo 1 || echo 0)"
ok "benign: status unchanged (not scout-unworkable)" "$(b2i "$(has "$(res sg_benign)" 'scout-unworkable')")"
run sg_off
ok "OVN_SCOUT_GUARD=off -> old behaviour: huge planned file IS loaded" "$([ "$(hasline "$(implcall sg_off)" 'app/huge.py')" = 1 ] && [ "$(has "$(tlog sg_off)" 'scout-guard')" = 0 ] && echo 1 || echo 0)"
run sg_limit
ok "OVN_MAX_FILE_BYTES is honoured (20 bytes: app/foo.py dropped)" "$(has "$(tlog sg_limit)" 'scout-guard: dropped planned file app/foo.py')"
run sg_pushfail
ok "park push rejected -> still no-op(scout-unworkable), no crash, failure logged" "$([ "$(res sg_pushfail)" = 'no-op(scout-unworkable)' ] && [ "$(has "$(tlog sg_pushfail)" 'park push failed')" = 1 ] && echo 1 || echo 0)"

echo "== downstream consumers of the new status =="
S="no-op(scout-unworkable)"
cls="$(bash "$Q/ovn_classify_fail.sh" "$T/sg_banned/task.log" "$S")"
ok "ovn_classify_fail: fail_reason=scout-unworkable" "$([ "$cls" = scout-unworkable ] && echo 1 || echo 0)"
ok "ovn_classify_fail: unparked variant too" "$([ "$(bash "$Q/ovn_classify_fail.sh" "$T/sg_banned/task.log" 'no-op(scout-unworkable-unparked)')" = scout-unworkable ] && echo 1 || echo 0)"
ok "ovn_classify_fail: bare no-op unaffected" "$([ "$(bash "$Q/ovn_classify_fail.sh" "$T/sg_banned/task.log" 'no-op')" != scout-unworkable ] && echo 1 || echo 0)"
ok "outcome buckets (legacy row, no severity): scout-unworkable is benign" "$([ "$(python3 -c "
import sys; sys.path.insert(0,'$Q/scripts')
import ovn_outcome_buckets as b
print(b.bucket_from_outcome_row({'class':'noop','status':'no-op(scout-unworkable)'}), b.bucket_from_outcome_row({'class':'noop','status':'no-op'}))")" = 'benign bad' ] && echo 1 || echo 0)"
# item guard: parked item must not bill the NEXT item (it is now the top line); the unparked variant still counts
mkdir -p "$T/g/st"; ( cd "$T/g" && git init -q && git config user.email t@t && git config user.name t && printf -- '- [ ] [T2] app/bar.py — next item\n' > OVERNIGHT_PROGRESS.md && git add -A && git commit -q -m i )
printf 'Tokens: 5k sent, 1 received\n' > "$T/g/l.log"
bash "$Q/scripts/ovn_item_guard.sh" "$T/g" "$S" "$T/g/st" idg "$T/g/l.log" >/dev/null
ok "item guard: parked scout-unworkable writes no streak/lastfail state" "$([ -z "$(ls "$T/g/st/item_fails" 2>/dev/null)" ] && echo 1 || echo 0)"
bash "$Q/scripts/ovn_item_guard.sh" "$T/g" "no-op(scout-unworkable-unparked)" "$T/g/st" idg "$T/g/l.log" >/dev/null
ok "item guard: unparked variant still accrues the normal no-op streak" "$(ls "$T/g/st/item_fails"/idg.*.noopcount >/dev/null 2>&1 && echo 1 || echo 0)"
ok "best-of-N loop excludes scout-unworkable from retries" "$(grep -q "exhausted|skip|scout-unworkable'; do" "$Q/run_overnight.sh" && echo 1 || echo 0)"

echo; echo "Scout guard: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
