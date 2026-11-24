# Grooming proposal — billwatch — 2026-11-24 04:01

## Current Next Steps
```
- [x] (already-satisfied in code, implement-verified) [EMERGENCY][T2] billwatch-backend pytest suite is RED — TRIAGE then FIX: decide whether the CODE is wrong (fix the code) or the TEST is stale/flaky (fix or update the test), then get the whole suite green. Failing: ________________ ERROR collecting tests/test_http_cache_etag.py ________________;ERROR tests/test_http_cache_etag.py Files to read and fix: `billwatch-backend/tests/test_http_cache_etag.py`
```

## Proposed (LLM re-evaluation — review before applying)
1. Fix collection error in `billwatch-backend/tests/test_http_cache_etag.py` by verifying the module path and import statements match the current backend structure.
2. Run the full `billwatch-backend` pytest suite to identify any remaining failing tests beyond the collection error.
3. Update or fix the specific test cases in `billwatch-backend/tests/test_http_cache_etag.py` that are failing due to stale assertions or flaky behavior.
4. Add a unit test for `Bill.calculate_reading_time` in `billwatch-android` to verify the logic uses only summary text as per recent commits.
5. Refactor `billwatch-android/app/src/main/java/com/billwatch/data/models/Bill.kt` to ensure `calculate_reading_time` is pure and easily testable without side effects.
6. Add a CI step in `.github/workflows/backend-tests.yml` to explicitly fail the build if any test file fails to collect, preventing silent skips.
