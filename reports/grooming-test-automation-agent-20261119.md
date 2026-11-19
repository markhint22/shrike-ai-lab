# Grooming proposal — test-automation-agent — 2026-11-19 04:00

## Current Next Steps
```
- [x] (already-satisfied in code, implement-verified) [EMERGENCY][T2] frontend vitest suite is RED — TRIAGE then FIX: decide whether the CODE is wrong (fix the code) or the TEST is stale/flaky (fix or update the test), then get the whole suite green. Failing: [31m[1m[7m FAIL [27m[22m[39m src/pages/testplaneditor-a11y.test.ts[2m > [22mTestPlanEditorPage Accessibility[2m > [22mshould have aria-live="polite" and role="status" on the validation result badge Files to read and fix: `frontend/src/pages/testplaneditor-a11y.test.ts`
```

## Proposed (LLM re-evaluation — review before applying)
1. Verify `frontend/src/pages/testplaneditor-a11y.test.ts` passes; if green, remove the emergency triage item from the backlog.
2. Consolidate duplicate deployment workflows in `.github/workflows/` (e.g., `backend-deploy.yml` vs `deploy-backend.yml`) into a single canonical pipeline to reduce maintenance overhead.
3. Add a `frontend/vitest.config.ts` if missing, or update it to ensure all test files are included in the coverage report for the next sprint.
