#!/usr/bin/env python3
"""Best-of-N pilot (gated OVN_BESTOF_N>1): for HARD items, if the solve didn't LAND
(reverted/no-op), re-run the whole solve up to N times (each call resets to a clean baseline
internally) and keep the first that lands. The per-cycle test gate is the selector (test-based
selection). Contained at the CALL SITE — does not touch the delicate verify/gate logic.
Default N=1 => identical to current behavior; hard-items-only bounds the extra GPU time."""
p = "run_overnight.sh"
s = open(p).read()
if "OVN_BESTOF_N" in s:
    print("already patched"); raise SystemExit
call = ('    STATUS="$(run_aider_fix_task "$ID" "$REPO" "$PROMPT" "$BRANCH" "$PERSISTENT" '
        '"$TASK_LOG" "$MAP_TOKENS" "$SKIP_AGENTS_MD" "$MAX_FILES" "$PROTECTED_FILES" "$TIMEOUT_SECS")"\n')
anchor = call + '    VERSION_OR_BRANCH="$BRANCH"\n  fi\n'
block = (
    call +
    '    # Best-of-N pilot (2026-09-04, gated OVN_BESTOF_N>1): a HARD item that did not land gets\n'
    '    # re-solved from a fresh baseline up to N times; the test gate keeps the first that lands.\n'
    '    _bestn="${OVN_BESTOF_N:-1}"; _btry=1\n'
    '    if [ "$_bestn" -gt 1 ] && echo "$PROMPT" | grep -qiE \'\\[T[45]\\]|refactor|multi-file|multiple files\'; then\n'
    '      while [ "$_btry" -lt "$_bestn" ] && echo "$STATUS" | grep -qiE \'revert|no-op|noop|fail|blocked|error\'; do\n'
    '        _btry=$((_btry+1))\n'
    '        log "best-of-N: item ${ID} attempt ${_btry}/${_bestn} (prev: ${STATUS})"\n'
    '        STATUS="$(run_aider_fix_task "$ID" "$REPO" "$PROMPT" "$BRANCH" "$PERSISTENT" "$TASK_LOG" "$MAP_TOKENS" "$SKIP_AGENTS_MD" "$MAX_FILES" "$PROTECTED_FILES" "$TIMEOUT_SECS")"\n'
    '      done\n'
    '    fi\n'
    '    VERSION_OR_BRANCH="$BRANCH"\n  fi\n'
)
assert s.count(anchor) == 1, f"anchor count={s.count(anchor)}"
open(p, "w").write(s.replace(anchor, block, 1))
print("patched best-of-N pilot (gated OVN_BESTOF_N>1, hard-items-only)")
