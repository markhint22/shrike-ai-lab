#!/usr/bin/env bash
# 2026-10-10 (harness R10, BX-02): an implement attempt that died on an API/context error ("no edit") is NOT an "already satisfied" finding.
#
# Live defect replayed (xlite, 2026-10-10 02:32 CDT, logs/20261010-023204): the implement call failed with litellm.ContextWindowExceededError (98,084 > 65,536 tokens),
# aider reported "attempt 1 verdict: no-edit", and the post-implement credit then matched file/symbol NAMES in the cycle log (the model's own plan and the error text) and ticked
# get_max_directive_value T1/T2 - a function that was never written. The dependent item could then never be satisfied (parked after 440k tokens).
# Drives the REAL run_aider_fix_task (hermetic fixture, stub aider) with the credit helper replaced by a stub that records whether it was called.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
[ "$(uname)" = Linux ] || { echo "  SKIP: box-only (the hermetic run_overnight.sh fixture needs the Linux runtime, like test_run_overnight_aider2_*); run on the box"; exit 0; }
. "$HERE/lib_ro_aider2_fixture.sh"

# the credit helper stub: records that it ran and "credits" the first open item (what the real helper did on the name match)
credit_stub(){ cat > "$CASE_DIR/credit.sh" <<'EOF'
echo called >> "$CASE_DIR/credit.called"
awk 'done==0 && /^- \[ \] /{sub(/^- \[ \] /,"- [x] (already-satisfied in code, implement-verified) "); done=1} {print}' OVERNIGHT_PROGRESS.md > OVERNIGHT_PROGRESS.md.tmp && mv OVERNIGHT_PROGRESS.md.tmp OVERNIGHT_PROGRESS.md
echo "credited line 3 (matched app.py)"
echo "CREDITED=1"
EOF
}
API_ERR='echo "Your estimated chat context of 93,471 tokens exceeds the 55,000 token limit for openai/qwen-dflash-27B!"
echo "litellm.BadRequestError: OpenAIException - litellm.ContextWindowExceededError: request (98084 tokens) exceeds the available context size (65536 tokens)"
echo "app.py"'

# ---------- A: ContextWindowExceededError, no edit -> the credit helper is NEVER run, nothing is ticked ----------
mk_case apierr_ctx
scout_ok
aplan 2 "$API_ERR"
credit_stub
run_case
ok "A1: the name-match credit helper was not called" '[ ! -e "$CASE_DIR/credit.called" ]'
ok "A2: the log says why it was skipped" 'logged "implement-pass already-satisfied credit SKIPPED"'
ok "A3: no credit commit was made" '! git -C "$REPO" log --format=%s | grep -q "credit item(s) the implement pass found already satisfied"'
ok "A4: the item list is untouched (no [x])" '! grep -q "^- \[x\]" "$REPO/OVERNIGHT_PROGRESS.md"'
eq "A5: the cycle reports the API error status (not a pushed/credited landing)" "$OUT" "error(model/API error - see log)"
ok "A6: nothing reached origin beyond the seed" '[ "$(git -C "$ORIGIN" rev-parse claude/feature)" = "$(git -C "$ORIGIN" rev-parse main)" ]'

# ---------- B: a BadRequestError that is not a context overflow is skipped too ----------
mk_case apierr_bad
scout_ok
aplan 2 'echo "litellm.BadRequestError: OpenAIException - invalid request"; echo "app.py already done, no changes needed"'
credit_stub
run_case
ok "B1: BadRequestError + 'already done' prose in the same log -> still no credit" '[ ! -e "$CASE_DIR/credit.called" ]'

# ---------- C: CONTROL - a real "already satisfied" conclusion with no API error is still credited ----------
mk_case ctl_ok
scout_ok
aplan 2 'echo "app.py already returns correct value, nothing to change"'
credit_stub
run_case
ok "C1: no API error -> the credit helper runs" '[ -e "$CASE_DIR/credit.called" ]'
ok "C2: ... and its credit commit is created" 'git -C "$REPO" log --format=%s | grep -q "credit item(s) the implement pass found already satisfied"'
ok "C3: ... and the guard line is absent" '! logged "implement-pass already-satisfied credit SKIPPED"'

# ---------- D: MUTATION / kill switch - OVN_IMPL_CREDIT_API_GUARD=off restores the old behaviour (credits on the error log) ----------
mk_case mut_off
scout_ok
aplan 2 "$API_ERR"
credit_stub
OVN_IMPL_CREDIT_API_GUARD=off run_case
ok "D1: guard off -> the credit helper runs on the API-error log (the original defect)" '[ -e "$CASE_DIR/credit.called" ]'
ok "D2: ... and the item gets ticked and committed" 'git -C "$REPO" log --format=%s | grep -q "credit item(s) the implement pass found already satisfied"'

summary
