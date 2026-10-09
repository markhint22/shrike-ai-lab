#!/usr/bin/env bash
# ovn_git_sync.sh (2026-10-09): the live-dir auto-sync silently failed for 7 days (last auto-sync commit 10-02). `git add -A` walks the whole tree incl. the fleet's
# transient state/ files and aborted ("fatal: unable to stat 'state/HOLD_xlite'", 28 log lines); nothing was staged so the script exited 0 and nobody noticed.
# Now: explicit pathspec (never state/ logs/ repos/ worktrees/), one retry on a stat failure, state/git_sync_last_ok on success, a warn line in
# state/alerts.log on a persistent failure and when the marker is older than 24 h.
# Runs the REAL script in a throwaway repo + bare origin under a fake HOME. `git` is a PATH wrapper that can make `git add` fail like the live one did (a file that
# vanished between the directory scan and the stat), then everything is run again against 6 mutants of the script, each of which must be caught.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
G=""; for c in "$HERE/../../ovn_git_sync.sh" "$HERE/../ovn_git_sync.sh"; do [ -f "$c" ] && { G="$c"; break; }; done
[ -n "$G" ] || { echo "  SKIP: ovn_git_sync.sh not found"; exit 0; }
G="$(cd "$(dirname "$G")" && pwd)/$(basename "$G")"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
T="$(cd "$T" && pwd -P)"   # /private/var vs /var on macOS
P=0; F=0
# assertions are evaluated with pipefail OFF (no `x | grep -q` flakiness); conditions use grep -c / [ ] only
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $SUITE: $1"; fi; }
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
REALGIT="$(command -v git)"

build(){  # $1=script under test -> fresh live-dir repo with a bare origin
  W="$T/w.$RANDOM"; HOME_="$W/home"; R="$HOME_/overnight-queue"; BARE="$W/origin.git"; CTL="$W/ctl"; BIN="$W/bin"
  mkdir -p "$R/scripts" "$R/qa" "$R/state" "$CTL" "$BIN"
  cp "$1" "$R/ovn_git_sync.sh"
  git init -q --bare "$BARE"
  ( cd "$R" && git init -q && git config user.email t@t && git config user.name t && git remote add origin "$BARE" \
    && echo v1 > scripts/a.sh && echo v1 > qa/q.sh && echo v1 > queue.sh && echo '{"a":1}' > tasks.json && echo r > README.md \
    && git add -A && git commit -q -m init && git checkout -q -b overnight-live && git push -q -u origin overnight-live ) >/dev/null 2>&1
  # `git` wrapper: records every `add` (full args); fails the next $CTL/add_fail_n of them exactly like the live incident, otherwise passes through
  cat > "$BIN/git" <<EOF
#!/usr/bin/env bash
args=("\$@"); i=0; while [ "\${args[\$i]:-}" = "-c" ]; do i=\$((i+2)); done
if [ "\${args[\$i]:-}" = add ]; then
  echo "\$*" >> "$CTL/add_calls"
  n=\$(cat "$CTL/add_fail_n" 2>/dev/null || echo 0)
  if [ "\$n" -gt 0 ]; then echo \$((n-1)) > "$CTL/add_fail_n"; echo "fatal: unable to stat 'state/HOLD_xlite': No such file or directory" >&2; exit 128; fi
fi
exec "$REALGIT" "\$@"
EOF
  chmod +x "$BIN/git"
}
sync_run(){ ( cd "$HOME_" && env -i HOME="$HOME_" PATH="$BIN:/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin" TMPDIR="$W" OVN_GIT_SYNC_RETRY_SLEEP=0 \
    GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null "$@" bash "$R/ovn_git_sync.sh" > "$W/out.log" 2>&1 ); RC=$?; }
head_(){ git -C "$R" rev-parse HEAD; }
remote_(){ git -C "$BARE" rev-parse overnight-live; }
adds(){ [ -f "$CTL/add_calls" ] && wc -l < "$CTL/add_calls" | tr -d ' ' || echo 0; }
alerts(){ if [ -f "$R/state/alerts.log" ]; then grep -c -F -- "$1" "$R/state/alerts.log" || true; else echo 0; fi; }
age_marker(){ python3 -c "import os,sys,time; t=time.time()-float(sys.argv[2])*3600; os.utime(sys.argv[1],(t,t))" "$R/state/git_sync_last_ok" "$1"; }
tracked(){ git -C "$R" ls-files | grep -c -x -F -- "$1"; }

run_suite(){  # $1=label $2=script
  SUITE="$1"
  # ---- A: a transient stat failure on the first add -> retried once -> committed, pushed, marker written ----
  build "$2"; echo v2 > "$R/scripts/a.sh"; echo 1 > "$CTL/add_fail_n"; h0="$(head_)"
  sync_run
  ok "A transient 'unable to stat' on the first add: retried, then committed and pushed (new HEAD == origin overnight-live), exit 0" "[ $RC -eq 0 ] && [ \"\$(head_)\" != '$h0' ] && [ \"\$(head_)\" = \"\$(remote_)\" ]"
  ok "A: exactly two add attempts (one retry, no more)" "[ \"\$(adds)\" = 2 ]"
  ok "A: state/git_sync_last_ok written, no failure alert" "[ -f '$R/state/git_sync_last_ok' ] && [ \"\$(alerts 'git add failed')\" = 0 ]"
  # ---- B: persistent failure -> no commit, no marker, an alert line, exit 1, still only one retry ----
  build "$2"; echo v2 > "$R/scripts/a.sh"; echo 99 > "$CTL/add_fail_n"; h0="$(head_)"
  sync_run
  ok "B persistent add failure: exit 1, no commit, nothing pushed" "[ $RC -eq 1 ] && [ \"\$(head_)\" = '$h0' ] && [ \"\$(remote_)\" = '$h0' ]"
  ok "B: no success marker is written" "[ ! -f '$R/state/git_sync_last_ok' ]"
  ok "B: a 'warn | git_sync | git add failed' line is appended to state/alerts.log with the git error" "[ \"\$(alerts 'warn | git_sync | git add failed')\" = 1 ] && [ \"\$(alerts 'unable to stat')\" = 1 ]"
  ok "B: exactly two add attempts (retry once, not a loop)" "[ \"\$(adds)\" = 2 ]"
  # a non-stat failure is not retried
  build "$2"; echo v2 > "$R/scripts/a.sh"; sed -i.bak 's/unable to stat/some other failure/' "$BIN/git" && rm -f "$BIN/git.bak"; echo 99 > "$CTL/add_fail_n"
  sync_run
  ok "B2 a non-stat add failure is not retried (1 attempt) but still alerts and exits 1" "[ $RC -eq 1 ] && [ \"\$(adds)\" = 1 ] && [ \"\$(alerts 'git add failed')\" = 1 ]"
  # ---- C: marker age ----
  build "$2"; touch "$R/state/git_sync_last_ok"; age_marker 25
  sync_run
  ok "C marker 25 h old -> a stale-sync warn line in alerts.log" "[ \"\$(alerts 'warn | git_sync | last successful sync was 25h ago')\" = 1 ]"
  ok "C: the no-op cycle itself succeeds, so the marker is refreshed (age < 1 h)" "[ $RC -eq 0 ] && [ -n \"\$(find '$R/state/git_sync_last_ok' -mmin -5)\" ]"
  build "$2"; touch "$R/state/git_sync_last_ok"; age_marker 1
  sync_run
  ok "C marker 1 h old -> no stale alert" "[ \"\$(alerts 'git_sync')\" = 0 ]"
  build "$2"; touch "$R/state/git_sync_last_ok"; age_marker 25; echo 99 > "$CTL/add_fail_n"; echo v2 > "$R/scripts/a.sh"
  sync_run
  ok "C stale marker + failing sync: stale alert AND failure alert, marker stays old" "[ \"\$(alerts 'last successful sync was 25h ago')\" = 1 ] && [ \"\$(alerts 'git add failed')\" = 1 ] && [ -z \"\$(find '$R/state/git_sync_last_ok' -mmin -5)\" ]"
  build "$2"; sync_run
  ok "C no marker yet (first run after deploy / after a week of failures) -> one 'no successful sync recorded' warn, then the marker exists" "[ \"\$(alerts 'no successful sync recorded yet')\" = 1 ] && [ -f '$R/state/git_sync_last_ok' ]"
  build "$2"; touch "$R/state/git_sync_last_ok"; age_marker 25
  sync_run OVN_GIT_SYNC_STALE_H=48
  ok "C OVN_GIT_SYNC_STALE_H=48 raises the stale threshold (25 h is fine)" "[ \"\$(alerts 'git_sync')\" = 0 ]"
  # ---- D: what gets added ----
  build "$2"
  echo v2 > "$R/scripts/a.sh"; echo new > "$R/scripts/new_tool.sh"; echo new > "$R/qa/new_gate.py"; echo new > "$R/new_root.py"; echo '{"a":2}' > "$R/tasks.json"
  mkdir -p "$R/scripts/__pycache__" "$R/logs" "$R/worktrees/w" "$R/repos/emb" "$R/state"
  echo x > "$R/scripts/__pycache__/m.pyc"; echo x > "$R/scripts/._junk"; echo x > "$R/logs/run.log"; echo x > "$R/worktrees/w/f.txt"; echo x > "$R/state/HOLD_xlite"; echo x > "$R/random.dat"
  ( cd "$R/repos/emb" && git init -q && echo e > e.txt && git add e.txt && git commit -q -m e ) >/dev/null 2>&1
  sync_run
  ok "D modified and new files under scripts/ qa/ and the root *.py / tracked tasks.json are synced" "[ $RC -eq 0 ] && [ \"\$(tracked scripts/new_tool.sh)\" = 1 ] && [ \"\$(tracked qa/new_gate.py)\" = 1 ] && [ \"\$(tracked new_root.py)\" = 1 ] && [ \"\$(git -C '$R' show HEAD:tasks.json | grep -c '\"a\":2')\" = 1 ] && [ \"\$(head_)\" = \"\$(remote_)\" ]"
  ok "D state/ logs/ repos/ worktrees/ are never added" "[ \"\$(git -C '$R' ls-files state logs repos worktrees | wc -l | tr -d ' ')\" = 0 ]"
  ok "D __pycache__, ._* junk and an untracked root file that is not *.sh/*.py/*.md stay out" "[ \"\$(git -C '$R' ls-files | grep -c -E '__pycache__|\\._junk|random\\.dat')\" = 0 ]"
  ok "D the add used an explicit pathspec (never a bare 'add -A'), and never named state/logs/repos/worktrees" \
     "[ \"\$(grep -c -E 'add -A -- ' '$CTL/add_calls')\" = 1 ] && [ \"\$(grep -c -E ' (state|logs|repos|worktrees)( |\$)' '$CTL/add_calls')\" = 0 ]"
  ok "D no 'adding embedded git repository' warning (the embedded repo is never scanned)" "[ \"\$(grep -c 'embedded git repository' '$W/out.log')\" = 0 ]"
  # ---- D2: .gitignore'd named paths must not fail the whole sync (`git add` exits 1 on an ignored pathspec) ----
  build "$2"
  mkdir -p "$R/docs" "$R/tools"; echo x > "$R/docs/readme.txt"; echo x > "$R/ignored_root.sh"; echo new > "$R/scripts/real_change.sh"
  printf 'docs/\nignored_root.sh\n' > "$R/.gitignore"
  sync_run
  ok "D2 an ignored dir (docs/) and an ignored root *.sh do not break the sync: exit 0, other changes committed and pushed, marker written" "[ $RC -eq 0 ] && [ \"\$(tracked scripts/real_change.sh)\" = 1 ] && [ \"\$(head_)\" = \"\$(remote_)\" ] && [ -f '$R/state/git_sync_last_ok' ] && [ \"\$(alerts 'git add failed')\" = 0 ]"
  ok "D2 the ignored paths themselves stay out of the commit" "[ \"\$(tracked docs/readme.txt)\" = 0 ] && [ \"\$(tracked ignored_root.sh)\" = 0 ]"
  # an ignored dir that ALREADY has tracked files keeps syncing its tracked changes
  build "$2"; mkdir -p "$R/docs"; echo d1 > "$R/docs/t.md"; git -C "$R" add -f docs/t.md >/dev/null 2>&1; git -C "$R" commit -q -m docs >/dev/null 2>&1; git -C "$R" push -q origin overnight-live >/dev/null 2>&1
  printf 'docs/\n' > "$R/.gitignore"; echo d2 > "$R/docs/t.md"; echo untracked > "$R/docs/u.md"
  sync_run
  ok "D2 an ignored dir with tracked files: its tracked change is synced (exit 0), its untracked files are not" "[ $RC -eq 0 ] && [ \"\$(git -C '$R' show HEAD:docs/t.md)\" = d2 ] && [ \"\$(tracked docs/u.md)\" = 0 ]"
  # ---- D3: nested git repos under the named dirs are never committed as a gitlink ----
  build "$2"; mkdir -p "$R/tools/emb"; ( cd "$R/tools/emb" && git init -q && echo e > e.txt && git add e.txt && git commit -q -m e ) >/dev/null 2>&1
  echo t > "$R/tools/real_tool.py"; echo v2 > "$R/scripts/a.sh"
  sync_run
  ok "D3 a nested repo (tools/emb) is excluded: exit 0, tools/real_tool.py synced, nothing of tools/emb in the commit (no gitlink)" "[ $RC -eq 0 ] && [ \"\$(tracked tools/real_tool.py)\" = 1 ] && [ \"\$(git -C '$R' ls-files tools/emb | wc -l | tr -d ' ')\" = 0 ] && [ \"\$(git -C '$R' ls-files -s | grep -c '^160000')\" = 0 ]"
  # ---- D4: deletions are synced ----
  build "$2"; mkdir -p "$R/tools"; echo t > "$R/tools/t.py"; echo g > "$R/gone.sh"; echo g > "$R/gone_data.json"
  git -C "$R" add -A >/dev/null 2>&1; git -C "$R" commit -q -m more >/dev/null 2>&1; git -C "$R" push -q origin overnight-live >/dev/null 2>&1
  rm -f "$R/gone.sh" "$R/gone_data.json"; rm -rf "$R/tools"; echo v2 > "$R/scripts/a.sh"
  sync_run
  ok "D4 a deleted tracked root *.sh, a deleted tracked root data file and a whole deleted tracked dir (tools/) are removed from the mirror too" "[ $RC -eq 0 ] && [ \"\$(tracked gone.sh)\" = 0 ] && [ \"\$(tracked gone_data.json)\" = 0 ] && [ \"\$(tracked tools/t.py)\" = 0 ] && [ \"\$(git -C '$R' status --porcelain | grep -c '^ D')\" = 0 ] && [ \"\$(head_)\" = \"\$(remote_)\" ]"
  # ---- E: no-op ----
  sync_run; h1="$(head_)"; sync_run
  ok "E no-op cycle: no new commit, exit 0, marker fresh" "[ $RC -eq 0 ] && [ \"\$(head_)\" = '$h1' ] && [ -n \"\$(find '$R/state/git_sync_last_ok' -mmin -5)\" ]"
  # ---- F: commit ok but push fails ----
  build "$2"; echo v2 > "$R/scripts/a.sh"; git -C "$R" remote set-url origin "$W/does-not-exist.git"
  sync_run
  ok "F push failure: exit 1, a 'git push' warn line, NO success marker (a local-only commit is not a sync)" "[ $RC -eq 1 ] && [ \"\$(alerts 'git push origin overnight-live failed')\" = 1 ] && [ ! -f '$R/state/git_sync_last_ok' ]"
  # ---- F2: a persistent push failure must not turn into a fresh marker on the NEXT (idle, nothing-to-commit) cycle ----
  ok "F2 the failed-push commit is still local-only (HEAD != origin), as the next cycle starts" "[ \"\$(head_)\" != \"\$(remote_)\" ]"
  sync_run
  ok "F2 idle rerun while the remote is still down: exit 1 (not 0), the push is retried and alerted AGAIN (2 push alerts in total), still NO marker" "[ $RC -eq 1 ] && [ \"\$(alerts 'git push origin overnight-live failed')\" = 2 ] && [ ! -f '$R/state/git_sync_last_ok' ]"
  ok "F2: nothing was pushed (origin still behind HEAD) and nothing new was committed" "[ \"\$(git -C '$R' rev-list --count origin/overnight-live..HEAD)\" = 1 ] && [ \"\$(git -C '$R' log --oneline | wc -l | tr -d ' ')\" = 2 ]"
  sync_run
  ok "F2: a third idle cycle still fails and still has no marker (it never becomes 'ok' by repetition)" "[ $RC -eq 1 ] && [ \"\$(alerts 'git push origin overnight-live failed')\" = 3 ] && [ ! -f '$R/state/git_sync_last_ok' ]"
  git -C "$R" remote set-url origin "$BARE"
  sync_run
  ok "F2 remote back: the idle cycle pushes the stranded commit (HEAD == origin), exit 0 and ONLY now the marker is written" "[ $RC -eq 0 ] && [ \"\$(head_)\" = \"\$(remote_)\" ] && [ -f '$R/state/git_sync_last_ok' ]"
  # stale marker + idle push failure: the marker must stay old so the 24 h stale alert keeps firing
  build "$2"; echo v2 > "$R/scripts/a.sh"; git -C "$R" remote set-url origin "$W/does-not-exist.git"; sync_run
  touch "$R/state/git_sync_last_ok"; age_marker 25
  sync_run
  ok "F2 stale marker (25 h) + idle push failure: exit 1, the marker is NOT refreshed (still >= 25 h old) and the stale-sync warn fires" "[ $RC -eq 1 ] && [ -z \"\$(find '$R/state/git_sync_last_ok' -mmin -5)\" ] && [ \"\$(alerts 'last successful sync was 25h ago')\" = 1 ]"
  # no remote-tracking ref at all (never pushed from this clone): nothing staged still means "unknown -> push to find out", never a free marker
  build "$2"; git -C "$R" update-ref -d refs/remotes/origin/overnight-live; git -C "$R" remote set-url origin "$W/does-not-exist.git"
  sync_run
  ok "F2 no origin/overnight-live tracking ref and the remote is down: exit 1, no marker" "[ $RC -eq 1 ] && [ ! -f '$R/state/git_sync_last_ok' ]"
  # ---- G: kill switch ----
  build "$2"; echo v2 > "$R/scripts/a.sh"; echo x > "$R/random.dat"
  sync_run OVN_GIT_SYNC_LEGACY=1
  ok "G OVN_GIT_SYNC_LEGACY=1 restores the old behaviour: bare 'add -A' (the untracked root file is committed)" "[ \"\$(grep -c -x 'add -A' '$CTL/add_calls')\" = 1 ] && [ \"\$(tracked random.dat)\" = 1 ]"
}

run_suite "real" "$G"
[ "$F" -eq 0 ] && echo "  ok   real script: all scenario assertions hold"

mutate(){  # $1=label $2=old $3=new : the suite against the mutant must produce at least one FAIL line
  OLD="$2" NEW="$3" python3 - "$G" "$T/mutant.sh" <<'PY'
import os, sys
s = open(sys.argv[1]).read()
if s.count(os.environ["OLD"]) != 1:
    sys.exit("mutation anchor not found exactly once: " + os.environ["OLD"])
open(sys.argv[2], "w").write(s.replace(os.environ["OLD"], os.environ["NEW"]))
PY
  [ $? -eq 0 ] || { F=$((F+1)); echo "  FAIL: mutation '$1' could not be applied"; return; }
  local out; out="$(run_suite "mutant" "$T/mutant.sh" 2>&1)"
  if [ "$(printf '%s\n' "$out" | grep -c 'FAIL: mutant')" -gt 0 ]; then P=$((P+1)); echo "  ok   mutation caught: $1"; else F=$((F+1)); echo "  FAIL: mutation NOT caught: $1"; fi
}
mutate "no retry on a stat failure" '"$rc" -ne 0 ] && grep -q "unable to stat" "$ERR"' '"$rc" -ne 0 ] && false'
mutate "add failure swallowed (the 7-day silent failure)" 'if [ "$rc" -ne 0 ]; then
  alert' 'if false; then
  alert'
mutate "stale-marker check removed" '[ "$age_h" -ge "${OVN_GIT_SYNC_STALE_H:-24}" ] &&' 'false &&'
mutate "state/ added to the pathspec" 'SRC_DIRS="scripts qa' 'SRC_DIRS="state scripts qa'
mutate "ignored untracked named paths not filtered (git add exits 1 on them)" ' 2>/dev/null && return 1' ' 2>/dev/null && return 0'
mutate "ignored dir with tracked files added with -A (exits 1) instead of add -u" 'then upd+=("$1"); return 1; fi' 'then return 0; fi'
mutate "nested repos not excluded (committed as a gitlink)" 'excl+=(":(exclude)$(dirname "$g")")' ':'
mutate "tracked root files only added when they still exist (deletions never synced)" 'while IFS= read -r f; do [ -n "$f" ] && paths+=("$f"); done' 'while IFS= read -r f; do [ -n "$f" ] && [ -f "$f" ] && paths+=("$f"); done'
mutate "tracked dirs that vanished are dropped (dir deletions never synced)" '  if tracked_any "$1"; then' '  if false; then'
mutate "marker written even when the push failed" 'local commit(s) not on origin)"; exit 1; }' 'local commit(s) not on origin)"; touch "$MARK"; exit 1; }'
mutate "idle cycle does not retry an unpushed commit (the reviewed defect: failed push -> next idle run writes a fresh marker)" 'if unpushed; then push_or_fail; fi' ':'
mutate "unpushed() always false" "  [ \"\$(git rev-list --count refs/remotes/origin/overnight-live..HEAD 2>/dev/null || echo 1)\" != 0 ]
}" "  false
}"
mutate "idle retry ignores a failed push and still touches the marker" 'if unpushed; then push_or_fail; fi' 'if unpushed; then git push -q origin overnight-live || alert "x"; fi'
mutate "bare add -A again" 'git -c advice.addEmbeddedRepo=false add -A -- ${paths[@]+"${paths[@]}"} "${excl[@]}"' 'git add -A'

echo "git_sync_failure: $P passed, $F failed"
[ "$F" -eq 0 ]
