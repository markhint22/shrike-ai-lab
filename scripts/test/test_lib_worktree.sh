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
# 2026-10-08: assertions are evaluated with pipefail OFF - under pipefail `A | grep -q X` is flaky (grep -q exits at its first hit, A may take SIGPIPE: rc 141) and `! A | grep -q X` can mask a real failure
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

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

# ---- 2026-10-02 additions (ovn_test_watch worktree redesign): --detach, --tag, wt_link_envs, wt_seed_godot ----
(
  cd work
  git -c user.email=t@t -c user.name=t pull -q --rebase origin overnight/feature >/dev/null 2>&1
  mkdir -p backend web game
  echo k > backend/keep.txt; echo k > web/keep.txt; echo k > game/keep.txt
  printf '.venv/\nnode_modules/\n.godot/\n*.import\n*.log\n' > .gitignore
  git -c user.email=t@t -c user.name=t add -A
  git -c user.email=t@t -c user.name=t commit -q -m "tracked dirs for env-link tests"
  git push -q origin overnight/feature
  # untracked, gitignored envs/caches in the LIVE clone
  mkdir -p backend/.venv/bin web/node_modules/m node_modules/top ghost/node_modules/g game/.godot/imported
  echo py > backend/.venv/bin/pytest; echo m > web/node_modules/m/i.js; echo t > node_modules/top/i.js; echo g > ghost/node_modules/g/i.js
  echo imp > game/.godot/imported/a.bin; echo imp > game/sprite.png.import; echo log > game/debug.log
  git checkout -q -b other   # main clone is NOT on overnight/feature (the case that makes `checkout -B` dangerous)
)
LOCAL_BEFORE="$(git -C work rev-parse overnight/feature)"
dwt="$(wt_open work overnight/feature --detach --tag=mytag)"
ok "--tag puts the tag in the worktree dir name" "case '$dwt' in /tmp/wt-mytag-work.*) true;; *) false;; esac"
ok "--detach: worktree is on origin's head" "[ \"\$(git -C '$dwt' rev-parse HEAD)\" = \"\$(git -C work rev-parse origin/overnight/feature)\" ]"
ok "--detach: worktree HEAD is detached (no local branch created)" "! git -C '$dwt' symbolic-ref -q HEAD"
ok "--detach: the main clone's LOCAL overnight/feature ref was NOT moved (no checkout -B)" "[ \"\$(git -C work rev-parse overnight/feature)\" = '$LOCAL_BEFORE' ]"
ok "--detach: main clone still on its own branch" "[ \"\$(git -C work branch --show-current)\" = other ]"
ok "--detach worktree has the tracked files but not the gitignored envs yet" "[ -f '$dwt/backend/keep.txt' ] && [ ! -e '$dwt/backend/.venv' ]"

wt_link_envs work "$dwt"
ok "wt_link_envs: nested backend/.venv linked and usable" "[ -L '$dwt/backend/.venv' ] && [ \"\$(cat '$dwt/backend/.venv/bin/pytest')\" = py ]"
ok "wt_link_envs: nested web/node_modules linked and usable" "[ -L '$dwt/web/node_modules' ] && [ -f '$dwt/web/node_modules/m/i.js' ]"
ok "wt_link_envs: root node_modules linked" "[ -L '$dwt/node_modules' ] && [ -f '$dwt/node_modules/top/i.js' ]"
ok "wt_link_envs: env whose parent dir is not in the worktree is skipped (no stray dirs)" "[ ! -e '$dwt/ghost' ]"
ok "wt_link_envs: symlinks point at the LIVE clone's dirs (absolute)" "[ \"\$(readlink '$dwt/backend/.venv')\" = \"\$(cd work && pwd)/backend/.venv\" ]"
ok "wt_link_envs: idempotent (second call changes nothing, no error)" "wt_link_envs work '$dwt' && [ -L '$dwt/backend/.venv' ]"
ok "wt_link_envs: the .git dir is never linked/walked" "[ ! -L '$dwt/.git' ]"

if command -v rsync >/dev/null 2>&1; then
  wt_seed_godot work "$dwt" game
  ok "wt_seed_godot: copies the ignored .godot cache + *.import files" "[ -f '$dwt/game/.godot/imported/a.bin' ] && [ -f '$dwt/game/sprite.png.import' ]"
  ok "wt_seed_godot: they are COPIES, not links (godot writes into them)" "[ ! -L '$dwt/game/.godot' ] && [ ! -L '$dwt/game/.godot/imported/a.bin' ]"
  ok "wt_seed_godot: other ignored files (debug.log) are NOT copied" "[ ! -e '$dwt/game/debug.log' ]"
  ok "wt_seed_godot: live clone's cache untouched" "[ -f work/game/.godot/imported/a.bin ]"
else echo "  SKIP wt_seed_godot (no rsync)"; fi

wt_close work "$dwt"; rm -rf "$dwt"
ok "closing the worktree removes the links but NEVER the live envs they point at" "[ -f work/backend/.venv/bin/pytest ] && [ -f work/web/node_modules/m/i.js ] && [ -f work/node_modules/top/i.js ]"
ok "closed worktree no longer registered" "! git -C work worktree list | grep -q 'wt-mytag-work'"
# benign: callers that pass no new flags behave exactly as before (branch checked out inside the worktree)
cwt="$(wt_open work overnight/feature)"
ok "no flags: legacy behaviour unchanged (dir name has no tag, worktree populated)" "case '$cwt' in /tmp/wt-work.*) [ -f '$cwt/file.txt' ];; *) false;; esac"
wt_close work "$cwt"

echo "lib_worktree: $P passed, $F failed"
[ "$F" -eq 0 ]
