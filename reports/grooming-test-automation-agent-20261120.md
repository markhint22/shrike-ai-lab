# Grooming proposal — test-automation-agent — 2026-11-20 04:00

## Current Next Steps
```
- [x] (already-satisfied in code, implement-verified) [EMERGENCY][T2] frontend vitest suite is RED — TRIAGE then FIX: decide whether the CODE is wrong (fix the code) or the TEST is stale/flaky (fix or update the test), then get the whole suite green. Failing: [31m[1m[7m FAIL [27m[22m[39m src/pages/testplaneditor-a11y.test.ts[2m > [22mTestPlanEditorPage Accessibility[2m > [22mshould have aria-live="polite" and role="status" on the validation result badge Files to read and fix: `frontend/src/pages/testplaneditor-a11y.test.ts`
```

## Proposed (LLM re-evaluation — review before applying)
1. Fix the failing accessibility test in `frontend/src/pages/testplaneditor-a11y.test.ts` by verifying if the `aria-live="polite"` and `role="status"` attributes are missing from the validation badge component or if the test selector is incorrect, then apply the necessary code or test fix to turn the suite green.
2. Consolidate the redundant deployment workflows in `.github/workflows/` (specifically `backend-deploy.yml`, `deploy-backend.yml`, and `fly-deploy.yml`) into a single, parameterized workflow to reduce maintenance overhead and CI flakiness.
3. Add a pre-commit hook or GitHub Action step to enforce PEP 8 compliance and type checking for the Python backend files in `backend/app/agents/` to prevent style regressions before they reach the main branch.
