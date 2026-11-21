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

# --- 27B-decomposed from roadmap [2026-11-10]: `AuthService.get_last_used_at` and the usage counters are untested together - `backend/app (review + tweak) [feat:shrike-notify-20261110-authservice-get-last-used-at-and-the-usa] ---

# --- 27B-decomposed from roadmap [2026-11-10]: `AuthManager.list_active` with a persistent store skips expired and malformed token ids, w (review + tweak) [feat:shrike-notify-20261110-authmanager-list-active-with-a-persisten] ---

# --- 27B-decomposed from roadmap [2026-11-11]: `issue_token` persistence failure outside an event loop is untested - `backend/app/service (review + tweak) [feat:shrike-notify-20261111-issue-token-persistence-failure-outside-] ---

# --- 27B-decomposed from roadmap [2026-11-11]: `record_token_usage` store failure outside an event loop is untested - `backend/app/servic (review + tweak) [feat:shrike-notify-20261111-record-token-usage-store-failure-outside] ---

# --- 27B-decomposed from roadmap [2026-11-11]: `should_deliver_now` timezone override and priority rules in broker.py are untested - `bac (review + tweak) [feat:shrike-notify-20261111-should-deliver-now-timezone-override-and] ---

# --- 27B-decomposed from roadmap [2026-11-11]: The guarded-name branch of `cleanup_garbage` is untested - `backend/scripts/cleanup_garbag (review + tweak) [feat:shrike-notify-20261111-the-guarded-name-branch-of-cleanup-garba] ---

# --- 27B-decomposed from roadmap [2026-11-11]: `MaxBodyBytesMiddleware` with a non-numeric `Content-Length` is untested - `backend/app/mi (review + tweak) [feat:shrike-notify-20261111-maxbodybytesmiddleware-with-a-non-numeri] ---

# --- 27B-decomposed from roadmap [2026-11-11]: `notify_cli.check_health` and `check_auth_rejection` failure paths are untested - `backend (review + tweak) [feat:shrike-notify-20261111-notify-cli-check-health-and-check-auth-r] ---

# --- 27B-decomposed from roadmap [2026-11-11]: `notify_cli.check_sse_reception` and the default smoke payload are untested - `backend/scr (review + tweak) [feat:shrike-notify-20261111-notify-cli-check-sse-reception-and-the-d] ---

# --- 27B-decomposed from roadmap [2026-11-11]: `notify_cli.main` smoke-check dispatch and missing publish arguments are untested - `backe (review + tweak) [feat:shrike-notify-20261111-notify-cli-main-smoke-check-dispatch-and] ---

# --- 27B-decomposed from roadmap [2026-11-11]: `notify_cli.main` bootstrap-token secret handling and publish error exits are untested - ` (review + tweak) [feat:shrike-notify-20261111-notify-cli-main-bootstrap-token-secret-h] ---

# --- 27B-decomposed from roadmap [2026-11-11]: `pre_commit_check.check_script_executable_and_syntax` has no test - `backend/scripts/pre_c (review + tweak) [feat:shrike-notify-20261111-pre-commit-check-check-script-executable] ---

# --- 27B-decomposed from roadmap [2026-11-11]: `pre_commit_check.main` filename rules and exit codes have no test - `backend/scripts/pre_ (review + tweak) [feat:shrike-notify-20261111-pre-commit-check-main-filename-rules-and] ---

# --- 27B-decomposed from roadmap [2026-11-11]: `token_mint --list-topics` and the invalid-scope guard in `mint_tokens` are untested - `ba (review + tweak) [feat:shrike-notify-20261111-token-mint-list-topics-and-the-invalid-s] ---

# --- 27B-decomposed from roadmap [2026-11-11]: Add file backend/tests/test_redact_param.py: `_redact_param` has no direct test - `backend (review + tweak) [feat:shrike-notify-20261111-add-file-backend-tests-test-redact-param] ---

# --- 27B-decomposed from roadmap [2026-11-11]: Add backend/.dockerignore so `COPY . .` stops baking local state into the image - `backend (review + tweak) [feat:shrike-notify-20261111-add-backend-dockerignore-so-copy-stops-b] ---

# --- 27B-decomposed from roadmap [2026-11-11]: The WebSocket endpoint's invalid-topic close and auth-required close are untested - `backe (review + tweak) [feat:shrike-notify-20261111-the-websocket-endpoint-s-invalid-topic-c] ---

# --- 27B-decomposed from roadmap [2026-11-11]: `format_sse` frame layout with and without `id` and `event` is not pinned directly - `back (review + tweak) [feat:shrike-notify-20261111-format-sse-frame-layout-with-and-without] ---

# --- 27B-decomposed from roadmap [2026-11-11]: `Broker.unsubscribe` for a topic that was never subscribed is untested - `backend/app/serv (review + tweak) [feat:shrike-notify-20261111-broker-unsubscribe-for-a-topic-that-was-] ---

# --- 27B-decomposed from roadmap [2026-11-11]: Add a bounded in-memory delivery log module - create `backend/app/services/delivery_log.py (review + tweak) [feat:shrike-notify-20261111-add-a-bounded-in-memory-delivery-log-mod] ---

# --- 27B-decomposed from roadmap [2026-11-11]: Record a delivery receipt for every accepted publish - in `backend/app/routers/publish.py` (review + tweak) [feat:shrike-notify-20261111-record-a-delivery-receipt-for-every-acce] ---

# --- 27B-decomposed from roadmap [2026-11-11]: Add `GET /{topic}/messages/{message_id}` returning one retained message - in `backend/app/ (review + tweak) [feat:shrike-notify-20261111-add-get-topic-messages-message-id-return] ---

# --- 27B-decomposed from roadmap [2026-11-11]: Add `GET /{topic}/messages/{message_id}/receipt` - in `backend/app/routers/messages.py` de (review + tweak) [feat:shrike-notify-20261111-add-get-topic-messages-message-id-receip] ---

# --- 27B-decomposed from roadmap [2026-11-11]: Return the new message id in an `X-Message-ID` response header - in `backend/app/routers/p (review + tweak) [feat:shrike-notify-20261111-return-the-new-message-id-in-an-x-messag] ---

# --- 27B-decomposed from roadmap [2026-11-11]: Expose `X-Message-ID` to browser clients - in `backend/app/main.py` add `"X-Message-ID"` t (review + tweak) [feat:shrike-notify-20261111-expose-x-message-id-to-browser-clients-i] ---

# --- 27B-decomposed from roadmap [2026-11-11]: Document the lookup and receipt endpoints in the README - in `README.md` add two rows to t (review + tweak) [feat:shrike-notify-20261111-document-the-lookup-and-receipt-endpoint] ---

# --- 27B-decomposed from roadmap [2026-11-11]: Add a safe placeholder renderer - create `backend/app/utils/templating.py` with `render_te (review + tweak) [feat:shrike-notify-20261111-add-a-safe-placeholder-renderer-create-b] ---

# --- 27B-decomposed from roadmap [2026-11-11]: Support a default value in a placeholder - in `backend/app/utils/templating.py` let `{{ na (review + tweak) [feat:shrike-notify-20261111-support-a-default-value-in-a-placeholder] ---

# --- 27B-decomposed from roadmap [2026-11-11]: Accept an optional `vars` object on the publish body - in `backend/app/schemas.py` add `va (review + tweak) [feat:shrike-notify-20261111-accept-an-optional-vars-object-on-the-pu] ---

# --- 27B-decomposed from roadmap [2026-11-11]: Render `vars` into the title and body when publishing - in `backend/app/routers/publish.py (review + tweak) [feat:shrike-notify-20261111-render-vars-into-the-title-and-body-when] ---

# --- 27B-decomposed from roadmap [2026-11-12]: Document `vars` in the README - in `README.md` add a short "Templating" subsection under E (review + tweak) [feat:shrike-notify-20261112-document-vars-in-the-readme-in-readme-md] ---

# --- 27B-decomposed from roadmap [2026-11-12]: Add a pure topic-overview builder - create `backend/app/services/topic_overview.py` with ` (review + tweak) [feat:shrike-notify-20261112-add-a-pure-topic-overview-builder-create] ---

# --- 27B-decomposed from roadmap [2026-11-12]: Add `GET /topics/overview` as its own router - create `backend/app/routers/topic_admin.py` (review + tweak) [feat:shrike-notify-20261112-add-get-topics-overview-as-its-own-route] ---

# --- 27B-decomposed from roadmap [2026-11-12]: Wire the topic admin router into the app - in `backend/app/main.py` import `topic_admin` n (review + tweak) [feat:shrike-notify-20261112-wire-the-topic-admin-router-into-the-app] ---

# --- 27B-decomposed from roadmap [2026-11-12]: Add `prefix` and `limit` query parameters to the overview - in `backend/app/routers/topic_ (review + tweak) [feat:shrike-notify-20261112-add-prefix-and-limit-query-parameters-to] ---

# --- 27B-decomposed from roadmap [2026-11-12]: Document the overview endpoint - in `README.md` add one API table row `GET /topics/overvie (review + tweak) [feat:shrike-notify-20261112-document-the-overview-endpoint-in-readme] ---

# --- 27B-decomposed from roadmap [2026-11-12]: Add the `NOTIFY_METRICS_ENABLED` setting - in `backend/app/config.py` add `metrics_enabled (review + tweak) [feat:shrike-notify-20261112-add-the-notify-metrics-enabled-setting-i] ---

# --- 27B-decomposed from roadmap [2026-11-12]: Add a tiny counter registry with Prometheus text output - create `backend/app/services/met (review + tweak) [feat:shrike-notify-20261112-add-a-tiny-counter-registry-with-prometh] ---

# --- 27B-decomposed from roadmap [2026-11-12]: Count publish outcomes - in `backend/app/routers/publish.py` call `metrics.inc("notify_pub (review + tweak) [feat:shrike-notify-20261112-count-publish-outcomes-in-backend-app-ro] ---

# --- 27B-decomposed from roadmap [2026-11-12]: Add the `GET /metrics` router, disabled by default - create `backend/app/routers/metrics_r (review + tweak) [feat:shrike-notify-20261112-add-the-get-metrics-router-disabled-by-d] ---

# --- 27B-decomposed from roadmap [2026-11-12]: Wire the metrics router into the app - in `backend/app/main.py` import `metrics_router` an (review + tweak) [feat:shrike-notify-20261112-wire-the-metrics-router-into-the-app-in-] ---

# --- 27B-decomposed from roadmap [2026-11-12]: Add a read-only per-topic rate-limit status route - create `backend/app/routers/rate_statu (review + tweak) [feat:shrike-notify-20261112-add-a-read-only-per-topic-rate-limit-sta] ---

# --- 27B-decomposed from roadmap [2026-11-12]: Wire the rate-status router into the app - in `backend/app/main.py` import `rate_status` a (review + tweak) [feat:shrike-notify-20261112-wire-the-rate-status-router-into-the-app] ---

# --- 27B-decomposed from roadmap [2026-11-12]: Document metrics and limits in the README - in `README.md` add the `NOTIFY_METRICS_ENABLED (review + tweak) [feat:shrike-notify-20261112-document-metrics-and-limits-in-the-readm] ---

# --- 27B-decomposed from roadmap [2026-11-12]: Add client snippets - create `docs/SDK_SNIPPETS.md` with fenced `bash` (curl publish and s (review + tweak) [feat:shrike-notify-20261112-add-client-snippets-create-docs-sdk-snip] ---

# --- 27B-decomposed from roadmap [2026-11-12]: Document retention and pruning - create `docs/RETENTION.md` describing, from reading `back (review + tweak) [feat:shrike-notify-20261112-document-retention-and-pruning-create-do] ---

# --- 27B-decomposed from roadmap [2026-11-12]: Document subscribing and resuming - create `docs/SUBSCRIBING.md` covering SSE (`GET /{topi (review + tweak) [feat:shrike-notify-20261112-document-subscribing-and-resuming-create] ---

# --- 27B-decomposed from roadmap [2026-11-12]: Document the health endpoints - create `docs/OPERATIONS.md` with a table of the keys retur (review + tweak) [feat:shrike-notify-20261112-document-the-health-endpoints-create-doc] ---

# --- 27B-decomposed from roadmap [2026-11-12]: Link the new docs from the README - in `README.md` add a "Docs" section listing `docs/SDK_ (review + tweak) [feat:shrike-notify-20261112-link-the-new-docs-from-the-readme-in-rea] ---

# --- 27B-decomposed from roadmap [2026-11-12]: Add the message filter helpers - create `backend/app/utils/message_filter.py` with `parse_ (review + tweak) [feat:shrike-notify-20261112-add-the-message-filter-helpers-create-ba] ---

# --- 27B-decomposed from roadmap [2026-11-12]: Add the `q` filter to the history route - in `backend/app/routers/messages.py` import `fil (review + tweak) [feat:shrike-notify-20261112-add-the-q-filter-to-the-history-route-in] ---

# --- 27B-decomposed from roadmap [2026-11-13]: Add the `since` and `until` window - in `backend/app/routers/messages.py` add `since: str  (review + tweak) [feat:shrike-notify-20261113-add-the-since-and-until-window-in-backen] ---

# --- 27B-decomposed from roadmap [2026-11-13]: Add the `severity` filter - in `backend/app/routers/messages.py` add `severity: str | None (review + tweak) [feat:shrike-notify-20261113-add-the-severity-filter-in-backend-app-r] ---

# --- 27B-decomposed from roadmap [2026-11-13]: Document the history filters - in `README.md` change the `GET /{topic}/messages` table row (review + tweak) [feat:shrike-notify-20261113-document-the-history-filters-in-readme-m] ---

# --- 27B-decomposed from roadmap [2026-11-13]: Add the tag counting helper - create `backend/app/utils/tag_counts.py` with `count_tags(me (review + tweak) [feat:shrike-notify-20261113-add-the-tag-counting-helper-create-backe] ---

# --- 27B-decomposed from roadmap [2026-11-13]: Add the tags router - create `backend/app/routers/tags.py` with `router = APIRouter(tags=[ (review + tweak) [feat:shrike-notify-20261113-add-the-tags-router-create-backend-app-r] ---

# --- 27B-decomposed from roadmap [2026-11-13]: Wire the tags router into the app - in `backend/app/main.py` change the import line `from  (review + tweak) [feat:shrike-notify-20261113-wire-the-tags-router-into-the-app-in-bac] ---

# --- 27B-decomposed from roadmap [2026-11-13]: Document the tags route - in `README.md` add an API table row `| GET | /{topic}/tags?prefi (review + tweak) [feat:shrike-notify-20261113-document-the-tags-route-in-readme-md-add] ---

# --- 27B-decomposed from roadmap [2026-11-13]: Add the message line formatter - in `backend/scripts/notify_cli.py` add `format_message_li (review + tweak) [feat:shrike-notify-20261113-add-the-message-line-formatter-in-backen] ---

# --- 27B-decomposed from roadmap [2026-11-15]: Add the history fetch helper - in `backend/scripts/notify_cli.py` add `async def fetch_his (review + tweak) [feat:shrike-notify-20261115-add-the-history-fetch-helper-in-backend-] ---

# --- 27B-decomposed from roadmap [2026-11-15]: Add the `history` subcommand arguments - in `parse_args()` of `backend/scripts/notify_cli. (review + tweak) [feat:shrike-notify-20261115-add-the-history-subcommand-arguments-in-] ---

# --- 27B-decomposed from roadmap [2026-11-15]: Dispatch the `history` subcommand - in `main()` of `backend/scripts/notify_cli.py` add `el (review + tweak) [feat:shrike-notify-20261115-dispatch-the-history-subcommand-in-main-] ---

# --- 27B-decomposed from roadmap [2026-11-15]: Add the two fields to the stats schema - in `backend/app/schemas.py` add `subscribers: int (review + tweak) [feat:shrike-notify-20261115-add-the-two-fields-to-the-stats-schema-i] ---

# --- 27B-decomposed from roadmap [2026-11-15]: Report live subscribers in the stats route - in `get_stats` of `backend/app/routers/messag (review + tweak) [feat:shrike-notify-20261115-report-live-subscribers-in-the-stats-rou] ---

# --- 27B-decomposed from roadmap [2026-11-15]: Report held quiet-hours messages in the stats route - in `get_stats` pass `held=len(broker (review + tweak) [feat:shrike-notify-20261115-report-held-quiet-hours-messages-in-the-] ---

# --- 27B-decomposed from roadmap [2026-11-15]: Document the stats route - in `README.md` add the API table row `| GET | /{topic}/stats |  (review + tweak) [feat:shrike-notify-20261115-document-the-stats-route-in-readme-md-ad] ---

# --- 27B-decomposed from roadmap [2026-11-15]: Add the NDJSON encoder - create `backend/app/utils/ndjson.py` with `to_ndjson(rows: list[d (review + tweak) [feat:shrike-notify-20261115-add-the-ndjson-encoder-create-backend-ap] ---

# --- 27B-decomposed from roadmap [2026-11-16]: Add the export router - create `backend/app/routers/export.py` with `router = APIRouter(ta (review + tweak) [feat:shrike-notify-20261116-add-the-export-router-create-backend-app] ---

# --- 27B-decomposed from roadmap [2026-11-16]: Make the export a download - in `backend/app/routers/export.py` pass `headers={'Content-Di (review + tweak) [feat:shrike-notify-20261116-make-the-export-a-download-in-backend-ap] ---

# --- 27B-decomposed from roadmap [2026-11-16]: Wire the export router into the app - in `backend/app/main.py` import `export` from `app.r (review + tweak) [feat:shrike-notify-20261116-wire-the-export-router-into-the-app-in-b] ---

# --- 27B-decomposed from roadmap [2026-11-16]: Document the export route - in `README.md` add the API table row `| GET | /{topic}/export? (review + tweak) [feat:shrike-notify-20261116-document-the-export-route-in-readme-md-a] ---

# --- 27B-decomposed from roadmap [2026-11-16]: Add the retry schedule helper - create `backend/app/utils/retry_schedule.py` with `retry_s (review + tweak) [feat:shrike-notify-20261116-add-the-retry-schedule-helper-create-bac] ---

# --- 27B-decomposed from roadmap [2026-11-16]: Add the total wait helper - in `backend/app/utils/retry_schedule.py` add `total_retry_wait (review + tweak) [feat:shrike-notify-20261116-add-the-total-wait-helper-in-backend-app] ---

# --- 27B-decomposed from roadmap [2026-11-16]: Add the schedule text formatter - in `backend/app/utils/retry_schedule.py` add `format_ret (review + tweak) [feat:shrike-notify-20261116-add-the-schedule-text-formatter-in-backe] ---

# --- 27B-decomposed from roadmap [2026-11-16]: Pin the retry defaults to the real client - create `backend/tests/test_retry_defaults_matc (review + tweak) [feat:shrike-notify-20261116-pin-the-retry-defaults-to-the-real-clien] ---

# --- 27B-decomposed from roadmap [2026-11-16]: Pin the retry doc to the helper - create `backend/tests/test_retry_doc_pinned.py` that rea (review + tweak) [feat:shrike-notify-20261116-pin-the-retry-doc-to-the-helper-create-b] ---

# --- 27B-decomposed from roadmap [2026-11-16]: Add the settings rows helper - create `backend/app/utils/settings_report.py` with `setting (review + tweak) [feat:shrike-notify-20261116-add-the-settings-rows-helper-create-back] ---

# --- 27B-decomposed from roadmap [2026-11-16]: Add the settings report formatter - in `backend/app/utils/settings_report.py` add `format_ (review + tweak) [feat:shrike-notify-20261116-add-the-settings-report-formatter-in-bac] ---

# --- 27B-decomposed from roadmap [2026-11-17]: Add the advisory notes helper - in `backend/app/utils/settings_report.py` add `settings_no (review + tweak) [feat:shrike-notify-20261117-add-the-advisory-notes-helper-in-backend] ---

# --- 27B-decomposed from roadmap [2026-11-17]: Add the unknown environment variable check - create `backend/app/utils/env_check.py` with  (review + tweak) [feat:shrike-notify-20261117-add-the-unknown-environment-variable-che] ---

# --- 27B-decomposed from roadmap [2026-11-17]: Add the malformed value check - in `backend/app/utils/env_check.py` add `malformed_env_val (review + tweak) [feat:shrike-notify-20261117-add-the-malformed-value-check-in-backend] ---

# --- 27B-decomposed from roadmap [2026-11-17]: Add the config report builder - create `backend/app/utils/config_command.py` with `build_c (review + tweak) [feat:shrike-notify-20261117-add-the-config-report-builder-create-bac] ---

# --- 27B-decomposed from roadmap [2026-11-17]: Add the `config` subcommand - in `backend/scripts/notify_cli.py` add `config_parser = subp (review + tweak) [feat:shrike-notify-20261117-add-the-config-subcommand-in-backend-scr] ---

# --- 27B-decomposed from roadmap [2026-11-17]: Add the topics fetch helper - in `backend/scripts/notify_cli.py` add `async def fetch_topi (review + tweak) [feat:shrike-notify-20261117-add-the-topics-fetch-helper-in-backend-s] ---

# --- 27B-decomposed from roadmap [2026-11-17]: Add the `topics` subcommand - in `backend/scripts/notify_cli.py` add a `topics` subparser  (review + tweak) [feat:shrike-notify-20261117-add-the-topics-subcommand-in-backend-scr] ---

# --- 27B-decomposed from roadmap [2026-11-17]: Add the retention report helper - create `backend/app/services/retention_report.py` with ` (review + tweak) [feat:shrike-notify-20261117-add-the-retention-report-helper-create-b] ---

# --- 27B-decomposed from roadmap [2026-11-17]: Add the retention router - create `backend/app/routers/retention.py` with `router = APIRou (review + tweak) [feat:shrike-notify-20261117-add-the-retention-router-create-backend-] ---

# --- 27B-decomposed from roadmap [2026-11-17]: Wire the retention router - in `backend/app/main.py` import `retention` in the `from app.r (review + tweak) [feat:shrike-notify-20261117-wire-the-retention-router-in-backend-app] ---

# --- 27B-decomposed from roadmap [2026-11-17]: Document the retention route - in `README.md` add an API table row `| GET | /{topic}/reten (review + tweak) [feat:shrike-notify-20261117-document-the-retention-route-in-readme-m] ---

# --- 27B-decomposed from roadmap [2026-11-17]: Add an example to `PublishRequest` - in `backend/app/schemas.py` extend `PublishRequest.mo (review + tweak) [feat:shrike-notify-20261117-add-an-example-to-publishrequest-in-back] ---

# --- 27B-decomposed from roadmap [2026-11-17]: Add examples to `MessageOut` and `PublishResult` - in `backend/app/schemas.py` add `model_ (review + tweak) [feat:shrike-notify-20261117-add-examples-to-messageout-and-publishre] ---

# --- 27B-decomposed from roadmap [2026-11-17]: Add examples to `TopicStatsOut` and `TokenResult` - in `backend/app/schemas.py` add `model (review + tweak) [feat:shrike-notify-20261117-add-examples-to-topicstatsout-and-tokenr] ---

# --- 27B-decomposed from roadmap [2026-11-17]: Pin that the examples validate - create `backend/tests/test_openapi_examples_validate.py`  (review + tweak) [feat:shrike-notify-20261117-pin-that-the-examples-validate-create-ba] ---

# --- 27B-decomposed from roadmap [2026-11-17]: Add the hourly counts helper - create `backend/app/utils/activity.py` with `hourly_counts( (review + tweak) [feat:shrike-notify-20261117-add-the-hourly-counts-helper-create-back] ---

# --- 27B-decomposed from roadmap [2026-11-17]: Add the busiest-hour helper - in `backend/app/utils/activity.py` add `busiest_bucket(count (review + tweak) [feat:shrike-notify-20261117-add-the-busiest-hour-helper-in-backend-a] ---

# --- 27B-decomposed from roadmap [2026-11-17]: Add the activity router - create `backend/app/routers/activity.py` with `router = APIRoute (review + tweak) [feat:shrike-notify-20261117-add-the-activity-router-create-backend-a] ---

# --- 27B-decomposed from roadmap [2026-11-17]: Wire the activity router - in `backend/app/main.py` import `activity` in the `from app.rou (review + tweak) [feat:shrike-notify-20261117-wire-the-activity-router-in-backend-app-] ---

# --- 27B-decomposed from roadmap [2026-11-17]: Add the message line renderer - create `backend/app/utils/render.py` with `render_message_ (review + tweak) [feat:shrike-notify-20261117-add-the-message-line-renderer-create-bac] ---

# --- 27B-decomposed from roadmap [2026-11-17]: Add the digest renderer with a length cap - in `backend/app/utils/render.py` add `truncate (review + tweak) [feat:shrike-notify-20261117-add-the-digest-renderer-with-a-length-ca] ---

# --- 27B-decomposed from roadmap [2026-11-18]: Add the digest router - create `backend/app/routers/digest.py` with `router = APIRouter(ta (review + tweak) [feat:shrike-notify-20261118-add-the-digest-router-create-backend-app] ---

# --- 27B-decomposed from roadmap [2026-11-18]: Wire the digest router - in `backend/app/main.py` import `digest` in the `from app.routers (review + tweak) [feat:shrike-notify-20261118-wire-the-digest-router-in-backend-app-ma] ---

# --- 27B-decomposed from roadmap [2026-11-19]: Add the delivery summary helper - create `backend/app/services/delivery_summary.py` with ` (review + tweak) [feat:shrike-notify-20261119-add-the-delivery-summary-helper-create-b] ---

# --- 27B-decomposed from roadmap [2026-11-19]: Add the delivery summary router - create `backend/app/routers/delivery_summary.py` with `r (review + tweak) [feat:shrike-notify-20261119-add-the-delivery-summary-router-create-b] ---

# --- 27B-decomposed from roadmap [2026-11-19]: Wire the delivery summary router - in `backend/app/main.py` import `delivery_summary` in t (review + tweak) [feat:shrike-notify-20261119-wire-the-delivery-summary-router-in-back] ---

# --- 27B-decomposed from roadmap [2026-11-19]: Add the next change helper - create `backend/app/utils/quiet_status.py` with `next_quiet_c (review + tweak) [feat:shrike-notify-20261119-add-the-next-change-helper-create-backen] ---

# --- 27B-decomposed from roadmap [2026-11-19]: Add the status dict helper - in `backend/app/utils/quiet_status.py` add `quiet_hours_statu (review + tweak) [feat:shrike-notify-20261119-add-the-status-dict-helper-in-backend-ap] ---

# --- 27B-decomposed from roadmap [2026-11-19]: Add the body splitter - create `backend/app/utils/split_body.py` with `split_body(body: st (review + tweak) [feat:shrike-notify-20261119-add-the-body-splitter-create-backend-app] ---

# --- 27B-decomposed from roadmap [2026-11-19]: Add the part numbering helper - in `backend/app/utils/split_body.py` add `number_parts(par (review + tweak) [feat:shrike-notify-20261119-add-the-part-numbering-helper-in-backend] ---

# --- 27B-decomposed from roadmap [2026-11-19]: Add the batch publish helper - create `backend/app/utils/publish_batch.py` with `async def (review + tweak) [feat:shrike-notify-20261119-add-the-batch-publish-helper-create-back] ---

# --- 27B-decomposed from roadmap [2026-11-19]: Add the batch summary line - in `backend/app/utils/publish_batch.py` add `summarize_batch( (review + tweak) [feat:shrike-notify-20261119-add-the-batch-summary-line-in-backend-ap] ---

# --- 27B-decomposed from roadmap [2026-11-20]: Add the topic suggestion helper - create `backend/app/utils/topic_hint.py` with `suggest_t (review + tweak) [feat:shrike-notify-20261120-add-the-topic-suggestion-helper-create-b] ---

# --- 27B-decomposed from roadmap [2026-11-20]: Add the priority and severity reference doc - create `docs/PRIORITY_AND_SEVERITY.md` (titl (review + tweak) [feat:shrike-notify-20261120-add-the-priority-and-severity-reference-] ---

# --- 27B-decomposed from roadmap [2026-11-20]: Add the module map doc - create `docs/MODULES.md` (title `# Module map`) with a section `# (review + tweak) [feat:shrike-notify-20261120-add-the-module-map-doc-create-docs-modul] ---

# --- 27B-decomposed from roadmap [2026-11-20]: Add the scope description helper - create `backend/app/utils/scope_text.py` with `describe (review + tweak) [feat:shrike-notify-20261120-add-the-scope-description-helper-create-] ---

# --- 27B-decomposed from roadmap [2026-11-20]: Add the scope overlap helper - in `backend/app/utils/scope_text.py` add `scopes_overlap(a: (review + tweak) [feat:shrike-notify-20261120-add-the-scope-overlap-helper-in-backend-] ---

# --- 27B-decomposed from roadmap [2026-11-20]: Add the token scopes doc pinned to the helpers - create `docs/TOKEN_SCOPES.md` (title `# T (review + tweak) [feat:shrike-notify-20261120-add-the-token-scopes-doc-pinned-to-the-h] ---

# --- 27B-decomposed from roadmap [2026-11-20]: Add the priority breakdown helper - create `backend/app/utils/breakdown.py` with `priority (review + tweak) [feat:shrike-notify-20261120-add-the-priority-breakdown-helper-create] ---

# --- 27B-decomposed from roadmap [2026-11-20]: Add the severity breakdown helper - in `backend/app/utils/breakdown.py` add `severity_brea (review + tweak) [feat:shrike-notify-20261120-add-the-severity-breakdown-helper-in-bac] ---

# --- 27B-decomposed from roadmap [2026-11-20]: Add the breakdown router - create `backend/app/routers/breakdown.py` with `router = APIRou (review + tweak) [feat:shrike-notify-20261120-add-the-breakdown-router-create-backend-] ---

# --- 27B-decomposed from roadmap [2026-11-20]: Wire the breakdown router - in `backend/app/main.py` import `breakdown` in the `from app.r (review + tweak) [feat:shrike-notify-20261120-wire-the-breakdown-router-in-backend-app] ---
- [ ] [T3] backend/app/main.py — Import `breakdown` in the `from app.routers import ...` line and add `app.include_router(breakdown.router)` after `app.include_router(messages.router)`. VERIFY: `cd backend && python3 -c "from app.main import app; assert any('/ops/breakdown' in r.path for r in app.routes)"`. (cat:python; multifile:no) [feat:shrike-notify-20261120-wire-the-breakdown-router-in-backend-app]
- [ ] [T1] backend/tests/test_breakdown_wired.py — Create the test file with a fixture that patches `app.routers.breakdown.broker.history` to return `[]` and a test asserting `GET /ops/breakdown` returns 200 with `total == 0`. VERIFY: `cd backend && python3 -m pytest tests/test_breakdown_wired.py::test_ops_breakdown_total_zero -q`. (cat:test; multifile:no) [feat:shrike-notify-20261120-wire-the-breakdown-router-in-backend-app]
- [ ] [T1] backend/tests/test_breakdown_wired.py — Add a test asserting that `/{topic}/breakdown` is a key in the `/openapi.json` paths response. VERIFY: `cd backend && python3 -m pytest tests/test_breakdown_wired.py::test_openapi_has_topic_breakdown -q`. (cat:test; multifile:no) [feat:shrike-notify-20261120-wire-the-breakdown-router-in-backend-app]

# --- 27B-decomposed from roadmap [2026-11-20]: Document the breakdown - create `docs/BREAKDOWN.md` (title `# Priority and severity breakd (review + tweak) [feat:shrike-notify-20261120-document-the-breakdown-create-docs-break] ---
- [ ] [T1] backend/app/models.py — Ensure `PRIORITY_LEVELS` is a public iterable of strings containing the canonical priority names for the breakdown documentation. VERIFY: `cd backend && python3 -c "from app.models import PRIORITY_LEVELS; assert isinstance(PRIORITY_LEVELS, (list, tuple, set)) and all(isinstance(p, str) for p in PRIORITY_LEVELS)"`. (cat:schema; multifile:no) [feat:shrike-notify-20261120-document-the-breakdown-create-docs-break]
- [ ] [T2] docs/BREAKDOWN.md — Create the file with title `# Priority and severity breakdown`, stating `GET /{topic}/breakdown` is read-only, listing every name from `PRIORITY_LEVELS`, and stating that messages without a severity are counted under `unset`. VERIFY: `test -f docs/BREAKDOWN.md && grep -q "# Priority and severity breakdown" docs/BREAKDOWN.md && grep -q "GET /{topic}/breakdown" docs/BREAKDOWN.md && grep -q "unset" docs/BREAKDOWN.md`. (cat:docs; multifile:no) [feat:shrike-notify-20261120-document-the-breakdown-create-docs-break]
- [ ] [T3] backend/tests/test_breakdown_doc.py — Create the test file that resolves `Path(__file__).resolve().parents[2] / 'docs' / 'BREAKDOWN.md'`, reads its content, and asserts the presence of every priority name from `app.models.PRIORITY_LEVELS`, the text `unset`, and the route text `/{topic}/breakdown`. VERIFY: `cd backend && python3 -m pytest tests/test_breakdown_doc.py -q`. (cat:test; multifile:no) [feat:shrike-notify-20261120-document-the-breakdown-create-docs-break]

# --- 27B-decomposed from roadmap [2026-11-20]: Add the message size helper - create `backend/app/utils/size_report.py` with `message_byte (review + tweak) [feat:shrike-notify-20261120-add-the-message-size-helper-create-backe] ---
- [ ] [T1] backend/app/utils/size_report.py — Add `message_bytes(message: Message) -> int` function that returns the sum of UTF-8 encoded lengths of `message.title` and `message.body`, importing `Message` from `app.models`. VERIFY: `cd backend && python3 -c "from app.utils.size_report import message_bytes; print('ok')"`. (cat:python; multifile:no) [feat:shrike-notify-20261120-add-the-message-size-helper-create-backe]
- [ ] [T1] backend/tests/test_size_message_bytes.py — Create test file with `test_ascii_title_and_body` asserting `message_bytes` returns correct byte count for ASCII strings. VERIFY: `cd backend && python3 -m pytest tests/test_size_message_bytes.py::test_ascii_title_and_body -q`. (cat:test; multifile:no) [feat:shrike-notify-20261120-add-the-message-size-helper-create-backe]
- [ ] [T1] backend/tests/test_size_message_bytes.py — Add `test_multibyte_characters_count_their_utf8_bytes` asserting a body containing `é` counts as 2 bytes in the total. VERIFY: `cd backend && python3 -m pytest tests/test_size_message_bytes.py::test_multibyte_characters_count_their_utf8_bytes -q`. (cat:test; multifile:no) [feat:shrike-notify-20261120-add-the-message-size-helper-create-backe]
- [ ] [T1] backend/tests/test_size_message_bytes.py — Add `test_empty_title_counts_only_the_body` asserting empty title results in byte count equal to body length only. VERIFY: `cd backend && python3 -m pytest tests/test_size_message_bytes.py::test_empty_title_counts_only_the_body -q`. (cat:test; multifile:no) [feat:shrike-notify-20261120-add-the-message-size-helper-create-backe]

# --- 27B-decomposed from roadmap [2026-11-20]: Add the size summary helper - in `backend/app/utils/size_report.py` add `size_summary(mess (review + tweak) [feat:shrike-notify-20261120-add-the-size-summary-helper-in-backend-a] ---
- [ ] [T1] backend/app/utils/size_report.py — Add `size_summary(messages: list[Message]) -> dict` handling empty input and computing count, total_bytes, average_bytes, largest_id (earliest on tie), and largest_bytes. VERIFY: `cd backend && python3 -c "from app.utils.size_report import size_summary; print(size_summary([]))"`. (cat:python; multifile:no) [feat:shrike-notify-20261120-add-the-size-summary-helper-in-backend-a]
- [ ] [T1] backend/app/utils/size_report.py — Ensure `size_summary` correctly iterates to find the earliest largest message and handles rounding for average_bytes. VERIFY: `cd backend && python3 -m pytest tests/test_size_summary.py -q`. (cat:python; multifile:no) [feat:shrike-notify-20261120-add-the-size-summary-helper-in-backend-a]
- [ ] [T2] backend/tests/test_size_summary.py — Add `test_empty_input_gives_zero_summary` asserting the exact zero-state dict for an empty list. VERIFY: `cd backend && python3 -m pytest tests/test_size_summary.py::test_empty_input_gives_zero_summary -q`. (cat:test; multifile:no) [feat:shrike-notify-20261120-add-the-size-summary-helper-in-backend-a]
- [ ] [T2] backend/tests/test_size_summary.py — Add `test_totals_and_average` verifying count, total_bytes, and average_bytes calculation for a non-empty list. VERIFY: `cd backend && python3 -m pytest tests/test_size_summary.py::test_totals_and_average -q`. (cat:test; multifile:no) [feat:shrike-notify-20261120-add-the-size-summary-helper-in-backend-a]
- [ ] [T2] backend/tests/test_size_summary.py — Add `test_largest_message_is_reported` verifying largest_id and largest_bytes for a list with a distinct maximum. VERIFY: `cd backend && python3 -m pytest tests/test_size_summary.py::test_largest_message_is_reported -q`. (cat:test; multifile:no) [feat:shrike-notify-20261120-add-the-size-summary-helper-in-backend-a]
- [ ] [T2] backend/tests/test_size_summary.py — Add `test_tie_reports_the_earliest_message` verifying that on a size tie, the earliest message ID is returned. VERIFY: `cd backend && python3 -m pytest tests/test_size_summary.py::test_tie_reports_the_earliest_message -q`. (cat:test; multifile:no) [feat:shrike-notify-20261120-add-the-size-summary-helper-in-backend-a]

# --- 27B-decomposed from roadmap [2026-11-20]: Add the size histogram helper - in `backend/app/utils/size_report.py` add `size_buckets(me (review + tweak) [feat:shrike-notify-20261120-add-the-size-histogram-helper-in-backend] ---
- [ ] [T1] backend/app/utils/size_report.py — Add `size_buckets` function that maps message bytes to bucket keys based on edges tuple VERIFY: `cd backend && python3 -c "from app.utils.size_report import size_buckets; print(size_buckets([]))"` (cat:python; multifile:no) [feat:shrike-notify-20261120-add-the-size-histogram-helper-in-backend]
- [ ] [T2] backend/tests/test_size_buckets.py — Add `test_keys_follow_the_edges` asserting returned dict keys match expected bucket labels for default edges VERIFY: `cd backend && python3 -m pytest tests/test_size_buckets.py::test_keys_follow_the_edges -q` (cat:test; multifile:no) [feat:shrike-notify-20261120-add-the-size-histogram-helper-in-backend]
- [ ] [T3] backend/tests/test_size_buckets.py — Add `test_message_on_an_edge_lands_in_that_bucket` verifying a 256-byte message increments the `<=256` bucket VERIFY: `cd backend && python3 -m pytest tests/test_size_buckets.py::test_message_on_an_edge_lands_in_that_bucket -q` (cat:test; multifile:no) [feat:shrike-notify-20261120-add-the-size-histogram-helper-in-backend]
- [ ] [T4] backend/tests/test_size_buckets.py — Add `test_larger_than_every_edge_lands_in_the_last_bucket` verifying a 5000-byte message increments the `>4096` bucket VERIFY: `cd backend && python3 -m pytest tests/test_size_buckets.py::test_larger_than_every_edge_lands_in_the_last_bucket -q` (cat:test; multifile:no) [feat:shrike-notify-20261120-add-the-size-histogram-helper-in-backend]
- [ ] [T5] backend/tests/test_size_buckets.py — Add `test_empty_input_gives_all_zero_buckets` verifying empty list returns all buckets with value 0 VERIFY: `cd backend && python3 -m pytest tests/test_size_buckets.py::test_empty_input_gives_all_zero_buckets -q` (cat:test; multifile:no) [feat:shrike-notify-20261120-add-the-size-histogram-helper-in-backend]

# --- 27B-decomposed from roadmap [2026-11-20]: Add the sizes router - create `backend/app/routers/sizes.py` with `router = APIRouter(tags (review + tweak) [feat:shrike-notify-20261120-add-the-sizes-router-create-backend-app-] ---
- [ ] [T1] backend/tests/test_sizes_utils.py — Add test file importing `size_summary` and `size_buckets` from `app.utils.sizes`, asserting correct counts, byte sums, and bucket distribution for sample message objects. VERIFY: `cd backend && python3 -m pytest tests/test_sizes_utils.py -q`. (cat:test; multifile:no) [feat:shrike-notify-20261120-add-the-sizes-router-create-backend-app-]
- [ ] [T2] backend/app/routers/sizes.py — Create file with `router = APIRouter(tags=["messages"])` and `GET /{topic}/sizes` endpoint using `Depends(require_topic_and_auth)` and `broker.history(topic, limit=None)`, returning JSON with topic, size summary, and buckets. VERIFY: `cd backend && python3 -c "from app.routers.sizes import router; print(router.tags)"`. (cat:endpoint; multifile:no) [feat:shrike-notify-20261120-add-the-sizes-router-create-backend-app-]
- [ ] [T3] backend/app/routers/__init__.py — Import `sizes` router and include it in the main router aggregation to expose the new endpoint. VERIFY: `cd backend && python3 -c "from app.main import app; print(any('sizes' in r.path for r in app.routes))"`. (cat:refactor; multifile:no) [feat:shrike-notify-20261120-add-the-sizes-router-create-backend-app-]
- [ ] [T2] backend/tests/test_sizes_router.py — Create test file mounting the sizes router on a local FastAPI instance, mocking `broker.history` to return two messages with bodies 'abc' and 'abcdef', asserting response fields `count==2`, `total_bytes==9`, `largest_bytes==6`, `buckets['<=256']==2`. VERIFY: `cd backend && python3 -m pytest tests/test_sizes_router.py -q`. (cat:test; multifile:no) [feat:shrike-notify-20261120-add-the-sizes-router-create-backend-app-]
- [ ] [T2] backend/tests/test_sizes_router.py — Add test case in the same file asserting that requesting `/bad$topic/sizes` returns status code 422. VERIFY: `cd backend && python3 -m pytest tests/test_sizes_router.py -q`. (cat:test; multifile:no) [feat:shrike-notify-20261120-add-the-sizes-router-create-backend-app-]

# --- 27B-decomposed from roadmap [2026-11-21]: Wire the sizes router - in `backend/app/main.py` import `sizes` in the `from app.routers i (review + tweak) [feat:shrike-notify-20261121-wire-the-sizes-router-in-backend-app-mai] ---
- [ ] [T1] backend/app/routers/sizes.py — Create the `sizes` router module with a `router = APIRouter(prefix="/ops", tags=["sizes"])` and a `GET /sizes` endpoint that calls `broker.history()` and returns `{"count": len(history)}`. VERIFY: `cd backend && python3 -c "from app.routers.sizes import router; print(router.prefix)"`. (cat:python; multifile:no) [feat:shrike-notify-20261121-wire-the-sizes-router-in-backend-app-mai]
- [ ] [T1] backend/app/routers/sizes.py — Add a `GET /{topic}/sizes` endpoint to the existing `router` in `backend/app/routers/sizes.py` that returns a placeholder list for the given topic. VERIFY: `cd backend && python3 -c "from app.routers.sizes import router; print([r.path for r in router.routes])"`. (cat:python; multifile:no) [feat:shrike-notify-20261121-wire-the-sizes-router-in-backend-app-mai]
- [ ] [T3] backend/app/main.py — Modify the `from app.routers import ...` line to include `sizes` and add `app.include_router(sizes.router)` immediately after `app.include_router(messages.router)`. VERIFY: `cd backend && python3 -m pytest tests/test_sizes_wired.py -q`. (cat:python; multifile:no) [feat:shrike-notify-20261121-wire-the-sizes-router-in-backend-app-mai]
- [ ] [T2] backend/tests/test_sizes_wired.py — Create a new test file that imports `app` from `backend.app.main`, uses `TestClient`, patches `app.routers.sizes.broker.history` to return `[]`, and asserts `GET /ops/sizes` returns 200 with `count == 0`. VERIFY: `cd backend && python3 -m pytest tests/test_sizes_wired.py -q`. (cat:test; multifile:no) [feat:shrike-notify-20261121-wire-the-sizes-router-in-backend-app-mai]
- [ ] [T2] backend/tests/test_sizes_wired.py — Add a test case to `backend/tests/test_sizes_wired.py` that fetches `/openapi.json` and asserts `"/ops/{topic}/sizes"` is present in the `paths` dictionary. VERIFY: `cd backend && python3 -m pytest tests/test_sizes_wired.py -q`. (cat:test; multifile:no) [feat:shrike-notify-20261121-wire-the-sizes-router-in-backend-app-mai]

# --- 27B-decomposed from roadmap [2026-11-21]: Add the time-to-expiry helper - create `backend/app/utils/expiry.py` with `seconds_until_e (review + tweak) [feat:shrike-notify-20261121-add-the-time-to-expiry-helper-create-bac] ---
- [ ] [T1] backend/app/utils/expiry.py — Add `seconds_until_expiry(created_at: float, ttl_seconds: float, now: float) -> float | None` returning `None` if `ttl_seconds <= 0` else `max(0.0, created_at + ttl_seconds - now)` VERIFY: `cd backend && python3 -c "from app.utils.expiry import seconds_until_expiry; assert seconds_until_expiry(100, 0, 200) is None; assert seconds_until_expiry(100, 50, 120) == 30.0; assert seconds_until_expiry(100, 50, 200) == 0.0"`. (cat:python; multifile:no) [feat:shrike-notify-20261121-add-the-time-to-expiry-helper-create-bac]
- [ ] [T2] backend/tests/test_expiry_seconds_until.py — Add `test_non_positive_ttl_never_expires` asserting `seconds_until_expiry` returns `None` for `ttl_seconds=0` and `ttl_seconds=-1` VERIFY: `cd backend && python3 -m pytest tests/test_expiry_seconds_until.py::test_non_positive_ttl_never_expires -q`. (cat:test; multifile:no) [feat:shrike-notify-20261121-add-the-time-to-expiry-helper-create-bac]
- [ ] [T2] backend/tests/test_expiry_seconds_until.py — Add `test_remaining_time_is_created_plus_ttl_minus_now` asserting correct positive float calculation for valid inputs VERIFY: `cd backend && python3 -m pytest tests/test_expiry_seconds_until.py::test_remaining_time_is_created_plus_ttl_minus_now -q`. (cat:test; multifile:no) [feat:shrike-notify-20261121-add-the-time-to-expiry-helper-create-bac]
- [ ] [T2] backend/tests/test_expiry_seconds_until.py — Add `test_already_expired_is_zero_not_negative` asserting `0.0` is returned when `now > created_at + ttl_seconds` VERIFY: `cd backend && python3 -m pytest tests/test_expiry_seconds_until.py::test_already_expired_is_zero_not_negative -q`. (cat:test; multifile:no) [feat:shrike-notify-20261121-add-the-time-to-expiry-helper-create-bac]

# --- 27B-decomposed from roadmap [2026-11-21]: Add the expiry summary helper - in `backend/app/utils/expiry.py` add `expiry_summary(creat (review + tweak) [feat:shrike-notify-20261121-add-the-expiry-summary-helper-in-backend] ---
- [ ] [T1] backend/app/utils/expiry.py — Add `expiry_summary` function handling `ttl_seconds <= 0` case returning zeros and None for next expiry. VERIFY: `cd backend && python3 -c "from app.utils.expiry import expiry_summary; assert expiry_summary([], 0, 0) == {'ttl_seconds': 0, 'never_expires': True, 'expired': 0, 'expiring_within_hour': 0, 'next_expiry_seconds': None}"`. (cat:python; multifile:no) [feat:shrike-notify-20261121-add-the-expiry-summary-helper-in-backend]
- [ ] [T1] backend/app/utils/expiry.py — Extend `expiry_summary` to calculate counts for expired and expiring_within_hour based on remaining time. VERIFY: `cd backend && python3 -c "from app.utils.expiry import expiry_summary; now=10000; r=expiry_summary([now-4000, now-1800, now-10], 3600, now); assert r['expired']==1 and r['expiring_within_hour']==1"`. (cat:python; multifile:no) [feat:shrike-notify-20261121-add-the-expiry-summary-helper-in-backend]
- [ ] [T1] backend/app/utils/expiry.py — Extend `expiry_summary` to calculate `next_expiry_seconds` as the smallest remaining time above 0. VERIFY: `cd backend && python3 -c "from app.utils.expiry import expiry_summary; now=10000; r=expiry_summary([now-4000, now-1800, now-10], 3600, now); assert r['next_expiry_seconds']==10"`. (cat:python; multifile:no) [feat:shrike-notify-20261121-add-the-expiry-summary-helper-in-backend]
- [ ] [T2] backend/tests/test_expiry_summary.py — Create test file with `test_counts_expired_and_soon_to_expire` verifying counts for mixed expiry states. VERIFY: `cd backend && python3 -m pytest tests/test_expiry_summary.py::test_counts_expired_and_soon_to_expire -q`. (cat:test; multifile:no) [feat:shrike-notify-20261121-add-the-expiry-summary-helper-in-backend]
- [ ] [T2] backend/tests/test_expiry_summary.py — Add `test_next_expiry_is_the_smallest_remaining` verifying the minimum positive remaining time is returned. VERIFY: `cd backend && python3 -m pytest tests/test_expiry_summary.py::test_next_expiry_is_the_smallest_remaining -q`. (cat:test; multifile:no) [feat:shrike-notify-20261121-add-the-expiry-summary-helper-in-backend]
- [ ] [T2] backend/tests/test_expiry_summary.py — Add `test_no_ttl_reports_never_expires` verifying behavior when `ttl_seconds <= 0`. VERIFY: `cd backend && python3 -m pytest tests/test_expiry_summary.py::test_no_ttl_reports_never_expires -q`. (cat:test; multifile:no) [feat:shrike-notify-20261121-add-the-expiry-summary-helper-in-backend]
- [ ] [T2] backend/tests/test_expiry_summary.py — Add `test_empty_list_has_no_next_expiry` verifying `next_expiry_seconds` is None for empty input. VERIFY: `cd backend && python3 -m pytest tests/test_expiry_summary.py::test_empty_list_has_no_next_expiry -q`. (cat:test; multifile:no) [feat:shrike-notify-20261121-add-the-expiry-summary-helper-in-backend]

# --- 27B-decomposed from roadmap [2026-11-21]: Add the expiry router - create `backend/app/routers/expiry.py` with `router = APIRouter(ta (review + tweak) [feat:shrike-notify-20261121-add-the-expiry-router-create-backend-app] ---
- [ ] [T2] backend/app/routers/expiry.py — Define `router = APIRouter(tags=["messages"])` and the endpoint `GET /{topic}/expiry` with `topic: str = Depends(require_topic_and_auth)` that calls `broker.history(topic, limit=None)` and returns the expiry summary dict using `get_settings().message_ttl_seconds`. VERIFY: `cd backend && python3 -c "from app.routers.expiry import router; assert any(r.path == '/{topic}/expiry' for r in router.routes)"`. (cat:python; multifile:no) [feat:shrike-notify-20261121-add-the-expiry-router-create-backend-app]
- [ ] [T1] backend/app/routers/expiry.py — Add module-level imports for `get_settings` from `app.config`, `broker` from `app.services.broker`, `APIRouter` from `fastapi`, and `Depends` from `fastapi`. VERIFY: `cd backend && python3 -c "from app.routers.expiry import router, get_settings, broker"`. (cat:python; multifile:no) [feat:shrike-notify-20261121-add-the-expiry-router-create-backend-app]
- [ ] [T3] backend/app/routers/expiry.py — Add `responses={401: {"description": "Unauthorized"}, 422: {"description": "Invalid topic name"}}` to the `@router.get` decorator for the expiry endpoint. VERIFY: `cd backend && python3 -c "from app.routers.expiry import router; r = [r for r in router.routes if r.path == '/{topic}/expiry'][0]; assert r.responses.get(401, {}).get('description') == 'Unauthorized' and r.responses.get(422, {}).get('description') == 'Invalid topic name'"`. (cat:python; multifile:no) [feat:shrike-notify-20261121-add-the-expiry-router-create-backend-app]
- [ ] [T4] backend/tests/test_expiry_router.py — Create test file that mounts the expiry router on a local `FastAPI()` instance and patches `broker.history` with an `AsyncMock` returning a single `Message` created at `time.time()`. VERIFY: `cd backend && python3 -m pytest tests/test_expiry_router.py::test_expiry_router_mounted -q`. (cat:test; multifile:no) [feat:shrike-notify-20261121-add-the-expiry-router-create-backend-app]
- [ ] [T5] backend/tests/test_expiry_router.py — Add test case that patches `app.routers.expiry.get_settings` to return an object with `message_ttl_seconds=7200.0`, asserts response JSON has `expired == 0`, `expiring_within_hour == 0`, and `next_expiry_seconds > 7100`. VERIFY: `cd backend && python3 -m pytest tests/test_expiry_router.py::test_expiry_summary_values -q`. (cat:test; multifile:no) [feat:shrike-notify-20261121-add-the-expiry-router-create-backend-app]

# --- 27B-decomposed from roadmap [2026-11-21]: Wire the expiry router - in `backend/app/main.py` import `expiry` in the `from app.routers (review + tweak) [feat:shrike-notify-20261121-wire-the-expiry-router-in-backend-app-ma] ---
- [ ] [T2] backend/app/routers/expiry.py — Add a `GET /{topic}/expiry` endpoint to the router that returns 404 if topic is not in `broker.history()` else 200 with topic details. VERIFY: `cd backend && python3 -c "from app.routers import expiry; routes = [r.path for r in expiry.router.routes]; assert '/ops/{topic}/expiry' in routes"`. (cat:python; multifile:no) [feat:shrike-notify-20261121-wire-the-expiry-router-in-backend-app-ma]
- [ ] [T1] backend/app/routers/expiry.py — Create the router module with `router = APIRouter(prefix="/ops", tags=["expiry"])` and a `GET /expiry` endpoint that calls `broker.history()` and returns `{"expired": len(history)}`. VERIFY: `cd backend && python3 -c "from app.routers import expiry; assert hasattr(expiry, 'router')"`. (cat:python; multifile:no) [feat:shrike-notify-20261121-wire-the-expiry-router-in-backend-app-ma]
- [ ] [T3] backend/app/main.py — Import `expiry` in the `from app.routers import ...` line and add `app.include_router(expiry.router)` immediately after `app.include_router(messages.router)`. VERIFY: `cd backend && python3 -c "from app.main import app; paths = [r.path for r in app.routes]; assert '/ops/expiry' in paths"`. (cat:python; multifile:no) [feat:shrike-notify-20261121-wire-the-expiry-router-in-backend-app-ma]
- [ ] [T4] backend/tests/test_expiry_wired.py — Create test file with `TestClient(app)` fixture, patch `app.routers.expiry.broker.history` to return `[]`, and assert `GET /ops/expiry` returns 200 with `{"expired": 0}`. VERIFY: `cd backend && python3 -m pytest tests/test_expiry_wired.py::test_get_ops_expiry_returns_zero -q`. (cat:test; multifile:no) [feat:shrike-notify-20261121-wire-the-expiry-router-in-backend-app-ma]
- [ ] [T5] backend/tests/test_expiry_wired.py — Add test case asserting that `/{topic}/expiry` path pattern exists in the OpenAPI spec paths dictionary. VERIFY: `cd backend && python3 -m pytest tests/test_expiry_wired.py::test_openapi_contains_topic_expiry_path -q`. (cat:test; multifile:no) [feat:shrike-notify-20261121-wire-the-expiry-router-in-backend-app-ma]

# --- 27B-decomposed from roadmap [2026-11-21]: Document the expiry report - create `docs/EXPIRY.md` (title `# Message expiry`) naming the (review + tweak) [feat:shrike-notify-20261121-document-the-expiry-report-create-docs-e] ---
- [ ] [T1] backend/app/services/ttl.py — Add `expiry_summary` function returning dict with keys: `topic`, `ttl_seconds`, `legacy_ttl_seconds`, `never_expires`, `endpoint`. VERIFY: `cd backend && python3 -c "from app.services.ttl import expiry_summary; d=expiry_summary([], 3600.0, 0.0); assert set(d.keys()) == {'topic','ttl_seconds','legacy_ttl_seconds','never_expires','endpoint'}"`. (cat:python; multifile:no) [feat:shrike-notify-20261121-document-the-expiry-report-create-docs-e]
- [ ] [T1] docs/EXPIRY.md — Create file with title `# Message expiry`, stating `NOTIFY_TTL_SECONDS` and `NOTIFY_MESSAGE_TTL_SECONDS` (legacy), noting 0 means never expire, naming `GET /{topic}/expiry` as read-only, and listing keys: `topic`, `ttl_seconds`, `legacy_ttl_seconds`, `never_expires`, `endpoint`. VERIFY: `cd backend && python3 -m pytest tests/test_expiry_doc.py -q`. (cat:docs; multifile:no) [feat:shrike-notify-20261121-document-the-expiry-report-create-docs-e]
- [ ] [T2] backend/tests/test_expiry_doc.py — Create test file that imports `expiry_summary`, calls it with `([], 3600.0, 0.0)`, reads `docs/EXPIRY.md` via `Path(__file__).resolve().parents[2] / 'docs' / 'EXPIRY.md'`, and asserts all keys from the result plus `NOTIFY_TTL_SECONDS` and `NOTIFY_MESSAGE_TTL_SECONDS` are in the text. VERIFY: `cd backend && python3 -m pytest tests/test_expiry_doc.py -q`. (cat:test; multifile:no) [feat:shrike-notify-20261121-document-the-expiry-report-create-docs-e]

# --- 27B-decomposed from roadmap [2026-11-21]: Add the duration parser - create `backend/app/utils/duration.py` with `parse_duration(text (review + tweak) [feat:shrike-notify-20261121-add-the-duration-parser-create-backend-a] ---
- [ ] [T1] backend/app/utils/duration.py — Add `parse_duration` function handling single unit parsing for 's', 'm', 'h', 'd' and bare digits, returning float seconds or None for invalid inputs. VERIFY: `cd backend && python3 -c "from app.utils.duration import parse_duration; assert parse_duration('90s') == 90.0; assert parse_duration('15m') == 900.0; assert parse_duration('2h') == 7200.0; assert parse_duration('1d') == 86400.0; assert parse_duration('45') == 45.0"`. (cat:python; multifile:no) [feat:shrike-notify-20261121-add-the-duration-parser-create-backend-a]
- [ ] [T2] backend/app/utils/duration.py — Extend `parse_duration` to handle combined parts (e.g., `1h30m`) by summing values and detecting repeated units, returning None for duplicates or invalid grammar. VERIFY: `cd backend && python3 -c "from app.utils.duration import parse_duration; assert parse_duration('1h30m') == 5400.0; assert parse_duration('1h1h') is None; assert parse_duration('abc') is None; assert parse_duration('-5m') is None; assert parse_duration('1.5h') is None; assert parse_duration('5x') is None; assert parse_duration('') is None"`. (cat:python; multifile:no) [feat:shrike-notify-20261121-add-the-duration-parser-create-backend-a]
- [ ] [T3] backend/tests/test_duration_parse.py — Create test file with `test_single_units`, `test_combined_parts`, `test_bare_digits_are_seconds`, `test_invalid_text_is_none`, and `test_repeated_unit_is_none` covering all specified cases. VERIFY: `cd backend && python3 -m pytest tests/test_duration_parse.py -q`. (cat:test; multifile:no) [feat:shrike-notify-20261121-add-the-duration-parser-create-backend-a]

# --- 27B-decomposed from roadmap [2026-11-21]: Add the duration formatter - in `backend/app/utils/duration.py` add `format_duration(secon (review + tweak) [feat:shrike-notify-20261121-add-the-duration-formatter-in-backend-ap] ---
- [ ] [T1] backend/app/utils/duration.py — Add `format_duration(seconds: float) -> str` that returns "0s" for negative, NaN, or zero inputs, and otherwise formats the two largest non-zero parts among days, hours, minutes, and whole seconds (floored) joined by a single space. VERIFY: `cd backend && python3 -c "from app.utils.duration import format_duration; assert format_duration(45) == '45s'; assert format_duration(0) == '0s'; print('ok')"`. (cat:python; multifile:no) [feat:shrike-notify-20261121-add-the-duration-formatter-in-backend-ap]
- [ ] [T1] backend/tests/test_duration_format.py — Create test file with `test_seconds_only` asserting `format_duration(45)` is `"45s"` and `test_zero_negative_and_nan_give_zero_seconds` asserting `format_duration(0)`, `format_duration(-1)`, and `format_duration(float('nan'))` all return `"0s"`. VERIFY: `cd backend && python3 -m pytest tests/test_duration_format.py::test_seconds_only tests/test_duration_format.py::test_zero_negative_and_nan_give_zero_seconds -q`. (cat:test; multifile:no) [feat:shrike-notify-20261121-add-the-duration-formatter-in-backend-ap]
- [ ] [T1] backend/tests/test_duration_format.py — Add `test_minutes_have_no_seconds_part_when_zero` asserting `format_duration(300)` is `"5m"` and `test_hours_and_minutes` asserting `format_duration(5400)` is `"1h 30m"`. VERIFY: `cd backend && python3 -m pytest tests/test_duration_format.py::test_minutes_have_no_seconds_part_when_zero tests/test_duration_format.py::test_hours_and_minutes -q`. (cat:test; multifile:no) [feat:shrike-notify-20261121-add-the-duration-formatter-in-backend-ap]
- [ ] [T1] backend/tests/test_duration_format.py — Add `test_days_and_hours` asserting `format_duration(183600)` is `"2d 3h"` and `test_only_two_parts_are_shown` asserting `format_duration(90061)` is `"1d 1h"`. VERIFY: `cd backend && python3 -m pytest tests/test_duration_format.py::test_days_and_hours tests/test_duration_format.py::test_only_two_parts_are_shown -q`. (cat:test; multifile:no) [feat:shrike-notify-20261121-add-the-duration-formatter-in-backend-ap]
- [ ] [T2] backend/tests/test_duration_format.py — Add edge case assertions for single-part outputs: `format_duration(3600)` is `"1h"` and `format_duration(172800)` is `"2d"`. VERIFY: `cd backend && python3 -m pytest tests/test_duration_format.py -q`. (cat:test; multifile:no) [feat:shrike-notify-20261121-add-the-duration-formatter-in-backend-ap]

# --- 27B-decomposed from roadmap [2026-11-21]: Add the age and lifetime phrases - in `backend/app/utils/duration.py` add `age_text(create (review + tweak) [feat:shrike-notify-20261121-add-the-age-and-lifetime-phrases-in-back] ---
- [ ] [T1] backend/app/utils/duration.py — Add `age_text(created_at: float, now: float) -> str` returning `just now` if `now - created_at < 5` or `created_at > now`, else `f"{format_duration(now - created_at)} ago"` VERIFY: `cd backend && python3 -c "from app.utils.duration import age_text; assert age_text(10, 12) == 'just now'; assert age_text(20, 10) == 'just now'; assert age_text(0, 5400) == '1h 30m ago'"`. (cat:python; multifile:no) [feat:shrike-notify-20261121-add-the-age-and-lifetime-phrases-in-back]
- [ ] [T1] backend/app/utils/duration.py — Add `describe_ttl(ttl_seconds: float) -> str` returning `never` if `ttl_seconds <= 0`, else `format_duration(ttl_seconds)` VERIFY: `cd backend && python3 -c "from app.utils.duration import describe_ttl; assert describe_ttl(0) == 'never'; assert describe_ttl(-1) == 'never'; assert describe_ttl(3600) == '1h'"`. (cat:python; multifile:no) [feat:shrike-notify-20261121-add-the-age-and-lifetime-phrases-in-back]
- [ ] [T2] backend/tests/test_duration_phrases.py — Create file with `test_recent_message_is_just_now` asserting `age_text(10, 14)` is `just now` VERIFY: `cd backend && python3 -m pytest tests/test_duration_phrases.py::test_recent_message_is_just_now -q`. (cat:test; multifile:no) [feat:shrike-notify-20261121-add-the-age-and-lifetime-phrases-in-back]
- [ ] [T2] backend/tests/test_duration_phrases.py — Add `test_future_timestamp_is_just_now` asserting `age_text(100, 50)` is `just now` VERIFY: `cd backend && python3 -m pytest tests/test_duration_phrases.py::test_future_timestamp_is_just_now -q`. (cat:test; multifile:no) [feat:shrike-notify-20261121-add-the-age-and-lifetime-phrases-in-back]
- [ ] [T2] backend/tests/test_duration_phrases.py — Add `test_older_message_has_ago_suffix` asserting `age_text(0, 5400)` is `1h 30m ago` VERIFY: `cd backend && python3 -m pytest tests/test_duration_phrases.py::test_older_message_has_ago_suffix -q`. (cat:test; multifile:no) [feat:shrike-notify-20261121-add-the-age-and-lifetime-phrases-in-back]
- [ ] [T2] backend/tests/test_duration_phrases.py — Add `test_zero_ttl_is_never` asserting `describe_ttl(0)` is `never` VERIFY: `cd backend && python3 -m pytest tests/test_duration_phrases.py::test_zero_ttl_is_never -q`. (cat:test; multifile:no) [feat:shrike-notify-20261121-add-the-age-and-lifetime-phrases-in-back]
- [ ] [T2] backend/tests/test_duration_phrases.py — Add `test_ttl_uses_the_formatter` asserting `describe_ttl(3600)` is `1h` VERIFY: `cd backend && python3 -m pytest tests/test_duration_phrases.py::test_ttl_uses_the_formatter -q`. (cat:test; multifile:no) [feat:shrike-notify-20261121-add-the-age-and-lifetime-phrases-in-back]

# --- 27B-decomposed from roadmap [2026-11-21]: Document the duration helpers - create `docs/DURATIONS.md` (title `# Duration text`) with  (review + tweak) [feat:shrike-notify-20261121-document-the-duration-helpers-create-doc] ---
- [ ] [T1] backend/app/utils/duration.py — Add `parse_duration(text: str) -> int` and `format_duration(seconds: int) -> str` functions handling units s, m, h, d with space-separated output for formatting. VERIFY: `cd backend && python3 -c "from app.utils.duration import parse_duration, format_duration; assert parse_duration('1h30m') == 5400; assert format_duration(5400) == '1h 30m'; assert format_duration(3600) == '1h'"`. (cat:python; multifile:no) [feat:shrike-notify-20261121-document-the-duration-helpers-create-doc]
- [ ] [T2] docs/DURATIONS.md — Create file with title `# Duration text`, section `## Parsing` listing units `s, m, h, d` and example `1h30m` = 5400, section `## Formatting` showing `5400` as `1h 30m` and `3600` as `1h`. VERIFY: `grep -q "# Duration text" docs/DURATIONS.md && grep -q "## Parsing" docs/DURATIONS.md && grep -q "## Formatting" docs/DURATIONS.md && grep -q "5400" docs/DURATIONS.md && grep -q "1h 30m" docs/DURATIONS.md`. (cat:docs; multifile:no) [feat:shrike-notify-20261121-document-the-duration-helpers-create-doc]
- [ ] [T3] backend/tests/test_duration_doc.py — Create test file that reads `Path(__file__).resolve().parents[2] / 'docs' / 'DURATIONS.md'`, asserts headings exist, imports `parse_duration` and `format_duration`, and asserts `parse_duration('1h30m') == 5400` and `format_duration(5400) == '1h 30m'` match doc content. VERIFY: `cd backend && python3 -m pytest tests/test_duration_doc.py -q`. (cat:test; multifile:no) [feat:shrike-notify-20261121-document-the-duration-helpers-create-doc]

# --- 27B-decomposed from roadmap [2026-11-21]: Add the shortcode table and lookup - create `backend/app/utils/tag_emoji.py` with `EMOJI_S (review + tweak) [feat:shrike-notify-20261121-add-the-shortcode-table-and-lookup-creat] ---
- [ ] [T1] backend/app/utils/tag_emoji.py — Add `EMOJI_SHORTCODES: dict[str, str]` with the 8 specified keys and values. VERIFY: `cd backend && python3 -c "from app.utils.tag_emoji import EMOJI_SHORTCODES; assert len(EMOJI_SHORTCODES) == 8"`. (cat:python; multifile:no) [feat:shrike-notify-20261121-add-the-shortcode-table-and-lookup-creat]
- [ ] [T1] backend/app/utils/tag_emoji.py — Add `emoji_for_tag(tag: str) -> str | None` that strips, lowercases, removes one leading/trailing `:`, and returns the table value or `None`. VERIFY: `cd backend && python3 -c "from app.utils.tag_emoji import emoji_for_tag; assert emoji_for_tag('fire') == '\U0001f525' and emoji_for_tag(':Fire:') == '\U0001f525' and emoji_for_tag('unknown') is None"`. (cat:python; multifile:no) [feat:shrike-notify-20261121-add-the-shortcode-table-and-lookup-creat]
- [ ] [T2] backend/tests/test_tag_emoji_lookup.py — Add `test_table_has_exactly_the_eight_shortcodes` asserting the dict has exactly 8 keys matching the expected set. VERIFY: `cd backend && python3 -m pytest tests/test_tag_emoji_lookup.py::test_table_has_exactly_the_eight_shortcodes -q`. (cat:test; multifile:no) [feat:shrike-notify-20261121-add-the-shortcode-table-and-lookup-creat]
- [ ] [T2] backend/tests/test_tag_emoji_lookup.py — Add `test_known_shortcode_maps_to_emoji` asserting specific mappings like `warning` -> `"⚠️"` and `bug` -> `"\U0001f41b"`. VERIFY: `cd backend && python3 -m pytest tests/test_tag_emoji_lookup.py::test_known_shortcode_maps_to_emoji -q`. (cat:test; multifile:no) [feat:shrike-notify-20261121-add-the-shortcode-table-and-lookup-creat]
- [ ] [T2] backend/tests/test_tag_emoji_lookup.py — Add `test_case_and_colons_are_ignored` asserting `:Fire:` maps to the same value as `fire`. VERIFY: `cd backend && python3 -m pytest tests/test_tag_emoji_lookup.py::test_case_and_colons_are_ignored -q`. (cat:test; multifile:no) [feat:shrike-notify-20261121-add-the-shortcode-table-and-lookup-creat]
- [ ] [T2] backend/tests/test_tag_emoji_lookup.py — Add `test_unknown_tag_is_none` asserting `emoji_for_tag("nonexistent")` returns `None`. VERIFY: `cd backend && python3 -m pytest tests/test_tag_emoji_lookup.py::test_unknown_tag_is_none -q`. (cat:test; multifile:no) [feat:shrike-notify-20261121-add-the-shortcode-table-and-lookup-creat]
