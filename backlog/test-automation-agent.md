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

# --- 27B-decomposed from roadmap [2026-10-02]: Recover runs orphaned by restarts/deploys — execution_engine.py tracks live runs only in t (review + tweak) [feat:test-automation-agent-20261002-recover-runs-orphaned-by-restarts-deploy] ---

# --- 27B-decomposed from roadmap [2026-10-02]: Add graceful-shutdown drain to the app lifespan — `backend/app/main.py`'s lifespan `yield` (review + tweak) [feat:test-automation-agent-20261002-add-graceful-shutdown-drain-to-the-app-l] ---

# --- 27B-decomposed from roadmap [2026-10-02]: Audit and delete or wire `validate_upload_integrity()` in the uploads service — `backend/a (review + tweak) [feat:test-automation-agent-20261002-audit-and-delete-or-wire-validate-upload] ---

# --- 27B-decomposed from roadmap [2026-10-02]: Audit `backend/app/utils/baseline_lookup.py` for zero callers — this util exists in the ut (review + tweak) [feat:test-automation-agent-20261002-audit-backend-app-utils-baseline-lookup-] ---

# --- 27B-decomposed from roadmap [2026-10-02]: Add DB indexes on `TestFlakeStat.customer_id` and `TestFlakeStat.test_name` — every reques (review + tweak) [feat:test-automation-agent-20261002-add-db-indexes-on-testflakestat-customer] ---

# --- 27B-decomposed from roadmap [2026-10-03]: Rate limiter ignores real client IP on Fly.io — `backend/app/core/rate_limiting.py` uses ` (review + tweak) [feat:test-automation-agent-20261003-rate-limiter-ignores-real-client-ip-on-f] ---

# --- 27B-decomposed from roadmap [2026-10-03]: Misplaced `test_html_report.py` silently drops XSS guard test — `backend/app/utils/test_ht (review + tweak) [feat:test-automation-agent-20261003-misplaced-test-html-report-py-silently-d] ---

# --- 27B-decomposed from roadmap [2026-10-03]: `browser_defaults_test.py` doubly undiscoverable — wrong directory and wrong naming conven (review + tweak) [feat:test-automation-agent-20261003-browser-defaults-test-py-doubly-undiscov] ---

# --- 27B-decomposed from roadmap [2026-10-03]: Add CGN (100.64.0.0/10) and IPv6 ULA SSRF protection to ssrf_guard.py — `backend/app/utils (review + tweak) [feat:test-automation-agent-20261003-add-cgn-100-64-0-0-10-and-ipv6-ula-ssrf-] ---

# --- 27B-decomposed from roadmap [2026-10-13]: Wire `eta.remaining_seconds()` into WebSocket progress events or delete — `backend/app/uti (review + tweak) [feat:test-automation-agent-20261013-wire-eta-remaining-seconds-into-websocke] ---

# --- 27B-decomposed from roadmap [2026-10-13]: Wire `moving_average()` into flake trend smoothing or delete — `backend/app/utils/moving_a (review + tweak) [feat:test-automation-agent-20261013-wire-moving-average-into-flake-trend-smo] ---

# --- 27B-decomposed from roadmap [2026-10-13]: Wire `validate_selection_coverage()` into dry-run response or delete — `backend/app/servic (review + tweak) [feat:test-automation-agent-20261013-wire-validate-selection-coverage-into-dr] ---

# --- deterministic work supply 2026-10-16 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- 27B-decomposed from roadmap [2026-10-17]: Fix `get_live_role` returning wrong role for multi-org users — `backend/app/routers/usage. (review + tweak) [feat:test-automation-agent-20261017-fix-get-live-role-returning-wrong-role-f] ---

# --- 27B-decomposed from roadmap [2026-10-17]: Fix `_run_summary()` in public API always returning null `duration_human` — `backend/app/r (review + tweak) [feat:test-automation-agent-20261017-fix-run-summary-in-public-api-always-ret] ---

# --- 27B-decomposed from roadmap [2026-10-17]: Fix `derive_run_status` returning "flaky" which is not a valid `TestRunStatus` enum — `bac (review + tweak) [feat:test-automation-agent-20261017-fix-derive-run-status-returning-flaky-wh] ---

# --- 27B-decomposed from roadmap [2026-10-17]: Fix `InviteRequest.role` advertising "viewer" as valid but VALID_ROLES rejects it — `backe (review + tweak) [feat:test-automation-agent-20261017-fix-inviterequest-role-advertising-viewe] ---

# --- 27B-decomposed from roadmap [2026-10-17]: Fix `_finalize` storing a naive `completed_at` in a timezone-aware column — `backend/app/s (review + tweak) [feat:test-automation-agent-20261017-fix-finalize-storing-a-naive-completed-a] ---

# --- 27B-decomposed from roadmap [2026-10-17]: Delete dead `get_previous_screenshot_path` function with an inverted filter — `backend/app (review + tweak) [feat:test-automation-agent-20261017-delete-dead-get-previous-screenshot-path] ---

# --- deterministic work supply 2026-10-18 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- deterministic work supply 2026-10-18 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- 27B-decomposed from roadmap [2026-10-18]: `start_test_run` allows re-executing terminal runs — `backend/app/routers/test_runs.py:216 (review + tweak) [feat:test-automation-agent-20261018-start-test-run-allows-re-executing-termi] ---

# --- 27B-decomposed from roadmap [2026-10-18]: HTML report format=html silently returns empty content — `backend/app/routers/test_runs.py (review + tweak) [feat:test-automation-agent-20261018-html-report-format-html-silently-returns] ---

# --- 27B-decomposed from roadmap [2026-10-18]: `cancel_test_run` overwrites terminal-status runs — `backend/app/routers/test_runs.py:539- (review + tweak) [feat:test-automation-agent-20261018-cancel-test-run-overwrites-terminal-stat] ---

# --- deterministic work supply 2026-10-18 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- 27B-decomposed from roadmap [2026-10-18]: `TERMINAL_STATUSES` and `VALID_STATUSES` missing `"flaky"` — `backend/app/utils/run_status (review + tweak) [feat:test-automation-agent-20261018-terminal-statuses-and-valid-statuses-mis] ---

# --- 27B-decomposed from roadmap [2026-10-18]: `run.recovered` webhook event not subscribable — `backend/app/services/recovery.py:77` dis (review + tweak) [feat:test-automation-agent-20261018-run-recovered-webhook-event-not-subscrib] ---

# --- 27B-decomposed from roadmap [2026-10-18]: FLAKY run status is unreachable: call site never passes flaky count — `backend/app/service (review + tweak) [feat:test-automation-agent-20261018-flaky-run-status-is-unreachable-call-sit] ---

# --- 27B-decomposed from roadmap [2026-10-18]: `pause_test_run` and `resume_test_run` lack terminal-state guards — `backend/app/routers/t (review + tweak) [feat:test-automation-agent-20261018-pause-test-run-and-resume-test-run-lack-] ---

# --- 27B-decomposed from roadmap [2026-10-19]: Add tests for WebSocket authentication and broadcast logic — `backend/app/utils/ws_auth.py (review + tweak) [feat:test-automation-agent-20261019-add-tests-for-websocket-authentication-a] ---

# --- 27B-decomposed from roadmap [2026-10-19]: Add tests for Flake API endpoints — `backend/app/routers/flakes.py:38` (`validate_fix_firs (review + tweak) [feat:test-automation-agent-20261019-add-tests-for-flake-api-endpoints-backen] ---

# --- 27B-decomposed from roadmap [2026-10-19]: Add tests for Webhook management endpoints — `backend/app/routers/webhooks.py:125` (`list_ (review + tweak) [feat:test-automation-agent-20261019-add-tests-for-webhook-management-endpoin] ---

# --- 27B-decomposed from roadmap [2026-10-19]: Add tests for billing endpoints — `backend/app/routers/billing.py:63` (`get_usage`), `back (review + tweak) [feat:test-automation-agent-20261019-add-tests-for-billing-endpoints-backend-] ---

# --- 27B-decomposed from roadmap [2026-10-19]: Add tests for API auth principal resolution — `backend/app/core/api_auth.py:34` (`get_api_ (review + tweak) [feat:test-automation-agent-20261019-add-tests-for-api-auth-principal-resolut] ---

# --- 27B-decomposed from roadmap [2026-10-19]: Add tests for visual diffs listing — `backend/app/routers/visual_diffs.py:43` (`list_visua (review + tweak) [feat:test-automation-agent-20261019-add-tests-for-visual-diffs-listing-backe] ---

# --- 27B-decomposed from roadmap [2026-10-19]: Add tests for auth endpoints — `backend/app/routers/auth.py:30` (`get_current_user_endpoin (review + tweak) [feat:test-automation-agent-20261019-add-tests-for-auth-endpoints-backend-app] ---

# --- 27B-decomposed from roadmap [2026-10-20]: `rerun_failed_tests` bypasses monthly run quota — `backend/app/routers/test_runs.py:rerun_ (review + tweak) [feat:test-automation-agent-20261020-rerun-failed-tests-bypasses-monthly-run-] ---

# --- 27B-decomposed from roadmap [2026-10-20]: HTML report always shows "Started: N/A" — `backend/app/utils/html_report.py:27` reads `run (review + tweak) [feat:test-automation-agent-20261020-html-report-always-shows-started-n-a-bac] ---

# --- 27B-decomposed from roadmap [2026-10-20]: `TestRun.flaky_tests` column missing — flaky count discarded after every run — `backend/ap (review + tweak) [feat:test-automation-agent-20261020-testrun-flaky-tests-column-missing-flaky] ---

# --- 27B-decomposed from roadmap [2026-10-20]: `POST /{run_id}/start` silently re-executes PAUSED runs from scratch, discarding all progr (review + tweak) [feat:test-automation-agent-20261020-post-run-id-start-silently-re-executes-p] ---

# --- 27B-decomposed from roadmap [2026-10-20]: `duration_regression` is always NULL for FLAKY runs — `backend/app/services/execution_engi (review + tweak) [feat:test-automation-agent-20261020-duration-regression-is-always-null-for-f] ---

# --- 27B-decomposed from roadmap [2026-10-20]: Delete dead `backend/app/utils/recovery.py` (`find_stale_run_ids`) — zero callers anywhere (review + tweak) [feat:test-automation-agent-20261020-delete-dead-backend-app-utils-recovery-p] ---

# --- 27B-decomposed from roadmap [2026-10-20]: Delete batch of post-round-5 zero-caller utils added since the 2026-09-22 audit — confirme (review + tweak) [feat:test-automation-agent-20261020-delete-batch-of-post-round-5-zero-caller] ---

# --- 27B-decomposed from roadmap [2026-10-20]: Test `get_api_principal` resolution logic — Add unit tests for `backend/app/core/api_auth. (review + tweak) [feat:test-automation-agent-20261020-test-get-api-principal-resolution-logic-] ---

# --- deterministic work supply 2026-10-21 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- deterministic work supply 2026-10-21 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- deterministic work supply 2026-10-21 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- 27B-decomposed from roadmap [2026-10-21]: Test `broadcast_update` and `notify_clients` WebSocket logic — Add unit tests for `backend (review + tweak) [feat:test-automation-agent-20261021-test-broadcast-update-and-notify-clients] ---

# --- 27B-decomposed from roadmap [2026-10-21]: Test `validate_fix_first_limit` and `list_flakes` — Add unit tests for `backend/app/router (review + tweak) [feat:test-automation-agent-20261021-test-validate-fix-first-limit-and-list-f] ---

# --- 27B-decomposed from roadmap [2026-10-21]: Test `get_flake_analysis` and `get_fix_first` — Add unit tests for `backend/app/routers/fl (review + tweak) [feat:test-automation-agent-20261021-test-get-flake-analysis-and-get-fix-firs] ---

# --- 27B-decomposed from roadmap [2026-10-21]: Test `get_flakes_index` and `get_test_trend` — Add unit tests for `backend/app/routers/fla (review + tweak) [feat:test-automation-agent-20261021-test-get-flakes-index-and-get-test-trend] ---

# --- 27B-decomposed from roadmap [2026-10-21]: Test `list_webhooks` and `get_webhook` — Add unit tests for `backend/app/routers/webhooks. (review + tweak) [feat:test-automation-agent-20261021-test-list-webhooks-and-get-webhook-add-u] ---

# --- 27B-decomposed from roadmap [2026-10-21]: Test `update_webhook` and `retry_webhook_delivery` — Add unit tests for `backend/app/route (review + tweak) [feat:test-automation-agent-20261021-test-update-webhook-and-retry-webhook-de] ---

# --- 27B-decomposed from roadmap [2026-10-21]: Test `issue_key` and `revoke_key` — Add unit tests for `backend/app/routers/api_keys.py:68 (review + tweak) [feat:test-automation-agent-20261021-test-issue-key-and-revoke-key-add-unit-t] ---

# --- 27B-decomposed from roadmap [2026-10-21]: Test `get_healing_history` and `get_healing_stats` — Add unit tests for `backend/app/route (review + tweak) [feat:test-automation-agent-20261021-test-get-healing-history-and-get-healing] ---

# --- 27B-decomposed from roadmap [2026-10-21]: Test `get_webhook_deliveries` delivery history — Add unit tests for `backend/app/routers/w (review + tweak) [feat:test-automation-agent-20261021-test-get-webhook-deliveries-delivery-his] ---

# --- 27B-decomposed from roadmap [2026-10-21]: Test org management endpoints (list, create, switch) — Add unit tests for `backend/app/rou (review + tweak) [feat:test-automation-agent-20261021-test-org-management-endpoints-list-creat] ---

# --- 27B-decomposed from roadmap [2026-10-21]: Test org member and invite management — Add unit tests for `backend/app/routers/orgs.py:16 (review + tweak) [feat:test-automation-agent-20261021-test-org-member-and-invite-management-ad] ---

# --- 27B-decomposed from roadmap [2026-10-21]: Test `update_project_webhook` and invite management — Add unit tests for `backend/app/rout (review + tweak) [feat:test-automation-agent-20261021-test-update-project-webhook-and-invite-m] ---

# --- 27B-decomposed from roadmap [2026-10-21]: Test CI integration CRUD endpoints — Add unit tests for `backend/app/routers/ci.py:96` (`c (review + tweak) [feat:test-automation-agent-20261021-test-ci-integration-crud-endpoints-add-u] ---

# --- 27B-decomposed from roadmap [2026-10-21]: Test GitHub webhook handlers — Add unit tests for `backend/app/routers/ci.py:245` (`github (review + tweak) [feat:test-automation-agent-20261021-test-github-webhook-handlers-add-unit-te] ---

# --- 27B-decomposed from roadmap [2026-10-22]: Test `login_user` and `revoke_token` auth flows — Add unit tests for `backend/app/routers/ (review + tweak) [feat:test-automation-agent-20261022-test-login-user-and-revoke-token-auth-fl] ---

# --- 27B-decomposed from roadmap [2026-10-22]: Test `stripe_webhook` event processing — Add unit tests for `backend/app/routers/billing.p (review + tweak) [feat:test-automation-agent-20261022-test-stripe-webhook-event-processing-add] ---

# --- 27B-decomposed from roadmap [2026-10-22]: Fix O(N) cron scan in _calculate_next_run — `backend/app/routers/ci.py:396` (`_calculate_n (review + tweak) [feat:test-automation-agent-20261022-fix-o-n-cron-scan-in-calculate-next-run-] ---

# --- 27B-decomposed from roadmap [2026-10-22]: Add type="button" to BillingPage upgrade buttons — `frontend/src/pages/BillingPage.vue:33` (review + tweak) [feat:test-automation-agent-20261022-add-type-button-to-billingpage-upgrade-b] ---

# --- 27B-decomposed from roadmap [2026-10-22]: Add aria-label to BrowserSelector select element — `frontend/src/components/BrowserSelecto (review + tweak) [feat:test-automation-agent-20261022-add-aria-label-to-browserselector-select] ---

# --- 27B-decomposed from roadmap [2026-10-22]: Add role="alert" to CiIntegrationsPage error div — `frontend/src/pages/CiIntegrationsPage. (review + tweak) [feat:test-automation-agent-20261022-add-role-alert-to-ciintegrationspage-err] ---

# --- 27B-decomposed from roadmap [2026-10-22]: Test `update_member_role` and `remove_member` — Add unit tests for `backend/app/routers/or (review + tweak) [feat:test-automation-agent-20261022-test-update-member-role-and-remove-membe] ---

# --- 27B-decomposed from roadmap [2026-10-22]: Test `create_invite` and `accept_invite` — Add unit tests for `backend/app/routers/orgs.py (review + tweak) [feat:test-automation-agent-20261022-test-create-invite-and-accept-invite-add] ---

# --- 27B-decomposed from roadmap [2026-10-23]: Test `get_usage` billing endpoint — Add unit tests for `backend/app/routers/billing.py:63` (review + tweak) [feat:test-automation-agent-20261023-test-get-usage-billing-endpoint-add-unit] ---

# --- 27B-decomposed from roadmap [2026-10-23]: Test `get_artifact` endpoint — Add unit tests for `backend/app/routers/artifacts.py:74` (` (review + tweak) [feat:test-automation-agent-20261023-test-get-artifact-endpoint-add-unit-test] ---

# --- 27B-decomposed from roadmap [2026-10-23]: Test `create_schedule` CI endpoint — Add unit tests for `backend/app/routers/ci.py:386` (` (review + tweak) [feat:test-automation-agent-20261023-test-create-schedule-ci-endpoint-add-uni] ---

# --- 27B-decomposed from roadmap [2026-10-23]: Reject empty or whitespace-only test names in uploads — `backend/app/routers/uploads.py:10 (review + tweak) [feat:test-automation-agent-20261023-reject-empty-or-whitespace-only-test-nam] ---

# --- 27B-decomposed from roadmap [2026-10-23]: Return 409 for duplicate GitHub integrations per tenant — `backend/app/routers/ci.py:103`  (review + tweak) [feat:test-automation-agent-20261023-return-409-for-duplicate-github-integrat] ---

# --- 27B-decomposed from roadmap [2026-10-23]: Test `list_integrations` and `delete_integration` — Add unit tests for `backend/app/router (review + tweak) [feat:test-automation-agent-20261023-test-list-integrations-and-delete-integr] ---

# --- 27B-decomposed from roadmap [2026-10-23]: Test `list_schedules` and `delete_schedule` — Add unit tests for `backend/app/routers/ci.p (review + tweak) [feat:test-automation-agent-20261023-test-list-schedules-and-delete-schedule-] ---

# --- 27B-decomposed from roadmap [2026-10-23]: Test `run_due` CI scheduler logic — Add unit tests for `backend/app/routers/ci.py:459` (`r (review + tweak) [feat:test-automation-agent-20261023-test-run-due-ci-scheduler-logic-add-unit] ---

# --- 27B-decomposed from roadmap [2026-10-24]: Test `get_user_by_email` and `list_memberships_for_user` — Add unit tests for `backend/app (review + tweak) [feat:test-automation-agent-20261024-test-get-user-by-email-and-list-membersh] ---

# --- 27B-decomposed from roadmap [2026-10-24]: Test `list_members` tenancy service — Add unit tests for `backend/app/services/tenancy.py: (review + tweak) [feat:test-automation-agent-20261024-test-list-members-tenancy-service-add-un] ---

# --- 27B-decomposed from roadmap [2026-10-24]: Test `revoke_key` API key service — Add unit tests for `backend/app/services/api_keys.py:1 (review + tweak) [feat:test-automation-agent-20261024-test-revoke-key-api-key-service-add-unit] ---

# --- 27B-decomposed from roadmap [2026-10-24]: Test `email_configured` service function — Add unit tests for `backend/app/services/email_ (review + tweak) [feat:test-automation-agent-20261024-test-email-configured-service-function-a] ---

# --- deterministic work supply 2026-10-24 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- 27B-decomposed from roadmap [2026-10-24]: Test `notify_recovered_runs` recovery notification logic — Add unit tests for `backend/app (review + tweak) [feat:test-automation-agent-20261024-test-notify-recovered-runs-recovery-noti] ---

# --- 27B-decomposed from roadmap [2026-10-24]: Test `should_update_github_ci` execution logic — Add unit tests for `backend/app/services/ (review + tweak) [feat:test-automation-agent-20261024-test-should-update-github-ci-execution-l] ---

# --- 27B-decomposed from roadmap [2026-10-24]: Test `create_rerun_run` execution engine logic — Add unit tests for `backend/app/services/ (review + tweak) [feat:test-automation-agent-20261024-test-create-rerun-run-execution-engine-l] ---

# --- 27B-decomposed from roadmap [2026-10-24]: Use SQL aggregate for monthly usage instead of loading all runs — `backend/app/routers/usa (review + tweak) [feat:test-automation-agent-20261024-use-sql-aggregate-for-monthly-usage-inst] ---

# --- 27B-decomposed from roadmap [2026-10-24]: Remove duplicate query execution in get_failure_patterns — `backend/app/services/knowledge (review + tweak) [feat:test-automation-agent-20261024-remove-duplicate-query-execution-in-get-] ---

# --- 27B-decomposed from roadmap [2026-10-25]: Add type attribute to UploadPage upload button — `frontend/src/pages/UploadPage.vue:30` (` (review + tweak) [feat:test-automation-agent-20261025-add-type-attribute-to-uploadpage-upload-] ---

# --- 27B-decomposed from roadmap [2026-10-25]: Add aria-live to TestPlanEditor result badge for screen reader announcement — `frontend/sr (review + tweak) [feat:test-automation-agent-20261025-add-aria-live-to-testplaneditor-result-b] ---

# --- 27B-decomposed from roadmap [2026-10-25]: Test `list_visual_diffs` endpoint — Add unit tests for `backend/app/routers/visual_diffs.p (review + tweak) [feat:test-automation-agent-20261025-test-list-visual-diffs-endpoint-add-unit] ---

# --- 27B-decomposed from roadmap [2026-10-25]: Parallelize LLM difficulty classification in plan_phase — `backend/app/agents/orchestrator (review + tweak) [feat:test-automation-agent-20261025-parallelize-llm-difficulty-classificatio] ---

# --- 27B-decomposed from roadmap [2026-10-25]: Test `get_current_user_endpoint` auth resolution — Add unit tests for `backend/app/routers (review + tweak) [feat:test-automation-agent-20261025-test-get-current-user-endpoint-auth-reso] ---

# --- 27B-decomposed from roadmap [2026-10-26]: Test `list_org_members` endpoint — Add unit tests for `backend/app/routers/orgs.py:169` (` (review + tweak) [feat:test-automation-agent-20261026-test-list-org-members-endpoint-add-unit-] ---

# --- 27B-decomposed from roadmap [2026-10-27]: Add scope attribute to FlakeDashboard table headers — `frontend/src/pages/FlakeDashboardPa (review + tweak) [feat:test-automation-agent-20261027-add-scope-attribute-to-flakedashboard-ta] ---

# --- 27B-decomposed from roadmap [2026-10-27]: Fix division by zero in SQL order_by for knowledge base queries — `backend/app/services/kn (review + tweak) [feat:test-automation-agent-20261027-fix-division-by-zero-in-sql-order-by-for] ---

# --- 27B-decomposed from roadmap [2026-10-28]: Python SDK typed errors and retries with mocked-transport tests (C3) — `sdk/python/specpil (review + tweak) [feat:test-automation-agent-20261028-python-sdk-typed-errors-and-retries-with] ---

# --- 27B-decomposed from roadmap [2026-10-28]: Public API flake listing plus SDK `list_flakes` (C3/C5) — `backend/app/routers/public_api. (review + tweak) [feat:test-automation-agent-20261028-public-api-flake-listing-plus-sdk-list-f] ---

# --- 27B-decomposed from roadmap [2026-10-28]: Deduplicate GitHub webhook deliveries by `X-GitHub-Delivery` (C7) — `backend/app/routers/c (review + tweak) [feat:test-automation-agent-20261028-deduplicate-github-webhook-deliveries-by] ---

# --- 27B-decomposed from roadmap [2026-10-28]: Retry transient failures when posting GitHub commit statuses (C7) — `backend/app/services/ (review + tweak) [feat:test-automation-agent-20261028-retry-transient-failures-when-posting-gi] ---

# --- 27B-decomposed from roadmap [2026-10-28]: Link the SpecPilot run from the GitHub commit status (C7) — `backend/app/routers/ci.py` `g (review + tweak) [feat:test-automation-agent-20261028-link-the-specpilot-run-from-the-github-c] ---

# --- 27B-decomposed from roadmap [2026-10-28]: Usage page limit warning at 80 percent (C10) — `frontend/src/pages/UsagePage.vue` only tur (review + tweak) [feat:test-automation-agent-20261028-usage-page-limit-warning-at-80-percent-c] ---

# --- 27B-decomposed from roadmap [2026-10-28]: Approve a visual diff as the new baseline (C2) — `backend/app/routers/visual_diffs.py` has (review + tweak) [feat:test-automation-agent-20261028-approve-a-visual-diff-as-the-new-baselin] ---

# --- 27B-decomposed from roadmap [2026-10-28]: Test `should_process_delivery` CI logic — Add unit tests for `backend/app/routers/ci.py:18 (review + tweak) [feat:test-automation-agent-20261028-test-should-process-delivery-ci-logic-ad] ---

# --- 27B-decomposed from roadmap [2026-10-29]: Test `build_run_url` CI result utility — Add unit tests for `backend/app/utils/ci_result.p (review + tweak) [feat:test-automation-agent-20261029-test-build-run-url-ci-result-utility-add] ---

# --- deterministic work supply 2026-10-29 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- 27B-decomposed from roadmap [2026-10-30]: Add 'element_not_exists' assertion for absence checks — `backend/app/agents/executor.py:33 (review + tweak) [feat:test-automation-agent-20261030-add-element-not-exists-assertion-for-abs] ---

# --- 27B-decomposed from roadmap [2026-10-31]: Add aria-label to period selector in UsagePage — `frontend/src/pages/UsagePage.vue:5` (`te (review + tweak) [feat:test-automation-agent-20261031-add-aria-label-to-period-selector-in-usa] ---

# --- 27B-decomposed from roadmap [2026-11-01]: Approve a visual diff from the Visual Regressions page (C2) — `frontend/src/stores/visualD (review + tweak) [feat:test-automation-agent-20261101-approve-a-visual-diff-from-the-visual-re] ---

# --- 27B-decomposed from roadmap [2026-11-01]: Rerun-failed button on the run detail page (C1) — `POST /api/test-runs/{run_id}/rerun-fail (review + tweak) [feat:test-automation-agent-20261101-rerun-failed-button-on-the-run-detail-pa] ---

# --- 27B-decomposed from roadmap [2026-11-01]: Behavioral tests for the rerun-failed endpoint (C1) — `rerun_failed_tests` in `backend/app (review + tweak) [feat:test-automation-agent-20261101-behavioral-tests-for-the-rerun-failed-en] ---

# --- 27B-decomposed from roadmap [2026-11-01]: Deterministic ordering and status filter for public API run listing (C3) — `list_runs` in  (review + tweak) [feat:test-automation-agent-20261101-deterministic-ordering-and-status-filter] ---

# --- 27B-decomposed from roadmap [2026-11-01]: Cancel a run through the public API and SDK (C3) — the public API in `backend/app/routers/ (review + tweak) [feat:test-automation-agent-20261101-cancel-a-run-through-the-public-api-and-] ---

# --- 27B-decomposed from roadmap [2026-11-01]: Per-test results endpoint on the public API plus SDK `get_run_results` (C3) — `GET /api/v1 (review + tweak) [feat:test-automation-agent-20261101-per-test-results-endpoint-on-the-public-] ---

# --- 27B-decomposed from roadmap [2026-11-01]: SDK `wait_for_run` polling helper (C3) — `sdk/python/specpilot_sdk/client.py` forces every (review + tweak) [feat:test-automation-agent-20261101-sdk-wait-for-run-polling-helper-c3-sdk-p] ---

# --- 27B-decomposed from roadmap [2026-11-01]: SDK `iter_runs` auto-pagination generator (C3) — `SpecPilotClient.list_runs(skip, limit)`  (review + tweak) [feat:test-automation-agent-20261101-sdk-iter-runs-auto-pagination-generator-] ---

# --- 27B-decomposed from roadmap [2026-11-01]: Document `GET /v1/flakes` and the `flakes:read` scope on the developer docs page (C3) — `f (review + tweak) [feat:test-automation-agent-20261101-document-get-v1-flakes-and-the-flakes-re] ---

# --- 27B-decomposed from roadmap [2026-11-01]: Unit tests for `validate_yaml_plan` (C4) — `backend/app/services/test_plan_validation.py:2 (review + tweak) [feat:test-automation-agent-20261101-unit-tests-for-validate-yaml-plan-c4-bac] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Test `webhook_pr_comment` comment processing — Add unit tests for `backend/app/routers/ci. (review + tweak) [feat:test-automation-agent-20261102-test-webhook-pr-comment-comment-processi] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Plan validation rejects executor-supported actions check/uncheck/clear/reload (C4) — `back (review + tweak) [feat:test-automation-agent-20261102-plan-validation-rejects-executor-support] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Plan-level SSRF check reads the wrong key for navigate steps (C4) — `_extract_urls_from_st (review + tweak) [feat:test-automation-agent-20261102-plan-level-ssrf-check-reads-the-wrong-ke] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Run detail screenshots, videos and traces cannot load in the browser because artifact link (review + tweak) [feat:test-automation-agent-20261102-run-detail-screenshots-videos-and-traces] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Visual regression baseline and current images cannot load in the browser because they carr (review + tweak) [feat:test-automation-agent-20261102-visual-regression-baseline-and-current-i] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Plan validator warns that `element_not_exists` is an unknown assertion prefix (C4) — `VALI (review + tweak) [feat:test-automation-agent-20261102-plan-validator-warns-that-element-not-ex] ---

# --- 27B-decomposed from roadmap [2026-11-02]: `cron_matches` disagrees with standard cron and with `next_cron_match` (C8) — in `backend/ (review + tweak) [feat:test-automation-agent-20261102-cron-matches-disagrees-with-standard-cro] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Schedule next-run preview scans minute by minute (C8) — `next_cron_match` in `backend/app/ (review + tweak) [feat:test-automation-agent-20261102-schedule-next-run-preview-scans-minute-b] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Webhook delivery retries permanent 4xx responses (C8) — `_attempt_delivery` in `backend/ap (review + tweak) [feat:test-automation-agent-20261102-webhook-delivery-retries-permanent-4xx-r] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Deterministic ordering for the test run list endpoint (C3) — `list_test_runs` in `backend/ (review + tweak) [feat:test-automation-agent-20261102-deterministic-ordering-for-the-test-run-] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Flake dashboard never loads or colors the suite health badge (C5) — `frontend/src/pages/Fl (review + tweak) [feat:test-automation-agent-20261102-flake-dashboard-never-loads-or-colors-th] ---

# --- 27B-decomposed from roadmap [2026-11-04]: Add run_id filter to self-healing history endpoint — `backend/app/routers/self_healing.py: (review + tweak) [feat:test-automation-agent-20261104-add-run-id-filter-to-self-healing-histor] ---

# --- 27B-decomposed from roadmap [2026-11-04]: Plan validation rejects legitimate falsy step values such as `value: 0` (C4) — `validate_p (review + tweak) [feat:test-automation-agent-20261104-plan-validation-rejects-legitimate-falsy] ---

# --- 27B-decomposed from roadmap [2026-11-04]: Executor passes non-string YAML scalars straight to Playwright so numeric inputs fail at r (review + tweak) [feat:test-automation-agent-20261104-executor-passes-non-string-yaml-scalars-] ---

# --- 27B-decomposed from roadmap [2026-11-04]: GitHub webhook triggers a run for every `pull_request` action and for branch deletions (C7 (review + tweak) [feat:test-automation-agent-20261104-github-webhook-triggers-a-run-for-every-] ---

# --- 27B-decomposed from roadmap [2026-11-04]: Self-healing history returns too few or no events because LIMIT is applied to results, not (review + tweak) [feat:test-automation-agent-20261104-self-healing-history-returns-too-few-or-] ---

# --- 27B-decomposed from roadmap [2026-11-04]: Run detail and public results endpoints return results in undefined order (C3) — `get_test (review + tweak) [feat:test-automation-agent-20261104-run-detail-and-public-results-endpoints-] ---

# --- 27B-decomposed from roadmap [2026-11-04]: Login and Signup pages have unannounced errors and no autofill or length hints (C1) — `fro (review + tweak) [feat:test-automation-agent-20261104-login-and-signup-pages-have-unannounced-] ---

# --- 27B-decomposed from roadmap [2026-11-04]: ApiKeys, Notifications and SelfHealing pages show errors without `role="alert"` (C1) — `fr (review + tweak) [feat:test-automation-agent-20261104-apikeys-notifications-and-selfhealing-pa] ---

# --- 27B-decomposed from roadmap [2026-11-04]: Billing, Usage and VisualDiffs pages show errors without `role="alert"` (C1) — `frontend/s (review + tweak) [feat:test-automation-agent-20261104-billing-usage-and-visualdiffs-pages-show] ---

# --- 27B-decomposed from roadmap [2026-11-06]: `POST /api/test-runs` returns an unhandled 500 when the YAML plan's `tests` is null, a num (review + tweak) [feat:test-automation-agent-20261106-post-api-test-runs-returns-an-unhandled-] ---

# --- 27B-decomposed from roadmap [2026-11-06]: Run detail page always shows an empty result count, 0% pass rate and never offers "Rerun F (review + tweak) [feat:test-automation-agent-20261106-run-detail-page-always-shows-an-empty-re] ---

# --- 27B-decomposed from roadmap [2026-11-06]: Dashboard stat tiles are always 0 because the page reads camelCase keys the dashboard summ (review + tweak) [feat:test-automation-agent-20261106-dashboard-stat-tiles-are-always-0-becaus] ---

# --- 27B-decomposed from roadmap [2026-11-06]: `POST /api/test-plans/dry-run` crashes with 500 instead of returning `valid: false` for a  (review + tweak) [feat:test-automation-agent-20261106-post-api-test-plans-dry-run-crashes-with] ---

# --- 27B-decomposed from roadmap [2026-11-06]: `validate_plan` raises TypeError (500 on `/api/test-plans/validate` and `/dry-run`) for a  (review + tweak) [feat:test-automation-agent-20261106-validate-plan-raises-typeerror-500-on-ap] ---

# --- 27B-decomposed from roadmap [2026-11-06]: HTML run report lists every test as "Unknown" (C1) — the `format=html` branch of `get_test (review + tweak) [feat:test-automation-agent-20261106-html-run-report-lists-every-test-as-unkn] ---

# --- 27B-decomposed from roadmap [2026-11-06]: A failed test whose exception has an empty message is saved with an empty error (C1) — `Te (review + tweak) [feat:test-automation-agent-20261106-a-failed-test-whose-exception-has-an-emp] ---

# --- 27B-decomposed from roadmap [2026-11-06]: Approving a visual diff leaves it flagged, so it reappears in the Visual Regressions list  (review + tweak) [feat:test-automation-agent-20261106-approving-a-visual-diff-leaves-it-flagge] ---

# --- 27B-decomposed from roadmap [2026-11-06]: Run detail page never updates while a run is in flight (C1) — `frontend/src/pages/TestRunD (review + tweak) [feat:test-automation-agent-20261106-run-detail-page-never-updates-while-a-ru] ---

# --- 27B-decomposed from roadmap [2026-11-06]: Run detail page offers "Resume" on pending runs and "Pause" on initializing runs, both of  (review + tweak) [feat:test-automation-agent-20261106-run-detail-page-offers-resume-on-pending] ---

# --- 27B-decomposed from roadmap [2026-11-06]: Test Runs page silently shows only the 10 newest runs (C1) — `TestRunsPage.vue` calls `sto (review + tweak) [feat:test-automation-agent-20261106-test-runs-page-silently-shows-only-the-1] ---

# --- 27B-decomposed from roadmap [2026-11-06]: GitHub integration accepts unknown event names that can never fire (C7) — `IntegrationCrea (review + tweak) [feat:test-automation-agent-20261106-github-integration-accepts-unknown-event] ---

# --- 27B-decomposed from roadmap [2026-11-06]: Webhook list and detail responses omit `channel`, and the list has no stable order, so the (review + tweak) [feat:test-automation-agent-20261106-webhook-list-and-detail-responses-omit-c] ---

# --- 27B-decomposed from roadmap [2026-11-06]: Notification form controls have no accessible names and the HMAC secret is typed in clear  (review + tweak) [feat:test-automation-agent-20261106-notification-form-controls-have-no-acces] ---

# --- 27B-decomposed from roadmap [2026-11-06]: Placeholder-only inputs on the API Keys, Organizations and CI Integrations pages (C1) — `A (review + tweak) [feat:test-automation-agent-20261106-placeholder-only-inputs-on-the-api-keys-] ---

# --- 27B-decomposed from roadmap [2026-11-06]: `cron_matches` in backend/app/utils/cron_match.py only validates the fields it happens to  (review + tweak) [feat:test-automation-agent-20261106-cron-matches-in-backend-app-utils-cron-m] ---

# --- 27B-decomposed from roadmap [2026-11-06]: `verify_github_signature` in backend/app/services/github_ci.py raises TypeError for a non- (review + tweak) [feat:test-automation-agent-20261106-verify-github-signature-in-backend-app-s] ---

# --- 27B-decomposed from roadmap [2026-11-06]: `select_tests_by_risk` in backend/app/utils/test_selection.py crashes the whole run on a m (review + tweak) [feat:test-automation-agent-20261106-select-tests-by-risk-in-backend-app-util] ---

# --- 27B-decomposed from roadmap [2026-11-06]: `backoff_delay_ms` in backend/app/utils/retry_backoff.py raises OverflowError for large at (review + tweak) [feat:test-automation-agent-20261106-backoff-delay-ms-in-backend-app-utils-re] ---

# --- 27B-decomposed from roadmap [2026-11-06]: `build_artifact_path` in backend/app/utils/artifact_paths.py slugifies `test_name` but joi (review + tweak) [feat:test-automation-agent-20261106-build-artifact-path-in-backend-app-utils] ---

# --- 27B-decomposed from roadmap [2026-11-06]: `post_or_update_pr_comment` in backend/app/services/github_ci.py looks for its marker comm (review + tweak) [feat:test-automation-agent-20261106-post-or-update-pr-comment-in-backend-app] ---

# --- 27B-decomposed from roadmap [2026-11-06]: `verify_signature` in backend/app/utils/webhook_signing.py: `verify_signature(secret, body (review + tweak) [feat:test-automation-agent-20261106-verify-signature-in-backend-app-utils-we] ---

# --- 27B-decomposed from roadmap [2026-11-06]: `redact_secrets` in backend/app/utils/redact.py both over-redacts and under-redacts: `_SK_ (review + tweak) [feat:test-automation-agent-20261106-redact-secrets-in-backend-app-utils-reda] ---

# --- 27B-decomposed from roadmap [2026-11-06]: `extract_host` in backend/app/utils/hostname.py mangles IPv6 literals and URLs with creden (review + tweak) [feat:test-automation-agent-20261106-extract-host-in-backend-app-utils-hostna] ---

# --- 27B-decomposed from roadmap [2026-11-06]: `detect_type` and `normalize` in backend/app/utils/selector_normalize.py only recognise XP (review + tweak) [feat:test-automation-agent-20261106-detect-type-and-normalize-in-backend-app] ---

# --- 27B-decomposed from roadmap [2026-11-06]: App shell has no skip-to-content link and the `<main>` landmark is not focusable: frontend (review + tweak) [feat:test-automation-agent-20261106-app-shell-has-no-skip-to-content-link-an] ---

# --- 27B-decomposed from roadmap [2026-11-06]: The SPA never updates `document.title` on navigation: frontend/src/router/index.js defines (review + tweak) [feat:test-automation-agent-20261106-the-spa-never-updates-document-title-on-] ---

# --- 27B-decomposed from roadmap [2026-11-06]: frontend/src/pages/TestRunsPage.vue results table has column headers without `scope` and a (review + tweak) [feat:test-automation-agent-20261106-frontend-src-pages-testrunspage-vue-resu] ---

# --- 27B-decomposed from roadmap [2026-11-06]: frontend/src/pages/VisualDiffsPage.vue list table has an empty column header, no header sc (review + tweak) [feat:test-automation-agent-20261106-frontend-src-pages-visualdiffspage-vue-l] ---

# --- 27B-decomposed from roadmap [2026-11-08]: Test `issue_key` API key issuance logic — Add unit tests for `backend/app/routers/api_keys (review + tweak) [feat:test-automation-agent-20261108-test-issue-key-api-key-issuance-logic-ad] ---

# --- 27B-decomposed from roadmap [2026-11-08]: Test `remove_member` org membership deletion — Add unit tests for `backend/app/routers/org (review + tweak) [feat:test-automation-agent-20261108-test-remove-member-org-membership-deleti] ---

# --- 27B-decomposed from roadmap [2026-11-09]: Test `approve_visual_diff` state transition — Add unit tests for `backend/app/routers/visu (review + tweak) [feat:test-automation-agent-20261109-test-approve-visual-diff-state-transitio] ---
- [ ] [T2] backend/app/routers/visual_diffs.py — Ensure `approve_visual_diff` commits the transaction only after successful status update and re-approval check passes. VERIFY: `pytest backend/tests/test_visual_diffs_approve.py -v` (cat:python; multifile:no) [feat:test-automation-agent-20261109-test-approve-visual-diff-state-transitio]
- [ ] [T1] backend/tests/test_visual_diffs_approve.py — Add unit test `test_approve_updates_status` that mocks DB session, calls `approve_visual_diff`, and asserts the visual diff status is updated to 'approved' in the database state. VERIFY: `pytest backend/tests/test_visual_diffs_approve.py::test_approve_updates_status -v` (cat:test; multifile:no) [feat:test-automation-agent-20261109-test-approve-visual-diff-state-transitio]
- [ ] [T1] backend/tests/test_visual_diffs_approve.py — Add unit test `test_approve_returns_correct_response` that mocks DB session, calls `approve_visual_diff`, and asserts the API response JSON contains status 'approved' and correct ID. VERIFY: `pytest backend/tests/test_visual_diffs_approve.py::test_approve_returns_correct_response -v` (cat:test; multifile:no) [feat:test-automation-agent-20261109-test-approve-visual-diff-state-transitio]
- [ ] [T1] backend/tests/test_visual_diffs_approve.py — Add unit test `test_reapprove_returns_409` that mocks a diff with status 'approved', calls `approve_visual_diff`, and asserts response status is 409. VERIFY: `pytest backend/tests/test_visual_diffs_approve.py::test_reapprove_returns_409 -v` (cat:test; multifile:no) [feat:test-automation-agent-20261109-test-approve-visual-diff-state-transitio]
- [ ] [T1] backend/tests/test_visual_diffs_approve.py — Add unit test `test_reapprove_does_not_update_db` that mocks a diff with status 'approved', calls `approve_visual_diff`, and asserts no update is committed to the database session. VERIFY: `pytest backend/tests/test_visual_diffs_approve.py::test_reapprove_does_not_update_db -v` (cat:test; multifile:no) [feat:test-automation-agent-20261109-test-approve-visual-diff-state-transitio]

# --- 27B-decomposed from roadmap [2026-11-09]: Test webhook CRUD endpoints — Add unit tests for `list_webhooks`, `get_webhook`, and `upda (review + tweak) [feat:test-automation-agent-20261109-test-webhook-crud-endpoints-add-unit-tes] ---
- [ ] [T1] backend/tests/test_webhooks_list_order.py — Add unit test verifying `list_webhooks` returns webhooks sorted by `created_at` descending using a mocked database session. VERIFY: `pytest backend/tests/test_webhooks_list_order.py -v` (cat:test; multifile:no) [feat:test-automation-agent-20261109-test-webhook-crud-endpoints-add-unit-tes]
- [ ] [T1] backend/tests/test_webhooks_get_by_id.py — Add unit test verifying `get_webhook` retrieves the correct webhook object when provided with a valid ID and raises 404 for invalid IDs. VERIFY: `pytest backend/tests/test_webhooks_get_by_id.py -v` (cat:test; multifile:no) [feat:test-automation-agent-20261109-test-webhook-crud-endpoints-add-unit-tes]
- [ ] [T1] backend/tests/test_webhooks_update_persistence.py — Add unit test verifying `update_webhook` persists changes to the database session and returns the updated object with new values. VERIFY: `pytest backend/tests/test_webhooks_update_persistence.py -v` (cat:test; multifile:no) [feat:test-automation-agent-20261109-test-webhook-crud-endpoints-add-unit-tes]
- [ ] [T2] backend/tests/test_webhooks_list_pagination.py — Add unit test verifying `list_webhooks` respects pagination parameters (`limit`, `offset`) and returns the correct subset of webhooks. VERIFY: `pytest backend/tests/test_webhooks_list_pagination.py -v` (cat:test; multifile:no) [feat:test-automation-agent-20261109-test-webhook-crud-endpoints-add-unit-tes]
- [ ] [T2] backend/tests/test_webhooks_update_validation.py — Add unit test verifying `update_webhook` rejects invalid payload fields (e.g., missing required fields or wrong types) with a 422 error. VERIFY: `pytest backend/tests/test_webhooks_update_validation.py -v` (cat:test; multifile:no) [feat:test-automation-agent-20261109-test-webhook-crud-endpoints-add-unit-tes]
- [ ] [T2] backend/tests/test_webhooks_auth_isolation.py — Add unit test verifying that `list_webhooks`, `get_webhook`, and `update_webhook` enforce tenant isolation by filtering results based on the authenticated user's organization. VERIFY: `pytest backend/tests/test_webhooks_auth_isolation.py -v` (cat:test; multifile:no) [feat:test-automation-agent-20261109-test-webhook-crud-endpoints-add-unit-tes]

# --- 27B-decomposed from roadmap [2026-11-09]: Test `switch_org` context switching logic — Add unit tests for `backend/app/routers/orgs.p (review + tweak) [feat:test-automation-agent-20261109-test-switch-org-context-switching-logic-] ---
- [ ] [T1] backend/app/routers/orgs.py — Modify `switch_org` to validate organization existence against the database before updating session state, raising `HTTPException(status_code=404)` if not found. VERIFY: `pytest backend/tests/test_orgs_switch.py::test_switch_org_invalid_id_returns_404 -v`. (cat:python; multifile:no) [feat:test-automation-agent-20261109-test-switch-org-context-switching-logic-]
- [ ] [T1] backend/app/routers/orgs.py — Modify `switch_org` to update the `active_org_id` in the user's session or authenticated context after successful validation. VERIFY: `pytest backend/tests/test_orgs_switch.py::test_switch_org_updates_session_context -v`. (cat:python; multifile:no) [feat:test-automation-agent-20261109-test-switch-org-context-switching-logic-]
- [ ] [T1] backend/app/routers/orgs.py — Add logic to `switch_org` to prevent context drift by ensuring the new organization ID matches the user's membership list before committing the change. VERIFY: `pytest backend/tests/test_orgs_switch.py::test_switch_org_rejects_non_member_org -v`. (cat:python; multifile:no) [feat:test-automation-agent-20261109-test-switch-org-context-switching-logic-]
- [ ] [T2] backend/tests/test_orgs_switch.py — Create test file with a fixture mocking the database session and user authentication to isolate `switch_org` logic. VERIFY: `pytest backend/tests/test_orgs_switch.py --collect-only -q`. (cat:test; multifile:no) [feat:test-automation-agent-20261109-test-switch-org-context-switching-logic-]
- [ ] [T2] backend/tests/test_orgs_switch.py — Add unit test `test_switch_org_valid_id_updates_context` asserting that a valid org ID updates the session's active organization and returns 200. VERIFY: `pytest backend/tests/test_orgs_switch.py::test_switch_org_valid_id_updates_context -v`. (cat:test; multifile:no) [feat:test-automation-agent-20261109-test-switch-org-context-switching-logic-]
- [ ] [T2] backend/tests/test_orgs_switch.py — Add unit test `test_switch_org_invalid_id_returns_404` asserting that a non-existent org ID triggers a 404 response and does not modify session state. VERIFY: `pytest backend/tests/test_orgs_switch.py::test_switch_org_invalid_id_returns_404 -v`. (cat:test; multifile:no) [feat:test-automation-agent-20261109-test-switch-org-context-switching-logic-]
- [ ] [T2] backend/tests/test_orgs_switch.py — Add unit test `test_switch_org_prevents_drift_on_concurrent_change` simulating a race condition where the org is deleted between validation and commit, ensuring no silent drift. VERIFY: `pytest backend/tests/test_orgs_switch.py::test_switch_org_prevents_drift_on_concurrent_change -v`. (cat:test; multifile:no) [feat:test-automation-agent-20261109-test-switch-org-context-switching-logic-]

# --- 27B-decomposed from roadmap [2026-11-09]: `_attempt_delivery` in backend/app/services/notification_dispatcher.py crashes with TypeEr (review + tweak) [feat:test-automation-agent-20261109-attempt-delivery-in-backend-app-services] ---
- [ ] [T3] backend/app/services/notification_dispatcher.py — Modify `_attempt_delivery` to use `json.dumps(payload, default=str)` instead of `json.dumps(payload)` to handle non-JSON-native values like datetime. VERIFY: `cd backend && python3 -m pytest tests/test_notification_dispatcher.py -q -k non_serializable_payload` passes. (cat:python; multifile:no) [feat:test-automation-agent-20261109-attempt-delivery-in-backend-app-services]
- [ ] [T2] backend/tests/test_notification_dispatcher.py — Add `test_attempt_delivery_non_serializable_payload` that monkeypatches `nd._send_request` to return a 200 response, calls `_attempt_delivery` with a payload containing `datetime.datetime(2026,1,1)`, and asserts `outcome["status"] == "delivered"` and `attempts == 1`. VERIFY: `cd backend && python3 -m pytest tests/test_notification_dispatcher.py -q -k non_serializable_payload` fails with TypeError before the fix. (cat:test; multifile:no) [feat:test-automation-agent-20261109-attempt-delivery-in-backend-app-services]

# --- 27B-decomposed from roadmap [2026-11-09]: `render_email` in backend/app/services/email_service.py lets a newline in the payload titl (review + tweak) [feat:test-automation-agent-20261109-render-email-in-backend-app-services-ema] ---
- [ ] [T1] backend/app/services/email_service.py — In `render_email`, replace the direct `str(title)` assignment for the subject with `" ".join(str(title).split())` to collapse all whitespace and newlines into single spaces. VERIFY: `cd backend && python3 -c "from app.services.email_service import render_email; s, _ = render_email('run.completed', {'title': 'a\nBcc: x@y.z'}); assert s == 'a Bcc: x@y.z' and '\n' not in s"` (cat:python; multifile:no) [feat:test-automation-agent-20261109-render-email-in-backend-app-services-ema]
- [ ] [T2] backend/tests/test_email_service.py — Add `test_render_email_subject_single_line` which asserts `render_email("run.completed", {"title": "a\nBcc: x@y.z"})[0]` equals `"a Bcc: x@y.z"` and does not contain `"\n"`, and that a clean title `"Run done"` is returned unchanged. VERIFY: `cd backend && python3 -m pytest tests/test_email_service.py -q -k subject_single_line` (cat:test; multifile:no) [feat:test-automation-agent-20261109-render-email-in-backend-app-services-ema]

# --- 27B-decomposed from roadmap [2026-11-09]: `ConnectionManager.broadcast` in backend/app/services/websocket_service.py raises TypeErro (review + tweak) [feat:test-automation-agent-20261109-connectionmanager-broadcast-in-backend-a] ---
- [ ] [T1] backend/app/services/websocket_service.py — Replace `self.run_states[run_id].update(message.get("data", {}))` with `data = message.get("data"); if isinstance(data, dict): self.run_states[run_id].update(data)` in `ConnectionManager.broadcast`. VERIFY: `cd backend && python3 -c "from app.services.websocket_service import ConnectionManager; print('ok')"` succeeds. (cat:python; multifile:no) [feat:test-automation-agent-20261109-connectionmanager-broadcast-in-backend-a]
- [ ] [T2] backend/tests/test_websocket_service_broadcast.py — Add `test_broadcast_none_data_still_delivers` that mocks a websocket, calls `broadcast("r", {"type": "progress_update", "data": None})`, asserts no exception and message received, then calls `broadcast("r", {"type": "progress_update", "data": {"done": 2}})` and asserts `run_states["r"] == {"done": 2}`. VERIFY: `cd backend && python3 -m pytest tests/test_websocket_service_broadcast.py -q -k none_data` passes. (cat:test; multifile:no) [feat:test-automation-agent-20261109-connectionmanager-broadcast-in-backend-a]

# --- 27B-decomposed from roadmap [2026-11-09]: `human_bytes` in backend/app/utils/human_bytes.py shows "1024.0 KB" / "1024.0 MB" just bel (review + tweak) [feat:test-automation-agent-20261109-human-bytes-in-backend-app-utils-human-b] ---
- [ ] [T1] backend/app/utils/human_bytes.py — Modify the `human_bytes` function to check if `round(value, 1) >= 1024` after the division loop and, if a larger unit exists, divide by 1024 again and advance the unit index. VERIFY: `cd backend && python3 -c "from app.utils.human_bytes import human_bytes; assert human_bytes(1048575) == '1.0 MB', human_bytes(1048575); assert human_bytes(1024**3 - 1) == '1.0 GB', human_bytes(1024**3 - 1)"`. (cat:python; multifile:no) [feat:test-automation-agent-20261109-human-bytes-in-backend-app-utils-human-b]
- [ ] [T3] backend/tests/test_human_bytes.py — Add a new test function `test_rounding_rolls_over_to_next_unit` that asserts `human_bytes(1048575) == "1.0 MB"`, `human_bytes(1024**3 - 1) == "1.0 GB"`, `human_bytes(1536) == "1.5 KB"`, and `human_bytes(1023) == "1023 B"`. VERIFY: `cd backend && python3 -m pytest tests/test_human_bytes.py::test_rounding_rolls_over_to_next_unit -q`. (cat:test; multifile:no) [feat:test-automation-agent-20261109-human-bytes-in-backend-app-utils-human-b]
- [ ] [T2] backend/tests/test_human_bytes.py — Update the existing assertion for `human_bytes(1024 * 1024 - 1)` to expect `"1.0 MB"` instead of `"1024.0 KB"`. VERIFY: `cd backend && python3 -m pytest tests/test_human_bytes.py -q -k "1024 * 1024 - 1"`. (cat:test; multifile:no) [feat:test-automation-agent-20261109-human-bytes-in-backend-app-utils-human-b]

# --- 27B-decomposed from roadmap [2026-11-09]: `sanitize_filename` in backend/app/utils/sanitize_filename.py returns the dot-only names " (review + tweak) [feat:test-automation-agent-20261109-sanitize-filename-in-backend-app-utils-s] ---
- [ ] [T1] backend/app/utils/sanitize_filename.py — Add a check after the existing replacement and truncation logic: if `result.strip(".")` is empty, return "file". VERIFY: `cd backend && python3 -c "from app.utils.sanitize_filename import sanitize_filename; assert sanitize_filename('..') == 'file' and sanitize_filename('.') == 'file' and sanitize_filename('...') == 'file' and sanitize_filename('.env') == '.env' and sanitize_filename('a.b') == 'a.b'"`. (cat:python; multifile:no) [feat:test-automation-agent-20261109-sanitize-filename-in-backend-app-utils-s]
- [ ] [T2] backend/tests/test_utils_sanitize_filename.py — Add test function `test_dot_only_names_fall_back` asserting `sanitize_filename("..") == "file"`, `sanitize_filename(".") == "file"`, `sanitize_filename("...") == "file"`, `sanitize_filename(".env") == ".env"`, and `sanitize_filename("a.b") == "a.b"`. VERIFY: `cd backend && python3 -m pytest tests/test_utils_sanitize_filename.py -q -k dot_only`. (cat:test; multifile:no) [feat:test-automation-agent-20261109-sanitize-filename-in-backend-app-utils-s]

# --- 27B-decomposed from roadmap [2026-11-09]: `selector_strength` in backend/app/utils/selector_strength.py rates an XPath `@data-testid (review + tweak) [feat:test-automation-agent-20261109-selector-strength-in-backend-app-utils-s] ---
- [ ] [T1] backend/app/utils/selector_strength.py — Update `_HIGH_TESTID_RE` to `re.compile(r"\[\s*@?data-testid\s*=", re.IGNORECASE)` VERIFY: `cd backend && python3 -c "from app.utils.selector_strength import selector_strength; assert selector_strength('//*[@data-testid=\'x\']') == 'high'"`. (cat:python; multifile:no) [feat:test-automation-agent-20261109-selector-strength-in-backend-app-utils-s]
- [ ] [T2] backend/tests/test_selector_strength.py — Add `test_xpath_data_testid_is_high` asserting `selector_strength("//*[@data-testid='x']") == "high"` and `selector_strength("//button[@data-testid=\"save\"]") == "high"` VERIFY: `cd backend && python3 -m pytest tests/test_selector_strength.py::test_xpath_data_testid_is_high -q`. (cat:test; multifile:no) [feat:test-automation-agent-20261109-selector-strength-in-backend-app-utils-s]
- [ ] [T2] backend/tests/test_selector_strength.py — Add assertion in `test_xpath_data_testid_is_high` that `selector_strength("//div[@class='a']") == "medium"` to ensure non-testid attributes remain medium VERIFY: `cd backend && python3 -m pytest tests/test_selector_strength.py::test_xpath_data_testid_is_high -q`. (cat:test; multifile:no) [feat:test-automation-agent-20261109-selector-strength-in-backend-app-utils-s]

# --- 27B-decomposed from roadmap [2026-11-09]: `build_healing_event` in backend/app/utils/healing_event.py turns a NaN confidence into th (review + tweak) [feat:test-automation-agent-20261109-build-healing-event-in-backend-app-utils] ---
- [ ] [T2] backend/app/utils/healing_event.py — Modify `build_healing_event` to check `if confidence is None or confidence != confidence: clamped = 0.0` before the existing `max(0.0, min(1.0, confidence))` logic. VERIFY: `cd backend && python3 -m pytest tests/test_healing_event.py::test_nan_and_none_confidence_become_zero -q` passes after fix. (cat:python; multifile:no) [feat:test-automation-agent-20261109-build-healing-event-in-backend-app-utils]
- [ ] [T3] backend/app/utils/healing_event.py — Ensure `math` is imported or use the `!=` identity check for NaN to avoid external dependency if not already present, verifying no import errors occur during module load. VERIFY: `cd backend && python3 -c "from backend.app.utils.healing_event import build_healing_event; print('OK')"`. (cat:python; multifile:no) [feat:test-automation-agent-20261109-build-healing-event-in-backend-app-utils]
- [ ] [T5] backend/app/services/self_healing.py — Verify that the call site around line 107 correctly passes the `confidence` value from the LLM response to `build_healing_event` without pre-processing that might mask NaN/None, ensuring the fix in `healing_event.py` is the sole point of correction. VERIFY: `cd backend && grep -n "build_healing_event" app/services/self_healing.py` shows the call passes raw confidence. (cat:python; multifile:no) [feat:test-automation-agent-20261109-build-healing-event-in-backend-app-utils]
- [ ] [T1] backend/tests/test_healing_event.py — Add `test_nan_and_none_confidence_become_zero` asserting `build_healing_event("a", "b", float("nan"), 0)["confidence"] == 0.0`, `build_healing_event("a", "b", None, 0)["confidence"] == 0.0`, `build_healing_event("a", "b", 0.5, 0)["confidence"] == 0.5`, and `build_healing_event("a", "b", 7, 0)["confidence"] == 1.0`. VERIFY: `cd backend && python3 -m pytest tests/test_healing_event.py::test_nan_and_none_confidence_become_zero -q` fails before fix. (cat:test; multifile:no) [feat:test-automation-agent-20261109-build-healing-event-in-backend-app-utils]
- [ ] [T4] backend/tests/test_healing_event.py — Add `test_valid_confidence_clamping` to explicitly verify that `build_healing_event("a", "b", 0.5, 0)["confidence"] == 0.5` and `build_healing_event("a", "b", 7, 0)["confidence"] == 1.0` remain unchanged by the new logic. VERIFY: `cd backend && python3 -m pytest tests/test_healing_event.py::test_valid_confidence_clamping -q` passes. (cat:test; multifile:no) [feat:test-automation-agent-20261109-build-healing-event-in-backend-app-utils]

# --- 27B-decomposed from roadmap [2026-11-09]: `format_duration_ms` and `humanize_duration` in backend/app/utils/duration.py produce garb (review + tweak) [feat:test-automation-agent-20261109-format-duration-ms-and-humanize-duration] ---
- [ ] [T1] backend/app/utils/duration.py — Add `ms = int(ms)` immediately after the `if ms <= 0: return "0s"` guard in `format_duration_ms` to truncate float inputs. VERIFY: `cd backend && python3 -c "from app.utils.duration import format_duration_ms; assert format_duration_ms(1500.5) == '1.5s'"`. (cat:python; multifile:no) [feat:test-automation-agent-20261109-format-duration-ms-and-humanize-duration]
- [ ] [T1] backend/app/utils/duration.py — Add `seconds = int(seconds)` immediately after the `if seconds <= 0: return "0s"` guard in `humanize_duration` to truncate float inputs. VERIFY: `cd backend && python3 -c "from app.utils.duration import humanize_duration; assert humanize_duration(65.5) == '1m 5s'"`. (cat:python; multifile:no) [feat:test-automation-agent-20261109-format-duration-ms-and-humanize-duration]
- [ ] [T2] backend/tests/test_duration.py — Add test function `test_float_inputs_are_truncated` asserting `format_duration_ms(1500.5) == "1.5s"`, `format_duration_ms(60000.0) == "1m"`, `humanize_duration(65.5) == "1m 5s"`, and `humanize_duration(3600.0) == "1h"`. VERIFY: `cd backend && python3 -m pytest tests/test_duration.py::test_float_inputs_are_truncated -q`. (cat:test; multifile:no) [feat:test-automation-agent-20261109-format-duration-ms-and-humanize-duration]
- [ ] [T2] backend/tests/test_duration.py — Add test function `test_int_inputs_unchanged` asserting `format_duration_ms(1500) == "1.5s"` and `humanize_duration(65) == "1m 5s"` to ensure integer behavior is preserved. VERIFY: `cd backend && python3 -m pytest tests/test_duration.py::test_int_inputs_unchanged -q`. (cat:test; multifile:no) [feat:test-automation-agent-20261109-format-duration-ms-and-humanize-duration]

# --- 27B-decomposed from roadmap [2026-11-09]: `extract_browser_type` in backend/app/utils/plan_normalizer.py keeps whitespace and mixed  (review + tweak) [feat:test-automation-agent-20261109-extract-browser-type-in-backend-app-util] ---
- [ ] [T1] backend/app/utils/plan_normalizer.py — Modify `extract_browser_type` to return `"chromium"` if `str(value).strip()` is empty, else `str(value).strip().lower()` VERIFY: `cd backend && python3 -c "from app.utils.plan_normalizer import extract_browser_type; assert extract_browser_type('  Chromium ') == 'chromium'; assert extract_browser_type('   ') == 'chromium'; assert extract_browser_type(None) == 'chromium'"`. (cat:python; multifile:no) [feat:test-automation-agent-20261109-extract-browser-type-in-backend-app-util]
- [ ] [T2] backend/tests/test_plan_normalizer.py — Add `test_extract_browser_type_trims_and_lowercases` asserting `extract_browser_type("  Chromium ") == "chromium"`, `extract_browser_type("FireFox") == "firefox"`, `extract_browser_type("   ") == "chromium"`, and `extract_browser_type(None) == "chromium"` VERIFY: `cd backend && python3 -m pytest tests/test_plan_normalizer.py -q -k trims_and_lowercases`. (cat:test; multifile:no) [feat:test-automation-agent-20261109-extract-browser-type-in-backend-app-util]

# --- 27B-decomposed from roadmap [2026-11-09]: `summarize_results` in backend/app/utils/results_summary.py raises ValueError for a NaN or (review + tweak) [feat:test-automation-agent-20261109-summarize-results-in-backend-app-utils-r] ---
- [ ] [T1] backend/app/utils/results_summary.py — Add `import math` at the top of the file to support finite number checks. VERIFY: `cd backend && python3 -c "import ast; tree = ast.parse(open('app/utils/results_summary.py').read()); imports = [n for n in ast.walk(tree) if isinstance(n, (ast.Import, ast.ImportFrom))]; assert any(isinstance(i, ast.Import) and i.names[0].name == 'math' for i in imports)"`. (cat:python; multifile:no) [feat:test-automation-agent-20261109-summarize-results-in-backend-app-utils-r]
- [ ] [T1] backend/app/utils/results_summary.py — Modify the `summarize_results` function to skip entries where `duration_ms` is not finite by adding a `math.isfinite(duration)` check alongside the existing `isinstance` guard before accumulating `total_duration_ms`. VERIFY: `cd backend && python3 -c "from app.utils.results_summary import summarize_results; r = summarize_results([{'status': 'passed', 'duration_ms': float('nan')}, {'status': 'failed', 'duration_ms': 40}]); assert r['total_duration_ms'] == 40"`. (cat:python; multifile:no) [feat:test-automation-agent-20261109-summarize-results-in-backend-app-utils-r]
- [ ] [T2] backend/tests/test_results_summary.py — Add a new test function `test_non_finite_duration_is_ignored` that asserts `summarize_results` correctly ignores NaN and Infinity values in `duration_ms` while counting statuses and summing valid durations. VERIFY: `cd backend && python3 -m pytest tests/test_results_summary.py::test_non_finite_duration_is_ignored -q`. (cat:test; multifile:no) [feat:test-automation-agent-20261109-summarize-results-in-backend-app-utils-r]
- [ ] [T2] backend/tests/test_results_summary.py — Add a new test function `test_infinite_duration_is_ignored` that specifically verifies `float('inf')` does not raise an `OverflowError` and is excluded from the total duration sum. VERIFY: `cd backend && python3 -m pytest tests/test_results_summary.py::test_infinite_duration_is_ignored -q`. (cat:test; multifile:no) [feat:test-automation-agent-20261109-summarize-results-in-backend-app-utils-r]
- [ ] [T2] backend/tests/test_results_summary.py — Add a new test function `test_negative_infinite_duration_is_ignored` that verifies `float('-inf')` is handled gracefully without raising exceptions. VERIFY: `cd backend && python3 -m pytest tests/test_results_summary.py::test_negative_infinite_duration_is_ignored -q`. (cat:test; multifile:no) [feat:test-automation-agent-20261109-summarize-results-in-backend-app-utils-r]
- [ ] [T2] backend/tests/test_results_summary.py — Add a new test function `test_mixed_finite_and_non_finite_durations` that validates the aggregate counts and total duration when a list contains a mix of valid, NaN, and Infinity values. VERIFY: `cd backend && python3 -m pytest tests/test_results_summary.py::test_mixed_finite_and_non_finite_durations -q`. (cat:test; multifile:no) [feat:test-automation-agent-20261109-summarize-results-in-backend-app-utils-r]

# --- 27B-decomposed from roadmap [2026-11-09]: `render_html_report` in backend/app/utils/html_report.py writes the per-test duration into (review + tweak) [feat:test-automation-agent-20261109-render-html-report-in-backend-app-utils-] ---
- [ ] [T2] backend/app/utils/html_report.py — Modify the row template in `render_html_report` to wrap `{duration}` with `escape_html()` so `<b>x</b>` becomes `&lt;b&gt;x&lt;/b&gt;`. VERIFY: `cd backend && python3 -m pytest tests/test_html_report.py -q -k test_duration_and_artifact_count_are_escaped` passes for duration assertions. (cat:python; multifile:no) [feat:test-automation-agent-20261109-render-html-report-in-backend-app-utils-]
- [ ] [T3] backend/app/utils/html_report.py — Modify the artifact count rendering in `render_html_report` to wrap `{artifact_count}` with `escape_html()` so `<i>1</i>` becomes `&lt;i&gt;1&lt;/i&gt;`. VERIFY: `cd backend && python3 -m pytest tests/test_html_report.py -q -k test_duration_and_artifact_count_are_escaped` passes for artifact_count assertions. (cat:python; multifile:no) [feat:test-automation-agent-20261109-render-html-report-in-backend-app-utils-]
- [ ] [T1] backend/tests/test_html_report.py — Add `test_duration_and_artifact_count_are_escaped` that renders a timeline with `duration_ms="<b>x</b>"` and `artifact_count="<i>1</i>"`, asserting raw HTML tags are absent, escaped entities are present, and integer duration 12 renders as "12ms". VERIFY: `cd backend && python3 -m pytest tests/test_html_report.py -q -k test_duration_and_artifact_count_are_escaped` fails before fix. (cat:test; multifile:no) [feat:test-automation-agent-20261109-render-html-report-in-backend-app-utils-]

# --- 27B-decomposed from roadmap [2026-11-09]: `create_plan_snapshot` in backend/app/utils/plan_snapshot.py raises TypeError for plans th (review + tweak) [feat:test-automation-agent-20261109-create-plan-snapshot-in-backend-app-util] ---
- [ ] [T2] backend/app/utils/plan_snapshot.py — Modify `create_plan_snapshot` to add `default=str` argument to the `json.dumps` call. VERIFY: `cd backend && python3 -m pytest tests/test_plan_snapshot_pure.py -q -k handles_dates` (cat:python; multifile:no) [feat:test-automation-agent-20261109-create-plan-snapshot-in-backend-app-util]
- [ ] [T1] backend/tests/test_plan_snapshot_pure.py — Add `test_snapshot_handles_dates` asserting `create_plan_snapshot({"d": datetime.date(2026, 1, 1)})` returns a 64-char hex string, equals `create_plan_snapshot({"d": "2026-01-01"})`, and differs from `create_plan_snapshot({"d": datetime.date(2026, 1, 2)})`. VERIFY: `cd backend && python3 -m pytest tests/test_plan_snapshot_pure.py -q -k handles_dates` (cat:test; multifile:no) [feat:test-automation-agent-20261109-create-plan-snapshot-in-backend-app-util]

# --- 27B-decomposed from roadmap [2026-11-09]: `validate_upload_integrity` in backend/app/services/ci_service.py rejects a correct digest (review + tweak) [feat:test-automation-agent-20261109-validate-upload-integrity-in-backend-app] ---
- [ ] [T1] backend/app/services/ci_service.py — In `validate_upload_integrity`, replace the final comparison with a check that `expected_sha256` is a string, normalize it via `.strip().lower()`, and compare using `hmac.compare_digest` against the computed hex digest. VERIFY: `cd backend && python3 -c "import hmac; from app.services.ci_service import validate_upload_integrity; import hashlib; p='backend/tests/tmp_test_file'; open(p,'wb').write(b'hi'); assert validate_upload_integrity(p, hashlib.sha256(b'hi').hexdigest().upper()) is True; assert validate_upload_integrity(p, '  '+hashlib.sha256(b'hi').hexdigest()+' ') is True; assert validate_upload_integrity(p, None) is False; print('OK')"` (cat:python; multifile:no) [feat:test-automation-agent-20261109-validate-upload-integrity-in-backend-app]
- [ ] [T2] backend/tests/test_ci_service.py — Add test `test_validate_upload_integrity_case_insensitive` that writes `b"hi"` to a temp file and asserts `validate_upload_integrity` returns `True` for lowercase, uppercase, and whitespace-padded correct digests, and `False` for an incorrect digest or `None`. VERIFY: `cd backend && python3 -m pytest tests/test_ci_service.py -q -k integrity_case_insensitive` (cat:test; multifile:no) [feat:test-automation-agent-20261109-validate-upload-integrity-in-backend-app]

# --- 27B-decomposed from roadmap [2026-11-09]: `FailureAnalyzer.categorize_error` in backend/app/agents/analyzer.py crashes with Attribut (review + tweak) [feat:test-automation-agent-20261109-failureanalyzer-categorize-error-in-back] ---
- [ ] [T1] backend/app/agents/analyzer.py — In `FailureAnalyzer.categorize_error`, replace the assignment `msg = error_message.lower()` with `msg = str(error_message or "").lower()` to handle None and non-string inputs. VERIFY: `cd backend && python3 -c "from app.agents.analyzer import FailureAnalyzer; a=FailureAnalyzer(); import asyncio; print(asyncio.run(a.categorize_error(None)))"`. (cat:python; multifile:no) [feat:test-automation-agent-20261109-failureanalyzer-categorize-error-in-back]
- [ ] [T2] backend/tests/test_analyzer_categorize_error.py — Add test function `test_categorize_error_none_and_empty` that instantiates the analyzer and asserts `await analyzer.categorize_error(None) == "other"`, `await analyzer.categorize_error("") == "other"`, and `await analyzer.categorize_error("Timeout 30000ms exceeded") == "timing"`. VERIFY: `cd backend && python3 -m pytest tests/test_analyzer_categorize_error.py -q -k none_and_empty`. (cat:test; multifile:no) [feat:test-automation-agent-20261109-failureanalyzer-categorize-error-in-back]

# --- 27B-decomposed from roadmap [2026-11-09]: `ConnectionManager.connect` in backend/app/services/websocket_service.py leaves a dead soc (review + tweak) [feat:test-automation-agent-20261109-connectionmanager-connect-in-backend-app] ---
- [ ] [T2] backend/app/services/websocket_service.py — Modify `ConnectionManager.connect` to wrap the initial `await websocket.send_json(state_sync)` call in a `try/except Exception` block that logs the error and calls `await self.disconnect(run_id, websocket)` before returning. VERIFY: `cd backend && python3 -m pytest tests/test_websocket_service.py -q -k state_sync_failure` passes after fix. (cat:python; multifile:no) [feat:test-automation-agent-20261109-connectionmanager-connect-in-backend-app]
- [ ] [T1] backend/tests/test_websocket_service.py — Add `test_connect_state_sync_failure_unregisters` that initializes `manager.run_states["r"] = {"a": 1}`, creates a fake websocket where `accept` succeeds and `send_json` raises `RuntimeError`, asserts `await manager.connect("r", ws)` does not raise, and asserts `"r" not in manager.active_connections`. VERIFY: `cd backend && python3 -m pytest tests/test_websocket_service.py -q -k state_sync_failure` fails before fix. (cat:test; multifile:no) [feat:test-automation-agent-20261109-connectionmanager-connect-in-backend-app]
