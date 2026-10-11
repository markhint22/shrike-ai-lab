#!/usr/bin/env bash
# qacov R10: test_cron_r10.sh must survive being REPLACED IN PLACE while it runs (a deploy rsync over the live dir, an editor save during its ~20 s run). Bash reads a script
# incrementally, so an unwrapped script died with "syntax error near unexpected token" at a stale byte offset (2 of 48 looped runs overlapped an edit and failed that way). The test body is
# therefore one function called on the last line. Here: run a private copy, overwrite the copy in place as soon as it is past its first section, and require the full summary + 0 failures.
# The MUTANT (the same file with the wrapper removed) must NOT finish cleanly. SKIPs without docs/ (loud; OVN_TEST_REQUIRE_DOCS=1 makes it a failure) or without the tools the test needs.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$(cd "$HERE/.." && pwd)"
DOC="$HERE/../../../../docs/patches/cron-r10.txt"; [ -f "$DOC" ] || DOC="$HERE/../../docs/patches/cron-r10.txt"
if [ ! -f "$DOC" ]; then
  if [ "${OVN_TEST_REQUIRE_DOCS:-0}" = 1 ]; then echo "  FAIL: docs/patches/cron-r10.txt not present and OVN_TEST_REQUIRE_DOCS=1"; exit 1; fi
  echo "  SKIP: docs/patches/cron-r10.txt not present - NOTHING WAS TESTED; run it from a checkout (premerge_docs_tests.sh)"; exit 0
fi
for t in flock timeout git python3 nice; do command -v $t >/dev/null 2>&1 || { echo "  SKIP: no $t"; exit 0; }; done
P=0; F=0
ok(){ if [ "$2" = "1" ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
T="$(mktemp -d)"; T="$(cd "$T" && pwd -P)"; trap 'rm -rf "$T"' EXIT
mktree(){ # <name> -> tree $T/<name> shaped like the checkout: scripts/test/test_cron_r10.sh, scripts/<tools>, docs/patches/cron-r10.txt
  local d="$T/$1"; mkdir -p "$d/scripts/test" "$d/docs/patches"
  for f in lib_verify_clause.sh lib_gut_xml.sh lib_worktree.sh ovn_spec_check.sh ovn_spec_gate.py ovn_spec_rules.py ovn_spec_classify.py ovn_backlog_eligibility.py ovn_mutation_supply.py ovn_log_cap.sh; do cp "$SRC/$f" "$d/scripts/" 2>/dev/null; done
  cp "$DOC" "$d/docs/patches/cron-r10.txt"
}
# run <name>: start the copy, wait until it printed its second section header, clobber it in place, wait for it to end
run(){
  local d="$T/$1" out="$T/$1.out" i=0
  ( cd "$d/scripts/test" && timeout 240 bash ./test_cron_r10.sh > "$out" 2>&1 ) &
  local pid=$!
  while ! grep -q '== spec gate scan line' "$out" 2>/dev/null && [ $i -lt 600 ]; do sleep 0.1; i=$((i+1)); done
  printf '#!/usr/bin/env bash\necho "clobbered in place"\n' > "$d/scripts/test/test_cron_r10.sh"
  wait $pid; echo $? > "$T/$1.rc"
}
mktree real; cp "$HERE/test_cron_r10.sh" "$T/real/scripts/test/test_cron_r10.sh"
mktree mut;  sed '1,/^main() {$/{/^main() {$/d;}' "$HERE/test_cron_r10.sh" | sed '$d' | sed '$d' > "$T/mut/scripts/test/test_cron_r10.sh"
ok "the mutant (wrapper removed) differs from the real file and still parses" "$(! cmp -s "$HERE/test_cron_r10.sh" "$T/mut/scripts/test/test_cron_r10.sh" && bash -n "$T/mut/scripts/test/test_cron_r10.sh" && echo 1 || echo 0)"
ok "the real file's body is one function called on the last line" "$([ "$(grep -c '^main() {$' "$HERE/test_cron_r10.sh")" = 1 ] && [ "$(tail -1 "$HERE/test_cron_r10.sh")" = 'main "$@"; exit $?' ] && echo 1 || echo 0)"
run mut
ok "MUTANT (unwrapped), replaced in place mid-run: does NOT finish with a clean summary - proves the assertion below bites" "$(grep -qE '^  [0-9]+ passed, 0 failed$' "$T/mut.out" && [ "$(cat "$T/mut.rc")" = 0 ] && echo 0 || echo 1)"
run real
ok "REAL file, replaced in place mid-run: still runs to the end (summary line, 0 failed, rc 0)" "$(grep -qE '^  [0-9]+ passed, 0 failed$' "$T/real.out" && [ "$(cat "$T/real.rc")" = 0 ] && ! grep -q 'syntax error' "$T/real.out" && echo 1 || echo 0)"
echo "  $P passed, $F failed"; [ "$F" = 0 ]
