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

# --- 27B-decomposed from roadmap [2026-11-20]: Document the breakdown - create `docs/BREAKDOWN.md` (title `# Priority and severity breakd (review + tweak) [feat:shrike-notify-20261120-document-the-breakdown-create-docs-break] ---

# --- 27B-decomposed from roadmap [2026-11-20]: Add the message size helper - create `backend/app/utils/size_report.py` with `message_byte (review + tweak) [feat:shrike-notify-20261120-add-the-message-size-helper-create-backe] ---

# --- 27B-decomposed from roadmap [2026-11-20]: Add the size summary helper - in `backend/app/utils/size_report.py` add `size_summary(mess (review + tweak) [feat:shrike-notify-20261120-add-the-size-summary-helper-in-backend-a] ---

# --- 27B-decomposed from roadmap [2026-11-20]: Add the size histogram helper - in `backend/app/utils/size_report.py` add `size_buckets(me (review + tweak) [feat:shrike-notify-20261120-add-the-size-histogram-helper-in-backend] ---

# --- 27B-decomposed from roadmap [2026-11-20]: Add the sizes router - create `backend/app/routers/sizes.py` with `router = APIRouter(tags (review + tweak) [feat:shrike-notify-20261120-add-the-sizes-router-create-backend-app-] ---

# --- 27B-decomposed from roadmap [2026-11-21]: Wire the sizes router - in `backend/app/main.py` import `sizes` in the `from app.routers i (review + tweak) [feat:shrike-notify-20261121-wire-the-sizes-router-in-backend-app-mai] ---

# --- 27B-decomposed from roadmap [2026-11-21]: Add the time-to-expiry helper - create `backend/app/utils/expiry.py` with `seconds_until_e (review + tweak) [feat:shrike-notify-20261121-add-the-time-to-expiry-helper-create-bac] ---

# --- 27B-decomposed from roadmap [2026-11-21]: Add the expiry summary helper - in `backend/app/utils/expiry.py` add `expiry_summary(creat (review + tweak) [feat:shrike-notify-20261121-add-the-expiry-summary-helper-in-backend] ---

# --- 27B-decomposed from roadmap [2026-11-21]: Add the expiry router - create `backend/app/routers/expiry.py` with `router = APIRouter(ta (review + tweak) [feat:shrike-notify-20261121-add-the-expiry-router-create-backend-app] ---

# --- 27B-decomposed from roadmap [2026-11-21]: Wire the expiry router - in `backend/app/main.py` import `expiry` in the `from app.routers (review + tweak) [feat:shrike-notify-20261121-wire-the-expiry-router-in-backend-app-ma] ---

# --- 27B-decomposed from roadmap [2026-11-21]: Document the expiry report - create `docs/EXPIRY.md` (title `# Message expiry`) naming the (review + tweak) [feat:shrike-notify-20261121-document-the-expiry-report-create-docs-e] ---

# --- 27B-decomposed from roadmap [2026-11-21]: Add the duration parser - create `backend/app/utils/duration.py` with `parse_duration(text (review + tweak) [feat:shrike-notify-20261121-add-the-duration-parser-create-backend-a] ---

# --- 27B-decomposed from roadmap [2026-11-21]: Add the duration formatter - in `backend/app/utils/duration.py` add `format_duration(secon (review + tweak) [feat:shrike-notify-20261121-add-the-duration-formatter-in-backend-ap] ---

# --- 27B-decomposed from roadmap [2026-11-21]: Add the age and lifetime phrases - in `backend/app/utils/duration.py` add `age_text(create (review + tweak) [feat:shrike-notify-20261121-add-the-age-and-lifetime-phrases-in-back] ---

# --- 27B-decomposed from roadmap [2026-11-21]: Document the duration helpers - create `docs/DURATIONS.md` (title `# Duration text`) with  (review + tweak) [feat:shrike-notify-20261121-document-the-duration-helpers-create-doc] ---

# --- 27B-decomposed from roadmap [2026-11-21]: Add the shortcode table and lookup - create `backend/app/utils/tag_emoji.py` with `EMOJI_S (review + tweak) [feat:shrike-notify-20261121-add-the-shortcode-table-and-lookup-creat] ---

# --- 27B-decomposed from roadmap [2026-11-21]: Add the tag splitter - in `backend/app/utils/tag_emoji.py` add `split_emoji_tags(tags: lis (review + tweak) [feat:shrike-notify-20261121-add-the-tag-splitter-in-backend-app-util] ---

# --- 27B-decomposed from roadmap [2026-11-21]: Add the title prefix helper - in `backend/app/utils/tag_emoji.py` add `title_with_emoji(ti (review + tweak) [feat:shrike-notify-20261121-add-the-title-prefix-helper-in-backend-a] ---

# --- 27B-decomposed from roadmap [2026-11-21]: Document the shortcodes - create `docs/TAG_EMOJI.md` (title `# Tag emoji shortcodes`) with (review + tweak) [feat:shrike-notify-20261121-document-the-shortcodes-create-docs-tag-] ---

# --- 27B-decomposed from roadmap [2026-11-21]: Add the publish request reference - create `docs/PUBLISH_REQUEST.md` (title `# Publish req (review + tweak) [feat:shrike-notify-20261121-add-the-publish-request-reference-create] ---

# --- 27B-decomposed from roadmap [2026-11-22]: Add the response header reference - create `docs/RESPONSE_HEADERS.md` (title `# Response h (review + tweak) [feat:shrike-notify-20261122-add-the-response-header-reference-create] ---

# --- 27B-decomposed from roadmap [2026-11-22]: Add the latest message helper - create `backend/app/utils/latest.py` with `latest_message( (review + tweak) [feat:shrike-notify-20261122-add-the-latest-message-helper-create-bac] ---

# --- 27B-decomposed from roadmap [2026-11-22]: Add the message summary helper - in `backend/app/utils/latest.py` add `message_summary(mes (review + tweak) [feat:shrike-notify-20261122-add-the-message-summary-helper-in-backen] ---

# --- 27B-decomposed from roadmap [2026-11-22]: Add the age helper - in `backend/app/utils/latest.py` add `age_seconds(created_at: float,  (review + tweak) [feat:shrike-notify-20261122-add-the-age-helper-in-backend-app-utils-] ---

# --- 27B-decomposed from roadmap [2026-11-22]: Add the latest router - create `backend/app/routers/latest.py` with `router = APIRouter(ta (review + tweak) [feat:shrike-notify-20261122-add-the-latest-router-create-backend-app] ---

# --- 27B-decomposed from roadmap [2026-11-22]: Wire the latest router - in `backend/app/main.py` add `latest` to the existing `from app.r (review + tweak) [feat:shrike-notify-20261122-wire-the-latest-router-in-backend-app-ma] ---

# --- 27B-decomposed from roadmap [2026-11-22]: Add the gap list helper - create `backend/app/utils/gaps.py` with `gap_seconds(messages: l (review + tweak) [feat:shrike-notify-20261122-add-the-gap-list-helper-create-backend-a] ---

# --- 27B-decomposed from roadmap [2026-11-22]: Add the gap statistics helper - in `backend/app/utils/gaps.py` add `gap_stats(gaps: list[f (review + tweak) [feat:shrike-notify-20261122-add-the-gap-statistics-helper-in-backend] ---

# --- 27B-decomposed from roadmap [2026-11-22]: Add the since last helper - in `backend/app/utils/gaps.py` add `since_last(messages: list[ (review + tweak) [feat:shrike-notify-20261122-add-the-since-last-helper-in-backend-app] ---

# --- 27B-decomposed from roadmap [2026-11-22]: Add the gaps router - create `backend/app/routers/gaps.py` with `router = APIRouter(tags=[ (review + tweak) [feat:shrike-notify-20261122-add-the-gaps-router-create-backend-app-r] ---

# --- 27B-decomposed from roadmap [2026-11-22]: Wire the gaps router - in `backend/app/main.py` add `gaps` to the existing `from app.route (review + tweak) [feat:shrike-notify-20261122-wire-the-gaps-router-in-backend-app-main] ---

# --- 27B-decomposed from roadmap [2026-11-22]: Add the duplicate key helper - create `backend/app/utils/duplicates.py` with `duplicate_ke (review + tweak) [feat:shrike-notify-20261122-add-the-duplicate-key-helper-create-back] ---

# --- 27B-decomposed from roadmap [2026-11-22]: Add the duplicate grouping helper - in `backend/app/utils/duplicates.py` add `find_duplica (review + tweak) [feat:shrike-notify-20261122-add-the-duplicate-grouping-helper-in-bac] ---

# --- 27B-decomposed from roadmap [2026-11-22]: Add the duplicates router - create `backend/app/routers/duplicates.py` with `router = APIR (review + tweak) [feat:shrike-notify-20261122-add-the-duplicates-router-create-backend] ---

# --- 27B-decomposed from roadmap [2026-11-22]: Wire the duplicates router - in `backend/app/main.py` add `duplicates` to the existing `fr (review + tweak) [feat:shrike-notify-20261122-wire-the-duplicates-router-in-backend-ap] ---

# --- 27B-decomposed from roadmap [2026-11-22]: Add the pair counting helper - create `backend/app/utils/tag_pairs.py` with `count_tag_pai (review + tweak) [feat:shrike-notify-20261122-add-the-pair-counting-helper-create-back] ---

# --- 27B-decomposed from roadmap [2026-11-22]: Add the ranked pair list - in `backend/app/utils/tag_pairs.py` add `top_tag_pairs(counts:  (review + tweak) [feat:shrike-notify-20261122-add-the-ranked-pair-list-in-backend-app-] ---

# --- 27B-decomposed from roadmap [2026-11-22]: Add the tag pairs router - create `backend/app/routers/tag_pairs.py` with `router = APIRou (review + tweak) [feat:shrike-notify-20261122-add-the-tag-pairs-router-create-backend-] ---

# --- 27B-decomposed from roadmap [2026-11-23]: Wire the tag pairs router - in `backend/app/main.py` add `tag_pairs` to the existing `from (review + tweak) [feat:shrike-notify-20261123-wire-the-tag-pairs-router-in-backend-app] ---

# --- 27B-decomposed from roadmap [2026-11-23]: Add the field usage counter - create `backend/app/utils/field_usage.py` with `field_usage( (review + tweak) [feat:shrike-notify-20261123-add-the-field-usage-counter-create-backe] ---

# --- 27B-decomposed from roadmap [2026-11-23]: Add the percentage helper - in `backend/app/utils/field_usage.py` add `usage_percent(count (review + tweak) [feat:shrike-notify-20261123-add-the-percentage-helper-in-backend-app] ---

# --- 27B-decomposed from roadmap [2026-11-23]: Add the fields router - create `backend/app/routers/fields.py` with `router = APIRouter(ta (review + tweak) [feat:shrike-notify-20261123-add-the-fields-router-create-backend-app] ---

# --- 27B-decomposed from roadmap [2026-11-23]: Wire the fields router - in `backend/app/main.py` add `fields` to the existing `from app.r (review + tweak) [feat:shrike-notify-20261123-wire-the-fields-router-in-backend-app-ma] ---

# --- 27B-decomposed from roadmap [2026-11-23]: Add the hour counting helper - create `backend/app/utils/hours.py` with `hour_counts(messa (review + tweak) [feat:shrike-notify-20261123-add-the-hour-counting-helper-create-back] ---

# --- 27B-decomposed from roadmap [2026-11-23]: Add the busiest hour helper - in `backend/app/utils/hours.py` add `busiest_hour(counts: li (review + tweak) [feat:shrike-notify-20261123-add-the-busiest-hour-helper-in-backend-a] ---

# --- 27B-decomposed from roadmap [2026-11-23]: Add the hours router - create `backend/app/routers/hours.py` with `router = APIRouter(tags (review + tweak) [feat:shrike-notify-20261123-add-the-hours-router-create-backend-app-] ---

# --- 27B-decomposed from roadmap [2026-11-23]: Wire the hours router - in `backend/app/main.py` add `hours` to the existing `from app.rou (review + tweak) [feat:shrike-notify-20261123-wire-the-hours-router-in-backend-app-mai] ---

# --- 27B-decomposed from roadmap [2026-11-23]: Add the day counting helper - create `backend/app/utils/daily.py` with `day_key(created_at (review + tweak) [feat:shrike-notify-20261123-add-the-day-counting-helper-create-backe] ---

# --- 27B-decomposed from roadmap [2026-11-23]: Add the recent days helper - in `backend/app/utils/daily.py` add `recent_days(counts: dict (review + tweak) [feat:shrike-notify-20261123-add-the-recent-days-helper-in-backend-ap] ---
- [ ] [T1] backend/app/utils/daily.py — Add `busiest_day(counts: dict[str, int]) -> str | None` returning the date with the greatest count (earliest date on tie) or `None` if empty. VERIFY: `cd backend && python3 -c "from app.utils.daily import busiest_day; assert busiest_day({'2023-10-02': 5, '2023-10-01': 5}) == '2023-10-01'"`. (cat:python; multifile:no) [feat:shrike-notify-20261123-add-the-recent-days-helper-in-backend-ap]
- [ ] [T2] backend/tests/test_daily_recent.py — Create test file with `test_recent_days_are_newest_first` verifying descending date order. VERIFY: `cd backend && python3 -m pytest tests/test_daily_recent.py::test_recent_days_are_newest_first -q`. (cat:test; multifile:no) [feat:shrike-notify-20261123-add-the-recent-days-helper-in-backend-ap]
- [ ] [T2] backend/tests/test_daily_recent.py — Add `test_limit_caps_the_list` verifying the result length does not exceed the limit. VERIFY: `cd backend && python3 -m pytest tests/test_daily_recent.py::test_limit_caps_the_list -q`. (cat:test; multifile:no) [feat:shrike-notify-20261123-add-the-recent-days-helper-in-backend-ap]
- [ ] [T2] backend/tests/test_daily_recent.py — Add `test_zero_limit_is_empty` verifying an empty list is returned when limit is 0 or negative. VERIFY: `cd backend && python3 -m pytest tests/test_daily_recent.py::test_zero_limit_is_empty -q`. (cat:test; multifile:no) [feat:shrike-notify-20261123-add-the-recent-days-helper-in-backend-ap]
- [ ] [T2] backend/tests/test_daily_recent.py — Add `test_busiest_day_prefers_the_earliest_on_a_tie` verifying the earliest date is returned when counts are equal. VERIFY: `cd backend && python3 -m pytest tests/test_daily_recent.py::test_busiest_day_prefers_the_earliest_on_a_tie -q`. (cat:test; multifile:no) [feat:shrike-notify-20261123-add-the-recent-days-helper-in-backend-ap]
- [ ] [T2] backend/tests/test_daily_recent.py — Add `test_empty_counts_have_no_busiest_day` verifying `None` is returned for an empty counts dictionary. VERIFY: `cd backend && python3 -m pytest tests/test_daily_recent.py::test_empty_counts_have_no_busiest_day -q`. (cat:test; multifile:no) [feat:shrike-notify-20261123-add-the-recent-days-helper-in-backend-ap]

# --- 27B-decomposed from roadmap [2026-11-23]: Add the daily router - create `backend/app/routers/daily.py` with `router = APIRouter(tags (review + tweak) [feat:shrike-notify-20261123-add-the-daily-router-create-backend-app-] ---
- [ ] [T1] backend/app/utils/daily.py — Add `recent_days(counts: dict, limit: int) -> list` that returns a list of `{"date": str, "count": int}` dicts sorted by date descending, limited to the top `limit` entries. VERIFY: `cd backend && python3 -c "from app.utils.daily import recent_days; c={'1970-01-02':2,'1970-01-03':1}; r=recent_days(c, 7); assert r[0]=={'date':'1970-01-03','count':1} and r[1]=={'date':'1970-01-02','count':2}"`. (cat:python; multifile:no) [feat:shrike-notify-20261123-add-the-daily-router-create-backend-app-]
- [ ] [T1] backend/app/utils/daily.py — Add `busiest_day(counts: dict) -> str | None` that returns the date string with the highest count, or `None` if counts is empty. VERIFY: `cd backend && python3 -c "from app.utils.daily import busiest_day; c={'1970-01-02':2,'1970-01-03':1}; assert busiest_day(c)=='1970-01-02'; assert busiest_day({}) is None"`. (cat:python; multifile:no) [feat:shrike-notify-20261123-add-the-daily-router-create-backend-app-]
- [ ] [T2] backend/app/routers/daily.py — Create the file with `router = APIRouter(tags=["messages"])` and import `Query` from `fastapi`, `require_topic_and_auth` from `app.dependencies`, `broker` from `app.services.broker`, and `daily_counts`, `recent_days`, `busiest_day` from `app.utils.daily`. VERIFY: `cd backend && python3 -c "import app.routers.daily"`. (cat:python; multifile:no) [feat:shrike-notify-20261123-add-the-daily-router-create-backend-app-]
- [ ] [T2] backend/app/routers/daily.py — Add `GET /{topic}/daily` endpoint with `topic: str = Depends(require_topic_and_auth)` and `limit: int = Query(7, ge=1, le=90)`, returning the specified JSON structure using `await broker.history(topic, limit=None)`. VERIFY: `cd backend && python3 -c "from app.routers.daily import router; assert any(r.path=='/{topic}/daily' for r in router.routes)"`. (cat:python; multifile:no) [feat:shrike-notify-20261123-add-the-daily-router-create-backend-app-]
- [ ] [T2] backend/tests/test_daily_router.py — Create the test file with a local `FastAPI()` instance mounting the daily router, and include a fixture or helper to patch `broker.history` with an `AsyncMock`. VERIFY: `cd backend && python3 -m pytest tests/test_daily_router.py --collect-only -q`. (cat:test; multifile:no) [feat:shrike-notify-20261123-add-the-daily-router-create-backend-app-]
- [ ] [T2] backend/tests/test_daily_router.py — Add test case asserting that for messages at 86400, 86460, and 172800, `days[0]['date'] == '1970-01-03'`, `days[1] == {'date': '1970-01-02', 'count': 2}`, and `busiest_day == '1970-01-02'`. VERIFY: `cd backend && python3 -m pytest tests/test_daily_router.py::test_daily_counts_and_busiest -q`. (cat:test; multifile:no) [feat:shrike-notify-20261123-add-the-daily-router-create-backend-app-]
- [ ] [T2] backend/tests/test_daily_router.py — Add test case asserting that an empty history returns `days == []` and `busiest_day is None`. VERIFY: `cd backend && python3 -m pytest tests/test_daily_router.py::test_daily_empty_history -q`. (cat:test; multifile:no) [feat:shrike-notify-20261123-add-the-daily-router-create-backend-app-]
- [ ] [T2] backend/tests/test_daily_router.py — Add test case asserting that `limit=0` returns status code 422. VERIFY: `cd backend && python3 -m pytest tests/test_daily_router.py::test_daily_limit_zero_422 -q`. (cat:test; multifile:no) [feat:shrike-notify-20261123-add-the-daily-router-create-backend-app-]
- [ ] [T2] backend/tests/test_daily_router.py — Add test case asserting that requesting `/bad$topic/daily` returns status code 422. VERIFY: `cd backend && python3 -m pytest tests/test_daily_router.py::test_daily_invalid_topic_422 -q`. (cat:test; multifile:no) [feat:shrike-notify-20261123-add-the-daily-router-create-backend-app-]

# --- 27B-decomposed from roadmap [2026-11-23]: Wire the daily router - in `backend/app/main.py` add `daily` to the existing `from app.rou (review + tweak) [feat:shrike-notify-20261123-wire-the-daily-router-in-backend-app-mai] ---
- [ ] [T1] backend/app/routers/daily.py — Create the router module with `router = APIRouter()` and a `GET /{topic}/daily` endpoint that returns 200 for valid topics and 422 for invalid ones. VERIFY: `cd backend && python3 -c "from app.routers.daily import router; print('ok')"`. (cat:endpoint; multifile:no) [feat:shrike-notify-20261123-wire-the-daily-router-in-backend-app-mai]
- [ ] [T1] backend/app/routers/__init__.py — Add `daily` to the existing `from app.routers import ...` import line. VERIFY: `cd backend && python3 -c "from app.routers import daily; print('ok')"`. (cat:python; multifile:no) [feat:shrike-notify-20261123-wire-the-daily-router-in-backend-app-mai]
- [ ] [T2] backend/app/main.py — Add `app.include_router(daily.router)` directly after the line `app.include_router(export.router)`. VERIFY: `cd backend && python3 -c "from app.main import app; assert '/{topic}/daily' in app.openapi()['paths']"`. (cat:endpoint; multifile:no) [feat:shrike-notify-20261123-wire-the-daily-router-in-backend-app-mai]
- [ ] [T1] backend/tests/test_daily_wired.py — Create the test file with `test_daily_route_registered` asserting `/{topic}/daily` is a key in `app.openapi()['paths']`. VERIFY: `cd backend && python3 -m pytest tests/test_daily_wired.py::test_daily_route_registered -q`. (cat:test; multifile:no) [feat:shrike-notify-20261123-wire-the-daily-router-in-backend-app-mai]
- [ ] [T1] backend/tests/test_daily_wired.py — Add `test_daily_rejects_a_bad_topic` asserting `TestClient(app).get('/bad$topic/daily')` returns status code 422. VERIFY: `cd backend && python3 -m pytest tests/test_daily_wired.py::test_daily_rejects_a_bad_topic -q`. (cat:test; multifile:no) [feat:shrike-notify-20261123-wire-the-daily-router-in-backend-app-mai]
- [ ] [T3] backend/tests/test_daily_wired.py — Ensure the test file imports `app` from `app.main` and uses `TestClient` correctly to verify both tests pass together. VERIFY: `cd backend && python3 -m pytest tests/test_daily_wired.py -q`. (cat:test; multifile:no) [feat:shrike-notify-20261123-wire-the-daily-router-in-backend-app-mai]

# --- 27B-decomposed from roadmap [2026-11-23]: Add the weekday counting helper - create `backend/app/utils/weekdays.py` with `weekday_cou (review + tweak) [feat:shrike-notify-20261123-add-the-weekday-counting-helper-create-b] ---
- [ ] [T1] backend/app/utils/weekdays.py — Add `weekday_counts(messages: list[Message]) -> list[int]` that initializes a 7-element zero list, iterates messages skipping those with `created_at <= 0`, and increments the bucket at index `time.gmtime(created_at).tm_wday`. VERIFY: `cd backend && python3 -c "from app.utils.weekdays import weekday_counts; from app.models import Message; print(weekday_counts([Message(id='1', topic='t', body='b', created_at=0)]))"`. (cat:python; multifile:no) [feat:shrike-notify-20261123-add-the-weekday-counting-helper-create-b]
- [ ] [T2] backend/tests/test_weekday_counts.py — Add `test_always_seven_buckets` asserting `len(weekday_counts([])) == 7` and all elements are 0. VERIFY: `cd backend && python3 -m pytest tests/test_weekday_counts.py::test_always_seven_buckets -q`. (cat:test; multifile:no) [feat:shrike-notify-20261123-add-the-weekday-counting-helper-create-b]
- [ ] [T3] backend/tests/test_weekday_counts.py — Add `test_epoch_day_is_a_thursday` asserting `weekday_counts([Message(id='1', topic='t', body='b', created_at=0)])` returns `[0, 0, 0, 1, 0, 0, 0]`. VERIFY: `cd backend && python3 -m pytest tests/test_weekday_counts.py::test_epoch_day_is_a_thursday -q`. (cat:test; multifile:no) [feat:shrike-notify-20261123-add-the-weekday-counting-helper-create-b]
- [ ] [T4] backend/tests/test_weekday_counts.py — Add `test_same_weekday_on_different_weeks_adds_up` asserting two messages with `created_at` values 7 days apart on the same weekday result in a count of 2 for that weekday. VERIFY: `cd backend && python3 -m pytest tests/test_weekday_counts.py::test_same_weekday_on_different_weeks_adds_up -q`. (cat:test; multifile:no) [feat:shrike-notify-20261123-add-the-weekday-counting-helper-create-b]
- [ ] [T5] backend/tests/test_weekday_counts.py — Add `test_unknown_creation_time_is_skipped` asserting messages with `created_at=0` or negative values do not increment any bucket. VERIFY: `cd backend && python3 -m pytest tests/test_weekday_counts.py::test_unknown_creation_time_is_skipped -q`. (cat:test; multifile:no) [feat:shrike-notify-20261123-add-the-weekday-counting-helper-create-b]

# --- 27B-decomposed from roadmap [2026-11-23]: Add the weekday naming helper - in `backend/app/utils/weekdays.py` add `WEEKDAY_NAMES = (' (review + tweak) [feat:shrike-notify-20261123-add-the-weekday-naming-helper-in-backend] ---
- [ ] [T1] backend/app/utils/weekdays.py — Add WEEKDAY_NAMES tuple with 7 lowercase weekday names in order. VERIFY: `cd backend && python3 -c "from app.utils.weekdays import WEEKDAY_NAMES; assert len(WEEKDAY_NAMES) == 7 and WEEKDAY_NAMES[0] == 'monday'"` (cat:python; multifile:no) [feat:shrike-notify-20261123-add-the-weekday-naming-helper-in-backend]
- [ ] [T1] backend/app/utils/weekdays.py — Add weekday_map function that zips WEEKDAY_NAMES with input list and returns dict. VERIFY: `cd backend && python3 -c "from app.utils.weekdays import weekday_map; assert weekday_map([1,2,3,4,5,6,7]) == {'monday':1,'tuesday':2,'wednesday':3,'thursday':4,'friday':5,'saturday':6,'sunday':7}"` (cat:python; multifile:no) [feat:shrike-notify-20261123-add-the-weekday-naming-helper-in-backend]
- [ ] [T1] backend/app/utils/weekdays.py — Add busiest_weekday function returning name of max count (earliest on tie) or None if all zero/empty. VERIFY: `cd backend && python3 -c "from app.utils.weekdays import busiest_weekday; assert busiest_weekday([0,5,0,0,0,0,0]) == 'tuesday' and busiest_weekday([]) is None and busiest_weekday([0,0,0,0,0,0,0]) is None"` (cat:python; multifile:no) [feat:shrike-notify-20261123-add-the-weekday-naming-helper-in-backend]
- [ ] [T2] backend/tests/test_weekday_names.py — Add test_map_has_seven_named_entries verifying weekday_map output has 7 keys matching WEEKDAY_NAMES. VERIFY: `cd backend && python3 -m pytest tests/test_weekday_names.py::test_map_has_seven_named_entries -q` (cat:test; multifile:no) [feat:shrike-notify-20261123-add-the-weekday-naming-helper-in-backend]
- [ ] [T2] backend/tests/test_weekday_names.py — Add test_busiest_weekday_single_peak verifying busiest_weekday returns correct name for single max value. VERIFY: `cd backend && python3 -m pytest tests/test_weekday_names.py::test_busiest_weekday_single_peak -q` (cat:test; multifile:no) [feat:shrike-notify-20261123-add-the-weekday-naming-helper-in-backend]
- [ ] [T2] backend/tests/test_weekday_names.py — Add test_tie_picks_the_earliest_weekday verifying busiest_weekday returns earliest weekday on tie. VERIFY: `cd backend && python3 -m pytest tests/test_weekday_names.py::test_tie_picks_the_earliest_weekday -q` (cat:test; multifile:no) [feat:shrike-notify-20261123-add-the-weekday-naming-helper-in-backend]
- [ ] [T2] backend/tests/test_weekday_names.py — Add test_all_zero_is_none verifying busiest_weekday returns None for all zeros and empty list. VERIFY: `cd backend && python3 -m pytest tests/test_weekday_names.py::test_all_zero_is_none -q` (cat:test; multifile:no) [feat:shrike-notify-20261123-add-the-weekday-naming-helper-in-backend]

# --- 27B-decomposed from roadmap [2026-11-23]: Add the weekdays router - create `backend/app/routers/weekdays.py` with `router = APIRoute (review + tweak) [feat:shrike-notify-20261123-add-the-weekdays-router-create-backend-a] ---
- [ ] [T1] backend/app/utils/activity.py — Add `weekday_counts(history)` and `busiest_weekday(counts)` functions returning a dict of weekday counts and the max weekday name or None. VERIFY: `cd backend && python3 -c "from app.utils.activity import weekday_counts, busiest_weekday; print(weekday_counts([]))"`. (cat:python; multifile:no) [feat:shrike-notify-20261123-add-the-weekdays-router-create-backend-a]
- [ ] [T2] backend/tests/test_activity_weekday_utils.py — Add tests for `weekday_counts` and `busiest_weekday` covering empty lists, single day, and tie-breaking. VERIFY: `cd backend && python3 -m pytest tests/test_activity_weekday_utils.py -q`. (cat:test; multifile:no) [feat:shrike-notify-20261123-add-the-weekdays-router-create-backend-a]
- [ ] [T3] backend/app/routers/weekdays.py — Create router with `GET /{topic}/weekdays` endpoint using `require_topic_and_auth` and `broker.history`, returning the specified JSON structure. VERIFY: `cd backend && python3 -c "from app.routers.weekdays import router; print(router)"`. (cat:endpoint; multifile:no) [feat:shrike-notify-20261123-add-the-weekdays-router-create-backend-a]
- [ ] [T5] backend/app/main.py — Include the weekdays router in the FastAPI app initialization. VERIFY: `cd backend && python3 -c "from app.main import app; print(any('weekdays' in r.path for r in app.routes))"`. (cat:endpoint; multifile:no) [feat:shrike-notify-20261123-add-the-weekdays-router-create-backend-a]
- [ ] [T4] backend/tests/test_weekdays_router.py — Create test file with FastAPI app mounting the weekdays router, mocking `broker.history` to return two Thursday messages, asserting counts and busiest weekday, empty history case, and 422 for invalid topic. VERIFY: `cd backend && python3 -m pytest tests/test_weekdays_router.py -q`. (cat:test; multifile:no) [feat:shrike-notify-20261123-add-the-weekdays-router-create-backend-a]

# --- 27B-decomposed from roadmap [2026-11-23]: Wire the weekdays router - in `backend/app/main.py` add `weekdays` to the existing `from a (review + tweak) [feat:shrike-notify-20261123-wire-the-weekdays-router-in-backend-app-] ---
- [ ] [T3] backend/app/main.py — Add `weekdays` to the existing `from app.routers import ...` line and add `app.include_router(weekdays.router)` directly after `app.include_router(export.router)`. VERIFY: `cd backend && python3 -c "from app.main import app; assert '/{topic}/weekdays' in app.openapi()['paths']"`. (cat:endpoint; multifile:no) [feat:shrike-notify-20261123-wire-the-weekdays-router-in-backend-app-]
- [ ] [T1] backend/app/routers/weekdays.py — Create the router module with a `router = APIRouter()` and a `GET /{topic}/weekdays` endpoint that returns 422 for invalid topic slugs. VERIFY: `cd backend && python3 -c "from app.routers.weekdays import router; assert hasattr(router, 'routes')"`. (cat:endpoint; multifile:no) [feat:shrike-notify-20261123-wire-the-weekdays-router-in-backend-app-]
- [ ] [T1] backend/app/routers/weekdays.py — Implement the topic validation logic to reject topics containing invalid characters like `$` by raising a `422` response or using Pydantic validation. VERIFY: `cd backend && python3 -c "from app.routers.weekdays import router; print('ok')"`. (cat:endpoint; multifile:no) [feat:shrike-notify-20261123-wire-the-weekdays-router-in-backend-app-]
- [ ] [T2] backend/tests/test_weekdays_wired.py — Create the test file with `test_weekdays_route_registered` asserting `/{topic}/weekdays` is a key in `app.openapi()['paths']`. VERIFY: `cd backend && python3 -m pytest tests/test_weekdays_wired.py::test_weekdays_route_registered -q`. (cat:test; multifile:no) [feat:shrike-notify-20261123-wire-the-weekdays-router-in-backend-app-]
- [ ] [T2] backend/tests/test_weekdays_wired.py — Add `test_weekdays_rejects_a_bad_topic` asserting `TestClient(app).get('/bad$topic/weekdays')` returns status code 422. VERIFY: `cd backend && python3 -m pytest tests/test_weekdays_wired.py::test_weekdays_rejects_a_bad_topic -q`. (cat:test; multifile:no) [feat:shrike-notify-20261123-wire-the-weekdays-router-in-backend-app-]
- [ ] [T1] backend/tests/test_weekdays_wired.py — Ensure the test file imports `app` from `app.main` and `TestClient` from `fastapi.testclient` correctly. VERIFY: `cd backend && python3 -m pytest tests/test_weekdays_wired.py -q`. (cat:test; multifile:no) [feat:shrike-notify-20261123-wire-the-weekdays-router-in-backend-app-]

# --- 27B-decomposed from roadmap [2026-11-23]: Add the word splitting helper - create `backend/app/utils/words.py` with `STOP_WORDS = fro (review + tweak) [feat:shrike-notify-20261123-add-the-word-splitting-helper-create-bac] ---
- [ ] [T1] backend/app/utils/words.py — Add `STOP_WORDS` frozenset and `tokenize` function using regex `[a-z0-9]{3,}` on lowercased text VERIFY: `cd backend && python3 -c "from app.utils.words import STOP_WORDS, tokenize; assert isinstance(STOP_WORDS, frozenset); assert callable(tokenize)"`. (cat:python; multifile:no) [feat:shrike-notify-20261123-add-the-word-splitting-helper-create-bac]
- [ ] [T2] backend/tests/test_words_tokenize.py — Add `test_words_are_lowercased` asserting `tokenize("Hello World")` returns `['hello', 'world']` VERIFY: `cd backend && python3 -m pytest tests/test_words_tokenize.py::test_words_are_lowercased -q`. (cat:test; multifile:no) [feat:shrike-notify-20261123-add-the-word-splitting-helper-create-bac]
- [ ] [T2] backend/tests/test_words_tokenize.py — Add `test_short_words_are_dropped` asserting `tokenize("a b c def")` returns `['def']` VERIFY: `cd backend && python3 -m pytest tests/test_words_tokenize.py::test_short_words_are_dropped -q`. (cat:test; multifile:no) [feat:shrike-notify-20261123-add-the-word-splitting-helper-create-bac]
- [ ] [T2] backend/tests/test_words_tokenize.py — Add `test_stop_words_are_dropped` asserting `tokenize("the quick brown fox")` returns `['quick', 'brown', 'fox']` VERIFY: `cd backend && python3 -m pytest tests/test_words_tokenize.py::test_stop_words_are_dropped -q`. (cat:test; multifile:no) [feat:shrike-notify-20261123-add-the-word-splitting-helper-create-bac]
- [ ] [T2] backend/tests/test_words_tokenize.py — Add `test_punctuation_separates_words` asserting `tokenize("hello,world! foo")` returns `['hello', 'world', 'foo']` VERIFY: `cd backend && python3 -m pytest tests/test_words_tokenize.py::test_punctuation_separates_words -q`. (cat:test; multifile:no) [feat:shrike-notify-20261123-add-the-word-splitting-helper-create-bac]
- [ ] [T2] backend/tests/test_words_tokenize.py — Add `test_empty_text_gives_no_words` asserting `tokenize("")` returns `[]` VERIFY: `cd backend && python3 -m pytest tests/test_words_tokenize.py::test_empty_text_gives_no_words -q`. (cat:test; multifile:no) [feat:shrike-notify-20261123-add-the-word-splitting-helper-create-bac]

# --- 27B-decomposed from roadmap [2026-11-23]: Add the top words helper - in `backend/app/utils/words.py` add `top_words(messages: list[M (review + tweak) [feat:shrike-notify-20261123-add-the-top-words-helper-in-backend-app-] ---
- [ ] [T1] backend/app/utils/words.py — Add `tokenize(text: str) -> list[str]` helper that splits on whitespace and lowercases tokens. VERIFY: `cd backend && python3 -c "from app.utils.words import tokenize; assert tokenize('Hello World hello') == ['hello', 'world', 'hello']"`. (cat:python; multifile:no) [feat:shrike-notify-20261123-add-the-top-words-helper-in-backend-app-]
- [ ] [T1] backend/app/utils/words.py — Add `top_words(messages: list[Message], limit: int = 10) -> list[dict]` function that counts tokens from `m.title + ' ' + m.body` and returns sorted results. VERIFY: `cd backend && python3 -c "from app.utils.words import top_words; from app.models import Message; msgs=[Message(title='a b', body='b c')]; assert top_words(msgs, 2) == [{'word': 'b', 'count': 2}, {'word': 'a', 'count': 1}]"`. (cat:python; multifile:no) [feat:shrike-notify-20261123-add-the-top-words-helper-in-backend-app-]
- [ ] [T2] backend/tests/test_words_top.py — Create test file with `test_counts_words_across_title_and_body` verifying token counting logic. VERIFY: `cd backend && python3 -m pytest tests/test_words_top.py::test_counts_words_across_title_and_body -q`. (cat:test; multifile:no) [feat:shrike-notify-20261123-add-the-top-words-helper-in-backend-app-]
- [ ] [T2] backend/tests/test_words_top.py — Add `test_orders_by_count_then_word` verifying sort order by count desc then word asc. VERIFY: `cd backend && python3 -m pytest tests/test_words_top.py::test_orders_by_count_then_word -q`. (cat:test; multifile:no) [feat:shrike-notify-20261123-add-the-top-words-helper-in-backend-app-]
- [ ] [T2] backend/tests/test_words_top.py — Add `test_limit_caps_the_list` verifying limit parameter truncates results. VERIFY: `cd backend && python3 -m pytest tests/test_words_top.py::test_limit_caps_the_list -q`. (cat:test; multifile:no) [feat:shrike-notify-20261123-add-the-top-words-helper-in-backend-app-]
- [ ] [T2] backend/tests/test_words_top.py — Add `test_zero_limit_is_empty` verifying empty list returned for limit <= 0. VERIFY: `cd backend && python3 -m pytest tests/test_words_top.py::test_zero_limit_is_empty -q`. (cat:test; multifile:no) [feat:shrike-notify-20261123-add-the-top-words-helper-in-backend-app-]
- [ ] [T2] backend/tests/test_words_top.py — Add `test_no_messages_give_an_empty_list` verifying empty input returns empty list. VERIFY: `cd backend && python3 -m pytest tests/test_words_top.py::test_no_messages_give_an_empty_list -q`. (cat:test; multifile:no) [feat:shrike-notify-20261123-add-the-top-words-helper-in-backend-app-]

# --- 27B-decomposed from roadmap [2026-11-23]: Add the words router - create `backend/app/routers/words.py` with `router = APIRouter(tags (review + tweak) [feat:shrike-notify-20261123-add-the-words-router-create-backend-app-] ---
- [ ] [T1] backend/app/utils/words.py — Add `top_words(history: list, limit: int) -> list[dict]` that counts word frequencies from message bodies and returns top N as `[{"word": str, "count": int}]`. VERIFY: `cd backend && python3 -m pytest tests/test_words_util.py -q`. (cat:python; multifile:no) [feat:shrike-notify-20261123-add-the-words-router-create-backend-app-]
- [ ] [T2] backend/app/routers/words.py — Create router with `GET /{topic}/words` endpoint using `require_topic_and_auth`, `Query(10, ge=1, le=50)`, and returning topic stats with `top_words`. VERIFY: `cd backend && python3 -c "from app.routers.words import router; print(router.routes[0].path)"`. (cat:endpoint; multifile:no) [feat:shrike-notify-20261123-add-the-words-router-create-backend-app-]
- [ ] [T1] backend/tests/test_words_util.py — Add unit tests for `top_words` verifying correct counting, sorting by frequency, and limit enforcement. VERIFY: `cd backend && python3 -m pytest tests/test_words_util.py -q`. (cat:test; multifile:no) [feat:shrike-notify-20261123-add-the-words-router-create-backend-app-]
- [ ] [T2] backend/tests/test_words_router.py — Add tests for words router verifying response structure, empty history case, limit=0 validation error, and invalid topic 422 response. VERIFY: `cd backend && python3 -m pytest tests/test_words_router.py -q`. (cat:test; multifile:no) [feat:shrike-notify-20261123-add-the-words-router-create-backend-app-]
- [ ] [T3] backend/app/routers/__init__.py — Import `words` router and include it in the main router aggregation. VERIFY: `cd backend && python3 -c "from app.routers import api_router; assert any(r.path == '/{topic}/words' for r in api_router.routes)"`. (cat:refactor; multifile:no) [feat:shrike-notify-20261123-add-the-words-router-create-backend-app-]
- [ ] [T3] backend/app/main.py — Ensure words router is mounted in the FastAPI application instance. VERIFY: `cd backend && python3 -c "from app.main import app; assert any('/{topic}/words' in r.path for r in app.routes)"`. (cat:endpoint; multifile:no) [feat:shrike-notify-20261123-add-the-words-router-create-backend-app-]

# --- 27B-decomposed from roadmap [2026-11-23]: Wire the words router - in `backend/app/main.py` add `words` to the existing `from app.rou (review + tweak) [feat:shrike-notify-20261123-wire-the-words-router-in-backend-app-mai] ---
- [ ] [T1] backend/app/routers/words.py — Add `router = APIRouter()` and a `GET /{topic}/words` endpoint that returns 422 for topics containing invalid characters. VERIFY: `cd backend && python3 -m pytest tests/test_words_endpoint.py -q`. (cat:endpoint; multifile:no) [feat:shrike-notify-20261123-wire-the-words-router-in-backend-app-mai]
- [ ] [T1] backend/tests/test_words_endpoint.py — Create test file with `test_words_rejects_bad_topic` asserting 422 response for `/bad$topic/words`. VERIFY: `cd backend && python3 -m pytest tests/test_words_endpoint.py::test_words_rejects_bad_topic -q`. (cat:test; multifile:no) [feat:shrike-notify-20261123-wire-the-words-router-in-backend-app-mai]
- [ ] [T3] backend/app/main.py — Add `words` to the `from app.routers import ...` line and add `app.include_router(words.router)` immediately after `app.include_router(export.router)`. VERIFY: `cd backend && python3 -c "from app.main import app; assert '/{topic}/words' in app.openapi()['paths']"`. (cat:python; multifile:no) [feat:shrike-notify-20261123-wire-the-words-router-in-backend-app-mai]
- [ ] [T1] backend/tests/test_words_wired.py — Create test file with `test_words_route_registered` asserting `/{topic}/words` is a key in `app.openapi()['paths']`. VERIFY: `cd backend && python3 -m pytest tests/test_words_wired.py::test_words_route_registered -q`. (cat:test; multifile:no) [feat:shrike-notify-20261123-wire-the-words-router-in-backend-app-mai]
- [ ] [T1] backend/tests/test_words_wired.py — Add `test_words_rejects_a_bad_topic` asserting `TestClient(app).get('/bad$topic/words')` returns status code 422. VERIFY: `cd backend && python3 -m pytest tests/test_words_wired.py::test_words_rejects_a_bad_topic -q`. (cat:test; multifile:no) [feat:shrike-notify-20261123-wire-the-words-router-in-backend-app-mai]
- [ ] [T5] backend/app/routers/words.py — Ensure the `/{topic}/words` path parameter uses a regex validator or manual check to reject topics with `$` or other invalid chars, returning 422. VERIFY: `cd backend && python3 -m pytest tests/test_words_wired.py -q`. (cat:endpoint; multifile:no) [feat:shrike-notify-20261123-wire-the-words-router-in-backend-app-mai]

# --- 27B-decomposed from roadmap [2026-11-23]: Add the URL extraction helper - create `backend/app/utils/links.py` with `extract_urls(tex (review + tweak) [feat:shrike-notify-20261123-add-the-url-extraction-helper-create-bac] ---
- [ ] [T1] backend/app/utils/links.py — Add `extract_urls` function using regex `https?://[^\s<>"')]+` and stripping trailing `.`, `,`, `;`, `:`, `?` from matches. VERIFY: `cd backend && python3 -c "from app.utils.links import extract_urls; assert extract_urls('http://a.com.') == ['http://a.com']"`. (cat:python; multifile:no) [feat:shrike-notify-20261123-add-the-url-extraction-helper-create-bac]
- [ ] [T1] backend/tests/test_links_extract.py — Add test file with `test_finds_http_and_https_links` verifying basic extraction. VERIFY: `cd backend && python3 -m pytest tests/test_links_extract.py::test_finds_http_and_https_links -q`. (cat:test; multifile:no) [feat:shrike-notify-20261123-add-the-url-extraction-helper-create-bac]
- [ ] [T1] backend/tests/test_links_extract.py — Add `test_trailing_punctuation_is_removed` verifying punctuation stripping logic. VERIFY: `cd backend && python3 -m pytest tests/test_links_extract.py::test_trailing_punctuation_is_removed -q`. (cat:test; multifile:no) [feat:shrike-notify-20261123-add-the-url-extraction-helper-create-bac]
- [ ] [T1] backend/tests/test_links_extract.py — Add `test_text_without_links_gives_an_empty_list` verifying empty return for no matches. VERIFY: `cd backend && python3 -m pytest tests/test_links_extract.py::test_text_without_links_gives_an_empty_list -q`. (cat:test; multifile:no) [feat:shrike-notify-20261123-add-the-url-extraction-helper-create-bac]
- [ ] [T1] backend/tests/test_links_extract.py — Add `test_two_links_keep_their_order` verifying order preservation. VERIFY: `cd backend && python3 -m pytest tests/test_links_extract.py::test_two_links_keep_their_order -q`. (cat:test; multifile:no) [feat:shrike-notify-20261123-add-the-url-extraction-helper-create-bac]
- [ ] [T1] backend/tests/test_links_extract.py — Add `test_link_inside_parentheses_stops_before_the_bracket` verifying regex stops at `)`. VERIFY: `cd backend && python3 -m pytest tests/test_links_extract.py::test_link_inside_parentheses_stops_before_the_bracket -q`. (cat:test; multifile:no) [feat:shrike-notify-20261123-add-the-url-extraction-helper-create-bac]

# --- 27B-decomposed from roadmap [2026-11-24]: Add the link host helper - in `backend/app/utils/links.py` add `link_hosts(messages: list[ (review + tweak) [feat:shrike-notify-20261124-add-the-link-host-helper-in-backend-app-] ---
- [ ] [T1] backend/app/utils/links.py — Add `link_hosts(messages: list[Message], limit: int = 10) -> list[dict]` function that extracts URLs from message title/body, parses hostnames using `urllib.parse.urlsplit`, lowercases them, counts occurrences, filters out entries without hostnames, sorts by count descending then host ascending, and returns at most `limit` entries (empty list if limit <= 0). VERIFY: `cd backend && python3 -c "from app.utils.links import link_hosts; print('imported')"` (cat:python; multifile:no) [feat:shrike-notify-20261124-add-the-link-host-helper-in-backend-app-]
- [ ] [T1] backend/app/utils/links.py — Add `messages_with_links(messages: list[Message]) -> int` function that counts messages with at least one extracted URL. VERIFY: `cd backend && python3 -c "from app.utils.links import messages_with_links; print('imported')"` (cat:python; multifile:no) [feat:shrike-notify-20261124-add-the-link-host-helper-in-backend-app-]
- [ ] [T2] backend/tests/test_links_hosts.py — Create test file with `test_hosts_are_counted_and_lowercased` verifying that URLs are extracted, hostnames lowercased, and counts accurate. VERIFY: `cd backend && python3 -m pytest tests/test_links_hosts.py::test_hosts_are_counted_and_lowercased -q` (cat:test; multifile:no) [feat:shrike-notify-20261124-add-the-link-host-helper-in-backend-app-]
- [ ] [T2] backend/tests/test_links_hosts.py — Add `test_orders_by_count_then_host` verifying results are sorted by count descending, then host ascending. VERIFY: `cd backend && python3 -m pytest tests/test_links_hosts.py::test_orders_by_count_then_host -q` (cat:test; multifile:no) [feat:shrike-notify-20261124-add-the-link-host-helper-in-backend-app-]
- [ ] [T2] backend/tests/test_links_hosts.py — Add `test_limit_caps_the_list` verifying the returned list respects the limit parameter and returns empty list when limit <= 0. VERIFY: `cd backend && python3 -m pytest tests/test_links_hosts.py::test_limit_caps_the_list -q` (cat:test; multifile:no) [feat:shrike-notify-20261124-add-the-link-host-helper-in-backend-app-]
- [ ] [T2] backend/tests/test_links_hosts.py — Add `test_messages_with_links_counts_messages_not_links` verifying that `messages_with_links` counts messages with at least one URL, not total URLs. VERIFY: `cd backend && python3 -m pytest tests/test_links_hosts.py::test_messages_with_links_counts_messages_not_links -q` (cat:test; multifile:no) [feat:shrike-notify-20261124-add-the-link-host-helper-in-backend-app-]

# --- 27B-decomposed from roadmap [2026-11-24]: Add the links router - create `backend/app/routers/links.py` with `router = APIRouter(tags (review + tweak) [feat:shrike-notify-20261124-add-the-links-router-create-backend-app-] ---
- [ ] [T1] backend/app/utils/link_extract.py — Add pure functions `messages_with_links(history: list) -> int` and `link_hosts(history: list, limit: int) -> list[dict]` that parse URLs from message bodies, count messages containing at least one link, and aggregate host counts sorted by frequency descending then alphabetically, truncating to `limit`. VERIFY: `cd backend && python3 -m pytest tests/test_link_extract.py -q`. (cat:python; multifile:no) [feat:shrike-notify-20261124-add-the-links-router-create-backend-app-]
- [ ] [T1] backend/tests/test_link_extract.py — Add unit tests for `messages_with_links` and `link_hosts` verifying correct counting, host normalization to lowercase, sorting by count desc then name asc, and limit truncation. VERIFY: `cd backend && python3 -m pytest tests/test_link_extract.py -q`. (cat:test; multifile:no) [feat:shrike-notify-20261124-add-the-links-router-create-backend-app-]
- [ ] [T2] backend/app/routers/links.py — Create router with `GET /{topic}/links` endpoint accepting `topic: str = Depends(require_topic_and_auth)` and `limit: int = Query(10, ge=1, le=50)`, fetching history via `broker.history(topic, limit=None)`, and returning the specified JSON structure with 401/422 responses. VERIFY: `cd backend && python3 -c "from app.routers.links import router; print(router.routes[0].path)"`. (cat:endpoint; multifile:no) [feat:shrike-notify-20261124-add-the-links-router-create-backend-app-]
- [ ] [T2] backend/tests/test_links_router.py — Create test file with local FastAPI app mounting the links router, patching `broker.history` with AsyncMock to return two Message objects (one with link, one without), asserting `messages_with_links == 1` and `hosts == [{'host': 'example.com', 'count': 1}]`, plus tests for empty history, `limit=0` returning 422, and invalid topic returning 422. VERIFY: `cd backend && python3 -m pytest tests/test_links_router.py -q`. (cat:test; multifile:no) [feat:shrike-notify-20261124-add-the-links-router-create-backend-app-]
- [ ] [T3] backend/app/routers/__init__.py — Import `links` router from `app.routers.links` and include it in the main router aggregation if applicable, or ensure it is importable for external mounting. VERIFY: `cd backend && python3 -c "from app.routers import links; print('ok')"`. (cat:refactor; multifile:no) [feat:shrike-notify-20261124-add-the-links-router-create-backend-app-]

# --- 27B-decomposed from roadmap [2026-11-24]: Wire the links router - in `backend/app/main.py` add `links` to the existing `from app.rou (review + tweak) [feat:shrike-notify-20261124-wire-the-links-router-in-backend-app-mai] ---
- [ ] [T3] backend/app/routers/links.py — Add `router = APIRouter()` and a `GET /{topic}/links` endpoint that returns 422 for invalid topic slugs. VERIFY: `cd backend && python3 -c "from app.routers.links import router; print(router.routes[0].path)"`. (cat:endpoint; multifile:no) [feat:shrike-notify-20261124-wire-the-links-router-in-backend-app-mai]
- [ ] [T3] backend/app/main.py — Add `links` to the `from app.routers import ...` line and add `app.include_router(links.router)` directly after `app.include_router(export.router)`. VERIFY: `cd backend && python3 -c "from app.main import app; assert '/{topic}/links' in app.openapi()['paths']"`. (cat:endpoint; multifile:no) [feat:shrike-notify-20261124-wire-the-links-router-in-backend-app-mai]
- [ ] [T2] backend/tests/test_links_wired.py — Create file with `test_links_route_registered` asserting `/{topic}/links` is in `app.openapi()['paths']`. VERIFY: `cd backend && python3 -m pytest tests/test_links_wired.py::test_links_route_registered -q`. (cat:test; multifile:no) [feat:shrike-notify-20261124-wire-the-links-router-in-backend-app-mai]
- [ ] [T2] backend/tests/test_links_wired.py — Add `test_links_rejects_a_bad_topic` asserting `TestClient(app).get('/bad$topic/links')` returns 422. VERIFY: `cd backend && python3 -m pytest tests/test_links_wired.py::test_links_rejects_a_bad_topic -q`. (cat:test; multifile:no) [feat:shrike-notify-20261124-wire-the-links-router-in-backend-app-mai]
