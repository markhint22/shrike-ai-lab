# Grooming proposal — gitlark — 2026-10-22 04:00

## Current Next Steps
```
- [x] [EMERGENCY][T2] web vitest suite is RED — TRIAGE then FIX: decide whether the CODE is wrong (fix the code) or the TEST is stale/flaky (fix or update the test), then get the whole suite green. Failing: [41m[1m FAIL [22m[49m src/components/__tests__/TemporalNavigation.test.ts[2m [ src/components/__tests__/TemporalNavigation.test.ts ][22m
- [x] (already-satisfied in code, implement-verified) [EMERGENCY][T2] backend pytest suite is RED — TRIAGE then FIX: decide whether the CODE is wrong (fix the code) or the TEST is stale/flaky (fix or update the test), then get the whole suite green. Failing: FAILED tests/test_conversation_analytics_summary.py::test_generate_summary_empty_messages;FAILED tests/test_conversation_analytics_summary.py::test_generate_summary_counts_user_and_ai_messages FAILED tests/test_conversation_analytics_summary.py::test_generate_summary_only_user_messages;FAILED tests/test_conversation_analytics_summary.py::test_generate_summary_only_ai_messages
```

## Proposed (LLM re-evaluation — review before applying)
1. Verify `src/components/__tests__/TemporalNavigation.test.ts` passes in isolation and confirm the component logic handles edge cases (empty state, invalid dates) to prevent regression.
2. Add unit tests for `backend/app/api/conversation_analytics.py` covering the `generate_summary` function with mixed user/AI message counts to lock in the fix.
3. Refactor `android/app/src/main/java/com/shrikelabs/gitlark/data/repository/WorkspaceRepository.kt` to extract API call logic into a separate interface for easier mocking in future tests.
4. Implement error handling and retry logic in `android/app/src/main/java/com/shrikelabs/gitlark/data/api/GitLarkApi.kt` for network failures during workspace listing.
5. Update `Makefile` to include a `test-android` target that runs the existing `GitHubOAuthTest.kt` suite via Gradle.
