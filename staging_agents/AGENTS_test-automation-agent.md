# AGENTS.md — SpecPilot (test-automation-agent)

AI-powered UI test-automation SaaS: customers upload YAML test plans; Claude agents orchestrate/execute/analyze/optimize Playwright runs.
**Stack:** FastAPI + SQLAlchemy(async) + Alembic + Postgres (backend, heavily tested) · Vue 3 + Vite + Pinia + Tailwind (frontend, thin — current release focus) · Anthropic + Stripe · deploys on Fly.

## Repo map
```
backend/app/
  main.py            FastAPI entry (mounts routers, CORS, catch-all guard)
  core/              config.py (Settings/env), auth.py (JWT), api_auth.py (API keys), database.py
  routers/           endpoints: auth, test_runs, test_plans, uploads, usage, billing, orgs,
                     api_keys, ci, flakes, webhooks, public_api, websocket, artifacts
  services/          execution_engine, playwright_service, llm_service (tier→model), knowledge_base,
                     billing, scheduling, flake_detection, self_healing, tenancy, notification_*, github_ci
  agents/            orchestrator, executor, analyzer, optimizer
  models/            SQLAlchemy: test_run, billing, ci, tenancy, api_key
  utils/             small pure helpers (each has a focused unit test)
backend/alembic/versions/   001..008 migrations
backend/tests/              pytest — one narrow test file per behavior (dense coverage)
frontend/src/
  pages/    Dashboard, TestRuns, TestRunDetail, Upload, TestPlanEditor, Login, Signup, Terms, Privacy
  stores/   auth.ts, testRuns.js  (Pinia, setup-style)
  router/   index.js  (routes + beforeEach auth guard, meta.requiresAuth)
frontend/tests/   vitest unit + e2e/*.spec.ts (see gotchas)
fly.toml · Dockerfile · backend/entrypoint.sh (alembic upgrade head → uvicorn)
```

## Commands
Backend (from repo root; most targets `cd backend`):
```bash
make install        # pip install -r backend/requirements.txt
make verify         # import-smoke: python -c "from app.main import app"
make dev            # docker-compose postgres + uvicorn --reload :8000
make test           # cd backend && pytest tests/ -v --tb=short
make lint           # cd backend && ruff check app/ && mypy app/
make db-upgrade     # alembic upgrade head    (db-migrate = autogenerate revision)
```
Frontend (`cd frontend`):
```bash
npm install
npm run dev         # vite
npm run build       # vite build  (ALSO the real typecheck gate — no separate tsc/vue-tsc)
npm run test        # vitest run --passWithNoTests
npm run lint        # eslint --fix
```
No `tsc`/`vue-tsc` step: `.ts` is transpiled (not type-checked) by Vite/esbuild. Rely on `npm run build` + eslint.

## Conventions
- **Backend:** async everywhere (`async def`/`await`/asyncpg). Config via `core/config.py` `Settings` (pydantic-settings) — never hardcode secrets/URLs; read `settings.*`. Pydantic v2 models (often inline in routers); validate with `field_validator`. Auth = JWT (`core/auth.py`) or API key (`core/api_auth.py`); org scoping via `utils/org_scoping`/`rbac`. New table → Alembic migration.
- **Frontend:** Vue 3 `<script setup>` for all pages/App (Options API only in PrivacyPage — don't copy). Pinia **setup-style** stores (see `stores/auth.ts`). API via `axios`, base `import.meta.env.VITE_API_URL || '/api'`; auth store injects `Bearer` via interceptor + persists token/org_id to localStorage. Tailwind; every `<button>` needs `type="button"` unless it submits. Modals get `role`/`aria-*`. Handle all four UI states: loading, empty, error, success.

## External APIs & env vars
- **Anthropic** (`llm_service`): `ANTHROPIC_API_KEY`; `DEFAULT_MODEL` (haiku) / `SONNET_MODEL`.
- **Stripe** (test-mode, gated on key): `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, `STRIPE_PRICE_PRO`, `STRIPE_PRICE_ENTERPRISE`, `STRIPE_SUCCESS_URL`, `STRIPE_CANCEL_URL`.
- **Auth/JWT:** `SECRET_KEY` (non-default in prod), `ALGORITHM` (HS256), `ACCESS_TOKEN_EXPIRE_MINUTES`.
- **DB:** `DATABASE_URL` (auto-normalized to `postgresql+asyncpg://`). Also `CORS_ORIGINS`, `GITHUB_TOKEN`/`GITHUB_WEBHOOK_SECRET`, SMTP_*, `PLAYWRIGHT_HEADLESS`, `MAX_CONCURRENT_BROWSERS`.
- Frontend: `VITE_API_URL` (prod → `https://specpilot.fly.dev/api`).

## Gotchas
- **Status vocabulary is layered — don't conflate.** Run-level `TestRunStatus` = `pending|running|completed|failed|cancelled` (there is **no** `success`). Result-level = `passed|failed|skipped`. Webhook delivery = `delivered|failed|pending`. A `completed` run can hold `failed` results. Match the exact enum for the layer.
- **Fly deploy is human-gated** — `git push` does not ship. Prod `specpilot.fly.dev`; `entrypoint.sh` runs `alembic upgrade head` on boot, so a bad/dup migration blocks startup. GitHub Actions disabled fleet-wide — verify locally.
- **Auth UI EXISTS** (LoginPage/SignupPage + `stores/auth.ts` + router guard). Login posts `/api/auth/login-user`, signup `/api/auth/signup`. (Docs claiming "no login UI" are stale.)
- **e2e specs aren't wired:** `frontend/tests/e2e/*.spec.ts` are Playwright-shaped but Playwright isn't a frontend dep — won't run via npm. Aspirational until wired.
- `app/agents/*` are partially stubbed — check for `TODO`/`NotImplemented` before assuming a method is wired into `execution_engine`.
- Backend >> frontend maturity: many backend features have no UI yet — frontend release work = surfacing them.
