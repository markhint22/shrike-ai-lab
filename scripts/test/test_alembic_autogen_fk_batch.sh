#!/usr/bin/env bash
# 2026-10-20 (iptv-reverts): a model column with ForeignKey(...) made autogenerate emit op.create_foreign_key, which SQLite cannot ALTER, so the
# hook's post-generate validation failed ("not auto-fixable") on EVERY attempt and the 27B hand-wrote a forked migration (iptv search_history.profile_id:
# 3x reverted(migration-fork)). Fix: render batch style + deterministic constraint names when the diff carries create FK/unique/check ops.
# Mutant: OVN_ALEMBIC_BATCH_CONSTRAINTS=off restores the pre-fix behaviour and MUST fail with the SQLite NotImplementedError.
# Needs a python with alembic+sqlalchemy ($OVN_TEST_PY, else a repo venv under ~/overnight-queue/repos). SKIPs (exit 0) if none.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
HERE="$(cd "$(dirname "$0")" && pwd)"; SCRIPTS="$(cd "$HERE/.." && pwd)"
PYS="$SCRIPTS/ovn_alembic_autogen.py"
PYX=""
for c in "${OVN_TEST_PY:-}" "$HOME"/overnight-queue/repos/*/.venv/bin/python "$HOME"/overnight-queue/repos/*/*/.venv/bin/python "$HOME"/LocalProjects/*/*/venv/bin/python python3; do
  [ -n "$c" ] || continue
  if "$c" -c 'import alembic, sqlalchemy; from alembic import command; command.check' 2>/dev/null; then PYX="$c"; break; fi
done
fail=0; ok(){ echo "  ok   - $1"; }; bad(){ echo "  FAIL - $1"; fail=1; }
T="$(safe_mktemp_dir)" || exit 1; trap 'rm -rf "$T"' EXIT
export TMPDIR="$T/tmpd"; mkdir -p "$TMPDIR"; export OVN_SAFE_RM_ROOTS="$T"; unset DATABASE_URL ANTHROPIC_API_KEY
[ -n "$PYX" ] || { echo "SKIP: no python with alembic+sqlalchemy found"; exit 0; }
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
newp() { P="$(safe_mktemp_dir_in "$T" p)" || exit 1; mkproj "$P"; write_model "$P" "$1"; }

# a new nullable FK column on items (+ index, as the iptv model has)
add_fk_model() { python3 - "$1/app/models.py" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
s = s.replace("    qty = Column(String(10), nullable=True)\n", "    qty = Column(String(10), nullable=True)\n    owner_id = Column(Integer, ForeignKey(\"child.id\"), index=True, nullable=True)\n", 1)
open(p, "w").write(s)
PY
}

echo "FK add_column: generated, batch style, named constraints, upgrade/downgrade round-trips on SQLite"
newp base; add_fk_model "$P"; out="$(runpy "$P" --message "owner id")"; rc=$?
f="$(ls "$P"/alembic/versions/*owner_id.py 2>/dev/null | head -1)"
[ $rc = 0 ] && echo "$out" | grep -q '^GENERATED' && ok "FK column migration GENERATED (rc 0)" || bad "FK column not generated rc=$rc: $out"
[ -n "$f" ] && grep -q 'batch_alter_table' "$f" && ok "rendered in batch style" || bad "not batch style: $(cat "$f" 2>/dev/null | tail -15)"
[ -n "$f" ] && ! grep -q 'drop_constraint(None' "$f" && grep -q "drop_constraint('fk_items_owner_id_child'" "$f" && ok "downgrade drops the FK by NAME (not None)" || bad "downgrade FK unnamed: $(grep drop_constraint "$f" 2>/dev/null)"
rt="$(cd "$P" && DATABASE_URL="sqlite:///$T/rt.db" "$PYX" -c "
from alembic import command; from alembic.config import Config
c=Config('alembic.ini'); command.upgrade(c,'head'); command.downgrade(c,'-1'); command.upgrade(c,'head'); print('RT_OK')" 2>&1 | tail -1)"
[ "$rt" = RT_OK ] && ok "upgrade -> downgrade -1 -> upgrade round-trips" || bad "round-trip failed: $rt"

echo "MUTANT: OVN_ALEMBIC_BATCH_CONSTRAINTS=off reproduces the pre-fix failure"
newp base; add_fk_model "$P"; out="$(OVN_ALEMBIC_BATCH_CONSTRAINTS=off runpy "$P" --message "owner id")"; rc=$?
[ $rc = 12 ] && echo "$out" | grep -q 'No support for ALTER of constraints in SQLite' && ok "mutant fails exactly like the live log (rc 12, SQLite NotImplementedError)" || bad "mutant did not fail as expected rc=$rc: $out"

echo "BENIGN: plain nullable column (no constraint) keeps the plain op.add_column shape"
newp add_nullable; out="$(runpy "$P" --message "note")"; rc=$?; f="$(ls "$P"/alembic/versions/*note.py 2>/dev/null | head -1)"
[ $rc = 0 ] && [ -n "$f" ] && ! grep -q batch_alter_table "$f" && grep -q "op.add_column('items'" "$f" && ok "no-constraint migration unchanged (plain add_column)" || bad "plain shape changed rc=$rc: $out"

[ "$fail" = 0 ] && echo "ALL PASS" || { echo FAILURES; exit 1; }
