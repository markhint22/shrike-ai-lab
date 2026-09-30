#!/usr/bin/env python3
"""ovn_alembic_autogen.py - deterministic, zero-LLM `alembic revision --autogenerate`.

Run with the TARGET REPO's venv python, cwd = the directory holding alembic.ini
(backend/, iptv-backend/, ...):

    <repo-venv>/bin/python ovn_alembic_autogen.py --message "<slug words>" [--dry-run]

Mechanism is the same one every repo's tests/test_migration_drift.py uses: point
DATABASE_URL at a throwaway SQLite file, `alembic upgrade head` (replays the real
chain), then autogenerate against Base.metadata (env.py loads the models).

Exit codes (the bash hook keys off these):
  0   a new migration file was written (path printed as `GENERATED <path>`)
  10  no drift - nothing to generate (never writes a file)
  11  refused: generation would be unsafe/needs a human (multiple heads BEFORE we
      start, destructive ops, NOT NULL add_column with no scalar default, ...)
  12  internal error (upgrade of the existing chain failed, env.py failed, ...)
Never overwrites/edits an existing migration: only ever adds ONE new file.
"""
import argparse, os, re, sys, tempfile, glob, io, contextlib

ap = argparse.ArgumentParser()
ap.add_argument("--message", required=True)
ap.add_argument("--dry-run", action="store_true", help="detect + render but write no file")
ap.add_argument("--allow-destructive", action="store_true")
ap.add_argument("--max-ops", type=int, default=25, help="refuse absurdly large autogen output (spurious-op guard)")
args = ap.parse_args()

proj = os.getcwd()
if not os.path.isfile(os.path.join(proj, "alembic.ini")):
    print("REFUSE no alembic.ini in cwd"); sys.exit(11)

tmp = tempfile.mkdtemp(prefix="ovn-autogen-")
# 2026-09-30: the throwaway SQLite dir was never removed on any exit path (28 leaked in one test run)
import atexit, shutil
atexit.register(shutil.rmtree, tmp, True)
dbfile = os.path.join(tmp, "autogen.db")
# env.py flavour decides the URL flavour: async env.py (async_engine_from_config) needs the
# aiosqlite driver spec; a sync env.py (iptv_apps: app.database derives its own async URL)
# must get a bare sqlite:/// URL - handing it +aiosqlite makes app.database build a bogus
# async URL and crash on import. Same split the two repos' drift tests already encode.
try:
    _envsrc = open(os.path.join(proj, "alembic", "env.py")).read()
except OSError:
    _envsrc = ""
_async_env = "async_engine_from_config" in _envsrc or "create_async_engine" in _envsrc
os.environ["DATABASE_URL"] = (f"sqlite+aiosqlite:///{dbfile}" if _async_env else f"sqlite:///{dbfile}")
os.environ.setdefault("ANTHROPIC_API_KEY", "")

# import alembic BEFORE putting the project dir on sys.path (a local alembic/ dir must
# never shadow the real package - same caveat the drift tests document).
from alembic import command
from alembic.config import Config
from alembic.script import ScriptDirectory
from alembic.operations import ops
from alembic.runtime import environment as _envmod
import sqlalchemy as sa
sys.path.insert(0, proj)

cfg = Config(os.path.join(proj, "alembic.ini"))
cfg.set_main_option("script_location", os.path.join(proj, "alembic"))
script = ScriptDirectory.from_config(cfg)

try:
    heads = script.get_heads()
except Exception as e:  # dangling down_revision, duplicate ids, ...
    print(f"REFUSE chain is broken before we start: {type(e).__name__}: {str(e)[:200]}"); sys.exit(11)
if len(heads) != 1:
    print(f"REFUSE chain already has {len(heads)} heads {heads}"); sys.exit(11)
head = heads[0]

# ---- next revision id, following the repo's own convention -------------------
slug = re.sub(r"[^a-z0-9]+", "_", args.message.lower()).strip("_")[:40] or "auto"
m = re.match(r"^(\d{3,5})_", head)
rev_id = None
if m:  # numbered convention (0006_referrals, 0009_epg_active_unique, ...)
    width = len(m.group(1))
    rev_id = f"{int(m.group(1)) + 1:0{width}d}_{slug}"

# ---- hook: drop empty migrations, refuse destructive, add server_default ----
STATE = {"refuse": None, "n_ops": 0}

def _walk(oplist):
    for o in oplist:
        if isinstance(o, ops.ModifyTableOps):
            yield from _walk(o.ops)
        else:
            yield o

def _server_default_for(col):
    d = col.default
    if d is None or not getattr(d, "is_scalar", False):
        return None
    v = d.arg
    if isinstance(v, bool):
        return sa.text("true" if v else "false")
    if isinstance(v, (int, float)):
        return sa.text(repr(v))
    if isinstance(v, str):
        return sa.text("'" + v.replace("'", "''") + "'")
    return None

def hook(context, revision, directives):
    if STATE.get("mode") == "check" or not directives:
        return  # command.check() drives its own directive handling; we only mutate real generates
    scr = directives[0]
    if scr.upgrade_ops.is_empty():
        directives[:] = []
        return
    STATE["n_ops"] = len(list(_walk(scr.upgrade_ops.ops)))
    if STATE["n_ops"] > args.max_ops:
        STATE["refuse"] = f"{STATE['n_ops']} ops > --max-ops {args.max_ops}: looks spurious, needs a human"
    for o in _walk(scr.upgrade_ops.ops):
        if isinstance(o, (ops.DropTableOp, ops.DropColumnOp)) and not args.allow_destructive:
            STATE["refuse"] = f"destructive op {o.__class__.__name__} (model removed something) - needs a human"
        if isinstance(o, ops.AddColumnOp):
            c = o.column
            if not c.nullable and c.server_default is None and not c.primary_key:
                sd = _server_default_for(c)
                if sd is None:
                    STATE["refuse"] = (f"add_column {o.table_name}.{c.name} is NOT NULL with no scalar default: "
                                       "would fail on a populated table - needs a human")
                else:
                    c.server_default = sa.schema.DefaultClause(sd)

_orig_configure = _envmod.EnvironmentContext.configure
def _configure(self, *a, **kw):
    kw.setdefault("process_revision_directives", hook)
    kw.setdefault("compare_type", True)
    return _orig_configure(self, *a, **kw)
_envmod.EnvironmentContext.configure = _configure

buf = io.StringIO()
import logging; logging.disable(logging.CRITICAL)  # env.py fileConfig chatter
try:
    with contextlib.redirect_stdout(buf):
        command.upgrade(cfg, "head")
except Exception as e:  # existing chain does not even replay -> not ours to fix
    print(f"ERROR upgrade head on temp DB failed: {type(e).__name__}: {str(e)[:300]}"); sys.exit(12)

before = set(glob.glob(os.path.join(proj, "alembic", "versions", "*.py")))
try:
    with contextlib.redirect_stdout(buf):
        command.revision(cfg, message=args.message, autogenerate=True, rev_id=rev_id)
except Exception as e:
    print(f"ERROR autogenerate failed: {type(e).__name__}: {str(e)[:300]}"); sys.exit(12)
new = sorted(set(glob.glob(os.path.join(proj, "alembic", "versions", "*.py"))) - before)

if not new:
    print("NODRIFT"); sys.exit(10)
if len(new) != 1:
    print(f"ERROR expected 1 new file, got {new}")
    [os.remove(p) for p in new]; sys.exit(12)
path = new[0]
if STATE["refuse"]:
    os.remove(path); print("REFUSE " + STATE["refuse"]); sys.exit(11)

# ---- conform filename to the repo's convention (numbered repos: NNNN_slug.py) ----
if rev_id:
    dst = os.path.join(os.path.dirname(path), f"{rev_id}.py")
    if not os.path.exists(dst):
        os.rename(path, dst); path = dst

# ---- re-validate: the SAME check the drift test does, on a fresh DB ----
try:
    script2 = ScriptDirectory.from_config(cfg)
    if len(script2.get_heads()) != 1:
        raise RuntimeError(f"multiple heads after generate: {script2.get_heads()}")
    with contextlib.redirect_stdout(buf):
        os.remove(dbfile)
        command.upgrade(cfg, "head")
        STATE["mode"] = "check"
        command.check(cfg)          # raises AutogenerateDiffsDetected if any drift remains
except Exception as e:
    os.remove(path); print(f"ERROR post-generate validation failed: {type(e).__name__}: {str(e)[:300]}"); sys.exit(12)

if args.dry_run:
    print(open(path).read()); os.remove(path); print("DRYRUN ok"); sys.exit(0)
print(f"GENERATED {os.path.relpath(path, proj)}")
sys.exit(0)
