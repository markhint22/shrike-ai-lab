#!/usr/bin/env bash
# Regression test for ovn_stage_runner.sh's push-accounting fix (2026-09-09).
#
# Before the fix, `ncommits` (which feeds the stage_runs summary's `commits_pushed` field —
# the ground truth this whole pipeline's T3+ pass rate is computed from) was set from the
# PRE-push local rev-list count and never cleared when the push itself failed. A push that
# raced and lost would still report commits_pushed>0, even though nothing reached origin and
# the commits are later lost with the worktree. Never observed live (0 hits in
# state/stage_runs/*.log at fix time) but it's the exact same silent-success shape as the T3+
# land-rate bug this session found and fixed elsewhere, so it gets a real integration test:
# build a throwaway bare "origin", make the push race for real, and assert commits_pushed only
# reflects what ACTUALLY reached origin.
#
# Extracts the real block out of ovn_stage_runner.sh (not a reimplementation) so this can't
# silently drift from what's deployed.
set -uo pipefail
SR="${OVN_STAGE_RUNNER:-$HOME/overnight-queue/ovn_stage_runner.sh}"
[ -f "$SR" ] || { echo "  SKIP: $SR not found on this host"; exit 0; }

BLOCK="$(sed -n '/^# ---- push ONLY when independently verified ----$/,/^fi$/p' "$SR")"
[ -n "$BLOCK" ] || { echo "  FAIL: could not extract the push-accounting block from $SR"; exit 1; }
# sanity: make sure we captured the right block (not a coincidental namesake) and that it still
# has the fix (a stale extraction — e.g. if the block got restructured — should fail loudly here
# rather than silently testing nothing).
case "$BLOCK" in
  *'local_ncommits='*'git -C "$wt" rev-list'*) : ;;
  *) echo "  FAIL: extracted block doesn't look like the expected push-accounting code:"; printf '%s\n' "$BLOCK"; exit 1 ;;
esac

P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
say(){ :; }  # the real script's logger; a no-op here is fine, we only assert on $ncommits

git init -q --bare "$tmp/origin.git"
git clone -q "$tmp/origin.git" "$tmp/seed" 2>/dev/null
( cd "$tmp/seed"; git config user.email t@t; git config user.name t
  echo base > f.txt; git add -A; git commit -q -m base
  git branch -M overnight/feature; git push -q origin overnight/feature )
# the bare repo's default HEAD still points at whatever init.defaultBranch resolved to (which
# never received a commit) - fix it so a plain `git clone` of origin checks out overnight/feature.
git -C "$tmp/origin.git" symbolic-ref HEAD refs/heads/overnight/feature

run_block(){ # $1 = worktree dir; sets VERIFIED=1 and evals the extracted block in-scope
  local wt="$1" ncommits VERIFIED=1
  # git rebase/push chatter (e.g. "Auto-merging f.txt" / "CONFLICT...") goes to the eval'd
  # block's OWN stdout+stderr - in the real pipeline that's fine (the whole stage runner's
  # stdout is redirected to a task log by its caller), but here it would otherwise pollute
  # the $(...) capture of $ncommits below. Suppress it the same way the real caller does.
  eval "$BLOCK" >/dev/null 2>&1
  printf '%s' "$ncommits"
}

# ---- scenario A: clean push, nothing else touched origin -> commits_pushed reflects reality ----
git clone -q "$tmp/origin.git" "$tmp/wt_clean" 2>/dev/null
( cd "$tmp/wt_clean"; git config user.email t@t; git config user.name t
  echo change > g.txt; git add -A; git commit -q -m "real change" )
nc_clean="$(run_block "$tmp/wt_clean")"
ok "clean push: ncommits reflects the real pushed count (1)" "[ '$nc_clean' = 1 ]"
ok "clean push: the commit actually reached origin" \
   "git -C '$tmp/origin.git' log --oneline overnight/feature | grep -q 'real change'"

# ---- scenario B: a RACE — another clone pushes first, so this worktree's push is rejected AND
#      the rebase-retry hits a real conflicting file -> push must fail for real ----
git clone -q "$tmp/origin.git" "$tmp/wt_race" 2>/dev/null
( cd "$tmp/wt_race"; git config user.email t@t; git config user.name t
  echo racer-change > f.txt; git add -A; git commit -q -m "racing local change" )
# a DIFFERENT clone lands first and changes the SAME line, so the rebase in the retry conflicts
git clone -q "$tmp/origin.git" "$tmp/wt_other" 2>/dev/null
( cd "$tmp/wt_other"; git config user.email t@t; git config user.name t
  echo other-change > f.txt; git add -A; git commit -q -m "the winning racer"; git push -q origin overnight/feature )
nc_race="$(run_block "$tmp/wt_race")"
ok "lost race: ncommits is 0 (NOT counted as pushed)" "[ '$nc_race' = 0 ]"
ok "lost race: the losing commit did NOT reach origin" \
   "! git -C '$tmp/origin.git' log --oneline overnight/feature | grep -q 'racing local change'"

echo "Stage push-accounting: $P passed, $F failed"
[ "$F" -eq 0 ]
