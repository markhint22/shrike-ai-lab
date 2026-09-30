#!/usr/bin/env bash
# ovn_alembic_autogen.sh <repo_root> <BEFORE_SHA> <AFTER_SHA>
#
# Post-implement hook (2026-09-30). When this cycle's commit(s) changed a SQLAlchemy model
# (or touched alembic/versions) and the repo's Alembic chain no longer matches the models
# - exactly what tests/test_migration_drift.py::test_alembic_head_matches_models asserts -
# generate the missing migration DETERMINISTICALLY (no LLM: aider has no shell, so it can
# never run `alembic revision --autogenerate` itself) and commit it on top of the cycle's
# commit. Same shape/safety rules as the OpenAPI-contract regen hook in run_overnight.sh:
# cheap, idempotent (no drift => writes nothing), zero-LLM, only ADDS one file.
#
# Contract with the caller: prints status lines (for $task_log); ALWAYS exits 0; the caller
# re-reads `git rev-parse HEAD` to learn whether a commit was added. On any refusal/error the
# working tree is left exactly as the cycle left it, so every existing gate (drift test,
# MIGRATION-SAFETY, NO-NEW-RED, revert) behaves as before - this hook can only help.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="${1:?repo_root}"; before="${2:?before}"; after="${3:?after}"
say() { echo "ALEMBIC-AUTOGEN: $*"; }

[ -n "${OVN_ALEMBIC_AUTOGEN_DISABLE:-}" ] && exit 0
cd "$repo" || exit 0
name="$(basename "$repo")"

# GATE 1 - allowlisted repos only (silent for the rest). Both have been trialled; billwatch's
# chain is Postgres-only (ALTER COLUMN TYPE) so it cannot replay on SQLite - leave it out.
# 2026-09-30: default narrowed to the one repo the trial actually proved (13/14 real failing commits -> green). iptv_apps has no
# real model/migration drift (items say "create migration for X" but X's premise is false), so the hook would just no-op there.
allow="${OVN_ALEMBIC_AUTOGEN_REPOS:-test-automation-agent}"
case " $allow " in *" $name "*) ;; *) exit 0 ;; esac

# GATE 2 - exactly one alembic project, and it has adopted the drift-test pattern.
mapfile -t _inis < <(git ls-files -- '*alembic.ini' | grep -v 'alembic\.backup')
[ "${#_inis[@]}" -eq 1 ] || exit 0
proj="$(dirname "${_inis[0]}")"
[ -f "$proj/tests/test_migration_drift.py" ] || exit 0
vdir="$proj/alembic/versions"
PY="$repo/$proj/.venv/bin/python"; [ -x "$PY" ] || { say "skip: no $proj/.venv"; exit 0; }

# GATE 3 - only when this cycle actually committed something that can cause drift.
changed="$(git diff --no-renames --name-only "$before" "$after" -- "$proj" 2>/dev/null)"
echo "$changed" | grep -Eq '(^|/)models?(/|\.py$)|/alembic/versions/' || exit 0

# GATE 4 - clean tree (never mix our commit with someone's uncommitted work), and not a
# red/structurally-broken build: every changed .py must at least compile. (A model file that
# fails to import makes the driver exit 12 too - belt and braces.)
git diff --quiet HEAD -- || { say "skip: dirty working tree"; exit 0; }
while IFS= read -r f; do
  case "$f" in *.py) [ -f "$f" ] && ! "$PY" -m py_compile "$f" 2>/dev/null && { say "skip: $f does not compile (red build)"; exit 0; } ;; esac
done <<< "$changed"

run_driver() {  # $1 = message ; runs in the alembic project dir
  ( cd "$repo/$proj" && "$PY" "$SCRIPT_DIR/ovn_alembic_autogen.py" --message "$1" 2>&1 | grep -E '^(GENERATED|NODRIFT|REFUSE|ERROR)' | head -1 )
}
# message = subject of the cycle's first commit, conventional-commit prefix stripped
msg="$(git log --format=%s "$before..$after" 2>/dev/null | tail -1 | sed -E 's/^[a-z]+(\([^)]*\))?!?: *//')"
[ -n "$msg" ] || msg="sync models with schema"

# STEP A - drop pipeline placeholder stubs (run_overnight.sh stubs a brand-new migration file
# with a docstring-only body BEFORE implement; if the model never fills it in, that file has
# no `revision` and breaks the WHOLE chain). Exact-marker match only.
for f in $(git ls-files -- "$vdir/*.py"); do
  if grep -q 'Placeholder - the implement step fills in' "$f" && ! grep -q '^revision' "$f"; then
    git rm -q -f -- "$f" && say "removed unfilled placeholder stub $f"
  fi
done

out="$(run_driver "$msg")"

# STEP B - chain broken by the model's OWN migration work (stale down_revision like '009',
# two heads, edited an old migration): undo exactly what THIS cycle did under versions/ -
# delete files it added, restore files it modified/deleted - then retry ONCE.
if echo "$out" | grep -Eq '^REFUSE chain'; then
  say "chain broken by this cycle ($out) - reverting the cycle's own migration edits, then retrying once"
  git diff --no-renames --name-only --diff-filter=A "$before" "$after" -- "$vdir" | grep '\.py$' | while IFS= read -r f; do git rm -q -f -- "$f" 2>/dev/null; done
  git diff --no-renames --name-only --diff-filter=MDT "$before" "$after" -- "$vdir" | grep '\.py$' | while IFS= read -r f; do git checkout -q "$before" -- "$f"; done
  out="$(run_driver "$msg")"
fi

case "$out" in
  GENERATED\ *)
    new="$proj/${out#GENERATED }"
    # final safety net: single head + the repo's static migration checks (dup ids, FK types)
    if [ -f "$SCRIPT_DIR/check_migrations.py" ] && ! python3 "$SCRIPT_DIR/check_migrations.py" "$repo/$proj" >/dev/null 2>&1; then
      say "post-generate check_migrations.py failed - discarding"; git reset -q --hard HEAD; git clean -fdq -- "$vdir"; exit 0
    fi
    git add -A -- "$vdir"
    git commit -q -m "chore(migration): auto-generate Alembic migration for model change (deterministic, zero-LLM)

Models changed without a matching migration (tests/test_migration_drift.py would fail).
Generated by scripts/ovn_alembic_autogen.py against a throwaway SQLite DB at head; new file: ${new}" \
      && say "generated and committed ${new}"
    ;;
  NODRIFT*) say "no drift - nothing to generate"; git reset -q --hard HEAD; git clean -fdq -- "$vdir" ;;
  *)        say "not auto-fixable (${out:-no driver output}) - leaving the cycle's commit for the existing gates"
            git reset -q --hard HEAD; git clean -fdq -- "$vdir" ;;
esac
exit 0
