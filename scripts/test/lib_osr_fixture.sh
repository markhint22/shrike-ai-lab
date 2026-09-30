#!/usr/bin/env bash
# lib_osr_fixture.sh — hermetic fake-tree fixture for running the REAL ovn_stage_runner.sh / ovn_stage_sweep.sh end to end.
# Sourced by test_ovn_stage_runner_*.sh / test_ovn_stage_sweep.sh. Everything lives in a mktemp -d tree:
#   $T/home                 = $HOME of the script under test; the script does `cd $HOME/overnight-queue`
#   $T/home/overnight-queue = fake pipeline tree ($Q): scripts/ libs, state/, logs/, repos/osrrepo (clone of bare $O)
#   $T/home/aider-venv/bin  = stub `aider`, `curl`, `sleep`, `npx`, `docker` (the script PREPENDS this dir to PATH)
#   $T/scn                  = per-call scenario snippets for stub aider / stub ovn_autotest.sh (aider.N, aider.default ...)
#   $T/llm                  = canned LLM replies for stub curl (plan.N, plan.default; `fail`/`hang` flags)
# No network, no GPU, no real tree: origin is a local bare repo, LLM + aider + docker + godot are stubs.
OSR_REPO=osrrepo
HERE_OSR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER="$HERE_OSR/../../ovn_stage_runner.sh"; [ -f "$RUNNER" ] || RUNNER="$HERE_OSR/../ovn_stage_runner.sh"
SWEEP="$HERE_OSR/../../ovn_stage_sweep.sh";  [ -f "$SWEEP" ]  || SWEEP="$HERE_OSR/../ovn_stage_sweep.sh"
REALQ="$(cd "$(dirname "$RUNNER")" && pwd)"
export OSR_REPO

pass=0; fail=0; warn=0
ok(){ if [ "$2" = "1" ]; then pass=$((pass+1)); echo "  ok   $1"; else fail=$((fail+1)); echo "  FAIL $1"; fi; }
t(){ local l="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$l" 1; else ok "$l" 0; fi; }       # t "label" cmd args...
kb(){ local l="$1"; shift; if "$@" >/dev/null 2>&1; then echo "  ok   KNOWN-BUG(fixed?): $l"; pass=$((pass+1)); else warn=$((warn+1)); echo "  WARN KNOWN-BUG: $l"; fi; }
osr_summary(){ echo; echo "$pass passed, $fail failed ($warn known-bug warnings)"; [ "$fail" -eq 0 ]; }

_osr_stub(){ printf '%s\n' "$2" > "$1"; chmod +x "$1"; }

osr_new(){   # build a fresh fake tree. sets T H Q O RD
  T="$(mktemp -d)"; H="$T/home"; Q="$H/overnight-queue"; O="$T/origin.git"; RD="$Q/repos/$OSR_REPO"
  mkdir -p "$Q/scripts" "$Q/state" "$Q/logs" "$Q/assets" "$H/aider-venv/bin" "$H/godot" "$T/scn" "$T/llm" "$Q/repos"
  cp "$REALQ/scripts/lib_lock.sh" "$REALQ/scripts/lib_pytest_parallel.sh" "$Q/scripts/"
  cp "$REALQ/ovn_classify_fail.sh" "$Q/"
  echo '# godot4 rules' > "$Q/assets/GODOT4.md"; echo '{}' > "$Q/model-metadata.json"
  _osr_stub "$Q/scripts/ovn_log_tokens.sh" '#!/usr/bin/env bash
echo "$*" >> "$HOME/overnight-queue/state/tokens.calls"'
  _osr_stub "$Q/queue.sh" '#!/usr/bin/env bash
echo "$*" >> "$HOME/overnight-queue/state/queue.calls"'
  _osr_stub "$Q/scripts/ovn_autotest.sh" '#!/usr/bin/env bash
S="$OSR_SCN"; n=$(( $(cat "$S/autotest.n" 2>/dev/null || echo 0) + 1 )); echo $n > "$S/autotest.n"
f="$S/autotest.$n"; [ -f "$f" ] || f="$S/autotest.default"
echo "autotest call $n in $PWD link=$([ -L web/node_modules ] && echo y || echo n)" >> "$S/autotest.calls"
[ -f "$f" ] && . "$f"
exit 0'
  _osr_stub "$H/aider-venv/bin/aider" '#!/usr/bin/env bash
S="$OSR_SCN"; n=$(( $(cat "$S/aider.n" 2>/dev/null || echo 0) + 1 )); echo $n > "$S/aider.n"
printf "%s\n" "$@" > "$S/aider.args.$n"
echo "Tokens: 2.5k sent, 340 received."
f="$S/aider.$n"; [ -f "$f" ] || f="$S/aider.default"
[ -f "$f" ] && . "$f"
exit 0'
  _osr_stub "$H/aider-venv/bin/curl" '#!/usr/bin/env bash
L="$OSR_LLM"; n=$(( $(cat "$L/n" 2>/dev/null || echo 0) + 1 )); echo $n > "$L/n"
body=""; while [ $# -gt 0 ]; do case "$1" in -d) body="$2"; shift;; esac; shift; done
printf "%s" "$body" > "$L/body.$n"
[ -f "$L/hang" ] && exec /bin/sleep 6
f="$L/plan.$n"; [ -f "$f" ] || f="$L/plan.default"
if [ ! -f "$f" ]; then [ -f "$L/fail" ] && exit 22; echo "{}"; exit 0; fi
python3 -c "import json,sys; print(json.dumps({\"choices\":[{\"message\":{\"content\":open(sys.argv[1]).read()}}],\"usage\":{\"prompt_tokens\":11,\"completion_tokens\":7}}))" "$f"'
  # sleep: backoff / dedicate sleeps return at once; a big sleep is the watchdog: it lives only while its parent subshell does
  # (bounded to 60s so watchdogs orphaned by the script's early exits cannot leak); OSR_WD_ARG fires a watchdog after 1s.
  _osr_stub "$H/aider-venv/bin/sleep" '#!/usr/bin/env bash
a="${1:-0}"
if [ "$a" = "${OSR_WD_ARG:-x}" ]; then /bin/sleep 1; exit 0; fi
case "$a" in ""|*[!0-9]*) exec /bin/sleep "$a";; esac
if [ "$a" -ge 60 ]; then for _i in $(seq 1 120); do kill -0 "$PPID" 2>/dev/null || exit 0; /bin/sleep 0.5; done; exit 0; fi
exit 0'
  _osr_stub "$H/aider-venv/bin/npx" '#!/usr/bin/env bash
echo "npx $* @ $PWD link=$([ -L node_modules ] && echo y || echo n)" >> "$OSR_SCN/npx.calls"; echo "vitest run"; exit "$(cat "$OSR_SCN/npx.rc" 2>/dev/null || echo 0)"'
  _osr_stub "$H/aider-venv/bin/docker" '#!/usr/bin/env bash
echo "docker $* @ $PWD" >> "$OSR_SCN/docker.calls"; case "$1" in build) exit "$(cat "$OSR_SCN/docker.rc" 2>/dev/null || echo 0)";; esac; exit 0'
  # origin + repo (branch overnight/feature, the only branch the runner touches)
  git init -q --bare "$O"; git -C "$O" symbolic-ref HEAD refs/heads/overnight/feature
  cat > "$O/hooks/pre-receive" <<HOOK
#!/bin/sh
if [ -f "$T/reject_always" ]; then echo rejected-always >&2; exit 1; fi
if [ -f "$T/reject_once" ]; then rm -f "$T/reject_once"; echo rejected-once >&2; exit 1; fi
exit 0
HOOK
  chmod +x "$O/hooks/pre-receive"
  git init -q "$RD"; git -C "$RD" checkout -q -b overnight/feature
  git -C "$RD" config user.email t@t; git -C "$RD" config user.name t
  mkdir -p "$RD/backend/app" "$RD/backend/tests" "$RD/backend/scripts"
  echo '# pkg' > "$RD/backend/app/__init__.py"
  printf 'def run_job():\n    return 1\n' > "$RD/backend/app/svc.py"
  printf 'from app.svc import run_job\n\ndef test_run_job():\n    assert run_job() == 1\n' > "$RD/backend/tests/test_svc.py"
  printf "open('generated.txt','w').write('fresh')\n" > "$RD/backend/scripts/gen.py"
  printf '#!/usr/bin/env bash\necho fresh > generated.txt\n' > "$RD/backend/scripts/gen.sh"
  printf '#!/usr/bin/env bash\ntrue\n' > "$RD/backend/scripts/noop.sh"
  echo 'agents' > "$RD/AGENTS.md"
  printf '.venv/\nnode_modules/\nlocal.properties\n__pycache__/\n*.pyc\n' > "$RD/.gitignore"
  echo '# Progress' > "$RD/OVERNIGHT_PROGRESS.md"
  git -C "$RD" add -A; git -C "$RD" commit -q -m seed
  git -C "$RD" remote add origin "$O"; git -C "$RD" push -q origin overnight/feature 2>/dev/null
  git -C "$RD" branch -q --set-upstream-to=origin/overnight/feature 2>/dev/null
  export OSR_SCN="$T/scn" OSR_LLM="$T/llm"
}
osr_cleanup(){ [ -n "${T:-}" ] && rm -rf "$T"; rm -rf /tmp/stage-${OSR_REPO}.* 2>/dev/null; return 0; }

osr_venv(){  # $1 = backend (default) | root | nopython : live-venv pytest (+python) stubs, untracked/ignored like the real thing
  local d="$RD/backend/.venv/bin"; [ "${1:-backend}" = root ] && d="$RD/.venv/bin"
  mkdir -p "$d"
  _osr_stub "$d/pytest" '#!/usr/bin/env bash
echo "$PWD :: $*" >> "$OSR_SCN/pytest.calls"
mode="$(cat "$OSR_SCN/pytest.mode" 2>/dev/null || echo ok)"
case "$mode" in
  ok) echo "5 passed"; exit 0;;
  fail) echo "FAILED tests/test_x.py::t - assert 1 == 2"; exit 1;;
  regen:*) cmd="${mode#regen:}"
     if [ -f generated.txt ] && grep -q fresh generated.txt; then echo "5 passed"; exit 0; fi
     echo "openapi is stale: re-run \`$cmd\` from backend/ and commit"; exit 1;;
esac'
  if [ "${1:-backend}" != nopython ]; then
    _osr_stub "$d/python" '#!/usr/bin/env bash
if [ "$1" = -c ] && [ "$2" = "import xdist" ]; then exit "${OSR_XDIST_RC:-0}"; fi
exec /usr/bin/env python3 "$@"'
  fi
}
osr_progress(){ { echo "# Progress"; echo "## Next Steps"; local l; for l in "$@"; do echo "$l"; done; } > "$RD/OVERNIGHT_PROGRESS.md"
  git -C "$RD" add -A; git -C "$RD" commit -q -m prog; git -C "$RD" push -q origin HEAD:overnight/feature; }
osr_tracked(){  # $1=path (rel to repo) $2=content $3=mode(optional) -> commit+push a tracked file
  mkdir -p "$(dirname "$RD/$1")"; printf '%b' "$2" > "$RD/$1"; [ -n "${3:-}" ] && chmod "$3" "$RD/$1"
  git -C "$RD" add -A; git -C "$RD" commit -q -m "add $1"; git -C "$RD" push -q origin HEAD:overnight/feature; }
osr_godot(){  # $1 = GUT result mode written to $T/scn/gut.mode; installs the godot stub + project.godot
  osr_tracked project.godot 'config_version=5\n'
  _osr_stub "$H/godot/godot4" '#!/usr/bin/env bash
echo "godot4 $* @ $PWD" >> "$OSR_SCN/godot.calls"
x=""; for a in "$@"; do case "$a" in -gjunit_xml_file=*) x="${a#-gjunit_xml_file=}";; esac; done
[ -n "$x" ] || exit "$(cat "$OSR_SCN/godot.rc" 2>/dev/null || echo 0)"
case "$(cat "$OSR_SCN/gut.mode" 2>/dev/null || echo ok)" in
  ok) echo "<testsuites><testsuite failures=\"0\"><testcase status=\"pass\"/></testsuite></testsuites>" > "$x";;
  fail) echo "<testsuites><testsuite failures=\"2\"/></testsuites>" > "$x";;
  noasserts) echo "<testsuites><testsuite failures=\"0\"><testcase status=\"no asserts\"/></testsuite></testsuites>" > "$x";;
  parse) echo "<testsuites><testsuite failures=\"0\"/></testsuites>" > "$x"; echo "Parse Error: bad thing";;
  empty) : > "$x";;
esac
exit 0'
  echo "${1:-ok}" > "$T/scn/gut.mode"
}

# ---- canned content ----
ITEM_PY='[T3] backend/app/foo.py — Add foo helper with its test. VERIFY: `pytest backend/tests/test_foo.py` (cat:python)'
PLAN_FOO='[{"desc":"add foo helper","files":["backend/app/foo.py","backend/tests/test_foo.py"],"verify":"pytest backend/tests/test_foo.py"}]'
SNIP_FOO='mkdir -p backend/app backend/tests
printf "def foo():\n    return 1\n" > backend/app/foo.py
printf "from app.foo import foo\n\ndef test_foo():\n    assert foo() == 1\n" > backend/tests/test_foo.py
echo "Applied edit to backend/app/foo.py"'
osr_plan(){ printf '%s' "$2" > "$T/llm/plan.$1"; }          # osr_plan N|default '<content>'
osr_aider(){ printf '%s\n' "$2" > "$T/scn/aider.$1"; }      # osr_aider N|default '<snippet>'
osr_autotest(){ printf '%s\n' "$2" > "$T/scn/autotest.$1"; }

osr_run(){   # osr_run <runner args...>  -> rc in $RC, combined output in $T/out.txt ; callers set OVN_* via `VAR=x osr_run ...`
  ( cd "$T" && HOME="$H" OSR_SCN="$T/scn" OSR_LLM="$T/llm" OVN_STAGE_STARTUP_TIMEOUT="${OVN_STAGE_STARTUP_TIMEOUT:-1500}" \
      bash "$RUNNER" "$@" ) > "$T/out.txt" 2>&1 < /dev/null
  RC=$?
}
osr_out(){ cat "$T/out.txt"; }
osr_jsonl(){ cat "$Q"/state/stage_runs/"$OSR_REPO"-*[0-9].jsonl 2>/dev/null; }
osr_vlog(){ cat "$Q"/state/stage_runs/"$OSR_REPO"-*.verify.log 2>/dev/null; }
osr_origin_log(){ git -C "$O" log --format=%s overnight/feature; }
osr_origin_file(){ git -C "$O" show "overnight/feature:$1" 2>/dev/null; }
