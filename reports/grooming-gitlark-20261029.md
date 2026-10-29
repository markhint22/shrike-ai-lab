# Grooming proposal — gitlark — 2026-10-29 04:00

## Current Next Steps
```
- [x] [AUTO-SKIP after 203000 tokens with no landing (only 3/4 cycles — caught by spend, not attempt count) — already-done, mis-targeted, or beyond the 27B; review] [EMERGENCY][T2] backend pytest suite is RED — TRIAGE then FIX: decide whether the CODE is wrong (fix the code) or the TEST is stale/flaky (fix or update the test), then get the whole suite green. Failing: FAILED tests/test_repo_analysis_background_task.py::test_save_analysis_fresh_signature Files to read and fix: `backend/tests/test_repo_analysis_background_task.py`  <!-- superseded by recovery decomposition below -->
- [x] (already-done, scout-verified) [T1] backend/app/routers/repo_analysis.py — Ensure `_save_analysis_fresh` uses `async_session_maker()` as an async context manager (`async with`) and calls `session.add(instance)` followed by `await session.commit()`. VERIFY: `cd backend && python -m pytest tests/test_repo_analysis_background_task.py::test_save_analysis_fresh_signature -v` (cat:code-fix; recovery:decomposed)
- [x] [EMERGENCY][T2] web vitest suite is RED — TRIAGE then FIX: decide whether the CODE is wrong (fix the code) or the TEST is stale/flaky (fix or update the test), then get the whole suite green. Failing: [41m[1m FAIL [22m[49m src/components/__tests__/TemporalNavigation.test.ts[2m [ src/components/__tests__/TemporalNavigation.test.ts ][22m
- [x] (already-satisfied in code, implement-verified) [EMERGENCY][T2] backend pytest suite is RED — TRIAGE then FIX: decide whether the CODE is wrong (fix the code) or the TEST is stale/flaky (fix or update the test), then get the whole suite green. Failing: FAILED tests/test_conversation_analytics_summary.py::test_generate_summary_empty_messages;FAILED tests/test_conversation_analytics_summary.py::test_generate_summary_counts_user_and_ai_messages FAILED tests/test_conversation_analytics_summary.py::test_generate_summary_only_user_messages;FAILED tests/test_conversation_analytics_summary.py::test_generate_summary_only_ai_messages
```

## Proposed (LLM re-evaluation — review before applying)
1. Run `cd backend && python -m pytest` to verify the full suite is green after the recent dispatcher and analysis fixes; if any tests remain red, triage and fix the specific failing test or code logic.
2. Run `cd web && npm run test` to verify the frontend vitest suite is green after the TemporalNavigation fix; if any tests remain red, triage and fix the specific failing component or mock.
3. Refactor `backend/app/services/dispatcher.py` to extract the `validate_task_path` logic into a separate utility module if it exceeds 50 lines, ensuring the main dispatch flow remains under 15 minutes of cognitive load for future maintenance.
4. Add unit tests for `backend/app/services/dispatcher.py::DispatcherService.dispatch` covering edge cases where the task path is invalid or the session context manager fails, ensuring robust error handling.
5. Create a `Makefile` target `make test-all` that runs both backend pytest and web vitest suites in parallel to streamline local verification before committing.
