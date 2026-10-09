#!/usr/bin/env bash
# QA harness-X X1 (2026-10-02): the runner's per-file AUTO-CREDIT may tick an item only when
#   the touched path EQUALS the item's named path, the file is real work (not a 0/0 add, not a placeholder stub), the item's own VERIFY: clause
#   exists, is safe, and PASSES, the tree equals the cycle's AFTER_SHA, and the tick commit stages ONLY OVERNIGHT_PROGRESS.md.
# Incidents this encodes: test-automation-agent T1/T2 "stop the sync Anthropic client" ticked by unrelated commits (VERIFY still fails);
# billwatch ticked an `articles.py` item because article_relevance.py changed (the cycle had committed a placeholder routers/articles.py);
# the 13:14 CDT billwatch chore commit that swept a half-restored tree into history.
# Part 1 drives the real ovn_auto_credit() against throwaway git repos; part 2 drives the real run_aider_fix_task() end to end (stub aider).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_ro_aider2_fixture.sh"
export OVN_VERIFY_SHADOW_LOG="$W/shadow.log"
[ -f "$Q/scripts/lib_auto_credit.sh" ] && . "$Q/scripts/lib_auto_credit.sh"

# ---------------- part 1: the real function on fixture repos ----------------
if ! declare -F ovn_auto_credit >/dev/null; then F=$((F+1)); echo "  FAIL: ovn_auto_credit() does not exist (old code): part 1 cannot run"; else
# mk1 <name>: repo with src/a.py src/b.py src/article_relevance.py backend/tests/test_x.py; BEFORE sha in $B1. Progress items are the incident shapes.
mk1() {
  R1="$W/p1/$1"; rm -rf "$R1"; mkdir -p "$R1/src" "$R1/backend/tests"; cd "$R1" || exit 1
  git init -q -b main . && git config user.email t@t && git config user.name t
  printf 'def old_a():\n    return 1\n' > src/a.py
  printf 'client = SyncAnthropic()\n' > src/b.py
  printf 'def rel():\n    return 1\n' > src/article_relevance.py
  printf 'def test_x():\n    assert True\n' > backend/tests/test_x.py
  cat > OVERNIGHT_PROGRESS.md <<'EOP'
## Next Steps
- [ ] [T2] src/a.py — Add new_a. VERIFY: `grep -q "def new_a" src/a.py`
- [ ] [T2] src/b.py — Stop the sync Anthropic client. VERIFY: `grep -q "AsyncAnthropic" src/b.py`
- [ ] [T2] src/articles.py — Create the articles router. VERIFY: `true`
- [ ] [T2] src/novfy.py — Add novfy with no verify clause at all.
- [ ] [T2] src/unsafe.py — Add unsafe. VERIFY: `curl http://example.invalid/x`
- [ ] [T2] tests/test_x.py — Cover x. VERIFY: `grep -q "def test_y" backend/tests/test_x.py`
- [ ] [T2] src/mutate.py — Mutator. VERIFY: `rm src/mutate.py; true`

## Completed
EOP
  git add -A && git commit -q -m base; B1="$(git rev-parse HEAD)"
}
commit1() { git add -A && git commit -q -m "$1"; A1="$(git rev-parse HEAD)"; }
prog_line() { grep -E "$1" OVERNIGHT_PROGRESS.md | head -1; }
call() { : > "$R1/task.log"; ovn_auto_credit "$B1" "$A1" OVERNIGHT_PROGRESS.md "$R1/task.log" 2>/dev/null; CRC=$?; CLOG="$(cat "$R1/task.log")"; }

# 1. everything agrees -> credits, and the tick commit touches ONLY the progress file
mk1 agree; printf 'def new_a():\n    return 2\n' >> src/a.py; commit1 "feat: new_a"
call
eq "agree: rc 0" "$CRC" 0
ok "agree: the src/a.py item is ticked" 'prog_line "src/a.py" | grep -q "^- \[x\]"'
eq "agree: exactly one item ticked" "$(grep -c '^- \[x\]' OVERNIGHT_PROGRESS.md)" 1
eq "agree: tick commit is a new commit on top of AFTER" "$(git rev-parse HEAD~1)" "$A1"
eq "agree: tick commit stages ONLY OVERNIGHT_PROGRESS.md" "$(git show --name-only --format= HEAD | tr '\n' ' ')" "OVERNIGHT_PROGRESS.md "
eq "agree: OVN_AC_NEWHEAD is HEAD" "$OVN_AC_NEWHEAD" "$(git rev-parse HEAD)"
ok "agree: log says VERIFY passed" 'printf "%s" "$CLOG" | grep -q "VERIFY passed for line 2"'
ok "agree: the other items are untouched" 'prog_line "src/b.py" | grep -q "^- \[ \]"'
ok "agree: worktree clean after" '[ -z "$(git status --porcelain --untracked-files=no)" ]'

# 2. the item's VERIFY still fails (TAA T1/T2 shape): an unrelated edit to the named file must NOT credit it
mk1 verifyfail; printf '# unrelated comment\n' >> src/b.py; commit1 "chore: touch b"
call
ok "verify-fail: item stays open" 'prog_line "src/b.py" | grep -q "^- \[ \]"'
eq "verify-fail: no commit made" "$(git rev-parse HEAD)" "$A1"
ok "verify-fail: refusal logged with the reason" 'printf "%s" "$CLOG" | grep -q "line 3.*VERIFY: clause FAILED"'
# benign twin: the same file but the VERIFY now holds -> credits
mk1 verifyok; printf 'client = AsyncAnthropic()\n' > src/b.py; commit1 "fix: async client"
call
ok "verify-pass twin: credits the same item" 'prog_line "src/b.py" | grep -q "^- \[x\]"'

# 3. path mismatch (billwatch article_relevance.py vs articles.py item): never credit
mk1 mismatch; printf 'def rel2():\n    return 2\n' >> src/article_relevance.py; commit1 "feat: relevance"
call
ok "mismatch: the articles.py item stays open even though its VERIFY is a trivially-true 'true'" 'prog_line "src/articles.py" | grep -q "^- \[ \]"'
eq "mismatch: nothing ticked" "$(grep -c '^- \[x\]' OVERNIGHT_PROGRESS.md)" 0
eq "mismatch: no commit" "$(git rev-parse HEAD)" "$A1"
# path normalisation (benign): item says tests/test_x.py, commit touched backend/tests/test_x.py
mk1 normalise; printf 'def test_y():\n    assert True\n' >> backend/tests/test_x.py; commit1 "test: y"
call
ok "normalise: tests/test_x.py item credits for backend/tests/test_x.py" 'prog_line "tests/test_x.py" | grep -q "^- \[x\]"'

# 4. tree differs from AFTER -> refuse (unstaged edit, staged edit, wrong HEAD)
mk1 dirty_unstaged; printf 'def new_a():\n    return 2\n' >> src/a.py; commit1 "feat: new_a"; printf 'half\n' >> src/b.py
call
eq "dirty tree: rc 1 (refused)" "$CRC" 1
ok "dirty tree: nothing ticked" '[ "$(grep -c "^- \[x\]" OVERNIGHT_PROGRESS.md)" = 0 ]'
eq "dirty tree: no commit made" "$(git rev-parse HEAD)" "$A1"
ok "dirty tree: refusal names the offending path" 'printf "%s" "$CLOG" | grep -q "REFUSED - working tree/index differ.*src/b.py"'
mk1 dirty_staged; printf 'def new_a():\n    return 2\n' >> src/a.py; commit1 "feat: new_a"; git checkout -q "$B1" -- src/article_relevance.py src/b.py; printf 'x\n' >> src/b.py; git add src/b.py
call
eq "half-restored INDEX (the 13:14 incident shape): rc 1" "$CRC" 1
eq "half-restored INDEX: HEAD unchanged, nothing swept into a commit" "$(git rev-parse HEAD)" "$A1"
ok "half-restored INDEX: the staged path is still just staged (we did not touch it)" 'git diff --cached --name-only | grep -qx src/b.py'
mk1 wrong_head; printf 'def new_a():\n    return 2\n' >> src/a.py; commit1 "feat: new_a"; printf 'z\n' > extra.txt; git add extra.txt; git commit -q -m later
call
eq "HEAD != AFTER: rc 1" "$CRC" 1
# benign: untracked droppings (aider/pytest) do not block
mk1 untracked; printf 'def new_a():\n    return 2\n' >> src/a.py; commit1 "feat: new_a"; mkdir -p .pytest_cache; echo x > .pytest_cache/f; echo y > scratch.tmp
call
eq "untracked files are ignored: rc 0 and credited" "$CRC:$(grep -c '^- \[x\]' OVERNIGHT_PROGRESS.md)" "0:1"
ok "untracked files never get committed" '[ "$(git show --name-only --format= HEAD | grep -c "scratch.tmp\|pytest_cache")" = 0 ]'  # was: ! ... | grep -q (flaky/masking under pipefail: grep -q exits early, SIGPIPE flips the negation)

# 5. placeholder stubs are never credited
mk1 placeholder; printf '# Placeholder - the implement step fills this in\n' > src/articles.py; commit1 "feat: stub"
call
ok "placeholder: articles.py item stays open (VERIFY 'true' would pass)" 'prog_line "src/articles.py" | grep -q "^- \[ \]"'
ok "placeholder: refusal says placeholder" 'printf "%s" "$CLOG" | grep -q "only a placeholder stub"'
# benign twin: the same item with REAL content credits
mk1 realarticles; printf 'def list_articles():\n    return []\n' > src/articles.py; commit1 "feat: articles"
call
ok "real articles.py content credits the articles.py item" 'prog_line "src/articles.py" | grep -q "^- \[x\]"'

# 6. no VERIFY clause / unsafe VERIFY -> no credit, with the reason logged
mk1 noverify; printf 'def f():\n    return 1\n' > src/novfy.py; commit1 "feat: novfy"
call
ok "no VERIFY clause: not credited" 'prog_line "src/novfy.py" | grep -q "^- \[ \]"'
ok "no VERIFY clause: reason logged" 'printf "%s" "$CLOG" | grep -q "no VERIFY: clause"'
mk1 unsafe; printf 'def f():\n    return 1\n' > src/unsafe.py; commit1 "feat: unsafe"
call
ok "unsafe VERIFY (curl): not credited" 'prog_line "src/unsafe.py" | grep -q "^- \[ \]"'
ok "unsafe VERIFY: reason logged" 'printf "%s" "$CLOG" | grep -q "not safe to run"'

# 7. a VERIFY command that dirties the tree must not get committed: refuse and restore AFTER
mk1 mutate; printf 'def f():\n    return 1\n' > src/mutate.py; commit1 "feat: mutate"
call
eq "mutating VERIFY: rc 1" "$CRC" 1
eq "mutating VERIFY: tree restored to AFTER (HEAD)" "$(git rev-parse HEAD)" "$A1"
ok "mutating VERIFY: worktree clean again" '[ -z "$(git diff "$A1" --name-only)" ]'
ok "mutating VERIFY: nothing ticked" '[ "$(grep -c "^- \[x\]" OVERNIGHT_PROGRESS.md)" = 0 ]'

# 8. 0/0 empty add is not real work (the 2026-09-20 guard survives the rewrite)
mk1 empty; : > src/novfy.py; printf 'def f():\n    return 1\n' > src/mutate2.py; commit1 "feat: empty"
call
ok "empty 0/0 add skipped" 'printf "%s" "$CLOG" | grep -q "SKIPPED src/novfy.py"'

# 9. old substring behaviour is really gone: an item that only MENTIONS a touched file is not credited
mk1 mention; cat >> OVERNIGHT_PROGRESS.md <<'EOP'
- [ ] [T2] Wire the retry docs; touches src/a.py indirectly. VERIFY: `true`
EOP
git commit -qam "docs: more items"; B1="$(git rev-parse HEAD)"
printf 'def new_a():\n    return 2\n' >> src/a.py; commit1 "feat: new_a"
call
ok "mention-only item (no leading path) stays open" 'prog_line "Wire the retry docs" | grep -q "^- \[ \]"'

fi

# ---------------- part 2: end to end through the real run_aider_fix_task ----------------
cd "$W" || exit 1
ITEM='- [ ] app.py — Make hello return 2. VERIFY: `grep -q "return 2" app.py`'
mk_case e2e_credit; scout_ok
aplan 2 "gc OVERNIGHT_PROGRESS.md '$ITEM' 'docs: queue item'
printf 'def hello():\n    return 2\n' > app.py; git add -A; git commit -q -m 'feat: hello returns 2'"
run_case
ok "E2E credit: pushed(tests:pass)" '[[ "$OUT" == pushed\(tests:pass\)* ]]'
ok "E2E credit: item ticked on the pushed branch" 'git -C "$ORIGIN" show claude/feature:OVERNIGHT_PROGRESS.md | grep -q "^- \[x\] app.py — Make hello"'
eq "E2E credit: the tick commit contains ONLY the progress file" "$(git -C "$ORIGIN" show --name-only --format= claude/feature | tr '\n' ' ')" "OVERNIGHT_PROGRESS.md "
ok "E2E credit: item-hash marker logged (item-guard contract)" 'logged "auto-credit: item-hash"'

mk_case e2e_refuse; scout_ok
aplan 2 "gc OVERNIGHT_PROGRESS.md '- [ ] app.py — Stop the sync client. VERIFY: \`grep -q \"sync_gone\" app.py\`' 'docs: queue item'
printf 'def hello():\n    return 2\n' > app.py; git add -A; git commit -q -m 'feat: unrelated edit to app.py'"
run_case
ok "E2E refuse: the cycle still lands (green tests)" '[[ "$OUT" == pushed* ]]'
ok "E2E refuse: item NOT ticked despite app.py being touched" 'git -C "$ORIGIN" show claude/feature:OVERNIGHT_PROGRESS.md | grep -q "^- \[ \] app.py — Stop the sync client"'
ok "E2E refuse: NO item at all was ticked (the old code ticked the first item mentioning app.py)" '[ "$(git -C "$ORIGIN" show claude/feature:OVERNIGHT_PROGRESS.md | grep -c "^- \[x\]")" = 0 ]'  # was: ! ... | grep -q (flaky/masking under pipefail: grep -q exits early, SIGPIPE flips the negation)
ok "E2E refuse: reason logged" 'logged "the item'"'"'s own VERIFY: clause FAILED"'
ok "E2E refuse: no auto-credit commit exists" '! origin_has claude/feature "auto-credit item(s)"'

# progress bookkeeping (DONE: trailer path) is hardened the same way: a dirty INDEX at that point must not be swept into the bookkeeping commit
mk_case e2e_bookkeeping_dirty; scout_ok
aplan 2 'gc app.py "def hello2(): return 2" "feat(app): return 2

DONE: Fix \`hello\` in app.py to return 2"'
# the repo's verifier leaves a half-restored INDEX behind (stand-in for the 13:14 red-green restore failure)
vplan default 'echo "half-restored" >> other.py; git add other.py; exit 0'
run_case
ok "E2E bookkeeping: refused with a log line + alert when the index holds something else" 'logged "progress bookkeeping: REFUSED" && printf "%s" "$ALERTS" | grep -q "progress bookkeeping refused"'
eq "E2E bookkeeping: the half-restored index was NOT swept into a commit (pushed tip touches only app.py)" "$(git -C "$ORIGIN" log --format= --name-only -1 claude/feature)" "app.py"
ok "E2E bookkeeping: the DONE item was not ticked off a dirty tree" '[ "$(git -C "$ORIGIN" show claude/feature:OVERNIGHT_PROGRESS.md | grep -c "^- \[x\]")" = 0 ]'  # was: ! ... | grep -q (flaky/masking under pipefail: grep -q exits early, SIGPIPE flips the negation)

# wiring: every credit/bookkeeping commit in run_overnight.sh is a pathspec commit (a bare `git commit` commits the whole index)
RO="$Q/run_overnight.sh"
for pat in "credit deterministic delete" "credit already-done item" "credit already-satisfied item (scout verdict path)" "credit item(s) the implement pass found already satisfied" "docs: runner-owned progress bookkeeping"; do
  ok "WIRING: '$pat' commit is limited to -- OVERNIGHT_PROGRESS.md" 'grep -F "$pat" "$RO" | grep -v "^ *#" | grep -F "git commit" | grep -qF -- "-- OVERNIGHT_PROGRESS.md"'
done
ok "WIRING: the old inline substring credit is gone" '! grep -q "grep -F \"\$_cf\" | head -1 | cut -d: -f1" "$RO"'

summary
