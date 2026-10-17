#!/usr/bin/env bash
# 2026-10-12 (package uidcredit, part 1): Godot sidecars of a deleted file.
# Real case: xlite `Delete tests/test_aoe_destructible.gd` - the delete executor (and the DELETE: trailer handler) removed ONLY the .gd and left the tracked
# `tests/test_aoe_destructible.gd.uid` behind, so tests/test_uid_hygiene.gd::test_no_orphaned_uid_files went red, the cycle was reverted twice and the item was parked
# NEEDS-DECISION although the delete was right. Covered here:
#   A. ovn_delete_executor.py decide: targets carry the tracked `<path>.uid` / `<path>.import`; ALREADY-GONE with an orphan sidecar is still work; `orphans` CLI.
#   B. lib_fixup.sh ovn_delete_sidecars + ovn_uid_orphan_fixup (the deterministic fix-up before the revert decision).
#   C. the REAL extracted run_overnight.sh blocks: DELETE-EXECUTOR, DELETE: trailer handler, UID-FIXUP gate block, and the delete-hint text.
# Every behaviour is also proven to FAIL with the kill switch (OVN_DELETE_SIDECARS=off / OVN_UID_FIXUP=off = the old behaviour).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCR="$HERE/.."; [ -f "$SCR/ovn_delete_executor.py" ] || SCR="$HERE"
EX="$SCR/ovn_delete_executor.py"; LIB="$SCR/lib_fixup.sh"
RO="$SCR/../run_overnight.sh"; [ -f "$RO" ] || RO="$HERE/../run_overnight.sh"
. "$HERE/ntfy_guard.sh" 2>/dev/null || true
pass=0; fail=0
ok(){ if [ "$2" = "1" ]; then pass=$((pass+1)); echo "  ok   $1"; else fail=$((fail+1)); echo "  FAIL $1"; fi; }
T="$(mktemp -d)" || exit 1; trap 'rm -rf "$T"' EXIT

mkrepo(){  # a Godot-shaped repo: tracked scripts + their .uid sidecars (+ a .import)
  rm -rf "${T:?}/r" "${T:?}/origin.git"; git init -q --bare "$T/origin.git"; git clone -q "$T/origin.git" "$T/r" 2>/dev/null; cd "$T/r" || exit 1
  git config user.email t@t; git config user.name t
  mkdir -p tests scripts art
  printf 'extends GutTest\nfunc test_x():\n\tpass_test("x")\n' > tests/test_aoe_destructible.gd; echo 'uid://b1aoe' > tests/test_aoe_destructible.gd.uid
  printf 'extends GutTest\nfunc test_y():\n\tpass_test("y")\n' > tests/test_other_thing.gd;       echo 'uid://b2oth' > tests/test_other_thing.gd.uid
  printf 'extends Node\nfunc lone(): return 1\n' > scripts/lone_helper.gd                         # no sidecar at all
  printf 'extends Node\nfunc hurt(): return 2\n' > scripts/hurt_logic.gd; echo 'uid://b3hur' > scripts/hurt_logic.gd.uid
  printf 'extends Node\n' > scripts/zzz_dead_mod.gd; echo 'uid://b4zzz' > scripts/zzz_dead_mod.gd.uid
  printf 'extends GutTest\n' > tests/test_zzz_dead_mod.gd; echo 'uid://b5zzt' > tests/test_zzz_dead_mod.gd.uid
  printf 'png' > art/tile.png; printf '[remap]\n' > art/tile.png.import
  git add -A; git commit -q -m base; git branch -M main; git push -q origin main
}
d(){ python3 "$EX" check "$T/r" "$1"; }

# ======================= A. the executor's decision =======================
mkrepo
ITEM='- [ ] [T3] tests/test_aoe_destructible.gd — Delete the entire file as it exclusively tests the orphaned `Aoe.is_destructible_type`. VERIFY: `test -f tests/test_aoe_destructible.gd` returns false. (cat:test; multifile:no) [feat:xlite-x-delete-aoe]'
r="$(d "$ITEM")"
ok "A1 real case: the targets name the .gd AND its .gd.uid (was: the .gd only)" "$([ "$r" = "$(printf 'OK\ttests/test_aoe_destructible.gd tests/test_aoe_destructible.gd.uid')" ] && echo 1 || echo 0)"
r="$(OVN_DELETE_SIDECARS=off d "$ITEM")"
ok "A2 kill switch OVN_DELETE_SIDECARS=off restores the .gd-only target list (mutation proof of A1)" "$([ "$r" = "$(printf 'OK\ttests/test_aoe_destructible.gd')" ] && echo 1 || echo 0)"
r="$(d '- [ ] [T1] scripts/lone_helper.gd — Delete this dead file, nothing calls it. (cat:godot)')"
ok "A3 a file WITHOUT a sidecar is unchanged (no phantom paths)" "$([ "$r" = "$(printf 'OK\tscripts/lone_helper.gd')" ] && echo 1 || echo 0)"
r="$(d '- [ ] [T1] scripts/zzz_dead_mod.gd — Delete the dead file and its dedicated test tests/test_zzz_dead_mod.gd. (cat:godot)')"
ok "A4 a named dedicated test brings its own .uid too" "$(printf '%s' "$r" | grep -q '^OK' && for x in scripts/zzz_dead_mod.gd scripts/zzz_dead_mod.gd.uid tests/test_zzz_dead_mod.gd tests/test_zzz_dead_mod.gd.uid; do printf '%s' "$r" | grep -qw -- "$x" || exit 1; done && echo 1 || echo 0)"
# an untracked stray sidecar is never promised to `git rm` (that would fail the whole executor attempt)
echo 'uid://stray' > scripts/lone_helper.gd.uid
r="$(d '- [ ] [T1] scripts/lone_helper.gd — Delete this dead file, nothing calls it. (cat:godot)')"
ok "A5 an UNTRACKED sidecar is not put in the git-rm target list" "$([ "$r" = "$(printf 'OK\tscripts/lone_helper.gd')" ] && echo 1 || echo 0)"
rm -f scripts/lone_helper.gd.uid
# ALREADY-GONE with an orphan tracked sidecar: the orphan is the remaining work
git rm -q scripts/hurt_logic.gd; git commit -q -m "half delete (the .uid stayed)"
r="$(d '- [ ] [T1] scripts/hurt_logic.gd — Delete the dead file. VERIFY: `test ! -f scripts/hurt_logic.gd`. (cat:godot)')"
ok "A6 file already deleted but its tracked .uid is orphaned -> OK <the .uid> (not ALREADY-GONE)" "$([ "$r" = "$(printf 'OK\tscripts/hurt_logic.gd.uid')" ] && echo 1 || echo 0)"
r="$(OVN_DELETE_SIDECARS=off d '- [ ] [T1] scripts/hurt_logic.gd — Delete the dead file. VERIFY: `test ! -f scripts/hurt_logic.gd`. (cat:godot)')"
ok "A7 (kill switch) the old answer ALREADY-GONE" "$([ "$r" = "$(printf 'ALREADY-GONE\tscripts/hurt_logic.gd')" ] && echo 1 || echo 0)"
git rm -q scripts/hurt_logic.gd.uid; git commit -q -m "orphan removed"
r="$(d '- [ ] [T1] scripts/hurt_logic.gd — Delete the dead file. VERIFY: `test ! -f scripts/hurt_logic.gd`. (cat:godot)')"
ok "A8 fully deleted (no orphan) -> ALREADY-GONE as before" "$([ "$r" = "$(printf 'ALREADY-GONE\tscripts/hurt_logic.gd')" ] && echo 1 || echo 0)"
# orphans CLI
mkrepo
git rm -q tests/test_aoe_destructible.gd
o="$(python3 "$EX" orphans "$T/r" tests/test_aoe_destructible.gd tests/test_other_thing.gd)"
ok "A9 orphans: lists the sidecar of the gone file only (the live file's .uid is not an orphan)" "$([ "$o" = "tests/test_aoe_destructible.gd.uid" ] && echo 1 || echo 0)"
git rm -q art/tile.png
o="$(python3 "$EX" orphans "$T/r" art/tile.png)"
ok "A10 orphans: a .import sidecar counts too" "$([ "$o" = "art/tile.png.import" ] && echo 1 || echo 0)"
o="$(OVN_DELETE_SIDECARS=off python3 "$EX" orphans "$T/r" tests/test_aoe_destructible.gd)"
ok "A11 orphans: kill switch prints nothing" "$([ -z "$o" ] && echo 1 || echo 0)"
o="$(python3 "$EX" orphans "$T/r" ../etc/passwd /abs/path)"
ok "A12 orphans: traversal / absolute paths are ignored" "$([ -z "$o" ] && echo 1 || echo 0)"

# ======================= B. lib_fixup.sh helpers =======================
mkrepo; cd "$T/r" || exit 1
git rm -q tests/test_aoe_destructible.gd
out="$( . "$LIB"; ovn_delete_sidecars "$T/r" tests/test_aoe_destructible.gd tests/test_other_thing.gd )"
ok "B1 ovn_delete_sidecars prints and stages the removal of the orphan only" "$([ "$out" = "tests/test_aoe_destructible.gd.uid" ] && [ ! -e tests/test_aoe_destructible.gd.uid ] && [ -f tests/test_other_thing.gd.uid ] && git diff --cached --name-only | grep -qx 'tests/test_aoe_destructible.gd.uid' && echo 1 || echo 0)"
mkrepo; cd "$T/r" || exit 1
git rm -q tests/test_aoe_destructible.gd
out="$( . "$LIB"; OVN_DELETE_SIDECARS=off ovn_delete_sidecars "$T/r" tests/test_aoe_destructible.gd )"
ok "B2 (kill switch) nothing removed" "$([ -z "$out" ] && [ -f tests/test_aoe_destructible.gd.uid ] && echo 1 || echo 0)"

# the fix-up: before = base, after = a commit that deleted the .gd only (what the old executor produced)
mkrepo; cd "$T/r" || exit 1
B="$(git rev-parse HEAD)"; git rm -q tests/test_aoe_destructible.gd; git commit -q -m "chore: remove dead file(s) tests/test_aoe_destructible.gd (deterministic delete executor)"; A="$(git rev-parse HEAD)"
: > "$T/tl"
( . "$LIB"; ovn_uid_orphan_fixup "$B" "$A" "$T/tl" ); rc=$?
ok "B3 ovn_uid_orphan_fixup: rc 0, a NEW commit removes the orphan .uid, tree clean" "$([ "$rc" = 0 ] && [ "$(git rev-parse HEAD)" != "$A" ] && [ ! -e tests/test_aoe_destructible.gd.uid ] && [ -z "$(git status --porcelain)" ] && git show --stat --format= HEAD | grep -q 'test_aoe_destructible.gd.uid' && echo 1 || echo 0)"
ok "B4 the task log says what was removed" "$(grep -q 'UID-FIXUP: removed orphaned Godot sidecar(s).*test_aoe_destructible.gd.uid' "$T/tl" && echo 1 || echo 0)"
ok "B5 only that sidecar went (the other test's .uid is untouched)" "$([ -f tests/test_other_thing.gd.uid ] && echo 1 || echo 0)"
mkrepo; cd "$T/r" || exit 1
B="$(git rev-parse HEAD)"; git rm -q tests/test_aoe_destructible.gd; git commit -q -m del; A="$(git rev-parse HEAD)"
( . "$LIB"; OVN_UID_FIXUP=off ovn_uid_orphan_fixup "$B" "$A" "$T/tl" ); rc=$?
ok "B6 (kill switch OVN_UID_FIXUP=off) rc 1, nothing removed - the old behaviour" "$([ "$rc" = 1 ] && [ -f tests/test_aoe_destructible.gd.uid ] && [ "$(git rev-parse HEAD)" = "$A" ] && echo 1 || echo 0)"
mkrepo; cd "$T/r" || exit 1
B="$(git rev-parse HEAD)"; echo '# touched' >> tests/test_other_thing.gd; git commit -q -am edit; A="$(git rev-parse HEAD)"
( . "$LIB"; ovn_uid_orphan_fixup "$B" "$A" "$T/tl" ); rc=$?
ok "B7 a cycle that deleted nothing: rc 1, no commit" "$([ "$rc" = 1 ] && [ "$(git rev-parse HEAD)" = "$A" ] && echo 1 || echo 0)"
mkrepo; cd "$T/r" || exit 1
B="$(git rev-parse HEAD)"; git rm -q tests/test_aoe_destructible.gd tests/test_aoe_destructible.gd.uid; git commit -q -m "clean delete"; A="$(git rev-parse HEAD)"
( . "$LIB"; ovn_uid_orphan_fixup "$B" "$A" "$T/tl" ); rc=$?
ok "B8 a clean delete (sidecar already gone): rc 1, no extra commit" "$([ "$rc" = 1 ] && [ "$(git rev-parse HEAD)" = "$A" ] && echo 1 || echo 0)"
# a file deleted AND re-created at another path keeps working: only paths absent now are orphan candidates
mkrepo; cd "$T/r" || exit 1
B="$(git rev-parse HEAD)"; git mv tests/test_other_thing.gd tests/test_other_thing2.gd; git commit -q -m mv; A="$(git rev-parse HEAD)"
( . "$LIB"; ovn_uid_orphan_fixup "$B" "$A" "$T/tl" ); rc=$?
ok "B9 a RENAME (old path gone, .uid stays under the old name) is the same orphan and is removed" "$([ "$rc" = 0 ] && [ ! -e tests/test_other_thing.gd.uid ] && echo 1 || echo 0)"

# ======================= C. the REAL runner blocks =======================
# C1/C2: DELETE-EXECUTOR block. The verification stub models test_no_orphaned_uid_files: red while any tracked .uid has no sibling file.
orph_red(){ for u in $(git ls-files '*.uid'); do [ -e "${u%.uid}" ] || return 0; done; return 1; }
blk="$(awk '/# >>> DELETE-EXECUTOR-BEGIN/{f=1} f{print} /# <<< DELETE-EXECUTOR-END/{f=0}' "$RO")"
ok "C0 DELETE-EXECUTOR block present in run_overnight.sh" "$([ -n "$blk" ] && echo 1 || echo 0)"
run_exec_block(){  # $1 = extra env assignment for the harness ("" for none)
  mkrepo; cd "$T/r" || exit 1
  printf '## Next Steps\n%s\n' "$ITEM" > OVERNIGHT_PROGRESS.md
  git add -A; git commit -q -m prog; git push -q origin main
  rm -rf "${T:?}/sd"; mkdir -p "$T/sd/scripts" "$T/sd/state"; cp "$EX" "$T/sd/scripts/"
  cat > "$T/harness.sh" <<H
set -u
$1
SCRIPT_DIR="$T/sd"; id="ongoing-xlite"; branch=main; task_log="$T/task.log"; : > "\$task_log"
. "$LIB"
ovn_item_hash(){ printf '%s' "\$1" | cksum | cut -d' ' -f1; }
run_repo_verification(){ for u in \$(git ls-files '*.uid'); do [ -e "\${u%.uid}" ] || { echo fail; return; }; done; echo pass; }
ovn_bug_first_order(){ cat; }
f(){
BEFORE_SHA="\$(git rev-parse HEAD)"
$blk
echo FELL-THROUGH
}
f
H
  bash "$T/harness.sh" 2>&1
}
out="$(run_exec_block "")"; cd "$T/r" || exit 1; git fetch -q origin
ok "C1 executor block (real case): verify GREEN, pushed, no fall-through" "$(printf '%s' "$out" | grep -q 'pushed(tests:pass) delete-executor' && ! printf '%s' "$out" | grep -q FELL-THROUGH && echo 1 || echo 0)"
ok "C2 origin has NEITHER the .gd NOR its .gd.uid" "$(! git cat-file -e origin/main:tests/test_aoe_destructible.gd 2>/dev/null && ! git cat-file -e origin/main:tests/test_aoe_destructible.gd.uid 2>/dev/null && echo 1 || echo 0)"
# post-delete check even when the TARGET LIST missed the sidecar: stub the decision to name only the .gd (what the old executor did)
cp "$EX" "$T/ex_orig.py"
mkrepo; cd "$T/r" || exit 1
printf '## Next Steps\n%s\n' "$ITEM" > OVERNIGHT_PROGRESS.md; git add -A; git commit -q -m prog; git push -q origin main
rm -rf "${T:?}/sd2"; mkdir -p "$T/sd2/scripts" "$T/sd2/state"
cat > "$T/sd2/scripts/ovn_delete_executor.py" <<'PY'
import sys
if sys.argv[1] == "check":
    print("OK\ttests/test_aoe_destructible.gd")   # an old/foreign decision that forgot the sidecar
PY
cp "$EX" "$T/sd2/scripts/ovn_delete_executor_real.py"
# the lib resolves `orphans` through ovn_delete_executor.py next to it: give the lib copy the real one
mkdir -p "$T/libcopy"; cp "$LIB" "$T/libcopy/lib_fixup.sh"; cp "$EX" "$T/libcopy/ovn_delete_executor.py"
sed -e "s#SCRIPT_DIR=\"$T/sd\"#SCRIPT_DIR=\"$T/sd2\"#" -e "s#^\. \"$LIB\"#. \"$T/libcopy/lib_fixup.sh\"#" "$T/harness.sh" > "$T/harness2.sh"
out="$(bash "$T/harness2.sh" 2>&1)"; cd "$T/r" || exit 1; git fetch -q origin
ok "C3 post-delete check: a decision that forgot the .uid still ends green (the runner removes the orphan in the same commit)" "$(printf '%s' "$out" | grep -q 'pushed(tests:pass) delete-executor' && ! git cat-file -e origin/main:tests/test_aoe_destructible.gd.uid 2>/dev/null && echo 1 || echo 0)"
mkrepo; cd "$T/r" || exit 1; printf '## Next Steps\n%s\n' "$ITEM" > OVERNIGHT_PROGRESS.md; git add -A; git commit -q -m prog; git push -q origin main
out="$(OVN_DELETE_SIDECARS=off bash "$T/harness2.sh" 2>&1)"
ok "C4 (kill switch) the same run reproduces the old failure: verify red -> reverted, falls through" "$(printf '%s' "$out" | grep -q FELL-THROUGH && grep -q 'verification=fail' "$T/task.log" && echo 1 || echo 0)"

# C5: DELETE: trailer handler (extracted)
tblk="$(awk '/_ovn_del_already=0/{f=1} /# Working-tree residue guard/{f=0} f{print}' "$RO")"
ok "C5a trailer handler block extracted" "$([ -n "$tblk" ] && echo 1 || echo 0)"
run_trailer(){  # $1 = env assignment
  mkrepo; cd "$T/r" || exit 1
  cat > "$T/harness3.sh" <<H
set -u
$1
task_log="$T/task3.log"; printf 'blah\nDELETE: tests/test_aoe_destructible.gd\n' > "\$task_log"
. "$LIB"
f(){
BEFORE_SHA="\$(git rev-parse HEAD)"; AFTER_SHA="\$BEFORE_SHA"
$tblk
echo "AFTER=\$AFTER_SHA BEFORE=\$BEFORE_SHA"
}
f
H
  bash "$T/harness3.sh" 2>&1
}
out="$(run_trailer "")"; cd "$T/r" || exit 1
# (run_trailer sources the repo lib; the lib finds ovn_delete_executor.py next to itself in scripts/)
ok "C5 DELETE: trailer removes the .gd AND its .gd.uid in ONE commit" "$(printf '%s' "$out" | grep -qE 'AFTER=[0-9a-f]+ BEFORE=[0-9a-f]+' && [ "$(git rev-parse HEAD)" != "$(git rev-parse HEAD~1)" ] && git show --stat --format= HEAD | grep -q 'test_aoe_destructible.gd.uid' && [ ! -e tests/test_aoe_destructible.gd.uid ] && [ -z "$(git status --porcelain)" ] && echo 1 || echo 0)"
out="$(run_trailer "export OVN_DELETE_SIDECARS=off")"; cd "$T/r" || exit 1
ok "C6 (kill switch) trailer removes only the .gd - the old orphan" "$([ ! -e tests/test_aoe_destructible.gd ] && [ -f tests/test_aoe_destructible.gd.uid ] && echo 1 || echo 0)"

# C6b/C6c: a lone `DELETE: X.gd.uid` trailer while X.gd still exists (the real xlite cell_ring case: owner REFUSED by the importer guard, sidecar trailer went through and was the
# only net diff of a cycle that then counted as `landed`). The sidecar must stay until its owner goes.
run_trailer_uid_only(){  # $1 = env assignment
  mkrepo; cd "$T/r" || exit 1
  cat > "$T/harness3b.sh" <<H
set -u
$1
task_log="$T/task3b.log"; printf 'blah\nDELETE: tests/test_aoe_destructible.gd.uid\n' > "\$task_log"
. "$LIB"
f(){
BEFORE_SHA="\$(git rev-parse HEAD)"; AFTER_SHA="\$BEFORE_SHA"
$tblk
echo "AFTER=\$AFTER_SHA BEFORE=\$BEFORE_SHA"
}
f
H
  bash "$T/harness3b.sh" 2>&1
}
out="$(run_trailer_uid_only "")"; cd "$T/r" || exit 1
ok "C6b lone sidecar trailer with the owner .gd still present: nothing removed, no commit" "$([ -f tests/test_aoe_destructible.gd.uid ] && [ -f tests/test_aoe_destructible.gd ] && printf '%s' "$out" | grep -qE 'AFTER=([0-9a-f]+) BEFORE=\1' && grep -q 'sidecar of tests/test_aoe_destructible.gd, which is still present' "$T/task3b.log" && echo 1 || echo 0)"
out="$(run_trailer_uid_only "export OVN_DELETE_SIDECAR_OWNER_GUARD=off")"; cd "$T/r" || exit 1
ok "C6c (kill switch) the old behaviour: the orphaning sidecar-only delete goes through" "$([ ! -e tests/test_aoe_destructible.gd.uid ] && [ -f tests/test_aoe_destructible.gd ] && echo 1 || echo 0)"

# C7: UID-FIXUP gate block
gblk="$(awk '/# UID-FIXUP \(2026-10-12/{f=1} /# Tier-2 grounded fix-up \(2026-09-16\)/{f=0} f{print}' "$RO")"
ok "C7a UID-FIXUP block extracted" "$([ -n "$gblk" ] && echo 1 || echo 0)"
run_gate(){  # $1 = env assignment
  mkrepo; cd "$T/r" || exit 1
  git rm -q tests/test_aoe_destructible.gd; git commit -q -m "model commit: deleted only the .gd"
  cat > "$T/harness4.sh" <<H
set -u
$1
task_log="$T/task4.log"; : > "\$task_log"
. "$LIB"
run_repo_verification(){ for u in \$(git ls-files '*.uid'); do [ -e "\${u%.uid}" ] || { echo fail; return; }; done; echo pass; }
_ovn_apply_baseline_subtraction(){ :; }
f(){
BEFORE_SHA="\$(git rev-parse HEAD~1)"; AFTER_SHA="\$(git rev-parse HEAD)"; VERIFY_RESULT=fail; _ovn_voff=0
$gblk
echo "VERIFY_RESULT=\$VERIFY_RESULT HEAD=\$(git rev-parse HEAD) AFTER=\$AFTER_SHA"
}
f
H
  bash "$T/harness4.sh" 2>&1
}
out="$(run_gate "")"; cd "$T/r" || exit 1
ok "C7 gate: red run caused by the orphan .uid -> fix-up commit, re-verify PASS, AFTER_SHA follows HEAD (no revert)" "$(printf '%s' "$out" | grep -q 'VERIFY_RESULT=pass' && printf '%s' "$out" | grep -qE "HEAD=([0-9a-f]+) AFTER=\1" && [ ! -e tests/test_aoe_destructible.gd.uid ] && echo 1 || echo 0)"
ok "C8 the task log records the fix-up and its re-verify" "$(grep -q 'UID-FIXUP: removed orphaned' "$T/task4.log" && grep -q 'UID-FIXUP re-verify: pass' "$T/task4.log" && echo 1 || echo 0)"
out="$(run_gate "export OVN_UID_FIXUP=off")"; cd "$T/r" || exit 1
ok "C9 (kill switch) the red run stays red - the old path would revert the commit" "$(printf '%s' "$out" | grep -q 'VERIFY_RESULT=fail' && [ -f tests/test_aoe_destructible.gd.uid ] && echo 1 || echo 0)"
# a red run NOT caused by a sidecar: nothing to fix-up -> stays red, no commit
mkrepo; cd "$T/r" || exit 1
echo '# edit' >> tests/test_other_thing.gd; git commit -q -am "plain edit"
sed -e 's#git rm -q tests/test_aoe_destructible.gd;##' "$T/harness4.sh" > "$T/harness5.sh"
out="$(bash "$T/harness5.sh" 2>&1)"
ok "C10 a red cycle that deleted nothing is untouched (no fix-up commit, stays fail)" "$(printf '%s' "$out" | grep -q 'VERIFY_RESULT=fail' && ! grep -q 'UID-FIXUP: removed' "$T/task4.log" && echo 1 || echo 0)"

# C11: the delete hint names the sidecar
ok "C11 the delete-hint prompt names the .uid sidecar" "$(grep -q 'DELETE: <path> — that is the ONLY mechanism that works here to remove a file. A Godot file' "$RO" && grep -q '<path>.uid' "$RO" && echo 1 || echo 0)"

echo "  $pass passed, $fail failed"; [ "$fail" = 0 ]
