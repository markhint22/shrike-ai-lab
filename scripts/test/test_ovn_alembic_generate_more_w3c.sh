#!/usr/bin/env bash
# Wave-3c coverage tests, executing the REAL scripts in place:
#   ovn_alembic_autogen.py : non-scalar-typed default refusal, "expected 1 new file" guard
#   ovn_generate_items.py  : every pattern, dedupe, limit/priority order, Needs-human insertion, unreadable files
# Hermetic: temp projects/repos only; TMPDIR redirected; needs a python with alembic+sqlalchemy (alembic half SKIPs otherwise).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
D="$HERE/.."; [ -f "$D/ovn_generate_items.py" ] || D="$HERE"
REAL_HOME="$HOME"
export PYTHONDONTWRITEBYTECODE=1
pass=0; fail=0
ok(){ if [ "$2" = "1" ]; then pass=$((pass+1)); echo "  ok   $1"; else fail=$((fail+1)); echo "  FAIL $1"; fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export TMPDIR="$T/tmpd"; mkdir -p "$TMPDIR"

# ----------------------------------------------------------------- alembic half
PYS="$D/ovn_alembic_autogen.py"
PYX=""
for c in "${OVN_TEST_PY:-}" "$REAL_HOME"/overnight-queue/repos/*/.venv/bin/python "$REAL_HOME"/overnight-queue/repos/*/*/.venv/bin/python python3; do
  [ -n "$c" ] || continue
  if "$c" -c 'import alembic, sqlalchemy; from alembic import command; command.check' 2>/dev/null; then PYX="$c"; break; fi
done
mkproj() {  # $1 = extra env.py snippet run inside run()
  local P; P="$(mktemp -d "$T/p.XXXXXX")"; mkdir -p "$P/app" "$P/alembic/versions"
  printf '[alembic]\nscript_location = alembic\nprepend_sys_path = .\n' > "$P/alembic.ini"
  : > "$P/app/__init__.py"
  cat > "$P/app/models.py" <<'PY'
import datetime
from sqlalchemy import Column, Integer, String, Date, LargeBinary
from sqlalchemy.orm import declarative_base
Base = declarative_base()
class Item(Base):
    __tablename__ = "items"
    id = Column(Integer, primary_key=True)
    name = Column(String(50), nullable=False)
PY
  cat > "$P/alembic/env.py" <<PY
import os
from alembic import context
from sqlalchemy import create_engine
from app.models import Base
def run():
    eng = create_engine(os.environ["DATABASE_URL"].replace("+aiosqlite", ""))
    with eng.connect() as c:
        context.configure(connection=c, target_metadata=Base.metadata, compare_type=True)
        with context.begin_transaction():
            context.run_migrations()
$1
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
    op.create_table("items", sa.Column("id", sa.Integer(), primary_key=True), sa.Column("name", sa.String(50), nullable=False))
def downgrade():
    op.drop_table("items")
PY
  echo "$P"
}
runpy(){ local d="$1"; shift; ( cd "$d" && "$PYX" "$PYS" "$@" 2>&1 ); }
nver(){ ls "$1"/alembic/versions/*.py | wc -l | tr -d ' '; }
if [ -z "$PYX" ]; then
  echo "  SKIP alembic half: no python with alembic+sqlalchemy"
else
  # non-bool/int/float/str scalar default (a datetime.date) on a NOT NULL add_column -> no server_default derivable -> refuse
  P="$(mkproj "")"
  printf '    born = Column(Date, nullable=False, default=datetime.date(2020, 1, 1))\n' >> "$P/app/models.py"
  out="$(runpy "$P" --message "add born")"; rc=$?
  ok "date-typed scalar default on NOT NULL column -> REFUSE (rc 11)" "$([ $rc = 11 ] && printf '%s' "$out" | grep -q '^REFUSE add_column items.born is NOT NULL with no scalar default' && echo 1 || echo 0)"
  ok "refused run leaves no new file" "$([ "$(nver "$P")" = 1 ] && echo 1 || echo 0)"
  P="$(mkproj "")"
  printf '    blob = Column(LargeBinary, nullable=False, default=b"\\x00")\n' >> "$P/app/models.py"
  out="$(runpy "$P" --message "add blob")"; rc=$?
  ok "bytes default -> also not derivable -> REFUSE (rc 11)" "$([ $rc = 11 ] && printf '%s' "$out" | grep -q 'items.blob is NOT NULL' && echo 1 || echo 0)"

  # env.py drops a second migration file during autogenerate -> "expected 1 new file" guard deletes everything new, rc 12
  # the mako template (rendered once, only by the revision step) drops a second .py beside the generated one
  P="$(mkproj "")"
  printf '<%% open("alembic/versions/zz_stray.py", "w").write("x = 1\\n") %%>\n' | cat - "$P/alembic/script.py.mako" > "$P/mako.tmp" && mv "$P/mako.tmp" "$P/alembic/script.py.mako"
  printf '    note = Column(String(20))\n' >> "$P/app/models.py"
  out="$(runpy "$P" --message "add note")"; rc=$?
  ok "two new files from one revision -> 'ERROR expected 1 new file', rc 12" "$([ $rc = 12 ] && printf '%s' "$out" | grep -q '^ERROR expected 1 new file, got ' && echo 1 || echo 0)"
  ok "all new files removed again (only baseline left)" "$([ "$(nver "$P")" = 1 ] && [ -f "$P/alembic/versions/0001_baseline.py" ] && echo 1 || echo 0)"
fi

# --------------------------------------------------------------- generate_items
GI="$D/ovn_generate_items.py"
gi(){ python3 "$GI" "$@"; }
out="$(gi 2>&1)"; rc=$?
ok "no args -> usage, rc 2" "$([ $rc = 2 ] && printf '%s' "$out" | grep -q '^usage: ovn_generate_items.py' && echo 1 || echo 0)"
R="$T/repo"; mkdir -p "$R/pkg" "$R/web" "$R/tests" "$R/node_modules/x" "$R/.git" "$R/ios"
printf 'def f():\n    try:\n        pass\n    except:  # swallow\n        pass\n' > "$R/pkg/bare.py"
printf 'class A:\n    def __repr__(self):\n        return "a"\n' > "$R/pkg/rep.py"
printf 'class B:\n    def __init__(self, x):\n        self.x = x\n    def __repr__(self):\n        return "b"\n' > "$R/pkg/init_and_repr.py"
printf 'class C:\n    def __init__(self, x) -> None:\n        pass\n    def __init__(self):\n        pass\n' > "$R/pkg/init_only.py"
printf '<a href="x" target="_blank">l</a>\n<a target="_blank" href="y">m</a>\n' > "$R/web/Link.vue"
printf '<div>\n<a\n target="_blank"\n>\nx</a>\n<a href="x" target="_blank" rel="noopener">fine</a>\n' > "$R/web/Page.html"
printf 'try:\n    x\nexcept:\n    pass\n' > "$R/tests/test_skipped.py"
printf 'try:\n    x\nexcept:\n    pass\n' > "$R/node_modules/x/dep.py"
printf 'try:\n    x\nexcept:\n    pass\n' > "$R/ios/skipped.py"
printf 'try:\n    x\nexcept:\n    pass\n' > "$R/.git/hook.py"
ln -s "$T/does-not-exist" "$R/pkg/dangling.py"                 # unreadable -> read() returns None
ln -s "$T/does-not-exist" "$R/web/dangling.vue"
out="$(gi "$R")"
ok "GENERATED=6 (bare, vue link, html link, 2x repr, init)" "$([ "$out" = "GENERATED=6" ] && echo 1 || echo 0)"
PM="$R/OVERNIGHT_PROGRESS.md"
ok "new progress file seeded with header + Next Steps" "$(head -3 "$PM" | grep -q '^# Overnight Progress' && grep -q '^## Next Steps' "$PM" && echo 1 || echo 0)"
ok "auto-generated section header present" "$(grep -q '^### Auto-generated (deterministic scanner)' "$PM" && echo 1 || echo 0)"
ok "bare except item (HIGH, T1) with line number" "$(grep -q '^- \[ \] \[T1\] \[HIGH\] `pkg/bare.py` (line 4): change the bare' "$PM" && echo 1 || echo 0)"
ok "target=_blank no rel flagged in .vue (line 1)" "$(grep -q '`web/Link.vue` (line 1): the `target="_blank"` link has no `rel`' "$PM" && echo 1 || echo 0)"
ok "multi-line tag missing rel flagged in .html (line 4)" "$(grep -q '`web/Page.html` (line 3)' "$PM" && echo 1 || echo 0)"
ok "__repr__ item (LOW)" "$(grep -q '\[LOW\] `pkg/rep.py` (line 2): add a return type hint to `__repr__`' "$PM" && echo 1 || echo 0)"
ok "first hit per file: init_and_repr gets the repr item only via pattern 3" "$(grep -c 'pkg/init_and_repr.py' "$PM" | grep -qx 1 && echo 1 || echo 0)"
ok "pattern 4 item names constructor signature" "$(grep -q '`pkg/init_only.py` (line 4): add a return type hint to the constructor — change `def __init__(self):` to `def __init__(self) -> None:`' "$PM" && echo 1 || echo 0)"
ok "tests/, node_modules, ios, .git never scanned" "$(! grep -qE 'test_skipped|dep.py|skipped.py|hook.py' "$PM" && echo 1 || echo 0)"
hi="$(grep -n 'HIGH' "$PM" | tail -1 | cut -d: -f1)"; lo="$(grep -n 'LOW' "$PM" | head -1 | cut -d: -f1)"
ok "HIGH items sorted before LOW items" "$([ "$hi" -lt "$lo" ] && echo 1 || echo 0)"
out="$(gi "$R")"
ok "rerun: every file already has an active item -> GENERATED=0" "$([ "$out" = "GENERATED=0" ] && echo 1 || echo 0)"
# checked-off items free the file for a new item
sed -i.bak 's/^- \[ \]/- [x]/' "$PM"; rm -f "$PM.bak"
out="$(gi "$R" 2)"
ok "after checking items off, limit=2 caps the new batch" "$([ "$out" = "GENERATED=2" ] && echo 1 || echo 0)"
# insertion before a '## Needs human' section
R2="$T/repo2"; mkdir -p "$R2"; printf 'try:\n    x\nexcept:\n    pass\n' > "$R2/m.py"
printf '# Prog\n\n## Next Steps\n- [ ] something\n\n## Needs human\n- [ ] ask\n' > "$R2/OVERNIGHT_PROGRESS.md"
out="$(gi "$R2")"
a="$(grep -n 'Auto-generated' "$R2/OVERNIGHT_PROGRESS.md" | cut -d: -f1)"; h="$(grep -n '^## Needs human' "$R2/OVERNIGHT_PROGRESS.md" | cut -d: -f1)"
ok "block inserted above '## Needs human'" "$([ "$out" = "GENERATED=1" ] && [ -n "$a" ] && [ "$a" -lt "$h" ] && grep -qx -- '- \[ \] ask' "$R2/OVERNIGHT_PROGRESS.md" && echo 1 || echo 0)"
# clean repo: nothing to add, file not created
R3="$T/repo3"; mkdir -p "$R3"; printf 'x = 1\n' > "$R3/ok.py"
out="$(gi "$R3")"
ok "clean repo -> GENERATED=0 and no progress file written" "$([ "$out" = "GENERATED=0" ] && [ ! -e "$R3/OVERNIGHT_PROGRESS.md" ] && echo 1 || echo 0)"
# the pre-existing python regression suite, run through this wrapper so the coverage runner executes it too
if [ -f "$HERE/test_generate_items.py" ]; then
  out="$(OVN_ROOT="$(cd "$D/.." && pwd)" python3 "$HERE/test_generate_items.py" 2>&1)"; rc=$?
  ok "test_generate_items.py regression suite passes ($(printf '%s' "$out" | tail -1))" "$([ $rc = 0 ] && echo 1 || echo 0)"
fi

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
