#!/usr/bin/env bash
# Regression test for reconcile_branches.sh — the branch-divergence guard. Builds a throwaway
# bare "origin" with main/develop/feature, simulates a DIRECT commit to main (the accidental
# chat-to-main case that caused the divergence), runs reconcile, and asserts it back-merges
# main into develop AND feature, is idempotent, and detects a real conflict.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REC="$HERE/../../reconcile_branches.sh"; [ -f "$REC" ] || REC="$HERE/../reconcile_branches.sh"; [ -f "$REC" ] || REC="$HERE/reconcile_branches.sh"
[ -f "$REC" ] || { echo "  ❌ reconcile_branches.sh not found"; exit 1; }
rc=0; ok(){ echo "  ✅ $1"; }; fail(){ echo "  ❌ $1"; rc=1; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export NTFY_TOPIC="shrike_reconcile_selftest_ignore"   # any alert goes to an unwatched junk topic

git init -q --bare "$tmp/origin.git"
git clone -q "$tmp/origin.git" "$tmp/seed" 2>/dev/null
( cd "$tmp/seed"; git config user.email t@t; git config user.name t
  echo base > f.txt; git add -A; git commit -q -m base
  git branch -M main; git push -q origin main
  git checkout -q -b develop; git push -q origin develop
  git checkout -q -b overnight/feature; git push -q origin overnight/feature
  # a DIRECT (non-promote) commit straight on main -> main ahead of develop
  git checkout -q main; echo hot > hot.txt; git add -A; git commit -q -m "fix: direct hotfix to main"; git push -q origin main )

# fake HOME/overnight-queue with a clone at repos/testrepo (reconcile cds to $HOME/overnight-queue)
export HOME="$tmp/home"; mkdir -p "$HOME/overnight-queue/repos"
cp "$REC" "$HOME/overnight-queue/reconcile_branches.sh"
git clone -q "$tmp/origin.git" "$HOME/overnight-queue/repos/testrepo" 2>/dev/null

out=$(cd "$HOME/overnight-queue" && bash ./reconcile_branches.sh repos/testrepo 2>&1)
echo "$out" | grep -q "back-merged main->develop" && ok "back-merges a direct-to-main commit into develop" || fail "no back-merge: $out"
git -C "$HOME/overnight-queue/repos/testrepo" fetch -q origin
git -C "$HOME/overnight-queue/repos/testrepo" merge-base --is-ancestor origin/main origin/develop && ok "develop now contains main" || fail "develop missing main's commit"
git -C "$HOME/overnight-queue/repos/testrepo" merge-base --is-ancestor origin/main origin/overnight/feature && ok "feature now contains main" || fail "feature missing main's commit"

out2=$(cd "$HOME/overnight-queue" && bash ./reconcile_branches.sh repos/testrepo 2>&1)
echo "$out2" | grep -q "in sync" && ok "idempotent (second run = all in sync)" || fail "not idempotent: $out2"

# conflict case: main and develop edit the same file differently -> must FLAG, not silently merge.
# Reset the seed to the CURRENT origin first (the earlier reconcile advanced it) so the edits actually
# diverge and the pushes aren't rejected as non-fast-forward.
( cd "$tmp/seed"; git fetch -q origin
  git checkout -q -B develop origin/develop; echo devside > hot.txt; git add -A; git commit -q -m "dev edits hot"; git push -q origin develop
  git checkout -q -B main origin/main; echo mainside > hot.txt; git add -A; git commit -q -m "main edits hot (direct)"; git push -q origin main )
outc=$(cd "$HOME/overnight-queue" && bash ./reconcile_branches.sh repos/testrepo 2>&1)
echo "$outc" | grep -qi "CONFLICT main" && ok "detects + flags a real main/develop conflict" || fail "conflict not flagged: $outc"

# 2026-09-16 regression: the real-world case where the "ambiguous push from a detached
# worktree" bug actually bit. In production, repos/<name> (the main clone) sits checked out
# on overnight/feature - the SAME branch merge_into's develop->overnight/feature sync targets
# in a fresh worktree via `checkout -B overnight/feature ...`. git refuses to check out one
# branch in two worktrees of the same repo at once, so that checkout silently fails, leaving
# the worktree in detached HEAD - and the old ambiguous `git push origin "$tgt"` then
# resolved "overnight/feature" to the MAIN CLONE's own (unrelated, unchanged) local branch
# ref instead of the worktree's actual merged HEAD, most often reporting false success
# ("Everything up-to-date") while nothing real ever reached origin. Reproduce the exact
# condition on a FRESH, isolated origin/repo (the earlier test cases above leave main/develop
# deliberately conflicted - reusing that repo here would contaminate this scenario): a main
# clone checked out to overnight/feature (matching real usage), overnight/feature has a real
# unique commit (forcing merge_into's real-merge path, not a plain fast-forward), develop has
# a non-conflicting advance. Confirm the sync doesn't just report success - it must ACTUALLY
# land on origin.
git init -q --bare "$tmp/origin2.git"
git clone -q "$tmp/origin2.git" "$tmp/seed2" 2>/dev/null
( cd "$tmp/seed2"; git config user.email t@t; git config user.name t
  echo base > f.txt; git add -A; git commit -q -m base
  git branch -M main; git push -q origin main
  git checkout -q -b develop; git push -q origin develop
  git checkout -q -b overnight/feature; git push -q origin overnight/feature
  echo "feature-only work" > feature_only.txt; git add -A; git commit -q -m "feat: fleet work only on feature"; git push -q origin overnight/feature
  git checkout -q -B develop origin/develop
  echo "develop-only work" > develop_only.txt; git add -A; git commit -q -m "feat: unrelated develop advance"; git push -q origin develop )
git clone -q "$tmp/origin2.git" "$HOME/overnight-queue/repos/testrepo2" 2>/dev/null
git -C "$HOME/overnight-queue/repos/testrepo2" checkout -q overnight/feature
before_feat_sha="$(git -C "$tmp/seed2" rev-parse origin/overnight/feature)"
outd=$(cd "$HOME/overnight-queue" && bash ./reconcile_branches.sh repos/testrepo2 2>&1)
echo "$outd" | grep -q "merged develop->overnight/feature" && ok "reports a real merge (not a false no-op) for develop->overnight/feature" || fail "did not report a merge: $outd"
git -C "$HOME/overnight-queue/repos/testrepo2" fetch -q origin overnight/feature
after_feat_sha="$(git -C "$HOME/overnight-queue/repos/testrepo2" rev-parse origin/overnight/feature)"
[ "$before_feat_sha" != "$after_feat_sha" ] && ok "origin/overnight/feature's tip actually MOVED (the real bug: it silently didn't)" || fail "origin/overnight/feature is UNCHANGED - the false-success bug is back"
git -C "$HOME/overnight-queue/repos/testrepo2" merge-base --is-ancestor origin/develop origin/overnight/feature && ok "the real merge commit actually contains develop's content" || fail "overnight/feature does not actually contain develop - push was a no-op"

[ $rc -eq 0 ] && echo "  test_reconcile_branches: PASS" || echo "  test_reconcile_branches: FAIL"
exit $rc
