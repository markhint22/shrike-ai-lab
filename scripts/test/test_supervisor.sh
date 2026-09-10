#!/usr/bin/env bash
# Regression test: supervisor.sh must turn queue state into an accurate
# "findings" digest: auto-disabled tasks, genuinely-actionable alerts (filtering
# out routine build-gate/red-green noise and archiving the log after), stuck
# no-op streaks, and the timeout auto-recovery self-heal - and must fall back to
# "All clear" when none of those conditions are present.
#
# supervisor.sh honors OVERNIGHT_DIR, so this test sandboxes it fully without
# touching the real state/ or repos/ dirs. NTFY_TOPIC is left unset throughout
# so no network push is ever attempted. No repos/ dir is created, so the
# git-fetch-based sections (drift / commit-sanity) never run (no network needed
# there either) - those sections are covered separately, see BUGS note at the
# bottom of this file.
set -uo pipefail
SCRIPT="$(cd "$(dirname "$0")/../.." && pwd)/supervisor.sh"
[ -f "$SCRIPT" ] || { echo "  SKIP: $SCRIPT not found"; exit 0; }
P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

tmp="$(mktemp -d)"
DIR="$tmp/ovn"

reset_dir() {
  rm -rf "$DIR"
  mkdir -p "$DIR/state" "$DIR/reports" "$DIR/logs"
  echo '[]' > "$DIR/tasks.json"
}

RUN() { OVERNIGHT_DIR="$DIR" bash "$SCRIPT" 2>>"$DIR/logs/supervisor.log"; }

# --- A: healthy/all-clear path -----------------------------------------------
reset_dir
OUT="$(RUN)"
REPORT="$(ls -t "$DIR"/reports/supervisor-*.md 2>/dev/null | head -1)"
ok "all-clear run produces a report file" "[ -n '$REPORT' ] && [ -f '$REPORT' ]"
ok "all-clear run reports 0 findings on stdout" "echo \"$OUT\" | grep -q 'supervisor: 0 finding(s)'"
ok "all-clear report body says All clear" "grep -q 'All clear' '$REPORT'"

# --- B: auto-disabled task surfaces as a finding -----------------------------
reset_dir
cat > "$DIR/tasks.json" <<'JSON'
[ { "id": "gitlark-broken-thing", "enabled": false, "timeout_secs": 600 } ]
JSON
mkdir -p "$DIR/state/failures"
echo "5" > "$DIR/state/failures/gitlark-broken-thing.count"
OUT="$(RUN)"
REPORT="$(ls -t "$DIR"/reports/supervisor-*.md 2>/dev/null | head -1)"
ok "auto-disabled task -> exactly 1 finding" "echo \"$OUT\" | grep -q 'supervisor: 1 finding(s)'"
ok "report names the disabled task and fail count" "grep -q 'AUTO-DISABLED: gitlark-broken-thing (failed 5x)' '$REPORT'"

# --- C: alerts.log - build-gate/red-green noise is filtered, a real alert isn't,
#        and the log is archived+cleared afterward (no re-counting next run) ---
reset_dir
cat > "$DIR/state/alerts.log" <<'LOG'
[2026-09-10 08:00:00] warn | ongoing-xlite | build-gate reverted a commit that broke the build (syntax/import/parse error) — the model produced non-loading code
[2026-09-10 08:10:00] warn | ongoing-gitlark | reverted a commit that left tests red (a source change broke a previously-green test); feature kept green for hygiene
[2026-09-10 09:00:00] error | ongoing-foo | disk quota exceeded on the runner host, manual cleanup needed
LOG
OUT="$(RUN)"
REPORT="$(ls -t "$DIR"/reports/supervisor-*.md 2>/dev/null | head -1)"
ok "only the genuine alert counts (build-gate/red-green noise filtered)" "grep -q '1 alert(s) need a look' '$REPORT'"
ok "the surfaced alert is the real one, not the filtered noise" "grep -q 'disk quota exceeded' '$REPORT'"
ok "the surfaced alert text excludes the filtered build-gate line" "! grep -q 'build-gate reverted' '$REPORT'"
ok "alerts.log is archived" "grep -q 'disk quota exceeded' '$DIR/state/alerts.archive.log'"
ok "alerts.log is cleared after archiving (no re-count next run)" "[ ! -s '$DIR/state/alerts.log' ]"
# second run must NOT re-report the same (now-archived, now-empty) alert
OUT2="$(RUN)"
ok "archived alert is not re-counted on the next run" "echo \"$OUT2\" | grep -q 'supervisor: 0 finding(s)'"

# --- D: stuck no-op streak (>= NOOP_STREAK_ALERT) surfaces; below-threshold doesn't --
reset_dir
mkdir -p "$DIR/state/noops"
echo "30" > "$DIR/state/noops/ongoing-stuckrepo.count"
echo "3"  > "$DIR/state/noops/ongoing-finerepo.count"
OUT="$(RUN)"
REPORT="$(ls -t "$DIR"/reports/supervisor-*.md 2>/dev/null | head -1)"
ok "stuck (>=30) no-op streak is flagged" "grep -q 'STUCK: ongoing-stuckrepo no-op.*30 cycles' '$REPORT'"
ok "below-threshold (3) streak is NOT flagged" "! grep -q 'ongoing-finerepo' '$REPORT'"

# --- E: timeout auto-recovery self-heal (the real edge case section 8 guards):
#     a task disabled by the safety valve (has a .count file) whose 2 most
#     recent report rows both show error(exit=124) gets re-enabled ONCE with
#     doubled timeout_secs, and its recovery flag prevents doing this twice. ---
reset_dir
cat > "$DIR/tasks.json" <<'JSON'
[ { "id": "slow-task", "enabled": false, "timeout_secs": 600 } ]
JSON
mkdir -p "$DIR/state/failures"
echo "3" > "$DIR/state/failures/slow-task.count"
cat > "$DIR/reports/2026-09-09-2300.md" <<'MD'
| slow-task | aider_fix | error(exit=124) | overnight/feature | /x/a.log | 600s |
MD
cat > "$DIR/reports/2026-09-10-0200.md" <<'MD'
| slow-task | aider_fix | error(exit=124) | overnight/feature | /x/b.log | 600s |
MD
OUT="$(RUN)"
REPORT="$(ls -t "$DIR"/reports/supervisor-*.md 2>/dev/null | head -1)"
ok "timeout auto-recovery fires and re-enables the task" "grep -q 'AUTO-RECOVERED slow-task' '$REPORT'"
ok "timeout_secs was doubled (600 -> 1200)" "[ \"\$(jq -r '.[0].timeout_secs' '$DIR/tasks.json')\" = 1200 ]"
ok "task is re-enabled in tasks.json" "[ \"\$(jq -r '.[0].enabled' '$DIR/tasks.json')\" = true ]"
ok "the safety-valve failure count file was cleared" "[ ! -f '$DIR/state/failures/slow-task.count' ]"
ok "a one-shot recovery flag was written" "[ -f '$DIR/state/autorecovered_slow-task' ]"
# now simulate it failing again (re-disabled) - must NOT auto-recover a 2nd time
echo "1" > "$DIR/state/failures/slow-task.count"
jq '(.[]|select(.id=="slow-task")) |= (.enabled=false)' "$DIR/tasks.json" > "$DIR/tasks.json.tmp" && mv "$DIR/tasks.json.tmp" "$DIR/tasks.json"
OUT2="$(RUN)"
ok "does not auto-recover a second time (one-shot guard)" "! echo \"$OUT2\" | grep -q 'AUTO-RECOVERED'"

# --- G: FIXED BUG regression guard (2026-09-10) — sections 6/7/9/AI-review must
#     land in the real `findings` array, not the dead `_muted` variable they used
#     to accumulate into (a typo that silently dropped 5 of 9 monitoring sections
#     from both the digest report and the ntfy push, no matter how actionable).
#     Section 9 (grooming-ready notice) is the cheapest of the five to trigger
#     deterministically with no git/network dependency, so it's the regression
#     canary for the whole class of bug. ---
reset_dir
touch "$DIR/reports/grooming-gitlark-$(date +%Y%m%d).md"
OUT="$(RUN)"
REPORT="$(ls -t "$DIR"/reports/supervisor-*.md 2>/dev/null | head -1)"
ok "grooming-ready notice reaches the real findings count, not a dead variable" \
   "echo \"$OUT\" | grep -qE 'supervisor: [1-9][0-9]* finding'"
ok "grooming-ready notice appears in the actual report body" \
   "grep -q 'backlog grooming proposal' '$REPORT'"

# --- H: same fix, via the commit-sanity heuristics (section 7) — an empty
#     (0-line-change) commit on overnight/feature ahead of main must surface as
#     a finding, proving the fix isn't specific to section 9's simpler code path. ---
reset_dir
mkdir -p "$DIR/repos/fakerepo"
( cd "$DIR/repos/fakerepo" && git init -q && git config user.email t@t.com && git config user.name t \
  && echo x > f.txt && git add -A && git commit -q -m init \
  && git branch -M main && git checkout -q -b overnight/feature \
  && git commit -q --allow-empty -m "no-op cycle" \
  && mkdir -p .git/refs/remotes/origin \
  && git update-ref refs/remotes/origin/main main \
  && git update-ref refs/remotes/origin/overnight/feature overnight/feature )
OUT="$(RUN)"
REPORT="$(ls -t "$DIR"/reports/supervisor-*.md 2>/dev/null | head -1)"
ok "empty-commit finding reaches the real findings count" \
   "echo \"$OUT\" | grep -qE 'supervisor: [1-9][0-9]* finding'"
ok "empty-commit finding appears in the actual report body" \
   "grep -q 'EMPTY COMMIT' '$REPORT'"

rm -rf "$tmp"
echo "supervisor: $P passed, $F failed"
[ "$F" -eq 0 ]
