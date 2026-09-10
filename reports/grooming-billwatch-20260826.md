# Grooming proposal — billwatch — 2026-08-26 04:00

## Current Next Steps
```
1. Wire bill-background to its own bill_backgrounds table — the active BillBackgroundService should read/write that table (context/stakeholders/etc.) instead of the ad-hoc httpx call to localhost:8080, so the new model is actually used.
2. Collapse the two /api/bills/{id}/background routes (GET in routers/bills.py + POST in routers/bill_background.py) into one canonical endpoint.
3. Fix the Android test package mismatch: LegislatorSearchScreenTest imports com.billwatch.data.model.Legislator but the model actually lives at com.policylogs.data.models.Legislator — align packages so the Android tests compile.
4. Add a real llm_client for article-relevance ranking (currently heuristic-only after the dead import was removed) OR formally keep it heuristic-only and delete the remaining unused prompt-building code — decide and document which.
```

## Proposed (LLM re-evaluation — review before applying)
1. Confirm and document the removal of the dead llm_client import and ensure heuristic-only article-relevance ranking is properly implemented.
2. Refactor the /api/bills/{id}/background routes into a single canonical endpoint in routers/bills.py.
3. Update the Android test package imports to align with the actual model location and verify all tests pass.
4. Split the large task of wiring bill-background to its own table into smaller subtasks for database setup and service integration.
5. Add a new feature to track and display user-specific bill preferences using a new user_bills_preferences table.
6. Implement a basic caching layer for frequently accessed bill data to improve API response times.
7. Add automated testing for the new bill_backgrounds table integration to prevent regressions.
