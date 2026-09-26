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

# --- 27B-decomposed from roadmap [2026-09-19]: Add unit tests for the auth Pinia store — frontend/src/stores/auth.ts (signup, login, swit (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-19]: Wire the orphaned pct() util into testRuns.js's duplicate passRate calculation — frontend/ (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-19]: `is_safe_url()`'s blocking DNS resolution runs synchronously inside async request/delivery (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-19]: Dead duplicate scheduling-due-check in `utils/schedule.py`, superseded by `cron_match.py`  (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-19]: Dead duplicate `event_matches()` in `utils/event_pattern.py` that also disagrees with the  (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-19]: Wire `throughput.tests_per_minute()` into the dashboard summary, following the exact prece (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-20]: Actually wire visual-regression diffing — the earlier "Visual-regression diff flagging" de (review + tweak) [feat:test-automation-agent-20260920-actually-wire-visual-regression-diffing-] ---

# --- 27B-decomposed from roadmap [2026-09-20]: Harden test coverage on the three lowest-covered, highest-risk routers — measured directly (review + tweak) [feat:test-automation-agent-20260920-harden-test-coverage-on-the-three-lowest] ---

# --- 27B-decomposed from roadmap [2026-09-21]: Actually wire visual-regression diffing — the earlier "Visual-regression diff flagging" de (review + tweak) [feat:test-automation-agent-20260921-actually-wire-visual-regression-diffing-] ---

# --- 27B-decomposed from roadmap [2026-09-21]: Harden test coverage on the three lowest-covered, highest-risk routers — measured directly (review + tweak) [feat:test-automation-agent-20260921-harden-test-coverage-on-the-three-lowest] ---

# --- 27B-decomposed from roadmap [2026-09-21]: Two aider-authored files landed inside `backend/app/utils/` instead of `backend/tests/`, s (review + tweak) [feat:test-automation-agent-20260921-two-aider-authored-files-landed-inside-b] ---

# --- Claude-decomposed from roadmap [2026-09-22]: Fix a live PII-masking divergence bug in email_service.py's mask_email import (review + tweak) ---

# --- Claude-decomposed from roadmap [2026-09-22]: Delete backend/app/utils/mask.py for real this time (review + tweak) ---

# --- Claude-decomposed from roadmap [2026-09-22]: Remove dead duplicate backend/app/utils/ssrf.py, superseded by ssrf_guard.py (review + tweak) ---

# --- Claude-decomposed from roadmap [2026-09-22]: git rm the still-empty backend/app/utils/schedule.py stub (review + tweak) ---

# --- Claude-decomposed from roadmap [2026-09-22]: Wire run_status.derive_run_status() into execution_engine.py (review + tweak) ---

# --- Claude-decomposed from roadmap [2026-09-22]: Remove dead duplicate kb_index builders build_index()/build_index_from_objects() (review + tweak) ---

# --- Claude-decomposed from roadmap [2026-09-22]: Remove dead format_dashboard_summary()/format_priority_score()/_format_duration() from dashboard_metrics.py (review + tweak) ---

# --- Claude-decomposed from roadmap [2026-09-22]: Remove dead backend/app/utils/pagination.py (review + tweak) ---

# --- Claude-decomposed from roadmap [2026-09-22]: Remove dead sync validate_url() wrapper in webhooks.py (review + tweak) ---

# --- Claude-decomposed refuel [2026-09-22]: Fix broken derive_run_status()/_ci_state calls in execution_engine.py's GitHub check-run update paths (real TypeError bug, silently swallowed) [feat:test-automation-agent-20260922-fix-derive-run-status-ci-check-run-bug] ---

# --- Claude-decomposed refuel [2026-09-22]: Remove dead format_dashboard_summary()/format_priority_score()/_format_duration() from dashboard_metrics.py (zero callers, duplicate test coverage across two files) [feat:test-automation-agent-20260922-remove-dead-dashboard-metrics-formatters] ---

# --- Claude-decomposed refuel [2026-09-22]: Add unit tests for the webhooks Pinia store, frontend/src/stores/webhooks.js (zero coverage today, largest untested store in the repo) [feat:test-automation-agent-20260922-webhooks-store-unit-tests] ---

# --- Claude-decomposed refuel [2026-09-22]: Add unit tests for the Vue Router auth guard, frontend/src/router/index.js (sole authorization boundary for all requiresAuth routes, zero test coverage today) [feat:test-automation-agent-20260922-router-auth-guard-unit-tests] ---

# --- Claude-decomposed refuel [2026-09-22]: Delete two dead/orphaned backend utility files (pagination.py, ssrf.py) that are already empty or fully superseded [feat:test-automation-agent-20260922-remove-dead-pagination-and-ssrf] ---

# --- Claude-decomposed refuel [2026-09-22]: Actually wire visual-regression diffing into the run pipeline and surface it end-to-end (still permanently false in production — perform_visual_regression_check() has zero callers, the report endpoint doesn't return the field, and the frontend badge doesn't exist) [feat:test-automation-agent-20260922-wire-visual-regression-end-to-end] ---

# --- Claude-decomposed refuel round 3 [2026-09-22]: Fix false-green empty test_pct.py + delete dead backend/app/utils/pct.py [feat:test-automation-agent-20260922-fix-empty-test-pct-and-delete-dead-pct] ---

# --- Claude-decomposed refuel round 3 [2026-09-22]: Wire the real backend suite_health field + suiteBadge.ts into FlakeDashboardPage.vue [feat:test-automation-agent-20260922-wire-real-suite-health-into-dashboard] ---

# --- Claude-decomposed refuel round 3 [2026-09-22]: Resolve ambiguous duplicate pct.js/pct.ts + add missing test coverage [feat:test-automation-agent-20260922-resolve-duplicate-pct-js-ts] ---

# --- Claude-decomposed refuel round 3 [2026-09-22]: Delete dead duplicate getStatusColor() in frontend/src/utils/status.ts [feat:test-automation-agent-20260922-delete-dead-status-ts] ---

# --- Claude-decomposed refuel round 3 [2026-09-22]: Extract triplicated formatDate() into a shared, tested util [feat:test-automation-agent-20260922-extract-shared-formatdate-util] ---

# --- Claude-decomposed refuel round 3 [2026-09-22]: Add unit tests for the orgs Pinia store [feat:test-automation-agent-20260922-orgs-store-unit-tests] ---

# --- Claude-decomposed refuel round 3 [2026-09-22]: Add unit tests for the apiKeys Pinia store [feat:test-automation-agent-20260922-apikeys-store-unit-tests] ---

# --- Claude-decomposed refuel round 3 [2026-09-22]: Add unit tests for the billing Pinia store [feat:test-automation-agent-20260922-billing-store-unit-tests] ---

# --- Claude-decomposed refuel round 3 [2026-09-22]: Add unit tests for the selfHealing Pinia store [feat:test-automation-agent-20260922-selfhealing-store-unit-tests] ---

# --- Claude-decomposed refuel round 3 [2026-09-22]: Add unit tests for the usageMetrics Pinia store [feat:test-automation-agent-20260922-usagemetrics-store-unit-tests] ---

# --- Claude-decomposed refuel round 3 [2026-09-22]: Add unit tests for the useAsyncState composable [feat:test-automation-agent-20260922-useasyncstate-composable-tests] ---

# --- Claude-decomposed refuel round 3 [2026-09-22]: Remove dead calculate_trend_scores() from flake_trend.py [feat:test-automation-agent-20260922-remove-dead-calculate-trend-scores] ---

# --- Claude-decomposed refuel round 3 [2026-09-22]: Remove duplicate chunk()/chunk_list() (list_chunk.py vs chunking.py) [feat:test-automation-agent-20260922-remove-dead-chunking-py] ---

# --- Claude-decomposed refuel round 3 [2026-09-22]: Consolidate divergent parse_bool.py vs env_flag.py truthy() [feat:test-automation-agent-20260922-consolidate-parse-bool-env-flag] ---

# --- Claude-decomposed refuel round 3 [2026-09-22]: Remove dead split_name.py [feat:test-automation-agent-20260922-remove-dead-split-name] ---

# --- Claude-decomposed refuel round 3 [2026-09-22]: Make the upload size limit configurable via parse_bytes/human_bytes [feat:test-automation-agent-20260922-configurable-upload-size-limit] ---

# --- Claude-decomposed refuel round 3 [2026-09-22]: Delete the now-fully-dead sanitize() left behind in sanitize_filename.py [feat:test-automation-agent-20260922-delete-dead-sanitize-loser] ---

# --- Claude-decomposed refuel round 3 [2026-09-22]: Remove orphaned utils batch 1 (ordinal, parse_kv, count_words, pct_bar, smart_title) [feat:test-automation-agent-20260922-remove-orphaned-utils-batch-1] ---

# --- Claude-decomposed refuel round 3 [2026-09-22]: Remove orphaned utils batch 2 (group_consecutive, moving_average, percent_change, stable_hash, duration_parse, time_ago) [feat:test-automation-agent-20260922-remove-orphaned-utils-batch-2] ---

# --- grounded research pass (2026-09-24): fresh-streak refill after backlog file emptied out to header-only records; META backlog had 0 real unchecked items, live queue (OVERNIGHT_PROGRESS.md) had 34 unchecked (several AUTO-SKIP/staged) ---

# --- 27B-decomposed from roadmap [2026-09-25]: Add a test-plan field to the CI Integrations dashboard forms so GitHub-triggered and cron- (review + tweak) [feat:test-automation-agent-20260925-add-a-test-plan-field-to-the-ci-integrat] ---

# --- 27B-decomposed from roadmap [2026-09-25]: Replace fabricated duration/cost estimates in `GET /api/usage/metrics` with real data alre (review + tweak) [feat:test-automation-agent-20260925-replace-fabricated-duration-cost-estimat] ---
- [ ] [T2] backend/tests/test_duration.py — Create test file with unit tests for `sum_duration_minutes`, `sum_duration_minutes_with_fallback`, and `estimate_cost_from_ai_calls`. VERIFY: python -m pytest backend/tests/test_duration.py -v (cat:test; multifile:no) [feat:test-automation-agent-20260925-replace-fabricated-duration-cost-estimat]

# --- 27B-decomposed from roadmap [2026-09-25]: **[HUMAN/design]** Track real per-run LLM token usage so `/api/usage/metrics` cost figures (review + tweak) [feat:test-automation-agent-20260925-human-design-track-real-per-run-llm-toke] ---
- [ ] [T1] backend/app/utils/token_usage.py — Add dataclass `TokenUsage` with fields `input_tokens: int`, `output_tokens: int`, and method `total_tokens` returning sum. VERIFY: python -c "from backend.app.utils.token_usage import TokenUsage; t=TokenUsage(10,5); assert t.total_tokens==15" (cat:python; multifile:no) [feat:test-automation-agent-20260925-human-design-track-real-per-run-llm-toke]
- [ ] [T2] backend/app/utils/token_aggregator.py — Add function `aggregate_usage(usages: list[TokenUsage]) -> TokenUsage` that sums input and output tokens across a list. VERIFY: python -c "from backend.app.utils.token_aggregator import aggregate_usage; from backend.app.utils.token_usage import TokenUsage; assert aggregate_usage([TokenUsage(1,2), TokenUsage(3,4)]).total_tokens==10" (cat:python; multifile:no) [feat:test-automation-agent-20260925-human-design-track-real-per-run-llm-toke]
- [ ] [T3] backend/app/models/test_run.py — Add columns `llm_input_tokens` (Integer, default 0) and `llm_output_tokens` (Integer, default 0) to the `TestRun` model. VERIFY: grep -q "llm_input_tokens" backend/app/models/test_run.py && grep -q "llm_output_tokens" backend/app/models/test_run.py (cat:schema; multifile:no) [feat:test-automation-agent-20260925-human-design-track-real-per-run-llm-toke]
- [ ] [T4] backend/alembic/versions/0002_add_token_usage_columns.py — Create migration adding `llm_input_tokens` and `llm_output_tokens` columns to `test_runs` table. VERIFY: grep -q "add_column" backend/alembic/versions/0002_add_token_usage_columns.py && grep -q "llm_input_tokens" backend/alembic/versions/0002_add_token_usage_columns.py (cat:schema; multifile:no) [feat:test-automation-agent-20260925-human-design-track-real-per-run-llm-toke]
- [ ] [T5] backend/app/services/llm_service.py — Modify `chat_completion` to return a tuple `(response, TokenUsage)` where `TokenUsage` is extracted from the API response's `usage` field. VERIFY: grep -q "return.*response.*usage" backend/app/services/llm_service.py || grep -q "TokenUsage" backend/app/services/llm_service.py (cat:python; multifile:no) [feat:test-automation-agent-20260925-human-design-track-real-per-run-llm-toke]

# --- 27B-decomposed from roadmap [2026-09-25]: Expose browser selection on the actual upload flow, not just the separate YAML-editor tool (review + tweak) [feat:test-automation-agent-20260925-expose-browser-selection-on-the-actual-u] ---
- [ ] [T1] backend/app/utils/browser_defaults.py — Create module exporting `DEFAULT_BROWSER = "chromium"` and `SUPPORTED_BROWSERS = ["chromium", "firefox", "webkit"]` constants. VERIFY: `cd backend && python -c "from app.utils.browser_defaults import DEFAULT_BROWSER, SUPPORTED_BROWSERS; assert DEFAULT_BROWSER == 'chromium' and len(SUPPORTED_BROWSERS) == 3"`. (cat:python; multifile:no) [feat:test-automation-agent-20260925-expose-browser-selection-on-the-actual-u]
- [ ] [T1] backend/app/utils/browser_defaults_test.py — Create unit test verifying `SUPPORTED_BROWSERS` matches the set defined in `backend/app/services/playwright_service.py` and that `DEFAULT_BROWSER` is a valid member. VERIFY: `cd backend && pytest app/utils/browser_defaults_test.py -v`. (cat:test; multifile:no) [feat:test-automation-agent-20260925-expose-browser-selection-on-the-actual-u]
- [ ] [T2] frontend/src/utils/browserTypes.ts — Create TypeScript utility exporting `BROWSER_TYPES = ['chromium', 'firefox', 'webkit'] as const` and `BrowserType` type alias. VERIFY: `cd frontend && npx tsc --noEmit src/utils/browserTypes.ts`. (cat:typescript; multifile:no) [feat:test-automation-agent-20260925-expose-browser-selection-on-the-actual-u]
- [ ] [T3] frontend/src/pages/UploadPage.vue — Add a `<select>` element bound to a new `browserType` ref (default 'chromium') using options from `frontend/src/utils/browserTypes.ts`, placed near the file input. VERIFY: `grep -n "browserType" frontend/src/pages/UploadPage.vue | wc -l` returns > 0 and `grep -n "BROWSER_TYPES" frontend/src/pages/UploadPage.vue` exists. (cat:vue; multifile:no) [feat:test-automation-agent-20260925-expose-browser-selection-on-the-actual-u]
- [ ] [T3] frontend/src/pages/UploadPage.vue — Modify the plan parsing/upload logic to inject `browser_type: this.browserType` into the final JSON/YAML payload before sending to the backend API. VERIFY: `grep -n "browser_type" frontend/src/pages/UploadPage.vue` exists and `grep -n "payload\[.browser_type.\]" frontend/src/pages/UploadPage.vue` or equivalent assignment logic is present. (cat:vue; multifile:no) [feat:test-automation-agent-20260925-expose-browser-selection-on-the-actual-u]
- [ ] [T2] frontend/src/components/BrowserSelector.vue — Create a reusable Vue component accepting `modelValue` and emitting `update:modelValue`, rendering the browser dropdown using `BROWSER_TYPES`. VERIFY: `cd frontend && npx vue-tsc --noEmit src/components/BrowserSelector.vue`. (cat:vue; multifile:no) [feat:test-automation-agent-20260925-expose-browser-selection-on-the-actual-u]
- [ ] [T3] frontend/src/pages/UploadPage.vue — Refactor to use the new `BrowserSelector` component instead of the inline `<select>` added in the previous step, ensuring two-way binding. VERIFY: `grep -n "BrowserSelector" frontend/src/pages/UploadPage.vue` exists and `grep -n "<select" frontend/src/pages/UploadPage.vue` returns 0 results for browser selection. (cat:vue; multifile:no) [feat:test-automation-agent-20260925-expose-browser-selection-on-the-actual-u]
- [ ] [T1] frontend/src/utils/browserTypes.test.ts — Create Vitest unit test verifying `BROWSER_TYPES` contains exactly 'chromium', 'firefox', and 'webkit'. VERIFY: `cd frontend && npx vitest run src/utils/browserTypes.test.ts`. (cat:test; multifile:no) [feat:test-automation-agent-20260925-expose-browser-selection-on-the-actual-u]
- [ ] [T3] backend/app/routers/uploads.py — Ensure the upload endpoint passes `browser_type` from the request body to the execution engine context if present, defaulting to 'chromium' if missing. VERIFY: `cd backend && pytest tests/test_uploads_router.py -k test_browser_type_passthrough -v` (assuming test exists or create minimal check via `grep -n "browser_type" backend/app/routers/uploads.py`). (cat:endpoint; multifile:no) [feat:test-automation-agent-20260925-expose-browser-selection-on-the-actual-u]

# --- 27B-decomposed from roadmap [2026-09-26]: **[HUMAN/design]** CI schedules/integrations each embed an independent raw `test_plan` cop (review + tweak) [feat:test-automation-agent-20260926-human-design-ci-schedules-integrations-e] ---
- [ ] [T1] backend/app/utils/plan_ref.py — Add `parse_plan_ref(data: dict) -> tuple[str, str | None]` that extracts `upload_id` if present, else returns `("embedded", None)`. VERIFY: `pytest backend/tests/test_plan_ref.py::test_parse_upload_ref -v`. (cat:python; multifile:no) [feat:test-automation-agent-20260926-human-design-ci-schedules-integrations-e]
- [ ] [T1] backend/app/utils/plan_snapshot.py — Add `create_plan_snapshot(plan_data: dict) -> str` that returns a stable SHA256 hash of the canonical JSON representation. VERIFY: `pytest backend/tests/test_plan_snapshot.py::test_stable_hash -v`. (cat:python; multifile:no) [feat:test-automation-agent-20260926-human-design-ci-schedules-integrations-e]
- [ ] [T2] backend/app/models/ci.py — Add `plan_source: Mapped[str]` (enum: 'upload', 'embedded') and `plan_upload_id: Mapped[Optional[int]]` to `GitHubIntegration` and `ScheduledRun`. VERIFY: `alembic revision --autogenerate -m "add plan source fields" && alembic upgrade head`. (cat:schema; multifile:no) [feat:test-automation-agent-20260926-human-design-ci-schedules-integrations-e]
- [ ] [T3] backend/app/services/ci_service.py — Implement `resolve_test_plan(db, integration) -> dict` that fetches `Upload` if `plan_source == 'upload'`, else returns embedded `default_test_plan`. VERIFY: `pytest backend/tests/test_ci_service.py::test_resolve_upload_plan -v`. (cat:python; multifile:no) [feat:test-automation-agent-20260926-human-design-ci-schedules-integrations-e]
- [ ] [T3] backend/app/routers/ci.py — Update `create_integration` and `create_schedule` endpoints to accept optional `upload_id`, validate existence, and set `plan_source`/`plan_upload_id` accordingly. VERIFY: `pytest backend/tests/test_ci_router.py::test_create_with_upload_ref -v`. (cat:endpoint; multifile:no) [feat:test-automation-agent-20260926-human-design-ci-schedules-integrations-e]
- [ ] [T3] backend/app/services/scheduling.py — Modify `execute_scheduled_run` to call `resolve_test_plan` instead of reading raw `test_plan` JSON directly. VERIFY: `pytest backend/tests/test_scheduling.py::test_schedule_uses_resolved_plan -v`. (cat:python; multifile:no) [feat:test-automation-agent-20260926-human-design-ci-schedules-integrations-e]
- [ ] [T4] backend/app/services/ci_service.py — Add `validate_upload_integrity(db, upload_id) -> bool` that checks if the referenced upload still exists and hasn't been marked deleted. VERIFY: `pytest backend/tests/test_ci_service.py::test_validate_deleted_upload -v`. (cat:python; multifile:no) [feat:test-automation-agent-20260926-human-design-ci-schedules-integrations-e]
- [ ] [T4] backend/app/routers/uploads.py — Add `on_delete` hook logic to prevent deletion of `Upload` rows referenced by active `GitHubIntegration` or `ScheduledRun` records. VERIFY: `pytest backend/tests/test_uploads_router.py::test_prevent_delete_referenced_upload -v`. (cat:endpoint; multifile:yes) [feat:test-automation-agent-20260926-human-design-ci-schedules-integrations-e]

# --- 27B-decomposed from roadmap [2026-09-26]: Add duration-regression detection per test, mirroring the already-shipped visual-regressio (review + tweak) [feat:test-automation-agent-20260926-add-duration-regression-detection-per-te] ---
- [ ] [T1] backend/app/utils/duration_regression.py — Implement `is_duration_regressed(current_ms: int, history_ms: list[int], threshold_pct: float = 50.0) -> bool` that returns True if current_ms exceeds the trailing average of history_ms by more than threshold_pct. VERIFY: pytest backend/tests/test_duration_regression.py -v (cat:python; multifile:no) [feat:test-automation-agent-20260926-add-duration-regression-detection-per-te]
- [ ] [T2] backend/tests/test_duration_regression.py — Create unit tests for `is_duration_regressed` covering normal, regression, empty history, and single-item history cases. VERIFY: pytest backend/tests/test_duration_regression.py -v (cat:test; multifile:no) [feat:test-automation-agent-20260926-add-duration-regression-detection-per-te]
- [ ] [T3] backend/app/services/execution_engine.py — Import `is_duration_regressed` and update the test run completion logic to calculate duration regression against prior runs of the same `test_plan_name`+`test_name`, storing the boolean result in the `TestRun` model's new field. VERIFY: pytest backend/tests/test_execution_engine.py -v (cat:python; multifile:no) [feat:test-automation-agent-20260926-add-duration-regression-detection-per-te]
- [ ] [T4] backend/app/models/test_run.py — Add a nullable boolean column `duration_regression` to the `TestRun` SQLAlchemy model and create an Alembic migration script to add the column to the database. VERIFY: alembic upgrade head && python -c "from backend.app.models.test_run import TestRun; assert hasattr(TestRun, 'duration_regression')" (cat:schema; multifile:yes) [feat:test-automation-agent-20260926-add-duration-regression-detection-per-te]
- [ ] [T5] backend/app/routers/test_runs.py — Update the `GET /api/test-runs/{run_id}` response schema to include the `duration_regression` field from the database model. VERIFY: pytest backend/tests/test_test_runs_router.py -v (cat:endpoint; multifile:no) [feat:test-automation-agent-20260926-add-duration-regression-detection-per-te]
