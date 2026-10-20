#!/usr/bin/env bash
# test_mac_bridge_e2e.sh - L2-mac-jobs END TO END: the REAL scripts/overnight-queue/claude_queue_bridge.sh run from a dedicated live checkout (default SHARED = the checkout the script lives in),
# with stub ssh/scp (no network, no box) against a local bare origin. Reproduces incident (c): the bridge could not push for 3h because the shared checkout was a detached HEAD inside a stale
# rebase. Asserts: pushes with the explicit refspec, repairs the wedge in enforce, refuses (loudly, exit 1, NO success heartbeat) in shadow, merges (never rebases) when origin moved.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_mac_fixture.sh" || exit 1
QDIR="$MF_SCRIPTS/overnight-queue"
for f in claude_queue_bridge.sh claude_queue_bridge.py archive_claude_queue_done.py; do [ -f "$QDIR/$f" ] || { echo "  FAIL: $QDIR/$f missing"; exit 1; }; done
mf_init
trap 'safe_rm_rf "$T"' EXIT
fails=0; n=0
ok() { n=$((n+1)); if [ "$2" = 0 ]; then echo "  ok   $1"; else echo "  FAIL $1"; fails=$((fails+1)); fi; }
chk() { local d="$1"; shift; "$@" >/dev/null 2>&1; ok "$d" $?; }
printf '#!/bin/sh\necho "scp $*" >> "$CALLS"\nexit 0\n' > "$T/bin/scp"; chmod 755 "$T/bin/scp"
# seed origin develop with the real bridge + mac scripts and a queue holding two completed items
mkdir -p "$PUSHER/scripts/overnight-queue"
cp "$QDIR/claude_queue_bridge.sh" "$QDIR/claude_queue_bridge.py" "$QDIR/archive_claude_queue_done.py" "$PUSHER/scripts/overnight-queue/"
cp "$MF_SCRIPTS"/mac_*.sh "$PUSHER/scripts/"
newq() { # newq <tag>: queue with a completed item that the bridge's archive pass will move; commit+push through the pusher
  git -C "$PUSHER" pull -q --no-rebase origin develop 2>/dev/null
  printf '# Claude queue\n\n- [x] [P2] done item %s - something that was finished and ticked\n' "$1" > "$PUSHER/CLAUDE_QUEUE.md"
  git -C "$PUSHER" add -A; git -C "$PUSHER" commit -q -m "queue $1"; git -C "$PUSHER" push -q origin HEAD:refs/heads/develop
}
newq seed
RN=0
fresh() { RN=$((RN+1)); export OVN_MAC_STATE="$T/st$RN" LIVE="$T/home/LocalProjects/live$RN"; mkdir -p "$OVN_MAC_STATE"; : > "$CALLS"; mf_live_clone; }
bridge() { # bridge <mode> [script]  -> RC ; output $T/out.txt
  local m="$1" s="${2:-$LIVE/scripts/overnight-queue/claude_queue_bridge.sh}"
  ( export PATH="$T/bin:$PATH" OVN_MAC_JOBS="$m" MAC_LIVE_DIR="$LIVE" MAC_LIVE_ORIGIN="$ORIGIN" TMPDIR="$T"; [ -n "${SD:-}" ] && export SHARED_DIR="$SD"; bash "$s" > "$T/out.txt" 2>&1 < /dev/null ); RC=$?
}
oshow() { git --git-dir="$ORIGIN" show "develop:$1" 2>/dev/null; }

echo "== clean run from the live checkout (SHARED defaults to the script's own checkout)"
fresh; bridge enforce
chk "rc 0; the archive pass moved the item and the commit reached origin develop" bash -c "[ $RC -eq 0 ] && ! git --git-dir='$ORIGIN' show develop:CLAUDE_QUEUE.md | grep -q 'done item seed' && git --git-dir='$ORIGIN' show develop:CLAUDE_QUEUE_DONE.md | grep -q 'done item seed'"
chk "success heartbeat written (supervisor sees the bridge alive)" test -s "$OVN_MAC_STATE/hb/claudequeuebridge"
chk "the bridge never touched the network except through the stub ssh (no scp, no real host)" bash -c "! grep -q '^scp' '$CALLS'"
chk "live checkout is attached to develop-live and clean afterwards" bash -c "[ \"\$(git -C '$LIVE' symbolic-ref --short HEAD)\" = develop-live ] && [ -z \"\$(git -C '$LIVE' status --porcelain --untracked-files=no)\" ]"
chk "log shows 'pushed ... to origin/develop'" grep -q "pushed .* to origin/develop" "$T/out.txt"

echo "== INCIDENT: live checkout detached inside a stale rebase"
newq two; fresh; newq three
mf_wedge_rebase "$LIVE" README.md || { echo "  FAIL fixture: wedge"; exit 1; }
bridge enforce
chk "enforce: the start-of-run sync recovers the wedge, the pass completes rc 0 and pushes" bash -c "[ $RC -eq 0 ] && [ ! -d '$LIVE/.git/rebase-merge' ] && [ \"\$(git -C '$LIVE' symbolic-ref --short HEAD)\" = develop-live ] && grep -q 'RECOVERED' '$T/out.txt' && git --git-dir='$ORIGIN' show develop:CLAUDE_QUEUE_DONE.md | grep -q 'done item three'"
chk "heartbeat written after the recovered pass" test -s "$OVN_MAC_STATE/hb/claudequeuebridge"
newq four; fresh; newq five; mf_wedge_rebase "$LIVE" README.md || { echo "  FAIL fixture: wedge"; exit 1; }; hbf="$OVN_MAC_STATE/hb/claudequeuebridge"; before="$(git -C "$LIVE" rev-parse HEAD)"; : > "$CALLS"
bridge shadow
chk "shadow: exit 1 (launchd shows the failure), NO success heartbeat, wedge untouched" bash -c "[ $RC -eq 1 ] && [ ! -e '$hbf' ] && [ -d '$LIVE/.git/rebase-merge' ] && [ \"\$(git -C '$LIVE' rev-parse HEAD)\" = '$before' ]"
chk "shadow: the failure is LOUD (emergency push to the relay + alerts.log)" bash -c "grep -q 'X-Ovn-Level: emergency' '$CALLS' && grep -qi 'wedged\|cannot push' '$OVN_MAC_STATE/alerts.log'"
chk "shadow: nothing was pushed to origin by the refused pass" bash -c "! git --git-dir='$ORIGIN' show develop:CLAUDE_QUEUE_DONE.md | grep -q 'done item five'"

echo "== origin moved between commit and push -> merge, not rebase"
newq six; fresh; rm -f "$T/hook.done"
printf '%s\n' 'git -C "$PUSHER" pull -q --no-rebase origin develop' 'echo "readme moved under the bridge" > "$PUSHER/README.md"' 'git -C "$PUSHER" add -A; git -C "$PUSHER" commit -q -m hook-up; git -C "$PUSHER" push -q origin HEAD:refs/heads/develop' > "$T/hook.sh"
MF_SSH_HOOK="sh $T/hook.sh" bridge enforce       # the stub ssh (called mid-run, AFTER the start sync) moves origin, so Pass E's first push is rejected
chk "the first push was really rejected (origin moved mid-run) and the pass still succeeded" grep -q "attempt 1/3 rejected" "$T/out.txt"
chk "rc 0, both the bridge's queue change and the upstream README change are on origin develop" bash -c "[ $RC -eq 0 ] && git --git-dir='$ORIGIN' show develop:README.md | grep -q 'moved under the bridge' && git --git-dir='$ORIGIN' show develop:CLAUDE_QUEUE_DONE.md | grep -q 'done item six'"
chk "no rebase state left in the live checkout" bash -c "[ ! -d '$LIVE/.git/rebase-merge' ] && [ ! -d '$LIVE/.git/rebase-apply' ]"

echo "== a failing push is a failing job (no fake success heartbeat)"
newq seven; fresh; printf '#!/bin/sh\necho "remote: rejected" >&2\nexit 1\n' > "$ORIGIN/hooks/pre-receive"; chmod 755 "$ORIGIN/hooks/pre-receive"
MAC_PUSH_TRIES=2 bridge enforce
chk "push rejected every time: exit 1 and no success heartbeat" bash -c "[ $RC -eq 1 ] && [ ! -e '$OVN_MAC_STATE/hb/claudequeuebridge' ]"
rm -f "$ORIGIN/hooks/pre-receive"

echo "== mutants"
MUT="$T/mut"; mkdir -p "$MUT"
mutate "$QDIR/claude_queue_bridge.sh" "$MUT/m1.sh" 'commit_rc="${PIPESTATUS[0]}"' 'commit_rc=0' && {
  newq eight; fresh; printf '#!/bin/sh\nexit 1\n' > "$ORIGIN/hooks/pre-receive"; chmod 755 "$ORIGIN/hooks/pre-receive"
  SD="$LIVE" MAC_PUSH_TRIES=2 bridge enforce "$MUT/m1.sh"; SD=""
  chk "M1 (commit failure ignored) is caught: a heartbeat was written although the push failed" test -s "$OVN_MAC_STATE/hb/claudequeuebridge"
  rm -f "$ORIGIN/hooks/pre-receive"; }
mutate "$QDIR/claude_queue_bridge.sh" "$MUT/m2.sh" 'if [ -f "$COMMIT_HELPER" ]; then' 'if false; then' && {
  newq nine; fresh; SD="$LIVE" bridge enforce "$MUT/m2.sh"; SD=""
  chk "M2 (Pass E does not push) is caught: origin never got the archive commit" bash -c "! git --git-dir='$ORIGIN' show develop:CLAUDE_QUEUE_DONE.md | grep -q 'done item nine'"; }
mutate "$QDIR/claude_queue_bridge.sh" "$MUT/m3.sh" 'SHARED="${SHARED_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"' 'SHARED="${SHARED_DIR:-$HOME/LocalProjects/shared}"' && {
  newq ten; fresh; mkdir -p "$T/home/LocalProjects/shared"; SD="" bridge enforce "$MUT/m3.sh"
  chk "M3 (hard-coded interactive default) is caught: the live checkout was not used (no push)" bash -c "! git --git-dir='$ORIGIN' show develop:CLAUDE_QUEUE_DONE.md | grep -q 'done item ten'"; }

echo; echo "mac_bridge_e2e: $((n-fails))/$n passed"; [ "$fails" = 0 ]
