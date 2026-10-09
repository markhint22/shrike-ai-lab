#!/usr/bin/env bash
# test_ovn_stage_runner_alembic.sh - H6 M4 (2026-10-02): the Alembic autogen hook, wired into the REAL ovn_stage_runner.sh,
# exercised END TO END in the hermetic fake tree of lib_osr_fixture.sh (local bare origin, stub aider / autotest / pytest /
# LLM). Only the model + the repo's test suite are faked: the autogen hook, the credit helper, check_migrations.py and alembic
# itself are the real files (alembic runs under a real venv python, $OVN_TEST_PY or a repo venv under ~/overnight-queue).
#   A  a model-only staged step gets its migration generated in the same run; the generated commit (and the T2 credit commit)
#      are part of the run: verified together and pushed together; the hook ran BEFORE the independent full_verify.
#   B  the T2 "create migration" backlog item is credited, so the next run finds nothing to do and no 2nd migration appears.
#   C  a run whose independent verification FAILS is discarded as a unit: nothing (migration, credit) reaches origin.
#   D  a run where every step is reverted never invokes the hook: no migration anywhere.
#   E  a "create migration" step that hand-writes a forked migration (stale down_revision) is repaired: one head, one file.
#   F  a refusal (dropped index) inside the staged flow: no migration, the run still verifies on its own merits, tree intact.
# SKIPs (exit 0) when no python with alembic+sqlalchemy exists.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_osr_fixture.sh"
trap osr_cleanup EXIT
PYX=""
for c in "${OVN_TEST_PY:-}" "$HOME"/overnight-queue/repos/*/.venv/bin/python "$HOME"/overnight-queue/repos/*/*/.venv/bin/python; do
  [ -n "$c" ] && [ -x "$c" ] || continue
  if "$c" -c 'import alembic, sqlalchemy; from alembic import command; command.check' 2>/dev/null; then PYX="$c"; break; fi
done
[ -n "$PYX" ] || { echo "SKIP: no python with alembic+sqlalchemy found"; exit 0; }
G(){ grep -qF -- "$1" "$T/out.txt"; }
J(){ osr_jsonl | grep -F -- "$1" >/dev/null; }
export OVN_STAGE_DEDICATE=0 OVN_VERIFY_REPAIR_ROUNDS=0 OVN_VERIFY_REGEN=0 OVN_ALEMBIC_AUTOGEN_REPOS="$OSR_REPO" OVN_STAGE_MAX_ATTEMPTS=1 OVN_STAGE_REDECOMP=0

ITEM_MODEL='[T3] backend/app/models.py — Add note column (String(20), nullable) to the Item model. VERIFY: `pytest backend/tests` (cat:python)'
ITEM_MIG='[T3] backend/alembic/versions/0002_item_note.py — Create migration to add `note` column to the items table. (cat:schema; multifile:no)'
PLAN1='[{"desc":"add note column to Item model","files":["backend/app/models.py"],"verify":"pytest backend/tests"}]'
PLAN2='[{"desc":"add note column to Item model","files":["backend/app/models.py"],"verify":"pytest backend/tests"},{"desc":"create the migration for note","files":["backend/alembic/versions/0002_item_note.py"],"verify":"pytest backend/tests"}]'
SNIP_NOTE='sed -i "s/^    name = .*/&\n    note = Column(String(20))/" backend/app/models.py'
SNIP_DROPIDX='sed -i "s/, Index(\"ix_items_name\", \"name\")//" backend/app/models.py'
SNIP_FORKED='printf "from alembic import op\nimport sqlalchemy as sa\nrevision = \"0002_item_note\"\ndown_revision = \"0009\"\nbranch_labels = None\ndepends_on = None\ndef upgrade():\n    op.add_column(\"items\", sa.Column(\"note\", sa.String(20)))\ndef downgrade(): pass\n" > backend/alembic/versions/0002_item_note.py'

alembic_tree() {  # fresh fake tree whose repo has a real alembic project under backend/ + the hook scripts in the fake pipeline
  osr_new; osr_venv backend
  printf '#!/usr/bin/env bash\nexec "%s" "$@"\n' "$PYX" > "$RD/backend/.venv/bin/python"; chmod +x "$RD/backend/.venv/bin/python"   # the hook needs a python WITH alembic
  cp "$REALQ/scripts/ovn_alembic_autogen.sh" "$REALQ/scripts/ovn_alembic_autogen.py" "$REALQ/scripts/ovn_alembic_credit.py" "$REALQ/scripts/check_migrations.py" "$Q/scripts/"
  chmod +x "$Q/scripts/ovn_alembic_autogen.sh" "$Q/scripts/ovn_alembic_autogen.py"
  local b="$RD/backend"; mkdir -p "$b/alembic/versions"
  printf '[alembic]\nscript_location = alembic\nprepend_sys_path = .\n' > "$b/alembic.ini"
  cat > "$b/app/models.py" <<'PY'
from sqlalchemy import Column, Index, Integer, String, UniqueConstraint
from sqlalchemy.orm import declarative_base
Base = declarative_base()
class Item(Base):
    __tablename__ = "items"
    __table_args__ = (UniqueConstraint("email", name="uq_items_email"), Index("ix_items_name", "name"),)
    id = Column(Integer, primary_key=True)
    name = Column(String(50), nullable=False)
    email = Column(String(50))
PY
  cat > "$b/alembic/env.py" <<'PY'
import os
from alembic import context
from sqlalchemy import create_engine
from app.models import Base
def run():
    eng = create_engine(os.environ["DATABASE_URL"])
    with eng.connect() as c:
        context.configure(connection=c, target_metadata=Base.metadata, compare_type=True)
        with context.begin_transaction():
            context.run_migrations()
run()
PY
  cat > "$b/alembic/script.py.mako" <<'PY'
"""${message}"""
from alembic import op
import sqlalchemy as sa
${imports if imports else ""}
revision = ${repr(up_revision)}
down_revision = ${repr(down_revision)}
branch_labels = None
depends_on = None


def upgrade():
    ${upgrades if upgrades else "pass"}


def downgrade():
    ${downgrades if downgrades else "pass"}
PY
  cat > "$b/alembic/versions/0001_baseline.py" <<'PY'
"""baseline"""
from alembic import op
import sqlalchemy as sa
revision = "0001_baseline"
down_revision = None
branch_labels = None
depends_on = None
def upgrade():
    op.create_table("items", sa.Column("id", sa.Integer(), primary_key=True), sa.Column("name", sa.String(50), nullable=False),
                    sa.Column("email", sa.String(50)), sa.UniqueConstraint("email", name="uq_items_email"))
    op.create_index("ix_items_name", "items", ["name"])
def downgrade():
    op.drop_table("items")
PY
  echo "def test_alembic_head_matches_models(): pass" > "$b/tests/test_migration_drift.py"
  git -C "$RD" add -A; git -C "$RD" commit -q -m "alembic project"; git -C "$RD" push -q origin HEAD:overnight/feature
  osr_progress "- [ ] $ITEM_MODEL" "- [ ] $ITEM_MIG"
}
o_tree()  { git -C "$O" ls-tree -r --name-only overnight/feature; }
o_migs()  { o_tree | grep -c '^backend/alembic/versions/.*\.py$'; }
o_prog()  { osr_origin_file OVERNIGHT_PROGRESS.md; }
chain_ok(){  # materialise origin's tree and run the repo-agnostic chain check the MIGRATION-SAFETY gate uses
  local d; d="$(mktemp -d "$T/chk.XXXX")"; git -C "$O" archive overnight/feature backend/alembic | tar -x -C "$d"
  python3 "$REALQ/scripts/check_migrations.py" "$d/backend" >/dev/null 2>&1; }

echo "== A: model-only staged step -> migration generated in the same run, verified + pushed with it"
alembic_tree; osr_plan default "$PLAN1"; osr_aider 1 "$SNIP_NOTE"
H0="$(git -C "$O" rev-parse overnight/feature)"
osr_run "$OSR_REPO"
t "run ends 1/1 landed, independently verified" bash -c "[ $RC = 0 ] && grep -q 'independent full-verify: PASSED' '$T/out.txt' && grep -q 'DONE: 1/1 steps landed' '$T/out.txt'"
t "hook log names the generated file AND its operations" G "ALEMBIC-AUTOGEN: generated and committed backend/alembic/versions/0002_"
t "operation names in the log line" bash -c "grep -q 'ops: add_column items.note' '$T/out.txt'"
t "hook outcome journaled" J '"event":"alembic_autogen"'
t "hook ran BEFORE the independent full_verify" bash -c "[ \$(grep -n 'ALEMBIC-AUTOGEN: generated' '$T/out.txt' | head -1 | cut -d: -f1) -lt \$(grep -n 'independent full-verify' '$T/out.txt' | head -1 | cut -d: -f1) ]"
t "origin has the generated migration (2 files: baseline + new)" bash -c "[ \$(git -C '$O' ls-tree -r --name-only overnight/feature | grep -c '^backend/alembic/versions/.*\\.py\$') = 2 ]"
t "the migration commit is on origin, with an Operations: list" bash -c "git -C '$O' log --format=%B $H0..overnight/feature | grep -q '^Operations: add_column items.note'"
t "step + migration + credit = 3 verified commits pushed together" G "pushed 3 verified commit(s)"
t "T2 'create migration' item credited on origin" bash -c "git -C '$O' show overnight/feature:OVERNIGHT_PROGRESS.md | grep -q '^- \[x\] (satisfied by auto-generated migration 0002_.*\.py) \[T3\] backend/alembic/versions/0002_item_note.py'"
t "T1/model item checked off by the runner itself" bash -c "git -C '$O' show overnight/feature:OVERNIGHT_PROGRESS.md | grep -q '^- \[x\] \[T3\] backend/app/models.py.*staged 1/1 DONE'"
t "origin chain is a single linear head (check_migrations.py)" chain_ok
MIGN="$(o_migs)"; HA="$(git -C "$O" rev-parse overnight/feature)"

echo "== B: the next run finds the T2 item satisfied -> nothing to do, no duplicate migration"
osr_run "$OSR_REPO"
t "picker finds no doable item (T2 credited, T1 done)" G "no doable T3+ item found"
t "no second migration, origin untouched" bash -c "[ \"\$(git -C '$O' rev-parse overnight/feature)\" = '$HA' ] && [ $MIGN = 2 ]"
osr_cleanup

echo "== B2: negative control - WITHOUT the hook the T2 item stays open and the run lacks a migration (proves A is the hook's doing)"
alembic_tree; osr_plan default "$PLAN1"; osr_aider 1 "$SNIP_NOTE"
OVN_ALEMBIC_AUTOGEN_DISABLE=1 osr_run "$OSR_REPO"
t "hook disabled: no migration on origin" bash -c "[ \$(git -C '$O' ls-tree -r --name-only overnight/feature | grep -c '^backend/alembic/versions/.*\\.py\$') = 1 ]"
t "hook disabled: T2 item still open" bash -c "git -C '$O' show overnight/feature:OVERNIGHT_PROGRESS.md | grep -q '^- \[ \] \[T3\] backend/alembic/versions/0002_item_note.py'"
osr_cleanup

echo "== C: independent verification fails -> the whole run (step + generated migration + credit) is discarded"
alembic_tree; osr_plan default "$PLAN1"; osr_aider 1 "$SNIP_NOTE"; echo fail > "$T/scn/pytest.mode"
H0="$(git -C "$O" rev-parse overnight/feature)"
osr_run "$OSR_REPO"
t "migration WAS generated in the worktree (hook ran) ..." G "ALEMBIC-AUTOGEN: generated and committed"
t "... verification failed and nothing was pushed" bash -c "grep -q 'independent full-verify: FAILED' '$T/out.txt' && ! grep -q 'verified commit' '$T/out.txt'"
t "origin has NO migration and no staged commit" bash -c "[ \$(git -C '$O' ls-tree -r --name-only overnight/feature | grep -c '^backend/alembic/versions/.*\\.py\$') = 1 ] && ! git -C '$O' log --format=%s $H0..overnight/feature | grep -q 'staged step\|auto-generate'"
t "T2 item NOT credited on origin (credit rode the discarded run)" bash -c "! git -C '$O' show overnight/feature:OVERNIGHT_PROGRESS.md | grep -q 'satisfied by auto-generated'"
osr_cleanup

echo "== D: every step reverted -> hook never runs, no migration anywhere"
alembic_tree; osr_plan default "$PLAN1"   # stub aider edits nothing -> no-edit, step reverted
osr_run "$OSR_REPO"
t "step reverted (no-edit) and nothing landed" bash -c "grep -q 'step 0 BLOCKED' '$T/out.txt' && grep -q 'DONE: 0/1 steps landed' '$T/out.txt'"
t "hook not invoked when nothing passed" bash -c "! grep -q 'ALEMBIC-AUTOGEN' '$T/out.txt'"
t "no migration on origin" bash -c "[ \$(git -C '$O' ls-tree -r --name-only overnight/feature | grep -c '^backend/alembic/versions/.*\\.py\$') = 1 ]"
osr_cleanup

echo "== E: a 'create migration' STEP that hand-writes a forked migration (stale down_revision) is repaired, not duplicated"
alembic_tree; osr_plan default "$PLAN2"; osr_aider 1 "$SNIP_NOTE"; osr_aider 2 "$SNIP_FORKED"
osr_run "$OSR_REPO"
t "both steps landed, hook repaired the chain" bash -c "grep -q 'DONE: 2/2 steps landed' '$T/out.txt' && grep -q 'chain broken by this cycle' '$T/out.txt' && grep -q 'generated and committed' '$T/out.txt'"
t "verified + pushed" G "independent full-verify: PASSED"
t "origin: exactly one new migration, no stale-0009 file, single head" bash -c "[ \$(git -C '$O' ls-tree -r --name-only overnight/feature | grep -c '^backend/alembic/versions/.*\\.py\$') = 2 ] && ! git -C '$O' grep -q 'down_revision = \"0009\"' overnight/feature -- backend/alembic"
t "origin chain check passes" chain_ok
osr_cleanup

echo "== F: refusal inside the staged flow (model drops an index) -> no migration, hook says 'needs a human', verify decides alone"
alembic_tree; osr_plan default "$PLAN1"; osr_aider 1 "$SNIP_DROPIDX"
osr_run "$OSR_REPO"
t "hook refuses with 'needs a human'" bash -c "grep -q 'ALEMBIC-AUTOGEN: not auto-fixable (REFUSE .*drop_index.*needs a human' '$T/out.txt'"
t "no migration generated or pushed (tree left as the step left it)" bash -c "[ \$(git -C '$O' ls-tree -r --name-only overnight/feature | grep -c '^backend/alembic/versions/.*\\.py\$') = 1 ] && ! git -C '$O' log --format=%s overnight/feature | grep -q 'auto-generate'"
t "model-only step still verified on its own merits (stub suite green) and pushed" bash -c "grep -q 'pushed 1 verified commit' '$T/out.txt'"
t "T2 item not credited" bash -c "! git -C '$O' show overnight/feature:OVERNIGHT_PROGRESS.md | grep -q 'satisfied by auto-generated'"
osr_cleanup

osr_summary
