#!/usr/bin/env python3
"""_migr_helper.py - executed with a TARGET REPO's venv python, cwd = the directory holding alembic.ini.

It is the only code that imports a repo's backend (models / env.py / app.main), so it is the only code that needs that repo's
dependencies. gate_migrations.py itself needs nothing but the stdlib. Subcommands (all print ONE JSON object as the last line):

  heads                    -> {"heads": [rev, ...]}            (no database needed)
  upgrade <target>         -> alembic upgrade <target>         (DATABASE_URL from env)
  downgrade <target>       -> alembic downgrade <target>
  current                  -> {"current": [...]}
  diffs                    -> {"diffs": [{op, table, name, detail, key}, ...]}  alembic-check equivalent, but forces
                              compare_type=True AND compare_server_default=True and returns STRUCTURED diffs
  openapi <outfile>        -> writes app.openapi() of the module named by QA_OPENAPI_MODULE (default app.main:app)

Never prints environment values. Exit 0 = ok, 2 = the operation failed (message on stderr, last line JSON {"error": ...}).
"""
import json
import os
import sys

# Import alembic's own modules BEFORE putting the repo dir on sys.path: billwatch has a package literally named `alembic/`
# (its migrations dir) that would otherwise shadow the real library.
try:
    import alembic.autogenerate  # noqa: F401
    import alembic.command  # noqa: F401
    import alembic.config  # noqa: F401
    import alembic.runtime.environment  # noqa: F401
    import alembic.runtime.migration  # noqa: F401
    import alembic.script  # noqa: F401
except ImportError:  # the openapi subcommand does not need alembic
    pass
sys.path.insert(0, os.getcwd())


def _out(obj, rc=0):
    sys.stdout.write("\n" + json.dumps(obj, sort_keys=True, default=str) + "\n")
    sys.stdout.flush()
    return rc


def _config():
    from alembic.config import Config
    return Config(os.path.join(os.getcwd(), "alembic.ini"))


def cmd_heads():
    from alembic.script import ScriptDirectory
    sd = ScriptDirectory.from_config(_config())
    return _out({"heads": sorted(sd.get_heads())})


def cmd_stage(name, target):
    from alembic import command
    cfg = _config()
    getattr(command, name)(cfg, target)
    return _out({"ok": True, "op": name, "target": target})


def cmd_current():
    from alembic.runtime.migration import MigrationContext  # noqa: F401
    from alembic.script import ScriptDirectory  # noqa: F401
    from alembic import command
    cfg = _config()
    command.current(cfg)
    return _out({"ok": True})


def _flatten(d):
    if isinstance(d, list):
        for x in d:
            yield from _flatten(x)
    else:
        yield d


def _sql(x):
    """Stable text for a server default / type (no memory addresses)."""
    if x is None:
        return "None"
    a = getattr(x, "arg", x)
    t = getattr(a, "text", None)
    import re
    return re.sub(r"0x[0-9a-fA-F]+", "0x", str(t if t is not None else a))


def _name(o):
    return getattr(o, "name", None) or getattr(o, "fullname", None) or str(o)[:80]


def _summarize(d):
    """One structured record per alembic diff tuple. Defensive: alembic's tuple shapes differ per op."""
    op = d[0]
    table = name = detail = ""
    try:
        if op in ("add_table", "remove_table"):
            table = name = _name(d[1])
        elif op in ("add_column", "remove_column"):
            table, name = d[2], _name(d[3])
            if op == "add_column":
                c = d[3]
                detail = "type=%s nullable=%s" % (c.type, c.nullable)
        elif op in ("modify_type", "modify_nullable", "modify_default", "modify_comment"):
            table, name = d[2], d[3]
            kw, old, new = d[4], d[5], d[6]
            if op == "modify_default":
                detail = "server_default %s -> %s" % (_sql(old)[:60], _sql(new)[:60])
            else:
                detail = "%s -> %s" % (_sql(old)[:60], _sql(new)[:60])
        elif op in ("add_index", "remove_index", "add_constraint", "remove_constraint", "add_fk", "remove_fk"):
            o = d[1]
            name = getattr(o, "name", None) or ",".join(getattr(o, "column_keys", None) or []) or type(o).__name__
            t = getattr(o, "table", None)
            table = getattr(t, "name", "") if t is not None else ""
            cols = getattr(o, "columns", None)
            try:
                detail = "cols=%s" % ",".join(c.name for c in cols)
            except Exception:  # noqa: BLE001
                detail = type(o).__name__
        else:
            detail = str(d[1:])[:120]
    except Exception:  # noqa: BLE001
        detail = str(d)[:160]
    import re
    clean = lambda x: re.sub(r"0x[0-9a-fA-F]+", "0x", str(x))  # noqa: E731 - no memory addresses in stable keys
    rec = {"op": op, "table": clean(table), "name": clean(name), "detail": clean(detail)}
    rec["key"] = "|".join([rec["op"], rec["table"], rec["name"], rec["detail"]])
    return rec


def cmd_diffs():
    from alembic import autogenerate as autogen
    from alembic.runtime import environment as envmod
    from alembic.runtime.environment import EnvironmentContext
    from alembic.script import ScriptDirectory

    orig = envmod.EnvironmentContext.configure

    def configure(self, *a, **kw):
        kw["compare_type"] = True
        kw["compare_server_default"] = True
        return orig(self, *a, **kw)

    envmod.EnvironmentContext.configure = configure
    cfg = _config()
    sd = ScriptDirectory.from_config(cfg)
    args = dict(message=None, autogenerate=True, sql=False, head="head", splice=False, branch_label=None,
                version_path=None, rev_id=None, depends_on=None)
    rc = autogen.RevisionContext(cfg, sd, args)

    def retrieve(rev, context):
        rc.run_autogenerate(rev, context)
        return []

    with EnvironmentContext(cfg, sd, fn=retrieve, as_sql=False, template_args=rc.template_args, revision_context=rc):
        sd.run_env()
    diffs = []
    for ops in rc.generated_revisions[-1].upgrade_ops_list:
        diffs.extend(ops.as_diffs())
    return _out({"diffs": [_summarize(d) for d in _flatten(diffs)]})


def cmd_openapi(outfile):
    spec = os.environ.get("QA_OPENAPI_MODULE", "app.main:app")
    mod, _, attr = spec.partition(":")
    import importlib
    m = importlib.import_module(mod)
    app = getattr(m, attr or "app")
    schema = app.openapi()
    with open(outfile, "w") as f:
        json.dump(schema, f, sort_keys=True)
    return _out({"ok": True, "paths": len(schema.get("paths", {}))})


def main(argv):
    if not argv:
        return _out({"error": "no subcommand"}, 2)
    c, rest = argv[0], argv[1:]
    try:
        if c == "heads":
            return cmd_heads()
        if c in ("upgrade", "downgrade"):
            return cmd_stage(c, rest[0])
        if c == "current":
            return cmd_current()
        if c == "diffs":
            return cmd_diffs()
        if c == "openapi":
            return cmd_openapi(rest[0])
        return _out({"error": "unknown subcommand %s" % c}, 2)
    except BaseException as ex:  # noqa: BLE001 - include SystemExit from alembic.util.err
        import traceback
        traceback.print_exc(file=sys.stderr)
        return _out({"error": "%s: %s" % (type(ex).__name__, str(ex)[:300])}, 2)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
