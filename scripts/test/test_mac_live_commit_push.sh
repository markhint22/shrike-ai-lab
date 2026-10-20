#!/usr/bin/env bash
# test_mac_live_commit_push.sh - L2-mac-jobs: scripts/mac_live_commit_push.sh (the bridge's Pass E). Reproduces the 2026-10-18 failure: a detached HEAD / stale rebase-merge made the old
# inline code push `origin HEAD` (nothing) and answer a rejection with `git pull --rebase` on a branch holding merge commits. Hermetic (lib_mac_fixture.sh). Mutants must each FAIL a scenario.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_mac_fixture.sh" || exit 1
CP="$MF_SCRIPTS/mac_live_commit_push.sh"; [ -f "$CP" ] && [ -f "$MF_SCRIPTS/mac_lib.sh" ] || { echo "  FAIL: mac_live_commit_push.sh / mac_lib.sh missing"; exit 1; }
mf_init
trap 'safe_rm_rf "$T"' EXIT
fails=0; n=0
ok() { n=$((n+1)); if [ "$2" = 0 ]; then echo "  ok   $1"; else echo "  FAIL $1"; fails=$((fails+1)); fi; }
chk() { local d="$1"; shift; "$@" >/dev/null 2>&1; ok "$d" $?; }
RC=0
cp_() { # cp_ <repo> <mode> [script]  -> sets RC, output in $T/out.txt
  local r="$1" m="$2" s="${3:-$CP}"
  OVN_MAC_JOBS="$m" MAC_LIVE_DIR="$LIVE" timeout 60 bash "$s" "$r" "chore(queue): test pass" CLAUDE_QUEUE.md CLAUDE_QUEUE_DONE.md > "$T/out.txt" 2>&1 < /dev/null; RC=$?
}
RN=0
fresh() { # fresh <live-count-suffix>: new state dir, new live clone, new interactive clone; resets origin to a known develop content
  RN=$((RN+1)); export OVN_MAC_STATE="$T/state$RN" LIVE="$T/home/LocalProjects/live$RN"; INT="$T/interactive$RN"; mkdir -p "$OVN_MAC_STATE"; : > "$CALLS"
  mf_live_clone; git clone -q "$ORIGIN" "$INT" 2>/dev/null; git -C "$INT" checkout -q -B develop origin/develop
}
ohead() { git --git-dir="$ORIGIN" rev-parse develop; }
oshow() { git --git-dir="$ORIGIN" show "develop:$1" 2>/dev/null; }
edit_q() { printf '%s\n' "$2" >> "$1/CLAUDE_QUEUE.md"; }

echo "== normal push (explicit refspec)"
fresh; edit_q "$LIVE" "tick A"; cp_ "$LIVE" enforce
chk "rc 0 and origin develop now contains the queue edit" bash -c "[ $RC -eq 0 ] && git --git-dir='$ORIGIN' show develop:CLAUDE_QUEUE.md | grep -q 'tick A'"
chk "pushed ONLY to develop: no develop-live branch was created on origin" bash -c "[ -z \"\$(git ls-remote '$ORIGIN' refs/heads/develop-live)\" ]"
chk "live checkout stays attached to develop-live and clean" bash -c "[ \"\$(git -C '$LIVE' symbolic-ref --short HEAD)\" = develop-live ] && [ -z \"\$(git -C '$LIVE' status --porcelain --untracked-files=no)\" ]"
cp_ "$LIVE" enforce
chk "no change -> rc 0, says so, creates no commit" bash -c "[ $RC -eq 0 ] && grep -q 'no changes' '$T/out.txt'"

echo "== only the named paths are committed"
fresh; edit_q "$LIVE" "tick B"; printf 'stray edit\n' >> "$LIVE/README.md"; cp_ "$LIVE" enforce
chk "README (not named) was NOT swept into the commit; still dirty locally" bash -c "[ $RC -eq 0 ] && ! git --git-dir='$ORIGIN' show develop:README.md | grep -q 'stray edit' && grep -q 'stray edit' '$LIVE/README.md'"

echo "== rejected push -> MERGE (never rebase), including a local merge commit"
fresh; edit_q "$LIVE" "tick C1"; git -C "$LIVE" commit -q -am "local C1 unpushed"
mf_up_commit README.md "readme upstream 1" "up1"; git -C "$LIVE" fetch -q origin develop; git -C "$LIVE" merge -q --no-edit origin/develop
lm="$(git -C "$LIVE" rev-parse HEAD)"; git -C "$LIVE" rev-parse -q --verify "HEAD^2" >/dev/null || { echo "  FAIL fixture: no local merge commit"; exit 1; }
mf_up_commit README.md "readme upstream 2" "up2"; edit_q "$LIVE" "tick C2"; cp_ "$LIVE" enforce
chk "rc 0; origin has the upstream commit AND both local edits" bash -c "[ $RC -eq 0 ] && git --git-dir='$ORIGIN' show develop:CLAUDE_QUEUE.md | grep -q 'tick C2' && git --git-dir='$ORIGIN' show develop:CLAUDE_QUEUE.md | grep -q 'tick C1' && git --git-dir='$ORIGIN' show develop:README.md | grep -q 'upstream 2'"
chk "the unpushed LOCAL MERGE COMMIT is preserved (ancestor of origin develop): history was merged, not rebased" git --git-dir="$ORIGIN" merge-base --is-ancestor "$lm" develop
chk "no rebase-merge/rebase-apply/MERGE_HEAD left behind" bash -c "[ ! -d '$LIVE/.git/rebase-merge' ] && [ ! -d '$LIVE/.git/rebase-apply' ] && [ ! -f '$LIVE/.git/MERGE_HEAD' ]"

echo "== merge conflict"
fresh; mf_up_commit CLAUDE_QUEUE.md "queue UPSTREAM rewrite $RN" "up conflicting $RN"; printf 'queue LOCAL rewrite\n' > "$LIVE/CLAUDE_QUEUE.md"   # live is one commit behind and edits the same file
cp_ "$LIVE" enforce
chk "conflict: rc 5, merge aborted (no MERGE_HEAD), live reset to origin, local commit kept on rescue/*" bash -c "[ $RC -eq 5 ] && [ ! -f '$LIVE/.git/MERGE_HEAD' ] && [ \"\$(git -C '$LIVE' rev-parse HEAD)\" = \"\$(git --git-dir='$ORIGIN' rev-parse develop)\" ] && git -C '$LIVE' branch --list 'rescue/*' | grep -q rescue"
fresh; mf_up_commit CLAUDE_QUEUE.md "queue UPSTREAM rewrite $RN" "up conflicting $RN"; printf 'queue LOCAL rewrite\n' > "$LIVE/CLAUDE_QUEUE.md"
cp_ "$LIVE" shadow
chk "conflict in SHADOW: rc 5, merge aborted, no reset (local commit stays, HEAD attached)" bash -c "[ $RC -eq 5 ] && [ ! -f '$LIVE/.git/MERGE_HEAD' ] && [ \"\$(git -C '$LIVE' symbolic-ref --short HEAD)\" = develop-live ] && [ \"\$(git -C '$LIVE' rev-parse HEAD)\" != \"\$(git --git-dir='$ORIGIN' rev-parse develop)\" ]"

echo "== INCIDENT: live checkout detached in a stale rebase"
fresh; mf_wedge_rebase "$LIVE" scripts/job.sh || { echo "  FAIL fixture: wedge"; exit 1; }; edit_q "$LIVE" "tick W"; : > "$CALLS"
cp_ "$LIVE" shadow
chk "shadow: REFUSED rc 4, the wedge is left exactly as found, emergency alert sent" bash -c "[ $RC -eq 4 ] && [ -d '$LIVE/.git/rebase-merge' ] && grep -q 'X-Ovn-Level: emergency' '$CALLS'"
cp_ "$LIVE" enforce
chk "enforce: repaired (attached to develop-live, rebase dir gone) and rc 0" bash -c "[ $RC -eq 0 ] && [ ! -d '$LIVE/.git/rebase-merge' ] && [ \"\$(git -C '$LIVE' symbolic-ref --short HEAD)\" = develop-live ] && grep -q repaired '$T/out.txt'"
edit_q "$LIVE" "tick W2"; cp_ "$LIVE" enforce
chk "after the repair the next pass pushes normally" bash -c "[ $RC -eq 0 ] && git --git-dir='$ORIGIN' show develop:CLAUDE_QUEUE.md | grep -q 'tick W2'"
fresh; git -C "$LIVE" checkout -q --detach; edit_q "$LIVE" "tick D"; cp_ "$LIVE" enforce
chk "detached HEAD alone (the exact old-bridge failure) is repaired then pushes on the next pass, never 'push origin HEAD'" bash -c "[ \"\$(git -C '$LIVE' symbolic-ref --short HEAD)\" = develop-live ]"

echo "== the interactive (non-live) checkout is NEVER touched"
fresh; mf_wedge_rebase "$INT" scripts/job.sh || { echo "  FAIL fixture: wedge INT"; exit 1; }; edit_q "$INT" "tick I"; ih="$(git -C "$INT" rev-parse HEAD)"; od="$(ohead)"
cp_ "$INT" enforce
chk "mid-rebase interactive checkout, mode=enforce: REFUSED rc 4, rebase dir + HEAD untouched, origin unchanged" bash -c "[ $RC -eq 4 ] && [ -d '$INT/.git/rebase-merge' ] && [ \"\$(git -C '$INT' rev-parse HEAD)\" = '$ih' ] && [ '$(ohead)' = '$od' ]"
fresh; git -C "$INT" checkout -q -b feature/someone-elses-work; printf 'wip\n' > "$INT/wip.txt"; git -C "$INT" add -A; git -C "$INT" commit -q -m wip; edit_q "$INT" "tick F"; od="$(ohead)"
cp_ "$INT" enforce
chk "interactive checkout on a feature branch: REFUSED (would push unrelated commits to develop), origin unchanged" bash -c "[ $RC -eq 4 ] && [ '$(ohead)' = '$od' ]"
fresh; edit_q "$INT" "tick L"; cp_ "$INT" enforce
chk "interactive checkout on develop (legacy bridge location) still works normally" bash -c "[ $RC -eq 0 ] && git --git-dir='$ORIGIN' show develop:CLAUDE_QUEUE.md | grep -q 'tick L'"

echo "== bounded retries"
fresh; edit_q "$LIVE" "tick R"
printf '#!/bin/sh\necho "remote: rejected by test hook" >&2\nexit 1\n' > "$ORIGIN/hooks/pre-receive"; chmod 755 "$ORIGIN/hooks/pre-receive"; : > "$CALLS"
cp_ "$LIVE" enforce
chk "push always rejected: rc 3 after exactly 3 attempts (bounded), emergency alert" bash -c "[ $RC -eq 3 ] && [ \$(grep -c 'rejected:' '$T/out.txt') -eq 3 ] && grep -q 'X-Ovn-Level: emergency' '$CALLS'"
chk "no half-done merge/rebase after exhausting retries" bash -c "[ ! -f '$LIVE/.git/MERGE_HEAD' ] && [ ! -d '$LIVE/.git/rebase-merge' ]"
rm -f "$ORIGIN/hooks/pre-receive"

echo "== mutants"
MUT="$T/mut"; mkdir -p "$MUT"; cp "$MF_SCRIPTS"/mac_*.sh "$MUT/"
mutant() { mutate "$CP" "$MUT/mac_live_commit_push.sh" "$2" "$3" || { ok "mutant $1: anchor exists" 1; return 1; }; }
# MA: push by current branch name instead of the explicit refspec
if mutant refspec 'push -q "$REM" "HEAD:refs/heads/$PB"' 'push -q "$REM" "$(git -C "$R" symbolic-ref --short HEAD)"'; then
  fresh; edit_q "$LIVE" "tick MA"; cp_ "$LIVE" enforce "$MUT/mac_live_commit_push.sh"
  chk "MA (push by branch name) is caught: origin develop never received the edit" bash -c "! git --git-dir='$ORIGIN' show develop:CLAUDE_QUEUE.md | grep -q 'tick MA'"
fi
# MB: rebase instead of merge on rejection
if mutant rebase 'git_id merge -q --no-edit "$REM/$PB"' 'git_id rebase -q "$REM/$PB"'; then
  fresh; edit_q "$LIVE" "tick MB1"; git -C "$LIVE" commit -q -am "local MB1"; mf_up_commit README.md "readme MB 1" "mb up1"; git -C "$LIVE" fetch -q origin develop; git -C "$LIVE" merge -q --no-edit origin/develop
  lm="$(git -C "$LIVE" rev-parse HEAD)"; mf_up_commit README.md "readme MB 2" "mb up2"; edit_q "$LIVE" "tick MB2"; cp_ "$LIVE" enforce "$MUT/mac_live_commit_push.sh"
  chk "MB (rebase on rejection) is caught: the local merge commit is no longer an ancestor of origin develop" bash -c "! git --git-dir='$ORIGIN' merge-base --is-ancestor '$lm' develop"
fi
# MC: any checkout may be repaired (the interactive one too)
if mutant nonlive-repair 'if [ "$is_live" = 1 ] && [ "$MODE" = enforce ]; then
    mac_git_clear_stale_index_lock "$R"' 'if [ "$MODE" = enforce ]; then
    mac_git_clear_stale_index_lock "$R"'; then
  fresh; mf_wedge_rebase "$INT" scripts/job.sh; cp_ "$INT" enforce "$MUT/mac_live_commit_push.sh"
  chk "MC (repair outside the live checkout) is caught: the interactive rebase was destroyed" bash -c "[ ! -d '$INT/.git/rebase-merge' ]"
fi
# MD: shadow repairs
if mutant shadow-repair 'if [ "$is_live" = 1 ] && [ "$MODE" = enforce ]; then
    mac_git_clear_stale_index_lock "$R"' 'if [ "$is_live" = 1 ]; then
    mac_git_clear_stale_index_lock "$R"'; then
  fresh; mf_wedge_rebase "$LIVE" scripts/job.sh; cp_ "$LIVE" shadow "$MUT/mac_live_commit_push.sh"
  chk "MD (shadow repairs) is caught: the wedge was modified in shadow mode" bash -c "[ ! -d '$LIVE/.git/rebase-merge' ]"
fi
# ME: unbounded retry loop
if mutate "$CP" "$MUT/step1.sh" 'while [ "$n" -le "$TRIES" ]; do' 'while true; do' && mutate "$MUT/step1.sh" "$MUT/mac_live_commit_push.sh" '  [ "$n" -ge "$TRIES" ] && break' '  :'; then
  fresh; edit_q "$LIVE" "tick ME"; printf '#!/bin/sh\nexit 1\n' > "$ORIGIN/hooks/pre-receive"; chmod 755 "$ORIGIN/hooks/pre-receive"
  OVN_MAC_JOBS=enforce MAC_LIVE_DIR="$LIVE" MAC_PUSH_TRIES=2 timeout 8 bash "$MUT/mac_live_commit_push.sh" "$LIVE" msg CLAUDE_QUEUE.md > "$T/out.txt" 2>&1 < /dev/null; mrc=$?
  chk "ME (no retry bound) is caught: the pass never terminates by itself (timeout rc 124)" bash -c "[ $mrc -eq 124 ]"
  rm -f "$ORIGIN/hooks/pre-receive"
fi
# MF: commit everything (-a) instead of the named paths
if mutant commit-all 'git_id commit -q -m "$MSG" -- "$@"' 'git_id commit -q -a -m "$MSG"'; then
  fresh; edit_q "$LIVE" "tick MF"; printf 'stray MF\n' >> "$LIVE/README.md"; cp_ "$LIVE" enforce "$MUT/mac_live_commit_push.sh"
  chk "MF (commit -a) is caught: the stray README edit reached origin" bash -c "git --git-dir='$ORIGIN' show develop:README.md | grep -q 'stray MF'"
fi
# MG: a conflicted merge is left in place
if mutant no-merge-abort '    git -C "$R" merge --abort >/dev/null 2>&1; mac_git_abort_all "$R"' '    :'; then
  fresh; mf_up_commit CLAUDE_QUEUE.md "queue UPSTREAM MG" "mg up"; printf 'queue LOCAL MG\n' > "$LIVE/CLAUDE_QUEUE.md"
  cp_ "$LIVE" shadow "$MUT/mac_live_commit_push.sh"
  chk "MG (conflict left unaborted) is caught: MERGE_HEAD survives" bash -c "[ -f '$LIVE/.git/MERGE_HEAD' ]"
fi

echo; echo "mac_live_commit_push: $((n-fails))/$n passed"; [ "$fails" = 0 ]
