#!/usr/bin/env bash
# 2026-10-14 restart storm: overnight-queue.service (Restart=always) restarted run_overnight.sh every ~3 s while the queue was paused, because a paused
# start exited 0 and systemd restarted it (NRestarts 6554). With OVN_PAUSE_WAIT=1 a paused start must STAY UP (sleep + re-check the pause flag) and resume
# by itself when the flag is removed; without it the cron/manual path keeps its old exit-0 behaviour. Real run_overnight.sh, hermetic fake tree.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_ro_core.sh"
ro_init
ro_hook_stubs
ro_link update_progress.py dedupe_progress_headers.py dedupe_gd_duplicate_functions.py dedupe_python_duplicate_defs.py \
        scripts/ovn_classify.py scripts/ovn_progress_slice.py scripts/ovn_credit_already_satisfied.sh scripts/ovn_retire_vague.py scripts/ovn_extract_failure.sh
ST="$T/tree/state"; HK="$RO_STUB/hooks.log"
mkdir -p "$ST"
ro_tasks '[]'

echo "=== paused, no wait (cron/manual path): unchanged, exits 0 at once ==="
touch "$ST/PAUSED"
ro_run_main
eq "paused without OVN_PAUSE_WAIT: exits 0" 0 "$RO_RC"
has "paused without OVN_PAUSE_WAIT: says skipping" "$RO_OUT" "Skipping this run entirely"

echo "=== paused under the service (OVN_PAUSE_WAIT=1): stays alive, no exit storm ==="
ro_run_main OVN_PAUSE_WAIT=1 OVN_PAUSE_POLL_SEC=1 timeout 4
eq "paused with OVN_PAUSE_WAIT=1: still running after 4 s (timeout rc 124, not an exit)" 124 "$RO_RC"
has "paused with wait: logs that it is waiting" "$RO_OUT" "Waiting for resume"
hasnt "paused with wait: does not log the skip-and-exit line" "$RO_OUT" "Skipping this run entirely"
hasnt "paused with wait: no cycle hooks ran" "$(cat "$HK" 2>/dev/null)" "cycle_notify"

echo "=== resume: removing the flag while waiting lets the same process run a cycle ==="
( cd "$T" && exec timeout 90 env HOME="$T/home" OVN_SCRIPT_DIR="$T/tree" RO_STUB="$T/stub" OVN_PAUSE_WAIT=1 OVN_PAUSE_POLL_SEC=1 bash "$RO_SCRIPT" ) > "$T/resume.out" 2>&1 &
RPID=$!
sleep 3
rm -f "$ST/PAUSED"
wait "$RPID"; RRC=$?
RRES="$(cat "$T/resume.out")"
eq "resume: the waiting process exits 0 after the flag is removed" 0 "$RRC"
has "resume: logs the resume" "$RRES" "Queue resumed"
has "resume: runs the cycle (zero tasks)" "$RRES" "Loaded 0 task(s)"
has "resume: completion logged" "$RRES" "complete. Report:"

echo; echo "$pass passed, $fail failed"; [ "$fail" -eq 0 ]
