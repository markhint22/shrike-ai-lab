#!/bin/bash
# ===========================================
# Shrike AI Lab - Overnight Task Runner (SERVER-RESIDENT VERSION)
# ===========================================
# Runs entirely ON the GPU server, scheduled by the overnight-queue.service
# systemd unit (CHANGED 2026-08-15 - was cron, every 2 hours; see below),
# not launchd. This exists because the original Mac-resident version
# (run_overnight.sh) requires the Mac to be awake, plugged in, and reachable
# on the home LAN every night - which breaks the moment the Mac travels and
# isn't reliably connected. This box stays home, stays on, and doesn't
# sleep, so it's the right place for unattended automation to actually live.
#
# CHANGED 2026-08-15: replaced the "every 2 hours" cron entry with a
# continuous systemd loop (Restart=always, RestartSec=20 - see
# /etc/systemd/system/overnight-queue.service). Measured live: the 2-hour
# cadence left the GPU idle ~88% of the time (real work was only ~126 of
# 1080 minutes across 9 cycles in one day), because a cycle finishing in
# 2-20 minutes still had to wait out the rest of the 2-hour window before
# the next one started. The lock file below still exists as a genuine
# safety net (e.g. a manual `queue.sh run-now` overlapping a scheduled
# invocation), not as the primary cadence control anymore.
#
# Two task types:
#   - aider_fix: runs aider against a repo cloned locally under repos/,
#     committing + pushing a branch. Never touches main/develop. Two modes:
#       * one-shot (default): fresh branch off the default branch every run
#         (overnight/<run-key>/<id>) - for a single specific, scoped fix.
#       * persistent_branch:true: reuses ONE fixed branch (overnight/feature)
#         across every run, never resetting it - for an ongoing "review
#         status, pick the next TODO, implement it" task that's meant to
#         accumulate work over many runs/weeks until you review and merge it.
#   - train_job: stops the inference container locally (docker stop),
#     trains locally in ~/shrike-ai-lab-training's venv, then ALWAYS
#     restarts inference afterward (even on failure).
#
# CHANGED 2026-08-04: removed the old "already ran tonight" marker/skip
# logic entirely. That was designed for a once-per-night cron trigger; now
# that this fires continuously (systemd loop, ~20s between cycles) and
# tasks are meant to run every single time they're enabled, a per-calendar-
# day dedup marker would just skip every run after the first each day.
# Cadence is controlled by the systemd unit now - this script always runs
# its full task loop when invoked. Logs and reports are named by a full run
# timestamp (not just date) so multiple same-day runs don't overwrite each
# other's history.
#
# Safety valve: if the SAME task fails 3 runs in a row, THAT TASK is
# auto-disabled (enabled:false in tasks.json) rather than silently burning
# GPU time on a broken task indefinitely. CHANGED 2026-08-08: this
# used to pause the whole queue - live testing showed one structurally-stuck
# task (gitlark repeatedly overflowing context on the same item) took down
# 6 other healthy repos for 4 days with nobody noticing. Now only the
# offending task is disabled; everything else keeps running. Check
# state/failures/<id>.count and the task's own log, fix it, then
# `queue.sh enable <id>`. The global state/PAUSED flag still exists for your
# own manual pause/resume (e.g. during an active chat session) - it's just
# no longer triggered automatically by a single task's failures.
#
# Pause/resume: touch state/PAUSED (from anywhere you can SSH in, e.g. via
# Tailscale from a phone, or `queue.sh pause`) to stop the queue from
# starting further tasks. A task already in progress finishes; pause just
# stops the next one from starting.
#
# Usage:
#   ./run_overnight_server.sh   # always runs the full task loop once
#
# Scheduled continuously by overnight-queue.service (systemd) - nothing
# here depends on the Mac being present, awake, or reachable.
# ===========================================

set -uo pipefail

export PATH="$HOME/aider-venv/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# optional pilot flags (OVN_ARCHITECT / OVN_BESTOF_N / OVN_EDIT_FORMAT) — toggle without restarts
[ -f "$SCRIPT_DIR/state/pilot_flags.env" ] && . "$SCRIPT_DIR/state/pilot_flags.env" || true

LITELLM_MASTER_KEY="${LITELLM_MASTER_KEY:-sk-shrike-local}"
MODEL_NAME="${OVERNIGHT_MODEL:-qwen-dflash-27B}"
LITELLM_BASE="http://localhost:4000"
INFERENCE_CONTAINER="${INFERENCE_CONTAINER:-shrike-llama-dflash-35b}"

# Explicit context-window metadata for aider (2026-08-08 hardening). Without
# this, aider doesn't recognize the custom model name and warns "Unknown
# context window size and costs, using sane defaults" - it can't proactively
# manage/trim context, it just sends and lets the API 400 on overflow (the
# ContextWindowExceededError failures documented throughout this file).
# Confirmed via `curl .../v1/models` that the real ceiling is 16384 tokens.
MODEL_METADATA_FILE="$SCRIPT_DIR/model-metadata.json"

# Shared quality bar, appended to every aider_fix task's prompt (2026-08-08
# hardening) so it doesn't need to be copy-pasted into every task definition
# and applies uniformly to one-off tasks added later via `queue.sh add` too.
STANDARDS_SUFFIX="

HOW TO WORK (follow every call):
You have NO shell. You cannot run tests, pytest, npm, or any command. Never say 'let me run the tests' or 'let me check if it imports' - that burns the whole call and commits nothing. Aider runs the test suite for you AFTER your edit and pastes any failures back; read those and fix your code until the suite is green. That is how work lands.

1. ONE item, minimal focused diff. Edit only the specific file(s) the item names, match the existing style, add no new dependencies unless the item requires them.
2. Write the diff THIS call. One or two sentences of plan, then the change. If you catch yourself still explaining or asking for more files, stop and write the diff with what you already have - a slightly imperfect real change beats a perfect explanation that gets killed at 600s.
3. Keep it compiling and green. A commit that breaks the build (a syntax/import/parse error) is auto-reverted and nothing lands; when aider shows failing tests, fix them before you finish.
4. Report ONLY via commit-message trailer lines - never edit OVERNIGHT_PROGRESS.md, it is read-only and the runner maintains it from your commit:
   DONE: <exact Next Steps item text you finished>
   DECISION: <what you decided and why>   (required when the item is marked NEEDS DECISION)
   NEW: <a short follow-up item>
   DELETE: <path>   (to remove a file - never edit the file to delete it)
5. Do not guess. Use the repo-map and already-open files to find a file's real path and a method's real name/signature before you reference it - a guessed path or API wastes the whole call.
6. If every listed item is blocked or human-only, do not re-argue them - make one small genuine improvement elsewhere (a real bug fix, a docs fix, a safe refactor) and note it with a NEW: trailer.
7. WRITING A TEST? Assert PROPERTIES you can derive by reading the code - a type, a bound/range, monotonicity, idempotence, that it raises on bad input, that a round-trip preserves data, that two code paths agree - NOT a guessed exact number/string. Only hard-code an exact expected value if you can compute it by tracing the code; if you cannot, assert the property instead. A wrong hard-coded expected value that the real code does not produce is the #1 reason the gate reverts your work - it makes your own new test fail. When in doubt, assert less-specifically-but-correctly rather than exactly-but-wrong.

Budget: ~85 tokens/sec, hard-killed at 600s (~40000 tokens) - ample for one complete, correct change. Do not rush out a broken diff to save budget."
TRAINING_DIR="$HOME/shrike-ai-lab-training"

TASKS_FILE="$SCRIPT_DIR/tasks.json"
STATE_DIR="$SCRIPT_DIR/state"

# Per-item outcome log (2026-09-06): one JSONL line per finished item so no-op / flail /
# land / oversized rates are actually measurable (feeds the dashboard + any A/B). Never fatal.
record_outcome(){  # $1=id $2=repo $3=status $4=prompt $5=type $6=attempt $7=task_log $8=duration_s
  local tier cat cls sev st attempt tl src dur
  attempt="${6:-1}"; tl="${7:-}"; dur="${8:-0}"
  # tier + category from the ITEM the model actually saw (task_log has the item text +
  # the file paths it touched), falling back to the task prompt. 2026-09-10: was head -c 6000 -
  # a long AUTO-SKIP-after-N-cycles prefix (often 80-100+ chars) plus normal aider preamble
  # (repo-map, tool-loading, the scout PLAN/VERDICT text) routinely pushed the real [T#] tag
  # past that cutoff before it was ever seen (confirmed live: a real [T1] tag sitting at byte
  # 10116 of a 20604-byte log, past the 6000-byte window). This was the largest remaining
  # source of tier=? in outcome stats after the self-generation-tagging fix - not a missing-tag
  # problem but a truncated-read one. 40000 comfortably covers this class of log with headroom
  # while still bounding a pathological giant pytest-failure dump.
  src="$( { head -c 40000 "$tl" 2>/dev/null; printf ' %s' "${4:-}"; } | tr 'A-Z' 'a-z' )"
  tier="$(printf '%s' "$src" | grep -oE '\[t[1-5]\]|·t[1-5]·' | head -1 | grep -oE '[1-5]' | head -1)"   # explicit tier TAG only (was: any loose t<digit> -> wrong tiers)
  case "$src" in
    *.gd*|*godot*|*gut*)                         cat=godot;;
    *.vue*)                                      cat=vue;;
    *.tsx*|*tsconfig*|*vue-tsc*|*.ts:*|*.ts\ *)  cat=typescript;;
    *router*|*endpoint*|*/api/*|*apirouter*)     cat=endpoint;;
    *schema*|*pydantic*|*validator*)             cat=schema;;
    *refactor*|*multi-file*|*multiple\ files*)    cat=refactor;;
    *docstring*|*readme*|*changelog*|*docs*)     cat=docs;;
    *test_*|*vitest*|*pytest*|*.test.*|*_test.*) cat=test;;
    *.py*)                                       cat=python;;
    *)                                           cat=other;;
  esac
  # class + severity: severity is the "is this actually a problem?" axis.
  #   good=landed  bad=real flail (broke build / faced doable work, produced nothing)
  #   neutral=not-a-model-failure but worth pruning (blocked/ambiguous item, transient error)
  #   expected=normal + not a problem (skipped an exhausted/empty backlog)
  #   fixable=self-inflicted + trimmable (item too big for the context window)
  local sl; sl="$(printf '%s' "$3" | tr 'A-Z' 'a-z')"
  case "$sl" in
    reverted*)                     cls=reverted;  sev=bad;;
    *oversized*)                   cls=oversized; sev=fixable;;
    *blocked*|*needs-decision*|*needs_decision*) cls=noop; sev=neutral;;
    no-op*|noop*)                  cls=noop;      sev=bad;;
    skip*exhausted*|skip*none*|skip*empty*) cls=skipped; sev=expected;;
    skip*)                         cls=skipped;   sev=neutral;;
    error*|fail*)                  cls=error;     sev=neutral;;
    held*)                         cls=held;      sev=neutral;;
    # 2026-09-09 FIX: this used to be a bare `*) cls=landed` catch-all, so ANY status string
    # that didn't match a known failure pattern silently counted as a land - this is exactly
    # how the inline higher-tier sub-flow's unconditional "stage(higher-tier)" echo inflated
    # the T3+ land rate to ~95% when the real rate (per stage_runs/*.jsonl) was ~15-20%. Only
    # classify as landed on an explicit positive signal; anything else is "unknown" so a future
    # unrecognized status is visible in the dashboard instead of silently counted as a success.
    *pushed*|*landed*|*tests:pass*|*done*|trained) cls=landed; sev=good;;
    *)                              cls=unknown;   sev=neutral;;
  esac
  st="$(printf '%s' "$3" | tr -d '"' | cut -c1-80)"
  # fail-cause tag (2026-09-07): stop lumping everything as "flailing" — classify WHY, so the higher-tier
  # pain points are visible + addressable. Only bother when it's not a clean land.
  local fail_reason=""
  if [ "$cls" != "landed" ] && [ -n "$tl" ] && [ -x "$SCRIPT_DIR/ovn_classify_fail.sh" ]; then
    fail_reason="$("$SCRIPT_DIR/ovn_classify_fail.sh" "$tl" "$3" 2>/dev/null)"
  fi
  # 2026-09-09: token spend, so the digest can report real cost by tier (not just pass/fail).
  # Same "Tokens: Xk sent, Y received" parse ovn_stage_runner.sh already uses per-step, applied
  # here to the WHOLE task_log (a cycle can hold multiple aider calls: scout+implement, best-of-N
  # retries, or a staged item's several sub-steps) so this is the item's TOTAL spend this cycle.
  local toks_sent=0 toks_recv=0
  if [ -n "$tl" ] && [ -f "$tl" ]; then
    toks_sent="$(grep -oiE '[0-9.]+k? +sent' "$tl" 2>/dev/null | grep -oiE '^[0-9.]+k?' | awk '/[kK]/{gsub(/[kK]/,"");s+=$1*1000;next}{s+=$1}END{print int(s)}')"; toks_sent="${toks_sent:-0}"
    toks_recv="$(grep -oiE '[0-9.]+k? +received' "$tl" 2>/dev/null | grep -oiE '^[0-9.]+k?' | awk '/[kK]/{gsub(/[kK]/,"");s+=$1*1000;next}{s+=$1}END{print int(s)}')"; toks_recv="${toks_recv:-0}"
  fi
  printf '{"ts":"%s","repo":"%s","id":"%s","type":"%s","tier":"%s","category":"%s","class":"%s","severity":"%s","attempt":%s,"fail_reason":"%s","status":"%s","tokens_sent":%s,"tokens_recv":%s,"duration_s":%s}\n' "$(date -u +%FT%TZ)" "${2:-}" "${1:-}" "${5:-}" "${tier:-?}" "$cat" "$cls" "$sev" "${attempt:-1}" "${fail_reason:-}" "$st" "${toks_sent:-0}" "${toks_recv:-0}" "${dur:-0}" >> "$STATE_DIR/outcomes.jsonl" 2>/dev/null || true
}
FAIL_DIR="$STATE_DIR/failures"
NOOP_DIR="$STATE_DIR/noops"
LOG_DIR="$SCRIPT_DIR/logs"
REPORT_DIR="$SCRIPT_DIR/reports"
mkdir -p "$STATE_DIR" "$FAIL_DIR" "$NOOP_DIR" "$LOG_DIR" "$REPORT_DIR"

PAUSE_FLAG="$STATE_DIR/PAUSED"
ALERTS_FILE="$STATE_DIR/alerts.log"
MAX_CONSECUTIVE_FAILURES=8   # raised from 3 (2026-08-30): only genuine reverts count now, and we tolerate a longer streak during heavy self-gen/refill
# Human-hold auto-expiry (2026-08-25 Tier-2 hardening): a `queue.sh hold <repo>`
# lets a human safely edit a repo's working tree without racing the ~20s loop
# (the runner skips a held repo instead of resetting its tree). Auto-expire a
# forgotten hold so it can't silently freeze a repo for days — the exact
# silent-outage class this batch is closing.
HOLD_MAX_HOURS=6
# No-op streak alert (2026-08-25 Tier-2 hardening): a no-op never trips the
# failure valve (by design — "nothing to do" isn't a failure), so a task that
# silently stops making progress reads as healthy. Alert once when a task
# no-ops this many cycles in a row so "silence == healthy" can't hide a stuck
# backlog. Not a disable — a genuinely-exhausted backlog also no-ops.
NOOP_STREAK_ALERT=30

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# Structured alert sink (2026-08-25 Tier-2 hardening). The runner can't push to
# the phone itself (that's Claude-side), so it appends here; `queue.sh status`
# surfaces recent alerts, and the scheduled Claude supervisor escalates real
# ones to a push. Keep messages one-line.
emit_alert() {
  local sev="$1" id="$2" msg="$3"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] ${sev} | ${id} | ${msg}" >> "$ALERTS_FILE"
  # 2026-09-07: >&2, not stdout. run_aider_fix_task is called as
  # STATUS="$(run_aider_fix_task ...)" at every call site - this function's
  # entire stdout becomes the outcome status string that record_outcome's
  # classifier pattern-matches against (reverted*/no-op*/etc, anchored at the
  # START of the string). emit_alert is called from inside that function at
  # 7 sites (build-gate revert, ts-ratchet revert, red-green-suspect,
  # no-op-streak, auto-disable, divergence-heal...) immediately before the
  # real `echo "<status>"` return - when this line went to stdout, it was
  # captured FIRST, so STATUS became "[timestamp] ALERT(...): ...\n<real
  # status>" instead of just "<real status>". The classifier's anchored
  # patterns never matched, so every one of these real problems silently
  # fell through to the wildcard case (cls=landed, sev=good) in outcomes.jsonl
  # - undermining the exact "landed vs reverted" signal that log is for.
  # stderr is fine here: no call site does `2>&1`, and both stdout+stderr
  # land in the same place either way (systemd journal, no custom
  # StandardOutput/StandardError in the unit file).
  log "ALERT(${sev}) ${id}: ${msg}" >&2
}

# Error classifier (2026-08-25). Distinguishes a TRANSIENT failure (a
# LiteLLM/network blip, rate limit, upstream 5xx — retries fine next cycle) from
# a real one, so a run of transient blips can't falsely trip the 3-strike safety
# valve on an otherwise-healthy task. A ContextWindowExceededError is NOT
# transient (the item is genuinely too big) so it always classifies as real.
# $1 = task log, $2 = the real-error status to fall back to.
error_status() {
  if ! grep -q "ContextWindowExceededError" "$1" 2>/dev/null \
     && grep -qE "RateLimitError|APIConnectionError|APITimeoutError|ServiceUnavailable|Connection (reset|aborted|refused|error)|reset by peer|Max retries exceeded|Read timed out|Temporary failure|50[234] (Bad Gateway|Service|Gateway)" "$1" 2>/dev/null; then
    echo "error-transient(API/network - see log)"
  else
    echo "$2"
  fi
}

# Concurrency lock. Found by live testing (2026-08-08): a slow manual
# `run-now` was still in progress when the next scheduled cron tick fired,
# producing two run_overnight.sh processes walking the same tasks.json
# concurrently - no corruption happened this time, but two processes racing
# git checkout/commit on the same repo checkout is a real risk, and both
# aider calls competing for the one inference container also just slows
# everything down further, making the next overlap more likely. Non-blocking:
# if another run is already in progress, skip this invocation entirely
# rather than queue up behind it - the next cron tick will pick up any
# skipped work anyway.
LOCK_FILE="$STATE_DIR/run.lock"
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
  log "Another run_overnight.sh is already in progress (lock: ${LOCK_FILE}) — skipping this invocation entirely."
  exit 0
fi

RUN_KEY="$(date +%Y%m%d-%H%M%S)"
LOG_RUN_DIR="$LOG_DIR/$RUN_KEY"
mkdir -p "$LOG_RUN_DIR"
REPORT_FILE="$REPORT_DIR/${RUN_KEY}.md"

if [ -f "$PAUSE_FLAG" ]; then
  log "Queue is paused (${PAUSE_FLAG} exists). Skipping this run entirely."
  exit 0
fi

write_abort_report() {
  {
    echo "# Overnight run report — ${RUN_KEY}"
    echo ""
    echo "**Aborted**: $1"
  } > "$REPORT_FILE"
}

# Quick local check only - no long wait loop needed since this script only
# runs on the box that IS the GPU server.
if ! curl -sf --max-time 10 "${LITELLM_BASE}/health/liveliness" >/dev/null 2>&1 \
    && ! curl -sf --max-time 10 "${LITELLM_BASE}/health" >/dev/null 2>&1; then
  log "LiteLLM (${LITELLM_BASE}) not responding. Aborting this run."
  write_abort_report "LiteLLM (${LITELLM_BASE}) was not reachable — check \`docker ps\` on this box."
  exit 1
fi

if ! command -v aider >/dev/null 2>&1; then
  log "aider not found on PATH. Aborting."
  write_abort_report "\`aider\` not found on PATH — check ~/aider-venv/bin/aider exists."
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  log "jq not found on PATH. Aborting."
  write_abort_report "\`jq\` not found on PATH."
  exit 1
fi

if ! curl -sf --max-time 10 -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" "${LITELLM_BASE}/v1/models" \
    | grep -q "\"${MODEL_NAME}\""; then
  log "WARNING: model '${MODEL_NAME}' not found in ${LITELLM_BASE}/v1/models — continuing anyway."
fi

TASK_COUNT="$(jq 'length' "$TASKS_FILE")"
log "Loaded ${TASK_COUNT} task(s) from ${TASKS_FILE}"

{
  echo "# Overnight run report — ${RUN_KEY}"
  echo ""
  echo "Model: \`${MODEL_NAME}\` via ${LITELLM_BASE} (server-resident run)"
  echo ""
  echo "| Task | Type | Status | Branch/Version | Log |"
  echo "|---|---|---|---|---|"
} > "$REPORT_FILE"

# Post-commit test verification (2026-08-08 hardening). Best-effort: only
# runs suites that are ALREADY provisioned (a real .venv with pytest, or
# node_modules already installed) - never installs anything itself, so it's
# a safe no-op ("none") on a repo that hasn't been provisioned, rather than
# attempting a slow/flaky unattended `npm install`/`pip install` every
# cycle. Must be called with cwd already inside the target repo. Appends
# real output to $task_log (global, set by the caller) and returns one of:
# "pass" (something ran and all green), "fail" (something ran, at least one
# failure), "none" (nothing provisioned to run).
run_repo_verification() {
  local any_ran=0 any_failed=0 dir
  # 2026-08-27: scope each suite to the subdirs THIS cycle's commit(s) touched,
  # so a backend-only change never triggers an unrelated (e.g. broken Android)
  # build and mislabels a green change as tests:FAIL.
  local _OVN_CHANGED
  _OVN_CHANGED="$(git diff --name-only "${BEFORE_SHA:-HEAD~1}" HEAD 2>/dev/null || true)"
  _ovn_touched() {
    local d="${1#./}"
    [ -z "$_OVN_CHANGED" ] && return 0    # unknown -> run (safe default)
    [ "$d" = "." ] && return 0            # root-level project -> always run
    printf '%s\n' "$_OVN_CHANGED" | grep -q "^${d}/" && return 0
    return 1
  }

  # Per-repo verify override (2026-08-29 v2): if the repo ships an .ovn-verify.sh
  # anywhere (maxdepth 3) it OWNS verification - run ONLY that (pinned interpreter,
  # coverage-gate bypass, correct tree, web-vitest-run, whatever the repo needs) and
  # skip the default dir-walking. Works regardless of venv naming (.venv vs venv).
  local _ovnv
  _ovnv="$(find . -maxdepth 3 -type f -name '.ovn-verify.sh' 2>/dev/null | head -1)"
  if [ -n "$_ovnv" ]; then
    # 2026-09-09 FIX: raised 240s -> 600s. iptv_apps's unscoped full-suite .ovn-verify.sh (deliberately
    # NOT scoped to changed files - see the 2026-08-15 comment below, a scoped verify once let a real
    # full-suite break slip through) measured 356s today (1436 tests, up from 657 when the cap was last
    # raised to 240 on 2026-08-15 - "and growing" in that comment was exactly right). Every single cycle
    # touching the backend was GUARANTEED to hit the 240s cap, get misread by NO-NEW-RED GUARD as "tests
    # red", and revert fully-green, fully-passing work - confirmed 97+ false reverts in <2 days from
    # this alone. The other repos on this same override path (gitlark: smartly scoped; test-automation-
    # agent/shrike-monitor/shrike-notify: all sub-second full suites) have real headroom under 600s too.
    echo "--- verify: $_ovnv (repo-owned, 600s cap) ---" >> "$task_log"
    if ( cd "$(dirname "$_ovnv")" && OVN_CHANGED_FILES="$_OVN_CHANGED" timeout 600 bash "$(basename "$_ovnv")" ) >> "$task_log" 2>&1; then
      echo "pass"
    else
      echo "fail"
    fi
    return
  fi

  while IFS= read -r -d '' venv_pytest; do
    dir="${venv_pytest%/.venv/bin/pytest}"
    if ! _ovn_touched "$dir"; then echo "--- skip pytest in ${dir}: commit did not touch it ---" >> "$task_log"; continue; fi
    # 240s (2026-08-15, was 120s): confirmed live, repeatedly, that
    # iptv_apps's full backend suite (657+ tests and growing) genuinely
    # takes 200+ seconds to run in full. At 120s the cap fired on EVERY
    # cycle regardless of whether tests actually passed, timeout's exit
    # code got treated as a real failure, and every report said
    # "tests:FAIL" even when the suite was 100% green - a misleading
    # signal that would only get worse as more tests get added.
    # Per-repo targeted-verify override (2026-08-29): repos whose FULL suite is too
    # slow (gitlark ~24min: pydantic slow-import + slow async tests) or hangs
    # (billwatch test_auth) ship a fast .ovn-verify.sh that runs only the tests
    # covering this cycle's change. It gets $OVN_CHANGED_FILES and must exit
    # 0=green / non-0=red. Keeps the queue verifiable without the 240s cap firing.
    if [ -x "${dir}/.ovn-verify.sh" ]; then
      # 2026-09-09: same 240s->600s raise as the repo-root override path above (see that comment).
      echo "--- verify: .ovn-verify.sh override in ${dir} (600s cap) ---" >> "$task_log"
      ( cd "$dir" && OVN_CHANGED_FILES="$_OVN_CHANGED" timeout 600 ./.ovn-verify.sh ) >> "$task_log" 2>&1
      [ $? -ne 0 ] && any_failed=1
      any_ran=1
      continue
    fi
    echo "--- verify: pytest in ${dir} (240s cap) ---" >> "$task_log"
    ( cd "$dir" && timeout 240 ./.venv/bin/pytest -q --no-cov ) >> "$task_log" 2>&1
    [ $? -ne 0 ] && any_failed=1
    any_ran=1
  done < <(find . -maxdepth 4 -type f -path "*/.venv/bin/pytest" -print0 2>/dev/null)

  while IFS= read -r -d '' pkg; do
    dir="$(dirname "$pkg")"
    if ! _ovn_touched "$dir"; then echo "--- skip npm test in ${dir}: commit did not touch it ---" >> "$task_log"; continue; fi
    if [ -d "${dir}/node_modules" ] && grep -q '"test"[[:space:]]*:' "$pkg"; then
      echo "--- verify: npm test in ${dir} (120s cap - if this project's test script defaults to interactive watch mode, this will time out rather than hang forever; check the log) ---" >> "$task_log"
      # CI=true: several repos' "test" script is plain "vitest" (not
      # "vitest --run"), which defaults to interactive watch mode outside
      # CI and would hang until the timeout kills it - vitest/Jest/CRA all
      # respect CI=true to run once and exit instead.
      ( cd "$dir" && CI=true timeout 120 npm test --silent ) >> "$task_log" 2>&1
      [ $? -ne 0 ] && any_failed=1
      any_ran=1
    fi
  done < <(find . -maxdepth 4 -type f -name "package.json" -not -path "*/node_modules/*" -print0 2>/dev/null)

  # Android (Gradle) - added 2026-08-14 after finding a repo where a
  # non-compiling 2-line stub file had been sitting committed for a full
  # day: nothing was ever running ./gradlew to catch it, since the server
  # had no JDK/Android SDK installed at all until this same day. Requires
  # ANDROID_HOME set (see setup: JDK 17 + cmdline-tools + platform-34 +
  # build-tools;34.0.0 installed at $HOME/android-sdk).
  while IFS= read -r -d '' gradlew; do
    dir="$(dirname "$gradlew")"
    if ! _ovn_touched "$dir"; then echo "--- skip gradle test in ${dir}: commit did not touch it ---" >> "$task_log"; continue; fi
    if [ -f "${dir}/settings.gradle.kts" ] || [ -f "${dir}/settings.gradle" ]; then
      echo "--- verify: ./gradlew test in ${dir} (240s cap) ---" >> "$task_log"
      (
        cd "$dir" &&
        export ANDROID_HOME="$HOME/android-sdk" &&
        [ -f local.properties ] || echo "sdk.dir=$ANDROID_HOME" > local.properties &&
        timeout 240 ./gradlew test --console=plain
      ) >> "$task_log" 2>&1
      [ $? -ne 0 ] && any_failed=1
      any_ran=1
    fi
  done < <(find . -maxdepth 3 -type f -name "gradlew" -print0 2>/dev/null)

  # Godot (GDScript) - added 2026-08-16 for the xlite onboarding. Godot's own
  # process exit code cannot be trusted AT ALL for pass/fail here: confirmed
  # live that a raw `--quit-after` scene run exits 0 even with a real
  # "Could not find type X" parse error, AND that GUT's own -gexit /
  # -gexit_on_success flags ALSO always exit 0 regardless of test outcome
  # (tested with a deliberately-broken assertion). --import must run first
  # and separately: a fresh clone has no .godot/ cache (gitignored), so any
  # class_name-declared script (this project's convention for every
  # gameplay class) fails to resolve until the cache is built. Requires
  # $HOME/godot/godot4 (Godot 4.3 headless Linux build, installed once, not
  # project-specific). IMPORTANT: GUT 9.4.0 is the version that actually
  # supports Godot 4.3.x - the newer 9.7.x line requires Godot 4.7.x and
  # fails to even parse ("Could not resolve class GutErrorTracker") on 4.3 -
  # check plugin.cfg's version before ever upgrading addons/gut here.
  while IFS= read -r -d '' godot_proj; do
    dir="$(dirname "$godot_proj")"
    if [ -x "$HOME/godot/godot4" ]; then
      GODOT_OUT="$(mktemp)"
      if [ -f "${dir}/addons/gut/gut_cmdln.gd" ]; then
        # GUT installed: real per-test pass/fail via JUnit XML, not exit code.
        echo "--- verify: GUT tests in ${dir} (90s cap) ---" >> "$task_log"
        XML_OUT="$(mktemp)"
        (
          cd "$dir" &&
          timeout 60 "$HOME/godot/godot4" --headless --path . --import >/dev/null 2>&1; timeout 60 "$HOME/godot/godot4" --headless --path . --import &&
          timeout 30 "$HOME/godot/godot4" --headless -s addons/gut/gut_cmdln.gd \
            -gdir=res://tests -gexit "-gjunit_xml_file=${XML_OUT}"
        ) > "$GODOT_OUT" 2>&1
        cat "$GODOT_OUT" >> "$task_log"
        [ -f "$XML_OUT" ] && cat "$XML_OUT" >> "$task_log"
        # failures="0" alone is NOT enough: confirmed live that a test calling a
        # nonexistent function throws a runtime script error, silently never
        # reaches its assertion, and GUT reports it as status="no asserts"
        # (Risky) rather than a failure - the JUnit failures count stays 0 even
        # though the test proved nothing. Treat any no-asserts testcase as a
        # real failure too.
        if [ ! -s "$XML_OUT" ] || ! grep -qE 'failures="0"' "$XML_OUT" || grep -qE 'status="no asserts"' "$XML_OUT"; then
          any_failed=1
        fi
        # GUT only tests res://tests - a genuine compile error elsewhere in the
        # project (confirmed live: a new script with a bad type annotation broke
        # battle.gd's loadability entirely) can coexist with a clean GUT run,
        # since GUT never touches that file. $GODOT_OUT already has the --import
        # step's own output (runs before GUT) - check it too.
        { grep -E "SCRIPT ERROR|Parse Error|ERROR: Failed to load" "$GODOT_OUT" | grep -vE "has no resource loaders|Cannot call method '[^']*' on a null value|AudioStreamOggVorbis|base object of type 'Nil'|Attempted to free a RefCounted|Parameter .* is null" | grep -q .; } && any_failed=1
        rm -f "$XML_OUT"
      else
        # No test framework yet: just confirm the project still parses/runs.
        echo "--- verify: godot4 --headless in ${dir} (90s cap, no GUT yet) ---" >> "$task_log"
        (
          cd "$dir" &&
          timeout 60 "$HOME/godot/godot4" --headless --path . --import >/dev/null 2>&1; timeout 60 "$HOME/godot/godot4" --headless --path . --import &&
          timeout 30 "$HOME/godot/godot4" --headless --path . --quit-after 60
        ) > "$GODOT_OUT" 2>&1
        cat "$GODOT_OUT" >> "$task_log"
        { grep -E "SCRIPT ERROR|Parse Error|ERROR: Failed to load" "$GODOT_OUT" | grep -vE "has no resource loaders|Cannot call method '[^']*' on a null value|AudioStreamOggVorbis|base object of type 'Nil'|Attempted to free a RefCounted|Parameter .* is null" | grep -q .; } && any_failed=1
      fi
      rm -f "$GODOT_OUT"
      any_ran=1
    fi
  done < <(find . -maxdepth 3 -type f -name "project.godot" -print0 2>/dev/null)

  if [ "$any_ran" -eq 0 ]; then
    echo "none"
  elif [ "$any_failed" -eq 1 ]; then
    echo "fail"
  else
    echo "pass"
  fi
}

# Red-green verification (2026-08-25 Tier-3 hardening). Makes "tests pass" mean
# "the test earned its pass." For a BUGFIX commit (changes BOTH non-test source
# AND test files), a genuine regression test must FAIL against the pre-fix
# source. If the new test(s) still PASS with the source reverted, the test is
# vacuous or mirrors the bug's own wrong assumption - a failure mode seen
# repeatedly here (e.g. a settings int-vs-string test that passed because it
# made the exact same mistake as the code it was "testing"). ADVISORY ONLY:
# reports + alerts, never auto-disables (green is already covered by
# run_repo_verification; the runner can't tell a true regression from a flake).
# Skips pure coverage-adds (no source change) and non-pytest repos. Must run
# with cwd at the repo root (as inside run_aider_fix_task's subshell).
# Echoes: "ok" | "suspect" | "n/a".
run_redgreen_check() {
  local before="$1" after="$2"
  local changed tests src test_re='(^|/)(test_[^/]*|[^/]*_test)\.py$|/tests?/.*\.py$'
  changed="$(git diff --name-only "$before" "$after")"
  tests="$(echo "$changed" | grep -E "$test_re" || true)"
  src="$(echo "$changed" | grep -E '\.py$' | grep -vE "$test_re" || true)"
  [ -z "$tests" ] && { echo "n/a"; return; }
  [ -z "$src" ] && { echo "n/a"; return; }   # coverage-only add, not a bugfix

  local venv_pytest dir dir_rel
  venv_pytest="$(find . -maxdepth 4 -type f -path '*/.venv/bin/pytest' 2>/dev/null | head -1)"
  [ -z "$venv_pytest" ] && { echo "n/a"; return; }
  dir="${venv_pytest%/.venv/bin/pytest}"
  dir_rel="${dir#./}"

  # Make the changed test paths relative to the venv's dir (repos commonly keep
  # .venv + tests under backend/), and only run tests that live under it.
  local dtests="" t
  for t in $tests; do
    if [ "$dir_rel" = "." ]; then
      dtests="$dtests $t"
    else
      case "$t" in "$dir_rel"/*) dtests="$dtests ${t#"$dir_rel"/}" ;; esac
    fi
  done
  [ -z "$dtests" ] && { echo "n/a"; return; }

  # Revert ONLY the source to pre-fix (keep the new tests), run just the new
  # tests, then restore. Cleanup restores source even if pytest is killed.
  echo "--- red-green: running new test(s) against pre-fix source ---" >> "$task_log"
  git checkout "$before" -- $src 2>>"$task_log"
  local rc=0
  ( cd "$dir" && timeout 120 ./.venv/bin/pytest -q --no-cov $dtests ) >> "$task_log" 2>&1 || rc=$?
  git checkout "$after" -- $src 2>>"$task_log"

  # rc==0 means the new tests PASSED without the fix -> they don't exercise it.
  if [ "$rc" -eq 0 ]; then echo "suspect"; else echo "ok"; fi
}

# Lint/format check (2026-08-25 improvement #5, advisory). Runs the repo's own
# linter on ONLY the files THIS commit changed - not the whole repo, which is
# all pre-existing noise - so it surfaces a style/type regression the change
# introduced. Advisory: reported as [lint:N] on the push status, never fails
# verification or trips the valve. Uses ruff (python) / eslint (js/ts) when
# already provisioned; silent no-op otherwise. Must run with cwd at repo root.
# Echoes an integer issue count.
run_lint_check() {
  local before="$1" after="$2" issues=0 changed n
  changed="$(git diff --name-only "$before" "$after" 2>/dev/null)"
  local pyfiles ruff
  pyfiles="$(echo "$changed" | grep -E '\.py$' | grep -vE '/(migrations|\.venv)/' || true)"
  if [ -n "$pyfiles" ]; then
    ruff="$(find . -maxdepth 4 -path '*/.venv/bin/ruff' 2>/dev/null | head -1)"
    [ -z "$ruff" ] && command -v ruff >/dev/null 2>&1 && ruff="ruff"
    if [ -n "$ruff" ]; then
      n="$("$ruff" check --quiet $pyfiles 2>/dev/null | grep -cE '^[^[:space:]]' || true)"
      issues=$((issues + ${n:-0}))
    fi
  fi
  local jsfiles eslint
  jsfiles="$(echo "$changed" | grep -E '\.(js|ts|jsx|tsx|vue)$' | grep -v '/node_modules/' || true)"
  if [ -n "$jsfiles" ]; then
    eslint="$(find . -maxdepth 3 -path '*/node_modules/.bin/eslint' 2>/dev/null | head -1)"
    if [ -n "$eslint" ]; then
      n="$("$eslint" --format unix $jsfiles 2>/dev/null | grep -cE ':[0-9]+:[0-9]+:' || true)"
      issues=$((issues + ${n:-0}))
    fi
  fi
  echo "${issues:-0}"
}

# Coverage-on-diff signal (2026-08-25 improvement #3, advisory). A cheap
# deterministic proxy for "did this change ship with a test": if the commit ADDS
# new definitions (def/class/func/function) but touches NO test file, flag
# [untested-change]. Complements red-green (which checks a test that IS present).
# Advisory only. Echoes "ok" | "untested".
run_coverage_check() {
  local before="$1" after="$2" changed testchanged newdefs
  changed="$(git diff --name-only "$before" "$after" 2>/dev/null)"
  testchanged="$(echo "$changed" | grep -cE '(^|/)(test_|tests/).*\.(py|gd)$|\.(test|spec)\.(js|ts|jsx|tsx)$' || true)"
  [ "${testchanged:-0}" -gt 0 ] && { echo "ok"; return; }
  newdefs="$(git diff "$before" "$after" -- '*.py' '*.ts' '*.js' '*.jsx' '*.tsx' '*.gd' 2>/dev/null | grep -cE '^\+[[:space:]]*(def |class |func |export (async )?function |function )' || true)"
  [ "${newdefs:-0}" -ge 1 ] && echo "untested" || echo "ok"
}

run_aider_fix_task() {
  local id="$1" repo="$2" prompt="$3" branch="$4" persistent="$5" task_log="$6" map_tokens="$7" skip_agents_md="$8" max_files="${9:-2}" protected_files="${10:-}" aider_timeout="${11:-600}"

  if [ ! -d "$repo/.git" ]; then
    log "Repo ${repo} has no .git checkout — skipping"
    echo "error: no .git at ${repo}"
    return
  fi

  (
    cd "$repo" || exit 1

    DEFAULT_BRANCH="$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's@^origin/@@')"
    DEFAULT_BRANCH="${DEFAULT_BRANCH:-main}"
    git fetch origin "$DEFAULT_BRANCH" --quiet 2>/dev/null
    git fetch origin "$branch" --quiet 2>/dev/null

    if [ "$persistent" = "true" ] && git rev-parse --verify --quiet "$branch" >/dev/null; then
      # Branch already exists locally from a previous run - keep building on
      # it, don't reset (that would discard all prior accumulated work).
      git checkout "$branch" --quiet
    elif [ "$persistent" = "true" ] && git rev-parse --verify --quiet "origin/${branch}" >/dev/null; then
      # Exists on the remote (e.g. queue restarted) but not local yet.
      git checkout -B "$branch" "origin/${branch}" --quiet
    elif ! git checkout -B "$branch" "origin/${DEFAULT_BRANCH}" --quiet 2>/dev/null; then
      git checkout -B "$branch" "$DEFAULT_BRANCH" --quiet
    fi

    # Pre-cycle local-clone sync (2026-08-25 Tier-2 hardening). Root cause of
    # the 2026-08-24 "silently disabled for 10 days" incident: a human salvage
    # fast-forwarded origin/overnight/feature past a bug the local clone had
    # failed on, but the runner only ever checked out the LOCAL branch as-is
    # (above) and never reconciled it with origin — so the clone kept
    # re-attempting an item that origin had already fixed. Fix, data-loss-safe:
    #   - local strictly BEHIND origin (local is an ancestor of origin): the
    #     human advanced origin — fast-forward the clone to match. No local-only
    #     commits exist to lose.
    #   - local strictly ahead (normal steady state — it pushes each cycle): do
    #     nothing, the push at the end reconciles.
    #   - genuinely DIVERGED (e.g. a human force-RESET origin back, discarding
    #     commits the clone still has): do NOT auto-resolve — a reset here could
    #     drop unpushed work. Flag once (deduped) for a human to reconcile.
    if [ "$persistent" = "true" ] && git rev-parse --verify --quiet "origin/${branch}" >/dev/null; then
      LOCAL_HEAD="$(git rev-parse HEAD)"
      ORIGIN_HEAD="$(git rev-parse "origin/${branch}")"
      DIVERGE_FLAG="$STATE_DIR/diverged_${id}"
      if [ "$LOCAL_HEAD" != "$ORIGIN_HEAD" ]; then
        if git merge-base --is-ancestor "$LOCAL_HEAD" "$ORIGIN_HEAD"; then
          echo "--- local ${branch} was behind origin; fast-forwarding clone to origin/${branch} ---" >> "$task_log"
          git reset --hard "origin/${branch}" --quiet
          rm -f "$DIVERGE_FLAG"
        elif git merge-base --is-ancestor "$ORIGIN_HEAD" "$LOCAL_HEAD"; then
          rm -f "$DIVERGE_FLAG"
        elif [ "$ORIGIN_HEAD" = "$(git rev-parse origin/main 2>/dev/null)" ]; then
          # 2026-08-28: diverged BUT origin/${branch} == origin/main means
          # branch-hygiene merged this branch to main and reset it; the local
          # divergent commits are post-merge stragglers on a now-dead base and
          # cannot fast-forward push. Safe to reset the clone to the merged
          # baseline so the runner makes forward progress (stragglers stay in
          # reflog). This is the every-3h hygiene-orphan case, NOT a human
          # force-reset — those (origin != main) still fall through to the flag.
          echo "--- local ${branch} diverged but origin==main (hygiene merged); resetting clone ---" >> "$task_log"
          git reset --hard "origin/${branch}" --quiet
          rm -f "$DIVERGE_FLAG"
        else
          # 2026-09-06 data-loss-safe auto-heal: a genuinely-diverged clone used to be
          # flagged + left untouched, which no-op'd the item FOREVER (iptv hit 31 cycles).
          # Instead: preserve every local commit in a backup branch (nothing is ever lost),
          # reset the clone to origin so the fleet makes progress, and alert to review the
          # backup for any real unlanded work to re-land. Not a human force-reset case.
          bkp="backup-diverged-${id}-$(date +%Y%m%d-%H%M%S)"
          git branch -f "$bkp" "$LOCAL_HEAD" >/dev/null 2>&1
          echo "--- local ${branch} DIVERGED (origin != main); backed up to $bkp, resetting clone to origin ---" >> "$task_log"
          git reset --hard "origin/${branch}" --quiet
          rm -f "$DIVERGE_FLAG"
          emit_alert warn "$id" "local ${branch} DIVERGED — auto-healed: local commits saved to branch $bkp, clone reset to origin so the fleet keeps moving. Review $bkp for any unlanded work to re-land."
        fi
      else
        rm -f "$DIVERGE_FLAG"
      fi
    fi

    # Discovered by live testing: this model's udiff output is reliable for
    # editing existing files, but unreliable for synthesizing a brand-new
    # prose file from scratch - it sometimes emits a hunk aider can't apply
    # at all (silent no-op), and sometimes an empty 0-byte file gets
    # committed. Sidestep this entirely by having bash stub the file out
    # first (plain heredoc, no LLM involved) whenever the task's prompt
    # references it - aider then only ever has to EDIT an existing file,
    # which it does reliably.
    if [[ "$prompt" == *"OVERNIGHT_PROGRESS.md"* ]] && [ ! -f "OVERNIGHT_PROGRESS.md" ]; then
      cat > OVERNIGHT_PROGRESS.md <<'STUB'
# Overnight Progress

## Current Status
(not yet reviewed)

## Next Steps
(not yet populated)
STUB
      git add OVERNIGHT_PROGRESS.md
      git commit -m "chore: stub OVERNIGHT_PROGRESS.md" --quiet
    fi

    BEFORE_SHA="$(git rev-parse HEAD)"

    # OVERNIGHT_PROGRESS.md is always pre-loaded, not counted against
    # max_files - it's the queue's own bookkeeping doc (typically 1-2KB) and
    # was previously never actually added to the chat (excluded from
    # scan_for_new_files as a .md file), meaning the model edited it "blind"
    # without ever seeing its real current content - the likely cause of the
    # duplicate "Next Steps" sections found in iptv_apps and
    # test-automation-agent (2026-08-13).
    #
    # Read-only for the scout pass, editable only for implement (2026-08-15
    # hardening): scout's only job is to reply with a file list - it never
    # needs to WRITE to this doc. Live logs showed the model repeatedly
    # opening implement attempts by re-diffing the entire Next Steps list
    # back into its own response before ever touching real code, burning
    # most of the 600s budget on pure restatement despite an explicit prompt
    # instruction not to. Giving edit access only where it's actually needed
    # removes the affordance instead of just asking nicely not to use it -
    # the same lesson as the scout --no-auto-commits fix.
    # 2026-08-25 Tier-1 (deterministic bookkeeping): the doc is now READ-ONLY to
    # the model in BOTH passes. The runner owns every edit (update_progress.py,
    # applied from DONE:/DECISION:/NEW: trailers in the commit message after a
    # verified push) — so the model can no longer duplicate headers, re-add done
    # items, renumber wrong, or burn its budget on doc surgery. PROGRESS_FILE_ARGS
    # is kept (empty) so any remaining reference expands to nothing safely.
    PROGRESS_READ_ARGS=()
    PROGRESS_FILE_ARGS=()
    # Pre-cycle sanitizer (2026-08-30): retire unchecked items that name NO
    # file - the scout's file-loading loop cannot act on them, so they block
    # every cycle (no-op(BLOCKED), the dominant no-op class). Deterministic;
    # runs BEFORE the scout picks an item. Commits so the retirement sticks.
    if [ -f "OVERNIGHT_PROGRESS.md" ] && [ -f "$SCRIPT_DIR/scripts/ovn_retire_vague.py" ]; then
      _RV="$(python3 "$SCRIPT_DIR/scripts/ovn_retire_vague.py" OVERNIGHT_PROGRESS.md 2>>"$task_log" | grep -E "retired [1-9]" || true)"
      if [ -n "$_RV" ] && ! git diff --quiet -- OVERNIGHT_PROGRESS.md 2>/dev/null; then
        echo "--- sanitizer: ${_RV} ---" >> "$task_log"
        git add OVERNIGHT_PROGRESS.md
        git commit -m "chore(queue): retire vague no-file items (auto-sanitizer)" --quiet 2>>"$task_log" || true
      fi
    fi

    # Self-generation low-water-mark (Option C, 2026-08-30): when a repo is
    # running low on genuine work, deterministically generate SAFE mechanical
    # items ($0, no LLM, no hallucination) so it doesn't idle/no-op. Backstops
    # the periodic Claude refills. Only safe patterns (bare-except, rel=noopener,
    # __repr__ -> str, __init__ -> None); the no-new-red gate catches any miss.
    if [ -f "OVERNIGHT_PROGRESS.md" ] && [ -f "$SCRIPT_DIR/scripts/ovn_generate_items.py" ]; then
      _DOABLE="$(grep -E '^- \[ \]' OVERNIGHT_PROGRESS.md 2>/dev/null | grep -viE 'HUMAN-ONLY|human/|AUTO-SKIP|BLOCKED ITEM|retired-' | wc -l | tr -d ' ')"
      if [ "${_DOABLE:-9}" -le 3 ]; then
        _GEN="$(python3 "$SCRIPT_DIR/scripts/ovn_generate_items.py" . 12 2>>"$task_log")"
        if echo "$_GEN" | grep -qE 'GENERATED=[1-9]'; then
          echo "--- self-gen: $_GEN (repo low on work, deterministic top-up) ---" >> "$task_log"
          git add OVERNIGHT_PROGRESS.md
          git commit -q -m "chore(queue): auto-generate safe mechanical items (self-generation, repo was low)" 2>>"$task_log" || true
        fi
      fi
    fi

    # Exhausted-repo skip (2026-08-31): after self-gen has had its chance, if the
    # repo has NO doable items left, skip the scout+implement entirely instead of
    # feeding the model an empty backlog it can only no-op on. An exhausted repo
    # (mechanically drained, or unverifiable-only like xlite gdscript that self-gen
    # cannot refill) should not burn a cycle + tokens on a guaranteed no-op; it
    # resumes automatically once it has work again. Reported as skip(exhausted),
    # tracked apart from real "faced work, did not land" no-ops.
    if [ -f "OVERNIGHT_PROGRESS.md" ]; then
      _DOABLE_NOW="$(grep -E '^- \[ \]' OVERNIGHT_PROGRESS.md 2>/dev/null | grep -viE 'HUMAN-ONLY|human/|AUTO-SKIP|BLOCKED ITEM|retired-' | wc -l | tr -d ' ')"
      if [ "${_DOABLE_NOW:-1}" -eq 0 ]; then
        echo "--- skip: 0 doable items (exhausted; resumes when refilled) ---" >> "$task_log"
        echo "skip(exhausted)"
        return
      fi
    fi

    # HIGHER-TIER SUB-FLOW (inline, 2026-09-08): if this repo has a doable non-godot T3+ item, hand it
    # to the multi-stage runner (decompose -> per-step aider+gate -> independent verify) RIGHT HERE in
    # the fleet's own serial slot. Because we ARE the fleet and already hold the GPU, no pause/dedicate
    # is needed (OVN_STAGE_DEDICATE=0) — there is structurally NOTHING to contend with, so higher-tier
    # items can never be timed out by a concurrent fleet aider. This REPLACES the old separate paused
    # sweep: same queue, one serial loop, tier just selects the flow. Lower-tier items fall through to
    # the normal scout+implement below. The runner auto-picks its own T3+ python item and checks it off.
    if [ "${OVN_INLINE_STAGE:-1}" = 1 ] && [ -f "OVERNIGHT_PROGRESS.md" ] \
       && grep -E '^- \[ \] ' OVERNIGHT_PROGRESS.md 2>/dev/null \
          | grep -vE 'AUTO-SKIP|HUMAN-ONLY|BLOCKED' | grep -E '\[T[345]\]|·T[345]·' \
          | grep -qviE '\.gd\b'; then
      echo "--- higher-tier sub-flow (inline in fleet slot; no pause, no contention) ---" >> "$task_log"
      ( cd "$SCRIPT_DIR" && OVN_STAGE_DEDICATE=0 timeout 1500 bash ovn_stage_runner.sh "$(basename "$repo")" ) >> "$task_log" 2>&1
      # 2026-09-09 FIX: this used to unconditionally echo "stage(higher-tier)" regardless of what
      # the stage runner actually did. That string matches none of record_outcome's known status
      # prefixes, so it fell through to the catch-all `*) cls=landed` case - EVERY inline higher-tier
      # attempt was counted as a land, inflating the T3+ "land rate" to ~95% when the stage runner's
      # own summary events showed the real rate was ~15-20% (state/stage_runs/*.jsonl: verified=True
      # only ~20% of runs). Read that repo's most recent stage-runs summary and classify honestly.
      _STAGE_SUMMARY="$(ls -t "$SCRIPT_DIR"/state/stage_runs/"$(basename "$repo")"-*.jsonl 2>/dev/null | head -1 | xargs -r grep '"event":"summary"' | tail -1)"
      _STAGE_PUSHED="$(printf '%s' "$_STAGE_SUMMARY" | grep -oE '"commits_pushed":[0-9]+' | grep -oE '[0-9]+$')"
      if [ -n "$_STAGE_PUSHED" ] && [ "$_STAGE_PUSHED" -gt 0 ]; then
        echo "pushed(tests:pass) stage(higher-tier)"
      else
        echo "no-op(stage-unverified) stage(higher-tier)"
      fi
      return
    fi

    # Re-capture BEFORE_SHA AFTER the sanitizer + self-gen maintenance commits
    # (2026-08-30 CRITICAL FIX): BEFORE_SHA was taken earlier, so every later
    # `git reset --hard "$BEFORE_SHA"` (scout-reset, residue-guard, red revert)
    # DISCARDED the freshly-generated/retired items - backlogs never refilled and
    # empty repos stayed empty forever (0 doable despite self-gen making 12).
    BEFORE_SHA="$(git rev-parse HEAD)"
    if [ -f "OVERNIGHT_PROGRESS.md" ]; then
      PROGRESS_READ_ARGS=(--read "OVERNIGHT_PROGRESS.md")
    fi

    READ_ARGS=()
    if [ "$skip_agents_md" != "true" ]; then
      for f in CLAUDE.md AGENTS.md; do
        if [ -f "$f" ]; then
          READ_ARGS+=(--read "$f")
        fi
      done
    fi

    # --edit-format udiff: aider doesn't recognize this custom model name, so
    # it defaults to the fragile "whole" format (expects the model to output
    # the entire file). This model naturally outputs unified-diff hunks
    # instead, which "whole" can't parse - aider then silently no-ops (shows
    # a plausible-looking diff in the log, but never actually commits).
    # Confirmed by testing: forcing "udiff" (which matches the model's
    # natural output) fixes this - verified a real commit gets created.
    # 2026-08-25: switched udiff -> diff when production moved to Qwen3-Coder-30B
    # (MoE). The coder emits aider SEARCH/REPLACE blocks (diff format), not
    # unified diffs — verified in the bake-off (a perfect SEARCH/REPLACE fix).
    # --edit-format udiff FORCES that format regardless of model-name recognition.
    AIDER_BASE_ARGS=(
      --yes-always --no-check-update --edit-format "${OVN_EDIT_FORMAT:-udiff}"
      --model "openai/${OVN_ACTIVE_MODEL:-$MODEL_NAME}"
      --openai-api-base "${LITELLM_BASE}/v1"
      --openai-api-key "${LITELLM_MASTER_KEY}"
    )
    if [ -f "$MODEL_METADATA_FILE" ]; then
      AIDER_BASE_ARGS+=(--model-metadata-file "$MODEL_METADATA_FILE")
    fi
    # Per-task override for large repos: aider's default repo-map budget
    # scales with repo size, and for a repo with hundreds of files the
    # map alone (before any task file is even loaded) can already consume
    # most of the 16,384-token window. Set via the task's "map_tokens"
    # field in tasks.json.
    # Fleet map-token default (2026-09-04): a real repo-map budget gives the model
    # cross-file signatures so multi-file work can pick the right files (research: repo-map
    # localization beats context-stuffing). Was unset for 5/7 repos -> tiny scaled default.
    if [ -z "$map_tokens" ] || [ "$map_tokens" = "null" ]; then map_tokens="${OVN_MAP_TOKENS:-3072}"; fi
    AIDER_BASE_ARGS+=(--map-tokens "$map_tokens")

    full_prompt="${prompt}${STANDARDS_SUFFIX}"

    # Iterative file-feeding. Root cause found by live testing (2026-08-08):
    # aider's single-shot `--message` mode does NOT loop back after the
    # model asks to add more files mid-conversation - if the model's first
    # move is "please add file X", the run just ends there with nothing
    # done (confirmed: billwatch/task-manager-platform/test-automation-agent
    # all stalled exactly this way for multiple cycles). Aider DOES support
    # pre-loading files via --file before the message is sent, so: pass 1
    # asks (read-only, no edits expected) which files it needs; each
    # subsequent pass re-scans the transcript so far for newly-mentioned
    # existing files, adds any not already loaded, and retries - up to
    # MAX_IMPLEMENT_ATTEMPTS times, stopping early on a real commit or once
    # a retry surfaces no new file to add.
    #
    # A second bug found during that same testing: the naive first version
    # of this (bare-path-line matching against the whole log) kept picking
    # up README.md/OVERNIGHT_PROGRESS.md/AGENTS.md as "requested files" -
    # aider silently auto-adds any file mentioned in the message TEXT
    # ITSELF to the chat and echoes that as a bare filename line, which is
    # indistinguishable from the model's real answer under a pure
    # exists-on-disk check. Since the prompt text always mentions
    # OVERNIGHT_PROGRESS.md, this wasted the file budget on it every time.
    # Fixed by excluding markdown docs from candidates (real code-file needs
    # don't come through as .md) and by extracting path-like tokens instead
    # of requiring the WHOLE line to be a bare path, since the model often
    # appends trailing prose on the same line ("services/foo.py (the
    # service under test)").
    MAX_IMPLEMENT_ATTEMPTS=3
    FILE_ARGS=()
    ADDED_FILES="|"

    # Shared pattern for detecting a "junk" file: one whose path IS a shell
    # command or file-request text rather than a real source file. The model
    # has repeatedly tried to "ask for more files" or "run a command" by
    # emitting a diff that creates a real file named after that command/
    # request instead of just asking in plain English (which works fine
    # elsewhere in these same logs) - e.g. `ask_for_files`, a
    # `git grep --files-with-matches ...` invocation as a filename. Used both
    # to retry mid-loop (below) and to sweep any straggler after the loop.
    JUNK_FILE_PATTERN='(^| )(git|cat|ls|find|grep|echo) |[|"\\]|^ask_for_file|^please_add|^files_needed|^request_files'

    # Protected-file guard (2026-08-15 hardening): found live that a file
    # path merely QUOTED as prose inside OVERNIGHT_PROGRESS.md's own diff
    # (e.g. "do NOT touch iptv-android/app/build.gradle.kts, it has a secret")
    # gets picked up by the plain path-token grep below exactly like a real
    # file request, since the check only looks at "does this path exist on
    # disk" - it can't tell a real request apart from a file being mentioned
    # as something to avoid. Caught a case where this loaded the one file in
    # the repo holding a plaintext secret into the aider chat as editable.
    # protected_files is a comma-separated list from the task's tasks.json
    # entry; skip any candidate that matches one exactly.
    IFS=',' read -r -a PROTECTED_FILE_LIST <<< "$protected_files"
    is_protected_file() {
      local f="$1" p
      for p in "${PROTECTED_FILE_LIST[@]}"; do
        [ -n "$p" ] && [ "$f" = "$p" ] && return 0
      done
      return 1
    }

    scan_for_new_files() {
      local found_new=0
      local cand
      while IFS= read -r cand; do
        [ -z "$cand" ] && continue
        case "$cand" in
          *.md) continue ;;
        esac
        case "$ADDED_FILES" in
          *"|${cand}|"*) continue ;;
        esac
        if is_protected_file "$cand"; then
          echo "--- skipping protected file mentioned in log: ${cand} ---" >> "$task_log"
          continue
        fi
        if [ -f "$cand" ] && [ "${#FILE_ARGS[@]}" -lt $((max_files * 2)) ]; then
          FILE_ARGS+=(--file "$cand")
          ADDED_FILES="${ADDED_FILES}${cand}|"
          found_new=1
        fi
      done < <(grep -oE '[A-Za-z0-9_./-]+\.[A-Za-z0-9]{1,8}' "$task_log" | sort -u)
      [ "$found_new" -eq 1 ]
    }

    SCOUT_PROMPT="Before writing any code, PLAN first. Reply in EXACTLY this format and nothing else:
VERDICT: one of PROCEED | ALREADY-DONE | BLOCKED | NEEDS-DECISION
PLAN: one line - if PROCEED, the change you will make in 1-2 short steps; if ALREADY-DONE, name the existing file/test that already implements the item; if BLOCKED, what a human must do
FILES: up to ${max_files} existing repo file paths you would need to see in full (relative to the repo root, one per line), or NONE

Task: ${prompt}"

    # timeout wrapper (2026-08-08 hardening): if the inference server hangs
    # mid-request, aider would otherwise block forever - combined with the
    # concurrency lock, that would freeze the queue permanently until
    # someone manually intervenes. 600s is generous for a single completion.
    #
    # --no-auto-commits on the scout call only (2026-08-14 hardening): the
    # scout prompt asks for file names, not edits, but that's just a prompt
    # instruction - nothing previously stopped the model from ignoring it
    # and emitting a real diff, which aider (with --yes-always) would apply
    # AND commit with zero oversight. Caught live: a scout pass rewrote an
    # unrelated iOS file (SettingsView.swift) into a gutted stub with no
    # connection to the actual task, and the only reason it didn't get
    # pushed was that the same call also timed out (exit 124) and the
    # exit-code check happened to short-circuit before the push step -
    # pure luck, not a real safeguard. --no-auto-commits makes it structurally
    # impossible for this call to create a commit; any edit the model still
    # writes to disk gets wiped by the git checkout/clean below before the
    # real implement pass runs, so it can never leak in as a base state.
    timeout 600 aider "${AIDER_BASE_ARGS[@]}" --no-auto-commits \
      ${READ_ARGS[@]+"${READ_ARGS[@]}"} \
      ${PROGRESS_READ_ARGS[@]+"${PROGRESS_READ_ARGS[@]}"} \
      --message "${SCOUT_PROMPT}" \
      > "$task_log" 2>&1
    AIDER_EXIT=$?
    scan_for_new_files || true

    # Scout is supposed to be read-only - forcibly discard any working-tree
    # edits it left behind (whether or not it also tried to commit) so
    # nothing from this pass can contaminate the real implement pass below.
    git checkout -- . 2>/dev/null
    git clean -fd --quiet 2>/dev/null

    SCOUT_SHA="$(git rev-parse HEAD)"
    if [ "$SCOUT_SHA" != "$BEFORE_SHA" ]; then
      # Should be impossible with --no-auto-commits, but harden anyway:
      # don't trust or push a commit from a pass that's meant to be
      # read-only - reset and report a hard error instead.
      git reset --hard "$BEFORE_SHA" --quiet
      # 2026-08-30 FIX: do NOT abort the cycle here. Trivial self-gen items
      # (e.g. `__repr__ -> str`) get done by the model IN the read-only scout
      # pass, which then commits; aborting with error(scout committed
      # unexpectedly) meant the implement pass never ran and NO work landed on
      # ANY repo once backlogs drained to one-liners (135 errors / 6 pass). The
      # scout commit is discarded above; fall through to the implement pass,
      # which re-does the work with the full build/test gates.
      echo "--- scout pass committed despite --no-auto-commits; reset + CONTINUING to implement ---" >> "$task_log"
    fi

    # Auto-test feedback (2026-08-26): if a provisioned pytest venv exists, let aider
    # run the suite after each edit and feed failures back, so the model fixes its own
    # code to GREEN before committing (it was writing blind and its own tests failed).
    TEST_ARGS=()
    # Adaptive auto-test (2026-08-28): run the RIGHT suite for whatever the model
    # edits — vitest for web, pytest for backend — so WEB test items stop
    # committing blind and escaping as tests:FAIL. See scripts/ovn_autotest.sh.
    if [ -f "$SCRIPT_DIR/scripts/ovn_autotest.sh" ] && { find . -maxdepth 4 -type f -path '*/.venv/bin/pytest' 2>/dev/null | grep -q . || find . -maxdepth 3 -name package.json -not -path '*/node_modules/*' 2>/dev/null | grep -q .; }; then
      TEST_ARGS=(--auto-test --test-cmd "bash \"$SCRIPT_DIR/scripts/ovn_autotest.sh\" \"$(pwd)\"")
      echo "--- auto-test enabled: adaptive vitest(web)/pytest(backend) ---" >> "$task_log"
    fi
    # --- Stage 1.5 (2026-08-29): carry the scout's PLAN + VERDICT into implement ---
    # The original stage-1 only LOGGED the plan; the implement pass then re-derived
    # from scratch and frequently produced NO diff (61/62 no-ops carried
    # verdict=PROCEED). Feed the plan forward and forbid re-planning; skip the code
    # attempt on ALREADY-DONE / BLOCKED so a done/blocked item can't waste a red push.
    OVN_VERDICT="$(grep -hoiE "VERDICT:[[:space:]]*(PROCEED|ALREADY-DONE|BLOCKED|NEEDS-DECISION)" "$task_log" 2>/dev/null | head -1 | sed -E "s/.*VERDICT:[[:space:]]*//I" | tr "[:lower:]" "[:upper:]")"
    OVN_PLAN="$(grep -hoiE "PLAN:[[:space:]]*.+" "$task_log" 2>/dev/null | head -1 | sed -E "s/^PLAN:[[:space:]]*//I; s/[[:space:]]*FILES:.*//I" | cut -c1-300)"
    # The 27B emits VERDICT/PLAN/FILES as ONE logical line the terminal WRAPS
    # across ~3 log lines, so the single-line OVN_PLAN above misses the file
    # token when it lands on a wrapped continuation (shrike's PrivacyPage.vue) ->
    # the planned file never force-loads -> implement flails ("0 files
    # pre-loaded", model hallucinates a read_file tool_call) -> no-op on a
    # genuinely-not-done item. Harvest path tokens from the WHOLE scout reply
    # (VERDICT line + next 4 wrapped lines + any FILES: line) regardless of wrap.
    OVN_SCOUT_FILES="$( { grep -A4 -hiE "VERDICT:[[:space:]]*(PROCEED|NEEDS-DECISION)" "$task_log" 2>/dev/null; grep -hiE "FILES:" "$task_log" 2>/dev/null; } | grep -oE "[A-Za-z0-9_./-]+\.[A-Za-z0-9]{1,8}" | grep -vE "\.md$" | sort -u)"
    # Per-cycle summary log (2026-08-30) for easy diagnosis: one line per repo
    # per cycle -> tail state/cycle_summary.log to see verdict distribution + the
    # planned files without digging through per-repo task logs.
    _CS_TOP="$(grep -m1 -E "^- \[ \]" OVERNIGHT_PROGRESS.md 2>/dev/null | grep -oE "\`[^\`]+\`" | head -1 | tr -d '\`')"
    mkdir -p "$SCRIPT_DIR/state" 2>/dev/null
    # classify the item the model actually planned (its chosen file) for stats
    _CS_PF="$(echo $OVN_SCOUT_FILES | tr ' ' '\n' | grep -E '\.[A-Za-z]' | head -1)"
    _CS_ITEM="$(grep -m1 -F "${_CS_PF:-$_CS_TOP}" OVERNIGHT_PROGRESS.md 2>/dev/null)"
    _CS_TAG="$(python3 "$SCRIPT_DIR/scripts/ovn_classify.py" --tag "$_CS_ITEM" 2>/dev/null || echo '{?}')"
    echo "$(date +%H:%M:%S) ${id} verdict=${OVN_VERDICT:-NONE} planfiles=[$(echo $OVN_SCOUT_FILES | tr '\n' ' ')] top_item=${_CS_TOP:-none} class=${_CS_TAG}" >> "$SCRIPT_DIR/state/cycle_summary.log"
    if [ "$OVN_VERDICT" = "BLOCKED" ] || [ "$OVN_VERDICT" = "ALREADY-DONE" ] || [ "$OVN_VERDICT" = "NEEDS-DECISION" ]; then
      echo "--- scout verdict=${OVN_VERDICT}; skipping implement this cycle (no code attempt, no wasted red) ---" >> "$task_log"
      # ALREADY-DONE crediting (2026-08-30): the #1 remaining no-op source was a
      # genuinely-done item re-faced EVERY cycle forever, because ALREADY-DONE
      # skipped implement but never ticked the checkbox. If the scout's PLAN
      # names a file matching an unchecked, non-human item, credit that item so
      # it leaves rotation (mirrors the green-commit auto-credit logic).
      if [ "$OVN_VERDICT" = "ALREADY-DONE" ] && [ -f "OVERNIGHT_PROGRESS.md" ] && [ -n "$OVN_PLAN" ]; then
        for _df in $(echo "$OVN_PLAN" | grep -oE "[A-Za-z0-9_./-]+\.[A-Za-z0-9]{1,8}" | sort -u); do
          case "$_df" in *.md) continue;; esac
          _df_base="$(basename "$_df")"
          _ad_ln="$(grep -nE '^- \[ \]' OVERNIGHT_PROGRESS.md | grep -viE 'HUMAN-ONLY|human/|AUTO-SKIP|HARD FILE BAN|BLOCKED' | grep -F "$_df_base" | head -1 | cut -d: -f1)"
          if [ -n "$_ad_ln" ]; then
            sed -i "${_ad_ln}s/^- \[ \] /- [x] (already-done, scout-verified) /" OVERNIGHT_PROGRESS.md
            git add OVERNIGHT_PROGRESS.md
            git commit -m "chore(queue): credit already-done item (scout verified ${_df_base})" --quiet 2>>"$task_log" || true
            echo "--- credited already-done item at line ${_ad_ln} (matched ${_df_base}) ---" >> "$task_log"
            break
          fi
        done
      fi
      # Any-verdict already-satisfied crediting (2026-08-30): the scout sometimes
      # says NEEDS-DECISION/BLOCKED on an item whose fix is ALREADY in the code
      # (e.g. App.vue buttons already have type=button) and explains so in its
      # reasoning. Run the credit helper against the scout log so such items get
      # checked off instead of clean-skipping forever.
      if [ -f "OVERNIGHT_PROGRESS.md" ] && [ -f "$SCRIPT_DIR/scripts/ovn_credit_already_satisfied.sh" ]; then
        _SKC="$(bash "$SCRIPT_DIR/scripts/ovn_credit_already_satisfied.sh" "$task_log" OVERNIGHT_PROGRESS.md 2>>"$task_log")"
        if echo "$_SKC" | grep -qE 'CREDITED=[1-9]'; then
          git add OVERNIGHT_PROGRESS.md
          git commit -q -m "chore(queue): credit already-satisfied item (scout verdict path)" 2>>"$task_log" || true
        fi
      fi
      echo "no-op(${OVN_VERDICT})"
      return
    fi
    # Force-load the file(s) the PLAN names so the model can actually execute its own
    # plan. scan_for_new_files loads alphabetically-first path tokens up to a cap and
    # was dropping the planned target (e.g. it planned ImportView.vue but loaded the
    # alphabetically-earlier test_auth.py from the item list, so the implement had the
    # wrong file open and no-oped). The PLAN's target always wins now.
    if [ -n "$OVN_PLAN" ] || [ -n "$OVN_SCOUT_FILES" ]; then
      for _pf in $( { echo "$OVN_PLAN" | grep -oE "[A-Za-z0-9_./-]+\.[A-Za-z0-9]{1,8}"; echo "$OVN_SCOUT_FILES"; } | sort -u); do
        [ -f "$_pf" ] || continue
        case "$_pf" in *.md) continue;; esac
        case " ${FILE_ARGS[*]} " in *" $_pf "*) continue;; esac
        if [ -n "$protected_files" ]; then case " $protected_files " in *" $_pf "*) continue;; esac; fi
        FILE_ARGS+=(--file "$_pf")
        echo "--- force-loaded PLAN target file: $_pf ---" >> "$task_log"
      done
    fi
    if [ -n "$OVN_PLAN" ]; then
      full_prompt="You already analyzed this task and chose a plan and the files you need. Execute it NOW and produce the actual code diff. Do NOT re-plan, do NOT re-explore, do NOT ask to see more files. If the plan proves wrong mid-edit, correct it, but this pass MUST end in a concrete change.

Your plan: ${OVN_PLAN}

--- Task ---
${full_prompt}"
    fi
    # Architect-mode pilot (2026-09-04, gated OVN_ARCHITECT=1): hard/multi-file items get
    # aider's structured plan->edit (same 27B as editor). Simple items keep the fast path.
    ARCH_ARGS=()
    if [ "${OVN_ARCHITECT:-0}" = 1 ] && echo "$prompt" | grep -qiE '\[T[345]\]|refactor|multi-file|multiple files|architect|generics|type-heavy'; then
      ARCH_ARGS=(--architect --auto-accept-architect)
      echo "--- architect mode ON for this hard item ---" >> "$task_log"
    fi
    ATTEMPT=1
    while [ "$ATTEMPT" -le "$MAX_IMPLEMENT_ATTEMPTS" ]; do
      echo "--- implement attempt ${ATTEMPT}/${MAX_IMPLEMENT_ATTEMPTS} (${#FILE_ARGS[@]} file(s) pre-loaded) ---" >> "$task_log"
      timeout "$aider_timeout" aider "${AIDER_BASE_ARGS[@]}" \
        ${ARCH_ARGS[@]+"${ARCH_ARGS[@]}"} \
        ${TEST_ARGS[@]+"${TEST_ARGS[@]}"} \
        ${READ_ARGS[@]+"${READ_ARGS[@]}"} \
        ${PROGRESS_READ_ARGS[@]+"${PROGRESS_READ_ARGS[@]}"} \
        ${FILE_ARGS[@]+"${FILE_ARGS[@]}"} \
        --message "${full_prompt}" \
        >> "$task_log" 2>&1
      AIDER_EXIT=$?

      # Oversized-context guard (2026-09-06): if this item blew past the model's window
      # (litellm 400 exceed_context_size — seen at 70-115K tokens), stop NOW instead of
      # retrying and re-sending 100k-token requests. Logged as oversized so it can be trimmed.
      if grep -q "exceed_context_size" "$task_log" 2>/dev/null; then
        echo "--- item exceeded the context window (oversized) — skipping; trim/split it ---" >> "$task_log"
        echo "skip(oversized-context)"; return
      fi

      NOW_SHA="$(git rev-parse HEAD)"
      if [ "$NOW_SHA" != "$BEFORE_SHA" ]; then
        # Junk-only-commit guard (2026-08-16 hardening): aider auto-commits
        # whatever it wrote, including a junk file - naively breaking here
        # on "a commit happened" wastes the whole cycle, since the next
        # attempt (which would load the very files the model just asked
        # for, via scan_for_new_files below) never runs. If every file this
        # attempt touched is junk, discard it and keep iterating instead of
        # treating "a commit happened" as "real progress happened."
        CHANGED_FILES="$(git diff --name-only "$BEFORE_SHA" "$NOW_SHA" -- .)"
        JUNK_FILES="$(echo "$CHANGED_FILES" | grep -E "$JUNK_FILE_PATTERN" || true)"
        NONJUNK_FILES="$(echo "$CHANGED_FILES" | grep -vE "$JUNK_FILE_PATTERN" | grep -v '^$' || true)"
        if [ -n "$JUNK_FILES" ] && [ -z "$NONJUNK_FILES" ]; then
          echo "--- attempt ${ATTEMPT} only committed junk file(s), discarding and retrying: ---" >> "$task_log"
          echo "$JUNK_FILES" >> "$task_log"
          git reset --hard "$BEFORE_SHA" --quiet
          if [ "$ATTEMPT" -eq "$MAX_IMPLEMENT_ATTEMPTS" ] || ! scan_for_new_files; then
            break
          fi
          ATTEMPT=$((ATTEMPT + 1))
          continue
        fi
        break
      fi
      if [ "$ATTEMPT" -eq "$MAX_IMPLEMENT_ATTEMPTS" ] || ! scan_for_new_files; then
        break
      fi
      ATTEMPT=$((ATTEMPT + 1))
    done

    AFTER_SHA="$(git rev-parse HEAD)"

    # DELETE: trailer handling (2026-08-25). Deleting a file via aider's udiff
    # format makes the model reproduce the ENTIRE file as removed lines — for a
    # large file that blows the 600s budget and times out every cycle (this
    # auto-disabled gitlark on seven "delete a dead service" items). So the
    # model is told (STANDARDS_SUFFIX) NOT to edit a file to delete it, and to
    # instead emit a 'DELETE: <path>' line; the runner removes it here with a
    # cheap git rm. Grep the task log (catches it whether the model put it in a
    # commit message or just its reply); only remove paths that actually exist.
    DEL_PATHS="$(grep -oE '^[[:space:]]*(-[[:space:]]*)?DELETE:[[:space:]]*[A-Za-z0-9_./-]+' "$task_log" 2>/dev/null | sed -E 's/.*DELETE:[[:space:]]*//' | sort -u)"
    if [ -n "$DEL_PATHS" ]; then
      del_did=0
      while IFS= read -r dp; do
        [ -z "$dp" ] && continue
        if [ -f "$dp" ]; then
          git rm -q -- "$dp" 2>>"$task_log" && { echo "--- DELETE trailer: removed ${dp} ---" >> "$task_log"; del_did=1; }
        fi
      done <<< "$DEL_PATHS"
      if [ "$del_did" -eq 1 ] && ! git diff --cached --quiet; then
        git commit -q -m "chore: remove file(s) per DELETE trailer (aider can't cheaply delete via udiff)"
        AFTER_SHA="$(git rev-parse HEAD)"
      fi
    fi

    # Working-tree residue guard (2026-08-16 hardening): if nothing got
    # committed (e.g. an attempt timed out mid-write, or staged a file it
    # never committed), leftover staged/untracked/modified state would
    # otherwise persist into the NEXT cycle's git status, since this
    # directory is reused across cycles rather than freshly cloned each
    # time. Caught live: a `git grep -l "defineStore" ...` junk file left
    # staged-then-modified after a no-op cycle. Since nothing here was ever
    # committed, none of it is "real" progress by this script's own
    # definition - safe to discard unconditionally.
    if [ "$AFTER_SHA" = "$BEFORE_SHA" ] && [ -n "$(git status --porcelain)" ]; then
      echo "--- discarding uncommitted working-tree residue from an incomplete attempt ---" >> "$task_log"
      git status --porcelain >> "$task_log"
      git reset --hard "$BEFORE_SHA" --quiet
      git clean -fd --quiet
    fi

    # Implement-pass already-satisfied crediting (2026-08-30): THE #1 remaining
    # no-op. Items already done in code (scout says PROCEED, but implement finds
    # them satisfied -> no diff, no commit) never got checked off, so they were
    # re-faced every cycle forever. The helper harvests the file named right
    # before each "already done" admission and checks off the matching item.
    # Only runs when NOTHING committed this cycle.
    if [ "$AFTER_SHA" = "$BEFORE_SHA" ] && [ -f "OVERNIGHT_PROGRESS.md" ] && [ -f "$SCRIPT_DIR/scripts/ovn_credit_already_satisfied.sh" ]; then
      _AC_OUT="$(bash "$SCRIPT_DIR/scripts/ovn_credit_already_satisfied.sh" "$task_log" OVERNIGHT_PROGRESS.md 2>>"$task_log")"
      echo "$_AC_OUT" >> "$task_log"
      if echo "$_AC_OUT" | grep -qE 'CREDITED=[1-9]'; then
        git add OVERNIGHT_PROGRESS.md
        git commit -q -m "chore(queue): credit item(s) the implement pass found already satisfied in code" 2>>"$task_log" || true
        AFTER_SHA="$(git rev-parse HEAD)"
      fi
    fi

    # Hard-file-ban enforcement (2026-08-24 hardening): some repos declare
    # specific files permanently off-limits to automated edits in their own
    # OVERNIGHT_PROGRESS.md (e.g. xlite's battle.gd/mission_select.gd, both
    # of which broke parsing repeatedly from automated attempts before being
    # banned). The doc language alone has now failed for real at least once
    # (xlite's mission_select.gd, caught live by a human monitoring session,
    # not by this script) - a model can read "NEEDS HUMAN DECISION, this
    # file is hard-banned" and still edit the file anyway. This makes the
    # ban mechanical: a repo opts in by adding a `.queue-hard-banned-files`
    # file at its root (one path or glob per line, '#' comments allowed);
    # if this cycle's commit(s) touch any of those paths, the ENTIRE
    # cycle's local, not-yet-pushed work is discarded (git reset --hard back
    # to BEFORE_SHA) rather than trying to selectively revert just the
    # offending file - simpler and safer than a partial revert (which
    # itself can leave a stale .godot/ class-cache mismatch requiring a
    # follow-up --import, as seen live undoing the mission_select.gd
    # violation by hand). A discarded cycle is then correctly a plain
    # no-op for every check below (AFTER_SHA back to equaling BEFORE_SHA).
    if [ "$AFTER_SHA" != "$BEFORE_SHA" ] && [ -f ".queue-hard-banned-files" ]; then
      BANNED_PATTERN="$(grep -v '^\s*#' .queue-hard-banned-files | grep -v '^\s*$' | paste -sd'|' - || true)"
      if [ -n "$BANNED_PATTERN" ]; then
        BANNED_HIT="$(git diff --name-only "$BEFORE_SHA" "$AFTER_SHA" | grep -E "$BANNED_PATTERN" || true)"
        if [ -n "$BANNED_HIT" ]; then
          echo "--- HARD-BAN VIOLATION: this cycle touched a permanently-banned file, discarding the whole cycle: ---" >> "$task_log"
          echo "$BANNED_HIT" >> "$task_log"
          git reset --hard "$BEFORE_SHA" --quiet
          git clean -fd --quiet
          if [ -x "$HOME/godot/godot4" ]; then
            timeout 60 "$HOME/godot/godot4" --headless --path . --import > /dev/null 2>>"$task_log"
          fi
          AFTER_SHA="$(git rev-parse HEAD)"
        fi
      fi
    fi

    # Auto-remove junk files (2026-08-16 hardening): belt-and-suspenders
    # sweep for any junk file (see JUNK_FILE_PATTERN above) that survived
    # the in-loop guard - e.g. a mixed commit with some real progress
    # alongside a junk file, which the in-loop guard deliberately leaves
    # alone since it only discards attempts that are ENTIRELY junk.
    if [ "$AFTER_SHA" != "$BEFORE_SHA" ]; then
      JUNK_FILES="$(git diff --name-only --diff-filter=A "$BEFORE_SHA" "$AFTER_SHA" -- . \
        | grep -E "$JUNK_FILE_PATTERN" \
        || true)"
      if [ -n "$JUNK_FILES" ]; then
        echo "--- auto-removing junk file(s) accidentally committed: ---" >> "$task_log"
        echo "$JUNK_FILES" >> "$task_log"
        echo "$JUNK_FILES" | while IFS= read -r f; do
          [ -n "$f" ] && git rm -f -- "$f" >/dev/null 2>>"$task_log"
        done
        if ! git diff --cached --quiet; then
          git commit -m "chore: auto-remove junk file(s) accidentally committed by aider" --quiet
          AFTER_SHA="$(git rev-parse HEAD)"
        fi
      fi
    fi

    # Duplicate-section-header auto-merge (2026-08-24 hardening): the model
    # sometimes appends a brand-new "## Decisions Made" (or other "## "
    # section) header instead of scrolling up to find the existing one,
    # especially right after editing near the bottom of the file (e.g.
    # right after "## Completed"). An in-doc instruction telling it not to
    # do this was tried first and failed twice within two cycles on xlite -
    # this merges duplicate same-titled top-level sections back into one
    # automatically (first-seen order, content concatenated in encounter
    # order), rather than relying on the model's compliance. No-ops (exits
    # "unchanged", no commit) when there's nothing to merge.
    if [ "$AFTER_SHA" != "$BEFORE_SHA" ] && [ -f "OVERNIGHT_PROGRESS.md" ]; then
      DEDUPE_OUT="$(python3 "$SCRIPT_DIR/dedupe_progress_headers.py" OVERNIGHT_PROGRESS.md 2>>"$task_log")"
      if [ "$DEDUPE_OUT" != "unchanged" ]; then
        echo "--- OVERNIGHT_PROGRESS.md: ${DEDUPE_OUT} ---" >> "$task_log"
        git add OVERNIGHT_PROGRESS.md
        if ! git diff --cached --quiet; then
          git commit -m "docs: auto-merge duplicate section header(s) in OVERNIGHT_PROGRESS.md" --quiet
          AFTER_SHA="$(git rev-parse HEAD)"
        fi
      fi
    fi

    # Duplicate-GDScript-function auto-merge (2026-08-24 hardening, same day
    # as the header dedup above): xlite's TurnManager.get_phase_display_name()
    # was independently re-duplicated by 4 SEPARATE cycles (a fix for one
    # occurrence never stopped the next cycle from reintroducing it) - each
    # time a byte-identical copy of the same function, which GDScript can't
    # parse (duplicate function name), breaking every other script that
    # references the class (TurnManager is a class_name global). Runs on
    # every .gd file the commit actually touched; only removes a LATER
    # occurrence when its body is byte-identical to an earlier same-named
    # one - a genuine same-name-different-body conflict is left alone and
    # reported, never auto-resolved.
    if [ "$AFTER_SHA" != "$BEFORE_SHA" ]; then
      CHANGED_GD_FILES="$(git diff --name-only --diff-filter=AM "$BEFORE_SHA" "$AFTER_SHA" -- '*.gd' || true)"
      if [ -n "$CHANGED_GD_FILES" ]; then
        echo "$CHANGED_GD_FILES" | while IFS= read -r gd_file; do
          [ -f "$gd_file" ] || continue
          GD_DEDUPE_OUT="$(python3 "$SCRIPT_DIR/dedupe_gd_duplicate_functions.py" "$gd_file" 2>>"$task_log")"
          if [ "$GD_DEDUPE_OUT" != "unchanged" ]; then
            echo "--- ${gd_file}: ${GD_DEDUPE_OUT} ---" >> "$task_log"
            git add "$gd_file"
          fi
        done
        if ! git diff --cached --quiet; then
          git commit -m "fix: auto-remove duplicate GDScript function definition(s)" --quiet
          AFTER_SHA="$(git rev-parse HEAD)"
        fi
      fi
    fi

    # Duplicate-Python-definition auto-merge (2026-08-25 hardening, same
    # shape as the GDScript one above): test-automation-agent's
    # TestOrchestratorExecutePhaseIntegration test class was independently
    # re-added, byte-identical, by 2 SEPARATE cycles two apart - Python
    # silently lets a later same-named top-level class/def shadow an
    # earlier one at module scope (not a parse error like GDScript, just
    # dead, invisible-to-pytest code). Runs on every .py file the commit
    # actually touched; only removes a LATER top-level class/def when its
    # body is byte-identical to an earlier same-name one - a genuine
    # same-name-different-body conflict is left alone and reported, never
    # auto-resolved.
    if [ "$AFTER_SHA" != "$BEFORE_SHA" ]; then
      CHANGED_PY_FILES="$(git diff --name-only --diff-filter=AM "$BEFORE_SHA" "$AFTER_SHA" -- '*.py' || true)"
      if [ -n "$CHANGED_PY_FILES" ]; then
        echo "$CHANGED_PY_FILES" | while IFS= read -r py_file; do
          [ -f "$py_file" ] || continue
          PY_DEDUPE_OUT="$(python3 "$SCRIPT_DIR/dedupe_python_duplicate_defs.py" "$py_file" 2>>"$task_log")"
          if [ "$PY_DEDUPE_OUT" != "unchanged" ]; then
            echo "--- ${py_file}: ${PY_DEDUPE_OUT} ---" >> "$task_log"
            git add "$py_file"
          fi
        done
        if ! git diff --cached --quiet; then
          git commit -m "fix: auto-remove duplicate Python class/function definition(s)" --quiet
          AFTER_SHA="$(git rev-parse HEAD)"
        fi
      fi
    fi

    if [ "$AIDER_EXIT" -ne 0 ]; then
      error_status "$task_log" "error(exit=${AIDER_EXIT})"
    elif [ "$BEFORE_SHA" != "$AFTER_SHA" ]; then
      # Post-commit verification (2026-08-08 hardening). Provisioned once,
      # server-side, for all 7 repos (real .venv/node_modules, not
      # reinstalled every cycle - see docs/ops/LOCAL_LLM_UPGRADE_PLAN.md).
      # Runs whatever test suite already exists in THIS repo and puts the
      # real pass/fail into the log and the report status, instead of only
      # trusting the model's own "I ran the tests" claim. Deliberately does
      # NOT feed into the consecutive-failure safety valve - a real code
      # regression and an environment/flake-caused failure look identical
      # here, and auto-disabling a task over the latter would be worse than
      # just surfacing it for you to glance at in the report.
      VERIFY_RESULT="$(run_repo_verification)"

      # TS-RATCHET (2026-09-04): type-check web on TS-touching commits and REVERT if this
      # commit raised the tsc error count above the repo baseline (ratchet: only holds or
      # improves). Real type feedback WITHOUT reverting the pre-existing type-error backlog
      # (iptv-web ~69, billwatch-web ~71). Baselines: state/tsc_baseline/. Toggle OVN_TSC_GATE=0.
      if [ "${OVN_TSC_GATE:-1}" = 1 ] && [ -f "$SCRIPT_DIR/scripts/ovn_tsc_gate.sh" ]; then
        TSC_OUT="$(bash "$SCRIPT_DIR/scripts/ovn_tsc_gate.sh" "$(pwd)" "$SCRIPT_DIR/state/tsc_baseline" "$repo" "$BEFORE_SHA" "$AFTER_SHA" 2>&1)"
        [ -n "$TSC_OUT" ] && echo "$TSC_OUT" >> "$task_log"
        if echo "$TSC_OUT" | grep -q "TSC-RATCHET-REGRESSION"; then
          echo "--- TS-RATCHET: commit raised type errors above baseline — reverting to ${BEFORE_SHA} ---" >> "$task_log"
          git reset --hard "$BEFORE_SHA" --quiet
          git clean -fd --quiet 2>/dev/null
          emit_alert warn "$id" "ts-ratchet reverted a commit that introduced net-new TypeScript errors"
          echo "reverted(ts-regression)"
          return
        fi
      fi

      # BUILD-GATE (2026-08-26): if this commit STRUCTURALLY broke the build — a
      # syntax/import/collection/parse error, i.e. the code no longer even loads —
      # REVERT it to BEFORE_SHA and do not push. This is the fix for the coder
      # trial's compounding breakage: one bad edit used to poison a repo so every
      # later cycle failed on already-broken code. A plain test-ASSERTION failure
      # is NOT reverted (kept + reported as tests:FAIL) — that can be a real fix
      # in progress or a pre-existing flake. Grep the verification output (already
      # in $task_log) for unambiguous structural-break signals across py/gd/js.
      if [ "$VERIFY_RESULT" = "fail" ] && { grep -E "SyntaxError|IndentationError|invalid syntax|ImportError while loading|cannot import name|ERROR collecting|errors during collection|SCRIPT ERROR|Parse Error|ERROR: Failed to load|Cannot find module|error TS[0-9]|Build failed|Compilation error|compile[A-Za-z]*Kotlin FAILED|compile[A-Za-z]*JavaWithJavac FAILED" "$task_log" | grep -vE "has no resource loaders|Cannot call method '[^']*' on a null value|AudioStreamOggVorbis|base object of type 'Nil'|Attempted to free a RefCounted|Parameter .* is null" | grep -q .; }; then
        echo "--- BUILD-GATE: commit structurally broke the build — reverting to ${BEFORE_SHA} ---" >> "$task_log"
        git reset --hard "$BEFORE_SHA" --quiet
        git clean -fd --quiet 2>/dev/null
        if [ -x "$HOME/godot/godot4" ] && [ -f project.godot ]; then
          timeout 60 "$HOME/godot/godot4" --headless --path . --import >/dev/null 2>>"$task_log"
        fi
        emit_alert warn "$id" "build-gate reverted a commit that broke the build (syntax/import/parse error) — the model produced non-loading code"
        echo "reverted(build-break)"
        return
      fi

      # NO-NEW-RED GUARD (2026-08-29): iptv + xlite are green at main and hygiene keeps
      # feature green, so ANY tests:FAIL here is red THIS commit introduced. The old behavior
      # (keep it on feature as tests:FAIL) blocks hygiene from merging every GREEN commit
      # stacked behind it — the drift that piles up. So revert it. Build-breaks are handled
      # above; this catches BOTH a model-authored failing test AND a source change that breaks
      # a previously-green test (e.g. an any->unknown retype that alters an error message).
      # Status is a no-op (does NOT trip the task safety-valve); the per-item guard still
      # counts it and auto-blocks the offending item after 3 tries, so a persistently-bad
      # item self-limits instead of revert-looping forever.
      if [ "$VERIFY_RESULT" = "fail" ]; then
        OVN_CHANGED_ALL="$(git diff --name-only "$BEFORE_SHA" "$AFTER_SHA" -- . | grep -v '^$' || true)"
        OVN_NONTEST="$(echo "$OVN_CHANGED_ALL" | grep -vE '(^|/)(tests?|__tests__)/|\.test\.[jt]sx?$|\.spec\.[jt]sx?$|(^|/)test_[^/]*\.py$|_test\.py$|Test\.kt$|Tests?\.swift$' | grep -v '^$' || true)"
        if [ -n "$OVN_NONTEST" ]; then _redkind="a source change broke a previously-green test"; else _redkind="the model added failing tests"; fi
        echo "--- NO-NEW-RED GUARD: commit left the suite red (${_redkind}) — reverting so feature stays green and mergeable ---" >> "$task_log"
        git reset --hard "$BEFORE_SHA" --quiet
        git clean -fd --quiet 2>/dev/null
        emit_alert warn "$id" "reverted a commit that left tests red (${_redkind}); feature kept green for hygiene"
        echo "no-op(reverted-red)"
        return
      fi

      # Red-green check (2026-08-25 Tier-3): did a bugfix's new test earn its
      # pass? Runs on the code state before the bookkeeping doc commit.
      REDGREEN="$(run_redgreen_check "$BEFORE_SHA" "$AFTER_SHA")"
      if [ "$REDGREEN" = "suspect" ]; then
        echo "--- RED-GREEN SUSPECT: new test(s) passed WITHOUT the fix (vacuous or mirrors the bug) ---" >> "$task_log"
        emit_alert warn "$id" "red-green: a new test passed without the fix (possible vacuous/mirror test) — review the diff on ${branch}"
      fi

      # Runner-owned progress bookkeeping (2026-08-25 Tier-1). The model declared
      # what it did via DONE:/DECISION:/NEW: trailers in its commit message(s);
      # apply them to OVERNIGHT_PROGRESS.md deterministically here. Gated on
      # verification NOT failing — a broken build must never mark an item done.
      # The tiny doc commit rides the same push below (no extra push).
      if [ "$VERIFY_RESULT" != "fail" ] && [ -f "OVERNIGHT_PROGRESS.md" ]; then
        PROG_MSGS="$(git log --format=%B "${BEFORE_SHA}..${AFTER_SHA}")"
        PROG_OUT="$(printf '%s' "$PROG_MSGS" | python3 "$SCRIPT_DIR/update_progress.py" OVERNIGHT_PROGRESS.md 2>>"$task_log")"
        if [ "$PROG_OUT" != "unchanged" ]; then
          echo "--- progress bookkeeping: ${PROG_OUT} ---" >> "$task_log"
          git add OVERNIGHT_PROGRESS.md
          if ! git diff --cached --quiet; then
            git commit -m "docs: runner-owned progress bookkeeping" --quiet
            AFTER_SHA="$(git rev-parse HEAD)"
          fi
        fi
      fi

      # Auto-credit (2026-08-29, per-file): the 27B almost never emits DONE: trailers, so
      # the bookkeeping above can't check items off - the model then re-faces finished work
      # forever (no-op) until the item-guard wrongly blocks it. The model does NOT always do
      # the TOP item, so credit ANY unchecked, non-blocked item whose EXACT named file this
      # green commit touched. Single-file items name their target file, so a green change to
      # that file is that item's completion.
      if [ "$VERIFY_RESULT" != "fail" ] && [ -f "OVERNIGHT_PROGRESS.md" ]; then
        _ac_changed="$(git diff --name-only "$BEFORE_SHA" "$AFTER_SHA" -- . | grep -v '^$')"
        _ac_hit=0
        if [ -n "$_ac_changed" ]; then
          while IFS= read -r _cf; do
            [ -z "$_cf" ] && continue
            case "$_cf" in OVERNIGHT_PROGRESS.md) continue;; esac
            _ac_ln="$(grep -nE '^- \[ \]' OVERNIGHT_PROGRESS.md | grep -viE 'HUMAN-ONLY|AUTO-SKIP|HARD FILE BAN|BLOCKED' | grep -F "$_cf" | head -1 | cut -d: -f1)"
            if [ -n "$_ac_ln" ]; then
              sed -i "${_ac_ln}s/^- \[ \] /- [x] /" OVERNIGHT_PROGRESS.md
              _ac_hit=1
              echo "--- auto-credit: checked off the item naming ${_cf} (green change touched it) ---" >> "$task_log"
            fi
          done <<< "$_ac_changed"
          if [ "$_ac_hit" = "1" ]; then
            git add OVERNIGHT_PROGRESS.md 2>/dev/null
            if ! git diff --cached --quiet; then
              git commit -q -m "chore(queue): auto-credit item(s) whose file this green change touched"
              AFTER_SHA="$(git rev-parse HEAD)"
            fi
          fi
        fi
      fi

      if git push origin "$branch" --quiet 2>>"$task_log"; then
        case "$VERIFY_RESULT" in
          fail) PUSH_STATUS="pushed(tests:FAIL - see log)" ;;
          pass) PUSH_STATUS="pushed(tests:pass)" ;;
          *) PUSH_STATUS="pushed" ;;
        esac
        [ "$REDGREEN" = "suspect" ] && PUSH_STATUS="${PUSH_STATUS} [redgreen:SUSPECT]"
        LINT_ISSUES="$(run_lint_check "$BEFORE_SHA" "$AFTER_SHA")"
        [ "${LINT_ISSUES:-0}" -gt 0 ] && PUSH_STATUS="${PUSH_STATUS} [lint:${LINT_ISSUES}]"
        [ "$(run_coverage_check "$BEFORE_SHA" "$AFTER_SHA")" = "untested" ] && PUSH_STATUS="${PUSH_STATUS} [untested-change]"
        echo "$PUSH_STATUS"
      else
        # Push rejected (usually non-fast-forward: origin advanced from a
        # concurrent queue push OR a manual push). This is an INFRA divergence,
        # NOT a task failure - self-heal by rebasing onto origin and retrying,
        # and do NOT let it count toward the 3-strike safety valve (that was
        # auto-disabling healthy repos - billwatch/shrike - during heavy manual
        # pushing). If the rebase-retry also fails, emit a transient status.
        echo "--- push rejected; rebasing onto origin/${branch} and retrying ---" >> "$task_log"
        if git pull --rebase origin "$branch" >>"$task_log" 2>&1 && git push origin "$branch" --quiet 2>>"$task_log"; then
          echo "pushed(after-rebase)"
        else
          git rebase --abort >/dev/null 2>&1 || true
          git fetch -q origin "$branch" 2>/dev/null && git reset --hard "origin/$branch" >/dev/null 2>&1 || true
          echo "error-transient(push-diverged - resynced, retry next cycle)"
        fi
      fi
    elif grep -qE "ContextWindowExceededError|BadRequestError|APIError|RateLimitError|Traceback \(most recent call last\)" "$task_log"; then
      # Aider often exits 0 even after an internal API exception (e.g. the
      # model asking for more files than fit in context) - it just prints the
      # error and stops, which looks identical to a genuine "nothing needed
      # changing" no-op unless we check the log content too. Without this, a
      # systematically-broken task would report "no-op" forever and never trip
      # the safety valve. error_status downgrades a transient blip so it doesn't
      # count toward the valve.
      error_status "$task_log" "error(model/API error - see log)"
    else
      echo "no-op"
    fi
  )
}

run_train_job_task() {
  local id="$1" project="$2" task_name="$3" engine="$4" version="$5" task_log="$6"

  {
    echo "=== Stopping inference container (${INFERENCE_CONTAINER}) to free the GPU ==="
    docker stop "${INFERENCE_CONTAINER}"
  } >> "$task_log" 2>&1
  STOP_EXIT=$?

  TRAIN_EXIT=1
  if [ "$STOP_EXIT" -eq 0 ]; then
    {
      echo ""
      echo "=== Running training job: ${project}/${task_name} (engine=${engine}, version=${version}) ==="
      cd "$TRAINING_DIR" && . .venv/bin/activate && python scripts/train.py \
        --project "${project}" --task "${task_name}" --engine "${engine}" --version "${version}"
    } >> "$task_log" 2>&1
    TRAIN_EXIT=$?
  else
    echo "Skipping training run: failed to stop the inference container (see log)." >> "$task_log"
  fi

  # ALWAYS restart inference afterward, regardless of stop/train success.
  {
    echo ""
    echo "=== Restarting inference container ==="
    docker start "${INFERENCE_CONTAINER}"
    for i in $(seq 1 24); do
      HEALTH="$(docker inspect --format='{{.State.Health.Status}}' "${INFERENCE_CONTAINER}" 2>/dev/null || echo unknown)"
      echo "  [$i] health: ${HEALTH}"
      [ "$HEALTH" = "healthy" ] && break
      sleep 5
    done
  } >> "$task_log" 2>&1
  RESTART_EXIT=$?

  if [ "$STOP_EXIT" -ne 0 ]; then
    echo "error(could not stop inference, exit=${STOP_EXIT})"
  elif [ "$TRAIN_EXIT" -ne 0 ]; then
    echo "error(training exit=${TRAIN_EXIT}, inference restart exit=${RESTART_EXIT})"
  elif [ "$RESTART_EXIT" -ne 0 ]; then
    echo "trained-but-inference-restart-failed(exit=${RESTART_EXIT}) — check manually"
  else
    echo "trained"
  fi
}

# Consecutive-failure tracking: bumps a per-task counter file on error/no-op,
# resets it on any non-error outcome. If a task hits MAX_CONSECUTIVE_FAILURES,
# auto-disable THAT TASK (not the whole queue - see header comment) rather
# than keep burning GPU time on it every 2 hours indefinitely.
check_and_record_failure() {
  local id="$1" status="$2"
  local count_file="$FAIL_DIR/${id}.count"
  case "$status" in
    error-transient*|committed-but-push-failed*|push-diverged*|*push-diverged*)
      # A LiteLLM/network blip — do NOT count toward the valve (and don't reset
      # a real streak either): just leave the counter untouched so a run of
      # transient failures can't disable a healthy task, and a real failure
      # before/after still accumulates correctly.
      log "transient error for ${id} — not counted toward the safety valve"
      ;;
    reverted*)
      local count=0
      [ -f "$count_file" ] && count="$(cat "$count_file")"
      count=$((count + 1))
      echo "$count" > "$count_file"
      if [ "$count" -ge "$MAX_CONSECUTIVE_FAILURES" ]; then
        jq --arg id "$id" '(.[] | select(.id == $id)).enabled = false' "$TASKS_FILE" > "$TASKS_FILE.tmp" && mv "$TASKS_FILE.tmp" "$TASKS_FILE"
        log "SAFETY VALVE: task '${id}' has failed ${count} times in a row — auto-disabled THIS TASK ONLY (the rest of the queue keeps running). Check ${FAIL_DIR}/${id}.count and its log, fix the issue, then 'queue.sh enable ${id}'."
        emit_alert crit "$id" "AUTO-DISABLED after ${count} consecutive failures (last: ${status}) — check: queue.sh log ${id}"
      fi
      ;;
    *)
      rm -f "$count_file"
      ;;
  esac
}

# No-op streak tracking (2026-08-25 Tier-2 hardening). Separate from the failure
# valve: a no-op is not a failure, so it never disables a task — but a long
# no-op streak means a task has silently stopped making progress (stuck item, or
# an exhausted backlog it isn't refilling). Alert exactly once at the threshold
# (== not >=) so it surfaces without spamming every subsequent cycle. Any real
# pushed progress resets the streak.
track_progress_signal() {
  local id="$1" status="$2"
  local noop_file="$NOOP_DIR/${id}.count"
  case "$status" in
    no-op)
      local c=0
      [ -f "$noop_file" ] && c="$(cat "$noop_file")"
      c=$((c + 1))
      echo "$c" > "$noop_file"
      if [ "$c" -eq "$NOOP_STREAK_ALERT" ]; then
        emit_alert warn "$id" "no-op'd ${c} cycles in a row — likely a stuck item or an unrefilled backlog; check its Next Steps."
      fi
      ;;
    pushed*)
      rm -f "$noop_file"
      ;;
    *)
      : # errors are the failure valve's job; leave the no-op streak as-is
      ;;
  esac
}

# ============================================================================
# Coder-30B fast-batch (2026-09-02). OFF by default (OVN_CODER_FAST=0). When ON,
# batches SIMPLE (classifier T1/T2) discrete items into ONE coder GPU window
# (stop 27B -> serve coder-30b -> process via the SAME run_aider_fix_task + ALL
# gates, model=coder-30b + --edit-format diff -> restore 27B). Below the
# break-even batch size, no swap (items run on 27B normally). Fully reversible:
# with the toggle OFF, CODER_DONE stays empty and OVN_ACTIVE_MODEL/OVN_EDIT_FORMAT
# stay unset, so every existing code path is byte-for-byte unchanged.
# ============================================================================
OVN_CODER_ALIAS="${OVN_CODER_ALIAS:-coder-30b}"
OVN_CODER_GGUF="${OVN_CODER_GGUF:-Qwen3-Coder-30B-A3B-Instruct-Q4_K_M.gguf}"
OVN_CODER_CTX="${OVN_CODER_CTX:-32768}"
OVN_SERVE_EVAL="${OVN_SERVE_EVAL:-/run/media/mhintermeister/secondary_drive1/LocalProjects/shrike-ai-lab/scripts/serve-eval.sh}"
CODER_DONE=""

coder_window_open() {
  mkdir -p "$STATE_DIR"; touch "$STATE_DIR/coder_window.hold"
  log "CODER WINDOW: hold set; stopping 27B (${INFERENCE_CONTAINER}); serving ${OVN_CODER_GGUF}"
  docker stop "$INFERENCE_CONTAINER" >/dev/null 2>&1 || true
  local i
  for i in $(seq 1 30); do [ "$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits 2>/dev/null | head -1)" -lt 3000 ] && break; sleep 2; done
  bash "$OVN_SERVE_EVAL" "$OVN_CODER_GGUF" "$OVN_CODER_CTX" >/dev/null 2>&1 || { log "CODER WINDOW: serve-eval failed"; return 1; }
  for i in $(seq 1 40); do [ "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8083/health 2>/dev/null)" = "200" ] && break; sleep 3; done
  [ "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8083/health 2>/dev/null)" = "200" ] || { log "CODER WINDOW: coder backend not healthy"; return 1; }
  local ok; ok="$(curl -s "$LITELLM_BASE/v1/chat/completions" -H 'Content-Type: application/json' -H "Authorization: Bearer $LITELLM_MASTER_KEY" -d "{\"model\":\"$OVN_CODER_ALIAS\",\"messages\":[{\"role\":\"user\",\"content\":\"ok\"}],\"max_tokens\":3}" 2>/dev/null | grep -c '"choices"')"
  [ "$ok" -ge 1 ] || { log "CODER WINDOW: LiteLLM did not route ${OVN_CODER_ALIAS}"; return 1; }
  log "CODER WINDOW: coder up + LiteLLM routing ${OVN_CODER_ALIAS}."
  return 0
}

coder_window_close() {
  log "CODER WINDOW: stopping coder; restoring 27B (${INFERENCE_CONTAINER})"
  docker rm -f shrike-eval >/dev/null 2>&1 || true
  docker start "$INFERENCE_CONTAINER" >/dev/null 2>&1 || true
  local i
  for i in $(seq 1 30); do [ "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8081/health 2>/dev/null)" = "200" ] && break; sleep 3; done
  rm -f "$STATE_DIR/coder_window.hold"
  if [ "$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8081/health 2>/dev/null)" = "200" ]; then
    log "CODER WINDOW: 27B restored + healthy."
  else
    log "CODER WINDOW: WARNING 27B not healthy after restore — gpu_autoswap watcher will retry."
    emit_alert warn "coder-window" "27B did not health-check after a coder window; watcher should restore it. Check docker ps."
  fi
}

coder_process_index() {
  local i="$1"
  local ID TYPE ENABLED TASK_LOG REPO REPO_BASENAME HOLD_FILE PROMPT PERSISTENT MAP_TOKENS SKIP_AGENTS_MD MAX_FILES PROTECTED_FILES TIMEOUT_SECS BRANCH STATUS VERSION_OR_BRANCH
  ID="$(jq -r ".[$i].id" "$TASKS_FILE")"
  if [ "${OVN_CODER_FAST:-0}" = "1" ]; then case " ${CODER_DONE:-} " in *" ${ID} "*) continue;; esac; fi
  TYPE="$(jq -r ".[$i].type // \"aider_fix\"" "$TASKS_FILE")"
  ENABLED="$(jq -r ".[$i].enabled | if . == null then true else . end" "$TASKS_FILE")"
  TASK_LOG="$LOG_RUN_DIR/${ID}.log"
  [ "$ENABLED" = "true" ] || return 0
  [ "$TYPE" = "aider_fix" ] || return 0
  REPO="$(jq -r ".[$i].repo" "$TASKS_FILE")"
  REPO_BASENAME="$(basename "$REPO")"; HOLD_FILE="$STATE_DIR/HOLD_${REPO_BASENAME}"
  if [ -f "$HOLD_FILE" ]; then
    if [ -n "$(find "$HOLD_FILE" -mmin +$((HOLD_MAX_HOURS * 60)) 2>/dev/null)" ]; then rm -f "$HOLD_FILE"; else
      log "[CODER] Task ${ID} skipped — repo ${REPO_BASENAME} on hold."; return 0; fi
  fi
  PROMPT="$(jq -r ".[$i].prompt" "$TASKS_FILE")"
  PERSISTENT="$(jq -r ".[$i].persistent_branch // false" "$TASKS_FILE")"
  MAP_TOKENS="$(jq -r ".[$i].map_tokens // \"\"" "$TASKS_FILE")"
  SKIP_AGENTS_MD="$(jq -r ".[$i].skip_agents_md // false" "$TASKS_FILE")"
  MAX_FILES="$(jq -r ".[$i].max_files // 2" "$TASKS_FILE")"
  PROTECTED_FILES="$(jq -r ".[$i].protected_files // [] | join(\",\")" "$TASKS_FILE")"
  TIMEOUT_SECS="$(jq -r ".[$i].timeout_secs // 600" "$TASKS_FILE")"
  if [ "$PERSISTENT" = "true" ]; then BRANCH="overnight/feature"; else BRANCH="overnight/${RUN_KEY}/${ID}"; fi
  log "=== [CODER] Task ${ID} (model=${OVN_CODER_ALIAS}, edit-format=diff) ==="
  export OVN_ACTIVE_MODEL="$OVN_CODER_ALIAS" OVN_EDIT_FORMAT="diff"
  STATUS="$(run_aider_fix_task "$ID" "$REPO" "$PROMPT" "$BRANCH" "$PERSISTENT" "$TASK_LOG" "$MAP_TOKENS" "$SKIP_AGENTS_MD" "$MAX_FILES" "$PROTECTED_FILES" "$TIMEOUT_SECS")"
  unset OVN_ACTIVE_MODEL OVN_EDIT_FORMAT
  VERSION_OR_BRANCH="$BRANCH"
  log "Task ${ID}: ${STATUS}"
  echo "| ${ID} | ${TYPE} | ${STATUS} (coder) | ${VERSION_OR_BRANCH} | ${TASK_LOG} |" >> "$REPORT_FILE"
  [ -x "$SCRIPT_DIR/scripts/ovn_item_guard.sh" ] && "$SCRIPT_DIR/scripts/ovn_item_guard.sh" "$REPO" "$STATUS" "$STATE_DIR" "$ID" "${TASK_LOG:-}" 2>/dev/null || true
  check_and_record_failure "$ID" "$STATUS"
  [ -x "$SCRIPT_DIR/scripts/ovn_cycle_triage.sh" ] && "$SCRIPT_DIR/scripts/ovn_cycle_triage.sh" "$REPO" "$STATUS" "$TASK_LOG" "$STATE_DIR" "$ID" 2>/dev/null || true
  track_progress_signal "$ID" "$STATUS"
  CODER_DONE="${CODER_DONE} ${ID}"
}

coder_fast_prepass() {
  local min="${OVN_CODER_MIN_BATCH:-4}" i explicit persist prompt tag
  local idxs=""
  for i in $(seq 0 $((TASK_COUNT - 1))); do
    [ "$(jq -r ".[$i].type // \"aider_fix\"" "$TASKS_FILE")" = "aider_fix" ] || continue
    [ "$(jq -r ".[$i].enabled | if . == null then true else . end" "$TASKS_FILE")" = "true" ] || continue
    explicit="$(jq -r ".[$i].coder_eligible // \"\"" "$TASKS_FILE")"
    [ "$explicit" = "false" ] && continue
    if [ "$explicit" = "true" ]; then idxs="${idxs} ${i}"; continue; fi
    persist="$(jq -r ".[$i].persistent_branch // false" "$TASKS_FILE")"
    if [ "$persist" = "true" ] && [ "${OVN_CODER_INCLUDE_PERSISTENT:-0}" != "1" ]; then continue; fi
    prompt="$(jq -r ".[$i].prompt" "$TASKS_FILE")"
    tag="$(python3 "$SCRIPT_DIR/scripts/ovn_classify.py" --tag "$prompt" 2>/dev/null || echo '')"
    case "$tag" in *"·T1·"*|*"·T2·"*) idxs="${idxs} ${i}";; esac
  done
  local n; n="$(echo $idxs | wc -w)"
  if [ "$n" -lt "$min" ]; then
    log "CODER FAST BATCH: ${n} eligible simple item(s) < break-even ${min} — NO coder swap; all items run on 27B."
    return 0
  fi
  log "CODER FAST BATCH: ${n} eligible simple item(s) >= break-even ${min} — opening coder window."
  if ! coder_window_open; then
    log "CODER FAST BATCH: window open FAILED — restoring 27B, all items fall back to 27B."
    coder_window_close
    CODER_DONE=""
    return 0
  fi
  for i in $idxs; do coder_process_index "$i"; done
  coder_window_close
  log "CODER FAST BATCH: done (${n} item(s)); handing remaining items to 27B."
}


if [ "${OVN_CODER_FAST:-0}" = "1" ]; then coder_fast_prepass; fi

REMAINING_SKIPPED=0
for i in $(seq 0 $((TASK_COUNT - 1))); do
  if [ -f "$PAUSE_FLAG" ]; then
    REMAINING_NOW=$((TASK_COUNT - i))
    log "Queue paused mid-run (${PAUSE_FLAG} exists) — stopping before task $((i + 1))/${TASK_COUNT}. ${REMAINING_NOW} task(s) skipped."
    for j in $(seq "$i" $((TASK_COUNT - 1))); do
      SKIPPED_ID="$(jq -r ".[$j].id" "$TASKS_FILE")"
      echo "| ${SKIPPED_ID} | - | skipped(paused) | - | - |" >> "$REPORT_FILE"
    done
    REMAINING_SKIPPED=1
    break
  fi

  ID="$(jq -r ".[$i].id" "$TASKS_FILE")"
  TYPE="$(jq -r ".[$i].type // \"aider_fix\"" "$TASKS_FILE")"
  ENABLED="$(jq -r ".[$i].enabled | if . == null then true else . end" "$TASKS_FILE")"
  TASK_LOG="$LOG_RUN_DIR/${ID}.log"

  if [ "$ENABLED" != "true" ]; then
    log "Task ${ID} (type=${TYPE}) is disabled — skipping"
    echo "| ${ID} | ${TYPE} | disabled | - | - |" >> "$REPORT_FILE"
    continue
  fi

  log "=== Task ${ID} (type=${TYPE}) ==="
  _TASK_START_TS="$(date +%s)"

  if [ "$TYPE" = "train_job" ]; then
    PROJECT="$(jq -r ".[$i].project" "$TASKS_FILE")"
    TASK_NAME="$(jq -r ".[$i].task" "$TASKS_FILE")"
    ENGINE="$(jq -r ".[$i].engine // \"unsloth\"" "$TASKS_FILE")"
    VERSION="$(jq -r ".[$i].version // \"overnight-${RUN_KEY}-${ID}\"" "$TASKS_FILE")"
    STATUS="$(run_train_job_task "$ID" "$PROJECT" "$TASK_NAME" "$ENGINE" "$VERSION" "$TASK_LOG")"
    VERSION_OR_BRANCH="$VERSION"
  else
    REPO="$(jq -r ".[$i].repo" "$TASKS_FILE")"

    # Human-hold check (2026-08-25 Tier-2 hardening): skip a repo a human is
    # actively editing, so live manual fixes don't race the working-tree reset.
    # Safer than `disable` — doesn't touch the failure counter. Auto-expires.
    REPO_BASENAME="$(basename "$REPO")"
    HOLD_FILE="$STATE_DIR/HOLD_${REPO_BASENAME}"
    if [ -f "$HOLD_FILE" ]; then
      if [ -n "$(find "$HOLD_FILE" -mmin +$((HOLD_MAX_HOURS * 60)) 2>/dev/null)" ]; then
        log "Hold on ${REPO_BASENAME} is older than ${HOLD_MAX_HOURS}h — auto-expiring and proceeding."
        rm -f "$HOLD_FILE"
        emit_alert warn "$ID" "auto-expired a stale ${HOLD_MAX_HOURS}h+ hold on ${REPO_BASENAME}"
      else
        log "Task ${ID} skipped — repo ${REPO_BASENAME} is on hold (queue.sh release ${REPO_BASENAME} to clear)."
        echo "| ${ID} | ${TYPE} | held(${REPO_BASENAME}) | - | - |" >> "$REPORT_FILE"
        continue
      fi
    fi

    PROMPT="$(jq -r ".[$i].prompt" "$TASKS_FILE")"
    PERSISTENT="$(jq -r ".[$i].persistent_branch // false" "$TASKS_FILE")"
    MAP_TOKENS="$(jq -r ".[$i].map_tokens // \"\"" "$TASKS_FILE")"
    SKIP_AGENTS_MD="$(jq -r ".[$i].skip_agents_md // false" "$TASKS_FILE")"
    MAX_FILES="$(jq -r ".[$i].max_files // 2" "$TASKS_FILE")"
    PROTECTED_FILES="$(jq -r ".[$i].protected_files // [] | join(\",\")" "$TASKS_FILE")"
    # Per-task implement timeout (2026-08-25). Default 600s; set "timeout_secs"
    # in a task for a legitimately larger piece of work so it isn't killed
    # mid-generation and falsely counted toward the safety valve.
    TIMEOUT_SECS="$(jq -r ".[$i].timeout_secs // 600" "$TASKS_FILE")"
    if [ "$PERSISTENT" = "true" ]; then
      BRANCH="overnight/feature"
    else
      BRANCH="overnight/${RUN_KEY}/${ID}"
    fi
    STATUS="$(run_aider_fix_task "$ID" "$REPO" "$PROMPT" "$BRANCH" "$PERSISTENT" "$TASK_LOG" "$MAP_TOKENS" "$SKIP_AGENTS_MD" "$MAX_FILES" "$PROTECTED_FILES" "$TIMEOUT_SECS")"
    # Best-of-N pilot (2026-09-04, gated OVN_BESTOF_N>1): a HARD item that did not land gets
    # re-solved from a fresh baseline up to N times; the test gate keeps the first that lands.
    _bestn="${OVN_BESTOF_N:-1}"; _btry=1
    if [ "$_bestn" -gt 1 ] && grep -qiE '\[T[345]\]|refactor|multi-file|multiple files' "$TASK_LOG" 2>/dev/null; then
      while [ "$_btry" -lt "$_bestn" ] && echo "$STATUS" | grep -qiE 'revert|no-op|noop|error' && ! echo "$STATUS" | grep -qiE 'oversized|blocked|needs-decision|exhausted|skip'; do
        _btry=$((_btry+1))
        log "best-of-N: item ${ID} attempt ${_btry}/${_bestn} (prev: ${STATUS})"
        STATUS="$(run_aider_fix_task "$ID" "$REPO" "$PROMPT" "$BRANCH" "$PERSISTENT" "$TASK_LOG" "$MAP_TOKENS" "$SKIP_AGENTS_MD" "$MAX_FILES" "$PROTECTED_FILES" "$TIMEOUT_SECS")"
      done
    fi
    VERSION_OR_BRANCH="$BRANCH"
  fi

  _TASK_DURATION_S=$(( $(date +%s) - ${_TASK_START_TS:-$(date +%s)} ))
  log "Task ${ID}: ${STATUS} (${_TASK_DURATION_S}s)"
  echo "| ${ID} | ${TYPE} | ${STATUS} | ${VERSION_OR_BRANCH} | ${TASK_LOG} | ${_TASK_DURATION_S}s |" >> "$REPORT_FILE"
  record_outcome "$ID" "${REPO_BASENAME:-}" "$STATUS" "${PROMPT:-}" "$TYPE" "${_btry:-1}" "${TASK_LOG:-}" "${_TASK_DURATION_S:-0}"
  # Per-item fail cap runs FIRST (2026-08-30): if ONE bad item hits the cap it
  # parks itself AND resets the task-valve counter, so a single broken item can't
  # auto-disable the whole repo (the double-jeopardy that kept disabling shrike).
  # check_and_record_failure runs AFTER and sees the reset counter -> only a repo
  # where MANY DIFFERENT items fail still trips the valve.
  [ "$TYPE" != "train_job" ] && [ -x "$SCRIPT_DIR/scripts/ovn_item_guard.sh" ] && \
    "$SCRIPT_DIR/scripts/ovn_item_guard.sh" "$REPO" "$STATUS" "$STATE_DIR" "$ID" "${TASK_LOG:-}" 2>/dev/null || true
  check_and_record_failure "$ID" "$STATUS"
  [ "$TYPE" != "train_job" ] && [ -x "$SCRIPT_DIR/scripts/ovn_cycle_triage.sh" ] && \
    "$SCRIPT_DIR/scripts/ovn_cycle_triage.sh" "$REPO" "$STATUS" "$TASK_LOG" "$STATE_DIR" "$ID" 2>/dev/null || true
  track_progress_signal "$ID" "$STATUS"
done

# End-of-cycle auto-planning + refill (race-free — run.lock is still held here). ovn_planner
# decomposes the next [ready] roadmap feature into backlog items when a backlog runs low;
# queue_refill then pulls backlog -> the live queue. This is where the fleet self-sustains from
# roadmap/<repo>.md — done HERE (not a separate cron) because a full cycle holds the lock ~16min,
# which was starving fleet_autofix's refill. 2026-09-07.
# timeout-GUARDED so a slow/hung 27B call can NEVER wedge the whole fleet (2026-09-07: an old prework
# process infinite-looped here for 2.5h holding run.lock -> zero cycles. never again).
[ -f "$SCRIPT_DIR/ovn_planner.sh" ] && timeout 240 bash "$SCRIPT_DIR/ovn_planner.sh" >> "$SCRIPT_DIR/logs/ovn_planner.log" 2>&1 || true
[ -f "$SCRIPT_DIR/queue_refill.sh" ] && MIN_DOABLE=15 timeout 180 bash "$SCRIPT_DIR/queue_refill.sh" >> "$SCRIPT_DIR/logs/queue_refill.log" 2>&1 || true
# NOTE: prework (the 27B briefing Claude-bound tasks) is DELIBERATELY NOT here anymore — it competes
# with the fleet for the GPU and, when it hung, wedged the whole loop. It now runs as its own
# timeout-guarded cron (ovn_prework cron) OUT of the fleet's critical path.

if [ "$REMAINING_SKIPPED" -eq 1 ]; then
  log "Run ${RUN_KEY} stopped early due to pause. Report: ${REPORT_FILE}"
else
  log "Run ${RUN_KEY} complete. Report: ${REPORT_FILE}"
fi

[ -x "$SCRIPT_DIR/cycle_notify.sh" ] && "$SCRIPT_DIR/cycle_notify.sh" "$REPORT_FILE" 2>/dev/null || true

# --- daily branch hygiene: reconcile overnight/feature -> main, prune dead branches ---
# Runs after each full pass so agent work never silently orphans on overnight/feature.
# Skip when paused mid-run, or disable via RUN_BRANCH_HYGIENE=0.
HYGIENE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ "$REMAINING_SKIPPED" -ne 1 ] && [ "${RUN_BRANCH_HYGIENE:-1}" = "1" ] && [ -x "$HYGIENE_DIR/branch_hygiene.sh" ]; then
  log "Running daily branch hygiene..."
  { echo ""; echo "### Branch hygiene"; echo "| repo | outcome |"; echo "|---|---|"; } >> "$REPORT_FILE"
  REPORT_FILE="$REPORT_FILE" "$HYGIENE_DIR/branch_hygiene.sh" --from-config 2>&1 | while IFS= read -r l; do log "$l"; done
fi
