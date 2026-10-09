#!/usr/bin/env bash
# Regression tests for scripts/ovn_alembic_autogen.{sh,py}. Builds a throwaway git repo with a
# tiny SQLAlchemy+Alembic project (numbered revision ids like iptv_apps, a sync env.py, a
# tests/test_migration_drift.py marker) and drives the hook the way run_overnight.sh does:
# commit a "model change" on top of BEFORE, call the hook with BEFORE/AFTER, inspect the result.
# Needs a python with alembic+sqlalchemy: $OVN_TEST_PY, else the test-automation-agent venv;
# SKIPs (exit 0) if none exists.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; SCRIPTS="$(cd "$HERE/.." && pwd)"
PYX="${OVN_TEST_PY:-$HOME/overnight-queue/repos/test-automation-agent/backend/.venv/bin/python}"
"$PYX" -c 'import alembic, sqlalchemy' 2>/dev/null || { echo "SKIP: no python with alembic+sqlalchemy ($PYX)"; exit 0; }
fail=0; ok() { echo "  ok   - $1"; }; bad() { echo "  FAIL - $1"; fail=1; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

mkrepo() {  # $1 = repo dir name (basename matters: allowlist)
  local R; R="$(mktemp -d "$T/r.XXXXXX")/$1"; mkdir -p "$R/proj/app" "$R/proj/alembic/versions" "$R/proj/tests"; cd "$R" || exit 1
  git init -q . && git config user.email t@t && git config user.name t
  ln -s "$(dirname "$(dirname "$PYX")")" proj/.venv           # hook uses proj/.venv/bin/python
  printf '[alembic]\nscript_location = alembic\nprepend_sys_path = .\n' > proj/alembic.ini
  : > proj/app/__init__.py
  cat > proj/app/main.py <<'PY'
from app import models  # noqa: F401
PY
  cat > proj/app/models.py <<'PY'
from sqlalchemy import Column, Integer, String
from sqlalchemy.orm import declarative_base
Base = declarative_base()
class Item(Base):
    __tablename__ = "items"
    id = Column(Integer, primary_key=True)
    name = Column(String(50), nullable=False)
PY
  cat > proj/alembic/env.py <<'PY'
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
  cat > proj/alembic/script.py.mako <<'PY'
"""${message}

Revision ID: ${up_revision}
Revises: ${down_revision | comma,n}
"""
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
  cat > proj/alembic/versions/0001_baseline.py <<'PY'
"""baseline"""
from alembic import op
import sqlalchemy as sa
revision = "0001_baseline"
down_revision = None
branch_labels = None
depends_on = None
def upgrade():
    op.create_table("items", sa.Column("id", sa.Integer(), primary_key=True), sa.Column("name", sa.String(50), nullable=False))
def downgrade():
    op.drop_table("items")
PY
  echo "def test_alembic_head_matches_models(): pass" > proj/tests/test_migration_drift.py
  printf '.venv\n__pycache__/\n' > .gitignore
  git add -A && git commit -qm base && echo "$R"
}
hook() { OVN_ALEMBIC_AUTOGEN_REPOS="${REPOS:-fixture-app}" bash "$SCRIPTS/ovn_alembic_autogen.sh" "$PWD" "$1" "$(git rev-parse HEAD)" 2>&1; }
commit_models() { git add -A && git commit -qm "$1"; }
nfiles() { ls proj/alembic/versions/*.py | wc -l | tr -d ' '; }
drift_clean() { ( cd proj && DATABASE_URL="sqlite:///$T/d$$.db" "$PYX" - <<'PY'
import os, sys
from alembic import command
from alembic.config import Config
from alembic.autogenerate import compare_metadata
from alembic.migration import MigrationContext
from sqlalchemy import create_engine
cfg = Config("alembic.ini"); cfg.set_main_option("script_location", "alembic")
if os.path.exists(os.environ["DATABASE_URL"][10:]): os.remove(os.environ["DATABASE_URL"][10:])
command.upgrade(cfg, "head")
sys.path.insert(0, "."); import app.main; from app.models import Base
e = create_engine(os.environ["DATABASE_URL"])
with e.connect() as c: sys.exit(1 if compare_metadata(MigrationContext.configure(c), Base.metadata) else 0)
PY
); }

echo "T1 nullable column added -> migration generated, numbered 0002_, drift clean"
R="$(mkrepo fixture-app)"; cd "$R"; B=$(git rev-parse HEAD)
sed -i 's/^    name = .*/&\n    note = Column(String(20))/' proj/app/models.py; commit_models "feat(models): add item note"
out="$(hook "$B")"; echo "$out" | grep -q 'generated and committed' && ok "generated" || bad "not generated: $out"
ls proj/alembic/versions | grep -q '^0002_' && ok "numbered like the repo (0002_...)" || bad "naming: $(ls proj/alembic/versions)"
drift_clean && ok "drift test would pass" || bad "drift remains"
[ "$(git log --format=%s -1)" = "chore(migration): auto-generate Alembic migration for model change (deterministic, zero-LLM)" ] && ok "conventional commit" || bad "commit msg"
sha0001="$(git show "$B:proj/alembic/versions/0001_baseline.py" | md5sum)"; [ "$sha0001" = "$(md5sum < proj/alembic/versions/0001_baseline.py)" ] && ok "existing migration untouched" || bad "0001 modified"
out2="$(hook "$B")"; [ "$(nfiles)" = 2 ] && ok "idempotent: second run adds nothing" || bad "second run added a file"

echo "T2 NOT NULL column with python default -> server_default injected"
R="$(mkrepo fixture-app)"; cd "$R"; B=$(git rev-parse HEAD)
sed -i 's/^    name = .*/&\n    kind = Column(String(10), nullable=False, default="std")/' proj/app/models.py; commit_models "feat: kind"
hook "$B" >/dev/null; grep -q "server_default=sa.text(\"'std'\")" proj/alembic/versions/0002_*.py && ok "server_default present" || bad "no server_default: $(cat proj/alembic/versions/0002_*.py 2>&1 | grep add_column)"

echo "T3 NOT NULL column, no scalar default -> refuse, tree untouched"
R="$(mkrepo fixture-app)"; cd "$R"; B=$(git rev-parse HEAD)
sed -i 's/^    name = .*/&\n    req = Column(String(10), nullable=False)/' proj/app/models.py; commit_models "feat: req"; H=$(git rev-parse HEAD)
out="$(hook "$B")"; echo "$out" | grep -q 'not auto-fixable' && [ "$(git rev-parse HEAD)" = "$H" ] && [ "$(nfiles)" = 1 ] && ok "refused, HEAD unchanged, no stray file" || bad "$out"

echo "T4 no drift -> nothing"
R="$(mkrepo fixture-app)"; cd "$R"; B=$(git rev-parse HEAD); echo "# c" >> proj/app/models.py; commit_models "chore: comment"; H=$(git rev-parse HEAD)
out="$(hook "$B")"; echo "$out" | grep -q 'no drift' && [ "$(git rev-parse HEAD)" = "$H" ] && ok "no-op" || bad "$out"

echo "T5 destructive (column removed) -> refuse"
R="$(mkrepo fixture-app)"; cd "$R"; B=$(git rev-parse HEAD)
sed -i '/name = Column/d' proj/app/models.py; commit_models "refactor: drop name"; H=$(git rev-parse HEAD)
out="$(hook "$B")"; echo "$out" | grep -q 'destructive' && [ "$(git rev-parse HEAD)" = "$H" ] && ok "refused destructive" || bad "$out"

echo "T6 unfilled placeholder stub + model change -> stub removed, migration generated"
R="$(mkrepo fixture-app)"; cd "$R"
printf '"""Placeholder - the implement step fills in revision/down_revision/upgrade/downgrade."""\n' > proj/alembic/versions/0002_thing.py; git add -A; git commit -qm stub; B=$(git rev-parse HEAD)
sed -i 's/^    name = .*/&\n    note = Column(String(20))/' proj/app/models.py; commit_models "feat: note"
out="$(hook "$B")"; echo "$out" | grep -q "removed unfilled placeholder" && drift_clean && ok "stub dropped, drift clean" || bad "stub case: $out"

echo "T7 model wrote its OWN migration with a stale down_revision -> reverted + regenerated"
R="$(mkrepo fixture-app)"; cd "$R"; B=$(git rev-parse HEAD)
sed -i 's/^    name = .*/&\n    note = Column(String(20))/' proj/app/models.py
cat > proj/alembic/versions/009_note.py <<'PY'
revision = "009"
down_revision = "008"
def upgrade(): pass
def downgrade(): pass
PY
commit_models "feat: note + hand-written migration"
out="$(hook "$B")"; [ ! -f proj/alembic/versions/009_note.py ] && drift_clean && ok "bad hand-written migration replaced" || bad "$out"

echo "T8 model EDITED an existing migration -> restored from BEFORE"
R="$(mkrepo fixture-app)"; cd "$R"; B=$(git rev-parse HEAD)
sed -i 's/^    name = .*/&\n    note = Column(String(20))/' proj/app/models.py
sed -i 's/down_revision = None/down_revision = "bogus"/' proj/alembic/versions/0001_baseline.py; commit_models "feat: note (+ mangled 0001)"
hook "$B" >/dev/null; git diff --quiet "$B" -- proj/alembic/versions/0001_baseline.py && drift_clean && ok "0001 restored, drift clean" || bad "0001 not restored"

echo "T9 gates: repo not allowlisted / dirty tree / no drift-test marker / non-model change"
R="$(mkrepo other-app)"; cd "$R"; B=$(git rev-parse HEAD); sed -i 's/^    name = .*/&\n    note = Column(String(20))/' proj/app/models.py; commit_models "feat: note"; H=$(git rev-parse HEAD)
REPOS="fixture-app" hook "$B" >/dev/null; [ "$(git rev-parse HEAD)" = "$H" ] && ok "non-allowlisted repo skipped" || bad "ran on non-allowlisted repo"
R="$(mkrepo fixture-app)"; cd "$R"; B=$(git rev-parse HEAD); sed -i 's/^    name = .*/&\n    note = Column(String(20))/' proj/app/models.py; commit_models "feat: note"; H=$(git rev-parse HEAD); echo "x" >> proj/app/main.py
out="$(hook "$B")"; echo "$out" | grep -q dirty && [ "$(git rev-parse HEAD)" = "$H" ] && ok "dirty tree skipped" || bad "dirty tree not skipped"
git checkout -q -- proj/app/main.py
git rm -q proj/tests/test_migration_drift.py; git commit -qm x; H=$(git rev-parse HEAD); hook "$B" >/dev/null; [ "$(git rev-parse HEAD)" = "$H" ] && ok "no drift-test marker -> skipped" || bad "ran without marker"
R="$(mkrepo fixture-app)"; cd "$R"; B=$(git rev-parse HEAD); echo "print(1)" > proj/app/util.py; commit_models "feat: util"; H=$(git rev-parse HEAD)
hook "$B" >/dev/null; [ "$(git rev-parse HEAD)" = "$H" ] && ok "non-model change skipped (no work)" || bad "ran on non-model change"

echo "T10 red build (model file has a syntax error) -> skipped"
R="$(mkrepo fixture-app)"; cd "$R"; B=$(git rev-parse HEAD); echo "class Broken(" >> proj/app/models.py; commit_models "feat: broken"; H=$(git rev-parse HEAD)
out="$(hook "$B")"; echo "$out" | grep -q "red build" && [ "$(git rev-parse HEAD)" = "$H" ] && ok "compile failure -> skipped" || bad "ran on red build"

echo "T11 hanging model import -> hook times out, treats it as not auto-fixable, leaves tree untouched, no stray process (2026-10-02)"
R="$(mkrepo fixture-app)"; cd "$R"; B=$(git rev-parse HEAD)
sed -i 's/^    name = .*/&\n    note = Column(String(20))/' proj/app/models.py; printf 'import time\ntime.sleep(2971)\n' >> proj/app/models.py; commit_models "feat: hang"; H=$(git rev-parse HEAD)
t0=$(date +%s); out="$(OVN_ALEMBIC_AUTOGEN_TIMEOUT=3 hook "$B")"; el=$(( $(date +%s) - t0 ))
echo "$out" | grep -q 'not auto-fixable (ERROR driver timed out after 3s' && ok "timeout reported as not auto-fixable" || bad "no timeout report: $out"
[ "$el" -lt 25 ] && ok "returned in ${el}s (cap 3s + kill grace), not the 2971s sleep" || bad "took ${el}s"
[ "$(git rev-parse HEAD)" = "$H" ] && [ "$(nfiles)" = 1 ] && git diff --quiet HEAD && ok "HEAD unchanged, no stray file, tree clean" || bad "tree touched"
sleep 1; pgrep -f 'time.sleep\(2971\)' >/dev/null && bad "hung python child survived" || ok "hung child process was killed"
echo "T12 benign: normal run under the timeout wrapper still generates (default 120s cap)"
R="$(mkrepo fixture-app)"; cd "$R"; B=$(git rev-parse HEAD)
sed -i 's/^    name = .*/&\n    note = Column(String(20))/' proj/app/models.py; commit_models "feat: note"
out="$(hook "$B")"; echo "$out" | grep -q 'generated and committed' && drift_clean && ok "generated under wrapper" || bad "$out"
echo "T13 hanging check_migrations.py -> migration discarded (not committed), tree clean"
S2="$T/scr2"; mkdir -p "$S2"; cp "$SCRIPTS/ovn_alembic_autogen.sh" "$SCRIPTS/ovn_alembic_autogen.py" "$S2/"; printf 'import time\ntime.sleep(2972)\n' > "$S2/check_migrations.py"
R="$(mkrepo fixture-app)"; cd "$R"; B=$(git rev-parse HEAD)
sed -i 's/^    name = .*/&\n    note = Column(String(20))/' proj/app/models.py; commit_models "feat: note"; H=$(git rev-parse HEAD)
t0=$(date +%s); out="$(OVN_ALEMBIC_AUTOGEN_TIMEOUT=3 OVN_ALEMBIC_AUTOGEN_REPOS=fixture-app bash "$S2/ovn_alembic_autogen.sh" "$PWD" "$B" "$H" 2>&1)"; el=$(( $(date +%s) - t0 ))
echo "$out" | grep -q 'check_migrations.py failed - discarding' && [ "$(git rev-parse HEAD)" = "$H" ] && [ "$(nfiles)" = 1 ] && git diff --quiet HEAD && ok "check_migrations timeout -> discarded, HEAD unchanged" || bad "$out"
[ "$el" -lt 30 ] && ok "bounded (${el}s)" || bad "took ${el}s"
sleep 1; pgrep -f 'time.sleep\(2972\)' >/dev/null && bad "hung check_migrations survived" || ok "hung check_migrations killed"

[ "$fail" = 0 ] && echo "ALL PASS" || { echo "FAILURES"; exit 1; }
