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
- [ ] [T1] web/src/pages/ConversationDetailPage.vue — Add minimal `onTimelineNavigate(timestamp: Date)` and `onTimelineEvent(event: TimelineEvent)` handler stubs (scroll-to or log for now) so the two events `TemporalNavigation` emits have a real listener instead of an unhandled emit. VERIFY: `grep -q "function onTimelineNavigate" web/src/pages/ConversationDetailPage.vue`. (cat:frontend; size:S; multifile:no) [feat:gitlark-20260922-temporal-navigation-wiring]
- [ ] [T2] web/src/components/__tests__/TemporalNavigation.test.ts — Add a new test file (this component has zero test coverage today) mocking `@/services/api`'s `api.get` to resolve a canned `TimelineData` payload, mounting the component, and asserting `loadTimeline()` populates `timeline` and that the slider/tooltip render without throwing. VERIFY: `cd web && npx vitest run src/components/__tests__/TemporalNavigation.test.ts`. (cat:frontend; size:M; multifile:no) [feat:gitlark-20260922-temporal-navigation-wiring]
- [ ] [T1] web/src/pages/__tests__/ConversationDetailPage.test.ts — Add or extend a test asserting the "View timeline" toggle renders `TemporalNavigation` when clicked (mount the page, trigger the toggle, assert `findComponent(TemporalNavigation).exists()` is true). VERIFY: `cd web && npx vitest run src/pages/__tests__/ConversationDetailPage.test.ts`. (cat:frontend; size:S; multifile:no) [feat:gitlark-20260922-temporal-navigation-wiring]

# --- 27B-decomposed from roadmap [2026-09-27]: **ControlPlaneAgent chat wiring computes a tool-call decision and then silently discards i (review + tweak) [feat:gitlark-20260927-controlplaneagent-chat-wiring-computes-a] ---
- [ ] [T1] backend/app/services/conversation.py — Add a helper function `build_control_plane_context(session: AsyncSession, project_config: ProjectConfig, workspace_id: UUID, user_id: UUID, conversation_id: UUID) -> ControlPlaneContext` that extracts the access token from `project_config` and constructs the context object. VERIFY: `pytest backend/tests/test_conversation.py::test_build_control_plane_context -v`. (cat:python; multifile:no) [feat:gitlark-20260927-controlplaneagent-chat-wiring-computes-a]
- [ ] [T2] backend/app/services/conversation.py — Add a helper function `execute_ops_tool_calls(tool_calls: List[Dict], ctx: ControlPlaneContext) -> List[Dict]` that iterates through tool calls, invokes `execute_tool_call` for each, and collects the results into a list. VERIFY: `pytest backend/tests/test_conversation.py::test_execute_ops_tool_calls -v`. (cat:python; multifile:no) [feat:gitlark-20260927-controlplaneagent-chat-wiring-computes-a]
- [ ] [T3] backend/app/services/conversation.py — Modify `add_message` to call `build_control_plane_context` and `execute_ops_tool_calls` when `is_ops_intent` is true, replacing the current `logger.info` call with logic that appends the result of `format_control_plane_response` to `conversation.messages`. VERIFY: `pytest backend/tests/test_conversation.py::test_add_message_ops_intent_appends_response -v`. (cat:python; multifile:no) [feat:gitlark-20260927-controlplaneagent-chat-wiring-computes-a]
- [ ] [T4] backend/tests/test_conversation.py — Create a new test file or add tests that mock `ControlPlaneAgent.decide` and `extract_tool_calls` to return a known tool call, then assert that `execute_tool_call` is called and the final message in `conversation.messages` matches the output of `format_control_plane_response`. VERIFY: `pytest backend/tests/test_conversation.py -v`. (cat:test; multifile:no) [feat:gitlark-20260927-controlplaneagent-chat-wiring-computes-a]
- [ ] [T5] backend/app/services/conversation.py — Ensure `ControlPlaneContext` imports are correct and that `session` and `access_token` are properly passed from the `add_message` scope to the new helper functions, handling cases where `project_config` might be null or missing a token by raising a specific exception or logging a warning. VERIFY: `python -m mypy backend/app/services/conversation.py`. (cat:python; multifile:no) [feat:gitlark-20260927-controlplaneagent-chat-wiring-computes-a]

# --- 27B-decomposed from roadmap [2026-09-27]: **Delete three dead, superseded single-purpose service duplicates: `ClaudeAgent`, `GitHubI (review + tweak) [feat:gitlark-20260927-delete-three-dead-superseded-single-purp] ---
- [ ] [T1] backend/app/services/claude_agent.py — Delete the file containing the dead `ClaudeAgent` class. VERIFY: `test -f backend/app/services/claude_agent.py && echo "FAIL" || echo "PASS"`. (cat:refactor; multifile:no) [feat:gitlark-20260927-delete-three-dead-superseded-single-purp]
- [ ] [T1] backend/tests/test_claude_agent.py — Delete the dedicated test file for the removed `ClaudeAgent` service. VERIFY: `test -f backend/tests/test_claude_agent.py && echo "FAIL" || echo "PASS"`. (cat:test; multifile:no) [feat:gitlark-20260927-delete-three-dead-superseded-single-purp]
- [ ] [T1] backend/app/services/github_integration_service.py — Delete the file containing the dead `GitHubIntegrationService` class. VERIFY: `test -f backend/app/services/github_integration_service.py && echo "FAIL" || echo "PASS"`. (cat:refactor; multifile:no) [feat:gitlark-20260927-delete-three-dead-superseded-single-purp]
- [ ] [T1] backend/tests/test_github_integration_service.py — Delete the dedicated test file for the removed `GitHubIntegrationService` service. VERIFY: `test -f backend/tests/test_github_integration_service.py && echo "FAIL" || echo "PASS"`. (cat:test; multifile:no) [feat:gitlark-20260927-delete-three-dead-superseded-single-purp]
- [ ] [T1] backend/app/services/plan_service.py — Delete the file containing the dead `PlanService` class. VERIFY: `test -f backend/app/services/plan_service.py && echo "FAIL" || echo "PASS"`. (cat:refactor; multifile:no) [feat:gitlark-20260927-delete-three-dead-superseded-single-purp]
- [ ] [T1] backend/tests/test_plan_service.py — Delete the dedicated test file for the removed `PlanService` service. VERIFY: `test -f backend/tests/test_plan_service.py && echo "FAIL" || echo "PASS"`. (cat:test; multifile:no) [feat:gitlark-20260927-delete-three-dead-superseded-single-purp]
- [ ] [T2] backend/app — Verify no remaining imports of the deleted modules exist in the codebase. VERIFY: `grep -r "from app.services.claude_agent import\|from app.services.github_integration_service import\|from app.services.plan_service import" backend/app --include="*.py" | grep -v "test_" | wc -l` returns 0. (cat:refactor; multifile:yes) [feat:gitlark-20260927-delete-three-dead-superseded-single-purp]

# --- 27B-decomposed from roadmap [2026-09-27]: **Delete dead dispatch-domain scaffolding superseded by `DispatcherService`'s real impleme (review + tweak) [feat:gitlark-20260927-delete-dead-dispatch-domain-scaffolding-] ---
- [ ] [T1] backend/app/services/dispatch_dedup.py — Delete the entire file containing `is_duplicate_dispatch`, `record_dispatch`, and `filter_undispatched`. VERIFY: `test -f backend/app/services/dispatch_dedup.py && echo "FAIL" || echo "PASS"`. (cat:python; multifile:no) [feat:gitlark-20260927-delete-dead-dispatch-domain-scaffolding-]
- [ ] [T1] backend/tests/test_dispatch_dedup.py — Delete the entire test file for the removed dispatch dedup module. VERIFY: `test -f backend/tests/test_dispatch_dedup.py && echo "FAIL" || echo "PASS"`. (cat:test; multifile:no) [feat:gitlark-20260927-delete-dead-dispatch-domain-scaffolding-]
- [ ] [T2] backend/app/services/dispatcher.py — Remove the `commit_task_to_git()` function definition and its docstring. VERIFY: `grep -q "def commit_task_to_git" backend/app/services/dispatcher.py && echo "FAIL" || echo "PASS"`. (cat:python; multifile:no) [feat:gitlark-20260927-delete-dead-dispatch-domain-scaffolding-]
- [ ] [T2] backend/app/services/dispatcher.py — Remove the `dispatch_flow()` function definition and its docstring. VERIFY: `grep -q "def dispatch_flow" backend/app/services/dispatcher.py && echo "FAIL" || echo "PASS"`. (cat:python; multifile:no) [feat:gitlark-20260927-delete-dead-dispatch-domain-scaffolding-]
- [ ] [T2] backend/app/services/dispatcher.py — Remove the `queue_action_from_chat()` function definition and its docstring. VERIFY: `grep -q "def queue_action_from_chat" backend/app/services/dispatcher.py && echo "FAIL" || echo "PASS"`. (cat:python; multifile:no) [feat:gitlark-20260927-delete-dead-dispatch-domain-scaffolding-]
- [ ] [T2] backend/tests/test_dispatcher.py — Remove all test cases and assertions that call `commit_task_to_git`, `dispatch_flow`, or `queue_action_from_chat`. VERIFY: `grep -E "commit_task_to_git|dispatch_flow|queue_action_from_chat" backend/tests/test_dispatcher.py && echo "FAIL" || echo "PASS"`. (cat:test; multifile:no) [feat:gitlark-20260927-delete-dead-dispatch-domain-scaffolding-]
- [ ] [T3] backend/app/services/dispatcher.py — Verify that `task_marker` and the `DispatcherService` class remain intact and functional. VERIFY: `grep -q "def task_marker" backend/app/services/dispatcher.py && grep -q "class DispatcherService" backend/app/services/dispatcher.py && echo "PASS" || echo "FAIL"`. (cat:python; multifile:no) [feat:gitlark-20260927-delete-dead-dispatch-domain-scaffolding-]
- [ ] [T4] backend/tests/test_dispatcher.py — Run the remaining test suite to ensure no regressions in `DispatcherService` tests after removing dead code. VERIFY: `cd backend && python -m pytest tests/test_dispatcher.py -v --tb=short`. (cat:test; multifile:yes) [feat:gitlark-20260927-delete-dead-dispatch-domain-scaffolding-]

# --- 27B-decomposed from roadmap [2026-09-27]: **Consolidate/delete two dead, mutually-inconsistent GitHub-webhook-classification pure fu (review + tweak) [feat:gitlark-20260927-consolidate-delete-two-dead-mutually-inc] ---
- [ ] [T4] backend/app/services/github_payload.py — Delete the file containing `normalize_pull_request_payload()` as it is dead code with inconsistent logic. VERIFY: `test -f backend/app/services/github_payload.py && echo "FAIL" || echo "PASS"` (cat:refactor; multifile:no) [feat:gitlark-20260927-consolidate-delete-two-dead-mutually-inc]
- [ ] [T4] backend/app/services/webhook_events.py — Delete the file containing `classify_webhook_event()` as it is dead code with inconsistent logic. VERIFY: `test -f backend/app/services/webhook_events.py && echo "FAIL" || echo "PASS"` (cat:refactor; multifile:no) [feat:gitlark-20260927-consolidate-delete-two-dead-mutually-inc]
- [ ] [T4] backend/tests/test_github_payload.py — Delete the test file for the removed `github_payload` module. VERIFY: `test -f backend/tests/test_github_payload.py && echo "FAIL" || echo "PASS"` (cat:test; multifile:no) [feat:gitlark-20260927-consolidate-delete-two-dead-mutually-inc]
- [ ] [T4] backend/tests/test_webhook_events.py — Delete the test file for the removed `webhook_events` module. VERIFY: `test -f backend/tests/test_webhook_events.py && echo "FAIL" || echo "PASS"` (cat:test; multifile:no) [feat:gitlark-20260927-consolidate-delete-two-dead-mutually-inc]
- [ ] [T3] backend/app/routers/github_webhook.py — Verify `_REVIEWABLE_ACTIONS` contains exactly `{"opened", "synchronize", "reopened", "ready_for_review"}` and is used in the handler logic. VERIFY: `grep -q '_REVIEWABLE_ACTIONS = {"opened", "synchronize", "reopened", "ready_for_review"}' backend/app/routers/github_webhook.py` (cat:python; multifile:no) [feat:gitlark-20260927-consolidate-delete-two-dead-mutually-inc]
- [ ] [T1] backend/tests/test_github_webhook_actions.py — Create a new unit test asserting that `ready_for_review` is included in the set of actions triggering auto-review logic. VERIFY: `pytest backend/tests/test_github_webhook_actions.py -v` (cat:test; multifile:no) [feat:gitlark-20260927-consolidate-delete-two-dead-mutually-inc]
- [ ] [T1] backend/tests/test_github_webhook_actions.py — Add a test case asserting that `closed` and `labeled` are NOT in the reviewable actions set. VERIFY: `pytest backend/tests/test_github_webhook_actions.py::test_non_reviewable_actions -v` (cat:test; multifile:no) [feat:gitlark-20260927-consolidate-delete-two-dead-mutually-inc]
- [ ] [T4] backend/app/routers/github_webhook.py — Ensure no imports remain from `app.services.github_payload` or `app.services.webhook_events`. VERIFY: `grep -r "from app.services.github_payload import" backend/ && grep -r "from app.services.webhook_events import" backend/ && echo "FAIL" || echo "PASS"` (cat:refactor; multifile:no) [feat:gitlark-20260927-consolidate-delete-two-dead-mutually-inc]
