#!/usr/bin/env bash
# Regression test: ovn_classify_fail.sh must not mislabel a genuine LLM/API-layer error as
# "test-red" (2026-09-10).
#
# Real incident: run_overnight.sh's error_status() already correctly detects an API-layer
# failure (ContextWindowExceededError/BadRequestError/APIError/RateLimitError/a raw Traceback,
# or a non-zero aider exit) and tags the status "error(model/API error - see log)" or
# "error(exit=N)" BEFORE this classifier ever runs. But ovn_classify_fail.sh ignored that
# up-front signal and fell through to scanning the raw log content instead — and a stack trace
# or error dump frequently contains incidental text ("assert", "failing", etc.) that the
# test-red regex matches. Confirmed: 8 of billwatch's 9 "test-red" fail_reasons overnight on
# 2026-09-10 were actually this — a genuine infra/API hiccup misfiled as a code-quality problem,
# muddying the real signal.
set -uo pipefail
C="${OVN_CLASSIFY_FAIL:-$HOME/overnight-queue/ovn_classify_fail.sh}"
[ -f "$C" ] || { echo "  SKIP: $C not found on this host"; exit 0; }
P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

tmp="$(mktemp -d)"

# a log whose content WOULD match the test-red regex (contains "assert"/"failing"), but the
# status says this was actually an API-layer error — the status must win.
cat > "$tmp/api_error.log" <<'EOF'
Traceback (most recent call last):
  File "aider/coders/base_coder.py", line 500, in send
    raise BadRequestError("context window exceeded, model returned an error mid-generation")
litellm.exceptions.BadRequestError: OpenAIException - request failed
Some internal library assert failing here, incidental text that used to trigger test-red
EOF
ok "error(model/API...) status classifies as model-api-error, not test-red" \
   "[ \"\$(bash "$C" "$tmp/api_error.log" 'error(model/API error - see log)')\" = model-api-error ]"
ok "error(exit=N) status also classifies as model-api-error" \
   "[ \"\$(bash "$C" "$tmp/api_error.log" 'error(exit=1)')\" = model-api-error ]"

# a genuine test failure (no error() status prefix) must still classify as test-red — this
# fix must not swallow the real case it's meant to be distinguished from.
cat > "$tmp/real_testred.log" <<'EOF'
1 failed, 40 passed
FAILED tests/test_foo.py::test_bar - AssertionError: assert 1 == 2
EOF
ok "a genuine test failure (no-op status) still classifies as test-red" \
   "[ \"\$(bash "$C" "$tmp/real_testred.log" 'no-op')\" = test-red ]"

# landed/needs-decision/oversized precedence must be unaffected by the new case
cat > "$tmp/empty.log" <<'EOF'
nothing interesting here
EOF
ok "a landed status still classifies as landed regardless of log content" \
   "[ \"\$(bash "$C" "$tmp/empty.log" 'landed')\" = landed ]"

# --- FIXED BUG regression guard (2026-09-10): three status strings that already name their own
# cause were falling through to the log-content scan (which usually didn't match) and landing
# in fail_reason=unknown. skip(exhausted) alone was 219 of 295 (74%) of all "unknown" records
# fleet-wide - a benign "nothing to do right now" state, not a failure. ---
cat > "$tmp/exhausted.log" <<'EOF'
--- skip: 0 doable items (exhausted; resumes when refilled) ---
EOF
ok "skip(exhausted) classifies as queue-exhausted, not unknown" \
   "[ \"\$(bash "$C" "$tmp/exhausted.log" 'skip(exhausted)')\" = queue-exhausted ]"

cat > "$tmp/buildbreak.log" <<'EOF'
some unrelated log content with no build-red-matching text
EOF
ok "reverted(build-break) status classifies as build-red even with unmatching log content" \
   "[ \"\$(bash "$C" "$tmp/buildbreak.log" 'reverted(build-break)')\" = build-red ]"

cat > "$tmp/revertedred.log" <<'EOF'
some unrelated log content with no test-red-matching text
EOF
ok "no-op(reverted-red) status classifies as test-red even with unmatching log content" \
   "[ \"\$(bash "$C" "$tmp/revertedred.log" 'no-op(reverted-red)')\" = test-red ]"

ok "error-transient(API/network) status classifies as model-api-error" \
   "[ \"\$(bash "$C" "$tmp/empty.log" 'error-transient(API/network - see log)')\" = model-api-error ]"

rm -rf "$tmp"
echo "Classify-fail model-api-error: $P passed, $F failed"
[ "$F" -eq 0 ]
