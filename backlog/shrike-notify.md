# shrike-notify — RELEASE-READINESS backlog (27B-friendly), release-blockers FIRST
# queue_refill.py pulls [T1-T5] items top-down, so blockers get worked first.

# --- refill (2026-09-05): remaining uncovered guards/bounds (service is well-tested) ---

# --- refill 2026-09-06: new self-contained pure modules + pytest (landable T1-T2) ---

# --- refill 2026-09-06: build-out toward a usable pub/sub service (publish/subscribe/messages already wired) ---

# --- refill 2026-09-06b: more pub/sub build-out ---

# --- 27B-decomposed from roadmap [2026-09-07]: Tokens endpoint + scoped auth (require_auth path) {cat: backend; size: M; multifile: yes;  (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-07]: Retention caps + message TTL + topic list/stats endpoints {cat: backend; size: M; multifil (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-07]: Priority/tag validation + quiet-hours delivery gating {cat: backend; size: S; multifile: n (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-07]: Health details + rate-limit headers + a publish client helper (dogfood) {cat: backend; siz (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-11]: Gate GET /tokens and POST /tokens/revoke behind require_auth — currently in `backend/app/r (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-11]: Wire the already-built TokenStore into token issue/revoke so persistence is consistent wit (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-11]: Make NOTIFY_MAX_MESSAGE_LENGTH actually control the publish body limit — `backend/app/conf (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-13]: Delete domain-irrelevant orphaned utility modules with zero call sites — `backend/app/util (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-13]: Remove the dead duplicate TTL-expiry implementation before freeze — `backend/app/utils/ttl (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-14]: Fix phantom `get_token_store` import crashing persisted-auth wiring — `backend/app/depende (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-14]: Fix `is_expired()` signature/type mismatch vs. its only caller — `backend/app/services/ttl (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-14]: Close token-revocation authorization gap on POST /tokens/revoke — `backend/app/routers/mes (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-14]: Delete the duplicate QuietHoursConfig/should_defer_delivery landmine in `backend/app/utils (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-14]: Evict expired/revoked entries from the in-memory `_issued_tokens` registry — `backend/app/ (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-14]: Delete 8 garbage tracked files whose names are leftover LLM/aider chat text, not real sour (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-14]: Persist and return the validated `severity` field instead of discarding it after validatio (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-14]: Wire `get_auth_manager()`/`AuthManager` into the actual token endpoints so persisted token (review + tweak) ---
- [ ] [T4] backend/tests/test_integration_auth_persist.py — Create new integration test file that sets `NOTIFY_PERSIST=1`, issues a token via the API, asserts a row exists in `TokenStore`, revokes it, and asserts the row is marked revoked. VERIFY: python -m pytest backend/tests/test_integration_auth_persist.py -v. (cat:test; multifile:yes)

# --- 27B-decomposed from roadmap [2026-09-14]: Wire quiet-hours delivery gating into the actual publish path — `backend/app/services/brok (review + tweak) ---
- [ ] [T1] backend/app/config.py — Add `quiet_hours_start`, `quiet_hours_end`, and `quiet_hours_timezone` fields to the `Settings` class with default values. VERIFY: `python -c "from backend.app.config import Settings; s=Settings(); assert hasattr(s, 'quiet_hours_start') and hasattr(s, 'quiet_hours_end') and hasattr(s, 'quiet_hours_timezone')"`. (cat:schema; multifile:no)
- [ ] [T2] backend/app/utils/quiet_hours.py — Ensure `is_in_quiet_hours(dt, start, end, tz)` correctly handles timezone conversion and edge cases (midnight wrap). VERIFY: `pytest backend/tests/test_quiet_hours.py -v`. (cat:python; multifile:no)
- [ ] [T3] backend/app/services/broker.py — Modify `Broker.publish()` to call `should_deliver_now()` and suppress immediate fan-out if the message is low-priority and within quiet hours, logging the deferral. VERIFY: `pytest backend/tests/test_broker.py::test_should_deliver_now_* -v`. (cat:python; multifile:no)
- [ ] [T3] backend/app/routers/publish.py — Update `publish()` endpoint to pass the current time and config context to the broker, ensuring the quiet-hours check is triggered during the request lifecycle. VERIFY: `pytest backend/tests/test_publish_client.py -v`. (cat:endpoint; multifile:no)
- [ ] [T4] backend/app/delivery.py — Integrate `QuietHoursConfig` into `DeliveryManager.deliver_message()` to respect gating for any deferred or batched delivery logic. VERIFY: `pytest backend/tests/test_delivery.py -v`. (cat:python; multifile:yes)
- [ ] [T2] backend/tests/test_quiet_hours_integration.py — Create a new test file that simulates a low-priority message publish during configured quiet hours and asserts it is not immediately delivered. VERIFY: `pytest backend/tests/test_quiet_hours_integration.py -v`. (cat:test; multifile:no)
- [ ] [T3] backend/app/main.py — Ensure the `Settings` instance is correctly initialized with the new quiet-hours fields and passed to the dependency injection container for the broker. VERIFY: `python -c "from backend.app.main import app; print('OK')"`. (cat:python; multifile:no)
- [ ] [T5] backend/tests/test_core.py — Add an end-to-end integration test that starts the app, publishes a low-priority message during quiet hours, and verifies no SSE/WebSocket events are emitted. VERIFY: `pytest backend/tests/test_core.py -v`. (cat:test; multifile:yes)

# --- 27B-decomposed from roadmap [2026-09-14]: Expose `min_priority`/`tag` query filters on `GET /{topic}/messages` — `backend/app/servic (review + tweak) ---
- [ ] [T3] backend/app/routers/messages.py — Add `min_priority: str | None = Query(None)` and `tag: str | None = Query(None)` parameters to `list_messages()` and pass them to `broker.history()`. VERIFY: `grep -n "min_priority\|tag" backend/app/routers/messages.py | grep -q "Query"`. (cat:endpoint; multifile:no)
- [ ] [T2] backend/tests/test_messages_filters.py — Create new test file with a fixture that publishes messages with varying priorities and tags, then asserts `GET /{topic}/messages?min_priority=high` returns only high-priority messages. VERIFY: `pytest backend/tests/test_messages_filters.py::test_min_priority_filter -v`. (cat:test; multifile:no)
- [ ] [T2] backend/tests/test_messages_filters.py — Add test case asserting `GET /{topic}/messages?tag=critical` returns only messages tagged 'critical'. VERIFY: `pytest backend/tests/test_messages_filters.py::test_tag_filter -v`. (cat:test; multifile:no)
- [ ] [T2] backend/tests/test_messages_filters.py — Add test case asserting combined filters `min_priority=high&tag=critical` return only messages satisfying both conditions. VERIFY: `pytest backend/tests/test_messages_filters.py::test_combined_filters -v`. (cat:test; multifile:no)
- [ ] [T2] backend/tests/test_messages_filters.py — Add test case asserting that omitting filters (no query params) returns all messages up to the default limit, ensuring backward compatibility. VERIFY: `pytest backend/tests/test_messages_filters.py::test_no_filters_returns_all -v`. (cat:test; multifile:no)
- [ ] [T2] backend/tests/test_messages_filters.py — Add test case asserting that an invalid `min_priority` value (e.g., "urgent") results in a 422 validation error or empty list depending on schema constraints. VERIFY: `pytest backend/tests/test_messages_filters.py::test_invalid_min_priority -v`. (cat:test; multifile:no)

# --- 27B-decomposed from roadmap [2026-09-14]: Delete the orphaned `delivery_receipt()` helper in `backend/app/services/receipt.py` — thi (review + tweak) ---
- [ ] [T1] backend/app/services/receipt.py — Remove the `delivery_receipt()` function definition and any associated imports within this file. VERIFY: `grep -q "def delivery_receipt" backend/app/services/receipt.py && exit 1 || exit 0`. (cat:python; multifile:no)
- [ ] [T2] backend/tests/test_receipt.py — Delete the entire test file containing unit tests for the orphaned `delivery_receipt()` helper. VERIFY: `test ! -f backend/tests/test_receipt.py`. (cat:test; multifile:no)
- [ ] [T3] backend/app/services/__init__.py — Remove any import or re-export of `receipt` or `delivery_receipt` if present in the package initialization. VERIFY: `grep -q "receipt" backend/app/services/__init__.py && exit 1 || exit 0`. (cat:python; multifile:no)
- [ ] [T4] backend/app/services/broker.py — Verify that no code path imports or calls `delivery_receipt` from `app.services.receipt`. VERIFY: `grep -q "from app.services.receipt import" backend/app/services/broker.py && exit 1 || exit 0`. (cat:python; multifile:no)
- [ ] [T5] backend/app/main.py — Confirm that the application entry point does not reference or initialize any receipt-related services. VERIFY: `grep -q "receipt" backend/app/main.py && exit 1 || exit 0`. (cat:python; multifile:no)

# --- 27B-decomposed from roadmap [2026-09-14]: Wire rate-limit response headers into the publish endpoint — `backend/app/services/rate_he (review + tweak) ---
- [ ] [T1] backend/app/services/ratelimit.py — Add `remaining(self, key: str) -> float` method to `RateLimiter` that returns current token count for a specific key without mutating state. VERIFY: python -m pytest backend/tests/test_ratelimit.py::test_remaining_accessor -v. (cat:python; multifile:no)
- [ ] [T2] backend/tests/test_ratelimit.py — Add unit tests for `RateLimiter.remaining()` verifying it returns correct float values after consumption and refill, and does not mutate bucket state. VERIFY: python -m pytest backend/tests/test_ratelimit.py::test_remaining_accessor -v. (cat:test; multifile:no)
- [ ] [T3] backend/app/routers/publish.py — Modify `publish()` to call `build_rate_limit_headers()` from `backend/app/services/rate_headers.py` and attach returned headers to both 200 success and 429 throttle responses. VERIFY: python -m pytest backend/tests/test_publish_client.py -v --tb=short. (cat:endpoint; multifile:no)
- [ ] [T3] backend/tests/test_publish_client.py — Add test case asserting that a successful publish response includes `X-RateLimit-Limit`, `X-RateLimit-Remaining`, and `X-RateLimit-Reset` headers with correct values. VERIFY: python -m pytest backend/tests/test_publish_client.py::test_publish_success_includes_rate_headers -v. (cat:test; multifile:no)
- [ ] [T3] backend/tests/test_publish_client.py — Add test case asserting that a throttled publish response (429) includes `Retry-After` and `X-RateLimit-Remaining: 0` headers. VERIFY: python -m pytest backend/tests/test_publish_client.py::test_publish_throttle_includes_retry_after -v. (cat:test; multifile:no)
- [ ] [T3] backend/tests/test_publish_client.py — Add test case asserting that `X-RateLimit-Remaining` header value decreases by 1 across two successive successful publishes to the same topic. VERIFY: python -m pytest backend/tests/test_publish_client.py::test_remaining_decreases_on_successive_publishes -v. (cat:test; multifile:no)
- [ ] [T4] backend/app/routers/publish.py — Ensure `RateLimiter` instance is accessible in `publish()` context to pass the specific topic key to `remaining()` and `build_rate_limit_headers()`. VERIFY: python -m pytest backend/tests/test_publish_client.py -v. (cat:endpoint; multifile:yes)
