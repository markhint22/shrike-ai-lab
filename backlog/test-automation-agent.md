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
- [ ] [T4] backend/app/utils/mask_secret.py — Delete the file entirely as it contains a conflicting `mask_secret` implementation with zero production callers. VERIFY: `test ! -f backend/app/utils/mask_secret.py`. (cat:refactor; multifile:no)
- [ ] [T4] backend/tests/test_mask.py — Delete the test file for the removed `backend/app/utils/mask.py` module. VERIFY: `test ! -f backend/tests/test_mask.py`. (cat:test; multifile:no)
- [ ] [T4] backend/tests/test_mask_secret.py — Delete the test file for the removed `backend/app/utils/mask_secret.py` module. VERIFY: `test ! -f backend/tests/test_mask_secret.py`. (cat:test; multifile:no)
- [ ] [T4] backend/tests/test_utils_mask_secret.py — Delete the test file for the removed `backend/app/utils/mask_secret.py` module. VERIFY: `test ! -f backend/tests/test_utils_mask_secret.py`. (cat:test; multifile:no)
- [ ] [T3] backend/app/utils/redact.py — Remove the `redact_secret` function definition and any imports solely used by it, preserving `redact_secrets` and `redact_all`. VERIFY: `grep -q "def redact_secret" backend/app/utils/redact.py && exit 1 || exit 0`. (cat:refactor; multifile:no)
- [ ] [T3] backend/tests/test_utils_redact.py — Remove all test cases specifically targeting the `redact_secret` function while keeping tests for `redact_secrets` and `redact_all`. VERIFY: `grep -q "redact_secret" backend/tests/test_utils_redact.py && exit 1 || exit 0`. (cat:test; multifile:no)
- [ ] [T5] backend/app/utils/__init__.py — Remove any exports or imports of `mask`, `mask_secret`, or `redact_secret` to ensure the package no longer references deleted code. VERIFY: `grep -E "from .mask|from .mask_secret|redact_secret" backend/app/utils/__init__.py && exit 1 || exit 0`. (cat:refactor; multifile:yes)

# --- 27B-decomposed from roadmap [2026-09-14]: Add p50/p95 duration percentiles to the dashboard summary — backend/app/utils/dashboard_me (review + tweak) ---
- [ ] [T1] backend/app/utils/dashboard_metrics.py — Add `p50_duration_s` and `p95_duration_s` keys to the return dictionary of `calculate_dashboard_summary()`, using `percentile(durations, 50)` and `percentile(durations, 95)` respectively, with a guard for empty `durations` list returning 0.0. VERIFY: `python -m pytest backend/tests/test_dashboard_metrics.py::test_calculate_dashboard_summary_with_data -v` (cat:python; multifile:no)
- [ ] [T1] backend/app/utils/dashboard_metrics.py — Ensure the early-return path for empty runs in `calculate_dashboard_summary()` includes `p50_duration_s: 0.0` and `p95_duration_s: 0.0`. VERIFY: `python -m pytest backend/tests/test_dashboard_metrics.py::test_calculate_dashboard_summary_empty -v` (cat:python; multifile:no)
- [ ] [T2] backend/tests/test_dashboard_metrics.py — Add unit tests verifying that `calculate_dashboard_summary()` returns correct `p50_duration_s` and `p95_duration_s` values for a known list of durations, and that they default to 0.0 when no runs exist. VERIFY: `python -m pytest backend/tests/test_dashboard_metrics.py -v` (cat:test; multifile:no)
- [ ] [T3] backend/app/routers/test_runs.py — Update the `get_dashboard_summary` endpoint response construction to include `p50_duration_s` and `p95_duration_s` from the result of `calculate_dashboard_summary()`. VERIFY: `python -m pytest backend/tests/test_routers_test_runs.py::test_get_dashboard_summary_response_fields -v` (cat:endpoint; multifile:no)
- [ ] [T2] backend/tests/test_routers_test_runs.py — Add an integration test that mocks the database layer and asserts the JSON response of `GET /api/test-runs/dashboard-summary` contains non-null `p50_duration_s` and `p95_duration_s` fields. VERIFY: `python -m pytest backend/tests/test_routers_test_runs.py::test_get_dashboard_summary_response_fields -v` (cat:test; multifile:no)
- [ ] [T1] backend/app/utils/percentile.py — Verify that `percentile()` handles edge cases (empty list, single element) correctly to support the new dashboard metrics usage. VERIFY: `python -m pytest backend/tests/test_percentile.py -v` (cat:python; multifile:no)

# --- 27B-decomposed from roadmap [2026-09-14]: Consolidate duplicate duration-bucket helpers and add a duration-distribution histogram to (review + tweak) ---
- [ ] [T1] backend/app/utils/duration_bucket.py — Add a `distribution(durations: list[float]) -> dict[str, int]` helper that counts occurrences of each bucket label from `bucket()` for the input list. VERIFY: `pytest backend/tests/test_duration_bucket.py::test_distribution_counts -v`. (cat:python; multifile:no)
- [ ] [T2] backend/tests/test_duration_bucket.py — Add unit tests for the new `distribution` helper covering empty lists, single values, and mixed bucket ranges. VERIFY: `pytest backend/tests/test_duration_bucket.py -v`. (cat:test; multifile:no)
- [ ] [T4] backend/app/utils/elapsed_bucket.py — Delete the file as it is a duplicate implementation with zero callers outside its test. VERIFY: `test ! -f backend/app/utils/elapsed_bucket.py && echo "deleted"`. (cat:refactor; multifile:yes)
- [ ] [T4] backend/tests/test_elapsed_bucket.py — Delete the test file corresponding to the removed utility. VERIFY: `test ! -f backend/tests/test_elapsed_bucket.py && echo "deleted"`. (cat:test; multifile:yes)
- [ ] [T3] backend/app/utils/dashboard_metrics.py — Import `duration_bucket` and update `calculate_dashboard_summary()` to compute `duration_distribution` using `duration_bucket.distribution(durations)` and include it in the returned summary dict. VERIFY: `pytest backend/tests/test_dashboard_metrics.py::test_summary_includes_distribution -v`. (cat:python; multifile:no)
- [ ] [T2] backend/tests/test_dashboard_metrics.py — Add a test asserting that `calculate_dashboard_summary()` returns a `duration_distribution` key with correct counts for a known input list. VERIFY: `pytest backend/tests/test_dashboard_metrics.py::test_summary_includes_distribution -v`. (cat:test; multifile:no)
- [ ] [T3] backend/app/routers/test_runs.py — Ensure the `get_dashboard_summary` endpoint response schema or serialization explicitly includes the `duration_distribution` field from the service layer. VERIFY: `pytest backend/tests/test_test_runs_router.py::test_dashboard_response_has_distribution -v`. (cat:endpoint; multifile:no)
- [ ] [T2] backend/tests/test_test_runs_router.py — Add an integration test for the dashboard endpoint verifying the JSON response contains the `duration_distribution` object. VERIFY: `pytest backend/tests/test_test_runs_router.py::test_dashboard_response_has_distribution -v`. (cat:test; multifile:no)
