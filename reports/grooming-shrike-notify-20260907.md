# Grooming proposal — shrike-notify — 2026-09-07 04:00

## Current Next Steps
```
- [ ] [HUMAN-ONLY BLOCKED ITEM — auto-skipped after 3 failed cycles; needs a human] [T1] Add tests for `Message.to_dict` in backend/app/models.py (round-trips all fields incl. tags list and created_at)
- [ ] [HUMAN-ONLY BLOCKED ITEM — auto-skipped after 3 failed cycles; needs a human] [T1] Add tests for `normalize_priority` in backend/app/models.py covering a float input and an out-of-range int (0 and 6) -> "default"
- [ ] [HUMAN-ONLY BLOCKED ITEM — auto-skipped after 3 failed cycles; needs a human] [T2] Add tests for `RateLimiter` refill math in backend/app/services/ratelimit.py (partial refill after half a window allows the expected token count)
- [ ] [HUMAN-ONLY BLOCKED ITEM — auto-skipped after 3 failed cycles; needs a human] [T2] Add a `revoke`/deny-list concept stub is out of scope; instead add tests for `auth.issue_token` raising ValueError on an empty scope in backend/app/services/auth.py
- [ ] [HUMAN-ONLY BLOCKED ITEM — auto-skipped after 3 failed cycles; needs a human] [T2] Add a `Broker.clear(topic)` method that drops a topic's history and disconnects subscribers, in backend/app/services/broker.py, + a test
```

## Proposed (LLM re-evaluation — review before applying)
1. Add tests for `Message.to_dict` in backend/app/models.py (round-trips all fields incl. tags list and created_at)
2. Add tests for `normalize_priority` in backend/app/models.py covering a float input and an out-of-range int (0 and 6) -> "default"
3. Add tests for `RateLimiter` refill math in backend/app/services/ratelimit.py (partial refill after half a window allows the expected token count)
4. Add tests for `auth.issue_token` raising ValueError on an empty scope in backend/app/services/auth.py
5. Add a `Broker.clear(topic)` method that drops a topic's history and disconnects subscribers, in backend/app/services/broker.py
6. Add a test for `Broker.clear(topic)` verifying history is dropped and subscribers are disconnected
7. Add integration test for `retry_after` header generation in backend/app/services/rate_headers.py using the new helper
8. Add unit tests for `delivery_receipt` function in backend/app/services/receipt.py covering success and failure cases
9. Add unit tests for TTL expiry logic in backend/app/services/ttl.py ensuring expired items are correctly filtered
