#!/usr/bin/env bash
# q-weekend-fixes item 3 (2026-11-15): TAA auto-credit `VERIFY not runnable: rc=127` x8. `cd sdk/python && python3 -m pytest ../../backend/tests/test_x.py` : the cd target has no .venv (TAA's venv is
# backend/.venv), the bare python3 stayed bare and resolved to the runner's aider-venv python (no pytest) -> "No module named pytest" -> UNRUNNABLE rc=127 -> finished items stayed open and were re-picked.
# _resolve_tool_paths now falls back to a venv elsewhere in the repo (or $OVN_VERIFY_VENV_FALLBACK). Mutants: fallback removed / off-switch ignored / wrong venv preference.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
_HERE="$(cd "$(dirname "$0")" && pwd)"; SCRIPT="$_HERE/../lib_verify_clause.sh"
[ -f "$SCRIPT" ] || { echo "  SKIP: $SCRIPT not found"; exit 77; }
P=0; F=0
ok(){ if [ "$2" = 1 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
tmp="$(safe_mktemp_dir)" || exit 1; trap 'rm -rf "$tmp"' EXIT
extract(){ sed -n '/^_resolve_tool_paths(){/,/^}/p' "$1" > "$2"; }
# a repo shaped like test-automation-agent: backend/.venv (python3 + pytest), sdk/python without a venv
R="$tmp/repo"; mkdir -p "$R/backend/.venv/bin" "$R/backend/tests" "$R/sdk/python" "$R/other/.venv/bin"
mkpy(){ cat > "$1" <<'PY'
#!/usr/bin/env bash
echo "venv-python:$0 $*"; exit 0
PY
chmod +x "$1"; }
mkpy "$R/backend/.venv/bin/python3"; mkpy "$R/other/.venv/bin/python3"; printf '#!/usr/bin/env bash\nexit 0\n' > "$R/backend/.venv/bin/pytest"; chmod +x "$R/backend/.venv/bin/pytest"
# the "aider-venv" python3 first on PATH: no pytest
mkdir -p "$tmp/aiderbin"; cat > "$tmp/aiderbin/python3" <<'PY'
#!/usr/bin/env bash
echo "$0: No module named pytest"; exit 1
PY
chmod +x "$tmp/aiderbin/python3"
CMD='cd sdk/python && python3 -m pytest ../../backend/tests/test_client_cancel_run.py -q'
resolve(){ ( . "$1"; cd "$R" && OVN_VERIFY_VENV_ANCESTOR="${2:-on}" _resolve_tool_paths "$CMD" ); }
extract "$SCRIPT" "$tmp/fn.sh"; [ -s "$tmp/fn.sh" ] || { echo "  FAIL: cannot extract _resolve_tool_paths"; exit 1; }

out="$(resolve "$tmp/fn.sh")"
ok "cd target without a venv: bare python3 is replaced by the repo's backend/.venv python (the one WITH pytest)" "$(printf '%s' "$out" | grep -q "^cd sdk/python && $R/backend/.venv/bin/python3 -m pytest " && echo 1 || echo 0)"
ok "the rest of the clause (path, -q) survives" "$(printf '%s' "$out" | grep -q -- '../../backend/tests/test_client_cancel_run.py -q$' && echo 1 || echo 0)"
res="$(cd "$R" && PATH="$tmp/aiderbin:$PATH" bash -c "$out" 2>&1)"; rc=$?
ok "EXECUTED: the resolved clause runs the venv python (rc 0, no 'No module named pytest')" "$([ $rc = 0 ] && echo "$res" | grep -q 'venv-python:' && ! echo "$res" | grep -q 'No module named' && echo 1 || echo 0)"
res="$(cd "$R" && PATH="$tmp/aiderbin:$PATH" bash -c "$CMD" 2>&1)"; rc=$?
ok "CONTROL: the unresolved clause hits the aider-venv python and fails (the incident)" "$([ $rc != 0 ] && echo "$res" | grep -q 'No module named pytest' && echo 1 || echo 0)"
out="$(resolve "$tmp/fn.sh" off)"
ok "OVN_VERIFY_VENV_ANCESTOR=off keeps the bare python3 (old behaviour)" "$(printf '%s' "$out" | grep -q '^cd sdk/python && python3 -m pytest ' && echo 1 || echo 0)"
# without pytest in the clause: first .venv python in sorted order (backend before other)
out="$( ( . "$tmp/fn.sh"; cd "$R" && _resolve_tool_paths 'cd sdk/python && python3 -c "print(1)"' ) )"
ok "non-pytest clause: falls back to the first venv python found (sorted)" "$(printf '%s' "$out" | grep -q "$R/backend/.venv/bin/python3 -c" && echo 1 || echo 0)"
# repo with no venv at all: untouched
mkdir -p "$tmp/bare/sdk/python"; out="$( ( . "$tmp/fn.sh"; cd "$tmp/bare" && _resolve_tool_paths "$CMD" ) )"
ok "no venv anywhere: the clause is left as authored" "$([ "$out" = "$CMD" ] && echo 1 || echo 0)"
# stage worktree: no venv in the worktree, the live clone ($OVN_VERIFY_VENV_FALLBACK) has one
mkdir -p "$tmp/wt/sdk/python"; out="$( ( . "$tmp/fn.sh"; cd "$tmp/wt" && OVN_VERIFY_VENV_FALLBACK="$R" _resolve_tool_paths "$CMD" ) )"
ok "stage worktree: falls back to the live clone's venv via OVN_VERIFY_VENV_FALLBACK" "$(printf '%s' "$out" | grep -q "$R/backend/.venv/bin/python3 -m pytest" && echo 1 || echo 0)"
# an own venv under the cd target still wins (unchanged behaviour)
mkdir -p "$R/sdk/python/.venv/bin"; mkpy "$R/sdk/python/.venv/bin/python3"
out="$(resolve "$tmp/fn.sh")"
ok "a venv under the cd target still takes precedence" "$(printf '%s' "$out" | grep -q "$R/sdk/python/.venv/bin/python3 -m pytest" && echo 1 || echo 0)"
rm -rf "$R/sdk/python/.venv"
# a clause with no python token is untouched
out="$( ( . "$tmp/fn.sh"; cd "$R" && _resolve_tool_paths 'cd sdk/python && ls -la' ) )"
ok "a clause without a python token is untouched" "$([ "$out" = 'cd sdk/python && ls -la' ] && echo 1 || echo 0)"
# mutants
sed 's/\[ -z "\$vpy" \] && \[ "\${OVN_VERIFY_VENV_ANCESTOR:-on}" != off \] &&/false \&\&/' "$SCRIPT" > "$tmp/m1.src"; extract "$tmp/m1.src" "$tmp/m1.sh"
out="$(resolve "$tmp/m1.sh")"; ok "MUTANT (fallback disabled) is caught" "$(printf '%s' "$out" | grep -q "backend/.venv/bin/python3" && echo 0 || echo 1)"
sed 's/"\${OVN_VERIFY_VENV_ANCESTOR:-on}" != off/"on" != off/' "$SCRIPT" > "$tmp/m2.src"; extract "$tmp/m2.src" "$tmp/m2.sh"
out="$(resolve "$tmp/m2.sh" off)"; ok "MUTANT (off-switch ignored) is caught" "$(printf '%s' "$out" | grep -q "backend/.venv/bin/python3" && echo 1 || echo 0)"
python3 -c 'import sys;s=open(sys.argv[1]).read();o="[ -x \"$bin/pytest\" ] || continue";assert o in s;open(sys.argv[2],"w").write(s.replace(o,":",1))' "$SCRIPT" "$tmp/m3.src"; extract "$tmp/m3.src" "$tmp/m3.sh"
mkdir -p "$R/aaa/.venv/bin"; mkpy "$R/aaa/.venv/bin/python3"
out="$(resolve "$tmp/m3.sh")"; ok "MUTANT (pytest-bearing venv no longer preferred) is caught" "$(printf '%s' "$out" | grep -q "$R/backend/.venv/bin/python3 -m pytest" && echo 0 || echo 1)"
out="$(resolve "$tmp/fn.sh")"; ok "with a lexically-earlier pytest-less venv present, the pytest-bearing venv is still preferred" "$(printf '%s' "$out" | grep -q "$R/backend/.venv/bin/python3 -m pytest" && echo 1 || echo 0)"
# ---- review advisory (b): .venv directly under the root wins; find does not follow committed symlinks; -x required ----
# mut <src> <dst> <old> <new>: literal (non-regex) mutation of the lib; fails the test loudly when <old> is not present (a stale mutant would prove nothing)
mut(){ python3 -c 'import sys;s=open(sys.argv[1]).read();o=sys.argv[3];assert o in s,"mutant anchor missing";open(sys.argv[2],"w").write(s.replace(o,sys.argv[4],1))' "$@" || { echo "  FAIL mutant anchor missing: $3"; F=$((F+1)); }; }
mkdir -p "$tmp/rr/sdk/python" "$tmp/rr/-aa/.venv/bin" "$tmp/rr/.venv/bin" "$tmp/rr/zzz/.venv/bin"
mkpy "$tmp/rr/-aa/.venv/bin/python3"; mkpy "$tmp/rr/.venv/bin/python3"; mkpy "$tmp/rr/zzz/.venv/bin/python3"
NP='cd sdk/python && python3 -c "print(1)"'
rnp(){ ( . "$1"; cd "$2" && _resolve_tool_paths "$NP" ); }
out="$(rnp "$tmp/fn.sh" "$tmp/rr")"
ok "non-pytest clause: the .venv directly under the repo root beats an alphabetically earlier -aa/.venv" "$(printf '%s' "$out" | grep -q "$tmp/rr/.venv/bin/python3 -c" && echo 1 || echo 0)"
mut "$SCRIPT" "$tmp/m4.src" '{ [ -e "$base/.venv" ] && printf '"'"'%s\n'"'"' "$base/.venv"; find' '{ find'; extract "$tmp/m4.src" "$tmp/m4.sh"
out="$(rnp "$tmp/m4.sh" "$tmp/rr")"
ok "MUTANT (root .venv preference removed) is caught" "$(printf '%s' "$out" | grep -q "$tmp/rr/.venv/bin/python3 -c" && echo 0 || echo 1)"
# a committed symlink out of the repo is never followed
mkdir -p "$tmp/evil/bin" "$tmp/lk/sdk/python" "$tmp/lk/pkg"; mkpy "$tmp/evil/bin/python3"; ln -s "$tmp/evil" "$tmp/lk/pkg/.venv"
out="$(rnp "$tmp/fn.sh" "$tmp/lk")"
ok "a committed pkg/.venv symlink pointing OUTSIDE the repo is not used (clause left bare)" "$(printf '%s' "$out" | grep -q "pkg/.venv/bin/python3" && echo 0 || echo 1)"
out="$( ( . "$tmp/fn.sh"; cd "$tmp/lk" && _resolve_tool_paths 'cd sdk/python && python3 -m pytest x -q' ) )"
ok "same for a pytest clause" "$(printf '%s' "$out" | grep -q "pkg/.venv/bin/python3" && echo 0 || echo 1)"
mut "$SCRIPT" "$tmp/m5.src" '[ -L "$d" ] || return 0' 'return 0'; extract "$tmp/m5.src" "$tmp/m5.sh"
out="$(rnp "$tmp/m5.sh" "$tmp/lk")"
ok "MUTANT (symlink realpath check removed) is caught" "$(printf '%s' "$out" | grep -q "pkg/.venv/bin/python3" && echo 1 || echo 0)"
# a symlinked .venv whose target stays INSIDE the repo is still accepted
mkdir -p "$tmp/in/real/bin" "$tmp/in/sdk/python"; mkpy "$tmp/in/real/bin/python3"; ln -s "$tmp/in/real" "$tmp/in/.venv"
out="$(rnp "$tmp/fn.sh" "$tmp/in")"
ok "a .venv symlink resolving inside the repo is accepted" "$(printf '%s' "$out" | grep -qE "in/(real|\.venv)/bin/python3 -c" && echo 1 || echo 0)"
# a non-executable interpreter is skipped
mkdir -p "$tmp/nx/sdk/python" "$tmp/nx/.venv/bin" "$tmp/nx/zz/.venv/bin"; : > "$tmp/nx/.venv/bin/python3"; chmod -x "$tmp/nx/.venv/bin/python3"; mkpy "$tmp/nx/zz/.venv/bin/python3"
out="$(rnp "$tmp/fn.sh" "$tmp/nx")"
ok "a non-executable .venv/bin/python3 is skipped (next executable venv used)" "$(printf '%s' "$out" | grep -q "$tmp/nx/zz/.venv/bin/python3 -c" && echo 1 || echo 0)"
mut "$SCRIPT" "$tmp/m6.src" '      if [ -x "$bin/python3" ]; then printf '"'"'%s'"'"' "$bin/python3"; return 0; fi
      if [ -x "$bin/python" ]; then printf '"'"'%s'"'"' "$bin/python"; return 0; fi
    done' '      if [ -e "$bin/python3" ]; then printf '"'"'%s'"'"' "$bin/python3"; return 0; fi
      if [ -e "$bin/python" ]; then printf '"'"'%s'"'"' "$bin/python"; return 0; fi
    done'; extract "$tmp/m6.src" "$tmp/m6.sh"
out="$(rnp "$tmp/m6.sh" "$tmp/nx")"
ok "MUTANT (-x requirement dropped) is caught" "$(printf '%s' "$out" | grep -q "$tmp/nx/.venv/bin/python3 -c" && echo 1 || echo 0)"
echo "  $P passed, $F failed"; [ "$F" -eq 0 ]
