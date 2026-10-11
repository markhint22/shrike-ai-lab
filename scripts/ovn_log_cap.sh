#!/usr/bin/env bash
# scripts/ovn_log_cap.sh - size cap for the pipeline's append-only cron logs (qacov F7, 2026-10-10).
#
# Why: logs/ reached 2.4 GB with no rotation (branch_hygiene.log 136 MB / 1.5M lines, queue_refill.log 12 MB of "still dry" lines) and a post-incident grep
# over them took minutes. Disk is not the problem (647 GB free); readability is. logrotate is NOT used: these logs are written by `>>` redirects of cron jobs
# that stay open for the whole run, so the cap works copytruncate-style on the same inode (the writers keep appending at the new end).
#
# usage: ovn_log_cap.sh [--apply]       default = DRY RUN: prints what it would do and changes nothing. OVN_LOG_CAP=on is the same as --apply (cron).
#   for each logs/*.log bigger than OVN_LOG_CAP_MB (default 20 MB): the part before the last OVN_LOG_KEEP_LINES (default 20000) lines is gzipped into
#   logs/archive/<name>.<UTC ts>.gz, the log keeps its tail. Lines appended between the tail read and the truncate are lost (a few lines at most; take the
#   cost, these are diagnostics). Archives beyond the newest OVN_LOG_ARCHIVE_KEEP (default 3) per log, and per-run gate files in logs/hygiene_gate older than
#   OVN_HYGIENE_GATE_KEEP_DAYS (default 3) are deleted - ONLY inside those two dirs, ONLY in apply mode.
#   ovn_planner.log is the exception: ovn_research_trigger_check.py walks it BACKWARD for a repo's unbroken "no [ready] roadmap feature" streak (hours -> research ordering), so
#   a 20000-line tail (~2 days at the measured ~10k lines/day) would cut a longer streak short. It keeps OVN_LOG_KEEP_PLANNER lines (default 100000, ~10 days) when that is more than
#   the global keep. ovn_planning_stats.py only reads a <= 24 h window and is fine either way.
# env: OVN_Q (default ~/overnight-queue). Never touches state/, repos/ or anything outside logs/. A log whose size changes while it is being read is skipped.
# Cron (SHADOW: dry run, writes its findings to logs/log_cap.log; switch to OVN_LOG_CAP=on after one look):
#   17 5 * * * cd ~/overnight-queue && nice -n 19 scripts/ovn_log_cap.sh >> logs/log_cap.log 2>&1
set -uo pipefail
Q="${OVN_Q:-$HOME/overnight-queue}"; LOGS="$Q/logs"
APPLY=0; [ "${1:-}" = "--apply" ] && APPLY=1; [ "${OVN_LOG_CAP:-off}" = "on" ] && APPLY=1
num(){ case "$1" in ''|*[!0-9]*) echo "$2";; *) echo "$1";; esac; }   # non-numeric -> the default
MB="$(num "${OVN_LOG_CAP_MB:-20}" 20)"; KEEP="$(num "${OVN_LOG_KEEP_LINES:-20000}" 20000)"; AKEEP="$(num "${OVN_LOG_ARCHIVE_KEEP:-3}" 3)"; GDAYS="$(num "${OVN_HYGIENE_GATE_KEEP_DAYS:-3}" 3)"
KEEP_PLANNER="$(num "${OVN_LOG_KEEP_PLANNER:-100000}" 100000)"
[ "$KEEP" -ge 1 ] || KEEP=1
say(){ echo "$(date '+%F %T') log_cap: $*"; }
[ -d "$LOGS" ] || { say "no $LOGS - nothing to do"; exit 0; }
MODE="dry-run"; [ "$APPLY" = 1 ] && MODE="apply"
say "mode=$MODE cap=${MB}MB keep=${KEEP}lines (ovn_planner.log: ${KEEP_PLANNER}) archives=${AKEEP}"
LIMIT=$(( MB * 1024 * 1024 )); capped=0; saved=0
for f in "$LOGS"/*.log; do
  [ -f "$f" ] || continue
  size="$(wc -c < "$f" | tr -d ' ')"
  [ "$size" -gt "$LIMIT" ] || continue
  total="$(wc -l < "$f" | tr -d ' ')"
  keep="$KEEP"; [ "$(basename "$f")" = "ovn_planner.log" ] && [ "$KEEP_PLANNER" -gt "$keep" ] && keep="$KEEP_PLANNER"
  if [ "$total" -le "$keep" ]; then say "$(basename "$f"): ${size} bytes but only $total lines (<= keep $keep; very long lines or a log whose readers need the history) - left alone"; continue; fi
  drop=$(( total - keep ))
  if [ "$APPLY" != 1 ]; then say "WOULD cap $(basename "$f"): $((size / 1048576)) MB, $total lines -> keep last $keep, archive $drop lines to logs/archive/"; capped=$((capped+1)); continue; fi
  mkdir -p "$LOGS/archive" || { say "cannot create $LOGS/archive - skipped $(basename "$f")"; continue; }
  ts="$(date -u +%Y%m%dT%H%M%SZ)"; arch="$LOGS/archive/$(basename "$f").$ts.gz"; tmp="$(mktemp "$LOGS/.log_cap.XXXXXX")" || continue
  # snapshot of the head to archive and of the tail to keep, both taken from the same byte range (the first $size bytes), so a concurrent append is never half-copied
  head -c "$size" "$f" > "$tmp.snap" 2>/dev/null
  if [ "$(wc -c < "$tmp.snap" | tr -d ' ')" -ne "$size" ]; then say "$(basename "$f"): shrank while being read - skipped"; rm -f "$tmp" "$tmp.snap"; continue; fi
  head -n "$drop" "$tmp.snap" | gzip -c > "$arch" && gzip -t "$arch" 2>/dev/null || { say "$(basename "$f"): archive failed - log untouched"; rm -f "$tmp" "$tmp.snap" "$arch"; continue; }
  tail -n "$keep" "$tmp.snap" > "$tmp"
  # keep anything appended after the snapshot, then truncate in place (same inode: open `>>` writers continue at the new end)
  tail -c +"$((size + 1))" "$f" >> "$tmp" 2>/dev/null
  cat "$tmp" > "$f" && { capped=$((capped+1)); saved=$(( saved + size - $(wc -c < "$tmp" | tr -d ' ') )); say "capped $(basename "$f"): $total -> $keep lines (+ appended since), head archived to $arch"; }
  rm -f "$tmp" "$tmp.snap"
  # archive retention: newest AKEEP per log
  n=0; for a in $(ls -1t "$LOGS/archive/$(basename "$f")".*.gz 2>/dev/null); do n=$((n+1)); [ "$n" -gt "$AKEEP" ] && { rm -f "$a"; say "pruned old archive $(basename "$a")"; }; done
done
# per-run hygiene gate files
if [ -d "$LOGS/hygiene_gate" ]; then
  old="$(find "$LOGS/hygiene_gate" -maxdepth 1 -type f -mtime +"$GDAYS" 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$old" -gt 0 ]; then
    if [ "$APPLY" = 1 ]; then find "$LOGS/hygiene_gate" -maxdepth 1 -type f -mtime +"$GDAYS" -exec rm -f {} + 2>/dev/null; say "removed $old hygiene gate file(s) older than ${GDAYS}d"
    else say "WOULD remove $old hygiene gate file(s) older than ${GDAYS}d"; fi
  fi
fi
say "done: $capped log(s) $([ "$APPLY" = 1 ] && echo capped || echo "would be capped"), ~$((saved / 1048576)) MB freed"
exit 0
