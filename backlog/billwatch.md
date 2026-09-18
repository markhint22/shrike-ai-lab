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
- [ ] [T1] billwatch-backend/app/services/webhook_service.py — Delete the file containing the orphaned WebhookService class and its methods. VERIFY: `test -f billwatch-backend/app/services/webhook_service.py && echo "FAIL" || echo "PASS"` (cat:refactor; multifile:no)
- [ ] [T2] billwatch-backend/tests/test_webhook_service.py — Delete the test file that exclusively tests the deleted WebhookService. VERIFY: `test -f billwatch-backend/tests/test_webhook_service.py && echo "FAIL" || echo "PASS"` (cat:test; multifile:no)
- [ ] [T3] billwatch-backend/app/services/__init__.py — Remove any import or export of `webhook_service` or `WebhookService` if present. VERIFY: `grep -r "webhook_service\|WebhookService" billwatch-backend/app/ && echo "FAIL" || echo "PASS"` (cat:refactor; multifile:no)
- [ ] [T4] billwatch-backend/app/main.py — Verify no router registration or dependency injection references the deleted webhook service. VERIFY: `grep -r "webhook" billwatch-backend/app/main.py && echo "FAIL" || echo "PASS"` (cat:refactor; multifile:no)
- [ ] [T5] billwatch-backend/app/routers/__init__.py — Ensure no router module imports or references the deleted webhook service. VERIFY: `grep -r "webhook" billwatch-backend/app/routers/ && echo "FAIL" || echo "PASS"` (cat:refactor; multifile:no)
