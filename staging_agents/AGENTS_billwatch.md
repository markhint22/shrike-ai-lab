# AGENTS.md — BillWatch

Multi-platform federal legislation tracker. **Stack:** FastAPI (async) backend · Vue 3 web · native iOS (SwiftUI) · native Android (Jetpack Compose). Postgres via SQLAlchemy 2.0 async; deployed on Railway (backend) + Vercel (web).

> Work primarily in `billwatch-backend/` and `billwatch-web/`. Mobile is native — no cross-platform framework.

## Repo map
```
billwatch-backend/            FastAPI
  app/
    main.py                   app entry: CORS, exception handlers, include_router (all under /api/*)
    config.py / database.py   Settings (pydantic-settings) + async engine/get_db
    core/                     exceptions, validators, logging, dependencies, rate_limiting, congress
    models/                   SQLAlchemy 2.0 (Mapped[]) — bill, legislator, user, vote, topic, ...
    schemas/                  Pydantic v2 request/response
    routers/                  API routes (bills, legislators, civic, auth, finance, ...) — thin
    services/                 business logic + external API clients (congress_api, fec_api, civic_api, llm_service)
    utils/                    small pure helpers (bill_status, finance_math, relevance, ...)
    jobs/scheduler.py         APScheduler background bill/legislator sync
  alembic/versions/           DB migrations (numbered 001..009)
  tests/                      pytest (conftest.py, test_*.py)
billwatch-web/                Vue 3 + Vite (pkg name "policylogs-web")
  src/{views,pages}/          route-level screens
  src/components/             UI (+ components/modals, components/__tests__)
  src/stores/                 Pinia stores
  src/services/               axios API client layer
  src/{composables,layouts,router,utils,types}/
billwatch-ios/                SwiftUI + MVVM (scheme "PolicyLogs", bundle com.policylogs.app)
billwatch-android/            Compose + Hilt (package com.billwatch, app/src/main/java/com/billwatch/)
```

## Commands
**Backend** (`cd billwatch-backend`):
```bash
pip install -r requirements.txt
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000   # run
pytest                                                     # test (asyncio_mode=auto, --cov=app, term-missing)
pytest tests/test_bills.py -q                              # single file
python -c "from app.main import app; print('imports OK')"  # fast import sanity check (make check-imports)
alembic revision -m "desc" && alembic upgrade head         # migrations
```
No ruff/flake8/mypy config committed — keep style consistent with existing files; the gate is import-check + pytest.

**Web** (`cd billwatch-web`):
```bash
npm install
npm run dev                 # vite dev
npm run test                # vitest --run
npm run build               # vite build
npm run build:typecheck     # vue-tsc && vite build   <-- run this to catch type errors
npm run lint                # eslint --fix (.vue,.ts,.tsx,...)
```
`vue-tsc` is strict: `strict`, `noUnusedLocals`, `noUnusedParameters`, `noFallthroughCasesInSwitch` on. `@/*` → `src/*`.

**Mobile** (rarely): iOS `xcodebuild -scheme PolicyLogs`; Android `cd billwatch-android && ./gradlew test`.

## Conventions
**Backend**
- **Async everywhere.** Routers `async def`; DB via `db: AsyncSession = Depends(get_db)`. Never sync sessions.
- **Layering:** routers stay thin (parse params, auth dep) → call a `Service(db)` in `services/`. Logic in services, not routers.
- **Validation:** Pydantic v2 `@field_validator` on schemas; shared sanitizers in `core/validators.py` (`ValidationError` → JSON envelope handler in `main.py`).
- **Errors:** raise the custom `HTTPException` subclasses in `core/exceptions.py` (`BillNotFound`, `LegislatorNotFound`, `InvalidSearchQuery`, `RateLimitExceeded`, `UnauthorizedAccess`) — don't hand-roll `HTTPException(404, ...)`.
- **Models:** SQLAlchemy 2.0 typed (`id: Mapped[str]`, `mapped_column(...)`). **Any model change REQUIRES a matching Alembic migration** (a prod incident happened from model/DB drift — see `SCHEMA_MIGRATION_INCIDENT_REPORT.md`).
- **Migrations:** UUID columns use `postgresql.UUID(as_uuid=True)` — NOT `String`/`String(36)` (see `004_...`).
- **Logging:** use the logger from `core/logging.py` (`setup_logging`), never `print`.
- **New endpoint:** schema → model+migration if needed → service → thin router → `include_router(..., prefix="/api/...")` in `main.py`.

**Web**
- Vue 3 **Composition API** (`<script setup>`) + Pinia (setup syntax, `ref`/computed).
- All API access via `src/services/` (axios), not scattered `axios` calls.
- Always `type="button"` on non-submit `<button>`s.
- Keep TS clean for `vue-tsc`: no unused locals/params, no implicit any.

## External APIs + env vars
| Service | Env var | Use |
|---|---|---|
| Congress.gov (`api.congress.gov/v3`) | `CONGRESS_API_KEY` | federal bills/legislators/votes (required) |
| OpenFEC | `FEC_API_KEY` | campaign finance |
| Open States | `OPEN_STATES_API_KEY` | state bills/legislators |
| Google Civic | `GOOGLE_CIVIC_API_KEY` | address geocoding (optional) |
| Firebase | `FIREBASE_CREDENTIALS_PATH` | push notifications (optional) |
| Anthropic | (config) | LLM bill summaries via `services/llm_service.py` |

Core backend env: `DATABASE_URL` (must be `postgresql+asyncpg://`), `SECRET_KEY` (differ from default in prod), `APP_NAME`, `APP_URL`, SMTP_*. Web: `VITE_API_URL` (prod → `https://billwatch-production.up.railway.app/api`).

## Gotchas
- `DATABASE_URL` must use **`postgresql+asyncpg://`**; `asyncpg`/`aiosqlite` must be installed or the app 502s silently at startup (they are).
- **Models ≠ database** — `models/` changes do nothing until an Alembic migration is written + applied (start.sh runs migrations on deploy).
- Web package is `policylogs-web` and iOS scheme is `PolicyLogs` (legacy) but Android is `com.billwatch` — product is BillWatch; don't "fix" these without checking.
- Some routers already carry their own `/api/...` prefix (e.g. `bill_chat`, `civic`) and are included WITHOUT a prefix arg — match the existing pattern in `main.py`, don't double-prefix.
- Many near-duplicate service files exist (`notification_service.py` vs `notifications.py`, `caching.py` vs `caching_service.py`) — grep for the one imported in `main.py`/routers before editing.
