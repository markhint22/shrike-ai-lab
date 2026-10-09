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

# --- 27B-decomposed from roadmap [2026-09-25]: **[HUMAN/design]** Track real per-run LLM token usage so `/api/usage/metrics` cost figures (review + tweak) [feat:test-automation-agent-20260925-human-design-track-real-per-run-llm-toke] ---

# --- 27B-decomposed from roadmap [2026-09-25]: Expose browser selection on the actual upload flow, not just the separate YAML-editor tool (review + tweak) [feat:test-automation-agent-20260925-expose-browser-selection-on-the-actual-u] ---

# --- 27B-decomposed from roadmap [2026-09-26]: **[HUMAN/design]** CI schedules/integrations each embed an independent raw `test_plan` cop (review + tweak) [feat:test-automation-agent-20260926-human-design-ci-schedules-integrations-e] ---

# --- 27B-decomposed from roadmap [2026-09-26]: Add duration-regression detection per test, mirroring the already-shipped visual-regressio (review + tweak) [feat:test-automation-agent-20260926-add-duration-regression-detection-per-te] ---

# --- 27B-decomposed from roadmap [2026-09-26]: Add an HTML export option to the test-run report, closing the gap against PRODUCT_ROADMAP. (review + tweak) [feat:test-automation-agent-20260926-add-an-html-export-option-to-the-test-ru] ---


# --- grounded research pass (2026-09-27): backlog hit zero open items; fresh batch from a real codebase read (backend routers/services/utils, frontend pages/stores). Focus per repo's own header note ("Backend is saturated with tests; the real release gaps are the thin Vue frontend") plus a confirmed recurrence of the dead-code-removal-leaves-orphan bug the repo has hit before. ---

# --- 27B-decomposed from roadmap [2026-09-27]: Dead-code cleanup batch A — an emptied-not-deleted file and 3 orphaned pure utils left behind by prior "remove orphaned X" commits that deleted only the paired test file (review + tweak) [feat:test-automation-agent-20260927-dead-code-cleanup-batch-a] ---

# --- 27B-decomposed from roadmap [2026-09-27]: Dead-code cleanup batch B — 4 more orphaned pure utils, same incomplete-removal signature (review + tweak) [feat:test-automation-agent-20260927-dead-code-cleanup-batch-b] ---

# --- 27B-decomposed from roadmap [2026-09-27]: Dead-code cleanup batch C — 2 more orphaned pure utils plus 2 dead duplicate functions living inside otherwise-real, used files (review + tweak) [feat:test-automation-agent-20260927-dead-code-cleanup-batch-c] ---

# --- 27B-decomposed from roadmap [2026-09-27]: Fix 3 misplaced test files under app/utils/ that pytest's own config silently never runs — confirmed via OVERNIGHT_PROGRESS.md:1307, where a properly-targeted `backend/tests/test_html_report.py` item was auto-retired as "dead path" because this misplaced file already squatted a similar name (review + tweak) [feat:test-automation-agent-20260927-fix-misplaced-uncollected-tests] ---

# --- 27B-decomposed from roadmap [2026-09-27]: Resolve a stale duplicate frontend test file for FlakeDashboardPage — same "two files, one drifted" pattern the repo already fixed once for pct.js/pct.ts (review + tweak) [feat:test-automation-agent-20260927-resolve-flakedashboard-duplicate-spec] ---

# --- 27B-decomposed from roadmap [2026-09-27]: Add unit test coverage for untested Vue pages, batch A (auth + account-management pages, zero existing test files) (review + tweak) [feat:test-automation-agent-20260927-frontend-page-tests-batch-a] ---

# --- 27B-decomposed from roadmap [2026-09-27]: Add unit test coverage for untested Vue pages, batch B (ops/monitoring dashboards, zero existing test files) (review + tweak) [feat:test-automation-agent-20260927-frontend-page-tests-batch-b] ---

# --- 27B-decomposed from roadmap [2026-09-27]: Frontend polish — lightweight smoke tests for the remaining untested pages/components (mostly-static content, small diffs) (review + tweak) [feat:test-automation-agent-20260927-frontend-polish-tests] ---

# --- 27B-decomposed from roadmap [2026-09-30]: Replace retired Claude model IDs (every LLM call 404s) — backend/app/core/config.py lines  (review + tweak) [feat:test-automation-agent-20260930-replace-retired-claude-model-ids-every-l] ---

# --- 27B-decomposed from roadmap [2026-09-30]: Stop the sync Anthropic client from blocking the event loop — backend/app/services/llm_ser (review + tweak) [feat:test-automation-agent-20260930-stop-the-sync-anthropic-client-from-bloc] ---

# --- 27B-decomposed from roadmap [2026-09-30]: Authenticate and tenant-scope the run WebSocket and broadcast/notify endpoints — backend/a (review + tweak) [feat:test-automation-agent-20260930-authenticate-and-tenant-scope-the-run-we] ---

# --- 27B-decomposed from roadmap [2026-09-30]: Fix cross-tenant baseline lookup in visual regression — backend/app/services/execution_eng (review + tweak) [feat:test-automation-agent-20260930-fix-cross-tenant-baseline-lookup-in-visu] ---

# --- 27B-decomposed from roadmap [2026-09-30]: Fix cross-tenant data mixing in the flake index — backend/app/services/flake_detection.py  (review + tweak) [feat:test-automation-agent-20260930-fix-cross-tenant-data-mixing-in-the-flak] ---

# --- 27B-decomposed from roadmap [2026-09-30]: Enforce billing quota and metering on every run-creation path — only backend/app/routers/t (review + tweak) [feat:test-automation-agent-20260930-enforce-billing-quota-and-metering-on-ev] ---

# --- 27B-decomposed from roadmap [2026-09-30]: Derive tier and role from the DB, not the 24h JWT claims — backend/app/core/auth.py `get_c (review + tweak) [feat:test-automation-agent-20260930-derive-tier-and-role-from-the-db-not-the] ---

# --- 27B-decomposed from roadmap [2026-09-30]: Actually apply rate limiting (slowapi limiter is created but never used) — backend/app/mai (review + tweak) [feat:test-automation-agent-20260930-actually-apply-rate-limiting-slowapi-lim] ---

# --- 27B-decomposed from roadmap [2026-10-01]: Harden Stripe webhook handling — backend/app/services/billing.py `apply_webhook_event`: no (review + tweak) [feat:test-automation-agent-20261001-harden-stripe-webhook-handling-backend-a] ---

# --- 27B-decomposed from roadmap [2026-10-01]: Enforce a global browser concurrency cap — backend/app/services/playwright_service.py crea (review + tweak) [feat:test-automation-agent-20261001-enforce-a-global-browser-concurrency-cap] ---

# --- 27B-decomposed from roadmap [2026-10-02]: Block SSRF via test-plan app_url and navigate steps — backend/app/agents/executor.py (line (review + tweak) [feat:test-automation-agent-20261002-block-ssrf-via-test-plan-app-url-and-nav] ---
- [ ] [T2] backend/app/services/test_plan_validation.py — Import `is_safe_url_async` from `backend.app.utils.ssrf_guard` and validate `plan["app_url"]` against SSRF rules during plan validation, raising a specific validation error if unsafe. VERIFY: pytest backend/tests/test_test_plan_validation.py::test_app_url_ssrf_blocked -v (cat:python; multifile:no) [feat:test-automation-agent-20261002-block-ssrf-via-test-plan-app-url-and-nav]
- [ ] [T3] backend/app/services/test_plan_validation.py — Extend validation to iterate through all `steps` in the plan and validate any step with type `navigate` or containing `url` field against SSRF rules. VERIFY: pytest backend/tests/test_test_plan_validation.py::test_navigate_step_ssrf_blocked -v (cat:python; multifile:no) [feat:test-automation-agent-20261002-block-ssrf-via-test-plan-app-url-and-nav]
- [ ] [T5] backend/app/agents/executor.py — Implement a Playwright route handler (`page.route`) that intercepts all requests, resolves the final URL after redirects, and aborts the request if the resolved host is internal (localhost, 169.254.x.x, 10.x, 172.16-31.x, 192.168.x) or matches 6PN patterns. VERIFY: pytest backend/tests/test_executor_ssrf_guard.py::test_redirect_to_internal_blocked -v (cat:python; multifile:no) [feat:test-automation-agent-20261002-block-ssrf-via-test-plan-app-url-and-nav]

# --- 27B-decomposed from roadmap [2026-10-02]: Recover runs orphaned by restarts/deploys — execution_engine.py tracks live runs only in t (review + tweak) [feat:test-automation-agent-20261002-recover-runs-orphaned-by-restarts-deploy] ---

# --- 27B-decomposed from roadmap [2026-10-02]: Add graceful-shutdown drain to the app lifespan — `backend/app/main.py`'s lifespan `yield` (review + tweak) [feat:test-automation-agent-20261002-add-graceful-shutdown-drain-to-the-app-l] ---

# --- 27B-decomposed from roadmap [2026-10-02]: Audit and delete or wire `validate_upload_integrity()` in the uploads service — `backend/a (review + tweak) [feat:test-automation-agent-20261002-audit-and-delete-or-wire-validate-upload] ---

# --- 27B-decomposed from roadmap [2026-10-02]: Audit `backend/app/utils/baseline_lookup.py` for zero callers — this util exists in the ut (review + tweak) [feat:test-automation-agent-20261002-audit-backend-app-utils-baseline-lookup-] ---

# --- 27B-decomposed from roadmap [2026-10-02]: Add DB indexes on `TestFlakeStat.customer_id` and `TestFlakeStat.test_name` — every reques (review + tweak) [feat:test-automation-agent-20261002-add-db-indexes-on-testflakestat-customer] ---
- [ ] [T4] backend/tests/test_flake_model_indexes.py — Create test file that imports `TestFlakeStat` from `backend.app.models.test_run` and asserts the table has indexes named `ix_test_flake_stat_customer_id` and `ix_test_flake_stat_customer_test_name`. VERIFY: `pytest backend/tests/test_flake_model_indexes.py -v`. (cat:test; multifile:no) [feat:test-automation-agent-20261002-add-db-indexes-on-testflakestat-customer]
- [ ] [T5] backend/alembic/env.py — Verify no changes needed to env.py for index creation, but add a comment or ensure `target_metadata` includes the new model if not already present. VERIFY: `grep -q "target_metadata" backend/alembic/env.py`. (cat:schema; multifile:no) [feat:test-automation-agent-20261002-add-db-indexes-on-testflakestat-customer]

# --- 27B-decomposed from roadmap [2026-10-03]: Rate limiter ignores real client IP on Fly.io — `backend/app/core/rate_limiting.py` uses ` (review + tweak) [feat:test-automation-agent-20261003-rate-limiter-ignores-real-client-ip-on-f] ---
- [ ] [T1] backend/app/utils/rate_limit_key.py — Ensure `get_client_ip` correctly prioritizes `Fly-Client-IP` header over `X-Forwarded-For` and falls back to `request.client.host`. VERIFY: `pytest backend/tests/test_rate_limit_key.py -v`. (cat:python; multifile:no) [feat:test-automation-agent-20261003-rate-limiter-ignores-real-client-ip-on-f]
- [ ] [T2] backend/app/core/rate_limiting.py — Import `get_client_ip` from `backend.app.utils.rate_limit_key` and replace the current `key_func` implementation with it. VERIFY: `grep -n "from backend.app.utils.rate_limit_key import get_client_ip" backend/app/core/rate_limiting.py`. (cat:python; multifile:no) [feat:test-automation-agent-20261003-rate-limiter-ignores-real-client-ip-on-f]
- [ ] [T3] backend/tests/test_rate_limiting.py — Create a new test file that mocks a FastAPI Request object with `Fly-Client-IP` header set to "1.2.3.4" and `client.host` set to "5.6.7.8", asserting the rate limiter generates a key based on "1.2.3.4". VERIFY: `pytest backend/tests/test_rate_limiting.py -v`. (cat:test; multifile:no) [feat:test-automation-agent-20261003-rate-limiter-ignores-real-client-ip-on-f]
- [ ] [T3] backend/tests/test_rate_limiting.py — Add a test case for `X-Forwarded-For` header handling where `Fly-Client-IP` is absent, ensuring the first IP in the chain is used for the rate limit key. VERIFY: `pytest backend/tests/test_rate_limiting.py::test_x_forwarded_for_fallback -v`. (cat:test; multifile:no) [feat:test-automation-agent-20261003-rate-limiter-ignores-real-client-ip-on-f]
- [ ] [T3] backend/tests/test_rate_limiting.py — Add a test case for the fallback scenario where neither `Fly-Client-IP` nor `X-Forwarded-For` is present, ensuring `request.client.host` is used. VERIFY: `pytest backend/tests/test_rate_limiting.py::test_fallback_to_client_host -v`. (cat:test; multifile:no) [feat:test-automation-agent-20261003-rate-limiter-ignores-real-client-ip-on-f]
- [ ] [T4] backend/app/core/rate_limiting.py — Verify that the rate limiter middleware correctly applies the new `key_func` to all protected endpoints by checking the integration with the FastAPI app instance. VERIFY: `python -c "from backend.app.main import app; print('App loaded successfully')"` and `pytest backend/tests/test_rate_limiting.py -v`. (cat:refactor; multifile:yes) [feat:test-automation-agent-20261003-rate-limiter-ignores-real-client-ip-on-f]

# --- 27B-decomposed from roadmap [2026-10-03]: Misplaced `test_html_report.py` silently drops XSS guard test — `backend/app/utils/test_ht (review + tweak) [feat:test-automation-agent-20261003-misplaced-test-html-report-py-silently-d] ---
- [ ] [T1] backend/tests/test_html_report.py — Create new file containing the `test_escape_html` function moved from `backend/app/utils/test_html_report.py`. VERIFY: `grep -q "def test_escape_html" backend/tests/test_html_report.py`. (cat:test; multifile:no) [feat:test-automation-agent-20261003-misplaced-test-html-report-py-silently-d]
- [ ] [T2] backend/app/utils/test_html_report.py — Delete this file as it has been moved to `backend/tests/`. VERIFY: `test ! -f backend/app/utils/test_html_report.py`. (cat:refactor; multifile:no) [feat:test-automation-agent-20261003-misplaced-test-html-report-py-silently-d]
- [ ] [T3] backend/tests/test_html_report.py — Ensure the test imports `escape_html` from `backend.app.utils.html_report` and asserts correct XSS escaping behavior. VERIFY: `cd backend && python -m pytest tests/test_html_report.py -v`. (cat:test; multifile:no) [feat:test-automation-agent-20261003-misplaced-test-html-report-py-silently-d]
- [ ] [T4] backend/app/utils/html_report.py — Verify that `escape_html` is correctly imported and used within `render_html_report` to sanitize user input. VERIFY: `grep -q "escape_html" backend/app/utils/html_report.py`. (cat:python; multifile:no) [feat:test-automation-agent-20261003-misplaced-test-html-report-py-silently-d]
- [ ] [T5] backend/app/routers/test_runs.py — Confirm that the endpoint calling `render_html_report` passes untrusted data through the sanitization path. VERIFY: `grep -q "render_html_report" backend/app/routers/test_runs.py`. (cat:endpoint; multifile:no) [feat:test-automation-agent-20261003-misplaced-test-html-report-py-silently-d]

# --- 27B-decomposed from roadmap [2026-10-03]: `browser_defaults_test.py` doubly undiscoverable — wrong directory and wrong naming conven (review + tweak) [feat:test-automation-agent-20261003-browser-defaults-test-py-doubly-undiscov] ---
- [ ] [T1] backend/tests/test_browser_defaults.py — Create new file containing the assertions for `SUPPORTED_BROWSERS` and `DEFAULT_BROWSER` consistency with `PlaywrightService.SUPPORTED_BROWSERS`, importing from `backend.app.utils.browser_defaults` and `backend.app.services.playwright_service`. VERIFY: `pytest backend/tests/test_browser_defaults.py -v` passes. (cat:test; multifile:no) [feat:test-automation-agent-20261003-browser-defaults-test-py-doubly-undiscov]
- [ ] [T2] backend/app/utils/browser_defaults_test.py — Remove the file using `git rm backend/app/utils/browser_defaults_test.py` to eliminate the undiscoverable duplicate. VERIFY: `test ! -f backend/app/utils/browser_defaults_test.py` returns 0. (cat:refactor; multifile:no) [feat:test-automation-agent-20261003-browser-defaults-test-py-doubly-undiscov]
- [ ] [T3] backend/pyproject.toml — Ensure `testpaths` includes `backend/tests` or is set to `["backend/tests"]` so pytest discovers the new location. VERIFY: `grep -q "backend/tests" backend/pyproject.toml` returns 0. (cat:python; multifile:no) [feat:test-automation-agent-20261003-browser-defaults-test-py-doubly-undiscov]
- [ ] [T4] backend/tests/__init__.py — Create an empty `__init__.py` file to ensure `backend/tests` is treated as a package for proper import resolution if required by the project structure. VERIFY: `test -f backend/tests/__init__.py` returns 0. (cat:python; multifile:no) [feat:test-automation-agent-20261003-browser-defaults-test-py-doubly-undiscov]
- [ ] [T5] backend/app/utils/browser_defaults.py — Verify that `SUPPORTED_BROWSERS` and `DEFAULT_BROWSER` constants are correctly defined and exported for import by the new test file. VERIFY: `python -c "from backend.app.utils.browser_defaults import SUPPORTED_BROWSERS, DEFAULT_BROWSER; print('OK')"` succeeds. (cat:python; multifile:no) [feat:test-automation-agent-20261003-browser-defaults-test-py-doubly-undiscov]

# --- 27B-decomposed from roadmap [2026-10-03]: Add CGN (100.64.0.0/10) and IPv6 ULA SSRF protection to ssrf_guard.py — `backend/app/utils (review + tweak) [feat:test-automation-agent-20261003-add-cgn-100-64-0-0-10-and-ipv6-ula-ssrf-] ---
- [ ] [T1] backend/app/utils/ssrf_guard.py — Add `CGN_RANGE = ip_network("100.64.0.0/10")` and `ULA_RANGE = ip_network("fc00::/7")` constants at module level. VERIFY: `python -c "from backend.app.utils.ssrf_guard import CGN_RANGE, ULA_RANGE; print(CGN_RANGE, ULA_RANGE)"`. (cat:python; multifile:no) [feat:test-automation-agent-20261003-add-cgn-100-64-0-0-10-and-ipv6-ula-ssrf-]
- [ ] [T2] backend/app/utils/ssrf_guard.py — Update `is_safe_url()` to return `False` if the resolved IP is in `CGN_RANGE` or `ULA_RANGE`. VERIFY: `python -c "from backend.app.utils.ssrf_guard import is_safe_url; assert not is_safe_url('http://100.64.0.1'); assert not is_safe_url('http://[fd00::1]')"` [feat:test-automation-agent-20261003-add-cgn-100-64-0-0-10-and-ipv6-ula-ssrf-]
- [ ] [T2] backend/tests/test_ssrf_guard.py — Add test cases asserting `is_safe_url` returns `False` for `http://100.64.0.1` and `http://[fd00::1]`. VERIFY: `pytest backend/tests/test_ssrf_guard.py -k "cgn or ula" -v`. (cat:test; multifile:no) [feat:test-automation-agent-20261003-add-cgn-100-64-0-0-10-and-ipv6-ula-ssrf-]
- [ ] [T2] backend/tests/test_ssrf_guard.py — Add test cases asserting `is_safe_url` returns `True` for `http://100.63.255.255` and `http://[fe80::1]` (boundary checks). VERIFY: `pytest backend/tests/test_ssrf_guard.py -k "boundary" -v`. (cat:test; multifile:no) [feat:test-automation-agent-20261003-add-cgn-100-64-0-0-10-and-ipv6-ula-ssrf-]
- [ ] [T3] backend/app/routers/webhooks.py — Verify existing import of `is_safe_url` from `backend.app.utils.ssrf_guard` is used at line 94 to validate webhook URLs. VERIFY: `grep -n "is_safe_url" backend/app/routers/webhooks.py | grep -v "^#"`. (cat:python; multifile:no) [feat:test-automation-agent-20261003-add-cgn-100-64-0-0-10-and-ipv6-ula-ssrf-]
- [ ] [T3] backend/app/services/notification_dispatcher.py — Verify existing import of `is_safe_url` from `backend.app.utils.ssrf_guard` is used at line 59 to validate notification URLs. VERIFY: `grep -n "is_safe_url" backend/app/services/notification_dispatcher.py | grep -v "^#"`. (cat:python; multifile:no) [feat:test-automation-agent-20261003-add-cgn-100-64-0-0-10-and-ipv6-ula-ssrf-]
- [ ] [T4] backend/tests/test_ssrf_guard.py — Add integration test mocking `socket.getaddrinfo` to return CGN/ULA IPs and asserting `is_safe_url` blocks them. VERIFY: `pytest backend/tests/test_ssrf_guard.py -k "mock_getaddrinfo" -v`. (cat:test; multifile:no) [feat:test-automation-agent-20261003-add-cgn-100-64-0-0-10-and-ipv6-ula-ssrf-]
- [ ] [T5] backend/app/utils/ssrf_guard.py — Ensure `is_safe_url` handles IPv6 link-local (`fe80::/10`) correctly alongside new ULA checks without regression. VERIFY: `python -c "from backend.app.utils.ssrf_guard import is_safe_url; assert not is_safe_url('http://[fe80::1]')"` [feat:test-automation-agent-20261003-add-cgn-100-64-0-0-10-and-ipv6-ula-ssrf-]
