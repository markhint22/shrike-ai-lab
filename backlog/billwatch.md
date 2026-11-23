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

# --- 27B-decomposed from roadmap [2026-09-30]: Enforce the admin "ban" (is_active=false) at login, refresh and get_current_user — app/rou (review + tweak) [feat:billwatch-20260930-enforce-the-admin-ban-is-active-false-at] ---

# --- 27B-decomposed from roadmap [2026-10-01]: Fix rate limiting keying on the proxy IP on Railway — app/core/rate_limiter.py uses slowap (review + tweak) [feat:billwatch-20261001-fix-rate-limiting-keying-on-the-proxy-ip] ---

# --- 27B-decomposed from roadmap [2026-10-01]: Add real session refresh to web and Android (users are forced to re-login every 30 minutes (review + tweak) [feat:billwatch-20261001-add-real-session-refresh-to-web-and-andr] ---

# --- 27B-decomposed from roadmap [2026-10-01]: Register push device tokens after login on iOS and Android, and unregister on logout — iOS (review + tweak) [feat:billwatch-20261001-register-push-device-tokens-after-login-] ---

# --- 27B-decomposed from roadmap [2026-10-02]: Add forgot/reset-password flow (none exists in backend or any client) — repo-wide grep for (review + tweak) [feat:billwatch-20261002-add-forgot-reset-password-flow-none-exis] ---

# --- 27B-decomposed from roadmap [2026-10-02]: Fix dead unsubscribe/app links in emails and add List-Unsubscribe headers — DigestService. (review + tweak) [feat:billwatch-20261002-fix-dead-unsubscribe-app-links-in-emails] ---

# --- 27B-decomposed from roadmap [2026-10-02]: Fix `digest_service.run_batch()` silently emailing users with `email_enabled=False` — `app (review + tweak) [feat:billwatch-20261002-fix-digest-service-run-batch-silently-em] ---

# --- 27B-decomposed from roadmap [2026-10-02]: Fix IDOR in `GET /api/export/exports/{export_id}` — `app/routers/data_export.py:48-64` cal (review + tweak) [feat:billwatch-20261002-fix-idor-in-get-api-export-exports-expor] ---

# --- 27B-decomposed from roadmap [2026-10-02]: `register()` never records a SecurityAuditService audit event — `app/routers/auth.py:138-1 (review + tweak) [feat:billwatch-20261002-register-never-records-a-securityauditse] ---

# --- 27B-decomposed from roadmap [2026-10-02]: `PATCH /me/settings` accepts arbitrary `notification_prefs` dict, bypassing `digest_freque (review + tweak) [feat:billwatch-20261002-patch-me-settings-accepts-arbitrary-noti] ---

# --- 27B-decomposed from roadmap [2026-10-03]: FEC API `_request` has no retry on 429 or 5xx — `app/services/fec_api.py:54-89` issues a s (review + tweak) [feat:billwatch-20261003-fec-api-request-has-no-retry-on-429-or-5] ---

# --- 27B-decomposed from roadmap [2026-10-03]: Add router-level tests for app/routers/civic.py — the 3 endpoints (POST + GET `/api/civic/ (review + tweak) [feat:billwatch-20261003-add-router-level-tests-for-app-routers-c] ---

# --- 27B-decomposed from roadmap [2026-10-03]: iOS BillWatchTests/ has only 2 test files against 50+ source files — `billwatch-ios/BillWa (review + tweak) [feat:billwatch-20261003-ios-billwatchtests-has-only-2-test-files] ---

# --- deterministic work supply 2026-10-14 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- deterministic work supply 2026-10-15 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- deterministic work supply 2026-10-16 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- deterministic work supply 2026-10-16 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- 27B-decomposed from roadmap [2026-10-17]: Allowlist `sort_by` on GET /api/bills and GET /api/legislators to prevent 500 crashes — `b (review + tweak) [feat:billwatch-20261017-allowlist-sort-by-on-get-api-bills-and-g] ---

# --- 27B-decomposed from roadmap [2026-10-17]: Gate `?regenerate=true` on GET /api/analytics/{bill_id}/summary behind auth to stop anonym (review + tweak) [feat:billwatch-20261017-gate-regenerate-true-on-get-api-analytic] ---

# --- 27B-decomposed from roadmap [2026-10-17]: Fix web token-refresh interceptor's `/auth/` guard forcing logout when access token expire (review + tweak) [feat:billwatch-20261017-fix-web-token-refresh-interceptor-s-auth] ---

# --- 27B-decomposed from roadmap [2026-10-18]: Security: `POST /api/analytics/summaries/generate-batch` allows any authenticated user to  (review + tweak) [feat:billwatch-20261018-security-post-api-analytics-summaries-ge] ---

# --- 27B-decomposed from roadmap [2026-10-18]: Diverged sort-field allowlists: bills.py and legislators.py shadow the canonical validator (review + tweak) [feat:billwatch-20261018-diverged-sort-field-allowlists-bills-py-] ---

# --- 27B-decomposed from roadmap [2026-10-18]: Rate-limit bills.py — the most-trafficked router has zero rate limiting on all public read (review + tweak) [feat:billwatch-20261018-rate-limit-bills-py-the-most-trafficked-] ---

# --- deterministic work supply 2026-10-18 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- 27B-decomposed from roadmap [2026-10-18]: Rate-limit legislators.py — public legislator search and detail endpoints have zero rate l (review + tweak) [feat:billwatch-20261018-rate-limit-legislators-py-public-legisla] ---

# --- 27B-decomposed from roadmap [2026-10-18]: Rate-limit finance.py — public campaign finance endpoints have zero rate limiting — financ (review + tweak) [feat:billwatch-20261018-rate-limit-finance-py-public-campaign-fi] ---

# --- 27B-decomposed from roadmap [2026-10-19]: Rate-limit alerts.py dedicated CRUD router — app/routers/alerts.py has no `limiter` import (review + tweak) [feat:billwatch-20261019-rate-limit-alerts-py-dedicated-crud-rout] ---

# --- 27B-decomposed from roadmap [2026-10-19]: Rate-limit saved_searches.py — app/routers/saved_searches.py has no `limiter` import (grep (review + tweak) [feat:billwatch-20261019-rate-limit-saved-searches-py-app-routers] ---

# --- 27B-decomposed from roadmap [2026-10-19]: Rate-limit ranking.py and users.py — ranking.py has no `limiter` import (grep: zero hits); (review + tweak) [feat:billwatch-20261019-rate-limit-ranking-py-and-users-py-ranki] ---

# --- 27B-decomposed from roadmap [2026-10-19]: iOS uses /api/alerts and web uses /api/analytics/alerts — both write to the same BillAlert (review + tweak) [feat:billwatch-20261019-ios-uses-api-alerts-and-web-uses-api-ana] ---

# --- 27B-decomposed from roadmap [2026-10-19]: Rate-limit priority_api.py — app/routers/priority_api.py has no `limiter` import (grep: ze (review + tweak) [feat:billwatch-20261019-rate-limit-priority-api-py-app-routers-p] ---

# --- 27B-decomposed from roadmap [2026-10-20]: Add unit tests for `validate_user_id` and `validate_api_key` — `billwatch-backend/app/core (review + tweak) [feat:billwatch-20261020-add-unit-tests-for-validate-user-id-and-] ---

# --- 27B-decomposed from roadmap [2026-10-20]: Add unit tests for `find_similar_bills` — `billwatch-backend/app/core/congress.py:138` is  (review + tweak) [feat:billwatch-20261020-add-unit-tests-for-find-similar-bills-bi] ---

# --- 27B-decomposed from roadmap [2026-10-20]: Test `check_stale_sources_job` stale detection logic — `billwatch-backend/app/jobs/schedul (review + tweak) [feat:billwatch-20261020-test-check-stale-sources-job-stale-detec] ---

# --- 27B-decomposed from roadmap [2026-10-20]: Test `sync_bill_sponsors_maintenance` data integrity — `billwatch-backend/app/routers/bill (review + tweak) [feat:billwatch-20261020-test-sync-bill-sponsors-maintenance-data] ---

# --- 27B-decomposed from roadmap [2026-10-20]: Test `setup_logging` configuration application — `billwatch-backend/app/core/logging.py:30 (review + tweak) [feat:billwatch-20261020-test-setup-logging-configuration-applica] ---

# --- deterministic work supply 2026-10-20 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- 27B-decomposed from roadmap [2026-10-20]: Add router-level tests for `get_most_viewed_bills` — `billwatch-backend/app/routers/bills. (review + tweak) [feat:billwatch-20261020-add-router-level-tests-for-get-most-view] ---

# --- 27B-decomposed from roadmap [2026-10-20]: Add router-level tests for `get_bill_summary` — `billwatch-backend/app/routers/bills.py:53 (review + tweak) [feat:billwatch-20261020-add-router-level-tests-for-get-bill-summ] ---

# --- 27B-decomposed from roadmap [2026-10-20]: Add unit test for `seed_topics` — `billwatch-backend/app/seed_topics.py:149` is a public f (review + tweak) [feat:billwatch-20261020-add-unit-test-for-seed-topics-billwatch-] ---

# --- deterministic work supply 2026-10-20 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- 27B-decomposed from roadmap [2026-10-21]: Test `lifespan` startup/shutdown lifecycle — `billwatch-backend/app/main.py:56` is a publi (review + tweak) [feat:billwatch-20261021-test-lifespan-startup-shutdown-lifecycle] ---

# --- 27B-decomposed from roadmap [2026-10-21]: Test `validation_exception_handler` error response format — `billwatch-backend/app/main.py (review + tweak) [feat:billwatch-20261021-test-validation-exception-handler-error-] ---

# --- deterministic work supply 2026-10-21 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- 27B-decomposed from roadmap [2026-10-21]: Test `share_image` endpoint response — `billwatch-backend/app/main.py:145` is a public fun (review + tweak) [feat:billwatch-20261021-test-share-image-endpoint-response-billw] ---

# --- 27B-decomposed from roadmap [2026-10-21]: Add unit test for `get_settings_uncached` — `billwatch-backend/app/config.py:171` is a pub (review + tweak) [feat:billwatch-20261021-add-unit-test-for-get-settings-uncached-] ---

# --- deterministic work supply 2026-10-21 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- 27B-decomposed from roadmap [2026-10-21]: Add router-level tests for `root` and `status_endpoint` — `billwatch-backend/app/main.py:1 (review + tweak) [feat:billwatch-20261021-add-router-level-tests-for-root-and-stat] ---

# --- 27B-decomposed from roadmap [2026-10-21]: Add unit test for `debug_env_vars` — `billwatch-backend/app/config.py:176` is a public fun (review + tweak) [feat:billwatch-20261021-add-unit-test-for-debug-env-vars-billwat] ---

# --- 27B-decomposed from roadmap [2026-10-21]: Add router-level tests for `get_feedback_types` — `billwatch-backend/app/routers/feedback. (review + tweak) [feat:billwatch-20261021-add-router-level-tests-for-get-feedback-] ---

# --- 27B-decomposed from roadmap [2026-10-22]: Fix N+1 query in _hydrate_bill_details for action deduplication — `billwatch-backend/app/s (review + tweak) [feat:billwatch-20261022-fix-n-1-query-in-hydrate-bill-details-fo] ---

# --- deterministic work supply 2026-10-22 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- 27B-decomposed from roadmap [2026-10-22]: Fix upvote_bill to persist the vote instead of returning success without action — `billwat (review + tweak) [feat:billwatch-20261022-fix-upvote-bill-to-persist-the-vote-inst] ---

# --- deterministic work supply 2026-10-22 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- 27B-decomposed from roadmap [2026-10-22]: Test `metrics_endpoint` response contract — `billwatch-backend/app/main.py:194` is a publi (review + tweak) [feat:billwatch-20261022-test-metrics-endpoint-response-contract-] ---

# --- 27B-decomposed from roadmap [2026-10-22]: Fix set_cached to use per-entry TTL instead of mutating global cache_ttl — `billwatch-back (review + tweak) [feat:billwatch-20261022-fix-set-cached-to-use-per-entry-ttl-inst] ---

# --- 27B-decomposed from roadmap [2026-10-22]: Test `get_bill_background` endpoint — `billwatch-backend/app/routers/bills.py:506` is a pu (review + tweak) [feat:billwatch-20261022-test-get-bill-background-endpoint-billwa] ---

# --- 27B-decomposed from roadmap [2026-10-22]: Test `get_request_context` dependency injection — `billwatch-backend/app/core/dependencies (review + tweak) [feat:billwatch-20261022-test-get-request-context-dependency-inje] ---

# --- 27B-decomposed from roadmap [2026-10-22]: Test `get_share_image` and `get_share_card` endpoints — `billwatch-backend/app/routers/bil (review + tweak) [feat:billwatch-20261022-test-get-share-image-and-get-share-card-] ---

# --- 27B-decomposed from roadmap [2026-10-23]: Remove deprecated ProPublica reference from CAREER_HISTORY doc — `docs/features/CAREER_HIS (review + tweak) [feat:billwatch-20261023-remove-deprecated-propublica-reference-f] ---

# --- 27B-decomposed from roadmap [2026-10-23]: Test `get_similar_bills` endpoint — `billwatch-backend/app/routers/bills.py:666` is a publ (review + tweak) [feat:billwatch-20261023-test-get-similar-bills-endpoint-billwatc] ---

# --- 27B-decomposed from roadmap [2026-10-23]: Fix relativeTime for future dates — `billwatch-web/src/utils/relativeTime.ts:9` (`relative (review + tweak) [feat:billwatch-20261023-fix-relativetime-for-future-dates-billwa] ---

# --- 27B-decomposed from roadmap [2026-10-23]: Test `get_bills_requiring_action` priority logic — `billwatch-backend/app/routers/priority (review + tweak) [feat:billwatch-20261023-test-get-bills-requiring-action-priority] ---

# --- 27B-decomposed from roadmap [2026-10-23]: Test `get_priority_recommendations` scoring — `billwatch-backend/app/routers/priority_api. (review + tweak) [feat:billwatch-20261023-test-get-priority-recommendations-scorin] ---

# --- 27B-decomposed from roadmap [2026-10-23]: Test `get_priority_statistics` aggregation logic — `billwatch-backend/app/routers/priority (review + tweak) [feat:billwatch-20261023-test-get-priority-statistics-aggregation] ---

# --- 27B-decomposed from roadmap [2026-10-23]: Test `get_saved_search` retrieval logic — `billwatch-backend/app/routers/saved_searches.py (review + tweak) [feat:billwatch-20261023-test-get-saved-search-retrieval-logic-bi] ---

# --- 27B-decomposed from roadmap [2026-10-23]: Test `refresh_legislator_finance` endpoint — `billwatch-backend/app/routers/finance.py:271 (review + tweak) [feat:billwatch-20261023-test-refresh-legislator-finance-endpoint] ---

# --- 27B-decomposed from roadmap [2026-10-23]: Test `get_legislator_voting_record` endpoint — `billwatch-backend/app/routers/legislator_s (review + tweak) [feat:billwatch-20261023-test-get-legislator-voting-record-endpoi] ---

# --- 27B-decomposed from roadmap [2026-10-23]: Test `create_checkout` and `create_portal` billing endpoints — `billwatch-backend/app/rout (review + tweak) [feat:billwatch-20261023-test-create-checkout-and-create-portal-b] ---

# --- 27B-decomposed from roadmap [2026-10-24]: Test `get_feature_count` logic — `billwatch-backend/app/schemas/mobile_feature_map.py:72`  (review + tweak) [feat:billwatch-20261024-test-get-feature-count-logic-billwatch-b] ---

# --- 27B-decomposed from roadmap [2026-10-24]: Test `get_feedback_types` endpoint — `billwatch-backend/app/routers/feedback.py:116` is a  (review + tweak) [feat:billwatch-20261024-test-get-feedback-types-endpoint-billwat] ---

# --- 27B-decomposed from roadmap [2026-10-24]: Test `stripe_webhook` signature verification and event handling — `billwatch-backend/app/r (review + tweak) [feat:billwatch-20261024-test-stripe-webhook-signature-verificati] ---

# --- 27B-decomposed from roadmap [2026-10-24]: Test `verify_password` hash validation logic — `billwatch-backend/app/routers/auth.py:45`  (review + tweak) [feat:billwatch-20261024-test-verify-password-hash-validation-log] ---

# --- 27B-decomposed from roadmap [2026-10-24]: Test `get_me` endpoint response contract — `billwatch-backend/app/routers/auth.py:291` is  (review + tweak) [feat:billwatch-20261024-test-get-me-endpoint-response-contract-b] ---

# --- 27B-decomposed from roadmap [2026-10-24]: Test `login_history` endpoint — `billwatch-backend/app/routers/auth.py:304` is a public fu (review + tweak) [feat:billwatch-20261024-test-login-history-endpoint-billwatch-ba] ---

# --- 27B-decomposed from roadmap [2026-10-24]: Test `update_notification_prefs` endpoint — `billwatch-backend/app/routers/auth.py:318` is (review + tweak) [feat:billwatch-20261024-test-update-notification-prefs-endpoint-] ---

# --- 27B-decomposed from roadmap [2026-10-24]: Test `update_user_address` endpoint — `billwatch-backend/app/routers/auth.py:339` is a pub (review + tweak) [feat:billwatch-20261024-test-update-user-address-endpoint-billwa] ---

# --- 27B-decomposed from roadmap [2026-10-24]: Implement actual filtering logic in AdvancedFilterService.filter_bills — `billwatch-backen (review + tweak) [feat:billwatch-20261024-implement-actual-filtering-logic-in-adva] ---

# --- 27B-decomposed from roadmap [2026-10-24]: Test `register_device_token` endpoint — `billwatch-backend/app/routers/auth.py:378` is a p (review + tweak) [feat:billwatch-20261024-test-register-device-token-endpoint-bill] ---

# --- 27B-decomposed from roadmap [2026-10-24]: Test `forgot_password` endpoint — `billwatch-backend/app/routers/auth.py:421` is a public  (review + tweak) [feat:billwatch-20261024-test-forgot-password-endpoint-billwatch-] ---

# --- 27B-decomposed from roadmap [2026-10-24]: Test `get_user_preferences` endpoint — `billwatch-backend/app/routers/ranking.py:58` is a  (review + tweak) [feat:billwatch-20261024-test-get-user-preferences-endpoint-billw] ---

# --- 27B-decomposed from roadmap [2026-10-24]: Test `update_user_preferences` persistence — `billwatch-backend/app/routers/ranking.py:71` (review + tweak) [feat:billwatch-20261024-test-update-user-preferences-persistence] ---

# --- 27B-decomposed from roadmap [2026-10-24]: Test `get_ranked_bills` ranking logic — `billwatch-backend/app/routers/ranking.py:109` is  (review + tweak) [feat:billwatch-20261024-test-get-ranked-bills-ranking-logic-bill] ---

# --- 27B-decomposed from roadmap [2026-10-24]: Test `upvote_bill` persistence and response — `billwatch-backend/app/routers/ranking.py:21 (review + tweak) [feat:billwatch-20261024-test-upvote-bill-persistence-and-respons] ---

# --- 27B-decomposed from roadmap [2026-10-25]: Add loading and error states to Admin.vue data fetching — `billwatch-web/src/pages/Admin.v (review + tweak) [feat:billwatch-20261025-add-loading-and-error-states-to-admin-vu] ---

# --- 27B-decomposed from roadmap [2026-10-25]: Add loading and error states to LegislatorSearch results — `billwatch-web/src/components/L (review + tweak) [feat:billwatch-20261025-add-loading-and-error-states-to-legislat] ---

# --- 27B-decomposed from roadmap [2026-10-26]: Add navigation to search results in SearchPage — `billwatch-web/src/pages/SearchPage.vue:1 (review + tweak) [feat:billwatch-20261026-add-navigation-to-search-results-in-sear] ---

# --- 27B-decomposed from roadmap [2026-10-26]: Implement View Voting Record action in LegislatorSearch — `billwatch-web/src/components/Le (review + tweak) [feat:billwatch-20261026-implement-view-voting-record-action-in-l] ---

# --- 27B-decomposed from roadmap [2026-10-26]: Test `list_committees` endpoint — `billwatch-backend/app/routers/committees.py:32` is a pu (review + tweak) [feat:billwatch-20261026-test-list-committees-endpoint-billwatch-] ---

# --- 27B-decomposed from roadmap [2026-10-26]: Test `get_committee` endpoint — `billwatch-backend/app/routers/committees.py:52` is a publ (review + tweak) [feat:billwatch-20261026-test-get-committee-endpoint-billwatch-ba] ---

# --- 27B-decomposed from roadmap [2026-10-26]: Test `search_topics` endpoint — `billwatch-backend/app/routers/search.py:47` is a public f (review + tweak) [feat:billwatch-20261026-test-search-topics-endpoint-billwatch-ba] ---

# --- 27B-decomposed from roadmap [2026-10-27]: Test `list_users` admin endpoint — `billwatch-backend/app/routers/admin.py:20` is a public (review + tweak) [feat:billwatch-20261027-test-list-users-admin-endpoint-billwatch] ---

# --- 27B-decomposed from roadmap [2026-10-27]: Make downvote_bill persist state or return 501 like upvote — `billwatch-backend/app/router (review + tweak) [feat:billwatch-20261027-make-downvote-bill-persist-state-or-retu] ---

# --- 27B-decomposed from roadmap [2026-10-27]: Replace blocking alert() with accessible inline error in AlertsView — `billwatch-web/src/v (review + tweak) [feat:billwatch-20261027-replace-blocking-alert-with-accessible-i] ---

# --- 27B-decomposed from roadmap [2026-10-27]: Make career event cards keyboard accessible in LegislatorCareerHistoryPage — `billwatch-we (review + tweak) [feat:billwatch-20261027-make-career-event-cards-keyboard-accessi] ---

# --- 27B-decomposed from roadmap [2026-10-27]: Replace blocking alert() with accessible inline error in BillChatPanel — `billwatch-web/sr (review + tweak) [feat:billwatch-20261027-replace-blocking-alert-with-accessible-i] ---

# --- 27B-decomposed from roadmap [2026-10-27]: Test `unban_user` admin endpoint — `billwatch-backend/app/routers/admin.py:71` is a public (review + tweak) [feat:billwatch-20261027-test-unban-user-admin-endpoint-billwatch] ---

# --- 27B-decomposed from roadmap [2026-10-27]: check_alerts_for_bill loads all active alerts into memory and iterates in Python — `billwa (review + tweak) [feat:billwatch-20261027-check-alerts-for-bill-loads-all-active-a] ---

# --- 27B-decomposed from roadmap [2026-10-27]: Test `get_system_statistics` aggregation logic — `billwatch-backend/app/routers/admin.py:1 (review + tweak) [feat:billwatch-20261027-test-get-system-statistics-aggregation-l] ---

# --- 27B-decomposed from roadmap [2026-10-27]: Test `find_similar_bills` similarity logic — `billwatch-backend/app/core/congress.py:138`  (review + tweak) [feat:billwatch-20261027-test-find-similar-bills-similarity-logic] ---

# --- 27B-decomposed from roadmap [2026-10-27]: Test `get_mobile_gaps` admin endpoint response — `billwatch-backend/app/routers/admin.py:1 (review + tweak) [feat:billwatch-20261027-test-get-mobile-gaps-admin-endpoint-resp] ---

# --- 27B-decomposed from roadmap [2026-10-27]: Test `post_bill_message` chat endpoint — `billwatch-backend/app/routers/bill_chat.py:31` i (review + tweak) [feat:billwatch-20261027-test-post-bill-message-chat-endpoint-bil] ---

# --- 27B-decomposed from roadmap [2026-10-27]: Test `get_current_user_or_404` dependency — `billwatch-backend/app/routers/users.py:34` is (review + tweak) [feat:billwatch-20261027-test-get-current-user-or-404-dependency-] ---

# --- 27B-decomposed from roadmap [2026-10-27]: Test `get_followed_bills` endpoint — `billwatch-backend/app/routers/users.py:67` is a publ (review + tweak) [feat:billwatch-20261027-test-get-followed-bills-endpoint-billwat] ---

# --- 27B-decomposed from roadmap [2026-10-27]: Test `follow_bill` endpoint — `billwatch-backend/app/routers/users.py:93` is a public func (review + tweak) [feat:billwatch-20261027-test-follow-bill-endpoint-billwatch-back] ---

# --- 27B-decomposed from roadmap [2026-10-27]: Test `unfollow_topic` endpoint — `billwatch-backend/app/routers/users.py:222` is a public  (review + tweak) [feat:billwatch-20261027-test-unfollow-topic-endpoint-billwatch-b] ---

# --- 27B-decomposed from roadmap [2026-10-27]: Test `unfollow_legislator` endpoint — `billwatch-backend/app/routers/users.py:294` is a pu (review + tweak) [feat:billwatch-20261027-test-unfollow-legislator-endpoint-billwa] ---

# --- 27B-decomposed from roadmap [2026-10-27]: Test `get_all_sync_status` and `get_bills_sync_status` endpoints — `billwatch-backend/app/ (review + tweak) [feat:billwatch-20261027-test-get-all-sync-status-and-get-bills-s] ---

# --- 27B-decomposed from roadmap [2026-10-27]: Test `get_followed_committees`, `follow_committee`, and `unfollow_committee` endpoints — ` (review + tweak) [feat:billwatch-20261027-test-get-followed-committees-follow-comm] ---

# --- 27B-decomposed from roadmap [2026-10-27]: Test `get_campaign_finance` endpoint — `billwatch-backend/app/routers/legislator_finance.p (review + tweak) [feat:billwatch-20261027-test-get-campaign-finance-endpoint-billw] ---

# --- 27B-decomposed from roadmap [2026-10-27]: Test `get_financial_disclosures` endpoint — `billwatch-backend/app/routers/legislator_fina (review + tweak) [feat:billwatch-20261027-test-get-financial-disclosures-endpoint-] ---

# --- 27B-decomposed from roadmap [2026-10-27]: Test `get_voting_summary` endpoint — `billwatch-backend/app/routers/legislator_finance.py: (review + tweak) [feat:billwatch-20261027-test-get-voting-summary-endpoint-billwat] ---

# --- 27B-decomposed from roadmap [2026-10-28]: Use SQL aggregation instead of loading all votes to count positions — `billwatch-backend/a (review + tweak) [feat:billwatch-20261028-use-sql-aggregation-instead-of-loading-a] ---

# --- 27B-decomposed from roadmap [2026-10-28]: Describe bill death in status change summary — `billwatch-backend/app/services/status_chan (review + tweak) [feat:billwatch-20261028-describe-bill-death-in-status-change-sum] ---

# --- 27B-decomposed from roadmap [2026-10-28]: Daily budget cap for LLM bill summaries — add an int setting `summary_daily_call_cap` (def (review + tweak) [feat:billwatch-20261028-daily-budget-cap-for-llm-bill-summaries-] ---

# --- 27B-decomposed from roadmap [2026-10-28]: Summary coverage metric for recent bills — add `get_summary_coverage(db, days=90)` to bill (review + tweak) [feat:billwatch-20261028-summary-coverage-metric-for-recent-bills] ---

# --- 27B-decomposed from roadmap [2026-10-28]: OpenAI-compatible mode for the LLM client — in billwatch-backend/app/services/llm_service. (review + tweak) [feat:billwatch-20261028-openai-compatible-mode-for-the-llm-clien] ---

# --- 27B-decomposed from roadmap [2026-10-28]: Retry-After backoff for Congress.gov 429 responses — in CongressAPIClient._request in bill (review + tweak) [feat:billwatch-20261028-retry-after-backoff-for-congress-gov-429] ---

# --- 27B-decomposed from roadmap [2026-10-28]: Public robots.txt and sitemap.xml for SEO — add billwatch-web/public/robots.txt (allow all (review + tweak) [feat:billwatch-20261028-public-robots-txt-and-sitemap-xml-for-se] ---

# --- 27B-decomposed from roadmap [2026-10-28]: Weekly KPI snapshot endpoint (server side, no PII) — add `get_weekly_kpi_snapshot(days=7)` (review + tweak) [feat:billwatch-20261028-weekly-kpi-snapshot-endpoint-server-side] ---

# --- 27B-decomposed from roadmap [2026-10-28]: New-Congress rollover for the legislator sync service — in billwatch-backend/app/services/ (review + tweak) [feat:billwatch-20261028-new-congress-rollover-for-the-legislator] ---

# --- 27B-decomposed from roadmap [2026-10-28]: Admin legislator-sync endpoint defaults to the current Congress — in billwatch-backend/app (review + tweak) [feat:billwatch-20261028-admin-legislator-sync-endpoint-defaults-] ---

# --- 27B-decomposed from roadmap [2026-10-28]: Replace the fake sessions on the Security Settings page with real login history — billwatc (review + tweak) [feat:billwatch-20261028-replace-the-fake-sessions-on-the-securit] ---

# --- 27B-decomposed from roadmap [2026-10-28]: Error state for the legislators list — billwatch-web/src/stores/legislators.ts `searchLegi (review + tweak) [feat:billwatch-20261028-error-state-for-the-legislators-list-bil] ---

# --- 27B-decomposed from roadmap [2026-10-28]: Test the Priority Dashboard page — billwatch-web/src/pages/PriorityDashboardPage.vue (rout (review + tweak) [feat:billwatch-20261028-test-the-priority-dashboard-page-billwat] ---

# --- 27B-decomposed from roadmap [2026-10-28]: Test the Bill Ranking page — billwatch-web/src/pages/BillRankingPage.vue (routed, 242 line (review + tweak) [feat:billwatch-20261028-test-the-bill-ranking-page-billwatch-web] ---

# --- 27B-decomposed from roadmap [2026-10-28]: Test the Privacy and Terms pages — billwatch-web/src/pages/PrivacyPage.vue and billwatch-w (review + tweak) [feat:billwatch-20261028-test-the-privacy-and-terms-pages-billwat] ---

# --- 27B-decomposed from roadmap [2026-10-28]: Open Graph tags on the bill detail page — add a small composable billwatch-web/src/composa (review + tweak) [feat:billwatch-20261028-open-graph-tags-on-the-bill-detail-page-] ---

# --- 27B-decomposed from roadmap [2026-10-29]: Congress rollover guard test across ingestion defaults — add billwatch-backend/tests/test_ (review + tweak) [feat:billwatch-20261029-congress-rollover-guard-test-across-inge] ---

# --- 27B-decomposed from roadmap [2026-10-29]: Test `fetch_with_retry` retry logic — `billwatch-backend/app/core/congress.py:255` is a pu (review + tweak) [feat:billwatch-20261029-test-fetch-with-retry-retry-logic-billwa] ---

# --- 27B-decomposed from roadmap [2026-10-29]: Test `build_sitemap_xml` generation — `billwatch-backend/app/routers/bills.py:226` is a pu (review + tweak) [feat:billwatch-20261029-test-build-sitemap-xml-generation-billwa] ---

# --- 27B-decomposed from roadmap [2026-10-29]: Test `downvote_bill` endpoint — `billwatch-backend/app/routers/ranking.py:234` is a public (review + tweak) [feat:billwatch-20261029-test-downvote-bill-endpoint-billwatch-ba] ---

# --- 27B-decomposed from roadmap [2026-10-30]: Test `stripe_webhook` endpoint — `billwatch-backend/app/routers/billing.py:84` is a public (review + tweak) [feat:billwatch-20261030-test-stripe-webhook-endpoint-billwatch-b] ---

# --- 27B-decomposed from roadmap [2026-10-30]: Test `validate_user_id` dependency — `billwatch-backend/app/core/dependencies.py:57` is a  (review + tweak) [feat:billwatch-20261030-test-validate-user-id-dependency-billwat] ---

# --- 27B-decomposed from roadmap [2026-10-30]: Test `validate_api_key` dependency — `billwatch-backend/app/core/dependencies.py:73` is a  (review + tweak) [feat:billwatch-20261030-test-validate-api-key-dependency-billwat] ---

# --- deterministic work supply 2026-10-30 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- 27B-decomposed from roadmap [2026-10-30]: Test `status_endpoint` health check — `billwatch-backend/app/main.py:181` is a public func (review + tweak) [feat:billwatch-20261030-test-status-endpoint-health-check-billwa] ---

# --- 27B-decomposed from roadmap [2026-10-31]: Implement filter_legislators with real DB query — `billwatch-backend/app/services/advanced (review + tweak) [feat:billwatch-20261031-implement-filter-legislators-with-real-d] ---

# --- 27B-decomposed from roadmap [2026-10-31]: Implement full_text_search with real query — `billwatch-backend/app/services/advanced_sear (review + tweak) [feat:billwatch-20261031-implement-full-text-search-with-real-que] ---

# --- 27B-decomposed from roadmap [2026-10-31]: Test `get_summary_coverage_endpoint` — `billwatch-backend/app/routers/sync_status.py:56` i (review + tweak) [feat:billwatch-20261031-test-get-summary-coverage-endpoint-billw] ---

# --- 27B-decomposed from roadmap [2026-10-31]: Test `get_source_sync_status` endpoint — `billwatch-backend/app/routers/sync_status.py:86` (review + tweak) [feat:billwatch-20261031-test-get-source-sync-status-endpoint-bil] ---

# --- 27B-decomposed from roadmap [2026-10-31]: Test `require_auth` dependency — `billwatch-backend/app/routers/sync_status.py:63` is a pu (review + tweak) [feat:billwatch-20261031-test-require-auth-dependency-billwatch-b] ---

# --- 27B-decomposed from roadmap [2026-10-31]: Test `recommend_bills` endpoint — `billwatch-backend/app/routers/recommendations.py:20` is (review + tweak) [feat:billwatch-20261031-test-recommend-bills-endpoint-billwatch-] ---

# --- 27B-decomposed from roadmap [2026-10-31]: Test `find_representatives` civic endpoint — `billwatch-backend/app/routers/civic.py:33` i (review + tweak) [feat:billwatch-20261031-test-find-representatives-civic-endpoint] ---

# --- 27B-decomposed from roadmap [2026-10-31]: Test `get_representatives` civic endpoint — `billwatch-backend/app/routers/civic.py:95` is (review + tweak) [feat:billwatch-20261031-test-get-representatives-civic-endpoint-] ---

# --- 27B-decomposed from roadmap [2026-10-31]: Test `search_divisions` civic endpoint — `billwatch-backend/app/routers/civic.py:133` is a (review + tweak) [feat:billwatch-20261031-test-search-divisions-civic-endpoint-bil] ---

# --- 27B-decomposed from roadmap [2026-10-31]: Test `trending_bill_to_response` endpoint — `billwatch-backend/app/routers/analytics.py:28 (review + tweak) [feat:billwatch-20261031-test-trending-bill-to-response-endpoint-] ---

# --- 27B-decomposed from roadmap [2026-10-31]: Test `get_popular_bills` endpoint — `billwatch-backend/app/routers/analytics.py:69` is a p (review + tweak) [feat:billwatch-20261031-test-get-popular-bills-endpoint-billwatc] ---

# --- 27B-decomposed from roadmap [2026-10-31]: Test `get_bill_summary` analytics endpoint — `billwatch-backend/app/routers/analytics.py:1 (review + tweak) [feat:billwatch-20261031-test-get-bill-summary-analytics-endpoint] ---

# --- 27B-decomposed from roadmap [2026-10-31]: Test `list_user_alerts` endpoint — `billwatch-backend/app/routers/analytics.py:210` is a p (review + tweak) [feat:billwatch-20261031-test-list-user-alerts-endpoint-billwatch] ---

# --- 27B-decomposed from roadmap [2026-10-31]: Test `create_bill_alert` endpoint — `billwatch-backend/app/routers/analytics.py:241` is a  (review + tweak) [feat:billwatch-20261031-test-create-bill-alert-endpoint-billwatc] ---

# --- 27B-decomposed from roadmap [2026-10-31]: Test `update_bill_alert` endpoint — `billwatch-backend/app/routers/analytics.py:270` is a  (review + tweak) [feat:billwatch-20261031-test-update-bill-alert-endpoint-billwatc] ---

# --- 27B-decomposed from roadmap [2026-10-31]: Test `track_page_view` analytics endpoint — `billwatch-backend/app/routers/analytics.py:33 (review + tweak) [feat:billwatch-20261031-test-track-page-view-analytics-endpoint-] ---

# --- 27B-decomposed from roadmap [2026-10-31]: Test `get_kpi_weekly` endpoint — `billwatch-backend/app/routers/analytics.py:467` is a pub (review + tweak) [feat:billwatch-20261031-test-get-kpi-weekly-endpoint-billwatch-b] ---

# --- 27B-decomposed from roadmap [2026-10-31]: Test `trigger_summary_batch` endpoint — `billwatch-backend/app/routers/analytics.py:480` i (review + tweak) [feat:billwatch-20261031-test-trigger-summary-batch-endpoint-bill] ---

# --- deterministic work supply 2026-10-31 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- 27B-decomposed from roadmap [2026-10-31]: Test `get_notifications` endpoint — `billwatch-backend/app/routers/notifications.py:25` is (review + tweak) [feat:billwatch-20261031-test-get-notifications-endpoint-billwatc] ---

# --- 27B-decomposed from roadmap [2026-10-31]: Test `update_notification` endpoint — `billwatch-backend/app/routers/notifications.py:79`  (review + tweak) [feat:billwatch-20261031-test-update-notification-endpoint-billwa] ---

# --- 27B-decomposed from roadmap [2026-10-31]: Test `mark_all_read` endpoint — `billwatch-backend/app/routers/notifications.py:120` is a  (review + tweak) [feat:billwatch-20261031-test-mark-all-read-endpoint-billwatch-ba] ---

# --- 27B-decomposed from roadmap [2026-10-31]: Test `preview_digest` endpoint — `billwatch-backend/app/routers/digest.py:88` is a public  (review + tweak) [feat:billwatch-20261031-test-preview-digest-endpoint-billwatch-b] ---

# --- 27B-decomposed from roadmap [2026-10-31]: Test `get_career_history` endpoint — `billwatch-backend/app/routers/career_history.py:70`  (review + tweak) [feat:billwatch-20261031-test-get-career-history-endpoint-billwat] ---

# --- 27B-decomposed from roadmap [2026-10-31]: Test `get_legislator_votes` endpoint — `billwatch-backend/app/routers/votes.py:78` is a pu (review + tweak) [feat:billwatch-20261031-test-get-legislator-votes-endpoint-billw] ---

# --- 27B-decomposed from roadmap [2026-11-01]: Fix NameError in RequestIdMiddleware when call_next raises — `billwatch-backend/app/core/r (review + tweak) [feat:billwatch-20261101-fix-nameerror-in-requestidmiddleware-whe] ---

# --- 27B-decomposed from roadmap [2026-11-01]: Per-hour API call budget counter (pure module) — add `billwatch-backend/app/services/api_b (review + tweak) [feat:billwatch-20261101-per-hour-api-call-budget-counter-pure-mo] ---

# --- 27B-decomposed from roadmap [2026-11-01]: Count and enforce the OpenFEC per-hour budget in FECAPIClient — in `billwatch-backend/app/ (review + tweak) [feat:billwatch-20261101-count-and-enforce-the-openfec-per-hour-b] ---

# --- 27B-decomposed from roadmap [2026-11-01]: Count Census geocoder calls against a per-hour counter — in `billwatch-backend/app/service (review + tweak) [feat:billwatch-20261101-count-census-geocoder-calls-against-a-pe] ---

# --- 27B-decomposed from roadmap [2026-11-01]: Surface API budget usage next to sync status — add `GET /api/sync/budgets` to `billwatch-b (review + tweak) [feat:billwatch-20261101-surface-api-budget-usage-next-to-sync-st] ---

# --- 27B-decomposed from roadmap [2026-11-01]: Cache Census geocoder results with a TTL — `POST/GET /api/civic/representatives` geocodes  (review + tweak) [feat:billwatch-20261101-cache-census-geocoder-results-with-a-ttl] ---

# --- 27B-decomposed from roadmap [2026-11-01]: Retry transient Census geocoder failures — `CensusGeocoderClient.geocode_address` in `bill (review + tweak) [feat:billwatch-20261101-retry-transient-census-geocoder-failures] ---

# --- 27B-decomposed from roadmap [2026-11-01]: Test CensusGeocoderClient.geocode_address end to end with mocked httpx — `billwatch-backen (review + tweak) [feat:billwatch-20261101-test-censusgeocoderclient-geocode-addres] ---

# --- 27B-decomposed from roadmap [2026-11-01]: Make `GET /api/sync/{source}` return the same freshness fields as `GET /api/sync` — `get_s (review + tweak) [feat:billwatch-20261101-make-get-api-sync-source-return-the-same] ---

# --- 27B-decomposed from roadmap [2026-11-01]: OpenAPI contract test for the sync routes — add a NEW file `billwatch-backend/tests/test_o (review + tweak) [feat:billwatch-20261101-openapi-contract-test-for-the-sync-route] ---

# --- 27B-decomposed from roadmap [2026-11-01]: Web service + types for two-legislator vote comparison — the backend `GET /api/votes/compa (review + tweak) [feat:billwatch-20261101-web-service-types-for-two-legislator-vot] ---

# --- 27B-decomposed from roadmap [2026-11-01]: Legislator vote comparison page — add `billwatch-web/src/pages/LegislatorComparePage.vue`  (review + tweak) [feat:billwatch-20261101-legislator-vote-comparison-page-add-bill] ---

# --- 27B-decomposed from roadmap [2026-11-01]: Functional tests for TrendingBillsPage — `billwatch-web/src/pages/TrendingBillsPage.vue` ( (review + tweak) [feat:billwatch-20261101-functional-tests-for-trendingbillspage-b] ---

# --- 27B-decomposed from roadmap [2026-11-01]: Tests for LegislatorsView — `billwatch-web/src/views/LegislatorsView.vue` (routed at /legi (review + tweak) [feat:billwatch-20261101-tests-for-legislatorsview-billwatch-web-] ---

# --- 27B-decomposed from roadmap [2026-11-01]: Test `get_sitemap` — `billwatch-backend/app/routers/bills.py:239` is a public function ref (review + tweak) [feat:billwatch-20261101-test-get-sitemap-billwatch-backend-app-r] ---

# --- 27B-decomposed from roadmap [2026-11-01]: Test `get_voting_statistics` endpoint — `billwatch-backend/app/routers/votes.py:326` is a  (review + tweak) [feat:billwatch-20261101-test-get-voting-statistics-endpoint-bill] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Test `get_endpoint_docs` API documentation endpoint — `billwatch-backend/app/routers/api_d (review + tweak) [feat:billwatch-20261102-test-get-endpoint-docs-api-documentation] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Test `get_topics` endpoint — `billwatch-backend/app/routers/topics.py:44` is a public func (review + tweak) [feat:billwatch-20261102-test-get-topics-endpoint-billwatch-backe] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Test `get_sync_status` admin endpoint — `billwatch-backend/app/routers/admin.py:147` is a  (review + tweak) [feat:billwatch-20261102-test-get-sync-status-admin-endpoint-bill] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Test `legislator_to_response` serialization — `billwatch-backend/app/routers/legislators.p (review + tweak) [feat:billwatch-20261102-test-legislator-to-response-serializatio] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Enforce `summary_daily_call_cap` with a real daily LLM call budget — `Settings.summary_dai (review + tweak) [feat:billwatch-20261102-enforce-summary-daily-call-cap-with-a-re] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Apply the daily LLM budget to the Claude summary path and stop the scheduler batch when it (review + tweak) [feat:billwatch-20261102-apply-the-daily-llm-budget-to-the-claude] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Stop `BillSummaryService` blocking the event loop on the Anthropic call — `_generate_summa (review + tweak) [feat:billwatch-20261102-stop-billsummaryservice-blocking-the-eve] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Bound the tone-filter LLM work in GET /api/bills/{bill_id}/chat — `get_bill_chat` in `bill (review + tweak) [feat:billwatch-20261102-bound-the-tone-filter-llm-work-in-get-ap] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Bound and narrow GET /api/bills/{bill_id}/similar — `get_similar_bills` in `billwatch-back (review + tweak) [feat:billwatch-20261102-bound-and-narrow-get-api-bills-bill-id-s] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Remove the per-vote N+1 in GET /api/legislators/{bioguide_id}/missed-votes — `get_missed_v (review + tweak) [feat:billwatch-20261102-remove-the-per-vote-n-1-in-get-api-legis] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Make sitemap `<loc>` URLs point at the public web page, not the JSON API — `build_sitemap_ (review + tweak) [feat:billwatch-20261102-make-sitemap-loc-urls-point-at-the-publi] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Replace the stray `print` and duplicated SSL setup in the SMTP send path — `billwatch-back (review + tweak) [feat:billwatch-20261102-replace-the-stray-print-and-duplicated-s] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Add baseline security response headers to the API — nothing in `billwatch-backend/app` set (review + tweak) [feat:billwatch-20261102-add-baseline-security-response-headers-t] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Compress large API responses with GZipMiddleware — `billwatch-backend/app/main.py` registe (review + tweak) [feat:billwatch-20261102-compress-large-api-responses-with-gzipmi] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Make `tests/test_finance_helpers.py` test the real router helper, then reuse the shared pe (review + tweak) [feat:billwatch-20261102-make-tests-test-finance-helpers-py-test-] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Add a naive-UTC `utcnow_naive()` helper for the DB-column timestamps — `datetime.utcnow()` (review + tweak) [feat:billwatch-20261102-add-a-naive-utc-utcnow-naive-helper-for-] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Migrate `bill_analytics_service.py` and `trending_service.py` off `datetime.utcnow()` — in (review + tweak) [feat:billwatch-20261102-migrate-bill-analytics-service-py-and-tr] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Migrate `bill_ranking_service.py`, `alert_service.py` and `security_audit_service.py` off  (review + tweak) [feat:billwatch-20261102-migrate-bill-ranking-service-py-alert-se] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Give GET /api/legislators/{bioguide_id}/sponsored-bills a typed schema and stable ordering (review + tweak) [feat:billwatch-20261102-give-get-api-legislators-bioguide-id-spo] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Delete the orphaned `TrendingBillsView.vue` — `billwatch-web/src/views/TrendingBillsView.v (review + tweak) [feat:billwatch-20261102-delete-the-orphaned-trendingbillsview-vu] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Expose a load-error state from the bills store — every action in `billwatch-web/src/stores (review + tweak) [feat:billwatch-20261102-expose-a-load-error-state-from-the-bills] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Show an error/not-found state on the bill detail page instead of a blank screen — `billwat (review + tweak) [feat:billwatch-20261102-show-an-error-not-found-state-on-the-bil] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Show a failed-search error with retry on the bills list — `billwatch-web/src/views/BillsVi (review + tweak) [feat:billwatch-20261102-show-a-failed-search-error-with-retry-on] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Show a failed-load error with retry on the Following page — `billwatch-web/src/views/Follo (review + tweak) [feat:billwatch-20261102-show-a-failed-load-error-with-retry-on-t] ---

# --- 27B-decomposed from roadmap [2026-11-04]: Make `UnifiedBillCard` keyboard accessible — `billwatch-web/src/components/UnifiedBillCard (review + tweak) [feat:billwatch-20261104-make-unifiedbillcard-keyboard-accessible] ---

# --- 27B-decomposed from roadmap [2026-11-04]: Add an accessible `ConfirmDialog` component and use it for deleting saved searches — `bill (review + tweak) [feat:billwatch-20261104-add-an-accessible-confirmdialog-componen] ---

# --- 27B-decomposed from roadmap [2026-11-04]: Use `ConfirmDialog` for deleting alerts and the account — `billwatch-web/src/views/AlertsV (review + tweak) [feat:billwatch-20261104-use-confirmdialog-for-deleting-alerts-an] ---

# --- 27B-decomposed from roadmap [2026-11-04]: Make bill and legislator search honor the LIKE escaping they already apply — `search_bills (review + tweak) [feat:billwatch-20261104-make-bill-and-legislator-search-honor-th] ---

# --- 27B-decomposed from roadmap [2026-11-04]: Give GET /api/bills a stable, NULLS-LAST sort — `search_bills` in `billwatch-backend/app/r (review + tweak) [feat:billwatch-20261104-give-get-api-bills-a-stable-nulls-last-s] ---

# --- 27B-decomposed from roadmap [2026-11-04]: Add an id tiebreak to the legislator list sort — `search_legislators` in `billwatch-backen (review + tweak) [feat:billwatch-20261104-add-an-id-tiebreak-to-the-legislator-lis] ---

# --- 27B-decomposed from roadmap [2026-11-04]: Add id tiebreaks to the other OFFSET-paginated lists — `billwatch-backend/app/routers/noti (review + tweak) [feat:billwatch-20261104-add-id-tiebreaks-to-the-other-offset-pag] ---

# --- 27B-decomposed from roadmap [2026-11-04]: Bound the saved-search payload and cap saved searches per user — `SavedSearchCreate`/`Save (review + tweak) [feat:billwatch-20261104-bound-the-saved-search-payload-and-cap-s] ---

# --- 27B-decomposed from roadmap [2026-11-04]: Fix `format_currency_short` unit rollover and negative small amounts — `format_currency_sh (review + tweak) [feat:billwatch-20261104-fix-format-currency-short-unit-rollover-] ---

# --- 27B-decomposed from roadmap [2026-11-04]: Make `parse_amount` reject NaN/Infinity — `parse_amount` in `billwatch-backend/app/utils/f (review + tweak) [feat:billwatch-20261104-make-parse-amount-reject-nan-infinity-pa] ---

# --- 27B-decomposed from roadmap [2026-11-04]: Fix the legislator finance currency formatting and remove its duplicate — `billwatch-web/s (review + tweak) [feat:billwatch-20261104-fix-the-legislator-finance-currency-form] ---

# --- 27B-decomposed from roadmap [2026-11-04]: Add a catch-all 404 route and view — `billwatch-web/src/router/index.ts` defines every rou (review + tweak) [feat:billwatch-20261104-add-a-catch-all-404-route-and-view-billw] ---

# --- 27B-decomposed from roadmap [2026-11-04]: Set a per-route document title — nothing in `billwatch-web/src` sets `document.title` exce (review + tweak) [feat:billwatch-20261104-set-a-per-route-document-title-nothing-i] ---

# --- 27B-decomposed from roadmap [2026-11-04]: Ignore stale responses in the bills store — `searchBills` and `fetchBillDetail` in `billwa (review + tweak) [feat:billwatch-20261104-ignore-stale-responses-in-the-bills-stor] ---

# --- 27B-decomposed from roadmap [2026-11-04]: Give the shared axios client a request timeout and a readable timeout message — `api = axi (review + tweak) [feat:billwatch-20261104-give-the-shared-axios-client-a-request-t] ---

# --- 27B-decomposed from roadmap [2026-11-04]: Do not fire 1-character searches from the bills list — `BillsView.vue` (`billwatch-web/src (review + tweak) [feat:billwatch-20261104-do-not-fire-1-character-searches-from-th] ---

# --- 27B-decomposed from roadmap [2026-11-06]: Test `fetch_with_retry` transient failure handling — `billwatch-backend/app/core/congress. (review + tweak) [feat:billwatch-20261106-test-fetch-with-retry-transient-failure-] ---

# --- 27B-decomposed from roadmap [2026-11-06]: Fix the web alert toggle calling a verb the backend does not serve — `toggleAlert` in `bil (review + tweak) [feat:billwatch-20261106-fix-the-web-alert-toggle-calling-a-verb-] ---

# --- 27B-decomposed from roadmap [2026-11-06]: Stop the legislator detail page showing the PREVIOUS legislator's finance, scorecard, comm (review + tweak) [feat:billwatch-20261106-stop-the-legislator-detail-page-showing-] ---

# --- 27B-decomposed from roadmap [2026-11-06]: Escape user and third-party text in the digest email HTML — `DigestService.render_html` in (review + tweak) [feat:billwatch-20261106-escape-user-and-third-party-text-in-the-] ---

# --- 27B-decomposed from roadmap [2026-11-06]: Escape user-supplied text in the feedback and status-change alert emails — `EmailService.s (review + tweak) [feat:billwatch-20261106-escape-user-supplied-text-in-the-feedbac] ---

# --- 27B-decomposed from roadmap [2026-11-06]: Let a saved search's filters actually be cleared via PATCH — `SavedSearchService.update` i (review + tweak) [feat:billwatch-20261106-let-a-saved-search-s-filters-actually-be] ---

# --- 27B-decomposed from roadmap [2026-11-06]: Make `POST /api/bills/{id}/favorite` return 404 (not 500) for a missing bill, and `POST /a (review + tweak) [feat:billwatch-20261106-make-post-api-bills-id-favorite-return-4] ---

# --- 27B-decomposed from roadmap [2026-11-06]: Report real ingestion freshness from `GET /api/admin/sync/{source}` instead of `max(update (review + tweak) [feat:billwatch-20261106-report-real-ingestion-freshness-from-get] ---

# --- 27B-decomposed from roadmap [2026-11-06]: Reject out-of-range bill ids with 422 instead of an unhandled 500 — every `bill_id: int` p (review + tweak) [feat:billwatch-20261106-reject-out-of-range-bill-ids-with-422-in] ---

# --- 27B-decomposed from roadmap [2026-11-09]: Reject out-of-range legislator ids with 422 on the stats and career-history routes — `legi (review + tweak) [feat:billwatch-20261109-reject-out-of-range-legislator-ids-with-] ---

# --- 27B-decomposed from roadmap [2026-11-09]: Bound `cycle` and `legislator_id` on the public campaign-finance routes — `billwatch-backe (review + tweak) [feat:billwatch-20261109-bound-cycle-and-legislator-id-on-the-pub] ---

# --- 27B-decomposed from roadmap [2026-11-09]: Cap `page` on the paginated list routes (bills and legislators) — `page: int = Query(1, ge (review + tweak) [feat:billwatch-20261109-cap-page-on-the-paginated-list-routes-bi] ---

# --- 27B-decomposed from roadmap [2026-11-09]: Cap `page` on notifications and `skip` on the admin user list — `get_notifications` in `bi (review + tweak) [feat:billwatch-20261109-cap-page-on-notifications-and-skip-on-th] ---

# --- 27B-decomposed from roadmap [2026-11-09]: Remove the 40-line duplicate response builder between `get_bill` and `get_bill_by_congress (review + tweak) [feat:billwatch-20261109-remove-the-40-line-duplicate-response-bu] ---

# --- 27B-decomposed from roadmap [2026-11-09]: Test `get_legislator_scorecard` — `billwatch-backend/app/routers/legislator_stats.py:57` i (review + tweak) [feat:billwatch-20261109-test-get-legislator-scorecard-billwatch-] ---

# --- 27B-decomposed from roadmap [2026-11-10]: Test `list_committees` and `get_committee` endpoints — `billwatch-backend/app/routers/comm (review + tweak) [feat:billwatch-20261110-test-list-committees-and-get-committee-e] ---

# --- 27B-decomposed from roadmap [2026-11-10]: `_compute_summary` is only tested with an empty vote list - `billwatch-backend/app/service (review + tweak) [feat:billwatch-20261110-compute-summary-is-only-tested-with-an-e] ---

# --- 27B-decomposed from roadmap [2026-11-10]: The 100-character item limit on `BillAlertCreate`'s list fields is untested - `billwatch-b (review + tweak) [feat:billwatch-20261110-the-100-character-item-limit-on-billaler] ---

# --- 27B-decomposed from roadmap [2026-11-10]: The share-card `_fit` truncation helper is untested - `billwatch-backend/app/services/shar (review + tweak) [feat:billwatch-20261110-the-share-card-fit-truncation-helper-is-] ---

# --- 27B-decomposed from roadmap [2026-11-10]: `calculate_backoff_delay` in `app/core/congress.py` has no tests (the existing backoff tes (review + tweak) [feat:billwatch-20261110-calculate-backoff-delay-in-app-core-cong] ---

# --- 27B-decomposed from roadmap [2026-11-10]: The non-integer branches of the pagination validators are untested - `billwatch-backend/ap (review + tweak) [feat:billwatch-20261110-the-non-integer-branches-of-the-paginati] ---

# --- 27B-decomposed from roadmap [2026-11-10]: `CachingService.get` eviction of an expired entry is untested - `billwatch-backend/app/ser (review + tweak) [feat:billwatch-20261110-cachingservice-get-eviction-of-an-expire] ---

# --- 27B-decomposed from roadmap [2026-11-10]: `Legislator.display_name` formatting is untested - `billwatch-backend/app/models/legislato (review + tweak) [feat:billwatch-20261110-legislator-display-name-formatting-is-un] ---

# --- 27B-decomposed from roadmap [2026-11-11]: Test `unban_user` permission and state change — `billwatch-backend/app/routers/admin.py:75 (review + tweak) [feat:billwatch-20261111-test-unban-user-permission-and-state-cha] ---

# --- 27B-decomposed from roadmap [2026-11-11]: Test `follow_bill` and `unfollow_bill` state changes — `billwatch-backend/app/routers/user (review + tweak) [feat:billwatch-20261111-test-follow-bill-and-unfollow-bill-state] ---

# --- 27B-decomposed from roadmap [2026-11-11]: Test `follow_topic` and `unfollow_topic` state changes — `billwatch-backend/app/routers/us (review + tweak) [feat:billwatch-20261111-test-follow-topic-and-unfollow-topic-sta] ---

# --- 27B-decomposed from roadmap [2026-11-11]: Test `unfollow_committee` state change — `billwatch-backend/app/routers/users.py:350` is u (review + tweak) [feat:billwatch-20261111-test-unfollow-committee-state-change-bil] ---

# --- 27B-decomposed from roadmap [2026-11-11]: `jaccard` similarity has no test - `billwatch-backend/app/utils/relevance.py` `jaccard(a,  (review + tweak) [feat:billwatch-20261111-jaccard-similarity-has-no-test-billwatch] ---

# --- 27B-decomposed from roadmap [2026-11-11]: `RateLimitService.check_global_limit` is never called by a test - `billwatch-backend/app/s (review + tweak) [feat:billwatch-20261111-ratelimitservice-check-global-limit-is-n] ---

# --- 27B-decomposed from roadmap [2026-11-11]: `PasswordResetService.validate_reset_token` rejection branches are untested - `billwatch-b (review + tweak) [feat:billwatch-20261111-passwordresetservice-validate-reset-toke] ---

# --- 27B-decomposed from roadmap [2026-11-11]: `SearchService` status, bill-type, state and chamber filters are untested - `billwatch-bac (review + tweak) [feat:billwatch-20261111-searchservice-status-bill-type-state-and] ---

# --- 27B-decomposed from roadmap [2026-11-11]: `POST /api/auth/refresh` success path is never exercised - `billwatch-backend/app/routers/ (review + tweak) [feat:billwatch-20261111-post-api-auth-refresh-success-path-is-ne] ---

# --- 27B-decomposed from roadmap [2026-11-11]: Remove the shadowed first `normalize_address` in `geocoder.py` - `billwatch-backend/app/se (review + tweak) [feat:billwatch-20261111-remove-the-shadowed-first-normalize-addr] ---

# --- 27B-decomposed from roadmap [2026-11-11]: Delete the unreferenced `Alert` model module `app/models/alert.py` - `billwatch-backend/ap (review + tweak) [feat:billwatch-20261111-delete-the-unreferenced-alert-model-modu] ---

# --- 27B-decomposed from roadmap [2026-11-11]: Delete the unreferenced alert schema module `app/schemas/alerts.py` - `billwatch-backend/a (review + tweak) [feat:billwatch-20261111-delete-the-unreferenced-alert-schema-mod] ---

# --- 27B-decomposed from roadmap [2026-11-11]: Test `get_federal_legislators` endpoint — `billwatch-backend/app/routers/civic.py:117` is  (review + tweak) [feat:billwatch-20261111-test-get-federal-legislators-endpoint-bi] ---

# --- 27B-decomposed from roadmap [2026-11-11]: Bill timeline on the bill detail page — the bill page lists at most 10 raw actions with an (review + tweak) [feat:billwatch-20261111-bill-timeline-on-the-bill-detail-page-th] ---

# --- 27B-decomposed from roadmap [2026-11-12]: Priority dashboard: the Change Priority modal becomes reachable — `PriorityDashboardPage.v (review + tweak) [feat:billwatch-20261112-priority-dashboard-the-change-priority-m] ---

# --- 27B-decomposed from roadmap [2026-11-12]: Saved searches: accessible and easier to scan — `SavedSearchesView.vue` shows errors and l (review + tweak) [feat:billwatch-20261112-saved-searches-accessible-and-easier-to-] ---

# --- 27B-decomposed from roadmap [2026-11-12]: Legislator comparison page: selection and ordering — `LegislatorComparePage.vue` lists agr (review + tweak) [feat:billwatch-20261112-legislator-comparison-page-selection-and] ---

# --- 27B-decomposed from roadmap [2026-11-12]: Weekly Digest and page titles are reachable — the main nav links to `/digest` but the rout (review + tweak) [feat:billwatch-20261112-weekly-digest-and-page-titles-are-reacha] ---

# --- 27B-decomposed from roadmap [2026-11-13]: Backend accuracy: summary batch counting and status history — `SummaryScheduler.generate_m (review + tweak) [feat:billwatch-20261113-backend-accuracy-summary-batch-counting-] ---

# --- 27B-decomposed from roadmap [2026-11-13]: Notifications inbox: the page lists real notifications — `billwatch-web/src/views/Notifica (review + tweak) [feat:billwatch-20261113-notifications-inbox-the-page-lists-real-] ---

# --- 27B-decomposed from roadmap [2026-11-13]: Committees page: search by name and show followed only — `billwatch-web/src/pages/Committe (review + tweak) [feat:billwatch-20261113-committees-page-search-by-name-and-show-] ---

# --- 27B-decomposed from roadmap [2026-11-13]: Committee detail: members ordered by rank with a party filter — `billwatch-web/src/pages/C (review + tweak) [feat:billwatch-20261113-committee-detail-members-ordered-by-rank] ---

# --- 27B-decomposed from roadmap [2026-11-13]: Following page: sort and filter followed bills — `billwatch-web/src/views/FollowingView.vu (review + tweak) [feat:billwatch-20261113-following-page-sort-and-filter-followed-] ---

# --- 27B-decomposed from roadmap [2026-11-13]: Bill sync refreshes the sponsor of a bill it already knows — in `billwatch-backend/app/ser (review + tweak) [feat:billwatch-20261113-bill-sync-refreshes-the-sponsor-of-a-bil] ---

# --- 27B-decomposed from roadmap [2026-11-16]: Legislators list: filter by chamber, party and state — `billwatch-web/src/views/Legislator (review + tweak) [feat:billwatch-20261116-legislators-list-filter-by-chamber-party] ---

# --- 27B-decomposed from roadmap [2026-11-16]: Bills list: sort order selector — `billwatch-web/src/views/BillsView.vue` always shows bil (review + tweak) [feat:billwatch-20261116-bills-list-sort-order-selector-billwatch] ---

# --- 27B-decomposed from roadmap [2026-11-16]: Recently viewed bills on the home page — a user who opens a bill has no way back to it exc (review + tweak) [feat:billwatch-20261116-recently-viewed-bills-on-the-home-page-a] ---

# --- 27B-decomposed from roadmap [2026-11-16]: Recent searches on the bills page — a user who repeats a bill search has to retype it. The (review + tweak) [feat:billwatch-20261116-recent-searches-on-the-bills-page-a-user] ---

# --- 27B-decomposed from roadmap [2026-11-16]: Press / to focus the search box — keyboard users on the bills and members pages have to ta (review + tweak) [feat:billwatch-20261116-press-to-focus-the-search-box-keyboard-u] ---

# --- 27B-decomposed from roadmap [2026-11-16]: Bill status glossary pinned to the status ranking — `billwatch-backend/app/utils/bill_stat (review + tweak) [feat:billwatch-20261116-bill-status-glossary-pinned-to-the-statu] ---

# --- 27B-decomposed from roadmap [2026-11-16]: Saved searches: sort, filter and notifications-only — `billwatch-web/src/views/SavedSearch (review + tweak) [feat:billwatch-20261116-saved-searches-sort-filter-and-notificat] ---

# --- 27B-decomposed from roadmap [2026-11-16]: Screen reader announcements for list results — pages change their result lists without tel (review + tweak) [feat:billwatch-20261116-screen-reader-announcements-for-list-res] ---

# --- 27B-decomposed from roadmap [2026-11-16]: HTTP cache validator helpers — list and detail endpoints could answer repeat requests chea (review + tweak) [feat:billwatch-20261116-http-cache-validator-helpers-list-and-de] ---

# --- 27B-decomposed from roadmap [2026-11-16]: Bill stage progress helpers and reference — `billwatch-backend/app/utils/bill_stage.py` ha (review + tweak) [feat:billwatch-20261116-bill-stage-progress-helpers-and-referenc] ---

# --- 27B-decomposed from roadmap [2026-11-16]: Vote tally text helpers for the web — vote results show raw yea and nay numbers with no se (review + tweak) [feat:billwatch-20261116-vote-tally-text-helpers-for-the-web-vote] ---

# --- 27B-decomposed from roadmap [2026-11-16]: Safe search term helpers — search code that builds `ILIKE` patterns has to escape `%`, `_` (review + tweak) [feat:billwatch-20261116-safe-search-term-helpers-search-code-tha] ---

# --- 27B-decomposed from roadmap [2026-11-17]: Test `create_checkout` endpoint — `billwatch-backend/app/routers/billing.py:42` is unteste (review + tweak) [feat:billwatch-20261117-test-create-checkout-endpoint-billwatch-] ---

# --- 27B-decomposed from roadmap [2026-11-17]: Congress session date helpers and reference — `billwatch-backend/app/utils/congress_number (review + tweak) [feat:billwatch-20261117-congress-session-date-helpers-and-refere] ---

# --- 27B-decomposed from roadmap [2026-11-17]: Reading time helpers for bill summaries — long bill summaries have no hint of how long the (review + tweak) [feat:billwatch-20261117-reading-time-helpers-for-bill-summaries-] ---

# --- 27B-decomposed from roadmap [2026-11-17]: Bill citation helpers for the web — the web app has no single place that turns a bill type (review + tweak) [feat:billwatch-20261117-bill-citation-helpers-for-the-web-the-we] ---

# --- 27B-decomposed from roadmap [2026-11-17]: Vote margin helpers and reference — `billwatch-backend/app/utils/vote_outcome.py` says whe (review + tweak) [feat:billwatch-20261117-vote-margin-helpers-and-reference-billwa] ---

# --- 27B-decomposed from roadmap [2026-11-17]: Member counts by party and chamber for the web — the members list has no summary line of w (review + tweak) [feat:billwatch-20261117-member-counts-by-party-and-chamber-for-t] ---

# --- 27B-decomposed from roadmap [2026-11-17]: Bill type reference pinned to the label helpers — `billwatch-backend/app/utils/bill_type_l (review + tweak) [feat:billwatch-20261117-bill-type-reference-pinned-to-the-label-] ---

# --- 27B-decomposed from roadmap [2026-11-18]: Test `upvote_bill` and `downvote_bill` state changes — `billwatch-backend/app/routers/rank (review + tweak) [feat:billwatch-20261118-test-upvote-bill-and-downvote-bill-state] ---

# --- 27B-decomposed from roadmap [2026-11-20]: Bill votes endpoint reports overall totals and an outcome — `GET /api/votes/bill/{congress (review + tweak) [feat:billwatch-20261120-bill-votes-endpoint-reports-overall-tota] ---

# --- 27B-decomposed from roadmap [2026-11-20]: Sync status reports a freshness label — `SyncStatusResponse` in `billwatch-backend/app/sch (review + tweak) [feat:billwatch-20261120-sync-status-reports-a-freshness-label-sy] ---

# --- 27B-decomposed from roadmap [2026-11-20]: Bill responses carry a display id and an action freshness label — `BillResponse` in `billw (review + tweak) [feat:billwatch-20261120-bill-responses-carry-a-display-id-and-an] ---

# --- 27B-decomposed from roadmap [2026-11-20]: Status-change fan-out reports the alert priority — `StatusChangeAlertService.fan_out` in ` (review + tweak) [feat:billwatch-20261120-status-change-fan-out-reports-the-alert-] ---

# --- 27B-decomposed from roadmap [2026-11-20]: Bill detail page shows a stage progress bar — `billwatch-web/src/views/BillDetailView.vue` (review + tweak) [feat:billwatch-20261120-bill-detail-page-shows-a-stage-progress-] ---

# --- 27B-decomposed from roadmap [2026-11-20]: Notification times read as relative time with the exact time on hover — `billwatch-web/src (review + tweak) [feat:billwatch-20261120-notification-times-read-as-relative-time] ---

# --- 27B-decomposed from roadmap [2026-11-20]: The audit report is limited to admin users — `GET /api/activity-logs/audit-report` in `bil (review + tweak) [feat:billwatch-20261120-the-audit-report-is-limited-to-admin-use] ---

# --- 27B-decomposed from roadmap [2026-11-21]: Notification toggles reject values that are not booleans — `UserPreferencesService.update_ (review + tweak) [feat:billwatch-20261121-notification-toggles-reject-values-that-] ---

# --- 27B-decomposed from roadmap [2026-11-21]: The notifications list can be filtered by type — `GET /api/notifications` in `billwatch-ba (review + tweak) [feat:billwatch-20261121-the-notifications-list-can-be-filtered-b] ---

# --- 27B-decomposed from roadmap [2026-11-21]: A lightweight unread notification count endpoint — a client that only needs the badge numb (review + tweak) [feat:billwatch-20261121-a-lightweight-unread-notification-count-] ---

# --- 27B-decomposed from roadmap [2026-11-21]: Notification responses carry a short preview — `NotificationResponse` in `billwatch-backen (review + tweak) [feat:billwatch-20261121-notification-responses-carry-a-short-pre] ---

# --- 27B-decomposed from roadmap [2026-11-21]: Notifications can be deleted — there is no way to remove a notification; `billwatch-backen (review + tweak) [feat:billwatch-20261121-notifications-can-be-deleted-there-is-no] ---

# --- 27B-decomposed from roadmap [2026-11-21]: Digest and saved-search titles are cut at a word boundary — `billwatch-backend/app/service (review + tweak) [feat:billwatch-20261121-digest-and-saved-search-titles-are-cut-a] ---

# --- 27B-decomposed from roadmap [2026-11-21]: The topics list sends an ETag and answers If-None-Match — `GET /api/topics` in `billwatch- (review + tweak) [feat:billwatch-20261121-the-topics-list-sends-an-etag-and-answer] ---

# --- 27B-decomposed from roadmap [2026-11-21]: Bill summaries report a reading time — `BillSummaryResponse` in `billwatch-backend/app/sch (review + tweak) [feat:billwatch-20261121-bill-summaries-report-a-reading-time-bil] ---

# --- 27B-decomposed from roadmap [2026-11-21]: Bill responses carry a stage progress percentage — `BillResponse` in `billwatch-backend/ap (review + tweak) [feat:billwatch-20261121-bill-responses-carry-a-stage-progress-pe] ---

# --- 27B-decomposed from roadmap [2026-11-21]: Find Representatives uses the shared party helper and announces its states — `billwatch-we (review + tweak) [feat:billwatch-20261121-find-representatives-uses-the-shared-par] ---

# --- 27B-decomposed from roadmap [2026-11-21]: Representative cards have meaningful contact links — in `billwatch-web/src/components/RepC (review + tweak) [feat:billwatch-20261121-representative-cards-have-meaningful-con] ---

# --- 27B-decomposed from roadmap [2026-11-21]: Weekly Digest groups follow the bill life cycle and use plain labels — `billwatch-web/src/ (review + tweak) [feat:billwatch-20261121-weekly-digest-groups-follow-the-bill-lif] ---
- [ ] [T1] billwatch-web/src/utils/digestGroups.ts — Add `STAGE_ORDER` constant, `stageLabel` function mapping known stages to plain English and unknowns to title-cased spaced strings, and `orderStageGroups` function sorting by stage order with unknowns last. VERIFY: `cd billwatch-web && npx vitest run src/utils/__tests__/digestGroups.test.ts`. (cat:typescript; multifile:no) [feat:billwatch-20261121-weekly-digest-groups-follow-the-bill-lif]
- [ ] [T2] billwatch-web/src/utils/__tests__/digestGroups.test.ts — Add unit tests verifying `stageLabel` for all defined stages and `on_hold`, and `orderStageGroups` sorting logic including unknown stage placement and input immutability. VERIFY: `cd billwatch-web && npx vitest run src/utils/__tests__/digestGroups.test.ts`. (cat:test; multifile:no) [feat:billwatch-20261121-weekly-digest-groups-follow-the-bill-lif]
- [ ] [T3] billwatch-web/src/views/WeeklyDigestView.vue — Import `orderStageGroups` and `stageLabel`, wrap the computed stage groups in `orderStageGroups`, replace raw stage headings with `stageLabel(group.stage)`, and remove the `capitalize` class from the heading element. VERIFY: `cd billwatch-web && npx vitest run src/views/__tests__/WeeklyDigestView.groups.test.ts`. (cat:vue; multifile:no) [feat:billwatch-20261121-weekly-digest-groups-follow-the-bill-lif]
- [ ] [T4] billwatch-web/src/views/__tests__/WeeklyDigestView.groups.test.ts — Add test mounting `WeeklyDigestView` with mocked bills in stages `passed_senate`, `introduced`, `in_committee` and asserting sections render in order `Introduced`, `In Committee`, `Passed Senate`. VERIFY: `cd billwatch-web && npx vitest run src/views/__tests__/WeeklyDigestView.groups.test.ts`. (cat:test; multifile:no) [feat:billwatch-20261121-weekly-digest-groups-follow-the-bill-lif]
- [ ] [T5] billwatch-web/src/views/__tests__/WeeklyDigestView.test.ts — Update any assertions matching raw stage headings (e.g., `in_committee`) to match the new plain English labels (e.g., `In Committee`). VERIFY: `cd billwatch-web && npx vitest run src/views/__tests__/WeeklyDigestView.test.ts`. (cat:test; multifile:no) [feat:billwatch-20261121-weekly-digest-groups-follow-the-bill-lif]
- [ ] [T5] billwatch-web/src/views/__tests__/WeeklyDigestView.preview.test.ts — Update any assertions matching raw stage headings to match the new plain English labels. VERIFY: `cd billwatch-web && npx vitest run src/views/__tests__/WeeklyDigestView.preview.test.ts`. (cat:test; multifile:no) [feat:billwatch-20261121-weekly-digest-groups-follow-the-bill-lif]

# --- 27B-decomposed from roadmap [2026-11-21]: Trending Bills has a time window selector — `billwatch-web/src/pages/TrendingBillsPage.vue (review + tweak) [feat:billwatch-20261121-trending-bills-has-a-time-window-selecto] ---
- [ ] [T1] billwatch-web/src/utils/trendingWindow.ts — Add `TRENDING_WINDOWS` array with 7/14/30 day options, `DEFAULT_TRENDING_DAYS = 7`, and `isTrendingWindow` validation function. VERIFY: `cd billwatch-web && npx vitest run src/utils/__tests__/trendingWindow.test.ts`. (cat:typescript; multifile:no) [feat:billwatch-20261121-trending-bills-has-a-time-window-selecto]
- [ ] [T3] billwatch-web/src/pages/TrendingBillsPage.vue — Import `TRENDING_WINDOWS`/`DEFAULT_TRENDING_DAYS`, add `selectedDays` ref, update fetch call to use `selectedDays.value`, and render time window `<select>` above stats grid. VERIFY: `cd billwatch-web && npx vitest run src/pages/__tests__/TrendingBillsPage.window.test.ts`. (cat:vue; multifile:no) [feat:billwatch-20261121-trending-bills-has-a-time-window-selecto]
- [ ] [T2] billwatch-web/src/utils/__tests__/trendingWindow.test.ts — Add unit tests verifying `TRENDING_WINDOWS` order/labels, `DEFAULT_TRENDING_DAYS` value, and `isTrendingWindow` behavior for 7, 30, 0, and 15. VERIFY: `cd billwatch-web && npx vitest run src/utils/__tests__/trendingWindow.test.ts`. (cat:test; multifile:no) [feat:billwatch-20261121-trending-bills-has-a-time-window-selecto]
- [ ] [T4] billwatch-web/src/pages/__tests__/TrendingBillsPage.window.test.ts — Add tests verifying initial fetch uses `(7, 200)`, changing selection to 30 triggers fetch with `(30, 200)`, and page resets to 1 on window change. VERIFY: `cd billwatch-web && npx vitest run src/pages/__tests__/TrendingBillsPage.window.test.ts`. (cat:test; multifile:no) [feat:billwatch-20261121-trending-bills-has-a-time-window-selecto]
- [ ] [T5] billwatch-web/src/pages/TrendingBillsPage.vue — Add `<p role="status">Showing the past {{ selectedDays }} days</p>` under page title to announce current window. VERIFY: `cd billwatch-web && npx vitest run src/pages/__tests__/TrendingBillsPage.window-label.test.ts`. (cat:vue; multifile:no) [feat:billwatch-20261121-trending-bills-has-a-time-window-selecto]

# --- 27B-decomposed from roadmap [2026-11-21]: Recommendation cards link to the bill and the legislator — `billwatch-web/src/pages/Recomm (review + tweak) [feat:billwatch-20261121-recommendation-cards-link-to-the-bill-an] ---
- [ ] [T2] billwatch-web/src/pages/__tests__/RecommendationsPage.states.test.ts — Create new test file that mounts `RecommendationsPage` with a rejected API load and asserts exactly one `[role="alert"]` element and one `Retry` button exist. VERIFY: `cd billwatch-web && npx vitest run src/pages/__tests__/RecommendationsPage.states.test.ts`. (cat:test; multifile:no) [feat:billwatch-20261121-recommendation-cards-link-to-the-bill-an]
- [ ] [T3] billwatch-web/src/pages/RecommendationsPage.vue — Remove the second duplicated `v-else-if="error"` block and add `role="alert"` to the remaining error block. VERIFY: `cd billwatch-web && npx vitest run src/pages/__tests__/RecommendationsPage.states.test.ts`. (cat:vue; multifile:no) [feat:billwatch-20261121-recommendation-cards-link-to-the-bill-an]
- [ ] [T3] billwatch-web/src/pages/RecommendationsPage.vue — Add `bioguide_id?: string` to the `Recommendation` interface and wrap each bill card in `<RouterLink :to="`/bills/${bill.id}`">` and each legislator card in `<RouterLink :to="`/legislators/${leg.bioguide_id}`">` (rendering the link only when `bioguide_id` is set). VERIFY: `cd billwatch-web && npx vitest run src/pages/__tests__/RecommendationsPage.links.test.ts`. (cat:vue; multifile:no) [feat:billwatch-20261121-recommendation-cards-link-to-the-bill-an]
- [ ] [T3] billwatch-web/src/pages/__tests__/RecommendationsPage.test.ts — Update the mount helper to stub `RouterLink` with `{ props: ['to'], template: '<a :href="to"><slot /></a>' }` in `global.stubs`. VERIFY: `cd billwatch-web && npx vitest run src/pages/__tests__/RecommendationsPage.test.ts`. (cat:test; multifile:no) [feat:billwatch-20261121-recommendation-cards-link-to-the-bill-an]
- [ ] [T2] billwatch-web/src/pages/__tests__/RecommendationsPage.links.test.ts — Create new test file that verifies the first bill card links to `/bills/7` for `id: 7`, the legislator card links to `/legislators/B000001` for `bioguide_id: 'B000001'`, and a legislator without `bioguide_id` renders no link. VERIFY: `cd billwatch-web && npx vitest run src/pages/__tests__/RecommendationsPage.links.test.ts`. (cat:test; multifile:no) [feat:billwatch-20261121-recommendation-cards-link-to-the-bill-an]

# --- 27B-decomposed from roadmap [2026-11-21]: Search shows a failed search instead of staying silent — in `billwatch-web/src/pages/Searc (review + tweak) [feat:billwatch-20261121-search-shows-a-failed-search-instead-of-] ---
- [ ] [T2] billwatch-web/src/pages/__tests__/SearchPage.error.test.ts — Create test file mocking `advancedSearch` to reject, typing 'health', advancing timers, and asserting `role="alert"` contains "Search failed. Please try again." VERIFY: `cd billwatch-web && npx vitest run src/pages/__tests__/SearchPage.error.test.ts`. (cat:test; multifile:no) [feat:billwatch-20261121-search-shows-a-failed-search-instead-of-]
- [ ] [T3] billwatch-web/src/pages/SearchPage.vue — Add `searchError` ref, set it in `catch`, clear at start of `search()`, and render alert div above results. VERIFY: `cd billwatch-web && npx vitest run src/pages/__tests__/SearchPage.error.test.ts`. (cat:vue; multifile:no) [feat:billwatch-20261121-search-shows-a-failed-search-instead-of-]
- [ ] [T2] billwatch-web/src/pages/__tests__/SearchPage.retry.test.ts — Create test file mocking `advancedSearch` to reject then resolve, asserting "Try again" button appears and clicking it triggers second call with same query. VERIFY: `cd billwatch-web && npx vitest run src/pages/__tests__/SearchPage.retry.test.ts`. (cat:test; multifile:no) [feat:billwatch-20261121-search-shows-a-failed-search-instead-of-]
- [ ] [T3] billwatch-web/src/pages/SearchPage.vue — Add "Try again" button inside alert div that calls `search()`. VERIFY: `cd billwatch-web && npx vitest run src/pages/__tests__/SearchPage.retry.test.ts`. (cat:vue; multifile:no) [feat:billwatch-20261121-search-shows-a-failed-search-instead-of-]
- [ ] [T4] billwatch-web/src/pages/SearchPage.vue — Ensure `searchError` is cleared when a subsequent search resolves successfully. VERIFY: `cd billwatch-web && npx vitest run src/pages/__tests__/SearchPage.error.test.ts src/pages/__tests__/SearchPage.retry.test.ts`. (cat:vue; multifile:no) [feat:billwatch-20261121-search-shows-a-failed-search-instead-of-]
- [ ] [T5] billwatch-web/src/pages/SearchPage.vue — Verify no regression in existing search behavior by running full test suite for SearchPage. VERIFY: `cd billwatch-web && npx vitest run src/pages/__tests__/SearchPage.error.test.ts src/pages/__tests__/SearchPage.retry.test.ts src/pages/__tests__/SearchPage.test.ts src/pages/__tests__/SearchPage.routes.test.ts`. (cat:test; multifile:no) [feat:billwatch-20261121-search-shows-a-failed-search-instead-of-]

# --- 27B-decomposed from roadmap [2026-11-22]: Search re-runs when a filter changes — in `billwatch-web/src/pages/SearchPage.vue` the Con (review + tweak) [feat:billwatch-20261122-search-re-runs-when-a-filter-changes-in-] ---
- [ ] [T3] billwatch-web/src/pages/SearchPage.vue — Add `watch([congress, status], () => { void search() })` after the refs to trigger re-search on filter change. VERIFY: `grep -q "watch(\[congress, status\]" billwatch-web/src/pages/SearchPage.vue` (cat:vue; multifile:no) [feat:billwatch-20261122-search-re-runs-when-a-filter-changes-in-]
- [ ] [T2] billwatch-web/src/pages/__tests__/SearchPage.filters.test.ts — Create test verifying that changing `#filter-congress` to `118` after a query calls `advancedSearch` with `congress: 118`, and that changing it with an empty query makes no request. VERIFY: `cd billwatch-web && npx vitest run src/pages/__tests__/SearchPage.filters.test.ts` (cat:test; multifile:no) [feat:billwatch-20261122-search-re-runs-when-a-filter-changes-in-]
- [ ] [T2] billwatch-web/src/pages/__tests__/SearchPage.filters-status.test.ts — Create test verifying that changing `#filter-status` to `Passed` calls `advancedSearch` with `status: 'Passed'`, and setting it to `All Status` passes `status: null`. VERIFY: `cd billwatch-web && npx vitest run src/pages/__tests__/SearchPage.filters-status.test.ts` (cat:test; multifile:no) [feat:billwatch-20261122-search-re-runs-when-a-filter-changes-in-]

# --- 27B-decomposed from roadmap [2026-11-22]: Bill Ranking sliders are labelled and saving gives feedback — `billwatch-web/src/pages/Bil (review + tweak) [feat:billwatch-20261122-bill-ranking-sliders-are-labelled-and-sa] ---
- [ ] [T1] billwatch-web/src/pages/BillRankingPage.vue — Add `importanceText(value: number): string` function to the script block returning 'Not important', 'Important', or 'Very important' for values 0, 1, and 2 respectively. VERIFY: `cd billwatch-web && npx vitest run src/pages/__tests__/BillRankingPage.labels.test.ts --reporter=verbose 2>&1 | grep -q "importanceText" || echo "FAIL"` (cat:vue; multifile:no) [feat:billwatch-20261122-bill-ranking-sliders-are-labelled-and-sa]
- [ ] [T2] billwatch-web/src/pages/BillRankingPage.vue — Assign ids `rank-personal`, `rank-societal`, `rank-rights`, and `rank-economic` to the four `<input type="range">` elements and add matching `for` attributes to their corresponding `<label>` elements. VERIFY: `cd billwatch-web && npx vitest run src/pages/__tests__/BillRankingPage.labels.test.ts 2>&1 | grep -q "passed"` (cat:vue; multifile:no) [feat:billwatch-20261122-bill-ranking-sliders-are-labelled-and-sa]
- [ ] [T3] billwatch-web/src/pages/BillRankingPage.vue — Bind `:aria-valuetext="importanceText(personalImportance)"` (and corresponding bindings for societal, rights, and economic sliders) to the four range inputs. VERIFY: `cd billwatch-web && npx vitest run src/pages/__tests__/BillRankingPage.labels.test.ts 2>&1 | grep -q "passed"` (cat:vue; multifile:no) [feat:billwatch-20261122-bill-ranking-sliders-are-labelled-and-sa]
- [ ] [T4] billwatch-web/src/pages/__tests__/BillRankingPage.labels.test.ts — Create new test file importing the store mock and mount helper from `BillRankingPage.test.ts`, asserting that each `label[for]` points to an existing range input and that the personal slider has `aria-valuetext` "Important" for the default value 1. VERIFY: `cd billwatch-web && npx vitest run src/pages/__tests__/BillRankingPage.labels.test.ts` (cat:test; multifile:no) [feat:billwatch-20261122-bill-ranking-sliders-are-labelled-and-sa]
- [ ] [T5] billwatch-web/src/pages/BillRankingPage.vue — Add `const saveStatus = ref<'idle' | 'saved' | 'error'>('idle')` to the script, set it to `'saved'` after successful `updateUserPreferences` call and `'error'` in the catch block of the save function. VERIFY: `cd billwatch-web && npx vitest run src/pages/__tests__/BillRankingPage.save.test.ts 2>&1 | grep -q "passed"` (cat:vue; multifile:no) [feat:billwatch-20261122-bill-ranking-sliders-are-labelled-and-sa]

# --- 27B-decomposed from roadmap [2026-11-23]: The alert form labels are connected and a failed load can be retried — in `billwatch-web/s (review + tweak) [feat:billwatch-20261123-the-alert-form-labels-are-connected-and-] ---
- [ ] [T3] billwatch-web/src/views/AlertsView.vue — Add `for="alert-name"` to the Alert Name label and `id="alert-name"` to its input, and `for="alert-keywords"` to the Keywords label and `id="alert-keywords"` to its input. VERIFY: `cd billwatch-web && npx vitest run src/views/__tests__/AlertsView.labels.test.ts`. (cat:vue; multifile:no) [feat:billwatch-20261123-the-alert-form-labels-are-connected-and-]
- [ ] [T2] billwatch-web/src/views/__tests__/AlertsView.labels.test.ts — Create test file that mounts AlertsView, clicks "Create New Alert", and asserts `wrapper.find('label[for="alert-name"]')` exists with matching input id and `wrapper.find('#alert-keywords')` exists. VERIFY: `cd billwatch-web && npx vitest run src/views/__tests__/AlertsView.labels.test.ts`. (cat:test; multifile:no) [feat:billwatch-20261123-the-alert-form-labels-are-connected-and-]
- [ ] [T2] billwatch-web/src/views/__tests__/AlertsView.retry.test.ts — Create test file that mocks `getUserAlerts` to reject first then resolve, asserts "Failed to load alerts." and "Try again" button appear on failure, and clicking the button removes the alert and lists alerts. VERIFY: `cd billwatch-web && npx vitest run src/views/__tests__/AlertsView.retry.test.ts`. (cat:test; multifile:no) [feat:billwatch-20261123-the-alert-form-labels-are-connected-and-]
- [ ] [T3] billwatch-web/src/views/AlertsView.vue — Add `const loadFailed = ref(false)`, set `loadFailed.value = true` in `loadAlerts` catch block, clear `loadFailed.value = false` and `error.value = ''` at start of `loadAlerts`, and render a "Try again" button inside the error alert box that calls `loadAlerts` when `loadFailed` is true. VERIFY: `cd billwatch-web && npx vitest run src/views/__tests__/AlertsView.retry.test.ts`. (cat:vue; multifile:no) [feat:billwatch-20261123-the-alert-form-labels-are-connected-and-]

# --- 27B-decomposed from roadmap [2026-11-23]: Notification preferences can retry a failed load and confirm a reset — in `billwatch-web/s (review + tweak) [feat:billwatch-20261123-notification-preferences-can-retry-a-fai] ---
- [ ] [T1] billwatch-web/src/views/__tests__/NotificationPreferencesView.retry.test.ts — Create test file with `vi.hoisted` store mock copied from `billwatch-web/src/views/__tests__/NotificationPreferencesView.a11y.test.ts`, asserting that when `storeState.error` is set, a "Try again" button exists and clicking it calls `mockFetchPreferences`. VERIFY: `cd billwatch-web && npx vitest run src/views/__tests__/NotificationPreferencesView.retry.test.ts`. (cat:test; multifile:no) [feat:billwatch-20261123-notification-preferences-can-retry-a-fai]
- [ ] [T3] billwatch-web/src/views/NotificationPreferencesView.vue — Add `loadPreferences()` function that awaits `store.fetchPreferences()` and copies `store.preferences` to `form`, add "Try again" button in error alert calling it, and update `onMounted` to call `loadPreferences()`. VERIFY: `cd billwatch-web && npx vitest run src/views/__tests__/NotificationPreferencesView.retry.test.ts`. (cat:vue; multifile:no) [feat:billwatch-20261123-notification-preferences-can-retry-a-fai]
- [ ] [T1] billwatch-web/src/views/__tests__/NotificationPreferencesView.reset.test.ts — Create test file with store mock including `resetPreferences: vi.fn()`, asserting that clicking "Reset to Defaults" does NOT call `resetPreferences`, clicking `[data-testid="confirm-dialog-confirm"]` DOES call it, and clicking `[data-testid="confirm-dialog-cancel"]` does NOT. VERIFY: `cd billwatch-web && npx vitest run src/views/__tests__/NotificationPreferencesView.reset.test.ts`. (cat:test; multifile:no) [feat:billwatch-20261123-notification-preferences-can-retry-a-fai]
- [ ] [T3] billwatch-web/src/views/NotificationPreferencesView.vue — Add `showResetConfirm` ref, change "Reset to Defaults" button to set it true, render `<ConfirmDialog>` with correct props from `billwatch-web/src/components/ConfirmDialog.vue`, and add `confirmReset()` that closes dialog and calls existing `handleReset`. VERIFY: `cd billwatch-web && npx vitest run src/views/__tests__/NotificationPreferencesView.reset.test.ts`. (cat:vue; multifile:no) [feat:billwatch-20261123-notification-preferences-can-retry-a-fai]
- [ ] [T2] billwatch-web/src/views/__tests__/NotificationPreferencesView.a11y.test.ts — Update any assertion that clicks "Reset to Defaults" and expects immediate `resetPreferences` call to instead expect the confirm dialog to open (or remove if no longer applicable). VERIFY: `cd billwatch-web && npx vitest run src/views/__tests__/NotificationPreferencesView.a11y.test.ts`. (cat:test; multifile:no) [feat:billwatch-20261123-notification-preferences-can-retry-a-fai]
- [ ] [T5] billwatch-web/src/views/NotificationPreferencesView.vue — Final integration check ensuring both retry and reset flows work together without conflicts. VERIFY: `cd billwatch-web && npx vitest run src/views/__tests__/NotificationPreferencesView.retry.test.ts src/views/__tests__/NotificationPreferencesView.reset.test.ts src/views/__tests__/NotificationPreferencesView.a11y.test.ts`. (cat:vue; multifile:yes) [feat:billwatch-20261123-notification-preferences-can-retry-a-fai]
