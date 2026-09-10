# billwatch — pre-decomposed release-polish backlog (27B-friendly)
# queue_refill.py pulls [T1-T5] items from here into OVERNIGHT_PROGRESS.md when doable is low.


# --- next-year roadmap decomposition (2026-09-05): router-404 fix + finished-backend wiring + Q5 ---

# --- refill 2026-09-06: bill-domain pure modules (self-verifying, T1-T2) ---

# --- COMPETITIVE 2026-09-06: BillWatch vs FastDemocracy — digests + real-time alerts + AI summaries (federal-only consumer wedge) ---
# Weekly digest (FastDemocracy free tier has it)
# Real-time alerts (FastDemocracy Professional; BillWatch wedge = free/simple)
# AI summaries — competitor has "AI meeting summaries"; BillWatch already has bill summaries, deepen them

# --- TS gate hardening (2026-09-07): make each web repo's per-cycle type-check explicit ---

# --- 27B-decomposed from roadmap [2026-09-07]: Weekly digest (grouped by stage/topic) + endpoint + view {cat: backend+web; size: M; multi (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-07]: Real-time alerts on tracked topics/bills (rules + match) {cat: backend+web; size: M; multi (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-08]: Plain-English "what changed" status summaries {cat: backend; size: S; multifile: no; resea (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-08]: Legislator profiles + scorecards surface polish {cat: web; size: M; multifile: yes; resear (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-09]: iOS/Android feature parity with web (tracking, digests, alerts) — researched 2026-09-09: b (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-09]: Campaign-finance / vote-record insights as a light premium tier — CORRECTED 2026-09-09: th (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-10]: Committee hearing & floor-activity calendar for tracked bills — Surface a "This Week in Co (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-10]: Shareable bill status cards — One-tap "share" on any tracked bill generates a branded imag (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-10]: Shareable bill status cards — One-tap "share" on any tracked bill generates a branded imag (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-10]: Plain-English bill "odds of passage" indicator — A lightweight, transparent heuristic (not (review + tweak) ---
- [ ] [T1] billwatch-backend/app/services/bill_odds_service.py — Implement `calculate_odds(bill: Bill) -> OddsResult` pure function using stage, days_elapsed, and committee to return probability and plain-English string. VERIFY: python -m pytest billwatch-backend/tests/test_bill_odds_service.py::test_calculate_odds_basic -v (cat:python; multifile:no)
- [ ] [T1] billwatch-backend/app/services/bill_odds_service.py — Implement `get_historical_base_rate(stage: str, committee_id: Optional[int]) -> float` to query historical bill success rates from DB. VERIFY: python -m pytest billwatch-backend/tests/test_bill_odds_service.py::test_get_historical_base_rate -v (cat:python; multifile:no)
- [ ] [T2] billwatch-backend/app/schemas/bill.py — Add `OddsOfPassage` Pydantic schema with `probability`, `plain_english`, and `confidence_level` fields. VERIFY: python -c "from billwatch_backend.app.schemas.bill import OddsOfPassage; print(OddsOfPassage.__fields__.keys())" (cat:schema; multifile:no)
- [ ] [T3] billwatch-backend/app/routers/bills.py — Add `/bills/{bill_id}/odds` endpoint that calls `bill_odds_service.calculate_odds` and returns `OddsOfPassage` schema. VERIFY: python -m pytest billwatch-backend/tests/test_bills_router.py::test_get_bill_odds -v (cat:endpoint; multifile:no)
- [ ] [T3] billwatch-backend/app/routers/digest.py — Inject `odds_of_passage` field into daily digest bill summaries by calling `bill_odds_service`. VERIFY: python -m pytest billwatch-backend/tests/test_digest_router.py::test_digest_includes_odds -v (cat:endpoint; multifile:no)
- [ ] [T4] billwatch-backend/app/models/bill.py — Add `odds_cache` JSON column and `odds_calculated_at` timestamp to Bill model for performance. VERIFY: alembic upgrade head && python -c "from billwatch_backend.app.models.bill import Bill; print(hasattr(Bill, 'odds_cache'))" (cat:python; multifile:yes)
- [ ] [T5] billwatch-backend/app/services/bill_sync_service.py — Update sync logic to trigger odds recalculation when bill stage changes or new historical data is ingested. VERIFY: python -m pytest billwatch-backend/tests/test_bill_sync_service.py::test_sync_triggers_odds_update -v (cat:python; multifile:yes)
- [ ] [T2] billwatch-backend/app/core/validators.py — Add `validate_odds_input` to ensure stage and days_elapsed are within valid ranges before calculation. VERIFY: python -m pytest billwatch-backend/tests/test_validators.py::test_validate_odds_input -v (cat:python; multifile:no)

# --- 27B-decomposed from roadmap [2026-09-10]: "Bills like this" similarity finder — Surface companion/duplicate/related bills (e.g. Hous (review + tweak) ---
- [ ] [T1] billwatch-backend/app/services/bill_similarity_service.py — Implement `compute_bill_embedding(text: str) -> list[float]` using local sentence-transformers and `find_similar_bills(bill_id: int, db: Session, limit: int = 5) -> list[Bill]` that queries existing summaries/titles. VERIFY: `pytest billwatch-backend/tests/test_bill_similarity_service.py::test_compute_embedding_returns_vector -v`. (cat:python; multifile:no)
- [ ] [T2] billwatch-backend/app/schemas/bill.py — Add `SimilarBill` Pydantic schema with `id`, `title`, `summary`, and `similarity_score` fields. VERIFY: `python -c "from billwatch_backend.app.schemas.bill import SimilarBill; print(SimilarBill.model_fields.keys())"`. (cat:schema; multifile:no)
- [ ] [T3] billwatch-backend/app/services/bill_summary_service.py — Modify the summary generation job to call `compute_bill_embedding` on the generated text and store the vector in a new `embedding` column on the Bill model. VERIFY: `pytest billwatch-backend/tests/test_bill_summary_service.py::test_summary_job_stores_embedding -v`. (cat:python; multifile:no)
- [ ] [T4] billwatch-backend/app/models/bill.py — Add an `embedding` column of type `Vector(384)` to the Bill model and create a corresponding Alembic migration. VERIFY: `alembic upgrade head && python -c "from billwatch_backend.app.models.bill import Bill; print(Bill.embedding)"`. (cat:schema; multifile:yes)
- [ ] [T5] billwatch-backend/app/routers/bills.py — Add a `GET /bills/{bill_id}/similar` endpoint that calls `find_similar_bills` and returns a list of `SimilarBill` objects. VERIFY: `curl -s http://localhost:8000/bills/1/similar | jq '.[0].similarity_score'`. (cat:endpoint; multifile:no)
