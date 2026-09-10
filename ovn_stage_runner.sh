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
cd "$HOME/overnight-queue" || exit 1
export PATH="$HOME/aider-venv/bin:/usr/local/bin:/usr/bin:/bin:${PATH:-}"
LITELLM="${LITELLM_BASE:-http://localhost:4000}"; LKEY="${LITELLM_MASTER_KEY:-sk-shrike-local}"
MODEL="${OVN_MODEL:-qwen-dflash-27B}"
MAX_ATT="${OVN_STAGE_MAX_ATTEMPTS:-2}"; MAX_STEPS="${OVN_STAGE_MAX_STEPS:-6}"; REDECOMP="${OVN_STAGE_REDECOMP:-1}"
STEP_TIMEOUT="${OVN_STAGE_STEP_TIMEOUT:-350}"
repo="${1:?repo required}"; item_arg="${2:-}"
rd="repos/$repo"; [ -d "$rd/.git" ] || { echo "no clone $rd"; exit 1; }
RUNID="$(date -u +%Y%m%d-%H%M%S)-$$"
mkdir -p state/stage_runs logs
SLOG="state/stage_runs/${repo}-${RUNID}.jsonl"
LOG="logs/ovn_stage_runner.log"; say(){ echo "$(date '+%F %T') [$repo] $*" | tee -a "$LOG"; }
jlog(){ echo "$1" >> "$SLOG"; }   # $1 = a json object string

# ONLY ONE stage runner at a time. Concurrent stage runners (a manual run + the cron sweep + the loop)
# each spawn an aider that contends on the SINGLE-THREADED llama-server, collapsing tok/s (60 solo ->
# ~4 under 4-way load) and timing steps out. Serialize them so each gets the GPU to itself.
exec 209>state/stage.lock
if ! flock -w 30 209; then say "another stage runner holds the lock — skipping (avoids 27B contention)"; exit 0; fi

# HARD SELF-WATCHDOG: a hung git/aider/LLM call must NEVER leave a runner alive forever — it holds the
# lock + contends on the 27B (this exact runaway crashed tok/s to 4 and had a 58-min zombie). Recursively
# kill this process + every descendant after the cap, regardless of how we were launched.
_self=$$
# `exec 209>&-`: the watchdog must NOT inherit the lock fd, or it holds state/stage.lock for 2000s AFTER
# the runner exits — which made sequential batch items skip ("another runner holds the lock"). Closing
# fd 209 here means the lock releases the instant the main runner exits, independent of the watchdog.
( exec 209>&-
  sleep "${OVN_STAGE_HARD_TIMEOUT:-2000}"
  _kt(){ local c; for c in $(pgrep -P "$1" 2>/dev/null); do _kt "$c"; done; kill -9 "$1" 2>/dev/null; }
  _kt "$_self" ) >/dev/null 2>&1 &
_wd=$!

# DEDICATED INFERENCE by default: contention was the dominant failure driver — under load the 27B
# generates too slowly and gets killed mid-edit (no-edit/timeout); SOLO it produces real edits fast
# (proven: the first genuinely-verified T3 landed only when dedicated). The lock guarantees ONE runner,
# so pausing the fleet here is safe. The fleet checks PAUSED between items; give it a moment to yield.
_dedicated=0
if [ "${OVN_STAGE_DEDICATE:-1}" = 1 ] && [ ! -f state/PAUSED ]; then
  touch state/PAUSED; date +%s > state/stage_pause_since; _dedicated=1; sleep 18
fi

# ---- one LiteLLM chat call: $1=prompt-file -> stdout = content. RETRIES with backoff so a collision
#      with the fleet's aider on the single-threaded llama-server queues instead of aborting. ----
llm(){ local pf="$1" body resp content i
  body="$(python3 -c "import json,sys;print(json.dumps({'model':'$MODEL','messages':[{'role':'user','content':open(sys.argv[1]).read()}],'temperature':0.2,'max_tokens':1100}))" "$pf")"
  for i in 1 2 3 4; do
    resp="$(curl -fsS --max-time 300 "$LITELLM/v1/chat/completions" -H 'Content-Type: application/json' \
      -H "Authorization: Bearer $LKEY" -d "$body" 2>>"$LOG")"
    content="$(printf '%s' "$resp" | jq -r '.choices[0].message.content // empty' 2>/dev/null)"
    if [ -n "$content" ]; then printf '%s' "$content"; return 0; fi
    echo "$(date '+%F %T') llm attempt $i got empty (resp ${#resp} bytes) — backoff $((i*8))s (fleet contention?)" >> "$LOG"
    sleep $((i*8))
  done
  return 1
}

# ---- pick the item ----
if [ -n "$item_arg" ]; then item="$item_arg"
else
  # PREFER the 27B's sweet spot (python) so a slot LANDS an item; then FALL BACK to the harder
  # non-godot items (frontend/wiring/T4/T5) so the 27B keeps ATTEMPTING them (it lands some, and the
  # verify layer + escalation route the rest). GODOT is the one class we never pick — it's measured 0%
  # and only wastes the slot on a guaranteed timeout; the sweep routes godot to Claude separately.
  _doable="$(grep -E '^- \[ \] ' "$rd/OVERNIGHT_PROGRESS.md" | grep -vE 'AUTO-SKIP|HUMAN-ONLY|BLOCKED' | grep -E '\[T[345]\]|·T[345]·' | grep -viE '\.gd\b')"
  item="$(printf '%s\n' "$_doable" | grep -iE '\.py\b' | grep -viE 'wire|integrate|\.vue\b|\.tsx?\b' | head -1 | sed -E 's/^- \[ \] //')"
  [ -z "$item" ] && item="$(printf '%s\n' "$_doable" | head -1 | sed -E 's/^- \[ \] //')"
fi
[ -z "$item" ] && { say "no doable T3+ item found"; exit 0; }
tier="$(printf '%s' "$item" | grep -oE '\[T[1-5]\]|·T[1-5]·' | head -1 | grep -oE '[1-5]' | head -1)"; tier="${tier:-3}"
say "ITEM (T$tier): ${item:0:100}"

# ---- worktree (all steps build on each other) ----
git -C "$rd" fetch -q origin overnight/feature 2>/dev/null
wt="$(mktemp -d "/tmp/stage-${repo}.XXXX")"
git -C "$rd" worktree add -q "$wt" origin/overnight/feature 2>/dev/null || { say "worktree failed"; exit 1; }
cleanup(){ kill "$_wd" 2>/dev/null; [ "${_dedicated:-0}" = 1 ] && rm -f state/PAUSED state/stage_pause_since; git -C "$rd" worktree remove --force "$wt" >/dev/null 2>&1; }
trap cleanup EXIT
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
layout="$(cd "$wt" && find . -maxdepth 4 \( -name '*.py' -o -name '*.ts' -o -name '*.tsx' -o -name '*.vue' -o -name '*.gd' \) -not -path '*/node_modules/*' -not -path '*/.venv/*' -not -path '*/.godot/*' 2>/dev/null | sed 's#^\./##' | sort | head -100)"

# ---- DECOMPOSE the item into ordered sub-steps (JSON) ----
decompose(){ # $1=task text  -> writes JSON array of {desc,files[],verify} to stdout
  local pf; pf="$(mktemp)"
  # GODOT carve-out: the 27B can write valid Godot-4 SOURCE with the gdparse/engine loop, but it CANNOT
  # author GUT test scripts (the test-framework .gd format defeats it every time — proven empirically).
  # So for godot items, decompose into SOURCE-ONLY steps and verify by compile-check, NOT by making it
  # write a GUT test. The runner's full_verify still runs the EXISTING GUT suite to catch regressions.
  local _rules
  case "$1" in
    *.gd*|*[Gg][Dd][Ss]cript*|*[Gg]odot*)
      _rules='GODOT 4 MODE — SOURCE ONLY. 1 to '"$MAX_STEPS"' small steps. Do NOT create or modify any GUT/test
.gd file (no tests/, no test_*.gd) — authoring GUT tests is OUT OF SCOPE and will fail. Each step ADDS or
MODIFIES only the named production .gd script(s). Each step "files" lists ONLY that source .gd. Each step
"verify" MUST be exactly "gdparse <that .gd path>" (valid Godot-4 syntax) — nothing else. Write REAL Godot
4.x code (typed, @export/@onready, await, callable .connect) — never Godot 3, never a stub/TODO. If the
task asks to WRITE A TEST, emit an empty array [] (it is not a source task). Keep each step to 1 file.' ;;
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
  cat > "$pf" <<PROMPT
Break this coding task into an ORDERED list of the SMALLEST safe sub-steps, each independently
committable and testable by an autonomous 27B model driving aider. Output ONLY a JSON array, no prose.

REPO: $repo
Real source paths (use EXACTLY, do not invent):
$layout

TASK:
$1

Each element: {"desc":"<one precise change>","files":["real/path.ext"],"verify":"<exact test/command that proves this step>"}
Rules: $_rules Output ONLY the JSON array.
PROMPT
  local raw; raw="$(llm "$pf")"; rm -f "$pf"
  # extract the JSON array from the raw content (model may wrap it in prose/fences)
  printf '%s' "$raw" | python3 -c "import sys,json
txt=sys.stdin.read(); i=txt.find('['); j=txt.rfind(']')
try:
    a=json.loads(txt[i:j+1]) if i>=0 and j>i else []
    a=[s for s in a if isinstance(s,dict) and s.get('desc')]
    print(json.dumps(a[:$MAX_STEPS]))
except Exception: print('[]')"
}

STEPS_JSON="$(decompose "$item")"
NSTEPS="$(printf '%s' "$STEPS_JSON" | jq 'length' 2>/dev/null || echo 0)"
if [ "${NSTEPS:-0}" -lt 1 ]; then say "decompose produced no steps — abort"; jlog "{\"run\":\"$RUNID\",\"repo\":\"$repo\",\"tier\":$tier,\"event\":\"decompose_failed\"}"; exit 1; fi
say "decomposed into $NSTEPS sub-steps"
jlog "$(jq -nc --arg r "$RUNID" --arg repo "$repo" --argjson t "$tier" --arg it "$item" --argjson n "$NSTEPS" --argjson plan "$STEPS_JSON" '{run:$r,repo:$repo,tier:$t,item:$it,event:"decomposed",steps:$n,plan:$plan}')"

# ---- run ONE sub-step: returns 0 pass / 1 fail. logs the attempt. ----
run_step(){ # $1=idx $2=desc $3=files(space-sep) $4=verify $5=redecomp-left
  local idx="$1" desc="$2" files="$3" verify="$4" rd_left="$5" att fa rc
  local fargs=(); for f in $files; do [ -n "$f" ] && fargs+=(--file "$f"); done
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
  local slog="state/stage_runs/${repo}-${RUNID}-s${idx}.log"   # per-step aider session log for review
  # adaptive context: start rich (repo-map + architect + AGENTS.md), SHRINK if we blow the 27B window
  local mt=3072; local rdargs=(--read AGENTS.md); local archargs=(--architect --auto-accept-architect)
  # GODOT: hand the model the Godot-4 rules file (kills the Godot-3 syntax the 27B defaults to). The
  # per-step ovn_autotest gdparse/godot --check-only loop then makes it fix any residual mistakes.
  local _gd4="$HOME/overnight-queue/assets/GODOT4.md"; local _is_godot=0
  case "$item$files$desc" in *.gd*|*[Gg][Dd][Ss]cript*|*[Gg]odot*) [ -f "$_gd4" ] && { rdargs+=(--read "$_gd4"); _is_godot=1; } ;; esac
  for att in $(seq 1 "$MAX_ATT"); do
    local base t0 atmp; base="$(git -C "$wt" rev-parse HEAD)"; t0=$(date +%s); atmp="$(mktemp)"
    { echo "===== step $idx attempt $att @ $(date '+%F %T') (map=$mt arch=${#archargs[@]} read=${#rdargs[@]}) ====="; echo "DESC: $desc"; echo "FILES: $files"; echo "VERIFY: $verify"; } >> "$slog"
    local msg="Execute THIS one sub-step now and produce the diff. Do NOT do other steps.
STEP: $desc
VERIFY: $verify
Make the minimal change to the named file(s), keep it compiling + all tests green. Write a REAL working implementation — NO stub/placeholder/'for demonstration'/TODO/NotImplementedError. Any test you write MUST import and call the EXACT symbol you just created, and EVERY import in the test MUST resolve to a real module+symbol — check the actual file path of what you import (a single wrong import raises ImportError at collection time and fails the ENTIRE test file). For an endpoint, prefer a TestClient behavior test (client.get('/path')) over importing the handler. If writing a test, assert PROPERTIES not guessed exact values. Beware DB round-trips: a value read back from the DB may be naive (SQLite drops tzinfo) or lower-precision — assert on the value BEFORE persistence or on behavior, never that tzinfo/exact-precision survived a DB read.${_tgtctx}"
    if [ "$_is_godot" = 1 ]; then msg="This is a GODOT 4.x GDScript task. Follow the Godot-4 rules file you were given (GODOT4.md). Write Godot 4 ONLY — NEVER Godot 3 API (no 'export var', no 'yield(', no KinematicBody/Spatial, no string-signal connect). Use @export/@onready annotations, 'await', callable '.connect()', typed vars/returns. Only reference methods/signals that exist on the node type you extend. The gate will run gdparse + godot --check-only on your file and hand back any error to fix. Ignore the python/pytest/TestClient/DB guidance above — it does not apply here.
STEP: $desc
VERIFY: $verify
Make the minimal change to the named .gd file(s), valid Godot 4 that parses clean.${_tgtctx}"; fi
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
    grep -qiE 'context size has been exceeded|context length|context_length|prompt is too long|exceed_context' "$atmp" && ctx=1
    if [ "$ctx" = 1 ]; then
      # aider never completed the edit — do NOT let a trivial partial change false-pass the scoped gate
      fa="context-exceeded"; rc=1
      excerpt="27B context window exceeded; shrinking (map->$((mt/2)), drop architect+AGENTS) and retrying"
    elif [ "$dur" -ge $((STEP_TIMEOUT - 12)) ]; then
      # aider was HARD-KILLED at the step timeout = it wandered / never finished its turn. A clean turn
      # exits before the timeout. Refuse to count a killed-mid-edit change as a pass (the T4 false-pass).
      fa="timeout"; rc=1
      excerpt="aider hit the ${STEP_TIMEOUT}s step timeout (wandered/incomplete) — not a clean pass"
    elif [ -z "$(git -C "$wt" status --porcelain 2>/dev/null)" ]; then
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
    else
      if ( cd "$wt" && bash "$HOME/overnight-queue/scripts/ovn_autotest.sh" "$wt" ) >> "$slog" 2>&1; then
        fa=""; rc=0
      else
        fa="$(bash "$HOME/overnight-queue/ovn_classify_fail.sh" "$atmp" reverted 2>/dev/null)"; rc=1
        excerpt="$(grep -iE 'error|fail|assert|expected|traceback|<failure|cannot|not found|no attribute|no such' "$atmp" 2>/dev/null | tail -4 | tr '\n' ' ' | cut -c1-320)"
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
      git -C "$wt" add -A && git -C "$wt" -c user.email=fleet@shrike.local -c user.name=shrike-fleet commit -q -m "feat($repo): staged step $idx — ${desc:0:60}" 2>/dev/null
      return 0
    fi
    say "  step $idx att $att FAIL ($fa, ${dur}s): ${excerpt:0:90}"
    git -C "$wt" reset -q --hard "$base"; git -C "$wt" clean -qfd 2>/dev/null
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
      local k; for k in $(seq 0 $((nsub-1))); do
        local sd sf sv
        sd="$(printf '%s' "$sub" | jq -r ".[$k].desc")"
        sf="$(printf '%s' "$sub" | jq -r ".[$k].files // [] | join(\" \")")"
        sv="$(printf '%s' "$sub" | jq -r ".[$k].verify // \"tests green\"")"
        run_step "${idx}.${k}" "$sd" "$sf" "$sv" 0 || { say "  sub-step ${idx}.${k} BLOCKED"; }
      done
      return 0   # partial progress from whatever sub-steps passed
    fi
  fi
  say "  step $idx BLOCKED (could not land after retries + re-decomp)"
  jlog "$(jq -nc --arg r "$RUNID" --argjson i "$idx" '{run:$r,step:$i,verdict:"blocked"}')"
  return 1
}

# ---- run all steps ----
passed=0
for i in $(seq 0 $((NSTEPS-1))); do
  d="$(printf '%s' "$STEPS_JSON" | jq -r ".[$i].desc")"
  f="$(printf '%s' "$STEPS_JSON" | jq -r ".[$i].files // [] | join(\" \")")"
  v="$(printf '%s' "$STEPS_JSON" | jq -r ".[$i].verify // \"tests green\"")"
  run_step "$i" "$d" "$f" "$v" "$REDECOMP" && passed=$((passed+1))
done

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
    local pkg; pkg="${vp%/.venv/bin/pytest}"; pkg="${pkg#"$rd"/}"
    # 600s (was 300s, 2026-09-09): iptv_apps's full pytest suite (1436 tests, ~356s+ measured) was
    # getting killed at exactly 300s every single T3+ run (confirmed via verify.log truncated
    # mid-progress-bar at 81% + start/FAILED log timestamps exactly 300s apart), a false-revert
    # of every T4/T5 attempt regardless of whether the change was actually good — same class of
    # bug as the run_overnight.sh 240->600 fix, just a separate hardcoded cap in this file.
    [ -d "$wt/$pkg" ] && { echo "-- pytest FULL in $pkg --" >> "$vlog"; ( cd "$wt/$pkg" && timeout 600 "$HOME/overnight-queue/$vp" -q -o addopts="" -p no:cacheprovider ) >> "$vlog" 2>&1 || vok=0; }
  fi
  # GODOT: GUT full suite + compile scan
  if [ "$vok" = 1 ] && [ -f "$wt/project.godot" ] && [ -x "$HOME/godot/godot4" ]; then
    echo "-- GUT FULL --" >> "$vlog"
    ( cd "$wt" && timeout 120 "$HOME/godot/godot4" --headless --path . --import ) >>"$vlog" 2>&1
    local xml; xml="$(mktemp)"
    ( cd "$wt" && timeout 90 "$HOME/godot/godot4" --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit "-gjunit_xml_file=$xml" ) >> "$vlog" 2>&1
    { [ -s "$xml" ] && grep -q 'failures="0"' "$xml" && ! grep -q 'status="no asserts"' "$xml"; } || vok=0
    grep -qiE 'Failed to load script|Failed to compile|Parse Error' "$vlog" && vok=0; rm -f "$xml"
  fi
  # WEB: vitest full run (reuse provisioned node_modules)
  if [ "$vok" = 1 ]; then
    local pj; pj="$(find "$rd" -maxdepth 3 -name package.json -not -path '*/node_modules/*' 2>/dev/null | grep -l . 2>/dev/null | head -1)"
    [ -z "$pj" ] && pj="$(find "$rd" -maxdepth 3 -name package.json -not -path '*/node_modules/*' 2>/dev/null | head -1)"
    if [ -n "$pj" ] && grep -q '"vitest"' "$pj" 2>/dev/null; then
      local wd; wd="$(dirname "$pj")"
      [ -d "$wd/node_modules" ] && { local wwd; wwd="$wt/${wd#"$rd"/}"; [ -e "$wwd/node_modules" ] || ln -s "$(cd "$wd" && pwd)/node_modules" "$wwd/node_modules" 2>/dev/null; echo "-- vitest FULL --" >> "$vlog"; ( cd "$wwd" && CI=true timeout 240 npx vitest run ) >> "$vlog" 2>&1 || vok=0; }
    fi
  fi
  # SEMANTIC: a "wire/integrate/register X into FILE" item must leave FILE actually referencing X
  if printf '%s' "$item" | grep -qiE '\b(wire|integrate|register|hook|call|invoke)\b'; then
    local sym tgt
    sym="$(printf '%s' "$item" | grep -oE '`[A-Za-z_][A-Za-z0-9_.]*`' | head -1 | tr -d '`' | sed 's/.*\.//')"
    # target file: prefer a file named after "into/in <file>"; else the item's PRIMARY named file (the
    # one at the start, e.g. "checker.py — Integrate X into ..."). NOT the last path (that's often the test).
    tgt="$(printf '%s' "$item" | grep -oiE '\b(into|in) +`?[A-Za-z0-9_./-]+\.(gd|py|ts|tsx|vue)' | grep -oE '[A-Za-z0-9_./-]+\.(gd|py|ts|tsx|vue)' | head -1)"
    [ -z "$tgt" ] && tgt="$(printf '%s' "$item" | grep -oE '[A-Za-z0-9_./-]+\.(gd|py|ts|tsx|vue)' | head -1)"
    if [ -n "$sym" ] && [ -n "$tgt" ] && [ -f "$wt/$tgt" ]; then
      # count references OUTSIDE the symbol's own definition line: a real integration USES the symbol
      local refs; refs="$(grep -c "$sym" "$wt/$tgt" 2>/dev/null)"; refs="${refs:-0}"   # NO `|| echo 0` (that yields "0\n0" -> integer errors)
      if [ "${refs:-0}" -ge 2 ] || { [ "${refs:-0}" -ge 1 ] && ! grep -qE "(def|func|function|static func) +$sym" "$wt/$tgt" 2>/dev/null; }; then
        echo "-- semantic OK: $tgt uses $sym ($refs refs) --" >> "$vlog"
      else
        echo "-- SEMANTIC FAIL: $tgt only defines (or never uses) $sym — the claimed integration never happened --" >> "$vlog"; vok=0
      fi
    fi
  fi
  # QUALITY: reject stub/placeholder implementations, and tests that never exercise the new code
  # (the gitlark PlanService "win" was a keyword stub whose test tested a DIFFERENT class — a fake pass).
  local changed; changed="$(git -C "$wt" diff --name-only origin/overnight/feature..HEAD 2>/dev/null)"
  local srcs tests; srcs="$(printf '%s\n' "$changed" | grep -E '\.(py|gd|ts|tsx|vue)$' | grep -viE 'test|spec')"
  tests="$(printf '%s\n' "$changed" | grep -iE 'test|spec' | grep -E '\.(py|gd|ts|tsx|vue)$')"
  local cf
  for cf in $srcs; do
    [ -f "$wt/$cf" ] || continue
    if grep -qiE 'for demonstration|placeholder|not implemented|NotImplementedError|TODO:? implement|for now,? (just|return)|# *stub|dummy (value|impl)|simple .* for demonstration' "$wt/$cf" 2>/dev/null; then
      echo "-- QUALITY FAIL: $cf is a stub/placeholder — a real working implementation is required --" >> "$vlog"; vok=0
    fi
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
  git -C "$wt" add -A 2>/dev/null
  git -C "$wt" diff --cached --quiet 2>/dev/null && return 1   # nothing actually regenerated
  git -C "$wt" -c user.email=fleet@shrike.local -c user.name=shrike-fleet commit -q -m "chore($repo): regenerate stale artifact so verification passes" 2>/dev/null
  return 0
}

VERIFIED=0
if [ "$passed" -gt 0 ]; then
  if full_verify; then VERIFIED=1; say "independent full-verify: PASSED — the combined result is real"
  else
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
      rmsg="Your change LANDED but FAILED final verification. Fix it so verification passes — edit the SOURCE and/or the TEST, whichever is actually wrong; do NOT revert the working parts, make the minimal fix. Likely causes: (a) your new test asserts a guessed/wrong value or a tz/precision a DB round-trip drops (SQLite naive datetimes) — assert real behavior/PROPERTIES instead; (b) the test never calls the code you changed — import and exercise the real symbol, or drive an endpoint via TestClient; (c) a stub/placeholder remains — implement it for real; (d) the change broke a sibling test — fix the source. THE EXACT FAILURE:
$reason"
      ( cd "$wt" && timeout "$STEP_TIMEOUT" aider --yes-always --no-check-update --no-auto-commits --edit-format udiff \
          --model "openai/$MODEL" --openai-api-base "$LITELLM/v1" --openai-api-key "$LKEY" \
          --model-metadata-file "$HOME/overnight-queue/model-metadata.json" --map-tokens 2048 \
          --auto-test --test-cmd "bash $HOME/overnight-queue/scripts/ovn_autotest.sh $wt" \
          ${repair_fargs[@]+"${repair_fargs[@]}"} --message "$rmsg" ) >> "$local_vlog" 2>&1
      if full_verify; then
        VERIFIED=1; passed="$NSTEPS"
        git -C "$wt" add -A && git -C "$wt" -c user.email=fleet@shrike.local -c user.name=shrike-fleet commit -q -m "fix($repo): repair staged item to pass verification (round $_rr)" 2>/dev/null
        say "REPAIR PASSED (round $_rr) — verified after fixing the flagged failure"
      fi
    done
    [ "$VERIFIED" = 0 ] && { say "independent full-verify: FAILED — NOT pushing, re-opening (see ${SLOG%.jsonl}.verify.log)"; passed=0; }
  fi
fi
jlog "$(jq -nc --arg r "$RUNID" --argjson v "$VERIFIED" '{run:$r,event:"verify",verified:($v==1)}')"

# ---- push ONLY when independently verified ----
ncommits=0
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
    if git -C "$wt" push -q origin HEAD:overnight/feature 2>/dev/null || { git -C "$wt" pull -q --rebase origin overnight/feature && git -C "$wt" push -q origin HEAD:overnight/feature; }; then
      ncommits="$local_ncommits"
      say "pushed $ncommits verified commit(s) to overnight/feature"
    else say "push FAILED (fleet racing) — commits are in the worktree branch only, NOT counted as pushed"; fi
  fi
fi

# ---- mark the item done ONLY if independently verified (else leave OPEN for a clean re-attempt) ----
if [ "$VERIFIED" = 1 ] && [ "$passed" -gt 0 ] && [ -z "$item_arg" ]; then   # only auto-picked items live in the queue
  ./queue.sh hold "$repo" >/dev/null 2>&1
  ( cd "$rd" && git fetch -q origin overnight/feature && git reset -q --hard origin/overnight/feature ) 2>/dev/null
  OVN_F="$rd/OVERNIGHT_PROGRESS.md" OVN_ITEM="$item" OVN_P="$passed" OVN_N="$NSTEPS" python3 - <<'PY'
import os
f=os.environ["OVN_F"]; item=os.environ["OVN_ITEM"]; p=int(os.environ["OVN_P"]); n=int(os.environ["OVN_N"])
lines=open(f,encoding="utf-8").read().split("\n"); key=item[:55]
for i,ln in enumerate(lines):
    if ln.startswith("- [ ] ") and key and key in ln:
        if p>=n:  # fully done -> check it off
            lines[i]=ln.replace("- [ ] ","- [x] ",1)+f"  <!-- staged {p}/{n} DONE -->"
        else:     # partial -> park the remainder so it isn't blindly redone identically
            lines[i]=ln.replace("- [ ] ","- [ ] [AUTO-SKIP staged {}/{} — {} step(s) blocked; recover/review] ".format(p,n,n-p),1)
        open(f,"w",encoding="utf-8").write("\n".join(lines)); break
PY
  ( cd "$rd" && git diff --quiet -- OVERNIGHT_PROGRESS.md || {
      git add OVERNIGHT_PROGRESS.md
      git -c user.email=fleet@shrike.local -c user.name=shrike-fleet commit -q -m "chore(queue): mark staged T$tier item ($passed/$NSTEPS) so it isn't re-run"
      git push -q origin overnight/feature 2>/dev/null || { git pull -q --rebase origin overnight/feature && git push -q origin overnight/feature; }; } )
  ./queue.sh release "$repo" >/dev/null 2>&1
elif [ "$passed" -eq 0 ] && [ -z "$item_arg" ]; then
  # ESCALATE: the staged pipeline (retries + re-decomp + target-fn context) landed NOTHING — this is
  # genuinely beyond the 27B (usually a wire-into-a-complex-existing-function). Stop looping the fleet
  # on it: tag it for Claude so the Mac bridge harvests it to the Claude queue.
  ./queue.sh hold "$repo" >/dev/null 2>&1
  ( cd "$rd" && git fetch -q origin overnight/feature && git reset -q --hard origin/overnight/feature ) 2>/dev/null
  OVN_F="$rd/OVERNIGHT_PROGRESS.md" OVN_ITEM="$item" python3 - <<'PY'
import os
f=os.environ["OVN_F"]; item=os.environ["OVN_ITEM"]; key=item[:55]
lines=open(f,encoding="utf-8").read().split("\n")
for i,ln in enumerate(lines):
    if ln.startswith("- [ ] ") and key and key in ln and "[CLAUDE]" not in ln:
        lines[i]=ln.replace("- [ ] ","- [ ] [AUTO-SKIP staged: 27B could not land this (beyond it) — route to CLAUDE] ",1)
        open(f,"w",encoding="utf-8").write("\n".join(lines)); break
PY
  ( cd "$rd" && git diff --quiet -- OVERNIGHT_PROGRESS.md || {
      git add OVERNIGHT_PROGRESS.md
      git -c user.email=fleet@shrike.local -c user.name=shrike-fleet commit -q -m "chore(queue): escalate staged T$tier item to Claude (27B couldn't land it)"
      git push -q origin overnight/feature 2>/dev/null || { git pull -q --rebase origin overnight/feature && git push -q origin overnight/feature; }; } )
  ./queue.sh release "$repo" >/dev/null 2>&1
  say "escalated to Claude (staged pipeline landed 0/$NSTEPS — beyond the 27B)"
fi

pct=$(( NSTEPS>0 ? 100*passed/NSTEPS : 0 ))
say "DONE: $passed/$NSTEPS steps landed (${pct}%) for T$tier item. log: $SLOG"
jlog "$(jq -nc --arg r "$RUNID" --argjson p "$passed" --argjson n "$NSTEPS" --argjson t "$tier" --argjson vf "$VERIFIED" '{run:$r,event:"summary",tier:$t,passed:$p,total:$n,verified:($vf==1),commits_pushed:'"${ncommits:-0}"'}')"
