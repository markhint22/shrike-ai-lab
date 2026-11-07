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
- [ ] [T4] backend/tests/test_logging_and_openapi.py — Verify existing OpenAPI structure tests still pass with the new response codes added to the publish endpoint. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_logging_and_openapi.py`. (cat:test; multifile:no) [feat:shrike-notify-20261106-post-topic-documents-401-422-429-but-not]

# --- 27B-decomposed from roadmap [2026-11-06]: README API section is stale versus the real routes and shows a token format that no longer (review + tweak) [feat:shrike-notify-20261106-readme-api-section-is-stale-versus-the-r] ---
- [ ] [T1] backend/tests/test_readme_api_table.py — Add test that asserts every APIRoute method+path from app.routes (excluding /docs, /redoc, /openapi.json, websockets) appears in README.md text. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_readme_api_table.py::test_all_routes_in_readme` (cat:test; multifile:no) [feat:shrike-notify-20261106-readme-api-section-is-stale-versus-the-r]
- [ ] [T1] backend/tests/test_readme_api_table.py — Add test that asserts the string "<hexsig>" does not appear in README.md text. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_readme_api_table.py::test_no_hexsig_in_readme` (cat:test; multifile:no) [feat:shrike-notify-20261106-readme-api-section-is-stale-versus-the-r]
- [ ] [T2] README.md — Update the "API (v1)" table to include rows for `GET /{topic}/stats`, `GET /topics`, `GET /tokens`, `POST /tokens/revoke`, and `GET /health/detailed`. VERIFY: `grep -q "GET /{topic}/stats" README.md && grep -q "GET /topics" README.md && grep -q "GET /tokens" README.md && grep -q "POST /tokens/revoke" README.md && grep -q "GET /health/detailed" README.md` (cat:docs; multifile:no) [feat:shrike-notify-20261106-readme-api-section-is-stale-versus-the-r]
- [ ] [T2] README.md — Update the `/messages` row in the API table to document `after_id`, `min_priority`, and `tag` query parameters. VERIFY: `grep -q "after_id" README.md && grep -q "min_priority" README.md && grep -q "tag" README.md` (cat:docs; multifile:no) [feat:shrike-notify-20261106-readme-api-section-is-stale-versus-the-r]
- [ ] [T2] README.md — Replace the token example in the "Issue a scoped token" section to show `{"token": "<scope>.<issued_at>.<ttl>.<sig>", ...}` and include `issued_at`, `expires_at`, and `ttl_seconds` fields. VERIFY: `grep -q "<scope>.<issued_at>.<ttl>.<sig>" README.md && grep -q "issued_at" README.md && grep -q "expires_at" README.md && grep -q "ttl_seconds" README.md` (cat:docs; multifile:no) [feat:shrike-notify-20261106-readme-api-section-is-stale-versus-the-r]
- [ ] [T2] README.md — Add documentation for WebSocket `?token=` authentication in the API section. VERIFY: `grep -q "?token=" README.md` (cat:docs; multifile:no) [feat:shrike-notify-20261106-readme-api-section-is-stale-versus-the-r]
- [ ] [T3] backend/tests/test_readme_api_table.py — Ensure the test file imports `app` from `backend.app.main` and correctly iterates `app.routes` to collect APIRoute instances. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_readme_api_table.py` (cat:test; multifile:no) [feat:shrike-notify-20261106-readme-api-section-is-stale-versus-the-r]

# --- 27B-decomposed from roadmap [2026-11-06]: `app/middleware.py::max_body_bytes()` re-implements `Settings.max_body_bytes` (the same `m (review + tweak) [feat:shrike-notify-20261106-app-middleware-py-max-body-bytes-re-impl] ---
- [ ] [T1] backend/tests/test_middleware_max_body.py — Add test `test_max_body_bytes_uses_settings_property` that monkeypatches `Settings.max_body_bytes` to return 123 and asserts `app.middleware.max_body_bytes() == 123`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_middleware_max_body.py::test_max_body_bytes_uses_settings_property`. (cat:test; multifile:no) [feat:shrike-notify-20261106-app-middleware-py-max-body-bytes-re-impl]
- [ ] [T3] backend/app/middleware.py — Modify `max_body_bytes()` to return `get_settings().max_body_bytes` instead of recomputing the formula. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_middleware_max_body.py`. (cat:python; multifile:no) [feat:shrike-notify-20261106-app-middleware-py-max-body-bytes-re-impl]
- [ ] [T2] backend/tests/test_config.py — Add test `test_max_body_bytes_property_formula` that verifies `Settings().max_body_bytes` equals `max_message_length * 8 + 65536` with default values. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_config.py::test_max_body_bytes_property_formula`. (cat:test; multifile:no) [feat:shrike-notify-20261106-app-middleware-py-max-body-bytes-re-impl]
- [ ] [T1] backend/tests/test_middleware_max_body.py — Add test `test_max_body_bytes_default_value` that asserts `app.middleware.max_body_bytes()` equals the expected default calculation without monkeypatching. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_middleware_max_body.py::test_max_body_bytes_default_value`. (cat:test; multifile:no) [feat:shrike-notify-20261106-app-middleware-py-max-body-bytes-re-impl]
- [ ] [T2] backend/tests/test_config_env_float.py — Add test `test_max_body_bytes_respects_env_override` that sets env var for max_message_length and verifies `Settings().max_body_bytes` reflects the change. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_config_env_float.py::test_max_body_bytes_respects_env_override`. (cat:test; multifile:no) [feat:shrike-notify-20261106-app-middleware-py-max-body-bytes-re-impl]
- [ ] [T1] backend/tests/test_middleware_max_body.py — Add test `test_max_body_bytes_dynamic_update` that changes `Settings.max_message_length` at runtime and verifies `app.middleware.max_body_bytes()` updates accordingly. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_middleware_max_body.py::test_max_body_bytes_dynamic_update`. (cat:test; multifile:no) [feat:shrike-notify-20261106-app-middleware-py-max-body-bytes-re-impl]

# --- 27B-decomposed from roadmap [2026-11-06]: `Broker.topics()` (and so `GET /topics`) keeps listing topics whose retained messages have (review + tweak) [feat:shrike-notify-20261106-broker-topics-and-so-get-topics-keeps-li] ---
- [ ] [T2] backend/app/services/broker.py — Modify `Broker.topics` to accept `now: float | None = None`, filter `_history` keys using `ttl.is_expired` against `now` or `time.time()`, retain keys with live subscribers, and pop expired non-subscribed keys from `self._history`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_broker.py`. (cat:python; multifile:no) [feat:shrike-notify-20261106-broker-topics-and-so-get-topics-keeps-li]
- [ ] [T1] backend/tests/test_broker_topics_expired.py — Create test file with `test_topics_excludes_expired_no_subscriber` verifying that a topic with only expired messages is absent from `topics()` and `_history`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_broker_topics_expired.py::test_topics_excludes_expired_no_subscriber`. (cat:test; multifile:no) [feat:shrike-notify-20261106-broker-topics-and-so-get-topics-keeps-li]
- [ ] [T1] backend/tests/test_broker_topics_expired.py — Add `test_topics_includes_expired_with_subscriber` verifying that a topic with expired messages but a live subscriber remains in `topics()`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_broker_topics_expired.py::test_topics_includes_expired_with_subscriber`. (cat:test; multifile:no) [feat:shrike-notify-20261106-broker-topics-and-so-get-topics-keeps-li]
- [ ] [T1] backend/tests/test_broker_topics_expired.py — Add `test_topics_includes_fresh_message` verifying that a topic with a non-expired message remains in `topics()`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_broker_topics_expired.py::test_topics_includes_fresh_message`. (cat:test; multifile:no) [feat:shrike-notify-20261106-broker-topics-and-so-get-topics-keeps-li]
- [ ] [T1] backend/tests/test_broker_topics_expired.py — Add `test_topics_ttl_zero_never_drops` verifying that with `ttl_seconds=0`, topics are never dropped from `topics()` even if messages appear expired. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_broker_topics_expired.py::test_topics_ttl_zero_never_drops`. (cat:test; multifile:no) [feat:shrike-notify-20261106-broker-topics-and-so-get-topics-keeps-li]
- [ ] [T3] backend/tests/test_broker_topics_expired.py — Add `test_topics_pops_dead_history_keys` verifying that `_history` dict does not contain keys for topics with only expired messages and no subscribers after calling `topics()`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_broker_topics_expired.py::test_topics_pops_dead_history_keys`. (cat:test; multifile:no) [feat:shrike-notify-20261106-broker-topics-and-so-get-topics-keeps-li]
- [ ] [T4] backend/tests/test_broker_topics_expired.py — Add `test_topics_now_parameter_respected` verifying that passing explicit `now` to `topics()` correctly determines expiration status independent of system time. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_broker_topics_expired.py::test_topics_now_parameter_respected`. (cat:test; multifile:no) [feat:shrike-notify-20261106-broker-topics-and-so-get-topics-keeps-li]
- [ ] [T5] backend/tests/test_broker_topics_expired.py — Add `test_topics_mixed_expired_and_fresh` verifying that a topic with both expired and fresh messages remains in `topics()` and retains only non-expired entries in `_history`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_broker_topics_expired.py::test_topics_mixed_expired_and_fresh`. (cat:test; multifile:no) [feat:shrike-notify-20261106-broker-topics-and-so-get-topics-keeps-li]

# --- 27B-decomposed from roadmap [2026-11-06]: `_env_float` accepts `nan` and `inf`, so one bad env value silently breaks severity gating (review + tweak) [feat:shrike-notify-20261106-env-float-accepts-nan-and-inf-so-one-bad] ---
- [ ] [T1] backend/app/config.py — Add `import math` at the top of the file to support finiteness checks. VERIFY: `cd backend && .venv/bin/python -c "from app.config import math; print('ok')"`. (cat:python; multifile:no) [feat:shrike-notify-20261106-env-float-accepts-nan-and-inf-so-one-bad]
- [ ] [T2] backend/app/config.py — In `_env_float`, after `value = float(raw)`, add `if not math.isfinite(value):` which logs a warning and returns `default`. VERIFY: `cd backend && .venv/bin/python -c "from app.config import _env_float; assert _env_float('nan', 1.0) == 1.0; assert _env_float('inf', 2.0) == 2.0"`. (cat:python; multifile:no) [feat:shrike-notify-20261106-env-float-accepts-nan-and-inf-so-one-bad]
- [ ] [T3] backend/tests/test_config_env_float_nonfinite.py — Create new test file with parametrized tests for `nan`, `NaN`, `inf`, `-inf`, `Infinity` asserting `_env_float` returns default and logs warning. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_config_env_float_nonfinite.py`. (cat:test; multifile:no) [feat:shrike-notify-20261106-env-float-accepts-nan-and-inf-so-one-bad]
- [ ] [T4] backend/tests/test_config_env_float_nonfinite.py — Add test case asserting `_env_float('2.5', 7.5)` returns `2.5` to ensure valid floats are not affected. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_config_env_float_nonfinite.py::test_valid_float`. (cat:test; multifile:no) [feat:shrike-notify-20261106-env-float-accepts-nan-and-inf-so-one-bad]
- [ ] [T5] backend/tests/test_config_env_float_nonfinite.py — Add test asserting `Settings().severity_gate_threshold == 0.0` when `NOTIFY_SEVERITY_GATE_THRESHOLD=nan` is set in env. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_config_env_float_nonfinite.py::test_settings_severity_nan`. (cat:test; multifile:no) [feat:shrike-notify-20261106-env-float-accepts-nan-and-inf-so-one-bad]

# --- 27B-decomposed from roadmap [2026-11-06]: `NOTIFY_REQUIRE_AUTH=true` (or `True`, `yes`, `on`) silently leaves the service OPEN with  (review + tweak) [feat:shrike-notify-20261106-notify-require-auth-true-or-true-yes-on-] ---
- [ ] [T1] backend/app/config.py — Add `_env_flag(name: str, default: bool = False) -> bool` helper that parses truthy/falsy strings and logs a warning for unrecognized values. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_config_env_flag.py::test_env_flag_helper`. (cat:python; multifile:no) [feat:shrike-notify-20261106-notify-require-auth-true-or-true-yes-on-]
- [ ] [T3] backend/app/config.py — Update `Settings.require_auth` to use `_env_flag("NOTIFY_REQUIRE_AUTH", False)` instead of strict string comparison. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_config_env_flag.py::test_require_auth_true`. (cat:python; multifile:no) [feat:shrike-notify-20261106-notify-require-auth-true-or-true-yes-on-]
- [ ] [T3] backend/app/config.py — Update `Settings.persist` to use `_env_flag("NOTIFY_PERSIST", False)` instead of strict string comparison. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_config_env_flag.py::test_persist_true`. (cat:python; multifile:no) [feat:shrike-notify-20261106-notify-require-auth-true-or-true-yes-on-]
- [ ] [T1] backend/tests/test_config_env_flag.py — Create test file with cases for `_env_flag` parsing truthy/falsy/unset/invalid inputs. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_config_env_flag.py::test_env_flag_helper`. (cat:test; multifile:no) [feat:shrike-notify-20261106-notify-require-auth-true-or-true-yes-on-]
- [ ] [T2] backend/tests/test_config_env_flag.py — Add tests verifying `Settings().require_auth` and `Settings().persist` correctly parse `true`, `True`, `YES`, `on`, `1` as True. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_config_env_flag.py::test_require_auth_true tests/test_config_env_flag.py::test_persist_true`. (cat:test; multifile:no) [feat:shrike-notify-20261106-notify-require-auth-true-or-true-yes-on-]
- [ ] [T2] backend/tests/test_config_env_flag.py — Add tests verifying `Settings().require_auth` and `Settings().persist` correctly parse `0`, `false`, `off`, empty string as False. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_config_env_flag.py::test_require_auth_false tests/test_config_env_flag.py::test_persist_false`. (cat:test; multifile:no) [feat:shrike-notify-20261106-notify-require-auth-true-or-true-yes-on-]
- [ ] [T2] backend/tests/test_config_env_flag.py — Add test verifying invalid value `treu` returns default and logs a warning via caplog. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_config_env_flag.py::test_invalid_value_warns`. (cat:test; multifile:no) [feat:shrike-notify-20261106-notify-require-auth-true-or-true-yes-on-]
- [ ] [T2] backend/tests/test_config_env_flag.py — Add test verifying unset environment variables return the default value. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_config_env_flag.py::test_unset_default`. (cat:test; multifile:no) [feat:shrike-notify-20261106-notify-require-auth-true-or-true-yes-on-]

# --- 27B-decomposed from roadmap [2026-11-06]: A JSON body containing `NaN`/`Infinity` or a lone UTF-16 surrogate makes `POST /{topic}` r (review + tweak) [feat:shrike-notify-20261106-a-json-body-containing-nan-infinity-or-a] ---
- [ ] [T1] backend/tests/test_validation_error_unencodable_input.py — Add test `test_nan_priority_returns_422` sending raw bytes `b'{"body":"a","priority":NaN}'` with `content-type: application/json`, asserting status 422 and `detail` list items contain `loc`/`msg`/`type` but no `input`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_validation_error_unencodable_input.py::test_nan_priority_returns_422`. (cat:test; multifile:no) [feat:shrike-notify-20261106-a-json-body-containing-nan-infinity-or-a]
- [ ] [T1] backend/tests/test_validation_error_unencodable_input.py — Add test `test_infinity_body_returns_422` sending raw bytes with `Infinity` in body field, asserting status 422 and no `input` key in detail items. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_validation_error_unencodable_input.py::test_infinity_body_returns_422`. (cat:test; multifile:no) [feat:shrike-notify-20261106-a-json-body-containing-nan-infinity-or-a]
- [ ] [T1] backend/tests/test_validation_error_unencodable_input.py — Add test `test_lone_surrogate_body_returns_422` sending raw bytes with `\ud800` in body, asserting status 422. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_validation_error_unencodable_input.py::test_lone_surrogate_body_returns_422`. (cat:test; multifile:no) [feat:shrike-notify-20261106-a-json-body-containing-nan-infinity-or-a]
- [ ] [T1] backend/tests/test_validation_error_unencodable_input.py — Add test `test_lone_surrogate_title_returns_422` sending raw bytes with `\udfff` in title, asserting status 422. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_validation_error_unencodable_input.py::test_lone_surrogate_title_returns_422`. (cat:test; multifile:no) [feat:shrike-notify-20261106-a-json-body-containing-nan-infinity-or-a]
- [ ] [T1] backend/tests/test_validation_error_unencodable_input.py — Add test `test_plain_invalid_body_still_contains_input` sending `{"body":5}`, asserting status 422 and `detail[0]` contains `input`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_validation_error_unencodable_input.py::test_plain_invalid_body_still_contains_input`. (cat:test; multifile:no) [feat:shrike-notify-20261106-a-json-body-containing-nan-infinity-or-a]
- [ ] [T1] backend/tests/test_validation_error_unencodable_input.py — Add test `test_nul_byte_returns_400` sending raw bytes with NUL character, asserting status 400. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_validation_error_unencodable_input.py::test_nul_byte_returns_400`. (cat:test; multifile:no) [feat:shrike-notify-20261106-a-json-body-containing-nan-infinity-or-a]
- [ ] [T3] backend/app/main.py — Modify `request_validation_handler` to wrap the call to `default_request_validation_handler` in `try/except (ValueError, UnicodeEncodeError)` and return a sanitized 422 JSONResponse excluding `input` and `ctx` keys on exception. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_validation_error_unencodable_input.py`. (cat:python; multifile:no) [feat:shrike-notify-20261106-a-json-body-containing-nan-infinity-or-a]

# --- 27B-decomposed from roadmap [2026-11-06]: A single publish with a lone-surrogate tag poisons the whole topic: `GET /{topic}/messages (review + tweak) [feat:shrike-notify-20261106-a-single-publish-with-a-lone-surrogate-t] ---
- [ ] [T1] backend/app/schemas.py — Add `_reject_surrogates(tag: str) -> None` helper that raises `ValueError` on `UnicodeEncodeError` from `tag.encode('utf-8')`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_schemas_surrogate_tags.py::test_reject_surrogates_helper`. (cat:schema; multifile:no) [feat:shrike-notify-20261106-a-single-publish-with-a-lone-surrogate-t]
- [ ] [T2] backend/app/schemas.py — Modify `PublishRequest.validate_tags` to call `_reject_surrogates` on every tag in the list input shape. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_schemas_surrogate_tags.py::test_list_input_rejects_surrogate`. (cat:schema; multifile:no) [feat:shrike-notify-20261106-a-single-publish-with-a-lone-surrogate-t]
- [ ] [T3] backend/app/schemas.py — Modify `PublishRequest.validate_tags` to call `_reject_surrogates` on every tag in the comma-separated string input shape. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_schemas_surrogate_tags.py::test_comma_string_input_rejects_surrogate`. (cat:schema; multifile:no) [feat:shrike-notify-20261106-a-single-publish-with-a-lone-surrogate-t]
- [ ] [T4] backend/app/schemas.py — Modify `PublishRequest.validate_tags` to call `_reject_surrogates` on every tag in the JSON-array string input shape. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_schemas_surrogate_tags.py::test_json_string_input_rejects_surrogate`. (cat:schema; multifile:no) [feat:shrike-notify-20261106-a-single-publish-with-a-lone-surrogate-t]
- [ ] [T5] backend/tests/test_schemas_surrogate_tags.py — Add test cases verifying that valid astral (`\U0001F600`) and accented (`caf\u00e9`) tags pass validation and round-trip correctly. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_schemas_surrogate_tags.py::test_valid_astral_and_accented_pass`. (cat:test; multifile:no) [feat:shrike-notify-20261106-a-single-publish-with-a-lone-surrogate-t]

# --- 27B-decomposed from roadmap [2026-11-06]: `notify_cli.py watch` dies after 5 seconds of silence with an empty error message, so it c (review + tweak) [feat:shrike-notify-20261106-notify-cli-py-watch-dies-after-5-seconds] ---
- [ ] [T1] backend/scripts/notify_cli.py — Add `make_watch_client` function returning `httpx.AsyncClient(timeout=httpx.Timeout(10.0, read=None))`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_notify_cli_watch_timeout.py::test_make_watch_client_timeout`. (cat:python; multifile:no) [feat:shrike-notify-20261106-notify-cli-py-watch-dies-after-5-seconds]
- [ ] [T2] backend/scripts/notify_cli.py — Update `watch_topic` error handling to format stderr as `f"Error watching topic: {type(e).__name__}: {e}"`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_notify_cli_watch_timeout.py::test_watch_topic_error_message`. (cat:python; multifile:no) [feat:shrike-notify-20261106-notify-cli-py-watch-dies-after-5-seconds]
- [ ] [T3] backend/scripts/notify_cli.py — Replace `httpx.AsyncClient()` instantiation in the `watch` branch of `main` with `make_watch_client()`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_notify_cli_watch_timeout.py::test_main_watch_uses_custom_client`. (cat:python; multifile:no) [feat:shrike-notify-20261106-notify-cli-py-watch-dies-after-5-seconds]
- [ ] [T4] backend/tests/test_notify_cli_watch_timeout.py — Create test file with `test_make_watch_client_timeout` asserting `read is None` and `connect == 10.0`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_notify_cli_watch_timeout.py::test_make_watch_client_timeout`. (cat:test; multifile:no) [feat:shrike-notify-20261106-notify-cli-py-watch-dies-after-5-seconds]
- [ ] [T5] backend/tests/test_notify_cli_watch_timeout.py — Add `test_watch_topic_error_message` monkeypatching `fetch_sse_stream` to raise `httpx.ReadTimeout('')` and asserting stderr contains `ReadTimeout`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_notify_cli_watch_timeout.py::test_watch_topic_error_message`. (cat:test; multifile:no) [feat:shrike-notify-20261106-notify-cli-py-watch-dies-after-5-seconds]

# --- 27B-decomposed from roadmap [2026-11-06]: Tags `null` and nested values are silently turned into the strings `"None"`, `"['x']"` and (review + tweak) [feat:shrike-notify-20261106-tags-null-and-nested-values-are-silently] ---
- [ ] [T1] backend/app/schemas.py — In `PublishRequest.validate_tags`, add a check before stringification in the list branch to raise `ValueError('each tag must be a string or number')` if any element is `None`, `bool`, `list`, or `dict`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_schemas_tags_nonstring.py::test_tags_none_raises tests/test_schemas_tags_nonstring.py::test_tags_bool_raises tests/test_schemas_tags_nonstring.py::test_tags_list_raises tests/test_schemas_tags_nonstring.py::test_tags_dict_raises`. (cat:schema; multifile:no) [feat:shrike-notify-20261106-tags-null-and-nested-values-are-silently]
- [ ] [T1] backend/app/schemas.py — In `PublishRequest.validate_tags`, add the same type check before stringification in the decoded JSON branch to raise `ValueError('each tag must be a string or number')` if any element is `None`, `bool`, `list`, or `dict`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_schemas_tags_nonstring.py::test_tags_json_null_raises`. (cat:schema; multifile:no) [feat:shrike-notify-20261106-tags-null-and-nested-values-are-silently]
- [ ] [T2] backend/tests/test_schemas_tags_nonstring.py — Create new test file with tests asserting `ValidationError` for `tags=['a', None]`, `tags=[True]`, `tags=[['x']]`, `tags=[{'k': 1}]`, and `tags='[null]'`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_schemas_tags_nonstring.py`. (cat:test; multifile:no) [feat:shrike-notify-20261106-tags-null-and-nested-values-are-silently]
- [ ] [T2] backend/tests/test_schemas_tags_nonstring.py — Add test asserting `tags=[1, 2.5, 'three']` still coerces to `['1', '2.5', 'three']` without error. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_schemas_tags_nonstring.py::test_tags_valid_numbers_strings`. (cat:test; multifile:no) [feat:shrike-notify-20261106-tags-null-and-nested-values-are-silently]
- [ ] [T3] backend/tests/test_schemas_tags.py — Verify existing tests for numeric/string coercion still pass with the new validation logic. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_schemas_tags.py`. (cat:test; multifile:no) [feat:shrike-notify-20261106-tags-null-and-nested-values-are-silently]
- [ ] [T3] backend/tests/test_schemas.py — Verify general schema validation tests still pass with the updated tag validation. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_schemas.py`. (cat:test; multifile:no) [feat:shrike-notify-20261106-tags-null-and-nested-values-are-silently]

# --- 27B-decomposed from roadmap [2026-11-06]: `publish_with_retry` sleeps for `nan` seconds when the server sends `Retry-After: nan` - ` (review + tweak) [feat:shrike-notify-20261106-publish-with-retry-sleeps-for-nan-second] ---
- [ ] [T1] backend/app/utils/publish_client.py — Add `import math` at the top of the file. VERIFY: `cd backend && .venv/bin/python -c "import ast; tree=ast.parse(open('app/utils/publish_client.py').read()); imports=[n for n in ast.walk(tree) if isinstance(n, ast.Import)]; assert any(any(a.name=='math' for a in i.names) for i in imports)"`. (cat:python; multifile:no) [feat:shrike-notify-20261106-publish-with-retry-sleeps-for-nan-second]
- [ ] [T2] backend/app/utils/publish_client.py — In `publish_with_retry`, inside the existing `try` block after `ra_val = float(retry_after_header)`, add `if not math.isfinite(ra_val): raise ValueError("Non-finite Retry-After")`. VERIFY: `cd backend && .venv/bin/python -c "import ast; tree=ast.parse(open('app/utils/publish_client.py').read()); found=False; [exec('found=True') for node in ast.walk(tree) if isinstance(node, ast.Raise) and isinstance(node.exc, ast.Call) and getattr(node.exc.func, 'id', '')=='ValueError' and any(isinstance(a, ast.Constant) and a.value=='Non-finite Retry-After' for a in node.exc.args)]; assert found"`. (cat:python; multifile:no) [feat:shrike-notify-20261106-publish-with-retry-sleeps-for-nan-second]
- [ ] [T3] backend/tests/test_publish_client_retry_after_nonfinite.py — Create new test file with `httpx.MockTransport` and monkeypatched `asyncio.sleep` recorder to verify `Retry-After: nan` results in a sleep of `0.5` (fallback backoff) and final status 200. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_publish_client_retry_after_nonfinite.py::test_retry_after_nan_falls_back_to_backoff`. (cat:test; multifile:no) [feat:shrike-notify-20261106-publish-with-retry-sleeps-for-nan-second]
- [ ] [T4] backend/tests/test_publish_client_retry_after_nonfinite.py — Add test case for `Retry-After: inf` verifying the recorded sleep is `60.0` (max_retry_after cap) and final status 200. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_publish_client_retry_after_nonfinite.py::test_retry_after_inf_capped_to_max`. (cat:test; multifile:no) [feat:shrike-notify-20261106-publish-with-retry-sleeps-for-nan-second]
- [ ] [T5] backend/tests/test_publish_client_retry_after_nonfinite.py — Add test case for `Retry-After: -5` verifying the recorded sleep is `0.5` (fallback backoff) and final status 200. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_publish_client_retry_after_nonfinite.py::test_retry_after_negative_falls_back_to_backoff`. (cat:test; multifile:no) [feat:shrike-notify-20261106-publish-with-retry-sleeps-for-nan-second]

# --- 27B-decomposed from roadmap [2026-11-06]: `notify_cli.load_payload` accepts JSON that is not an object and crashes with a traceback  (review + tweak) [feat:shrike-notify-20261106-notify-cli-load-payload-accepts-json-tha] ---
- [ ] [T5] backend/scripts/notify_cli.py — Modify `load_payload` file branch to catch `OSError` and `UnicodeDecodeError` alongside existing exceptions, printing 'Error reading payload' and exiting 1. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_notify_cli_load_payload_hardening.py::test_directory_input_exits_1 tests/test_notify_cli_load_payload_hardening.py::test_invalid_encoding_exits_1` (cat:python; multifile:no) [feat:shrike-notify-20261106-notify-cli-load-payload-accepts-json-tha]
- [ ] [T1] backend/tests/test_notify_cli_load_payload_hardening.py — Add test cases verifying `load_payload` exits with code 1 and prints 'Error: payload must be a JSON object' to stderr for inputs '[1]', '"x"', '5', and 'null'. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_notify_cli_load_payload_hardening.py::test_non_object_payloads_exit_1` (cat:test; multifile:no) [feat:shrike-notify-20261106-notify-cli-load-payload-accepts-json-tha]
- [ ] [T2] backend/tests/test_notify_cli_load_payload_hardening.py — Add test case verifying `load_payload` exits with code 1 and prints 'Error reading payload' to stderr when input is a directory path using tmp_path. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_notify_cli_load_payload_hardening.py::test_directory_input_exits_1` (cat:test; multifile:no) [feat:shrike-notify-20261106-notify-cli-load-payload-accepts-json-tha]
- [ ] [T3] backend/tests/test_notify_cli_load_payload_hardening.py — Add test case verifying `load_payload` exits with code 1 and prints 'Error reading payload' to stderr when input file contains non-UTF-8 bytes. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_notify_cli_load_payload_hardening.py::test_invalid_encoding_exits_1` (cat:test; multifile:no) [feat:shrike-notify-20261106-notify-cli-load-payload-accepts-json-tha]
- [ ] [T4] backend/tests/test_notify_cli_load_payload_hardening.py — Add test cases verifying `load_payload` returns the correct dict for valid JSON object string and valid @file path. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_notify_cli_load_payload_hardening.py::test_valid_object_returns_dict` (cat:test; multifile:no) [feat:shrike-notify-20261106-notify-cli-load-payload-accepts-json-tha]

# --- 27B-decomposed from roadmap [2026-11-06]: `MessageStore.prune(max_count=0)` deletes nothing, so a topic configured to retain zero me (review + tweak) [feat:shrike-notify-20261106-messagestore-prune-max-count-0-deletes-n] ---
- [ ] [T1] backend/app/persistence.py — Modify `MessageStore.prune` to treat `max_count == 0` as a keep-none condition by executing `delete(MessageRecord).where(base_cond)` and returning the deleted row count, while preserving existing behavior for `None` and positive integers. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_persistence_prune_zero_cap.py::test_prune_zero_cap_deletes_all_rows`. (cat:python; multifile:no) [feat:shrike-notify-20261106-messagestore-prune-max-count-0-deletes-n]
- [ ] [T2] backend/app/persistence.py — Update the docstring of `MessageStore.prune` to explicitly state that `max_count=0` results in deleting all rows for the topic, distinguishing it from `None` (no cap). VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_persistence_prune_zero_cap.py::test_prune_docstring_mentions_zero`. (cat:docs; multifile:no) [feat:shrike-notify-20261106-messagestore-prune-max-count-0-deletes-n]
- [ ] [T3] backend/tests/test_persistence_prune_zero_cap.py — Create the test file with fixtures mirroring `test_persistence.py` (sqlite in tmp_path) and implement `test_prune_zero_cap_deletes_all_rows` to assert that `prune(max_count=0)` returns the correct count and `load()` returns an empty list for the target topic. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_persistence_prune_zero_cap.py::test_prune_zero_cap_deletes_all_rows`. (cat:test; multifile:no) [feat:shrike-notify-20261106-messagestore-prune-max-count-0-deletes-n]
- [ ] [T4] backend/tests/test_persistence_prune_zero_cap.py — Add `test_prune_zero_cap_preserves_other_topics` to verify that rows belonging to a different topic remain intact after pruning one topic with `max_count=0`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_persistence_prune_zero_cap.py::test_prune_zero_cap_preserves_other_topics`. (cat:test; multifile:no) [feat:shrike-notify-20261106-messagestore-prune-max-count-0-deletes-n]
- [ ] [T5] backend/tests/test_persistence_prune_zero_cap.py — Add `test_prune_none_cap_deletes_nothing` to confirm that `max_count=None` results in zero deletions and all rows are retained. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_persistence_prune_zero_cap.py::test_prune_none_cap_deletes_nothing`. (cat:test; multifile:no) [feat:shrike-notify-20261106-messagestore-prune-max-count-0-deletes-n]

# --- 27B-decomposed from roadmap [2026-11-06]: `cleanup_garbage.find_garbage_paths` skips `.github` (and any directory with `.git`/`venv` (review + tweak) [feat:shrike-notify-20261106-cleanup-garbage-find-garbage-paths-skips] ---
- [ ] [T1] backend/scripts/cleanup_garbage.py — Add `SKIP_DIRS = {'.git', '.venv', 'venv', 'node_modules', '__pycache__'}` constant at module level. VERIFY: `cd backend && .venv/bin/python -c "from scripts.cleanup_garbage import SKIP_DIRS; assert SKIP_DIRS == {'.git', '.venv', 'venv', 'node_modules', '__pycache__'}"`. (cat:python; multifile:no) [feat:shrike-notify-20261106-cleanup-garbage-find-garbage-paths-skips]
- [ ] [T2] backend/scripts/cleanup_garbage.py — In `find_garbage_paths`, replace the substring `if '.git' in root or 'venv' in root: continue` with `dirs[:] = [d for d in dirs if d not in SKIP_DIRS]` placed before the file iteration loop. VERIFY: `cd backend && .venv/bin/python -c "import inspect; from scripts import cleanup_garbage; src = inspect.getsource(cleanup_garbage.find_garbage_paths); assert 'dirs[:]' in src and \"if '.git' in root\" not in src"`. (cat:python; multifile:no) [feat:shrike-notify-20261106-cleanup-garbage-find-garbage-paths-skips]
- [ ] [T3] backend/tests/test_cleanup_garbage_walk_pruning.py — Create test file with `test_github_artifact_reported` verifying that a garbage file inside `.github/` is returned by `find_garbage_paths`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_cleanup_garbage_walk_pruning.py::test_github_artifact_reported`. (cat:test; multifile:no) [feat:shrike-notify-20261106-cleanup-garbage-find-garbage-paths-skips]
- [ ] [T4] backend/tests/test_cleanup_garbage_walk_pruning.py — Add `test_venv_and_git_not_reported` verifying that garbage files inside `.venv/` and `.git/` are NOT returned by `find_garbage_paths`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_cleanup_garbage_walk_pruning.py::test_venv_and_git_not_reported`. (cat:test; multifile:no) [feat:shrike-notify-20261106-cleanup-garbage-find-garbage-paths-skips]
- [ ] [T5] backend/tests/test_cleanup_garbage_walk_pruning.py — Add `test_check_returns_1_for_garbage` verifying that `check()` returns exit code 1 and prints the path when a garbage file exists in a non-skipped directory. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_cleanup_garbage_walk_pruning.py::test_check_returns_1_for_garbage`. (cat:test; multifile:no) [feat:shrike-notify-20261106-cleanup-garbage-find-garbage-paths-skips]

# --- 27B-decomposed from roadmap [2026-11-06]: `NOTIFY_DATABASE_URL` in the form hosting providers hand out crashes startup with a confus (review + tweak) [feat:shrike-notify-20261106-notify-database-url-in-the-form-hosting-] ---
- [ ] [T1] backend/app/config.py — Add pure helper `_normalize_database_url(url: str) -> str` that rewrites `postgres://` and `postgresql://` prefixes to `postgresql+asyncpg://`, `sqlite://` to `sqlite+aiosqlite://`, and returns other URLs unchanged. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_config_database_url.py::test_normalize_helper`. (cat:python; multifile:no) [feat:shrike-notify-20261106-notify-database-url-in-the-form-hosting-]
- [ ] [T3] backend/app/config.py — Modify the `database_url` field in `Settings` to use a default factory or validator that applies `_normalize_database_url` to the incoming value. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_config_database_url.py::test_settings_normalization`. (cat:python; multifile:no) [feat:shrike-notify-20261106-notify-database-url-in-the-form-hosting-]
- [ ] [T2] backend/tests/test_config_database_url.py — Create test file with unit tests for `_normalize_database_url` covering the three rewrites (preserving creds/host/path/query), unchanged cases (`postgresql+asyncpg://`, `sqlite+aiosqlite:///`, `mysql://`), and edge cases. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_config_database_url.py::test_normalize_helper`. (cat:test; multifile:no) [feat:shrike-notify-20261106-notify-database-url-in-the-form-hosting-]
- [ ] [T4] backend/tests/test_config_database_url.py — Add integration-style tests verifying `Settings().database_url` behavior: unset env yields normalized sqlite default, `NOTIFY_DATABASE_URL=postgres://u:p@h/db` yields `postgresql+asyncpg://u:p@h/db`, and existing valid URLs pass through. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_config_database_url.py::test_settings_normalization`. (cat:test; multifile:no) [feat:shrike-notify-20261106-notify-database-url-in-the-form-hosting-]
- [ ] [T5] backend/tests/test_config_database_url.py — Add regression test ensuring that when `NOTIFY_DATABASE_URL` is set to a raw `postgres://` URL, the resulting `Settings().database_url` is exactly `postgresql+asyncpg://u:p@h/db` (red before fix). VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_config_database_url.py::test_regression_postgres_rewrite`. (cat:test; multifile:no) [feat:shrike-notify-20261106-notify-database-url-in-the-form-hosting-]

# --- 27B-decomposed from roadmap [2026-11-06]: `notify_cli.fetch_sse_stream` (the engine behind the `watch` subcommand) has no test that  (review + tweak) [feat:shrike-notify-20261106-notify-cli-fetch-sse-stream-the-engine-b] ---
- [ ] [T2] backend/tests/test_notify_cli_fetch_sse_stream.py — Add test `test_fetch_sse_stream_mixed_payload` using `httpx.MockTransport` to verify parsing of comments, ids, valid/invalid JSON, and empty data lines yields `[{'a': 1}, {'b': 2}]`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_notify_cli_fetch_sse_stream.py::test_fetch_sse_stream_mixed_payload`. (cat:test; multifile:no) [feat:shrike-notify-20261106-notify-cli-fetch-sse-stream-the-engine-b]
- [ ] [T2] backend/tests/test_notify_cli_fetch_sse_stream.py — Add test `test_fetch_sse_stream_auth_header` verifying `Authorization: Bearer <token>` is sent when token provided and absent when not. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_notify_cli_fetch_sse_stream.py::test_fetch_sse_stream_auth_header`. (cat:test; multifile:no) [feat:shrike-notify-20261106-notify-cli-fetch-sse-stream-the-engine-b]
- [ ] [T2] backend/tests/test_notify_cli_fetch_sse_stream.py — Add test `test_fetch_sse_stream_error_401` verifying `httpx.HTTPStatusError` is raised on 401 response. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_notify_cli_fetch_sse_stream.py::test_fetch_sse_stream_error_401`. (cat:test; multifile:no) [feat:shrike-notify-20261106-notify-cli-fetch-sse-stream-the-engine-b]
- [ ] [T2] backend/tests/test_notify_cli_fetch_sse_stream.py — Add test `test_fetch_sse_stream_error_500` verifying `httpx.HTTPStatusError` is raised on 500 response. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_notify_cli_fetch_sse_stream.py::test_fetch_sse_stream_error_500`. (cat:test; multifile:no) [feat:shrike-notify-20261106-notify-cli-fetch-sse-stream-the-engine-b]
- [ ] [T2] backend/tests/test_notify_cli_fetch_sse_stream.py — Add test `test_fetch_sse_stream_empty_body` verifying an empty stream yields `[]`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_notify_cli_fetch_sse_stream.py::test_fetch_sse_stream_empty_body`. (cat:test; multifile:no) [feat:shrike-notify-20261106-notify-cli-fetch-sse-stream-the-engine-b]
- [ ] [T2] backend/tests/test_notify_cli_fetch_sse_stream.py — Run full test file and existing watch tests to ensure no regressions. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_notify_cli_fetch_sse_stream.py tests/test_notify_cli_watch.py`. (cat:test; multifile:no) [feat:shrike-notify-20261106-notify-cli-fetch-sse-stream-the-engine-b]

# --- 27B-decomposed from roadmap [2026-11-06]: `TokenStore.prune_expired` has no test for the rows it must keep - `backend/app/persistenc (review + tweak) [feat:shrike-notify-20261106-tokenstore-prune-expired-has-no-test-for] ---
- [ ] [T1] backend/tests/test_token_store_prune_unparseable.py — Create new test file with `token_store` fixture mirroring `backend/tests/test_token_store_prune.py` and a test asserting that `prune_expired()` returns 0 when the store contains only unparseable ids (`legacy`, `a.x.y.sig`) and a ttl-0 token, leaving all rows intact. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_token_store_prune_unparseable.py::test_unparseable_and_ttl0_retained`. (cat:test; multifile:no) [feat:shrike-notify-20261106-tokenstore-prune-expired-has-no-test-for]
- [ ] [T1] backend/tests/test_token_store_prune_unparseable.py — Add test asserting that `prune_expired()` returns 1 when the store contains an expired valid id (`a.<now-100>.10.sig`), unparseable ids, and a ttl-0 token, deleting only the expired row. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_token_store_prune_unparseable.py::test_expired_deleted_others_retained`. (cat:test; multifile:no) [feat:shrike-notify-20261106-tokenstore-prune-expired-has-no-test-for]
- [ ] [T1] backend/tests/test_token_store_prune_unparseable.py — Add test asserting that `prune_expired()` removes the `RevokedToken` row for an expired id but retains the `RevokedToken` row for a retained unparseable id, after calling `revoke_token` on both before pruning. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_token_store_prune_unparseable.py::test_revoked_rows_cleanup`. (cat:test; multifile:no) [feat:shrike-notify-20261106-tokenstore-prune-expired-has-no-test-for]
- [ ] [T2] backend/tests/test_token_store_prune_unparseable.py — Add test asserting that `get_all_tokens()` returns exactly `['legacy', 'a.x.y.sig']` after `prune_expired()` runs on a mixed store, confirming the unparseable rows are not deleted. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_token_store_prune_unparseable.py::test_get_all_tokens_after_prune`. (cat:test; multifile:no) [feat:shrike-notify-20261106-tokenstore-prune-expired-has-no-test-for]
- [ ] [T2] backend/tests/test_token_store_prune_unparseable.py — Add test asserting that a token with `ttl=0` and an old `issued_at` is not deleted by `prune_expired()`, verifying the "ttl 0 never expires" logic. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_token_store_prune_unparseable.py::test_ttl_zero_never_expires`. (cat:test; multifile:no) [feat:shrike-notify-20261106-tokenstore-prune-expired-has-no-test-for]
- [ ] [T3] backend/tests/test_token_store_prune_unparseable.py — Add test asserting that `prune_expired()` is idempotent when run twice on a store with unparseable and expired rows, returning 0 on the second call. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_token_store_prune_unparseable.py::test_idempotency_with_unparseable`. (cat:test; multifile:no) [feat:shrike-notify-20261106-tokenstore-prune-expired-has-no-test-for]
