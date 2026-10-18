#!/usr/bin/env bash
# Regression test for scan_for_new_files()'s multifile:no guard (run_overnight.sh).
# Extracts the real function body from run_overnight.sh (not a re-implementation) and
# exercises it standalone: a (multifile:no) item must never accumulate extra files from
# the log, while an untagged/multifile:yes item keeps the existing scan-and-load behavior.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }   # 2026-10-16: fail-closed sandbox helpers (see lint_unsafe_rm.py)
HERE="$(cd "$(dirname "$0")" && pwd)"
RO="$HERE/../../run_overnight.sh"; [ -f "$RO" ] || RO="$HERE/../run_overnight.sh"; [ -f "$RO" ] || RO="$HERE/run_overnight.sh"
[ -f "$RO" ] || { echo "  ❌ run_overnight.sh not found"; exit 1; }
rc=0; ok(){ echo "  ✅ $1"; }; fail(){ echo "  ❌ $1"; rc=1; }
tmp="$(safe_mktemp_dir)" || exit 1; trap 'rm -rf "$tmp"' EXIT
cd "$tmp"

# Pull the live function body straight out of run_overnight.sh so this test breaks if the
# guard is ever removed/refactored away, instead of silently testing a stale copy.
python3 - "$RO" > fn.sh <<'PY'
import re, sys
content = open(sys.argv[1]).read()
m = re.search(r'    scan_for_new_files\(\) \{.*?\n    \}', content, re.S)
assert m, "scan_for_new_files() not found in run_overnight.sh"
print(m.group(0))
PY
grep -q "multifile:no" fn.sh && ok "multifile:no guard is present in the live function" || { fail "guard missing from run_overnight.sh — was it removed?"; exit 1; }

is_protected_file() { return 1; }  # no protected files in this test

# real files the log will "mention"
mkdir -p src
echo "x" > src/related.py
echo "y" > src/unrelated_android.kt
echo "z" > src/unrelated_backend.py

run_scan() {  # $1=prompt $2=task_log content
  prompt="$1"
  task_log="$tmp/task.log"
  printf '%s' "$2" > "$task_log"
  FILE_ARGS=(); READ_ARGS=(); ADDED_FILES="|"; max_files=2
  source fn.sh
  scan_for_new_files
}

# Case A: multifile:no — must add ZERO files regardless of what the log mentions
run_scan "[T2] src/related.py — do the thing. (cat:test; multifile:no)" \
  "some aider output mentioning src/related.py and src/unrelated_android.kt and src/unrelated_backend.py"
if [ "${#FILE_ARGS[@]}" -eq 0 ]; then ok "multifile:no item adds zero extra files"; else fail "multifile:no item still added files: ${FILE_ARGS[*]}"; fi

# Case B: no multifile tag at all — existing scan-and-load behavior must be unchanged
run_scan "[T2] src/related.py — do the thing." \
  "some aider output mentioning src/related.py and src/unrelated_android.kt"
if [ "${#FILE_ARGS[@]}" -gt 0 ]; then ok "untagged item still scans and loads mentioned files (unchanged)"; else fail "untagged item's existing scan behavior regressed"; fi

# Case C: explicit multifile:yes — same as untagged, still scans
run_scan "[T3] src/related.py — do the thing. (multifile:yes)" \
  "some aider output mentioning src/related.py"
if [ "${#FILE_ARGS[@]}" -gt 0 ]; then ok "multifile:yes item still scans and loads mentioned files"; else fail "multifile:yes item's scan behavior regressed"; fi

# Case D (2026-10-18): a multifile:no item whose model ASKS for the source under test: the file is fed READ-ONLY (never editable), only the asked-for file (not every token), and
# only once (a second scan finds nothing new, so the retry loop stops instead of spinning).
ask_log=$'Added AGENTS.md to the chat (read-only).\nI need to see the actual implementation of check_x in\nsrc/related.py to write correct tests for it. Let me add\nthat file to the chat.\nsome noise mentioning src/unrelated_backend.py\n'
run_scan "[T1] tests/test_x.py — add a test. (cat:test; multifile:no)" "$ask_log"; rcD=$?
if [ "$rcD" -eq 0 ] && [ "${#FILE_ARGS[@]}" -eq 0 ] && [ "${READ_ARGS[*]}" = "--read src/related.py" ]; then ok "multifile:no item feeds the asked-for source READ-ONLY (FILE_ARGS stays empty, unrelated mention ignored)"; else fail "read-only feed wrong: rc=$rcD FILE_ARGS=(${FILE_ARGS[*]}) READ_ARGS=(${READ_ARGS[*]})"; fi
ADDED_FILES2="$ADDED_FILES"; READ_ARGS2=("${READ_ARGS[@]}")
ADDED_FILES="$ADDED_FILES2"; READ_ARGS=("${READ_ARGS2[@]}"); FILE_ARGS=(); printf '%s' "$ask_log" > "$tmp/task.log"; prompt="[T1] x (multifile:no)"; source fn.sh
if scan_for_new_files; then fail "a second scan re-fed the same file (would loop)"; else ok "second scan finds nothing new (loop stops)"; fi
# Case E: kill switch restores the old behaviour
OVN_NOEDIT_READONLY_FEED=off run_scan "[T1] tests/test_x.py — add a test. (cat:test; multifile:no)" "$ask_log"; rcE=$?
if [ "$rcE" -ne 0 ] && [ "${#READ_ARGS[@]}" -eq 0 ]; then ok "OVN_NOEDIT_READONLY_FEED=off: no feed"; else fail "kill switch ignored"; fi
unset OVN_NOEDIT_READONLY_FEED
# Case F: protected / oversize / .md requests are never fed
cp src/related.py src/big.py; head -c 70000 /dev/zero | tr '\0' 'a' > src/big.py; echo m > src/notes.md
big_log=$'Please add src/big.py to the chat\nPlease add src/notes.md to the chat\n'
run_scan "[T1] tests/test_x.py — add a test. (multifile:no)" "$big_log"; rcF=$?
if [ "$rcF" -ne 0 ] && [ "${#READ_ARGS[@]}" -eq 0 ]; then ok "oversize / markdown requests are not fed"; else fail "oversize or markdown file fed: READ_ARGS=(${READ_ARGS[*]})"; fi

[ $rc -eq 0 ] && echo "  multifile scope guard: ALL PASS" || echo "  multifile scope guard: FAILURES"
exit $rc
