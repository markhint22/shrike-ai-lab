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

# --- 27B-decomposed from roadmap [2026-09-11]: Remove dead fix-first stub router — backend/app/routers/fix_first.py is a leftover stub (` (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-13]: Surface overall suite health badge on Flake Dashboard — backend/app/utils/suite_health.py' (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-13]: Wire tiered flake-severity badges into the Flake Dashboard — backend/app/utils/flake_indic (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-13]: Consolidate duplicate status-color helpers and wire flaky coloring into the run list — thr (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-13]: Remove dead duplicate select_by_tag helper — backend/app/utils/test_selection.py's `select (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-13]: Add unit tests for the flakes Pinia store — frontend/src/stores/flakes.js (fetchFlakes, se (review + tweak) ---
- [ ] [T1] frontend/src/stores/__tests__/flakes.test.js — Create the test file with mocked axios and Pinia setup following the pattern in frontend/src/stores/__tests__/testRuns.test.js. VERIFY: `npx vitest run frontend/src/stores/__tests__/flakes.test.js` passes with 0 tests (or skips) initially, confirming the file exists and imports resolve. (cat:test; multifile:no)
- [ ] [T2] frontend/src/stores/__tests__/flakes.test.js — Add a test case verifying that `fetchFlakes` populates the `flakes` state array with the mocked response data on success. VERIFY: `npx vitest run frontend/src/stores/__tests__/flakes.test.js -t "successful fetch"` passes. (cat:test; multifile:no)
- [ ] [T2] frontend/src/stores/__tests__/flakes.test.js — Add a test case verifying that `fetchFlakes` sets the `error` state and leaves `flakes` empty when the axios request rejects. VERIFY: `npx vitest run frontend/src/stores/__tests__/flakes.test.js -t "fetch error"` passes. (cat:test; multifile:no)
- [ ] [T2] frontend/src/stores/__tests__/flakes.test.js — Add a test case verifying that `setQuarantine` updates the specific entry in the `flakes` array in place on successful API response. VERIFY: `npx vitest run frontend/src/stores/__tests__/flakes.test.js -t "setQuarantine success"` passes. (cat:test; multifile:no)
- [ ] [T2] frontend/src/stores/__tests__/flakes.test.js — Add a test case verifying that `setQuarantine` surfaces the API error message in the `error` state when the request fails. VERIFY: `npx vitest run frontend/src/stores/__tests__/flakes.test.js -t "setQuarantine failure"` passes. (cat:test; multifile:no)
- [ ] [T3] frontend/src/stores/flakes.js — Ensure the `fetchFlakes` action correctly handles loading state and error propagation to match the test expectations for empty data on error. VERIFY: `npx vitest run frontend/src/stores/__tests__/flakes.test.js` passes all tests. (cat:typescript; multifile:no)
- [ ] [T3] frontend/src/stores/flakes.js — Ensure the `setQuarantine` action correctly updates the local state array and handles error messages to match the test expectations for in-place updates and error surfacing. VERIFY: `npx vitest run frontend/src/stores/__tests__/flakes.test.js` passes all tests. (cat:typescript; multifile:no)
