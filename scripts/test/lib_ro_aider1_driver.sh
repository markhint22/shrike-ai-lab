#!/usr/bin/env bash
# Scenario driver for test_run_overnight_aider1_flow.sh (agent "f", 2026-09-30).
# usage: lib_ro_aider1_driver.sh <scenario> <workdir>
# Builds a hermetic fake overnight tree + a temp git repo (bare origin) in <workdir>, sources the REAL run_overnight.sh in
# OVN_SOURCE_ONLY mode and calls the REAL run_aider_fix_task with a scenario-driven stub `aider`. The status string the function
# echoed is written to <workdir>/result; the task log is <workdir>/task.log. Nothing outside <workdir> is touched except the
# literal /tmp/ovn_progress_tail_<repo>.md file the script itself writes (scenario sc_progress_tail only).
set -u
SCN_NAME="${1:?scenario}"; D="${2:?workdir}"
HERE="$(cd "$(dirname "$0")" && pwd)"
Q="$(cd "$HERE/../.." && pwd)"
RO="${OVN_RUN_OVERNIGHT:-$Q/run_overnight.sh}"
[ -f "$RO" ] || { echo "no run_overnight.sh"; exit 3; }

rm -rf "$D"; mkdir -p "$D"
export HOME="$D/home"; mkdir -p "$HOME/aider-venv/bin"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_TERMINAL_PROMPT=0
SD="$D/sd"; R="$D/repos/ro_aider1_repo"; O="$D/origin.git"; TL="$D/task.log"; SC="$D/scn"
mkdir -p "$SD/scripts" "$SD/state" "$SD/logs" "$SD/reports" "$SC" "$D/repos"
export AIDER1_SCN="$SC"

# ---- fake tree: symlink the real helper scripts (so they are the real code), stub what must be controlled ----
for f in "$Q"/scripts/*.sh "$Q"/scripts/*.py; do [ -f "$f" ] && ln -s "$f" "$SD/scripts/$(basename "$f")"; done
for f in dedupe_progress_headers.py ovn_classify_fail.sh ovn_park_unworkable.py; do [ -f "$Q/$f" ] && ln -s "$Q/$f" "$SD/$f"; done
echo '{}' > "$SD/model-metadata.json"; echo '[]' > "$SD/tasks.json"
cat > "$SD/ovn_stage_runner.sh" <<'STUB'
#!/bin/bash
# stub higher-tier stage runner; behaviour from $AIDER1_SCN/stage.mode
m="$(cat "$AIDER1_SCN/stage.mode" 2>/dev/null)"
echo "stub stage runner invoked mode=$m repo=$1"
case "$m" in
  nodoable) echo "no doable T3+ item found" ;;
  lock)     echo "another stage runner holds the lock" ;;
  pushed|unverified|unverified_bug|nojsonl)
    if [ "$m" != nojsonl ]; then
      mkdir -p state/stage_runs
      n=1; [ "$m" = pushed ] && n=2
      {
        echo '{"event":"decomposed","item":"- [ ] [T3] app/foo.py — rework foo heavily (cat:python)"}'
        echo '{"event":"step","tokens_sent":1200,"tokens_recv":300}'
        echo '{"event":"step","tokens_sent":800,"tokens_recv":200}'
        # 2026-10-02: the real runner journals this when it counted/escalated a manual bug itself (stage_bug_attempt)
        [ "$m" = unverified_bug ] && echo '{"run":"r","event":"bug_attempt","attempts":1,"cap":2}'
        echo "{\"event\":\"summary\",\"commits_pushed\":$([ "$m" = pushed ] && echo 2 || echo 0)}"
      } > "state/stage_runs/$1-$n.jsonl"
    fi ;;
esac
exit 0
STUB
cat > "$HOME/aider-venv/bin/aider" <<'STUB'
#!/bin/bash
# stub aider: scout pass (has --no-auto-commits) vs implement pass, scenario files in $AIDER1_SCN
S="$AIDER1_SCN"; mkdir -p "$S/calls"
n=$(ls "$S/calls" | wc -l | tr -d ' ')
kind=impl; for a in "$@"; do [ "$a" = "--no-auto-commits" ] && kind=scout; done
printf '%s\n' "$@" > "$S/calls/$((n+1)).$kind"
[ -f "$S/$kind.hook" ] && bash "$S/$kind.hook"
if [ -f "$S/$kind.out" ]; then cat "$S/$kind.out"; else echo "Tokens: 10 sent, 5 received"; fi
exit 0
STUB
chmod +x "$HOME/aider-venv/bin/aider" "$SD/ovn_stage_runner.sh"

# ---- repo helpers ----
git_init_origin(){ git init -q --bare "$O"; git -C "$O" symbolic-ref HEAD refs/heads/main; }
base_repo(){  # clone with app/foo.py app/bar.py CLAUDE.md OVERNIGHT_PROGRESS.md on main, pushed
  git_init_origin
  git clone -q "$O" "$R" 2>/dev/null
  ( cd "$R" && git checkout -q -b main 2>/dev/null
    mkdir -p app
    printf 'def foo():\n    return 1\n' > app/foo.py
    printf 'def bar():\n    return 2\n' > app/bar.py
    printf 'def prot():\n    return 3\n' > app/prot.py
    printf 'readme\n' > README.md
    printf 'claude rules\n' > CLAUDE.md
    printf '# Overnight Progress\n\n## Next Steps\n- [ ] [T1] app/foo.py — fix the foo handling (cat:python)\n- [ ] [T1] app/bar.py — tidy bar (cat:python)\n' > OVERNIGHT_PROGRESS.md
    git add -A; git commit -q -m base; git push -q origin main 2>/dev/null )
  git -C "$O" symbolic-ref HEAD refs/heads/main
}
other(){  # fresh second clone at $D/c2 (used to advance origin from "someone else")
  rm -rf "$D/c2"; git clone -q "$O" "$D/c2" 2>/dev/null
}
progress(){ printf '%s' "$1" > "$R/OVERNIGHT_PROGRESS.md"; ( cd "$R" && git add -A && git commit -q -m "prog" && git push -q origin main 2>/dev/null ); }
scout(){ printf '%s\n' "$1" > "$SC/scout.out"; }
proceed(){ scout "VERDICT: PROCEED
PLAN: $1
FILES:
$2
Tokens: 100 sent, 50 received"; }
reject_hook(){ printf '#!/bin/sh\necho rejected-by-test-hook >&2\nexit 1\n' > "$O/hooks/pre-receive"; chmod +x "$O/hooks/pre-receive"; }
TOP_PROG='# Overnight Progress

## Next Steps
- [ ] [T1] app/foo.py — fix the foo handling (cat:python)
- [ ] [T1] app/bar.py — tidy bar (cat:python)
'

ID="t1"; BR="ovn/t1"; PERSIST=false; PROMPT="Work the top item: app/foo.py fix foo. (cat:python)"
MAXF=2; PROT=""; MAP=""; SKIP=false; ATO=30
export OVN_SCRIPT_DIR="$SD" OVN_SOURCE_ONLY=1
export OVN_ARCHITECT="${OVN_ARCHITECT:-0}"

case "$SCN_NAME" in
  nogit) mkdir -p "$R" ;;
  *) base_repo ;;
esac

# source the REAL script (defines every function, returns before the main loop)
# shellcheck disable=SC1090
source "$RO"
set +e
STATE_DIR="$SD/state"
run_repo_verification(){ [ -f "$D/rrv.hook" ] && ( bash "$D/rrv.hook" ) >/dev/null 2>&1; cat "$D/rrv.mode" 2>/dev/null || echo pass; }
call(){ STATUS="$(run_aider_fix_task "$ID" "$R" "$PROMPT" "$BR" "$PERSIST" "$TL" "$MAP" "$SKIP" "$MAXF" "$PROT" "$ATO")"; printf '%s' "$STATUS" > "$D/result"; }
top_hash(){ local t; t="$(cd "$R" && ovn_resolve_top_item ".")"; ovn_item_hash "${t#*:}"; }

case "$SCN_NAME" in
  # ---------- prompt injection / repo prep ----------
  nogit) call ;;
  delhint) PROMPT="Delete the dead file app/old.py from the repo."; call ;;
  delhint_ongoing)
    PROMPT="Work the single top not-yet-done item in the overnight progress log."
    progress '# Overnight Progress

## Next Steps
- [ ] [T1] Remove the dead file app/bar.py — nothing imports it. (cat:python)
'
    call ;;
  br_default) call ;;
  br_persist_local)
    BR="claude/feature"; PERSIST=true
    ( cd "$R" && git checkout -q -b claude/feature && echo x >> README.md && git commit -qam localwork && git push -q origin claude/feature 2>/dev/null && git checkout -q main )
    call ;;
  br_persist_remote)
    BR="claude/feature"; PERSIST=true
    git -C "$O" branch claude/feature main
    call ;;
  br_fallback)
    # origin has no main at all -> `checkout -B branch origin/main` fails, falls back to the LOCAL main
    git -C "$O" update-ref -d refs/heads/main; git -C "$O" symbolic-ref HEAD refs/heads/nothere
    ( cd "$R" && git update-ref -d refs/remotes/origin/main; git remote set-head origin -d >/dev/null 2>&1 )
    call ;;
  sync_equal)
    BR="claude/feature"; PERSIST=true
    ( cd "$R" && git checkout -q -b claude/feature && git push -q origin claude/feature 2>/dev/null )
    call ;;
  sync_behind)
    BR="claude/feature"; PERSIST=true
    ( cd "$R" && git checkout -q -b claude/feature && git push -q origin claude/feature 2>/dev/null )
    other; ( cd "$D/c2" && git checkout -q claude/feature && echo adv > adv.txt && git add -A && git commit -q -m adv && git push -q origin claude/feature 2>/dev/null )
    call ;;
  sync_ahead)
    BR="claude/feature"; PERSIST=true
    ( cd "$R" && git checkout -q -b claude/feature && git push -q origin claude/feature 2>/dev/null && echo a > ahead.txt && git add -A && git commit -q -m ahead )
    call ;;
  sync_div_main)
    BR="claude/feature"; PERSIST=true
    git -C "$O" branch claude/feature main
    ( cd "$R" && git fetch -q origin && git checkout -q -b claude/feature origin/claude/feature && echo l > straggler.txt && git add -A && git commit -q -m straggler )
    # origin/claude/feature AND origin/main advance together (hygiene merged + reset the branch): local straggler is on a dead base
    other; ( cd "$D/c2" && echo merged >> README.md && git commit -qam merged && git push -q origin main 2>/dev/null && git push -q origin main:claude/feature -f 2>/dev/null )
    call ;;
  sync_div_recover)
    BR="claude/feature"; PERSIST=true
    ( cd "$R" && git checkout -q -b claude/feature && git push -q origin claude/feature 2>/dev/null && printf -- '- [ ] [T1] app/bar.py — local queue note\n' >> OVERNIGHT_PROGRESS.md && git commit -qam "local queue-only" )
    other; ( cd "$D/c2" && git checkout -q claude/feature && echo remote >> README.md && git commit -qam remote-readme && git push -q origin claude/feature 2>/dev/null )
    call ;;
  sync_div_conflict)
    BR="claude/feature"; PERSIST=true
    ( cd "$R" && git checkout -q -b claude/feature && git push -q origin claude/feature 2>/dev/null && sed -i.bak 's/tidy bar/LOCAL edit of bar/' OVERNIGHT_PROGRESS.md && rm -f OVERNIGHT_PROGRESS.md.bak && git commit -qam "local prog edit" )
    other; ( cd "$D/c2" && git checkout -q claude/feature && sed -i.bak 's/tidy bar/REMOTE edit of bar/' OVERNIGHT_PROGRESS.md && rm -f OVERNIGHT_PROGRESS.md.bak && git commit -qam "remote prog edit" && git push -q origin claude/feature 2>/dev/null )
    call ;;
  sync_div_pushfail)
    BR="claude/feature"; PERSIST=true
    ( cd "$R" && git checkout -q -b claude/feature && git push -q origin claude/feature 2>/dev/null && printf -- '- [ ] [T1] app/bar.py — local queue note\n' >> OVERNIGHT_PROGRESS.md && git commit -qam "local queue-only" )
    other; ( cd "$D/c2" && git checkout -q claude/feature && echo remote >> README.md && git commit -qam remote-readme && git push -q origin claude/feature 2>/dev/null )
    reject_hook
    call ;;
  sync_div_other)
    BR="claude/feature"; PERSIST=true
    ( cd "$R" && git checkout -q -b claude/feature && git push -q origin claude/feature 2>/dev/null && echo '# local' >> app/foo.py && git commit -qam "local code edit" )
    other; ( cd "$D/c2" && git checkout -q claude/feature && echo remote >> README.md && git commit -qam remote-readme && git push -q origin claude/feature 2>/dev/null )
    call ;;
  # ---------- placeholder / new-file stubs ----------
  stub_progress)
    PROMPT="Review OVERNIGHT_PROGRESS.md and pick the next item."
    ( cd "$R" && git rm -q OVERNIGHT_PROGRESS.md && git commit -q -m rmprog && git push -q origin main 2>/dev/null )
    call ;;
  stub_alembic) PROMPT="Add backend/alembic/versions/0007_sessions.py for the new table."; call ;;
  stub_py)      PROMPT="Create app/brand_new.py with a helper."; call ;;
  stub_gd)      PROMPT="Create scripts/mission/brand_new.gd with a helper."; call ;;
  stub_testts)  PROMPT="Create web/src/brand_new.test.ts covering the helper."; call ;;
  stub_spects)  PROMPT="Create web/src/brand_new.spec.tsx covering the helper."; call ;;
  stub_ts)      PROMPT="Create web/src/brand_new.ts with a helper."; call ;;
  stub_kt)      PROMPT="Create android/app/BrandNew.kt with a helper."; call ;;
  stub_swift)   PROMPT="Create ios/BrandNew.swift with a helper."; call ;;
  stub_vue)     PROMPT="Create web/src/BrandNew.vue component."; call ;;
  stub_existing) PROMPT="Edit app/foo.py to be better."; call ;;
  selfheal)
    ( cd "$R" && mkdir -p web
      printf '// Placeholder - the implement step fills this in.\n' > web/a.test.ts
      printf '// just a comment, not ours\n' > web/b.test.ts
      printf "import { it } from 'vitest'\nit('real', () => {})\n" > web/c.test.ts
      printf '// Placeholder - the implement step fills this in.\n' > web/d.spec.tsx
      git add -A && git commit -q -m tests && git push -q origin main 2>/dev/null
      rm -f web/d.spec.tsx )
    call ;;
  # ---------- maintenance commits ----------
  sanitizer)
    progress '# Overnight Progress

## Next Steps
- [ ] Improve overall code quality everywhere
- [ ] [T1] app/foo.py — fix the foo handling (cat:python)
- [ ] [T1] app/bar.py — tidy bar (cat:python)
- [ ] [T1] app/prot.py — tidy prot (cat:python)
- [ ] [T1] app/foo.py — second foo (cat:python)
'
    call ;;
  selfgen)
    ( cd "$R" && printf 'def risky():\n    try:\n        return 1\n    except:\n        pass\n' > app/risky.py && git add -A && git commit -q -m risky && git push -q origin main 2>/dev/null )
    call ;;
  exhausted)
    progress '# Overnight Progress

## Next Steps
- [x] [T1] app/foo.py — done already (cat:python)
'
    call ;;
  inline_refill|inline_refill_dry)
    # queue_refill.sh stub: records its args; the "wet" variant pulls one doable item into the live queue and commits it locally
    cat > "$SD/queue_refill.sh" <<'RSTUB'
#!/bin/bash
echo "$*" >> "$AIDER1_SCN/refill.args"
if [ -f "$AIDER1_SCN/refill.wet" ]; then
  cd "$HOME/../repos/$1" 2>/dev/null || cd "$(dirname "$AIDER1_SCN")/repos/$1" || exit 0
  printf -- '- [ ] [T1] app/foo.py — refilled from backlog (cat:python)\n' >> OVERNIGHT_PROGRESS.md
  git add -A && git commit -q -m "chore(queue): auto-refill 1 items from backlog"
fi
exit 0
RSTUB
    chmod +x "$SD/queue_refill.sh"
    [ "$SCN_NAME" = inline_refill ] && : > "$SC/refill.wet"
    progress '# Overnight Progress

## Next Steps
- [x] [T1] app/foo.py — done already (cat:python)
'
    proceed 'fix foo' 'app/foo.py'
    call ;;
  # ---------- higher tier stage ----------
  stage_nodoable) progress "$TOP_PROG- [ ] [T3] app/foo.py — rework foo heavily (cat:python)
"; echo nodoable > "$SC/stage.mode"; call ;;
  stage_lock)     progress "$TOP_PROG- [ ] [T3] app/foo.py — rework foo heavily (cat:python)
"; echo lock > "$SC/stage.mode"; call ;;
  stage_pushed)   progress "$TOP_PROG- [ ] [T3] app/foo.py — rework foo heavily (cat:python)
"; echo pushed > "$SC/stage.mode"; call ;;
  stage_unverified) progress "$TOP_PROG- [ ] [T3] app/foo.py — rework foo heavily (cat:python)
"; echo unverified > "$SC/stage.mode"; call ;;
  stage_unverified_bug) progress "$TOP_PROG- [ ] [T3] app/foo.py — rework foo heavily (cat:python)
"; echo unverified_bug > "$SC/stage.mode"; call ;;
  stage_nojsonl)  progress "$TOP_PROG- [ ] [T3] app/foo.py — rework foo heavily (cat:python)
"; echo nojsonl > "$SC/stage.mode"; call ;;
  stage_off)      progress "$TOP_PROG- [ ] [T3] app/foo.py — rework foo heavily (cat:python)
"; echo pushed > "$SC/stage.mode"; OVN_INLINE_STAGE=0; export OVN_INLINE_STAGE; call ;;
  # ---------- delete executor ----------
  de_*)
    ID="ongoing-ro_aider1_repo"; BR="main"; PROMPT="Work the single top not-yet-done item in the overnight progress log."
    ( cd "$R" && printf 'def dead():\n    return 0\n' > app/dead_mod.py && git add -A && git commit -q -m dead && git push -q origin main 2>/dev/null )
    DITEM='- [ ] [T1] app/dead_mod.py — Delete this file, nothing imports it. (cat:python)'
    progress "# Overnight Progress

## Next Steps
$DITEM
- [ ] [T1] app/bar.py — tidy bar (cat:python)
- [ ] [T1] app/foo.py — second foo (cat:python)
- [ ] [T1] app/prot.py — third (cat:python)
"
    case "$SCN_NAME" in
      de_pass) echo pass > "$D/rrv.mode"; call ;;
      de_fail) echo fail > "$D/rrv.mode"; call ;;
      de_skip) echo skip > "$D/rrv.mode"; call ;;
      de_push_retry)
        echo pass > "$D/rrv.mode"
        other
        printf '#!/bin/bash\nc=%s; rm -rf "$c" ; git clone -q %s "$c" 2>/dev/null; cd "$c" && echo adv >> README.md && git commit -qam adv && git push -q origin main 2>/dev/null\n' "$D/c3" "$O" > "$D/rrv.hook"
        call ;;
      de_push_fail)
        echo pass > "$D/rrv.mode"
        printf '#!/bin/bash\nprintf "#!/bin/sh\\nexit 1\\n" > %s/hooks/pre-receive; chmod +x %s/hooks/pre-receive\n' "$O" "$O" > "$D/rrv.hook"
        call ;;
      de_commit_fail)
        printf '#!/bin/sh\nexit 1\n' > "$R/.git/hooks/pre-commit"; chmod +x "$R/.git/hooks/pre-commit"
        call ;;
      de_skip_line)
        progress "# Overnight Progress

## Next Steps
- [ ] [T1] app/foo.py — Remove the dead function foo from this module. (cat:python)
- [ ] [T1] app/bar.py — tidy bar (cat:python)
- [ ] [T1] app/prot.py — third (cat:python)
- [ ] [T1] app/foo.py — second foo (cat:python)
"
        call ;;
      de_failed_memory)
        mkdir -p "$SD/state/delete_exec_failed"; : > "$SD/state/delete_exec_failed/$(top_hash)"
        call ;;
      de_off) export OVN_DELETE_EXECUTOR=off; call ;;
      de_noitem)
        # passes the exhausted-check filter (only "BLOCKED ITEM" is excluded there) but is excluded from the delete-executor peek
        progress '# Overnight Progress

## Next Steps
- [ ] [T1] app/foo.py — fix foo, BLOCKED on an upstream change (cat:python)
'
        call ;;
    esac ;;
  # ---------- scout verdicts ----------
  sc_blocked) scout "VERDICT: BLOCKED
PLAN: a human must add the credential
FILES: NONE"; call ;;
  sc_needsdec) scout "VERDICT: NEEDS-DECISION
PLAN: product decision needed for app/foo.py
FILES:
app/foo.py"; call ;;
  sc_none) scout "I think we should look at app/foo.py"; call ;;
  sc_alreadydone)
    scout "VERDICT: ALREADY-DONE
PLAN: README.md and app/nomatch.py and app/foo.py already implement this item
FILES: NONE"; call ;;
  sc_ad_nomatch)
    scout "VERDICT: ALREADY-DONE
PLAN: app/elsewhere.py already implements this item
FILES: NONE"; call ;;
  sc_ad_noplan)
    scout "VERDICT: ALREADY-DONE
FILES: NONE"; call ;;
  sc_ad_pushrebase)
    scout "VERDICT: ALREADY-DONE
PLAN: app/foo.py already implements this item
FILES: NONE"
    other
    printf '#!/bin/bash\nc=%s; rm -rf "$c"; git clone -q %s "$c" 2>/dev/null; cd "$c" && git checkout -q -b ovn/t1 origin/main && echo adv >> README.md && git commit -qam adv && git push -q origin ovn/t1 2>/dev/null\n' "$D/c3" "$O" > "$SC/scout.hook"
    call ;;
  sc_ad_pushfail)
    scout "VERDICT: ALREADY-DONE
PLAN: app/foo.py already implements this item
FILES: NONE"
    printf '#!/bin/bash\nprintf "#!/bin/sh\\nexit 1\\n" > %s/hooks/pre-receive; chmod +x %s/hooks/pre-receive\n' "$O" "$O" > "$SC/scout.hook"
    call ;;
  sc_ad_commitfail)
    scout "VERDICT: ALREADY-DONE
PLAN: app/foo.py already implements this item
FILES: NONE"
    printf '#!/bin/bash\nprintf "#!/bin/sh\\nexit 1\\n" > .git/hooks/pre-commit; chmod +x .git/hooks/pre-commit\n' > "$SC/scout.hook"
    call ;;
  sc_credit_changes)
    rm -f "$SD/scripts/ovn_credit_already_satisfied.sh"
    cat > "$SD/scripts/ovn_credit_already_satisfied.sh" <<'STUB'
#!/bin/bash
sed -i.bak '0,/^- \[ \] /s//- [x] (stub-credit) /' "$2"; rm -f "$2.bak"; echo "CREDITED=1"
STUB
    scout "VERDICT: BLOCKED
PLAN: nothing
FILES: NONE"
    call ;;
  sc_credit_nochange)
    rm -f "$SD/scripts/ovn_credit_already_satisfied.sh"
    printf '#!/bin/bash\necho CREDITED=1\n' > "$SD/scripts/ovn_credit_already_satisfied.sh"
    scout "VERDICT: NEEDS-DECISION
PLAN: nothing
FILES: NONE"
    call ;;
  sc_credit_pushfail)
    rm -f "$SD/scripts/ovn_credit_already_satisfied.sh"
    cat > "$SD/scripts/ovn_credit_already_satisfied.sh" <<'STUB'
#!/bin/bash
sed -i.bak '0,/^- \[ \] /s//- [x] (stub-credit) /' "$2"; rm -f "$2.bak"; echo "CREDITED=1"
STUB
    scout "VERDICT: BLOCKED
PLAN: nothing
FILES: NONE"
    reject_hook
    call ;;
  sc_ungrounded) proceed "make it better somehow" "NONE"; call ;;
  sc_forceload)
    MAXF=1; PROT="app/prot.py"
    proceed "change app/bar.py app/foo.py app/prot.py and README.md" "app/bar.py
app/foo.py"
    call ;;
  sc_multifile_no)
    PROMPT="$PROMPT multifile:no"
    proceed "change app/bar.py and app/foo.py" "NONE"; call ;;
  sc_ident_fallback)
    ( cd "$R" && mkdir -p tests && printf 'def compute_total(x):\n    return x\n\ndef other_helper():\n    return 0\n' > app/calc.py
      printf 'def guarded_fn():\n    return 1\n' > app/guard.py
      printf 'def only_in_tests():\n    return 1\n' > tests/test_zzz.py
      git add -A && git commit -q -m calc && git push -q origin main 2>/dev/null )
    PROMPT='Implement `compute_total` and `other_helper` plus `guarded_fn` and `only_in_tests` and `no_such_fn` properly.'
    PROT="app/guard.py"
    proceed "update app/ghost/zzz.py accordingly" "NONE"
    call ;;
  # ---------- scout file guard (2026-10-02) ----------
  sg_*)
    ( cd "$R" && mkdir -p tests && python3 -c "open('app/huge.py','w').write('x = 1\n' * 60000)"
      printf 'def b():\n    return 1\n' > app/banned.py; printf 'app/banned.py\n' > .queue-hard-banned-files
      git add -A && git commit -q -m sgfix && git push -q origin main 2>/dev/null )
    SG_ITEM='- [ ] [T2] tests/test_persist.py — add a test that the autosave persists (cat:test)'
    case "$SCN_NAME" in sg_target) SG_ITEM='- [ ] [T2] app/huge.py — add a helper (cat:python)';; esac
    progress "# Overnight Progress

## Next Steps
$SG_ITEM
- [ ] [T1] app/bar.py — tidy bar (cat:python)
"
    PROMPT="Work the single top not-yet-done item in the overnight progress log."
    case "$SCN_NAME" in
      sg_banned)   proceed "persist the autosave via the code in app/banned.py" "app/banned.py";;
      sg_oversize) proceed "persist the autosave via the code in app/huge.py" "app/huge.py";;
      sg_target)   proceed "edit app/huge.py to add the helper" "app/huge.py
app/foo.py";;
      sg_partial)  proceed "write tests/test_persist.py against app/huge.py and app/foo.py" "tests/test_persist.py
app/huge.py
app/foo.py";;
      sg_benign)   proceed "write tests/test_persist.py against app/foo.py" "tests/test_persist.py
app/foo.py";;
      sg_off)      export OVN_SCOUT_GUARD=off; proceed "write tests/test_persist.py against app/huge.py" "tests/test_persist.py
app/huge.py";;
      sg_limit)    export OVN_MAX_FILE_BYTES=20; proceed "write tests/test_persist.py against app/foo.py" "tests/test_persist.py
app/foo.py";;
      sg_pushfail) reject_hook; proceed "persist the autosave via the code in app/banned.py" "app/banned.py";;
    esac
    call ;;
  sc_proceed_plan)
    proceed "edit app/foo.py to fix the foo handling" "app/foo.py"; call ;;
  sc_lastfail)
    mkdir -p "$SD/state/item_fails"; h="$(top_hash)"
    printf '%s|the previous attempt broke test_foo with an AssertionError\n' "$h" > "$SD/state/item_fails/${ID}.${h}.lastfail"
    proceed "edit app/foo.py" "app/foo.py"; call ;;
  sc_lastfail_mismatch)
    mkdir -p "$SD/state/item_fails"; h="$(top_hash)"
    printf 'deadbeef|stale note from another item\n' > "$SD/state/item_fails/${ID}.${h}.lastfail"
    proceed "edit app/foo.py" "app/foo.py"; call ;;
  sc_architect)
    export OVN_ARCHITECT=1; PROMPT="Refactor app/foo.py across multiple files."
    proceed "edit app/foo.py" "app/foo.py"; call ;;
  sc_committed_scout)
    scout "VERDICT: BLOCKED
PLAN: nothing
FILES: NONE"
    printf '#!/bin/bash\necho junk > scout_junk.txt\necho dirty >> app/foo.py\ngit add -A; git commit -q -m "scout committed anyway"\necho more >> app/bar.py\necho unt > untracked_scout.txt\n' > "$SC/scout.hook"
    call ;;
  sc_autotest)
    ( cd "$R" && echo '{}' > package.json && git add -A && git commit -q -m pkg && git push -q origin main 2>/dev/null )
    call ;;
  sc_progress_tail)
    export OVN_PROGRESS_MAX_BYTES=200
    big="$TOP_PROG"; for i in 1 2 3 4 5 6; do big="$big- [x] (done) item $i mentions OVERNIGHT_PROGRESS.md and some long history text to pad it out\n"; done
    progress "$(printf '%b' "$big")
"
    call ;;
  sc_no_progress)
    PROMPT="Fix things in app/foo.py."
    ( cd "$R" && git rm -q OVERNIGHT_PROGRESS.md && git commit -q -m noprog && git push -q origin main 2>/dev/null )
    call ;;
  sc_nolib)
    # the shared lib_item_select helpers are optional (`command -v` guards): exercise the inline fallbacks
    unset -f ovn_resolve_top_item ovn_item_hash
    proceed "edit app/foo.py" "app/foo.py"; call ;;
  sc_skip_agents)
    SKIP=true; MAP=4096; call ;;
  *) echo "unknown scenario $SCN_NAME"; exit 4 ;;
esac
exit 0
