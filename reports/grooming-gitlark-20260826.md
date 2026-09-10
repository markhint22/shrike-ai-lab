# Grooming proposal — gitlark — 2026-08-26 04:00

## Deterministically stale (target file already gone — safe to drop)
```
1. ~~Delete backend/app/services/ai_agent_service.py (0 external refs, 0% cov) — grep-confirm no import first, then re-run backend pytest (must stay 196 passed).~~ ✅ Done 2026-08-25
2. ~~Delete backend/app/services/code_review_agent.py (0 external refs).~~ ✅ Done 2026-08-25
3. ~~Delete backend/app/services/github_integration_service.py (the live one is github.py).~~ ✅ Done 2026-08-25
4. ~~Delete backend/app/services/realtime_update_service.py (the live one is realtime_service.py).~~ ✅ Done 2026-08-25
5. ~~Delete backend/app/services/feature_flags_service.py (the live one is feature_flags.py).~~ ✅ Done 2026-08-25
6. ~~Delete backend/app/services/claude_agent.py (the live one is claude.py).~~ ✅ Done 2026-08-25
7. ~~Delete backend/app/services/conversation_analytics.py (0 refs, 0% cov).~~ ✅ Done 2026-08-25
```

## Current Next Steps
```
1. ~~Delete backend/app/services/ai_agent_service.py (0 external refs, 0% cov) — grep-confirm no import first, then re-run backend pytest (must stay 196 passed).~~ ✅ Done 2026-08-25
2. ~~Delete backend/app/services/code_review_agent.py (0 external refs).~~ ✅ Done 2026-08-25
3. ~~Delete backend/app/services/github_integration_service.py (the live one is github.py).~~ ✅ Done 2026-08-25
4. ~~Delete backend/app/services/realtime_update_service.py (the live one is realtime_service.py).~~ ✅ Done 2026-08-25
5. ~~Delete backend/app/services/feature_flags_service.py (the live one is feature_flags.py).~~ ✅ Done 2026-08-25
6. ~~Delete backend/app/services/claude_agent.py (the live one is claude.py).~~ ✅ Done 2026-08-25
7. ~~Delete backend/app/services/conversation_analytics.py (0 refs, 0% cov).~~ ✅ Done 2026-08-25
8. ~~Add unit tests for backend/app/services/repo_analyzer.py only (47%; core feature).~~ ✅ Done 2026-08-25
9. ~~Add unit tests for backend/app/services/code_review.py only (57%).~~ ✅ Done 2026-08-25
12. Add error handling for OAuth callback failures in backend/app/routers/github.py and auth.py.
13. Reconcile the two coverage gates: root pytest.ini enforces --cov-fail-under=80 but backend/pytest.ini doesn't; pick the canonical config.
14. Pin/relax deps so they build on Python 3.14 (system default), or document the 3.12 requirement in the backend README.
- [ ] Add integration tests for the conversation streaming endpoint in backend/app/routers/conversations.py. (DEPRIORITIZED: too large for the current slow model in one budget — revisit after the model upgrade or split it manually.)
```

## Proposed (LLM re-evaluation — review before applying)
1. Add error handling for OAuth callback failures in backend/app/routers/github.py and auth.py.
2. Reconcile the two coverage gates: root pytest.ini enforces --cov-fail-under=80 but backend/pytest.ini doesn't; pick the canonical config.
3. Pin/relax deps so they build on Python 3.14 (system default), or document the 3.12 requirement in the backend README.
4. Add integration tests for the conversation streaming endpoint in backend/app/routers/conversations.py.
5. Implement unit tests for backend/app/services/repo_analyzer.py with mocked async operations.
6. Add comprehensive unit tests for backend/app/services/code_review.py with mocked async operations.
7. Update backend/README.md with clear instructions for setting up Python 3.12 environment.
