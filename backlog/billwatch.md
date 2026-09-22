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
- [ ] [T1] billwatch-backend/tests/test_advanced_auth_router.py — Create the test file with fixtures imports (`client`, `authenticated_client` from conftest) and a happy-path test asserting `GET /api/advanced/login-history` returns 200 with an `events` key in the JSON body via `authenticated_client`. VERIFY: `pytest billwatch-backend/tests/test_advanced_auth_router.py -v`. (cat:python; multifile:no) [feat:billwatch-20260922-advanced-auth-router-login-history-tests]
- [ ] [T1] billwatch-backend/tests/test_advanced_auth_router.py — Add a test case asserting `GET /api/advanced/login-history` returns 401/403 when called via the plain unauthenticated `client` fixture (no Authorization header), covering the router's `Depends(get_current_user)` wiring. VERIFY: `pytest billwatch-backend/tests/test_advanced_auth_router.py -v -k unauthorized`. (cat:python; multifile:no) [feat:billwatch-20260922-advanced-auth-router-login-history-tests]
- [ ] [T2] billwatch-backend/tests/test_advanced_auth_router.py — Add a test case for the `limit` query parameter's declared bounds (`Query(20, ge=1, le=100)`): assert `?limit=0` and `?limit=101` both return 422 via `authenticated_client`. VERIFY: `pytest billwatch-backend/tests/test_advanced_auth_router.py -v -k limit`. (cat:python; multifile:no) [feat:billwatch-20260922-advanced-auth-router-login-history-tests]
- [ ] [T2] billwatch-backend/tests/test_advanced_auth_router.py — Add a test case that records two login events for the authenticated test user via `SecurityAuditService` against `db_session`, then asserts `GET /api/advanced/login-history` returns both, serialized via `SecurityAuditService.serialize`, ordered most-recent-first. VERIFY: `pytest billwatch-backend/tests/test_advanced_auth_router.py -v -k history`. (cat:python; multifile:no) [feat:billwatch-20260922-advanced-auth-router-login-history-tests]
- [ ] [T1] billwatch-backend/tests/test_advanced_auth_router.py — Full-file check: run every test case in the file together (not filtered individually) and confirm all pass with no fixture ordering issues. VERIFY: `pytest billwatch-backend/tests/test_advanced_auth_router.py -v`. (cat:python; multifile:no) [feat:billwatch-20260922-advanced-auth-router-login-history-tests]

# --- 27B-decomposed from roadmap [2026-09-22 refuel round 3]: Add router-level tests for app/routers/priority_api.py — all 6 endpoints have zero route-level coverage (only the underlying TrackedBillPriority service is tested) (review + tweak) [feat:billwatch-20260922-priority-api-router-tests] ---
- [ ] [T1] billwatch-backend/tests/test_priority_api_router.py — Create the test file with fixtures imports and a happy-path test for `POST /api/priorities/bills/{bill_id}/priority` (body `{"priority": "high"}`) against a Bill row seeded via `db_session`, using `authenticated_client`, asserting 200. VERIFY: `pytest billwatch-backend/tests/test_priority_api_router.py -v`. (cat:python; multifile:no) [feat:billwatch-20260922-priority-api-router-tests]
- [ ] [T2] billwatch-backend/tests/test_priority_api_router.py — Add a test case for `POST .../priority` with an invalid `priority` value (e.g. `"urgent"`), asserting the router's `except ValueError` branch returns 400 with a detail message listing the valid `PriorityLevel` values. VERIFY: `pytest billwatch-backend/tests/test_priority_api_router.py -v -k invalid_priority`. (cat:python; multifile:no) [feat:billwatch-20260922-priority-api-router-tests]
- [ ] [T1] billwatch-backend/tests/test_priority_api_router.py — Add a test case asserting `POST .../priority` returns 401/403 when called via the unauthenticated `client` fixture. VERIFY: `pytest billwatch-backend/tests/test_priority_api_router.py -v -k unauthorized`. (cat:python; multifile:no) [feat:billwatch-20260922-priority-api-router-tests]
- [ ] [T1] billwatch-backend/tests/test_priority_api_router.py — Add a happy-path test for `GET /api/priorities/dashboard` via `authenticated_client`, asserting 200 and a dict response body. VERIFY: `pytest billwatch-backend/tests/test_priority_api_router.py -v -k dashboard`. (cat:python; multifile:no) [feat:billwatch-20260922-priority-api-router-tests]
- [ ] [T1] billwatch-backend/tests/test_priority_api_router.py — Add a happy-path test for `GET /api/priorities/bills-requiring-action` using the default `days_ahead=7`, asserting 200. VERIFY: `pytest billwatch-backend/tests/test_priority_api_router.py -v -k bills_requiring_action_default`. (cat:python; multifile:no) [feat:billwatch-20260922-priority-api-router-tests]
- [ ] [T2] billwatch-backend/tests/test_priority_api_router.py — Add a test case for `GET .../bills-requiring-action?days_ahead=30`, asserting the request succeeds with the explicit override (distinct from the default-value case above). VERIFY: `pytest billwatch-backend/tests/test_priority_api_router.py -v -k bills_requiring_action_override`. (cat:python; multifile:no) [feat:billwatch-20260922-priority-api-router-tests]
- [ ] [T1] billwatch-backend/tests/test_priority_api_router.py — Add a happy-path test for `POST /api/priorities/alerts` with a valid `CreateAlertRequest` body (`alert_type: "vote_scheduled"`), asserting 200. VERIFY: `pytest billwatch-backend/tests/test_priority_api_router.py -v -k create_alert`. (cat:python; multifile:no) [feat:billwatch-20260922-priority-api-router-tests]
- [ ] [T1] billwatch-backend/tests/test_priority_api_router.py — Add a happy-path test for `GET /api/priorities/recommendations`, asserting 200 and a list response body. VERIFY: `pytest billwatch-backend/tests/test_priority_api_router.py -v -k recommendations`. (cat:python; multifile:no) [feat:billwatch-20260922-priority-api-router-tests]
- [ ] [T1] billwatch-backend/tests/test_priority_api_router.py — Add a happy-path test for `GET /api/priorities/statistics`, asserting 200 and a dict response body. VERIFY: `pytest billwatch-backend/tests/test_priority_api_router.py -v -k statistics`. (cat:python; multifile:no) [feat:billwatch-20260922-priority-api-router-tests]
- [ ] [T2] billwatch-backend/tests/test_priority_api_router.py — Add a single parametrized/looped test case asserting all 6 priority_api endpoints (priority, dashboard, bills-requiring-action, alerts, recommendations, statistics) return 401/403 rather than 200 when called via the unauthenticated `client` fixture, closing the auth-wiring gap across the whole router in one pass. VERIFY: `pytest billwatch-backend/tests/test_priority_api_router.py -v -k all_endpoints_require_auth`. (cat:python; multifile:no) [feat:billwatch-20260922-priority-api-router-tests]
- [ ] [T1] billwatch-backend/tests/test_priority_api_router.py — Full-file check: run every test case in the file together and confirm all pass with no fixture ordering issues. VERIFY: `pytest billwatch-backend/tests/test_priority_api_router.py -v`. (cat:python; multifile:no) [feat:billwatch-20260922-priority-api-router-tests]

# --- 27B-decomposed from roadmap [2026-09-22 refuel round 3]: Add router-level tests for app/routers/bill_chat.py — POST/GET /api/bills/{bill_id}/chat have ZERO test coverage of any kind (review + tweak) [feat:billwatch-20260922-bill-chat-router-tests] ---
- [ ] [T1] billwatch-backend/tests/test_bill_chat_router.py — Create the test file, mocking `app.routers.bill_chat.llm_service.moderate_comment` (patched to return `{"status": "approved", "confidence": 0.99}`), seed a Bill row via `db_session`, and add a happy-path test for `POST /api/bills/{bill_id}/chat` via `authenticated_client` asserting 200 and the response's `content` echoes the posted message. VERIFY: `pytest billwatch-backend/tests/test_bill_chat_router.py -v`. (cat:python; multifile:no) [feat:billwatch-20260922-bill-chat-router-tests]
- [ ] [T1] billwatch-backend/tests/test_bill_chat_router.py — Add a test case for `POST /api/bills/{bill_id}/chat` against a non-existent `bill_id`, asserting 404 "Bill not found" per the router's own `if not bill` branch. VERIFY: `pytest billwatch-backend/tests/test_bill_chat_router.py -v -k post_bill_not_found`. (cat:python; multifile:no) [feat:billwatch-20260922-bill-chat-router-tests]
- [ ] [T1] billwatch-backend/tests/test_bill_chat_router.py — Add a test case asserting `POST .../chat` returns 401/403 via the unauthenticated `client` fixture (the route hard-requires `get_current_user`, unlike the GET route below). VERIFY: `pytest billwatch-backend/tests/test_bill_chat_router.py -v -k post_unauthorized`. (cat:python; multifile:no) [feat:billwatch-20260922-bill-chat-router-tests]
- [ ] [T2] billwatch-backend/tests/test_bill_chat_router.py — Add a test case where the mocked `moderate_comment` returns `{"status": "hidden", "reason": "harassment", "confidence": 0.9}`, asserting the created `BillMessage` row still persists (200 response) but with `moderation_status == "hidden"` — the router persists-but-marks-hidden rather than rejecting the post outright. VERIFY: `pytest billwatch-backend/tests/test_bill_chat_router.py -v -k moderation_hidden`. (cat:python; multifile:no) [feat:billwatch-20260922-bill-chat-router-tests]
- [ ] [T1] billwatch-backend/tests/test_bill_chat_router.py — Add a test case for `GET /api/bills/{bill_id}/chat` against a non-existent `bill_id`, asserting 404. VERIFY: `pytest billwatch-backend/tests/test_bill_chat_router.py -v -k get_bill_not_found`. (cat:python; multifile:no) [feat:billwatch-20260922-bill-chat-router-tests]
- [ ] [T1] billwatch-backend/tests/test_bill_chat_router.py — Add a happy-path test for `GET .../chat`: seed 2 non-hidden `BillMessage` rows via `db_session`, call the route (auth optional per `get_current_user_optional`), and assert 200, `message_count == 2`, and messages ordered by `created_at` descending. VERIFY: `pytest billwatch-backend/tests/test_bill_chat_router.py -v -k get_happy_path`. (cat:python; multifile:no) [feat:billwatch-20260922-bill-chat-router-tests]
- [ ] [T2] billwatch-backend/tests/test_bill_chat_router.py — Add a test case seeding one `moderation_status="approved"` and one `moderation_status="hidden"` message, asserting `GET .../chat` excludes the hidden one from both the `messages` list and `message_count` (the router filters via `cast(moderation_status, String) != "hidden"`). VERIFY: `pytest billwatch-backend/tests/test_bill_chat_router.py -v -k excludes_hidden`. (cat:python; multifile:no) [feat:billwatch-20260922-bill-chat-router-tests]
- [ ] [T2] billwatch-backend/tests/test_bill_chat_router.py — Add a test case for `GET .../chat?filtered=true`, mocking `llm_service.filter_comment_tone` to return a fixed string, asserting the returned message's `content` equals the mocked filtered text (not the raw `content`) and that `filtered_content` gets persisted (verify via a second call not re-invoking the mock, or by checking `db_session` state). VERIFY: `pytest billwatch-backend/tests/test_bill_chat_router.py -v -k filtered_tone`. (cat:python; multifile:no) [feat:billwatch-20260922-bill-chat-router-tests]
- [ ] [T1] billwatch-backend/tests/test_bill_chat_router.py — Full-file check: run every test case in the file together and confirm all pass with no fixture/mock ordering issues. VERIFY: `pytest billwatch-backend/tests/test_bill_chat_router.py -v`. (cat:python; multifile:no) [feat:billwatch-20260922-bill-chat-router-tests]

# --- 27B-decomposed from roadmap [2026-09-22 refuel round 3]: Finish deleting the orphaned billwatch-web/src/api/ directory — client.ts + its test are the two files left over from a partially-landed 2026-09-21 cleanup (review + tweak) [feat:billwatch-20260922-finish-orphaned-api-dir-cleanup] ---
- [ ] [T1] billwatch-web/src/api/client.ts — Delete the file entirely: it is a gutted re-export (`deleteAccount()` calling `api.delete('/export/account')`) with zero remaining callers anywhere under src/ outside its own directory (verified via repo-wide grep for `api/client`), fully superseded by `DeleteAccountButton.vue`'s direct `api.delete('/auth/me')` call. VERIFY: `test ! -f billwatch-web/src/api/client.ts && echo OK`. (cat:typescript; multifile:no) [feat:billwatch-20260922-finish-orphaned-api-dir-cleanup]
- [ ] [T1] billwatch-web/src/api/__tests__/client.test.ts — Delete the test file for the now-deleted client.ts module (it only tests the orphaned re-export and would fail to import a nonexistent module once client.ts is gone). VERIFY: `test ! -f billwatch-web/src/api/__tests__/client.test.ts && echo OK`. (cat:test; multifile:no) [feat:billwatch-20260922-finish-orphaned-api-dir-cleanup]

# --- 27B-decomposed from roadmap [2026-09-22 refuel round 3]: Add unit tests for Android SavedSearchesRepository + SavedSearchesViewModel — zero coverage today, same gap already fixed for Bills/Billing (review + tweak) [feat:billwatch-20260922-android-savedsearches-tests] ---
- [ ] [T1] billwatch-android/app/src/test/java/com/billwatch/data/repository/SavedSearchesRepositoryTest.kt — Create the test class with mockk setup for `BillWatchApi`, covering `getSavedSearches()` happy-path (`Result.success` with the api's `List<SavedSearch>`) and error-path (api throws -> `Result.failure`), mirroring `BillsRepositoryTest.kt`'s established pattern. VERIFY: `./gradlew :app:testDebugUnitTest --tests "com.billwatch.data.repository.SavedSearchesRepositoryTest"`. (cat:kotlin; multifile:no) [feat:billwatch-20260922-android-savedsearches-tests]
- [ ] [T1] billwatch-android/app/src/test/java/com/billwatch/data/repository/SavedSearchesRepositoryTest.kt — Add a test case for `createSavedSearch(request)` asserting it forwards the `SavedSearchCreateRequest` to `api.createSavedSearch` (via `coVerify`) and returns `Result.success` with the api's response. VERIFY: `./gradlew :app:testDebugUnitTest --tests "com.billwatch.data.repository.SavedSearchesRepositoryTest"`. (cat:kotlin; multifile:no) [feat:billwatch-20260922-android-savedsearches-tests]
- [ ] [T1] billwatch-android/app/src/test/java/com/billwatch/data/repository/SavedSearchesRepositoryTest.kt — Add a test case for `updateSavedSearch(id, request)` asserting both arguments are forwarded to `api.updateSavedSearch` and the method returns `Result.success`. VERIFY: `./gradlew :app:testDebugUnitTest --tests "com.billwatch.data.repository.SavedSearchesRepositoryTest"`. (cat:kotlin; multifile:no) [feat:billwatch-20260922-android-savedsearches-tests]
- [ ] [T1] billwatch-android/app/src/test/java/com/billwatch/data/repository/SavedSearchesRepositoryTest.kt — Add a test case for `deleteSavedSearch(id)` asserting `api.deleteSavedSearch(id)` is invoked exactly once and the method returns `Result.success(Unit)`. VERIFY: `./gradlew :app:testDebugUnitTest --tests "com.billwatch.data.repository.SavedSearchesRepositoryTest"`. (cat:kotlin; multifile:no) [feat:billwatch-20260922-android-savedsearches-tests]
- [ ] [T1] billwatch-android/app/src/test/java/com/billwatch/data/repository/SavedSearchesRepositoryTest.kt — Add a happy-path and a failure-path test case for `runSavedSearch(id)`, asserting `Result.success` with the api's `SavedSearchRunResponse` and `Result.failure` when the api throws. VERIFY: `./gradlew :app:testDebugUnitTest --tests "com.billwatch.data.repository.SavedSearchesRepositoryTest"`. (cat:kotlin; multifile:no) [feat:billwatch-20260922-android-savedsearches-tests]
- [ ] [T1] billwatch-android/app/src/test/java/com/billwatch/ui/screens/SavedSearchesViewModelTest.kt — Create the test class with mockk setup for `SavedSearchesRepository`, covering `loadSavedSearches()` populating the `savedSearches` StateFlow on success and setting `error` from the failure message on `Result.failure`. VERIFY: `./gradlew :app:testDebugUnitTest --tests "com.billwatch.ui.screens.SavedSearchesViewModelTest"`. (cat:kotlin; multifile:no) [feat:billwatch-20260922-android-savedsearches-tests]
- [ ] [T2] billwatch-android/app/src/test/java/com/billwatch/ui/screens/SavedSearchesViewModelTest.kt — Add a test case for `createSavedSearch(name, query, notify)` asserting the newly-created item is appended to the `savedSearches` StateFlow on success. VERIFY: `./gradlew :app:testDebugUnitTest --tests "com.billwatch.ui.screens.SavedSearchesViewModelTest"`. (cat:kotlin; multifile:no) [feat:billwatch-20260922-android-savedsearches-tests]
- [ ] [T2] billwatch-android/app/src/test/java/com/billwatch/ui/screens/SavedSearchesViewModelTest.kt — Add a test case for `runSavedSearch(id)` asserting `runningSearchId` is set to `id` during the call and cleared to null afterward, and `runResults` is populated from the repository's `SavedSearchRunResponse.results` on success. VERIFY: `./gradlew :app:testDebugUnitTest --tests "com.billwatch.ui.screens.SavedSearchesViewModelTest"`. (cat:kotlin; multifile:no) [feat:billwatch-20260922-android-savedsearches-tests]
- [ ] [T1] billwatch-android/app/src/test/java/com/billwatch/ui/screens/SavedSearchesViewModelTest.kt — Full-file check: run both new test files together and confirm every case passes. VERIFY: `./gradlew :app:testDebugUnitTest --tests "com.billwatch.data.repository.SavedSearchesRepositoryTest" --tests "com.billwatch.ui.screens.SavedSearchesViewModelTest"`. (cat:kotlin; multifile:yes) [feat:billwatch-20260922-android-savedsearches-tests]

# --- 27B-decomposed from roadmap [2026-09-22 refuel round 3]: Add unit tests for Android LegislatorsRepository + LegislatorsViewModel — zero coverage today, same gap already fixed for Bills/Billing (review + tweak) [feat:billwatch-20260922-android-legislators-tests] ---
- [ ] [T1] billwatch-android/app/src/test/java/com/billwatch/data/repository/LegislatorsRepositoryTest.kt — Create the test class with mockk setup for `BillWatchApi`, covering `searchLegislators()` happy-path with its default arguments (`query=null, chamber=null, party=null, state=null, page=1, pageSize=50`) forwarded to `api.searchLegislators`, and its error-path (api throws -> `Result.failure`), mirroring `BillsRepositoryTest.kt`'s pattern. VERIFY: `./gradlew :app:testDebugUnitTest --tests "com.billwatch.data.repository.LegislatorsRepositoryTest"`. (cat:kotlin; multifile:no) [feat:billwatch-20260922-android-legislators-tests]
- [ ] [T1] billwatch-android/app/src/test/java/com/billwatch/data/repository/LegislatorsRepositoryTest.kt — Add a test case for `getLegislator(bioguideId)` asserting it forwards `bioguideId` to `api.getLegislator` and returns `Result.success` with the api's `LegislatorDetail`. VERIFY: `./gradlew :app:testDebugUnitTest --tests "com.billwatch.data.repository.LegislatorsRepositoryTest"`. (cat:kotlin; multifile:no) [feat:billwatch-20260922-android-legislators-tests]
- [ ] [T2] billwatch-android/app/src/test/java/com/billwatch/data/repository/LegislatorsRepositoryTest.kt — Add test cases for `getLegislatorVotes(bioguideId, limit, offset)` and `getLegislatorMissedVotes(bioguideId, limit)` asserting each forwards its default `limit=50`/`offset=0` values to the api and returns `Result.success`. VERIFY: `./gradlew :app:testDebugUnitTest --tests "com.billwatch.data.repository.LegislatorsRepositoryTest"`. (cat:kotlin; multifile:no) [feat:billwatch-20260922-android-legislators-tests]
- [ ] [T1] billwatch-android/app/src/test/java/com/billwatch/data/repository/LegislatorsRepositoryTest.kt — Add test cases for `followLegislator(id)` and `unfollowLegislator(id)` asserting each invokes the corresponding api call exactly once (`coVerify`) and returns `Result.success(Unit)`. VERIFY: `./gradlew :app:testDebugUnitTest --tests "com.billwatch.data.repository.LegislatorsRepositoryTest"`. (cat:kotlin; multifile:no) [feat:billwatch-20260922-android-legislators-tests]
- [ ] [T2] billwatch-android/app/src/test/java/com/billwatch/data/repository/LegislatorsRepositoryTest.kt — Add test cases for `getLegislatorFinance(legislatorId, cycle)` and `refreshLegislatorFinance(legislatorId, cycle)` asserting both forward the optional `cycle` parameter to the api and handle the `cycle=null` default correctly. VERIFY: `./gradlew :app:testDebugUnitTest --tests "com.billwatch.data.repository.LegislatorsRepositoryTest"`. (cat:kotlin; multifile:no) [feat:billwatch-20260922-android-legislators-tests]
- [ ] [T1] billwatch-android/app/src/test/java/com/billwatch/ui/screens/LegislatorsViewModelTest.kt — Create the test class with mockk setup for `LegislatorsRepository`, covering `searchLegislators()` populating the `legislators` StateFlow on success (replacing, not appending, on page 1) and `loadMoreLegislators()` appending results when called with `currentPage > 1`. VERIFY: `./gradlew :app:testDebugUnitTest --tests "com.billwatch.ui.screens.LegislatorsViewModelTest"`. (cat:kotlin; multifile:no) [feat:billwatch-20260922-android-legislators-tests]
- [ ] [T2] billwatch-android/app/src/test/java/com/billwatch/ui/screens/LegislatorsViewModelTest.kt — Add a test case for `toggleFollowLegislator(id)` asserting it calls `followLegislator` when the id is not already in `followedLegislatorIds` and `unfollowLegislator` when it is, updating the StateFlow accordingly on success. VERIFY: `./gradlew :app:testDebugUnitTest --tests "com.billwatch.ui.screens.LegislatorsViewModelTest"`. (cat:kotlin; multifile:no) [feat:billwatch-20260922-android-legislators-tests]
- [ ] [T2] billwatch-android/app/src/test/java/com/billwatch/ui/screens/LegislatorsViewModelTest.kt — Add a test case for `fetchLegislatorFinance(legislatorId)` asserting `financeLoading` toggles true then false around the call, and `financeError` is set to the repository's failure message (or the fallback string) on `Result.failure`. VERIFY: `./gradlew :app:testDebugUnitTest --tests "com.billwatch.ui.screens.LegislatorsViewModelTest"`. (cat:kotlin; multifile:no) [feat:billwatch-20260922-android-legislators-tests]
- [ ] [T1] billwatch-android/app/src/test/java/com/billwatch/ui/screens/LegislatorsViewModelTest.kt — Full-file check: run both new test files together and confirm every case passes. VERIFY: `./gradlew :app:testDebugUnitTest --tests "com.billwatch.data.repository.LegislatorsRepositoryTest" --tests "com.billwatch.ui.screens.LegislatorsViewModelTest"`. (cat:kotlin; multifile:yes) [feat:billwatch-20260922-android-legislators-tests]
