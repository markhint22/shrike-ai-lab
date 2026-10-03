#!/usr/bin/env bash
# Scenario driver for test_harness_y.sh (harness Y2, 2026-10-02): runs the REAL run_aider_fix_task (OVN_SOURCE_ONLY) in a hermetic fake tree with a stub
# `aider`, so the scout-grounding step is exercised end to end. Generic: the test supplies the repo layout, the progress file and the scout reply.
# usage: lib_ro_harness_y_driver.sh <workdir>     env: Y_SETUP=<sh file run inside the repo before the base commit>  Y_PROGRESS=<md file>  Y_SCOUT=<scout reply file>
#                                                      Y_LINK_GROUND=0 (do not link ovn_scout_ground.py = the pre-change tree)
# outputs: <workdir>/result (the status string), <workdir>/task.log, <workdir>/scn/calls/N.(scout|impl) (aider argv per call)
set -u
D="${1:?workdir}"
HERE="$(cd "$(dirname "$0")" && pwd)"; Q="$(cd "$HERE/../.." && pwd)"
RO="${OVN_RUN_OVERNIGHT:-$Q/run_overnight.sh}"
rm -rf "$D"; mkdir -p "$D"
export HOME="$D/home"; mkdir -p "$HOME/aider-venv/bin"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_TERMINAL_PROMPT=0
SD="$D/sd"; R="$D/repos/yrepo"; O="$D/origin.git"; TL="$D/task.log"; SC="$D/scn"
mkdir -p "$SD/scripts" "$SD/state" "$SD/logs" "$SD/reports" "$SC" "$D/repos"
for f in "$Q"/scripts/*.sh "$Q"/scripts/*.py; do [ -f "$f" ] && ln -s "$f" "$SD/scripts/$(basename "$f")"; done
for f in dedupe_progress_headers.py ovn_classify_fail.sh ovn_park_unworkable.py; do [ -f "$Q/$f" ] && ln -s "$Q/$f" "$SD/$f"; done
[ "${Y_LINK_GROUND:-1}" = 1 ] && ln -s "$Q/ovn_scout_ground.py" "$SD/ovn_scout_ground.py"
echo '{}' > "$SD/model-metadata.json"; echo '[]' > "$SD/tasks.json"
cat > "$HOME/aider-venv/bin/aider" <<'STUB'
#!/bin/bash
S="$Y_SCN"; mkdir -p "$S/calls"
n=$(ls "$S/calls" | wc -l | tr -d ' ')
kind=impl; for a in "$@"; do [ "$a" = "--no-auto-commits" ] && kind=scout; done
printf '%s\n' "$@" > "$S/calls/$((n+1)).$kind"
if [ "$kind" = scout ]; then cat "$S/scout.out"; else echo "Tokens: 10 sent, 5 received"; fi
exit 0
STUB
chmod +x "$HOME/aider-venv/bin/aider"; export Y_SCN="$SC"
git init -q --bare "$O"; git -C "$O" symbolic-ref HEAD refs/heads/main
git clone -q "$O" "$R" 2>/dev/null
( cd "$R" && git checkout -q -b main 2>/dev/null
  printf 'claude rules\n' > CLAUDE.md
  [ -n "${Y_SETUP:-}" ] && bash "$Y_SETUP"
  cp "$Y_PROGRESS" OVERNIGHT_PROGRESS.md
  git add -A; git commit -q -m base; git push -q origin main 2>/dev/null )
git -C "$O" symbolic-ref HEAD refs/heads/main
cp "$Y_SCOUT" "$SC/scout.out"
export OVN_SCRIPT_DIR="$SD" OVN_SOURCE_ONLY=1 OVN_ARCHITECT=0
# shellcheck disable=SC1090
source "$RO"
set +e
STATE_DIR="$SD/state"
run_repo_verification(){ echo pass; }
PROMPT="${Y_PROMPT:-Work the single top not-yet-done item in the overnight progress log.}"
STATUS="$(run_aider_fix_task t1 "$R" "$PROMPT" ovn/t1 false "$TL" "" false 2 "" 30)"
printf '%s' "$STATUS" > "$D/result"
exit 0
