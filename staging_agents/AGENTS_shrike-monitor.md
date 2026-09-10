# AGENTS.md — shrike-monitor

Uptime + heartbeat (dead-man's-switch) monitoring service. Registers monitors (http or heartbeat),
records check results, computes status/uptime, and (planned) publishes alerts to shrike-notify.
Part of the Shrike suite; intended to replace the ad-hoc deploy_watch/deploy_health scripts.

**Stack:** FastAPI (Python 3.11), no frontend. Deploys on Railway (Dockerfile + railway.toml).

## Repo map (where things live)
- `backend/app/models.py` — pure logic: `classify_http`, `heartbeat_overdue`, `uptime_ratio`,
  `summarize_status`, `Monitor`/`CheckResult` dataclasses, `validate_name`, `ValidationError`.
- `backend/app/schemas.py` — `MonitorCreate`, `StatusOut` (Pydantic v2).
- `backend/app/services/checker.py` — `probe()` (does one HTTP check, injectable `fetch`).
- `backend/app/store.py` — in-memory `Store` (monitors + results; `create`/`results`/`delete`).
- `backend/app/routers/{monitors,heartbeat}.py` — endpoints; `main.py` — wiring, CORS, health.
- `backend/tests/` — pytest (TestClient + injectable clock/fetch for determinism).

## Commands (exact)
- Test: `cd backend && .venv/bin/pytest -q --no-cov` (pytest-asyncio + pytest-cov installed).
- Run: `cd backend && .venv/bin/uvicorn app.main:app --port 8080`. Health: `GET /health`.
- No typecheck (pure Python).

## Conventions
- Keep the decision logic **pure** in `models.py` (inject `now`/clock and `fetch` so tests are deterministic, no real sleeps/network).
- Pydantic **v2** bounds/validators; validation → **422**, not-found → **404**, bad request → **400**.
- **Structured logging** (`logging.getLogger(__name__)`), never `print`.
- Status vocabulary: `pending` (never checked) / `up` / `degraded` (ok but slow vs `degraded_latency_ms`) / `down`.
- Bound resources (cap monitors/results) — this is a public-ish write API.

## Env vars
`CORS_ORIGINS` (comma-sep, default `*`), `MAX_RESULTS` (100), `MAX_MONITORS` (1000),
`SERVICE_VERSION`, `PORT`, `SHRIKE_NOTIFY_URL` (for the planned notifier).

## Gotchas
- **Known correctness bug (top backlog item):** the `/monitors/{id}/status` endpoint uses
  `summarize_status` for ALL types, so a **heartbeat monitor never reports "down" when overdue** —
  the dead-man's-switch is defeated. Fix routes heartbeat monitors through a `heartbeat_status`/`overall_status` dispatch.
- Store is **in-memory** (monitors/results lost on restart — DB persistence is a Claude item).
- There is **no scheduler yet** — nothing actively probes on an interval or flips overdue heartbeats;
  that async loop + the shrike-notify alert publisher are Claude-owned (the service doesn't truly "monitor" until they land).
- Heartbeat pings are unauthenticated/spoofable in v1 (per-monitor ping token pending).
