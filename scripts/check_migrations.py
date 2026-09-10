#!/usr/bin/env python3
"""Static alembic migration safety checks — catch deploy-breaking migration bugs
BEFORE they reach prod (no DB required). Exit 0 = clean, 1 = problem(s) found.

Usage: check_migrations.py <path>   (scans for alembic/versions dirs under <path>)

Catches the two classes that crash-looped prod this session:
  1. MULTIPLE HEADS  — two migrations sharing a revision id / branching, so
     `alembic upgrade head` fails ("Multiple head revisions are present") and the
     app refuses to start. [billwatch: duplicate revision 004]
  2. STRING FK TO UUID — a column in a ForeignKeyConstraint typed sa.String while
     its target id column is postgresql.UUID; Postgres rejects the FK
     (DatatypeMismatchError) at upgrade time. [gitlark: api_usage/notifications
     user_id String(36) -> users.id uuid]
"""
import ast
import os
import re
import sys


def find_versions_dirs(root):
    out = []
    for dp, dns, fns in os.walk(root):
        if ".git" in dp or "node_modules" in dp or "alembic.backup" in dp:
            continue
        if os.path.basename(dp) == "versions" and "alembic" in dp and any(f.endswith(".py") for f in fns):
            out.append(dp)
    return out


def rev_and_down(text):
    r = re.search(r"^revision(?:\s*:\s*[^=]+)?\s*=\s*['\"]([^'\"]+)", text, re.M)
    d = re.search(r"^down_revision(?:\s*:\s*[^=]+)?\s*=\s*['\"]?([^'\"\n]+)", text, re.M)
    dn = d.group(1).strip() if d else None
    if dn in ("None", "none", ""):
        dn = None
    return (r.group(1) if r else None), dn


def check_single_head(vdir, problems):
    revs = {}
    for f in os.listdir(vdir):
        if not f.endswith(".py") or f.startswith("__"):
            continue
        rev, down = rev_and_down(open(os.path.join(vdir, f), encoding="utf-8").read())
        if rev:
            revs.setdefault(rev, []).append(f)
    # duplicate revision ids
    for rev, files in revs.items():
        if len(files) > 1:
            problems.append(f"{vdir}: revision '{rev}' declared in {len(files)} files: {', '.join(sorted(files))}")
    downs = {rev_and_down(open(os.path.join(vdir, f), encoding='utf-8').read())[1]
             for f in os.listdir(vdir) if f.endswith('.py') and not f.startswith('__')}
    heads = [r for r in revs if r not in downs]
    if len(heads) > 1:
        problems.append(f"{vdir}: MULTIPLE HEADS {sorted(heads)} — 'alembic upgrade head' will fail")


def _type_str(node):
    """Render a column-type ast node to a coarse tag: 'uuid' | 'string' | 'other'."""
    src = ast.unparse(node) if hasattr(ast, "unparse") else ""
    low = src.lower()
    if "uuid" in low:
        return "uuid"
    if "string" in low or "varchar" in low or "char" in low or low.startswith("sa.text"):
        return "string" if "string" in low or "char" in low else "other"
    return "other"


def check_fk_types(vdir, problems):
    # Pass 1: global map of "<table>.<col>" -> type tag (esp. id columns)
    coltypes = {}
    fks = []  # (file, table, localcol, target)
    for f in sorted(os.listdir(vdir)):
        if not f.endswith(".py") or f.startswith("__"):
            continue
        try:
            tree = ast.parse(open(os.path.join(vdir, f), encoding="utf-8").read())
        except SyntaxError:
            continue
        for call in ast.walk(tree):
            if not (isinstance(call, ast.Call) and isinstance(call.func, ast.Attribute)
                    and call.func.attr == "create_table"):
                continue
            if not call.args or not isinstance(call.args[0], ast.Constant):
                continue
            table = call.args[0].value
            for arg in call.args[1:]:
                if not isinstance(arg, ast.Call) or not isinstance(arg.func, ast.Attribute):
                    continue
                attr = arg.func.attr
                if attr == "Column" and arg.args and isinstance(arg.args[0], ast.Constant):
                    cname = arg.args[0].value
                    ctype = _type_str(arg.args[1]) if len(arg.args) > 1 else "other"
                    coltypes[f"{table}.{cname}"] = ctype
                    # inline ForeignKey('t.c')
                    for a in arg.args[1:]:
                        if isinstance(a, ast.Call) and getattr(a.func, "attr", "") == "ForeignKey" and a.args and isinstance(a.args[0], ast.Constant):
                            fks.append((f, table, cname, a.args[0].value))
                elif attr == "ForeignKeyConstraint" and len(arg.args) >= 2:
                    locs = [e.value for e in getattr(arg.args[0], "elts", []) if isinstance(e, ast.Constant)]
                    tgts = [e.value for e in getattr(arg.args[1], "elts", []) if isinstance(e, ast.Constant)]
                    for lc, tg in zip(locs, tgts):
                        fks.append((f, table, lc, tg))
    # Pass 2: flag String local col -> UUID target
    for f, table, lc, target in fks:
        ttype = coltypes.get(target)
        ltype = coltypes.get(f"{table}.{lc}")
        if ttype == "uuid" and ltype == "string":
            problems.append(
                f"{vdir}/{f}: FK {table}.{lc} is String but target {target} is UUID "
                f"— Postgres will reject the FK (use postgresql.UUID(as_uuid=True))")


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else "."
    vdirs = find_versions_dirs(root)
    if not vdirs:
        print(f"no alembic versions dirs under {root} (nothing to check)")
        return 0
    problems = []
    for vd in vdirs:
        check_single_head(vd, problems)
        check_fk_types(vd, problems)
    if problems:
        print("MIGRATION SAFETY: FAIL")
        for p in problems:
            print("  ✗", p)
        return 1
    print(f"MIGRATION SAFETY: OK ({len(vdirs)} versions dir(s) clean)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
