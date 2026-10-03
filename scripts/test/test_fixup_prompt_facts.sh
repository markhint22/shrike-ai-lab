#!/usr/bin/env bash
# QA harness-X X3 (2026-10-02): fix-up prompts are built from FACTS, never "your last change".
# Incident: the Tier-2 / BUILD-GATE / MIGRATION fix-ups told a FRESH aider session "the test suite is failing after your last change: <summary>".
# With no memory of any change, the 27B grabbed aider's built-in udiff example (replace is_prime with sympy in mathweb/flask/app.py) as "its
# previous change" and stalled: 7 of 7 fix-ups on 2026-10-02 were wasted, 6 of 7 logs carry the is_prime contamination
# (logs/20261002-121658/ongoing-iptv-apps.log ~663-792). Part 1 drives the lib functions; part 2 drives the real run_aider_fix_task and reads
# the message the stub aider actually received.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_ro_aider2_fixture.sh"
[ -f "$Q/scripts/lib_fixup_prompt.sh" ] && . "$Q/scripts/lib_fixup_prompt.sh"

# ---------------- part 1: lib functions ----------------
if ! declare -F ovn_fixup_prompt >/dev/null; then F=$((F+1)); echo "  FAIL: ovn_fixup_prompt() does not exist (old code): part 1 cannot run"; else
R="$W/fp"; rm -rf "$R"; mkdir -p "$R/src" "$R/tests"; cd "$R" || exit 1
git init -q -b main . && git config user.email t@t && git config user.name t
printf 'def total(xs):\n    return sum(xs)\n' > src/calc.py
printf 'from src.calc import total\n\ndef test_total():\n    assert total([1, 2]) == 3\n' > tests/test_calc.py
printf '# Progress\n- [ ] item\n' > OVERNIGHT_PROGRESS.md
git add -A; git commit -q -m base; B="$(git rev-parse HEAD)"
printf 'def total(xs):\n    return sum(xs) + 1   # the committed behaviour change\n' > src/calc.py
printf '# Progress\n- [x] item\n' > OVERNIGHT_PROGRESS.md
git add -A; git commit -q -m change; A="$(git rev-parse HEAD)"
LOG="$R/task.log"
{ for i in $(seq 1 900); do echo "aider noise line $i is_prime sympy mathweb"; done
  echo "FAILED tests/test_calc.py::test_total - assert 4 == 3"
  echo "E       assert 4 == 3"
  echo "E        +  where 4 = total([1, 2])"
} > "$LOG"
EV="$(ovn_fixup_failure_facts "$LOG" "SUMMARY-FALLBACK")"
MSG="$(ovn_fixup_prompt "The test suite is failing after the change below was committed." "$B" "$A" "$EV" "Fix this SPECIFIC failure.")"

ok "P1: prompt carries the committed diff (added line)" 'printf "%s" "$MSG" | grep -qF "+    return sum(xs) + 1   # the committed behaviour change"'
ok "P1: prompt carries the diff header with the file name" 'printf "%s" "$MSG" | grep -qF "src/calc.py"'
ok "P1: prompt carries the failing test id" 'printf "%s" "$MSG" | grep -qF "FAILED tests/test_calc.py::test_total"'
ok "P1: prompt carries the failing assertion line" 'printf "%s" "$MSG" | grep -qF "E       assert 4 == 3"'
ok "P1: prompt says the change 'was just committed'" 'printf "%s" "$MSG" | grep -qF "was just committed"'
ok "P1: prompt NEVER says 'your last change'" '! printf "%s" "$MSG" | grep -qi "your last change"'
ok "P1: prompt tells the model to ignore the is_prime/sympy/mathweb example" 'printf "%s" "$MSG" | grep -qi "ignore any example" && printf "%s" "$MSG" | grep -q "is_prime" && printf "%s" "$MSG" | grep -q "sympy" && printf "%s" "$MSG" | grep -q "mathweb"'
ok "P1: bookkeeping file diff is not in the prompt" '! printf "%s" "$MSG" | grep -q "OVERNIGHT_PROGRESS"'
ok "P1: log noise ('aider noise line') is not copied into the evidence" '! printf "%s" "$EV" | grep -q "aider noise"'
eq "P1: no failure lines in the log -> falls back to the summary" "$(ovn_fixup_failure_facts "$R/none.log" "SUMMARY-FALLBACK")" "SUMMARY-FALLBACK"

# size caps: a huge diff stays within the budget; per-file truncation marker; omitted files are named
mkdir -p big; for i in $(seq 1 40); do seq 1 3000 | sed "s/^/line $i /" > "big/f$i.txt"; done
git add -A; git commit -q -m big; A2="$(git rev-parse HEAD)"
BIG="$(ovn_fixup_prompt "H" "$A" "$A2" "$EV" "I")"
ok "P2: a 40x3000-line diff keeps the whole prompt under 18000 chars (was unbounded)" '[ "${#BIG}" -lt 18000 ]'
ok "P2: per-file truncation is announced" 'printf "%s" "$BIG" | grep -q "truncated:"'
ok "P2: files cut for size are named, never silently dropped" 'printf "%s" "$BIG" | grep -q "diff omitted for size"'
ok "P2: a long single line is clipped (minified blob)" '[ "$(printf "%s" "$BIG" | awk "{ if (length(\$0) > m) m = length(\$0) } END { print m }")" -le 400 ]'
head -c 30000 /dev/zero | tr '\0' x > min.js.txt; git add -A; git commit -q -m min; A3="$(git rev-parse HEAD)"
MIN="$(ovn_fixup_prompt "H" "$A2" "$A3" "$EV" "I")"
ok "P2: a 30k-char single-line file cannot blow the budget" '[ "${#MIN}" -lt 6000 ]'

# failing test files + the pre-load budget
ok "P3: failing test file is found from the FAILED id" '[ "$(ovn_fixup_failing_test_files "$LOG")" = "tests/test_calc.py" ]'
ok "P3: already-listed file is not offered twice" '[ -z "$(ovn_fixup_extra_files "$LOG" tests/test_calc.py src/calc.py)" ]'
ok "P3: not-yet-listed failing file is offered" '[ "$(ovn_fixup_extra_files "$LOG" src/calc.py)" = "tests/test_calc.py" ]'
ok "P3: byte budget exhausted -> not offered" '[ -z "$(OVN_FIXUP_FILES_BYTES=10 ovn_fixup_extra_files "$LOG" src/calc.py)" ]'
mkdir -p backend/tests; cp tests/test_calc.py backend/tests/test_calc.py; git add backend/tests/test_calc.py
echo "FAILED tests/test_calc.py::test_x - e" > "$R/l2.log"; git rm -rqf tests
ok "P3: pytest-relative path resolves to the repo path (backend/tests/...)" '[ "$(ovn_fixup_failing_test_files "$R/l2.log")" = "backend/tests/test_calc.py" ]'
ok "P3: id naming a file that does not exist is ignored" '[ -z "$(echo "FAILED nope/test_ghost.py::t" > "$R/l3.log"; ovn_fixup_failing_test_files "$R/l3.log")" ]'
fi

# ---------------- part 2: end to end, the message aider really receives ----------------
cd "$W" || exit 1
msg_of() { grep -v '^--' "$CASE_DIR/aider.args.$1" 2>/dev/null | tr '\n' ' '; }   # all args, one blob

# Tier-2: a red test that EXISTED before (tests/test_app.py is not in the commit)
mk_case fp_t2; scout_ok
aplan 2 'gc app.py "def t2(): return 1" "feat: t2 marker line"'
vplan 1 'echo "FAILED tests/test_app.py::test_app - assert 1 == 2"; echo "E       assert 1 == 2"; exit 1'
echo "tests/test_app.py::test_app - assert 1 == 2" > "$CASE_DIR/extract.out"
aplan 3 'gc tests/test_app.py "# adjust" "fix(test): adjust"'
run_case
MSG2="$(msg_of 3)"
ok "E2E Tier-2: fix-up ran" 'logged "Tier-2 fix-up: one bounded attempt"'
ok "E2E Tier-2: message contains the committed diff" 'printf "%s" "$MSG2" | grep -qF "def t2(): return 1"'
ok "E2E Tier-2: message contains the failing test id + assertion" 'printf "%s" "$MSG2" | grep -qF "FAILED tests/test_app.py::test_app" && printf "%s" "$MSG2" | grep -qF "E       assert 1 == 2"'
ok "E2E Tier-2: message says 'was just committed', never 'your last change'" 'printf "%s" "$MSG2" | grep -qF "just committed" && ! printf "%s" "$MSG2" | grep -qi "your last change"'
ok "E2E Tier-2: message carries the ignore-the-example line" 'printf "%s" "$MSG2" | grep -qi "ignore any example from your instructions"'
ok "E2E Tier-2: the changed source file is pre-loaded" 'grep -qx "app.py" "$CASE_DIR/aider.args.3"'
ok "E2E Tier-2: the failing (older) test file is pre-loaded too" 'grep -qx "tests/test_app.py" "$CASE_DIR/aider.args.3"'
ok "E2E Tier-2: prompt size is logged" 'logged "Tier-2 fix-up: prompt="'
ok "E2E Tier-2: whole message stays small (< 6000 chars)" '[ "$(grep -v "^--" "$CASE_DIR/aider.args.3" | wc -c)" -lt 6000 ]'

# BUILD-GATE
mk_case fp_build; scout_ok
aplan 2 'gc app.py "def broken(:" "feat: breaks build"'
vplan 1 'echo "app.py:3: SyntaxError: invalid syntax"; exit 1'
aplan 3 'echo "def broken(): pass" > app.py; git add -A; git commit -q -m "fix: parse error"'
run_case
MSGB="$(msg_of 3)"
ok "E2E BUILD-GATE: fix-up ran" 'logged "BUILD-GATE fix-up: one bounded attempt"'
ok "E2E BUILD-GATE: message contains the committed diff" 'printf "%s" "$MSGB" | grep -qF "def broken(:"'
ok "E2E BUILD-GATE: message keeps the verbatim failing output" 'printf "%s" "$MSGB" | grep -qF "app.py:3: SyntaxError: invalid syntax" && printf "%s" "$MSGB" | grep -qF "REAL failing output"'
ok "E2E BUILD-GATE: 'was just committed', never 'your last change'" 'printf "%s" "$MSGB" | grep -qF "just committed" && ! printf "%s" "$MSGB" | grep -qi "your last change"'
ok "E2E BUILD-GATE: ignore-the-example line present" 'printf "%s" "$MSGB" | grep -qi "ignore any example from your instructions"'

# MIGRATION-SAFETY
mk_case fp_mig; scout_ok
aplan 2 'gc backend/alembic/versions/0002_x.py "revision = \"0002\"" "feat(db): add migration"'
printf 'rc=1\n  ✗ MIGRATION FORK: two heads\nMULTIPLE HEADS: 0001, 0002\n' > "$CASE_DIR/mig.1"
printf 'rc=0\nok\n' > "$CASE_DIR/mig.2"
aplan 3 'echo "down_revision = \"0001\"" >> backend/alembic/versions/0002_x.py; git add -A; git commit -q -m "fix(db): linearize"'
run_case
MSGM="$(msg_of 3)"
ok "E2E MIGRATION: fix-up ran" 'logged "MIGRATION-SAFETY fix-up: one bounded attempt"'
ok "E2E MIGRATION: message contains the committed migration diff" 'printf "%s" "$MSGM" | grep -qF "revision = \"0002\""'
ok "E2E MIGRATION: message keeps the structured check output" 'printf "%s" "$MSGM" | grep -qF "MULTIPLE HEADS"'
ok "E2E MIGRATION: 'just committed', never 'your last change'" 'printf "%s" "$MSGM" | grep -qF "just committed" && ! printf "%s" "$MSGM" | grep -qi "your last change"'

# static: no prompt in run_overnight.sh still says "your last change"
ok "WIRING: run_overnight.sh has no 'your last change' prompt left" '! grep -qi "your last change" "$Q/run_overnight.sh"'
ok "WIRING: lib_fixup direction text no longer says 'your change'" '! grep -qi "your change" "$Q/scripts/lib_fixup.sh"'

summary
