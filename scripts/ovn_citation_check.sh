#!/usr/bin/env bash
# ovn_citation_check.sh — shadow-mode check for backlog items citing a file that
# doesn't actually exist (2026-09-23).
#
# Root cause this closes: a research/decompose pass writes a backlog item that
# references an existing file by name as the pattern to follow or the thing being
# modified (e.g. "mirroring AuthRepositoryTest.kt's mockk pattern", "covering
# TopicsViewModel.kt's methods") — if that referenced file doesn't actually exist
# (hallucinated during research, or renamed/deleted since), the model either
# no-ops (can't find the file to follow) or invents something to fill the gap,
# neither of which is what the item asked for. Complements ovn_backlog_format_
# check.sh (structurally-missing payload lines) and ovn_verify_direction_check.sh
# (VERIFY clauses that can never fail) — this one checks that an item's PREMISE
# is grounded in a real file, not that its shape or gate is sound.
#
# Deliberately does NOT check the item's own leading target path (the file it's
# creating/changing) — that's expected to not exist yet for a "create this new
# file" item. Only flags OTHER files the item's own text leans on as already
# existing. SHADOW-MODE, alert-only — never blocks a commit, never edits a
# backlog file, just tells a human/Claude which items need a second look before
# the fleet burns a cycle on a premise that doesn't hold.
set -uo pipefail
cd "$HOME/overnight-queue" || exit 1
export PATH=/usr/local/bin:/usr/bin:/bin:${PATH:-}
LOG="logs/ovn_citation_check.log"
say(){ echo "$(date '+%F %T') $*" >> "$LOG"; }
STATE_DIR="state"; mkdir -p "$STATE_DIR" 2>/dev/null
NTFY_TOPIC_RESOLVED="${NTFY_TOPIC:-$(cat "$STATE_DIR/ntfy_topic" 2>/dev/null)}"
alert(){ [ -n "$NTFY_TOPIC_RESOLVED" ] && curl -fsS --max-time 8 -H "Title: $1" -H "Tags: $2" -d "$3" "https://ntfy.sh/$NTFY_TOPIC_RESOLVED" >/dev/null 2>&1; true; }
HELPER="$(dirname "$0")/ovn_citation_check.py"

REPOS="${1:-billwatch gitlark iptv_apps test-automation-agent xlite shrike-notify shrike-monitor shrike-labs-website}"
PAYLOAD_RE='^\+- \[ \] \[T[1-5]\]'
FOUND=0
REPORT=""

for r in $REPOS; do
  f="backlog/$r.md"
  [ -f "$f" ] || continue
  repo_dir="repos/$r"
  [ -d "$repo_dir" ] || continue
  since_file="$STATE_DIR/citation_check_since_${r}"
  since_sha="$(cat "$since_file" 2>/dev/null || true)"

  if [ -n "$since_sha" ]; then
    commits="$(git log --format=%H "${since_sha}..HEAD" -- "$f" 2>/dev/null | tac)"
  else
    commits="$(git log --format=%H -- "$f" 2>/dev/null | tac)"
  fi

  for c in $commits; do
    diff="$(git show "$c" -- "$f" 2>/dev/null)"
    lines="$(printf '%s\n' "$diff" | grep -E "$PAYLOAD_RE" || true)"
    [ -z "$lines" ] && continue
    # Whole commit at once (not per-line): the python helper needs every sibling
    # line's own target to know a "missing" file isn't just about to be created by
    # the item right next to it in the same batch (found live: a route-wiring item
    # citing CodeInsightsPage.vue one line before the item that creates it).
    flags="$(printf '%s\n' "$lines" | python3 "$HELPER" "$repo_dir" 2>/dev/null || true)"
    [ -z "$flags" ] && continue
    while IFS=$'\t' read -r line missing; do
      [ -z "$line" ] && continue
      FOUND=$((FOUND+1))
      short="$(printf '%s' "$line" | cut -c1-100)"
      msg="$r @ ${c:0:9}: ${short}... -> ${missing}"
      say "SUSPECT: $msg"
      REPORT="${REPORT}${msg}
"
    done <<< "$flags"
  done

  latest="$(git log -1 --format=%H -- "$f" 2>/dev/null)"
  [ -n "$latest" ] && echo "$latest" > "$since_file"
done

if [ "$FOUND" -gt 0 ]; then
  say "=== $FOUND item(s) citing a file not found anywhere in the repo this run ==="
  alert "Citation check: $FOUND suspect item(s)" "warning" "$(printf '%s' "$REPORT" | head -c 800)"
else
  say "clean run — no missing-citation items found"
fi
