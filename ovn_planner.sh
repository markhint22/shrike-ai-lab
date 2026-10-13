#!/usr/bin/env bash
# ovn_planner.sh — the auto-planning layer above queue_refill (2026-09-07).
# When a repo's backlog/<repo>.md runs low AND its roadmap/<repo>.md has a [ready] feature, the 27B
# reads the repo and DECOMPOSES that feature into small, tiered, categorized, self-verifying backlog
# items (appended to backlog/<repo>.md, tagged so a human can review), and marks the feature
# [decomposed]. queue_refill then pulls those items into the live queue as it drains. Net: leave the
# fleet unattended and it keeps planning->decomposing->building down the roadmap, on its own judgment.
#
# Design notes:
#  - Uses the model DIRECTLY via LiteLLM (a "generate a decomposition" task, not a code edit).
#  - The 27B TRIES the decomposition; a human (Claude) reviews the roadmap + the generated items.
#  - Conservative: at most ONE feature per repo per run; only touches [ready] features (Claude
#    promotes [needs-research] -> [ready] after web/market research).
#  - Assumes it's called where the run.lock is already held (run_overnight cycle-end) OR standalone.
set -uo pipefail
cd "$HOME/overnight-queue" || exit 1
export PATH=/usr/local/bin:/usr/bin:/bin:${PATH:-}
LITELLM="${LITELLM_BASE:-http://localhost:4000}"
LITELLM_KEY="${LITELLM_MASTER_KEY:-sk-shrike-local}"
MODEL="${OVN_MODEL:-qwen-dflash-27B}"
PLAN_THRESHOLD="${OVN_PLAN_THRESHOLD:-10}"   # decompose a feature when backlog has fewer than this many T-items
LOG="logs/ovn_planner.log"
say(){ echo "$(date '+%F %T') $*" >> "$LOG"; }

# 2026-09-21: respect a manual/GPU-testing pause — this script hits the local LLM directly
# (real GPU contention) and had no pause check, so `queue.sh pause` before a dedicated GPU
# session did NOT actually stop this from firing on its own cron.
if [ -f state/PAUSED ]; then
  say "queue is paused (state/PAUSED exists) — skipping this run entirely"
  exit 0
fi

# 2026-09-17: this state (roadmap fully [decomposed], zero [ready] features left to pull from) was
# found sitting SILENT for hours on gitlark+billwatch during a live audit -- the script logged
# 'needs Claude research?' every single cycle but never told a human, unlike queue_refill.sh's
# backlog-dry alert or queue_health.sh's low-doable alert. A repo can fully starve (roadmap
# exhausted -> backlog empties -> live queue empties) with zero ntfy signal that a Claude research
# pass (promote [needs-research] -> [ready] in roadmap/<repo>.md) is what's actually needed. Same
# dry/newly-dry/reminder/recovered marker pattern as queue_refill.sh's qr_dry_<repo>, scoped to
# THIS specific terminal state (not general backlog-low, which queue_refill already covers).
STATE_DIR="state"; mkdir -p "$STATE_DIR" 2>/dev/null
# 2026-10-11 (r11 acct, xlite X8): a lane with no [ready] roadmap feature logged the SAME "backlog low (0) but no [ready] roadmap feature" line on every pass (945x per lane in 24h;
# ~69 s apart). say_rl <key> <message...> is queue_refill.sh's log_rl for this log: silent while the SAME message was already written for <key> less than PLN_LOG_REPEAT_S (default
# 1800) seconds ago; a changed message (a different backlog count) or a window repeat prints at once. ovn_research_trigger_check.py takes `starving_since` from the FIRST starved line
# after the last clear (so fewer repeats do not move it) and ovn_planning_stats.py reads the last line per repo within 3 h, so the window stays far below that. PLN_LOG_REPEAT_S=0 =
# the old behaviour (log every pass). The once-per-day alert lives in ovn_research_trigger_check.py (the starving timer), not here.
PLN_LOG_REPEAT_S="${PLN_LOG_REPEAT_S:-1800}"
say_rl(){
  local key="$1"; shift
  local msg="$*" f="$STATE_DIR/pl_log_$key" sig last_ts last_sig
  case "$PLN_LOG_REPEAT_S" in ''|*[!0-9]*) PLN_LOG_REPEAT_S=1800 ;; esac
  if [ "$PLN_LOG_REPEAT_S" -gt 0 ]; then
    sig="$(printf '%s' "$msg" | cksum | tr ' ' '-')"
    if [ -f "$f" ]; then
      last_ts="$(sed -n 1p "$f" 2>/dev/null)"; last_sig="$(sed -n 2p "$f" 2>/dev/null)"
      case "$last_ts" in ''|*[!0-9]*) last_ts=0 ;; esac
      if [ "$last_sig" = "$sig" ] && [ $(( $(date +%s) - last_ts )) -lt "$PLN_LOG_REPEAT_S" ]; then return 0; fi
    fi
    printf '%s\n%s\n' "$(date +%s)" "$sig" > "$f.tmp.$$" 2>/dev/null && mv -f "$f.tmp.$$" "$f" 2>/dev/null || rm -f "$f.tmp.$$" 2>/dev/null
  fi
  say "$msg"
}
say_rl_reset(){ rm -f "$STATE_DIR/pl_log_$1" 2>/dev/null; }   # a line printed with plain say() for <key> is a state change: forget the stored signature
RESEARCH_REMIND_HOURS="${OVN_RESEARCH_REMIND_HOURS:-24}"
# 2026-09-28: this used to push its own "Roadmap exhausted" ntfy on top of queue_refill.sh's
# "out of queued items", ovn_research_trigger_check.sh's "needs research", AND
# ovn_fleet_health.sh's "low runway" — four separate pushes for the same underlying fact
# (confirmed live: state/ovn_needs_research_shrike-monitor and state/qr_dry_shrike-monitor
# existed simultaneously for the same repo/fact). ovn_fleet_health.sh is now the single
# canonical alerter for "this repo is running out of work" (richest context: doable count,
# burn rate, days-of-runway; sensible once-daily cadence). This still does its OWN
# detection + the ovn_needs_research_<repo> marker bookkeeping (nothing else reads that
# marker today, confirmed by grep, but keeping it costs nothing and preserves the dedup
# behavior if that changes) — it just no longer pushes a redundant phone notification, so
# the NTFY_TOPIC-resolving alert() helper this used to call was removed as dead weight.
needs_research_alert(){ # $1=repo $2=backlog-count
  local r="$1" bc="$2" now remind_secs last marker
  marker="$STATE_DIR/ovn_needs_research_${r}"
  now=$(date +%s); remind_secs=$(( RESEARCH_REMIND_HOURS * 3600 ))
  if [ ! -f "$marker" ]; then
    echo "$now" > "$marker"
    say "$r: needs-research condition newly detected (backlog=${bc}, no [ready] feature) — ntfy suppressed, see ovn_fleet_health.sh for the consolidated low-runway push"
  else
    last=$(cat "$marker" 2>/dev/null || echo "$now")
    if [ $(( now - last )) -ge "$remind_secs" ]; then
      echo "$now" > "$marker"
      say "$r: needs-research condition still open after ${RESEARCH_REMIND_HOURS}h+ — ntfy suppressed, see ovn_fleet_health.sh"
    fi
  fi
}
clear_research_alert(){ local r="$1" marker="$STATE_DIR/ovn_needs_research_${r}"; [ -f "$marker" ] && rm -f "$marker" && say "$r: needs-research condition cleared"; }
# 2026-09-30: single-instance guard. Found live: an interactive/manual run overlapping the :40 cron run
# (or a slow prior pass) made 2-3 passes each pick the SAME [ready] feature before any of them had marked it
# [decomposed], so one feature was decomposed 2-3x into near-duplicate (differently-worded) backlog items
# (gitlark 2x, shrike-monitor 3x, test-automation-agent 2x). Silent skip on contention: the next hourly pass
# picks up whatever is still [ready], so a skipped pass costs nothing.
exec 228>"$STATE_DIR/ovn_planner.lock"
if ! flock -n 228; then say "another planner pass is already running - skipping this one"; exit 0; fi
REPOS="${*:-billwatch gitlark iptv_apps test-automation-agent shrike-notify shrike-monitor xlite}"
# 2026-09-30: 4 -> 8. A research refuel lands ~70 [ready] features at once and at 4/hour they took ~17h to drain
# (iptv_apps last in line with 0 doable items). Each decomposition is ~15-40s of 27B time, so 8 is ~2-5 min/hour;
# repos are processed neediest-first so the cap is spent where it matters. OVN_PLAN_MAX_PER_RUN overrides.
MAX_PER_RUN="${OVN_PLAN_MAX_PER_RUN:-8}"   # cap decompositions per invocation so cycle-end never balloons
_did=0

# Process the NEEDIEST repos first (fewest backlog T-items), so a dry repo gets fed before a full
# one — otherwise a fixed order can burn the cap on repos that still have backlog while a truly-dry
# repo starves. 2026-09-07.
REPOS="$(for r in $REPOS; do
  b=$(grep -cE '^- \[ \] \[T[1-5]\]' "backlog/$r.md" 2>/dev/null); echo "${b:-0} $r"
done | sort -n | awk '{print $2}')"

for r in $REPOS; do
  [ "$_did" -ge "$MAX_PER_RUN" ] && { say "hit MAX_PER_RUN=$MAX_PER_RUN — stopping this planning pass"; break; }
  rm="roadmap/$r.md"; bl="backlog/$r.md"
  [ -f "$rm" ] || { continue; }
  bcount=$(grep -cE '^- \[ \] \[T[1-5]\]' "$bl" 2>/dev/null)
  [ "${bcount:-0}" -ge "$PLAN_THRESHOLD" ] && { say "$r: backlog=$bcount >= $PLAN_THRESHOLD — no planning needed"; continue; }

  # next [ready] feature (skip needs-research/decomposed/done)
  feat_line="$(grep -nE '^- \[ \] \[P[1-4]\] \[ready\]' "$rm" 2>/dev/null | head -1)"
  if [ -z "$feat_line" ]; then
    say_rl "$r" "$r: backlog low ($bcount) but no [ready] roadmap feature (needs Claude research?)"
    needs_research_alert "$r" "$bcount"
    continue
  fi
  say_rl_reset "$r"   # a [ready] feature exists again: the next dry spell must print its first line
  fln="${feat_line%%:*}"
  feat="$(printf '%s' "${feat_line#*:}" | sed -E 's/^- \[ \] \[P[1-4]\] \[ready\] //')"

  # 2026-10-11 (delplan X5): a feature that is a pure whole-file delete ("Delete orphan <path> ... VERIFY: `test ! -f <path>`", or a {cat: dead-code|infra; size: S} Delete title)
  # needs no 27B: asking it for "6 to 10 items" split a one-line deletion into ceremonial items with conflicting VERIFYs (verify-only x4, an absence test ordered BEFORE the
  # delete). `ovn_delete_executor.py plan` emits ONE `Delete the file` item per path, only when the delete executor's own safety checks (no importer, not protected, tracked, ...)
  # pass for EVERY path; anything doubtful is a SKIP and the model decomposes the feature exactly as before. OVN_PLANNER_DELETE_BYPASS=off|shadow|on (default shadow: log what
  # it would have done, still call the model).
  _det_items=""
  _delx="$HOME/overnight-queue/scripts/ovn_delete_executor.py"
  _dp_mode="${OVN_PLANNER_DELETE_BYPASS:-shadow}"
  if [ "$_dp_mode" != off ] && [ -f "$_delx" ]; then
    _dp_out="$(timeout 90 python3 "$_delx" plan "repos/$r" "$feat" 2>>"$LOG")"
    _dp_head="${_dp_out%%$'\n'*}"
    case "$_dp_head" in
      OK*)
        say "$r: delete-plan (${_dp_mode}): $(printf '%s' "$_dp_out" | tail -n +2 | grep -c '^- \[ \]') deterministic delete item(s) for: ${feat:0:80}"
        [ "$_dp_mode" = on ] && _det_items="$(printf '%s\n' "$_dp_out" | tail -n +2 | grep -E '^- \[ \] \[T[1-5]\] .+ VERIFY: ')" ;;
      DONE*)
        say "$r: delete-plan (${_dp_mode}): every named path is already gone (${_dp_head#DONE?}) for: ${feat:0:80}"
        if [ "$_dp_mode" = on ]; then
          sed -i "${fln}s/\[ready\]/[decomposed]/" "$rm"
          say "$r: feature already satisfied - marked [decomposed], no items appended"
          clear_research_alert "$r"; _did=$((_did+1)); continue
        fi ;;
      SKIP*) say "$r: delete-plan declined (${_dp_head#SKIP?})" ;;
    esac
  fi
  if [ -n "$_det_items" ]; then
    items="$_det_items"; n=$(printf '%s\n' "$items" | grep -c '^- \[ \]')
  else
  # compact repo layout for context (key source files, capped)
  layout="$(cd "repos/$r" 2>/dev/null && find . -maxdepth 4 \( -name '*.py' -o -name '*.ts' -o -name '*.tsx' -o -name '*.vue' -o -name '*.gd' \) \
              -not -path '*/node_modules/*' -not -path '*/.venv/*' -not -path '*/.godot/*' 2>/dev/null | sed 's#^\./##' | sort | head -120)"
  [ -z "$layout" ] && { say "$r: no source layout found — skip"; continue; }

  # 2026-10-09 (spec-compiler-v2): two prompt rules that stop the two spec shapes that could never land (verification-only items; deleting a definition before its
  # references are gone - 10 remove/restore commits in 8 minutes on the enemy_faction_map batch). OVN_PLANNER_SPEC_RULES=off drops them (prompt byte-identical to before).
  _spec_rules=""
  if [ "${OVN_PLANNER_SPEC_RULES:-on}" != off ]; then
    _spec_rules=$'\n- An item that only Verifies/Ensures/Checks is forbidden: every item must change code or tests.\n- For a Delete feature the FIRST items remove every reference to the symbol outside its definition (tests included); the LAST item deletes the definition.'
  fi
  read -r -d '' PROMPT <<PROMPT_END || true
You decompose a product FEATURE into small, self-verifying backlog items for an autonomous coding fleet (a 27B model driving aider). Output ONLY the item lines — no preamble, no prose.

REPO: $r
Source layout (real paths you must reuse):
$layout

FEATURE to decompose:
$feat

Output 6 to 10 items, each EXACTLY one line in this format:
- [ ] [T<1-5>] <real/path.ext> — <one precise change> VERIFY: <an exact test or command that proves it>. (cat:<category>; multifile:<yes|no>)

Hard rules:
- Each item is SMALL, independently landable, and self-verifying (a unit test, a type-check, or a grep).
- Prefer NEW pure functions + a colocated test (T1-T2). Use T3 for a wired change; reserve T4-T5 for a genuine multi-file refactor and set multifile:yes.
- Use ONLY real paths consistent with the layout above; put new files in the right directory.
- NEVER write "Create"/"Implement"/"Define" for a function, class or test file the FEATURE text says already exists
  (or that a path in the layout shows exists): modify it instead. Tests go where the repo's runner collects them
  (iptv_apps: iptv-backend/tests/ only; xlite: tests/ only, never test/).
- Do NOT invent a new generic helper function (coercion, casting, formatting) in an unrelated file. Put the change
  INLINE in the function the FEATURE names, and write at most ONE test file per behaviour (no near-duplicate tests).
- Do not add a step that only casts values already typed as int/str; every step must change observable behaviour.${_spec_rules}
- category is one of: python, typescript, vue, godot, endpoint, schema, test, docs, refactor.
- No secrets, no deploy/DNS/keys (those are human tasks — skip them).
PROMPT_END

  say "$r: decomposing [ready] feature: ${feat:0:80}"
  body="$(python3 -c "import json,sys;print(json.dumps({'model':'$MODEL','messages':[{'role':'user','content':sys.stdin.buffer.read().decode('utf-8','replace')}],'temperature':0.3,'max_tokens':1200}))" <<<"$PROMPT")"
  _raw="$(curl -fsS --max-time 180 "$LITELLM/v1/chat/completions" -H 'Content-Type: application/json' -H "Authorization: Bearer $LITELLM_KEY" -d "$body" 2>>"$LOG")"
  resp="$(printf '%s' "$_raw" | jq -r '.choices[0].message.content // empty' 2>>"$LOG")"
  # 2026-09-16: this runs HOURLY and its real token spend was discarded entirely - log it.
  bash "$HOME/overnight-queue/scripts/ovn_log_tokens.sh" planner "$r" \
    "$(printf '%s' "$_raw" | jq -r '.usage.prompt_tokens // 0' 2>/dev/null)" \
    "$(printf '%s' "$_raw" | jq -r '.usage.completion_tokens // 0' 2>/dev/null)" 2>/dev/null || true
  # keep only well-formed item lines
  items="$(printf '%s\n' "$resp" | grep -E '^- \[ \] \[T[1-5]\] .+ VERIFY: ' | head -12)"
  n=$(printf '%s' "$items" | grep -c '^- \[ \]')
  # 2026-10-05: a tiny feature legitimately decomposes into 1-2 steps, but "<3 valid -> skip" retried it
  # every pass forever (6 identical 4s model calls in 45 min on a one-line console.log cleanup). Count
  # misses per feature: accept 1-2 valid items on the 2nd miss, park a feature that yields nothing
  # after 3 tries as [needs-decompose] (which the [ready] selector skips) and say so.
  _miss_file="$STATE_DIR/planner_miss_${r}"
  _miss_key="$(printf '%s' "$r|$feat" | cksum | cut -d' ' -f1)"
  if [ "${n:-0}" -lt 3 ]; then
    _misses=0
    [ "$(cut -d' ' -f1 "$_miss_file" 2>/dev/null)" = "$_miss_key" ] && _misses="$(cut -d' ' -f2 "$_miss_file" 2>/dev/null)"
    _misses=$(( ${_misses:-0} + 1 ))
    printf '%s %s\n' "$_miss_key" "$_misses" > "$_miss_file" 2>/dev/null || true
    if [ "${n:-0}" -ge 1 ] && [ "$_misses" -ge 2 ]; then
      say "$r: 27B produced ${n} valid item(s) twice for this feature - accepting the small decomposition"
    elif [ "$_misses" -ge 3 ]; then
      sed -i "${fln}s/\[ready\]/[needs-decompose]/" "$rm"
      rm -f "$_miss_file"
      say "$r: feature produced no valid items 3 times - PARKED as [needs-decompose] (needs a human/Claude to rewrite it): ${feat:0:80}"
      continue
    else
      say "$r: 27B produced only ${n} valid items - NOT appending (try ${_misses}/3; needs Claude review of the prompt/feature)"
      continue
    fi
  fi
  rm -f "$_miss_file" 2>/dev/null || true
  # Android flavor-task disambiguation (2026-09-20): the 27B has no way to know a repo's
  # real Gradle product-flavor names (not in its layout/prompt context here), so it
  # routinely writes VERIFY commands using the single-variant task shape
  # (":app:testDebugUnitTest") that AGP only accepts when the app module has ZERO
  # product flavors. iptv-android declares googleTv+fireTv (billwatch-android declares
  # none, confirmed by audit) - Gradle then fails immediately with "Task '...' is
  # ambiguous in project ':app'" before a single test runs. scripts/ovn_gradle_flavor_guard.sh
  # rewrites that exact shape to Gradle's own umbrella ":<module>:test" task, which is
  # valid whether or not the module has flavors.
  _gradle_guard="$HOME/overnight-queue/scripts/ovn_gradle_flavor_guard.sh"
  if [ -f "$_gradle_guard" ]; then
    _guard_log="$(mktemp)"
    # NEVER let a missing/misbehaving guard silently empty out a good decomposition -
    # only replace $items if the guard actually produced output.
    _guard_out="$(printf '%s\n' "$items" | bash "$_gradle_guard" "repos/$r" 2>"$_guard_log")"
    [ -n "$_guard_out" ] && items="$_guard_out"
    [ -s "$_guard_log" ] && say "$r: $(cat "$_guard_log")"
    rm -f "$_guard_log"
  fi
  # 2026-10-05 grounding guard: the 27B decomposes without reading the repo, so it told the fleet to
  # "Implement" functions and "Create" test files that already exist (and to put tests where the runner
  # never collects them). Same fail-safe contract as the Gradle guard: never lose a decomposition to it.
  _ground_guard="$HOME/overnight-queue/scripts/ovn_decomp_ground_guard.py"
  if [ -f "$_ground_guard" ]; then
    _gg_log="$(mktemp)"
    _gg_out="$(printf '%s\n' "$items" | python3 "$_ground_guard" "repos/$r" 2>"$_gg_log")"
    [ -n "$_gg_out" ] && items="$_gg_out"
    [ -s "$_gg_log" ] && say "$r: $(tr '\n' ' ' < "$_gg_log" | cut -c1-600)"
    rm -f "$_gg_log"
    n=$(printf '%s\n' "$items" | grep -c '^- \[ \]')
  fi
  # 2026-10-09 spec gate lint (spec-compiler-v2): static repairs R01-R03 (bare VERIFY -> backticked, vacuous echo idiom, narrated "fails") on the decomposition,
  # only for the rules named in OVN_SPEC_GATE_ENFORCE_RULES (default R01,R11, the repair-only rules; set it empty to repair nothing, R02/R03 are opt-in); the rest is only reported. OVN_SPEC_GATE=off skips it. Same fail-safe
  # contract as the guards above: a missing/crashing lint can never lose or alter a decomposition (it echoes its input on any error, and an empty answer is ignored).
  _spec_gate="$HOME/overnight-queue/scripts/ovn_spec_gate.py"
  if [ -f "$_spec_gate" ]; then
    _sg_log="$(mktemp)"
    _sg_out="$(printf '%s\n' "$items" | python3 "$_spec_gate" lint "repos/$r" 2>"$_sg_log")"
    [ -n "$_sg_out" ] && items="$_sg_out"
    [ -s "$_sg_log" ] && say "$r: $(tr '\n' ' ' < "$_sg_log" | cut -c1-600)"
    rm -f "$_sg_log"
  fi
  fi   # end of the model-decomposition region (skipped when the deterministic delete plan above produced the items)
  # 2026-09-20 feature tracking: tag every item this feature decomposes into with a durable
  # [feat:ID] marker so a % complete / completion notification can be computed later (see
  # scripts/ovn_feature_groups.py's header for the full investigation — until this, the link
  # from a decomposed item back to its parent roadmap feature was thrown away the moment
  # queue_refill.py copied it into OVERNIGHT_PROGRESS.md as a bare line). The tag survives
  # checkbox toggling (run_overnight.sh's sed only ever rewrites the "- [ ] " prefix) and
  # archival to OVERNIGHT_DONE.md (archive_done.py moves lines verbatim), so it stays
  # attached to the item for its whole life. ID = repo + decompose-date + a slug of the
  # feature title, which also doubles as a human-readable label in the completion push.
  feat_slug="$(printf '%s' "$feat" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' | cut -c1-40)"
  feat_id="${r}-$(date '+%Y%m%d')-${feat_slug:-item}"
  items="$(printf '%s\n' "$items" | sed -E "s/\$/ [feat:${feat_id}]/")"
  # 2026-10-12 (package uidcredit): never append an item whose canonical identity (scripts/ovn_credit_items.py canon_item: annotation/state-tag/tier/feat-date-insensitive) already exists in the
  # repo's progress file (open, done or parked), its done archive or the backlog itself, nor two identical items of this one decomposition (a re-decomposed stuck feature used to re-add
  # its finished items; queue_refill then had to prune them one pull at a time). Fail-safe: any error keeps every item. OVN_PLANNER_DEDUPE=off disables.
  _ci_py="$HOME/overnight-queue/scripts/ovn_credit_items.py"
  if [ "${OVN_PLANNER_DEDUPE:-on}" != off ] && [ -f "$_ci_py" ]; then
    _dd_err="$(mktemp)"
    if _dd_out="$(printf '%s\n' "$items" | timeout 30 python3 "$_ci_py" filter-new "repos/$r/OVERNIGHT_PROGRESS.md" "repos/$r/OVERNIGHT_DONE.md" "$bl" 2>"$_dd_err")"; then
      _dd_n_new="$(printf '%s\n' "$_dd_out" | grep -c '^- \[ \]')"
      if [ "${_dd_n_new:-0}" -lt "${n:-0}" ]; then
        say "$r: dedupe dropped $(( ${n:-0} - ${_dd_n_new:-0} )) of ${n:-0} decomposed item(s) already present in the queue/done archive/backlog ($(tr '\n' ' ' < "$_dd_err" | cut -c1-80))"
        items="$_dd_out"; n="$_dd_n_new"
      fi
    fi
    rm -f "$_dd_err"
    if [ "${n:-0}" -le 0 ]; then
      sed -i "${fln}s/\[ready\]/[decomposed]/" "$rm"
      say "$r: every decomposed item already exists - nothing appended; marked feature [decomposed]"
      clear_research_alert "$r"
      continue
    fi
  fi
  {
    echo ""
    echo "# --- 27B-decomposed from roadmap [$(date '+%F')]: ${feat:0:90} (review + tweak) [feat:${feat_id}] ---"
    printf '%s\n' "$items"
  } >> "$bl"
  # mark the feature decomposed in the roadmap
  sed -i "${fln}s/\[ready\]/[decomposed]/" "$rm"
  say "$r: appended ${n} 27B-decomposed items to backlog; marked feature [decomposed]"
  clear_research_alert "$r"
  _did=$((_did+1))
done
