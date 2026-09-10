# Grooming proposal — shrike-notify — 2026-09-06 04:00

## Current Next Steps
```
- [ ] [HUMAN-ONLY BLOCKED ITEM — auto-skipped after 3 failed cycles; needs a human] [T1] Add tests for `Message.to_dict` in backend/app/models.py (round-trips all fields incl. tags list and created_at)
- [ ] [HUMAN-ONLY BLOCKED ITEM — auto-skipped after 3 failed cycles; needs a human] [T1] Add tests for `normalize_priority` in backend/app/models.py covering a float input and an out-of-range int (0 and 6) -> "default"
- [ ] [HUMAN-ONLY BLOCKED ITEM — auto-skipped after 3 failed cycles; needs a human] [T2] Add tests for `RateLimiter` refill math in backend/app/services/ratelimit.py (partial refill after half a window allows the expected token count)
- [ ] [HUMAN-ONLY BLOCKED ITEM — auto-skipped after 3 failed cycles; needs a human] [T2] Add a `revoke`/deny-list concept stub is out of scope; instead add tests for `auth.issue_token` raising ValueError on an empty scope in backend/app/services/auth.py
- [ ] [HUMAN-ONLY BLOCKED ITEM — auto-skipped after 3 failed cycles; needs a human] [T2] Add a `Broker.clear(topic)` method that drops a topic's history and disconnects subscribers, in backend/app/services/broker.py, + a test
```

## Proposed (LLM re-evaluation — review before applying)
1. Add tests for `Message.to_dict` in backend/app/models.py to verify round-trip fidelity of all fields including tags list and created_at timestamp
2. Add tests for `normalize_priority` in backend/app/models.py covering float inputs and out-of-range integers (0 and 6) mapping to "default"
3. Add tests for `RateLimiter` refill math in backend/app/services/ratelimit.py verifying partial refill after half a window allows the expected token count
4. Add tests for `auth.issue_token` in backend/app/services/auth.py ensuring it raises ValueError when an empty scope is provided
5. Implement `Broker.clear(topic)` method in backend/app/services/broker.py to drop topic history and disconnect subscribers
6. Add unit tests for the new `Broker.clear(topic)` method verifying history removal and subscriber disconnection
7. Add integration tests for the `/publish` endpoint in backend/tests/test_publish_api.py to verify message persistence and broker notification flow
