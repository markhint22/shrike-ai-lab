#!/bin/bash
# Bash wrapper so run_all.sh executes test_qwen_critic.py (the Qwen critic stage of scripts/ovn_qwen_explore.py: OVN_QWEN_CRITIC=off|shadow|on).
# Hermetic. Mutation proofs are skipped by default (QE_TEST_NO_MUT=1) to keep run_all.sh fast; QE_FULL_MUT=1 runs them (several minutes).
HERE="$(cd "$(dirname "$0")" && pwd)"
export NTFY_SERVER="${NTFY_SERVER:-http://127.0.0.1:8099}"
if [ "${QE_FULL_MUT:-0}" != "1" ]; then export QE_TEST_NO_MUT=1; echo "(mutation proofs skipped: QE_FULL_MUT=1 runs them)"; fi
PY="$(command -v python3.12 || command -v python3)"
"$PY" "$HERE/test_qwen_critic.py"
rc=$?
echo "test_qwen_critic.py rc=$rc"
exit $rc
