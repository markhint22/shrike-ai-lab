# gitlark — pre-decomposed release-polish backlog (27B-friendly)
# queue_refill.py pulls [T1-T5] items from here into OVERNIGHT_PROGRESS.md when doable is low.
# Note: gitlark web is Vue 3 + Pinia (not React).


# --- gitlark deepen (2026-09-04): release-blockers first (Terms page, validation, error states, WCAG) ---
- [ ] [T2] backend/tests/test_conversation_analytics_summary.py — Unit-test ConversationAnalytics.generate_summary in backend/app/services/conversation_analytics.py (total_messages == len(messages); user_messages/ai_messages count role=="user"/"assistant"; conversation_id echoed). Async, in-memory. VERIFY: pytest passes. (polish:test-coverage)
- [ ] [T2] backend/tests/test_search_get_suggestions.py — Unit-test ConversationSearchService.get_suggestions filtering in backend/app/services/search.py (falsy/empty suggestions dropped, result capped at 10). Construct with a stub/None db_session; only exercise the pure filter path. VERIFY: pytest passes. (polish:test-coverage)
- [ ] [T2] backend/tests/test_reactions_counts.py — Unit-test ReactionService.get_message_reactions aggregation in backend/app/services/reactions.py against a fake result object (counts group by reaction; empty -> {}). VERIFY: pytest passes. (polish:test-coverage)
- [ ] [T1] backend/tests/test_feature_flag_rollout.py — Unit-test FeatureFlagService.create_flag + is_enabled + update_rollout in backend/app/services/feature_flags.py (disabled flag -> False; enabled+rollout 100 -> True; unknown flag -> False; update_rollout changes result). Async, in-memory. VERIFY: pytest passes. (polish:test-coverage)

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
- [ ] [T1] web/src/composables/useApi.ts — Add `getWorkspaceMembers(workspaceId: string)` and `inviteMember(workspaceId: string, email: string)` methods that call `/api/workspaces/${workspaceId}/members` via GET and POST respectively. VERIFY: `npx vitest run web/src/composables/__tests__/useApi.test.ts -t "workspace members"`. (cat:typescript; multifile:no)
- [ ] [T1] web/src/composables/useApi.ts — Add `updateMemberRole(workspaceId: string, userId: string, role: string)` and `removeMember(workspaceId: string, userId: string)` methods that call the corresponding PUT and DELETE endpoints. VERIFY: `npx vitest run web/src/composables/__tests__/useApi.test.ts -t "member management"`. (cat:typescript; multifile:no)
- [ ] [T2] web/src/pages/TeamManagementPage.vue — Refactor `loadTeamMembers()` to call `useApi().getWorkspaceMembers(currentWorkspaceId.value)` and map the response to the local `members` ref, removing all hardcoded data. VERIFY: `grep -q "getWorkspaceMembers" web/src/pages/TeamManagementPage.vue && ! grep -q "Mark Hintermeister" web/src/pages/TeamManagementPage.vue`. (cat:vue; multifile:no)
- [ ] [T2] web/src/pages/TeamManagementPage.vue — Refactor `sendInvite()` to call `useApi().inviteMember(currentWorkspaceId.value, email)` and handle success/error states, removing the placeholder comment. VERIFY: `grep -q "inviteMember" web/src/pages/TeamManagementPage.vue && ! grep -q "API call would go here" web/src/pages/TeamManagementPage.vue`. (cat:vue; multifile:no)
- [ ] [T3] web/src/router.ts — Add a route entry for `/team` (or similar) that maps to `TeamManagementPage.vue` with appropriate meta permissions if defined. VERIFY: `grep -q "TeamManagementPage" web/src/router.ts`. (cat:typescript; multifile:no)
- [ ] [T3] web/src/pages/TeamManagementPage.vue — Implement UI handlers for changing member roles and removing members that call `updateMemberRole` and `removeMember` from `useApi`. VERIFY: `grep -q "updateMemberRole" web/src/pages/TeamManagementPage.vue && grep -q "removeMember" web/src/pages/TeamManagementPage.vue`. (cat:vue; multifile:no)
- [ ] [T4] web/src/pages/__tests__/TeamManagementPage.spec.ts — Create a unit test that mocks `useApi` and verifies `loadTeamMembers` updates the DOM with fetched data and `sendInvite` triggers the API call. VERIFY: `npx vitest run web/src/pages/__tests__/TeamManagementPage.spec.ts`. (cat:test; multifile:no)

# --- 27B-decomposed from roadmap [2026-09-14]: Wire Code Insights page to a real analysis endpoint (or drop it) — `web/src/pages/CodeInsi (review + tweak) ---
- [ ] [T1] backend/app/routers/code_insights.py — Create new router with `POST /api/workspaces/{workspace_id}/code-insights` endpoint that calls `MLCodeInsightsService.analyze_repository` and returns `CodeQualityReport`. VERIFY: `python -c "from backend.app.routers.code_insights import router; print(router.routes)"`. (cat:endpoint; multifile:no)
- [ ] [T2] backend/app/main.py — Import `code_insights` router and include it in the FastAPI app instance. VERIFY: `grep -q "code_insights" backend/app/main.py && python -c "from backend.app.main import app; print([r.path for r in app.routes if 'insights' in r.path])"`. (cat:python; multifile:no)
- [ ] [T3] web/src/router.ts — Add route definition for `/workspaces/:id/insights` pointing to `CodeInsightsPage.vue`. VERIFY: `grep -q "CodeInsightsPage" web/src/router.ts`. (cat:typescript; multifile:no)
- [ ] [T4] web/src/pages/CodeInsightsPage.vue — Replace fake `setTimeout` logic in `analyzeRepository()` with a real `fetch` call to `/api/workspaces/${workspaceId}/code-insights` and map response to `categories`/`topIssues`. VERIFY: `grep -q "fetch" web/src/pages/CodeInsightsPage.vue && ! grep -q "setTimeout" web/src/pages/CodeInsightsPage.vue`. (cat:vue; multifile:no)
- [ ] [T5] backend/tests/test_code_insights_router.py — Add unit test mocking `MLCodeInsightsService` to verify the new endpoint returns 200 and correct schema. VERIFY: `pytest backend/tests/test_code_insights_router.py -v`. (cat:test; multifile:no)

# --- 27B-decomposed from roadmap [2026-09-14]: Mount workspace conversation search and fix its route collision with per-conversation sear (review + tweak) ---
- [ ] [T1] backend/app/services/search.py — Rename the router prefix from "/conversations" to "/workspaces" and update route paths to "/{workspace_id}/conversations/search" and "/{workspace_id}/conversations/search/suggestions". VERIFY: grep -n "prefix=\"/workspaces\"" backend/app/services/search.py && grep -n "/{workspace_id}/conversations/search" backend/app/services/search.py. (cat:python; multifile:no)
- [ ] [T2] backend/app/main.py — Import the search router from app.services.search and add an include_router call with prefix="/api/workspaces". VERIFY: grep -n "from app.services.search import" backend/app/main.py && grep -n "include_router.*search_router" backend/app/main.py. (cat:python; multifile:no)
- [ ] [T3] web/src/stores/conversation.ts — Update the API endpoint in searchConversations() to /workspaces/${workspaceId}/conversations/search?q=... and remove the stale 2026-09-05 comment. VERIFY: grep -n "/workspaces/\${workspaceId}/conversations/search" web/src/stores/conversation.ts && ! grep -n "KNOWN BROKEN" web/src/stores/conversation.ts. (cat:typescript; multifile:no)
- [ ] [T4] web/src/stores/conversation.ts — Update the API endpoint in getSearchSuggestions() to /workspaces/${workspaceId}/conversations/search/suggestions?q=.... VERIFY: grep -n "/workspaces/\${workspaceId}/conversations/search/suggestions" web/src/stores/conversation.ts. (cat:typescript; multifile:no)
- [ ] [T5] web/src/components/ConversationSearch.vue — Update any hardcoded API calls or fetch URLs to use the new /workspaces/{id}/conversations/search paths if present, ensuring consistency with the store. VERIFY: grep -rn "conversations/search" web/src/components/ConversationSearch.vue | grep -v "workspaces" || echo "No direct calls found". (cat:vue; multifile:no)

# --- 27B-decomposed from roadmap [2026-09-14]: Build a notification bell/panel UI for the already-built notification APIs — two complete, (review + tweak) ---
- [ ] [T1] web/src/api/notifications.ts — Create a TypeScript API client module exporting `fetchNotifications`, `markNotificationRead`, and `markAllNotificationsRead` functions that call the `/api/notifications` endpoints. VERIFY: `npx tsc --noEmit` passes without errors. (cat:typescript; multifile:no)
- [ ] [T2] web/src/components/NotificationBell.vue — Create a Vue component with a bell icon, an unread count badge, and a dropdown list that fetches data on mount and emits `markRead` events. VERIFY: `npx vue-tsc --noEmit` passes and `grep -q "unread_count" web/src/components/NotificationBell.vue`. (cat:vue; multifile:no)
- [ ] [T3] web/src/App.vue — Import and register the `NotificationBell` component in the header section of the App layout. VERIFY: `grep -q "NotificationBell" web/src/App.vue` and `npx vue-tsc --noEmit` passes. (cat:vue; multifile:no)
- [ ] [T4] web/src/components/NotificationBell.vue — Implement the click handler logic to call `markNotificationRead` for individual items and `markAllNotificationsRead` for the "Mark all read" button, updating local state optimistically. VERIFY: `npx vitest run web/src/components/__tests__/NotificationBell.test.ts` passes (create test file if missing or update existing). (cat:vue; multifile:yes)
- [ ] [T5] web/src/api/notifications.ts — Add error handling and retry logic for the notification API calls, ensuring network failures do not crash the UI. VERIFY: `npx vitest run web/src/api/__tests__/notifications.test.ts` passes. (cat:typescript; multifile:no)
