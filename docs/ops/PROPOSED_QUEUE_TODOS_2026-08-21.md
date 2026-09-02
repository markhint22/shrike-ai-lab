# Proposed Queue Todos & overnight/feature disposition — 2026-08-21

Review doc from the workspace cleanup + `overnight/feature` salvage pass.
**Nothing here has been added to the overnight queue yet — this is for your review.**
Once you approve, these become `recurring_tasks.json` / one-off `queue.sh add` items.

---

## 1. What already happened (done, no action needed)

**3 dev repos — cleaned & merged to `main`** (deployed; `main == overnight/feature`, drift 0):

| Repo | Result | Tests |
|---|---|---|
| gitlark | QuotaService refactor, dedup, deps landed; dropped broken root test, fixed metadata test properly | backend 196/0, web build green |
| task-manager-platform | vitest fix (unbroke web suite) + approval_api landed; deleted dead `approval_service.py`; fixed misleading progress doc | backend 117/0, web 29/2 (2 pre-existing) |
| test-automation-agent | orchestrator/executor logic landed; dropped redundant test, fixed 7 `AgentContext` tests; also reverted a `.gitignore` regression that was about to commit `.claude`/`.aider` files | backend 375/0 |

**2 production repos — cleaned on a branch, `main` untouched, awaiting your go/no-go** (see §2).

**1 repo — rework, no code landed** (social-media-manager; see §3D).

---

## 2. DECISIONS FOR YOU — the two production merges

### A. billwatch → `salvage/billwatch-clean` (129/0 backend, frontend untouched)
Merging this to `main` auto-deploys the **backend** to Railway (Vercel/frontend unaffected — no frontend changes).

**What would deploy:**
- `POST /api/articles/rank` → 200, gracefully falls back to heuristic ranking when no LLM is reachable.
- `GET /api/bills/{id}/background` → 200, graceful error string when its LLM is unreachable.
- `POST /api/bills/{id}/background` → **500 without a local LLM** (calls Ollama at localhost:11434). Dormant unless the UI calls it.
- New table `bill_backgrounds` auto-created on startup (non-destructive `create_all`); no changes to existing `bills` columns.
- `config.py` adds `llm_inference_url`/`llm_api_key` (empty defaults, degrade gracefully); `requirements.txt` adds `requests`.

**Rough edges (work-but-messy):** `bill_background_service.py` has two concatenated class defs; `article_relevance_service.py` imports a `llm_client` module that doesn't exist yet (so the LLM path never runs — always heuristic).

**Recommendation:** low deploy risk (frontend untouched, new paths degrade gracefully). Either **(a) merge now** and clean the rough edges via queue todos B1–B4 below, or **(b) do B1–B4 on the branch first, then merge.** My lean: option (b) — the two rough edges are quick and it's production.

### B. shrike-labs-website → `salvage/shrike-clean` (build green, 15/15 tests)
The 88-commit branch was **salvaged successfully** — the breakage was mechanical concatenation corruption (duplicate blocks appended repeatedly), not tangled logic. Net diff is +37/−1692 (almost all deletions of dead/duplicated code). ~13 real feature components work.

**Caveat:** only `npm run build` (the Vercel command) + vitest were verified. **No visual QA / Vercel preview / contact-backend check was done.** Merging auto-deploys the live marketing site.

**Recommendation:** do **not** merge to `main` yet. First a Vercel **preview deploy** of `salvage/shrike-clean` + a visual smoke test of every section/route (todo W15). Then promote. The completion work is todos W1–W15.

---

## 3. Proposed queue todos per repo (NOT queued yet)

### A. gitlark (already merged; these are follow-ups)
**P1 — dead-code cleanup (one module per task; grep-confirm no import, delete, re-run 196-test suite):**
1. Delete `backend/app/services/ai_agent_service.py` (0 refs, 0% cov)
2. Delete `backend/app/services/code_review_agent.py` (0 refs)
3. Delete `backend/app/services/github_integration_service.py` (live one is `github.py`)
4. Delete `backend/app/services/realtime_update_service.py` (live one is `realtime_service.py`)
5. Delete `backend/app/services/feature_flags_service.py` (live one is `feature_flags.py`)
6. Delete `backend/app/services/claude_agent.py` (live one is `claude.py`)
7. Delete `backend/app/services/conversation_analytics.py` (0 refs, 0% cov)

**P2 — targeted unit tests, ONE wired service per task:**
8. Tests for `services/metadata.py` (19%; feeds workspace-context injection)
9. Tests for `services/repo_analyzer.py` (47%; core, large surface)
10. Tests for `services/code_review.py` (57%)

**P3 — feature/hardening (narrow):**
11. Rate-limit Claude API calls in `services/claude.py` (slowapi already a dep)
12. Integration tests for conversation streaming endpoint in `routers/conversations.py`
13. Error handling for OAuth callback failures in `routers/github.py`/`auth.py`

**P4 — hygiene:**
14. Reconcile the two coverage gates (root `pytest.ini` enforces 80%, `backend/pytest.ini` doesn't) — pick canonical
15. Pin/relax deps to build on Python 3.14, or document the 3.12 requirement in backend README

### B. task-manager-platform (already merged; follow-ups)
1. Remove dead approval cruft — delete `approval_engine.py`, `approval_workflow.py` (router+service), `approvals.py` (router); all verified unimported. One at a time, re-run 117-test suite after each.
2. Fix the 2 `Dashboard.test.tsx` failures (component renders "Failed" under mocked fetch — fix mock/assertions or the data-load path)
3. Consolidate the approval service layer — 4+ overlapping modules; only `approval_workflow_service.py` is wired; pick canonical, collapse the rest
4. Add `happy-dom` install verification to web preflight/CI (declared but was absent → suite silently reports 0 tests)

### C. test-automation-agent (already merged; follow-ups)
1. Implement `run_step` `type` action in `agents/executor.py` (`page.fill(selector, value)`) + one test
2. De-duplicate the two step executors — `run_step` (navigate/click) is orphaned; live pipeline uses richer `_execute_step`; unify
3. Fix `progress_report` terminal phase (orchestrator.py:326 hardcodes next_phase; return `None`/`should_continue=False` when phase=="hard")
4. Add a happy-path integration test (`execute_phase` → `run_tests_concurrent` against a mocked Playwright page)
5. Wire `LLMService` into `classify_difficulty` (orchestrator.py:26; keep heuristic as fallback) — largest, do last

### D. billwatch (production; do these before or after the §2A merge)
1. De-dupe `bill_background_service.py` (remove dead first class + duplicated `BillBackgroundResponse` schema)
2. Wire bill-background to its own `bill_backgrounds` table instead of the ad-hoc httpx call to localhost:8080
3. Guard the background POST endpoint — return graceful 503/empty instead of raw 500 when LLM unreachable
4. Add `llm_client.py` OR drop the dead lazy import in `article_relevance_service.py` (LLM path currently never runs)
5. Collapse the two `/api/bills/{id}/background` routes (GET in `bills.py` + POST in `bill_background.py`) into one
6. Fix Android test package mismatch (`com.billwatch.data.model.Legislator` vs real `com.policylogs.data.models.Legislator`)

### W. shrike-labs-website (production; completion plan for `salvage/shrike-clean`)
1. Register `@unhead/vue` in `main.ts` (unblocks all per-page SEO)
2. Wire `useSEO` into each routed page (Home/About/Privacy/Terms) + title test (needs #1)
3. Add missing `public/og-image.png` (1200×630) — currently 404s
4. Rebuild browser-safe blog loader — `import.meta.glob('./blog/posts/*.md')` in `composables/useBlogPosts.ts` (replaces deleted Node-`fs` `blog.config.ts`)
5. Rebuild Blog listing page from #4 (tags/pagination)
6. Wire blog detail routing — `/blog` + `/blog/:slug`, un-orphan `BlogPostView.vue`, `useSEO` type=article (needs #1,#4)
7. Add a nav/route link to the blog in `App.vue`
8. Wire Footer newsletter to a real endpoint (replace `setTimeout` simulation)
9. Verify + document contact backend — confirm `/api/contact` resolves in prod (add `vercel.json` rewrite if missing)
10. Regenerate sitemap at build time (real `scripts/generate-sitemap.ts` + vite plugin) or delete stale one
11. Relocate stray Python out of `src/` (`src/api/routers/blog.py`, `src/services/blog_*.py`) into backend/ or delete
12. Resolve orphan pages (`PrivacyPage.vue`, `TestimonialsPage.vue`, `BlogPage.vue` — keep+route or delete)
13. Accessibility audit pass (axe/Lighthouse; contrast, focus-visible, heading order, ARIA — WCAG 2.1 AA)
14. Add component tests to hit the 80% coverage gate (ContactSection validation, Careers, Testimonials, Footer)
15. **Production verification before promotion** — Vercel preview of `salvage/shrike-clean`, visual smoke test every section/route, confirm no console errors + OG preview renders. **Gate before merge.**

### E. social-media-manager (Ripple) — REWORK (no code landed; `overnight/feature` left as-is, flagged)
The branch is architecturally broken (3–4 parallel backend router trees, deleted `user` model with dangling imports, corrupted `backend/requirements.txt`, `web/package.json` has a duplicate `dependencies` block that silently drops vue/axios/pinia/vue-router). Rework the broken layers rather than salvage. Ordered so it builds+tests green BEFORE feature work:

**Phase 1 — structural collapse:**
1. Pick ONE canonical backend router structure (suggest `app/api/routes/*`); delete `app/api/v1/*`, `app/routers/*`, `app/api/analytics.py`/`posts.py` (migrate any unique endpoints first)
2. Rewrite `main.py` mounts — each router once at a unique prefix; remove mid-file duplicate import + duplicate analytics/auth mounts
3. Restore `app/models/user.py` (move inline `User` out of `__init__.py`), fix dangling `app.models.user` imports
4. Delete the stray `b/` tree

**Phase 2 — deps & DB init:**
5. Repair `backend/requirements.txt` (dedupe, add `greenlet`); pick one canonical requirements file
6. Remove hardcoded DB URL; lazy-init the async engine (read `DATABASE_URL` from settings, engine in a factory/`init_db()`)

**Phase 3 — web build:**
7. Fix `web/package.json` — merge the two `dependencies` blocks (restore vue/axios/pinia/vue-router/@tabler/icons-vue); add `autoprefixer` to devDeps
8. Fix `web/tsconfig.json` `ignoreDeprecations` "6.0"→"5.0"
9. Verify `npm ci && npm run build` end-to-end

**Phase 4 — green tests:**
10. Make backend `pytest` green (fix the 5 failures post-collapse)
11. Make top-level `tests/` collectible (fix `AsyncSession`/`app.models.user` imports) or delete if superseded

**Phase 5 — the actual product bug (after Phases 1–4 green):**
12. Diagnose + fix "backend returns HTML instead of JSON in prod" — confirm Railway serves the FastAPI app (not a static/error fallback), verify start command, confirm no 502 (now greenlet + lazy engine fixed), add a JSON-content-type smoke test on `/api/health`

**Phase 6 — feature work** — resume only once 1–5 are green.

**Open sub-decision:** whether to `git reset overnight/feature → main` for a clean slate before rebuilding (discards the 60 broken commits; recoverable via reflog) vs. rebuild on top. Recommend reset-to-main once you've had a look, so the runner starts clean.

---

## 4. Branch state after this pass
- **main-only** (clean): shared, iptv_apps, shrike-ai-lab, xlite, + the 3 merged dev repos.
- **`salvage/billwatch-clean`**, **`salvage/shrike-clean`**: pending your §2 decision (delete after promote-or-discard).
- **`overnight/feature`**: in sync with main on all merged repos; still ahead+flagged on social-media (rework) — daily hygiene keeps it flagged, not orphaned.
