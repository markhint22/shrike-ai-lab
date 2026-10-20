#!/usr/bin/env bash
# test_mac_review_fixes.sh - L2-mac-jobs ADVERSARIAL REVIEW (2026-10-19): regression tests for the defects the review found. Hermetic (lib_mac_fixture.sh). Every fix has a mutant that must FAIL its scenario.
#   D1 live-sync called a bridge pass's own queue-doc edits a "dirty live checkout" EMERGENCY (sync every 5 min vs a pass that edits CLAUDE_QUEUE*.md for ~a minute every hour), and a killed pass left a
#      dirty tree that blocked the fast-forward until the next pass; the bridge also could overlap itself. Fix: bridge.lock + queue-only residue handling.
#   D2 mac_lock_acquire stale takeover was racy (two contenders both "won"). Fix: mkdir guard + re-judge under the guard.
#   D3 mac_jobs_install --apply ran `launchctl bootout` on RUNNING jobs (kills a 4h fleet review / a mid-commit bridge). Fix: defer running labels (rc 4) unless --force-running.
#   D5 a commit left unpushed by an earlier pass (kill -9 between commit and push, or rc 3) was never pushed once the next pass had "no changes" (rc 0 + success heartbeat while origin lacked it).
#   D4 the qa-notes-bridge plist would read qa/manual_logs from the never-interactive live copy, so notes typed by scripts/qa-log in the interactive checkout were never bridged. Fix: QA_NOTES_LOGS_DIR.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_mac_fixture.sh" || exit 1
SYNC="$MF_SCRIPTS/mac_live_sync.sh"; LIB="$MF_SCRIPTS/mac_lib.sh"; INST="$MF_SCRIPTS/mac_jobs_install.sh"; TPL="$MF_SCRIPTS/mac_jobs/templates"; QDIR="$MF_SCRIPTS/overnight-queue"
for f in "$SYNC" "$LIB" "$INST" "$QDIR/claude_queue_bridge.sh"; do [ -f "$f" ] || { echo "  FAIL: $f missing"; exit 1; }; done
mf_init
trap 'safe_rm_rf "$T"' EXIT
fails=0; n=0
ok() { n=$((n+1)); if [ "$2" = 0 ]; then echo "  ok   $1"; else echo "  FAIL $1"; fails=$((fails+1)); fi; }
chk() { local d="$1"; shift; "$@" >/dev/null 2>&1; ok "$d" $?; }
RN=0
fresh() { RN=$((RN+1)); export OVN_MAC_STATE="$T/state$RN" LIVE="$T/home/LocalProjects/live$RN"; mkdir -p "$OVN_MAC_STATE"; : > "$CALLS"; mf_live_clone; }
sync_() { # sync_ <mode> [script]
  OVN_MAC_JOBS="$1" MAC_LIVE_DIR="$LIVE" timeout 60 bash "${2:-$SYNC}" > "$T/out.txt" 2>&1 < /dev/null; RC=$?
}
st() { python3 -c "import json;print(json.load(open('$OVN_MAC_STATE/live_sync.json'))['state'])" 2>/dev/null; }
holder() { sleep 60 & HPID=$!; mkdir -p "$OVN_MAC_STATE/bridge.lock"; echo "$HPID" > "$OVN_MAC_STATE/bridge.lock/pid"; }   # a live "bridge pass"
unholder() { kill "$HPID" 2>/dev/null; wait "$HPID" 2>/dev/null; rm -f "$OVN_MAC_STATE/bridge.lock/pid"; rmdir "$OVN_MAC_STATE/bridge.lock" 2>/dev/null; }

echo "== D1: live-sync vs the bridge's own queue-doc edits"
fresh; holder; echo "harvested by the running pass" >> "$LIVE/CLAUDE_QUEUE.md"; h0="$(git -C "$LIVE" rev-parse HEAD)"; : > "$CALLS"
sync_ enforce
chk "bridge pass running (live pid holds bridge.lock): state ok, NOT dirty, no emergency alert, queue edit untouched" bash -c "[ \"\$(python3 -c \"import json;print(json.load(open('$OVN_MAC_STATE/live_sync.json'))['state'])\")\" = ok ] && ! grep -q 'X-Ovn-Level: emergency' '$CALLS' && grep -q 'harvested by the running pass' '$LIVE/CLAUDE_QUEUE.md'"
unholder
fresh; echo "left by a kill -9'd pass" >> "$LIVE/CLAUDE_QUEUE.md"; mf_up_commit README.md "readme moved" "up readme"; : > "$CALLS"
sync_ enforce
chk "no pass running + queue-only residue (enforce): patch saved, queue doc restored, checkout fast-forwarded to origin, state ok" bash -c "[ \"$(st)\" = ok ] && ! grep -q 'left by a kill' '$LIVE/CLAUDE_QUEUE.md' && ls '$OVN_MAC_STATE'/rescue/residue-*.patch >/dev/null && grep -q 'left by a kill' '$OVN_MAC_STATE'/rescue/residue-*.patch && [ \"\$(git -C '$LIVE' rev-parse HEAD)\" = \"\$(git --git-dir='$ORIGIN' rev-parse develop)\" ] && ! grep -q 'X-Ovn-Level: emergency' '$CALLS'"
fresh; echo "left by a kill -9'd pass" >> "$LIVE/CLAUDE_QUEUE.md"; : > "$CALLS"
sync_ shadow
chk "shadow + queue-only residue: reported as bridge_residue, tree untouched, no emergency" bash -c "[ \"$(st)\" = bridge_residue ] && grep -q 'left by a kill' '$LIVE/CLAUDE_QUEUE.md' && ! grep -q 'X-Ovn-Level: emergency' '$CALLS'"
fresh; echo "stray" >> "$LIVE/README.md"; sync_ enforce
chk "REGRESSION GUARD: a dirty NON-queue file is still refused (state dirty, file kept)" bash -c "[ \"$(st)\" = dirty ] && grep -q stray '$LIVE/README.md'"
fresh; echo "q" >> "$LIVE/CLAUDE_QUEUE.md"; echo "stray" >> "$LIVE/README.md"; sync_ enforce
chk "REGRESSION GUARD: queue doc + a non-queue file dirty together is refused, nothing discarded" bash -c "[ \"$(st)\" = dirty ] && grep -q stray '$LIVE/README.md' && grep -q '^q\$' '$LIVE/CLAUDE_QUEUE.md'"
fresh; holder; echo "stray" >> "$LIVE/README.md"; sync_ enforce; unholder
chk "REGRESSION GUARD: a held bridge.lock does NOT excuse a non-queue dirty file" bash -c "[ \"$(st)\" = dirty ]"

echo "== D1 bridge: one pass at a time, lock visible to live-sync during the pass and gone afterwards"
printf '#!/bin/sh\necho "scp $*" >> "$CALLS"\nexit 0\n' > "$T/bin/scp"; chmod 755 "$T/bin/scp"
mkdir -p "$PUSHER/scripts/overnight-queue"; cp "$QDIR/claude_queue_bridge.sh" "$QDIR/claude_queue_bridge.py" "$QDIR/archive_claude_queue_done.py" "$PUSHER/scripts/overnight-queue/"; cp "$MF_SCRIPTS"/mac_*.sh "$PUSHER/scripts/"
git -C "$PUSHER" pull -q --no-rebase origin develop 2>/dev/null; printf '# Claude queue\n\n- [x] [P2] done item r1 - finished and ticked\n' > "$PUSHER/CLAUDE_QUEUE.md"; git -C "$PUSHER" add -A; git -C "$PUSHER" commit -q -m seedbridge; git -C "$PUSHER" push -q origin HEAD:refs/heads/develop
bridge() { # bridge [script]
  ( export PATH="$T/bin:$PATH" OVN_MAC_JOBS=enforce MAC_LIVE_DIR="$LIVE" MAC_LIVE_ORIGIN="$ORIGIN" TMPDIR="$T"; bash "${1:-$LIVE/scripts/overnight-queue/claude_queue_bridge.sh}" > "$T/out.txt" 2>&1 < /dev/null ); RC=$?
}
fresh; rm -f "$T/hook.done" "$T/lockseen"
printf '%s\n' 'if [ -d "$OVN_MAC_STATE/bridge.lock" ]; then echo seen > "$T/lockseen"; cat "$OVN_MAC_STATE/bridge.lock/pid" > "$T/lockpid"; fi' > "$T/hook.sh"
MF_SSH_HOOK="sh $T/hook.sh" bridge
chk "during the pass bridge.lock exists and names a pid; after the pass it is released; the pass still succeeded and pushed" bash -c "[ -s '$T/lockseen' ] && [ -s '$T/lockpid' ] && [ ! -d '$OVN_MAC_STATE/bridge.lock' ] && [ $RC -eq 0 ] && git --git-dir='$ORIGIN' show develop:CLAUDE_QUEUE_DONE.md | grep -q 'done item r1'"
fresh; holder; : > "$CALLS"; bridge; unholder
chk "a second pass while a live one holds the lock: exits 0, says so, touches neither ssh nor the queue, writes no success heartbeat" bash -c "[ $RC -eq 0 ] && grep -q 'another bridge pass holds' '$T/out.txt' && ! grep -q '^ssh' '$CALLS' && [ ! -e '$OVN_MAC_STATE/hb/claudequeuebridge' ]"
fresh; mkdir -p "$OVN_MAC_STATE/bridge.lock"; echo 99999999 > "$OVN_MAC_STATE/bridge.lock/pid"; bridge
chk "a lock left by a kill -9'd pass (dead pid) is taken over; the pass runs and the lock is released" bash -c "[ $RC -eq 0 ] && [ ! -d '$OVN_MAC_STATE/bridge.lock' ] && [ -s '$OVN_MAC_STATE/hb/claudequeuebridge' ]"

echo "== D2: stale-lock takeover must have exactly one winner"
race() { # race <lib> <trials> -> prints number of trials where two contenders held the lock at once
  ( export OVN_MAC_STATE="$T/racestate"; mkdir -p "$OVN_MAC_STATE"; . "$1"; bad=0; t=0
    while [ "$t" -lt "$2" ]; do
      t=$((t+1)); L="$OVN_MAC_STATE/trial.lock"; D="$OVN_MAC_STATE/trial.d"; rm -f "$L/pid"; rmdir "$L" 2>/dev/null; rmdir "$L.take" 2>/dev/null; rm -f "$D/v"; rmdir "$D" 2>/dev/null; rm -f "$OVN_MAC_STATE/viol"
      mkdir -p "$L"; echo 99999999 > "$L/pid"
      for i in 1 2 3 4 5 6; do ( mac_lock_acquire "$L" 1800 2>/dev/null && { mkdir "$D" 2>/dev/null || echo v >> "$OVN_MAC_STATE/viol"; sleep 0.25; rmdir "$D" 2>/dev/null; mac_lock_release "$L"; } ) & done; wait
      [ -s "$OVN_MAC_STATE/viol" ] && bad=$((bad+1))
    done; echo "$bad" )
}
r="$(race "$LIB" 20)"
chk "20 trials x 6 contenders over a dead-owner lock: never two owners at once (got $r bad trials)" test "$r" = 0
git -C "$MF_REPO" show d394694:scripts/mac_lib.sh > "$T/old_lib.sh" 2>/dev/null || cp "$LIB" "$T/old_lib.sh"
if grep -q '_mac_lock_is_stale' "$T/old_lib.sh"; then python3 - "$LIB" "$T/old_lib.sh" <<'PYEOF'
import sys,re
s=open(sys.argv[1]).read()
a=s.index('mac_lock_acquire() {'); b=s.index('_mac_lock_is_stale() {')
old='''mac_lock_acquire() {
  local l="$1" stale="${2:-1800}" pid age
  mkdir -p "$(dirname "$l")" 2>/dev/null
  if mkdir "$l" 2>/dev/null; then echo "$$" > "$l/pid"; return 0; fi
  pid="$(cat "$l/pid" 2>/dev/null)"
  age=$(( $(mac_now) - $(mac_mtime "$l") ))
  if { [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; } || [ "$age" -gt "$stale" ] || { [ -z "$pid" ] && [ "$age" -gt 60 ]; }; then
    rm -f "$l/pid"; rmdir "$l" 2>/dev/null
    if mkdir "$l" 2>/dev/null; then echo "$$" > "$l/pid"; return 0; fi
  fi
  return 1
}
'''
open(sys.argv[2],'w').write(s[:a]+old+s[b:])
PYEOF
fi
r="$(race "$T/old_lib.sh" 20)"
chk "MUTANT D2 (the original unguarded takeover) is caught: two owners in at least one trial (got $r bad trials)" bash -c "[ '$r' -gt 0 ]"

echo "== D3: installer must not bootout a RUNNING job"
INSTD="$T/home/inst"; mkdir -p "$INSTD"
instfresh() { RN=$((RN+1)); export OVN_MAC_STATE="$T/ist$RN" LIVE="$T/home/LocalProjects/ilive$RN" AGENTS="$T/home/Library/ILA$RN"; mkdir -p "$OVN_MAC_STATE" "$AGENTS" "$LIVE/.git"; : > "$CALLS"; : > "$T/launchctl.table"
  for p in $(grep -ho '@LIVE@/[^<]*' "$TPL"/*.plist | sed "s|@LIVE@|$LIVE|"); do mkdir -p "$(dirname "$p")"; : > "$p"; done; : > "$LIVE/.git/ovn_live_checkout"; }
inst() { MAC_LIVE_DIR="$LIVE" MAC_LAUNCH_AGENTS_DIR="$AGENTS" MAC_JOBS_UID=501 bash "${INSTS:-$INST}" "$@" > "$T/out.txt" 2>&1 < /dev/null; RC=$?; }
instfresh; printf '4242\t0\tcom.shrike.fleet-review\n' > "$T/launchctl.table"; sed -e "s|@LIVE@|$LIVE|g" -e "s|@HOME@|$HOME|g" "$TPL/com.shrike.fleet-review.plist" | sed 's|fleet_review/run_review.sh|OLD/run_review.sh|' > "$AGENTS/com.shrike.fleet-review.plist"; fr_before="$(cksum < "$AGENTS/com.shrike.fleet-review.plist")"
inst --apply
chk "running fleet-review (pid 4242) is DEFERRED: no bootout of it, plist untouched, rc 4, others installed" bash -c "[ $RC -eq 4 ] && grep -q 'DEFERRED  com.shrike.fleet-review' '$T/out.txt' && ! grep -q 'bootout gui/501/com.shrike.fleet-review' '$CALLS' && [ \"\$(cksum < '$AGENTS/com.shrike.fleet-review.plist')\" = '$fr_before' ] && [ -f '$AGENTS/com.shrike.mac-live-sync.plist' ] && grep -q 'bootstrap.*mac-live-sync' '$CALLS'"
: > "$CALLS"; inst --apply --force-running
chk "--force-running replaces it anyway (bootout + new plist), rc 0" bash -c "[ $RC -eq 0 ] && grep -q 'bootout gui/501/com.shrike.fleet-review' '$CALLS' && grep -q '$HOME/fleet_review/run_review.sh' '$AGENTS/com.shrike.fleet-review.plist'"
instfresh; printf -- '-\t0\tcom.shrike.fleet-review\n' > "$T/launchctl.table"; sed -e "s|@LIVE@|$LIVE|g" -e "s|@HOME@|$HOME|g" "$TPL/com.shrike.fleet-review.plist" | sed 's|fleet_review/run_review.sh|OLD/run_review.sh|' > "$AGENTS/com.shrike.fleet-review.plist"; inst --apply
chk "an IDLE loaded job (pid '-') is replaced normally, rc 0" bash -c "[ $RC -eq 0 ] && grep -q 'bootout gui/501/com.shrike.fleet-review' '$CALLS'"
python3 - "$INST" "$T/inst_m1.sh" <<'PYEOF'
import sys
s=open(sys.argv[1]).read(); o='if [ -n "$rp" ] && [ "$FORCE_RUNNING" != 1 ]; then'; assert s.count(o)==1
open(sys.argv[2],'w').write(s.replace(o,'if false; then'))
PYEOF
cp "$T/inst_m1.sh" "$MF_SCRIPTS/.mut_install_$$.sh"; INSTS="$MF_SCRIPTS/.mut_install_$$.sh"
instfresh; printf '4242\t0\tcom.shrike.fleet-review\n' > "$T/launchctl.table"; sed -e "s|@LIVE@|$LIVE|g" -e "s|@HOME@|$HOME|g" "$TPL/com.shrike.fleet-review.plist" | sed 's|fleet_review/run_review.sh|OLD/run_review.sh|' > "$AGENTS/com.shrike.fleet-review.plist"; inst --apply
chk "MUTANT D3 (no running-job check) is caught: the running job IS booted out" bash -c "grep -q 'bootout gui/501/com.shrike.fleet-review' '$CALLS'"
rm -f "$MF_SCRIPTS/.mut_install_$$.sh"; INSTS=""

echo "== D4: qa-notes-bridge reads the notes the human writes (interactive checkout), not the live copy"
tpl_reads_interactive() { sed -e "s|@LIVE@|$LIVE|g" -e "s|@HOME@|$HOME|g" "$1" | grep -q "<key>QA_NOTES_LOGS_DIR</key><string>$HOME/LocalProjects/shared/qa/manual_logs</string>"; }
chk "rendered qa-notes-bridge plist sets QA_NOTES_LOGS_DIR to the interactive checkout's qa/manual_logs" tpl_reads_interactive "$TPL/com.shrike.qa-notes-bridge.plist"
chk "qa-notes-bridge.sh really honours QA_NOTES_LOGS_DIR (override beats \$SHARED/qa/manual_logs)" grep -q 'LOGS_DIR="${QA_NOTES_LOGS_DIR:-$SHARED/qa/manual_logs}"' "$MF_SCRIPTS/qa-notes-bridge.sh"
sed '/QA_NOTES_LOGS_DIR/d' "$TPL/com.shrike.qa-notes-bridge.plist" > "$T/tpl_m.plist"
chk "MUTANT D4 (template without the env key) is caught by the same check" bash -c "$(declare -f tpl_reads_interactive); LIVE='$LIVE'; ! tpl_reads_interactive '$T/tpl_m.plist'"

echo "== mutants for D1 (live-sync)"
mut_sync() { # mut_sync <name> <old> <new> <scenario-desc> <check cmd...>   (mutated copy lives next to mac_lib.sh so HERE resolves)
  local nm="$1" o="$2" w="$3" d="$4"; shift 4
  mutate "$SYNC" "$MF_SCRIPTS/.mut_sync_$nm.sh" "$o" "$w" || { ok "$nm: mutation anchor" 1; return; }
  "$@"; rm -f "$MF_SCRIPTS/.mut_sync_$nm.sh"
}
m1() { fresh; holder; echo "inflight-edit" >> "$LIVE/CLAUDE_QUEUE.md"; : > "$CALLS"; sync_ enforce "$MF_SCRIPTS/.mut_sync_M1.sh"; unholder; ! grep -q inflight-edit "$LIVE/CLAUDE_QUEUE.md"; ok "M1 (bridge.lock ignored) is caught: the running pass's in-flight edit was discarded" $?; }
mut_sync M1 'if mac_lock_held "$OVN_MAC_STATE/bridge.lock" 3600; then' 'if false; then' x m1
m2() { fresh; echo "stray" >> "$LIVE/README.md"; sync_ enforce "$MF_SCRIPTS/.mut_sync_M2.sh"; ! grep -q stray "$LIVE/README.md"; ok "M2 (every dirty file treated as a queue doc) is caught: the stray README edit was discarded" $?; }
mut_sync M2 '[ "$f" = "$q" ] && ok=1; done; [ "$ok" = 1 ] || { q_only=0; break; }; done
  if [ "$q_only" = 1 ]; then
    if mac_lock_held' '[ "$f" = "$q" ] && ok=1; done; ok=1; [ "$ok" = 1 ] || { q_only=0; break; }; done
  if [ "$q_only" = 1 ]; then
    if mac_lock_held' x m2
m3() { fresh; echo "left" >> "$LIVE/CLAUDE_QUEUE.md"; mf_up_commit README.md "r moved" "up"; sync_ enforce "$MF_SCRIPTS/.mut_sync_M3.sh"; [ "$(st)" != ok ] || grep -q left "$LIVE/CLAUDE_QUEUE.md"; ok "M3 (residue not restored) is caught: queue doc still dirty / sync not ok" $?; }
mut_sync M3 'git -C "$D" checkout -q HEAD -- $dirty_files 2>/dev/null' 'false' x m3

echo "== D5: an unpushed commit from an earlier pass is pushed by the next pass (kill -9 / failed push)"
CP="$MF_SCRIPTS/mac_live_commit_push.sh"
cp_() { # cp_ <script>
  OVN_MAC_JOBS=enforce MAC_LIVE_DIR="$LIVE" timeout 60 bash "${1:-$CP}" "$LIVE" "chore(queue): test pass" CLAUDE_QUEUE.md CLAUDE_QUEUE_DONE.md > "$T/out.txt" 2>&1 < /dev/null; RC=$?
}
fresh; echo "tick killed-before-push" >> "$LIVE/CLAUDE_QUEUE.md"; git -C "$LIVE" commit -q -am "chore(queue): earlier pass (killed before push)"; cp_
chk "unpushed queue-doc commit + no new edits: rc 0 AND origin develop now has it (was: 'no changes', origin never updated)" bash -c "[ $RC -eq 0 ] && git --git-dir='$ORIGIN' show develop:CLAUDE_QUEUE.md | grep -q killed-before-push"
fresh; echo "tick will-fail" >> "$LIVE/CLAUDE_QUEUE.md"
printf '#!/bin/sh\necho rejected-by-hook >&2\nexit 1\n' > "$ORIGIN/hooks/pre-receive"; chmod 755 "$ORIGIN/hooks/pre-receive"; cp_; rc1=$RC; rm -f "$ORIGIN/hooks/pre-receive"; cp_
chk "push failed 3x (rc 3) in one pass; the NEXT pass with no new edits pushes it, rc 0" bash -c "[ $rc1 -eq 3 ] && [ $RC -eq 0 ] && git --git-dir='$ORIGIN' show develop:CLAUDE_QUEUE.md | grep -q will-fail"
fresh; echo "private work" >> "$LIVE/README.md"; git -C "$LIVE" commit -q -am "local README work (not a queue doc)"; od="$(git --git-dir="$ORIGIN" rev-parse develop)"; cp_
chk "REGRESSION GUARD: an unpushed commit touching a NON-named file is NOT published; rc 0 'no changes', origin untouched" bash -c "[ $RC -eq 0 ] && grep -q 'no changes' '$T/out.txt' && [ \"\$(git --git-dir='$ORIGIN' rev-parse develop)\" = '$od' ]"
fresh; cp_
chk "REGRESSION GUARD: nothing to do at all (even with origin) stays 'no changes', rc 0" bash -c "[ $RC -eq 0 ] && grep -q 'no changes' '$T/out.txt'"
mutate "$CP" "$MF_SCRIPTS/.mut_cp_M4.sh" 'if [ "${ahead:-0}" -gt 0 ] && only_named "$@"; then pending=1' 'if false; then pending=1' && {
  fresh; echo "tick m4-unique" >> "$LIVE/CLAUDE_QUEUE.md"; git -C "$LIVE" commit -q -am "earlier pass"; cp_ "$MF_SCRIPTS/.mut_cp_M4.sh"
  git --git-dir="$ORIGIN" show develop:CLAUDE_QUEUE.md | grep -q m4-unique; [ $? -ne 0 ]; ok "M4 (no pending-push branch = the original behaviour) is caught: origin never got the commit" $?; rm -f "$MF_SCRIPTS/.mut_cp_M4.sh"; }
mutate "$CP" "$MF_SCRIPTS/.mut_cp_M5.sh" 'if [ "${ahead:-0}" -gt 0 ] && only_named "$@"; then pending=1' 'if [ "${ahead:-0}" -gt 0 ]; then pending=1' && {
  fresh; echo "private work" >> "$LIVE/README.md"; git -C "$LIVE" commit -q -am "local README work"; od="$(git --git-dir="$ORIGIN" rev-parse develop)"; cp_ "$MF_SCRIPTS/.mut_cp_M5.sh"
  [ "$(git --git-dir="$ORIGIN" rev-parse develop)" != "$od" ]; ok "M5 (no only-named-paths guard) is caught: unrelated local work was published" $?; rm -f "$MF_SCRIPTS/.mut_cp_M5.sh"; }

echo "mac_review_fixes: $((n-fails))/$n passed"
[ "$fails" -eq 0 ]
