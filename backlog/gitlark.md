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
- [ ] [T2] vscode-extension/src/views/conversations-tree.test.ts — Add test case for `getChildren()` returning empty array when API returns no conversations, verifying the "no conversations" empty-state branch (lines 39-46). VERIFY: `npx jest vscode-extension/src/views/conversations-tree.test.ts -t "returns empty array when no conversations"`. (cat:test; multifile:no)
- [ ] [T2] vscode-extension/src/views/conversations-tree.test.ts — Add test case for `getChildren()` returning conversation items when API returns data, verifying `getTreeItem()` labels and icons. VERIFY: `npx jest vscode-extension/src/views/conversations-tree.test.ts -t "returns conversation items when data exists"`. (cat:test; multifile:no)
- [ ] [T2] vscode-extension/src/views/conversations-tree.test.ts — Add test case for `refresh()` method calling `apiClient.getConversations` and firing `onDidChangeTreeData`. VERIFY: `npx jest vscode-extension/src/views/conversations-tree.test.ts -t "refresh calls api and fires event"`. (cat:test; multifile:no)
- [ ] [T1] vscode-extension/src/views/workspaces-tree.test.ts — Create test file mocking `GitLarkApiClient` and `vscode`, importing `WorkspacesTreeProvider` to verify module loads without errors. VERIFY: `npx jest vscode-extension/src/views/workspaces-tree.test.ts --testPathPattern=workspaces-tree --silent`. (cat:test; multifile:no)
- [ ] [T2] vscode-extension/src/views/workspaces-tree.test.ts — Add test case for `getChildren()` returning empty array when API returns no workspaces, verifying the "Create a workspace" empty-state branch (lines 36-45). VERIFY: `npx jest vscode-extension/src/views/workspaces-tree.test.ts -t "returns empty array when no workspaces"`. (cat:test; multifile:no)
- [ ] [T2] vscode-extension/src/views/workspaces-tree.test.ts — Add test case for `getChildren()` returning workspace items when API returns data, verifying `getTreeItem()` labels and context values. VERIFY: `npx jest vscode-extension/src/views/workspaces-tree.test.ts -t "returns workspace items when data exists"`. (cat:test; multifile:no)
- [ ] [T2] vscode-extension/src/views/workspaces-tree.test.ts — Add test case for `refresh()` method calling `apiClient.getWorkspaces` and firing `onDidChangeTreeData`. VERIFY: `npx jest vscode-extension/src/views/workspaces-tree.test.ts -t "refresh calls api and fires event"`. (cat:test; multifile:no)

# --- 27B-decomposed from roadmap [2026-09-19]: Wire `TemporalNavigationService.create_audit_event` into real message actions — the entire (review + tweak) ---
- [ ] [T1] backend/app/services/conversation.py — Add a private helper `_create_audit_event(db: Session, user_id: UUID, event_type: str, message_id: UUID, metadata: dict)` that instantiates `TemporalNavigationService(db)` and calls `create_audit_event` with the provided arguments. VERIFY: `grep -n "_create_audit_event" backend/app/services/conversation.py` returns at least one match. (cat:python; multifile:no)
- [ ] [T2] backend/tests/test_conversation_audit_helper.py — Create a new test file that mocks `TemporalNavigationService` and verifies `_create_audit_event` calls it with the correct `event_type`, `user_id`, and `message_id`. VERIFY: `pytest backend/tests/test_conversation_audit_helper.py -v` passes. (cat:test; multifile:no)
- [ ] [T3] backend/app/services/conversation.py — Modify `add_message` (line 333) to call `_create_audit_event(db, user.id, "message_created", message.id, {"conversation_id": conversation.id})` after the message is successfully committed. VERIFY: `grep -A 5 "def add_message" backend/app/services/conversation.py | grep "_create_audit_event"` returns a match. (cat:python; multifile:no)
- [ ] [T4] backend/tests/test_conversation_add_message_audit.py — Create a test that mocks the database session and `TemporalNavigationService`, calls `add_message`, and asserts `create_audit_event` was called with `event_type="message_created"`. VERIFY: `pytest backend/tests/test_conversation_add_message_audit.py -v` passes. (cat:test; multifile:no)
- [ ] [T3] backend/app/services/conversation.py — Modify `edit_message` (line 556) to call `_create_audit_event(db, user.id, "message_edited", message.id, {"conversation_id": conversation.id})` after the message update is committed. VERIFY: `grep -A 10 "def edit_message" backend/app/services/conversation.py | grep "_create_audit_event"` returns a match. (cat:python; multifile:no)
- [ ] [T4] backend/tests/test_conversation_edit_message_audit.py — Create a test that mocks the database session and `TemporalNavigationService`, calls `edit_message`, and asserts `create_audit_event` was called with `event_type="message_edited"`. VERIFY: `pytest backend/tests/test_conversation_edit_message_audit.py -v` passes. (cat:test; multifile:no)
- [ ] [T3] backend/app/services/conversation.py — Modify `delete_message` (line 587) to call `_create_audit_event(db, user.id, "message_deleted", message.id, {"conversation_id": conversation.id})` before or after the deletion commit. VERIFY: `grep -A 10 "def delete_message" backend/app/services/conversation.py | grep "_create_audit_event"` returns a match. (cat:python; multifile:no)
- [ ] [T4] backend/tests/test_conversation_delete_message_audit.py — Create a test that mocks the database session and `TemporalNavigationService`, calls `delete_message`, and asserts `create_audit_event` was called with `event_type="message_deleted"`. VERIFY: `pytest backend/tests/test_conversation_delete_message_audit.py -v` passes. (cat:test; multifile:no)
- [ ] [T5] backend/app/routers/audit.py — Verify that the `/audit-trail` endpoint correctly queries `AuditEvent` rows created by the new service calls by ensuring no filtering logic excludes `message_created`, `message_edited`, or `message_deleted` event types. VERIFY: `grep -n "event_type" backend/app/routers/audit.py` confirms no exclusion of the new event types. (cat:endpoint; multifile:no)

# --- 27B-decomposed from roadmap [2026-09-19]: Route the vscode-extension's Agent Library and Conversations page through the shared API c (review + tweak) ---
- [ ] [T3] web/src/components/AgentLibrary.vue — Replace `fetch('/api/agents/marketplace/templates')` and `fetch('/api/agents/marketplace/chains')` with `api.get` from `@/services/api`, removing manual token handling. VERIFY: `grep -q "fetch('/api" web/src/components/AgentLibrary.vue && exit 1 || exit 0`. (cat:vue; multifile:no)
- [ ] [T3] web/src/pages/ConversationsPage.vue — Replace `fetch('/api/conversations')` and `fetch('/api/conversations/${threadId}/archive', ...)` with `api.get` and `api.post` from `@/services/api`. VERIFY: `grep -q "fetch('/api" web/src/pages/ConversationsPage.vue && exit 1 || exit 0`. (cat:vue; multifile:no)
- [ ] [T3] web/src/pages/AgentChatPage.vue — Replace `fetch` calls in `loadAgents()` and `sendMessage()` with `api.get` and `api.post` from `@/services/api`, removing `localStorage.getItem('token')` usage. VERIFY: `grep -q "localStorage.getItem('token')" web/src/pages/AgentChatPage.vue && exit 1 || exit 0`. (cat:vue; multifile:no)
- [ ] [T4] web/src/services/api.ts — Ensure the axios instance correctly handles 401 responses by redirecting to login, and verify `baseURL` defaults to `VITE_API_URL || '/api'`. VERIFY: `grep -q "baseURL.*VITE_API_URL" web/src/services/api.ts && grep -q "401" web/src/services/api.ts`. (cat:typescript; multifile:no)
- [ ] [T1] web/src/__tests__/api_client.test.ts — Create a unit test mocking the axios instance to verify that `api.get` and `api.post` are called with correct URLs and that auth headers are attached via interceptors. VERIFY: `npx vitest run web/src/__tests__/api_client.test.ts`. (cat:test; multifile:no)
- [ ] [T2] web/src/__tests__/agent_library_api.test.ts — Create a unit test for `AgentLibrary.vue` logic (extracted or mocked) to verify it calls the shared API client instead of raw fetch. VERIFY: `npx vitest run web/src/__tests__/agent_library_api.test.ts`. (cat:test; multifile:no)
- [ ] [T2] web/src/__tests__/conversations_api.test.ts — Create a unit test for `ConversationsPage.vue` logic to verify it uses the shared API client for loading and archiving conversations. VERIFY: `npx vitest run web/src/__tests__/conversations_api.test.ts`. (cat:test; multifile:no)
- [ ] [T2] web/src/__tests__/agent_chat_api.test.ts — Create a unit test for `AgentChatPage.vue` logic to verify it uses the shared API client for loading agents and sending messages. VERIFY: `npx vitest run web/src/__tests__/agent_chat_api.test.ts`. (cat:test; multifile:no)

# --- 27B-decomposed from roadmap [2026-09-19]: Wire `ArchitectureAnalysisAgent` into a real endpoint — `backend/app/services/architecture (review + tweak) ---
- [ ] [T1] backend/app/schemas/architecture.py — Create Pydantic models `ArchitectureAnalysisRequest`, `ArchitectureAnalysisResponse`, `ArchitectureIssue`, and `ArchitectureRecommendation` matching the agent's output structure. VERIFY: python -c "from backend.app.schemas.architecture import ArchitectureAnalysisResponse; print('OK')". (cat:schema; multifile:no)
- [ ] [T2] backend/app/routers/code_review.py — Add `POST /{conversation_id}/architecture-review` endpoint that validates input, instantiates `ArchitectureAnalysisAgent`, calls `analyze_architecture`, and returns the parsed result. VERIFY: grep -q "architecture-review" backend/app/routers/code_review.py && python -m pytest backend/tests/test_code_review_router.py::test_architecture_endpoint_exists -v. (cat:endpoint; multifile:no)
- [ ] [T3] backend/tests/test_architecture_endpoint.py — Create integration test that mocks `ArchitectureAnalysisAgent.analyze_architecture` to return a fixed `ArchitectureAnalysisResult` and asserts the endpoint returns 200 with correct JSON structure. VERIFY: python -m pytest backend/tests/test_architecture_endpoint.py -v. (cat:test; multifile:no)
- [ ] [T4] vscode-extension/src/commands/code-review.ts — Modify `CodeReviewCommand` to detect `reviewType === 'architect'` and POST to `/api/conversations/{id}/architecture-review` instead of the generic review endpoint. VERIFY: grep -q "architecture-review" vscode-extension/src/commands/code-review.ts && npm run build --prefix vscode-extension. (cat:typescript; multifile:no)
- [ ] [T5] backend/app/services/architecture_analysis_agent.py — Refactor `analyze_architecture` to accept an optional `db_session` parameter for future context enrichment and ensure it returns the Pydantic model defined in `backend/app/schemas/architecture.py`. VERIFY: python -m pytest backend/tests/test_architecture_agent_parse.py -v. (cat:python; multifile:no)
