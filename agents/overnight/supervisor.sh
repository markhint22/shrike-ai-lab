#!/bin/bash
# ===========================================
# Shrike AI Lab - Overnight Queue Supervisor (Tier-4, 2026-08-25)
# ===========================================
# The local 27B does the volume coding; this is the periodic "judgment" pass it
# keeps getting wrong. Runs on the GPU server (cron), and DEGRADES GRACEFULLY:
#
#   * ALWAYS: builds a deterministic health digest from queue state
#     (auto-disabled tasks, unacked alerts, red-green SUSPECT flags, no-op
#     streaks, diverged clones, branch-hygiene review flags, main<-feature
#     drift) and, if anything is actionable, pushes it to your phone via ntfy.
#   * IF `claude` CLI + ANTHROPIC_API_KEY are present: ALSO runs a Claude review
#     pass over recent overnight/feature commits ("does each commit do what its
#     message claims?" - catches the 'remove duplicate' commit that ADDS one,
#     and red-green SUSPECT diffs) and appends its findings to the digest/push.
#
# Enable phone push:   export NTFY_TOPIC=<your-secret-topic>  (ntfy.sh app, free)
# Enable Claude review: install `@anthropic-ai/claude-code` + set
#                       ANTHROPIC_API_KEY, then this auto-upgrades. No code change.
#
# Usage:  ./supervisor.sh          # run a pass now
#         NTFY_TOPIC=xxx ./supervisor.sh
# Cron:   0 */3 * * *  cd ~/overnight-queue && ./supervisor.sh >> logs/supervisor.log 2>&1
# ===========================================
set -uo pipefail

DIR="${OVERNIGHT_DIR:-$HOME/overnight-queue}"
STATE="$DIR/state"
REPOS="$DIR/repos"
TASKS="$DIR/tasks.json"
REPORT_DIR="$DIR/reports"
TS="$(date '+%Y-%m-%d %H:%M')"
NOOP_STREAK_ALERT="${NOOP_STREAK_ALERT:-30}"
NTFY_TOPIC="${NTFY_TOPIC:-}"
NTFY_SERVER="${NTFY_SERVER:-https://ntfy.sh}"

findings=()   # human-readable actionable lines

# --- 1. auto-disabled tasks (safety valve tripped) -------------------------
if [ -f "$TASKS" ]; then
  while IFS= read -r id; do
    [ -z "$id" ] && continue
    if [ -f "$STATE/failures/${id}.count" ]; then
      findings+=("AUTO-DISABLED: ${id} (failed $(cat "$STATE/failures/${id}.count")x) — queue.sh log ${id}")
    fi
  done < <(jq -r '.[] | select((.enabled // true) == false) | .id' "$TASKS" 2>/dev/null)
fi

# --- 2. unacknowledged alerts ---------------------------------------------
if [ -s "$STATE/alerts.log" ]; then
  n=$(wc -l < "$STATE/alerts.log")
  findings+=("${n} unacked alert(s) — queue.sh alerts; newest: $(tail -1 "$STATE/alerts.log" | sed 's/^[^|]*| //')")
fi

# --- 3. red-green SUSPECT in the latest report ----------------------------
LATEST_REPORT="$(ls -t "$REPORT_DIR"/*.md 2>/dev/null | head -1)"
if [ -n "$LATEST_REPORT" ] && grep -q 'redgreen:SUSPECT' "$LATEST_REPORT" 2>/dev/null; then
  sus=$(grep -c 'redgreen:SUSPECT' "$LATEST_REPORT")
  findings+=("${sus} red-green SUSPECT test(s) in the last run — a new test passed WITHOUT its fix; review the diff.")
fi

# --- 4. long no-op streaks (silently stuck) -------------------------------
if [ -d "$STATE/noops" ]; then
  for f in "$STATE"/noops/*.count; do
    [ -f "$f" ] || continue
    c="$(cat "$f")"
    if [ "$c" -ge "$NOOP_STREAK_ALERT" ]; then
      findings+=("STUCK: $(basename "$f" .count) no-op'd ${c} cycles — check its Next Steps.")
    fi
  done
fi

# --- 5. diverged clones + branch-hygiene review flags ---------------------
for f in "$STATE"/diverged_* ; do
  [ -e "$f" ] || continue
  findings+=("DIVERGED clone: $(basename "$f" | sed 's/^diverged_//') — manual reconcile needed.")
done
for f in "$STATE"/branch_hygiene_review_* ; do
  [ -e "$f" ] || continue
  findings+=("branch-hygiene flagged: $(basename "$f" | sed 's/^branch_hygiene_review_//') — feature->main gate not green.")
done

# --- 6. overnight/feature drift ahead of main (unlanded work) -------------
if [ -d "$REPOS" ]; then
  for r in "$REPOS"/*/ ; do
    [ -d "$r/.git" ] || continue
    name="$(basename "$r")"
    ahead="$(git -C "$r" rev-list --count origin/main..origin/overnight/feature 2>/dev/null || echo 0)"
    if [ "${ahead:-0}" -ge 40 ]; then
      findings+=("DRIFT: ${name} overnight/feature is ${ahead} commits ahead of main — consider a salvage-merge.")
    fi
  done
fi

# --- assemble digest ------------------------------------------------------
REPORT_FILE="$REPORT_DIR/supervisor-$(date +%Y%m%d-%H%M%S).md"
{
  echo "# Supervisor digest — ${TS}"
  echo ""
  if [ "${#findings[@]}" -eq 0 ]; then
    echo "All clear — no actionable issues."
  else
    echo "## Actionable (${#findings[@]})"
    for f in "${findings[@]}"; do echo "- $f"; done
  fi
} > "$REPORT_FILE"

# --- optional: Claude review pass (only if creds present) -----------------
CLAUDE_NOTE=""
if command -v claude >/dev/null 2>&1 && [ -n "${ANTHROPIC_API_KEY:-}" ]; then
  echo "" >> "$REPORT_FILE"
  echo "## Claude review" >> "$REPORT_FILE"
  PROMPT="You are the overnight-queue supervisor. For each active repo clone under ${REPOS} on branch overnight/feature, inspect the last 5 commits (git log -p -5 origin/main..overnight/feature). Flag ONLY: (a) a commit whose diff does NOT do what its message claims (e.g. 'remove duplicate' that adds one), (b) a test that looks vacuous or mirrors the code's own assumption, (c) an OVERNIGHT_PROGRESS.md item that is oversized or stale. Output a terse bulleted list of real findings with repo + commit sha, or 'no issues found'. Do not edit anything."
  # headless, read-only, time-boxed
  if timeout 900 claude -p "$PROMPT" --allowedTools "Bash(git*),Read,Grep,Glob" >> "$REPORT_FILE" 2>>"$DIR/logs/supervisor.log"; then
    CLAUDE_NOTE=" (+Claude review)"
  else
    echo "_(Claude review failed — see logs/supervisor.log)_" >> "$REPORT_FILE"
  fi
fi

echo "supervisor: ${#findings[@]} finding(s)${CLAUDE_NOTE} -> $REPORT_FILE"

# --- phone push (only when actionable and a topic is configured) ----------
if [ "${#findings[@]}" -gt 0 ] && [ -n "$NTFY_TOPIC" ]; then
  BODY="$(printf '%s\n' "${findings[@]}")"
  curl -fsS \
    -H "Title: Overnight queue: ${#findings[@]} item(s) need attention" \
    -H "Priority: default" \
    -H "Tags: warning" \
    -d "$BODY" \
    "${NTFY_SERVER}/${NTFY_TOPIC}" >/dev/null 2>&1 \
    && echo "pushed to ntfy topic" || echo "ntfy push failed (check NTFY_TOPIC/network)"
fi
