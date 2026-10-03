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
say() { echo "ALEMBIC-AUTOGEN: $*"; }

# --drop-stubs <repo_root>  (2026-10-03, landing gates): STEP A on its own, runnable EVERY cycle before the
# MIGRATION-SAFETY gate and again after that gate's revert. run_overnight.sh commits a docstring-only stub
# ("Placeholder - the implement step fills in ...") for a brand-new migration BEFORE implement; if the model
# never fills it in the file has no `revision`, breaks the whole alembic chain (iptv_apps 0011, 2026-10-02)
# and - when the stub commit is at/below the gate's BEFORE_SHA - survives the gate's `git reset --hard`.
# Not allowlisted/gated on a venv: deleting an exact-marker, revision-less file is safe in any alembic repo.
# Prints one status line per removed stub; ALWAYS exits 0; commits the deletion (tree stays clean).
if [ "${1:-}" = "--drop-stubs" ]; then
  [ -n "${OVN_ALEMBIC_AUTOGEN_DISABLE:-}" ] && exit 0
  cd "${2:?repo_root}" 2>/dev/null || exit 0
  _dropped=0; _paths=()
  while IFS= read -r f; do
    [ -n "$f" ] && [ -f "$f" ] || continue
    if grep -q 'Placeholder - the implement step fills in' "$f" && ! grep -q '^revision' "$f"; then
      git rm -q -f -- "$f" 2>/dev/null && { say "removed unfilled placeholder stub $f"; _dropped=1; _paths+=("$f"); }
    fi
  done < <(git ls-files -- '*alembic/versions/*.py' 2>/dev/null)
  if [ "$_dropped" = 1 ]; then
    # commit ONLY the deleted paths (never sweep whatever else is staged); on failure undo only those paths
    git commit -q -m "chore(migration): drop unfilled Alembic placeholder stub (no revision identifiers)" -- "${_paths[@]}" 2>/dev/null \
      || { git reset -q -- "${_paths[@]}" 2>/dev/null; git checkout -q -- "${_paths[@]}" 2>/dev/null; }
  fi
  exit 0
fi

repo="${1:?repo_root}"; before="${2:?before}"; after="${3:?after}"

[ -n "${OVN_ALEMBIC_AUTOGEN_DISABLE:-}" ] && exit 0
cd "$repo" || exit 0
# OVN_ALEMBIC_AUTOGEN_NAME: the staged runner's checkout is a mktemp worktree (stage-<repo>.XXXX), so the
# basename is not the repo name the allowlist is keyed on.
name="${OVN_ALEMBIC_AUTOGEN_NAME:-$(basename "$repo")}"

# GATE 1 - allowlisted repos only (silent for the rest). Both have been trialled; billwatch's
# chain is Postgres-only (ALTER COLUMN TYPE) so it cannot replay on SQLite - leave it out.
# 2026-09-30: default was narrowed to test-automation-agent on the claim that iptv_apps "has no real
# model/migration drift". 2026-10-02 that claim is refuted by the live fleet: the iptv_apps item
# "Add last_event_ms column (BigInteger, nullable) to Subscription model" (T1; its T2 sibling creates
# the migration) failed test_migration_drift.py::test_alembic_head_matches_models 3 cycles in a row
# (a model-only commit can never pass), and the model's own hand-written migration then forked the
# chain (bad down_revision) and MIGRATION-SAFETY reverted it. iptv_apps is back on the allowlist; its
# trial (real clone, real model edit) is in the 2026-10-02 commit message.
allow="${OVN_ALEMBIC_AUTOGEN_REPOS:-test-automation-agent iptv_apps}"
case " $allow " in *" $name "*) ;; *) exit 0 ;; esac

# GATE 2 - exactly one alembic project, and it has adopted the drift-test pattern.
mapfile -t _inis < <(git ls-files -- '*alembic.ini' | grep -v 'alembic\.backup')
[ "${#_inis[@]}" -eq 1 ] || exit 0
proj="$(dirname "${_inis[0]}")"
[ -f "$proj/tests/test_migration_drift.py" ] || exit 0
vdir="$proj/alembic/versions"
# 2026-10-02: OVN_ALEMBIC_AUTOGEN_VENV_ROOT lets a caller whose checkout has no .venv (the staged runner
# works in a git WORKTREE; .venv is gitignored so a worktree never has one - same reason try_regen uses
# the main clone's venv) borrow the main clone's venv python while the hook still edits $repo.
PY="${OVN_ALEMBIC_AUTOGEN_VENV_ROOT:-$repo}/$proj/.venv/bin/python"; [ -x "$PY" ] || { say "skip: no $proj/.venv"; exit 0; }

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

# 2026-10-02: every call into the repo's code is time-boxed. env.py / app.main import can block (DB or
# network connect, a sleeping import) and this hook runs synchronously BEFORE verification, so an
# unbounded hang would stall the whole lane. GNU timeout signals its whole process group (no -
# --foreground), so grandchildren die too; -k escalates to KILL. A timeout = "not auto-fixable".
_TMO="${OVN_ALEMBIC_AUTOGEN_TIMEOUT:-120}"
_TO="$(command -v timeout || command -v gtimeout || true)"
tmo() { if [ -n "$_TO" ]; then "$_TO" -k 5 "$_TMO" "$@"; else "$@"; fi; }
run_driver() {  # $1 = message ; runs in the alembic project dir
  local raw rc
  raw="$( cd "$repo/$proj" && tmo "$PY" "$SCRIPT_DIR/ovn_alembic_autogen.py" --message "$1" 2>&1 )"; rc=$?
  if [ "$rc" = 124 ] || [ "$rc" = 137 ]; then echo "ERROR driver timed out after ${_TMO}s (env.py/model import hang?)"; return; fi
  # status line first, then (only on GENERATED) the `OPS ...` line naming every generated operation (H6 M3)
  printf '%s\n' "$raw" | grep -E '^(GENERATED|NODRIFT|REFUSE|ERROR)' | head -1
  printf '%s\n' "$raw" | grep -E '^OPS ' | head -1
}
split_out() {  # sets $out (status line only) and $ops (operation names) from run_driver's two-line output
  ops="$(printf '%s\n' "$out" | sed -n 's/^OPS //p' | head -1)"
  out="$(printf '%s\n' "$out" | grep -vE '^OPS ' | head -1)"
}
# H6 M2: a hand-written migration with DATA work (op.execute, bulk_insert, UPDATE/INSERT) that STEP B throws away
# is lost silently otherwise; the generator only ever emits schema DDL.
_DATA_RE='op\.execute|bulk_insert|\.update\(|\bUPDATE\b|\bINSERT\b|\bDELETE FROM\b'
discarded_data=""
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

out="$(run_driver "$msg")"; split_out

# STEP B - chain broken by the model's OWN migration work (stale down_revision like '009',
# two heads, edited an old migration): undo exactly what THIS cycle did under versions/ -
# delete files it added, restore files it modified/deleted - then retry ONCE.
if echo "$out" | grep -Eq '^REFUSE chain'; then
  say "chain broken by this cycle ($out) - reverting the cycle's own migration edits, then retrying once"
  # H6 M2: say LOUDLY if what we are about to discard contained data operations (backfill/seed/update): the
  # regenerated migration is schema-only, so that data work is LOST and needs a human to redo it.
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if git show "$after:$f" 2>/dev/null | grep -Eq "$_DATA_RE"; then
      discarded_data="${discarded_data:+$discarded_data, }$(basename "$f")"
      say "!! WARNING: discarding hand-written migration $f which contains DATA operations (op.execute/bulk_insert/UPDATE) - the regenerated migration is schema-only, the data work is LOST and needs a human"
    fi
  done < <(git diff --no-renames --name-only --diff-filter=AM "$before" "$after" -- "$vdir" | grep '\.py$')
  git diff --no-renames --name-only --diff-filter=A "$before" "$after" -- "$vdir" | grep '\.py$' | while IFS= read -r f; do git rm -q -f -- "$f" 2>/dev/null; done
  git diff --no-renames --name-only --diff-filter=MDT "$before" "$after" -- "$vdir" | grep '\.py$' | while IFS= read -r f; do git checkout -q "$before" -- "$f"; done
  out="$(run_driver "$msg")"; split_out
fi

case "$out" in
  GENERATED\ *)
    new="$proj/${out#GENERATED }"
    # final safety net: single head + the repo's static migration checks (dup ids, FK types)
    if [ -f "$SCRIPT_DIR/check_migrations.py" ] && ! tmo python3 "$SCRIPT_DIR/check_migrations.py" "$repo/$proj" >/dev/null 2>&1; then
      say "post-generate check_migrations.py failed - discarding"; git reset -q --hard HEAD; git clean -fdq -- "$vdir"; exit 0
    fi
    # H6 M3: the generator diffs the WHOLE model metadata against the chain, so unrelated pre-existing drift gets
    # bundled in silently. Name every operation, and flag the ones this cycle's diff never mentions.
    _unrel=""
    _cdiff="$(git diff --no-renames "$before" "$after" -- "$proj" ':!*/alembic/versions/*' 2>/dev/null | grep -E '^\+' )"
    while IFS= read -r _o; do
      [ -n "$_o" ] || continue
      _id="${_o#* }"; _id="${_id%% on *}"; _id="${_id##*.}"
      [ -n "$_id" ] && ! printf '%s\n' "$_cdiff" | grep -Fq -- "$_id" && _unrel="${_unrel:+$_unrel; }$_o"
    done < <(printf '%s\n' "$ops" | tr ';' '\n' | sed -E 's/^ +//')
    _body="Models changed without a matching migration (tests/test_migration_drift.py would fail).
Generated by scripts/ovn_alembic_autogen.py against a throwaway SQLite DB at head; new file: ${new}
Operations: ${ops:-(not reported)}"
    [ -n "$_unrel" ] && _body="$_body
NOTE - op(s) not traceable to this cycle's model diff (pre-existing drift bundled in?): ${_unrel}"
    [ -n "$discarded_data" ] && _body="$_body
WARNING - discarded hand-written migration(s) containing data operations (needs a human): ${discarded_data}"
    git add -A -- "$vdir"
    git commit -q -m "chore(migration): auto-generate Alembic migration for model change (deterministic, zero-LLM)

${_body}" \
      && say "generated and committed ${new} | ops: ${ops:-(not reported)}${_unrel:+ | UNRELATED?: $_unrel}"
    # 2026-10-02: the backlog splits a schema change into T1 (model) + T2 ("create migration ...").
    # Now that the hook writes the migration, the T2 item is satisfied before anyone attempts it;
    # left open, the model re-attempts it, writes a SECOND migration (the T2 item names its own
    # filename) and forks the chain. The credit helper marks ONLY open items that name a
    # not-yet-existing alembic/versions/*.py target AND every column/table this migration really
    # adds; anything else stays open. Same commit range as the migration, so a reverted cycle
    # reverts the credit too. Failure here is never fatal (the migration commit already stands).
    if [ -f OVERNIGHT_PROGRESS.md ] && [ -f "$SCRIPT_DIR/ovn_alembic_credit.py" ]; then
      _cr="$(python3 "$SCRIPT_DIR/ovn_alembic_credit.py" OVERNIGHT_PROGRESS.md "$new" "$repo" 2>/dev/null)"
      echo "$_cr" | grep '^NOT credited' | while IFS= read -r _l; do say "!! $_l"; done
      if echo "$_cr" | grep -qE '^CREDITED=[1-9]' && ! git diff --quiet -- OVERNIGHT_PROGRESS.md; then
        git add OVERNIGHT_PROGRESS.md
        git commit -q -m "chore(queue): credit migration item(s) satisfied by the auto-generated migration" \
          && say "credited open migration item(s): $(echo "$_cr" | tr '\n' ' ')"
      else
        git checkout -q -- OVERNIGHT_PROGRESS.md 2>/dev/null
      fi
    fi
    ;;
  NODRIFT*) say "no drift - nothing to generate"; git reset -q --hard HEAD; git clean -fdq -- "$vdir" ;;
  *)        say "not auto-fixable (${out:-no driver output}) - leaving the cycle's commit for the existing gates"
            git reset -q --hard HEAD; git clean -fdq -- "$vdir" ;;
esac
exit 0
