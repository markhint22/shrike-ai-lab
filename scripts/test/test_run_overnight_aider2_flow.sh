#!/usr/bin/env bash
# Hermetic end-to-end tests of run_aider_fix_task's implement phase (run_overnight.sh, second half):
# implement attempt loop + retry handling, junk-file guard, oversized guard, DELETE trailer, residue guard,
# implement-pass already-satisfied credit, hard-ban, junk auto-removal, dedupe passes, openapi regen,
# alembic autogen hook and the happy-path push. Runs the REAL function via OVN_SOURCE_ONLY + stub aider.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_ro_aider2_fixture.sh"

# ---------- A: happy path (good commit, verify pass, bookkeeping, auto-credit, push) ----------
mk_case happy
scout_ok
aplan 2 'gc app.py "def hello2(): return 2" "feat(app): return 2

DONE: Fix \`hello\` in app.py to return 2"; echo "Tests  2 passed (2)"'
run_case
eq "A: status pushed(tests:pass)" "$OUT" "pushed(tests:pass) [untested-change]"
ok "A: implement attempt 1/3 logged" 'logged "implement attempt 1/3"'
ok "A: implement prompt carried the scout PLAN" 'grep -qF "Your plan: change hello in app.py" "$CASE_DIR/aider.args.2"'
ok "A: aider exactly 2 calls (scout+implement)" '[ "$(cat "$CASE_DIR/aider.n")" = 2 ]'
ok "A: pushed to origin" 'origin_has claude/feature "feat(app): return 2"'
ok "A: runner-owned progress bookkeeping ran" 'logged "progress bookkeeping:"'
ok "A: auto-credit item-hash line logged" 'logged "auto-credit: item-hash"'
ok "A: no alerts" '[ -z "$ALERTS" ]'

# ---------- B: auto-credit by EXACT named path + passing VERIFY (no DONE trailer), 0/0 skip, binary file ----------
# 2026-10-02 (harness-X): was "credit the first item whose text contains the touched file name"; now the item must NAME the touched path
# and its own VERIFY must pass (see test_auto_credit_gate.sh for the refusal cases).
mk_case credit
scout_ok
aplan 2 "$(cat <<'EOS'
gc app.py "def h3(): return 3" "feat: touch app"; : > empty.py; printf "\x89PNG\x00\x01" > img.png; git add -A; git commit -q -m "chore: add empty + binary"
printf '%s\n' '- [ ] empty.py — Add empty. VERIFY: `true`' '- [ ] img.png — Add asset. VERIFY: `true`' '- [ ] app.py — Touch app. VERIFY: `grep -q h3 app.py`' >> OVERNIGHT_PROGRESS.md; git add -A; git commit -q -m "chore: note assets"
EOS
)"
run_case
ok "B: pushed" '[[ "$OUT" == pushed* ]]'
ok "B: auto-credit skipped the 0/0 empty file" 'logged "auto-credit: SKIPPED empty.py"'
ok "B: auto-credit checked off the item naming app.py after its VERIFY passed" 'logged "VERIFY passed for line" && git -C "$REPO" show HEAD:OVERNIGHT_PROGRESS.md | grep -q "^- \[x\] app.py — Touch app"'
ok "B: auto-credit of binary file never blocked (img.png credited)" '! logged "SKIPPED img.png" && git -C "$REPO" show HEAD:OVERNIGHT_PROGRESS.md | grep -q "^- \[x\] img.png"'
ok "B: the empty.py item stays open" 'git -C "$REPO" show HEAD:OVERNIGHT_PROGRESS.md | grep -q "^- \[ \] empty.py"'
ok "B: the unrelated first item (which merely MENTIONS app.py) is NOT ticked any more" 'git -C "$REPO" show HEAD:OVERNIGHT_PROGRESS.md | grep -q "^- \[ \] Fix .hello. in app.py"'

# ---------- C: aider exit != 0 after a commit -> error(exit=N) ; transient variant ----------
mk_case exitcode
scout_ok
aplan 2 'gc app.py "x=1" "feat: c"; echo "boom"; exit 3'
run_case
eq "C: nonzero aider exit -> error(exit=3)" "$OUT" "error(exit=3)"
mk_case exittrans
scout_ok
aplan 2 'gc app.py "x=1" "feat: c"; echo "litellm.RateLimitError: slow down"; exit 1'
run_case
eq "C: nonzero exit + RateLimitError -> error-transient" "$OUT" "error-transient(API/network - see log)"

# ---------- D: oversized context ----------
mk_case oversized
scout_ok
aplan 2 'echo "litellm.ContextWindowExceededError: exceed_context_size_error"'
run_case
eq "D: exceed_context_size -> skip(oversized-context)" "$OUT" "skip(oversized-context)"
ok "D: message logged" 'logged "item exceeded the context window"'

# ---------- E: retry loop: no-diff attempt that names a new file -> attempt 2 commits ----------
mk_case retry1
scout_ok
aplan 2 'echo "I need to see extra.py and other.py to do this"'
aplan 3 'gc app.py "def r(): return 9" "feat: retried"'
run_case
ok "E: retry landed after attempt 2" '[[ "$OUT" == pushed* ]]'
ok "E: attempt 2 logged" 'logged "implement attempt 2/3"'
ok "E: attempt 2 pre-loaded the newly named existing file" 'grep -qx "other.py" "$CASE_DIR/aider.args.3"'
ok "E: attempt 3 never needed" '! logged "implement attempt 3/3"'

# ---------- F: junk-only commit discarded and retried; junk on last attempt -> break -> no-op ----------
mk_case junk1
scout_ok
aplan 2 'gc ask_for_file.txt "please add app.py" "chore: junk"; echo "also look at other.py"'
aplan 3 'gc app.py "def j(): return 1" "feat: real after junk"'
run_case
ok "F: junk-only attempt discarded then real commit pushed" '[[ "$OUT" == pushed* ]]'
ok "F: junk discard message logged" 'logged "only committed junk file(s), discarding and retrying"'
ok "F: junk file not in final tree" '[ "$(git -C "$REPO" ls-files | grep -c ask_for_file)" = 0 ]'  # was: ! ... | grep -q (flaky/masking under pipefail: grep -q exits early, SIGPIPE flips the negation)
mk_case junk2
scout_ok
aplan 2 'gc ask_for_file.txt "please add app.py" "chore: junk"; echo "also look at other.py"'
aplan 3 'gc ask_for_file.txt "please add app.py" "chore: junk"; echo "also look at old.py"'
aplan 4 'gc ask_for_file.txt "please add app.py" "chore: junk"; echo "also look at tests/test_app.py"'
run_case "$PROMPT_DEFAULT" false claude/feature "" 4
eq "F: junk on every attempt -> no-op" "$OUT" "no-op"
ok "F: 3 attempts were made" 'logged "implement attempt 3/3"'
ok "F: no 4th attempt" '! logged "attempt 4/3"'
mk_case junk3
scout_ok
aplan default 'gc ask_for_file.txt "x" "chore: junk"'
aplan 1 'scout PROCEED "change hello in app.py" "app.py"'
run_case
eq "F: junk + no new files to load (scan false) -> break -> no-op" "$OUT" "no-op"
ok "F: only one implement attempt when nothing new to load" '! logged "implement attempt 2/3"'

# ---------- G: scan_for_new_files: protected, multifile:no, max_files cap, md skipped ----------
mk_case protected
scout_ok
aplan 2 'echo "see old.py and README.md and other.py"'
run_case "$PROMPT_DEFAULT" false claude/feature "old.py"
ok "G: protected file skipped with a log line" 'logged "skipping protected file mentioned in log: old.py"'
ok "G: protected file never loaded" '! grep -qx "old.py" "$CASE_DIR/aider.args.3"'
ok "G: md files never loaded" '! grep -qx "README.md" "$CASE_DIR/aider.args.3"'
ok "G: non-protected file loaded on retry" 'grep -qx "other.py" "$CASE_DIR/aider.args.3"'
mk_case multifile
scout_ok
aplan 2 'echo "see other.py"'
run_case "$PROMPT_DEFAULT multifile:no"
ok "G: multifile:no -> single attempt" '! logged "implement attempt 2/3"'
mk_case maxfiles
scout_ok
aplan default 'echo "see other.py old.py extra.py tests/test_app.py"'
aplan 1 'scout PROCEED "change hello" "app.py"'
run_case "$PROMPT_DEFAULT" false claude/feature "" 1
ok "G: max_files cap reached -> nothing more to load -> single attempt" '! logged "implement attempt 2/3"'
ok "G: only the force-loaded scout file is loaded (cap 1)" '[ "$(grep -cx -- "--file" "$CASE_DIR/aider.args.2")" = 1 ]'

# ---------- H: architect mode ----------
mk_case arch
scout_ok
aplan 2 'echo "nothing"'
OVN_ARCHITECT=1 run_case 'refactor the multi-file thing [T4] in app.py'
ok "H: architect flag passed to aider" 'grep -qx -- "--architect" "$CASE_DIR/aider.args.2"'
ok "H: architect mode logged" 'logged "architect mode ON for this hard item"'

# ---------- I: DELETE trailer ----------
mk_case delete
scout_ok
aplan 2 'gc app.py "def d(): return 4" "feat: something"; echo "DELETE: old.py"; echo "DELETE: does_not_exist.py"'
run_case
ok "I: delete trailer committed removal" 'git -C "$REPO" log --format=%s | grep -q "remove file(s) per DELETE trailer"'
ok "I: old.py gone from tree" '[ ! -f "$REPO/old.py" ]'
ok "I: DELETE logged" 'logged "DELETE trailer: removed old.py"'
ok "I: pushed" '[[ "$OUT" == pushed* ]]'

# ---------- J: residue guard: uncommitted residue ----------
mk_case residue_discard
scout_ok
aplan 2 'echo "edit" >> app.py; echo "no tests reported"'
run_case
ok "J: no test signal -> discard" 'logged "discarding uncommitted working-tree residue"'
ok "J: tree clean" '[ -z "$(git -C "$REPO" status --porcelain)" ]'
eq "J: status no-op" "$OUT" "no-op"
mk_case residue_salvage
scout_ok
aplan 2 'echo "def s(): return 5" >> app.py; echo "Tests 3 passed (3)"'
run_case
ok "J: passing residue salvaged" 'logged "independently re-verified as PASSING - salvaging"'
ok "J: salvage commit on repo" 'git -C "$REPO" log --format=%s | grep -q "salvage working-tree residue"'
mk_case residue_failverify
scout_ok
aplan 2 'echo "def s(): return 5" >> app.py; echo "Tests 3 passed (3)"'
vplan 1 'echo "FAILED tests/test_app.py::test_x - assert 0"; exit 1'
run_case
ok "J: residue with failing re-verify discarded" 'logged "residue re-verify came back"'
ok "J: file content reverted" '! grep -q "def s" "$REPO/app.py"'
mk_case residue_commitfail
scout_ok
aplan 2 'echo "def s(): return 5" >> app.py; echo "Tests 3 passed (3)"; touch "$CASE_DIR/block_commit"'
printf '#!/bin/sh\n[ -f "$CASE_DIR/block_commit" ] && exit 1\nexit 0\n' > "$CASE_DIR/repo/.git/hooks/pre-commit"; chmod +x "$CASE_DIR/repo/.git/hooks/pre-commit"
run_case
ok "J: salvage commit failure falls back to discard" 'logged "salvage commit failed - falling back to discard"'

# ---------- K: implement pass found item already satisfied -> credit commit ----------
mk_case alreadysat
scout_ok
aplan 2 'echo "app.py already returns correct value, nothing to change"'
cat > "$CASE_DIR/credit.sh" <<'EOF'
sed -i '0,/^- \[ \] /s//- [x] (already-satisfied) /' OVERNIGHT_PROGRESS.md
echo "CREDITED=1"
EOF
run_case
ok "K: credit commit created" '_o="$(git -C "$REPO" log --format=%s)"; printf "%s\n" "$_o" | grep -q "credit item(s) the implement pass found already satisfied"'
ok "K: credited commit pushed via normal path" '[[ "$OUT" == pushed* ]]'
mk_case alreadysat0
scout_ok
aplan 2 'echo "already done, nothing to do"'
run_case
eq "K: no change + already-done phrase -> no-op(ALREADY-DONE)" "$OUT" "no-op(ALREADY-DONE)"

# ---------- L: hard-banned file ----------
mk_case banned
scout_ok
printf '# comment\n\nsecrets/.*\n' > "$OTHER/.queue-hard-banned-files"
( cd "$OTHER" && git add -A && git commit -q -m banlist && git push -q origin main ) >/dev/null 2>&1
( cd "$REPO" && git pull -q origin main ) >/dev/null 2>&1
printf '#!/bin/sh\nexit 0\n' > "$HOME/godot/godot4"; chmod +x "$HOME/godot/godot4"
aplan 2 'gc secrets/key.txt "hunter2" "feat: touch banned"'
run_case
ok "L: hard-ban violation logged" 'logged "HARD-BAN VIOLATION"'
ok "L: banned file gone" '[ ! -e "$REPO/secrets/key.txt" ]'
eq "L: nothing landed -> no-op" "$OUT" "no-op"
rm -f "$HOME/godot/godot4"
mk_case banned_empty
scout_ok
printf '# only comments\n' > "$OTHER/.queue-hard-banned-files"
( cd "$OTHER" && git add -A && git commit -q -m banlist && git push -q origin main ) >/dev/null 2>&1
( cd "$REPO" && git pull -q origin main ) >/dev/null 2>&1
aplan 2 'gc app.py "def ok(): return 1" "feat: fine"'
run_case
ok "L: empty ban pattern does not block" '[[ "$OUT" == pushed* ]]'

# ---------- M: junk file accidentally committed alongside real work ----------
mk_case junkalong
scout_ok
aplan 2 'gc app.py "def ja(): return 1" "feat: real"; gc "git status" "x" "chore: stray"'
run_case
ok "M: junk auto-removal logged" 'logged "auto-removing junk file(s) accidentally committed"'
ok "M: auto-remove commit exists" 'git -C "$REPO" log --format=%s | grep -q "auto-remove junk file(s)"'
ok "M: junk not in tree" '[ ! -e "$REPO/git status" ]'

# ---------- N: dedupe passes (progress headers, gd, python) ----------
mk_case dedupe
scout_ok
aplan 2 'printf "def dup():\n    return 1\n\n\ndef dup():\n    return 1\n" > dupmod.py
printf "extends Node\n\nfunc a():\n\tpass\n\nfunc a():\n\tpass\n" > thing.gd
printf "\n## Decisions Made\n- one\n\n## Completed\n- x\n\n## Decisions Made\n- two\n" >> OVERNIGHT_PROGRESS.md
git add -A; git commit -q -m "feat: dupes"'
run_case
ok "N: python dedupe commit" '_o="$(git -C "$REPO" log --format=%s)"; printf "%s\n" "$_o" | grep -q "duplicate Python class/function"'
ok "N: gd dedupe commit" 'git -C "$REPO" log --format=%s | grep -q "duplicate GDScript function"'
ok "N: progress header merge commit" 'git -C "$REPO" log --format=%s | grep -q "auto-merge duplicate section header"'
ok "N: only one def dup remains" '[ "$(grep -c "def dup" "$REPO/dupmod.py")" = 1 ]'

# ---------- O: openapi regen + alembic autogen hook ----------
add_backend(){ # $1 = value committed in docs/openapi.json
( cd "$OTHER" && mkdir -p backend/scripts backend/.venv/bin docs && ln -s "$(command -v python3)" backend/.venv/bin/python3
  printf 'import pathlib\npathlib.Path("../docs/openapi.json").write_text("{\\"v\\": 2}\\n")\n' > backend/scripts/export_openapi.py
  echo "{\"v\": $1}" > docs/openapi.json
  git add -A && git commit -q -m "add backend" && git push -q origin main ) >/dev/null 2>&1
( cd "$REPO" && git pull -q origin main ) >/dev/null 2>&1
}
mk_case openapi
scout_ok
add_backend 1
aplan 2 'gc app.py "def o(): return 1" "feat: api change"'
cat > "$CASE_DIR/autogen.sh" <<'EOF'
echo "alembic-autogen: generated migration stub"
echo x > gen_marker.txt; git add -A; git commit -q -m "chore(alembic): autogen migration"
EOF
run_case
ok "O: openapi regenerated + committed" 'git -C "$REPO" log --format=%s | grep -q "auto-regenerate openapi.json"'
ok "O: openapi regen logged" 'logged "auto-regenerated docs/openapi.json"'
ok "O: alembic autogen output logged" 'logged "alembic-autogen: generated migration stub"'
ok "O: autogen commit included in push" 'origin_has claude/feature "autogen migration"'
mk_case openapi_same
scout_ok
add_backend 2
aplan 2 'gc app.py "def o2(): return 1" "feat: api change 2"'
run_case
ok "O: no regen commit when contract already in sync" '[ "$(git -C "$REPO" log --format=%s | grep -c "auto-regenerate openapi.json")" = 0 ]'  # was: ! ... | grep -q (flaky/masking under pipefail: grep -q exits early, SIGPIPE flips the negation)

summary
