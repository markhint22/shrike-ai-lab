# Grooming proposal — billwatch — 2026-11-22 04:00

## Current Next Steps
```
- [x] (already-satisfied in code, implement-verified) [EMERGENCY][T2] billwatch-backend pytest suite is RED — TRIAGE then FIX: decide whether the CODE is wrong (fix the code) or the TEST is stale/flaky (fix or update the test), then get the whole suite green. Failing: ________________ ERROR collecting tests/test_http_cache_etag.py ________________;ERROR tests/test_http_cache_etag.py Files to read and fix: `billwatch-backend/tests/test_http_cache_etag.py`
```

## Proposed (LLM re-evaluation — review before applying)
1. Fix collection error in `billwatch-backend/tests/test_http_cache_etag.py` by resolving import or syntax issues to allow test discovery.
2. Run full backend pytest suite and triage remaining failures, distinguishing between code bugs and stale tests.
3. Update or fix specific failing tests identified in the triage phase to achieve a green build.
4. Add unit tests for `billwatch-android/app/src/main/java/com/billwatch/data/repository/BillsRepository.kt` to cover core data fetching logic.
5. Implement input validation and error handling in `billwatch-backend` API endpoints for missing or malformed request parameters.
6. Refactor `billwatch-android/app/src/main/java/com/billwatch/ui/screens/BillDetailScreen.kt` to extract complex UI logic into a dedicated ViewModel for better testability.
