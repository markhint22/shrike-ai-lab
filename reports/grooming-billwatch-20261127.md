# Grooming proposal — billwatch — 2026-11-27 04:00

## Current Next Steps
```
- [x] (already-satisfied in code, implement-verified) [EMERGENCY][T2] billwatch-backend pytest suite is RED — TRIAGE then FIX: decide whether the CODE is wrong (fix the code) or the TEST is stale/flaky (fix or update the test), then get the whole suite green. Failing: ________________ ERROR collecting tests/test_http_cache_etag.py ________________;ERROR tests/test_http_cache_etag.py Files to read and fix: `billwatch-backend/tests/test_http_cache_etag.py`
```

## Proposed (LLM re-evaluation — review before applying)
1. Fix collection error in `billwatch-backend/tests/test_http_cache_etag.py` by resolving import or syntax issues to allow pytest to run the suite.
2. Run full `billwatch-backend` pytest suite and triage remaining failures, fixing code or updating stale tests to achieve a green state.
3. Add unit tests for `BillWatchApi.kt` in `billwatch-android` to verify HTTP request construction and error handling logic.
4. Implement basic UI navigation flow in `billwatch-android` linking `MainActivity.kt` to `BillsScreen.kt` via `Navigation.kt`.
5. Create a `Makefile` target for `billwatch-android` to automate building the debug APK for local testing.
