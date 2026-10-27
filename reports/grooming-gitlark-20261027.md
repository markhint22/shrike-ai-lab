# Grooming proposal — gitlark — 2026-10-27 04:00

## Current Next Steps
```
- [x] [EMERGENCY][T2] web vitest suite is RED — TRIAGE then FIX: decide whether the CODE is wrong (fix the code) or the TEST is stale/flaky (fix or update the test), then get the whole suite green. Failing: [41m[1m FAIL [22m[49m src/components/__tests__/TemporalNavigation.test.ts[2m [ src/components/__tests__/TemporalNavigation.test.ts ][22m
- [x] (already-satisfied in code, implement-verified) [EMERGENCY][T2] backend pytest suite is RED — TRIAGE then FIX: decide whether the CODE is wrong (fix the code) or the TEST is stale/flaky (fix or update the test), then get the whole suite green. Failing: FAILED tests/test_conversation_analytics_summary.py::test_generate_summary_empty_messages;FAILED tests/test_conversation_analytics_summary.py::test_generate_summary_counts_user_and_ai_messages FAILED tests/test_conversation_analytics_summary.py::test_generate_summary_only_user_messages;FAILED tests/test_conversation_analytics_summary.py::test_generate_summary_only_ai_messages
```

## Proposed (LLM re-evaluation — review before applying)
1. Verify `backend/tests/test_github_app_installation.py` passes and confirm the new test for `get_workspace_installation` is stable.
2. Add unit tests for `android/app/src/main/java/com/shrikelabs/gitlark/data/repository/AuthRepository.kt` to cover OAuth token refresh logic.
3. Implement error handling in `android/app/src/main/java/com/shrikelabs/gitlark/ui/login/LoginViewModel.kt` for network failures during login.
4. Refactor `backend/app/routers/git.py` to extract common GitHub API client logic into a dedicated service module.
5. Add integration tests for the `PlansScreen` and `PlanDetailScreen` in the Android app to verify data binding from `WorkspaceRepository`.
