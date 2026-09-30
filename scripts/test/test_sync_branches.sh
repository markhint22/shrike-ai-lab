#!/usr/bin/env bash
# Regression tests for sync_branches.sh: the main -> develop release BACK-MERGE (keeps develop a superset of main).
# Hermetic: HOME is a temp dir (the script does `cd $HOME/overnight-queue`), every repo is a clone of a throwaway bare
# origin in the temp dir, and curl is an exported shell function (the script prepends /usr/bin to PATH, so a PATH stub
# would lose to the real curl; an exported function wins) - nothing touches the network or any real repo.
# Covered: default-list/unknown-dir handling, non-git skip, fetch failure, missing main/develop, in-sync (equal and
# develop-ahead), DRY_RUN, successful back-merge (+N count, merge message, worktree cleanup, origin updated), idempotency,
# conflict (alert + untouched develop + worktree cleanup), push failure, worktree-add failure, multiple repos in one run,
# NTFY_TOPIC default/override, and the local-clone-has-develop-checked-out scenario.
# Lines tagged KNOWN-BUG are non-fatal warnings documenting real defects in the script (correct behaviour asserted).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
S="$HERE/../../sync_branches.sh"; [ -f "$S" ] || S="$HERE/../sync_branches.sh"; [ -f "$S" ] || S="$HERE/sync_branches.sh"
[ -f "$S" ] || { echo "sync_branches.sh not found"; exit 1; }
pass=0; fail=0; warn=0
ok(){ if [ "$2" = "1" ]; then pass=$((pass+1)); echo "  ok   $1"; else fail=$((fail+1)); echo "  FAIL $1"; fi; }
kb(){ if [ "$2" = "1" ]; then pass=$((pass+1)); echo "  ok   KNOWN-BUG (now fixed): $1"; else warn=$((warn+1)); echo "  WARN KNOWN-BUG: $1"; fi; }
T="$(mktemp -d)"; PFX="sbt$$"
trap 'rm -rf "$T" /tmp/sync-${PFX}*' EXIT
export GIT_CONFIG_GLOBAL="$T/gitconfig"; printf '[user]\n\temail = t@t\n\tname = t\n[init]\n\tdefaultBranch = main\n' > "$GIT_CONFIG_GLOBAL"
export GIT_CONFIG_NOSYSTEM=1
H="$T/home"; Q="$H/overnight-queue"; mkdir -p "$Q/repos"
export NTFY_LOG="$T/ntfy.log"
curl(){ echo "CURL $*" >> "$NTFY_LOG"; return 0; }; export -f curl
unset NTFY_TOPIC DRY_RUN
run(){ ( cd "$T" && HOME="$H" bash "$S" "$@" 2>&1 ); }
O(){ echo "$T/o/$1.git"; }
# mk <name>: bare origin + clone under repos/, with main and develop (same commit); clone sits on claude/feature
mk(){ local n="$1"; mkdir -p "$T/o"; git init -q --bare "$(O "$n")"; git clone -q "$(O "$n")" "$Q/repos/$n" 2>/dev/null
  ( cd "$Q/repos/$n"; git checkout -q -b main; echo base > f.txt; git add -A; git commit -q -m base; git push -q origin main
    git branch develop; git push -q origin develop; git checkout -q -b claude/feature ) >/dev/null 2>&1
  git clone -q "$(O "$n")" "$T/p-$n" 2>/dev/null; }
# adv <name> <branch> <file> <content> <msg>: commit to origin/<branch> via the pusher clone
adv(){ ( cd "$T/p-$1"; git fetch -q origin; git checkout -q -B "$2" "origin/$2"; printf '%s\n' "$4" > "$3"; git add -A; git commit -q -m "$5"; git push -q origin "$2" ) >/dev/null 2>&1; }
ahead(){ git -C "$(O "$1")" rev-list --count "$2..$3"; }   # commits in $3 not in $2
sha(){ git -C "$(O "$1")" rev-parse "$2"; }
leaks(){ ls -d /tmp/sync-${PFX}* 2>/dev/null | wc -l | tr -d ' '; }

# ---- 1. environment handling ----
out="$(run)"; rc=$?
ok "default repo list with nothing on disk: exit 0, only the completion line" "$([ $rc = 0 ] && [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = 1 ] && printf '%s' "$out" | grep -q 'sync_branches complete (reconciled: none)' && echo 1 || echo 0)"
out="$(cd "$T" && HOME="$T/nohome" bash "$S" 2>&1)"; rc=$?
ok "missing \$HOME/overnight-queue -> exit 1 before doing anything" "$([ $rc = 1 ] && echo 1 || echo 0)"
mkdir -p "$Q/repos/${PFX}notgit"
out="$(run "repos/${PFX}notgit" repos/${PFX}nonexistent)"
ok "non-git dir / nonexistent path are skipped silently" "$(! printf '%s' "$out" | grep -q "${PFX}" && printf '%s' "$out" | grep -q 'complete (reconciled: none)' && echo 1 || echo 0)"

# ---- 2. precondition skips ----
n="${PFX}nofetch"; mk "$n"; git -C "$Q/repos/$n" remote set-url origin "$T/o/does-not-exist.git"
out="$(run "repos/$n")"
ok "fetch failure is logged and skipped" "$(printf '%s' "$out" | grep -q "$n: fetch failed" && echo 1 || echo 0)"
n="${PFX}nomain"; mkdir -p "$T/o"; git init -q --bare "$(O $n)"; git clone -q "$(O $n)" "$Q/repos/$n" 2>/dev/null
( cd "$Q/repos/$n"; git checkout -q -b develop; echo x > f; git add -A; git commit -q -m x; git push -q origin develop ) >/dev/null 2>&1
out="$(run "repos/$n")"
ok "origin without main -> 'no main', skipped" "$(printf '%s' "$out" | grep -q "$n: no main" && echo 1 || echo 0)"
n="${PFX}nodev"; mkdir -p "$T/o"; git init -q --bare "$(O $n)"; git clone -q "$(O $n)" "$Q/repos/$n" 2>/dev/null
( cd "$Q/repos/$n"; git checkout -q -b main; echo x > f; git add -A; git commit -q -m x; git push -q origin main ) >/dev/null 2>&1
out="$(run "repos/$n")"
ok "origin without develop -> 'no develop', skipped" "$(printf '%s' "$out" | grep -q "$n: no develop" && echo 1 || echo 0)"

# ---- 3. already in sync ----
n="${PFX}sync"; mk "$n"; b="$(sha $n develop)"
out="$(run "repos/$n")"
ok "develop == main -> 'in sync', origin untouched" "$(printf '%s' "$out" | grep -q "$n: develop already contains main (in sync)" && [ "$(sha $n develop)" = "$b" ] && echo 1 || echo 0)"
adv "$n" develop d.txt d "feat: develop only"; b="$(sha $n develop)"
out="$(run "repos/$n")"
ok "develop ahead of main -> still 'in sync' (no merge)" "$(printf '%s' "$out" | grep -q 'in sync' && [ "$(sha $n develop)" = "$b" ] && echo 1 || echo 0)"

# ---- 4. dry run ----
n="${PFX}dry"; mk "$n"; adv "$n" main m1.txt m1 "hotfix 1"; adv "$n" main m2.txt m2 "hotfix 2"; b="$(sha $n develop)"
out="$(DRY_RUN=1 run "repos/$n")"
ok "DRY_RUN=1 reports the would-merge with the commit count (+2)" "$(printf '%s' "$out" | grep -q "$n: \[dry-run\] would back-merge main -> develop (+2)" && echo 1 || echo 0)"
ok "DRY_RUN=1 leaves origin/develop untouched, no worktree, no alert" "$([ "$(sha $n develop)" = "$b" ] && [ "$(git -C "$Q/repos/$n" worktree list | wc -l | tr -d ' ')" = 1 ] && [ ! -f "$NTFY_LOG" ] && echo 1 || echo 0)"

# ---- 5. real back-merge (same repo as the dry run: main is +2) ----
out="$(run "repos/$n")"
ok "back-merge succeeds and reports the +N count" "$(printf '%s' "$out" | grep -q "$n: back-merged main -> develop (+2)" && printf '%s' "$out" | grep -q 'reconciled)$\|reconciled$' && echo 1 || echo 0)"
ok "origin/develop now contains origin/main" "$([ "$(ahead $n develop main)" = 0 ] && echo 1 || echo 0)"
ok "origin/develop moved (a real --no-ff merge commit)" "$([ "$(sha $n develop)" != "$b" ] && [ "$(git -C "$(O $n)" rev-list --parents -n1 develop | wc -w | tr -d ' ')" = 3 ] && echo 1 || echo 0)"
ok "merge commit message is the conventional chore(sync) text with the count" "$(git -C "$(O $n)" log -1 --format=%s develop | grep -q '^chore(sync): back-merge main -> develop (+2: promote/hotfix reconcile)$' && echo 1 || echo 0)"
ok "both hotfix files reached develop" "$(git -C "$(O $n)" cat-file -e develop:m1.txt 2>/dev/null && git -C "$(O $n)" cat-file -e develop:m2.txt 2>/dev/null && echo 1 || echo 0)"
ok "temporary worktree removed (repo lists only its main worktree)" "$([ "$(git -C "$Q/repos/$n" worktree list | wc -l | tr -d ' ')" = 1 ] && [ "$(leaks)" = 0 ] && echo 1 || echo 0)"
ok "final summary names the reconciled repo" "$(printf '%s' "$out" | grep -q "sync_branches complete (reconciled: $n)" && echo 1 || echo 0)"
ok "no ntfy alert on a clean back-merge" "$([ ! -f "$NTFY_LOG" ] && echo 1 || echo 0)"
b="$(sha $n develop)"; out="$(run "repos/$n")"
ok "idempotent: second run is 'in sync' and origin/develop does not move" "$(printf '%s' "$out" | grep -q 'in sync' && [ "$(sha $n develop)" = "$b" ] && echo 1 || echo 0)"
ok "main itself is never modified by the script" "$([ "$(ahead $n main develop)" -gt 0 ] && [ "$(ahead $n develop main)" = 0 ] && echo 1 || echo 0)"

# ---- 6. conflict ----
n="${PFX}conf"; mk "$n"; adv "$n" main f.txt "main-side edit" "hotfix on main"; adv "$n" develop f.txt "develop-side edit" "feat on develop"; b="$(sha $n develop)"
out="$(run "repos/$n")"
ok "conflicting back-merge logged as needing a human" "$(printf '%s' "$out" | grep -q "$n: CONFLICT back-merging main -> develop — needs a human" && echo 1 || echo 0)"
ok "conflict leaves origin/develop untouched and reports reconciled: none" "$([ "$(sha $n develop)" = "$b" ] && printf '%s' "$out" | grep -q 'reconciled: none' && echo 1 || echo 0)"
ok "conflict: worktree removed, no leaked temp dir, merge aborted" "$([ "$(git -C "$Q/repos/$n" worktree list | wc -l | tr -d ' ')" = 1 ] && [ "$(leaks)" = 0 ] && echo 1 || echo 0)"
ok "conflict: ntfy alert posted to the default topic with high priority" "$(grep -q 'https://ntfy.sh/shrike_ovn_311380987a' "$NTFY_LOG" && grep -q 'Priority: high' "$NTFY_LOG" && grep -q 'Title: Branch back-merge conflict' "$NTFY_LOG" && echo 1 || echo 0)"
ok "conflict alert names the repo and uses --max-time 8" "$(grep -q "needs a human): $n\." "$NTFY_LOG" && grep -q -- '--max-time 8' "$NTFY_LOG" && echo 1 || echo 0)"
rm -f "$NTFY_LOG"; out="$(NTFY_TOPIC=my_topic run "repos/$n")"
ok "NTFY_TOPIC override is honoured in the alert URL" "$(grep -q 'https://ntfy.sh/my_topic' "$NTFY_LOG" && ! grep -q shrike_ovn "$NTFY_LOG" && echo 1 || echo 0)"
ok "conflict persists across runs (still flagged, still untouched)" "$(printf '%s' "$out" | grep -q CONFLICT && [ "$(sha $n develop)" = "$b" ] && echo 1 || echo 0)"

# ---- 7. push rejected by origin ----
n="${PFX}nopush"; mk "$n"; adv "$n" main m.txt m "hotfix"; b="$(sha $n develop)"
mkdir -p "$(O $n)/hooks"; printf '#!/bin/sh\nwhile read o n r; do [ "$r" = refs/heads/develop ] && exit 1; done; exit 0\n' > "$(O $n)/hooks/pre-receive"; chmod +x "$(O $n)/hooks/pre-receive"
rm -f "$NTFY_LOG"; out="$(run "repos/$n")"
ok "push rejection logged as FAILED and not counted as reconciled" "$(printf '%s' "$out" | grep -q "$n: push to develop FAILED" && printf '%s' "$out" | grep -q 'reconciled: none' && echo 1 || echo 0)"
ok "push failure: origin/develop unchanged, worktree cleaned" "$([ "$(sha $n develop)" = "$b" ] && [ "$(git -C "$Q/repos/$n" worktree list | wc -l | tr -d ' ')" = 1 ] && echo 1 || echo 0)"
ok "push failure does not fire the conflict alert" "$([ ! -f "$NTFY_LOG" ] && echo 1 || echo 0)"

# ---- 8. worktree creation fails ----
n="${PFX}nowt"; mk "$n"; adv "$n" main m.txt m "hotfix"; b="$(sha $n develop)"
git -C "$Q/repos/$n" fetch -q origin; rm -rf "$Q/repos/$n/.git/worktrees"; : > "$Q/repos/$n/.git/worktrees"
out="$(run "repos/$n")"
ok "worktree add failure logged and skipped (develop untouched)" "$(printf '%s' "$out" | grep -q "$n: worktree add failed" && [ "$(sha $n develop)" = "$b" ] && echo 1 || echo 0)"
kb "worktree-add-failed path leaks the mktemp dir /tmp/sync-<repo>.XXXX (continue skips cleanup; sync_branches.sh:36-37)" "$([ "$(leaks)" = 0 ] && echo 1 || echo 0)"
rm -f "$Q/repos/$n/.git/worktrees"; rm -rf /tmp/sync-${PFX}nowt.*

# ---- 9. several repos in one run: one good, one conflicted, one in sync ----
g="${PFX}multi_ok"; c="${PFX}multi_cf"; s="${PFX}multi_sy"; mk "$g"; mk "$c"; mk "$s"
adv "$g" main m.txt m "hotfix"; adv "$c" main f.txt A "m"; adv "$c" develop f.txt B "d"; rm -f "$NTFY_LOG"
out="$(run "repos/$g" "repos/$c" "repos/$s")"
ok "multi-repo: good one reconciled, conflict flagged, in-sync one skipped - all in one pass" "$(printf '%s' "$out" | grep -q "$g: back-merged" && printf '%s' "$out" | grep -q "$c: CONFLICT" && printf '%s' "$out" | grep -q "$s: develop already contains" && echo 1 || echo 0)"
ok "multi-repo: summary lists only the reconciled repo; alert names only the conflicted one" "$(printf '%s' "$out" | grep -q "reconciled: $g)" && grep -q "needs a human): $c\." "$NTFY_LOG" && ! grep -q "$g" "$NTFY_LOG" && echo 1 || echo 0)"
ok "multi-repo: exactly one alert for the whole run" "$([ "$(grep -c '^CURL' "$NTFY_LOG")" = 1 ] && echo 1 || echo 0)"
g2="${PFX}multi_ok2"; mk "$g2"; adv "$g2" main m.txt m "hotfix"
out="$(run "repos/$g" "repos/$g2")"
ok "a second real back-merge is listed alongside (space-separated) in the summary" "$(printf '%s' "$out" | grep -q "reconciled: $g2)" && echo 1 || echo 0)"

# ---- 10. local clone has develop checked out ----
n="${PFX}codev"; mk "$n"; adv "$n" main m.txt m "hotfix"
( cd "$Q/repos/$n"; git fetch -q origin; git checkout -q -B develop origin/develop ) >/dev/null 2>&1
out="$(run "repos/$n")"
ok "local develop checked out: run completes without crashing" "$(printf '%s' "$out" | grep -q 'sync_branches complete' && echo 1 || echo 0)"
kb "when the clone has develop checked out, 'checkout -B develop' in the worktree fails silently, the merge lands on a detached HEAD and 'push origin develop' pushes the clone's stale local develop (sync_branches.sh:38-40): origin/develop must contain main" "$([ "$(ahead $n develop main)" = 0 ] && echo 1 || echo 0)"
kb "...and the log must not claim 'reconciled' when origin/develop did not move" "$(! { printf '%s' "$out" | grep -q "$n: back-merged" && [ "$(ahead $n develop main)" != 0 ]; } && echo 1 || echo 0)"

echo "  $pass passed, $fail failed, $warn known-bug warning(s)"; [ "$fail" = 0 ]
