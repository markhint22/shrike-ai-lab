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
- [ ] [T3] frontend/src/pages/VisualDiffsPage.vue — Update `approve()` to reload current page via `store.fetchVisualDiffs(offset.value)` and step back one page if result is empty and `offset > 0`. VERIFY: `cd frontend && npx vitest run src/pages/__tests__/VisualDiffsPage-paging.spec.js -t "approving"`. (cat:vue; multifile:no) [feat:test-automation-agent-20261115-visual-diffs-page-paging-through-all-fla]
- [ ] [T3] frontend/src/pages/__tests__/VisualDiffsPage-paging.spec.js — Add tests verifying Next button calls `fetchVisualDiffs(20)`, Previous calls `fetchVisualDiffs(0)` after navigation, and nav is hidden when `total <= 20`. VERIFY: `cd frontend && npx vitest run src/pages/__tests__/VisualDiffsPage-paging.spec.js`. (cat:test; multifile:no) [feat:test-automation-agent-20261115-visual-diffs-page-paging-through-all-fla]

# --- 27B-decomposed from roadmap [2026-11-16]: Notification history shows when, which HTTP status and why — `frontend/src/pages/Notificat (review + tweak) [feat:test-automation-agent-20261116-notification-history-shows-when-which-ht] ---
- [ ] [T1] frontend/src/utils/deliveryDetail.js — Add `deliveryDetail(d)` returning array of strings: `HTTP <status>` if finite number, collapsed/truncated `last_error` (120 chars + ellipsis) only if status !== 'delivered' and error non-empty, and `formatDate(delivered_at || created_at)` unless '-'. VERIFY: `cd frontend && npx vitest run src/utils/__tests__/deliveryDetail.test.js` (cat:typescript; multifile:no) [feat:test-automation-agent-20261116-notification-history-shows-when-which-ht]
- [ ] [T2] frontend/src/utils/__tests__/deliveryDetail.test.js — Add tests for failed delivery with long multi-line error (verify 120 cut/ellipsis), delivered delivery (no error part), missing status code, and no dates (empty array). VERIFY: `cd frontend && npx vitest run src/utils/__tests__/deliveryDetail.test.js` (cat:test; multifile:no) [feat:test-automation-agent-20261116-notification-history-shows-when-which-ht]
- [ ] [T3] frontend/src/pages/NotificationsPage.vue — Import `deliveryDetail` and render `<p v-if="deliveryDetail(d).length" class="text-xs text-gray-500">{{ deliveryDetail(d).join(' · ') }}</p>` under each delivery `<li>`, wrapping existing row to keep Retry button placement. VERIFY: `cd frontend && npx vitest run src/pages/__tests__/NotificationsPage-delivery-detail.spec.js` (cat:vue; multifile:no) [feat:test-automation-agent-20261116-notification-history-shows-when-which-ht]
- [ ] [T4] frontend/src/pages/__tests__/NotificationsPage-delivery-detail.spec.js — Create spec mocking store, mounting page, and asserting that expanding history for a failed delivery with `response_status: 502` shows `HTTP 502` and error text. VERIFY: `cd frontend && npx vitest run src/pages/__tests__/NotificationsPage-delivery-detail.spec.js` (cat:test; multifile:no) [feat:test-automation-agent-20261116-notification-history-shows-when-which-ht]
- [ ] [T5] frontend/src/utils/deliveryDetail.js — Append `filterDeliveries(deliveries, mode)` (all/failed/delivered/unknown/non-array handling) and `summarizeDeliveries(deliveries)` returning `{ delivered, failed, pending }` counts. VERIFY: `cd frontend && npx vitest run src/utils/__tests__/deliveryDetail.test.js` (cat:typescript; multifile:no) [feat:test-automation-agent-20261116-notification-history-shows-when-which-ht]

# --- 27B-decomposed from roadmap [2026-11-16]: Run comparison page — a user who wants to know what changed between two runs of a plan has (review + tweak) [feat:test-automation-agent-20261116-run-comparison-page-a-user-who-wants-to-] ---
- [ ] [T1] frontend/src/utils/runComparison.js — Add `compareRuns` function that computes `newlyFailing`, `fixed`, `stillFailing`, `added`, `removed`, and `slower` buckets based on `test_name` matching, status logic, and duration thresholds. VERIFY: `cd frontend && npx vitest run src/utils/__tests__/runComparison.test.js`. (cat:typescript; multifile:no) [feat:test-automation-agent-20261116-run-comparison-page-a-user-who-wants-to-]
- [ ] [T2] frontend/src/utils/__tests__/runComparison.test.js — Add unit tests covering all buckets, boundary conditions for `slowerPct` and `minDeltaMs`, duplicate name handling, missing `results` arrays, and input immutability. VERIFY: `cd frontend && npx vitest run src/utils/__tests__/runComparison.test.js`. (cat:test; multifile:no) [feat:test-automation-agent-20261116-run-comparison-page-a-user-who-wants-to-]
- [ ] [T3] frontend/src/stores/testRuns.js — Add `fetchRunDetail(runId)` function that performs a GET request to `${API_BASE}/test-runs/${runId}`, returns `response.data` if it is an object, otherwise `null`, without modifying store state. VERIFY: `cd frontend && npx vitest run src/stores/__tests__/testRunsFetchDetail.test.js`. (cat:typescript; multifile:no) [feat:test-automation-agent-20261116-run-comparison-page-a-user-who-wants-to-]
- [ ] [T4] frontend/src/stores/__tests__/testRunsFetchDetail.test.js — Add tests for `fetchRunDetail` success, non-object response, request rejection, and verification that `currentRun`, `loading`, and `error` remain unchanged. VERIFY: `cd frontend && npx vitest run src/stores/__tests__/testRunsFetchDetail.test.js`. (cat:test; multifile:no) [feat:test-automation-agent-20261116-run-comparison-page-a-user-who-wants-to-]
- [ ] [T5] frontend/src/pages/RunComparePage.vue — Create Vue component that reads `route.query.a` and `b`, fetches run details on mount, displays loading/error states, and renders comparison buckets using `compareRuns`. VERIFY: `cd frontend && npx vitest run src/pages/__tests__/RunComparePage.spec.js`. (cat:vue; multifile:no) [feat:test-automation-agent-20261116-run-comparison-page-a-user-who-wants-to-]

# --- 27B-decomposed from roadmap [2026-11-16]: Schedule form: plain-language cron hint, presets and labelled remove buttons — `frontend/s (review + tweak) [feat:test-automation-agent-20261116-schedule-form-plain-language-cron-hint-p] ---
- [ ] [T1] frontend/src/utils/cronDescribe.js — Add `describeCron` and `cronFieldProblem` functions handling specific cron patterns and field validation. VERIFY: `cd frontend && npx vitest run src/utils/__tests__/cronDescribe.test.js`. (cat:typescript; multifile:no) [feat:test-automation-agent-20261116-schedule-form-plain-language-cron-hint-p]
- [ ] [T5] frontend/src/pages/CiIntegrationsPage.vue — Add `CRON_PRESETS` constant and `<select aria-label="Schedule preset">` before cron input, binding change to update `newSchedule.cron` and resetting select on successful create. VERIFY: `cd frontend && npx vitest run src/pages/__tests__/CiIntegrationsPage-cron-presets.spec.js`. (cat:vue; multifile:no) [feat:test-automation-agent-20261116-schedule-form-plain-language-cron-hint-p]
- [ ] [T3] frontend/src/pages/CiIntegrationsPage.vue — Add `aria-describedby="cron-hint"` to cron input and `<p id="cron-hint" aria-live="polite">` displaying `describeCron` or `cronFieldProblem` based on input state. VERIFY: `cd frontend && npx vitest run src/pages/__tests__/CiIntegrationsPage-cron-hint.spec.js`. (cat:vue; multifile:no) [feat:test-automation-agent-20261116-schedule-form-plain-language-cron-hint-p]
- [ ] [T2] frontend/src/utils/__tests__/cronDescribe.test.js — Add unit tests for `describeCron` patterns, zero-padding, null returns for invalid inputs, and `cronFieldProblem` outcomes. VERIFY: `cd frontend && npx vitest run src/utils/__tests__/cronDescribe.test.js`. (cat:test; multifile:no) [feat:test-automation-agent-20261116-schedule-form-plain-language-cron-hint-p]
- [ ] [T4] frontend/src/pages/__tests__/CiIntegrationsPage-cron-hint.spec.js — Add tests verifying hint text for valid cron, invalid field count, empty input, and `aria-describedby` attribute presence. VERIFY: `cd frontend && npx vitest run src/pages/__tests__/CiIntegrationsPage-cron-hint.spec.js`. (cat:test; multifile:no) [feat:test-automation-agent-20261116-schedule-form-plain-language-cron-hint-p]

# --- 27B-decomposed from roadmap [2026-11-16]: Public API reference doc pinned to the OpenAPI schema — the public `/api/v1` API has docst (review + tweak) [feat:test-automation-agent-20261116-public-api-reference-doc-pinned-to-the-o] ---
- [ ] [T1] docs/PUBLIC_API.md — Add title `# SpecPilot public API (v1)`, `## Authentication` section explaining `X-API-Key`, and `## Endpoints` table with rows for `GET /api/v1/runs`, `GET /api/v1/runs/{run_id}`, `GET /api/v1/runs/{run_id}/results`, `POST /api/v1/runs`, `POST /api/v1/plans/validate`, `GET /api/v1/flakes`, `POST /api/v1/runs/{run_id}/cancel` mapping to scopes `runs:read`, `runs:write`, `plans:read`, `flakes:read`. VERIFY: `cd backend && python3 -m pytest tests/test_public_api_doc_pinned.py -q -k "test_doc_structure"`. (cat:docs; multifile:no) [feat:test-automation-agent-20261116-public-api-reference-doc-pinned-to-the-o]
- [ ] [T1] backend/tests/test_public_api_doc_pinned.py — Create test file with `test_doc_structure` asserting `docs/PUBLIC_API.md` exists, contains headings `## Authentication` and `## Endpoints`, and that every backticked `METHOD /api/v1/...` pair in the Endpoints table exists in `app.openapi()['paths']`. VERIFY: `cd backend && python3 -m pytest tests/test_public_api_doc_pinned.py -q -k "test_doc_structure"`. (cat:test; multifile:no) [feat:test-automation-agent-20261116-public-api-reference-doc-pinned-to-the-o]
- [ ] [T2] docs/PUBLIC_API.md — Add `## Scopes` section listing each value from `VALID_SCOPES` in `backend/app/services/api_keys.py` with a one-sentence description. VERIFY: `cd backend && python3 -m pytest tests/test_public_api_doc_pinned.py -q -k "test_every_valid_scope_is_documented"`. (cat:docs; multifile:no) [feat:test-automation-agent-20261116-public-api-reference-doc-pinned-to-the-o]
- [ ] [T2] backend/tests/test_public_api_doc_pinned.py — Add `test_every_valid_scope_is_documented` that imports `VALID_SCOPES` from `app.services.api_keys` and asserts each scope string appears in the content of `docs/PUBLIC_API.md`. VERIFY: `cd backend && python3 -m pytest tests/test_public_api_doc_pinned.py -q -k "test_every_valid_scope_is_documented"`. (cat:test; multifile:no) [feat:test-automation-agent-20261116-public-api-reference-doc-pinned-to-the-o]
- [ ] [T2] docs/PUBLIC_API.md — Add `## Examples` section with `curl` commands for `POST /api/v1/runs` (including `autostart`) and `GET /api/v1/runs?status=completed&limit=20`, plus `## Status codes` section documenting 401/403, 402, 422, and 429 with `Retry-After`. VERIFY: `cd backend && python3 -m pytest tests/test_public_api_doc_pinned.py -q -k "test_examples_and_status_codes"`. (cat:docs; multifile:no) [feat:test-automation-agent-20261116-public-api-reference-doc-pinned-to-the-o]
- [ ] [T2] backend/tests/test_public_api_doc_pinned.py — Add `test_examples_and_status_codes` asserting the doc contains `X-API-Key`, `autostart`, `402`, `422`, `Retry-After`, and that `backend/app/routers/public_api.py` source contains `status_code=402`. VERIFY: `cd backend && python3 -m pytest tests/test_public_api_doc_pinned.py -q -k "test_examples_and_status_codes"`. (cat:test; multifile:no) [feat:test-automation-agent-20261116-public-api-reference-doc-pinned-to-the-o]
- [ ] [T1] backend/tests/test_public_api_doc_pinned.py — Add `test_readme_links_the_public_api_doc` asserting the content of `README.md` contains the string `docs/PUBLIC_API.md`. VERIFY: `cd backend && python3 -m pytest tests/test_public_api_doc_pinned.py -q -k "test_readme_links_the_public_api_doc"`. (cat:test; multifile:no) [feat:test-automation-agent-20261116-public-api-reference-doc-pinned-to-the-o]
- [ ] [T1] README.md — Add a line in the API or documentation section linking to `docs/PUBLIC_API.md`. VERIFY: `cd backend && python3 -m pytest tests/test_public_api_doc_pinned.py -q -k "test_readme_links_the_public_api_doc"`. (cat:docs; multifile:no) [feat:test-automation-agent-20261116-public-api-reference-doc-pinned-to-the-o]

# --- 27B-decomposed from roadmap [2026-11-16]: SDK command line — a CI job that only needs to list runs or wait for one has to write Pyth (review + tweak) [feat:test-automation-agent-20261116-sdk-command-line-a-ci-job-that-only-need] ---
- [ ] [T1] sdk/python/specpilot_sdk/cli.py — Add `format_run_line(run: dict) -> str` and `format_runs(runs: list) -> str` with logic for missing keys and empty lists. VERIFY: `cd sdk/python && python3 -m pytest tests/test_cli_format.py -q`. (cat:python; multifile:no) [feat:test-automation-agent-20261116-sdk-command-line-a-ci-job-that-only-need]
- [ ] [T3] sdk/python/specpilot_sdk/cli.py — Add `main(argv=None, environ=None, client_factory=SpecPilotClient) -> int` handling `runs` and `run` subcommands with error handling for missing connection and `SpecPilotError`. VERIFY: `cd sdk/python && python3 -m pytest tests/test_cli_main.py -q`. (cat:python; multifile:no) [feat:test-automation-agent-20261116-sdk-command-line-a-ci-job-that-only-need]
- [ ] [T2] sdk/python/specpilot_sdk/cli.py — Add `build_parser() -> argparse.ArgumentParser` with subcommands `runs`, `run`, `wait` and global flags, plus `resolve_connection(args, environ) -> tuple[str, str] | None`. VERIFY: `cd sdk/python && python3 -m pytest tests/test_cli_parser.py -q`. (cat:python; multifile:no) [feat:test-automation-agent-20261116-sdk-command-line-a-ci-job-that-only-need]
- [ ] [T4] sdk/python/specpilot_sdk/cli.py — Extend `main` to handle the `wait` subcommand, calling `client.wait_for_run` and handling `TimeoutError` and terminal statuses. VERIFY: `cd sdk/python && python3 -m pytest tests/test_cli_wait.py -q`. (cat:python; multifile:no) [feat:test-automation-agent-20261116-sdk-command-line-a-ci-job-that-only-need]
- [ ] [T5] sdk/python/specpilot_sdk/__main__.py — Create entry point module importing `main` from `specpilot_sdk.cli` and raising `SystemExit(main())` under `if __name__ == "__main__":`. VERIFY: `cd sdk/python && python3 -m pytest tests/test_cli_entry.py -q`. (cat:python; multifile:no) [feat:test-automation-agent-20261116-sdk-command-line-a-ci-job-that-only-need]

# --- 27B-decomposed from roadmap [2026-11-16]: Notification endpoint form: readable, grouped event choices — `frontend/src/pages/Notifica (review + tweak) [feat:test-automation-agent-20261116-notification-endpoint-form-readable-grou] ---
- [ ] [T1] frontend/src/utils/eventLabels.js — Export `describeEvent(event)` that converts dot/underscore-separated strings to Title Case readable names and returns empty string for non-strings. VERIFY: `cd frontend && npx vitest run src/utils/__tests__/eventLabels.test.js`. (cat:typescript; multifile:no) [feat:test-automation-agent-20261116-notification-endpoint-form-readable-grou]
- [ ] [T1] frontend/src/utils/eventLabels.js — Export `groupEvents(events)` that groups events by prefix, orders groups as Run, Test, then alphabetical with Other last, and filters non-strings/duplicates. VERIFY: `cd frontend && npx vitest run src/utils/__tests__/eventLabels.test.js`. (cat:typescript; multifile:no) [feat:test-automation-agent-20261116-notification-endpoint-form-readable-grou]
- [ ] [T2] frontend/src/utils/__tests__/eventLabels.test.js — Add unit tests covering label generation, group ordering, Other handling, duplicate removal, and non-array input edge cases. VERIFY: `cd frontend && npx vitest run src/utils/__tests__/eventLabels.test.js`. (cat:test; multifile:no) [feat:test-automation-agent-20261116-notification-endpoint-form-readable-grou]
- [ ] [T3] frontend/src/pages/NotificationsPage.vue — Replace flat event checkbox list with grouped fieldsets using `groupEvents` and `describeEvent`, preserving raw event values in v-model. VERIFY: `cd frontend && npx vitest run src/pages/__tests__/NotificationsPage-event-groups.spec.js`. (cat:vue; multifile:no) [feat:test-automation-agent-20261116-notification-endpoint-form-readable-grou]
- [ ] [T3] frontend/src/pages/__tests__/NotificationsPage-event-groups.spec.js — Add tests verifying Run/Test legends render, checkbox labels are readable, and checking a box updates the create payload with raw event string. VERIFY: `cd frontend && npx vitest run src/pages/__tests__/NotificationsPage-event-groups.spec.js`. (cat:test; multifile:no) [feat:test-automation-agent-20261116-notification-endpoint-form-readable-grou]
- [ ] [T3] frontend/src/pages/NotificationsPage.vue — Add "Select all events" and "Clear events" buttons above groups that update `newHook.events`, plus a live region showing selection count. VERIFY: `cd frontend && npx vitest run src/pages/__tests__/NotificationsPage-event-groups.spec.js`. (cat:vue; multifile:no) [feat:test-automation-agent-20261116-notification-endpoint-form-readable-grou]
- [ ] [T3] frontend/src/pages/__tests__/NotificationsPage-event-groups.spec.js — Add tests for Select All/Clear button behavior and verify the aria-live count text updates correctly. VERIFY: `cd frontend && npx vitest run src/pages/__tests__/NotificationsPage-event-groups.spec.js`. (cat:test; multifile:no) [feat:test-automation-agent-20261116-notification-endpoint-form-readable-grou]
- [ ] [T3] frontend/src/pages/__tests__/NotificationsPage-event-groups.spec.js — Add test verifying that after successful webhook creation, the event selection resets to default and count text reflects the reset state. VERIFY: `cd frontend && npx vitest run src/pages/__tests__/NotificationsPage-event-groups.spec.js src/pages/__tests__/NotificationsPage.spec.js`. (cat:test; multifile:no) [feat:test-automation-agent-20261116-notification-endpoint-form-readable-grou]

# --- 27B-decomposed from roadmap [2026-11-16]: Test plan editor: label the YAML box, name the result table columns and validate from the  (review + tweak) [feat:test-automation-agent-20261116-test-plan-editor-label-the-yaml-box-name] ---
- [ ] [T1] frontend/src/utils/textStats.js — Add `countLines(text)` function returning 0 for non-string/empty else count of `\n` separated lines ignoring trailing newline. VERIFY: `cd frontend && npx vitest run src/utils/__tests__/textStats.test.js` (cat:typescript; multifile:no) [feat:test-automation-agent-20261116-test-plan-editor-label-the-yaml-box-name]
- [ ] [T3] frontend/src/pages/TestPlanEditorPage.vue — Add `id="plan-yaml"` to textarea, `for="plan-yaml"` to label, `aria-describedby="plan-yaml-help"` to textarea, and insert `<p id="plan-yaml-help">` with keyboard instructions below textarea. VERIFY: `cd frontend && npx vitest run src/pages/__tests__/TestPlanEditorPage-labels.spec.js` (cat:vue; multifile:no) [feat:test-automation-agent-20261116-test-plan-editor-label-the-yaml-box-name]
- [ ] [T1] frontend/src/pages/__tests__/TestPlanEditorPage-labels.spec.js — Add tests verifying label `for` matches textarea id and `aria-describedby` points to existing element containing "Ctrl+Enter". VERIFY: `cd frontend && npx vitest run src/pages/__tests__/TestPlanEditorPage-labels.spec.js` (cat:test; multifile:no) [feat:test-automation-agent-20261116-test-plan-editor-label-the-yaml-box-name]
- [ ] [T3] frontend/src/pages/TestPlanEditorPage.vue — Add `scope="col"` to the four `<th>` cells in the results table and insert `<caption class="sr-only">Tests found in the validated plan</caption>` as first child of the table. VERIFY: `cd frontend && npx vitest run src/pages/__tests__/TestPlanEditorPage-labels.spec.js` (cat:vue; multifile:no) [feat:test-automation-agent-20261116-test-plan-editor-label-the-yaml-box-name]
- [ ] [T1] frontend/src/pages/__tests__/TestPlanEditorPage-labels.spec.js — Add tests verifying all four table headers have `scope="col"` and the caption exists after validation. VERIFY: `cd frontend && npx vitest run src/pages/__tests__/TestPlanEditorPage-labels.spec.js` (cat:test; multifile:no) [feat:test-automation-agent-20261116-test-plan-editor-label-the-yaml-box-name]
- [ ] [T3] frontend/src/pages/TestPlanEditorPage.vue — Add `@keydown.ctrl.enter.prevent="validate"` and `@keydown.meta.enter.prevent="validate"` to the YAML textarea. VERIFY: `cd frontend && npx vitest run src/pages/__tests__/TestPlanEditorPage-labels.spec.js` (cat:vue; multifile:no) [feat:test-automation-agent-20261116-test-plan-editor-label-the-yaml-box-name]
- [ ] [T1] frontend/src/pages/__tests__/TestPlanEditorPage-labels.spec.js — Add tests verifying `axios.post` is called once for Ctrl+Enter and Meta+Enter, and not called for plain Enter. VERIFY: `cd frontend && npx vitest run src/pages/__tests__/TestPlanEditorPage-labels.spec.js` (cat:test; multifile:no) [feat:test-automation-agent-20261116-test-plan-editor-label-the-yaml-box-name]
- [ ] [T3] frontend/src/pages/TestPlanEditorPage.vue — Import `countLines` from `frontend/src/utils/textStats.js` and add `<p class="text-xs text-gray-500" data-testid="plan-line-count">{{ countLines(yaml) }} lines</p>` below the help text. VERIFY: `cd frontend && npx vitest run src/pages/__tests__/TestPlanEditorPage-labels.spec.js` (cat:vue; multifile:no) [feat:test-automation-agent-20261116-test-plan-editor-label-the-yaml-box-name]
- [ ] [T1] frontend/src/utils/__tests__/textStats.test.js — Add tests for `countLines` covering empty, single line, multiple lines, trailing newline, CRLF, and non-string inputs. VERIFY: `cd frontend && npx vitest run src/utils/__tests__/textStats.test.js` (cat:test; multifile:no) [feat:test-automation-agent-20261116-test-plan-editor-label-the-yaml-box-name]
- [ ] [T1] frontend/src/pages/__tests__/TestPlanEditorPage-labels.spec.js — Add test verifying the line count element updates correctly when textarea value changes. VERIFY: `cd frontend && npx vitest run src/pages/__tests__/TestPlanEditorPage-labels.spec.js` (cat:test; multifile:no) [feat:test-automation-agent-20261116-test-plan-editor-label-the-yaml-box-name]

# --- 27B-decomposed from roadmap [2026-11-16]: Test runs list: sort order, a count line and the flaky status — `frontend/src/pages/TestRu (review + tweak) [feat:test-automation-agent-20261116-test-runs-list-sort-order-a-count-line-a] ---
- [ ] [T1] frontend/src/utils/runList.js — Add `sortRuns(runs, mode)` function handling array validation, date parsing with fallback to 0, numeric failed fallback to 0, and sorting logic for newest/oldest/failures/name modes with correct tie-breakers. VERIFY: `cd frontend && npx vitest run src/utils/__tests__/runList.test.js`. (cat:typescript; multifile:no) [feat:test-automation-agent-20261116-test-runs-list-sort-order-a-count-line-a]
- [ ] [T1] frontend/src/utils/runList.js — Add `RUN_SORT_OPTIONS` constant exporting the array of sort option objects with values and labels for newest, oldest, failures, and name. VERIFY: `cd frontend && npx vitest run src/utils/__tests__/runList.test.js`. (cat:typescript; multifile:no) [feat:test-automation-agent-20261116-test-runs-list-sort-order-a-count-line-a]
- [ ] [T2] frontend/src/utils/__tests__/runList.test.js — Add unit tests covering each sort mode, tie-breakers for failures and name, unparseable dates, non-array input returning empty array, and ensuring input array is not mutated. VERIFY: `cd frontend && npx vitest run src/utils/__tests__/runList.test.js`. (cat:test; multifile:no) [feat:test-automation-agent-20261116-test-runs-list-sort-order-a-count-line-a]
- [ ] [T3] frontend/src/pages/TestRunsPage.vue — Import `sortRuns` and `RUN_SORT_OPTIONS`, add `sortMode` ref, insert `<select v-model="sortMode" aria-label="Sort runs">` after status select and before Refresh button, and update `filteredRuns` to apply `sortRuns` to the status-filtered list. VERIFY: `cd frontend && npx vitest run src/pages/__tests__/TestRunsPage-sort.spec.js`. (cat:vue; multifile:no) [feat:test-automation-agent-20261116-test-runs-list-sort-order-a-count-line-a]
- [ ] [T2] frontend/src/pages/__tests__/TestRunsPage-sort.spec.js — Add component tests verifying default newest-first order, failures sort placing most-failed run first, and ensuring status select remains the first select element. VERIFY: `cd frontend && npx vitest run src/pages/__tests__/TestRunsPage-sort.spec.js`. (cat:test; multifile:no) [feat:test-automation-agent-20261116-test-runs-list-sort-order-a-count-line-a]
- [ ] [T3] frontend/src/pages/TestRunsPage.vue — Add `<p class="text-sm text-gray-600" aria-live="polite">` displaying run count with singular/plural handling above the table in the non-loading block. VERIFY: `cd frontend && npx vitest run src/pages/__tests__/TestRunsPage-sort.spec.js`. (cat:vue; multifile:no) [feat:test-automation-agent-20261116-test-runs-list-sort-order-a-count-line-a]
- [ ] [T3] frontend/src/pages/TestRunsPage.vue — Add `<option value="flaky">Flaky</option>` after the Completed option in the status select and add `'flaky': 'bg-amber-100 text-amber-800'` to the `getStatusBadge` badges map. VERIFY: `cd frontend && npx vitest run src/pages/__tests__/TestRunsPage-sort.spec.js`. (cat:vue; multifile:no) [feat:test-automation-agent-20261116-test-runs-list-sort-order-a-count-line-a]
- [ ] [T2] frontend/src/pages/__tests__/TestRunsPage-sort.spec.js — Add tests verifying count text for 3 runs and 1 run, that filtering by flaky shows only flaky runs, and that the flaky badge element has class `bg-amber-100`. VERIFY: `cd frontend && npx vitest run src/pages/__tests__/TestRunsPage-sort.spec.js`. (cat:test; multifile:no) [feat:test-automation-agent-20261116-test-runs-list-sort-order-a-count-line-a]

# --- 27B-decomposed from roadmap [2026-11-16]: Run detail timeline: filter by status and search by test name — `frontend/src/pages/TestRu (review + tweak) [feat:test-automation-agent-20261116-run-detail-timeline-filter-by-status-and] ---
- [ ] [T1] frontend/src/utils/timelineFilter.js — Add `filterTimeline(steps, { status = '', query = '' } = {})` handling non-array input, status equality, case-insensitive test_name search, and combined filters without mutation. VERIFY: `cd frontend && npx vitest run src/utils/__tests__/timelineFilter.test.js`. (cat:typescript; multifile:no) [feat:test-automation-agent-20261116-run-detail-timeline-filter-by-status-and]
- [ ] [T1] frontend/src/utils/timelineFilter.js — Add `timelineStatusCounts(steps)` returning `{ all, passed, failed, skipped, other }` counts for the provided steps array. VERIFY: `cd frontend && npx vitest run src/utils/__tests__/timelineFilter.test.js`. (cat:typescript; multifile:no) [feat:test-automation-agent-20261116-run-detail-timeline-filter-by-status-and]
- [ ] [T2] frontend/src/pages/__tests__/TestRunDetailPage-timeline-filter.spec.js — Create component test mocking store/router, verifying status filter narrows list and search query filters by name. VERIFY: `cd frontend && npx vitest run src/pages/__tests__/TestRunDetailPage-timeline-filter.spec.js`. (cat:test; multifile:no) [feat:test-automation-agent-20261116-run-detail-timeline-filter-by-status-and]
- [ ] [T3] frontend/src/pages/TestRunDetailPage.vue — Add status `<select>` and search `<input>` controls inside the Test Timeline card, visible only when timeline is non-empty. VERIFY: `cd frontend && npx vitest run src/pages/__tests__/TestRunDetailPage-timeline-filter.spec.js`. (cat:vue; multifile:no) [feat:test-automation-agent-20261116-run-detail-timeline-filter-by-status-and]
- [ ] [T3] frontend/src/pages/TestRunDetailPage.vue — Add "No steps match the filter" message when filtered list is empty but source has data, and live count text `{{ filteredTimeline.length }} of {{ store.report.timeline.length }} steps`. VERIFY: `cd frontend && npx vitest run src/pages/__tests__/TestRunDetailPage-timeline-filter.spec.js`. (cat:vue; multifile:no) [feat:test-automation-agent-20261116-run-detail-timeline-filter-by-status-and]
- [ ] [T3] frontend/src/pages/TestRunDetailPage.vue — Import `filterTimeline` and `timelineStatusCounts`, add `stepStatus`, `stepQuery`, `filteredTimeline`, and `stepCounts` refs/computed properties. VERIFY: `cd frontend && npx vitest run src/pages/__tests__/TestRunDetailPage-timeline-filter.spec.js`. (cat:vue; multifile:no) [feat:test-automation-agent-20261116-run-detail-timeline-filter-by-status-and]
- [ ] [T2] frontend/src/utils/__tests__/timelineFilter.test.js — Write unit tests covering `filterTimeline` alone/combined, blank queries, missing test_name, non-array input, and `timelineStatusCounts` including 'other' status. VERIFY: `cd frontend && npx vitest run src/utils/__tests__/timelineFilter.test.js`. (cat:test; multifile:no) [feat:test-automation-agent-20261116-run-detail-timeline-filter-by-status-and]
- [ ] [T3] frontend/src/pages/TestRunDetailPage.vue — Replace the raw timeline `v-for` with `filteredTimeline` to render only matching steps. VERIFY: `cd frontend && npx vitest run src/pages/__tests__/TestRunDetailPage-timeline-filter.spec.js`. (cat:vue; multifile:no) [feat:test-automation-agent-20261116-run-detail-timeline-filter-by-status-and]
- [ ] [T2] frontend/src/pages/__tests__/TestRunDetailPage-timeline-filter.spec.js — Add assertions for the "No steps match" message visibility and dynamic count text updates. VERIFY: `cd frontend && npx vitest run src/pages/__tests__/TestRunDetailPage-timeline-filter.spec.js`. (cat:test; multifile:no) [feat:test-automation-agent-20261116-run-detail-timeline-filter-by-status-and]

# --- 27B-decomposed from roadmap [2026-11-16]: Run detail: copy a failure summary — after a failed run a user has to copy test names and  (review + tweak) [feat:test-automation-agent-20261116-run-detail-copy-a-failure-summary-after-] ---
- [ ] [T1] frontend/src/utils/failureSummary.js — Add `failureSummary(run, steps, { maxLines = 20, maxError = 120 } = {})` handling empty/non-array steps, no-failed-steps case, header formatting with plan name fallback, failed step lines with error truncation, and overflow count. VERIFY: `cd frontend && npx vitest run src/utils/__tests__/failureSummary.test.js`. (cat:typescript; multifile:no) [feat:test-automation-agent-20261116-run-detail-copy-a-failure-summary-after-]
- [ ] [T2] frontend/src/utils/__tests__/failureSummary.test.js — Add tests covering no-failure text, header format, multi-line error first-line extraction, truncation with ellipsis, maxLines overflow message, and missing plan name fallback. VERIFY: `cd frontend && npx vitest run src/utils/__tests__/failureSummary.test.js`. (cat:test; multifile:no) [feat:test-automation-agent-20261116-run-detail-copy-a-failure-summary-after-]
- [ ] [T3] frontend/src/pages/TestRunDetailPage.vue — Add `hasFailedSteps` computed, `copyMessage` ref, and `copySummary` async function that uses `navigator.clipboard.writeText` with try/catch to set status message. VERIFY: `cd frontend && npx vitest run src/pages/__tests__/TestRunDetailPage-copy-summary.spec.js`. (cat:vue; multifile:no) [feat:test-automation-agent-20261116-run-detail-copy-a-failure-summary-after-]
- [ ] [T4] frontend/src/pages/TestRunDetailPage.vue — Add "Copy failure summary" button with `v-if="hasFailedSteps"` and `@click="copySummary"` in Test Timeline card header, plus `<span role="status" aria-live="polite">` for copy message. VERIFY: `cd frontend && npx vitest run src/pages/__tests__/TestRunDetailPage-copy-summary.spec.js`. (cat:vue; multifile:no) [feat:test-automation-agent-20261116-run-detail-copy-a-failure-summary-after-]
- [ ] [T5] frontend/src/pages/__tests__/TestRunDetailPage-copy-summary.spec.js — Add tests verifying button visibility with failed steps, clipboard write called with correct summary string, copy failure message display on rejection, and button absence when no failed steps. VERIFY: `cd frontend && npx vitest run src/pages/__tests__/TestRunDetailPage-copy-summary.spec.js src/pages/__tests__/TestRunDetailPage.spec.js`. (cat:test; multifile:no) [feat:test-automation-agent-20261116-run-detail-copy-a-failure-summary-after-]

# --- 27B-decomposed from roadmap [2026-11-16]: Usage page: tests remaining this month — `frontend/src/pages/UsagePage.vue` shows `used /  (review + tweak) [feat:test-automation-agent-20261116-usage-page-tests-remaining-this-month-fr] ---
- [ ] [T1] frontend/src/utils/testsRemaining.js — Add `testsRemaining(limits)` returning null for missing/invalid limits or non-finite max, else `Math.max(0, max - used)`, and `remainingText(n)` handling singular/plural. VERIFY: `cd frontend && npx vitest run src/utils/__tests__/testsRemaining.test.js`. (cat:typescript; multifile:no) [feat:test-automation-agent-20261116-usage-page-tests-remaining-this-month-fr]
- [ ] [T2] frontend/src/utils/__tests__/testsRemaining.test.js — Add tests for normal plan, over-limit (0), unlimited string, missing object, missing used count, and singular/plural text. VERIFY: `cd frontend && npx vitest run src/utils/__tests__/testsRemaining.test.js`. (cat:test; multifile:no) [feat:test-automation-agent-20261116-usage-page-tests-remaining-this-month-fr]
- [ ] [T3] frontend/src/pages/UsagePage.vue — Import `testsRemaining` and `remainingText`, add `remaining` computed, and insert `<p v-if="remaining !== null" class="text-sm text-gray-500">{{ remainingText(remaining) }}</p>` below the "Tests this month" row. VERIFY: `cd frontend && npx vitest run src/pages/__tests__/UsagePage.spec.js`. (cat:vue; multifile:no) [feat:test-automation-agent-20261116-usage-page-tests-remaining-this-month-fr]
- [ ] [T4] frontend/src/pages/__tests__/UsagePage-remaining.spec.js — Add tests verifying "750 tests remaining this month" for 1000/250, singular for 1000/999, and no text for unlimited. VERIFY: `cd frontend && npx vitest run src/pages/__tests__/UsagePage-remaining.spec.js`. (cat:test; multifile:no) [feat:test-automation-agent-20261116-usage-page-tests-remaining-this-month-fr]

# --- 27B-decomposed from roadmap [2026-11-16]: SDK result summary helpers — a CI script that fetches run results with `SpecPilotClient.ge (review + tweak) [feat:test-automation-agent-20261116-sdk-result-summary-helpers-a-ci-script-t] ---
- [ ] [T1] sdk/python/specpilot_sdk/summary.py — Add `summarize_results(results: list[dict]) -> dict` function that counts statuses (passed, failed/errored, other) and handles non-list input by returning zeros. VERIFY: `cd sdk/python && python3 -m pytest tests/test_summary_counts.py -q`. (cat:python; multifile:no) [feat:test-automation-agent-20261116-sdk-result-summary-helpers-a-ci-script-t]
- [ ] [T1] sdk/python/specpilot_sdk/summary.py — Add `slowest_tests(results: list[dict], n: int = 5) -> list[dict]` function that filters numeric durations, sorts by duration desc then name asc, and returns up to `n` entries or empty list if `n <= 0`. VERIFY: `cd sdk/python && python3 -m pytest tests/test_summary_slowest.py -q`. (cat:python; multifile:no) [feat:test-automation-agent-20261116-sdk-result-summary-helpers-a-ci-script-t]
- [ ] [T1] sdk/python/specpilot_sdk/summary.py — Add `format_summary(results: list[dict], slowest: int = 3) -> str` function that renders the status summary line and optional slowest tests lines with integer formatting for whole-number durations. VERIFY: `cd sdk/python && python3 -m pytest tests/test_summary_format.py -q`. (cat:python; multifile:no) [feat:test-automation-agent-20261116-sdk-result-summary-helpers-a-ci-script-t]
- [ ] [T3] sdk/python/specpilot_sdk/__init__.py — Import `summarize_results`, `slowest_tests`, and `format_summary` from `specpilot_sdk.summary` and add them to `__all__` while preserving existing exports. VERIFY: `cd sdk/python && python3 -m pytest tests/test_summary_exports.py -q`. (cat:python; multifile:no) [feat:test-automation-agent-20261116-sdk-result-summary-helpers-a-ci-script-t]
- [ ] [T2] sdk/python/tests/test_summary_counts.py — Add test file with `test_counts_each_status`, `test_errored_counts_as_failed`, `test_unknown_and_missing_status_are_other`, and `test_non_list_gives_zeros` verifying the logic of `summarize_results`. VERIFY: `cd sdk/python && python3 -m pytest tests/test_summary_counts.py -q`. (cat:test; multifile:no) [feat:test-automation-agent-20261116-sdk-result-summary-helpers-a-ci-script-t]
- [ ] [T2] sdk/python/tests/test_summary_slowest.py — Add test file covering ordering, tie-breaking by name, cap enforcement, skipping non-numeric/missing durations, and `n=0` behavior for `slowest_tests`. VERIFY: `cd sdk/python && python3 -m pytest tests/test_summary_slowest.py -q`. (cat:test; multifile:no) [feat:test-automation-agent-20261116-sdk-result-summary-helpers-a-ci-script-t]
- [ ] [T2] sdk/python/tests/test_summary_format.py — Add test file verifying the first line format, slowest lines content, whole-number duration printing without decimals, and empty list output. VERIFY: `cd sdk/python && python3 -m pytest tests/test_summary_format.py -q`. (cat:test; multifile:no) [feat:test-automation-agent-20261116-sdk-result-summary-helpers-a-ci-script-t]
- [ ] [T2] sdk/python/tests/test_summary_exports.py — Add test file verifying that `from specpilot_sdk import summarize_results, slowest_tests, format_summary` works and that all pre-existing exports remain accessible. VERIFY: `cd sdk/python && python3 -m pytest tests/test_summary_exports.py -q`. (cat:test; multifile:no) [feat:test-automation-agent-20261116-sdk-result-summary-helpers-a-ci-script-t]
