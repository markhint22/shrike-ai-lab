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

# --- 27B-decomposed from roadmap [2026-09-25]: Add a permanent AST-based duplicate-top-level-definition guard test across `backend/app/`  (review + tweak) [feat:shrike-notify-20260925-add-a-permanent-ast-based-duplicate-top-] ---

# --- 27B-decomposed from roadmap [2026-09-25]: Finally close the oscillating `backend/app/utils/ttl.py` duplicate with a permanent regres (review + tweak) [feat:shrike-notify-20260925-finally-close-the-oscillating-backend-ap] ---

# --- 27B-decomposed from roadmap [2026-09-25]: Verify and, if still broken, fix `GET /tokens` reading only the in-memory token registry i (review + tweak) [feat:shrike-notify-20260925-verify-and-if-still-broken-fix-get-token] ---

# --- 27B-decomposed from roadmap [2026-09-25]: **[HUMAN/design]** Decide and land the fate of the orphaned `severity_rank()`/`is_actionab (review + tweak) [feat:shrike-notify-20260925-human-design-decide-and-land-the-fate-of] ---

# --- 27B-decomposed from roadmap [2026-09-25]: **[HUMAN/design]** Decide and land the fate of `QuietHoursConfig.timezone`/`NOTIFY_QUIET_H (review + tweak) [feat:shrike-notify-20260925-human-design-decide-and-land-the-fate-of] ---
- [ ] [T2] backend/tests/test_publish_quiet_hours.py — Add integration-style tests verifying that messages are blocked during quiet hours in a non-UTC timezone (e.g., `America/New_York`) when the config is set. VERIFY: `python -m pytest backend/tests/test_publish_quiet_hours.py::test_publish_blocked_in_non_utc_quiet_hours -v`. (cat:test; multifile:no) [feat:shrike-notify-20260925-human-design-decide-and-land-the-fate-of]

# --- 27B-decomposed from roadmap [2026-09-25]: Add a `tail`/`watch` subcommand to `backend/scripts/notify_cli.py` that subscribes to a to (review + tweak) [feat:shrike-notify-20260925-add-a-tail-watch-subcommand-to-backend-s] ---

# --- 27B-decomposed from roadmap [2026-09-25]: Re-verify and either wire or drop `backend/app/utils/coalesce.py::first_present()` into `b (review + tweak) [feat:shrike-notify-20260925-re-verify-and-either-wire-or-drop-backen] ---

# --- 27B-decomposed from roadmap [2026-09-26]: Consolidate the duplicate `/tokens` POST+GET routes defined in both `backend/app/routers/t (review + tweak) [feat:shrike-notify-20260926-consolidate-the-duplicate-tokens-post-ge] ---

# --- 27B-decomposed from roadmap [2026-09-26]: Wire `settings.severity_gate_threshold` onto the live broker singleton, and stop duplicati (review + tweak) [feat:shrike-notify-20260926-wire-settings-severity-gate-threshold-on] ---

# --- 27B-decomposed from roadmap [2026-09-26]: Close a live, currently-unmatched blind spot in the garbage-filename pre-commit guard — `b (review + tweak) [feat:shrike-notify-20260926-close-a-live-currently-unmatched-blind-s] ---

# --- 27B-decomposed from roadmap [2026-09-26]: Run the production Docker container as a non-root user — `backend/Dockerfile` (`FROM pytho (review + tweak) [feat:shrike-notify-20260926-run-the-production-docker-container-as-a] ---

# --- 27B-decomposed from roadmap [2026-09-26]: Pin exact dependency versions in `backend/requirements.txt` instead of unbounded floors —  (review + tweak) [feat:shrike-notify-20260926-pin-exact-dependency-versions-in-backend] ---

# --- 27B-decomposed from roadmap [2026-09-26]: Add backup/editor-artifact patterns to `.gitignore` — `.gitignore` today covers `.venv/`,  (review + tweak) [feat:shrike-notify-20260926-add-backup-editor-artifact-patterns-to-g] ---

# --- 27B-decomposed from roadmap [2026-09-27]: Fix should_deliver_now()'s misleading quiet-hours docstring (review + tweak) [feat:shrike-notify-20260927-fix-misleading-quiet-hours-docstring] ---

# --- 27B-decomposed from roadmap [2026-09-27]: Delete the orphaned SSE client/parsing utility pair (review + tweak) [feat:shrike-notify-20260927-delete-orphaned-sse-utils] ---

# --- 27B-decomposed from roadmap [2026-09-27]: Delete the orphaned truncate.py helper module (review + tweak) [feat:shrike-notify-20260927-delete-orphaned-truncate-module] ---

# --- 27B-decomposed from roadmap [2026-09-27]: Close real test-coverage gaps found in a fresh pytest --cov=app run (503->605 passed since last audit, still real gaps remain) (review + tweak) [feat:shrike-notify-20260927-close-app-coverage-gaps] ---

# --- 27B-decomposed from roadmap [2026-09-27]: Harden pre_commit_check.py + cleanup_garbage.py test coverage (pre_commit_check.py is at 10% line coverage today) (review + tweak) [feat:shrike-notify-20260927-harden-precommit-cleanup-script-tests] ---

# --- 27B-decomposed from roadmap [2026-09-30]: Gate message-history, stats and topic-list reads behind auth when NOTIFY_REQUIRE_AUTH=1 —  (review + tweak) [feat:shrike-notify-20260930-gate-message-history-stats-and-topic-lis] ---

# --- 27B-decomposed from roadmap [2026-09-30]: Refuse to start when NOTIFY_REQUIRE_AUTH=1 and the signing secret is the default — `backen (review + tweak) [feat:shrike-notify-20260930-refuse-to-start-when-notify-require-auth] ---

# --- 27B-decomposed from roadmap [2026-09-30]: Apply message TTL at read time, not only on the next publish — TTL pruning runs only insid (review + tweak) [feat:shrike-notify-20260930-apply-message-ttl-at-read-time-not-only-] ---

# --- 27B-decomposed from roadmap [2026-09-30]: Make publish resilient to a failing message store — in `backend/app/services/broker.py::Br (review + tweak) [feat:shrike-notify-20260930-make-publish-resilient-to-a-failing-mess] ---

# --- 27B-decomposed from roadmap [2026-09-30]: Stop fire-and-forget token persistence from silently losing writes — `backend/app/services (review + tweak) [feat:shrike-notify-20260930-stop-fire-and-forget-token-persistence-f] ---

# --- 27B-decomposed from roadmap [2026-09-30]: Give SSE frames an `id:` and honor `Last-Event-ID` so reconnects don't replay everything — (review + tweak) [feat:shrike-notify-20260930-give-sse-frames-an-id-and-honor-last-eve] ---

# --- 27B-decomposed from roadmap [2026-10-01]: Invalid `NOTIFY_QUIET_HOURS_TZ` string causes uncaught `ValueError` in `broker.publish()`  (review + tweak) [feat:shrike-notify-20261001-invalid-notify-quiet-hours-tz-string-cau] ---

# --- 27B-decomposed from roadmap [2026-10-01]: `startup_check()` creates a `TokenStore` engine that's never closed, leaking DB connection (review + tweak) [feat:shrike-notify-20261001-startup-check-creates-a-tokenstore-engin] ---
- [ ] [T5] backend/app/main.py — Refactor `startup_check` and `shutdown_cleanup` to use a context manager or explicit lifecycle management for all DB engines to prevent leaks. VERIFY: `python -m pytest backend/tests/test_main_startup.py backend/tests/test_dependencies.py -v`. (cat:refactor; multifile:yes) [feat:shrike-notify-20261001-startup-check-creates-a-tokenstore-engin]

# --- 27B-decomposed from roadmap [2026-10-01]: `backend/tests/test_tokens_api.py` is missing despite 5+ roadmap items referencing it as t (review + tweak) [feat:shrike-notify-20261001-backend-tests-test-tokens-api-py-is-miss] ---
- [ ] [T1] backend/tests/test_tokens_api.py — Create file with `test_post_tokens_200_when_no_wildcard_exists_yet` verifying 200 response and token creation via `POST /tokens` when no wildcard token exists. VERIFY: `pytest backend/tests/test_tokens_api.py::test_post_tokens_200_when_no_wildcard_exists_yet -v`. (cat:test; multifile:no) [feat:shrike-notify-20261001-backend-tests-test-tokens-api-py-is-miss]
- [ ] [T1] backend/tests/test_tokens_api.py — Add `test_post_tokens_401_unauth_once_bootstrapped` verifying 401 response from `POST /tokens` when a wildcard token already exists in the database. VERIFY: `pytest backend/tests/test_tokens_api.py::test_post_tokens_401_unauth_once_bootstrapped -v`. (cat:test; multifile:no) [feat:shrike-notify-20261001-backend-tests-test-tokens-api-py-is-miss]
- [ ] [T1] backend/tests/test_tokens_api.py — Add `test_get_tokens_returns_issued_token` verifying `GET /tokens` returns 200 and includes the previously issued token in the JSON response body. VERIFY: `pytest backend/tests/test_tokens_api.py::test_get_tokens_returns_issued_token -v`. (cat:test; multifile:no) [feat:shrike-notify-20261001-backend-tests-test-tokens-api-py-is-miss]
- [ ] [T1] backend/tests/test_tokens_api.py — Add `test_post_tokens_revoke_removes_token` verifying `POST /tokens/revoke` returns 200 and subsequent `GET /tokens` does not include the revoked token. VERIFY: `pytest backend/tests/test_tokens_api.py::test_post_tokens_revoke_removes_token -v`. (cat:test; multifile:no) [feat:shrike-notify-20261001-backend-tests-test-tokens-api-py-is-miss]
- [ ] [T1] backend/tests/test_tokens_api.py — Add `test_post_tokens_422_invalid_scope` verifying `POST /tokens` returns 422 when the request body contains an invalid or unsupported scope value. VERIFY: `pytest backend/tests/test_tokens_api.py::test_post_tokens_422_invalid_scope -v`. (cat:test; multifile:no) [feat:shrike-notify-20261001-backend-tests-test-tokens-api-py-is-miss]

# --- 27B-decomposed from roadmap [2026-10-01]: Hardcoded `allow_origins=["*"]` CORS with no environment override — `backend/app/main.py:4 (review + tweak) [feat:shrike-notify-20261001-hardcoded-allow-origins-cors-with-no-env] ---
- [ ] [T1] backend/app/config.py — Add `cors_origins: list[str] = ["*"]` field to `Settings` class with `Field(default_factory=lambda: ["*"])`. VERIFY: `python -c "from backend.app.config import Settings; s=Settings(); assert s.cors_origins == ['*']"`. (cat:python; multifile:no) [feat:shrike-notify-20261001-hardcoded-allow-origins-cors-with-no-env]
- [ ] [T1] backend/app/config.py — Implement logic in `Settings` to parse `NOTIFY_CORS_ORIGINS` env var (comma-separated string) into a list of strings, defaulting to `["*"]` if unset or empty. VERIFY: `python -c "import os; os.environ['NOTIFY_CORS_ORIGINS']='http://a.com,http://b.com'; from backend.app.config import Settings; s=Settings(); assert s.cors_origins == ['http://a.com','http://b.com']"`. (cat:python; multifile:no) [feat:shrike-notify-20261001-hardcoded-allow-origins-cors-with-no-env]
- [ ] [T2] backend/tests/test_config.py — Add test `test_cors_origins_env_parsing` that sets `NOTIFY_CORS_ORIGINS` to a comma-separated string and asserts `Settings().cors_origins` matches the split list. VERIFY: `pytest backend/tests/test_config.py::test_cors_origins_env_parsing -v`. (cat:test; multifile:no) [feat:shrike-notify-20261001-hardcoded-allow-origins-cors-with-no-env]
- [ ] [T2] backend/tests/test_config.py — Add test `test_cors_origins_default_star` that ensures `Settings().cors_origins` is `["*"]` when `NOTIFY_CORS_ORIGINS` is not set. VERIFY: `pytest backend/tests/test_config.py::test_cors_origins_default_star -v`. (cat:test; multifile:no) [feat:shrike-notify-20261001-hardcoded-allow-origins-cors-with-no-env]
- [ ] [T3] backend/app/main.py — Replace hardcoded `allow_origins=["*"]` in `CORSMiddleware` initialization with `allow_origins=settings.cors_origins`. VERIFY: `grep -q "allow_origins=settings.cors_origins" backend/app/main.py`. (cat:python; multifile:no) [feat:shrike-notify-20261001-hardcoded-allow-origins-cors-with-no-env]
- [ ] [T3] backend/tests/test_main_startup.py — Add test `test_cors_middleware_uses_settings` that mocks `Settings` with a specific origin list and asserts `CORSMiddleware` is called with that list. VERIFY: `pytest backend/tests/test_main_startup.py::test_cors_middleware_uses_settings -v`. (cat:test; multifile:no) [feat:shrike-notify-20261001-hardcoded-allow-origins-cors-with-no-env]
- [ ] [T4] backend/tests/test_core.py — Add integration test `test_cors_preflight_rejects_mismatched_origin` that starts the app with `NOTIFY_CORS_ORIGINS=http://allowed.com`, sends an OPTIONS request with `Origin: http://evil.com`, and asserts the response does NOT contain `Access-Control-Allow-Origin`. VERIFY: `pytest backend/tests/test_core.py::test_cors_preflight_rejects_mismatched_origin -v`. (cat:test; multifile:yes) [feat:shrike-notify-20261001-hardcoded-allow-origins-cors-with-no-env]
- [ ] [T4] backend/tests/test_core.py — Add integration test `test_cors_preflight_allows_configured_origin` that starts the app with `NOTIFY_CORS_ORIGINS=http://allowed.com`, sends an OPTIONS request with `Origin: http://allowed.com`, and asserts the response contains `Access-Control-Allow-Origin: http://allowed.com`. VERIFY: `pytest backend/tests/test_core.py::test_cors_preflight_allows_configured_origin -v`. (cat:test; multifile:yes) [feat:shrike-notify-20261001-hardcoded-allow-origins-cors-with-no-env]

# --- 27B-decomposed from roadmap [2026-10-01]: Token endpoints have no rate limiting — `backend/app/routers/tokens.py`'s `POST /tokens`,  (review + tweak) [feat:shrike-notify-20261001-token-endpoints-have-no-rate-limiting-ba] ---
- [ ] [T1] backend/app/services/ratelimit.py — Add a `TokenRateLimiter` class or factory function that returns a limiter instance configured for token endpoints with a stricter limit than the default publish limiter. VERIFY: python -m pytest backend/tests/test_ratelimit.py::test_token_limiter_factory -v. (cat:python; multifile:no) [feat:shrike-notify-20261001-token-endpoints-have-no-rate-limiting-ba]
- [ ] [T2] backend/app/routers/tokens.py — Import `get_rate_limiter` from `backend.app.services.ratelimit` (or the new token-specific factory) and define a local dependency `require_token_rate_limit`. VERIFY: grep -q "from backend.app.services.ratelimit import" backend/app/routers/tokens.py && grep -q "def require_token_rate_limit" backend/app/routers/tokens.py. (cat:python; multifile:no) [feat:shrike-notify-20261001-token-endpoints-have-no-rate-limiting-ba]
- [ ] [T3] backend/app/routers/tokens.py — Add `Depends(require_token_rate_limit)` to the `POST /tokens` endpoint signature. VERIFY: python -m pytest backend/tests/test_tokens_api.py::test_post_tokens_rate_limited -v. (cat:endpoint; multifile:no) [feat:shrike-notify-20261001-token-endpoints-have-no-rate-limiting-ba]
- [ ] [T4] backend/app/routers/tokens.py — Add `Depends(require_token_rate_limit)` to the `POST /tokens/revoke` endpoint signature. VERIFY: python -m pytest backend/tests/test_tokens_api.py::test_post_revoke_rate_limited -v. (cat:endpoint; multifile:no) [feat:shrike-notify-20261001-token-endpoints-have-no-rate-limiting-ba]
- [ ] [T5] backend/app/routers/tokens.py — Add `Depends(require_token_rate_limit)` to the `GET /tokens` endpoint signature. VERIFY: python -m pytest backend/tests/test_tokens_api.py::test_get_tokens_rate_limited -v. (cat:endpoint; multifile:no) [feat:shrike-notify-20261001-token-endpoints-have-no-rate-limiting-ba]
- [ ] [T1] backend/tests/test_tokens_rate_limit.py — Create a new test file with a fixture that mocks the rate limiter state to be exhausted, then asserts `POST /tokens` returns 429. VERIFY: python -m pytest backend/tests/test_tokens_rate_limit.py::test_post_tokens_429_on_exhaustion -v. (cat:test; multifile:no) [feat:shrike-notify-20261001-token-endpoints-have-no-rate-limiting-ba]
- [ ] [T1] backend/tests/test_tokens_rate_limit.py — Add a test asserting `POST /tokens/revoke` returns 429 when the token rate limit is exhausted. VERIFY: python -m pytest backend/tests/test_tokens_rate_limit.py::test_post_revoke_429_on_exhaustion -v. (cat:test; multifile:no) [feat:shrike-notify-20261001-token-endpoints-have-no-rate-limiting-ba]
- [ ] [T1] backend/tests/test_tokens_rate_limit.py — Add a test asserting `GET /tokens` returns 429 when the token rate limit is exhausted. VERIFY: python -m pytest backend/tests/test_tokens_rate_limit.py::test_get_tokens_429_on_exhaustion -v. (cat:test; multifile:no) [feat:shrike-notify-20261001-token-endpoints-have-no-rate-limiting-ba]
- [ ] [T3] backend/app/services/ratelimit.py — Ensure the `get_rate_limiter` dependency checks the specific scope or key for token endpoints to prevent cross-contamination with publish limits. VERIFY: python -m pytest backend/tests/test_ratelimit.py::test_token_scope_isolation -v. (cat:python; multifile:no) [feat:shrike-notify-20261001-token-endpoints-have-no-rate-limiting-ba]

# --- 27B-decomposed from roadmap [2026-10-01]: `MessageStore.load()` fetches all rows then slices in Python instead of using SQL LIMIT —  (review + tweak) [feat:shrike-notify-20261001-messagestore-load-fetches-all-rows-then-] ---
- [ ] [T1] backend/app/persistence.py — Refactor `MessageStore.load()` to accept an optional `limit` parameter and apply `.limit(limit)` to the SQLAlchemy query when provided, reversing the result list if `limit` is not None. VERIFY: `pytest backend/tests/test_persistence.py -v`. (cat:python; multifile:no) [feat:shrike-notify-20261001-messagestore-load-fetches-all-rows-then-]
- [ ] [T2] backend/tests/test_persistence.py — Add a test case `test_load_with_limit_returns_correct_rows` that inserts 5 messages, calls `load(limit=2)`, and asserts the last 2 messages are returned in oldest-first order. VERIFY: `pytest backend/tests/test_persistence.py::test_load_with_limit_returns_correct_rows -v`. (cat:test; multifile:no) [feat:shrike-notify-20261001-messagestore-load-fetches-all-rows-then-]
- [ ] [T3] backend/app/persistence.py — Ensure `MessageStore.load()` handles `limit=None` by omitting the `.limit()` clause from the query chain to maintain backward compatibility for full fetches. VERIFY: `pytest backend/tests/test_persistence.py -v`. (cat:python; multifile:no) [feat:shrike-notify-20261001-messagestore-load-fetches-all-rows-then-]
- [ ] [T4] backend/app/routers/messages.py — Update the `GET /messages` endpoint handler to pass the `limit` query parameter directly to `MessageStore.load()` instead of slicing the returned list in Python. VERIFY: `pytest backend/tests/test_messages_limit.py -v`. (cat:endpoint; multifile:no) [feat:shrike-notify-20261001-messagestore-load-fetches-all-rows-then-]
- [ ] [T5] backend/tests/test_messages_limit.py — Add an integration test that populates a topic with 10 messages, requests `?limit=3`, and asserts the response contains exactly 3 items in correct chronological order. VERIFY: `pytest backend/tests/test_messages_limit.py -v`. (cat:test; multifile:no) [feat:shrike-notify-20261001-messagestore-load-fetches-all-rows-then-]
