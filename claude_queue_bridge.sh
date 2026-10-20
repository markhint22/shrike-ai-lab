#!/usr/bin/env bash
# claude_queue_bridge.sh — MAC-SIDE bridge (CLAUDE_QUEUE.md lives only in the shared repo).
# Four passes, wired to a Mac cron (the server can't see CLAUDE_QUEUE.md):
#   A) HARVEST  — refill the Claude queue from the 27B's AUTO-SKIP ceiling failures.
#   B) PREWORK  — schedule 27B prework for every code-able Claude item that lacks a briefing.
#   C) RETIRE   — flip AUTO-SKIP lines server-side to [x] once their matching CLAUDE_QUEUE.md
#                 item is checked off, so the 27B stops re-flagging code Claude already fixed
#                 and harvest (Pass A) stops re-adding it as a "new" duplicate next cycle.
#   D) ARCHIVE  — move checked-off `[x]` items out of the live queue into CLAUDE_QUEUE_DONE.md
#                 so the live file stays scannable. Safe: harvest/signatures both read
#                 --archive too, so an archived item still suppresses re-harvest/still counts
#                 toward retire — moving it out of the live file never re-opens the dedup bug.
# Idempotent + dedup on both ends, so it's safe to run on a schedule.
set -uo pipefail
# L2-mac-jobs: default = the checkout this script lives in (the dedicated live checkout under launchd), NOT a hard-coded interactive path. SHARED_DIR still overrides.
SHARED="${SHARED_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
QUEUE="$SHARED/CLAUDE_QUEUE.md"
ARCHIVE="$SHARED/CLAUDE_QUEUE_DONE.md"
BRIDGE="$SHARED/scripts/overnight-queue/claude_queue_bridge.py"
ARCHIVER="$SHARED/scripts/overnight-queue/archive_claude_queue_done.py"
SRV="${OVN_SSH:-mhintermeister@100.79.64.64}"
REMOTE="${OVN_REMOTE_DIR:-overnight-queue}"
TMP="$(mktemp -d)" || { echo "claude_queue_bridge: mktemp -d failed - abort" >&2; exit 1; }
[ -n "$TMP" ] && [ -d "$TMP" ] || { echo "claude_queue_bridge: mktemp -d returned no usable directory - abort" >&2; exit 1; }   # 2026-10-16: an empty TMP made every "$TMP/..." path absolute
trap 'rm -rf "${TMP:?}"' EXIT
log(){ echo "$(date '+%F %T') $*"; }

# L2-mac-jobs: when this IS the live checkout, bring it current first (fast-forward / wedged-state recovery live in mac_live_sync.sh; mode OVN_MAC_JOBS, default shadow = report only)
if [ -f "$SHARED/scripts/mac_live_sync.sh" ] && [ "$(cd "${MAC_LIVE_DIR:-$HOME/LocalProjects/shared-live}" 2>/dev/null && pwd -P)" = "$(cd "$SHARED" && pwd -P)" ]; then
  bash "$SHARED/scripts/mac_live_sync.sh" 2>&1 | while read -r l; do log "sync: $l"; done
fi
# L2-mac-jobs review fix: ONE bridge pass at a time, and mac_live_sync.sh (every 5 min) can tell "a pass is editing the queue docs right now" (bridge.lock) from a real dirty checkout.
# Taken AFTER the sync above so that sync still clears residue left by a killed earlier pass.
BRIDGE_LOCK="${OVN_MAC_STATE:-$HOME/.ovn_mac_jobs}/bridge.lock"
if [ -f "$SHARED/scripts/mac_lib.sh" ]; then
  . "$SHARED/scripts/mac_lib.sh"
  if ! mac_lock_acquire "$BRIDGE_LOCK" 3600; then log "another bridge pass holds $BRIDGE_LOCK - skipping this run"; exit 0; fi
  trap 'rm -rf "${TMP:?}"; mac_lock_release "$BRIDGE_LOCK"' EXIT
fi
[ -f "$QUEUE" ] || { log "no CLAUDE_QUEUE.md at $QUEUE — abort"; exit 1; }

# ---- one round-trip: pull server state (AUTO-SKIP items + existing prework basenames) ----
ssh -o ConnectTimeout=20 "$SRV" "
  cd ~/$REMOTE || exit 1
  echo '===AUTOSKIP==='
  for d in repos/*/; do
    r=\$(basename \"\$d\")
    f=\"\$d/OVERNIGHT_PROGRESS.md\"; [ -f \"\$f\" ] || continue
    # 2026-10-03 (A7-1): also harvest '[CLAUDE] [bug-escalated: ...]' lines (the bug-first hand-off to a Claude session; they never reached this queue
    # before). 'sibling step' lines are the other steps of the SAME escalated bug - one queue item per bug, so they are not harvested.
    grep -E '^- \[ \] .*(AUTO-SKIP|\[CLAUDE\] \[bug-escalated)' \"\$f\" 2>/dev/null | grep -v 'bug-escalated: sibling step' | while IFS= read -r line; do
      task=\$(printf '%s' \"\$line\" | sed -E 's/^- \[ \] //; s/\[AUTO-SKIP[^]]*\][[:space:]]*//; s/\[CLAUDE\][[:space:]]*\[bug-escalated[^]]*\][[:space:]]*//' | sed -E 's/[[:space:]]+\$//')
      [ \"\${#task}\" -ge 20 ] && printf '%s\t%s\n' \"\$r\" \"\$task\"
    done
  done
  echo '===PREWORKLIST==='
  ls prework/ 2>/dev/null | grep -E '\.md$' || true
" > "$TMP/srv.txt" 2>"$TMP/ssherr" || { log "ssh pull failed: $(cat "$TMP/ssherr")"; exit 1; }

awk '/^===AUTOSKIP===/{s=1;next} /^===PREWORKLIST===/{s=2;next} s==1{print > "'"$TMP"'/autoskip.tsv"} s==2{print > "'"$TMP"'/prework_list.txt"}' "$TMP/srv.txt"
touch "$TMP/autoskip.tsv" "$TMP/prework_list.txt"

# ---- Pass A: harvest 27B ceiling failures into the Claude queue ----
if [ -s "$TMP/autoskip.tsv" ]; then
  python3 "$BRIDGE" harvest --queue "$QUEUE" --autoskip "$TMP/autoskip.tsv" --archive "$ARCHIVE" 2>&1 | while read -r l; do log "$l"; done
else
  log "harvest: no AUTO-SKIP items on the server"
fi

# ---- Pass B: schedule prework for code-able Claude items lacking a briefing ----
python3 "$BRIDGE" prework --queue "$QUEUE" --prework-list "$TMP/prework_list.txt" > "$TMP/new_prework.tsv" 2>"$TMP/pwerr"
log "$(cat "$TMP/pwerr")"
if [ -s "$TMP/new_prework.tsv" ]; then
  n=$(wc -l < "$TMP/new_prework.tsv" | tr -d ' ')
  # append to the server's prework/queue.tsv, deduping against what's already queued
  scp -o ConnectTimeout=20 "$TMP/new_prework.tsv" "$SRV:~/$REMOTE/prework/.new_prework.tsv" >/dev/null 2>&1
  ssh -o ConnectTimeout=20 "$SRV" "
    cd ~/$REMOTE/prework || exit 1
    touch queue.tsv
    # keep only lines not already present (exact-line dedup)
    # 2026-09-30 FIX: this used to end with a '|| cat .new_prework.tsv >> queue.tsv' fallback. 'grep -v' exits 1 when it prints NOTHING (i.e. every line was already
    # queued), so the fallback re-appended ALL of them every hour: 1,070 unique items had become 13,239 lines (12x) and the prework cron crawled a
    # mostly-duplicate file. Nothing new is a perfectly normal outcome - never treat grep's exit status as failure here.
    grep -vxF -f queue.tsv .new_prework.tsv 2>/dev/null >> queue.tsv; true
    rm -f .new_prework.tsv
    wc -l < queue.tsv
  " > "$TMP/qlen" 2>/dev/null
  log "prework: queued $n item(s); server prework/queue.tsv now has $(tr -d ' ' < "$TMP/qlen") line(s)"
else
  log "prework: nothing new to queue (all code-able Claude items already have briefings)"
fi

# ---- Pass C: retire AUTO-SKIP items on the server whose Claude Queue item is already [x] ----
python3 "$BRIDGE" signatures --queue "$QUEUE" --archive "$ARCHIVE" > "$TMP/checked_sigs.tsv" 2>"$TMP/sigerr"
if [ -s "$TMP/checked_sigs.tsv" ] && [ -s "$TMP/autoskip.tsv" ]; then
  retired_total=0
  for repo in $(cut -f1 "$TMP/checked_sigs.tsv" | sort -u); do
    remote_file="repos/$repo/OVERNIGHT_PROGRESS.md"
    # skip the remote round-trip entirely if this repo had no AUTO-SKIP items this pull
    grep -qF "$(printf '%s\t' "$repo")" "$TMP/autoskip.tsv" 2>/dev/null || continue
    ssh -o ConnectTimeout=20 "$SRV" "cat ~/$REMOTE/$remote_file 2>/dev/null" > "$TMP/prog_$repo.md" 2>/dev/null
    [ -s "$TMP/prog_$repo.md" ] || continue
    awk -F'\t' -v r="$repo" '$1==r{print $2}' "$TMP/checked_sigs.tsv" > "$TMP/sigs_$repo.txt"
    [ -s "$TMP/sigs_$repo.txt" ] || continue
    retire_err="$(python3 "$BRIDGE" retire --progress "$TMP/prog_$repo.md" --signatures "$TMP/sigs_$repo.txt" 2>&1 >/dev/null)"
    n="$(echo "$retire_err" | grep -oE 'RETIRED=[0-9]+' | cut -d= -f2)"
    if [ -n "$n" ] && [ "$n" -gt 0 ]; then
      # back up the remote file before overwriting, then push the patched version
      ssh -o ConnectTimeout=20 "$SRV" "cp ~/$REMOTE/$remote_file ~/$REMOTE/$remote_file.bak" 2>/dev/null
      if scp -o ConnectTimeout=20 "$TMP/prog_$repo.md" "$SRV:~/$REMOTE/$remote_file" >/dev/null 2>&1; then
        log "retire: $repo — retired $n AUTO-SKIP item(s) already resolved by Claude"
        retired_total=$((retired_total + n))
      else
        log "retire: $repo — scp back failed, not applied"
      fi
    fi
  done
  [ "$retired_total" -gt 0 ] || log "retire: nothing to retire this pass"
else
  log "retire: no checked-off signatures or no server AUTO-SKIP items to check"
fi

# ---- Pass D: archive checked-off items out of the live queue ----
archive_out="$(python3 "$ARCHIVER" "$QUEUE" "$ARCHIVE" 2>&1)"
log "archive: $archive_out"

# ---- Pass E: commit + push any changes this pass made ----
# FIX 2026-09-28: this script mutates CLAUDE_QUEUE.md/CLAUDE_QUEUE_DONE.md every hour (harvest/retire/archive); Pass E commits and pushes them.
# FIX 2026-10-18 (L2-mac-jobs): the old inline version pushed `origin <current branch name>` (on a detached HEAD that pushes nothing) and answered a rejection with
# `git pull --rebase` on a branch holding merge commits - that started a 1244-commit interactive rebase which wedged the shared checkout for hours. The logic now lives in
# scripts/mac_live_commit_push.sh: explicit HEAD:refs/heads/develop refspec, MERGE (never rebase) on rejection, bounded retries, merge conflicts aborted at once, a wedged
# checkout is refused (or, on the dedicated live checkout in enforce mode, repaired). Exit 0 = pushed or nothing to commit.
COMMIT_HELPER="$SHARED/scripts/mac_live_commit_push.sh"
if [ -f "$COMMIT_HELPER" ]; then
  bash "$COMMIT_HELPER" "$SHARED" "chore(queue): automated bridge pass $(date '+%F %H:%M')" CLAUDE_QUEUE.md CLAUDE_QUEUE_DONE.md 2>&1 | while read -r l; do log "commit: $l"; done
  commit_rc="${PIPESTATUS[0]}"
else
  log "commit: $COMMIT_HELPER missing - queue docs NOT committed this pass"; commit_rc=4
fi

log "claude_queue_bridge pass complete (commit rc=$commit_rc)"
# L2-mac-jobs: success heartbeat (supervisor scripts/mac_jobs_health.py): the whole pass worked AND the queue docs are pushed (or there was nothing to push)
if [ "$commit_rc" = 0 ]; then
  mkdir -p "${OVN_MAC_STATE:-$HOME/.ovn_mac_jobs}/hb" 2>/dev/null && date +%s > "${OVN_MAC_STATE:-$HOME/.ovn_mac_jobs}/hb/claudequeuebridge" 2>/dev/null
fi
[ "$commit_rc" = 0 ] || exit 1
