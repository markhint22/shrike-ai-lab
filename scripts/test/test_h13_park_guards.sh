#!/usr/bin/env bash
# test_h13_park_guards.sh - 2026-10-04 (h13 task 1). ovn_filesize_retag.sh (cron 40 */4) and scripts/ovn_batch_park_stragglers.sh both
# `git reset --hard origin/overnight/feature` in the live clone with no guard; that discarded a fleet cycle's unpushed commit twice
# (12:40 and 00:40 CDT). Both must now SKIP a repo whose cycle is in flight (same ovn_ri_cycle_active guard as ovn_park_sweep.sh), and
# keep the old behaviour when the integrity lib is absent (the live dir is deployed file by file).
# Each case: live cycle marker => skipped, commit survives (the fix); dead-pid marker => processed (BENIGN control); no marker and no
# guard => the reset really discards the commit (NEGATIVE control of the hazard).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
Q="$(cd "$HERE/../.." && pwd)"
P=0; F=0
ok(){ if [ "$2" = 1 ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL $1"; fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"; [ -n "${SLP:-}" ] && kill "$SLP" 2>/dev/null' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t.com GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0
( sleep 300 & echo $! > "$T/slp"; wait ) >/dev/null 2>&1 &
sleep 0.3; SLP="$(cat "$T/slp")"
( sleep 0.1 & echo $! > "$T/dead"; wait ) >/dev/null 2>&1; sleep 0.4; DEAD="$(cat "$T/dead")"

# mk_world: fresh fake $HOME/overnight-queue with repo r1 (origin + clone on overnight/feature carrying ONE unpushed commit "L")
mk_world(){
  rm -rf "$T/w"; export HOME="$T/w/home"; OQ="$HOME/overnight-queue"
  mkdir -p "$OQ/scripts" "$OQ/state" "$OQ/logs" "$OQ/repos"
  cp "$Q/ovn_filesize_retag.sh" "$Q/ovn_filesize_retag.py" "$OQ/"
  cp "$Q/scripts/ovn_batch_park_stragglers.sh" "$Q/scripts/ovn_batch_stragglers.py" "$Q/scripts/ovn_batch_park_tagger.py" "$Q/scripts/lib_worktree.sh" "$OQ/scripts/"
  [ "${NOLIB:-0}" = 1 ] || cp "$Q/scripts/lib_run_integrity.sh" "$OQ/scripts/"
  printf '#!/bin/bash\necho "queue.sh $*" >> "$HOME/queue.calls"\nexit 0\n' > "$OQ/queue.sh"; chmod +x "$OQ/queue.sh"
  printf '[{"id":"ongoing-r1","type":"aider_fix","repo":"%s/repos/r1","enabled":true}]\n' "$OQ" > "$OQ/tasks.json"
  ORIGIN="$T/w/origin.git"; git init -q --bare -b main "$ORIGIN"; git init -q -b overnight/feature "$T/w/seed"
  ( cd "$T/w/seed" && mkdir -p app && seq 1 700 | sed 's/^/x = /' > app/big.py \
    && printf '# P\n\n## Next Steps\n- [ ] [T1] app/big.py — rework. [feat:r1-bad]\n- [ ] [T1] app/big.py — rework two. [feat:r1-bad]\n' > OVERNIGHT_PROGRESS.md \
    && git add -A && git commit -q -m base && git remote add origin "$ORIGIN" && git push -q origin overnight/feature )
  git clone -q -b overnight/feature "$ORIGIN" "$OQ/repos/r1" 2>/dev/null
  ( cd "$OQ/repos/r1" && echo 2 > extra.py && git add extra.py && git commit -q -m "model commit L (unpushed)" )
  LSHA="$(git -C "$OQ/repos/r1" rev-parse HEAD)"
  : > "$HOME/queue.calls"
}
head_of(){ git -C "$OQ/repos/r1" rev-parse HEAD; }
retag(){ ( cd "$OQ" && bash ovn_filesize_retag.sh r1 ) > "$T/out" 2>&1; }

# ------------------------------------------------------------------ ovn_filesize_retag.sh
mk_world; rm -f "$OQ/state/cycle_active_r1"
retag
ok "retag NEG control: idle repo, unpushed commit IS discarded by the reset (the incident) and the repo is retagged" "$([ "$(head_of)" != "$LSHA" ] && grep -q 'retagged 2' "$T/out" && echo 1 || echo 0)"

mk_world; printf '%s\n' "$SLP" > "$OQ/state/cycle_active_r1"
retag
ok "retag: live cycle marker => skipped with a log line" "$(grep -q 'in flight - skipping this pass' "$T/out" && echo 1 || echo 0)"
ok "retag: the unpushed model commit SURVIVES" "$([ "$(head_of)" = "$LSHA" ] && echo 1 || echo 0)"
ok "retag: no hold taken, nothing pushed on a skipped repo" "$(! grep -q 'hold r1' "$HOME/queue.calls" && [ "$(git -C "$ORIGIN" rev-list --count overnight/feature)" = 1 ] && echo 1 || echo 0)"
ok "retag: the pass still completes" "$(grep -q 'ovn_filesize_retag pass complete' "$T/out" && echo 1 || echo 0)"

mk_world; printf '%s\n' "$DEAD" > "$OQ/state/cycle_active_r1"
retag
ok "retag BENIGN: dead-pid (stale) marker does not freeze the repo - it is retagged" "$(grep -q 'retagged 2' "$T/out" && echo 1 || echo 0)"

NOLIB=1 mk_world; printf '%s\n' "$SLP" > "$OQ/state/cycle_active_r1"
retag
ok "retag fail-safe: lib missing => old behaviour, no crash, repo processed" "$(grep -q 'retagged 2' "$T/out" && ! grep -q 'command not found' "$T/out" && echo 1 || echo 0)"
rm -f "$OQ/state/cycle_active_r1"

# ------------------------------------------------------------------ ovn_batch_park_stragglers.sh
ts_of(){ python3 -c "import time,sys; print(time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(int(sys.argv[1]))))" "$1"; }
seed_outcomes(){   # chronically-F batch r1-bad: 1 landed of 5 attempts, 30h old
  local t; t="$(ts_of $(( $(date +%s) - 30*3600 )))"
  for cls in landed noop noop reverted noop; do printf '{"repo":"r1","feat_tag":"r1-bad","class":"%s","ts":"%s"}\n' "$cls" "$t"; done > "$OQ/state/outcomes.jsonl"
}
strag(){ ( cd "$OQ" && bash scripts/ovn_batch_park_stragglers.sh ) > "$T/sout" 2>&1; }
prog_on_origin(){ git -C "$ORIGIN" show overnight/feature:OVERNIGHT_PROGRESS.md; }

mk_world; seed_outcomes; rm -f "$OQ/state/cycle_active_r1"
strag
ok "straggler NEG control: idle repo => parked on origin AND the live clone is reset (unpushed commit gone: the incident)" "$(prog_on_origin | grep -q 'AUTO-SKIP batch-graded-F' && [ "$(head_of)" != "$LSHA" ] && echo 1 || echo 0)"

mk_world; seed_outcomes; printf '%s\n' "$SLP" > "$OQ/state/cycle_active_r1"
before="$(git -C "$ORIGIN" rev-parse overnight/feature)"
strag
ok "straggler: live cycle marker => the repo is skipped (logged)" "$(grep -q 'cycle in flight - skipping' "$OQ/logs/ovn_batch_park_stragglers.log" && echo 1 || echo 0)"
ok "straggler: unpushed model commit SURVIVES in the live clone" "$([ "$(head_of)" = "$LSHA" ] && echo 1 || echo 0)"
ok "straggler: nothing pushed while the cycle is in flight" "$([ "$(git -C "$ORIGIN" rev-parse overnight/feature)" = "$before" ] && echo 1 || echo 0)"
ok "straggler: batch NOT marked dedup (retried next run)" "$(! grep -qxF r1-bad "$OQ/state/batch_stragglers_parked.txt" 2>/dev/null && echo 1 || echo 0)"
rm -f "$OQ/state/cycle_active_r1"; strag
ok "straggler: once the cycle ends the next run parks the batch (retry works)" "$(prog_on_origin | grep -q 'AUTO-SKIP batch-graded-F' && grep -qxF r1-bad "$OQ/state/batch_stragglers_parked.txt" && echo 1 || echo 0)"

mk_world; seed_outcomes; printf '%s\n' "$DEAD" > "$OQ/state/cycle_active_r1"
strag
ok "straggler BENIGN: dead-pid marker is ignored - batch parked as usual" "$(prog_on_origin | grep -q 'AUTO-SKIP batch-graded-F' && echo 1 || echo 0)"

NOLIB=1 mk_world; seed_outcomes; printf '%s\n' "$SLP" > "$OQ/state/cycle_active_r1"
strag
ok "straggler fail-safe: lib missing => old behaviour, batch parked, no crash" "$(prog_on_origin | grep -q 'AUTO-SKIP batch-graded-F' && ! grep -q 'command not found' "$T/sout" && echo 1 || echo 0)"

echo "test_h13_park_guards: $P passed, $F failed"
[ "$F" -eq 0 ]
