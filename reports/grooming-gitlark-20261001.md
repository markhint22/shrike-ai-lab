# Grooming proposal — gitlark — 2026-10-01 04:00

## Current Next Steps
```
- [x] [EMERGENCY][T2] web vitest suite is RED — TRIAGE then FIX: decide whether the CODE is wrong (fix the code) or the TEST is stale/flaky (fix or update the test), then get the whole suite green. Failing: [41m[1m FAIL [22m[49m src/components/__tests__/TemporalNavigation.test.ts[2m [ src/components/__tests__/TemporalNavigation.test.ts ][22m
- [x] (already-satisfied in code, implement-verified) [EMERGENCY][T2] backend pytest suite is RED — TRIAGE then FIX: decide whether the CODE is wrong (fix the code) or the TEST is stale/flaky (fix or update the test), then get the whole suite green. Failing: FAILED tests/test_conversation_analytics_summary.py::test_generate_summary_empty_messages;FAILED tests/test_conversation_analytics_summary.py::test_generate_summary_counts_user_and_ai_messages FAILED tests/test_conversation_analytics_summary.py::test_generate_summary_only_user_messages;FAILED tests/test_conversation_analytics_summary.py::test_generate_summary_only_ai_messages
```

## Proposed (LLM re-evaluation — review before applying)
1. Verify `web/src/utils/apiPathGuard.test.ts` passes and ensure the mocked axios setup is stable for future runs.
2. Confirm the `DispatchWriteError` handler registration in the FastAPI app is correctly wired and tested.
3. Add unit tests for `android/app/src/main/java/com/shrikelabs/gitlark/data/repository/AuthRepository.kt` to cover OAuth token exchange logic.
4. Implement basic input validation and error handling in `android/app/src/main/java/com/shrikelabs/gitlark/ui/login/LoginViewModel.kt`.
5. Create a CI workflow step to run Android unit tests (`android/app/src/test/...`) alongside existing backend/frontend tests.
