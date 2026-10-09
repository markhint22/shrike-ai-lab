#!/usr/bin/env python3
"""prodshape.py - build a prod-SHAPED synthetic dataset from STATISTICS ONLY (never row contents, never PII).

Why: the billwatch 2026-09-14 prod 500 was model/DB drift against LIVE data. An empty-database `alembic upgrade head` cannot
exercise a migration that adds NOT NULL / UNIQUE / a foreign key / a narrower type against the nulls, duplicates and long
strings that production actually holds. This module loads a synthetic dataset with the same row counts, null rates, distinct
counts (=> duplicates) and max text lengths into the throwaway Postgres, BEFORE the head migrations run on top of it.

CLI
  collect --repo X [--out PATH]    read STATISTICS from a database over a READ-ONLY connection. The connection string comes
                                   ONLY from the env var QA_STATS_DATABASE_URL and is never printed. Only counts, null counts,
                                   distinct counts and max text LENGTHS are selected - never a value. Writes
                                   state/qa_prodshape/<repo>.stats.json (or --out).
                                   Operators run this against a replica/snapshot; the QA build never pointed it at prod/staging.
  describe --stats FILE            print a human summary of a stats file (no database needed).

Library (used by gate_migrations.py): load_stats, synth_stress_stats, schema_introspect, build_load_sql, load_into.

Stats file (version 1):
  {"version":1, "repo":"billwatch", "kind":"collected|handwritten|synthetic_stress", "collected_at":"...",
   "tables": {"<table>": {"rows": N, "columns": {"<col>": {"null_frac":0.0-1.0, "distinct":int|null, "max_len":int|null,
                                                          "dup_count":int (informational)}}}}}
Columns absent from a stats entry get safe defaults (never null, all distinct). Tables/columns that do not exist at the base
schema are ignored (and listed in the load report) - the head migration may create them.
"""
import json
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.parse

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import qa_common as qc  # noqa: E402

SEP = "\x1f"
MAX_ROWS_DEFAULT = int(os.environ.get("QA_PRODSHAPE_MAX_ROWS", "50000"))
MAX_TEXT = 100000


# --------------------------------------------------------------------------------------------- stats files

def stats_path(repo):
    return os.path.join(qc.state_dir(), "qa_prodshape", repo + ".stats.json")


def load_stats(path):
    with open(path) as f:
        s = json.load(f)
    if not isinstance(s, dict) or not isinstance(s.get("tables"), dict):
        raise ValueError("stats file has no 'tables' object")
    for t, ent in s["tables"].items():
        if not isinstance(ent.get("rows"), int) or ent["rows"] < 0:
            raise ValueError("table %s: 'rows' must be a non-negative integer" % t)
        for c, cs in (ent.get("columns") or {}).items():
            nf = cs.get("null_frac", 0)
            if not isinstance(nf, (int, float)) or not 0 <= nf <= 1:
                raise ValueError("table %s column %s: null_frac must be within 0..1" % (t, c))
    return s


def describe(stats):
    lines = ["stats kind=%s repo=%s tables=%d" % (stats.get("kind"), stats.get("repo"), len(stats["tables"]))]
    for t, ent in sorted(stats["tables"].items()):
        nulls = sum(1 for c in (ent.get("columns") or {}).values() if c.get("null_frac", 0) > 0)
        dups = sum(1 for c in (ent.get("columns") or {}).values() if c.get("distinct") is not None and c["distinct"] < ent["rows"])
        lines.append("  %-40s rows=%-9d cols_with_nulls=%d cols_with_dups=%d" % (t, ent["rows"], nulls, dups))
    return "\n".join(lines)


# --------------------------------------------------------------------------------------------- schema introspection

def _q(ident):
    return '"' + ident.replace('"', '""') + '"'


SCHEMA_SQL = {
    "columns": """SELECT c.table_name, c.column_name, c.data_type, c.udt_name, c.is_nullable,
       (c.column_default IS NOT NULL)::text, coalesce(c.character_maximum_length::text,''), coalesce(c.column_default,''),
       coalesce(c.identity_generation,''), c.is_generated
  FROM information_schema.columns c JOIN information_schema.tables t USING (table_schema, table_name)
 WHERE c.table_schema='public' AND t.table_type='BASE TABLE' AND c.table_name <> 'alembic_version'
 ORDER BY c.table_name, c.ordinal_position""",
    "uniques": """SELECT cl.relname, con.contype::text,
       array_to_string(ARRAY(SELECT a.attname FROM unnest(con.conkey) k JOIN pg_attribute a ON a.attrelid=con.conrelid AND a.attnum=k), ',')
  FROM pg_constraint con JOIN pg_class cl ON cl.oid=con.conrelid JOIN pg_namespace n ON n.oid=cl.relnamespace
 WHERE n.nspname='public' AND con.contype IN ('p','u')
UNION ALL
SELECT cl.relname, 'i',
       array_to_string(ARRAY(SELECT a.attname FROM unnest(i.indkey::int2[]) k JOIN pg_attribute a ON a.attrelid=i.indrelid AND a.attnum=k WHERE k>0), ',')
  FROM pg_index i JOIN pg_class cl ON cl.oid=i.indrelid JOIN pg_namespace n ON n.oid=cl.relnamespace
 WHERE n.nspname='public' AND i.indisunique AND i.indpred IS NULL AND NOT i.indisprimary""",
    "fks": """SELECT cl.relname, array_to_string(ARRAY(SELECT a.attname FROM unnest(con.conkey) k JOIN pg_attribute a ON a.attrelid=con.conrelid AND a.attnum=k), ','),
       rcl.relname, array_to_string(ARRAY(SELECT a.attname FROM unnest(con.confkey) k JOIN pg_attribute a ON a.attrelid=con.confrelid AND a.attnum=k), ',')
  FROM pg_constraint con JOIN pg_class cl ON cl.oid=con.conrelid JOIN pg_class rcl ON rcl.oid=con.confrelid
  JOIN pg_namespace n ON n.oid=cl.relnamespace WHERE n.nspname='public' AND con.contype='f'""",
    "enums": """SELECT t.typname, string_agg(e.enumlabel, E'\\x1e' ORDER BY e.enumsortorder)
  FROM pg_enum e JOIN pg_type t ON t.oid=e.enumtypid GROUP BY t.typname""",
}


def schema_introspect(psql):
    """psql(sql) -> stdout rows (SEP separated). Returns {'tables': {t: [col dicts]}, 'unique': {t: [[cols]...]}, 'pk': {t: [cols]},
    'fks': {t: [(cols, reftable, refcols)]}, 'enums': {typname: [labels]}}."""
    out = {"tables": {}, "unique": {}, "pk": {}, "fks": {}, "enums": {}}
    for line in psql(SCHEMA_SQL["columns"]).splitlines():
        p = line.split(SEP)
        if len(p) < 10:
            continue
        t, c, dt, udt, nullable, hasdef, clen, cdef, ident, gen = p[:10]
        out["tables"].setdefault(t, []).append({
            "name": c, "type": dt, "udt": udt, "nullable": nullable == "YES", "has_default": hasdef == "true",
            "maxlen": int(clen) if clen else None, "default": cdef, "identity": ident, "generated": gen == "ALWAYS"})
    for line in psql(SCHEMA_SQL["uniques"]).splitlines():
        p = line.split(SEP)
        if len(p) < 3 or not p[2]:
            continue
        t, kind, cols = p[0], p[1], p[2].split(",")
        if kind == "p":
            out["pk"][t] = cols
        out["unique"].setdefault(t, []).append(cols)
    for line in psql(SCHEMA_SQL["fks"]).splitlines():
        p = line.split(SEP)
        if len(p) < 4:
            continue
        out["fks"].setdefault(p[0], []).append((p[1].split(","), p[2], p[3].split(",")))
    for line in psql(SCHEMA_SQL["enums"]).splitlines():
        p = line.split(SEP, 1)
        if len(p) == 2:
            out["enums"][p[0]] = p[1].split("\x1e")
    return out


def synth_stress_stats(schema, rows=300, null_frac=0.25, dup_frac=0.5, max_len=300):
    """A clearly-labelled WORST-CASE-ish profile derived from the schema alone (no production knowledge): every nullable column
    ~25% null, every non-key column ~50% duplicates, text columns with long values. It answers "would this migration survive
    hostile data", NOT "would it survive prod" - use `collect` stats for the latter."""
    tables = {}
    uniq_cols = {t: {c for cols in us if len(cols) == 1 for c in cols} for t, us in schema["unique"].items()}
    for t, cols in schema["tables"].items():
        cs = {}
        for c in cols:
            if c["name"] in uniq_cols.get(t, set()):
                cs[c["name"]] = {"null_frac": 0.0, "distinct": rows, "max_len": max_len}
            else:
                cs[c["name"]] = {"null_frac": null_frac if c["nullable"] else 0.0, "distinct": max(1, int(rows * (1 - dup_frac))),
                                 "max_len": max_len}
        tables[t] = {"rows": rows, "columns": cs}
    return {"version": 1, "repo": "?", "kind": "synthetic_stress", "collected_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "tables": tables}


# --------------------------------------------------------------------------------------------- SQL generation

_INT = {"smallint", "integer", "bigint"}
_TEXT = {"character varying", "character", "text"}
_NUM = {"numeric", "real", "double precision", "money"}


def _col_expr(col, cs, v, enums, maxlen_cap):
    """SQL expression (a string) producing a value for `col` given value-index expression `v` (>=1). None = unsupported."""
    t, udt = col["type"], col["udt"]
    if t in _INT:
        return "((%s) %% %d)" % (v, 32000 if t == "smallint" else 2000000000)
    if t in _NUM:
        return "(%s)::numeric" % v
    if t == "boolean":
        return "((%s) %% 2 = 0)" % v
    if t in _TEXT or udt == "citext":
        lim = col["maxlen"]
        ml = cs.get("max_len")
        ml = min(ml if isinstance(ml, int) and ml > 0 else 0, lim or MAX_TEXT, MAX_TEXT)
        base = "left('v' || (%s), %d)" % (v, lim) if lim else "('v' || (%s))" % v
        if ml > 8:  # first distinct value carries the maximum observed length (exercises length-narrowing migrations)
            return "(CASE WHEN (%s) = 1 THEN rpad('v1', %d, 'x') ELSE %s END)" % (v, ml, base)
        return base
    if t == "uuid":
        return "md5('u' || (%s))::uuid" % v
    if t.startswith("timestamp"):
        return "(now() - ((%s) || ' minutes')::interval)" % v
    if t == "date":
        return "(current_date - ((%s) %% 3650)::int)" % v
    if t.startswith("time"):
        return "(time '00:00' + (((%s) %% 86400) || ' seconds')::interval)" % v
    if t == "interval":
        return "(((%s) %% 86400) || ' seconds')::interval" % v
    if t == "jsonb":
        return "'{}'::jsonb"
    if t == "json":
        return "'{}'::json"
    if t == "ARRAY":
        return "'{}'::%s" % _q(udt)
    if t == "bytea":
        return "decode(md5((%s)::text), 'hex')" % v
    if t == "inet":
        return "('10.0.' || (((%s) / 256) %% 256) || '.' || ((%s) %% 256))::inet" % (v, v)
    if t == "USER-DEFINED" and udt in enums and enums[udt]:
        labs = enums[udt]
        arr = "ARRAY[%s]" % ",".join("'" + l.replace("'", "''") + "'" for l in labs)
        return "(%s)[1 + ((%s) %% %d)]::%s" % (arr, v, len(labs), _q(udt))
    return None


def build_load_sql(schema, stats, scale=1.0, max_rows=None):
    """Returns (ordered [(table, sql, nrows)], report). Order is a topological order over foreign keys."""
    max_rows = max_rows or MAX_ROWS_DEFAULT
    report = {"tables_planned": 0, "ignored_stat_tables": [], "ignored_stat_columns": [], "capped_tables": [], "notes": []}
    st_tables = stats["tables"]
    for t in st_tables:
        if t not in schema["tables"]:
            report["ignored_stat_tables"].append(t)
    todo = [t for t in schema["tables"] if t in st_tables and st_tables[t]["rows"] > 0]
    # topological order by FK dependencies (self refs / cycles tolerated: leftovers appended)
    deps = {t: {r for (_, r, _) in schema["fks"].get(t, []) if r != t and r in todo} for t in todo}
    ordered, seen = [], set()
    while len(ordered) < len(todo):
        ready = [t for t in sorted(todo) if t not in seen and deps[t] <= seen]
        if not ready:
            ready = [sorted(t for t in todo if t not in seen)[0]]
            report["notes"].append("FK cycle involving %s; loaded without parent guarantee" % ready[0])
        for t in ready:
            seen.add(t)
            ordered.append(t)
    plans = []
    for t in ordered:
        ent = st_tables[t]
        n = int(ent["rows"] * scale)
        if n > max_rows:
            report["capped_tables"].append("%s:%d->%d" % (t, n, max_rows))
            n = max_rows
        n = max(n, 1)
        cstats = ent.get("columns") or {}
        names = {c["name"] for c in schema["tables"][t]}
        for c in cstats:
            if c not in names:
                report["ignored_stat_columns"].append("%s.%s" % (t, c))
        uniq1 = {c for cols in schema["unique"].get(t, []) if len(cols) == 1 for c in cols}
        comp = [cols for cols in schema["unique"].get(t, []) if len(cols) > 1]
        comp_last = {cols[-1] for cols in comp}
        pk = schema["pk"].get(t, [])
        fkcols = {}
        for i, (cols, rt, rcols) in enumerate(schema["fks"].get(t, [])):
            if len(cols) == 1 and len(rcols) == 1:
                fkcols[cols[0]] = (rt, rcols[0], "p%d" % i)
        ctes, cross, cols_sql, exprs = [], [], [], []
        used_fk = {}
        for col in schema["tables"][t]:
            name = col["name"]
            cs = cstats.get(name)
            if col["generated"] or col["identity"] == "ALWAYS":
                continue
            serial_pk = name in pk and col["type"] in _INT and col["default"].startswith("nextval(")
            if serial_pk or (cs is None and col["has_default"]):
                continue  # let the database default fill it
            cs = cs or {}
            nullable = col["nullable"] and name not in pk
            nf = float(cs.get("null_frac", 0.0)) if nullable else 0.0
            distinct = cs.get("distinct")
            unique = name in uniq1 or name in pk or name in comp_last
            k = n if (unique or distinct is None) else max(1, min(int(distinct), n))
            v = "g.i" if k >= n else "((g.i - 1) %% %d) + 1" % k
            if name in fkcols:
                rt, rc, cte = fkcols[name]
                if rt not in st_tables or rt not in seen or rt == t:
                    ex = "NULL" if col["nullable"] else None
                    if ex is None:
                        report["notes"].append("%s.%s is NOT NULL FK to %s which has no loaded rows" % (t, name, rt))
                        ex = _col_expr(col, cs, v, schema["enums"], MAX_TEXT)
                else:
                    if cte not in used_fk:
                        ctes.append("%s AS (SELECT array_agg(%s ORDER BY %s) a FROM (SELECT %s FROM %s ORDER BY %s LIMIT 100000) s)"
                                    % (cte, _q(rc), _q(rc), _q(rc), _q(rt), _q(rc)))
                        cross.append("CROSS JOIN %s" % cte)
                        used_fk[cte] = True
                    ex = "(%s.a)[1 + ((%s - 1) %% GREATEST(cardinality(%s.a), 1))]" % (cte, v if k < n else "g.i", cte)
            else:
                ex = _col_expr(col, cs, v, schema["enums"], MAX_TEXT)
            if ex is None:
                if col["nullable"]:
                    ex = "NULL"
                else:
                    report["notes"].append("%s.%s: unsupported type %s/%s, NOT NULL - table may fail to load" % (t, name, col["type"], col["udt"]))
                    continue
            if nf > 0:
                thr = int(round(nf * 1000))
                ex = "(CASE WHEN ((g.i * 7919) %% 1000) < %d THEN NULL ELSE %s END)" % (thr, ex)
            cols_sql.append(_q(name))
            exprs.append(ex)
        if not cols_sql:
            report["notes"].append("%s: no insertable columns" % t)
            continue
        sql = "%sINSERT INTO %s (%s) SELECT %s FROM generate_series(1, %d) AS g(i) %s;" % (
            ("WITH " + ", ".join(ctes) + " ") if ctes else "", _q(t), ", ".join(cols_sql), ", ".join(exprs), n, " ".join(cross))
        plans.append((t, sql, n))
    report["tables_planned"] = len(plans)
    return plans, report


def load_into(psql_db, schema, stats, scale=1.0, max_rows=None, timeout_hint=None):
    """psql_db(sql)->(rc, out, err) executes in the target database. Disables FK/triggers for the load
    (session_replication_role=replica). Returns a report dict: loaded, failed {table: first error line}, rows, notes."""
    plans, rep = build_load_sql(schema, stats, scale, max_rows)
    loaded, failed, rows = [], {}, 0
    for t, sql, n in plans:
        rc, out, err = psql_db("SET session_replication_role = replica;\n" + sql)
        if rc == 0 and "ERROR" not in err:
            loaded.append(t)
            rows += n
        else:
            msg = (err or out).strip().splitlines()
            failed[t] = (msg[0] if msg else "unknown error")[:200]
    # keep serial sequences ahead of the generated ids so later INSERTs by migrations/app do not collide
    for t in loaded:
        for col in schema["tables"][t]:
            if col["type"] in _INT and col["default"].startswith("nextval("):
                psql_db("SELECT setval(pg_get_serial_sequence('%s','%s'), (SELECT coalesce(max(%s),1) FROM %s));"
                        % (t.replace("'", "''"), col["name"].replace("'", "''"), _q(col["name"]), _q(t)))
    rep.update({"loaded": loaded, "failed": failed, "rows_loaded": rows})
    return rep


# --------------------------------------------------------------------------------------------- collect (read-only)

_TEXTISH = {"character varying", "character", "text"}
_SKIP_DISTINCT = {"json", "jsonb", "bytea", "ARRAY", "xml"}


def _libpq_env(url):
    """Parse a DB URL into libpq environment variables (so no secret ever appears in argv). Returns (env, redact_words)."""
    u = urllib.parse.urlsplit(url)
    if not u.hostname:
        raise ValueError("QA_STATS_DATABASE_URL is not a usable connection URL")
    q = dict(urllib.parse.parse_qsl(u.query))
    env = {"PGHOST": u.hostname, "PGPORT": str(u.port or 5432), "PGUSER": urllib.parse.unquote(u.username or ""),
           "PGPASSWORD": urllib.parse.unquote(u.password or ""), "PGDATABASE": (u.path or "/").lstrip("/") or "postgres",
           "PGSSLMODE": q.get("sslmode", "prefer"), "PGCONNECT_TIMEOUT": "15",
           # read-only at the connection level; every statement below additionally runs in BEGIN READ ONLY
           "PGOPTIONS": "-c default_transaction_read_only=on -c statement_timeout=120000 -c idle_in_transaction_session_timeout=60000"}
    words = [w for w in (env["PGHOST"], env["PGUSER"], env["PGPASSWORD"], env["PGDATABASE"]) if w and len(w) > 2]
    return env, words


def _redact(text, words):
    for w in sorted(words, key=len, reverse=True):
        text = text.replace(w, "***")
    return text


def _psql_runner(env):
    """Return fn(sql)->(rc,out,err). Uses a local psql if present, else docker run postgres:16 psql (network host)."""
    base_env = {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "HOME": os.environ.get("HOME", "/tmp")}
    base_env.update(env)
    if shutil.which("psql"):
        cmd = ["psql", "-X", "-A", "-t", "-F", SEP, "-v", "ON_ERROR_STOP=1", "-q"]
    elif shutil.which("docker"):
        cmd = ["docker", "run", "--rm", "-i", "--network", "host"]
        for k in env:
            cmd += ["-e", k]  # name only: the value is inherited from our environment, never placed in argv
        cmd += ["postgres:16", "psql", "-X", "-A", "-t", "-F", SEP, "-v", "ON_ERROR_STOP=1", "-q"]
    else:
        raise RuntimeError("neither psql nor docker is available")

    def run(sql):
        p = subprocess.run(cmd, input=sql.encode(), capture_output=True, env=base_env, timeout=300)
        return p.returncode, p.stdout.decode("utf-8", "replace"), p.stderr.decode("utf-8", "replace")
    return run


def collect(repo, out_path=None, url=None):
    url = url or os.environ.get("QA_STATS_DATABASE_URL", "")
    if not url:
        return 2, "QA_STATS_DATABASE_URL is not set (point it at a READ-ONLY replica/snapshot; never printed)"
    env, words = _libpq_env(url)
    run = _psql_runner(env)

    def ro(sql):
        rc, out, err = run("BEGIN READ ONLY;\n" + sql.strip().rstrip(";") + ";\nROLLBACK;")
        if rc != 0:
            raise RuntimeError(_redact(err.strip()[:300], words))
        return out

    # the connection MUST be read-only or we refuse to run a single query
    # 2026-10-02: probe OUTSIDE `BEGIN READ ONLY` (via ro() it always answered "on" - the probe could never fail). This asks the
    # connection itself, i.e. the PGOPTIONS default_transaction_read_only=on we set; a server that overrides it would show "off".
    rc0, out0, err0 = run("SHOW transaction_read_only;")
    if rc0 != 0:
        raise RuntimeError(_redact(err0.strip()[:300], words))
    probe = out0.strip().splitlines()
    if not probe or probe[-1].strip() != "on":
        return 3, "refusing to collect: connection is not read-only"
    schema = schema_introspect(lambda sql: ro(sql))
    tables = {}
    for t, cols in sorted(schema["tables"].items()):
        sels = ["count(*)"]
        for c in cols:
            qc_ = _q(c["name"])
            sels.append("count(*) FILTER (WHERE %s IS NULL)" % qc_)
            sels.append("NULL" if c["type"] in _SKIP_DISTINCT else "count(DISTINCT %s)" % qc_)
            sels.append("max(length(%s::text))" % qc_ if c["type"] in _TEXTISH else "NULL")
        try:
            # NB: no str.strip() on the row - \x1f (our separator) is whitespace to Python and a trailing empty field would vanish
            line = [l for l in ro("SELECT %s FROM %s;" % (", ".join(sels), _q(t))).split("\n") if l][-1].split(SEP)
            line += [""] * (1 + 3 * len(cols) - len(line))
        except Exception as ex:  # noqa: BLE001 - one unreadable table must not abort the rest
            tables[t] = {"rows": 0, "columns": {}, "error": str(ex)[:120]}
            continue
        n = int(line[0])
        cs = {}
        for i, c in enumerate(cols):
            nn, dist, ml = line[1 + 3 * i], line[2 + 3 * i], line[3 + 3 * i]
            nulls = int(nn or 0)
            d = int(dist) if dist not in ("", None) else None
            nonnull = n - nulls
            cs[c["name"]] = {"null_frac": round(nulls / n, 4) if n else 0.0, "distinct": d,
                             "max_len": int(ml) if ml not in ("", None) else None,
                             "dup_count": (nonnull - d) if d is not None else None}
        tables[t] = {"rows": n, "columns": cs}
    stats = {"version": 1, "repo": repo, "kind": "collected", "collected_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
             "tables": tables}
    out_path = out_path or stats_path(repo)
    os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
    tmp = out_path + ".tmp%d" % os.getpid()
    with open(tmp, "w") as f:
        json.dump(stats, f, indent=1, sort_keys=True)
    os.replace(tmp, out_path)
    return 0, "wrote %s (%d tables, %d rows total)" % (out_path, len(tables), sum(x["rows"] for x in tables.values()))


def main(argv):
    if not argv or argv[0] not in ("collect", "describe"):
        print(__doc__)
        return 2
    opts, i = {}, 1
    while i < len(argv):
        if argv[i].startswith("--") and i + 1 < len(argv):
            opts[argv[i][2:]] = argv[i + 1]
            i += 2
        else:
            i += 1
    if argv[0] == "describe":
        print(describe(load_stats(opts["stats"])))
        return 0
    if "repo" not in opts:
        print("collect needs --repo")
        return 2
    try:
        rc, msg = collect(opts["repo"], opts.get("out"))
    except Exception as ex:  # noqa: BLE001
        rc, msg = 1, "collect failed: %s" % str(ex)[:300]
    print(msg)
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
