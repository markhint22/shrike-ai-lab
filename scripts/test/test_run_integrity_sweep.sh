#!/usr/bin/env bash
# test_run_integrity_sweep.sh - 2026-10-03, integrity track (A6). The park sweep and deploy_watch's enqueue_fix both `git reset --hard origin/overnight/feature`
# in the live clone; the hold they take only stops a NEW cycle, so a commit made but not yet pushed by a cycle in flight was discarded (xlite: "pushed" recorded
# for work origin never had). Both must now SKIP a repo whose cycle/stage runner is active. Each case has the incident (reset discards the commit when nothing is
# running = NEGATIVE control of the hazard) and the guarded behaviour; plus the benign cases (idle repo and stale marker are still swept / enqueued).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
Q="$(cd "$HERE/../.." && pwd)"
P=0; F=0
ok(){ if [ "$2" = 1 ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL $1"; fi; }
eq(){ if [ "$2" = "$3" ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL $1 (expected [$2] got [$3])"; fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"; [ -n "${SLP:-}" ] && kill "$SLP" 2>/dev/null' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0
export HOME="$T/home"; OQ="$HOME/overnight-queue"; mkdir -p "$OQ/scripts" "$OQ/state" "$OQ/repos" "$HOME/bin"
export PATH="$HOME/bin:$PATH"
cp "$Q/ovn_park_sweep.sh" "$Q/ovn_park_sweep.py" "$Q/ovn_park_unworkable.py" "$OQ/" 2>/dev/null
cp "$Q/scripts/lib_run_integrity.sh" "$Q/scripts/ovn_enqueue_emergency.py" "$OQ/scripts/"
printf '#!/bin/bash\necho "queue.sh $*" >> "$HOME/queue.calls"\nexit 0\n' > "$OQ/queue.sh"; chmod +x "$OQ/queue.sh"
printf '[{"id":"ongoing-r1","type":"aider_fix","repo":"%s/repos/r1","enabled":true}]\n' "$OQ" > "$OQ/tasks.json"

ORIGIN="$T/origin.git"
mk_repo(){   # fresh clone of origin on overnight/feature with ONE unpushed model commit "L" on top
  rm -rf "$ORIGIN" "$OQ/repos/r1" "$T/seed"; git init -q --bare -b main "$ORIGIN"
  git init -q -b overnight/feature "$T/seed"
  ( cd "$T/seed" && printf '# P\n\n## Next Steps\n- [ ] [T1] `a.py` do a thing\n' > OVERNIGHT_PROGRESS.md && echo 1 > a.py && git add -A && git commit -q -m base && git remote add origin "$ORIGIN" && git push -q origin overnight/feature )
  git clone -q -b overnight/feature "$ORIGIN" "$OQ/repos/r1" 2>/dev/null
  ( cd "$OQ/repos/r1" && echo 2 >> a.py && git add -A && git commit -q -m "model commit L (unpushed)" )
  LSHA="$(git -C "$OQ/repos/r1" rev-parse HEAD)"
}
head_of(){ git -C "$OQ/repos/r1" rev-parse HEAD; }
sweep(){ ( cd "$OQ" && bash ovn_park_sweep.sh r1 ) > "$T/sweep.out" 2>&1; }
( sleep 120 & echo $! > "$T/slp"; wait ) >/dev/null 2>&1 &
sleep 0.3; SLP="$(cat "$T/slp")"

# ---- A6 NEGATIVE control of the hazard: nothing is running => the sweep resets, the unpushed commit is gone (this is the incident)
mk_repo; rm -f "$OQ/state/cycle_active_r1"
sweep
ok "sweep idle repo: sweep runs (benign: an idle repo is still swept)" "$(grep -q 'nothing to sweep' "$T/sweep.out" && echo 1 || echo 0)"
ok "control: with no cycle running the reset really does discard the unpushed commit (the incident)" "$([ "$(head_of)" != "$LSHA" ] && echo 1 || echo 0)"

# ---- A6: a live cycle marker => skip, commit survives, no hold/reset
mk_repo; : > "$HOME/queue.calls"; printf '%s\n' "$SLP" > "$OQ/state/cycle_active_r1"
sweep
ok "sweep: cycle in flight => skipped with a log line" "$(grep -q 'in flight - skipping this pass' "$T/sweep.out" && echo 1 || echo 0)"
eq "sweep: the unpushed model commit SURVIVES" "$LSHA" "$(head_of)"
ok "sweep: no hold was taken on a skipped repo" "$(! grep -q 'hold r1' "$HOME/queue.calls" && echo 1 || echo 0)"
ok "sweep: other work in the same pass is not blocked (pass completes)" "$(grep -q 'ovn_park_sweep pass complete' "$T/sweep.out" && echo 1 || echo 0)"

# ---- stale marker (dead pid) must NOT freeze the repo
mk_repo; ( sleep 0.1 & echo $! > "$T/dead"; wait ) >/dev/null 2>&1; sleep 0.4; printf '%s\n' "$(cat "$T/dead")" > "$OQ/state/cycle_active_r1"
sweep
ok "sweep: dead-pid marker is ignored (benign control)" "$(grep -q 'nothing to sweep' "$T/sweep.out" && echo 1 || echo 0)"

# ---- stage runner for the repo (no marker) => skip too
mk_repo; rm -f "$OQ/state/cycle_active_r1"
mkdir -p "$T/sr"; printf '#!/bin/bash\nsleep 30\n' > "$T/sr/ovn_stage_runner.sh"
( bash "$T/sr/ovn_stage_runner.sh" r1 >/dev/null 2>&1 & echo $! > "$T/srp"; wait ) >/dev/null 2>&1 &
sleep 0.5
sweep
ok "sweep: a stage runner started for the repo => skipped" "$(grep -q 'in flight - skipping this pass' "$T/sweep.out" && echo 1 || echo 0)"
eq "sweep: ... commit survives" "$LSHA" "$(head_of)"
kill "$(cat "$T/srp")" 2>/dev/null; pkill -P "$(cat "$T/srp")" 2>/dev/null; sleep 0.3

# ---- lib missing => old behaviour (fail-safe): the sweep still works
mk_repo; mv "$OQ/scripts/lib_run_integrity.sh" "$OQ/scripts/lib.off"; printf '%s\n' "$SLP" > "$OQ/state/cycle_active_r1"
sweep
ok "sweep: lib missing => old behaviour, no crash (declare -F guard)" "$(grep -q 'ovn_park_sweep pass complete' "$T/sweep.out" && ! grep -q 'command not found' "$T/sweep.out" && echo 1 || echo 0)"
mv "$OQ/scripts/lib.off" "$OQ/scripts/lib_run_integrity.sh"; rm -f "$OQ/state/cycle_active_r1"

# ============================================================ deploy_watch enqueue_fix
# real function body, real remote script; ssh is a shim that runs the remote script locally
awk '/^enqueue_fix\(\)\{/{f=1} f{print} f&&/^}$/{exit}' "$Q/deploy_watch.sh" > "$T/enqueue_fix.sh"
ok "enqueue_fix extracted from the real deploy_watch.sh" "$([ "$(wc -l < "$T/enqueue_fix.sh")" -gt 10 ] && echo 1 || echo 0)"
cat > "$HOME/bin/ssh" <<'EOF'
#!/bin/bash
# shim: drop "-o X" pairs and the host, then run `env VAR=.. bash -s` locally with the script on stdin
while [ "$1" = "-o" ]; do shift 2; done
shift   # host
vars=(); while [ $# -gt 0 ] && [[ "$1" == *=* ]]; do vars+=("$1"); shift; done
exec env "${vars[@]}" bash -s
EOF
chmod +x "$HOME/bin/ssh"
( . "$T/enqueue_fix.sh"; SRV=fake ENQ_REMOTE=scripts/ovn_enqueue_emergency.py; export SRV ENQ_REMOTE
  # busy: live marker
  mk_repo; printf '%s\n' "$SLP" > "$OQ/state/cycle_active_r1"
  OVN_ENQ_BUSY_WAIT_SEC=0 enqueue_fix r1 svc1 "- [ ] [T4] EMERGENCY DEPLOY FIX test item"; echo "rc=$? busy=$ENQ_BUSY" > "$T/enq1"
  echo "head=$(git -C "$OQ/repos/r1" rev-parse HEAD)" >> "$T/enq1"; echo "head=$LSHA" > "$T/enq1.want"
  # bounded wait: the cycle ends (marker pid exits) within the wait window => proceeds and enqueues instead of skipping
  mk_repo; ( sleep 4 ) & printf '%s\n' "$!" > "$OQ/state/cycle_active_r1"
  OVN_ENQ_BUSY_WAIT_SEC=30 enqueue_fix r1 svc1 "- [ ] [T4] EMERGENCY DEPLOY FIX test item" > "$T/enq3.out"; echo "rc=$? busy=$ENQ_BUSY" > "$T/enq3"
  # idle
  mk_repo; rm -f "$OQ/state/cycle_active_r1"
  enqueue_fix r1 svc1 "- [ ] [T4] EMERGENCY DEPLOY FIX test item" > "$T/enq2.out"; echo "rc=$? busy=$ENQ_BUSY" > "$T/enq2"
)
eq "enqueue_fix: cycle in flight => rc 75 (busy), ENQ_BUSY=1" "rc=75 busy=1" "$(sed -n 1p "$T/enq1")"
eq "enqueue_fix: ... the unpushed commit was NOT reset away" "$(cat "$T/enq1.want")" "$(sed -n 2p "$T/enq1")"
eq "enqueue_fix BENIGN: cycle ends inside the bounded wait => waited, then enqueued (rc 0)" "rc=0 busy=0" "$(cat "$T/enq3")"
eq "enqueue_fix BENIGN: idle repo => enqueued (rc 0, not busy)" "rc=0 busy=0" "$(cat "$T/enq2")"
ok "enqueue_fix BENIGN: the emergency commit reached origin" "$(git -C "$ORIGIN" log --format=%s overnight/feature | grep -q 'auto-enqueue emergency deploy-fix' && echo 1 || echo 0)"
ok "enqueue_fix control: with no cycle running the old reset discarded the unpushed commit (same hazard)" "$([ "$(git -C "$ORIGIN" log --format=%s overnight/feature | grep -c 'model commit L')" = 0 ] && echo 1 || echo 0)"
# the main loop: a busy skip must give the attempt back so the failed deploy is retried next pass
ok "deploy_watch main loop: busy skip un-marks the deploy and refunds the attempt" "$(grep -q 'ENQ_BUSY:-0}" = 1' "$Q/deploy_watch.sh" && grep -q 'rm -f "\$idf"; echo \$((atts - 1)) > "\$atf"' "$Q/deploy_watch.sh" && echo 1 || echo 0)"

echo "  $P passed, $F failed"; [ "$F" = 0 ]
