#!/usr/bin/env python3
"""VERIFY malformation lint (2026-10-15, fixer A2): ovn_verify_malformed.py + the verify-malformed tag in ovn_classify_fail.sh.

Fixtures mirror the four overnight failures: a pytest node that does not exist (exit 4), `npx tsc` with no local compiler,
`from app.x` run from the repo root, a grep target that does not exist, and a remove-premise with live callers.
Every case that asserts a finding is paired with a clean case so the lint cannot pass by flagging everything."""
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPTS = os.path.abspath(os.path.join(HERE, ".."))
QUEUE = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, SCRIPTS)
import ovn_verify_malformed as M  # noqa: E402

P = F = 0


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name + ((" :: " + str(extra)[:300]) if extra else ""))


def put(root, rel, text=""):
    full = os.path.join(root, rel)
    os.makedirs(os.path.dirname(full), exist_ok=True)
    with open(full, "w", encoding="utf-8") as fh:
        fh.write(text)


def codes(findings):
    return sorted(f["code"] for f in findings)


root = tempfile.mkdtemp(prefix="vm-tree-")
put(root, "backend/app/utils/eta.py", "def remaining_seconds(total, completed, elapsed):\n    return 0.0\n")
put(root, "backend/tests/test_utils_eta.py", "class TestRemainingSeconds:\n    def test_none_for_invalid_total(self):\n        pass\n")
put(root, "iptv-web/node_modules/.bin/tsc", "#!/bin/sh\n")
put(root, "iptv-web/src/views/VodView.vue", "<template></template>\n")
put(root, "svc/discover.py", "from x import filter_streams_for_profile\nprint(filter_streams_for_profile)\n")
put(root, "svc/dead.py", "def dead_helper():\n    return 1\n")
put(root, "svc/tests/test_dead.py", "from dead import dead_helper\n")
os.makedirs(os.path.join(root, "bare"), exist_ok=True)

# 1. pytest node that exists, run from the package dir: clean
v = "cd backend && python -m pytest tests/test_utils_eta.py::TestRemainingSeconds::test_none_for_invalid_total -v"
ok("pytest node that exists (cd backend) is clean", M.lint_verify(v, root) == [], M.lint_verify(v, root))

# 2. pytest node that does not exist (the item's test_remaining_seconds_edge_cases)
v = "cd backend && python -m pytest tests/test_utils_eta.py::test_remaining_seconds_edge_cases -v"
ok("missing pytest node is pytest-node-missing", codes(M.lint_verify(v, root)) == ["pytest-node-missing"], M.lint_verify(v, root))

# 3. pytest path resolved from the repo root instead of the package dir
v = "python -m pytest tests/test_utils_eta.py::test_none_for_invalid_total"
ok("pytest path not under the effective cwd is pytest-path-missing", codes(M.lint_verify(v, root)) == ["pytest-path-missing"], M.lint_verify(v, root))

# 4. npx tsc run from the repo root where no compiler is installed
v = "npx tsc --noEmit -p tsconfig.json"
ok("npx tsc with no local compiler is flagged", "npx-tsc-no-local-compiler" in codes(M.lint_verify(v, root, tsc_baseline_green=True)))
v = "cd iptv-web && npx tsc --noEmit -p tsconfig.json"
ok("npx tsc from the package dir with a local compiler is not flagged", "npx-tsc-no-local-compiler" not in codes(M.lint_verify(v, root, tsc_baseline_green=True)))

# 5. whole-project tsc baseline handling
v = "cd iptv-web && npx tsc --noEmit -p tsconfig.json"
ok("whole-project tsc with no baseline is unbaselined", "whole-project-tsc-unbaselined" in codes(M.lint_verify(v, root)))
ok("whole-project tsc with a red baseline is tsc-baseline-red", "tsc-baseline-red" in codes(M.lint_verify(v, root, tsc_baseline_green=False)))
v = "cd iptv-web && npx tsc --noEmit src/views/VodView.vue"
ok("scoped tsc (named file) is not whole-project", "whole-project-tsc-unbaselined" not in codes(M.lint_verify(v, root)))

# 6. `from app.x` run from the repo root (the TAA eta clause)
v = "python -c 'from app.utils.eta import remaining_seconds; assert remaining_seconds(5, 5, 10) == 0.0'"
ok("from app.x from repo root is import-root-missing", "import-root-missing" in codes(M.lint_verify(v, root)), M.lint_verify(v, root))
v = "cd backend && python -c 'from app.utils.eta import remaining_seconds; assert remaining_seconds(5, 5, 10) == 0.0'"
ok("from app.x from backend/ is clean", M.lint_verify(v, root) == [], M.lint_verify(v, root))

# 7. literal target that does not exist: an 'add' item may create it, a verify-only item may not
v = "grep -c logo_url iptv-web/src/__tests__/vod-types.test.ts"
ok("missing grep target on a verify-only item is target-path-missing", "target-path-missing" in codes(M.lint_verify(v, root, "Verify VodItem fields")))
ok("missing grep target on an add item is not flagged", "target-path-missing" not in codes(M.lint_verify(v, root, "Add test asserting VodItem logo_url")))
v = "grep -q x iptv-web/src/views/VodView.vue"
ok("existing grep target is clean", M.lint_verify(v, root, "Verify") == [], M.lint_verify(v, root, "Verify"))

# 8. classifier verdict on a finished run
ok("rc 4 from pytest is verify-malformed", M.classify_result(4, "", "python -m pytest x.py::y") == "verify-malformed")
ok("rc 4 from a non-pytest command is not verify-malformed", M.classify_result(4, "", "make") is None)
ok("npx tsc install prompt is verify-malformed", M.classify_result(1, "To get access to the TypeScript compiler, install", "npx tsc") == "verify-malformed")
ok("ModuleNotFoundError for app.foo (a real API mismatch) is not verify-malformed",
   M.classify_result(1, "ModuleNotFoundError: No module named 'app.foo'", "python -c") is None)
ok("ModuleNotFoundError for bare app is verify-malformed",
   M.classify_result(1, "ModuleNotFoundError: No module named 'app'", "python -c") == "verify-malformed")

# 8b. P2: the ERROR not found signature is anchored to the pytest verify-clause shape
ok("pytest verify-clause 'ERROR: not found: path::node (no match...)' is verify-malformed",
   M.classify_result(4, "ERROR: not found: /w/backend/tests/test_x.py::test_x (no match in any of [<Module test_x.py>])", "python -m pytest tests/test_x.py::test_x") == "verify-malformed")
ok("a Playwright 'ERROR: not found: #login-button' is NOT verify-malformed (classify_result)",
   M.classify_result(1, "ERROR: not found: #login-button", "npx playwright test") is None)

# 9. park decision: one malformed attempt parks, nothing else changes
ok("verify-malformed parks after one attempt", M.verify_park_decision("verify-malformed", 1) == "park")
ok("verify-malformed with no prior attempt still retries once", M.verify_park_decision("verify-malformed", 0) == "retry")
ok("test-red is never parked by the malformed rule", M.verify_park_decision("test-red", 3) == "retry")

# 10. remove-premise: a symbol with a live non-test caller is flagged, one called only by tests is not
ok("remove-premise with live caller is flagged",
   codes(M.remove_premise_findings(["filter_streams_for_profile"], os.path.join(root, "svc"))) == ["remove-premise-live-callers"])
ok("remove-premise called only from tests is clean",
   M.remove_premise_findings(["dead_helper"], os.path.join(root, "svc")) == [])

# 11. the classifier script. The verify-malformed block is OFF by default (P2 review): positives opt in with OVN_CLASSIFY_MALFORMED=on.
C = os.path.join(QUEUE, "ovn_classify_fail.sh")
ON = {"OVN_CLASSIFY_MALFORMED": "on"}


def classify(log_text, status="failed", env=None, pop_default=True):
    lp = os.path.join(tempfile.mkdtemp(prefix="vm-log-"), "task.log")
    with open(lp, "w", encoding="utf-8") as fh:
        fh.write(log_text)
    e = dict(os.environ)
    if pop_default:
        e.pop("OVN_CLASSIFY_MALFORMED", None)
        e.pop("OVN_VERIFY_MALFORMED_SHADOW_LOG", None)
    e.update(env or {})
    r = subprocess.run(["bash", C, lp, status], capture_output=True, text=True, env=e, timeout=60)
    return r.stdout.strip()


TSC_LOG = "> npx tsc --noEmit\nTo get access to the TypeScript compiler, install\n"
PYTEST_NF_LOG = "> pytest x.py::test_x\nERROR: not found: /w/x.py::test_x (no match in any of [<Module x.py>])\n"
PLAYWRIGHT_RED_LOG = ("--- verify: npm test in iptv-web (120s cap) ---\n"
                      "  1) login.spec.ts > shows the form\n"
                      "ERROR: not found: #login-button\n"
                      "  1 failed\n")

ok("classifier (opt-in on): TypeScript compiler install prompt -> verify-malformed",
   classify(TSC_LOG, env=ON) == "verify-malformed")
ok("classifier (opt-in on): bare 'No module named app' -> verify-malformed",
   classify("Traceback\nModuleNotFoundError: No module named 'app'\n", env=ON) == "verify-malformed")
ok("classifier (opt-in on): real missing submodule app.foo stays api-mismatch",
   classify("Traceback\nModuleNotFoundError: No module named 'app.foo'\n", env=ON) == "api-mismatch")
ok("classifier (opt-in on): pytest verify-clause not-found -> verify-malformed",
   classify(PYTEST_NF_LOG, env=ON) == "verify-malformed")
ok("classifier: context overflow still context-exceeded",
   classify("maximum context length exceeded\n") == "context-exceeded")

# P2 (4a): the default is inert. The same log that is verify-malformed when on must NOT change fail_reason by default.
ok("DEFAULT IS INERT: TypeScript install prompt with no env is not verify-malformed",
   classify(TSC_LOG) != "verify-malformed", classify(TSC_LOG))
ok("DEFAULT IS INERT: pytest verify-clause not-found with no env is not verify-malformed",
   classify(PYTEST_NF_LOG) != "verify-malformed", classify(PYTEST_NF_LOG))
ok("explicit OVN_CLASSIFY_MALFORMED=off is inert too",
   classify(TSC_LOG, env={"OVN_CLASSIFY_MALFORMED": "off"}) != "verify-malformed")

# P2 (4b): a real test-red line that carries the phrase ERROR not found stays test-red.
ok("real Playwright test-red with 'ERROR: not found: #login-button' is test-red by default",
   classify(PLAYWRIGHT_RED_LOG) == "test-red", classify(PLAYWRIGHT_RED_LOG))
ok("real Playwright test-red stays test-red even with OVN_CLASSIFY_MALFORMED=on",
   classify(PLAYWRIGHT_RED_LOG, env=ON) == "test-red", classify(PLAYWRIGHT_RED_LOG, env=ON))

# P2 (1): shadow mode prints the old tag and only logs.
shadow_log = os.path.join(tempfile.mkdtemp(prefix="vm-shadow-"), "shadow.tsv")
shadow_env = {"OVN_CLASSIFY_MALFORMED": "shadow", "OVN_VERIFY_MALFORMED_SHADOW_LOG": shadow_log}
out = classify(TSC_LOG, env=shadow_env, pop_default=False)
ok("shadow mode prints the old tag, not verify-malformed", out != "verify-malformed", out)
ok("shadow mode appends one line when the signature would have matched",
   os.path.isfile(shadow_log) and "task.log" in open(shadow_log, encoding="utf-8").read())
shadow_log2 = os.path.join(tempfile.mkdtemp(prefix="vm-shadow2-"), "shadow.tsv")
classify(PLAYWRIGHT_RED_LOG, env={"OVN_CLASSIFY_MALFORMED": "shadow", "OVN_VERIFY_MALFORMED_SHADOW_LOG": shadow_log2}, pop_default=False)
ok("shadow mode does not log a real test-red line", not os.path.isfile(shadow_log2) or open(shadow_log2, encoding="utf-8").read() == "")

# P2 (3): shadow lint helper. Off writes nothing; shadow writes one JSON line; a lint bug never raises.
lint_log = os.path.join(tempfile.mkdtemp(prefix="vm-lint-"), "verify_lint_shadow.log")
ok("shadow_log_verify with mode off writes nothing and returns None",
   M.shadow_log_verify("npx tsc --noEmit -p x", root, "item", lint_log, mode="off") is None and not os.path.exists(lint_log))
fnd = M.shadow_log_verify("cd backend && python -m pytest tests/test_utils_eta.py::test_remaining_seconds_edge_cases -v", root,
                          "item", lint_log, mode="shadow")
ok("shadow_log_verify returns the findings in shadow mode", codes(fnd or []) == ["pytest-node-missing"], fnd)
rows = open(lint_log, encoding="utf-8").read().splitlines() if os.path.isfile(lint_log) else []
ok("shadow_log_verify appends exactly one JSON line", len(rows) == 1 and "pytest-node-missing" in rows[0], rows)
ok("shadow_log_verify never raises on an unwritable path",
   M.shadow_log_verify("npx tsc", root, "item", "/nonexistent-root-xyz/\0bad/log", mode="shadow") is None)

# P2 (3): production caller. queue_refill's pull path calls the shadow lint; it logs and is inert when off.
import importlib  # noqa: E402
sys.path.insert(0, QUEUE)
QR = importlib.import_module("queue_refill")
qr_log = os.path.join(tempfile.mkdtemp(prefix="vm-qr-"), "verify_lint_shadow.log")
os.environ["OVN_VERIFY_LINT_LOG"] = qr_log
os.environ.pop("OVN_VERIFY_LINT", None)
_qr_fn = getattr(QR, "_verify_lint_shadow", None)
item = "- [ ] Fix thing - VERIFY: `cd backend && python -m pytest tests/test_utils_eta.py::test_remaining_seconds_edge_cases -v` (cat: x)"
n = _qr_fn([item], root) if _qr_fn else -1
ok("queue_refill shadow lint writes a row for a pulled item with a VERIFY", n == 1 and os.path.isfile(qr_log), n)
os.environ["OVN_VERIFY_LINT"] = "off"
qr_log2 = qr_log + ".off"
os.environ["OVN_VERIFY_LINT_LOG"] = qr_log2
n2 = _qr_fn([item], root) if _qr_fn else -1
ok("queue_refill shadow lint is inert with OVN_VERIFY_LINT=off", n2 == 0 and not os.path.exists(qr_log2), n2)
os.environ.pop("OVN_VERIFY_LINT", None)
os.environ.pop("OVN_VERIFY_LINT_LOG", None)

print("  %d passed, %d failed" % (P, F))
sys.exit(0 if F == 0 else 1)
