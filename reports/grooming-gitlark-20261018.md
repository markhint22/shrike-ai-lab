# Grooming proposal — gitlark — 2026-10-18 04:00

## Current Next Steps
```
- [x] [EMERGENCY][T2] web vitest suite is RED — TRIAGE then FIX: decide whether the CODE is wrong (fix the code) or the TEST is stale/flaky (fix or update the test), then get the whole suite green. Failing: [41m[1m FAIL [22m[49m src/components/__tests__/TemporalNavigation.test.ts[2m [ src/components/__tests__/TemporalNavigation.test.ts ][22m
- [x] (already-satisfied in code, implement-verified) [EMERGENCY][T2] backend pytest suite is RED — TRIAGE then FIX: decide whether the CODE is wrong (fix the code) or the TEST is stale/flaky (fix or update the test), then get the whole suite green. Failing: FAILED tests/test_conversation_analytics_summary.py::test_generate_summary_empty_messages;FAILED tests/test_conversation_analytics_summary.py::test_generate_summary_counts_user_and_ai_messages FAILED tests/test_conversation_analytics_summary.py::test_generate_summary_only_user_messages;FAILED tests/test_conversation_analytics_summary.py::test_generate_summary_only_ai_messages
```

## Proposed (LLM re-evaluation — review before applying)
1. Verify `src/components/__tests__/TemporalNavigation.test.ts` passes in isolation and confirm the component logic handles edge cases for temporal navigation.
2. Run `pytest tests/test_conversation_analytics_summary.py -v` to confirm all four previously failing tests are green and stable.
3. Remove `Dockerfile.bak` from the repository root to reduce clutter and potential confusion during container builds.
4. Add a unit test for `android/app/src/main/java/com/shrikelabs/gitlark/data/oauth/GitHubOAuth.kt` to verify OAuth token exchange logic.
5. Create a basic integration test for `android/app/src/main/java/com/shrikelabs/gitlark/data/repository/AuthRepository.kt` using mocked API responses.
6. Update `.github/workflows/node-tests.yml` to explicitly specify the Node.js version and cache dependencies for faster CI runs.
