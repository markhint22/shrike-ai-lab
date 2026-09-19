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

# --- 27B-decomposed from roadmap [2026-09-18]: Delete the unverified-signature `validate_scope_token()`/`token_allows()` pair in `backend (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-18]: `QuietHoursConfig.timezone` is a fully dead field — modeled, tested, never configurable or (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-18]: Remove the duplicate `is_quiet_hours_active()` definition in `backend/app/utils/quiet_hour (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-18]: Wire up or delete the fully-orphaned `backend/app/services/topic_stats.py` — `summarize_to (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-18]: Remove the unused `get_greeting()` demo function — `backend/app/utils/garbage.py` defines  (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-18]: Consolidate the duplicated quiet-hours/delivery-decision helpers — only one code path is a (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-18]: Wire or delete `publish_message()` in `app/utils/publish_client.py` — this async HTTP-clie (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-19]: A revoked token becomes valid again after any process restart, even with `NOTIFY_PERSIST=1 (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-19]: `app/models.py::Message` declares the `severity` field twice, back to back — lines 112-113 (review + tweak) ---
- [ ] [T1] backend/app/models.py — Remove the duplicate `severity: str | None = None` line at line 113 within the `Message` dataclass. VERIFY: `grep -n "severity" backend/app/models.py | wc -l` returns 1. (cat:python; multifile:no)
- [ ] [T2] backend/tests/test_core.py — Add a test asserting `len([f for f in dataclasses.fields(Message) if f.name == 'severity']) == 1`. VERIFY: `pytest backend/tests/test_core.py -k "test_message_severity_field_count" -v` passes. (cat:test; multifile:no)
- [ ] [T3] backend/app/models.py — Ensure the remaining `severity` field retains its original default value and type annotation exactly as before deletion. VERIFY: `python -c "from backend.app.models import Message; m=Message(); assert m.severity is None; print('OK')"` succeeds. (cat:python; multifile:no)
- [ ] [T4] backend/tests/test_broker.py — Verify existing severity round-trip tests still pass without modification after the duplicate removal. VERIFY: `pytest backend/tests/test_broker.py -k "severity" -v` passes. (cat:test; multifile:no)
- [ ] [T5] backend/app/models.py — Confirm no other fields in `Message` are duplicated by running a static check for repeated field names in the dataclass body. VERIFY: `python -c "import dataclasses; from backend.app.models import Message; names=[f.name for f in dataclasses.fields(Message)]; assert len(names)==len(set(names)); print('No duplicates')"` succeeds. (cat:python; multifile:no)
