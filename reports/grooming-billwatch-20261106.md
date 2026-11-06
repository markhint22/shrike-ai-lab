# Grooming proposal — billwatch — 2026-11-06 04:00

## Current Next Steps
```
- [ ] [EMERGENCY][T2] billwatch-web vitest suite is RED — TRIAGE then FIX: decide whether the CODE is wrong (fix the code) or the TEST is stale/flaky (fix or update the test), then get the whole suite green. Failing: [31m[1m[7m FAIL [27m[22m[39m src/__tests__/TrendingBillsView.test.ts[2m > [22mTrendingBillsView[2m > [22mshould not contain followBill in source code Files to read and fix: `billwatch-web/src/__tests__/TrendingBillsView.test.ts`
```

## Proposed (LLM re-evaluation — review before applying)
1. [EMERGENCY][T2] Fix `billwatch-web/src/__tests__/TrendingBillsView.test.ts` by updating the assertion to match current `TrendingBillsView.vue` implementation (remove stale `followBill` check) and verify suite passes locally.
2. [T3] Add unit test for `FollowingView.vue` success state rendering to complement recently added error state tests.
3. [T3] Add unit test for `BillsView.vue` loading state spinner visibility to ensure UX consistency with error states.
4. [T4] Refactor `billwatch-android/app/src/main/java/com/billwatch/ui/screens/BillsScreen.kt` to extract list item composable for improved reusability and testability.
5. [T4] Add integration test for `billwatch-android` `BillsRepository` to verify API response mapping against mock data.
