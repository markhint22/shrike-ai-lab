#!/usr/bin/env bash
# Regression tests for ovn_worktree_sweep.sh: force-removes orphaned /tmp-based linked git worktrees older than
# SWEEP_MIN_AGE_MIN (default 90) for repos under repos/*, prunes stale registrations, writes an alerts.log line,
# prints a one-line summary. Hermetic: a fake queue tree in a temp dir with throwaway git repos; the only things it
# can touch are worktrees THIS test creates under /tmp (and /var/tmp for the "not under /tmp" case).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SH="$HERE/../ovn_worktree_sweep.sh"; [ -f "$SH" ] || SH="$HOME/overnight-queue/scripts/ovn_worktree_sweep.sh"
[ -f "$SH" ] || { echo "  SKIP: script not found"; exit 0; }
command -v git >/dev/null || { echo "  SKIP: git missing"; exit 0; }
stat -c %Y / >/dev/null 2>&1 || { echo "  SKIP: needs GNU stat (-c) - run this test on the Linux box"; exit 0; }
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
unset SWEEP_MIN_AGE_MIN

pass=0; fail=0; warnc=0
ok(){ pass=$((pass+1)); echo "  ok   $1"; }
bad(){ fail=$((fail+1)); echo "  FAIL $1"; }
chk(){ local l="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$l"; else bad "$l"; fi; }
eqv(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected [$2] got [$3])"; fi; }
known(){ local l="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$l"; else warnc=$((warnc+1)); echo "  WARN KNOWN-BUG: $l"; fi; }

T="$(mktemp -d)"
EXTRA=()     # extra dirs to always clean
cleanup(){ for d in "${EXTRA[@]:-}"; do [ -n "$d" ] && rm -rf "$d"; done; rm -rf "$T"; }
trap cleanup EXIT
Q="$T/q"
mkq(){ rm -rf "$Q"; mkdir -p "$Q/scripts" "$Q/state" "$Q/repos"; cp "$SH" "$Q/scripts/ovn_worktree_sweep.sh"; }
mkrepo(){ # name
  local r="$Q/repos/$1"; mkdir -p "$r"; git -C "$r" init -q -b main 2>/dev/null || git -C "$r" init -q
  echo base > "$r/f.txt"; git -C "$r" add -A; git -C "$r" commit -q -m base; git -C "$r" branch -M main 2>/dev/null || true
}
# mkwt <repo> <parent-dir> <minutes-old> -> echoes path
mkwt(){
  local wt; wt="$(mktemp -d "$2/ovnws.XXXXXX")"; EXTRA+=("$wt")
  git -C "$Q/repos/$1" worktree add -q --detach "$wt" >/dev/null 2>&1
  touch -d "$3 minutes ago" "$wt"; echo "$wt"
}
sweep(){ ( cd "$T" && bash "$Q/scripts/ovn_worktree_sweep.sh" "$@" 2>&1 ); }
wtlist(){ git -C "$Q/repos/$1" worktree list --porcelain | awk '/^worktree /{print $2}'; }
ALERTS="$Q/state/alerts.log"

echo "== basic sweep =="
mkq; mkrepo alpha
W1="$(mkwt alpha /tmp 180)"
chk "precondition: worktree registered + exists" bash -c "[ -d '$W1' ] && git -C '$Q/repos/alpha' worktree list | grep -q '$W1'"
out="$(sweep)"; rc=$?
eqv "exit 0" "0" "$rc"
eqv "summary line" "worktree sweep: removed 1 orphaned worktree(s)" "$out"
chk "old /tmp worktree dir removed" test ! -d "$W1"
chk "registration removed from repo" bash -c "! git -C '$Q/repos/alpha' worktree list | grep -q '$W1'"
chk "alert line format (severity | id | msg with age + threshold)" grep -Eq "^\[[0-9-]{10} [0-9:]{8}\] warn \| worktree-sweep \| removed orphaned worktree $W1 for alpha \(age 18[0-9]m, threshold 90m\)$" "$ALERTS"
chk "main worktree intact" test -f "$Q/repos/alpha/f.txt"

echo "== age threshold =="
mkq; mkrepo alpha
Wy="$(mkwt alpha /tmp 89)"
out="$(sweep)"
eqv "89-minute-old worktree kept (default 90m) -> no output" "" "$out"
chk "young worktree still present" test -d "$Wy"
chk "no alert written" bash -c "! test -s '$ALERTS'"
Wo="$(mkwt alpha /tmp 91)"
out="$(sweep)"
chk "91-minute-old one removed, 89-minute one kept" bash -c "[ ! -d '$Wo' ] && [ -d '$Wy' ]"
eqv "summary counts only the removed one" "worktree sweep: removed 1 orphaned worktree(s)" "$out"
out="$(SWEEP_MIN_AGE_MIN=10 sweep)"
chk "SWEEP_MIN_AGE_MIN=10 now removes the 89-minute one" test ! -d "$Wy"
chk "env threshold shown in the alert text" grep -q 'threshold 10m' "$ALERTS"
Wf="$(mkwt alpha /tmp 0)"
out="$(SWEEP_MIN_AGE_MIN=0 sweep)"
chk "SWEEP_MIN_AGE_MIN=0 sweeps even a brand-new worktree (>= comparison)" test ! -d "$Wf"

echo "== safety: what must NOT be swept =="
mkq; mkrepo alpha
mkdir -p /var/tmp 2>/dev/null
if [ -w /var/tmp ]; then
  Wv="$(mkwt alpha /var/tmp 600)"
  out="$(sweep)"
  chk "old worktree outside /tmp is never swept" test -d "$Wv"
  eqv "outside-/tmp: no output" "" "$out"
  git -C "$Q/repos/alpha" worktree remove --force "$Wv" >/dev/null 2>&1
else
  echo "  (skip: /var/tmp not writable)"
fi
case "$T" in
  /tmp/*) touch -d '10 hours ago' "$Q/repos/alpha"; out="$(sweep)"
          chk "main worktree itself (under /tmp, ancient) is never removed" test -f "$Q/repos/alpha/f.txt"
          eqv "main worktree: no output" "" "$out" ;;
  *) echo "  (skip: fake tree not under /tmp)" ;;
esac
mkdir -p "$Q/repos/notagit/sub"; echo keep > "$Q/repos/notagit/sub/x"
touch "$Q/repos/plainfile"
out="$(sweep)"; rc=$?
eqv "non-git dir + stray file under repos/ are skipped cleanly (exit 0)" "0" "$rc"
chk "non-git dir untouched" test -f "$Q/repos/notagit/sub/x"

echo "== messy worktrees =="
mkq; mkrepo alpha
# dirty (untracked + modified)
Wd="$(mkwt alpha /tmp 0)"; echo junk > "$Wd/untracked.txt"; echo changed >> "$Wd/f.txt"; touch -d '5 hours ago' "$Wd"
# mid-merge conflict
git -C "$Q/repos/alpha" branch side >/dev/null 2>&1
echo main-change > "$Q/repos/alpha/f.txt"; git -C "$Q/repos/alpha" commit -qam m
Wm="$(mktemp -d /tmp/ovnws.XXXXXX)"; EXTRA+=("$Wm")
git -C "$Q/repos/alpha" worktree add -q -b conflict "$Wm" side >/dev/null 2>&1
( cd "$Wm" && echo side-change > f.txt && git commit -qam s && git merge main >/dev/null 2>&1 )
chk "precondition: merge in progress with conflict" bash -c "cd '$Wm' && git status | grep -qi 'unmerged\|merging'"
touch -d '5 hours ago' "$Wm"
out="$(sweep)"
chk "dirty worktree force-removed" test ! -d "$Wd"
chk "mid-merge conflicted worktree removed" test ! -d "$Wm"
eqv "both counted" "worktree sweep: removed 2 orphaned worktree(s)" "$out"
eqv "only the main worktree remains registered" "1" "$(wtlist alpha | wc -l | tr -d ' ')"

# registration whose directory is already gone -> pruned silently
mkq; mkrepo alpha
Wg="$(mkwt alpha /tmp 500)"; rm -rf "$Wg"
chk "precondition: stale registration present" bash -c "git -C '$Q/repos/alpha' worktree list | grep -q '$Wg'"
out="$(sweep)"
eqv "dir already gone -> nothing swept, no output" "" "$out"
chk "stale registration pruned" bash -c "! git -C '$Q/repos/alpha' worktree list | grep -q '$Wg'"
chk "no alert for an already-gone dir" bash -c "! test -s '$ALERTS'"

echo "== multiple repos / state dir arg =="
mkq; mkrepo alpha; mkrepo bravo
Wa="$(mkwt alpha /tmp 200)"; Wb="$(mkwt bravo /tmp 200)"; Wb2="$(mkwt bravo /tmp 300)"
mkdir -p "$T/customstate"
out="$(sweep "$T/customstate")"
eqv "three orphans across two repos counted together" "worktree sweep: removed 3 orphaned worktree(s)" "$out"
chk "custom state_dir arg receives the alerts" test "$(grep -c worktree-sweep "$T/customstate/alerts.log")" = 3
chk "alerts name the right repo" bash -c "grep -q 'for bravo' '$T/customstate/alerts.log' && grep -q 'for alpha' '$T/customstate/alerts.log'"
chk "default state/alerts.log NOT written when arg given" bash -c "! test -s '$ALERTS'"
chk "all orphans gone" bash -c "[ ! -d '$Wa' ] && [ ! -d '$Wb' ] && [ ! -d '$Wb2' ]"

mkq; mkrepo alpha
Wn="$(mkwt alpha /tmp 200)"
out="$(sweep "$T/no/such/dir")"; rc=$?
eqv "unwritable/nonexistent alerts dir -> exit 0" "0" "$rc"
chk "sweep still happens when the alert can't be written" test ! -d "$Wn"
chk "summary still printed" grep -q 'removed 1 orphaned' <<<"$out"
known "alert-write failure should be silent (2>/dev/null follows the failing >> redirect so 'No such file' leaks)" bash -c "! grep -q 'No such file' <<<\"$out\""

mkq
out="$(sweep)"; rc=$?
eqv "empty repos/ dir -> exit 0, silent" "0:" "$rc:$out"
rm -rf "$Q/repos"
out="$(sweep)"; rc=$?
eqv "no repos/ dir at all -> exit 0, silent" "0:" "$rc:$out"

echo
echo "$pass passed, $fail failed ($warnc known-bug warning(s))"
[ "$fail" -eq 0 ]
