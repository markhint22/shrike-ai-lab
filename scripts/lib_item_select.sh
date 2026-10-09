#!/usr/bin/env bash
# scripts/lib_item_select.sh — shared "which item did this cycle actually work on" resolver.
#
# 2026-09-28 ROOT CAUSE: every "find the real top item" selector in this pipeline
# (ovn_item_guard.sh's own cap-tracking selector, run_overnight.sh's record_outcome()
# item_hash, and several others) independently re-grepped OVERNIGHT_PROGRESS.md's literal
# TOPMOST unchecked line as a proxy for "the item this cycle worked on". That's the right
# thing for the scout PROMPT (which tells the model to pick the top undone item itself,
# before anything is known about what it will actually do) but wrong for anything that runs
# AFTER the cycle and needs to know what was ACTUALLY attempted — the model's own choice, a
# mid-cycle checkbox flip, or wording drift between the roadmap line and what the scout named
# can all make "literal top line, re-read fresh" diverge from "the item the fleet just spent
# a cycle on". Confirmed live on test-automation-agent: one item failed 8 times across 2
# hours while state/item_fails/ongoing-<repo>.count stayed at 1 the entire time, because the
# guard kept hashing whatever unrelated item happened to be topmost that cycle instead of the
# one actually retried — completely decoupling the consecutive-fail auto-skip and the
# grounded-failure-memory safety net from reality.
#
# The one piece of real per-cycle ground truth that already exists is the scout's own FILES:
# answer, recorded in that cycle's task_log (run_overnight.sh already extracts this as
# OVN_SCOUT_FILES for cycle_summary.log + ALREADY-DONE auto-crediting — proven, live logic,
# not a new invention). Reuse it here: if the task_log names a file the model said it would
# work on, and that file appears verbatim in an undone, non-escalated OVERNIGHT_PROGRESS.md
# line, THAT line — not the literal top-of-file line — is "the item". Falls back to the
# plain top-of-file line when there's no usable scout signal (empty/missing task_log, a cheap
# ALREADY-DONE/BLOCKED short-circuit with no FILES: line, or a scouted file that doesn't
# literally appear in the progress file) — i.e. exactly the prior behavior, unchanged.
#
# Usage: source this file, then:
#   line="$(ovn_resolve_top_item "$repo_dir" "$task_log")"   # empty if nothing doable
#   lineno="${line%%:*}"; text="${line#*:}"
# ($task_log is optional — omit it, or pass a nonexistent path, to get the old
#  top-of-file-only behavior verbatim.)
# ---------------------------------------------------------------------------------------------------------------------------------
# BUGS FIRST (2026-10-02, branch qa/h8-bug-first). DECISION FROM MARK: quality over new development. A bug he logged while testing by hand
# (qa/manual_logs -> qa-notes-bridge -> qa/manual_notes_ingest.py) is an open line tagged 'Manual-test bug (reported by Mark ... src:manual)'
# with a [feat:<repo>-<date>-manual-<8 hex id>[.rN]] tag (a decomposed multi-step brief shares that one tag across its step lines). It must be
# worked RIGHT AWAY, ahead of every roadmap / refill / self-gen item, and while one is open that repo's lane works ONLY bug items.
#
# ONE ordering, enforced where the loop actually SELECTS (not where items are inserted): every selector that answers "which open item is next"
# (ovn_resolve_top_item below, run_overnight.sh's prompt peek / delete-executor peek / the 'Doable Next Steps' slice the scout is shown /
# the inline T3+ stage trigger / the stage runner's own pick) pipes its already-filtered doable lines through ovn_bug_first_order. Insertion order
# alone cannot be trusted (queue_refill appends at the END of the file, the ingest inserts at the top of '## Next Steps', a deploy EMERGENCY goes
# above everything, the planner/stage runner/hygiene rewrite the file) - so selection decides, and every selector agrees.
#   EMERGENCY lines  keep their precedence: they stay first, in file order.
#   bug lines        next, in file order.
#   everything else  DROPPED while a bug is open (lane focus; OVN_BUG_FOCUS=off keeps them after the bugs instead).
# A parked/escalated bug never reaches this filter (callers already exclude AUTO-SKIP/HUMAN-ONLY/BLOCKED/[CLAUDE]) so it stops counting as "open"
# and the lane goes back to normal work. With NO bug line in the input the filter is a pure pass-through (byte-for-byte the old behaviour), and
# OVN_BUG_FIRST=off is a kill switch that makes it a pass-through always.
#
#   ovn_is_manual_bug_text "<line text>"    -> 0 when the text is a manual-test bug item
#   <lines> | ovn_bug_first_order           -> reorders/narrows as above (stdin lines may carry a 'N:' grep -n prefix)
#   <lines> | ovn_has_bug_line              -> 0 when any input line is a manual-test bug
#   ovn_open_bug_count <repo_dir>           -> number of open, not-parked manual bugs in <repo_dir>/OVERNIGHT_PROGRESS.md
# spec-compiler-v2 (2026-10-09): the parked-line patterns live in ONE place (lib_parked_pattern.sh; twin of ovn_backlog_eligibility.py). BLOCKED is a
# case-sensitive TAG - the old case-insensitive `grep -viE '...|BLOCKED|...'` parked every line that merely contained the word "blocked" (all 10 open iptv_apps
# items). Inline fallback (identical values) for a deployment that has not got the library yet.
_LIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
[ -f "$_LIS_DIR/lib_parked_pattern.sh" ] && . "$_LIS_DIR/lib_parked_pattern.sh"
: "${OVN_PARKED_CI_ERE:=AUTO-SKIP|HUMAN-ONLY|human/|HARD FILE BAN|\[CLAUDE\]}"
: "${OVN_PARKED_CS_ERE:=BLOCKED}"
[ "${OVN_PARKED_BLOCKED_CI:-off}" = on ] && [ -z "${_LIS_BLOCKED_CI_DONE:-}" ] && { OVN_PARKED_CI_ERE="$OVN_PARKED_CI_ERE|BLOCKED"; _LIS_BLOCKED_CI_DONE=1; }   # kill switch: legacy case-insensitive BLOCKED (idempotent)
ovn_is_manual_bug_text() {
  [ "${OVN_BUG_FIRST:-on}" = off ] && return 1
  printf '%s' "${1:-}" | grep -qE '\[feat:[^]]*-manual-[0-9a-f]{8}(\.r[0-9]+)?\]|Manual-test bug \(reported by Mark.*src:manual'
}
ovn_has_bug_line() {
  [ "${OVN_BUG_FIRST:-on}" = off ] && return 1
  grep -qE '\[feat:[^]]*-manual-[0-9a-f]{8}(\.r[0-9]+)?\]|Manual-test bug \(reported by Mark.*src:manual'
}
ovn_bug_first_order() {
  if [ "${OVN_BUG_FIRST:-on}" = off ]; then cat; return; fi
  # The whole input is read and the result captured BEFORE anything is written: callers pipe this into `grep -q` / `head -1` under
  # `set -o pipefail`, and a reader that exits early must not turn into SIGPIPE/EPIPE (a non-zero stage status that pipefail reports as "no match").
  local out
  out="$(awk -v focus="${OVN_BUG_FOCUS:-on}" '
    function isbug(s) { return (s ~ /\[feat:[^]]*-manual-[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f](\.r[0-9]+)?\]/) || (index(s, "Manual-test bug (reported by Mark") > 0 && index(s, "src:manual") > 0) }
    { a[NR] = $0; b[NR] = isbug($0); nb += b[NR] }
    END {
      if (!nb) { for (i = 1; i <= NR; i++) print a[i]; exit }
      for (i = 1; i <= NR; i++) if (!b[i] && index(a[i], "EMERGENCY") > 0) print a[i]
      for (i = 1; i <= NR; i++) if (b[i]) print a[i]
      if (focus == "off") for (i = 1; i <= NR; i++) if (!b[i] && index(a[i], "EMERGENCY") == 0) print a[i]
    }')"
  [ -n "$out" ] || return 0
  ( trap '' PIPE; printf '%s\n' "$out" 2>/dev/null )
  return 0
}
ovn_open_bug_count() {
  local prog="${1:-.}/OVERNIGHT_PROGRESS.md"
  [ -f "$prog" ] || { printf '0'; return 0; }
  [ "${OVN_BUG_FIRST:-on}" = off ] && { printf '0'; return 0; }
  grep -E '^- \[ \]' "$prog" 2>/dev/null | grep -viE "$OVN_PARKED_CI_ERE|\(retired-" | grep -vE "$OVN_PARKED_CS_ERE" \
    | grep -cE '\[feat:[^]]*-manual-[0-9a-f]{8}(\.r[0-9]+)?\]|Manual-test bug \(reported by Mark.*src:manual' || true
}

ovn_resolve_top_item() {
  local repo_dir="$1" task_log="${2:-}"
  local prog="$repo_dir/OVERNIGHT_PROGRESS.md"
  [ -f "$prog" ] || return 0
  local scouted f top
  if [ -n "$task_log" ] && [ -f "$task_log" ]; then
    # Same extraction as run_overnight.sh's OVN_SCOUT_FILES: the scout's VERDICT line + next 4
    # wrapped lines (a 27B's VERDICT/PLAN/FILES answer is one logical reply the terminal wraps
    # across ~3 lines) plus any FILES: line, harvested for real repo-file-shaped tokens.
    scouted="$( { grep -A4 -hiE "VERDICT:[[:space:]]*(PROCEED|NEEDS-DECISION)" "$task_log" 2>/dev/null; grep -hiE "FILES:" "$task_log" 2>/dev/null; } \
                | grep -oE "[A-Za-z0-9_./-]+\.[A-Za-z0-9]{1,8}" | grep -vE "\.md$" | sort -u)"
    while IFS= read -r f; do
      [ -z "$f" ] && continue
      top="$(grep -nE '^- \[ \]' "$prog" 2>/dev/null | grep -viE "$OVN_PARKED_CI_ERE" | grep -vE "$OVN_PARKED_CS_ERE" | ovn_bug_first_order | grep -F -- "$f" | head -1)"
      if [ -n "$top" ]; then
        printf '%s' "$top"
        return 0
      fi
    done <<< "$scouted"
  fi
  # Fallback: no task_log, no scout signal, or the scouted file isn't literally in the
  # progress file — the original top-of-file behavior, unchanged.
  top="$(grep -nE '^- \[ \]' "$prog" 2>/dev/null | grep -viE "$OVN_PARKED_CI_ERE" | grep -vE "$OVN_PARKED_CS_ERE" | ovn_bug_first_order | head -1)"
  printf '%s' "$top"
}

# ovn_item_hash — shared "identity" hash for an item's line text (2026-09-29).
#
# Both ovn_item_guard.sh (fail/no-op streak keys) and run_overnight.sh (record_outcome's
# item_hash + the lastfail-memory lookup) need to answer "is this the SAME item as last
# time" from a line's text. Before this, each independently re-implemented the featkey
# extraction/date-strip, and drifted: ovn_item_guard.sh picked up the 2026-09-28 date-strip
# fix (a [feat:...] tag's embedded YYYYMMDD/MMDDYY stamp changes every roadmap regeneration
# of the SAME underlying feature, so stripping it before hashing collapses regenerations onto
# one streak) but run_overnight.sh's lastfail lookup never did, so it hashed the RAW top-line
# text while the producer hashed the (stripped) feat-tag — the two could never agree for any
# feat-tagged item, silently disabling the grounded-failure-memory injection for exactly the
# multi-line-feature case it was built for. One function, one algorithm, sourced by both.
#
# Normalizes away a leading "- [ ] "/"- [x] "/"- [X] " checkbox marker first (a no-op for
# text that never had one), so a caller with the raw "grep -n" line (checkbox included, e.g.
# ovn_item_guard.sh's own $text) and a caller with just the bare item text (e.g. a "+- [x] "
# diff line, or ovn_stage_runner.sh's checkbox-stripped $item) hash to the SAME value for the
# same underlying item regardless of which checkbox state or calling convention was used.
#
# Usage: h="$(ovn_item_hash "$text")"   # $text = the line text, e.g. "${top#*:}"
ovn_item_hash() {
  local text featkey
  text="$(printf '%s' "${1:-}" | sed -E 's/^- \[[ xX]\] //')"
  featkey="$(printf '%s' "$text" | grep -oE '\[feat:[^]]+\]' | head -1)"
  if [ -n "$featkey" ]; then
    featkey="$(printf '%s' "$featkey" | sed -E 's/-[0-9]{8}-/-/; s/-[0-9]{6}-/-/')"
    printf '%s' "$featkey" | md5sum | cut -d' ' -f1
  else
    printf '%s' "$text" | md5sum | cut -d' ' -f1
  fi
}

# ovn_is_schema_item / ovn_schema_budget - per-category attempt budget (2026-10-02).
#
# MEASURED on the box (state/outcomes.jsonl, 16.5k rows 2026-09-07..10-02, plus the repos' OVERNIGHT_PROGRESS.md AUTO-SKIP tags):
#   * 33 of 600 AUTO-SKIPped items are schema/migration/model items (path under alembic|migrations|models|schemas, or cat:schema); 16 of
#     those 33 were parked by the 200k TOKEN cap after only ~2 cycles (avg 32/16), 15 by the 4-cycle fail cap, 2 by the no-op cap - i.e.
#     the budget that bites is spend, not attempt count. (Non-schema: 243/567 token-cap, avg 2.25 cycles - same shape, so the evidence for a
#     *bigger* budget is the convergence below, not the cap mix.)
#   * 71 schema-tagged item hashes: 46 landed eventually, 25 never did; 5 hit best-of-N exhaustion (attempt>=3 not landed), 2 reached >=4 bad cycles.
#   * the live case (gitlark control-plane/oauth item, 2026-10-02 07:59-08:42): consecutive staged attempts' VERIFY went 195 failed + 292 errors
#     -> 14 failed -> 1 failed (test_github_oauth_stores_token), then no-op(stage-unverified) with best-of-N 3/3 spent - converging work thrown away
#     one attempt short. A schema/model change fans out into many tests, so each attempt legitimately needs more spend and more attempts.
# So schema-tagged items get a bigger budget; EVERYTHING ELSE keeps the exact existing defaults. Per-kind absolute override env wins, else the
# relative default below; OVN_SCHEMA_BUDGET=off disables the whole thing (all items back to the base budget).
#   kind     base source            schema default            override env
#   bestn    OVN_BESTOF_N (>1 only)  base + 2                  OVN_BESTOF_N_SCHEMA
#   failcap  OVN_ITEM_FAIL_CAP       base + 2                  OVN_ITEM_FAIL_CAP_SCHEMA
#   tokcap   OVN_ITEM_TOKEN_CAP      base * 2                  OVN_ITEM_TOKEN_CAP_SCHEMA
#   noopcap  OVN_ITEM_NOOP_CAP       base (unchanged)          OVN_ITEM_NOOP_CAP_SCHEMA   (only 2/33 schema parks were no-op-cap; no convergence signal in a no-op)
ovn_is_schema_item() {
  [ "${OVN_SCHEMA_BUDGET:-on}" = off ] && return 1
  # 2026-10-02: a Mark-reported manual bug NEVER gets the bigger schema budget (bugs-first policy: 2 attempts, then escalate to a Claude session);
  # a bigger budget would just keep the whole lane on one bug longer. OVN_BUG_FIRST=off restores the old behaviour.
  ovn_is_manual_bug_text "${1:-}" && return 1
  printf '%s' "${1:-}" | grep -qiE 'cat:schema|alembic|(^|[^A-Za-z0-9_])(migrations?|models?|schemas?)/|(^|/)(models?|schemas?)\.py|[^A-Za-z]migration'
}
# usage: v="$(ovn_schema_budget <bestn|failcap|tokcap|noopcap> <base> "<item text>")"   -> base unless the item is schema-tagged
ovn_schema_budget() {
  local kind="${1:-}" base="${2:-0}" text="${3:-}" ov
  ovn_is_schema_item "$text" || { printf '%s' "$base"; return 0; }
  case "$kind" in
    bestn)   ov="${OVN_BESTOF_N_SCHEMA:-}";       [ -n "$ov" ] && { printf '%s' "$ov"; return 0; }; [ "$base" -gt 1 ] && printf '%s' $((base + 2)) || printf '%s' "$base";;
    failcap) ov="${OVN_ITEM_FAIL_CAP_SCHEMA:-}";  [ -n "$ov" ] && { printf '%s' "$ov"; return 0; }; printf '%s' $((base + 2));;
    tokcap)  ov="${OVN_ITEM_TOKEN_CAP_SCHEMA:-}"; [ -n "$ov" ] && { printf '%s' "$ov"; return 0; }; printf '%s' $((base * 2));;
    noopcap) ov="${OVN_ITEM_NOOP_CAP_SCHEMA:-}";  [ -n "$ov" ] && { printf '%s' "$ov"; return 0; }; printf '%s' "$base";;
    *)       printf '%s' "$base";;
  esac
}

# ---------------------------------------------------------------------------------------------------------------------------------------------
# Deterministic-failure awareness for best-of-N and the per-item guard (2026-10-02, harness Y1).
#
# MEASURED (iptv_apps 'Add last_event_ms column', 2026-10-02 14:50-15:57 CDT): ~9 model attempts in 65 minutes, 0 landed. Best-of-N 5 (the
# schema budget deployed that morning) ran 5 inner attempts in ONE outcome row: attempt 1 forked the Alembic chain, 2-4 were test_migration_drift
# red, 5 forked again. A failure that is DETERMINISTIC (the same drift test / the same forked chain / the same failing test ids) repeated
# identically is not bad luck, so extra samples only burn GPU. Two pure helpers + one circuit breaker, all log-derived (no model, no network):
#   ovn_attempt_signature <status> <log>     -> "migration-drift" for a migration-chain failure, else empty
#   ovn_failing_ids <log>                    -> the sorted, de-duplicated pytest FAILED/ERROR test ids (one per line), empty when none
#   ovn_bestn_after_failure <bestn> <sig>    -> the best-of-N budget to use once the previous attempt failed with <sig>
#   ovn_repeat_streak <prev_key> <cur_key> <streak> -> new consecutive-identical-failure streak
# Kill switches: OVN_BESTOF_N_DRIFT_CAP=0 (disable the drift cap), OVN_REPEAT_BREAKER=off (disable the repeat breaker).
# ---------------------------------------------------------------------------------------------------------------------------------------------
ovn_attempt_signature() {
  local status="${1:-}" log="${2:-}"
  case "$status" in *migration-fork*) printf 'migration-drift'; return 0;; esac
  [ -f "$log" ] || return 0
  # The ACTUAL failure, not a mention: a log that merely names the drift test ("Added tests/test_migration_drift.py to the chat", a prompt echo, a file
  # list) is not a drift failure. Accepted: a pytest FAILED/ERROR line for the drift test (summary or -v form), the drift AssertionError text, or the gate's own messages.
  if grep -qE '^(FAILED|ERROR) [^ ]*test_migration_drift|test_migration_drift[^ ]* (FAILED|ERROR)|Migration drift detected|MIGRATION-SAFETY GATE|MULTIPLE HEADS' "$log" 2>/dev/null; then
    printf 'migration-drift'
  fi
}

ovn_failing_ids() {
  local log="${1:-}"
  [ -f "$log" ] || return 0
  # pytest short summary ("FAILED tests/x.py::t - msg", "ERROR tests/x.py::t - msg"); keep only the node id
  grep -hoE '^(FAILED|ERROR) [^ ]+' "$log" 2>/dev/null | sed -E 's/^(FAILED|ERROR) //' | sort -u
}

ovn_bestn_after_failure() {
  local bestn="${1:-1}" sig="${2:-}" cap="${OVN_BESTOF_N_DRIFT_CAP:-2}"
  if [ "$sig" = "migration-drift" ] && [ "$cap" -gt 0 ] 2>/dev/null && [ "$bestn" -gt "$cap" ]; then
    printf '%s' "$cap"
  else
    printf '%s' "$bestn"
  fi
}

# usage: s="$(ovn_repeat_streak "<prev key>" "<cur key>" <streak>)"  -> 1 when the keys differ / are empty, else streak+1.
# A key is "<item hash>|<failing-id md5>"; callers pass an EMPTY key when there is nothing to compare (no ids, > OVN_REPEAT_MAX_IDS ids).
ovn_repeat_streak() {
  local prev="${1:-}" cur="${2:-}" streak="${3:-1}"
  if [ -n "$cur" ] && [ "$prev" = "$cur" ]; then printf '%s' $((streak + 1)); else printf '1'; fi
}

# usage: k="$(ovn_repeat_key <item hash> <log> [<repo dir> <state dir>])" -> "<hash>|<md5 of ids>" or empty. Many failing ids (> OVN_REPEAT_MAX_IDS,
# default 20) means a baseline/env break touching the whole suite, not something this item's attempt repeats - never a breaker signal.
# With <repo dir> + <state dir> (Y-e) ids that are red at the repo's baseline (qa/baseline_verify.py store) do not count, and with no active baseline
# ids that also failed on the previous item's last attempt do not count (scripts/ovn_repeat_ids.py); nothing left -> empty key.
ovn_repeat_key() {
  local h="${1:-}" log="${2:-}" rdir="${3:-}" sdir="${4:-}" ids n helper
  [ "${OVN_REPEAT_BREAKER:-on}" = off ] && return 0
  ids="$(ovn_failing_ids "$log")"
  [ -n "$ids" ] || return 0
  n="$(printf '%s\n' "$ids" | wc -l | tr -d ' ')"
  [ "$n" -le "${OVN_REPEAT_MAX_IDS:-20}" ] || return 0
  helper="$(dirname "${BASH_SOURCE[0]}")/ovn_repeat_ids.py"
  if [ -n "$rdir" ] && [ -n "$sdir" ] && [ -f "$helper" ]; then
    ids="$(printf '%s\n' "$ids" | python3 "$helper" filter "$(basename "$rdir")" "$sdir" "$h" 2>/dev/null)"
    [ -n "$ids" ] || return 0
  fi
  printf '%s|%s' "$h" "$(printf '%s' "$ids" | md5sum | cut -d' ' -f1)"
}

# usage: ovn_repeat_basis <repo dir> <state dir> -> "baseline" | "previous-item" (which rule ovn_repeat_key used), for the park note
ovn_repeat_basis() {
  local helper; helper="$(dirname "${BASH_SOURCE[0]}")/ovn_repeat_ids.py"
  [ -f "$helper" ] && python3 "$helper" basis "$(basename "${1:-x}")" "${2:-/nonexistent}" 2>/dev/null
}
# usage: ovn_repeat_record <repo dir> <state dir> <item hash> <log> - remember this attempt's failing ids (the "previous item" memory)
ovn_repeat_record() {
  local helper; helper="$(dirname "${BASH_SOURCE[0]}")/ovn_repeat_ids.py"
  [ -f "$helper" ] || return 0
  ovn_failing_ids "${4:-}" | python3 "$helper" record "$(basename "${1:-x}")" "${2:-}" "${3:-}" 2>/dev/null
  return 0
}

# ---------------------------------------------------------------------------------------------------------------------------------------------
# "model/API error" classifier (2026-10-02, harness Y3).
#
# run_overnight.sh used to label ANY log containing "Traceback (most recent call last)" as error(model/API error). iptv_apps row 17Z 2026-10-02
# was aider's own lint output for the model's IndentationError ("# Fix any errors below, if possible." + a python traceback + flake8 output): not an
# API failure at all, but it was bucketed error/neutral instead of the real flail it was, and (via ovn_classify_fail.sh) model-api-error.
# Consumers of the label: error_status() (a transient subset downgrades to error-transient), check_and_record_failure() (only reverted* counts toward
# the safety valve; error* falls in its reset-the-streak branch) and ovn_item_guard.sh - none of that changes for a REAL API error; only the lint
# false positive stops matching.
#   ovn_strip_lint_blocks <log>   stdout = the log without aider lint blocks ("# Fix any errors below" through the end of the block)
#   ovn_log_has_api_error <log>   exit 0 iff the log (minus lint blocks) carries a real API/transport marker
# A bare Traceback no longer counts; a Traceback does when its EXCEPTION line is an API/transport one (litellm.*, openai.*, httpx.*, ...).
# ---------------------------------------------------------------------------------------------------------------------------------------------
ovn_strip_lint_blocks() {
  local log="${1:-}"
  [ -f "$log" ] || return 0
  # A lint block runs from "# Fix any errors below" to its terminator. It is bounded in two ways so that a real API error can never be swallowed:
  #  - it ENDS (and the line is KEPT) at an unindented marker line: a litellm/openai/APIError/ContextWindowExceeded... line or a networking-library
  #    exception line (httpx.ConnectError ...). Indented/quoted source lines and flake8 path:line:col: lines (a lint block quoting `except APIError:`, F821 undefined name 'APIError') are not markers.
  #  - the usual terminators (Tokens:, Applied edit, Commit, ...) and a 120-line cap, as before.
  awk '
    function ismarker(l) {
      if (l ~ /^[ \t]/ || l ~ /^[^ ]+:[0-9]+(:[0-9]+)?:/ || index(l, "\342\226\210") || index(l, "\342\224\202") || index(l, "\342\213\256")) return 0
      if (l ~ /ContextWindowExceeded|BadRequestError|APIError|RateLimitError|APIConnectionError|APITimeoutError|ServiceUnavailableError|InternalServerError|litellm[.][A-Za-z]+(Error|Exception)|openai[.][A-Za-z]+Error|Connection (reset|aborted|refused)|ConnectionError|Read timed out|Max retries exceeded/) return 1
      if (l ~ /^(litellm|openai|httpx|httpcore|requests|urllib3|aiohttp|socket|ssl)[.A-Za-z_]*(Error|Exception|Timeout)/) return 1
      return 0
    }
    /Fix any errors below/ { skip = 1; n = 0; next }
    skip && ismarker($0) { skip = 0 }
    skip && (/^Tokens:/ || /^Applied edit/ || /^Commit [0-9a-f]+/ || /^Only [0-9]+ reflections/ || /^Attempt to fix/ || /^> / || /^Add .* to the chat/ || ++n > 120) { skip = 0 }
    !skip { print }
  ' "$log" 2>/dev/null
}

ovn_log_has_api_error() {
  local log="${1:-}" body
  [ -f "$log" ] || return 1
  body="$(ovn_strip_lint_blocks "$log")"
  [ -n "$body" ] || return 1
  # named API / transport exceptions anywhere in the (non-lint) output
  if grep -qE 'ContextWindowExceededError|BadRequestError|APIError|RateLimitError|APIConnectionError|APITimeoutError|ServiceUnavailableError|InternalServerError|litellm\.[A-Za-z]+(Error|Exception)|openai\.[A-Za-z]+Error|Connection (reset|aborted|refused)|ConnectionError|Read timed out|Max retries exceeded' <<< "$body"; then
    return 0
  fi
  # an unindented networking/LLM-library exception line (the tail of a transport traceback whose header a lint block may have swallowed)
  if grep -qE '^(litellm|openai|httpx|httpcore|requests|urllib3|aiohttp|socket|ssl)[.A-Za-z_]*(Error|Exception|Timeout)' <<< "$body"; then
    return 0
  fi
  # a traceback whose final exception line is an API/transport exception of a networking/LLM library
  printf '%s\n' "$body" | awk '
    /^Traceback \(most recent call last\)/ { tb = 1; next }
    tb && /^[[:space:]]/ { next }
    tb && NF { if ($0 ~ /^(litellm|openai|httpx|httpcore|requests|urllib3|aiohttp|socket|ssl)[.A-Za-z_]*(Error|Exception|Timeout)/) found = 1; tb = 0 }
    END { exit found ? 0 : 1 }
  '
}
