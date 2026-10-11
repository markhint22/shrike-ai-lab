#!/usr/bin/env bash
# qacov R10: the docs-dependent tests (test_cron_r10, test_gitignore_live_dir) must not be SILENT no-ops where docs/ is absent (the box's live dir): without docs/ they SKIP loudly
# (exit 0, "NOTHING WAS TESTED"), and with OVN_TEST_REQUIRE_DOCS=1 the same situation is a FAILURE; premerge_docs_tests.sh turns any SKIP into a failure. Copies each test into a
# private tree that has no docs/ and runs it both ways.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
P=0; F=0
ok(){ if [ "$2" = "1" ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
T="$(mktemp -d)"; T="$(cd "$T" && pwd -P)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/scripts/test"; for t in test_cron_r10.sh test_gitignore_live_dir.sh; do cp "$HERE/$t" "$T/scripts/test/"; done
cp "$HERE/../../ovn_git_sync.sh" "$T/ovn_git_sync.sh" 2>/dev/null || cp "$HERE/../ovn_git_sync.sh" "$T/ovn_git_sync.sh" 2>/dev/null
for t in test_cron_r10.sh test_gitignore_live_dir.sh; do
  out="$(env -u OVN_TEST_REQUIRE_DOCS bash "$T/scripts/test/$t" 2>&1)"; rc=$?
  ok "$t without docs/: exits 0 with a loud 'SKIP ... NOTHING WAS TESTED' line" "$([ $rc = 0 ] && printf '%s' "$out" | grep -q 'SKIP.*NOTHING WAS TESTED' && echo 1 || echo 0)"
  out="$(OVN_TEST_REQUIRE_DOCS=1 bash "$T/scripts/test/$t" 2>&1)"; rc=$?
  ok "$t without docs/ and OVN_TEST_REQUIRE_DOCS=1: FAILS (rc!=0, says why)" "$([ $rc != 0 ] && printf '%s' "$out" | grep -q 'OVN_TEST_REQUIRE_DOCS=1' && echo 1 || echo 0)"
done
# the wrapper: a SKIP anywhere is a failure, so run it against the real tree (docs/ present in a checkout -> must pass; skipped when this tree has none)
if [ -f "$HERE/../../../../docs/patches/cron-r10.txt" ]; then
  mkdir -p "$T/fake/scripts/test"; cp "$HERE/premerge_docs_tests.sh" "$T/fake/scripts/test/"; printf '#!/usr/bin/env bash\necho "  SKIP: stub"; exit 0\n' > "$T/fake/scripts/test/test_cron_r10.sh"; cp "$HERE/test_gitignore_live_dir.sh" "$T/fake/scripts/test/"
  bash "$T/fake/scripts/test/premerge_docs_tests.sh" > "$T/wrap.out" 2>&1; wrc=$?
  ok "premerge_docs_tests.sh: a test that merely SKIPs (exit 0) makes the wrapper fail" "$([ $wrc != 0 ] && grep -q 'skipped (nothing tested)' "$T/wrap.out" && echo 1 || echo 0)"
else
  echo "  SKIP: wrapper check needs a checkout with docs/"
fi
echo "  $P passed, $F failed"; [ "$F" = 0 ]
