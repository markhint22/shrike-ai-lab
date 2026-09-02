#!/usr/bin/env bash
# Restore a known-good working state after the coder trial:
#  1) roll the model back to the 27B (known-careful baseline)
#  2) back up + reset each active repo's overnight/feature to its last
#     pre-cutover commit (discard the coder's broken night, keep prior good work)
#  3) re-enable the two auto-disabled tasks + clear failure counters
#  4) resume the queue
# Disconnect-safe-ish; conservative (skips a repo's reset if the pre-cutover
# commit can't be found). Everything is backed up to a branch for recovery.
set -uo pipefail
Q=/home/mhintermeister/overnight-queue
OUT=$Q/reports/restore.out
CUTOVER="2026-08-25 21:24:00"    # coder cutover time; reset target = last commit BEFORE this
: > "$OUT"
log(){ echo "[$(date +%H:%M:%S)] $*" >> "$OUT"; }

log "pausing queue"; "$Q/queue.sh" pause >/dev/null
for i in $(seq 1 20); do fuser "$Q/state/run.lock" >/dev/null 2>&1 || break; sleep 8; done

# --- 1. roll model back to 27B ---
if docker inspect shrike-llama-27b-rollback >/dev/null 2>&1; then
  log "rolling model back: coder -> 27B"
  docker stop shrike-llama-coder >/dev/null 2>&1 || true
  docker rm -f shrike-llama-coder >/dev/null 2>&1 || true
  docker rename shrike-llama-27b-rollback shrike-llama-dflash-35b 2>/dev/null || true
  docker start shrike-llama-dflash-35b >/dev/null 2>&1 || true
  for i in $(seq 1 60); do curl -sf http://localhost:8081/health >/dev/null 2>&1 && break; sleep 2; done
  log "27B health: $(docker ps --filter name=shrike-llama-dflash-35b --format '{{.Status}}')"
  # revert edit-format for the 27B (it uses udiff)
  sed -i 's/--edit-format diff/--edit-format udiff/' "$Q/run_overnight.sh" && log "edit-format -> udiff"
else
  log "WARN: rollback container missing; leaving current model as-is"
fi

# --- 2. back up + reset broken overnight/feature branches ---
for repo in billwatch gitlark iptv_apps test-automation-agent xlite shrike-labs-website social-media-manager; do
  d="$Q/repos/$repo"; [ -d "$d/.git" ] || continue
  git -C "$d" fetch origin overnight/feature --quiet 2>/dev/null
  git -C "$d" checkout overnight/feature --quiet 2>/dev/null || continue
  target=$(git -C "$d" rev-list -1 --before="$CUTOVER" overnight/feature 2>/dev/null)
  cur=$(git -C "$d" rev-parse overnight/feature 2>/dev/null)
  if [ -z "$target" ] || [ "$target" = "$cur" ]; then
    log "$repo: nothing to reset (already at/ before cutover)"; continue
  fi
  n=$(git -C "$d" rev-list --count "$target..$cur")
  git -C "$d" branch -f coder-trial-backup "$cur" 2>/dev/null
  git -C "$d" reset --hard "$target" --quiet
  git -C "$d" push origin +overnight/feature --quiet 2>/dev/null
  log "$repo: reset overnight/feature back $n commit(s) to pre-cutover $target (backup: coder-trial-backup)"
done

# --- 3. re-enable auto-disabled tasks + clear counters ---
for id in ongoing-test-automation-agent ongoing-xlite; do
  "$Q/queue.sh" enable "$id" >/dev/null 2>&1 && log "re-enabled $id (+counter reset)"
done

# --- 4. resume ---
"$Q/queue.sh" resume >/dev/null; log "queue resumed on 27B"
log "=== RESTORE COMPLETE ==="
