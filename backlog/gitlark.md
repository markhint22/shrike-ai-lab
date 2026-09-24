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
- [ ] [T1] backend/tests/test_diff_parser.py — Confirm the real, surviving `diff_parser.count_diff_changes` test suite still passes unchanged (proving the deleted duplicate wasn't silently relied on anywhere). VERIFY: `cd backend && python -m pytest tests/test_diff_parser.py -v`. (cat:python; multifile:no) [feat:gitlark-20260922-hunk-summary-dedup]

# --- Claude-decomposed from roadmap [2026-09-22 round 3]: repo_analysis.py has a dead unused import + a dead duplicate local helper; wire the real, tested format_diff_stats into the PR diff UI instead ---
- [ ] [T1] backend/app/routers/repo_analysis.py — Remove the unused `from app.services.diff_stats_format import format_diff_stats` import (line ~26); confirmed via grep it is never called anywhere in this file. VERIFY: `! grep -q "from app.services.diff_stats_format import format_diff_stats" backend/app/routers/repo_analysis.py`. (cat:python; multifile:no) [feat:gitlark-20260922-diff-stats-wiring]
- [ ] [T1] backend/app/routers/repo_analysis.py — Delete the dead `format_diff_stats_helper(additions, deletions) -> dict` function; confirmed via grep it has zero callers anywhere in the repo including its own file. VERIFY: `! grep -q "def format_diff_stats_helper" backend/app/routers/repo_analysis.py`. (cat:python; multifile:no) [feat:gitlark-20260922-diff-stats-wiring]
- [ ] [T1] backend/tests/test_repo_analysis.py — Confirm this test suite still passes unchanged after the removals above (proving neither dead symbol was actually exercised by any real test). VERIFY: `cd backend && python -m pytest tests/test_repo_analysis.py -v`. (cat:python; multifile:no) [feat:gitlark-20260922-diff-stats-wiring]
- [ ] [T2] backend/app/routers/pull_requests.py — Add a `stats_badge: str` field to the `PullRequestFile` model, and import `format_diff_stats` from `app.services.diff_stats_format`. VERIFY: `grep -q "stats_badge: str" backend/app/routers/pull_requests.py && grep -q "from app.services.diff_stats_format import format_diff_stats" backend/app/routers/pull_requests.py`. (cat:python; multifile:no) [feat:gitlark-20260922-diff-stats-wiring]
- [ ] [T2] backend/app/routers/pull_requests.py — In `get_pull_request`, change `files = [PullRequestFile(**f) for f in sliced_files]` to compute `stats_badge=format_diff_stats(f.get("additions", 0), f.get("deletions", 0))` per file and pass it into each `PullRequestFile(...)` construction alongside the existing `**f`. VERIFY: `grep -q "stats_badge=format_diff_stats(" backend/app/routers/pull_requests.py`. (cat:python; multifile:no) [feat:gitlark-20260922-diff-stats-wiring]
- [ ] [T2] backend/tests/test_pull_requests_router.py — Add `test_get_pull_request_includes_stats_badge`: mock a PR file with `additions=5, deletions=3` and assert the response's `files[0]["stats_badge"] == "+5 -3"`. VERIFY: `cd backend && python -m pytest tests/test_pull_requests_router.py::test_get_pull_request_includes_stats_badge -v`. (cat:python; multifile:no) [feat:gitlark-20260922-diff-stats-wiring]
- [ ] [T2] web/src/pages/PullRequestsPage.vue — Render each file's `stats_badge` string next to its filename in the PR file list (following the same small-badge visual pattern already used for `size_label`). VERIFY: `grep -q "stats_badge" web/src/pages/PullRequestsPage.vue`. (cat:frontend; size:S; multifile:no) [feat:gitlark-20260922-diff-stats-wiring]

# --- Claude-decomposed from roadmap [2026-09-22 round 3]: wire ExponentialBackoffRetry into GitHubClient — zero retry logic on any of its ~10 HTTP methods today ---
- [ ] [T2] backend/app/services/github.py — Import `ExponentialBackoffRetry` from `app.services.error_recovery` and add a module-level `_github_retry = ExponentialBackoffRetry(max_retries=3, base_delay_ms=200)` instance for reuse across calls. VERIFY: `grep -q "from app.services.error_recovery import ExponentialBackoffRetry" backend/app/services/github.py`. (cat:python; multifile:no) [feat:gitlark-20260922-github-retry-wiring]
- [ ] [T2] backend/app/services/github.py — Wrap `get_file_content`'s underlying request in `await _github_retry.execute(...)` so a transient network/5xx failure retries instead of immediately raising. VERIFY: `grep -n "async def get_file_content" -A 15 backend/app/services/github.py | grep -q "_github_retry.execute"`. (cat:python; multifile:no) [feat:gitlark-20260922-github-retry-wiring]
- [ ] [T2] backend/app/services/github.py — Wrap `create_or_update_file`'s underlying request in `await _github_retry.execute(...)` for the same reason — this is the method `DispatcherService.dispatch()`'s read-modify-write depends on, where a transient failure today means a silently stuck plan dispatch. VERIFY: `grep -n "async def create_or_update_file" -A 15 backend/app/services/github.py | grep -q "_github_retry.execute"`. (cat:python; multifile:no) [feat:gitlark-20260922-github-retry-wiring]
- [ ] [T2] backend/app/services/github.py — Wrap `get_pr_review_bundle`'s underlying request(s) in the same retry helper — this is the method the webhook auto-review background task depends on, where a transient failure today means a silently dropped PR review. VERIFY: `grep -n "async def get_pr_review_bundle" -A 15 backend/app/services/github.py | grep -q "_github_retry.execute"`. (cat:python; multifile:no) [feat:gitlark-20260922-github-retry-wiring]
- [ ] [T2] backend/tests/test_github_service.py — Add `test_get_file_content_retries_on_transient_failure`: mock the underlying httpx call to raise `httpx.HTTPError` once then succeed, and assert `get_file_content` still returns the successful result (proving the retry actually happens rather than immediately propagating the first failure). VERIFY: `cd backend && python -m pytest tests/test_github_service.py::test_get_file_content_retries_on_transient_failure -v`. (cat:python; multifile:no) [feat:gitlark-20260922-github-retry-wiring]
- [ ] [T1] backend/tests/test_github_service.py — Add `test_get_file_content_gives_up_after_max_retries`: mock the underlying call to always raise, and assert the original exception is still raised after retries are exhausted (proving this doesn't silently swallow a permanent failure). VERIFY: `cd backend && python -m pytest tests/test_github_service.py::test_get_file_content_gives_up_after_max_retries -v`. (cat:python; multifile:no) [feat:gitlark-20260922-github-retry-wiring]

# --- Claude-decomposed from roadmap [2026-09-22 round 3]: wire secret_redaction.redact_secrets into conversation message storage — real, currently-open secret-leak surface ---
- [ ] [T1] backend/app/services/conversation.py — Import `redact_secrets` from `app.services.secret_redaction` near the top of the file, alongside the other service imports. VERIFY: `grep -q "from app.services.secret_redaction import redact_secrets" backend/app/services/conversation.py`. (cat:python; multifile:no) [feat:gitlark-20260922-secret-redaction-wiring]
- [ ] [T1] backend/app/services/conversation.py — In `add_message`, redact the content before it's stored: `content = redact_secrets(content)` as the first line of the method body (before the `message = {...}` dict is built), so both user-pasted and AI-echoed secrets are masked for every role. VERIFY: `grep -n "async def add_message" -A 5 backend/app/services/conversation.py | grep -q "redact_secrets(content)"`. (cat:python; multifile:no) [feat:gitlark-20260922-secret-redaction-wiring]
- [ ] [T2] backend/tests/test_conversation_service.py — Add `test_add_message_redacts_github_token`: call `add_message` with content containing a fake `ghp_` token, then assert the persisted message's `content` does not contain the raw token string and does contain `[REDACTED]`. VERIFY: `cd backend && python -m pytest tests/test_conversation_service.py::test_add_message_redacts_github_token -v`. (cat:python; multifile:no) [feat:gitlark-20260922-secret-redaction-wiring]
- [ ] [T1] backend/tests/test_conversation_service.py — Add `test_add_message_normal_content_unchanged`: call `add_message` with plain content containing no secret patterns, and assert the persisted content is byte-for-byte identical to the input (proving redaction doesn't mangle ordinary messages). VERIFY: `cd backend && python -m pytest tests/test_conversation_service.py::test_add_message_normal_content_unchanged -v`. (cat:python; multifile:no) [feat:gitlark-20260922-secret-redaction-wiring]
- [ ] [T1] backend/tests/test_secret_redaction.py — Confirm the existing `secret_redaction` unit tests still pass unchanged (proving the wiring above didn't require any change to the underlying pure function). VERIFY: `cd backend && python -m pytest tests/test_secret_redaction.py -v`. (cat:python; multifile:no) [feat:gitlark-20260922-secret-redaction-wiring]

# --- Claude-decomposed from roadmap [2026-09-22 round 3]: delete five dead, unmounted Vue conversation-UI components superseded by ConversationDetailPage.vue's own inline rendering ---
- [ ] [T1] web/src/components/ConversationList.vue — Delete this file; confirmed via repo-wide grep it is never imported or referenced anywhere in web/src (router.ts, App.vue, every page, every other component) outside its own definition. VERIFY: `test ! -f web/src/components/ConversationList.vue`. (cat:frontend; size:S; multifile:no) [feat:gitlark-20260922-dead-conversation-components-cleanup]
- [ ] [T1] web/src/components/ConversationPanel.vue — Delete this file; confirmed via repo-wide grep it is never imported or referenced anywhere in web/src outside its own definition. VERIFY: `test ! -f web/src/components/ConversationPanel.vue`. (cat:frontend; size:S; multifile:no) [feat:gitlark-20260922-dead-conversation-components-cleanup]
- [ ] [T1] web/src/components/ConversationActions.vue — Delete this file; confirmed via repo-wide grep it is never imported or referenced anywhere in web/src outside its own definition. VERIFY: `test ! -f web/src/components/ConversationActions.vue`. (cat:frontend; size:S; multifile:no) [feat:gitlark-20260922-dead-conversation-components-cleanup]
- [ ] [T1] web/src/components/MessageActions.vue — Delete this file; confirmed via repo-wide grep it is never imported or referenced anywhere in web/src outside its own definition. VERIFY: `test ! -f web/src/components/MessageActions.vue`. (cat:frontend; size:S; multifile:no) [feat:gitlark-20260922-dead-conversation-components-cleanup]
- [ ] [T1] web/src/components/ConversationAI.vue — Delete this file; confirmed via repo-wide grep it is never imported or referenced anywhere in web/src outside its own definition. VERIFY: `test ! -f web/src/components/ConversationAI.vue`. (cat:frontend; size:S; multifile:no) [feat:gitlark-20260922-dead-conversation-components-cleanup]
- [ ] [T2] web/src/pages/ConversationDetailPage.vue — Confirm the real page still builds and its own three real component imports (`ReactionButtons`, `ReactionCounts`, `ExportMenu`) are unaffected by the deletions above, since none of the five deleted files were ever imported by this page in the first place. VERIFY: `cd web && npx vue-tsc --noEmit -p tsconfig.json`. (cat:frontend; size:S; multifile:no) [feat:gitlark-20260922-dead-conversation-components-cleanup]

# --- Claude-decomposed from roadmap [2026-09-22 round 3]: wire TemporalNavigation.vue into ConversationDetailPage.vue — the backend replay-timeline endpoint it expects already exists ---
- [ ] [T2] web/src/components/TemporalNavigation.vue — Replace the raw `fetch('/api/conversations/${conversationId}/replay-timeline')` call in `loadTimeline()` with the shared `api` client (`import { api } from '@/services/api'`; `const response = await api.get(`/conversations/${props.conversationId}/replay-timeline`)`), so it carries auth headers and respects `VITE_API_URL` like every other real API call in the app. VERIFY: `! grep -q "fetch(" web/src/components/TemporalNavigation.vue`. (cat:frontend; size:S; multifile:no) [feat:gitlark-20260922-temporal-navigation-wiring]
- [ ] [T2] web/src/components/TemporalNavigation.vue — Update the response handling to match `api.get`'s already-unwrapped `.data` shape (drop the old `response.ok`/`response.json()` fetch-style checks; assign `timeline.value = response.data` directly, catching errors via try/catch as the rest of the method already does). VERIFY: `grep -q "timeline.value = response.data" web/src/components/TemporalNavigation.vue`. (cat:frontend; size:S; multifile:no) [feat:gitlark-20260922-temporal-navigation-wiring]
- [ ] [T2] web/src/pages/ConversationDetailPage.vue — Import `TemporalNavigation` from `../components/TemporalNavigation.vue` and mount `<TemporalNavigation :conversation-id="conversationId" @navigate="onTimelineNavigate" @selected-event="onTimelineEvent" />` behind a "View timeline" toggle button, alongside the page's existing `ReactionButtons`/`ReactionCounts`/`ExportMenu` mounts. VERIFY: `grep -q "TemporalNavigation" web/src/pages/ConversationDetailPage.vue`. (cat:frontend; size:M; multifile:no) [feat:gitlark-20260922-temporal-navigation-wiring]
- [ ] [T1] web/src/pages/ConversationDetailPage.vue — Add minimal `onTimelineNavigate(timestamp: Date)` and `onTimelineEvent(event: TimelineEvent)` handler stubs (scroll-to or log for now) so the two events `TemporalNavigation` emits have a real listener instead of an unhandled emit. VERIFY: `grep -q "function onTimelineNavigate" web/src/pages/ConversationDetailPage.vue`. (cat:frontend; size:S; multifile:no) [feat:gitlark-20260922-temporal-navigation-wiring]
- [ ] [T2] web/src/components/__tests__/TemporalNavigation.test.ts — Add a new test file (this component has zero test coverage today) mocking `@/services/api`'s `api.get` to resolve a canned `TimelineData` payload, mounting the component, and asserting `loadTimeline()` populates `timeline` and that the slider/tooltip render without throwing. VERIFY: `cd web && npx vitest run src/components/__tests__/TemporalNavigation.test.ts`. (cat:frontend; size:M; multifile:no) [feat:gitlark-20260922-temporal-navigation-wiring]
- [ ] [T1] web/src/pages/__tests__/ConversationDetailPage.test.ts — Add or extend a test asserting the "View timeline" toggle renders `TemporalNavigation` when clicked (mount the page, trigger the toggle, assert `findComponent(TemporalNavigation).exists()` is true). VERIFY: `cd web && npx vitest run src/pages/__tests__/ConversationDetailPage.test.ts`. (cat:frontend; size:S; multifile:no) [feat:gitlark-20260922-temporal-navigation-wiring]
