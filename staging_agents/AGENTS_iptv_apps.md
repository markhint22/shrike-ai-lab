# AGENTS.md — Chickadee Streams (iptv_apps)

Multi-platform IPTV app. **Fleet scope = `iptv-backend` (FastAPI) + `iptv-web` (Vue 3 / Vite / TypeScript) only.**
`iptv-ios/` (SwiftUI+tvOS) and `iptv-android/` (Compose+Hilt) are **out of scope** — never edit them.

## Repo map
```
iptv-backend/            FastAPI backend (async SQLAlchemy 2.0 + Pydantic v2)
  app/main.py            app entry, router registration, CORS
  app/database.py        async engine / get_db
  app/core/              config, security
  app/models/            SQLAlchemy models (16)
  app/schemas/           Pydantic schemas (13)
  app/routers/           API routes (22: auth, streams, discover, epg, subscription, parental, profiles, search, ...)
  app/services/          business logic (24: revenuecat, tmdb, playlist, m3u_validator, stream_checker, premium, ...)
  app/jobs/              APScheduler background jobs
  alembic/               DB migrations
iptv-web/src/
  views/                 page components (HomeView, PlayerView, DiscoverView, SubscriptionView, ... 20)
  components/            shared (PaywallModal, AppHeader, StreamFilterBar, OnboardingWalkthrough, ...)
  stores/                Pinia stores (auth, streams, subscription, epg, parental, profiles, ...)
  services/              api.ts (axios), revenuecat.ts
  tv/                    TV/remote spatial-navigation (see Gotchas)
  router/ i18n/ types/ utils/ assets/
```

## Commands
Backend (`cd iptv-backend`, venv active):
- Test: `pytest` (or `make test-backend` from root)
- Run: `uvicorn app.main:app --reload` (or `make backend`)
- Lint: `pylint app/`
- Migration after model change: `alembic revision --autogenerate -m "..."` then `alembic upgrade head`

Web (`cd iptv-web`):
- Typecheck: `npm run type-check` (`vue-tsc --noEmit`) — **iptv-web is currently type-clean; keep it that way.**
- Unit test: `npm run test` (vitest) / `npm run test:run` (CI, no watch)
- Lint: `npm run lint` (eslint --fix)
- Build: `npm run build` (runs `vue-tsc --noEmit` then `vite build`)
- E2E: `npm run test:e2e` (Playwright; slower, not needed for most changes)

## Conventions
Backend:
- Routers: `async def` handlers, `db: AsyncSession = Depends(get_db)`, `current_user: User = Depends(get_current_user)`.
- Schemas: Pydantic v2 `BaseModel` with `Field(...)` and `@field_validator`; use `str, Enum` classes for closed value sets (see `schemas/subscription.py`).
- Models: SQLAlchemy 2.0 typed `Mapped[...]` / `mapped_column`.
- Structured logging: `logger = logging.getLogger(__name__)` — no `print`.
- Register new routers in `app/main.py`.

Web:
- Vue 3 **Composition API** + `<script setup lang="ts">` only (never Options API).
- Pinia stores use the setup style (`ref` + functions, `return {...}`).
- All API calls go through `services/api.ts` (axios instance), not raw fetch.
- Modals: `role="dialog"` + focus handling (see `OnboardingWalkthrough.vue`, `PaywallModal.vue`).
- Every `<button>` needs explicit `type="button"` unless it submits a form.
- Keep strict TS types; add to `src/types/index.ts` rather than using `any`.

## External APIs + env vars
Backend (`.env`, see `.env.example`):
- `DATABASE_URL` (async: `postgresql+asyncpg://...` — asyncpg required and present)
- `JWT_SECRET_KEY`, `ACCESS_TOKEN_EXPIRE_MINUTES`, `REFRESH_TOKEN_EXPIRE_DAYS`
- `CORS_ORIGINS`, `REDIS_URL`, `RATE_LIMIT_*`, `SENTRY_DSN`, `LOG_LEVEL`
- Integrations: Stripe (`services/subscription.py`), RevenueCat (`services/revenuecat.py`), TMDB (`services/tmdb.py`), Apple/Google receipt validation, Supabase.

Web (`iptv-web/.env.production`):
- `VITE_API_URL` — backend base URL (must end in `/api`).
- `VITE_REVENUECAT_API_KEY` — RevenueCat **public/browser SDK key**; safe to ship in the client bundle. Never put Stripe/RevenueCat *secret* keys in web.

## Gotchas
- **`VITE_API_URL` must point at the working Railway backend**: `https://chickadeestream-production.up.railway.app/api`. The pretty custom domains (`app.chickadeestreams.app`, `api.chickadeestream.com`) have no DNS and 000 — don't switch to them.
- Backend is **async SQLAlchemy** end to end; any DB call must be awaited with an `AsyncSession`. A missing `await` or sync driver URL causes silent startup 502s.
- **`src/tv/` spatial-navigation** (`spatialNavigation.ts`, `useSpatialNavigation.ts`, `remoteKeys.ts`) powers D-pad/remote focus for the TV build (`npm run build:tv`, `VITE_TV_MODE=1`). Intricate + well-tested — read the sibling `*.test.ts` before touching, keep tests green.
- After any model change, generate + apply an Alembic migration or prod deploy breaks.
- The 22 routers must be registered in `main.py`; adding a router file alone does nothing.
- Run `npm run type-check && npm run test:run` before considering web work done (broad vitest + Playwright + @axe-core suites).
