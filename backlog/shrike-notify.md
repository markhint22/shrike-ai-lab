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

# --- 27B-decomposed from roadmap [2026-10-01]: `backend/tests/test_tokens_api.py` is missing despite 5+ roadmap items referencing it as t (review + tweak) [feat:shrike-notify-20261001-backend-tests-test-tokens-api-py-is-miss] ---

# --- 27B-decomposed from roadmap [2026-10-01]: Hardcoded `allow_origins=["*"]` CORS with no environment override — `backend/app/main.py:4 (review + tweak) [feat:shrike-notify-20261001-hardcoded-allow-origins-cors-with-no-env] ---

# --- 27B-decomposed from roadmap [2026-10-01]: Token endpoints have no rate limiting — `backend/app/routers/tokens.py`'s `POST /tokens`,  (review + tweak) [feat:shrike-notify-20261001-token-endpoints-have-no-rate-limiting-ba] ---

# --- 27B-decomposed from roadmap [2026-10-01]: `MessageStore.load()` fetches all rows then slices in Python instead of using SQL LIMIT —  (review + tweak) [feat:shrike-notify-20261001-messagestore-load-fetches-all-rows-then-] ---

# --- 27B-decomposed from roadmap [2026-10-02]: `_limiter` in `publish.py` is frozen at module import time — `backend/app/routers/publish. (review + tweak) [feat:shrike-notify-20261002-limiter-in-publish-py-is-frozen-at-modul] ---

# --- deterministic work supply 2026-10-14 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- 27B-decomposed from roadmap [2026-10-17]: ⚠️ CORRECTION: invalid NOTIFY_QUIET_HOURS_TZ still 500s every publish — `broker.py:142` ca (review + tweak) [feat:shrike-notify-20261017-correction-invalid-notify-quiet-hours-tz] ---

# --- 27B-decomposed from roadmap [2026-10-17]: ⚠️ CORRECTION: `Broker.is_actionable()` silently drops severity="high" messages — `broker. (review + tweak) [feat:shrike-notify-20261017-correction-broker-is-actionable-silently] ---

# --- 27B-decomposed from roadmap [2026-10-17]: Delete dead `AuthManager.revoke()` with untracked fire-and-forget task — `auth.py:262` def (review + tweak) [feat:shrike-notify-20261017-delete-dead-authmanager-revoke-with-untr] ---

# --- 27B-decomposed from roadmap [2026-10-17]: Delete dead `SELECT Token` in `TokenStore.revoke_token()` — `persistence.py:283-285` execu (review + tweak) [feat:shrike-notify-20261017-delete-dead-select-token-in-tokenstore-r] ---

# --- 27B-decomposed from roadmap [2026-10-17]: Delete `test_requirements_pin.py` and `utils/versions.py` — `test_requirements_pin.py:9-12 (review + tweak) [feat:shrike-notify-20261017-delete-test-requirements-pin-py-and-util] ---

# --- 27B-decomposed from roadmap [2026-10-18]: GET /topics returns empty after process restart with NOTIFY_PERSIST=1 — `broker.topics()`  (review + tweak) [feat:shrike-notify-20261018-get-topics-returns-empty-after-process-r] ---

# --- deterministic work supply 2026-10-18 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- 27B-decomposed from roadmap [2026-10-18]: broker.persistence_failures counter never surfaced in health endpoint — `broker.py:79,128` (review + tweak) [feat:shrike-notify-20261018-broker-persistence-failures-counter-neve] ---

# --- 27B-decomposed from roadmap [2026-10-18]: test_no_duplicate_definitions.py guard excludes tests/ — allowing duplicate test functions (review + tweak) [feat:shrike-notify-20261018-test-no-duplicate-definitions-py-guard-e] ---

# --- 27B-decomposed from roadmap [2026-10-18]: `format_sse_frame()` in subscribe.py is dead — only its own test calls it — `subscribe.py: (review + tweak) [feat:shrike-notify-20261018-format-sse-frame-in-subscribe-py-is-dead] ---

# --- 27B-decomposed from roadmap [2026-10-18]: `TokenStore.load_revoked_tokens()` is dead — startup_check never calls it — `persistence.p (review + tweak) [feat:shrike-notify-20261018-tokenstore-load-revoked-tokens-is-dead-s] ---

# --- 27B-decomposed from roadmap [2026-10-18]: `require_wildcard_scope()` and `dispose_token_store()` in dependencies.py are both dead —  (review + tweak) [feat:shrike-notify-20261018-require-wildcard-scope-and-dispose-token] ---

# --- 27B-decomposed from roadmap [2026-10-18]: SSE history replay leaks `persisted: false` for DB-backed messages — `Message.persisted: b (review + tweak) [feat:shrike-notify-20261018-sse-history-replay-leaks-persisted-false] ---

# --- 27B-decomposed from roadmap [2026-10-18]: Test `configure_logging` — `backend/app/logging_config.py:55` defines public `configure_lo (review + tweak) [feat:shrike-notify-20261018-test-configure-logging-backend-app-loggi] ---

# --- 27B-decomposed from roadmap [2026-10-19]: Test `health_detailed` — `backend/app/main.py:227` defines public `health_detailed` with z (review + tweak) [feat:shrike-notify-20261019-test-health-detailed-backend-app-main-py] ---

# --- 27B-decomposed from roadmap [2026-10-19]: Test `custom_openapi` — `backend/app/main.py:52` defines public `custom_openapi` with zero (review + tweak) [feat:shrike-notify-20261019-test-custom-openapi-backend-app-main-py-] ---

# --- 27B-decomposed from roadmap [2026-10-19]: Test `require_wildcard_or_bootstrap` — Add tests for the untested public function at `back (review + tweak) [feat:shrike-notify-20261019-test-require-wildcard-or-bootstrap-add-t] ---

# --- 27B-decomposed from roadmap [2026-10-19]: Test `list_tokens` — Add tests for the untested public function at `backend/app/routers/to (review + tweak) [feat:shrike-notify-20261019-test-list-tokens-add-tests-for-the-untes] ---

# --- 27B-decomposed from roadmap [2026-10-20]: Health endpoint permanently returns 503 after any DB blip because it uses the lifetime cou (review + tweak) [feat:shrike-notify-20261020-health-endpoint-permanently-returns-503-] ---

# --- 27B-decomposed from roadmap [2026-10-20]: Fix `broker._history` deque closure capturing wrong `history_size` — `backend/app/services (review + tweak) [feat:shrike-notify-20261020-fix-broker-history-deque-closure-capturi] ---

# --- 27B-decomposed from roadmap [2026-10-20]: `/health/detailed` always returns `status: "ok"` even when persistence is degraded — `back (review + tweak) [feat:shrike-notify-20261020-health-detailed-always-returns-status-ok] ---

# --- 27B-decomposed from roadmap [2026-10-20]: `schemas.py:TokenRequest` with `ge=1` constraint is a dead divergent duplicate — `backend/ (review + tweak) [feat:shrike-notify-20261020-schemas-py-tokenrequest-with-ge-1-constr] ---

# --- 27B-decomposed from roadmap [2026-10-20]: REST `GET /{topic}/messages` silently drops `persisted` field while SSE/WebSocket expose i (review + tweak) [feat:shrike-notify-20261020-rest-get-topic-messages-silently-drops-p] ---

# --- 27B-decomposed from roadmap [2026-10-20]: `test_no_duplicate_definitions.py` has an exact-duplicate AST scan that masks the still-op (review + tweak) [feat:shrike-notify-20261020-test-no-duplicate-definitions-py-has-an-] ---

# --- 27B-decomposed from roadmap [2026-10-20]: Fix smoke-check SSE check: publish before subscribing — `backend/scripts/notify_smoke_chec (review + tweak) [feat:shrike-notify-20261020-fix-smoke-check-sse-check-publish-before] ---

# --- 27B-decomposed from roadmap [2026-10-20]: Fix smoke-check auth_rejection check false-fails on no-auth servers — `backend/scripts/not (review + tweak) [feat:shrike-notify-20261020-fix-smoke-check-auth-rejection-check-fal] ---

# --- 27B-decomposed from roadmap [2026-10-21]: Fix `_resolve_health_status()` logic bug — `backend/app/main.py:199-205`: `_resolve_health (review + tweak) [feat:shrike-notify-20261021-fix-resolve-health-status-logic-bug-back] ---

# --- 27B-decomposed from roadmap [2026-10-21]: Wire `publish.startup_check()` into app startup — `backend/app/routers/publish.py:78-82` d (review + tweak) [feat:shrike-notify-20261021-wire-publish-startup-check-into-app-star] ---

# --- 27B-decomposed from roadmap [2026-10-21]: Delete 3 dead `Settings` fields in `config.py` — `backend/app/config.py:112-122` defines ` (review + tweak) [feat:shrike-notify-20261021-delete-3-dead-settings-fields-in-config-] ---

# --- 27B-decomposed from roadmap [2026-10-21]: Fix normalize_topic to avoid trailing hyphens after truncation — `backend/app/utils/topic_ (review + tweak) [feat:shrike-notify-20261021-fix-normalize-topic-to-avoid-trailing-hy] ---

# --- 27B-decomposed from roadmap [2026-10-21]: Fix SSE/WS duplicate frame delivery when a message is published during the subscribe-to-hi (review + tweak) [feat:shrike-notify-20261021-fix-sse-ws-duplicate-frame-delivery-when] ---

# --- 27B-decomposed from roadmap [2026-10-21]: Delete empty `backend/app/utils/truncate.py` and `backend/tests/test_truncate.py` — both f (review + tweak) [feat:shrike-notify-20261021-delete-empty-backend-app-utils-truncate-] ---

# --- 27B-decomposed from roadmap [2026-10-28]: WebSocket subscribers can resume after disconnect without loss — SSE already honors `Last- (review + tweak) [feat:shrike-notify-20261028-websocket-subscribers-can-resume-after-d] ---

# --- 27B-decomposed from roadmap [2026-10-28]: Drop slow subscribers cleanly instead of silently losing messages forever — `backend/app/s (review + tweak) [feat:shrike-notify-20261028-drop-slow-subscribers-cleanly-instead-of] ---

# --- 27B-decomposed from roadmap [2026-10-28]: Accept webhook-style JSON bodies on publish — `PublishRequest` in `backend/app/schemas.py` (review + tweak) [feat:shrike-notify-20261028-accept-webhook-style-json-bodies-on-publ] ---

# --- 27B-decomposed from roadmap [2026-10-28]: Token scopes can be a topic pattern, not only `*` or one exact topic — `backend/app/securi (review + tweak) [feat:shrike-notify-20261028-token-scopes-can-be-a-topic-pattern-not-] ---

# --- 27B-decomposed from roadmap [2026-10-28]: Token listing shows when each token was last used — `TokenResult` in `backend/app/schemas. (review + tweak) [feat:shrike-notify-20261028-token-listing-shows-when-each-token-was-] ---

# --- 27B-decomposed from roadmap [2026-10-28]: Topic stats report storage used — `GET /{topic}/stats` (`backend/app/routers/messages.py:: (review + tweak) [feat:shrike-notify-20261028-topic-stats-report-storage-used-get-topi] ---

# --- 27B-decomposed from roadmap [2026-10-28]: Per-topic retention override — retention count is one global `history_size` (`NOTIFY_HISTO (review + tweak) [feat:shrike-notify-20261028-per-topic-retention-override-retention-c] ---

# --- 27B-decomposed from roadmap [2026-10-28]: Quiet hours deliver one coalesced summary afterwards instead of losing deferred messages t (review + tweak) [feat:shrike-notify-20261028-quiet-hours-deliver-one-coalesced-summar] ---

# --- 27B-decomposed from roadmap [2026-10-28]: Test `record_token_usage` and wire into token validation flow — `backend/app/services/auth (review + tweak) [feat:shrike-notify-20261028-test-record-token-usage-and-wire-into-to] ---

# --- 27B-decomposed from roadmap [2026-10-28]: Test `get_last_used_at` for token audit trail — `backend/app/services/auth.py:370` defines (review + tweak) [feat:shrike-notify-20261028-test-get-last-used-at-for-token-audit-tr] ---

# --- 27B-decomposed from roadmap [2026-11-01]: Keep delivering to the remaining subscribers after one slow subscriber is dropped — in `ba (review + tweak) [feat:shrike-notify-20261101-keep-delivering-to-the-remaining-subscri] ---

# --- 27B-decomposed from roadmap [2026-11-01]: Bound the per-connection `seen_ids` dedupe set in SSE and WebSocket streams — `backend/app (review + tweak) [feat:shrike-notify-20261101-bound-the-per-connection-seen-ids-dedupe] ---

# --- 27B-decomposed from roadmap [2026-11-01]: Cap `Broker.held_quiet_messages` per topic — `backend/app/services/broker.py::Broker.publi (review + tweak) [feat:shrike-notify-20261101-cap-broker-held-quiet-messages-per-topic] ---

# --- 27B-decomposed from roadmap [2026-11-01]: Actually apply per-topic retention overrides in the running service — `Settings.topic_hist (review + tweak) [feat:shrike-notify-20261101-actually-apply-per-topic-retention-overr] ---

# --- 27B-decomposed from roadmap [2026-11-01]: Stop the token usage registries leaking after revoke/expiry — `backend/app/services/auth.p (review + tweak) [feat:shrike-notify-20261101-stop-the-token-usage-registries-leaking-] ---

# --- 27B-decomposed from roadmap [2026-11-01]: Make `GET /tokens` report `last_used_at` for real — `TokenResult` in `backend/app/schemas. (review + tweak) [feat:shrike-notify-20261101-make-get-tokens-report-last-used-at-for-] ---

# --- 27B-decomposed from roadmap [2026-11-01]: Reject `*` inside topic names while still allowing it in token scopes — `backend/app/model (review + tweak) [feat:shrike-notify-20261101-reject-inside-topic-names-while-still-al] ---

# --- 27B-decomposed from roadmap [2026-11-01]: Add subscribe-side tests for pattern-scoped tokens — pattern scopes (`ci-*`) are covered f (review + tweak) [feat:shrike-notify-20261101-add-subscribe-side-tests-for-pattern-sco] ---

# --- 27B-decomposed from roadmap [2026-11-01]: Rate limit publishes per token scope as the roadmap's C1 requires — `backend/app/routers/p (review + tweak) [feat:shrike-notify-20261101-rate-limit-publishes-per-token-scope-as-] ---

# --- 27B-decomposed from roadmap [2026-11-01]: Document every env var in the README and guard against drift — the env table in `README.md (review + tweak) [feat:shrike-notify-20261101-document-every-env-var-in-the-readme-and] ---

# --- 27B-decomposed from roadmap [2026-11-01]: Prove store pruning is idempotent — roadmap C5 requires "cleanup is idempotent" but `backe (review + tweak) [feat:shrike-notify-20261101-prove-store-pruning-is-idempotent-roadma] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Tokens for dotted topic names fail with a 500 although `validate_topic` allows `.` — token (review + tweak) [feat:shrike-notify-20261102-tokens-for-dotted-topic-names-fail-with-] ---

# --- 27B-decomposed from roadmap [2026-11-02]: `GET /{topic}/messages?limit=N&min_priority=...` returns fewer than N messages for the in- (review + tweak) [feat:shrike-notify-20261102-get-topic-messages-limit-n-min-priority-] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Same limit-before-filter defect on the persisted path — `backend/app/persistence.py::Messa (review + tweak) [feat:shrike-notify-20261102-same-limit-before-filter-defect-on-the-p] ---

# --- 27B-decomposed from roadmap [2026-11-02]: A malformed or non-positive env var crashes every request instead of falling back to its d (review + tweak) [feat:shrike-notify-20261102-a-malformed-or-non-positive-env-var-cras] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Bound the number of concurrent subscribers per topic — `backend/app/services/broker.py::Br (review + tweak) [feat:shrike-notify-20261102-bound-the-number-of-concurrent-subscribe] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Quiet-hours flush summary ignores messages evicted by the per-topic cap and never resets t (review + tweak) [feat:shrike-notify-20261102-quiet-hours-flush-summary-ignores-messag] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Let HTTP pollers fetch only new messages with `after_id` on `GET /{topic}/messages` — SSE  (review + tweak) [feat:shrike-notify-20261102-let-http-pollers-fetch-only-new-messages] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Accept `last_event_id` as a query parameter on the SSE endpoint, matching the WebSocket ro (review + tweak) [feat:shrike-notify-20261102-accept-last-event-id-as-a-query-paramete] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Send proxy-safe headers on the SSE stream — `backend/app/routers/subscribe.py::subscribe`  (review + tweak) [feat:shrike-notify-20261102-send-proxy-safe-headers-on-the-sse-strea] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Surface live broker state on `/health/detailed` — `backend/app/services/broker.py::Broker. (review + tweak) [feat:shrike-notify-20261102-surface-live-broker-state-on-health-deta] ---

# --- 27B-decomposed from roadmap [2026-11-04]: Quiet-hours held messages are only flushed by the NEXT publish to the same topic, so a top (review + tweak) [feat:shrike-notify-20261104-quiet-hours-held-messages-are-only-flush] ---

# --- 27B-decomposed from roadmap [2026-11-04]: `Broker._drop_counts` leaks every unsubscribed queue that ever dropped a message, and `sum (review + tweak) [feat:shrike-notify-20261104-broker-drop-counts-leaks-every-unsubscri] ---

# --- 27B-decomposed from roadmap [2026-11-04]: `NOTIFY_MAX_SUBSCRIBERS_PER_TOPIC=0` cannot disable the cap although the README and the Se (review + tweak) [feat:shrike-notify-20261104-notify-max-subscribers-per-topic-0-canno] ---

# --- 27B-decomposed from roadmap [2026-11-04]: README env table documents defaults and formats that do not match the code, and nothing ch (review + tweak) [feat:shrike-notify-20261104-readme-env-table-documents-defaults-and-] ---

# --- 27B-decomposed from roadmap [2026-11-04]: `publish_with_retry` ignores the server's `Retry-After` on 429 even though the publish end (review + tweak) [feat:shrike-notify-20261104-publish-with-retry-ignores-the-server-s-] ---

# --- 27B-decomposed from roadmap [2026-11-04]: SSE/WS replay on connect is capped at the global `NOTIFY_HISTORY_SIZE`, ignoring per-topic (review + tweak) [feat:shrike-notify-20261104-sse-ws-replay-on-connect-is-capped-at-th] ---

# --- 27B-decomposed from roadmap [2026-11-04]: Browser `EventSource` clients cannot authenticate to the SSE endpoint — `backend/app/depen (review + tweak) [feat:shrike-notify-20261104-browser-eventsource-clients-cannot-authe] ---

# --- 27B-decomposed from roadmap [2026-11-04]: Token and revoked-token DB rows are never pruned, so `tokens`/`revoked_tokens` grow foreve (review + tweak) [feat:shrike-notify-20261104-token-and-revoked-token-db-rows-are-neve] ---

# --- 27B-decomposed from roadmap [2026-11-04]: Test `request_validation_handler` — `backend/app/main.py:96` defines public `request_valid (review + tweak) [feat:shrike-notify-20261104-test-request-validation-handler-backend-] ---

# --- 27B-decomposed from roadmap [2026-11-04]: Test `max_body_bytes` middleware — `backend/app/middleware.py:9` defines public `max_body_ (review + tweak) [feat:shrike-notify-20261104-test-max-body-bytes-middleware-backend-a] ---

# --- 27B-decomposed from roadmap [2026-11-06]: Test `get_current_user_scoped_sse` — `backend/app/dependencies.py:118` defines public `get (review + tweak) [feat:shrike-notify-20261106-test-get-current-user-scoped-sse-backend] ---

# --- 27B-decomposed from roadmap [2026-11-06]: Test `require_topic_and_auth_sse` — `backend/app/dependencies.py:100` defines public `requ (review + tweak) [feat:shrike-notify-20261106-test-require-topic-and-auth-sse-backend-] ---

# --- 27B-decomposed from roadmap [2026-11-06]: The WebSocket endpoint `GET /{topic}/ws` is dead in the deployed container because no WebS (review + tweak) [feat:shrike-notify-20261106-the-websocket-endpoint-get-topic-ws-is-d] ---

# --- 27B-decomposed from roadmap [2026-11-06]: A non-string `severity` makes `POST /{topic}` return 500 and a boolean `priority` is silen (review + tweak) [feat:shrike-notify-20261106-a-non-string-severity-makes-post-topic-r] ---

# --- 27B-decomposed from roadmap [2026-11-06]: The README env-table check is vacuous (always SKIPPED) and README documents wrong defaults (review + tweak) [feat:shrike-notify-20261106-the-readme-env-table-check-is-vacuous-al] ---

# --- 27B-decomposed from roadmap [2026-11-06]: `validate_topic`/`validate_scope` accept a trailing newline — `backend/app/models.py` uses (review + tweak) [feat:shrike-notify-20261106-validate-topic-validate-scope-accept-a-t] ---

# --- 27B-decomposed from roadmap [2026-11-06]: One test sleeps 180 s of real time and eats a third of the 351 s suite — `backend/tests/te (review + tweak) [feat:shrike-notify-20261106-one-test-sleeps-180-s-of-real-time-and-e] ---

# --- 27B-decomposed from roadmap [2026-11-06]: Browser JS on another origin cannot read the rate-limit, Retry-After or request-id headers (review + tweak) [feat:shrike-notify-20261106-browser-js-on-another-origin-cannot-read] ---

# --- 27B-decomposed from roadmap [2026-11-06]: `GET /{topic}/messages?after_id=` returns the NEWEST `limit` messages after the id, so a p (review + tweak) [feat:shrike-notify-20261106-get-topic-messages-after-id-returns-the-] ---

# --- 27B-decomposed from roadmap [2026-11-06]: The OpenAPI schema omits auth and the 401/429 responses on the token and history routes ev (review + tweak) [feat:shrike-notify-20261106-the-openapi-schema-omits-auth-and-the-40] ---

# --- 27B-decomposed from roadmap [2026-11-06]: `POST /{topic}` documents 401/422/429 but not the 400 (NUL byte) and 413 (body too large)  (review + tweak) [feat:shrike-notify-20261106-post-topic-documents-401-422-429-but-not] ---

# --- 27B-decomposed from roadmap [2026-11-06]: README API section is stale versus the real routes and shows a token format that no longer (review + tweak) [feat:shrike-notify-20261106-readme-api-section-is-stale-versus-the-r] ---

# --- 27B-decomposed from roadmap [2026-11-06]: `app/middleware.py::max_body_bytes()` re-implements `Settings.max_body_bytes` (the same `m (review + tweak) [feat:shrike-notify-20261106-app-middleware-py-max-body-bytes-re-impl] ---

# --- 27B-decomposed from roadmap [2026-11-06]: `Broker.topics()` (and so `GET /topics`) keeps listing topics whose retained messages have (review + tweak) [feat:shrike-notify-20261106-broker-topics-and-so-get-topics-keeps-li] ---

# --- 27B-decomposed from roadmap [2026-11-06]: `_env_float` accepts `nan` and `inf`, so one bad env value silently breaks severity gating (review + tweak) [feat:shrike-notify-20261106-env-float-accepts-nan-and-inf-so-one-bad] ---

# --- 27B-decomposed from roadmap [2026-11-06]: `NOTIFY_REQUIRE_AUTH=true` (or `True`, `yes`, `on`) silently leaves the service OPEN with  (review + tweak) [feat:shrike-notify-20261106-notify-require-auth-true-or-true-yes-on-] ---

# --- 27B-decomposed from roadmap [2026-11-06]: A JSON body containing `NaN`/`Infinity` or a lone UTF-16 surrogate makes `POST /{topic}` r (review + tweak) [feat:shrike-notify-20261106-a-json-body-containing-nan-infinity-or-a] ---

# --- 27B-decomposed from roadmap [2026-11-06]: A single publish with a lone-surrogate tag poisons the whole topic: `GET /{topic}/messages (review + tweak) [feat:shrike-notify-20261106-a-single-publish-with-a-lone-surrogate-t] ---

# --- 27B-decomposed from roadmap [2026-11-06]: `notify_cli.py watch` dies after 5 seconds of silence with an empty error message, so it c (review + tweak) [feat:shrike-notify-20261106-notify-cli-py-watch-dies-after-5-seconds] ---

# --- 27B-decomposed from roadmap [2026-11-06]: Tags `null` and nested values are silently turned into the strings `"None"`, `"['x']"` and (review + tweak) [feat:shrike-notify-20261106-tags-null-and-nested-values-are-silently] ---

# --- 27B-decomposed from roadmap [2026-11-06]: `publish_with_retry` sleeps for `nan` seconds when the server sends `Retry-After: nan` - ` (review + tweak) [feat:shrike-notify-20261106-publish-with-retry-sleeps-for-nan-second] ---

# --- 27B-decomposed from roadmap [2026-11-06]: `notify_cli.load_payload` accepts JSON that is not an object and crashes with a traceback  (review + tweak) [feat:shrike-notify-20261106-notify-cli-load-payload-accepts-json-tha] ---

# --- 27B-decomposed from roadmap [2026-11-06]: `MessageStore.prune(max_count=0)` deletes nothing, so a topic configured to retain zero me (review + tweak) [feat:shrike-notify-20261106-messagestore-prune-max-count-0-deletes-n] ---

# --- 27B-decomposed from roadmap [2026-11-06]: `cleanup_garbage.find_garbage_paths` skips `.github` (and any directory with `.git`/`venv` (review + tweak) [feat:shrike-notify-20261106-cleanup-garbage-find-garbage-paths-skips] ---

# --- 27B-decomposed from roadmap [2026-11-06]: `NOTIFY_DATABASE_URL` in the form hosting providers hand out crashes startup with a confus (review + tweak) [feat:shrike-notify-20261106-notify-database-url-in-the-form-hosting-] ---

# --- 27B-decomposed from roadmap [2026-11-06]: `notify_cli.fetch_sse_stream` (the engine behind the `watch` subcommand) has no test that  (review + tweak) [feat:shrike-notify-20261106-notify-cli-fetch-sse-stream-the-engine-b] ---

# --- 27B-decomposed from roadmap [2026-11-06]: `TokenStore.prune_expired` has no test for the rows it must keep - `backend/app/persistenc (review + tweak) [feat:shrike-notify-20261106-tokenstore-prune-expired-has-no-test-for] ---

# --- 27B-decomposed from roadmap [2026-11-09]: `backoff_delay`/`retry_delay` raise OverflowError for a large attempt number instead of re (review + tweak) [feat:shrike-notify-20261109-backoff-delay-retry-delay-raise-overflow] ---

# --- 27B-decomposed from roadmap [2026-11-09]: `QuietHoursManager(max_held=0)` crashes with IndexError on the first `hold()`, and `is_wit (review + tweak) [feat:shrike-notify-20261109-quiethoursmanager-max-held-0-crashes-wit] ---

# --- 27B-decomposed from roadmap [2026-11-09]: `summarize_topic` and `get_topic_stats` crash on the dict messages their docstrings say th (review + tweak) [feat:shrike-notify-20261109-summarize-topic-and-get-topic-stats-cras] ---

# --- 27B-decomposed from roadmap [2026-11-09]: `filter_expired` reads the wrong key, so real message dicts (which carry `created_at`) are (review + tweak) [feat:shrike-notify-20261109-filter-expired-reads-the-wrong-key-so-re] ---

# --- 27B-decomposed from roadmap [2026-11-09]: `normalize_priority` raises OverflowError for an infinite float instead of falling back to (review + tweak) [feat:shrike-notify-20261109-normalize-priority-raises-overflowerror-] ---

# --- 27B-decomposed from roadmap [2026-11-09]: `normalize_topic` with a non-positive `max_length` slices from the wrong end and returns a (review + tweak) [feat:shrike-notify-20261109-normalize-topic-with-a-non-positive-max-] ---

# --- 27B-decomposed from roadmap [2026-11-09]: `notify_smoke_check.check_publish_roundtrip` crashes with a traceback instead of reporting (review + tweak) [feat:shrike-notify-20261109-notify-smoke-check-check-publish-roundtr] ---

# --- 27B-decomposed from roadmap [2026-11-09]: `notify_cli.check_sse_reception` has no timeout, so `run_smoke_checks` hangs forever on a  (review + tweak) [feat:shrike-notify-20261109-notify-cli-check-sse-reception-has-no-ti] ---

# --- 27B-decomposed from roadmap [2026-11-09]: `test_startup_sets_broker_ttl` and `test_startup_sets_broker_severity_gate_threshold` asse (review + tweak) [feat:shrike-notify-20261109-test-startup-sets-broker-ttl-and-test-st] ---

# --- 27B-decomposed from roadmap [2026-11-09]: `test_startup_check_initializes_limiter` never asserts that the limiter was initialised -  (review + tweak) [feat:shrike-notify-20261109-test-startup-check-initializes-limiter-n] ---

# --- 27B-decomposed from roadmap [2026-11-09]: The container image has no `.dockerignore`, so `COPY . .` in `backend/Dockerfile` bakes lo (review + tweak) [feat:shrike-notify-20261109-the-container-image-has-no-dockerignore-] ---

# --- 27B-decomposed from roadmap [2026-11-09]: A deploy/restart waits forever on open SSE/WebSocket connections because uvicorn has no gr (review + tweak) [feat:shrike-notify-20261109-a-deploy-restart-waits-forever-on-open-s] ---

# --- 27B-decomposed from roadmap [2026-11-10]: `parse_tags` raises TypeError for a non-iterable scalar tags value instead of returning an (review + tweak) [feat:shrike-notify-20261110-parse-tags-raises-typeerror-for-a-non-it] ---

# --- 27B-decomposed from roadmap [2026-11-10]: No test checks that the Railway healthcheck path is a real route, so renaming `/health` wo (review + tweak) [feat:shrike-notify-20261110-no-test-checks-that-the-railway-healthch] ---

# --- 27B-decomposed from roadmap [2026-11-10]: No test guarantees that every third-party package imported by `backend/app` and `backend/s (review + tweak) [feat:shrike-notify-20261110-no-test-guarantees-that-every-third-part] ---

# --- 27B-decomposed from roadmap [2026-11-10]: `app/utils/dedupe.py` carries two byte-for-byte identical LRU set classes, `_BoundedSeen`  (review + tweak) [feat:shrike-notify-20261110-app-utils-dedupe-py-carries-two-byte-for] ---

# --- 27B-decomposed from roadmap [2026-11-10]: `validate_topic`'s exact length boundary and non-string rejection are not pinned: the exis (review + tweak) [feat:shrike-notify-20261110-validate-topic-s-exact-length-boundary-a] ---

# --- 27B-decomposed from roadmap [2026-11-10]: `Message.to_ntfy_dict()` hands out the message's own `tags` list, so a caller that appends (review + tweak) [feat:shrike-notify-20261110-message-to-ntfy-dict-hands-out-the-messa] ---

# --- 27B-decomposed from roadmap [2026-11-10]: `_redact_param` (the per-parameter core of query-token log redaction) has no direct test - (review + tweak) [feat:shrike-notify-20261110-redact-param-the-per-parameter-core-of-q] ---

# --- 27B-decomposed from roadmap [2026-11-10]: `RedactTokenFilter.filter` fallback for a record whose arguments do not match its format s (review + tweak) [feat:shrike-notify-20261110-redacttokenfilter-filter-fallback-for-a-] ---

# --- 27B-decomposed from roadmap [2026-11-10]: `AuthManager.revoke` for a token that is not in the in-memory registry has untested outcom (review + tweak) [feat:shrike-notify-20261110-authmanager-revoke-for-a-token-that-is-n] ---
- [ ] [T1] backend/tests/test_auth_manager_revoke_unknown.py — Add `_FakeStore` class with `rows` and `revoked` lists, and async methods `revoke_token`, `get_all_tokens`, and `get_tokens_for_user`. VERIFY: `cd backend && python3 -m pytest tests/test_auth_manager_revoke_unknown.py --collect-only -q`. (cat:test; multifile:no) [feat:shrike-notify-20261110-authmanager-revoke-for-a-token-that-is-n]
- [ ] [T2] backend/tests/test_auth_manager_revoke_unknown.py — Add `test_revoke_unknown_token_without_store_or_loop_returns_false` asserting `AuthManager().revoke("never-issued") is False` and `AuthManager(token_store=_FakeStore()).revoke("never-issued") is False`. VERIFY: `cd backend && python3 -m pytest tests/test_auth_manager_revoke_unknown.py::test_revoke_unknown_token_without_store_or_loop_returns_false -q`. (cat:test; multifile:no) [feat:shrike-notify-20261110-authmanager-revoke-for-a-token-that-is-n]
- [ ] [T2] backend/tests/test_auth_manager_revoke_unknown.py — Add `test_revoke_unknown_token_with_store_and_loop_schedules_persistence` asserting `AuthManager(token_store=store).revoke("other-worker-token") is True`, awaiting sleep, and checking `store.revoked == ["other-worker-token"]`. VERIFY: `cd backend && python3 -m pytest tests/test_auth_manager_revoke_unknown.py::test_revoke_unknown_token_with_store_and_loop_schedules_persistence -q`. (cat:test; multifile:no) [feat:shrike-notify-20261110-authmanager-revoke-for-a-token-that-is-n]
- [ ] [T1] backend/tests/test_auth_manager_revoke_unknown.py — Run full test file to ensure all fixtures, classes, and tests pass together. VERIFY: `cd backend && python3 -m pytest tests/test_auth_manager_revoke_unknown.py -q`. (cat:test; multifile:no) [feat:shrike-notify-20261110-authmanager-revoke-for-a-token-that-is-n]

# --- 27B-decomposed from roadmap [2026-11-10]: `AuthService.get_last_used_at` and the usage counters are untested together - `backend/app (review + tweak) [feat:shrike-notify-20261110-authservice-get-last-used-at-and-the-usa] ---
- [ ] [T1] backend/tests/test_auth_service_last_used.py — Add file with `_clean` autouse fixture monkeypatching `auth._issued_tokens`, `auth._revoked_tokens`, `auth._last_used`, and `auth._usage_counts` to empty collections. VERIFY: `cd backend && python3 -m pytest tests/test_auth_service_last_used.py --collect-only -q`. (cat:test; multifile:no) [feat:shrike-notify-20261110-authservice-get-last-used-at-and-the-usa]
- [ ] [T1] backend/tests/test_auth_service_last_used.py — Add `test_auth_service_get_last_used_at_and_usage_count` asserting `AuthService().get_last_used_at("t1") is None` before any usage. VERIFY: `cd backend && python3 -m pytest tests/test_auth_service_last_used.py::test_auth_service_get_last_used_at_and_usage_count -q`. (cat:test; multifile:no) [feat:shrike-notify-20261110-authservice-get-last-used-at-and-the-usa]
- [ ] [T1] backend/tests/test_auth_service_last_used.py — Extend `test_auth_service_get_last_used_at_and_usage_count` to call `auth.record_token_usage("t1", now=123.0)` and `auth.record_token_usage("t1", now=456.0)`, then assert `svc.get_last_used_at("t1") == 456.0`. VERIFY: `cd backend && python3 -m pytest tests/test_auth_service_last_used.py::test_auth_service_get_last_used_at_and_usage_count -q`. (cat:test; multifile:no) [feat:shrike-notify-20261110-authservice-get-last-used-at-and-the-usa]
- [ ] [T1] backend/tests/test_auth_service_last_used.py — Extend `test_auth_service_get_last_used_at_and_usage_count` to assert `auth.get_token_usage_count("t1") == 2` and `auth.get_token_usage_count("never") == 0`. VERIFY: `cd backend && python3 -m pytest tests/test_auth_service_last_used.py::test_auth_service_get_last_used_at_and_usage_count -q`. (cat:test; multifile:no) [feat:shrike-notify-20261110-authservice-get-last-used-at-and-the-usa]

# --- 27B-decomposed from roadmap [2026-11-10]: `AuthManager.list_active` with a persistent store skips expired and malformed token ids, w (review + tweak) [feat:shrike-notify-20261110-authmanager-list-active-with-a-persisten] ---
- [ ] [T3] backend/app/services/auth.py — Modify `AuthManager.list_active` to explicitly filter out token IDs that do not split into four dot-separated parts before calling `verify_token`, ensuring malformed IDs are skipped without raising exceptions. VERIFY: `cd backend && python3 -m pytest tests/test_auth_manager_list_active_store.py -q`. (cat:python; multifile:no) [feat:shrike-notify-20261110-authmanager-list-active-with-a-persisten]
- [ ] [T1] backend/tests/test_auth_manager_list_active_store.py — Create file with `import time`, `from app.services import auth`, autouse fixture `_clean(monkeypatch)` patching `auth._issued_tokens`, `auth._revoked_tokens`, `auth._last_used`, `auth._usage_counts`, and class `_FakeStore` with `rows`, `revoked`, `revoke_token`, `get_all_tokens`, `get_tokens_for_user`. VERIFY: `cd backend && python3 -m pytest tests/test_auth_manager_list_active_store.py --collect-only -q`. (cat:test; multifile:no) [feat:shrike-notify-20261110-authmanager-list-active-with-a-persisten]
- [ ] [T2] backend/tests/test_auth_manager_list_active_store.py — Add async test `test_list_active_with_store_skips_expired_and_malformed_ids` constructing `AuthManager` with `_FakeStore` containing valid, expired, and malformed token rows, asserting `list_active()` returns only the valid token with correct scope/expires_at and `list_active(scope="other")` returns empty. VERIFY: `cd backend && python3 -m pytest tests/test_auth_manager_list_active_store.py::test_list_active_with_store_skips_expired_and_malformed_ids -q`. (cat:test; multifile:no) [feat:shrike-notify-20261110-authmanager-list-active-with-a-persisten]
- [ ] [T4] backend/tests/test_auth_manager_list_active_store.py — Add assertion in `test_list_active_with_store_skips_expired_and_malformed_ids` verifying that the `_FakeStore.revoke_token` method is NOT called for the malformed ID "garbage" (i.e., `store.revoked == []`). VERIFY: `cd backend && python3 -m pytest tests/test_auth_manager_list_active_store.py::test_list_active_with_store_skips_expired_and_malformed_ids -q`. (cat:test; multifile:no) [feat:shrike-notify-20261110-authmanager-list-active-with-a-persisten]
- [ ] [T5] backend/tests/test_auth_manager_list_active_store.py — Add assertion in `test_list_active_with_store_skips_expired_and_malformed_ids` verifying that the returned token entry's `expires_at` is strictly greater than `time.time()`. VERIFY: `cd backend && python3 -m pytest tests/test_auth_manager_list_active_store.py::test_list_active_with_store_skips_expired_and_malformed_ids -q`. (cat:test; multifile:no) [feat:shrike-notify-20261110-authmanager-list-active-with-a-persisten]

# --- 27B-decomposed from roadmap [2026-11-11]: `issue_token` persistence failure outside an event loop is untested - `backend/app/service (review + tweak) [feat:shrike-notify-20261111-issue-token-persistence-failure-outside-] ---
- [ ] [T2] backend/tests/test_auth_issue_token_store_failure_without_loop.py — Add autouse fixture `reset_auth_state` that monkeypatches `auth._issued_tokens` to `{}` and `auth._revoked_tokens` to `set()`. VERIFY: `cd backend && python3 -m pytest tests/test_auth_issue_token_store_failure_without_loop.py -q --collect-only`. (cat:test; multifile:no) [feat:shrike-notify-20261111-issue-token-persistence-failure-outside-]
- [ ] [T3] backend/tests/test_auth_issue_token_store_failure_without_loop.py — Add test function `test_issue_token_without_loop_logs_and_returns_when_store_write_fails` that calls `auth.issue_token` with `_FailingStore`, asserts token prefix, verification, and error log message. VERIFY: `cd backend && python3 -m pytest tests/test_auth_issue_token_store_failure_without_loop.py::test_issue_token_without_loop_logs_and_returns_when_store_write_fails -q`. (cat:test; multifile:no) [feat:shrike-notify-20261111-issue-token-persistence-failure-outside-]
- [ ] [T4] backend/tests/test_auth_issue_token_store_failure_without_loop.py — Ensure imports for `logging`, `pytest`, and `app.services.auth` are present at the top of the file. VERIFY: `cd backend && python3 -c "import ast; tree=ast.parse(open('tests/test_auth_issue_token_store_failure_without_loop.py').read()); names=[n.name for node in ast.walk(tree) if isinstance(node, ast.Import) for n in node.names]; assert 'logging' in names or any('auth' in str(n) for n in names); print('OK')"`. (cat:test; multifile:no) [feat:shrike-notify-20261111-issue-token-persistence-failure-outside-]
- [ ] [T5] backend/tests/test_auth_issue_token_store_failure_without_loop.py — Run the full test file to confirm all assertions pass and no collection errors occur. VERIFY: `cd backend && python3 -m pytest tests/test_auth_issue_token_store_failure_without_loop.py -q`. (cat:test; multifile:no) [feat:shrike-notify-20261111-issue-token-persistence-failure-outside-]

# --- 27B-decomposed from roadmap [2026-11-11]: `record_token_usage` store failure outside an event loop is untested - `backend/app/servic (review + tweak) [feat:shrike-notify-20261111-record-token-usage-store-failure-outside] ---
- [ ] [T3] backend/tests/test_auth_record_usage_store_failure_without_loop.py — Add test `test_record_token_usage_without_loop_logs_and_keeps_memory_when_store_write_fails` that calls `auth.record_token_usage("tok", now=123.0, token_store=_FailingStore())` under `caplog.at_level(logging.ERROR, logger=auth._logger.name)`. VERIFY: `cd backend && python3 -m pytest tests/test_auth_record_usage_store_failure_without_loop.py::test_record_token_usage_without_loop_logs_and_keeps_memory_when_store_write_fails -q`. (cat:test; multifile:no) [feat:shrike-notify-20261111-record-token-usage-store-failure-outside]
- [ ] [T2] backend/tests/test_auth_record_usage_store_failure_without_loop.py — Add autouse fixture `reset_auth_state` that monkeypatches `auth._last_used` to `{}` and `auth._usage_counts` to `{}`. VERIFY: `cd backend && python3 -m pytest tests/test_auth_record_usage_store_failure_without_loop.py --collect-only -q | grep "test_record_token_usage_without_loop_logs_and_keeps_memory_when_store_write_fails"`. (cat:test; multifile:no) [feat:shrike-notify-20261111-record-token-usage-store-failure-outside]
- [ ] [T4] backend/tests/test_auth_record_usage_store_failure_without_loop.py — In the test, assert `auth.get_last_used_at("tok") == 123.0` and `auth.get_token_usage_count("tok") == 1`. VERIFY: `cd backend && python3 -m pytest tests/test_auth_record_usage_store_failure_without_loop.py::test_record_token_usage_without_loop_logs_and_keeps_memory_when_store_write_fails -q`. (cat:test; multifile:no) [feat:shrike-notify-20261111-record-token-usage-store-failure-outside]
- [ ] [T5] backend/tests/test_auth_record_usage_store_failure_without_loop.py — In the test, assert that `caplog.text` contains "Failed to persist token usage". VERIFY: `cd backend && python3 -m pytest tests/test_auth_record_usage_store_failure_without_loop.py::test_record_token_usage_without_loop_logs_and_keeps_memory_when_store_write_fails -q`. (cat:test; multifile:no) [feat:shrike-notify-20261111-record-token-usage-store-failure-outside]

# --- 27B-decomposed from roadmap [2026-11-11]: `should_deliver_now` timezone override and priority rules in broker.py are untested - `bac (review + tweak) [feat:shrike-notify-20261111-should-deliver-now-timezone-override-and] ---
- [ ] [T1] backend/tests/test_broker_should_deliver_now_tz_override.py — Add `test_should_deliver_now_tz_override_and_priority_rules` verifying `should_deliver_now` behavior with `QuietHoursConfig(start=22, end=7, timezone="UTC")`, including `ValueError` for string `tz`, case-insensitive priority handling, and `ZoneInfo("Asia/Tokyo")` override. VERIFY: `cd backend && python3 -m pytest tests/test_broker_should_deliver_now_tz_override.py::test_should_deliver_now_tz_override_and_priority_rules -q`. (cat:test; multifile:no) [feat:shrike-notify-20261111-should-deliver-now-timezone-override-and]

# --- 27B-decomposed from roadmap [2026-11-11]: The guarded-name branch of `cleanup_garbage` is untested - `backend/scripts/cleanup_garbag (review + tweak) [feat:shrike-notify-20261111-the-guarded-name-branch-of-cleanup-garba] ---
- [ ] [T1] backend/tests/test_cleanup_garbage_guarded_path_block.py — Add `test_guarded_garbage_name_blocks_scan_and_check_reports_warning` that inserts `backend/scripts` into `sys.path`, imports `cleanup_garbage`, uses `monkeypatch.chdir(tmp_path)`, writes `"Looking at the broker notes.txt"`, asserts `pytest.raises(RuntimeError, match="Guard blocked processing of guarded path")` on `find_garbage_paths()`, and verifies `check()` returns 0 with the specific warning in stdout. VERIFY: `cd backend && python3 -m pytest tests/test_cleanup_garbage_guarded_path_block.py -q`. (cat:test; multifile:no) [feat:shrike-notify-20261111-the-guarded-name-branch-of-cleanup-garba]

# --- 27B-decomposed from roadmap [2026-11-11]: `MaxBodyBytesMiddleware` with a non-numeric `Content-Length` is untested - `backend/app/mi (review + tweak) [feat:shrike-notify-20261111-maxbodybytesmiddleware-with-a-non-numeri] ---
- [ ] [T1] backend/tests/test_middleware_content_length_non_numeric.py — Add `test_non_numeric_content_length_is_not_rejected_early` that patches `max_body_bytes` to 10, defines an inner ASGI app returning 200, and asserts the middleware passes through non-numeric `Content-Length` without early rejection. VERIFY: `cd backend && python3 -m pytest tests/test_middleware_content_length_non_numeric.py::test_non_numeric_content_length_is_not_rejected_early -q`. (cat:test; multifile:no) [feat:shrike-notify-20261111-maxbodybytesmiddleware-with-a-non-numeri]

# --- 27B-decomposed from roadmap [2026-11-11]: `notify_cli.check_health` and `check_auth_rejection` failure paths are untested - `backend (review + tweak) [feat:shrike-notify-20261111-notify-cli-check-health-and-check-auth-r] ---
- [ ] [T1] backend/tests/test_notify_cli_health_and_auth_probe_failures.py — Add `sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "scripts"))` and import `check_health`, `check_auth_rejection` from `notify_cli`. VERIFY: `cd backend && python3 -c "import sys; sys.path.insert(0, 'scripts'); from notify_cli import check_health, check_auth_rejection; print('ok')"`. (cat:test; multifile:no) [feat:shrike-notify-20261111-notify-cli-check-health-and-check-auth-r]
- [ ] [T1] backend/tests/test_notify_cli_health_and_auth_probe_failures.py — Add helper `_client(handler)` returning `httpx.AsyncClient(transport=httpx.MockTransport(handler))`. VERIFY: `cd backend && python3 -m pytest tests/test_notify_cli_health_and_auth_probe_failures.py --collect-only -q | grep _client`. (cat:test; multifile:no) [feat:shrike-notify-20261111-notify-cli-check-health-and-check-auth-r]
- [ ] [T2] backend/tests/test_notify_cli_health_and_auth_probe_failures.py — Add `async def test_check_health_true_for_200_ok()` asserting `check_health` returns True for `httpx.Response(200, json={"status": "ok"})`. VERIFY: `cd backend && python3 -m pytest tests/test_notify_cli_health_and_auth_probe_failures.py::test_check_health_true_for_200_ok -q`. (cat:test; multifile:no) [feat:shrike-notify-20261111-notify-cli-check-health-and-check-auth-r]
- [ ] [T2] backend/tests/test_notify_cli_health_and_auth_probe_failures.py — Add `async def test_check_health_false_for_non_200_degraded_non_json_and_transport_error()` asserting False for 503, `{"status": "degraded"}`, non-JSON text, and `httpx.ConnectError`. VERIFY: `cd backend && python3 -m pytest tests/test_notify_cli_health_and_auth_probe_failures.py::test_check_health_false_for_non_200_degraded_non_json_and_transport_error -q`. (cat:test; multifile:no) [feat:shrike-notify-20261111-notify-cli-check-health-and-check-auth-r]
- [ ] [T2] backend/tests/test_notify_cli_health_and_auth_probe_failures.py — Add `async def test_check_auth_rejection_true_only_for_401()` asserting True for 401 and False for 200, 403, and `httpx.ConnectError`. VERIFY: `cd backend && python3 -m pytest tests/test_notify_cli_health_and_auth_probe_failures.py::test_check_auth_rejection_true_only_for_401 -q`. (cat:test; multifile:no) [feat:shrike-notify-20261111-notify-cli-check-health-and-check-auth-r]

# --- 27B-decomposed from roadmap [2026-11-11]: `notify_cli.check_sse_reception` and the default smoke payload are untested - `backend/scr (review + tweak) [feat:shrike-notify-20261111-notify-cli-check-sse-reception-and-the-d] ---
- [ ] [T2] backend/scripts/notify_cli.py — Modify `check_sse_reception` to ensure it correctly handles the `Authorization` header injection and returns False on `httpx.ConnectError` or non-200 status, while returning True only upon receiving a `data:` line. VERIFY: `cd backend && python3 -m pytest tests/test_notify_cli_sse_reception_and_default_payload.py::test_check_sse_reception_header_status_and_error_paths -q` (cat:python; multifile:no) [feat:shrike-notify-20261111-notify-cli-check-sse-reception-and-the-d]
- [ ] [T2] backend/scripts/notify_cli.py — Modify `run_smoke_checks` to ensure the default payload for the publish round-trip is strictly `{"body": "smoke-check"}` following the auth probe `{"body": "test"}`, and that the returned dictionary contains exactly the keys `health`, `auth_rejection`, `publish_roundtrip`, and `sse_reception`. VERIFY: `cd backend && python3 -m pytest tests/test_notify_cli_sse_reception_and_default_payload.py::test_run_smoke_checks_default_payload_is_smoke_check_after_auth_probe -q` (cat:python; multifile:no) [feat:shrike-notify-20261111-notify-cli-check-sse-reception-and-the-d]
- [ ] [T1] backend/tests/test_notify_cli_sse_reception_and_default_payload.py — Add `async def test_check_sse_reception_header_status_and_error_paths` verifying `check_sse_reception` returns True for valid SSE data with Bearer header, and False for keepalive-only, 401 response, and ConnectError. VERIFY: `cd backend && python3 -m pytest tests/test_notify_cli_sse_reception_and_default_payload.py::test_check_sse_reception_header_status_and_error_paths -q` (cat:test; multifile:no) [feat:shrike-notify-20261111-notify-cli-check-sse-reception-and-the-d]
- [ ] [T1] backend/tests/test_notify_cli_sse_reception_and_default_payload.py — Add `async def test_run_smoke_checks_default_payload_is_smoke_check_after_auth_probe` verifying `run_smoke_checks` result keys are exactly `health`, `auth_rejection`, `publish_roundtrip`, `sse_reception` and POST bodies are `[{"body": "test"}, {"body": "smoke-check"}]`. VERIFY: `cd backend && python3 -m pytest tests/test_notify_cli_sse_reception_and_default_payload.py::test_run_smoke_checks_default_payload_is_smoke_check_after_auth_probe -q` (cat:test; multifile:no) [feat:shrike-notify-20261111-notify-cli-check-sse-reception-and-the-d]
- [ ] [T3] backend/tests/test_notify_cli_sse_reception_and_default_payload.py — Ensure the test file imports `httpx`, `json`, and the necessary functions from `backend.scripts.notify_cli` are correctly resolved for the MockTransport handlers. VERIFY: `cd backend && python3 -m pytest tests/test_notify_cli_sse_reception_and_default_payload.py -q` (cat:test; multifile:no) [feat:shrike-notify-20261111-notify-cli-check-sse-reception-and-the-d]

# --- 27B-decomposed from roadmap [2026-11-11]: `notify_cli.main` smoke-check dispatch and missing publish arguments are untested - `backe (review + tweak) [feat:shrike-notify-20261111-notify-cli-main-smoke-check-dispatch-and] ---
- [ ] [T1] backend/tests/test_notify_cli_main_smoke_check_and_missing_args.py — Add `async def test_smoke_check_subcommand_runs_script_with_token_and_propagates_exit_code` that monkeypatches `notify_cli.subprocess.run`, sets `sys.argv` for smoke-check with token, asserts `SystemExit` code 3 and correct command args including `--token`. VERIFY: `cd backend && python3 -m pytest tests/test_notify_cli_main_smoke_check_and_missing_args.py::test_smoke_check_subcommand_runs_script_with_token_and_propagates_exit_code -q`. (cat:test; multifile:no) [feat:shrike-notify-20261111-notify-cli-main-smoke-check-dispatch-and]
- [ ] [T1] backend/tests/test_notify_cli_main_smoke_check_and_missing_args.py — Add `async def test_smoke_check_subcommand_without_token_omits_flag` that monkeypatches `notify_cli.subprocess.run`, sets `sys.argv` for smoke-check without token, asserts `SystemExit` code 0 and command args do not contain `--token`. VERIFY: `cd backend && python3 -m pytest tests/test_notify_cli_main_smoke_check_and_missing_args.py::test_smoke_check_subcommand_without_token_omits_flag -q`. (cat:test; multifile:no) [feat:shrike-notify-20261111-notify-cli-main-smoke-check-dispatch-and]
- [ ] [T1] backend/tests/test_notify_cli_main_smoke_check_and_missing_args.py — Add `async def test_publish_without_url_or_payload_exits_one_with_message` that tests three argv scenarios (empty, missing payload, missing url) and asserts `SystemExit` code 1 with specific error message in stderr. VERIFY: `cd backend && python3 -m pytest tests/test_notify_cli_main_smoke_check_and_missing_args.py::test_publish_without_url_or_payload_exits_one_with_message -q`. (cat:test; multifile:no) [feat:shrike-notify-20261111-notify-cli-main-smoke-check-dispatch-and]

# --- 27B-decomposed from roadmap [2026-11-11]: `notify_cli.main` bootstrap-token secret handling and publish error exits are untested - ` (review + tweak) [feat:shrike-notify-20261111-notify-cli-main-bootstrap-token-secret-h] ---
- [ ] [T1] backend/tests/test_notify_cli_bootstrap_token_secret_and_publish_errors.py — Add `async def test_bootstrap_token_requires_a_secret_and_reports_value_errors` that deletes `NOTIFY_SIGNING_SECRET`, runs `notify_cli.main` with `["notify_cli.py", "bootstrap-token"]` expecting exit 1 and stderr containing `Error: --secret or NOTIFY_SIGNING_SECRET must be set`, then monkeypatches `notify_cli.bootstrap_admin_token` to raise `ValueError("secret too short")` and runs with `["notify_cli.py", "bootstrap-token", "--secret", "x"]` expecting exit 1 and stderr containing `Error: secret too short`. VERIFY: `cd backend && python3 -m pytest tests/test_notify_cli_bootstrap_token_secret_and_publish_errors.py::test_bootstrap_token_requires_a_secret_and_reports_value_errors -q`. (cat:test; multifile:no) [feat:shrike-notify-20261111-notify-cli-main-bootstrap-token-secret-h]
- [ ] [T1] backend/tests/test_notify_cli_bootstrap_token_secret_and_publish_errors.py — Add `async def test_publish_exits_one_on_http_error_status_and_transport_error` that runs `notify_cli.main` with `["notify_cli.py", "--url", "http://h/t", "--payload", '{"body": "x"}']`, monkeypatching `notify_cli.publish_message` to return `httpx.Response(403, text="forbidden")` expecting exit 1 and stderr containing `Client Error (403): forbidden`, then monkeypatching it to raise `httpx.ConnectError("refused")` expecting exit 1 and stderr containing `HTTP error: refused`. VERIFY: `cd backend && python3 -m pytest tests/test_notify_cli_bootstrap_token_secret_and_publish_errors.py::test_publish_exits_one_on_http_error_status_and_transport_error -q`. (cat:test; multifile:no) [feat:shrike-notify-20261111-notify-cli-main-bootstrap-token-secret-h]

# --- 27B-decomposed from roadmap [2026-11-11]: `pre_commit_check.check_script_executable_and_syntax` has no test - `backend/scripts/pre_c (review + tweak) [feat:shrike-notify-20261111-pre-commit-check-check-script-executable] ---
- [ ] [T1] backend/tests/test_pre_commit_check_script_validation.py — Add `test_check_script_executable_and_syntax_reports_each_violation` that imports `check_script_executable_and_syntax` from `pre_commit_check` (via `sys.path.insert`) and asserts the return value for a missing file is `["Script not found: <path>"]`. VERIFY: `cd backend && python3 -m pytest tests/test_pre_commit_check_script_validation.py::test_check_script_executable_and_syntax_reports_each_violation -q`. (cat:test; multifile:no) [feat:shrike-notify-20261111-pre-commit-check-check-script-executable]
- [ ] [T1] backend/tests/test_pre_commit_check_script_validation.py — Extend `test_check_script_executable_and_syntax_reports_each_violation` to create a file with mode 644 and assert the return value is `["Script is not executable: <path>"]`. VERIFY: `cd backend && python3 -m pytest tests/test_pre_commit_check_script_validation.py::test_check_script_executable_and_syntax_reports_each_violation -q`. (cat:test; multifile:no) [feat:shrike-notify-20261111-pre-commit-check-check-script-executable]
- [ ] [T1] backend/tests/test_pre_commit_check_script_validation.py — Extend `test_check_script_executable_and_syntax_reports_each_violation` to create a file with invalid syntax and mode 755, asserting the return value is a list of length 1 where the first element starts with `Syntax error in <path>:`. VERIFY: `cd backend && python3 -m pytest tests/test_pre_commit_check_script_validation.py::test_check_script_executable_and_syntax_reports_each_violation -q`. (cat:test; multifile:no) [feat:shrike-notify-20261111-pre-commit-check-check-script-executable]
- [ ] [T1] backend/tests/test_pre_commit_check_script_validation.py — Extend `test_check_script_executable_and_syntax_reports_each_violation` to create a valid executable file and assert the return value is `[]`. VERIFY: `cd backend && python3 -m pytest tests/test_pre_commit_check_script_validation.py::test_check_script_executable_and_syntax_reports_each_violation -q`. (cat:test; multifile:no) [feat:shrike-notify-20261111-pre-commit-check-check-script-executable]

# --- 27B-decomposed from roadmap [2026-11-11]: `pre_commit_check.main` filename rules and exit codes have no test - `backend/scripts/pre_ (review + tweak) [feat:shrike-notify-20261111-pre-commit-check-main-filename-rules-and] ---
- [ ] [T1] backend/tests/test_pre_commit_check_main_filename_rules.py — Add fixture `repo` that creates `tmp_path/backend/scripts/token_mint.py` with content `x = 1`, sets permissions to `0o755`, and chdirs to `tmp_path`. VERIFY: `cd backend && python3 -m pytest tests/test_pre_commit_check_main_filename_rules.py::test_fixture_repo_setup -q` (assuming a placeholder test or just checking file existence via collection). (cat:test; multifile:no) [feat:shrike-notify-20261111-pre-commit-check-main-filename-rules-and]
- [ ] [T2] backend/tests/test_pre_commit_check_main_filename_rules.py — Add `test_main_exit_codes_and_messages_for_path_arguments` asserting exit 0 for `README.md` and `backend/app/claude_helper.py`. VERIFY: `cd backend && python3 -m pytest tests/test_pre_commit_check_main_filename_rules.py::test_main_exit_codes_and_messages_for_path_arguments -q`. (cat:test; multifile:no) [feat:shrike-notify-20261111-pre-commit-check-main-filename-rules-and]
- [ ] [T2] backend/tests/test_pre_commit_check_main_filename_rules.py — Extend `test_main_exit_codes_and_messages_for_path_arguments` to create `backend/app/utils/ttl.py`, then assert exit 1 and stderr contains `File should not exist: backend/app/utils/ttl.py` when no path arguments are provided. VERIFY: `cd backend && python3 -m pytest tests/test_pre_commit_check_main_filename_rules.py::test_main_exit_codes_and_messages_for_path_arguments -q`. (cat:test; multifile:no) [feat:shrike-notify-20261111-pre-commit-check-main-filename-rules-and]
- [ ] [T1] backend/tests/test_pre_commit_check_main_filename_rules.py — Add helper `_run(monkeypatch, capsys, *paths)` that sets `sys.argv`, calls `pre_commit_check.main()`, captures `SystemExit` code and `stderr`. VERIFY: `cd backend && python3 -m pytest tests/test_pre_commit_check_main_filename_rules.py::test_helper_run_structure -q` (structural check via import/collection). (cat:test; multifile:no) [feat:shrike-notify-20261111-pre-commit-check-main-filename-rules-and]
- [ ] [T2] backend/tests/test_pre_commit_check_main_filename_rules.py — Extend `test_main_exit_codes_and_messages_for_path_arguments` to assert exit 1 and stderr contains `File path contains spaces: my file.txt` for input `my file.txt`. VERIFY: `cd backend && python3 -m pytest tests/test_pre_commit_check_main_filename_rules.py::test_main_exit_codes_and_messages_for_path_arguments -q`. (cat:test; multifile:no) [feat:shrike-notify-20261111-pre-commit-check-main-filename-rules-and]
- [ ] [T2] backend/tests/test_pre_commit_check_main_filename_rules.py — Extend `test_main_exit_codes_and_messages_for_path_arguments` to assert exit 1 and stderr contains `File name contains LLM-like keyword 'gpt' in root directory: ./GPT_notes.md` for input `./GPT_notes.md`. VERIFY: `cd backend && python3 -m pytest tests/test_pre_commit_check_main_filename_rules.py::test_main_exit_codes_and_messages_for_path_arguments -q`. (cat:test; multifile:no) [feat:shrike-notify-20261111-pre-commit-check-main-filename-rules-and]

# --- 27B-decomposed from roadmap [2026-11-11]: `token_mint --list-topics` and the invalid-scope guard in `mint_tokens` are untested - `ba (review + tweak) [feat:shrike-notify-20261111-token-mint-list-topics-and-the-invalid-s] ---
- [ ] [T1] backend/tests/test_token_mint_list_topics_and_invalid_scope.py — Add `test_main_list_topics_prints_fleet_topics_and_exits_without_minting` that monkeypatches `sys.argv` to `["token_mint.py", "--list-topics"]`, passes an `io.StringIO` as `file` to `main`, asserts return is `None`, and verifies output lines match `token_mint.FLEET_TOPICS`. VERIFY: `cd backend && python3 -m pytest tests/test_token_mint_list_topics_and_invalid_scope.py::test_main_list_topics_prints_fleet_topics_and_exits_without_minting -q` (cat:test; multifile:no) [feat:shrike-notify-20261111-token-mint-list-topics-and-the-invalid-s]
- [ ] [T1] backend/tests/test_token_mint_list_topics_and_invalid_scope.py — Add `test_mint_tokens_rejects_invalid_scope_before_minting_any_token` that asserts `pytest.raises(ValueError, match="Invalid scope: bad scope!")` when calling `mint_tokens(["good-scope", "bad scope!"])`. VERIFY: `cd backend && python3 -m pytest tests/test_token_mint_list_topics_and_invalid_scope.py::test_mint_tokens_rejects_invalid_scope_before_minting_any_token -q` (cat:test; multifile:no) [feat:shrike-notify-20261111-token-mint-list-topics-and-the-invalid-s]
- [ ] [T1] backend/tests/test_token_mint_list_topics_and_invalid_scope.py — Add assertions in `test_mint_tokens_rejects_invalid_scope_before_minting_any_token` verifying `validate_scope("*") is True`, `validate_scope("a" * 65) is False`, and `validate_scope("") is False`. VERIFY: `cd backend && python3 -m pytest tests/test_token_mint_list_topics_and_invalid_scope.py::test_mint_tokens_rejects_invalid_scope_before_minting_any_token -q` (cat:test; multifile:no) [feat:shrike-notify-20261111-token-mint-list-topics-and-the-invalid-s]

# --- 27B-decomposed from roadmap [2026-11-11]: Add file backend/tests/test_redact_param.py: `_redact_param` has no direct test - `backend (review + tweak) [feat:shrike-notify-20261111-add-file-backend-tests-test-redact-param] ---
- [ ] [T1] backend/tests/test_redact_param.py — Add file with `from app.logging_config import REDACTED, _redact_param` and test function `test_redact_param_token_keys_stream_mode_and_passthrough` asserting: empty string returns unchanged; `token=abc`, `TOKEN=abc`, `t%6Fken=abc`, `x=token%3Dabc` return `token=` + `REDACTED`; with `redact_all_values=True`, non-token `key=value` returns `key=` + `REDACTED` and bare key returns unchanged; with `redact_all_values=False`, non-token param returns unchanged. VERIFY: `cd backend && python3 -m pytest tests/test_redact_param.py -q -k test_redact_param_token_keys_stream_mode_and_passthrough`. (cat:test; multifile:no) [feat:shrike-notify-20261111-add-file-backend-tests-test-redact-param]

# --- 27B-decomposed from roadmap [2026-11-11]: Add backend/.dockerignore so `COPY . .` stops baking local state into the image - `backend (review + tweak) [feat:shrike-notify-20261111-add-backend-dockerignore-so-copy-stops-b] ---
- [ ] [T1] backend/.dockerignore — Add line `.env` to ignore local environment files. VERIFY: `cd backend && grep -q '^\.env$' .dockerignore`. (cat:infra; multifile:no) [feat:shrike-notify-20261111-add-backend-dockerignore-so-copy-stops-b]
- [ ] [T1] backend/.dockerignore — Add line `*.db` to ignore SQLite database files. VERIFY: `cd backend && grep -q '^\*\.db$' .dockerignore`. (cat:infra; multifile:no) [feat:shrike-notify-20261111-add-backend-dockerignore-so-copy-stops-b]
- [ ] [T1] backend/.dockerignore — Add line `__pycache__/` to ignore Python bytecode cache directories. VERIFY: `cd backend && grep -q '^__pycache__/$' .dockerignore`. (cat:infra; multifile:no) [feat:shrike-notify-20261111-add-backend-dockerignore-so-copy-stops-b]
- [ ] [T1] backend/.dockerignore — Add line `*.pyc` to ignore compiled Python files. VERIFY: `cd backend && grep -q '^\*\.pyc$' .dockerignore`. (cat:infra; multifile:no) [feat:shrike-notify-20261111-add-backend-dockerignore-so-copy-stops-b]
- [ ] [T1] backend/.dockerignore — Add line `.pytest_cache/` to ignore pytest cache directories. VERIFY: `cd backend && grep -q '^\.pytest_cache/$' .dockerignore`. (cat:infra; multifile:no) [feat:shrike-notify-20261111-add-backend-dockerignore-so-copy-stops-b]
- [ ] [T1] backend/.dockerignore — Add lines `venv/`, `.venv/`, and `tests/` to ignore virtual environments and test suites. VERIFY: `cd backend && grep -q '^venv/$' .dockerignore && grep -q '^\.venv/$' .dockerignore && grep -q '^tests/$' .dockerignore`. (cat:infra; multifile:no) [feat:shrike-notify-20261111-add-backend-dockerignore-so-copy-stops-b]
- [ ] [T1] backend/.dockerignore — Add lines `.git` and `.aider*` to ignore version control and AI assistant state. VERIFY: `cd backend && grep -q '^\.git$' .dockerignore && grep -q '^\.aider\*$' .dockerignore`. (cat:infra; multifile:no) [feat:shrike-notify-20261111-add-backend-dockerignore-so-copy-stops-b]
- [ ] [T2] backend/tests/test_dockerfile_unchanged.py — Run existing test to ensure Dockerfile remains unmodified. VERIFY: `cd backend && python3 -m pytest tests/test_dockerfile_unchanged.py -q`. (cat:test; multifile:no) [feat:shrike-notify-20261111-add-backend-dockerignore-so-copy-stops-b]

# --- 27B-decomposed from roadmap [2026-11-11]: The WebSocket endpoint's invalid-topic close and auth-required close are untested - `backe (review + tweak) [feat:shrike-notify-20261111-the-websocket-endpoint-s-invalid-topic-c] ---
- [ ] [T1] backend/tests/test_ws_close_codes_invalid_topic_and_auth.py — Add `test_ws_invalid_topic_closes_with_422` which uses `TestClient.websocket_connect('/bad topic!/ws')`, expects `WebSocketDisconnect` with code 422, and verifies the close reason contains validation details. VERIFY: `cd backend && python3 -m pytest tests/test_ws_close_codes_invalid_topic_and_auth.py::test_ws_invalid_topic_closes_with_422 -q`. (cat:test; multifile:no) [feat:shrike-notify-20261111-the-websocket-endpoint-s-invalid-topic-c]
- [ ] [T1] backend/tests/test_ws_close_codes_invalid_topic_and_auth.py — Add `test_ws_requires_token_when_auth_is_on` which overrides `get_settings` with `require_auth=True`, connects to `/wsauth/ws` without a token expecting `WebSocketDisconnect` code 401, then connects with `?token=garbage` expecting the same, and restores dependencies in `finally`. VERIFY: `cd backend && python3 -m pytest tests/test_ws_close_codes_invalid_topic_and_auth.py::test_ws_requires_token_when_auth_is_on -q`. (cat:test; multifile:no) [feat:shrike-notify-20261111-the-websocket-endpoint-s-invalid-topic-c]
- [ ] [T2] backend/tests/test_ws_close_codes_invalid_topic_and_auth.py — Ensure imports for `pytest`, `TestClient`, `WebSocketDisconnect`, `Settings`, `get_settings`, and `app` are present at the top of the file. VERIFY: `cd backend && python3 -m pytest tests/test_ws_close_codes_invalid_topic_and_auth.py --collect-only -q`. (cat:test; multifile:no) [feat:shrike-notify-20261111-the-websocket-endpoint-s-invalid-topic-c]

# --- 27B-decomposed from roadmap [2026-11-11]: `format_sse` frame layout with and without `id` and `event` is not pinned directly - `back (review + tweak) [feat:shrike-notify-20261111-format-sse-frame-layout-with-and-without] ---
- [ ] [T1] backend/tests/test_format_sse_frames.py — Add `test_format_sse_orders_id_event_data_and_omits_missing_fields` asserting the four exact string outputs for `format_sse` with/without `id` and `event`. VERIFY: `cd backend && python3 -m pytest tests/test_format_sse_frames.py -q -k test_format_sse_orders_id_event_data_and_omits_missing_fields`. (cat:test; multifile:no) [feat:shrike-notify-20261111-format-sse-frame-layout-with-and-without]

# --- 27B-decomposed from roadmap [2026-11-11]: `Broker.unsubscribe` for a topic that was never subscribed is untested - `backend/app/serv (review + tweak) [feat:shrike-notify-20261111-broker-unsubscribe-for-a-topic-that-was-] ---
- [ ] [T1] backend/tests/test_broker_unsubscribe_unknown_and_last.py — Create file with `import asyncio`, `from app.services.broker import Broker`, and sync test `test_unsubscribe_unknown_topic_is_a_noop_and_last_queue_removes_topic` that asserts `Broker().unsubscribe('never', asyncio.Queue())` leaves `'never' not in b._subscribers` and unsubscribing the last queue of a subscribed topic removes the topic key. VERIFY: `cd backend && python3 -m pytest tests/test_broker_unsubscribe_unknown_and_last.py -q -k test_unsubscribe_unknown_topic_is_a_noop_and_last_queue_removes_topic`. (cat:test; multifile:no) [feat:shrike-notify-20261111-broker-unsubscribe-for-a-topic-that-was-]

# --- 27B-decomposed from roadmap [2026-11-11]: Add a bounded in-memory delivery log module - create `backend/app/services/delivery_log.py (review + tweak) [feat:shrike-notify-20261111-add-a-bounded-in-memory-delivery-log-mod] ---
- [ ] [T1] backend/app/services/delivery_log.py — Add `DeliveryLog` class with `__init__(max_entries=1000)` using `OrderedDict`, `record(topic, message_id, delivered, dropped, now=None)` storing dict and evicting oldest if `len > max_entries`, and `get(topic, message_id)` returning dict or None. VERIFY: `cd backend && python3 -c "from app.services.delivery_log import DeliveryLog; dl = DeliveryLog(2); dl.record('t', 'm1', 1, 0); dl.record('t', 'm2', 1, 0); dl.record('t', 'm3', 1, 0); assert dl.get('t', 'm1') is None and dl.get('t', 'm3') is not None"`. (cat:python; multifile:no) [feat:shrike-notify-20261111-add-a-bounded-in-memory-delivery-log-mod]
- [ ] [T1] backend/app/services/delivery_log.py — Add module-level instance `delivery_log = DeliveryLog()`. VERIFY: `cd backend && python3 -c "from app.services.delivery_log import delivery_log; assert isinstance(delivery_log, DeliveryLog)"`. (cat:python; multifile:no) [feat:shrike-notify-20261111-add-a-bounded-in-memory-delivery-log-mod]
- [ ] [T2] backend/tests/test_delivery_log.py — Add `test_delivery_log_records_and_evicts_oldest` creating `DeliveryLog(max_entries=2)`, recording three distinct message IDs for the same topic, asserting the first is `None` and the last two are present. VERIFY: `cd backend && python3 -m pytest tests/test_delivery_log.py::test_delivery_log_records_and_evicts_oldest -q`. (cat:test; multifile:no) [feat:shrike-notify-20261111-add-a-bounded-in-memory-delivery-log-mod]
- [ ] [T2] backend/tests/test_delivery_log.py — Add `test_delivery_log_get_unknown_returns_none` asserting `get` returns `None` for a non-existent `(topic, message_id)` pair. VERIFY: `cd backend && python3 -m pytest tests/test_delivery_log.py::test_delivery_log_get_unknown_returns_none -q`. (cat:test; multifile:no) [feat:shrike-notify-20261111-add-a-bounded-in-memory-delivery-log-mod]

# --- 27B-decomposed from roadmap [2026-11-11]: Record a delivery receipt for every accepted publish - in `backend/app/routers/publish.py` (review + tweak) [feat:shrike-notify-20261111-record-a-delivery-receipt-for-every-acce] ---
- [ ] [T2] backend/app/services/delivery_log.py — Add `get(topic, msg_id)` function that returns the receipt dict from `_entries` or None. VERIFY: `cd backend && python3 -c "from app.services.delivery_log import record, get; record('t','i',True,0,now=1); assert get('t','i')['delivered']==True; print('ok')"` (cat:python; multifile:no) [feat:shrike-notify-20261111-record-a-delivery-receipt-for-every-acce]
- [ ] [T1] backend/app/services/delivery_log.py — Add module-level `_entries` dict and `record(topic, msg_id, delivered, dropped, now)` function that appends a receipt dict to `_entries[topic][msg_id]`. VERIFY: `cd backend && python3 -c "from app.services.delivery_log import record; record('t','i',True,0,now=1); print('ok')"` (cat:python; multifile:no) [feat:shrike-notify-20261111-record-a-delivery-receipt-for-every-acce]
- [ ] [T3] backend/app/routers/publish.py — Import `delivery_log` from `app.services.delivery_log` and call `delivery_log.record(topic, message.id, delivered, _dropped, now=message.created_at)` immediately after `delivered, _dropped = await broker.publish(message)`. VERIFY: `cd backend && python3 -m pytest tests/test_publish_records_delivery.py -q -k test_publish_records_delivery_receipt` (cat:python; multifile:no) [feat:shrike-notify-20261111-record-a-delivery-receipt-for-every-acce]
- [ ] [T4] backend/tests/test_publish_records_delivery.py — Create test file with fixture clearing `delivery_log._entries` and test `test_publish_records_delivery_receipt` that POSTs to unique topic, resets limiter, and asserts receipt matches response. VERIFY: `cd backend && python3 -m pytest tests/test_publish_records_delivery.py -q -k test_publish_records_delivery_receipt` (cat:test; multifile:no) [feat:shrike-notify-20261111-record-a-delivery-receipt-for-every-acce]

# --- 27B-decomposed from roadmap [2026-11-11]: Add `GET /{topic}/messages/{message_id}` returning one retained message - in `backend/app/ (review + tweak) [feat:shrike-notify-20261111-add-get-topic-messages-message-id-return] ---
- [ ] [T1] backend/app/routers/messages.py — Add `get_message_by_id` route handler with `response_model=MessageOut` and `require_topic_and_auth` dependency that searches `broker.history(topic, limit=None)` for the message ID and returns 404 if not found. VERIFY: `cd backend && python3 -c "from app.routers.messages import get_message_by_id; print('ok')"` (cat:endpoint; multifile:no) [feat:shrike-notify-20261111-add-get-topic-messages-message-id-return]
- [ ] [T2] backend/tests/test_message_by_id_endpoint.py — Create test file with `test_get_message_by_id_returns_retained_message` that publishes to a unique topic, fetches by ID, and asserts `body` and `id` match. VERIFY: `cd backend && python3 -m pytest tests/test_message_by_id_endpoint.py::test_get_message_by_id_returns_retained_message -q` (cat:test; multifile:no) [feat:shrike-notify-20261111-add-get-topic-messages-message-id-return]
- [ ] [T3] backend/tests/test_message_by_id_endpoint.py — Add `test_get_message_by_id_unknown_is_404` that requests a non-existent message ID and asserts status code 404 and detail "message not found". VERIFY: `cd backend && python3 -m pytest tests/test_message_by_id_endpoint.py::test_get_message_by_id_unknown_is_404 -q` (cat:test; multifile:no) [feat:shrike-notify-20261111-add-get-topic-messages-message-id-return]
- [ ] [T4] backend/app/routers/messages.py — Ensure the new route is registered in the router and uses the correct path parameter `{message_id}`. VERIFY: `cd backend && python3 -c "from app.main import app; routes = [r.path for r in app.routes]; assert any('/messages/{message_id}' in r for r in routes); print('ok')"` (cat:endpoint; multifile:no) [feat:shrike-notify-20261111-add-get-topic-messages-message-id-return]
- [ ] [T5] backend/tests/test_message_by_id_endpoint.py — Verify the test file imports are correct and fixtures are properly used from `conftest.py`. VERIFY: `cd backend && python3 -m pytest tests/test_message_by_id_endpoint.py --collect-only -q` (cat:test; multifile:no) [feat:shrike-notify-20261111-add-get-topic-messages-message-id-return]

# --- 27B-decomposed from roadmap [2026-11-11]: Add `GET /{topic}/messages/{message_id}/receipt` - in `backend/app/routers/messages.py` de (review + tweak) [feat:shrike-notify-20261111-add-get-topic-messages-message-id-receip] ---
- [ ] [T1] backend/app/routers/messages.py — Add `DeliveryReceipt` Pydantic model with fields `id: str`, `topic: str`, `delivered: int`, `dropped: int`, `published_at: float`. VERIFY: `cd backend && python3 -c "from app.routers.messages import DeliveryReceipt; assert hasattr(DeliveryReceipt, 'model_fields') and set(DeliveryReceipt.model_fields.keys()) == {'id', 'topic', 'delivered', 'dropped', 'published_at'}"`. (cat:schema; multifile:no) [feat:shrike-notify-20261111-add-get-topic-messages-message-id-receip]
- [ ] [T3] backend/app/routers/messages.py — Add `GET /{topic}/messages/{message_id}/receipt` route with `response_model=DeliveryReceipt` behind `require_topic_and_auth`, returning 404 if `delivery_log` lacks the entry. VERIFY: `cd backend && python3 -m pytest tests/test_message_receipt_endpoint.py::test_receipt_endpoint_unknown_id_is_404 -q`. (cat:endpoint; multifile:no) [feat:shrike-notify-20261111-add-get-topic-messages-message-id-receip]
- [ ] [T2] backend/tests/test_message_receipt_endpoint.py — Create test file with `test_receipt_endpoint_unknown_id_is_404` that asserts 404 status and detail "receipt not found" for a non-existent message ID. VERIFY: `cd backend && python3 -m pytest tests/test_message_receipt_endpoint.py::test_receipt_endpoint_unknown_id_is_404 -q`. (cat:test; multifile:no) [feat:shrike-notify-20261111-add-get-topic-messages-message-id-receip]
- [ ] [T4] backend/tests/test_message_receipt_endpoint.py — Add `test_receipt_endpoint_reports_delivered_count` that publishes a message with no subscribers and asserts receipt has `delivered == 0` and `dropped == 0`. VERIFY: `cd backend && python3 -m pytest tests/test_message_receipt_endpoint.py::test_receipt_endpoint_reports_delivered_count -q`. (cat:test; multifile:no) [feat:shrike-notify-20261111-add-get-topic-messages-message-id-receip]

# --- 27B-decomposed from roadmap [2026-11-11]: Return the new message id in an `X-Message-ID` response header - in `backend/app/routers/p (review + tweak) [feat:shrike-notify-20261111-return-the-new-message-id-in-an-x-messag] ---
- [ ] [T1] backend/app/routers/publish.py — Add `response.headers["X-Message-ID"] = message.id` immediately after the message object is constructed and before returning the response. VERIFY: `cd backend && python3 -m pytest tests/test_publish_message_id_header.py -q -k test_publish_sets_x_message_id_header_matching_body`. (cat:python; multifile:no) [feat:shrike-notify-20261111-return-the-new-message-id-in-an-x-messag]
- [ ] [T2] backend/tests/test_publish_message_id_header.py — Create file with `test_publish_sets_x_message_id_header_matching_body` that asserts `resp.headers["X-Message-ID"] == resp.json()["id"]`. VERIFY: `cd backend && python3 -m pytest tests/test_publish_message_id_header.py -q -k test_publish_sets_x_message_id_header_matching_body`. (cat:test; multifile:no) [feat:shrike-notify-20261111-return-the-new-message-id-in-an-x-messag]

# --- 27B-decomposed from roadmap [2026-11-11]: Expose `X-Message-ID` to browser clients - in `backend/app/main.py` add `"X-Message-ID"` t (review + tweak) [feat:shrike-notify-20261111-expose-x-message-id-to-browser-clients-i] ---
- [ ] [T3] backend/app/main.py — Add `"X-Message-ID"` to the `expose_headers` list in the `CORSMiddleware` instantiation. VERIFY: `cd backend && grep -q '"X-Message-ID"' app/main.py`. (cat:python; multifile:no) [feat:shrike-notify-20261111-expose-x-message-id-to-browser-clients-i]
- [ ] [T2] backend/tests/test_cors_expose_headers.py — Add `test_cors_exposes_x_message_id` function that performs a cross-origin publish request and asserts `"x-message-id"` is in the `access-control-expose-headers` response header (case-insensitive). VERIFY: `cd backend && python3 -m pytest tests/test_cors_expose_headers.py::test_cors_exposes_x_message_id -q`. (cat:test; multifile:no) [feat:shrike-notify-20261111-expose-x-message-id-to-browser-clients-i]

# --- 27B-decomposed from roadmap [2026-11-11]: Document the lookup and receipt endpoints in the README - in `README.md` add two rows to t (review + tweak) [feat:shrike-notify-20261111-document-the-lookup-and-receipt-endpoint] ---
- [ ] [T1] README.md — Add a row to the API table for `GET /{topic}/messages/{message_id}` describing it as retrieving one retained message. VERIFY: `grep -q 'GET /{topic}/messages/{message_id}' README.md`. (cat:docs; multifile:no) [feat:shrike-notify-20261111-document-the-lookup-and-receipt-endpoint]
- [ ] [T1] README.md — Add a row to the API table for `GET /{topic}/messages/{message_id}/receipt` describing it as returning delivered/dropped counts, kept in memory per process, bounded to 1000 entries, not shared across workers, and lost on restart. VERIFY: `grep -q 'GET /{topic}/messages/{message_id}/receipt' README.md`. (cat:docs; multifile:no) [feat:shrike-notify-20261111-document-the-lookup-and-receipt-endpoint]
- [ ] [T1] README.md — Update the Observability paragraph to explicitly mention the `X-Message-ID` header. VERIFY: `grep -q 'X-Message-ID' README.md`. (cat:docs; multifile:no) [feat:shrike-notify-20261111-document-the-lookup-and-receipt-endpoint]

# --- 27B-decomposed from roadmap [2026-11-11]: Add a safe placeholder renderer - create `backend/app/utils/templating.py` with `render_te (review + tweak) [feat:shrike-notify-20261111-add-a-safe-placeholder-renderer-create-b] ---
- [ ] [T1] backend/app/utils/templating.py — Add module docstring and import `re` to prepare for regex-based template rendering. VERIFY: `cd backend && python3 -c "import app.utils.templating"`. (cat:python; multifile:no) [feat:shrike-notify-20261111-add-a-safe-placeholder-renderer-create-b]
- [ ] [T2] backend/app/utils/templating.py — Implement `render_template(text, variables, max_length)` using `re.sub` with pattern `\{\{\s*([A-Za-z0-9_.\-]{1,64})\s*\}\}` to replace known keys and truncate output. VERIFY: `cd backend && python3 -c "from app.utils.templating import render_template; assert render_template('{{ a }}', {'a': 'b'}) == 'b'"`. (cat:python; multifile:no) [feat:shrike-notify-20261111-add-a-safe-placeholder-renderer-create-b]
- [ ] [T3] backend/tests/test_templating.py — Create test file with `test_render_template_substitutes_known_and_keeps_unknown` asserting exact substitution behavior for known and unknown placeholders. VERIFY: `cd backend && python3 -m pytest tests/test_templating.py::test_render_template_substitutes_known_and_keeps_unknown -q`. (cat:test; multifile:no) [feat:shrike-notify-20261111-add-a-safe-placeholder-renderer-create-b]
- [ ] [T4] backend/tests/test_templating.py — Add `test_render_template_truncates_and_ignores_expressions` asserting that `{{ x.__class__ }}` remains unchanged and long outputs are truncated to `max_length`. VERIFY: `cd backend && python3 -m pytest tests/test_templating.py::test_render_template_truncates_and_ignores_expressions -q`. (cat:test; multifile:no) [feat:shrike-notify-20261111-add-a-safe-placeholder-renderer-create-b]
- [ ] [T5] backend/tests/test_templating.py — Add edge case tests for `variables=None`, empty dict, and invalid placeholder names to ensure robustness. VERIFY: `cd backend && python3 -m pytest tests/test_templating.py -q`. (cat:test; multifile:no) [feat:shrike-notify-20261111-add-a-safe-placeholder-renderer-create-b]

# --- 27B-decomposed from roadmap [2026-11-11]: Support a default value in a placeholder - in `backend/app/utils/templating.py` let `{{ na (review + tweak) [feat:shrike-notify-20261111-support-a-default-value-in-a-placeholder] ---
- [ ] [T1] backend/app/utils/templating.py — Add `render_template(template: str, variables: dict[str, str]) -> str` function that splits on `{{`, parses `name|fallback` syntax, strips fallback, and returns stripped fallback if key missing or variable value if present. VERIFY: `cd backend && python3 -c "from app.utils.templating import render_template; assert render_template('{{ name|fallback }}', {}) == 'fallback'; assert render_template('{{ name|fallback }}', {'name': 'val'}) == 'val'; assert render_template('{{ name| }}', {}) == ''; print('OK')"`. (cat:python; multifile:no) [feat:shrike-notify-20261111-support-a-default-value-in-a-placeholder]
- [ ] [T2] backend/tests/test_templating.py — Add `test_render_template_default_value_used_only_when_missing` function that asserts `render_template` returns variable value for present key, stripped fallback for missing key with default, and empty string for missing key with empty default. VERIFY: `cd backend && python3 -m pytest tests/test_templating.py -q -k test_render_template_default_value_used_only_when_missing`. (cat:test; multifile:no) [feat:shrike-notify-20261111-support-a-default-value-in-a-placeholder]

# --- 27B-decomposed from roadmap [2026-11-11]: Accept an optional `vars` object on the publish body - in `backend/app/schemas.py` add `va (review + tweak) [feat:shrike-notify-20261111-accept-an-optional-vars-object-on-the-pu] ---
- [ ] [T1] backend/app/schemas.py — Add `vars: dict[str, str | int | float | bool] | None = Field(None, description="Values for {{ name }} placeholders in title and body")` to the `PublishRequest` class. VERIFY: `cd backend && python3 -c "from app.schemas import PublishRequest; assert hasattr(PublishRequest, 'vars')"`. (cat:schema; multifile:no) [feat:shrike-notify-20261111-accept-an-optional-vars-object-on-the-pu]
- [ ] [T2] backend/tests/test_schemas_vars.py — Create file with test `test_publish_request_accepts_vars_and_defaults_to_none` asserting default is None and provided dict is preserved. VERIFY: `cd backend && python3 -m pytest tests/test_schemas_vars.py -q -k test_publish_request_accepts_vars_and_defaults_to_none`. (cat:test; multifile:no) [feat:shrike-notify-20261111-accept-an-optional-vars-object-on-the-pu]

# --- 27B-decomposed from roadmap [2026-11-11]: Render `vars` into the title and body when publishing - in `backend/app/routers/publish.py (review + tweak) [feat:shrike-notify-20261111-render-vars-into-the-title-and-body-when] ---
- [ ] [T1] backend/app/utils/templating.py — Add `render_template(text: str, vars: dict, max_length: int) -> str` that substitutes `{{ key }}` placeholders with values from `vars`, truncates result to `max_length`, and returns original text if `vars` is empty or no matches found. VERIFY: `cd backend && python3 -c "from app.utils.templating import render_template; assert render_template('Hi {{ name }}', {'name': 'Bob'}, 100) == 'Hi Bob'; assert render_template('No vars', {}, 100) == 'No vars'"`. (cat:python; multifile:no) [feat:shrike-notify-20261111-render-vars-into-the-title-and-body-when]
- [ ] [T3] backend/app/routers/publish.py — Import `render_template` from `app.utils.templating` and `get_settings` from `app.config`; in the publish endpoint, if `req.vars` is non-empty, call `render_template(req.body, req.vars, get_settings().max_message_length)` and `render_template(req.title, req.vars, 256)`, passing results to `broker.build_message`; otherwise pass original `req.body` and `req.title`. VERIFY: `cd backend && python3 -c "import ast; tree = ast.parse(open('app/routers/publish.py').read()); assert any(isinstance(n, ast.ImportFrom) and n.module == 'app.utils.templating' for n in ast.walk(tree))"`. (cat:python; multifile:no) [feat:shrike-notify-20261111-render-vars-into-the-title-and-body-when]
- [ ] [T2] backend/tests/test_templating.py — Create test file with `test_render_template_substitutes_vars`, `test_render_template_truncates_to_max_length`, and `test_render_template_empty_vars_returns_original`. VERIFY: `cd backend && python3 -m pytest tests/test_templating.py -q`. (cat:test; multifile:no) [feat:shrike-notify-20261111-render-vars-into-the-title-and-body-when]
- [ ] [T4] backend/tests/test_publish_templates.py — Create test file with `test_publish_renders_vars_into_body_and_title` (POST with vars, GET messages to verify rendered content) and `test_publish_without_vars_leaves_placeholders_untouched` (POST with `{{ var }}` in body but no vars, GET messages to verify original text). VERIFY: `cd backend && python3 -m pytest tests/test_publish_templates.py -q -k 'test_publish_renders_vars_into_body_and_title or test_publish_without_vars_leaves_placeholders_untouched'`. (cat:test; multifile:no) [feat:shrike-notify-20261111-render-vars-into-the-title-and-body-when]
- [ ] [T5] backend/tests/test_publish_type_validation.py — Add `test_publish_with_vars_exceeding_max_length_truncates` to verify that when rendered body exceeds `max_message_length`, it is truncated. VERIFY: `cd backend && python3 -m pytest tests/test_publish_type_validation.py::test_publish_with_vars_exceeding_max_length_truncates -q`. (cat:test; multifile:no) [feat:shrike-notify-20261111-render-vars-into-the-title-and-body-when]
