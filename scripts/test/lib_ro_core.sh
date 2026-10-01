#!/usr/bin/env bash
# Shared fixtures for scripts/test/test_run_overnight_core_*.sh (2026-09-30, wave 2 coverage work).
# NOT a test itself (no test_ prefix). Source it, then call ro_init.
#
# Everything lives under one mktemp dir $T:
#   $T/home                  fake $HOME (run_overnight.sh prepends $HOME/aider-venv/bin to PATH, so every stub lives there)
#   $T/stub                  stub state dir ($RO_STUB): call logs + scenario files the stubs read
#   $T/tree                  fake "overnight-queue" tree handed to the real script via OVN_SCRIPT_DIR
#   $T/repos/<name>          fake work repos (clone of $T/origin/<name>.git)
# The REAL run_overnight.sh is always the code under test (never copied) so coverage is attributed to it.

RO_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RO_SCRIPT="$RO_HERE/../../run_overnight.sh"; [ -f "$RO_SCRIPT" ] || RO_SCRIPT="$RO_HERE/../run_overnight.sh"
RO_SCRIPT="$(cd "$(dirname "$RO_SCRIPT")" && pwd)/run_overnight.sh"
RO_Q="$(dirname "$RO_SCRIPT")"

pass=0; fail=0; warn=0
ok(){ if [ "$2" = "1" ]; then pass=$((pass+1)); echo "  ok   $1"; else fail=$((fail+1)); echo "  FAIL $1"; fi; }
# eq LABEL EXPECTED ACTUAL
eq(){ if [ "$2" = "$3" ]; then pass=$((pass+1)); echo "  ok   $1"; else fail=$((fail+1)); echo "  FAIL $1 (expected [$2] got [$3])"; fi; }
# has LABEL HAYSTACK NEEDLE (fixed string)
has(){ if printf '%s' "$2" | grep -qF -- "$3"; then pass=$((pass+1)); echo "  ok   $1"; else fail=$((fail+1)); echo "  FAIL $1 (missing [$3])"; fi; }
hasnt(){ if printf '%s' "$2" | grep -qF -- "$3"; then fail=$((fail+1)); echo "  FAIL $1 (unexpected [$3])"; else pass=$((pass+1)); echo "  ok   $1"; fi; }
# known_bug LABEL 1|0  - asserts CORRECT behaviour but only warns when the production script is wrong
known_bug(){ if [ "$2" = "1" ]; then pass=$((pass+1)); echo "  ok   KNOWN-BUG (now fixed): $1"; else warn=$((warn+1)); echo "  WARN KNOWN-BUG: $1"; fi; }
ro_summary(){ echo; echo "$pass passed, $fail failed ($warn known-bug warnings)"; [ "$fail" -eq 0 ]; }

ro_git_env(){
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0
}

ro_link(){ # link real helper(s) from the real tree into the fake tree
  local f
  for f in "$@"; do mkdir -p "$T/tree/$(dirname "$f")"; ln -sf "$RO_Q/$f" "$T/tree/$f"; done
}

ro_stub(){ # ro_stub NAME <<'EOF' ... EOF   (body from stdin) -> $HOME/aider-venv/bin/NAME
  { echo '#!/bin/bash'; cat; } > "$T/home/aider-venv/bin/$1"; chmod +x "$T/home/aider-venv/bin/$1"
}

ro_init(){
  T="$(mktemp -d)"; export T
  trap 'rm -rf "$T"' EXIT
  ro_git_env
  export HOME="$T/home" RO_STUB="$T/stub"
  mkdir -p "$T/home/aider-venv/bin" "$T/stub" "$T/tree/scripts" "$T/repos" "$T/origin"
  # libs the real script sources unconditionally / uses in the record_outcome + verification paths
  ro_link scripts/lib_lock.sh scripts/lib_item_select.sh scripts/lib_gut_xml.sh scripts/lib_autotest_base.sh scripts/lib_fixup.sh
  echo '[]' > "$T/tree/tasks.json"
  # ---- curl: health/models/coder-routing all controlled by marker files in $RO_STUB -------------------------------
  ro_stub curl <<'EOF'
S="${RO_STUB:-/nonexistent}"
echo "curl $*" >> "$S/curl.log" 2>/dev/null
args="$*"
case "$args" in
  *health/liveliness*) [ -f "$S/litellm_down" ] && exit 22; exit 0;;
  *localhost:4000/health*) [ -f "$S/litellm_down" ] && exit 22; exit 0;;
  *localhost:4000/v1/models*) [ -f "$S/models_missing" ] || echo '{"data":[{"id":"qwen-dflash-27B"}]}'; exit 0;;
  *chat/completions*) [ -f "$S/no_route" ] || echo '{"choices":[{"message":{"content":"ok"}}]}'; exit 0;;
  *localhost:8083/health*) if [ -f "$S/coder_unhealthy" ]; then printf 503; else printf 200; fi; exit 0;;
  *localhost:8081/health*) if [ -f "$S/restore_unhealthy" ]; then printf 503; else printf 200; fi; exit 0;;
esac
exit 0
EOF
  ro_stub sleep <<'EOF'
echo "sleep $*" >> "${RO_STUB:-/nonexistent}/sleep.log" 2>/dev/null
[ -f "${RO_STUB:-/nonexistent}/sleep_fails" ] && exit 1
exit 0
EOF
  ro_stub nvidia-smi <<'EOF'
echo 100
EOF
  ro_stub docker <<'EOF'
S="${RO_STUB:-/nonexistent}"
echo "docker $*" >> "$S/docker.log" 2>/dev/null
case "$1" in
  stop) [ -f "$S/docker_stop_fails" ] && { echo "Error: no such container"; exit 1; }; echo "stopped"; exit 0;;
  inspect) if [ -f "$S/docker_unhealthy" ]; then echo starting; else echo healthy; fi; exit 0;;
  *) exit 0;;
esac
EOF
  ro_stub python <<'EOF'
echo "python $*" >> "${RO_STUB:-/nonexistent}/python.log" 2>/dev/null
[ -f "${RO_STUB:-/nonexistent}/train_fails" ] && { echo "training blew up"; exit 3; }
echo "training ok"; exit 0
EOF
  ro_stub npm <<'EOF'
echo "npm $* CI=${CI:-}" >> "${RO_STUB:-/nonexistent}/npm.log" 2>/dev/null
[ -f "${RO_STUB:-/nonexistent}/npm_fails" ] && { echo "npm test failed"; exit 1; }
echo "npm tests ok"; exit 0
EOF
  # ---- aider: scenario-driven (see $RO_STUB/scn, sourced on every call) ------------------------------------------
  ro_stub aider <<'EOF'
S="${RO_STUB:?}"
echo "$*" > "$S/aider.last_args"
n=$(( $(cat "$S/aider_n" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$S/aider_n"
[ -f "$S/scn" ] && . "$S/scn"
msg=""; prev=""; for a in "$@"; do [ "$prev" = "--message" ] && msg="$a"; prev="$a"; done
case " $* " in
  *" --no-auto-commits "*) kind=scout;;
  *) case "$msg" in
       "Your last change broke the build"*) kind=buildfix;;
       "The test suite is failing"*) kind=fixup;;
       "Your last change broke the Alembic"*) kind=migfix;;
       *) kind=impl;;
     esac;;
esac
echo "$kind" >> "$S/aider_kinds"
echo "$(basename "$(pwd)")" >> "$S/aider_cwds"
[ -n "${SCN_TOUCH:-}" ] && touch "$SCN_TOUCH"
case "$kind" in
  scout)
    printf 'VERDICT: %s\nPLAN: %s\nFILES: %s\nTokens: 1.2k sent, 300 received.\n' "${SCOUT_VERDICT:-PROCEED}" "${SCOUT_PLAN:-edit app/foo.py to add a bar function}" "${SCOUT_FILES:-app/foo.py}"
    [ -n "${SCOUT_EXTRA:-}" ] && echo "$SCOUT_EXTRA"
    exit "${SCOUT_RC:-0}";;
  impl)
    k=$(( $(cat "$S/impl_n" 2>/dev/null || echo 0) + 1 )); echo "$k" > "$S/impl_n"
    act="none"; i=0; for w in ${IMPL_SEQ:-ok}; do i=$((i+1)); act="$w"; [ "$i" -ge "$k" ] && break; done
    case "$act" in
      ok) echo "def bar_$k(): return $k" >> app/foo.py; git add -A; git commit -q -m "feat: add bar $k" -m "DONE: add bar"; echo "Tokens: 2k sent, 500 received. Applied edit to app/foo.py";;
      okdel) git rm -q -f app/old.py 2>/dev/null; echo "DELETE: app/old.py"; echo "Tokens: 2k sent, 500 received.";;
      bad) echo 'def broken(:' > app/broken.py; git add -A; git commit -q -m "feat: broken"; echo "Tokens: 2k sent, 500 received.";;
      assertfail) echo "def test_x(): pass" > app/test_x.py; git add -A; git commit -q -m "test: x";;
      dirty) echo "# scribble" >> app/foo.py; echo "3 passed in 0.1s";;
      dirtyfail) echo "# scribble" >> app/foo.py; echo "nothing ran";;
      none) echo "I considered the request but produced no edits.";;
      ratelimit) echo "litellm.RateLimitError: slow down";;
      ctx) echo "litellm.ContextWindowExceededError: too big";;
      oversized) echo "exceed_context_size 99999";;
      alreadydone) echo "The function is already implemented and correct; no changes are needed.";;
      fail) echo "boom"; exit 1;;
      junk) echo x > ask_for_files; git add -A; git commit -q -m "junk";;
      *) echo "unknown act $act";;
    esac
    exit "${IMPL_RC:-0}";;
  buildfix|fixup|migfix)
    case "${FIXUP_ACT:-none}" in
      fix) echo 'def fixed(): return 1' > app/broken.py; git add -A; git commit -q -m "fix: repair";;
      *) echo "I do not see the problem.";;
    esac
    exit 0;;
esac
EOF
}

# Write a tasks.json from a jq-friendly JSON array string
ro_tasks(){ printf '%s\n' "$1" > "$T/tree/tasks.json"; }

# ro_mkrepo NAME [PROGRESS_TEXT] -> creates $T/repos/NAME w/ bare origin, app/foo.py, .ovn-verify.sh, OVERNIGHT_PROGRESS.md
ro_mkrepo(){
  local name="$1" prog="${2-__default__}" r="$T/repos/$1"
  rm -rf "$r" "$T/origin/$name.git"
  git init -q --bare "$T/origin/$name.git"
  git clone -q "$T/origin/$name.git" "$r" 2>/dev/null
  ( cd "$r" && git checkout -q -b main 2>/dev/null
    mkdir -p app
    printf 'def foo():\n    return 1\n' > app/foo.py
    printf 'def old():\n    return 0\n' > app/old.py
    cat > .ovn-verify.sh <<'V'
#!/bin/bash
# fake repo-owned verification: mode from $RO_STUB/verify.<repo-dir-name> or RO_VERIFY = skip|assertfail|ok(default)
m="$(cat "${RO_STUB:-/nonexistent}/verify.$(basename "$PWD")" 2>/dev/null || echo "${RO_VERIFY:-ok}")"
case "$m" in
  skip) echo "SKIPPED — venv lock contended, not treating as a failure"; exit 0;;
  assertfail) echo "FAILED tests/test_x.py::test_x - AssertionError: assert 1 == 2"; echo "1 failed, 4 passed"; exit 1;;
esac
rc=0
for f in $(git ls-files '*.py'); do
  python3 -c 'import ast,sys; ast.parse(open(sys.argv[1]).read())' "$f" 2>/dev/null || { echo "SyntaxError: invalid syntax in $f"; rc=1; }
done
[ "$rc" = 0 ] && echo "verify ok"
exit $rc
V
    chmod +x .ovn-verify.sh
    if [ "$prog" = "__default__" ]; then
      printf '# Overnight Progress\n\n## Current Status\nok\n\n## Next Steps\n- [ ] [T1] `app/foo.py` — add a bar function (cat:python)\n' > OVERNIGHT_PROGRESS.md
    elif [ "$prog" != "__none__" ]; then
      printf '%s\n' "$prog" > OVERNIGHT_PROGRESS.md
    fi
    git add -A; git commit -q -m base; git push -q origin main 2>/dev/null
    git remote set-head origin main >/dev/null 2>&1 || true )
  echo "$r"
}

# ro_source: load every function of the real script into the current shell (OVN_SOURCE_ONLY seam). Needs a valid tasks.json.
ro_source(){
  export OVN_SCRIPT_DIR="$T/tree" OVN_SOURCE_ONLY=1
  # shellcheck disable=SC1090
  . "$RO_SCRIPT"
  set +u
  unset OVN_SOURCE_ONLY
}

# ro_run_main [ENV=VAL ...]: run the WHOLE real script in the fake tree; stdout+stderr -> $T/run.out, rc -> $RO_RC
ro_run_main(){
  ( cd "$T" && env HOME="$T/home" OVN_SCRIPT_DIR="$T/tree" RO_STUB="$T/stub" "$@" bash "$RO_SCRIPT" ) > "$T/run.out" 2>&1
  RO_RC=$?
  RO_OUT="$(cat "$T/run.out")"
}
ro_report(){ cat "$(ls -t "$T"/tree/reports/*.md 2>/dev/null | head -1)" 2>/dev/null; }

# stubs for the per-task hooks run_overnight.sh invokes after each task (record calls instead of acting)
ro_hook_stubs(){
  local h
  for h in scripts/ovn_item_guard.sh scripts/ovn_cycle_triage.sh; do
    mkdir -p "$T/tree/scripts"; rm -f "$T/tree/$h"
    printf '#!/bin/bash\necho "$(basename "$0") $*" >> "%s/hooks.log"\nexit 0\n' "$T/stub" > "$T/tree/$h"; chmod +x "$T/tree/$h"
  done
  for h in ovn_planner.sh queue_refill.sh cycle_notify.sh; do
    rm -f "$T/tree/$h"
    printf '#!/bin/bash\necho "%s $*" >> "%s/hooks.log"\nexit 0\n' "$h" "$T/stub" > "$T/tree/$h"; chmod +x "$T/tree/$h"
  done
}
