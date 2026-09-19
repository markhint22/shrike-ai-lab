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
- [ ] [T5] backend/app/models/snippet.py — Add a composite unique constraint on `(snippet_id, tag_id)` in the `snippet_tags` association table definition to prevent duplicate links at the DB level. VERIFY: `alembic upgrade head && alembic downgrade -1 && alembic upgrade head`. (cat:schema; multifile:no)

# --- 27B-decomposed from roadmap [2026-09-18]: Fix NotificationBell's response-shape crash — `web/src/api/notifications.ts`'s `fetchNotif (review + tweak) ---
- [ ] [T1] web/src/api/notifications.ts — Update `fetchNotifications` to destructure `response.data.notifications` and return the array instead of the raw object. VERIFY: `npx vitest run web/src/api/__tests__/notifications.test.ts`. (cat:typescript; multifile:no)
- [ ] [T1] web/src/api/__tests__/notifications.test.ts — Create a new test file mocking `api.get` to return `{ data: { notifications: [...], unread_count: 1 } }` and assert `fetchNotifications()` resolves to the array. VERIFY: `npx vitest run web/src/api/__tests__/notifications.test.ts`. (cat:test; multifile:no)
- [ ] [T2] web/src/components/NotificationBell.vue — Update the `loadNotifications` method to handle the updated return type from `fetchNotifications`, ensuring `notifications.value` is assigned an array and `unreadCount` is computed correctly. VERIFY: `npx vue-tsc --noEmit`. (cat:vue; multifile:no)
- [ ] [T3] web/src/components/__tests__/NotificationBell.spec.ts — Create a new component test that mocks the API service to return valid notification data and asserts that the component renders the list without throwing errors. VERIFY: `npx vitest run web/src/components/__tests__/NotificationBell.spec.ts`. (cat:test; multifile:no)
- [ ] [T4] web/src/api/notifications.ts — Refactor `fetchNotifications` to return a typed object `{ notifications: Notification[], unreadCount: number }` instead of just the array, updating the interface definition. VERIFY: `npx tsc --noEmit`. (cat:typescript; multifile:no)
- [ ] [T4] web/src/components/NotificationBell.vue — Update the component to consume the new `{ notifications, unreadCount }` object from the API, removing client-side filtering for unread count if the backend provides it. VERIFY: `npx vue-tsc --noEmit`. (cat:vue; multifile:no)

# --- 27B-decomposed from roadmap [2026-09-18]: Wire up the VS Code extension's dead `loadStoredTokenAsync` so login survives an editor re (review + tweak) ---
- [ ] [T1] vscode-extension/src/services/auth-service.ts — Add a private `isTokenValid(token: string): Promise<boolean>` method that performs the `/api/auth/me` verification logic currently embedded in `loadStoredTokenAsync`, returning true only on a 200 response. VERIFY: `npx jest --testPathPattern=auth-service.test.ts -t "isTokenValid returns true for valid token"` passes. (cat:typescript; multifile:no)
- [ ] [T1] vscode-extension/src/services/auth-service.test.ts — Create unit tests mocking `vscode.SecretStorage` and `fetch`, verifying that `loadStoredTokenAsync` sets `this.token` when a stored token is valid and clears it if invalid. VERIFY: `npx jest --testPathPattern=auth-service.test.ts` passes with 100% coverage of `loadStoredTokenAsync`. (cat:test; multifile:no)
- [ ] [T3] vscode-extension/src/services/auth-service.ts — Refactor `loadStoredTokenAsync` to use the new `isTokenValid` helper, ensuring it handles the case where `context.secrets.get('gitlark.token')` returns null by resolving immediately without setting the token. VERIFY: `npx tsc --noEmit` passes and `npx jest --testPathPattern=auth-service.test.ts -t "loadStoredTokenAsync handles missing token"` passes. (cat:typescript; multifile:no)
- [ ] [T3] vscode-extension/src/extension-core.ts — Modify `initialize()` to `await this.authService.loadStoredTokenAsync()` immediately after constructing `AuthService` and before calling `this.authService.checkAuthentication()`. VERIFY: `npx tsc --noEmit` passes and a manual integration test confirms the user remains logged in after restarting VS Code. (cat:typescript; multifile:no)
- [ ] [T1] vscode-extension/src/services/auth-service.ts — Add error handling to `loadStoredTokenAsync` to catch network errors during token verification, logging a warning via `vscode.window.showWarningMessage` and leaving the token unset if verification fails. VERIFY: `npx jest --testPathPattern=auth-service.test.ts -t "loadStoredTokenAsync handles network error"` passes. (cat:typescript; multifile:no)
- [ ] [T2] vscode-extension/src/extension-core.ts — Add a unit test for `initialize()` that mocks `AuthService` to verify `loadStoredTokenAsync` is called before `checkAuthentication`. VERIFY: `npx jest --testPathPattern=extension-core.test.ts -t "initialize calls loadStoredTokenAsync before checkAuthentication"` passes. (cat:test; multifile:no)

# --- 27B-decomposed from roadmap [2026-09-18]: Add missing vscode-extension unit tests for the two untested tree providers — `vscode-exte (review + tweak) ---
- [ ] [T1] vscode-extension/src/views/conversations-tree.test.ts — Create test file mocking `GitLarkApiClient` and `vscode`, importing `ConversationsTreeProvider` to verify module loads without errors. VERIFY: `npx jest vscode-extension/src/views/conversations-tree.test.ts --testPathPattern=conversations-tree --silent`. (cat:test; multifile:no)
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
