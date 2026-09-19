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

# --- 27B-decomposed from roadmap [2026-09-14]: Remove dead org_scoping.py — backend/app/utils/org_scoping.py's `can_access`/`require_owne (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-14]: Delete duplicate get_relevant_tests method in knowledge_base.py — backend/app/services/kno (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-14]: Remove dead duplicate duration_format.py — backend/app/utils/duration_format.py's `format_ (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-14]: Fix test-plan selection endpoint that always returns empty — `POST /api/test-plans/{plan_i (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-14]: Wire step_histogram helpers into orchestrator's difficulty heuristic — backend/app/agents/ (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-14]: Remove dead duplicate webhook event-matcher — backend/app/utils/event_pattern.py's `event_ (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-14]: Remove dead duplicate result-summarization helpers — backend/app/utils/allure_summary.py's (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-14]: Remove three-way duplicate/conflicting secret-masking helpers — backend/app/utils/mask.py' (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-14]: Add p50/p95 duration percentiles to the dashboard summary — backend/app/utils/dashboard_me (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-14]: Consolidate duplicate duration-bucket helpers and add a duration-distribution histogram to (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-17]: Fix the non-functional upload confirm/status/list/delete flow — `POST /api/uploads/test-pl (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-17]: Wire kb_index.build_index() into a real endpoint — backend/app/utils/kb_index.py's `build_ (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-18]: Add unit tests for the webhooks Pinia store — frontend/src/stores/webhooks.js (121 lines:  (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-18]: Remove dead flakes_quarantine.py helpers — backend/app/utils/flakes_quarantine.py's `apply (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-18]: Consolidate divergent, zero-caller sanitize-filename helpers — backend/app/utils/sanitize_ (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-18]: Remove dead orphaned frontend/src/views/TestRunDetailPage.vue — this 17-line file (the onl (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-18]: Wire the Upload model into the upload confirm/status/list/delete endpoints — round-5's fin (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-18]: Finish wiring kb_index.build_index()/build_index_from_rows() — round-5's "Wire kb_index.bu (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-18]: Fix the dead-code-removal mechanism leaving empty tracked stub files instead of deleting t (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-18]: Remove dead duplicate PR-comment helpers left behind in execution_engine.py — the real, wi (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-18]: Add unit tests for the Vue Router auth guard — frontend/src/router/index.js's `router.befo (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-18]: Add unit tests for the ci Pinia store — frontend/src/stores/ci.js (109 lines: fetchIntegra (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-18]: Wire plan_normalizer.normalize_test_plan() into the upload/test-plan flow — backend/app/ut (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-18]: Remove the live-request-path call to process_dead_code_removal() from the orchestrator's Y (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-18]: Fix the SSRF hole in webhook URL validation — backend/app/routers/webhooks.py's `validate_ (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-18]: Wire mask_email() into the three log lines that print raw customer email addresses — backe (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-18]: Add jitter to webhook delivery retry backoff — backend/app/utils/backoff_jitter.py's `jitt (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-19]: Wire GET /api/test-runs/dashboard/summary into DashboardPage.vue instead of computing wron (review + tweak) ---
- [ ] [T2] frontend/src/components/StatTile.vue — Create a reusable `StatTile` component that accepts `label`, `value`, and `icon` props, replacing the hardcoded HTML blocks in DashboardPage. VERIFY: `npx vitest run src/components/StatTile.test.js`. (cat:vue; multifile:no)
- [ ] [T3] frontend/src/pages/DashboardPage.vue — Replace the local computation of stats using `testRuns.value.length` and filters with bindings to `store.dashboardSummary` fields (`total_runs`, `pass_rate`, `total_failed`, `avg_duration_s`). VERIFY: `npx vitest run src/pages/DashboardPage.test.js -t "uses dashboard summary"`. (cat:vue; multifile:no)
- [ ] [T3] frontend/src/pages/DashboardPage.vue — Update the `onMounted` hook to call `store.fetchDashboardSummary()` instead of relying solely on `fetchTestRuns`, ensuring the summary data is loaded on page entry. VERIFY: `npx vitest run src/pages/DashboardPage.test.js -t "calls fetchDashboardSummary"`. (cat:vue; multifile:no)
- [ ] [T4] frontend/src/pages/DashboardPage.vue — Remove the now-redundant local variables and computed properties that derived stats from `testRuns` (lines 25, 35, 45, 55) to prevent future confusion about data sources. VERIFY: `grep -c "testRuns.value.length" frontend/src/pages/DashboardPage.vue` returns 0. (cat:vue; multifile:no)
- [ ] [T5] frontend/src/stores/testRuns.js — Refactor `fetchTestRuns` to explicitly pass a `limit` parameter or document that it is for list view only, and ensure `dashboardSummary` is independent of the list fetch to avoid race conditions. VERIFY: `npx vitest run src/stores/testRuns.test.js -t "independent summary fetch"`. (cat:typescript; multifile:yes)

# --- 27B-decomposed from roadmap [2026-09-19]: Add unit tests for the auth Pinia store — frontend/src/stores/auth.ts (signup, login, swit (review + tweak) ---
- [ ] [T1] frontend/src/stores/__tests__/auth.test.ts — Create test file with mocked axios and Pinia setup, implementing a successful login test that verifies `user`, `token`, and `orgId` are set in the store and corresponding keys are written to localStorage. VERIFY: `npx vitest run frontend/src/stores/__tests__/auth.test.ts -t "successful login"`. (cat:test; multifile:no)
- [ ] [T1] frontend/src/stores/__tests__/auth.test.ts — Add a test case for successful signup that asserts the store state is populated with `user`, `token`, and `orgId` and that localStorage contains all three keys. VERIFY: `npx vitest run frontend/src/stores/__tests__/auth.test.ts -t "successful signup"`. (cat:test; multifile:no)
- [ ] [T1] frontend/src/stores/__tests__/auth.test.ts — Add a test case for failed login that mocks an axios error with `response.data.detail`, asserting the store `error` field is set and `isAuthenticated` remains false. VERIFY: `npx vitest run frontend/src/stores/__tests__/auth.test.ts -t "failed login"`. (cat:test; multifile:no)
- [ ] [T1] frontend/src/stores/__tests__/auth.test.ts — Add a test case for failed signup that mocks an axios error, asserting the store `error` field is populated from `err.response.data.detail` and `isAuthenticated` is false. VERIFY: `npx vitest run frontend/src/stores/__tests__/auth.test.ts -t "failed signup"`. (cat:test; multifile:no)
- [ ] [T1] frontend/src/stores/__tests__/auth.test.ts — Add a test case for `switchOrg` that mocks a successful API response, asserting the store updates `orgId`, `user`, and `token` and persists the new session to localStorage. VERIFY: `npx vitest run frontend/src/stores/__tests__/auth.test.ts -t "switchOrg success"`. (cat:test; multifile:no)
- [ ] [T1] frontend/src/stores/__tests__/auth.test.ts — Add a test case for `logout` that asserts all three localStorage keys are removed and store fields (`user`, `token`, `orgId`) are reset to null/undefined. VERIFY: `npx vitest run frontend/src/stores/__tests__/auth.test.ts -t "logout"`. (cat:test; multifile:no)
- [ ] [T1] frontend/src/stores/__tests__/auth.test.ts — Add a test case for the axios Bearer token interceptor that verifies the request header is set to `Bearer <token>` when a token exists in the store. VERIFY: `npx vitest run frontend/src/stores/__tests__/auth.test.ts -t "axios interceptor"`. (cat:test; multifile:no)
- [ ] [T1] frontend/src/stores/__tests__/auth.test.ts — Add a test case for `isAuthenticated` getter that asserts it returns true only when both `token` and `user` are present, covering the regression where user was not persisted. VERIFY: `npx vitest run frontend/src/stores/__tests__/auth.test.ts -t "isAuthenticated"`. (cat:test; multifile:no)

# --- 27B-decomposed from roadmap [2026-09-19]: Wire the orphaned pct() util into testRuns.js's duplicate passRate calculation — frontend/ (review + tweak) ---
- [ ] [T1] frontend/src/utils/pct.ts — Verify existing `pct` implementation handles zero denominator and rounding correctly. VERIFY: `npx vitest run frontend/src/utils/pct.test.ts`. (cat:typescript; multifile:no)
- [ ] [T2] frontend/src/stores/testRuns.js — Add import statement for `pct` from `../utils/pct` at the top of the file. VERIFY: `grep -q "import { pct } from '../utils/pct'" frontend/src/stores/testRuns.js`. (cat:typescript; multifile:no)
- [ ] [T3] frontend/src/stores/testRuns.js — Replace inline `total > 0 ? Math.round((passed / total) * 100) : 0` logic in `passRate` computed property with `pct(passed, total)`. VERIFY: `grep -q "pct(passed, total)" frontend/src/stores/testRuns.js && ! grep -q "Math.round((passed / total) \* 100)" frontend/src/stores/testRuns.js`. (cat:refactor; multifile:no)
- [ ] [T4] frontend/src/stores/testRuns.test.js — Add unit test verifying `passRate` returns 0 when `total` is 0 using the refactored logic. VERIFY: `npx vitest run frontend/src/stores/testRuns.test.js -t "passRate zero total"`. (cat:test; multifile:no)
- [ ] [T5] frontend/src/stores/testRuns.test.js — Add unit test verifying `passRate` returns correct rounded percentage for non-zero totals. VERIFY: `npx vitest run frontend/src/stores/testRuns.test.js -t "passRate calculation"`. (cat:test; multifile:no)

# --- 27B-decomposed from roadmap [2026-09-19]: `is_safe_url()`'s blocking DNS resolution runs synchronously inside async request/delivery (review + tweak) ---
- [ ] [T1] backend/app/utils/ssrf_guard.py — Add `async def is_safe_url_async(url: str) -> bool` that wraps the existing `is_safe_url` logic in `asyncio.to_thread` to offload blocking DNS resolution from the event loop. VERIFY: `python -m pytest backend/tests/test_ssrf_guard.py::test_is_safe_url_async_offloads_to_thread -v`. (cat:python; multifile:no)
- [ ] [T2] backend/tests/test_ssrf_guard.py — Create test file with a mock for `socket.getaddrinfo` that sleeps 0.1s, asserting that `is_safe_url_async` completes without blocking the event loop (using `asyncio.wait_for` or concurrent task timing). VERIFY: `python -m pytest backend/tests/test_ssrf_guard.py::test_is_safe_url_async_non_blocking -v`. (cat:test; multifile:no)
- [ ] [T3] backend/app/services/notification_dispatcher.py — Update `_send_request` to replace the synchronous `is_safe_url(url)` call with `await is_safe_url_async(url)` and import the new async utility. VERIFY: `python -m pytest backend/tests/test_notification_dispatcher.py::test_send_request_uses_async_ssrf_check -v`. (cat:python; multifile:no)
- [ ] [T3] backend/app/routers/webhooks.py — Update `register_webhook` to replace the synchronous `validate_url(url)` call (which internally calls `is_safe_url`) with an async-safe validation path using `is_safe_url_async`. VERIFY: `python -m pytest backend/tests/test_webhooks.py::test_register_webhook_uses_async_validation -v`. (cat:python; multifile:no)
- [ ] [T4] backend/app/services/notification_dispatcher.py — Add a regression test in `backend/tests/test_notification_dispatcher.py` that simulates a slow DNS resolution (mocking `socket.getaddrinfo` with a delay) and asserts that a concurrent dummy request completes within a strict timeout, proving the event loop is not stalled. VERIFY: `python -m pytest backend/tests/test_notification_dispatcher.py::test_slow_dns_does_not_stall_event_loop -v`. (cat:test; multifile:yes)
- [ ] [T2] backend/app/utils/ssrf_guard.py — Ensure `is_safe_url` remains synchronous for backward compatibility but is explicitly marked as blocking in docstring, and verify no other direct synchronous calls to `socket.getaddrinfo` exist in the module. VERIFY: `grep -n "getaddrinfo" backend/app/utils/ssrf_guard.py | wc -l` returns 1 (only inside the function body) and `python -m mypy backend/app/utils/ssrf_guard.py`. (cat:refactor; multifile:no)
- [ ] [T1] backend/tests/test_webhooks.py — Add a unit test for `register_webhook` that mocks `is_safe_url_async` to return `False` and verifies the endpoint returns 400 without blocking, confirming the async path is wired correctly. VERIFY: `python -m pytest backend/tests/test_webhooks.py::test_register_webhook_rejects_unsafe_url_async -v`. (cat:test; multifile:no)
