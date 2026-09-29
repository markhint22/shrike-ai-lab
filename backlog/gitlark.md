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

# --- 27B-decomposed from roadmap [2026-09-19]: Dead-code note: `ConnectorLockManager`/`ConnectorRegistryService.dispatch()` implement per (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-20]: Finish P5: wire the already-built conversational control-plane agent into the real chat pa (review + tweak) [feat:gitlark-20260920-finish-p5-wire-the-already-built-convers] ---

# --- 27B-decomposed from roadmap [2026-09-21]: Build the still-unconsumed workspace Notifications Feed panel — now that the control-plane (review + tweak) [feat:gitlark-20260921-build-the-still-unconsumed-workspace-not] ---

# --- 27B-decomposed from roadmap [2026-09-21]: Build the still-unconsumed workspace Notifications Feed panel — now that the control-plane (review + tweak) [feat:gitlark-20260921-build-the-still-unconsumed-workspace-not] ---

# --- 27B-decomposed from roadmap [2026-09-21]: Add missing unit tests for `get_template_rules()` in `backend/app/services/review_rule_tem (review + tweak) [feat:gitlark-20260921-add-missing-unit-tests-for-get-template-] ---

# --- 27B-decomposed from roadmap [2026-09-21]: Add unit tests for the pure rendering paths of `ConversationExportService` in `backend/app (review + tweak) [feat:gitlark-20260921-add-unit-tests-for-the-pure-rendering-pa] ---

# --- 27B-decomposed from roadmap [2026-09-21]: Harden `repo_slug()` in `backend/app/utils/repo_slug.py` (15 lines) against consecutive-se (review + tweak) [feat:gitlark-20260921-harden-repo-slug-in-backend-app-utils-re] ---

# --- 27B-decomposed from roadmap [2026-09-21]: Delete a genuinely dead, zero-byte stray file: `web/src/src/stores/conversation.ts` — veri (review + tweak) [feat:gitlark-20260921-delete-a-genuinely-dead-zero-byte-stray-] ---

# --- 27B-decomposed from roadmap [2026-09-21]: Add a unit test for `web/src/utils/apiError.ts` (43 lines, exports `getErrorMessage()`/`ge (review + tweak) [feat:gitlark-20260921-add-a-unit-test-for-web-src-utils-apierr] ---

# --- 27B-decomposed from roadmap [2026-09-21]: Add a unit test for the `useApi()` composable in `web/src/composables/useApi.ts` (38 lines (review + tweak) [feat:gitlark-20260921-add-a-unit-test-for-the-useapi-composabl] ---

# --- 27B-decomposed from roadmap [2026-09-21]: Add a unit test for the `useWorkspaceOptions()` composable in `web/src/composables/useWork (review + tweak) [feat:gitlark-20260921-add-a-unit-test-for-the-useworkspaceopti] ---

# --- 27B-decomposed from roadmap [2026-09-21]: Add a unit test for `useFleetStatusStore` in `web/src/stores/fleetStatus.ts` (42 lines, it (review + tweak) [feat:gitlark-20260921-add-a-unit-test-for-usefleetstatusstore-] ---

# --- Claude-decomposed from roadmap [2026-09-22]: connector_credentials.py create/update encrypt() signature bug + real DB persistence — backend/app/routers/connector_credentials.py (fresh live-code audit, roadmap's own earlier item on this file was stale — router IS mounted and list/get/update/delete already query the real DB; only create() is still a full mock and both create+update call encryption_service.encrypt() with swapped/wrong-typed args) ---

# --- Claude-decomposed from roadmap [2026-09-22]: dead/orphaned service + stray-file cleanup sweep (fresh live-code audit, each confirmed zero-caller via grep against the current tree — several superseded roadmap items from 2026-09-14/17/18/19 turned out to already be fixed by the fleet, this batch is a fresh re-scan, not a recycled description) ---

# --- Claude-decomposed from roadmap [2026-09-22]: get_repo_context() ignores its own workspace_id parameter — cross-workspace repo-analysis data leak — backend/app/services/repo_context.py (verified live: the SQL query has no WHERE clause on workspace at all, it always returns whichever repo was analyzed most recently system-wide) ---

# --- Claude-decomposed from roadmap [2026-09-22]: OtaService is fully unwired mock scaffolding — web/src/services/ota.ts (parseCapgoUpdateResponse/shouldApplyUpdate are already tested pure functions, but OtaService.initialize() fakes a hardcoded newer version and is never called by any component in web/src) ---

# --- Claude-decomposed from roadmap [2026-09-22]: re-added with corrected VERIFY commands — 7 items from the connector_credentials/dead-orphan-cleanup/repo_context features above were pulled with backwards-logic grep VERIFY commands (checking PRESENCE of the code-to-be-removed, or PRESENCE of a substring that already existed in a stale comment, instead of its ABSENCE) and got instantly, wrongly pre-verify-credited without a single real 27B cycle touching the file. Reverted those 7 false credits in OVERNIGHT_DONE.md; these are the same 7 fixes with corrected VERIFY logic ---

# --- Claude-decomposed from roadmap [2026-09-22 round 3]: ControlPlaneAgent chat wiring computes tool_calls but discards them — no execute_tool_call(), no response message ever appended (undoes part of the 2026-09-20 "Finish P5" claim) ---

# --- Claude-decomposed from roadmap [2026-09-22 round 3]: delete three dead, superseded service duplicates — ClaudeAgent, GitHubIntegrationService, PlanService (each confirmed zero-caller outside its own file+test) ---

# --- Claude-decomposed from roadmap [2026-09-22 round 3]: delete dead dispatch-domain scaffolding superseded by DispatcherService's real marker-based idempotency check ---

# --- Claude-decomposed from roadmap [2026-09-22 round 3]: delete two dead, mutually-inconsistent GitHub-webhook-classification pure functions (real behavior-drift bug: they use a narrower reviewable-actions set than the live router) ---

# --- Claude-decomposed from roadmap [2026-09-22 round 3]: delete hunk_summary.py — dead, unwired duplicate of diff_parser.py's explicitly-designated "single shared implementation" ---

# --- Claude-decomposed from roadmap [2026-09-22 round 3]: repo_analysis.py has a dead unused import + a dead duplicate local helper; wire the real, tested format_diff_stats into the PR diff UI instead ---

# --- Claude-decomposed from roadmap [2026-09-22 round 3]: wire ExponentialBackoffRetry into GitHubClient — zero retry logic on any of its ~10 HTTP methods today ---

# --- Claude-decomposed from roadmap [2026-09-22 round 3]: wire secret_redaction.redact_secrets into conversation message storage — real, currently-open secret-leak surface ---

# --- Claude-decomposed from roadmap [2026-09-22 round 3]: delete five dead, unmounted Vue conversation-UI components superseded by ConversationDetailPage.vue's own inline rendering ---

# --- Claude-decomposed from roadmap [2026-09-22 round 3]: wire TemporalNavigation.vue into ConversationDetailPage.vue — the backend replay-timeline endpoint it expects already exists ---

# --- 27B-decomposed from roadmap [2026-09-27]: **ControlPlaneAgent chat wiring computes a tool-call decision and then silently discards i (review + tweak) [feat:gitlark-20260927-controlplaneagent-chat-wiring-computes-a] ---

# --- 27B-decomposed from roadmap [2026-09-27]: **Delete three dead, superseded single-purpose service duplicates: `ClaudeAgent`, `GitHubI (review + tweak) [feat:gitlark-20260927-delete-three-dead-superseded-single-purp] ---

# --- 27B-decomposed from roadmap [2026-09-27]: **Delete dead dispatch-domain scaffolding superseded by `DispatcherService`'s real impleme (review + tweak) [feat:gitlark-20260927-delete-dead-dispatch-domain-scaffolding-] ---

# --- 27B-decomposed from roadmap [2026-09-27]: **Consolidate/delete two dead, mutually-inconsistent GitHub-webhook-classification pure fu (review + tweak) [feat:gitlark-20260927-consolidate-delete-two-dead-mutually-inc] ---

# --- 27B-decomposed from roadmap [2026-09-28]: **Delete `hunk_summary.py` — a dead, unwired duplicate of `diff_parser.py`'s explicitly-de (review + tweak) [feat:gitlark-20260928-delete-hunk-summary-py-a-dead-unwired-du] ---

# --- 27B-decomposed from roadmap [2026-09-28]: **`repo_analysis.py` imports a dead diff-stats function and defines an equally-dead duplic (review + tweak) [feat:gitlark-20260928-repo-analysis-py-imports-a-dead-diff-sta] ---

# --- 27B-decomposed from roadmap [2026-09-28]: **Wire `ExponentialBackoffRetry` into `GitHubClient` — every one of its ~10 HTTP methods h (review + tweak) [feat:gitlark-20260928-wire-exponentialbackoffretry-into-github] ---

# --- 27B-decomposed from roadmap [2026-09-28]: **Wire `secret_redaction.redact_secrets` into conversation message storage — a real, curre (review + tweak) [feat:gitlark-20260928-wire-secret-redaction-redact-secrets-int] ---

# --- 27B-decomposed from roadmap [2026-09-28]: **Wire `tier_evaluator.evaluate_tier_usage` — `QuotaService` has NO monthly token cap at a (review + tweak) [feat:gitlark-20260928-wire-tier-evaluator-evaluate-tier-usage-] ---

# --- 27B-decomposed from roadmap [2026-09-28]: **Wire `usage_period.current_billing_period` — quota resets always use calendar day 1, ign (review + tweak) [feat:gitlark-20260928-wire-usage-period-current-billing-period] ---

# --- 27B-decomposed from roadmap [2026-09-28]: **`ConversationAnalytics` is a mostly-stub, zero-caller class — one real method worth keep (review + tweak) [feat:gitlark-20260928-conversationanalytics-is-a-mostly-stub-z] ---

# --- 27B-decomposed from roadmap [2026-09-29]: **Wire `intent_router.classify_intent` as a cheap pre-filter before the (real API-cost) `C (review + tweak) [feat:gitlark-20260929-wire-intent-router-classify-intent-as-a-] ---

# --- 27B-decomposed from roadmap [2026-09-29]: **`format_bytes` silently produces an incorrect/misleading result above the petabyte range (review + tweak) [feat:gitlark-20260929-format-bytes-silently-produces-an-incorr] ---

# --- 27B-decomposed from roadmap [2026-09-29]: **Delete five dead, unmounted Vue conversation-UI components superseded by `ConversationDe (review + tweak) [feat:gitlark-20260929-delete-five-dead-unmounted-vue-conversat] ---
- [ ] [T1] web/src/components/MessageActions.vue — Delete the file entirely as it is unreferenced dead code. VERIFY: `test ! -f web/src/components/MessageActions.vue`. (cat:vue; multifile:no) [feat:gitlark-20260929-delete-five-dead-unmounted-vue-conversat]
- [ ] [T1] web/src/components/ConversationAI.vue — Delete the file entirely as it is unreferenced dead code. VERIFY: `test ! -f web/src/components/ConversationAI.vue`. (cat:vue; multifile:no) [feat:gitlark-20260929-delete-five-dead-unmounted-vue-conversat]
- [ ] [T2] web/src/pages/ConversationDetailPage.vue — Verify no imports or references to the five deleted components remain in the live page. VERIFY: `grep -E "ConversationList|ConversationPanel|ConversationActions|MessageActions|ConversationAI" web/src/pages/ConversationDetailPage.vue | wc -l` returns 0. (cat:vue; multifile:no) [feat:gitlark-20260929-delete-five-dead-unmounted-vue-conversat]
- [ ] [T2] web/src — Verify no other file in the frontend source tree imports or references the deleted components. VERIFY: `grep -rE "import.*ConversationList|import.*ConversationPanel|import.*ConversationActions|import.*MessageActions|import.*ConversationAI" web/src/ | wc -l` returns 0. (cat:vue; multifile:no) [feat:gitlark-20260929-delete-five-dead-unmounted-vue-conversat]

# --- 27B-decomposed from roadmap [2026-09-29]: **Wire `TemporalNavigation.vue` into `ConversationDetailPage.vue` — the backend endpoint i (review + tweak) [feat:gitlark-20260929-wire-temporalnavigation-vue-into-convers] ---
- [ ] [T1] web/src/services/api.ts — Export a `getReplayTimeline(conversationId: string)` method that uses the shared axios instance to GET `/conversations/${conversationId}/replay-timeline` and returns the typed response. VERIFY: `npx tsc --noEmit` passes and `grep -q "getReplayTimeline" web/src/services/api.ts`. (cat:typescript; multifile:no) [feat:gitlark-20260929-wire-temporalnavigation-vue-into-convers]
- [ ] [T2] web/src/components/TemporalNavigation.vue — Replace the raw `fetch('/api/conversations/${conversationId}/replay-timeline')` call inside `loadTimeline()` with `import { api } from '@/services/api'` and `api.getReplayTimeline(this.conversationId)`. VERIFY: `grep -q "api.getReplayTimeline" web/src/components/TemporalNavigation.vue` AND `! grep -q "fetch('/api/conversations" web/src/components/TemporalNavigation.vue`. (cat:vue; multifile:no) [feat:gitlark-20260929-wire-temporalnavigation-vue-into-convers]
- [ ] [T3] web/src/pages/ConversationDetailPage.vue — Import `TemporalNavigation` from `@/components/TemporalNavigation.vue`, add a boolean data property `showTimeline` (default false), and add a toggle button in the template that binds to `showTimeline`. VERIFY: `grep -q "import TemporalNavigation" web/src/pages/ConversationDetailPage.vue` AND `grep -q "showTimeline" web/src/pages/ConversationDetailPage.vue`. (cat:vue; multifile:no) [feat:gitlark-20260929-wire-temporalnavigation-vue-into-convers]
- [ ] [T4] web/src/pages/ConversationDetailPage.vue — Add the `<TemporalNavigation>` component to the template, conditionally rendered with `v-if="showTimeline"`, passing `:conversation-id="conversationId"` and listening for `@navigate` to update the current message view or scroll position. VERIFY: `grep -q "<TemporalNavigation" web/src/pages/ConversationDetailPage.vue` AND `grep -q "v-if=\"showTimeline\"" web/src/pages/ConversationDetailPage.vue`. (cat:vue; multifile:no) [feat:gitlark-20260929-wire-temporalnavigation-vue-into-convers]
- [ ] [T5] web/src/components/__tests__/TemporalNavigation.spec.ts — Create a unit test that mocks the `api.getReplayTimeline` service, mounts `TemporalNavigation`, triggers `loadTimeline()`, and asserts that the component's internal state updates with the mock data and no raw `fetch` is called. VERIFY: `npx vitest run web/src/components/__tests__/TemporalNavigation.spec.ts` passes. (cat:test; multifile:no) [feat:gitlark-20260929-wire-temporalnavigation-vue-into-convers]

# --- 27B-decomposed from roadmap [2026-09-29]: **Add component tests for the three components `ConversationDetailPage.vue` actually mount (review + tweak) [feat:gitlark-20260929-add-component-tests-for-the-three-compon] ---
- [ ] [T1] web/src/components/__tests__/ReactionButtons.test.ts — Create Vitest test for ReactionButtons.vue verifying that clicking an emoji button emits the 'react' event with the correct payload. VERIFY: `cd web && npx vitest run src/components/__tests__/ReactionButtons.test.ts`. (cat:test; multifile:no) [feat:gitlark-20260929-add-component-tests-for-the-three-compon]
- [ ] [T1] web/src/components/__tests__/ReactionCounts.test.ts — Create Vitest test for ReactionCounts.vue verifying it renders the correct count for each emoji and hides entries with zero counts. VERIFY: `cd web && npx vitest run src/components/__tests__/ReactionCounts.test.ts`. (cat:test; multifile:no) [feat:gitlark-20260929-add-component-tests-for-the-three-compon]
- [ ] [T1] web/src/components/__tests__/ExportMenu.test.ts — Create Vitest test for ExportMenu.vue verifying that selecting 'markdown', 'html', and 'json' options triggers the corresponding export service calls or emits. VERIFY: `cd web && npx vitest run src/components/__tests__/ExportMenu.test.ts`. (cat:test; multifile:no) [feat:gitlark-20260929-add-component-tests-for-the-three-compon]
- [ ] [T2] web/src/components/ReactionButtons.vue — Refactor to ensure explicit event emission for clicks if not already present, and add JSDoc for testability. VERIFY: `cd web && npx vue-tsc --noEmit`. (cat:vue; multifile:no) [feat:gitlark-20260929-add-component-tests-for-the-three-compon]
- [ ] [T2] web/src/components/ReactionCounts.vue — Ensure zero-count filtering logic is isolated or explicit to support unit testing of visibility rules. VERIFY: `cd web && npx vue-tsc --noEmit`. (cat:vue; multifile:no) [feat:gitlark-20260929-add-component-tests-for-the-three-compon]
- [ ] [T2] web/src/components/ExportMenu.vue — Ensure export format selection logic is decoupled from UI state to allow mocking of export services in tests. VERIFY: `cd web && npx vue-tsc --noEmit`. (cat:vue; multifile:no) [feat:gitlark-20260929-add-component-tests-for-the-three-compon]

# --- 27B-decomposed from roadmap [2026-09-29]: **Batch cleanup: four more small, genuinely dead pure-helper modules found in the same swe (review + tweak) [feat:gitlark-20260929-batch-cleanup-four-more-small-genuinely-] ---
- [ ] [T1] backend/app/services/cache_keys.py — Delete the file entirely as it contains only the dead `build_cache_key()` helper with zero callers. VERIFY: `test -f backend/app/services/cache_keys.py && echo "FAIL" || echo "PASS"`. (cat:python; multifile:no) [feat:gitlark-20260929-batch-cleanup-four-more-small-genuinely-]
- [ ] [T1] backend/tests/test_cache_keys.py — Delete the dedicated test file for the removed `cache_keys` module. VERIFY: `test -f backend/tests/test_cache_keys.py && echo "FAIL" || echo "PASS"`. (cat:test; multifile:no) [feat:gitlark-20260929-batch-cleanup-four-more-small-genuinely-]
- [ ] [T1] backend/app/services/commit_message_parse.py — Delete the file entirely as it contains only the dead `parse_commit_message()` helper with zero callers. VERIFY: `test -f backend/app/services/commit_message_parse.py && echo "FAIL" || echo "PASS"`. (cat:python; multifile:no) [feat:gitlark-20260929-batch-cleanup-four-more-small-genuinely-]
- [ ] [T1] backend/tests/test_commit_message_parse.py — Delete the dedicated test file for the removed `commit_message_parse` module. VERIFY: `test -f backend/tests/test_commit_message_parse.py && echo "FAIL" || echo "PASS"`. (cat:test; multifile:no) [feat:gitlark-20260929-batch-cleanup-four-more-small-genuinely-]
- [ ] [T1] backend/app/services/code_fence.py — Delete the file entirely as it contains only dead `extract_code_blocks()` and `wrap_code_block()` helpers with zero callers. VERIFY: `test -f backend/app/services/code_fence.py && echo "FAIL" || echo "PASS"`. (cat:python; multifile:no) [feat:gitlark-20260929-batch-cleanup-four-more-small-genuinely-]
- [ ] [T1] backend/tests/test_code_fence.py — Delete the dedicated test file for the removed `code_fence` module. VERIFY: `test -f backend/tests/test_code_fence.py && echo "FAIL" || echo "PASS"`. (cat:test; multifile:no) [feat:gitlark-20260929-batch-cleanup-four-more-small-genuinely-]
- [ ] [T1] backend/app/services/chat_transcript.py — Remove the `inject_fleet_event_to_transcript()` function while preserving `format_transcript()` and other live exports. VERIFY: `grep -q "def inject_fleet_event_to_transcript" backend/app/services/chat_transcript.py && echo "FAIL" || echo "PASS"`. (cat:python; multifile:no) [feat:gitlark-20260929-batch-cleanup-four-more-small-genuinely-]
- [ ] [T1] backend/tests/test_chat_transcript.py — Remove test cases specifically targeting `inject_fleet_event_to_transcript` while keeping tests for `format_transcript`. VERIFY: `grep -q "inject_fleet_event_to_transcript" backend/tests/test_chat_transcript.py && echo "FAIL" || echo "PASS"`. (cat:test; multifile:no) [feat:gitlark-20260929-batch-cleanup-four-more-small-genuinely-]
- [ ] [T2] backend/app/services/__init__.py — Ensure no imports reference the deleted modules or removed functions to prevent import errors. VERIFY: `python -c "import backend.app.services" && echo "PASS" || echo "FAIL"`. (cat:python; multifile:no) [feat:gitlark-20260929-batch-cleanup-four-more-small-genuinely-]
