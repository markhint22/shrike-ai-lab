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
# mirrors the deployed stub-comment case statement exactly
stub_comment_for() {  # $1=path
  case "$1" in
    *.py) echo '"""Placeholder - the implement step fills this in."""' ;;
    *.gd) echo '# Placeholder - the implement step fills this in.' ;;
    *.kt|*.swift|*.ts|*.tsx) echo '// Placeholder - the implement step fills this in.' ;;
    *.vue) echo '<!-- Placeholder - the implement step fills this in. -->' ;;
    *) echo '' ;;
  esac
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
ok "ts/tsx/kt/swift stub uses // (C-style line comment)" \
   "[ \"\$(stub_comment_for foo.ts)\" = '// Placeholder - the implement step fills this in.' ]"
ok "vue stub uses an HTML comment (valid outside any SFC block)" \
   "[ \"\$(stub_comment_for foo.vue)\" = '<!-- Placeholder - the implement step fills this in. -->' ]"

cd - >/dev/null 2>&1 || true

echo "new-source-file-stub: $P passed, $F failed"
[ "$F" -eq 0 ]
