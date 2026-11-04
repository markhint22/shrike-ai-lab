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
- [ ] [T1] backend/app/core/config.py — Replace the `print` statement at lines 192-193 for missing `DATABASE_URL` with `logging.getLogger(__name__).warning("Missing DATABASE_URL in production environment")`. VERIFY: `cd backend && grep -q "logging.getLogger(__name__).warning" app/core/config.py && ! grep -q "print.*Missing DATABASE_URL" app/core/config.py`. (cat:python; multifile:no) [feat:gitlark-20261102-route-the-production-config-warnings-thr]
- [ ] [T1] backend/app/core/config.py — Replace the `print` statement at lines 207-208 for invalid `SECRET_KEY` with `logging.getLogger(__name__).warning("Invalid SECRET_KEY in production environment")`. VERIFY: `cd backend && grep -q "logging.getLogger(__name__).warning" app/core/config.py && ! grep -q "print.*Invalid SECRET_KEY" app/core/config.py`. (cat:python; multifile:no) [feat:gitlark-20261102-route-the-production-config-warnings-thr]
- [ ] [T2] backend/tests/test_config_prod_warnings_logged.py — Create a test file that imports `Settings` and `caplog`, constructs `Settings(environment="production", database_url="", secret_key="")`, and asserts that two WARNING records are captured with the specific messages "Missing DATABASE_URL in production environment" and "Invalid SECRET_KEY in production environment". VERIFY: `cd backend && python3 -m pytest tests/test_config_prod_warnings_logged.py -q`. (cat:test; multifile:no) [feat:gitlark-20261102-route-the-production-config-warnings-thr]
- [ ] [T2] backend/tests/test_config_prod_warnings_logged.py — Add a test case to the new file that uses `capsys` to assert that no output is written to stdout during the construction of `Settings(environment="production", database_url="", secret_key="")`. VERIFY: `cd backend && python3 -m pytest tests/test_config_prod_warnings_logged.py::test_no_stdout_output -q`. (cat:test; multifile:no) [feat:gitlark-20261102-route-the-production-config-warnings-thr]
- [ ] [T3] backend/tests/test_config_token_warning.py — Verify that the existing test for `TOKEN_ENCRYPTION_KEY` still passes and asserts the stderr warning is unchanged. VERIFY: `cd backend && python3 -m pytest tests/test_config_token_warning.py -q`. (cat:test; multifile:no) [feat:gitlark-20261102-route-the-production-config-warnings-thr]
- [ ] [T4] backend/app/core/config.py — Ensure `logging` is imported at the top of the file if not already present, and verify no other `print` statements remain in `Settings.__init__` for production warnings. VERIFY: `cd backend && python3 -c "import ast; tree=ast.parse(open('app/core/config.py').read()); imports=[n for n in ast.walk(tree) if isinstance(n, ast.Import) or isinstance(n, ast.ImportFrom)]; assert any('logging' in [a.name for a in i.names] if isinstance(i, ast.Import) else 'logging' in (i.module or '') for i in imports)"`. (cat:python; multifile:no) [feat:gitlark-20261102-route-the-production-config-warnings-thr]

# --- 27B-decomposed from roadmap [2026-11-02]: Make the backend PWA manifest icon paths match the real files — `backend/app/routers/pwa.p (review + tweak) [feat:gitlark-20261102-make-the-backend-pwa-manifest-icon-paths] ---
- [ ] [T3] backend/app/routers/pwa.py — Update `MANIFEST` icons to `/icon-192.png`, `/icon-512.png`, and add a third entry with `src: "/icon-512.png"` and `purpose: "maskable"`. VERIFY: `cd backend && python3 -c "from app.routers.pwa import MANIFEST; assert any(i['src'] == '/icon-192.png' for i in MANIFEST['icons']); assert any(i['src'] == '/icon-512.png' and i.get('purpose') == 'maskable' for i in MANIFEST['icons'])"`. (cat:python; multifile:no) [feat:gitlark-20261102-make-the-backend-pwa-manifest-icon-paths]
- [ ] [T1] backend/tests/test_pwa_manifest_icons.py — Create test file that imports `MANIFEST` from `app.routers.pwa`, asserts all icon `src` paths exist under `Path(__file__).resolve().parents[2] / "web" / "public"`, and asserts a maskable icon entry exists. VERIFY: `cd backend && python3 -m pytest tests/test_pwa_manifest_icons.py -q`. (cat:test; multifile:no) [feat:gitlark-20261102-make-the-backend-pwa-manifest-icon-paths]

# --- 27B-decomposed from roadmap [2026-11-02]: Run the container as a non-root user and drop the stray `Dockerfile.bak` — repo-root `Dock (review + tweak) [feat:gitlark-20261102-run-the-container-as-a-non-root-user-and] ---
- [ ] [T2] backend/tests/test_dockerfile_hardening.py — Add test asserting `Dockerfile.bak` does not exist in the repository root. VERIFY: `cd backend && python3 -m pytest tests/test_dockerfile_hardening.py::test_dockerfile_bak_removed -q`. (cat:test; multifile:no) [feat:gitlark-20261102-run-the-container-as-a-non-root-user-and]
- [ ] [T2] backend/tests/test_dockerfile_hardening.py — Add test asserting a `USER` line with a non-root value appears before the `CMD` instruction in the root `Dockerfile`. VERIFY: `cd backend && python3 -m pytest tests/test_dockerfile_hardening.py::test_user_instruction_present -q`. (cat:test; multifile:no) [feat:gitlark-20261102-run-the-container-as-a-non-root-user-and]
- [ ] [T2] backend/tests/test_dockerfile_hardening.py — Add test asserting the `CMD` instruction contains both `alembic upgrade head` and `uvicorn` in the correct order. VERIFY: `cd backend && python3 -m pytest tests/test_dockerfile_hardening.py::test_cmd_sequence -q`. (cat:test; multifile:no) [feat:gitlark-20261102-run-the-container-as-a-non-root-user-and]
- [ ] [T4] Dockerfile — Add `RUN useradd --create-home --uid 10001 appuser && chown -R appuser:appuser /app` after `COPY backend/ .` and add `USER appuser` before the existing `CMD`. VERIFY: `grep -q "USER appuser" Dockerfile && grep -q "useradd.*appuser" Dockerfile`. (cat:infra; multifile:no) [feat:gitlark-20261102-run-the-container-as-a-non-root-user-and]
- [ ] [T4] Dockerfile.bak — Remove the file from the repository. VERIFY: `test ! -f Dockerfile.bak`. (cat:refactor; multifile:no) [feat:gitlark-20261102-run-the-container-as-a-non-root-user-and]

# --- 27B-decomposed from roadmap [2026-11-02]: Add a pure GitHub rate-limit header parser — `backend/app/services/github.py` never reads  (review + tweak) [feat:gitlark-20261102-add-a-pure-github-rate-limit-header-pars] ---
- [ ] [T1] backend/app/services/github_rate_limit.py — Add frozen dataclass `RateLimitInfo` with fields `limit: int | None`, `remaining: int | None`, `reset_epoch: int | None`. VERIFY: `cd backend && python3 -c "from app.services.github_rate_limit import RateLimitInfo; r = RateLimitInfo(1, 2, 3); assert r.limit == 1 and r.remaining == 2 and r.reset_epoch == 3"`. (cat:python; multifile:no) [feat:gitlark-20261102-add-a-pure-github-rate-limit-header-pars]
- [ ] [T1] backend/app/services/github_rate_limit.py — Add function `parse_rate_limit(headers: Mapping[str, str]) -> RateLimitInfo` that reads `X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset` case-insensitively, converting non-numeric strings to `None`. VERIFY: `cd backend && python3 -c "from app.services.github_rate_limit import parse_rate_limit; r = parse_rate_limit({'x-ratelimit-limit': '100', 'X-RATELIMIT-REMAINING': '50', 'X-RateLimit-Reset': '123'}); assert r.limit == 100 and r.remaining == 50 and r.reset_epoch == 123"`. (cat:python; multifile:no) [feat:gitlark-20261102-add-a-pure-github-rate-limit-header-pars]
- [ ] [T1] backend/app/services/github_rate_limit.py — Add function `is_exhausted(info: RateLimitInfo, threshold: int = 0) -> bool` that returns `False` if `info.remaining` is `None`, otherwise `info.remaining <= threshold`. VERIFY: `cd backend && python3 -c "from app.services.github_rate_limit import RateLimitInfo, is_exhausted; assert is_exhausted(RateLimitInfo(100, 0, 1)) is True and is_exhausted(RateLimitInfo(100, 1, 1)) is False and is_exhausted(RateLimitInfo(100, None, 1)) is False"`. (cat:python; multifile:no) [feat:gitlark-20261102-add-a-pure-github-rate-limit-header-pars]
- [ ] [T2] backend/tests/test_github_rate_limit.py — Add test `test_parse_full_headers` verifying correct parsing of standard mixed-case headers. VERIFY: `cd backend && python3 -m pytest tests/test_github_rate_limit.py::test_parse_full_headers -q`. (cat:test; multifile:no) [feat:gitlark-20261102-add-a-pure-github-rate-limit-header-pars]
- [ ] [T2] backend/tests/test_github_rate_limit.py — Add test `test_parse_missing_headers` verifying all fields are `None` when headers are empty. VERIFY: `cd backend && python3 -m pytest tests/test_github_rate_limit.py::test_parse_missing_headers -q`. (cat:test; multifile:no) [feat:gitlark-20261102-add-a-pure-github-rate-limit-header-pars]
- [ ] [T2] backend/tests/test_github_rate_limit.py — Add test `test_parse_lowercase_keys` verifying parsing works with all-lowercase header keys. VERIFY: `cd backend && python3 -m pytest tests/test_github_rate_limit.py::test_parse_lowercase_keys -q`. (cat:test; multifile:no) [feat:gitlark-20261102-add-a-pure-github-rate-limit-header-pars]
- [ ] [T2] backend/tests/test_github_rate_limit.py — Add test `test_parse_garbage_values` verifying non-numeric values result in `None` fields. VERIFY: `cd backend && python3 -m pytest tests/test_github_rate_limit.py::test_parse_garbage_values -q`. (cat:test; multifile:no) [feat:gitlark-20261102-add-a-pure-github-rate-limit-header-pars]
- [ ] [T2] backend/tests/test_github_rate_limit.py — Add test `test_is_exhausted_boundary` verifying threshold behavior including `None` remaining and exact threshold match. VERIFY: `cd backend && python3 -m pytest tests/test_github_rate_limit.py::test_is_exhausted_boundary -q`. (cat:test; multifile:no) [feat:gitlark-20261102-add-a-pure-github-rate-limit-header-pars]

# --- 27B-decomposed from roadmap [2026-11-02]: Log a warning when the GitHub API quota is nearly spent — builds on `backend/app/services/ (review + tweak) [feat:gitlark-20261102-log-a-warning-when-the-github-api-quota-] ---
- [ ] [T1] backend/app/services/github_rate_limit.py — Add `parse_rate_limit(headers: dict) -> tuple[int | None, int | None]` returning `(remaining, reset)` from `X-RateLimit-Remaining` and `X-RateLimit-Reset` headers. VERIFY: `cd backend && python3 -c "from app.services.github_rate_limit import parse_rate_limit; assert parse_rate_limit({'X-RateLimit-Remaining': '5', 'X-RateLimit-Reset': '123'}) == (5, 123)"`. (cat:python; multifile:no) [feat:gitlark-20261102-log-a-warning-when-the-github-api-quota-]
- [ ] [T1] backend/app/services/github_rate_limit.py — Add `is_exhausted(remaining: int | None) -> bool` returning `True` if `remaining` is not None and `<= 0`. VERIFY: `cd backend && python3 -c "from app.services.github_rate_limit import is_exhausted; assert is_exhausted(0) and not is_exhausted(1) and not is_exhausted(None)"`. (cat:python; multifile:no) [feat:gitlark-20261102-log-a-warning-when-the-github-api-quota-]
- [ ] [T2] backend/tests/test_github_rate_limit.py — Create test file with `test_parse_rate_limit_valid` and `test_is_exhausted_logic` verifying the new functions in `github_rate_limit.py`. VERIFY: `cd backend && python3 -m pytest tests/test_github_rate_limit.py -q`. (cat:test; multifile:no) [feat:gitlark-20261102-log-a-warning-when-the-github-api-quota-]
- [ ] [T3] backend/app/services/github.py — In `GitHubClient.execute_with_httpx`, import `parse_rate_limit` from `app.services.github_rate_limit`, extract headers from the response, and if `remaining` is not None and `<= 10`, call `logger.warning("GitHub rate limit low: %s remaining, resets at %s", remaining, reset)` without altering the return value. VERIFY: `cd backend && python3 -c "import ast; tree = ast.parse(open('app/services/github.py').read()); print('OK')"`. (cat:python; multifile:no) [feat:gitlark-20261102-log-a-warning-when-the-github-api-quota-]
- [ ] [T2] backend/tests/test_github_rate_limit_logging.py — Create test file that mocks `httpx.Response` with `X-RateLimit-Remaining: 3` and `500`, monkeypatches the client's executor, and asserts `logger.warning` is called only for the low quota case. VERIFY: `cd backend && python3 -m pytest tests/test_github_rate_limit_logging.py -q`. (cat:test; multifile:no) [feat:gitlark-20261102-log-a-warning-when-the-github-api-quota-]

# --- 27B-decomposed from roadmap [2026-11-02]: Return 400 for a malformed `Content-Length` instead of silently accepting it — the middlew (review + tweak) [feat:gitlark-20261102-return-400-for-a-malformed-content-lengt] ---
- [ ] [T3] backend/app/main.py — In `BodySizeLimitMiddleware.dispatch`, replace the `except ValueError: pass` block with a return of `JSONResponse(status_code=400, content={"detail": "Malformed Content-Length header"})`. VERIFY: `cd backend && python3 -c "from app.main import BodySizeLimitMiddleware; import inspect; src = inspect.getsource(BodySizeLimitMiddleware.dispatch); assert 'status_code=400' in src and 'Malformed Content-Length header' in src"`. (cat:python; multifile:no) [feat:gitlark-20261102-return-400-for-a-malformed-content-lengt]
- [ ] [T1] backend/tests/test_body_size_malformed_length.py — Create a new test file that mounts `BodySizeLimitMiddleware` on a minimal FastAPI app and uses `TestClient` to assert that a POST with `headers={"Content-Length": "abc"}` returns 400. VERIFY: `cd backend && python3 -m pytest tests/test_body_size_malformed_length.py::test_malformed_content_length_returns_400 -q`. (cat:test; multifile:no) [feat:gitlark-20261102-return-400-for-a-malformed-content-lengt]
- [ ] [T1] backend/tests/test_body_size_malformed_length.py — Add a test case to the new file asserting that a POST with an oversized numeric `Content-Length` header returns 413. VERIFY: `cd backend && python3 -m pytest tests/test_body_size_malformed_length.py::test_oversized_content_length_returns_413 -q`. (cat:test; multifile:no) [feat:gitlark-20261102-return-400-for-a-malformed-content-lengt]
- [ ] [T1] backend/tests/test_body_size_malformed_length.py — Add a test case to the new file asserting that a normal POST request with a valid `Content-Length` returns 200. VERIFY: `cd backend && python3 -m pytest tests/test_body_size_malformed_length.py::test_normal_request_returns_200 -q`. (cat:test; multifile:no) [feat:gitlark-20261102-return-400-for-a-malformed-content-lengt]
- [ ] [T5] backend/tests/test_body_size_limit.py — Run the existing test suite to ensure no regressions were introduced by the middleware change. VERIFY: `cd backend && python3 -m pytest tests/test_body_size_limit.py -q`. (cat:test; multifile:no) [feat:gitlark-20261102-return-400-for-a-malformed-content-lengt]
- [ ] [T5] backend/tests/test_body_size_middleware.py — Run the existing middleware test suite to ensure compatibility with the new 400 response behavior. VERIFY: `cd backend && python3 -m pytest tests/test_body_size_middleware.py -q`. (cat:test; multifile:no) [feat:gitlark-20261102-return-400-for-a-malformed-content-lengt]

# --- 27B-decomposed from roadmap [2026-11-02]: Register the environment-aware security-headers middleware instead of the legacy one — `ba (review + tweak) [feat:gitlark-20261102-register-the-environment-aware-security-] ---
- [ ] [T1] backend/tests/test_main_security_headers_wiring.py — Add a test function `test_middleware_class_source` that asserts the `SecurityHeadersMiddleware` class in `app.user_middleware` is imported from `app.core.security_headers` and not `app.core.security`. VERIFY: `cd backend && python3 -m pytest tests/test_main_security_headers_wiring.py::test_middleware_class_source -q` (cat:test; multifile:no) [feat:gitlark-20261102-register-the-environment-aware-security-]
- [ ] [T1] backend/tests/test_main_security_headers_wiring.py — Add a test function `test_health_permissions_policy_dev` that overrides `get_db` with a stub, sets `settings.environment` to "development", and asserts `GET /health` response contains `Permissions-Policy` header. VERIFY: `cd backend && python3 -m pytest tests/test_main_security_headers_wiring.py::test_health_permissions_policy_dev -q` (cat:test; multifile:no) [feat:gitlark-20261102-register-the-environment-aware-security-]
- [ ] [T1] backend/tests/test_main_security_headers_wiring.py — Add a test function `test_health_no_hsts_dev` that overrides `get_db` with a stub, sets `settings.environment` to "development", and asserts `GET /health` response does NOT contain `Strict-Transport-Security` header. VERIFY: `cd backend && python3 -m pytest tests/test_main_security_headers_wiring.py::test_health_no_hsts_dev -q` (cat:test; multifile:no) [feat:gitlark-20261102-register-the-environment-aware-security-]
- [ ] [T3] backend/app/main.py — Change the import statement on line 13 from `from app.core.security import SecurityHeadersMiddleware` to `from app.core.security_headers import SecurityHeadersMiddleware`. VERIFY: `cd backend && python3 -m pytest tests/test_main_security_headers_wiring.py -q` (cat:refactor; multifile:no) [feat:gitlark-20261102-register-the-environment-aware-security-]
- [ ] [T2] backend/tests/test_main_security_headers_wiring.py — Add a test function `test_health_csp_not_blanket` that overrides `get_db` with a stub, sets `settings.environment` to "development", and asserts `GET /health` response does NOT contain the exact string `Content-Security-Policy: default-src 'self'`. VERIFY: `cd backend && python3 -m pytest tests/test_main_security_headers_wiring.py::test_health_csp_not_blanket -q` (cat:test; multifile:no) [feat:gitlark-20261102-register-the-environment-aware-security-]
- [ ] [T2] backend/tests/test_main_security_headers_wiring.py — Add a test function `test_legacy_middleware_still_importable` that asserts `from app.core.security import SecurityHeadersMiddleware as LegacyMw` succeeds and `LegacyMw is not None`. VERIFY: `cd backend && python3 -m pytest tests/test_main_security_headers_wiring.py::test_legacy_middleware_still_importable -q` (cat:test; multifile:no) [feat:gitlark-20261102-register-the-environment-aware-security-]

# --- 27B-decomposed from roadmap [2026-11-02]: Add a catch-all 404 route to the web router — `web/src/router.ts` lists 21 routes and no ` (review + tweak) [feat:gitlark-20261102-add-a-catch-all-404-route-to-the-web-rou] ---
- [ ] [T1] web/src/pages/NotFoundPage.vue — Create Vue SFC with `<script setup lang="ts">`, `<h1>Page not found</h1>`, `useRoute().fullPath` display, and `<router-link to="/">`. VERIFY: `cd web && npx vue-tsc --noEmit`. (cat:vue; multifile:no) [feat:gitlark-20261102-add-a-catch-all-404-route-to-the-web-rou]
- [ ] [T2] web/src/router.ts — Append `{ path: '/:pathMatch(.*)*', name: 'not-found', component: () => import('@/pages/NotFoundPage.vue'), meta: { requiresAuth: false } }` as the last entry in `routes`. VERIFY: `cd web && npx vue-tsc --noEmit`. (cat:typescript; multifile:no) [feat:gitlark-20261102-add-a-catch-all-404-route-to-the-web-rou]
- [ ] [T3] web/src/pages/__tests__/NotFoundPage.test.ts — Create vitest test asserting `router.resolve('/definitely/not/a/page').name === 'not-found'`, `/dashboard` resolves to its own route, and `NotFoundPage` renders the heading. VERIFY: `cd web && npx vitest run src/pages/__tests__/NotFoundPage.test.ts`. (cat:test; multifile:no) [feat:gitlark-20261102-add-a-catch-all-404-route-to-the-web-rou]

# --- 27B-decomposed from roadmap [2026-11-02]: Set `document.title` per route — `web/src/router.ts:159` `router.afterEach(...)` is an emp (review + tweak) [feat:gitlark-20261102-set-document-title-per-route-web-src-rou] ---
- [ ] [T1] web/src/router.ts — Add `title` string to the `meta` object of the `/dashboard`, `/conversations`, `/plan`, `/pull-requests`, `/review-rules`, `/connector-runs`, `/usage`, `/team`, `/privacy`, `/terms`, and `/welcome` route definitions. VERIFY: `grep -q "title:" web/src/router.ts && grep -c "title:" web/src/router.ts | awk '{exit !($1 >= 11)}'` (cat:typescript; multifile:no) [feat:gitlark-20261102-set-document-title-per-route-web-src-rou]
- [ ] [T2] web/src/router.ts — Replace the empty `router.afterEach` stub with logic that sets `document.title` to `${route.meta.title} - GitLark` if `route.meta.title` exists, otherwise falls back to "GitLark - AI-Powered Code Workspace". VERIFY: `grep -q "document.title" web/src/router.ts && grep -q "afterEach" web/src/router.ts` (cat:typescript; multifile:no) [feat:gitlark-20261102-set-document-title-per-route-web-src-rou]
- [ ] [T3] web/src/__tests__/routerTitles.test.ts — Create a new test file that imports the router, navigates to `/privacy`, `/terms`, and `/dashboard` using `router.push`, awaits `router.isReady()`, and asserts `document.title` matches the expected strings for each route. VERIFY: `cd web && npx vitest run src/__tests__/routerTitles.test.ts --reporter=verbose 2>&1 | grep -q "passed"` (cat:test; multifile:no) [feat:gitlark-20261102-set-document-title-per-route-web-src-rou]
- [ ] [T4] web/src/__tests__/routerTitles.test.ts — Add a test case that navigates to `/` (or a route without a specific title meta) and asserts `document.title` equals the default "GitLark - AI-Powered Code Workspace". VERIFY: `cd web && npx vitest run src/__tests__/routerTitles.test.ts --reporter=verbose 2>&1 | grep -q "default title passed"` (cat:test; multifile:no) [feat:gitlark-20261102-set-document-title-per-route-web-src-rou]

# --- 27B-decomposed from roadmap [2026-11-02]: Add a safe post-login redirect helper — `web/src/router.ts:141-155` sends every unauthenti (review + tweak) [feat:gitlark-20261102-add-a-safe-post-login-redirect-helper-we] ---
- [ ] [T1] web/src/utils/postLoginRedirect.ts — Add `sanitizeRedirect(path: unknown): string | null` that returns a same-origin absolute path only if it starts with a single `/`, is not `//`, contains no backslashes, has no scheme (e.g., `javascript:`), and is ≤512 chars; otherwise returns null. VERIFY: `cd web && npx vitest run src/utils/__tests__/postLoginRedirect.test.ts -t "sanitizeRedirect"`. (cat:typescript; multifile:no) [feat:gitlark-20261102-add-a-safe-post-login-redirect-helper-we]
- [ ] [T1] web/src/utils/postLoginRedirect.ts — Add `stashRedirect(path: string)` that stores the sanitized path in `sessionStorage` under key `gitlark.postLoginRedirect`, wrapped in try/catch to handle storage exceptions. VERIFY: `cd web && npx vitest run src/utils/__tests__/postLoginRedirect.test.ts -t "stashRedirect"`. (cat:typescript; multifile:no) [feat:gitlark-20261102-add-a-safe-post-login-redirect-helper-we]
- [ ] [T1] web/src/utils/postLoginRedirect.ts — Add `consumeRedirect(): string | null` that retrieves the value from `sessionStorage`, clears the key, sanitizes it via `sanitizeRedirect`, and returns the result or null, wrapped in try/catch. VERIFY: `cd web && npx vitest run src/utils/__tests__/postLoginRedirect.test.ts -t "consumeRedirect"`. (cat:typescript; multifile:no) [feat:gitlark-20261102-add-a-safe-post-login-redirect-helper-we]
- [ ] [T2] web/src/utils/__tests__/postLoginRedirect.test.ts — Create test file covering `sanitizeRedirect` accepted paths (valid absolute paths), rejected forms (`//host`, backslashes, `javascript:`, schemes, >512 chars), and edge cases. VERIFY: `cd web && npx vitest run src/utils/__tests__/postLoginRedirect.test.ts -t "sanitizeRedirect"`. (cat:test; multifile:no) [feat:gitlark-20261102-add-a-safe-post-login-redirect-helper-we]
- [ ] [T2] web/src/utils/__tests__/postLoginRedirect.test.ts — Add tests for `stashRedirect` and `consumeRedirect` round-trip: stash a valid path, consume returns it, second consume returns null. VERIFY: `cd web && npx vitest run src/utils/__tests__/postLoginRedirect.test.ts -t "round trip"`. (cat:test; multifile:no) [feat:gitlark-20261102-add-a-safe-post-login-redirect-helper-we]
- [ ] [T2] web/src/utils/__tests__/postLoginRedirect.test.ts — Add tests for throwing `sessionStorage`: mock `sessionStorage.setItem` and `getItem` to throw, verify `stashRedirect` doesn't crash and `consumeRedirect` returns null. VERIFY: `cd web && npx vitest run src/utils/__tests__/postLoginRedirect.test.ts -t "throwing"`. (cat:test; multifile:no) [feat:gitlark-20261102-add-a-safe-post-login-redirect-helper-we]
- [ ] [T3] web/src/router.ts — Modify the unauthenticated redirect logic at lines 141-155 to call `stashRedirect(to.fullPath)` before redirecting to `/`, importing from `@/utils/postLoginRedirect`. VERIFY: `cd web && npx vue-tsc --noEmit`. (cat:typescript; multifile:no) [feat:gitlark-20261102-add-a-safe-post-login-redirect-helper-we]
- [ ] [T3] web/src/pages/AuthCallbackPage.vue — Modify the post-login navigation to call `consumeRedirect()` and navigate to the returned path if non-null, otherwise default to `/dashboard`, importing from `@/utils/postLoginRedirect`. VERIFY: `cd web && npx vue-tsc --noEmit`. (cat:vue; multifile:no) [feat:gitlark-20261102-add-a-safe-post-login-redirect-helper-we]

# --- 27B-decomposed from roadmap [2026-11-02]: Wire the post-login redirect into the auth guard and OAuth callback — depends on `web/src/ (review + tweak) [feat:gitlark-20261102-wire-the-post-login-redirect-into-the-au] ---
- [ ] [T1] web/src/utils/postLoginRedirect.ts — Create module exporting `stashRedirect(path: string)`, `consumeRedirect(): string | null`, and `isValidRedirectPath(path: string): boolean` with in-memory storage and protocol-relative path validation. VERIFY: `cd web && npx vitest run src/utils/__tests__/postLoginRedirect.test.ts`. (cat:typescript; multifile:no) [feat:gitlark-20261102-wire-the-post-login-redirect-into-the-au]
- [ ] [T1] web/src/utils/__tests__/postLoginRedirect.test.ts — Create unit tests verifying `stashRedirect` stores value, `consumeRedirect` returns it and clears storage, and `isValidRedirectPath` rejects `//evil.example` but accepts `/dashboard`. VERIFY: `cd web && npx vitest run src/utils/__tests__/postLoginRedirect.test.ts`. (cat:test; multifile:no) [feat:gitlark-20261102-wire-the-post-login-redirect-into-the-au]
- [ ] [T3] web/src/router.ts — Modify `beforeEach` guard to import `stashRedirect` and call it with `to.fullPath` when `to.meta.requiresAuth` is true and user is not authenticated, before redirecting to `/`. VERIFY: `cd web && npx vitest run src/router.test.ts`. (cat:typescript; multifile:no) [feat:gitlark-20261102-wire-the-post-login-redirect-into-the-au]
- [ ] [T3] web/src/pages/AuthCallbackPage.vue — Replace unconditional `router.push('/dashboard')` at line 64 with `router.push(consumeRedirect() ?? '/dashboard')` and import `consumeRedirect` from `@/utils/postLoginRedirect`. VERIFY: `cd web && npx vitest run src/pages/__tests__/AuthCallbackRedirect.test.ts`. (cat:vue; multifile:no) [feat:gitlark-20261102-wire-the-post-login-redirect-into-the-au]
- [ ] [T2] web/src/pages/__tests__/AuthCallbackRedirect.test.ts — Create test file mocking auth store and router, asserting that with stashed `/dashboard/workspace/abc/pulls` the callback pushes it, with nothing stashed it pushes `/dashboard`, and with stashed `//evil.example` it falls back to `/dashboard`. VERIFY: `cd web && npx vitest run src/pages/__tests__/AuthCallbackRedirect.test.ts`. (cat:test; multifile:no) [feat:gitlark-20261102-wire-the-post-login-redirect-into-the-au]

# --- 27B-decomposed from roadmap [2026-11-02]: Stop logging the stored auth token in the auth store — `web/src/stores/auth.ts:66-90` (`in (review + tweak) [feat:gitlark-20261102-stop-logging-the-stored-auth-token-in-th] ---
- [ ] [T1] web/src/stores/auth.ts — Remove `console.log` calls containing `savedToken.substring(0, 20)` and replace with a boolean presence check log. VERIFY: `cd web && npx vitest run src/stores/__tests__/auth.noTokenLogging.test.ts`. (cat:typescript; multifile:no) [feat:gitlark-20261102-stop-logging-the-stored-auth-token-in-th]
- [ ] [T1] web/src/stores/auth.ts — Remove `console.log`/`console.error` calls that dump `response.data` or full error objects in `initializeAuth`, keeping only status code logging on failure. VERIFY: `cd web && npx vitest run src/stores/__tests__/auth.noTokenLogging.test.ts`. (cat:typescript; multifile:no) [feat:gitlark-20261102-stop-logging-the-stored-auth-token-in-th]
- [ ] [T2] web/src/stores/__tests__/auth.noTokenLogging.test.ts — Add test that mocks `@/services/api` get, sets fake JWT in localStorage, spies on console methods, runs `initializeAuth()`, and asserts no console argument contains 8+ char substring of the token. VERIFY: `cd web && npx vitest run src/stores/__tests__/auth.noTokenLogging.test.ts`. (cat:test; multifile:no) [feat:gitlark-20261102-stop-logging-the-stored-auth-token-in-th]

# --- 27B-decomposed from roadmap [2026-11-02]: Make concurrent 401s share one token refresh — `web/src/services/api.ts:45-60` response in (review + tweak) [feat:gitlark-20261102-make-concurrent-401s-share-one-token-ref] ---
- [ ] [T1] web/src/services/api.ts — Add module-level `refreshInFlight: Promise<boolean> | null` variable and export it for testing. VERIFY: `cd web && npx tsc --noEmit`. (cat:typescript; multifile:no) [feat:gitlark-20261102-make-concurrent-401s-share-one-token-ref]
- [ ] [T2] web/src/services/api.ts — Modify the 401 response interceptor to check `refreshInFlight`; if null, set it to a new Promise that calls `/auth/refresh`, clears tokens on failure, and resolves boolean; if not null, await the existing promise. VERIFY: `cd web && npx tsc --noEmit`. (cat:typescript; multifile:no) [feat:gitlark-20261102-make-concurrent-401s-share-one-token-ref]
- [ ] [T3] web/src/services/api.ts — Update the interceptor logic so that after awaiting `refreshInFlight`, it retries the original request if the refresh succeeded, or rejects if it failed; ensure `refreshInFlight` is cleared in a `finally` block. VERIFY: `cd web && npx tsc --noEmit`. (cat:typescript; multifile:no) [feat:gitlark-20261102-make-concurrent-401s-share-one-token-ref]
- [ ] [T4] web/src/services/__tests__/refreshSingleFlight.test.ts — Create test file with mocked axios adapter that simulates three parallel 401s, asserting exactly one `/auth/refresh` call and successful retries for all three. VERIFY: `cd web && npx vitest run src/services/__tests__/refreshSingleFlight.test.ts`. (cat:test; multifile:no) [feat:gitlark-20261102-make-concurrent-401s-share-one-token-ref]
- [ ] [T5] web/src/services/__tests__/refreshSingleFlight.test.ts — Add test case where the single refresh call fails, asserting that stored tokens are cleared once and all pending requests reject. VERIFY: `cd web && npx vitest run src/services/__tests__/refreshSingleFlight.test.ts`. (cat:test; multifile:no) [feat:gitlark-20261102-make-concurrent-401s-share-one-token-ref]

# --- 27B-decomposed from roadmap [2026-11-02]: Make notification items in `NotificationBell` keyboard-operable — `web/src/components/Noti (review + tweak) [feat:gitlark-20261102-make-notification-items-in-notificationb] ---
- [ ] [T1] web/src/components/__tests__/NotificationBell.keyboard.test.ts — Add test case asserting that an unread notification row has `role="button"` and `tabindex="0"`. VERIFY: `cd web && npx vitest run src/components/__tests__/NotificationBell.keyboard.test.ts -t "unread row has role button and tabindex 0"`. (cat:test; multifile:no) [feat:gitlark-20261102-make-notification-items-in-notificationb]
- [ ] [T1] web/src/components/__tests__/NotificationBell.keyboard.test.ts — Add test case asserting that a read notification row has `tabindex="-1"` and is not tabbable. VERIFY: `cd web && npx vitest run src/components/__tests__/NotificationBell.keyboard.test.ts -t "read row is not tabbable"`. (cat:test; multifile:no) [feat:gitlark-20261102-make-notification-items-in-notificationb]
- [ ] [T1] web/src/components/__tests__/NotificationBell.keyboard.test.ts — Add test case asserting that pressing Enter on an unread row triggers `handleItemClick` exactly once. VERIFY: `cd web && npx vitest run src/components/__tests__/NotificationBell.keyboard.test.ts -t "pressing Enter triggers mark-read once"`. (cat:test; multifile:no) [feat:gitlark-20261102-make-notification-items-in-notificationb]
- [ ] [T1] web/src/components/__tests__/NotificationBell.keyboard.test.ts — Add test case asserting that pressing Space on an unread row triggers `handleItemClick` exactly once. VERIFY: `cd web && npx vitest run src/components/__tests__/NotificationBell.keyboard.test.ts -t "pressing Space triggers mark-read once"`. (cat:test; multifile:no) [feat:gitlark-20261102-make-notification-items-in-notificationb]
- [ ] [T1] web/src/components/__tests__/NotificationBell.keyboard.test.ts — Add test case asserting that the inner "Mark as read" button click does not trigger the row's `handleItemClick` due to `@click.stop`. VERIFY: `cd web && npx vitest run src/components/__tests__/NotificationBell.keyboard.test.ts -t "inner mark-as-read button does not trigger row handler"`. (cat:test; multifile:no) [feat:gitlark-20261102-make-notification-items-in-notificationb]
- [ ] [T3] web/src/components/NotificationBell.vue — Modify the notification item `<div>` at line 132 to include `role="button"`, dynamic `:tabindex` (0 for unread, -1 for read), and `@keydown.enter.prevent` / `@keydown.space.prevent` handlers calling `handleItemClick`. VERIFY: `cd web && npx vitest run src/components/__tests__/NotificationBell.keyboard.test.ts`. (cat:vue; multifile:no) [feat:gitlark-20261102-make-notification-items-in-notificationb]
- [ ] [T3] web/src/components/NotificationBell.vue — Add `:aria-label` to the notification item `<div>` combining `event_type` and `message` properties. VERIFY: `cd web && npx vitest run src/components/__tests__/NotificationBell.keyboard.test.ts`. (cat:vue; multifile:no) [feat:gitlark-20261102-make-notification-items-in-notificationb]
- [ ] [T3] web/src/components/NotificationBell.vue — Ensure the inner "Mark as read" button has `@click.stop` and `@keydown.stop` to prevent event bubbling to the row. VERIFY: `cd web && npx vitest run src/components/__tests__/NotificationBell.keyboard.test.ts`. (cat:vue; multifile:no) [feat:gitlark-20261102-make-notification-items-in-notificationb]

# --- 27B-decomposed from roadmap [2026-11-02]: Give the unlabeled form inputs accessible names — `web/src/pages/SelectRepositoriesPage.vu (review + tweak) [feat:gitlark-20261102-give-the-unlabeled-form-inputs-accessibl] ---
- [ ] [T1] web/src/pages/SelectRepositoriesPage.vue — Add `aria-label="Search repositories"` to the repository search `<input>` element VERIFY: `cd web && npx vitest run src/pages/__tests__/formLabels.a11y.test.ts` (cat:vue; multifile:no) [feat:gitlark-20261102-give-the-unlabeled-form-inputs-accessibl]
- [ ] [T1] web/src/pages/NewConversationPage.vue — Add `for="conversation-title"` to the "Conversation Title (optional)" `<label>` and `id="conversation-title"` to the corresponding `<input>` VERIFY: `cd web && npx vitest run src/pages/__tests__/formLabels.a11y.test.ts` (cat:vue; multifile:no) [feat:gitlark-20261102-give-the-unlabeled-form-inputs-accessibl]
- [ ] [T2] web/src/pages/__tests__/formLabels.a11y.test.ts — Create test file that mounts `SelectRepositoriesPage` and `NewConversationPage` with stubbed router/stores, asserting `getByLabelText('Search repositories')` and `getByLabelText(/Conversation Title/)` resolve to the input elements VERIFY: `cd web && npx vitest run src/pages/__tests__/formLabels.a11y.test.ts` (cat:test; multifile:no) [feat:gitlark-20261102-give-the-unlabeled-form-inputs-accessibl]

# --- 27B-decomposed from roadmap [2026-11-02]: Expose expanded state on the Pull Requests list toggles — `web/src/pages/PullRequestsPage. (review + tweak) [feat:gitlark-20261102-expose-expanded-state-on-the-pull-reques] ---
- [ ] [T1] web/src/pages/PullRequestsPage.vue — Add `aria-expanded="false"` and `aria-controls="pr-panel-${pr.number}"` attributes to the PR header `<button>` element at lines 36-47. VERIFY: `cd web && grep -q 'aria-expanded' src/pages/PullRequestsPage.vue`. (cat:vue; multifile:no) [feat:gitlark-20261102-expose-expanded-state-on-the-pull-reques]
- [ ] [T1] web/src/pages/PullRequestsPage.vue — Update the PR header `<button>` to bind `:aria-expanded="expandedNumber === pr.number ? 'true' : 'false'"` and `:aria-controls="'pr-panel-' + pr.number"` dynamically. VERIFY: `cd web && grep -q ':aria-expanded="expandedNumber === pr.number' src/pages/PullRequestsPage.vue`. (cat:vue; multifile:no) [feat:gitlark-20261102-expose-expanded-state-on-the-pull-reques]
- [ ] [T1] web/src/pages/PullRequestsPage.vue — Add `id="'pr-panel-' + pr.number"` to the expanded panel `<div>` that is revealed when `expandedNumber === pr.number`. VERIFY: `cd web && grep -q "id=\"pr-panel-" src/pages/PullRequestsPage.vue || grep -q ":id=\"'pr-panel-'" src/pages/PullRequestsPage.vue`. (cat:vue; multifile:no) [feat:gitlark-20261102-expose-expanded-state-on-the-pull-reques]
- [ ] [T1] web/src/pages/PullRequestsPage.vue — Add `aria-hidden="true"` to the decorative arrow `<span>` element inside the PR header button. VERIFY: `cd web && grep -q 'aria-hidden="true"' src/pages/PullRequestsPage.vue`. (cat:vue; multifile:no) [feat:gitlark-20261102-expose-expanded-state-on-the-pull-reques]
- [ ] [T2] web/src/pages/__tests__/PullRequestsPage.aria.test.ts — Create new test file mocking the store and component, asserting that initially `aria-expanded` is `"false"` and `aria-controls` matches an existing element ID. VERIFY: `cd web && npx vitest run src/pages/__tests__/PullRequestsPage.aria.test.ts`. (cat:test; multifile:no) [feat:gitlark-20261102-expose-expanded-state-on-the-pull-reques]
- [ ] [T2] web/src/pages/__tests__/PullRequestsPage.aria.test.ts — Add test case that clicks the PR header button and asserts `aria-expanded` becomes `"true"` and the `aria-controls` value matches the `id` of the visible panel element. VERIFY: `cd web && npx vitest run src/pages/__tests__/PullRequestsPage.aria.test.ts`. (cat:test; multifile:no) [feat:gitlark-20261102-expose-expanded-state-on-the-pull-reques]

# --- 27B-decomposed from roadmap [2026-11-02]: Make the Connector Runs error banner a proper alert — `web/src/pages/ConnectorRunsPage.vue (review + tweak) [feat:gitlark-20261102-make-the-connector-runs-error-banner-a-p] ---
- [ ] [T3] web/src/pages/ConnectorRunsPage.vue — Remove `@click="clearError"` from the error banner div and add `role="alert"` attribute. VERIFY: `grep -q 'role="alert"' web/src/pages/ConnectorRunsPage.vue && ! grep -q '@click="clearError"' web/src/pages/ConnectorRunsPage.vue`. (cat:vue; multifile:no) [feat:gitlark-20261102-make-the-connector-runs-error-banner-a-p]
- [ ] [T3] web/src/pages/ConnectorRunsPage.vue — Add `aria-label="Dismiss error"` to the dismiss button inside the error banner and remove the `.stop` modifier from its click handler. VERIFY: `grep -q 'aria-label="Dismiss error"' web/src/pages/ConnectorRunsPage.vue && ! grep -q '@click.stop' web/src/pages/ConnectorRunsPage.vue`. (cat:vue; multifile:no) [feat:gitlark-20261102-make-the-connector-runs-error-banner-a-p]
- [ ] [T2] web/src/pages/__tests__/ConnectorRunsPage.alert.test.ts — Create test file that mocks the store in an error state and asserts the banner element has `role="alert"`. VERIFY: `cd web && npx vitest run src/pages/__tests__/ConnectorRunsPage.alert.test.ts -t "banner has role alert"`. (cat:test; multifile:no) [feat:gitlark-20261102-make-the-connector-runs-error-banner-a-p]
- [ ] [T2] web/src/pages/__tests__/ConnectorRunsPage.alert.test.ts — Add test case that simulates a click on the error message text and asserts the error state persists (is not cleared). VERIFY: `cd web && npx vitest run src/pages/__tests__/ConnectorRunsPage.alert.test.ts -t "clicking message does not clear error"`. (cat:test; multifile:no) [feat:gitlark-20261102-make-the-connector-runs-error-banner-a-p]
- [ ] [T2] web/src/pages/__tests__/ConnectorRunsPage.alert.test.ts — Add test case that simulates a click on the "Dismiss error" button and asserts the error state is cleared. VERIFY: `cd web && npx vitest run src/pages/__tests__/ConnectorRunsPage.alert.test.ts -t "clicking dismiss button clears error"`. (cat:test; multifile:no) [feat:gitlark-20261102-make-the-connector-runs-error-banner-a-p]
