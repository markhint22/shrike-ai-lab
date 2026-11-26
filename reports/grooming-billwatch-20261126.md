# Grooming proposal — billwatch — 2026-11-26 04:00

## Current Next Steps
```
- [x] (already-satisfied in code, implement-verified) [EMERGENCY][T2] billwatch-backend pytest suite is RED — TRIAGE then FIX: decide whether the CODE is wrong (fix the code) or the TEST is stale/flaky (fix or update the test), then get the whole suite green. Failing: ________________ ERROR collecting tests/test_http_cache_etag.py ________________;ERROR tests/test_http_cache_etag.py Files to read and fix: `billwatch-backend/tests/test_http_cache_etag.py`
```

## Proposed (LLM re-evaluation — review before applying)
1. Fix collection error in `billwatch-backend/tests/test_http_cache_etag.py` by verifying file existence and correcting import paths or test fixtures to ensure the pytest suite can load.
2. Run full `billwatch-backend` pytest suite and triage any remaining failures, fixing code bugs or updating stale tests to achieve a green status.
3. Add input validation and error handling to the new `billwatch-backend/app/routers/topics.py` FastAPI router to prevent 500 errors on malformed requests.
4. Implement unit tests for the `topics.py` router endpoints to verify correct response codes and data serialization.
5. Refactor `billwatch-android/app/src/main/java/com/billwatch/data/api/BillWatchApi.kt` to use consistent error handling and retry logic for network calls.
