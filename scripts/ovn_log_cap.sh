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
#   RETENTION (2026-10-13, night review platform P9): the idle loop wrote a run dir (logs/<YYYYMMDD-HHMMSS>/) and a run report (reports/<...>.md) every ~65 s: 46k run dirs and 40k
#   reports (2.5 GB logs, 163 MB reports) on the box. In apply mode, after the size caps:
#     - run dirs logs/<YYYYMMDD-HHMMSS> and logs/<YYYY-MM-DD> older than OVN_LOG_RUN_KEEP_DAYS (default 14, by mtime) are removed, EXCEPT the newest OVN_LOG_RUN_KEEP_NEWEST (default 200)
#       by mtime (a dormant box keeps its latest evidence). Only dirs with exactly those names, never a symlink, never logs/archive or logs/hygiene_gate.
#     - RUN reports only: reports/<YYYYMMDD-HHMMSS>.md (the run_overnight.sh report names) older than OVN_REPORT_KEEP_DAYS (default 14) are removed, EXCEPT the newest OVN_REPORT_KEEP_NEWEST
#       (default 200) of them by mtime. Every other file in reports/ (groom.sh proposals grooming-<repo>-<date>.md, dated one-offs like 2026-08-02.md, *.out) is NEVER touched: they are not
#       idle-loop output and have their own retention story (review finding 2026-10-13: a name-blind *.md rule would have deleted ~500 of them on the live flip). Why the newest 200 are sacred: the
#       off-box dead-man's switch (ops/fleet_review/box_deadman.py: `ls -t reports | head -1`, DEADMAN_STALE_S 20 min) and ovn_notify.py (_last_heartbeat: newest report at or before a
#       cut, 'Queue silent' / boot notes) use the NEWEST report's mtime as the queue's heartbeat; retention can therefore never leave them without one, and a 14-day-old report is
#       far older than any freshness window (20-40 min). In dry-run mode retention only reports counts.
#     OVN_LOG_RETENTION=off disables both. A dir/report that is deleted while another tool reads it is a non-issue at these ages.
#   NOTE the live-mode flip (OVN_LOG_CAP=on / --apply) is a CRON-LINE decision, see docs: until it is flipped everything above only logs 'WOULD ...'.
# env: OVN_Q (default ~/overnight-queue). Never touches state/, repos/ or anything outside logs/ and reports/. A log whose size changes while it is being read is skipped.
# Cron (SHADOW: dry run, writes its findings to logs/log_cap.log; switch to OVN_LOG_CAP=on after one look):
#   17 5 * * * cd ~/overnight-queue && nice -n 19 scripts/ovn_log_cap.sh >> logs/log_cap.log 2>&1
# LIVE (after reading the first dry-run lines of logs/log_cap.log; proposed 2026-10-13):
#   17 5 * * * cd ~/overnight-queue && OVN_LOG_CAP=on nice -n 19 scripts/ovn_log_cap.sh >> logs/log_cap.log 2>&1
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
# ---- retention of run dirs and run reports (2026-10-13) ----
# Candidate lists come from ONE find each (-type d / -type f never matches a symlink), the keep-newest set is subtracted with one grep -vxFf, so 46k run dirs cost a few
# process spawns, not 46k. Temp files live in ${TMPDIR:-/tmp}, so even the dry run writes nothing under logs/ or reports/.
if [ "${OVN_LOG_RETENTION:-on}" != off ]; then
  RDAYS="$(num "${OVN_LOG_RUN_KEEP_DAYS:-14}" 14)"; RNEW="$(num "${OVN_LOG_RUN_KEEP_NEWEST:-200}" 200)"
  PDAYS="$(num "${OVN_REPORT_KEEP_DAYS:-14}" 14)"; PNEW="$(num "${OVN_REPORT_KEEP_NEWEST:-200}" 200)"
  RUNDIR_ERE='^(20[0-9]{6}-[0-9]{6}|20[0-9]{2}-[0-9]{2}-[0-9]{2})$'
  tk="$(mktemp "${TMPDIR:-/tmp}/ovn_log_cap.keep.XXXXXX")" && tc="$(mktemp "${TMPDIR:-/tmp}/ovn_log_cap.cand.XXXXXX")" || { say "no temp file - retention skipped"; tk=""; }
  if [ -n "$tk" ]; then
    # run dirs: exact names only; the newest RNEW (by mtime) are never candidates
    ls -1t "$LOGS" 2>/dev/null | grep -E "$RUNDIR_ERE" | head -n "$RNEW" > "$tk" || true
    find "$LOGS" -mindepth 1 -maxdepth 1 -type d -mtime +"$RDAYS" 2>/dev/null | sed 's#.*/##' | grep -E "$RUNDIR_ERE" | grep -vxFf "$tk" > "$tc" || true
    rd_n="$(wc -l < "$tc" | tr -d ' ')"
    if [ "$rd_n" -gt 0 ]; then
      if [ "$APPLY" = 1 ]; then
        while IFS= read -r d; do [ -n "$d" ] && [ -d "$LOGS/$d" ] && [ ! -L "$LOGS/$d" ] && rm -rf -- "${LOGS:?}/$d"; done < "$tc"
        say "removed $rd_n run dir(s) older than ${RDAYS}d (kept the newest $RNEW)"
      else say "WOULD remove $rd_n run dir(s) older than ${RDAYS}d (keeping the newest $RNEW)"; fi
    fi
    # run reports: exact run-report names only (NOT grooming proposals or other *.md); the newest PNEW (by mtime) are never candidates (box_deadman / ovn_notify heartbeat)
    RPT="$Q/reports"; REPORT_ERE='^20[0-9]{6}-[0-9]{6}\.md$'
    if [ -d "$RPT" ]; then
      ls -1t "$RPT" 2>/dev/null | grep -E "$REPORT_ERE" | head -n "$PNEW" > "$tk" || true
      find "$RPT" -maxdepth 1 -type f -name '*.md' -mtime +"$PDAYS" 2>/dev/null | sed 's#.*/##' | grep -E "$REPORT_ERE" | grep -vxFf "$tk" > "$tc" || true
      rp_n="$(wc -l < "$tc" | tr -d ' ')"
      if [ "$rp_n" -gt 0 ]; then
        if [ "$APPLY" = 1 ]; then
          while IFS= read -r f; do [ -n "$f" ] && [ -f "$RPT/$f" ] && [ ! -L "$RPT/$f" ] && rm -f -- "${RPT:?}/$f"; done < "$tc"
          say "removed $rp_n report(s) older than ${PDAYS}d (kept the newest $PNEW)"
        else say "WOULD remove $rp_n report(s) older than ${PDAYS}d (keeping the newest $PNEW)"; fi
      fi
    fi
    rm -f "$tk" "$tc"
  fi
fi
say "done: $capped log(s) $([ "$APPLY" = 1 ] && echo capped || echo "would be capped"), ~$((saved / 1048576)) MB freed"
exit 0
