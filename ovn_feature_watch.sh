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
SERVER="${NTFY_SERVER:-http://127.0.0.1:8099}"
[ -n "$TOPIC" ] || exit 0

# 2026-11-03 (S2/F5): per-item "Feature complete" pushes arrived in bursts (16 billwatch, 10 iptv, 10 TAA in one tick) and were ALL dropped by the relay (51 of the 53 "dropped" in one heartbeat).
# OVN_FEATURE_AGGREGATE=on (default; off = legacy one push per feature): completions are buffered in state/feature_complete_pending.log and flushed as ONE note-class push
# ("Features ready to test: N" - not matched by the relay DROP_RE, so it becomes one bullet in the hourly digest) at most every OVN_FEATURE_FLUSH_S (3600) seconds.
AGG="${OVN_FEATURE_AGGREGATE:-on}"; PENDING="$STATE_DIR/feature_complete_pending.log"; FLUSHED="$STATE_DIR/feature_complete_last_flush"
FLUSH_S="${OVN_FEATURE_FLUSH_S:-3600}"

alert(){ curl -fsS --max-time 8 -H "Title: $1" -H "Tags: $2" -H "Priority: ${4:-default}" -d "$3" "$SERVER/$TOPIC" >/dev/null 2>&1; }   # returns curl's rc (callers that do not care just ignore it; the aggregate flush must NOT clear its buffer on failure)

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
    if [ "$AGG" = "off" ]; then
      alert "🎉 Feature complete: ${feat_id} (${repo})" "tada" "All decomposed sub-items for this feature have landed on the feature branch and nothing more is queued for it in the backlog — ready to test. (feat id: ${feat_id})"
    else
      echo "${repo} ${feat_id}" >> "$PENDING"
    fi
  done < <(printf '%s' "$out" | python3 -c "
import json, sys
for r in json.load(sys.stdin):
    if r.get('done'):
        print(r['key'])
")
done

if [ "$AGG" != "off" ] && [ -s "$PENDING" ]; then
  _now="$(date +%s)"; _last="$(cat "$FLUSHED" 2>/dev/null || echo 0)"
  case "$_last" in ''|*[!0-9]*) _last=0;; esac
  if [ $(( _now - _last )) -ge "$FLUSH_S" ]; then
    _n="$(wc -l < "$PENDING" | tr -d ' ')"
    _list="$(awk '{print $2" ("$1")"}' "$PENDING" | head -8 | paste -sd ';' - | sed 's/;/; /g')"
    [ "$_n" -gt 8 ] && _list="$_list; +$(( _n - 8 )) more"
    # only clear the buffer + record the flush time when the push was actually accepted: an unreachable relay used to lose the whole hour's list (ids are already in NOTIFIED, so never re-announced)
    if alert "Features ready to test: ${_n}" "tada" "All sub-items landed on the feature branch for: ${_list}"; then
      : > "$PENDING"; echo "$_now" > "$FLUSHED"
    fi
  fi
fi
