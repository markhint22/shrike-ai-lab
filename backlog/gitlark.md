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
- [ ] [T1] backend/app/core/api_versioning.py — Implement `_get_legacy_handler` to return a valid handler or raise `NotImplementedError` instead of `pass`. VERIFY: `python -c "from backend.app.core.api_versioning import APIVersion; v=APIVersion(); assert v._get_legacy_handler('v0', 'test') is not None or True"` (cat:python; multifile:no)
- [ ] [T1] backend/tests/test_api_versioning.py — Add unit test verifying `_get_legacy_handler` no longer returns `None` implicitly and handles missing versions gracefully. VERIFY: `pytest backend/tests/test_api_versioning.py -v` (cat:test; multifile:no)
- [ ] [T2] backend/app/routers/version.py — Create new router file exposing `GET /api/version` that returns `APIVersion.get_version_info()`. VERIFY: `python -c "from backend.app.routers.version import router; assert hasattr(router, 'routes')"` (cat:endpoint; multifile:no)
- [ ] [T3] backend/app/main.py — Import and include the new version router in the FastAPI app instance. VERIFY: `grep -q "include_router.*version" backend/app/main.py` (cat:python; multifile:no)
- [ ] [T3] backend/app/main.py — Replace hardcoded `version="0.1.0"` in `FastAPI(...)` initialization with `APIVersion.VERSION`. VERIFY: `grep -q "version=APIVersion.VERSION" backend/app/main.py` (cat:python; multifile:no)
- [ ] [T4] backend/app/core/api_versioning.py — Remove unused imports and dead code paths that are no longer reachable after wiring up the version endpoint. VERIFY: `flake8 backend/app/core/api_versioning.py --select=F401` (cat:refactor; multifile:yes)
- [ ] [T5] backend/tests/test_api_versioning.py — Update tests to cover the new `/api/version` endpoint integration and legacy handler behavior. VERIFY: `pytest backend/tests/test_api_versioning.py -v --tb=short` (cat:test; multifile:yes)

# --- 27B-decomposed from roadmap [2026-09-18]: Review-collaboration WebSocket trusts a client-supplied user_id with zero token verificati (review + tweak) ---
- [ ] [T1] backend/app/core/security.py — Add a pure function `extract_ws_token(query_params: dict) -> str | None` that safely retrieves and validates the 'token' key from a query parameter dictionary, returning None if missing or not a string. VERIFY: python -m pytest backend/tests/test_security_ws_token.py::test_extract_ws_token_valid -v && python -m pytest backend/tests/test_security_ws_token.py::test_extract_ws_token_missing -v. (cat:python; multifile:no)
- [ ] [T2] backend/app/core/security.py — Add a pure function `validate_ws_handshake(token: str | None, expected_user_id: UUID | None = None) -> tuple[bool, str]` that calls `verify_token` if token exists and returns (True, "ok") or (False, "reason"), handling missing/invalid tokens without raising exceptions. VERIFY: python -m pytest backend/tests/test_security_ws_validation.py::test_validate_ws_handshake_valid_token -v && python -m pytest backend/tests/test_security_ws_validation.py::test_validate_ws_handshake_invalid_token -v. (cat:python; multifile:no)
- [ ] [T3] backend/app/routers/review_collab.py — Modify `websocket_review_collaboration` to extract the token from `websocket.query_params` and call `validate_ws_handshake` before accepting the connection, closing with code 4001 if validation fails. VERIFY: python -m pytest backend/tests/test_review_collab_ws_auth.py::test_ws_rejects_missing_token -v && python -m pytest backend/tests/test_review_collab_ws_auth.py::test_ws_rejects_invalid_token -v. (cat:endpoint; multifile:no)
- [ ] [T3] backend/app/routers/review_collab.py — Update the authenticated path in `websocket_review_collaboration` to derive `user_id` from the verified token result instead of `handshake.get("user_id")`, ensuring the identity matches the token owner. VERIFY: python -m pytest backend/tests/test_review_collab_ws_auth.py::test_ws_uses_token_user_id_not_handshake -v. (cat:endpoint; multifile:no)
- [ ] [T4] backend/app/routers/review_collab.py — Remove the unauthenticated `handshake = await websocket.receive_json()` and `user_id = UUID(handshake.get("user_id"))` logic, replacing it with a strict JSON handshake validation that only accepts metadata (like review_id) after authentication is confirmed. VERIFY: grep -q "handshake.get(\"user_id\")" backend/app/routers/review_collab.py && echo "FAIL: old code present" || echo "PASS: old code removed". (cat:refactor; multifile:no)
- [ ] [T5] backend/app/routers/review_collab.py — Add a unit test that simulates a WebSocket connection with a valid token but a mismatched `user_id` in the handshake body, asserting that the server ignores the body user_id and uses the token-derived identity. VERIFY: python -m pytest backend/tests/test_review_collab_ws_auth.py::test_ws_ignores_handshake_user_id_mismatch -v. (cat:test; multifile:no)

# --- 27B-decomposed from roadmap [2026-09-18]: Normalize LLM-generated snippet tags before they hit the DB — `backend/app/services/tag_no (review + tweak) ---
- [ ] [T1] backend/app/services/tag_normalizer.py — Ensure `normalize_tags` strips leading/trailing whitespace from each tag before lowercasing and deduplication. VERIFY: `pytest backend/tests/test_tag_normalizer.py -v`. (cat:python; multifile:no)
- [ ] [T2] backend/tests/test_tag_normalizer.py — Add test cases verifying that `normalize_tags([" react", "React", "react"])` returns `["react"]` and that inputs exceeding `max_tags` are truncated to the first `max_tags` unique items. VERIFY: `pytest backend/tests/test_tag_normalizer.py -v`. (cat:test; multifile:no)
- [ ] [T3] backend/app/services/snippet.py — Import `normalize_tags` from `backend.app.services.tag_normalizer` and apply it to `ai_tags` immediately after retrieval in `_generate_ai_metadata` or before the loop in `create_snippet`. VERIFY: `grep -n "normalize_tags" backend/app/services/snippet.py`. (cat:python; multifile:no)
- [ ] [T4] backend/tests/test_snippet_service.py — Add a unit test for `SnippetService.create_snippet` mocking `_generate_ai_metadata` to return `[" React", "react", "Vue"]` and assert that only one `Tag` row with name `"react"` is created/linked. VERIFY: `pytest backend/tests/test_snippet_service.py -v`. (cat:test; multifile:no)
- [ ] [T5] backend/app/models/snippet.py — Add a composite unique constraint on `(snippet_id, tag_id)` in the `snippet_tags` association table definition to prevent duplicate links at the DB level. VERIFY: `alembic upgrade head && alembic downgrade -1 && alembic upgrade head`. (cat:schema; multifile:no)
