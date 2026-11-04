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
- [ ] [T2] billwatch-backend/tests/test_bills_similar_endpoint.py — Add a new test `test_get_similar_bills_excludes_zero_score` that seeds bills with no similarity (or distinct policy areas to force 0 score in logic if applicable, but primarily testing the filter logic by mocking or ensuring distinct areas) and asserts that no entry has `similarity_score == 0`. VERIFY: `pytest billwatch-backend/tests/test_bills_similar_endpoint.py::test_get_similar_bills_excludes_zero_score -v`. (cat:test; multifile:no) [feat:billwatch-20261102-bound-and-narrow-get-api-bills-bill-id-s]
- [ ] [T2] billwatch-backend/tests/test_bills_similar_endpoint.py — Add a new test `test_get_similar_bills_empty_policy_area` that seeds a bill with `policy_area=None`, calls the endpoint, and asserts that `similar_bills` is an empty list. VERIFY: `pytest billwatch-backend/tests/test_bills_similar_endpoint.py::test_get_similar_bills_empty_policy_area -v`. (cat:test; multifile:no) [feat:billwatch-20261102-bound-and-narrow-get-api-bills-bill-id-s]

# --- 27B-decomposed from roadmap [2026-11-02]: Remove the per-vote N+1 in GET /api/legislators/{bioguide_id}/missed-votes — `get_missed_v (review + tweak) [feat:billwatch-20261102-remove-the-per-vote-n-1-in-get-api-legis] ---
- [ ] [T1] billwatch-backend/tests/test_missed_votes_query_count.py — Add a new test file that seeds one legislator with 5 not-voting roll calls (mixed bill presence) and asserts the response shape. VERIFY: `pytest billwatch-backend/tests/test_missed_votes_query_count.py -v` passes. (cat:test; multifile:no) [feat:billwatch-20261102-remove-the-per-vote-n-1-in-get-api-legis]
- [ ] [T1] billwatch-backend/tests/test_missed_votes_query_count.py — Add a SQLAlchemy `before_cursor_execute` event listener to the test engine in the new test file to count SQL statements. VERIFY: `pytest billwatch-backend/tests/test_missed_votes_query_count.py -v` passes and the listener is active. (cat:test; multifile:no) [feat:billwatch-20261102-remove-the-per-vote-n-1-in-get-api-legis]
- [ ] [T2] billwatch-backend/app/routers/legislators.py — Modify `get_missed_votes` to replace the per-row `select(Bill)` loop with a single `select(Vote, RollCallVote, Bill).outerjoin(Bill, RollCallVote.bill_id == Bill.id)` query. VERIFY: `pytest billwatch-backend/tests/test_missed_votes_query_count.py -v` passes and response shape is preserved. (cat:python; multifile:no) [feat:billwatch-20261102-remove-the-per-vote-n-1-in-get-api-legis]
- [ ] [T2] billwatch-backend/app/routers/legislators.py — Update the loop in `get_missed_votes` to construct `bill_info` from the joined `Bill` object (handling None) instead of fetching it separately. VERIFY: `pytest billwatch-backend/tests/test_missed_votes_query_count.py -v` passes and `bill` field is correct for both null and non-null cases. (cat:python; multifile:no) [feat:billwatch-20261102-remove-the-per-vote-n-1-in-get-api-legis]
- [ ] [T3] billwatch-backend/tests/test_missed_votes_query_count.py — Assert in the new test that the total number of SQL statements executed during the request is at most 3. VERIFY: `pytest billwatch-backend/tests/test_missed_votes_query_count.py -v` passes and fails if statement count exceeds 3. (cat:test; multifile:no) [feat:billwatch-20261102-remove-the-per-vote-n-1-in-get-api-legis]

# --- 27B-decomposed from roadmap [2026-11-02]: Make sitemap `<loc>` URLs point at the public web page, not the JSON API — `build_sitemap_ (review + tweak) [feat:billwatch-20261102-make-sitemap-loc-urls-point-at-the-publi] ---
- [ ] [T1] billwatch-backend/app/routers/bills.py — Modify `build_sitemap_xml` to accept a `base_url: str` parameter and construct `<loc>` entries as `{base_url.rstrip('/')}/bills/{bill_id}` instead of using the API base URL. VERIFY: `grep -q "base_url.rstrip" billwatch-backend/app/routers/bills.py`. (cat:python; multifile:no) [feat:billwatch-20261102-make-sitemap-loc-urls-point-at-the-publi]
- [ ] [T1] billwatch-backend/app/routers/bills.py — Modify `get_sitemap` to import `get_settings` from `app.config` and pass `get_settings().app_url` as the `base_url` argument to `build_sitemap_xml`. VERIFY: `grep -q "get_settings().app_url" billwatch-backend/app/routers/bills.py`. (cat:python; multifile:no) [feat:billwatch-20261102-make-sitemap-loc-urls-point-at-the-publi]
- [ ] [T2] billwatch-backend/tests/test_sitemap_loc_urls.py — Create new test file with a fixture that mocks `get_settings` to return `app_url="https://billwatch.vercel.app"` and asserts that `build_sitemap_xml` output contains `<loc>https://billwatch.vercel.app/bills/123</loc>` for a bill with id 123. VERIFY: `cd billwatch-backend && python -m pytest tests/test_sitemap_loc_urls.py::test_loc_uses_app_url -v`. (cat:test; multifile:no) [feat:billwatch-20261102-make-sitemap-loc-urls-point-at-the-publi]
- [ ] [T2] billwatch-backend/tests/test_sitemap_loc_urls.py — Add test case asserting that if `app_url` is `"https://billwatch.vercel.app/"` (with trailing slash), the generated `<loc>` is `https://billwatch.vercel.app/bills/123` (no double slash). VERIFY: `cd billwatch-backend && python -m pytest tests/test_sitemap_loc_urls.py::test_no_double_slash_with_trailing_app_url -v`. (cat:test; multifile:no) [feat:billwatch-20261102-make-sitemap-loc-urls-point-at-the-publi]
- [ ] [T2] billwatch-backend/tests/test_sitemap_loc_urls.py — Add test case asserting that the generated `<loc>` string does not contain `/api/`. VERIFY: `cd billwatch-backend && python -m pytest tests/test_sitemap_loc_urls.py::test_no_api_in_loc -v`. (cat:test; multifile:no) [feat:billwatch-20261102-make-sitemap-loc-urls-point-at-the-publi]
- [ ] [T3] billwatch-backend/tests/test_bills_sitemap.py — Update existing sitemap tests to ensure they still pass with the new `base_url` logic, specifically verifying that bill IDs appear in the `<loc>` tags as before. VERIFY: `cd billwatch-backend && python -m pytest tests/test_bills_sitemap.py -v`. (cat:test; multifile:no) [feat:billwatch-20261102-make-sitemap-loc-urls-point-at-the-publi]

# --- 27B-decomposed from roadmap [2026-11-02]: Replace the stray `print` and duplicated SSL setup in the SMTP send path — `billwatch-back (review + tweak) [feat:billwatch-20261102-replace-the-stray-print-and-duplicated-s] ---
- [ ] [T1] billwatch-backend/app/services/email_service.py — Remove the `print(f"[GODADDY-SMTP] Connecting to {smtp_host}:{smtp_port}", flush=True)` line and the duplicate `context = ssl.create_default_context()` assignment inside `_send_via_smtp_godaddy`, ensuring only one SSL context creation remains. VERIFY: `grep -q "print.*GODADDY-SMTP" billwatch-backend/app/services/email_service.py && exit 1 || exit 0` (cat:python; multifile:no) [feat:billwatch-20261102-replace-the-stray-print-and-duplicated-s]
- [ ] [T1] billwatch-backend/app/services/email_service.py — Replace the removed print statement with `logger.debug(f"Connecting to {smtp_host}:{smtp_port}")` using the existing logger instance in the module. VERIFY: `grep -q "logger.debug.*Connecting to" billwatch-backend/app/services/email_service.py` (cat:python; multifile:no) [feat:billwatch-20261102-replace-the-stray-print-and-duplicated-s]
- [ ] [T2] billwatch-backend/tests/test_email_service_no_print.py — Create a new test file containing a test class that imports `EmailService`, uses the `email_service` fixture pattern, patches `smtplib.SMTP_SSL`, and calls `_send_via_smtp_godaddy`. VERIFY: `python -m pytest billwatch-backend/tests/test_email_service_no_print.py --collect-only -q | grep -q "test_email_service_no_print"` (cat:test; multifile:no) [feat:billwatch-20261102-replace-the-stray-print-and-duplicated-s]
- [ ] [T2] billwatch-backend/tests/test_email_service_no_print.py — Add a test method that asserts `capsys.readouterr().out` is empty after calling the SMTP send method to verify no stdout leakage. VERIFY: `python -m pytest billwatch-backend/tests/test_email_service_no_print.py::TestNoPrint::test_no_stdout_output -v` (cat:test; multifile:no) [feat:billwatch-20261102-replace-the-stray-print-and-duplicated-s]
- [ ] [T2] billwatch-backend/tests/test_email_service_no_print.py — Add a test method that asserts `smtplib.SMTP_SSL` mock was called exactly once with `timeout=10` argument. VERIFY: `python -m pytest billwatch-backend/tests/test_email_service_no_print.py::TestNoPrint::test_smtp_called_with_timeout -v` (cat:test; multifile:no) [feat:billwatch-20261102-replace-the-stray-print-and-duplicated-s]

# --- 27B-decomposed from roadmap [2026-11-02]: Add baseline security response headers to the API — nothing in `billwatch-backend/app` set (review + tweak) [feat:billwatch-20261102-add-baseline-security-response-headers-t] ---
- [ ] [T1] billwatch-backend/app/core/security_headers.py — Create `SecurityHeadersMiddleware` class inheriting `BaseHTTPMiddleware` that sets `X-Content-Type-Options`, `X-Frame-Options`, `Referrer-Policy`, and `Permissions-Policy` on responses only if not already present. VERIFY: `python -c "from billwatch-backend.app.core.security_headers import SecurityHeadersMiddleware; print('ok')"`. (cat:python; multifile:no) [feat:billwatch-20261102-add-baseline-security-response-headers-t]
- [ ] [T2] billwatch-backend/tests/test_security_headers.py — Create test file with a minimal FastAPI app using `SecurityHeadersMiddleware` to verify headers are present on 200, 404, and error responses, and that handler-set `X-Frame-Options` is preserved. VERIFY: `cd billwatch-backend && pytest tests/test_security_headers.py -v`. (cat:test; multifile:no) [feat:billwatch-20261102-add-baseline-security-response-headers-t]
- [ ] [T3] billwatch-backend/app/main.py — Register `SecurityHeadersMiddleware` using `app.add_middleware` immediately after `RequestIdMiddleware` registration. VERIFY: `grep -q "add_middleware(SecurityHeadersMiddleware)" billwatch-backend/app/main.py`. (cat:python; multifile:no) [feat:billwatch-20261102-add-baseline-security-response-headers-t]

# --- 27B-decomposed from roadmap [2026-11-02]: Compress large API responses with GZipMiddleware — `billwatch-backend/app/main.py` registe (review + tweak) [feat:billwatch-20261102-compress-large-api-responses-with-gzipmi] ---
- [ ] [T1] billwatch-backend/tests/test_gzip_middleware.py — Create test file with `test_health_no_gzip` asserting `GET /health` response has no `content-encoding` header. VERIFY: `cd billwatch-backend && python -m pytest tests/test_gzip_middleware.py::test_health_no_gzip -v`. (cat:test; multifile:no) [feat:billwatch-20261102-compress-large-api-responses-with-gzipmi]
- [ ] [T1] billwatch-backend/tests/test_gzip_middleware.py — Add `test_sitemap_gzip` asserting `GET /api/bills/sitemap.xml` with `Accept-Encoding: gzip` returns `content-encoding: gzip`. VERIFY: `cd billwatch-backend && python -m pytest tests/test_gzip_middleware.py::test_sitemap_gzip -v`. (cat:test; multifile:no) [feat:billwatch-20261102-compress-large-api-responses-with-gzipmi]
- [ ] [T1] billwatch-backend/tests/test_gzip_middleware.py — Add `test_no_accept_encoding` asserting `GET /api/bills/sitemap.xml` without `Accept-Encoding` has no `content-encoding` header. VERIFY: `cd billwatch-backend && python -m pytest tests/test_gzip_middleware.py::test_no_accept_encoding -v`. (cat:test; multifile:no) [feat:billwatch-20261102-compress-large-api-responses-with-gzipmi]
- [ ] [T3] billwatch-backend/app/main.py — Add `from fastapi.middleware.gzip import GZipMiddleware` import and `app.add_middleware(GZipMiddleware, minimum_size=1000)` registration. VERIFY: `cd billwatch-backend && grep -q "GZipMiddleware" app/main.py && python -m pytest tests/test_gzip_middleware.py -v`. (cat:python; multifile:no) [feat:billwatch-20261102-compress-large-api-responses-with-gzipmi]

# --- 27B-decomposed from roadmap [2026-11-02]: Make `tests/test_finance_helpers.py` test the real router helper, then reuse the shared pe (review + tweak) [feat:billwatch-20261102-make-tests-test-finance-helpers-py-test-] ---
- [ ] [T1] billwatch-backend/app/utils/finance_math.py — Add `pct_of_total(part: float, total: float) -> float` function returning 0.0 if total is 0 else round(part/total*100, 1). VERIFY: `python -c "from app.utils.finance_math import pct_of_total; assert pct_of_total(1, 2) == 50.0; assert pct_of_total(1, 0) == 0.0"`. (cat:python; multifile:no) [feat:billwatch-20261102-make-tests-test-finance-helpers-py-test-]
- [ ] [T2] billwatch-backend/tests/test_finance_helpers.py — Replace local `_calculate_donation_pcts` definition with `from app.routers.finance import _calculate_donation_pcts`. VERIFY: `grep -q "def _calculate_donation_pcts" tests/test_finance_helpers.py && exit 1 || true; grep -q "from app.routers.finance import _calculate_donation_pcts" tests/test_finance_helpers.py`. (cat:test; multifile:no) [feat:billwatch-20261102-make-tests-test-finance-helpers-py-test-]
- [ ] [T3] billwatch-backend/app/routers/finance.py — Import `pct_of_total` from `app.utils.finance_math` and update `_calculate_donation_pcts` to use it. VERIFY: `python -c "from app.routers.finance import _calculate_donation_pcts; assert _calculate_donation_pcts(10, 90) == (10.0, 90.0); assert _calculate_donation_pcts(0, 0) == (0.0, 0.0)"`. (cat:python; multifile:no) [feat:billwatch-20261102-make-tests-test-finance-helpers-py-test-]
- [ ] [T4] billwatch-backend/tests/test_finance_helpers.py — Run existing test suite to ensure all assertions pass with the imported helper. VERIFY: `pytest tests/test_finance_helpers.py -v`. (cat:test; multifile:no) [feat:billwatch-20261102-make-tests-test-finance-helpers-py-test-]
- [ ] [T5] billwatch-backend/tests/test_finance_math.py — Verify `pct_of_total` is tested or add minimal test if missing, ensuring consistency with router usage. VERIFY: `pytest tests/test_finance_math.py -v`. (cat:test; multifile:no) [feat:billwatch-20261102-make-tests-test-finance-helpers-py-test-]

# --- 27B-decomposed from roadmap [2026-11-02]: Add a naive-UTC `utcnow_naive()` helper for the DB-column timestamps — `datetime.utcnow()` (review + tweak) [feat:billwatch-20261102-add-a-naive-utc-utcnow-naive-helper-for-] ---
- [ ] [T1] billwatch-backend/app/utils/datetime_utils.py — Add `utcnow_naive()` function returning `datetime.now(timezone.utc).replace(tzinfo=None)` with docstring explaining usage for naive DB columns. VERIFY: `python -c "from app.utils.datetime_utils import utcnow_naive; d = utcnow_naive(); assert d.tzinfo is None"`. (cat:python; multifile:no) [feat:billwatch-20261102-add-a-naive-utc-utcnow-naive-helper-for-]
- [ ] [T1] billwatch-backend/tests/test_utcnow_naive.py — Create test file verifying `utcnow_naive()` returns naive datetime and is within 1 second of current UTC time. VERIFY: `pytest billwatch-backend/tests/test_utcnow_naive.py -v`. (cat:test; multifile:no) [feat:billwatch-20261102-add-a-naive-utc-utcnow-naive-helper-for-]
- [ ] [T3] billwatch-backend/app/services/trending.py — Replace all `datetime.utcnow()` calls (lines ~116, 143, 238, 337, 359, 389) with `utcnow_naive()` and add import from `app.utils.datetime_utils`. VERIFY: `grep -c "datetime.utcnow(" billwatch-backend/app/services/trending.py` returns 0. (cat:refactor; multifile:no) [feat:billwatch-20261102-add-a-naive-utc-utcnow-naive-helper-for-]
- [ ] [T1] billwatch-backend/tests/test_utcnow_naive.py — Add test asserting `billwatch-backend/app/services/trending.py` file text does not contain literal string `datetime.utcnow(`. VERIFY: `pytest billwatch-backend/tests/test_utcnow_naive.py::test_trending_no_utcnow -v`. (cat:test; multifile:no) [feat:billwatch-20261102-add-a-naive-utc-utcnow-naive-helper-for-]
- [ ] [T3] billwatch-backend/app/services/trending.py — Ensure all `.isoformat()` calls on timestamps from `utcnow_naive()` do not include `+00:00` suffix by verifying output format matches naive datetime ISO format. VERIFY: `python -c "from app.utils.datetime_utils import utcnow_naive; s = utcnow_naive().isoformat(); assert '+00:00' not in s"`. (cat:refactor; multifile:no) [feat:billwatch-20261102-add-a-naive-utc-utcnow-naive-helper-for-]

# --- 27B-decomposed from roadmap [2026-11-02]: Migrate `bill_analytics_service.py` and `trending_service.py` off `datetime.utcnow()` — in (review + tweak) [feat:billwatch-20261102-migrate-bill-analytics-service-py-and-tr] ---
- [ ] [T1] billwatch-backend/app/utils/datetime_utils.py — Add `utcnow_naive()` function returning `datetime.now(timezone.utc).replace(tzinfo=None)` if not present. VERIFY: `python -c "from app.utils.datetime_utils import utcnow_naive; assert utcnow_naive().tzinfo is None"`. (cat:python; multifile:no) [feat:billwatch-20261102-migrate-bill-analytics-service-py-and-tr]
- [ ] [T3] billwatch-backend/app/services/bill_analytics_service.py — Replace all occurrences of `datetime.utcnow()` with `utcnow_naive()` and import it from `app.utils.datetime_utils`. VERIFY: `grep -q "datetime.utcnow(" billwatch-backend/app/services/bill_analytics_service.py && exit 1 || exit 0`. (cat:refactor; multifile:no) [feat:billwatch-20261102-migrate-bill-analytics-service-py-and-tr]
- [ ] [T3] billwatch-backend/app/services/trending_service.py — Replace all occurrences of `datetime.utcnow()` with `utcnow_naive()` and import it from `app.utils.datetime_utils`. VERIFY: `grep -q "datetime.utcnow(" billwatch-backend/app/services/trending_service.py && exit 1 || exit 0`. (cat:refactor; multifile:no) [feat:billwatch-20261102-migrate-bill-analytics-service-py-and-tr]
- [ ] [T2] billwatch-backend/tests/test_utcnow_naive_migration_analytics.py — Create new test file asserting `bill_analytics_service.py` and `trending_service.py` do not contain `datetime.utcnow(`. VERIFY: `pytest billwatch-backend/tests/test_utcnow_naive_migration_analytics.py -v`. (cat:test; multifile:no) [feat:billwatch-20261102-migrate-bill-analytics-service-py-and-tr]
- [ ] [T4] billwatch-backend/app/services/bill_analytics_service.py — Ensure existing logic remains intact by running existing tests. VERIFY: `pytest billwatch-backend/tests/test_bill_analytics_service.py -v`. (cat:test; multifile:yes) [feat:billwatch-20261102-migrate-bill-analytics-service-py-and-tr]
- [ ] [T4] billwatch-backend/app/services/trending_service.py — Ensure existing logic remains intact by running existing tests. VERIFY: `pytest billwatch-backend/tests/test_trending_service.py -v`. (cat:test; multifile:yes) [feat:billwatch-20261102-migrate-bill-analytics-service-py-and-tr]

# --- 27B-decomposed from roadmap [2026-11-02]: Migrate `bill_ranking_service.py`, `alert_service.py` and `security_audit_service.py` off  (review + tweak) [feat:billwatch-20261102-migrate-bill-ranking-service-py-alert-se] ---
- [ ] [T1] billwatch-backend/app/utils/datetime_utils.py — Add `utcnow_naive()` function returning `datetime.now(timezone.utc).replace(tzinfo=None)` and import necessary modules. VERIFY: `python -c "from billwatch_backend.app.utils.datetime_utils import utcnow_naive; print(utcnow_naive())"`. (cat:python; multifile:no) [feat:billwatch-20261102-migrate-bill-ranking-service-py-alert-se]
- [ ] [T3] billwatch-backend/app/services/bill_ranking_service.py — Replace all occurrences of `datetime.utcnow()` with `utcnow_naive()` and add the import. VERIFY: `grep -c "datetime.utcnow(" billwatch-backend/app/services/bill_ranking_service.py` returns 0. (cat:refactor; multifile:no) [feat:billwatch-20261102-migrate-bill-ranking-service-py-alert-se]
- [ ] [T3] billwatch-backend/app/services/alert_service.py — Replace all occurrences of `datetime.utcnow()` with `utcnow_naive()` and add the import. VERIFY: `grep -c "datetime.utcnow(" billwatch-backend/app/services/alert_service.py` returns 0. (cat:refactor; multifile:no) [feat:billwatch-20261102-migrate-bill-ranking-service-py-alert-se]
- [ ] [T3] billwatch-backend/app/services/security_audit_service.py — Replace all occurrences of `datetime.utcnow()` with `utcnow_naive()` and add the import. VERIFY: `grep -c "datetime.utcnow(" billwatch-backend/app/services/security_audit_service.py` returns 0. (cat:refactor; multifile:no) [feat:billwatch-20261102-migrate-bill-ranking-service-py-alert-se]
- [ ] [T2] billwatch-backend/tests/test_utcnow_naive_migration_services.py — Create test file asserting `datetime.utcnow(` is absent in the three service files and verifying `AlertService` logic via existing test patterns. VERIFY: `pytest billwatch-backend/tests/test_utcnow_naive_migration_services.py -v`. (cat:test; multifile:no) [feat:billwatch-20261102-migrate-bill-ranking-service-py-alert-se]
- [ ] [T4] billwatch-backend/tests/test_alert_service.py — Run existing tests to ensure `last_triggered_at` assignment still works with naive datetimes. VERIFY: `pytest billwatch-backend/tests/test_alert_service.py -v`. (cat:test; multifile:no) [feat:billwatch-20261102-migrate-bill-ranking-service-py-alert-se]
- [ ] [T4] billwatch-backend/tests/test_bill_ranking_service.py — Run existing tests to ensure ranking logic remains consistent after datetime migration. VERIFY: `pytest billwatch-backend/tests/test_bill_ranking_service.py -v`. (cat:test; multifile:no) [feat:billwatch-20261102-migrate-bill-ranking-service-py-alert-se]

# --- 27B-decomposed from roadmap [2026-11-02]: Give GET /api/legislators/{bioguide_id}/sponsored-bills a typed schema and stable ordering (review + tweak) [feat:billwatch-20261102-give-get-api-legislators-bioguide-id-spo] ---
- [ ] [T1] billwatch-backend/app/schemas/legislator.py — Add `SponsoredBillResponse` Pydantic model with fields `id: int`, `congress_id: str`, `title: str`, `status: str | None`, `introduced_date: date | None`, `latest_action_date: date | None`, `latest_action_text: str | None`. VERIFY: `python -c "from billwatch_backend.app.schemas.legislator import SponsoredBillResponse; print(SponsoredBillResponse.model_fields.keys())"` shows all 7 fields. (cat:schema; multifile:no) [feat:billwatch-20261102-give-get-api-legislators-bioguide-id-spo]
- [ ] [T3] billwatch-backend/app/routers/legislators.py — Import `SponsoredBillResponse` and update `get_sponsored_bills` to set `response_model=list[SponsoredBillResponse]`. VERIFY: `python -c "from billwatch_backend.app.main import app; schema = app.openapi(); assert 'SponsoredBillResponse' in schema['components']['schemas']"` passes. (cat:endpoint; multifile:no) [feat:billwatch-20261102-give-get-api-legislators-bioguide-id-spo]
- [ ] [T3] billwatch-backend/app/routers/legislators.py — Update the query ordering in `get_sponsored_bills` to use `Bill.introduced_date.desc().nulls_last()` and add `Bill.id.desc()` as a secondary sort. VERIFY: `grep -n "nulls_last" billwatch-backend/app/routers/legislators.py` returns a line containing `Bill.introduced_date.desc().nulls_last()`. (cat:endpoint; multifile:no) [feat:billwatch-20261102-give-get-api-legislators-bioguide-id-spo]
- [ ] [T2] billwatch-backend/tests/test_sponsored_bills_schema.py — Create test file with a fixture that seeds a legislator and bills (one with NULL `introduced_date`, others with dates) and a test asserting the OpenAPI schema includes `SponsoredBillResponse` for the `/api/legislators/{bioguide_id}/sponsored-bills` path. VERIFY: `pytest billwatch-backend/tests/test_sponsored_bills_schema.py::test_openapi_schema_includes_sponsored_bill_response -v` passes. (cat:test; multifile:no) [feat:billwatch-20261102-give-get-api-legislators-bioguide-id-spo]
- [ ] [T2] billwatch-backend/tests/test_sponsored_bills_schema.py — Add a test that calls the endpoint and asserts bills are returned in descending order of `introduced_date` with NULL dates appearing last, and that the response keys match `SponsoredBillResponse` fields. VERIFY: `pytest billwatch-backend/tests/test_sponsored_bills_schema.py::test_sponsored_bills_ordering_and_schema -v` passes. (cat:test; multifile:no) [feat:billwatch-20261102-give-get-api-legislators-bioguide-id-spo]
- [ ] [T2] billwatch-backend/tests/test_sponsored_bills_schema.py — Add a test that verifies `limit` and `offset` parameters correctly paginate the results, ensuring the first page excludes items that should be on the second page. VERIFY: `pytest billwatch-backend/tests/test_sponsored_bills_schema.py::test_sponsored_bills_pagination -v` passes. (cat:test; multifile:no) [feat:billwatch-20261102-give-get-api-legislators-bioguide-id-spo]

# --- 27B-decomposed from roadmap [2026-11-02]: Delete the orphaned `TrendingBillsView.vue` — `billwatch-web/src/views/TrendingBillsView.v (review + tweak) [feat:billwatch-20261102-delete-the-orphaned-trendingbillsview-vu] ---
- [ ] [T3] billwatch-web/src/views/TrendingBillsView.vue — Remove the `followBill` function definition and its associated `console.log` statement. VERIFY: `grep -n "followBill" billwatch-web/src/views/TrendingBillsView.vue` returns no matches. (cat:vue; multifile:no) [feat:billwatch-20261102-delete-the-orphaned-trendingbillsview-vu]
- [ ] [T3] billwatch-web/src/views/TrendingBillsView.vue — Remove the HTML button element that triggers the `followBill` action. VERIFY: `grep -n "Follow" billwatch-web/src/views/TrendingBillsView.vue` returns no matches. (cat:vue; multifile:no) [feat:billwatch-20261102-delete-the-orphaned-trendingbillsview-vu]
- [ ] [T3] billwatch-web/src/views/TrendingBillsView.vue — Remove all unused imports and variables that were only used by the removed follow functionality. VERIFY: `cd billwatch-web && npx vue-tsc --noEmit` passes without errors. (cat:vue; multifile:no) [feat:billwatch-20261102-delete-the-orphaned-trendingbillsview-vu]
- [ ] [T3] billwatch-web/src/views/TrendingBillsView.vue — Delete the entire file content, leaving an empty file or removing it entirely if the tool allows. VERIFY: `test -f billwatch-web/src/views/TrendingBillsView.vue && wc -l < billwatch-web/src/views/TrendingBillsView.vue` outputs 0 or the file is missing. (cat:vue; multifile:no) [feat:billwatch-20261102-delete-the-orphaned-trendingbillsview-vu]
- [ ] [T4] billwatch-web/src — Verify no other files import or reference `TrendingBillsView`. VERIFY: `grep -rn "TrendingBillsView" billwatch-web/src` returns nothing. (cat:refactor; multifile:yes) [feat:billwatch-20261102-delete-the-orphaned-trendingbillsview-vu]
- [ ] [T5] billwatch-web — Run the full test suite to ensure no tests depend on the deleted component. VERIFY: `cd billwatch-web && npx vitest run` passes. (cat:test; multifile:yes) [feat:billwatch-20261102-delete-the-orphaned-trendingbillsview-vu]
- [ ] [T5] billwatch-web — Run the type-check build to ensure no type errors remain after deletion. VERIFY: `cd billwatch-web && npm run build:typecheck` passes. (cat:typescript; multifile:yes) [feat:billwatch-20261102-delete-the-orphaned-trendingbillsview-vu]

# --- 27B-decomposed from roadmap [2026-11-02]: Expose a load-error state from the bills store — every action in `billwatch-web/src/stores (review + tweak) [feat:billwatch-20261102-expose-a-load-error-state-from-the-bills] ---
- [ ] [T1] billwatch-web/src/stores/bills.ts — Add `const error = ref<string | null>(null)` to the store state and include it in the returned object. VERIFY: `grep -q "const error = ref<string | null>(null)" billwatch-web/src/stores/bills.ts && grep -q "error," billwatch-web/src/stores/bills.ts`. (cat:typescript; multifile:no) [feat:billwatch-20261102-expose-a-load-error-state-from-the-bills]
- [ ] [T2] billwatch-web/src/stores/bills.ts — In `searchBills`, `fetchTrendingBills`, and `fetchFollowedBills`, set `error.value = null` at the start of the function and `error.value = 'Failed to load bills. Please try again.'` in the `catch` block before `return`. VERIFY: `grep -A 5 "async searchBills" billwatch-web/src/stores/bills.ts | grep -q "error.value = null" && grep -A 10 "async searchBills" billwatch-web/src/stores/bills.ts | grep -q "error.value = 'Failed to load bills. Please try again.'"`. (cat:typescript; multifile:no) [feat:billwatch-20261102-expose-a-load-error-state-from-the-bills]
- [ ] [T3] billwatch-web/src/stores/bills.ts — In `fetchBillDetail`, set `selectedBill.value = null` and `error.value = null` at the start of the function, and set `error.value = 'Bill not found or unavailable.'` in the `catch` block. VERIFY: `grep -A 5 "async fetchBillDetail" billwatch-web/src/stores/bills.ts | grep -q "selectedBill.value = null" && grep -A 10 "async fetchBillDetail" billwatch-web/src/stores/bills.ts | grep -q "error.value = 'Bill not found or unavailable.'"`. (cat:typescript; multifile:no) [feat:billwatch-20261102-expose-a-load-error-state-from-the-bills]
- [ ] [T4] billwatch-web/src/stores/bills.ts — In `toggleFollow`, set `error.value = null` at the start of the function and `error.value = 'Failed to update follow status. Please try again.'` in the `catch` block. VERIFY: `grep -A 5 "async toggleFollow" billwatch-web/src/stores/bills.ts | grep -q "error.value = null" && grep -A 10 "async toggleFollow" billwatch-web/src/stores/bills.ts | grep -q "error.value = 'Failed to update follow status. Please try again.'"`. (cat:typescript; multifile:no) [feat:billwatch-20261102-expose-a-load-error-state-from-the-bills]
- [ ] [T5] billwatch-web/src/stores/__tests__/bills.error.test.ts — Create a new test file that mocks `@/services/api`, imports the bills store, and verifies that `error` is set to a non-null string when `api.get` rejects in `searchBills`. VERIFY: `cd billwatch-web && npx vitest run src/stores/__tests__/bills.error.test.ts -t "sets error on search failure"`. (cat:test; multifile:no) [feat:billwatch-20261102-expose-a-load-error-state-from-the-bills]

# --- 27B-decomposed from roadmap [2026-11-02]: Show an error/not-found state on the bill detail page instead of a blank screen — `billwat (review + tweak) [feat:billwatch-20261102-show-an-error-not-found-state-on-the-bil] ---
- [ ] [T2] billwatch-web/src/stores/bills.ts — Add `error: ref<string | null>(null)` to the store state and set it in the catch block of `fetchBillDetail`. VERIFY: `grep -q "error: ref<string | null>(null)" billwatch-web/src/stores/bills.ts && grep -q "error.value = " billwatch-web/src/stores/bills.ts`. (cat:typescript; multifile:no) [feat:billwatch-20261102-show-an-error-not-found-state-on-the-bil]
- [ ] [T3] billwatch-web/src/views/BillDetailView.vue — Add a final `v-else` block with `role="alert"` displaying `billsStore.error` (fallback 'This bill could not be loaded.'), a Retry button calling `billsStore.fetchBillDetail(billId.value)`, and a `router-link` to `/bills`. VERIFY: `grep -q "role=\"alert\"" billwatch-web/src/views/BillDetailView.vue && grep -q "fetchBillDetail(billId.value)" billwatch-web/src/views/BillDetailView.vue`. (cat:vue; multifile:no) [feat:billwatch-20261102-show-an-error-not-found-state-on-the-bil]
- [ ] [T1] billwatch-web/src/views/__tests__/BillDetailView.error.test.ts — Create test file mocking `@/stores/bills` and `vue-router`, asserting the alert text renders when `bill` is null, `isLoading` is false, and `error` is set. VERIFY: `cd billwatch-web && npx vitest run src/views/__tests__/BillDetailView.error.test.ts -t "renders alert"`. (cat:test; multifile:no) [feat:billwatch-20261102-show-an-error-not-found-state-on-the-bil]
- [ ] [T1] billwatch-web/src/views/__tests__/BillDetailView.error.test.ts — Add test case asserting the Retry button calls `fetchBillDetail` with the route id when clicked. VERIFY: `cd billwatch-web && npx vitest run src/views/__tests__/BillDetailView.error.test.ts -t "calls fetchBillDetail"`. (cat:test; multifile:no) [feat:billwatch-20261102-show-an-error-not-found-state-on-the-bil]
- [ ] [T1] billwatch-web/src/views/__tests__/BillDetailView.error.test.ts — Add test case asserting the alert element is absent when a bill is present. VERIFY: `cd billwatch-web && npx vitest run src/views/__tests__/BillDetailView.error.test.ts -t "alert absent when bill present"`. (cat:test; multifile:no) [feat:billwatch-20261102-show-an-error-not-found-state-on-the-bil]

# --- 27B-decomposed from roadmap [2026-11-02]: Show a failed-search error with retry on the bills list — `billwatch-web/src/views/BillsVi (review + tweak) [feat:billwatch-20261102-show-a-failed-search-error-with-retry-on] ---
- [ ] [T2] billwatch-web/src/stores/bills.ts — Add `error: ref<string | null>(null)` state, clear it at the start of `searchBills`, and set it in the catch block of `searchBills`. VERIFY: `cd billwatch-web && npx vitest run src/stores/__tests__/bills.test.ts -t "sets error on search failure"`. (cat:typescript; multifile:no) [feat:billwatch-20261102-show-a-failed-search-error-with-retry-on]
- [ ] [T3] billwatch-web/src/views/BillsView.vue — Import `billsStore`, add a `role="alert"` div with the error message and a Retry button (`@click="billsStore.searchBills(searchQuery.value, 1)"`) that renders when `billsStore.error` is set, placed before the empty state and above the list. VERIFY: `cd billwatch-web && npx vue-tsc --noEmit`. (cat:vue; multifile:no) [feat:billwatch-20261102-show-a-failed-search-error-with-retry-on]
- [ ] [T1] billwatch-web/src/views/__tests__/BillsView.error.test.ts — Create new test file mocking `@/stores/bills`, `vue-router`, and stubbing components; test that alert is visible when error is set, Retry calls `searchBills` with query and page 1, and no alert when error is null. VERIFY: `cd billwatch-web && npx vitest run src/views/__tests__/BillsView.error.test.ts`. (cat:test; multifile:no) [feat:billwatch-20261102-show-a-failed-search-error-with-retry-on]

# --- 27B-decomposed from roadmap [2026-11-02]: Show a failed-load error with retry on the Following page — `billwatch-web/src/views/Follo (review + tweak) [feat:billwatch-20261102-show-a-failed-load-error-with-retry-on-t] ---
- [ ] [T2] billwatch-web/src/stores/bills.ts — Add `error: ref<string | null>(null)` state, clear it at the start of `fetchFollowedBills`, and set it in the catch block. VERIFY: `cd billwatch-web && npx vitest run src/stores/__tests__/bills.test.ts -t "sets error on fetch failure"`. (cat:typescript; multifile:no) [feat:billwatch-20261102-show-a-failed-load-error-with-retry-on-t]
- [ ] [T3] billwatch-web/src/views/FollowingView.vue — Modify template to render a `role="alert"` div with error message and a `type="button"` Retry button when `billsStore.error` is truthy, hiding the empty state. VERIFY: `cd billwatch-web && npx vue-tsc --noEmit`. (cat:vue; multifile:no) [feat:billwatch-20261102-show-a-failed-load-error-with-retry-on-t]
- [ ] [T3] billwatch-web/src/views/FollowingView.vue — Add a `retryLoad` function that calls `billsStore.fetchFollowedBills()` and bind it to the Retry button's `@click`. VERIFY: `cd billwatch-web && npx vue-tsc --noEmit`. (cat:vue; multifile:no) [feat:billwatch-20261102-show-a-failed-load-error-with-retry-on-t]
- [ ] [T1] billwatch-web/src/views/__tests__/FollowingView.error.test.ts — Create new test file verifying that when `billsStore.error` is set, the empty state text "No bills yet" is NOT rendered and an element with `role="alert"` IS rendered. VERIFY: `cd billwatch-web && npx vitest run src/views/__tests__/FollowingView.error.test.ts`. (cat:test; multifile:no) [feat:billwatch-20261102-show-a-failed-load-error-with-retry-on-t]
- [ ] [T1] billwatch-web/src/views/__tests__/FollowingView.error.test.ts — Add test case verifying that clicking the Retry button triggers `billsStore.fetchFollowedBills` again. VERIFY: `cd billwatch-web && npx vitest run src/views/__tests__/FollowingView.error.test.ts`. (cat:test; multifile:no) [feat:billwatch-20261102-show-a-failed-load-error-with-retry-on-t]
- [ ] [T1] billwatch-web/src/views/__tests__/FollowingView.error.test.ts — Add test case verifying that when `billsStore.error` is null and bills list is empty, the empty state text "No bills yet" IS rendered. VERIFY: `cd billwatch-web && npx vitest run src/views/__tests__/FollowingView.error.test.ts`. (cat:test; multifile:no) [feat:billwatch-20261102-show-a-failed-load-error-with-retry-on-t]
