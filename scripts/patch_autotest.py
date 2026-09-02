#!/usr/bin/env python3
"""Add an aider AUTO-TEST feedback loop to the implement pass. Diagnosis (2026-08-26):
repos are GREEN at origin/main, but the model writes code BLIND (no shell, tests run
only AFTER commit) so its own new tests/fixes fail -> nothing lands clean. With
--auto-test + --test-cmd, aider runs the repo's pytest after each edit and feeds
failures back so the model fixes to green before committing. Scoped to repos that
have a provisioned .venv/bin/pytest (the python backends); others are unchanged."""
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
before = s
changes = 0

# 1) derive TEST_ARGS just before the implement attempt loop
A_OLD = '    ATTEMPT=1\n    while [ "$ATTEMPT" -le "$MAX_IMPLEMENT_ATTEMPTS" ]; do'
A_NEW = (
'    # Auto-test feedback (2026-08-26): if a provisioned pytest venv exists, let aider\n'
'    # run the suite after each edit and feed failures back, so the model fixes its own\n'
'    # code to GREEN before committing (it was writing blind and its own tests failed).\n'
'    TEST_ARGS=()\n'
'    _pytest_dir="$(find . -maxdepth 4 -type f -path \'*/.venv/bin/pytest\' 2>/dev/null | head -1 | sed \'s#/.venv/bin/pytest##\')"\n'
'    if [ -n "$_pytest_dir" ]; then\n'
'      TEST_ARGS=(--auto-test --test-cmd "cd \\"$_pytest_dir\\" && ./.venv/bin/pytest -q --no-cov -x")\n'
'      echo "--- auto-test enabled: cd $_pytest_dir && pytest -q --no-cov -x ---" >> "$task_log"\n'
'    fi\n'
'    ATTEMPT=1\n    while [ "$ATTEMPT" -le "$MAX_IMPLEMENT_ATTEMPTS" ]; do')
if A_OLD in s:
    s = s.replace(A_OLD, A_NEW, 1); changes += 1

# 2) add TEST_ARGS to the implement aider call (the one with $aider_timeout)
B_OLD = ('      timeout "$aider_timeout" aider "${AIDER_BASE_ARGS[@]}" \\\n'
         '        ${READ_ARGS[@]+"${READ_ARGS[@]}"} \\')
B_NEW = ('      timeout "$aider_timeout" aider "${AIDER_BASE_ARGS[@]}" \\\n'
         '        ${TEST_ARGS[@]+"${TEST_ARGS[@]}"} \\\n'
         '        ${READ_ARGS[@]+"${READ_ARGS[@]}"} \\')
if B_OLD in s:
    s = s.replace(B_OLD, B_NEW, 1); changes += 1

# 3) reframe the prompt: aider now runs tests DURING the session; fix the failures it shows
C_OLD = ("The runner automatically runs the real test suite for you AFTER you commit, so you "
         "never need to verify by running - just open the specific file named in the item, make "
         "the code change, and let your commit stand.")
C_NEW = ("For most tasks aider will AUTOMATICALLY run the project's test suite for you after your "
         "edits and paste any failures back to you - when it does, READ the failure and FIX your "
         "code (or your test) so the suite goes green before you finish; that is how your work "
         "actually lands. You still cannot type shell commands yourself - aider runs the tests, "
         "you just react to the results. Open the specific file named in the item, make the "
         "change, and iterate to green.")
if C_OLD in s:
    s = s.replace(C_OLD, C_NEW, 1); changes += 1

if changes == 0:
    print("NO anchors matched; nothing modified"); sys.exit(1)
open(p, "w", encoding="utf-8").write(s)
print(f"auto-test wired: {changes}/3 blocks changed")
