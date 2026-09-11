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

# --- 27B-decomposed from roadmap [2026-09-10]: "Bills like this" similarity finder — Surface companion/duplicate/related bills (e.g. Hous (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-11]: Add unit tests for advanced_auth router — app/routers/advanced_auth.py (29 lines, GET /log (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-11]: Add unit tests for recommendations router — app/routers/recommendations.py (4 GET endpoint (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-11]: Add unit tests for email_service.py — app/services/email_service.py (309 lines) has zero t (review + tweak) ---
- [ ] [T1] billwatch-backend/tests/test_email_service.py — Create test file with fixtures mocking `urllib.request.urlopen` and `smtplib.SMTP` to isolate network calls. VERIFY: `cd billwatch-backend && python -m pytest tests/test_email_service.py --collect-only`. (cat:test; multifile:no)
- [ ] [T2] billwatch-backend/tests/test_email_service.py — Add test `test_send_email_success_via_sendgrid` asserting `urllib.request.urlopen` is called with correct SendGrid payload and `smtplib` is NOT called. VERIFY: `cd billwatch-backend && python -m pytest tests/test_email_service.py::test_send_email_success_via_sendgrid -v`. (cat:test; multifile:no)
- [ ] [T3] billwatch-backend/tests/test_email_service.py — Add test `test_send_email_fallback_to_smtp_on_sendgrid_failure` asserting `urllib.request.urlopen` raises exception and `smtplib.SMTP.send_message` is called. VERIFY: `cd billwatch-backend && python -m pytest tests/test_email_service.py::test_send_email_fallback_to_smtp_on_sendgrid_failure -v`. (cat:test; multifile:no)
- [ ] [T4] billwatch-backend/tests/test_email_service.py — Add test `test_send_email_raises_on_both_failures` asserting custom exception is raised when both SendGrid and SMTP mocks fail. VERIFY: `cd billwatch-backend && python -m pytest tests/test_email_service.py::test_send_email_raises_on_both_failures -v`. (cat:test; multifile:no)
- [ ] [T5] billwatch-backend/tests/test_email_service.py — Add test `test_send_email_validation_error` asserting invalid email format raises validation error before any network call. VERIFY: `cd billwatch-backend && python -m pytest tests/test_email_service.py::test_send_email_validation_error -v`. (cat:test; multifile:no)

# --- 27B-decomposed from roadmap [2026-09-11]: Delete two unused stub services — app/services/github_integration_service.py and app/servi (review + tweak) ---
- [ ] [T1] billwatch-backend/app/services/github_integration_service.py — Delete the file containing hardcoded fake data stubs. VERIFY: `test ! -f billwatch-backend/app/services/github_integration_service.py`. (cat:refactor; multifile:no)
- [ ] [T1] billwatch-backend/app/services/legislator_relationship_service.py — Delete the file containing hardcoded fake data stubs. VERIFY: `test ! -f billwatch-backend/app/services/legislator_relationship_service.py`. (cat:refactor; multifile:no)
- [ ] [T2] billwatch-backend/tests/test_dead_code_removal.py — Create a test that asserts the modules `app.services.github_integration_service` and `app.services.legislator_relationship_service` cannot be imported. VERIFY: `cd billwatch-backend && python -m pytest tests/test_dead_code_removal.py -v`. (cat:test; multifile:no)
- [ ] [T3] billwatch-backend/app/services/__init__.py — Ensure no explicit imports of the deleted services exist in the package init file. VERIFY: `grep -q "github_integration_service\|legislator_relationship_service" billwatch-backend/app/services/__init__.py && exit 1 || exit 0`. (cat:python; multifile:no)
- [ ] [T4] billwatch-backend/app/main.py — Verify the application starts successfully without the deleted services to ensure no hidden dependencies. VERIFY: `cd billwatch-backend && timeout 5 python -c "from app.main import app" && echo "OK"`. (cat:python; multifile:no)
- [ ] [T5] billwatch-backend/ — Perform a repository-wide search to confirm zero references to the deleted service filenames remain in any Python file. VERIFY: `grep -r "github_integration_service\|legislator_relationship_service" --include="*.py" . && exit 1 || exit 0`. (cat:refactor; multifile:yes)
