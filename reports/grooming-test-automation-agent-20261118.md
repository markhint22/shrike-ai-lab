# Grooming proposal — test-automation-agent — 2026-11-18 04:00

## Current Next Steps
```
- [x] (already-satisfied in code, implement-verified) [EMERGENCY][T2] frontend vitest suite is RED — TRIAGE then FIX: decide whether the CODE is wrong (fix the code) or the TEST is stale/flaky (fix or update the test), then get the whole suite green. Failing: [31m[1m[7m FAIL [27m[22m[39m src/pages/testplaneditor-a11y.test.ts[2m > [22mTestPlanEditorPage Accessibility[2m > [22mshould have aria-live="polite" and role="status" on the validation result badge Files to read and fix: `frontend/src/pages/testplaneditor-a11y.test.ts`
```

## Proposed (LLM re-evaluation — review before applying)
1. Fix the failing accessibility test in `frontend/src/pages/testplaneditor-a11y.test.ts` by ensuring the validation result badge has `aria-live="polite"` and `role="status"`, then verify the suite is green.
2. Add a unit test for the 'flaky' status select option and badge mapping logic in the frontend to ensure the recent feature is covered.
3. Add a unit test for the run count display paragraph logic, specifically verifying singular/plural handling edge cases.
