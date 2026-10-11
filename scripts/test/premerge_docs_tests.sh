#!/usr/bin/env bash
# scripts/test/premerge_docs_tests.sh - run the tests that need docs/ (so they are silent no-ops in the box's live dir, which carries no docs/) from a CHECKOUT, and fail on any SKIP.
# qacov R10: test_cron_r10.sh (validates docs/patches/cron-r10.txt) and test_gitignore_live_dir.sh (validates docs/patches/overnight-live.gitignore) print SKIP and exit 0 on the box,
# so the nightly run_all.sh on the box never exercises them. Run this on the Mac (or any checkout of the shared repo) before merging/installing a change to either docs/patches file:
#   bash scripts/overnight-queue/scripts/test/premerge_docs_tests.sh
# Host matrix of the package's tests that SKIP part or all of themselves (each says so on its own SKIP line):
#   test_cron_r10, test_cron_r10_edit_safe, test_gitignore_live_dir ... checkout only (need docs/); this wrapper makes a skip a failure
#   test_hygiene_gate_cap part 2 (real script) .... box only (flock -w 0 is rejected by macOS flock); part 1 runs everywhere
#   test_cov_copy_measure ......................... hosts whose python3 has coverage.py (the box; a Mac venv works)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
rc=0
for t in test_cron_r10.sh test_cron_r10_edit_safe.sh test_gitignore_live_dir.sh; do
  echo "===== $t (OVN_TEST_REQUIRE_DOCS=1) ====="
  out="$(OVN_TEST_REQUIRE_DOCS=1 timeout 600 bash "$HERE/$t" 2>&1)"; trc=$?
  printf '%s\n' "$out"
  if [ "$trc" != 0 ]; then echo "  FAIL: $t rc=$trc"; rc=1
  elif printf '%s\n' "$out" | grep -q 'SKIP'; then echo "  FAIL: $t skipped (nothing tested)"; rc=1; fi
done
[ $rc = 0 ] && echo "premerge docs tests: all ran and passed" || echo "premerge docs tests: FAILED"
exit $rc
