#!/usr/bin/env python3
"""gate_migrations.py - S6: Postgres migration + OpenAPI gate (see qa/gate_migrations.README.md, docs/QA_GATES_SPEC.md).

    python3 qa/gate_migrations.py check --repo <name> --base <ref> --head <ref>
            [--no-record] [--enforce-exit] [--prodshape auto|off|stress] [--stats FILE] [--no-openapi]
            [--breaking-verdict FLAG|FAIL] [--roundtrip-verdict FLAG|FAIL] [--budget SECONDS]

Against a throwaway postgres:16 container (random localhost port, tmpfs, name qa-pg-<pid>, ALWAYS removed) it checks, for the
HEAD ref of a repo that has alembic:
  1. `alembic upgrade head` on an EMPTY database                         (FAIL if it breaks and base did not)
  2. model/DB drift: alembic-check equivalent with compare_type + compare_server_default   (FAIL on NEW drift vs base)
  3. downgrade -1 / upgrade head round trip, when the diff adds a migration  (FLAG by default: a broken downgrade does not break a
     deploy; --roundtrip-verdict FAIL escalates)
  4. multiple heads
  5. prod-shaped data (qa/prodshape.py): stats-driven synthetic rows loaded at the BASE schema, then HEAD migrations run on top
  6. OpenAPI diff base -> head: removed path/method, removed/newly-required request field, removed response field/status,
     changed type = BREAKING (FLAG by default, --breaking-verdict FAIL to escalate); additions PASS.
Verdict rules: any step FAIL -> FAIL; else any FLAG -> FLAG; else any UNVERIFIED -> UNVERIFIED (never PASS on partial evidence);
else PASS. Infra problems (no docker, timeout, repo env cannot import) are UNVERIFIED, never FAIL. Backend code runs ONLY via
qa/_migr_helper.py with the repo's own venv, inside a detached git worktree, with a scrubbed environment (no ambient secrets).
"""
import atexit
import contextlib
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import qa_common as qc  # noqa: E402
import prodshape as ps  # noqa: E402

GATE = "migrations"
HELPER = os.path.join(HERE, "_migr_helper.py")
IMAGE = os.environ.get("QA_PG_IMAGE", "postgres:16")
SEP = "\x1f"

DRIFT_ANCESTOR_TRIES = int(os.environ.get("QA_DRIFT_ANCESTOR_TRIES", "5"))   # how far back to look for a buildable baseline (0 = base only)

FAIL_OPS = {"add_table", "remove_table", "add_column", "remove_column", "modify_type", "modify_nullable", "add_constraint",
            "remove_constraint", "add_fk", "remove_fk"}


# ------------------------------------------------------------------------------------------------ small helpers

def repos_config():
    path = os.environ.get("QA_REPOS_JSON") or os.path.join(HERE, "qa_repos.json")
    with open(path) as f:
        return json.load(f)


_URL_RE = re.compile(r"(://)[^@/\s]+@")


def scrub(text, limit=300):
    text = _URL_RE.sub(r"\1***@", text or "")
    text = re.sub(r"\s+", " ", text).strip()
    return text[-limit:] if len(text) > limit else text


def last_json(out):
    for line in reversed((out or "").strip().splitlines()):
        line = line.strip()
        if line.startswith("{"):
            try:
                return json.loads(line)
            except ValueError:
                continue
    return None


def clean_env(extra=None):
    """A scrubbed environment for running repo code: no ambient secrets, no ~/.env, no network credentials."""
    e = {"PATH": "/usr/bin:/bin:/usr/local/bin", "HOME": tempfile.gettempdir(), "LANG": "C.UTF-8",
         "PYTHONDONTWRITEBYTECODE": "1", "PYTHONUNBUFFERED": "1", "NO_PROXY": "*", "HTTP_PROXY": "http://127.0.0.1:9",
         "HTTPS_PROXY": "http://127.0.0.1:9"}
    e.update(extra or {})
    return e


def run_clean(cmd, cwd, env, timeout):
    """Like qa_common.run but with a REPLACED (not merged) environment. Local helper (qa_common.run merges os.environ)."""
    try:
        p = subprocess.run(qc.cpu_prefix() + list(cmd), cwd=cwd, env=env, capture_output=True, timeout=timeout)
        return p.returncode, p.stdout.decode("utf-8", "replace"), p.stderr.decode("utf-8", "replace")
    except subprocess.TimeoutExpired as ex:
        return 124, (ex.stdout or b"").decode("utf-8", "replace"), "timeout after %ss" % timeout
    except FileNotFoundError as ex:
        return 127, "", str(ex)


# ------------------------------------------------------------------------------------------------ postgres container

class PgContainer:
    def __init__(self):
        self.name = "qa-pg-%d" % os.getpid()
        self.port = None
        self.started = False

    @staticmethod
    def docker_ok():
        rc, _, _ = qc.run(["docker", "info", "--format", "{{.ServerVersion}}"], timeout=25, polite=False)
        return rc == 0

    @staticmethod
    def reap_stale():
        """Remove qa-pg-<pid> containers whose owning process is gone (e.g. the gate was SIGKILLed)."""
        rc, out, _ = qc.run(["docker", "ps", "-a", "--filter", "name=qa-pg-", "--format", "{{.Names}}"], timeout=20, polite=False)
        if rc != 0:
            return
        for nm in out.split():
            m = re.fullmatch(r"qa-pg-(\d+)", nm)
            if not m or int(m.group(1)) == os.getpid():
                continue
            try:
                os.kill(int(m.group(1)), 0)
            except ProcessLookupError:
                qc.run(["docker", "rm", "-f", nm], timeout=30, polite=False)
            except PermissionError:
                pass

    def start(self, timeout=120):
        self.reap_stale()
        self.started = True  # set first: even a half-started container must be removed
        rc, _, err = qc.run(["docker", "run", "-d", "--rm", "--name", self.name, "--label", "qa-gate=migrations",
                             "-e", "POSTGRES_PASSWORD=qa", "-p", "127.0.0.1::5432", "--tmpfs", "/var/lib/postgresql/data:rw",
                             "--memory", "2g", "--cpus", "2", IMAGE, "-c", "fsync=off", "-c", "synchronous_commit=off",
                             "-c", "full_page_writes=off", "-c", "max_connections=50"], timeout=timeout, polite=False)
        if rc != 0:
            raise RuntimeError("docker run failed: " + scrub(err))
        t0 = time.time()
        while time.time() - t0 < timeout:
            rc, out, _ = qc.run(["docker", "port", self.name, "5432/tcp"], timeout=15, polite=False)
            m = re.search(r":(\d+)\s*$", out.strip().splitlines()[0]) if rc == 0 and out.strip() else None
            if m:
                self.port = int(m.group(1))
                rc2, _, _ = qc.run(["docker", "exec", self.name, "pg_isready", "-h", "127.0.0.1", "-U", "postgres"], timeout=15, polite=False)
                if rc2 == 0:
                    # initdb's temp server has no TCP; a TCP-ready server is the real one. Confirm it answers a query.
                    rc3, o3, _ = self.psql("postgres", "SELECT 1;", timeout=20)
                    if rc3 == 0 and o3.strip() == "1":
                        return
            time.sleep(0.5)
        raise RuntimeError("postgres container did not become ready in %ds" % timeout)

    def psql(self, db, sql, timeout=120):
        rc, out, err = qc.run(["docker", "exec", "-i", self.name, "psql", "-U", "postgres", "-d", db, "-X", "-A", "-t", "-F", SEP,
                               "-v", "ON_ERROR_STOP=1", "-q"], timeout=timeout, polite=False, input_text=sql)
        return rc, out, err

    def create_db(self, db):
        rc, _, err = self.psql("postgres", 'CREATE DATABASE "%s";' % db, timeout=60)
        if rc != 0:
            raise RuntimeError("create database failed: " + scrub(err))

    def url(self, db, scheme):
        return "%s://postgres:qa@127.0.0.1:%d/%s" % (scheme, self.port, db)

    def stop(self):
        if self.started:
            qc.run(["docker", "rm", "-f", self.name], timeout=60, polite=False)
            self.started = False


# ------------------------------------------------------------------------------------------------ repo checkout + helper

class Checkout:
    """A detached worktree of one ref with the clone's venv symlinked in (never committed; removed with the worktree)."""

    def __init__(self, path, cfg, ref):
        self.path, self.cfg, self.ref = path, cfg, ref
        self.backend = os.path.join(path, cfg["backend_dir"])
        self.venv_py = os.path.join(self.backend, cfg.get("venv", ".venv"), "bin", "python")

    def run_helper(self, sub, db_url=None, timeout=240, extra_env=None):
        env = dict(self.cfg.get("env") or {})
        env.update(extra_env or {})
        if db_url:
            env["DATABASE_URL"] = db_url
        if self.cfg.get("openapi", {}).get("module"):
            env["QA_OPENAPI_MODULE"] = self.cfg["openapi"]["module"]
        rc, out, err = run_clean([self.venv_py, HELPER] + list(sub), self.backend, clean_env(env), timeout)
        res = last_json(out)
        return rc, res, scrub((err or "") + "\n" + (out or ""), 4000)


def classify(rc, res, text):
    """-> (kind, message). kinds: ok | timeout | infra | db | app"""
    if rc == 0 and res is not None and not res.get("error"):
        return "ok", ""
    if rc == 124:
        return "timeout", "timeout"
    if rc == 127:
        return "infra", "interpreter missing: " + text[-120:]
    err = (res or {}).get("error") or ""
    low = (text + " " + err).lower()
    if re.search(r"could not connect|connection refused|connection to server|server closed the connection|the database system is", low):
        return "infra", scrub(err or text, 200)
    if re.search(r"sqlalchemy\.exc\.|psycopg2\.errors|asyncpg\.exceptions|alembic\.util\.exc|alembic\.script\.revision|multiple head", low) \
            or re.search(r"\b(dataerror|programmingerror|integrityerror|internalerror|notsupportederror|commanderror|multipleheads|"
                         r"duplicateobject|duplicatetable|undefinedcolumn|undefinedtable)\b", low):
        return "db", scrub(err or text, 300)
    return "app", scrub(err or text, 300)


# ------------------------------------------------------------------------------------------------ OpenAPI diff

def _resolve(spec, node, depth=0):
    seen = 0
    while isinstance(node, dict) and "$ref" in node and seen < 20:
        ref = node["$ref"]
        cur = spec
        for part in ref.lstrip("#/").split("/"):
            cur = cur.get(part, {}) if isinstance(cur, dict) else {}
        node, seen = cur, seen + 1
    if isinstance(node, dict) and "allOf" in node:
        merged = {k: v for k, v in node.items() if k != "allOf"}
        props, req = dict(merged.get("properties") or {}), list(merged.get("required") or [])
        for sub in node["allOf"]:
            sub = _resolve(spec, sub, depth + 1)
            props.update(sub.get("properties") or {})
            req += sub.get("required") or []
            for k in ("type", "enum", "items"):
                if k in sub and k not in merged:
                    merged[k] = sub[k]
        if props:
            merged["properties"] = props
        if req:
            merged["required"] = sorted(set(req))
        return merged
    return node if isinstance(node, dict) else {}


def _alts(spec, s):
    """-> (nullable, [non-null alternatives]) for anyOf/oneOf; a plain schema is one alternative."""
    s = _resolve(spec, s)
    for key in ("anyOf", "oneOf"):
        if key in s:
            alts = [_resolve(spec, a) for a in s[key]]
            nullable = any(a.get("type") == "null" for a in alts)
            return nullable, [a for a in alts if a.get("type") != "null"]
    t = s.get("type")
    if isinstance(t, list):
        return "null" in t, [dict(s, type=x) for x in t if x != "null"]
    return bool(s.get("nullable")) or t == "null", ([s] if t != "null" else [])


def _tsig(s):
    return s.get("type") or ("object" if s.get("properties") else "any")


def _type_ok(old_t, new_t, direction):
    if old_t == new_t or "any" in (old_t, new_t):
        return True
    if direction == "req":      # new must accept everything old accepted
        return old_t == "integer" and new_t == "number"
    return old_t == "number" and new_t == "integer"   # response: new must be a subset of old


def _cmp_schema(ospec, nspec, o, n, where, direction, out, seen=None, depth=0):
    seen = set() if seen is None else seen
    if depth > 10:
        return
    ro, rn = _resolve(ospec, o), _resolve(nspec, n)
    key = (where.count("."), id(o), id(n))
    onull, oalts = _alts(ospec, o)
    nnull, nalts = _alts(nspec, n)
    if direction == "req" and onull and not nnull:
        out.append(("narrowed-nullable", where, "no longer accepts null"))
    if direction == "res" and nnull and not onull:
        out.append(("response-became-nullable", where, "may now be null"))
    if len(oalts) != 1 or len(nalts) != 1:
        osig, nsig = sorted(_tsig(a) for a in oalts), sorted(_tsig(a) for a in nalts)
        if osig != nsig:
            bad = (set(osig) - set(nsig)) if direction == "req" else (set(nsig) - set(osig))
            if bad:
                out.append(("type-changed", where, "%s -> %s" % ("|".join(osig), "|".join(nsig))))
        return
    ro, rn = oalts[0], nalts[0]
    ot, nt = _tsig(ro), _tsig(rn)
    if not _type_ok(ot, nt, direction):
        out.append(("type-changed", where, "%s -> %s" % (ot, nt)))
        return
    if direction == "req" and ro.get("enum") and rn.get("enum"):
        gone = set(map(str, ro["enum"])) - set(map(str, rn["enum"]))
        if gone:
            out.append(("enum-value-removed", where, "removed %s" % sorted(gone)[:5]))
    if nt == "array" or ot == "array":
        if ro.get("items") is not None and rn.get("items") is not None:
            _cmp_schema(ospec, nspec, ro["items"], rn["items"], where + "[]", direction, out, seen, depth + 1)
        return
    op, np_ = ro.get("properties") or {}, rn.get("properties") or {}
    oreq, nreq = set(ro.get("required") or []), set(rn.get("required") or [])
    for p in op:
        if p not in np_:
            out.append(("response-field-removed" if direction == "res" else "request-field-removed", where + "." + p, "removed"))
    for p in np_:
        if direction == "req" and p in nreq and (p not in op or p not in oreq):
            out.append(("request-field-newly-required", where + "." + p, "new required field" if p not in op else "became required"))
    for p in op:
        if p in np_:
            _cmp_schema(ospec, nspec, op[p], np_[p], where + "." + p, direction, out, seen, depth + 1)
    ap_o, ap_n = ro.get("additionalProperties"), rn.get("additionalProperties")
    if isinstance(ap_o, dict) and isinstance(ap_n, dict):
        _cmp_schema(ospec, nspec, ap_o, ap_n, where + ".*", direction, out, seen, depth + 1)


def _json_schema(spec, content):
    if not isinstance(content, dict):
        return None
    for ct in ("application/json", "application/*+json"):
        if ct in content:
            return content[ct].get("schema")
    for ct, v in content.items():
        if "json" in ct:
            return v.get("schema")
    return None


_METHODS = ("get", "put", "post", "delete", "patch", "options", "head")


def openapi_diff(old, new):
    """-> (breaking [dict], additions int). Pure function, unit-tested."""
    out, additions = [], 0
    opaths, npaths = old.get("paths", {}), new.get("paths", {})
    for path, oitem in opaths.items():
        nitem = npaths.get(path)
        for m in _METHODS:
            if m not in oitem:
                continue
            op_id = "%s %s" % (m.upper(), path)
            if nitem is None or m not in nitem:
                out.append(("endpoint-removed", op_id, "deprecated" if oitem[m].get("deprecated") else "removed"))
                continue
            oo, no = oitem[m], nitem[m]
            oparams = {(p.get("in"), p.get("name")): _resolve(old, p) for p in (oitem.get("parameters", []) + oo.get("parameters", []))}
            nparams = {(p.get("in"), p.get("name")): _resolve(new, p) for p in (nitem.get("parameters", []) + no.get("parameters", []))}
            for k, p in nparams.items():
                if k not in oparams and p.get("required"):
                    out.append(("request-param-newly-required", "%s param %s" % (op_id, k[1]), "new required %s parameter" % k[0]))
                elif k in oparams:
                    if p.get("required") and not oparams[k].get("required"):
                        out.append(("request-param-newly-required", "%s param %s" % (op_id, k[1]), "became required"))
                    _cmp_schema(old, new, oparams[k].get("schema", {}), p.get("schema", {}), "%s param %s" % (op_id, k[1]), "req", out)
            additions += sum(1 for k in nparams if k not in oparams)
            orb, nrb = _resolve(old, oo.get("requestBody", {})), _resolve(new, no.get("requestBody", {}))
            if nrb and nrb.get("required") and not (orb and orb.get("required")):
                out.append(("request-body-newly-required", op_id, "request body became required"))
            os_, ns_ = _json_schema(old, orb.get("content")), _json_schema(new, nrb.get("content"))
            if os_ is not None and ns_ is not None:
                _cmp_schema(old, new, os_, ns_, op_id + " body", "req", out)
            for code, ores in oo.get("responses", {}).items():
                nres = no.get("responses", {}).get(code)
                if nres is None:
                    if code.startswith(("2", "3")):
                        out.append(("response-status-removed", "%s -> %s" % (op_id, code), "status removed"))
                    continue
                os2, ns2 = _json_schema(old, _resolve(old, ores).get("content")), _json_schema(new, _resolve(new, nres).get("content"))
                if os2 is not None and ns2 is not None:
                    _cmp_schema(old, new, os2, ns2, "%s -> %s" % (op_id, code), "res", out)
                elif os2 is not None and ns2 is None and code.startswith("2"):
                    out.append(("response-body-removed", "%s -> %s" % (op_id, code), "response body removed"))
            additions += sum(1 for code in no.get("responses", {}) if code not in oo.get("responses", {}))
        if nitem:
            additions += sum(1 for m in _METHODS if m in nitem and m not in oitem)
    additions += sum(1 for p in npaths if p not in opaths)
    return [{"kind": k, "where": w, "detail": d} for (k, w, d) in out], additions


# ------------------------------------------------------------------------------------------------ the gate

class Steps:
    def __init__(self):
        self.items = []

    def add(self, step, v, msg="", **extra):
        d = {"step": step, "verdict": v, "msg": msg[:300]}
        d.update(extra)
        self.items.append(d)
        return d


def default_budget():
    """Total seconds the gate may spend. 2026-10-02: the shadow runner SIGKILLs the whole process group at QA_GATE_TIMEOUT (default 900),
    and the old default budget (900) was equal to it - so a slow run was killed with NO verdict (and an orphaned container) instead of
    reaching its own UNVERIFIED path. Stay 120s under the runner's cap so the gate always gets to answer and clean up."""
    try:
        if os.environ.get("QA_MIGR_BUDGET"):
            return int(os.environ["QA_MIGR_BUDGET"])
        cap = int(os.environ.get("QA_GATE_TIMEOUT", "900"))
    except ValueError:
        cap = 900
    return max(60, cap - 120)


def parse_args(argv):
    o = {"repo": None, "base": None, "head": None, "prodshape": "auto", "stats": None, "openapi": True,
         "breaking": "FLAG", "roundtrip": "FLAG", "budget": default_budget()}
    i = 0
    if argv and argv[0] == "check":
        i = 1
    while i < len(argv):
        a = argv[i]
        if a == "--no-openapi":
            o["openapi"] = False
        elif a == "--no-record":
            pass
        elif a in ("--repo", "--base", "--head", "--prodshape", "--stats", "--budget", "--breaking-verdict", "--roundtrip-verdict") and i + 1 < len(argv):
            k = {"--breaking-verdict": "breaking", "--roundtrip-verdict": "roundtrip"}.get(a, a[2:])
            o[k] = int(argv[i + 1]) if k == "budget" else argv[i + 1]
            i += 1
        i += 1
    return o


def name_status(rd, base, head):
    """[(status, path)] for base..head, or None when git cannot resolve the refs."""
    rc, out, _ = qc.git(rd, "diff", "--name-status", "-M", "%s..%s" % (base, head), timeout=120)
    if rc != 0:
        return None
    res = []
    for line in out.splitlines():
        p = line.split("\t")
        if len(p) >= 2:
            res.append((p[0][0], p[-1]))
    return res


def relevant(files, cfg):
    bd = cfg["backend_dir"].rstrip("/") + "/"
    sl = cfg.get("script_location", "alembic").rstrip("/")
    ver = bd + sl + "/versions/"
    rel, newmig = [], False
    for st, f in files:
        if not f.startswith(bd):
            continue
        sub = f[len(bd):]
        if sub.startswith(("tests/", "htmlcov/", "alembic.backup/", "docs/", "scripts/")) or not sub.endswith((".py", ".ini", ".mako")):
            continue
        rel.append(f)
        if f.startswith(ver) and f.endswith(".py") and st in "AM":
            newmig = True
    return rel, newmig


def worst(verdicts):
    if "FAIL" in verdicts:
        return "FAIL"
    if "FLAG" in verdicts:
        return "FLAG"
    if "UNVERIFIED" in verdicts:
        return "UNVERIFIED"
    return "PASS"


def check(argv):
    o = parse_args(argv)
    t_start = time.time()
    deadline = t_start + o["budget"]
    if not (o["repo"] and o["base"] and o["head"]):
        return qc.verdict("UNVERIFIED", GATE, o["repo"] or "?", o["head"] or "?", "usage: check --repo R --base B --head H")
    repo, ref = o["repo"], o["head"]

    def V(v, summary, details=None):
        return qc.verdict(v, GATE, repo, ref, summary, details)

    # 2026-10-02: every other gate honours its off switch (gate_scanners does); this one did not, so OVN_QA_MIGRATIONS=off / qa_modes.json
    # still started a postgres container per merge.
    if qc.mode(GATE) == "off":
        return V("NA", "gate is off")

    try:
        cfg = repos_config().get(repo)
    except (OSError, ValueError) as ex:
        return V("UNVERIFIED", "qa_repos.json unreadable: %s" % ex)
    if not cfg:
        return V("NA", "repo %s has no alembic backend registered in qa_repos.json" % repo)
    rd = qc.repo_dir(cfg.get("clone", repo))
    if not rd:
        return V("UNVERIFIED", "no clone for %s" % repo)
    files = name_status(rd, o["base"], o["head"])
    if files is None:
        return V("UNVERIFIED", "git cannot diff %s..%s in the clone (unknown ref?)" % (o["base"], o["head"]))
    rel, newmig = relevant(files, cfg)
    if not rel:
        return V("NA", "no backend source/migration change (%d files in diff)" % len(files), {"changed": len(files)})
    if not PgContainer.docker_ok():
        return V("UNVERIFIED", "docker daemon not available - cannot start postgres", {"relevant_files": len(rel)})
    if not os.path.isdir(os.path.join(rd, cfg["backend_dir"], cfg.get("venv", ".venv"))):
        return V("UNVERIFIED", "venv %s/%s missing in clone" % (cfg["backend_dir"], cfg.get("venv", ".venv")))

    steps, timings = Steps(), {}
    pg = PgContainer()
    atexit.register(pg.stop)
    old_term = signal.signal(signal.SIGTERM, lambda *_: (_ for _ in ()).throw(SystemExit(143)))
    scheme = cfg.get("db_scheme", "postgresql+asyncpg")
    try:
        with contextlib.ExitStack() as stack:
            def checkout(r):
                wt = stack.enter_context(qc.worktree(rd, r))
                if not wt:
                    return None
                link = os.path.join(wt, cfg["backend_dir"], cfg.get("venv", ".venv"))
                if not os.path.lexists(link):
                    os.symlink(os.path.join(rd, cfg["backend_dir"], cfg.get("venv", ".venv")), link)
                return Checkout(wt, cfg, r)

            head = checkout(o["head"])
            if head is None:
                return V("UNVERIFIED", "could not create worktree for head %s" % o["head"])
            cache = {}

            def base_co():
                if "b" not in cache:
                    has = qc.git(rd, "rev-parse", "--verify", "-q", o["base"])[0] == 0
                    cache["b"] = checkout(o["base"]) if has else None
                return cache["b"]

            def left():
                return max(0, int(deadline - time.time()))

            def timed(name, fn):
                t0 = time.time()
                try:
                    return fn()
                finally:
                    timings[name] = timings.get(name, 0) + int((time.time() - t0) * 1000)

            t0 = time.time()
            try:
                pg.start(timeout=min(150, max(20, left())))
            except Exception as ex:  # noqa: BLE001
                return V("UNVERIFIED", "postgres container failed to start: %s" % scrub(str(ex), 200))
            timings["container_start"] = int((time.time() - t0) * 1000)
            nameseq = [0]
            pg_last = [None]

            shim = [False]   # True once we learned that alembic_version.version_num must be widened to run the chain at all

            def newdb(tag, widen=None):
                nameseq[0] += 1
                db = "%s_%d" % (tag, nameseq[0])
                pg.create_db(db)
                if shim[0] if widen is None else widen:
                    pg.psql(db, "CREATE TABLE alembic_version (version_num varchar(255) NOT NULL PRIMARY KEY);", timeout=30)
                return db

            def stage(co, sub, db, timeout=240):
                if left() < 3:
                    return "timeout", "time budget exhausted", None
                url = pg.url(db, scheme) if db else pg.url("postgres", scheme)
                rc, res, text = co.run_helper(sub, db_url=url, timeout=min(timeout, left()))
                kind, msg = classify(rc, res, text)
                return kind, msg, res

            # ---- 4. heads (no db)
            def do_heads():
                kind, msg, res = stage(head, ["heads"], None, 90)
                if kind in ("timeout", "infra"):
                    steps.add("heads", "UNVERIFIED", "%s: %s" % (kind, msg))
                    return False
                if kind != "ok":
                    b = base_co()
                    bk = stage(b, ["heads"], None, 90)[0] if b else "n/a"
                    if bk == "ok":
                        steps.add("heads", "FAIL", "alembic cannot load the migration scripts at head but can at base: " + msg)
                    else:
                        steps.add("heads", "UNVERIFIED", "alembic/app import fails at head and base (%s): %s" % (bk, msg))
                    return False
                hs = res.get("heads", [])
                if len(hs) > 1:
                    b = base_co()
                    bres = stage(b, ["heads"], None, 90)[2] if b else None
                    pre = bres is not None and len(bres.get("heads", [])) > 1
                    steps.add("heads", "FLAG" if pre else "FAIL", "multiple heads %s%s" % (hs, " (already at base)" if pre else ""), heads=hs)
                    return False
                steps.add("heads", "PASS", "single head %s" % (hs[0] if hs else "none"))
                return True

            single = timed("heads", do_heads)

            # ---- 1. upgrade on empty db
            ok_upgrade = False
            hdb = None
            if single:
                def do_upgrade():
                    nonlocal hdb
                    hdb = newdb("h_empty")
                    kind, msg, _ = stage(head, ["upgrade", "head"], hdb)
                    if kind == "ok":
                        steps.add("upgrade_empty", "PASS", "alembic upgrade head on empty postgres:16")
                        return True
                    if kind in ("timeout", "infra"):
                        steps.add("upgrade_empty", "UNVERIFIED", "%s: %s" % (kind, msg))
                        return False
                    if kind == "db" and re.search(r"alembic_version", msg) and re.search(r"too long|StringDataRightTruncation", msg):
                        # Postgres-only defect (SQLite ignores varchar length): a revision id > 32 chars cannot be stamped into
                        # alembic.version_num varchar(32). Retry with the column pre-widened so the remaining steps still run.
                        sdb = newdb("h_empty_wide", widen=True)
                        k2, _, _ = stage(head, ["upgrade", "head"], sdb)
                        if k2 == "ok":
                            hdb, shim[0] = sdb, True
                            b = base_co()
                            bk = "n/a"
                            if b is not None:
                                bk = stage(b, ["upgrade", "head"], newdb("b_empty", widen=False))[0]
                            note = ("a revision id is longer than 32 chars, so `alembic upgrade head` cannot stamp alembic_version.version_num "
                                    "varchar(32) on Postgres (SQLite hides this); chain runs only with the column widened. ")
                            if bk == "ok":
                                steps.add("upgrade_empty", "FAIL", "NEW in this diff: " + note, shim="widen_version_num")
                            else:
                                # 2026-10-02: was FLAG on every commit (iptv_apps: 10 of 15 replayed commits flagged for one standing defect
                                # no commit introduced). Attribution is the gate's job: the finding stays visible (summary "standing:" +
                                # details.standing) but only a NEW occurrence (FAIL above) or a failure to run the chain at all moves the verdict.
                                steps.add("upgrade_empty", "PASS", "standing (pre-existing at base, not from this diff): " + note + "Remaining steps ran with the shim.",
                                          shim="widen_version_num", preexisting=True)
                            return True
                    b = base_co()
                    if b is not None:
                        bdb = newdb("b_empty", widen=False)
                        bkind, bmsg, _ = stage(b, ["upgrade", "head"], bdb)
                    else:
                        bkind, bmsg = "n/a", ""
                    if bkind == "ok":
                        steps.add("upgrade_empty", "FAIL", "upgrade head fails at head, passes at base: " + msg, error_kind=kind)
                    elif kind == "app":
                        steps.add("upgrade_empty", "UNVERIFIED", "repo code cannot run here (also fails at base): " + msg)
                    else:
                        # 2026-10-02: was FLAG per commit (test-automation-agent: 8 of 15 replayed commits, one broken chain none of them touched). With
                        # the chain unbuildable at base AND head nothing else about this diff can be checked: say so (UNVERIFIED), keep it as standing.
                        steps.add("upgrade_empty", "UNVERIFIED", "upgrade head already failed at base (standing, not from this diff; the rest of this diff cannot be checked): " + msg, preexisting=True)
                    return False
                ok_upgrade = timed("upgrade_empty", do_upgrade)
            else:
                steps.add("upgrade_empty", "UNVERIFIED", "skipped (heads step did not pass)")

            # ---- 2. drift
            if ok_upgrade:
                def do_drift():
                    kind, msg, res = stage(head, ["diffs"], hdb)
                    if kind != "ok":
                        steps.add("drift", "UNVERIFIED", "alembic compare failed to run: " + msg)
                        return
                    hd = res.get("diffs", [])
                    if not hd:
                        steps.add("drift", "PASS", "no model/DB drift (compare_type+compare_server_default)")
                        return
                    bkeys, bok, bnote, anc = set(), False, "no base ref", 0
                    refs = [o["base"]] + ["%s~%d" % (o["base"], i) for i in range(1, DRIFT_ANCESTOR_TRIES + 1)]
                    for i, r in enumerate(refs):
                        if i == 0:
                            b = base_co()
                        elif left() < 30 or qc.git(rd, "rev-parse", "--verify", "-q", r + "^{commit}")[0] != 0:
                            break
                        else:
                            b = checkout(r)
                        if b is None:
                            continue
                        pg_last[0] = newdb("b_drift")
                        k1, m1, _ = stage(b, ["upgrade", "head"], pg_last[0])
                        bnote = "base%s upgrade %s: %s" % ("" if i == 0 else "~%d" % i, k1, m1[:120])
                        if k1 != "ok":
                            continue
                        k2, m2, bres = stage(b, ["diffs"], pg_last[0])
                        bnote = "base%s diffs %s: %s" % ("" if i == 0 else "~%d" % i, k2, m2[:120])
                        if k2 == "ok":
                            bkeys, bok, anc = {d["key"] for d in bres.get("diffs", [])}, True, i
                            break
                    new = [d for d in hd if d["key"] not in bkeys]
                    pre = len(hd) - len(new)
                    brief = lambda ds: "; ".join("%s %s.%s %s" % (d["op"], d["table"], d["name"], d["detail"][:40]) for d in ds[:3])  # noqa: E731
                    if not bok:
                        # 2026-10-02: was FLAG on ALL head drift (gitlark: ~94 pre-existing UUID-vs-VARCHAR items re-FLAGged 5 of 15 commits whose
                        # base could not be upgraded - every one noise). Drift we cannot attribute to this diff is not a finding: UNVERIFIED.
                        steps.add("drift", "UNVERIFIED", "%d drift items at head but no buildable baseline (base and %d ancestors failed; %s) - cannot attribute to this diff: %s" % (
                            len(hd), DRIFT_ANCESTOR_TRIES, bnote[:80], brief(hd)), diffs=hd[:30], base_note=bnote)
                    elif not new:
                        steps.add("drift", "PASS", "no NEW drift (%d pre-existing drift items at %s)" % (pre, "base" if anc == 0 else "base~%d" % anc), preexisting=pre,
                                  preexisting_sample=[d["key"][:140] for d in hd[:8]], baseline_ancestor=anc)
                    else:
                        hard = [d for d in new if d["op"] in FAIL_OPS]
                        # an ancestor baseline can mis-attribute drift that landed between it and base: never FAIL on it
                        v_ = "FAIL" if (hard and anc == 0) else "FLAG"
                        steps.add("drift", v_,
                                  "%d NEW drift items (%d pre-existing)%s: %s" % (len(new), pre, "" if anc == 0 else " vs baseline base~%d (base itself unbuildable)" % anc, brief(hard or new)),
                                  new=new[:30], preexisting=pre, baseline_ancestor=anc)
                timed("drift", do_drift)

            # ---- 3. downgrade/upgrade round trip (only when the diff adds/changes a migration)
            if ok_upgrade and newmig:
                def do_rt():
                    rtv = o["roundtrip"] if o["roundtrip"] in ("FAIL", "FLAG") else "FLAG"
                    k1, m1, _ = stage(head, ["downgrade", "-1"], hdb)
                    if k1 != "ok":
                        steps.add("roundtrip", "UNVERIFIED" if k1 in ("timeout", "infra") else rtv, "downgrade -1 failed: " + m1)
                        return
                    k2, m2, _ = stage(head, ["upgrade", "head"], hdb)
                    if k2 != "ok":
                        steps.add("roundtrip", "UNVERIFIED" if k2 in ("timeout", "infra") else rtv, "re-upgrade after downgrade failed: " + m2)
                        return
                    steps.add("roundtrip", "PASS", "downgrade -1 then upgrade head round trip")
                timed("roundtrip", do_rt)
            else:
                steps.add("roundtrip", "NA", "no migration file added/changed in this diff" if ok_upgrade else "skipped")

            # ---- 5. prod-shaped data
            mode = o["prodshape"]
            spath = o["stats"] or ps.stats_path(repo)
            if mode != "off" and ok_upgrade and newmig and base_co() is not None and (mode == "stress" or os.path.isfile(spath)):
                def do_shape():
                    b = base_co()
                    sdb = newdb("h_shape")
                    k, m, _ = stage(b, ["upgrade", "head"], sdb)
                    if k != "ok":
                        steps.add("prodshape", "UNVERIFIED", "base schema could not be built for the data load: " + m)
                        return
                    schema = ps.schema_introspect(lambda sql: pg.psql(sdb, sql)[1])
                    if mode == "stress" and not os.path.isfile(spath):
                        stats = ps.synth_stress_stats(schema)
                    else:
                        stats = ps.load_stats(spath)
                    rep = ps.load_into(lambda sql: pg.psql(sdb, sql, timeout=min(300, left()))[0:3], schema, stats)
                    kind, msg, _ = stage(head, ["upgrade", "head"], sdb, 300)
                    info = {"stats_kind": stats.get("kind"), "tables_loaded": len(rep["loaded"]), "tables_failed": rep["failed"],
                            "rows_loaded": rep["rows_loaded"], "capped": rep["capped_tables"][:5]}
                    if kind == "ok":
                        if rep["failed"] or not rep["loaded"]:
                            steps.add("prodshape", "UNVERIFIED", "upgrade passed but only %d/%d tables loaded (%s)" % (
                                len(rep["loaded"]), rep["tables_planned"], "; ".join("%s: %s" % kv for kv in list(rep["failed"].items())[:2])), **info)
                        else:
                            steps.add("prodshape", "PASS", "head migrations ran over %d rows in %d tables (%s stats)" % (
                                rep["rows_loaded"], len(rep["loaded"]), stats.get("kind")), **info)
                    elif kind in ("timeout", "infra"):
                        steps.add("prodshape", "UNVERIFIED", "%s: %s" % (kind, msg), **info)
                    else:
                        v = "FAIL" if rep["loaded"] else "UNVERIFIED"
                        steps.add("prodshape", v, "head migration fails on prod-shaped data (passes on empty DB): " + msg, **info)
                timed("prodshape", do_shape)
            else:
                why = "off" if mode == "off" else ("no migration in diff" if not newmig else "no stats file (use --prodshape stress or prodshape.py collect)")
                steps.add("prodshape", "NA", why)

            # ---- 6. OpenAPI
            if o["openapi"] and cfg.get("openapi"):
                def do_openapi():
                    td = tempfile.mkdtemp(prefix="qa-openapi-")
                    stack.callback(shutil.rmtree, td, True)
                    fh, fb = os.path.join(td, "head.json"), os.path.join(td, "base.json")
                    url = pg.url("postgres", scheme)
                    rc, res, text = head.run_helper(["openapi", fh], db_url=url, timeout=min(150, left()))
                    kh, mh = classify(rc, res, text)
                    b = base_co()
                    if b is None:
                        steps.add("openapi", "UNVERIFIED" if kh != "ok" else "NA", "no base ref to diff against")
                        return
                    rc, res, text = b.run_helper(["openapi", fb], db_url=url, timeout=min(150, left()))
                    kb, mb = classify(rc, res, text)
                    if kb != "ok" and kh != "ok":
                        steps.add("openapi", "UNVERIFIED", "OpenAPI export fails at head and base: " + mh)
                        return
                    if kh != "ok":
                        steps.add("openapi", "FAIL" if kh == "app" else "UNVERIFIED", "app no longer imports/exports OpenAPI at head (works at base): " + mh)
                        return
                    if kb != "ok":
                        steps.add("openapi", "UNVERIFIED", "OpenAPI export fails at base, cannot diff: " + mb)
                        return
                    with open(fh) as f1, open(fb) as f2:
                        new_s, old_s = json.load(f1), json.load(f2)
                    brk, adds = openapi_diff(old_s, new_s)
                    if brk:
                        v = o["breaking"] if o["breaking"] in ("FAIL", "FLAG") else "FLAG"
                        steps.add("openapi", v, "%d BREAKING OpenAPI changes: %s" % (len(brk), "; ".join(
                            "%s %s" % (x["kind"], x["where"]) for x in brk[:3])), breaking=brk[:50], additions=adds)
                    else:
                        steps.add("openapi", "PASS", "no breaking OpenAPI change (%d additive)" % adds, additions=adds,
                                  paths=len(new_s.get("paths", {})))
                timed("openapi", do_openapi)
            else:
                steps.add("openapi", "NA", "disabled or no OpenAPI export configured")
    except SystemExit:
        raise
    except Exception as ex:  # noqa: BLE001
        steps.add("gate", "UNVERIFIED", "%s: %s" % (type(ex).__name__, scrub(str(ex), 200)))
    finally:
        pg.stop()
        with contextlib.suppress(Exception):
            signal.signal(signal.SIGTERM, old_term)

    vs = [s["verdict"] for s in steps.items if s["verdict"] != "NA"]
    v = worst(vs) if vs else "NA"
    bad = [s for s in steps.items if s["verdict"] in ("FAIL", "FLAG")] or [s for s in steps.items if s["verdict"] == "UNVERIFIED"]
    summary = "; ".join("%s: %s" % (s["step"], s["msg"]) for s in bad[:3]) if bad else \
        "evidence found: " + ", ".join("%s=%s" % (s["step"], s["verdict"]) for s in steps.items)
    standing = [s for s in steps.items if s.get("preexisting") is True and s["verdict"] in ("PASS", "UNVERIFIED")]
    if [s for s in standing if s["verdict"] == "PASS"]:
        summary = (summary + " [standing, not from this diff: " + "; ".join("%s: %s" % (s["step"], s["msg"][:120]) for s in standing if s["verdict"] == "PASS") + "]")[:400]
    return qc.verdict(v, GATE, repo, ref, summary, {"steps": steps.items, "standing": [s["step"] for s in standing], "timings_ms": timings, "base": o["base"],
                                                    "relevant_files": len(rel), "new_migration": newmig})


def main(argv=None):
    return qc.main_guard(GATE, check, argv)


if __name__ == "__main__":
    sys.exit(main())
