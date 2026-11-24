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

# --- 27B-decomposed from roadmap [2026-11-09]: Test webhook CRUD endpoints — Add unit tests for `list_webhooks`, `get_webhook`, and `upda (review + tweak) [feat:test-automation-agent-20261109-test-webhook-crud-endpoints-add-unit-tes] ---

# --- 27B-decomposed from roadmap [2026-11-09]: Test `switch_org` context switching logic — Add unit tests for `backend/app/routers/orgs.p (review + tweak) [feat:test-automation-agent-20261109-test-switch-org-context-switching-logic-] ---

# --- 27B-decomposed from roadmap [2026-11-09]: `_attempt_delivery` in backend/app/services/notification_dispatcher.py crashes with TypeEr (review + tweak) [feat:test-automation-agent-20261109-attempt-delivery-in-backend-app-services] ---

# --- 27B-decomposed from roadmap [2026-11-09]: `render_email` in backend/app/services/email_service.py lets a newline in the payload titl (review + tweak) [feat:test-automation-agent-20261109-render-email-in-backend-app-services-ema] ---

# --- 27B-decomposed from roadmap [2026-11-09]: `ConnectionManager.broadcast` in backend/app/services/websocket_service.py raises TypeErro (review + tweak) [feat:test-automation-agent-20261109-connectionmanager-broadcast-in-backend-a] ---

# --- 27B-decomposed from roadmap [2026-11-09]: `human_bytes` in backend/app/utils/human_bytes.py shows "1024.0 KB" / "1024.0 MB" just bel (review + tweak) [feat:test-automation-agent-20261109-human-bytes-in-backend-app-utils-human-b] ---

# --- 27B-decomposed from roadmap [2026-11-09]: `sanitize_filename` in backend/app/utils/sanitize_filename.py returns the dot-only names " (review + tweak) [feat:test-automation-agent-20261109-sanitize-filename-in-backend-app-utils-s] ---

# --- 27B-decomposed from roadmap [2026-11-09]: `selector_strength` in backend/app/utils/selector_strength.py rates an XPath `@data-testid (review + tweak) [feat:test-automation-agent-20261109-selector-strength-in-backend-app-utils-s] ---

# --- 27B-decomposed from roadmap [2026-11-09]: `build_healing_event` in backend/app/utils/healing_event.py turns a NaN confidence into th (review + tweak) [feat:test-automation-agent-20261109-build-healing-event-in-backend-app-utils] ---

# --- 27B-decomposed from roadmap [2026-11-09]: `format_duration_ms` and `humanize_duration` in backend/app/utils/duration.py produce garb (review + tweak) [feat:test-automation-agent-20261109-format-duration-ms-and-humanize-duration] ---

# --- 27B-decomposed from roadmap [2026-11-09]: `extract_browser_type` in backend/app/utils/plan_normalizer.py keeps whitespace and mixed  (review + tweak) [feat:test-automation-agent-20261109-extract-browser-type-in-backend-app-util] ---

# --- 27B-decomposed from roadmap [2026-11-09]: `summarize_results` in backend/app/utils/results_summary.py raises ValueError for a NaN or (review + tweak) [feat:test-automation-agent-20261109-summarize-results-in-backend-app-utils-r] ---

# --- 27B-decomposed from roadmap [2026-11-09]: `render_html_report` in backend/app/utils/html_report.py writes the per-test duration into (review + tweak) [feat:test-automation-agent-20261109-render-html-report-in-backend-app-utils-] ---

# --- 27B-decomposed from roadmap [2026-11-09]: `create_plan_snapshot` in backend/app/utils/plan_snapshot.py raises TypeError for plans th (review + tweak) [feat:test-automation-agent-20261109-create-plan-snapshot-in-backend-app-util] ---

# --- 27B-decomposed from roadmap [2026-11-09]: `validate_upload_integrity` in backend/app/services/ci_service.py rejects a correct digest (review + tweak) [feat:test-automation-agent-20261109-validate-upload-integrity-in-backend-app] ---

# --- 27B-decomposed from roadmap [2026-11-09]: `FailureAnalyzer.categorize_error` in backend/app/agents/analyzer.py crashes with Attribut (review + tweak) [feat:test-automation-agent-20261109-failureanalyzer-categorize-error-in-back] ---

# --- 27B-decomposed from roadmap [2026-11-09]: `ConnectionManager.connect` in backend/app/services/websocket_service.py leaves a dead soc (review + tweak) [feat:test-automation-agent-20261109-connectionmanager-connect-in-backend-app] ---

# --- 27B-decomposed from roadmap [2026-11-10]: `validate_plan_async` crashes with AttributeError for a plan that is not a mapping, althou (review + tweak) [feat:test-automation-agent-20261110-validate-plan-async-crashes-with-attribu] ---

# --- 27B-decomposed from roadmap [2026-11-10]: `validate_plan` emits one warning per CHARACTER when a test's `assertions` is a plain stri (review + tweak) [feat:test-automation-agent-20261110-validate-plan-emits-one-warning-per-char] ---

# --- 27B-decomposed from roadmap [2026-11-10]: `validate_email_address` accepts an address with a trailing newline, so `"a@b.co\n"` or `" (review + tweak) [feat:test-automation-agent-20261110-validate-email-address-accepts-an-addres] ---

# --- 27B-decomposed from roadmap [2026-11-10]: `_detect_test_command` treats any comment that merely starts with the letters "/test" as t (review + tweak) [feat:test-automation-agent-20261110-detect-test-command-treats-any-comment-t] ---

# --- 27B-decomposed from roadmap [2026-11-10]: `extract_pr_number` accepts booleans, zero, negative numbers and truncates floats, so a ma (review + tweak) [feat:test-automation-agent-20261110-extract-pr-number-accepts-booleans-zero-] ---

# --- 27B-decomposed from roadmap [2026-11-10]: `select_tests` treats a plain-string `tags` value as a set of single characters, so `inclu (review + tweak) [feat:test-automation-agent-20261110-select-tests-treats-a-plain-string-tags-] ---

# --- 27B-decomposed from roadmap [2026-11-10]: `build_index_from_rows` never copies a row's `tags` into the index, so the `by_tag` map it (review + tweak) [feat:test-automation-agent-20261110-build-index-from-rows-never-copies-a-row] ---

# --- 27B-decomposed from roadmap [2026-11-10]: `should_retry` raises AttributeError when a failed test's error is not a string, which abo (review + tweak) [feat:test-automation-agent-20261110-should-retry-raises-attributeerror-when-] ---

# --- 27B-decomposed from roadmap [2026-11-10]: `normalize_flake_score` turns a NaN score into the maximum flakiness 1.0 - `backend/app/ut (review + tweak) [feat:test-automation-agent-20261110-normalize-flake-score-turns-a-nan-score-] ---

# --- 27B-decomposed from roadmap [2026-11-10]: `percentile` fails with the misleading "cannot convert float NaN to integer" for `p=nan` i (review + tweak) [feat:test-automation-agent-20261110-percentile-fails-with-the-misleading-can] ---

# --- 27B-decomposed from roadmap [2026-11-10]: `remaining_seconds` returns a negative ETA when the elapsed time is negative and NaN when  (review + tweak) [feat:test-automation-agent-20261110-remaining-seconds-returns-a-negative-eta] ---

# --- 27B-decomposed from roadmap [2026-11-10]: `validate_yaml_plan` has no test for its two parse-failure branches - `backend/app/service (review + tweak) [feat:test-automation-agent-20261110-validate-yaml-plan-has-no-test-for-its-t] ---

# --- 27B-decomposed from roadmap [2026-11-10]: `_classify_difficulty` in the plan validator has no direct test of its easy/medium/hard ru (review + tweak) [feat:test-automation-agent-20261110-classify-difficulty-in-the-plan-validato] ---

# --- 27B-decomposed from roadmap [2026-11-10]: `select_tests_by_risk` string-score coercion is untested - `backend/app/utils/test_selecti (review + tweak) [feat:test-automation-agent-20261110-select-tests-by-risk-string-score-coerci] ---

# --- 27B-decomposed from roadmap [2026-11-10]: `_event_timestamp` (Stripe `created` to datetime) has no test for its reject branches - `b (review + tweak) [feat:test-automation-agent-20261110-event-timestamp-stripe-created-to-dateti] ---

# --- 27B-decomposed from roadmap [2026-11-10]: `verify_webhook_signature` success and invalid-signature wrapping are untested - `backend/ (review + tweak) [feat:test-automation-agent-20261110-verify-webhook-signature-success-and-inv] ---

# --- 27B-decomposed from roadmap [2026-11-10]: The zero-size-image branches of the visual diff helpers are untested - `backend/app/utils/ (review + tweak) [feat:test-automation-agent-20261110-the-zero-size-image-branches-of-the-visu] ---

# --- 27B-decomposed from roadmap [2026-11-10]: `authenticate_ws_token` swallows the HTTP auth failure and rejects an expired token, but n (review + tweak) [feat:test-automation-agent-20261110-authenticate-ws-token-swallows-the-http-] ---

# --- 27B-decomposed from roadmap [2026-11-10]: `is_missing_step_param` and the private `_is_missing_param` in the orchestrator are not te (review + tweak) [feat:test-automation-agent-20261110-is-missing-step-param-and-the-private-is] ---

# --- 27B-decomposed from roadmap [2026-11-10]: The malformed-argument messages of `element_count_equals` and the page-title failure messa (review + tweak) [feat:test-automation-agent-20261110-the-malformed-argument-messages-of-eleme] ---

# --- 27B-decomposed from roadmap [2026-11-10]: The malformed-argument messages of `element_count_at_least` are untested - `backend/app/ag (review + tweak) [feat:test-automation-agent-20261110-the-malformed-argument-messages-of-eleme] ---

# --- 27B-decomposed from roadmap [2026-11-10]: `validate_upload_integrity` is untested for its unreadable-path and hash-mismatch outcomes (review + tweak) [feat:test-automation-agent-20261110-validate-upload-integrity-is-untested-fo] ---

# --- 27B-decomposed from roadmap [2026-11-10]: `_parse_pr_comment_event` raises AttributeError for a webhook whose `comment` is null and  (review + tweak) [feat:test-automation-agent-20261110-parse-pr-comment-event-raises-attributee] ---

# --- 27B-decomposed from roadmap [2026-11-10]: `calculate_usage_metrics` raises TypeError when a run's `total_tests` is None - `backend/a (review + tweak) [feat:test-automation-agent-20261110-calculate-usage-metrics-raises-typeerror] ---

# --- 27B-decomposed from roadmap [2026-11-10]: `_get_installation_token` always fails in the deployed environment because it imports the  (review + tweak) [feat:test-automation-agent-20261110-get-installation-token-always-fails-in-t] ---

# --- 27B-decomposed from roadmap [2026-11-11]: `_get_installation_token` argument validation is untested - `backend/app/services/github_c (review + tweak) [feat:test-automation-agent-20261111-get-installation-token-argument-validati] ---

# --- 27B-decomposed from roadmap [2026-11-11]: `validate_plan` malformed `steps` shapes are untested - `backend/app/services/test_plan_va (review + tweak) [feat:test-automation-agent-20261111-validate-plan-malformed-steps-shapes-are] ---

# --- 27B-decomposed from roadmap [2026-11-11]: `email_service._smtp_send` is never executed by any test - `backend/app/services/email_ser (review + tweak) [feat:test-automation-agent-20261111-email-service-smtp-send-is-never-execute] ---

# --- 27B-decomposed from roadmap [2026-11-11]: `next_cron_match` with only day-of-week restricted is untested - `backend/app/utils/cron_m (review + tweak) [feat:test-automation-agent-20261111-next-cron-match-with-only-day-of-week-re] ---

# --- 27B-decomposed from roadmap [2026-11-11]: `DeliveryDedupe.__len__` is untested - `backend/app/utils/delivery_dedupe.py` `DeliveryDed (review + tweak) [feat:test-automation-agent-20261111-deliverydedupe-len-is-untested-backend-a] ---

# --- 27B-decomposed from roadmap [2026-11-11]: `normalize_test_plan` error paths are untested - `backend/app/utils/plan_normalizer.py` `n (review + tweak) [feat:test-automation-agent-20261111-normalize-test-plan-error-paths-are-unte] ---

# --- 27B-decomposed from roadmap [2026-11-11]: `validate_ws_token` has no test for its rejection branches - `backend/app/utils/ws_auth.py (review + tweak) [feat:test-automation-agent-20261111-validate-ws-token-has-no-test-for-its-re] ---

# --- 27B-decomposed from roadmap [2026-11-11]: `ConnectionManager.send_personal` error handling is untested - `backend/app/services/webso (review + tweak) [feat:test-automation-agent-20261111-connectionmanager-send-personal-error-ha] ---

# --- 27B-decomposed from roadmap [2026-11-11]: `get_flake_index_data` without a customer and the empty-list shortcut of `get_flake_index_ (review + tweak) [feat:test-automation-agent-20261111-get-flake-index-data-without-a-customer-] ---

# --- 27B-decomposed from roadmap [2026-11-11]: `KnowledgeBaseService.store_success` upsert behaviour is untested - `backend/app/services/ (review + tweak) [feat:test-automation-agent-20261111-knowledgebaseservice-store-success-upser] ---

# --- 27B-decomposed from roadmap [2026-11-11]: The billing webhook's Stripe-unavailable 503 paths are untested - `backend/app/routers/bil (review + tweak) [feat:test-automation-agent-20261111-the-billing-webhook-s-stripe-unavailable] ---

# --- 27B-decomposed from roadmap [2026-11-11]: `is_retryable_status` is never called by a test - `backend/app/utils/retry_backoff.py` `is (review + tweak) [feat:test-automation-agent-20261111-is-retryable-status-is-never-called-by-a] ---

# --- 27B-decomposed from roadmap [2026-11-11]: `update_check_run` summary output and its 65535-character cap are untested - `backend/app/ (review + tweak) [feat:test-automation-agent-20261111-update-check-run-summary-output-and-its-] ---

# --- 27B-decomposed from roadmap [2026-11-11]: `list_uploads` status filter is untested at the service level - `backend/app/services/uplo (review + tweak) [feat:test-automation-agent-20261111-list-uploads-status-filter-is-untested-a] ---

# --- 27B-decomposed from roadmap [2026-11-11]: `update_upload_status` ownership and not-found behaviour are untested - `backend/app/servi (review + tweak) [feat:test-automation-agent-20261111-update-upload-status-ownership-and-not-f] ---

# --- 27B-decomposed from roadmap [2026-11-11]: Remove the duplicated input guard in `duration_bucket.bucket` - `backend/app/utils/duratio (review + tweak) [feat:test-automation-agent-20261111-remove-the-duplicated-input-guard-in-dur] ---

# --- 27B-decomposed from roadmap [2026-11-11]: `tests/utils/test_suite_health.py` contains three identical copies of two tests - `backend (review + tweak) [feat:test-automation-agent-20261111-tests-utils-test-suite-health-py-contain] ---

# --- 27B-decomposed from roadmap [2026-11-11]: `test_websocket_service_type_hints.py` defines `test_cleanup_run_has_return_type_hint` twi (review + tweak) [feat:test-automation-agent-20261111-test-websocket-service-type-hints-py-def] ---

# --- 27B-decomposed from roadmap [2026-11-11]: Run report exports: JUnit XML and CSV — `GET /api/test-runs/{run_id}/report` only offers J (review + tweak) [feat:test-automation-agent-20261111-run-report-exports-junit-xml-and-csv-get] ---

# --- 27B-decomposed from roadmap [2026-11-11]: Run history filter by plan name — the run lists can filter only by status; a user can narr (review + tweak) [feat:test-automation-agent-20261111-run-history-filter-by-plan-name-the-run-] ---

# --- 27B-decomposed from roadmap [2026-11-12]: Python SDK convenience methods — the SDK cannot cancel a run, page through results, or cre (review + tweak) [feat:test-automation-agent-20261112-python-sdk-convenience-methods-the-sdk-c] ---

# --- 27B-decomposed from roadmap [2026-11-12]: Flake dashboard: recent results, sorting and filtering — `FlakeDashboardPage.vue` shows on (review + tweak) [feat:test-automation-agent-20261112-flake-dashboard-recent-results-sorting-a] ---

# --- 27B-decomposed from roadmap [2026-11-12]: OpenAPI documentation quality — the generated OpenAPI has no description, no tag descripti (review + tweak) [feat:test-automation-agent-20261112-openapi-documentation-quality-the-genera] ---

# --- 27B-decomposed from roadmap [2026-11-12]: Starter test plan templates — the plan editor opens with one hard-coded example; a user ca (review + tweak) [feat:test-automation-agent-20261112-starter-test-plan-templates-the-plan-edi] ---

# --- 27B-decomposed from roadmap [2026-11-12]: API keys page: choose scopes and copy the new key — `frontend/src/pages/ApiKeysPage.vue` a (review + tweak) [feat:test-automation-agent-20261112-api-keys-page-choose-scopes-and-copy-the] ---

# --- 27B-decomposed from roadmap [2026-11-13]: Self-healing page: filter, search and sort the healed selectors — `frontend/src/pages/Self (review + tweak) [feat:test-automation-agent-20261113-self-healing-page-filter-search-and-sort] ---

# --- 27B-decomposed from roadmap [2026-11-13]: Dashboard pass rate — `frontend/src/pages/DashboardPage.vue` shows total, active, passed a (review + tweak) [feat:test-automation-agent-20261113-dashboard-pass-rate-frontend-src-pages-d] ---

# --- 27B-decomposed from roadmap [2026-11-13]: Organizations page: ordered members, a marker for yourself and a two-step remove — `fronte (review + tweak) [feat:test-automation-agent-20261113-organizations-page-ordered-members-a-mar] ---

# --- 27B-decomposed from roadmap [2026-11-13]: Test plan editor: action reference from the schema endpoint — `GET /api/test-plans/schema` (review + tweak) [feat:test-automation-agent-20261113-test-plan-editor-action-reference-from-t] ---

# --- 27B-decomposed from roadmap [2026-11-15]: Visual diffs page: paging through all flagged results — `GET /api/visual-diffs` already ac (review + tweak) [feat:test-automation-agent-20261115-visual-diffs-page-paging-through-all-fla] ---

# --- 27B-decomposed from roadmap [2026-11-16]: Notification history shows when, which HTTP status and why — `frontend/src/pages/Notificat (review + tweak) [feat:test-automation-agent-20261116-notification-history-shows-when-which-ht] ---

# --- 27B-decomposed from roadmap [2026-11-16]: Run comparison page — a user who wants to know what changed between two runs of a plan has (review + tweak) [feat:test-automation-agent-20261116-run-comparison-page-a-user-who-wants-to-] ---

# --- 27B-decomposed from roadmap [2026-11-16]: Schedule form: plain-language cron hint, presets and labelled remove buttons — `frontend/s (review + tweak) [feat:test-automation-agent-20261116-schedule-form-plain-language-cron-hint-p] ---

# --- 27B-decomposed from roadmap [2026-11-16]: Public API reference doc pinned to the OpenAPI schema — the public `/api/v1` API has docst (review + tweak) [feat:test-automation-agent-20261116-public-api-reference-doc-pinned-to-the-o] ---

# --- 27B-decomposed from roadmap [2026-11-16]: SDK command line — a CI job that only needs to list runs or wait for one has to write Pyth (review + tweak) [feat:test-automation-agent-20261116-sdk-command-line-a-ci-job-that-only-need] ---

# --- 27B-decomposed from roadmap [2026-11-16]: Notification endpoint form: readable, grouped event choices — `frontend/src/pages/Notifica (review + tweak) [feat:test-automation-agent-20261116-notification-endpoint-form-readable-grou] ---

# --- 27B-decomposed from roadmap [2026-11-16]: Test plan editor: label the YAML box, name the result table columns and validate from the  (review + tweak) [feat:test-automation-agent-20261116-test-plan-editor-label-the-yaml-box-name] ---

# --- 27B-decomposed from roadmap [2026-11-16]: Test runs list: sort order, a count line and the flaky status — `frontend/src/pages/TestRu (review + tweak) [feat:test-automation-agent-20261116-test-runs-list-sort-order-a-count-line-a] ---

# --- 27B-decomposed from roadmap [2026-11-16]: Run detail timeline: filter by status and search by test name — `frontend/src/pages/TestRu (review + tweak) [feat:test-automation-agent-20261116-run-detail-timeline-filter-by-status-and] ---

# --- 27B-decomposed from roadmap [2026-11-16]: Run detail: copy a failure summary — after a failed run a user has to copy test names and  (review + tweak) [feat:test-automation-agent-20261116-run-detail-copy-a-failure-summary-after-] ---

# --- 27B-decomposed from roadmap [2026-11-16]: Usage page: tests remaining this month — `frontend/src/pages/UsagePage.vue` shows `used /  (review + tweak) [feat:test-automation-agent-20261116-usage-page-tests-remaining-this-month-fr] ---

# --- 27B-decomposed from roadmap [2026-11-16]: SDK result summary helpers — a CI script that fetches run results with `SpecPilotClient.ge (review + tweak) [feat:test-automation-agent-20261116-sdk-result-summary-helpers-a-ci-script-t] ---

# --- 27B-decomposed from roadmap [2026-11-17]: Run status reference pinned to the code — the allowed run statuses and transitions live on (review + tweak) [feat:test-automation-agent-20261117-run-status-reference-pinned-to-the-code-] ---

# --- 27B-decomposed from roadmap [2026-11-17]: Markdown run report, step 1 of 3 - NEW `backend/app/utils/markdown_report.py` with `escape (review + tweak) [feat:test-automation-agent-20261117-markdown-run-report-step-1-of-3-new-back] ---

# --- 27B-decomposed from roadmap [2026-11-17]: Markdown run report, step 2 of 3 - the module `backend/app/utils/markdown_report.py` from  (review + tweak) [feat:test-automation-agent-20261117-markdown-run-report-step-2-of-3-the-modu] ---

# --- 27B-decomposed from roadmap [2026-11-17]: Markdown run report, step 3 of 3 - the module `backend/app/utils/markdown_report.py` from  (review + tweak) [feat:test-automation-agent-20261117-markdown-run-report-step-3-of-3-the-modu] ---

# --- 27B-decomposed from roadmap [2026-11-17]: Failure grouping by error message, step 1 of 3 - NEW `backend/app/utils/failure_groups.py` (review + tweak) [feat:test-automation-agent-20261117-failure-grouping-by-error-message-step-1] ---

# --- 27B-decomposed from roadmap [2026-11-17]: Failure grouping by error message, step 2 of 3 - the module `backend/app/utils/failure_gro (review + tweak) [feat:test-automation-agent-20261117-failure-grouping-by-error-message-step-2] ---

# --- 27B-decomposed from roadmap [2026-11-17]: Failure grouping by error message, step 3 of 3 - the module `backend/app/utils/failure_gro (review + tweak) [feat:test-automation-agent-20261117-failure-grouping-by-error-message-step-3] ---

# --- 27B-decomposed from roadmap [2026-11-17]: One-line run summary text, step 1 of 2 - NEW `backend/app/utils/run_summary_text.py` with  (review + tweak) [feat:test-automation-agent-20261117-one-line-run-summary-text-step-1-of-2-ne] ---

# --- 27B-decomposed from roadmap [2026-11-17]: One-line run summary text, step 2 of 2 - the module `backend/app/utils/run_summary_text.py (review + tweak) [feat:test-automation-agent-20261117-one-line-run-summary-text-step-2-of-2-th] ---

# --- 27B-decomposed from roadmap [2026-11-17]: Dashboard: relative time and the latest failed run, step 1 of 3 - NEW `frontend/src/utils/ (review + tweak) [feat:test-automation-agent-20261117-dashboard-relative-time-and-the-latest-f] ---

# --- 27B-decomposed from roadmap [2026-11-17]: Dashboard: relative time and the latest failed run, step 2 of 3 - `frontend/src/pages/Dash (review + tweak) [feat:test-automation-agent-20261117-dashboard-relative-time-and-the-latest-f] ---

# --- 27B-decomposed from roadmap [2026-11-17]: Dashboard: relative time and the latest failed run, step 3 of 3 - `frontend/src/pages/Dash (review + tweak) [feat:test-automation-agent-20261117-dashboard-relative-time-and-the-latest-f] ---

# --- 27B-decomposed from roadmap [2026-11-17]: Page window helper for list responses, step 1 of 2 - NEW `backend/app/utils/page_window.py (review + tweak) [feat:test-automation-agent-20261117-page-window-helper-for-list-responses-st] ---

# --- 27B-decomposed from roadmap [2026-11-17]: Page window helper for list responses, step 2 of 2 - the module `backend/app/utils/page_wi (review + tweak) [feat:test-automation-agent-20261117-page-window-helper-for-list-responses-st] ---

# --- 27B-decomposed from roadmap [2026-11-17]: Dashboard metrics reference pinned to the code, step 1 of 1 - NEW `docs/DASHBOARD_METRICS. (review + tweak) [feat:test-automation-agent-20261117-dashboard-metrics-reference-pinned-to-th] ---

# --- 27B-decomposed from roadmap [2026-11-19]: Usage text helpers shared by the web pages, step 1 of 2 - NEW `frontend/src/utils/compactN (review + tweak) [feat:test-automation-agent-20261119-usage-text-helpers-shared-by-the-web-pag] ---

# --- 27B-decomposed from roadmap [2026-11-19]: Usage text helpers shared by the web pages, step 2 of 2 - NEW `frontend/src/utils/passRate (review + tweak) [feat:test-automation-agent-20261119-usage-text-helpers-shared-by-the-web-pag] ---

# --- 27B-decomposed from roadmap [2026-11-19]: Test plan statistics, step 1 of 2 - NEW `backend/app/utils/plan_stats.py` with `plan_stats (review + tweak) [feat:test-automation-agent-20261119-test-plan-statistics-step-1-of-2-new-bac] ---

# --- 27B-decomposed from roadmap [2026-11-19]: Test plan statistics, step 2 of 2 - the module `backend/app/utils/plan_stats.py` from the  (review + tweak) [feat:test-automation-agent-20261119-test-plan-statistics-step-2-of-2-the-mod] ---

# --- 27B-decomposed from roadmap [2026-11-20]: Test plan action reference pinned to the orchestrator, step 1 of 2 - NEW `docs/TEST_PLAN_A (review + tweak) [feat:test-automation-agent-20261120-test-plan-action-reference-pinned-to-the] ---

# --- 27B-decomposed from roadmap [2026-11-20]: Test plan action reference pinned to the orchestrator, step 2 of 2 - `docs/TEST_PLAN_ACTIO (review + tweak) [feat:test-automation-agent-20261120-test-plan-action-reference-pinned-to-the] ---

# --- 27B-decomposed from roadmap [2026-11-20]: Test duration summary helpers, step 1 of 3 - NEW `backend/app/utils/duration_stats.py` wit (review + tweak) [feat:test-automation-agent-20261120-test-duration-summary-helpers-step-1-of-] ---

# --- 27B-decomposed from roadmap [2026-11-20]: Test duration summary helpers, step 2 of 3 - the module `backend/app/utils/duration_stats. (review + tweak) [feat:test-automation-agent-20261120-test-duration-summary-helpers-step-2-of-] ---

# --- 27B-decomposed from roadmap [2026-11-20]: Test duration summary helpers, step 3 of 3 - the module `backend/app/utils/duration_stats. (review + tweak) [feat:test-automation-agent-20261120-test-duration-summary-helpers-step-3-of-] ---

# --- 27B-decomposed from roadmap [2026-11-21]: Shared run status badge classes for the web, step 1 of 2 - NEW `frontend/src/utils/statusB (review + tweak) [feat:test-automation-agent-20261121-shared-run-status-badge-classes-for-the-] ---

# --- 27B-decomposed from roadmap [2026-11-21]: Shared run status badge classes for the web, step 2 of 2 - NEW `frontend/src/utils/__tests (review + tweak) [feat:test-automation-agent-20261121-shared-run-status-badge-classes-for-the-] ---

# --- 27B-decomposed from roadmap [2026-11-21]: Run result comparison, step 1 of 5 - NEW `backend/app/utils/run_compare.py` with `status_b (review + tweak) [feat:test-automation-agent-20261121-run-result-comparison-step-1-of-5-new-ba] ---

# --- 27B-decomposed from roadmap [2026-11-21]: Run result comparison, step 2 of 5 - the module `backend/app/utils/run_compare.py` from th (review + tweak) [feat:test-automation-agent-20261121-run-result-comparison-step-2-of-5-the-mo] ---

# --- 27B-decomposed from roadmap [2026-11-21]: Run result comparison, step 3 of 5 - the module `backend/app/utils/run_compare.py` and NEW (review + tweak) [feat:test-automation-agent-20261121-run-result-comparison-step-3-of-5-the-mo] ---

# --- 27B-decomposed from roadmap [2026-11-21]: Run result comparison, step 4 of 5 - the module `backend/app/utils/run_compare.py` and NEW (review + tweak) [feat:test-automation-agent-20261121-run-result-comparison-step-4-of-5-the-mo] ---

# --- 27B-decomposed from roadmap [2026-11-21]: Run result comparison, step 5 of 5 - NEW `docs/RUN_COMPARE.md` (title `# Run result compar (review + tweak) [feat:test-automation-agent-20261121-run-result-comparison-step-5-of-5-new-do] ---

# --- 27B-decomposed from roadmap [2026-11-21]: Test plan lint warnings, step 1 of 5 - NEW `backend/app/utils/plan_lint.py` with `PLAN_LIN (review + tweak) [feat:test-automation-agent-20261121-test-plan-lint-warnings-step-1-of-5-new-] ---

# --- 27B-decomposed from roadmap [2026-11-21]: Test plan lint warnings, step 2 of 5 - the module `backend/app/utils/plan_lint.py` and NEW (review + tweak) [feat:test-automation-agent-20261121-test-plan-lint-warnings-step-2-of-5-the-] ---

# --- 27B-decomposed from roadmap [2026-11-22]: Test plan lint warnings, step 3 of 5 - the module `backend/app/utils/plan_lint.py` and NEW (review + tweak) [feat:test-automation-agent-20261122-test-plan-lint-warnings-step-3-of-5-the-] ---

# --- 27B-decomposed from roadmap [2026-11-22]: Test plan lint warnings, step 4 of 5 - the module `backend/app/utils/plan_lint.py` and NEW (review + tweak) [feat:test-automation-agent-20261122-test-plan-lint-warnings-step-4-of-5-the-] ---

# --- 27B-decomposed from roadmap [2026-11-22]: Test plan lint warnings, step 5 of 5 - NEW `docs/PLAN_LINT.md` (title `# Test plan lint`)  (review + tweak) [feat:test-automation-agent-20261122-test-plan-lint-warnings-step-5-of-5-new-] ---

# --- 27B-decomposed from roadmap [2026-11-22]: Browser and viewport matrix helpers, step 1 of 4 - NEW `backend/app/utils/browser_matrix.p (review + tweak) [feat:test-automation-agent-20261122-browser-and-viewport-matrix-helpers-step] ---

# --- 27B-decomposed from roadmap [2026-11-22]: Browser and viewport matrix helpers, step 2 of 4 - the module `backend/app/utils/browser_m (review + tweak) [feat:test-automation-agent-20261122-browser-and-viewport-matrix-helpers-step] ---

# --- 27B-decomposed from roadmap [2026-11-22]: Browser and viewport matrix helpers, step 3 of 4 - the module `backend/app/utils/browser_m (review + tweak) [feat:test-automation-agent-20261122-browser-and-viewport-matrix-helpers-step] ---

# --- 27B-decomposed from roadmap [2026-11-22]: Browser and viewport matrix helpers, step 4 of 4 - NEW `docs/BROWSER_MATRIX.md` (title `#  (review + tweak) [feat:test-automation-agent-20261122-browser-and-viewport-matrix-helpers-step] ---

# --- 27B-decomposed from roadmap [2026-11-22]: Cron schedule preview, step 1 of 3 - NEW `backend/app/utils/cron_preview.py` with `next_cr (review + tweak) [feat:test-automation-agent-20261122-cron-schedule-preview-step-1-of-3-new-ba] ---

# --- 27B-decomposed from roadmap [2026-11-22]: Cron schedule preview, step 2 of 3 - the module `backend/app/utils/cron_preview.py` and NE (review + tweak) [feat:test-automation-agent-20261122-cron-schedule-preview-step-2-of-3-the-mo] ---

# --- 27B-decomposed from roadmap [2026-11-22]: Cron schedule preview, step 3 of 3 - NEW `docs/CRON_PREVIEW.md` (title `# Cron schedule pr (review + tweak) [feat:test-automation-agent-20261122-cron-schedule-preview-step-3-of-3-new-do] ---

# --- 27B-decomposed from roadmap [2026-11-22]: Webhook event reference pinned to the validator, step 1 of 1 - NEW `docs/WEBHOOK_EVENTS.md (review + tweak) [feat:test-automation-agent-20261122-webhook-event-reference-pinned-to-the-va] ---

# --- 27B-decomposed from roadmap [2026-11-23]: Text helpers for the web app, step 1 of 3 - NEW `frontend/src/utils/listText.ts` exporting (review + tweak) [feat:test-automation-agent-20261123-text-helpers-for-the-web-app-step-1-of-3] ---

# --- 27B-decomposed from roadmap [2026-11-23]: Text helpers for the web app, step 2 of 3 - NEW `frontend/src/utils/truncateMiddle.ts` exp (review + tweak) [feat:test-automation-agent-20261123-text-helpers-for-the-web-app-step-2-of-3] ---

# --- 27B-decomposed from roadmap [2026-11-23]: Text helpers for the web app, step 3 of 3 - NEW `frontend/src/utils/parseDurationInput.ts` (review + tweak) [feat:test-automation-agent-20261123-text-helpers-for-the-web-app-step-3-of-3] ---

# --- 27B-decomposed from roadmap [2026-11-23]: Add the duration list helper - create `backend/app/utils/duration_report.py` with `duratio (review + tweak) [feat:test-automation-agent-20261123-add-the-duration-list-helper-create-back] ---

# --- 27B-decomposed from roadmap [2026-11-23]: Add the slowest tests helper - in `backend/app/utils/duration_report.py` add `slowest_test (review + tweak) [feat:test-automation-agent-20261123-add-the-slowest-tests-helper-in-backend-] ---

# --- 27B-decomposed from roadmap [2026-11-23]: Add the run durations router - create `backend/app/routers/run_durations.py` with `router  (review + tweak) [feat:test-automation-agent-20261123-add-the-run-durations-router-create-back] ---

# --- 27B-decomposed from roadmap [2026-11-23]: Wire the run durations router - in `backend/app/main.py` add `run_durations` to the existi (review + tweak) [feat:test-automation-agent-20261123-wire-the-run-durations-router-in-backend] ---

# --- 27B-decomposed from roadmap [2026-11-23]: Add the pass rate to the run summary - in `get_test_run_summary` of `backend/app/routers/t (review + tweak) [feat:test-automation-agent-20261123-add-the-pass-rate-to-the-run-summary-in-] ---

# --- 27B-decomposed from roadmap [2026-11-23]: Add the run link to the run summary - in `get_test_run_summary` of `backend/app/routers/te (review + tweak) [feat:test-automation-agent-20261123-add-the-run-link-to-the-run-summary-in-g] ---

# --- 27B-decomposed from roadmap [2026-11-23]: Add the fix priority to the flake item - in `_serialize` of `backend/app/routers/flakes.py (review + tweak) [feat:test-automation-agent-20261123-add-the-fix-priority-to-the-flake-item-i] ---
- [ ] [T2] backend/tests/test_flake_item_fix_priority.py — Create test file with unit tests for `_serialize` verifying `fix_priority` calculation for normal and null inputs VERIFY: `cd backend && python3 -m pytest tests/test_flake_item_fix_priority.py -q`. (cat:test; multifile:no) [feat:test-automation-agent-20261123-add-the-fix-priority-to-the-flake-item-i]
- [ ] [T3] backend/app/routers/flakes.py — Import `compute_flake_priority` from `app.utils.flake_priority` at the top of the file VERIFY: `cd backend && grep -q "from app.utils.flake_priority import compute_flake_priority" app/routers/flakes.py`. (cat:python; multifile:no) [feat:test-automation-agent-20261123-add-the-fix-priority-to-the-flake-item-i]

# --- 27B-decomposed from roadmap [2026-11-23]: Add the sort parameter to the flake list - in `list_flakes` of `backend/app/routers/flakes (review + tweak) [feat:test-automation-agent-20261123-add-the-sort-parameter-to-the-flake-list] ---
- [ ] [T1] backend/app/utils/flake_priority.py — Add `compute_flake_priority(score: float, total_runs: int) -> float` that returns `score * math.log2(total_runs + 1)` and handle `total_runs <= 0` by returning 0.0 VERIFY: `cd backend && python3 -c "from app.utils.flake_priority import compute_flake_priority; assert abs(compute_flake_priority(0.5, 100) - (0.5 * __import__('math').log2(101))) < 1e-9"` (cat:python; multifile:no) [feat:test-automation-agent-20261123-add-the-sort-parameter-to-the-flake-list]
- [ ] [T3] backend/app/routers/flakes.py — Add `sort: str = Query("score")` to `list_flakes` signature and insert logic after stats load to sort by `compute_flake_priority` descending then `test_name` ascending if `sort == "priority"` VERIFY: `cd backend && python3 -c "import inspect; from app.routers.flakes import list_flakes; sig = inspect.signature(list_flakes); assert 'sort' in sig.parameters"` (cat:endpoint; multifile:no) [feat:test-automation-agent-20261123-add-the-sort-parameter-to-the-flake-list]
- [ ] [T4] backend/tests/test_flake_list_sort.py — Create async tests using `authenticated_client` and `test_session_factory` seeding two `TestFlakeStat` rows (0.9/2 runs, 0.5/100 runs) to assert default/score order puts 0.9 first, priority order puts 0.5 first, and nonsense sort returns 200 with default order VERIFY: `cd backend && python3 -m pytest tests/test_flake_list_sort.py -q` (cat:test; multifile:no) [feat:test-automation-agent-20261123-add-the-sort-parameter-to-the-flake-list]

# --- 27B-decomposed from roadmap [2026-11-23]: Add the progress percent helper - create `backend/app/utils/run_progress.py` with `progres (review + tweak) [feat:test-automation-agent-20261123-add-the-progress-percent-helper-create-b] ---
- [ ] [T1] backend/app/utils/run_progress.py — Add `progress_percent` function returning 0.0 for total <= 0 and rounded clamped percentage otherwise VERIFY: `cd backend && python3 -c "from app.utils.run_progress import progress_percent; assert progress_percent(0, 0) == 0.0; assert progress_percent(1, 2) == 50.0"`. (cat:python; multifile:no) [feat:test-automation-agent-20261123-add-the-progress-percent-helper-create-b]
- [ ] [T2] backend/tests/test_run_progress_percent.py — Add `test_zero_total_is_zero` and `test_negative_completed_is_zero` verifying edge cases for total=0 and completed<0 VERIFY: `cd backend && python3 -m pytest tests/test_run_progress_percent.py::test_zero_total_is_zero tests/test_run_progress_percent.py::test_negative_completed_is_zero -q`. (cat:test; multifile:no) [feat:test-automation-agent-20261123-add-the-progress-percent-helper-create-b]
- [ ] [T2] backend/tests/test_run_progress_percent.py — Add `test_half_done_is_50` and `test_done_is_100` verifying standard progress calculations VERIFY: `cd backend && python3 -m pytest tests/test_run_progress_percent.py::test_half_done_is_50 tests/test_run_progress_percent.py::test_done_is_100 -q`. (cat:test; multifile:no) [feat:test-automation-agent-20261123-add-the-progress-percent-helper-create-b]
- [ ] [T2] backend/tests/test_run_progress_percent.py — Add `test_over_completed_is_capped_at_100` verifying that completed > total results in 100.0 VERIFY: `cd backend && python3 -m pytest tests/test_run_progress_percent.py::test_over_completed_is_capped_at_100 -q`. (cat:test; multifile:no) [feat:test-automation-agent-20261123-add-the-progress-percent-helper-create-b]

# --- 27B-decomposed from roadmap [2026-11-23]: Add the elapsed helper - in `backend/app/utils/run_progress.py` add `elapsed_seconds(start (review + tweak) [feat:test-automation-agent-20261123-add-the-elapsed-helper-in-backend-app-ut] ---
- [ ] [T1] backend/app/utils/run_progress.py — Add `elapsed_seconds(started_at: datetime | None, finished_at: datetime | None, now: datetime) -> float` handling None started_at, naive/aware datetime normalization to UTC, clamping negative values to 0.0, and rounding to 1 decimal place. VERIFY: `cd backend && python3 -c "from app.utils.run_progress import elapsed_seconds; from datetime import datetime, timezone; assert elapsed_seconds(None, None, datetime.now(timezone.utc)) == 0.0"`. (cat:python; multifile:no) [feat:test-automation-agent-20261123-add-the-elapsed-helper-in-backend-app-ut]
- [ ] [T1] backend/tests/test_run_progress_elapsed.py — Create test file with `test_unstarted_run_is_zero` and `test_finished_run_uses_the_finish_time` verifying basic calculation logic for None started_at and completed runs. VERIFY: `cd backend && python3 -m pytest tests/test_run_progress_elapsed.py::test_unstarted_run_is_zero tests/test_run_progress_elapsed.py::test_finished_run_uses_the_finish_time -q`. (cat:test; multifile:no) [feat:test-automation-agent-20261123-add-the-elapsed-helper-in-backend-app-ut]
- [ ] [T1] backend/tests/test_run_progress_elapsed.py — Add `test_running_run_uses_now` and `test_negative_difference_is_zero` verifying behavior when finished_at is None and when finished_at is before started_at. VERIFY: `cd backend && python3 -m pytest tests/test_run_progress_elapsed.py::test_running_run_uses_now tests/test_run_progress_elapsed.py::test_negative_difference_is_zero -q`. (cat:test; multifile:no) [feat:test-automation-agent-20261123-add-the-elapsed-helper-in-backend-app-ut]
- [ ] [T1] backend/tests/test_run_progress_elapsed.py — Add `test_naive_and_aware_datetimes_can_be_mixed` verifying that naive datetimes are treated as UTC and can be subtracted from aware datetimes without TypeError. VERIFY: `cd backend && python3 -m pytest tests/test_run_progress_elapsed.py::test_naive_and_aware_datetimes_can_be_mixed -q`. (cat:test; multifile:no) [feat:test-automation-agent-20261123-add-the-elapsed-helper-in-backend-app-ut]

# --- 27B-decomposed from roadmap [2026-11-23]: Add the run progress router - create `backend/app/routers/run_progress.py` with `router =  (review + tweak) [feat:test-automation-agent-20261123-add-the-run-progress-router-create-backe] ---
- [ ] [T3] backend/app/utils/throughput.py — Add `elapsed_seconds(start: datetime, end: datetime | None, now: datetime) -> float` function that calculates seconds between start and end (or now if end is None). VERIFY: `cd backend && python3 -c "from app.utils.throughput import elapsed_seconds; from datetime import datetime, timezone; s = datetime(2024,1,1, tzinfo=timezone.utc); e = datetime(2024,1,1, minute=1, tzinfo=timezone.utc); assert elapsed_seconds(s, e, datetime.now(timezone.utc)) == 60.0"`. (cat:python; multifile:no) [feat:test-automation-agent-20261123-add-the-run-progress-router-create-backe]
- [ ] [T1] backend/app/utils/run_progress.py — Add `progress_percent(completed: int, total: int) -> float` and `tests_per_minute(completed: int, elapsed_seconds: float) -> float` functions. VERIFY: `cd backend && python3 -c "from app.utils.run_progress import progress_percent, tests_per_minute; assert progress_percent(5, 10) == 50.0; assert tests_per_minute(5, 60) == 5.0"`. (cat:python; multifile:no) [feat:test-automation-agent-20261123-add-the-run-progress-router-create-backe]
- [ ] [T2] backend/app/utils/eta.py — Add `remaining_seconds(completed: int, total: int, elapsed_seconds: float) -> float | None` function that returns `None` if `completed == 0` or `total <= completed`, otherwise calculates remaining time based on current rate. VERIFY: `cd backend && python3 -c "from app.utils.eta import remaining_seconds; assert remaining_seconds(5, 10, 60) == 60.0; assert remaining_seconds(0, 10, 60) is None"`. (cat:python; multifile:no) [feat:test-automation-agent-20261123-add-the-run-progress-router-create-backe]
- [ ] [T4] backend/app/routers/run_progress.py — Create file with `router = APIRouter(prefix="/api/test-runs", tags=["test-runs"])` and `GET /{run_id}/progress` endpoint that fetches run, checks ownership, calculates metrics using helpers from `app.utils.run_progress`, `app.utils.eta`, and `app.utils.throughput`, and returns JSON response. VERIFY: `cd backend && python3 -c "from app.routers.run_progress import router; assert router.prefix == '/api/test-runs'"`. (cat:endpoint; multifile:no) [feat:test-automation-agent-20261123-add-the-run-progress-router-create-backe]
- [ ] [T5] backend/app/routers/__init__.py — Import `run_progress` router and include it in the main router aggregation. VERIFY: `cd backend && python3 -c "from app.routers import api_router; assert any(hasattr(r, 'routes') and any(getattr(r, 'path', '') == '/api/test-runs/{run_id}/progress' for r in r.routes) for r in [api_router])"`. (cat:python; multifile:no) [feat:test-automation-agent-20261123-add-the-run-progress-router-create-backe]

# --- 27B-decomposed from roadmap [2026-11-23]: Wire the run progress router - in `backend/app/main.py` add `run_progress` to the existing (review + tweak) [feat:test-automation-agent-20261123-wire-the-run-progress-router-in-backend-] ---
- [ ] [T3] backend/app/routers/run_progress.py — Add `summary="Get the progress of a test run"` to the `@router.get("/{run_id}/progress")` decorator if it is missing. VERIFY: `cd backend && python3 -c "from app.routers.run_progress import router; assert any('summary' in str(r) for r in router.routes)"`. (cat:endpoint; multifile:no) [feat:test-automation-agent-20261123-wire-the-run-progress-router-in-backend-]
- [ ] [T3] backend/app/main.py — Add `run_progress` to the `from app.routers import ...` line and add `app.include_router(run_progress.router)` immediately after `app.include_router(test_runs.router)`. VERIFY: `cd backend && python3 -c "from app.main import app; assert '/api/test-runs/{run_id}/progress' in app.openapi()['paths']"`. (cat:python; multifile:no) [feat:test-automation-agent-20261123-wire-the-run-progress-router-in-backend-]
- [ ] [T1] backend/tests/test_run_progress_wired.py — Create file with `test_progress_route_registered` asserting `/api/test-runs/{run_id}/progress` is in `app.openapi()['paths']`. VERIFY: `cd backend && python3 -m pytest tests/test_run_progress_wired.py::test_progress_route_registered -q`. (cat:test; multifile:no) [feat:test-automation-agent-20261123-wire-the-run-progress-router-in-backend-]
- [ ] [T1] backend/tests/test_run_progress_wired.py — Add `test_progress_has_a_summary` asserting the `get` operation for `/api/test-runs/{run_id}/progress` has a non-empty `summary`. VERIFY: `cd backend && python3 -m pytest tests/test_run_progress_wired.py::test_progress_has_a_summary -q`. (cat:test; multifile:no) [feat:test-automation-agent-20261123-wire-the-run-progress-router-in-backend-]

# --- 27B-decomposed from roadmap [2026-11-23]: Make the healing event sort robust to missing values - in `backend/app/utils/sort_healing_ (review + tweak) [feat:test-automation-agent-20261123-make-the-healing-event-sort-robust-to-mi] ---
- [ ] [T1] backend/app/utils/sort_healing_events.py — Modify `get_confidence_key` to return 0 if `confidence` is None or a bool instance. VERIFY: `cd backend && python3 -c "from app.utils.sort_healing_events import get_confidence_key; assert get_confidence_key({'confidence': None}) == 0; assert get_confidence_key({'confidence': True}) == 0"`. (cat:python; multifile:no) [feat:test-automation-agent-20261123-make-the-healing-event-sort-robust-to-mi]
- [ ] [T1] backend/app/utils/sort_healing_events.py — Modify `get_time_key` to return `datetime.min` if `timestamp` is not a string instance. VERIFY: `cd backend && python3 -c "from app.utils.sort_healing_events import get_time_key; from datetime import datetime; assert get_time_key({'timestamp': 123}) == datetime.min"`. (cat:python; multifile:no) [feat:test-automation-agent-20261123-make-the-healing-event-sort-robust-to-mi]
- [ ] [T2] backend/tests/test_sort_healing_events_missing_values.py — Add `test_explicit_null_confidence_sorts_as_zero` verifying that an event with `confidence: None` sorts to the end in descending confidence mode. VERIFY: `cd backend && python3 -m pytest tests/test_sort_healing_events_missing_values.py::test_explicit_null_confidence_sorts_as_zero -q`. (cat:test; multifile:no) [feat:test-automation-agent-20261123-make-the-healing-event-sort-robust-to-mi]
- [ ] [T2] backend/tests/test_sort_healing_events_missing_values.py — Add `test_boolean_confidence_sorts_as_zero` verifying that an event with `confidence: True` sorts to the end in descending confidence mode. VERIFY: `cd backend && python3 -m pytest tests/test_sort_healing_events_missing_values.py::test_boolean_confidence_sorts_as_zero -q`. (cat:test; multifile:no) [feat:test-automation-agent-20261123-make-the-healing-event-sort-robust-to-mi]
- [ ] [T2] backend/tests/test_sort_healing_events_missing_values.py — Add `test_non_string_timestamp_sorts_as_oldest` verifying that an event with a non-string timestamp sorts to the end in descending time mode. VERIFY: `cd backend && python3 -m pytest tests/test_sort_healing_events_missing_values.py::test_non_string_timestamp_sorts_as_oldest -q`. (cat:test; multifile:no) [feat:test-automation-agent-20261123-make-the-healing-event-sort-robust-to-mi]
- [ ] [T2] backend/tests/test_sort_healing_events_missing_values.py — Add `test_the_three_modes_still_order_a_clean_list` verifying correct ordering for 'newest', 'oldest', and 'confidence' modes with valid data. VERIFY: `cd backend && python3 -m pytest tests/test_sort_healing_events_missing_values.py::test_the_three_modes_still_order_a_clean_list -q`. (cat:test; multifile:no) [feat:test-automation-agent-20261123-make-the-healing-event-sort-robust-to-mi]

# --- 27B-decomposed from roadmap [2026-11-23]: Add the sort parameter to the healing history - in `get_healing_history` of `backend/app/r (review + tweak) [feat:test-automation-agent-20261123-add-the-sort-parameter-to-the-healing-hi] ---
- [ ] [T1] backend/app/utils/sort_healing_events.py — Add `sort_healing_events(events: list[dict], sort_key: str) -> list[dict]` that returns a new list sorted by `timestamp` desc for "newest", `timestamp` asc for "oldest", and `confidence` desc for "confidence", defaulting to "newest" for invalid keys. VERIFY: `cd backend && python3 -c "from app.utils.sort_healing_events import sort_healing_events; print(sort_healing_events([{'timestamp': '2026-01-01T00:00:00+00:00', 'confidence': 0.9}, {'timestamp': '2026-01-02T00:00:00+00:00', 'confidence': 0.2}], 'oldest')[0]['timestamp'])"`. (cat:python; multifile:no) [feat:test-automation-agent-20261123-add-the-sort-parameter-to-the-healing-hi]
- [ ] [T3] backend/app/routers/self_healing.py — Import `sort_healing_events` from `app.utils.sort_healing_events`, add `sort: str = Query("newest")` parameter to `get_healing_history`, and replace the existing sort logic with `events = sort_healing_events(events, sort if sort in ("newest", "oldest", "confidence") else "newest")` before slicing. VERIFY: `cd backend && python3 -c "from app.routers.self_healing import get_healing_history; import inspect; sig = inspect.signature(get_healing_history); assert 'sort' in sig.parameters"`. (cat:python; multifile:no) [feat:test-automation-agent-20261123-add-the-sort-parameter-to-the-healing-hi]
- [ ] [T2] backend/tests/test_self_healing_history_sort.py — Create async tests using `authenticated_client` and `test_session_factory` that seed a run for `test-customer` with two `TestResult` rows containing healing events with timestamps `2026-01-01T00:00:00+00:00` (conf 0.9) and `2026-01-02T00:00:00+00:00` (conf 0.2), asserting default/`sort=newest` lists later event first, `sort=oldest` lists earlier first, `sort=confidence` lists 0.9 first, and `sort=nonsense` returns 200 in default order. VERIFY: `cd backend && python3 -m pytest tests/test_self_healing_history_sort.py -q`. (cat:test; multifile:no) [feat:test-automation-agent-20261123-add-the-sort-parameter-to-the-healing-hi]

# --- 27B-decomposed from roadmap [2026-11-23]: Add the comparison table builder - NEW `backend/app/utils/run_compare_table.py` with `comp (review + tweak) [feat:test-automation-agent-20261123-add-the-comparison-table-builder-new-bac] ---
- [ ] [T1] backend/app/utils/run_compare_table.py — Add `compare_status_tables` function implementing union of names, last-status deduplication, missing status handling, change classification (regressed/improved/unchanged), and summary counting logic. VERIFY: `cd backend && python3 -c "from app.utils.run_compare_table import compare_status_tables; print(compare_status_tables([], []))"`. (cat:python; multifile:no) [feat:test-automation-agent-20261123-add-the-comparison-table-builder-new-bac]
- [ ] [T1] backend/tests/utils/test_run_compare_table.py — Add `test_union_of_names_sorted` verifying that distinct test names from both lists are included in the output sorted alphabetically. VERIFY: `cd backend && python3 -m pytest tests/utils/test_run_compare_table.py::test_union_of_names_sorted -q`. (cat:test; multifile:no) [feat:test-automation-agent-20261123-add-the-comparison-table-builder-new-bac]
- [ ] [T1] backend/tests/utils/test_run_compare_table.py — Add `test_missing_status` verifying that a test name present in only one run has "missing" for the absent status. VERIFY: `cd backend && python3 -m pytest tests/utils/test_run_compare_table.py::test_missing_status -q`. (cat:test; multifile:no) [feat:test-automation-agent-20261123-add-the-comparison-table-builder-new-bac]
- [ ] [T1] backend/tests/utils/test_run_compare_table.py — Add `test_regressed_and_improved` verifying that passed->failed is "regressed" and failed->passed is "improved". VERIFY: `cd backend && python3 -m pytest tests/utils/test_run_compare_table.py::test_regressed_and_improved -q`. (cat:test; multifile:no) [feat:test-automation-agent-20261123-add-the-comparison-table-builder-new-bac]
- [ ] [T1] backend/tests/utils/test_run_compare_table.py — Add `test_unchanged_for_same_status` verifying that identical statuses result in "unchanged" change type. VERIFY: `cd backend && python3 -m pytest tests/utils/test_run_compare_table.py::test_unchanged_for_same_status -q`. (cat:test; multifile:no) [feat:test-automation-agent-20261123-add-the-comparison-table-builder-new-bac]
- [ ] [T1] backend/tests/utils/test_run_compare_table.py — Add `test_summary_counts_use_run_b` verifying that summary counts total tests, passed (run_b), and failed (run_b) correctly. VERIFY: `cd backend && python3 -m pytest tests/utils/test_run_compare_table.py::test_summary_counts_use_run_b -q`. (cat:test; multifile:no) [feat:test-automation-agent-20261123-add-the-comparison-table-builder-new-bac]

# --- 27B-decomposed from roadmap [2026-11-23]: Add the compare router and mount it before the run routes - NEW `backend/app/routers/run_c (review + tweak) [feat:test-automation-agent-20261123-add-the-compare-router-and-mount-it-befo] ---
- [ ] [T1] backend/app/utils/ci_result.py — Add pure function `compare_status_tables(list_a: list[dict], list_b: list[dict]) -> dict` that returns a dictionary with keys "added", "removed", and "changed" containing lists of test names based on status differences between the two input lists. VERIFY: `cd backend && python3 -c "from app.utils.ci_result import compare_status_tables; assert compare_status_tables([{'test_name': 'a', 'status': 'passed'}], []) == {'added': [], 'removed': ['a'], 'changed': []}"`. (cat:python; multifile:no) [feat:test-automation-agent-20261123-add-the-compare-router-and-mount-it-befo]
- [ ] [T4] backend/app/routers/__init__.py — Add `run_compare` to the existing import statement from `app.routers` module. VERIFY: `cd backend && python3 -c "from app.routers import run_compare; assert hasattr(run_compare, 'router')"`. (cat:python; multifile:no) [feat:test-automation-agent-20261123-add-the-compare-router-and-mount-it-befo]
- [ ] [T3] backend/app/routers/run_compare.py — Create new file with `router = APIRouter(prefix="/api/test-runs", tags=["test-runs"])` and endpoint `GET /compare` that loads two `TestRun` objects by ID filtered by `current_user.customer_id`, returns 404 if missing, loads associated `TestResult` rows ordered by `created_at, id`, and returns the comparison payload using `compare_status_tables`. VERIFY: `cd backend && python3 -c "from app.routers.run_compare import router; assert router.prefix == '/api/test-runs'"`. (cat:endpoint; multifile:no) [feat:test-automation-agent-20261123-add-the-compare-router-and-mount-it-befo]
- [ ] [T2] backend/tests/test_ci_result.py — Add test case for `compare_status_tables` verifying it correctly identifies tests with changed statuses when both lists contain the same test name but different status values. VERIFY: `cd backend && python3 -m pytest tests/test_ci_result.py::test_compare_status_tables_changed -v`. (cat:test; multifile:no) [feat:test-automation-agent-20261123-add-the-compare-router-and-mount-it-befo]
- [ ] [T5] backend/app/main.py — Import `run_compare` in the existing router imports and add `app.include_router(run_compare.router)` immediately before the line `app.include_router(test_runs.router)`. VERIFY: `cd backend && python3 -c "from app.main import app; assert '/api/test-runs/compare' in app.openapi()['paths']"`. (cat:python; multifile:no) [feat:test-automation-agent-20261123-add-the-compare-router-and-mount-it-befo]

# --- 27B-decomposed from roadmap [2026-11-23]: Pin the compare endpoint behaviour - this step adds no application code and only a test fi (review + tweak) [feat:test-automation-agent-20261123-pin-the-compare-endpoint-behaviour-this-] ---
- [ ] [T1] backend/tests/test_run_compare_router.py — Add `test_compare_reports_a_regression` verifying that a test passing in run A and failing in run B returns 200 with `change == "regressed"`. VERIFY: `cd backend && python3 -m pytest tests/test_run_compare_router.py::test_compare_reports_a_regression -q`. (cat:test; multifile:no) [feat:test-automation-agent-20261123-pin-the-compare-endpoint-behaviour-this-]
- [ ] [T1] backend/tests/test_run_compare_router.py — Add `test_compare_unknown_run_is_404` verifying that comparing against a non-existent run ID returns 404. VERIFY: `cd backend && python3 -m pytest tests/test_run_compare_router.py::test_compare_unknown_run_is_404 -q`. (cat:test; multifile:no) [feat:test-automation-agent-20261123-pin-the-compare-endpoint-behaviour-this-]
- [ ] [T1] backend/tests/test_run_compare_router.py — Add `test_compare_other_customers_run_is_404` verifying that accessing another customer's run returns 404. VERIFY: `cd backend && python3 -m pytest tests/test_run_compare_router.py::test_compare_other_customers_run_is_404 -q`. (cat:test; multifile:no) [feat:test-automation-agent-20261123-pin-the-compare-endpoint-behaviour-this-]
- [ ] [T1] backend/tests/test_run_compare_router.py — Add `test_compare_requires_auth` verifying that unauthenticated requests to the compare endpoint return 401 or 403. VERIFY: `cd backend && python3 -m pytest tests/test_run_compare_router.py::test_compare_requires_auth -q`. (cat:test; multifile:no) [feat:test-automation-agent-20261123-pin-the-compare-endpoint-behaviour-this-]

# --- 27B-decomposed from roadmap [2026-11-23]: Register the compare page route - in `frontend/src/router/index.js` add `{ path: '/runs/co (review + tweak) [feat:test-automation-agent-20261123-register-the-compare-page-route-in-front] ---
- [ ] [T1] frontend/src/router/index.js — Add the `/runs/compare` route entry with `name: 'RunCompare'`, dynamic import of `../pages/RunComparePage.vue`, and `meta: { requiresAuth: true, title: 'Compare Runs' }` immediately before the `/runs/:id` route definition. VERIFY: `grep -n "path: '/runs/compare'" frontend/src/router/index.js && grep -n "name: 'RunCompare'" frontend/src/router/index.js`. (cat:vue; multifile:no) [feat:test-automation-agent-20261123-register-the-compare-page-route-in-front]
- [ ] [T1] frontend/src/router/__tests__/runCompareRoute.test.js — Create the test file importing `router` from `'../index'` and add a test case `'compare resolves to the compare page'` that asserts `router.resolve('/runs/compare').name === 'RunCompare'`. VERIFY: `cd frontend && npx vitest run src/router/__tests__/runCompareRoute.test.js -t "compare resolves"`. (cat:test; multifile:no) [feat:test-automation-agent-20261123-register-the-compare-page-route-in-front]
- [ ] [T1] frontend/src/router/__tests__/runCompareRoute.test.js — Add a test case `'a run id still resolves to the detail page'` that asserts `router.resolve('/runs/abc').name === 'TestRunDetail'` to ensure the new route does not shadow the dynamic ID route. VERIFY: `cd frontend && npx vitest run src/router/__tests__/runCompareRoute.test.js -t "a run id still resolves"`. (cat:test; multifile:no) [feat:test-automation-agent-20261123-register-the-compare-page-route-in-front]
- [ ] [T2] frontend/src/pages/RunComparePage.vue — Ensure the component file exists at this path with a default export Vue component (create if missing, or verify existing structure) to satisfy the dynamic import in the router. VERIFY: `test -f frontend/src/pages/RunComparePage.vue && grep -q "export default" frontend/src/pages/RunComparePage.vue`. (cat:vue; multifile:no) [feat:test-automation-agent-20261123-register-the-compare-page-route-in-front]
- [ ] [T2] frontend/src/router/__tests__/runCompareRoute.test.js — Run the full test suite for the router to verify both specific assertions pass and no other route resolutions are broken by the insertion. VERIFY: `cd frontend && npx vitest run src/router/__tests__/runCompareRoute.test.js`. (cat:test; multifile:no) [feat:test-automation-agent-20261123-register-the-compare-page-route-in-front]

# --- 27B-decomposed from roadmap [2026-11-23]: Link the runs page to the compare page - in `frontend/src/pages/TestRunsPage.vue` add `<ro (review + tweak) [feat:test-automation-agent-20261123-link-the-runs-page-to-the-compare-page-i] ---
- [ ] [T3] frontend/src/pages/TestRunsPage.vue — Insert `<router-link to="/runs/compare" class="px-4 py-2 border border-gray-300 rounded-lg text-gray-700 hover:bg-gray-50">Compare runs</router-link>` immediately after the Refresh button in the filters row. VERIFY: `cd frontend && npx vitest run src/pages/__tests__/TestRunsPage-compare-link.spec.js`. (cat:vue; multifile:no) [feat:test-automation-agent-20261123-link-the-runs-page-to-the-compare-page-i]
- [ ] [T1] frontend/src/pages/__tests__/TestRunsPage-compare-link.spec.js — Create test file that mounts `TestRunsPage.vue` with `router-link` stubbed as an anchor and asserts existence of link to `/runs/compare` with text "Compare runs". VERIFY: `cd frontend && npx vitest run src/pages/__tests__/TestRunsPage-compare-link.spec.js`. (cat:test; multifile:no) [feat:test-automation-agent-20261123-link-the-runs-page-to-the-compare-page-i]

# --- 27B-decomposed from roadmap [2026-11-23]: Add the run deletion service - NEW `backend/app/services/run_deletion.py` with `async def  (review + tweak) [feat:test-automation-agent-20261123-add-the-run-deletion-service-new-backend] ---
- [ ] [T1] backend/app/services/run_deletion.py — Create module with `async def delete_run(db: AsyncSession, storage: ArtifactStorage, customer_id: str, run_id: str) -> dict` that queries `TestRun` by id and customer_id, returns `{"deleted": False, "reason": "not_found"}` if missing, checks `is_terminal_status(run.status.value)` from `app.utils.run_status` returning `{"deleted": False, "reason": "active"}` if false, otherwise counts and deletes associated `Artifact` and `TestResult` rows, unlinks artifact files via `storage.resolve(a.path).unlink(missing_ok=True)` (skipping on `ValueError`/`OSError`), deletes the `TestRun`, commits, and returns `{"deleted": True, "results": n_results, "artifacts": n_artifacts}`. VERIFY: `cd backend && python3 -c "from app.services.run_deletion import delete_run; print('ok')"`. (cat:python; multifile:no) [feat:test-automation-agent-20261123-add-the-run-deletion-service-new-backend]
- [ ] [T2] backend/tests/test_run_deletion_service.py — Create test file with async fixtures using `test_session_factory` and `ArtifactStorage(root=str(tmp_path))`, seeding data similar to `backend/tests/test_artifacts_endpoints.py`, containing `test_deletes_rows_and_files` which asserts DB rows are gone and files unlinked, and `test_unknown_run_is_not_found` which asserts the not_found response. VERIFY: `cd backend && python3 -m pytest tests/test_run_deletion_service.py::test_deletes_rows_and_files tests/test_run_deletion_service.py::test_unknown_run_is_not_found -q`. (cat:test; multifile:no) [feat:test-automation-agent-20261123-add-the-run-deletion-service-new-backend]
- [ ] [T2] backend/tests/test_run_deletion_service.py — Add `test_active_run_is_kept` which seeds a non-terminal run and asserts the response is `{"deleted": False, "reason": "active"}` and the row persists, and `test_other_customers_run_is_not_found` which asserts a different customer_id yields not_found. VERIFY: `cd backend && python3 -m pytest tests/test_run_deletion_service.py::test_active_run_is_kept tests/test_run_deletion_service.py::test_other_customers_run_is_not_found -q`. (cat:test; multifile:no) [feat:test-automation-agent-20261123-add-the-run-deletion-service-new-backend]
- [ ] [T2] backend/tests/test_run_deletion_service.py — Add `test_missing_file_does_not_block_deletion` which seeds an artifact with a path that does not exist on disk and asserts deletion succeeds with `deleted: True` despite the missing file. VERIFY: `cd backend && python3 -m pytest tests/test_run_deletion_service.py::test_missing_file_does_not_block_deletion -q`. (cat:test; multifile:no) [feat:test-automation-agent-20261123-add-the-run-deletion-service-new-backend]

# --- 27B-decomposed from roadmap [2026-11-23]: Add the delete endpoint and mount it - NEW `backend/app/routers/run_delete.py` with `route (review + tweak) [feat:test-automation-agent-20261123-add-the-delete-endpoint-and-mount-it-new] ---
- [ ] [T3] backend/app/routers/run_delete.py — Import `delete_run` from `app.services.execution_engine` (or appropriate service module if not there, but feature implies service call) and `artifacts_router` from `app.routers`, then call `delete_run(db, artifacts_router.storage, current_user.customer_id, run_id)` inside the endpoint. VERIFY: `cd backend && python3 -c "import inspect; from app.routers import run_delete; src = inspect.getsource(run_delete); assert 'delete_run' in src and 'artifacts_router.storage' in src"`. (cat:endpoint; multifile:no) [feat:test-automation-agent-20261123-add-the-delete-endpoint-and-mount-it-new]
- [ ] [T3] backend/app/main.py — Add `run_delete` to the existing `from app.routers import ...` line and add `app.include_router(run_delete.router)` immediately after `app.include_router(artifacts.router)`. VERIFY: `cd backend && python3 -c "from app.main import app; assert '/api/test-runs/{run_id}' in app.openapi()['paths']"`. (cat:endpoint; multifile:no) [feat:test-automation-agent-20261123-add-the-delete-endpoint-and-mount-it-new]
- [ ] [T1] backend/app/routers/run_delete.py — Create new file with `router = APIRouter(prefix="/api/test-runs", tags=["test-runs"])` and a stub `DELETE /{run_id}` endpoint returning 204. VERIFY: `cd backend && python3 -c "from app.routers.run_delete import router; assert any(r.path == '/api/test-runs/{run_id}' for r in router.routes)"`. (cat:endpoint; multifile:no) [feat:test-automation-agent-20261123-add-the-delete-endpoint-and-mount-it-new]
- [ ] [T2] backend/app/routers/run_delete.py — Add `current_user: User = Depends(get_current_user)` and `db: Session = Depends(get_db)` parameters to the endpoint, importing from `app.core.auth` and `app.core.database`. VERIFY: `cd backend && python3 -c "from app.routers.run_delete import router; ep = [r for r in router.routes if r.path == '/api/test-runs/{run_id}'][0]; assert 'current_user' in ep.dependant.query_params or 'current_user' in ep.dependant.body_params or any('current_user' in str(p) for p in ep.dependant.dependencies)"`. (cat:endpoint; multifile:no) [feat:test-automation-agent-20261123-add-the-delete-endpoint-and-mount-it-new]
- [ ] [T4] backend/app/routers/run_delete.py — Add exception handling for `not_found` returning 404 with detail "Test run not found" and `active` returning 409 with detail "Cannot delete a run that is still active". VERIFY: `cd backend && python3 -c "import inspect; from app.routers import run_delete; src = inspect.getsource(run_delete); assert '404' in src or 'HTTPException(status_code=404' in src; assert '409' in src or 'HTTPException(status_code=409' in src"`. (cat:endpoint; multifile:no) [feat:test-automation-agent-20261123-add-the-delete-endpoint-and-mount-it-new]
- [ ] [T1] backend/tests/test_run_delete.py — Create test file with a test that mocks `delete_run` to raise `not_found` and asserts the endpoint returns 404. VERIFY: `cd backend && python3 -m pytest tests/test_run_delete.py::test_delete_not_found -v`. (cat:test; multifile:no) [feat:test-automation-agent-20261123-add-the-delete-endpoint-and-mount-it-new]
- [ ] [T1] backend/tests/test_run_delete.py — Add a test that mocks `delete_run` to raise `active` and asserts the endpoint returns 409. VERIFY: `cd backend && python3 -m pytest tests/test_run_delete.py::test_delete_active -v`. (cat:test; multifile:no) [feat:test-automation-agent-20261123-add-the-delete-endpoint-and-mount-it-new]
- [ ] [T1] backend/tests/test_run_delete.py — Add a test that mocks `delete_run` to succeed and asserts the endpoint returns 204. VERIFY: `cd backend && python3 -m pytest tests/test_run_delete.py::test_delete_success -v`. (cat:test; multifile:no) [feat:test-automation-agent-20261123-add-the-delete-endpoint-and-mount-it-new]

# --- 27B-decomposed from roadmap [2026-11-24]: Pin the delete endpoint behaviour - this step adds no application code and only a test fil (review + tweak) [feat:test-automation-agent-20261124-pin-the-delete-endpoint-behaviour-this-s] ---
- [ ] [T1] backend/tests/test_run_delete_router.py — Add `test_delete_completed_run_answers_204_and_removes_it` verifying 204 response, subsequent GET 404, and artifact file deletion. VERIFY: `cd backend && python3 -m pytest tests/test_run_delete_router.py::test_delete_completed_run_answers_204_and_removes_it -q`. (cat:test; multifile:no) [feat:test-automation-agent-20261124-pin-the-delete-endpoint-behaviour-this-s]
- [ ] [T1] backend/tests/test_run_delete_router.py — Add `test_delete_running_run_answers_409_and_keeps_it` verifying 409 response and artifact file persistence. VERIFY: `cd backend && python3 -m pytest tests/test_run_delete_router.py::test_delete_running_run_answers_409_and_keeps_it -q`. (cat:test; multifile:no) [feat:test-automation-agent-20261124-pin-the-delete-endpoint-behaviour-this-s]
- [ ] [T1] backend/tests/test_run_delete_router.py — Add `test_delete_unknown_run_answers_404` verifying 404 response for non-existent run ID. VERIFY: `cd backend && python3 -m pytest tests/test_run_delete_router.py::test_delete_unknown_run_answers_404 -q`. (cat:test; multifile:no) [feat:test-automation-agent-20261124-pin-the-delete-endpoint-behaviour-this-s]
- [ ] [T1] backend/tests/test_run_delete_router.py — Add `test_delete_other_customers_run_answers_404` verifying 404 response for cross-tenant access attempt. VERIFY: `cd backend && python3 -m pytest tests/test_run_delete_router.py::test_delete_other_customers_run_answers_404 -q`. (cat:test; multifile:no) [feat:test-automation-agent-20261124-pin-the-delete-endpoint-behaviour-this-s]
- [ ] [T1] backend/tests/test_run_delete_router.py — Add `test_delete_requires_auth` verifying 401 response for unauthenticated request. VERIFY: `cd backend && python3 -m pytest tests/test_run_delete_router.py::test_delete_requires_auth -q`. (cat:test; multifile:no) [feat:test-automation-agent-20261124-pin-the-delete-endpoint-behaviour-this-s]

# --- 27B-decomposed from roadmap [2026-11-24]: Add the delete action to the web store - NEW `frontend/src/stores/runDelete.js` exporting  (review + tweak) [feat:test-automation-agent-20261124-add-the-delete-action-to-the-web-store-n] ---
- [ ] [T2] frontend/src/stores/runDelete.js — Implement error handling in `deleteRun` to set `error` ref to `err.response?.data?.detail || 'Failed to delete the run'` on failure and return `false`. VERIFY: `cd frontend && npx vitest run src/stores/__tests__/runDelete.test.js -t 'a 409 sets the detail as the error'`. (cat:typescript; multifile:no) [feat:test-automation-agent-20261124-add-the-delete-action-to-the-web-store-n]
- [ ] [T3] frontend/src/stores/runDelete.js — Ensure `deleting` ref is set to `true` before request and `false` in `finally` block. VERIFY: `cd frontend && npx vitest run src/stores/__tests__/runDelete.test.js -t 'deleting is false after the call'`. (cat:typescript; multifile:no) [feat:test-automation-agent-20261124-add-the-delete-action-to-the-web-store-n]
- [ ] [T1] frontend/src/stores/runDelete.js — Add `useRunDeleteStore` Pinia setup store with `deleting`, `error` refs and `deleteRun` async action calling `axios.delete` to `${API_BASE}/test-runs/${runId}`. VERIFY: `cd frontend && npx vitest run src/stores/__tests__/runDelete.test.js -t 'deleteRun calls the delete route'`. (cat:typescript; multifile:no) [feat:test-automation-agent-20261124-add-the-delete-action-to-the-web-store-n]
- [ ] [T4] frontend/src/stores/__tests__/runDelete.test.js — Create test file mocking `axios` and `API_BASE`, implementing tests for successful delete, 409 error detail mapping, and `deleting` state reset. VERIFY: `cd frontend && npx vitest run src/stores/__tests__/runDelete.test.js`. (cat:test; multifile:no) [feat:test-automation-agent-20261124-add-the-delete-action-to-the-web-store-n]

# --- 27B-decomposed from roadmap [2026-11-24]: Add a delete button to the run detail page - in `frontend/src/pages/TestRunDetailPage.vue` (review + tweak) [feat:test-automation-agent-20261124-add-a-delete-button-to-the-run-detail-pa] ---
- [ ] [T1] frontend/src/stores/runDelete.js — Create store with `deleteRun` action that returns a boolean indicating success VERIFY: `cd frontend && npx vitest run src/stores/__tests__/runDelete.spec.js`. (cat:typescript; multifile:no) [feat:test-automation-agent-20261124-add-a-delete-button-to-the-run-detail-pa]
- [ ] [T2] frontend/src/pages/TestRunDetailPage.vue — Import `useRouter` from `vue-router` and `useRunDeleteStore` from `../stores/runDelete`, instantiate them, and add a `Delete run` button (`type="button"`, `data-testid="delete-run"`) visible only when status is in `['completed', 'failed', 'cancelled', 'flaky']` with a click handler that confirms via `window.confirm` and navigates to `/runs` on success VERIFY: `cd frontend && npx vitest run src/pages/__tests__/TestRunDetailPage-delete.spec.js`. (cat:vue; multifile:no) [feat:test-automation-agent-20261124-add-a-delete-button-to-the-run-detail-pa]
- [ ] [T3] frontend/src/pages/__tests__/TestRunDetailPage-delete.spec.js — Create test file mocking `vue-router` and `../stores/runDelete`, including tests for hidden button on running status, cancelled confirm, and successful delete navigation VERIFY: `cd frontend && npx vitest run src/pages/__tests__/TestRunDetailPage-delete.spec.js`. (cat:test; multifile:no) [feat:test-automation-agent-20261124-add-a-delete-button-to-the-run-detail-pa]

# --- 27B-decomposed from roadmap [2026-11-24]: Add the public run report endpoint and mount it - NEW `backend/app/routers/public_reports. (review + tweak) [feat:test-automation-agent-20261124-add-the-public-run-report-endpoint-and-m] ---
- [ ] [T1] backend/app/routers/public_reports.py — Add `router = APIRouter(prefix="/api/v1", tags=["public-api"])` and import `APIRouter`, `Request`, `Response`, `Query`, `Literal`, `Depends`, `select`, `async_sessionmaker`, `AsyncSession`, `ApiPrincipal`, `require_scope`, `public_api_limit`, `TestRun`, `TestResult`, `_render_junit_xml`, `render_csv_report`. VERIFY: `cd backend && python3 -c "from app.routers.public_reports import router; assert router.prefix == '/api/v1'"`. (cat:python; multifile:no) [feat:test-automation-agent-20261124-add-the-public-run-report-endpoint-and-m]
- [ ] [T2] backend/app/routers/public_reports.py — Add `GET /runs/{run_id}/report` endpoint with `@public_api_limit`, `fmt: Literal["junit", "csv"] = Query("junit", alias="format")`, `principal: ApiPrincipal = Depends(require_scope("runs:read"))`, `db: AsyncSession = Depends(get_db)`, loading `TestRun` where `customer_id == principal.customer_id` (404 if not found), building `report_data` with `run.test_plan_name`, timeline from `TestResult` ordered by `created_at, id`, and `total_duration_ms`. VERIFY: `cd backend && python3 -c "from app.routers.public_reports import router; assert any(r.path == '/runs/{run_id}/report' for r in router.routes)"`. (cat:python; multifile:no) [feat:test-automation-agent-20261124-add-the-public-run-report-endpoint-and-m]
- [ ] [T4] backend/app/main.py — Add `public_reports` to the `from app.routers import ...` line and add `app.include_router(public_reports.router)` immediately after `app.include_router(public_api.router)`. VERIFY: `cd backend && python3 -c "from app.main import app; assert 'get' in app.openapi()['paths']['/api/v1/runs/{run_id}/report']"`. (cat:python; multifile:no) [feat:test-automation-agent-20261124-add-the-public-run-report-endpoint-and-m]
- [ ] [T3] backend/app/routers/public_reports.py — Complete the endpoint logic to return `Response(content=_render_junit_xml(report_data), media_type="application/xml")` for `junit` or `Response(content=render_csv_report(report_data), media_type="text/csv")` for `csv`. VERIFY: `cd backend && python3 -c "from app.routers.public_reports import router; assert len(router.routes) == 1"`. (cat:python; multifile:no) [feat:test-automation-agent-20261124-add-the-public-run-report-endpoint-and-m]

# --- 27B-decomposed from roadmap [2026-11-24]: Pin the public run report behaviour - this step adds no application code and only a test f (review + tweak) [feat:test-automation-agent-20261124-pin-the-public-run-report-behaviour-this] ---
- [ ] [T1] backend/tests/test_public_reports_report.py — Add `test_junit_is_the_default` asserting `application/xml` content type, one `<testcase` per result, and a `<failure` tag for the failed test. VERIFY: `cd backend && python3 -m pytest tests/test_public_reports_report.py::test_junit_is_the_default -q`. (cat:test; multifile:no) [feat:test-automation-agent-20261124-pin-the-public-run-report-behaviour-this]
- [ ] [T1] backend/tests/test_public_reports_report.py — Add `test_csv_format` asserting the first line is `test_name,status,duration_ms,error_message,is_visual_regression`. VERIFY: `cd backend && python3 -m pytest tests/test_public_reports_report.py::test_csv_format -q`. (cat:test; multifile:no) [feat:test-automation-agent-20261124-pin-the-public-run-report-behaviour-this]
- [ ] [T1] backend/tests/test_public_reports_report.py — Add `test_other_tenants_run_is_404` asserting a 404 response when accessing a run from a different tenant. VERIFY: `cd backend && python3 -m pytest tests/test_public_reports_report.py::test_other_tenants_run_is_404 -q`. (cat:test; multifile:no) [feat:test-automation-agent-20261124-pin-the-public-run-report-behaviour-this]
- [ ] [T1] backend/tests/test_public_reports_report.py — Add `test_missing_key_is_rejected` asserting a 401/403 response when the `X-API-Key` header is missing. VERIFY: `cd backend && python3 -m pytest tests/test_public_reports_report.py::test_missing_key_is_rejected -q`. (cat:test; multifile:no) [feat:test-automation-agent-20261124-pin-the-public-run-report-behaviour-this]

# --- 27B-decomposed from roadmap [2026-11-24]: Add the public flake export endpoint - in `backend/app/routers/public_reports.py` add `GET (review + tweak) [feat:test-automation-agent-20261124-add-the-public-flake-export-endpoint-in-] ---
- [ ] [T1] backend/app/services/flake_detection.py — Add `list_stats(db: AsyncSession, customer_id: UUID) -> list[TestFlakeStat]` that queries `TestFlakeStat` filtered by `customer_id` and orders by `flake_score` desc. VERIFY: `cd backend && python3 -m pytest tests/test_flake_detection_list_stats.py -q`. (cat:python; multifile:no) [feat:test-automation-agent-20261124-add-the-public-flake-export-endpoint-in-]
- [ ] [T3] backend/app/routers/public_reports.py — Create file with `GET /flakes/export` endpoint using `@public_api_limit`, `principal` with `flakes:read` scope, calling `flake_detection.list_stats`, building CSV via `csv` module with header `test_name,flake_score,total_runs,fails,quarantined`, returning `Response(content=csv_text, media_type="text/csv")`. VERIFY: `cd backend && python3 -m pytest tests/test_public_reports_flakes.py -q`. (cat:endpoint; multifile:no) [feat:test-automation-agent-20261124-add-the-public-flake-export-endpoint-in-]
- [ ] [T3] backend/app/main.py — Import and include `public_reports` router with prefix `/api/v1/flakes` if not already registered. VERIFY: `cd backend && python3 -c "from app.main import app; assert '/api/v1/flakes/export' in app.openapi()['paths']"`. (cat:endpoint; multifile:no) [feat:test-automation-agent-20261124-add-the-public-flake-export-endpoint-in-]
- [ ] [T2] backend/tests/test_public_reports_flakes.py — Create test file with `test_export_lists_one_row_per_flake` seeding two `TestFlakeStat` for tenant A and one for tenant B, asserting CSV has header + 2 rows for tenant A. VERIFY: `cd backend && python3 -m pytest tests/test_public_reports_flakes.py::test_export_lists_one_row_per_flake -q`. (cat:test; multifile:no) [feat:test-automation-agent-20261124-add-the-public-flake-export-endpoint-in-]
- [ ] [T2] backend/tests/test_public_reports_flakes.py — Add `test_export_header_only_when_none` asserting CSV contains only header row when no stats exist for tenant. VERIFY: `cd backend && python3 -m pytest tests/test_public_reports_flakes.py::test_export_header_only_when_none -q`. (cat:test; multifile:no) [feat:test-automation-agent-20261124-add-the-public-flake-export-endpoint-in-]
- [ ] [T2] backend/tests/test_public_reports_flakes.py — Add `test_export_needs_flakes_scope` using a key with only `runs:read` scope, asserting response is 401 or 403. VERIFY: `cd backend && python3 -m pytest tests/test_public_reports_flakes.py::test_export_needs_flakes_scope -q`. (cat:test; multifile:no) [feat:test-automation-agent-20261124-add-the-public-flake-export-endpoint-in-]
- [ ] [T2] backend/tests/test_public_reports_flakes.py — Add `test_route_registered` asserting `/api/v1/flakes/export` exists in `app.openapi()['paths']`. VERIFY: `cd backend && python3 -m pytest tests/test_public_reports_flakes.py::test_route_registered -q`. (cat:test; multifile:no) [feat:test-automation-agent-20261124-add-the-public-flake-export-endpoint-in-]
