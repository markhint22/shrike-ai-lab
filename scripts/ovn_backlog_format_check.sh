#!/usr/bin/env bash
# ovn_backlog_format_check.sh — shadow-mode check for the "header-only backlog" bug (2026-09-22).
#
# Root cause this closes: a commit to backlog/<repo>.md can add a "# --- decomposed from roadmap
# ... ---" header without ever adding a real "- [ ] [T1]".."[T5]" payload line beneath it. Since
# queue_refill.py ONLY ever pulls lines matching ^- \[ \] \[T[1-5]\], a header-only commit silently
# makes that repo's backlog non-functional from the moment it lands — found live today across 3
# repos (billwatch: weeks; shrike-monitor: since 2026-09-05; xlite: from a same-night refill), each
# discovered only because doable hit exactly 0 and someone went looking, not because anything
# alerted. This is a SHADOW-MODE, alert-only check — it never blocks a commit or reverts anything,
# it just tells a human/Claude which commits need a follow-up decomposition pass.
set -uo pipefail
cd "$HOME/overnight-queue" || exit 1
export PATH=/usr/local/bin:/usr/bin:/bin:${PATH:-}
LOG="logs/ovn_backlog_format_check.log"
say(){ echo "$(date '+%F %T') $*" >> "$LOG"; }
STATE_DIR="state"; mkdir -p "$STATE_DIR" 2>/dev/null
NTFY_TOPIC_RESOLVED="${NTFY_TOPIC:-$(cat "$STATE_DIR/ntfy_topic" 2>/dev/null)}"
alert(){ [ -n "$NTFY_TOPIC_RESOLVED" ] && curl -fsS --max-time 8 -H "Title: $1" -H "Tags: $2" -d "$3" "https://ntfy.sh/$NTFY_TOPIC_RESOLVED" >/dev/null 2>&1; true; }

REPOS="${1:-billwatch gitlark iptv_apps test-automation-agent xlite shrike-notify shrike-monitor}"
HEADER_RE='^\+# --- '
PAYLOAD_RE='^\+- \[ \] \[T[1-5]\]'
FOUND=0
REPORT=""

for r in $REPOS; do
  f="backlog/$r.md"
  [ -f "$f" ] || continue
  since_file="$STATE_DIR/backlog_check_since_${r}"
  since_sha="$(cat "$since_file" 2>/dev/null || true)"

  if [ -n "$since_sha" ]; then
    commits="$(git log --format=%H "${since_sha}..HEAD" -- "$f" 2>/dev/null | tac)"
  else
    commits="$(git log --format=%H -- "$f" 2>/dev/null | tac)"
  fi

  for c in $commits; do
    diff="$(git show "$c" -- "$f" 2>/dev/null)"
    headers_added="$(printf '%s\n' "$diff" | grep -cE "$HEADER_RE" || true)"
    payload_added="$(printf '%s\n' "$diff" | grep -cE "$PAYLOAD_RE" || true)"
    if [ "${headers_added:-0}" -gt 0 ] && [ "${payload_added:-0}" -eq 0 ]; then
      FOUND=$((FOUND+1))
      msg="$r backlog commit ${c:0:9} added $headers_added header(s) with ZERO real [T#] payload lines"
      say "SUSPECT: $msg"
      REPORT="${REPORT}${msg}
"
    fi
  done

  latest="$(git log -1 --format=%H -- "$f" 2>/dev/null)"
  [ -n "$latest" ] && echo "$latest" > "$since_file"
done

if [ "$FOUND" -gt 0 ]; then
  say "=== $FOUND header-only-backlog commit(s) found this run ==="
  alert "Backlog format check: $FOUND suspect commit(s)" "warning" "$(printf '%s' "$REPORT" | head -c 800)"
else
  say "clean run — no header-only-backlog commits found"
fi
