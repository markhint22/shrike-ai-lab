# AGENTS.md — shrike-notify

Topic pub/sub notification service (ntfy-style): `POST /{topic}` to publish, SSE `GET /{topic}/sse`
to subscribe, scoped HMAC bearer tokens, in-memory broker + per-topic history, token-bucket rate
limit. Part of the Shrike suite (the notification bus other tools publish alerts to).

**Stack:** FastAPI (Python 3.11), no frontend. Deploys on Railway (Dockerfile + railway.toml).

## Repo map (where things live)
- `backend/app/config.py` — `Settings` (env-driven: signing secret, require_auth, limits).
- `backend/app/models.py` — pure helpers: `validate_topic`, `normalize_priority`, `parse_tags`,
  `Message` dataclass, `PRIORITY_LEVELS`; `ValidationError`.
- `backend/app/schemas.py` — `PublishRequest` (Pydantic v2 request model + bounds).
- `backend/app/services/auth.py` — HMAC token `issue_token`/`verify_token`/`token_allows` (format `scope.<hexsig>`).
- `backend/app/services/broker.py` — in-memory pub/sub: `subscribe`/`unsubscribe`/`publish`/`history`/`subscriber_count`/`build_message`.
- `backend/app/services/ratelimit.py` — `RateLimiter` token bucket (`allow(key, now)`).
- `backend/app/routers/{publish,subscribe,messages}.py` — endpoints; `main.py` — app wiring, CORS, health.
- `backend/tests/` — pytest (TestClient + async).

## Commands (exact)
- Test: `cd backend && .venv/bin/pytest -q --no-cov` (pytest-asyncio for `async def` tests; pytest-cov installed).
- Run: `cd backend && .venv/bin/uvicorn app.main:app --port 8080`.
- No typecheck (pure Python). Health: `GET /health` → `{"status":"ok","service":"shrike-notify"}`.

## Conventions
- Pydantic **v2** (`field_validator`, `model_validator`, `Field(...)` bounds) — validation errors must surface as HTTP **422**, auth failures **401**, rate-limit **429**, unknown route **404**.
- Topic names go through `validate_topic` (charset + length); never trust a raw path segment.
- **Structured logging** via `logging.getLogger(__name__)` — never `print`; never log message bodies (payload leak).
- Tests: `TestClient(app)`; for auth-mode tests `monkeypatch` `get_settings` in BOTH `routers.publish` and `routers.subscribe`.
- Keep pure logic (models/broker/ratelimit/auth) free of framework/DB deps so it stays unit-testable.

## Env vars
`NOTIFY_SIGNING_SECRET` (MUST NOT be the `dev-insecure-secret` default in prod), `NOTIFY_REQUIRE_AUTH`
(only `"1"` = true), `NOTIFY_MAX_MESSAGE_LENGTH` (4096), `NOTIFY_MAX_TOPIC_LENGTH` (64),
`NOTIFY_HISTORY_SIZE` (100), `NOTIFY_RATE_LIMIT_MAX` (60), `NOTIFY_RATE_LIMIT_WINDOW`.

## Gotchas
- Broker is **in-memory** — history is lost on restart and not shared across workers (DB persistence is a Claude-owned item).
- SSE subscriber queue is currently unbounded (slow-consumer DoS risk — bounding is pending).
- Tokens are eternal/unrevocable in v1 (expiry/revocation pending).
- `history(limit=0)` must return `[]` (an `items[-0:]` bug returned the whole history).
- `POST /tokens` is intentionally unauthenticated when `require_auth` is off — document, don't "fix" blindly.
