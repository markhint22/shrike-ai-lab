`semantic_query`/`search_similar` on `vector_store.py`, a `VSCodeEnhancedReviewCommand` command, an
"extract `_enrich_review_result` helper" refactor — all *after* the 2026-09-05 pivot). That guard failed
because it was phrased as file-level "don't touch X," which a scout reasoning from task *intent* can
route around by inventing a plausible-sounding task against the same file ("improve scoring," "add a
helper," "wire up a command") without ever re-deriving *why* the file shouldn't grow. Read this as intent,
not a blocklist:

**gitlark's product is the planner → dispatch → review PWA described in `GITLARK_V2_PLAN.md` (merged into
`/Users/mhintermeister/LocalProjects/shared/ROADMAP_2YEAR.md`, search "### gitlark"). It is not, and will
never again be, a standalone PR-diff-review / static-code-analysis tool.** "Reviewing" in this product
means one thing only: reading back the fleet's own commits/PRs on a dispatched task and approving/merging
them (`pull_requests.py` / `PullRequestsPage.vue` — the P4 loop). It does NOT mean: scoring an arbitrary
diff, running an AI code reviewer against arbitrary repos, semantic/vector search over a codebase for
review purposes, or configuring reviewer prompt rules. **Any task that would add capability, tests, or
"polish" to that second meaning is out of scope, no matter how mechanical or well-formed the task reads,**
because there is no plan to ever ship that product again — it's not "unfinished," it's *retired*.

**Legacy/frozen — do not add features, tests, refactors, or helpers to these, even for
"cleanup"/"hardening"/coverage tasks (the fact that a file has an item in the queue does not mean it's
in-scope; check this list first):**
- `backend/app/services/code_review_agent.py`, `backend/app/routers/code_review.py` — the AI-reviews-a-diff
  engine. Frozen. Bug fixes only if it's actively breaking something the *current* product depends on
  (check callers before assuming that).
- `backend/app/services/search.py`, `backend/app/services/vector_store.py`, `backend/app/services/snippet.py`
  and the semantic-search/embedding surface generally — built for "search your codebase to inform a code
  review," a use case that no longer exists in this product. Frozen.
- `backend/app/services/review_rule_templates.py`, `backend/app/routers/review_rules.py`,
  `web/src/pages/ReviewRulesPage.vue`, `web/src/stores/reviewRules.ts` — configuring an AI reviewer's
  prompt. Frozen.
- `backend/app/routers/pull_requests.py` (the diff-viewer parts specifically — file-by-file patch
  rendering) and `web/src/pages/PullRequestsPage.vue` — **careful, this one is dual-purpose**: it is
  *also* currently the closest thing to the P4 "review the fleet's own PRs" screen, so it stays and may
  get P4-relevant additions (surfacing which dispatched task/plan a PR came from, fleet build status).
  What's out of scope is generic diff-review polish unrelated to fleet-dispatch status (inline comments,
  review-collaboration/real-time cursors, suggested-fix application, severity scoring of arbitrary diffs).
- `backend/app/services/code_quality_metrics.py`, `backend/app/services/ml_code_insights.py`,
  `backend/app/services/architecture_analysis_agent.py` — standalone code-analysis/ML-insights engines
  with no caller in the current product. Frozen; being wound down via the `code_review_agent` cleanup
  already in flight — don't add to them in the meantime.
- The VSCode extension's review-command surface (`VSCodeEnhancedReviewCommand` and similar) — same
  reasoning: extending IDE-side review tooling is old-product work.

**Deleted 2026-09-18 as verified-dead (zero real callers, not reachable from any route or nav link — do
not re-add or "restore" these if a stale task references them):** `web/src/components/CodeReviewPanel.vue`,
`web/src/components/EnhancedCodeReview.vue`, `web/src/components/ReviewCollaborationManager.vue` (these
two only ever imported each other; no page rendered either), `web/src/pages/CodeInsightsPage.vue` (routed
at an orphaned `/workspaces/:id/insights` path with no nav link, and its "analysis" was 100% hardcoded
mock data — not a real feature).

**Before generating any task touching a file with "review," "search," "insight," "quality," or "vector" in
its name: first ask "does this serve planning a repo change, dispatching it to the fleet, or reading back
the fleet's own result?" If the honest answer is no, the task is legacy-identity work — do not queue it,
regardless of how clean or "good hygiene" it looks in isolation.**
