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
- [ ] [T2] frontend — Run the full frontend test suite once to confirm removing pct.js caused zero regressions anywhere. VERIFY: `cd frontend && npm test`. (cat:test; multifile:no) [feat:test-automation-agent-20260922-resolve-duplicate-pct-js-ts]

# --- Claude-decomposed refuel round 3 [2026-09-22]: Delete dead duplicate getStatusColor() in frontend/src/utils/status.ts [feat:test-automation-agent-20260922-delete-dead-status-ts] ---
- [ ] [T1] frontend/src/utils/status.ts — Confirm zero callers outside its own test before deleting. VERIFY: `! grep -rn "from ['\"].*utils/status['\"]" frontend/src --include='*.vue' --include='*.js' --include='*.ts' | grep -v "utils/status.test"`. (cat:web; multifile:no) [feat:test-automation-agent-20260922-delete-dead-status-ts]
- [ ] [T1] frontend/src/utils/status.ts — Delete this dead duplicate file. VERIFY: `test ! -f frontend/src/utils/status.ts`. (cat:web; multifile:no) [feat:test-automation-agent-20260922-delete-dead-status-ts]
- [ ] [T1] frontend/src/utils/status.test.ts — Delete its now-orphaned dedicated test file. VERIFY: `test ! -f frontend/src/utils/status.test.ts`. (cat:test; multifile:no) [feat:test-automation-agent-20260922-delete-dead-status-ts]
- [ ] [T2] frontend — Run the full frontend test suite once to confirm zero regressions from the deletion. VERIFY: `cd frontend && npm test`. (cat:test; multifile:no) [feat:test-automation-agent-20260922-delete-dead-status-ts]

# --- Claude-decomposed refuel round 3 [2026-09-22]: Extract triplicated formatDate() into a shared, tested util [feat:test-automation-agent-20260922-extract-shared-formatdate-util] ---
- [ ] [T1] frontend/src/utils/formatDate.ts — Create this new file exporting `formatDate(dateString)`, ported verbatim from the identical inline implementation in TestRunsPage.vue/DashboardPage.vue/TestRunDetailPage.vue (null/invalid-date guard returning '-', `toLocaleDateString('en-US', {month:'short', day:'numeric', year:'numeric', hour:'2-digit', minute:'2-digit'})`). VERIFY: `grep -q "export function formatDate" frontend/src/utils/formatDate.ts`. (cat:web; multifile:no) [feat:test-automation-agent-20260922-extract-shared-formatdate-util]
- [ ] [T1] frontend/src/utils/__tests__/formatDate.test.ts — Create this new test file covering a valid ISO date string, a null/undefined input returning '-', and an invalid/unparseable string returning '-'. VERIFY: `cd frontend && npx vitest run src/utils/__tests__/formatDate.test.ts`. (cat:test; multifile:no) [feat:test-automation-agent-20260922-extract-shared-formatdate-util]
- [ ] [T2] frontend/src/pages/TestRunsPage.vue — Replace the inline `formatDate()` function with `import { formatDate } from '../utils/formatDate'`. VERIFY: `grep -q "from '../utils/formatDate'" frontend/src/pages/TestRunsPage.vue`. (cat:web; multifile:no) [feat:test-automation-agent-20260922-extract-shared-formatdate-util]
- [ ] [T2] frontend/src/pages/DashboardPage.vue — Replace the inline `formatDate()` function with `import { formatDate } from '../utils/formatDate'`. VERIFY: `grep -q "from '../utils/formatDate'" frontend/src/pages/DashboardPage.vue`. (cat:web; multifile:no) [feat:test-automation-agent-20260922-extract-shared-formatdate-util]
- [ ] [T2] frontend/src/pages/TestRunDetailPage.vue — Replace the inline `formatDate()` function with `import { formatDate } from '../utils/formatDate'`. VERIFY: `grep -q "from '../utils/formatDate'" frontend/src/pages/TestRunDetailPage.vue`. (cat:web; multifile:no) [feat:test-automation-agent-20260922-extract-shared-formatdate-util]
- [ ] [T2] frontend — Run the full frontend test suite once to confirm all three pages still render dates correctly after the consolidation. VERIFY: `cd frontend && npm test`. (cat:test; multifile:no) [feat:test-automation-agent-20260922-extract-shared-formatdate-util]

# --- Claude-decomposed refuel round 3 [2026-09-22]: Add unit tests for the orgs Pinia store [feat:test-automation-agent-20260922-orgs-store-unit-tests] ---
- [ ] [T1] frontend/src/stores/__tests__/orgs.test.js — Create this new test file with mocked axios + Pinia setup (following flakes.test.js's pattern) and a first test that `fetchOrgs()` populates `orgs` from a mocked GET response. VERIFY: `cd frontend && npx vitest run src/stores/__tests__/orgs.test.js`. (cat:test; multifile:no) [feat:test-automation-agent-20260922-orgs-store-unit-tests]
- [ ] [T2] frontend/src/stores/__tests__/orgs.test.js — Add a test that a failed `fetchOrgs()` sets `error` from `err.response.data.detail` and leaves `orgs` empty. VERIFY: `cd frontend && npx vitest run src/stores/__tests__/orgs.test.js`. (cat:test; multifile:no) [feat:test-automation-agent-20260922-orgs-store-unit-tests]
- [ ] [T2] frontend/src/stores/__tests__/orgs.test.js — Add a test that `createOrg(name)` pushes the API response into `orgs` and returns it. VERIFY: `cd frontend && npx vitest run src/stores/__tests__/orgs.test.js`. (cat:test; multifile:no) [feat:test-automation-agent-20260922-orgs-store-unit-tests]
- [ ] [T2] frontend/src/stores/__tests__/orgs.test.js — Add tests that `fetchMembers(orgId)` populates `members` and `fetchInvites(orgId)` populates `invites` from their mocked GET responses. VERIFY: `cd frontend && npx vitest run src/stores/__tests__/orgs.test.js`. (cat:test; multifile:no) [feat:test-automation-agent-20260922-orgs-store-unit-tests]
- [ ] [T3] frontend/src/stores/__tests__/orgs.test.js — Add a test that `updateMemberRole(orgId, userId, role)` replaces the matching entry in `members` in place using the PATCH response. VERIFY: `cd frontend && npx vitest run src/stores/__tests__/orgs.test.js`. (cat:test; multifile:no) [feat:test-automation-agent-20260922-orgs-store-unit-tests]
- [ ] [T3] frontend/src/stores/__tests__/orgs.test.js — Add a test that `removeMember(orgId, userId)` filters the matching member out of `members` after a successful DELETE, and a test that `createInvite(orgId, email, role)` pushes the new invite into `invites`. VERIFY: `cd frontend && npx vitest run src/stores/__tests__/orgs.test.js`. (cat:test; multifile:no) [feat:test-automation-agent-20260922-orgs-store-unit-tests]

# --- Claude-decomposed refuel round 3 [2026-09-22]: Add unit tests for the apiKeys Pinia store [feat:test-automation-agent-20260922-apikeys-store-unit-tests] ---
- [ ] [T1] frontend/src/stores/__tests__/apiKeys.test.js — Create this new test file with mocked axios + Pinia setup and a first test that `fetchKeys()` populates `keys` from a mocked GET response. VERIFY: `cd frontend && npx vitest run src/stores/__tests__/apiKeys.test.js`. (cat:test; multifile:no) [feat:test-automation-agent-20260922-apikeys-store-unit-tests]
- [ ] [T2] frontend/src/stores/__tests__/apiKeys.test.js — Add a test that a failed `fetchKeys()` sets `error` and leaves `keys` empty. VERIFY: `cd frontend && npx vitest run src/stores/__tests__/apiKeys.test.js`. (cat:test; multifile:no) [feat:test-automation-agent-20260922-apikeys-store-unit-tests]
- [ ] [T2] frontend/src/stores/__tests__/apiKeys.test.js — Add a test that `createKey(name, scopes)` pushes a record into `keys` that does NOT include the plaintext `api_key` field, while the function's return value still includes it. VERIFY: `cd frontend && npx vitest run src/stores/__tests__/apiKeys.test.js`. (cat:test; multifile:no) [feat:test-automation-agent-20260922-apikeys-store-unit-tests]
- [ ] [T2] frontend/src/stores/__tests__/apiKeys.test.js — Add a test that a failed `createKey()` sets `error` and re-throws. VERIFY: `cd frontend && npx vitest run src/stores/__tests__/apiKeys.test.js`. (cat:test; multifile:no) [feat:test-automation-agent-20260922-apikeys-store-unit-tests]
- [ ] [T2] frontend/src/stores/__tests__/apiKeys.test.js — Add a test that `revokeKey(id)` filters the matching key out of `keys` after a successful DELETE. VERIFY: `cd frontend && npx vitest run src/stores/__tests__/apiKeys.test.js`. (cat:test; multifile:no) [feat:test-automation-agent-20260922-apikeys-store-unit-tests]

# --- Claude-decomposed refuel round 3 [2026-09-22]: Add unit tests for the billing Pinia store [feat:test-automation-agent-20260922-billing-store-unit-tests] ---
- [ ] [T1] frontend/src/stores/__tests__/billing.test.js — Create this new test file with mocked axios + Pinia setup and a first test that `fetchSubscription()` populates `subscription` from a mocked GET response. VERIFY: `cd frontend && npx vitest run src/stores/__tests__/billing.test.js`. (cat:test; multifile:no) [feat:test-automation-agent-20260922-billing-store-unit-tests]
- [ ] [T2] frontend/src/stores/__tests__/billing.test.js — Add a test that a failed `fetchSubscription()` sets `error` and leaves `subscription` null. VERIFY: `cd frontend && npx vitest run src/stores/__tests__/billing.test.js`. (cat:test; multifile:no) [feat:test-automation-agent-20260922-billing-store-unit-tests]
- [ ] [T2] frontend/src/stores/__tests__/billing.test.js — Add a test that `fetchUsage()` populates `usage` on success and never toggles `loading` (asserting it stays false throughout the call). VERIFY: `cd frontend && npx vitest run src/stores/__tests__/billing.test.js`. (cat:test; multifile:no) [feat:test-automation-agent-20260922-billing-store-unit-tests]
- [ ] [T2] frontend/src/stores/__tests__/billing.test.js — Add a test that `startCheckout(tier)` returns `response.data.checkout_url` on success. VERIFY: `cd frontend && npx vitest run src/stores/__tests__/billing.test.js`. (cat:test; multifile:no) [feat:test-automation-agent-20260922-billing-store-unit-tests]
- [ ] [T2] frontend/src/stores/__tests__/billing.test.js — Add a test that a failed `startCheckout(tier)` sets `error` and re-throws. VERIFY: `cd frontend && npx vitest run src/stores/__tests__/billing.test.js`. (cat:test; multifile:no) [feat:test-automation-agent-20260922-billing-store-unit-tests]

# --- Claude-decomposed refuel round 3 [2026-09-22]: Add unit tests for the selfHealing Pinia store [feat:test-automation-agent-20260922-selfhealing-store-unit-tests] ---
- [ ] [T1] frontend/src/stores/__tests__/selfHealing.test.js — Create this new test file with mocked axios + Pinia setup and a first test that `fetchHistory()` populates `history` from a mocked GET response, passing the default `limit=50` param through. VERIFY: `cd frontend && npx vitest run src/stores/__tests__/selfHealing.test.js`. (cat:test; multifile:no) [feat:test-automation-agent-20260922-selfhealing-store-unit-tests]
- [ ] [T2] frontend/src/stores/__tests__/selfHealing.test.js — Add a test that `fetchHistory(10)` passes `{ params: { limit: 10 } }` through to axios.get. VERIFY: `cd frontend && npx vitest run src/stores/__tests__/selfHealing.test.js`. (cat:test; multifile:no) [feat:test-automation-agent-20260922-selfhealing-store-unit-tests]
- [ ] [T2] frontend/src/stores/__tests__/selfHealing.test.js — Add a test that a failed `fetchHistory()` sets `error` and leaves `history` at its initial value. VERIFY: `cd frontend && npx vitest run src/stores/__tests__/selfHealing.test.js`. (cat:test; multifile:no) [feat:test-automation-agent-20260922-selfhealing-store-unit-tests]
- [ ] [T2] frontend/src/stores/__tests__/selfHealing.test.js — Add a test that `fetchStats()` populates `stats` on success and a test that a failed `fetchStats()` sets `error`. VERIFY: `cd frontend && npx vitest run src/stores/__tests__/selfHealing.test.js`. (cat:test; multifile:no) [feat:test-automation-agent-20260922-selfhealing-store-unit-tests]

# --- Claude-decomposed refuel round 3 [2026-09-22]: Add unit tests for the usageMetrics Pinia store [feat:test-automation-agent-20260922-usagemetrics-store-unit-tests] ---
- [ ] [T1] frontend/src/stores/__tests__/usageMetrics.test.js — Create this new test file with mocked axios + Pinia setup and a first test that `fetchMetrics()` populates `metrics` from a mocked GET response, passing the default `period_days=30` param through. VERIFY: `cd frontend && npx vitest run src/stores/__tests__/usageMetrics.test.js`. (cat:test; multifile:no) [feat:test-automation-agent-20260922-usagemetrics-store-unit-tests]
- [ ] [T2] frontend/src/stores/__tests__/usageMetrics.test.js — Add a test that `fetchMetrics(7)` passes `{ params: { period_days: 7 } }` through to axios.get. VERIFY: `cd frontend && npx vitest run src/stores/__tests__/usageMetrics.test.js`. (cat:test; multifile:no) [feat:test-automation-agent-20260922-usagemetrics-store-unit-tests]
- [ ] [T2] frontend/src/stores/__tests__/usageMetrics.test.js — Add a test that a failed `fetchMetrics()` sets `error` and leaves `metrics` null. VERIFY: `cd frontend && npx vitest run src/stores/__tests__/usageMetrics.test.js`. (cat:test; multifile:no) [feat:test-automation-agent-20260922-usagemetrics-store-unit-tests]
- [ ] [T2] frontend/src/stores/__tests__/usageMetrics.test.js — Add a test that `fetchLimits()` populates `limits` on success and a test that a failed `fetchLimits()` sets `error`. VERIFY: `cd frontend && npx vitest run src/stores/__tests__/usageMetrics.test.js`. (cat:test; multifile:no) [feat:test-automation-agent-20260922-usagemetrics-store-unit-tests]

# --- Claude-decomposed refuel round 3 [2026-09-22]: Add unit tests for the useAsyncState composable [feat:test-automation-agent-20260922-useasyncstate-composable-tests] ---
- [ ] [T1] frontend/src/composables/__tests__/useAsyncState.test.js — Create this new test file with a first test that `execute()` sets `loading` true during the call and false after, and populates `data` with the resolved value on success. VERIFY: `cd frontend && npx vitest run src/composables/__tests__/useAsyncState.test.js`. (cat:test; multifile:no) [feat:test-automation-agent-20260922-useasyncstate-composable-tests]
- [ ] [T2] frontend/src/composables/__tests__/useAsyncState.test.js — Add a test that a rejected `asyncFn` sets `error` via the default `errorMessage` extractor (`error?.response?.data?.detail || error?.message`) and leaves `data` unchanged. VERIFY: `cd frontend && npx vitest run src/composables/__tests__/useAsyncState.test.js`. (cat:test; multifile:no) [feat:test-automation-agent-20260922-useasyncstate-composable-tests]
- [ ] [T2] frontend/src/composables/__tests__/useAsyncState.test.js — Add a test that a custom `options.errorMessage` function is used instead of the default when provided. VERIFY: `cd frontend && npx vitest run src/composables/__tests__/useAsyncState.test.js`. (cat:test; multifile:no) [feat:test-automation-agent-20260922-useasyncstate-composable-tests]
- [ ] [T2] frontend/src/composables/__tests__/useAsyncState.test.js — Add a test that `empty` is true only when not loading, not erroring, and `isEmpty(data.value)` is true (using the default array-length check and a custom `isEmpty` option). VERIFY: `cd frontend && npx vitest run src/composables/__tests__/useAsyncState.test.js`. (cat:test; multifile:no) [feat:test-automation-agent-20260922-useasyncstate-composable-tests]
- [ ] [T2] frontend/src/composables/__tests__/useAsyncState.test.js — Add a test that `statusRole`/`statusLive`/`statusMessage` are `null` when idle, `('status','polite','Loading…')` while loading, and `('alert','assertive', <error message>)` after an error. VERIFY: `cd frontend && npx vitest run src/composables/__tests__/useAsyncState.test.js`. (cat:test; multifile:no) [feat:test-automation-agent-20260922-useasyncstate-composable-tests]

# --- Claude-decomposed refuel round 3 [2026-09-22]: Remove dead calculate_trend_scores() from flake_trend.py [feat:test-automation-agent-20260922-remove-dead-calculate-trend-scores] ---
- [ ] [T1] backend/app/utils/flake_trend.py — Confirm `calculate_trend_scores` has zero callers outside its own test before deleting. VERIFY: `! grep -rn "calculate_trend_scores" backend/app --include='*.py' | grep -v 'flake_trend.py'`. (cat:backend; multifile:no) [feat:test-automation-agent-20260922-remove-dead-calculate-trend-scores]
- [ ] [T1] backend/app/utils/flake_trend.py — Delete the `calculate_trend_scores` function (keep `split_history`, `trend_direction`, and `calculate_trend`, which are genuinely wired). VERIFY: `! grep -q "def calculate_trend_scores" backend/app/utils/flake_trend.py`. (cat:backend; multifile:no) [feat:test-automation-agent-20260922-remove-dead-calculate-trend-scores]
- [ ] [T1] backend/tests/test_flake_trend.py — Delete the test cases exercising `calculate_trend_scores` (keep the tests for `split_history`/`trend_direction`/`calculate_trend`). VERIFY: `! grep -q "calculate_trend_scores" backend/tests/test_flake_trend.py`. (cat:test; multifile:no) [feat:test-automation-agent-20260922-remove-dead-calculate-trend-scores]
- [ ] [T2] backend/tests — Run flake_trend's own test file plus the flakes router tests to confirm zero regressions. VERIFY: `cd backend && python -m pytest tests/test_flake_trend.py tests/test_flakes_router.py -q`. (cat:test; multifile:no) [feat:test-automation-agent-20260922-remove-dead-calculate-trend-scores]

# --- Claude-decomposed refuel round 3 [2026-09-22]: Remove duplicate chunk()/chunk_list() (list_chunk.py vs chunking.py) [feat:test-automation-agent-20260922-remove-dead-chunking-py] ---
- [ ] [T1] backend/app/utils/chunking.py — Confirm zero callers before deleting. VERIFY: `! grep -rn "chunking\|chunk_list" backend/app --include='*.py' | grep -v 'utils/chunking.py'`. (cat:backend; multifile:no) [feat:test-automation-agent-20260922-remove-dead-chunking-py]
- [ ] [T1] backend/app/utils/chunking.py — Delete this dead duplicate file (no test file exists for it, so no companion test deletion needed). VERIFY: `test ! -f backend/app/utils/chunking.py`. (cat:backend; multifile:no) [feat:test-automation-agent-20260922-remove-dead-chunking-py]
- [ ] [T2] backend/tests — Run `test_utils_list_chunk.py` to confirm the surviving `list_chunk.py` implementation is unaffected. VERIFY: `cd backend && python -m pytest tests/test_utils_list_chunk.py -q`. (cat:test; multifile:no) [feat:test-automation-agent-20260922-remove-dead-chunking-py]

# --- Claude-decomposed refuel round 3 [2026-09-22]: Consolidate divergent parse_bool.py vs env_flag.py truthy() [feat:test-automation-agent-20260922-consolidate-parse-bool-env-flag] ---
- [ ] [T1] backend/app/utils/env_flag.py — Confirm zero callers before deleting. VERIFY: `! grep -rn "env_flag\|truthy(" backend/app --include='*.py' | grep -v 'utils/env_flag.py'`. (cat:backend; multifile:no) [feat:test-automation-agent-20260922-consolidate-parse-bool-env-flag]
- [ ] [T1] backend/app/utils/env_flag.py — Delete this dead, weaker-behaved duplicate file. VERIFY: `test ! -f backend/app/utils/env_flag.py`. (cat:backend; multifile:no) [feat:test-automation-agent-20260922-consolidate-parse-bool-env-flag]
- [ ] [T1] backend/tests/test_utils_env_flag.py — Delete its now-orphaned dedicated test file. VERIFY: `test ! -f backend/tests/test_utils_env_flag.py`. (cat:test; multifile:no) [feat:test-automation-agent-20260922-consolidate-parse-bool-env-flag]
- [ ] [T2] backend/tests — Run `test_parse_bool.py` to confirm the surviving fail-loud implementation is unaffected. VERIFY: `cd backend && python -m pytest tests/test_parse_bool.py -q`. (cat:test; multifile:no) [feat:test-automation-agent-20260922-consolidate-parse-bool-env-flag]

# --- Claude-decomposed refuel round 3 [2026-09-22]: Remove dead split_name.py [feat:test-automation-agent-20260922-remove-dead-split-name] ---
- [ ] [T1] backend/app/utils/split_name.py — Confirm zero callers before deleting. VERIFY: `! grep -rn "split_name" backend/app --include='*.py' | grep -v 'utils/split_name.py'`. (cat:backend; multifile:no) [feat:test-automation-agent-20260922-remove-dead-split-name]
- [ ] [T1] backend/app/utils/split_name.py — Delete this dead file. VERIFY: `test ! -f backend/app/utils/split_name.py`. (cat:backend; multifile:no) [feat:test-automation-agent-20260922-remove-dead-split-name]
- [ ] [T1] backend/tests/test_split_name.py — Delete its now-orphaned dedicated test file. VERIFY: `test ! -f backend/tests/test_split_name.py`. (cat:test; multifile:no) [feat:test-automation-agent-20260922-remove-dead-split-name]
- [ ] [T2] backend/tests — Run the full backend test suite once to confirm zero regressions from the deletion. VERIFY: `cd backend && python -m pytest -q`. (cat:test; multifile:no) [feat:test-automation-agent-20260922-remove-dead-split-name]

# --- Claude-decomposed refuel round 3 [2026-09-22]: Make the upload size limit configurable via parse_bytes/human_bytes [feat:test-automation-agent-20260922-configurable-upload-size-limit] ---
- [ ] [T1] backend/app/core/config.py — Add a `max_upload_size: str = "5MB"` setting field alongside the other Artifacts & Healing settings. VERIFY: `grep -q "max_upload_size" backend/app/core/config.py`. (cat:backend; multifile:no) [feat:test-automation-agent-20260922-configurable-upload-size-limit]
- [ ] [T2] backend/app/routers/uploads.py — Import `parse_bytes` from `app.utils.bytes_parse` and `human_bytes` from `app.utils.human_bytes`, and parse `settings.max_upload_size` into an integer byte count once at module load (or per-request, matching this file's existing settings-access style). VERIFY: `grep -q "parse_bytes" backend/app/routers/uploads.py`. (cat:backend; multifile:no) [feat:test-automation-agent-20260922-configurable-upload-size-limit]
- [ ] [T2] backend/app/routers/uploads.py — Replace the hardcoded `if len(contents) > 5_000_000:` check with the parsed setting, and build the 413 error detail message from `human_bytes()` of that same parsed value instead of the hand-typed `"max 5MB"` string. VERIFY: `! grep -q "5_000_000" backend/app/routers/uploads.py`. (cat:backend; multifile:no) [feat:test-automation-agent-20260922-configurable-upload-size-limit]
- [ ] [T2] backend/tests/test_uploads_router.py — Add a regression test that a file larger than the configured (mocked/overridden) `max_upload_size` is rejected with a 413 whose detail message matches `human_bytes()`'s formatting of the configured limit. VERIFY: `cd backend && python -m pytest tests/test_uploads_router.py -k too_large -q`. (cat:test; multifile:no) [feat:test-automation-agent-20260922-configurable-upload-size-limit]
- [ ] [T3] backend/tests — Run the full uploads test file to confirm the existing 5MB-boundary tests still pass unchanged with the new default config value. VERIFY: `cd backend && python -m pytest tests/test_uploads_router.py -q`. (cat:test; multifile:no) [feat:test-automation-agent-20260922-configurable-upload-size-limit]

# --- Claude-decomposed refuel round 3 [2026-09-22]: Delete the now-fully-dead sanitize() left behind in sanitize_filename.py [feat:test-automation-agent-20260922-delete-dead-sanitize-loser] ---
- [ ] [T1] backend/app/utils/sanitize_filename.py — Confirm `sanitize()` (not `sanitize_filename()`) has zero callers before deleting it. VERIFY: `! grep -rn "\bsanitize(" backend/app --include='*.py' | grep -v 'utils/sanitize_filename.py'`. (cat:backend; multifile:no) [feat:test-automation-agent-20260922-delete-dead-sanitize-loser]
- [ ] [T1] backend/app/utils/sanitize_filename.py — Delete the `sanitize()` function, keeping `sanitize_filename()` (the real, wired one used by uploads.py) intact. VERIFY: `! grep -q "^def sanitize(" backend/app/utils/sanitize_filename.py`. (cat:backend; multifile:no) [feat:test-automation-agent-20260922-delete-dead-sanitize-loser]
- [ ] [T2] backend/tests/test_sanitize_filename.py — Remove the test cases for the deleted `sanitize()` function, keeping the `sanitize_filename()` cases. VERIFY: `! grep -q "\bsanitize(" backend/tests/test_sanitize_filename.py`. (cat:test; multifile:no) [feat:test-automation-agent-20260922-delete-dead-sanitize-loser]
- [ ] [T2] backend/tests/test_utils_sanitize_filename.py — If this second, duplicate-named test file also covers `sanitize()`, remove those cases here too (keep `sanitize_filename()` cases). VERIFY: `! grep -q "\bsanitize(" backend/tests/test_utils_sanitize_filename.py`. (cat:test; multifile:no) [feat:test-automation-agent-20260922-delete-dead-sanitize-loser]
- [ ] [T2] backend/tests — Run the uploads router tests plus both sanitize-filename test files to confirm zero regressions. VERIFY: `cd backend && python -m pytest tests/test_sanitize_filename.py tests/test_utils_sanitize_filename.py tests/test_uploads_router.py -q`. (cat:test; multifile:no) [feat:test-automation-agent-20260922-delete-dead-sanitize-loser]

# --- Claude-decomposed refuel round 3 [2026-09-22]: Remove orphaned utils batch 1 (ordinal, parse_kv, count_words, pct_bar, smart_title) [feat:test-automation-agent-20260922-remove-orphaned-utils-batch-1] ---
- [ ] [T1] backend/app/utils/ordinal.py — Confirm zero callers, then delete this file and its test backend/tests/test_utils_ordinal.py. VERIFY: `test ! -f backend/app/utils/ordinal.py -a ! -f backend/tests/test_utils_ordinal.py`. (cat:backend; multifile:yes) [feat:test-automation-agent-20260922-remove-orphaned-utils-batch-1]
- [ ] [T1] backend/app/utils/parse_kv.py — Confirm zero callers, then delete this file and its test backend/tests/test_parse_kv.py. VERIFY: `test ! -f backend/app/utils/parse_kv.py -a ! -f backend/tests/test_parse_kv.py`. (cat:backend; multifile:yes) [feat:test-automation-agent-20260922-remove-orphaned-utils-batch-1]
- [ ] [T1] backend/app/utils/count_words.py — Confirm zero callers, then delete this file and its test backend/tests/test_count_words.py. VERIFY: `test ! -f backend/app/utils/count_words.py -a ! -f backend/tests/test_count_words.py`. (cat:backend; multifile:yes) [feat:test-automation-agent-20260922-remove-orphaned-utils-batch-1]
- [ ] [T1] backend/app/utils/pct_bar.py — Confirm zero callers, then delete this file and its test backend/tests/test_utils_pct_bar.py. VERIFY: `test ! -f backend/app/utils/pct_bar.py -a ! -f backend/tests/test_utils_pct_bar.py`. (cat:backend; multifile:yes) [feat:test-automation-agent-20260922-remove-orphaned-utils-batch-1]
- [ ] [T1] backend/app/utils/smart_title.py — Confirm zero callers, then delete this file and its test backend/tests/test_smart_title.py. VERIFY: `test ! -f backend/app/utils/smart_title.py -a ! -f backend/tests/test_smart_title.py`. (cat:backend; multifile:yes) [feat:test-automation-agent-20260922-remove-orphaned-utils-batch-1]
- [ ] [T2] backend/tests — Run the full backend test suite once to confirm zero regressions from all five deletions. VERIFY: `cd backend && python -m pytest -q`. (cat:test; multifile:no) [feat:test-automation-agent-20260922-remove-orphaned-utils-batch-1]

# --- Claude-decomposed refuel round 3 [2026-09-22]: Remove orphaned utils batch 2 (group_consecutive, moving_average, percent_change, stable_hash, duration_parse, time_ago) [feat:test-automation-agent-20260922-remove-orphaned-utils-batch-2] ---
- [ ] [T1] backend/app/utils/group_consecutive.py — Confirm zero callers, then delete this file and its test backend/tests/test_group_consecutive.py. VERIFY: `test ! -f backend/app/utils/group_consecutive.py -a ! -f backend/tests/test_group_consecutive.py`. (cat:backend; multifile:yes) [feat:test-automation-agent-20260922-remove-orphaned-utils-batch-2]
- [ ] [T1] backend/app/utils/moving_average.py — Confirm zero callers, then delete this file and its test backend/tests/test_utils_moving_average.py. VERIFY: `test ! -f backend/app/utils/moving_average.py -a ! -f backend/tests/test_utils_moving_average.py`. (cat:backend; multifile:yes) [feat:test-automation-agent-20260922-remove-orphaned-utils-batch-2]
- [ ] [T1] backend/app/utils/percent_change.py — Confirm zero callers, then delete this file and its test backend/tests/test_utils_percent_change.py. VERIFY: `test ! -f backend/app/utils/percent_change.py -a ! -f backend/tests/test_utils_percent_change.py`. (cat:backend; multifile:yes) [feat:test-automation-agent-20260922-remove-orphaned-utils-batch-2]
- [ ] [T1] backend/app/utils/stable_hash.py — Confirm zero callers, then delete this file and its test backend/tests/test_stable_hash.py. VERIFY: `test ! -f backend/app/utils/stable_hash.py -a ! -f backend/tests/test_stable_hash.py`. (cat:backend; multifile:yes) [feat:test-automation-agent-20260922-remove-orphaned-utils-batch-2]
- [ ] [T1] backend/app/utils/duration_parse.py — Confirm zero callers, then delete this file and its test backend/tests/test_utils_duration_parse.py. VERIFY: `test ! -f backend/app/utils/duration_parse.py -a ! -f backend/tests/test_utils_duration_parse.py`. (cat:backend; multifile:yes) [feat:test-automation-agent-20260922-remove-orphaned-utils-batch-2]
- [ ] [T1] backend/app/utils/time_ago.py — Confirm zero callers, then delete this file and its test backend/tests/test_utils_time_ago.py. VERIFY: `test ! -f backend/app/utils/time_ago.py -a ! -f backend/tests/test_utils_time_ago.py`. (cat:backend; multifile:yes) [feat:test-automation-agent-20260922-remove-orphaned-utils-batch-2]
- [ ] [T2] backend/tests — Run the full backend test suite once to confirm zero regressions from all six deletions. VERIFY: `cd backend && python -m pytest -q`. (cat:test; multifile:no) [feat:test-automation-agent-20260922-remove-orphaned-utils-batch-2]
