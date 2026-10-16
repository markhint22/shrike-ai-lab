#!/usr/bin/env bash
# Git-level tests for scripts/ovn_progress_merge.py (package conflict, 2026-10-12): the REAL conflict shape in throwaway repos, the per-clone
# driver wiring (info/attributes + `git config merge.ovn-progress.driver`, never global config), the OVN_PM_DEFER / OVN_PROGRESS_MERGE switches,
# and --resolve-index (resolve from the index stages; decline - touching nothing - when anything else is conflicted).
# Optional: when the real iptv_apps history is on this machine (OVN_REAL_IPTV_REPO, default ~/LocalProjects/iptv_apps) the actual conflict between
# fb07d121d1 (develop) and c2204cc7d9 (overnight/feature) is replayed and the merged TREE must equal the hand resolution c7be7d3c.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PM="$HERE/../ovn_progress_merge.py"; FIX="$HERE/fixtures/progress_merge"
[ -f "$PM" ] || { echo "  FAIL: ovn_progress_merge.py not found"; exit 1; }
for t in git python3; do command -v $t >/dev/null || { echo "  SKIP: no $t"; exit 0; }; done
pass=0; fail=0
ok(){ if [ "$2" = "1" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "  FAIL $1"; fi; }
b(){ if "$@" >/dev/null 2>&1; then echo 1; else echo 0; fi; }   # command succeeded -> 1
REAL_HOME_DIR="$HOME"
T="$(mktemp -d)" || exit 1; trap 'rm -rf "$T"' EXIT
export HOME="$T/home"; mkdir -p "$HOME"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export OVN_PM_LOG="$T/pm.log"
unset OVN_PROGRESS_MERGE OVN_PM_DEFER

# repo with the real conflict shape: base on main, ours on A, theirs on B (+ an unrelated file only B touches)
mkrepo(){   # $1 = dir
  git init -q -b main "$1"; ( cd "$1"
    cp "$FIX/real_base.md" OVERNIGHT_PROGRESS.md; echo base > code.txt; git add -A; git commit -q -m base
    git checkout -q -b A; cp "$FIX/real_ours.md" OVERNIGHT_PROGRESS.md; git commit -qam "ours"
    git checkout -q main; git checkout -q -b B; cp "$FIX/real_theirs.md" OVERNIGHT_PROGRESS.md; echo b > b_only.txt; git add -A; git commit -q -m "theirs"
    git checkout -q A )
}

# ===== plain git conflicts (reproduction) =====
mkrepo "$T/r1"
ok "repro: a plain 'git merge' of the real shape CONFLICTS on OVERNIGHT_PROGRESS.md" "$(b bash -c "cd '$T/r1' && ! git merge --no-edit B")"
ok "repro: the conflict is on OVERNIGHT_PROGRESS.md" "$([ "$(git -C "$T/r1" diff --name-only --diff-filter=U)" = "OVERNIGHT_PROGRESS.md" ] && echo 1 || echo 0)"
git -C "$T/r1" merge --abort

# ===== setup-clone wiring =====
python3 "$PM" --setup-clone "$T/r1"; ok "setup-clone exits 0" "$([ $? = 0 ] && echo 1 || echo 0)"
ATTR="$T/r1/.git/info/attributes"
ok "setup-clone writes info/attributes (PROGRESS)" "$(grep -qxF 'OVERNIGHT_PROGRESS.md merge=ovn-progress' "$ATTR" && echo 1 || echo 0)"
ok "setup-clone writes info/attributes (DONE)" "$(grep -qxF 'OVERNIGHT_DONE.md merge=ovn-progress' "$ATTR" && echo 1 || echo 0)"
ok "setup-clone writes info/attributes (CLAUDE_QUEUE)" "$(grep -qxF 'CLAUDE_QUEUE.md merge=ovn-progress' "$ATTR" && echo 1 || echo 0)"
ok "setup-clone sets the LOCAL driver config naming this script" "$(git -C "$T/r1" config --local --get merge.ovn-progress.driver | grep -qF "ovn_progress_merge.py" && echo 1 || echo 0)"
ok "setup-clone never touches global config" "$([ ! -s "$HOME/.gitconfig" ] && [ -z "$(git config --global --list 2>/dev/null)" ] && echo 1 || echo 0)"
python3 "$PM" --setup-clone "$T/r1"; python3 "$PM" --setup-clone "$T/r1"
ok "setup-clone is idempotent (one attribute line each, one config value)" "$([ "$(grep -c 'merge=ovn-progress' "$ATTR")" = 3 ] && [ "$(git -C "$T/r1" config --local --get-all merge.ovn-progress.driver | wc -l | tr -d ' ')" = 1 ] && echo 1 || echo 0)"
ok "setup-clone on a non-repo fails cleanly" "$(b bash -c "! python3 '$PM' --setup-clone '$T/nope'")"

# ===== the wired clone resolves the real shape inside 'git merge' =====
( cd "$T/r1" && git merge --no-edit B >/dev/null 2>&1 ); mrc=$?
ok "wired clone: 'git merge B' exits 0 (the driver resolved it)" "$([ $mrc = 0 ] && echo 1 || echo 0)"
ok "wired clone: result == the hand resolution (distilled c7be7d3c)" "$(cmp -s "$T/r1/OVERNIGHT_PROGRESS.md" "$FIX/real_hand.md" && echo 1 || echo 0)"
ok "wired clone: it is a real merge commit (2 parents) and B's unrelated file merged" "$([ "$(git -C "$T/r1" rev-list --parents -n1 HEAD | wc -w | tr -d ' ')" = 3 ] && [ -f "$T/r1/b_only.txt" ] && echo 1 || echo 0)"
ok "wired clone: the resolution was logged (driver mode)" "$(grep -q 'mode=driver' "$T/pm.log" && echo 1 || echo 0)"

# worktrees of a wired clone share the wiring (hygiene/reconcile merge in /tmp worktrees)
mkrepo "$T/r2"; python3 "$PM" --setup-clone "$T/r2"
git -C "$T/r2" worktree add -q --detach "$T/r2wt" A
( cd "$T/r2wt" && git merge --no-edit B >/dev/null 2>&1 ); wrc=$?
ok "worktree of a wired clone: merge resolved through the shared driver wiring" "$([ $wrc = 0 ] && cmp -s "$T/r2wt/OVERNIGHT_PROGRESS.md" "$FIX/real_hand.md" && echo 1 || echo 0)"
git -C "$T/r2" worktree remove --force "$T/r2wt"

# ===== OVN_PM_DEFER: the driver steps aside (plain text merge) so the caller can resolve under its gate =====
mkrepo "$T/r3"; python3 "$PM" --setup-clone "$T/r3"
( cd "$T/r3" && OVN_PM_DEFER=1 git merge --no-edit B >/dev/null 2>&1 ); drc=$?
ok "OVN_PM_DEFER=1: the merge CONFLICTS (driver defers to the text merge)" "$([ $drc != 0 ] && [ "$(git -C "$T/r3" diff --name-only --diff-filter=U)" = "OVERNIGHT_PROGRESS.md" ] && echo 1 || echo 0)"
ok "OVN_PM_DEFER=1: conflict markers are in the file as with a plain merge" "$(grep -q '^<<<<<<<' "$T/r3/OVERNIGHT_PROGRESS.md" && echo 1 || echo 0)"
# --resolve-index resolves from the index stages (ignores the marker text in the work tree)
out="$(python3 "$PM" --resolve-index "$T/r3" --tag t)"; rrc=$?
ok "resolve-index: exit 0 and says what it resolved" "$([ $rrc = 0 ] && echo "$out" | grep -q 'resolved: OVERNIGHT_PROGRESS.md' && echo 1 || echo 0)"
ok "resolve-index: file == hand resolution, no markers, and staged (no unmerged paths left)" "$(cmp -s "$T/r3/OVERNIGHT_PROGRESS.md" "$FIX/real_hand.md" && [ -z "$(git -C "$T/r3" diff --name-only --diff-filter=U)" ] && echo 1 || echo 0)"
( cd "$T/r3" && git commit --no-edit -q ) 2>/dev/null
ok "resolve-index: 'git commit' then makes the 2-parent merge commit" "$([ "$(git -C "$T/r3" rev-list --parents -n1 HEAD | wc -w | tr -d ' ')" = 3 ] && echo 1 || echo 0)"
ok "resolve-index: logged with the tag" "$(grep -q '| t | OVERNIGHT_PROGRESS.md | mode=resolve-index' "$T/pm.log" && echo 1 || echo 0)"

# ===== resolve-index DECLINES (touches nothing) when anything else is conflicted =====
mkrepo "$T/r4"; python3 "$PM" --setup-clone "$T/r4"
( cd "$T/r4" && git checkout -q main && echo mainside > code.txt && git commit -qam "main edits code" && git branch -f A2 HEAD )
( cd "$T/r4" && git checkout -q A && echo aside > code.txt && git commit -qam "A edits code" && git checkout -q B && echo bside > code.txt && git commit -qam "B edits code" && git checkout -q A )
( cd "$T/r4" && OVN_PM_DEFER=1 git merge --no-edit B >/dev/null 2>&1 )
before="$(git -C "$T/r4" ls-files -u | md5sum)"
python3 "$PM" --resolve-index "$T/r4" --tag t >/dev/null 2>&1; rrc=$?
ok "decline: PROGRESS + code.txt both conflicted -> exit 1" "$([ $rrc = 1 ] && echo 1 || echo 0)"
ok "decline: the index is untouched (still 2 unmerged paths)" "$([ "$before" = "$(git -C "$T/r4" ls-files -u | md5sum)" ] && [ "$(git -C "$T/r4" diff --name-only --diff-filter=U | wc -l | tr -d ' ')" = 2 ] && echo 1 || echo 0)"
ok "decline: the decline is logged" "$(grep -q 'declined: code.txt is conflicted too' "$T/pm.log" && echo 1 || echo 0)"
git -C "$T/r4" merge --abort
# a conflict on a non-progress file only
mkrepo "$T/r5"; ( cd "$T/r5" && git checkout -q A && echo a > code.txt && git commit -qam a && git checkout -q B && echo b > code.txt && git commit -qam b && git checkout -q A && OVN_PM_DEFER=1 git merge --no-edit B >/dev/null 2>&1 )
python3 "$PM" --resolve-index "$T/r5" >/dev/null 2>&1; ok "decline: only a code file conflicted -> exit 1" "$([ $? = 1 ] && echo 1 || echo 0)"
git -C "$T/r5" merge --abort
# no merge in progress
python3 "$PM" --resolve-index "$T/r5" >/dev/null 2>&1; ok "decline: nothing unmerged -> exit 1" "$([ $? = 1 ] && echo 1 || echo 0)"
# delete/modify on the progress file is not guessed
mkrepo "$T/r6"; ( cd "$T/r6" && git checkout -q A && git rm -q OVERNIGHT_PROGRESS.md && git commit -qm "A deletes it" && OVN_PM_DEFER=1 git merge --no-edit B >/dev/null 2>&1 )
python3 "$PM" --resolve-index "$T/r6" >/dev/null 2>&1; ok "decline: delete/modify conflict on the progress file -> exit 1" "$([ $? = 1 ] && echo 1 || echo 0)"
git -C "$T/r6" merge --abort

# ===== kill switch =====
mkrepo "$T/r7"; python3 "$PM" --setup-clone "$T/r7"
( cd "$T/r7" && OVN_PROGRESS_MERGE=off git merge --no-edit B >/dev/null 2>&1 ); krc=$?
ok "OVN_PROGRESS_MERGE=off: the wired clone's merge conflicts again (plain text merge)" "$([ $krc != 0 ] && grep -q '^<<<<<<<' "$T/r7/OVERNIGHT_PROGRESS.md" && echo 1 || echo 0)"
OVN_PROGRESS_MERGE=off python3 "$PM" --resolve-index "$T/r7" >/dev/null 2>&1; ok "OVN_PROGRESS_MERGE=off: resolve-index declines" "$([ $? = 1 ] && echo 1 || echo 0)"
git -C "$T/r7" merge --abort
OVN_PROGRESS_MERGE=off python3 "$PM" --setup-clone "$T/r7"
ok "OVN_PROGRESS_MERGE=off: setup-clone unwires the clone (attributes + config removed)" "$([ -z "$(grep 'ovn-progress' "$T/r7/.git/info/attributes" 2>/dev/null)" ] && [ -z "$(git -C "$T/r7" config --local --get merge.ovn-progress.driver)" ] && echo 1 || echo 0)"
( cd "$T/r7" && git merge --no-edit B >/dev/null 2>&1 ); ok "unwired clone: plain merge conflicts" "$([ $? != 0 ] && echo 1 || echo 0)"
git -C "$T/r7" merge --abort

# ===== the driver never leaves git with a half result: a broken resolver falls back to the text merge =====
mkrepo "$T/r8"; python3 "$PM" --setup-clone "$T/r8"
git -C "$T/r8" config --local merge.ovn-progress.driver "python3 -c 'import sys; sys.exit(3)' %O %A %B"   # a crashing driver = git treats it as a conflict (its own contract)
( cd "$T/r8" && git merge --no-edit B >/dev/null 2>&1 ); ok "a failing driver process is a normal conflict (git contract), merge is not silently 'resolved'" "$([ $? != 0 ] && echo 1 || echo 0)"
git -C "$T/r8" merge --abort
# driver mode directly on plain text (no items): both rewrites kept
printf 'a\nb\n' > "$T/g_base"; printf 'a\nX\n' > "$T/g_ours"; printf 'a\nY\n' > "$T/g_theirs"
python3 "$PM" --driver "$T/g_base" "$T/g_ours" "$T/g_theirs" 5 f.md; drc=$?
ok "driver mode on plain (non-item) lines both sides rewrote: nothing lost, exit 0 (union of both rewrites)" "$([ $drc = 0 ] && grep -qx X "$T/g_ours" && grep -qx Y "$T/g_ours" && echo 1 || echo 0)"
# ===== real history replay (optional) =====
REAL="${OVN_REAL_IPTV_REPO:-$REAL_HOME_DIR/LocalProjects/iptv_apps}"
if [ -d "$REAL/.git" ] && git -C "$REAL" cat-file -e c7be7d3c2d9a1425f66b578b518f6a4de3536fea 2>/dev/null && git -C "$REAL" cat-file -e fb07d121d1500c72f5f8705e1f17e091e58d3f97 2>/dev/null; then
  git clone -q --no-checkout "$REAL" "$T/real" 2>/dev/null && ( cd "$T/real"
    git checkout -q --detach fb07d121d1500c72f5f8705e1f17e091e58d3f97
    OVN_PM_DEFER=1 git merge --no-commit c2204cc7d9af7eb440d91884ba88d3d83d4e8d32 >/dev/null 2>&1; echo $? > "$T/real_rc"
    git diff --name-only --diff-filter=U > "$T/real_unmerged"
    python3 "$PM" --resolve-index "$T/real" --tag real >/dev/null 2>&1; echo $? > "$T/real_res"
    git commit --no-edit -q -m merge 2>/dev/null
    git diff --quiet HEAD c7be7d3c2d9a1425f66b578b518f6a4de3536fea && echo 1 > "$T/real_tree" || echo 0 > "$T/real_tree" )
  ok "REAL history: fb07d121d1 + c2204cc7d9 conflicts on exactly OVERNIGHT_PROGRESS.md" "$([ "$(cat "$T/real_rc")" != 0 ] && [ "$(cat "$T/real_unmerged")" = "OVERNIGHT_PROGRESS.md" ] && echo 1 || echo 0)"
  ok "REAL history: resolver resolves it" "$([ "$(cat "$T/real_res")" = 0 ] && echo 1 || echo 0)"
  ok "REAL history: the merged TREE equals the hand resolution c7be7d3c (every file, byte for byte)" "$(cat "$T/real_tree")"
else
  echo "  SKIP real-history replay (iptv_apps clone with c7be7d3c / fb07d121d1 not found; set OVN_REAL_IPTV_REPO)"
fi

echo "  test_progress_merge_git.sh: $pass passed, $fail failed"
[ "$fail" = 0 ]
