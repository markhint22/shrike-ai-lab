# billwatch — pre-decomposed release-polish backlog (27B-friendly)
# queue_refill.py pulls [T1-T5] items from here into OVERNIGHT_PROGRESS.md when doable is low.


# --- next-year roadmap decomposition (2026-09-05): router-404 fix + finished-backend wiring + Q5 ---

# --- refill 2026-09-06: bill-domain pure modules (self-verifying, T1-T2) ---

# --- COMPETITIVE 2026-09-06: BillWatch vs FastDemocracy — digests + real-time alerts + AI summaries (federal-only consumer wedge) ---
# Weekly digest (FastDemocracy free tier has it)
# Real-time alerts (FastDemocracy Professional; BillWatch wedge = free/simple)
# AI summaries — competitor has "AI meeting summaries"; BillWatch already has bill summaries, deepen them

# --- TS gate hardening (2026-09-07): make each web repo's per-cycle type-check explicit ---

# --- 27B-decomposed from roadmap [2026-09-07]: Weekly digest (grouped by stage/topic) + endpoint + view {cat: backend+web; size: M; multi (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-07]: Real-time alerts on tracked topics/bills (rules + match) {cat: backend+web; size: M; multi (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-08]: Plain-English "what changed" status summaries {cat: backend; size: S; multifile: no; resea (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-08]: Legislator profiles + scorecards surface polish {cat: web; size: M; multifile: yes; resear (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-09]: iOS/Android feature parity with web (tracking, digests, alerts) — researched 2026-09-09: b (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-09]: Campaign-finance / vote-record insights as a light premium tier — CORRECTED 2026-09-09: th (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-10]: Committee hearing & floor-activity calendar for tracked bills — Surface a "This Week in Co (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-10]: Shareable bill status cards — One-tap "share" on any tracked bill generates a branded imag (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-10]: Shareable bill status cards — One-tap "share" on any tracked bill generates a branded imag (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-10]: Plain-English bill "odds of passage" indicator — A lightweight, transparent heuristic (not (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-10]: "Bills like this" similarity finder — Surface companion/duplicate/related bills (e.g. Hous (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-11]: Add unit tests for advanced_auth router — app/routers/advanced_auth.py (29 lines, GET /log (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-11]: Add unit tests for recommendations router — app/routers/recommendations.py (4 GET endpoint (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-11]: Add unit tests for email_service.py — app/services/email_service.py (309 lines) has zero t (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-11]: Delete two unused stub services — app/services/github_integration_service.py and app/servi (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-11]: Add unit tests for apiError.ts — billwatch-web/src/utils/apiError.ts (getErrorMessage/getE (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-13]: Fix activity-logs audit-report fake-data endpoint — app/routers/activity_logs.py's GET /ap (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-13]: Add tests for the two untested api_docs endpoints — app/routers/api_docs.py has 3 GET endp (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-13]: Add tests for GET /api/topics/{slug} — app/routers/topics.py's list-endpoint caching is al (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-13]: Add unit tests for LegislatorStatisticsService — app/services/legislator_statistics_servic (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-13]: Add unit tests for NotificationService — app/services/notification_service.py (183 lines,  (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-14]: Fix crash in data_export.py's current_user["id"] access — app/routers/data_export.py's req (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-14]: Re-enable address capture at registration — app/routers/auth.py's register() (line ~141) h (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-14]: Add PATCH /api/auth/me/address and wire ProfileView.vue's saveAddress() to it — billwatch- (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-14]: Fix feedback router's dead background-task wiring — app/routers/feedback.py's submit_feedb (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-14]: Add router tests for priority_api.py — app/routers/priority_api.py (6 endpoints: set_bill_ (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-14]: Add router tests for bill_chat.py — app/routers/bill_chat.py's two endpoints (`post_bill_m (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-14]: Fix crash bug in POST/PATCH /api/alerts (duplicate broken alert system) — app/routers/aler (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-14]: Fix crash bugs in GET /api/votes/comparison and GET /api/votes/statistics/{bioguide_id} —  (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-14]: Delete unused dead-code service app/services/export.py (ExportService) — its export_bills_ (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-14]: Add router-level tests for app/routers/notifications.py — GET /api/notifications (paginati (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-14]: Add tests for GET/POST/DELETE /api/me/bills and /api/me/topics — app/routers/users.py's ge (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-14]: Add router-level tests for app/routers/ranking.py (mounted at /api/ranking, app/main.py:10 (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-14]: Add a router-level test for POST /api/articles/rank — app/routers/article_relevance.py's r (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-14]: Add a router-level test for POST /api/bills/{bill_id}/background — app/routers/bill_backgr (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-17]: Add router-level test coverage for app/routers/analytics.py — mounted at prefix /api/analy (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-17]: Add router tests for POST /api/legislators/sync and POST /api/legislators/sync-stats — app (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-17]: Vote/RollCallVote data has no production ingestion path — app/services/congress_api.py's g (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-17]: Delete orphaned dead-code service app/services/webhook_service.py — its WebhookService (re (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-18]: Add tests for billwatch-web Pinia stores auth.ts, bills.ts, and billChat.ts — billwatch-we (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-18]: Fix iOS SettingsView — Save Settings and Logout buttons are both non-functional stubs — bi (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-18]: Delete 3 more orphaned dead-code files with self-testing test suites — app/services/congre (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-18]: Add unit tests for SummaryScheduler (app/services/summary_scheduler.py, 194 lines) and rem (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-18]: Add unit tests for LegislatorSyncService._upsert_legislator's field-mapping logic (app/ser (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-18]: Add unit tests for app/utils/datetime_utils.py's utcnow() — this 12-line module's own docs (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-18]: Delete orphaned dead Vue component billwatch-web/src/components/BillDetailView.vue — this  (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-18]: Consolidate duplicate/stale billwatch-web/src/services/api.test.ts — two separate test fil (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-18]: Fix Android registration silently dropping the address field — billwatch-android/app/src/m (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-18]: Fix the two broken/never-run files in billwatch-ios/Tests/ and wire the directory into a r (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-18]: Add real unit tests for BillSummaryService (app/services/bill_summary_service.py, 136 line (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-18]: Add unit tests for TrendingService (app/services/trending_service.py, 172 lines) — this is (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-18]: Add unit tests for BillAnalyticsService (app/services/bill_analytics_service.py, 176 lines (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-18]: Add unit tests for Android BillsRepository + BillsViewModel — billwatch-android/app/src/ma (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-18]: Add unit tests for Android BillingRepository + BillingViewModel — billwatch-android/app/sr (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-18]: Add a unit test for billwatch-web/src/components/UnifiedBillCard.vue — this 70-line compon (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-19]: Add a unit test for billwatch-web/src/components/BillChatPanel.vue — this 276-line compone (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-19]: Expose the new dark_mode/language user-settings columns via the API — commit 6daacd2 ("fea (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-19]: Fix Bill Chat "send message" always failing with 401 for logged-in users — billwatch-web/s (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-19]: Fix double `/api/api/...` 404s breaking global search and legislator search — billwatch-we (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-19]: Fix the same double `/api/api/...` 404 bug breaking the admin dashboard — billwatch-web/sr (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-19]: Bill comments feature (BillCommentsSection.vue) has zero backend implementation — the comp (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-19]: Scheduled vote-sync job is a hardcoded no-op stub, never syncs real votes — app/jobs/sched (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-20]: Wire up production error monitoring/crash reporting across all 3 clients — `sentry-sdk[fas (review + tweak) [feat:billwatch-20260920-wire-up-production-error-monitoring-cras] ---

# --- 27B-decomposed from roadmap [2026-09-21]: The GDPR/CCPA "export my data" and "delete my account" endpoints are 100% fake — `app/serv (review + tweak) [feat:billwatch-20260921-the-gdpr-ccpa-export-my-data-and-delete-] ---

# --- 27B-decomposed from roadmap [2026-09-21]: The GDPR/CCPA "export my data" and "delete my account" endpoints are 100% fake — `app/serv (review + tweak) [feat:billwatch-20260921-the-gdpr-ccpa-export-my-data-and-delete-] ---

# --- 27B-decomposed from roadmap [2026-09-21]: Delete the entirely-orphaned billwatch-web/src/api/ directory (5 files, dead since it was  (review + tweak) [feat:billwatch-20260921-delete-the-entirely-orphaned-billwatch-w] ---

# --- 27B-decomposed from roadmap [2026-09-21]: Delete the entirely-orphaned billwatch-web/src/api/ directory (5 files, dead since it was  (review + tweak) [feat:billwatch-20260921-delete-the-entirely-orphaned-billwatch-w] ---

# --- 27B-decomposed from roadmap [2026-09-21]: Delete stale duplicate test file DeleteAccountButton.spec.js — billwatch-web/src/component (review + tweak) [feat:billwatch-20260921-delete-stale-duplicate-test-file-deletea] ---

# --- 27B-decomposed from roadmap [2026-09-21]: Add a unit test for LoginView.vue — billwatch-web/src/views/LoginView.vue (84 lines) has n (review + tweak) [feat:billwatch-20260921-add-a-unit-test-for-loginview-vue-billwa] ---

# --- 27B-decomposed from roadmap [2026-09-21]: Add a unit test for FollowingView.vue — billwatch-web/src/views/FollowingView.vue (75 line (review + tweak) [feat:billwatch-20260921-add-a-unit-test-for-followingview-vue-bi] ---

# --- 27B-decomposed from roadmap [2026-09-21]: Add a direct unit test for searchService.ts — billwatch-web/src/services/searchService.ts  (review + tweak) [feat:billwatch-20260921-add-a-direct-unit-test-for-searchservice] ---

# --- 27B-decomposed from roadmap [2026-09-22]: Add a direct unit test for legislatorService.ts — billwatch-web/src/services/legislatorSer (review + tweak) [feat:billwatch-20260922-add-a-direct-unit-test-for-legislatorser] ---

# --- 27B-decomposed from roadmap [2026-09-22]: Add a unit test for Icon.vue — billwatch-web/src/components/Icon.vue (28 lines) is a small (review + tweak) [feat:billwatch-20260922-add-a-unit-test-for-icon-vue-billwatch-w] ---

# --- 27B-decomposed from roadmap [2026-09-22]: Add a unit test for PremiumPaywall.vue — billwatch-web/src/components/PremiumPaywall.vue ( (review + tweak) [feat:billwatch-20260922-add-a-unit-test-for-premiumpaywall-vue-b] ---

# --- 27B-decomposed from roadmap [2026-09-22 refuel round 3]: Add router-level tests for app/routers/advanced_auth.py — GET /api/advanced/login-history has zero route-level coverage (only the underlying SecurityAuditService is tested) (review + tweak) [feat:billwatch-20260922-advanced-auth-router-login-history-tests] ---

# --- 27B-decomposed from roadmap [2026-09-22 refuel round 3]: Add router-level tests for app/routers/priority_api.py — all 6 endpoints have zero route-level coverage (only the underlying TrackedBillPriority service is tested) (review + tweak) [feat:billwatch-20260922-priority-api-router-tests] ---

# --- 27B-decomposed from roadmap [2026-09-22 refuel round 3]: Add router-level tests for app/routers/bill_chat.py — POST/GET /api/bills/{bill_id}/chat have ZERO test coverage of any kind (review + tweak) [feat:billwatch-20260922-bill-chat-router-tests] ---

# --- 27B-decomposed from roadmap [2026-09-22 refuel round 3]: Finish deleting the orphaned billwatch-web/src/api/ directory — client.ts + its test are the two files left over from a partially-landed 2026-09-21 cleanup (review + tweak) [feat:billwatch-20260922-finish-orphaned-api-dir-cleanup] ---

# --- 27B-decomposed from roadmap [2026-09-22 refuel round 3]: Add unit tests for Android SavedSearchesRepository + SavedSearchesViewModel — zero coverage today, same gap already fixed for Bills/Billing (review + tweak) [feat:billwatch-20260922-android-savedsearches-tests] ---

# --- 27B-decomposed from roadmap [2026-09-22 refuel round 3]: Add unit tests for Android LegislatorsRepository + LegislatorsViewModel — zero coverage today, same gap already fixed for Bills/Billing (review + tweak) [feat:billwatch-20260922-android-legislators-tests] ---

# --- Claude-decomposed from roadmap [2026-09-22 round 4]: Fix crash bug in GET /api/activity-logs/logs — current_user["id"] subscript on a User ORM object (review + tweak) [feat:billwatch-20260922-activity-logs-current-user-crash] ---

# --- Claude-decomposed from roadmap [2026-09-22 round 4]: Delete orphaned dead-code module app/core/rate_limiting.py — zero references anywhere, superseded by app/core/rate_limiter.py (review + tweak) [feat:billwatch-20260922-delete-rate-limiting-dead-module] ---

# --- Claude-decomposed from roadmap [2026-09-22 round 4]: Delete orphaned dead-code module app/services/caching.py (CacheService) plus its 3 orphan-only test files (review + tweak) [feat:billwatch-20260922-delete-caching-dead-module] ---

# --- Claude-decomposed from roadmap [2026-09-22 round 4]: Finish deleting app/services/export.py and app/services/webhook_service.py — dead code whose test files were already removed in a partial prior pass (review + tweak) [feat:billwatch-20260922-finish-export-webhook-dead-code] ---

# --- Claude-decomposed from roadmap [2026-09-22 round 4]: Delete orphaned dead-code Pinia store billwatch-web/src/stores/billChat.ts — never imported outside its own test file (review + tweak) [feat:billwatch-20260922-delete-billchat-store-dead-code] ---

# --- Claude-decomposed from roadmap [2026-09-22 round 4]: Delete orphaned dead component billwatch-web/src/components/BillSummaryCard.vue — never imported anywhere (review + tweak) [feat:billwatch-20260922-delete-billsummarycard-dead-code] ---

# --- Claude-decomposed from roadmap [2026-09-22 round 4]: Delete unreachable dead component billwatch-web/src/components/BillCommentsSection.vue — not imported by any view, and its backend doesn't exist either (review + tweak) [feat:billwatch-20260922-delete-billcommentssection-dead-code] ---

# --- Claude-decomposed from roadmap [2026-09-22 round 4]: Add unit tests for views/AlertsView.vue — real analyticsService-backed alert CRUD, zero coverage (review + tweak) [feat:billwatch-20260922-alertsview-tests] ---

# --- Claude-decomposed from roadmap [2026-09-22 round 4]: Add unit tests for views/RegisterView.vue — password-mismatch guard, terms gate, register+redirect flow, zero coverage (review + tweak) [feat:billwatch-20260922-registerview-tests] ---

# --- Claude-decomposed from roadmap [2026-09-22 round 4]: Expand stores/__tests__/auth.test.ts — only login() is tested; register/saveAddress/logout/checkAuth/fetchCurrentUser-failure are untested (review + tweak) [feat:billwatch-20260922-authstore-expand-coverage] ---

# --- Claude-decomposed from roadmap [2026-09-22 round 4]: Add direct unit tests for services/adminApi.ts and services/analyticsService.ts — only indirectly covered via other components' mocks (review + tweak) [feat:billwatch-20260922-adminapi-analyticsservice-direct-tests] ---

# --- Claude-decomposed from roadmap [2026-09-22 round 4]: Add unit tests for the 3 untested Priority-Dashboard components — BillActionItem, BillPriorityItem, PriorityLevelCard (review + tweak) [feat:billwatch-20260922-priority-components-tests] ---

# --- Claude-decomposed from roadmap [2026-09-22 round 4]: Add a unit test for components/BillRankingCard.vue — 4-way urgency-state computed classes + record-activity emit, zero coverage (review + tweak) [feat:billwatch-20260922-billrankingcard-tests] ---

# --- Claude-decomposed from roadmap [2026-09-22 round 4]: Add a functional (non-a11y) unit test for components/modals/ChangePriorityModal.vue — existing test only covers dialog semantics (review + tweak) [feat:billwatch-20260922-changeprioritymodal-functional-tests] ---

# --- Claude-decomposed from roadmap [2026-09-22 round 4]: Add unit tests for Android TopicsRepository + TopicsViewModel — zero coverage today, same gap already fixed for Bills/Billing (review + tweak) [feat:billwatch-20260922-android-topics-tests] ---
- [ ] [T2] billwatch-android/app/src/test/java/com/billwatch/ui/screens/TopicsViewModelTest.kt — Create this new test file following the same established mockk pattern, covering TopicsViewModel.kt's methods (mock TopicsRepository, use `coEvery`/`runTest`). VERIFY: `cd billwatch-android && ./gradlew testDebugUnitTest --tests "com.billwatch.ui.screens.TopicsViewModelTest"`. (cat:mobile; multifile:no) [feat:billwatch-20260922-android-topics-tests]

# --- Claude-decomposed from roadmap [2026-09-22 round 4]: Add unit tests for Android CivicRepository + FindRepsViewModel + HomeViewModel — zero coverage today (review + tweak) [feat:billwatch-20260922-android-civic-findreps-home-tests] ---
- [ ] [T2] billwatch-android/app/src/test/java/com/billwatch/data/repository/CivicRepositoryTest.kt — Create this new test file mirroring AuthRepositoryTest.kt's mockk/coEvery/runTest pattern, covering CivicRepository.kt's methods. VERIFY: `cd billwatch-android && ./gradlew testDebugUnitTest --tests "com.billwatch.data.repository.CivicRepositoryTest"`. (cat:mobile; multifile:no) [feat:billwatch-20260922-android-civic-findreps-home-tests]
- [ ] [T2] billwatch-android/app/src/test/java/com/billwatch/ui/screens/FindRepsViewModelTest.kt — Create this new test file following the same established mockk pattern, covering FindRepsViewModel.kt's methods (mock CivicRepository). VERIFY: `cd billwatch-android && ./gradlew testDebugUnitTest --tests "com.billwatch.ui.screens.FindRepsViewModelTest"`. (cat:mobile; multifile:no) [feat:billwatch-20260922-android-civic-findreps-home-tests]
- [ ] [T2] billwatch-android/app/src/test/java/com/billwatch/ui/screens/HomeViewModelTest.kt — Create this new test file following the same established mockk pattern, covering HomeViewModel.kt's methods. VERIFY: `cd billwatch-android && ./gradlew testDebugUnitTest --tests "com.billwatch.ui.screens.HomeViewModelTest"`. (cat:mobile; multifile:no) [feat:billwatch-20260922-android-civic-findreps-home-tests]

# --- Claude-decomposed from roadmap [2026-09-22 round 4]: Add unit tests for Android PreferencesRepository + NotificationPreferencesViewModel — zero coverage today (review + tweak) [feat:billwatch-20260922-android-preferences-tests] ---
- [ ] [T1] billwatch-android/app/src/test/java/com/billwatch/data/repository/PreferencesRepositoryTest.kt — Create this new test file mirroring AuthRepositoryTest.kt's mockk/coEvery/runTest pattern, covering PreferencesRepository.kt's methods. VERIFY: `cd billwatch-android && ./gradlew testDebugUnitTest --tests "com.billwatch.data.repository.PreferencesRepositoryTest"`. (cat:mobile; multifile:no) [feat:billwatch-20260922-android-preferences-tests]
- [ ] [T1] billwatch-android/app/src/test/java/com/billwatch/ui/screens/NotificationPreferencesViewModelTest.kt — Create this new test file following the same established mockk pattern, covering NotificationPreferencesViewModel.kt's methods. VERIFY: `cd billwatch-android && ./gradlew testDebugUnitTest --tests "com.billwatch.ui.screens.NotificationPreferencesViewModelTest"`. (cat:mobile; multifile:no) [feat:billwatch-20260922-android-preferences-tests]

# --- Claude research pass [2026-09-23]: civic router missing /api/civic prefix breaks Find-My-Representatives on all 3 clients (review + tweak) [feat:billwatch-20260923-civic-prefix-bug] ---
- [ ] [T1] billwatch-backend/app/main.py — `app.include_router(civic.router, tags=["Civic"])` (line 119) registers the civic router with NO prefix at all (the router itself is also defined as `APIRouter(tags=["civic"])` with no prefix), so the real live paths are bare `POST /representatives`, `GET /representatives`, `GET /representatives/federal`, and `GET /divisions` — confirmed empirically with TestClient: `GET /representatives?address=x` → 422 (route found), `GET /api/civic/representatives?address=x` → 404 (route missing). All 3 clients call the `/api/civic/...` path instead: billwatch-web/src/stores/civic.ts:25 (`api.get('/civic/representatives', ...)` against a baseURL that already includes `/api`), billwatch-ios/BillWatch/Services/APIService.swift:668,679 (`"\(baseURL)/civic/representatives"`), billwatch-android/app/src/main/java/com/billwatch/data/api/BillWatchApi.kt:201,207 (`@GET("civic/representatives")`). The "Find My Representatives" feature 404s end-to-end in production on web, iOS, and Android. Even the backend's own test docstring in `tests/test_civic_router_error_handling.py` incorrectly claims it's testing "POST /api/civic/representatives and GET /api/civic/divisions" while actually posting to bare `/representatives` and `/divisions`. Fix: add `prefix="/api/civic"` to the `include_router(civic.router, ...)` call in main.py, then update `tests/test_civic_router_error_handling.py`'s two `client.post("/representatives", ...)` / `client.get("/divisions", ...)` calls to the corrected `/api/civic/...` paths. VERIFY: `cd billwatch-backend && .venv/bin/python -m pytest tests/test_civic_router_error_handling.py -q && .venv/bin/python -c "from fastapi.testclient import TestClient; from app.main import app; c=TestClient(app); print(c.get('/api/civic/divisions?query=CA').status_code)"` — should print `422` (route resolved, just failing validation), not `404`. (cat:backend; multifile:yes) [feat:billwatch-20260923-civic-prefix-bug]

# --- Claude research pass [2026-09-23]: dead code + missing coverage batch (review + tweak) [feat:billwatch-20260923-coverage-and-cleanup] ---
- [ ] [T1] billwatch-backend/app/models/bill_comment.py — Orphaned AND broken model: not imported by `app/models/__init__.py` or any router/service (grep for `bill_comment|BillComment` across `app/` only matches this file itself), has no Alembic migration creating a `bill_comments` table, and its `bill: Mapped["Bill"] = relationship(back_populates="comments")` points at a `Bill.comments` attribute that does not exist on `app/models/bill.py` — if this module were ever imported, SQLAlchemy's mapper configuration would raise a `ConfigureMappersError`. This is the leftover backend half of the already-deleted `BillCommentsSection.vue` frontend component (deleted in an earlier pass; that pass noted the backend "doesn't exist," but this dead file remained). Delete it. VERIFY: `cd billwatch-backend && grep -rn "bill_comment\|BillComment" app/ | grep -v models/bill_comment.py` returns nothing, then `.venv/bin/python -m pytest -q` stays green (1384+ passed). (cat:backend; multifile:no) [feat:billwatch-20260923-coverage-and-cleanup]
- [ ] [T2] billwatch-backend/app/schemas/scorecard.py — Unused Pydantic schema module: 0% coverage in `pytest --cov`, and not imported anywhere (`grep -rn "schemas.scorecard\|schemas import scorecard" app/ tests/` returns nothing). The real scorecard logic and its tests live in `app/services/legislator_scorecard_service.py` / `tests/test_legislator_scorecard.py` / `tests/test_scorecard_grade.py` / `tests/test_scorecard_ideology_label.py` — none of them touch this schema file. Delete it. VERIFY: `cd billwatch-backend && grep -rn "schemas.scorecard\|schemas import scorecard" app/ tests/` returns nothing, then `.venv/bin/python -m pytest -q` stays green. (cat:backend; multifile:no) [feat:billwatch-20260923-coverage-and-cleanup]
- [ ] [T2] billwatch-backend/app/services/notification_service.py — `NotificationService.send_notification()` (the Firebase push-send path invoked from `app/jobs/scheduler.py::send_notifications_job`) has no dedicated test file and sits at 17% coverage, the lowest of any service module in the repo per `pytest --cov=app --cov-report=term-missing`. Add `tests/test_notification_service.py` covering: no Firebase credentials configured (`_init_firebase` returns False, `send_notification` returns False without raising), user has no `device_tokens` (returns False), and user has `push_enabled: False` in `notification_prefs` (returns False, no send attempted). VERIFY: `cd billwatch-backend && .venv/bin/python -m pytest tests/test_notification_service.py -q --cov=app.services.notification_service --cov-report=term-missing`. (cat:test; multifile:no) [feat:billwatch-20260923-coverage-and-cleanup]
- [ ] [T2] billwatch-backend/app/routers/analytics.py — `GET /api/analytics/{bill_id}/detail` (`get_bill_detail`, line 419) has zero test coverage — `pytest --cov` shows lines 424-436 (the entire function body after the docstring) as missed, and no test in `tests/test_analytics_router.py` calls this route. Add tests for the 404 path (nonexistent `bill_id`) and the 200 path (existing bill, asserting the `BillAnalyticsService.get_status_change_history` data is included in the response). VERIFY: `cd billwatch-backend && .venv/bin/python -m pytest tests/test_analytics_router.py -q --cov=app.routers.analytics --cov-report=term-missing`. (cat:test; multifile:no) [feat:billwatch-20260923-coverage-and-cleanup]
- [ ] [T2] billwatch-backend/app/routers/analytics.py — `POST /api/analytics/summaries/generate-batch` (`trigger_summary_batch`, line 396) has zero test coverage — no test in `tests/test_analytics_router.py` calls this route, despite neighboring alert endpoints (`/alerts`, `/alerts/{id}`) being tested. Add a test for the authenticated success path (mock `app.services.summary_scheduler.scheduler.generate_missing_summaries`) and one for the 500-on-exception path. VERIFY: `cd billwatch-backend && .venv/bin/python -m pytest tests/test_analytics_router.py -q --cov=app.routers.analytics --cov-report=term-missing`. (cat:test; multifile:no) [feat:billwatch-20260923-coverage-and-cleanup]
- [ ] [T2] billwatch-backend/app/routers/legislators.py — `GET /api/legislators/{bioguide_id}/sponsored-bills` (line 379) is only exercised by `tests/test_legislator_search.py:41`, which hits a non-existent bioguide id and asserts an empty list — the happy path (a real legislator with matching `Bill.sponsor_bioguide_id` rows) and the response-shaping code at the end of the function are untested. Add a test that seeds a legislator + bills and asserts the returned fields/ordering. VERIFY: `cd billwatch-backend && .venv/bin/python -m pytest tests/test_legislator_search.py -q --cov=app.routers.legislators --cov-report=term-missing`. (cat:test; multifile:no) [feat:billwatch-20260923-coverage-and-cleanup]
- [ ] [T2] billwatch-backend/app/services/bill_ranking_service.py + app/routers/ranking.py — `BillRankingService.get_recently_enacted()` (service, line 228) and its router wrapper `get_recently_enacted` (routers/ranking.py, line 175) have zero test coverage anywhere in the suite — every other method on `BillRankingService` (`rank_bills`, `handle_cooldown`, `detect_activity`, `update_user_preferences`) has at least mocked coverage via `tests/test_bill_ranking.py` / `tests/test_ranking_router.py`, but neither file, nor any other, references `get_recently_enacted`. Add a router test with seeded enacted bills. VERIFY: `cd billwatch-backend && .venv/bin/python -m pytest tests/test_ranking_router.py -q --cov=app.services.bill_ranking_service --cov-report=term-missing`. (cat:test; multifile:yes) [feat:billwatch-20260923-coverage-and-cleanup]
- [ ] [T2] billwatch-backend/app/jobs/scheduler.py — `check_saved_searches_job`, `sync_committees_job`, and `sync_votes_job` (lines 134-231) are real APScheduler-invoked background jobs with zero test coverage — `tests/test_background_scheduler.py` and `tests/test_summary_scheduler.py` exist but only cover other jobs. Add tests mocking the underlying services (`SavedSearchService.check_all_notifying`, `CommitteeSyncService.sync_all`, `VoteSyncService.sync_votes`) to verify both the success-logging branch and the `except Exception` branch run without raising. VERIFY: `cd billwatch-backend && .venv/bin/python -m pytest tests/test_background_scheduler.py -q --cov=app.jobs.scheduler --cov-report=term-missing`. (cat:test; multifile:no) [feat:billwatch-20260923-coverage-and-cleanup]
- [ ] [T2] billwatch-backend/app/services/civic_api.py — `GoogleCivicAPIClient._get_state_legislators_from_openstates()` (line 470, ~115 lines) has zero test coverage despite being the real Open States integration backing state-legislator lookups — no test file references `openstates` or this method name anywhere in `tests/`. Add tests covering: no `OPEN_STATES_API_KEY` configured (graceful fallback/empty result, not a crash), a successful mocked API response, and an `httpx.HTTPStatusError` response. VERIFY: `cd billwatch-backend && .venv/bin/python -m pytest tests/test_civic_api.py -q --cov=app.services.civic_api --cov-report=term-missing`. (cat:test; multifile:no) [feat:billwatch-20260923-coverage-and-cleanup]
- [ ] [T2] billwatch-backend/app/routers/votes.py — `GET /api/votes/comparison` (`compare_legislator_votes`, line 205) has tests for empty and duplicate bioguide-id lists (`tests/test_votes_comparison.py:121,132`) but none for: more than 10 ids (should raise `InvalidLegislatorIDs`, line 226), an unknown/nonexistent bioguide id (should raise `LegislatorNotFound`, line 238), or a `bill_id` query param that doesn't match any bill's `congress_id` (should raise `BillNotFound`, lines 244-247). Add tests for these three branches. VERIFY: `cd billwatch-backend && .venv/bin/python -m pytest tests/test_votes_comparison.py -q --cov=app.routers.votes --cov-report=term-missing`. (cat:test; multifile:no) [feat:billwatch-20260923-coverage-and-cleanup]
