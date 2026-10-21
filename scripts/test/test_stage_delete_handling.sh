#!/usr/bin/env bash
# 2026-10-20 stage-unverified review (TAA plan_snapshot / truncate.py): three delete-handling defects in the staged runner, all pure-bash helpers in lib_stage_guards.sh (runs anywhere):
#   A. stage_item_wants_delete must also read the planner step's desc/verify ("Delete the orphaned test file <path>" emptied by aider = a deletion, not an empty-file failure x2)
#   B. stage_changed_live_files: the QUALITY 'changed test exercises the changed source' check must not run over DELETED paths (good deletion -> QUALITY FAIL)
#   C. stage_pure_delete_paths: aider cannot delete files; a step 'Delete X ...' whose VERIFY asserts absence gets X git-rm'd deterministically
# Mutants: each guard is re-run against a mutated copy of the lib and must be CAUGHT.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_osr_fixture.sh"
trap osr_cleanup EXIT
LIB="$HERE/../lib_stage_guards.sh"
. "$LIB"
unset OVN_STAGE_QUALITY_LIVE_ONLY OVN_STAGE_PURE_DELETE
echo "== A: stage_item_wants_delete reads step desc + verify"
ITEM='[T4] backend/app/utils/plan_snapshot.py — Delete the file. (cat:python)'
P='backend/tests/test_plan_snapshot.py'
yes_(){ stage_item_wants_delete "$1" "$2"; }
no_(){ ! stage_item_wants_delete "$1" "$2"; }
t "A1 item text alone does not name the orphaned test (old behaviour: empty-file failure)" no_ "$ITEM" "$P"
t "A2 planner step desc 'Delete the orphaned test file <path>' is a delete intent" yes_ "$ITEM"$'\n'"Delete the orphaned test file $P"$'\n'"VERIFY: pytest -q" "$P"
t "A3 step verify 'test ! -f <path>' is a delete intent" yes_ "$ITEM"$'\n'"cleanup"$'\n'"VERIFY: test ! -f $P" "$P"
t "A4 'test -f <path> && exit 1 || exit 0' is a delete intent" yes_ "x"$'\n'"VERIFY: test -f $P && exit 1 || exit 0" "$P"
t "A5 'Remove unused import from <path>' is NOT a delete intent" no_ "Remove the unused import from $P" "$P"
t "A6 a different path in the desc is not a delete intent for this path" yes_ "Delete the orphaned test file backend/tests/other.py" "backend/tests/other.py"
t "A7 ...and not for $P" no_ "Delete the orphaned test file backend/tests/other.py" "$P"
t "A8 the legacy item forms still work (Delete the file <path>)" yes_ "[T1] $P — Delete the file $P entirely." "$P"
echo "== B: stage_changed_live_files excludes deleted paths"
T1="$(safe_mktemp_dir)"; OSR_ALL_T+=("$T1")
G(){ git -C "$T1" -c user.email=t@t -c user.name=t "$@"; }
git -C "$T1" init -q -b main 2>/dev/null || git -C "$T1" init -q
mkdir -p "$T1/app" "$T1/tests"; echo "def a(): pass" > "$T1/app/plan_snapshot.py"; echo "import plan_snapshot" > "$T1/tests/test_plan_snapshot.py"; echo "x=1" > "$T1/app/keep.py"
G add -A; G commit -qm base; BASE="$(git -C "$T1" rev-parse HEAD)"
G rm -q app/plan_snapshot.py tests/test_plan_snapshot.py; echo "x=2" > "$T1/app/keep.py"; echo "y" > "$T1/app/new.py"; G add -A; G commit -qm change
LIVE="$(stage_changed_live_files "$T1" "$BASE..HEAD")"
t "B1 live list keeps modified + added files" bash -c "printf '%s\n' '$LIVE' | grep -qx app/keep.py && printf '%s\n' '$LIVE' | grep -qx app/new.py"
t "B2 live list drops the deleted source" bash -c "! printf '%s\n' '$LIVE' | grep -q plan_snapshot.py"
t "B3 live list drops the deleted test" bash -c "! printf '%s\n' '$LIVE' | grep -q test_plan_snapshot"
t "B4 a deletion-only change yields an EMPTY live list (so the exercise check is skipped)" bash -c "cd '$T1' && git reset -q --hard $BASE && git rm -q app/plan_snapshot.py tests/test_plan_snapshot.py && git -c user.email=t@t -c user.name=t commit -qm del && [ -z \"\$(OVN_STAGE_QUALITY_LIVE_ONLY=on bash -c '. $LIB; stage_changed_live_files $T1 $BASE..HEAD')\" ]"
t "B5 OVN_STAGE_QUALITY_LIVE_ONLY=off restores the old list (kill switch)" bash -c "OVN_STAGE_QUALITY_LIVE_ONLY=off bash -c '. $LIB; stage_changed_live_files $T1 $BASE..HEAD' | grep -q plan_snapshot.py"
MUT="$(safe_mktemp_dir)"; OSR_ALL_T+=("$MUT")
python3 - "$LIB" "$MUT/lib_mut_B.sh" <<'PY'
import sys; s=open(sys.argv[1]).read(); s=s.replace('filt="--diff-filter=ACMR"','filt=""'); open(sys.argv[2],'w').write(s)
PY
t "B6 MUTANT (diff-filter removed) is caught: deleted paths reappear" bash -c "bash -c '. $MUT/lib_mut_B.sh; stage_changed_live_files $T1 $BASE..HEAD' | grep -q plan_snapshot.py"
t "B7 the runner builds srcs/tests from the live list" bash -c "grep -q 'stage_changed_live_files \"\$wt\"' '$REALQ/ovn_stage_runner.sh' && grep -q 'printf .%s.n. \"\$_live\" | grep -E' '$REALQ/ovn_stage_runner.sh' && grep -q 'tests=\"\$(printf .%s.n. \"\$_live\"' '$REALQ/ovn_stage_runner.sh'"
echo "== C: stage_pure_delete_paths"
T2="$(safe_mktemp_dir)"; OSR_ALL_T+=("$T2")
git -C "$T2" init -q; mkdir -p "$T2/backend/app/utils"; echo "def trunc(): pass" > "$T2/backend/app/utils/truncate.py"; echo z > "$T2/README"
git -C "$T2" -c user.email=t@t -c user.name=t add -A; git -C "$T2" -c user.email=t@t -c user.name=t commit -qm base
PD='backend/app/utils/truncate.py'
ITEMD="[T4] $PD — Delete the file. VERIFY: test -f $PD && exit 1 || exit 0"
pd(){ stage_pure_delete_paths "$T2" "$1" "$2" "$3" "$4"; }
t "C1 'Delete truncate.py and add a test' + absence VERIFY -> path emitted" bash -c ". $LIB; [ \"\$(stage_pure_delete_paths '$T2' 'Delete truncate.py and add a test asserting its absence' '$PD backend/tests/test_truncate_removed.py' '$ITEMD' 'test ! -f $PD')\" = '$PD' ]"
t "C2 absence asserted only in the ITEM verify also counts" bash -c ". $LIB; [ \"\$(stage_pure_delete_paths '$T2' 'Delete $PD' '$PD' '$ITEMD' 'pytest -q')\" = '$PD' ]"
t "C3 no absence VERIFY anywhere -> nothing emitted" bash -c ". $LIB; [ -z \"\$(stage_pure_delete_paths '$T2' 'Delete truncate.py' '$PD' '[T4] x — Delete it.' 'pytest -q')\" ]"
t "C4 desc that is not a delete -> nothing" bash -c ". $LIB; [ -z \"\$(stage_pure_delete_paths '$T2' 'Update truncate.py' '$PD' '$ITEMD' 'test ! -f $PD')\" ]"
t "C5 untracked / missing path -> nothing" bash -c ". $LIB; [ -z \"\$(stage_pure_delete_paths '$T2' 'Delete nope.py' 'backend/app/utils/nope.py' 'VERIFY: test ! -f backend/app/utils/nope.py' 'test ! -f backend/app/utils/nope.py')\" ]"
t "C6 desc must name the file (a Delete step about another file does not delete this one)" bash -c ". $LIB; [ -z \"\$(stage_pure_delete_paths '$T2' 'Delete the cache dir' '$PD' '$ITEMD' 'test ! -f $PD')\" ]"
t "C7 OVN_STAGE_PURE_DELETE=off disables it" bash -c "OVN_STAGE_PURE_DELETE=off; export OVN_STAGE_PURE_DELETE; . $LIB; [ -z \"\$(stage_pure_delete_paths '$T2' 'Delete truncate.py' '$PD' '$ITEMD' 'test ! -f $PD')\" ]"
python3 - "$LIB" "$MUT/lib_mut_C.sh" <<'PY'
import sys,re; s=open(sys.argv[1]).read()
n=s.count('if printf \'%s\\n%s\' "$verify" "$item" | grep -qE')
assert n==1,n
s=s.replace('if printf \'%s\\n%s\' "$verify" "$item" | grep -qE','if true || printf \'%s\\n%s\' "$verify" "$item" | grep -qE')
open(sys.argv[2],'w').write(s)
PY
t "C8 MUTANT (absence-VERIFY requirement dropped) is caught by C3" bash -c ". $MUT/lib_mut_C.sh; [ -n \"\$(stage_pure_delete_paths '$T2' 'Delete truncate.py' '$PD' '[T4] x — Delete it.' 'pytest -q')\" ]"
t "C9 the runner calls stage_pure_delete_paths and git rm's per attempt" bash -c "grep -q 'stage_pure_delete_paths \"\$wt\"' '$REALQ/ovn_stage_runner.sh' && grep -q 'event:\"pure_delete\"' '$REALQ/ovn_stage_runner.sh'"
t "C10 the runner passes step desc + verify to the empty-file scan" bash -c "grep -q 'stage_empty_files_scan \"\$wt\" \"\$files\" \"\$item\".*\"\$desc\"' '$REALQ/ovn_stage_runner.sh'"
bash -n "$REALQ/ovn_stage_runner.sh" && ok "D1 runner still parses (bash -n)" 1 || ok "D1 runner still parses (bash -n)" 0
osr_summary
