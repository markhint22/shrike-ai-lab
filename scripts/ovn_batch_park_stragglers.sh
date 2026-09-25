#!/usr/bin/env bash
# ovn_batch_park_stragglers.sh — daily cron wrapper (2026-09-25), the "handling"
# half of the letter-grade scorecard work: ovn_batch_scorecard.sh answers "how is
# the research pipeline doing" (reporting); this answers "is there still-open work
# under a batch that's ALREADY shown it's going to fail the same way, that will
# otherwise keep burning fleet cycles one item at a time until
# ovn_item_guard.sh's PER-ITEM cap catches each one individually?" and acts on it.
#
# Action taken is deliberately the SAME reversible pattern ovn_item_guard.sh
# already uses for a single misbehaving item, just triggered by a batch-level
# signal instead of a per-item streak: prepend an AUTO-SKIP marker (never delete,
# never touch code, checkbox stays unchecked) to the batch's remaining
# un-attempted items once the batch has shown a clear failure pattern (grade F,
# i.e. <25% landed, with at least 5 attempts already recorded and >=24h old — the
# same age floor as the scorecard). A quiet day with nothing to park sends no
# alert, matching every other alert-only-when-something-needs-attention script
# in this pipeline (ovn_fleet_health.sh, ovn_batch_scorecard.sh).
#
# Dedup: each batch tag is only ever processed ONCE (tracked in
# state/batch_stragglers_parked.txt) — a batch doesn't get re-parked every day
# just because it's still F-graded; a human who un-parks an item to give it
# another shot won't have it silently re-parked by tomorrow's run.
#
# Worktree-isolated per repo (scripts/lib_worktree.sh, matching the pipeline's
# Phase 2 hardening convention) so this never races the fleet's own live
# checkout while editing OVERNIGHT_PROGRESS.md.
set -uo pipefail
cd "$HOME/overnight-queue" || exit 1
export PATH=/usr/local/bin:/usr/bin:/bin:${PATH:-}
source scripts/lib_worktree.sh
LOG="logs/ovn_batch_park_stragglers.log"
say(){ echo "$(date '+%F %T') $*" >> "$LOG"; }
STATE_DIR="state"; mkdir -p "$STATE_DIR" 2>/dev/null
DEDUP="$STATE_DIR/batch_stragglers_parked.txt"; touch "$DEDUP"
NTFY_TOPIC_RESOLVED="${NTFY_TOPIC:-$(cat "$STATE_DIR/ntfy_topic" 2>/dev/null)}"
alert(){ [ -n "$NTFY_TOPIC_RESOLVED" ] && curl -fsS --max-time 8 -H "Title: $1" -H "Tags: $2" -d "$3" "https://ntfy.sh/$NTFY_TOPIC_RESOLVED" >/dev/null 2>&1; true; }

OUT="$(python3 scripts/ovn_batch_stragglers.py 2>>"$LOG")"
if [ -z "$OUT" ]; then
  say "no qualifying chronically-F batches with open stragglers"
  exit 0
fi

TOTAL_PARKED=0
SUMMARY=""
BATCH_JSON="$(mktemp)"
trap 'rm -f "$BATCH_JSON"' EXIT

while IFS= read -r line; do
  [ -z "$line" ] && continue
  tag="$(printf '%s' "$line" | python3 -c 'import json,sys; print(json.load(sys.stdin)["tag"])' 2>/dev/null)"
  [ -z "$tag" ] && { say "malformed line from ovn_batch_stragglers.py, skipping: $line"; continue; }
  if grep -qxF "$tag" "$DEDUP"; then
    continue
  fi
  repo="$(printf '%s' "$line" | python3 -c 'import json,sys; print(json.load(sys.stdin)["repo"])')"
  landed="$(printf '%s' "$line" | python3 -c 'import json,sys; print(json.load(sys.stdin)["landed"])')"
  ntotal="$(printf '%s' "$line" | python3 -c 'import json,sys; print(json.load(sys.stdin)["n"])')"
  pct="$(printf '%s' "$line" | python3 -c 'import json,sys; print(json.load(sys.stdin)["pct"])')"

  wt="$(wt_open "repos/$repo" overnight/feature)" || { say "wt_open FAILED for $repo/$tag"; continue; }
  printf '%s' "$line" > "$BATCH_JSON"
  parked="$(python3 scripts/ovn_batch_park_tagger.py "$wt/OVERNIGHT_PROGRESS.md" "$BATCH_JSON")"

  if [ "${parked:-0}" -gt 0 ]; then
    git -C "$wt" add OVERNIGHT_PROGRESS.md
    git -C "$wt" -c user.name="overnight-fleet" -c user.email="overnight@shrike-labs.local" commit -q -m "chore(backlog): park $parked straggler item(s) under chronically-F batch $tag

Batch $tag landed $landed/$ntotal ($pct%) — grade F, already a demonstrated
failure pattern with a large enough sample to trust the signal. Its
remaining un-attempted items are AUTO-SKIP tagged (reversible, checkbox
stays unchecked) so the fleet stops repeating the same likely-failing
pattern on each sibling individually instead of waiting for
ovn_item_guard.sh's per-item cap to catch every one on its own. To
resume any of them: remove the [AUTO-SKIP batch-graded-F ...] prefix."
    res="$(wt_push "$wt" overnight/feature)"
    if [ "$res" = "ok" ]; then
      echo "$tag" >> "$DEDUP"
      git -C "repos/$repo" fetch -q origin overnight/feature 2>>"$LOG"
      git -C "repos/$repo" reset --hard -q origin/overnight/feature 2>>"$LOG"
      TOTAL_PARKED=$((TOTAL_PARKED + parked))
      SUMMARY="$SUMMARY
  ${repo}/${tag}: parked ${parked} item(s) — batch landed ${landed}/${ntotal} (${pct}%)"
      say "parked $parked item(s) for $repo/$tag"
    else
      say "push FAILED for $repo/$tag — not marking dedup, will retry next run"
    fi
  else
    say "0 items actually tagged for $repo/$tag (already tagged by a concurrent run?) — marking dedup"
    echo "$tag" >> "$DEDUP"
  fi
  wt_close "repos/$repo" "$wt"
done <<< "$OUT"

if [ "$TOTAL_PARKED" -gt 0 ]; then
  alert "Batch health: paused $TOTAL_PARKED straggler item(s)" "warning" "$(printf 'Batch(es) graded F with a demonstrated failure pattern (>=5 attempts, <25%% landed, >=24h old) had their remaining un-attempted items paused (AUTO-SKIP) so the fleet stops repeating the same likely-failing pattern item-by-item.\n\nTo resume any of them: search OVERNIGHT_PROGRESS.md for the batch tag and remove the "[AUTO-SKIP batch-graded-F ...]" prefix.\n%s' "$SUMMARY")"
else
  say "no new batches to park this run"
fi
