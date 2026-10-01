#!/usr/bin/env python3
"""Tests for qa/card_lint.py + qa/acceptance_card.py (gate S0).

Runs the REAL entry point exactly as cron would: absolute path AND relative path from scripts/overnight-queue, under `env -i` with a minimal PATH and
NTFY_SERVER set. The model is a loopback fake litellm (no network, never ntfy). Stdlib only (no pytest needed); runs under the Mac python3 and the box
python3.12.
"""
import http.server
import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
QUEUE = os.path.abspath(os.path.join(HERE, "..", ".."))
QA = os.path.join(QUEUE, "qa")
sys.path.insert(0, QA)
import card_lint as cl  # noqa: E402

P = F = 0


def ok(name, cond, extra=""):
    global P, F
    if isinstance(extra, dict) and "summary" in extra:
        extra = "%s: %s | exec=%s" % (extra.get("verdict"), extra.get("summary"), (extra.get("details") or {}).get("exec"))
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name + (("  :: " + str(extra)[:300]) if extra else ""))


T = tempfile.mkdtemp(prefix="qa-acc-test-")
OVN = os.path.join(T, "ovn")
os.makedirs(os.path.join(OVN, "state"))
REPOS = os.path.join(T, "repos")
os.makedirs(REPOS)
SECRET = "sk-TESTSECRET-do-not-print"

# ---------------------------------------------------------------------------------------------------------------- 1. linter (pure)
print("card_lint: verify-command rules")
ROOT = os.path.join(T, "lintroot")
for p in ("backend/app/utils/a.py", "backend/tests/test_a.py", "backend/app/main.py", "backend/app/__init__.py"):
    os.makedirs(os.path.dirname(os.path.join(ROOT, p)), exist_ok=True)
    open(os.path.join(ROOT, p), "w").write("def test_ok():\n    pass\n\ndef existing():\n    return 1\n")


def item(desc, path="backend/app/utils/a.py", cat=None):
    return {"path": path, "desc": desc, "cat": cat, "tier": "T2", "tags": [], "verify": None, "raw": desc}


def rules(verify, it, root=ROOT):
    f, info = cl.lint_verify(verify, it, root)
    return {x["rule"] for x in f if x["severity"] == "error"}, {x["rule"] for x in f if x["severity"] == "flag"}, info


ADD = item("Add `foo(x)` returning x*2 and raising ValueError on negatives")
NEG_CONTROLS = [  # (verify, item, expected error rule)
    ("grep -q foo backend/app/utils/a.py || echo missing", ADD, "swallow-or-handler"),
    ("grep -q foo backend/app/utils/a.py || true", ADD, "swallow-or-handler"),
    ("grep -q foo backend/app/utils/a.py ; true", ADD, "swallow-semicolon"),
    ("grep -q foo backend/app/utils/a.py; echo done", ADD, "swallow-semicolon"),
    ("pytest backend/tests/test_a.py | tail -3", ADD, "swallow-pipe"),
    ("pytest backend/tests/test_a.py | cat", ADD, "swallow-pipe"),
    ("pytest backend/tests/test_a.py && exit 0", ADD, "swallow-exit0"),
    ("pytest backend/tests/test_a.py; exit 0", ADD, "swallow-exit0"),
    ("pytest backend/tests/test_a.py &", ADD, "swallow-background"),
    ("curl -X POST http://localhost:8000/x | jq .status", ADD, "unsafe-command"),
    ("rm -rf backend && grep -q foo backend/app/utils/a.py", ADD, "unsafe-command"),
    ("pytest backend/tests/test_a.py > out.txt", ADD, "unsafe-redirect"),
    ("pytest backend/tests/test_a.py &> out.txt", ADD, "unsafe-redirect"),
    ("`rm -rf x`; grep -q foo backend/app/utils/a.py", ADD, "shell-unparseable"),
    ("grep -q foo \"unterminated backend/app/utils/a.py", ADD, "shell-unparseable"),
    ("if true; then grep -q foo backend/app/utils/a.py; fi", ADD, "shell-compound"),
    ("git push origin develop", ADD, "unsafe-command"),
    ("npm install && npm test", ADD, "unsafe-command"),
    ("python -c \"import os; os.system('id'); assert 1 == 1\"", ADD, "unsafe-command"),
    ("python -c \"open('x','w').write('y'); assert foo(1)\"", ADD, "unsafe-command"),
    ("sed -i s/a/b/ backend/app/utils/a.py && grep -q foo backend/app/utils/a.py", ADD, "unsafe-command"),
    ("mysterytool --check backend/app/utils/a.py", ADD, "unknown-command"),
    ("echo ok", ADD, "no-assertion"),
    ("true", ADD, "no-assertion"),
    ("grep -q foo backend/app/utils/a.py", ADD, "weak-existence"),  # behaviour item verified by existence only
    ("test -e backend/app/utils/a.py", ADD, "existence-only"),
    ("ls backend/app/utils/a.py", ADD, "existence-only"),
    ("cd backend && python -c \"import app.utils.a\"", ADD, "existence-only"),
    ("python -c \"import os; assert os.path.exists('backend/app/utils/a.py')\"", ADD, "existence-only"),
    ("python -m py_compile backend/app/utils/a.py", ADD, "existence-only"),
    ("python -c \"import inspect; from app import main; assert 'foo' in inspect.getsource(main)\"", ADD, "weak-existence"),
    ("python -c \"x = 1; try: assert foo(1)\\nexcept ValueError: pass\"", ADD, "py-syntax"),
    ("cd backend && python -c \"from app.utils.a import foo; class R: pass; assert foo(R())\"", ADD, "py-syntax"),
    ("cd backend && python -m pytest tests/test_a.py::test_ghost -q", ADD, "test-id-missing"),
    ("cd backend && python -c \"from app.config import Settings; assert Settings().x == 1\"", ADD, "import-missing-module"),
    ("cd backend && python -c \"from app.main import zzz_thing; assert zzz_thing(1) == 2\"", ADD, "import-name-missing"),
    ("python -c \"from app.main import existing; assert existing() == 1\"", ADD, "import-wrong-cwd"),
    ("test -e backend/app/utils/a.py", item("Delete the dead file a.py", cat=None), "direction-mismatch"),
    ("grep -q foo backend/app/utils/a.py", item("Remove the hardcoded `foo` from a.py"), "direction-mismatch"),
    ("! grep -q foo backend/app/utils/a.py", ADD, "direction-mismatch"),
    ("test ! -e backend/app/utils/a.py", ADD, "direction-mismatch"),
    ("pytest backend/tests/test_zzz.py", ADD, "path-missing"),
    ("cd backend/nope && pytest tests/test_a.py", ADD, "path-missing"),
    ("grep -q foo backend/app/utils/nothere.py && pytest backend/tests/test_a.py", ADD, "path-missing"),
    ("pytest /etc/passwd", ADD, "path-absolute"),
    ("pytest ../outside/test_a.py", ADD, "path-escape"),
    ("", ADD, "verify-missing"),
    ("cd backend && python -c \"from app.utils.a import foo; assert foo(1) == 2 or True\"", ADD, "py-tautology"),
    ("cd backend && python -c \"from app.utils.a import foo; assert True\"", ADD, "py-tautology"),
    ("grep -q foo backend/app/utils/a.py", item("Create tests for foo", "backend/tests/test_a.py", "test"), "weak-existence"),
    ("cd backend && python -c \"from app.utils.a import foo; assert foo(1) == 2\" <(touch /tmp/PWN_a)", ADD, "unsafe-command"),
    ("cd backend && python -c \"from app.utils.a import foo; assert foo(1) == 2\" >(touch /tmp/PWN_b)", ADD, "unsafe-command"),
    ("awk 'BEGIN{system(\"touch /tmp/PWN_f\")}' /dev/null && grep -q foo backend/app/utils/a.py", ADD, "unsafe-command"),
    ("test \"$(awk 'BEGIN{system(\"touch /tmp/PWN_g\")}')\" = x && grep -q foo backend/app/utils/a.py", ADD, "unsafe-command"),
    ("awk '{print $1 > \"/tmp/PWN_h\"}' backend/app/utils/a.py && grep -q foo backend/app/utils/a.py", ADD, "unsafe-command"),
    ("awk '{print $1 | \"sh\"}' backend/app/utils/a.py && grep -q foo backend/app/utils/a.py", ADD, "unsafe-command"),
    ("awk '{\"id\" | getline x}' backend/app/utils/a.py && grep -q foo backend/app/utils/a.py", ADD, "unsafe-command"),
    ("sed 's/a/b/e' backend/app/utils/a.py && grep -q foo backend/app/utils/a.py", ADD, "unsafe-command"),
    ("sed 's/a/b/w /tmp/PWN_i' backend/app/utils/a.py && grep -q foo backend/app/utils/a.py", ADD, "unsafe-command"),
    ("sed -n '1e touch /tmp/PWN_j' backend/app/utils/a.py && grep -q foo backend/app/utils/a.py", ADD, "unsafe-command"),
    ("sed 'w /tmp/PWN_k' backend/app/utils/a.py && grep -q foo backend/app/utils/a.py", ADD, "unsafe-command"),
    ("sed -f /tmp/script.sed backend/app/utils/a.py && grep -q foo backend/app/utils/a.py", ADD, "unsafe-command"),
    ("sort -o /tmp/PWN_l backend/app/utils/a.py && grep -q foo backend/app/utils/a.py", ADD, "unsafe-command"),
    ("git diff --output=/tmp/PWN_m && grep -q foo backend/app/utils/a.py", ADD, "unsafe-command"),
    ("rg --pre 'touch /tmp/PWN_n' foo backend/app/utils/a.py", ADD, "unsafe-command"),
    ("ruff check --fix backend/app/utils/a.py && grep -q foo backend/app/utils/a.py", ADD, "unsafe-command"),
    ("find backend -fprintf /tmp/PWN_o x && grep -q foo backend/app/utils/a.py", ADD, "unsafe-command"),
]
for v, it, want in NEG_CONTROLS:
    errs, flags, info = rules(v, it)
    if want is None:
        ok("benign: %r passes lint" % v[:60], not errs, errs)
    else:
        ok("negative: %-62r -> %s" % (v[:60], want), want in errs, (errs, flags))

SAFE_FILTERS = [
    "cd backend && test \"$(sed -n '1,5p' app/utils/a.py | wc -l)\" -ge 1 && python -m pytest tests/test_a.py -q",
    "cd backend && test \"$(sed 's/a/b/g' app/utils/a.py | wc -l)\" -ge 1 && python -m pytest tests/test_a.py -q",
    "cd backend && test \"$(awk 'NR>1{print $1}' app/utils/a.py | wc -l)\" -ge 0 && python -m pytest tests/test_a.py -q",
    "cd backend && test \"$(awk '$1 > 5 {print $1}' app/utils/a.py | wc -l)\" -ge 0 && python -m pytest tests/test_a.py -q",
    "cd backend && test \"$(sort -u app/utils/a.py | wc -l)\" -ge 1 && python -m pytest tests/test_a.py -q",
]
for v in SAFE_FILTERS:
    errs, flags, info = rules(v, ADD)
    ok("benign filter use still allowed: %r" % v[16:70], "unsafe-command" not in errs, errs)

BENIGN = [
    ("cd backend && python -m pytest tests/test_a.py -q", ADD),
    ("cd backend && python -m pytest tests/test_a.py::test_ok -q", ADD),
    ("cd backend && python -c \"from app.utils.a import foo; assert foo(2) == 4\"", ADD),
    ("cd backend && python -c \"from app.main import existing; assert existing() == 1\"", ADD),
    ("pytest backend/tests/test_a.py::test_ok -q -k foo", ADD),
    ("set -o pipefail; pytest backend/tests/test_a.py | tail -3", ADD),
    ("test \"$(grep -c foo backend/app/utils/a.py)\" -ge 2 && cd backend && python -c \"from app.utils.a import foo; assert foo(1) == 2\"", ADD),
    ("test ! -e backend/app/utils/a.py", item("Delete the dead file a.py")),
    ("! grep -q 'old_name' backend/app/utils/a.py && grep -q 'new_name' backend/app/utils/a.py", item("Rename `old_name` to `new_name` in a.py")),
    ("grep -q 'TIMEOUT = 30' backend/app/utils/a.py", item("Add constant TIMEOUT = 30 to a.py")),
    ("grep -q foo backend/app/utils/a.py 2>/dev/null && pytest backend/tests/test_a.py -q 2>&1", ADD),
    ("pytest backend/tests/test_new.py::test_x -q", item("Create test_x", "backend/tests/test_new.py", "test")),
    ("test $(grep -c 'existing(' backend/app/utils/a.py) -eq 1", ADD),                       # quote-aware $( ) with a paren inside quotes
    ("! git ls-files backend/app/utils/a.py | grep .", item("Remove the dead module a.py")),    # `! a | b` negates the pipeline
    ("test ! -f backend/app/utils/a.py -a ! -f backend/tests/test_a.py", item("Remove the dead module a.py and its test")),
    ("cd backend && python -c \"import app.utils.a as m; assert 'x' in m.__dict__\"", ADD),
    ("cd backend && python -c \"from app.utils.a import existing\"", item("Re-export `existing` from the package so `from app.utils.a import existing` works")),  # value/membership assertion is a content check
]
for v, it in BENIGN:
    errs, flags, info = rules(v, it)
    ok("benign: %r -> no lint errors" % v[:70], not errs, errs)

# negation inside python -c counts as a negative assertion (direction); hallucinated string literals are flagged
REMOVE = item("Remove the hardcoded `foo_marker` from main.py", "backend/app/main.py")
errs, flags, _ = rules("cd backend && python -c \"import inspect; from app import main; assert 'foo_marker' not in inspect.getsource(main)\"", REMOVE)
ok("benign: a python -c `assert 'x' not in src` satisfies a REMOVE item's direction", "direction-mismatch" not in errs, errs)
errs, flags, _ = rules("cd backend && python -c \"import inspect; from app import main; assert 'foo_marker' in inspect.getsource(main)\"", REMOVE)
ok("negative: a positive python -c assert for a REMOVE item -> direction-mismatch", "direction-mismatch" in errs, errs)
errs, flags, _ = rules("cd backend && python -c \"from app.main import existing; assert 'RateLimiterZZ' in str(existing)\"", ADD)
ok("negative: asserting on an identifier-like literal that is in neither the item nor the repo -> FLAG literal-not-in-repo", "literal-not-in-repo" in flags, (errs, flags))
errs, flags, _ = rules("cd backend && python -c \"from app.main import existing; assert 'existing' in str(existing)\"", ADD)
ok("benign: a literal that exists in the repo is not flagged", "literal-not-in-repo" not in flags, (errs, flags))

errs, flags, _ = rules("cd backend && python -m pytest tests/test_a.py -q -k test_nonexistent_thing", ADD)
ok("negative: pytest -k term that matches no test in the named file -> test-selector-missing", "test-selector-missing" in errs, (errs, flags))
errs, flags, _ = rules("cd backend && python -m pytest tests/test_a.py -q -k test_ok", ADD)
ok("benign: pytest -k term that exists in the named file", "test-selector-missing" not in errs, errs)
SVC = item("Add `thing(x)` returning x+1 to the service", "backend/app/services/billing.py")
errs, flags, _ = rules("cd backend && python -c \"from app.models.billing import thing; assert thing(1) == 2\"", SVC)
ok("negative: verify touches a DIFFERENT module that merely shares the stem -> FLAG verify-unrelated", "verify-unrelated" in flags, (errs, flags))
ok("a model named test_run.py is not misclassified as a test file", cl.classify_item(item("Add columns `a` and `b` to the `TestRun` model", "backend/app/models/test_run.py"))["kind"] != "test")
REFAC = item("Refactor `enforce_quota` to read the tier from the DB", "backend/app/utils/a.py")
errs, flags, _ = rules("cd backend && python -c \"import inspect; from app.utils import a; assert 'tier' not in inspect.getsource(a)\"", REFAC)
ok("a refactor verified by a removal-only check is a FLAG (not an error); an ADD item verified that way is an error",
   "direction-mismatch" in flags and "direction-mismatch" not in errs and "direction-mismatch" in rules("cd backend && python -c \"import inspect; from app.utils import a; assert 'foo' not in inspect.getsource(a)\"", ADD)[0])

errs, flags, _ = rules("grep -q 'new_name' backend/app/utils/a.py && ! grep -q 'old_name' backend/app/utils/a.py", item("Update `thing` to call `new_name` instead of the old helper"))
ok("a mechanical edit verified by positive+negative grep is a FLAG (not an error)", "weak-existence" not in errs and "weak-existence" in flags, (errs, flags))
ok("audit items ('Confirm/Verify/Audit ...') have nothing to verify", cl.classify_item(item("Confirm line 99 still uses `role_at_least`"))["kind"] == "nochange")

print("card_lint: bullets, schema, risk, item model")
GOOD = {"bullets": ["`foo(2)` returns 4", "`foo(-1)` raises ValueError", "`foo` is importable from `app.utils.a`"],
        "verify_cmd": "cd backend && python -m pytest tests/test_a.py -q", "files": ["backend/app/utils/a.py"], "risk_class": "C", "needs_human_review": False}
r = cl.lint_card(GOOD, ADD, ROOT)
ok("a well-formed card has no lint errors", not r["errors"], r["errors"])
bad = dict(GOOD, bullets=["it works correctly", "everything is handled properly", "behaves as expected"])
ok("vague bullets with no observable are rejected", {e["rule"] for e in cl.lint_card(bad, ADD, ROOT)["errors"]} >= {"bullet-vague"})
mixed = dict(GOOD, bullets=["`foo(2)` works correctly and returns 4", "`foo(-1)` raises ValueError", "`foo` is importable from `app.utils.a`"])
ok("a vague word next to a concrete observable is accepted", not [e for e in cl.lint_card(mixed, ADD, ROOT)["errors"] if e["rule"] == "bullet-vague"])
ok("2 bullets is rejected", any(e["rule"] == "bullet-count" for e in cl.lint_card(dict(GOOD, bullets=GOOD["bullets"][:2]), ADD, ROOT)["errors"]))
ok("8 bullets is rejected", any(e["rule"] == "bullet-count" for e in cl.lint_card(dict(GOOD, bullets=GOOD["bullets"] * 3), ADD, ROOT)["errors"]))
ok("bad risk_class is rejected", any(e["rule"] == "schema" for e in cl.lint_card(dict(GOOD, risk_class="Z"), ADD, ROOT)["errors"]))
ok("non-bool needs_human_review is rejected", any(e["rule"] == "schema" for e in cl.lint_card(dict(GOOD, needs_human_review="no"), ADD, ROOT)["errors"]))
ok("absolute files entry is rejected", any(e["rule"] == "files-unsafe" for e in cl.lint_card(dict(GOOD, files=["/etc/passwd"]), ADD, ROOT)["errors"]))
ok("a files entry that does not exist and is not created by the item is rejected",
   any(e["rule"] == "files-missing" for e in cl.lint_card(dict(GOOD, files=["backend/app/utils/a.py", "backend/app/ghost.py"]), ADD, ROOT)["errors"]))
ok("a non-dict card does not crash the linter", bool(cl.lint_card("nope", ADD, ROOT)["errors"]))
auth = item("Refactor `enforce_quota` to read the subscription tier from the DB", "backend/app/routers/test_runs.py")
res = cl.lint_card(dict(GOOD, risk_class="C", files=["backend/app/utils/a.py"]), auth, ROOT)
ok("risk can only go UP: model says C, item is billing/quota => final A + needs_human_review", res["info"]["risk_class_final"] == "A" and res["info"]["needs_human_review_final"] is True
   and res["info"]["risk_understated"] is True, res["info"])
ok("classify_item: delete / test / structural / behaviour / nochange",
   [cl.classify_item(x)["kind"] for x in (item("Delete the dead file fix_first.py"), item("Create tests for foo", "backend/tests/test_a.py", "test"),
                                         item("Replace hardcoded model ids with constants"), item("Implement `POST /api/x` returning 429 when over quota"),
                                         item("No change needed for this step"))] == ["delete", "test", "structural", "behaviour", "nochange"])
LINE = ("- [ ] [AUTO-SKIP staged: 27B could not land this] [T3] backend/app/services/billing.py — Update `set_tier` to bump user.token_version. "
        "VERIFY: `grep -q \"token_version\" backend/app/services/billing.py`. (cat:python; multifile:no) [feat:test-automation-agent-2026-x]")
pi = cl.parse_item_line(LINE)
ok("parse_item_line extracts tier/path/desc/verify/cat", pi and pi["tier"] == "T3" and pi["path"] == "backend/app/services/billing.py" and pi["cat"] == "python"
   and pi["verify"] == 'grep -q "token_version" backend/app/services/billing.py' and pi["desc"].startswith("Update `set_tier`"), pi)
DONE_LINE = "- [x] [T2] backend/tests/test_x.py — Add test for `foo`. VERIFY: `pytest backend/tests/test_x.py -v`. (cat:test; multifile:no)  <!-- staged 2/2 DONE -->"
pd = cl.parse_item_line(DONE_LINE)
ok("parse_item_line peels trailing '(cat:..)  <!-- .. -->' annotations in any order", pd and pd["verify"] == "pytest backend/tests/test_x.py -v" and pd["cat"] == "test", pd)
PROSE_LINE = "- [x] [T2] frontend/src/stores/x.js — Add a store test. VERIFY: `npx vitest run frontend/src/stores/__tests__/x.test.js -t \"fetch error\"` passes. (cat:test; multifile:no)"
pp = cl.parse_item_line(PROSE_LINE)
ok("parse_item_line takes the first backtick span of a '`cmd` passes' verify as the command", pp and pp["verify"] == 'npx vitest run frontend/src/stores/__tests__/x.test.js -t "fetch error"', pp)
ok("parse_item_line rejects a non-item line", cl.parse_item_line("- [ ] just some prose without a path") is None)
ok("eligibility excludes Vue/GDScript/Swift/Kotlin/markdown and keeps python",
   [cl.eligibility({"path": p, "desc": "x"})[0] for p in ("a/b.vue", "a/b.gd", "a/b.swift", "a/b.kt", "README.md", "backend/app/x.py")] == [False] * 5 + [True])
ok("existing-verify lint: the real-world `curl ... | jq .status` verify is rejected", "unsafe-command" in rules("curl -X POST http://localhost:8000/api/auth/revoke -H 'Authorization: Bearer <token>' | jq .status", ADD)[0])

# ---------------------------------------------------------------------------------------------------------------- 2. fake litellm
class Fake(http.server.BaseHTTPRequestHandler):
    script = []          # list of ("ok", card_dict) | ("500",) | ("garbage",) | ("sleep", secs)
    seen = []
    active = 0
    max_active = 0
    lock = threading.Lock()
    auth_seen = []

    def log_message(self, *a):
        pass

    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0)
        body = json.loads(self.rfile.read(n) or b"{}")
        with Fake.lock:
            Fake.active += 1
            Fake.max_active = max(Fake.max_active, Fake.active)
            Fake.seen.append(body)
            Fake.auth_seen.append(self.headers.get("Authorization"))
            step = Fake.script.pop(0) if Fake.script else ("500",)
        try:
            if step[0] == "sleep":
                time.sleep(step[1])
                step = ("500",)
            if step[0] == "500":
                self.send_response(500)
                self.end_headers()
                self.wfile.write(b"{}")
                return
            content = json.dumps(step[1]) if step[0] == "ok" else "this is not json at all"
            resp = {"choices": [{"message": {"content": content}, "finish_reason": "stop"}], "usage": {"prompt_tokens": 900, "completion_tokens": 120},
                    "timings": {"prompt_ms": 400.0, "predicted_ms": 1100.0}}
            data = json.dumps(resp).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        finally:
            with Fake.lock:
                Fake.active -= 1


class Srv(http.server.ThreadingHTTPServer):
    daemon_threads = True


srv = Srv(("127.0.0.1", 0), Fake)
PORT = srv.server_address[1]
threading.Thread(target=srv.serve_forever, daemon=True).start()
URL = "http://127.0.0.1:%d" % PORT

# ---------------------------------------------------------------------------------------------------------------- 3. demo repo
DEMO = os.path.join(REPOS, "demo")
os.makedirs(os.path.join(DEMO, "app"))
os.makedirs(os.path.join(DEMO, "tests"))
GENV = dict(os.environ, GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t", GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@t")


def g(*a):
    return subprocess.run(["git", "-C", DEMO] + list(a), capture_output=True, text=True, env=GENV)


g("init", "-q", "-b", "develop")
open(os.path.join(DEMO, "app", "__init__.py"), "w").write("")
open(os.path.join(DEMO, "app", "util.py"), "w").write("def existing():\n    return 1\n")
open(os.path.join(DEMO, "app", "old.py"), "w").write("X = 1\n")
open(os.path.join(DEMO, "tests", "test_util.py"), "w").write("import unittest\nfrom app.util import existing\nclass T(unittest.TestCase):\n    def test_a(self):\n        self.assertEqual(existing(), 1)\n")
g("add", "app", "tests")
g("commit", "-q", "-m", "base")
BASE = g("rev-parse", "HEAD").stdout.strip()
# head: adds slugify + a test
open(os.path.join(DEMO, "app", "util.py"), "a").write("\ndef slugify(s):\n    return s.lower().replace(' ', '-')\n")
os.remove(os.path.join(DEMO, "app", "old.py"))
g("add", "-A", "app")
g("commit", "-q", "-m", "head: add slugify, drop old")
HEAD = g("rev-parse", "HEAD").stdout.strip()
g("checkout", "-q", BASE)  # leave the clone at base

PYBIN = os.path.dirname(sys.executable)
MINPATH = PYBIN + ":/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin"


def run_cli(args, rel=False, extra_env=None, timeout=180):
    env = {"PATH": MINPATH, "NTFY_SERVER": "http://127.0.0.1:9/relay", "OVN_DIR": OVN, "OVN_REPOS_DIR": REPOS, "HOME": T, "LITELLM_MASTER_KEY": SECRET}
    env.update(extra_env or {})
    envl = ["env", "-i"] + ["%s=%s" % kv for kv in env.items()]
    script = "qa/acceptance_card.py" if rel else os.path.join(QA, "acceptance_card.py")
    p = subprocess.run(envl + [sys.executable, script] + args, capture_output=True, text=True, cwd=QUEUE, timeout=timeout)
    lines = [l for l in p.stdout.splitlines() if l.strip()]
    try:
        res = json.loads(lines[-1])
    except (IndexError, ValueError):
        res = {"verdict": "NOJSON", "summary": (p.stdout + p.stderr)[-400:], "details": {}}
    return p, res


ITEM_ADD = "app/util.py - Add `slugify(s)` that returns the lowercase string with spaces replaced by hyphens"
CARD_OK = {"bullets": ["`slugify('A b')` returns `'a-b'`", "`slugify('X')` returns `'x'`", "`slugify` is importable from `app.util`"],
           "verify_cmd": "python -c \"from app.util import slugify; assert slugify('A b') == 'a-b'\"", "files": ["app/util.py"], "risk_class": "C", "needs_human_review": False}


def cardfile(card, name="card.json"):
    p = os.path.join(T, name)
    json.dump(card, open(p, "w"))
    return p


print("entry point: absolute + relative path, env -i, benign + negative controls (stored cards, no model)")
for rel in (False, True):
    tag = "relative" if rel else "absolute"
    p, res = run_cli(["check", "--repo", "demo", "--base", BASE, "--item", ITEM_ADD, "--card-json", cardfile(CARD_OK), "--no-record"], rel=rel)
    ok("[%s] benign card -> PASS, exit 0, one JSON line" % tag, res["verdict"] == "PASS" and p.returncode == 0, res)
    ok("[%s] PASS records WHY the verify fails before (import error on a repo module)" % tag, "import-error" in json.dumps(res["details"].get("exec")), res["details"].get("exec"))
    bad = dict(CARD_OK, verify_cmd="grep -q slugify app/util.py || echo not-yet")
    p, res = run_cli(["check", "--repo", "demo", "--base", BASE, "--item", ITEM_ADD, "--card-json", cardfile(bad), "--no-record"], rel=rel)
    ok("[%s] negative: '|| echo' verify -> FAIL" % tag, res["verdict"] == "FAIL" and "swallow-or-handler" in res["summary"], res)

p, res = run_cli(["check", "--repo", "demo", "--base", BASE, "--item", ITEM_ADD, "--card-json", cardfile(dict(CARD_OK, verify_cmd="grep -q slugify app/util.py")), "--no-record"])
ok("negative: existence-only grep on a symbol the item adds -> FAIL (weak-existence)", res["verdict"] == "FAIL" and "weak-existence" in res["summary"], res)
p, res = run_cli(["check", "--repo", "demo", "--base", HEAD, "--item", ITEM_ADD, "--card-json", cardfile(CARD_OK), "--no-record"])
ok("negative: verify already passes at the base ref (item already done) -> FLAG", res["verdict"] == "FLAG" and "ALREADY PASSES" in res["summary"], res)
ITEM_NEW = "app/util_v2.py - Add `slugify(s)` that returns the lowercase string with spaces replaced by hyphens"
p, res = run_cli(["check", "--repo", "demo", "--base", BASE, "--item", ITEM_NEW, "--card-json", cardfile(dict(CARD_OK, files=["app/util_v2.py"], verify_cmd="python -c \"from app.util_v2 import slugify; assert slugify('A b') == 'a-b'\"")), "--no-record"])
ok("benign: item creates a NEW module; verify imports it -> fails before (module missing) -> PASS", res["verdict"] == "PASS", res)
p, res = run_cli(["check", "--repo", "demo", "--base", BASE, "--item", ITEM_ADD, "--card-json", cardfile(dict(CARD_OK, verify_cmd="python -c \"from app.util_v2 import slugify; assert slugify('A b') == 'a-b'\"")), "--no-record"])
ok("negative: verify imports a module the item never creates -> FAIL import-missing-module", res["verdict"] == "FAIL" and "import-missing-module" in res["summary"], res)
p, res = run_cli(["check", "--repo", "demo", "--base", BASE, "--item", ITEM_ADD, "--card-json", cardfile(dict(CARD_OK, verify_cmd="python -m pytest tests/test_ghost.py -q")), "--no-record"])
ok("negative: verify naming a path that does not exist and is not created by the item -> FAIL path-missing", res["verdict"] == "FAIL" and "path-missing" in res["summary"], res)
DELETE_ITEM = "app/old.py - Delete the dead file app/old.py"
dcard = dict(CARD_OK, bullets=["`app/old.py` no longer exists", "`app` still imports cleanly via `app.util`", "no other module in `app` imports `app.old`"],
             verify_cmd="test ! -e app/old.py", files=["app/old.py"])
p, res = run_cli(["check", "--repo", "demo", "--base", BASE, "--item", DELETE_ITEM, "--card-json", cardfile(dcard), "--no-record"])
ok("delete item with `test ! -e` -> PASS (exists at base, so it fails before)", res["verdict"] == "PASS", res)
p, res = run_cli(["check", "--repo", "demo", "--base", BASE, "--head", HEAD, "--item", DELETE_ITEM, "--card-json", cardfile(dcard), "--no-record"])
ok("--head: verify passes after the change -> still PASS and records after=passed", res["verdict"] == "PASS" and res["details"]["after"]["outcome"] == "passed", res)
p, res = run_cli(["check", "--repo", "demo", "--base", BASE, "--item", DELETE_ITEM, "--card-json", cardfile(dict(dcard, verify_cmd="test -e app/old.py")), "--no-record"])
ok("negative: delete item verified by a POSITIVE existence test -> FAIL direction-mismatch", res["verdict"] == "FAIL" and "direction-mismatch" in res["summary"], res)
p, res = run_cli(["check", "--repo", "demo", "--base", BASE, "--head", HEAD, "--item", ITEM_ADD, "--card-json", cardfile(dict(CARD_OK, verify_cmd="python -c \"from app.util import slugify; assert slugify('A b') == 'A-b'\"")), "--no-record"])
ok("--head: verify still failing AFTER the change -> FLAG", res["verdict"] == "FLAG" and "AFTER" in res["summary"], res)

import acceptance_card as _ac  # noqa: E402
ok("exec classification: rc5 'no tests ran' is not an infra error", _ac.classify_outcome(5, "no tests ran in 0.01s", T) == ("failed", "no-tests-collected"))
_lint_ok = {"errors": [], "flags": []}
_ex = {"outcome": "failed", "reason": "no-tests-collected"}
ok("decide: 'selects no tests' is FAIL for a non-test item and legitimate for a test-creating item",
   _ac.decide("behaviour", _lint_ok, _ex, None)[0] == "FAIL" and _ac.decide("test", _lint_ok, _ex, None)[0] == "PASS")
ok("decide: NameError/SyntaxError in the verify is 'broken' -> FAIL", _ac.classify_outcome(1, "NameError: name 'x' is not defined", T)[0] == "broken"
   and _ac.decide("behaviour", _lint_ok, {"outcome": "broken", "reason": "NameError: x"}, None)[0] == "FAIL")

print("safety: unsafe verify is never executed; env is scrubbed; timeouts are enforced")
SENT = os.path.join(T, "sentinel.txt")
open(SENT, "w").write("alive")
p, res = run_cli(["check", "--repo", "demo", "--base", BASE, "--item", ITEM_ADD, "--card-json", cardfile(dict(CARD_OK, verify_cmd="rm -f %s && grep -q slugify app/util.py" % SENT)), "--no-record"])
ok("negative: destructive verify -> FAIL and the command was NOT run (sentinel survives)", res["verdict"] == "FAIL" and os.path.exists(SENT) and res["details"]["exec"] is None, res)
envleak = dict(CARD_OK, verify_cmd="python -c \"import os; from app.util import slugify; assert os.environ.get('LITELLM_MASTER_KEY') or os.environ.get('SECRET_TOKEN')\"")
p, res = run_cli(["check", "--repo", "demo", "--base", HEAD, "--item", ITEM_ADD, "--card-json", cardfile(envleak), "--no-record"], extra_env={"SECRET_TOKEN": "leak"})
ok("exec env is scrubbed: a verify that needs an inherited secret FAILS at exec (a leaked env would make it PASS before)", res["details"]["exec"]["outcome"] == "failed" and res["details"]["exec"]["reason"] == "assertion", res)
broken = dict(CARD_OK, verify_cmd="python -c \"from app.util import existing; assert undefined_name_zz(existing())\"")
p, res = run_cli(["check", "--repo", "demo", "--base", BASE, "--item", ITEM_ADD, "--card-json", cardfile(broken), "--no-record"])
ok("a verify that fails for its OWN reason (NameError) is FAIL 'broken', not a fake 'fails before' PASS", res["verdict"] == "FAIL" and "broken" in res["summary"], res)
slow = dict(CARD_OK, verify_cmd="python -c \"import time; time.sleep(60); assert abs(1) == 1\"")
t0 = time.time()
p, res = run_cli(["check", "--repo", "demo", "--base", BASE, "--item", ITEM_ADD, "--card-json", cardfile(slow), "--no-record", "--exec-timeout", "3"])
ok("timeout -> UNVERIFIED (never PASS/FAIL), exit 0, killed promptly", res["verdict"] == "UNVERIFIED" and p.returncode == 0 and time.time() - t0 < 30, (res, time.time() - t0))
dep = dict(CARD_OK, verify_cmd="python -c \"import zz_not_installed_dep; assert zz_not_installed_dep.f() == 1\"")
p, res = run_cli(["check", "--repo", "demo", "--base", BASE, "--item", ITEM_ADD, "--card-json", cardfile(dep), "--no-record"])
ok("a third-party import error is infra -> UNVERIFIED, not a fake 'fails before'", res["verdict"] == "UNVERIFIED" and "missing-dependency" in res["summary"], res)
p, res = run_cli(["check", "--repo", "demo", "--base", "no-such-ref", "--item", ITEM_ADD, "--card-json", cardfile(CARD_OK), "--no-record"])
ok("unknown base ref -> UNVERIFIED", res["verdict"] == "UNVERIFIED", res)
p, res = run_cli(["check", "--repo", "nonexistent-repo", "--base", BASE, "--item", ITEM_ADD, "--card-json", cardfile(CARD_OK), "--no-record"])
ok("unknown repo -> UNVERIFIED", res["verdict"] == "UNVERIFIED", res)
p, res = run_cli(["check", "--repo", "demo", "--base", BASE, "--item", "this is not an item", "--no-record"])
ok("unparseable item -> UNVERIFIED", res["verdict"] == "UNVERIFIED", res)
ok("no worktrees or temp dirs leaked into the clone", g("worktree", "list").stdout.strip().count("\n") == 0, g("worktree", "list").stdout)

print("scope: out-of-scope items cost no model call")
Fake.seen.clear()
for line in ("frontend/src/pages/X.vue - Add a field `x` and bind it to a textarea", "game/unit.gd - Add `take_damage(n)` to Unit", "docs/NOTES.md - Add a section about retries",
             "app/util.py - No change needed for this step, but ensure the module is clean"):
    p, res = run_cli(["check", "--repo", "demo", "--base", BASE, "--item", line, "--llm-url", URL, "--no-record"])
    ok("NA without a model call: %r" % line[:50], res["verdict"] == "NA", res)
ok("no request reached the model for out-of-scope items", len(Fake.seen) == 0, len(Fake.seen))

print("model path: fake loopback litellm (serial, strict, bounded)")


def with_script(script, args=None, extra_env=None, **kw):
    for _ in range(300):  # a previous timed-out request may still be sleeping inside the fake server
        if Fake.active == 0:
            break
        time.sleep(0.1)
    Fake.script = list(script)
    Fake.seen.clear()
    Fake.max_active = 0
    a = ["check", "--repo", "demo", "--base", BASE, "--item", ITEM_ADD, "--llm-url", URL, "--no-record"] + (args or [])
    return run_cli(a, extra_env=extra_env, **kw)


p, res = with_script([("ok", CARD_OK)])
ok("drafted card, lint-clean, fails before -> PASS", res["verdict"] == "PASS", res)
ok("exactly one request; tokens + GPU seconds recorded", len(Fake.seen) == 1 and res["details"]["llm"]["prompt_tokens"] == 900 and res["details"]["llm"]["gpu_s"] == 1.5, res["details"].get("llm"))
b = Fake.seen[0]
ok("request is bounded: temperature<=0.2, max_tokens<=800, JSON mode, model name set", b["temperature"] <= 0.2 and b["max_tokens"] <= 800 and b["response_format"] == {"type": "json_object"} and b["model"])
ok("the prompt carries the item and the target file", "slugify" in b["messages"][1]["content"] and "def existing" in b["messages"][1]["content"])
ok("the API key is sent as a bearer token but never printed", Fake.auth_seen[0] == "Bearer " + SECRET and SECRET not in p.stdout and SECRET not in p.stderr)
p, res = with_script([("500",), ("ok", CARD_OK)])
ok("1 retry: first 500 then a good answer -> PASS after 2 requests", res["verdict"] == "PASS" and len(Fake.seen) == 2, (res, len(Fake.seen)))
p, res = with_script([("500",), ("500",), ("ok", CARD_OK)])
ok("model error twice -> UNVERIFIED, never more than 2 requests", res["verdict"] == "UNVERIFIED" and len(Fake.seen) == 2, (res, len(Fake.seen)))
p, res = with_script([("garbage",), ("garbage",)])
ok("unparseable JSON twice -> UNVERIFIED", res["verdict"] == "UNVERIFIED" and "unparseable" in res["summary"], res)
t0 = time.time()
p, res = with_script([("sleep", 6), ("sleep", 6)], extra_env={"QA_ACCEPTANCE_LLM_TIMEOUT": "1"})
ok("hard model timeout -> UNVERIFIED, bounded wall time, exit 0", res["verdict"] == "UNVERIFIED" and p.returncode == 0 and time.time() - t0 < 20, (res, time.time() - t0))
p, res = with_script([("ok", CARD_OK)], ["--llm-url", "http://10.1.2.3:4000"])
ok("a non-loopback model URL is refused without a request -> UNVERIFIED", res["verdict"] == "UNVERIFIED" and len(Fake.seen) == 0, (res, len(Fake.seen)))
shortcard = dict(CARD_OK, bullets=["`slugify('A b')` returns `'a-b'`", "it works correctly"])
p, res = with_script([("ok", shortcard)])
ok("negative: a 2-bullet card from the model -> FAIL (bullet-count) and no retry without --repair", res["verdict"] == "FAIL" and "bullet-count" in res["summary"] and len(Fake.seen) == 1, (res, len(Fake.seen)))
p, res = with_script([("ok", shortcard), ("ok", CARD_OK)], ["--repair"])
ok("--repair: lint feedback is sent back once and the fixed card is accepted (2 requests max)", res["verdict"] == "PASS" and len(Fake.seen) == 2 and "REJECTED BY THE LINTER" in Fake.seen[1]["messages"][1]["content"], (res, len(Fake.seen)))
p, res = with_script([("ok", shortcard), ("ok", shortcard), ("ok", CARD_OK)], ["--repair"])
ok("--repair never makes a third request", len(Fake.seen) == 2, len(Fake.seen))
evil = dict(CARD_OK, verify_cmd="rm -f %s; grep -q slugify app/util.py" % SENT)
p, res = with_script([("ok", evil)])
ok("model-proposed destructive verify -> FAIL, never executed (sentinel survives)", res["verdict"] == "FAIL" and os.path.exists(SENT), res)
ok("requests were strictly serial (max 1 in flight)", Fake.max_active == 1, Fake.max_active)
p, res = with_script([("ok", dict(CARD_OK, risk_class="C", needs_human_review=False))], ["--item", "app/util.py - Add `slugify(s)` to hash the user token for the billing webhook"])
ok("risk floor wins: billing/token keywords force class A + human review regardless of the model", res["details"].get("risk_class") == "A" and res["details"].get("needs_human_review") is True, res["details"])

print("recording + enforce semantics")
shadow = os.path.join(OVN, "state", "qa_shadow", "acceptance.jsonl")
p, res = run_cli(["check", "--repo", "demo", "--base", BASE, "--item", ITEM_ADD, "--card-json", cardfile(CARD_OK)])
ok("without --no-record the result is appended to state/qa_shadow/acceptance.jsonl", os.path.isfile(shadow) and json.loads(open(shadow).read().splitlines()[-1])["verdict"] == "PASS")
n0 = len(open(shadow).read().splitlines())
run_cli(["check", "--repo", "demo", "--base", BASE, "--item", ITEM_ADD, "--card-json", cardfile(CARD_OK), "--no-record"])
ok("--no-record writes nothing", len(open(shadow).read().splitlines()) == n0)
badc = cardfile(dict(CARD_OK, verify_cmd="echo ok"))
p, res = run_cli(["check", "--repo", "demo", "--base", BASE, "--item", ITEM_ADD, "--card-json", badc, "--no-record", "--enforce-exit"])
ok("shadow mode: FAIL still exits 0 even with --enforce-exit", res["verdict"] == "FAIL" and p.returncode == 0 and res["mode"] == "shadow", (p.returncode, res))
p, res = run_cli(["check", "--repo", "demo", "--base", BASE, "--item", ITEM_ADD, "--card-json", badc, "--no-record", "--enforce-exit"], extra_env={"OVN_QA_ACCEPTANCE": "enforce"})
ok("enforce mode + --enforce-exit: FAIL exits 1", res["verdict"] == "FAIL" and p.returncode == 1, (p.returncode, res))

print("pilot subcommand")
items = os.path.join(T, "items.md")
open(items, "w").write("\n".join([
    "- [ ] [T2] app/util.py — " + "Add `slugify(s)` that returns the lowercase string with spaces replaced by hyphens. VERIFY: `grep -q slugify app/util.py`. (cat:python; multifile:no)",
    "- [ ] [T3] ui/Page.vue — Add a `foo` field bound to a textarea. VERIFY: `grep -q foo ui/Page.vue`. (cat:web; multifile:no)",
    "- [ ] [HUMAN-ONLY] [T3] app/util.py — Something a human must do. VERIFY: true. (cat:python; multifile:no)",
    "- [x] [T1] app/util.py — Already done item. (cat:python; multifile:no)",
]) + "\n")
Fake.script = [("ok", CARD_OK)]
Fake.seen.clear()
out = os.path.join(T, "pilot-out")
p, res = run_cli(["pilot", "--repo", "demo", "--base", BASE, "--items-file", items, "--out", out, "--llm-url", URL, "--compare-existing", "--no-record"])
summ = json.load(open(os.path.join(out, "summary.json"))) if os.path.exists(os.path.join(out, "summary.json")) else {}
ok("pilot writes cards.jsonl + summary.json and counts only open, non-human, in-scope items",
   summ.get("cards_attempted") == 1 and summ.get("excluded", {}).get("excluded language/UI: UI (Vue)") == 1 and os.path.exists(os.path.join(out, "cards.jsonl")), summ)
ok("pilot summary has lint pass rate, fails-before rate, GPU seconds, token means and the existing-VERIFY comparison",
   summ.get("lint_pass_rate") == 1.0 and summ.get("fails_before") == 1 and summ["gpu_s_per_card"]["mean"] == 1.5 and summ.get("prompt_tokens_mean") == 900
   and summ["existing_verify"]["n"] == 1 and summ["existing_verify"]["lint_rejected"] == 1, summ)

print("exec_check in-process: node_modules symlink provisioning leaves the source intact")
import acceptance_card as ac  # noqa: E402
os.environ["OVN_REPOS_DIR"] = REPOS
os.environ["OVN_DIR"] = OVN
nm = os.path.join(DEMO, "node_modules")
os.makedirs(nm, exist_ok=True)
open(os.path.join(nm, "marker"), "w").write("m")
os.makedirs(os.path.join(DEMO, "tests"), exist_ok=True)
r1 = ac.exec_check("demo", BASE, "test -f node_modules/marker || exit 1")
ok("node_modules is provisioned into the worktree by symlink", r1["outcome"] == "passed", r1)
ok("... and the real node_modules survives worktree teardown", os.path.isfile(os.path.join(nm, "marker")))

srv.shutdown()
shutil.rmtree(T, ignore_errors=True)
print("  %d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
