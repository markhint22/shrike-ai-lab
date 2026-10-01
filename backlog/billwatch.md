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

# --- 27B-decomposed from roadmap [2026-09-25]: **[LIVE BUG]** Fix `bill_status.py`'s `STATUS_ALIASES` to recognize the literal status str (review + tweak) [feat:billwatch-20260925-live-bug-fix-bill-status-py-s-status-ali] ---

# --- 27B-decomposed from roadmap [2026-09-25]: **[LIVE BUG]** Fix `recommendation_service.py`'s stale "Active"/"Introduced" status litera (review + tweak) [feat:billwatch-20260925-live-bug-fix-recommendation-service-py-s] ---

# --- 27B-decomposed from roadmap [2026-09-25]: Alert the founder when a Congress.gov ingestion source goes stale, instead of only exposin (review + tweak) [feat:billwatch-20260925-alert-the-founder-when-a-congress-gov-in] ---

# --- 27B-decomposed from roadmap [2026-09-28]: **[HUMAN/design]** Add a real "bill died / session ended" terminal status instead of leavi (review + tweak) [feat:billwatch-20260928-human-design-add-a-real-bill-died-sessio] ---

# --- 27B-decomposed from roadmap [2026-09-28]: Prune invalid/unregistered FCM device tokens after failed push sends instead of retrying t (review + tweak) [feat:billwatch-20260928-prune-invalid-unregistered-fcm-device-to] ---

# --- 27B-decomposed from roadmap [2026-09-28]: Add `DELETE /api/auth/me/device-token` so a logged-out device stops receiving another user (review + tweak) [feat:billwatch-20260928-add-delete-api-auth-me-device-token-so-a] ---

# --- 27B-decomposed from roadmap [2026-09-28]: Wire the already-built `MobileGapAnalyzer` + `mobile_feature_map` static data into a real  (review + tweak) [feat:billwatch-20260928-wire-the-already-built-mobilegapanalyzer] ---

# --- 27B-decomposed from roadmap [2026-09-29]: Delete 5 more orphaned dead-code backend services with self-testing-only test suites — ver (review + tweak) [feat:billwatch-20260929-delete-5-more-orphaned-dead-code-backend] ---

# --- 27B-decomposed from roadmap [2026-09-30]: Stop bill status from regressing and firing "backwards" follower alerts — bill_sync_servic (review + tweak) [feat:billwatch-20260930-stop-bill-status-from-regressing-and-fir] ---

# --- 27B-decomposed from roadmap [2026-09-30]: Stop the scheduled bill sync from clobbering sponsor/policy_area and hydrate from the deta (review + tweak) [feat:billwatch-20260930-stop-the-scheduled-bill-sync-from-clobbe] ---

# --- 27B-decomposed from roadmap [2026-09-30]: Make sure followed bills are always synced, not just the 50 most recently updated — app/jo (review + tweak) [feat:billwatch-20260930-make-sure-followed-bills-are-always-sync] ---

# --- 27B-decomposed from roadmap [2026-09-30]: Require auth/admin on unauthenticated quota-burning and abuse-prone POST endpoints — verif (review + tweak) [feat:billwatch-20260930-require-auth-admin-on-unauthenticated-qu] ---

# --- 27B-decomposed from roadmap [2026-09-30]: Fix account deletion failing on Postgres and the web button that calls a non-existent rout (review + tweak) [feat:billwatch-20260930-fix-account-deletion-failing-on-postgres] ---

# --- 27B-decomposed from roadmap [2026-09-30]: Add in-app account deletion to the iOS and Android apps (App Store 5.1.1(v) / Google Play  (review + tweak) [feat:billwatch-20260930-add-in-app-account-deletion-to-the-ios-a] ---
- [ ] [T1] billwatch-backend/app/routers/data_export.py — Add `delete_account` endpoint handler that validates auth, deletes user record and associated data, returns 204. VERIFY: `cd billwatch-backend && python -m pytest tests/test_data_export_delete.py::test_delete_account_success -v`. (cat:endpoint; multifile:no) [feat:billwatch-20260930-add-in-app-account-deletion-to-the-ios-a]
- [ ] [T1] billwatch-backend/tests/test_data_export_delete.py — Create test file with mock user and verify `DELETE /api/export/account` returns 204 and removes user from DB. VERIFY: `cd billwatch-backend && python -m pytest tests/test_data_export_delete.py -v`. (cat:test; multifile:no) [feat:billwatch-20260930-add-in-app-account-deletion-to-the-ios-a]
- [ ] [T1] billwatch-ios/BillWatch/Services/APIService.swift — Add `deleteAccount()` method that sends DELETE request to `/api/export/account` and handles 204 response. VERIFY: `cd billwatch-ios && xcodebuild test -scheme BillWatch -only-testing:BillWatchTests/APIServicesTests/testDeleteAccount`. (cat:typescript; multifile:no) [feat:billwatch-20260930-add-in-app-account-deletion-to-the-ios-a]
- [ ] [T1] billwatch-ios/BillWatch/Tests/APIServicesTests.swift — Add unit test for `deleteAccount()` verifying correct HTTP method and URL. VERIFY: `cd billwatch-ios && xcodebuild test -scheme BillWatch -only-testing:BillWatchTests/APIServicesTests/testDeleteAccount`. (cat:test; multifile:no) [feat:billwatch-20260930-add-in-app-account-deletion-to-the-ios-a]
- [ ] [T1] billwatch-android/app/src/main/java/com/billwatch/api/BillWatchApi.kt — Add `deleteAccount()` suspend function using Retrofit DELETE to `/api/export/account`. VERIFY: `cd billwatch-android && ./gradlew testDebugUnitTest --tests "com.billwatch.api.BillWatchApiTest.deleteAccount"`. (cat:typescript; multifile:no) [feat:billwatch-20260930-add-in-app-account-deletion-to-the-ios-a]
- [ ] [T1] billwatch-android/app/src/test/java/com/billwatch/api/BillWatchApiTest.kt — Add unit test for `deleteAccount()` verifying Retrofit call construction. VERIFY: `cd billwatch-android && ./gradlew testDebugUnitTest --tests "com.billwatch.api.BillWatchApiTest.deleteAccount"`. (cat:test; multifile:no) [feat:billwatch-20260930-add-in-app-account-deletion-to-the-ios-a]
- [ ] [T3] billwatch-ios/BillWatch/Views/Profile/ProfileView.swift — Add "Delete Account" row with confirmation dialog that calls `APIService.deleteAccount()` and clears tokens on success. VERIFY: `cd billwatch-ios && xcodebuild test -scheme BillWatch -only-testing:BillWatchTests/ProfileViewTests/testDeleteAccountFlow`. (cat:typescript; multifile:no) [feat:billwatch-20260930-add-in-app-account-deletion-to-the-ios-a]
- [ ] [T3] billwatch-android/app/src/main/java/com/billwatch/ui/screens/ProfileScreen.kt — Add "Delete Account" UI element with confirmation dialog that calls `BillWatchApi.deleteAccount()` and clears session on success. VERIFY: `cd billwatch-android && ./gradlew testDebugUnitTest --tests "com.billwatch.ui.screens.ProfileScreenTest.deleteAccountFlow"`. (cat:typescript; multifile:no) [feat:billwatch-20260930-add-in-app-account-deletion-to-the-ios-a]

# --- 27B-decomposed from roadmap [2026-09-30]: Enforce the admin "ban" (is_active=false) at login, refresh and get_current_user — app/rou (review + tweak) [feat:billwatch-20260930-enforce-the-admin-ban-is-active-false-at] ---
- [ ] [T1] billwatch-backend/app/services/auth_guard.py — Create new module with `check_user_active(user: User) -> None` that raises `HTTPException(403, "Account disabled")` if `user.is_active is False`, and `log_ban_attempt(user_id: int, ip: str)` that creates an `AuthEvent` record. VERIFY: `cd billwatch-backend && python -m pytest tests/test_auth_guard.py::test_check_user_active_raises -v`. (cat:python; multifile:no) [feat:billwatch-20260930-enforce-the-admin-ban-is-active-false-at]
- [ ] [T1] billwatch-backend/tests/test_auth_guard.py — Create test file mocking `User` and `AuthEvent` to verify `check_user_active` raises 403 for inactive users and passes for active, and that `log_ban_attempt` calls `session.add`. VERIFY: `cd billwatch-backend && python -m pytest tests/test_auth_guard.py -v`. (cat:test; multifile:no) [feat:billwatch-20260930-enforce-the-admin-ban-is-active-false-at]
- [ ] [T3] billwatch-backend/app/routers/auth.py — Import `check_user_active` and `log_ban_attempt` in `login()` (line 161), call `check_user_active(user)` after password verification, and wrap the call to log the event on failure. VERIFY: `cd billwatch-backend && python -m pytest tests/test_auth_login_ban.py::test_login_banned_user_returns_403 -v`. (cat:endpoint; multifile:no) [feat:billwatch-20260930-enforce-the-admin-ban-is-active-false-at]
- [ ] [T3] billwatch-backend/app/routers/auth.py — Import `check_user_active` and `log_ban_attempt` in `refresh_token()` (line 198), call `check_user_active(user)` after fetching user from token, and log the event on failure. VERIFY: `cd billwatch-backend && python -m pytest tests/test_auth_refresh_ban.py::test_refresh_banned_user_returns_403 -v`. (cat:endpoint; multifile:no) [feat:billwatch-20260930-enforce-the-admin-ban-is-active-false-at]
- [ ] [T3] billwatch-backend/app/routers/auth.py — Import `check_user_active` in `get_current_user()` (line 58), call it after fetching the user, and return `None` or raise 401 if inactive to treat as unauthenticated. VERIFY: `cd billwatch-backend && python -m pytest tests/test_auth_deps_ban.py::test_get_current_user_inactive_raises_401 -v`. (cat:endpoint; multifile:no) [feat:billwatch-20260930-enforce-the-admin-ban-is-active-false-at]
- [ ] [T3] billwatch-backend/app/routers/auth.py — Import `check_user_active` in `get_current_user_optional()` (line 75), call it after fetching the user, and return `None` if inactive to treat as unauthenticated. VERIFY: `cd billwatch-backend && python -m pytest tests/test_auth_deps_ban.py::test_get_current_user_optional_inactive_returns_none -v`. (cat:endpoint; multifile:no) [feat:billwatch-20260930-enforce-the-admin-ban-is-active-false-at]
- [ ] [T2] billwatch-backend/tests/test_auth_login_ban.py — Create test that mocks a banned user, calls `login()`, and asserts 403 response with "Account disabled" message. VERIFY: `cd billwatch-backend && python -m pytest tests/test_auth_login_ban.py -v`. (cat:test; multifile:no) [feat:billwatch-20260930-enforce-the-admin-ban-is-active-false-at]
- [ ] [T2] billwatch-backend/tests/test_auth_refresh_ban.py — Create test that mocks a banned user with a valid refresh token, calls `refresh_token()`, and asserts 403 response. VERIFY: `cd billwatch-backend && python -m pytest tests/test_auth_refresh_ban.py -v`. (cat:test; multifile:no) [feat:billwatch-20260930-enforce-the-admin-ban-is-active-false-at]
- [ ] [T2] billwatch-backend/tests/test_auth_deps_ban.py — Create tests for `get_current_user` and `get_current_user_optional` with inactive users, asserting 401/None respectively. VERIFY: `cd billwatch-backend && python -m pytest tests/test_auth_deps_ban.py -v`. (cat:test; multifile:no) [feat:billwatch-20260930-enforce-the-admin-ban-is-active-false-at]

# --- 27B-decomposed from roadmap [2026-10-01]: Fix rate limiting keying on the proxy IP on Railway — app/core/rate_limiter.py uses slowap (review + tweak) [feat:billwatch-20261001-fix-rate-limiting-keying-on-the-proxy-ip] ---
- [ ] [T1] billwatch-backend/app/core/rate_limiter.py — Add a `get_client_ip(request: Request) -> str` function that extracts the last IP from the `X-Forwarded-For` header (splitting by comma and stripping whitespace) or falls back to `request.client.host` if the header is missing/invalid. VERIFY: `python -m pytest billwatch-backend/tests/test_rate_limiter.py::test_get_client_ip_xff_last_hop -v` passes with a mock request containing `X-Forwarded-For: 1.2.3.4, 5.6.7.8` returning `5.6.7.8`. (cat:python; multifile:no) [feat:billwatch-20261001-fix-rate-limiting-keying-on-the-proxy-ip]
- [ ] [T1] billwatch-backend/app/core/rate_limiter.py — Add a `get_client_ip_no_xff(request: Request) -> str` function that strictly returns `request.client.host` ignoring any proxy headers, for use in non-proxy contexts or as a fallback. VERIFY: `python -m pytest billwatch-backend/tests/test_rate_limiter.py::test_get_client_ip_no_xff -v` passes with a mock request containing `X-Forwarded-For: 9.9.9.9` and `request.client.host=10.0.0.1` returning `10.0.0.1`. (cat:python; multifile:no) [feat:billwatch-20261001-fix-rate-limiting-keying-on-the-proxy-ip]
- [ ] [T2] billwatch-backend/tests/test_rate_limiter.py — Create a new test file with unit tests for `get_client_ip` covering: valid multi-hop XFF, single-hop XFF, missing XFF header, malformed XFF header (no commas), and empty XFF header. VERIFY: `python -m pytest billwatch-backend/tests/test_rate_limiter.py -v` passes all 5 test cases. (cat:test; multifile:no) [feat:billwatch-20261001-fix-rate-limiting-keying-on-the-proxy-ip]
- [ ] [T3] billwatch-backend/app/core/rate_limiter.py — Update the `key_func` parameter in the `SlowAPIMiddleware` initialization (or the specific limiter instances) to use `get_client_ip` instead of relying on the default `get_remote_address`. VERIFY: `grep -n "key_func=get_client_ip" billwatch-backend/app/core/rate_limiter.py` returns at least one match. (cat:python; multifile:no) [feat:billwatch-20261001-fix-rate-limiting-keying-on-the-proxy-ip]
- [ ] [T3] billwatch-backend/app/services/security_audit_service.py — Refactor the `client_ip` property (or equivalent method around line 27) to use the new `get_client_ip` utility from `app.core.rate_limiter` instead of parsing `X-Forwarded-For` manually, ensuring consistency with rate limiting. VERIFY: `grep -n "from app.core.rate_limiter import get_client_ip" billwatch-backend/app/services/security_audit_service.py` returns a match and `python -m pytest billwatch-backend/tests/test_security_audit.py::test_client_ip_uses_rate_limiter_util -v` passes. (cat:python; multifile:no) [feat:billwatch-20261001-fix-rate-limiting-keying-on-the-proxy-ip]
- [ ] [T3] billwatch-backend/start.sh — Modify the uvicorn startup command to include `--proxy-headers --forwarded-allow-ips='*'` flags to ensure `request.client.host` reflects the proxy chain correctly if the key_func relies on it, or to support the new header parsing logic. VERIFY: `grep -n "uvicorn.*--proxy-headers" billwatch-backend/start.sh` returns a match. (cat:python; multifile:no) [feat:billwatch-20261001-fix-rate-limiting-keying-on-the-proxy-ip]
- [ ] [T4] billwatch-backend/app/main.py — Verify that the `SlowAPIMiddleware` is correctly configured to use the updated key function by checking the import and instantiation, ensuring no circular imports occur with `app.core.rate_limiter`. VERIFY: `python -c "from app.main import app; print('OK')"` executes without ImportError or CircularImportError. (cat:python; multifile:yes) [feat:billwatch-20261001-fix-rate-limiting-keying-on-the-proxy-ip]

# --- 27B-decomposed from roadmap [2026-10-01]: Add real session refresh to web and Android (users are forced to re-login every 30 minutes (review + tweak) [feat:billwatch-20261001-add-real-session-refresh-to-web-and-andr] ---
- [ ] [T1] billwatch-web/src/services/authUtils.ts — Create pure function `extractRefreshToken()` that reads from localStorage and returns string or null. VERIFY: `npx vitest run src/services/__tests__/authUtils.test.ts` passes. (cat:typescript; multifile:no) [feat:billwatch-20261001-add-real-session-refresh-to-web-and-andr]
- [ ] [T2] billwatch-web/src/services/api.ts — Modify response interceptor to check if URL is `/auth/refresh`; if 401 and not refresh URL, call `extractRefreshToken()`, POST to `/auth/refresh`, update tokens in storage, and retry original request once; only redirect to login on second failure. VERIFY: `npx vitest run src/services/__tests__/api.test.ts` passes with mocked axios instance. (cat:typescript; multifile:no) [feat:billwatch-20261001-add-real-session-refresh-to-web-and-andr]
- [ ] [T3] billwatch-web/src/stores/auth.ts — Ensure `refresh_token` is persisted to localStorage upon successful login/refresh and cleared on logout. VERIFY: `npx vitest run src/stores/__tests__/auth.test.ts` passes. (cat:typescript; multifile:no) [feat:billwatch-20261001-add-real-session-refresh-to-web-and-andr]
- [ ] [T1] billwatch-android/app/src/main/java/com/billwatch/data/local/AuthDataStore.kt — Add `getRefreshToken(): String?` and `saveRefreshToken(token: String)` methods using DataStore keys. VERIFY: `./gradlew :app:testDebugUnitTest --tests "com.billwatch.data.local.AuthDataStoreTest"` passes. (cat:kotlin; multifile:no) [feat:billwatch-20261001-add-real-session-refresh-to-web-and-andr]
- [ ] [T2] billwatch-android/app/src/main/java/com/billwatch/data/network/Authenticator.kt — Implement `okhttp3.Authenticator` that reads refresh token from DataStore, calls `/auth/refresh`, updates DataStore with new tokens, and returns new Request; return null if refresh fails. VERIFY: `./gradlew :app:testDebugUnitTest --tests "com.billwatch.data.network.AuthenticatorTest"` passes with mocked Retrofit/DataStore. (cat:kotlin; multifile:no) [feat:billwatch-20261001-add-real-session-refresh-to-web-and-andr]
- [ ] [T3] billwatch-android/app/src/main/java/com/billwatch/data/network/ApiClient.kt — Configure OkHttp client to use the new `Authenticator` instance. VERIFY: `./gradlew :app:testDebugUnitTest --tests "com.billwatch.data.network.ApiClientTest"` passes verifying authenticator is set. (cat:kotlin; multifile:no) [feat:billwatch-20261001-add-real-session-refresh-to-web-and-andr]
- [ ] [T4] billwatch-android/app/src/main/java/com/billwatch/data/repository/AuthRepository.kt — Refactor `refreshToken()` to use the new DataStore methods and API client instead of hard-coded empty string, ensuring it returns updated tokens. VERIFY: `./gradlew :app:testDebugUnitTest --tests "com.billwatch.data.repository.AuthRepositoryTest"` passes. (cat:kotlin; multifile:yes) [feat:billwatch-20261001-add-real-session-refresh-to-web-and-andr]
