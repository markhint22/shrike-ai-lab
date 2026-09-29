#!/usr/bin/env bash
# Tests for run_overnight.sh's record_outcome() status->class classification.
#
# Written 2026-09-09 after a real incident: the inline higher-tier sub-flow unconditionally
# echoed "stage(higher-tier)" regardless of what actually happened, that string matched no known
# failure pattern, and record_outcome's `*) cls=landed` catch-all silently counted EVERY such
# attempt as a land. The reported T3+ "land rate" was ~95%; the real rate (state/stage_runs/*.jsonl
# ground truth) was ~15-20%. Both halves of that bug are covered here:
#   1. record_outcome must never default an unrecognized status to "landed" (catch-all -> unknown).
#   2. the specific status strings the inline higher-tier flow can emit classify correctly.
# Source the REAL function out of run_overnight.sh (not a reimplementation) so this can't drift
# from what's actually deployed.
set -uo pipefail
R="${OVN_RUNNER:-$HOME/overnight-queue/run_overnight.sh}"
P=0; F=0
ok(){  if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }
nok(){ if eval "$2" >/dev/null 2>&1; then F=$((F+1)); echo "  FAIL(expected-false): $1"; else P=$((P+1)); fi; }

[ -f "$R" ] || { echo "  SKIP: $R not found on this host"; exit 0; }

FN_SRC="$(sed -n '/^record_outcome(/,/^}/p' "$R")"
[ -n "$FN_SRC" ] || { echo "  FAIL: could not extract record_outcome() from $R"; exit 1; }
eval "$FN_SRC"
# record_outcome references $SCRIPT_DIR (for ovn_classify_fail.sh) which normally comes from
# run_overnight.sh's own top-of-file setup — extracting just the function skips that, and this
# test runs under `set -u`, so it must be defined or every non-landed status errors out silently
# swallowed by `eval`'s exit-code-only ok()/nok() (a false pass would have hidden this).
SCRIPT_DIR="$(cd "$(dirname "$R")" && pwd)"

STATE_DIR="$(mktemp -d)"
class_of(){ # $1=status $2=id(unique per call so lines don't collide)
  : > "$STATE_DIR/outcomes.jsonl"
  record_outcome "$2" repo "$1" "" aider_fix 1 /dev/null
  grep -o '"class":"[a-z]*"' "$STATE_DIR/outcomes.jsonl" | head -1 | sed -E 's/.*"([a-z]+)".*/\1/'
}
sev_of(){ # $1=status $2=id(unique per call so lines don't collide)
  : > "$STATE_DIR/outcomes.jsonl"
  record_outcome "$2" repo "$1" "" aider_fix 1 /dev/null
  grep -o '"severity":"[a-z]*"' "$STATE_DIR/outcomes.jsonl" | head -1 | sed -E 's/.*"([a-z]+)".*/\1/'
}

# ---- 1. the exact statuses involved in the 2026-09-09 incident ----
ok "FIXED success status classifies as landed"  "[ \"\$(class_of 'pushed(tests:pass) stage(higher-tier)' t1)\" = landed ]"
ok "FIXED failure status classifies as noop"    "[ \"\$(class_of 'no-op(stage-unverified) stage(higher-tier)' t2)\" = noop ]"
# ---- 2. the OLD buggy status must NOT silently land if it ever reappears ----
nok "the historically-buggy bare status does NOT land" "[ \"\$(class_of 'stage(higher-tier)' t3)\" = landed ]"
ok  "the historically-buggy bare status is now unknown (visible, not a false win)" "[ \"\$(class_of 'stage(higher-tier)' t3b)\" = unknown ]"

# ---- 3. regression guard: NO unrecognized status silently lands ----
ok "a totally novel/unrecognized status is 'unknown', not 'landed'" \
   "[ \"\$(class_of 'some-brand-new-status-nobody-wrote-yet' t4)\" = unknown ]"
nok "a totally novel/unrecognized status never classifies as landed" \
   "[ \"\$(class_of 'some-brand-new-status-nobody-wrote-yet' t4b)\" = landed ]"

# ---- 4. known-good statuses still land (no regression from tightening the catch-all) ----
ok "pushed(tests:pass) lands"     "[ \"\$(class_of 'pushed(tests:pass)' t5)\" = landed ]"
ok "pushed(after-rebase) lands"   "[ \"\$(class_of 'pushed(after-rebase)' t6)\" = landed ]"
ok "train_job success 'trained' lands" "[ \"\$(class_of 'trained' t7)\" = landed ]"

# ---- 5. a MIXED partial-success train_job status must NOT be counted as a clean land ----
nok "'trained-but-inference-restart-failed(...)' does not silently land" \
    "[ \"\$(class_of 'trained-but-inference-restart-failed(exit=1) — check manually' t8)\" = landed ]"

# ---- 6. known-bad statuses still classify correctly (no regression) ----
ok "reverted(build-break) -> reverted"     "[ \"\$(class_of 'reverted(build-break)' t9)\" = reverted ]"
ok "no-op(NEEDS-DECISION) -> noop"         "[ \"\$(class_of 'no-op(NEEDS-DECISION)' t10)\" = noop ]"
ok "skip(exhausted) -> skipped"            "[ \"\$(class_of 'skip(exhausted)' t11)\" = skipped ]"
ok "error-transient(...) -> error"         "[ \"\$(class_of 'error-transient(API/network - see log)' t12)\" = error ]"

# ---- 6b. 2026-09-15 incident: the inline higher-tier flow's "no doable T3+ item found" /
# "another stage runner holds the lock" early exits wrote NO new stage_runs file, so the old
# stale-summary fallback re-reported a PAST run's outcome as if it just happened — 19 consecutive
# benign "nothing to do" cycles on xlite all got recorded as fresh no-op(stage-unverified) godot
# failures overnight. Fixed by emitting this new status when the early-exit phrases are detected
# in THIS invocation's own output, before ever consulting the stale-file fallback.
ok "skip(exhausted) stage(higher-tier) -> skipped (not a false godot failure)" \
   "[ \"\$(class_of 'skip(exhausted) stage(higher-tier)' t12b)\" = skipped ]"

# ---- 6c. 2026-09-28 FIX: ALREADY-DONE (a read-only scout verdict, zero implement attempts -
# same shape as BLOCKED/NEEDS-DECISION) used to fall through to the generic no-op*|noop* pattern
# and get sev=bad, wrongly counting a benign near-zero-cost non-event as a real failure in every
# severity-based pass rate (scripts/ovn_tier_stats.py's per-tier denominator, the hourly/3-hourly
# push notifications it feeds). class stays 'noop' either way (unchanged) - only severity flips.
ok "no-op(ALREADY-DONE) -> class noop (unchanged)"    "[ \"\$(class_of 'no-op(ALREADY-DONE)' t-ad1)\" = noop ]"
ok "no-op(ALREADY-DONE) -> severity neutral (FIXED, was bad)" \
   "[ \"\$(sev_of 'no-op(ALREADY-DONE)' t-ad2)\" = neutral ]"
ok "no-op(BLOCKED) -> severity neutral (no regression from the ALREADY-DONE fix)" \
   "[ \"\$(sev_of 'no-op(BLOCKED)' t-ad3)\" = neutral ]"
ok "no-op(NEEDS-DECISION) -> severity neutral (no regression from the ALREADY-DONE fix)" \
   "[ \"\$(sev_of 'no-op(NEEDS-DECISION)' t-ad4)\" = neutral ]"
# a genuine thrown-away attempt (bare no-op / gate-reverted) must still be sev=bad - the fix must
# not accidentally widen the neutral case to swallow real failures too.
ok "bare no-op (flailed) -> severity bad (unaffected by the ALREADY-DONE fix)" \
   "[ \"\$(sev_of 'no-op' t-ad5)\" = bad ]"
ok "no-op(reverted-red) (gate-reverted) -> severity bad (unaffected by the ALREADY-DONE fix)" \
   "[ \"\$(sev_of 'no-op(reverted-red)' t-ad6)\" = bad ]"
ok "reverted(build-break) -> severity bad" "[ \"\$(sev_of 'reverted(build-break)' t-ad7)\" = bad ]"
ok "pushed(tests:pass) -> severity good"   "[ \"\$(sev_of 'pushed(tests:pass)' t-ad8)\" = good ]"
ok "skip(exhausted) -> severity expected"  "[ \"\$(sev_of 'skip(exhausted)' t-ad9)\" = expected ]"

# ---- 7. structural backstop: the dangerous bare catch-all pattern must not come back verbatim ----
ok "no bare '*) cls=landed' catch-all remains in record_outcome" \
   "! printf '%s' \"\$FN_SRC\" | grep -qE '^\s*\*\)\s*cls=landed'"

# ---- 7b. 2026-09-15: the inline higher-tier caller must check ITS OWN invocation's output for
# the early-exit phrases (not the stale cross-cycle summary file) before deriving a status.
INLINE_SRC="$(sed -n '/HIGHER-TIER SUB-FLOW/,/^    fi$/p' "$R" | head -60)"
ok "inline higher-tier flow checks its own output for early-exit phrases" \
   "printf '%s' \"\$INLINE_SRC\" | grep -q 'no doable T3' && printf '%s' \"\$INLINE_SRC\" | grep -q 'another stage runner holds the lock'"
ok "inline higher-tier flow captures stage-runner output to a fresh temp file (not blind >> task_log)" \
   "printf '%s' \"\$INLINE_SRC\" | grep -q '_STAGE_OUT=\"\$(mktemp)\"'"

# ---- 8. token spend (2026-09-09): sums every "Tokens: X sent, Y received" line in the task_log,
#      so the digest can report real cost by tier, not just pass/fail.
tokens_of(){ # $1=status $2=id $3=task_log
  : > "$STATE_DIR/outcomes.jsonl"
  record_outcome "$2" repo "$1" "" aider_fix 1 "$3"
  cat "$STATE_DIR/outcomes.jsonl"
}
tl1="$(mktemp)"
printf '[T3] item\nTokens: 22k sent, 1.4k received.\nmore output\nTokens: 3.2k sent, 500 received.\n' > "$tl1"
out1="$(tokens_of 'pushed(tests:pass)' t13 "$tl1")"
ok "tokens: sums multiple 'Tokens:' lines across the whole log (sent)" \
   "printf '%s' \"\$out1\" | grep -q '\"tokens_sent\":25200'"
ok "tokens: sums multiple 'Tokens:' lines across the whole log (received)" \
   "printf '%s' \"\$out1\" | grep -q '\"tokens_recv\":1900'"
rm -f "$tl1"

tl2="$(mktemp)"
printf 'no token summary lines in this log at all\n' > "$tl2"
out2="$(tokens_of 'no-op' t14 "$tl2")"
ok "tokens: a log with no 'Tokens:' line reports 0, not empty/error" \
   "printf '%s' \"\$out2\" | grep -q '\"tokens_sent\":0,\"tokens_recv\":0'"
rm -f "$tl2"

ok "tokens: a missing/empty task_log path doesn't crash record_outcome" \
   "tokens_of 'no-op' t15 '' | grep -q '\"tokens_sent\":0'"

# ---- 9. task duration (2026-09-09): $8=duration_s, so per-task time is visible alongside
#      tokens/tier/pass-fail, not just inferable from log timestamps.
: > "$STATE_DIR/outcomes.jsonl"
record_outcome "t16" repo "pushed(tests:pass)" "" aider_fix 1 /dev/null "125"
ok "duration: an explicit duration_s is recorded verbatim" \
   "grep -q '\"duration_s\":125' '$STATE_DIR/outcomes.jsonl'"

: > "$STATE_DIR/outcomes.jsonl"
record_outcome "t17" repo "no-op" "" aider_fix 1 /dev/null
ok "duration: omitting \$8 (older call site) defaults to 0, doesn't crash" \
   "grep -q '\"duration_s\":0' '$STATE_DIR/outcomes.jsonl'"

# ---- 10. tier extraction (2026-09-10): a real [T#] tag must be found even when it sits deep
#      in the task_log - a long "[AUTO-SKIP after N no-op cycles...]" prefix (routinely 80-100+
#      chars) plus normal aider preamble (repo-map, tool-loading, the scout PLAN/VERDICT text)
#      can push the tag well past a too-small read window. Confirmed live: a real [T1] tag at
#      byte 10116 of a 20604-byte log was invisible to a 6000-byte head, showing up as tier="?"
#      in outcome stats even though the source item WAS properly tagged.
tier_of(){ # $1=task_log
  : > "$STATE_DIR/outcomes.jsonl"
  record_outcome "t-tier" repo "pushed(tests:pass)" "" aider_fix 1 "$1"
  grep -o '"tier":"[^"]*"' "$STATE_DIR/outcomes.jsonl" | head -1 | sed -E 's/.*"([^"]*)"$/\1/'
}
tl3="$(mktemp)"
{ python3 -c "print('x' * 9500)"; printf '[AUTO-SKIP after 5 no-op cycles — already-done, mis-targeted, or beyond the 27B; review] [T1] backend/app/services/foo.py — do the thing.\n'; } > "$tl3"
ok "tier: a real [T1] tag ~10KB into the log is still found, not tier=?" \
   "[ \"\$(tier_of "$tl3")\" = 1 ]"
rm -f "$tl3"

tl4="$(mktemp)"
{ python3 -c "print('x' * 45000)"; printf '[T2] some/file.py — do a thing.\n'; } > "$tl4"
ok "tier: a tag beyond even the widened window correctly reports as unknown (?), not a false tier" \
   "[ \"\$(tier_of "$tl4")\" = '?' ]"
rm -f "$tl4"

rm -rf "$STATE_DIR"
echo "Outcome classification: $P passed, $F failed"
[ "$F" -eq 0 ]
