#!/usr/bin/env bash
# Z2 (2026-11-07) stage-runner waste fixes (nov7 outcomes RC5), driving the REAL ovn_stage_runner.sh in the hermetic fixture (lib_osr_fixture.sh):
#  1. BUGFIX  scope_learn rejects junk tokens (a stray file `a` was 'scope extended'); OVN_STAGE_SCOPE_TOKEN_CHECK=off = old behaviour
#  2. SHADOW  OVN_STAGE_TIMEOUT_PARK=off|shadow|on : park after 2 timeouts on the same file set (12 timeouts = 70 min / 24h)
#  3. SHADOW  OVN_STAGE_EMPTY_WHOLE=off|shadow|on : retry an empty-file failure with --edit-format whole (no architect) instead of the same udiff+architect
# Needs GNU sed + bash 5 (run on the box).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_osr_fixture.sh"
if ! sed --version >/dev/null 2>&1; then echo "  SKIP: needs GNU sed; run on the box"; exit 0; fi
unset OVN_BUG_FIRST OVN_BUG_ATTEMPT_CAP OVN_STAGE_ZERO_CAP OVN_STAGE_SCOPE_LEARN OVN_STAGE_SAME_SIG_STOP OVN_STAGE_MAX_ATTEMPTS OVN_STAGE_SCOPE_TOKEN_CHECK OVN_STAGE_TIMEOUT_PARK OVN_STAGE_TIMEOUT_PARK_AT OVN_STAGE_EMPTY_WHOLE NTFY_SERVER NTFY_TOPIC
trap osr_cleanup EXIT
. "$REALQ/scripts/lib_item_select.sh" 2>/dev/null
G(){ grep -qF -- "$1" "$T/out.txt"; }
NG(){ ! grep -qF -- "$1" "$T/out.txt"; }
J(){ osr_jsonl | grep -F -- "$1" >/dev/null; }
nextrun(){ rm -f "$T/llm/n" "$T/scn/aider.n" "$T"/llm/body.* "$T"/scn/aider.args.*; }
SC_ITEM='[T3] backend/app/foo.py — Add foo helper with its test. VERIFY: `pytest backend/tests/test_foo.py` (cat:python; multifile:no)'
PLAN='[{"desc":"add foo helper","files":["backend/app/foo.py","backend/tests/test_foo.py"],"verify":"pytest backend/tests/test_foo.py"}]'
sc_setup(){ osr_new; osr_venv backend; cp "$REALQ/scripts/lib_item_select.sh" "$Q/scripts/" 2>/dev/null; osr_tracked a "x\n"; osr_progress "- [ ] $SC_ITEM"; osr_plan default "$PLAN"; osr_aider default "$SNIP_FOO
echo '# touched' >> a"; }

echo "== A: junk scope token (a tracked 1-char file named a) must never be learned"
sc_setup; OVN_STAGE_SCOPE_LEARN=on OVN_STAGE_REDECOMP=1 osr_run "$OSR_REPO"
t "A1 att 1 REJECTED (scope) for a" G "step 0 REJECTED (scope): touched undeclared file(s): a"
t "A2 the recurrence is 'cannot be learned (... not a plausible scope token ...)' and the step ABANDONED" bash -c "grep -q 'cannot be learned (a is not a plausible scope token' '$T/out.txt' && grep -q 'ABANDONED (scope-violation)' '$T/out.txt'"
t "A3 nothing persisted as the scope extension" bash -c "[ -z \"\$(ls '$Q'/state/item_fails/stage-$OSR_REPO.*.scopeext 2>/dev/null)\" ]"
osr_cleanup
echo "== A-kill: OVN_STAGE_SCOPE_TOKEN_CHECK=off is the old behaviour (junk is extended)"
sc_setup; OVN_STAGE_SCOPE_TOKEN_CHECK=off OVN_STAGE_SCOPE_LEARN=on OVN_STAGE_REDECOMP=0 osr_run "$OSR_REPO"
t "AK1 old behaviour: 'scope extended ... (a)'" G "scope extended: the same undeclared set recurred (a)"
osr_cleanup
echo "== A2: a junk token persisted earlier (pre-Z2 scopeext) is ignored when the scope is rebuilt"
sc_setup; h="$(ovn_item_hash "$SC_ITEM")"; mkdir -p "$Q/state/item_fails"; printf 'a\n' > "$Q/state/item_fails/stage-$OSR_REPO.$h.scopeext"
OVN_STAGE_SCOPE_LEARN=on OVN_STAGE_REDECOMP=0 OVN_STAGE_MAX_ATTEMPTS=1 osr_run "$OSR_REPO"
t "AP0 the seed is keyed by the hash the runner uses" bash -c "ls '$Q'/state/item_fails/stage-$OSR_REPO.$h.scopeext >/dev/null && ! ls '$Q'/state/item_fails/ | grep -q '^stage-$OSR_REPO\\.\\.'"
t "AP1 the stale junk extension no longer declares a: the step is still REJECTED (scope)" G "step 0 REJECTED (scope): touched undeclared file(s): a"
t "AP2 ... and does not land" G "DONE: 0/1 steps landed"
osr_cleanup
echo "== A3: plausible tokens still learn (regression guard for the guard)"
osr_new; osr_venv backend; cp "$REALQ/scripts/lib_item_select.sh" "$Q/scripts/" 2>/dev/null; osr_progress "- [ ] $SC_ITEM"; osr_plan default "$PLAN"; osr_aider default "$SNIP_FOO
echo '# touched' >> backend/app/svc.py"
OVN_STAGE_SCOPE_LEARN=on OVN_STAGE_REDECOMP=0 osr_run "$OSR_REPO"
t "AL1 backend/app/svc.py is still extended on recurrence" G "scope extended: the same undeclared set recurred (backend/app/svc.py)"
osr_cleanup

echo "== A4: a TRACKED path with shell/glob-special characters (Next/SvelteKit routes) is a plausible scope token and is learned verbatim"
osr_new; osr_venv backend; cp "$REALQ/scripts/lib_item_select.sh" "$Q/scripts/" 2>/dev/null; osr_tracked 'backend/app/(grp)/[id]$x.py' "x\n"; osr_tracked 'backend/app/(grp)/i$x.py' "x\n"; osr_progress "- [ ] $SC_ITEM"; osr_plan default "$PLAN"; osr_aider default "$SNIP_FOO
echo '# touched' >> 'backend/app/(grp)/[id]\$x.py'"
OVN_STAGE_SCOPE_LEARN=on OVN_STAGE_REDECOMP=0 osr_run "$OSR_REPO"
t "AB1 the tracked special-character path is extended on recurrence (not 'not a plausible scope token')" bash -c "grep -qF 'scope extended: the same undeclared set recurred (backend/app/(grp)/[id]\$x.py)' '$T/out.txt' && ! grep -q 'not a plausible scope token' '$T/out.txt'"
t "AB2 the persisted extension is the ONE literal path (never glob-expanded onto the tracked sibling backend/app/(grp)/i\$x.py)" bash -c "f=\"\$(ls '$Q'/state/item_fails/stage-$OSR_REPO.*.scopeext | head -1)\"; [ \"\$(wc -l < \"\$f\" | tr -d ' ')\" = 1 ] && grep -qxF 'backend/app/(grp)/[id]\$x.py' \"\$f\""
osr_cleanup

echo "== A5: tracked NON-ASCII path (git status quotes it as octal unless parsed with -z) is learned verbatim"
osr_new; osr_venv backend; cp "$REALQ/scripts/lib_item_select.sh" "$Q/scripts/" 2>/dev/null; NA='backend/app/café.py'; osr_tracked "$NA" "x\n"; osr_progress "- [ ] $SC_ITEM"; osr_plan default "$PLAN"; osr_aider default "$SNIP_FOO
echo '# touched' >> '$NA'"
OVN_STAGE_SCOPE_LEARN=on OVN_STAGE_REDECOMP=0 osr_run "$OSR_REPO"
t "AN1 att 1 reports the real UTF-8 name, not octal escapes" bash -c "grep -qF 'touched undeclared file(s): $NA' '$T/out.txt' && ! grep -q '\\\\303' '$T/out.txt'"
t "AN2 the recurrence extends the scope by the non-ASCII path (not 'not an existing tracked file')" bash -c "grep -qF 'scope extended: the same undeclared set recurred ($NA)' '$T/out.txt' && ! grep -q 'not an existing tracked file' '$T/out.txt'"
osr_cleanup
echo "== A6: tracked path WITH A SPACE is one token (awk \$2 cut it at the space)"
osr_new; osr_venv backend; cp "$REALQ/scripts/lib_item_select.sh" "$Q/scripts/" 2>/dev/null; SP='backend/app/my mod.py'; osr_tracked "$SP" "x\n"; osr_progress "- [ ] $SC_ITEM"; osr_plan default "$PLAN"; osr_aider default "$SNIP_FOO
echo '# touched' >> '$SP'"
OVN_STAGE_SCOPE_LEARN=on OVN_STAGE_REDECOMP=0 osr_run "$OSR_REPO"
t "AS1 the recurrence extends the scope by the WHOLE spaced path" bash -c "grep -qF 'scope extended: the same undeclared set recurred ($SP)' '$T/out.txt' && grep -qxF '$SP' \"\$(ls '$Q'/state/item_fails/stage-$OSR_REPO.*.scopeext | head -1)\""
osr_cleanup
echo "== A7: glob metacharacters stay literal: a DECOY matching the pattern in the runner's cwd must never be learned in place of the tracked path"
osr_new; osr_venv backend; cp "$REALQ/scripts/lib_item_select.sh" "$Q/scripts/" 2>/dev/null; GP='backend/app/(grp)/[id]$x.py'; osr_tracked "$GP" "x\n"
mkdir -p "$Q/backend/app/(grp)"; : > "$Q/backend/app/(grp)/i\$x.py"   # a file in the cwd the runner runs in that an unquoted pattern would match
osr_progress "- [ ] $SC_ITEM"; osr_plan default "$PLAN"; osr_aider default "$SNIP_FOO
echo '# touched' >> '$GP'"
OVN_STAGE_SCOPE_LEARN=on OVN_STAGE_REDECOMP=0 osr_run "$OSR_REPO"
t "AG1 the recurrence extends by the literal pattern path, never the cwd decoy" bash -c "grep -qF 'scope extended: the same undeclared set recurred ($GP)' '$T/out.txt' && ! grep -qF 'i\$x.py' '$T/out.txt'"
osr_cleanup

# ---- timeouts: stub aider sleeps 3s with STEP_TIMEOUT=14 (hard-kill threshold = 14-12 = 2s) ----
to_setup(){ osr_new; osr_venv backend; cp "$REALQ/scripts/lib_item_select.sh" "$Q/scripts/" 2>/dev/null; osr_progress "- [ ] $SC_ITEM"; osr_plan default "$PLAN"; osr_aider default '/bin/sleep 3'; }
echo "== B: timeout park SHADOW (default): logs, changes nothing (old flow: 2 attempts, then re-decompose)"
to_setup; OVN_STAGE_STEP_TIMEOUT=14 OVN_STAGE_REDECOMP=1 osr_run "$OSR_REPO"
t "B1 two timeouts happened and the shadow line says it WOULD park" bash -c "[ \"\$(grep -c 'FAIL (timeout' '$T/out.txt')\" -ge 2 ] && grep -q 'timeout-park (shadow): would abandon the step after 2 timeouts' '$T/out.txt'"
t "B2 nothing was abandoned: the step still re-decomposes (old behaviour)" bash -c "grep -q 're-decomposing smaller' '$T/out.txt' && ! grep -q 'ABANDONED' '$T/out.txt'"
t "B3 journal: would_park_timeout row" J '"event":"would_park_timeout"'
osr_cleanup
echo "== B2: timeout park ON: the 2nd timeout of the same files abandons the step and escalates at once"
to_setup; OVN_STAGE_TIMEOUT_PARK=on OVN_STAGE_STEP_TIMEOUT=14 OVN_STAGE_REDECOMP=1 osr_run "$OSR_REPO"
t "C1 'timeout-park: 2 timeouts on the same file set' + ABANDONED (timeout), no re-decomposition" bash -c "grep -q 'timeout-park: 2 timeouts on the same file set' '$T/out.txt' && grep -q 'step 0 ABANDONED (timeout)' '$T/out.txt' && ! grep -q 're-decomposing smaller' '$T/out.txt'"
t "C2 only the one decompose LLM call was made" bash -c "[ \"\$(cat '$T/llm/n')\" = 1 ]"
t "C3 the item is escalated to Claude right away (1 attempt, not 3 cycles)" G "escalated to Claude (staged pipeline landed 0/1 - 1 attempts"
t "C4 journal: park_timeout row" J '"event":"park_timeout"'
osr_cleanup
echo "== B3: ON across cycles: 1 attempt per run; the 2nd run's timeout (2nd on the same files, persisted) parks"
to_setup; OVN_STAGE_TIMEOUT_PARK=on OVN_STAGE_MAX_ATTEMPTS=1 OVN_STAGE_STEP_TIMEOUT=14 OVN_STAGE_REDECOMP=0 osr_run "$OSR_REPO"
t "D1 run 1: first timeout only counts; the item stays OPEN" bash -c "grep -q 'attempt 1/3: item stays OPEN' '$T/out.txt' && ! grep -q 'timeout-park' '$T/out.txt'"
nextrun; OVN_STAGE_TIMEOUT_PARK=on OVN_STAGE_MAX_ATTEMPTS=1 OVN_STAGE_STEP_TIMEOUT=14 OVN_STAGE_REDECOMP=0 osr_run "$OSR_REPO"
t "D2 run 2: the second timeout parks and escalates (not 'attempt 2/3')" bash -c "grep -q 'timeout-park: 2 timeouts' '$T/out.txt' && grep -q 'escalated to Claude (staged pipeline landed 0/1 - 1 attempts' '$T/out.txt'"
osr_cleanup
echo "== B4: OFF changes nothing (no state, no log)"
to_setup; OVN_STAGE_TIMEOUT_PARK=off OVN_STAGE_STEP_TIMEOUT=14 OVN_STAGE_REDECOMP=0 osr_run "$OSR_REPO"
t "E1 OFF: no timeout-park line, no .timeouts state" bash -c "! grep -q 'timeout-park' '$T/out.txt' && [ -z \"\$(ls '$Q'/state/item_fails/stage-$OSR_REPO.*.timeouts 2>/dev/null)\" ]"
osr_cleanup

# ---- empty file -> whole-file edit format ----
SNIP_EMPTY_DECL='mkdir -p backend/app backend/tests
printf "def foo():\n    return 1\n" > backend/app/foo.py
: > backend/tests/test_foo.py
echo "Applied edit to backend/app/foo.py"'
ef_setup(){ osr_new; osr_venv backend; osr_progress "- [ ] $ITEM_PY"; osr_plan default "$PLAN"; osr_aider 1 "$SNIP_EMPTY_DECL"; osr_aider 2 "$SNIP_FOO"; }
echo "== F: empty-file retry SHADOW (explicit; also the default): logs only, retry keeps udiff + architect"
ef_setup; OVN_STAGE_EMPTY_WHOLE=shadow OVN_STAGE_REDECOMP=0 osr_run "$OSR_REPO"
t "F1 shadow line + journal row" bash -c "grep -q 'empty-file (shadow): would retry with --edit-format whole' '$T/out.txt'"
t "F2 journal: would_whole_retry" J '"event":"would_whole_retry"'
t "F3 the retry (aider call 2) still uses udiff and the architect" bash -c "grep -qx udiff '$T/scn/aider.args.2' && grep -qx -- --architect '$T/scn/aider.args.2' && ! grep -qx whole '$T/scn/aider.args.2'"
osr_cleanup
echo "== G0 (Z8b review): OVN_STAGE_EMPTY_WHOLE unset => the default is SHADOW (measured 33% = 15/45 for udiff+architect attempt 2; whole has no outcome data): the retry keeps udiff + architect"
unset OVN_STAGE_EMPTY_WHOLE; ef_setup; OVN_STAGE_REDECOMP=0 osr_run "$OSR_REPO"
t "G0 default: attempt 2 still uses udiff + architect, never whole" bash -c "grep -qx udiff '$T/scn/aider.args.2' && grep -qx -- --architect '$T/scn/aider.args.2' && ! grep -qx whole '$T/scn/aider.args.2'"
osr_cleanup
echo "== G: empty-file retry ON: attempt 2 uses --edit-format whole and no architect; attempt 1 is unchanged"
ef_setup; OVN_STAGE_EMPTY_WHOLE=on OVN_STAGE_REDECOMP=0 osr_run "$OSR_REPO"
t "G1 attempt 1: udiff + architect (unchanged)" bash -c "grep -qx udiff '$T/scn/aider.args.1' && grep -qx -- --architect '$T/scn/aider.args.1'"
t "G2 attempt 2: --edit-format whole, no --architect, no udiff" bash -c "grep -A1 -x -- --edit-format '$T/scn/aider.args.2' | grep -qx whole && ! grep -qx -- --architect '$T/scn/aider.args.2' && ! grep -qx udiff '$T/scn/aider.args.2'"
t "G3 the step passes on attempt 2 and the run lands 1/1" bash -c "grep -q 'step 0 PASS (att 2' '$T/out.txt' && grep -q 'DONE: 1/1 steps landed' '$T/out.txt'"
t "G4 journal: whole_retry" J '"event":"whole_retry"'
osr_cleanup
echo "== H: no empty-file failure -> the format never changes even with ON"
osr_new; osr_venv backend; osr_progress "- [ ] $ITEM_PY"; osr_plan default "$PLAN"; osr_aider default "$SNIP_FOO"
OVN_STAGE_EMPTY_WHOLE=on OVN_STAGE_REDECOMP=0 osr_run "$OSR_REPO"
t "H1 a clean pass uses udiff+architect and never logs whole_retry" bash -c "grep -qx udiff '$T/scn/aider.args.1' && grep -qx -- --architect '$T/scn/aider.args.1' && ! grep -q 'whole' '$T/out.txt'"
osr_cleanup
osr_summary
