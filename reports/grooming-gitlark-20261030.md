# Grooming proposal — gitlark — 2026-10-30 04:00

## Current Next Steps
```
- [x] [AUTO-SKIP after 203000 tokens with no landing (only 3/4 cycles — caught by spend, not attempt count) — already-done, mis-targeted, or beyond the 27B; review] [EMERGENCY][T2] backend pytest suite is RED — TRIAGE then FIX: decide whether the CODE is wrong (fix the code) or the TEST is stale/flaky (fix or update the test), then get the whole suite green. Failing: FAILED tests/test_repo_analysis_background_task.py::test_save_analysis_fresh_signature Files to read and fix: `backend/tests/test_repo_analysis_background_task.py`  <!-- superseded by recovery decomposition below -->
- [x] (already-done, scout-verified) [T1] backend/app/routers/repo_analysis.py — Ensure `_save_analysis_fresh` uses `async_session_maker()` as an async context manager (`async with`) and calls `session.add(instance)` followed by `await session.commit()`. VERIFY: `cd backend && python -m pytest tests/test_repo_analysis_background_task.py::test_save_analysis_fresh_signature -v` (cat:code-fix; recovery:decomposed)
- [x] [EMERGENCY][T2] web vitest suite is RED — TRIAGE then FIX: decide whether the CODE is wrong (fix the code) or the TEST is stale/flaky (fix or update the test), then get the whole suite green. Failing: [41m[1m FAIL [22m[49m src/components/__tests__/TemporalNavigation.test.ts[2m [ src/components/__tests__/TemporalNavigation.test.ts ][22m
- [x] (already-satisfied in code, implement-verified) [EMERGENCY][T2] backend pytest suite is RED — TRIAGE then FIX: decide whether the CODE is wrong (fix the code) or the TEST is stale/flaky (fix or update the test), then get the whole suite green. Failing: FAILED tests/test_conversation_analytics_summary.py::test_generate_summary_empty_messages;FAILED tests/test_conversation_analytics_summary.py::test_generate_summary_counts_user_and_ai_messages FAILED tests/test_conversation_analytics_summary.py::test_generate_summary_only_user_messages;FAILED tests/test_conversation_analytics_summary.py::test_generate_summary_only_ai_messages
```

## Proposed (LLM re-evaluation — review before applying)
1. Verify `backend/tests/test_repo_analysis_background_task.py::test_save_analysis_fresh_signature` passes and remove the stale `[EMERGENCY]` marker from the backlog if green.
2. Verify `src/components/__tests__/TemporalNavigation.test.ts` passes and confirm the web vitest suite is fully green.
3. Verify `backend/tests/test_conversation_analytics_summary.py` passes for all four listed test cases.
4. Add unit tests for the new environment-aware token encryption key validation logic in the backend.
5. Add unit tests for the repository context value sanitization function to ensure prompt injection prevention works.
6. Update `README.md` and `QUICKSTART.md` to reflect the new Android app structure and setup instructions.
