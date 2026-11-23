# Grooming proposal — billwatch — 2026-11-23 04:00

## Current Next Steps
```
- [x] (already-satisfied in code, implement-verified) [EMERGENCY][T2] billwatch-backend pytest suite is RED — TRIAGE then FIX: decide whether the CODE is wrong (fix the code) or the TEST is stale/flaky (fix or update the test), then get the whole suite green. Failing: ________________ ERROR collecting tests/test_http_cache_etag.py ________________;ERROR tests/test_http_cache_etag.py Files to read and fix: `billwatch-backend/tests/test_http_cache_etag.py`
```

## Proposed (LLM re-evaluation — review before applying)
1. Fix collection error in `billwatch-backend/tests/test_http_cache_etag.py` by verifying import paths and mocking dependencies to ensure the test file loads without crashing.
2. Run the full `billwatch-backend` pytest suite to identify any remaining failing tests beyond the collection error, then triage each failure as code-bug or stale-test.
3. Update `billwatch-android/app/src/main/java/com/billwatch/data/models/Bill.kt` to include a `lastUpdated` timestamp field if missing, ensuring data freshness tracking for the UI.
4. Add unit tests for `billwatch-android/app/src/main/java/com/billwatch/data/repository/BillsRepository.kt` to verify cache invalidation logic when new bill data is fetched.
5. Refactor `billwatch-backend/tests/test_http_cache_etag.py` to use a shared fixture for HTTP client mocking, reducing duplication and improving maintainability of cache-related tests.
