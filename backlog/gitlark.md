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

# --- 27B-decomposed from roadmap [2026-10-22]: Test `record_use` snippet endpoint — `backend/app/routers/snippet.py:406` is a public func (review + tweak) [feat:gitlark-20261022-test-record-use-snippet-endpoint-backend] ---

# --- 27B-decomposed from roadmap [2026-10-22]: Test `analyze_code_review` endpoint — `backend/app/routers/code_review.py:193` is a public (review + tweak) [feat:gitlark-20261022-test-analyze-code-review-endpoint-backen] ---

# --- 27B-decomposed from roadmap [2026-10-23]: Test `list_review_rules` and `create_review_rule` — `backend/app/routers/review_rules.py:4 (review + tweak) [feat:gitlark-20261023-test-list-review-rules-and-create-review] ---

# --- 27B-decomposed from roadmap [2026-10-23]: Test `update_review_rule` and `delete_review_rule` — `backend/app/routers/review_rules.py: (review + tweak) [feat:gitlark-20261023-test-update-review-rule-and-delete-revie] ---

# --- 27B-decomposed from roadmap [2026-10-23]: Test `create_code_review` and `get_code_review` — `backend/app/routers/code_review.py:212` (review + tweak) [feat:gitlark-20261023-test-create-code-review-and-get-code-rev] ---

# --- 27B-decomposed from roadmap [2026-10-23]: Test `add_comment` on code reviews — `backend/app/routers/code_review.py:271` is a public  (review + tweak) [feat:gitlark-20261023-test-add-comment-on-code-reviews-backend] ---

# --- 27B-decomposed from roadmap [2026-10-23]: Test `dispatch_action` control plane endpoint — `backend/app/routers/control_plane.py:95`  (review + tweak) [feat:gitlark-20261023-test-dispatch-action-control-plane-endpo] ---

# --- 27B-decomposed from roadmap [2026-10-23]: Test `pause_fleet_action` — `backend/app/routers/control_plane.py:179` is a public endpoin (review + tweak) [feat:gitlark-20261023-test-pause-fleet-action-backend-app-rout] ---

# --- 27B-decomposed from roadmap [2026-10-23]: Test `get_fleet_status` — `backend/app/routers/fleet_status.py:84` is a public endpoint wi (review + tweak) [feat:gitlark-20261023-test-get-fleet-status-backend-app-router] ---

# --- 27B-decomposed from roadmap [2026-10-24]: Test `get_review_comments` endpoint — `backend/app/routers/code_review.py:312` is a public (review + tweak) [feat:gitlark-20261024-test-get-review-comments-endpoint-backen] ---

# --- 27B-decomposed from roadmap [2026-10-24]: Complete get_message_reactions endpoint to return reaction data — `backend/app/services/re (review + tweak) [feat:gitlark-20261024-complete-get-message-reactions-endpoint-] ---

# --- 27B-decomposed from roadmap [2026-10-24]: Add auth dependency to get_active_reviewers — `backend/app/routers/review_collab.py:152` ( (review + tweak) [feat:gitlark-20261024-add-auth-dependency-to-get-active-review] ---

# --- 27B-decomposed from roadmap [2026-10-24]: Fix UnboundLocalError in add_reaction when reaction exists — `backend/app/services/reactio (review + tweak) [feat:gitlark-20261024-fix-unboundlocalerror-in-add-reaction-wh] ---

# --- 27B-decomposed from roadmap [2026-10-24]: Test `post_overnight_progress` — `backend/app/routers/fleet_status.py:156` is a public end (review + tweak) [feat:gitlark-20261024-test-post-overnight-progress-backend-app] ---

# --- 27B-decomposed from roadmap [2026-10-24]: Test `ingest_event` — `backend/app/routers/notifications_ingest.py:60` is a public functio (review + tweak) [feat:gitlark-20261024-test-ingest-event-backend-app-routers-no] ---

# --- 27B-decomposed from roadmap [2026-10-24]: Test `billing_status` — `backend/app/routers/billing.py:44` is a public endpoint with zero (review + tweak) [feat:gitlark-20261024-test-billing-status-backend-app-routers-] ---

# --- 27B-decomposed from roadmap [2026-10-24]: Fix get_connector_credential returning hardcoded values — `backend/app/routers/connector_c (review + tweak) [feat:gitlark-20261024-fix-get-connector-credential-returning-h] ---

# --- 27B-decomposed from roadmap [2026-10-25]: Test `billing_usage` endpoint — `backend/app/routers/billing.py:71` is a public endpoint w (review + tweak) [feat:gitlark-20261025-test-billing-usage-endpoint-backend-app-] ---

# --- 27B-decomposed from roadmap [2026-10-25]: Test `stripe_webhook` endpoint — `backend/app/routers/billing.py:132` is a public function (review + tweak) [feat:gitlark-20261025-test-stripe-webhook-endpoint-backend-app] ---

# --- 27B-decomposed from roadmap [2026-10-25]: Test `github_oauth_url` — `backend/app/routers/auth.py:21` is a public function with zero  (review + tweak) [feat:gitlark-20261025-test-github-oauth-url-backend-app-router] ---

# --- 27B-decomposed from roadmap [2026-10-25]: Test `get_me` auth endpoint — `backend/app/routers/auth.py:99` is a public function with z (review + tweak) [feat:gitlark-20261025-test-get-me-auth-endpoint-backend-app-ro] ---

# --- 27B-decomposed from roadmap [2026-10-25]: Test `refresh_token_endpoint` — `backend/app/routers/auth.py:139` is a public endpoint wit (review + tweak) [feat:gitlark-20261025-test-refresh-token-endpoint-backend-app-] ---

# --- 27B-decomposed from roadmap [2026-10-25]: Test `export_conversation_json` — `backend/app/routers/export.py:18` is a public endpoint  (review + tweak) [feat:gitlark-20261025-test-export-conversation-json-backend-ap] ---

# --- deterministic work supply 2026-10-25 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- 27B-decomposed from roadmap [2026-10-25]: Test `archive_conversation` — `backend/app/routers/export.py:73` is a public endpoint with (review + tweak) [feat:gitlark-20261025-test-archive-conversation-backend-app-ro] ---

# --- 27B-decomposed from roadmap [2026-10-25]: Test `export_workspace_conversations` — `backend/app/routers/export.py:88` is a public end (review + tweak) [feat:gitlark-20261025-test-export-workspace-conversations-back] ---

# --- 27B-decomposed from roadmap [2026-10-25]: Test `create_connector_credential` — `backend/app/routers/connector_credentials.py:51` is  (review + tweak) [feat:gitlark-20261025-test-create-connector-credential-backend] ---

# --- 27B-decomposed from roadmap [2026-10-25]: Test `list_connector_credentials` — `backend/app/routers/connector_credentials.py:93` is a (review + tweak) [feat:gitlark-20261025-test-list-connector-credentials-backend-] ---

# --- 27B-decomposed from roadmap [2026-10-25]: Parallelize dependency file fetching in RepoAnalyzer — `backend/app/services/repo_analyzer (review + tweak) [feat:gitlark-20261025-parallelize-dependency-file-fetching-in-] ---

# --- 27B-decomposed from roadmap [2026-10-25]: Test `analyze_code_review` in review router — `backend/app/routers/review.py:79` is a publ (review + tweak) [feat:gitlark-20261025-test-analyze-code-review-in-review-route] ---

# --- 27B-decomposed from roadmap [2026-10-26]: Fix code snippet truncation byte/string mismatch — `backend/app/routers/repo_analysis.py:3 (review + tweak) [feat:gitlark-20261026-fix-code-snippet-truncation-byte-string-] ---

# --- 27B-decomposed from roadmap [2026-10-26]: Fix edit_message to use message ID instead of list index — `backend/app/routers/conversati (review + tweak) [feat:gitlark-20261026-fix-edit-message-to-use-message-id-inste] ---

# --- 27B-decomposed from roadmap [2026-10-26]: Test `map_code_review_result_to_schema` — `backend/app/routers/code_review.py:164` is a pu (review + tweak) [feat:gitlark-20261026-test-map-code-review-result-to-schema-ba] ---

# --- 27B-decomposed from roadmap [2026-10-26]: Test `review_github_pr` endpoint — `backend/app/routers/review.py:126` is a public functio (review + tweak) [feat:gitlark-20261026-test-review-github-pr-endpoint-backend-a] ---

# --- 27B-decomposed from roadmap [2026-10-26]: Test `get_pr_summary` endpoint — `backend/app/routers/review.py:228` is a public function  (review + tweak) [feat:gitlark-20261026-test-get-pr-summary-endpoint-backend-app] ---

# --- 27B-decomposed from roadmap [2026-10-26]: Test `get_project_config` endpoint — `backend/app/routers/project_config.py:52` is a publi (review + tweak) [feat:gitlark-20261026-test-get-project-config-endpoint-backend] ---

# --- 27B-decomposed from roadmap [2026-10-26]: Test `look_at_failure_action` — `backend/app/routers/control_plane.py:148` is a public end (review + tweak) [feat:gitlark-20261026-test-look-at-failure-action-backend-app-] ---

# --- 27B-decomposed from roadmap [2026-10-26]: Test `initialize_agent` — `backend/app/routers/ai_agents.py:64` is a public function with  (review + tweak) [feat:gitlark-20261026-test-initialize-agent-backend-app-router] ---

# --- 27B-decomposed from roadmap [2026-10-26]: Test `query_agent` and `get_agent_status` — `backend/app/routers/ai_agents.py:193` (`query (review + tweak) [feat:gitlark-20261026-test-query-agent-and-get-agent-status-ba] ---

# --- 27B-decomposed from roadmap [2026-10-26]: Test `list_workspaces` — `backend/app/routers/workspaces.py:40` is a public function with  (review + tweak) [feat:gitlark-20261026-test-list-workspaces-backend-app-routers] ---

# --- 27B-decomposed from roadmap [2026-10-27]: Test `approve_plan` and `dispatch_plan` — `backend/app/routers/plans.py:244` (`approve_pla (review + tweak) [feat:gitlark-20261027-test-approve-plan-and-dispatch-plan-back] ---

# --- 27B-decomposed from roadmap [2026-10-27]: Test `github_app_callback` — `backend/app/routers/github_app.py:35` is a public endpoint w (review + tweak) [feat:gitlark-20261027-test-github-app-callback-backend-app-rou] ---

# --- 27B-decomposed from roadmap [2026-10-27]: Test `get_workspace_installation` — `backend/app/routers/github_app.py:120` is a public en (review + tweak) [feat:gitlark-20261027-test-get-workspace-installation-backend-] ---

# --- 27B-decomposed from roadmap [2026-10-27]: Test `get_workspace_metadata` — `backend/app/routers/metadata.py:17` is a public endpoint  (review + tweak) [feat:gitlark-20261027-test-get-workspace-metadata-backend-app-] ---

# --- 27B-decomposed from roadmap [2026-10-27]: Test `get_repository_metadata` — `backend/app/routers/metadata.py:52` is a public endpoint (review + tweak) [feat:gitlark-20261027-test-get-repository-metadata-backend-app] ---

# --- 27B-decomposed from roadmap [2026-10-27]: Prune old error timestamps in get_error_rate to prevent memory leak — `backend/app/service (review + tweak) [feat:gitlark-20261027-prune-old-error-timestamps-in-get-error-] ---

# --- 27B-decomposed from roadmap [2026-10-27]: Test `trigger_metadata_sync` — `backend/app/routers/metadata.py:103` is a public endpoint  (review + tweak) [feat:gitlark-20261027-test-trigger-metadata-sync-backend-app-r] ---

# --- 27B-decomposed from roadmap [2026-10-27]: Test `extract_key_points` — `backend/app/routers/conversations.py:28` is a public function (review + tweak) [feat:gitlark-20261027-test-extract-key-points-backend-app-rout] ---

# --- 27B-decomposed from roadmap [2026-10-27]: Test `get_unread_count` — `backend/app/routers/notifications_feed.py:82` is a public funct (review + tweak) [feat:gitlark-20261027-test-get-unread-count-backend-app-router] ---

# --- 27B-decomposed from roadmap [2026-10-27]: Fix background task DB session usage — `backend/app/routers/repo_analysis.py:111` (`analyz (review + tweak) [feat:gitlark-20261027-fix-background-task-db-session-usage-bac] ---

# --- 27B-decomposed from roadmap [2026-10-27]: Test `send_message` conversation endpoint — `backend/app/routers/conversations.py:157` is  (review + tweak) [feat:gitlark-20261027-test-send-message-conversation-endpoint-] ---

# --- 27B-decomposed from roadmap [2026-10-27]: Test `toggle_pin_conversation` endpoint — `backend/app/routers/conversations.py:233` is a  (review + tweak) [feat:gitlark-20261027-test-toggle-pin-conversation-endpoint-ba] ---

# --- deterministic work supply 2026-10-27 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- 27B-decomposed from roadmap [2026-10-27]: Test `add_suggestion` endpoint — `backend/app/routers/code_review.py:369` is a public func (review + tweak) [feat:gitlark-20261027-test-add-suggestion-endpoint-backend-app] ---

# --- 27B-decomposed from roadmap [2026-10-27]: Test `search_messages` conversation endpoint — `backend/app/routers/conversations.py:517`  (review + tweak) [feat:gitlark-20261027-test-search-messages-conversation-endpoi] ---

# --- 27B-decomposed from roadmap [2026-10-27]: Test `get_conversation_stats` endpoint — `backend/app/routers/conversations.py:570` is a p (review + tweak) [feat:gitlark-20261027-test-get-conversation-stats-endpoint-bac] ---

# --- 27B-decomposed from roadmap [2026-10-27]: Test `post_fleet_events` — `backend/app/routers/conversations.py:628` is a public function (review + tweak) [feat:gitlark-20261027-test-post-fleet-events-backend-app-route] ---

# --- 27B-decomposed from roadmap [2026-10-27]: Test conversation tag management endpoints — `backend/app/routers/conversations.py:290` (` (review + tweak) [feat:gitlark-20261027-test-conversation-tag-management-endpoin] ---

# --- 27B-decomposed from roadmap [2026-10-27]: Test `get_aggregate_analytics` endpoint — `backend/app/routers/analytics.py:27` is a publi (review + tweak) [feat:gitlark-20261027-test-get-aggregate-analytics-endpoint-ba] ---

# --- 27B-decomposed from roadmap [2026-10-27]: Test `queue_conversation_action` endpoint — `backend/app/routers/conversations.py:671` is  (review + tweak) [feat:gitlark-20261027-test-queue-conversation-action-endpoint-] ---

# --- 27B-decomposed from roadmap [2026-10-27]: Test `architecture_review` endpoint — `backend/app/routers/conversations.py:702` is a publ (review + tweak) [feat:gitlark-20261027-test-architecture-review-endpoint-backen] ---

# --- 27B-decomposed from roadmap [2026-10-27]: Test `get_workspace_health` endpoint — `backend/app/routers/analytics.py:67` is a public f (review + tweak) [feat:gitlark-20261027-test-get-workspace-health-endpoint-backe] ---

# --- 27B-decomposed from roadmap [2026-10-27]: Test `get_contributor_stats` endpoint — `backend/app/routers/analytics.py:80` is a public  (review + tweak) [feat:gitlark-20261027-test-get-contributor-stats-endpoint-back] ---

# --- 27B-decomposed from roadmap [2026-10-27]: Test `get_agent_type_stats` endpoint — `backend/app/routers/analytics.py:99` is a public f (review + tweak) [feat:gitlark-20261027-test-get-agent-type-stats-endpoint-backe] ---

# --- 27B-decomposed from roadmap [2026-10-27]: Test `get_usage_metrics` endpoint — `backend/app/routers/analytics.py:112` is a public fun (review + tweak) [feat:gitlark-20261027-test-get-usage-metrics-endpoint-backend-] ---

# --- 27B-decomposed from roadmap [2026-10-27]: Test `sync_analysis_to_memory` — `backend/app/routers/memory.py:61` is a public function w (review + tweak) [feat:gitlark-20261027-test-sync-analysis-to-memory-backend-app] ---

# --- 27B-decomposed from roadmap [2026-10-27]: Test `get_analysis_from_memory` — `backend/app/routers/memory.py:153` is a public function (review + tweak) [feat:gitlark-20261027-test-get-analysis-from-memory-backend-ap] ---

# --- 27B-decomposed from roadmap [2026-10-27]: Test `rate_insight` — `backend/app/routers/memory.py:196` is a public function with zero t (review + tweak) [feat:gitlark-20261027-test-rate-insight-backend-app-routers-me] ---

# --- 27B-decomposed from roadmap [2026-10-27]: Test `save_insight_to_memory` — `backend/app/routers/memory.py:236` is a public function w (review + tweak) [feat:gitlark-20261027-test-save-insight-to-memory-backend-app-] ---

# --- 27B-decomposed from roadmap [2026-10-28]: Require authentication on every /api/connectors route — `backend/app/routers/connectors.py (review + tweak) [feat:gitlark-20261028-require-authentication-on-every-api-conn] ---

# --- 27B-decomposed from roadmap [2026-10-28]: Validate task paths before dispatch writes them to the repo queue file — `backend/app/serv (review + tweak) [feat:gitlark-20261028-validate-task-paths-before-dispatch-writ] ---

# --- 27B-decomposed from roadmap [2026-10-28]: Flag the default token encryption key in production — `backend/app/core/config.py` default (review + tweak) [feat:gitlark-20261028-flag-the-default-token-encryption-key-in] ---

# --- 27B-decomposed from roadmap [2026-10-28]: Delimit repo text as untrusted data in the planner prompt — `backend/app/services/planner. (review + tweak) [feat:gitlark-20261028-delimit-repo-text-as-untrusted-data-in-t] ---

# --- 27B-decomposed from roadmap [2026-10-28]: Add pure stalled-task detection for dispatched plan tasks — nothing in `backend/app` detec (review + tweak) [feat:gitlark-20261028-add-pure-stalled-task-detection-for-disp] ---

# --- 27B-decomposed from roadmap [2026-10-28]: Add a pure per-day landing-rate aggregator — `backend/app/services/status_reader.py` class (review + tweak) [feat:gitlark-20261028-add-a-pure-per-day-landing-rate-aggregat] ---

# --- 27B-decomposed from roadmap [2026-10-28]: Report why a dispatched task reverted — `backend/app/services/status_reader.py`'s `TaskSta (review + tweak) [feat:gitlark-20261028-report-why-a-dispatched-task-reverted-ba] ---

# --- 27B-decomposed from roadmap [2026-10-28]: Read the planner model id from config instead of the module constant — `backend/app/servic (review + tweak) [feat:gitlark-20261028-read-the-planner-model-id-from-config-in] ---

# --- 27B-decomposed from roadmap [2026-10-28]: Retry a stale-sha 409 once when writing the queue file — `GitHubClient.create_or_update_fi (review + tweak) [feat:gitlark-20261028-retry-a-stale-sha-409-once-when-writing-] ---

# --- 27B-decomposed from roadmap [2026-10-28]: Mark access tokens with a type claim — `create_access_token` in `backend/app/core/security (review + tweak) [feat:gitlark-20261028-mark-access-tokens-with-a-type-claim-cre] ---

# --- 27B-decomposed from roadmap [2026-10-28]: Test `PlanningAgent.create_project_plan` — `backend/app/services/planning_agent.py:85` has (review + tweak) [feat:gitlark-20261028-test-planningagent-create-project-plan-b] ---

# --- 27B-decomposed from roadmap [2026-10-28]: Test `ConnectorRegistry.load_from_db` — `backend/app/services/connector_registry.py:150` h (review + tweak) [feat:gitlark-20261028-test-connectorregistry-load-from-db-back] ---

# --- 27B-decomposed from roadmap [2026-10-28]: Test `parse_cursor_output` — `backend/app/services/connector_registry.py:273` extracts cos (review + tweak) [feat:gitlark-20261028-test-parse-cursor-output-backend-app-ser] ---

# --- 27B-decomposed from roadmap [2026-10-29]: Test `GitHubClient.list_issues` and `get_issue` — `backend/app/services/github.py:369` and (review + tweak) [feat:gitlark-20261029-test-githubclient-list-issues-and-get-is] ---

# --- 27B-decomposed from roadmap [2026-10-29]: Test `LocalLLMClient.stream_generate` — `backend/app/services/local_llm_client.py:52` is t (review + tweak) [feat:gitlark-20261029-test-localllmclient-stream-generate-back] ---

# --- 27B-decomposed from roadmap [2026-10-29]: Add component tests for `NewWorkspacePage` — `web/src/pages/NewWorkspacePage.vue` (149 lin (review + tweak) [feat:gitlark-20261029-add-component-tests-for-newworkspacepage] ---

# --- 27B-decomposed from roadmap [2026-10-29]: Test `record_consent` endpoint — `backend/app/routers/auth.py:113` is a public function wi (review + tweak) [feat:gitlark-20261029-test-record-consent-endpoint-backend-app] ---

# --- 27B-decomposed from roadmap [2026-10-29]: Test `build_diff_pagination_meta` — `backend/app/routers/pull_requests.py:154` is a public (review + tweak) [feat:gitlark-20261029-test-build-diff-pagination-meta-backend-] ---

# --- 27B-decomposed from roadmap [2026-10-29]: Test `check_deploys_action` — `backend/app/routers/control_plane.py:137` is a public funct (review + tweak) [feat:gitlark-20261029-test-check-deploys-action-backend-app-ro] ---

# --- 27B-decomposed from roadmap [2026-10-29]: Test `initialize_memory_repo` — `backend/app/routers/memory.py:359` is a public function w (review + tweak) [feat:gitlark-20261029-test-initialize-memory-repo-backend-app-] ---

# --- 27B-decomposed from roadmap [2026-10-29]: Test `list_notifications` and `mark_notification_read` — `backend/app/routers/notification (review + tweak) [feat:gitlark-20261029-test-list-notifications-and-mark-notific] ---

# --- 27B-decomposed from roadmap [2026-10-30]: Test `get_analysis` endpoint — `backend/app/routers/repo_analysis.py:253` is a public func (review + tweak) [feat:gitlark-20261030-test-get-analysis-endpoint-backend-app-r] ---

# --- 27B-decomposed from roadmap [2026-10-30]: Test `save_insight` endpoint — `backend/app/routers/repo_analysis.py:412` is a public func (review + tweak) [feat:gitlark-20261030-test-save-insight-endpoint-backend-app-r] ---

# --- 27B-decomposed from roadmap [2026-10-30]: Test `get_members` — `backend/app/routers/collaborative_workspace.py:77` is a public funct (review + tweak) [feat:gitlark-20261030-test-get-members-backend-app-routers-col] ---

# --- 27B-decomposed from roadmap [2026-10-30]: Test `get_annotations` endpoint — `backend/app/routers/collaborative_workspace.py:389` is  (review + tweak) [feat:gitlark-20261030-test-get-annotations-endpoint-backend-ap] ---

# --- 27B-decomposed from roadmap [2026-10-30]: Test `get_review_session_stats` endpoint — `backend/app/routers/review_collab.py:168` is a (review + tweak) [feat:gitlark-20261030-test-get-review-session-stats-endpoint-b] ---

# --- 27B-decomposed from roadmap [2026-10-30]: Test `get_conversation_history` endpoint — `backend/app/routers/audit.py:54` is a public f (review + tweak) [feat:gitlark-20261030-test-get-conversation-history-endpoint-b] ---

# --- 27B-decomposed from roadmap [2026-10-30]: Test `get_manifest` endpoint — `backend/app/routers/pwa.py:45` is a public function with z (review + tweak) [feat:gitlark-20261030-test-get-manifest-endpoint-backend-app-r] ---

# --- 27B-decomposed from roadmap [2026-10-30]: Test `get_user_activity` — `backend/app/routers/audit.py:118` is a public function with ze (review + tweak) [feat:gitlark-20261030-test-get-user-activity-backend-app-route] ---

# --- 27B-decomposed from roadmap [2026-10-30]: Test `get_audit_report` — `backend/app/routers/audit.py:167` is a public function with zer (review + tweak) [feat:gitlark-20261030-test-get-audit-report-backend-app-router] ---

# --- 27B-decomposed from roadmap [2026-10-30]: Test `get_replay_timeline` — `backend/app/routers/audit.py:257` is a public function with  (review + tweak) [feat:gitlark-20261030-test-get-replay-timeline-backend-app-rou] ---

# --- 27B-decomposed from roadmap [2026-10-30]: Test `list_connector_runs` — `backend/app/routers/connectors.py:43` is a public function w (review + tweak) [feat:gitlark-20261030-test-list-connector-runs-backend-app-rou] ---

# --- 27B-decomposed from roadmap [2026-10-30]: Test `register_connector` — `backend/app/routers/connectors.py:57` is a public function wi (review + tweak) [feat:gitlark-20261030-test-register-connector-backend-app-rout] ---

# --- deterministic work supply 2026-10-30 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- 27B-decomposed from roadmap [2026-10-30]: Test `update_presence_status` endpoint — `backend/app/routers/realtime.py:188` is a public (review + tweak) [feat:gitlark-20261030-test-update-presence-status-endpoint-bac] ---

# --- 27B-decomposed from roadmap [2026-10-30]: Test `create_export` service — `backend/app/services/export.py:224` is a public function w (review + tweak) [feat:gitlark-20261030-test-create-export-service-backend-app-s] ---

# --- 27B-decomposed from roadmap [2026-10-30]: Test `search_conversations` service function — `backend/app/services/search.py:143` is a p (review + tweak) [feat:gitlark-20261030-test-search-conversations-service-functi] ---

# --- 27B-decomposed from roadmap [2026-10-30]: Test `get_connection_stats` endpoint — `backend/app/routers/realtime.py:215` is a public f (review + tweak) [feat:gitlark-20261030-test-get-connection-stats-endpoint-backe] ---

# --- 27B-decomposed from roadmap [2026-10-30]: Test `code_review_stream` — `backend/app/services/code_review_agent.py:264` is a public fu (review + tweak) [feat:gitlark-20261030-test-code-review-stream-backend-app-serv] ---

# --- 27B-decomposed from roadmap [2026-10-30]: Test `invoke_agent_via_connector` — `backend/app/services/ai_agent.py:343` is a public fun (review + tweak) [feat:gitlark-20261030-test-invoke-agent-via-connector-backend-] ---

# --- 27B-decomposed from roadmap [2026-10-30]: Test `remove_message_reaction` — `backend/app/services/reactions.py:136` is a public funct (review + tweak) [feat:gitlark-20261030-test-remove-message-reaction-backend-app] ---

# --- deterministic work supply 2026-10-30 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- deterministic work supply 2026-10-30 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- 27B-decomposed from roadmap [2026-10-30]: Return 404 when plan not found in overnight progress endpoint — `backend/app/routers/fleet (review + tweak) [feat:gitlark-20261030-return-404-when-plan-not-found-in-overni] ---

# --- deterministic work supply 2026-10-30 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- deterministic work supply 2026-10-31 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- 27B-decomposed from roadmap [2026-10-31]: Test `remove_tag_from_conversation` endpoint — `backend/app/routers/conversations.py:332`  (review + tweak) [feat:gitlark-20261031-test-remove-tag-from-conversation-endpoi] ---

# --- 27B-decomposed from roadmap [2026-10-31]: Test `create_checkout` endpoint — `backend/app/routers/billing.py:112` is a public functio (review + tweak) [feat:gitlark-20261031-test-create-checkout-endpoint-backend-ap] ---

# --- 27B-decomposed from roadmap [2026-10-31]: Check workspace ownership in create_workspace_conversation — `backend/app/routers/workspac (review + tweak) [feat:gitlark-20261031-check-workspace-ownership-in-create-work] ---

# --- 27B-decomposed from roadmap [2026-10-31]: Fix N+1 query in get_shared_snippets by batching snippet fetch — `backend/app/routers/coll (review + tweak) [feat:gitlark-20261031-fix-n-1-query-in-get-shared-snippets-by-] ---

# --- 27B-decomposed from roadmap [2026-11-01]: Add a pure in-process sliding-window rate limiter — `backend/app/core/config.py:155` defin (review + tweak) [feat:gitlark-20261101-add-a-pure-in-process-sliding-window-rat] ---

# --- 27B-decomposed from roadmap [2026-11-01]: Add a `rate_limit(max_requests, window_seconds, scope)` FastAPI dependency factory — build (review + tweak) [feat:gitlark-20261101-add-a-rate-limit-max-requests-window-sec] ---

# --- 27B-decomposed from roadmap [2026-11-01]: Enforce rate limits on the unauthenticated auth routes — `backend/app/routers/auth.py` exp (review + tweak) [feat:gitlark-20261101-enforce-rate-limits-on-the-unauthenticat] ---

# --- 27B-decomposed from roadmap [2026-11-01]: Rate-limit the GitHub webhook receiver and the plan dispatch route — `backend/app/routers/ (review + tweak) [feat:gitlark-20261101-rate-limit-the-github-webhook-receiver-a] ---

# --- 27B-decomposed from roadmap [2026-11-01]: Add a security-headers middleware — a grep for `nosniff`, `X-Frame-Options`, `Referrer-Pol (review + tweak) [feat:gitlark-20261101-add-a-security-headers-middleware-a-grep] ---

# --- 27B-decomposed from roadmap [2026-11-01]: Reject oversized request bodies with 413 — a grep for `content-length`/body size limits ac (review + tweak) [feat:gitlark-20261101-reject-oversized-request-bodies-with-413] ---

# --- 27B-decomposed from roadmap [2026-11-01]: Add an env-gated error-reporting hook for unhandled exceptions (Sentry-style, but no SDK a (review + tweak) [feat:gitlark-20261101-add-an-env-gated-error-reporting-hook-fo] ---

# --- 27B-decomposed from roadmap [2026-11-01]: Redact secrets from every log record — `backend/app/services/secret_redaction.py` has `red (review + tweak) [feat:gitlark-20261101-redact-secrets-from-every-log-record-bac] ---

# --- 27B-decomposed from roadmap [2026-11-01]: Add a `.pre-commit-config.yaml` with a gitleaks secret scan and a `.gitleaks.toml` allowli (review + tweak) [feat:gitlark-20261101-add-a-pre-commit-config-yaml-with-a-gitl] ---

# --- 27B-decomposed from roadmap [2026-11-01]: Add a first-run state composable for the web app — a grep of `web/src` for onboarding/welc (review + tweak) [feat:gitlark-20261101-add-a-first-run-state-composable-for-the] ---

# --- 27B-decomposed from roadmap [2026-11-01]: Add a first-run wizard page and route — depends on `web/src/composables/useFirstRun.ts` (c (review + tweak) [feat:gitlark-20261101-add-a-first-run-wizard-page-and-route-de] ---

# --- 27B-decomposed from roadmap [2026-11-01]: Show a clear message when the API answers 429 — `web/src/services/api.ts` has a response i (review + tweak) [feat:gitlark-20261101-show-a-clear-message-when-the-api-answer] ---

# --- 27B-decomposed from roadmap [2026-11-01]: Test `lifespan` lifecycle — `backend/app/main.py:43` defines the FastAPI lifespan context  (review + tweak) [feat:gitlark-20261101-test-lifespan-lifecycle-backend-app-main] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Test `get_review_history` — `backend/app/routers/review.py:277` is a public function with  (review + tweak) [feat:gitlark-20261102-test-get-review-history-backend-app-rout] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Test `disable_agent` endpoint — `backend/app/routers/ai_agents.py:323` is a public functio (review + tweak) [feat:gitlark-20261102-test-disable-agent-endpoint-backend-app-] ---

# --- deterministic work supply 2026-11-02 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- deterministic work supply 2026-11-02 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- 27B-decomposed from roadmap [2026-11-02]: Test `set_enabled` and `clear_reporters` — `backend/app/core/error_reporting.py:21` and `b (review + tweak) [feat:gitlark-20261102-test-set-enabled-and-clear-reporters-bac] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Batch the per-annotation author lookup in `get_annotations` — `backend/app/routers/collabo (review + tweak) [feat:gitlark-20261102-batch-the-per-annotation-author-lookup-i] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Batch the per-presence user lookup in `get_active_users` — `backend/app/routers/collaborat (review + tweak) [feat:gitlark-20261102-batch-the-per-presence-user-lookup-in-ge] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Bound the `limit` query param on the notification-events list — `backend/app/routers/notif (review + tweak) [feat:gitlark-20261102-bound-the-limit-query-param-on-the-notif] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Validate `EditMessageRequest.content` — `backend/app/schemas/__init__.py:208` is `content: (review + tweak) [feat:gitlark-20261102-validate-editmessagerequest-content-back] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Cap `SnippetCreate` field lengths to the DB column sizes — `backend/app/schemas/snippet.py (review + tweak) [feat:gitlark-20261102-cap-snippetcreate-field-lengths-to-the-d] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Bound `ConversationCreate.title` and the connector-credential create schema — `backend/app (review + tweak) [feat:gitlark-20261102-bound-conversationcreate-title-and-the-c] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Use the shared `webhook_signature.verify_signature` in the GitHub App webhook — `backend/a (review + tweak) [feat:gitlark-20261102-use-the-shared-webhook-signature-verify-] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Replace `print()` in the app lifespan with module logging — `backend/app/main.py:65-81` (` (review + tweak) [feat:gitlark-20261102-replace-print-in-the-app-lifespan-with-m] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Route the production config warnings through logging — `backend/app/core/config.py:192-193 (review + tweak) [feat:gitlark-20261102-route-the-production-config-warnings-thr] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Make the backend PWA manifest icon paths match the real files — `backend/app/routers/pwa.p (review + tweak) [feat:gitlark-20261102-make-the-backend-pwa-manifest-icon-paths] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Run the container as a non-root user and drop the stray `Dockerfile.bak` — repo-root `Dock (review + tweak) [feat:gitlark-20261102-run-the-container-as-a-non-root-user-and] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Add a pure GitHub rate-limit header parser — `backend/app/services/github.py` never reads  (review + tweak) [feat:gitlark-20261102-add-a-pure-github-rate-limit-header-pars] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Log a warning when the GitHub API quota is nearly spent — builds on `backend/app/services/ (review + tweak) [feat:gitlark-20261102-log-a-warning-when-the-github-api-quota-] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Return 400 for a malformed `Content-Length` instead of silently accepting it — the middlew (review + tweak) [feat:gitlark-20261102-return-400-for-a-malformed-content-lengt] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Register the environment-aware security-headers middleware instead of the legacy one — `ba (review + tweak) [feat:gitlark-20261102-register-the-environment-aware-security-] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Add a catch-all 404 route to the web router — `web/src/router.ts` lists 21 routes and no ` (review + tweak) [feat:gitlark-20261102-add-a-catch-all-404-route-to-the-web-rou] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Set `document.title` per route — `web/src/router.ts:159` `router.afterEach(...)` is an emp (review + tweak) [feat:gitlark-20261102-set-document-title-per-route-web-src-rou] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Add a safe post-login redirect helper — `web/src/router.ts:141-155` sends every unauthenti (review + tweak) [feat:gitlark-20261102-add-a-safe-post-login-redirect-helper-we] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Wire the post-login redirect into the auth guard and OAuth callback — depends on `web/src/ (review + tweak) [feat:gitlark-20261102-wire-the-post-login-redirect-into-the-au] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Stop logging the stored auth token in the auth store — `web/src/stores/auth.ts:66-90` (`in (review + tweak) [feat:gitlark-20261102-stop-logging-the-stored-auth-token-in-th] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Make concurrent 401s share one token refresh — `web/src/services/api.ts:45-60` response in (review + tweak) [feat:gitlark-20261102-make-concurrent-401s-share-one-token-ref] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Make notification items in `NotificationBell` keyboard-operable — `web/src/components/Noti (review + tweak) [feat:gitlark-20261102-make-notification-items-in-notificationb] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Give the unlabeled form inputs accessible names — `web/src/pages/SelectRepositoriesPage.vu (review + tweak) [feat:gitlark-20261102-give-the-unlabeled-form-inputs-accessibl] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Expose expanded state on the Pull Requests list toggles — `web/src/pages/PullRequestsPage. (review + tweak) [feat:gitlark-20261102-expose-expanded-state-on-the-pull-reques] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Make the Connector Runs error banner a proper alert — `web/src/pages/ConnectorRunsPage.vue (review + tweak) [feat:gitlark-20261102-make-the-connector-runs-error-banner-a-p] ---

# --- 27B-decomposed from roadmap [2026-11-04]: Test `redact` function — `backend/app/core/error_reporting.py:28` is a public function wit (review + tweak) [feat:gitlark-20261104-test-redact-function-backend-app-core-er] ---

# --- 27B-decomposed from roadmap [2026-11-05]: Test `status_action` endpoint — `backend/app/routers/control_plane.py:119` is a public fun (review + tweak) [feat:gitlark-20261105-test-status-action-endpoint-backend-app-] ---

# --- 27B-decomposed from roadmap [2026-11-06]: Test `promote_action` endpoint — `backend/app/routers/control_plane.py:185` is a public fu (review + tweak) [feat:gitlark-20261106-test-promote-action-endpoint-backend-app] ---

# --- 27B-decomposed from roadmap [2026-11-06]: Test `list_notifications` endpoint — `backend/app/routers/notifications.py:23` is a public (review + tweak) [feat:gitlark-20261106-test-list-notifications-endpoint-backend] ---

# --- 27B-decomposed from roadmap [2026-11-06]: Test `get_workspace_stats` — `backend/app/routers/collaborative_workspace.py:663` is a pub (review + tweak) [feat:gitlark-20261106-test-get-workspace-stats-backend-app-rou] ---

# --- 27B-decomposed from roadmap [2026-11-06]: Validate the plan-task PATCH body — `backend/app/routers/plans.py` defines its own `PlanTa (review + tweak) [feat:gitlark-20261106-validate-the-plan-task-patch-body-backen] ---

# --- 27B-decomposed from roadmap [2026-11-06]: Report tasks the dispatcher rejected in the dispatch response — `DispatcherService.dispatc (review + tweak) [feat:gitlark-20261106-report-tasks-the-dispatcher-rejected-in-] ---

# --- 27B-decomposed from roadmap [2026-11-06]: Do not mark a plan `dispatched` when the control-plane dispatch failed to write — `backend (review + tweak) [feat:gitlark-20261106-do-not-mark-a-plan-dispatched-when-the-c] ---

# --- 27B-decomposed from roadmap [2026-11-06]: Read the control-plane status from the configured branch — `backend/app/services/control_p (review + tweak) [feat:gitlark-20261106-read-the-control-plane-status-from-the-c] ---

# --- 27B-decomposed from roadmap [2026-11-06]: Stop `route_task` sending ordinary engineering work to `human` by substring — `backend/app (review + tweak) [feat:gitlark-20261106-stop-route-task-sending-ordinary-enginee] ---

# --- 27B-decomposed from roadmap [2026-11-06]: Make `estimate_tier` match word starts, not substrings — `backend/app/services/planner_tie (review + tweak) [feat:gitlark-20261106-make-estimate-tier-match-word-starts-not] ---

# --- 27B-decomposed from roadmap [2026-11-06]: Bound the ingest payload and match repos case-insensitively — `backend/app/routers/notific (review + tweak) [feat:gitlark-20261106-bound-the-ingest-payload-and-match-repos] ---

# --- 27B-decomposed from roadmap [2026-11-06]: Constrain the pull-request router's free-form params — `backend/app/routers/pull_requests. (review + tweak) [feat:gitlark-20261106-constrain-the-pull-request-router-s-free] ---

# --- 27B-decomposed from roadmap [2026-11-06]: Bound the plan-generation goal — `backend/app/routers/plans.py` `GeneratePlanRequest.goal` (review + tweak) [feat:gitlark-20261106-bound-the-plan-generation-goal-backend-a] ---

# --- 27B-decomposed from roadmap [2026-11-06]: Order and paginate `GET /plans` — `list_plans` in `backend/app/routers/plans.py` selects e (review + tweak) [feat:gitlark-20261106-order-and-paginate-get-plans-list-plans-] ---

# --- 27B-decomposed from roadmap [2026-11-06]: Add a pure `derive_plan_status` — nothing in `backend/app` ever moves a plan past `dispatc (review + tweak) [feat:gitlark-20261106-add-a-pure-derive-plan-status-nothing-in] ---

# --- 27B-decomposed from roadmap [2026-11-06]: Persist the derived plan status when build status is read — builds on `derive_plan_status` (review + tweak) [feat:gitlark-20261106-persist-the-derived-plan-status-when-bui] ---

# --- 27B-decomposed from roadmap [2026-11-06]: Make the fleet-status card actually show its loading state — `web/src/components/FleetStat (review + tweak) [feat:gitlark-20261106-make-the-fleet-status-card-actually-show] ---

# --- 27B-decomposed from roadmap [2026-11-06]: Show why a task reverted on the plan page — the status endpoint already returns `failure_r (review + tweak) [feat:gitlark-20261106-show-why-a-task-reverted-on-the-plan-pag] ---

# --- 27B-decomposed from roadmap [2026-11-06]: Block saving a blank task edit on the plan page — `handleSaveEdit` in `web/src/pages/PlanP (review + tweak) [feat:gitlark-20261106-block-saving-a-blank-task-edit-on-the-pl] ---

# --- 27B-decomposed from roadmap [2026-11-06]: Delete the stale `FirstRunPage.tsx` duplicate — `web/src/pages/FirstRunPage.tsx` (a 52-lin (review + tweak) [feat:gitlark-20261106-delete-the-stale-firstrunpage-tsx-duplic] ---

# --- 27B-decomposed from roadmap [2026-11-06]: Detect a reverted task from the commit SUBJECT only, and match configured keywords case-in (review + tweak) [feat:gitlark-20261106-detect-a-reverted-task-from-the-commit-s] ---

# --- 27B-decomposed from roadmap [2026-11-06]: Stop a non-numeric rate-limit header from crashing every GitHub call - `parse_rate_limit`  (review + tweak) [feat:gitlark-20261106-stop-a-non-numeric-rate-limit-header-fro] ---

# --- 27B-decomposed from roadmap [2026-11-06]: Evict expired keys from the live rate limiter so spoofed client IPs cannot grow memory wit (review + tweak) [feat:gitlark-20261106-evict-expired-keys-from-the-live-rate-li] ---

# --- 27B-decomposed from roadmap [2026-11-09]: Make `classify_intent` match keywords at a word start, not as raw substrings - `backend/ap (review + tweak) [feat:gitlark-20261109-make-classify-intent-match-keywords-at-a] ---

# --- 27B-decomposed from roadmap [2026-11-09]: Redact lowercase bearer tokens and Stripe/Slack secrets in `redact_secrets` - `backend/app (review + tweak) [feat:gitlark-20261109-redact-lowercase-bearer-tokens-and-strip] ---

# --- 27B-decomposed from roadmap [2026-11-09]: Turn malformed LLM plan JSON into a clear `ValueError` instead of a raw `KeyError` - `Plan (review + tweak) [feat:gitlark-20261109-turn-malformed-llm-plan-json-into-a-clea] ---
- [ ] [T1] backend/tests/test_planner_parse_malformed.py — Create a new test file containing tests for `_parse_response` that verify `ValueError` is raised with correct messages for non-dict data, non-list tasks, and missing/invalid task fields (path, spec, verify). VERIFY: `cd backend && python3 -m pytest tests/test_planner_parse_malformed.py::test_parse_response_non_dict_data tests/test_planner_parse_malformed.py::test_parse_response_tasks_not_list tests/test_planner_parse_malformed.py::test_parse_response_missing_verify -q`. (cat:test; multifile:no) [feat:gitlark-20261109-turn-malformed-llm-plan-json-into-a-clea]
- [ ] [T1] backend/tests/test_planner_parse_malformed.py — Add a test to the existing file that verifies `generate_plan` raises `ValueError("Planner response had no content")` when the mocked API response has an empty content list. VERIFY: `cd backend && python3 -m pytest tests/test_planner_parse_malformed.py::test_generate_plan_empty_content -q`. (cat:test; multifile:no) [feat:gitlark-20261109-turn-malformed-llm-plan-json-into-a-clea]
- [ ] [T1] backend/tests/test_planner_parse_malformed.py — Add a test to the existing file that verifies a valid JSON payload with correct task structures still returns a `Plan` object successfully through `_parse_response`. VERIFY: `cd backend && python3 -m pytest tests/test_planner_parse_malformed.py::test_parse_response_valid_payload -q`. (cat:test; multifile:no) [feat:gitlark-20261109-turn-malformed-llm-plan-json-into-a-clea]

# --- 27B-decomposed from roadmap [2026-11-09]: Make `format_repo_context` tolerate non-string values and strip every line separator - `_s (review + tweak) [feat:gitlark-20261109-make-format-repo-context-tolerate-non-st] ---
- [ ] [T1] backend/app/services/planner.py — Update `_sanitize_context_value` to coerce `None` to `""`, convert other types to `str`, and remove `\r`, `\n`, `\u2028`, `\u2029`, `\x0b`, `\x0c`, `\x85`, and `<repo_context>` tags before returning. VERIFY: `cd backend && python3 -c "from app.services.planner import _sanitize_context_value; assert _sanitize_context_value(None) == ''; assert _sanitize_context_value(123) == '123'; assert _sanitize_context_value('a\rb\u2028c') == 'ac'"`. (cat:python; multifile:no) [feat:gitlark-20261109-make-format-repo-context-tolerate-non-st]
- [ ] [T2] backend/app/services/planner.py — Update `format_repo_context` to skip `primary_language` if `None` or blank, and filter out `None` entries from `frameworks`, `dependencies`, and `files` lists before processing. VERIFY: `cd backend && python3 -c "from app.services.planner import format_repo_context; assert 'Primary Language' not in format_repo_context({'primary_language': None}); assert 'fastapi' in format_repo_context({'frameworks': ['fastapi', None]})"`. (cat:python; multifile:no) [feat:gitlark-20261109-make-format-repo-context-tolerate-non-st]
- [ ] [T3] backend/tests/test_planner_context_sanitize.py — Add test cases verifying that `format_repo_context` handles `{"primary_language": None}`, `{"frameworks": ["fastapi", 3]}`, and `["a.py", None]` without raising `AttributeError`. VERIFY: `cd backend && python3 -m pytest tests/test_planner_context_sanitize.py::test_format_repo_context_handles_none_and_mixed_types -q`. (cat:test; multifile:no) [feat:gitlark-20261109-make-format-repo-context-tolerate-non-st]
- [ ] [T4] backend/tests/test_planner_context_sanitize.py — Add test case verifying that `format_repo_context({"files": ["a\rb.py", "c\u2028- evil.py"]})` output contains no `\r`, `\u2028`, or other line separators. VERIFY: `cd backend && python3 -m pytest tests/test_planner_context_sanitize.py::test_format_repo_context_strips_line_separators -q`. (cat:test; multifile:no) [feat:gitlark-20261109-make-format-repo-context-tolerate-non-st]
- [ ] [T5] backend/tests/test_planner_context_sanitize.py — Add test case asserting that `format_repo_context` with clean string inputs produces identical output to the pre-fix behavior (literal string comparison). VERIFY: `cd backend && python3 -m pytest tests/test_planner_context_sanitize.py::test_format_repo_context_clean_input_unchanged -q`. (cat:test; multifile:no) [feat:gitlark-20261109-make-format-repo-context-tolerate-non-st]

# --- 27B-decomposed from roadmap [2026-11-09]: Accept only well-formed client request ids in `RequestIdMiddleware` - `backend/app/core/re (review + tweak) [feat:gitlark-20261109-accept-only-well-formed-client-request-i] ---
- [ ] [T1] backend/app/core/request_id_middleware.py — Add `_VALID_REQUEST_ID = re.compile(r"^[A-Za-z0-9._:-]{1,128}$")` and import `re` and `uuid`. VERIFY: `cd backend && python3 -c "from app.core.request_id_middleware import _VALID_REQUEST_ID; assert _VALID_REQUEST_ID.fullmatch('abc-123_X.9'); assert not _VALID_REQUEST_ID.fullmatch('bad id')"`. (cat:python; multifile:no) [feat:gitlark-20261109-accept-only-well-formed-client-request-i]
- [ ] [T1] backend/app/core/request_id_middleware.py — Modify `dispatch` to check `_VALID_REQUEST_ID.fullmatch(incoming_id)`; if it fails or header is missing, set `request_id = str(uuid.uuid4())`, else use `incoming_id`. VERIFY: `cd backend && python3 -c "from app.core.request_id_middleware import RequestIdMiddleware; print('ok')"`. (cat:python; multifile:no) [feat:gitlark-20261109-accept-only-well-formed-client-request-i]
- [ ] [T2] backend/tests/test_request_id_untrusted_header.py — Create test file with a minimal FastAPI app using `RequestIdMiddleware` and a route returning `request_id_ctx.get()`. VERIFY: `cd backend && python3 -m pytest tests/test_request_id_untrusted_header.py --collect-only -q`. (cat:test; multifile:no) [feat:gitlark-20261109-accept-only-well-formed-client-request-i]
- [ ] [T2] backend/tests/test_request_id_untrusted_header.py — Add test case verifying that a valid ID `abc-123_X.9` is echoed unchanged in the response header and route body. VERIFY: `cd backend && python3 -m pytest tests/test_request_id_untrusted_header.py::test_valid_id_echoed -q`. (cat:test; multifile:no) [feat:gitlark-20261109-accept-only-well-formed-client-request-i]
- [ ] [T2] backend/tests/test_request_id_untrusted_header.py — Add test case verifying that a 129-character ID is replaced by a fresh UUID (36 chars, 4 hyphens) in both response header and route body. VERIFY: `cd backend && python3 -m pytest tests/test_request_id_untrusted_header.py::test_long_id_replaced -q`. (cat:test; multifile:no) [feat:gitlark-20261109-accept-only-well-formed-client-request-i]
- [ ] [T2] backend/tests/test_request_id_untrusted_header.py — Add test case verifying that IDs with invalid characters (`bad id`, `a"b`, `x=y`) are replaced by a fresh UUID in both response header and route body. VERIFY: `cd backend && python3 -m pytest tests/test_request_id_untrusted_header.py::test_invalid_chars_replaced -q`. (cat:test; multifile:no) [feat:gitlark-20261109-accept-only-well-formed-client-request-i]
- [ ] [T2] backend/tests/test_request_id_untrusted_header.py — Add test case verifying that when no `X-Request-ID` header is provided, a fresh UUID is generated and used in both response header and route body. VERIFY: `cd backend && python3 -m pytest tests/test_request_id_untrusted_header.py::test_no_header_generates_uuid -q`. (cat:test; multifile:no) [feat:gitlark-20261109-accept-only-well-formed-client-request-i]

# --- 27B-decomposed from roadmap [2026-11-09]: Price dated Claude model ids with their base model, not as haiku - `QuotaService.estimate_ (review + tweak) [feat:gitlark-20261109-price-dated-claude-model-ids-with-their-] ---
- [ ] [T1] backend/app/services/quota.py — Add `import re` at the top of the file if not already present. VERIFY: `cd backend && python3 -c "import app.services.quota"`. (cat:python; multifile:no) [feat:gitlark-20261109-price-dated-claude-model-ids-with-their-]
- [ ] [T2] backend/app/services/quota.py — In `QuotaService.estimate_cost`, before the alias lookup, normalize the model ID by stripping trailing 8-digit dates using `re.sub(r"-\d{8}$", "", model)` and use this normalized ID for both `MODEL_ALIASES` and `PRICING` lookups, while preserving the original ID for any fallback warnings. VERIFY: `cd backend && python3 -c "from app.services.quota import QuotaService; q=QuotaService(); assert q.estimate_cost('claude-sonnet-5-20261001', 10**6, 10**6) == q.estimate_cost('claude-sonnet-5', 10**6, 10**6)"`. (cat:python; multifile:no) [feat:gitlark-20261109-price-dated-claude-model-ids-with-their-]
- [ ] [T3] backend/tests/test_quota_dated_model_pricing.py — Create a new test file containing tests that verify `estimate_cost` returns identical costs for dated and undated model IDs (e.g., `claude-sonnet-5-20261001` vs `claude-sonnet-5`, `claude-opus-4-8-20261101` vs `claude-opus-4-8`, `claude-haiku-4-5-20261101` vs `claude-haiku-4-5`). VERIFY: `cd backend && python3 -m pytest tests/test_quota_dated_model_pricing.py -q`. (cat:test; multifile:no) [feat:gitlark-20261109-price-dated-claude-model-ids-with-their-]
- [ ] [T4] backend/tests/test_quota_dated_model_pricing.py — Add a test case to the new file asserting that legacy dated entries with specific pricing rows (e.g., `claude-sonnet-4-20250514`) still match their exact PRICING row (18.0 for 1M/1M) rather than falling back to stripped base model pricing if they differ, or confirming the stripping logic handles it correctly per the "exact match wins" requirement. VERIFY: `cd backend && python3 -m pytest tests/test_quota_dated_model_pricing.py::test_legacy_dated_entry_exact_match -q`. (cat:test; multifile:no) [feat:gitlark-20261109-price-dated-claude-model-ids-with-their-]
- [ ] [T5] backend/tests/test_quota_dated_model_pricing.py — Add a test case to the new file asserting that an unknown model ID (e.g., `unknown-model`) still falls back to haiku pricing. VERIFY: `cd backend && python3 -m pytest tests/test_quota_dated_model_pricing.py::test_unknown_model_fallback -q`. (cat:test; multifile:no) [feat:gitlark-20261109-price-dated-claude-model-ids-with-their-]

# --- 27B-decomposed from roadmap [2026-11-09]: Make the GitLark logo in the dashboard nav keyboard-operable - `web/src/pages/DashboardPag (review + tweak) [feat:gitlark-20261109-make-the-gitlark-logo-in-the-dashboard-n] ---
- [ ] [T2] web/src/pages/DashboardPage.vue — Ensure `goToDashboard` function remains defined and used by other elements in the file. VERIFY: `cd web && grep -q 'const goToDashboard' src/pages/DashboardPage.vue && grep -c 'goToDashboard' src/pages/DashboardPage.vue | awk '{exit !($1 >= 4)}'`. (cat:vue; multifile:no) [feat:gitlark-20261109-make-the-gitlark-logo-in-the-dashboard-n]
- [ ] [T2] web/src/pages/DashboardPage.vue — Add `hover:text-indigo-700` class to the `<router-link>` for visual feedback on hover. VERIFY: `cd web && grep -q 'hover:text-indigo-700' src/pages/DashboardPage.vue`. (cat:vue; multifile:no) [feat:gitlark-20261109-make-the-gitlark-logo-in-the-dashboard-n]
- [ ] [T3] web/src/pages/DashboardPage.vue — Replace `<h1 class="text-2xl font-bold text-indigo-600 cursor-pointer" @click="goToDashboard">GitLark</h1>` with `<h1 class="text-2xl font-bold"><router-link to="/dashboard" class="text-indigo-600 hover:text-indigo-700">GitLark</router-link></h1>`. VERIFY: `cd web && grep -q '<router-link to="/dashboard"' src/pages/DashboardPage.vue && ! grep -q 'cursor-pointer' src/pages/DashboardPage.vue && ! grep -q '@click="goToDashboard"' src/pages/DashboardPage.vue`. (cat:vue; multifile:no) [feat:gitlark-20261109-make-the-gitlark-logo-in-the-dashboard-n]
- [ ] [T2] web/src/pages/DashboardPage.vue — Remove `cursor-pointer` class from the `<h1>` element to avoid misleading cursor behavior on non-interactive heading text. VERIFY: `cd web && ! grep -q 'cursor-pointer' src/pages/DashboardPage.vue`. (cat:vue; multifile:no) [feat:gitlark-20261109-make-the-gitlark-logo-in-the-dashboard-n]
- [ ] [T2] web/src/pages/DashboardPage.vue — Ensure the `<router-link>` has `to="/dashboard"` attribute for correct navigation target. VERIFY: `cd web && grep -q 'to="/dashboard"' src/pages/DashboardPage.vue`. (cat:vue; multifile:no) [feat:gitlark-20261109-make-the-gitlark-logo-in-the-dashboard-n]
- [ ] [T1] web/src/pages/__tests__/DashboardPage.logoLink.test.ts — Create test file that reads `../DashboardPage.vue` and asserts the first `<h1` block contains `<router-link to="/dashboard"`, does not contain `@click` or `cursor-pointer`, and that `goToDashboard` is still defined in the file. VERIFY: `cd web && npx vitest run src/pages/__tests__/DashboardPage.logoLink.test.ts`. (cat:test; multifile:no) [feat:gitlark-20261109-make-the-gitlark-logo-in-the-dashboard-n]
- [ ] [T2] web/src/pages/__tests__/DashboardPage.logoLink.test.ts — Add assertion that `goToDashboard` is still defined in the source to prevent accidental removal. VERIFY: `cd web && npx vitest run src/pages/__tests__/DashboardPage.logoLink.test.ts`. (cat:test; multifile:no) [feat:gitlark-20261109-make-the-gitlark-logo-in-the-dashboard-n]
- [ ] [T2] web/src/pages/__tests__/DashboardPage.logoLink.test.ts — Add assertion that the `<h1>` element does not contain `cursor-pointer` class. VERIFY: `cd web && npx vitest run src/pages/__tests__/DashboardPage.logoLink.test.ts`. (cat:test; multifile:no) [feat:gitlark-20261109-make-the-gitlark-logo-in-the-dashboard-n]
- [ ] [T2] web/src/pages/__tests__/DashboardPage.logoLink.test.ts — Add assertion that the `<router-link>` contains `hover:text-indigo-700` class. VERIFY: `cd web && npx vitest run src/pages/__tests__/DashboardPage.logoLink.test.ts`. (cat:test; multifile:no) [feat:gitlark-20261109-make-the-gitlark-logo-in-the-dashboard-n]
- [ ] [T2] web/src/pages/__tests__/DashboardPage.logoLink.test.ts — Add assertion that the `<router-link>` has `to="/dashboard"` attribute. VERIFY: `cd web && npx vitest run src/pages/__tests__/DashboardPage.logoLink.test.ts`. (cat:test; multifile:no) [feat:gitlark-20261109-make-the-gitlark-logo-in-the-dashboard-n]

# --- 27B-decomposed from roadmap [2026-11-09]: Give the usage-period select an accessible name and drop its invalid `type` attribute - `w (review + tweak) [feat:gitlark-20261109-give-the-usage-period-select-an-accessib] ---
- [ ] [T2] web/src/components/__tests__/UsageInsights.a11y.test.ts — Create test file that mounts `UsageInsights` with `usage` and `trends` props, asserting all `<select>` elements have non-empty `aria-label`, no `<select>` has a `type` attribute, and the period select options are `7d`, `30d`, `90d`. VERIFY: `cd web && npx vitest run src/components/__tests__/UsageInsights.a11y.test.ts` (cat:test; multifile:no) [feat:gitlark-20261109-give-the-usage-period-select-an-accessib]
- [ ] [T1] web/src/components/UsageInsights.vue — Remove `type="button"` from the period `<select>` and add `aria-label="Usage period"` to it. VERIFY: `grep -q 'aria-label="Usage period"' web/src/components/UsageInsights.vue && ! grep -q 'type="button"' web/src/components/UsageInsights.vue` (cat:vue; multifile:no) [feat:gitlark-20261109-give-the-usage-period-select-an-accessib]
- [ ] [T1] web/src/components/UsageInsights.vue — Remove `type="button"` from the sibling trend metric `<select>` while keeping its existing `aria-label`. VERIFY: `grep -q 'aria-label="Trend metric"' web/src/components/UsageInsights.vue && ! grep -q 'type="button"' web/src/components/UsageInsights.vue` (cat:vue; multifile:no) [feat:gitlark-20261109-give-the-usage-period-select-an-accessib]

# --- 27B-decomposed from roadmap [2026-11-09]: Label the conversation search input and its two filter selects - `web/src/components/Conve (review + tweak) [feat:gitlark-20261109-label-the-conversation-search-input-and-] ---
- [ ] [T1] web/src/components/__tests__/ConversationSearch.labels.test.ts — Create test file that mounts `ConversationSearch` and asserts the text input has a non-empty `aria-label`. VERIFY: `cd web && npx vitest run src/components/__tests__/ConversationSearch.labels.test.ts` (cat:test; multifile:no) [feat:gitlark-20261109-label-the-conversation-search-input-and-]
- [ ] [T3] web/src/components/ConversationSearch.vue — Add `aria-label="Search conversations by text"` to the main search `<input>` element. VERIFY: `cd web && npx vitest run src/components/__tests__/ConversationSearch.labels.test.ts` (cat:vue; multifile:no) [feat:gitlark-20261109-label-the-conversation-search-input-and-]
- [ ] [T3] web/src/components/ConversationSearch.vue — Add `id="search-agent-type"` to the first filter `<select>` and `for="search-agent-type"` to its corresponding `<label>`. VERIFY: `cd web && npx vitest run src/components/__tests__/ConversationSearch.labels.test.ts` (cat:vue; multifile:no) [feat:gitlark-20261109-label-the-conversation-search-input-and-]
- [ ] [T3] web/src/components/ConversationSearch.vue — Add `id="search-days"` to the second filter `<select>` and `for="search-days"` to its corresponding `<label>`. VERIFY: `cd web && npx vitest run src/components/__tests__/ConversationSearch.labels.test.ts` (cat:vue; multifile:no) [feat:gitlark-20261109-label-the-conversation-search-input-and-]
- [ ] [T1] web/src/components/__tests__/ConversationSearch.labels.test.ts — Add assertions that for each select, a `label[for=<select id>]` exists and the select has that specific id. VERIFY: `cd web && npx vitest run src/components/__tests__/ConversationSearch.labels.test.ts` (cat:test; multifile:no) [feat:gitlark-20261109-label-the-conversation-search-input-and-]
- [ ] [T1] web/src/components/__tests__/ConversationSearch.labels.test.ts — Add assertion that all assigned ids (`search-agent-type`, `search-days`) are unique within the component. VERIFY: `cd web && npx vitest run src/components/__tests__/ConversationSearch.labels.test.ts` (cat:test; multifile:no) [feat:gitlark-20261109-label-the-conversation-search-input-and-]
- [ ] [T5] web/src/components/__tests__/ConversationSearch.labels.test.ts — Run full verification suite including existing tests to ensure no regressions. VERIFY: `cd web && npx vitest run src/components/__tests__/ConversationSearch.labels.test.ts src/components/__tests__/ConversationSearch.test.ts` (cat:test; multifile:no) [feat:gitlark-20261109-label-the-conversation-search-input-and-]

# --- 27B-decomposed from roadmap [2026-11-09]: Stop the workspace store logging API payloads to the browser console - `web/src/stores/wor (review + tweak) [feat:gitlark-20261109-stop-the-workspace-store-logging-api-pay] ---
- [ ] [T4] web/src/stores/workspace.ts — Verify no `console.log` calls remain in the file while ensuring `console.error` calls in catch blocks are preserved. VERIFY: `cd web && grep -n "console.log" src/stores/workspace.ts | wc -l` returns 0 and `cd web && npx vitest run src/stores/__tests__/workspace.nolog.test.ts src/stores/__tests__/workspace.test.ts`. (cat:typescript; multifile:no) [feat:gitlark-20261109-stop-the-workspace-store-logging-api-pay]
- [ ] [T3] web/src/stores/workspace.ts — Delete the `console.log` call at line ~51 that logs `'Workspaces loaded:', workspaces.value`. VERIFY: `cd web && npx vitest run src/stores/__tests__/workspace.nolog.test.ts`. (cat:typescript; multifile:no) [feat:gitlark-20261109-stop-the-workspace-store-logging-api-pay]
- [ ] [T3] web/src/stores/workspace.ts — Delete the `console.log` call at line ~56 that logs workspace data. VERIFY: `cd web && npx vitest run src/stores/__tests__/workspace.nolog.test.ts`. (cat:typescript; multifile:no) [feat:gitlark-20261109-stop-the-workspace-store-logging-api-pay]
- [ ] [T3] web/src/stores/workspace.ts — Delete the `console.log` call at line ~94 that logs workspace fetch response. VERIFY: `cd web && npx vitest run src/stores/__tests__/workspace.nolog.test.ts`. (cat:typescript; multifile:no) [feat:gitlark-20261109-stop-the-workspace-store-logging-api-pay]
- [ ] [T3] web/src/stores/workspace.ts — Delete the `console.log` call at line ~98 that logs workspace details. VERIFY: `cd web && npx vitest run src/stores/__tests__/workspace.nolog.test.ts`. (cat:typescript; multifile:no) [feat:gitlark-20261109-stop-the-workspace-store-logging-api-pay]
- [ ] [T3] web/src/stores/workspace.ts — Delete the `console.log` call at line ~100 that logs workspace data. VERIFY: `cd web && npx vitest run src/stores/__tests__/workspace.nolog.test.ts`. (cat:typescript; multifile:no) [feat:gitlark-20261109-stop-the-workspace-store-logging-api-pay]
- [ ] [T1] web/src/stores/__tests__/workspace.nolog.test.ts — Add new test file that mocks `@/services/api`, spies on `console.log`, calls `fetchWorkspaces()` and `fetchWorkspace('id')`, asserts `console.log` is never called, and verifies store state is populated. VERIFY: `cd web && npx vitest run src/stores/__tests__/workspace.nolog.test.ts`. (cat:test; multifile:no) [feat:gitlark-20261109-stop-the-workspace-store-logging-api-pay]

# --- 27B-decomposed from roadmap [2026-11-09]: Fall back to the caller message when an API error carries an empty validation array - `get (review + tweak) [feat:gitlark-20261109-fall-back-to-the-caller-message-when-an-] ---
- [ ] [T1] web/src/utils/apiError.ts — Modify `getErrorMessage` to filter array `detail` items for non-empty `msg || message`, join valid ones with '. ', and return `error.message || fallback` if the joined string is empty. VERIFY: `cd web && npx vitest run src/utils/__tests__/apiError.emptyDetail.test.ts`. (cat:typescript; multifile:no) [feat:gitlark-20261109-fall-back-to-the-caller-message-when-an-]
- [ ] [T2] web/src/utils/__tests__/apiError.emptyDetail.test.ts — Add test case asserting `getErrorMessage` returns `'Network Error'` when `detail` is `[]` and `error.message` is `'Network Error'`. VERIFY: `cd web && npx vitest run src/utils/__tests__/apiError.emptyDetail.test.ts -t "returns 'Network Error'"`. (cat:test; multifile:no) [feat:gitlark-20261109-fall-back-to-the-caller-message-when-an-]
- [ ] [T2] web/src/utils/__tests__/apiError.emptyDetail.test.ts — Add test case asserting `getErrorMessage` returns the supplied fallback when `detail` is `[]` and `error.message` is undefined. VERIFY: `cd web && npx vitest run src/utils/__tests__/apiError.emptyDetail.test.ts -t "returns the supplied fallback"`. (cat:test; multifile:no) [feat:gitlark-20261109-fall-back-to-the-caller-message-when-an-]
- [ ] [T2] web/src/utils/__tests__/apiError.emptyDetail.test.ts — Add test case asserting `getErrorMessage` returns the fallback when `detail` contains items with only blank `msg`/`message` fields. VERIFY: `cd web && npx vitest run src/utils/__tests__/apiError.emptyDetail.test.ts -t "returns the fallback"`. (cat:test; multifile:no) [feat:gitlark-20261109-fall-back-to-the-caller-message-when-an-]
- [ ] [T2] web/src/utils/__tests__/apiError.emptyDetail.test.ts — Add test case asserting `getErrorMessage` returns `'Field A is required. Field B is invalid'` for a valid two-item array to ensure existing behavior is preserved. VERIFY: `cd web && npx vitest run src/utils/__tests__/apiError.emptyDetail.test.ts -t "returns 'Field A is required. Field B is invalid'"`. (cat:test; multifile:no) [feat:gitlark-20261109-fall-back-to-the-caller-message-when-an-]
- [ ] [T2] web/src/utils/__tests__/apiError.emptyDetail.test.ts — Add test case asserting `getErrorMessage` returns `'A'` for a mixed array containing one valid and one blank item. VERIFY: `cd web && npx vitest run src/utils/__tests__/apiError.emptyDetail.test.ts -t "returns 'A'"`. (cat:test; multifile:no) [feat:gitlark-20261109-fall-back-to-the-caller-message-when-an-]

# --- 27B-decomposed from roadmap [2026-11-09]: Number PR inline comments from the hunk header, not from a running patch-line counter - `_ (review + tweak) [feat:gitlark-20261109-number-pr-inline-comments-from-the-hunk-] ---
- [ ] [T1] backend/app/routers/pull_requests.py — Add `import re` at the top of the file if not already present to support regex parsing in `_build_inline_comments`. VERIFY: `cd backend && python3 -c "from app.routers.pull_requests import _build_inline_comments; print('OK')"` (cat:python; multifile:no) [feat:gitlark-20261109-number-pr-inline-comments-from-the-hunk-]
- [ ] [T2] backend/app/routers/pull_requests.py — Modify `_build_inline_comments` to detect lines starting with `@@`, parse the new-file start line using `re.match(r"@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@", line)`, set `line_number = int(m.group(1)) - 1` for headers, and skip incrementing on header lines while preserving existing logic for non-header lines. VERIFY: `cd backend && python3 -c "from app.routers.pull_requests import _build_inline_comments; r=_build_inline_comments('a.py', '@@ -10,2 +10,3 @@\n ctx\n+new\n ctx'); assert r[0]['line']==11, r; print('OK')"` (cat:python; multifile:no) [feat:gitlark-20261109-number-pr-inline-comments-from-the-hunk-]
- [ ] [T3] backend/tests/test_pull_requests_inline_line_numbers.py — Create a new test file containing a test case that verifies `_build_inline_comments` returns `line: 11` for the patch `"@@ -10,2 +10,3 @@\n ctx\n+new\n ctx"`. VERIFY: `cd backend && python3 -m pytest tests/test_pull_requests_inline_line_numbers.py::test_single_hunk_line_number -q` (cat:test; multifile:no) [feat:gitlark-20261109-number-pr-inline-comments-from-the-hunk-]
- [ ] [T4] backend/tests/test_pull_requests_inline_line_numbers.py — Add a test case to the new file verifying that a two-hunk patch `"@@ -1,2 +1,2 @@\n a\n+b\n@@ -20,2 +21,3 @@\n c\n+d\n e"` yields lines 2 and 22 for the added lines. VERIFY: `cd backend && python3 -m pytest tests/test_pull_requests_inline_line_numbers.py::test_multi_hunk_line_numbers -q` (cat:test; multifile:no) [feat:gitlark-20261109-number-pr-inline-comments-from-the-hunk-]
- [ ] [T5] backend/tests/test_pull_requests_inline_line_numbers.py — Add a test case to the new file verifying that a hunk header with no counts `"@@ -5 +5 @@\n-x\n+y"` yields line 5 for the added line. VERIFY: `cd backend && python3 -m pytest tests/test_pull_requests_inline_line_numbers.py::test_header_no_counts -q` (cat:test; multifile:no) [feat:gitlark-20261109-number-pr-inline-comments-from-the-hunk-]

# --- 27B-decomposed from roadmap [2026-11-09]: Parse single-line hunk headers (`@@ -1 +1 @@`) in `parse_unified_diff` instead of dropping (review + tweak) [feat:gitlark-20261109-parse-single-line-hunk-headers-1-1-in-pa] ---
- [ ] [T1] backend/app/services/diff_parser.py — Add `import re` at the top of the file to enable regex-based hunk header parsing. VERIFY: `grep -q "^import re$" backend/app/services/diff_parser.py`. (cat:python; multifile:no) [feat:gitlark-20261109-parse-single-line-hunk-headers-1-1-in-pa]
- [ ] [T2] backend/app/services/diff_parser.py — Replace the `old_part.split(',')` and `new_part.split(',')` logic in `parse_unified_diff` with `re.fullmatch(r"[-+](\d+)(?:,(\d+))?", part)` for both old and new parts, defaulting count to 1 if the second group is None. VERIFY: `cd backend && python3 -c "from app.services.diff_parser import parse_unified_diff; r = parse_unified_diff('--- a/x\n+++ b/x\n@@ -1 +1 @@\n-a\n+b\n'); assert len(r[0].hunks) == 1 and r[0].hunks[0].old_count == 1 and r[0].hunks[0].new_count == 1"`. (cat:python; multifile:no) [feat:gitlark-20261109-parse-single-line-hunk-headers-1-1-in-pa]
- [ ] [T3] backend/tests/test_diff_parser.py — Add a test case `test_parse_single_line_hunk` that asserts `parse_unified_diff("--- a/x\n+++ b/x\n@@ -1 +1 @@\n-a\n+b\n")` results in 1 hunk with `old_start==1`, `old_count==1`, `new_start==1`, `new_count==1`, `additions==1`, `removed==1`. VERIFY: `cd backend && python3 -m pytest tests/test_diff_parser.py::test_parse_single_line_hunk -q`. (cat:test; multifile:no) [feat:gitlark-20261109-parse-single-line-hunk-headers-1-1-in-pa]
- [ ] [T4] backend/tests/test_diff_parser.py — Add a test case `test_parse_mixed_count_hunk` that asserts `parse_unified_diff("--- a/x\n+++ b/x\n@@ -3,2 +3 @@\n-a\n-b\n+c\n")` results in 1 hunk with `old_count==2` and `new_count==1`. VERIFY: `cd backend && python3 -m pytest tests/test_diff_parser.py::test_parse_mixed_count_hunk -q`. (cat:test; multifile:no) [feat:gitlark-20261109-parse-single-line-hunk-headers-1-1-in-pa]
- [ ] [T5] backend/tests/test_diff_parser.py — Add a test case `test_parse_standard_comma_hunk` that asserts `parse_unified_diff("--- a/x\n+++ b/x\n@@ -1,3 +1,4 @@\n-a\n-b\n+c\n+d\n")` results in 1 hunk with `old_count==3` and `new_count==4`. VERIFY: `cd backend && python3 -m pytest tests/test_diff_parser.py::test_parse_standard_comma_hunk -q`. (cat:test; multifile:no) [feat:gitlark-20261109-parse-single-line-hunk-headers-1-1-in-pa]

# --- 27B-decomposed from roadmap [2026-11-09]: Stop `format_review_summary` crashing on a null severity and escape file names in its HTML (review + tweak) [feat:gitlark-20261109-stop-format-review-summary-crashing-on-a] ---
- [ ] [T1] backend/app/services/review_formatting.py — Add `import html` at the top of the file to enable HTML escaping utilities. VERIFY: `cd backend && python3 -c "from app.services.review_formatting import *; import inspect; src = inspect.getsource(__import__('app.services.review_formatting', fromlist=['*'])); assert 'import html' in src"`. (cat:python; multifile:no) [feat:gitlark-20261109-stop-format-review-summary-crashing-on-a]
- [ ] [T2] backend/app/services/review_formatting.py — In `format_review_summary`, replace `f.get("severity", "info").lower()` with `sev = str(f.get("severity") or "info").lower()` to handle null severities. VERIFY: `cd backend && python3 -c "from app.services.review_formatting import format_review_summary; r = format_review_summary([{'severity': None, 'file': 'a.py', 'message': 'm'}]); assert '### Info (1)' in r"`. (cat:python; multifile:no) [feat:gitlark-20261109-stop-format-review-summary-crashing-on-a]
- [ ] [T3] backend/app/services/review_formatting.py — In `format_review_summary`, replace raw file interpolation with `fname = html.escape(str(item.get("file") or "unknown"))` and use `fname` in the HTML output. VERIFY: `cd backend && python3 -c "from app.services.review_formatting import format_review_summary; r = format_review_summary([{'severity': 'info', 'file': '<b>x</b>', 'message': 'm'}]); assert '&lt;b&gt;x&lt;/b&gt;' in r and '<strong><b>' not in r"`. (cat:python; multifile:no) [feat:gitlark-20261109-stop-format-review-summary-crashing-on-a]
- [ ] [T4] backend/app/services/review_formatting.py — In `format_review_summary`, modify the line rendering logic to output `?` when `line` is None or missing, instead of `None`. VERIFY: `cd backend && python3 -c "from app.services.review_formatting import format_review_summary; r = format_review_summary([{'severity': 'info', 'file': 'a.py', 'message': 'm', 'line': None}]); assert '**Line ?**' in r and 'Line None' not in r"`. (cat:python; multifile:no) [feat:gitlark-20261109-stop-format-review-summary-crashing-on-a]
- [ ] [T5] backend/tests/test_review_formatting.py — Add a test case `test_null_severity_counts_as_info` that asserts `format_review_summary([{"severity": None, "file": "a.py", "message": "m"}])` contains `### Info (1)` and does not raise. VERIFY: `cd backend && python3 -m pytest tests/test_review_formatting.py::test_null_severity_counts_as_info -q`. (cat:test; multifile:no) [feat:gitlark-20261109-stop-format-review-summary-crashing-on-a]

# --- 27B-decomposed from roadmap [2026-11-09]: Make `normalize_tags` honour `max_tags <= 0` - `backend/app/services/tag_normalizer.py` ap (review + tweak) [feat:gitlark-20261109-make-normalize-tags-honour-max-tags-0-ba] ---
- [ ] [T1] backend/app/services/tag_normalizer.py — Add `if max_tags <= 0: return []` guard at the top of `normalize_tags` after the empty-input check. VERIFY: `cd backend && python3 -c "from app.services.tag_normalizer import normalize_tags; assert normalize_tags(['a'], 0) == []; assert normalize_tags(['a'], -1) == []"`. (cat:python; multifile:no) [feat:gitlark-20261109-make-normalize-tags-honour-max-tags-0-ba]
- [ ] [T2] backend/tests/test_tag_normalizer.py — Add test cases to existing class verifying `normalize_tags(["a", "b"], 0) == []` and `normalize_tags(["a"], -3) == []`. VERIFY: `cd backend && python3 -m pytest tests/test_tag_normalizer.py -q`. (cat:test; multifile:no) [feat:gitlark-20261109-make-normalize-tags-honour-max-tags-0-ba]
- [ ] [T3] backend/tests/test_tag_normalizer.py — Add test cases verifying `normalize_tags(["a", "b", "c"], 2) == ["a", "b"]` and default cap behavior remains unchanged. VERIFY: `cd backend && python3 -m pytest tests/test_tag_normalizer.py -q`. (cat:test; multifile:no) [feat:gitlark-20261109-make-normalize-tags-honour-max-tags-0-ba]

# --- 27B-decomposed from roadmap [2026-11-09]: Raise `LLMConnectionError` from `LocalLLMClient.generate`/`chat` like `stream_message` doe (review + tweak) [feat:gitlark-20261109-raise-llmconnectionerror-from-localllmcl] ---
- [ ] [T1] backend/app/services/local_llm_client.py — Wrap the `httpx.post` call and response handling in `generate` with `try: ... except httpx.HTTPError as e: raise LLMConnectionError(f"Failed to reach local LLM server: {e}") from e` VERIFY: `cd backend && python -c "from app.services.local_llm_client import LocalLLMClient; import inspect; src=inspect.getsource(LocalLLMClient.generate); assert 'except httpx.HTTPError' in src and 'LLMConnectionError' in src"`. (cat:python; multifile:no) [feat:gitlark-20261109-raise-llmconnectionerror-from-localllmcl]
- [ ] [T1] backend/app/services/local_llm_client.py — Wrap the `httpx.post` call and response handling in `chat` with `try: ... except httpx.HTTPError as e: raise LLMConnectionError(f"Failed to reach local LLM server: {e}") from e` VERIFY: `cd backend && python -c "from app.services.local_llm_client import LocalLLMClient; import inspect; src=inspect.getsource(LocalLLMClient.chat); assert 'except httpx.HTTPError' in src and 'LLMConnectionError' in src"`. (cat:python; multifile:no) [feat:gitlark-20261109-raise-llmconnectionerror-from-localllmcl]
- [ ] [T2] backend/tests/test_local_llm_client.py — Add a test `test_generate_raises_connection_error_on_500` that mocks `httpx.AsyncClient` with a `MockTransport` returning 500 and asserts `pytest.raises(LLMConnectionError)` when calling `client.generate("hi")` VERIFY: `cd backend && python -m pytest tests/test_local_llm_client.py::test_generate_raises_connection_error_on_500 -q`. (cat:test; multifile:no) [feat:gitlark-20261109-raise-llmconnectionerror-from-localllmcl]
- [ ] [T2] backend/tests/test_local_llm_client.py — Add a test `test_chat_raises_connection_error_on_500` that mocks `httpx.AsyncClient` with a `MockTransport` returning 500 and asserts `pytest.raises(LLMConnectionError)` when calling `client.chat([{"role": "user", "content": "hi"}])` VERIFY: `cd backend && python -m pytest tests/test_local_llm_client.py::test_chat_raises_connection_error_on_500 -q`. (cat:test; multifile:no) [feat:gitlark-20261109-raise-llmconnectionerror-from-localllmcl]
- [ ] [T2] backend/tests/test_local_llm_client.py — Add a test `test_generate_returns_ok_on_200` that mocks `httpx.AsyncClient` with a `MockTransport` returning 200 with JSON `{"response": "ok"}` and asserts `await client.generate("hi") == "ok"` VERIFY: `cd backend && python -m pytest tests/test_local_llm_client.py::test_generate_returns_ok_on_200 -q`. (cat:test; multifile:no) [feat:gitlark-20261109-raise-llmconnectionerror-from-localllmcl]
- [ ] [T2] backend/tests/test_local_llm_client.py — Add a test `test_chat_returns_ok_on_200` that mocks `httpx.AsyncClient` with a `MockTransport` returning 200 with JSON `{"response": "ok"}` and asserts `await client.chat([{"role": "user", "content": "hi"}]) == "ok"` VERIFY: `cd backend && python -m pytest tests/test_local_llm_client.py::test_chat_returns_ok_on_200 -q`. (cat:test; multifile:no) [feat:gitlark-20261109-raise-llmconnectionerror-from-localllmcl]

# --- 27B-decomposed from roadmap [2026-11-09]: Make `fleet_event_to_message` tolerate a null or non-dict payload - `backend/app/services/ (review + tweak) [feat:gitlark-20261109-make-fleet-event-to-message-tolerate-a-n] ---
- [ ] [T1] backend/app/services/event_format.py — Modify `fleet_event_to_message` to coerce non-dict `event` to `{}` and non-dict/null `payload` to `{}` inline before processing. VERIFY: `cd backend && python3 -c "from app.services.event_format import fleet_event_to_message; assert isinstance(fleet_event_to_message(None), str); assert isinstance(fleet_event_to_message({'type': 'landed', 'payload': None}), str)"`. (cat:python; multifile:no) [feat:gitlark-20261109-make-fleet-event-to-message-tolerate-a-n]
- [ ] [T2] backend/tests/test_event_format.py — Add test case asserting `fleet_event_to_message({"type": "landed", "payload": None})` returns a string containing `"0 tasks landed on unknown"`. VERIFY: `cd backend && python3 -m pytest tests/test_event_format.py::test_null_payload_landed -q`. (cat:test; multifile:no) [feat:gitlark-20261109-make-fleet-event-to-message-tolerate-a-n]
- [ ] [T3] backend/tests/test_event_format.py — Add test case asserting `fleet_event_to_message({"type": "reverted", "payload": "oops"})` returns a string containing `"task X reverted: unknown"`. VERIFY: `cd backend && python3 -m pytest tests/test_event_format.py::test_string_payload_reverted -q`. (cat:test; multifile:no) [feat:gitlark-20261109-make-fleet-event-to-message-tolerate-a-n]
- [ ] [T4] backend/tests/test_event_format.py — Add test case asserting `fleet_event_to_message({"type": "deploy_fail"})` returns a string containing `"deploy failed on unknown: unknown error"`. VERIFY: `cd backend && python3 -m pytest tests/test_event_format.py::test_missing_payload_deploy_fail -q`. (cat:test; multifile:no) [feat:gitlark-20261109-make-fleet-event-to-message-tolerate-a-n]
- [ ] [T5] backend/tests/test_event_format.py — Add test case asserting `fleet_event_to_message(None)` returns a string ending with `"event: None"`. VERIFY: `cd backend && python3 -m pytest tests/test_event_format.py::test_none_event -q`. (cat:test; multifile:no) [feat:gitlark-20261109-make-fleet-event-to-message-tolerate-a-n]

# --- 27B-decomposed from roadmap [2026-11-10]: Close the remaining gaps in `validate_task_path` and sanitize the tier/tag in `task_to_bac (review + tweak) [feat:gitlark-20261110-close-the-remaining-gaps-in-validate-tas] ---
- [ ] [T1] backend/app/services/planner_format.py — Add control-character and whitespace validation at the start of `validate_task_path` to return "Invalid characters in path" if any char < 32 or path is empty/whitespace. VERIFY: `cd backend && python3 -m pytest tests/test_planner_format.py::test_validate_task_path_invalid_chars -q`. (cat:python; multifile:no) [feat:gitlark-20261110-close-the-remaining-gaps-in-validate-tas]
- [ ] [T1] backend/app/services/planner_format.py — Normalize backslashes to forward slashes in `validate_task_path` and reject paths containing `..` segments or `.git`/`.github` segments. VERIFY: `cd backend && python3 -m pytest tests/test_planner_format.py::test_validate_task_path_traversal_and_git -q`. (cat:python; multifile:no) [feat:gitlark-20261110-close-the-remaining-gaps-in-validate-tas]
- [ ] [T1] backend/app/services/planner_format.py — Sanitize `tier` and `tag` in `task_to_backlog_line` by stripping brackets from tier and applying `sanitize_backlog_field` to both. VERIFY: `cd backend && python3 -m pytest tests/test_planner_format.py::test_task_to_backlog_line_sanitization -q`. (cat:python; multifile:no) [feat:gitlark-20261110-close-the-remaining-gaps-in-validate-tas]
- [ ] [T2] backend/tests/test_planner_format.py — Add test cases for `validate_task_path` rejecting `.git`, `.github`, `a/b/.git`, `a\..\b`, `a/b\x00c`, and `"   "`. VERIFY: `cd backend && python3 -m pytest tests/test_planner_format.py::test_validate_task_path_invalid_chars tests/test_planner_format.py::test_validate_task_path_traversal_and_git -q`. (cat:test; multifile:no) [feat:gitlark-20261110-close-the-remaining-gaps-in-validate-tas]
- [ ] [T2] backend/tests/test_planner_format.py — Add test cases for `validate_task_path` accepting `backend/app/x.py`, `.gitignore`, `docs/gitignore.md`, and `.github_notes.md`. VERIFY: `cd backend && python3 -m pytest tests/test_planner_format.py::test_validate_task_path_valid_paths -q`. (cat:test; multifile:no) [feat:gitlark-20261110-close-the-remaining-gaps-in-validate-tas]
- [ ] [T2] backend/tests/test_planner_format.py — Add test case for `task_to_backlog_line` ensuring no newlines in output and exactly one `- [ ]` marker when inputs contain injection attempts. VERIFY: `cd backend && python3 -m pytest tests/test_planner_format.py::test_task_to_backlog_line_sanitization -q`. (cat:test; multifile:no) [feat:gitlark-20261110-close-the-remaining-gaps-in-validate-tas]

# --- 27B-decomposed from roadmap [2026-11-10]: Return the DEFAULT pill for prototype-chain keys in `planStatusPill` - `web/src/utils/plan (review + tweak) [feat:gitlark-20261110-return-the-default-pill-for-prototype-ch] ---
- [ ] [T1] web/src/utils/planStatusPill.ts — Replace the `STATUS_MAP[state] || DEFAULT_PILL` lookup with `Object.prototype.hasOwnProperty.call(STATUS_MAP, state) ? STATUS_MAP[state] : DEFAULT_PILL` to prevent prototype chain pollution. VERIFY: `cd web && npx tsc --noEmit`. (cat:typescript; multifile:no) [feat:gitlark-20261110-return-the-default-pill-for-prototype-ch]
- [ ] [T2] web/src/utils/__tests__/planStatusPill.test.ts — Add test cases asserting that `planStatusPill('constructor')`, `planStatusPill('toString')`, `planStatusPill('__proto__')`, and `planStatusPill('hasOwnProperty')` all return `{ label: 'Unknown', color: 'gray' }`. VERIFY: `cd web && npx vitest run src/utils/__tests__/planStatusPill.test.ts -t "prototype"`. (cat:test; multifile:no) [feat:gitlark-20261110-return-the-default-pill-for-prototype-ch]
- [ ] [T3] web/src/utils/__tests__/planStatusPill.test.ts — Verify existing tests for the six known statuses and the generic unknown state still pass after the change. VERIFY: `cd web && npx vitest run src/utils/__tests__/planStatusPill.test.ts`. (cat:test; multifile:no) [feat:gitlark-20261110-return-the-default-pill-for-prototype-ch]

# --- 27B-decomposed from roadmap [2026-11-10]: Do not cut a surrogate pair in half in `truncateMsg` - `web/src/utils/truncateMsg.ts` uses (review + tweak) [feat:gitlark-20261110-do-not-cut-a-surrogate-pair-in-half-in-t] ---
- [ ] [T1] web/src/utils/truncateMsg.ts — Modify `truncateMsg` to check if the last code unit of the sliced string is a high surrogate (`/[\ud800-\udbff]$/.test(cut)`) and drop it before appending the ellipsis. VERIFY: `cd web && npx vitest run src/utils/__tests__/truncateMsg.test.ts -t "surrogate"` (assuming test name added in next step, or just run full file). (cat:typescript; multifile:no) [feat:gitlark-20261110-do-not-cut-a-surrogate-pair-in-half-in-t]
- [ ] [T2] web/src/utils/__tests__/truncateMsg.test.ts — Add test case `expect(truncateMsg('\u{1F600}\u{1F600}\u{1F600}', 2)).toBe('\u2026')` and `expect(truncateMsg('\u{1F600}\u{1F600}\u{1F600}', 4)).toBe('\u{1F600}\u2026')`. VERIFY: `cd web && npx vitest run src/utils/__tests__/truncateMsg.test.ts`. (cat:test; multifile:no) [feat:gitlark-20261110-do-not-cut-a-surrogate-pair-in-half-in-t]
- [ ] [T2] web/src/utils/__tests__/truncateMsg.test.ts — Add test case `expect(truncateMsg('abcdef', 4)).toBe('abc\u2026')` and `expect(truncateMsg('abc', 3)).toBe('abc')`. VERIFY: `cd web && npx vitest run src/utils/__tests__/truncateMsg.test.ts`. (cat:test; multifile:no) [feat:gitlark-20261110-do-not-cut-a-surrogate-pair-in-half-in-t]
- [ ] [T2] web/src/utils/__tests__/truncateMsg.test.ts — Add test case asserting that for emoji inputs, the result does not match `/[\ud800-\udbff](?![\udc00-\udfff])/`. VERIFY: `cd web && npx vitest run src/utils/__tests__/truncateMsg.test.ts`. (cat:test; multifile:no) [feat:gitlark-20261110-do-not-cut-a-surrogate-pair-in-half-in-t]

# --- 27B-decomposed from roadmap [2026-11-10]: Return an empty string from `formatTime` for an invalid date instead of `NaNd ago` - `web/ (review + tweak) [feat:gitlark-20261110-return-an-empty-string-from-formattime-f] ---
- [ ] [T1] web/src/utils/agent-chat.ts — Add `if (Number.isNaN(date.getTime())) return '';` as the first statement in the `formatTime` function body. VERIFY: `cd web && npx vitest run src/utils/__tests__/agentChat.test.ts -t "invalid date"`. (cat:typescript; multifile:no) [feat:gitlark-20261110-return-an-empty-string-from-formattime-f]
- [ ] [T2] web/src/utils/__tests__/agentChat.test.ts — Add a test case asserting `formatTime(new Date('not a date'))` equals `''`. VERIFY: `cd web && npx vitest run src/utils/__tests__/agentChat.test.ts -t "invalid date"`. (cat:test; multifile:no) [feat:gitlark-20261110-return-an-empty-string-from-formattime-f]
- [ ] [T2] web/src/utils/__tests__/agentChat.test.ts — Add a test case using `vi.useFakeTimers()` and `vi.setSystemTime` to assert `formatTime` for a date 30 seconds ago equals `'now'`. VERIFY: `cd web && npx vitest run src/utils/__tests__/agentChat.test.ts -t "30 seconds"`. (cat:test; multifile:no) [feat:gitlark-20261110-return-an-empty-string-from-formattime-f]
- [ ] [T2] web/src/utils/__tests__/agentChat.test.ts — Add a test case using `vi.useFakeTimers()` and `vi.setSystemTime` to assert `formatTime` for a date 5 minutes ago equals `'5m ago'`. VERIFY: `cd web && npx vitest run src/utils/__tests__/agentChat.test.ts -t "5 minutes"`. (cat:test; multifile:no) [feat:gitlark-20261110-return-an-empty-string-from-formattime-f]
- [ ] [T2] web/src/utils/__tests__/agentChat.test.ts — Add a test case using `vi.useFakeTimers()` and `vi.setSystemTime` to assert `formatTime` for a date 3 hours ago equals `'3h ago'`. VERIFY: `cd web && npx vitest run src/utils/__tests__/agentChat.test.ts -t "3 hours"`. (cat:test; multifile:no) [feat:gitlark-20261110-return-an-empty-string-from-formattime-f]
- [ ] [T2] web/src/utils/__tests__/agentChat.test.ts — Add a test case using `vi.useFakeTimers()` and `vi.setSystemTime` to assert `formatTime` for a date 2 days ago equals `'2d ago'`. VERIFY: `cd web && npx vitest run src/utils/__tests__/agentChat.test.ts -t "2 days"`. (cat:test; multifile:no) [feat:gitlark-20261110-return-an-empty-string-from-formattime-f]

# --- 27B-decomposed from roadmap [2026-11-10]: Clear the previous pull request when `fetchPull` starts so a failed load cannot show the w (review + tweak) [feat:gitlark-20261110-clear-the-previous-pull-request-when-fet] ---
- [ ] [T3] web/src/stores/pulls.ts — Modify `fetchPull` to set `currentPull.value = null` at the start of the function alongside `error.value = null`. VERIFY: `cd web && npx vitest run src/stores/__tests__/pulls.test.ts`. (cat:typescript; multifile:no) [feat:gitlark-20261110-clear-the-previous-pull-request-when-fet]
- [ ] [T1] web/src/stores/__tests__/pulls.test.ts — Create test file mocking `@/services/api` and `createPinia`, asserting `fetchPull` success sets `currentPull.number` to 1. VERIFY: `cd web && npx vitest run src/stores/__tests__/pulls.test.ts`. (cat:test; multifile:no) [feat:gitlark-20261110-clear-the-previous-pull-request-when-fet]
- [ ] [T2] web/src/stores/__tests__/pulls.test.ts — Add test case asserting that after a failed `fetchPull`, `currentPull` is `null`, `error` is `'Failed to fetch pull request'`, and `isLoading` is false. VERIFY: `cd web && npx vitest run src/stores/__tests__/pulls.test.ts`. (cat:test; multifile:no) [feat:gitlark-20261110-clear-the-previous-pull-request-when-fet]

# --- 27B-decomposed from roadmap [2026-11-10]: Show API validation arrays as text in the notification bell errors - `web/src/components/N (review + tweak) [feat:gitlark-20261110-show-api-validation-arrays-as-text-in-th] ---
- [ ] [T3] web/src/components/NotificationBell.vue — Add `import { getErrorMessage } from '@/utils/apiError'` to the script imports. VERIFY: `grep -q "import { getErrorMessage } from '@/utils/apiError'" web/src/components/NotificationBell.vue`. (cat:vue; multifile:no) [feat:gitlark-20261110-show-api-validation-arrays-as-text-in-th]
- [ ] [T3] web/src/components/NotificationBell.vue — Replace the first assignment `error.value = e.response?.data?.detail || 'Failed to load notifications'` (or similar fallback) with `error.value = getErrorMessage(e, 'Failed to load notifications')`. VERIFY: `! grep -q "e.response?.data?.detail" web/src/components/NotificationBell.vue && grep -q "getErrorMessage(e, 'Failed to load notifications')" web/src/components/NotificationBell.vue`. (cat:vue; multifile:no) [feat:gitlark-20261110-show-api-validation-arrays-as-text-in-th]
- [ ] [T3] web/src/components/NotificationBell.vue — Replace the second assignment `error.value = e.response?.data?.detail || 'Failed to send notification'` (or similar fallback) with `error.value = getErrorMessage(e, 'Failed to send notification')`. VERIFY: `! grep -q "e.response?.data?.detail" web/src/components/NotificationBell.vue && grep -q "getErrorMessage(e, 'Failed to send notification')" web/src/components/NotificationBell.vue`. (cat:vue; multifile:no) [feat:gitlark-20261110-show-api-validation-arrays-as-text-in-th]
- [ ] [T3] web/src/components/NotificationBell.vue — Replace the third assignment `error.value = e.response?.data?.detail || 'Failed to mark as read'` (or similar fallback) with `error.value = getErrorMessage(e, 'Failed to mark as read')`. VERIFY: `! grep -q "e.response?.data?.detail" web/src/components/NotificationBell.vue && grep -q "getErrorMessage(e, 'Failed to mark as read')" web/src/components/NotificationBell.vue`. (cat:vue; multifile:no) [feat:gitlark-20261110-show-api-validation-arrays-as-text-in-th]
- [ ] [T3] web/src/components/NotificationBell.vue — Replace the fourth assignment `error.value = e.response?.data?.detail || 'Failed to clear notifications'` (or similar fallback) with `error.value = getErrorMessage(e, 'Failed to clear notifications')`. VERIFY: `test "$(grep -c 'e.response?.data?.detail' web/src/components/NotificationBell.vue)" -eq 0 && grep -q "getErrorMessage(e, 'Failed to clear notifications')" web/src/components/NotificationBell.vue`. (cat:vue; multifile:no) [feat:gitlark-20261110-show-api-validation-arrays-as-text-in-th]
- [ ] [T1] web/src/components/__tests__/NotificationBell.errors.test.ts — Add test case asserting that when `fetchNotifications` rejects with `{ response: { data: { detail: [{ msg: 'bad thing' }] } } }`, the `.error` element contains text `bad thing` and does not contain `[object Object]`. VERIFY: `cd web && npx vitest run src/components/__tests__/NotificationBell.errors.test.ts -t "renders array detail as text"`. (cat:test; multifile:no) [feat:gitlark-20261110-show-api-validation-arrays-as-text-in-th]
- [ ] [T1] web/src/components/__tests__/NotificationBell.errors.test.ts — Add test case asserting that when `fetchNotifications` rejects with `{ response: { data: { detail: 'Nope' } } }`, the `.error` element contains text `Nope`. VERIFY: `cd web && npx vitest run src/components/__tests__/NotificationBell.errors.test.ts -t "renders string detail"`. (cat:test; multifile:no) [feat:gitlark-20261110-show-api-validation-arrays-as-text-in-th]
- [ ] [T1] web/src/components/__tests__/NotificationBell.errors.test.ts — Add test case asserting that when `fetchNotifications` rejects with an error object lacking a `response` property, the `.error` element contains text `Failed to load notifications`. VERIFY: `cd web && npx vitest run src/components/__tests__/NotificationBell.errors.test.ts -t "renders fallback on no response"`. (cat:test; multifile:no) [feat:gitlark-20261110-show-api-validation-arrays-as-text-in-th]

# --- 27B-decomposed from roadmap [2026-11-11]: Handle clipboard failures in the snippet browser copy-and-track action - `copyToClipboard` (review + tweak) [feat:gitlark-20261111-handle-clipboard-failures-in-the-snippet] ---
- [ ] [T2] web/src/components/SnippetBrowser.vue — Change `copyToClipboard` signature to `async` and replace the body with `try { await navigator.clipboard.writeText(selectedSnippet.value.content) } catch (error) { console.error('Failed to copy snippet:', error) }`, removing the `.then()` chain and `console.log`. VERIFY: `test "$(grep -c "await navigator.clipboard.writeText(selectedSnippet.value.content)" web/src/components/SnippetBrowser.vue)" -eq 1` && `test "$(grep -c "console.log('Copied to clipboard')" web/src/components/SnippetBrowser.vue)" -eq 0`. (cat:vue; multifile:no) [feat:gitlark-20261111-handle-clipboard-failures-in-the-snippet]
- [ ] [T2] web/src/components/SnippetBrowser.vue — Update the call site in `recordUse` to `await copyToClipboard()` to ensure sequential execution and proper error propagation context. VERIFY: `test "$(grep -c "await copyToClipboard()" web/src/components/SnippetBrowser.vue)" -eq 1`. (cat:vue; multifile:no) [feat:gitlark-20261111-handle-clipboard-failures-in-the-snippet]
- [ ] [T1] web/src/components/__tests__/SnippetBrowser.test.ts — Create a unit test that mocks `navigator.clipboard.writeText` to reject, renders `SnippetBrowser`, triggers the copy action, and asserts that `console.error` is called with 'Failed to copy snippet:' and no unhandled promise rejections occur. VERIFY: `cd web && npx vitest run src/components/__tests__/SnippetBrowser.test.ts`. (cat:test; multifile:no) [feat:gitlark-20261111-handle-clipboard-failures-in-the-snippet]
- [ ] [T1] web/src/components/__tests__/SnippetBrowser.test.ts — Add a test case that mocks `navigator.clipboard.writeText` to resolve, triggers the copy action, and asserts that `console.log` is NOT called with 'Copied to clipboard' (verifying the log removal). VERIFY: `cd web && npx vitest run src/components/__tests__/SnippetBrowser.test.ts`. (cat:test; multifile:no) [feat:gitlark-20261111-handle-clipboard-failures-in-the-snippet]
- [ ] [T3] web/src/components/SnippetBrowser.vue — Ensure `recordUse` is marked as `async` if it is not already, to support the `await copyToClipboard()` call without syntax errors. VERIFY: `cd web && npx vue-tsc --noEmit`. (cat:vue; multifile:no) [feat:gitlark-20261111-handle-clipboard-failures-in-the-snippet]

# --- 27B-decomposed from roadmap [2026-11-11]: Keep arbitrary event types out of the `EventMessage` class attribute - `web/src/components (review + tweak) [feat:gitlark-20261111-keep-arbitrary-event-types-out-of-the-ev] ---
- [ ] [T1] web/src/components/__tests__/EventMessage.test.ts — Create test file with cases for 'landed', 'deploy fail', '../x', empty type, and <time> datetime/summary rendering using @vue/test-utils mount. VERIFY: cd web && npx vitest run src/components/__tests__/EventMessage.test.ts --reporter=verbose 2>&1 | grep -q "FAIL" && exit 1 || true (expect failure before fix). (cat:test; multifile:no) [feat:gitlark-20261111-keep-arbitrary-event-types-out-of-the-ev]
- [ ] [T2] web/src/components/EventMessage.vue — Add computed safeType sanitizing props.event.type to lowercase alphanumeric/dash/underscore and eventClass computed returning "event-message event-" + safeType.value. VERIFY: cd web && npx vitest run src/components/__tests__/EventMessage.test.ts 2>&1 | grep -q "Tests.*failed" && exit 1 || true (expect failure if not wired). (cat:vue; multifile:no) [feat:gitlark-20261111-keep-arbitrary-event-types-out-of-the-ev]
- [ ] [T3] web/src/components/EventMessage.vue — Update template root element class binding to use eventClass.value instead of raw string interpolation. VERIFY: cd web && npx vitest run src/components/__tests__/EventMessage.test.ts 2>&1 | grep -q "Tests.*failed" && exit 1 || true (expect failure if not wired). (cat:vue; multifile:no) [feat:gitlark-20261111-keep-arbitrary-event-types-out-of-the-ev]
- [ ] [T4] web/src/components/EventMessage.vue — Ensure summary and timestamp markup remains unchanged while class binding is updated. VERIFY: cd web && npx vitest run src/components/__tests__/EventMessage.test.ts 2>&1 | grep -q "Tests.*failed" && exit 1 || true (expect failure if not wired). (cat:vue; multifile:no) [feat:gitlark-20261111-keep-arbitrary-event-types-out-of-the-ev]
- [ ] [T5] web/src/components/EventMessage.vue — Finalize component with safeType and eventClass computeds wired to template class attribute. VERIFY: cd web && npx vitest run src/components/__tests__/EventMessage.test.ts 2>&1 | grep -q "Tests.*failed" && exit 1 || true (expect failure if not wired). (cat:vue; multifile:no) [feat:gitlark-20261111-keep-arbitrary-event-types-out-of-the-ev]
