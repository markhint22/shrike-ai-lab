# Grooming proposal — shrike-notify — 2026-11-21 04:01

## Current Next Steps
```
- [x] (already-satisfied in code, implement-verified) [T1] Add tests for `Message.to_dict` in backend/app/models.py (round-trips all fields incl. tags list and created_at)
- [x] (already-satisfied in code, implement-verified) [T1] Add tests for `normalize_priority` in backend/app/models.py covering a float input and an out-of-range int (0 and 6) -> "default"
- [x] [T3] backend/app/routers/publish.py — Create `POST /tokens` endpoint accepting `TokenCreate` schema and returning a new scoped token, protected by admin scope. VERIFY: pytest backend/tests/test_tokens_api.py::test_create_token_success -q (cat:endpoint; multifile:no)
- [x] [T3] backend/app/routers/publish.py — Create `GET /tokens` endpoint listing active tokens for the authenticated user, protected by read scope. VERIFY: pytest backend/tests/test_tokens_api.py::test_list_tokens_success -q (cat:endpoint; multifile:no)
- [x] [AUTO-SKIP after 4 failed-to-land cycles — kept reverting (already-done, too hard for the 27B, or a sibling-file gate fail); review — NOT necessarily human-only] [T2] Add tests for `RateLimiter` refill math in backend/app/services/ratelimit.py (partial refill after half a window allows the expected token count)  <!-- superseded by recovery decomposition below -->
- [x] [T1] backend/app/services/ratelimit.py — Add a pure helper function `calculate_refill_tokens(elapsed_seconds, window_seconds, max_tokens)` that returns the integer number of tokens to add based on elapsed time, ensuring it handles partial windows correctly without side effects. VERIFY: python -c "from backend.app.services.ratelimit import calculate_refill_tokens; assert calculate_refill_tokens(1.5, 2.0, 10) == 7 or calculate_refill_tokens(1.5, 2.0, 10) == 8" (cat:logic; recovery:decomposed)
- [x] [T2] backend/tests/test_ratelimit.py — Add a test case `test_partial_refill_math` that imports `calculate_refill_tokens` and asserts that the returned token count is an integer, non-negative, and does not exceed `max_tokens`, verifying the monotonic property that more elapsed time yields >= tokens. VERIFY: pytest backend/tests/test_ratelimit.py::test_partial_refill_math -v (cat:test; recovery:decomposed)
- [x] (already-satisfied in code, implement-verified) [T2] Add a `revoke`/deny-list concept stub is out of scope; instead add tests for `auth.issue_token` raising ValueError on an empty scope in backend/app/services/auth.py
- [x] (already-satisfied in code, implement-verified) [T2] Add a `Broker.clear(topic)` method that drops a topic's history and disconnects subscribers, in backend/app/services/broker.py, + a test
- [x] [T1] backend/tests/test_severity.py — Add tests for backend/app/utils/severity.py: `severity_rank("critical") == 4`, `severity_rank("unknown-level") == -1`, `is_actionable("error") is True` and `is_actionable("info") is False`, `validate_severity("WARNING") == "warning"` (case-normalization), and `validate_severity("bogus")` raises `ValueError`. VERIFY: `cd backend && pytest tests/test_severity.py -v`. (cat:test; multifile:no)
```

## Proposed (LLM re-evaluation — review before applying)
1. Add unit tests for `backend/app/utils/dedupe.py` verifying that duplicate message bodies within a sliding window are correctly identified and removed.
2. Implement a `GET /health` endpoint in `backend/app/main.py` that returns 200 OK with a JSON body containing the current version and active broker connection status.
3. Add tests for `backend/app/utils/backoff.py` ensuring that exponential backoff calculations respect the maximum delay cap and jitter range.
4. Create a `POST /messages/batch` endpoint in `backend/app/routers/messages.py` that accepts a list of messages, validates each against the schema, and returns a summary of accepted/rejected items.
5. Add unit tests for `backend/app/utils/sanitize.py` verifying that HTML tags and script blocks are stripped from message bodies while preserving safe formatting characters.
6. Implement a `GET /metrics/summary` endpoint in `backend/app/routers/metrics_router.py` that aggregates total messages published, average latency, and error rates from the metrics service.
7. Add tests for `backend/app/utils/coalesce.py` ensuring that consecutive identical events are merged into a single event with an incremented count within the specified time window.
8. Create a `DELETE /topics/{topic_id}` endpoint in `backend/app/routers/topic_admin.py` that removes a topic and its associated history, protected by admin scope.
9. Add unit tests for `backend/app/utils/quiet_hours.py` verifying that notification suppression logic correctly respects user-specific quiet hours across time zones.
10. Implement a `GET /export/messages` endpoint in `backend/app/routers/export.py` that streams message history as NDJSON, supporting pagination via cursor parameters.
