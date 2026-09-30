#!/usr/bin/env bash
# Direct tests for scripts/ovn_alembic_autogen.py (the zero-LLM `alembic revision --autogenerate` driver).
# test_alembic_autogen.sh drives it only through the ovn_alembic_autogen.sh hook; this file calls the python CLI itself and
# covers the branches the hook test leaves unexercised: usage/argparse, REFUSE (no alembic.ini, broken chain, multiple heads,
# destructive ops +--allow-destructive, NOT NULL w/o scalar default, --max-ops), NODRIFT (exit 10), ERROR (upgrade of the
# existing chain fails, no env.py, autogenerate raises, post-generate validation fails -> generated file is DELETED, multiple
# heads after generate), --dry-run, server_default injection for bool/int/float/str, callable default refusal, explicit
# server_default passthrough, revision-id conventions (numbered width, un-numbered random id, slug rules, 40-char cap), async
# vs sync env.py DATABASE_URL flavour, DATABASE_URL isolation, ANTHROPIC_API_KEY setdefault, existing files never touched.
# Hermetic: each case builds a tiny SQLAlchemy+Alembic project in a temp dir; TMPDIR is redirected into the temp dir.
# Needs a python with alembic+sqlalchemy: $OVN_TEST_PY, else a repo venv under ~/overnight-queue/repos (read-only use, nothing is
# ever installed); SKIPs (exit 0) if none can import both. Lines tagged KNOWN-BUG are non-fatal warnings.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PYS="$HERE/../ovn_alembic_autogen.py"; [ -f "$PYS" ] || PYS="$HERE/ovn_alembic_autogen.py"
[ -f "$PYS" ] || { echo "ovn_alembic_autogen.py not found"; exit 1; }
PYX=""
for c in "${OVN_TEST_PY:-}" "$HOME"/overnight-queue/repos/*/.venv/bin/python "$HOME"/overnight-queue/repos/*/*/.venv/bin/python "$HOME"/overnight-queue/repos/*/*/venv/bin/python python3; do
  [ -n "$c" ] || continue
  if "$c" -c 'import alembic, sqlalchemy; from alembic import command; command.check' 2>/dev/null; then PYX="$c"; break; fi
done
[ -n "$PYX" ] || { echo "SKIP: no python with alembic+sqlalchemy found"; exit 0; }
pass=0; fail=0; warn=0
ok(){ if [ "$2" = "1" ]; then pass=$((pass+1)); echo "  ok   $1"; else fail=$((fail+1)); echo "  FAIL $1"; fi; }
kb(){ if [ "$2" = "1" ]; then pass=$((pass+1)); echo "  ok   KNOWN-BUG (now fixed): $1"; else warn=$((warn+1)); echo "  WARN KNOWN-BUG: $1"; fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export TMPDIR="$T/tmpd"; mkdir -p "$TMPDIR"
export OVN_REC="$T/rec.txt"; unset DATABASE_URL ANTHROPIC_API_KEY

# mkproj <envmode> <tmplmode> <basemode> [head-id]  -> echoes project dir
#   envmode : sync | asyncmarker | badmeta (target_metadata=object(), upgrade works, autogenerate raises) | none
#   tmplmode: normal | emptyup (upgrade body always `pass`) | nohead (down_revision always None)
#   basemode: good | bad (baseline upgrade raises)
mkproj() {
  local envm="$1" tm="$2" bm="$3" hid="${4:-0001_baseline}" P; P="$(mktemp -d "$T/p.XXXXXX")"; mkdir -p "$P/app" "$P/alembic/versions"
  printf '[alembic]\nscript_location = alembic\nprepend_sys_path = .\n' > "$P/alembic.ini"
  : > "$P/app/__init__.py"
  cat > "$P/app/models.py" <<'PY'
from sqlalchemy import Column, Integer, String
from sqlalchemy.orm import declarative_base
Base = declarative_base()
class Item(Base):
    __tablename__ = "items"
    id = Column(Integer, primary_key=True)
    name = Column(String(50), nullable=False)
PY
  if [ "$envm" != none ]; then
    local meta="Base.metadata"; [ "$envm" = badmeta ] && meta="object()"
    local marker=""; [ "$envm" = asyncmarker ] && marker="# uses async_engine_from_config in the real repo"
    cat > "$P/alembic/env.py" <<PY
import os
$marker
from alembic import context
from sqlalchemy import create_engine
from app.models import Base
rec = os.environ.get("OVN_REC")
if rec:
    open(rec, "a").write(os.environ["DATABASE_URL"] + "\n" + repr(os.environ.get("ANTHROPIC_API_KEY")) + "\n")
def run():
    eng = create_engine(os.environ["DATABASE_URL"].replace("+aiosqlite", ""))
    with eng.connect() as c:
        context.configure(connection=c, target_metadata=$meta, compare_type=True)
        with context.begin_transaction():
            context.run_migrations()
run()
PY
  fi
  local up='${upgrades if upgrades else "pass"}' dn='${downgrades if downgrades else "pass"}' dr='${repr(down_revision)}'
  [ "$tm" = emptyup ] && up='pass'
  [ "$tm" = nohead ] && dr='None'
  cat > "$P/alembic/script.py.mako" <<PY
"""\${message}"""
from alembic import op
import sqlalchemy as sa
\${imports if imports else ""}
revision = \${repr(up_revision)}
down_revision = $dr
branch_labels = None
depends_on = None

def upgrade():
    $up

def downgrade():
    $dn
PY
  # mako needs literal \${...}; undo the escaping used above for the heredoc
  sed -i.bak 's/\\\$/$/g' "$P/alembic/script.py.mako"; rm -f "$P/alembic/script.py.mako.bak"
  local body='op.create_table("items", sa.Column("id", sa.Integer(), primary_key=True), sa.Column("name", sa.String(50), nullable=False))'
  [ "$bm" = bad ] && body='raise RuntimeError("boom in baseline")'
  cat > "$P/alembic/versions/${hid}.py" <<PY
"""baseline"""
from alembic import op
import sqlalchemy as sa
revision = "$hid"
down_revision = None
branch_labels = None
depends_on = None
def upgrade():
    $body
def downgrade():
    op.drop_table("items")
PY
  echo "$P"
}
addcols() { cat >> "$1/app/models.py" <<<"$2"; }   # append statements to the model file
# model columns are added inside the class: indent lines
col() { printf '    %s\n' "$@"; }
runpy() { local d="$1"; shift; ( cd "$d" && "$PYX" "$PYS" "$@" 2>&1 ); }
nver() { ls "$1"/alembic/versions/*.py 2>/dev/null | wc -l | tr -d ' '; }
md5f() { md5sum < "$1" 2>/dev/null || md5 -q "$1"; }

# ---- usage / environment ----
P="$(mkproj sync normal good)"
out="$(cd "$P" && "$PYX" "$PYS" 2>&1)"; rc=$?
ok "missing --message -> argparse error, exit 2" "$([ $rc = 2 ] && printf '%s' "$out" | grep -q 'required: --message' && echo 1 || echo 0)"
E="$(mktemp -d "$T/empty.XXXX")"; out="$(runpy "$E" --message x)"; rc=$?
ok "no alembic.ini in cwd -> 'REFUSE no alembic.ini', exit 11" "$([ $rc = 11 ] && printf '%s' "$out" | grep -q '^REFUSE no alembic.ini in cwd' && echo 1 || echo 0)"

# ---- NODRIFT ----
base_md5="$(md5f "$P/alembic/versions/0001_baseline.py")"
out="$(runpy "$P" --message "nothing changed")"; rc=$?
ok "models match chain -> 'NODRIFT', exit 10, no file written" "$([ $rc = 10 ] && [ "$out" = NODRIFT ] && [ "$(nver "$P")" = 1 ] && echo 1 || echo 0)"

# ---- GENERATED + conventions ----
python3 - "$P/app/models.py" <<'PY'
import sys; p=sys.argv[1]; s=open(p).read(); open(p,"w").write(s+"    note = Column(String(20))\n")
PY
out="$(runpy "$P" --message "Add Item note!!")"; rc=$?
ok "nullable add_column -> 'GENERATED alembic/versions/0002_add_item_note.py', exit 0" "$([ $rc = 0 ] && [ "$(printf '%s' "$out" | tail -1)" = "GENERATED alembic/versions/0002_add_item_note.py" ] && [ -f "$P/alembic/versions/0002_add_item_note.py" ] && echo 1 || echo 0)"
ok "generated file has add_column + down_revision 0001_baseline" "$(grep -q 'add_column' "$P/alembic/versions/0002_add_item_note.py" && grep -q "down_revision = '0001_baseline'\|down_revision = \"0001_baseline\"" "$P/alembic/versions/0002_add_item_note.py" && echo 1 || echo 0)"
ok "existing migration file is byte-identical afterwards" "$([ "$(md5f "$P/alembic/versions/0001_baseline.py")" = "$base_md5" ] && echo 1 || echo 0)"
out="$(runpy "$P" --message "again")"; rc=$?
ok "idempotent: after generating, the next run is NODRIFT (exit 10)" "$([ $rc = 10 ] && [ "$(nver "$P")" = 2 ] && echo 1 || echo 0)"

# dry run
P="$(mkproj sync normal good)"; python3 - "$P/app/models.py" <<'PY'
import sys; p=sys.argv[1]; open(p,"a").write("    note = Column(String(20))\n")
PY
out="$(runpy "$P" --message dry --dry-run)"; rc=$?
ok "--dry-run prints the rendered migration and 'DRYRUN ok', exit 0" "$([ $rc = 0 ] && printf '%s' "$out" | grep -q 'add_column' && printf '%s' "$out" | tail -1 | grep -qx 'DRYRUN ok' && echo 1 || echo 0)"
ok "--dry-run leaves no file behind" "$([ "$(nver "$P")" = 1 ] && echo 1 || echo 0)"

# slug / id rules
P="$(mkproj sync normal good)"; python3 - "$P/app/models.py" <<'PY'
import sys; p=sys.argv[1]; open(p,"a").write("    note = Column(String(20))\n")
PY
out="$(runpy "$P" --message '!!!')"
ok "message with no [a-z0-9] -> slug 'auto' (0002_auto.py)" "$(printf '%s' "$out" | grep -qx 'GENERATED alembic/versions/0002_auto.py' && echo 1 || echo 0)"
P="$(mkproj sync normal good)"; python3 - "$P/app/models.py" <<'PY'
import sys; p=sys.argv[1]; open(p,"a").write("    note = Column(String(20))\n")
PY
long="$(printf 'a%.0s' $(seq 1 60))"; out="$(runpy "$P" --message "$long")"
ok "slug truncated to 40 chars" "$(printf '%s' "$out" | grep -qx "GENERATED alembic/versions/0002_$(printf 'a%.0s' $(seq 1 40)).py" && echo 1 || echo 0)"
P="$(mkproj sync normal good 00009_base)"; python3 - "$P/app/models.py" <<'PY'
import sys; p=sys.argv[1]; open(p,"a").write("    note = Column(String(20))\n")
PY
out="$(runpy "$P" --message note)"
ok "5-digit numbered head keeps its width (00009 -> 00010_note.py)" "$(printf '%s' "$out" | grep -qx 'GENERATED alembic/versions/00010_note.py' && echo 1 || echo 0)"
P="$(mkproj sync normal good abc123)"; python3 - "$P/app/models.py" <<'PY'
import sys; p=sys.argv[1]; open(p,"a").write("    note = Column(String(20))\n")
PY
out="$(runpy "$P" --message "hex ids")"; rc=$?
ok "un-numbered head -> alembic's own random id, file named <rev>_hex_ids.py (no rename)" "$([ $rc = 0 ] && printf '%s' "$out" | grep -Eq '^GENERATED alembic/versions/[0-9a-f]{12}_hex_ids\.py$' && echo 1 || echo 0)"

# ---- REFUSE: chain problems ----
P="$(mkproj sync normal good)"; cat > "$P/alembic/versions/0002_orphan.py" <<'PY'
revision = "0002_orphan"
down_revision = "does_not_exist"
def upgrade(): pass
def downgrade(): pass
PY
out="$(runpy "$P" --message x)"; rc=$?
ok "dangling down_revision -> 'REFUSE chain is broken before we start', exit 11" "$([ $rc = 11 ] && printf '%s' "$out" | grep -q '^REFUSE chain is broken before we start' && echo 1 || echo 0)"
P="$(mkproj sync normal good)"; cat > "$P/alembic/versions/0002_fork.py" <<'PY'
revision = "0002_fork"
down_revision = None
def upgrade(): pass
def downgrade(): pass
PY
out="$(runpy "$P" --message x)"; rc=$?
ok "two heads before we start -> 'REFUSE chain already has 2 heads', exit 11, nothing written" "$([ $rc = 11 ] && printf '%s' "$out" | grep -q '^REFUSE chain already has 2 heads' && [ "$(nver "$P")" = 2 ] && echo 1 || echo 0)"

# ---- REFUSE: destructive ----
P="$(mkproj sync normal good)"; python3 - "$P/app/models.py" <<'PY'
import sys; p=sys.argv[1]; s=open(p).read().replace('    name = Column(String(50), nullable=False)\n',''); open(p,"w").write(s)
PY
out="$(runpy "$P" --message drop)"; rc=$?
ok "removed column -> 'REFUSE destructive op DropColumnOp', exit 11, generated file deleted" "$([ $rc = 11 ] && printf '%s' "$out" | grep -q '^REFUSE destructive op DropColumnOp' && [ "$(nver "$P")" = 1 ] && echo 1 || echo 0)"
out="$(runpy "$P" --message drop --allow-destructive)"; rc=$?
ok "--allow-destructive lets the drop through (GENERATED, exit 0)" "$([ $rc = 0 ] && printf '%s' "$out" | grep -q '^GENERATED' && grep -q drop_column "$P"/alembic/versions/0002_drop.py && echo 1 || echo 0)"
P="$(mkproj sync normal good)"; printf 'class Gone(Base):\n    __tablename__ = "gone"\n    id = Column(Integer, primary_key=True)\n' >> "$P/app/models.py"
# table present in models AND chain -> then remove it from models: first create it in the chain
out="$(runpy "$P" --message gone)"; python3 - "$P/app/models.py" <<'PY'
import sys; p=sys.argv[1]; s=open(p).read(); i=s.index("class Gone"); open(p,"w").write(s[:i])
PY
out="$(runpy "$P" --message drop_gone)"; rc=$?
ok "removed table -> 'REFUSE destructive op DropTableOp', exit 11" "$([ $rc = 11 ] && printf '%s' "$out" | grep -q 'DropTableOp' && echo 1 || echo 0)"

# ---- REFUSE: NOT NULL handling / server_default injection ----
P="$(mkproj sync normal good)"; python3 - "$P/app/models.py" <<'PY'
import sys; p=sys.argv[1]
open(p,"a").write('''    flag_t = Column(Boolean, nullable=False, default=True)
    flag_f = Column(Boolean, nullable=False, default=False)
    n_int = Column(Integer, nullable=False, default=3)
    n_flt = Column(Float, nullable=False, default=1.5)
    n_str = Column(String(20), nullable=False, default="it's")
''')
s=open(p).read().replace("import Column, Integer, String","import Column, Integer, String, Boolean, Float"); open(p,"w").write(s)
PY
out="$(runpy "$P" --message defaults)"; rc=$?
f="$P/alembic/versions/0002_defaults.py"
ok "NOT NULL columns with scalar python defaults -> GENERATED (exit 0)" "$([ $rc = 0 ] && [ -f "$f" ] && echo 1 || echo "0: $out")"
ok "bool True/False -> server_default 'true' / 'false'" "$(grep -Eq "sa.text\('\(?true\)?'\)" "$f" && grep -Eq "sa.text\('\(?false\)?'\)" "$f" && echo 1 || echo 0)"
ok "int and float defaults -> server_default '3' and '1.5'" "$(grep -Eq "sa.text\('\(?3\)?'\)" "$f" && grep -Eq "sa.text\('\(?1\.5\)?'\)" "$f" && echo 1 || echo 0)"
ok "string default is quoted and its apostrophe doubled" "$(grep -q "it''s" "$f" && echo 1 || echo 0)"
P="$(mkproj sync normal good)"; python3 - "$P/app/models.py" <<'PY'
import sys; p=sys.argv[1]
open(p,"a").write('    req = Column(String(10), nullable=False)\n')
PY
out="$(runpy "$P" --message req)"; rc=$?
ok "NOT NULL, no default -> 'REFUSE add_column items.req is NOT NULL with no scalar default', exit 11, no file" "$([ $rc = 11 ] && printf '%s' "$out" | grep -q '^REFUSE add_column items.req is NOT NULL with no scalar default' && [ "$(nver "$P")" = 1 ] && echo 1 || echo 0)"
P="$(mkproj sync normal good)"; python3 - "$P/app/models.py" <<'PY'
import sys; p=sys.argv[1]
open(p,"a").write('    cb = Column(Integer, nullable=False, default=lambda: 1)\n')
PY
out="$(runpy "$P" --message cb)"; rc=$?
ok "callable python default is non-scalar -> REFUSE, exit 11" "$([ $rc = 11 ] && printf '%s' "$out" | grep -q 'items.cb is NOT NULL' && echo 1 || echo 0)"
P="$(mkproj sync normal good)"; python3 - "$P/app/models.py" <<'PY'
import sys; p=sys.argv[1]
s=open(p).read().replace("import Column, Integer, String","import Column, Integer, String, text"); open(p,"w").write(s)
open(p,"a").write('    sd = Column(String(10), nullable=False, server_default=text("\'x\'"))\n')
PY
out="$(runpy "$P" --message sd)"; rc=$?
ok "NOT NULL with an explicit server_default passes through untouched (GENERATED)" "$([ $rc = 0 ] && printf '%s' "$out" | grep -q '^GENERATED' && echo 1 || echo 0)"

# ---- REFUSE: --max-ops ----
P="$(mkproj sync normal good)"; python3 - "$P/app/models.py" <<'PY'
import sys; p=sys.argv[1]
open(p,"a").write('    a = Column(String(5))\n    b = Column(String(5))\n    c = Column(String(5))\n')
PY
out="$(runpy "$P" --message many --max-ops 2)"; rc=$?
ok "3 ops with --max-ops 2 -> 'REFUSE 3 ops > --max-ops 2', exit 11, no file" "$([ $rc = 11 ] && printf '%s' "$out" | grep -q '^REFUSE 3 ops > --max-ops 2: looks spurious' && [ "$(nver "$P")" = 1 ] && echo 1 || echo 0)"
out="$(runpy "$P" --message many --max-ops 3)"; rc=$?
ok "exactly at the limit (3 ops, --max-ops 3) is allowed" "$([ $rc = 0 ] && printf '%s' "$out" | grep -q '^GENERATED' && echo 1 || echo 0)"

# ---- ERROR paths ----
P="$(mkproj sync normal bad)"
out="$(runpy "$P" --message x)"; rc=$?
ok "existing chain fails to replay -> 'ERROR upgrade head on temp DB failed: ...boom', exit 12" "$([ $rc = 12 ] && printf '%s' "$out" | grep -q '^ERROR upgrade head on temp DB failed: .*boom in baseline' && [ "$(nver "$P")" = 1 ] && echo 1 || echo 0)"
P="$(mkproj none normal good)"
out="$(runpy "$P" --message x)"; rc=$?
ok "no alembic/env.py -> ERROR (upgrade cannot run), exit 12" "$([ $rc = 12 ] && printf '%s' "$out" | grep -q '^ERROR upgrade head' && echo 1 || echo 0)"
P="$(mkproj badmeta normal good)"
out="$(runpy "$P" --message x)"; rc=$?
ok "autogenerate raising -> 'ERROR autogenerate failed: ...', exit 12, no file" "$([ $rc = 12 ] && printf '%s' "$out" | grep -q '^ERROR autogenerate failed:' && [ "$(nver "$P")" = 1 ] && echo 1 || echo 0)"
P="$(mkproj sync emptyup good)"; python3 - "$P/app/models.py" <<'PY'
import sys; p=sys.argv[1]; open(p,"a").write("    note = Column(String(20))\n")
PY
out="$(runpy "$P" --message useless)"; rc=$?
ok "post-generate validation failure (migration does not fix the drift) -> 'ERROR post-generate validation failed', exit 12" "$([ $rc = 12 ] && printf '%s' "$out" | grep -q '^ERROR post-generate validation failed:' && echo 1 || echo 0)"
ok "...and the generated file is DELETED (tree left exactly as found)" "$([ "$(nver "$P")" = 1 ] && [ ! -e "$P/alembic/versions/0002_useless.py" ] && echo 1 || echo 0)"
P="$(mkproj sync nohead good)"; python3 - "$P/app/models.py" <<'PY'
import sys; p=sys.argv[1]; open(p,"a").write("    note = Column(String(20))\n")
PY
out="$(runpy "$P" --message fork)"; rc=$?
ok "generate that would create a second head -> 'ERROR post-generate validation failed: RuntimeError: multiple heads after generate', exit 12" "$([ $rc = 12 ] && printf '%s' "$out" | grep -q 'RuntimeError: multiple heads after generate' && echo 1 || echo 0)"
ok "...and that file is deleted too (chain back to 1 version)" "$([ "$(nver "$P")" = 1 ] && echo 1 || echo 0)"

# ---- environment handling ----
P="$(mkproj sync normal good)"; rm -f "$OVN_REC"
( cd "$P" && DATABASE_URL="sqlite:///$T/real.db" "$PYX" "$PYS" --message x >/dev/null 2>&1 )
ok "sync env.py gets a bare sqlite:/// URL" "$(sed -n 1p "$OVN_REC" | grep -q '^sqlite:///' && echo 1 || echo 0)"
ok "DATABASE_URL is forced to a throwaway temp DB (caller's URL ignored, caller's DB never created)" "$(! sed -n 1p "$OVN_REC" | grep -q real.db && [ ! -e "$T/real.db" ] && sed -n 1p "$OVN_REC" | grep -q "$TMPDIR/ovn-autogen-" && echo 1 || echo 0)"
ok "ANTHROPIC_API_KEY defaults to '' when unset" "$([ "$(sed -n 2p "$OVN_REC")" = "''" ] && echo 1 || echo 0)"
P="$(mkproj asyncmarker normal good)"; rm -f "$OVN_REC"
( cd "$P" && ANTHROPIC_API_KEY=sk-keep "$PYX" "$PYS" --message x >/dev/null 2>&1 )
ok "env.py mentioning async_engine_from_config -> sqlite+aiosqlite:/// URL" "$(sed -n 1p "$OVN_REC" | grep -q '^sqlite+aiosqlite:///' && echo 1 || echo 0)"
ok "an existing ANTHROPIC_API_KEY is preserved (setdefault, not overwrite)" "$([ "$(sed -n 2p "$OVN_REC")" = "'sk-keep'" ] && echo 1 || echo 0)"
ok "async-flavour project still generates/validates fine (NODRIFT on a clean project)" "$( ( cd "$P" && "$PYX" "$PYS" --message x >/dev/null 2>&1; [ $? = 10 ] ) && echo 1 || echo 0)"

# ---- leak check ----
left="$(ls "$TMPDIR" | grep -c '^ovn-autogen-')"
kb "each run leaves its mkdtemp dir (ovn-autogen-XXXX with autogen.db) behind in \$TMPDIR; it is never removed (ovn_alembic_autogen.py:tempfile.mkdtemp, no cleanup on any exit path) - ${left} leaked over this test run" "$([ "$left" = 0 ] && echo 1 || echo 0)"

echo "  $pass passed, $fail failed, $warn known-bug warning(s)"; [ "$fail" = 0 ]
