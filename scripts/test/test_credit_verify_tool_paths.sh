#!/usr/bin/env bash
# Regression test for ovn_credit_already_satisfied.sh's shadow-verify tool-path
# resolution, calibration round 2 (2026-09-26). After the first round of shadow
# data (2026-09-24/25: bare python/venv substitution + denylist narrowing), 105
# more data points came in with 44 FAILs - almost all environment noise, not
# real credit problems: bare `pytest` was never substituted (only python/python3
# were), several items' own VERIFY text has a duplicated path segment from a
# "cd backend && ./backend/.venv/bin/python3 ..." authoring mistake, and `godot`
# is never resolvable bare anywhere on this box (confirmed: no symlink/alias/
# PATH entry, not even in a login shell) despite being how VERIFY clauses are
# authored - the real pipeline always uses $HOME/godot/godot4.
set -uo pipefail
SCRIPT="${OVN_CREDIT_CHECK:-$HOME/overnight-queue/scripts/ovn_credit_already_satisfied.sh}"
[ -f "$SCRIPT" ] || { echo "  SKIP: $SCRIPT not found on this host"; echo "credit-verify tool-path resolution: 0 passed, 0 failed"; exit 0; }

P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
sed -n '/^_resolve_tool_paths(){/,/^}/p' "$SCRIPT" > "$tmp/fn.sh"
[ -s "$tmp/fn.sh" ] || { echo "  FAIL: could not extract _resolve_tool_paths from $SCRIPT (renamed?)"; echo "credit-verify tool-path resolution: 0 passed, 1 failed"; exit 1; }
source "$tmp/fn.sh"

# ---- 1: bare godot is always substituted for the real full path ----
out="$(_resolve_tool_paths 'godot --headless -s addons/gut/gut_cmdln.gd -gexit')"
ok "bare godot substituted with \$HOME/godot/godot4" "printf '%s' \"\$out\" | grep -q \"^${HOME}/godot/godot4 \""
ok "the rest of the godot command survives unchanged" "printf '%s' \"\$out\" | grep -q -- '-gexit\$'"

# ---- 2: godot after a leading cd/&& is also substituted ----
out="$(_resolve_tool_paths 'cd xlite && godot --headless -gexit')"
ok "godot after 'cd X &&' is substituted" "printf '%s' \"\$out\" | grep -q \"${HOME}/godot/godot4\""

# ---- 3: a real nearby .venv is found and a bare `pytest` gets resolved to it ----
mkdir -p "$tmp/repo/backend/.venv/bin"
touch "$tmp/repo/backend/.venv/bin/pytest" "$tmp/repo/backend/.venv/bin/python3"
chmod +x "$tmp/repo/backend/.venv/bin/pytest" "$tmp/repo/backend/.venv/bin/python3"
( cd "$tmp/repo" && out="$(_resolve_tool_paths 'cd backend && pytest tests/test_x.py -v')"
  echo "$out" > "$tmp/out3.txt" )
ok "bare pytest (no python/python3 token at all) is resolved to the real venv pytest" \
   "grep -q 'backend/.venv/bin/pytest' '$tmp/out3.txt'"
ok "the resolved pytest path actually exists on disk" \
   "p=\$(grep -oE '[^ ]*backend/\.venv/bin/pytest' '$tmp/out3.txt'); (cd '$tmp/repo' && [ -x \"\$p\" ])"

# ---- 4: a WRONG, duplicated-prefix venv path self-heals to the real one ----
( cd "$tmp/repo" && out="$(_resolve_tool_paths 'cd backend && ./backend/.venv/bin/python3 -m pytest tests/test_x.py -v')"
  echo "$out" > "$tmp/out4.txt" )
ok "a double-prefixed 'backend/backend/.venv' reference is NOT what's left in the resolved command" \
   "! grep -q 'backend/backend' '$tmp/out4.txt'"
ok "the self-healed path points at the real, existing .venv" \
   "p=\$(grep -oE '[^ ]*\.venv/bin/python3?' '$tmp/out4.txt' | head -1); (cd '$tmp/repo' && [ -e \"\$p\" ])"

# ---- 5: a bare python3 (already-correct convention) still resolves as before ----
( cd "$tmp/repo/backend" && out="$(_resolve_tool_paths 'python3 -m pytest tests/test_x.py -v')"
  echo "$out" > "$tmp/out5.txt" )
ok "bare python3 (no cd prefix) still resolves to the real venv python3" \
   "grep -q '.venv/bin/python3' '$tmp/out5.txt'"

# ---- 6: no .venv anywhere near -> command passes through unchanged (no false substitution) ----
mkdir -p "$tmp/no_venv_repo"
( cd "$tmp/no_venv_repo" && out="$(_resolve_tool_paths 'python3 -m pytest tests/test_x.py -v')"
  echo "$out" > "$tmp/out6.txt" )
ok "with no .venv found, the command is left as-is (still says bare python3)" \
   "grep -qx 'python3 -m pytest tests/test_x.py -v' '$tmp/out6.txt'"

echo "credit-verify tool-path resolution: $P passed, $F failed"
[ "$F" -eq 0 ]
