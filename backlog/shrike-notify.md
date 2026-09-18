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

# --- 27B-decomposed from roadmap [2026-09-14]: Wire quiet-hours delivery gating into the actual publish path — `backend/app/services/brok (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-14]: Expose `min_priority`/`tag` query filters on `GET /{topic}/messages` — `backend/app/servic (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-14]: Delete the orphaned `delivery_receipt()` helper in `backend/app/services/receipt.py` — thi (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-14]: Wire rate-limit response headers into the publish endpoint — `backend/app/services/rate_he (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-17]: Wire `settings.quiet_hours_config` onto the process-wide broker singleton at startup — `ba (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-17]: Add a message-TTL `Settings` field and wire it into the broker singleton — `backend/app/co (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-17]: Enforce retention cap and TTL on the persisted message store, not just in-memory history — (review + tweak) ---
- [ ] [T1] backend/app/persistence.py — Add `prune(topic: str, keep_max: int | None = None, ttl_seconds: float | None = None) -> int` method to `MessageStore` that executes `DELETE FROM messages WHERE topic = :topic AND (created_at < :cutoff OR id NOT IN (SELECT id FROM messages WHERE topic = :topic ORDER BY created_at DESC LIMIT :keep_max))` and returns rowcount. VERIFY: `pytest backend/tests/test_persistence.py::test_prune_by_count -v`. (cat:python; multifile:no)
- [ ] [T2] backend/tests/test_persistence.py — Add `test_prune_by_count` that inserts 10 rows for topic 't1', calls `store.prune('t1', keep_max=5)`, and asserts `SELECT COUNT(*) FROM messages WHERE topic='t1'` equals 5 and the oldest 5 rows are gone. VERIFY: `pytest backend/tests/test_persistence.py::test_prune_by_count -v`. (cat:test; multifile:no)
- [ ] [T2] backend/tests/test_persistence.py — Add `test_prune_by_ttl` that inserts rows with varying `created_at` timestamps, calls `store.prune('t1', ttl_seconds=60)`, and asserts only rows within the last 60 seconds remain. VERIFY: `pytest backend/tests/test_persistence.py::test_prune_by_ttl -v`. (cat:test; multifile:no)
- [ ] [T3] backend/app/services/broker.py — Modify `Broker.publish()` to call `await self.store.prune(message.topic, keep_max=self._history_size, ttl_seconds=self._ttl)` immediately after `await self.store.save(message)` when `self.store is not None`. VERIFY: `pytest backend/tests/test_broker.py::test_publish_prunes_persisted -v`. (cat:python; multifile:no)
- [ ] [T3] backend/tests/test_broker.py — Add `test_publish_prunes_persisted` that mocks a `MessageStore`, publishes 10 messages with `history_size=5`, and asserts `store.prune` was called with correct `keep_max` and `ttl_seconds` arguments. VERIFY: `pytest backend/tests/test_broker.py::test_publish_prunes_persisted -v`. (cat:test; multifile:no)
- [ ] [T4] backend/app/config.py — Ensure `NOTIFY_HISTORY_SIZE` and `NOTIFY_TTL_SECONDS` environment variables are parsed and exposed as `settings.history_size` and `settings.ttl_seconds` for use by `Broker` and `MessageStore`. VERIFY: `python -c "from backend.app.config import get_settings; s=get_settings(); print(s.history_size, s.ttl_seconds)"`. (cat:python; multifile:no)
- [ ] [T4] backend/tests/test_integration_auth_persist.py — Add `test_end_to_end_retention_cap` that enables persistence, publishes 100 messages to a single topic with `NOTIFY_HISTORY_SIZE=10`, and asserts the database contains exactly 10 rows for that topic. VERIFY: `pytest backend/tests/test_integration_auth_persist.py::test_end_to_end_retention_cap -v`. (cat:test; multifile:yes)
