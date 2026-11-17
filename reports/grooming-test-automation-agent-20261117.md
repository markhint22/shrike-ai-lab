# Grooming proposal — test-automation-agent — 2026-11-17 04:00

## Current Next Steps
```
- [ ] [EMERGENCY][T2] frontend vitest suite is RED — TRIAGE then FIX: decide whether the CODE is wrong (fix the code) or the TEST is stale/flaky (fix or update the test), then get the whole suite green. Failing: [31m[1m[7m FAIL [27m[22m[39m src/pages/__tests__/VisualDiffsPage.spec.js[2m > [22mVisualDiffsPage[2m > [22mnavigates on successful approval Files to read and fix: `frontend/src/pages/__tests__/VisualDiffsPage.spec.js`
- [x] (already-satisfied in code, implement-verified) [EMERGENCY][T2] frontend vitest suite is RED — TRIAGE then FIX: decide whether the CODE is wrong (fix the code) or the TEST is stale/flaky (fix or update the test), then get the whole suite green. Failing: [31m[1m[7m FAIL [27m[22m[39m src/pages/testplaneditor-a11y.test.ts[2m > [22mTestPlanEditorPage Accessibility[2m > [22mshould have aria-live="polite" and role="status" on the validation result badge Files to read and fix: `frontend/src/pages/testplaneditor-a11y.test.ts`
```

## Proposed (LLM re-evaluation — review before applying)
1. Verify `frontend/src/pages/__tests__/VisualDiffsPage.spec.js` passes locally to confirm the "navigates on successful approval" fix is stable and remove this item if green.
2. Add unit tests for `backend/app/agents/analyzer.py` covering edge cases in test result parsing.
3. Refactor `backend/app/agents/orchestrator.py` to extract state transition logic into a separate utility module for better testability.
4. Create integration tests for the Alembic migration chain (versions 0001-0010) to ensure database schema consistency.
