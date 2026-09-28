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
- [ ] [T1] backend/app/services/hunk_summary.py — Remove the file containing the dead `summarize_diff` implementation. VERIFY: `test -f backend/app/services/hunk_summary.py && echo "FAIL" || echo "PASS"`. (cat:refactor; multifile:no) [feat:gitlark-20260928-delete-hunk-summary-py-a-dead-unwired-du]
- [ ] [T2] backend/tests/test_hunk_summary.py — Remove the test file for the deleted service. VERIFY: `test -f backend/tests/test_hunk_summary.py && echo "FAIL" || echo "PASS"`. (cat:test; multifile:no) [feat:gitlark-20260928-delete-hunk-summary-py-a-dead-unwired-du]
- [ ] [T3] backend/app/services/diff_parser.py — Verify `count_diff_changes` is the sole active diff counter and add a docstring note confirming it as the single shared implementation. VERIFY: `grep -q "single shared implementation" backend/app/services/diff_parser.py && echo "PASS" || echo "FAIL"`. (cat:python; multifile:no) [feat:gitlark-20260928-delete-hunk-summary-py-a-dead-unwired-du]
- [ ] [T4] backend/app — Ensure no remaining imports of `hunk_summary` exist in the codebase. VERIFY: `grep -r "from.*hunk_summary import\|import hunk_summary" backend/app/ && echo "FAIL" || echo "PASS"`. (cat:refactor; multifile:yes) [feat:gitlark-20260928-delete-hunk-summary-py-a-dead-unwired-du]
- [ ] [T5] backend/tests — Ensure no remaining test imports of `hunk_summary` exist. VERIFY: `grep -r "from.*hunk_summary import\|import hunk_summary" backend/tests/ && echo "FAIL" || echo "PASS"`. (cat:test; multifile:yes) [feat:gitlark-20260928-delete-hunk-summary-py-a-dead-unwired-du]

# --- 27B-decomposed from roadmap [2026-09-28]: **`repo_analysis.py` imports a dead diff-stats function and defines an equally-dead duplic (review + tweak) [feat:gitlark-20260928-repo-analysis-py-imports-a-dead-diff-sta] ---
- [ ] [T1] backend/app/services/diff_stats_format.py — Ensure `format_diff_stats` exists and returns a string badge (e.g., "+5 -3") handling None/negatives; add unit test `test_format_diff_stats_badge`. VERIFY: `pytest backend/tests/test_diff_stats_format.py::test_format_diff_stats_badge -v`. (cat:python; multifile:no) [feat:gitlark-20260928-repo-analysis-py-imports-a-dead-diff-sta]
- [ ] [T2] backend/app/routers/repo_analysis.py — Remove unused import `from app.services.diff_stats_format import format_diff_stats` at line 26. VERIFY: `grep -q "from app.services.diff_stats_format import format_diff_stats" backend/app/routers/repo_analysis.py && exit 1 || exit 0`. (cat:refactor; multifile:no) [feat:gitlark-20260928-repo-analysis-py-imports-a-dead-diff-sta]
- [ ] [T3] backend/app/routers/repo_analysis.py — Remove dead local function `format_diff_stats_helper` definition starting at line 376. VERIFY: `grep -q "def format_diff_stats_helper" backend/app/routers/repo_analysis.py && exit 1 || exit 0`. (cat:refactor; multifile:no) [feat:gitlark-20260928-repo-analysis-py-imports-a-dead-diff-sta]
- [ ] [T4] backend/app/routers/pull_requests.py — Add computed field `diff_badge` to `PullRequestFile` schema using `format_diff_stats` from `app.services.diff_stats_format`. VERIFY: `grep -q "diff_badge" backend/app/routers/pull_requests.py && grep -q "format_diff_stats" backend/app/routers/pull_requests.py`. (cat:python; multifile:no) [feat:gitlark-20260928-repo-analysis-py-imports-a-dead-diff-sta]
- [ ] [T5] web/src/components/PullRequestsPage.vue — Render `file.diff_badge` in the file list template next to filename. VERIFY: `grep -q "diff_badge" web/src/components/PullRequestsPage.vue`. (cat:vue; multifile:no) [feat:gitlark-20260928-repo-analysis-py-imports-a-dead-diff-sta]

# --- 27B-decomposed from roadmap [2026-09-28]: **Wire `ExponentialBackoffRetry` into `GitHubClient` — every one of its ~10 HTTP methods h (review + tweak) [feat:gitlark-20260928-wire-exponentialbackoffretry-into-github] ---
- [ ] [T1] backend/app/services/error_recovery.py — Add `is_retryable_error` static method to `ExponentialBackoffRetry` that returns True for `httpx.HTTPStatusError` with status >= 500 or `httpx.RequestError`. VERIFY: pytest backend/tests/test_error_recovery.py::test_is_retryable_error -v. (cat:python; multifile:no) [feat:gitlark-20260928-wire-exponentialbackoffretry-into-github]
- [ ] [T2] backend/app/services/error_recovery.py — Add `execute_with_httpx` method to `ExponentialBackoffRetry` that wraps an async callable, catching retryable errors and applying backoff/jitter before re-raising on final failure. VERIFY: pytest backend/tests/test_error_recovery.py::test_execute_with_httpx_retries -v. (cat:python; multifile:no) [feat:gitlark-20260928-wire-exponentialbackoffretry-into-github]
- [ ] [T3] backend/app/services/github.py — Import `ExponentialBackoffRetry` and wrap the `httpx` call in `get_file_content` with `await ExponentialBackoffRetry().execute_with_httpx(...)` to handle transient 5xx/network errors. VERIFY: grep -q "execute_with_httpx" backend/app/services/github.py && pytest backend/tests/test_github_client.py::test_get_file_content_retries_on_503 -v. (cat:python; multifile:no) [feat:gitlark-20260928-wire-exponentialbackoffretry-into-github]
- [ ] [T3] backend/app/services/github.py — Wrap the `httpx` call in `create_or_update_file` with `await ExponentialBackoffRetry().execute_with_httpx(...)` to ensure file operations retry on transient failures. VERIFY: grep -q "execute_with_httpx" backend/app/services/github.py && pytest backend/tests/test_github_client.py::test_create_or_update_file_retries_on_502 -v. (cat:python; multifile:no) [feat:gitlark-20260928-wire-exponentialbackoffretry-into-github]
- [ ] [T3] backend/app/routers/github_webhook.py — In `_review_and_comment`, wrap the `GitHubClient` method calls with `ExponentialBackoffRetry().execute_with_httpx(...)` to prevent silent drop of reviews during transient GitHub outages. VERIFY: grep -q "execute_with_httpx" backend/app/routers/github_webhook.py && pytest backend/tests/test_github_webhook.py::test_review_retries_on_transient_error -v. (cat:python; multifile:no) [feat:gitlark-20260928-wire-exponentialbackoffretry-into-github]
- [ ] [T3] backend/app/services/dispatcher.py — In `DispatcherService.dispatch`, wrap the `get_file_content` and `create_or_update_file` calls with `ExponentialBackoffRetry().execute_with_httpx(...)` to prevent stuck dispatches on network blips. VERIFY: grep -q "execute_with_httpx" backend/app/services/dispatcher.py && pytest backend/tests/test_dispatcher.py::test_dispatch_retries_on_network_error -v. (cat:python; multifile:no) [feat:gitlark-20260928-wire-exponentialbackoffretry-into-github]
- [ ] [T4] backend/app/services/github.py — Refactor all remaining `httpx` calls in `GitHubClient` methods (e.g., `create_issue_comment`, `get_pull_request`) to use the new `execute_with_httpx` wrapper for consistent retry behavior. VERIFY: grep -c "execute_with_httpx" backend/app/services/github.py | awk '{exit $1 < 5}' && pytest backend/tests/test_github_client.py -v. (cat:refactor; multifile:no) [feat:gitlark-20260928-wire-exponentialbackoffretry-into-github]
- [ ] [T2] backend/tests/test_error_recovery.py — Add unit tests for `is_retryable_error` covering 500, 503, 404, and `httpx.RequestError` cases to ensure correct classification of transient vs permanent failures. VERIFY: pytest backend/tests/test_error_recovery.py::test_is_retryable_error -v. (cat:test; multifile:no) [feat:gitlark-20260928-wire-exponentialbackoffretry-into-github]
- [ ] [T2] backend/tests/test_github_client.py — Add integration tests mocking `httpx` to return 503 then 200, verifying that `get_file_content` and `create_or_update_file` succeed after retry. VERIFY: pytest backend/tests/test_github_client.py::test_retry_success -v. (cat:test; multifile:no) [feat:gitlark-20260928-wire-exponentialbackoffretry-into-github]
- [ ] [T1] backend/app/services/error_recovery.py — Ensure `ExponentialBackoffRetry` configuration allows overriding max_retries and base_delay via constructor arguments for specific high-latency endpoints. VERIFY: python -c "from app.services.error_recovery import ExponentialBackoffRetry; r = ExponentialBackoffRetry(max_retries=5); assert r.max_retries == 5". (cat:python; multifile:no) [feat:gitlark-20260928-wire-exponentialbackoffretry-into-github]

# --- 27B-decomposed from roadmap [2026-09-28]: **Wire `secret_redaction.redact_secrets` into conversation message storage — a real, curre (review + tweak) [feat:gitlark-20260928-wire-secret-redaction-redact-secrets-int] ---
- [ ] [T1] backend/app/services/conversation.py — Import `redact_secrets` from `backend.app.services.secret_redaction` at the top of the file. VERIFY: `grep -q "from backend.app.services.secret_redaction import redact_secrets" backend/app/services/conversation.py`. (cat:python; multifile:no) [feat:gitlark-20260928-wire-secret-redaction-redact-secrets-int]
- [ ] [T1] backend/app/services/conversation.py — Modify `add_message` to call `redact_secrets(content)` on the `content` argument before appending it to the `conversation.messages` list for both `user` and `assistant` roles. VERIFY: `grep -q "redact_secrets(content)" backend/app/services/conversation.py`. (cat:python; multifile:no) [feat:gitlark-20260928-wire-secret-redaction-redact-secrets-int]
- [ ] [T2] backend/tests/test_conversation_redaction.py — Create a new test file that mocks the database session and asserts that `add_message` stores redacted content when input contains a mock GitHub PAT. VERIFY: `pytest backend/tests/test_conversation_redaction.py -v`. (cat:test; multifile:no) [feat:gitlark-20260928-wire-secret-redaction-redact-secrets-int]
- [ ] [T2] backend/tests/test_conversation_redaction.py — Add a test case verifying that `add_message` redacts AWS access keys in assistant messages. VERIFY: `pytest backend/tests/test_conversation_redaction.py::test_add_message_redacts_aws_keys -v`. (cat:test; multifile:no) [feat:gitlark-20260928-wire-secret-redaction-redact-secrets-int]
- [ ] [T2] backend/tests/test_conversation_redaction.py — Add a test case verifying that `add_message` redacts Bearer tokens in user messages. VERIFY: `pytest backend/tests/test_conversation_redaction.py::test_add_message_redacts_bearer_tokens -v`. (cat:test; multifile:no) [feat:gitlark-20260928-wire-secret-redaction-redact-secrets-int]
- [ ] [T3] backend/app/services/conversation.py — Ensure the `ConversationExportService` or any downstream consumer of `conversation.messages` does not bypass the redaction by verifying no direct DB access to raw content exists in export logic. VERIFY: `grep -r "raw_content" backend/app/services/ | grep -v "redact" | wc -l` returns 0. (cat:python; multifile:no) [feat:gitlark-20260928-wire-secret-redaction-redact-secrets-int]
- [ ] [T4] backend/app/routers/conversations.py — Verify that the API endpoint returning conversation history does not strip redaction or expose raw fields, ensuring the redacted content from `add_message` is what is returned. VERIFY: `pytest backend/tests/test_conversation_api_redaction.py -v`. (cat:endpoint; multifile:no) [feat:gitlark-20260928-wire-secret-redaction-redact-secrets-int]
- [ ] [T5] backend/app/services/audit_service.py — Confirm that audit logs capturing conversation events use the same redacted content source, preventing secret leakage in audit trails. VERIFY: `grep -q "redact_secrets" backend/app/services/audit_service.py || echo "Audit service relies on model state which is now redacted"`. (cat:python; multifile:no) [feat:gitlark-20260928-wire-secret-redaction-redact-secrets-int]
