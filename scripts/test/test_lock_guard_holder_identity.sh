#!/usr/bin/env bash
# Regression test for lock_guard.sh's orphan-detection fix (2026-09-09).
#
# Real incident: two ~10min fleet stalls in one night (00:22-00:32, 06:33-06:43) from an orphaned
# run.lock, and lock_guard.sh's OWN log was empty through both - it never actually intervened. Root
# cause: it checked `pgrep -f run_overnight.sh` GLOBALLY (does that process name exist ANYWHERE),
# not whether the ACTUAL HOLDER of the lock (per `fuser`) is a legitimate one. Under systemd
# Restart=always crash-looping (each fresh instance dies near-instantly on the lock check, a new one
# spawns 20s later), some run_overnight.sh-named process is ALWAYS alive at nearly any instant even
# though none of them can ever acquire the lock - so the guard was blind to exactly the failure shape
# it exists to catch. Fixed to check the identity of the specific PID(s) fuser reports.
#
# This test proves both directions with REAL processes (not mocks) since the bug is specifically
# about process-identity confusion that a pure-logic mirror could hide:
#   A) a decoy process named run_overnight.sh exists elsewhere, but the ACTUAL lock holder is an
#      unrelated orphan -> the orphan must be killed (this is the bug fix).
#   B) the actual lock holder genuinely IS run_overnight.sh -> it must NOT be killed (no regression).
set -uo pipefail
LG="${OVN_LOCK_GUARD:-$HOME/overnight-queue/lock_guard.sh}"
[ -f "$LG" ] || { echo "  SKIP: $LG not found on this host"; exit 0; }
P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

tmp="$(mktemp -d)"
# lock_guard.sh hardcodes `cd "$HOME/overnight-queue"; LOCK="state/run.lock"` (not overridable via
# env/args) - sandbox via $HOME (same technique as test_reconcile_branches.sh) so this test can
# NEVER touch the real production lock file, since the script would otherwise `kill -9` real PIDs.
export HOME="$tmp/home"
mkdir -p "$HOME/overnight-queue/state"
cp "$LG" "$HOME/overnight-queue/lock_guard.sh"
LOCKFILE="$HOME/overnight-queue/state/run.lock"
cleanup(){ pkill -9 -f "$tmp/" 2>/dev/null; rm -rf "$tmp"; }
trap cleanup EXIT

# a real script literally named run_overnight.sh (NOT a renamed coreutils multi-call binary, which
# dispatches on argv[0] and breaks under a rename) so a process's `ps -o cmd=` contains that exact
# string, purely by virtue of its own script path - mirrors the real crash-loop decoy.
printf '#!/usr/bin/env bash\nsleep "$1"\n' > "$tmp/run_overnight.sh"; chmod +x "$tmp/run_overnight.sh"

# ---- scenario A: decoy run_overnight.sh alive elsewhere; the ACTUAL holder is an unrelated orphan ----
"$tmp/run_overnight.sh" 300 & decoy_pid=$!
bash -c "exec 200>\"$LOCKFILE\"; flock -n 200 && sleep 300" & orphan_pid=$!
sleep 0.3
( cd "$HOME/overnight-queue" && bash lock_guard.sh >/dev/null 2>&1 )
sleep 0.5
ok "scenario A: the actual orphan HOLDER is killed despite a same-named decoy existing elsewhere" \
   "! kill -0 $orphan_pid 2>/dev/null"
ok "scenario A: the unrelated decoy run_overnight.sh process is left alone" \
   "kill -0 $decoy_pid 2>/dev/null"
kill -9 "$decoy_pid" "$orphan_pid" 2>/dev/null
rm -f "$LOCKFILE"

# ---- scenario B: the actual lock holder genuinely IS run_overnight.sh -> must NOT be killed ----
bash -c "exec 200>\"$LOCKFILE\"; flock -n 200 && exec \"$tmp/run_overnight.sh\" 300" & legit_pid=$!
sleep 0.3
( cd "$HOME/overnight-queue" && bash lock_guard.sh >/dev/null 2>&1 )
sleep 0.5
ok "scenario B: a genuinely legitimate run_overnight.sh holder is NOT killed" \
   "kill -0 $legit_pid 2>/dev/null"
kill -9 "$legit_pid" 2>/dev/null

echo "Lock-guard holder identity: $P passed, $F failed"
[ "$F" -eq 0 ]
