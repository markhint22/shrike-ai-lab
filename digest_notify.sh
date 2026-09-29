#!/usr/bin/env bash
# Every ~3h (cron): roll state/digest_buffer.log up into ONE human-readable ntfy
# message, then clear the buffer. Replaces the old per-cycle push. If nothing ran
# in the window, sends a short "quiet" heartbeat so you still know the box is alive.
#
# 2026-09-20: hourly_notify.sh (cron, hourly) now ALSO fires a leaner version of the
# landed-detail + tier-breakdown sections below for the trailing 1h — this digest stays the
# "fuller" one on purpose (tokens, by-language pass-rate, planning activity, and — new this
# same date — feature progress) and is effectively a rollup covering the last ~3 hourly
# summaries, not a duplicate of them. It is also still the ONLY one of the two that sends an
# idle/paused/not-running heartbeat, so a quiet box is never ambiguous even on an hour where
# hourly_notify.sh correctly stayed silent.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="$DIR/state"
BUF="$STATE_DIR/digest_buffer.log"
TOPIC="${NTFY_TOPIC:-$(cat "$STATE_DIR/ntfy_topic" 2>/dev/null)}"
SERVER="${NTFY_SERVER:-https://ntfy.sh}"
DIGEST_HOURS=3
[ -n "$TOPIC" ] || exit 0

# 2026-09-19 FIX: this used to be a bare `curl ... || true` — a single transient failure
# (network blip, ntfy.sh 5xx, etc.) was silently swallowed with no retry, and the caller
# always proceeded as if delivery had succeeded (see the unconditional buffer-clear this
# used to feed). Confirmed live: cron invoked this script on schedule and it ran to
# completion (buffer rotated to .last as usual), but the ~18:20 CDT digest never reached
# ntfy — no error anywhere because nothing checked curl's exit code. Now retries a few
# times and reports real success/failure so the caller can decide whether it's safe to
# drop the buffer.
# shrike-notify dual-publish (no-op unless SHRIKE_NOTIFY_URL is configured — see
# shrike_notify_lib.sh for the topic taxonomy and env var docs).
# shellcheck source=./shrike_notify_lib.sh
[ -f "$DIR/shrike_notify_lib.sh" ] && source "$DIR/shrike_notify_lib.sh"

send() {
  local title="$1" tags="$2" body="$3" prio="${4:-default}" attempt rc=0
  # Independent parallel sink — doesn't participate in the ntfy retry/rc logic above,
  # fires once per call regardless of ntfy's own success/failure.
  command -v shrike_notify_publish >/dev/null 2>&1 && shrike_notify_publish "fleet_queue_task" "$title" "$tags" "$body"
  for attempt in 1 2 3; do
    if curl -fsS --max-time 8 -H "Title: $title" -H "Tags: $tags" -H "Priority: $prio" -d "$body" "$SERVER/$TOPIC" >/dev/null 2>&1; then
      return 0
    fi
    rc=$?
    [ "$attempt" -lt 3 ] && sleep 2
  done
  echo "$(date '+%Y-%m-%d %H:%M:%S') send() FAILED after 3 attempts (curl rc=$rc): title='$title'" >&2
  return 1
}

# 2026-09-09: an empty buffer only means "nothing since the last digest" — it does NOT imply
# idle-or-paused (that vague "or" read as alarming even when the queue was running fine the
# whole time; confirmed live when two manual digest runs a few minutes apart hit this exact
# branch on the second one purely because the first had just drained the buffer). Check the
# REAL state instead of guessing.
if [ ! -s "$BUF" ]; then
  if [ -f "$STATE_DIR/PAUSED" ]; then
    send "Overnight queue — PAUSED" "pause_button" "$(date '+%a %H:%M') · The queue IS paused (queue.sh resume to continue). Nothing ran since the last digest." "default"
  elif systemctl is-active --quiet overnight-queue 2>/dev/null; then
    send "Overnight queue — quiet" "zzz" "$(date '+%a %H:%M') · Running normally — just nothing new since the last digest. NOT paused." "low"
  else
    send "Overnight queue — NOT RUNNING" "rotating_light" "$(date '+%a %H:%M') · The systemd service is not active and nothing ran since the last digest. Check: systemctl status overnight-queue" "high"
  fi
  exit 0
fi

cycles=0; NP=0; NF=0; NR=0; NN=0; NE=0; NI=0
pass=""; fail=""; rev=""; err=""
while IFS=$'\t' read -r ts a b c d e P F R E I; do
  [ -z "${a:-}" ] && continue
  cycles=$((cycles+1))
  NP=$((NP+a)); NF=$((NF+b)); NR=$((NR+c)); NN=$((NN+d)); NE=$((NE+e))
  # IDLE=N is a 2026-09-20 addition (cycle_notify.sh) - $I is empty for any pre-existing
  # buffer line written by the OLD cycle_notify.sh before this fix deployed, so default it
  # to 0 rather than let an empty operand blow up the arithmetic.
  _idle_val="${I#IDLE=}"; NI=$((NI+${_idle_val:-0}))
  pass="$pass,${P#PASS=}"; fail="$fail,${F#FAIL=}"; rev="$rev,${R#REV=}"; err="$err,${E#ERR=}"
done < "$BUF"

uniq_csv() { echo "$1" | tr ',' '\n' | grep -vE '^$' | sort -u | paste -sd', ' -; }
Praw="$(uniq_csv "$pass")"; Fraw="$(uniq_csv "$fail")"; Rraw="$(uniq_csv "$rev")"; Eraw="$(uniq_csv "$err")"
allrepos="$(uniq_csv "$pass,$fail,$rev,$err")"

# 2026-09-20 FIX (math-mismatch bug): every ✅/⚠️/↩️/⛔/➖ count shown further down comes from
# the SAME $NP/$NF/$NR/$NN/$NE variables computed above, so they can never disagree with each
# other the way a "$items work items done" header total once could (previously the ➖ line
# substituted a DIFFERENT, independently-sourced count from ovn_stats.py's task_stats.log-based
# classification — confirmed live to disagree: a real window showed a header total of 67 while
# the visible per-category lines summed to only 34). 2026-09-28: that header total is gone
# entirely now — the digest leads with the canonical outcomes.jsonl-based rate instead (below),
# so there is no second, cycle-buffer-derived total left to disagree with it.

# 2026-09-28 REWRITE (plain-language + corrected-metric fix): this digest used to LEAD with
# a jargon-heavy tally sourced from cycle_notify.sh's own per-cycle classification
# (state/digest_buffer.log's PASS=/FAIL=/REV=/ERR= counts) — a SEPARATE, independently
# computed number from the canonical GOOD/BAD/BENIGN split (ovn_outcome_buckets.py, via
# outcomes.jsonl) used elsewhere in this same message. Those two counting methods have
# disagreed before (the exact "three disagreeing formulas" bug: 91% on the dashboard, 45-58%
# on phone notifications, ~50% honest) — leading with the OLD one while a corrected one
# exists lower in the message is the last place that discrepancy could still surface. Now
# leads with the single canonical, honest number (scripts/ovn_tier_stats.py --headline),
# stated in plain words ("Last 3h: 11 of ~16 real attempts landed (69%)"), with wasted vs.
# benign explicitly separated and glossed — matching exactly what the user asked for.
_HEADLINE=""
if [ -x "$DIR/scripts/ovn_tier_stats.py" ]; then
  _HEADLINE="$(python3 "$DIR/scripts/ovn_tier_stats.py" "$DIGEST_HOURS" --headline 2>/dev/null)"
fi
_READY=0
if [ -x "$DIR/scripts/ovn_feature_groups.py" ]; then
  _READY="$(OVN_QUEUE_DIR="$DIR" python3 "$DIR/scripts/ovn_feature_groups.py" --ready-count "$DIGEST_HOURS" 2>/dev/null)"
  case "$_READY" in ''|*[!0-9]*) _READY=0 ;; esac
fi
_READY_NOTE=""
if [ "$_READY" -gt 0 ]; then
  _READY_WORD="feature"; [ "$_READY" -gt 1 ] && _READY_WORD="features"
  _READY_NOTE=" — ${_READY} ${_READY_WORD} ready to test"
fi

if [ -n "$_HEADLINE" ]; then
  body="Overnight queue · last ~${DIGEST_HOURS}h ($(date '+%a %H:%M'))
${_HEADLINE}${_READY_NOTE}"
else
  # no good/bad attempts recorded this window (e.g. everything was a benign skip, or the
  # canonical source has no data yet) — fall back to the cycle-count line below so the
  # digest still says something concrete rather than an empty headline.
  body="Overnight queue · last ~${DIGEST_HOURS}h ($(date '+%a %H:%M'))${_READY_NOTE}"
fi

# 2026-09-28: this section is now explicitly labeled as CYCLE-level detail — which repos
# hit which outcome, this run — distinct from (and may not exactly match) the canonical
# per-ATTEMPT headline above, since the two are sourced from different logs (digest_buffer.log's
# own per-cycle classification vs. outcomes.jsonl's canonical bucketing). Saying so plainly
# beats a false appearance of one single number.
body="$body

Cycle detail ($cycles run this window, touching: ${allrepos:-–}$( [ "$NI" -gt 0 ] && echo ", +${NI} idle check(s) with nothing to do")):"
# 2026-09-09 FIX: this used to say "landed on main" - wrong since the staging-flow change (see
# CLAUDE.md "Staging flow restored"). Every landed item here pushes to overnight/feature; it only
# reaches develop via the next hourly branch_hygiene merge, and only reaches main/prod via the
# daily GATED promote. Saying "on main" made it look like production already had the change when
# it was still several steps away - actively misleading, not just imprecise.
[ "$NP" -gt 0 ] && body="$body

✅ $NP landed on the feature branch (tests passed) — reaches develop at the next hourly merge, prod only via the daily gated promote  [$Praw]"
[ "$NF" -gt 0 ] && body="$body

⚠️ $NF had a failing test — still being fixed, held off the feature branch, nothing broke  [$Fraw]"
[ "$NR" -gt 0 ] && body="$body

↩️ $NR auto-reverted (the code didn't compile — an automatic safety check undid it, no action needed)  [$Rraw]"
[ "$NE" -gt 0 ] && body="$body

⛔ $NE errored (an infrastructure problem — network or timeout — not a code quality issue)  [$Eraw]"
if [ "$NN" -gt 0 ]; then
  # 2026-09-18 FIX: this used to just print the flat $NN count with no breakdown, so
  # "the fleet correctly declined 4 already-done items" (fine, cheap) and "the fleet
  # burned 8 real implement+verify attempts and landed nothing" (worth investigating)
  # looked identical. Reuse ovn_stats.py's existing cheap/burned + per-cause split.
  #
  # 2026-09-20 FIX: this used to let that breakdown REPLACE $NN outright with a smaller,
  # independently-sourced number - the displayed count could disagree with the header math.
  # Always show the real, header-consistent $NN;
  # append the cause breakdown as supplementary detail on however many of those $NN
  # cycles got a cause logged, worded so it can never read as a second, competing total.
  _NOOP_LINE=""
  if [ -x "$DIR/scripts/ovn_stats.py" ]; then
    _NOOP_LINE="$(python3 "$DIR/scripts/ovn_stats.py" "$DIGEST_HOURS" --noop-headline 2>/dev/null)"
  fi
  _NOOP_CAUSE="$(printf '%s' "$_NOOP_LINE" | sed -nE 's/^[0-9]+ no-op *-- *(.+)$/\1/p')"
  if [ -n "$_NOOP_CAUSE" ]; then
    body="$body

➖ $NN no change (item already done, or nothing to do) — cause on record for some: $_NOOP_CAUSE"
  else
    body="$body

➖ $NN no change (item already done, or nothing to do)"
  fi
fi
body="$body

Every line above is one work item. Only ✅ reaches the feature branch; ⚠️/↩️/⛔ never do."

# 2026-09-20: the ✅/➖ lines above only ever gave aggregate counts ("4 landed") - no way to
# tell WHAT landed without tailing logs by hand. state/outcomes.jsonl's own `id` field is just
# the generic tasks.json task id (e.g. "ongoing-billwatch"), not a per-item description - but
# state/task_stats.log (the file ovn_stats.py already reads above) DOES carry a real per-item
# target path per landed row, so ovn_landed_detail.py surfaces that instead. Capped per-repo
# and overall so this can't blow past ntfy's practical message-size ceiling (existing digests
# already run ~2-3KB; this adds well under 1KB with these defaults).
if [ -x "$DIR/scripts/ovn_landed_detail.py" ]; then
  _LANDED_DETAIL="$(python3 "$DIR/scripts/ovn_landed_detail.py" "$DIGEST_HOURS" --max-per-repo 3 --max-total 12 2>/dev/null)"
  [ -n "$_LANDED_DETAIL" ] && body="$body

$_LANDED_DETAIL"
fi

# 2026-09-20: repeat no-op/reverted items, grouped+deduped (full-day audit finding) - the
# ➖/↩️ counts above are raw per-CYCLE outcome tallies, so a single stale item the fleet keeps
# re-picking and re-failing inflates the apparent number of distinct problems (confirmed live:
# one billwatch item alone produced 7-8 separate no-op/revert records in a day). This groups
# by (repo, file, tier) and shows one line per repeat with a count, distinguishing items that
# eventually landed (self-resolved) from ones still stuck - see ovn_noop_detail.py's header.
if [ -x "$DIR/scripts/ovn_noop_detail.py" ]; then
  _NOOP_DETAIL="$(python3 "$DIR/scripts/ovn_noop_detail.py" "$DIGEST_HOURS" --max-total 8 2>/dev/null)"
  [ -n "$_NOOP_DETAIL" ] && body="$body

$_NOOP_DETAIL"
fi

# 2026-09-20: feature-level % complete, for whichever multi-item groups (real [feat:ID]
# planner-linked features, or an approximate same-file fallback where no such tag exists yet —
# see scripts/ovn_feature_groups.py's header for the full investigation) had a landed item in
# this window. A DISTINCT "🎉 Feature complete" push (ovn_feature_watch.sh, cron) fires the
# moment a real feature's last sub-item lands, separately from this routine digest.
if [ -x "$DIR/scripts/ovn_feature_groups.py" ]; then
  _FEAT="$(OVN_QUEUE_DIR="$DIR" python3 "$DIR/scripts/ovn_feature_groups.py" --digest "$DIGEST_HOURS" --max-total 6 2>/dev/null)"
  [ -n "$_FEAT" ] && body="$body

$_FEAT"
fi

# 2026-09-20: proactive "features in progress" - previously the ONLY feature-progress signal
# outside this window-scoped section above was ovn_feature_watch.sh's 100%-complete push;
# there was no way to see a real [feat:ID] group's standing %-complete unless it happened to
# land something in THIS exact window. Deliberately real-feat-only (never the file-based
# approximation fallback - that one stays completion-silent by design, see
# scripts/ovn_feature_groups.py's header) and not gated on window activity - a feature can be
# "in progress" for days between the fleet touching it, and this is meant to be visible the
# whole time it's incomplete. Kept in the fuller 3h digest, not the lean hourly one.
if [ -x "$DIR/scripts/ovn_feature_groups.py" ]; then
  _FEAT_PROGRESS="$(OVN_QUEUE_DIR="$DIR" python3 "$DIR/scripts/ovn_feature_groups.py" --in-progress --max-total 6 2>/dev/null)"
  [ -n "$_FEAT_PROGRESS" ] && body="$body

$_FEAT_PROGRESS"
fi

# 2026-09-09: tier-sliced pass/no-op/timeout + token spend. outcomes.jsonl has the accurate,
# EXPLICIT tier per item (record_outcome's own [T#] tag parse), so this replaced the old
# ovn_stats.py "Tiers:" line below, which inferred tier from a separate classification tag and
# couldn't show no-op/timeout/token detail. See project memory
# project_27b-higher-tier-and-throughput for why tier-accuracy here matters.
if [ -x "$DIR/scripts/ovn_tier_stats.py" ]; then
  _TIERS="$(python3 "$DIR/scripts/ovn_tier_stats.py" "$DIGEST_HOURS" 2>/dev/null)"
  [ -n "$_TIERS" ] && body="$body

$_TIERS"
fi

# 2026-09-09: a rolling 24h token total alongside the ${DIGEST_HOURS}h tier breakdown above —
# the ${DIGEST_HOURS}h number alone doesn't answer "how much am I spending per day," and this
# digest fires every ${DIGEST_HOURS}h so a plain 24h call here would just repeat the same total
# ~8x/day; --tokens-only keeps it to one line instead of duplicating the whole tier table.
if [ -x "$DIR/scripts/ovn_tier_stats.py" ]; then
  _TOKENS_24H="$(python3 "$DIR/scripts/ovn_tier_stats.py" 24 --tokens-only 2>/dev/null)"
  [ -n "$_TOKENS_24H" ] && body="$body
$_TOKENS_24H"
fi

# 2026-09-16: an all-time cumulative total ("total tokens burned, ever, and how much of that was
# on failures" - an explicit user request). Shown once per calendar day (same dedupe-stamp
# pattern as ovn_toks_monitor.sh's state/toks_alerted) rather than every ${DIGEST_HOURS}h - an
# all-time total barely moves between consecutive digests, so repeating it ~8x/day would just be
# noise; the 24h rolling total above already covers "how much am I spending per day."
if [ -x "$DIR/scripts/ovn_tier_stats.py" ] && [ "$(cat "$STATE_DIR/alltime_toks_shown" 2>/dev/null)" != "$(date +%F)" ]; then
  _TOKENS_ALL="$(python3 "$DIR/scripts/ovn_tier_stats.py" --all-time --tokens-only 2>/dev/null)"
  if [ -n "$_TOKENS_ALL" ]; then
    body="$body
$_TOKENS_ALL"
    date +%F > "$STATE_DIR/alltime_toks_shown"
  fi
fi

# classification pass-rate stats (2026-08-31): slice pass-rate by
# language/type/complexity/verifiability so failures are attributed to the RIGHT
# cause (a language like gdscript vs a complexity tier vs unverifiable gating).
if [ -x "$DIR/scripts/ovn_stats.py" ]; then
  _ACTIVE="$(jq -r 'map(select(.enabled != false)) | .[].repo' "$DIR/tasks.json" 2>/dev/null | xargs -n1 basename 2>/dev/null | sort -u | tr "\n" " ")"
  _STATS="$(OVN_REPOS_DIR="$DIR/repos" OVN_ACTIVE_REPOS="$_ACTIVE" python3 "$DIR/scripts/ovn_stats.py" "$DIGEST_HOURS" --ntfy 2>/dev/null)"
  [ -n "$_STATS" ] && body="$body

📈 By language/type (last ${DIGEST_HOURS}h):
$_STATS"
fi

# 2026-09-09: planner + refill activity, so it's visible when the queue is self-sustaining vs
# when a repo genuinely needs a human/Claude to add roadmap work (previously invisible unless you
# tailed logs/ovn_planner.log and logs/queue_refill.log by hand).
if [ -x "$DIR/scripts/ovn_planning_stats.py" ]; then
  _PLANNING="$(python3 "$DIR/scripts/ovn_planning_stats.py" "$DIGEST_HOURS" 2>/dev/null)"
  [ -n "$_PLANNING" ] && body="$body

$_PLANNING"
fi

# 2026-09-29 (Phase 6c): failure patterns seen for the FIRST time this window, from
# scripts/ovn_failure_triage.py --digest (read-only; the hourly ovn_failure_triage_cron.sh owns
# the detection pass). Capped at 5 lines so a burst of unfamiliar failures can't turn one digest
# into a wall of text. Only NEW patterns belong here — a pattern we already fixed coming BACK is
# pushed separately (high priority, hourly) by ovn_failure_triage_cron.sh, so its REGRESSION
# lines are intentionally ignored here rather than reported twice. Deliberately not its own
# alerter script: the 2026-09-28 notification redesign consolidated four scripts that each
# alerted on the same fact into one, and this must not undo that.
if [ -x "$DIR/scripts/ovn_failure_triage.py" ]; then
  _TRIAGE="$(python3 "$DIR/scripts/ovn_failure_triage.py" "$STATE_DIR" "$DIR/logs" --digest "$DIGEST_HOURS" 2>/dev/null)"
  _TRI_N="$(printf '%s\n' "$_TRIAGE" | grep -c '^NEW: ')"
  if [ "${_TRI_N:-0}" -gt 0 ]; then
    _TRI_LINES="$(printf '%s\n' "$_TRIAGE" | grep '^NEW: ' | head -5 | sed 's/^NEW: /  • /; s/ :: /: /')"
    [ "$_TRI_N" -gt 5 ] && _TRI_LINES="$_TRI_LINES
  …and $((_TRI_N - 5)) more"
    body="$body

🆕 ${_TRI_N} failure pattern(s) seen for the first time this window (never seen before — worth a look):
$_TRI_LINES"
  fi
fi

# 2026-09-19 FIX: only rotate/clear the buffer if the digest actually delivered. Previously
# this ran unconditionally, so a failed send (see send() above) still wiped the accumulated
# stats — the next cycle would report a falsely-quiet window and the failed window's data
# was gone for good. On failure, leave the buffer in place so the next cycle's digest
# naturally accumulates and reports the missed window's items too.
if send "Overnight queue" "robot" "$body"; then
  # clear the buffer (keep one rotation for debugging)
  cp "$BUF" "$BUF.last" 2>/dev/null || true
  : > "$BUF"
else
  echo "$(date '+%Y-%m-%d %H:%M:%S') digest delivery failed — leaving buffer intact for retry+accumulation next cycle" >&2
fi
