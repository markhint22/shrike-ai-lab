# Grooming proposal — test-automation-agent — 2026-11-22 04:01

## Current Next Steps
```
- [x] (already-satisfied in code, implement-verified) [EMERGENCY][T2] frontend vitest suite is RED — TRIAGE then FIX: decide whether the CODE is wrong (fix the code) or the TEST is stale/flaky (fix or update the test), then get the whole suite green. Failing: [31m[1m[7m FAIL [27m[22m[39m src/pages/testplaneditor-a11y.test.ts[2m > [22mTestPlanEditorPage Accessibility[2m > [22mshould have aria-live="polite" and role="status" on the validation result badge Files to read and fix: `frontend/src/pages/testplaneditor-a11y.test.ts`
```

## Proposed (LLM re-evaluation — review before applying)
1. Fix the failing accessibility test in `frontend/src/pages/testplaneditor-a11y.test.ts` by verifying if the `aria-live="polite"` and `role="status"` attributes are missing from the validation result badge component or if the test selector is incorrect, then apply the necessary code or test fix to make the suite green.
2. Consolidate duplicate deployment workflows in `.github/workflows/` (e.g., `backend-deploy.yml`, `deploy-backend.yml`, `fly-deploy.yml`) into a single, parameterized workflow to reduce maintenance overhead and CI execution time.
3. Add unit tests for the backend agent logic in `backend/app/agents/analyzer.py` and `backend/app/agents/executor.py` to ensure core automation functions are covered by the existing test suite.
