# gitlark — pre-decomposed release-polish backlog (27B-friendly)
# queue_refill.py pulls [T1-T5] items from here into OVERNIGHT_PROGRESS.md when doable is low.
# Note: gitlark web is Vue 3 + Pinia (not React).


# --- gitlark deepen (2026-09-04): release-blockers first (Terms page, validation, error states, WCAG) ---

# --- next-year roadmap decomposition (2026-09-05): usage-insights coverage + deprecated-model guards + reliability ---

# --- gitlark v2 (2026-09-05): planner/dispatcher pure helpers + PWA component tests ---

# gitlark control-plane pure helpers (2026-09-05)

# --- refill 2026-09-06: plan/dispatch-domain pure modules (self-verifying, T1-T2) ---

# --- COMPETITIVE 2026-09-06: Gitlark vs GitHub Mobile — beyond-triage review + Agent Connectors (the validated portfolio gap) ---
# Beyond-triage: GitHub Mobile is read/comment/approve-only, chokes on >300-file PRs, can't run tests
# Agent Connectors: nobody targets external CLI agents (Claude Code, aider, cursor) from a phone — Replit is in-house only

# --- gitlark web type errors the ratchet is currently holding (2026-09-07) — fix to ratchet down ---

# --- 27B-decomposed from roadmap [2026-09-07]: Planner backend: goal → routed task plan (schemas, plan state machine) {cat: backend; size (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-07]: PWA: conversation-first mobile UI (talk to repos, see plans) {cat: web; size: L; multifile (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-07]: Git-mediated dispatch: plan → commit tasks to the fleet's OVERNIGHT_PROGRESS {cat: backend (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-07]: Review loop: see + merge what the fleet built (PR/diff surfaces, big-diff pagination) {cat (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-07]: Conversational control plane: fleet events in chat, add-to-queue from chat, gated ops {cat (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-08]: Connector registry + event normalization + picker UI {cat: backend+web; size: M; multifile (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-09]: LocalLLMClient service: OpenAI-compatible streaming client for the LiteLLM box, mirroring  (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-09]: Repo-file GET/PUT endpoint: thin wrapper over github get_file_content/create_or_update_fil (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-09]: Single ad-hoc task enqueue endpoint: append one backlog line to a repo queue file, reusing (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-09]: Stage-run stats aggregator: pure module parsing stage_runs jsonl -> by-tier verified count (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-09]: Packaging enablers: extract the backlog item-line grammar into a versioned serialize/parse (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-10]: Connector abstraction for external coding agents — Normalize on a `Connector` interface wi (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-10]: Native iOS + Android via Capacitor wrap of the PWA — gitlark's web app is Vue 3 + Vite (co (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-11]: Per-workspace encrypted connector credentials — add a `connector_credentials` table (works (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-11]: Per-repo connector run lock — add `backend/app/services/connector_lock.py` (in-process asy (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-11]: Connector Runs dashboard page — new `web/src/pages/ConnectorRunsPage.vue` + `web/src/store (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-11]: "Send review feedback to connector" round-trip — add a `POST /api/workspaces/{workspace_id (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-13]: Ground plan generation in real repo analysis — Wire the already-built `RepoAnalysis` model (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-13]: Multi-repo plan fan-out — Today a `Plan` (backend/app/models/plan.py) belongs to exactly o (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-13]: Review rule template packs — `ReviewRule` (backend/app/models/review_rule.py) is 100% cust (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-13]: VS Code extension: Plans tree view — the extension already ships `WorkspacesTreeProvider`  (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-14]: Wire `POST /api/connectors/reinvoke` — `web/src/components/CodeReviewPanel.vue`'s "Send to (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-14]: Fix connector-runs URL mismatch — `web/src/stores/connectorRuns.ts`'s `fetchRuns()` calls  (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-14]: Wire real persistence into connector credentials + register the router — `backend/app/rout (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-14]: Multi-repo plan fan-out — expose target_workspace_id in the UI — the backend already fully (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-14]: VS Code extension: fix duplicate PlansTreeProvider — the real, API-wired `PlansTreeProvide (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-14]: Wire Team Management page to the real workspace-members API — `web/src/pages/TeamManagemen (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-14]: Wire Code Insights page to a real analysis endpoint (or drop it) — `web/src/pages/CodeInsi (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-14]: Mount workspace conversation search and fix its route collision with per-conversation sear (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-14]: Build a notification bell/panel UI for the already-built notification APIs — two complete, (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-15]: Consolidate duplicate dead FeatureFlag service implementations — `backend/app/services/fea (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-15]: Fix ReviewCollaborationManager's WebSocket path mismatch and mount it in the review UI — ` (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-15]: Wire VS Code snippet star/delete into commands and context menu — `vscode-extension/src/se (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-17]: Route the already-built Connector Runs page — `web/src/pages/ConnectorRunsPage.vue` is a c (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-17]: Delete the dead duplicate `GitHubFileService` — `backend/app/services/github_file_service. (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-17]: Delete the dead duplicate `RealTimeUpdateService` — `backend/app/services/realtime_update_ (review + tweak) ---
- [ ] [T1] backend/tests/test_realtime_update_service_removal.py — Create a test that asserts `backend/app/services/realtime_update_service.py` does not exist and that `import backend.app.services.realtime_update_service` raises `ModuleNotFoundError`. VERIFY: `cd backend && python -m pytest tests/test_realtime_update_service_removal.py -v`. (cat:test; multifile:no)
- [ ] [T3] backend/app/services/realtime_update_service.py — Delete the file containing the dead `RealTimeUpdateService` class. VERIFY: `test ! -f backend/app/services/realtime_update_service.py`. (cat:refactor; multifile:no)
- [ ] [T4] backend/app — Ensure no remaining imports of `realtime_update_service` or `RealTimeUpdateService` exist in the codebase. VERIFY: `grep -r "realtime_update_service\|RealTimeUpdateService" backend/app/ --include="*.py" | wc -l` returns 0. (cat:refactor; multifile:yes)
- [ ] [T1] backend/tests/test_realtime_service_integrity.py — Create a test verifying that `backend.app.services.realtime_service` imports successfully and exposes the `realtime_service` singleton instance. VERIFY: `cd backend && python -m pytest tests/test_realtime_service_integrity.py -v`. (cat:test; multifile:no)
- [ ] [T3] backend/app/routers/realtime.py — Verify that all 8 call sites correctly reference `realtime_service` from `backend.app.services.realtime_service` and not the deleted service. VERIFY: `grep -c "realtime_service" backend/app/routers/realtime.py` returns at least 8 and `grep "RealTimeUpdateService" backend/app/routers/realtime.py` returns 0. (cat:refactor; multifile:no)
- [ ] [T5] backend — Run the full backend test suite to ensure no regressions from removing the dead service. VERIFY: `cd backend && python -m pytest tests/ -v --tb=short`. (cat:test; multifile:yes)
