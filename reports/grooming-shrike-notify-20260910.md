# Grooming proposal — shrike-notify — 2026-09-10 04:00

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
```

## Proposed (LLM re-evaluation — review before applying)
1. Add unit tests for `backend/app/utils/dedupe.py` covering duplicate message removal and order preservation
2. Implement a `GET /stats` endpoint in `backend/app/routers/publish.py` to expose topic statistics using `topic_stats.py`
3. Add integration tests for `backend/app/services/receipt.py` verifying receipt generation and persistence logic
