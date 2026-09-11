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
- [ ] [T1] backend/app/utils/pr_comment_body.py — Add `build_pr_comment_body()` function that constructs a markdown string with status, duration, and link to the run. VERIFY: `pytest backend/tests/test_pr_comment_body.py::test_build_pr_comment_body` (cat:python; multifile:no)
- [ ] [T1] backend/app/utils/pr_comment_marker.py — Add `get_pr_comment_marker()` function that returns a unique HTML comment string for identifying bot comments. VERIFY: `pytest backend/tests/test_pr_comment_marker.py::test_get_pr_comment_marker` (cat:python; multifile:no)
- [ ] [T2] backend/app/services/github_ci.py — Add `post_or_update_pr_comment()` async function that accepts repo, pr_number, token, and body, performs GET on comments, checks for marker, and executes PATCH or POST accordingly. VERIFY: `pytest backend/tests/test_github_ci.py::test_post_or_update_pr_comment_new` (cat:python; multifile:no)
- [ ] [T2] backend/app/services/github_ci.py — Add logic to `post_or_update_pr_comment()` to handle the case where an existing comment with the marker is found, updating it via PATCH. VERIFY: `pytest backend/tests/test_github_ci.py::test_post_or_update_pr_comment_existing` (cat:python; multifile:no)
- [ ] [T3] backend/app/services/execution_engine.py — Import `post_or_update_pr_comment` and call it within the CI-linked run completion block near `update_check_run()` to post results to the PR. VERIFY: `pytest backend/tests/test_execution_engine.py::test_ci_run_posts_pr_comment` (cat:python; multifile:no)
- [ ] [T3] backend/app/services/execution_engine.py — Ensure `post_or_update_pr_comment` is only called when the run is associated with a GitHub PR and has valid repository context. VERIFY: `pytest backend/tests/test_execution_engine.py::test_non_ci_run_skips_pr_comment` (cat:python; multifile:no)
- [ ] [T4] backend/app/services/github_ci.py — Refactor `post_or_update_pr_comment` to accept a generic `http_client` or use the existing session manager for dependency injection, ensuring testability without mocking global requests. VERIFY: `pytest backend/tests/test_github_ci.py::test_post_or_update_pr_comment_injection` (cat:python; multifile:yes)
- [ ] [T4] backend/app/services/execution_engine.py — Update the call site to pass the necessary GitHub token and repository details from the run's CI metadata to `post_or_update_pr_comment`. VERIFY: `pytest backend/tests/test_execution_engine.py::test_ci_run_passes_correct_metadata` (cat:python; multifile:yes)

# --- 27B-decomposed from roadmap [2026-09-11]: Visual-regression diff flagging — backend/app/utils/visual_diff.py (diff_ratio, is_visual_ (review + tweak) ---
- [ ] [T1] backend/app/utils/visual_diff.py — Implement `diff_ratio(image_a: bytes, image_b: bytes) -> float` using Pillow to compute normalized pixel difference. VERIFY: `pytest backend/tests/test_visual_diff.py::test_diff_ratio_identical -v`. (cat:python; multifile:no)
- [ ] [T1] backend/app/utils/visual_diff.py — Implement `is_visual_regression(ratio: float, threshold: float = 0.05) -> bool` to flag regressions based on ratio. VERIFY: `pytest backend/tests/test_visual_diff.py::test_is_visual_regression_threshold -v`. (cat:python; multifile:no)
- [ ] [T2] backend/app/models/test_run.py — Add `is_visual_regression: Mapped[bool] = mapped_column(Boolean, default=False)` to the `TestResult` model. VERIFY: `grep -q "is_visual_regression" backend/app/models/test_run.py`. (cat:schema; multifile:no)
- [ ] [T3] backend/alembic/versions/009_visual_regression.py — Create migration adding `is_visual_regression` boolean column to `test_results` table. VERIFY: `alembic upgrade head && alembic downgrade -1`. (cat:schema; multifile:no)
- [ ] [T3] backend/app/services/execution_engine.py — In `_process_step_result`, fetch previous run screenshot for same `test_plan_name`, compute `diff_ratio`, and set `result.is_visual_regression`. VERIFY: `pytest backend/tests/test_execution_engine.py::test_visual_regression_flag_set -v`. (cat:python; multifile:no)
- [ ] [T3] backend/app/routers/test_runs.py — Ensure `TestResult` serialization includes `is_visual_regression` field in API response. VERIFY: `curl -s localhost:8000/api/test-runs/1 | jq '.results[0].is_visual_regression'`. (cat:endpoint; multifile:no)
- [ ] [T3] frontend/src/stores/testRuns.js — Update `testRuns` store mapping to include `isVisualRegression` from API payload. VERIFY: `grep -q "isVisualRegression" frontend/src/stores/testRuns.js`. (cat:typescript; multifile:no)
- [ ] [T4] frontend/src/pages/TestRunDetailPage.vue — Add conditional badge component displaying "Visual Regression" when `result.isVisualRegression` is true. VERIFY: `grep -q "Visual Regression" frontend/src/pages/TestRunDetailPage.vue`. (cat:vue; multifile:yes)
