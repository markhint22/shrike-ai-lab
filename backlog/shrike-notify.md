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
- [ ] [T1] backend/scripts/token_mint.py — Delete the first (dead, shadowed) `import argparse/json/sys/re` block and its accompanying first `def main()` definition, keeping only the second, currently-live block's imports and `main()` (the one with `FLEET_TOPICS`/`--list-topics`/`--json`). VERIFY: `grep -c "^def main" backend/scripts/token_mint.py` returns `1`. (cat:python; multifile:no) [feat:shrike-notify-20260922-dedupe-token-mint-script]
- [ ] [T1] backend/scripts/token_mint.py — Confirm exactly one top-level `import argparse` statement remains after the trim (the duplicate import block must be fully removed, not just the `def main`). VERIFY: `grep -c "^import argparse" backend/scripts/token_mint.py` returns `1`. (cat:python; multifile:no) [feat:shrike-notify-20260922-dedupe-token-mint-script]
- [ ] [T1] backend/scripts/token_mint.py — Confirm `generate_token_payload`, `validate_scope`, `rotate_token`, `mint_tokens`, `format_scope_warning`, and `build_mint_command` are each still defined exactly once (they were not part of the duplicated block and must be untouched). VERIFY: `for f in generate_token_payload validate_scope rotate_token mint_tokens format_scope_warning build_mint_command; do grep -c "^def $f" backend/scripts/token_mint.py; done` prints six `1`s. (cat:python; multifile:no) [feat:shrike-notify-20260922-dedupe-token-mint-script]
- [ ] [T2] backend/tests/test_token_mint.py — Run the full existing test file against the trimmed script to confirm both `--scope`/`--rotate` and `--list-topics`/`--json` behavior still work identically. VERIFY: `cd backend && python -m pytest tests/test_token_mint.py -v` (all pass, same pass count as before the trim). (cat:test; multifile:no) [feat:shrike-notify-20260922-dedupe-token-mint-script]
- [ ] [T2] backend/tests/test_token_mint.py — Add a permanent regression guard, `test_no_duplicate_top_level_defs_in_token_mint`, that parses `backend/scripts/token_mint.py` with `ast` and asserts no top-level `def`/`import` name is defined more than once. VERIFY: `cd backend && python -m pytest tests/test_token_mint.py::test_no_duplicate_top_level_defs_in_token_mint -v`. (cat:test; multifile:no) [feat:shrike-notify-20260922-dedupe-token-mint-script]
- [ ] [T1] backend/scripts/token_mint.py — Final safety re-grep confirming no other file in the repo imports the now-deleted duplicate `main`/import block by name (nothing should break outside this one file). VERIFY: `grep -rln "from scripts.token_mint import main" backend/` shows only `backend/tests/test_token_mint.py`. (cat:python; multifile:no) [feat:shrike-notify-20260922-dedupe-token-mint-script]

# --- 27B-decomposed from roadmap [2026-09-22]: CORRECTION — tests/test_token_mint.py's duplicate test_cli_bootstrap_mint/test_cli_scope_wa (review + tweak) [feat:shrike-notify-20260922-dedupe-test-token-mint-tests] ---
- [ ] [T1] backend/tests/test_token_mint.py — Delete the FIRST `test_cli_bootstrap_mint()` definition (the earlier of the two occurrences in the file), keeping only the second, correct definition. VERIFY: `grep -c "^def test_cli_bootstrap_mint" backend/tests/test_token_mint.py` returns `1`. (cat:test; multifile:no) [feat:shrike-notify-20260922-dedupe-test-token-mint-tests]
- [ ] [T1] backend/tests/test_token_mint.py — Delete the FIRST `test_cli_scope_warning()` definition, keeping only the second, correct definition. VERIFY: `grep -c "^def test_cli_scope_warning" backend/tests/test_token_mint.py` returns `1`. (cat:test; multifile:no) [feat:shrike-notify-20260922-dedupe-test-token-mint-tests]
- [ ] [T1] backend/tests/test_token_mint.py — Run the full file to confirm both surviving tests pass and no collection errors were introduced by the deletions. VERIFY: `cd backend && python -m pytest tests/test_token_mint.py -v` (all pass). (cat:test; multifile:no) [feat:shrike-notify-20260922-dedupe-test-token-mint-tests]
- [ ] [T2] backend/tests/test_token_mint.py — Add a permanent regression guard, `test_no_duplicate_test_definitions`, that `ast`-parses the file and asserts no top-level `def test_*` name is defined more than once — this exact class of bug ("fix" landed once already per `OVERNIGHT_PROGRESS.md` but silently re-broken) needs a guard that actually runs in CI, not just a one-off grep. VERIFY: `cd backend && python -m pytest tests/test_token_mint.py::test_no_duplicate_test_definitions -v`. (cat:test; multifile:no) [feat:shrike-notify-20260922-dedupe-test-token-mint-tests]
- [ ] [T1] backend/tests/test_token_mint.py — Confirm the full backend test suite still collects successfully with zero duplicate-name warnings from this file. VERIFY: `cd backend && python -m pytest tests/test_token_mint.py --collect-only -q` lists each test exactly once. (cat:test; multifile:no) [feat:shrike-notify-20260922-dedupe-test-token-mint-tests]

# --- 27B-decomposed from roadmap [2026-09-22]: backend/tests/test_persistence.py::test_prune_by_ttl is defined EIGHT times in the same fil (review + tweak) [feat:shrike-notify-20260922-dedupe-test-prune-by-ttl] ---
- [ ] [T1] backend/tests/test_persistence.py — Delete 7 of the 8 duplicate `test_prune_by_ttl` definitions, keeping exactly the first occurrence; all interleaved, differently-named tests between the duplicates (e.g. `test_store_load_filters_limit_priority_tag`, `test_message_record_severity_field`) must remain untouched. VERIFY: `grep -c "^async def test_prune_by_ttl" backend/tests/test_persistence.py` returns `1`. (cat:test; multifile:no) [feat:shrike-notify-20260922-dedupe-test-prune-by-ttl]
- [ ] [T1] backend/tests/test_persistence.py — Run the full file to confirm every other (non-duplicate) test still passes after the removal, with the total collected-test count reduced by exactly 7. VERIFY: `cd backend && python -m pytest tests/test_persistence.py -v` (all pass). (cat:test; multifile:no) [feat:shrike-notify-20260922-dedupe-test-prune-by-ttl]
- [ ] [T2] backend/tests/test_persistence.py — Use the now-freed test slot to add real new coverage: `test_prune_by_ttl_zero_is_noop` asserting `store.prune(topic, ttl_seconds=0)` deletes nothing (matches `Broker._purge_expired_and_capped`'s `if self.ttl_seconds > 0` guard semantics). VERIFY: `cd backend && python -m pytest tests/test_persistence.py::test_prune_by_ttl_zero_is_noop -v`. (cat:test; multifile:no) [feat:shrike-notify-20260922-dedupe-test-prune-by-ttl]
- [ ] [T2] backend/tests/test_persistence.py — Add `test_prune_by_ttl_empty_topic` asserting `store.prune()` against a topic with zero rows returns `0` rather than raising. VERIFY: `cd backend && python -m pytest tests/test_persistence.py::test_prune_by_ttl_empty_topic -v`. (cat:test; multifile:no) [feat:shrike-notify-20260922-dedupe-test-prune-by-ttl]
- [ ] [T2] backend/tests/test_persistence.py — Add `test_prune_by_ttl_negative_is_noop` asserting a negative `ttl_seconds` behaves like `0` (no rows deleted), not as "everything is expired". VERIFY: `cd backend && python -m pytest tests/test_persistence.py::test_prune_by_ttl_negative_is_noop -v`. (cat:test; multifile:no) [feat:shrike-notify-20260922-dedupe-test-prune-by-ttl]
- [ ] [T1] backend/tests/test_persistence.py — Add a permanent regression guard, `test_no_duplicate_test_definitions`, `ast`-parsing this file and asserting no top-level `def`/`async def` test name repeats — this file specifically has demonstrated re-duplication risk (8x landings of the same task). VERIFY: `cd backend && python -m pytest tests/test_persistence.py::test_no_duplicate_test_definitions -v`. (cat:test; multifile:no) [feat:shrike-notify-20260922-dedupe-test-prune-by-ttl]

# --- 27B-decomposed from roadmap [2026-09-22]: Delete the dead, differently-configured duplicate retry_delay() in backend/app/utils/backoff (review + tweak) [feat:shrike-notify-20260922-delete-dead-retry-delay] ---
- [ ] [T1] backend/app/utils/backoff.py — Re-confirm `retry_delay()` has zero non-test callers before deleting anything (safety re-grep). VERIFY: `grep -rn "retry_delay" backend/app backend/scripts` matches only its own definition in `backend/app/utils/backoff.py`. (cat:python; multifile:no) [feat:shrike-notify-20260922-delete-dead-retry-delay]
- [ ] [T1] backend/app/utils/backoff.py — Delete the `retry_delay()` function, keeping `backoff_delay()` (the one real caller, `app/utils/publish_client.py::publish_with_retry()`, is unaffected) fully intact. VERIFY: `grep -c "^def retry_delay" backend/app/utils/backoff.py` returns `0`. (cat:python; multifile:no) [feat:shrike-notify-20260922-delete-dead-retry-delay]
- [ ] [T1] backend/tests/test_backoff.py — Remove `test_retry_delay` and `test_retry_delay_custom_base_and_cap` (the only references to the now-deleted function). VERIFY: `grep -c "retry_delay" backend/tests/test_backoff.py` returns `0`. (cat:test; multifile:no) [feat:shrike-notify-20260922-delete-dead-retry-delay]
- [ ] [T1] backend/tests/test_backoff.py — Confirm `backoff_delay()`'s own coverage still passes in full after the trim. VERIFY: `cd backend && python -m pytest tests/test_backoff.py -v` (all pass). (cat:test; multifile:no) [feat:shrike-notify-20260922-delete-dead-retry-delay]
- [ ] [T1] backend/app/utils/backoff.py — Final safety re-grep confirming nothing anywhere in the repo still imports `retry_delay` by name. VERIFY: `grep -rn "import retry_delay\|backoff import.*retry_delay" backend/` returns nothing. (cat:python; multifile:no) [feat:shrike-notify-20260922-delete-dead-retry-delay]

# --- 27B-decomposed from roadmap [2026-09-22]: GET /tokens (list_tokens() in backend/app/routers/messages.py) always reads the in-memory, (review + tweak) [feat:shrike-notify-20260922-wire-persisted-tokens-into-list-tokens] ---
- [ ] [T2] backend/app/services/auth.py — Add `AuthManager.list_active(scope: str | None = None) -> list[dict]`: when `self._token_store` is set, return `await self._token_store.get_tokens_for_user(scope)` (or all scopes if `scope is None` — extend `TokenStore` if needed); when no store is set, fall back to the existing module-level `get_active_tokens()`, optionally filtered by `scope`. VERIFY: `cd backend && python -m pytest tests/test_auth.py::test_authmanager_list_active_uses_store_when_present -v`. (cat:backend; multifile:no) [feat:shrike-notify-20260922-wire-persisted-tokens-into-list-tokens]
- [ ] [T2] backend/tests/test_auth.py — Add `test_authmanager_list_active_falls_back_without_store` asserting `AuthManager(signing_secret=...).list_active()` (no `token_store`) returns the same shape as today's `get_active_tokens()`. VERIFY: `cd backend && python -m pytest tests/test_auth.py::test_authmanager_list_active_falls_back_without_store -v`. (cat:test; multifile:no) [feat:shrike-notify-20260922-wire-persisted-tokens-into-list-tokens]
- [ ] [T2] backend/app/routers/messages.py — Update `list_tokens()` to depend on `Depends(get_auth_manager)` (already imported from `app.dependencies`, matching `issue_token`/`revoke_token`'s existing DI) and call `auth_manager.list_active()` instead of the bare module-level `auth.get_active_tokens()`. VERIFY: `grep -n "auth_manager.list_active" backend/app/routers/messages.py` returns a match. (cat:backend; multifile:no) [feat:shrike-notify-20260922-wire-persisted-tokens-into-list-tokens]
- [ ] [T3] backend/tests/test_tokens_api.py — Add `test_list_tokens_visible_across_store_instances_when_persisted`: with `NOTIFY_PERSIST=1`, issue a token via one `AuthManager`/`TokenStore` instance, construct a SECOND independent `AuthManager`/`TokenStore` against the same sqlite file (genuinely simulating a restart/different worker, not reusing the same Python object), and assert `GET /tokens` (via the second instance's `list_active()`) still returns the token. VERIFY: `cd backend && python -m pytest tests/test_tokens_api.py::test_list_tokens_visible_across_store_instances_when_persisted -v`. (cat:test; multifile:yes) [feat:shrike-notify-20260922-wire-persisted-tokens-into-list-tokens]
- [ ] [T1] backend/tests/test_tokens_api.py — Add `test_list_tokens_unpersisted_unchanged` confirming `GET /tokens` behavior is byte-for-byte unchanged when `NOTIFY_PERSIST=0` (default) — no regression for the non-persisted path. VERIFY: `cd backend && python -m pytest tests/test_tokens_api.py::test_list_tokens_unpersisted_unchanged -v`. (cat:test; multifile:no) [feat:shrike-notify-20260922-wire-persisted-tokens-into-list-tokens]
- [ ] [T3] backend/app/services/auth.py — Since `Token` DB rows (`app/models.py::Token`) store only `id`/`scope`/`created_at` with no expiry column, have `list_active()`'s store-backed path re-verify each row's own `id` (the full encoded token string) via `verify_token()` before including it, so an expired-but-still-present persisted row is excluded rather than reported as active. VERIFY: `cd backend && python -m pytest tests/test_tokens_api.py::test_list_tokens_excludes_expired_persisted_tokens -v`. (cat:backend; multifile:no) [feat:shrike-notify-20260922-wire-persisted-tokens-into-list-tokens]
- [ ] [T1] backend/tests/test_tokens_api.py — Run the full `test_tokens_api.py` and `test_persistence.py` suites together to confirm zero regressions from the wiring change. VERIFY: `cd backend && python -m pytest tests/test_tokens_api.py tests/test_persistence.py -v` (all pass). (cat:test; multifile:no) [feat:shrike-notify-20260922-wire-persisted-tokens-into-list-tokens]

# --- 27B-decomposed from roadmap [2026-09-22]: backend/app/models.py::check_message_field_duplicates() is called TWICE at module leve (review + tweak) [feat:shrike-notify-20260922-dedupe-check-message-field-duplicates-call] ---
- [ ] [T1] backend/app/models.py — Remove the redundant second top-level `check_message_field_duplicates()` call, keeping exactly one immediately after the `Message` class definition. VERIFY: `grep -c "^check_message_field_duplicates()" backend/app/models.py` returns `1`. (cat:python; multifile:no) [feat:shrike-notify-20260922-dedupe-check-message-field-duplicates-call]
- [ ] [T1] backend/tests/test_models.py — Confirm the existing import-time subprocess test still passes after the trim (must not have implicitly relied on the call firing twice). VERIFY: `cd backend && python -m pytest tests/test_models.py -v` (all pass). (cat:test; multifile:no) [feat:shrike-notify-20260922-dedupe-check-message-field-duplicates-call]
- [ ] [T1] backend/app/models.py — Confirm `import app.models` still exits `0` in a clean subprocess after the trim. VERIFY: `cd backend && python3 -c "import app.models"` exits 0. (cat:python; multifile:no) [feat:shrike-notify-20260922-dedupe-check-message-field-duplicates-call]
- [ ] [T1] backend/app/models.py — Re-grep to confirm no other module-level statement in this file is similarly copy-paste-duplicated. VERIFY: `grep -c "^check_message_field_duplicates()" backend/app/models.py` returns exactly `1` (re-run as a final safety check). (cat:python; multifile:no) [feat:shrike-notify-20260922-dedupe-check-message-field-duplicates-call]
- [ ] [T1] backend/app/models.py — Run the full backend test suite once to confirm the trim caused zero collateral regressions (this function's `ValueError` path, if ever broken, would fail FastAPI startup entirely). VERIFY: `cd backend && python -m pytest -q` (full suite green). (cat:test; multifile:no) [feat:shrike-notify-20260922-dedupe-check-message-field-duplicates-call]

# --- 27B-decomposed from roadmap [2026-09-22]: backend/tests/test_ratelimit.py::test_bucket_count_tracks_distinct_keys is defined twice (review + tweak) [feat:shrike-notify-20260922-delete-empty-bucket-count-stub] ---
- [ ] [T1] backend/tests/test_ratelimit.py — Delete the first, empty-bodied `test_bucket_count_tracks_distinct_keys()` stub (docstring only, no assertions), keeping the second, fully-assertive definition. VERIFY: `grep -c "^def test_bucket_count_tracks_distinct_keys" backend/tests/test_ratelimit.py` returns `1`. (cat:test; multifile:no) [feat:shrike-notify-20260922-delete-empty-bucket-count-stub]
- [ ] [T1] backend/tests/test_ratelimit.py — Run the full file to confirm the surviving test still passes and no other tests were disturbed by the deletion. VERIFY: `cd backend && python -m pytest tests/test_ratelimit.py -v` (all pass). (cat:test; multifile:no) [feat:shrike-notify-20260922-delete-empty-bucket-count-stub]
- [ ] [T1] backend/tests/test_ratelimit.py — Re-run an `ast`-based duplicate-definition check against this file and confirm it reports zero duplicate top-level names. VERIFY: `cd backend && python3 -c "import ast,collections; d=collections.Counter(n.name for n in ast.parse(open('tests/test_ratelimit.py').read()).body if isinstance(n,(ast.FunctionDef,ast.AsyncFunctionDef))); print([k for k,v in d.items() if v>1])"` prints `[]`. (cat:test; multifile:no) [feat:shrike-notify-20260922-delete-empty-bucket-count-stub]
- [ ] [T1] backend/tests/test_ratelimit.py — Confirm `RateLimiter.bucket_count`'s `allow()`/`reset()` coverage is unaffected by the stub removal. VERIFY: `cd backend && python -m pytest tests/test_ratelimit.py -k bucket_count -v` (all pass). (cat:test; multifile:no) [feat:shrike-notify-20260922-delete-empty-bucket-count-stub]
- [ ] [T1] backend/tests/test_ratelimit.py — Confirm no other file in the repo also defines `test_bucket_count_tracks_distinct_keys` (final safety check that this dedup didn't remove intentionally-separate coverage). VERIFY: `grep -rn "def test_bucket_count_tracks_distinct_keys" backend/tests/` shows exactly one match, in this file. (cat:test; multifile:no) [feat:shrike-notify-20260922-delete-empty-bucket-count-stub]
