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
- [ ] [T2] billwatch-backend/tests/test_rate_limiting.py — Add a test that asserts `users.follow_bill` (or equivalent write endpoint) has the `limiter.limit` decorator applied. VERIFY: `pytest billwatch-backend/tests/test_rate_limiting.py::test_users_follow_limited -v` (cat:test; multifile:no) [feat:billwatch-20261019-rate-limit-ranking-py-and-users-py-ranki]

# --- 27B-decomposed from roadmap [2026-10-19]: iOS uses /api/alerts and web uses /api/analytics/alerts — both write to the same BillAlert (review + tweak) [feat:billwatch-20261019-ios-uses-api-alerts-and-web-uses-api-ana] ---
- [ ] [T2] billwatch-backend/app/models/analytics.py — Add `notify_on_match: Mapped[bool] = mapped_column(Boolean, default=True)` and `sponsor_states: Mapped[list[str]] = mapped_column(JSON, default=list)` to the `BillAlert` model. VERIFY: `cd billwatch-backend && python -c "from app.models.analytics import BillAlert; assert hasattr(BillAlert, 'notify_on_match') and hasattr(BillAlert, 'sponsor_states')"`. (cat:schema; multifile:no) [feat:billwatch-20261019-ios-uses-api-alerts-and-web-uses-api-ana]
- [ ] [T2] billwatch-backend/alembic/versions/0006_add_alert_unified_fields.py — Create migration adding `notify_on_match` (Boolean, default True) and `sponsor_states` (JSON, default []) columns to the `bill_alerts` table. VERIFY: `cd billwatch-backend && alembic upgrade head && python -c "import sqlalchemy; e=sqlalchemy.create_engine('sqlite://'); c=e.connect(); print(c.execute(sqlalchemy.text('PRAGMA table_info(bill_alerts)')).fetchall())" | grep notify_on_match`. (cat:schema; multifile:no) [feat:billwatch-20261019-ios-uses-api-alerts-and-web-uses-api-ana]
- [ ] [T3] billwatch-backend/app/services/bill_alert_service.py — Update `create_alert` and `update_alert` methods to accept and persist `notify_on_match` and `sponsor_states`, ensuring they are saved to the `BillAlert` model instance. VERIFY: `cd billwatch-backend && pytest tests/test_bill_alert_service.py -k "test_create_alert_with_unified_fields" -v`. (cat:python; multifile:no) [feat:billwatch-20261019-ios-uses-api-alerts-and-web-uses-api-ana]
- [ ] [T3] billwatch-backend/app/routers/analytics.py — Modify the `/api/analytics/alerts` POST and PUT endpoints to accept `notify_on_match` and `sponsor_states` in the request body and pass them to `BillAlertService`. VERIFY: `cd billwatch-backend && python -c "from app.routers.analytics import router; routes=[r.path for r in router.routes]; assert '/api/analytics/alerts' in routes"`. (cat:endpoint; multifile:no) [feat:billwatch-20261019-ios-uses-api-alerts-and-web-uses-api-ana]
- [ ] [T3] billwatch-backend/app/routers/alerts.py — Modify the `/api/alerts` POST and PUT endpoints to accept `notify_on_match` and `sponsor_states`, and update the response schema to include these fields. VERIFY: `cd billwatch-backend && python -c "from app.routers.alerts import router; routes=[r.path for r in router.routes]; assert '/api/alerts' in routes"`. (cat:endpoint; multifile:no) [feat:billwatch-20261019-ios-uses-api-alerts-and-web-uses-api-ana]
- [ ] [T4] billwatch-backend/app/schemas/bill.py — Add `notify_on_match: bool = True` and `sponsor_states: list[str] = []` to `BillAlertCreate` and `BillAlertUpdate` schemas. VERIFY: `cd billwatch-backend && python -c "from app.schemas.bill import BillAlertCreate; s=BillAlertCreate(bill_id='1', notify_on_match=False); assert s.notify_on_match == False"`. (cat:schema; multifile:no) [feat:billwatch-20261019-ios-uses-api-alerts-and-web-uses-api-ana]
- [ ] [T4] billwatch-backend/app/services/alert_service.py — Update `create_alert` and `update_alert` to map incoming `notify_on_match` and `sponsor_states` to the `BillAlert` model fields, ensuring consistency with `BillAlertService`. VERIFY: `cd billwatch-backend && pytest tests/test_alert_service.py -k "test_unified_fields_persistence" -v`. (cat:python; multifile:no) [feat:billwatch-20261019-ios-uses-api-alerts-and-web-uses-api-ana]
- [ ] [T5] billwatch-backend/app/routers/alerts.py — Deprecate the `/api/alerts` endpoints by adding a `DeprecationWarning` log and redirecting logic to use `BillAlertService` internally, or return 410 Gone if fully migrating (choose redirect for compatibility). VERIFY: `cd billwatch-backend && pytest tests/test_alerts_deprecation.py -v`. (cat:endpoint; multifile:yes) [feat:billwatch-20261019-ios-uses-api-alerts-and-web-uses-api-ana]

# --- 27B-decomposed from roadmap [2026-10-19]: Rate-limit priority_api.py — app/routers/priority_api.py has no `limiter` import (grep: ze (review + tweak) [feat:billwatch-20261019-rate-limit-priority-api-py-app-routers-p] ---
- [ ] [T3] billwatch-backend/app/routers/priority_api.py — Add `from app.core.limiter import limiter` import and apply `@limiter.limit("120/minute")` decorator to the `get_dashboard`, `get_bills_requiring_action`, `get_recommendations`, and `get_statistics` endpoint functions. VERIFY: `grep -c "@limiter.limit(\"120/minute\")" billwatch-backend/app/routers/priority_api.py` returns 4. (cat:python; multifile:no) [feat:billwatch-20261019-rate-limit-priority-api-py-app-routers-p]
- [ ] [T3] billwatch-backend/app/routers/priority_api.py — Apply `@limiter.limit("30/minute")` decorator to the `set_bill_priority` and `create_alert` endpoint functions. VERIFY: `grep -c "@limiter.limit(\"30/minute\")" billwatch-backend/app/routers/priority_api.py` returns 2. (cat:python; multifile:no) [feat:billwatch-20261019-rate-limit-priority-api-py-app-routers-p]
- [ ] [T1] billwatch-backend/tests/test_priority_api_rate_limit.py — Create test file with a test that uses `TestClient` to make 31 consecutive POST requests to `/api/priorities/bills/1/priority` and asserts the 31st response status code is 429. VERIFY: `pytest billwatch-backend/tests/test_priority_api_rate_limit.py::test_write_rate_limit -v` passes. (cat:test; multifile:no) [feat:billwatch-20261019-rate-limit-priority-api-py-app-routers-p]
- [ ] [T1] billwatch-backend/tests/test_priority_api_rate_limit.py — Add a test that uses `TestClient` to make 121 consecutive GET requests to `/api/priorities/dashboard` and asserts the 121st response status code is 429. VERIFY: `pytest billwatch-backend/tests/test_priority_api_rate_limit.py::test_read_rate_limit -v` passes. (cat:test; multifile:no) [feat:billwatch-20261019-rate-limit-priority-api-py-app-routers-p]
