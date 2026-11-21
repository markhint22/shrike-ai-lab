# Grooming proposal — test-automation-agent — 2026-11-21 04:00

## Current Next Steps
```
- [x] (already-satisfied in code, implement-verified) [EMERGENCY][T2] frontend vitest suite is RED — TRIAGE then FIX: decide whether the CODE is wrong (fix the code) or the TEST is stale/flaky (fix or update the test), then get the whole suite green. Failing: [31m[1m[7m FAIL [27m[22m[39m src/pages/testplaneditor-a11y.test.ts[2m > [22mTestPlanEditorPage Accessibility[2m > [22mshould have aria-live="polite" and role="status" on the validation result badge Files to read and fix: `frontend/src/pages/testplaneditor-a11y.test.ts`
```

## Proposed (LLM re-evaluation — review before applying)
1. Fix the failing accessibility test in `frontend/src/pages/testplaneditor-a11y.test.ts` by ensuring the validation result badge has `aria-live="polite"` and `role="status"`.
2. Add unit tests for the `describe_plan` function in `backend/app/services/plan_templat` to verify output formatting and edge cases.
3. Implement a basic health check endpoint in the backend API to support the existing deployment workflows.
