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
- [ ] [T1] billwatch-backend/app/services/congress.py — `CongressClient` (78-line httpx client for `fetch_bills`/`fetch_bill_details`/`fetch_legislators` against `api.congress.gov/v3`) has full dedicated unit tests (`tests/test_congress_client.py`, 100% line coverage per `--cov` run) but is never instantiated by any router, service, or job in the actual app — `grep -rln "CongressClient" app/routers/ app/services/ app/jobs/` (excluding `congress.py` itself) returns nothing. The real, actively-used Congress.gov client wired into production is `app/services/congress_api.py` (476 lines, imported by `bills.py`, `legislators.py`, `vote_sync_service.py`, `bill_sync_service.py`, `bill_sponsor_sync_service.py`, `civic_api.py`, `legislator_sync_service.py`) — `congress.py` is a fully-tested but production-orphaned parallel implementation. Delete `app/services/congress.py` and its dedicated test, or confirm intent and document why a second client exists. VERIFY: `cd billwatch-backend && grep -rln "CongressClient" app/routers/ app/services/ app/jobs/ | grep -v congress.py` (currently empty — confirms no production caller), then after deletion `.venv/bin/python -c "from app.main import app; print('imports OK')"` still succeeds. (cat:backend; multifile:no) [feat:billwatch-20260924-orphaned-code-and-coverage-gaps]
- [ ] [T2] billwatch-backend/app/services/bill_summary.py — `apply_embedding_to_bill(bill, vector)` (the whole 12-line file) sets `bill.embedding = vector`, but `models/bill.py` has no `embedding` column — it's a plain Python attribute, not a persisted field. The function is called by exactly one place in the whole repo: its own unit test (`tests/test_bill_summary_service.py:3,15`). No router, service, or job calls it — there is no real embedding/semantic-search feature wired to any endpoint. Either wire this into the actual bill-summary pipeline (`services/bill_summary_service.py`, which is the real, used module) with a real `embedding` column + migration, or delete the dead function and its isolated test. VERIFY: `cd billwatch-backend && grep -rn "apply_embedding_to_bill" app/ tests/` — currently only 2 hits (the def + its own test); after the fix either a real caller appears or both are gone, then `.venv/bin/python -m pytest tests/test_bill_summary_service.py -q` stays green (or the file is removed). (cat:backend; multifile:no) [feat:billwatch-20260924-orphaned-code-and-coverage-gaps]
- [ ] [T2] billwatch-backend/app/services/notification_service.py — `NotificationService` (183 lines: `_init_firebase`, `send_notification`, `send_pending_notifications`, `create_and_send`) is the real push-notification service invoked by `app/jobs/scheduler.py`'s notification-sending job, but there is no `tests/test_notification_service.py` (or any test file) that imports or exercises this class directly — `grep -rln "NotificationService" tests/ --include='*.py'` returns nothing (confirmed the class name only shows up in a stale `__pycache__` artifact, not any real `.py` source file). Add tests covering `send_notification` (Firebase configured vs not), `send_pending_notifications`'s batching/error branch, and `create_and_send`. VERIFY: `cd billwatch-backend && grep -rln "NotificationService" tests/ --include='*.py'` (currently empty), then after adding tests `.venv/bin/python -m pytest tests/test_notification_service.py -q --cov=app.services.notification_service --cov-report=term-missing`. (cat:test; multifile:no) [feat:billwatch-20260924-orphaned-code-and-coverage-gaps]
- [ ] [T2] billwatch-backend/app/routers/career_history.py — `get_career_timeline` (`/legislators/{id}/career-timeline`, line 91) is the filtered-timeline endpoint with real `start_year`/`end_year`/`event_types` query-param filtering logic (lines 103-113), but `tests/test_career_history.py` only has a 404-for-unknown-legislator test for this endpoint (`test_career_timeline_endpoint_404_for_unknown_legislator`, line 107) — no test exercises the actual success path or any of the 3 filter params. Add tests for: a legislator with events across multiple years filtered by `start_year`/`end_year`, and filtering by `event_types=election` vs `event_types=bill`. VERIFY: `cd billwatch-backend && grep -n 'def test_' tests/test_career_history.py` shows a new filter-covering test, then `.venv/bin/python -m pytest tests/test_career_history.py -q --cov=app.routers.career_history --cov-report=term-missing`. (cat:test; multifile:no) [feat:billwatch-20260924-orphaned-code-and-coverage-gaps]
- [ ] [T2] billwatch-backend/app/jobs/scheduler.py — `check_saved_searches_job`, `sync_committees_job`, and `sync_votes_job` (lines 134/190/217) are real APScheduler-invoked background jobs re-verified as still having zero test coverage — `tests/test_background_scheduler.py` and `tests/test_summary_scheduler.py` exist but only cover other jobs, and `grep -rln "check_saved_searches_job\|sync_committees_job\|sync_votes_job" tests/` returns nothing. Add tests mocking `SavedSearchService.check_all_notifying`, `CommitteeSyncService.sync_all`, and `VoteSyncService.sync_votes` to verify both the success-logging branch and the `except Exception` branch run without raising. VERIFY: `cd billwatch-backend && grep -rln "check_saved_searches_job\|sync_committees_job\|sync_votes_job" tests/` (currently empty), then `.venv/bin/python -m pytest tests/test_background_scheduler.py -q --cov=app.jobs.scheduler --cov-report=term-missing`. (cat:test; multifile:no) [feat:billwatch-20260924-orphaned-code-and-coverage-gaps]
- [ ] [T2] billwatch-backend/app/services/civic_api.py — `GoogleCivicAPIClient._get_state_legislators_from_openstates()` (line 470, ~115 lines, called from `find_my_representatives` at line 249) re-verified as still having zero test coverage — `grep -rln "openstates\|_get_state_legislators_from_openstates" tests/` returns nothing. Add tests covering: no `OPEN_STATES_API_KEY` configured (`app/config.py:81`, graceful empty-result fallback, not a crash), a successful mocked Open States response, and an `httpx.HTTPStatusError`. VERIFY: `cd billwatch-backend && grep -rln "openstates" tests/` (currently empty), then `.venv/bin/python -m pytest tests/test_civic_api.py -q --cov=app.services.civic_api --cov-report=term-missing`. (cat:test; multifile:no) [feat:billwatch-20260924-orphaned-code-and-coverage-gaps]
- [ ] [T2] billwatch-backend/app/routers/votes.py — `compare_legislator_votes` (`GET /api/votes/comparison`, line 205) re-verified as still missing tests for its 3 error branches: more than 10 bioguide ids raising `InvalidLegislatorIDs` (line 226), an unknown bioguide id raising `LegislatorNotFound` (line 238), and a `bill_id` that matches no bill's `congress_id` raising `BillNotFound` (line 247) — `tests/test_votes_comparison.py` only covers the empty-list and duplicate-id `InvalidLegislatorIDs` cases (lines 121, 132). Add tests for the 3 missing branches. VERIFY: `cd billwatch-backend && grep -n 'LegislatorNotFound\|BillNotFound' tests/test_votes_comparison.py` (currently empty), then `.venv/bin/python -m pytest tests/test_votes_comparison.py -q --cov=app.routers.votes --cov-report=term-missing`. (cat:test; multifile:no) [feat:billwatch-20260924-orphaned-code-and-coverage-gaps]
- [ ] [T2] billwatch-backend/app/models/committee.py + app/schemas/committee.py + app/routers/committees.py — the dead "committee meetings" sub-feature re-verified as still present and still disconnected: the `CommitteeMeeting` SQLAlchemy model (`models/committee.py:75`, table `committee_meetings`) is never written to by any service/job (`grep -rn "CommitteeMeeting" app/services/ app/jobs/` is empty); the same-named Pydantic `CommitteeMeeting` schema (`schemas/committee.py:23`) has an incompatible shape (`chamber`/`time`/`bill_numbers`/`status`) vs. the model (`external_id`/`committee_id`/`date`/`title`) and is only ever built with literal data in its own isolated test (`tests/test_committee_schema.py`); `filter_meetings_for_followed_bills()` (`routers/committees.py:23`) is called by no endpoint, only by `tests/test_committees_router.py:100`. Delete the unused schema class and dead helper (flag the never-read model+table for a follow-up drop decision). VERIFY: `cd billwatch-backend && grep -rn "CommitteeMeeting\|filter_meetings_for_followed_bills" app/ tests/` to see what's touched, then after cleanup `.venv/bin/python -m pytest tests/test_committee_schema.py tests/test_committees_router.py -q` (delete the now-pointless test cases along with the code) and the full suite stays green. (cat:backend; multifile:yes) [feat:billwatch-20260924-orphaned-code-and-coverage-gaps]
- [ ] [T1] billwatch-backend/app/schemas/alerts.py + app/services/alert_service.py — re-verified as still dead: `BillAlertCreateRequest` in `schemas/alerts.py:4` is imported at `services/alert_service.py:12` but never referenced again anywhere in that 217-line file (an unused import — `AlertService.create_alert()` takes plain keyword args, not a schema object), and `routers/alerts.py` doesn't import it either (it defines its own inline `BillAlertCreate`/`BillAlertUpdate`/`BillAlertResponse`). The actually-used `BillAlertCreateRequest` (imported by `routers/analytics.py` and `services/bill_alert_service.py`) is a differently-shaped class in `app/schemas/analytics.py:71`. Delete the unused import in `alert_service.py` and delete the orphaned `app/schemas/alerts.py` module. VERIFY: `cd billwatch-backend && grep -n "BillAlertCreateRequest" app/services/alert_service.py` (currently shows the unused import line), then after the fix `grep -rn "schemas.alerts\b" app/ tests/` shows no results, and `.venv/bin/python -m pytest tests/test_alert_service.py tests/test_alerts_router.py -q` stays green. (cat:backend; multifile:yes) [feat:billwatch-20260924-orphaned-code-and-coverage-gaps]
- [ ] [T2] billwatch-backend/app/schemas/analytics.py + app/schemas/bill.py + app/schemas/bill_chat.py — `BillSummaryResponse` re-verified as still defined 3 separate times with 3 incompatible shapes: `schemas/analytics.py:10` (`id, bill_id, summary_text, key_points: List[str]|None, generated_at`), `schemas/bill.py:97` (`bill_id, summary, key_points: list[str], impact_analysis, model, created_at, cached`), and `schemas/bill_chat.py:45` (`id, bill_id, summary, key_points: Optional[str]` — a single string, not a list — `impact_analysis, model, created_at`). Each router currently imports its own module's version so nothing is broken today, but the identical class name with divergent field sets (including the `key_points` list-vs-string mismatch) is a landmine for the next consolidation attempt. Rename to disambiguate (e.g. `AnalyticsBillSummaryResponse` / keep `BillSummaryResponse` on `bill.py` as canonical / `ChatBillSummaryResponse`), updating router imports. VERIFY: `cd billwatch-backend && grep -rn "class BillSummaryResponse" app/schemas/*.py` shows exactly 1 result after the rename, then `.venv/bin/python -m pytest tests/test_analytics_router.py tests/test_bills.py tests/test_bill_chat_router.py -q` (adjust to the actual bill_chat test filename) stays green. (cat:backend; multifile:yes) [feat:billwatch-20260924-orphaned-code-and-coverage-gaps]
- [ ] [T3] billwatch-backend/app/routers/auth.py — `PATCH /api/auth/me/settings` (`update_user_settings`, line 290, using `UserSettingsUpdate`) re-verified as still called by zero clients: `grep -rn "me/settings" ../billwatch-web/src ../billwatch-ios/BillWatch ../billwatch-android/app/src/main` returns nothing on any of the 3 platforms. `display_name`, `dark_mode`, and `language` have no other endpoint that sets them (unlike `notification_prefs` via `/me/notifications`, `address` via `/me/address`), so there is currently no way for a user to change display name, dark-mode preference, or language from any client. Either wire a real UI control on at least one client to call this endpoint, or explicitly document it as intentionally unshipped. VERIFY: `cd billwatch-backend && grep -rn "me/settings" ../billwatch-web/src ../billwatch-ios/BillWatch ../billwatch-android/app/src/main` (currently empty; should show at least one caller after the fix, or a doc note), then `.venv/bin/python -m pytest tests/test_auth_settings.py -q` stays green. (cat:backend; multifile:yes) [feat:billwatch-20260924-orphaned-code-and-coverage-gaps]
- [ ] [T2] billwatch-web/src/views/BillDetailView.vue — this 220-line view (bill header/status, follow-toggle wired to `billsStore.toggleFollow`, `analyticsService.trackBillView` on mount, `partyName`/`partyColor` mapping helpers, `cleanSummary` HTML-stripping computed, `recentActions` slice) re-verified as still having zero test coverage — `ls src/views/__tests__/` shows only `AlertsView.test.ts`, `FollowingView.test.ts`, `LoginView.test.ts`, `RegisterView.test.ts`, plus 2 a11y specs; no `BillDetailView.test.ts`. Add a unit test mounting the component with a mocked `useBillsStore`/`analyticsService`, covering the loading state, the follow/unfollow toggle, and the `partyName`/`partyColor`/`cleanSummary` pure-logic branches. VERIFY: `cd billwatch-web && npm run test -- BillDetailView`. (cat:test; multifile:no) [feat:billwatch-20260924-orphaned-code-and-coverage-gaps]
- [ ] [T2] billwatch-web/src/views/PremiumView.vue — this 130-line view drives the paid-upgrade flow (`useBillingStore`, `handleCheckout` → `store.startCheckout()` redirecting `window.location.href`, `handlePortal` for managing an active subscription, loading/error/billing-disabled/is_premium branch rendering) re-verified as still having zero test coverage — no `views/__tests__/PremiumView.test.ts` exists. Add a unit test mocking `useBillingStore` covering: the `billing_enabled: false` banner, the active-premium branch rendering "Manage Subscription", the non-premium upgrade branch, and that `handleCheckout`/`handlePortal` call the store methods and toggle `actionLoading`. VERIFY: `cd billwatch-web && npm run test -- PremiumView`. (cat:test; multifile:no) [feat:billwatch-20260924-orphaned-code-and-coverage-gaps]
