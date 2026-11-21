# Grooming proposal — billwatch — 2026-11-21 04:00

## Current Next Steps
```
- [x] (already-satisfied in code, implement-verified) [EMERGENCY][T2] billwatch-backend pytest suite is RED — TRIAGE then FIX: decide whether the CODE is wrong (fix the code) or the TEST is stale/flaky (fix or update the test), then get the whole suite green. Failing: ________________ ERROR collecting tests/test_http_cache_etag.py ________________;ERROR tests/test_http_cache_etag.py Files to read and fix: `billwatch-backend/tests/test_http_cache_etag.py`
```

## Proposed (LLM re-evaluation — review before applying)
1. Verify `billwatch-backend/tests/test_http_cache_etag.py` passes locally to confirm the ETag format fix is complete and remove the stale emergency item from the backlog.
2. Add unit tests for the newly implemented vote margin helpers in `billwatch-backend` to ensure edge cases (ties, missing data) are covered.
3. Refactor `billwatch-android/app/src/main/java/com/billwatch/ui/screens/BillsScreen.kt` to extract list item rendering into a composable component for improved readability and testability.
4. Implement basic input validation and error handling in `billwatch-android/app/src/main/java/com/billwatch/data/repository/AuthRepository.kt` for network failures.
5. Create a shared utility module in `billwatch-backend` to centralize common HTTP client configuration and retry logic used across services.
