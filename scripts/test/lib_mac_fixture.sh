#!/usr/bin/env bash
# lib_mac_fixture.sh - SOURCE from test_mac_*.sh (not a test). Hermetic fixture for the Mac launchd job package (L2-mac-jobs): a sandbox HOME, a bare "origin" repo with branch develop, a "pusher"
# clone that makes upstream commits, stub curl/ssh/launchctl that only log, and helpers to build the broken checkout states from the 2026-10-17/18 incident (detached HEAD + stale rebase-merge,
# merge in progress, diverged develop). Nothing here touches the real HOME, real launchd, the box or the interactive checkout.
#
#   mf_init                       sets T HOME OVN_MAC_STATE ORIGIN PUSHER LIVE CALLS and PATH-independent stubs (MAC_CURL MAC_SSH MAC_LAUNCHCTL)
#   mf_up_commit <file> <content> <msg>   commit+push to origin develop via the pusher clone
#   mf_origin_head                short sha of origin develop
#   mf_live_clone                 create LIVE as the sync would (branch develop-live tracking origin/develop + marker)
#   mf_wedge_rebase <dir> <file>  leave <dir> mid-rebase (stale rebase-merge dir + detached HEAD) by rebasing a local commit onto a conflicting upstream commit
#   mf_wedge_merge <dir> <file>   leave <dir> mid-merge (MERGE_HEAD present)
#   mf_calls                      the stub call log
#   mutate <src> <dst> <old> <new>   write a copy of src with exactly one occurrence of old replaced (fails the test run if the anchor is not unique)
MF_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$MF_HERE/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
MF_REPO="$(cd "$MF_HERE/../../../.." && pwd)"          # <repo>/scripts/overnight-queue/scripts/test -> <repo>
MF_SCRIPTS="$MF_REPO/scripts"

mf_init() {
  T="$(safe_mktemp_dir macjobs)" || exit 1
  safe_set_sandbox_home "$T" || exit 1
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_NOSYSTEM=1
  export OVN_MAC_STATE="$T/state" ORIGIN="$T/origin.git" PUSHER="$T/pusher" LIVE="$T/home/LocalProjects/shared-live" CALLS="$T/calls.log"
  export MAC_CURL="$T/bin/curl" MAC_SSH="$T/bin/ssh" MAC_LAUNCHCTL="$T/bin/launchctl" NTFY_SERVER="http://relay.test:8099" OVN_SSH="u@box.test" MAC_PUSH_SLEEP_S=0
  unset OVN_MAC_JOBS MAC_LIVE_DIR MAC_LIVE_ORIGIN
  mkdir -p "$T/bin" "$OVN_MAC_STATE" "$T/home/LocalProjects"; : > "$CALLS"
  printf '%s\n' '#!/bin/sh' 'echo "curl $*" >> "$CALLS"' 'exit 0' > "$T/bin/curl"
  printf '%s\n' '#!/bin/sh' 'echo "ssh $*" >> "$CALLS"' \
    'if [ -n "$MF_SSH_CAPTURE" ]; then cat > "$T/ssh_stdin.$$" 2>/dev/null; fi' \
    'if [ -n "$MF_SSH_HOOK" ] && [ ! -e "$T/hook.done" ]; then : > "$T/hook.done"; sh -c "$MF_SSH_HOOK" >/dev/null 2>&1; fi' \
    'case "$*" in *AUTOSKIP*) printf "===AUTOSKIP===\n===PREWORKLIST===\n";; esac' 'exit "${MF_SSH_RC:-0}"' > "$T/bin/ssh"
  printf '%s\n' '#!/bin/sh' 'echo "launchctl $*" >> "$CALLS"' \
    'case "$1" in' \
    '  list) cat "$T/launchctl.table" 2>/dev/null; exit "${MF_LC_LIST_RC:-0}";;' \
    '  kickstart) exit "${MF_LC_KICK_RC:-0}";;' \
    '  bootout) exit 0;;' \
    '  bootstrap) lab="$(sed -n "s|.*<key>Label</key><string>\(.*\)</string>.*|\1|p" "$3" | head -1)"' \
    '    if [ -f "$T/launchctl.bootstrap_fail" ] && grep -qx "$lab" "$T/launchctl.bootstrap_fail"; then echo "Bootstrap failed: 5: Input/output error" >&2; exit 5; fi' \
    '    printf "%s\t0\t%s\n" "-" "$lab" >> "$T/launchctl.table"; exit 0;;' \
    'esac; exit 0' > "$T/bin/launchctl"
  chmod 755 "$T/bin/curl" "$T/bin/ssh" "$T/bin/launchctl"; export T
  git init -q --bare "$ORIGIN" && git -C "$ORIGIN" symbolic-ref HEAD refs/heads/develop
  git clone -q "$ORIGIN" "$PUSHER" 2>/dev/null; git -C "$PUSHER" checkout -q -b develop
  mkdir -p "$PUSHER/scripts"
  printf 'queue v1\nline2\nline3\n' > "$PUSHER/CLAUDE_QUEUE.md"; printf 'done v1\n' > "$PUSHER/CLAUDE_QUEUE_DONE.md"
  printf 'job v1\n' > "$PUSHER/scripts/job.sh"; printf 'readme\n' > "$PUSHER/README.md"
  git -C "$PUSHER" add -A && git -C "$PUSHER" commit -q -m seed && git -C "$PUSHER" push -q origin HEAD:refs/heads/develop
}
mf_up_commit() { # file content msg
  git -C "$PUSHER" pull -q --no-rebase origin develop 2>/dev/null
  mkdir -p "$(dirname "$PUSHER/$1")"; printf '%s\n' "$2" > "$PUSHER/$1"
  git -C "$PUSHER" add -A && git -C "$PUSHER" commit -q -m "$3" && git -C "$PUSHER" push -q origin HEAD:refs/heads/develop
}
mf_origin_head() { git --git-dir="$ORIGIN" rev-parse --short develop; }
mf_live_clone() {
  git clone -q "$ORIGIN" "$LIVE" 2>/dev/null && git -C "$LIVE" checkout -q -B develop-live origin/develop && git -C "$LIVE" branch -q --set-upstream-to=origin/develop develop-live
  : > "$LIVE/.git/ovn_live_checkout"
}
mf_wedge_rebase() { # dir file : local commit on develop-live conflicts with a later upstream commit; rebase stops mid-way
  git -C "$1" checkout -q -B develop-live origin/develop
  printf 'LOCAL change %s\n' "${MF_N:-0}" > "$1/$2"; git -C "$1" add -A; git -C "$1" commit -q -m "local conflicting"
  MF_N=$((${MF_N:-0}+1)); mf_up_commit "$2" "UPSTREAM change $MF_N" "upstream conflicting $MF_N"
  git -C "$1" fetch -q origin develop
  git -C "$1" rebase origin/develop >/dev/null 2>&1
  [ -d "$1/.git/rebase-merge" ] || [ -d "$1/.git/rebase-apply" ]
}
mf_wedge_merge() { # dir file
  git -C "$1" checkout -q -B develop-live origin/develop
  printf 'LOCAL change %s\n' "${MF_N:-0}" > "$1/$2"; git -C "$1" add -A; git -C "$1" commit -q -m "local conflicting"
  MF_N=$((${MF_N:-0}+1)); mf_up_commit "$2" "UPSTREAM change $MF_N" "upstream conflicting $MF_N"
  git -C "$1" fetch -q origin develop
  git -C "$1" merge origin/develop >/dev/null 2>&1
  [ -f "$1/.git/MERGE_HEAD" ]
}
mf_calls() { cat "$CALLS" 2>/dev/null; }
mutate() { # src dst old new
  python3 - "$1" "$2" "$3" "$4" <<'PYEOF'
import sys
s = open(sys.argv[1]).read(); old, new = sys.argv[3], sys.argv[4]
assert s.count(old) == 1, "mutation anchor %r found %d times in %s" % (old, s.count(old), sys.argv[1])
open(sys.argv[2], "w").write(s.replace(old, new))
PYEOF
}
