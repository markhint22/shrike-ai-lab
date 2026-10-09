#!/usr/bin/env python3
"""Tests for qa/gate_migrations.py + qa/prodshape.py (gate S6). Run via test_qa_migrations.sh (picks the python + venv).

Part 1 (no docker): openapi_diff negative/benign controls, prodshape SQL generation + stats validation, collect refusals,
                    registry sanity, UNVERIFIED on missing docker (stub docker on PATH), NA cases.
Part 2 (docker + a venv with fastapi/sqlalchemy/psycopg2/alembic; SKIPped with a loud notice otherwise): a REAL git fixture repo
                    run through the REAL entry point (absolute path AND relative path from scripts/overnight-queue, under `env -i`
                    with a minimal PATH and NTFY_SERVER set): benign controls -> PASS, seeded bad changes -> FAIL/FLAG,
                    infra problems -> UNVERIFIED, no leaked qa-pg-* containers, reaper removes a SIGKILLed gate's container,
                    prodshape `collect` against a local container is read-only and leaks no row contents.
Environment: OVN_TEST_VENV = a venv dir with fastapi sqlalchemy psycopg2 alembic (default: first matching repo venv).
"""
import glob
import json
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
OVN = os.path.abspath(os.path.join(HERE, "..", ".."))              # scripts/overnight-queue
QA = os.path.join(OVN, "qa")
GATE = os.path.join(QA, "gate_migrations.py")
FIXT = os.path.join(HERE, "fixtures_qa_migrations")
sys.path.insert(0, QA)

PASSED, FAILED, SKIPPED = [], [], []


def ok(name, cond, extra=""):
    (PASSED if cond else FAILED).append(name)
    print("  %s %s%s" % ("ok  " if cond else "FAIL", name, ("   <- " + str(extra)[:400]) if (extra and not cond) else ""))
    return cond


def skip(name, why):
    SKIPPED.append(name)
    print("  SKIP %s (%s)" % (name, why))


# ============================================================================================ part 1: pure unit tests

def part1():
    import gate_migrations as g
    import prodshape as ps
    import qa_common as qc

    print("== openapi_diff")

    def spec(paths=None, schemas=None):
        return {"openapi": "3.1.0", "paths": paths or {}, "components": {"schemas": schemas or {}}}

    def ref(n):
        return {"$ref": "#/components/schemas/" + n}

    def jbody(s):
        return {"content": {"application/json": {"schema": s}}}

    user_out = {"type": "object", "required": ["id", "email"], "properties": {
        "id": {"type": "integer"}, "email": {"type": "string"}, "name": {"anyOf": [{"type": "string"}, {"type": "null"}]}}}
    user_in = {"type": "object", "required": ["email"], "properties": {"email": {"type": "string"}}}

    def base():
        return spec({"/users": {"get": {"responses": {"200": jbody({"type": "array", "items": ref("UserOut")})}},
                                "post": {"requestBody": dict(jbody(ref("UserIn")), required=True),
                                         "responses": {"200": jbody(ref("UserOut"))}}},
                     "/health": {"get": {"responses": {"200": {"description": "ok"}}}}},
                    {"UserOut": json.loads(json.dumps(user_out)), "UserIn": json.loads(json.dumps(user_in))})

    brk, adds = g.openapi_diff(base(), base())
    ok("openapi identical -> no breaking, 0 additions", brk == [] and adds == 0, brk)

    n = base()
    n["components"]["schemas"]["UserOut"]["properties"]["nick"] = {"type": "string"}
    n["paths"]["/new"] = {"get": {"responses": {"200": {"description": "ok"}}}}
    n["components"]["schemas"]["UserIn"]["properties"]["bio"] = {"type": "string"}      # optional request field
    brk, adds = g.openapi_diff(base(), n)
    ok("openapi additive (new path, optional req field, new resp field) -> benign", brk == [] and adds >= 1, brk)

    n = base()
    del n["paths"]["/health"]
    brk, _ = g.openapi_diff(base(), n)
    ok("openapi removed path -> endpoint-removed", [b["kind"] for b in brk] == ["endpoint-removed"], brk)

    n = base()
    del n["paths"]["/users"]["post"]
    brk, _ = g.openapi_diff(base(), n)
    ok("openapi removed method -> endpoint-removed", any(b["kind"] == "endpoint-removed" and "POST" in b["where"] for b in brk), brk)

    n = base()
    del n["components"]["schemas"]["UserOut"]["properties"]["name"]
    brk, _ = g.openapi_diff(base(), n)
    ok("openapi removed response field (through $ref, nested in array) -> response-field-removed",
       any(b["kind"] == "response-field-removed" and b["where"].endswith(".name") for b in brk), brk)

    n = base()
    del n["components"]["schemas"]["UserIn"]["properties"]["email"]
    n["components"]["schemas"]["UserIn"]["required"] = []
    brk, _ = g.openapi_diff(base(), n)
    ok("openapi removed request field -> request-field-removed", any(b["kind"] == "request-field-removed" for b in brk), brk)

    n = base()
    n["components"]["schemas"]["UserIn"]["properties"]["age"] = {"type": "integer"}
    n["components"]["schemas"]["UserIn"]["required"] = ["email", "age"]
    brk, _ = g.openapi_diff(base(), n)
    ok("openapi newly-required request field -> request-field-newly-required",
       any(b["kind"] == "request-field-newly-required" and b["where"].endswith(".age") for b in brk), brk)

    n = base()
    n["components"]["schemas"]["UserIn"]["required"] = ["email"]
    n["components"]["schemas"]["UserIn"]["properties"]["name"] = {"type": "string"}
    b0 = base()
    b0["components"]["schemas"]["UserIn"]["properties"]["name"] = {"type": "string"}
    n["components"]["schemas"]["UserIn"]["required"] = ["email", "name"]
    brk, _ = g.openapi_diff(b0, n)
    ok("openapi optional->required request field -> flagged", any("became required" in b["detail"] for b in brk), brk)

    n = base()
    n["components"]["schemas"]["UserOut"]["properties"]["id"] = {"type": "string"}
    brk, _ = g.openapi_diff(base(), n)
    ok("openapi changed response type int->str -> type-changed", any(b["kind"] == "type-changed" for b in brk), brk)

    n = base()
    n["components"]["schemas"]["UserIn"]["properties"]["email"] = {"type": "integer"}
    brk, _ = g.openapi_diff(base(), n)
    ok("openapi changed request type str->int -> type-changed", any(b["kind"] == "type-changed" for b in brk), brk)

    n = base()
    del n["paths"]["/users"]["post"]["responses"]["200"]
    n["paths"]["/users"]["post"]["responses"]["201"] = jbody(ref("UserOut"))
    brk, _ = g.openapi_diff(base(), n)
    ok("openapi removed 2xx response status -> response-status-removed", any(b["kind"] == "response-status-removed" for b in brk), brk)

    n = base()
    n["paths"]["/users"]["get"]["responses"]["422"] = {"description": "validation"}
    brk, _ = g.openapi_diff(base(), n)
    ok("openapi added 422 response is not breaking", brk == [], brk)

    n = base()
    n["components"]["schemas"]["UserOut"]["properties"]["name"] = {"type": "string"}      # was nullable
    brk, _ = g.openapi_diff(base(), n)
    ok("openapi response field no longer nullable is NOT breaking (narrower)", brk == [], brk)

    n = base()
    n["components"]["schemas"]["UserOut"]["properties"]["email"] = {"anyOf": [{"type": "string"}, {"type": "null"}]}
    brk, _ = g.openapi_diff(base(), n)
    ok("openapi response field became nullable -> flagged", any(b["kind"] == "response-became-nullable" for b in brk), brk)

    # cyclic $ref must not hang
    cyc = spec({"/t": {"get": {"responses": {"200": jbody(ref("Node"))}}}},
               {"Node": {"type": "object", "properties": {"child": ref("Node"), "v": {"type": "integer"}}}})
    brk, _ = g.openapi_diff(cyc, json.loads(json.dumps(cyc)))
    ok("openapi self-referential schema terminates cleanly", brk == [])

    print("== prodshape generation (no database)")
    schema = {"tables": {
        "users": [{"name": "id", "type": "integer", "udt": "int4", "nullable": False, "has_default": True, "maxlen": None, "default": "nextval('u')", "identity": "", "generated": False},
                  {"name": "email", "type": "character varying", "udt": "varchar", "nullable": False, "has_default": False, "maxlen": 80, "default": "", "identity": "", "generated": False},
                  {"name": "nick", "type": "character varying", "udt": "varchar", "nullable": True, "has_default": False, "maxlen": 10, "default": "", "identity": "", "generated": False},
                  {"name": "role", "type": "USER-DEFINED", "udt": "role_t", "nullable": False, "has_default": False, "maxlen": None, "default": "", "identity": "", "generated": False}],
        "posts": [{"name": "id", "type": "integer", "udt": "int4", "nullable": False, "has_default": True, "maxlen": None, "default": "nextval('p')", "identity": "", "generated": False},
                  {"name": "user_id", "type": "integer", "udt": "int4", "nullable": False, "has_default": False, "maxlen": None, "default": "", "identity": "", "generated": False}]},
        "unique": {"users": [["id"], ["email"]], "posts": [["id"]]}, "pk": {"users": ["id"], "posts": ["id"]},
        "fks": {"posts": [(["user_id"], "users", ["id"])]}, "enums": {"role_t": ["admin", "member"]}}
    stats = {"tables": {"posts": {"rows": 50, "columns": {}},
                        "users": {"rows": 100, "columns": {"email": {"null_frac": 0, "distinct": 100, "max_len": 80},
                                                           "nick": {"null_frac": 0.3, "distinct": 40, "max_len": 10}}},
                        "ghost": {"rows": 5, "columns": {}}}}
    plans, rep = ps.build_load_sql(schema, stats)
    order = [p[0] for p in plans]
    ok("prodshape orders parents (users) before children (posts)", order == ["users", "posts"], order)
    ok("prodshape ignores stats tables absent from the base schema (listed, not fatal)", rep["ignored_stat_tables"] == ["ghost"], rep)
    usql = dict((t, s) for t, s, _ in plans)["users"]
    ok("prodshape lets the DB fill serial PK (id column not inserted)", '"id"' not in usql.split("SELECT")[0], usql[:200])
    ok("prodshape applies null fraction to nullable columns (CASE ... NULL)", "THEN NULL" in usql and "< 300" in usql, usql[:400])
    ok("prodshape clamps duplicates via distinct count (% 40)", "% 40" in usql, usql[:400])
    ok("prodshape emits the long max-length value without exceeding the column limit", "rpad('v1', 10" in usql, usql[:400])
    ok("prodshape draws enum values from the real labels", "'admin','member'" in usql, usql[:400])
    psql_ = dict((t, s) for t, s, _ in plans)["posts"]
    ok("prodshape FK column samples parent keys (array_agg CTE)", "array_agg" in psql_ and "cardinality" in psql_, psql_[:300])
    ok("prodshape caps huge row counts", ps.build_load_sql(schema, {"tables": {"users": {"rows": 10 ** 9, "columns": {}}}}, max_rows=77)[0][0][2] == 77)
    bad = False
    try:
        import tempfile as _t
        p = os.path.join(_t.mkdtemp(), "s.json")
        json.dump({"tables": {"t": {"rows": 1, "columns": {"c": {"null_frac": 3}}}}}, open(p, "w"))
        ps.load_stats(p)
    except ValueError:
        bad = True
    ok("prodshape rejects a stats file with null_frac outside 0..1", bad)
    for repo in ("billwatch", "fx"):
        s = ps.load_stats(os.path.join(FIXT, repo + ".stats.json"))
        ok("hand-written stats fixture %s.stats.json is valid" % repo, len(s["tables"]) >= 1 and s["kind"] == "handwritten")
    stress = ps.synth_stress_stats(schema)
    ok("synth_stress_stats labels itself and has nulls+dups", stress["kind"] == "synthetic_stress" and stress["tables"]["users"]["columns"]["nick"]["null_frac"] > 0)

    print("== collect refusals (no database)")
    env = {k: v for k, v in os.environ.items() if k != "QA_STATS_DATABASE_URL"}
    r = subprocess.run([sys.executable, os.path.join(QA, "prodshape.py"), "collect", "--repo", "x", "--out", "/nonexistent-dir/x.json"],
                       capture_output=True, text=True, env=env)
    ok("collect without QA_STATS_DATABASE_URL refuses (rc!=0) and names the variable", r.returncode != 0 and "QA_STATS_DATABASE_URL" in r.stdout, r.stdout + r.stderr)
    env2 = dict(env, QA_STATS_DATABASE_URL="postgresql://secretuser:SuperSecretPw@192.0.2.1:1/prod?sslmode=disable")
    r = subprocess.run([sys.executable, os.path.join(QA, "prodshape.py"), "collect", "--repo", "x", "--out", os.path.join(tempfile.mkdtemp(), "x.json")],
                       capture_output=True, text=True, env=env2, timeout=120)
    leak = "SuperSecretPw" in r.stdout + r.stderr or "secretuser" in r.stdout + r.stderr or "192.0.2.1" in r.stdout + r.stderr
    ok("collect against an unreachable host fails WITHOUT printing the url, user, password or host", r.returncode != 0 and not leak, r.stdout + r.stderr)
    # 2026-10-02: the read-only probe used to run INSIDE `BEGIN READ ONLY`, so it always said "on" and could never refuse. A stub psql
    # on PATH answers the probe: "off" => collect must refuse (rc 3) after exactly ONE statement, "on" => it proceeds.
    sd = tempfile.mkdtemp(prefix="qa-mig-psqlstub-")
    logf = os.path.join(sd, "calls.log")
    with open(os.path.join(sd, "psql"), "w") as f:
        f.write('#!/bin/sh\nsql=$(cat)\nprintf "%%s\\n--CALL--\\n" "$sql" >> "%s"\n'
                'case "$sql" in *"BEGIN READ ONLY"*) ;; *"SHOW transaction_read_only"*) cat "$(dirname "$0")/ro";; esac\nexit 0\n' % logf)
    os.chmod(os.path.join(sd, "psql"), 0o755)
    saved_env = {k: os.environ.get(k) for k in ("PATH",)}
    setro = lambda v: open(os.path.join(sd, "ro"), "w").write(v + "\n")  # noqa: E731
    try:
        os.environ["PATH"] = sd + ":" + saved_env["PATH"]
        setro("off")
        rc_, msg_ = ps.collect("x", out_path=os.path.join(sd, "o.json"), url="postgresql://u:pw@h.example/db")
        calls = open(logf).read().split("--CALL--") if os.path.exists(logf) else []
        ok("negative: server says transaction_read_only=off -> collect refuses (rc 3) and ran only the probe, nothing written",
           rc_ == 3 and "not read-only" in msg_ and len([c for c in calls if c.strip()]) == 1 and "BEGIN READ ONLY" not in calls[0]
           and not os.path.exists(os.path.join(sd, "o.json")), (rc_, msg_, calls))
        setro("on")
        rc_, msg_ = ps.collect("x", out_path=os.path.join(sd, "o.json"), url="postgresql://u:pw@h.example/db")
        ok("benign: read-only connection (on) -> collect proceeds and writes a stats file", rc_ == 0 and os.path.exists(os.path.join(sd, "o.json")), (rc_, msg_))
    finally:
        for k, v in saved_env.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v
        shutil.rmtree(sd, ignore_errors=True)
    e, words = ps._libpq_env("postgresql+asyncpg://u:p%40ss@h.example:6543/db?sslmode=require")
    ok("libpq env parsed from url (driver suffix, escaped password, sslmode); nothing in argv",
       e["PGHOST"] == "h.example" and e["PGPASSWORD"] == "p@ss" and e["PGSSLMODE"] == "require" and "default_transaction_read_only=on" in e["PGOPTIONS"])

    print("== registry")
    with open(os.path.join(QA, "qa_repos.json")) as f:
        reg = json.load(f)
    for repo in ("billwatch", "gitlark", "iptv_apps", "test-automation-agent"):
        c = reg.get(repo, {})
        ok("qa_repos.json has %s with backend_dir/venv/openapi" % repo, c.get("backend_dir") and c.get("venv") and c.get("openapi", {}).get("module"))

    print("== time budget derives from the shadow runner's cap")
    saved = {k: os.environ.pop(k, None) for k in ("QA_MIGR_BUDGET", "QA_GATE_TIMEOUT")}
    try:
        ok("default budget (no env) is 120s under the runner's default 900s cap", g.default_budget() == 780, g.default_budget())
        os.environ["QA_GATE_TIMEOUT"] = "300"
        ok("budget follows QA_GATE_TIMEOUT-120 (cap 300 -> 180)", g.default_budget() == 180, g.default_budget())
        os.environ["QA_GATE_TIMEOUT"] = "100"
        ok("budget never below 60s (tiny cap)", g.default_budget() == 60, g.default_budget())
        os.environ["QA_GATE_TIMEOUT"] = "garbage"
        ok("garbage cap falls back to the default instead of crashing", g.default_budget() == 780, g.default_budget())
        os.environ["QA_MIGR_BUDGET"] = "42"
        ok("explicit QA_MIGR_BUDGET wins", g.default_budget() == 42, g.default_budget())
        ok("parse_args picks the derived budget", g.parse_args(["check", "--repo", "r"])["budget"] == 42)
    finally:
        for k in ("QA_MIGR_BUDGET", "QA_GATE_TIMEOUT"):
            os.environ.pop(k, None)
            if saved[k] is not None:
                os.environ[k] = saved[k]

    print("== coverage exclusion consistency (qa/ is unmeasurable under env -i; these files live there)")
    covsh = os.path.join(OVN, "scripts", "cov", "run_coverage.sh")
    covpy = os.path.join(OVN, "scripts", "cov", "ovn_cov_report.py")
    if os.path.exists(covsh) and os.path.exists(covpy):
        csrc, psrc = open(covsh).read(), open(covpy).read()
        ok("run_coverage.sh omits */qa/* (covers gate_migrations/prodshape/_migr_helper/replay_migrations)", "*/qa/*" in csrc)
        ok("ovn_cov_report.py walk skips the qa dir", '"qa"' in psrc)
        ok("every S6 file sits under qa/ (so the exclusions apply)", all(os.path.exists(os.path.join(QA, f)) for f in
           ("gate_migrations.py", "prodshape.py", "_migr_helper.py", "replay_migrations.py")))
    else:
        skip("coverage exclusion consistency", "scripts/cov not present in this tree")

    print("== entry point without docker / NA cases (stub docker on PATH)")
    work = tempfile.mkdtemp(prefix="qa-mig-t1-")
    try:
        fx = make_fixture_repo(work, venv=None, with_venv=False)
        stubdir = os.path.join(work, "stub")
        os.makedirs(stubdir)
        with open(os.path.join(stubdir, "docker"), "w") as f:
            f.write("#!/bin/sh\nexit 1\n")
        os.chmod(os.path.join(stubdir, "docker"), 0o755)
        stub_path = stubdir + ":/usr/bin:/bin"
        # a relevant change (backend/app/models.py) but docker is down => UNVERIFIED, never FAIL/PASS
        branch(fx, "dockerless", {"backend/app/models.py": MODELS + "\n# touch\n"})
        v = run_gate(fx, "main", "dockerless", path=stub_path)
        ok("docker unavailable -> UNVERIFIED (not PASS, not FAIL)", v["verdict"] == "UNVERIFIED" and "docker" in v["summary"], v)
        branch(fx, "docs_only", {"README.md": "hello\n"})
        v = run_gate(fx, "main", "docs_only", path=stub_path)
        ok("docs-only diff -> NA (no docker needed)", v["verdict"] == "NA", v)
        branch(fx, "tests_only", {"backend/tests/test_x.py": "def test_x():\n    assert True\n"})
        v = run_gate(fx, "main", "tests_only", path=stub_path)
        ok("tests-only diff under backend/ -> NA", v["verdict"] == "NA", v)
        v = run_gate(fx, "main", "dockerless", path=stub_path, repo="nosuchrepo")
        ok("repo not in qa_repos.json -> NA", v["verdict"] == "NA", v)
        # 2026-10-02: the off switch (OVN_QA_MIGRATIONS=off) must stop the gate before it touches docker or the repo
        v = run_gate(fx, "main", "dockerless", path=stub_path, envx={"OVN_QA_MIGRATIONS": "off"})
        ok("mode off (env) -> NA 'gate is off', no docker probe (negative: same diff without the switch is UNVERIFIED above)",
           v["verdict"] == "NA" and "off" in v["summary"] and not v["details"], v)
        v = run_gate(fx, "main", "dockerless", path=stub_path, envx={"OVN_QA_MIGRATIONS": "enforce"})
        ok("benign: mode enforce does not short-circuit (docker down -> UNVERIFIED)", v["verdict"] == "UNVERIFIED", v)
        v = run_gate(fx, "main", "no-such-ref", path=stub_path)
        ok("unresolvable head ref -> UNVERIFIED/NA, never a crash or FAIL", v["verdict"] in ("UNVERIFIED", "NA"), v)
        # docker answers `info` but cannot start a container => UNVERIFIED and no hang
        with open(os.path.join(stubdir, "docker"), "w") as f:
            f.write('#!/bin/sh\ncase "$1" in info) echo 27.0; exit 0;; ps) exit 0;; *) echo "boom" >&2; exit 1;; esac\n')
        # venv must exist for this path: make a dummy one
        fx2 = make_fixture_repo(os.path.join(work, "two"), venv="/usr", with_venv=False)
        branch(fx2, "dockerless", {"backend/app/models.py": MODELS + "\n# touch\n"})
        v = run_gate(fx2, "main", "dockerless", path=stub_path)
        ok("container cannot start -> UNVERIFIED", v["verdict"] == "UNVERIFIED", v)
    finally:
        shutil.rmtree(work, ignore_errors=True)


# ============================================================================================ fixture repo

ALEMBIC_INI = "[alembic]\nscript_location = alembic\nprepend_sys_path = .\n"
ENV_PY = '''import os
from alembic import context
from sqlalchemy import create_engine, pool
from app.db import Base
import app.models  # noqa: F401
target_metadata = Base.metadata
url = os.environ["DATABASE_URL"].replace("+asyncpg", "+psycopg2")
eng = create_engine(url, poolclass=pool.NullPool)
with eng.connect() as c:
    context.configure(connection=c, target_metadata=target_metadata, compare_type=True)
    with context.begin_transaction():
        context.run_migrations()
'''
DB_PY = "from sqlalchemy.orm import declarative_base\nBase = declarative_base()\n"
MODELS = '''from sqlalchemy import Column, Integer, String
from app.db import Base


class User(Base):
    __tablename__ = "users"
    id = Column(Integer, primary_key=True)
    email = Column(String(120), nullable=False)
    name = Column(String(50), nullable=True)
'''
MAIN = '''from typing import List, Optional
from fastapi import FastAPI
from pydantic import BaseModel
import app.models  # noqa: F401

app = FastAPI()


class UserIn(BaseModel):
    email: str


class UserOut(BaseModel):
    id: int
    email: str
    name: Optional[str] = None


@app.get("/users", response_model=List[UserOut])
def users():
    return []


@app.post("/users", response_model=UserOut)
def create(u: UserIn):
    return {"id": 1, "email": u.email}


@app.get("/health")
def health():
    return {"ok": True}
'''
M0001 = '''import sqlalchemy as sa
from alembic import op

revision = "0001"
down_revision = None


def upgrade():
    op.create_table("users", sa.Column("id", sa.Integer, primary_key=True), sa.Column("email", sa.String(120), nullable=False),
                    sa.Column("name", sa.String(50), nullable=True))


def downgrade():
    op.drop_table("users")
'''


def mig(rev, down, up, dn="pass"):
    return 'import sqlalchemy as sa\nfrom alembic import op\n\nrevision = "%s"\ndown_revision = %s\n\n\ndef upgrade():\n    %s\n\n\ndef downgrade():\n    %s\n' % (
        rev, ('"%s"' % down) if down else "None", up, dn)


def sh(cmd, cwd, env=None):
    r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, env=env or dict(os.environ, GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t", GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@t"))
    if r.returncode != 0:
        raise RuntimeError("%s failed: %s" % (cmd, r.stderr))
    return r.stdout


def make_fixture_repo(root, venv, with_venv=True):
    """Creates <root>/repos/fx (a real git repo, branch main) and <root>/repos.json registry. Returns a dict of paths."""
    repos = os.path.join(root, "repos")
    fx = os.path.join(repos, "fx")
    os.makedirs(os.path.join(fx, "backend", "alembic", "versions"))
    os.makedirs(os.path.join(fx, "backend", "app"))

    def w(rel, txt):
        with open(os.path.join(fx, rel), "w") as f:
            f.write(txt)
    w("README.md", "fixture\n")
    w("backend/alembic.ini", ALEMBIC_INI)
    w("backend/alembic/env.py", ENV_PY)
    w("backend/alembic/versions/0001.py", M0001)
    w("backend/app/__init__.py", "")
    w("backend/app/db.py", DB_PY)
    w("backend/app/models.py", MODELS)
    w("backend/app/main.py", MAIN)
    sh(["git", "init", "-q", "-b", "main"], fx)
    sh(["git", "add", "README.md", "backend"], fx)
    sh(["git", "commit", "-q", "-m", "base"], fx)
    reg = {"fx": {"clone": "fx", "backend_dir": "backend", "alembic_ini": "alembic.ini", "script_location": "alembic",
                  "venv": venv or ".venv", "db_scheme": "postgresql+asyncpg", "env": {}, "openapi": {"module": "app.main:app"}}}
    rj = os.path.join(root, "repos.json")
    with open(rj, "w") as f:
        json.dump(reg, f)
    return {"root": root, "repos": repos, "fx": fx, "reg": rj, "ovn": os.path.join(root, "ovn")}


def branch(fx, name, files, start="main"):
    sh(["git", "checkout", "-q", "-b", name, start], fx["fx"])
    for rel, txt in files.items():
        p = os.path.join(fx["fx"], rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "w") as f:
            f.write(txt)
    sh(["git", "add"] + list(files), fx["fx"])
    sh(["git", "commit", "-q", "-m", name], fx["fx"])
    sh(["git", "checkout", "-q", "main"], fx["fx"])


def docker_dir():
    d = shutil.which("docker")
    return os.path.dirname(d) if d else ""


def run_gate(fx, base, head, path=None, repo="fx", extra=None, rel=False, py=None, timeout=900, record=False, envx=None):
    py = py or sys.executable
    env = {"PATH": path or ("/usr/bin:/bin:" + docker_dir()), "HOME": fx["root"], "NTFY_SERVER": "http://127.0.0.1:9",
           "OVN_DIR": fx["ovn"], "OVN_REPOS_DIR": fx["repos"], "QA_REPOS_JSON": fx["reg"], "LANG": "C.UTF-8"}
    env.update(envx or {})
    cmd = [py, ("qa/gate_migrations.py" if rel else GATE), "check", "--repo", repo, "--base", base, "--head", head]
    if not record:
        cmd.append("--no-record")
    cmd += extra or []
    r = subprocess.run(["env", "-i"] + ["%s=%s" % kv for kv in env.items()] + cmd, cwd=OVN if rel else "/", capture_output=True, text=True, timeout=timeout)
    lines = [l for l in r.stdout.strip().splitlines() if l.strip()]
    try:
        v = json.loads(lines[-1])
    except Exception:  # noqa: BLE001
        v = {"verdict": "NOPARSE", "summary": (r.stdout + r.stderr)[-500:], "details": {}}
    v["_rc"] = r.returncode
    return v


def step(v, name):
    for s in v.get("details", {}).get("steps", []):
        if s["step"] == name:
            return s
    return {}


def docker_up():
    r = subprocess.run(["docker", "info"], capture_output=True, timeout=30) if shutil.which("docker") else None
    return bool(r and r.returncode == 0)


def leaked():
    r = subprocess.run(["docker", "ps", "-a", "--filter", "name=qa-pg-", "--format", "{{.Names}}"], capture_output=True, text=True)
    return r.stdout.split()


def find_venv():
    cands = [os.environ.get("OVN_TEST_VENV", "")]
    for pat in ("~/overnight-queue/repos/*/*/.venv", "~/LocalProjects/*/*/.venv"):
        cands += sorted(glob.glob(os.path.expanduser(pat)))
    for c in cands:
        py = os.path.join(c, "bin", "python") if c else ""
        if py and os.path.exists(py):
            r = subprocess.run([py, "-c", "import fastapi, sqlalchemy, psycopg2, alembic, pydantic"], capture_output=True)
            if r.returncode == 0:
                return c
    return None


# ============================================================================================ part 2: docker integration

def part2():
    print("== integration (real postgres container + real git fixture repo)")
    if not docker_up():
        skip("integration scenarios", "docker daemon not reachable here")
        return
    venv = find_venv()
    if not venv:
        skip("integration scenarios", "no venv with fastapi+sqlalchemy+psycopg2+alembic (set OVN_TEST_VENV)")
        return
    work = tempfile.mkdtemp(prefix="qa-mig-t2-")
    try:
        fx = make_fixture_repo(work, venv=venv)
        sdir = os.path.join(work, "stats")
        os.makedirs(sdir)
        shutil.copy(os.path.join(FIXT, "fx.stats.json"), os.path.join(sdir, "fx.stats.json"))
        stats = os.path.join(sdir, "fx.stats.json")

        add_nick = MODELS + '    nick = Column(String(20), nullable=True)\n'
        m2_nick = mig("0002", "0001", 'op.add_column("users", sa.Column("nick", sa.String(20), nullable=True))',
                      'op.drop_column("users", "nick")')
        V = "backend/alembic/versions/"
        scenarios = {
            "benign_add_column": {"backend/app/models.py": add_nick, V + "0002.py": m2_nick},
            "drift_model_only": {"backend/app/models.py": add_nick},
            "bad_upgrade": {V + "0002.py": mig("0002", "0001", 'op.execute("SELECT * FROM table_that_does_not_exist")')},
            "multi_heads": {V + "0002a.py": mig("0002a", "0001", "pass"), V + "0002b.py": mig("0002b", "0001", "pass")},
            "bad_downgrade": {"backend/app/models.py": add_nick,
                              V + "0002.py": mig("0002", "0001", 'op.add_column("users", sa.Column("nick", sa.String(20), nullable=True))',
                                                 'op.execute("DROP TABLE table_that_does_not_exist")')},
            "shape_unique_dups": {
                "backend/app/models.py": MODELS.replace("from sqlalchemy import Column, Integer, String", "from sqlalchemy import Column, Integer, String, UniqueConstraint")
                + '    __table_args__ = (UniqueConstraint("name", name="uq_users_name"),)\n',
                V + "0002.py": mig("0002", "0001", 'op.create_unique_constraint("uq_users_name", "users", ["name"])',
                                   'op.drop_constraint("uq_users_name", "users")')},
            "shape_not_null": {
                "backend/app/models.py": MODELS.replace("name = Column(String(50), nullable=True)", "name = Column(String(50), nullable=False)"),
                V + "0002.py": mig("0002", "0001", 'op.alter_column("users", "name", existing_type=sa.String(50), nullable=False)',
                                   'op.alter_column("users", "name", existing_type=sa.String(50), nullable=True)')},
            "shape_narrow_type": {
                "backend/app/models.py": MODELS.replace("name = Column(String(50)", "name = Column(String(10)"),
                V + "0002.py": mig("0002", "0001", 'op.alter_column("users", "name", existing_type=sa.String(50), type_=sa.String(10))',
                                   'op.alter_column("users", "name", existing_type=sa.String(10), type_=sa.String(50))')},
            "shape_benign_unique_email": {
                "backend/app/models.py": MODELS.replace("from sqlalchemy import Column, Integer, String", "from sqlalchemy import Column, Integer, String, UniqueConstraint")
                + '    __table_args__ = (UniqueConstraint("email", name="uq_users_email"),)\n',
                V + "0002.py": mig("0002", "0001", 'op.create_unique_constraint("uq_users_email", "users", ["email"])',
                                   'op.drop_constraint("uq_users_email", "users")')},
            "api_remove_field": {"backend/app/main.py": MAIN.replace("    name: Optional[str] = None\n", "")},
            "api_remove_endpoint": {"backend/app/main.py": MAIN.replace('@app.get("/health")\ndef health():\n    return {"ok": True}\n', "")},
            "api_new_required": {"backend/app/main.py": MAIN.replace("class UserIn(BaseModel):\n    email: str\n", "class UserIn(BaseModel):\n    email: str\n    age: int\n")},
            "api_type_change": {"backend/app/main.py": MAIN.replace("    id: int\n", "    id: str\n")},
            "api_additive": {"backend/app/main.py": MAIN.replace("    name: Optional[str] = None\n", "    name: Optional[str] = None\n    nick: Optional[str] = None\n")
                             + '\n\n@app.get("/ping")\ndef ping():\n    return {"pong": True}\n'},
            "app_broken": {"backend/app/main.py": MAIN + '\nraise RuntimeError("boom at import")\n'},
        }
        for name, files in scenarios.items():
            branch(fx, name, files)
        LONG = "0002_" + "x" * 40     # 45 chars: does not fit alembic_version.version_num varchar(32) on Postgres
        branch(fx, "long_rev_id", {"backend/app/models.py": add_nick, V + "0002.py": mig(LONG, "0001", 'op.add_column("users", sa.Column("nick", sa.String(20), nullable=True))',
                                                                                          'op.drop_column("users", "nick")')})
        branch(fx, "long_rev_followup", {"backend/app/models.py": add_nick + "\n# touch\n", V + "0002.py": mig(LONG, "0001", 'op.add_column("users", sa.Column("nick", sa.String(20), nullable=True))',
                                                                                                              'op.drop_column("users", "nick")')}, start="long_rev_id")
        branch(fx, "bad_upgrade_followup", {"backend/app/models.py": MODELS + "\n# touch\n"}, start="bad_upgrade")
        BAD2 = mig("0002", "0001", 'op.execute("SELECT * FROM table_that_does_not_exist")')
        OK2 = mig("0002", "0001", "pass")
        branch(fx, "dr_c0", {"backend/app/models.py": add_nick})                          # model column with no migration: standing drift
        branch(fx, "dr_base", {V + "0002.py": BAD2}, start="dr_c0")                       # chain broken at this base
        branch(fx, "dr_fix", {V + "0002.py": OK2}, start="dr_base")
        branch(fx, "dr_fix_newdrift", {V + "0002.py": OK2, "backend/app/models.py": add_nick + '    bio = Column(String(20), nullable=True)\n'}, start="dr_base")
        before = set(leaked())

        def go(name, **kw):
            return run_gate(fx, "main", name, **kw)

        v = go("benign_add_column")
        ok("benign add nullable column + migration -> PASS (real entry point, abs path)", v["verdict"] == "PASS", v["summary"])
        ok("  benign: upgrade_empty, drift and roundtrip all PASS", all(step(v, s).get("verdict") == "PASS" for s in ("upgrade_empty", "drift", "roundtrip")), v["details"].get("steps"))
        v = go("benign_add_column", rel=True)
        ok("benign add column via RELATIVE path from scripts/overnight-queue -> PASS", v["verdict"] == "PASS", v["summary"])

        v = go("drift_model_only")
        ok("negative: model column without migration -> FAIL drift", v["verdict"] == "FAIL" and step(v, "drift").get("verdict") == "FAIL" and "add_column" in step(v, "drift").get("msg", ""), v["summary"])
        ok("  drift: the empty-db upgrade itself still PASSes (drift is what is wrong)", step(v, "upgrade_empty").get("verdict") == "PASS")

        v = go("bad_upgrade")
        ok("negative: migration with bad SQL -> FAIL upgrade_empty (base passes)", v["verdict"] == "FAIL" and step(v, "upgrade_empty").get("verdict") == "FAIL", v["summary"])

        v = go("multi_heads")
        ok("negative: two heads -> FAIL heads", v["verdict"] == "FAIL" and step(v, "heads").get("verdict") == "FAIL" and "multiple heads" in step(v, "heads").get("msg", ""), v["summary"])

        v = go("bad_downgrade")
        ok("negative: broken downgrade -> FLAG roundtrip (default: does not break a deploy)", v["verdict"] == "FLAG" and step(v, "roundtrip").get("verdict") == "FLAG", v["summary"])
        v = go("bad_downgrade", extra=["--roundtrip-verdict", "FAIL"])
        ok("  --roundtrip-verdict FAIL escalates it to FAIL", v["verdict"] == "FAIL" and step(v, "roundtrip").get("verdict") == "FAIL", v["summary"])

        v = go("long_rev_id")
        ok("negative: revision id > 32 chars (SQLite-invisible) -> FAIL upgrade_empty, NEW in this diff, with the widen shim noted",
           v["verdict"] == "FAIL" and step(v, "upgrade_empty").get("verdict") == "FAIL" and step(v, "upgrade_empty").get("shim") == "widen_version_num", step(v, "upgrade_empty"))
        ok("  and the remaining steps still ran with the shim (drift + roundtrip PASS)", step(v, "drift").get("verdict") == "PASS" and step(v, "roundtrip").get("verdict") == "PASS", v["details"].get("steps"))
        v = run_gate(fx, "long_rev_id", "long_rev_followup")
        ok("standing (pre-existing) long revision id at base -> PASS with a 'standing' note, NOT a FLAG on every later commit; the drift step still runs",
           step(v, "upgrade_empty").get("verdict") == "PASS" and step(v, "upgrade_empty").get("preexisting") is True and step(v, "drift").get("verdict") == "PASS"
           and v["details"].get("standing") == ["upgrade_empty"] and "standing" in v["summary"] and v["verdict"] == "PASS", (v["summary"], v["details"].get("steps")))
        v = run_gate(fx, "bad_upgrade", "bad_upgrade_followup")
        ok("chain already broken at base AND head -> UNVERIFIED (standing), not FLAG/FAIL: this diff cannot be assessed",
           v["verdict"] == "UNVERIFIED" and step(v, "upgrade_empty").get("verdict") == "UNVERIFIED" and step(v, "upgrade_empty").get("preexisting") is True
           and v["details"].get("standing") == ["upgrade_empty"], (v["summary"], v["details"].get("steps")))
        # 2026-10-02 drift baseline: base unbuildable (bad 0002) while an ancestor (dr_c0) builds and already carries the nick drift
        v = run_gate(fx, "dr_base", "dr_fix")
        ok("benign: base unbuildable, head repairs it, only PRE-EXISTING drift (same at ancestor base~1) -> drift PASS with baseline_ancestor=1",
           step(v, "drift").get("verdict") == "PASS" and step(v, "drift").get("baseline_ancestor") == 1 and step(v, "drift").get("preexisting") == 1 and v["verdict"] == "PASS",
           (v["summary"], step(v, "drift")))
        v = run_gate(fx, "dr_base", "dr_fix_newdrift")
        ok("negative: same unbuildable base, head ALSO adds a model column without migration -> drift FLAG (never FAIL on an ancestor baseline), names the new column",
           step(v, "drift").get("verdict") == "FLAG" and "bio" in step(v, "drift").get("msg", "") and step(v, "drift").get("baseline_ancestor") == 1 and v["verdict"] == "FLAG",
           (v["summary"], step(v, "drift")))
        v = run_gate(fx, "dr_base", "dr_fix", envx={"QA_DRIFT_ANCESTOR_TRIES": "0"})
        ok("no buildable baseline at all (ancestor search off) -> drift UNVERIFIED 'cannot attribute' (was a FLAG on ALL head drift), overall UNVERIFIED",
           step(v, "drift").get("verdict") == "UNVERIFIED" and "cannot attribute" in step(v, "drift").get("msg", "") and v["verdict"] == "UNVERIFIED", (v["summary"], step(v, "drift")))

        v = go("shape_unique_dups")
        ok("control: unique-on-nullable-dup column PASSes the EMPTY-db checks (why prod-shape is needed)",
           step(v, "upgrade_empty").get("verdict") == "PASS" and step(v, "drift").get("verdict") == "PASS", v["summary"])
        ok("  and with no stats file the prodshape step is NA (not a silent PASS)", step(v, "prodshape").get("verdict") == "NA", step(v, "prodshape"))
        v = go("shape_unique_dups", extra=["--stats", stats])
        ok("negative: UNIQUE on a column with duplicates in prod-shaped data -> FAIL prodshape",
           v["verdict"] == "FAIL" and step(v, "prodshape").get("verdict") == "FAIL" and "unique" in step(v, "prodshape").get("msg", "").lower(), step(v, "prodshape"))
        v = go("shape_not_null", extra=["--stats", stats])
        ok("negative: SET NOT NULL on a column with nulls in prod-shaped data -> FAIL prodshape",
           v["verdict"] == "FAIL" and step(v, "prodshape").get("verdict") == "FAIL" and "null" in step(v, "prodshape").get("msg", "").lower(), step(v, "prodshape"))
        v = go("shape_narrow_type", extra=["--stats", stats])
        ok("negative: narrowing varchar(50)->(10) over max-length data -> FAIL prodshape",
           v["verdict"] == "FAIL" and step(v, "prodshape").get("verdict") == "FAIL", step(v, "prodshape"))
        v = go("shape_benign_unique_email", extra=["--stats", stats])
        ok("benign: UNIQUE on a genuinely unique column (stats distinct==rows) -> PASS incl. prodshape PASS",
           v["verdict"] == "PASS" and step(v, "prodshape").get("verdict") == "PASS" and step(v, "prodshape").get("rows_loaded") == 200, step(v, "prodshape"))
        v = go("shape_unique_dups", extra=["--prodshape", "stress"])
        ok("--prodshape stress (schema-derived worst case, no stats file) also catches the duplicate-unique migration",
           step(v, "prodshape").get("verdict") == "FAIL" and step(v, "prodshape").get("stats_kind") == "synthetic_stress", step(v, "prodshape"))

        v = go("api_remove_field")
        ok("negative: removed response field -> FLAG (OpenAPI breaking)", v["verdict"] == "FLAG" and step(v, "openapi").get("breaking", [{}])[0].get("kind") == "response-field-removed", v["summary"])
        v = go("api_remove_field", extra=["--breaking-verdict", "FAIL"])
        ok("  --breaking-verdict FAIL escalates the same change to FAIL", v["verdict"] == "FAIL", v["summary"])
        v = go("api_remove_endpoint")
        ok("negative: removed endpoint -> FLAG", v["verdict"] == "FLAG" and any(b["kind"] == "endpoint-removed" for b in step(v, "openapi").get("breaking", [])), v["summary"])
        v = go("api_new_required")
        ok("negative: newly required request field -> FLAG", v["verdict"] == "FLAG" and any(b["kind"] == "request-field-newly-required" for b in step(v, "openapi").get("breaking", [])), v["summary"])
        v = go("api_type_change")
        ok("negative: changed response type -> FLAG", v["verdict"] == "FLAG" and any(b["kind"] == "type-changed" for b in step(v, "openapi").get("breaking", [])), v["summary"])
        v = go("api_additive")
        ok("benign: additive API change (new endpoint + optional response field) -> PASS", v["verdict"] == "PASS" and step(v, "openapi").get("additions", 0) >= 1, v["summary"])
        v = go("app_broken")
        ok("negative: app no longer imports at head (works at base) -> FAIL", v["verdict"] == "FAIL" and step(v, "openapi").get("verdict") == "FAIL", v["summary"])
        ok("  scrubbed environment: gate/repo output never contains the url password", "postgres:qa@" not in json.dumps(v))

        # base already broken -> cannot attribute -> UNVERIFIED, never FAIL
        sh(["git", "checkout", "-q", "-b", "broken2", "app_broken"], fx["fx"])
        with open(os.path.join(fx["fx"], "backend/app/models.py"), "a") as f:
            f.write("\n# touch\n")
        sh(["git", "add", "backend/app/models.py"], fx["fx"])
        sh(["git", "commit", "-q", "-m", "touch on broken base"], fx["fx"])
        sh(["git", "checkout", "-q", "main"], fx["fx"])
        v = run_gate(fx, "app_broken", "broken2")
        ok("repo code already unimportable at base AND head -> openapi UNVERIFIED (not FAIL)", step(v, "openapi").get("verdict") == "UNVERIFIED" and v["verdict"] != "FAIL", v["summary"])

        # timeout: a 1s budget cannot finish => UNVERIFIED (never PASS/FAIL), and still cleans up
        v = go("benign_add_column", extra=["--budget", "1"])
        ok("budget exhausted -> UNVERIFIED (never PASS, never FAIL)", v["verdict"] == "UNVERIFIED", v["summary"])

        # shadow log + exit code contract
        v = go("benign_add_column", record=True)
        logp = os.path.join(fx["ovn"], "state", "qa_shadow", "migrations.jsonl")
        ok("shadow mode records one JSON line to state/qa_shadow/migrations.jsonl", os.path.exists(logp) and len(open(logp).read().strip().splitlines()) == 1)
        env = {"PATH": "/usr/bin:/bin:" + docker_dir(), "HOME": work, "OVN_DIR": fx["ovn"], "OVN_REPOS_DIR": fx["repos"], "QA_REPOS_JSON": fx["reg"],
               "OVN_QA_MIGRATIONS": "enforce", "NTFY_SERVER": "http://127.0.0.1:9"}
        r = subprocess.run(["env", "-i"] + ["%s=%s" % kv for kv in env.items()] + [sys.executable, GATE, "check", "--repo", "fx", "--base", "main", "--head", "bad_upgrade", "--no-record", "--enforce-exit"],
                           capture_output=True, text=True, timeout=600)
        ok("enforce mode + --enforce-exit + FAIL -> exit code 1", r.returncode == 1, r.returncode)
        r = subprocess.run(["env", "-i"] + ["%s=%s" % kv for kv in env.items()] + [sys.executable, GATE, "check", "--repo", "fx", "--base", "main", "--head", "benign_add_column", "--no-record", "--enforce-exit"],
                           capture_output=True, text=True, timeout=600)
        ok("enforce mode + PASS -> exit code 0", r.returncode == 0, r.returncode)

        # container cleanup: nothing leaked by any scenario above
        ok("no qa-pg-* container leaked by any scenario", set(leaked()) <= before, set(leaked()) - before)

        # SIGKILL a running gate mid-flight; the next gate run must reap its orphaned container
        # 2026-10-02: a SIGKILLed gate cannot run its worktree cleanup; its qa-wt-* dir used to land in /tmp and stay there after EVERY run of this
        # test (found on the box: 5 stale dirs). Give the killed gates a TMPDIR inside `work` so the final rmtree takes the leftovers with it.
        os.makedirs(os.path.join(work, "tmp"), exist_ok=True)
        env = {"PATH": "/usr/bin:/bin:" + docker_dir(), "HOME": work, "OVN_DIR": fx["ovn"], "OVN_REPOS_DIR": fx["repos"], "QA_REPOS_JSON": fx["reg"], "NTFY_SERVER": "http://127.0.0.1:9",
               "TMPDIR": os.path.join(work, "tmp")}
        p = subprocess.Popen(["env", "-i"] + ["%s=%s" % kv for kv in env.items()] + [sys.executable, GATE, "check", "--repo", "fx", "--base", "main", "--head", "benign_add_column", "--no-record"],
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
        seen = False
        for _ in range(60):
            time.sleep(0.5)
            if set(leaked()) - before:
                seen = True
                break
        # kill the whole process group (the env -i exec'd python is the same pid as p)
        try:
            os.killpg(p.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        p.wait()
        orphan = set(leaked()) - before
        ok("SIGKILL mid-run leaves an orphan container (the case the reaper exists for)", seen and bool(orphan), orphan)
        v = go("benign_add_column")
        ok("next gate run reaps the orphan (no leftover qa-pg-* containers)", set(leaked()) <= before and v["verdict"] == "PASS", (set(leaked()) - before, v["summary"]))

        # SIGTERM: finally-block cleanup
        p = subprocess.Popen(["env", "-i"] + ["%s=%s" % kv for kv in env.items()] + [sys.executable, GATE, "check", "--repo", "fx", "--base", "main", "--head", "benign_add_column", "--no-record"],
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        for _ in range(60):
            time.sleep(0.5)
            if set(leaked()) - before:
                break
        p.send_signal(signal.SIGTERM)
        p.wait(timeout=120)
        time.sleep(2)
        ok("SIGTERM mid-run still removes the container (finally/trap)", set(leaked()) <= before, set(leaked()) - before)

        part2_collect(work)
    finally:
        shutil.rmtree(work, ignore_errors=True)
        subprocess.run(["docker", "rm", "-f"] + [n for n in leaked() if n.startswith("qa-pg-") and False], capture_output=True)


def part2_collect(work):
    print("== prodshape collect against a local container (read-only, statistics only)")
    import gate_migrations as g
    import prodshape as ps
    pg = g.PgContainer()
    pg.name = "qa-pg-%d" % os.getpid()
    try:
        pg.start(timeout=120)
        rc, _, err = pg.psql("postgres", """CREATE TABLE people (id serial PRIMARY KEY, email text NOT NULL, note varchar(40), age int);
            INSERT INTO people (email, note, age) SELECT 'canary-pii-' || i || '@secret.example', CASE WHEN i % 4 = 0 THEN NULL ELSE 'note-CANARY-' || (i % 5) END, CASE WHEN i % 2 = 0 THEN NULL ELSE 30 + i % 3 END FROM generate_series(1, 100) i;
            CREATE TABLE empty_t (id int);""")
        ok("collect fixture seeded in a local container", rc == 0, err)
        url = pg.url("postgres", "postgresql")
        out = os.path.join(work, "collected.stats.json")
        env = dict(os.environ, QA_STATS_DATABASE_URL=url)
        r = subprocess.run([sys.executable, os.path.join(QA, "prodshape.py"), "collect", "--repo", "demo", "--out", out], capture_output=True, text=True, env=env, timeout=300)
        ok("collect succeeds against a local postgres", r.returncode == 0 and os.path.exists(out), r.stdout + r.stderr)
        if os.path.exists(out):
            raw = open(out).read()
            st = json.loads(raw)
            ok("collect output contains NO row contents (canary strings absent)", "canary" not in raw.lower() and "secret.example" not in raw and "CANARY" not in raw)
            p_ = st["tables"]["people"]
            ok("collect row count correct", p_["rows"] == 100, p_["rows"])
            ok("collect null fraction correct (note 25%, age 50%)", abs(p_["columns"]["note"]["null_frac"] - 0.25) < 1e-6 and abs(p_["columns"]["age"]["null_frac"] - 0.5) < 1e-6, p_["columns"])
            ok("collect distinct + duplicate counts (email unique, note 5 distinct)", p_["columns"]["email"]["distinct"] == 100 and p_["columns"]["email"]["dup_count"] == 0 and p_["columns"]["note"]["distinct"] == 5, p_["columns"])
            ok("collect max text length recorded for text columns only", p_["columns"]["email"]["max_len"] > 20 and p_["columns"]["age"]["max_len"] is None, p_["columns"])
            ok("collect handles an empty table", st["tables"]["empty_t"]["rows"] == 0)
            ok("collected stats file is accepted by load_stats", len(ps.load_stats(out)["tables"]) == 2)
            ok("stats url never printed", url not in r.stdout + r.stderr and "postgres:qa" not in r.stdout + r.stderr)
        # read-only enforcement: the same connection settings must refuse writes
        e, _ = ps._libpq_env(url)
        run = ps._psql_runner(e)
        rc, o, err = run("INSERT INTO people (email) VALUES ('x');")
        ok("the collect connection is READ-ONLY (INSERT refused by the server)", rc != 0 and "read-only" in err.lower(), err[-200:])
        rc, o, err = run("BEGIN READ ONLY; CREATE TABLE zz (a int); ROLLBACK;")
        ok("the collect connection refuses DDL as well", rc != 0 and "read-only" in err.lower(), err[-200:])
        # refuse when the connection is not read-only: a role/db without the option can't be forced here, so assert the guard text path
        src = open(os.path.join(QA, "prodshape.py")).read()
        ok("collect aborts before any query unless SHOW transaction_read_only = on", "connection is not read-only" in src and 'SHOW transaction_read_only' in src)
        # prodshape.load_into -> real load into the same server (round trip of the generator against a real schema)
        pg.create_db("shape_t")
        pg.psql("shape_t", "CREATE TYPE mood AS ENUM ('happy','sad'); CREATE TABLE parent (id serial PRIMARY KEY, code varchar(12) NOT NULL, tag text, m mood NOT NULL DEFAULT 'happy', meta jsonb, ts timestamptz, ok boolean NOT NULL DEFAULT false);"
                "CREATE TABLE child (id serial PRIMARY KEY, parent_id int NOT NULL REFERENCES parent(id), label varchar(8), uid uuid, n numeric(10,2), arr text[]);")
        schema = ps.schema_introspect(lambda sql: pg.psql("shape_t", sql)[1])
        stats = {"tables": {"parent": {"rows": 120, "columns": {"code": {"null_frac": 0, "distinct": 120, "max_len": 12}, "tag": {"null_frac": 0.5, "distinct": 10, "max_len": 300}}},
                            "child": {"rows": 400, "columns": {"label": {"null_frac": 0.1, "distinct": 7, "max_len": 8}}}}}
        rep = ps.load_into(lambda sql: pg.psql("shape_t", sql), schema, stats)
        ok("load_into loads parent+child incl. enum/jsonb/uuid/array/numeric columns without errors", set(rep["loaded"]) == {"parent", "child"} and not rep["failed"], rep)
        rc, o, _ = pg.psql("shape_t", "SELECT (SELECT count(*) FROM parent), (SELECT count(*) FROM child), (SELECT count(*) FROM parent WHERE tag IS NULL), (SELECT count(DISTINCT label) FROM child), (SELECT count(*) FROM child c LEFT JOIN parent p ON p.id=c.parent_id WHERE p.id IS NULL), (SELECT max(length(tag)) FROM parent);")
        vals = o.strip().split(ps.SEP)
        ok("loaded counts match stats (120 parents, 400 children)", vals[0] == "120" and vals[1] == "400", vals)
        ok("loaded null fraction ~50% for parent.tag", 50 <= int(vals[2]) <= 70, vals)
        ok("loaded distinct count honoured for child.label (7)", vals[3] == "7", vals)
        ok("loaded FKs are valid (0 orphans)", vals[4] == "0", vals)
        ok("loaded max text length honoured (300)", vals[5] == "300", vals)
        rc, o, _ = pg.psql("shape_t", "INSERT INTO parent (code) VALUES ('after-load') RETURNING id;")
        ok("serial sequences advanced past loaded ids (next insert succeeds)", rc == 0, o)
    finally:
        pg.stop()


def main():
    part1()
    part2()
    print("\nqa_migrations tests: %d passed, %d failed, %d skipped" % (len(PASSED), len(FAILED), len(SKIPPED)))
    if FAILED:
        print("FAILED: " + "; ".join(FAILED))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
