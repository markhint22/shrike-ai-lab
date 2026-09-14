# test-automation-agent (SpecPilot) — RELEASE-READINESS backlog (27B-friendly), blockers FIRST
# Backend is saturated with tests; the real release gaps are the thin Vue frontend.

# --- next-year roadmap decomposition (2026-09-05): surface backend features + CI/scheduling ---

# --- refill (2026-09-05): frontend store/page coverage (backend near-exhausted) ---

# --- refill 2026-09-06: new self-contained pure modules (pytest + vitest, landable T1-T2) ---

# --- refill 2026-09-06: test-run-domain pure modules (self-verifying, T1-T2) ---

# --- refill 2026-09-06b: more test-run domain pure modules ---

# --- 27B-decomposed from roadmap [2026-09-07]: Test-run summaries, status, retry/rerun decisions, flake ratios (pure logic + endpoints) { (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-07]: Run dashboard UI: status colors, durations, pass/flake surfaces {cat: web; size: M; multif (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-07]: Knowledge-base / test-selection helpers {cat: backend; size: M; multifile: no; research: r (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-09]: CI integrations (GitHub Actions/Jenkins) result ingestion — researched 2026-09-09: GitHub  (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-10]: Flake-state Slack/webhook alerts — When a test's rolling flake ratio crosses a configured  (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-10]: "Fix-first" ranking view — Add a dashboard view/API endpoint that ranks tests by (flake-ra (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-10]: "Fix-first" ranking view — Add a dashboard view/API endpoint that ranks tests by (flake-ra (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-10]: Per-test flake-rate trend chart — On each test's detail page, render a time-series/sparkli (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-10]: PR-comment run summary — Post a single upserted PR comment (via the same GitHub App/token  (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-11]: Rerun-failed-only endpoint — Add `POST /api/test-runs/{run_id}/rerun-failed` (backend/app/ (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-11]: Auto-release stale quarantines — backend/app/services/flake_detection.py's record_result() (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-11]: Wire PR-comment upsert into the GitHub API — backend/app/utils/pr_comment_body.py (build_p (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-11]: Visual-regression diff flagging — backend/app/utils/visual_diff.py (diff_ratio, is_visual_ (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-11]: Remove dead fix-first stub router — backend/app/routers/fix_first.py is a leftover stub (` (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-13]: Surface overall suite health badge on Flake Dashboard — backend/app/utils/suite_health.py' (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-13]: Wire tiered flake-severity badges into the Flake Dashboard — backend/app/utils/flake_indic (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-13]: Consolidate duplicate status-color helpers and wire flaky coloring into the run list — thr (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-13]: Remove dead duplicate select_by_tag helper — backend/app/utils/test_selection.py's `select (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-13]: Add unit tests for the flakes Pinia store — frontend/src/stores/flakes.js (fetchFlakes, se (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-14]: Wire flake-trend direction into the per-test trend endpoint — `GET /api/flakes/{test_name} (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-14]: Wire selector_scoring.score_selector into the optimizer's ranking — backend/app/utils/sele (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-14]: Remove dead duplicate rbac.py — backend/app/utils/rbac.py's `has_permission`/`role_rank` ( (review + tweak) ---
- [ ] [T1] backend/app/utils/rbac.py — Delete the file containing dead `has_permission` and `role_rank` functions. VERIFY: `test -f backend/app/utils/rbac.py && echo "FAIL" || echo "PASS"`. (cat:refactor; multifile:no)
- [ ] [T2] backend/tests/test_rbac.py — Delete the test file for the removed rbac module. VERIFY: `test -f backend/tests/test_rbac.py && echo "FAIL" || echo "PASS"`. (cat:test; multifile:no)
- [ ] [T3] backend/app/utils/__init__.py — Remove any imports or exports referencing `rbac` if present. VERIFY: `grep -r "from.*rbac import\|import rbac" backend/app/ && echo "FAIL" || echo "PASS"`. (cat:python; multifile:no)
- [ ] [T4] backend/app/models/tenancy.py — Verify `ROLE_RANK` and `role_at_least` remain intact and correct. VERIFY: `grep -n "ROLE_RANK = {" backend/app/models/tenancy.py && grep -n "def role_at_least" backend/app/models/tenancy.py`. (cat:python; multifile:no)
- [ ] [T5] backend/app/routers/orgs.py — Verify line 99 still uses `role_at_least` from tenancy model. VERIFY: `sed -n '99p' backend/app/routers/orgs.py | grep "role_at_least"`. (cat:python; multifile:no)

# --- 27B-decomposed from roadmap [2026-09-14]: Remove dead org_scoping.py — backend/app/utils/org_scoping.py's `can_access`/`require_owne (review + tweak) ---
- [ ] [T1] backend/tests/test_org_scoping.py — Delete the file to remove tests for the unused `can_access` and `require_owner` functions. VERIFY: `test -f backend/tests/test_org_scoping.py && echo "FAIL" || echo "PASS"`. (cat:test; multifile:no)
- [ ] [T1] backend/app/utils/org_scoping.py — Delete the file to remove the dead code implementing the unused ownership check logic. VERIFY: `test -f backend/app/utils/org_scoping.py && echo "FAIL" || echo "PASS"`. (cat:refactor; multifile:no)
- [ ] [T2] backend/app/utils/__init__.py — Verify no imports of `org_scoping` exist in the package initialization or other utils. VERIFY: `grep -r "from .org_scoping import\|import org_scoping" backend/app/utils/ && echo "FAIL" || echo "PASS"`. (cat:python; multifile:no)
- [ ] [T2] backend/app/routers/webhooks.py — Confirm the existing `_owned_endpoint` logic remains intact and does not reference `org_scoping`. VERIFY: `grep -n "org_scoping" backend/app/routers/webhooks.py && echo "FAIL" || echo "PASS"`. (cat:python; multifile:no)
- [ ] [T2] backend/app/services/tenancy.py — Verify no imports or usage of `org_scoping` in the tenancy service. VERIFY: `grep -n "org_scoping" backend/app/services/tenancy.py && echo "FAIL" || echo "PASS"`. (cat:python; multifile:no)
- [ ] [T2] backend/app/core/auth.py — Verify no imports or usage of `org_scoping` in the core auth module. VERIFY: `grep -n "org_scoping" backend/app/core/auth.py && echo "FAIL" || echo "PASS"`. (cat:python; multifile:no)
- [ ] [T3] backend/app/main.py — Verify the application entry point does not import or register `org_scoping` utilities. VERIFY: `grep -n "org_scoping" backend/app/main.py && echo "FAIL" || echo "PASS"`. (cat:python; multifile:no)
- [ ] [T4] backend/ — Run a global grep across the entire backend directory to ensure zero references to `org_scoping` remain after deletion. VERIFY: `grep -r "org_scoping" backend/ && echo "FAIL" || echo "PASS"`. (cat:refactor; multifile:yes)

# --- 27B-decomposed from roadmap [2026-09-14]: Delete duplicate get_relevant_tests method in knowledge_base.py — backend/app/services/kno (review + tweak) ---
- [ ] [T1] backend/app/services/knowledge_base.py — Remove the duplicate `async def get_relevant_tests` definition located near line 244, ensuring only the original definition at line 50 remains. VERIFY: `grep -n "async def get_relevant_tests" backend/app/services/knowledge_base.py | wc -l` returns `1`. (cat:refactor; multifile:no)
- [ ] [T2] backend/tests/test_knowledge_base.py — Add a unit test that instantiates the service and asserts `get_relevant_tests` is callable and returns a list, mocking `query_knowledge_base` to prevent external calls. VERIFY: `pytest backend/tests/test_knowledge_base.py::test_get_relevant_tests_single_definition -v`. (cat:test; multifile:no)
- [ ] [T3] backend/app/services/knowledge_base.py — Verify the class structure is valid Python by importing the module and checking that `KnowledgeBaseService` has exactly one `get_relevant_tests` attribute in its namespace. VERIFY: `python -c "from backend.app.services.knowledge_base import KnowledgeBaseService; assert len([m for m in dir(KnowledgeBaseService) if m == 'get_relevant_tests']) == 1"`. (cat:python; multifile:no)
- [ ] [T4] backend/app/services/knowledge_base.py — Confirm no other methods in the file are duplicated by running a script that counts method definitions per name. VERIFY: `python -c "import ast; tree=ast.parse(open('backend/app/services/knowledge_base.py').read()); names=[n.name for n in ast.walk(tree) if isinstance(n, ast.AsyncFunctionDef)]; assert len(names)==len(set(names)), 'Duplicate methods found'". (cat:refactor; multifile:no)
- [ ] [T5] backend/app/services/knowledge_base.py — Ensure the remaining `get_relevant_tests` method correctly calls `query_knowledge_base` with `top_k=10` and returns the result. VERIFY: `pytest backend/tests/test_knowledge_base.py::test_get_relevant_tests_calls_query -v`. (cat:test; multifile:no)
