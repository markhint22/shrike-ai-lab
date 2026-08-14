# Local LLM Upgrade Plan — Tailscale, Overnight Runner, Local Training

Status doc for three related efforts. Written 2026-07-31 while offline; updated
2026-08-02 after a full session back on the home LAN where almost everything
below got tested and fixed for real.

---

## 1. Tailscale

**Status: DONE, 2026-08-03.** Both Mac and GPU server logged into the same
tailnet (account `markhint30@gmail.com`). Confirmed with a real `tailscale
ping` (not just `tailscale status`) — got a genuine `pong`. Tailscale IPs:
- Mac: `100.111.36.84`
- GPU server (`markhint-server1`): `100.79.64.64` — also resolves via
  MagicDNS as `markhint-server1`.

All configs switched from the LAN IP (`192.168.68.145`) to the Tailscale IP,
so everything below works both on and off the home network (Tailscale
auto-picks the direct LAN path when available, relays otherwise — no
downside to using it even while home):
- `shrike-ai-lab/.env`: `GPU_SERVER_HOST`, `LITELLM_BASE_URL`,
  `LLAMA_SERVER_URL`, `TAILSCALE_IP` all updated. Old LAN IP kept as
  `GPU_SERVER_LAN_IP` for reference.
- `~/.continue/config.yaml`: all 4 models' `apiBase` updated.
- `Makefile`'s `overnight-server-deploy` target had a latent bug — used a
  shell fallback default (`${GPU_SERVER_HOST:-192.168.68.145}`) that would
  silently keep using the stale LAN IP forever since that env var was never
  actually exported to the shell (only set in `.env`). Fixed to source
  `.env` directly instead of relying on a hardcoded fallback, so it can't
  go stale like this again.
- Verified end-to-end after the switch: `make gpu-status`, `make gpu-test`,
  `make overnight-smoke`, `make overnight-server-status` all pass via the
  Tailscale IP.
- Not checked/updated: Cline's base URL (no Cline config found in the usual
  VS Code extension storage location on this Mac — may not be actively
  configured; update manually if you do use it somewhere).

**Gotcha hit during setup, for next time**: the browser login link from
`tailscale up` authorizes *whichever device requested it* (the server, in
this case) regardless of which device's browser you open it in — that's
intentional, it's how headless server auth is supposed to work (approve
from your phone, authorizes the server). The confusing part: each link is
one-time-use — if you open it and it does anything (including completing
on an unexpected device), it's consumed and a stale copy of the same link
won't work again. Also: also had a device silently show as "offline"/have
zero peers for a bit after first login — turned out to be from a botched
first attempt (see above), not a real propagation delay; a clean
`tailscale logout` + `tailscale up` cycle on the server fixed it.

---

## 2. Overnight local-LLM task queue

**Status: fully rebuilt and live-tested 2026-08-03 as a multi-week, 7-repo,
12x/day autonomous fleet — all server-resident, zero Mac dependency.**

**MAJOR CHANGE 2026-08-02: moved to the GPU server, cron-scheduled.** The
original design ran on the Mac (launchd + `pmset` wake), which only works if
the Mac is home, awake, and on the LAN every night — useless once it travels
(vacation). The whole queue now runs natively on the always-on Linux GPU
server via cron. `agents/overnight/run_overnight_server.sh` (deployed to the
server as `~/overnight-queue/run_overnight.sh`) is the source of truth;
`train_job` does `docker stop`/`docker start` locally instead of SSHing back
to itself. New git identity + SSH key on the server so it can push
independently of the Mac being present.

**MAJOR CHANGE 2026-08-03: scaled to a 7-repo, 2-hourly, self-directing
fleet with persistent branches.** Per the user's decision (every-2-hours
cadence, all personal-workspace repos in scope), all 7 active repos
(billwatch, gitlark, task-manager-platform, shrike-labs-website, iptv_apps,
social-media-manager, test-automation-agent) are cloned on the server under
`~/overnight-queue/repos/` and each has a recurring `ongoing-<repo>` task in
`tasks.json` (source template: `agents/overnight/recurring_tasks.json`).
Cron fires every 2 hours (`0 */2 * * *`, was previously once nightly).

Each recurring task uses `"persistent_branch": true` — a single
`overnight/feature` branch per repo that accumulates commits across every
run for weeks, instead of the old one-shot `overnight/<run>/<id>` branch
that reset every time. `run_aider_fix_task()` in the runner only resets that
branch from the default branch the *first* time it's ever seen; every
subsequent run checks it out as-is (verified live: two consecutive test
runs produced two stacked commits on `overnight/feature`, no reset).

Each task's workflow: check `OVERNIGHT_PROGRESS.md` → if it's still a stub,
read the README and fill in a Current Status + 5-10-item Next Steps list; if
it already has real content, implement the single top not-done item
(minimal, focused, tested if the project has a test setup, honest about
what was/wasn't actually run), update the doc, commit both together. Never
touches `main`/`develop`.

**Reliability issues found and fixed via live testing (2026-08-03) — read
before assuming a "no-op" or silent run is fine:**

1. **Context-window overflow silently misreported as a harmless no-op.**
   The loaded model's real ceiling is **16,384 tokens** (confirmed via
   `curl .../v1/models` → `max_input_tokens`), not the 32000 some client
   configs claim. When a task asked the model to review 7 files at once
   for its initial survey, the API call failed with
   `litellm.ContextWindowExceededError` but aider still exited 0 — the
   simple before/after-SHA no-op check couldn't tell that apart from a
   genuine "nothing to do." **Fixed**: `run_aider_fix_task()` now greps the
   task log for `ContextWindowExceededError|BadRequestError|APIError|
   RateLimitError|Traceback` and reclassifies that as
   `error(model/API error - see log)`, which the consecutive-failure safety
   valve (3-in-a-row auto-pause) does catch. Prompts were also tightened to
   ask for at most 1-2 files at a time — this reduces but does **not
   eliminate** overflows on genuinely multi-file features (aider's own
   repo-map / follow-up file requests can still pull in more than asked;
   confirmed live — one run tried to pull in 7 files mid-task despite the
   instruction and correctly errored out safely, no bad commit).
2. **The model unreliably synthesizes brand-new prose files via aider's
   udiff edit format** — sometimes the diff hunk fails to apply at all
   (silent no-op, nothing committed), sometimes it applies but produces a
   **0-byte empty file that still gets committed** (confirmed live: a
   `feat: add overnight progress tracking document` commit with `0
   insertions`). This is specific to synthesizing new content from
   nothing — editing existing files works reliably. **Fixed**:
   `run_aider_fix_task()` now stubs `OVERNIGHT_PROGRESS.md` out itself via a
   plain bash heredoc (a separate `chore: stub OVERNIGHT_PROGRESS.md` commit,
   no LLM involved) the first time a task whose prompt references that
   filename runs against a repo that doesn't have it yet — aider then only
   ever has to *edit* an existing file, never conjure one from scratch.
3. **The model occasionally returns a degenerate near-empty completion**
   (observed: "Tokens: 12k sent, 5 received", output was just a couple of
   filenames) for no clear reason — not a script bug, just local-model
   variance (possibly related to the self-speculative decoding setup).
   Classified as a harmless `no-op` (nothing committed, nothing corrupted);
   self-heals on the next 2-hourly retry. **Known gap**: because repeated
   no-ops don't increment the failure counter (by design — a genuine "no
   changes needed" shouldn't trip the safety valve), there's currently no
   alert if a task no-ops for days straight. Worth watching via
   `queue.sh report` / `queue.sh log <task-id>` rather than assuming silence
   means healthy progress.

None of the above caused data loss or a false "success" — worst case is a
wasted ~10-30s cron cycle, always correctly logged as either `no-op` or
`error(...)`, never as a false `pushed`.

**INCIDENT 2026-08-04 to 2026-08-08 — the fleet went silently idle for 4
days.** The queue ran well for its first ~9 hours (2026-08-03 21:00 through
2026-08-04 06:00, ~5 cycles), then `ongoing-gitlark` got stuck retrying the
*exact same* item 3 runs in a row — a genuinely multi-file feature that
always needed ~21,290 tokens against the 16,384-token ceiling, and since a
failed attempt never marks anything done, it just repeated forever. The
safety valve correctly detected this and auto-paused... but at the time it
paused the **entire queue**, not just the stuck task, so all 6 healthy repos
sat idle for 4 days with nobody noticing (no-ops don't trip any alert, and
nothing was watching `queue.sh status` in the meantime). Real productive
work had landed on 3/7 repos before the pause (shrike-labs-website: 4
commits incl. accessibility fixes; iptv_apps: 1 commit, stream-discovery
tests; social-media-manager: 1 commit, SQLAlchemy models) — nothing was
lost, but 3/7 repos (billwatch, task-manager-platform, test-automation-agent)
never got past their initial progress doc at all.

Root-caused and fixed on 2026-08-08:

1. **Safety valve now disables only the offending task**, not the whole
   queue (`check_and_record_failure()` sets that one task's `enabled:false`
   via `jq` instead of touching the global `state/PAUSED` flag). The global
   pause flag still exists for your own manual pause/resume, it's just no
   longer auto-triggered by a single task's failures.
2. **`queue.sh status` now surfaces disabled tasks directly**, distinguishing
   auto-disabled-by-safety-valve (has a `state/failures/<id>.count` file)
   from manually-disabled, so this specific silent-for-days failure mode is
   visible at a glance going forward.
3. **Root cause of the 3 stalled repos, found by reading their logs
   closely**: aider's single-shot `--message` mode does not loop back after
   the model asks to add more files mid-conversation — if the model's first
   move is "please add file X", the run just ends there with nothing done.
   All 3 stalled repos showed exactly this pattern. **Fixed**:
   `run_aider_fix_task()` now does an iterative file-feeding dance —
   pass 1 asks (read-only) which files it needs; each subsequent pass
   (up to `MAX_IMPLEMENT_ATTEMPTS=2`) pre-loads newly-mentioned existing
   files via aider's `--file` flag and retries, stopping early on a real
   commit or once a retry surfaces no new file. A related bug in the first
   version of this fix: naively matching "any line that's an existing file
   path" against the whole log kept picking up `README.md`/
   `OVERNIGHT_PROGRESS.md` as "requested files", because aider silently
   auto-adds any file *mentioned in the message text itself* and echoes
   that as a bare filename line — indistinguishable from a real model
   answer under a pure exists-on-disk check, and it wasted the file budget
   on it every time. Fixed by excluding `.md` files from candidates and by
   extracting path-like tokens from each line instead of requiring the
   whole line to be a bare path (the model often appends trailing prose on
   the same line as the path). **Verified live**: `test-automation-agent`,
   which had stalled every single cycle before this, pushed a real commit
   on the first test run after the fix.
4. **Separately found while testing the above (pre-existing, not caused by
   this session's changes): no lock against two `run_overnight.sh`
   invocations running concurrently.** A slow manual `run-now` was still
   in progress when the next scheduled cron tick fired, producing two
   processes walking `tasks.json` at the same time — no corruption resulted
   this time (checked every repo's `git status`/HEAD directly afterward),
   but two processes racing `git checkout`/`commit` on the same working
   copy is a real risk, and both aider calls competing for the one
   inference container just slows everything down further, making the next
   overlap more likely. **Fixed**: a non-blocking `flock` on
   `state/run.lock` right after startup — if another run is already in
   progress, the new invocation logs a message and exits immediately rather
   than queuing up behind it. Verified live: a deliberately-started second
   invocation correctly detected the lock and exited without touching
   anything.

**HARDENING PASS 2026-08-08 — real test verification instead of trusting
self-report, plus a shared quality bar.** Prompted by the user asking for
process hardening and enforced coding standards/test coverage. Changes:

1. **Shared quality-bar suffix**, appended by the runner to every
   `aider_fix` prompt (`STANDARDS_SUFFIX`) rather than copy-pasted into
   each task definition: match existing code style, keep diffs minimal and
   focused, use the project's existing test framework/location convention,
   don't add new dependencies unnecessarily. Applies automatically to
   future one-off tasks added via `queue.sh add` too.
2. **Explicit aider model-metadata** (`agents/overnight/model-metadata.json`
   → `--model-metadata-file`) telling aider the real 16,384-token ceiling,
   instead of "Unknown context window size, using sane defaults". Confirmed
   live this changes aider's own behavior — it now pre-warns ("Your
   estimated chat context of 17,110 tokens exceeds the 16,384 token limit")
   before sending, instead of only finding out from the API's rejection.
3. **Real post-commit test verification**, not just the prompt asking the
   model to self-report. `run_repo_verification()` runs whatever test
   suite is *already provisioned* in the repo (a real `.venv/bin/pytest` or
   `node_modules` + a package.json `test` script) after every commit, and
   puts the true result into both the log and the report status:
   `pushed(tests:pass)` / `pushed(tests:FAIL - see log)` / plain `pushed`
   if nothing's provisioned. Deliberately does **not** feed into the
   consecutive-failure safety valve — a real regression and an
   environment/flake-caused failure look identical here, and auto-disabling
   a task over the latter would be worse than just surfacing it.
   - **To make this have real teeth** (not a no-op — none of the 7 repos
     had dependencies installed on the server, fresh clones only), node/npm
     were installed on the server (missing entirely - `sudo apt-get install
     nodejs npm`, got Node 22 from the default repo) and every repo's
     backend (`python3.12 -m venv .venv`, `pip install -r requirements.txt`,
     plus `pytest pytest-asyncio pytest-cov pytest-timeout httpx`) and
     frontend (`npm install`) were provisioned once, directly - not something the
     2-hourly cron re-does, so it'll drift stale over time; re-provision by
     hand if a repo's dependencies change enough that verification starts
     erroring on missing packages rather than real code issues.
   - **`CI=true` gotcha**: several repos' `package.json` `test` script is
     plain `"vitest"` (not `"vitest --run"`), which defaults to interactive
     watch mode outside CI and would hang until the timeout killed it.
     Fixed by exporting `CI=true` for the npm test call - vitest/Jest/CRA
     all respect it to run once and exit.
   - **Hang protection**: both the `aider` calls and the verification test
     runs are wrapped in `timeout` (600s / 120s) - found live that `pytest`
     can genuinely hang (a real test in iptv_apps did) and an unbounded
     hang combined with the concurrency lock would freeze the queue
     permanently until someone manually intervened.
   - **A bug in the verification code itself, found and fixed before fully
     trusting it**: the helper computing which directory a discovered
     `.venv/bin/pytest` belongs to used `dirname` twice, which strips one
     path component too few (`./backend/.venv/bin/pytest` → `./backend/
     .venv`, not `./backend`) - this made pytest silently fail to even
     execute (`No such file or directory`) and get misreported as
     `tests:FAIL`, when the real test suite was actually fine. Fixed with
     parameter-expansion suffix stripping (`${venv_pytest%/.venv/bin/
     pytest}`) instead of counting `dirname` calls, and verified directly
     against a real repo before trusting the mechanism.
4. **Real, pre-existing bugs found and fixed by finally running each
   repo's test suite for the first time** (all on `overnight/feature`,
   nothing merged to main/develop):
   - **billwatch**: the AI's own earlier commit had created `congress.py`
     using `from app.config import settings` (a singleton that doesn't
     exist anywhere else in the codebase - every other file uses
     `get_settings()`) and the wrong attribute casing; separately,
     `bill_background.py` imported `get_db` from `app.core.database`,
     which doesn't exist (`get_db` actually lives in `app.database`). Both
     would have broken the app at import time. Fixed; full suite now 127
     passed (was failing to even collect).
   - **gitlark**: `requirements.txt` was missing `aiosqlite` and
     `apscheduler`, both genuinely imported by the app. Fixed;
     151 passed / 4 skipped / 1 flaky performance-timing test (server-load
     sensitive, not a real bug).
   - **test-automation-agent**: `TestOrchestrator` had two methods both
     named `parse_test_plan` - two *prior* overnight commits each claimed
     to "remove the duplicate" but never actually did, since Python
     silently lets the second definition shadow the first with no error.
     `initialize()` was left referencing an undefined `questions` name that
     used to live in the shadowed method, breaking the real `/test_runs`
     endpoint, not just tests. Merged the logic into `initialize()` and
     removed the duplicate. Verified: 29 previously-failing tests instantly
     fixed (360 passed, was 331 passed / 29 failed).
   - **social-media-manager & task-manager-platform frontends**: both
     `vitest.config.ts`/`tests/setup.ts` were copy-pasted from a shared
     "standard Vue project" template without adapting them - task-manager-
     platform is a **React** app but its config imported
     `@vitejs/plugin-vue` and its setup imported `@vue/test-utils` (neither
     installed, both wrong framework). Fixed by swapping to
     `@vitejs/plugin-react`/`@testing-library/jest-dom` (already a real
     devDependency). Both also: were missing `happy-dom` as a dependency
     despite the config requiring it; had an `include` pattern that only
     matched `tests/**`, while the real unit tests live under
     `src/**/*.test.{ts,tsx}` (zero tests were being found/run at all);
     and were letting vitest try to execute Playwright `tests/e2e/**`
     specs as unit tests (`test.describe` from the wrong package). Fixed
     all of it. Went from "config fails to even load" to 13/13 and 29/31
     passing respectively (task-manager-platform's remaining 2 are a real
     but minor content-mismatch in `Dashboard.test.tsx`, left noted).
   - **social-media-manager**: had a `.venv` accidentally committed to git
     from a *Mac* (shebang `#!/Users/mhintermeister/LocalProjects/social-
     media-manager/.venv/bin/python3.12`), pre-dating this session. This
     one directly undermined the new verification mechanism itself - the
     runner correctly found and tried to execute it, got a kernel-level
     "No such file or directory" (the interpreter path doesn't exist on
     the Linux server), and that false failure flipped the whole task's
     status to `tests:FAIL` even though the real backend suite (9 passed)
     was fine. `git rm --cached`, added `.venv`/`node_modules` to
     `.gitignore`. Re-verified: `pass`. Checked all other 6 repos for the
     same mistake via `git ls-files | grep .venv` - none had it.
5. **Real issues found that need actual design judgment, not a blind
   fix - flagged as the top item in each repo's `OVERNIGHT_PROGRESS.md`
   for a future cycle (with full context) or you to address, rather than
   guessed at**:
   - **task-manager-platform**: the AI's approval-workflow feature
     (`approval_service.py`) imports `ApprovalStep`/`ApprovalStepStatus`/
     `ApprovalHistory` from `app.db.models`, but those models don't exist
     there - they exist only in `app/models/approval.py`, which is dead
     placeholder scaffold code (its own comment says "assuming it exists -
     customize as needed", never wired to the real declarative Base). This
     needs someone (AI or human) to actually design the missing SQLAlchemy
     models, not a mechanical rename. **Update**: by the next cycle, the AI
     had already added `ApprovalStep`/`ApprovalStepStatus` correctly
     (matching the existing model style) - `ApprovalHistory` is still
     missing; the progress doc was updated to reflect this rather than
     restate the original (partially stale) problem.
   - **iptv_apps**: `test_stream_discovery_service.py` has three
     near-duplicate copies of the same test class (three separate overnight
     cycles each assumed no tests existed yet - a reminder to actually
     check `OVERNIGHT_PROGRESS.md`/existing test files before adding more),
     plus a newer test that calls the service's now-`async` method without
     `await`. Separately, three premium-status tests fail because a fresh
     user shows `is_premium: True` - this could be an intentional
     free-trial-for-new-signups feature the tests predate, or a real bug;
     flagged as a product-logic call rather than guessed at.

**Also found and fixed in passing**: the Mac's local disk was at 99%
capacity (185MB free) during this session, intermittently breaking tool
calls - unrelated to the queue itself, but worth clearing space soon.

**HARDENING PASS 2026-08-13 — fixed gitlark's repeated context overflow, plus two
broader discoveries.** User reported gitlark had been auto-disabled by the
safety valve for days and asked to fix it properly, tested live.

1. **Root cause for gitlark**: it's the largest repo in the fleet (344 files).
   Its baseline overhead alone - repo-map + the always-`--read` `AGENTS.md`
   (11.5KB) + the task prompt - already sat around 12-13k tokens *before* a
   single task file was loaded, leaving almost no room for the 1-2 real files
   any actual code change needs. Confirmed empirically in a clean sandbox copy
   (no accumulated `.aider.chat.history.md` to contaminate the numbers):
   reducing aider's `--map-tokens` alone barely helped (1024→0 saved only
   ~1k tokens - the repo-map was never the dominant cost here, despite the
   initial hypothesis). What actually worked: dropping `--read AGENTS.md`
   entirely for this repo (relying on `OVERNIGHT_PROGRESS.md` instead, which
   is what it's for) plus capping the file-request budget to 1 file instead of
   2 - verified a real single 23KB file fits comfortably (13k of 16,384) but
   two large files together still overflow even with everything else stripped.
   **Fix**: added three new optional per-task fields to `tasks.json`
   (`map_tokens`, `skip_agents_md`, `max_files`), threaded through
   `run_aider_fix_task()` and into the `AIDER_BASE_ARGS`/`SCOUT_PROMPT`/file-cap
   logic. Set for gitlark: `map_tokens: 0`, `skip_agents_md: true`,
   `max_files: 1`. **Verified live end-to-end** (not just token-counted) -
   directly invoked the real function against the real repo: a genuine commit
   landed (`test: add unit tests for ConversationService`, 177 lines), the
   test venv had to be provisioned for gitlark for the first time (never
   included in the original 7-repo provisioning), and the new tests actually
   pass (151 passed, 1 pre-existing flaky perf-timing test unrelated to this
   change). Followed by two more consecutive clean `no-op` cycles through the
   real queue - no context errors since.
2. **Bigger discovery made while investigating: `OVERNIGHT_PROGRESS.md` was
   never actually being loaded into the aider chat for ANY repo, this whole
   time.** It's excluded from `scan_for_new_files()`'s candidates (deliberately,
   since `.md` files were excluded to stop `README.md` false-positives back on
   2026-08-08) - but that same exclusion meant the doc was NEVER added via
   `--file` either, for any task, ever. The model has therefore always been
   editing this file "blind," without its real current content in context,
   generating diffs against a *guessed* version of the file. This is almost
   certainly the root cause of the duplicate "## Next Steps" sections found
   in iptv_apps and test-automation-agent on 2026-08-13 (and possibly other
   silent corruption never caught). **Fixed**: `OVERNIGHT_PROGRESS.md` is now
   always pre-loaded via `--file` (a new `PROGRESS_FILE_ARGS`, separate from
   and not counted against `max_files`, since it's small - typically 1-2KB) on
   every scout AND implement call, for every repo. Confirmed working
   immediately: the next real cycle showed `social-media-manager` complete a
   genuinely complex architectural fix I'd flagged the day before (consolidating
   three separate SQLAlchemy `Base()` instances into one) with a clean,
   correctly-updated, non-duplicated progress doc.
3. **Second bigger discovery: the model's real context is ONE shared
   16,384-token budget for prompt + response combined, not separate pools.**
   Confirmed straight from the llama.cpp server's own startup flags
   (`--ctx-size 16384`, standard llama.cpp semantics - covers total tokens in
   the KV cache, input and output together). The `model-metadata.json` written
   on 2026-08-08 declared `max_input_tokens: 16384` AND `max_output_tokens:
   4096` as if they were separate 16,384+4,096=20,480 token pools - directly
   contradicted by a real failure caught live: a task-automation-agent attempt
   had only ~14.6k input tokens (comfortably under the input figure) but the
   model tried to generate ~5,700 output tokens for a big new test file,
   blowing straight through the real combined ceiling
   (14.6k + 5.7k = 20.3k of 16,384). Also confirmed that `max_output_tokens` in
   the metadata is advisory only, not a hard request-level cap - the actual
   generation exceeded the stated 4,096 figure with no server-side truncation.
   **Fix**: lowered `max_input_tokens` to 10,000 (down from 16,384) to leave
   real headroom for whatever the model decides to generate, since output
   length can't be reliably capped from the client side. This is a global
   change (affects every task) and is *advisory only* - aider still attempts
   the request even after warning ("probably safe to try... most providers
   won't charge"), so it reduces risk but doesn't eliminate it. The reliable
   lever remains the per-task `max_files`/`skip_agents_md` controls from
   point 1, which actually reduce what gets sent.
4. **Also narrowed two specific stuck items found mid-session** (same
   "oversized item" pattern as before, not a new class of bug):
   iptv_apps' premium-trial-ambiguity item (flagged 2026-08-09, still
   unresolved by design - it needs a product call) kept getting retried and
   nearly tripped the safety valve investigating 3 test files at once -
   deprioritized to the bottom of its list rather than forced. test-automation-
   agent's "implement TestExecutor.run_step + tests" item overflowed on BOTH
   input (needed 2 real files) and output (tried to generate ~5,700 tokens in
   one turn) - split into navigate/click first, tests as a separate later item,
   type-action handling later still.
5. **Some tasks will still occasionally hit a real `ContextWindowExceededError`
   - this is expected, not a regression.** In the final full-queue validation
   run, billwatch/task-manager-platform/social-media-manager each hit one
   (all at failure-count 1, nowhere near the 3-in-a-row safety-valve
   threshold) while working on DIFFERENT, unrelated items that happened to
   need 2+ real files. This is an inherent characteristic of running a
   16k-context model autonomously against an evolving, arbitrary task list -
   some fraction of "next steps" items will always need more context than
   fits, and the safety valve (self-contains the specific stuck task, doesn't
   touch the rest of the queue) is the correct steady-state handling for that,
   not a bug to eliminate entirely.

**MODEL SWAP + CONTEXT OPTIMIZATION 2026-08-13 (same day, later) - moved the queue from
16,384 to a real 262,144-token context, and switched the production model from
35B-A3B to 9B.** User was concerned the 16k ceiling was fundamentally too small and
asked to try the 27B and 9B alternatives already partially staged in
`scripts/switch-active-model.sh`.

1. **The actual biggest lever wasn't model size at all - it was KV cache
   quantization.** Discovered via `docker exec ... llama-server --help` that
   llama.cpp supports `--cache-type-k`/`--cache-type-v` (default `f16`, can drop
   to `q8_0` for a clean 2x reduction) plus `--flash-attn on`. Empirically tested
   (raw `docker run`, not docker-compose, to iterate fast) on the *existing*
   27B and 35B-A3B models with these two flags added and `--ctx-size` raised
   from 16,384 all the way up: **262,144 tokens loaded successfully on 27B
   using barely more VRAM than the original 16,384 f16 setup** (22.6GB → 22.9GB).
   Pushing further to 1,048,576 hit two real walls: llama.cpp warned
   `n_ctx_seq (1048576) > n_ctx_train (262144)` (this model family's own trained
   context ceiling is 262,144 - going beyond that isn't just wasteful, the model
   was never trained to understand positions that far out) and then genuinely
   OOM'd. So **262,144 is both the real hardware ceiling and the model's own
   architectural ceiling** - a happy coincidence, not a coincidence I'd bank on
   for a different model family. The 27B/35B-A3B `llama_context` logs also
   showed `Gated Delta Net` warnings, suggesting a hybrid linear-attention
   architecture is *why* KV cache scales so cheaply here - a classic dense
   transformer would not behave this well.
   - 35B-A3B at 262,144: only ~75MB VRAM free - too risky for production
     (any request-size variance could OOM it). Capped at 131,072 instead.
   - 27B at 262,144: ~1.2GB VRAM free - comfortable, kept at the full 262,144.
   - 9B at 262,144: ~9.1GB VRAM free - very comfortable margin.
2. **Switched production to 9B specifically** (per user request, after
   confirming it's genuinely faster too - ~103 tok/s vs 27B's ~26 tok/s in
   direct testing, consistent with far fewer active params). This required more
   than just flipping a switch:
   - The target model (`Qwen/Qwen3.5-9B`, a different/older model generation
     than the 27B/35B-A3B's "Qwen3.6") had no official `ggml-org` GGUF - only
     a stray local draft-only file existed
     (`qwen35-9b-dflash-Q4_K_M.gguf`, ~0.7GB) and `switch-active-model.sh`
     explicitly refused to activate 9B for exactly this reason. Used WebSearch
     to confirm no `ggml-org/Qwen3.6-9B-GGUF` repo exists (control-checked
     against the real 27B repo's HTTP 200/302 vs the 9B repo's 401 on both the
     page and API - a repo that doesn't exist behaves differently from one
     that's merely gated), found the real target on
     `bartowski/Qwen_Qwen3.5-9B-GGUF` (5.75GB, matches expected size exactly),
     downloaded it, and verified the existing local draft file - never
     confirmed compatible before - actually works with it live (speculative
     decoding engages correctly, ~65-88% draft acceptance across test calls).
   - `litellm_config.yaml` had **no model_list entry for `qwen-dflash-9B` at
     all** - the first activation attempt got as far as "Active model is
     ready" (the llama-server health check passed) but the actual validation
     request failed with "Connection reset by peer", because litellm had
     nowhere to route the model name. Added a proper entry, matching the
     27B/35B-A3B pattern (including `chat_template_kwargs: enable_thinking:
     false`, verified live to actually suppress the wasted `<think>` reasoning
     tokens on real `/v1/chat/completions` calls - dropped a `READY` reply
     from 30+ reasoning tokens down to exactly 2).
   - `docker-compose.yml`'s `llama-dflash-35b` service had `--ctx-size 16384`
     and `--chat-template-file /models/deepflash/fixed_template.jinja`
     hardcoded, with no way to vary flash-attn/cache-type per model. Rewrote
     the `command` as a `sh -c` wrapper (`entrypoint: ["/bin/sh", "-c"]`) so
     `--ctx-size`, `--flash-attn`, `--cache-type-k/-v`, and an optional
     `--chat-template-file` block are all env-var driven
     (`DFLASH_CTX_SIZE`, `DFLASH_FLASH_ATTN`, `DFLASH_CACHE_TYPE_K/V`,
     `DFLASH_CHAT_TEMPLATE_ARGS`) - the 3.6-family template is wrong for the
     3.5-family 9B model (verified live that 9B's own auto-detected template
     works correctly without it), so 9B's env sets that var empty.
   - **A quoting bug self-inflicted while editing over SSH**: tried to
     heredoc-write the updated `switch-active-model.sh` directly on the
     remote host inside a single-quoted outer SSH command - a literal
     single-quote/apostrophe inside my own comment text broke out of the
     outer quoting and corrupted the script. Recovered by writing the file
     locally first (no shell-escaping risk) and `scp`-ing it up instead -
     same safe pattern already used all session for `run_overnight_server.sh`.
     Lesson: never heredoc a multi-line script with prose comments directly
     inside an SSH one-liner: write locally, scp up.
   - **A `set -euo pipefail` robustness bug found live**: the first real
     9B activation got as far as "Active model is ready" but then the
     validation `curl` hit a transient ~10-15s window right after litellm's
     own restart where it wasn't ready yet ("Connection reset by peer") -
     under `set -e` this aborted the whole script *before* it reached the
     final line that writes `runtime/active-model.txt`, leaving that file
     stale (still said `qwen-dflash-27B`) even though the model swap itself
     had genuinely succeeded. Fixed by retrying the validation call up to 5
     times (3s apart) inside an `if` (exempt from `set -e`) rather than
     letting a transient curl failure be script-fatal. Verified: the retry
     path itself fired live on the very next real run (failed 4 times,
     succeeded on the 5th) and the script completed cleanly end to end this
     time, including a correctly-updated tracking file.
3. **A real 9B-specific quality issue found via full-queue validation, not
   context-related at all.** After wiring 9B in and relaxing the
   context-driven per-task restrictions (gitlark's `map_tokens`/
   `skip_agents_md`/`max_files: 1`, and the "your context window is only
   16384 tokens" boilerplate baked into 6 of 7 tasks' prompts - all now
   updated to reflect the real ~200k-token budget), gitlark's very next real
   cycle hit the 600s `timeout` wrapper and errored with `exit=124` - not a
   context overflow, a genuine hang. The log showed why: during a single
   "implement attempt", the model produced **14,600+ lines** of output that
   was just an unbroken chain of "let me also check `cat some_file.py`...
   and this one... and this one..." for dozens of files in a row, never once
   stopping to actually write a diff. iptv_apps hit the identical pattern the
   same cycle (24,000+ lines). This is a real, specific 9B behavioral gap
   versus 35B-A3B/27B, not a context-budget problem - the smaller model is
   evidently less disciplined about "I have enough information, time to act"
   judgment, and will happily narrate an unbounded exploration chain if
   nothing stops it. This means the earlier "ask for at most N files, be
   economical" restrictions (removed earlier the same session, thinking they
   were purely about the old 16k budget) had actually been serving a second,
   independent purpose the whole time - keeping the model decisive, not just
   keeping requests small. **Fixed** by adding an explicit decisiveness
   instruction to `STANDARDS_SUFFIX` (not a token-budget framing, since that's
   no longer true - a discipline framing): "pick the files you need in ONE
   pass and stop... do not narrate a long chain of 'let me also check this
   file' before ever writing code." **Verified live**: re-ran the same cycle
   immediately after - gitlark completed cleanly in ~3 minutes (down from a
   20-minute timeout), iptv_apps similarly fast. One repo (shrike-labs-website,
   previously reliable every single cycle all session) still no-op'd slowly
   once after this fix, but its log showed a legitimate, well-reasoned attempt
   (correctly preserving an above-the-fold logo's eager-loading while lazy-
   loading everything else) that just didn't end up committing - a much more
   benign failure mode than the earlier unbounded rambling, and not chased
   further given the clear overall improvement.
4. **Current production state**: `qwen-dflash-9B` active
   (262,144 ctx, flash-attn on, q8_0/q8_0 KV cache), litellm/model-metadata
   updated to match (200,000 conservative `max_input_tokens`, 8,192
   `max_output_tokens`), queue resumed and validated across two full cycles.
   `switch-active-model.sh qwen-dflash-27B` / `qwen-dflash-35B-A3B` remain
   available as one-command rollbacks if 9B's quality doesn't hold up over a
   longer real run - all three configs now live in one hardened script rather
   than needing hand-tuned `docker run` invocations to reproduce.

### Controlling the queue from your phone

`~/overnight-queue/queue.sh` (SSH in via Tailscale, e.g. Termius):
`status`, `pause`, `resume`, `report [N]`, `log <task-id>`, `run-now`,
`list`, `enable/disable <id>`, `repos`, `add <id> <repo> <prompt...>`,
`remove <id>`. `add` lets you queue a new one-off task without hand-editing
JSON — validates the repo is cloned and the id is unique first.

### Chat interface

Open WebUI (`shrike-webui` container, port 3000) reconfigured to point at
`litellm` instead of the stopped `ollama` container — reachable at
`http://100.79.64.64:3000` over Tailscale from anywhere, no Mac needed.
Starting it also starts `shrike-ollama` as an apparent docker-compose quirk
(harmless, no GPU memory used idle) — stop it manually if you notice it.

### TODO

- [x] Confirm SSH key on GitHub, clone all 7 repos, verify `aider_fix` push
      path end-to-end.
- [x] Test persistent-branch reuse across multiple runs (no reset).
- [x] Live-test the full fleet's shared prompt template on at least one
      repo before enabling all 7.
- [ ] Watch the first real unattended day (12 cycles/day × 7 repos) via
      `queue.sh report` and skim a few `overnight/feature` branches once
      back from vacation — nothing needs review before then, but confirm
      the fleet actually produced useful, mergeable work over multiple
      days before assuming it'll keep doing so unattended for weeks.

---

## 3. Local model setup

**Verified 2026-08-02**: `qwen-dflash-27B` (the size called out as best for a
24GB card) is registered *and* actually responding — confirmed with a real
completion, not just a config check.

Nothing further needed here for now.

---

## 4. Training pipeline — now fully working end-to-end

**Status: proven 2026-08-02** with a real GPU training run (not a CPU/tiny-model
smoke test): `specpilot/selector_optimization`, `--engine unsloth`, on the RTX
3090, produced a real 684MB LoRA adapter at
`~/shrike-ai-lab-training/models/specpilot-selector_optimization-manual-20260802-122608/`
on the GPU server. Getting there surfaced and fixed several real, previously
untested bugs — recorded here and in `memory/shrike-llm-ops.md` so they're not
rediscovered:

1. **GPU driver/kernel module mismatch**: `nvidia-driver-580` had been
   upgraded to 580.173.02 on disk, but the kernel module loaded in memory was
   still 580.159.03 (never reloaded since the apt upgrade — the box had been
   up 2 days). Broke `nvidia-smi` and would have broken any fresh CUDA
   process (though the *already-running* inference containers were
   unaffected, since they'd initialized against the driver before it changed).
   **Fixed by rebooting** — Docker's `unless-stopped` + the already-fixed
   fstab mount entry meant both containers self-healed cleanly afterward, no
   manual recovery needed.
2. **Python 3.14 incompatibilities** (the server's only system Python):
   `crewai`/`langchain` (used only by the out-of-scope agent-team subsystem,
   not training) have no 3.14-compatible release at all. Separately, `dill`
   (a transitive dependency of `datasets`, used for dataset fingerprinting)
   hit a real `pickle.Pickler._batch_setitems` signature incompatibility with
   3.14 that broke `Dataset.from_list()` outright. Rather than chase each
   package's 3.14 support individually, **installed Python 3.12 via the
   deadsnakes PPA** and rebuilt the training venv on that instead — matches
   what we already had to do for `aider` on the Mac for the same class of
   issue.
3. **`scripts/train.py` bug (pre-existing, not something we introduced)**:
   `get_finetune_module()` does `import training.<project>.finetune`, which
   only resolves if the repo root is on `sys.path`. Running as
   `python scripts/train.py` puts `scripts/` on `sys.path[0]`, not the repo
   root — so this import silently failed (caught by a broad `except
   Exception`) and every past run, including all the old Windows-era smoke
   tests, silently fell back to dumping raw JSON as the training text instead
   of each project's actual formatter (e.g. specpilot's real
   instruction/response template). **Fixed**: `train.py` now explicitly adds
   the repo root to `sys.path` at import time. Confirmed fixed — the
   "Project finetune import skipped" warning no longer appears, and the real
   formatter is now used.
4. **`fp16`/`bf16` mismatch (unsloth engine only)**: Unsloth's
   `FastLanguageModel.from_pretrained(dtype=None)` auto-selects `bfloat16` on
   Ampere+ GPUs (confirmed: RTX 3090), but `train.py` unconditionally set
   `fp16=True` whenever CUDA was available — Unsloth's `SFTTrainer` correctly
   rejects that combination outright. **Fixed**: `bf16`/`fp16` are now chosen
   per-engine (unsloth → bf16, hf → fp16, matching what each engine actually
   loads the model in).
5. **Missing system build tools**: Unsloth/Triton JIT-compiles small CUDA
   glue kernels at runtime and needs a real C toolchain + Python headers.
   **Fixed**: installed `build-essential` and `python3.12-dev` on the server.
6. **Checkpoint-save pickling bug**: with `save_strategy="epoch"`, the
   automatic mid-training checkpoint tries to pickle `TrainingArguments`,
   which fails under unsloth — its compiled-cache module re-defines
   `trl.trainer.sft_config.SFTConfig` as a distinct class object from the one
   in the installed `trl` package, so `pickle` refuses
   ("it's not the same object as trl.trainer.sft_config.SFTConfig"). Since
   `train.py` already does its own final `save_pretrained()` call once
   training finishes, and nothing here resumes from a mid-training
   checkpoint, the automatic checkpoint was redundant anyway. **Fixed**:
   changed to `save_strategy="no"`.

None of the above needed CUDA/GPU access to fix except discovering them, which
is why they only surfaced now — every prior "successful" training run in this
repo's history was a CPU/tiny-model smoke test that never exercised this real path.

### Remaining open decisions (still deliberately not changed without you)

- **Base models in `scripts/train.py` `PROJECT_CONFIGS`** are
  `codellama/CodeLlama-7b-hf` and `mistralai/Mistral-7B-Instruct-v0.2` — picked
  for the old RTX 2080/2080 Ti hardware. Now proven to actually train on the
  24GB 3090; still worth reconsidering a more current base model, but that's
  a real decision (changes downstream prompt formatting), not a drop-in swap.
- **Real training data**: everything under `training/*/data/*.jsonl` is
  still 10-15 example rows — enough to prove the pipeline works (as just
  done), not enough for a meaningful fine-tune. Collecting real data is a
  distinct, larger task.

### Explicitly out of scope (unchanged from before)

Same two Windows-era subsystems as previously noted — startup/crash-recovery
cluster (superseded by Docker's own restart policy) and the agent-team
promotion pipeline (separate, much larger initiative). Still untouched.
