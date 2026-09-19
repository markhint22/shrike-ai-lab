# Grooming proposal — shrike-monitor — 2026-09-19 04:00

## Current Next Steps
```
- [x] [T1] Add tests for `Monitor.to_dict` and `CheckResult.to_dict` in backend/app/models.py (round-trip all fields)
- [x] [T1] Add tests for `classify_http` boundary in backend/app/models.py (latency exactly == degraded_latency_ms -> degraded; a None latency but ok -> up)
- [x] (already-satisfied in code, implement-verified) [T2] Add tests for `heartbeat_overdue` boundary in backend/app/models.py (now exactly at interval+grace -> not overdue; one second past -> overdue)
- [x] (already-satisfied in code, implement-verified) [T2] Add a `worst_status` helper in backend/app/models.py returning the worst of a list of statuses (down>degraded>up>pending) + tests
- [x] (already-satisfied in code, implement-verified) [T2] Add a `latency_stats` helper in backend/app/models.py (min/avg/max/p95 over the ok results' latency_ms, ignoring None) + tests
- [x] [T2] Add a `consecutive_failures` helper in backend/app/models.py (count trailing non-ok results) + tests
- [x] (already-satisfied in code, implement-verified) [T2] Add a `should_alert` helper in backend/app/models.py (True when consecutive_failures >= a threshold, transitioning up->down) + tests
- [x] [T1] Add validation to `MonitorCreate` in backend/app/schemas.py requiring url to be non-empty when type=="http" (model validator) + a test
- [x] [T1] Add a `pattern`/scheme check that http monitor urls start with http:// or https:// in backend/app/schemas.py + a test
- [x] [T2] Add tests for `Store.results` limit argument and empty-monitor behavior in backend/app/store.py
- [x] (already-satisfied in code, implement-verified) [T2] Add a `Store.record_probe` convenience that records + trims, and a `Store.latest(monitor_id)` returning the most recent result or None, in backend/app/store.py + tests
- [x] [AUTO-SKIP after 4 failed-to-land cycles — kept reverting (already-done, too hard for the 27B, or a sibling-file gate fail); review — NOT necessarily human-only] [HUMAN] [T1] backend/app/main.py — pass a description and license_info to FastAPI(...) for a complete OpenAPI doc. VERIFY: GET /openapi.json → json["info"]["description"] is a non-empty string. (polish:docs)  <!-- superseded by recovery decomposition below -->
- [x] (already-satisfied in code, implement-verified) [T1] backend/app/main.py — Add `description="Shrike Monitor API"` and `license_info={"name": "MIT"}` arguments to the `FastAPI(...)` instantiation. VERIFY: `curl -s http://localhost:8000/openapi.json | jq '.info.description'` returns `"Shrike Monitor API"`. (cat:docs; recovery:decomposed)
- [x] [T2] backend/tests/test_sla_met.py — Add tests for `sla_met(results: list[CheckResult], target: float) -> bool` in backend/app/utils/sla_met.py covering: `target=0.0` with any results returns True, a target exactly equal to the computed `uptime_ratio(results)` returns True (boundary is `>=`), and an empty `results` list returns True for `target=0.0` (since `uptime_ratio([])` is `0.0`, per backend/app/models.py) but False for any `target > 0.0`. VERIFY: `cd backend && .venv/bin/pytest tests/test_sla_met.py -v`. (cat:test; multifile:no)
- [x] [T1] backend/tests/test_ema.py — Add tests for `ema(prev: float, sample: float, alpha: float) -> float` in backend/app/utils/ema.py: `ema(prev, sample, 1.0) == sample` (no smoothing), `ema(prev, sample, 0.0) == prev` (frozen), and a mid-range case e.g. `ema(0.0, 10.0, 0.5) == 5.0`. VERIFY: `cd backend && .venv/bin/pytest tests/test_ema.py -v`. (cat:test; multifile:no)
- [x] [T1] backend/app/models.py — Add a `-> None` return type hint to `CheckResult.__post_init__` (currently `def __post_init__(self):` with no annotation). VERIFY: `grep -q "def __post_init__(self) -> None" backend/app/models.py && echo PASS || echo FAIL`. (cat:refill)  <!-- pre-verified: VERIFY already passed against current code -->
- [x] [T1] backend/app/main.py — Add a return type hint to `async def health():` — it returns either `Health` or `JSONResponse`, so annotate as `-> Health | JSONResponse:` (both already imported in this file). VERIFY: `grep -qE "async def health\(\) *-> *Health *\| *JSONResponse" backend/app/main.py && echo PASS || echo FAIL`. (cat:refill)  <!-- pre-verified: VERIFY already passed against current code -->
- [x] [T1] backend/app/schemas.py — Add a return type hint to `MonitorCreate.check_url_rules(self):` (a `@model_validator(mode="after")` that returns `self`) — annotate as `-> "MonitorCreate":`. VERIFY: `grep -qE "def check_url_rules\(self\) *-> *.MonitorCreate." backend/app/schemas.py && echo PASS || echo FAIL`. (cat:refill)  <!-- pre-verified: VERIFY already passed against current code -->
- [x] [T2] backend/app/routers/monitors.py — In `create_monitor()`, catch `StoreFull` (import it from `app.store` alongside `store`) around the `await store.create(...)` call and re-raise as `HTTPException(status_code=507, detail=str(exc))` instead of letting the RuntimeError subclass propagate as an unhandled 500. VERIFY: `grep -q "StoreFull" backend/app/routers/monitors.py && grep -q "507" backend/app/routers/monitors.py && echo PASS || echo FAIL`. (cat:refill)  <!-- pre-verified: VERIFY already passed against current code -->
```

## Proposed (LLM re-evaluation — review before applying)
1. Add tests for `Store.record_probe` and `Store.latest` in backend/app/store.py to verify trimming logic and latest result retrieval (split from completed item)
2. Add tests for `Store.results` limit argument and empty-monitor behavior in backend/app/store.py (split from completed item)
3. Add a `worst_status` helper in backend/app/models.py returning the worst of a list of statuses (down>degraded>up>pending) + tests (split from completed item)
4. Add a `latency_stats` helper in backend/app/models.py (min/avg/max/p95 over the ok results' latency_ms, ignoring None) + tests (split from completed item)
5. Add a `consecutive_failures` helper in backend/app/models.py (count trailing non-ok results) + tests (split from completed item)
6. Add a `should_alert` helper in backend/app/models.py (True when consecutive_failures >= a threshold, transitioning up->down) + tests (split from completed item)
7. Add tests for `heartbeat_overdue` boundary in backend/app/models.py (now exactly at interval+grace -> not overdue; one second past -> overdue) (split from completed item)
8. Add validation to `MonitorCreate` in backend/app/schemas.py requiring url to be non-empty when type=="http" (model validator) + a test (split from completed item)
9. Add a `pattern`/scheme check that http monitor urls start with http:// or https:// in backend/app/schemas.py + a test (split from completed item)
10. Add tests for `Monitor.to_dict` and `CheckResult.to_dict` in backend/app/models.py (round-trip all fields) (split from completed item)
11. Add tests for `classify_http` boundary in backend/app/models.py (latency exactly == degraded_latency_ms -> degraded; a None latency but ok -> up) (split from completed item)
12. Add tests for `sla_met(results: list[CheckResult], target: float) -> bool` in backend/app/utils/sla_met.py covering edge cases (split from completed item)
13. Add tests for `ema(prev: float, sample: float, alpha: float) -> float` in backend/app/utils/ema.py covering boundary cases (split from completed item)
14. Add a return type hint to `CheckResult.__post_init__` in backend/app/models.py (split from completed item)
15. Add a return type hint to `async def health():` in backend/app/main.py (split from completed item)
16. Add a return type hint to `MonitorCreate.check_url_rules(self):` in backend/app/schemas.py (split from completed item)
17. In `create_monitor()` in backend/app/routers/monitors.py, catch `StoreFull` and re-raise as `HTTPException(status_code=507)` (split from completed item)
18. Add tests for `backend/app/utils/backoff.py` to verify exponential backoff calculation and jitter application
19. Add tests for `backend/app/utils/downtime.py` to verify downtime duration calculation from check results
20. Add tests for `backend/app/utils/status_streak.py` to verify streak counting logic for consecutive statuses
