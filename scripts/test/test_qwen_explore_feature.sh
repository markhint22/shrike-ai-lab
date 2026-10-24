#!/bin/bash
# Bash wrapper so run_all.sh (register_new_tests.py) executes test_qwen_explore_feature.py: the explorer's feature-ideation lens (scripts/ovn_qe_feature.py + ovn_qwen_explore.py),
# OVN_QE_FEATURE_LENS=off|shadow|on, the feature cap, the zero-call-pass cap accounting and the small-repo candidate fallback. Hermetic (stub LiteLLM + stub red-before checker).
# The ~95 behaviour checks take ~25 s; the MUTANTS (every rule re-run against a scratch copy of the scripts with that behaviour removed) take a few more minutes, so run_all.sh runs WITHOUT
# them by default (QE_TEST_NO_MUT=1). Run the full proofs with:  QE_FULL_MUT=1 bash test_qwen_explore_feature.sh   (QE_TEST_MUT="substring|substring" selects mutants by name).
HERE="$(cd "$(dirname "$0")" && pwd)"
export NTFY_SERVER="${NTFY_SERVER:-http://127.0.0.1:8099}"
if [ "${QE_FULL_MUT:-0}" != "1" ]; then export QE_TEST_NO_MUT=1; echo "(mutants skipped: QE_FULL_MUT=1 runs them)"; fi
PY="$(command -v python3.12 || command -v python3)"
"$PY" "$HERE/test_qwen_explore_feature.py"
rc=$?
echo "test_qwen_explore_feature.py rc=$rc"
exit $rc
