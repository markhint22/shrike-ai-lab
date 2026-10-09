#!/usr/bin/env bash
# cron_nightly.sh - the ONE entry point cron should call for the device lane (advisory; always exits 0).
#   crontab:  30 2 * * *  /home/mhintermeister/overnight-queue/qa/device_lane/cron_nightly.sh >>/home/mhintermeister/overnight-queue/state/qa_devicelane/cron.log 2>&1
# What it adds over run_nightly.sh: resolves its own path BEFORE any cd, pins a minimal PATH, takes a wrapper-level flock -n (a second
# firing is a silent no-op), pins the emulator to QA_CPUSET (default 10-15 = 6 of 16 cores, the QA cap in the plan), and re-execs itself
# under `sg kvm` when this session predates the user's membership in group kvm (cron normally has it already).
# It never takes run.lock or any per-repo lock (spec hard rule 4).
set -u
SELF="${BASH_SOURCE[0]}"; case "$SELF" in /*) ;; *) SELF="$PWD/$SELF" ;; esac
HERE="$(cd "$(dirname "$SELF")" && pwd)"
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export QA_CPUSET="${QA_CPUSET-10-15}"
OVN="${OVN_DIR:-$(cd "$HERE/../.." && pwd)}"; export OVN_DIR="$OVN"
STATE="$OVN/state/qa_devicelane"; mkdir -p "$STATE" 2>/dev/null

# under cron, NTFY_SERVER must point at the relay (never ntfy.sh); the lane itself never notifies, but be safe for child tooling
: "${NTFY_SERVER:=http://127.0.0.1:8099}"; export NTFY_SERVER

if [ -z "${DL_FAKE_KVM:-}" ] && { [ ! -r /dev/kvm ] || [ ! -w /dev/kvm ]; } && [ -z "${DL_IN_SG:-}" ] \
   && command -v sg >/dev/null 2>&1 && getent group kvm 2>/dev/null | tr ',:' '  ' | grep -qw "$(id -un)"; then
  export DL_IN_SG=1
  exec sg kvm -c "$(printf '%q ' "$SELF" "$@")"
fi

if command -v flock >/dev/null 2>&1; then
  exec 8>"$STATE/cron.lock"
  flock -n 8 || { echo "$(date -u +%FT%TZ) [cron_nightly] previous run still active - skipped"; exit 0; }
fi
echo "$(date -u +%FT%TZ) [cron_nightly] start"

# 2026-10-02 production-safety wrapper. The lane is ADVISORY and must never hurt the dev loop:
#  * the WHOLE run (build, emulator, appium, specs) is pinned to QA_CPUSET (6 of 16 cores), niced and best-effort-ioniced;
#  * run_nightly.sh has its own overall cap (DL_OVERALL_TIMEOUT, default 6000s) and tears down on it; this wrapper adds a backstop hard
#    timeout (cap + 420s, TERM then KILL) in case run_nightly itself hangs;
#  * AFTER the run, whatever happened, a verified sweep kills and reports anything still carrying our avd / appium port.
# It never takes run.lock / a repo lock, and always exits 0.
. "$HERE/lane_env.sh"
export PATH="$PATH:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator"
PFX=()
if [ -n "$QA_CPUSET" ] && command -v taskset >/dev/null 2>&1; then
  if taskset -c "$QA_CPUSET" true >/dev/null 2>&1; then PFX+=(taskset -c "$QA_CPUSET"); else echo "$(date -u +%FT%TZ) [cron_nightly] QA_CPUSET=$QA_CPUSET invalid on this host: not pinning"; fi
fi
command -v nice >/dev/null 2>&1 && PFX+=(nice -n 10)
command -v ionice >/dev/null 2>&1 && PFX+=(ionice -c2 -n7)
RUN="${DL_RUN_NIGHTLY:-$HERE/run_nightly.sh}"
CAP="${DL_OVERALL_TIMEOUT:-6000}"; export DL_OVERALL_TIMEOUT="$CAP"
HARD="${DL_HARD_TIMEOUT:-$((CAP + 420))}"
if command -v timeout >/dev/null 2>&1; then
  timeout -k "${DL_HARD_KILL_GRACE:-60}" "$HARD" ${PFX[@]+"${PFX[@]}"} "$RUN" "$@" 8>&-
else
  dl_timeout "$HARD" ${PFX[@]+"${PFX[@]}"} "$RUN" "$@" 8>&-
fi
rc=$?
[ "$rc" = 124 ] || [ "$rc" = 137 ] && echo "$(date -u +%FT%TZ) [cron_nightly] HARD TIMEOUT (${HARD}s) - run_nightly did not exit on its own; sweeping"

rm -f "$STATE/teardown_cron.json"   # never judge this run by a previous run's file
# verified sweep, only when no other (manual) lane run holds lane.lock - never kill a human's run
sweep() { DL_CHECK_ADB="" verify_teardown "$STATE/teardown_cron.json" ""; }
if command -v flock >/dev/null 2>&1; then
  ( flock -n 9 && sweep ) 9>"$STATE/lane.lock" || echo "$(date -u +%FT%TZ) [cron_nightly] another lane run is active - post-run sweep skipped"
else sweep; fi
if grep -q '"clean":true' "$STATE/teardown_cron.json" 2>/dev/null; then echo "$(date -u +%FT%TZ) [cron_nightly] teardown verified: no emulator/appium of ours left"
else echo "$(date -u +%FT%TZ) [cron_nightly] TEARDOWN NOT VERIFIED CLEAN: $(cat "$STATE/teardown_cron.json" 2>/dev/null)"; fi
echo "$(date -u +%FT%TZ) [cron_nightly] done"
exit 0
