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

# --- 27B-decomposed from roadmap [2026-09-18]: Wire the built-and-tested severity scoring + Markdown formatting into the AI code review e (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-18]: Replace github_webhook's hand-rolled HMAC check with the shared, already-tested `webhook_s (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-18]: Consolidate the duplicate, fully-dead in-memory vector-search stubs — `backend/app/service (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-18]: Port the VS Code "Enhanced Code Review" command out of stranded Python pseudocode — `vscod (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-18]: Consolidate three competing dead AST-based code-analysis services — `backend/app/services/ (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-18]: Wire `pr_label_classifier.classify_pr_size` into the PR detail response — `backend/app/ser (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-18]: Make PR diff pagination real — it currently computes metadata but never slices — `backend/ (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-18]: Wire `auto_merge.can_auto_merge` into the merge endpoint — it exists, is tested, and gates (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-18]: Delete or finish the entirely-dead, internally-incomplete `api_versioning.py` — `backend/a (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-18]: Review-collaboration WebSocket trusts a client-supplied user_id with zero token verificati (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-18]: Normalize LLM-generated snippet tags before they hit the DB — `backend/app/services/tag_no (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-18]: Fix NotificationBell's response-shape crash — `web/src/api/notifications.ts`'s `fetchNotif (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-18]: Wire up the VS Code extension's dead `loadStoredTokenAsync` so login survives an editor re (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-18]: Add missing vscode-extension unit tests for the two untested tree providers — `vscode-exte (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-19]: Wire `TemporalNavigationService.create_audit_event` into real message actions — the entire (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-19]: Route the vscode-extension's Agent Library and Conversations page through the shared API c (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-19]: Wire `ArchitectureAnalysisAgent` into a real endpoint — `backend/app/services/architecture (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-19]: Surface a real error message when adding repositories to a workspace fails — `web/src/page (review + tweak) ---
- [ ] [T2] web/src/pages/SelectRepositoriesPage.vue — Update the catch block in `handleAddRepositories()` to set `submitError.value` to a user-friendly message derived from the error object instead of just logging. VERIFY: grep -q "submitError.value =" web/src/pages/SelectRepositoriesPage.vue && ! grep -q "console.error('Failed to add repositories:', error)" web/src/pages/SelectRepositoriesPage.vue. (cat:vue; multifile:no)
- [ ] [T3] web/src/pages/SelectRepositoriesPage.vue — Add an error banner element in the template that binds to `submitError` using the same styling/classes as the existing load-error banner (lines 39-41). VERIFY: grep -q "v-if=\"submitError\"" web/src/pages/SelectRepositoriesPage.vue. (cat:vue; multifile:no)
- [ ] [T4] web/src/pages/SelectRepositoriesPage.vue — Ensure `submitError` is reset to null at the start of the `handleAddRepositories()` function to clear previous errors on new attempts. VERIFY: grep -q "submitError.value = null" web/src/pages/SelectRepositoriesPage.vue. (cat:vue; multifile:no)
- [ ] [T5] web/src/pages/SelectRepositoriesPage.spec.ts — Create a unit test that mocks `workspaceStore.addRepositoriesToWorkspace` to reject, triggers the add action, and asserts the error banner is visible with the correct message. VERIFY: npx vitest run web/src/pages/SelectRepositoriesPage.spec.ts --reporter=verbose. (cat:test; multifile:no)

# --- 27B-decomposed from roadmap [2026-09-19]: Dead-code note: `ConnectorLockManager`/`ConnectorRegistryService.dispatch()` implement per (review + tweak) ---
- [ ] [T1] backend/app/services/connector_registry.py — Remove the `ConnectorLockManager` class and the `dispatch` method from `ConnectorRegistryService` to eliminate dead code that misleads developers into thinking locking is active. VERIFY: `grep -rn "class ConnectorLockManager\|def dispatch" backend/app/services/connector_registry.py` returns no matches for the removed definitions. (cat:refactor; multifile:no)
- [ ] [T1] backend/tests/test_connector_registry_cleanup.py — Create a new test file that asserts `ConnectorLockManager` is not present in the `backend.app.services.connector_registry` module namespace and that `ConnectorRegistryService` does not have a `dispatch` attribute. VERIFY: `pytest backend/tests/test_connector_registry_cleanup.py -v` passes. (cat:test; multifile:no)
- [ ] [T2] backend/app/services/dispatcher.py — Add a private method `_acquire_repo_lock(resource_id)` to `DispatcherService` that uses `asyncio.Lock` or `redis` (if available in config) to serialize access per resource ID, raising a custom `ResourceLockedError` if the lock is held. VERIFY: `python -c "from backend.app.services.dispatcher import DispatcherService; assert hasattr(DispatcherService, '_acquire_repo_lock')"` exits 0. (cat:python; multifile:no)
- [ ] [T2] backend/tests/test_dispatcher_locking.py — Create a unit test that mocks the lock mechanism and verifies that `DispatcherService._acquire_repo_lock` raises `ResourceLockedError` when a concurrent simulation holds the lock for the same `resource_id`. VERIFY: `pytest backend/tests/test_dispatcher_locking.py -v` passes. (cat:test; multifile:no)
- [ ] [T3] backend/app/services/dispatcher.py — Modify `DispatcherService.dispatch()` to wrap the task execution logic with a try/finally block that acquires the lock via `_acquire_repo_lock(resource_id)` before starting and releases it after completion, ensuring no race condition on the target repo. VERIFY: `pytest backend/tests/test_dispatcher_integration.py -v` (assuming an integration test exists or is created in next step) passes. (cat:python; multifile:no)
- [ ] [T3] backend/tests/test_dispatcher_integration.py — Create an integration test that simulates two concurrent calls to `DispatcherService.dispatch()` for the same `resource_id` and asserts that the second call either waits or fails gracefully without corrupting state, verifying serialization. VERIFY: `pytest backend/tests/test_dispatcher_integration.py -v` passes. (cat:test; multifile:no)
- [ ] [T4] backend/app/routers/plans.py — Update the call site at line 295 to ensure that any exception raised by the new locking mechanism in `DispatcherService.dispatch()` is caught and returned as a 409 Conflict response with a clear message about resource contention. VERIFY: `pytest backend/tests/test_plans_router_conflict.py -v` passes. (cat:endpoint; multifile:no)
- [ ] [T4] backend/app/routers/fleet_status.py — Update the call site at line 111 to handle the new `ResourceLockedError` or 409 response from `DispatcherService.dispatch()` by logging a warning and returning a 202 Accepted with a "pending" status instead of crashing. VERIFY: `pytest backend/tests/test_fleet_status_router_conflict.py -v` passes. (cat:endpoint; multifile:no)
- [ ] [T5] backend/app/services/dispatcher.py — Refactor the lock acquisition to use a context manager pattern (`@asynccontextmanager`) for cleaner resource management, ensuring locks are always released even if exceptions occur during task execution. VERIFY: `python -m mypy backend/app/services/dispatcher.py` passes with no type errors regarding context managers. (cat:refactor; multifile:no)
