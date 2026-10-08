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
# 2026-10-03: _resolve_tool_paths moved to lib_verify_clause.sh (shared with the runner's auto-credit, harness X) - test the copy in THIS tree, not the live dir.
_HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="${OVN_CREDIT_CHECK:-$_HERE/../lib_verify_clause.sh}"
[ -f "$SCRIPT" ] || SCRIPT="$HOME/overnight-queue/scripts/lib_verify_clause.sh"
[ -f "$SCRIPT" ] || { echo "  SKIP: $SCRIPT not found on this host"; echo "credit-verify tool-path resolution: 0 passed, 0 failed"; exit 0; }

P=0; F=0
# 2026-10-08: assertions are evaluated with pipefail OFF - under pipefail `A | grep -q X` is flaky (grep -q exits at its first hit, A may take SIGPIPE: rc 141) and `! A | grep -q X` can mask a real failure
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

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


# ---- 7 (round 3, 2026-09-27): a SYMLINKED .venv is still found (find needs -L) ----
mkdir -p "$tmp/symlink_repo/real_venv/bin"
touch "$tmp/symlink_repo/real_venv/bin/python3"
chmod +x "$tmp/symlink_repo/real_venv/bin/python3"
ln -s "$tmp/symlink_repo/real_venv" "$tmp/symlink_repo/.venv"
( cd "$tmp/symlink_repo" && out="$(_resolve_tool_paths 'python3 -m pytest tests/test_x.py -v')"
  echo "$out" > "$tmp/out7.txt" )
ok "a symlinked .venv (not a real directory) is still found and resolved" \
   "grep -q '.venv/bin/python3' '$tmp/out7.txt'"

# ---- 8 (round 3): a genuinely BROKEN (self-referential) symlinked .venv still correctly finds nothing ----
mkdir -p "$tmp/broken_symlink_repo"
ln -s "$tmp/broken_symlink_repo/.venv" "$tmp/broken_symlink_repo/.venv"
( cd "$tmp/broken_symlink_repo" && out="$(_resolve_tool_paths 'python3 -m pytest tests/test_x.py -v')"
  echo "$out" > "$tmp/out8.txt" )
ok "a broken self-referential .venv symlink does not crash and leaves the command unresolved (correctly - out of scope, tracked separately)" \
   "grep -qx 'python3 -m pytest tests/test_x.py -v' '$tmp/out8.txt'"

# ---- 9 (round 3): the double-prefix self-heal now produces an ABSOLUTE path (not just a
# no-double-prefix string) - the actual fix, since a relative "backend/.venv/..." path
# substituted back into a "cd backend && ..." command still resolves wrong even without
# a literal "backend/backend" duplication in the text ----
( cd "$tmp/repo" && out="$(_resolve_tool_paths 'cd backend && backend/.venv/bin/python3 -m pytest tests/test_x.py -v')"
  echo "$out" > "$tmp/out9.txt" )
ok "the resolved venv path is absolute (starts with /), immune to any 'cd X &&' prefix" \
   "grep -oE '[^ ]*\.venv/bin/python3?' '$tmp/out9.txt' | head -1 | grep -q '^/'"
ok "running the resolved command for real actually finds the interpreter (not a phantom double-prefixed path)" \
   "cmd=\$(cat '$tmp/out9.txt'); bash -c \"\$cmd\" >/dev/null 2>&1; [ \$? -ne 127 ]"

# ---- 10 (round 3): a ./gradlew VERIFY clause resolves to the real gradlew AND runs from
# gradlew's own directory (a bare absolute-path substitution isn't enough - gradle looks
# for settings.gradle relative to $PWD, not relative to the script's own location) ----
mkdir -p "$tmp/repo/android_app"
cat > "$tmp/repo/android_app/gradlew" <<'EOF'
#!/usr/bin/env bash
if [ -f settings.gradle ]; then echo GRADLE_RAN_IN_RIGHT_DIR; else echo GRADLE_WRONG_DIR; fi
EOF
chmod +x "$tmp/repo/android_app/gradlew"
touch "$tmp/repo/android_app/settings.gradle"
( cd "$tmp/repo" && out="$(_resolve_tool_paths './gradlew :app:testDebugUnitTest')"
  echo "$out" > "$tmp/out10.txt" )
ok "gradlew resolves to an absolute path prefixed with a cd into its own directory" \
   "grep -qE '^cd .*android_app && \./gradlew' '$tmp/out10.txt'"
ok "running the resolved gradlew command actually finds settings.gradle (runs from the right cwd)" \
   "cmd=\$(cat '$tmp/out10.txt'); [ \"\$(bash -c \"\$cmd\" 2>/dev/null)\" = 'GRADLE_RAN_IN_RIGHT_DIR' ]"

echo "credit-verify tool-path resolution: $P passed, $F failed"
[ "$F" -eq 0 ]
