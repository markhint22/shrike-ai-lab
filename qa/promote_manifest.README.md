# qa/promote_manifest.py + qa/rollback_drill.py - Phase 5 manifest-driven promote groundwork (SHADOW)

Plan reference: Phase 5 ("Promote becomes the SHA-based, manifest-driven one") and 5A ("one rollback drill per promoted repo").

## The manifest
`python3 qa/promote_manifest.py generate --repo R [--candidate SHA] [--prior-tag TAG] [--out-dir D] [--no-write]` writes `state/promote_manifests/<repo>-<YYYYMMDD-HHMMSS>.json` and appends ONE ledger event
(`type: promote_manifest`, keyed per repo / sha12 / stamp). Fields: `candidate_sha`, `release_branch` (a `release/*` branch at the candidate, else null), `main_sha`, `prior_prod_tag {tag, sha, ts}` (the newest
`prod-<ts>-<repo>` tag that is not the candidate: the rollback anchor; null on a first promote), `batch {commits, merges, features, fixes}`, `gates {gate: {verdict, rows, fail_rows, latest_ts}}` (QA shadow rows whose
HEAD commit is in `prior_tag..candidate`; the release planner's exclusions apply: staged_shadow baseline rows, environment gates), `staging {verdict, relation, staging_sha, match}` + `soak_hours` (live only),
`decision` HOLD | PROCEED | PROCEED-UNVERIFIED, `summary` (starts with the decision), `rollback.command`.
* HOLD: a code-facing gate has a FAIL in the range, an environment gate (staging_check, release_candidate, staging_smoke, staging_e2e) FAILed ON the candidate, or staging is a known mismatch (behind / diverged / latest deploy failed).
* PROCEED-UNVERIFIED: no HOLD, but a gate is UNVERIFIED, a FAIL row cannot be resolved to a commit, staging could not be matched, or there is no prior prod tag. Infra gaps never HOLD (same rule as promote_gate.py).
* The decision is ADVISORY. `daily_promote.sh` / `promote_to_prod.sh` are NOT edited; the exact patch is `qa/patches/promote_manifest.md`.
`history --repo R [--n 1]` rebuilds manifests of the last N real promotes from the tags (staging evidence is marked "history: not reconstructible"). Acceptance on the Mac clones with a copy of the box state:
billwatch (prod-20261017-0900, prior prod-20261016-0900, 22 commits), iptv_apps (prod-20261017-0900, prior prod-20261016-0900, 6), shrike-labs-website (prod-20261013-0900, prior prod-20261009-0900, 1): valid JSON, prior tag present.
Gate lists are empty there because the box shadow rows were restarted after the 2026-10-16 wipe and their refs are fresher than those promotes.

## The rollback drill
`python3 qa/rollback_drill.py run --repo R [--tag T] [--smoke-cmd "CMD"] [--no-record]`: scratch `git clone --shared` (removed afterwards, guarded: only `rbdrill-*` directly under the temp root), detached checkout of the PREVIOUS
prod tag (second newest; `--tag` to choose), byte-for-byte check (tree id equals the tag's, `git diff` empty, nothing modified or untracked), then an offline smoke with a scrubbed environment: your `--smoke-cmd` /
`OVN_ROLLBACK_SMOKE_CMD_<REPO>`, else `compileall` over the tracked python files and a `package.json` parse (the npm build is not run: it needs the network). PASS / FAIL / UNVERIFIED (identical restore but nothing to smoke);
row appended to `state/qa_shadow/rollback_drill.jsonl`. DB downgrades are out of scope. Operator-run (not in cron).

## Flag `OVN_QA_PROMOTE_MANIFEST=off|shadow` (default shadow; `enforce` and anything else behave as shadow; off also disables the drill)
## How to promote to enforce (later, deliberate)
1. Apply Edit 1 of `qa/patches/promote_manifest.md` and read a week of manifests next to what actually got promoted: would HOLD have been right? how often PROCEED-UNVERIFIED and why?
2. Run the drill once per promoted repo (billwatch, iptv_apps, shrike-labs-website) and keep the PASS rows as the "rollback drill result per repo" metric.
3. Only then wire HOLD into the per-repo gate in `promote_to_prod.sh` (Edit 2 of the patch: HOLD skips the repo like the staging-evidence block; PROCEED-UNVERIFIED keeps promoting). Rollback = flag off.
Tests: `scripts/test/test_qa_promote_manifest.py` (78 checks incl. HOLD on a FAIL gate, prior tag, staging match / mismatch / soak, history for the three promoted repos, byte-for-byte restore, failure injection, mutants).

## Review fixes (2026-10-17)
* `rollback_drill` (and wip_cap / gpu_ledger / promote_manifest) are in `release_candidate.NON_CODE_GATES`: a drill FAIL row (ref = a prod tag, not a commit) can no longer become an unresolved FAIL that downgrades every release PASS, and `gate_verdicts` ignores those rows. It still lands in `qa_shadow/rollback_drill.jsonl` for operators.
* PROCEED-UNVERIFIED also when no code-facing gate row lies in the range (vacuous pass), and (opt-in) when fewer than `OVN_QA_MANIFEST_COVERAGE_PCT` percent of the batch commits carry a gate row (default 0 = off).
* Drill smoke on a non-python stack (native / engine project file in the tree, or python < 25% of tracked files, no `OVN_ROLLBACK_SMOKE_CMD_<REPO>`) is "partial": the verdict is capped at UNVERIFIED.
