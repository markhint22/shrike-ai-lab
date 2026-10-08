#!/usr/bin/env bash
# test_baseline_refresh_cron.sh - qa/baseline_refresh_cron.sh run EXACTLY as cron would: relative path, `env -i` with a minimal PATH, NTFY_SERVER set,
# in a fake OVN tree with a fake live clone whose working tree DIFFERS from origin/develop (so reading the wrong tree is detectable).
# 2026-10-02. Covers: baseline comes from origin/develop (not the live checkout / overnight/feature), live clone untouched, worktree removed, no run.lock,
# deterministic-only (truncated/timeout/missing ref => old baseline untouched), growth => alert not widen, shrink accepted, 24h expiry, own lock,
# kill switches, always exit 0. Never touches the network or ntfy. Runs on the Mac (mkdir lock) and the box (flock).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
QAS="$HERE/../../qa"
pass=0; fail=0
# 2026-10-08: assertions are evaluated with pipefail OFF - under pipefail `A | grep -q X` is flaky (grep -q exits at its first hit, A may take SIGPIPE: rc 141) and `! A | grep -q X` can mask a real failure
ok(){ if [ "$2" = 1 ]; then pass=$((pass+1)); echo "  ok   $1"; else fail=$((fail+1)); echo "  FAIL $1"; fi; }
T2(){ local l="$1"; if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then ok "$l" 1; else ok "$l" 0; fi; }   # snippet evaluated in THIS shell (helpers visible)
t(){ local l="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$l" 1; else ok "$l" 0; fi; }
PYB="$(command -v python3.12 || command -v python3)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
OVN="$T/ovn"; mkdir -p "$OVN/qa" "$OVN/state" "$OVN/logs" "$OVN/repos" "$T/tmp"
cp "$QAS/qa_common.py" "$QAS/baseline_verify.py" "$QAS/qa_timeout.py" "$QAS/baseline_refresh_cron.sh" "$OVN/qa/"
chmod +x "$OVN/qa/baseline_refresh_cron.sh"
G(){ git -C "$LIVE" "$@"; }
LIVE="$OVN/repos/foo"; ORIGIN="$T/origin.git"
git init -q --bare "$ORIGIN"
git init -q -b main "$LIVE"; G config user.email t@t; G config user.name t
mkdir -p "$LIVE/backend/.venv/bin"
# stub venv pytest: its failures are whatever backend/red.txt says IN THE TREE IT RUNS IN (cwd = the worktree's backend/)
cat > "$LIVE/backend/.venv/bin/pytest" <<'EOF'
#!/bin/sh
[ -f SLOW ] && exec sleep 30
[ -f TRUNC ] && { echo '.......... [ 40%]'; exit 1; }
n=0
if [ -s red.txt ]; then
  echo "=========================== short test summary info ==========================="
  while IFS= read -r id; do [ -n "$id" ] && { echo "FAILED $id - assert 0"; n=$((n+1)); }; done < red.txt
  echo "$n failed, 3 passed in 0.10s"; exit 1
fi
echo "3 passed in 0.10s"; exit 0
EOF
chmod +x "$LIVE/backend/.venv/bin/pytest"
printf '.venv/\n' > "$LIVE/.gitignore"
printf 'tests/test_a.py::test_old\n' > "$LIVE/backend/red.txt"
G add .gitignore backend/red.txt; G commit -q -m develop-content
G remote add origin "$ORIGIN"; G push -q origin main:develop 2>/dev/null; G fetch -q origin
# the LIVE working tree (branch main) now diverges from origin/develop: a different red id + an untracked file
printf 'tests/test_LIVE_ONLY.py::test_live\n' > "$LIVE/backend/red.txt"; G commit -q -am live-only; echo scratch > "$LIVE/untracked.txt"
LIVE_HEAD="$(G rev-parse HEAD)"; LIVE_STATUS="$(G status --porcelain)"
BLF="$OVN/state/qa_baselines/verify/foo.json"

cron(){   # cron(): run as cron does. extra env as args (VAR=val ...). rc in $RC, log in $OVN/logs/baseline_refresh.log
  ( cd "$OVN" && env -i PATH=/usr/local/bin:/usr/bin:/bin:"$(dirname "$PYB")" HOME="$T" TMPDIR="$T/tmp" NTFY_SERVER=http://127.0.0.1:9 \
      OVN_BASELINE_REFRESH_REPOS="${REPOS:-foo}" "$@" bash qa/baseline_refresh_cron.sh ) > "$T/cron.out" 2>&1
  RC=$?
}
ids(){ "$PYB" -c 'import json,sys; print("|".join(json.load(open(sys.argv[1]))["failing"]))' "$BLF" 2>/dev/null; }
LOGTXT(){ cat "$OVN/logs/baseline_refresh.log" 2>/dev/null; }
newfiles(){ ( cd "$OVN" && find . -type f -not -path './repos/*' -not -path './qa/*' | sort ); }

echo "== refresh from origin/develop (not the live checkout)"
cron OVN_REPOS_DIR="$OVN/repos"
t "exit 0" test "$RC" = 0
t "baseline = origin/develop's red set, NOT the live working tree's" test "$(ids)" = "[backend] tests/test_a.py::test_old"
T2 "baseline records the develop commit and source deterministic:refresh" "grep -q deterministic:refresh '$BLF' && grep -q '$(git -C "$LIVE" rev-parse origin/develop)' '$BLF'"
T2 "live clone untouched: same HEAD, same status, untracked file intact" "[ \"\$(git -C '$LIVE' rev-parse HEAD)\" = '$LIVE_HEAD' ] && [ \"\$(git -C '$LIVE' status --porcelain)\" = '$LIVE_STATUS' ] && [ -f '$LIVE/untracked.txt' ]"
t "no worktree left behind (live clone has only its own)" test "$(G worktree list | wc -l | tr -d ' ')" = 1
T2 "no qa-wt-* temp dirs left in TMPDIR" "[ -z \"\$(ls '$T/tmp' | grep qa-wt)\" ]"
T2 "never took run.lock; wrote only state/qa_baselines, state/qa_shadow, the refresh lock and logs" "! find '$OVN/state' -name 'run.lock*' | grep -q . && ! newfiles | grep -vE '^\./(state/(qa_baselines|qa_shadow)/|state/baseline_refresh\.lock|logs/)' | grep -q ."
T2 "log line says PASS + stored_fresh" "grep -q 'foo: PASS | refreshed baseline stored_fresh (1 red ids)' '$OVN/logs/baseline_refresh.log'"
T2 "result row recorded in state/qa_shadow/baseline.jsonl" "grep -q '\"gate\": \"baseline\"' '$OVN/state/qa_shadow/baseline.jsonl'"

echo "== growth is an ALERT, never an auto-widen (negative control)"
printf 'tests/test_a.py::test_old\ntests/test_b.py::test_new_red\n' > "$T/red2"
git clone -q "$ORIGIN" "$T/pusher"; ( cd "$T/pusher" && git config user.email t@t && git config user.name t && git checkout -q develop && cp "$T/red2" backend/red.txt && git commit -qam grow && git push -q origin develop )
G fetch -q origin
BEFORE="$(cat "$BLF")"
cron OVN_REPOS_DIR="$OVN/repos"
t "baseline NOT widened" test "$(ids)" = "[backend] tests/test_a.py::test_old"
T2 "growth_pending recorded + alert row" "grep -q '\"pending_growth\": {' '$BLF' && grep -q growth_pending '$OVN/state/qa_baselines/verify/growth_alerts.jsonl'"
T2 "log says FLAG / GROWTH ALERT" "grep -q 'GROWTH ALERT' '$OVN/logs/baseline_refresh.log'"

echo "== shrink (tests got fixed) is accepted automatically (benign control)"
( cd "$T/pusher" && : > backend/red.txt && git commit -qam fixed && git push -q origin develop ); G fetch -q origin
cron OVN_REPOS_DIR="$OVN/repos"
t "baseline shrinks to empty" test "$(ids)" = ""
T2 "log says stored_shrunk" "grep -q 'stored_shrunk' '$OVN/logs/baseline_refresh.log'"

echo "== deterministic only: truncated / timed-out / missing-ref runs never write"
( cd "$T/pusher" && printf 'tests/test_a.py::test_old\n' > backend/red.txt && touch backend/TRUNC && git add -f backend/TRUNC && git commit -qam trunc && git push -q origin develop ); G fetch -q origin
H0="$(cat "$BLF")"
cron OVN_REPOS_DIR="$OVN/repos"
T2 "truncated pytest output => UNVERIFIED, baseline file byte-identical" "[ \"\$(cat '$BLF')\" = '$H0' ] && grep -q 'foo: UNVERIFIED' '$OVN/logs/baseline_refresh.log'"
( cd "$T/pusher" && git rm -q backend/TRUNC && touch backend/SLOW && git add -f backend/SLOW && git commit -qam slow && git push -q origin develop ); G fetch -q origin
t0=$(date +%s); cron OVN_REPOS_DIR="$OVN/repos" OVN_BASELINE_REPO_TIMEOUT=2; el=$(( $(date +%s) - t0 ))
T2 "suite timeout => UNVERIFIED 'timed out', baseline untouched, bounded (${el}s)" "[ \"\$(cat '$BLF')\" = '$H0' ] && grep -q 'timed out' '$OVN/logs/baseline_refresh.log' && [ $el -le 30 ]"
T2 "timeout leaves no worktree/temp dir behind" "[ \"\$(git -C '$LIVE' worktree list | wc -l | tr -d ' ')\" = 1 ] && [ -z \"\$(ls '$T/tmp' | grep qa-wt)\" ]"
cron OVN_REPOS_DIR="$OVN/repos" OVN_BASELINE_REF=origin/no-such-branch
T2 "missing ref => UNVERIFIED, baseline untouched" "[ \"\$(cat '$BLF')\" = '$H0' ] && grep -q 'could not create worktree' '$OVN/logs/baseline_refresh.log'"
t "...and exit still 0" test "$RC" = 0

echo "== 24h expiry: an expired baseline is replaced by a fresh deterministic one, never silently widened"
( cd "$T/pusher" && git rm -q -f backend/SLOW && printf 'tests/test_a.py::test_old\ntests/test_c.py::test_c\n' > backend/red.txt && git commit -qam c && git push -q origin develop ); G fetch -q origin
"$PYB" - "$BLF" <<'EOF'
import json, sys, time
p = sys.argv[1]; d = json.load(open(p)); d["ts"] = time.time() - 48 * 3600; d["pending_growth"] = None; json.dump(d, open(p, "w"))
EOF
cron OVN_REPOS_DIR="$OVN/repos"
T2 "expired baseline replaced (stored_fresh_grown) and the widen is logged to growth_alerts" "grep -q stored_fresh_grown '$OVN/logs/baseline_refresh.log' && grep -q growth_accepted_after_expiry '$OVN/state/qa_baselines/verify/growth_alerts.jsonl'"

echo "== lock, kill switches, bad input"
if command -v flock >/dev/null 2>&1; then
  ( exec 8>"$OVN/state/baseline_refresh.lock"; flock -n 8 && exec sleep 8 ) & HOLD=$!
else
  mkdir "$OVN/state/baseline_refresh.lock.d"; HOLD=""
fi
sleep 1
H1="$(cat "$BLF")"; cron OVN_REPOS_DIR="$OVN/repos"
T2 "own lock held => skipped (exit 0, baseline untouched)" "[ $RC = 0 ] && [ \"\$(cat '$BLF')\" = '$H1' ] && LOGTXT | tail -1 | grep -q 'still running'"
if [ -n "$HOLD" ]; then kill "$HOLD" 2>/dev/null; wait "$HOLD" 2>/dev/null; else rmdir "$OVN/state/baseline_refresh.lock.d"; fi
: > "$OVN/logs/baseline_refresh.log"
cron OVN_REPOS_DIR="$OVN/repos" OVN_BASELINE_REFRESH=off
T2 "OVN_BASELINE_REFRESH=off => nothing runs" "grep -q 'disabled (OVN_BASELINE_REFRESH=off)' '$OVN/logs/baseline_refresh.log' && ! grep -q 'foo:' '$OVN/logs/baseline_refresh.log'"
: > "$OVN/logs/baseline_refresh.log"
cron OVN_REPOS_DIR="$OVN/repos" OVN_BASELINE_SHADOW=off
T2 "OVN_BASELINE_SHADOW=off (the runner hook's switch) also stops the refresh" "grep -q 'disabled (OVN_BASELINE_SHADOW=off)' '$OVN/logs/baseline_refresh.log'"
: > "$OVN/logs/baseline_refresh.log"; echo '{"baseline":"off"}' > "$OVN/state/qa_modes.json"
cron OVN_REPOS_DIR="$OVN/repos"
T2 "qa mode baseline=off => nothing runs" "grep -q 'qa mode baseline=off' '$OVN/logs/baseline_refresh.log'"
rm -f "$OVN/state/qa_modes.json"; : > "$OVN/logs/baseline_refresh.log"
REPOS="ghost ../evil foo bad;name" cron OVN_REPOS_DIR="$OVN/repos" OVN_BASELINE_BUDGET=100000
T2 "unknown clone skipped, path-traversal / shell-meta names skipped, exit 0" "[ $RC = 0 ] && grep -q 'ghost: no clone' '$OVN/logs/baseline_refresh.log' && grep -q 'skipped bad repo name' '$OVN/logs/baseline_refresh.log'"
: > "$OVN/logs/baseline_refresh.log"
REPOS="foo" cron OVN_REPOS_DIR="$OVN/repos" OVN_BASELINE_BUDGET=0
T2 "total budget spent => remaining repos skipped" "grep -q 'foo: skipped (total budget 0s spent)' '$OVN/logs/baseline_refresh.log'"

echo "== never prints secrets / never reaches ntfy (no NTFY or network use in the script)"
T2 "script code (non-comment lines) contains no curl/wget/ntfy/url" "! grep -vE '^[[:space:]]*#' '$QAS/baseline_refresh_cron.sh' | grep -qE 'curl|wget|ntfy|https?://'"

echo; echo "$pass passed, $fail failed"; [ "$fail" -eq 0 ]
