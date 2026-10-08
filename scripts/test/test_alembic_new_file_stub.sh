#!/usr/bin/env bash
# Regression test for run_overnight.sh's new-Alembic-migration-file stub fix
# (2026-09-29). Generalizes the pre-existing OVERNIGHT_PROGRESS.md stub trick: this
# model's udiff is unreliable synthesizing a whole brand-new file from scratch (it
# sometimes emits a hunk with no leading '+' on any body line, which aider parses as
# a silent no-op - no error text, no "Applied edit to ..."). Confirmed live: iptv_apps
# item_hash 2c43352a (iptv-backend/alembic/versions/0007_active_stream_sessions.py, a
# T2 recovered sub-item) hit this exact silent no-op 4 times in a row (2026-09-29
# 10:48-11:36 CDT) with fail_reason=unknown every time - one attempt even correctly
# loaded the real model file and matched its columns, and still never landed because
# the diff body had no '+' prefixes. Fix stubs the target file first (syntactically
# valid placeholder, immediately overwritten by the implement step) so aider only
# ever has to EDIT an existing file. Mirrors the deployed extraction regex exactly
# so this can't drift.
set -uo pipefail
RO="${OVN_RUN_OVERNIGHT:-$HOME/overnight-queue/run_overnight.sh}"
[ -f "$RO" ] || { echo "  SKIP: $RO not found on this host"; exit 0; }

grep -q "chore: stub new Alembic migration file before implement" "$RO" \
  || { echo "  FAIL: alembic-new-file stub fix not found in $RO"; exit 1; }
grep -q '\[ -n "\$_ovn_new_migration_file" \] && \[ ! -f "\$_ovn_new_migration_file" \]' "$RO" \
  || { echo "  FAIL: existence guard (never clobber a real migration) not found in $RO"; exit 1; }

P=0; F=0
# 2026-10-08: assertions are evaluated with pipefail OFF - under pipefail `A | grep -q X` is flaky (grep -q exits at its first hit, A may take SIGPIPE: rc 141) and `! A | grep -q X` can mask a real failure
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

# mirrors the deployed extraction regex exactly
extract_new_migration_path() {  # $1=prompt $2=top_progress_item
  printf '%s\n%s' "$1" "$2" | grep -oE '[A-Za-z0-9_./-]*alembic/versions/[A-Za-z0-9_]+\.py' | head -1
}

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cd "$tmp" || exit 1
mkdir -p iptv-backend/alembic/versions
: > iptv-backend/alembic/versions/0006_referrals.py   # an existing migration, must never be touched

# ---- 1. ongoing-lane blind spot: $prompt is the fixed generic wrapper (no file
#      names in it at all) - only the top-progress-item peek names the real path ----
generic_prompt="Work the single top not-yet-done item in the overnight progress log's Next Steps..."
top_item='- [ ] [T2] iptv-backend/alembic/versions/0007_active_stream_sessions.py — Create new migration file with revision ID "0007", down_revision "0006".'
hit="$(extract_new_migration_path "$generic_prompt" "$top_item")"
ok "resolves the new migration path from the ongoing-lane top-item peek, not just \$prompt" \
   '[ "$hit" = "iptv-backend/alembic/versions/0007_active_stream_sessions.py" ]'

# ---- 2. regular queued item: $prompt IS the item text directly ----
direct_prompt='[T1] iptv-backend/alembic/versions/0009_new_table.py (NEW) — Add a migration for the new table.'
hit2="$(extract_new_migration_path "$direct_prompt" "")"
ok "resolves the new migration path directly from \$prompt for non-ongoing-lane items" \
   '[ "$hit2" = "iptv-backend/alembic/versions/0009_new_table.py" ]'

# ---- 3. safety: an item naming an EXISTING migration file must never be stubbed
#      (the deployed [ ! -f ] guard is what actually enforces this - verify the path
#      extraction correctly finds it AND that it really does exist on disk, i.e. the
#      deployed "$_ovn_new_migration_file" && [ ! -f ] condition would evaluate to
#      false here and skip stubbing, leaving the real file untouched) ----
existing_hit="$(extract_new_migration_path "" '- [ ] [T2] iptv-backend/alembic/versions/0006_referrals.py — Fix the down_revision.')"
ok "extraction still finds the path named in the item text" \
   '[ "$existing_hit" = "iptv-backend/alembic/versions/0006_referrals.py" ]'
ok "that path already exists on disk, so the deployed [ ! -f ] guard would refuse to stub it (never clobbers real content)" \
   '[ -f "$existing_hit" ]'

# ---- 4. no false positive when the item has nothing to do with Alembic ----
unrelated_hit="$(extract_new_migration_path "Fix a typo in the README" "- [ ] [T1] docs/README.md — Fix a typo.")"
ok "no match when the item never mentions an alembic/versions path" \
   '[ -z "$unrelated_hit" ]'

cd - >/dev/null 2>&1 || true

echo "alembic-new-file-stub: $P passed, $F failed"
[ "$F" -eq 0 ]
