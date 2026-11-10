#!/usr/bin/env bash
# Z7-B (2026-11-09): bounded push/rebase retry + cycle phase timestamps (scripts/lib_push_bound.sh, wired into run_overnight.sh / ovn_stage_runner.sh / ovn_item_guard.sh / lib_landing_gates.sh).
# Incident: xlite cycle 5826 s on 2026-11-08, last log line "Successfully rebased", nothing for 97 min. A STUB git (first on PATH) rejects the push, then hangs; the cycle must proceed inside the cap.
# Mutants of the lib (each removes one bound / one safety property) must be KILLED by this file (see the mutation block at the end).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
. "$HERE/ntfy_guard.sh" 2>/dev/null || true
Q="$HERE/../.."; [ -f "$Q/run_overnight.sh" ] || Q="$HERE/.."
LIBDIR="${Z7_LIB_DIR:-$Q/scripts}"
[ -f "$LIBDIR/lib_push_bound.sh" ] || { echo "  FAIL: lib_push_bound.sh missing"; exit 1; }
type -P timeout >/dev/null 2>&1 || type -P gtimeout >/dev/null 2>&1 || { echo "  SKIP: no timeout binary"; exit 0; }
export NTFY_SERVER=http://127.0.0.1:9 OVN_NOTIFY_DISABLE=1 TZ=UTC
T="$(safe_mktemp_dir z7pb)" || exit 1
trap 'safe_rm_rf "$T"' EXIT
rc=0; ok(){ echo "  ok   $1"; }; bad(){ echo "  FAIL: $1"; rc=1; }
STUB="$T/bin"; mkdir -p "$STUB"
# stub git: behaviour per subcommand from $T/mode_<sub> (files: 'ok' | 'fail' | 'hang' | 'seq:<a,b,c>' consumed one per call); every call is appended to $T/calls with env facts
cat > "$STUB/git" <<'STUBEOF'
#!/usr/bin/env bash
T="${Z7_T:?}"; sub=""; for a in "$@"; do case "$a" in push|pull|fetch|rebase|merge|config|rev-parse) sub="$a"; break;; esac; done
printf '%s prompt=%s askpass=%s stdin=%s args=%s\n' "$sub" "${GIT_TERMINAL_PROMPT:-unset}" "${GIT_ASKPASS:-unset}" "$(cat 2>/dev/null | wc -c | tr -d ' ')" "$*" >> "$T/calls"
[ "$sub" = config ] && exit 1
m="$(cat "$T/mode_$sub" 2>/dev/null || echo ok)"
case "$m" in seq:*) list="${m#seq:}"; first="${list%%,*}"; rest="${list#*,}"; [ "$rest" = "$list" ] && rest="$first"; printf 'seq:%s' "$rest" > "$T/mode_$sub"; m="$first";; esac
case "$m" in
  ok) [ "$sub" = pull ] && echo "Successfully rebased and updated refs/heads/x."; exit 0;;
  fail) echo "! [rejected] (non-fast-forward)" >&2; exit 1;;
  conflict) echo "CONFLICT (content): Merge conflict in f" ; exit 1;;
  hang) sleep 90; exit 0;;
  slowfail) sleep 1; echo "! [rejected]" >&2; exit 1;;
esac
STUBEOF
chmod +x "$STUB/git"
mode(){ printf '%s' "$2" > "$T/mode_$1"; }
calls(){ grep -c "^$1 " "$T/calls" 2>/dev/null || true; }
reset(){ rm -f "$T"/mode_* "$T/calls"; : > "$T/calls"; : > "$T/task.log"; }
run_retry(){  # run ovn_push_rebase_retry in a clean subshell with the stub git first on PATH; prints "rc elapsed"
  ( export PATH="$STUB:$PATH" Z7_T="$T"; export OVN_GIT_NET_TIMEOUT="${OVN_GIT_NET_TIMEOUT:-2}" OVN_PUSH_RETRY_CAP_S="${OVN_PUSH_RETRY_CAP_S:-6}" OVN_PUSH_RETRY_N="${OVN_PUSH_RETRY_N:-3}"
    . "$LIBDIR/lib_push_bound.sh"; s=$SECONDS; ovn_push_rebase_retry feature "$T/task.log" </dev/null; r=$?; echo "$r $((SECONDS - s)) ${OVN_PUSH_REBASED:-0}" )
}

echo "== retry: push rejected, rebase ok, push HANGS (the incident shape)"
reset; mode pull ok; mode push hang
read -r r e rb <<< "$(run_retry)"
{ [ "$r" = 1 ] && [ "$e" -le 14 ]; } && ok "returns 1 within the wall-clock cap (rc=$r after ${e}s; stub push would sleep 90 s)" || bad "hung push not bounded (rc=$r after ${e}s)"
grep -q 'push-retry exhausted' "$T/task.log" && ok "logs 'push-retry exhausted'" || bad "no exhausted line: $(cat "$T/task.log")"
grep -q '^rebase ' "$T/calls" && ok "a half-done rebase is aborted (git rebase --abort called)" || bad "rebase --abort never called"
echo "== retry: pull --rebase HANGS"
reset; mode pull hang
read -r r e rb <<< "$(OVN_PUSH_RETRY_CAP_S=5 run_retry)"
{ [ "$r" = 1 ] && [ "$e" -le 16 ]; } && ok "hung pull --rebase is bounded (rc=$r after ${e}s)" || bad "hung pull not bounded (rc=$r after ${e}s)"
grep -q 'push-retry exhausted' "$T/task.log" && grep -q '^rebase ' "$T/calls" && ok "exhausted + rebase --abort after a killed pull" || bad "no exhausted/abort after killed pull"
echo "== retry: attempts bound"
reset; mode pull ok; mode push fail
read -r r e rb <<< "$(OVN_PUSH_RETRY_N=2 OVN_PUSH_RETRY_CAP_S=60 run_retry)"
{ [ "$r" = 1 ] && [ "$(calls pull)" = 2 ] && [ "$(calls push)" = 2 ]; } && ok "OVN_PUSH_RETRY_N=2: exactly 2 rebase attempts, 2 retry pushes (pull=$(calls pull) push=$(calls push))" || bad "attempt bound wrong (pull=$(calls pull) push=$(calls push) rc=$r)"
grep -q 'push-retry exhausted' "$T/task.log" && ok "exhausted line on the attempts bound" || bad "no exhausted line"
reset; mode pull ok; mode push fail
read -r r e rb <<< "$(run_retry)"
[ "$(calls pull)" = 3 ] && ok "default N is 3" || bad "default N != 3 (pull=$(calls pull))"
echo "== retry: wall-clock cap is independent of the attempt bound"
reset; mode pull ok; mode push slowfail
read -r r e rb <<< "$(OVN_PUSH_RETRY_N=50 OVN_PUSH_RETRY_CAP_S=3 run_retry)"
{ [ "$r" = 1 ] && [ "$e" -le 8 ] && [ "$(calls pull)" -lt 10 ]; } && ok "N=50 but CAP=3s: stops after ${e}s / $(calls pull) attempts (not 50)" || bad "wall-clock cap not enforced (rc=$r ${e}s pulls=$(calls pull))"
grep -q 'wall-clock cap' "$T/task.log" && ok "the exhausted line names the cap" || bad "exhausted line does not name the wall-clock cap: $(cat "$T/task.log")"
echo "== retry: the wall-clock cap is HARD (per-command timeout shrinks to the remaining budget; default 120 s per command must not overrun a short cap)"
reset; mode pull ok; mode push hang
read -r r e rb <<< "$(OVN_GIT_NET_TIMEOUT=120 OVN_PUSH_RETRY_N=3 OVN_PUSH_RETRY_CAP_S=4 run_retry)"
{ [ "$r" = 1 ] && [ "$e" -le 12 ]; } && ok "hung push under a 120 s per-command timeout stops at the 4 s cap (+grace): rc=$r after ${e}s" || bad "cap not hard for push (rc=$r after ${e}s; budget must cap the per-command timeout)"
reset; mode pull hang
read -r r e rb <<< "$(OVN_GIT_NET_TIMEOUT=120 OVN_PUSH_RETRY_N=3 OVN_PUSH_RETRY_CAP_S=4 run_retry)"
{ [ "$r" = 1 ] && [ "$e" -le 12 ] && [ "$(calls push)" = 0 ]; } && ok "hung pull --rebase under a 120 s per-command timeout stops at the 4 s cap: rc=$r after ${e}s" || bad "cap not hard for pull (rc=$r after ${e}s)"
reset; mode pull ok; mode push slowfail
read -r r e rb <<< "$(OVN_GIT_NET_TIMEOUT=120 OVN_PUSH_RETRY_N=9 OVN_PUSH_RETRY_CAP_S=4 run_retry)"
{ [ "$r" = 1 ] && [ "$e" -le 12 ]; } && ok "no command is started once the budget is spent (rc=$r after ${e}s, pulls=$(calls pull))" || bad "work started past the cap (${e}s)"
echo "== retry: a pull --rebase that TIMES OUT once is retried (stalled connection), a conflict is not"
reset; mode pull seq:hang,ok; mode push ok
read -r r e rb <<< "$(OVN_PUSH_RETRY_CAP_S=20 run_retry)"
{ [ "$r" = 0 ] && [ "$(calls pull)" = 2 ] && [ "$rb" = 1 ]; } && ok "hung pull, then a good pull: second attempt lands (pull=$(calls pull) rc=$r)" || bad "timed-out pull not retried (rc=$r pull=$(calls pull) ${e}s)"
echo "== retry: success paths"
reset; mode pull ok; mode push ok
read -r r e rb <<< "$(run_retry)"
{ [ "$r" = 0 ] && [ "$rb" = 1 ] && [ "$(calls pull)" = 1 ]; } && ok "rebase then push ok: rc=0, OVN_PUSH_REBASED=1, one pull" || bad "success path (rc=$r rebased=$rb)"
reset; mode pull ok; mode push seq:fail,ok
read -r r e rb <<< "$(run_retry)"
{ [ "$r" = 0 ] && [ "$(calls pull)" = 2 ]; } && ok "a second race (push rejected after the first rebase) is retried once more and lands" || bad "second race not retried (rc=$r pull=$(calls pull))"
echo "== retry: conflict is deterministic"
reset; mode pull conflict
read -r r e rb <<< "$(run_retry)"
{ [ "$r" = 1 ] && [ "$(calls pull)" = 1 ] && [ "$(calls push)" = 0 ]; } && ok "rebase conflict: no retry, no push, rc=1" || bad "conflict handling (rc=$r pull=$(calls pull) push=$(calls push))"
grep -q '^rebase ' "$T/calls" && grep -q 'push-retry exhausted' "$T/task.log" && ok "conflict: rebase --abort + exhausted line" || bad "conflict: abort/exhausted missing"

echo "== non-interactive: no tty prompt, no stdin"
reset; mode push ok
( export PATH="$STUB:$PATH" Z7_T="$T"; . "$LIBDIR/lib_push_bound.sh"; sleep 30 | ovn_gitb -C "$T" push origin x ) >/dev/null 2>&1 &
sp=$!; for _ in 1 2 3 4 5 6 7 8; do [ -s "$T/calls" ] && break; sleep 0.5; done; kill $sp 2>/dev/null; wait $sp 2>/dev/null
pl="$(grep '^push ' "$T/calls" | head -1)"
case "$pl" in *"prompt=0 askpass=true stdin=0"*) ok "ovn_gitb sets GIT_TERMINAL_PROMPT=0, GIT_ASKPASS=true and detaches stdin ($pl)";; *) bad "ovn_gitb environment wrong: $pl";; esac
reset; mode push ok
( export PATH="$STUB:$PATH" Z7_T="$T" OVN_GIT_BOUND=off; . "$LIBDIR/lib_push_bound.sh"; ovn_gitb push origin x </dev/null ) >/dev/null 2>&1
case "$(grep '^push ' "$T/calls" | head -1)" in *"prompt=unset"*) ok "OVN_GIT_BOUND=off is a plain git call (kill switch)";; *) bad "kill switch did not disable the hardening";; esac
echo "== the unbounded callers (item guard / landing gates / stage runner style): a hung push no longer blocks"
reset; mode push hang
s=$SECONDS; ( export PATH="$STUB:$PATH" Z7_T="$T" OVN_GIT_NET_TIMEOUT=2; . "$LIBDIR/lib_push_bound.sh"; ovn_gitb -C "$T" push -q origin feature 2>/dev/null; echo "rc=$?" > "$T/hang_rc" ); e=$((SECONDS - s))
{ [ "$e" -le 10 ] && [ "$(cat "$T/hang_rc")" != rc=0 ]; } && ok "ovn_gitb push on a hanging remote returns non-zero after ${e}s (was: forever)" || bad "ovn_gitb push not bounded (${e}s, $(cat "$T/hang_rc" 2>/dev/null))"
reset; mode pull hang
s=$SECONDS; ( export PATH="$STUB:$PATH" Z7_T="$T" OVN_GIT_NET_TIMEOUT=2; . "$LIBDIR/lib_push_bound.sh"; ovn_gitb_pull_rebase -C "$T" -q origin overnight/feature ); r=$?; e=$((SECONDS - s))
{ [ "$e" -le 10 ] && [ "$r" != 0 ] && grep -q '^rebase ' "$T/calls"; } && ok "ovn_gitb_pull_rebase on a hang: bounded (${e}s) and aborts the rebase" || bad "pull_rebase wrapper (rc=$r ${e}s)"

echo "== phase timestamps"
reset
( export OVN_PHASE_LOG="$T/phase.log"; . "$LIBDIR/lib_push_bound.sh"; out="$(ovn_phase generation start; ovn_phase generation end rc=0; ovn_phase verify start; ovn_phase verify end)"; echo "stdout=[$out]" > "$T/phase_stdout" )
[ "$(cat "$T/phase_stdout")" = "stdout=[]" ] && ok "ovn_phase never writes to stdout (callers capture it)" || bad "ovn_phase leaked to stdout: $(cat "$T/phase_stdout")"
grep -qE '^\[[0-9]{2}:[0-9]{2}:[0-9]{2}\] phase=generation start$' "$T/phase.log" && grep -qE '^\[[0-9]{2}:[0-9]{2}:[0-9]{2}\] phase=generation end dur=[0-9]+s rc=0$' "$T/phase.log" && ok "format: [HH:MM:SS] phase=<name> start / end dur=Ns" || bad "phase format: $(cat "$T/phase.log")"
( export OVN_PHASE_LOG="$T/phase2.log" OVN_PHASE_LOG_ON=off; . "$LIBDIR/lib_push_bound.sh"; ovn_phase push start ); [ ! -s "$T/phase2.log" ] && ok "OVN_PHASE_LOG_ON=off silences it" || bad "kill switch"
( task_log="$T/tl.log"; . "$LIBDIR/lib_push_bound.sh"; ovn_phase commit start ); grep -q 'phase=commit start' "$T/tl.log" && ok "falls back to \$task_log" || bad "task_log fallback"
( unset task_log TASK_LOG OVN_PHASE_LOG; . "$LIBDIR/lib_push_bound.sh"; ovn_phase commit start; echo rc=$? > "$T/nolog_rc" ); [ "$(cat "$T/nolog_rc")" = rc=0 ] && ok "no log target: a silent no-op, rc=0" || bad "ovn_phase without a log failed"
echo "== log consumers still parse a log with phase lines"
python3 - "$Q" "$T/phase.log" <<'PYEOF' && ok "walltime markers/timeouts regexes ignore phase lines; implement-attempt / verify-suite-red greps unaffected" || bad "a log consumer reacts to phase lines"
import re, sys, importlib.util
q, log = sys.argv[1], sys.argv[2]
spec = importlib.util.spec_from_file_location("w", q + "/scripts/ovn_cycle_walltime.py"); w = importlib.util.module_from_spec(spec); spec.loader.exec_module(w)
lines = open(log).read().splitlines() + ["[01:02:03] phase=rebase start attempt=1/3", "[01:02:04] phase=post-gates end dur=1s", "[01:02:05] phase=fixup end dur=3s", "[01:02:05] phase=push end dur=2s rc=124"]
bad = [l for l in lines if w._MARK_RE.match(l) or w._TIMEOUT_RE.search(l) or re.search(r"implement attempt|verify-suite-red|VERIFY timed out|^--- ", l) or re.search(r"already (fully |correctly )*(done|implemented)|APIError|Traceback", l)]
sys.exit(1 if bad else 0)
PYEOF

echo "== wiring lint"
RO="$Q/run_overnight.sh"
for p in generation verify fixup commit rebase push post-gates; do
  { grep -q "ovn_phase $p start" "$RO" || grep -q "ovn_phase $p start" "$LIBDIR/lib_push_bound.sh"; } && { grep -q "ovn_phase $p end" "$RO" || grep -q "ovn_phase $p end" "$LIBDIR/lib_push_bound.sh"; } && ok "phase=$p has start+end markers" || bad "phase $p missing start/end"
done
grep -q 'ovn_push_rebase_retry "\$branch" "\$task_log"' "$RO" && ok "the main push path uses ovn_push_rebase_retry" || bad "main push path not wired"
n=$(grep -c 'ovn_push_rebase_retry' "$RO"); [ "$n" -ge 3 ] && ok "main + credit push both use the bounded retry ($n refs)" || bad "credit push not wired ($n)"
unb=""; for f in "$RO" "$Q/ovn_stage_runner.sh" "$Q/scripts/ovn_item_guard.sh" "$Q/scripts/lib_landing_gates.sh"; do
  while IFS= read -r l; do case "$l" in *ovn_gitb*|*"timeout "*|\#*|*"echo "*|*"say "*) ;; *) unb="$unb"$'\n'"$(basename "$f"): ${l:0:110}";; esac
  done < <(grep -nE '(^|[ ;({&|])git( -C "[^"]*")? (push|fetch|pull)( |$)' "$f" | grep -v 'ls-remote')
done
[ -z "$unb" ] && ok "no unbounded git push/fetch/pull left in run_overnight / stage runner / item guard / landing gates" || bad "unbounded git network calls:$unb"
grep -q 'pull --rebase' "$LIBDIR/lib_push_bound.sh" && ! grep -qE 'git (pull|fetch)[^|]*(--no-rebase|merge)' "$LIBDIR/lib_push_bound.sh" && ok "semantics kept: the retry is a pull --rebase (no merge introduced)" || bad "retry semantics changed"
echo "== real runner path: the fallback text of run_overnight still names the push-failed outcome"
grep -q 'error-transient(push-diverged - resynced, retry next cycle)' "$RO" && ok "exhaustion falls back to error-transient(push-diverged - resynced...)" || bad "failure path missing"

if [ -z "${Z7_NO_MUTANTS:-}" ] && [ -z "${Z7_LIB_DIR:-}" ]; then
  echo "== mutation proofs (each mutant must make this file FAIL)"
  MD="$(safe_mktemp_dir z7pbm)" || exit 1; n=0; survived=0
  TB=("$(type -P timeout || type -P gtimeout)" -k 3)   # a mutant that removes a bound HANGS on the stub: killing it after 75 s is the proof it is caught
  mut(){ # mut <label> <old> <new>
    local d="$MD/$((n+1))"; n=$((n+1)); mkdir -p "$d"; cp "$LIBDIR/lib_push_bound.sh" "$d/"
    if ! OLD="$2" NEW="$3" python3 - "$d/lib_push_bound.sh" <<'PYEOF'
import os, sys
p = sys.argv[1]; s = open(p).read()
if os.environ["OLD"] not in s: sys.exit(3)
open(p, "w").write(s.replace(os.environ["OLD"], os.environ["NEW"], 1))
PYEOF
    then echo "  FAIL mutant '$1' not applicable"; survived=$((survived+1)); return; fi
    if Z7_LIB_DIR="$d" Z7_NO_MUTANTS=1 "${TB[@]}" 75 bash "$0" >/dev/null 2>&1; then echo "  FAIL mutant SURVIVED: $1"; survived=$((survived+1)); else echo "  ok   mutant killed: $1"; fi
  }
  mut "no timeout on git"                      'exec "$tb" -k 5 "$t" git "$@"' 'exec git "$@"'
  mut "no GIT_TERMINAL_PROMPT=0"               'GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=true SSH_ASKPASS=true exec' 'GIT_ASKPASS=true SSH_ASKPASS=true exec'
  mut "no GIT_ASKPASS"                         'GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=true SSH_ASKPASS=true exec' 'GIT_TERMINAL_PROMPT=0 SSH_ASKPASS=true exec'
  mut "stdin not detached"                     'git "$@" </dev/null )' 'git "$@" )'
  mut "per-command timeout ignores the remaining budget" '[ "$rem" -lt "$base" ] && base="$rem"' ':'
  mut "attempt bound ignored"                  'while [ "$i" -lt "$n" ]; do' 'while true; do'
  mut "wall-clock cap ignored"                 '[ "$rem" -ge 1 ] || return 1' '[ "$rem" -ge 1 ] || rem=1'
  mut "no exhausted line"                      'echo "--- push-retry exhausted (' 'echo "--- push-retry done ('
  mut "final rebase --abort missing"           '  git rebase --abort >/dev/null 2>&1 || true
  git merge --abort' '  git merge --abort'
  mut "conflict is retried"                    'why="rebase did not apply (rc=${rc})"; break' 'why="rebase did not apply (rc=${rc})"; continue'
  mut "timed-out pull is not retried"          'why="pull --rebase timed out"; continue' 'why="pull --rebase timed out"; break'
  mut "success flag not set"                   'OVN_PUSH_REBASED=1; return 0' 'return 0'
  mut "kill switch ignored"                    '[ "${OVN_GIT_BOUND:-on}" = off ]' 'false'
  mut "phase lines to stdout"                  "printf '%s\\n' \"\$line\" >> \"\$log\" 2>/dev/null || true" "printf '%s\\n' \"\$line\""
  mut "phase format without brackets"          'line="[$(date +%H:%M:%S 2>/dev/null)] phase=' 'line="$(date +%H:%M:%S 2>/dev/null) phase='
  mut "phase dur missing"                      'line="${line} dur=$((SECONDS - t0))s"' ':'
  mut "phase kill switch ignored"              '[ "${OVN_PHASE_LOG_ON:-on}" = off ] && return 0' ':'
  mut "pull_rebase never aborts"               'if [ "$rc" -ne 0 ]; then
    if [ -n "$dir" ]; then git -C' 'if false; then
    if [ -n "$dir" ]; then git -C'
  echo "mutants: $n, survived/unapplied: $survived"; [ "$survived" -eq 0 ] || rc=1
fi
[ "$rc" -eq 0 ] && echo "ALL OK" || echo "FAILED"
exit $rc
