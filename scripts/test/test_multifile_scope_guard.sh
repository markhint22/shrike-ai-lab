#!/usr/bin/env bash
# Regression test for scan_for_new_files()'s multifile:no guard (run_overnight.sh).
# Extracts the real function body from run_overnight.sh (not a re-implementation) and
# exercises it standalone: a (multifile:no) item must never accumulate extra files from
# the log, while an untagged/multifile:yes item keeps the existing scan-and-load behavior.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
RO="$HERE/../../run_overnight.sh"; [ -f "$RO" ] || RO="$HERE/../run_overnight.sh"; [ -f "$RO" ] || RO="$HERE/run_overnight.sh"
[ -f "$RO" ] || { echo "  ❌ run_overnight.sh not found"; exit 1; }
rc=0; ok(){ echo "  ✅ $1"; }; fail(){ echo "  ❌ $1"; rc=1; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
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
  FILE_ARGS=(); ADDED_FILES="|"; max_files=2
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

[ $rc -eq 0 ] && echo "  multifile scope guard: ALL PASS" || echo "  multifile scope guard: FAILURES"
exit $rc
