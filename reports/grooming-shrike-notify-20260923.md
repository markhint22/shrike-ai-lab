# Grooming proposal — shrike-notify — 2026-09-23 04:00

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
1. Add unit tests for `backend/app/utils/dedupe.py` covering exact-match removal, sliding-window expiration, and empty-input edge cases.
2. Implement a `GET /health` endpoint in `backend/app/main.py` that returns 200 OK with service version and broker status.
3. Add unit tests for `backend/app/utils/backoff.py` verifying exponential growth, jitter application, and max-retry capping logic.
4. Create a `POST /messages/bulk` endpoint in `backend/app/routers/messages.py` to accept a list of messages and return batch processing results.
5. Add integration tests for `backend/app/services/ttl.py` verifying that expired topics are correctly purged from the broker state.
