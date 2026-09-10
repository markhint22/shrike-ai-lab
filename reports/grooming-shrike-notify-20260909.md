# Grooming proposal — shrike-notify — 2026-09-09 04:00

## Current Next Steps
```
- [x] (already-satisfied in code, implement-verified) [T1] Add tests for `Message.to_dict` in backend/app/models.py (round-trips all fields incl. tags list and created_at)
- [x] (already-satisfied in code, implement-verified) [T1] Add tests for `normalize_priority` in backend/app/models.py covering a float input and an out-of-range int (0 and 6) -> "default"
- [x] [T3] backend/app/routers/publish.py — Create `POST /tokens` endpoint accepting `TokenCreate` schema and returning a new scoped token, protected by admin scope. VERIFY: pytest backend/tests/test_tokens_api.py::test_create_token_success -q (cat:endpoint; multifile:no)
- [x] [T3] backend/app/routers/publish.py — Create `GET /tokens` endpoint listing active tokens for the authenticated user, protected by read scope. VERIFY: pytest backend/tests/test_tokens_api.py::test_list_tokens_success -q (cat:endpoint; multifile:no)
- [ ] [AUTO-SKIP after 4 failed-to-land cycles — kept reverting (already-done, too hard for the 27B, or a sibling-file gate fail); review — NOT necessarily human-only] [T2] Add tests for `RateLimiter` refill math in backend/app/services/ratelimit.py (partial refill after half a window allows the expected token count)
- [x] (already-satisfied in code, implement-verified) [T2] Add a `revoke`/deny-list concept stub is out of scope; instead add tests for `auth.issue_token` raising ValueError on an empty scope in backend/app/services/auth.py
- [x] (already-satisfied in code, implement-verified) [T2] Add a `Broker.clear(topic)` method that drops a topic's history and disconnects subscribers, in backend/app/services/broker.py, + a test
```

## Proposed (LLM re-evaluation — review before applying)
1. Add tests for `RateLimiter` refill math in backend/app/services/ratelimit.py (partial refill after half a window allows the expected token count)
2. Add unit tests for `backoff.calculate_delay` in backend/app/utils/backoff.py covering exponential growth and max cap
3. Add unit tests for `dedupe.is_duplicate` in backend/app/utils/dedupe.py verifying TTL expiration logic
4. Add unit tests for `severity.parse_severity` in backend/app/utils/severity.py handling valid, invalid, and case-insensitive inputs
