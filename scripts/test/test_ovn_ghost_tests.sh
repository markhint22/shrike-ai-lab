#!/usr/bin/env bash
# Tests for scripts/ovn_ghost_tests.py (one-time relocation of ghost tests: test_*.py under iptv-backend/app/{jobs,routers,services} that pytest never collected).
# Real git only: a bare "origin", the fleet's live clone (must never be touched), an `overnight/feature` branch. pytest comes from a python that has it (OVN_GHOST_PY).
# Scenarios: dry run (nothing changes, cmp), real run (pass kept + committed, fail removed + listed, name collision -> _relocated, non-ghost untouched, live clone untouched,
# no worktree left), second run no-op, PAUSED skips, a push race (non-ff rejection -> fetch, rebase, retry ONCE), a persistently rejected push (nothing pushed, exactly 2 attempts).
# Environment-failure safety (review defects): a python without pytest / a broken env must NOT delete anything (preflight abort, UNDECIDED classes, half/none-passed abort).
# Relocation safety (round-3 review): a ghost that fails ONLY because it was moved (Path(__file__)-relative target, a path computed from its own frame) must be left in place, never
# deleted; a __file__-user that passes after the move (it would silently check another tree) is left in place too; a ghost that is inconclusive in place is never deleted.
# Every scenario is also run against a MUTANT of the script (one piece of logic broken) and must FAIL there.
# Speed: scenario+mutant pairs run as parallel jobs (every fixture has its own unique repo name, so /tmp/wt-ghost-<repo>.* checks cannot see another job's worktree);
# results are printed in declaration order. GHOST_TEST_JOBS (default 6) caps the parallelism.
# No `x | grep -q` under pipefail (pipefail is OFF; counts use grep -c / case), no kill -0, no greps on comments, paths are `pwd -P` normalised.
HERE="$(cd "$(dirname "$0")" && pwd -P)"; ROOT="$(cd "$HERE/../.." && pwd -P)"
GH="$ROOT/scripts/ovn_ghost_tests.py"; LIBWT="$ROOT/scripts/lib_worktree.sh"
PY3="$(command -v python3.12 || command -v python3)"
pass=0; fail=0
ok(){ if [ "$2" = "1" ]; then pass=$((pass+1)); echo "  ok   $1"; else fail=$((fail+1)); echo "  FAIL $1"; fi; }
find_pytest_py(){
  local c
  for c in "${OVN_TEST_TOOLS_PY:-}" "$PY3" "$(command -v python3)" "$HOME/overnight-queue/repos/iptv_apps/iptv-backend/.venv/bin/python" "$HOME/aider-venv/bin/python"; do
    [ -n "$c" ] && [ -x "$c" ] && "$c" -m pytest --version >/dev/null 2>&1 && { printf '%s' "$c"; return 0; }
  done
  return 1
}
PYT="$(find_pytest_py)" || PYT=""
if [ -z "$PYT" ]; then
  if [ -n "${OVN_REQUIRE_TOOLS:-}" ]; then echo "  FAIL pytest is required (OVN_REQUIRE_TOOLS set) but no python with pytest was found"; echo "0 passed, 1 failed"; exit 1; fi
  echo "  SKIP test_ovn_ghost_tests: pytest is genuinely absent here (set OVN_REQUIRE_TOOLS=1 to make that a failure)"; echo "0 passed, 0 failed"; exit 0
fi
T="$(mktemp -d)"; T="$(cd "$T" && pwd -P)"
# remove ONLY the temporary worktrees of the given fixture dirs' clones (never a /tmp/wt-ghost-* glob: a real ovn_ghost_tests.py run uses the same prefix at the same time)
rm_ghost_worktrees(){
  local fx c w
  for fx in "$@"; do
    for c in "$fx"/ovn/repos/demo*; do
      [ -d "$c/.git" ] || continue
      git -C "$c" worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p' | while IFS= read -r w; do
        case "$w" in */wt-ghost-demo*) rm -rf "$w";; esac
      done
    done
  done
}
trap 'wait; rm_ghost_worktrees "$T"/fx.*; rm -rf "$T" 2>/dev/null' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0
export PYTEST_DISABLE_PLUGIN_AUTOLOAD=1   # plain fixture tests: skipping third-party plugin discovery halves every pytest start
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
BR=overnight/feature
G(){ git -c advice.detachedHead=false "$@"; }

# ---- fixture: a fresh OVN_DIR + bare origin + live clone per scenario --------------------------------------------------------------------------------
mkfix(){ # scenarios run inside $(...) subshells, so every fixture gets its own mktemp dir (no counter that a subshell would lose)
  F_ROOT="$(mktemp -d "$T/fx.XXXXXX")"; F_REPO="demo${F_ROOT##*.}"; F_OVN="$F_ROOT/ovn"; F_BARE="$F_ROOT/origin.git"; F_CLONE="$F_OVN/repos/$F_REPO"; F_SEED="$F_ROOT/seed"; F_OTHER="$F_ROOT/other"
  mkdir -p "$F_OVN/repos" "$F_OVN/state" "$F_OVN/scripts"; cp "$LIBWT" "$F_OVN/scripts/"
  G init -q --bare "$F_BARE"; G -C "$F_BARE" symbolic-ref HEAD "refs/heads/$BR"
  G clone -q "$F_BARE" "$F_SEED" 2>/dev/null; G -C "$F_SEED" checkout -q -b "$BR"
  mkdir -p "$F_SEED/iptv-backend/app/jobs" "$F_SEED/iptv-backend/app/routers" "$F_SEED/iptv-backend/app/services" "$F_SEED/iptv-backend/app/other" "$F_SEED/iptv-backend/tests"
  printf 'def test_ok():\n    assert 1 + 1 == 2\n' > "$F_SEED/iptv-backend/app/jobs/test_pass.py"
  printf 'def test_bad():\n    assert False\n' > "$F_SEED/iptv-backend/app/jobs/test_fail.py"
  printf 'def test_dup_ghost():\n    assert True\n' > "$F_SEED/iptv-backend/app/routers/test_dup.py"
  printf 'def test_svc():\n    assert "a".upper() == "A"\n' > "$F_SEED/iptv-backend/app/services/test_svc.py"
  printf 'def helper():\n    return 1\n' > "$F_SEED/iptv-backend/app/jobs/helper.py"
  printf 'def test_not_a_ghost():\n    assert True\n' > "$F_SEED/iptv-backend/app/other/test_notghost.py"
  printf 'def test_dup_real():\n    assert True\n' > "$F_SEED/iptv-backend/tests/test_dup.py"
  printf 'def test_real():\n    assert True\n' > "$F_SEED/iptv-backend/tests/test_real.py"
  G -C "$F_SEED" add -A; G -C "$F_SEED" commit -q -m "init"; G -C "$F_SEED" push -q origin "$BR" 2>/dev/null
  G clone -q "$F_BARE" "$F_CLONE" 2>/dev/null; G -C "$F_CLONE" checkout -q "$BR"
}
ghost(){ # script args...  -> $OUT, $RC
  local s="$1"; shift
  OUT="$(OVN_DIR="$F_OVN" OVN_GHOST_PY="${GHOST_PY:-$PYT}" GHOST_RACE_CLONE="${F_OTHER:-/nonexistent}" "$PY3" "$s" run "$F_REPO" "$@" 2>&1)"; RC=$?
  refresh_rf
}
remote_sha(){ G -C "$F_BARE" rev-parse "refs/heads/$BR"; }
# remote_has answers from one listing of the remote branch taken after every ghost run / seed commit (a spawn per assertion is what made this suite slow)
refresh_rf(){ RF="$(G -C "$F_BARE" ls-tree -r --name-only "refs/heads/$BR" 2>/dev/null)"; }
remote_has(){ case "
$RF
" in *"
$1
"*) echo 1;; *) echo 0;; esac; }
nwt(){ G -C "$F_CLONE" worktree list | wc -l | tr -d ' '; }
b01(){ [ "$1" = "1" ] && echo 1 || echo 0; }

# ---- scenarios: each returns 1 (all assertions hold) or 0, given the script path -------------------------------------------------------------------
sc_dry(){
  mkfix; local before_remote before_clone after_clone ls1 ls2
  before_remote="$(remote_sha)"; before_clone="$(G -C "$F_CLONE" rev-parse HEAD)"; ls1="$(G -C "$F_CLONE" ls-files | sort | tr '\n' ' ')"
  G -C "$F_BARE" for-each-ref > "$F_ROOT/refs.before"
  ghost "$1" --dry-run
  G -C "$F_BARE" for-each-ref > "$F_ROOT/refs.after"
  after_clone="$(G -C "$F_CLONE" rev-parse HEAD)"; ls2="$(G -C "$F_CLONE" ls-files | sort | tr '\n' ' ')"
  local plans; plans="$(printf '%s\n' "$OUT" | grep -c '^  PLAN git mv ')"
  [ "$RC" = 0 ] && [ "$plans" = 4 ] && [ "$(remote_sha)" = "$before_remote" ] && cmp -s "$F_ROOT/refs.before" "$F_ROOT/refs.after" && [ "$after_clone" = "$before_clone" ] \
    && [ "$ls1" = "$ls2" ] && [ -z "$(G -C "$F_CLONE" status --porcelain)" ] && [ "$(nwt)" = 1 ] \
    && case "$OUT" in *"app/routers/test_dup.py -> iptv-backend/tests/test_dup_relocated.py"*) true;; *) false;; esac && echo 1 || { echo "$OUT" >&2; echo 0; }
}
sc_real(){
  mkfix; local live_head; live_head="$(G -C "$F_CLONE" rev-parse HEAD)"
  local real_blob; real_blob="$(G -C "$F_BARE" rev-parse "refs/heads/$BR:iptv-backend/tests/test_real.py")"
  local notg_blob; notg_blob="$(G -C "$F_BARE" rev-parse "refs/heads/$BR:iptv-backend/app/other/test_notghost.py")"
  local help_blob; help_blob="$(G -C "$F_BARE" rev-parse "refs/heads/$BR:iptv-backend/app/jobs/helper.py")"
  ghost "$1"
  local subj body; subj="$(G -C "$F_BARE" log --format=%s "refs/heads/$BR")"; body="$(G -C "$F_BARE" log --format=%b "refs/heads/$BR")"
  [ "$RC" = 0 ] \
    && [ "$(remote_has iptv-backend/tests/test_pass.py)" = 1 ] && [ "$(remote_has iptv-backend/tests/test_svc.py)" = 1 ] && [ "$(remote_has iptv-backend/tests/test_dup_relocated.py)" = 1 ] \
    && [ "$(remote_has iptv-backend/app/jobs/test_pass.py)" = 0 ] && [ "$(remote_has iptv-backend/app/jobs/test_fail.py)" = 0 ] && [ "$(remote_has iptv-backend/tests/test_fail.py)" = 0 ] \
    && [ "$(remote_has iptv-backend/app/routers/test_dup.py)" = 0 ] && [ "$(remote_has iptv-backend/app/services/test_svc.py)" = 0 ] \
    && [ "$(G -C "$F_BARE" rev-parse "refs/heads/$BR:iptv-backend/tests/test_real.py")" = "$real_blob" ] && [ "$(G -C "$F_BARE" rev-parse "refs/heads/$BR:iptv-backend/tests/test_dup.py")" != "" ] \
    && [ "$(G -C "$F_BARE" rev-parse "refs/heads/$BR:iptv-backend/app/other/test_notghost.py")" = "$notg_blob" ] && [ "$(G -C "$F_BARE" rev-parse "refs/heads/$BR:iptv-backend/app/jobs/helper.py")" = "$help_blob" ] \
    && [ "$(printf '%s\n' "$subj" | grep -c '^chore(tests): relocate ghost test test_pass.py into the collected dir$')" = 1 ] \
    && [ "$(printf '%s\n' "$subj" | grep -c '^chore(tests): drop 1 ghost tests that never ran$')" = 1 ] \
    && [ "$(printf '%s\n' "$body" | grep -c 'iptv-backend/app/jobs/test_fail.py')" = 1 ] \
    && [ "$(G -C "$F_CLONE" rev-parse HEAD)" = "$live_head" ] && [ -z "$(G -C "$F_CLONE" status --porcelain)" ] && [ "$(nwt)" = 1 ] \
    && [ -z "$(ls -d /tmp/wt-ghost-$F_REPO.* 2>/dev/null)" ] && echo 1 || { echo "$OUT" >&2; echo 0; }
}
sc_second_run(){
  mkfix; ghost "$1"; local after1; after1="$(remote_sha)"; ghost "$1"
  [ "$RC" = 0 ] && [ "$(remote_sha)" = "$after1" ] && case "$OUT" in *"nothing to do"*) true;; *) false;; esac && echo 1 || { echo "$OUT" >&2; echo 0; }
}
sc_paused(){
  mkfix; touch "$F_OVN/state/PAUSED"; local b; b="$(remote_sha)"; ghost "$1"
  [ "$RC" = 1 ] && [ "$(remote_sha)" = "$b" ] && case "$OUT" in *"state/PAUSED exists - abort, nothing done"*) true;; *) false;; esac && [ "$(nwt)" = 1 ] && [ -z "$(ls -d /tmp/wt-ghost-$F_REPO.* 2>/dev/null)" ] && echo 1 || { echo "$OUT" >&2; echo 0; }
}
sc_paused_mid(){
  mkfix
  # PAUSED appears while the work is running (a ghost test creates it): the script must abort before the push and leave the remote alone
  printf 'import os\n\n\ndef test_pause_the_fleet():\n    open(os.path.join(os.environ["OVN_DIR"], "state", "PAUSED"), "w").close()\n' > "$F_SEED/iptv-backend/app/jobs/test_pause_trigger.py"
  G -C "$F_SEED" add -A; G -C "$F_SEED" commit -q -m "add pause trigger"; G -C "$F_SEED" push -q origin "$BR" 2>/dev/null
  local b; b="$(remote_sha)"; ghost "$1"
  [ "$RC" = 1 ] && [ "$(remote_sha)" = "$b" ] && case "$OUT" in *"state/PAUSED appeared"*) true;; *) false;; esac && [ "$(nwt)" = 1 ] && echo 1 || { echo "$OUT" >&2; echo 0; }
}
sc_race(){
  mkfix
  # a ghost test that, WHEN IT RUNS (inside the script's work phase, after its fetch), publishes the racing commit: the script's first push is then a genuine
  # non-fast-forward rejection (a force push would silently wipe the racing commit - the assertion that it survives is what pins `non-force`)
  printf 'import os\nimport subprocess\n\n\ndef test_publish_race():\n    subprocess.run(["git", "-C", os.environ["GHOST_RACE_CLONE"], "push", "-q", "origin", "overnight/feature"], check=True)\n' > "$F_SEED/iptv-backend/app/jobs/test_race_trigger.py"
  G -C "$F_SEED" add -A; G -C "$F_SEED" commit -q -m "add race trigger"; G -C "$F_SEED" push -q origin "$BR" 2>/dev/null
  G clone -q "$F_BARE" "$F_OTHER" 2>/dev/null; G -C "$F_OTHER" checkout -q "$BR"
  printf 'racing change\n' > "$F_OTHER/RACE.txt"; G -C "$F_OTHER" add -A; G -C "$F_OTHER" commit -q -m "race: someone else pushed first"
  ghost "$1"
  local subj; subj="$(G -C "$F_BARE" log --format=%s "refs/heads/$BR")"
  [ "$RC" = 0 ] && [ "$(remote_has RACE.txt)" = 1 ] && [ "$(remote_has iptv-backend/tests/test_pass.py)" = 1 ] && [ "$(remote_has iptv-backend/tests/test_race_trigger.py)" = 1 ] \
    && [ "$(printf '%s\n' "$subj" | grep -c '^race: someone else pushed first$')" = 1 ] && [ "$(printf '%s\n' "$subj" | grep -c '^chore(tests): relocate ghost test test_pass.py')" = 1 ] \
    && case "$OUT" in *"rejected once"*) true;; *) false;; esac && [ "$(nwt)" = 1 ] && echo 1 || { echo "$OUT" >&2; echo 0; }
}
sc_rejected(){
  mkfix
  cat > "$F_CLONE/.git/hooks/pre-push" <<EOF
#!/bin/sh
echo x >> "$F_ROOT/reject.count"
exit 1
EOF
  chmod +x "$F_CLONE/.git/hooks/pre-push"
  local b; b="$(remote_sha)"; ghost "$1"
  local attempts; attempts="$(wc -l < "$F_ROOT/reject.count" 2>/dev/null | tr -d ' ')"
  [ "$RC" = 1 ] && [ "$attempts" = 2 ] && [ "$(remote_sha)" = "$b" ] && case "$OUT" in *"nothing pushed"*) true;; *) false;; esac && [ "$(nwt)" = 1 ] && echo 1 || { echo "attempts=$attempts" >&2; echo "$OUT" >&2; echo 0; }
}

seed_commit(){ G -C "$F_SEED" add -A; G -C "$F_SEED" commit -q -m "$1"; G -C "$F_SEED" push -q origin "$BR" 2>/dev/null; refresh_rf; }
add_ghosts_env(){ # a ghost that fails only because the environment lacks a module, one that does not even collect (SyntaxError, pytest rc 2)
  printf 'def test_needs_env():\n    import module_that_does_not_exist_xyz\n' > "$F_SEED/iptv-backend/app/jobs/test_noenv.py"
  printf 'def test_broken(:\n' > "$F_SEED/iptv-backend/app/jobs/test_collecterr.py"
}
sc_badpy(){ # a python without pytest: nothing may be deleted or pushed (the review reproduced a push deleting every ghost)
  mkfix; printf '#!/bin/sh\necho "No module named pytest" >&2\nexit 1\n' > "$F_ROOT/fakepy"; chmod +x "$F_ROOT/fakepy"; GHOST_PY="$F_ROOT/fakepy"
  local b; b="$(remote_sha)"; ghost "$1"
  [ "$RC" = 1 ] && [ "$(remote_sha)" = "$b" ] && case "$OUT" in *"PREFLIGHT failed"*) true;; *) false;; esac && [ "$(printf '%s\n' "$OUT" | grep -c 'DROP')" = 0 ] \
    && [ "$(remote_has iptv-backend/app/jobs/test_pass.py)" = 1 ] && [ "$(remote_has iptv-backend/app/jobs/test_fail.py)" = 1 ] && [ "$(nwt)" = 1 ] && echo 1 || { echo "$OUT" >&2; echo 0; }
}
sc_envfail(){ # preflight passes (collect-only delegates to the real pytest) but every ghost run dies on a missing module: UNDECIDED, nothing deleted, nothing pushed
  mkfix; printf '#!/bin/sh\ncase "$*" in *--collect-only*) exec "%s" "$@";; esac\necho "E   ModuleNotFoundError: No module named sqlalchemy"\nexit 1\n' "$PYT" > "$F_ROOT/fakepy"; chmod +x "$F_ROOT/fakepy"; GHOST_PY="$F_ROOT/fakepy"
  local b; b="$(remote_sha)"; ghost "$1"
  [ "$RC" = 0 ] && [ "$(remote_sha)" = "$b" ] && [ "$(printf '%s\n' "$OUT" | grep -c '^  UNDECIDED ')" = 4 ] && [ "$(printf '%s\n' "$OUT" | grep -c '^  DROP ')" = 0 ] \
    && [ "$(remote_has iptv-backend/app/jobs/test_fail.py)" = 1 ] && [ "$(nwt)" = 1 ] && echo 1 || { echo "$OUT" >&2; echo 0; }
}
sc_classify(){ # real pytest: pass -> kept, assertion failure -> deleted, env error (rc 1 + ModuleNotFoundError) and collection error (rc 2) -> left where they are
  mkfix; add_ghosts_env; seed_commit "env-sensitive ghosts"
  ghost "$1"
  [ "$RC" = 0 ] && [ "$(remote_has iptv-backend/tests/test_pass.py)" = 1 ] && [ "$(remote_has iptv-backend/app/jobs/test_fail.py)" = 0 ] && [ "$(remote_has iptv-backend/tests/test_fail.py)" = 0 ] \
    && [ "$(remote_has iptv-backend/app/jobs/test_noenv.py)" = 1 ] && [ "$(remote_has iptv-backend/app/jobs/test_collecterr.py)" = 1 ] \
    && [ "$(remote_has iptv-backend/tests/test_noenv.py)" = 0 ] && [ "$(remote_has iptv-backend/tests/test_collecterr.py)" = 0 ] \
    && [ "$(printf '%s\n' "$OUT" | grep -c '^  UNDECIDED ')" = 2 ] && [ "$(printf '%s\n' "$OUT" | grep -c '^  DROP ')" = 1 ] && [ "$(nwt)" = 1 ] && echo 1 || { echo "$OUT" >&2; echo 0; }
}
sc_mostfail(){ # more than half of the ghosts would be deleted: that is an environment problem, abort with nothing pushed
  mkfix; local i
  for i in 2 3 4 5 6; do printf 'def test_bad%s():\n    assert False\n' "$i" > "$F_SEED/iptv-backend/app/jobs/test_f$i.py"; done; seed_commit "five more failing ghosts"
  local b; b="$(remote_sha)"; ghost "$1"
  [ "$RC" = 1 ] && [ "$(remote_sha)" = "$b" ] && case "$OUT" in *"ABORT"*) true;; *) false;; esac && [ "$(remote_has iptv-backend/app/jobs/test_f2.py)" = 1 ] && [ "$(nwt)" = 1 ] && echo 1 || { echo "$OUT" >&2; echo 0; }
}
sc_nopass(){ # no ghost passed but one would be deleted (the other two are undecided): abort, nothing pushed
  mkfix; add_ghosts_env
  G -C "$F_SEED" rm -q iptv-backend/app/jobs/test_pass.py iptv-backend/app/routers/test_dup.py iptv-backend/app/services/test_svc.py; seed_commit "only failing/undecided ghosts"
  local b; b="$(remote_sha)"; ghost "$1"
  [ "$RC" = 1 ] && [ "$(remote_sha)" = "$b" ] && case "$OUT" in *"ABORT"*) true;; *) false;; esac && [ "$(remote_has iptv-backend/app/jobs/test_fail.py)" = 1 ] && [ "$(nwt)" = 1 ] && echo 1 || { echo "$OUT" >&2; echo 0; }
}
sc_cleanup_scope(){ # the test's own cleanup removes the fixture's worktrees and NOTHING else under /tmp/wt-ghost-* (a concurrent real run's worktree must survive)
  mkfix; local foreign own; foreign="$(mktemp -d /tmp/wt-ghost-realrun.XXXXXX)"; own="/tmp/wt-ghost-$F_REPO.leftover$$"
  G -C "$F_CLONE" worktree add -q --detach "$own" HEAD 2>/dev/null
  local before_own=0 after_own=1 foreign_ok=0
  [ -d "$own" ] && before_own=1
  rm_ghost_worktrees "$F_ROOT"
  [ -d "$own" ] || after_own=0
  [ -d "$foreign" ] && foreign_ok=1
  rm -rf "$foreign" "$own"
  [ "$before_own" = 1 ] && [ "$after_own" = 0 ] && [ "$foreign_ok" = 1 ] && echo 1 || { echo "own=$before_own/$after_own foreign_ok=$foreign_ok" >&2; echo 0; }
}

# round-3 review: a failure caused by the RELOCATION is not a broken test. Fixtures (services/tmdb.py is the real iptv test_tmdb_logger.py's target):
add_reloc_ghosts(){
  printf 'X = 1\n' > "$F_SEED/iptv-backend/app/services/tmdb.py"
  # the review's exact reproduction shape: passes in app/jobs, fails once moved to tests/ (Path(__file__).parent.parent no longer reaches app/services)
  printf 'from pathlib import Path\n\n\ndef test_target_exists():\n    assert (Path(__file__).parent.parent / "services" / "tmdb.py").exists()\n' > "$F_SEED/iptv-backend/app/jobs/test_tmdb_logger.py"
  # same failure mode WITHOUT the literal __file__ (so only the in-place re-run, not the __file__ rule, can save it)
  printf 'import os\nimport sys\n\n\ndef test_target_exists():\n    here = os.path.dirname(sys._getframe().f_code.co_filename)\n    assert os.path.exists(os.path.join(here, "..", "services", "tmdb.py"))\n' > "$F_SEED/iptv-backend/app/jobs/test_framepath.py"
  # the mirror case: passes both before and after the move, but after the move it would scan a different tree
  printf 'from pathlib import Path\n\n\ndef test_scans_its_parent_tree():\n    assert (Path(__file__).parent.parent).is_dir()\n' > "$F_SEED/iptv-backend/app/jobs/test_mirror.py"
  # fails when relocated (assert False), but is INCONCLUSIVE in place (a collection error there, rc 2): never a deletion
  printf 'import sys\n\nif "/app/" in sys._getframe().f_code.co_filename:\n    raise RuntimeError("cannot be collected in place")\n\n\ndef test_x():\n    assert False\n' > "$F_SEED/iptv-backend/app/jobs/test_inplace_broken.py"
  seed_commit "relocation-sensitive ghosts"
}
sc_reloc(){
  mkfix; add_reloc_ghosts
  ghost "$1"
  local body subj; body="$(G -C "$F_BARE" log --format=%b "refs/heads/$BR")"; subj="$(G -C "$F_BARE" log --format=%s "refs/heads/$BR")"
  [ "$RC" = 0 ] \
    && [ "$(remote_has iptv-backend/app/jobs/test_tmdb_logger.py)" = 1 ] && [ "$(remote_has iptv-backend/tests/test_tmdb_logger.py)" = 0 ] \
    && [ "$(remote_has iptv-backend/app/jobs/test_framepath.py)" = 1 ] && [ "$(remote_has iptv-backend/tests/test_framepath.py)" = 0 ] \
    && [ "$(remote_has iptv-backend/app/jobs/test_mirror.py)" = 1 ] && [ "$(remote_has iptv-backend/tests/test_mirror.py)" = 0 ] \
    && [ "$(remote_has iptv-backend/app/jobs/test_inplace_broken.py)" = 1 ] && [ "$(remote_has iptv-backend/tests/test_inplace_broken.py)" = 0 ] \
    && [ "$(printf '%s\n' "$OUT" | grep -c '^  UNDECIDED .*test_framepath.py.*relocation-sensitive')" = 1 ] \
    && [ "$(printf '%s\n' "$OUT" | grep -c '^  UNDECIDED .*test_tmdb_logger.py')" = 1 ] && [ "$(printf '%s\n' "$OUT" | grep -c '^  UNDECIDED .*test_mirror.py')" = 1 ] \
    && [ "$(printf '%s\n' "$OUT" | grep -c '^  UNDECIDED .*test_inplace_broken.py')" = 1 ] \
    && [ "$(printf '%s\n' "$OUT" | grep -c '^  DROP ')" = 1 ] && [ "$(printf '%s\n' "$body" | grep -c 'iptv-backend/app/jobs/test_fail.py')" = 1 ] \
    && [ "$(printf '%s\n' "$body" | grep -c 'test_tmdb_logger\|test_framepath\|test_mirror\|test_inplace_broken')" = 0 ] \
    && [ "$(printf '%s\n' "$body" | grep -c 'nothing is lost')" = 0 ] \
    && [ "$(remote_has iptv-backend/tests/test_pass.py)" = 1 ] && [ "$(remote_has iptv-backend/app/jobs/test_fail.py)" = 0 ] && [ "$(nwt)" = 1 ] && echo 1 || { echo "$OUT" >&2; echo 0; }
}

# ---- mutants ----------------------------------------------------------------------------------------------------------------------------------------
mutant(){ # old new  -> prints the path of a mutated copy (with lib_worktree.sh beside it); fails when the anchor is missing
  local d; d="$(mktemp -d "$T/mut.XXXXXX")"; cp "$LIBWT" "$d/"
  "$PY3" - "$GH" "$d/ovn_ghost_tests.py" "$1" "$2" <<'PYEOF' || return 1
import sys
src, dst, old, new = sys.argv[1:5]
s = open(src, encoding="utf-8").read()
if old not in s:
    sys.stderr.write("mutation anchor missing: %r\n" % old)
    sys.exit(1)
open(dst, "w", encoding="utf-8").write(s.replace(old, new))
PYEOF
  printf '%s' "$d/ovn_ghost_tests.py"
}
# ---- parallel runner -------------------------------------------------------------------------------------------------------------------------------
# Every check is a job writing its own result file (numbered in declaration order); a finished job touches done.<n>. Throttle: started - done < MAXJ (event based; the sleep only
# paces the poll). Output is assembled in declaration order at the end and the pass/fail counts come from the assembled lines.
MAXJ="${GHOST_TEST_JOBS:-6}"; NJ=0; mkdir -p "$T/res"
slot(){ local started=$NJ done_n; while :; do done_n="$(ls "$T/res" | grep -c '^done\.')"; [ $((started - done_n)) -lt "$MAXJ" ] && return 0; sleep 0.1; done; }
nextres(){ NJ=$((NJ+1)); RES="$T/res/$(printf '%04d' "$NJ")"; }
section(){ nextres; echo "$1" > "$RES.txt"; touch "$T/res/done.$NJ"; }
caught(){ # label scenario old new : real script passes the scenario, the mutant fails it (one background job; the real-script run of a scenario is shared by all checks of it)
  local label="$1" sc="$2" old="$3" new="$4" first=0
  mkdir -p "$T/real"; [ -e "$T/real/$sc.started" ] || { first=1; touch "$T/real/$sc.started"; }
  slot; nextres; local out="$RES.txt" n="$NJ"
  (
    if [ "$first" = 1 ]; then
      r1="$($sc "$GH" 2>/dev/null | tail -1)"; printf '%s' "$r1" > "$T/real/$sc.r"; touch "$T/real/$sc.ok"
    fi
    if m="$(mutant "$old" "$new")"; then r2="$($sc "$m" 2>/dev/null | tail -1)"; else r2=anchor; fi
    while [ ! -e "$T/real/$sc.ok" ]; do sleep 0.1; done        # the first check of this scenario produces the real-script result (an event, not a delay)
    r1="$(cat "$T/real/$sc.r")"
    ok "$label (real script)" "$(b01 "$r1")" > "$out"
    if [ "$r2" = anchor ]; then ok "MUTATION anchor exists for: $label" 0 >> "$out"; else ok "MUTATION caught: $label" "$([ "$r2" = 0 ] && echo 1 || echo 0)" >> "$out"; fi
    touch "$T/res/done.$n"
  ) &
}
single(){ # label scenario : no mutant (one background job)
  local label="$1" sc="$2"; slot; nextres; local out="$RES.txt" n="$NJ"
  ( r1="$($sc 2>/dev/null | tail -1)"; ok "$label" "$(b01 "$r1")" > "$out"; touch "$T/res/done.$n" ) &
}

# longest scenarios first (the parallel runner starts jobs in declaration order); the output keeps this order
section "== a failure caused by the relocation is never a reason to delete (round-3 review)"
caught "a ghost that passes in place but fails relocated (Path(__file__) / frame-path target) is left where it is: nothing moved, nothing deleted, not in the removal commit" sc_reloc '            if verdict0 == "fail":' '            if True:'
caught "a __file__-user is never moved (it would pass after the move while checking a different tree)" sc_reloc '        if location_relative(src_text):' '        if False:'
caught "a ghost that is inconclusive in place (collection error) is never deleted" sc_reloc '            if verdict0 == "fail":' '            if verdict0 != "pass":'
section "== environment failures never delete test code"
caught "a python without pytest: PREFLIGHT aborts (exit 1), nothing deleted or pushed" sc_badpy '    if pre_rc != 0:' '    if False:'
caught "an env error (rc 1 + ModuleNotFoundError) is UNDECIDED, not a deletion" sc_envfail '    if rc == 1 and not ENV_SIGNS.search(output or ""):' '    if rc == 1:'
caught "real pytest: assertion failure deleted; env error and collection error (rc 2) left in place" sc_classify '    if rc == 1 and not ENV_SIGNS.search(output or ""):' '    if rc == 1:'
caught "only pytest rc 1 may delete (rc 2 collection error is undecided)" sc_classify '    if rc == 1 and not ENV_SIGNS.search(output or ""):' '    if rc != 0 and not ENV_SIGNS.search(output or ""):'
caught "more than half of the ghosts failing aborts the run" sc_mostfail 'len(dropped) > MAX_DROP_FRACTION * len(moves)' 'False'
caught "no ghost passed but some would be deleted aborts the run" sc_nopass 'if dropped and (not kept or' 'if dropped and (False or'
section "== push race"
caught "a non-fast-forward rejection: fetch, rebase, retry once; the racing commit survives" sc_race '    if p.returncode != 0:
        f = git(wt, "fetch"' '    if False:
        f = git(wt, "fetch"'
caught "the push is never a force push (the racing commit survives)" sc_race '"push", "-q", remote' '"push", "-q", "-f", remote'
caught "a persistently rejected push is retried exactly once, then nothing is pushed" sc_rejected '        p = git(wt, "push", "-q", remote, "HEAD:%s" % branch, timeout=60)
        if p.returncode != 0:
            print("%s: push failed twice' '        p = git(wt, "push", "-q", remote, "HEAD:%s" % branch, timeout=60)
        p = git(wt, "push", "-q", remote, "HEAD:%s" % branch, timeout=60)
        if p.returncode != 0:
            print("%s: push failed twice'

section "== real run"
caught "real run: passing ghosts moved+committed, failing one git-rm'ed and listed in the closing commit, non-ghosts and the live clone untouched" sc_real '        elif verdict == "fail":
            git(wt, "rm", "-q", "-f", "--", dest)' '        elif verdict == "fail":
            pass'
caught "real run: only a pytest pass keeps a file" sc_real '        if verdict == "pass":' '        if True:'
caught "real run: a name collision gets the _relocated suffix" sc_real '        if dest in existing or dest in used:
            dest = ' '        if False:
            dest = '
caught "real run: only app/{jobs,routers,services} are ghost dirs" sc_real '"|".join(GHOST_DIRS)' '".*"'
section "== second run"
caught "second run is a no-op (nothing to do, remote unchanged)" sc_second_run '    moves, skipped = plan_moves(ls.stdout.split("\n"), backend)' '    moves, skipped = plan_moves(ls.stdout.split("\n") + ["iptv-backend/app/jobs/test_zzz_phantom.py"], backend)'
section "== PAUSED"
caught "state/PAUSED aborts with exit 1, nothing pushed" sc_paused '    if paused():
        print("%s: state/PAUSED exists' '    if False:
        print("%s: state/PAUSED exists'
caught "PAUSED appearing during the work aborts before the push" sc_paused_mid '    if paused():
        print("%s: state/PAUSED appeared' '    if False:
        print("%s: state/PAUSED appeared'
section "== dry run changes nothing"
caught "dry run: plan printed (4 ghosts, collision -> _relocated), remote refs cmp-identical, live clone untouched, no worktree" sc_dry '    if dry:' '    if False:'
section "== test cleanup is scoped to this test's own worktrees"
single "cleanup removes the fixture's worktree and leaves a foreign /tmp/wt-ghost-* alone" sc_cleanup_scope

wait
for f in "$T"/res/*.txt; do cat "$f"; done > "$T/all.txt"; cat "$T/all.txt"
pass="$(grep -c '^  ok ' "$T/all.txt")"; fail="$(grep -c '^  FAIL ' "$T/all.txt")"
echo "  $pass passed, $fail failed"; [ "$fail" = 0 ]
rc=$?
echo "test_ovn_ghost_tests.sh rc=$rc"
exit $rc
