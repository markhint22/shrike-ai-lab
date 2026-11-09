#!/usr/bin/env bash
# hotfix-scout-hang review round 2 (2026-11-08): D1 timeout note must never corrupt the stage-runner JSONL journal; D2 credit_already_satisfied cap + restore after a kill;
# H3 alembic_autogen cap above its own worst case + git recovery after a kill; minor: a helper's own rc 137 (OOM) is not a timeout.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
Q="$HERE/../.."; [ -f "$Q/run_overnight.sh" ] || Q="$HERE/.."
LIB="$Q/scripts/lib_helper_timeout.sh"
[ -f "$LIB" ] || { echo "  FAIL: $LIB missing"; exit 1; }
type -P timeout >/dev/null 2>&1 || type -P gtimeout >/dev/null 2>&1 || { echo "  SKIP: no timeout binary"; exit 0; }
type -P jq >/dev/null 2>&1 || { echo "  SKIP: no jq"; exit 0; }
export NTFY_SERVER=http://127.0.0.1:9 OVN_NOTIFY_DISABLE=1 TZ=UTC
T="$(safe_mktemp_dir hto2)" || exit 1
trap 'safe_rm_rf "$T"' EXIT
rc=0; ok(){ echo "  ok   $1"; }; bad(){ echo "  FAIL: $1"; rc=1; }
GI=(-c user.email=t@t -c user.name=t)
mkrepo(){ safe_rm_rf "${1:?}"; mkdir -p "$1"; git -C "$1" init -q; echo base > "$1/OVERNIGHT_PROGRESS.md"; git -C "$1" add -A; git -C "$1" "${GI[@]}" commit -qm i; }

echo "== D1: the timeout note never goes into a JSONL journal"
( . "$LIB"; unset task_log TASK_LOG OVN_HTO_CYCLE_LOG; SLOG="$T/run.jsonl"; export OVN_HTO_LOG="$T/state.log"
  echo '{"run":"r","tokens_sent":5}' > "$SLOG"; ovn_hto 1 so_item_filter sleep 5; echo '{"run":"r","tokens_sent":7}' >> "$SLOG" )
if jq -s '[.[].tokens_sent // 0] | add' "$T/run.jsonl" >"$T/o.txt" 2>/dev/null && [ "$(cat "$T/o.txt")" = 12 ]; then ok "stage-runner shape (only SLOG=*.jsonl set): journal still parses with jq -s after a timeout"; else bad "journal not parseable by jq -s after a timeout: $(cat "$T/run.jsonl")"; fi
jq -e -s 'any(.[]; .event=="helper_timeout" and .label=="so_item_filter")' "$T/run.jsonl" >/dev/null 2>&1 && ok "the timeout is recorded in the journal as a valid JSON object" || bad "no JSON helper_timeout record"
grep -q 'helper-timeout: so_item_filter' "$T/state.log" && ok "state log still gets the text line" || bad "state log line missing"
( . "$LIB"; task_log="$T/cyc.log"; SLOG="$T/run2.jsonl"; : > "$task_log"; echo '{"a":1}' > "$SLOG"; export OVN_HTO_LOG="$T/state2.log"; ovn_hto 1 stub sleep 5 )
{ grep -q 'helper-timeout: stub' "$T/cyc.log" && [ "$(jq -s length "$T/run2.jsonl")" = 1 ]; } && ok "with a text cycle log the note goes there and SLOG is untouched" || bad "SLOG touched / cycle log missed"
( . "$LIB"; unset task_log TASK_LOG; OVN_HTO_CYCLE_LOG="$T/c3.log"; SLOG="$T/run3.jsonl"; : > "$T/c3.log"; echo '{"a":1}' > "$SLOG"; export OVN_HTO_LOG="$T/state3.log"; ovn_hto 1 stub sleep 5 )
{ grep -q 'helper-timeout: stub' "$T/c3.log" && [ "$(jq -s length "$T/run3.jsonl")" = 1 ]; } && ok "OVN_HTO_CYCLE_LOG is honoured and wins" || bad "OVN_HTO_CYCLE_LOG ignored"
( . "$LIB"; unset task_log TASK_LOG OVN_HTO_CYCLE_LOG SLOG; export OVN_HTO_LOG="$T/state4.log"; ovn_hto 1 stub sleep 5 ); grep -q 'helper-timeout: stub' "$T/state4.log" && ok "no cycle log at all: state log only, no error" || bad "state-only failed"

echo "== minor: a helper's own rc 137 (OOM) is not a timeout"
( . "$LIB"; unset task_log TASK_LOG SLOG OVN_HTO_CYCLE_LOG; export OVN_HTO_LOG="$T/oom.log"
  ovn_hto 30 oomstub bash -c 'kill -9 $$'; a=$?; ovn_hto_open 30 oomstub bash -c 'kill -9 $$'; b=$?; echo "$a $b" > "$T/oomrc" )
[ "$(cat "$T/oomrc")" = "137 137" ] && ok "OOM-style 137 passes through ovn_hto and ovn_hto_open (an OOM-killed gate does NOT read as pass)" || bad "rc 137 mangled: $(cat "$T/oomrc")"
[ ! -s "$T/oom.log" ] && ok "and no helper-timeout note is logged for it" || bad "OOM logged as a timeout"
( . "$LIB"; export OVN_HTO_LOG="$T/kill.log"; unset task_log TASK_LOG SLOG; ovn_hto 1 stub bash -c 'trap "" TERM; while :; do sleep 1; done'; echo $? > "$T/killrc" )
[ "$(cat "$T/killrc")" = 124 ] && grep -q 'helper-timeout: stub' "$T/kill.log" && ok "a TERM-ignoring helper KILLed after the cap is still reported as a timeout (rc=124)" || bad "KILLed-by-cap helper not a timeout: rc=$(cat "$T/killrc")"

echo "== D2: credit_already_satisfied is capped far above a burst and a kill leaves no dirty ticks"
for pat in '_SKC="$(ovn_hto "${OVN_CREDIT_HTO:-900}" credit_already_satisfied' '_AC_OUT="$(ovn_hto "${OVN_CREDIT_HTO:-900}" credit_already_satisfied'; do
  grep -qF "$pat" "$Q/run_overnight.sh" && ok "call site carries the 900 s overridable cap: ${pat%% credit*}" || bad "call site missing: $pat"
done
! grep -q 'ovn_hto 120 credit_already_satisfied' "$Q/run_overnight.sh" && ok "the 120 s cap is gone" || bad "120 s cap still present"
STUB="$T/stub"; mkdir -p "$STUB/scripts"
printf '#!/usr/bin/env bash\nsed -i.bak "s/base/[x] ticked/" "$2"; rm -f "$2.bak"; sleep 30; echo CREDITED=1\n' > "$STUB/scripts/ovn_credit_already_satisfied.sh"
run_site(){  # $1 = pattern selecting the real call line; $2 = 1 to strip the restore (mutant)
  local call repo="$T/r_$RANDOM"; call="$(grep -F "$1" "$Q/run_overnight.sh" | head -1 | sed -E 's/^[[:space:]]+//')"
  [ "$2" = 1 ] && call="$(printf '%s' "$call" | sed 's/; \[ \$? -eq 124 \] && ovn_hto_restore_file OVERNIGHT_PROGRESS.md.*//')"
  mkrepo "$repo"
  ( set +u; . "$LIB"; cd "$repo"; SCRIPT_DIR="$STUB"; task_log="$T/site.log"; : > "$task_log"; export OVN_CREDIT_HTO=1 OVN_HTO_LOG="$T/site_state.log"; eval "$call" )
  git -C "$repo" status --porcelain | grep -c OVERNIGHT_PROGRESS
}
for pat in '_SKC="$(ovn_hto' '_AC_OUT="$(ovn_hto'; do
  [ "$(run_site "$pat" 0)" = 0 ] && ok "after a kill the progress file is restored (${pat%%=*})" || bad "progress file left dirty after a kill (${pat%%=*})"
  [ "$(run_site "$pat" 1)" = 1 ] && ok "mutant (no restore) leaves it dirty: the test can fail (${pat%%=*})" || bad "mutant did not leave file dirty (${pat%%=*}) - test is vacuous"
done
( . "$LIB"; r="$T/r_lib"; mkrepo "$r"; echo changed > "$r/OVERNIGHT_PROGRESS.md"; ovn_hto_restore_file "$r/OVERNIGHT_PROGRESS.md" 2>/dev/null; cd "$r" && ovn_hto_restore_file OVERNIGHT_PROGRESS.md; [ "$(cat OVERNIGHT_PROGRESS.md)" = base ] ) && ok "ovn_hto_restore_file restores a tracked file" || bad "restore helper broken"

echo "== H3: alembic_autogen cap exceeds the script's own worst case; a kill is cleaned up"
! grep -qE 'ovn_hto 120 alembic_autogen' "$Q/ovn_stage_runner.sh" "$Q/run_overnight.sh" && ok "no 120 s cap left on alembic_autogen" || bad "120 s alembic cap still present"
caps="$(grep -oE 'ovn_hto "\$\{OVN_ALEMBIC_HTO:-[0-9]+\}" alembic_autogen' "$Q/ovn_stage_runner.sh" | grep -oE '[0-9]+' )"
[ "$(printf '%s\n' "$caps" | grep -c .)" -ge 2 ] && ok "both stage-runner call sites use OVN_ALEMBIC_HTO" || bad "alembic call sites not parameterised ($caps)"
for c in $caps; do [ "$c" -ge 270 ] && ok "default cap ${c}s >= 2 x 120 s driver + slack" || bad "cap ${c}s below the script's worst case"; done
SR="$Q/ovn_stage_runner.sh"
[ "$(grep -c 'ovn_hto_git_recover "\$wt" "\$_ag_snap" "\$_ag_sent"' "$SR")" -ge 2 ] && ok "both call sites run ovn_hto_git_recover (snapshot + sentinel) after rc 124" || bad "call sites lack recovery"
[ "$(grep -c 'ovn_hto_snapshot_untracked "\$wt" .:(glob)\*\*/alembic/versions/\*\*.' "$SR")" -ge 2 ] && [ "$(grep -c 'ovn_hto_sentinel' "$SR")" -ge 2 ] && [ "$(grep -c 'ovn_hto_recover_done' "$SR")" -ge 2 ] && ok "call sites snapshot (alembic/versions only) + sentinel before the call and clean up after" || bad "call sites do not snapshot/sentinel/cleanup"
! grep -q '_ag_t0' "$SR" && ok "no whole-second epoch gate left in the stage runner" || bad "_ag_t0 epoch gate still present"
# the recovery section of the lib (from the refuse helper on, comments stripped) must contain no destructive git verb
REC="$(sed -n '/^_ovn_hto_refuse()/,$p' "$LIB" | sed 's/^[[:space:]]*#.*//')"
bad_verb=""; for v in 'reset' 'checkout' 'clean -' 'clean$' 'stash' 'rm -rf' 'rm -fr' 'rm -r ' 'git (-C [^ ]+ )?rm ' 'restore' ' mv '; do printf '%s\n' "$REC" | grep -qE -- "$v" && bad_verb="$bad_verb [$v]"; done
[ -z "$bad_verb" ] && ok "recovery code has no reset/checkout/clean/stash/restore/rm -r/git rm/mv" || bad "recovery code contains:$bad_verb"
printf '%s\n' "$REC" | grep -qE '-ge "\$since|since=' && bad "recovery still has a since-epoch gate" || ok "no whole-second epoch gate on files"

# ---- fixtures. The guard requires /tmp/stage-*: the worktree is $D/wt under /tmp/stage-hto3.XXXX (cleaned with safe_rm_rf under the default temp roots)
D="$(mktemp -d /tmp/stage-hto3.XXXXXX)" || exit 1; [ -n "$D" ] && [ -d "$D" ] || exit 1
rmD(){ ( unset TMPDIR; safe_rm_rf "$D" ); }
trap 'safe_rm_rf "$T"; rmD' EXIT
PS=':(glob)**/alembic/versions/**'
WN=0
mkwt(){ WN=$((WN+1)); wt="$D/wt$WN"   # a fresh worktree each time (safe_rm_rf refuses git roots; $D is removed at exit)
  mkdir -p "$wt/alembic/versions" "$wt/src" "$wt/backend/alembic/versions"; git -C "$wt" init -q
  echo orig > "$wt/src/app.py"; echo r1 > "$wt/alembic/versions/0001_old.py"; echo r0 > "$wt/alembic/versions/0000_pre.py"
  git -C "$wt" add -A; git -C "$wt" "${GI[@]}" commit -qm i; }
# run: cand-setup function name, killed-call script body; the killed call is sleep-killed by a 2 s cap
run_call(){  # $1 = script file for the "helper"
  ( . "$LIB"; export OVN_HTO_LOG="$T/ag.log"; unset task_log TASK_LOG SLOG
    snap="$(ovn_hto_snapshot_untracked "$wt" "$PS")"; sent="$(ovn_hto_sentinel)"
    ovn_hto 2 alembic_autogen bash "$1" "$wt"; [ $? -eq 124 ] && ovn_hto_git_recover "$wt" "$snap" "$sent"
    ovn_hto_recover_done "$snap" "$sent" ) 
}
cat > "$T/ag.sh" <<'EOS'
#!/usr/bin/env bash
cd "$1"; sleep 0.3
echo newrev > alembic/versions/0002_new.py          # NEW untracked file: must be removed
echo newdeep > backend/alembic/versions/0005_new.py # NEW untracked, nested versions dir: removed
echo staged > alembic/versions/0003_staged.py; git add alembic/versions/0003_staged.py   # staged-new debris: left
echo clobbered >> alembic/versions/0001_old.py       # modified-tracked debris: left
echo src-new > src/outside_pathspec.py               # outside pathspec: never touched
touch .git/index.lock; sleep 30
EOS
# candidates written IMMEDIATELY before the call (same wall-clock second, no touch -t), re-saved during the call, and old-mtime
mkwt
echo CANDIDATE >> "$wt/src/app.py"                                  # tracked edit
echo cand-mig >> "$wt/alembic/versions/0000_pre.py"                 # tracked edit inside the pathspec
echo cand-staged > "$wt/alembic/versions/0006_cand_staged.py"; git -C "$wt" add alembic/versions/0006_cand_staged.py   # staged new file
echo cand-untracked > "$wt/alembic/versions/0007_cand_untracked.py" # untracked new file written in the SAME SECOND as the call start
echo cand-old > "$wt/alembic/versions/0008_old_debris.py"; touch -t 202001010000 "$wt/alembic/versions/0008_old_debris.py"   # old-mtime untracked
cat > "$T/ag_resave.sh" <<'EOS'
#!/usr/bin/env bash
cd "$1"; sleep 0.3; touch alembic/versions/0007_cand_untracked.py alembic/versions/0000_pre.py alembic/versions/0006_cand_staged.py src/app.py   # re-save candidates during the call
cat "$(dirname "$0")/ag.sh" | tail -n +2 | sed 's/^cd "\$1"; sleep 0.3//' > "$(dirname "$0")/ag_body.sh"
EOS
cat "$T/ag.sh" > "$T/ag_all.sh"; sed -i.bak '2s/.*/cd "$1"; sleep 0.3; touch alembic\/versions\/0007_cand_untracked.py alembic\/versions\/0000_pre.py alembic\/versions\/0006_cand_staged.py src\/app.py/' "$T/ag_all.sh"; rm -f "$T/ag_all.sh.bak"
run_call "$T/ag_all.sh"
{ grep -q CANDIDATE "$wt/src/app.py" && grep -q cand-mig "$wt/alembic/versions/0000_pre.py"; } && ok "candidate TRACKED edits survive (incl. re-saved during the call)" || bad "candidate tracked edit lost"
[ "$(cat "$wt/alembic/versions/0006_cand_staged.py" 2>/dev/null)" = cand-staged ] && git -C "$wt" diff --cached --name-only | grep -q 0006_cand_staged && ok "candidate STAGED new file survives, still staged" || bad "candidate staged new file lost/unstaged"
[ "$(cat "$wt/alembic/versions/0007_cand_untracked.py" 2>/dev/null)" = cand-untracked ] && ok "candidate untracked file written in the same second as the call (and re-saved) survives" || bad "same-second/re-saved candidate untracked file destroyed"
[ "$(cat "$wt/alembic/versions/0008_old_debris.py" 2>/dev/null)" = cand-old ] && ok "pre-existing old-mtime untracked file survives" || bad "pre-existing old-mtime untracked file destroyed"
{ [ ! -e "$wt/alembic/versions/0002_new.py" ] && [ ! -e "$wt/backend/alembic/versions/0005_new.py" ]; } && ok "the killed call's NEW untracked files (not in the snapshot; incl. nested backend/alembic/versions) are removed" || bad "new untracked debris left"
[ -f "$wt/src/outside_pathspec.py" ] && ok "a new untracked file OUTSIDE the pathspec is not touched" || bad "file outside the pathspec removed"
{ [ -f "$wt/alembic/versions/0003_staged.py" ] && git -C "$wt" diff --cached --name-only | grep -q 0003_staged; } && ok "staged-new debris of the killed call is LEFT (documented: never destroy staged work)" || bad "staged debris was cleaned"
grep -q clobbered "$wt/alembic/versions/0001_old.py" && ok "modified-tracked debris is LEFT (documented)" || bad "tracked file was reverted"
[ ! -e "$wt/.git/index.lock" ] && ok "index.lock newer than the sentinel is removed" || bad "fresh index.lock left"
[ -z "$(ls -d "${TMPDIR:-/tmp}"/ovn_hto_[su].* 2>/dev/null | head -1)" ] || ok "(temp dirs from other runs may exist; not asserted)"
# sub-second lock compare: offset (ms) of the lock mtime relative to the sentinel; only STRICTLY newer is ours
if type -P python3 >/dev/null 2>&1; then
  for spec in "-1:kept:older by 1 ms" "0:kept:equal mtime" "1:removed:newer by 1 ms" "-1500:kept:older by 1.5 s" "1500:removed:newer by 1.5 s" "-999:kept:older by 999 ms (same whole second)" "999:removed:newer by 999 ms (same whole second)"; do
    off="${spec%%:*}"; rest="${spec#*:}"; want="${rest%%:*}"; lbl="${rest#*:}"
    mkwt; echo CANDIDATE >> "$wt/src/app.py"
    ( . "$LIB"; sent="$(ovn_hto_sentinel)"; snap="$(ovn_hto_snapshot_untracked "$wt" "$PS")"
      python3 - "$sent" "$wt/.git/index.lock" "$off" <<'PY'
import os,sys
s=os.stat(sys.argv[1]); open(sys.argv[2],"w").close(); d=int(sys.argv[3])*1000000
os.utime(sys.argv[2],ns=(s.st_atime_ns+d,s.st_mtime_ns+d))
PY
      ovn_hto_git_recover "$wt" "$snap" "$sent"; [ -e "$wt/.git/index.lock" ] && echo kept > "$T/lk" || echo removed > "$T/lk"; ovn_hto_recover_done "$snap" "$sent" )
    [ "$(cat "$T/lk")" = "$want" ] && ok "lock $lbl: $want" || bad "lock $lbl: expected $want got $(cat "$T/lk")"
    rm -f "$wt/.git/index.lock"
  done
else echo "  SKIP: no python3 for ns utime"; fi
grep -q CANDIDATE "$wt/src/app.py" && ok "candidate intact after lock handling" || bad "candidate lost during lock handling"
# linked worktree: the lock lives in the main repo's .git/worktrees/<n>/
mkwt; git -C "$wt" branch -q lw; LW="$D/lw"; git -C "$wt" worktree add -q "$LW" lw 2>/dev/null
if [ -d "$LW" ]; then
  ( . "$LIB"; sent="$(ovn_hto_sentinel)"; sleep 0.05; lk="$(git -C "$LW" rev-parse --git-path index.lock)"; case "$lk" in /*) ;; *) lk="$LW/$lk";; esac; : > "$lk"
    ovn_hto_git_recover "$LW" "" "$sent"; [ ! -e "$lk" ] && echo ok > "$T/lw" || echo no > "$T/lw"; ovn_hto_recover_done "" "$sent" )
  [ "$(cat "$T/lw")" = ok ] && ok "linked worktree: its own index.lock is resolved via --git-path and removed" || bad "linked-worktree lock not removed"
fi
# older lock: kept in both snapshot/no-snapshot modes (sentinel made AFTER the lock)
for snapmode in snap nosnap; do
  mkwt; : > "$wt/.git/index.lock"; sleep 0.05
  ( . "$LIB"; sent="$(ovn_hto_sentinel)"; snap=""; [ $snapmode = snap ] && snap="$(ovn_hto_snapshot_untracked "$wt" "$PS")"; ovn_hto_git_recover "$wt" "$snap" "$sent"; ovn_hto_recover_done "$snap" "$sent" )
  [ -e "$wt/.git/index.lock" ] && ok "older lock kept ($snapmode)" || bad "older lock removed ($snapmode)"
  rm -f "$wt/.git/index.lock"
done
# a missing sentinel removes nothing
mkwt; : > "$wt/.git/index.lock"; ( . "$LIB"; ovn_hto_git_recover "$wt" "" "" ); [ -e "$wt/.git/index.lock" ] && ok "no sentinel => no lock removal" || bad "lock removed without a sentinel"; rm -f "$wt/.git/index.lock"
# no snapshot => no file removal even when new untracked files exist
mkwt; echo late > "$wt/alembic/versions/0004_late.py"; ( . "$LIB"; sent="$(ovn_hto_sentinel)"; ovn_hto_git_recover "$wt" "" "$sent"; ovn_hto_recover_done "" "$sent" ); [ -f "$wt/alembic/versions/0004_late.py" ] && ok "empty snapshot => locks only, no file touched" || bad "files removed without a snapshot"
# a TRACKED file that is also absent from the snapshot list (never listed as untracked) is never deleted even if it vanished from the index race
mkwt; ( . "$LIB"; snap="$(ovn_hto_snapshot_untracked "$wt" "$PS")"; sent="$(ovn_hto_sentinel)"; git -C "$wt" rm -q --cached alembic/versions/0001_old.py; git -C "$wt" "${GI[@]}" reset -q 2>/dev/null; ovn_hto_git_recover "$wt" "$snap" "$sent"; ovn_hto_recover_done "$snap" "$sent" ) 2>/dev/null
echo "== guard: refuse on empty / wrong worktree (nothing changed, one log line)"
mkgd(){ g="$1"; mkdir -p "$g/alembic/versions"; git -C "$g" init -q; echo x > "$g/alembic/versions/0001.py"; git -C "$g" add -A; git -C "$g" "${GI[@]}" commit -qm i; : > "$g/.git/index.lock"; }
guard_case(){  # $1 label $2 dir
  rm -f "$T/ag.log"; ( . "$LIB"; export OVN_HTO_LOG="$T/ag.log"; unset task_log TASK_LOG
    sent="$(ovn_hto_sentinel)"; sleep 0.05; [ -d "$2" ] && { echo fresh > "$2/alembic/versions/0099_new.py"; : > "$2/.git/index.lock"; }
    s2="$(ovn_hto_snapshot_untracked "$2" "$PS")"; ovn_hto_git_recover "$2" "$s2" "$sent"; echo "snap=[$s2]" > "$T/gsnap"; ovn_hto_recover_done "" "$sent" )
  [ -z "$2" ] || { [ -f "$2/alembic/versions/0099_new.py" ] && [ -e "$2/.git/index.lock" ]; } && ok "$1: nothing removed" || bad "$1: guard let recovery modify the tree"
  grep -q 'helper-recover: ovn_hto_git_recover refused' "$T/ag.log" && ok "$1: refusal is logged" || bad "$1: refusal not logged"
  [ "$(cat "$T/gsnap")" = "snap=[]" ] && ok "$1: snapshot refused too" || bad "$1: snapshot not refused: $(cat "$T/gsnap")"
}
mkgd "$T/notstage"; guard_case "not a /tmp/stage-* dir" "$T/notstage"
mkdir -p "$D/overnight-queue/repos"; mkgd "$D/overnight-queue/repos/r"; guard_case "under overnight-queue/repos" "$D/overnight-queue/repos/r"
ln -s "$T/notstage" "$D/link_to_notstage"; guard_case "symlink into a non-stage dir" "$D/link_to_notstage"
rm -f "$T/ag.log"; ( . "$LIB"; export OVN_HTO_LOG="$T/ag.log"; ovn_hto_git_recover "" "" "" ; ovn_hto_git_recover "$D/does-not-exist" "" "" ); [ "$(grep -c 'refused' "$T/ag.log")" = 2 ] && ok "empty and non-directory worktree refused and logged" || bad "empty/nonexistent wt not refused"
( . "$LIB"; unset OVN_HTO_LOG task_log TASK_LOG; cd "$T/notstage"; echo keepme > alembic/versions/0100.py; ovn_hto_git_recover "" "" "$(ovn_hto_sentinel)" ); [ -f "$T/notstage/alembic/versions/0100.py" ] && ok "empty wt with cwd inside a repo touches nothing" || bad "empty wt acted on cwd"
exit $rc
