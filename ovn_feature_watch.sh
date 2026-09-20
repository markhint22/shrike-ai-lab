#!/usr/bin/env bash
# ovn_feature_watch.sh (cron, staggered every 15min) — fires a distinct, differently-titled
# ntfy push the moment a REAL (planner-tagged [feat:ID]) feature's last remaining sub-item
# lands, so it doesn't get lost in the routine hourly/3h digest noise. See
# scripts/ovn_feature_groups.py's header for the full feature-grouping investigation and why
# file-based approximate groups (kind=file) are deliberately EXCLUDED here — only a real
# planner-linked feature id is a trustworthy enough signal to claim "ready to test."
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="$DIR/state"
mkdir -p "$STATE_DIR"
NOTIFIED="$STATE_DIR/feature_progress_notified.log"
touch "$NOTIFIED"
TOPIC="${NTFY_TOPIC:-$(cat "$STATE_DIR/ntfy_topic" 2>/dev/null)}"
SERVER="${NTFY_SERVER:-https://ntfy.sh}"
[ -n "$TOPIC" ] || exit 0

alert(){ curl -fsS --max-time 8 -H "Title: $1" -H "Tags: $2" -d "$3" "$SERVER/$TOPIC" >/dev/null 2>&1 || true; }

for repo_path in "$DIR"/repos/*/; do
  repo="$(basename "$repo_path")"
  [ -f "$DIR/roadmap/$repo.md" ] || continue   # only planner-managed repos have real [feat:] items
  out="$(OVN_QUEUE_DIR="$DIR" python3 "$DIR/scripts/ovn_feature_groups.py" "$repo" --json 2>/dev/null)"
  [ -n "$out" ] || continue
  # bootstrap once per repo: the FIRST time this ever runs for a repo, silently record any
  # already-100%-done feature as already-notified instead of pushing — otherwise every feature
  # that happened to already be complete before this script existed would look like a brand
  # new completion and flood the phone the first tick after deploy.
  baseline_marker="$STATE_DIR/feature_progress_baselined.$repo"
  if [ ! -f "$baseline_marker" ]; then
    touch "$baseline_marker"
    printf '%s' "$out" | python3 -c "
import json, sys
for r in json.load(sys.stdin):
    if r.get('done'):
        print(r['key'])
" >> "$NOTIFIED"
    continue
  fi
  while IFS= read -r feat_id; do
    [ -z "$feat_id" ] && continue
    grep -qxF "$feat_id" "$NOTIFIED" && continue
    echo "$feat_id" >> "$NOTIFIED"
    alert "🎉 Feature complete: ${feat_id} (${repo})" "tada" "All decomposed sub-items for this feature have landed on the feature branch and nothing more is queued for it in the backlog — ready to test. (feat id: ${feat_id})"
  done < <(printf '%s' "$out" | python3 -c "
import json, sys
for r in json.load(sys.stdin):
    if r.get('done'):
        print(r['key'])
")
done
