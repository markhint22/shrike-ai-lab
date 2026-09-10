#!/usr/bin/env bash
# Regression test: ovn_park_sweep.sh (the WRAPPER, not the .py logic — see test_park_sweep.sh
# for that) must hold/release the repo correctly around the sweep, only commit+push when the
# python helper actually moved something (never an empty/no-op commit), survive a repo whose
# git sync fails (skip cleanly, still release the hold), and recover from a push race via its
# pull-rebase-then-push fallback (2026-09-10).
set -uo pipefail
REAL="$HOME/overnight-queue"
SH="$REAL/ovn_park_sweep.sh"
[ -f "$SH" ] || { echo "  SKIP: $SH not found on this host"; exit 0; }
P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

tmp="$(mktemp -d)"
SANDBOX_HOME="$tmp/home"
OQ="$SANDBOX_HOME/overnight-queue"
mkdir -p "$OQ/repos" "$OQ/state" "$OQ/logs"
cp "$REAL/queue.sh" "$OQ/queue.sh"
cp "$REAL/ovn_park_sweep.py" "$OQ/ovn_park_sweep.py"
chmod +x "$OQ/queue.sh"

run_sweep(){ # $1... = repo names as positional args (bypasses tasks.json)
  HOME="$SANDBOX_HOME" bash "$SH" "$@" 2>&1
}

# --- helper: a bare "origin" remote with an initial commit on overnight/feature ---
new_origin(){ # $1=name $2=progress-file-content
  local o="$tmp/origin_$1.git"
  git init -q --bare "$o"
  local w; w="$(mktemp -d)"
  ( cd "$w" && git init -q -b overnight/feature \
      && git config user.email t@t.com && git config user.name t \
      && printf '%s' "$2" > OVERNIGHT_PROGRESS.md \
      && git add -A && git commit -q -m init \
      && git remote add origin "$o" && git push -q origin overnight/feature )
  git --git-dir="$o" symbolic-ref HEAD refs/heads/overnight/feature
  rm -rf "$w"
  echo "$o"
}

clone_into_repos(){ # $1=repo-name $2=origin-path
  git clone -q "$2" "$OQ/repos/$1"
  # the real box has a global git identity configured; set one locally here so the fallback
  # `git pull --rebase` path (which, unlike the wrapper's own commit, sets no -c user.*) works
  # the same way it does in production instead of failing on an unrelated sandbox artifact.
  ( cd "$OQ/repos/$1" && git checkout -q overnight/feature && git config user.email t@t.com && git config user.name t )
}

PARKABLE=$'# Progress\n\n- [ ] [AUTO-SKIP after 5 no-op cycles — review] [T1] foo.py — thing. VERIFY: pytest -q\n- [ ] [T2] baz.py — real work. VERIFY: pytest -q\n'
CLEAN=$'# Progress\n\n- [ ] [T2] baz.py — real work. VERIFY: pytest -q\n- [x] [T1] done.py — already landed.\n'

# === A: healthy path — real parked item present -> holds, syncs, sweeps, commits, pushes, releases ===
oA="$(new_origin A "$PARKABLE")"
clone_into_repos repoA "$oA"
outA="$(run_sweep repoA)"
ok "A: logs a successful sweep of 1 item" "printf '%s' \"$outA\" | grep -q 'repoA: swept 1 parked item'"
ok "A: hold released after run (no leftover HOLD file)" "[ ! -f '$OQ/state/HOLD_repoA' ]"
ok "A: origin gained exactly one new commit (the sweep commit)" \
   "[ \"\$(git --git-dir='$oA' log --oneline overnight/feature | wc -l)\" -eq 2 ]"
ok "A: pushed commit message matches the wrapper's own template" \
   "git --git-dir='$oA' log -1 --format=%s overnight/feature | grep -q 'sweep 1 parked'"
ok "A: the parked item actually moved below the Parked header on origin's tip" \
   "git --git-dir='$oA' show overnight/feature:OVERNIGHT_PROGRESS.md | grep -q '^### Parked'"

# === B: nothing to sweep -> NO commit is created (only real changes get committed) ===
oB="$(new_origin B "$CLEAN")"
clone_into_repos repoB "$oB"
outB="$(run_sweep repoB)"
ok "B: logs nothing-to-sweep" "printf '%s' \"$outB\" | grep -q 'repoB: nothing to sweep'"
ok "B: origin has NO new commit (still just the init commit)" \
   "[ \"\$(git --git-dir='$oB' log --oneline overnight/feature | wc -l)\" -eq 1 ]"
ok "B: hold released after a no-op run too" "[ ! -f '$OQ/state/HOLD_repoB' ]"

# === C: git sync fails (broken remote / mid-conflict repo) -> skip cleanly, release hold, don't crash ===
oC="$(new_origin C "$PARKABLE")"
clone_into_repos repoC "$oC"
( cd "$OQ/repos/repoC" && git remote set-url origin "$tmp/does-not-exist.git" )
outC="$(run_sweep repoC)"
ok "C: logs a git-sync-failed skip" "printf '%s' \"$outC\" | grep -q 'repoC: git sync failed'"
ok "C: hold is released even though sync failed (not left stuck)" "[ ! -f '$OQ/state/HOLD_repoC' ]"
ok "C: file was never touched (sweep never ran)" \
   "! grep -q '^### Parked' '$OQ/repos/repoC/OVERNIGHT_PROGRESS.md'"
outC2="$(run_sweep repoC repoD_missing)"
ok "C: does not abort the whole pass — a healthy repo queued after it still runs" \
   "printf '%s' \"$outC2\" | grep -q 'no progress file, skipping'"

# === D: push race — origin moves between our reset and our push; wrapper must pull --rebase & retry ===
oD="$(new_origin D "$PARKABLE")"
clone_into_repos repoD "$oD"
hook="$oD/hooks/pre-receive"
cat > "$hook" <<'HOOK_EOF'
#!/usr/bin/env bash
# Reject exactly once, and while rejecting, simulate a concurrent push landing on the branch
# (via plumbing so no working tree is needed) so the client's retry has something to rebase onto.
BARE="$(cd "$(dirname "$0")/.." && pwd)"
# git's pre-receive hook runs inside an object "quarantine" that forbids ref writes; drop the
# quarantine env vars for our own plumbing calls so we can simulate a genuine concurrent commit.
NOQ="env -u GIT_QUARANTINE_PATH -u GIT_OBJECT_DIRECTORY -u GIT_ALTERNATE_OBJECT_DIRECTORIES"
if [ ! -f "$BARE/.raced_once" ]; then
  touch "$BARE/.raced_once"
  cur="$($NOQ git --git-dir="$BARE" rev-parse refs/heads/overnight/feature)"
  blob="$(printf 'raced-in-by-someone-else\n' | $NOQ git --git-dir="$BARE" hash-object -w --stdin)"
  export GIT_INDEX_FILE="$BARE/.race_index"
  $NOQ git --git-dir="$BARE" read-tree "$cur"
  $NOQ git --git-dir="$BARE" update-index --add --cacheinfo 100644,"$blob",RACE_FILE.txt
  newtree="$($NOQ git --git-dir="$BARE" write-tree)"
  rm -f "$GIT_INDEX_FILE"
  newcommit="$(printf 'concurrent push landed first\n' | GIT_AUTHOR_NAME=racer GIT_AUTHOR_EMAIL=racer@t.com GIT_COMMITTER_NAME=racer GIT_COMMITTER_EMAIL=racer@t.com $NOQ git --git-dir="$BARE" commit-tree "$newtree" -p "$cur")"
  $NOQ git --git-dir="$BARE" update-ref refs/heads/overnight/feature "$newcommit"
  echo "! [rejected] simulated non-fast-forward race" >&2
  exit 1
fi
exit 0
HOOK_EOF
chmod +x "$hook"
outD="$(run_sweep repoD)"
ok "D: still logs a successful sweep after the race (fallback worked)" \
   "printf '%s' \"$outD\" | grep -q 'repoD: swept 1 parked item'"
ok "D: origin has BOTH the raced-in commit and our rebased sweep commit" \
   "git --git-dir='$oD' log --oneline overnight/feature | wc -l | grep -qE '^[[:space:]]*3$'"
ok "D: the concurrent file from the race survived the rebase (nothing clobbered)" \
   "git --git-dir='$oD' show overnight/feature:RACE_FILE.txt | grep -q raced-in-by-someone-else"
ok "D: our sweep commit is still present after the retry" \
   "git --git-dir='$oD' log --oneline overnight/feature | grep -q 'sweep 1 parked'"
ok "D: hold released after the race-recovery path too" "[ ! -f '$OQ/state/HOLD_repoD' ]"

rm -rf "$tmp"
echo "Park sweep wrapper: $P passed, $F failed"
[ "$F" -eq 0 ]
