# Grooming proposal — gitlark — 2026-10-19 04:00

## Current Next Steps
```
- [x] [EMERGENCY][T2] web vitest suite is RED — TRIAGE then FIX: decide whether the CODE is wrong (fix the code) or the TEST is stale/flaky (fix or update the test), then get the whole suite green. Failing: [41m[1m FAIL [22m[49m src/components/__tests__/TemporalNavigation.test.ts[2m [ src/components/__tests__/TemporalNavigation.test.ts ][22m
- [x] (already-satisfied in code, implement-verified) [EMERGENCY][T2] backend pytest suite is RED — TRIAGE then FIX: decide whether the CODE is wrong (fix the code) or the TEST is stale/flaky (fix or update the test), then get the whole suite green. Failing: FAILED tests/test_conversation_analytics_summary.py::test_generate_summary_empty_messages;FAILED tests/test_conversation_analytics_summary.py::test_generate_summary_counts_user_and_ai_messages FAILED tests/test_conversation_analytics_summary.py::test_generate_summary_only_user_messages;FAILED tests/test_conversation_analytics_summary.py::test_generate_summary_only_ai_messages
```

## Proposed (LLM re-evaluation — review before applying)
1. Verify `src/components/__tests__/TemporalNavigation.test.ts` passes in isolation to confirm the emergency fix is stable before closing the ticket.
2. Run the full backend pytest suite to verify `tests/test_conversation_analytics_summary.py` is green and no regressions were introduced by recent import cleanups.
3. Remove `Dockerfile.bak` from the repository as it is a redundant backup file that clutters the codebase.
4. Consolidate overlapping GitHub Actions workflows (`backend-deploy.yml`, `deploy-backend.yml`, `frontend-deploy.yml`) into a single unified deployment pipeline to reduce maintenance overhead.
5. Add unit tests for `android/app/src/main/java/com/shrikelabs/gitlark/data/repository/AuthRepository.kt` to cover authentication logic gaps identified in the file inventory.
