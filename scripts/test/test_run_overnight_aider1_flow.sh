#!/usr/bin/env bash
# Integration test (agent "f", 2026-09-30): the FIRST HALF of run_overnight.sh's run_aider_fix_task - everything from the function start
# through the scout/verdict handling, the ALREADY-DONE/any-verdict credit paths, plan force-loading and the DELETE-EXECUTOR block.
# Unlike the older awk-extraction tests this RUNS the real script: lib_ro_aider1_driver.sh builds a hermetic fake tree + temp git repo
# (bare origin) and `source`s the real run_overnight.sh with OVN_SOURCE_ONLY=1, then calls run_aider_fix_task with a scenario-driven
# stub `aider` (and a stub stage runner). Only the implement loop onward is out of scope (agent "g").
# KNOWN-BUG: prefixed assertions document real defects (non-fatal warnings).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
DRV="$HERE/lib_ro_aider1_driver.sh"
[ -f "$DRV" ] || { echo "  SKIP: driver missing"; exit 0; }
pass=0; fail=0; warn=0
ok(){ if [ "$2" = "1" ]; then pass=$((pass+1)); echo "  ok   $1"; else fail=$((fail+1)); echo "  FAIL $1"; fi; }
kb(){ if [ "$2" = "1" ]; then pass=$((pass+1)); echo "  ok   KNOWN-BUG fixed: $1"; else warn=$((warn+1)); echo "  WARN KNOWN-BUG: $1"; fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"; rm -f /tmp/ovn_progress_tail_ro_aider1_repo.md' EXIT

run(){ timeout 150 bash "$DRV" "$1" "$T/$1" > "$T/$1.out" 2>&1; }   # one scenario = one fresh process + tree
res(){ cat "$T/$1/result" 2>/dev/null; }
rd(){ echo "$T/$1/repos/ro_aider1_repo"; }
og(){ echo "$T/$1/origin.git"; }
tlog(){ cat "$T/$1/task.log" 2>/dev/null; }
alerts(){ cat "$T/$1/sd/state/alerts.log" 2>/dev/null; }
has(){ grep -qF -- "$2" <<<"$1" && echo 1 || echo 0; }
hasre(){ grep -qE -- "$2" <<<"$1" && echo 1 || echo 0; }
hasline(){ grep -qxF -- "$2" <<<"$1" && echo 1 || echo 0; }
b2i(){ [ "$1" = 0 ] && echo 1 || echo 0; }
scoutcall(){ cat "$T/$1/scn/calls/1.scout" 2>/dev/null; }
implcall(){ cat "$T/$1/scn/calls/2.impl" 2>/dev/null; }
cur(){ git -C "$(rd "$1")" branch --show-current; }
headmsg(){ git -C "$(rd "$1")" log -1 --format=%s; }

echo "== repo prep =="
run nogit
ok "no .git -> 'error: no .git' status, no aider call" "$(hasre "$(res nogit)" 'error: no \.git at')"
ok "no .git -> aider never invoked" "$([ ! -d "$T/nogit/scn/calls" ] && echo 1 || echo 0)"

run delhint
ok "delete-shaped prompt gets the DELETE: trailer hint prepended to the scout prompt" "$(has "$(scoutcall delhint)" 'IMPORTANT: this task deletes/removes a file')"
run delhint_ongoing
ok "ongoing lane: generic prompt + delete-shaped TOP progress item still gets the hint" "$(has "$(scoutcall delhint_ongoing)" 'IMPORTANT: this task deletes/removes a file')"
run br_default
ok "non-persistent: fresh branch off origin/main" "$([ "$(cur br_default)" = ovn/t1 ] && echo 1 || echo 0)"
ok "non-delete prompt has NO delete hint" "$(b2i "$(has "$(scoutcall br_default)" 'IMPORTANT: this task deletes')")"
ok "no .venv/package.json -> no auto-test args in the implement call" "$(b2i "$(has "$(implcall br_default)" '--auto-test')")"
ok "CLAUDE.md pre-loaded read-only when skip_agents_md is false" "$(has "$(scoutcall br_default)" 'CLAUDE.md')"
ok "default map-tokens 3072 when none given" "$(has "$(scoutcall br_default)" '3072')"
ok "model-metadata file passed" "$(has "$(scoutcall br_default)" 'model-metadata.json')"
run br_persist_local
ok "persistent + branch exists locally: checked out as-is" "$([ "$(cur br_persist_local)" = claude/feature ] && git -C "$(rd br_persist_local)" log --oneline | grep -q localwork && echo 1 || echo 0)"
run br_persist_remote
ok "persistent + branch only on origin: created from origin/<branch>" "$([ "$(cur br_persist_remote)" = claude/feature ] && echo 1 || echo 0)"
run br_fallback
ok "origin/main missing: falls back to local main" "$([ "$(cur br_fallback)" = ovn/t1 ] && echo 1 || echo 0)"

echo "== persistent-branch sync with origin =="
run sync_equal
ok "equal heads: clone untouched, no alert" "$([ -z "$(alerts sync_equal)" ] && echo 1 || echo 0)"
run sync_behind
ok "local behind origin: fast-forwarded to origin (adv.txt present)" "$([ -f "$(rd sync_behind)/adv.txt" ] && echo 1 || echo 0)"
run sync_ahead
ok "local ahead: left alone (unpushed commit kept)" "$([ -f "$(rd sync_ahead)/ahead.txt" ] && echo 1 || echo 0)"
run sync_div_main
ok "diverged but origin==main: clone reset to merged baseline (straggler gone)" "$([ ! -f "$(rd sync_div_main)/straggler.txt" ] && [ "$(git -C "$(rd sync_div_main)" rev-parse HEAD)" = "$(git -C "$(og sync_div_main)" rev-parse main)" ] && echo 1 || echo 0)"
run sync_div_recover
a="$(alerts sync_div_recover)"
ok "diverged, queue-only local commit: auto-RECOVERED alert" "$(has "$a" 'auto-RECOVERED')"
ok "recovered commit replayed onto origin (pushed)" "$(git -C "$(og sync_div_recover)" log claude/feature --format=%s | grep -q 'local queue-only' && echo 1 || echo 0)"
ok "a backup-diverged branch is kept" "$(git -C "$(rd sync_div_recover)" branch | grep -q backup-diverged && echo 1 || echo 0)"
run sync_div_conflict
a="$(alerts sync_div_conflict)"
ok "diverged, same-line conflict on the queue file: NOT auto-recovered alert with commit subjects" "$(has "$a" 'NOT auto-recovered')"
ok "conflict: clone reset to origin (cherry-pick aborted, tree clean)" "$([ -z "$(git -C "$(rd sync_div_conflict)" status --porcelain)" ] && [ "$(git -C "$(rd sync_div_conflict)" rev-parse HEAD)" = "$(git -C "$(og sync_div_conflict)" rev-parse claude/feature)" ] && echo 1 || echo 0)"
run sync_div_pushfail
a="$(alerts sync_div_pushfail)"
ok "recovery push rejected twice: falls back to NOT auto-recovered + reset to origin" "$(has "$a" 'NOT auto-recovered')"
ok "push-fail: clone equals origin afterwards" "$([ "$(git -C "$(rd sync_div_pushfail)" rev-parse HEAD)" = "$(git -C "$(og sync_div_pushfail)" rev-parse claude/feature)" ] && echo 1 || echo 0)"
run sync_div_other
a="$(alerts sync_div_other)"
ok "diverged touching a code file: backup branch + NOT auto-recovered alert" "$(has "$a" 'NOT auto-recovered')"
ok "code-file divergence: backup branch holds the local commit" "$(git -C "$(rd sync_div_other)" log --all --format=%s | grep -q 'local code edit' && echo 1 || echo 0)"

echo "== placeholder / new-file stubs =="
run stub_progress
ok "missing OVERNIGHT_PROGRESS.md named in prompt -> stub committed" "$(git -C "$(rd stub_progress)" log --format=%s | grep -q 'stub OVERNIGHT_PROGRESS.md' && echo 1 || echo 0)"
ok "stub has no doable items -> skip(exhausted)" "$([ "$(res stub_progress)" = 'skip(exhausted)' ] && echo 1 || echo 0)"
run stub_alembic
f="$(rd stub_alembic)/backend/alembic/versions/0007_sessions.py"
ok "new Alembic migration file stubbed + committed" "$([ -f "$f" ] && git -C "$(rd stub_alembic)" log -1 --format=%s | grep -q 'stub new Alembic' && echo 1 || echo 0)"
run stub_py;   ok ".py stub is a docstring placeholder" "$(has "$(cat "$(rd stub_py)/app/brand_new.py")" '"""Placeholder')"
run stub_gd;   ok ".gd stub is a # comment placeholder" "$(has "$(cat "$(rd stub_gd)/scripts/mission/brand_new.gd")" '# Placeholder')"
run stub_testts
c="$(cat "$(rd stub_testts)/web/src/brand_new.test.ts")"
ok ".test.ts stub is a valid SKIPPED vitest suite (not comment-only)" "$([ "$(has "$c" "describe.skip(")" = 1 ] && [ "$(has "$c" "from 'vitest'")" = 1 ] && echo 1 || echo 0)"
run stub_spects
ok ".spec.tsx stub is also a skipped vitest suite" "$(has "$(cat "$(rd stub_spects)/web/src/brand_new.spec.tsx")" 'describe.skip(')"
run stub_ts;   ok "plain .ts stub exports {} (valid module)" "$(has "$(cat "$(rd stub_ts)/web/src/brand_new.ts")" 'export {}')"
run stub_kt;   ok ".kt stub committed as a comment placeholder" "$(has "$(cat "$(rd stub_kt)/android/app/BrandNew.kt")" '// Placeholder')"
run stub_swift; ok ".swift stub committed as a comment placeholder" "$(has "$(cat "$(rd stub_swift)/ios/BrandNew.swift")" '// Placeholder')"
run stub_vue;  ok ".vue stub has a minimal template" "$(has "$(cat "$(rd stub_vue)/web/src/BrandNew.vue")" '<template><div /></template>')"
run stub_existing
ok "already-existing file named in prompt is never stubbed/clobbered" "$([ "$(headmsg stub_existing)" = base ] && echo 1 || echo 0)"

echo "== self-heal of committed placeholder test stubs =="
run selfheal
r="$(rd selfheal)"
ok "marked placeholder-only test file repaired into a skipped suite" "$(has "$(cat "$r/web/a.test.ts")" 'describe.skip(')"
ok "comment-only test file WITHOUT our marker is left alone" "$([ "$(cat "$r/web/b.test.ts")" = '// just a comment, not ours' ] && echo 1 || echo 0)"
ok "real test file is untouched" "$(has "$(cat "$r/web/c.test.ts")" "it('real'")"
ok "self-heal commit message names the repaired count" "$(git -C "$r" log --format=%s | grep -q 'make 1 placeholder-only test file' && echo 1 || echo 0)"

echo "== maintenance commits (sanitizer / self-gen / exhausted) =="
run sanitizer
r="$(rd sanitizer)"
ok "sanitizer retires the vague no-file item and commits" "$(git -C "$r" log --format=%s | grep -q 'retire vague no-file items' && echo 1 || echo 0)"
ok "vague item no longer an open top-level item" "$(b2i "$(has "$(grep -E '^- \[ \]' "$r/OVERNIGHT_PROGRESS.md")" 'Improve overall code quality')")"
run selfgen
ok "self-gen tops up a low-water repo and commits" "$(git -C "$(rd selfgen)" log --format=%s | grep -q 'auto-generate safe mechanical items' && echo 1 || echo 0)"
run exhausted
ok "no doable items -> skip(exhausted)" "$([ "$(res exhausted)" = 'skip(exhausted)' ] && echo 1 || echo 0)"
ok "exhausted skip leaves a log line and never calls aider" "$([ "$(has "$(tlog exhausted)" '0 doable items')" = 1 ] && [ ! -d "$T/exhausted/scn/calls" ] && echo 1 || echo 0)"
run inline_refill
ok "low-water repo: the backlog refill runs INLINE for exactly this repo (by basename)" "$([ "$(cat "$T/inline_refill/scn/refill.args" 2>/dev/null)" = ro_aider1_repo ] && echo 1 || echo 0)"
ok "after the inline refill the cycle proceeds to the scout instead of skip(exhausted)" "$([ "$(res inline_refill)" != 'skip(exhausted)' ] && [ -f "$T/inline_refill/scn/calls/1.scout" ] && echo 1 || echo 0)"
kb "the task log keeps the inline-refill line (same scout '> \$task_log' truncation as the sanitizer lines)" "$(has "$(tlog inline_refill)" 'inline refill: only 0 doable')"
run inline_refill_dry
ok "an inline refill that finds nothing still ends in skip(exhausted), tried once" "$([ "$(res inline_refill_dry)" = 'skip(exhausted)' ] && [ "$(wc -l < "$T/inline_refill_dry/scn/refill.args" | tr -d ' ')" = 1 ] && echo 1 || echo 0)"
OVN_INLINE_REFILL=0 run inline_refill
ok "OVN_INLINE_REFILL=0 disables it (no refill call, exhausted skip as before)" "$([ ! -f "$T/inline_refill/scn/refill.args" ] && [ "$(res inline_refill)" = 'skip(exhausted)' ] && echo 1 || echo 0)"
# KNOWN-BUG: sanitizer/self-gen/self-heal log lines are written to task_log BEFORE the scout pass, whose `> "$task_log"` truncates them.
kb "pre-scout diagnostic lines (sanitizer) survive the scout's truncating '>' redirect (run_overnight.sh scout call: > \"\$task_log\")" "$(has "$(tlog sanitizer)" '--- sanitizer:')"

echo "== higher-tier inline stage hand-off =="
run stage_pushed
ok "stage with commits_pushed>0 -> 'pushed(tests:pass) stage(higher-tier)'" "$([ "$(res stage_pushed)" = 'pushed(tests:pass) stage(higher-tier)' ] && echo 1 || echo 0)"
ok "stage tokens summed from the run jsonl into the task log" "$(has "$(tlog stage_pushed)" 'Tokens: 2000 sent, 500 received')"
ok "stage outcome appended to task_stats.log as pass" "$(hasre "$(cat "$T/stage_pushed/sd/state/task_stats.log")" 'pass')"
ok "stage path never calls aider itself" "$([ ! -d "$T/stage_pushed/scn/calls" ] && echo 1 || echo 0)"
run stage_unverified
ok "stage with 0 pushed -> no-op(stage-unverified)" "$([ "$(res stage_unverified)" = 'no-op(stage-unverified) stage(higher-tier)' ] && echo 1 || echo 0)"
ok "0-pushed stage recorded as noop:flail" "$(has "$(cat "$T/stage_unverified/sd/state/task_stats.log")" 'noop:flail')"
run stage_unverified_bug
ok "stage that counted/escalated a manual bug itself (bug_attempt event) -> status carries 'bug-handled' (2026-10-02: guard must not re-count it)" "$([ "$(res stage_unverified_bug)" = 'no-op(stage-unverified) stage(higher-tier) bug-handled' ] && echo 1 || echo 0)"
ok "bug-handled status still classifies as stage-unverified (stats unchanged)" "$([ "$(bash "$HERE/../../ovn_classify_fail.sh" "$T/stage_unverified_bug/task.log" "$(res stage_unverified_bug)" 2>/dev/null | tail -1)" = stage-unverified ] && echo 1 || echo 0)"
run stage_nojsonl
ok "stage with no jsonl at all -> honest no-op(stage-unverified), no token line" "$([ "$(res stage_nojsonl)" = 'no-op(stage-unverified) stage(higher-tier)' ] && [ "$(b2i "$(has "$(tlog stage_nojsonl)" 'Tokens:')")" = 1 ] && echo 1 || echo 0)"
run stage_nodoable
ok "'no doable T3+' falls through to scout+implement (aider called)" "$([ -f "$T/stage_nodoable/scn/calls/1.scout" ] && echo 1 || echo 0)"
run stage_lock
ok "'another stage runner holds the lock' also falls through" "$([ -f "$T/stage_lock/scn/calls/1.scout" ] && echo 1 || echo 0)"
run stage_off
ok "OVN_INLINE_STAGE=0 skips the stage hand-off entirely" "$([ -f "$T/stage_off/scn/calls/1.scout" ] && echo 1 || echo 0)"

echo "== scout verdicts =="
run sc_blocked
ok "BLOCKED -> no-op(BLOCKED), implement skipped" "$([ "$(res sc_blocked)" = 'no-op(BLOCKED)' ] && [ ! -f "$T/sc_blocked/scn/calls/2.impl" ] && echo 1 || echo 0)"
ok "verdict recorded in cycle_summary.log" "$(has "$(cat "$T/sc_blocked/sd/state/cycle_summary.log")" 'verdict=BLOCKED')"
run sc_needsdec
ok "NEEDS-DECISION -> no-op(NEEDS-DECISION)" "$([ "$(res sc_needsdec)" = 'no-op(NEEDS-DECISION)' ] && echo 1 || echo 0)"
ok "NEEDS-DECISION plan files land in cycle_summary planfiles" "$(has "$(cat "$T/sc_needsdec/sd/state/cycle_summary.log")" 'app/foo.py')"
run sc_none
ok "no VERDICT at all: verdict=NONE in cycle_summary, implement still attempted" "$([ "$(has "$(cat "$T/sc_none/sd/state/cycle_summary.log")" 'verdict=NONE')" = 1 ] && [ -f "$T/sc_none/scn/calls/2.impl" ] && echo 1 || echo 0)"
run sc_committed_scout
r="$(rd sc_committed_scout)"
ok "scout that committed despite --no-auto-commits is reset to BEFORE_SHA" "$([ "$(headmsg sc_committed_scout)" = base ] && echo 1 || echo 0)"
ok "scout's dirty + untracked leftovers are cleaned" "$([ -z "$(git -C "$r" status --porcelain)" ] && [ ! -f "$r/untracked_scout.txt" ] && echo 1 || echo 0)"

echo "== ALREADY-DONE credit =="
run sc_alreadydone
r="$(rd sc_alreadydone)"
ok "ALREADY-DONE credits the matching item ([x] (already-done, scout-verified))" "$(has "$(cat "$r/OVERNIGHT_PROGRESS.md")" '- [x] (already-done, scout-verified) [T1] app/foo.py')"
ok "credit skips .md + non-matching tokens and matches foo.py" "$(has "$(tlog sc_alreadydone)" 'matched foo.py')"
ok "credit commit pushed to origin branch" "$(git -C "$(og sc_alreadydone)" log ovn/t1 --format=%s | grep -q 'credit already-done item' && echo 1 || echo 0)"
ok "status no-op(ALREADY-DONE)" "$([ "$(res sc_alreadydone)" = 'no-op(ALREADY-DONE)' ] && echo 1 || echo 0)"
run sc_ad_nomatch
ok "ALREADY-DONE naming a file no item mentions: nothing credited" "$([ "$(headmsg sc_ad_nomatch)" = base ] && echo 1 || echo 0)"
run sc_ad_noplan
ok "ALREADY-DONE with no PLAN line: no credit, no crash" "$([ "$(headmsg sc_ad_noplan)" = base ] && [ "$(res sc_ad_noplan)" = 'no-op(ALREADY-DONE)' ] && echo 1 || echo 0)"
run sc_ad_pushrebase
ok "credit push rejected -> pull --rebase + retry succeeds (origin has both commits)" "$([ "$(has "$(tlog sc_ad_pushrebase)" 'rebasing onto origin/ovn/t1')" = 1 ] && git -C "$(og sc_ad_pushrebase)" log ovn/t1 --format=%s | grep -q 'credit already-done item' && echo 1 || echo 0)"
run sc_ad_pushfail
ok "credit push failing after rebase-retry is logged (credit may be lost)" "$(has "$(tlog sc_ad_pushfail)" 'credit-push failed after rebase-retry')"
ok "failed credit push leaves no stuck rebase state" "$([ ! -d "$(rd sc_ad_pushfail)/.git/rebase-merge" ] && [ ! -d "$(rd sc_ad_pushfail)/.git/rebase-apply" ] && echo 1 || echo 0)"
run sc_ad_commitfail
ok "credit commit failing (hook) -> nothing pushed, still returns no-op(ALREADY-DONE)" "$([ "$(res sc_ad_commitfail)" = 'no-op(ALREADY-DONE)' ] && ! git -C "$(og sc_ad_commitfail)" rev-parse -q --verify ovn/t1 >/dev/null && echo 1 || echo 0)"
kb "log must not claim 'credited already-done item' when the credit commit failed (run_overnight.sh ~line 1640 echoes unconditionally)" "$(b2i "$(has "$(tlog sc_ad_commitfail)" 'credited already-done item')")"
run sc_credit_changes
ok "any-verdict already-satisfied credit: CREDITED>=1 -> commit + push" "$(git -C "$(og sc_credit_changes)" log ovn/t1 --format=%s | grep -q 'credit already-satisfied item (scout verdict path)' && echo 1 || echo 0)"
run sc_credit_nochange
ok "CREDITED>=1 but nothing staged: commit fails, nothing pushed, verdict still reported" "$([ "$(has "$(res sc_credit_nochange)" 'no-op(NEEDS-DECISION)')" = 1 ] && ! git -C "$(og sc_credit_nochange)" rev-parse -q --verify ovn/t1 >/dev/null && echo 1 || echo 0)"
# KNOWN-BUG: a failed `git commit -q` (nothing to commit) still prints 'On branch ...' to STDOUT, which is the function's status string.
kb "status string is exactly 'no-op(NEEDS-DECISION)' even when the verdict-path credit commit has nothing to commit (run_overnight.sh: git commit -q ... 2>>\"\$task_log\" leaks git's stdout)" "$([ "$(res sc_credit_nochange)" = 'no-op(NEEDS-DECISION)' ] && echo 1 || echo 0)"
run sc_credit_pushfail
ok "verdict-path credit push failure is logged, status unaffected" "$([ "$(has "$(tlog sc_credit_pushfail)" 'credit-push failed after rebase-retry')" = 1 ] && [ "$(res sc_credit_pushfail)" = 'no-op(BLOCKED)' ] && echo 1 || echo 0)"

echo "== PROCEED: ungrounded plan, force-loading, prompt building =="
run sc_ungrounded
ok "PROCEED naming zero file tokens -> no-op(ungrounded-plan), implement skipped" "$([ "$(res sc_ungrounded)" = 'no-op(ungrounded-plan)' ] && [ ! -f "$T/sc_ungrounded/scn/calls/2.impl" ] && echo 1 || echo 0)"
run sc_forceload
ok "plan file beyond the scan budget is force-loaded" "$(has "$(tlog sc_forceload)" 'force-loaded PLAN target file: app/foo.py')"
ok "protected file named in the plan is never loaded" "$(b2i "$(hasline "$(implcall sc_forceload)" 'app/prot.py')")"
ok "protected file skip is logged" "$(has "$(tlog sc_forceload)" 'skipping protected file mentioned in log: app/prot.py')"
ok ".md file in the plan is not loaded as --file" "$(b2i "$(hasline "$(implcall sc_forceload)" 'README.md')")"
ok "implement prompt wraps the scout plan ('Your plan: ...')" "$(has "$(implcall sc_forceload)" 'Your plan: change app/bar.py')"
run sc_multifile_no
ok "multifile:no disables log scanning but the plan files are still force-loaded" "$([ "$(has "$(tlog sc_multifile_no)" 'force-loaded PLAN target file: app/bar.py')" = 1 ] && [ "$(has "$(tlog sc_multifile_no)" 'force-loaded PLAN target file: app/foo.py')" = 1 ] && echo 1 || echo 0)"
run sc_ident_fallback
t="$(tlog sc_ident_fallback)"
ok "guessed plan file missing: real definition of a backticked identifier is force-loaded" "$(has "$t" 'force-loaded real definition of `compute_total`')"
ok "second identifier defined in the SAME file is not loaded twice" "$(b2i "$(has "$t" 'real definition of `other_helper`')")"
ok "identifier defined only in a protected file is skipped" "$(b2i "$(has "$t" 'real definition of `guarded_fn`')")"
ok "identifier defined only under tests/ is skipped" "$(b2i "$(has "$t" 'real definition of `only_in_tests`')")"
ok "fallback rescues the otherwise-ungrounded plan: implement runs" "$([ -f "$T/sc_ident_fallback/scn/calls/2.impl" ] && echo 1 || echo 0)"
run sc_proceed_plan
ok "PROCEED with a real plan file reaches the implement call with the file pre-loaded" "$(has "$(implcall sc_proceed_plan)" 'app/foo.py')"
run sc_lastfail
ok "lastfail memory for the SAME item is injected into the implement prompt" "$(has "$(implcall sc_lastfail)" 'the previous attempt broke test_foo')"
run sc_lastfail_mismatch
ok "lastfail note whose embedded hash mismatches is NOT injected" "$(b2i "$(has "$(implcall sc_lastfail_mismatch)" 'stale note')")"
run sc_architect
ok "OVN_ARCHITECT=1 + refactor item -> --architect args" "$(has "$(implcall sc_architect)" '--architect')"
run sc_autotest
ok "package.json present -> --auto-test wired into the implement call" "$([ "$(has "$(implcall sc_autotest)" '--auto-test')" = 1 ] && [ "$(has "$(tlog sc_autotest)" 'auto-test enabled')" = 1 ] && echo 1 || echo 0)"
run sc_progress_tail
ok "oversized progress log -> budget-limited tail file fed via --read" "$([ -f /tmp/ovn_progress_tail_ro_aider1_repo.md ] && [ "$(has "$(implcall sc_progress_tail)" 'ovn_progress_tail_ro_aider1_repo.md')" = 1 ] && echo 1 || echo 0)"
ok "tail file guarantees the doable item and hides the literal log filename" "$([ "$(has "$(cat /tmp/ovn_progress_tail_ro_aider1_repo.md)" 'fix the foo handling')" = 1 ] && [ "$(b2i "$(has "$(cat /tmp/ovn_progress_tail_ro_aider1_repo.md)" 'OVERNIGHT_PROGRESS.md')")" = 1 ] && echo 1 || echo 0)"
rm -f /tmp/ovn_progress_tail_ro_aider1_repo.md
run sc_no_progress
ok "repo with no progress log still runs scout+implement (no --read of it)" "$([ -f "$T/sc_no_progress/scn/calls/2.impl" ] && [ "$(b2i "$(has "$(implcall sc_no_progress)" 'OVERNIGHT_PROGRESS.md')")" = 1 ] && echo 1 || echo 0)"
run sc_nolib
ok "without lib_item_select helpers the inline top-item/hash fallbacks still reach the implement call" "$([ "$(has "$(implcall sc_nolib)" 'app/foo.py')" = 1 ] && echo 1 || echo 0)"
run sc_skip_agents
ok "skip_agents_md=true omits CLAUDE.md/AGENTS.md; explicit map_tokens honored" "$([ "$(b2i "$(has "$(scoutcall sc_skip_agents)" 'CLAUDE.md')")" = 1 ] && [ "$(has "$(scoutcall sc_skip_agents)" '4096')" = 1 ] && echo 1 || echo 0)"

echo "== DELETE-EXECUTOR =="
run de_pass
ok "OK + green verify: deleted, credited, pushed -> 'pushed(tests:pass) delete-executor'" "$([ "$(res de_pass)" = 'pushed(tests:pass) delete-executor' ] && [ ! -f "$(rd de_pass)/app/dead_mod.py" ] && echo 1 || echo 0)"
ok "progress item credited on origin" "$(has "$(git -C "$(og de_pass)" show main:OVERNIGHT_PROGRESS.md)" '- [x] (deleted by delete-executor, verified) [T1] app/dead_mod.py')"
ok "executor path never calls aider" "$([ ! -d "$T/de_pass/scn/calls" ] && echo 1 || echo 0)"
run de_push_retry
ok "direct push rejected -> pull --rebase + push succeeds" "$([ "$(res de_push_retry)" = 'pushed(tests:pass) delete-executor' ] && git -C "$(og de_push_retry)" log main --format=%s | grep -q '^adv$' && git -C "$(og de_push_retry)" log main --format=%s | grep -q 'credit deterministic delete' && echo 1 || echo 0)"
run de_fail
ok "red verification: reverted, file back, falls through to the normal scout path" "$([ -f "$(rd de_fail)/app/dead_mod.py" ] && [ -f "$T/de_fail/scn/calls/1.scout" ] && echo 1 || echo 0)"
ok "red verification: failure remembered once per item" "$([ -n "$(ls "$T/de_fail/sd/state/delete_exec_failed" 2>/dev/null)" ] && echo 1 || echo 0)"
ok "red verification: nothing pushed to origin" "$(git -C "$(og de_fail)" show main:app/dead_mod.py >/dev/null 2>&1 && echo 1 || echo 0)"
run de_skip
ok "skipped verification: reverted, NOT remembered as failed" "$([ -f "$(rd de_skip)/app/dead_mod.py" ] && [ -z "$(ls "$T/de_skip/sd/state/delete_exec_failed" 2>/dev/null)" ] && echo 1 || echo 0)"
run de_push_fail
ok "push fails even after rebase retry: reset to BEFORE_SHA, remembered, normal path continues" "$([ -f "$(rd de_push_fail)/app/dead_mod.py" ] && [ -n "$(ls "$T/de_push_fail/sd/state/delete_exec_failed" 2>/dev/null)" ] && [ -f "$T/de_push_fail/scn/calls/1.scout" ] && echo 1 || echo 0)"
ok "failed push leaves no stuck rebase" "$([ ! -d "$(rd de_push_fail)/.git/rebase-merge" ] && [ ! -d "$(rd de_push_fail)/.git/rebase-apply" ] && echo 1 || echo 0)"
run de_commit_fail
ok "git rm ok but commit hook fails: reset, file restored, not remembered, falls through" "$([ -f "$(rd de_commit_fail)/app/dead_mod.py" ] && [ -z "$(ls "$T/de_commit_fail/sd/state/delete_exec_failed" 2>/dev/null)" ] && [ -f "$T/de_commit_fail/scn/calls/1.scout" ] && echo 1 || echo 0)"
run de_skip_line
ok "executor SKIP (function removal, not a whole-file delete): falls through to scout" "$([ -f "$(rd de_skip_line)/app/foo.py" ] && [ -f "$T/de_skip_line/scn/calls/1.scout" ] && echo 1 || echo 0)"
run de_failed_memory
ok "item already in delete_exec_failed/: executor not retried (file kept)" "$([ -f "$(rd de_failed_memory)/app/dead_mod.py" ] && [ -f "$T/de_failed_memory/scn/calls/1.scout" ] && echo 1 || echo 0)"
run de_off
ok "OVN_DELETE_EXECUTOR=off disables the block" "$([ -f "$(rd de_off)/app/dead_mod.py" ] && [ -f "$T/de_off/scn/calls/1.scout" ] && echo 1 || echo 0)"
run de_noitem
ok "no eligible top item for the executor: block is a no-op, scout still runs" "$([ -f "$T/de_noitem/scn/calls/1.scout" ] && echo 1 || echo 0)"

echo "  $pass passed, $fail failed${warn:+, $warn known-bug warning(s)}"
[ "$fail" = 0 ]
