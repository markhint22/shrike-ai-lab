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
- [ ] [T1] backend/scripts/token_mint.py — Add `--scope` argument to accept either `*` or a specific topic slug, validating against the known fleet taxonomy (`fleet_*_deploy`, `fleet_queue_task`, `fleet_queue_promote`). VERIFY: `pytest backend/tests/test_token_mint.py::test_scope_validation -v`. (cat:python; multifile:no) [feat:shrike-notify-20260921-token-minting-rotation-helper-for-automa]
- [ ] [T1] backend/scripts/token_mint.py — Implement `mint_tokens(scopes: list[str])` function that generates a batch of tokens for the provided scopes, returning a dict mapping scope to token. VERIFY: `pytest backend/tests/test_token_mint.py::test_mint_tokens_batch -v`. (cat:python; multifile:no) [feat:shrike-notify-20260921-token-minting-rotation-helper-for-automa]
- [ ] [T2] backend/scripts/token_mint.py — Add `--rotate` flag that accepts an existing token hash and issues a new token for the same scope, invalidating the old one. VERIFY: `pytest backend/tests/test_token_mint.py::test_rotate_token -v`. (cat:python; multifile:no) [feat:shrike-notify-20260921-token-minting-rotation-helper-for-automa]
- [ ] [T1] backend/scripts/token_mint.py — Add `--list-topics` flag that outputs the standard fleet topic taxonomy (`fleet_<repo>_deploy`, `fleet_queue_task`, `fleet_queue_promote`) for operator reference. VERIFY: `pytest backend/tests/test_token_mint.py::test_list_topics_output -v`. (cat:python; multifile:no) [feat:shrike-notify-20260921-token-minting-rotation-helper-for-automa]
- [ ] [T3] backend/scripts/token_mint.py — Update CLI entry point to support both single wildcard minting and multi-topic per-topic minting, printing clear security posture warnings for each choice. VERIFY: `pytest backend/tests/test_token_mint.py::test_cli_scope_warning -v`. (cat:python; multifile:no) [feat:shrike-notify-20260921-token-minting-rotation-helper-for-automa]
- [ ] [T1] backend/tests/test_token_mint.py — Add test cases verifying that wildcard scope (`*`) triggers a security warning message about blast radius. VERIFY: `pytest backend/tests/test_token_mint.py::test_wildcard_security_warning -v`. (cat:test; multifile:no) [feat:shrike-notify-20260921-token-minting-rotation-helper-for-automa]
- [ ] [T1] backend/tests/test_token_mint.py — Add test cases verifying that per-topic scope generation produces distinct tokens for each topic in the fleet taxonomy. VERIFY: `pytest backend/tests/test_token_mint.py::test_per_topic_distinct_tokens -v`. (cat:test; multifile:no) [feat:shrike-notify-20260921-token-minting-rotation-helper-for-automa]
- [ ] [T1] backend/scripts/token_mint.py — Add `--json` output flag to emit minted tokens as JSON for programmatic consumption by automation clients. VERIFY: `pytest backend/tests/test_token_mint.py::test_json_output_format -v`. (cat:python; multifile:no) [feat:shrike-notify-20260921-token-minting-rotation-helper-for-automa]
- [ ] [T2] backend/scripts/token_mint.py — Implement `--dry-run` mode that prints the intended actions without persisting tokens to the database. VERIFY: `pytest backend/tests/test_token_mint.py::test_dry_run_no_persist -v`. (cat:python; multifile:no) [feat:shrike-notify-20260921-token-minting-rotation-helper-for-automa]
- [ ] [T1] backend/README.md — Add a "Token Management" section documenting the wildcard vs per-topic scope tradeoff, with examples for both automation patterns. VERIFY: `grep -q "wildcard.*per-topic\|blast radius" backend/README.md`. (cat:docs; multifile:no) [feat:shrike-notify-20260921-token-minting-rotation-helper-for-automa]

# --- 27B-decomposed from roadmap [2026-09-21]: Actually persist token revocation so it survives a restart — add a `revoked`/`revoked_at`  (review + tweak) [feat:shrike-notify-20260921-actually-persist-token-revocation-so-it-] ---
- [ ] [T1] backend/app/models.py — Add `revoked` (Boolean, default False) and `revoked_at` (DateTime, nullable) columns to the `Token` model. VERIFY: `python -c "from backend.app.models import Token; assert 'revoked' in Token.__table__.columns and 'revoked_at' in Token.__table__.columns"`. (cat:schema; multifile:no) [feat:shrike-notify-20260921-actually-persist-token-revocation-so-it-]
- [ ] [T2] backend/app/persistence.py — Modify `TokenStore.revoke_token()` to set `token.revoked = True` and `token.revoked_at = datetime.utcnow()` instead of calling `session.delete(token)`. VERIFY: `pytest backend/tests/test_persistence.py::test_revoke_token_flags_row -v`. (cat:python; multifile:no) [feat:shrike-notify-20260921-actually-persist-token-revocation-so-it-]
- [ ] [T3] backend/app/persistence.py — Modify `TokenStore.get_revoked_token_ids()` to query the database for tokens where `revoked == True` and return their IDs, removing reliance on the in-memory `_revoked_ids` set. VERIFY: `pytest backend/tests/test_persistence.py::test_get_revoked_token_ids_from_db -v`. (cat:python; multifile:no) [feat:shrike-notify-20260921-actually-persist-token-revocation-so-it-]
- [ ] [T4] backend/tests/test_persistence.py — Add a regression test that creates a token, revokes it, closes the `TokenStore`, opens a new independent `TokenStore` instance against the same DB file, and asserts `get_revoked_token_ids()` contains the revoked token ID. VERIFY: `pytest backend/tests/test_persistence.py::test_revocation_survives_restart -v`. (cat:test; multifile:no) [feat:shrike-notify-20260921-actually-persist-token-revocation-so-it-]
- [ ] [T5] backend/app/persistence.py — Ensure `TokenStore.startup_check()` or equivalent initialization logic loads revoked token IDs from the database into the in-memory cache if it still maintains one for fast lookup, or ensure the auth service queries the DB directly. VERIFY: `pytest backend/tests/test_integration_auth_persist.py::test_startup_loads_revoked_tokens -v`. (cat:python; multifile:no) [feat:shrike-notify-20260921-actually-persist-token-revocation-so-it-]
