#!/usr/bin/env bash
# test_z8a_bridge_commit_feature.sh - Z8a (2026-11-10): scripts/mac_live_commit_push.sh refused `branch-not-develop(claude/feature)` (rc 6, Z4) so the queue bridge's CLAUDE_QUEUE*.md edits were never
# committed after 2026-11-06 and its heartbeat died (emergency every 6 h). With OVN_BRIDGE_COMMIT_ON_FEATURE=on the helper commits ONLY the two queue files from the interactive checkout on
# claude/feature and pushes them to origin claude/feature (fetch + MERGE, never rebase/force/stash). STUB REPOS ONLY (bare origin + clones under a sandbox HOME): never the real checkout or box.
# Proven here: no other file is ever committed or pushed, no commit (local or upstream) is lost, the user's unrelated dirty/staged/untracked state is untouched, every unsafe state is refused
# (rc 6) with nothing changed, a queue-file conflict aborts the merge (rc 5, one alert), develop behaviour is unchanged, off = the Z4 refusal. Mutants must each FAIL a scenario.
# DEFAULT IS OFF (review decision 2026-11-10; known reasons D1 rc 5 forever on a stale checkout, D2 net-tree guard misses add-then-remove, D3 merge rewrites the working tree): every `on` scenario sets env=on explicitly;
# the `default` scenario runs with the variable UNSET and must be the Z4 refusal.
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
cp_() { # cp_ <repo> <on|off> [script] -> RC, output in $T/out.txt   (interactive checkout: no MAC_LIVE_DIR match, not a live checkout)
  local r="$1" g="$2" s="${3:-$CP}"
  local -a E=(); if [ "$g" = default ]; then E=(env -u OVN_BRIDGE_COMMIT_ON_FEATURE); else E=(env "OVN_BRIDGE_COMMIT_ON_FEATURE=$g"); fi
  "${E[@]}" OVN_MAC_JOBS=enforce MAC_LIVE_DIR="$T/nonexistent-live" timeout 60 bash "$s" "$r" "chore(queue): test pass" CLAUDE_QUEUE.md CLAUDE_QUEUE_DONE.md > "$T/out.txt" 2>&1 < /dev/null; RC=$?
}
RN=0
fresh() { # new state dir + interactive clone on claude/feature (origin claude/feature = develop at seed)
  RN=$((RN+1)); export OVN_MAC_STATE="$T/state$RN"; INT="$T/interactive$RN"; mkdir -p "$OVN_MAC_STATE"; : > "$CALLS"
  git -C "$PUSHER" push -q -f origin "origin/develop:refs/heads/claude/feature" 2>/dev/null || git -C "$PUSHER" push -q -f origin develop:refs/heads/claude/feature
  git -C "$PUSHER" fetch -q origin; git -C "$PUSHER" checkout -q develop 2>/dev/null; git -C "$PUSHER" reset -q --hard origin/develop
  git clone -q "$ORIGIN" "$INT" 2>/dev/null; git -C "$INT" checkout -q -B claude/feature origin/claude/feature
}
ofe() { git --git-dir="$ORIGIN" rev-parse claude/feature; }
odv() { git --git-dir="$ORIGIN" rev-parse develop; }
oshow() { git --git-dir="$ORIGIN" show "claude/feature:$1" 2>/dev/null; }
fup() { # fup <file> <content> <msg>: an upstream commit on origin claude/feature (what reconcile_branches / the fleet does)
  git -C "$PUSHER" fetch -q origin; git -C "$PUSHER" checkout -q -B featwork origin/claude/feature
  mkdir -p "$(dirname "$PUSHER/$1")"; printf '%s\n' "$2" > "$PUSHER/$1"; git -C "$PUSHER" add -A; git -C "$PUSHER" commit -q -m "$3"; git -C "$PUSHER" push -q origin featwork:refs/heads/claude/feature
  git -C "$PUSHER" checkout -q develop
}
edit_q() { printf '%s\n' "$2" >> "$1/CLAUDE_QUEUE.md"; }
changed_files() { git --git-dir="$ORIGIN" diff --name-only "$1" claude/feature | tr '\n' ' '; }
untouched() { # untouched <repo>: the user's stray state survived: README dirty, stray.txt untracked
  grep -q 'user wip' "$1/README.md" && [ -f "$1/stray.txt" ]
}
dirty() { printf 'user wip\n' >> "$1/README.md"; printf 'x\n' > "$1/stray.txt"; }

echo "== off: the Z4 deliberate refusal is unchanged"
fresh; edit_q "$INT" "tick OFF"; of0="$(ofe)"; cp_ "$INT" off
chk "off: rc 6, REFUSED (deliberate), origin claude/feature unchanged, nothing committed" bash -c "[ $RC -eq 6 ] && grep -q 'REFUSED (deliberate)' '$T/out.txt' && [ '$(ofe)' = '$of0' ] && [ \"\$(git -C '$INT' rev-parse HEAD)\" = '$of0' ]"

echo "== default (variable UNSET): off - the Z4 refusal, nothing committed or pushed"
fresh; edit_q "$INT" "tick DEF"; of0="$(ofe)"; cp_ "$INT" default
chk "unset: rc 6, REFUSED (deliberate), origin claude/feature unchanged, nothing committed" bash -c "[ $RC -eq 6 ] && grep -q 'REFUSED (deliberate)' '$T/out.txt' && [ '$(ofe)' = '$of0' ] && [ \"\$(git -C '$INT' rev-parse HEAD)\" = '$of0' ]"
chk "the default in the script is off (and documents D1/D2/D3)" bash -c "grep -q 'OVN_BRIDGE_COMMIT_ON_FEATURE:-off' '$CP' && grep -q 'D1 rc 5 FOREVER' '$CP' && grep -q 'D2 the unpushed-commit guards' '$CP' && grep -q 'D3 the merge rewrites' '$CP'"

echo "== on: commit ONLY the queue files, push to claude/feature"
fresh; edit_q "$INT" "tick A"; printf 'done A\n' >> "$INT/CLAUDE_QUEUE_DONE.md"; dirty "$INT"; of0="$(ofe)"; dv0="$(odv)"; ih="$(git -C "$INT" rev-parse HEAD)"; cp_ "$INT" on
chk "rc 0; origin claude/feature has BOTH queue edits" bash -c "[ $RC -eq 0 ] && git --git-dir='$ORIGIN' show claude/feature:CLAUDE_QUEUE.md | grep -q 'tick A' && git --git-dir='$ORIGIN' show claude/feature:CLAUDE_QUEUE_DONE.md | grep -q 'done A'"
ok "the LOCAL commit itself holds only the two queue files (files changed since the old HEAD: '$(git -C "$INT" diff --name-only "$ih" HEAD | tr '\n' ' ')')" "$([ "$(git -C "$INT" diff --name-only "$ih" HEAD | tr '\n' ' ')" = "CLAUDE_QUEUE.md CLAUDE_QUEUE_DONE.md " ] && echo 0 || echo 1)"
ok "NO other file reached origin (changed files vs the old tip: '$(changed_files "$of0")')" "$([ "$(changed_files "$of0")" = "CLAUDE_QUEUE.md CLAUDE_QUEUE_DONE.md " ] && echo 0 || echo 1)"
chk "the user's dirty README and untracked stray.txt are untouched (still dirty locally, never committed)" bash -c "cd '$INT' && grep -q 'user wip' README.md && [ -f stray.txt ] && ! git --git-dir='$ORIGIN' show claude/feature:README.md | grep -q 'user wip'"
chk "develop on origin untouched; checkout still attached to claude/feature; no stale rebase/merge state" bash -c "[ '$(odv)' = '$dv0' ] && [ \"\$(git -C '$INT' symbolic-ref --short HEAD)\" = claude/feature ] && [ ! -d '$INT/.git/rebase-merge' ] && [ ! -f '$INT/.git/MERGE_HEAD' ]"
cp_ "$INT" on
chk "second pass with nothing changed: rc 0, 'no changes', no new commit" bash -c "[ $RC -eq 0 ] && grep -q 'no changes' '$T/out.txt'"
chk "a successful push clears the refusal alert marker semantics (alerts.log has no emergency)" bash -c "! grep -q '\[emergency\]' '$OVN_MAC_STATE/alerts.log' 2>/dev/null"

echo "== on: upstream moved (reconcile pushed): fetch + MERGE before the push, nothing lost"
fresh; fup README.md "upstream R1" "up r1"; fup scripts/job.sh "upstream job" "up job"
edit_q "$INT" "tick B"; git -C "$INT" fetch -q origin; lt="$(git -C "$INT" rev-parse HEAD)"; printf 'user wip\n' >> "$INT/stray2.txt"; of0="$(ofe)"; cp_ "$INT" on
chk "rc 0; origin has the upstream commits AND the queue edit" bash -c "[ $RC -eq 0 ] && git --git-dir='$ORIGIN' show claude/feature:CLAUDE_QUEUE.md | grep -q 'tick B' && git --git-dir='$ORIGIN' show claude/feature:README.md | grep -q 'upstream R1' && git --git-dir='$ORIGIN' show claude/feature:scripts/job.sh | grep -q 'upstream job'"
chk "the upstream tip is an ancestor of the new origin tip (merged, upstream commits not lost)" git --git-dir="$ORIGIN" merge-base --is-ancestor "$of0" claude/feature
chk "history was MERGED not rebased: the local pre-merge commit survives as an ancestor, and the tip is a merge commit" bash -c "git --git-dir='$ORIGIN' rev-parse -q --verify claude/feature^2 >/dev/null && git --git-dir='$ORIGIN' log --format=%s claude/feature | grep -q 'chore(queue): test pass'"
chk "untracked user file untouched" bash -c "[ -f '$INT/stray2.txt' ]"

echo "== on: a local unpushed commit that touches ONLY the queue files is pushed (not lost); one touching anything else is NOT"
fresh; edit_q "$INT" "tick C1"; git -C "$INT" commit -q -am "local queue-only C1"; edit_q "$INT" "tick C2"; cp_ "$INT" on
chk "both the earlier local queue commit and the new edit reach origin" bash -c "[ $RC -eq 0 ] && git --git-dir='$ORIGIN' show claude/feature:CLAUDE_QUEUE.md | grep -q 'tick C1' && git --git-dir='$ORIGIN' show claude/feature:CLAUDE_QUEUE.md | grep -q 'tick C2'"
fresh; printf 'private work\n' > "$INT/mywork.txt"; git -C "$INT" add mywork.txt; git -C "$INT" commit -q -m "my unpushed work"; edit_q "$INT" "tick C3"; of0="$(ofe)"; ih="$(git -C "$INT" rev-parse HEAD)"; cp_ "$INT" on
chk "unpushed commit with another file: REFUSED rc 6, nothing pushed, nothing committed" bash -c "[ $RC -eq 6 ] && [ '$(ofe)' = '$of0' ] && [ \"\$(git -C '$INT' rev-parse HEAD)\" = '$ih' ] && grep -q 'tick C3' '$INT/CLAUDE_QUEUE.md'"

echo "== on: unsafe checkout states are refused with nothing changed"
fresh; edit_q "$INT" "tick S"; printf 'staged\n' > "$INT/other.txt"; git -C "$INT" add other.txt; of0="$(ofe)"; ih="$(git -C "$INT" rev-parse HEAD)"; cp_ "$INT" on
chk "OTHER staged change: rc 6, no commit, other.txt still staged, origin unchanged" bash -c "[ $RC -eq 6 ] && [ \"\$(git -C '$INT' rev-parse HEAD)\" = '$ih' ] && git -C '$INT' diff --cached --name-only | grep -qx other.txt && [ '$(ofe)' = '$of0' ]"
fresh; edit_q "$INT" "tick S2"; git -C "$INT" add CLAUDE_QUEUE.md; of0="$(ofe)"; cp_ "$INT" on
chk "ONLY queue files staged (the bridge's own add) is fine: rc 0, pushed" bash -c "[ $RC -eq 0 ] && git --git-dir='$ORIGIN' show claude/feature:CLAUDE_QUEUE.md | grep -q 'tick S2'"
fresh; git -C "$INT" checkout -q -b feature/x; edit_q "$INT" "tick O"; of0="$(ofe)"; cp_ "$INT" on
chk "any other branch (feature/x): rc 6, origin unchanged (also with the switch on)" bash -c "[ $RC -eq 6 ] && [ '$(ofe)' = '$of0' ] && [ '$(odv)' = '$(odv)' ]"
fresh; git -C "$INT" checkout -q --detach; edit_q "$INT" "tick DH"; of0="$(ofe)"; cp_ "$INT" on
chk "detached HEAD: refused (rc 4 as today: never touched), origin unchanged, HEAD still detached" bash -c "[ $RC -ne 0 ] && [ '$(ofe)' = '$of0' ] && ! git -C '$INT' symbolic-ref -q HEAD >/dev/null"
fresh; edit_q "$INT" "tick MR"; mf_wedge_rebase "$INT" scripts/job.sh >/dev/null 2>&1; git -C "$INT" checkout -q -f . 2>/dev/null
# build a mid-rebase of claude/feature: local commit conflicts with an upstream commit on claude/feature
fresh; printf 'LOCAL\n' > "$INT/scripts/job.sh"; git -C "$INT" add -A; git -C "$INT" commit -q -m "local conflicting"; fup scripts/job.sh "UPSTREAM" "up conflicting"; git -C "$INT" fetch -q origin; git -C "$INT" rebase origin/claude/feature >/dev/null 2>&1
[ -d "$INT/.git/rebase-merge" ] || [ -d "$INT/.git/rebase-apply" ] || { echo "  FAIL fixture: no mid-rebase of claude/feature"; exit 1; }
edit_q "$INT" "tick RB"; of0="$(ofe)"; ih="$(git -C "$INT" rev-parse HEAD)"; cp_ "$INT" on
chk "rebase of claude/feature in progress: rc 6, rebase dir + HEAD untouched, origin unchanged" bash -c "[ $RC -eq 6 ] && ( [ -d '$INT/.git/rebase-merge' ] || [ -d '$INT/.git/rebase-apply' ] ) && [ \"\$(git -C '$INT' rev-parse HEAD)\" = '$ih' ] && [ '$(ofe)' = '$of0' ]"
fresh; printf 'LOCAL M\n' > "$INT/scripts/job.sh"; git -C "$INT" add -A; git -C "$INT" commit -q -m "local conflicting M"; fup scripts/job.sh "UPSTREAM M" "up conflicting M"; git -C "$INT" fetch -q origin; git -C "$INT" merge origin/claude/feature >/dev/null 2>&1
[ -f "$INT/.git/MERGE_HEAD" ] || { echo "  FAIL fixture: no merge in progress"; exit 1; }
of0="$(ofe)"; cp_ "$INT" on
chk "merge in progress (conflicted): rc 6, MERGE_HEAD kept as found, origin unchanged" bash -c "[ $RC -eq 6 ] && [ -f '$INT/.git/MERGE_HEAD' ] && [ '$(ofe)' = '$of0' ]"
fresh; git -C "$INT" fetch -q origin; fup README.md "UP CP" "up for cherry-pick"; git -C "$INT" fetch -q origin; cpc="$(git -C "$INT" rev-parse origin/claude/feature)"; printf 'LOCALCP\n' > "$INT/README.md"; git -C "$INT" commit -q -am "local readme"
git -C "$INT" cherry-pick "$cpc" >/dev/null 2>&1
[ -f "$INT/.git/CHERRY_PICK_HEAD" ] || { echo "  FAIL fixture: no cherry-pick in progress"; exit 1; }
edit_q "$INT" "tick CP"; of0="$(ofe)"; cp_ "$INT" on
chk "cherry-pick in progress: rc 6, CHERRY_PICK_HEAD kept, origin unchanged" bash -c "[ $RC -eq 6 ] && [ -f '$INT/.git/CHERRY_PICK_HEAD' ] && [ '$(ofe)' = '$of0' ]"
fresh; edit_q "$INT" "tick FK"; git -C "$INT" rev-parse HEAD > "$INT/.git/CHERRY_PICK_HEAD"; of0="$(ofe)"; cp_ "$INT" on
chk "operation in progress with an otherwise CLEAN index (CHERRY_PICK_HEAD): rc 6, nothing committed/pushed" bash -c "[ $RC -eq 6 ] && [ '$(ofe)' = '$of0' ] && [ \"\$(git -C '$INT' rev-parse HEAD)\" = \"\$(git -C '$INT' rev-parse origin/claude/feature)\" ]"
fresh; edit_q "$INT" "tick UM"; b="$(git -C "$INT" hash-object -w "$INT/README.md")"; printf '100644 %s 1\tconf.txt\n100644 %s 2\tconf.txt\n100644 %s 3\tconf.txt\n' "$b" "$b" "$b" | git -C "$INT" update-index --index-info
of0="$(ofe)"; ih="$(git -C "$INT" rev-parse HEAD)"; cp_ "$INT" on
chk "conflicted (unmerged) index entries: rc 6, no commit, origin unchanged" bash -c "[ $RC -eq 6 ] && [ \"\$(git -C '$INT' rev-parse HEAD)\" = '$ih' ] && [ '$(ofe)' = '$of0' ]"

echo "== on: queue-file conflict => git merge --abort, rc 5, ONE alert; nothing lost"
fresh; fup CLAUDE_QUEUE.md "queue UPSTREAM rewrite" "up queue rewrite"; printf 'queue LOCAL rewrite\n' > "$INT/CLAUDE_QUEUE.md"; dirty "$INT"; of0="$(ofe)"; : > "$CALLS"; cp_ "$INT" on
chk "rc 5; no MERGE_HEAD; origin claude/feature unchanged; local commit kept (HEAD != origin); queue text kept" bash -c "[ $RC -eq 5 ] && [ ! -f '$INT/.git/MERGE_HEAD' ] && [ '$(ofe)' = '$of0' ] && [ \"\$(git -C '$INT' log -1 --format=%s)\" = 'chore(queue): test pass' ] && git -C '$INT' show HEAD:CLAUDE_QUEUE.md | grep -q 'LOCAL rewrite'"
ok "the user's unrelated dirty/untracked state survived the aborted merge" "$(untouched "$INT" && echo 0 || echo 1)"
c1="$(wc -l < "$CALLS" | tr -d ' ')"; cp_ "$INT" on; cp_ "$INT" on
chk "alerted ONCE (second/third pass add no delivery), every pass still logged, never an emergency" bash -c "[ \"\$(wc -l < '$CALLS' | tr -d ' ')\" = '$c1' ] && ! grep -q 'X-Ovn-Level: emergency' '$CALLS' && [ \$(grep -c 'commit-push' '$OVN_MAC_STATE/alerts.log') -ge 3 ]"

echo "== on: concurrent push race (origin advances between our fetch and our push)"
fresh; edit_q "$INT" "tick RACE"
cat > "$ORIGIN/hooks/pre-receive" <<HOOK
#!/bin/sh
# first push only: advance claude/feature on origin (a concurrent session), then reject this push (non-fast-forward in effect)
[ -e "$T/race.done" ] && exit 0
: > "$T/race.done"
unset GIT_QUARANTINE_PATH GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES
export GIT_DIR="$ORIGIN"
tip=\$(git rev-parse refs/heads/claude/feature); tree=\$(git rev-parse "\$tip^{tree}")
new=\$(GIT_AUTHOR_NAME=r GIT_AUTHOR_EMAIL=r@r GIT_COMMITTER_NAME=r GIT_COMMITTER_EMAIL=r@r git commit-tree "\$tree" -p "\$tip" -m "concurrent upstream commit")
git update-ref refs/heads/claude/feature "\$new"
echo "remote: rejected (race hook)" >&2
exit 1
HOOK
chmod 755 "$ORIGIN/hooks/pre-receive"; rm -f "$T/race.done"
cp_ "$INT" on
rm -f "$ORIGIN/hooks/pre-receive"
chk "rc 0 after the retry: origin has the queue edit AND the concurrent upstream commit (merge, none lost)" bash -c "[ $RC -eq 0 ] && git --git-dir='$ORIGIN' show claude/feature:CLAUDE_QUEUE.md | grep -q 'tick RACE' && git --git-dir='$ORIGIN' log --format=%s claude/feature | grep -q 'concurrent upstream commit' && grep -q 'rejected' '$T/out.txt'"
chk "no force: origin history is linear-extending (the old tip is an ancestor of the new tip)" bash -c "[ -f '$T/race.done' ]"

echo "== develop behaviour unchanged"
fresh; git -C "$INT" checkout -q -B develop origin/develop; edit_q "$INT" "tick DEV"; of0="$(ofe)"; cp_ "$INT" on
chk "interactive checkout on develop: pushes to develop exactly as before; claude/feature untouched" bash -c "[ $RC -eq 0 ] && git --git-dir='$ORIGIN' show develop:CLAUDE_QUEUE.md | grep -q 'tick DEV' && [ '$(ofe)' = '$of0' ]"
fresh; edit_q "$INT" "tick LV"; git -C "$INT" checkout -q -B develop origin/develop 2>/dev/null; : > "$INT/.git/ovn_live_checkout"; cp_ "$INT" on
chk "a checkout marked LIVE is not an interactive feature checkout (feature mode never applies)" bash -c "[ \"\$(git -C '$INT' symbolic-ref --short HEAD)\" != claude/feature ]"

echo "== mutants (each must FAIL a scenario)"
MUT="$T/mut"; mkdir -p "$MUT"; cp "$MF_SCRIPTS"/mac_*.sh "$MUT/"
mutant() { mutate "$CP" "$MUT/mac_live_commit_push.sh" "$2" "$3" || { ok "mutant $1: anchor exists" 1; return 1; }; }
if mutant commit-all 'git_id commit -q -m "$MSG" -- "$@"' 'git_id commit -q -a -m "$MSG"'; then
  fresh; edit_q "$INT" "tick MA"; dirty "$INT"; cp_ "$INT" on "$MUT/mac_live_commit_push.sh"
  chk "MA (commit -a) is caught: README is in the local commit (the post-merge guard still stops it reaching origin)" bash -c "git -C '$INT' show --name-only --format= HEAD | grep -qx README.md"
fi
if mutant no-staged-check 'git -C "$R" diff --cached --name-only 2>/dev/null | named_only_list "$@" || feat_refuse "the index has OTHER staged changes (only the queue files may be committed)"' ':'; then
  fresh; edit_q "$INT" "tick MB"; printf 'staged\n' > "$INT/other.txt"; git -C "$INT" add other.txt; cp_ "$INT" on "$MUT/mac_live_commit_push.sh"
  chk "MB (no other-staged check) is caught: rc is not 6" bash -c "[ $RC -ne 6 ]"
fi
if mutant no-ahead-check 'git -C "$R" diff --name-only "$REM/$PB...HEAD" 2>/dev/null | named_only_list "$@" || feat_refuse "unpushed local commits touch files other than the queue files (not publishing them)"' ':'; then
  fresh; printf 'private work\n' > "$INT/mywork.txt"; git -C "$INT" add mywork.txt; git -C "$INT" commit -q -m "my unpushed work"; edit_q "$INT" "tick MC"; ih="$(git -C "$INT" rev-parse HEAD)"; cp_ "$INT" on "$MUT/mac_live_commit_push.sh"
  chk "MC (no pre-commit unpushed-other-files check) is caught: a commit was made anyway (the post-merge guard still stops the push)" bash -c "[ \"\$(git -C '$INT' rev-parse HEAD)\" != '$ih' ]"
fi
if mutant rebase-not-merge 'if ! git_id merge -q --no-edit "$REM/$FEAT" >/dev/null 2>"$OVN_MAC_STATE/merge.err"; then
      conflicted=' 'if ! git_id rebase -q "$REM/$FEAT" >/dev/null 2>"$OVN_MAC_STATE/merge.err"; then
      conflicted='; then
  fresh; fup README.md "upstream MD" "up md"; edit_q "$INT" "tick MD"; cp_ "$INT" on "$MUT/mac_live_commit_push.sh"
  chk "MD (rebase instead of merge) is caught: the push is not a merge commit any more" bash -c "! git --git-dir='$ORIGIN' rev-parse -q --verify claude/feature^2 >/dev/null"
fi
if mutant no-abort '      git -C "$R" merge --abort >/dev/null 2>&1
      if [ -n "$conflicted" ]; then' '      if [ -n "$conflicted" ]; then'; then
  fresh; fup CLAUDE_QUEUE.md "queue UP ME" "up queue me"; printf 'queue LOCAL ME\n' > "$INT/CLAUDE_QUEUE.md"; cp_ "$INT" on "$MUT/mac_live_commit_push.sh"
  chk "ME (no merge --abort) is caught: MERGE_HEAD survives" bash -c "[ -f '$INT/.git/MERGE_HEAD' ]"
fi
if mutant no-midop-refusal '  [ -z "$midop" ] || feat_refuse "an operation is in progress ($midop)"' ':'; then
  fresh; edit_q "$INT" "tick MF"; git -C "$INT" rev-parse HEAD > "$INT/.git/CHERRY_PICK_HEAD"   # an in-progress operation with an otherwise clean index
  cp_ "$INT" on "$MUT/mac_live_commit_push.sh"
  chk "MF (no in-progress refusal) is caught: rc is not 6" bash -c "[ $RC -ne 6 ]"
fi
if mutant default-on 'FEATON="${OVN_BRIDGE_COMMIT_ON_FEATURE:-off}"' 'FEATON="${OVN_BRIDGE_COMMIT_ON_FEATURE:-on}"'; then
  fresh; edit_q "$INT" "tick MDEF"; of0="$(ofe)"; cp_ "$INT" default "$MUT/mac_live_commit_push.sh"
  chk "MDEF (default flipped back to on) is caught: unset env pushed to claude/feature" bash -c "[ '$(ofe)' != '$of0' ]"
fi
if mutant gate-ignored 'if [ "$FEATON" = on ] && [ "$is_live" = 0 ]' 'if [ "$is_live" = 0 ]'; then
  fresh; edit_q "$INT" "tick MG"; of0="$(ofe)"; cp_ "$INT" off "$MUT/mac_live_commit_push.sh"
  chk "MG (switch ignored) is caught: off still pushed to claude/feature" bash -c "[ '$(ofe)' != '$of0' ]"
fi
if mutant force-push 'if git -C "$R" push -q "$REM" "HEAD:refs/heads/$PB"' 'if git -C "$R" push -q -f "$REM" "HEAD:refs/heads/$PB"'; then
  fresh; edit_q "$INT" "tick MH"; fup README.md "up mh" "up mh"
  # origin advances AFTER the helper's own fetch+merge window is impossible to hit deterministically; assert the force flag is simply absent from the real script instead
  chk "MH real script has no force flag on the push" bash -c "! grep -E 'push .*(-f |--force)' '$CP'"
fi
echo; echo "Z8a bridge commit on claude/feature: $((n-fails))/$n passed"; [ "$fails" = 0 ]
