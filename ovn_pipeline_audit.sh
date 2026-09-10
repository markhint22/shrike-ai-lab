#!/usr/bin/env bash
# ovn_pipeline_audit.sh — systematic end-to-end health check of the overnight-queue pipeline.
#
# WHY THIS EXISTS (2026-09-10): the pipeline has grown to ~35 top-level scripts, ~17 under
# scripts/, 28 cron entries, and 22 test files, all added incrementally over weeks. Individual
# unit tests (scripts/test/*.sh) cover specific functions in isolation, but nothing checks the
# SYSTEM as a whole: is every cron-referenced script still on disk, executable, and syntactically
# valid RIGHT NOW? Is every cron job's log actually being written to (proof it's really running,
# not just installed)? Does every active script have SOME test coverage? Are there dead
# references, stale locks, or zombie processes nobody's looked at? This is meant to be run
# regularly (by a human, or eventually its own cron) as the single command that answers
# "is the pipeline actually healthy" without needing an hour of manual spelunking.
#
# Exit code: 0 if no CRITICAL findings, 1 if any CRITICAL finding exists. WARN findings never
# fail the exit code (they're for visibility, not blocking) - only things that would silently
# break the pipeline (missing script, syntax error, cron pointing nowhere) count as critical.
#
# Usage: ovn_pipeline_audit.sh [--quiet]   (--quiet suppresses OK lines, shows only WARN/CRIT)
set -uo pipefail
cd "$HOME/overnight-queue" || exit 1
QUIET=0; [ "${1:-}" = "--quiet" ] && QUIET=1

CRIT=0; WARN=0; OK=0
crit(){ echo "  [CRIT] $*"; CRIT=$((CRIT+1)); }
warn(){ echo "  [WARN] $*"; WARN=$((WARN+1)); }
pass(){ OK=$((OK+1)); [ "$QUIET" = 1 ] || echo "  [ OK ] $*"; }
section(){ echo; echo "== $* =="; }

# ---------------------------------------------------------------------------
section "1. Cron-referenced scripts: exist, executable, syntactically valid"
# ---------------------------------------------------------------------------
CRONTAB="$(crontab -l 2>/dev/null)"
cron_scripts="$(printf '%s\n' "$CRONTAB" | grep -v '^#' | grep -oE '\./[A-Za-z0-9_./]+\.(sh|py)|[A-Za-z0-9_/]+overnight-queue/[A-Za-z0-9_./]+\.(sh|py)' | sed -E 's#.*overnight-queue/##; s#^\./##' | sort -u)"
if [ -z "$CRONTAB" ]; then
  warn "crontab is empty or unreadable — cannot audit cron references"
else
  while IFS= read -r s; do
    [ -z "$s" ] && continue
    if [ ! -f "$s" ]; then
      crit "cron references '$s' but it does not exist on disk"
      continue
    fi
    if [ ! -x "$s" ]; then
      warn "'$s' is cron-referenced but not executable (chmod +x)"
    fi
    case "$s" in
      *.sh) bash -n "$s" 2>/tmp/audit_syn_err && pass "$s: syntax OK" || crit "$s: SYNTAX ERROR - $(cat /tmp/audit_syn_err)";;
      *.py) python3 -c "import ast; ast.parse(open('$s').read())" 2>/tmp/audit_syn_err && pass "$s: syntax OK" || crit "$s: SYNTAX ERROR - $(cat /tmp/audit_syn_err)";;
    esac
  done <<< "$cron_scripts"
fi
rm -f /tmp/audit_syn_err

# ---------------------------------------------------------------------------
section "2. Cron jobs actually firing (checked against syslog, not log-file mtime)"
# ---------------------------------------------------------------------------
# NOTE: log-file mtime is NOT a valid liveness signal here — several guard scripts
# (queue_health.sh, pause_guard.sh, lock_guard.sh) are deliberately silent (no output,
# exit 0) on a healthy no-op cycle, so their log can go days without a write while cron
# fires them correctly every cycle. Verified 2026-09-10: exit 0 with empty stdout/stderr
# on a manual healthy run. So this checks the actual cron dispatch record in syslog
# instead, which is what really proves "the schedule is firing."
# oldest file first, current syslog last, so `tail -1` on the concatenated stream
# actually returns the most recent matching line instead of the oldest.
SYSLOG_CAT="cat /var/log/syslog.1 /var/log/syslog 2>/dev/null"
while IFS= read -r line; do
  case "$line" in \#*|"") continue;; esac
  script="$(printf '%s' "$line" | grep -oE '\./[A-Za-z0-9_.-]+\.(sh|py)' | head -1 | sed -E 's#^\./##')"
  [ -z "$script" ] && continue
  min_field="$(printf '%s' "$line" | awk '{print $1}')"
  hour_field="$(printf '%s' "$line" | awk '{print $2}')"
  case "$min_field" in
    '*') interval=1 ;;
    */*) interval="${min_field#*/}" ;;
    *)
      case "$hour_field" in
        '*') interval=60 ;;
        */*) interval=$(( ${hour_field#*/} * 60 )) ;;
        *) interval=1440 ;;
      esac
      ;;
  esac
  threshold=$(( interval * 3 )); [ "$threshold" -lt 15 ] && threshold=15
  last_ts="$(eval "$SYSLOG_CAT" | grep -F "$script" | tail -1 | grep -oE '^[0-9T:.+-]+')"
  if [ -z "$last_ts" ]; then
    warn "$script: no cron dispatch found in syslog (syslog retention may not reach back far enough, or cron never fired it)"
    continue
  fi
  last_epoch="$(date -d "$last_ts" +%s 2>/dev/null || date -jf '%Y-%m-%dT%H:%M:%S' "${last_ts%%.*}" +%s 2>/dev/null)"
  [ -z "$last_epoch" ] && { warn "$script: could not parse syslog timestamp '$last_ts'"; continue; }
  age_min=$(( ( $(date +%s) - last_epoch ) / 60 ))
  if [ "$age_min" -gt "$threshold" ]; then
    warn "$script: cron last dispatched it ${age_min}min ago (expected every ~${interval}min) — cron may have stopped firing"
  else
    pass "$script: cron dispatched it ${age_min}min ago (expected every ~${interval}min)"
  fi
done <<< "$CRONTAB"

# ---------------------------------------------------------------------------
section "3. Scripts called internally by run_overnight.sh: exist + syntax valid"
# ---------------------------------------------------------------------------
internal="$(grep -oE '\$SCRIPT_DIR/[A-Za-z0-9_./]+\.(sh|py)|"\./[A-Za-z0-9_./]+\.(sh|py)"' run_overnight.sh 2>/dev/null | tr -d '"' | sed -E 's#\$SCRIPT_DIR/##; s#^\./##' | sort -u)"
while IFS= read -r s; do
  [ -z "$s" ] && continue
  if [ ! -f "$s" ]; then
    crit "run_overnight.sh calls '$s' but it does not exist"
  else
    pass "run_overnight.sh -> $s exists"
  fi
done <<< "$internal"

# ---------------------------------------------------------------------------
section "4. Active scripts with NO test coverage (grep their basename in scripts/test/*.sh)"
# ---------------------------------------------------------------------------
active="$(printf '%s\n%s\n' "$cron_scripts" "$internal" | sort -u | grep -v '^$')"
while IFS= read -r s; do
  [ -z "$s" ] && continue
  base="$(basename "$s")"
  if grep -rl "$base" scripts/test/*.sh scripts/test/*.py >/dev/null 2>&1; then
    pass "$base: has test coverage"
  else
    warn "$base: NO test file references it (active in cron/run_overnight, untested)"
  fi
done <<< "$active"

# ---------------------------------------------------------------------------
section "5. Locks and zombies"
# ---------------------------------------------------------------------------
for lockfile in state/run.lock state/stage.lock state/reconcile.lock state/sweep.lock; do
  [ -f "$lockfile" ] || continue
  # fuser prints one or more space-separated PIDs on a single line — check each one
  # individually rather than mashing them into one string (which produces garbage).
  holders="$(fuser "$lockfile" 2>/dev/null)"
  holders="${holders#*: }"
  if [ -n "$holders" ]; then
    live=0
    for pid in $holders; do
      if ps -o cmd= -p "$pid" >/dev/null 2>&1; then
        live=1
      fi
    done
    if [ "$live" -eq 1 ]; then
      pass "$lockfile held by live PID(s):$holders"
    else
      crit "$lockfile appears held but none of PID(s)$holders are real processes (orphaned lock)"
    fi
  else
    pass "$lockfile not currently held"
  fi
done
zombie_count=$(ps aux 2>/dev/null | awk '$8 ~ /^Z/' | wc -l | tr -d ' ')
if [ "$zombie_count" -gt 0 ]; then
  warn "$zombie_count zombie process(es) found on the host"
else
  pass "no zombie processes"
fi

# ---------------------------------------------------------------------------
section "6. Core service + connectivity"
# ---------------------------------------------------------------------------
if systemctl is-active --quiet overnight-queue 2>/dev/null; then
  pass "overnight-queue.service is active"
else
  crit "overnight-queue.service is NOT active"
fi
# LiteLLM requires an API key, so /health legitimately returns 401 when the service is UP.
# "Reachable" means we got ANY HTTP response, not specifically a 2xx.
litellm_code="$(curl -s -o /dev/null --max-time 5 -w '%{http_code}' http://localhost:4000/health 2>/dev/null)"
if [ -n "$litellm_code" ] && [ "$litellm_code" != "000" ]; then
  pass "LiteLLM (localhost:4000) is reachable (HTTP $litellm_code)"
else
  crit "LiteLLM (localhost:4000) is NOT reachable — every aider/stage-runner call will fail"
fi
if [ -f state/PAUSED ]; then
  age_min=$(( ( $(date +%s) - $(stat -c %Y state/PAUSED 2>/dev/null || stat -f %m state/PAUSED) ) / 60 ))
  if [ "$age_min" -gt 30 ]; then
    crit "state/PAUSED has existed for ${age_min}min — fleet may be stuck paused (pause_guard.sh should clear stale pauses)"
  else
    warn "state/PAUSED exists (${age_min}min old) — likely mid-dedicated-inference-run, not necessarily a problem"
  fi
else
  pass "fleet is not paused"
fi

# ---------------------------------------------------------------------------
section "7. Repo health: all 7 managed repos exist, on the right branch, clean-ish"
# ---------------------------------------------------------------------------
for r in gitlark iptv_apps shrike-monitor shrike-notify test-automation-agent xlite billwatch; do
  d="repos/$r"
  if [ ! -d "$d/.git" ]; then
    crit "repos/$r is not a git repo (missing entirely?)"
    continue
  fi
  branch="$(git -C "$d" rev-parse --abbrev-ref HEAD 2>/dev/null)"
  dirty="$(git -C "$d" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$dirty" -gt 0 ]; then
    warn "repos/$r ($branch) has $dirty uncommitted change(s) — a human/Claude may be mid-edit, or a cycle died mid-commit"
  else
    pass "repos/$r on $branch, clean"
  fi
done

# ---------------------------------------------------------------------------
section "8. Disk space + outcomes.jsonl sanity"
# ---------------------------------------------------------------------------
avail_pct=$(df -P "$HOME" 2>/dev/null | awk 'NR==2{print 100-$5+0}' | tr -d '%')
if [ -n "$avail_pct" ] && [ "$avail_pct" -lt 10 ]; then
  crit "disk space critically low: only ${avail_pct}% free"
elif [ -n "$avail_pct" ]; then
  pass "disk space OK: ${avail_pct}% free"
fi
if [ -f state/outcomes.jsonl ]; then
  bad_lines=$(python3 -c "
import json
bad = 0
with open('state/outcomes.jsonl') as f:
    for l in f:
        l = l.strip()
        if not l: continue
        try: json.loads(l)
        except Exception: bad += 1
print(bad)
" 2>/dev/null)
  if [ "${bad_lines:-0}" -gt 0 ]; then
    warn "state/outcomes.jsonl has $bad_lines malformed line(s)"
  else
    pass "state/outcomes.jsonl: all lines valid JSON"
  fi
fi

echo
echo "===================================================================="
echo "Pipeline audit: $OK OK, $WARN warnings, $CRIT critical"
echo "===================================================================="
[ "$CRIT" -eq 0 ]
