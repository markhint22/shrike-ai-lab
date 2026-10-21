#!/usr/bin/env bash
# ovn_stage_runner.sh — MULTI-STAGE executor for hard (T3+) items the one-shot fleet keeps failing.
#
# Instead of one all-or-nothing aider shot (lands or reverts), decompose the item into an ORDERED
# list of small sub-steps and run each through plan->act->test->pass/fail with retries. Each passed
# sub-step is committed (partial progress survives even if a later step fails). A sub-step that keeps
# failing is RE-DECOMPOSED into smaller pieces once, then retried; if it still fails it's marked
# BLOCKED and we move on. Everything is logged per-step so we can watch the higher-tier pass rate and
# chip away at what the 27B "can't do".
#
# Usage: ovn_stage_runner.sh <repo> ["<item text>"]   (no item -> first doable T3+ item in the queue)
# Tunables: OVN_STAGE_MAX_ATTEMPTS(2 per step) OVN_STAGE_MAX_STEPS(6) OVN_STAGE_REDECOMP(1)
set -uo pipefail
# 2026-10-04: GUT also descends into tests/*/ (release/battle/steam were never run). Verified green on xlite claude/feature (389 scripts, 2862 tests, 0 failing).
# Kill switch: OVN_GUT_SUBDIRS=off. 2026-10-13: the flag comes from lib_gut_xml.sh gut_subdirs_flag (sourced below) - one definition shared with run_overnight.sh's per-cycle verify.
cd "$HOME/overnight-queue" || exit 1
export PATH="$HOME/aider-venv/bin:/usr/local/bin:/usr/bin:/bin:${PATH:-}"
LITELLM="${LITELLM_BASE:-http://localhost:4000}"; LKEY="${LITELLM_MASTER_KEY:-sk-shrike-local}"
MODEL="${OVN_MODEL:-qwen-dflash-27B}"
MAX_ATT="${OVN_STAGE_MAX_ATTEMPTS:-2}"; MAX_STEPS="${OVN_STAGE_MAX_STEPS:-6}"; REDECOMP="${OVN_STAGE_REDECOMP:-1}"
STEP_TIMEOUT="${OVN_STAGE_STEP_TIMEOUT:-350}"
repo="${1:?repo required}"; item_arg="${2:-}"
rd="repos/$repo"; [ -d "$rd/.git" ] || { echo "no clone $rd"; exit 1; }
RUNID="$(date -u +%Y%m%d-%H%M%S)-$$"
_ST0="$(date +%s)"
mkdir -p state/stage_runs logs
SLOG="state/stage_runs/${repo}-${RUNID}.jsonl"
LOG="logs/ovn_stage_runner.log"; say(){ echo "$(date '+%F %T') [$repo] $*" | tee -a "$LOG"; }
jlog(){ echo "$1" >> "$SLOG"; }   # $1 = a json object string

# capstone_escalate_on_failure — escalation cap for a stuck "confirm zero regressions"
# capstone item (2026-09-28).
#
# The regression-check fast-path below is a single run-and-report, not a retry loop, so a
# capstone item correctly never gets hammered in a tight loop when its VERIFY fails — but
# nothing ever advanced PAST it either. The picker (head -1 of doable T3-5, after the
# python-preference filter) re-selects this EXACT same item on every subsequent invocation
# forever, permanently starving every other doable T3-5 item behind it — ovn_stage_sweep.sh
# invokes this script per-REPO, not per-item, so there is no $ID here for
# ovn_item_guard.sh's own no-op-streak AUTO-SKIP to ever see and act on. Confirmed live on
# xlite: an "index_from_label caused zero regressions" item looped
# capstone_regression_detected 22+ times over 7 hours, starving the whole T3-5 lane.
#
# Cap consecutive detections per item (hash-keyed on the item text so re-picking the
# identical line accumulates, same OVN_RECOVER_LINEAGE_CAP=2 house style
# ovn_recover_parked.sh already uses for its own escalation) and hand off to [CLAUDE] once
# hit — a real regression is genuine signal that needs a human/Claude diagnosis, not
# endless unattended re-verification. The picker's own doable-item exclusion (extended
# below to also skip [CLAUDE]) then moves past it automatically.
#
# Args: $1=repo_dir (the "$rd" clone path) $2=item text (no leading "- [ ] ") $3=repo basename
#       $4=tier $5=run id (for jlog) $6=state dir (default "state", override in tests)
# Emits jlog-shaped JSON on stdout when it escalates (caller decides whether/where to log it).
capstone_escalate_on_failure() {
  local rd="$1" item="$2" repo="$3" tier="$4" runid="$5" state_dir="${6:-state}"
  local cap countf n lineno
  cap="${OVN_STAGE_CAPSTONE_CAP:-2}"
  mkdir -p "$state_dir/stage_runs/capstone_fails" 2>/dev/null
  countf="$state_dir/stage_runs/capstone_fails/${repo}__$(printf '%s' "$item" | md5sum | cut -d' ' -f1).count"
  n=$(( $(cat "$countf" 2>/dev/null || echo 0) + 1 ))
  printf '%s' "$n" > "$countf"
  [ "$n" -ge "$cap" ] || return 1
  lineno="$(grep -nF -- "- [ ] ${item}" "$rd/OVERNIGHT_PROGRESS.md" | head -1 | cut -d: -f1)"
  if [ -n "$lineno" ]; then
    sed -i "${lineno}s#^- \[ \] #- [ ] [CLAUDE] #" "$rd/OVERNIGHT_PROGRESS.md"
    if ! git -C "$rd" diff --quiet OVERNIGHT_PROGRESS.md 2>/dev/null; then
      git -C "$rd" add OVERNIGHT_PROGRESS.md
      git -C "$rd" commit -q -m "chore(queue): escalate capstone regression-check item after ${n} consecutive real-regression detections"
      git -C "$rd" push -q origin overnight/feature 2>/dev/null || { git -C "$rd" pull -q --rebase origin overnight/feature && git -C "$rd" push -q origin overnight/feature; }
    fi
  fi
  rm -f "$countf" 2>/dev/null
  echo "{\"run\":\"$runid\",\"repo\":\"$repo\",\"tier\":$tier,\"event\":\"capstone_escalated\",\"n\":$n}"
  return 0
}

# ONLY ONE stage runner at a time. Concurrent stage runners (a manual run + the cron sweep + the loop)
# each spawn an aider that contends on the SINGLE-THREADED llama-server, collapsing tok/s (60 solo ->
# ~4 under 4-way load) and timing steps out. Serialize them so each gets the GPU to itself.
# 2026-09-19: migrated to the shared scripts/lib_lock.sh helper (Phase 1, day 3 - branch_hygiene.sh
# was day 1 in 9054f37, fleet_autofix.sh was day 2 in 193923b; see those commits + lib_lock.sh's
# header for the full root-cause writeup). A wait of 30 is byte-for-byte equivalent to the
# `flock -w 30 209` this replaces, plus an ntfy alert if the wait itself times out - the actual
# "stuck," not "briefly busy," signal. fd 209 is unchanged (the watchdog subshell below still
# closes it the same way).
source scripts/lib_lock.sh
# 2026-10-02 (bugs-first): the picker below must order items the same way every other selector does (scripts/lib_item_select.sh). Identity fallbacks if the
# lib is missing so the picker degrades to the old behaviour.
source scripts/lib_item_select.sh 2>/dev/null || true
command -v ovn_bug_first_order >/dev/null 2>&1 || ovn_bug_first_order() { cat; }
command -v ovn_has_bug_line >/dev/null 2>&1 || ovn_has_bug_line() { return 1; }
command -v ovn_is_manual_bug_text >/dev/null 2>&1 || ovn_is_manual_bug_text() { return 1; }
# 2026-10-02 (bugs-first review fix): the park blocks at the bottom used to stamp '[AUTO-SKIP staged ...]' on a manual bug after ONE staged cycle - every
# manual bug is tier T3, so it always comes through here - bypassing the 2-attempt cap with no escalation record and no relay note (it then read as
# needs-human, the exact failure this policy removes). A bug is now counted + escalated through the SAME helper the guard uses.
source scripts/lib_bug_escalate.sh 2>/dev/null || true
command -v ovn_bug_escalate >/dev/null 2>&1 || ovn_is_manual_bug_text() { return 1; }   # no escalation helper => keep the old (AUTO-SKIP) behaviour, never an uncapped open loop
# 2026-09-29: import-guarded pytest-xdist flag for full_verify's full-suite run (see the lib).
# Falls back to serial if the lib is missing.
source scripts/lib_pytest_parallel.sh 2>/dev/null || ovn_pytest_par_args(){ :; }
# shellcheck source=scripts/lib_tree_guard.sh
source scripts/lib_tree_guard.sh 2>/dev/null || ovn_unstage_abs_symlinks(){ :; }
# 2026-10-02 (harness Y4): ovn_item_hash for the unverified-run outcome row comes from lib_item_select.sh, already sourced above. Do NOT source it again
# here: that would redefine ovn_is_manual_bug_text after the fail-safe stub that follows lib_bug_escalate.sh.
# 2026-10-01: correct GUT green check (root <testsuites failures/errors); the old grep 'failures="0"' passed red suites.
source scripts/lib_gut_xml.sh 2>/dev/null || { gut_xml_green(){ return 1; }; gut_xml_summary(){ echo "lib_gut_xml.sh missing"; }; }
# partial-deploy guard (2026-10-13, review of package gate): a lib_gut_xml.sh that sources fine but PREDATES gut_subdirs_flag/gut_load_failure_line (rsync order, stale live copy) must not leave
# them undefined - an undefined gut_load_failure_line made the hygiene gate MERGE a parse-broken tests/<sub> script. Define each fallback only when the function is missing.
declare -F gut_subdirs_flag >/dev/null 2>&1 || gut_subdirs_flag(){ [ "${OVN_GUT_SUBDIRS:-on}" = "off" ] || printf '%s' "-ginclude_subdirs"; }
GUT_SUBDIRS="$(gut_subdirs_flag)"
# 2026-10-04 (QA audit H): explicit run of the cycle's new/changed test files (ovn_run_new_tests); lib missing => step is skipped.
source scripts/lib_new_tests.sh 2>/dev/null || true
# 2026-10-13 (package stage): deterministic guards (mis-targeted Verify steps / items, class_name conflicts, named tests, item-VERIFY red-before, web verify). Lib missing => every guard is a no-op.
source scripts/lib_stage_guards.sh 2>/dev/null || true
source scripts/lib_outcome_acct.sh 2>/dev/null || true   # 2026-10-18 (D4): ovn_oa_commits for the outcome row (absent => commits=[])
declare -F stage_step_mistarget >/dev/null 2>&1 || { stage_step_mistarget(){ return 1; }; stage_item_mistarget(){ return 1; }; stage_class_conflict(){ return 1; }
  stage_named_tests_check(){ return 0; }; stage_item_verify_run(){ printf 'NO_VERIFY_CLAUSE|lib missing'; }; stage_item_verify_decision(){ echo OK; }; stage_item_verify_textonly(){ return 1; }; stage_ctx_exceeded(){ grep -qiE 'context size has been exceeded|context length|context_length|prompt is too long|exceed_context|contextwindowexceeded|exceeds the available context size' "${1:-/dev/null}" 2>/dev/null; }
  stage_red_before_check(){ return 0; }; stage_web_verify(){ return 0; }; stage_tree_restore(){ return 0; }; }
if ! acquire_lock state/stage.lock 209 30 ovn-stage-runner; then exit 0; fi
# >>> d3 step-ordering helpers
# 2026-10-18 (D3-step-ordering): dependency-aware ordering of staged work (scripts/ovn_stage_order.py). OVN_STAGE_ORDER=off|shadow|enforce, default shadow (journal-only: state/stage_order_shadow.log
# + 'step_order' events in the run journal; plan, picker and steps are untouched). enforce: the picker skips queue items whose [feat:] prerequisites are not done, a red-by-design test step is merged
# into the commit of the step it needs (else reordered after it), and a step whose prerequisite step did not land is parked (the item is then PARTIAL, never checked off). Missing script => no-op.
_SO_MODE="${OVN_STAGE_ORDER:-shadow}"; case "$_SO_MODE" in off|shadow|enforce) ;; *) _SO_MODE=shadow ;; esac
_SO_PY="scripts/ovn_stage_order.py"; [ -f "$_SO_PY" ] || _SO_MODE=off
_SO_LOG="${OVN_STAGE_ORDER_LOG:-state/stage_order_shadow.log}"
_so_item_filter(){   # stdin = candidate queue lines -> stdout = the lines the picker may take (all of them unless enforce)
  local _in _out; _in="$(cat)"
  if [ "$_SO_MODE" = off ]; then printf '%s\n' "$_in"; return 0; fi
  if _out="$(printf '%s\n' "$_in" | python3 "$_SO_PY" item-filter --mode "$_SO_MODE" --progress "$rd/OVERNIGHT_PROGRESS.md" --repo "$repo" --log "$_SO_LOG" 2>/dev/null)"; then printf '%s\n' "$_out"; else printf '%s\n' "$_in"; fi
}
# <<< d3 step-ordering helpers

# HARD SELF-WATCHDOG: a hung git/aider/LLM call must NEVER leave a runner alive forever — it holds the
# lock + contends on the 27B (this exact runaway crashed tok/s to 4 and had a 58-min zombie). Recursively
# kill this process + every descendant after the cap, regardless of how we were launched.
#
# 2026-09-16 DYNAMIC REARM: this used to be a single fixed sleep (2000s) for the runner's ENTIRE
# lifetime. But the real worst-case legitimate path — up to MAX_STEPS steps, each up to MAX_ATT
# attempts plus one re-decompose's worth of sub-step attempts, THEN up to OVN_VERIFY_REPAIR_ROUNDS
# repair rounds each re-running the FULL verify suite (pytest/vitest/godot, up to 600+240+210s) —
# can legitimately clear 2000s for a 2+-step item that's genuinely still making progress, not hung.
# Confirmed live: a real iptv_apps attempt with 2 real steps + repair rounds crashed at ~1534s
# already close to the old ceiling, and a separate one got orphaned when the OUTER wrapper (a
# different bug, fixed the same day) raced past 1500s. Rather than pick one bigger fixed number
# (which either stays too tight for large items or needlessly delays hang-detection for small
# ones), rearm this watchdog once NSTEPS is known (right after decompose) to a budget scaled to
# the ACTUAL item size, capped at OVN_STAGE_HARD_TIMEOUT (now an absolute ceiling, not a fixed
# runtime, raised 2000->12600s/3.5h — see the rearm call below for the real formula). The initial
# spawn here only needs to cover flock-wait + the dedicate sleep + decompose's own retry loop
# (up to 4 attempts * 300s + backoff), so a smaller startup value still catches a genuinely hung
# decompose call quickly.
_self=$$
_wd=0
# `exec 209>&-`: the watchdog must NOT inherit the lock fd, or it holds state/stage.lock for the
# full watchdog duration AFTER the runner exits — which made sequential batch items skip ("another
# runner holds the lock"). Closing fd 209 here means the lock releases the instant the runner
# exits, independent of the watchdog's own remaining sleep.
_arm_watchdog(){ # $1 = seconds; kills any previously-armed watchdog first
  [ "$_wd" != 0 ] && kill "$_wd" 2>/dev/null
  ( exec 209>&-
    # 2026-09-30 FIX: `pgrep -P $_self` includes THIS watchdog subshell, so the old walk kill -9'd itself first and never reached the
    # runner (reproduced with a hung LLM call: the runner carried on past the watchdog). Skip our own pid.
    _me=$BASHPID
    sleep "$1"
    _kt(){ local c; for c in $(pgrep -P "$1" 2>/dev/null); do [ "$c" = "$_me" ] && continue; _kt "$c"; done; kill -9 "$1" 2>/dev/null; }
    _kt "$_self"
    rm -f "${TMPDIR:-/tmp}"/ovn_stage_"$_self".* 2>/dev/null   # 2026-10-17: SIGKILL cannot run the EXIT trap; the killed runner's prompt/attempt scratch files are removed here
  ) >/dev/null 2>&1 &
  _wd=$!
}
_arm_watchdog "${OVN_STAGE_STARTUP_TIMEOUT:-1500}"

# DEDICATED INFERENCE by default: contention was the dominant failure driver — under load the 27B
# generates too slowly and gets killed mid-edit (no-edit/timeout); SOLO it produces real edits fast
# (proven: the first genuinely-verified T3 landed only when dedicated). The lock guarantees ONE runner,
# so pausing the fleet here is safe. The fleet checks PAUSED between items; give it a moment to yield.
_dedicated=0
if [ "${OVN_STAGE_DEDICATE:-1}" = 1 ] && [ ! -f state/PAUSED ]; then
  touch state/PAUSED; date +%s > state/stage_pause_since; _dedicated=1; sleep 18
fi
# 2026-09-30 FIX: the cleanup trap used to be installed only after the worktree exists (line ~265), so the early exits ("no doable T3+
# item", capstone pass/fail, worktree failure) left state/PAUSED + stage_pause_since behind and the watchdog running until
# pause_guard.sh cleared them. Install it right after dedicated mode is switched on; the worktree removal is guarded on $wt.
cleanup(){ [ "$_wd" != 0 ] && kill "$_wd" 2>/dev/null; [ "${_dedicated:-0}" = 1 ] && rm -f state/PAUSED state/stage_pause_since; [ -n "${wt:-}" ] && git -C "$rd" worktree remove --force "$wt" >/dev/null 2>&1; rm -f "${TMPDIR:-/tmp}"/ovn_stage_"$$".* 2>/dev/null; return 0; }   # 2026-10-17: per-run scratch files (prompt/attempt/drop) die with the run even when it is killed mid-step
trap cleanup EXIT

# ---- one LiteLLM chat call: $1=prompt-file -> stdout = content. RETRIES with backoff so a collision
#      with the fleet's aider on the single-threaded llama-server queues instead of aborting. ----
llm(){ local pf="$1" body resp content i
  body="$(python3 -c "import json,sys;print(json.dumps({'model':'$MODEL','messages':[{'role':'user','content':open(sys.argv[1]).read()}],'temperature':0.2,'max_tokens':1100}))" "$pf")"
  for i in 1 2 3 4; do
    resp="$(curl -fsS --max-time 300 "$LITELLM/v1/chat/completions" -H 'Content-Type: application/json' \
      -H "Authorization: Bearer $LKEY" -d "$body" 2>>"$LOG")"
    content="$(printf '%s' "$resp" | jq -r '.choices[0].message.content // empty' 2>/dev/null)"
    # 2026-09-16: this decompose/planning call's real token spend was discarded entirely
    # (only .choices[0].message.content was ever kept) - the per-step aider calls below are
    # already tracked via stage_runs/*.jsonl, but this call that PRECEDES them never was.
    bash "$HOME/overnight-queue/scripts/ovn_log_tokens.sh" stage-decompose "$repo" \
      "$(printf '%s' "$resp" | jq -r '.usage.prompt_tokens // 0' 2>/dev/null)" \
      "$(printf '%s' "$resp" | jq -r '.usage.completion_tokens // 0' 2>/dev/null)" 2>/dev/null || true
    if [ -n "$content" ]; then printf '%s' "$content"; return 0; fi
    echo "$(date '+%F %T') llm attempt $i got empty (resp ${#resp} bytes) — backoff $((i*8))s (fleet contention?)" >> "$LOG"
    sleep $((i*8))
  done
  return 1
}

# ---- pick the item ----
# 2026-10-03 (A8): the picker is a function so the lazy bug brief (below) can re-pick after it replaced the single bug line by its decomposed steps.
_pick_item(){
  # PREFER the 27B's sweet spot (python) so a slot LANDS an item; then FALL BACK to the harder
  # items (frontend/wiring/T4/T5/godot) so the 27B keeps ATTEMPTING them (it lands some, and the
  # verify layer + escalation route the rest).
  #
  # 2026-09-14 RE-ENABLED godot (was hard-excluded here, "measured 0%, guaranteed timeout"): that
  # measurement predated the decompose SOURCE-ONLY carve-out below AND ovn_autotest.sh's fast
  # per-file gdparse/--check-only gate (both already existed in this file, just never re-tested
  # against the picker). Root-caused the actual 0%: the decompose rule said "if the task asks to
  # WRITE A TEST, emit []" and the model over-applied that to ANY item whose VERIFY line runs a GUT
  # test file — which is nearly EVERY xlite queue item's wording (source description + GUT-test
  # VERIFY) — so decompose silently emitted [] on almost the whole godot backlog. Fixed the rule
  # text (see below) and re-verified: 3/3 manual decompose replays classify correctly, 2/2 full
  # end-to-end runs landed real verified code (2280/2280 GUT tests) in 2.5-4 minutes each — nowhere
  # near a timeout. Re-enabling; the existing verify+repair+escalate safety net means a wrong pick
  # here costs a cycle, same as any other T3+ item, not a queue/repo risk. Monitor
  # state/stage_runs/xlite-*.jsonl real land rate over the next day before trusting this at scale.
  #
  # 2026-09-15 FIX: confirmed live — a godot item whose TARGET is itself a GUT test file
  # (tests/test_codex_manager.gd — "Add test case verifying...") gets auto-picked, hits the
  # SOURCE-ONLY decompose carve-out's "asks to WRITE A TEST -> emit []" rule (correctly — the
  # carve-out exists because the 27B genuinely can't author GUT tests), decompose_failed's exit 1
  # has NO parking/backoff, so the fleet re-picks the EXACT SAME item next cycle forever. Confirmed
  # via logs/ovn_stage_runner.log: the identical item decompose_failed 3x in 9 seconds. Since
  # decompose will deterministically reject any godot item whose PRIMARY target is a test file,
  # exclude those from auto-pick entirely rather than let them loop — this is prevention, not a
  # general decompose_failed retry-limit (a separate, still-open gap for the non-godot case).
  # \[CLAUDE\] exclusion (2026-09-28): without this, an item this script itself just
  # escalated to [CLAUDE] (see the capstone-cap fix above) — or one ovn_recover_parked.sh
  # escalated — gets re-picked right back up here (it's still an unchecked `- [ ] ` line),
  # defeating the whole point of escalating it. Matches the exclusion every other
  # "find the real doable item" selector in this codebase already carries (run_overnight.sh,
  # ovn_item_guard.sh, ovn_recover_parked.sh — see their own 2026-09-17 fix comments).
  # 2026-10-02 (bugs-first): the bug-first order + lane focus is applied BEFORE the T3+ filter, so while a manual bug is open this picker only ever sees
  # bug items (a T2 bug => nothing here => "no doable T3+ item found" => the cycle falls through to the scout flow, which works the bug); and when the
  # picked set is bug items the python-preference below is skipped - a Kotlin/GDScript bug must not queue behind a python roadmap item.
  _doable="$(grep -E '^- \[ \] ' "$rd/OVERNIGHT_PROGRESS.md" | grep -vE 'AUTO-SKIP|HUMAN-ONLY|BLOCKED|\[CLAUDE\]' | ovn_bug_first_order | grep -E '\[T[345]\]|·T[345]·' \
              | grep -vE '\btests?/[A-Za-z0-9_./-]*\.gd\b|\btest_[A-Za-z0-9_]*\.gd\b')"
  _doable="$(printf '%s\n' "$_doable" | _so_item_filter | grep -E '^- \[ \] ')"   # D3: drop items whose feature-group prerequisites are not done (enforce); shadow journals only
  if printf '%s\n' "$_doable" | ovn_has_bug_line; then
    item="$(printf '%s\n' "$_doable" | head -1 | sed -E 's/^- \[ \] //')"
  else
    item="$(printf '%s\n' "$_doable" | grep -iE '\.py\b' | grep -viE 'wire|integrate|\.vue\b|\.tsx?\b' | head -1 | sed -E 's/^- \[ \] //')"
    [ -z "$item" ] && item="$(printf '%s\n' "$_doable" | head -1 | sed -E 's/^- \[ \] //')"
  fi
}
if [ -n "$item_arg" ]; then item="$item_arg"; else _pick_item; fi
[ -z "$item" ] && { say "no doable T3+ item found"; exit 0; }
tier="$(printf '%s' "$item" | grep -oE '\[T[1-5]\]|·T[1-5]·' | head -1 | grep -oE '[1-5]' | head -1)"; tier="${tier:-3}"
say "ITEM (T$tier): ${item:0:100}"
# 2026-10-03 (A8, qa/h11-bug-pipeline): Kotlin/legacy bug grounding is ON only for a manual-test bug while OVN_BUG_FIRST != off (ovn_is_manual_bug_text is
# false under OVN_BUG_FIRST=off, so the kill switch restores the old behaviour) and only when qa/bug_ground.py is deployed (fail-safe: absent => old behaviour).
_bg_py="$HOME/overnight-queue/qa/bug_ground.py"
_bg_on=0; [ -f "$_bg_py" ] && ovn_is_manual_bug_text "$item" && _bg_on=1
_bg_plan_f=""; _bg_dropf=""

# ---- FAST PATH: templated "run the full suite once to confirm no regressions" capstone item ----
# 2026-09-26 FIX: every feature batch's LAST item is auto-generated in this exact shape — a pure
# re-verification with NO file to add/modify (cat:test; multifile:no; no source path in the
# description). decompose()'s schema requires every step to name a "files" target, so this can
# NEVER produce a valid step and decompose_failed's exit 1 has no parking/backoff (see the
# 2026-09-15 note above for the sibling godot-test-target case) — confirmed live on xlite: the
# SAME item ("index_from_label caused zero regressions") looped decompose_failed 22+ times over
# 7 hours (state/stage_runs/xlite-*.jsonl), NEVER reaching ovn_item_guard.sh's no-op-streak
# AUTO-SKIP because ovn_stage_sweep.sh invokes this script per-REPO, not per-item, so no $ID ever
# reaches the guard for whatever item the internal auto-pick above actually lands on. At least 4
# other features hit the exact same shape historically (level_for_xp, bonus_needed_for_
# guaranteed, hit_percent_needed, the Upkeep dedupe) and only escaped via ad hoc manual
# intervention each time. Since the item's true job — confirm the full suite is still green — is
# EXACTLY what every sibling step in the same batch already re-verifies via full_verify() before
# it's allowed to land, this never needed decompose() or an aider edit at all: extract the
# item's own VERIFY command and just run it directly. A pass means the regression-check claim is
# true (nothing to add/modify — clean-count as done); a genuine failure is real, valuable signal
# that must NOT be papered over by looping forever, so it's logged distinctly and left OPEN for a
# human/Claude to investigate instead of being silently retried.
if printf '%s' "$item" | grep -qiE 'run the (full |whole )?.*(suite|tests) (once )?to confirm .*(caused )?(zero|no) regressions'; then
  vcmd="$(printf '%s' "$item" | grep -oE 'VERIFY: `[^`]+`' | sed -E 's/^VERIFY: `//; s/`$//')"
  # bare `godot` is never resolvable on this box (see ovn_credit_already_satisfied.sh's
  # _resolve_tool_paths — same fix, applied here too): VERIFY clauses are authored with the
  # bare command name but the real pipeline always uses $HOME/godot/godot4.
  vcmd="$(printf '%s' "$vcmd" | sed -E "s#(^|&& |; )godot #\1${HOME}/godot/godot4 #g")"
  if [ -n "$vcmd" ]; then
    say "regression-check capstone item — running its own VERIFY directly (no decompose needed): $vcmd"
    git -C "$rd" fetch -q origin overnight/feature 2>/dev/null
    git -C "$rd" reset -q --hard origin/overnight/feature 2>/dev/null
    # Godot needs its asset/class_name cache imported before a headless GUT run will see the
    # project correctly (same warm-then-run pattern used everywhere else this repo runs GUT —
    # see run_overnight.sh/branch_hygiene.sh/ovn_stage_runner.sh's own full_verify() below).
    if [ -f "$rd/project.godot" ] && [ -x "$HOME/godot/godot4" ]; then
      ( cd "$rd" && timeout 120 "$HOME/godot/godot4" --headless --path . --import ) >/dev/null 2>&1
    fi
    if ( cd "$rd" && eval "$vcmd" ) >/tmp/stage-capstone-verify.log 2>&1; then
      say "regression-check PASSED — marking item done, no code change needed"
      lineno="$(grep -nF -- "- [ ] ${item}" "$rd/OVERNIGHT_PROGRESS.md" | head -1 | cut -d: -f1)"
      if [ -n "$lineno" ]; then
        sed -i "${lineno}s#^- \[ \] #- [x] (auto-verified via direct VERIFY run — regression-check item, no code edit needed) #" "$rd/OVERNIGHT_PROGRESS.md"
        if ! git -C "$rd" diff --quiet OVERNIGHT_PROGRESS.md 2>/dev/null; then
          git -C "$rd" add OVERNIGHT_PROGRESS.md
          git -C "$rd" commit -q -m "chore(queue): auto-verify regression-check capstone item (direct VERIFY run, no decompose)"
          git -C "$rd" push -q origin overnight/feature 2>/dev/null || { git -C "$rd" pull -q --rebase origin overnight/feature && git -C "$rd" push -q origin overnight/feature; }
        fi
      fi
      jlog "{\"run\":\"$RUNID\",\"repo\":\"$repo\",\"tier\":$tier,\"event\":\"capstone_verified\"}"
      exit 0
    else
      say "regression-check FAILED — a real regression, NOT auto-retrying (see /tmp/stage-capstone-verify.log): $(tail -3 /tmp/stage-capstone-verify.log | tr '\n' ' ')"
      jlog "{\"run\":\"$RUNID\",\"repo\":\"$repo\",\"tier\":$tier,\"event\":\"capstone_regression_detected\"}"
      # Escalation cap (2026-09-28): see capstone_escalate_on_failure()'s header comment above
      # for the full root-cause writeup — this fast-path never advanced past a capstone item
      # whose VERIFY keeps genuinely failing, permanently starving the T3-5 lane behind it.
      _esc_evt="$(capstone_escalate_on_failure "$rd" "$item" "$repo" "$tier" "$RUNID")" && {
        say "capstone item hit the ${OVN_STAGE_CAPSTONE_CAP:-2}-detection cap — escalated to [CLAUDE] so the picker moves past it"
        jlog "$_esc_evt"
      }
      exit 1
    fi
  fi
fi

# ---- LAZY BUG BRIEF (2026-10-03, A8): a manual bug enqueued BEFORE the brief stage was deployed (all 7 Chickadee bugs of 10-01) carries no brief, so the
# 27B planned it blind (3,2,4,2,1,2 steps for the same bug; every run died on invented symbols / duplicated types). On the FIRST attempt of such a bug, run
# the brief now (qa/manual_notes_ingest.py brief --id), then re-pick: the single line has become the brief's single-file steps. Bounded + fail-safe:
#   - only an auto-picked, still-OPEN bug (manual_notes status open) that has no state/bug_briefs/<feat>.json and was never lazily tried (marker state/bug_lazy/<feat>, kept out of bug_briefs/ so escalation never mistakes it for a brief), on its
#     first attempt (no bugcount); never a brief step itself ('(brief:i/K)');
#   - only when no other LLM consumer is running (a brief is minutes of GPU; an aider/prework/planner/brief process = skip, the old path runs);
#   - OVN_BUG_BRIEF=off / OVN_BUG_LAZY_BRIEF=off / a missing ingest or `timeout`/`pgrep` => skip. Any failure leaves the single item exactly as it was.
if [ "$_bg_on" = 1 ] && [ -z "$item_arg" ] && [ "${OVN_BUG_BRIEF:-on}" != off ] && [ "${OVN_BUG_LAZY_BRIEF:-on}" != off ] && [ -f qa/manual_notes_ingest.py ]; then
  _bg_feat="$(printf '%s' "$item" | grep -oE '\[feat:[^]]+\]' | head -1 | sed -E 's/^\[feat://; s/\]$//')"
  _bg_safe="$(printf '%s' "$_bg_feat" | tr -c 'A-Za-z0-9._-' '_')"
  if [ -n "$_bg_feat" ] && ! printf '%s' "$item" | grep -qE '\(brief:[0-9]+/[0-9]+\)' \
     && [ ! -f "state/bug_briefs/${_bg_safe}.json" ] && [ ! -f "state/bug_lazy/${_bg_safe}" ] \
     && [ ! -f "state/item_fails/stage-${repo}.$(ovn_item_hash "$item").bugcount" ]; then
    _bg_id="$(python3 "$_bg_py" brief-id --ovn "$PWD" --feat "$_bg_feat" 2>/dev/null)"
    if [ -z "$_bg_id" ]; then
      say "lazy bug brief: skipped (no open manual_notes entry for $_bg_feat, or it was already briefed)"
    elif ! command -v pgrep >/dev/null 2>&1 || ! command -v timeout >/dev/null 2>&1; then
      say "lazy bug brief: skipped (pgrep/timeout unavailable - cannot check GPU contention)"
    elif pgrep -f "${OVN_BUG_LAZY_BRIEF_BUSY_RE:-aider-venv/bin/aider|aider --yes-always|ovn_prework\.sh|ovn_planner\.sh|bug_brief\.py|manual_notes_ingest\.py (add|brief)}" >/dev/null 2>&1; then
      say "lazy bug brief: skipped (another LLM consumer is active - GPU contention)"
    else
      mkdir -p state/bug_lazy; : > "state/bug_lazy/${_bg_safe}"
      say "lazy bug brief: briefing $_bg_feat (entry $_bg_id) before the first attempt"
      OVN_DIR="$PWD" timeout "${OVN_BUG_LAZY_BRIEF_TIMEOUT:-900}" python3 qa/manual_notes_ingest.py brief --id "$_bg_id" --force >> logs/bug_brief.log 2>&1
      _bg_rc=$?
      [ "$_bg_rc" = 124 ] && rm -f "state/bug_lazy/${_bg_safe}"      # timed out: allow ONE retry on the next first-attempt pick (marker lives outside the bug_briefs glob)
      jlog "$(jq -nc --arg r "$RUNID" --arg f "$_bg_feat" --argjson rc "$_bg_rc" '{run:$r,event:"lazy_bug_brief",feat:$f,rc:$rc}')"
      git -C "$rd" fetch -q origin overnight/feature 2>/dev/null
      if [ -f "state/bug_briefs/${_bg_safe}.json" ] && grep -q '"status": "ok"' "state/bug_briefs/${_bg_safe}.json" 2>/dev/null; then
        git -C "$rd" reset -q --hard origin/overnight/feature 2>/dev/null; _pick_item
        [ -z "$item" ] && { say "lazy bug brief applied but nothing doable is left to pick"; exit 0; }
        say "lazy bug brief applied (rc=$_bg_rc); re-picked: ${item:0:100}"
        tier="$(printf '%s' "$item" | grep -oE '\[T[1-5]\]|·T[1-5]·' | head -1 | grep -oE '[1-5]' | head -1)"; tier="${tier:-3}"
        _bg_on=0; ovn_is_manual_bug_text "$item" && _bg_on=1
      else
        say "lazy bug brief: no usable brief (rc=$_bg_rc) - continuing with the single item (see logs/bug_brief.log)"
      fi
    fi
  fi
fi

# ---- worktree (all steps build on each other) ----
git -C "$rd" fetch -q origin overnight/feature 2>/dev/null
wt="$(mktemp -d "/tmp/stage-${repo}.XXXX" 2>/dev/null)" || wt=""   # 2026-10-16: empty on failure -> the worktree add below fails ("worktree failed"); cleanup() is guarded on a non-empty wt
git -C "$rd" worktree add -q "$wt" origin/overnight/feature 2>/dev/null || { say "worktree failed"; exit 1; }
cleanup(){ [ "$_wd" != 0 ] && kill "$_wd" 2>/dev/null; [ "${_dedicated:-0}" = 1 ] && rm -f state/PAUSED state/stage_pause_since; [ -n "${wt:-}" ] && git -C "$rd" worktree remove --force "$wt" >/dev/null 2>&1; rm -f "${TMPDIR:-/tmp}"/ovn_stage_"$$".* 2>/dev/null; return 0; }   # 2026-10-17: per-run scratch files (prompt/attempt/drop) die with the run even when it is killed mid-step
trap cleanup EXIT
_ST_H0="$(git -C "$wt" rev-parse -q --verify HEAD 2>/dev/null)"   # 2026-10-18 (D4): the stage run's base sha, for the outcome row's head_before/commits
# 2026-09-09 FIX: a fresh `git worktree add` never includes gitignored content, so node_modules
# is always absent here - every PER-STEP frontend gate (ovn_autotest.sh, called after every single
# aider attempt) hit "Cannot find package 'vitest'" and reported it as api-mismatch/no-edit/timeout
# instead of the real cause, permanently dooming any Vue/TS step regardless of code quality
# (confirmed live: test-automation-agent's DashboardCard.vue T4 item failed EVERY attempt this way).
# full_verify() already reused the main clone's node_modules via a symlink for its OWN final check
# (search "vitest FULL" below) but that happened only ONCE at the very end - too late to help any
# individual step. Do the same symlink here, for EVERY package.json in the repo, right after the
# worktree exists, so every step's gate has it from the start.
while IFS= read -r pj; do
  [ -z "$pj" ] && continue
  wd="$(dirname "$pj")"; [ -d "$wd/node_modules" ] || continue
  wwd="$wt/${wd#"$rd"/}"
  [ -d "$wwd" ] && [ ! -e "$wwd/node_modules" ] && ln -s "$(cd "$wd" && pwd)/node_modules" "$wwd/node_modules" 2>/dev/null
done < <(find "$rd" -maxdepth 3 -name package.json -not -path '*/node_modules/*' 2>/dev/null)
# 2026-10-09 (xlite godot lane): same class of bug as node_modules above, for Godot. A fresh `git worktree add` has no .godot/ or *.import (both
# gitignored), so the per-step gate (ovn_autotest.sh -> `godot --check-only --script res://<file>`) reported 'Identifier "ScreenBg" not declared' and
# 'Preload file ... has no resource loaders' on files the model never touched (7 false parse errors without the cache, 0 after `--import`). The model burned
# ~300s per attempt chasing non-errors and all three tech_tree/tech_manager T3 runs ended 'escalated to Claude'. Copy the live clone's import cache in
# (wt_seed_godot), then run the incremental headless --import once so the class cache exists before step 1. Kill switch OVN_STAGE_GODOT_SEED=off; a missing
# godot binary logs and continues (the gate then degrades exactly as before). lib_worktree.sh is sourced in a subshell only, so its function definitions never reach the runner.
if [ "${OVN_STAGE_GODOT_SEED:-on}" != off ]; then
  while IFS= read -r _gpg; do
    [ -z "$_gpg" ] && continue
    _gpd="$(dirname "$_gpg")"; _gsub="${_gpd#"$wt"}"; _gsub="${_gsub#/}"; [ -n "$_gsub" ] || _gsub="."
    _gbin="$HOME/godot/godot4"
    if [ ! -x "$_gbin" ]; then say "godot seed: $_gbin not found - skipping import cache for $_gsub (per-step godot gate may report false errors)"; continue; fi
    ( source scripts/lib_worktree.sh; wt_seed_godot "$rd" "$wt" "$_gsub" )
    ( cd "$_gpd" && timeout 120 "$_gbin" --headless --path . --import ) >> "logs/ovn_stage_godot_import.log" 2>&1
    say "godot seed: seeded + imported $_gsub in the stage worktree (rc=$?)"
  done < <(find "$wt" -maxdepth 3 -name project.godot -not -path '*/node_modules/*' -not -path '*/addons/*' 2>/dev/null)
fi
# end godot import seed
# 2026-09-16: added .kt (Android is now gradle-verified in full_verify() below; the model should
# see Kotlin files exist when a doable item targets one). .swift deliberately NOT added — those
# items are AUTO-SKIPped at the source (see ovn_swift_retag.py) since nothing here can verify them.
if declare -F stage_layout_listing >/dev/null 2>&1; then layout="$(stage_layout_listing "$wt")"
else layout="$(cd "$wt" && find . -maxdepth 4 \( -name '*.py' -o -name '*.ts' -o -name '*.tsx' -o -name '*.vue' -o -name '*.gd' -o -name '*.kt' \) -not -path '*/node_modules/*' -not -path '*/.venv/*' -not -path '*/.godot/*' 2>/dev/null | sed 's#^\./##' | sort | head -100)"; fi

# (2026-10-03: moved above the decompose step so a bug whose plan was all 'no change required' can be counted too.)
# stage_bug_attempt "<why>" - a staged run on a manual-test bug ($item) did NOT complete it. Never AUTO-SKIP a bug: count ONE attempt (state/item_fails/
# stage-<repo>.<hash>.bugcount - the runner has no lane id; the sweep path runs no guard at all, so it must count itself) and at OVN_BUG_ATTEMPT_CAP
# (default 2) escalate via ovn_bug_escalate ([CLAUDE] [bug-escalated: ...] + state/bug_escalations.jsonl + ONE relay note). Below the cap the line stays
# OPEN so the next cycle retries. Journals a bug_attempt event: run_overnight.sh turns it into the 'bug-handled' status marker so the guard does not
# double-count the cycle or bill it to another item. Caller already held the queue and reset $rd to origin/overnight/feature.
stage_bug_attempt() {
  local why="$1" h cap bc cf ln
  h="$(ovn_item_hash "$item")"
  cap="${OVN_BUG_ATTEMPT_CAP:-2}"; case "$cap" in ''|*[!0-9]*|0) cap=2;; esac
  mkdir -p state/item_fails 2>/dev/null
  cf="state/item_fails/stage-${repo}.${h}.bugcount"
  bc=$(( $(cat "$cf" 2>/dev/null || echo 0) + 1 )); printf '%s' "$bc" > "$cf"
  jlog "$(jq -nc --arg r "$RUNID" --argjson b "$bc" --argjson c "$cap" '{run:$r,event:"bug_attempt",attempts:$b,cap:$c}')"
  if [ "$bc" -ge "$cap" ]; then
    ln="$(grep -nF -- "- [ ] ${item:0:55}" "$rd/OVERNIGHT_PROGRESS.md" | head -1 | cut -d: -f1)"
    if [ -n "$ln" ] && command -v ovn_bug_escalate >/dev/null 2>&1; then
      # 2026-10-03 (A8/BUG-9): the first compile/test error of this run + the run id travel with the escalation (jsonl row + relay body), so the Claude
      # session that takes the bug can open the log; the old last_failure only said 'staged landed 0 of 2'.
      local _verr _vl="${SLOG%.jsonl}.verify.log"
      _verr="$(grep -m1 -E '^e: |Redeclaration|Unresolved reference|FAILED |QUALITY FAIL|SEMANTIC FAIL|error:|Error:' "$_vl" 2>/dev/null | sed -E 's#file://[^ ]*/##; s#://[^/ ]*@#://***@#g' | cut -c1-200)"
      [ -n "$_verr" ] || _verr="$(jq -r 'select(.verdict=="fail") | .excerpt // empty' "$SLOG" 2>/dev/null | tail -1 | cut -c1-200)"
      OVN_ESC_VERIFY_ERR="$_verr" OVN_ESC_RUN_ID="$RUNID" OVN_ESC_GIT_IDENTITY=fleet ovn_bug_escalate "$rd" "$rd/OVERNIGHT_PROGRESS.md" "$ln" "- [ ] $item" "$h" "stage-$repo" "$bc" "stage-runner: $why" "state" "${bc} failed attempts (cap ${cap})" "overnight/feature" | while IFS= read -r _l; do say "$_l"; done
      rm -f "$cf"
      [ -n "${_bg_plan_f:-}" ] && rm -f "$_bg_plan_f"      # the persisted first plan (A8) dies with the escalation
    fi
  else
    say "manual bug NOT parked: staged attempt ${bc}/${cap} ($why) - line stays open for the next cycle"
  fi
}

# ---- DECOMPOSE the item into ordered sub-steps (JSON) ----
decompose(){ # $1=task text  -> writes JSON array of {desc,files[],verify} to stdout
  local pf; pf="$(mktemp "${TMPDIR:-/tmp}/ovn_stage_$$.XXXXXX")"
  # GODOT carve-out: the 27B can write valid Godot-4 SOURCE with the gdparse/engine loop, but it CANNOT
  # author GUT test scripts (the test-framework .gd format defeats it every time — proven empirically).
  # So for godot items, decompose into SOURCE-ONLY steps and verify by compile-check, NOT by making it
  # write a GUT test. The runner's full_verify still runs the EXISTING GUT suite to catch regressions.
  #
  # 2026-09-14 FIX: the rule text below used to just say "if the task asks to WRITE A TEST, emit []" —
  # empirically (manual curl replay of this exact prompt, 3-for-3 real xlite queue items) the model
  # over-applied that to ANY item whose VERIFY line runs a GUT test file, even when the task's own
  # DESCRIPTION was a plain source addition ("Add static function X...") and the VERIFY was just
  # pointing at a test that already exists or is a separate queue item. Since nearly every xlite queue
  # item is worded exactly that way (source description + GUT-test VERIFY), this was silently emitting
  # [] on almost the entire godot backlog — decompose_failed, not a model capability limit. Clarified
  # the rule to key off the task DESCRIPTION, not the VERIFY clause; re-verified 3/3 items decompose
  # correctly (2 source items produce a real step, 1 genuine test-writing item still emits []).
  local _rules
  case "$1" in
    *.gd*|*[Gg][Dd][Ss]cript*|*[Gg]odot*)
      _rules='GODOT 4 MODE — SOURCE ONLY. 1 to '"$MAX_STEPS"' small steps. Do NOT create or modify any GUT/test
.gd file (no tests/, no test_*.gd) — authoring GUT tests is OUT OF SCOPE and will fail. Each step ADDS or
MODIFIES only the named production .gd script(s). Each step "files" lists ONLY that source .gd. Each step
"verify" MUST be exactly "gdparse <that .gd path>" (valid Godot-4 syntax) — nothing else. Write REAL Godot
4.x code (typed, @export/@onready, await, callable .connect) — never Godot 3, never a stub/TODO. The
task'"'"'s OWN VERIFY line frequently points at a GUT test file that ALREADY EXISTS or is handled by a
SEPARATE queue item — that does NOT make this a test-writing task. Only emit an empty array [] if the
task'"'"'s DESCRIPTION itself (before the VERIFY: clause) explicitly instructs you to add/create/write a NEW
.gd test file — a description that adds a production function/method/class is a source task regardless of
what its VERIFY clause happens to run. Keep each step to 1 file.' ;;
    *)
      _rules='2 to '"$MAX_STEPS"' steps, each SMALL. CRITICAL — every step must be SELF-VERIFYING: the code change
AND a test that exercises it belong in the SAME step (its "files" should usually include both the source
file and its test file). NEVER split "add X" and "test X" into two steps — a code-only step FALSE-PASSES
because nothing tests it yet. Each "verify" must be a command that genuinely FAILS if the step did not do
its job (a specific new test, not "existing tests still pass"), and that test MUST import and call the
EXACT symbol this step creates — matching the name precisely, not a similarly-named class. Prefer new
pure functions + their colocated test. Assert PROPERTIES (type/bounds/monotonic/idempotent/raises/
round-trip), NOT guessed exact values. Each step must leave the suite GREEN: the test asserts the step'"'"'s
INTENDED (post-change) behavior, NEVER the current or absent behavior — e.g. for an endpoint you are ADDING,
the test asserts it now returns the SUCCESS response, never that it still 404s. NEVER a "write a failing
test" / TDD-first step: a step that ends with a red test does not land and kills the item. QUALITY BAR: each step must produce a REAL, working
implementation — NEVER a stub, placeholder, "for demonstration", keyword-matching fake, TODO, or
NotImplementedError; if you cannot implement it for real, make the step smaller. If the task does not fit
the codebase as written (a concept that does not exist), adapt it to what is really there. Keep each step
to 1-2 files.' ;;
  esac
  # 2026-10-10 (BX-05): the decomposer invented prerequisite helpers in an UNRELATED module with no caller (xlite scripts/battle/damage.gd carried coerce_to_array and
  # simulate_single_load, both unreferenced). OVN_STAGE_HELPER_HINT=off drops this paragraph (prompt byte-identical to before).
  if [ "${OVN_STAGE_HELPER_HINT:-on}" != off ]; then
    _rules="$_rules"$'\nHELPERS: put any new helper function in the SAME file that calls it (the file the TASK names), in the same step as its first caller. NEVER add a helper to a different or unrelated module (for example a battle, damage or util file) that nothing calls: a function with no caller is dead code and is rejected.'
  fi
  # D3 (2026-10-18): OVN_STAGE_ORDER=enforce lets the plan declare ordering. Off/shadow leave the prompt byte-identical to before.
  if [ "${_SO_MODE:-off}" = enforce ]; then
    _rules="$_rules"$'\nORDERING: a step MAY add "depends_on":[0-based indexes of EARLIER steps] when it needs symbols or files those steps create. List a step that fixes or adds code BEFORE any step whose test exercises it (a test of new behavior is red until the code exists).'
  fi
  # 2026-10-07: a previous staged run at THIS item that landed nothing recorded why (state/item_fails/stage-<repo>.<hash>.priorfail, written by the
  # zero-landing retry budget below); a blind re-decomposition just repeats the same failing plan.
  local _prior="" _pf; _pf="state/item_fails/stage-${repo}.$(ovn_item_hash "$item").priorfail"
  [ -s "$_pf" ] && _prior="
PREVIOUS ATTEMPT(S) AT THIS TASK LANDED NOTHING. Last failure: $(head -c 1800 "$_pf")
Do NOT repeat the same plan: choose a different, SMALLER decomposition. If the failure shows an EXISTING test that asserts the opposite of what this task wants, make updating that test an explicit step in the same step as the source change. If the SAME test id or check failed before, change WHICH files and tests the steps touch instead of re-planning the same edit."
  cat > "$pf" <<PROMPT
Break this coding task into an ORDERED list of the SMALLEST safe sub-steps, each independently
committable and testable by an autonomous 27B model driving aider. Output ONLY a JSON array, no prose.

REPO: $repo
Real source paths (use EXACTLY, do not invent):
$layout

TASK:
$1
$_prior

Each element: {"desc":"<one precise change>","files":["real/path.ext"],"verify":"<exact test/command that proves this step>"}
Rules: $_rules Output ONLY the JSON array.
PROMPT
  local raw; raw="$(llm "$pf")"; rm -f "$pf"
  # extract the JSON array from the raw content (model may wrap it in prose/fences)
  printf '%s' "$raw" | python3 -c "import sys,json
txt=sys.stdin.buffer.read().decode('utf-8','replace'); i=txt.find('['); j=txt.rfind(']')
try:
    a=json.loads(txt[i:j+1]) if i>=0 and j>i else []
    a=[s for s in a if isinstance(s,dict) and s.get('desc')]
    print(json.dumps(a[:$MAX_STEPS]))
except Exception: print('[]')" | _bg_filter
}
# 2026-10-03 (A8): on a manual bug, drop decomposed steps whose desc says 'no change required' / 'nothing to change' (the categories bug stored such a step
# and the run "passed" it). The number dropped goes to $_bg_dropf so the caller can tell 'the model had nothing' from 'the LLM was down'.
_bg_filter(){ if [ "$_bg_on" = 1 ]; then python3 "$_bg_py" filter-steps ${_bg_dropf:+--drop-file "$_bg_dropf"} 2>/dev/null; else cat; fi; }

# 2026-10-03 (A8): the plan used to be re-made by the model on EVERY attempt (3, 2, 4, 2, 1, 2 steps for the same bug), so attempt 2 never built on attempt 1.
# A manual bug now persists its FIRST plan (state/bug_plans/<md5 of the item text>.json) and reuses it on the next attempt; removed on escalation / full pass.
# >>> n4-stage-waste helpers: verify-only preflight (Part 5)
# 2026-10-13 (N4 stage-runner-waste, Part 5, SHADOW ONLY) VERIFY-ONLY PREFLIGHT. shrike-monitor bf654f65 '[T3] ... Verify existing test suite passes without modification' (VERIFY `pytest backend/tests/test_monitors_api.py -v`
# = 34 passed on overnight/feature, nothing to edit) burned 9 no-edit attempts / 330k tokens: the 27B has nothing to change and the item is already satisfied on the pristine tree. The runner already runs the item's
# own VERIFY on the pristine tree (stage_item_verify_run, OVN_STAGE_ITEM_VERIFY shadow); when that verdict is PASS for an item whose description only asks to verify/ensure/confirm something, the verdict is LOGGED here
# (event verify_only_pristine_pass + state/stage_verifyonly_shadow.log) so the lead can see how many items a deterministic credit would settle. NOTHING changes: no enforcement, no credit, no skipped steps.
# OVN_STAGE_VERIFYONLY_PREFLIGHT=off|shadow (default shadow; any other value = shadow: there is deliberately no enforcing mode in this package).
stage_item_is_verify_only(){   # $1=item text -> rc 0 when the description (before VERIFY:) only asks to verify / confirm / ensure / check and names no change to make
  local d
  d="$(printf '%s' "$1" | sed -E 's/VERIFY:.*$//')"
  grep -qiE '(^|[]—-] *|\. )(verify|confirm|ensure|check|validate)\b' <<< "$d" || return 1
  # a change verb anywhere in the description (the reviewer found 'Modify the ... path to call X' and 'Ensure _f returns Y instead of falling back' misread as verify-only: these are edit requests)
  grep -qiE '\b(add|adds|adding|create|implement|write|fix|wire|refactor|replace|remove|change|update|rename|migrate|delete|extend|introduce|modify|modifies|set|sets|use|uses|call|calls|handle|handles|swap|swaps|move|moves|route|routes|return|returns|raise|raises|emit|emits|make|makes|reject|rejects|accept|accepts|contain|contains|include|includes|define|defines|expose|exposes|has an?|attach|attached|attaches|apply|applied|applies|place|placed|places|wrap|wrapped|wraps|inject|injected|register|registered)\b' <<< "$d" && return 1
  grep -qiE '\b(instead of|rather than)\b' <<< "$d" && return 1
  return 0
}
# the shadow log is append-only by design; keep it bounded (default 256 KiB -> newest 500 lines survive)
stage_shadow_log_cap(){   # $1=file  [$2=max bytes]
  local f="$1" max="${2:-${OVN_STAGE_SHADOW_LOG_MAX:-262144}}" sz
  case "$max" in ''|*[!0-9]*) max=262144;; esac
  [ -f "$f" ] || return 0
  sz="$(wc -c < "$f" 2>/dev/null | tr -d ' ')"; case "$sz" in ''|*[!0-9]*) return 0;; esac
  [ "$sz" -gt "$max" ] || return 0
  tail -n 500 "$f" > "$f.tmp.$$" 2>/dev/null && mv -f "$f.tmp.$$" "$f" 2>/dev/null || rm -f "$f.tmp.$$" 2>/dev/null
  return 0
}
# <<< n4-stage-waste helpers: verify-only preflight (Part 5)

# >>> d2 helpers: pre-edit credit (precredit)
# 2026-10-18 (D2-prestate-credit): a staged item whose OWN VERIFY already passes on the PRISTINE tree burned 2+ runs (~275k tokens) as no-ops (shrike-monitor 051e535 duplicate, shrike-notify
# severity_map): verification-only items, and items whose test a sibling item already landed. This runs BEFORE the planner/model (decompose is the first LLM call), using the same honest pristine probe
# as OVN_STAGE_ITEM_VERIFY (stage_item_verify_run: repo venv on PATH, own shadow log). scripts/ovn_precredit.py decides (PASS + non-vacuous VERIFY + verify-only/specific-test-node; duplicate when a sibling
# owns the same test node). OVN_STAGE_PRECREDIT=off|shadow|enforce, default shadow: shadow journals the would-credit decision (event precredit_decision + state/stage_precredit_shadow.log) and the model runs
# exactly as before; enforce credits the progress line `- [x] (already-satisfied: ...)` / `(duplicate: ...)`, pushes it and exits without calling the model. Auto-picked items only (an explicit item arg and
# manual bugs are never credited here). To promote: set OVN_STAGE_PRECREDIT=enforce where the runner is launched after reading the shadow log.
stage_precredit_run(){   # uses globals: wt rd repo item item_arg tier RUNID _bg_on ; sets _PRE_EARLY (pristine verdict, reused by the item-VERIFY block); rc 0 = item settled (caller exits 0), rc 1 = go on
  local mode _pk_vo=0 _pk_decu _pk_json _pk_dec _pk_why _pk_key _pk_sib _pk_snap _pk_note _pk_log _pk_py="$HOME/overnight-queue/scripts/ovn_precredit.py"
  mode="$(_sg_mode "${OVN_STAGE_PRECREDIT:-}" shadow 2>/dev/null || echo shadow)"
  [ "$mode" = off ] && return 1
  [ -f "$_pk_py" ] || return 1
  declare -F stage_item_verify_run >/dev/null 2>&1 || return 1
  # shadow must be behaviour-neutral: probe ONLY where the pre-existing item-VERIFY probe would have run (OVN_STAGE_ITEM_VERIFY != off and the item is not mis-targeted); otherwise leave
  # _PRE_EARLY empty so the later block behaves exactly as before. (The pre-existing probe also ran for manual-bug items, so those are not newly costed.)
  [ "${OVN_STAGE_ITEM_VERIFY:-shadow}" = off ] && return 1
  if OVN_STAGE_SHADOW_LOG=/dev/null stage_item_mistarget "$wt" "$item" >/dev/null 2>&1; then return 1; fi
  _pk_snap="$(git -C "$wt" status --porcelain -uall 2>/dev/null)"
  _PRE_EARLY="$(OVN_STAGE_REPO="$repo" OVN_STAGE_REPO_DIR="$rd" stage_item_verify_run "$wt" "$item")"
  declare -F stage_tree_restore >/dev/null 2>&1 && stage_tree_restore "$wt" "$_pk_snap"
  stage_item_is_verify_only "$item" && _pk_vo=1
  _pk_json="$(timeout 20 python3 -I "$_pk_py" decide --item "$item" --pre "$_PRE_EARLY" --progress "$wt/OVERNIGHT_PROGRESS.md" --wt "$wt" --verify-only "$_pk_vo" 2>/dev/null)"
  _pk_dec="$(printf '%s' "$_pk_json" | jq -r '.decision // "none"' 2>/dev/null)"; [ -n "$_pk_dec" ] || _pk_dec=none
  _pk_why="$(printf '%s' "$_pk_json" | jq -r '.reason // ""' 2>/dev/null)"
  _pk_key="$(printf '%s' "$_pk_json" | jq -r '.key // ""' 2>/dev/null)"
  _pk_sib="$(printf '%s' "$_pk_json" | jq -r '.sibling // ""' 2>/dev/null)"
  [ "$_pk_dec" = none ] && { say "pre-edit credit: no (${_pk_why:-no decision}) [mode=$mode]"; return 1; }
  _pk_decu="$(printf '%s' "$_pk_dec" | tr '[:lower:]' '[:upper:]')"   # upper-case via tr: bash 3.2 (the Mac) lacks the caret expansion
  say "pre-edit credit: WOULD $_pk_decu before any model call [mode=$mode]: ${_pk_why:0:200}${_pk_sib:+ | sibling: ${_pk_sib:0:120}}"
  jlog "$(jq -nc --arg r "$RUNID" --arg m "$mode" --arg d "$_pk_dec" --arg w "$_pk_why" --arg k "$_pk_key" --arg s "$_pk_sib" --arg pre "${_PRE_EARLY%%|*}" '{run:$r,event:"precredit_decision",mode:$m,would:$d,pre:$pre,why:$w,key:$k,sibling:$s}')"
  _pk_log="${OVN_STAGE_PRECREDIT_LOG:-state/stage_precredit_shadow.log}"
  stage_shadow_log_cap "$_pk_log"
  echo "$(date '+%F %T') [$repo] precredit mode=$mode would=$_pk_dec run=$RUNID item=${item:0:160} why=${_pk_why:0:160}" >> "$_pk_log" 2>/dev/null
  [ "$mode" = enforce ] || return 1
  if [ -n "$item_arg" ]; then say "pre-edit credit: not applied (explicit item argument: only queue-picked items are credited)"; return 1; fi
  if [ "${_bg_on:-0}" = 1 ]; then say "pre-edit credit: not applied (manual bug item: a bug is never credited without a fix)"; return 1; fi
  _pk_note="$([ "$_pk_dec" = duplicate ] && echo "duplicate: sibling owns the VERIFY test ${_pk_key:0:80}" || echo "already-satisfied: pre-edit VERIFY green, non-vacuous")"
  ./queue.sh hold "$repo" >/dev/null 2>&1
  git -C "$rd" fetch -q origin overnight/feature 2>/dev/null
  git -C "$rd" reset -q --hard origin/overnight/feature 2>/dev/null
  if [ "$(python3 -I "$_pk_py" mark --progress "$rd/OVERNIGHT_PROGRESS.md" --item "$item" --decision "$_pk_dec" --note "$_pk_note" 2>/dev/null | jq -r '.marked' 2>/dev/null)" = true ] \
     && ! git -C "$rd" diff --quiet OVERNIGHT_PROGRESS.md 2>/dev/null; then
    git -C "$rd" add OVERNIGHT_PROGRESS.md
    git -C "$rd" -c user.email=22970726+markhint22@users.noreply.github.com -c user.name=shrike-fleet commit -q -m "chore(queue): pre-edit credit T$tier item ($_pk_dec: its own VERIFY already passes before any edit)"
    if git -C "$rd" push -q origin overnight/feature 2>/dev/null || { git -C "$rd" pull -q --rebase origin overnight/feature 2>/dev/null && git -C "$rd" push -q origin overnight/feature 2>/dev/null; }; then
      ./queue.sh release "$repo" >/dev/null 2>&1
      jlog "$(jq -nc --arg r "$RUNID" --arg d "$_pk_dec" '{run:$r,event:"precredit_applied",decision:$d,model_calls:0}')"
      say "pre-edit credit APPLIED ($_pk_dec): item checked off and pushed, the model was never called"
      return 0
    fi
    git -C "$rd" reset -q --hard origin/overnight/feature 2>/dev/null
    say "pre-edit credit: push failed (fleet racing) - item left OPEN, the normal run continues"
  else
    git -C "$rd" checkout -q -- OVERNIGHT_PROGRESS.md 2>/dev/null
    say "pre-edit credit: could not locate the open item line - nothing written, the normal run continues"
  fi
  ./queue.sh release "$repo" >/dev/null 2>&1
  return 1
}
# <<< d2 helpers: pre-edit credit (precredit)
_PRE_EARLY=""
if stage_precredit_run; then
  jlog "$(jq -nc --arg r "$RUNID" --argjson t "${tier:-0}" '{run:$r,event:"summary",tier:$t,passed:0,total:0,verified:true,commits_pushed:0,precredit:true}')"
  say "DONE: pre-edit credit (0 model calls) for T$tier item. log: $SLOG"
  exit 0
fi
STEPS_JSON=""; _bg_reused=0
if [ "$_bg_on" = 1 ]; then
  _bg_dropf="$(mktemp "${TMPDIR:-/tmp}/ovn_stage_$$.XXXXXX")"; : > "$_bg_dropf"
  _bg_plan_f="state/bug_plans/$(printf '%s' "$item" | md5sum | cut -d' ' -f1).json"
  STEPS_JSON="$(python3 "$_bg_py" plan-load --file "$_bg_plan_f" 2>/dev/null | python3 "$_bg_py" filter-steps 2>/dev/null)"
  if [ -n "$STEPS_JSON" ] && [ "$(printf '%s' "$STEPS_JSON" | jq 'length' 2>/dev/null || echo 0)" -ge 1 ] 2>/dev/null; then
    _bg_reused=1; say "reusing the plan persisted by the first attempt ($(printf '%s' "$STEPS_JSON" | jq 'length') step(s))"
  else STEPS_JSON=""; fi
fi
[ -n "$STEPS_JSON" ] || STEPS_JSON="$(decompose "$item")"
# D3: order the plan by dependency (shadow: unchanged + journaled; enforce: merge red-by-design test steps into their fix step, else reorder)
if [ "$_SO_MODE" != off ] && [ -n "$STEPS_JSON" ]; then
  _so_res="$(printf '%s' "$STEPS_JSON" | python3 "$_SO_PY" plan --mode "$_SO_MODE" --repo "$repo" --run "$RUNID" --item "$item" --log "$_SO_LOG" 2>/dev/null)"
  if [ -n "$_so_res" ] && printf '%s' "$_so_res" | jq -e '.steps | type=="array"' >/dev/null 2>&1; then
    _so_nd="$(printf '%s' "$_so_res" | jq '.decisions | length')"
    if [ "${_so_nd:-0}" -gt 0 ]; then
      say "step-order ($_SO_MODE): $_so_nd decision(s): $(printf '%s' "$_so_res" | jq -r '[.decisions[] | (.event + ":" + ((.step // "")|tostring) + "->" + ((.needs // "")|tostring) + ":" + (.action // ""))] | join(", ")')"
      jlog "$(printf '%s' "$_so_res" | jq -c --arg r "$RUNID" --arg m "$_SO_MODE" '{run:$r,event:"step_order",mode:$m,changed:.changed,decisions:.decisions}')"
    fi
    # shadow: keep the model's plan byte-for-byte (the annotated copy only adds deps); enforce: use the transformed plan
    [ "$_SO_MODE" = enforce ] && STEPS_JSON="$(printf '%s' "$_so_res" | jq -c '.steps')"
    [ "$_SO_MODE" = shadow ] && _SO_ANN="$(printf '%s' "$_so_res" | jq -c '.steps')"
  fi
fi
NSTEPS="$(printf '%s' "$STEPS_JSON" | jq 'length' 2>/dev/null || echo 0)"
if [ "${NSTEPS:-0}" -lt 1 ]; then
  say "decompose produced no steps — abort"; jlog "{\"run\":\"$RUNID\",\"repo\":\"$repo\",\"tier\":$tier,\"event\":\"decompose_failed\"}"
  # a bug whose every planned step was vacuous ('no change required') is the MODEL having nothing, not an outage: count it as an attempt (escalates at the cap)
  if [ "$_bg_on" = 1 ] && [ "$(cat "$_bg_dropf" 2>/dev/null || echo 0)" -gt 0 ] 2>/dev/null; then
    ./queue.sh hold "$repo" >/dev/null 2>&1
    ( cd "$rd" && git fetch -q origin overnight/feature && git reset -q --hard origin/overnight/feature ) 2>/dev/null
    stage_bug_attempt "plan had only 'no change required' steps"
    ./queue.sh release "$repo" >/dev/null 2>&1
  fi
  [ -n "$_bg_dropf" ] && rm -f "$_bg_dropf"
  exit 1
fi
[ -n "$_bg_dropf" ] && { rm -f "$_bg_dropf"; _bg_dropf=""; }
[ "$_bg_on" = 1 ] && [ "$_bg_reused" = 0 ] && python3 "$_bg_py" plan-save --file "$_bg_plan_f" --plan-json "$STEPS_JSON" 2>/dev/null
say "decomposed into $NSTEPS sub-steps"
jlog "$(jq -nc --arg r "$RUNID" --arg repo "$repo" --argjson t "$tier" --arg it "$item" --argjson n "$NSTEPS" --argjson plan "$STEPS_JSON" '{run:$r,repo:$repo,tier:$t,item:$it,event:"decomposed",steps:$n,plan:$plan}')"

# 2026-09-16 DYNAMIC REARM: now that we know how many steps we're actually committing to, size the
# watchdog to what THIS item can legitimately need instead of one fixed number for every item.
# per-step: MAX_ATT attempts at STEP_TIMEOUT, plus (if REDECOMP=1) one more round of that same
# budget for whatever sub-steps a failing step's re-decompose produces — not per-sub-step (unknown
# count until it happens), just one extra round's worth as a realistic contingency, matching what's
# actually been observed (a redecompose typically yields ~2 sub-steps, each retried like any step).
# verify: full_verify() runs once, then up to OVN_VERIFY_REPAIR_ROUNDS times more (each a fresh
# aider repair call at STEP_TIMEOUT plus a full re-verify) — budgeted at 1500s/verify (2026-09-16:
# raised from 1150s to 1500s when the docker-build check was added on top of the earlier
# gradle/Android addition — a repo like iptv_apps/billwatch can legitimately exercise
# pytest+vitest+gradle+docker all in the SAME verify pass, ~600+240+240+400s (docker's 400s only
# actually applies when a touched Dockerfile changed, but the item that touched it is exactly the
# case this budget needs to cover). Capped at OVN_STAGE_HARD_TIMEOUT (an absolute ceiling, not a
# fixed runtime) so a pathological MAX_STEPS=6 item still can't hold the lock forever — see the
# ceiling's own comment for why 12600s.
_repair_rounds="${OVN_VERIFY_REPAIR_ROUNDS:-2}"
_per_step_budget=$(( MAX_ATT * STEP_TIMEOUT * (1 + REDECOMP) ))
_steps_budget=$(( NSTEPS * _per_step_budget ))
# 2026-10-04 (QA h13 review): +420s per verify = the new-tests helper's own bounds (OVN_NEW_TESTS_TIMEOUT 300s pytest + 120s GUT); it only runs after the rest of full_verify was green.
_verify_budget=$(( (_repair_rounds + 1) * (1500 + 420) + _repair_rounds * STEP_TIMEOUT ))
_dynamic_budget=$(( _steps_budget + _verify_budget + 300 ))
_ceiling="${OVN_STAGE_HARD_TIMEOUT:-12600}"
_armed=$(( _dynamic_budget < _ceiling ? _dynamic_budget : _ceiling ))
_arm_watchdog "$_armed"
say "watchdog rearmed for ${_armed}s (NSTEPS=$NSTEPS, dynamic budget was ${_dynamic_budget}s, ceiling ${_ceiling}s)"

# >>> n4-stage-waste helpers: empty-file (Part 1)
# 2026-10-13 (N4 stage-runner-waste, Part 1) EMPTY-FILE: a step whose aider run left a 0-byte NEW (or truncated declared) file used to pass the per-step gate - an empty test file collects 0
# tests and ovn_autotest passes it, and `git diff --shortstat` ignores untracked files (hence 'nostat') - and then died on the final full_verify '-- QUALITY FAIL: <file> is a 0-byte file'
# 15-25 minutes later (8 staged runs in 48h, 481k step tokens: billwatch test_auth_register_audit.py x2, gitlark test_memory_rekey.py x2, iptv junk paths app/jobs/test_*.py x3, TAA x1).
# That final check fails EVERY run with a 0-byte changed file, so converting it into a step failure here only moves a guaranteed final failure to where the existing retry can re-prompt it.
#   declared empty file (in the step FILES, or named by the item) -> fa=empty-file, rc=1, the retry prompt is told to write the full content
#   undeclared empty NEW file (junk path) -> removed ('reaped empty undeclared file') and the step carries on; if that leaves the tree unchanged the step is a no-edit
# `__init__.py` / `.gitkeep` / `.keep` / `py.typed` / `.gdignore` (marker files that are empty by design) are left alone (never reaped, never a failure here): behaviour for them is exactly what it was. OVN_STAGE_EMPTY_FILE=off disables.
# 2026-10-18: does the item text state an intent to delete exactly file $2? (VERIFY `test ! -f|-e <path>`, or "Delete|Remove the file|module [entirely|<path>]", or "Delete <path>").
declare -F stage_item_wants_delete >/dev/null 2>&1 || stage_item_wants_delete(){ return 1; }   # real definition: scripts/lib_stage_guards.sh (2026-10-20)
STAGE_EF_DECLARED=""; STAGE_EF_NOEDIT=0
stage_empty_files_scan(){   # $1=worktree $2=step files (space-sep) $3=item text. rc 0 = act on it (STAGE_EF_DECLARED non-empty -> empty-file; STAGE_EF_NOEDIT=1 -> tree emptied by the reap -> no-edit)
  local w="$1" files="$2" itm="$3" p cand decl="" t hit
  STAGE_EF_DECLARED=""; STAGE_EF_NOEDIT=0
  cand="$( { git -C "$w" ls-files --others --exclude-standard 2>/dev/null; git -C "$w" diff --cached --name-only --diff-filter=A 2>/dev/null; git -C "$w" diff --name-only --diff-filter=M 2>/dev/null; } | sort -u )"
  decl="$(printf '%s' "$itm" | sed -E 's/VERIFY:.*$//' | grep -oE '[A-Za-z0-9_./-]+\.[A-Za-z0-9]{1,8}' | sort -u)"
  while IFS= read -r p; do
    [ -n "$p" ] && [ -f "$w/$p" ] && [ ! -L "$w/$p" ] && [ ! -s "$w/$p" ] || continue
    case "${p##*/}" in __init__.py|.gitkeep|.keep|py.typed|.gdignore) continue;; esac   # empty by design (package / directory markers): never reaped, never an empty-file failure
    hit=0
    for t in $files; do [ "$t" = "$p" ] && hit=1; done
    if [ "$hit" = 0 ]; then
      while IFS= read -r t; do
        [ -n "$t" ] || continue
        if [ "$t" = "$p" ]; then hit=1; break; fi
        case "$t" in */*) case "$p" in */"$t") hit=1; break;; esac;; esac   # a path token with a directory part may be repo-relative to a sub-package; a bare basename must match exactly
      done <<< "$decl"
    fi
    if [ "$hit" = 1 ]; then
      # 2026-10-18 (shrike-monitor audit): aider's whole-file editor can only "delete" a file by writing EMPTY content (3 shrike-monitor T5 runs, 3 x empty-file/no-edit, ~140k tokens, item
      # "Delete backend/tests/test_paginate.py ... VERIFY: test ! -f ..."). When the item states a delete intent for exactly this tracked file, an emptied file IS the deletion: git rm it and carry on.
      # No delete intent -> still an empty-file failure. OVN_STAGE_EMPTY_AS_DELETE=off restores the old behaviour.
      if [ "${OVN_STAGE_EMPTY_AS_DELETE:-on}" != off ] && git -C "$w" cat-file -e "HEAD:$p" 2>/dev/null && stage_item_wants_delete "$itm" "$p"; then
        git -C "$w" rm -qf -- "$p" >/dev/null 2>&1 || { rm -f "$w/$p"; git -C "$w" add -A -- "$p" >/dev/null 2>&1; }
        say "  empty declared file is an intended deletion: $p"
        jlog "$(jq -nc --arg r "$RUNID" --arg f "$p" '{run:$r,event:"empty_as_delete",file:$f}')"
        continue
      fi
      STAGE_EF_DECLARED="$STAGE_EF_DECLARED $p"; continue
    fi
    # undeclared: only a NEW file (not in HEAD) is ever reaped - never touch a tracked file the step truncated
    if ! git -C "$w" cat-file -e "HEAD:$p" 2>/dev/null; then
      git -C "$w" rm -qf --cached -- "$p" >/dev/null 2>&1; rm -f "$w/$p"
      say "  reaped empty undeclared file: $p"
      jlog "$(jq -nc --arg r "$RUNID" --arg f "$p" '{run:$r,event:"empty_file_reaped",file:$f}')"
    fi
  done <<< "$cand"
  STAGE_EF_DECLARED="${STAGE_EF_DECLARED# }"
  [ -n "$STAGE_EF_DECLARED" ] && return 0
  if [ -z "$(git -C "$w" status --porcelain -uall 2>/dev/null)" ]; then STAGE_EF_NOEDIT=1; return 0; fi
  return 1
}
# <<< n4-stage-waste helpers: empty-file (Part 1)

# >>> n4-stage-waste helpers: retry signature (Part 2)
# 2026-10-13 (N4 stage-runner-waste, Part 2) SAME-SIGNATURE STOP + STRUCTURED PRIORFAIL.
# 48-72h: 47 distinct staged items, attempt 1 verified 24/47, the 2nd attempt 2/23, the 3rd 3/20; the failed retries of never-landing items were 34% of all stage tokens, and the failure was often
# IDENTICAL run to run (iptv test_content_history_returns_429_after_120_requests_per_minute x3, TAA the same 4 failing ids x2, shrike-notify x2, iptv ModuleNotFoundError app.core.rate_limit x2,
# billwatch 0-byte+SEMANTIC x3). A retry that fails exactly like the last one is pure waste: the signature below is persisted per item and a repeat goes straight to the escalate branch.
# stage_fail_facts <sig|block> <verify.log> <stage jsonl> prints (all scrubbed of credentials):
#   sig   : a 16-hex hash of the failure's identity, or NOTHING when there is no recognisable evidence (an empty signature never stops a retry).
#           evidence = the sorted failing test ids + the `-- QUALITY/SEMANTIC/MIGRATION/DEP-IMPORT FAIL` lines + ModuleNotFoundError texts + kotlin `e:` lines of the verify log; when the verify
#           log has none (the run never reached / never failed the final verify), the BLOCKED steps' fail_reason+files list and the undeclared-file set of their scope violations.
#   block : the human/LLM-readable version of the same evidence: up to 6 failing test ids with their first assertion line, the QUALITY/SEMANTIC lines, undeclared files, blocked-step reasons.
stage_fail_facts(){
  local _to=(); type -P timeout >/dev/null 2>&1 && _to=(timeout 20)
  ${_to[@]+"${_to[@]}"} python3 - "$1" "${2:-}" "${3:-}" <<'PY'
import sys, re, json, hashlib
mode, vlog, slog = sys.argv[1], sys.argv[2], sys.argv[3]
def rd(p):
    try:
        return open(p, encoding="utf-8", errors="replace").read()
    except OSError:
        return ""
SCRUB = [
    (re.compile(r"://[^/\s@]*@"), "://***@"),
    (re.compile(r"(?i)\bBearer\s+[A-Za-z0-9._~+/=-]{8,}"), "Bearer ***"),
    (re.compile(r"(?i)((?:password|passwd|secret|token|api[_-]?key|authorization)\w{0,6}\s*[=:]\s*[\"']?)[A-Za-z0-9+/=_.~-]{6,}"), r"\1***"),
    (re.compile(r"\b(?:sk|pk|ghp|gho|ghs|xox[abp])[-_][A-Za-z0-9_-]{16,}"), "***"),
]
def scrub(t):
    for rx, rep in SCRUB:
        t = rx.sub(rep, t)
    return t
lines = rd(vlog).splitlines()
ids = {}
for ln in lines:
    m = re.match(r"^ERROR collecting (\S+)", ln)
    if m:
        ids.setdefault(m.group(1), "collection error"); continue
    m = re.match(r"^(?:FAILED|ERROR) (\S+)(?: - (.*))?$", ln)
    if m:
        ids.setdefault(m.group(1), (m.group(2) or "").strip()); continue
    m = re.match(r"^(\S+ > \S.*?) FAILED$", ln)          # gradle
    if m:
        ids.setdefault(m.group(1), ""); continue
    m = re.match(r"^\s*(?:FAIL|×)\s+(\S.*?)\s*$", ln)  # vitest
    if m:
        ids.setdefault(m.group(1), "")
quality = sorted({re.sub(r"\s+", " ", ln).strip(" -")[:220] for ln in lines
                  if re.match(r"^-- (QUALITY FAIL|SEMANTIC FAIL|MIGRATION SAFETY FAIL|DEP-IMPORT FAIL|GUT RED|python tests exist but no venv)", ln)})
mods = sorted({m for ln in lines for m in re.findall(r"ModuleNotFoundError: No module named '[^']+'", ln)})
kts = sorted({re.sub(r"file://\S*/", "", ln)[:200] for ln in lines if ln.startswith("e: ")})
rows = []
for ln in rd(slog).splitlines():
    try:
        r = json.loads(ln)
        if isinstance(r, dict):
            rows.append(r)
    except ValueError:
        pass
blocked = {str(r.get("step")) for r in rows if r.get("verdict") == "blocked"}
sfail = sorted({"%s|%s" % (r.get("fail_reason") or "", r.get("files") or "") for r in rows
                if r.get("verdict") == "fail" and (str(r.get("step")) in blocked or r.get("fail_reason") == "mistargeted")})
undecl = set()
for r in rows:
    if r.get("verdict") == "fail" and r.get("fail_reason") == "scope-violation":
        m = re.search(r"touched undeclared file\(s\):(.*?) \(declared:", r.get("excerpt") or "")
        if m:
            undecl.update(m.group(1).split())
undecl = sorted(undecl)
vev = ["T:" + i for i in sorted(ids)] + ["Q:" + q for q in quality] + ["M:" + m for m in mods] + ["K:" + k for k in kts]
sev = ["S:" + x for x in sfail] + (["U:" + " ".join(undecl)] if undecl else [])
if mode == "sig":
    ev = vev or sev
    if ev:
        print(hashlib.sha1("\n".join(ev).encode("utf-8", "replace")).hexdigest()[:16])
    sys.exit(0)
def first_e(tid):
    name = re.escape(tid.split("::")[-1])
    for i, ln in enumerate(lines):
        if re.match(r"^_{2,} .*" + name + r".* _{2,}$", ln):
            for nx in lines[i + 1:i + 80]:
                if re.match(r"^_{2,} .* _{2,}$", nx):
                    break
                if nx.startswith("E "):
                    return nx[1:].strip()
    return ""
out = []
if ids:
    items = list(ids.items())
    out.append("failing tests (%d, showing up to 6):" % len(items))
    for tid, msg in items[:6]:
        a = msg or first_e(tid)
        out.append("- %s%s" % (tid, (": " + a) if a else ""))
for q in quality[:4]:
    out.append("check: " + q)
for m in mods[:2]:
    out.append("import error: " + m)
for k in kts[:3]:
    out.append("compile: " + k)
if not vev:
    for x in sfail[:4]:
        rs, _, fl = x.partition("|")
        out.append("blocked step: %s%s" % (rs or "failed", (" on " + fl) if fl else ""))
if undecl:
    out.append("a step touched files it did not declare (multifile:no): " + " ".join(undecl[:6]))
txt = "\n".join(l[:240] for l in out)
print(scrub(txt)[:1400])
PY
}
stage_fail_signature(){ stage_fail_facts sig "${1:-}" "${2:-}"; }      # $1=verify.log $2=stage jsonl -> 16-hex or nothing
stage_priorfail_block(){ stage_fail_facts block "${1:-}" "${2:-}"; }   # $1=verify.log $2=stage jsonl -> structured text or nothing
# <<< n4-stage-waste helpers: retry signature (Part 2)

# >>> n4-stage-waste helpers: scope-learn (Part 3)
# 2026-10-13 (N4 stage-runner-waste, Part 3) SCOPE-LEARN. The multifile:no scope guard in run_step rejects a step whose (already green) diff touches a file outside its declared set. 15 such rejections
# over 6 items in 48h, the SAME undeclared set recurring 8 times: an iptv RecordingsView.vue item whose text says 'ensuring type compatibility with the new store signature' needs
# iptv-web/src/stores/recordings.ts + __tests__/recordings.test.ts every time; RevenueCatManagerTest.kt needs RevenueCatManager.kt (4x). The guard can never be satisfied, so the item deadlocks.
# OVN_STAGE_SCOPE_LEARN=off|shadow|on (default SHADOW, flip to on only after the shadow log has been read):
#   the undeclared set U of every rejection is remembered per item (state/item_fails/stage-<repo>.<hash>.scopeseen). When the SAME U recurs (a 2nd attempt, in this run or a later one):
#     U eligible (<=3 files, every one an existing TRACKED file, none denylisted / hard-banned / under addons|vendor|node_modules, no native iOS/Android/tvOS) -> ON: U is added to the item's declared
#       scope for the NEXT attempt ('scope extended', state/item_fails/...scopeext); SHADOW: logs what it would extend.
#     U ineligible (junk/new file, banned, vendored, native, >3 files) -> ON: the step is abandoned at once (no more attempts, no re-decomposition: it can never be satisfied); SHADOW: logs it.
#   A first sighting never changes anything (the model may simply not touch the file next time). The guard only runs AFTER the step's own gate was green, so an extension never accepts a red tree.
STAGE_SL_DECISION=""; STAGE_SCOPE_EXTENDED=0
stage_path_denied(){   # $1=worktree $2=repo-relative path -> rc 0 + reason on stdout when the path must never be learned/fed (denylist, hard-banned list, vendored dirs, native mobile code)
  local w="$1" f="$2" b bf
  case "$f" in
    addons/*|*/addons/*|vendor/*|*/vendor/*|node_modules/*|*/node_modules/*|.godot/*|*/.godot/*|.venv/*|*/.venv/*|*/__pycache__/*|build/*|*/build/*|dist/*|*/dist/*|.github/*|.git/*) echo "vendored/generated path"; return 0;;
    .env|.env.*|*/.env|*/.env.*|*.pem|*.key|*.p12|*.jks|*.keystore|*secret*|*credential*) echo "secret-like path"; return 0;;
    OVERNIGHT_PROGRESS.md|OVERNIGHT_DONE.md|AGENTS.md|CLAUDE.md|*/AGENTS.md|*.lock|package-lock.json|*/package-lock.json|*.min.js) echo "queue/lock/generated file"; return 0;;
    iptv-ios/*|iptv-android/*|iptv-tvos/*|ios/*|android/*|*.swift|*.pbxproj|*.xcodeproj/*) echo "native mobile code"; return 0;;
  esac
  for bf in "$w/.queue-hard-banned-files" "${rd:-/nonexistent}/.queue-hard-banned-files"; do
    [ -f "$bf" ] || continue
    while IFS= read -r b; do
      b="${b%%#*}"; b="${b// /}"; [ -n "$b" ] || continue
      if [ "$f" = "$b" ]; then echo "hard-banned file"; return 0; fi
      case "$f" in "$b"*) echo "hard-banned file"; return 0;; esac
    done < "$bf"
  done
  return 1
}
stage_scope_ext_list(){   # $1=item hash -> the files the item's scope was extended by (ON mode only), one per line
  [ "${OVN_STAGE_SCOPE_LEARN:-shadow}" = on ] || return 0
  cat "state/item_fails/stage-${repo}.${1}.scopeext" 2>/dev/null
  return 0
}
stage_scope_learn(){   # $1=worktree $2=undeclared files (space-sep) $3=step idx -> sets STAGE_SL_DECISION = first|extend|escalate|shadow-extend|shadow-escalate|off
  local w="$1" extra="$2" idx="$3" mode="${OVN_STAGE_SCOPE_LEARN:-shadow}" h key f n=0 why="" seenf extf
  STAGE_SL_DECISION=off
  case "$mode" in off|OFF|0) return 0;; on|ON|1) mode=on;; *) mode=shadow;; esac
  extra="$(printf '%s\n' $extra | grep -v '^$' | sort -u | tr '\n' ' ')"; extra="${extra% }"
  [ -n "$extra" ] || return 0
  h="$(ovn_item_hash "$item" 2>/dev/null)"; key="${extra// /|}"
  mkdir -p state/item_fails 2>/dev/null
  seenf="state/item_fails/stage-${repo}.${h}.scopeseen"; extf="state/item_fails/stage-${repo}.${h}.scopeext"
  if ! grep -qxF -- "$key" "$seenf" 2>/dev/null; then
    printf '%s\n' "$key" >> "$seenf"
    STAGE_SL_DECISION=first
    jlog "$(jq -nc --arg r "$RUNID" --argjson i "$idx" --arg m "$mode" --arg f "$extra" '{run:$r,step:$i,event:"scope_learn",mode:$m,decision:"first",files:$f}')"
    return 0
  fi
  for f in $extra; do
    n=$((n+1))
    git -C "$w" cat-file -e "HEAD:$f" 2>/dev/null || { why="$f is not an existing tracked file"; break; }
    why="$(stage_path_denied "$w" "$f")" && { why="$f: $why"; break; }
    why=""
  done
  [ -z "$why" ] && [ "$n" -gt 3 ] && why="${n} files (limit 3)"
  if [ -z "$why" ]; then
    if [ "$mode" = on ]; then
      for f in $extra; do grep -qxF -- "$f" "$extf" 2>/dev/null || printf '%s\n' "$f" >> "$extf"; done
      STAGE_SL_DECISION=extend; STAGE_SCOPE_EXTENDED=1
      say "  step $idx scope extended: the same undeclared set recurred (${extra}) - declared for the next attempt"
    else
      STAGE_SL_DECISION=shadow-extend
      say "  step $idx scope-learn (shadow): would extend the declared scope by ${extra}"
    fi
  else
    if [ "$mode" = on ]; then
      STAGE_SL_DECISION=escalate
      say "  step $idx scope-learn: the same undeclared set recurred and cannot be learned (${why}) - escalating now, no more attempts"
    else
      STAGE_SL_DECISION=shadow-escalate
      say "  step $idx scope-learn (shadow): would escalate immediately (${why})"
    fi
  fi
  jlog "$(jq -nc --arg r "$RUNID" --argjson i "$idx" --arg m "$mode" --arg d "$STAGE_SL_DECISION" --arg f "$extra" --arg w "$why" '{run:$r,step:$i,event:"scope_learn",mode:$m,decision:$d,files:$f,why:$w}')"
  return 0
}
# <<< n4-stage-waste helpers: scope-learn (Part 3)

# >>> n4-stage-waste helpers: file-feed (Part 4)
# 2026-10-13 (N4 stage-runner-waste, Part 4) FILE-FEED for the staged path. 26 of 130 step attempts in 48h ended with NO edit because the architect answered 'Please add the following files to the chat'
# (iptv_apps-20261013-082239-1305878-s0.log needs routers/subscription.py + conftest.py while the step FILES lists only tests/test_subscription.py). aider's single-shot --message mode never loops back
# for them. The non-staged path already has 'Iterative file-feeding' (run_overnight.sh scan_for_new_files: path-token regex, existence check, max files); the staged path had none.
# On a no-edit attempt whose architect reply asks for files, the repo paths it names are validated (tracked, text, not denylisted / hard-banned / vendored / native / .md, <= OVN_STAGE_FILE_FEED_MAX_BYTES
# (default 60000) each, not already loaded) and at most 3 per step are added to the RETRY: `--read` for a multifile:no item (read-only context cannot trip the scope guard), `--file` otherwise.
# OVN_STAGE_FILE_FEED=off disables. Needs stage_path_denied (scope-learn block); without it nothing is fed (fail closed).
stage_feed_files(){   # $1=aider log of the attempt $2=worktree $3=files already loaded (space-sep, may include --file/--read words) $4=max -> up to $4 repo-relative paths, one per line
  local log="$1" w="$2" loaded="$3" max="${4:-3}" tok r n=0 cap="${OVN_STAGE_FILE_FEED_MAX_BYTES:-60000}" lst
  declare -F stage_path_denied >/dev/null 2>&1 || return 0
  case "$cap" in ''|*[!0-9]*) cap=60000;; esac
  lst="$(git -C "$w" ls-files 2>/dev/null)"
  while IFS= read -r tok; do
    [ -n "$tok" ] || continue
    [ "$n" -lt "$max" ] || break
    case "$tok" in *.md|*.MD) continue;; esac
    r=""
    # here-string, NOT a pipe: under `set -o pipefail` printf | grep -q returns 141 (SIGPIPE) when the listing exceeds the 64 KB pipe buffer (iptv_apps ~70 KB, xlite ~75 KB) and grep exits at the first match
    if grep -qxF -- "$tok" <<< "$lst"; then r="$tok"
    else
      case "$tok" in
        */*) r="$(printf '%s\n' "$lst" | awk -v t="/$tok" 'length($0)>length(t) && substr($0,length($0)-length(t)+1)==t')";;
        *)   r="$(printf '%s\n' "$lst" | awk -F/ -v b="$tok" '$NF==b')";;
      esac
      [ "$(printf '%s\n' "$r" | grep -c .)" = 1 ] || r=""
    fi
    [ -n "$r" ] && [ -f "$w/$r" ] && [ ! -L "$w/$r" ] || continue
    case " $loaded " in *" $r "*) continue;; esac
    stage_path_denied "$w" "$r" >/dev/null && continue
    [ "$(wc -c < "$w/$r" 2>/dev/null | tr -d ' ')" -le "$cap" ] 2>/dev/null || continue
    grep -Iq . "$w/$r" 2>/dev/null || continue
    printf '%s\n' "$r"; n=$((n+1))
  done < <(python3 - "$log" <<'PY'
import sys, re
try:
    lines = open(sys.argv[1], encoding="utf-8", errors="replace").read().splitlines()
except OSError:
    lines = []
out = []
for i, ln in enumerate(lines):
    if re.search(r"(?i)add the following files?\b", ln):
        for nx in lines[i + 1:i + 25]:
            if nx.startswith("Tokens:"):
                break
            for tok in re.findall(r"[A-Za-z0-9_./-]+\.[A-Za-z0-9]{1,8}", nx):
                tok = tok.lstrip("./") if tok.startswith("./") else tok
                if tok not in out:
                    out.append(tok)
print("\n".join(out))
PY
)
  return 0
}
# <<< n4-stage-waste helpers: file-feed (Part 4)


# ---- run ONE sub-step: returns 0 pass / 1 fail. logs the attempt. ----
run_step(){ # $1=idx $2=desc $3=files(space-sep) $4=verify $5=redecomp-left
  local idx="$1" desc="$2" files="$3" verify="$4" rd_left="$5" att fa rc
  local fargs=(); for f in $files; do [ -n "$f" ] && fargs+=(--file "$f"); done
  # 2026-10-13 (xlite F3, BLOCKER-class): a Verify/Check/Confirm step that names a file which does not exist is MIS-TARGETED. aider happily creates and fills any path it is handed, and a Verify
  # step is allowed to write: the run fabricated a 52-line scripts/mission/codex_manager.gd (the real module is scripts/codex/codex_manager.gd) whose existence turned the item's grep VERIFY
  # green. Refuse the step before any model call; it is BLOCKED (no re-decomposition: the target is wrong, not too big). OVN_STAGE_MISTARGET=off disables.
  local _mt
  if _mt="$(stage_step_mistarget "$wt" "$desc" "$files")"; then
    say "  step $idx REFUSED (mis-targeted): ${_mt:0:160}"
    jlog "$(jq -nc --arg r "$RUNID" --argjson i "$idx" --arg d "$desc" --arg f "$files" --arg ex "mis-targeted: $_mt" \
      '{run:$r,step:$i,desc:$d,files:$f,attempt:0,verdict:"fail",fail_reason:"mistargeted",duration_s:0,tokens_sent:0,tokens_recv:0,excerpt:$ex}')"
    jlog "$(jq -nc --arg r "$RUNID" --argjson i "$idx" '{run:$r,step:$i,verdict:"blocked"}')"
    return 1
  fi
  # AUTO-ADD SOURCE FILES: the #1 no-edit cause on wire/integrate steps was the 27B only getting the
  # TARGET file and then looping "I need to see flanking.gd" (the source it wires FROM). Find the file
  # that DEFINES each symbol the step references and open it too, so the model has the API up front.
  local _sym _df
  for _sym in $(printf '%s %s' "$desc" "$item" | grep -oE '`[A-Za-z_][A-Za-z0-9_]*`|\b[A-Z][A-Za-z0-9_]{3,}\b' | tr -d '`' | sort -u | head -8); do
    _df="$(grep -rlE "\b(class|class_name|func|def|interface|type|export (class|function|const)) +${_sym}\b" "$wt" --include='*.gd' --include='*.py' --include='*.ts' --include='*.tsx' --include='*.vue' 2>/dev/null | head -1)"
    [ -n "$_df" ] && { _df="${_df#"$wt"/}"; case " $files ${fargs[*]} " in *" $_df "*) : ;; *) fargs+=(--file "$_df");; esac; }
  done
  # INJECT THE TARGET FUNCTION BODY for wire/integrate steps: the dominant no-edit is the 27B failing to
  # locate/modify a specific function in a big file (e.g. battle.gd._cover_quality). Extract that exact
  # function and hand it to the model with a "insert the call HERE" instruction, so it edits the right code.
  local _tgtctx=""
  if printf '%s %s' "$desc" "$item" | grep -qiE '\b(wire|integrate|register|hook|call|invoke)\b'; then
    local _tfn _tfile _ln
    _tfn="$(printf '%s %s' "$desc" "$item" | grep -oE '\.[_a-z][A-Za-z0-9_]+' | grep -oE '_?[a-z][A-Za-z0-9_]+' | grep -vE '^(gd|py|ts|tsx|vue)$' | tail -1)"
    # target file: the "into <file>" path in the ITEM (a step's files often omit the big target file)
    _tfile="$(printf '%s' "$item" | grep -oE '[A-Za-z0-9_./-]+\.(gd|py|ts|tsx|vue)' | grep -viE 'test|spec' | head -1)"
    [ -z "$_tfile" ] && _tfile="$(printf '%s' "$files" | tr ' ' '\n' | grep -E '\.(gd|py|ts|tsx|vue)$' | grep -viE 'test|spec' | head -1)"
    if [ -n "$_tfn" ] && [ -n "$_tfile" ] && [ -f "$wt/$_tfile" ]; then
      _ln="$(grep -nE "(func|def|function|static func) +${_tfn}\b" "$wt/$_tfile" 2>/dev/null | head -1 | cut -d: -f1)"
      [ -n "$_ln" ] && _tgtctx="$(sed -n "${_ln},$((_ln+34))p" "$wt/$_tfile" 2>/dev/null)"
      [ -n "$_tgtctx" ] && _tgtctx="

The EXACT function you must modify is ${_tfn} in ${_tfile} (shown below). Insert the call to the wired symbol at the RIGHT place inside it — do NOT rewrite it wholesale, do NOT recreate the file:
--- ${_tfile}: ${_tfn} ---
${_tgtctx}
--- end ---"
    fi
  fi
  # 2026-10-03 (A8): real Kotlin definitions + the module's test dependencies for a Kotlin TEST step of a manual bug, and (after a rejected duplicate-type step)
  # the real definition of the type the model tried to re-declare. Empty (=> the old prompt) unless _bg_on.
  local _bgctx="" _bgre="" _bgdup=""
  if [ "$_bg_on" = 1 ]; then
    _bgctx="$(python3 "$_bg_py" kotlin-ctx --wt "$wt" --files "$files" --text "$desc $item" --desc "$desc" 2>/dev/null)"
    [ -n "$_bgctx" ] && _bgctx=$'\n\n'"$_bgctx"
  fi
  local slog="state/stage_runs/${repo}-${RUNID}-s${idx}.log"   # per-step aider session log for review
  # adaptive context: start rich (repo-map + architect + AGENTS.md), SHRINK if we blow the 27B window
  local mt=3072; local rdargs=(--read AGENTS.md); local archargs=(--architect --auto-accept-architect)
  # GODOT: hand the model the Godot-4 rules file (kills the Godot-3 syntax the 27B defaults to). The
  # per-step ovn_autotest gdparse/godot --check-only loop then makes it fix any residual mistakes.
  local _gd4="$HOME/overnight-queue/assets/GODOT4.md"; local _is_godot=0
  case "$item$files$desc" in *.gd*|*[Gg][Dd][Ss]cript*|*[Gg]odot*) [ -f "$_gd4" ] && { rdargs+=(--read "$_gd4"); _is_godot=1; } ;; esac
  local _cc="" _abandon=0
  local _fb_static=""   # N4 Part 2: the structured failure of the previous staged run at THIS item (state/item_fails/...priorfail) rides along in every step prompt; OVN_STAGE_PRIORFAIL_STEP=off drops it
  if [ "${OVN_STAGE_PRIORFAIL_STEP:-on}" != off ]; then
    local _pfs; _pfs="state/item_fails/stage-${repo}.$(ovn_item_hash "$item" 2>/dev/null).priorfail"
    [ -s "$_pfs" ] && _fb_static=$'\n\n'"A PREVIOUS STAGED RUN AT THIS TASK FAILED - do not repeat it. $(head -c 900 "$_pfs")"
  fi
  # 2026-10-20: aider cannot delete files, so a planner step "Delete X ..." whose own VERIFY asserts absence gets X removed deterministically (git rm) at the start of EVERY attempt
  # (a failed attempt resets the tree to $base, which would resurrect it) and X is not handed to aider (it would just re-create it). OVN_STAGE_PURE_DELETE=off disables.
  local _pdp=""
  if declare -F stage_pure_delete_paths >/dev/null 2>&1; then
    _pdp="$(stage_pure_delete_paths "$wt" "$desc" "$files" "$item" "$verify" | tr '\n' ' ')"
    if [ -n "${_pdp// /}" ]; then
      local _nf=() _fi=0
      while [ "$_fi" -lt "${#fargs[@]}" ]; do
        case " $_pdp " in *" ${fargs[$((_fi+1))]} "*) : ;; *) _nf+=("${fargs[$_fi]}" "${fargs[$((_fi+1))]}");; esac
        _fi=$((_fi+2))
      done
      fargs=("${_nf[@]+"${_nf[@]}"}")
    fi
  fi
  local _fed_n=0   # N4 Part 4: files fed to this step's retries (max 3 per step)
  local _fb="" _fb_next=""   # N4: per-attempt retry feedback appended to the step prompt (reset each attempt; the failing branch sets _fb_next for the NEXT attempt)
  for att in $(seq 1 "$MAX_ATT"); do
    local base t0 atmp; base="$(git -C "$wt" rev-parse HEAD)"; t0=$(date +%s); atmp="$(mktemp "${TMPDIR:-/tmp}/ovn_stage_$$.XXXXXX")"
    _fb="${_fb_static}${_fb_next}"; _fb_next=""
    local _pd1; for _pd1 in $_pdp; do
      if git -C "$wt" rm -qf -- "$_pd1" >/dev/null 2>&1; then
        say "  pure-delete: git rm $_pd1 (aider cannot delete files; the step's own VERIFY asserts absence)"
        jlog "$(jq -nc --arg r "$RUNID" --argjson i "$idx" --arg f "$_pd1" '{run:$r,step:$i,event:"pure_delete",file:$f}')"
      fi
    done
    { echo "===== step $idx attempt $att @ $(date '+%F %T') (map=$mt arch=${#archargs[@]} read=${#rdargs[@]}) ====="; echo "DESC: $desc"; echo "FILES: $files"; echo "VERIFY: $verify"; } >> "$slog"
    local msg="Execute THIS one sub-step now and produce the diff. Do NOT do other steps.
STEP: $desc
VERIFY: $verify
Make the minimal change to the named file(s), keep it compiling + all tests green. Write a REAL working implementation — NO stub/placeholder/'for demonstration'/TODO/NotImplementedError. Any test you write MUST import and call the EXACT symbol you just created, and EVERY import in the test MUST resolve to a real module+symbol — check the actual file path of what you import (a single wrong import raises ImportError at collection time and fails the ENTIRE test file). For an endpoint, prefer a TestClient behavior test (client.get('/path')) over importing the handler. If writing a test, assert PROPERTIES not guessed exact values. Beware DB round-trips: a value read back from the DB may be naive (SQLite drops tzinfo) or lower-precision — assert on the value BEFORE persistence or on behavior, never that tzinfo/exact-precision survived a DB read.${_tgtctx}"
    if [ "$_is_godot" = 1 ]; then msg="This is a GODOT 4.x GDScript task. Follow the Godot-4 rules file you were given (GODOT4.md). Write Godot 4 ONLY — NEVER Godot 3 API (no 'export var', no 'yield(', no KinematicBody/Spatial, no string-signal connect). Use @export/@onready annotations, 'await', callable '.connect()', typed vars/returns. Only reference methods/signals that exist on the node type you extend. The gate will run gdparse + godot --check-only on your file and hand back any error to fix. Ignore the python/pytest/TestClient/DB guidance above — it does not apply here.
STEP: $desc
VERIFY: $verify
Make the minimal change to the named .gd file(s), valid Godot 4 that parses clean.${_tgtctx}"; fi
    msg="${msg}${_bgctx}${_bgre}${_fb}"
    # --no-auto-commits is CRITICAL: aider used to auto-commit each step, so by the time the post-gate
    # ran, git-diff was empty and ovn_autotest exited 0 WITHOUT testing anything (a T4 test with an
    # ImportError slipped through). Keeping the change uncommitted lets the scoped gate actually run the
    # step's tests; we commit ONLY after it's green.
    ( cd "$wt" && timeout "$STEP_TIMEOUT" aider \
        --yes-always --no-check-update --no-auto-commits --edit-format udiff \
        --model "openai/$MODEL" --openai-api-base "$LITELLM/v1" --openai-api-key "$LKEY" \
        --model-metadata-file "$HOME/overnight-queue/model-metadata.json" --map-tokens "$mt" \
        ${archargs[@]+"${archargs[@]}"} \
        --auto-test --test-cmd "bash $HOME/overnight-queue/scripts/ovn_autotest.sh $wt" \
        ${rdargs[@]+"${rdargs[@]}"} "${fargs[@]}" --message "$msg" ) > "$atmp" 2>&1
    cat "$atmp" >> "$slog"
    local dur=$(( $(date +%s) - t0 ))
    # capture aider's token accounting for value-per-task tracking (sum across the step's exchanges)
    local toks_sent toks_recv
    toks_sent="$(grep -oiE '[0-9.]+k? +sent' "$atmp" 2>/dev/null | grep -oiE '^[0-9.]+k?' | awk '/[kK]/{gsub(/[kK]/,"");s+=$1*1000;next}{s+=$1}END{print int(s)}')"; toks_sent="${toks_sent:-0}"
    toks_recv="$(grep -oiE '[0-9.]+k? +received' "$atmp" 2>/dev/null | grep -oiE '^[0-9.]+k?' | awk '/[kK]/{gsub(/[kK]/,"");s+=$1*1000;next}{s+=$1}END{print int(s)}')"; toks_recv="${toks_recv:-0}"
    local tok_s=$(( dur > 0 ? toks_recv / dur : 0 ))
    local dstat; dstat="$( { git -C "$wt" diff --shortstat "$base" HEAD 2>/dev/null; git -C "$wt" diff --shortstat 2>/dev/null; } | tr '\n' ';' | sed 's/^[; ]*//;s/[; ]*$//')"
    local excerpt="" ctx=0
    stage_ctx_exceeded "$atmp" && ctx=1
    if [ "$ctx" = 1 ]; then
      # aider never completed the edit — do NOT let a trivial partial change false-pass the scoped gate
      fa="context-exceeded"; rc=1
      excerpt="27B context window exceeded; shrinking (map->$((mt/2)), drop architect+AGENTS) and retrying"
    elif _cc="$(stage_class_conflict "$atmp")"; then
      # 2026-10-13 (xlite F3): Godot's `Class "X" hides an autoload singleton` / `hides a global script class` means the class this step wrote ALREADY EXISTS under that name (the real
      # CodexManager is an autoload). aider's own fix loop answered it by deleting the class_name line and the fabricated file went on to be committed. The step is aimed at something
      # that exists: abandon it (no retry, no re-decomposition). OVN_STAGE_CLASS_CONFLICT=off disables.
      fa="class-conflict"; rc=1; _abandon=1
      excerpt="Godot reported a class_name / autoload conflict (${_cc:0:90}): the class already exists - step abandoned, not retried"
    elif [ "$dur" -ge $((STEP_TIMEOUT - 12)) ]; then
      # aider was HARD-KILLED at the step timeout = it wandered / never finished its turn. A clean turn
      # exits before the timeout. Refuse to count a killed-mid-edit change as a pass (the T4 false-pass).
      fa="timeout"; rc=1
      excerpt="aider hit the ${STEP_TIMEOUT}s step timeout (wandered/incomplete) — not a clean pass"
    elif [ -z "$(git -C "$wt" status --porcelain -uall 2>/dev/null)" ]; then
      # 2026-09-09 FIX: this used to be `git diff --quiet "$base" HEAD && git diff --quiet`, which is
      # BLIND to untracked files - `git diff` never shows a brand-new file until it's `git add`ed, so
      # a step whose ENTIRE job was creating a new file (very common: "Create backend/app/utils/x.py")
      # got misclassified as "no-edit" even when aider had just reported "Applied edit to x.py" for a
      # real, complete implementation. Verified live: 179/282 (63%) of all "no-edit" failures in
      # state/stage_runs were exactly this "Create <new file>" pattern - the single largest failure
      # mode in the whole higher-tier pipeline was largely a false negative, not the model failing.
      # `git status --porcelain` (unlike `git diff`) reports untracked files too, so it's empty ONLY
      # when the worktree is genuinely unchanged. ($base == HEAD always holds here since nothing is
      # committed mid-attempt, so the old "$base" HEAD comparison was also always a no-op.)
      fa="no-edit"; rc=1
    elif [ "${OVN_STAGE_EMPTY_FILE:-on}" != off ] && stage_empty_files_scan "$wt" "$files" "$item"$'\n'"$desc"$'\n'"VERIFY: $verify"; then
      # 2026-10-13 (N4 Part 1): see stage_empty_files_scan. After an undeclared junk file was reaped the tree may be unchanged = a plain no-edit.
      if [ -n "$STAGE_EF_DECLARED" ]; then
        fa="empty-file"; rc=1
        excerpt="declared file is empty - write the full content: ${STAGE_EF_DECLARED}"
        _fb_next=$'\n\n'"YOUR PREVIOUS ATTEMPT FAILED: you left ${STAGE_EF_DECLARED} EMPTY (0 bytes). Write the COMPLETE content of that file this time (every import, function and test), not just its name."
      else fa="no-edit"; rc=1; fi
    elif [ "$_bg_on" = 1 ] && _bgdup="$(python3 "$_bg_py" dupes --wt "$wt" 2>/dev/null)" && [ -n "$_bgdup" ]; then
      # 2026-10-03 (A8): a NEW .kt file re-declaring a type that already exists (GroupedCategories.kt vs CategoryModels.kt, DiscoverModels.kt vs ChickadeeApi.kt)
      # only surfaced as 'Redeclaration' at the final verify (a 15-25 min cycle). Reject it NOW and re-prompt with the real definition.
      fa="duplicate-type"; rc=1; _bgre=$'\n\n'"$_bgdup"
      excerpt="$(printf '%s' "$_bgdup" | head -1 | cut -c1-300)"
      say "  step $idx REJECTED (duplicate type): ${excerpt:0:140}"
    else
      if ( cd "$wt" && bash "$HOME/overnight-queue/scripts/ovn_autotest.sh" "$wt" ) >> "$slog" 2>&1; then
        fa=""; rc=0
        # 2026-09-20 scope guard: for a multifile:no item, reject a step that touched files
        # outside its declared target(s) + a reasonable matching test-companion, instead of
        # silently accepting whatever else the diff contains — this is exactly the shape of
        # the earlier shrike-monitor incident where an obviously-hallucinated junk file
        # (aether/README.md) slipped through a scope-less gate.
        if printf '%s' "$item" | grep -qiE 'multifile:no'; then
          local _declared _touched _extra _tf _df _tb _base _ok
          _declared="$(
            { printf '%s\n' "$files" | tr ' ' '\n'
              printf '%s' "$item" | sed -E 's/^\[T[0-9]\] //' | grep -oE '^[A-Za-z0-9_./-]+\.[A-Za-z0-9]+'
              stage_scope_ext_list "$(ovn_item_hash "$item" 2>/dev/null)"   # N4 Part 3: files this item's scope was extended by (OVN_STAGE_SCOPE_LEARN=on only)
            } | grep -vE '^$' | sort -u)"
          _touched="$(git -C "$wt" status --porcelain -uall 2>/dev/null | awk '{print $2}' | sort -u)"
          _extra=""
          while IFS= read -r _tf; do
            [ -z "$_tf" ] && continue
            _ok=0
            while IFS= read -r _df; do
              [ -z "$_df" ] && continue
              if [ "$_tf" = "$_df" ]; then _ok=1; break; fi
              # allow a same-basename test companion (foo.py <-> test_foo.py/foo_test.py/
              # foo.spec.ts/foo.test.ts), regardless of directory
              _tb="$(basename "$_tf" | sed -E 's/\.[A-Za-z0-9]+$//; s/^test_//; s/_test$//; s/\.(spec|test)$//')"
              _base="$(basename "$_df" | sed -E 's/\.[A-Za-z0-9]+$//; s/^test_//; s/_test$//; s/\.(spec|test)$//')"
              if [ -n "$_tb" ] && [ "$_tb" = "$_base" ]; then _ok=1; break; fi
            done <<< "$_declared"
            [ "$_ok" -eq 0 ] && _extra="$_extra $_tf"
          done <<< "$_touched"
          if [ -n "$(printf '%s' "$_extra" | tr -d '[:space:]')" ]; then
            fa="scope-violation"; rc=1
            excerpt="multifile:no step touched undeclared file(s):${_extra} (declared: $(printf '%s' "$_declared" | tr '\n' ' '))"
            say "  step $idx REJECTED (scope): touched undeclared file(s):${_extra}"
            stage_scope_learn "$wt" "$_extra" "$idx"   # N4 Part 3 (shadow by default): remember U; a recurrence extends the scope (on) or is only logged (shadow)
            [ "$STAGE_SL_DECISION" = escalate ] && _abandon=1
          fi
        fi
      else
        fa="$(bash "$HOME/overnight-queue/ovn_classify_fail.sh" "$atmp" reverted 2>/dev/null)"; rc=1
        excerpt="$(grep -iE 'error|fail|assert|expected|traceback|<failure|cannot|not found|no attribute|no such' "$atmp" 2>/dev/null | tail -4 | tr '\n' ' ' | cut -c1-320)"
      fi
    fi
    # 2026-10-13 (N4 Part 4): a no-edit attempt whose architect reply asked for files ('Please add the following files to the chat') - add the repo paths it named to the retry (see stage_feed_files)
    if [ "$fa" = "no-edit" ] && [ "${OVN_STAGE_FILE_FEED:-on}" != off ] && [ "$att" -lt "$MAX_ATT" ] && [ "$_fed_n" -lt 3 ]; then
      local _feed _fp _fl=""
      _feed="$(stage_feed_files "$atmp" "$wt" "$files ${fargs[*]}" $((3 - _fed_n)))"
      if [ -n "$_feed" ]; then
        while IFS= read -r _fp; do
          [ -n "$_fp" ] || continue
          if grep -qiE 'multifile:no' <<< "$item"; then fargs+=(--read "$_fp"); else fargs+=(--file "$_fp"); fi
          _fed_n=$((_fed_n+1)); _fl="$_fl $_fp"
        done <<< "$_feed"
        say "  step $idx file-feed: the architect asked for files - adding${_fl} to the retry"
        jlog "$(jq -nc --arg r "$RUNID" --argjson i "$idx" --arg f "${_fl# }" '{run:$r,step:$i,event:"file_feed",files:$f}')"
        _fb_next="${_fb_next}"$'\n\n'"THE FILES YOU ASKED FOR ARE NOW IN THE CHAT:${_fl}. Do NOT ask for files again: make the edit now."
      fi
    fi
    rm -f "$atmp"
    jlog "$(jq -nc --arg r "$RUNID" --argjson i "$idx" --arg d "$desc" --arg f "$files" --argjson a "$att" \
      --arg v "$([ $rc -eq 0 ] && echo pass || echo fail)" --arg fr "${fa:-}" --argjson dur "$dur" \
      --argjson ts "${toks_sent:-0}" --argjson tr "${toks_recv:-0}" --argjson tps "${tok_s:-0}" \
      --arg ds "${dstat:-}" --arg ex "${excerpt:-}" \
      '{run:$r,step:$i,desc:$d,files:$f,attempt:$a,verdict:$v,fail_reason:$fr,duration_s:$dur,tokens_sent:$ts,tokens_recv:$tr,tok_s:$tps,diffstat:$ds,excerpt:$ex}')"
    if [ "$rc" -eq 0 ]; then
      say "  step $idx PASS (att $att, ${dur}s, ${dstat:-nostat}): ${desc:0:55}"
      STAGE_STEP_TEXT="${STAGE_STEP_TEXT:-}${desc//$'\n'/ }"$'\t'"${verify//$'\n'/ }"$'\n'   # iptv F2: the tests a LANDED step promised are checked in the final tree (stage_named_tests_check)
      git -C "$wt" add -A && ovn_unstage_abs_symlinks "$wt" && git -C "$wt" -c user.email=22970726+markhint22@users.noreply.github.com -c user.name=shrike-fleet commit -q -m "feat($repo): staged step $idx — ${desc:0:60}" 2>/dev/null
      return 0
    fi
    say "  step $idx att $att FAIL ($fa, ${dur}s): ${excerpt:0:90}"
    git -C "$wt" reset -q --hard "$base"; git -C "$wt" clean -qfd 2>/dev/null
    if [ "${_abandon:-0}" = 1 ]; then
      say "  step $idx ABANDONED ($fa): not retrying, not re-decomposing"
      jlog "$(jq -nc --arg r "$RUNID" --argjson i "$idx" '{run:$r,step:$i,verdict:"blocked"}')"
      return 1
    fi
    # if we blew the context window, shrink it for the next attempt so the step can actually fit
    if [ "$ctx" = 1 ]; then mt=$(( mt/2 < 1024 ? 1024 : mt/2 )); rdargs=(); archargs=(); fi
  done
  # persistent failure: re-decompose ONCE into smaller pieces
  if [ "$rd_left" -gt 0 ]; then
    say "  step $idx failing after $MAX_ATT — re-decomposing smaller"
    local sub; sub="$(decompose "$desc  (VERIFY: $verify)")"
    local nsub; nsub="$(printf '%s' "$sub" | jq 'length' 2>/dev/null || echo 0)"
    if [ "${nsub:-0}" -ge 2 ]; then
      jlog "$(jq -nc --arg r "$RUNID" --argjson i "$idx" --argjson n "$nsub" '{run:$r,step:$i,event:"redecomposed",into:$n}')"
      local k sub_ok=0; for k in $(seq 0 $((nsub-1))); do
        local sd sf sv
        sd="$(printf '%s' "$sub" | jq -r ".[$k].desc")"
        sf="$(printf '%s' "$sub" | jq -r ".[$k].files // [] | join(\" \")")"
        sv="$(printf '%s' "$sub" | jq -r ".[$k].verify // \"tests green\"")"
        if run_step "${idx}.${k}" "$sd" "$sf" "$sv" 0; then sub_ok=$((sub_ok+1)); else say "  sub-step ${idx}.${k} BLOCKED"; fi
      done
      # 2026-10-10 (harness R10, BX-09): this used to `return 0` ("partial progress") even when EVERY sub-step was BLOCKED, so a step that landed nothing counted as landed
      # (xlite 01:36 and 01:52 CDT: step 0 + 0.0 + 0.1 all BLOCKED, then "DONE: 1/1 steps landed (100%)" and 'independent full-verify: PASSED' on the unchanged tree).
      # A step lands only if at least one sub-step did; any BLOCKED sub-step also flags the step PARTIAL (STAGE_PARTIAL) so the item is never checked off as fully done.
      # OVN_STAGE_SUBSTEP_HONEST=off restores the old unconditional success.
      if [ "${OVN_STAGE_SUBSTEP_HONEST:-on}" = off ]; then return 0; fi
      [ "$sub_ok" -lt "$nsub" ] && STAGE_PARTIAL=$((STAGE_PARTIAL+1))
      [ "$sub_ok" -gt 0 ] && return 0
      say "  step $idx BLOCKED (all $nsub re-decomposed sub-steps BLOCKED - nothing landed)"
      jlog "$(jq -nc --arg r "$RUNID" --argjson i "$idx" '{run:$r,step:$i,verdict:"blocked"}')"
      return 1
    fi
  fi
  say "  step $idx BLOCKED (could not land after retries + re-decomp)"
  jlog "$(jq -nc --arg r "$RUNID" --argjson i "$idx" '{run:$r,step:$i,verdict:"blocked"}')"
  return 1
}

# ---- run all steps ----
passed=0
_SO_DONE=""; _SO_ANN=""   # D3: ids of the steps that landed (the unmet-prerequisite gate); _SO_ANN = shadow-mode annotated plan (carries deps)
STAGE_PARTIAL=0   # steps that landed only some of their re-decomposed sub-steps (see run_step)
STAGE_STEP_TEXT=""   # "desc<TAB>verify" of every step that LANDED (the tests they promised are checked in the final tree)
STAGE_MISTARGET_ITEM=0
# 2026-10-13 (xlite F3): an item whose OWN VERIFY greps a file that does not exist in the pristine tree (and that the item does not create) was aimed at a wrong path (the real module was
# scripts/codex/codex_manager.gd, the item said scripts/mission/): its VERIFY goes green the moment ANY step creates that file, which is how the fabricated module was credited. No step runs;
# the item is parked for Claude right away (zero-landing cap 1 below) - the 27B cannot fix a wrong path in the item text. OVN_STAGE_MISTARGET=off disables.
if _mti="$(stage_item_mistarget "$wt" "$item")"; then
  STAGE_MISTARGET_ITEM=1
  say "item REFUSED (mis-targeted): ${_mti:0:200}"
  jlog "$(jq -nc --arg r "$RUNID" --arg ex "mis-targeted item: $_mti" '{run:$r,step:-1,desc:"item pre-check",files:"",attempt:0,verdict:"fail",fail_reason:"mistargeted",duration_s:0,tokens_sent:0,tokens_recv:0,excerpt:$ex}')"
  echo "-- QUALITY FAIL: mis-targeted item: ${_mti} --" > "${SLOG%.jsonl}.verify.log"
fi
# 2026-10-13 (xlite F3 / iptv F2): the item's own VERIFY on the PRISTINE tree (red-before). Shadow by default (OVN_STAGE_ITEM_VERIFY=off|shadow|enforce); the verdict after the change is taken below.
STAGE_IV_PRE=""
_iv_mode="${OVN_STAGE_ITEM_VERIFY:-shadow}"
if [ "$STAGE_MISTARGET_ITEM" = 0 ] && [ "$_iv_mode" != off ]; then
  _iv_snap="$(git -C "$wt" status --porcelain -uall 2>/dev/null)"
  if [ -n "${_PRE_EARLY:-}" ]; then STAGE_IV_PRE="$_PRE_EARLY"   # D2: already probed (pristine) before the planner ran
  else STAGE_IV_PRE="$(OVN_STAGE_REPO="$repo" OVN_STAGE_REPO_DIR="$rd" stage_item_verify_run "$wt" "$item")"; fi
  stage_tree_restore "$wt" "$_iv_snap"   # a VERIFY run must leave nothing behind that the per-step no-edit check (git status) would read as an edit (the provisioned node_modules / .godot symlinks stay)
  say "item VERIFY on the pristine tree: ${STAGE_IV_PRE%%|*}"
  # 2026-10-13 (N4 Part 5, SHADOW ONLY): see stage_item_is_verify_only. Logs only - never changes enforcement, credit or the steps that run.
  if [ "${OVN_STAGE_VERIFYONLY_PREFLIGHT:-shadow}" != off ] && [ "${STAGE_IV_PRE%%|*}" = PASS ] && stage_item_is_verify_only "$item"; then
    say "verify-only item whose own VERIFY already PASSES on the pristine tree (shadow: logged only, the steps still run): ${item:0:100}"
    jlog "$(jq -nc --arg r "$RUNID" --arg why "${STAGE_IV_PRE#*|}" '{run:$r,event:"verify_only_pristine_pass",mode:"shadow",pre:"PASS",why:$why}')"
    stage_shadow_log_cap "${OVN_STAGE_VERIFYONLY_LOG:-state/stage_verifyonly_shadow.log}"
    echo "$(date '+%F %T') [$repo] verify_only_pristine_pass run=$RUNID item=${item:0:160}" >> "${OVN_STAGE_VERIFYONLY_LOG:-state/stage_verifyonly_shadow.log}" 2>/dev/null
  fi
fi
if [ "$STAGE_MISTARGET_ITEM" = 0 ]; then
for i in $(seq 0 $((NSTEPS-1))); do
  d="$(printf '%s' "$STEPS_JSON" | jq -r ".[$i].desc")"
  f="$(printf '%s' "$STEPS_JSON" | jq -r ".[$i].files // [] | join(\" \")")"
  v="$(printf '%s' "$STEPS_JSON" | jq -r ".[$i].verify // \"tests green\"")"
  # D3: runtime gate. A step whose prerequisite step has not landed is parked (enforce) - never run red-by-design before the fix it tests; shadow only journals the would-have decision.
  _so_sid="$(printf '%s' "$STEPS_JSON" | jq -r ".[$i].id // $i")"; _so_um=""
  if [ "$_SO_MODE" != off ]; then _so_um="$(printf '%s' "${_SO_ANN:-$STEPS_JSON}" | python3 "$_SO_PY" unmet --i "$i" --done "$_SO_DONE" 2>/dev/null)"; fi
  if [ -n "$_so_um" ]; then
    say "  step $i waits for unlanded prerequisite step(s) [$_so_um] (step-order $_SO_MODE)"
    jlog "$(jq -nc --arg r "$RUNID" --argjson i "$i" --arg u "$_so_um" --arg m "$_SO_MODE" '{run:$r,step:$i,event:(if $m=="enforce" then "step_parked_dep" else "would_park_dep" end),mode:$m,unmet:$u}')"
    if [ "$_SO_MODE" = enforce ]; then STAGE_PARTIAL=$((STAGE_PARTIAL+1)); continue; fi
  fi
  if run_step "$i" "$d" "$f" "$v" "$REDECOMP"; then passed=$((passed+1)); _SO_DONE="$_SO_DONE $_so_sid"; fi
done
fi

# ---- INDEPENDENT full verification (autonomous — does NOT depend on a human spot-checking) ----
# The per-step gate proved insufficient (a circular import that broke the whole backend, and a
# "wire X into Y" that never wired, both false-passed). Before we trust/push/mark ANYTHING, run the
# ENTIRE relevant suite on the combined result + a semantic check. Nothing lands unless this is green.
full_verify(){   # 0 = independently verified real; 1 = false-pass/broken
  local vok=1 vlog="${SLOG%.jsonl}.verify.log"; : > "$vlog"
  echo "$(date '+%F %T') independent full-verify (combined result)" >> "$vlog"
  # PYTHON: FULL suite (catches circular imports / cross-file breaks / all tests) via the live venv
  local vp; vp="$(find "$rd" -maxdepth 4 -path '*/.venv/bin/pytest' 2>/dev/null | head -1)"
  if [ -n "$vp" ]; then
    local pkg; pkg="${vp%/.venv/bin/pytest}"; pkg="${pkg#"$rd"/}"; [ "$pkg" = "$rd" ] && pkg="."   # 2026-09-30: a repo-ROOT .venv left pkg as the absolute path, so [ -d "$wt/$pkg" ] was false and the whole python suite was silently skipped
    # 600s (was 300s, 2026-09-09): iptv_apps's full pytest suite (1436 tests, ~356s+ measured) was
    # getting killed at exactly 300s every single T3+ run (confirmed via verify.log truncated
    # mid-progress-bar at 81% + start/FAILED log timestamps exactly 300s apart), a false-revert
    # of every T4/T5 attempt regardless of whether the change was actually good — same class of
    # bug as the run_overnight.sh 240->600 fix, just a separate hardcoded cap in this file.
    # 2026-09-29: parallel (pytest-xdist) for allowlisted repos - iptv_apps' full suite is ~456s
    # serial vs ~64s with -n 8, and this runs on every staged (T3+) run. Empty (=> serial, as
    # before) unless the repo is allowlisted AND xdist imports in the live venv used here.
    local _xd; _xd="$(ovn_pytest_par_args "$(basename "$rd")" "$(dirname "$HOME/overnight-queue/$vp")")"
    [ -d "$wt/$pkg" ] && { echo "-- pytest FULL in $pkg ${_xd:+(parallel: $_xd)} --" >> "$vlog"; ( cd "$wt/$pkg" && timeout 600 "$HOME/overnight-queue/$vp" -q $_xd -o addopts="" -p no:cacheprovider ) >> "$vlog" 2>&1 || vok=0; }
  fi
  # FAIL CLOSED (2026-09-30): python tests exist but no live venv pytest was found -> the python suite silently did not run and this function
  # returned "verified" (2026-09-30 11:46-12:24: two red shrike-notify staged steps landed this way while the venv was broken).
  if [ -z "$vp" ] && [ "${OVN_VERIFY_FAIL_CLOSED:-1}" = 1 ] && find "$rd" -maxdepth 4 -path '*/tests/test_*.py' -not -path '*/node_modules/*' -not -path '*/.venv/*' 2>/dev/null | grep -q .; then
    echo "-- python tests exist but no venv pytest found: CANNOT verify (fail-closed) --" >> "$vlog"; vok=0
  fi
  # LANDING GATES (2026-10-03): revision-less/placeholder alembic files + removed-but-still-imported requirements +
  # clean-venv import of app.main (the iptv_apps 0011 stub / aiohttp prod-deploy incidents). Both helpers fail-safe:
  # absent script or infra failure = no effect. The stub-drop runs first so an unfilled stub is deleted, not failed.
  if [ -x scripts/ovn_alembic_autogen.sh ]; then
    GIT_AUTHOR_NAME=shrike-fleet GIT_COMMITTER_NAME=shrike-fleet GIT_AUTHOR_EMAIL=22970726+markhint22@users.noreply.github.com \
      GIT_COMMITTER_EMAIL=22970726+markhint22@users.noreply.github.com bash scripts/ovn_alembic_autogen.sh --drop-stubs "$wt" >> "$vlog" 2>&1
  fi
  if [ -f scripts/check_migrations.py ] && ! python3 scripts/check_migrations.py "$wt" >> "$vlog" 2>&1; then
    echo "-- MIGRATION SAFETY FAIL (see above) --" >> "$vlog"; vok=0
  fi
  if [ -f scripts/lib_dep_import_check.py ]; then
    python3 scripts/lib_dep_import_check.py gate --repo "$wt" --before "$(git -C "$wt" rev-parse origin/overnight/feature 2>/dev/null)" >> "$vlog" 2>&1 \
      || { echo "-- DEP-IMPORT FAIL (see above) --" >> "$vlog"; vok=0; }
  fi
  # ANDROID (Gradle) — 2026-09-16 FIX: full_verify() had ZERO Kotlin/Android coverage, so a staged
  # multi-step item touching a .kt file got NO real re-check before being trusted/pushed — the
  # exact "false-pass" risk this function exists to close for python/vitest/godot. Same
  # ANDROID_HOME/local.properties pattern as run_overnight.sh's working per-item gradle check.
  if [ "$vok" = 1 ]; then
    while IFS= read -r -d '' gradlew; do
      gdir="$(dirname "$gradlew")"
      if [ -f "$gdir/settings.gradle.kts" ] || [ -f "$gdir/settings.gradle" ]; then
        echo "-- gradlew test FULL in ${gdir#"$wt"/} --" >> "$vlog"
        ( cd "$gdir" &&
          export ANDROID_HOME="$HOME/android-sdk" &&
          [ -f local.properties ] || echo "sdk.dir=$ANDROID_HOME" > local.properties &&
          timeout 240 ./gradlew test --console=plain ) >> "$vlog" 2>&1 || vok=0
      fi
    done < <(find "$wt" -maxdepth 3 -type f -name "gradlew" -print0 2>/dev/null)
  fi
  # GODOT: GUT full suite + compile scan
  if [ "$vok" = 1 ] && [ -f "$wt/project.godot" ] && [ -x "$HOME/godot/godot4" ]; then
    echo "-- GUT FULL --" >> "$vlog"
    ( cd "$wt" && timeout 120 "$HOME/godot/godot4" --headless --path . --import ) >>"$vlog" 2>&1
    local xml; xml="$(mktemp)"
    ( cd "$wt" && timeout 90 "$HOME/godot/godot4" --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests $GUT_SUBDIRS -gexit "-gjunit_xml_file=$xml" ) >> "$vlog" 2>&1
    { [ -s "$xml" ] && gut_xml_green "$xml"; } || { vok=0; echo "-- GUT RED: $(gut_xml_summary "$xml") --" >> "$vlog"; }
    grep -qiE 'Failed to load script|Failed to compile|Parse Error' "$vlog" && vok=0; rm -f "$xml"
  fi
  # NEW/CHANGED TESTS (2026-10-04, QA audit H): explicitly run the test files this cycle added/changed. A new test file the verify command never
  # collects (iptv app/**/test_*.py, xlite test/ or *_test.gd) used to pass silently. Infra trouble (timeout/missing tool) = proceed, never red.
  # OVN_RUN_NEW_TESTS=off disables. Fail-safe: lib missing => no effect.
  if [ "$vok" = 1 ] && [ "${OVN_RUN_NEW_TESTS:-on}" != "off" ] && declare -F ovn_run_new_tests >/dev/null 2>&1; then
    ovn_run_new_tests "$wt" "${pkg:-.}" "${vp:+$HOME/overnight-queue/$vp}" "$HOME/godot/godot4" "$(git -C "$wt" rev-parse origin/overnight/feature 2>/dev/null || echo HEAD)" "$vlog" || vok=0
  fi
  # WEB: vitest full run (reuse provisioned node_modules)
  if [ "$vok" = 1 ]; then
    # 2026-09-30: the old detection piped `find | grep -l .` which yields the literal "(standard input)", so this block has NEVER run in
    # production (no "vitest FULL" line in any verify log). Detection is fixed below, but the full vitest run is OPT-IN
    # (OVN_STAGE_VITEST_FULL=1): turning on a brand-new full-suite gate unvalidated could fail healthy stage runs.
    local pj=""
    if [ "${OVN_STAGE_VITEST_FULL:-0}" = 1 ]; then
      pj="$(find "$rd" -maxdepth 3 -name package.json -not -path '*/node_modules/*' 2>/dev/null | xargs -r grep -l '"vitest"' 2>/dev/null | head -1)"
    fi
    if [ -n "$pj" ] && grep -q '"vitest"' "$pj" 2>/dev/null; then
      local wd; wd="$(dirname "$pj")"
      [ -d "$wd/node_modules" ] && { local wwd; wwd="$wt/${wd#"$rd"/}"; [ -e "$wwd/node_modules" ] || ln -s "$(cd "$wd" && pwd)/node_modules" "$wwd/node_modules" 2>/dev/null; echo "-- vitest FULL --" >> "$vlog"; ( cd "$wwd" && CI=true timeout 240 npx vitest run ) >> "$vlog" 2>&1 || vok=0; }
    fi
  fi
  # SHELL SCRIPTS — 2026-09-16 FIX: same coverage gap as branch_hygiene.sh's run_gate() (see its
  # own 2026-09-16 comment) — no path here ever checked a .sh file's syntax either. Cheap, always run.
  if [ "$vok" = 1 ]; then
    while IFS= read -r -d '' sh; do
      bash -n "$sh" 2>>"$vlog" || vok=0
    done < <(find "$wt" -maxdepth 4 -type f -name "*.sh" -not -path "*/node_modules/*" -print0 2>/dev/null)
  fi
  # DOCKER — 2026-09-16 FIX: same as branch_hygiene.sh's run_gate() — only pay the expensive real
  # `docker build` cost when the Dockerfile actually differs from the main clone (measured 146s
  # cold on a representative FastAPI+deps image; see the per-verify budget comment above, raised
  # to account for this). Always `docker rmi` the tagged image after, pass or fail.
  if [ "$vok" = 1 ]; then
    while IFS= read -r -d '' df; do
      ddir="$(dirname "$df")"; rel="${df#"$wt"/}"; mainfile="$rd/$rel"
      [ -f "$mainfile" ] && cmp -s "$df" "$mainfile" && continue
      echo "-- docker build FULL in ${ddir#"$wt"/} --" >> "$vlog"
      imgtag="stage-verify-$(basename "$rd")-$$-$RANDOM"
      ( cd "$ddir" && timeout 400 docker build -t "$imgtag" -f "$(basename "$df")" . ) >> "$vlog" 2>&1 || vok=0
      docker rmi "$imgtag" >/dev/null 2>&1
    done < <(find "$wt" -maxdepth 3 -type f -name "Dockerfile" -print0 2>/dev/null)
  fi
  # SEMANTIC: a "wire/integrate/register X into FILE" item must leave FILE actually referencing X
  # 2026-10-18 FIX (gitlark audit): match the trigger words against the item's PROSE only. The item
  # carries a trailing `[feat:...-should-invoke-]` tag and `<!-- ... -->` annotations; hyphens are
  # non-word chars so `\binvoke\b` matched INSIDE the feat tag of a pure REMOVAL item ("Remove the
  # import and all test cases for `should_invoke_control_plane`") and the gate then demanded the
  # file still reference the symbol it had just been asked to delete -> 3 consecutive
  # no-op(stage-unverified) cycles (~35 min of model time) on gitlark. Also skip removal items
  # (leading Remove/Delete/Drop/Retire verb): "never uses X" is the goal there, not a failure.
  # Off-switch: OVN_STAGE_SEMANTIC_PROSE_ONLY=0 restores the old whole-text match.
  local _sem_text="$item"
  if [ "${OVN_STAGE_SEMANTIC_PROSE_ONLY:-1}" = 1 ]; then
    _sem_text="$(printf '%s' "$item" | sed -E 's/<!--.*-->//g; s/\[feat:[^]]*\]//g')"
    if printf '%s' "$_sem_text" | grep -qiE '^\[T[0-9]\] +[^ ]+ +(—|-) +(remove|delete|drop|retire)\b'; then _sem_text=""; fi
  fi
  if printf '%s' "$_sem_text" | grep -qiE '\b(wire|integrate|register|hook|call|invoke)\b'; then
    local sym sym_alt tgt refs ok=0 cand
    sym="$(printf '%s' "$item" | grep -oE '`[A-Za-z_][A-Za-z0-9_.]*`' | head -1 | tr -d '`' | sed 's/.*\.//')"
    # 2026-09-19 FIX: the FIRST bare-identifier backtick token is frequently the function being
    # EDITED, not the thing being integrated — e.g. "Wrap the `db.commit()` call in
    # `add_to_watchlist()` ... that calls `handle_integrity_error(db, x)`" picks add_to_watchlist
    # (its own `()` variant doesn't match the bare-identifier regex, so the LAST plain-identifier
    # backtick token elsewhere in the item, e.g. inside its own VERIFY clause, wins by default).
    # add_to_watchlist is the function whose body was modified, so it structurally has exactly one
    # "def" reference and nothing else — the check then ALWAYS reports SEMANTIC FAIL for this class
    # of item regardless of how correct the edit is. Confirmed live: iptv_apps spun on this exact
    # false positive for 9 consecutive stage-runner cycles (~4.5h) across two near-identical items
    # (favorites.py add_to_watchlist/add_favorite) — the aider diff each time correctly defined AND
    # called handle_integrity_error, but the item was reverted anyway every single time.
    # Fix: also compute the LAST backtick-quoted call-syntax token, "`name(", in the item (usually
    # the real callee described by "...that calls `X(...)`") and try both candidates, original
    # bare-identifier first. This is strictly additive — any item whose original extraction already
    # passes is unaffected (the loop short-circuits on the first match), so nothing that already
    # verifies correctly can regress; only previously-false-FAIL items get a fair second look.
    sym_alt="$(printf '%s' "$item" | grep -oE '`[A-Za-z_][A-Za-z0-9_.]*\(' | tail -1 | tr -d '`(' | sed 's/.*\.//')"
    # target file: prefer a file named after "into/in <file>"; else the item's PRIMARY named file (the
    # one at the start, e.g. "checker.py — Integrate X into ..."). NOT the last path (that's often the test).
    tgt="$(printf '%s' "$item" | grep -oiE '\b(into|in) +`?[A-Za-z0-9_./-]+\.(gd|py|ts|tsx|vue)' | grep -oE '[A-Za-z0-9_./-]+\.(gd|py|ts|tsx|vue)' | head -1)"
    [ -z "$tgt" ] && tgt="$(printf '%s' "$item" | grep -oE '[A-Za-z0-9_./-]+\.(gd|py|ts|tsx|vue)' | head -1)"
    if [ -n "$tgt" ] && [ -f "$wt/$tgt" ] && { [ -n "$sym" ] || [ -n "$sym_alt" ]; }; then
      for cand in "$sym" "$sym_alt"; do
        [ -z "$cand" ] && continue
        # count references OUTSIDE the symbol's own definition line: a real integration USES the symbol
        refs="$(grep -c "$cand" "$wt/$tgt" 2>/dev/null)"; refs="${refs:-0}"   # NO `|| echo 0` (that yields "0\n0" -> integer errors)
        if [ "$refs" -ge 2 ] || { [ "$refs" -ge 1 ] && ! grep -qE "(def|func|function|static func) +$cand" "$wt/$tgt" 2>/dev/null; }; then
          echo "-- semantic OK: $tgt uses $cand ($refs refs) --" >> "$vlog"; ok=1; sym="$cand"; break
        fi
      done
      if [ "$ok" = 0 ]; then
        echo "-- SEMANTIC FAIL: $tgt only defines (or never uses) $sym — the claimed integration never happened --" >> "$vlog"; vok=0
      fi
    fi
  fi
  # QUALITY: reject stub/placeholder implementations, and tests that never exercise the new code
  # (the gitlark PlanService "win" was a keyword stub whose test tested a DIFFERENT class — a fake pass).
  local changed; changed="$(git -C "$wt" diff --name-only origin/overnight/feature..HEAD 2>/dev/null)"
  # 2026-10-20: srcs/tests (the 'changed test exercises the changed source' check) are built from files that still EXIST (ACMR): a deletion has nothing to exercise (stage_changed_live_files).
  local _live; if declare -F stage_changed_live_files >/dev/null 2>&1; then _live="$(stage_changed_live_files "$wt")"; else _live="$changed"; fi
  local srcs tests; srcs="$(printf '%s\n' "$_live" | grep -E '\.(py|gd|ts|tsx|vue)$' | grep -viE 'test|spec')"
  tests="$(printf '%s\n' "$_live" | grep -iE 'test|spec' | grep -E '\.(py|gd|ts|tsx|vue)$')"
  # 2026-09-18: the srcs/tests-exercise guard below only runs when $srcs is non-empty, so a step
  # that touches ZERO real source files and only creates an EMPTY test/source file (0 bytes) sails
  # through completely unchecked - confirmed live twice tonight: billwatch's vote_sync_service.py +
  # test_vote_sync_service.py landed as a 0-byte "feat" commit (self-healed by a later step before
  # this was caught), and test-automation-agent's test_upload_status.py stayed 0 bytes forever while
  # get_upload_status() in uploads.py was never actually touched - the item was still marked
  # "staged 1/1 DONE" because the FULL suite (which trivially collects 0 tests from an empty file
  # without failing) stayed green. Same bug class as the empty FlakeDashboardPage.spec.js 3-day
  # false-red, generalized: any 0-byte file this step touched is never a real deliverable.
  for cf in $changed; do
    [ -f "$wt/$cf" ] || continue
    if [ ! -s "$wt/$cf" ]; then
      echo "-- QUALITY FAIL: $cf is a 0-byte file - not a real implementation or test --" >> "$vlog"; vok=0
    fi
  done
  local cf
  # 2026-09-20 FIX: this used to grep the WHOLE file on disk ("$wt/$cf") instead of just the
  # lines this stage run actually added/changed, so any file that already legitimately contained
  # one of these substrings ANYWHERE — e.g. a pre-existing VS Code `placeHolder:` API option, an
  # HTML/Tailwind `placeholder="..."` attribute or `placeholder-gray-400` class, or an old comment
  # documenting a genuinely-unimplemented unrelated feature — permanently blocked every future
  # stage-runner change to that file, no matter how unrelated or how cleanly it verified. Confirmed
  # live: gitlark's backend/app/routers/pull_requests.py (a stale "VERIFY/test-result correlation
  # is NOT implemented" comment) failed this gate 8 times across three days, and gitlark's
  # code-review.ts, iptv_apps's DiscoverView.vue and HomeView.vue each tripped it on a bare
  # `placeholder`/`placeHolder` identifier while their actual new code was a fully passing,
  # verified change — all discarded as no-op(stage-unverified) for a false reason. Scope the check
  # to only the lines this run actually added, via the same origin/overnight/feature..HEAD diff
  # already used to build $changed above, so pre-existing file content can no longer trigger it.
  for cf in $srcs; do
    [ -f "$wt/$cf" ] || continue
    if git -C "$wt" diff origin/overnight/feature..HEAD -- "$cf" 2>/dev/null | grep -E '^\+' | grep -vE '^\+\+\+' | grep -qiE 'for demonstration|placeholder|not implemented|NotImplementedError|TODO:? implement|for now,? (just|return)|# *stub|dummy (value|impl)|simple .* for demonstration'; then
      echo "-- QUALITY FAIL: $cf is a stub/placeholder — a real working implementation is required --" >> "$vlog"; vok=0
    fi
  done
  # 2026-09-14: none of the keyword patterns above catch a bare `pass`-only body, which is valid
  # GDScript/Python syntax (so it parses clean and passes every gate above) but is a complete no-op.
  # Confirmed live: a godot staging run landed `static func simulate_missing_files() -> void: pass`
  # — WRONG arg count, WRONG return type, and zero logic — and this exact check block let it through
  # because "pass" alone matches none of the stub-keyword regex. Flag any newly-ADDED function whose
  # entire body (ignoring blank lines/comments) is just `pass`/`...`/`return None` before the next
  # def/func boundary or EOF — that shape is never a legitimate "real" implementation for a task that
  # asked for actual logic.
  for cf in $srcs; do
    [ -f "$wt/$cf" ] || continue
    case "$cf" in *.gd|*.py) : ;; *) continue ;; esac
    if git -C "$wt" diff origin/overnight/feature..HEAD -- "$cf" 2>/dev/null | python3 -c "
import sys, re
added = [l[1:] for l in sys.stdin if l.startswith('+') and not l.startswith('+++')]
i = 0
while i < len(added):
    if re.match(r'^\s*(static func|func|def)\s+\w+', added[i]):
        j = i + 1
        body = []
        while j < len(added) and not re.match(r'^\s*(static func|func|def|class)\b', added[j]):
            s = added[j].strip()
            if s and not s.startswith('#'):
                body.append(s)
            j += 1
        if body and all(b in ('pass', '...', 'return None', 'return') for b in body):
            print(added[i].strip()[:60]); sys.exit(0)
    i += 1
sys.exit(1)
" > /tmp/stub_hit.$$ 2>/dev/null; then
      echo "-- QUALITY FAIL: $cf has a bare pass/no-op body for a newly-added function ($(cat /tmp/stub_hit.$$ 2>/dev/null)) — not a real implementation --" >> "$vlog"; vok=0
    fi
    rm -f /tmp/stub_hit.$$
  done
  # a changed test must EXERCISE the changed source — either by referencing a new symbol OR (for
  # endpoints/routes) by hitting a route path the source added (endpoint tests use client.get("/topics"),
  # they don't name the handler symbol; requiring the symbol false-rejected real route work).
  if [ -n "$srcs" ] && [ -n "$tests" ]; then
    local newsym routes hit=0
    for cf in $srcs; do
      newsym="$(grep -oE '^ *(class|def|func|static func|export function|export const) +[A-Za-z_][A-Za-z0-9_]*' "$wt/$cf" 2>/dev/null | awk '{print $NF}' | head -8)"
      # route paths added by this source: @router.get("/x"), @app.post("/y"), path="/z"
      routes="$(grep -oE '(@[a-z_]+\.(get|post|put|patch|delete)|path=)[[:space:]]*\(?["'"'"'][^"'"'"']+' "$wt/$cf" 2>/dev/null | grep -oE '/[A-Za-z0-9_{}./-]*' | sort -u | head -6)"
      # the source MODULE name (basename): an update-existing item has no NEW symbol, but its test still
      # imports/references the module it changed (from app.services.flake_detection import ...).
      local modname; modname="$(basename "$cf" | sed -E 's/\.(py|gd|ts|tsx|vue)$//')"
      for s in $newsym; do for tf in $tests; do grep -qw "$s" "$wt/$tf" 2>/dev/null && hit=1; done; done
      for rp in $routes; do for tf in $tests; do grep -qF "$rp" "$wt/$tf" 2>/dev/null && hit=1; done; done
      [ -n "$modname" ] && for tf in $tests; do grep -qw "$modname" "$wt/$tf" 2>/dev/null && hit=1; done
    done
    if [ "$hit" = 0 ]; then
      echo "-- QUALITY FAIL: no changed test exercises the changed source (no new symbol, added route, NOR the changed module referenced) --" >> "$vlog"; vok=0
    fi
  fi
  # LANDING QUALITY (2026-10-18 landing audit, every pushed(tests:pass) of 6h; scripts/ovn_landing_quality.py): a green suite cannot see a tautological assertion (`assert .. or True`:
  # billwatch), a discarded `_ = call()` that only "uses" an import for the item's VERIFY (test-automation-agent), a function defined twice in one class so the second shadows the first
  # (shrike-notify), or a NEW private helper nothing but its own test references (iptv `_to_utc`). 4 true positives / 0 false positives over the 52 fleet commits of that window.
  # Findings are `-- QUALITY FAIL` rows (the repair prompt carries them). OVN_STAGE_LANDING_QUALITY=off|shadow|enforce (default enforce); the checker exiting 2 (git error) = no verdict.
  # 2026-10-18 repair (adversarial review): each rule is enforced or shadow per OVN_LQ_RULES_ENFORCE (default = only the rules with 0 false positives over a 2878-landing replay of 7 repos);
  # the checker prints enforced findings as `RULE<TAB>path<TAB>detail` and shadow-only ones as `~RULE...` (never rc 1): journaled as event landing_quality_shadow, never a QUALITY FAIL.
  if [ "$vok" = 1 ] && [ "${OVN_STAGE_LANDING_QUALITY:-enforce}" != off ] && [ -f scripts/ovn_landing_quality.py ]; then
    local _lq="" _lqrc=0 _lqb _lqe _lqs
    _lqb="$(git -C "$wt" rev-parse origin/overnight/feature 2>/dev/null)"
    if [ -n "$_lqb" ]; then _lq="$(timeout "${OVN_LQ_TIMEOUT:-90}" python3 scripts/ovn_landing_quality.py check "$wt" "$_lqb" HEAD 2>/dev/null)" || _lqrc=$?; fi
    _lqs="$(printf '%s\n' "$_lq" | grep '^~' || true)"
    _lqe="$(printf '%s\n' "$_lq" | grep -v '^~' | grep . || true)"
    if [ -n "$_lqs" ] && [ "$_lqrc" -le 1 ]; then
      say "landing-quality SHADOW (not enforced): $(printf '%s' "$_lqs" | tr '\t\n' ' |' | cut -c1-300)"
      jlog "$(jq -nc --arg r "$RUNID" --arg d "$(printf '%s' "$_lqs" | tr '\t\n' ' |' | cut -c1-600)" '{run:$r,event:"landing_quality_shadow",mode:"shadow-rule",detail:$d}')"
    fi
    if [ "$_lqrc" = 1 ] && [ -n "$_lqe" ]; then
      say "landing-quality (${OVN_STAGE_LANDING_QUALITY:-enforce}): $(printf '%s' "$_lqe" | tr '\t\n' ' |' | cut -c1-300)"
      jlog "$(jq -nc --arg r "$RUNID" --arg d "$(printf '%s' "$_lqe" | tr '\t\n' ' |' | cut -c1-600)" --arg m "${OVN_STAGE_LANDING_QUALITY:-enforce}" '{run:$r,event:"landing_quality",mode:$m,detail:$d}')"
      if [ "${OVN_STAGE_LANDING_QUALITY:-enforce}" = enforce ]; then
        while IFS=$'\t' read -r _lqr _lqp _lqd; do
          [ -n "$_lqr" ] && echo "-- QUALITY FAIL: $_lqp: ${_lqr} - ${_lqd} --" >> "$vlog"
        done <<< "$_lqe"
        vok=0
      fi
    fi
  fi
  # NAMED TESTS (2026-10-13, iptv F2): every test function the item / a landed step PROMISED ("Add test test_x") must exist in the FINAL tree and pass when run by node id (rc 4 / 5 = not found /
  # not collected = a failure). A repair round used to delete the very test it was meant to fix and the green suite (which no longer contained it) credited the item. The failure lines are
  # `-- QUALITY FAIL` rows, so the repair prompt carries them. OVN_STAGE_NAMED_TESTS=off|shadow|enforce (default enforce).
  if [ "$vok" = 1 ]; then
    stage_named_tests_check "$wt" "$vlog" "$item" "${STAGE_STEP_TEXT:-}" "${vp:+$HOME/overnight-queue/$vp}" "${pkg:-.}" || vok=0
  fi
  # RED-BEFORE (2026-10-13, iptv F6, SHADOW by default): a test the change ADDED must FAIL once the change's non-test python source is reverted (test_genres_query_count passed on the pre-change code too).
  if [ "$vok" = 1 ] && [ "${OVN_STAGE_RED_BEFORE:-shadow}" != off ]; then
    local _rb _rbrc=0
    _rb="$(stage_red_before_check "$wt" "$(git -C "$wt" rev-parse origin/overnight/feature 2>/dev/null)" "$vlog" "${vp:+$HOME/overnight-queue/$vp}" "${pkg:-.}")" || _rbrc=$?
    [ -n "$_rb" ] && { say "red-before (${OVN_STAGE_RED_BEFORE:-shadow}): ${_rb#RB }"; jlog "$(jq -nc --arg r "$RUNID" --arg d "$_rb" --arg m "${OVN_STAGE_RED_BEFORE:-shadow}" '{run:$r,event:"red_before",mode:$m,detail:$d}')"; }
    [ "$_rbrc" -ne 0 ] && vok=0
  fi
  # WEB (2026-10-13, iptv F6, SHADOW by default): vue-tsc + vitest related for the changed web files (the staged full-verify ran only pytest and gradle; web breakage surfaced hours later at the hygiene gate).
  if [ "$vok" = 1 ] && [ "${OVN_STAGE_WEB_VERIFY:-shadow}" != off ]; then
    local _wv _wvrc=0 _wv_snap
    _wv_snap="$(git -C "$wt" status --porcelain -uall 2>/dev/null)"
    _wv="$(stage_web_verify "$wt" "$(git -C "$wt" rev-parse origin/overnight/feature 2>/dev/null)" "$vlog")" || _wvrc=$?
    stage_tree_restore "$wt" "$_wv_snap"   # tsc / vitest droppings must never reach a later `git add -A` (repair round commit)
    [ -n "$_wv" ] && { say "web-verify (${OVN_STAGE_WEB_VERIFY:-shadow}): ${_wv#WEB }"; jlog "$(jq -nc --arg r "$RUNID" --arg d "$_wv" --arg m "${OVN_STAGE_WEB_VERIFY:-shadow}" '{run:$r,event:"web_verify",mode:$m,detail:$d}')"; }
    [ "$_wvrc" -ne 0 ] && vok=0
  fi
  return $((1 - vok))
}

# try_regen: many verify fails are just a STALE GENERATED ARTIFACT (OpenAPI spec, schema, snapshot) —
# the model added an endpoint/model, the committed docs/openapi.json (etc.) no longer matches, and the
# repo's freshness test says e.g. "re-run `python scripts/export_openapi.py` from backend/ and commit".
# The model can't run a build step, so the verify-repair model rounds can't fix it. Detect that exact
# instruction, run the command (SAFE: simple python/sh in the repo, no shell metachars), commit the
# regenerated file, and let the caller re-verify. Recovers endpoint/model items across any repo that
# uses this common "regenerate and commit" convention. Returns 0 if it regenerated + committed something.
try_regen(){  # $1 = verify log
  local vlog="$1" cmd dir rundir py
  cmd="$(grep -oE 're-?run [`'"'"'\"][^`'"'"'\"]+[`'"'"'\"]' "$vlog" 2>/dev/null | head -1 | sed -E 's/^re-?run [`'"'"'\"]//; s/[`'"'"'\"]$//')"
  [ -z "$cmd" ] && return 1
  case "$cmd" in *';'*|*'|'*|*'&'*|*'>'*|*'<'*|*'$('*|*'`'*|*'&&'*) return 1 ;; esac   # no shell injection
  case "$cmd" in python*|python3*|./*.sh|bash\ *|make\ *) : ;; *) return 1 ;; esac    # allowlist shapes
  dir="$(grep -oE 'from [A-Za-z0-9_./-]+/' "$vlog" 2>/dev/null | head -1 | sed -E 's/^from //; s#/$##')"
  rundir="$wt/${dir:-.}"; [ -d "$rundir" ] || rundir="$wt"
  # CRITICAL: the git WORKTREE has no .venv (gitignored), so a bare python3 lacks the repo's deps and the
  # regen script ImportErrors. Use the REPO's venv python ($rd) — run from the worktree dir so it imports
  # THIS item's new code, with the venv's dependencies. (This was why REGEN never passed on gitlark openapi.)
  case "$cmd" in python\ *|python3\ *)
    local vpy; vpy="$(find "$rd" -maxdepth 5 -path '*/.venv/bin/python' 2>/dev/null | head -1)"
    [ -x "$vpy" ] && py="$(cd "$(dirname "$vpy")" && pwd)/python" || py="python3"
    cmd="$py ${cmd#python* }" ;;
  esac
  say "verify wants a regenerated artifact — running: (cd ${dir:-.} && $cmd)"
  ( cd "$rundir" && timeout 120 bash -c "$cmd" ) >> "$vlog" 2>&1 || return 1
  git -C "$wt" add -A 2>/dev/null; ovn_unstage_abs_symlinks "$wt"
  git -C "$wt" diff --cached --quiet 2>/dev/null && return 1   # nothing actually regenerated
  git -C "$wt" -c user.email=22970726+markhint22@users.noreply.github.com -c user.name=shrike-fleet commit -q -m "chore($repo): regenerate stale artifact so verification passes" 2>/dev/null
  return 0
}

# ---- QA S4 (SHADOW ONLY, 2026-10-02): baseline-relative verdict logged NEXT TO the runner's real verdict ----
# Why: one pre-existing red test (e.g. the TAA stale-pricing tests, 2026-10-01) makes every staged step stage-unverified; qa/baseline_verify.py says
# whether THIS change added a NEW failing id. This only MEASURES it (state/qa_shadow/baseline.jsonl, one row per red run, pairing the baseline verdict
# with what the runner finally decided); the runner's verdict / exit code / pushes / output are unchanged - enforcing it is a separate, later decision.
# Two phases because every full_verify() call truncates the verify log: (1) right after the FIRST red verify, compare the log (writes
# <run>.baseline.json, NOT into verify.log: the repair loop greps that file); (2) after the repair flow, append the paired row with the real decision.
# Hard rules: runs in a SUBSHELL (set -u / any error cannot touch the runner), every external call bounded (5s), every failure swallowed and logged
# as UNVERIFIED to logs/qa_shadow.log + an UNVERIFIED row, no locks, no repo writes. Kill switch: OVN_BASELINE_SHADOW=off (or OVN_QA_BASELINE=off).
_QA_BL_PENDING=0
_qa_bl_log(){ echo "$(date '+%F %T') [$repo] baseline-shadow: $*" >> "$HOME/overnight-queue/logs/qa_shadow.log" 2>/dev/null; return 0; }
qa_baseline_first_red(){   # call right after the FIRST full_verify went red
  [ "${OVN_BASELINE_SHADOW:-on}" = off ] && return 0
  [ "${OVN_QA_BASELINE:-}" = off ] && return 0
  _QA_BL_PENDING=1
  (
    set +eu +o pipefail
    export PYTHONDONTWRITEBYTECODE=1 OVN_DIR="$HOME/overnight-queue"
    local qa="$OVN_DIR/qa" vlog="${SLOG%.jsonl}.verify.log" res="${SLOG%.jsonl}.baseline.json" chg py to
    rm -f "$res"
    py="$(command -v python3.12 || command -v python3)"
    if [ -f "$qa/qa_timeout.py" ] && [ -n "$py" ]; then to=("$py" "$qa/qa_timeout.py" 5)
    elif command -v timeout >/dev/null 2>&1; then to=(timeout 5)
    else _qa_bl_log "UNVERIFIED: no timeout tool"; exit 0; fi
    { [ -f "$qa/baseline_verify.py" ] && [ -n "$py" ] && [ -s "$vlog" ]; } || { _qa_bl_log "UNVERIFIED: baseline_verify.py, python or the verify log is missing"; exit 0; }
    chg="$(mktemp 2>/dev/null)" || exit 0
    git -C "$wt" diff --name-only origin/overnight/feature..HEAD 2>/dev/null | head -200 > "$chg"
    "${to[@]}" "$py" "$qa/baseline_verify.py" compare --repo "$repo" --failing-file "$vlog" --format verify-log --runner-failed \
      --changed-files-from "$chg" --worktree "$wt" --base-sha "$(git -C "$wt" rev-parse origin/overnight/feature 2>/dev/null)" --no-record \
      2>>"$OVN_DIR/logs/qa_shadow.log" | tail -1 > "$res"
    rm -f "$chg"
    if ! jq -e '.verdict' "$res" >/dev/null 2>&1; then rm -f "$res"; _qa_bl_log "UNVERIFIED: compare produced no verdict (crash/timeout/parse failure)"; fi
  ) >/dev/null 2>&1
  return 0
}
qa_baseline_record(){   # $1 = the runner's FINAL VERIFIED (0/1); call once, after the whole verify/regen/repair flow
  [ "$_QA_BL_PENDING" = 1 ] || return 0
  _QA_BL_PENDING=0
  (
    set +eu +o pipefail
    export PYTHONDONTWRITEBYTECODE=1 OVN_DIR="$HOME/overnight-queue"
    local qa="$OVN_DIR/qa" res="${SLOG%.jsonl}.baseline.json" py to dec row
    dec=not_verified; [ "$1" = 1 ] && dec=verified
    py="$(command -v python3.12 || command -v python3)"
    if [ -f "$qa/qa_timeout.py" ] && [ -n "$py" ]; then to=("$py" "$qa/qa_timeout.py" 5); elif command -v timeout >/dev/null 2>&1; then to=(timeout 5); else to=(); fi
    row=""
    if [ -n "$py" ] && [ -f "$qa/baseline_verify.py" ] && [ "${#to[@]}" -gt 0 ]; then
      row="$("${to[@]}" "$py" "$qa/baseline_verify.py" shadow-log --repo "$repo" --result-file "$res" --runner-decision "$dec" \
              --run "$(basename "${SLOG%.jsonl}")" --label first 2>>"$OVN_DIR/logs/qa_shadow.log" | tail -1)"
    fi
    # python path unusable (missing/crashed/timed out): still leave an UNVERIFIED row so the shadow data accounts for this red run
    if ! printf '%s' "$row" | jq -e '.verdict' >/dev/null 2>&1; then
      _qa_bl_log "UNVERIFIED: shadow-log produced no row; writing the fallback row"
      mkdir -p "$OVN_DIR/state/qa_shadow" 2>/dev/null
      jq -cn --arg repo "$repo" --arg run "$(basename "${SLOG%.jsonl}")" --arg dec "$dec" \
        '{ts:(now|strftime("%Y-%m-%dT%H:%M:%SZ")),gate:"baseline",kind:"staged_shadow",repo:$repo,run:$run,label:"first",verdict:"UNVERIFIED",mode:"shadow",
          summary:"baseline shadow hook error swallowed - runner unaffected",details:{},runner:{first:"not_verified",final:$dec},
          would_have_rescued:false,real_rescue:false}' >> "$OVN_DIR/state/qa_shadow/baseline.jsonl" 2>/dev/null
    fi
  ) >/dev/null 2>&1
  return 0
}

# ---- ALEMBIC AUTOGEN (2026-10-02): same deterministic hook run_overnight.sh runs after implement. A staged
# schema item (model step, then a "create migration" step) hits the identical wall: the 27B has no shell so it
# cannot run `alembic revision --autogenerate`, a model-only combined change fails test_migration_drift.py, and
# its hand-written migration invents a stale down_revision and forks the chain. Runs BEFORE the independent
# full_verify so a missing/forked migration is repaired (zero LLM) instead of burning repair rounds; the commit
# lands in the worktree so it is pushed only if verification passes and discarded with the worktree otherwise.
# The hook allowlists repos itself (default test-automation-agent + iptv_apps), refuses on anything doubtful,
# always exits 0 and leaves the tree untouched on refusal. OVN_ALEMBIC_AUTOGEN_DISABLE=1 disables.
if [ "$passed" -gt 0 ] && [ -x scripts/ovn_alembic_autogen.sh ]; then
  # fleet identity via env (every other commit in this file passes -c user.*; the hook uses plain `git commit`)
  _ag_out="$(OVN_ALEMBIC_AUTOGEN_NAME="$repo" OVN_ALEMBIC_AUTOGEN_VENV_ROOT="$(cd "$rd" && pwd)" \
    GIT_AUTHOR_NAME=shrike-fleet GIT_COMMITTER_NAME=shrike-fleet \
    GIT_AUTHOR_EMAIL=22970726+markhint22@users.noreply.github.com GIT_COMMITTER_EMAIL=22970726+markhint22@users.noreply.github.com \
    bash scripts/ovn_alembic_autogen.sh "$wt" "$(git -C "$wt" rev-parse origin/overnight/feature 2>/dev/null)" "$(git -C "$wt" rev-parse HEAD)" 2>>"$SLOG")"
  [ -n "$_ag_out" ] && { say "$_ag_out"; jlog "$(jq -nc --arg r "$RUNID" --arg o "$_ag_out" '{run:$r,event:"alembic_autogen",out:$o}')"; }
fi

# 2026-10-10 (harness R10, BX-09): "verified" must mean "a landed change was verified". When the worktree has NO commit ahead of origin/overnight/feature nothing was edited (every step
# BLOCKED / no-edit): the full verify would only re-run the baseline tree and report "the combined result is real" (xlite 01:36 and 01:52 CDT, ~700-900s each, ending no-op(stage-unverified)).
# Skip the verify, count 0 landed steps and say no-edit. OVN_STAGE_NOEDIT_GUARD=off disables.
STAGE_NOEDIT=0
if [ "$passed" -gt 0 ] && [ "${OVN_STAGE_NOEDIT_GUARD:-on}" != off ]; then
  _ahead="$(git -C "$wt" rev-list --count origin/overnight/feature..HEAD 2>/dev/null || echo 0)"
  if [ "${_ahead:-0}" = 0 ]; then
    STAGE_NOEDIT=1
    say "no-edit: no step produced a commit ahead of origin/overnight/feature (counted $passed landed) - skipping the independent full-verify, steps landed=0"
    jlog "$(jq -nc --arg r "$RUNID" --argjson p "$passed" '{run:$r,event:"no_edit",claimed:$p}')"
    passed=0
  fi
fi

VERIFIED=0
if [ "$passed" -gt 0 ]; then
  if full_verify; then VERIFIED=1; say "independent full-verify: PASSED — the combined result is real"
  else
    qa_baseline_first_red   # SHADOW only (QA S4): never alters control flow, always returns 0
    # STALE-ARTIFACT REGEN (2026-09-08): before the model repair rounds, try the cheap mechanical fix —
    # if verify failed because a generated file is stale ("re-run `X` and commit"), run X + re-verify.
    if [ "${OVN_VERIFY_REGEN:-1}" = 1 ] && try_regen "${SLOG%.jsonl}.verify.log"; then
      if full_verify; then VERIFIED=1; passed="$NSTEPS"; say "REGEN PASSED — verified after regenerating the stale artifact (no model needed)"; fi
    fi
  fi
  if [ "$VERIFIED" = 0 ]; then
    # VERIFY-REPAIR LOOP (2026-09-08): most steps LANDED but the COMBINED change failed final verification.
    # Instead of discarding all that mostly-complete work and reopening the item to redo from scratch,
    # feed the EXACT failure back and take up to OVN_VERIFY_REPAIR_ROUNDS corrective passes — fixing the
    # SOURCE and/or the TEST, re-verifying each round. Recovers: buggy self-written tests (wrong value /
    # DB-roundtrip tz), vacuous tests (don't exercise the code), leftover stubs, and sibling-test breaks.
    # The quality guards + full suite still gate the result, so a repair can't cheat past them. Set
    # OVN_VERIFY_REPAIR_ROUNDS=0 to disable (fall straight back to reopen).
    local_vlog="${SLOG%.jsonl}.verify.log"
    REPAIR_ROUNDS="${OVN_VERIFY_REPAIR_ROUNDS:-2}"
    # cap at 12 files so the repair stays focused on THIS item's change (a stale worktree base once made
    # the branch delta 42 files, diluting the repair context) — prefer the most-recently-touched files.
    changed_files="$(git -C "$wt" diff --name-only origin/overnight/feature..HEAD 2>/dev/null | grep -vE 'OVERNIGHT_PROGRESS|OVERNIGHT_DONE' | head -12)"
    _rr=0
    while [ "$VERIFIED" = 0 ] && [ "$_rr" -lt "$REPAIR_ROUNDS" ] && [ -n "$changed_files" ]; do
      _rr=$((_rr+1))
      # the concrete failure: a failed test + assertion, a quality-guard verdict, or an import/parse error
      reason="$(grep -iE 'QUALITY FAIL|FAILED |assert|Error|Parse Error|Import|not declared|tzinfo|does not exercise' "$local_vlog" 2>/dev/null | grep -viE 'passed|0 error' | tail -12)"
      [ -z "$reason" ] && reason="final verification failed (see the run's full test output)."
      nchg=$(printf '%s' "$changed_files" | wc -w | tr -d ' ')
      say "verify FAILED — repair round $_rr/$REPAIR_ROUNDS (recovering $nchg changed file(s))"
      repair_fargs=(); for cf in $changed_files; do [ -f "$wt/$cf" ] && repair_fargs+=(--file "$cf"); done
      rmsg="Your change LANDED but FAILED final verification. Fix it so verification passes — edit the SOURCE and/or the TEST, whichever is actually wrong; do NOT revert the working parts, make the minimal fix. Likely causes: (a) your new test asserts a guessed/wrong value or a tz/precision a DB round-trip drops (SQLite naive datetimes) — assert real behavior/PROPERTIES instead; (b) the test never calls the code you changed — import and exercise the real symbol, or drive an endpoint via TestClient; (c) a stub/placeholder remains — implement it for real; (d) the change broke a sibling test — fix the source; (e) a test this change promised is missing or red — FIX it, NEVER delete, empty, skip or xfail the test the change added (a repair that removes it is rejected and the item is not credited). THE EXACT FAILURE:
$reason"
      ( cd "$wt" && timeout "$STEP_TIMEOUT" aider --yes-always --no-check-update --no-auto-commits --edit-format udiff \
          --model "openai/$MODEL" --openai-api-base "$LITELLM/v1" --openai-api-key "$LKEY" \
          --model-metadata-file "$HOME/overnight-queue/model-metadata.json" --map-tokens 2048 \
          --auto-test --test-cmd "bash $HOME/overnight-queue/scripts/ovn_autotest.sh $wt" \
          ${repair_fargs[@]+"${repair_fargs[@]}"} --message "$rmsg" ) >> "$local_vlog" 2>&1
      if full_verify; then
        VERIFIED=1; passed="$NSTEPS"
        git -C "$wt" add -A && ovn_unstage_abs_symlinks "$wt" && git -C "$wt" -c user.email=22970726+markhint22@users.noreply.github.com -c user.name=shrike-fleet commit -q -m "fix($repo): repair staged item to pass verification (round $_rr)" 2>/dev/null
        say "REPAIR PASSED (round $_rr) — verified after fixing the flagged failure"
      fi
    done
    [ "$VERIFIED" = 0 ] && { say "independent full-verify: FAILED — NOT pushing, re-opening (see ${SLOG%.jsonl}.verify.log)"; passed=0; }
  fi
fi
# ---- ITEM VERIFY: red before, green after (2026-10-13; xlite F3 + iptv F2). The item was ticked on the full suite alone: its OWN VERIFY was never run after the change (iptv: the test it named had been
# deleted) and never required to have been RED before (xlite: a grep on a file that did not exist went green once a step created it). Run it on the final tree through the same shadow_check every
# other credit path uses and compare with the pristine-tree verdict taken before the first step. OVN_STAGE_ITEM_VERIFY=off|shadow|enforce (default SHADOW: the verdict is journalled as an
# item_verify event, nothing changes). ENFORCE: an item whose VERIFY is RED after the change, or was already GREEN before it, is NOT ticked - its code is still pushed (the full suite was green) and the
# line is parked '[AUTO-SKIP staged ... item VERIFY did not confirm ...]' for review. TIMEOUT / UNRUNNABLE / no clause on either side is no evidence: credited as before.
STAGE_NOCREDIT=0; STAGE_NOCREDIT_WHY=""
if [ "$VERIFIED" = 1 ] && [ "${_iv_mode:-off}" != off ] && [ "${STAGE_MISTARGET_ITEM:-0}" = 0 ]; then
  case "${STAGE_IV_PRE%%|*}" in
    PASS|FAIL)
      _ivpost="$(OVN_STAGE_REPO="$repo" OVN_STAGE_REPO_DIR="$rd" stage_item_verify_run "$wt" "$item")"
      _ivdec="$(stage_item_verify_decision "$STAGE_IV_PRE" "$_ivpost")"
      say "item VERIFY (${_iv_mode}): pre=${STAGE_IV_PRE%%|*} post=${_ivpost%%|*} -> ${_ivdec}"
      jlog "$(jq -nc --arg r "$RUNID" --arg pre "${STAGE_IV_PRE%%|*}" --arg post "${_ivpost%%|*}" --arg why "${_ivpost#*|}" --arg dec "$_ivdec" --arg m "$_iv_mode" '{run:$r,event:"item_verify",mode:$m,pre:$pre,post:$post,post_why:$why,decision:$dec}')"
      if [ "${_ivdec%%:*}" = refuse ] && [ "$_iv_mode" = enforce ]; then STAGE_NOCREDIT=1; STAGE_NOCREDIT_WHY="${_ivdec#refuse:}"; fi
      # 2026-10-18: a text-probe VERIFY (grep/test) that is RED after the change is enforced even in shadow mode (kill switch OVN_STAGE_ITEM_VERIFY_TEXT=off). See stage_item_verify_textonly.
      if [ "${_ivdec%%:*}" = refuse ] && [ "${_ivpost%%|*}" = FAIL ] && [ "${OVN_STAGE_ITEM_VERIFY_TEXT:-enforce}" = enforce ] && stage_item_verify_textonly "$item"; then
        STAGE_NOCREDIT=1; STAGE_NOCREDIT_WHY="${_ivdec#refuse:} (text-probe VERIFY, enforced)"; jlog "$(jq -nc --arg r "$RUNID" '{run:$r,event:"item_verify_text_enforced"}')"
      fi ;;
    *) jlog "$(jq -nc --arg r "$RUNID" --arg pre "${STAGE_IV_PRE%%|*}" --arg m "$_iv_mode" '{run:$r,event:"item_verify",mode:$m,pre:$pre,post:"not-run",decision:"no-evidence"}')" ;;
  esac
fi
# 2026-10-18 (iptv overnight audit): tell the caller (run_overnight.sh -> task_log -> ovn_landed_uncredited) that verified code is about to be pushed WITHOUT ticking the item, so the
# outcome row is landed-uncredited (neutral) instead of landed/good. 9 iptv rows were counted as good landings although the item's own VERIFY was RED and the item stayed [ ].
[ "${STAGE_NOCREDIT:-0}" = 1 ] && printf '%s\n' "--- stage-credit: REFUSED - ${STAGE_NOCREDIT_WHY:-item VERIFY did not confirm the change} ---"
qa_baseline_record "$VERIFIED"   # SHADOW only (QA S4): one paired row (baseline verdict vs the runner's final decision); no-op unless the first verify was red
jlog "$(jq -nc --arg r "$RUNID" --argjson v "$VERIFIED" '{run:$r,event:"verify",verified:($v==1)}')"

# ---- push ONLY when independently verified ----
ncommits=0
_push_attempted=0   # 2026-10-10 (BX-09): "push failed" may only be claimed after a push was actually attempted
if [ "$VERIFIED" = 1 ]; then
  # 2026-09-09 FIX: ncommits used to be set from the PRE-push rev-list count and never
  # cleared on push failure, so the jsonl summary's commits_pushed could read >0 even when
  # the push raced and nothing actually reached origin ("commits are in the worktree branch
  # only" - i.e. lost once the worktree is cleaned up). Never observed in practice (0 hits
  # in state/stage_runs/*.log so far) but it's exactly the kind of silent-success gap that
  # inflated the T3+ land rate before, so fix it before it becomes a real discrepancy: only
  # report commits_pushed>0 when the push actually succeeded.
  local_ncommits="$(git -C "$wt" rev-list --count origin/overnight/feature..HEAD 2>/dev/null || echo 0)"
  if [ "${local_ncommits:-0}" -gt 0 ]; then
    _push_attempted=1
    if git -C "$wt" push -q origin HEAD:overnight/feature 2>/dev/null || { git -C "$wt" pull -q --rebase origin overnight/feature && git -C "$wt" push -q origin HEAD:overnight/feature; }; then
      ncommits="$local_ncommits"
      say "pushed $ncommits verified commit(s) to overnight/feature"
    else say "push FAILED (fleet racing) — commits are in the worktree branch only, NOT counted as pushed"; fi
  fi
fi

# ---- mark the item done ONLY if independently verified AND actually pushed (else leave OPEN
# for a clean re-attempt). 2026-09-18 FIX: this used to gate only on $VERIFIED/$passed, so a
# push-race loss ("push FAILED (fleet racing)" above, ncommits left at 0) still fell through to
# this branch and permanently checked the item off in OVERNIGHT_PROGRESS.md even though the
# verified code never reached origin/overnight/feature - confirmed live (billwatch
# BillWatchAPIClientTests.swift, marked [x] DONE while origin/overnight/feature still had the
# un-removed FlockWorks test methods). Require ncommits>0 too, so a lost-to-a-race item is left
# OPEN for a clean re-attempt instead of being silently and permanently marked done. ----
if [ "$VERIFIED" = 1 ] && [ "$passed" -gt 0 ] && [ "${ncommits:-0}" -gt 0 ] && [ -z "$item_arg" ]; then   # only auto-picked items live in the queue
  ./queue.sh hold "$repo" >/dev/null 2>&1
  ( cd "$rd" && git fetch -q origin overnight/feature && git reset -q --hard origin/overnight/feature ) 2>/dev/null
  _is_bug=0; ovn_is_manual_bug_text "$item" && _is_bug=1
  OVN_F="$rd/OVERNIGHT_PROGRESS.md" OVN_ITEM="$item" OVN_P="$passed" OVN_N="$NSTEPS" OVN_BUG="$_is_bug" OVN_PARTIAL="${STAGE_PARTIAL:-0}" OVN_NOCREDIT="${STAGE_NOCREDIT:-0}" OVN_NOCREDIT_WHY="${STAGE_NOCREDIT_WHY//[\]\[]/}" python3 - <<'PY'
import os
f=os.environ["OVN_F"]; item=os.environ["OVN_ITEM"]; p=int(os.environ["OVN_P"]); n=int(os.environ["OVN_N"])
nocredit=os.environ.get("OVN_NOCREDIT")=="1"   # 2026-10-13: item VERIFY did not confirm the change (enforce mode only): never check the item off
# 2026-10-10 (BX-09): a step that landed only some of its re-decomposed sub-steps (BLOCKED ones are not landed) must not let the item be checked off as fully done
partial=int(os.environ.get("OVN_PARTIAL") or 0)
# 2026-10-18 FIX (xlite audit): the line to check off / escalate is the EXACT picked item, not the first line that merely contains item[:55]. Two sibling items often share a
# 55-char prefix (xlite "Delete the function definition `generate_intent`..." vs "`intent_label`..."): the first-substring match ticked/escalated the WRONG sibling, so the
# executed item stayed open and re-ran as no-op(stage-unverified) x3 while an item whose code never landed was credited. Ambiguous (no exact line, tied prefix) => touch nothing.
def pick_line(lines, item):
    exact=[i for i,l in enumerate(lines) if l.startswith("- [ ] ") and l[6:]==item]
    if exact: return exact[0]
    key=item[:55]
    cand=[i for i,l in enumerate(lines) if l.startswith("- [ ] ") and key and key in l]
    if len(cand)<=1: return cand[0] if cand else None
    cps={i:len(os.path.commonprefix([lines[i][6:],item])) for i in cand}
    top=max(cps.values()); tops=[i for i in cand if cps[i]==top]
    return tops[0] if len(tops)==1 and top>=55 else None
lines=open(f,encoding="utf-8").read().split("\n"); pick=pick_line(lines,item)
for i,ln in enumerate(lines):
    if i==pick:
        if p>=n and partial==0 and not nocredit:  # fully done -> check it off
            lines[i]=ln.replace("- [ ] ","- [x] ",1)+f"  <!-- staged {p}/{n} DONE -->"
        elif os.environ.get("OVN_BUG") == "1":
            pass  # a manual bug is NEVER AUTO-SKIPped (2026-10-02): stage_bug_attempt below counts the attempt and escalates at the cap
        elif nocredit and "AUTO-SKIP staged" not in ln:
            lines[i]=ln.replace("- [ ] ","- [ ] [AUTO-SKIP staged {}/{} — the verified code landed but the item's own VERIFY did not confirm it ({}); recover/review] ".format(p,n,os.environ.get("OVN_NOCREDIT_WHY") or "item VERIFY"),1)
        elif "AUTO-SKIP staged" not in ln:  # partial -> park the remainder, but only tag it ONCE -
            # blindly re-prepending on every retry stacked duplicate tags without bound (found live:
            # 4 on a test-automation-agent item, 15 on a shrike-monitor item, 2026-09-22).
            if p>=n: lines[i]=ln.replace("- [ ] ","- [ ] [AUTO-SKIP staged {}/{} — {} step(s) landed only part of their re-decomposed sub-steps (BLOCKED sub-steps are not landed); recover/review] ".format(p,n,partial),1)
            else: lines[i]=ln.replace("- [ ] ","- [ ] [AUTO-SKIP staged {}/{} — {} step(s) blocked; recover/review] ".format(p,n,n-p),1)
        open(f,"w",encoding="utf-8").write("\n".join(lines)); break
PY
  [ "${passed:-0}" -gt 0 ] && rm -f "state/item_fails/stage-${repo}.$(ovn_item_hash "$item").zerocount" "state/item_fails/stage-${repo}.$(ovn_item_hash "$item").priorfail" "state/item_fails/stage-${repo}.$(ovn_item_hash "$item").lastsig" "state/item_fails/stage-${repo}.$(ovn_item_hash "$item").scopeseen" "state/item_fails/stage-${repo}.$(ovn_item_hash "$item").scopeext"
  if [ "$_is_bug" = 1 ]; then
    if [ "$passed" -ge "$NSTEPS" ] && [ "${STAGE_PARTIAL:-0}" = 0 ] && [ "${STAGE_NOCREDIT:-0}" = 0 ]; then rm -f "state/item_fails/stage-${repo}.$(ovn_item_hash "$item").bugcount" ${_bg_plan_f:+"$_bg_plan_f"}
    else stage_bug_attempt "staged ${passed} of ${NSTEPS} landed"; fi
  fi
  ( cd "$rd" && git diff --quiet -- OVERNIGHT_PROGRESS.md || {
      git add OVERNIGHT_PROGRESS.md
      git -c user.email=22970726+markhint22@users.noreply.github.com -c user.name=shrike-fleet commit -q -m "chore(queue): mark staged T$tier item ($passed/$NSTEPS) so it isn't re-run"
      git push -q origin overnight/feature 2>/dev/null || { git pull -q --rebase origin overnight/feature && git push -q origin overnight/feature; }; } )
  ./queue.sh release "$repo" >/dev/null 2>&1
elif [ "$VERIFIED" = 1 ] && [ "$passed" -gt 0 ] && [ "${ncommits:-0}" -eq 0 ] && [ -z "$item_arg" ]; then
  # Verified and would have landed, but the push itself lost a fleet race - leave the item OPEN
  # (no OVERNIGHT_PROGRESS.md edit at all) so the next cycle gets a completely clean re-attempt
  # rather than silently losing this work forever.
  if [ "$_push_attempted" = 1 ]; then
    say "leaving item OPEN for a clean re-attempt (verified but push failed - not marking done)"
  else
    say "leaving item OPEN: verified, but there was nothing to push (no commit ahead of origin/overnight/feature) - not marking done"
  fi
elif [ "$passed" -eq 0 ] && [ -z "$item_arg" ]; then
  # ESCALATE: the staged pipeline (retries + re-decomp + target-fn context) landed NOTHING — this is
  # genuinely beyond the 27B (usually a wire-into-a-complex-existing-function). Stop looping the fleet
  # on it: tag it for Claude so the Mac bridge harvests it to the Claude queue.
  ./queue.sh hold "$repo" >/dev/null 2>&1
  ( cd "$rd" && git fetch -q origin overnight/feature && git reset -q --hard origin/overnight/feature ) 2>/dev/null
  if ovn_is_manual_bug_text "$item"; then
    # 2026-10-02: never AUTO-SKIP a manual bug - count the attempt, escalate at the cap (see stage_bug_attempt)
    stage_bug_attempt "staged landed 0 of ${NSTEPS}"
    ./queue.sh release "$repo" >/dev/null 2>&1
    say "manual bug: staged pipeline landed 0/$NSTEPS - attempt counted, NOT AUTO-SKIPped"
  else
  # 2026-10-07 RETRY BUDGET: ONE staged run that landed nothing used to route the whole item to Claude at once (105 open [CLAUDE] lines, ~60% of them
  # noise or already done). A zero-landing run now keeps the item OPEN for OVN_STAGE_ZERO_CAP (default 3) attempts - the reason of the last failure is
  # recorded and fed into the next decomposition - and only the cap routes it to Claude. OVN_STAGE_ZERO_CAP=1 = the old immediate escalation.
  _zh="$(ovn_item_hash "$item")"; _zf="state/item_fails/stage-${repo}.${_zh}.zerocount"; mkdir -p state/item_fails 2>/dev/null
  _zcap="${OVN_STAGE_ZERO_CAP:-3}"; case "$_zcap" in ''|*[!0-9]*|0) _zcap=3;; esac
  [ "${STAGE_MISTARGET_ITEM:-0}" = 1 ] && _zcap=1   # 2026-10-13 (xlite F3): a mis-targeted item can never land; retrying only re-plans the same wrong path - escalate at once
  _zc=$(( $(cat "$_zf" 2>/dev/null || echo 0) + 1 )); printf '%s' "$_zc" > "$_zf"
  jlog "$(jq -nc --arg r "$RUNID" --argjson c "$_zc" --argjson m "$_zcap" '{run:$r,event:"zero_landing_attempt",attempt:$c,cap:$m}')"
  # 2026-10-13 (N4 Part 2) SAME-SIGNATURE STOP: this run's failure identity (stage_fail_signature) is compared with the previous zero-landing run's (state/item_fails/...lastsig). An identical
  # failure means the retry would burn another ~200k tokens to fail exactly the same way: treat the budget as spent and take the existing escalate branch below.
  # An empty signature (no recognisable evidence) never stops anything AND clears the recorded one (a stale signature must not match a later, non-adjacent run).
  # OVN_STAGE_SAME_SIG_STOP=on|shadow|off (default SHADOW: replaying 932 zero-landing box runs, 7 of the 67 same-signature repeats landed on the very next run (~10%), so this is an enforcement
  # change, not a pure bug fix - read the same_signature_stop mode:shadow events for a cycle, then flip to on; shadow logs the would-stop and retries as before; off disables; the signature is always recorded).
  _zssm="${OVN_STAGE_SAME_SIG_STOP:-shadow}"
  _zssm="$(printf '%s' "$_zssm" | tr 'A-Z' 'a-z')"; case "$_zssm" in 0|false|no) _zssm=off;; esac   # the kill switch is case-insensitive and accepts 0/false/no (previously OFF/0/false silently ENFORCED)
  _zvl="${SLOG%.jsonl}.verify.log"
  _zsf="state/item_fails/stage-${repo}.${_zh}.lastsig"; _zsig="$(stage_fail_signature "$_zvl" "$SLOG" 2>/dev/null)"; _zsame=0
  if [ -n "$_zsig" ] && [ -s "$_zsf" ] && [ "$(cat "$_zsf" 2>/dev/null)" = "$_zsig" ]; then
    # a scope extension granted during THIS run (Part 3, OVN_STAGE_SCOPE_LEARN=on) changes what the next attempt can do, so the next failure is not "the same" yet
    if [ "$_zssm" = shadow ] && [ "${STAGE_SCOPE_EXTENDED:-0}" != 1 ]; then
      say "same failure signature as the previous staged run (${_zsig}) - SHADOW: would escalate now instead of attempt $((_zc+1))/${_zcap}; retrying as before"
      jlog "$(jq -nc --arg r "$RUNID" --arg s "$_zsig" --argjson c "$_zc" '{run:$r,event:"same_signature_stop",mode:"shadow",signature:$s,attempt:$c}')"
    elif [ "$_zssm" != off ] && [ "$_zssm" != shadow ] && [ "${STAGE_SCOPE_EXTENDED:-0}" != 1 ]; then
      _zsame=1
      say "same failure signature as the previous staged run (${_zsig}): another retry would repeat it - escalating now instead of attempt $((_zc+1))/${_zcap}"
      jlog "$(jq -nc --arg r "$RUNID" --arg s "$_zsig" --argjson c "$_zc" '{run:$r,event:"same_signature_stop",mode:"on",signature:$s,attempt:$c}')"
    fi
  fi
  if [ -n "$_zsig" ]; then printf '%s' "$_zsig" > "$_zsf"; else rm -f "$_zsf"; fi
  if [ "$_zc" -lt "$_zcap" ] && [ "$_zsame" = 0 ]; then
    _zerr="$(grep -m1 -E '^e: |Redeclaration|Unresolved reference|FAILED |QUALITY FAIL|SEMANTIC FAIL|error:|Error:' "$_zvl" 2>/dev/null | sed -E 's#file://[^ ]*/##; s#://[^/ ]*@#://***@#g' | cut -c1-200)"
    [ -n "$_zerr" ] || _zerr="$(jq -r 'select(.verdict=="fail") | .excerpt // empty' "$SLOG" 2>/dev/null | tail -1 | cut -c1-200)"
    [ -n "$_zerr" ] || _zerr="the staged run landed 0 of ${NSTEPS} steps (no error line captured)"
    # 2026-10-13 (N4 Part 2): the first error line stays the header (older readers/tests grep it); the structured evidence (failing test ids + first assertion, QUALITY/SEMANTIC lines,
    # undeclared files, blocked-step reasons) follows and is what the next decomposition AND every step prompt of the retry are told.
    _zblk="$(stage_priorfail_block "$_zvl" "$SLOG" 2>/dev/null)"
    printf 'attempt %s of %s: %s%s' "$_zc" "$_zcap" "$_zerr" "${_zblk:+$'\n'$_zblk}" > "state/item_fails/stage-${repo}.${_zh}.priorfail"
    ./queue.sh release "$repo" >/dev/null 2>&1
    say "staged pipeline landed 0/$NSTEPS - attempt ${_zc}/${_zcap}: item stays OPEN for another try (NOT routed to Claude yet)"
  else
  rm -f "$_zf" "state/item_fails/stage-${repo}.${_zh}.priorfail" "state/item_fails/stage-${repo}.${_zh}.lastsig" "state/item_fails/stage-${repo}.${_zh}.scopeseen" "state/item_fails/stage-${repo}.${_zh}.scopeext"
  OVN_F="$rd/OVERNIGHT_PROGRESS.md" OVN_ITEM="$item" python3 - <<'PY'
import os
f=os.environ["OVN_F"]; item=os.environ["OVN_ITEM"]
# 2026-10-18 FIX (xlite audit): the line to check off / escalate is the EXACT picked item, not the first line that merely contains item[:55]. Two sibling items often share a
# 55-char prefix (xlite "Delete the function definition `generate_intent`..." vs "`intent_label`..."): the first-substring match ticked/escalated the WRONG sibling, so the
# executed item stayed open and re-ran as no-op(stage-unverified) x3 while an item whose code never landed was credited. Ambiguous (no exact line, tied prefix) => touch nothing.
def pick_line(lines, item):
    exact=[i for i,l in enumerate(lines) if l.startswith("- [ ] ") and l[6:]==item]
    if exact: return exact[0]
    key=item[:55]
    cand=[i for i,l in enumerate(lines) if l.startswith("- [ ] ") and key and key in l]
    if len(cand)<=1: return cand[0] if cand else None
    cps={i:len(os.path.commonprefix([lines[i][6:],item])) for i in cand}
    top=max(cps.values()); tops=[i for i in cand if cps[i]==top]
    return tops[0] if len(tops)==1 and top>=55 else None
lines=open(f,encoding="utf-8").read().split("\n"); pick=pick_line(lines,item)
for i,ln in enumerate(lines):
    if i==pick and "[CLAUDE]" not in ln and "AUTO-SKIP staged: 27B could not land this" not in ln:
        lines[i]=ln.replace("- [ ] ","- [ ] [AUTO-SKIP staged: 27B could not land this (beyond it) — route to CLAUDE] ",1)
        open(f,"w",encoding="utf-8").write("\n".join(lines)); break
PY
  ( cd "$rd" && git diff --quiet -- OVERNIGHT_PROGRESS.md || {
      git add OVERNIGHT_PROGRESS.md
      git -c user.email=22970726+markhint22@users.noreply.github.com -c user.name=shrike-fleet commit -q -m "chore(queue): escalate staged T$tier item to Claude (27B couldn't land it)"
      git push -q origin overnight/feature 2>/dev/null || { git pull -q --rebase origin overnight/feature && git push -q origin overnight/feature; }; } )
  ./queue.sh release "$repo" >/dev/null 2>&1
  if [ "${_zsame:-0}" = 1 ]; then say "escalated to Claude (staged pipeline landed 0/$NSTEPS - the same failure twice in a row (attempt ${_zc}/${_zcap}), beyond the 27B)"
  else say "escalated to Claude (staged pipeline landed 0/$NSTEPS - ${_zcap} attempts, beyond the 27B)"; fi
  fi
  fi
fi

pct=$(( NSTEPS>0 ? 100*passed/NSTEPS : 0 ))
say "DONE: $passed/$NSTEPS steps landed (${pct}%) for T$tier item. log: $SLOG"
jlog "$(jq -nc --arg r "$RUNID" --argjson p "$passed" --argjson n "$NSTEPS" --argjson t "$tier" --argjson vf "$VERIFIED" '{run:$r,event:"summary",tier:$t,passed:$p,total:$n,verified:($vf==1),commits_pushed:'"${ncommits:-0}"'}')"

# ---- UNVERIFIED RUN -> OUTCOME ROW (2026-10-02, harness Y4) ----------------------------------------------------------------------------
# A staged run that ends unverified (0 of N steps pushed, ~15 min of GPU: iptv Android run 215550, 21:55Z) wrote NO row to state/outcomes.jsonl, so every
# pass-rate dashboard simply never saw it. One row per such run: status "no-op(stage-unverified) stage(runner)" (the same prefix the inline caller uses,
# so class/severity bucket as a real thrown-away attempt), fail_reason = the first error line of the verify log, plus repo / feat_tag / duration.
# Not emitted when run_overnight.sh invoked us inline (OVN_STAGE_OUTCOME_BY_CALLER=1): it records its own row for that run, and a second one would
# double count. Never fatal; OVN_STAGE_UNVERIFIED_ROW=off disables. (The item itself is already parked/escalated by the branches above.)
# ovn_scrub_text: stdin -> stdout with credentials removed (URL user:pass@, Bearer, key=value secrets, sk-/ghp_ tokens, JWTs, long hex/base64 blobs).
# Reuses the baseline gate's redact() (qa/baseline_verify.py) under a hard 5s cap - importing a qa module must never be able to stall the runner (a hung or
# crashing import, a missing qa/ dir, python or `timeout` all fall through to the sed scrubber below, which covers the same credential shapes).
ovn_scrub_text(){
  local in out
  in="$(cat)"
  if command -v timeout >/dev/null 2>&1 && [ -f qa/baseline_verify.py ] \
     && out="$(printf '%s' "$in" | timeout 5 python3 -c 'import sys; sys.path.insert(0,"qa"); import baseline_verify as b; sys.stdout.write(b.redact(sys.stdin.buffer.read().decode("utf-8","replace")))' 2>/dev/null)"; then
    printf '%s' "$out"; return 0
  fi
  printf '%s' "$in" | sed -E 's#(://[^/ :@]*:)[^@/ ]+@#\1***@#g; s#([Bb]earer )[A-Za-z0-9._~+/=-]{8,}#\1***#g; s#((password|passwd|secret|token|api[_-]?key|authorization)[A-Za-z_]{0,6}[ ]*[=:][ ]*["'"'"']?)[A-Za-z0-9+/=_.~-]{6,}#\1***#Ig; s#\b(sk|pk|ghp|gho|ghs|xox[abp])[-_][A-Za-z0-9_-]{16,}#***#g; s#[A-Za-z0-9+/=]{32,}#***#g'
}
emit_unverified_outcome(){
  [ "${OVN_STAGE_UNVERIFIED_ROW:-on}" = off ] && return 0
  [ "${OVN_STAGE_OUTCOME_BY_CALLER:-0}" = 1 ] && return 0
  [ "${VERIFIED:-0}" = 1 ] && return 0
  local vlog="${SLOG%.jsonl}.verify.log" fr detail ih ft cat first_path tsent trecv nat now dur ust="no-op(stage-unverified) stage(runner)" cf
  # fail_reason is a BOUNDED TAG (consumers Counter() it: ovn_t3_report.sh, ovn_godot_report.sh, ovn_failure_triage.py); the free-text excerpt goes in
  # the separate, scrubbed + truncated "detail" field (verify output can carry connection strings / tokens).
  cf="$vlog"; [ -f "$cf" ] || cf="$SLOG"
  fr="$(bash ovn_classify_fail.sh "$cf" "$ust" 2>/dev/null | head -1 | tr -cd 'a-z0-9-')"
  [ -n "$fr" ] && [ "$fr" != unknown ] || fr="stage-unverified"
  [ "${STAGE_NOEDIT:-0}" = 1 ] && fr="no-edit"   # 2026-10-10 (BX-09): the run produced no commit at all (bounded tag, same vocabulary as ovn_classify_fail.sh)
  detail="$(grep -m1 -iE 'FAILED |QUALITY FAIL|SEMANTIC FAIL|Error|error:|assert' "$vlog" 2>/dev/null | tr -d '"\\' | tr '\n\r\t' '   ' | tr -s ' ' | cut -c1-400)"
  [ -z "$detail" ] && detail="no step verified (${passed:-0}/${NSTEPS:-0} steps landed; no verify log)"
  detail="$(printf '%s' "$detail" | ovn_scrub_text | cut -c1-160)"
  ih=""; command -v ovn_item_hash >/dev/null 2>&1 && ih="$(ovn_item_hash "$item")"
  ft="$(printf '%s' "$item" | grep -oE '\[feat:[^]]+\]' | head -1 | tr -d '[]' | sed 's/^feat://' | tr -d '"' )"
  first_path="$(printf '%s' "$item" | grep -oE '[A-Za-z0-9_./-]+\.[A-Za-z0-9]{1,8}' | grep -vE '\.md$' | head -1)"
  case "$first_path" in *.gd) cat=godot;; *.vue) cat=vue;; *.ts|*.tsx) cat=typescript;; *.py) cat=python;; *) cat=other;; esac
  tsent="$(jq -s '[.[].tokens_sent // 0] | add // 0' "$SLOG" 2>/dev/null)"; trecv="$(jq -s '[.[].tokens_recv // 0] | add // 0' "$SLOG" 2>/dev/null)"
  nat="$(grep -c '"verdict":"\(pass\|fail\)"' "$SLOG" 2>/dev/null)"; [ "${nat:-0}" -ge 1 ] 2>/dev/null || nat=1
  now="$(date +%s)"; dur=$(( now - ${_ST0:-$now} ))
  # 2026-10-18 (D4): commit accounting, same additive fields as run_overnight.sh record_outcome (head_after = the stage worktree's HEAD; commits = what the run added on top of its base)
  local hb ha cm
  hb="$(printf '%s' "${_ST_H0:-}" | tr -cd '0-9a-fA-F')"; ha=""; [ -n "${wt:-}" ] && [ -d "$wt" ] && ha="$(git -C "$wt" rev-parse -q --verify HEAD 2>/dev/null)"
  cm='[]'; if declare -F ovn_oa_commits >/dev/null 2>&1 && [ -n "$hb" ] && [ -n "$ha" ]; then cm="$(ovn_oa_commits "$wt" "$hb" "$ha" 2>/dev/null)"; [ -n "$cm" ] || cm='[]'; fi
  jq -nc --arg ts "$(date -u +%FT%TZ)" --arg repo "$repo" --arg id "ongoing-${repo//_/-}" --argjson tier "${tier:-3}" --arg cat "$cat" \
    --argjson att "$nat" --arg fr "$fr" --arg detail "$detail" --argjson ts_ "${tsent:-0}" --argjson tr_ "${trecv:-0}" --argjson dur "$dur" --arg ih "$ih" --arg ft "$ft" --arg run "$RUNID" --arg ust "$ust" \
    --argjson cm "$cm" --arg hb "$hb" --arg ha "$ha" \
    '{ts:$ts,repo:$repo,id:$id,type:"aider_fix",tier:($tier|tostring),category:$cat,class:"noop",severity:"bad",attempt:$att,attempts:$att,bestn_stop:"",
      fail_reason:$fr,detail:$detail,status:$ust,tokens_sent:$ts_,tokens_recv:$tr_,duration_s:$dur,item_hash:$ih,feat_tag:$ft,stage_run:$run,commits:$cm,head_before:$hb,head_after:$ha}' \
    >> state/outcomes.jsonl 2>/dev/null || true
  return 0
}
emit_unverified_outcome
