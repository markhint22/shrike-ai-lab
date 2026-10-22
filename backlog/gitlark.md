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

# --- 27B-decomposed from roadmap [2026-09-29]: **Wire `TemporalNavigation.vue` into `ConversationDetailPage.vue` — the backend endpoint i (review + tweak) [feat:gitlark-20260929-wire-temporalnavigation-vue-into-convers] ---

# --- 27B-decomposed from roadmap [2026-09-29]: **Add component tests for the three components `ConversationDetailPage.vue` actually mount (review + tweak) [feat:gitlark-20260929-add-component-tests-for-the-three-compon] ---

# --- 27B-decomposed from roadmap [2026-09-29]: **Batch cleanup: four more small, genuinely dead pure-helper modules found in the same swe (review + tweak) [feat:gitlark-20260929-batch-cleanup-four-more-small-genuinely-] ---

# --- 27B-decomposed from roadmap [2026-09-30]: Fix queue-file data loss: GitHubClient.get_file_content has no branch/ref and swallows eve (review + tweak) [feat:gitlark-20260930-fix-queue-file-data-loss-githubclient-ge] ---

# --- 27B-decomposed from roadmap [2026-09-30]: Dispatcher reports success when the GitHub write silently failed — `create_or_update_file` (review + tweak) [feat:gitlark-20260930-dispatcher-reports-success-when-the-gith] ---

# --- 27B-decomposed from roadmap [2026-09-30]: Fix double `/api` prefix that 404s control-plane and notification-feed calls in production (review + tweak) [feat:gitlark-20260930-fix-double-api-prefix-that-404s-control-] ---

# --- 27B-decomposed from roadmap [2026-09-30]: Make the control-plane Pause/Promote store actually work with the confirmation gate — `web (review + tweak) [feat:gitlark-20260930-make-the-control-plane-pause-promote-sto] ---

# --- 27B-decomposed from roadmap [2026-09-30]: Fail closed on the committed placeholder JWT secret — `railway.toml:11` commits `SECRET_KE (review + tweak) [feat:gitlark-20260930-fail-closed-on-the-committed-placeholder] ---

# --- 27B-decomposed from roadmap [2026-09-30]: Add real OAuth `state` (login CSRF) — `backend/app/routers/auth.py:24` hardcodes `"state": (review + tweak) [feat:gitlark-20260930-add-real-oauth-state-login-csrf-backend-] ---

# --- 27B-decomposed from roadmap [2026-09-30]: Session expiry silently kills the PWA every 30 minutes — `backend/app/routers/auth.py:68`  (review + tweak) [feat:gitlark-20260930-session-expiry-silently-kills-the-pwa-ev] ---

# --- 27B-decomposed from roadmap [2026-09-30]: Privacy Policy promises erasure and portability but no account deletion/export endpoint ex (review + tweak) [feat:gitlark-20260930-privacy-policy-promises-erasure-and-port] ---

# --- 27B-decomposed from roadmap [2026-09-30]: Encrypt `users.github_token` at rest — `backend/app/models/user.py:19` stores the full-sco (review + tweak) [feat:gitlark-20260930-encrypt-users-github-token-at-rest-backe] ---

# --- 27B-decomposed from roadmap [2026-10-01]: Stop webhook review comment spam, duplicate runs, and cross-tenant PAT use — `backend/app/ (review + tweak) [feat:gitlark-20261001-stop-webhook-review-comment-spam-duplica] ---

# --- 27B-decomposed from roadmap [2026-10-01]: Realtime WebSocket is an unauthorized no-op with a path mismatch — `backend/app/routers/we (review + tweak) [feat:gitlark-20261001-realtime-websocket-is-an-unauthorized-no] ---

# --- 27B-decomposed from roadmap [2026-10-01]: Sanitize task text before it becomes a backlog line and harden the `/api/v1/tasks/enqueue` (review + tweak) [feat:gitlark-20261001-sanitize-task-text-before-it-becomes-a-b] ---

# --- 27B-decomposed from roadmap [2026-10-02]: NotificationEventResponse/NotificationEvent frontend schema mismatch — `backend/app/router (review + tweak) [feat:gitlark-20261002-notificationeventresponse-notificationev] ---

# --- 27B-decomposed from roadmap [2026-10-02]: FeatureFlagService always returns `{}` — per-request instantiation discards all state — `b (review + tweak) [feat:gitlark-20261002-featureflagservice-always-returns-per-re] ---

# --- 27B-decomposed from roadmap [2026-10-02]: `list_notification_events` runs unbounded DB query — `backend/app/routers/notifications_fe (review + tweak) [feat:gitlark-20261002-list-notification-events-runs-unbounded-] ---

# --- 27B-decomposed from roadmap [2026-10-02]: `task_to_backlog_line` path-normalization branch and format output are completely untested (review + tweak) [feat:gitlark-20261002-task-to-backlog-line-path-normalization-] ---

# --- 27B-decomposed from roadmap [2026-10-03]: Fix systemic `len(scalars().all())` COUNT anti-pattern across pagination and unread-count  (review + tweak) [feat:gitlark-20261003-fix-systemic-len-scalars-all-count-anti-] ---

# --- 27B-decomposed from roadmap [2026-10-03]: `memory.py` uses volatile `github_token` as per-user encryption key — token rotation perma (review + tweak) [feat:gitlark-20261003-memory-py-uses-volatile-github-token-as-] ---

# --- 27B-decomposed from roadmap [2026-10-03]: `ConversationSearchService.search()` applies text-query `q` in Python after loading all wo (review + tweak) [feat:gitlark-20261003-conversationsearchservice-search-applies] ---

# --- 27B-decomposed from roadmap [2026-10-03]: Billing webhook missing `invoice.payment_failed` handler — `subscription_status` never set (review + tweak) [feat:gitlark-20261003-billing-webhook-missing-invoice-payment-] ---

# --- deterministic work supply 2026-10-14 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- deterministic work supply 2026-10-15 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- deterministic work supply 2026-10-16 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- deterministic work supply 2026-10-17 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- deterministic work supply 2026-10-17 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- deterministic work supply 2026-10-17 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- 27B-decomposed from roadmap [2026-10-17]: `enforce_token_budget` compares cumulative monthly tokens against per-request ceiling — fa (review + tweak) [feat:gitlark-20261017-enforce-token-budget-compares-cumulative] ---

# --- 27B-decomposed from roadmap [2026-10-17]: Fleet Activity tab silently 404s in production — `notificationsFeed.ts` double-`/api` pref (review + tweak) [feat:gitlark-20261017-fleet-activity-tab-silently-404s-in-prod] ---

# --- 27B-decomposed from roadmap [2026-10-17]: Duplicate `redact_secrets` in `core/security.py` is dead code with its own test — `backend (review + tweak) [feat:gitlark-20261017-duplicate-redact-secrets-in-core-securit] ---

# --- 27B-decomposed from roadmap [2026-10-17]: Fleet introduced a dead `feature_flag_service.py` stub alongside the 2026-10-02 singleton  (review + tweak) [feat:gitlark-20261017-fleet-introduced-a-dead-feature-flag-ser] ---

# --- 27B-decomposed from roadmap [2026-10-17]: `conversation_service.py`'s `should_invoke_control_plane` is dead — not wired to any produ (review + tweak) [feat:gitlark-20261017-conversation-service-py-s-should-invoke-] ---

# --- 27B-decomposed from roadmap [2026-10-18]: Fix ExponentialBackoffRetry.execute() to skip non-retryable errors — `backend/app/services (review + tweak) [feat:gitlark-20261018-fix-exponentialbackoffretry-execute-to-s] ---

# --- deterministic work supply 2026-10-18 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- deterministic work supply 2026-10-18 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- 27B-decomposed from roadmap [2026-10-18]: Fix check_rate_limit() to count ApiUsage rows, not Conversation rows — `backend/app/servic (review + tweak) [feat:gitlark-20261018-fix-check-rate-limit-to-count-apiusage-r] ---

# --- 27B-decomposed from roadmap [2026-10-18]: Fix can_auto_merge() AttributeError when severity key is None — `backend/app/services/auto (review + tweak) [feat:gitlark-20261018-fix-can-auto-merge-attributeerror-when-s] ---

# --- 27B-decomposed from roadmap [2026-10-18]: Upgrade EncryptionService._derive_key from single-round SHA256 to PBKDF2HMAC — `backend/ap (review + tweak) [feat:gitlark-20261018-upgrade-encryptionservice-derive-key-fro] ---

# --- 27B-decomposed from roadmap [2026-10-19]: Fix billing _on_subscription_updated silently dropping tier when price_id is unrecognized  (review + tweak) [feat:gitlark-20261019-fix-billing-on-subscription-updated-sile] ---

# --- 27B-decomposed from roadmap [2026-10-19]: Fix scheduler.py N+1 SyncJob queries — `backend/app/services/scheduler.py:68-86`: fetches  (review + tweak) [feat:gitlark-20261019-fix-scheduler-py-n-1-syncjob-queries-bac] ---

# --- deterministic work supply 2026-10-19 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- 27B-decomposed from roadmap [2026-10-19]: Add VSCode extension commands for plan creation and fleet status — `vscode-extension/src/e (review + tweak) [feat:gitlark-20261019-add-vscode-extension-commands-for-plan-c] ---

# --- 27B-decomposed from roadmap [2026-10-19]: Add unit tests for `hash_password` and `verify_password` — `backend/app/core/security.py:2 (review + tweak) [feat:gitlark-20261019-add-unit-tests-for-hash-password-and-ver] ---

# --- 27B-decomposed from roadmap [2026-10-19]: Add unit tests for `connector_conflict_exception_handler` and `handle_dispatch_write_error (review + tweak) [feat:gitlark-20261019-add-unit-tests-for-connector-conflict-ex] ---

# --- 27B-decomposed from roadmap [2026-10-19]: Add unit tests for `validate_diff_pagination_params` — `backend/app/main.py:29` is a publi (review + tweak) [feat:gitlark-20261019-add-unit-tests-for-validate-diff-paginat] ---

# --- deterministic work supply 2026-10-20 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- deterministic work supply 2026-10-20 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- 27B-decomposed from roadmap [2026-10-20]: Test `health_check` and `status_endpoint` — `backend/app/main.py:162` and `backend/app/mai (review + tweak) [feat:gitlark-20261020-test-health-check-and-status-endpoint-ba] ---

# --- 27B-decomposed from roadmap [2026-10-20]: Test `metrics_endpoint` — `backend/app/main.py:216` is a public endpoint with zero test co (review + tweak) [feat:gitlark-20261020-test-metrics-endpoint-backend-app-main-p] ---

# --- deterministic work supply 2026-10-20 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- 27B-decomposed from roadmap [2026-10-21]: Test `get_diffs` — `backend/app/main.py:242` is a public endpoint with zero test coverage; (review + tweak) [feat:gitlark-20261021-test-get-diffs-backend-app-main-py-242-i] ---

# --- 27B-decomposed from roadmap [2026-10-21]: Test `lifespan` context manager — `backend/app/main.py:43` is a public async context manag (review + tweak) [feat:gitlark-20261021-test-lifespan-context-manager-backend-ap] ---

# --- 27B-decomposed from roadmap [2026-10-21]: Test `configure_logging` — `backend/app/core/logging_config.py:23` is a public function wi (review + tweak) [feat:gitlark-20261021-test-configure-logging-backend-app-core-] ---

# --- 27B-decomposed from roadmap [2026-10-21]: Test `get_current_user_optional` — `backend/app/core/dependencies.py:45` is a public depen (review + tweak) [feat:gitlark-20261021-test-get-current-user-optional-backend-a] ---

# --- deterministic work supply 2026-10-21 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- 27B-decomposed from roadmap [2026-10-21]: Test review rules CRUD and template application — `backend/app/routers/review_rules.py:47` (review + tweak) [feat:gitlark-20261021-test-review-rules-crud-and-template-appl] ---

# --- 27B-decomposed from roadmap [2026-10-21]: Test agent conversation and marketplace endpoints — `backend/app/routers/agents.py:138` (` (review + tweak) [feat:gitlark-20261021-test-agent-conversation-and-marketplace-] ---

# --- 27B-decomposed from roadmap [2026-10-21]: Test database initialization — `backend/app/core/database.py:33` (`init_db`) is a public f (review + tweak) [feat:gitlark-20261021-test-database-initialization-backend-app] ---

# --- deterministic work supply 2026-10-21 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- 27B-decomposed from roadmap [2026-10-21]: Test `list_snippets` and `search_public_snippets` — `backend/app/routers/snippet.py:131` a (review + tweak) [feat:gitlark-20261021-test-list-snippets-and-search-public-sni] ---

# --- 27B-decomposed from roadmap [2026-10-21]: Test `record_use` and `get_stats` — `backend/app/routers/snippet.py:357` and `backend/app/ (review + tweak) [feat:gitlark-20261021-test-record-use-and-get-stats-backend-ap] ---

# --- 27B-decomposed from roadmap [2026-10-21]: Test code review CRUD and analysis — `backend/app/routers/code_review.py:164` (`map_code_r (review + tweak) [feat:gitlark-20261021-test-code-review-crud-and-analysis-backe] ---

# --- 27B-decomposed from roadmap [2026-10-21]: Test `resolve_comment` and `add_suggestion` — `backend/app/routers/code_review.py:331` (`r (review + tweak) [feat:gitlark-20261021-test-resolve-comment-and-add-suggestion-] ---

# --- 27B-decomposed from roadmap [2026-10-21]: Test `enqueue_task` — `backend/app/routers/tasks.py:19` is a public endpoint with zero tes (review + tweak) [feat:gitlark-20261021-test-enqueue-task-backend-app-routers-ta] ---

# --- 27B-decomposed from roadmap [2026-10-21]: Test `handle_file_error` — `backend/app/routers/github.py:52` is a public function with ze (review + tweak) [feat:gitlark-20261021-test-handle-file-error-backend-app-route] ---

# --- 27B-decomposed from roadmap [2026-10-21]: Test `websocket_endpoint` — `backend/app/routers/websocket.py:64` is a public async endpoi (review + tweak) [feat:gitlark-20261021-test-websocket-endpoint-backend-app-rout] ---

# --- 27B-decomposed from roadmap [2026-10-21]: Test `update_review_status` — `backend/app/routers/code_review.py:424` is a public endpoin (review + tweak) [feat:gitlark-20261021-test-update-review-status-backend-app-ro] ---

# --- 27B-decomposed from roadmap [2026-10-21]: Test `enqueue_action` — `backend/app/routers/control_plane.py:69` is a public endpoint wit (review + tweak) [feat:gitlark-20261021-test-enqueue-action-backend-app-routers-] ---

# --- 27B-decomposed from roadmap [2026-10-22]: Test `get_template_stats` and `browse_template_marketplace` — `backend/app/routers/agents. (review + tweak) [feat:gitlark-20261022-test-get-template-stats-and-browse-templ] ---

# --- deterministic work supply 2026-10-22 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- deterministic work supply 2026-10-22 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- 27B-decomposed from roadmap [2026-10-22]: Test `browse_chain_marketplace` — `backend/app/routers/agents.py:515` is a public endpoint (review + tweak) [feat:gitlark-20261022-test-browse-chain-marketplace-backend-ap] ---

# --- 27B-decomposed from roadmap [2026-10-22]: Use PR state to determine landed status — `backend/app/services/dispatch_status.py:15` (`c (review + tweak) [feat:gitlark-20261022-use-pr-state-to-determine-landed-status-] ---

# --- deterministic work supply 2026-10-22 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- 27B-decomposed from roadmap [2026-10-22]: Fix send_direct to return accurate status when connection is missing or send fails — `back (review + tweak) [feat:gitlark-20261022-fix-send-direct-to-return-accurate-statu] ---

# --- 27B-decomposed from roadmap [2026-10-22]: Test `connector_conflict_exception_handler` — `backend/app/main.py:99` is a public excepti (review + tweak) [feat:gitlark-20261022-test-connector-conflict-exception-handle] ---
