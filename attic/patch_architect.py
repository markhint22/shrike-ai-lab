#!/usr/bin/env python3
"""Gated architect-mode pilot: for HARD items (T4/T5 or refactor/multi-file/type-heavy),
add aider `--architect --auto-accept-architect` to the implement pass so aider runs a
structured plan->edit with the same 27B (research: architect mode ~+3pts same-model, more for
multi-file). Default OFF (OVN_ARCHITECT unset) so the live fleet is unchanged until enabled.
Also honors OVN_EDIT_FORMAT for the whole-vs-udiff A/B (already supported; no change needed)."""
p = "run_overnight.sh"
s = open(p).read()
if "OVN_ARCHITECT" in s:
    print("already patched"); raise SystemExit

# 1) compute _HARD + ARCH_ARGS just before the implement attempt loop
anchor1 = '    ATTEMPT=1\n    while [ "$ATTEMPT" -le "$MAX_IMPLEMENT_ATTEMPTS" ]; do\n'
block1 = (
    '    # Architect-mode pilot (2026-09-04, gated OVN_ARCHITECT=1): hard/multi-file items get\n'
    '    # aider\'s structured plan->edit (same 27B as editor). Simple items keep the fast path.\n'
    '    ARCH_ARGS=()\n'
    '    if [ "${OVN_ARCHITECT:-0}" = 1 ] && echo "$prompt" | grep -qiE \'\\[T[45]\\]|refactor|multi-file|multiple files|architect|generics|type-heavy\'; then\n'
    '      ARCH_ARGS=(--architect --auto-accept-architect)\n'
    '      echo "--- architect mode ON for this hard item ---" >> "$task_log"\n'
    '    fi\n'
    + anchor1
)
assert s.count(anchor1) == 1, f"anchor1 count={s.count(anchor1)}"
s = s.replace(anchor1, block1, 1)

# 2) add ARCH_ARGS to the implement aider invocation
anchor2 = ('      timeout "$aider_timeout" aider "${AIDER_BASE_ARGS[@]}" \\\n'
           '        ${TEST_ARGS[@]+"${TEST_ARGS[@]}"} \\\n')
block2 = ('      timeout "$aider_timeout" aider "${AIDER_BASE_ARGS[@]}" \\\n'
          '        ${ARCH_ARGS[@]+"${ARCH_ARGS[@]}"} \\\n'
          '        ${TEST_ARGS[@]+"${TEST_ARGS[@]}"} \\\n')
assert s.count(anchor2) == 1, f"anchor2 count={s.count(anchor2)}"
s = s.replace(anchor2, block2, 1)

open(p, "w").write(s)
print("patched architect-mode pilot (gated OVN_ARCHITECT=1)")
