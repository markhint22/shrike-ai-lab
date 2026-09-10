# Grooming proposal — test-automation-agent — 2026-08-25 15:22

## Current Next Steps
```
1. ~~Implement the run_step "type" action in backend/app/agents/executor.py (page.fill(selector, value)) plus one unit test.~~ ✅ Done 2026-08-02
2. ~~De-duplicate the two step executors — run_step (navigate/click only) is orphaned; the live pipeline (run_test → _execute_step) uses the richer _execute_step which already handles type/wait/scroll/screenshot. Wire run_test to run_step or fold run_step into _execute_step so there's one code path.~~ ✅ Done 2026-08-02 — `run_step` now delegates to `_execute_step` (single code path, gains wait/scroll/screenshot support). Added 3 tests in `TestExecutorRunStepDelegation`.
3. ~~Add a happy-path integration test: one end-to-end execute_phase → run_tests_concurrent run against a mocked Playwright page, asserting passed/failed counts and context updates.~~ ✅ Done 2026-08-25 — `TestOrchestratorExecutePhaseIntegration.test_execute_phase_happy_path_updates_context` in `tests/test_orchestrator_agent.py`.
4. Add a `_classify_difficulty_llm(self, test)` helper in orchestrator.py that builds a short classification prompt and calls the LLM service, returning 'easy'/'medium'/'hard' (or None on any failure). Add ONE unit test with a mocked LLM service. (First half of the old LLM-classification item — keep it small.)
5. Wire classify_difficulty to call `_classify_difficulty_llm` when an LLM tier is available (non-flash), falling back to the existing heuristic on None/failure. Add ONE unit test. (Second half.)
```

## Proposed (LLM re-evaluation — review before applying)
1. Implement `_classify_difficulty_llm` helper in `backend/app/agents/orchestrator.py` to call LLM service for difficulty classification, returning 'easy'/'medium'/'hard' or None on failure, with one unit test using a mocked LLM service.
2. Wire `classify_difficulty` in `backend/app/agents/orchestrator.py` to use `_classify_difficulty_llm` when an LLM tier is available, falling back to the existing heuristic on None/failure, with one unit test.
3. Add a unit test for `backend/app/services/llm_service.py` to verify prompt construction and response parsing for the difficulty classification feature.
4. Create a basic integration test for `backend/app/routers/test_runs.py` to verify the API endpoint for triggering test runs returns the correct status code and structure.
5. Add a unit test for `backend/app/services/playwright_service.py` to ensure the service correctly initializes and closes browser contexts without leaking resources.
