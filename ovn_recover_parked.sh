#!/usr/bin/env bash
# ovn_recover_parked.sh — parked items must not be orphaned forever. When an item has been AUTO-SKIP
# parked (the fleet tried it N cycles and kept reverting/no-op'ing), don't just leave it: ask the 27B
# to either BREAK IT DOWN into 2-4 smaller, independently-landable sub-items, or declare it
# already-done / genuinely-beyond-the-fleet (-> route to Claude). Replaces the one stuck item with the
# smaller pieces (tagged so a human can review), giving the work a real path to completion.
#
# This is the "parked -> retry-able" recovery loop. Runs on a cron; conservative (a few per run).
# Cron: 25 */2 * * *  cd ~/overnight-queue && ./ovn_recover_parked.sh >> logs/ovn_recover_parked.log 2>&1
set -uo pipefail
cd "$HOME/overnight-queue" || exit 1
export PATH=/usr/local/bin:/usr/bin:/bin:${PATH:-}
LITELLM="${LITELLM_BASE:-http://localhost:4000}"; LITELLM_KEY="${LITELLM_MASTER_KEY:-sk-shrike-local}"
MODEL="${OVN_MODEL:-qwen-dflash-27B}"
MAX_PER_RUN="${OVN_RECOVER_MAX:-4}"      # decompose at most this many parked items per pass (cost control)
REPOS="${*:-billwatch gitlark iptv_apps test-automation-agent xlite shrike-notify shrike-monitor}"
LOG="logs/ovn_recover_parked.log"; say(){ echo "$(date '+%F %T') $*" >> "$LOG"; }
did=0

for r in $REPOS; do
  [ "$did" -ge "$MAX_PER_RUN" ] && break
  f="repos/$r/OVERNIGHT_PROGRESS.md"; [ -f "$f" ] || continue
  rd="repos/$r"
  # first parked item that hasn't already been through recovery. Matches BOTH the current
  # [AUTO-SKIP...] tag AND the retired [HUMAN-ONLY BLOCKED ITEM...] wording an older
  # ovn_item_guard.sh used to emit - items still carrying that old tag (never migrated) were
  # otherwise invisible here, so a repo whose parked items happened to predate the wording
  # change got ZERO automated recovery forever while its budget silently went to other repos
  # every single run (confirmed live: test-automation-agent, 2026-09-11).
  parked_line="$(grep -nE '^- \[ \] \[(AUTO-SKIP|HUMAN-ONLY BLOCKED ITEM)' "$f" 2>/dev/null | grep -v 'recovery:' | head -1)"
  [ -z "$parked_line" ] && continue
  lnno="${parked_line%%:*}"
  # the real task text = strip the leading [AUTO-SKIP ...] / [HUMAN-ONLY BLOCKED ITEM ...] tag
  task="$(printf '%s' "${parked_line#*:}" | sed -E 's/^- \[ \] \[(AUTO-SKIP|HUMAN-ONLY BLOCKED ITEM)[^]]*\][[:space:]]*//')"
  [ "${#task}" -lt 15 ] && continue

  # compact layout for grounding (reuse real paths)
  layout="$(cd "$rd" 2>/dev/null && find . -maxdepth 4 \( -name '*.py' -o -name '*.ts' -o -name '*.tsx' -o -name '*.vue' -o -name '*.gd' \) \
              -not -path '*/node_modules/*' -not -path '*/.venv/*' -not -path '*/.godot/*' 2>/dev/null | sed 's#^\./##' | sort | head -80)"

  read -r -d '' PROMPT <<PROMPT_END || true
An autonomous coding fleet (a 27B model driving aider) tried this item repeatedly and kept failing
(reverting or making no change). Your job: make it COMPLETABLE. Choose ONE:

REPO: $r
Real source paths (reuse EXACTLY, do not invent):
$layout

STUCK ITEM:
$task

Decide and output ONLY one of these two forms — no prose, no preamble:

1) If it can be broken into smaller independently-landable steps, output 2 to 4 lines, each:
- [ ] [T<1-3>] <real/path.ext> — <ONE tiny precise change> VERIFY: <exact test/command that proves it>. (cat:<category>; recovery:decomposed)
   Rules: each step MUST be smaller/simpler than the original, use ONLY real paths above, be self-verifying,
   and prefer a NEW pure function + its own unit test (which is the fleet's strongest capability). For a
   test-writing step, assert on INVARIANTS/PROPERTIES (monotonic, bounded, idempotent, type) NOT a guessed
   exact numeric value — guessing exact expected outputs is the #1 way the fleet fails a test it wrote.

2) If it is already satisfied, or genuinely needs a human / is beyond a small local model (multi-file
   refactor, real product/design decision, external creds), output EXACTLY one line:
- [ ] [CLAUDE] <one-line why it needs Claude/human> (recovery:escalated)
PROMPT_END

  say "$r: recovering parked item: ${task:0:80}"
  body="$(python3 -c "import json,sys;print(json.dumps({'model':'$MODEL','messages':[{'role':'user','content':sys.stdin.read()}],'temperature':0.3,'max_tokens':900}))" <<<"$PROMPT")"
  resp="$(curl -fsS --max-time 180 "$LITELLM/v1/chat/completions" -H 'Content-Type: application/json' -H "Authorization: Bearer $LITELLM_KEY" -d "$body" 2>>"$LOG" \
          | jq -r '.choices[0].message.content // empty' 2>>"$LOG")"
  items="$(printf '%s\n' "$resp" | grep -E '^- \[ \] (\[T[1-3]\].+VERIFY:|\[CLAUDE\])' | head -4)"
  cnt=$(printf '%s' "$items" | grep -c '^- \[ \]')
  if [ "${cnt:-0}" -lt 1 ]; then
    say "$r: 27B gave no usable recovery for this item — leaving parked, tagging so we don't retry it forever"
    # tag the parked line so the NEXT run picks a different parked item (avoids looping on one hard item)
    ./queue.sh hold "$r" >/dev/null 2>&1
    ( cd "$rd" && git fetch -q origin overnight/feature && git reset -q --hard origin/overnight/feature ) 2>/dev/null
    sed -i -E "${lnno}s/\[(AUTO-SKIP|HUMAN-ONLY BLOCKED ITEM)/[\1 recovery:none/" "$f" 2>/dev/null
    ( cd "$rd" && git add OVERNIGHT_PROGRESS.md && git -c user.email=fleet@shrike.local -c user.name=shrike-fleet commit -q -m "chore(queue): mark $r parked item recovery-attempted (no decomposition)" && git push -q origin overnight/feature 2>/dev/null || true )
    ./queue.sh release "$r" >/dev/null 2>&1
    continue
  fi
  # replace the stuck parked line with the recovered sub-items (hold-safe + push)
  ./queue.sh hold "$r" >/dev/null 2>&1
  ( cd "$rd" && git fetch -q origin overnight/feature && git reset -q --hard origin/overnight/feature ) 2>/dev/null
  # re-find the line (it may have shifted after the reset)
  lnno2="$(grep -nE '^- \[ \] \[(AUTO-SKIP|HUMAN-ONLY BLOCKED ITEM)' "$f" | grep -v 'recovery:' | head -1)"; lnno2="${lnno2%%:*}"
  if [ -n "$lnno2" ]; then
    # pass items + header via FILES (never interpolate multi-line data into python source)
    items_file="$(mktemp)"; printf '%s\n' "$items" > "$items_file"
    hdr_file="$(mktemp)"; printf '# --- recovered from a parked item [%s]: %s (review) ---\n' "$(date '+%F')" "${task:0:70}" > "$hdr_file"
    OVN_F="$f" OVN_LN="$lnno2" OVN_ITEMS="$items_file" OVN_HDR="$hdr_file" python3 - <<'PY'
import os
f, ln = os.environ["OVN_F"], int(os.environ["OVN_LN"])
items = [l for l in open(os.environ["OVN_ITEMS"], encoding="utf-8").read().split("\n") if l.strip()]
hdr = open(os.environ["OVN_HDR"], encoding="utf-8").read().rstrip("\n")
lines = open(f, encoding="utf-8").read().split("\n")
orig = lines[ln-1]
# check off the stuck item + annotate; insert the recovered sub-items right after it
lines[ln-1] = orig.replace("- [ ] ", "- [x] ", 1) + "  <!-- superseded by recovery decomposition below -->"
lines[ln:ln] = [""] + [hdr] + items
open(f, "w", encoding="utf-8").write("\n".join(lines))
PY
    rm -f "$items_file" "$hdr_file"
    ( cd "$rd" && git add OVERNIGHT_PROGRESS.md && git -c user.email=fleet@shrike.local -c user.name=shrike-fleet commit -q -m "feat(queue): recover parked $r item -> ${cnt} smaller sub-item(s)" && { git push -q origin overnight/feature 2>/dev/null || { git pull -q --rebase origin overnight/feature && git push -q origin overnight/feature; }; } )
    say "$r: replaced parked item with ${cnt} recovered sub-item(s)"
    did=$((did+1))
  fi
  ./queue.sh release "$r" >/dev/null 2>&1
done
say "recover-parked pass complete (recovered $did this run)"
