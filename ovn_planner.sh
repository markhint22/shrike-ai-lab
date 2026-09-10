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
  [ -z "$feat_line" ] && { say "$r: backlog low ($bcount) but no [ready] roadmap feature (needs Claude research?)"; continue; }
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
  resp="$(curl -fsS --max-time 180 "$LITELLM/v1/chat/completions" -H 'Content-Type: application/json' -H "Authorization: Bearer $LITELLM_KEY" -d "$body" 2>>"$LOG" \
          | jq -r '.choices[0].message.content // empty' 2>>"$LOG")"
  # keep only well-formed item lines
  items="$(printf '%s\n' "$resp" | grep -E '^- \[ \] \[T[1-5]\] .+ VERIFY: ' | head -12)"
  n=$(printf '%s' "$items" | grep -c '^- \[ \]')
  if [ "${n:-0}" -lt 3 ]; then
    say "$r: 27B produced only ${n} valid items — NOT appending (needs Claude review of the prompt/feature)"
    continue
  fi
  {
    echo ""
    echo "# --- 27B-decomposed from roadmap [$(date '+%F')]: ${feat:0:90} (review + tweak) ---"
    printf '%s\n' "$items"
  } >> "$bl"
  # mark the feature decomposed in the roadmap
  sed -i "${fln}s/\[ready\]/[decomposed]/" "$rm"
  say "$r: appended ${n} 27B-decomposed items to backlog; marked feature [decomposed]"
  _did=$((_did+1))
done
