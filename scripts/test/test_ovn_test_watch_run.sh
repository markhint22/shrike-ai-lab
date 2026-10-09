#!/usr/bin/env bash
# Runs the REAL ovn_test_watch.sh (full-suite watchdog) end to end in a fake $HOME tree: per-repo git clones with bare origins,
# stub pytest (.venv/bin/pytest) / npx (vitest) / godot (GUT), exported-function stubs for curl and flock (the script puts
# system dirs first on PATH, so PATH stubs for those would lose to the real binaries). Covers green/red/timeout for each
# runner, EMERGENCY item insertion (with header / without header / duplicate-open / closed-retired / no progress file), git
# sync failure, missing clone, test_watch.lock exclusion, unprovisioned + non-vitest web packages.
# 2026-10-02 (worktree redesign): the sweep tests each repo in a DETACHED WORKTREE of origin/overnight/feature and never takes
# run.lock, so fixtures commit what a real repo tracks (package.json, project.godot, addons/gut...) and leave only the
# envs (.venv, node_modules) untracked; extra cases cover: sweep proceeds while run.lock is held by another process, a second
# sweep is excluded by test_watch.lock, the live clone is never modified, worktrees are removed on TERM / push failure /
# next start (SIGKILL orphans), and a red suite files exactly ONE emergency. Lock cases need real flock (the box has it).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
TW=""
for c in "$HERE/../../ovn_test_watch.sh" "$HERE/../ovn_test_watch.sh" "$HERE/ovn_test_watch.sh"; do [ -f "$c" ] && { TW="$c"; break; }; done
[ -n "$TW" ] || { echo "  SKIP: ovn_test_watch.sh not found"; exit 0; }
P=0; F=0
ok(){ if [ "$2" = "1" ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
has(){ printf '%s' "$OUT" | grep -qF -- "$1" && echo 1 || echo 0; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
H="$T/home"; R="$H/overnight-queue"; ORG="$T/origins"; ALERTS="$T/alerts.txt"; PWDLOG="$T/pwd_seen.txt"
mkdir -p "$R/state" "$R/repos" "$ORG" "$H/aider-venv/bin" "$H/godot"; : > "$ALERTS"; : > "$PWDLOG"; export ALERTS PWDLOG
REALFLOCK=0; command -v flock >/dev/null 2>&1 && REALFLOCK=1
curl(){ local t=""; while [ $# -gt 0 ]; do case "$1" in -H) case "$2" in Title:*) t="$2";; esac; shift 2;; -d|--max-time) shift 2;; -*) shift;; *) shift;; esac; done; echo "$t" >> "$ALERTS"; return 0; }
export -f curl
# no real flock (e.g. a Mac): permissive stub so the rest of the suite still runs; the lock cases below are skipped
[ "$REALFLOCK" = 1 ] || { flock(){ return 0; }; export -f flock; }

# ---- runner stubs ----
cat > "$H/aider-venv/bin/npx" <<'EOF'
#!/usr/bin/env bash
# fake `npx vitest run`: behaviour chosen by ./VITEST_MODE in the package dir
case "$(cat VITEST_MODE 2>/dev/null)" in
  red)     printf 'stdout\n FAIL  src/a.test.ts > adds\n x1 failed\n Tests  1 failed | 3 passed\n'; exit 1;;
  timeout) exit 124;;
  *)       printf ' Tests  7 passed (7)\n'; exit 0;;
esac
EOF
cat > "$H/godot/godot4" <<'EOF'
#!/usr/bin/env bash
# fake godot: --import run prints nothing; the GUT run prints per ./GUT_MODE in cwd
case "$*" in *--import*) exit 0;; esac
case "$(cat GUT_MODE 2>/dev/null)" in
  red) printf 'Totals\n2 failing\nErrors 1\n';;
  *)   printf 'Totals\n9 passed\n';;
esac
exit 0
EOF
chmod +x "$H/aider-venv/bin/npx" "$H/godot/godot4"
mkdir -p "$H/godot" ; # script's GODOT is $HOME/godot/godot4

prog_with_header(){ printf '# Progress\n\n## Next Steps\n- [ ] existing item A\n- [ ] existing item B\n\n## Done\n- [x] old\n'; }
mkclone(){ # $1 name [$2 progress: header|nohdr|none|closed]
  local n="$1" mode="${2:-header}" o="$ORG/$1.git" d="$R/repos/$1"
  git init -q --bare "$o"
  mkdir -p "$d"
  ( cd "$d" && git init -q -b overnight/feature && git config user.email t@t && git config user.name t
    echo base > README.md; printf '.venv/\nnode_modules/\n' > .gitignore
    case "$mode" in
      header) prog_with_header > OVERNIGHT_PROGRESS.md;;
      nohdr)  printf 'just some text, no steps header\n' > OVERNIGHT_PROGRESS.md;;
      closed) { prog_with_header; echo "- [x] (retired-stale) [EMERGENCY][T2] ${n} pytest suite is RED — old one"; } > OVERNIGHT_PROGRESS.md;;
      none) ;;
    esac
    git add -A; git commit -q -m base; git remote add origin "$o"; git push -q origin overnight/feature )
}
pystub(){ # $1=repo dir  $2=mode  [$3=subdir]
  local d="$R/repos/$1${3:+/$3}"; mkdir -p "$d/.venv/bin"
  [ -n "${3:-}" ] && echo tracked > "$d/keep.txt"   # a real nested package tracks files; only the .venv is untracked
  case "$2" in
    green)   printf '#!/usr/bin/env bash\npwd >> "$PWDLOG"\necho "12 passed in 1.2s"\nexit 0\n' ;;
    term)    printf '#!/usr/bin/env bash\n# simulate the sweep being TERMinated mid-suite: signal the TOP-most `bash /…/ovn_test_watch.sh` ancestor (contiguous chain only), then die\np=$$; top=""\nwhile p="$(ps -o ppid= -p "$p" | tr -d " ")"; [ -n "$p" ] && [ "$p" -gt 1 ]; do a="$(ps -o args= -p "$p")"; case "$a" in "bash /"*"/ovn_test_watch.sh"*) top="$p";; *) [ -n "$top" ] && break;; esac; done\n[ -n "$top" ] && kill -TERM "$top"\nexit 1\n' ;;
    red)     printf '#!/usr/bin/env bash\necho "FAILED tests/test_a.py::test_x - AssertionError"\necho "ERROR tests/test_b.py"\necho "2 failed, 3 passed in 1s"\nexit 1\n' ;;
    errnolines) printf '#!/usr/bin/env bash\necho "3 error in 0.5s"\nexit 2\n' ;;
    timeout) printf '#!/usr/bin/env bash\nexit 124\n' ;;
    flaky)   printf '#!/usr/bin/env bash\nc="$(dirname "$0")/.n"; n=$(cat "$c" 2>/dev/null || echo 0); echo $((n+1)) > "$c"\nif [ "$n" = 0 ]; then echo "FAILED tests/test_flaky.py::t"; echo "1 failed in 1s"; exit 1; fi\necho "4 passed in 1s"; exit 0\n' ;;
  esac > "$d/.venv/bin/pytest"
  chmod +x "$d/.venv/bin/pytest"
}
webpkg(){ # $1=repo $2=mode(red|green|timeout) $3=vitest?(1/0) $4=provisioned?(1/0) [$5 subdir]
  local d="$R/repos/$1/${5:-web}"; mkdir -p "$d"
  if [ "$3" = 1 ]; then echo '{"devDependencies":{"vitest":"^1"}}' > "$d/package.json"; else echo '{"name":"x"}' > "$d/package.json"; fi
  [ "$4" = 1 ] && mkdir -p "$d/node_modules/vitest"
  echo "$2" > "$d/VITEST_MODE"
}

# ---------------- repos ----------------
mkclone r_py_red;     pystub r_py_red red
mkclone r_py_green;   pystub r_py_green green
mkclone r_py_flaky;   pystub r_py_flaky flaky
mkclone r_py_timeout; pystub r_py_timeout timeout
mkclone r_py_errnl;   pystub r_py_errnl errnolines
mkclone r_py_nested;  pystub r_py_nested red backend
mkclone r_py_term;    pystub r_py_term term
mkclone r_py_pushfail; pystub r_py_pushfail red
mkclone r_py_race;  pystub r_py_race red     # not in ALL: only the run.lock race cases below sweep these
mkclone r_py_race2; pystub r_py_race2 red
mkclone r_py_nohdr nohdr; pystub r_py_nohdr red
mkclone r_py_closed closed; pystub r_py_closed red
mkclone r_py_noprog none;  pystub r_py_noprog red
mkclone r_web_red;    webpkg r_web_red red 1 1
mkclone r_web_timeout; webpkg r_web_timeout timeout 1 1
mkclone r_web_green;  webpkg r_web_green green 1 1
mkclone r_web_noprov; webpkg r_web_noprov red 1 0
mkclone r_web_novitest; webpkg r_web_novitest red 0 1
mkclone r_gd_red;     mkdir -p "$R/repos/r_gd_red/game/addons/gut"; touch "$R/repos/r_gd_red/game/addons/gut/gut_cmdln.gd" "$R/repos/r_gd_red/game/project.godot"; echo red > "$R/repos/r_gd_red/game/GUT_MODE"
mkclone r_gd_green;   mkdir -p "$R/repos/r_gd_green/game/addons/gut"; touch "$R/repos/r_gd_green/game/addons/gut/gut_cmdln.gd" "$R/repos/r_gd_green/game/project.godot"
mkclone r_gd_nogut;   mkdir -p "$R/repos/r_gd_nogut/game"; touch "$R/repos/r_gd_nogut/game/project.godot"
# repo whose origin lacks overnight/feature -> git sync failure
mkdir -p "$R/repos/r_nosync"; ( cd "$R/repos/r_nosync" && git init -q -b main && git config user.email t@t && git config user.name t && echo x > f && git add f && git commit -q -m x && git init -q --bare "$ORG/r_nosync.git" && git remote add origin "$ORG/r_nosync.git" && git push -q origin main )
git -C "$R/repos/r_py_red" config user.email t@t >/dev/null

# commit what a real repo tracks (everything but the gitignored envs) and push, so origin/overnight/feature carries it - the
# sweep tests origin's head in a worktree, not the live clone's working tree. (r_nosync deliberately has no overnight/feature.)
for d in "$R"/repos/*/; do
  n="$(basename "$d")"; [ "$n" = r_nosync ] && continue
  ( cd "$d" && git add -A && git commit -q -m fixtures && git push -q origin overnight/feature )
done
# r_py_pushfail: origin rejects every push from now on -> the EMERGENCY write fails after its worktree was opened
printf '#!/bin/sh\nexit 1\n' > "$ORG/r_py_pushfail.git/hooks/pre-receive"; chmod +x "$ORG/r_py_pushfail.git/hooks/pre-receive"
ALL="r_missing r_nosync r_py_red r_py_flaky r_py_green r_py_timeout r_py_errnl r_py_nested r_py_nohdr r_py_closed r_py_noprog r_web_red r_web_timeout r_web_green r_web_noprov r_web_novitest r_gd_red r_gd_green r_gd_nogut"
run(){ OUT="$(cd "$H" && HOME="$H" bash "$TW" "$@" 2>&1)"; RC=$?; }
snap(){ { git -C "$R/repos/$1" rev-parse HEAD; git -C "$R/repos/$1" status --porcelain; git -C "$R/repos/$1" rev-parse --abbrev-ref HEAD; } | md5sum 2>/dev/null || md5; }
LIVE_BEFORE="$(snap r_py_red)|$(snap r_web_red)|$(snap r_py_green)"
LS_START=$(date +%s)
run $ALL
LS_SECS=$(( $(date +%s) - LS_START ))
ok "benign: run.lock free -> every emergency filed straight away, none deferred" "$([ "$(has 'DEFERRED')" = 0 ] && [ "$(has 'retrying deferred')" = 0 ] && echo 1 || echo 0)"
ok "run 1 exits 0" "$([ "$RC" = 0 ] && echo 1 || echo 0)"
ok "sweep start+complete markers" "$([ "$(has 'test-health sweep start')" = 1 ] && [ "$(has 'test-health sweep complete')" = 1 ] && echo 1 || echo 0)"
ok "missing clone skipped" "$(has 'r_missing: no clone — skip')"
ok "git sync failure skipped" "$(has 'r_nosync: git sync failed — skip')"
ok "pytest green logged with pass count" "$(has 'r_py_green: pytest green in r_py_green (12 passed)')"
ok "pytest red logged with FAILED/ERROR detail" "$(has 'r_py_red: pytest RED in r_py_red — FAILED tests/test_a.py::test_x')"
ok "flaky red (green on re-run) is NOT filed as an emergency" "$([ "$(has 're-running once to rule out contention')" = 1 ] && [ "$(has 'r_py_flaky: pytest green in r_py_flaky (4 passed)')" = 1 ] && ! git -C "$ORG/r_py_flaky.git" show overnight/feature:OVERNIGHT_PROGRESS.md | grep -q EMERGENCY && echo 1 || echo 0)"
ok "pytest timeout is RED not green" "$(has 'pytest TIMED OUT in r_py_timeout after 600s')"
ok "pytest 'N error' without FAILED lines falls back to summary line" "$(has 'r_py_errnl: pytest RED in r_py_errnl — 3 error in 0.5s')"
ok "nested .venv (backend/) discovered, area uses basename" "$(has 'r_py_nested: pytest RED in backend')"
ok "vitest red logged" "$(has 'r_web_red: vitest RED in web')"
ok "vitest timeout is RED" "$(has 'vitest TIMED OUT in web after 400s')"
ok "vitest green logged with count" "$(has 'r_web_green: vitest green in web (7 passed)')"
ok "unprovisioned web package skipped" "$(has 'r_web_noprov: web not provisioned (no node_modules) — skip web')"
ok "package.json without vitest silently ignored" "$(printf '%s' "$OUT" | grep -q 'r_web_novitest: vitest' && echo 0 || echo 1)"
ok "GUT red logged" "$(has 'r_gd_red: GUT RED')"
ok "GUT green logged with count" "$(has 'r_gd_green: GUT green (9 passed)')"
ok "godot project without addons/gut ignored" "$(printf '%s' "$OUT" | grep -q 'r_gd_nogut: GUT' && echo 0 || echo 1)"

fetch_prog(){ git -C "$ORG/$1.git" show "overnight/feature:OVERNIGHT_PROGRESS.md" 2>/dev/null; }
ok "EMERGENCY item pushed to origin for pytest red, inserted right under '## Next Steps'" "$(fetch_prog r_py_red | sed -n '/## Next Steps/{n;p;}' | grep -q '\[EMERGENCY\]\[T2\] r_py_red pytest suite is RED' && echo 1 || echo 0)"
ok "EMERGENCY item names the failing test file so the fleet preloads it" "$(fetch_prog r_py_red | grep -q 'Files to read and fix: `tests/test_a.py`' && echo 1 || echo 0)"
ok "EMERGENCY detail carries the failing tests" "$(fetch_prog r_py_red | grep -q 'Failing: FAILED tests/test_a.py::test_x' && echo 1 || echo 0)"
ok "timeout EMERGENCY text mentions 600s" "$(fetch_prog r_py_timeout | grep -q 'did not finish within 600s' && echo 1 || echo 0)"
ok "vitest timeout EMERGENCY text mentions 400s" "$(fetch_prog r_web_timeout | grep -q 'did not finish within 400s' && echo 1 || echo 0)"
ok "vitest red EMERGENCY pushed" "$(fetch_prog r_web_red | grep -q 'web vitest suite is RED' && echo 1 || echo 0)"
ok "GUT red EMERGENCY pushed" "$(fetch_prog r_gd_red | grep -q 'godot GUT suite is RED' && echo 1 || echo 0)"
ok "progress file with NO '## Next Steps' header gets one prepended" "$(fetch_prog r_py_nohdr | head -2 | tr '\n' '|' | grep -q '^## Next Steps|- \[ \] \[EMERGENCY\]' && echo 1 || echo 0)"
ok "closed/retired '- [x]' emergency does NOT block a fresh one" "$(fetch_prog r_py_closed | grep -c '^- \[ \] \[EMERGENCY\]\[T2\] r_py_closed pytest suite is RED' | grep -q '^1$' && echo 1 || echo 0)"
ok "repo without OVERNIGHT_PROGRESS.md: no enqueue, no crash" "$(has 'r_py_noprog: pytest RED' )"
ok "emergency queued log line" "$(has 'r_py_red/r_py_red pytest: EMERGENCY fix item queued + pushed')"
ok "ntfy alert per emergency (title names repo+area)" "$(grep -q 'Title: r_py_red r_py_red pytest tests are red' "$ALERTS" && echo 1 || echo 0)"
ok "no alert for green repos" "$(grep -q 'r_py_green' "$ALERTS" && echo 0 || echo 1)"

# ---- run 2: duplicates must not be re-filed ----
before="$(fetch_prog r_py_red | grep -c 'EMERGENCY')"
run r_py_red r_web_red
after="$(fetch_prog r_py_red | grep -c 'EMERGENCY')"
ok "run 2: open emergency already queued -> skipped" "$([ "$(has 'emergency already queued (open) — skip')" = 1 ] && [ "$before" = "$after" ] && echo 1 || echo 0)"

# ---- run 3: a SECOND sweep is excluded by test_watch.lock (bounded wait), the first is unaffected ----
if [ "$REALFLOCK" = 1 ]; then
  ( flock -x 9; exec sleep 120 ) 9>"$R/state/test_watch.lock" & HP=$!
  for _ in 1 2 3 4 5 6 7 8 9 10; do ( flock -n 9 ) 9>"$R/state/test_watch.lock" 2>/dev/null || break; sleep 0.3; done
  OVN_TW_LOCK_WAIT=1 run r_py_green
  ok "test_watch.lock held -> this pass skipped, exit 0, never started" "$([ "$RC" = 0 ] && [ "$(has 'another test-health sweep still holds test_watch.lock')" = 1 ] && [ "$(has 'sweep start')" = 0 ] && echo 1 || echo 0)"
  kill "$HP" 2>/dev/null; wait "$HP" 2>/dev/null
  OVN_TW_LOCK_WAIT=1 run r_py_green
  ok "lock released -> next sweep runs normally" "$([ "$RC" = 0 ] && [ "$(has 'test-health sweep complete')" = 1 ] && echo 1 || echo 0)"
else echo "  SKIP test_watch.lock exclusion (no flock on this host)"; fi

# ---- run 3b: the fleet's run.lock is NOT needed: sweep completes while another process holds it ----
if [ "$REALFLOCK" = 1 ]; then
  ( flock -x 9; exec sleep 120 ) 9>"$R/state/run.lock" & HP=$!
  for _ in 1 2 3 4 5 6 7 8 9 10; do ( flock -n 9 ) 9>"$R/state/run.lock" 2>/dev/null || break; sleep 0.3; done
  ok "precondition: run.lock really is held by another process" "$( ( flock -n 9 ) 9>"$R/state/run.lock" 2>/dev/null && echo 0 || echo 1)"
  RL_START=$(date +%s)
  OUT="$(cd "$H" && HOME="$H" timeout 60 bash "$TW" r_py_green r_web_green 2>&1)"; RC=$?
  RL_SECS=$(( $(date +%s) - RL_START ))
  ok "sweep completes (exit 0) while run.lock is held elsewhere - no waiting on the dev loop" "$([ "$RC" = 0 ] && [ "$(has 'test-health sweep complete')" = 1 ] && [ "$(has 'r_py_green: pytest green')" = 1 ] && [ "$(has 'r_web_green: vitest green')" = 1 ] && echo 1 || echo 0)"
  ok "...and quickly (<30s here; the old code blocked up to 3600s)" "$([ "$RL_SECS" -lt 30 ] && echo 1 || echo 0)"
  ok "run.lock is never mentioned or taken by the sweep" "$(printf '%s' "$OUT" | grep -q 'run.lock' && echo 0 || echo 1)"
  ok "the other process still holds run.lock afterwards (sweep did not steal/kill it)" "$(kill -0 "$HP" 2>/dev/null && echo 1 || echo 0)"
  kill "$HP" 2>/dev/null; wait "$HP" 2>/dev/null
  echo "  timing: full 19-repo fixture sweep ${LS_SECS}s; run.lock-held sweep ${RL_SECS}s"
else echo "  SKIP run.lock-held case (no flock on this host)"; fi

# ---- run 3c (2026-10-02 review fix): an EMERGENCY push must never land while a fleet cycle is live ----
# The cycle (holds run.lock) has an UNPUSHED local commit flipping the top '## Next Steps' checkbox - the line our insert is
# adjacent to. Pushing the emergency now makes the cycle's `pull --rebase` conflict and run_overnight.sh's push-rejected path
# `reset --hard`s the landed commit away. So: nothing may reach origin until the cycle has pushed and released run.lock.
if [ "$REALFLOCK" = 1 ]; then
  RC_LIVE="$R/repos/r_py_race"; RC_ORG="$ORG/r_py_race.git"
  ( flock -x 9
    echo held > "$T/race_held"
    cd "$RC_LIVE" && sed -i.bak 's/^- \[ \] existing item A/- [x] existing item A/' OVERNIGHT_PROGRESS.md && rm -f OVERNIGHT_PROGRESS.md.bak \
      && git add OVERNIGHT_PROGRESS.md && git commit -q -m "fleet: land item A (local, unpushed)"
    sleep 6
    git --git-dir="$RC_ORG" show overnight/feature:OVERNIGHT_PROGRESS.md | grep -c EMERGENCY > "$T/race_origin_during" || true
    git push -q origin overnight/feature 2> "$T/race_push_err"; echo $? > "$T/race_push_rc"
  ) 9>"$R/state/run.lock" & HP=$!
  for _ in $(seq 1 40); do [ -f "$T/race_held" ] && break; sleep 0.25; done
  FLEET_SHA="$(git -C "$RC_LIVE" rev-parse HEAD)"
  OVN_TW_EMERG_LOCK_WAIT=1 OVN_TW_EMERG_RETRY_WAIT=40 run r_py_race
  wait "$HP" 2>/dev/null
  ok "race: with a cycle live (run.lock held, unpushed local commit) NOTHING was pushed to origin" "$([ "$(cat "$T/race_origin_during" 2>/dev/null)" = 0 ] && echo 1 || echo 0)"
  ok "race: the filing was DEFERRED, then retried once the cycle released run.lock" "$([ "$(has 'EMERGENCY filing DEFERRED')" = 1 ] && [ "$(has 'retrying deferred EMERGENCY filing')" = 1 ] && [ "$(has 'r_py_race/r_py_race pytest: EMERGENCY fix item queued + pushed')" = 1 ] && echo 1 || echo 0)"
  ok "race: the cycle's own push was NOT rejected (rc 0, no push-diverged -> no reset --hard)" "$([ "$(cat "$T/race_push_rc" 2>/dev/null)" = 0 ] && echo 1 || echo 0)"
  ok "race: the cycle's local commit survived in the live clone and is in origin's history" "$(git -C "$RC_LIVE" cat-file -e "$FLEET_SHA" 2>/dev/null && git -C "$RC_ORG" merge-base --is-ancestor "$FLEET_SHA" overnight/feature 2>/dev/null && echo 1 || echo 0)"
  ok "race: origin ends with BOTH the landed '[x] item A' flip and exactly one EMERGENCY item on top" "$(fetch_prog r_py_race | grep -q '^- \[x\] existing item A' && [ "$(fetch_prog r_py_race | grep -c '^- \[ \] \[EMERGENCY\]\[T2\] r_py_race pytest suite is RED')" = 1 ] && fetch_prog r_py_race | sed -n '/## Next Steps/{n;p;}' | grep -q EMERGENCY && echo 1 || echo 0)"
  ok "race: exactly one alert, sent only after the item was really queued" "$([ "$(grep -c 'Title: r_py_race r_py_race pytest tests are red' "$ALERTS")" = 1 ] && echo 1 || echo 0)"
  ok "race: run.lock is free again after the sweep (fd 202 not leaked)" "$( ( flock -n 9 ) 9>"$R/state/run.lock" && echo 1 || echo 0)"

  # still busy for the whole sweep + retry: nothing pushed, no false 'queued' alert, no failure exit; next sweep re-detects
  ( flock -x 9; echo held > "$T/race2_held"; exec sleep 15 ) 9>"$R/state/run.lock" & HP=$!
  for _ in $(seq 1 40); do [ -f "$T/race2_held" ] && break; sleep 0.25; done
  O2_BEFORE="$(git -C "$ORG/r_py_race2.git" rev-parse overnight/feature)"
  OVN_TW_EMERG_LOCK_WAIT=1 OVN_TW_EMERG_RETRY_WAIT=2 run r_py_race2
  ok "busy throughout: sweep exits 0, origin untouched, still-deferred logged, no alert" "$([ "$RC" = 0 ] && [ "$(git -C "$ORG/r_py_race2.git" rev-parse overnight/feature)" = "$O2_BEFORE" ] && [ "$(has 'still deferred after retry')" = 1 ] && [ "$(has 'test-health sweep complete')" = 1 ] && ! grep -q 'r_py_race2' "$ALERTS" && echo 1 || echo 0)"
  kill "$HP" 2>/dev/null; wait "$HP" 2>/dev/null
  run r_py_race2
  ok "busy throughout: once the cycle is gone the next sweep files it" "$(fetch_prog r_py_race2 | grep -q '^- \[ \] \[EMERGENCY\]\[T2\] r_py_race2 pytest suite is RED' && echo 1 || echo 0)"
else echo "  SKIP run.lock emergency race cases (no flock on this host)"; fi

# ---- the suite runs in a detached worktree of origin's head; the live clone is never touched ----
ok "pytest ran inside a /tmp/wt-tw-* worktree, not the live clone" "$(grep -q '^/tmp/wt-tw-r_py_green\.' "$PWDLOG" && ! grep -q "$R/repos" "$PWDLOG" && echo 1 || echo 0)"
LIVE_AFTER="$(snap r_py_red)|$(snap r_web_red)|$(snap r_py_green)"
ok "live clone HEAD/branch/working tree byte-identical after sweeps that filed emergencies (no checkout/reset/edit)" "$([ "$LIVE_BEFORE" = "$LIVE_AFTER" ] && echo 1 || echo 0)"
ok "no worktree left registered / on disk after a normal sweep" "$([ "$(git -C "$R/repos/r_py_red" worktree list | wc -l | tr -d ' ')" = 1 ] && ! ls -d /tmp/wt-tw-r_py_red.* >/dev/null 2>&1 && echo 1 || echo 0)"
ok "a red suite files exactly ONE emergency item, one commit, one alert (after the confirmation re-run)" "$([ "$(fetch_prog r_py_red | grep -c '^- \[ \] \[EMERGENCY\]\[T2\] r_py_red pytest suite is RED')" = 1 ] && [ "$(git -C "$ORG/r_py_red.git" log --oneline overnight/feature | grep -c 'EMERGENCY.*suite red')" = 1 ] && [ "$(grep -c 'Title: r_py_red r_py_red pytest tests are red' "$ALERTS")" = 1 ] && echo 1 || echo 0)"

# ---- worktree cleanup on failure paths ----
run r_py_term
ok "TERM mid-suite: exits 143, no 'sweep complete'" "$([ "$RC" = 143 ] && [ "$(has 'test-health sweep complete')" = 0 ] && [ "$(has 'terminated')" = 1 ] && echo 1 || echo 0)"
ok "TERM mid-suite: worktree removed (not registered, not on disk)" "$([ "$(git -C "$R/repos/r_py_term" worktree list | wc -l | tr -d ' ')" = 1 ] && ! ls -d /tmp/wt-tw-r_py_term.* >/dev/null 2>&1 && echo 1 || echo 0)"
ok "TERM mid-suite: test_watch.lock released (fd 201 not leaked to a child)" "$( [ "$REALFLOCK" = 0 ] && echo 1 || { ( flock -n 9 ) 9>"$R/state/test_watch.lock" && echo 1 || echo 0; } )"
run r_py_pushfail
ok "EMERGENCY push rejected by origin: not logged as queued" "$([ "$(has 'r_py_pushfail/r_py_pushfail pytest: EMERGENCY fix item queued')" = 0 ] && [ "$(has 'r_py_pushfail: pytest RED')" = 1 ] && echo 1 || echo 0)"
ok "EMERGENCY push rejected: worktree still cleaned up" "$([ "$(git -C "$R/repos/r_py_pushfail" worktree list | wc -l | tr -d ' ')" = 1 ] && ! ls -d /tmp/wt-tw-r_py_pushfail.* >/dev/null 2>&1 && echo 1 || echo 0)"
ok "EMERGENCY push rejected: sweep still completes and the alert still goes out" "$([ "$(has 'test-health sweep complete')" = 1 ] && grep -q 'Title: r_py_pushfail r_py_pushfail pytest tests are red' "$ALERTS" && echo 1 || echo 0)"
# an orphan left by a SIGKILL'd sweep is reaped by the next sweep's start (it holds test_watch.lock, so it is provably not live)
git -C "$R/repos/r_py_green" worktree add -q --detach /tmp/wt-tw-r_py_green.orphan origin/overnight/feature
run r_py_green
ok "orphaned wt-tw-* worktree from a killed sweep is reaped at next start" "$([ "$(has 'reaping orphaned test-watch worktree')" = 1 ] && [ ! -d /tmp/wt-tw-r_py_green.orphan ] && [ "$(git -C "$R/repos/r_py_green" worktree list | wc -l | tr -d ' ')" = 1 ] && echo 1 || echo 0)"
# benign: a live worktree that is NOT ours (different prefix) is left alone
git -C "$R/repos/r_py_green" worktree add -q --detach /tmp/wt-notours-$$ origin/overnight/feature
run r_py_green
ok "non-test-watch worktrees are never reaped by the sweep" "$([ -d /tmp/wt-notours-$$ ] && echo 1 || echo 0)"
git -C "$R/repos/r_py_green" worktree remove --force /tmp/wt-notours-$$ >/dev/null 2>&1

# ---- run 4: default REPOS list (no args) is iterated; absent clones just skip ----
run
ok "no-arg run walks the default repo list" "$([ "$(has 'billwatch: no clone — skip')" = 1 ] && [ "$(has 'shrike-labs-website: no clone — skip')" = 1 ] && echo 1 || echo 0)"

# ---- godot absent -> GUT phase skipped entirely ----
rm -f "$H/godot/godot4"
run r_gd_red
ok "no godot binary: GUT phase silently skipped" "$(printf '%s' "$OUT" | grep -q 'GUT' && echo 0 || echo 1)"

# ---- cd failure ----
OUT="$(HOME="$T/nohome" bash "$TW" 2>&1)"; RC=$?
ok "missing \$HOME/overnight-queue exits 1" "$([ "$RC" = 1 ] && echo 1 || echo 0)"

echo "ovn_test_watch_run: $P passed, $F failed"
[ "$F" = 0 ]
