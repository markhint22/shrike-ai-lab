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

Quality bar: match existing code style, keep the diff minimal and focused on the one item, use the project's existing test framework/layout, don't add new dependencies unless needed. Do NOT edit OVERNIGHT_PROGRESS.md at all - it is READ-ONLY; the runner maintains it for you from your commit message, so any edit you make to it will be ignored/overwritten and just wastes your budget. Instead, record outcomes by adding trailer lines at the very END of your commit message (one per line, nothing after them): 'DONE: <the exact Next Steps item text you fully completed>' when you finish an item; 'DECISION: <one line - what you decided and why>' when you make a judgment call; 'NEW: <one short item>' to add a follow-up or a newly-chosen item. The runner checks the box, records the decision, and adds new items for you. Before adding a new function, grep for its name first - edit the existing one rather than adding a duplicate definition. To DELETE a file, do NOT open or edit it - deleting a file by editing it forces you to reproduce the whole file as removed lines, which wastes your entire budget and the call gets killed with nothing done. Instead just write a line 'DELETE: <path>' (in your commit message or your reply) and the runner will remove the file for you cheaply. Be decisive: pick the files you need in ONE pass and stop - do not narrate a long chain of 'let me also check this file... and this one... and this one' before ever writing code. If you are not sure a file is needed, do not ask for it - work with what you have and adjust later if a real problem shows up. Do NOT quote, restate, or diff OVERNIGHT_PROGRESS.md's Next Steps list back in your response - you have already read it, just silently pick the single top not-yet-done item and go straight to the code change; never write to that file - your commit-message trailers are how you report progress. If a file you need isn't visible, use the repo-map/existing open files to find its real path first - don't guess a path (e.g. assuming a services/ location for something that actually lives under routers/ or schemas/) and ask for the wrong file, which wastes the whole turn when it silently isn't found. If an item is tagged NEEDS DECISION or NEEDS HUMAN DECISION, do not skip it: use your best engineering/product judgment, make a real, reasonable choice, and implement it - but you MUST clearly record what you decided and a one-line why using a 'DECISION: <what and why>' trailer line in your commit message (the runner writes it into OVERNIGHT_PROGRESS.md's Decisions Made section for you - do not edit that file yourself), so a human can review and override it later. Never silently guess without leaving that record. If EVERY remaining Next Steps item is explicitly marked off-limits to automated cycles (HARD FILE BAN, HUMAN-ONLY BLOCKED ITEM, or requires a human doing something outside this tool, e.g. an editor GUI), do not reason about, argue for, or attempt any of them, no matter how tempting a workaround seems - immediately stop reasoning about the blocked items and instead pick a different, genuinely automatable idea (a small bug fix, missing test coverage, docs improvement, or refactor), implement THAT, and note it with a 'NEW: <item>' trailer in your commit message (the runner adds it to the list - do not edit the doc yourself), exactly as you would if the list were empty. This is a standing policy: keep making real product/design progress elsewhere in the repo rather than sitting idle re-litigating whether a blocked item is really blocked - that reasoning alone burns the whole budget with nothing committed. This model generates at roughly 5 tokens/second on this box and each call is hard-killed at 600 seconds (~3000 tokens) - if you spend more than a few hundred tokens reasoning before writing the actual diff, the call WILL be killed with no commit and the cycle is wasted. Budget yourself: a couple sentences on what you're changing and why, then the diff. If you notice you're still explaining/exploring after that, stop explaining and write the diff with your current best understanding instead - a slightly imperfect real change beats a well-reasoned non-answer that gets killed mid-thought. This also applies to test-writing tasks specifically: even with zero narration, writing exhaustive tests for every method in a large file is itself too much output for one 600-second call - when adding tests to a low/zero-coverage file, write 4-6 focused test cases covering the most important behavior and stop there, then mark real, partial progress (which file, how many methods still need coverage) rather than attempting the whole file and running out of budget with nothing committed. The next cycle can pick up where you left off. When writing tests for a class or module: you MUST have that file open and have actually read its real method names/signatures before writing a single assertion - never guess a method name because it sounds conventional (e.g. get_status(), validate_x()) if you have not confirmed it exists. This has caused full test-file rewrites more than once (real classes had different method names than assumed, used sync not async, or had properties instead of module-level names to mock). If a test you already wrote doesn't match the real code, fix the TEST - never add a new, separate, parallel implementation to the module just to make your own guessed API real; that produces unused dead code and fixes nothing. When adding a new test file, verify the project's actual test-runner include pattern first (e.g. a vitest.config.ts 'include' list, or a JUnit version mismatch) - a test file with the wrong name/suffix or wrong test framework can compile fine and even show a green build while contributing ZERO executed tests, silently. Confirm your new test file shows up with a real pass count in the tool's own output (not just 'no errors') before considering the task done."
TRAINING_DIR="$HOME/shrike-ai-lab-training"

TASKS_FILE="$SCRIPT_DIR/tasks.json"
STATE_DIR="$SCRIPT_DIR/state"
FAIL_DIR="$STATE_DIR/failures"
NOOP_DIR="$STATE_DIR/noops"
LOG_DIR="$SCRIPT_DIR/logs"
REPORT_DIR="$SCRIPT_DIR/reports"
mkdir -p "$STATE_DIR" "$FAIL_DIR" "$NOOP_DIR" "$LOG_DIR" "$REPORT_DIR"

PAUSE_FLAG="$STATE_DIR/PAUSED"
ALERTS_FILE="$STATE_DIR/alerts.log"
MAX_CONSECUTIVE_FAILURES=3
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
  log "ALERT(${sev}) ${id}: ${msg}"
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

  while IFS= read -r -d '' venv_pytest; do
    dir="${venv_pytest%/.venv/bin/pytest}"
    # 240s (2026-08-15, was 120s): confirmed live, repeatedly, that
    # iptv_apps's full backend suite (657+ tests and growing) genuinely
    # takes 200+ seconds to run in full. At 120s the cap fired on EVERY
    # cycle regardless of whether tests actually passed, timeout's exit
    # code got treated as a real failure, and every report said
    # "tests:FAIL" even when the suite was 100% green - a misleading
    # signal that would only get worse as more tests get added.
    echo "--- verify: pytest in ${dir} (240s cap) ---" >> "$task_log"
    ( cd "$dir" && timeout 240 ./.venv/bin/pytest -q --no-cov ) >> "$task_log" 2>&1
    [ $? -ne 0 ] && any_failed=1
    any_ran=1
  done < <(find . -maxdepth 4 -type f -path "*/.venv/bin/pytest" -print0 2>/dev/null)

  while IFS= read -r -d '' pkg; do
    dir="$(dirname "$pkg")"
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
          timeout 60 "$HOME/godot/godot4" --headless --path . --import &&
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
        grep -qE "SCRIPT ERROR|Parse Error|ERROR: Failed to load" "$GODOT_OUT" && any_failed=1
        rm -f "$XML_OUT"
      else
        # No test framework yet: just confirm the project still parses/runs.
        echo "--- verify: godot4 --headless in ${dir} (90s cap, no GUT yet) ---" >> "$task_log"
        (
          cd "$dir" &&
          timeout 60 "$HOME/godot/godot4" --headless --path . --import &&
          timeout 30 "$HOME/godot/godot4" --headless --path . --quit-after 60
        ) > "$GODOT_OUT" 2>&1
        cat "$GODOT_OUT" >> "$task_log"
        grep -qE "SCRIPT ERROR|Parse Error|ERROR: Failed to load" "$GODOT_OUT" && any_failed=1
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
        elif [ ! -f "$DIVERGE_FLAG" ]; then
          touch "$DIVERGE_FLAG"
          emit_alert warn "$id" "local ${branch} has DIVERGED from origin (both have unique commits) — manual reconcile needed; runner left the clone untouched."
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
    AIDER_BASE_ARGS=(
      --yes-always --no-check-update --edit-format udiff
      --model "openai/${MODEL_NAME}"
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
    if [ -n "$map_tokens" ] && [ "$map_tokens" != "null" ]; then
      AIDER_BASE_ARGS+=(--map-tokens "$map_tokens")
    fi

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
    MAX_IMPLEMENT_ATTEMPTS=2
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

    SCOUT_PROMPT="Before doing anything else: decide which existing repo files (at most ${max_files}) you would need to see in full to complete the task below. Reply with ONLY those file paths relative to the repo root, one per line, and nothing else - no explanation, no edits. If you don't need to see any files beyond what is already open, reply with exactly: NONE

Task: ${full_prompt}"

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
      echo "--- scout pass committed despite --no-auto-commits; reset to ${BEFORE_SHA} ---" >> "$task_log"
      echo "error(scout committed unexpectedly)"
      return
    fi

    ATTEMPT=1
    while [ "$ATTEMPT" -le "$MAX_IMPLEMENT_ATTEMPTS" ]; do
      echo "--- implement attempt ${ATTEMPT}/${MAX_IMPLEMENT_ATTEMPTS} (${#FILE_ARGS[@]} file(s) pre-loaded) ---" >> "$task_log"
      timeout "$aider_timeout" aider "${AIDER_BASE_ARGS[@]}" \
        ${READ_ARGS[@]+"${READ_ARGS[@]}"} \
        ${PROGRESS_READ_ARGS[@]+"${PROGRESS_READ_ARGS[@]}"} \
        ${FILE_ARGS[@]+"${FILE_ARGS[@]}"} \
        --message "${full_prompt}" \
        >> "$task_log" 2>&1
      AIDER_EXIT=$?

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
        echo "committed-but-push-failed"
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
    error-transient*)
      # A LiteLLM/network blip — do NOT count toward the valve (and don't reset
      # a real streak either): just leave the counter untouched so a run of
      # transient failures can't disable a healthy task, and a real failure
      # before/after still accumulates correctly.
      log "transient error for ${id} — not counted toward the safety valve"
      ;;
    error*|committed-but-push-failed)
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
    VERSION_OR_BRANCH="$BRANCH"
  fi

  log "Task ${ID}: ${STATUS}"
  echo "| ${ID} | ${TYPE} | ${STATUS} | ${VERSION_OR_BRANCH} | ${TASK_LOG} |" >> "$REPORT_FILE"
  check_and_record_failure "$ID" "$STATUS"
  track_progress_signal "$ID" "$STATUS"
done

if [ "$REMAINING_SKIPPED" -eq 1 ]; then
  log "Run ${RUN_KEY} stopped early due to pause. Report: ${REPORT_FILE}"
else
  log "Run ${RUN_KEY} complete. Report: ${REPORT_FILE}"
fi

# --- daily branch hygiene: reconcile overnight/feature -> main, prune dead branches ---
# Runs after each full pass so agent work never silently orphans on overnight/feature.
# Skip when paused mid-run, or disable via RUN_BRANCH_HYGIENE=0.
HYGIENE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ "$REMAINING_SKIPPED" -ne 1 ] && [ "${RUN_BRANCH_HYGIENE:-1}" = "1" ] && [ -x "$HYGIENE_DIR/branch_hygiene.sh" ]; then
  log "Running daily branch hygiene..."
  { echo ""; echo "### Branch hygiene"; echo "| repo | outcome |"; echo "|---|---|"; } >> "$REPORT_FILE"
  REPORT_FILE="$REPORT_FILE" "$HYGIENE_DIR/branch_hygiene.sh" --from-config 2>&1 | while IFS= read -r l; do log "$l"; done
fi
