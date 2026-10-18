#!/usr/bin/env bash
# 2026-10-10 (qacov F7): branch_hygiene.sh no longer streams the FULL pytest/gradle output into the cron log (logs/branch_hygiene.log reached 136 MB).
# hyg_gate_cap keeps head+tail in the main log, the full output in ONE per-run file, and never changes the gate's exit code.
#   part 1 (runs anywhere, bash 3.2 ok): the function extracted from the REAL script and driven directly (pass-through of small output, cap of big output,
#          pointer line, per-run file content, pruning, kill switch, unwritable dir, exit status through PIPESTATUS).
#   part 2 (needs flock -w 0 + timeout + jq, i.e. the box; SKIPs on a Mac like test_branch_hygiene_run.sh cannot run there): the REAL script gating a repo whose
#          stub pytest prints 5000 lines: the cron log stays small, the per-run file has all 5000, a red gate is still flagged, a green one still merges.
# Every check also runs against a MUTANT (cap removed / exit code lost) and must FAIL there.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }   # 2026-10-16: fail-closed sandbox helpers (see lint_unsafe_rm.py)
HERE="$(cd "$(dirname "$0")" && pwd)"
BH="$HERE/../../branch_hygiene.sh"; [ -f "$BH" ] || BH="$HERE/../branch_hygiene.sh"
[ -f "$BH" ] || { echo "  SKIP: branch_hygiene.sh not found"; exit 0; }
grep -q '^hyg_gate_cap()' "$BH" || { echo "  FAIL: hyg_gate_cap() is not defined in $BH"; exit 1; }
grep -q '^hyg_gate_run()' "$BH" || { echo "  FAIL: hyg_gate_run() is not defined in $BH"; exit 1; }
P=0; F=0
ok(){ if [ "$2" = "1" ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
T="$(safe_mktemp_dir)" || exit 1; trap 'rm -rf "$T"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

# ---- the function, extracted from the real script (from its header line to the closing brace at column 0)
extract(){ awk -v n="$2" '$0 ~ "^" n "\\(\\) \\{"{p=1} p{print} p&&/^}/{exit}' "$1"; }
{ extract "$BH" hyg_gate_cap; extract "$BH" hyg_gate_run; } > "$T/fn.sh"
extract "$BH" hyg_gate_run > "$T/fn_run_only.sh"
ok "the functions were extracted (non-empty, ends with a closing brace, both present)" "$([ -s "$T/fn.sh" ] && tail -1 "$T/fn.sh" | grep -q '^}$' && [ "$(grep -c '^hyg_gate_c\?[a-z]*() {' "$T/fn.sh")" = 2 ] && echo 1 || echo 0)"
mutant_nocap="$T/fn_nocap.sh";  sed 's/^  if \[ "\$n" -le \$((hn + tn)) \]; then cat "\$f"; rm -f "\$f"; return 0; fi$/  cat "$f"; rm -f "$f"; return 0/' "$T/fn.sh" > "$mutant_nocap"
ok "mutant 1 (never cap) differs from the real function" "$(cmp -s "$T/fn.sh" "$mutant_nocap" && echo 0 || echo 1)"

# drive <fn file> <lines> [env assignments...] -> runs `seq 1 N | cap` in a clean subshell; prints captured stdout to $T/o, the dir used is $T/gd
drive(){
  local fn="$1" n="$2"; shift 2
  rm -rf "${T:?}/gd"
  ( export SCRIPT_DIR="$T/sd"; export OVN_HYGIENE_GATE_DIR="$T/gd"; export repo="/x/myrepo"; for kv in "$@"; do export "$kv"; done
    log(){ echo "[branch-hygiene TS] $*"; }
    . "$fn"
    seq 1 "$n" | hyg_gate_cap pytest > "$T/o"; echo $? > "$T/cap_rc" )
}
lines(){ wc -l < "$1" | tr -d ' '; }

drive "$T/fn.sh" 100
ok "small output (100 lines) is passed through untouched" "$([ "$(lines $T/o)" = 100 ] && [ "$(head -1 $T/o)" = 1 ] && [ "$(tail -1 $T/o)" = 100 ] && echo 1 || echo 0)"
ok "small output leaves no per-run file behind" "$([ "$(ls "$T/gd" 2>/dev/null | wc -l | tr -d ' ')" = 0 ] && echo 1 || echo 0)"
drive "$T/fn.sh" 5000
ok "big output (5000 lines): main log gets head 30 + pointer + tail 150 = 181 lines" "$([ "$(lines $T/o)" = 181 ] && echo 1 || echo 0)"
ok "the head is the FIRST 30 lines and the tail the LAST 150 lines" "$([ "$(head -1 $T/o)" = 1 ] && [ "$(sed -n 30p $T/o)" = 30 ] && [ "$(tail -1 $T/o)" = 5000 ] && [ "$(tail -150 $T/o | head -1)" = 4851 ] && echo 1 || echo 0)"
ok "the pointer line says how many lines were omitted and names the per-run file" "$(sed -n 31p $T/o | grep -q 'gate pytest: 4820 of 5000 output lines omitted here; full output kept in '"$T"'/gd/' && echo 1 || echo 0)"
pf="$(ls "$T/gd"/* 2>/dev/null | head -1)"
ok "per-run file holds ALL 5000 lines, is named <ts>.<repo>.<kind>.XXXXXX" "$([ "$(lines "$pf")" = 5000 ] && basename "$pf" | grep -qE '^[0-9]{8}-[0-9]{6}\.myrepo\.pytest\.[A-Za-z0-9]{6}$' && echo 1 || echo 0)"
drive "$T/fn_nocap.sh" 5000
ok "MUTANT 1 (never cap): the main log would get all 5000 lines - the 181-line assertion FAILS on it" "$([ "$(lines $T/o)" = 181 ] && echo 0 || echo 1)"
drive "$T/fn.sh" 5000 OVN_HYGIENE_GATE_LOG=full
ok "OVN_HYGIENE_GATE_LOG=full restores the old unbounded stream (5000 lines, no per-run file)" "$([ "$(lines $T/o)" = 5000 ] && [ ! -d "$T/gd" ] && echo 1 || echo 0)"
drive "$T/fn.sh" 400 OVN_HYGIENE_GATE_HEAD=5 OVN_HYGIENE_GATE_TAIL=5
ok "OVN_HYGIENE_GATE_HEAD/TAIL are honoured" "$([ "$(lines $T/o)" = 11 ] && echo 1 || echo 0)"
drive "$T/fn.sh" 400 OVN_HYGIENE_GATE_HEAD=abc OVN_HYGIENE_GATE_TAIL=
ok "non-numeric knobs fall back to the defaults (30/150), not to an error" "$([ "$(lines $T/o)" = 181 ] && echo 1 || echo 0)"
# unwritable dir: the output is streamed as before (never lose diagnostics to save space)
: > "$T/notadir"
drive "$T/fn.sh" 5000 OVN_HYGIENE_GATE_DIR="$T/notadir/sub"
ok "per-run dir cannot be created: everything is streamed (5000 lines), nothing lost" "$([ "$(lines $T/o)" = 5000 ] && echo 1 || echo 0)"
# pruning: files older than KEEP_DAYS are removed, fresh ones stay
rm -rf "${T:?}/gd"; mkdir -p "$T/gd"; : > "$T/gd/old.file"; : > "$T/gd/new.file"; touch -t 202001010000 "$T/gd/old.file"
( export SCRIPT_DIR="$T/sd" OVN_HYGIENE_GATE_DIR="$T/gd" repo=r; log(){ :; }; . "$T/fn.sh"; seq 1 3 | hyg_gate_cap pytest > /dev/null )
ok "prune: a per-run file older than 3 days is removed, a fresh one is kept" "$([ ! -e "$T/gd/old.file" ] && [ -e "$T/gd/new.file" ] && echo 1 || echo 0)"
# exit status through the pipe: the gate's code is ${PIPESTATUS[0]}
( export SCRIPT_DIR="$T/sd" OVN_HYGIENE_GATE_DIR="$T/gd" repo=r; log(){ :; }; . "$T/fn.sh"
  ( seq 1 5000; exit 7 ) | hyg_gate_cap pytest > /dev/null; echo "${PIPESTATUS[0]}" > "$T/gate_rc" )
ok "the gate's exit code (7) survives the cap via PIPESTATUS[0]" "$([ "$(cat "$T/gate_rc")" = 7 ] && echo 1 || echo 0)"
ok "call sites in run_gate: pytest goes through hyg_gate_run (rc=\$? - no pipe), gradle keeps its tee pipeline and reads PIPESTATUS[0]" "$([ "$(grep -cF 'hyg_gate_run pytest "$wt_pkg" timeout "$TEST_TIMEOUT" "$venv_pytest"' "$BH")" = 1 ] && [ "$(grep -cF 'hyg_gate_run pytest' "$BH")" = 1 ] && grep -F 'hyg_gate_run pytest' "$BH" | grep -qF '; rc=$?' && [ "$(grep -cF '| hyg_gate_cap gradle; rc=${PIPESTATUS[0]}' "$BH")" = 1 ] && echo 1 || echo 0)"
ok "no gate site is left that streams pytest output straight to the log, and none pipes pytest into the cap (the detached-grandchild hang)" "$(grep -E 'venv_pytest.*no:cacheprovider' "$BH" | grep -vq 'hyg_gate_run' && echo 0 || echo 1)"
ok "no pipe feeds hyg_gate_cap from the pytest gate (only gradle's tee does)" "$([ "$(grep -E '\| *hyg_gate_cap' "$BH" | grep -vc gradle)" = 0 ] && echo 1 || echo 0)"

# ---- hyg_gate_run: exit status, output, and the DETACHED GRANDCHILD regression (a pipe would block until the leaked daemon exits)
runfn(){ # <fn file> <gate cmd...>: hyg_gate_run pytest $T <cmd...>; stdout -> $T/ro, status -> $T/ro_rc
  local fn="$1"; shift
  ( export SCRIPT_DIR="$T/sd" OVN_HYGIENE_GATE_DIR="$T/gd2" repo=r; log(){ :; }; . "$fn"
    hyg_gate_run pytest "$T" "$@" > "$T/ro" 2>&1; echo $? > "$T/ro_rc" )
}
printf '#!/bin/sh\necho "gate says hi"; echo "gate err" >&2; exit 7\n' > "$T/g_red.sh"
runfn "$T/fn.sh" sh "$T/g_red.sh"
ok "hyg_gate_run: returns the gate's own exit code (7) and passes its stdout+stderr through" "$([ "$(cat "$T/ro_rc")" = 7 ] && grep -q 'gate says hi' "$T/ro" && grep -q 'gate err' "$T/ro" && echo 1 || echo 0)"
printf '#!/bin/sh\ncd "$1" && echo "cwd=$(pwd -P)"\n' > "$T/g_cwd.sh"; mkdir -p "$T/wd"
( export SCRIPT_DIR="$T/sd" OVN_HYGIENE_GATE_DIR="$T/gd2" repo=r; log(){ :; }; . "$T/fn.sh"; hyg_gate_run pytest "$T/wd" sh -c 'echo "cwd=$(pwd -P)"' > "$T/ro" 2>&1 )
ok "hyg_gate_run: the command runs inside <dir>" "$(grep -qx "cwd=$T/wd" "$T/ro" && echo 1 || echo 0)"
( export SCRIPT_DIR="$T/sd" OVN_HYGIENE_GATE_DIR="$T/gd2" repo=r OVN_HYGIENE_GATE_LOG=full; log(){ :; }; . "$T/fn.sh"; hyg_gate_run pytest "$T" sh -c 'seq 1 5000; exit 5' > "$T/ro" 2>&1; echo $? > "$T/ro_rc" )
ok "hyg_gate_run: OVN_HYGIENE_GATE_LOG=full streams all 5000 lines, keeps exit code 5" "$([ "$(lines "$T/ro")" = 5000 ] && [ "$(cat "$T/ro_rc")" = 5 ] && echo 1 || echo 0)"
( export SCRIPT_DIR="$T/sd" OVN_HYGIENE_GATE_DIR="$T/gd2" repo=r; log(){ echo "[bh] $*"; }; . "$T/fn.sh"; hyg_gate_run pytest "$T" sh -c 'seq 1 5000; exit 5' > "$T/ro" 2>&1; echo $? > "$T/ro_rc" )
ok "hyg_gate_run: default mode caps the 5000-line gate (181 lines out) and still returns 5" "$([ "$(lines "$T/ro")" = 181 ] && [ "$(cat "$T/ro_rc")" = 5 ] && echo 1 || echo 0)"
# the regression: the gate leaves a DETACHED daemon (new session, survives timeout's kill) holding the inherited stdout. The call must return while the daemon is still alive.
if command -v python3 >/dev/null 2>&1; then
  LEAKSLEEP=12
  printf '#!/bin/sh\npython3 -c "import subprocess,sys; p=subprocess.Popen([\\"sleep\\",\\"%s\\"],start_new_session=True); open(sys.argv[1],\\"w\\").write(str(p.pid))" "$1"\necho "gate output before exit"\nexit "${2:-3}"\n' "$LEAKSLEEP" > "$T/g_leak.sh"
  printf '#!/bin/sh\npython3 -c "import subprocess,sys; p=subprocess.Popen([\\"sleep\\",\\"%s\\"],start_new_session=True); open(sys.argv[1],\\"w\\").write(str(p.pid))" "$1"\necho "hanging gate"\nsleep 30\n' "$LEAKSLEEP" > "$T/g_leak_hang.sh"
  leakcheck(){ # <label> <fn file> <expected rc> <gate cmd...>: returns 0 when hyg_gate_run came back with the right rc while the daemon was still alive
    local fn="$2" want="$3"; shift 3; rm -f "$T/leak.pid"
    runfn "$fn" "$@"
    local pid; pid="$(cat "$T/leak.pid" 2>/dev/null)"; local alive=0
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && alive=1
    [ -n "$pid" ] && { kill "$pid" 2>/dev/null; sleep 0.1; kill -9 "$pid" 2>/dev/null; } || true
    [ "$alive" = 1 ] && [ "$(cat "$T/ro_rc")" = "$want" ] && grep -q 'output before exit\|hanging gate' "$T/ro"
  }
  ok "DETACHED GRANDCHILD: a red gate that leaked a daemon returns (rc=3) while the daemon is still running - no wait for the pipe to drain" "$(leakcheck a "$T/fn.sh" 3 sh "$T/g_leak.sh" "$T/leak.pid" 3 && echo 1 || echo 0)"
  if command -v timeout >/dev/null 2>&1; then
    ok "DETACHED GRANDCHILD under timeout(1) (the reviewer's repro): rc=124 comes back without waiting for the leaked daemon" "$(leakcheck b "$T/fn.sh" 124 timeout 1 sh "$T/g_leak_hang.sh" "$T/leak.pid" && echo 1 || echo 0)"
  fi
  # MUTANT 3: the old shape - the gate piped straight into the cap. The same assertion must FAIL (the call only returns after the daemon's sleep, which is then gone).
  { extract "$BH" hyg_gate_cap; printf 'hyg_gate_run() {\n  local kind="$1" dir="$2"; shift 2\n  ( cd "$dir" && "$@" 2>&1 ) | hyg_gate_cap "$kind"; return ${PIPESTATUS[0]}\n}\n'; } > "$T/fn_pipe.sh"
  ok "MUTANT 3 (pipe the gate into the cap, the old shape): the detached-grandchild assertion FAILS on it (it blocks until the daemon exits)" "$(leakcheck m "$T/fn_pipe.sh" 3 sh "$T/g_leak.sh" "$T/leak.pid" 3 && echo 0 || echo 1)"
else
  echo "  SKIP: python3 missing - detached-grandchild checks not run"
fi

# ---- part 2: the real script
if ! flock -w 0 "$T/probe.lock" true >/dev/null 2>&1 || ! command -v timeout >/dev/null || ! command -v jq >/dev/null; then
  echo "  SKIP part 2: this host's flock rejects -w 0 (macOS) or timeout/jq is missing - runs on the box"
  echo "  $P passed, $F failed"; [ "$F" = 0 ]; exit $?
fi
REALGIT="$(type -P git)"
safe_set_sandbox_home "$T" || exit 1; export STATE_DIR="$T/state"; export OVN_QA_SHADOW=off OVN_XDIST_REPOS=none
BIN="$T/bin"; mkdir -p "$BIN"
printf '#!/usr/bin/env bash\nexit 0\n' > "$BIN/curl"; chmod +x "$BIN/curl"
mkrepo(){  # <name> <red 0|1>: bare origin + clone with a stub .venv/bin/pytest printing 5000 lines
  local n="$1" red="$2" o="$T/origin/$1.git" s="$T/seed/$1"
  git init -q --bare -b main "$o"; git clone -q "$o" "$s" 2>/dev/null
  ( cd "$s"; mkdir -p pkg; echo "def t(): pass" > pkg/test_x.py; echo base > f.txt; git add -A; git commit -q -m base; git branch -M main; git push -q origin main
    git branch develop; git push -q origin develop; git checkout -q -b overnight/feature; echo f1 > feat1.txt; git add -A; git commit -q -m "feat: 1"; git push -q origin overnight/feature
    git checkout -q develop; git branch claude/feature; git push -q origin claude/feature )
  git clone -q "$o" "$T/repos/$n" 2>/dev/null
  mkdir -p "$T/repos/$n/.venv/bin"
  { echo '#!/usr/bin/env bash'; [ "$red" = leak ] && echo "python3 -c \"import subprocess; p=subprocess.Popen(['sleep','45'],start_new_session=True); open('$T/leak2.pid','w').write(str(p.pid))\""
    echo 'for i in $(seq 1 5000); do echo "gate output line $i"; done'; [ "$red" = 1 ] && echo 'echo "1 failed"; exit 1'; echo 'echo ". passed"; exit 0'; } > "$T/repos/$n/.venv/bin/pytest"
  chmod +x "$T/repos/$n/.venv/bin/pytest"
}
runbh(){ # <bh script> <repo>
  rm -rf "${T:?}/home" "${T:?}/state"; mkdir -p "$HOME/overnight-queue/scripts" "$STATE_DIR"; : > "$HOME/overnight-queue/scripts/check_migrations.py"
  ( cd "$T" && PATH="$BIN:$PATH" bash "$1" "$T/repos/$2" > "$T/out.log" 2>&1 ); echo $? > "$T/rc"
}
mkdir -p "$T/repos"
mkrepo green 0; mkrepo red 1; mkrepo leaky leak
# the script resolves its helper libs next to itself, so run the real file in place; the per-run dir is redirected into the fixture
export OVN_HYGIENE_GATE_DIR="$T/gate_runs"
runbh "$BH" green
ok "REAL script, green gate: the cron log stays small (<= 400 lines, was 5000+)" "$([ "$(lines $T/out.log)" -le 400 ] && echo 1 || echo 0)"
ok "REAL script, green gate: still merged into develop" "$(git -C "$T/origin/green.git" merge-base --is-ancestor overnight/feature develop && echo 1 || echo 0)"
ok "REAL script, green gate: the per-run file has the full 5000 lines" "$([ "$(cat "$T"/gate_runs/*green*pytest* 2>/dev/null | grep -c 'gate output line')" = 5000 ] && echo 1 || echo 0)"
runbh "$BH" red
ok "REAL script, red gate: still flagged for review (exit code not lost)" "$([ -f "$STATE_DIR/branch_hygiene_review_red" ] && echo 1 || echo 0)"
ok "REAL script, red gate: the failure summary line (1 failed) is in the cron log (it is in the tail)" "$(grep -qF '1 failed' "$T/out.log" && echo 1 || echo 0)"
ok "REAL script, red gate: not merged" "$(git -C "$T/origin/red.git" merge-base --is-ancestor overnight/feature develop && echo 0 || echo 1)"
# the real script, a pytest gate that leaks a DETACHED daemon: the hygiene run must finish (and merge) while the daemon is still alive
if command -v python3 >/dev/null 2>&1; then
  rm -f "$T/leak2.pid"; runbh "$BH" leaky; lp="$(cat "$T/leak2.pid" 2>/dev/null)"; la=0; [ -n "$lp" ] && kill -0 "$lp" 2>/dev/null && la=1; [ -n "$lp" ] && kill -9 "$lp" 2>/dev/null
  ok "REAL script, gate that leaks a detached daemon: the run returned while the daemon was still alive (no pipe hang) and the green gate merged" "$([ "$la" = 1 ] && git -C "$T/origin/leaky.git" merge-base --is-ancestor overnight/feature develop && echo 1 || echo 0)"
fi
# mutant of the real script: exit code lost (rc forced to 0 after the pipe) -> the red gate would merge; the assertions above would FAIL
sed 's/^  return \$rc$/  return 0/' "$BH" > "$(dirname "$BH")/.bh_mut_$$.sh"
runbh "$(dirname "$BH")/.bh_mut_$$.sh" red; rm -f "$(dirname "$BH")/.bh_mut_$$.sh"
ok "MUTANT 2 (exit code lost): the red gate is no longer flagged - proves the red-gate assertion bites" "$([ -f "$STATE_DIR/branch_hygiene_review_red" ] && echo 0 || echo 1)"
echo "  $P passed, $F failed"; [ "$F" = 0 ]
