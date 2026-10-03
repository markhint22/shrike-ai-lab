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
SHARED="${SHARED_DIR:-$HOME/LocalProjects/shared}"
QUEUE="$SHARED/CLAUDE_QUEUE.md"
ARCHIVE="$SHARED/CLAUDE_QUEUE_DONE.md"
BRIDGE="$SHARED/scripts/overnight-queue/claude_queue_bridge.py"
ARCHIVER="$SHARED/scripts/overnight-queue/archive_claude_queue_done.py"
SRV="${OVN_SSH:-mhintermeister@100.79.64.64}"
REMOTE="${OVN_REMOTE_DIR:-overnight-queue}"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
log(){ echo "$(date '+%F %T') $*"; }

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
# FIX 2026-09-28: this script mutates CLAUDE_QUEUE.md/CLAUDE_QUEUE_DONE.md every hour
# (harvest/retire/archive) but never committed or pushed - left the shared repo dirty
# for hours at a time until a human or an interactive Claude session noticed and swept
# it up in an after-the-fact "update claude queue" commit. Close that gap here instead.
LOCKLIB="$SHARED/scripts/overnight-queue/scripts/lib_lock.sh"
# shellcheck disable=SC1090
[ -f "$LOCKLIB" ] && source "$LOCKLIB"
(
  cd "$SHARED" || exit 0
  if ! command -v acquire_lock >/dev/null 2>&1; then
    log "commit: lib_lock.sh unavailable, skipping commit this pass"
  elif acquire_lock "$SHARED/scripts/overnight-queue/state/claude_queue_bridge_commit.lock" 224 30 "claude-queue-bridge-commit" log; then
    if git diff --quiet -- CLAUDE_QUEUE.md CLAUDE_QUEUE_DONE.md 2>/dev/null; then
      log "commit: no queue-doc changes this pass"
    else
      branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo develop)"
      git add CLAUDE_QUEUE.md CLAUDE_QUEUE_DONE.md
      git commit -q -m "chore(queue): automated bridge pass $(date '+%F %H:%M')"
      git fetch -q origin "$branch" 2>/dev/null
      if git push -q origin "$branch" 2>"$TMP/pusherr"; then
        log "commit: pushed CLAUDE_QUEUE.md/CLAUDE_QUEUE_DONE.md changes to $branch"
      else
        log "commit: push rejected, rebasing and retrying"
        if git pull --rebase -q origin "$branch" 2>>"$TMP/pusherr" && git push -q origin "$branch" 2>>"$TMP/pusherr"; then
          log "commit: pushed after rebase"
        else
          log "commit: push STILL failed after rebase - $(cat "$TMP/pusherr")"
        fi
      fi
    fi
    flock -u 224
  else
    log "commit: lock contended, skipping this pass (next tick will catch up)"
  fi
)

log "claude_queue_bridge pass complete"
