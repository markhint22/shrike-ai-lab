# test-automation-agent (SpecPilot) — RELEASE-READINESS backlog (27B-friendly), blockers FIRST
# Backend is saturated with tests; the real release gaps are the thin Vue frontend.

# --- next-year roadmap decomposition (2026-09-05): surface backend features + CI/scheduling ---

# --- refill (2026-09-05): frontend store/page coverage (backend near-exhausted) ---

# --- refill 2026-09-06: new self-contained pure modules (pytest + vitest, landable T1-T2) ---

# --- refill 2026-09-06: test-run-domain pure modules (self-verifying, T1-T2) ---

# --- refill 2026-09-06b: more test-run domain pure modules ---

# --- 27B-decomposed from roadmap [2026-09-07]: Test-run summaries, status, retry/rerun decisions, flake ratios (pure logic + endpoints) { (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-07]: Run dashboard UI: status colors, durations, pass/flake surfaces {cat: web; size: M; multif (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-07]: Knowledge-base / test-selection helpers {cat: backend; size: M; multifile: no; research: r (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-09]: CI integrations (GitHub Actions/Jenkins) result ingestion — researched 2026-09-09: GitHub  (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-10]: Flake-state Slack/webhook alerts — When a test's rolling flake ratio crosses a configured  (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-10]: "Fix-first" ranking view — Add a dashboard view/API endpoint that ranks tests by (flake-ra (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-10]: "Fix-first" ranking view — Add a dashboard view/API endpoint that ranks tests by (flake-ra (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-10]: Per-test flake-rate trend chart — On each test's detail page, render a time-series/sparkli (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-10]: PR-comment run summary — Post a single upserted PR comment (via the same GitHub App/token  (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-11]: Rerun-failed-only endpoint — Add `POST /api/test-runs/{run_id}/rerun-failed` (backend/app/ (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-11]: Auto-release stale quarantines — backend/app/services/flake_detection.py's record_result() (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-11]: Wire PR-comment upsert into the GitHub API — backend/app/utils/pr_comment_body.py (build_p (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-11]: Visual-regression diff flagging — backend/app/utils/visual_diff.py (diff_ratio, is_visual_ (review + tweak) ---
- [ ] [T3] frontend/src/stores/testRuns.js — Update `testRuns` store mapping to include `isVisualRegression` from API payload. VERIFY: `grep -q "isVisualRegression" frontend/src/stores/testRuns.js`. (cat:typescript; multifile:no)
- [ ] [T4] frontend/src/pages/TestRunDetailPage.vue — Add conditional badge component displaying "Visual Regression" when `result.isVisualRegression` is true. VERIFY: `grep -q "Visual Regression" frontend/src/pages/TestRunDetailPage.vue`. (cat:vue; multifile:yes)

# --- 27B-decomposed from roadmap [2026-09-11]: Remove dead fix-first stub router — backend/app/routers/fix_first.py is a leftover stub (` (review + tweak) ---
- [ ] [T1] backend/app/routers/fix_first.py — Delete the file entirely as it contains only a dead stub router with no logic. VERIFY: `test ! -f backend/app/routers/fix_first.py`. (cat:refactor; multifile:no)
- [ ] [T2] backend/app/main.py — Remove the import statement `from app.routers import fix_first` located at line 12. VERIFY: `grep -q "from app.routers import fix_first" backend/app/main.py && exit 1 || exit 0`. (cat:python; multifile:no)
- [ ] [T3] backend/app/main.py — Remove the router registration call `app.include_router(fix_first.router)` located at line 71. VERIFY: `grep -q "include_router(fix_first" backend/app/main.py && exit 1 || exit 0`. (cat:python; multifile:no)
- [ ] [T4] backend/app/routers/__init__.py — Verify no import of `fix_first` exists in the package init to ensure clean module loading. VERIFY: `grep -q "fix_first" backend/app/routers/__init__.py && exit 1 || exit 0`. (cat:python; multifile:no)
- [ ] [T5] backend/tests/test_api_surface.py — Add a test asserting that `GET /fix-first` returns a 404 status code to confirm the dead endpoint is removed. VERIFY: `pytest backend/tests/test_api_surface.py::test_fix_first_endpoint_removed -v`. (cat:test; multifile:no)
