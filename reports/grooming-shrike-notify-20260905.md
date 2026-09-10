# Grooming proposal — shrike-notify — 2026-09-05 04:00

## Current Next Steps
```
- [ ] [HUMAN-ONLY BLOCKED ITEM — auto-skipped after 3 failed cycles; needs a human] [T1] Add tests for `Message.to_dict` in backend/app/models.py (round-trips all fields incl. tags list and created_at)
- [ ] [HUMAN-ONLY BLOCKED ITEM — auto-skipped after 3 failed cycles; needs a human] [T1] Add tests for `normalize_priority` in backend/app/models.py covering a float input and an out-of-range int (0 and 6) -> "default"
- [x] [T1] Add tests for `parse_tags` in backend/app/models.py covering a tuple input and a list with non-string items (ints) -> stringified + stripped
- [x] (already-satisfied in code, implement-verified) [T2] Add a `min`/`max` guard to `validate_topic` rejecting a whitespace-only name explicitly with a clear message in backend/app/models.py + a test
- [x] (already-satisfied in code, implement-verified) [T1] Add tests for `RateLimiter.reset` in backend/app/services/ratelimit.py (after reset, a throttled key is allowed again)
- [ ] [HUMAN-ONLY BLOCKED ITEM — auto-skipped after 3 failed cycles; needs a human] [T2] Add tests for `RateLimiter` refill math in backend/app/services/ratelimit.py (partial refill after half a window allows the expected token count)
- [x] (already-satisfied in code, implement-verified) [T1] Add tests for `format_sse` in backend/app/routers/subscribe.py (produces a `data: <json>\n\n` frame that round-trips via json.loads)
- [x] (already-satisfied in code, implement-verified) [T2] Add tests for `auth.verify_token` edge cases in backend/app/services/auth.py (token with no dot, empty scope, tampered signature) all -> None
- [ ] [HUMAN-ONLY BLOCKED ITEM — auto-skipped after 3 failed cycles; needs a human] [T2] Add a `revoke`/deny-list concept stub is out of scope; instead add tests for `auth.issue_token` raising ValueError on an empty scope in backend/app/services/auth.py
- [x] [T2] Add a `Broker.topics()` method returning the set of topics with history or subscribers, in backend/app/services/broker.py, + a test
- [ ] [HUMAN-ONLY BLOCKED ITEM — auto-skipped after 3 failed cycles; needs a human] [T2] Add a `Broker.clear(topic)` method that drops a topic's history and disconnects subscribers, in backend/app/services/broker.py, + a test
- [x] [T2] Add a `since_id` filter to `Broker.history` (return only messages after a given message id) in backend/app/services/broker.py, + a test
- [x] [T2] Add a `priority` filter to `Broker.history` (only messages at/above a min priority using PRIORITY_LEVELS order) in backend/app/services/broker.py, + a test
- [x] [T2] Add a `tag` filter to `Broker.history` (only messages containing a given tag) in backend/app/services/broker.py, + a test
- [x] [T2] Add a module logger to backend/app/services/broker.py and log publish fan-out counts at debug level
- [x] [T2] Add a `max_length` bound to `PublishRequest.title` is present; add a validator rejecting a body that is only whitespace in backend/app/schemas.py, + a test
- [x] [T2] Add a `HealthResult.extra` populated with version + uptime seconds in the /health handler in backend/app/main.py, + a test
- [x] [T3] Add a `WebSocket` subscribe endpoint `GET /{topic}/ws` mirroring the SSE stream, in backend/app/routers/subscribe.py, + a TestClient websocket test
- [x] [T2] Add a `truncate_body` helper in backend/app/models.py that caps a body at settings.max_message_length with an ellipsis, use it in publish, + a test
- [x] [T2] Add a `dropped` counter return to `Broker.publish` for subscribers whose queue is full (bounded queue) — set a maxsize on subscriber queues in backend/app/services/broker.py, + a test
- [x] [T2] Add a `to_ntfy_dict` compatibility method on Message (ntfy field names: message/title/priority/tags) in backend/app/models.py, + a test
- [x] [T1] Add docstrings to the `event_stream` inner generator and clarify the keep-alive interval constant in backend/app/routers/subscribe.py
- [x] [T2] Add a `created_at` monotonic-vs-walltime docstring note and a test asserting build_message sets a positive created_at in backend/app/services/broker.py
- [x] [T2] Add a `.ovn-verify.sh` running `.venv/bin/pytest -q` so the overnight gate verifies this repo, at repo root
```

## Proposed (LLM re-evaluation — review before applying)
1. Add tests for `Message.to_dict` in backend/app/models.py covering round-trips of all fields including tags list and created_at
2. Add tests for `normalize_priority` in backend/app/models.py covering float input and out-of-range int (0 and 6) mapping to "default"
3. Add tests for `RateLimiter` refill math in backend/app/services/ratelimit.py verifying partial refill after half a window allows the expected token count
4. Add tests for `auth.issue_token` in backend/app/services/auth.py asserting it raises ValueError on an empty scope
5. Implement `Broker.clear(topic)` method in backend/app/services/broker.py that drops history and disconnects subscribers, plus a test
6. Add a `limit` parameter to `Broker.history` in backend/app/services/broker.py to cap the number of returned messages, plus a test
7. Add a `GET /api/v1/topics` endpoint in backend/app/routers/messages.py returning the list of active topics from `Broker.topics()`, plus a test
