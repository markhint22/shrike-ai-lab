#!/usr/bin/env bash
# Regression test for run_overnight.sh's generalized new-source-file stub fix
# (2026-09-29 follow-up to the Alembic-only new-file stub, 59a1aa9).
#
# The Alembic-only stub only covers alembic/versions/*.py. The SAME root-cause udiff
# weakness (a brand-new file's hunk body comes back with no leading '+' on any line,
# so aider silently no-ops: no error text, fail_reason "unknown") is not
# migration-specific - it's inherent to this model synthesizing ANY whole new file
# from scratch. Confirmed live on xlite 19 minutes after the Alembic fix shipped:
# item_hash 25c1a4b2 asked for a brand-new scripts/mission/mission_directive.gd and
# hit the identical signature (bulleted hunk body, zero '+' prefixes, CREDITED=0) -
# a different repo AND file type than the Alembic case that fix covers.
#
# Mirrors the deployed extraction regex/logic exactly so this can't drift.
set -uo pipefail
RO="${OVN_RUN_OVERNIGHT:-$HOME/overnight-queue/run_overnight.sh}"
[ -f "$RO" ] || { echo "  SKIP: $RO not found on this host"; exit 0; }

grep -q "chore: stub new source file before implement" "$RO" \
  || { echo "  FAIL: generalized new-source-file stub fix not found in $RO"; exit 1; }
grep -q '\[ -n "\$_ovn_new_source_file" \] && \[ ! -f "\$_ovn_new_source_file" \]' "$RO" \
  || { echo "  FAIL: existence guard (never clobber a real file) not found in $RO"; exit 1; }

P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

# mirrors the deployed extraction regex exactly
extract_new_source_file() {  # $1=prompt $2=top_progress_item
  printf '%s\n%s' "$1" "$2" | grep -oE '[A-Za-z0-9_./-]+\.(gd|py|ts|tsx|vue|kt|swift)' | head -1
}
# Evaluates the DEPLOYED stub-content case statement itself (extracted from run_overnight.sh), not a
# hand-copied mirror: the previous mirrored copy kept passing while the real code changed, so it could
# never have caught a bad stub (2026-09-30: a comment-only vitest file broke a whole repo's suite).
CASE_SRC="$(sed -n '/case "\$_ovn_new_source_file" in/,/^      esac/p' "$RO")"
[ -n "$CASE_SRC" ] || { echo "  FAIL: could not extract the stub case statement from $RO"; exit 1; }
[ "$(printf '%s\n' "$CASE_SRC" | grep -c 'case "\$_ovn_new_source_file" in')" = 1 ] \
  || { echo "  FAIL: expected exactly one stub case statement in $RO"; exit 1; }
stub_comment_for() {  # $1=path -> the stub file content the deployed code would write
  local _ovn_new_source_file="$1" _ovn_stub_comment=''
  eval "$CASE_SRC"
  printf '%s' "$_ovn_stub_comment"
}

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cd "$tmp" || exit 1
mkdir -p scripts/mission backend/app/models
: > backend/app/models/existing.py   # an existing file, must never be touched

# ---- 1. ongoing-lane blind spot: $prompt is the fixed generic wrapper (no file
#      names in it at all) - only the top-progress-item peek names the real path,
#      same blind spot the Alembic fix and delete-hint fix both had to close ----
generic_prompt="Work the single top not-yet-done item in the overnight progress log's Next Steps..."
top_item='- [ ] [T1] scripts/mission/mission_directive.gd — Create with class_name MissionDirective.'
hit="$(extract_new_source_file "$generic_prompt" "$top_item")"
ok "resolves the new GDScript path from the ongoing-lane top-item peek, not just \$prompt" \
   '[ "$hit" = "scripts/mission/mission_directive.gd" ]'

# ---- 2. regular queued item: $prompt IS the item text directly, other extensions ----
direct_prompt='[T1] frontend/src/utils/formatDate.ts (NEW) — Add a date formatting helper.'
hit2="$(extract_new_source_file "$direct_prompt" "")"
ok "resolves a new .ts path directly from \$prompt for non-ongoing-lane items" \
   '[ "$hit2" = "frontend/src/utils/formatDate.ts" ]'

# ---- 3. safety: a path naming an EXISTING file must never be stubbed (the deployed
#      [ ! -f ] guard is what actually enforces this) ----
existing_hit="$(extract_new_source_file "" '- [ ] [T2] backend/app/models/existing.py — Add a field.')"
ok "extraction still finds the path named in the item text" \
   '[ "$existing_hit" = "backend/app/models/existing.py" ]'
ok "that path already exists on disk, so the deployed [ ! -f ] guard would refuse to stub it" \
   '[ -f "$existing_hit" ]'

# ---- 4. no false positive when the item has nothing to do with a new source file ----
unrelated_hit="$(extract_new_source_file "Fix a typo in the README" "- [ ] [T1] docs/README.md — Fix a typo.")"
ok "no match when the item never names a gd/py/ts/tsx/vue/kt/swift path" \
   '[ -z "$unrelated_hit" ]'

# ---- 5. extension-appropriate comment syntax (must be a valid single-line comment
#      in that language, since aider will EDIT this stub, not create from scratch) ----
ok "gd stub uses # (GDScript line comment)" \
   "[ \"\$(stub_comment_for foo.gd)\" = '# Placeholder - the implement step fills this in.' ]"
ok "py stub uses a docstring (valid standalone Python)" \
   "[ \"\$(stub_comment_for foo.py)\" = '\"\"\"Placeholder - the implement step fills this in.\"\"\"' ]"
ok "kt/swift stub uses // (C-style line comment)" \
   "[ \"\$(stub_comment_for foo.kt)\" = '// Placeholder - the implement step fills this in.' ] && [ \"\$(stub_comment_for foo.swift)\" = '// Placeholder - the implement step fills this in.' ]"

# ---- 6. stubs must be VALID for their file type, because the stub is committed and stays on the
#      branch if the implement step never fills it ----
ok "a vitest/jest test-file stub is a real (skipped) suite, not comment-only (an empty test file FAILS vitest: 'No test suite found')" \
   "s=\"\$(stub_comment_for foo.test.ts)\"; printf '%s' \"\$s\" | grep -q 'describe.skip' && printf '%s' \"\$s\" | grep -q \"import { describe, it } from 'vitest'\""
ok "same for .test.tsx / .spec.ts / .spec.tsx" \
   "( for f in foo.test.tsx foo.spec.ts foo.spec.tsx; do stub_comment_for \$f | grep -q 'describe.skip' || exit 1; done )"
ok "the test-file stub is NOT the plain .ts stub (pattern order: test patterns must precede *.ts)" \
   "[ \"\$(stub_comment_for foo.test.ts)\" != \"\$(stub_comment_for foo.ts)\" ]"
ok "a plain .ts/.tsx stub is a module (export {}), valid under isolatedModules" \
   "stub_comment_for foo.ts | grep -q '^export {}\$' && stub_comment_for foo.tsx | grep -q '^export {}\$'"
ok "a .vue stub is a minimal valid SFC (has a <template>)" \
   "stub_comment_for foo.vue | grep -q '<template>'"
ok "every stub keeps the greppable placeholder marker" \
   "( for f in a.py a.gd a.kt a.swift a.ts a.tsx a.vue a.test.ts a.spec.tsx; do stub_comment_for \$f | grep -q 'Placeholder - the implement step fills this in' || exit 1; done )"


# ---- 7. SELF-HEAL of already-committed placeholder-only vitest files (the deployed block, run for real
#      in a throwaway git repo) ----
HEAL_SRC="$(sed -n '/# >>> SELF-HEAL-BEGIN/,/# <<< SELF-HEAL-END/p' "$RO")"
[ -n "$HEAL_SRC" ] || { echo "  FAIL: could not extract the self-heal block from $RO"; exit 1; }
hr="$tmp/healrepo"; mkdir -p "$hr/web/__tests__" && cd "$hr" || exit 1
git init -q . && git config user.email t@t && git config user.name t
M='// Placeholder - the implement step fills this in.'
printf '%s\n' "$M" > web/__tests__/Stub.test.ts                                   # the poisoning case
printf '%s\n' "$M" > web/__tests__/StubSpec.spec.tsx                              # also healed
printf '%s\n' "import { it, expect } from 'vitest'" "it('real', () => { expect(1).toBe(1) })" > web/__tests__/Real.test.ts
printf '%s\n' "// just a comment someone else wrote" > web/__tests__/OtherComment.test.ts   # no marker: hands off
printf '%s\n' "$M" > web/plain.ts                                                  # not a test file: hands off
git add -A && git commit -q -m base
before_real="$(git hash-object web/__tests__/Real.test.ts)"; before_other="$(git hash-object web/__tests__/OtherComment.test.ts)"; before_plain="$(git hash-object web/plain.ts)"
task_log="$tmp/heal.log"; : > "$task_log"
eval "$HEAL_SRC"
ok "a placeholder-only .test.ts is repaired into a skipped suite" "grep -q 'describe.skip' web/__tests__/Stub.test.ts"
ok "a placeholder-only .spec.tsx is repaired too" "grep -q 'describe.skip' web/__tests__/StubSpec.spec.tsx"
ok "a real test file is never modified" "[ \"\$(git hash-object web/__tests__/Real.test.ts)\" = \"$before_real\" ]"
ok "a comment-only test file WITHOUT our marker is never modified" "[ \"\$(git hash-object web/__tests__/OtherComment.test.ts)\" = \"$before_other\" ]"
ok "a non-test placeholder is never modified by the heal" "[ \"\$(git hash-object web/plain.ts)\" = \"$before_plain\" ]"
ok "the repair is committed (working tree clean afterwards)" "[ -z \"\$(git status --short)\" ]"
ok "the repair is logged to the task log" "grep -q 'self-heal: repaired 2' '$tmp/heal.log'"
n_before="$(git rev-list --count HEAD)"; eval "$HEAL_SRC"
ok "a second pass is a no-op (idempotent: no new commit)" "[ \"\$(git rev-list --count HEAD)\" = \"$n_before\" ]"
cd "$tmp" || exit 1

cd - >/dev/null 2>&1 || true

echo "new-source-file-stub: $P passed, $F failed"
[ "$F" -eq 0 ]
