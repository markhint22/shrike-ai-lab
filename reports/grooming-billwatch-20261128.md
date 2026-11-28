# Grooming proposal — billwatch — 2026-11-28 04:00

## Current Next Steps
```
- [x] (already-satisfied in code, implement-verified) [EMERGENCY][T2] billwatch-backend pytest suite is RED — TRIAGE then FIX: decide whether the CODE is wrong (fix the code) or the TEST is stale/flaky (fix or update the test), then get the whole suite green. Failing: ________________ ERROR collecting tests/test_http_cache_etag.py ________________;ERROR tests/test_http_cache_etag.py Files to read and fix: `billwatch-backend/tests/test_http_cache_etag.py`
```

## Proposed (LLM re-evaluation — review before applying)
1. Fix collection error in `billwatch-backend/tests/test_http_cache_etag.py` by verifying the module path and import statements match the current backend structure.
2. Run the full `billwatch-backend` pytest suite to identify any remaining failing tests beyond the collection error.
3. Update `.github/workflows/python-tests.yml` to ensure it triggers on all relevant branches and caches dependencies correctly for faster CI feedback.
4. Add a missing `__init__.py` or adjust `pyproject.toml` in `billwatch-backend` if the test collection error stems from package discovery issues.
5. Verify that `billwatch-android/app/src/main/java/com/billwatch/data/api/BillWatchApi.kt` endpoints align with the current backend API routes to prevent integration drift.
