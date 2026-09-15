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
- [ ] [T2] tests/test_ranking_router.py — Add test_ranked_bills_empty_follows that mocks get_followed_bills to return [] and asserts GET /api/ranking/ranked-bills returns 200 with empty list. VERIFY: `pytest tests/test_ranking_router.py::test_ranked_bills_empty_follows -v` passes. (cat:test; multifile:no)
- [ ] [T2] tests/test_ranking_router.py — Add test_ranked_bills_congress_empty_follows that mocks get_followed_bills to return [] and asserts GET /api/ranking/ranked-bills/118 returns 200 with empty list. VERIFY: `pytest tests/test_ranking_router.py::test_ranked_bills_congress_empty_follows -v` passes. (cat:test; multifile:no)
- [ ] [T3] tests/test_ranking_router.py — Add test_detect_activity_endpoint that mocks activity detection service and asserts POST /api/ranking/detect-activity returns 200 with expected schema. VERIFY: `pytest tests/test_ranking_router.py::test_detect_activity_endpoint -v` passes. (cat:test; multifile:no)
- [ ] [T3] tests/test_ranking_router.py — Add test_apply_cooldown_endpoint that mocks cooldown application and asserts POST /api/ranking/apply-cooldown/123 returns 200. VERIFY: `pytest tests/test_ranking_router.py::test_apply_cooldown_endpoint -v` passes. (cat:test; multifile:no)
- [ ] [T3] tests/test_ranking_router.py — Add test_recently_enacted_endpoint that mocks recently enacted bills query and asserts GET /api/ranking/recently-enacted returns 200 with list. VERIFY: `pytest tests/test_ranking_router.py::test_recently_enacted_endpoint -v` passes. (cat:test; multifile:no)

# --- 27B-decomposed from roadmap [2026-09-14]: Add a router-level test for POST /api/articles/rank — app/routers/article_relevance.py's r (review + tweak) ---
- [ ] [T1] billwatch-backend/tests/test_article_relevance_router.py — Create new file with a `TestClient` fixture that mocks `ArticleRelevanceService.rank_articles` to return a valid `ArticleRelevanceResponse` and asserts the endpoint returns 200 with correct schema fields. VERIFY: `cd billwatch-backend && pytest tests/test_article_relevance_router.py::test_rank_success -v`. (cat:test; multifile:no)
- [ ] [T1] billwatch-backend/tests/test_article_relevance_router.py — Add a test case that mocks `ArticleRelevanceService.rank_articles` to raise a generic `Exception` and asserts the endpoint returns 500 with an appropriate error message. VERIFY: `cd billwatch-backend && pytest tests/test_article_relevance_router.py::test_rank_exception_500 -v`. (cat:test; multifile:no)
- [ ] [T2] billwatch-backend/tests/test_article_relevance_router.py — Add a test case that sends an invalid `ArticleRelevanceRequest` payload (missing required fields) and asserts the endpoint returns 422 validation error. VERIFY: `cd billwatch-backend && pytest tests/test_article_relevance_router.py::test_rank_validation_error -v`. (cat:test; multifile:no)
- [ ] [T3] billwatch-backend/app/routers/article_relevance.py — Verify that the `rank_articles` endpoint correctly propagates exceptions to the 500 handler by ensuring no silent swallowing of errors occurs in the try/except block. VERIFY: `cd billwatch-backend && grep -n "except Exception" app/routers/article_relevance.py | wc -l`. (cat:python; multifile:no)
- [ ] [T2] billwatch-backend/tests/test_article_relevance_router.py — Add a test that verifies the response headers include the correct content-type (`application/json`) for successful rank requests. VERIFY: `cd billwatch-backend && pytest tests/test_article_relevance_router.py::test_rank_content_type -v`. (cat:test; multifile:no)
- [ ] [T1] billwatch-backend/tests/test_article_relevance_router.py — Add a test that mocks the service to return an empty list of articles and asserts the response structure is valid with an empty `articles` array. VERIFY: `cd billwatch-backend && pytest tests/test_article_relevance_router.py::test_rank_empty_articles -v`. (cat:test; multifile:no)
- [ ] [T3] billwatch-backend/app/routers/article_relevance.py — Ensure the `ArticleRelevanceRequest` schema is imported and used correctly in the endpoint signature to guarantee type safety. VERIFY: `cd billwatch-backend && python -c "from app.routers.article_relevance import rank_articles; print('OK')"`. (cat:python; multifile:no)
- [ ] [T2] billwatch-backend/tests/test_article_relevance_router.py — Add a test that verifies the endpoint handles concurrent requests correctly by mocking the service with a delay and asserting no race conditions in response serialization. VERIFY: `cd billwatch-backend && pytest tests/test_article_relevance_router.py::test_rank_concurrent -v`. (cat:test; multifile:no)

# --- 27B-decomposed from roadmap [2026-09-14]: Add a router-level test for POST /api/bills/{bill_id}/background — app/routers/bill_backgr (review + tweak) ---
- [ ] [T1] tests/test_bill_background_router.py — Create new file with pytest fixture for FastAPI TestClient and mock BillBackgroundService dependency. VERIFY: `pytest tests/test_bill_background_router.py --collect-only` exits 0. (cat:test; multifile:no)
- [ ] [T2] tests/test_bill_background_router.py — Add test case `test_get_bill_background_success_200` that mocks service to return data and asserts response status 200 and JSON structure. VERIFY: `pytest tests/test_bill_background_router.py::test_get_bill_background_success_200 -v` passes. (cat:test; multifile:no)
- [ ] [T3] tests/test_bill_background_router.py — Add test case `test_get_bill_background_invalid_id_400` that calls endpoint with non-numeric bill_id and asserts response status 400. VERIFY: `pytest tests/test_bill_background_router.py::test_get_bill_background_invalid_id_400 -v` passes. (cat:test; multifile:no)
- [ ] [T4] tests/test_bill_background_router.py — Add test case `test_get_bill_background_service_none_503` that mocks service to return None and asserts response status 503 and error body presence. VERIFY: `pytest tests/test_bill_background_router.py::test_get_bill_background_service_none_503 -v` passes. (cat:test; multifile:no)
- [ ] [T5] billwatch-backend/app/routers/bill_background.py — Verify `get_bill_background` endpoint correctly handles non-numeric IDs by raising HTTPException 400 and service None by raising HTTPException 503 with detail. VERIFY: `grep -n "HTTPException" billwatch-backend/app/routers/bill_background.py | grep -E "400|503"` returns matches. (cat:endpoint; multifile:no)
