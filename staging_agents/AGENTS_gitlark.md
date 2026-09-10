# AGENTS.md — GitLark

GitHub-workspace + AI-conversation app. **Stack:** FastAPI (Python 3.11, async SQLAlchemy 2.0, Postgres) backend + **Vue 3 + Pinia + Vite + TypeScript + Tailwind** web SPA. Native iOS (SwiftUI) / Android (Compose) exist but are out of scope here — work in `backend/` and `web/`.

## Repo map

```
backend/app/
  main.py            entry: app factory, router registration, APScheduler init
  core/              config.py (pydantic-settings), database.py (async engine, get_db),
                     security.py (JWT create/verify), dependencies.py (get_current_user),
                     circuit_breaker.py, response_formatter.py, api_versioning.py
  models/            SQLAlchemy ORM. base.py defines Base + GUID (portable UUID type)
  schemas/           Pydantic v2 request/response models (app/schemas re-exports)
  routers/           HTTP endpoints, one file per domain (auth, workspaces, github,
                     metadata, conversations, agents, billing, code_review, ...)
  services/          business logic (github.py, metadata.py, scheduler.py, user.py, ...)
backend/alembic/versions/   migrations (001..006), numeric-prefixed
web/src/
  pages/             route views (HomePage.vue, DashboardPage.vue, ConversationDetailPage.vue, ...)
  components/        reusable UI (.vue)
  stores/            Pinia setup-stores (auth.ts, workspace.ts, conversation.ts, analytics.ts)
  services/api.ts    axios instance + JWT interceptor (single API client — always use it)
  router.ts          vue-router routes + auth guards (meta.requiresAuth)
```

Backend route prefixes: `/api/auth`, `/api/workspaces`, `/api/github`, `/api/metadata`, `/api/conversations`, `/api/agents`, `/api/billing`.

## Commands

Run from repo root unless noted. First-time: `make setup` (Docker Postgres + venv + deps + migrate). Daily: `make start` → backend :8000 (docs /docs), web :5173.

**Backend** (`cd backend`):
```bash
pytest                          # test suite
pytest tests/test_x.py -k name  # single test
alembic upgrade head            # apply migrations
alembic revision -m "msg"       # new migration (then edit up/down)
uvicorn app.main:app --reload   # run API (or: make backend-dev)
```
**Web** (`cd web`):
```bash
npm run dev          # vite dev server :5173
npm run build        # vite production build
npm run test         # vitest (happy-dom); files: src/**/__tests__/*.test.ts
npm run lint         # eslint --fix (.vue,.js,.ts)
npm run type-check   # vue-tsc --noEmit -p tsconfig.app.json  (SEE GOTCHAS — currently red)
```

## Conventions

- **Routers:** `APIRouter(prefix="/api/x", tags=["x"], redirect_slashes=False)`. Inject DB with `db: AsyncSession = Depends(get_db)`, auth with `Depends(get_current_user)`. Raise `HTTPException(status_code=status.HTTP_*, detail=...)` — never return bare error dicts. `async def` everywhere (async engine).
- **Models:** subclass `Base`; PK `id = Column(GUID, primary_key=True, default=uuid.uuid4)` — use the `GUID` type from `app/models/base.py`, not raw `String`/`UUID` (portable across Postgres/sqlite). Timestamps `created_at`/`updated_at` (`default=datetime.utcnow`, `onupdate=` on updated_at). Relationships via `relationship(..., back_populates=...)`.
- **Schemas:** Pydantic v2. Use `field_validator`/`model_validator`; `ConfigDict(from_attributes=True)` for ORM reads. Keep request/response schemas separate.
- **Migrations:** numeric prefix (`00N_desc.py`), correct `revision`/`down_revision`, always write `downgrade()`. Postgres-only DDL must be guarded so sqlite (tests) is a no-op — see `003_fix_uuid_types.py`.
- **Logging:** Python `logging` (module logger), structured; never `print`.
- **Pinia stores:** setup-store style — `defineStore('name', () => { const x = ref(...); const g = computed(...); async function act(){...}; return {...} })`. All HTTP through `@/services/api` (axios, auto-attaches `Bearer` from `localStorage.token`); try/catch and surface `e.response?.data?.detail`.
- **Vue components:** `<script setup lang="ts">`. Always `type="button"` on non-submit `<button>`s. Import with the `@/` alias (→ `src/`). Tailwind utilities.
- **Auth flow:** GitHub OAuth → backend mints JWT (HS256) → web stores token in `localStorage`; router guards check `meta.requiresAuth`.

## Key external APIs + env vars

Backend (`backend/.env`, see `.env.example`):
- `DATABASE_URL` — `postgresql+asyncpg://...` (async driver required; sqlite+aiosqlite for tests)
- `GITHUB_CLIENT_ID` / `GITHUB_CLIENT_SECRET` / `GITHUB_OAUTH_REDIRECT_URL` — GitHub OAuth
- `ANTHROPIC_API_KEY` — Claude for AI conversations
- `SECRET_KEY` + `ALGORITHM=HS256` + `ACCESS_TOKEN_EXPIRE_MINUTES` — JWT
- `STRIPE_*` — billing; `CORS_ORIGINS` (comma-sep); `RATE_LIMIT_ENABLED` (slowapi)

Web: `VITE_API_URL` (base for the axios client; falls back to `/api`).

## Gotchas

- **`npm run type-check` is currently RED:** a syntax error in `web/src/router.ts` — a merge left a stray `import TermsPage ...` and orphaned route-object literals *after* `export default router`. Fix router.ts (import at top, route inside the `routes` array, before the default export) for a clean typecheck. (tsconfig.app.json is present; earlier "missing" notes are stale.)
- **Async DB driver:** `postgresql+asyncpg` / `sqlite+aiosqlite` need `asyncpg`/`aiosqlite` (present) — a missing driver = silent 502 with no logs.
- **`app/schemas`** is the public schema surface; import from there when a re-export exists.
- Many `PHASE_*` / `*_ROADMAP*` docs are stale — treat code as truth.
- Two Android namespaces (`com.gitlark`, `com.shrikelabs.gitlark`) exist in-tree — irrelevant to backend/web.
