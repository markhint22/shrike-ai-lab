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
- [ ] [T1] billwatch-backend/tests/test_legislator_sync_upsert.py — Create test file with a helper function `make_congress_payload(**overrides)` that returns a realistic Congress.gov JSON dict containing `bioguideId`, `name` ("Doe, John"), `chamber`, `state`, `partyName`, and a `terms` list with `currentTerm` (containing `stateCode`, `district`) and `endYear`. VERIFY: `cd billwatch-backend && python -m pytest tests/test_legislator_sync_upsert.py::test_make_congress_payload_structure -v` passes. (cat:test; multifile:no)
- [ ] [T1] billwatch-backend/tests/test_legislator_sync_upsert.py — Add test `test_name_splitting_logic` that imports the name-splitting logic from `app/services/legislator_sync_service.py` (or mocks it if private) and asserts that "Doe, John" splits into last="Doe", first="John", and "Smith, Jane Doe" splits into last="Smith", first="Jane". VERIFY: `cd billwatch-backend && python -m pytest tests/test_legislator_sync_upsert.py::test_name_splitting_logic -v` passes. (cat:test; multifile:no)
- [ ] [T1] billwatch-backend/tests/test_legislator_sync_upsert.py — Add test `test_chamber_normalization_branches` that verifies "House of Representatives" normalizes to "House", "United States Senate" normalizes to "Senate", and "Unknown Chamber" truncates to first 20 chars. VERIFY: `cd billwatch-backend && python -m pytest tests/test_legislator_sync_upsert.py::test_chamber_normalization_branches -v` passes. (cat:test; multifile:no)
- [ ] [T1] billwatch-backend/tests/test_legislator_sync_upsert.py — Add test `test_party_code_derivation` that asserts "Democrat" maps to "D", "Republican" maps to "R", and "Independent" or empty string maps to "I". VERIFY: `cd billwatch-backend && python -m pytest tests/test_legislator_sync_upsert.py::test_party_code_derivation -v` passes. (cat:test; multifile:no)
- [ ] [T1] billwatch-backend/tests/test_legislator_sync_upsert.py — Add test `test_state_fallback_level_1_current_term` that provides a payload with `terms[0].currentTerm.stateCode = "CA"` and asserts the resulting state code is "CA", ignoring the `state` name. VERIFY: `cd billwatch-backend && python -m pytest tests/test_legislator_sync_upsert.py::test_state_fallback_level_1_current_term -v` passes. (cat:test; multifile:no)
- [ ] [T1] billwatch-backend/tests/test_legislator_sync_upsert.py — Add test `test_state_fallback_level_2_state_name_lookup` that provides a payload with no `stateCode` in term but `state = "California"` and asserts the resulting state code is "CA" via the STATE_CODES lookup. VERIFY: `cd billwatch-backend && python -m pytest tests/test_legislator_sync_upsert.py::test_state_fallback_level_2_state_name_lookup -v` passes. (cat:test; multifile:no)
- [ ] [T1] billwatch-backend/tests/test_legislator_sync_upsert.py — Add test `test_state_fallback_level_3_attribution_slice` that provides a payload with no stateCode, no valid state name, but `depiction.attribution = "Photo by CA News"` and asserts the resulting state code is "Ph" (documenting the likely bug) or the specific 2-char slice behavior. VERIFY: `cd billwatch-backend && python -m pytest tests/test_legislator_sync_upsert.py::test_state_fallback_level_3_attribution_slice -v` passes. (cat:test; multifile:no)
- [ ] [T1] billwatch-backend/tests/test_legislator_sync_upsert.py — Add test `test_in_office_determination_end_year_past` that provides a payload with `endYear` in the past (e.g., 2020) and asserts `in_office` is False, and another case with future endYear asserting True. VERIFY: `cd billwatch-backend && python -m pytest tests/test_legislator_sync_upsert.py::test_in_office_determination_end_year_past -v` passes. (cat:test; multifile:no)

# --- 27B-decomposed from roadmap [2026-09-18]: Add unit tests for app/utils/datetime_utils.py's utcnow() — this 12-line module's own docs (review + tweak) ---
- [ ] [T1] billwatch-backend/tests/test_datetime_utils.py — Create new test file with `test_utcnow_returns_timezone_aware` asserting `utcnow().tzinfo is not None`. VERIFY: `cd billwatch-backend && python -m pytest tests/test_datetime_utils.py::test_utcnow_returns_timezone_aware -v`. (cat:test; multifile:no)
- [ ] [T1] billwatch-backend/tests/test_datetime_utils.py — Add `test_utcnow_accuracy` asserting `abs((utcnow() - datetime.now(timezone.utc)).total_seconds()) < 1.0`. VERIFY: `cd billwatch-backend && python -m pytest tests/test_datetime_utils.py::test_utcnow_accuracy -v`. (cat:test; multifile:no)
- [ ] [T2] billwatch-backend/tests/test_datetime_utils.py — Add `test_utcnow_type` asserting `isinstance(utcnow(), datetime)`. VERIFY: `cd billwatch-backend && python -m pytest tests/test_datetime_utils.py::test_utcnow_type -v`. (cat:test; multifile:no)
- [ ] [T2] billwatch-backend/tests/test_datetime_utils.py — Add `test_utcnow_consistency` asserting two consecutive calls return values within 1 second of each other. VERIFY: `cd billwatch-backend && python -m pytest tests/test_datetime_utils.py::test_utcnow_consistency -v`. (cat:test; multifile:no)
- [ ] [T3] billwatch-backend/tests/__init__.py — Ensure test directory is a package by creating empty `__init__.py` if missing. VERIFY: `ls billwatch-backend/tests/__init__.py`. (cat:test; multifile:no)
- [ ] [T4] billwatch-backend/app/services/campaign_finance_sync_service.py — Verify existing usage of `utcnow()` still passes type checks and imports resolve correctly. VERIFY: `cd billwatch-backend && python -m mypy app/services/campaign_finance_sync_service.py --ignore-missing-imports`. (cat:python; multifile:no)

# --- 27B-decomposed from roadmap [2026-09-18]: Delete orphaned dead Vue component billwatch-web/src/components/BillDetailView.vue — this  (review + tweak) ---
- [ ] [T1] billwatch-web/src/components/BillDetailView.vue — Delete the file entirely as it is an orphaned dead component not imported by any active route or component. VERIFY: `test ! -f billwatch-web/src/components/BillDetailView.vue`. (cat:vue; multifile:no)
- [ ] [T1] billwatch-web/src/views/BillDetailView.vue — Verify the active view component remains intact and is the only BillDetailView file in the repository. VERIFY: `find billwatch-web/src -name "BillDetailView.vue" | wc -l` returns 1. (cat:vue; multifile:no)
- [ ] [T2] billwatch-web/src/router/index.ts — Confirm the router import path `@/views/BillDetailView.vue` is unchanged and valid. VERIFY: `grep -q "import('@/views/BillDetailView.vue')" billwatch-web/src/router/index.ts`. (cat:typescript; multifile:no)
- [ ] [T2] billwatch-web/src — Ensure no remaining references to the deleted component path exist in the codebase. VERIFY: `grep -r "components/BillDetailView" billwatch-web/src --include="*.vue" --include="*.ts" | wc -l` returns 0. (cat:typescript; multifile:no)
- [ ] [T3] billwatch-web/package.json — Execute the project's linting script to ensure no unused imports or broken references are flagged after deletion. VERIFY: `cd billwatch-web && npm run lint` exits with code 0. (cat:typescript; multifile:no)
- [ ] [T3] billwatch-web/package.json — Execute the project's type-checking script to ensure the TypeScript compilation succeeds without the deleted component. VERIFY: `cd billwatch-web && npm run type-check` exits with code 0. (cat:typescript; multifile:no)

# --- 27B-decomposed from roadmap [2026-09-18]: Consolidate duplicate/stale billwatch-web/src/services/api.test.ts — two separate test fil (review + tweak) ---
- [ ] [T1] billwatch-web/src/services/__tests__/api.test.ts — Add explicit assertions for `axios.create` call arguments and `auth` header injection to match old file's intent. VERIFY: `cd billwatch-web && npx vitest run src/services/__tests__/api.test.ts`. (cat:test; multifile:no)
- [ ] [T2] billwatch-web/src/services/api.test.ts — Delete the stale test file. VERIFY: `test ! -f billwatch-web/src/services/api.test.ts`. (cat:refactor; multifile:no)
- [ ] [T3] billwatch-web/package.json — Ensure `vitest` config or CLI command explicitly targets `src/**/__tests__/**/*.test.ts` to prevent future root-level test file ambiguity. VERIFY: `cd billwatch-web && npx vitest run --reporter=verbose 2>&1 | grep -q "api.test"`. (cat:test; multifile:no)
- [ ] [T4] billwatch-web/src/services/api.ts — Verify no imports reference the deleted test file path directly. VERIFY: `grep -r "services/api.test" billwatch-web/src --include="*.ts" --include="*.vue" | grep -v "__tests__" | wc -l` returns 0. (cat:typescript; multifile:no)
- [ ] [T5] billwatch-web/README.md — Update testing conventions section to mandate `__tests__/` subdirectory for all test files. VERIFY: `grep -q "__tests__" billwatch-web/README.md`. (cat:docs; multifile:no)
