# Grooming proposal — gitlark — 2026-10-28 04:00

## Current Next Steps
```
- [x] [AUTO-SKIP after 203000 tokens with no landing (only 3/4 cycles — caught by spend, not attempt count) — already-done, mis-targeted, or beyond the 27B; review] [EMERGENCY][T2] backend pytest suite is RED — TRIAGE then FIX: decide whether the CODE is wrong (fix the code) or the TEST is stale/flaky (fix or update the test), then get the whole suite green. Failing: FAILED tests/test_repo_analysis_background_task.py::test_save_analysis_fresh_signature Files to read and fix: `backend/tests/test_repo_analysis_background_task.py`  <!-- superseded by recovery decomposition below -->
- [x] (already-done, scout-verified) [T1] backend/app/routers/repo_analysis.py — Ensure `_save_analysis_fresh` uses `async_session_maker()` as an async context manager (`async with`) and calls `session.add(instance)` followed by `await session.commit()`. VERIFY: `cd backend && python -m pytest tests/test_repo_analysis_background_task.py::test_save_analysis_fresh_signature -v` (cat:code-fix; recovery:decomposed)
- [x] [EMERGENCY][T2] web vitest suite is RED — TRIAGE then FIX: decide whether the CODE is wrong (fix the code) or the TEST is stale/flaky (fix or update the test), then get the whole suite green. Failing: [41m[1m FAIL [22m[49m src/components/__tests__/TemporalNavigation.test.ts[2m [ src/components/__tests__/TemporalNavigation.test.ts ][22m
- [x] (already-satisfied in code, implement-verified) [EMERGENCY][T2] backend pytest suite is RED — TRIAGE then FIX: decide whether the CODE is wrong (fix the code) or the TEST is stale/flaky (fix or update the test), then get the whole suite green. Failing: FAILED tests/test_conversation_analytics_summary.py::test_generate_summary_empty_messages;FAILED tests/test_conversation_analytics_summary.py::test_generate_summary_counts_user_and_ai_messages FAILED tests/test_conversation_analytics_summary.py::test_generate_summary_only_user_messages;FAILED tests/test_conversation_analytics_summary.py::test_generate_summary_only_ai_messages
```

## Proposed (LLM re-evaluation — review before applying)
1. Run `cd backend && python -m pytest` to verify the full suite is green and identify any remaining flaky or failing tests for targeted fixes.
2. Run `cd web && npm run test` to verify the frontend vitest suite is green and fix any remaining failures in `src/components/__tests__/`.
3. Add unit tests for `android/app/src/main/java/com/shrikelabs/gitlark/data/repository/AuthRepository.kt` to cover login and token refresh logic.
4. Add unit tests for `android/app/src/main/java/com/shrikelabs/gitlark/data/repository/WorkspaceRepository.kt` to cover workspace creation and listing scenarios.
5. Refactor `backend/app/routers/repo_analysis.py` to extract database session handling into a reusable dependency injection helper to reduce boilerplate.
