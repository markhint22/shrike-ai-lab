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
- [ ] [T1] billwatch-web/src/stores/__tests__/billChat.test.ts — Delete this test file (its only subject, useBillChatStore, is now deleted). VERIFY: `test ! -f billwatch-web/src/stores/__tests__/billChat.test.ts`. (cat:web; multifile:no) [feat:billwatch-20260922-delete-billchat-store-dead-code]
- [ ] [T2] billwatch-web — Run the full web test suite to confirm nothing else depended on the deleted store or test file. VERIFY: `cd billwatch-web && npx vitest run 2>&1 | tail -20`. (cat:web; multifile:no) [feat:billwatch-20260922-delete-billchat-store-dead-code]

# --- Claude-decomposed from roadmap [2026-09-22 round 4]: Delete orphaned dead component billwatch-web/src/components/BillSummaryCard.vue — never imported anywhere (review + tweak) [feat:billwatch-20260922-delete-billsummarycard-dead-code] ---
- [ ] [T1] billwatch-web/src/components/BillSummaryCard.vue — Confirm zero references before deleting (the real, live summary component is the separate src/components/BillSummaryPanel.vue, imported by src/views/BillDetailView.vue). VERIFY: `cd billwatch-web && ! grep -rln "BillSummaryCard" src --include="*.vue" --include="*.ts" | grep -v "src/components/BillSummaryCard.vue"`. (cat:web; multifile:no) [feat:billwatch-20260922-delete-billsummarycard-dead-code]
- [ ] [T1] billwatch-web/src/components/BillSummaryCard.vue — Delete this orphaned 124-line component (no test file exists for it, so nothing else to remove). VERIFY: `test ! -f billwatch-web/src/components/BillSummaryCard.vue`. (cat:web; multifile:no) [feat:billwatch-20260922-delete-billsummarycard-dead-code]
- [ ] [T2] billwatch-web — Run the full web test suite plus the build to confirm nothing else referenced the deleted component. VERIFY: `cd billwatch-web && npx vitest run 2>&1 | tail -20 && npm run build 2>&1 | tail -20`. (cat:web; multifile:no) [feat:billwatch-20260922-delete-billsummarycard-dead-code]

# --- Claude-decomposed from roadmap [2026-09-22 round 4]: Delete unreachable dead component billwatch-web/src/components/BillCommentsSection.vue — not imported by any view, and its backend doesn't exist either (review + tweak) [feat:billwatch-20260922-delete-billcommentssection-dead-code] ---
- [ ] [T1] billwatch-web/src/components/BillCommentsSection.vue — Confirm this component is not imported by any view or component before deleting. VERIFY: `cd billwatch-web && ! grep -rln "BillCommentsSection" src --include="*.vue" | grep -v "src/components/BillCommentsSection.vue"`. (cat:web; multifile:no) [feat:billwatch-20260922-delete-billcommentssection-dead-code]
- [ ] [T1] billwatch-web/src/components/BillCommentsSection.vue — Delete this 97-line orphaned component (calls the double-prefixed, backend-less `/api/bills/${billId}/comments`, reads `route.params.id` without ever receiving a `billId` prop, and is not reachable from any route). VERIFY: `test ! -f billwatch-web/src/components/BillCommentsSection.vue`. (cat:web; multifile:no) [feat:billwatch-20260922-delete-billcommentssection-dead-code]
- [ ] [T2] billwatch-web — Run the full web test suite plus the build to confirm nothing else referenced the deleted component. VERIFY: `cd billwatch-web && npx vitest run 2>&1 | tail -20 && npm run build 2>&1 | tail -20`. (cat:web; multifile:no) [feat:billwatch-20260922-delete-billcommentssection-dead-code]

# --- Claude-decomposed from roadmap [2026-09-22 round 4]: Add unit tests for views/AlertsView.vue — real analyticsService-backed alert CRUD, zero coverage (review + tweak) [feat:billwatch-20260922-alertsview-tests] ---
- [ ] [T2] billwatch-web/src/views/__tests__/AlertsView.test.ts — Create this new test file mocking `@/services/analyticsService` (not raw api/axios, since AlertsView.vue calls the service directly) following the established `vi.mock` pattern used elsewhere in src/views/__tests__/. Cover: `loadAlerts()` populates `alerts` from `analyticsService.getUserAlerts()` on mount. VERIFY: `cd billwatch-web && npx vitest run src/views/__tests__/AlertsView.test.ts 2>&1 | grep -q "passed"`. (cat:web; multifile:no) [feat:billwatch-20260922-alertsview-tests]
- [ ] [T2] billwatch-web/src/views/__tests__/AlertsView.test.ts — Add a case asserting `submitAlert()`'s empty-keywords guard: with `newAlert.keywords` blank, submitting does NOT call `analyticsService.createAlert` (mock `window.alert` to avoid a real browser dialog in the test). VERIFY: `cd billwatch-web && npx vitest run src/views/__tests__/AlertsView.test.ts 2>&1 | grep -q "passed"`. (cat:web; multifile:no) [feat:billwatch-20260922-alertsview-tests]
- [ ] [T2] billwatch-web/src/views/__tests__/AlertsView.test.ts — Add a case asserting the create-vs-update branch: with `editingId` unset, submitting a valid alert calls `analyticsService.createAlert`; after calling `editAlert(existingAlert)` (setting `editingId`), submitting instead calls `analyticsService.updateAlert` with that id. VERIFY: `cd billwatch-web && npx vitest run src/views/__tests__/AlertsView.test.ts 2>&1 | grep -q "passed"`. (cat:web; multifile:no) [feat:billwatch-20260922-alertsview-tests]
- [ ] [T2] billwatch-web/src/views/__tests__/AlertsView.test.ts — Add a case asserting `editAlert()` pre-fills the form fields (name/keywords/policy_areas/chambers/notify flags) from the passed-in `BillAlert` and sets `showCreateForm` to true. VERIFY: `cd billwatch-web && npx vitest run src/views/__tests__/AlertsView.test.ts 2>&1 | grep -q "passed"`. (cat:web; multifile:no) [feat:billwatch-20260922-alertsview-tests]
- [ ] [T2] billwatch-web/src/views/__tests__/AlertsView.test.ts — Add cases for `toggleAlert(id)` calling `analyticsService.toggleAlert` then reloading, and `deleteAlertConfirm(id)` calling `analyticsService.deleteAlert` only when `window.confirm` is mocked to return true (and NOT calling it when mocked to return false). VERIFY: `cd billwatch-web && npx vitest run src/views/__tests__/AlertsView.test.ts 2>&1 | grep -q "passed"`. (cat:web; multifile:no) [feat:billwatch-20260922-alertsview-tests]
- [ ] [T1] billwatch-web/src/views/__tests__/AlertsView.test.ts — Add a case asserting `resetForm()` (triggered after a successful submit) clears all `newAlert` fields back to their defaults and sets `showCreateForm`/`editingId` back to falsy. VERIFY: `cd billwatch-web && npx vitest run src/views/__tests__/AlertsView.test.ts 2>&1 | grep -q "passed"`. (cat:web; multifile:no) [feat:billwatch-20260922-alertsview-tests]

# --- Claude-decomposed from roadmap [2026-09-22 round 4]: Add unit tests for views/RegisterView.vue — password-mismatch guard, terms gate, register+redirect flow, zero coverage (review + tweak) [feat:billwatch-20260922-registerview-tests] ---
- [ ] [T2] billwatch-web/src/views/__tests__/RegisterView.test.ts — Create this new test file mirroring LoginView.test.ts's `vi.mock('@/services/api', ...)` + `vi.mock('vue-router', () => ({ useRouter: () => ({ push: vi.fn() }) }))` pattern. Cover: successful registration (mocked `authStore.register` resolving true) navigates to '/'. VERIFY: `cd billwatch-web && npx vitest run src/views/__tests__/RegisterView.test.ts 2>&1 | grep -q "passed"`. (cat:web; multifile:no) [feat:billwatch-20260922-registerview-tests]
- [ ] [T2] billwatch-web/src/views/__tests__/RegisterView.test.ts — Add a case asserting `handleSubmit()`'s early-return guard: with `password !== confirmPassword`, submitting does NOT call `authStore.register` and does NOT navigate. VERIFY: `cd billwatch-web && npx vitest run src/views/__tests__/RegisterView.test.ts 2>&1 | grep -q "passed"`. (cat:web; multifile:no) [feat:billwatch-20260922-registerview-tests]
- [ ] [T2] billwatch-web/src/views/__tests__/RegisterView.test.ts — Add a case asserting `handleSubmit()`'s other early-return guard: with `agreedToTerms` false (even when passwords match), submitting does NOT call `authStore.register`. VERIFY: `cd billwatch-web && npx vitest run src/views/__tests__/RegisterView.test.ts 2>&1 | grep -q "passed"`. (cat:web; multifile:no) [feat:billwatch-20260922-registerview-tests]
- [ ] [T1] billwatch-web/src/views/__tests__/RegisterView.test.ts — Add a case asserting the password-mismatch `role="alert"` div only renders once BOTH `password` and `confirmPassword` are non-empty and they differ (not while either field is still empty). VERIFY: `cd billwatch-web && npx vitest run src/views/__tests__/RegisterView.test.ts 2>&1 | grep -q "passed"`. (cat:web; multifile:no) [feat:billwatch-20260922-registerview-tests]
- [ ] [T1] billwatch-web/src/views/__tests__/RegisterView.test.ts — Add a case asserting the submit button is `:disabled` when `authStore.isLoading` is true, when passwords mismatch, or when terms are not agreed — and enabled otherwise. VERIFY: `cd billwatch-web && npx vitest run src/views/__tests__/RegisterView.test.ts 2>&1 | grep -q "passed"`. (cat:web; multifile:no) [feat:billwatch-20260922-registerview-tests]

# --- Claude-decomposed from roadmap [2026-09-22 round 4]: Expand stores/__tests__/auth.test.ts — only login() is tested; register/saveAddress/logout/checkAuth/fetchCurrentUser-failure are untested (review + tweak) [feat:billwatch-20260922-authstore-expand-coverage] ---
- [ ] [T2] billwatch-web/src/stores/__tests__/auth.test.ts — Add a case for `register()` success: mocked `api.post('/auth/register', ...)` resolving with `{access_token, refresh_token}` followed by a mocked `api.get('/auth/me')`, asserting `register()` returns true and `accessToken`/`user` are populated, matching the existing `login` success test's structure. VERIFY: `cd billwatch-web && npx vitest run src/stores/__tests__/auth.test.ts 2>&1 | grep -q "passed"`. (cat:web; multifile:no) [feat:billwatch-20260922-authstore-expand-coverage]
- [ ] [T2] billwatch-web/src/stores/__tests__/auth.test.ts — Add a case for `register()` failure (mocked `api.post` rejecting), asserting `register()` returns false and `error` is set, matching the existing `login` failure test's structure. VERIFY: `cd billwatch-web && npx vitest run src/stores/__tests__/auth.test.ts 2>&1 | grep -q "passed"`. (cat:web; multifile:no) [feat:billwatch-20260922-authstore-expand-coverage]
- [ ] [T1] billwatch-web/src/stores/__tests__/auth.test.ts — Add a case for `saveAddress()` success: mocked `api.patch('/auth/me/address', {address})` resolving with an updated user object, asserting `saveAddress()` returns true and `store.user` reflects the response. VERIFY: `cd billwatch-web && npx vitest run src/stores/__tests__/auth.test.ts 2>&1 | grep -q "passed"`. (cat:web; multifile:no) [feat:billwatch-20260922-authstore-expand-coverage]
- [ ] [T1] billwatch-web/src/stores/__tests__/auth.test.ts — Add a case for `saveAddress()` failure (mocked `api.patch` rejecting), asserting it returns false and sets `error`. VERIFY: `cd billwatch-web && npx vitest run src/stores/__tests__/auth.test.ts 2>&1 | grep -q "passed"`. (cat:web; multifile:no) [feat:billwatch-20260922-authstore-expand-coverage]
- [ ] [T1] billwatch-web/src/stores/__tests__/auth.test.ts — Add a case for `logout()`: after setting a token/user, calling `logout()` clears `accessToken`/`user` and removes both localStorage keys. VERIFY: `cd billwatch-web && npx vitest run src/stores/__tests__/auth.test.ts 2>&1 | grep -q "passed"`. (cat:web; multifile:no) [feat:billwatch-20260922-authstore-expand-coverage]
- [ ] [T1] billwatch-web/src/stores/__tests__/auth.test.ts — Add a case for `fetchCurrentUser()`'s failure branch: mocked `api.get('/auth/me')` rejecting sets `user.value` to null rather than throwing. VERIFY: `cd billwatch-web && npx vitest run src/stores/__tests__/auth.test.ts 2>&1 | grep -q "passed"`. (cat:web; multifile:no) [feat:billwatch-20260922-authstore-expand-coverage]
- [ ] [T1] billwatch-web/src/stores/__tests__/auth.test.ts — Add a case for `checkAuth()`: when `isAuthenticated` is true it calls `fetchCurrentUser()` (assert `api.get` was invoked); when false (no token) it does not. VERIFY: `cd billwatch-web && npx vitest run src/stores/__tests__/auth.test.ts 2>&1 | grep -q "passed"`. (cat:web; multifile:no) [feat:billwatch-20260922-authstore-expand-coverage]

# --- Claude-decomposed from roadmap [2026-09-22 round 4]: Add direct unit tests for services/adminApi.ts and services/analyticsService.ts — only indirectly covered via other components' mocks (review + tweak) [feat:billwatch-20260922-adminapi-analyticsservice-direct-tests] ---
- [ ] [T2] billwatch-web/src/services/__tests__/adminApi.test.ts — Create this new test file mocking `./api` (same `vi.mock('@/services/api', ...)` shape as searchService.test.ts/legislatorService.test.ts) and asserting `adminApi.listUsers()` calls `api.get` with the literal path `/admin/users` (not `/api/admin/users` — pinning the exact double-prefix bug this file's own docstring says it exists to prevent) and resolves to `response.data`. VERIFY: `cd billwatch-web && npx vitest run src/services/__tests__/adminApi.test.ts 2>&1 | grep -q "passed"`. (cat:web; multifile:no) [feat:billwatch-20260922-adminapi-analyticsservice-direct-tests]
- [ ] [T1] billwatch-web/src/services/__tests__/adminApi.test.ts — Add a case for `adminApi.getStatistics()` asserting it calls `api.get` with `/admin/statistics`. VERIFY: `cd billwatch-web && npx vitest run src/services/__tests__/adminApi.test.ts 2>&1 | grep -q "passed"`. (cat:web; multifile:no) [feat:billwatch-20260922-adminapi-analyticsservice-direct-tests]
- [ ] [T1] billwatch-web/src/services/__tests__/adminApi.test.ts — Add a case for `adminApi.banUser(userId, reason)` asserting it calls `api.post` with `/admin/users/{userId}/ban` and body `{reason}`, including the default-reason branch when `reason` is omitted. VERIFY: `cd billwatch-web && npx vitest run src/services/__tests__/adminApi.test.ts 2>&1 | grep -q "passed"`. (cat:web; multifile:no) [feat:billwatch-20260922-adminapi-analyticsservice-direct-tests]
- [ ] [T2] billwatch-web/src/services/__tests__/analyticsService.test.ts — Create this new test file mocking `./api` and asserting `getTrendingBills`/`getPopularBills` call `api.get` with `/analytics/trending`/`/analytics/popular` and the correct `params` (days/limit), and `trackBillView(billId)` calls `api.post` with `/analytics/${billId}/views`. VERIFY: `cd billwatch-web && npx vitest run src/services/__tests__/analyticsService.test.ts 2>&1 | grep -q "passed"`. (cat:web; multifile:no) [feat:billwatch-20260922-adminapi-analyticsservice-direct-tests]
- [ ] [T1] billwatch-web/src/services/__tests__/analyticsService.test.ts — Add cases for `getUserAlerts`, `createAlert`, `updateAlert`, `deleteAlert`, and `toggleAlert`, each asserting the correct HTTP verb, path (`/analytics/alerts`, `/analytics/alerts/{id}`, `/analytics/alerts/{id}/toggle`), and body/params shape. VERIFY: `cd billwatch-web && npx vitest run src/services/__tests__/analyticsService.test.ts 2>&1 | grep -q "passed"`. (cat:web; multifile:no) [feat:billwatch-20260922-adminapi-analyticsservice-direct-tests]

# --- Claude-decomposed from roadmap [2026-09-22 round 4]: Add unit tests for the 3 untested Priority-Dashboard components — BillActionItem, BillPriorityItem, PriorityLevelCard (review + tweak) [feat:billwatch-20260922-priority-components-tests] ---
- [ ] [T1] billwatch-web/src/components/__tests__/BillActionItem.test.ts — Create this new test file mounting BillActionItem.vue and asserting: clicking the "View Bill" button emits `viewBill`, clicking "Set Priority" emits `setPriority`, and the `actionTypeLabel` map renders the correct label text for a given `actionType` prop. VERIFY: `cd billwatch-web && npx vitest run src/components/__tests__/BillActionItem.test.ts 2>&1 | grep -q "passed"`. (cat:web; multifile:no) [feat:billwatch-20260922-priority-components-tests]
- [ ] [T1] billwatch-web/src/components/__tests__/BillPriorityItem.test.ts — Create this new test file mounting BillPriorityItem.vue and asserting: each of the 4 `priority` prop values (critical/high/medium/low) renders its matching color class + icon from `priorityConfig`, the sponsor list truncates to the first 2 with a "+N more" suffix when `sponsors.length > 2`, and clicking the card emits `click`. VERIFY: `cd billwatch-web && npx vitest run src/components/__tests__/BillPriorityItem.test.ts 2>&1 | grep -q "passed"`. (cat:web; multifile:no) [feat:billwatch-20260922-priority-components-tests]
- [ ] [T1] billwatch-web/src/components/__tests__/PriorityLevelCard.test.ts — Create this new test file mounting PriorityLevelCard.vue and asserting the 3-way pluralization branch on `count`: `count === 0` renders "No bills at this priority level", `count === 1` renders "1 bill requires your attention", and `count >= 2` renders "N bills require your attention". VERIFY: `cd billwatch-web && npx vitest run src/components/__tests__/PriorityLevelCard.test.ts 2>&1 | grep -q "passed"`. (cat:web; multifile:no) [feat:billwatch-20260922-priority-components-tests]
- [ ] [T1] billwatch-web/src/components/__tests__/PriorityLevelCard.test.ts — Add a case asserting each of the 4 `level` prop values (critical/high/medium/low) renders its matching `levelConfig` icon/label/description/badge color. VERIFY: `cd billwatch-web && npx vitest run src/components/__tests__/PriorityLevelCard.test.ts 2>&1 | grep -q "passed"`. (cat:web; multifile:no) [feat:billwatch-20260922-priority-components-tests]

# --- Claude-decomposed from roadmap [2026-09-22 round 4]: Add a unit test for components/BillRankingCard.vue — 4-way urgency-state computed classes + record-activity emit, zero coverage (review + tweak) [feat:billwatch-20260922-billrankingcard-tests] ---
- [ ] [T1] billwatch-web/src/components/__tests__/BillRankingCard.test.ts — Create this new test file mounting BillRankingCard.vue with a mocked `bill` prop, asserting `urgencyColorClass`/`urgencyBadgeClass` render the correct classes for `urgency_state: 'rising'`. VERIFY: `cd billwatch-web && npx vitest run src/components/__tests__/BillRankingCard.test.ts 2>&1 | grep -q "passed"`. (cat:web; multifile:no) [feat:billwatch-20260922-billrankingcard-tests]
- [ ] [T1] billwatch-web/src/components/__tests__/BillRankingCard.test.ts — Add cases for `urgency_state: 'steady'` and `'cooling'`, each asserting the matching color/badge classes from the component's switch statements. VERIFY: `cd billwatch-web && npx vitest run src/components/__tests__/BillRankingCard.test.ts 2>&1 | grep -q "passed"`. (cat:web; multifile:no) [feat:billwatch-20260922-billrankingcard-tests]
- [ ] [T1] billwatch-web/src/components/__tests__/BillRankingCard.test.ts — Add a case for an unrecognized/default `urgency_state` value falling back to the `default:` branch's neutral classes. VERIFY: `cd billwatch-web && npx vitest run src/components/__tests__/BillRankingCard.test.ts 2>&1 | grep -q "passed"`. (cat:web; multifile:no) [feat:billwatch-20260922-billrankingcard-tests]
- [ ] [T1] billwatch-web/src/components/__tests__/BillRankingCard.test.ts — Add a case asserting `recordActivity(activityType)` emits `record-activity` with the payload `[bill.bill_id, activityType]`. VERIFY: `cd billwatch-web && npx vitest run src/components/__tests__/BillRankingCard.test.ts 2>&1 | grep -q "passed"`. (cat:web; multifile:no) [feat:billwatch-20260922-billrankingcard-tests]

# --- Claude-decomposed from roadmap [2026-09-22 round 4]: Add a functional (non-a11y) unit test for components/modals/ChangePriorityModal.vue — existing test only covers dialog semantics (review + tweak) [feat:billwatch-20260922-changeprioritymodal-functional-tests] ---
- [ ] [T1] billwatch-web/src/components/__tests__/ChangePriorityModal.test.ts — Create this new, separate test file (keep the existing a11y suite focused) mounting ChangePriorityModal.vue with `currentPriority: 'medium'`, selecting a different priority option, and clicking confirm — asserting the emitted `confirm` event's payload is `[selectedPriority, notes || undefined]`. VERIFY: `cd billwatch-web && npx vitest run src/components/__tests__/ChangePriorityModal.test.ts 2>&1 | grep -q "passed"`. (cat:web; multifile:no) [feat:billwatch-20260922-changeprioritymodal-functional-tests]
- [ ] [T1] billwatch-web/src/components/__tests__/ChangePriorityModal.test.ts — Add a case asserting that when the notes field is left blank, `handleConfirm()`'s emitted payload passes `undefined` (not an empty string) for notes. VERIFY: `cd billwatch-web && npx vitest run src/components/__tests__/ChangePriorityModal.test.ts 2>&1 | grep -q "passed"`. (cat:web; multifile:no) [feat:billwatch-20260922-changeprioritymodal-functional-tests]
- [ ] [T1] billwatch-web/src/components/__tests__/ChangePriorityModal.test.ts — Add a case asserting `handleClose()` emits `close` and resets `selectedPriority`/`notes` back to `props.currentPriority`/empty (verify by re-opening the confirm flow afterward and checking the reset state). VERIFY: `cd billwatch-web && npx vitest run src/components/__tests__/ChangePriorityModal.test.ts 2>&1 | grep -q "passed"`. (cat:web; multifile:no) [feat:billwatch-20260922-changeprioritymodal-functional-tests]

# --- Claude-decomposed from roadmap [2026-09-22 round 4]: Add unit tests for Android TopicsRepository + TopicsViewModel — zero coverage today, same gap already fixed for Bills/Billing (review + tweak) [feat:billwatch-20260922-android-topics-tests] ---
- [ ] [T2] billwatch-android/app/src/test/java/com/billwatch/data/repository/TopicsRepositoryTest.kt — Create this new test file mirroring the existing mockk/coEvery/runTest pattern already established in AuthRepositoryTest.kt, covering TopicsRepository.kt's methods (mock the underlying API/DataStore dependency). VERIFY: `cd billwatch-android && ./gradlew testDebugUnitTest --tests "com.billwatch.data.repository.TopicsRepositoryTest"`. (cat:mobile; multifile:no) [feat:billwatch-20260922-android-topics-tests]
- [ ] [T2] billwatch-android/app/src/test/java/com/billwatch/ui/screens/TopicsViewModelTest.kt — Create this new test file following the same established mockk pattern, covering TopicsViewModel.kt's methods (mock TopicsRepository, use `coEvery`/`runTest`). VERIFY: `cd billwatch-android && ./gradlew testDebugUnitTest --tests "com.billwatch.ui.screens.TopicsViewModelTest"`. (cat:mobile; multifile:no) [feat:billwatch-20260922-android-topics-tests]

# --- Claude-decomposed from roadmap [2026-09-22 round 4]: Add unit tests for Android CivicRepository + FindRepsViewModel + HomeViewModel — zero coverage today (review + tweak) [feat:billwatch-20260922-android-civic-findreps-home-tests] ---
- [ ] [T2] billwatch-android/app/src/test/java/com/billwatch/data/repository/CivicRepositoryTest.kt — Create this new test file mirroring AuthRepositoryTest.kt's mockk/coEvery/runTest pattern, covering CivicRepository.kt's methods. VERIFY: `cd billwatch-android && ./gradlew testDebugUnitTest --tests "com.billwatch.data.repository.CivicRepositoryTest"`. (cat:mobile; multifile:no) [feat:billwatch-20260922-android-civic-findreps-home-tests]
- [ ] [T2] billwatch-android/app/src/test/java/com/billwatch/ui/screens/FindRepsViewModelTest.kt — Create this new test file following the same established mockk pattern, covering FindRepsViewModel.kt's methods (mock CivicRepository). VERIFY: `cd billwatch-android && ./gradlew testDebugUnitTest --tests "com.billwatch.ui.screens.FindRepsViewModelTest"`. (cat:mobile; multifile:no) [feat:billwatch-20260922-android-civic-findreps-home-tests]
- [ ] [T2] billwatch-android/app/src/test/java/com/billwatch/ui/screens/HomeViewModelTest.kt — Create this new test file following the same established mockk pattern, covering HomeViewModel.kt's methods. VERIFY: `cd billwatch-android && ./gradlew testDebugUnitTest --tests "com.billwatch.ui.screens.HomeViewModelTest"`. (cat:mobile; multifile:no) [feat:billwatch-20260922-android-civic-findreps-home-tests]

# --- Claude-decomposed from roadmap [2026-09-22 round 4]: Add unit tests for Android PreferencesRepository + NotificationPreferencesViewModel — zero coverage today (review + tweak) [feat:billwatch-20260922-android-preferences-tests] ---
- [ ] [T1] billwatch-android/app/src/test/java/com/billwatch/data/repository/PreferencesRepositoryTest.kt — Create this new test file mirroring AuthRepositoryTest.kt's mockk/coEvery/runTest pattern, covering PreferencesRepository.kt's methods. VERIFY: `cd billwatch-android && ./gradlew testDebugUnitTest --tests "com.billwatch.data.repository.PreferencesRepositoryTest"`. (cat:mobile; multifile:no) [feat:billwatch-20260922-android-preferences-tests]
- [ ] [T1] billwatch-android/app/src/test/java/com/billwatch/ui/screens/NotificationPreferencesViewModelTest.kt — Create this new test file following the same established mockk pattern, covering NotificationPreferencesViewModel.kt's methods. VERIFY: `cd billwatch-android && ./gradlew testDebugUnitTest --tests "com.billwatch.ui.screens.NotificationPreferencesViewModelTest"`. (cat:mobile; multifile:no) [feat:billwatch-20260922-android-preferences-tests]
