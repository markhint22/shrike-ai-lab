# AGENTS.md — gitlark

**gitlark is a mobile-first tool to talk to your repos, plan projects, and dispatch the build-out to the
overnight 27B fleet — then review the resulting PRs.** The phone-side command center for the Shrike dev
system. **It is NOT a PR/code-review tool** — that was an old mis-framing; do NOT build code-review
features. See `GITLARK_V2_PLAN.md`. Direction: **PWA / responsive-web first** (fast path to testable),
then native iOS + Android over the same backend.

The core loop: connect a repo → **talk** (AI grounded in the code) → **plan** (goal → routed task list in
the fleet's item format) → **dispatch** (commit tasks to the repo's `OVERNIGHT_PROGRESS.md` on
`overnight/feature` via the GitHub API; the fleet builds them) → **review** (read the fleet's commits/PRs
back via GitHub, approve/merge in-app).

**Stack:** FastAPI (Python 3.11, async SQLAlchemy 2.0, Postgres) backend + Vue 3 + Pinia + Vite + TS web
(being rebuilt as a mobile-first PWA). Native iOS/Android come later (P5).

## Repo map
```
backend/app/
  main.py            entry: app factory, router registration
  core/              config.py (pydantic-settings), database.py (async get_db), security.py (JWT),
                     dependencies.py (get_current_user)
  models/            SQLAlchemy ORM (base.py: Base + GUID portable UUID). Plan/PlanTask are new (v2).
  schemas/           Pydantic v2 request/response (plan.py is new)
  routers/           HTTP endpoints per domain (auth, projects[=workspaces], github, conversations,
                     agents, billing). NEW: plan/dispatch/builds endpoints.
  services/          github.py (OAuth + repo access — REUSE), the conversation/AI engine (REUSE, reorient
                     to PLANNING), repo analysis/ast (REUSE = grounding). NEW: planner_*, dispatch_*.
web/src/
  pages/             route views — being reorganized to Projects / Conversation(home) / Plan / Builds / Settings
  stores/            Pinia setup-stores (auth, conversation/plans, ...)
  services/api.ts    axios client (single API client — always use it)
  router.ts          vue-router + auth guards
```

## Commands
Backend (`cd backend`): `pytest` · `pytest tests/test_x.py -k name` · `alembic upgrade head` · `uvicorn app.main:app --reload`.
Web (`cd web`): `npm run dev` · `npm run build` · `npm run test` (vitest) · `npm run lint` · `npm run type-check` (vue-tsc — currently ~42 real errors, a Claude batch).

## Conventions
- **Routers** `APIRouter(prefix="/api/x")`, `async def`, DB via `Depends(get_db)`, auth via `Depends(get_current_user)`; raise `HTTPException(status_code=status.HTTP_*, detail=...)`.
- **Models** subclass `Base`; PK `id = Column(GUID, ...)` (use the `GUID` type, not raw String/UUID); every model change → an Alembic migration (guard Postgres-only DDL so sqlite tests no-op).
- **Schemas** Pydantic v2 (`field_validator`/`model_validator`, `ConfigDict(from_attributes=True)`).
- **Pinia** setup-store style; all HTTP via `@/services/api`; try/catch + surface `e.response?.data?.detail`.
- **Vue** `<script setup lang="ts">`; `type="button"` on non-submit buttons; `@/` alias → `src/`.
- **The Planner** must emit tasks in the FLEET's item format: `- [ ] [T2] <repo-root-relative path> — <spec>. VERIFY: <check>. (tag)`, tier-tagged, routed 27b/claude/human. Keep the pure planner helpers (planner_format/route/tier, dispatch_status/dedup) framework-free so they're unit-testable.
- **The dispatcher** is git-mediated: write to the target repo's `OVERNIGHT_PROGRESS.md` on `overnight/feature` via the GitHub API; tag each task with a plan/task id in the commit message for status matching; dedup against existing progress lines.

## Key env vars
`DATABASE_URL` (`postgresql+asyncpg://`), `GITHUB_CLIENT_ID/SECRET/OAUTH_REDIRECT_URL` (OAuth — needs
**contents:write** scope for the dispatcher), `ANTHROPIC_API_KEY` (the planner's brain — decision pending,
see HUMAN_QUEUE), `SECRET_KEY`/`ALGORITHM=HS256`, `STRIPE_*`, `CORS_ORIGINS`, web `VITE_API_URL`.

## Gotchas
- **Do NOT build PR/code-review features** — repurpose the "review agents" into planning/build-out. If you see a task implying code-review-as-the-product, it's stale; skip it.
- `npm run type-check` is red (~42 real TS errors) — a Claude batch, not a 27B item.
- Async DB driver required (`asyncpg`/`aiosqlite`) or the app 502s silently at startup.
- The fabricated native fragments (`mobile/ios`, `mobile/android`, top-level `ios/`+`android/`, a `.tsx`
  containing Kotlin) are being DELETED (P0) — real native apps come in P5 over this same backend.
- Stale `PHASE_*` / `COMPLETION_SUMMARY` / "code review tool" docs — treat code + `GITLARK_V2_PLAN.md` as truth.
