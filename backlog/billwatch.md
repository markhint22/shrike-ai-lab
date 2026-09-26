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

# --- Claude-decomposed from roadmap [2026-09-22 round 4]: Add unit tests for Android CivicRepository + FindRepsViewModel + HomeViewModel — zero coverage today (review + tweak) [feat:billwatch-20260922-android-civic-findreps-home-tests] ---

# --- Claude-decomposed from roadmap [2026-09-22 round 4]: Add unit tests for Android PreferencesRepository + NotificationPreferencesViewModel — zero coverage today (review + tweak) [feat:billwatch-20260922-android-preferences-tests] ---

# --- Claude research pass [2026-09-23]: civic router missing /api/civic prefix breaks Find-My-Representatives on all 3 clients (review + tweak) [feat:billwatch-20260923-civic-prefix-bug] ---

# --- Claude research pass [2026-09-23]: dead code + missing coverage batch (review + tweak) [feat:billwatch-20260923-coverage-and-cleanup] ---


# --- Claude research pass [2026-09-23 round 2]: live current_user["id"] crash in GDPR export/delete + dead schema/model cleanup batch (review + tweak) [feat:billwatch-20260923-dataexport-crash-and-dead-code] ---


# --- Claude research pass [2026-09-24]: orphaned services + re-verified coverage/dead-code gaps (previously-credited items found still unaddressed on re-check) (review + tweak) [feat:billwatch-20260924-orphaned-code-and-coverage-gaps] ---


# --- Claude research pass [2026-09-24 round 2]: false-credit re-check (2 items marked "already-satisfied" that aren't) + dead-code cruft + 4 untested web views (5th starvation streak) (review + tweak) [feat:billwatch-20260924-false-credit-recheck-and-view-tests] ---
- [ ] [T1] billwatch-backend/app/schemas/bill.py — `BillBackgroundResponse` (lines 82-93, fields `id, bill_id, context, stakeholders, expert_views, related_bills, created_at, updated_at`) is a second, orphaned definition of a class already defined and actually used from `app/schemas/bill_background.py` (imported by both `app/routers/bill_background.py` and `app/routers/bills.py:22,480`). `grep -rn "from app.schemas.bill import" app/ tests/` shows nothing importing this name from `bill.py` — it is dead on arrival, never instantiated anywhere. Delete the duplicate class from `bill.py`. VERIFY: `cd billwatch-backend && grep -n "class BillBackgroundResponse" app/schemas/bill.py` (currently shows it at line 82); after deletion the same grep returns nothing and `.venv/bin/python -c "from app.main import app; print('imports OK')"` still succeeds, then `.venv/bin/python -m pytest tests/ -k bill_background -q` stays green. (cat:backend; multifile:no) [feat:billwatch-20260924-false-credit-recheck-and-view-tests]
- [ ] [T1] billwatch-web/src/stores/__tests__/billChat.test.ts — FALSE-CREDIT FOUND: `OVERNIGHT_PROGRESS.md:1284` already marked "`[x] [T1] ... Delete this test file (its only subject, useBillChatStore, is now deleted)`" under `feat:billwatch-20260922-delete-billchat-store-dead-code`, but the file still exists on disk today as a 6-line placeholder (`describe('billChat store', ...) { it('should be defined', () => { expect(true).toBe(true) }) }`) — the store deletion landed (`src/stores/billChat.ts` is confirmed gone) but this leftover test file was never actually removed despite being marked done. Delete it for real this time. VERIFY: `cd billwatch-web && test -f src/stores/__tests__/billChat.test.ts && echo STILL_THERE || echo GONE` (currently prints `STILL_THERE`); after deletion prints `GONE`, and `npm run test` still passes. (cat:web; multifile:no) [feat:billwatch-20260924-false-credit-recheck-and-view-tests]
- [ ] [T1] billwatch-web/src/components/DeleteAccountButton.js + DeleteAccountButton.jsx — two 1-line dead stub files (`// Deprecated: Use DeleteAccountButton.vue instead`, nothing else) sitting alongside the real, actively-used `DeleteAccountButton.vue` (imported by `ProfileView.vue`, tested by `src/components/__tests__/DeleteAccountButton.spec.ts`). `grep -rn "DeleteAccountButton" src/ --include='*.ts' --include='*.vue'` confirms zero references to the `.js`/`.jsx` versions anywhere. Delete both stub files. VERIFY: `cd billwatch-web && cat src/components/DeleteAccountButton.js src/components/DeleteAccountButton.jsx` (currently prints the deprecation comment twice); after deletion `test ! -f src/components/DeleteAccountButton.js && test ! -f src/components/DeleteAccountButton.jsx && echo DELETED`, then `npm run build` stays green. (cat:web; multifile:yes) [feat:billwatch-20260924-false-credit-recheck-and-view-tests]
- [ ] [T2] billwatch-android/app/src/test/java/com/billwatch/data/repository/TopicsRepositoryTest.kt + app/src/test/java/com/billwatch/ui/screens/TopicsViewModelTest.kt — FALSE-CREDIT FOUND: both are marked `[x] (already-satisfied in code, implement-verified)` in `OVERNIGHT_PROGRESS.md:1342` and `:1357` under `feat:billwatch-20260922-android-topics-tests`, but neither file exists anywhere in the repo — `find app/src/test -iname "TopicsRepositoryTest.kt" -o -iname "TopicsViewModelTest.kt"` returns nothing, while `TopicsRepository.kt` and `TopicsViewModel.kt` (the real, un-mocked production classes) still have zero test coverage. Create both test files mirroring the established mockk/coEvery/runTest pattern used in `AuthRepositoryTest.kt`. VERIFY: `cd billwatch-android && find app/src/test -iname "TopicsRepositoryTest.kt" -o -iname "TopicsViewModelTest.kt"` (currently empty), then after adding tests `./gradlew testDebugUnitTest --tests "com.billwatch.data.repository.TopicsRepositoryTest" --tests "com.billwatch.ui.screens.TopicsViewModelTest"`. (cat:mobile; multifile:yes) [feat:billwatch-20260924-false-credit-recheck-and-view-tests]
- [ ] [T2] billwatch-android/app/src/test/java/com/billwatch/ui/screens/NotificationPreferencesViewModelTest.kt — FALSE-CREDIT FOUND: marked `[x] (already-satisfied in code, implement-verified)` in `OVERNIGHT_PROGRESS.md:1368`, but the file does not exist — `find app/src/test -iname "NotificationPreferencesViewModelTest.kt"` returns nothing. `NotificationPreferencesRepository`'s own test (`PreferencesRepositoryTest.kt`) does exist and pass, but the ViewModel itself (`NotificationPreferencesViewModel.kt`) has zero coverage. Create the test file mocking the repository with mockk/coEvery/runTest. VERIFY: `cd billwatch-android && find app/src/test -iname "NotificationPreferencesViewModelTest.kt"` (currently empty), then after adding it `./gradlew testDebugUnitTest --tests "com.billwatch.ui.screens.NotificationPreferencesViewModelTest"`. (cat:mobile; multifile:no) [feat:billwatch-20260924-false-credit-recheck-and-view-tests]
- [ ] [T2] billwatch-web/src/components/BillSummaryPanel.vue — this 109-line component (expand/collapse toggle, conditional `key_points` list render, conditional `impact_analysis` block, `formatDate` on `summary.created_at`, collapsed 2-line preview) has zero test coverage — it's the one component in `src/components/` with no matching file in `__tests__/` (`comm -23` against the directory listing confirms it's the sole gap). Add a unit test mounting with a mocked `summary` prop covering: no-summary (renders nothing), collapsed-preview text, expanded state showing key points + impact analysis, and the expand/collapse toggle. VERIFY: `cd billwatch-web && npm run test -- BillSummaryPanel`. (cat:test; multifile:no) [feat:billwatch-20260924-false-credit-recheck-and-view-tests]
- [ ] [T2] billwatch-web/src/views/LegislatorDetailView.vue — this 518-line view (tab state machine across `info/votes/missed/finance/scorecard/committees`, lazy per-tab data fetch in a `watch(selectedTab, ...)` that only calls `fetchFinance`/`fetchScorecard`/`fetchCommittees` the first time each tab is opened, `toggleFollow`/`toggleFollowCommittee` wired to `useLegislatorsStore`) has zero test coverage — no `views/__tests__/LegislatorDetailView.test.ts` exists. Add a unit test mocking `useLegislatorsStore` covering: the lazy-fetch-only-once behavior when switching to the `finance`/`scorecard`/`committees` tabs, and the follow/unfollow toggles for both legislator and committee. VERIFY: `cd billwatch-web && npm run test -- LegislatorDetailView`. (cat:test; multifile:no) [feat:billwatch-20260924-false-credit-recheck-and-view-tests]
- [ ] [T2] billwatch-web/src/views/FindRepsView.vue — this 224-line view (`searchReps()`/`clearSearch()` wired to `useCivicStore`, address pre-fill from `authStore.user?.address` on mount, `federalReps`/`stateReps`/`localReps` computed groupings via `civicStore.getFederalReps()` etc., `partyColor`/`partyInitial` mapping helpers for Democrat/Republican/Independent) has zero test coverage — no `views/__tests__/FindRepsView.test.ts` exists (the Android equivalent, `FindRepsViewModelTest.kt`, already has coverage; the web view does not). Add a unit test mocking `useCivicStore`/`useAuthStore` covering the address pre-fill, `searchReps`/`clearSearch`, and the `partyColor`/`partyInitial` branches. VERIFY: `cd billwatch-web && npm run test -- FindRepsView`. (cat:test; multifile:no) [feat:billwatch-20260924-false-credit-recheck-and-view-tests]
- [ ] [T2] billwatch-web/src/views/SavedSearchesView.vue — this 257-line view (loading/error/empty-state branches, `showCreateDialog` flow, per-search `last_result_count`/`last_run_at` display with `formatDate`) has zero test coverage — no `views/__tests__/SavedSearchesView.test.ts` exists. Add a unit test mocking the saved-searches store covering the loading state, the empty-state "Create Your First Search" CTA, and the populated-list render with `formatDate`. VERIFY: `cd billwatch-web && npm run test -- SavedSearchesView`. (cat:test; multifile:no) [feat:billwatch-20260924-false-credit-recheck-and-view-tests]
- [ ] [T2] billwatch-web/src/views/ProfileView.vue — `saveAddress()` (the address edit/save flow: `startEditAddress()` pre-fills from `authStore.user?.address`, `saveAddress()` guards on empty/whitespace input, throws if `authStore.user` is falsy, calls `authStore.saveAddress()` and surfaces `authStore.error` via `saveErrorMessage`/`saveStatusMessage` computed) has zero test coverage — no `views/__tests__/ProfileView.test.ts` exists (prior work on this file only added `rel="noopener"` and a delete-account button, never a test). Add a unit test mocking `useAuthStore` covering: empty-input no-op, the not-authenticated throw path, a failed save surfacing the store's error message, and a successful save exiting edit mode. VERIFY: `cd billwatch-web && npm run test -- ProfileView`. (cat:test; multifile:no) [feat:billwatch-20260924-false-credit-recheck-and-view-tests]

# --- 27B-decomposed from roadmap [2026-09-25]: **[LIVE BUG]** Fix `bill_status.py`'s `STATUS_ALIASES` to recognize the literal status str (review + tweak) [feat:billwatch-20260925-live-bug-fix-bill-status-py-s-status-ali] ---
- [ ] [T1] billwatch-backend/app/utils/bill_status.py — Add underscored keys `passed_house`, `passed_senate` to `STATUS_ALIASES` mapping to `passed_chamber`, and add `became_law` mapping to `enacted`. VERIFY: `python -c "from app.utils.bill_status import normalize_status; assert normalize_status('passed_house') == 'passed_chamber'; assert normalize_status('became_law') == 'enacted'"`. (cat:python; multifile:no) [feat:billwatch-20260925-live-bug-fix-bill-status-py-s-status-ali]
- [ ] [T1] billwatch-backend/app/utils/bill_status.py — Add `vetoed` to `STATUS_ORDER` as a terminal state (rank 5, after `enacted`) and ensure `status_rank` returns the correct index for it. VERIFY: `python -c "from app.utils.bill_status import status_rank; assert status_rank('vetoed') == 5"`. (cat:python; multifile:no) [feat:billwatch-20260925-live-bug-fix-bill-status-py-s-status-ali]
- [ ] [T1] billwatch-backend/app/utils/bill_status.py — Add `to_president` to `STATUS_ORDER` (rank 4, between `passed_chamber` and `enacted`) and ensure `status_rank` returns the correct index for it. VERIFY: `python -c "from app.utils.bill_status import status_rank; assert status_rank('to_president') == 4"`. (cat:python; multifile:no) [feat:billwatch-20260925-live-bug-fix-bill-status-py-s-status-ali]
- [ ] [T2] billwatch-backend/tests/test_bill_status.py — Create a new test file with unit tests asserting `normalize_status` and `status_rank` handle the literal strings `passed_house`, `passed_senate`, `to_president`, `became_law`, and `vetoed`. VERIFY: `pytest billwatch-backend/tests/test_bill_status.py -v`. (cat:test; multifile:no) [feat:billwatch-20260925-live-bug-fix-bill-status-py-s-status-ali]
- [ ] [T2] billwatch-backend/tests/test_alert_threshold.py — Add regression tests to `should_alert` using the literal underscored strings (`passed_house`, `to_president`, `vetoed`) to verify threshold logic triggers correctly for real production values. VERIFY: `pytest billwatch-backend/tests/test_alert_threshold.py -v`. (cat:test; multifile:no) [feat:billwatch-20260925-live-bug-fix-bill-status-py-s-status-ali]
- [ ] [T3] billwatch-backend/app/utils/alert_threshold.py — Verify `should_alert` logic correctly handles the new rank values for `to_president` and `vetoed` without code changes if ranks are correct, but add explicit edge-case handling if `vetoed` should not trigger alerts from lower states (optional refinement). VERIFY: `pytest billwatch-backend/tests/test_alert_threshold.py -v`. (cat:python; multifile:no) [feat:billwatch-20260925-live-bug-fix-bill-status-py-s-status-ali]

# --- 27B-decomposed from roadmap [2026-09-25]: **[LIVE BUG]** Fix `recommendation_service.py`'s stale "Active"/"Introduced" status litera (review + tweak) [feat:billwatch-20260925-live-bug-fix-recommendation-service-py-s] ---
- [ ] [T1] billwatch-backend/app/services/recommendation_service.py — Replace the hardcoded list `["Active", "Introduced"]` in `recommend_bills_for_user` with a dynamic query using `Bill.status.notin_(["enacted", "dead", "vetoed"])` or explicit lowercase statuses `["introduced", "in_committee", "passed_house", "passed_senate"]`. VERIFY: `grep -n "Active\|Introduced" billwatch-backend/app/services/recommendation_service.py` returns no matches for the status filter. (cat:python; multifile:no) [feat:billwatch-20260925-live-bug-fix-recommendation-service-py-s]
- [ ] [T2] billwatch-backend/tests/test_recommendation_service.py — Update the `_bill()` fixture helper to default `status="introduced"` instead of `"Active"`. VERIFY: `grep -n 'status="Active"' billwatch-backend/tests/test_recommendation_service.py` returns no matches. (cat:test; multifile:no) [feat:billwatch-20260925-live-bug-fix-recommendation-service-py-s]
- [ ] [T2] billwatch-backend/tests/test_recommendation_service.py — Add a test case `test_recommend_bills_uses_lowercase_status` that creates a bill with `status="introduced"` and verifies it is returned by `recommend_bills_for_user`. VERIFY: `pytest billwatch-backend/tests/test_recommendation_service.py::test_recommend_bills_uses_lowercase_status -v` passes. (cat:test; multifile:no) [feat:billwatch-20260925-live-bug-fix-recommendation-service-py-s]
- [ ] [T2] billwatch-backend/tests/test_recommendation_service.py — Add a test case `test_recommend_bills_excludes_enacted` that creates a bill with `status="enacted"` and verifies it is NOT returned by `recommend_bills_for_user`. VERIFY: `pytest billwatch-backend/tests/test_recommendation_service.py::test_recommend_bills_excludes_enacted -v` passes. (cat:test; multifile:no) [feat:billwatch-20260925-live-bug-fix-recommendation-service-py-s]
- [ ] [T3] billwatch-backend/app/services/recommendation_service.py — Ensure the fallback logic in `_trending_excluding` is only triggered if the personalized query returns zero results, and add a log warning if the personalized query returns 0 rows to aid debugging. VERIFY: `grep -n "logger.warning" billwatch-backend/app/services/recommendation_service.py` shows a new warning line related to empty recommendations. (cat:python; multifile:no) [feat:billwatch-20260925-live-bug-fix-recommendation-service-py-s]

# --- 27B-decomposed from roadmap [2026-09-25]: Alert the founder when a Congress.gov ingestion source goes stale, instead of only exposin (review + tweak) [feat:billwatch-20260925-alert-the-founder-when-a-congress-gov-in] ---
- [ ] [T1] billwatch-backend/app/services/sync_status_service.py — Add `get_stale_sources()` function returning list of source IDs where `is_stale()` is True. VERIFY: `pytest tests/test_sync_status_service.py::test_get_stale_sources -v`. (cat:python; multifile:no) [feat:billwatch-20260925-alert-the-founder-when-a-congress-gov-in]
- [ ] [T1] billwatch-backend/app/services/staleness_alert_service.py — Create new service with `check_and_alert_stale_sources()` that calls `get_stale_sources()`, checks `admin_alert_email` config, and sends email via `email_service`. VERIFY: `pytest tests/test_staleness_alert_service.py::test_check_and_alert_stale_sources -v`. (cat:python; multifile:no) [feat:billwatch-20260925-alert-the-founder-when-a-congress-gov-in]
- [ ] [T2] billwatch-backend/app/services/staleness_alert_service.py — Add `_is_already_alerted(source_id)` and `_mark_as_alerted(source_id)` using in-memory set or DB check to dedupe alerts. VERIFY: `pytest tests/test_staleness_alert_service.py::test_deduplication -v`. (cat:python; multifile:no) [feat:billwatch-20260925-alert-the-founder-when-a-congress-gov-in]
- [ ] [T3] billwatch-backend/app/config.py — Add `admin_alert_email: str = ""` setting with empty string default. VERIFY: `grep -q "admin_alert_email" billwatch-backend/app/config.py && python -c "from app.config import settings; print(settings.admin_alert_email)"`. (cat:python; multifile:no) [feat:billwatch-20260925-alert-the-founder-when-a-congress-gov-in]
- [ ] [T3] billwatch-backend/app/jobs/scheduler.py — Register `staleness_alert_service.check_and_alert_stale_sources()` as a scheduled job. VERIFY: `grep -q "check_and_alert_stale_sources" billwatch-backend/app/jobs/scheduler.py && python -c "from app.jobs.scheduler import scheduler; print('registered')"`. (cat:python; multifile:no) [feat:billwatch-20260925-alert-the-founder-when-a-congress-gov-in]
- [ ] [T1] billwatch-backend/tests/test_sync_status_service.py — Add unit tests for `get_stale_sources()` with mocked sync statuses. VERIFY: `pytest tests/test_sync_status_service.py -v`. (cat:test; multifile:no) [feat:billwatch-20260925-alert-the-founder-when-a-congress-gov-in]
- [ ] [T1] billwatch-backend/tests/test_staleness_alert_service.py — Add unit tests for `check_and_alert_stale_sources()` including deduplication and email sending. VERIFY: `pytest tests/test_staleness_alert_service.py -v`. (cat:test; multifile:no) [feat:billwatch-20260925-alert-the-founder-when-a-congress-gov-in]
