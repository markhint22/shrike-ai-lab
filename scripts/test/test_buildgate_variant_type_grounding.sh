#!/usr/bin/env bash
# Regression test for run_overnight.sh's BUILD-GATE _BUILD_BREAK_NEG_RE fix (2026-09-28).
#
# The negative-exclusion list used to only exclude Godot's "base object of type 'Nil'"
# runtime-access error from tripping the structural BUILD-GATE revert path — every OTHER
# Variant type (Dictionary, Array, Object, ...) that same error shape can name still slipped
# through as a false structural break. Confirmed live: a plain GDScript test-assertion bug
# ("SCRIPT ERROR: Invalid access to property or key of type 'StringName' on a base object of
# type 'Dictionary'") got reverted via the harsher BUILD-GATE path instead of staying
# tests:FAIL (kept + reported), solely because 'Dictionary' wasn't 'Nil'.
#
# Extracts the real _BUILD_BREAK_POS_RE/_BUILD_BREAK_NEG_RE pair out of run_overnight.sh (not
# a reimplementation) so this can't silently drift from what's deployed.
set -uo pipefail
RO="${OVN_RUN_OVERNIGHT:-$HOME/overnight-queue/run_overnight.sh}"
[ -f "$RO" ] || { echo "  SKIP: $RO not found on this host"; exit 0; }

POS="$(grep -oE "_BUILD_BREAK_POS_RE=\"[^\"]+\"" "$RO" | head -1 | sed -E 's/^_BUILD_BREAK_POS_RE="//; s/"$//')"
NEG="$(grep -oE "_BUILD_BREAK_NEG_RE=\"[^\"]+\"" "$RO" | head -1 | sed -E "s/^_BUILD_BREAK_NEG_RE=\"//; s/\"\$//")"
[ -n "$POS" ] || { echo "  FAIL: could not extract _BUILD_BREAK_POS_RE from $RO"; exit 1; }
[ -n "$NEG" ] || { echo "  FAIL: could not extract _BUILD_BREAK_NEG_RE from $RO"; exit 1; }
if ! printf '%s' "$NEG" | grep -qE "base object of type '\[A-Za-z_\]"; then
  echo "  FAIL: _BUILD_BREAK_NEG_RE does not look generalized across Variant types:"
  echo "    $NEG"
  exit 1
fi

P=0; F=0
# 2026-10-08: assertions are evaluated with pipefail OFF - under pipefail `A | grep -q X` is flaky (grep -q exits at its first hit, A may take SIGPIPE: rc 141) and `! A | grep -q X` can mask a real failure
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

# is_build_break <log-text> -> 0 (true, BUILD-GATE would trip) or 1 (false, stays tests:FAIL)
# mirrors run_overnight.sh's own condition exactly: POS matches AND NOT NEG.
is_build_break(){ printf '%s' "$1" | grep -E "$POS" | grep -vE "$NEG" | grep -q .; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# --- A: the exact live false-positive this fix closes — Dictionary base-object type ---
log_dict="SCRIPT ERROR: Invalid access to property or key of type 'StringName' on a base object of type 'Dictionary'."
ok "Dictionary base-object runtime error is NOT a build break (stays tests:FAIL)" \
   "! is_build_break \"\$log_dict\""

# --- B: Array base-object type (a different Variant type, never explicitly enumerated) ---
log_arr="SCRIPT ERROR: Invalid access to property or key of type 'String' on a base object of type 'Array'."
ok "Array base-object runtime error is NOT a build break" "! is_build_break \"\$log_arr\""

# --- C: Object base-object type ---
log_obj="SCRIPT ERROR: Invalid access to property or key of type 'int' on a base object of type 'Object'."
ok "Object base-object runtime error is NOT a build break" "! is_build_break \"\$log_obj\""

# --- D: the ORIGINAL Nil case — unchanged, still excluded (no regression) ---
log_nil="SCRIPT ERROR: Invalid access to property or key of type 'StringName' on a base object of type 'Nil'."
ok "Nil base-object runtime error is still NOT a build break (pre-existing case preserved)" \
   "! is_build_break \"\$log_nil\""

# --- E: a GENUINE structural break must still trip BUILD-GATE (no over-widening) ---
log_syntax="Traceback (most recent call last):
  File \"app/main.py\", line 12
    def foo(:
             ^
SyntaxError: invalid syntax"
ok "a real Python SyntaxError still trips the BUILD-GATE" "is_build_break \"\$log_syntax\""

log_parse="SCRIPT ERROR: Parse Error: Expected end of statement after expression, found \",\" instead."
ok "a real Godot Parse Error still trips the BUILD-GATE" "is_build_break \"\$log_parse\""

log_import="ImportError while loading conftest 'tests/conftest.py'."
ok "a real Python ImportError still trips the BUILD-GATE" "is_build_break \"\$log_import\""

echo "buildgate variant-type grounding: $P passed, $F failed"
[ "$F" -eq 0 ]
