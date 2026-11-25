# Grooming proposal — test-automation-agent — 2026-11-25 04:00

## Current Next Steps
```
- [x] [EMERGENCY][T2] backend pytest suite is RED — TRIAGE then FIX: decide whether the CODE is wrong (fix the code) or the TEST is stale/flaky (fix or update the test), then get the whole suite green. Failing: FAILED tests/test_test_plan_actions_doc.py::test_doc_has_no_unknown_actions Files to read and fix: `backend/tests/test_test_plan_actions_doc.py` <!-- closed 2026-11-23: doc fixed in ecdaf3b4; baseline green -->
- [x] (already-satisfied in code, implement-verified) [EMERGENCY][T2] frontend vitest suite is RED — TRIAGE then FIX: decide whether the CODE is wrong (fix the code) or the TEST is stale/flaky (fix or update the test), then get the whole suite green. Failing: [31m[1m[7m FAIL [27m[22m[39m src/pages/testplaneditor-a11y.test.ts[2m > [22mTestPlanEditorPage Accessibility[2m > [22mshould have aria-live="polite" and role="status" on the validation result badge Files to read and fix: `frontend/src/pages/testplaneditor-a11y.test.ts`
```

## Proposed (LLM re-evaluation — review before applying)
1. Consolidate duplicate GitHub Actions workflows (e.g., `python-tests.yml` vs `tests.yml`, `deploy-backend.yml` vs `fly-deploy.yml`) to reduce CI noise and maintenance overhead.
2. Add unit tests for the `backend/app/agents/analyzer.py` module to ensure core analysis logic is covered by the green test suite.
3. Create a minimal, functional stub for `frontend/src/utils/__tests__/parseDurationInput.test.ts` to replace the deleted file and prevent future "unfilled stub" churn.
