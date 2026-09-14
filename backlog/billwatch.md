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
- [ ] [T1] tests/test_priority_api_router.py — Create file with `TestClient` fixture and a helper to mock `get_db` dependency injection for the priority router. VERIFY: python -m pytest tests/test_priority_api_router.py::test_client_fixture -v (cat:test; multifile:no)
- [ ] [T2] tests/test_priority_api_router.py — Add test `test_set_bill_priority_unauthenticated` asserting 401 status when no auth token is provided. VERIFY: python -m pytest tests/test_priority_api_router.py::test_set_bill_priority_unauthenticated -v (cat:test; multifile:no)
- [ ] [T3] tests/test_priority_api_router.py — Add test `test_get_priority_dashboard_unauthenticated` asserting 401 status when no auth token is provided. VERIFY: python -m pytest tests/test_priority_api_router.py::test_get_priority_dashboard_unauthenticated -v (cat:test; multifile:no)
- [ ] [T4] tests/test_priority_api_router.py — Add test `test_get_bills_requiring_action_unauthenticated` asserting 401 status when no auth token is provided. VERIFY: python -m pytest tests/test_priority_api_router.py::test_get_bills_requiring_action_unauthenticated -v (cat:test; multifile:no)
- [ ] [T5] tests/test_priority_api_router.py — Add test `test_create_priority_alert_unauthenticated` asserting 401 status when no auth token is provided. VERIFY: python -m pytest tests/test_priority_api_router.py::test_create_priority_alert_unauthenticated -v (cat:test; multifile:no)

# --- 27B-decomposed from roadmap [2026-09-14]: Add router tests for bill_chat.py — app/routers/bill_chat.py's two endpoints (`post_bill_m (review + tweak) ---
- [ ] [T1] tests/test_bill_chat_router.py — Create test file with `TestClient` fixture and mock `LLMService.moderate_comment`/`filter_comment_tone` to return approved status. VERIFY: `pytest tests/test_bill_chat_router.py -v --collect-only` shows 0 errors. (cat:test; multifile:no)
- [ ] [T2] tests/test_bill_chat_router.py — Add test `test_post_bill_message_success` mocking DB session to return a valid Bill and LLM service to approve content, asserting 201 status and response schema. VERIFY: `pytest tests/test_bill_chat_router.py::test_post_bill_message_success -v` passes. (cat:test; multifile:no)
- [ ] [T3] tests/test_bill_chat_router.py — Add test `test_post_bill_message_not_found` mocking DB session to return None for Bill, asserting 404 status and error message. VERIFY: `pytest tests/test_bill_chat_router.py::test_post_bill_message_not_found -v` passes. (cat:test; multifile:no)
- [ ] [T4] tests/test_bill_chat_router.py — Add test `test_get_bill_chat_filtered_true` mocking DB session to return messages and LLM service to flag one as inappropriate, asserting only safe messages are returned when `filtered=true`. VERIFY: `pytest tests/test_bill_chat_router.py::test_get_bill_chat_filtered_true -v` passes. (cat:test; multifile:no)
- [ ] [T5] tests/test_bill_chat_router.py — Add test `test_get_bill_chat_filtered_false` mocking DB session to return messages, asserting all messages are returned when `filtered=false`. VERIFY: `pytest tests/test_bill_chat_router.py::test_get_bill_chat_filtered_false -v` passes. (cat:test; multifile:no)
