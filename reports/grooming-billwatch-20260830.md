# Grooming proposal — billwatch — 2026-08-30 04:00

## Deterministically stale (target file already gone — safe to drop)
```
2. ~~Collapse the two divergent `/api/bills/{bill_id}/background` handlers into one implementation: GET in `app/routers/bills.py` (line 449, uses `BillBackgroundService` → localhost:8080) vs POST in `app/routers/bill_background.py` (uses `LLMService().generate_bill_background` → Ollama at :11434). Pick the DB-backed path from item 1 as canonical and remove/redirect the other so both verbs share one code path.~~ ✅ Done 2026-08-26
4. Remove dead LLM config in `app/services/article_relevance_service.py`: `self._base_url` and `self._api_key` (from `settings.llm_inference_url` / `settings.llm_api_key`, defined in `app/config.py` lines 35-36) are set in `__init__` but never read — the ranker is intentionally heuristic-only. Delete the unused fields (and the two settings if unused elsewhere — verified they are not) or add a one-line comment formally documenting heuristic-only.
```

## Current Next Steps
```
- [x] `billwatch-backend/app/services/batch_operations.py`: `typing` import is missing `Any` though annotations use `List[Any]` — add `Any` to the `from typing import ...` line. One line.
- [ ] A service module: `csv.DictWriter(...)` will KeyError on extra keys — add `extrasaction="ignore"`. One argument.
- [ ] A service module: a cache check uses `if cached:` which drops a valid empty/zero result — change to `if cached is not None:`. One line.
- [ ] A service module: a SQL LIKE query doesn't escape user `%`/`_` — escape them before building the LIKE pattern. Single function.
- [ ] `billwatch-backend/`: change one bare `except:` to `except Exception:`. One line.
1. Fix `BillBackgroundService.get_background` in `billwatch-backend/app/services/bill_background_service.py`: it currently POSTs to a placeholder `http://localhost:8080/v1/completions` and, on any failure, returns the string `f"Error fetching background: {str(e)}"` — so the GET route `/api/bills/{id}/background` (bills.py:449) returns HTTP 200 with an error message masquerading as real content, and the route's `None`→404 branch is dead. Rewrite it to read the existing `BillBackground` row (model in `app/models/bill.py`, `__tablename__ = "bill_backgrounds"`, fields context/stakeholders/expert_views/related_bills) via the `Bill.bill_background` relationship, return `None` when the bill or background is absent, and drop the httpx placeholder entirely so the `bill_backgrounds` table is actually used.
2. ~~Collapse the two divergent `/api/bills/{bill_id}/background` handlers into one implementation: GET in `app/routers/bills.py` (line 449, uses `BillBackgroundService` → localhost:8080) vs POST in `app/routers/bill_background.py` (uses `LLMService().generate_bill_background` → Ollama at :11434). Pick the DB-backed path from item 1 as canonical and remove/redirect the other so both verbs share one code path.~~ ✅ Done 2026-08-26
3. Reconcile the orphaned `com.billwatch` legislator-search feature (Android): BOTH `billwatch-android/app/src/main/java/com/billwatch/ui/screens/LegislatorSearchScreen.kt` and its test `.../androidTest/java/com/billwatch/ui/screens/LegislatorSearchScreenTest.kt` import `com.billwatch.data.model.Legislator` and `com.billwatch.ui.viewmodels.LegislatorSearchViewModel`, neither of which exists (the real model is `com.policylogs.data.models.Legislator`; there is no `LegislatorSearchViewModel` anywhere). This is not a test-only import fix — the production screen won't compile either. Decide and do ONE: (a) delete the orphaned screen + test, or (b) create the missing `LegislatorSearchViewModel` and a `com.billwatch.data.model.Legislator` (typealias to the policylogs model). Document the choice.
4. Remove dead LLM config in `app/services/article_relevance_service.py`: `self._base_url` and `self._api_key` (from `settings.llm_inference_url` / `settings.llm_api_key`, defined in `app/config.py` lines 35-36) are set in `__init__` but never read — the ranker is intentionally heuristic-only. Delete the unused fields (and the two settings if unused elsewhere — verified they are not) or add a one-line comment formally documenting heuristic-only.
5. Add `tests/test_bill_background_service.py` (none exists) covering the rewritten `BillBackgroundService.get_background` from item 1: bill-with-background returns formatted fields, bill-without-background returns `None`, missing-bill returns `None`. Follow the async `test_db` fixture pattern already in `tests/conftest.py` / `tests/test_article_relevance_service.py`.
- [ ] Add tests for bill_background router
```

## Proposed (LLM re-evaluation — review before applying)
1. Fix `BillBackgroundService.get_background` in `billwatch-backend/app/services/bill_background_service.py` to read from the `BillBackground` DB model instead of the placeholder HTTP endpoint, returning `None` for missing data.
2. Add `tests/test_bill_background_service.py` covering the rewritten `get_background` logic for bills with/without background data and missing bills.
3. Resolve the orphaned `LegislatorSearchScreen.kt` in `billwatch-android` by either deleting the screen and its test or creating the missing `LegislatorSearchViewModel` and `com.billwatch.data.model.Legislator` typealias.
4. Remove dead LLM configuration fields (`_base_url`, `_api_key`) from `billwatch-backend/app/services/article_relevance_service.py` or add a comment documenting the heuristic-only approach.
5. Add `extrasaction="ignore"` to `csv.DictWriter` in the relevant service module to prevent `KeyError` on extra keys.
6. Change the cache check from `if cached:` to `if cached is not None:` in the service module to handle valid empty/zero results.
7. Add tests for the `bill_background` router to verify the unified GET/POST behavior.
