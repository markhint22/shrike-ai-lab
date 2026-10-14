# Grooming proposal — gitlark — 2026-10-14 04:01

## Current Next Steps
```
- [x] [EMERGENCY][T2] web vitest suite is RED — TRIAGE then FIX: decide whether the CODE is wrong (fix the code) or the TEST is stale/flaky (fix or update the test), then get the whole suite green. Failing: [41m[1m FAIL [22m[49m src/components/__tests__/TemporalNavigation.test.ts[2m [ src/components/__tests__/TemporalNavigation.test.ts ][22m
- [x] (already-satisfied in code, implement-verified) [EMERGENCY][T2] backend pytest suite is RED — TRIAGE then FIX: decide whether the CODE is wrong (fix the code) or the TEST is stale/flaky (fix or update the test), then get the whole suite green. Failing: FAILED tests/test_conversation_analytics_summary.py::test_generate_summary_empty_messages;FAILED tests/test_conversation_analytics_summary.py::test_generate_summary_counts_user_and_ai_messages FAILED tests/test_conversation_analytics_summary.py::test_generate_summary_only_user_messages;FAILED tests/test_conversation_analytics_summary.py::test_generate_summary_only_ai_messages
```

## Proposed (LLM re-evaluation — review before applying)
1. Verify `src/components/__tests__/TemporalNavigation.test.ts` passes in isolation and confirm the component logic handles edge cases for temporal navigation.
2. Run `pytest tests/test_conversation_analytics_summary.py -v` to confirm all four previously failing tests pass and check for any new regressions in the analytics module.
3. Add unit tests for `android/app/src/main/java/com/shrikelabs/gitlark/data/repository/AuthRepository.kt` covering successful and failed OAuth token exchange scenarios.
4. Refactor `android/app/src/main/java/com/shrikelabs/gitlark/ui/plans/PlanDetailViewModel.kt` to extract data fetching logic into a separate repository method for better testability.
5. Update `.github/workflows/backend-tests.yml` to explicitly set the Python version from `.python-version` to ensure CI consistency.
