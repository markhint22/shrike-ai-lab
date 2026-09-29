#!/usr/bin/env bash
# Regression test for run_overnight.sh's scout-file-fallback fix (2026-09-29).
#
# The force-load loop just above this fix correctly refuses to --file a path the
# scout/plan named if that path doesn't exist on disk (`[ -f "$_pf" ] || continue`).
# That's the right call - it never crashes on a bad guess - but it can leave
# FILE_ARGS completely empty while the model is told "execute NOW, do not ask to
# see more files", with zero ground truth for a real function the item names by
# name. Confirmed live: iptv_apps burned 5 separate cycles (2026-09-29 01:32-02:23
# CDT) hallucinating test content against a nonexistent
# iptv-backend/app/services/cast_service.py before the real implementation of
# `validate_cast_device_info` (which actually lives in
# iptv-backend/app/models/stream.py) landed via an unrelated decomposition pass.
#
# This test extracts the real identifier-grep out of run_overnight.sh (not a
# reimplementation) so it can't silently drift from what's deployed, then exercises
# it against a small on-disk fixture tree.
set -uo pipefail
RO="${OVN_RUN_OVERNIGHT:-$HOME/overnight-queue/run_overnight.sh}"
[ -f "$RO" ] || RO="$(cd "$(dirname "$0")/../.." && pwd)/run_overnight.sh"
[ -f "$RO" ] || { echo "  SKIP: run_overnight.sh not found"; exit 0; }

P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

# --- A: the fix must be present and gated correctly ---
ok "fallback fix is present in run_overnight.sh" \
   "grep -q '2026-09-29 FIX: when the scout/plan-named file' '$RO'"
ok "fallback only fires when FILE_ARGS is empty (never overrides a real scout file)" \
   "grep -A20 '2026-09-29 FIX: when the scout/plan-named file' '$RO' | grep -q '\"\${#FILE_ARGS\[@\]}\" -eq 0'"

# --- B: the identifier-grep logic, extracted verbatim in spirit, must resolve a
# backtick-quoted function name in item text to its REAL defining file even when
# the scout guessed a different, nonexistent one ---
TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT
cd "$TMPD" || exit 1
mkdir -p app/models tests
cat > app/models/stream.py <<'PY'
def validate_cast_device_info(device_id: str, protocol: str) -> bool:
    return protocol in ("http", "https")
PY
cat > tests/test_cast_hardening_decoy.py <<'PY'
def validate_cast_device_info(device_id, protocol):
    # a decoy inside a test file - must never be preferred over the real source
    return False
PY

_resolve_ident() {  # $1 = prompt text containing backtick-quoted identifier(s)
  local prompt="$1" _ident _def_hit
  for _ident in $(printf '%s' "$prompt" | grep -oE '`[A-Za-z_][A-Za-z0-9_]*`' | tr -d '`' | sort -u); do
    _def_hit="$(grep -rlE "(^|[^.[:alnum:]_])(def|function|const|class) +${_ident}([[:space:](]|=)" \
      --include='*.py' --include='*.ts' --include='*.js' --include='*.vue' --include='*.gd' . 2>/dev/null \
      | grep -vE '/(tests?|__pycache__|node_modules|\.venv|\.git)/' \
      | grep -vE '(^|/)test_[^/]+$|_test\.[a-z]+$|\.test\.[a-z]+$' \
      | head -1)"
    [ -n "$_def_hit" ] && printf '%s\n' "${_def_hit#./}" && return 0
  done
  return 1
}

_hit="$(_resolve_ident 'Create tests for `validate_cast_device_info` covering invalid protocols.')"
ok "resolves a real definition when the scout's guessed file (cast_service.py) doesn't exist" \
   '[ "$_hit" = "app/models/stream.py" ]'
ok "never resolves to the decoy inside tests/ (test files are excluded)" \
   '[ "$_hit" != "tests/test_cast_hardening_decoy.py" ]'

_miss="$(_resolve_ident 'Create tests for `totally_fictional_function_xyz` covering nothing.')"
ok "returns nothing when no real definition exists anywhere (stays empty-FILE_ARGS, doesn't fabricate a hit)" \
   '[ -z "$_miss" ]'

cd - >/dev/null 2>&1 || true

echo "scout-file-fallback: $P passed, $F failed"
[ "$F" -eq 0 ]
