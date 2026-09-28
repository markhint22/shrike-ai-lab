# Grooming proposal — gitlark — 2026-09-28 04:00

## Current Next Steps
```
- [ ] [EMERGENCY][T2] web vitest suite is RED — TRIAGE then FIX: decide whether the CODE is wrong (fix the code) or the TEST is stale/flaky (fix or update the test), then get the whole suite green. Failing: [41m[1m FAIL [22m[49m src/composables/__tests__/useWorkspaceOptions.test.ts[2m > [22museWorkspaceOptions additional tests[2m > [22mpreserves prior options on error
```

## Proposed (LLM re-evaluation — review before applying)
1. Triage and fix the failing test `preserves prior options on error` in `src/composables/__tests__/useWorkspaceOptions.test.ts` to restore a green vitest suite.
2. Add unit tests for `android/app/src/test/java/com/shrikelabs/gitlark/data/repository/WorkspaceRepository.kt` to cover basic CRUD operations.
3. Implement error handling and retry logic in `android/app/src/main/java/com/shrikelabs/gitlark/data/api/GitLarkApi.kt` for network failures.
4. Create a `README.md` section documenting the Android build process and required environment variables.
