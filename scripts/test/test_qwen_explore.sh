#!/bin/bash
# Bash wrapper so run_all.sh (register_new_tests.py) executes test_qwen_explore.py (the box-side Qwen exploratory researcher: scripts/ovn_qwen_explore.py).
# Hermetic (stub LiteLLM + stub red-before checker). The ~150 behaviour checks take a few minutes; the MUTATION PROOFS (every check re-run against a scratch copy of the script with that
# behaviour removed) take roughly an hour on a loaded machine, so run_all.sh runs WITHOUT them by default (QE_TEST_NO_MUT=1). Run the full proofs with:  QE_FULL_MUT=1 bash test_qwen_explore.sh
# (or python3 test_qwen_explore.py directly). QE_TEST_MUT="substring|substring" runs only the mutations whose name contains one of the substrings.
# The queue hook has its own suite: test_qwen_explore_hook.sh. The critic stage has test_qwen_critic.sh.
HERE="$(cd "$(dirname "$0")" && pwd)"
export NTFY_SERVER="${NTFY_SERVER:-http://127.0.0.1:8099}"
if [ "${QE_FULL_MUT:-0}" != "1" ]; then export QE_TEST_NO_MUT=1; echo "(mutation proofs skipped: QE_FULL_MUT=1 runs them)"; fi
PY="$(command -v python3.12 || command -v python3)"
"$PY" "$HERE/test_qwen_explore.py"
rc=$?
echo "test_qwen_explore.py rc=$rc"
exit $rc
