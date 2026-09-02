#!/usr/bin/env bash
# Per-cycle ntfy push: reads a finished run report and sends the phone a concise,
# informative summary of what each repo did this cycle + the KIND of issue for any
# failure/revert. Deduplicated (identical consecutive summaries aren't re-sent) so
# a stable run of no-ops doesn't spam. Topic is read from state/ntfy_topic (NOT
# committed) so it stays secret. Called at the end of run_overnight.sh:
#     "$SCRIPT_DIR/cycle_notify.sh" "$REPORT_FILE"
set -uo pipefail
REPORT="${1:-}"
[ -f "$REPORT" ] || exit 0
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="$DIR/state"
TOPIC="${NTFY_TOPIC:-$(cat "$STATE_DIR/ntfy_topic" 2>/dev/null)}"
[ -n "$TOPIC" ] || exit 0
SERVER="${NTFY_SERVER:-https://ntfy.sh}"

# Pull one short, human "kind of issue" from a task's aider/test log.
issue_kind() {
  local logp="$1"
  [ -f "$logp" ] || { echo ""; return; }
  if grep -qiE "SyntaxError|IndentationError|invalid syntax" "$logp"; then echo "python syntax error"
  elif grep -qiE "ImportError|ModuleNotFound|cannot import name" "$logp"; then echo "bad/broken import"
  elif grep -qiE "SCRIPT ERROR|Parse Error|Expected|Unexpected token" "$logp"; then echo "GDScript/parse error"
  elif grep -qiE "error TS[0-9]|Cannot find module" "$logp"; then echo "TypeScript error"
  elif grep -qoE "[0-9]+ failed" "$logp"; then echo "$(grep -hoE "[0-9]+ failed" "$logp" | tail -1) test(s)"
  elif grep -qiE "ContextWindowExceeded" "$logp"; then echo "task too big (context)"
  elif grep -qiE "exit=124|timed out|Killed" "$logp"; then echo "hit the 600s time limit"
  elif grep -qiE "RateLimit|APIConnection|Connection reset|Max retries" "$logp"; then echo "network/API blip"
  else echo "see log"; fi
}

pass=""; fail=""; rev=""; err=""; noop=""; np=0; nf=0; nr=0; nn=0; ne=0
while IFS='|' read -r _ c_id c_type c_out c_branch c_log _; do
  id="$(echo "$c_id" | xargs | sed 's/^ongoing-//')"
  out="$(echo "$c_out" | xargs)"
  logp="$(echo "$c_log" | xargs)"
  case "$out" in
    *"tests:pass"*)        pass="$pass $id"; np=$((np+1));;
    *"tests:FAIL"*)        fail="$fail ${id}($(grep -hoE '[0-9]+ failed' "$logp" 2>/dev/null | tail -1))"; nf=$((nf+1));;
    reverted*|*build-gate*) rev="$rev ${id}[$(issue_kind "$logp")]"; nr=$((nr+1));;
    error*)                err="$err ${id}[$(issue_kind "$logp")]"; ne=$((ne+1));;
    no-op)                 noop="$noop $id"; nn=$((nn+1));;
  esac
done < <(grep -E "^\| ongoing" "$REPORT")

# nothing ran (paused / abort) -> skip
[ $((np+nf+nr+nn+ne)) -eq 0 ] && exit 0

body="$(date '+%H:%M')  ·  ${np} landed · ${nf} test-fail · ${nr} reverted · ${ne} error · ${nn} no-op"
[ -n "$pass" ] && body="$body"$'\n'"✅ landed (tests pass):$pass"
[ -n "$fail" ] && body="$body"$'\n'"⚠️ committed but tests FAIL:$fail"
[ -n "$rev" ]  && body="$body"$'\n'"↩️ reverted (broke build):$rev"
[ -n "$err" ]  && body="$body"$'\n'"⛔ errored:$err"
[ -n "$noop" ] && body="$body"$'\n'"➖ no change made:$noop"

# dedup identical consecutive summaries (ignore the leading timestamp)
sig="$(printf '%s' "$body" | tail -n +2 | md5sum | cut -d' ' -f1)"
hf="$STATE_DIR/last_ntfy_sig"
[ "$(cat "$hf" 2>/dev/null)" = "$sig" ] && exit 0
echo "$sig" > "$hf"

curl -fsS --max-time 8 -H "Title: Overnight queue" -H "Tags: robot" \
  -d "$body" "$SERVER/$TOPIC" >/dev/null 2>&1 || true
