# Grooming proposal — test-automation-agent — 2026-11-28 04:00

## Current Next Steps
```
- [x] [EMERGENCY][T2] backend pytest suite is RED — TRIAGE then FIX: decide whether the CODE is wrong (fix the code) or the TEST is stale/flaky (fix or update the test), then get the whole suite green. Failing: FAILED tests/test_test_plan_actions_doc.py::test_doc_has_no_unknown_actions Files to read and fix: `backend/tests/test_test_plan_actions_doc.py` <!-- closed 2026-11-23: doc fixed in ecdaf3b4; baseline green -->
- [x] (already-satisfied in code, implement-verified) [EMERGENCY][T2] frontend vitest suite is RED — TRIAGE then FIX: decide whether the CODE is wrong (fix the code) or the TEST is stale/flaky (fix or update the test), then get the whole suite green. Failing: [31m[1m[7m FAIL [27m[22m[39m src/pages/testplaneditor-a11y.test.ts[2m > [22mTestPlanEditorPage Accessibility[2m > [22mshould have aria-live="polite" and role="status" on the validation result badge Files to read and fix: `frontend/src/pages/testplaneditor-a11y.test.ts`
```

## Proposed (LLM re-evaluation — review before applying)
1. Consolidate redundant GitHub Actions workflows (e.g., merge `python-tests.yml` and `tests.yml`) to reduce CI noise and execution time
2. Add a `Makefile` target for running the full backend test suite with coverage reporting to standardize local development checks
3. Update `backend/TESTING_SUMMARY.md` to reflect the current green status of the pytest suite and document the recent fix in `test_test_plan_actions_doc.py`
