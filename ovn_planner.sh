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

# 2026-09-17: this state (roadmap fully [decomposed], zero [ready] features left to pull from) was
# found sitting SILENT for hours on gitlark+billwatch during a live audit -- the script logged
# 'needs Claude research?' every single cycle but never told a human, unlike queue_refill.sh's
# backlog-dry alert or queue_health.sh's low-doable alert. A repo can fully starve (roadmap
# exhausted -> backlog empties -> live queue empties) with zero ntfy signal that a Claude research
# pass (promote [needs-research] -> [ready] in roadmap/<repo>.md) is what's actually needed. Same
# dry/newly-dry/reminder/recovered marker pattern as queue_refill.sh's qr_dry_<repo>, scoped to
# THIS specific terminal state (not general backlog-low, which queue_refill already covers).
STATE_DIR="state"; mkdir -p "$STATE_DIR" 2>/dev/null
RESEARCH_REMIND_HOURS="${OVN_RESEARCH_REMIND_HOURS:-24}"
# same TOPIC-resolution pattern as queue_health.sh: explicit NTFY_TOPIC env (how cron invokes this
# script) or a persisted state/ntfy_topic, else empty -> alert() no-ops. Keeps a fresh test sandbox
# (no env var, no state file) from ever making a real network call.
NTFY_TOPIC_RESOLVED="${NTFY_TOPIC:-$(cat "$STATE_DIR/ntfy_topic" 2>/dev/null)}"
alert(){ [ -n "$NTFY_TOPIC_RESOLVED" ] && curl -fsS --max-time 8 -H "Title: $1" -H "Tags: $2" -d "$3" "https://ntfy.sh/$NTFY_TOPIC_RESOLVED" >/dev/null 2>&1; true; }
needs_research_alert(){ # $1=repo $2=backlog-count
  local r="$1" bc="$2" marker="$STATE_DIR/ovn_needs_research_${r}" now remind_secs last
  now=$(date +%s); remind_secs=$(( RESEARCH_REMIND_HOURS * 3600 ))
  if [ ! -f "$marker" ]; then
    echo "$now" > "$marker"
    alert "Roadmap exhausted: $r needs a Claude research pass" "books" "$r's roadmap/${r}.md has NO [ready] features left (all [decomposed]) and backlog/${r}.md is down to ${bc} item(s) -- the auto-planner can't make more work on its own. Promote a [needs-research] feature to [ready] (or add a new one) in roadmap/${r}.md to unstick it. (silent while still dry -- reminder repeats at most every ${RESEARCH_REMIND_HOURS}h)"
    say "$r: sent needs-research alert (new)"
  else
    last=$(cat "$marker" 2>/dev/null || echo "$now")
    if [ $(( now - last )) -ge "$remind_secs" ]; then
      echo "$now" > "$marker"
      alert "Still needs a Claude research pass: $r" "books" "Still no [ready] roadmap feature for $r after ${RESEARCH_REMIND_HOURS}h+. No rush -- periodic nudge."
      say "$r: sent needs-research reminder"
    fi
  fi
}
clear_research_alert(){ local r="$1" marker="$STATE_DIR/ovn_needs_research_${r}"; [ -f "$marker" ] && rm -f "$marker" && say "$r: needs-research condition cleared"; }
REPOS="${*:-billwatch gitlark iptv_apps test-automation-agent shrike-notify shrike-monitor xlite}"
MAX_PER_RUN="${OVN_PLAN_MAX_PER_RUN:-4}"   # cap decompositions per invocation so cycle-end never balloons
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
    say "$r: backlog low ($bcount) but no [ready] roadmap feature (needs Claude research?)"
    needs_research_alert "$r" "$bcount"
    continue
  fi
  fln="${feat_line%%:*}"
  feat="$(printf '%s' "${feat_line#*:}" | sed -E 's/^- \[ \] \[P[1-4]\] \[ready\] //')"

  # compact repo layout for context (key source files, capped)
  layout="$(cd "repos/$r" 2>/dev/null && find . -maxdepth 4 \( -name '*.py' -o -name '*.ts' -o -name '*.tsx' -o -name '*.vue' -o -name '*.gd' \) \
              -not -path '*/node_modules/*' -not -path '*/.venv/*' -not -path '*/.godot/*' 2>/dev/null | sed 's#^\./##' | sort | head -120)"
  [ -z "$layout" ] && { say "$r: no source layout found — skip"; continue; }

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
- category is one of: python, typescript, vue, godot, endpoint, schema, test, docs, refactor.
- No secrets, no deploy/DNS/keys (those are human tasks — skip them).
PROMPT_END

  say "$r: decomposing [ready] feature: ${feat:0:80}"
  body="$(python3 -c "import json,sys;print(json.dumps({'model':'$MODEL','messages':[{'role':'user','content':sys.stdin.read()}],'temperature':0.3,'max_tokens':1200}))" <<<"$PROMPT")"
  _raw="$(curl -fsS --max-time 180 "$LITELLM/v1/chat/completions" -H 'Content-Type: application/json' -H "Authorization: Bearer $LITELLM_KEY" -d "$body" 2>>"$LOG")"
  resp="$(printf '%s' "$_raw" | jq -r '.choices[0].message.content // empty' 2>>"$LOG")"
  # 2026-09-16: this runs HOURLY and its real token spend was discarded entirely - log it.
  bash "$HOME/overnight-queue/scripts/ovn_log_tokens.sh" planner "$r" \
    "$(printf '%s' "$_raw" | jq -r '.usage.prompt_tokens // 0' 2>/dev/null)" \
    "$(printf '%s' "$_raw" | jq -r '.usage.completion_tokens // 0' 2>/dev/null)" 2>/dev/null || true
  # keep only well-formed item lines
  items="$(printf '%s\n' "$resp" | grep -E '^- \[ \] \[T[1-5]\] .+ VERIFY: ' | head -12)"
  n=$(printf '%s' "$items" | grep -c '^- \[ \]')
  if [ "${n:-0}" -lt 3 ]; then
    say "$r: 27B produced only ${n} valid items — NOT appending (needs Claude review of the prompt/feature)"
    continue
  fi
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
