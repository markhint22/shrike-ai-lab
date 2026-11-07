#!/usr/bin/env bash
# Y2 (2026-11-04): ops/shared_branch_sync.sh - dry-run by default, --apply merges origin/develop into claude/feature and claude/feature into develop in a temp worktree: merge only, no force, no stash,
# never main, conflicts aborted with nothing pushed, push rejections stop with exit 4. Hermetic: a local bare "remote", private HOME/TMPDIR, no network, no ntfy, never the real shared repo. 8 mutants.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
[ -f "$HERE/ntfy_guard.sh" ] && . "$HERE/ntfy_guard.sh"
export NTFY_SERVER=http://127.0.0.1:9 OVN_NOTIFY_DISABLE=1 TZ=UTC
SYNC_SRC="${Y2_SYNC_SRC:-$HERE/../../ops/shared_branch_sync.sh}"
P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
W="$(safe_mktemp_dir y2sync)" || exit 1
case "$W" in /*/y2sync.??????) ;; *) echo "unsafe scratch dir '$W': abort" >&2; exit 2;; esac
cleanup(){ case "$W" in /*/y2sync.??????) find "$W" -mindepth 1 -depth -delete 2>/dev/null; rmdir "$W" 2>/dev/null;; esac; }
trap cleanup EXIT
safe_set_sandbox_home "$W" || exit 1; export TMPDIR="$W/tmp"; mkdir -p "$TMPDIR"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_GLOBAL="$W/gitconfig" GIT_CONFIG_NOSYSTEM=1
: > "$GIT_CONFIG_GLOBAL"
git config --global init.defaultBranch main; git config --global commit.gpgsign false
SYNC="$W/shared_branch_sync.sh"; cp "$SYNC_SRC" "$SYNC"; mkdir -p "$W/ops"

# mk <name> [conflict]: bare remote + working clone; develop has bridge commits on CLAUDE_QUEUE.md, claude/feature has pipeline code commits (conflicting edit of one line when asked)
mk(){
  local n="$1" conf="${2:-}" R="$W/$1.git" C="$W/$1"
  git init -q --bare "$R"; git clone -q "$R" "$C" 2>/dev/null
  ( cd "$C" || exit 1
    printf 'base\nline-a\n' > CLAUDE_QUEUE.md; mkdir -p scripts; echo 1 > scripts/x.py; git add -A; git commit -q -m base; git push -q origin HEAD:refs/heads/main
    git checkout -q -b develop; git push -q origin develop
    git checkout -q -b claude/feature; git push -q origin claude/feature
    git checkout -q develop
    echo "bridge 1" >> CLAUDE_QUEUE.md; git commit -qam "chore(queue): bridge 1"; echo "bridge 2" >> CLAUDE_QUEUE.md; git commit -qam "chore(queue): bridge 2"
    [ -n "$conf" ] && { sed -i.bak 's/line-a/line-DEVELOP/' CLAUDE_QUEUE.md; rm -f CLAUDE_QUEUE.md.bak; git commit -qam "dev edit"; }
    git push -q origin develop
    git checkout -q claude/feature
    echo 2 > scripts/x.py; git commit -qam "feat: pipeline 1"; echo 3 > scripts/y.py; git add -A; git commit -qm "feat: pipeline 2"
    [ -n "$conf" ] && { sed -i.bak 's/line-a/line-FEATURE/' CLAUDE_QUEUE.md; rm -f CLAUDE_QUEUE.md.bak; git commit -qam "feature edit"; }
    git push -q origin claude/feature
  ) >/dev/null 2>&1
}
rsha(){ git --git-dir="$W/$1.git" rev-parse "refs/heads/$2" 2>/dev/null; }
run(){ # <name> <args...>  (cwd = the clone)
  local n="$1"; shift; ( cd "$W/$n" && bash "$SYNC" --repo "$W/$n" "$@" ) 2>&1; }

mk A
M0="$(rsha A main)"; D0="$(rsha A develop)"; F0="$(rsha A claude/feature)"
echo "== dry run"
out="$(run A)"; rc=$?
ok "D1 dry-run exits 0 and says DRY RUN" '[ "$rc" = 0 ] && echo "$out" | grep -q "DRY RUN"'
ok "D2 dry-run reports 2 ahead in develop and 2 in claude/feature" 'echo "$out" | grep -q "is 2 commit(s) ahead of origin/claude/feature; origin/claude/feature is 2 commit(s) ahead"'
ok "D3 dry-run reports no conflict for the clean fixture" 'echo "$out" | grep -q "conflict: no"'
ok "D4 dry-run changed no remote branch" '[ "$(rsha A main)" = "$M0" ] && [ "$(rsha A develop)" = "$D0" ] && [ "$(rsha A claude/feature)" = "$F0" ]'
ok "D5 dry-run left no extra worktree" '[ "$(git -C "$W/A" worktree list | wc -l | tr -d " ")" = 1 ]'
mk Dd; DT0="$(git -C "$W/Dd" rev-parse origin/develop)"
git clone -q "$W/Dd.git" "$W/Dd_other" 2>/dev/null && ( cd "$W/Dd_other" && git checkout -q develop && echo more >> CLAUDE_QUEUE.md && git commit -qam "late bridge" && git push -q origin develop ) >/dev/null 2>&1
run Dd >/dev/null
ok "D7 dry-run does not fetch (origin/develop tracking ref did not move although the remote did)" '[ "$(git -C "$W/Dd" rev-parse origin/develop)" = "$DT0" ] && [ "$(rsha Dd develop)" != "$DT0" ]'
out_c="$(mk Cdry conflict; run Cdry)"
ok "D6 dry-run flags the real conflict" 'echo "$out_c" | grep -q "conflict: YES"'

echo "== apply"
out="$(run A --apply)"; rc=$?
D1="$(rsha A develop)"; F1="$(rsha A claude/feature)"
ok "A1 --apply exits 0" '[ "$rc" = 0 ]'
ok "A2 develop and claude/feature end on the SAME commit" '[ -n "$D1" ] && [ "$D1" = "$F1" ]'
ok "A3 the result contains both the bridge commits and the pipeline code" 'git --git-dir="$W/A.git" show "$F1:CLAUDE_QUEUE.md" | grep -q "bridge 2" && git --git-dir="$W/A.git" show "$F1:scripts/y.py" | grep -q 3'
ok "A4 both old tips are ancestors (nothing lost, history preserved: no rebase)" 'git --git-dir="$W/A.git" merge-base --is-ancestor "$D0" "$F1" && git --git-dir="$W/A.git" merge-base --is-ancestor "$F0" "$F1"'
ok "A5 main is untouched" '[ "$(rsha A main)" = "$M0" ]'
ok "A6 the merge commit carries the Claude trailer and a conventional subject" 'git --git-dir="$W/A.git" log -1 --format=%B "$F1" | grep -q "Co-Authored-By: Claude Sonnet 5.5" && git --git-dir="$W/A.git" log -1 --format=%s "$F1" | grep -q "^chore(sync): merge origin/develop into claude/feature"'
ok "A7 the user clone has no stash, no extra worktree, no leftover temp dir" '[ -z "$(git -C "$W/A" stash list)" ] && [ "$(git -C "$W/A" worktree list | wc -l | tr -d " ")" = 1 ] && [ -z "$(ls -A "$TMPDIR")" ]'
ok "A8 the user clone checkout/branch was never touched (still on claude/feature, clean)" '[ "$(git -C "$W/A" symbolic-ref --short HEAD)" = "claude/feature" ] && [ -z "$(git -C "$W/A" status --porcelain)" ]'
out2="$(run A --apply)"; rc2=$?
ok "A9 a second --apply is a no-op (nothing to merge, tips unchanged)" '[ "$rc2" = 0 ] && echo "$out2" | grep -q "nothing to merge" && [ "$(rsha A develop)" = "$D1" ] && [ "$(rsha A claude/feature)" = "$F1" ]'

echo "== conflict"
mk C conflict
MC="$(rsha C main)"; DC="$(rsha C develop)"; FC="$(rsha C claude/feature)"
out="$(run C --apply)"; rc=$?
ok "C1 conflict -> exit 3 and names CLAUDE_QUEUE.md" '[ "$rc" = 3 ] && echo "$out" | grep -q "MERGE CONFLICT" && echo "$out" | grep -q "CLAUDE_QUEUE.md"'
ok "C2 nothing was pushed (all three remote branches unchanged), step 2 skipped" '[ "$(rsha C main)" = "$MC" ] && [ "$(rsha C develop)" = "$DC" ] && [ "$(rsha C claude/feature)" = "$FC" ] && echo "$out" | grep -q "step 2 skipped"'
ok "C3 conflict leaves no worktree/stash/temp dir behind" '[ "$(git -C "$W/C" worktree list | wc -l | tr -d " ")" = 1 ] && [ -z "$(git -C "$W/C" stash list)" ] && [ -z "$(ls -A "$TMPDIR")" ]'

echo "== guards"
for b in main master prod release/1.0; do
  out="$(run A --apply --feature "$b")"; rc=$?
  ok "G1 refuses --feature $b (exit 2)" '[ "$rc" = 2 ]'
done
out="$(run A --apply --develop main)"; rc=$?
ok "G2 refuses --develop main" '[ "$rc" = 2 ]'
out="$(run A --feature develop --develop develop)"; rc=$?
ok "G3 refuses identical branches" '[ "$rc" = 2 ]'
out="$(run A --bogus)"; rc=$?
ok "G4 unknown argument -> exit 2" '[ "$rc" = 2 ]'
ok "G5 script has no rebase, force push, stash, ntfy or curl" '! grep -v "^[[:space:]]*#" "$SYNC_SRC" | grep -q -E "rebase|push .*(--force|-f |\\+)|stash|ntfy|curl"'
ok "G6 script is executable-clean bash (bash -n)" 'bash -n "$SYNC_SRC"'

echo "== push rejected"
mk R
HOOK="$W/R.git/hooks/pre-receive"; printf '#!/bin/sh\necho rejected-by-test >&2\nexit 1\n' > "$HOOK"; chmod +x "$HOOK"
DR="$(rsha R develop)"; FR="$(rsha R claude/feature)"
out="$(run R --apply)"; rc=$?
ok "R1 a push that is always rejected -> exit 4 after 3 attempts, branches unchanged" '[ "$rc" = 4 ] && echo "$out" | grep -q "attempt 3/3" && [ "$(rsha R develop)" = "$DR" ] && [ "$(rsha R claude/feature)" = "$FR" ]'
ok "R2 rejected run leaves no worktree/temp dir" '[ "$(git -C "$W/R" worktree list | wc -l | tr -d " ")" = 1 ] && [ -z "$(ls -A "$TMPDIR")" ]'

echo "== registration"
ok "X1 test registered in run_all.sh before finish (outside finish())" "awk '/bash test_y2_shared_branch_sync.sh/{r=NR} /^echo; finish/{f=NR} END{exit !(r && f && r<f)}' '$HERE/run_all.sh'"
ok "X2 python test registered in run_all.sh before finish" "awk '/python3 test_y2_bridge_harvest.py/{r=NR} /^echo; finish/{f=NR} END{exit !(r && f && r<f)}' '$HERE/run_all.sh'"

# ---------------------------------------------------------------- mutants (only in the primary run)
if [ -z "${Y2_SYNC_SRC:-}" ]; then
  echo "== mutants"
  mut(){ # <name> <python-old> <python-new>
    local name="$1" old="$2" new="$3" m="$W/mut_$RANDOM.sh"
    python3 - "$SYNC_SRC" "$m" "$old" "$new" <<'PY'
import sys
s = open(sys.argv[1]).read()
if sys.argv[3] not in s:
    sys.exit(7)
open(sys.argv[2], "w").write(s.replace(sys.argv[3], sys.argv[4], 1))
PY
    local prc=$?
    if [ "$prc" != 0 ]; then F=$((F+1)); echo "  FAIL mutant '$name' does not apply"; return; fi
    if Y2_SYNC_SRC="$m" bash "$0" >/dev/null 2>&1; then F=$((F+1)); echo "  FAIL mutant NOT caught: $name"; else P=$((P+1)); echo "  ok   mutant caught: $name"; fi
  }
  mut "apply by default" 'APPLY=0; REPO=""' 'APPLY=1; REPO=""'
  mut "conflict not detected" 'if ! git -C "$WT" -c user.name' 'if false && ! git -C "$WT" -c user.name'
  mut "main allowed" 'case "$b" in main|master|prod|production|release/*|"")' 'case "$b" in "")'
  mut "force push" 'push -q "$REMOTE" "HEAD:refs/heads/$into"' 'push -q --force "$REMOTE" "HEAD:refs/heads/$into"'
  mut "step 2 runs after a failed step 1" '[ "$rc" = 0 ] || { log "step 1 failed (rc=$rc); step 2 skipped"; exit "$rc"; }' 'true'
  mut "dry-run fetches" 'log "DRY RUN on $REPO (no fetch, no writes; --apply does the merge+push)"' 'git -C "$REPO" fetch --quiet "$REMOTE"; log "DRY RUN on $REPO (no fetch, no writes; --apply does the merge+push)"'
  mut "retry loop cut to one attempt" 'for try in 1 2 3; do' 'for try in 1; do'
  mut "merge ignores the trailer" 'merge -q -m "chore(sync): merge $from into $into

$TRAILER"' 'merge -q -m "chore(sync): merge $from into $into"'
fi
echo; echo "test_y2_shared_branch_sync: $P passed, $F failed"
[ "$F" = 0 ]
