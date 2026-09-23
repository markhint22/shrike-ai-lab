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

# --- 27B-decomposed from roadmap [2026-09-19]: Delete the orphaned `truncate_body()` helper in `app/models.py` — `truncate_body(body, max (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-19]: Delete the orphaned `severity_rank()`/`is_actionable()` pair in `app/utils/severity.py` —  (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-19]: Delete the orphaned `normalize_topic()` helper in `app/utils/topic_slug.py` — this lenient (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-20]: Close the token-issuance auth bypass: `POST /tokens` is wide open even when `NOTIFY_REQUIR (review + tweak) [feat:shrike-notify-20260920-close-the-token-issuance-auth-bypass-pos] ---

# --- 27B-decomposed from roadmap [2026-09-20]: Retry/backoff-hardened Python publish client for real automation callers: `backend/app/uti (review + tweak) [feat:shrike-notify-20260920-retry-backoff-hardened-python-publish-cl] ---

# --- 27B-decomposed from roadmap [2026-09-20]: Pre-cutover smoke-check CLI: extend `backend/scripts/notify_cli.py` (or add a new `backend (review + tweak) [feat:shrike-notify-20260920-pre-cutover-smoke-check-cli-extend-backe] ---

# --- 27B-decomposed from roadmap [2026-09-20]: Cross-repo publish-contract regression test: `shared/scripts/overnight-queue/shrike_notify (review + tweak) [feat:shrike-notify-20260920-cross-repo-publish-contract-regression-t] ---

# --- 27B-decomposed from roadmap [2026-09-20]: Token minting/rotation helper for automation clients, with the scope tradeoff surfaced exp (review + tweak) [feat:shrike-notify-20260920-token-minting-rotation-helper-for-automa] ---

# --- 27B-decomposed from roadmap [2026-09-21]: Close the token-issuance auth bypass: `POST /tokens` is wide open even when `NOTIFY_REQUIR (review + tweak) [feat:shrike-notify-20260921-close-the-token-issuance-auth-bypass-pos] ---

# --- 27B-decomposed from roadmap [2026-09-21]: Retry/backoff-hardened Python publish client for real automation callers: `backend/app/uti (review + tweak) [feat:shrike-notify-20260921-retry-backoff-hardened-python-publish-cl] ---

# --- 27B-decomposed from roadmap [2026-09-21]: Pre-cutover smoke-check CLI: extend `backend/scripts/notify_cli.py` (or add a new `backend (review + tweak) [feat:shrike-notify-20260921-pre-cutover-smoke-check-cli-extend-backe] ---

# --- 27B-decomposed from roadmap [2026-09-21]: Cross-repo publish-contract regression test: `shared/scripts/overnight-queue/shrike_notify (review + tweak) [feat:shrike-notify-20260921-cross-repo-publish-contract-regression-t] ---

# --- 27B-decomposed from roadmap [2026-09-21]: Token minting/rotation helper for automation clients, with the scope tradeoff surfaced exp (review + tweak) [feat:shrike-notify-20260921-token-minting-rotation-helper-for-automa] ---

# --- 27B-decomposed from roadmap [2026-09-21]: Actually persist token revocation so it survives a restart — add a `revoked`/`revoked_at`  (review + tweak) [feat:shrike-notify-20260921-actually-persist-token-revocation-so-it-] ---

# --- 27B-decomposed from roadmap [2026-09-22]: `QuietHoursConfig.timezone`/`NOTIFY_QUIET_HOURS_TZ` is configurable but never actually applied to the real quiet-hours delivery decision — `backend/app/utils/quiet_hours.py`'s `resolve_timezone(tz_name)` is fully implemented and directly unit-tested (`tests/test_quiet_hours.py::test_resolve_timezone_valid`/`_invalid`) but has ZERO call sites anywhere outside its own test (confirmed via `grep -rn resolve_timezone app/` matching only its own definition). `is_within_quiet_hours()`/`should_deliver_now()` (called from `app/services/broker.py`'s `publish()`) always call `in_quiet_hours(dt.hour, ...)` using the message's raw UTC hour, never converting `dt` into the configured timezone first — so `NOTIFY_QUIET_HOURS_TZ`/`config.quiet_hours_config.timezone` has no actual effect on which hours count as "quiet" for any non-UTC deployment, despite being fully plumbed through `Settings`. (review + tweak) [feat:shrike-notify-20260922-wire-resolve-timezone-into-quiet-hours] ---

# --- 27B-decomposed from roadmap [2026-09-22]: The unverified-signature `validate_scope_token()`/`token_allows()` pair in `backend/app/security/scope.py` was never actually deleted despite an earlier roadmap item flagging it — re-verified 2026-09-22: `grep -rn 'validate_scope_token\|token_allows' backend/app backend/tests` still shows both functions have ZERO callers anywhere outside their own dedicated `tests/test_scope.py`, and TWO other test files (`tests/test_subscribe_api.py::test_subscribe_no_security_scope_imports`, `tests/test_dependencies.py::test_no_security_scope_references`) already assert other modules must NOT use them — confirming these functions are intentionally meant to stay dead/unused, just never actually removed. Only `require_wildcard_token` (imported by `app/routers/messages.py`) is real, live code in this file. (review + tweak) [feat:shrike-notify-20260922-delete-dead-scope-token-pair] ---

# --- 27B-decomposed from roadmap [2026-09-22]: `backend/app/utils/garbage.py` and `backend/tests/test_garbage.py` are both now fully-empty orphaned leftovers — `garbage.py` (1 byte) previously held the already-deleted `get_greeting()` demo function, and `test_garbage.py` (1 byte) is its equally-emptied test counterpart; neither is referenced anywhere (confirmed via `grep -rn 'utils.garbage\|utils import garbage' backend/app` returning nothing, and `backend/tests/test_cleanup_garbage.py` is a fully separate file testing an unrelated `scripts/cleanup_garbage.py`). (review + tweak) [feat:shrike-notify-20260922-delete-empty-garbage-files] ---

# --- 27B-decomposed from roadmap [2026-09-22]: `first_present()` in `backend/app/utils/coalesce.py` is fully implemented and unit-tested but has ZERO call sites anywhere in app/ (confirmed via `grep -rn 'utils.coalesce\|utils import coalesce\|first_present' app/` matching only its own module) — meanwhile `app/config.py`'s `message_ttl_seconds` field already hand-rolls the exact "first non-None of several env vars, else a default" pattern `first_present()` exists to express: `int(os.getenv("NOTIFY_TTL_SECONDS", os.getenv("NOTIFY_MESSAGE_TTL_SECONDS", "0")))`. (review + tweak) [feat:shrike-notify-20260922-wire-first-present-into-config] ---

# --- 27B-decomposed from roadmap [2026-09-22]: `validate_tags()` in `backend/app/utils/dedupe.py` is fully implemented and unit-tested (enforces non-empty, <=64-char, deduplicated tags) but has ZERO call sites anywhere in app/ (confirmed via `grep -rn 'utils.dedupe\|utils import dedupe\|validate_tags' app/` matching only its own module) — the real publish path (`app/routers/publish.py` line 63) instead calls `app.models.parse_tags()`, which silently strips/dedupes tags but enforces NO length cap and NO explicit rejection of invalid input, so an over-length tag is silently accepted rather than rejected with a clear error. (review + tweak) [feat:shrike-notify-20260922-wire-validate-tags-into-publish] ---

# --- 27B-decomposed from roadmap [2026-09-22]: `backend/scripts/token_mint.py` contains two full duplicate top-level script bodies back-to (review + tweak) [feat:shrike-notify-20260922-dedupe-token-mint-script] ---

# --- 27B-decomposed from roadmap [2026-09-22]: CORRECTION — tests/test_token_mint.py's duplicate test_cli_bootstrap_mint/test_cli_scope_wa (review + tweak) [feat:shrike-notify-20260922-dedupe-test-token-mint-tests] ---

# --- 27B-decomposed from roadmap [2026-09-22]: backend/tests/test_persistence.py::test_prune_by_ttl is defined EIGHT times in the same fil (review + tweak) [feat:shrike-notify-20260922-dedupe-test-prune-by-ttl] ---

# --- 27B-decomposed from roadmap [2026-09-22]: Delete the dead, differently-configured duplicate retry_delay() in backend/app/utils/backoff (review + tweak) [feat:shrike-notify-20260922-delete-dead-retry-delay] ---

# --- 27B-decomposed from roadmap [2026-09-22]: GET /tokens (list_tokens() in backend/app/routers/messages.py) always reads the in-memory, (review + tweak) [feat:shrike-notify-20260922-wire-persisted-tokens-into-list-tokens] ---

# --- 27B-decomposed from roadmap [2026-09-22]: backend/app/models.py::check_message_field_duplicates() is called TWICE at module leve (review + tweak) [feat:shrike-notify-20260922-dedupe-check-message-field-duplicates-call] ---

# --- 27B-decomposed from roadmap [2026-09-22]: backend/tests/test_ratelimit.py::test_bucket_count_tracks_distinct_keys is defined twice (review + tweak) [feat:shrike-notify-20260922-delete-empty-bucket-count-stub] ---

# --- research pass 2026-09-23: starvation-triggered grounded audit (dead code, test-coverage gaps, incomplete error handling) — cross-checked against existing backlog/roadmap entries to avoid duplicating the utils/ttl.py, validate_scope_token, quiet-hours-wiring, and token-persistence items already tracked there. ---
- [ ] [T2] backend/scripts/token_mint.py — `generate_token_payload(scope)` is dead and broken: it returns a fake token `f"{scope}.placeholder"` instead of a real HMAC-signed one, and is never called by `main()`, `mint_tokens()`, or `rotate_token()` (confirmed via `grep -rn generate_token_payload backend/` — its only caller is its own unit test, `tests/test_token_mint.py::test_generate_token_payload_scope`). Either delete it and its test, or fix it to delegate to `issue_token()` the way `mint_tokens()` already does. VERIFY: cd backend && .venv/bin/pytest -q --no-cov tests/test_token_mint.py -v. (cat:python; multifile:yes) [feat:shrike-notify-20260923-deadcode-coverage-gaps]
- [ ] [T2] backend/app/services/auth.py — `revoke_token()` (module-level, ~lines 123-136) and `AuthManager.revoke()` (~lines 218-235) persist a revocation via `loop.create_task(token_store.revoke_token(token))` and never await or inspect the result — any exception the store raises is silently swallowed, and neither path checks whether the token was ever actually issued before reporting success. `.venv/bin/pytest -q --cov=app --cov-report=term-missing` shows `AuthManager.revoke()`'s token_store branch (lines 228-234) at 0% coverage — there is no test for "revoke an unknown token while a token_store is configured", the exact case where this matters. Add existence verification (or explicitly document + test the current best-effort behavior) and close the coverage gap. VERIFY: cd backend && .venv/bin/pytest -q --cov=app --cov-report=term-missing tests/test_auth.py -k revoke (confirm lines 228-234 no longer listed as missing). (cat:python; multifile:no) [feat:shrike-notify-20260923-deadcode-coverage-gaps]
- [ ] [T2] backend/app/services/auth.py — `AuthManager.list_active()` (~lines 255-293), specifically the `if self._token_store is not None:` branch that backs `GET /tokens` when `NOTIFY_PERSIST=1`, has zero test coverage: `.venv/bin/pytest -q --cov=app --cov-report=term-missing` reports lines 266-293 of app/services/auth.py as missing — the entire persisted-listing code path (both the `scope=None`/all-scopes case via `get_all_tokens()` and the `scope="x"` case via `get_tokens_for_user()`) is unexercised by any test. Add coverage in backend/tests/test_auth.py or backend/tests/test_integration_auth_persist.py. VERIFY: cd backend && .venv/bin/pytest -q --cov=app --cov-report=term-missing tests/test_auth.py tests/test_integration_auth_persist.py (confirm lines 266-293 no longer listed as missing). (cat:test; multifile:no) [feat:shrike-notify-20260923-deadcode-coverage-gaps]
- [ ] [T2] backend/app/dependencies.py + backend/app/security/scope.py — no existing test drives `get_current_user_scoped()` (dependencies.py line 78) or `require_wildcard_token()` (security/scope.py line 49) down their "signature verification failed" 401 branch (`auth.verify_token(...)` returning `None` for a garbled/tampered bearer token) — every current auth test only tries a *missing* token or a *validly-signed* token with the wrong scope. `.venv/bin/pytest -q --cov=app --cov-report=term-missing` shows both lines as permanently missing. Add a test per dependency sending `Authorization: Bearer not-a-real-token` and asserting 401 "invalid or expired token". VERIFY: cd backend && .venv/bin/pytest -q --cov=app --cov-report=term-missing tests/test_dependencies.py tests/test_scope.py (confirm dependencies.py:78 and security/scope.py:49 no longer listed as missing). (cat:test; multifile:yes) [feat:shrike-notify-20260923-deadcode-coverage-gaps]
- [ ] [T2] backend/app/main.py — `@app.on_event("startup")` (line 93) and `@app.on_event("shutdown")` (line 126) use FastAPI's deprecated event-handler API: `.venv/bin/pytest -q` currently prints 3 `DeprecationWarning: on_event is deprecated, use lifespan event handlers instead` warnings pointing at this file. Migrate `startup_check()`/`shutdown_cleanup()` into a single `@asynccontextmanager def lifespan(app):` passed as `FastAPI(..., lifespan=lifespan)`, preserving existing behavior (insecure-secret warning, `broker.store`/`quiet_hours_config`/`ttl_seconds`/`history_size` wiring, revoked-token reload from the store, and DB engine disposal on shutdown). VERIFY: cd backend && .venv/bin/pytest -q -W error::DeprecationWarning tests/test_main_startup.py. (cat:python; multifile:no) [feat:shrike-notify-20260923-deadcode-coverage-gaps]
- [ ] [T2] backend/app/routers/messages.py + backend/app/services/broker.py + backend/app/persistence.py — `GET /{topic}/messages?min_priority=<value>` accepts any string for `min_priority` with no validation. Both `Broker.history()` (app/services/broker.py, the in-memory path's `except ValueError: min_idx = 0` fallback) and `MessageStore.load()` (app/persistence.py, the identical fallback in the DB-backed path) silently treat an unrecognized value like `min_priority=bogus` as "no minimum filter" instead of rejecting it, even though AGENTS.md states validation errors must surface as HTTP 422. Add a check (in `list_messages()` or a shared helper) that returns 422 when `min_priority` isn't one of `PRIORITY_LEVELS`. VERIFY: after the fix, with the app running, `curl -s -o /dev/null -w '%{http_code}\n' 'http://127.0.0.1:8080/alerts/messages?min_priority=bogus'` should print 422 (currently 200); also extend backend/tests/test_messages_filters.py. (cat:python; multifile:yes) [feat:shrike-notify-20260923-deadcode-coverage-gaps]
- [ ] [T1] backend/app/schemas.py — `PublishRequest`'s tag validator (`validate_tags`, the `raise ValueError("tags JSON must be an array")` branch — triggered by a syntactically-valid-JSON-but-non-list `tags` string, e.g. `{"tags": "{\"a\": 1}"}`) has zero test coverage: `.venv/bin/pytest -q --cov=app --cov-report=term-missing` reports app/schemas.py line 49 as missing. Add a test posting a JSON-object string for `tags` and asserting a 422 response. VERIFY: cd backend && .venv/bin/pytest -q --no-cov tests/test_schemas_tags.py -k json_object -v. (cat:test; multifile:no) [feat:shrike-notify-20260923-deadcode-coverage-gaps]
- [ ] [T1] backend/app/config.py — `_load_quiet_hours()` (lines 18-36) silently returns `None` (quiet hours disabled) both when `NOTIFY_QUIET_HOURS_START`/`NOTIFY_QUIET_HOURS_END` fail `int()` parsing (lines 31-32) and when they're outside the 0-23 range (line 33-34), with no log line — unlike the sibling insecure-secret check in `app/main.py::startup_check()`, which does warn on misconfiguration. An operator who sets `NOTIFY_QUIET_HOURS_START=abc` (typo) gets zero signal that quiet hours are silently disabled. Add a `logging.getLogger(__name__).warning(...)` call in both invalid branches, plus a regression test (e.g. via `caplog`). VERIFY: cd backend && .venv/bin/pytest -q --no-cov tests/test_config.py -k quiet_hours_invalid -v. (cat:python; multifile:no) [feat:shrike-notify-20260923-deadcode-coverage-gaps]
- [ ] [T1] backend/app/utils/publish_client.py — the trailing `return None` on line 125 (end of `publish_with_retry()`) is unreachable dead code: every iteration of `for attempt in range(max_retries + 1)` already returns before the loop can exit normally — either `response` (line 103, success or final-attempt-with-bad-status) or `None` from inside the `except httpx.HTTPError` branch on the final attempt (line 124). `.venv/bin/pytest -q --cov=app --cov-report=term-missing` confirms line 125 is permanently uncovered. Delete the dead line. VERIFY: cd backend && .venv/bin/pytest -q --cov=app --cov-report=term-missing tests/test_publish_client_retry.py (all other lines in the function remain covered after removal). (cat:python; multifile:no) [feat:shrike-notify-20260923-deadcode-coverage-gaps]
- [ ] [T1] backend/app/utils/publish_client.py — `publish_message()`'s `raise httpx.ConnectError("All retry attempts exhausted")` branch (line 54, taken when `publish_with_retry()` returns `None` after exhausting retries on repeated connection errors) has zero test coverage per `.venv/bin/pytest -q --cov=app --cov-report=term-missing` (line 54 listed as missing). Add a test that mocks the httpx client to always raise `httpx.ConnectError`, calls `publish_message()`, and asserts it re-raises `httpx.ConnectError`. VERIFY: cd backend && .venv/bin/pytest -q --no-cov tests/test_publish_client.py -k connect_error_exhausted -v. (cat:test; multifile:no) [feat:shrike-notify-20260923-deadcode-coverage-gaps]
