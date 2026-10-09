#!/usr/bin/env bash
# H6 follow-up tests (2026-10-02) for the deterministic Alembic autogen hook. Every NEGATIVE case below fails on the
# pre-fix code (c7c0dc1); the BENIGN cases pin that the new refusals did not over-block.
#   M1 driver refuses deterministically (not because SQLite cannot replay ALTER): DropIndexOp, DropConstraintOp
#      (unique + FK), AlterColumnOp nullable->NOT NULL / type change. Allowed: add nullable column, add NOT NULL with a
#      scalar default, new table, nullable->True. Refusal says 'needs a human' and leaves the tree exactly as the cycle
#      left it (HEAD, status, file list, an unfilled placeholder stub STEP A had removed).
#   M2 ovn_alembic_credit.py never credits an item whose text asks for backfill/data/update/populate/seed/constraint/
#      unique/index; the hook logs the skip loudly; STEP B warns loudly (log + commit message) when it discards a
#      hand-written migration that contained data operations.
#   M3 generated operation names appear in the commit message and the hook's log line; ops not traceable to the cycle's
#      own model diff are flagged (unrelated pre-existing drift).
# Needs a python with alembic+sqlalchemy: $OVN_TEST_PY, else a repo venv under ~/overnight-queue/repos (read-only use).
# SKIPs (exit 0) if none.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; SCRIPTS="$(cd "$HERE/.." && pwd)"
PYS="$SCRIPTS/ovn_alembic_autogen.py"; HOOK="$SCRIPTS/ovn_alembic_autogen.sh"; CRED="$SCRIPTS/ovn_alembic_credit.py"
PYX=""
for c in "${OVN_TEST_PY:-}" "$HOME"/overnight-queue/repos/*/.venv/bin/python "$HOME"/overnight-queue/repos/*/*/.venv/bin/python python3; do
  [ -n "$c" ] || continue
  if "$c" -c 'import alembic, sqlalchemy; from alembic import command; command.check' 2>/dev/null; then PYX="$c"; break; fi
done
fail=0; ok(){ echo "  ok   - $1"; }; bad(){ echo "  FAIL - $1"; fail=1; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export TMPDIR="$T/tmpd"; mkdir -p "$TMPDIR"; unset DATABASE_URL ANTHROPIC_API_KEY

echo "C  credit helper (stdlib only - runs without alembic)"
mkdir -p "$T/c/proj/alembic/versions"; cd "$T/c" || exit 1
printf 'revision="0002_x"\ndown_revision="0001"\ndef upgrade():\n    op.add_column("items", sa.Column("note", sa.String(length=20), nullable=True))\ndef downgrade():\n    op.drop_column("items", "note")\n' > proj/alembic/versions/0002_x.py
credit_one() {  # $1 = item text after the path ; echoes helper output
  printf -- '- [ ] [T2] proj/alembic/versions/0009_y.py — %s (cat:schema; multifile:no)\n' "$1" > P.md
  python3 "$CRED" P.md proj/alembic/versions/0002_x.py "$PWD"
}
for txt in 'Create migration to add `note` column and backfill existing rows' \
           'Create migration to add `note` column, then populate it from name' \
           'Create migration to add `note` column plus a unique constraint' \
           'Create migration to add `note` column with an index' \
           'Create migration for `note` and seed default data' \
           'Create migration for `note` and update existing rows' \
           'Create migration for `note` (migrate the data)'; do
  out="$(credit_one "$txt")"
  if [ "$(echo "$out" | tail -1)" = "CREDITED=0" ] && echo "$out" | grep -q 'NOT credited line 1.*needs a human' && grep -q '^- \[ \]' P.md; then ok "not credited + logged loudly: ${txt:0:58}"; else bad "credited/silent: ${txt:0:58} -> $out"; fi
done
printf -- '- [ ] [T2] proj/alembic/versions/0009_epg_active_unique.py — Create migration for `note`. (cat:schema)\n' > P.md
out="$(python3 "$CRED" P.md proj/alembic/versions/0002_x.py "$PWD")"
[ "$(echo "$out" | tail -1)" = "CREDITED=0" ] && ok "a *_unique.py filename slug blocks credit too" || bad "slug not considered: $out"
for txt in 'Create migration to add `note` column to items table.' 'Create migration adding `note` to the items database table.' 'Alembic migration: add nullable `note` column (metadata only).'; do
  out="$(credit_one "$txt")"
  [ "$(echo "$out" | tail -1)" = "CREDITED=1" ] && ok "plain-DDL wording still CREDITED: ${txt:0:55}" || bad "plain DDL wrongly blocked: $txt -> $out"
done
cd "$HERE" || exit 1

[ -n "$PYX" ] || { echo "SKIP M1/M2-hook/M3: no python with alembic+sqlalchemy found"; [ "$fail" = 0 ] && echo "ALL PASS (credit only)" || { echo FAILURES; exit 1; }; exit 0; }

# ---- project factory -------------------------------------------------------------------------------------
# baseline chain: items(id, name NOT NULL w/ index ix_items_name, tag nullable, email w/ unique uq_items_email,
# qty String) + a child table with a named FK. The model below matches it exactly (no drift).
write_model() {  # $1 = project dir ; $2 = variant
  local v="${2:-base}" targs='UniqueConstraint("email", name="uq_items_email"), Index("ix_items_name", "name")'
  local name='Column(String(50), nullable=False)' tag='Column(String(20), nullable=True)' qty='Column(String(10), nullable=True)' extra='' fk='ForeignKey("items.id", name="fk_child_item")'
  case "$v" in
    idx_removed)  targs='UniqueConstraint("email", name="uq_items_email")';;
    uq_removed)   targs='Index("ix_items_name", "name")';;
    fk_removed)   fk='Integer';;
    notnull)      tag='Column(String(20), nullable=False)';;
    typechg)      qty='Column(Integer, nullable=True)';;
    nullable_true) name='Column(String(50), nullable=True)';;
    add_nullable) extra='    note = Column(String(20))';;
    add_notnull_default) extra='    score = Column(Integer, nullable=False, default=0)';;
    add_notnull_nodefault) extra='    score = Column(Integer, nullable=False)';;
    unrelated)    extra='    legacy_flag = Column(Integer, nullable=True)';;
  esac
  local childcol="Column(Integer, $fk)"; [ "$v" = fk_removed ] && childcol='Column(Integer)'
  cat > "$1/app/models.py" <<PY
from sqlalchemy import Column, ForeignKey, Index, Integer, String, UniqueConstraint
from sqlalchemy.orm import declarative_base
Base = declarative_base()
class Item(Base):
    __tablename__ = "items"
    __table_args__ = ($targs,)
    id = Column(Integer, primary_key=True)
    name = $name
    tag = $tag
    email = Column(String(50))
    qty = $qty
$extra
class Child(Base):
    __tablename__ = "child"
    id = Column(Integer, primary_key=True)
    item_id = $childcol
PY
  if [ "$v" = new_table ]; then printf 'class Fresh(Base):\n    __tablename__ = "fresh"\n    id = Column(Integer, primary_key=True)\n    label = Column(String(10), nullable=False, default="x")\n' >> "$1/app/models.py"; fi
}
mkproj() {  # $1 = dir
  local P="$1"; mkdir -p "$P/app" "$P/alembic/versions" "$P/tests"
  printf '[alembic]\nscript_location = alembic\nprepend_sys_path = .\n' > "$P/alembic.ini"
  : > "$P/app/__init__.py"; printf 'from app import models  # noqa: F401\n' > "$P/app/main.py"
  write_model "$P" base
  cat > "$P/alembic/env.py" <<'PY'
import os
from alembic import context
from sqlalchemy import create_engine
import app.main  # noqa: F401
from app.models import Base
def run():
    eng = create_engine(os.environ["DATABASE_URL"])
    with eng.connect() as c:
        context.configure(connection=c, target_metadata=Base.metadata, compare_type=True)
        with context.begin_transaction():
            context.run_migrations()
run()
PY
  cat > "$P/alembic/script.py.mako" <<'PY'
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
  cat > "$P/alembic/versions/0001_baseline.py" <<'PY'
"""baseline"""
from alembic import op
import sqlalchemy as sa
revision = "0001_baseline"
down_revision = None
branch_labels = None
depends_on = None
def upgrade():
    op.create_table("items", sa.Column("id", sa.Integer(), primary_key=True), sa.Column("name", sa.String(50), nullable=False),
                    sa.Column("tag", sa.String(20), nullable=True), sa.Column("email", sa.String(50)), sa.Column("qty", sa.String(10), nullable=True),
                    sa.UniqueConstraint("email", name="uq_items_email"))
    op.create_index("ix_items_name", "items", ["name"])
    op.create_table("child", sa.Column("id", sa.Integer(), primary_key=True), sa.Column("item_id", sa.Integer(), sa.ForeignKey("items.id", name="fk_child_item")))
def downgrade():
    op.drop_table("child"); op.drop_table("items")
PY
  echo "def test_alembic_head_matches_models(): pass" > "$P/tests/test_migration_drift.py"
}
runpy() { local d="$1"; shift; ( cd "$d" && "$PYX" "$PYS" "$@" 2>&1 ); }
nver() { ls "$1"/alembic/versions/*.py 2>/dev/null | wc -l | tr -d ' '; }
newp() { P="$(mktemp -d "$T/p.XXXXXX")"; mkproj "$P"; write_model "$P" "$1"; }

echo "M1 driver: NEGATIVE - each removal/alteration is refused ('needs a human'), no file left behind, rc 11"
for v in idx_removed uq_removed fk_removed notnull typechg; do
  newp "$v"; out="$(runpy "$P" --message "m $v")"; rc=$?
  if [ $rc = 11 ] && echo "$out" | grep -q '^REFUSE .*needs a human' && [ "$(nver "$P")" = 1 ]; then ok "$v refused: $(echo "$out" | grep '^REFUSE' | cut -c1-110)"; else bad "$v rc=$rc nver=$(nver "$P"): $out"; fi
done
echo "M1 driver: --allow-destructive still lets a human-requested run through"
newp idx_removed; out="$(runpy "$P" --message x --allow-destructive)"; rc=$?
[ $rc = 0 ] && echo "$out" | grep -q '^GENERATED' && ok "--allow-destructive generates the drop_index migration" || bad "allow-destructive rc=$rc: $out"
echo "M1 driver: BENIGN - still generated (and the OPS line names the operations)"
for v in add_nullable add_notnull_default new_table nullable_true; do
  newp "$v"; out="$(runpy "$P" --message "m $v")"; rc=$?
  ops="$(echo "$out" | sed -n 's/^OPS //p')"
  if [ $rc = 0 ] && echo "$out" | grep -q '^GENERATED' && [ "$(nver "$P")" = 2 ] && [ -n "$ops" ]; then ok "$v generated; OPS: $ops"; else bad "$v rc=$rc: $out"; fi
done
newp add_nullable;  out="$(runpy "$P" --message x)"; echo "$out" | grep -q '^OPS add_column items.note$' && ok "OPS line exact: add_column items.note" || bad "ops: $out"
newp new_table;     out="$(runpy "$P" --message x)"; echo "$out" | grep -q '^OPS create_table fresh$' && ok "OPS line exact: create_table fresh" || bad "ops: $out"
newp nullable_true; out="$(runpy "$P" --message x)"; echo "$out" | grep -q 'alter_column items.name' && grep -q 'nullable=True' "$P"/alembic/versions/0002_*.py && ok "nullable->True generates an alter_column (nullable=True)" || bad "nullable_true: $out"
newp add_notnull_default; runpy "$P" --message x >/dev/null; grep -q "server_default" "$P"/alembic/versions/0002_*.py && ok "NOT NULL add gets a server_default injected" || bad "no server_default"
newp add_notnull_nodefault; out="$(runpy "$P" --message x)"; [ $? = 11 ] && echo "$out" | grep -q 'needs a human' && ok "NOT NULL add with no scalar default still refused (unchanged behaviour)" || bad "$out"

# ---- hook level ------------------------------------------------------------------------------------------
mkrepo() {  # echoes repo root; project in proj/, committed as 'base'; .venv symlinked to the test python's venv
  local R; R="$(mktemp -d "$T/r.XXXXXX")/iptv_apps"; mkdir -p "$R"; cd "$R" || exit 1
  git init -q . && git config user.email t@t && git config user.name t
  mkproj "$R/proj"; ln -s "$(dirname "$(dirname "$PYX")")" proj/.venv; printf '.venv\n__pycache__/\n' > .gitignore
  cat > OVERNIGHT_PROGRESS.md <<'MD'
- [ ] [T1] proj/app/models.py — Add `note` column (String(20), nullable) to Item model. (cat:schema)
- [ ] [T2] proj/alembic/versions/0002_item_note.py — Create migration to add `note` column to items table. (cat:schema; multifile:no)
MD
  git add -A && git commit -qm base && echo "$R"
}
hook() { ( export PATH=/usr/local/bin:/usr/bin:/bin; bash "$HOOK" "$PWD" "$1" "$(git rev-parse HEAD)" 2>&1 ); }
snap() { { git rev-parse HEAD; git status --porcelain -uall; git ls-files -s; find proj/alembic/versions -type f -name '*.py' | sort; } | md5sum | cut -d' ' -f1; }

echo "M1 hook: a refusal leaves the tree EXACTLY as the cycle left it (incl. an unfilled placeholder stub STEP A removed)"
for v in idx_removed uq_removed fk_removed notnull typechg; do
  R="$(mkrepo)"; cd "$R"; B=$(git rev-parse HEAD)
  printf '"""Placeholder - the implement step fills in this migration"""\n' > proj/alembic/versions/0002_stub.py
  write_model proj "$v"; git add -A; git commit -qm "feat: $v"; before="$(snap)"
  out="$(hook "$B")"; after="$(snap)"
  if [ "$before" = "$after" ] && echo "$out" | grep -q 'not auto-fixable (REFUSE .*needs a human' && git diff --quiet HEAD -- && [ -f proj/alembic/versions/0002_stub.py ]; then ok "$v: hook refuses, tree + HEAD + stub untouched"; else bad "$v: tree changed or no log: $out"; git status --short | head -3; fi
done

echo "M3 hook: operation names in the commit message and the log line; unrelated pre-existing drift is flagged"
R="$(mkrepo)"; cd "$R"
write_model proj unrelated; git add -A; git commit -qm "chore: someone added legacy_flag without a migration"; B=$(git rev-parse HEAD)
sed -i 's/^    qty = .*/&\n    note = Column(String(20))/' proj/app/models.py; git add -A; git commit -qm "feat(models): add item note column"
out="$(hook "$B")"; msg="$(git log -2 --format=%B | head -40)"
echo "$out" | grep -q 'generated and committed .*| ops: .*add_column items.note' && echo "$out" | grep -q 'add_column items.legacy_flag' && ok "hook log names both operations" || bad "log: $out"
git log --format=%B -n 3 | grep -q '^Operations: .*add_column items.note' && git log --format=%B -n 3 | grep -q 'add_column items.legacy_flag' && ok "commit message lists Operations: (both)" || bad "commit msg: $(git log --format=%B -n 2)"
echo "$out" | grep -q 'UNRELATED?: add_column items.legacy_flag' && ! echo "$out" | grep -q 'UNRELATED?:.*items.note' && ok "only the pre-existing drift is flagged UNRELATED (not the cycle's own note column)" || bad "unrelated flag wrong: $out"
git log --format=%B -n 3 | grep -q 'NOTE - op(s) not traceable to this cycle' && ok "commit message carries the NOTE for the bundled drift" || bad "no NOTE in commit"
R="$(mkrepo)"; cd "$R"; B=$(git rev-parse HEAD)
sed -i 's/^    qty = .*/&\n    note = Column(String(20))/' proj/app/models.py; git add -A; git commit -qm "feat(models): add item note column"
out="$(hook "$B")"; echo "$out" | grep -q 'UNRELATED' && bad "benign: clean change falsely flagged: $out" || ok "benign: a clean model change is not flagged UNRELATED"

echo "M2 hook: STEP B warns loudly when it discards a hand-written migration with data operations"
R="$(mkrepo)"; cd "$R"; B=$(git rev-parse HEAD)
sed -i 's/^    qty = .*/&\n    note = Column(String(20))/' proj/app/models.py
printf 'from alembic import op\nimport sqlalchemy as sa\nrevision = "0002_item_note"\ndown_revision = "0009"\nbranch_labels = None\ndepends_on = None\ndef upgrade():\n    op.add_column("items", sa.Column("note", sa.String(20)))\n    op.execute("UPDATE items SET note = name")\ndef downgrade(): pass\n' > proj/alembic/versions/0002_item_note.py
git add -A; git commit -qm "feat: note + backfill migration"
out="$(hook "$B")"
echo "$out" | grep -q '!! WARNING: discarding hand-written migration proj/alembic/versions/0002_item_note.py which contains DATA operations' && ok "log warns about the discarded data migration" || bad "no warning: $out"
git log --format=%B -n 3 | grep -q 'WARNING - discarded hand-written migration(s) containing data operations (needs a human): 0002_item_note.py' && ok "commit message records the loss" || bad "no WARNING in commit: $(git log --format=%B -n 2)"
R="$(mkrepo)"; cd "$R"; B=$(git rev-parse HEAD)
sed -i 's/^    qty = .*/&\n    note = Column(String(20))/' proj/app/models.py
printf 'from alembic import op\nimport sqlalchemy as sa\nrevision = "0002_item_note"\ndown_revision = "0009"\nbranch_labels = None\ndepends_on = None\ndef upgrade():\n    op.add_column("items", sa.Column("note", sa.String(20)))\ndef downgrade(): pass\n' > proj/alembic/versions/0002_item_note.py
git add -A; git commit -qm "feat: note + plain forked migration"
out="$(hook "$B")"
echo "$out" | grep -q 'WARNING: discarding' && bad "benign: schema-only forked migration warned: $out" || ok "benign: discarding a schema-only forked migration does not warn"
echo "$out" | grep -q 'generated and committed' && ok "benign: still regenerated cleanly" || bad "not regenerated: $out"

echo "M2 hook: a T2 'create migration' item that asks for a backfill stays OPEN and the skip is logged"
R="$(mkrepo)"; cd "$R"; B=$(git rev-parse HEAD)
printf -- '- [ ] [T2] proj/alembic/versions/0002_item_note.py — Create migration to add `note` column to items and backfill existing rows from name. (cat:schema)\n- [ ] [T2] proj/alembic/versions/0003_other.py — Create migration to add `note` column to items table. (cat:schema)\n' > OVERNIGHT_PROGRESS.md
git add -A; git commit -qm "queue"; B=$(git rev-parse HEAD)
sed -i 's/^    qty = .*/&\n    note = Column(String(20))/' proj/app/models.py; git add -A; git commit -qm "feat(models): add item note column"
out="$(hook "$B")"
grep -q '^- \[ \] \[T2\] proj/alembic/versions/0002_item_note.py — Create migration to add `note` column to items and backfill' OVERNIGHT_PROGRESS.md && ok "backfill item NOT credited (still open)" || bad "backfill item credited: $(cat OVERNIGHT_PROGRESS.md)"
grep -q '^- \[x\] (satisfied by auto-generated migration .*) \[T2\] proj/alembic/versions/0003_other.py' OVERNIGHT_PROGRESS.md && ok "benign sibling item still credited" || bad "benign sibling not credited: $(cat OVERNIGHT_PROGRESS.md)"
echo "$out" | grep -q '!! NOT credited line 1.*needs a human' && ok "hook log shows the loud skip" || bad "no loud skip: $out"

[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILURES"; exit 1; }
