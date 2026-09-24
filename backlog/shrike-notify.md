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

# --- research pass 2026-09-24: fresh grounded audit after the 2026-09-22 batch (delete-empty-garbage-files, wire-first-present-into-config, wire-persisted-tokens-into-list-tokens, wire-resolve-timezone-into-quiet-hours, wire-validate-tags-into-publish) landed and the backlog hit zero unchecked items. Re-verified two 2026-09-22 findings (`app/utils/garbage.py`, `app/security/scope.py::validate_scope_token`) are STILL present/unresolved in the current `overnight/feature` checkout despite being decomposed before — re-flagged below with fresh evidence rather than assumed-done. New findings driven by a full `pytest --cov=app --cov-report=term-missing` run (503 passed, 95% overall) plus manual read of every app/ module. ---
- [ ] [T1] backend/app/utils/ttl.py — `is_expired()` (the whole file) is a byte-identical duplicate of `backend/app/services/ttl.py::is_expired()` (same signature, same body). It has ZERO call sites anywhere in `app/`, `tests/`, or `scripts/` — `grep -rn "utils.ttl\b\|utils import ttl" app tests scripts` matches only a descriptive comment in `tests/test_ttl.py:46`, never an actual import. The real one wired into production is `app/services/ttl.py`, imported by `app/services/broker.py:24` (`from app.services.ttl import is_expired as _is_expired`). Confirmed orphaned by the coverage report too: `app/utils/ttl.py` doesn't even appear in the `pytest --cov=app --cov-report=term-missing` module table (pytest-cov only lists modules that get imported at least once during the run), while `app/services/ttl.py` shows up at 75%. Delete `backend/app/utils/ttl.py`. VERIFY: `cd backend && grep -rn "utils.ttl\b\|utils import ttl" app tests scripts` (currently only the comment), then after deletion `test ! -f app/utils/ttl.py` and `.venv/bin/python -m pytest -q` stays green (503 passed). (cat:backend; multifile:no) [feat:shrike-notify-20260924-delete-dead-utils-ttl-duplicate]
- [ ] [T1] backend/app/utils/garbage.py — re-verified 2026-09-24: still a single blank line (`od -c` shows just `\n`), the last remnant of a `get_greeting()` demo function whose body was removed in commit `7c423ab` ("chore: remove dead code and tests for removed get_greeting function") but the file itself was never `git rm`'d. Zero references anywhere: `grep -rn "utils.garbage\|utils import garbage" app tests scripts` returns nothing — the unrelated `backend/scripts/cleanup_garbage.py` + `backend/tests/test_cleanup_garbage.py` test a completely different "find garbage chat-artifact files/dirs" script and never touch this module. `backend/tests/test_garbage.py` no longer exists (already deleted), so there's no test to remove alongside it. Delete the file. VERIFY: `cd backend && grep -rn "utils.garbage\|utils import garbage" app tests scripts` (currently empty), then after the fix `test ! -f app/utils/garbage.py` and `.venv/bin/python -m pytest -q` stays green. (cat:backend; multifile:no) [feat:shrike-notify-20260924-delete-empty-garbage-file-for-real]
- [ ] [T1] backend/app/security/scope.py — `validate_scope_token(token, required_scope)` (lines 18-28) re-verified 2026-09-24: still present, still has ZERO call sites anywhere in `app/` or `tests/` (not even its own `tests/test_scope.py`, which only imports/tests `token_allows` and `require_wildcard_token`). `pytest --cov=app --cov-report=term-missing` confirms 0% coverage on exactly those lines (`app/security/scope.py 24 4 83% Missing 24-28`). It's also built on a stale assumption — its docstring says "Assumes token format is 'scope.signature'" but the real tokens minted by `app/services/auth.py::issue_token` are 4-part (`<scope>.<issued_at>.<ttl>.<sig>`), so `token.split(".", 1)[0]` would still work but the function was clearly never updated alongside the real format and has no test proving it. Two other test files (`tests/test_subscribe_api.py`, `tests/test_dependencies.py`) already assert other modules must never reference `validate_scope_token`, confirming it's meant to stay dead. Delete the function (leave `token_allows` and `require_wildcard_token`, which are both actually tested/used). VERIFY: `cd backend && grep -n "def validate_scope_token" app/security/scope.py` (present now, gone after the fix), then `.venv/bin/python -m pytest tests/test_scope.py -q` stays green. (cat:backend; multifile:no) [feat:shrike-notify-20260924-delete-dead-validate-scope-token]
- [ ] [T1] backend/app/persistence.py — `MessageStore.clear(topic)` (lines 139-145) has ZERO test coverage per `pytest --cov=app --cov-report=term-missing` (`app/persistence.py ... Missing ... 140-145`). Add a test that saves 1+ messages to a topic via `MessageStore.save()`, calls `clear(topic)`, and asserts `load(topic)` then returns an empty list. VERIFY: `cd backend && .venv/bin/python -m pytest tests/test_persistence.py -q --cov=app.persistence --cov-report=term-missing` (currently shows `140-145` in Missing; should disappear after the fix). (cat:test; multifile:no) [feat:shrike-notify-20260924-test-messagestore-clear]
- [ ] [T1] backend/app/persistence.py — `TokenStore.get_all_tokens()` (lines 234-248) — the method `AuthManager.list_active(scope=None)` calls when `NOTIFY_PERSIST=1` — has ZERO test coverage per `pytest --cov=app --cov-report=term-missing` (`Missing ... 236-244`). Add a test that creates tokens for 2+ different scopes via `TokenStore.create_token()`, revokes one, and asserts `get_all_tokens()` returns the rest (excluding the revoked one) across all scopes. VERIFY: `cd backend && .venv/bin/python -m pytest tests/test_persistence.py tests/test_token_model.py -q --cov=app.persistence --cov-report=term-missing` (currently shows `236-244` in Missing). (cat:test; multifile:no) [feat:shrike-notify-20260924-test-tokenstore-get-all-tokens]
- [ ] [T1] backend/app/persistence.py — `MessageStore.load()`'s invalid-`min_priority` fallback (`except ValueError: min_idx = 0`, lines 131-133), hit when a caller passes a `min_priority` string not present in `PRIORITY_LEVELS`, is untested per coverage (`Missing ... 132-133`). Add a test calling `MessageStore.load(topic, min_priority="not-a-real-priority")` on a topic with existing messages and asserting it degrades to returning everything (behaves as `min_idx=0`) rather than raising. VERIFY: `cd backend && .venv/bin/python -m pytest tests/test_persistence.py -q --cov=app.persistence --cov-report=term-missing` (currently shows `132-133` in Missing). (cat:test; multifile:no) [feat:shrike-notify-20260924-test-messagestore-load-invalid-priority]
- [ ] [T2] backend/app/persistence.py — `MessageStore.prune()`'s combined-condition path (lines 177-181: the `keep_cond = True` fallback when a topic has fewer stored rows than `max_count`, and the `ttl_cond is not None and keep_cond is not None` branch that builds `delete(...).where(base_cond, or_(ttl_cond, keep_cond))`) is untested per coverage (`Missing ... 178, 181`) — existing prune tests apparently only ever pass `ttl_seconds` OR `max_count` alone, never both on the same call. Add a test calling `prune(topic, ttl_seconds=<n>, max_count=<n>)` against a topic with a mix of expired-but-under-cap and fresh-but-over-cap messages, asserting exactly the right rows survive both conditions combined. VERIFY: `cd backend && .venv/bin/python -m pytest tests/test_persistence.py -q --cov=app.persistence --cov-report=term-missing` (currently shows `178, 181` in Missing). (cat:test; multifile:no) [feat:shrike-notify-20260924-test-messagestore-prune-combined]
- [ ] [T2] backend/app/services/auth.py — `AuthManager.list_active()`'s entire `if self._token_store is not None:` branch (lines 271-299) — the code path that actually runs for `GET /tokens` in production whenever `NOTIFY_PERSIST=1` — has ZERO test coverage per `pytest --cov=app --cov-report=term-missing` (`app/services/auth.py 161 26 84% Missing ... 272-299`), the single largest uncovered block in the module. Add tests constructing `AuthManager(token_store=<TokenStore>, signing_secret=...)` and calling `list_active()` / `list_active(scope=...)`, covering: multiple stored tokens across scopes, an expired-but-still-stored token being filtered out via the internal `verify_token()` call, and a malformed (non-4-part) stored token id being skipped via the `len(parts) != 4` guard. VERIFY: `cd backend && .venv/bin/python -m pytest tests/test_auth.py tests/test_tokens_api.py -q --cov=app.services.auth --cov-report=term-missing` (currently shows `272-299` in Missing). (cat:test; multifile:no) [feat:shrike-notify-20260924-test-authmanager-list-active-persisted]
- [ ] [T1] backend/app/services/auth.py — `AuthManager.issue()`'s `if self._signing_secret is None: raise ValueError(...)` guard (line 212) is untested per coverage (`Missing ... 212`) — every existing test apparently constructs `AuthManager(signing_secret=...)`. Add a test constructing `AuthManager()` with no `signing_secret` and asserting `.issue("some-topic")` raises `ValueError`. VERIFY: `cd backend && .venv/bin/python -m pytest tests/test_auth.py -q --cov=app.services.auth --cov-report=term-missing` (currently shows `212` in Missing). (cat:test; multifile:no) [feat:shrike-notify-20260924-test-authmanager-issue-no-secret]
- [ ] [T2] backend/app/services/auth.py — `AuthManager.revoke()`'s fire-and-forget branch (lines 233-240: when a token is unknown to the in-memory `_issued_tokens` registry and not already revoked, but a `token_store` is configured, it schedules `loop.create_task(self._token_store.revoke_token(token))` and returns `True`) is untested per coverage (`Missing ... 239-240`). Add a test running inside an active event loop that calls `.revoke()` on a token string never issued via this process's `_issued_tokens` registry, with a `token_store` configured, and asserts it returns `True`. VERIFY: `cd backend && .venv/bin/python -m pytest tests/test_auth.py -q --cov=app.services.auth --cov-report=term-missing` (currently shows `239-240` in Missing). (cat:test; multifile:no) [feat:shrike-notify-20260924-test-authmanager-revoke-unknown-token]
- [ ] [T1] backend/app/services/auth.py — module-level `get_active_tokens()`'s two filter `continue` branches (line 166: skip a revoked token; line 168: skip an expired token) are untested per coverage (`Missing ... 167, 169`) — existing tests apparently only ever populate `_issued_tokens` with live, non-expired entries. Add tests that `register_token()` an entry, then (a) `revoke_token()` it and assert `get_active_tokens()` excludes it, and (b) register one with `expires_at` already in the past and assert it's excluded too. VERIFY: `cd backend && .venv/bin/python -m pytest tests/test_auth.py -q --cov=app.services.auth --cov-report=term-missing` (currently shows `167, 169` in Missing). (cat:test; multifile:no) [feat:shrike-notify-20260924-test-get-active-tokens-filters]
- [ ] [T1] backend/app/services/ttl.py — `is_expired()`'s tz-aware-datetime passthrough branch (`_to_utc_dt`'s `if val.tzinfo is None: ... ; return val`, lines 23-25) and its default-`now`-is-None branch (line 29: `current_time = datetime.now(timezone.utc)`) are untested per coverage (`app/services/ttl.py 16 4 75% Missing 23-25, 29`) — this is the module `app/services/broker.py:24` actually uses for real message-expiry checks in production. Add tests calling `is_expired(message_created_at=<a tz-aware datetime>, ttl_seconds=<n>)` and a separate call to `is_expired(message_created_at=<a float>, ttl_seconds=<n>)` with `now` omitted entirely (exercising the real-UTC-now default instead of an injected value). VERIFY: `cd backend && .venv/bin/python -m pytest tests/test_ttl.py -q --cov=app.services.ttl --cov-report=term-missing` (currently shows `23-25, 29` in Missing). (cat:test; multifile:no) [feat:shrike-notify-20260924-test-services-ttl-branches]
