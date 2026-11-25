# Grooming proposal — billwatch — 2026-11-25 04:00

## Current Next Steps
```
- [x] (already-satisfied in code, implement-verified) [EMERGENCY][T2] billwatch-backend pytest suite is RED — TRIAGE then FIX: decide whether the CODE is wrong (fix the code) or the TEST is stale/flaky (fix or update the test), then get the whole suite green. Failing: ________________ ERROR collecting tests/test_http_cache_etag.py ________________;ERROR tests/test_http_cache_etag.py Files to read and fix: `billwatch-backend/tests/test_http_cache_etag.py`
```

## Proposed (LLM re-evaluation — review before applying)
1. Fix collection error in `billwatch-backend/tests/test_http_cache_etag.py` by verifying import paths and module existence
2. Run full `billwatch-backend` pytest suite to identify remaining failures after fixing the collection error
3. Update `billwatch-android/app/src/main/java/com/billwatch/ui/screens/BillsScreen.kt` to handle empty state for bill lists
4. Add unit tests for `billwatch-android/app/src/main/java/com/billwatch/data/repository/BillsRepository.kt`
5. Refactor `billwatch-backend/tests/test_http_cache_etag.py` to use fixtures for HTTP mocking
