#!/usr/bin/env bash
# Regression test for scripts/lib_worktree.sh (Phase 2 — isolated worktree by default).
#
# The specific bug this guards against (documented at length in reconcile_branches.sh's
# 2026-09-16 fix, which lib_worktree.sh's wt_push extracts): a worktree checked out via
# `checkout -B "$branch" origin/$branch` ends up in DETACHED HEAD whenever $branch is
# already checked out in the main clone (the common case — git refuses two worktrees on
# the same branch). Pushing with the ambiguous `git push origin "$branch"` then silently
# resolves "$branch" as a LOCAL ref lookup and pushes the MAIN CLONE's stale ref instead
# of the worktree's actual commit — reports success, nothing real lands. Test 2 below
# asserts the pushed content on "origin" actually matches the worktree's commit, not just
# that wt_push returned "ok" (a wt_push that silently regressed to the ambiguous push form
# would still report "ok" here — this test would still catch it by checking origin's
# real content).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
LIB="$HERE/../lib_worktree.sh"; [ -f "$LIB" ] || LIB="$HERE/lib_worktree.sh"
[ -f "$LIB" ] || { echo "  SKIP: lib_worktree.sh not found"; exit 0; }
# shellcheck source=../lib_worktree.sh
source "$LIB"

P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT
cd "$TMPROOT" || exit 1

git init -q --bare origin.git
git clone -q origin.git work >/dev/null 2>&1
(
  cd work
  git checkout -q -b overnight/feature
  echo "hello" > file.txt
  git -c user.email=t@t -c user.name=t add file.txt
  git -c user.email=t@t -c user.name=t commit -q -m init
  git push -q origin overnight/feature
)

# --- test 1: wt_open returns a real, populated worktree path ---
wt="$(wt_open work overnight/feature)"
ok "wt_open returns a real worktree with the branch's content" \
  "[ -n '$wt' ] && [ -d '$wt' ] && [ -f '$wt/file.txt' ]"

# --- test 2: wt_push lands the WORKTREE's commit on origin, not a stale main-clone ref ---
echo "modified" >> "$wt/file.txt"
git -C "$wt" -c user.email=t@t -c user.name=t add file.txt
git -C "$wt" -c user.email=t@t -c user.name=t commit -q -m "wt change"
push_result="$(wt_push "$wt" overnight/feature)"
ok "wt_push reports ok" "[ '$push_result' = 'ok' ]"
ok "origin's real content reflects the worktree's commit (not a false-positive push)" \
  "git -C origin.git log -1 --format=%s overnight/feature | grep -q 'wt change'"

# --- test 3: wt_close removes the worktree cleanly, both git's registry and disk ---
wt_close work "$wt"
ok "worktree no longer registered after wt_close" "! git -C work worktree list | grep -q '$wt'"
ok "worktree directory removed from disk after wt_close" "[ ! -d '$wt' ]"

# --- test 4: wt_open fails cleanly (no partial state, no output) on a nonexistent repo ---
bad_wt="$(wt_open /tmp/definitely-does-not-exist-$$ overnight/feature 2>/dev/null)"
bad_rc=$?
ok "wt_open returns non-zero on a bad repo" "[ $bad_rc -ne 0 ]"
ok "wt_open prints nothing on failure (caller pattern: wt=\$(wt_open ...) || exit)" "[ -z '$bad_wt' ]"

# --- test 5: two sequential worktrees of the same branch don't collide or clobber each other ---
wt2="$(wt_open work overnight/feature)"
echo "second" >> "$wt2/file.txt"
git -C "$wt2" -c user.email=t@t -c user.name=t add file.txt
git -C "$wt2" -c user.email=t@t -c user.name=t commit -q -m "second wt change"
push2_result="$(wt_push "$wt2" overnight/feature)"
ok "second sequential worktree push reports ok" "[ '$push2_result' = 'ok' ]"
ok "second worktree's commit actually landed on origin" \
  "git -C origin.git log -1 --format=%s overnight/feature | grep -q 'second wt change'"
wt_close work "$wt2"

# --- test 6: a push that needs a rebase (origin moved since wt_open) still lands ---
# Simulate the concurrent change via a SEPARATE worktree, not the main clone's own branch —
# the main clone's local refs/heads/overnight/feature never advances just because another
# worktree pushed (that's the whole point of the detached-HEAD-per-worktree model this
# library relies on), so pushing FROM the main clone here would be testing a scenario that
# can't actually happen in production (every real caller goes through wt_open/wt_push).
# The two changes touch DIFFERENT files (a real conflict — same-line edits from both sides
# — is a legitimate pushfail outcome for the CALLER to handle via its own retry/escalation
# logic, e.g. ovn_recover_parked.sh's existing hold+fetch+reset-and-retry pattern; it isn't
# something wt_push's one rebase-retry is meant to resolve, matching reconcile_branches.sh's
# own merge_into(), which reports conflicts back to its caller rather than resolving them
# inline outside its opt-in LLM-assist path).
concurrent_wt="$(wt_open work overnight/feature)"
wt3="$(wt_open work overnight/feature)"
echo "concurrent" > "$concurrent_wt/other_file.txt"
git -C "$concurrent_wt" -c user.email=t@t -c user.name=t add other_file.txt
git -C "$concurrent_wt" -c user.email=t@t -c user.name=t commit -q -m "concurrent change from another worktree"
wt_push "$concurrent_wt" overnight/feature >/dev/null
wt_close work "$concurrent_wt"
echo "from worktree" > "$wt3/wt3_file.txt"
git -C "$wt3" -c user.email=t@t -c user.name=t add wt3_file.txt
git -C "$wt3" -c user.email=t@t -c user.name=t commit -q -m "wt3 change needing rebase"
push3_result="$(wt_push "$wt3" overnight/feature)"
ok "push requiring a rebase-retry still reports ok" "[ '$push3_result' = 'ok' ]"
ok "both the concurrent AND the worktree's change are present after the rebase-retry" \
  "git -C origin.git log --format=%s overnight/feature | grep -q 'concurrent change' && git -C origin.git log --format=%s overnight/feature | grep -q 'wt3 change needing rebase'"
wt_close work "$wt3"

# --- test 7: a genuine conflict (same-line edits from two worktrees) reports pushfail,
# not a silent false-success — the caller decides what to do next, this library never
# guesses at conflict resolution ---
conflict_a="$(wt_open work overnight/feature)"
conflict_b="$(wt_open work overnight/feature)"
echo "edit from A" >> "$conflict_a/file.txt"
git -C "$conflict_a" -c user.email=t@t -c user.name=t add file.txt
git -C "$conflict_a" -c user.email=t@t -c user.name=t commit -q -m "conflicting edit A"
wt_push "$conflict_a" overnight/feature >/dev/null
wt_close work "$conflict_a"
echo "edit from B" >> "$conflict_b/file.txt"
git -C "$conflict_b" -c user.email=t@t -c user.name=t add file.txt
git -C "$conflict_b" -c user.email=t@t -c user.name=t commit -q -m "conflicting edit B"
conflict_result="$(wt_push "$conflict_b" overnight/feature)"
ok "a genuine conflict is reported as pushfail, not swallowed as ok" "[ '$conflict_result' = 'pushfail' ]"
git -C "$conflict_b" rebase --abort >/dev/null 2>&1 || true
wt_close work "$conflict_b"

echo "lib_worktree: $P passed, $F failed"
[ "$F" -eq 0 ]
