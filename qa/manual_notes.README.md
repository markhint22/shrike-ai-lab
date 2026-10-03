# Manual-notes loop: your testing notes become fleet work

**Short answer to "will Qwen create action items and bug fixes from my notes?"**

- **Action items: yes.** Every `bug` line you log becomes one queue item at the top of that repo's `## Next Steps` (or, if the
  code cannot be located, a plain relay note asking you to re-log it with a function / label / file name).
- **Bug fixes: the fleet will *try* every one; it will land some.** Python/backend fixes land best. Vue/TypeScript less often.
  Kotlin / Swift / GDScript / Android-XML fixes land only about 20-35% of the time; those usually park into the `[CLAUDE]`
  needs-a-human list and you get a "needs a human" note. Nothing is claimed fixed unless the fleet checked the item off
  (and "fixed" still means "retest it": the fleet's check is its own tests, not you).
- **Locator v2 (2026-10-01): a tester note WITHOUT code names now finds the file.** The log carries the platform; the locator maps it
  to the repo's own directories, searches product code only (never e2e / tests / fixtures), and when the deterministic result is weak
  or ambiguous a bounded agentic loop with the local Qwen (<= 4 model calls) proposes search queries, the HARNESS runs them with
  `git grep` and verifies every path Qwen names. Qwen never touches the repo; invented / test / wrong-platform paths are discarded;
  any model problem falls back to the deterministic result. Measured on 100 real fix commits: see "Benchmark" below.

## How you use it

```
scripts/qa-log <repo> <platform> <flow> <minutes> <ok|bug> "note"
scripts/qa-log iptv_apps android home-countries-filter 5 bug "Clicking countries filter only showed all and Qatar 2."
```

Log line format: `date | platform | flow | minutes | result | note` with platform = `android ios tv tvos roku web backend game desktop other`
(what you were testing ON). Legacy 5-field lines (`date | flow | minutes | result | note`) still work; an optional header line
`# platform: android` gives the default platform for the legacy lines below it. Hand-written dates (`10/01/2026`) and flow names with
spaces are fine. If a line has no platform, the ingest infers it from the flow id prefix (`and-...` from docs/test-plans) or from
explicit words (`iPhone`, `in the browser`, `Android TV`); if that is still ambiguous across platforms the note is `needs-triage`
with the per-platform candidates (it never guesses alphabetically).

Only `bug` lines are bridged. **Write the note so it names something findable**: the exact button/label text in quotes, a function
or file name, a screen/route (`/api/alerts`), and say the platform if it matters (`on Android`, `in the browser`, `on tvOS`).
"App feels slow" cannot be placed in code and becomes `needs-triage` (you get one relay note; nothing is queued).

What you see on your phone (all through the relay at `NTFY_SERVER`, default priority, so they are buffered by the notification
policy, never urgent): `Manual bug needs triage: <repo>`, `Manual bug fixed: <repo>`, `Manual bug needs a human: <repo>`.
One note per status change, note text trimmed to ~80 chars.

Check status any time on the box: `python3.12 ~/overnight-queue/qa/manual_notes_ingest.py list` (add `--json` for everything).

## The pieces

| piece | where | job |
|---|---|---|
| `scripts/qa-notes-bridge.sh` | Mac (shared repo) | each run: new `bug` lines in `qa/manual_logs/<repo>.txt` -> ssh -> `manual_notes_ingest.py add` (note sent as base64) |
| `scripts/com.shrike.qa-notes-bridge.plist` | Mac | launchd TEMPLATE, every 10 min. **Not installed.** |
| `qa/manual_notes_ingest.py add\|sweep\|list` | box | locate, build item, enqueue, track, notify |
| `qa/manual_notes_cron.sh` | box | cron-safe wrapper for `sweep` (`*/10 * * * *`) |
| `qa/manual_locator.py` | box (next to the ingest) | locator v2 blocks: platform layout, product-only filter, agentic loop (deploy it WITH the ingest) |
| `qa/bug_brief.py` + `qa/bug_brief.README.md` | box | **bug brief (2026-10-02)**: research + plan + decompose the enqueued bug into a test-first list of single-file steps and REPLACE the single item (kill switch `OVN_BUG_BRIEF=off`; any failure leaves the single item untouched); `import-brief` takes a brief written by Claude or a human |
| `qa/locator_eval.py` + `qa/locator_eval_set.json` | box | benchmark harness + the 100-case set (see Benchmark) |
| `scripts/test/test_qa_manual_notes.py` | both | 153 checks, runs on Mac and box |
| `scripts/test/test_qa_locator_v2.py` | both | 109 checks for locator v2 (layout, filter, agentic loop with a stub model, bridge formats) |

### Bridge (Mac)
Idempotent: bridged lines are remembered as `sha1(date|flow|note)` in `~/.qa_notes_bridge/<repo>.done`. An ssh/box failure
leaves the line unbridged and the run stops at the first unreachable-box error (retry next run). A permanent rejection (unknown
repo, bad date, empty note) is recorded `rejected` and not retried. Mac-safe (no flock/timeout: mkdir lock + `qa_timeout.py`),
path resolved before any `cd`, explicit PATH, always exits 0, log at `~/.qa_notes_bridge/bridge.log`. Every token that reaches the
remote shell is validated first, and the note itself is base64, so a hand-edited log line cannot inject anything.
Env: `OVN_SSH` (default `mhintermeister@100.79.64.64`, the tailscale address the Claude-queue bridge uses), `OVN_REMOTE_DIR`
(default `overnight-queue`), `QA_NOTES_NTFY` (the box-side relay, default `http://127.0.0.1:8099`).

### `add` (box)
1. **Validate**: repo must have a clone under `repos/`; date `YYYY-MM-DD`; note non-empty after sanitizing (else exit 2 = permanent).
2. **Sanitize** (stored + queued text): control/zero-width/bidi chars and newlines removed, backticks, markdown, `|`, `[T1]`/`[feat:]`
   bracket lookalikes, `VERIFY:` / `cat:` / `src:` tag lookalikes, `AUTO-SKIP`, `HUMAN-ONLY`, `$(`, html comments and ` - ` defused,
   capped at 400 chars. (A note containing `VERIFY:` or `AUTO-SKIP` would otherwise corrupt or park its own queue item.)
3. **Dedupe** by `sha256(repo|date|flow|normalized note)` in `state/manual_notes.json`.
3b. **Platform** (v2): `--platform` from the bridge (log column / `# platform:` header) -> else flow-id prefix -> else explicit words -> else
   unresolved. Mapped to path prefixes from the directory conventions of the tree at `origin/overnight/feature` (`*-android/`, `*-ios/`
   minus the nested `*TV` target = tvOS, `*-web/` `web/` `frontend/`, `*-backend/` `backend/`, `*-roku/`, godot repos by `scripts/` +
   `scenes/`). Candidates are restricted to that platform; server-side (backend) files may appear only as an "Also look at" path. A
   platform the repo does not have is treated as unresolved. Unresolved in a multi-platform repo: only decisive evidence (top platform
   >= 1.5x the next) may pick one, otherwise `needs-triage` listing the per-platform candidates.
3c. **Product code only** (v2): `e2e/`, `tests/`, `__tests__/`, `androidTest/`, `*UITests/`, `*Tests/`, `*.spec.*`, `*.test.*`, `fixtures/`, `mocks/`,
   docs, generated / build output, `node_modules`, `.gradle`, lockfiles, gradle build files are never a target and never promoted by a file-name
   signal (the `HomePage.mjs` regression: a `flow:home` file-name hit once beat the real screen).
4. **Locate** on `origin/overnight/feature` (never the live checkout): keywords from note + flow are searched with `git grep`:
   identifiers (snake/camel/Pascal, `name()`), quoted UI labels, routes, file names, rare plain words, adjacent-word phrases
   (`restore purchases` also tries `restorePurchases`, `restore_purchases`, `restore-purchases`), file names that equal a word or
   the flow (`alerts` -> `routers/alerts.py`), UI labels found in `strings.xml` / locale JSON / `.strings` resolved to the code that
   uses their key (`R.string.x`, `t('x')`), and platform words (android / ios / web-browser / tv / backend / endpoint) steering
   between sibling implementations. A keyword hitting more than 40 files is ignored as non-discriminative. Test files are never
   the target unless the note names them. Needs score >= 3 to count as "located".
5. **Agentic localization** (v2), when the deterministic result is weak or ambiguous (no named file / identifier / quoted label with a
   score >= 9 and no rival): at most 4 model calls, ONE at a time, 70 s timeout each. (a) Qwen gets the note, platform and a compact
   platform-filtered repo map (directory -> file names) and returns up to 8 short search queries as strict JSON (UI labels, likely
   identifiers, concept synonyms); (b) the harness runs them with `git grep -n -I -i` on the platform-filtered tree, ranks files by
   distinct-query hits (discriminative queries count more), file role (screen / viewmodel / router / service ...) and resolves a UI
   label found in `strings.xml` to the code using its key; the keyword locator's own hits are one more pseudo-query; (c) Qwen picks up to 3
   files with a one-line reason (first = primary, the rest = "Also look at") and may ask for ONE more search round; (d) the harness verifies
   every path (exists, in-platform, product code; a bare file name that exists once is resolved) and discards the rest. If every pick was
   invented or filtered, one repair call; if still nothing, the deterministic result is used. Multi-layer bugs: the item carries the
   primary file plus up to 2 `Also look at: <real path>, <real path>.` paths and `multifile:yes` (so the stage runner's scope guard
   lets the fix touch them, and `ovn_retire_vague.py` still sees real paths). Kill switches: `OVN_MANUAL_AGENTIC=off` (back to the v1
   one-call tie-break), `OVN_MANUAL_MODEL=off` / `--no-model` (deterministic only). Legacy v1 tie-break (>= 2 plausible candidates, one
   model call ordering them) is kept as the fallback when the agentic loop did not run or failed and the 4-call budget allows.
6. **No evidence => `needs-triage`**: not enqueued (the retire-vague sanitizer would delete an item that names no real file),
   one relay note, candidates + note stored.
7. **Enqueue** one item, e.g.
   `- [ ] [T2] billwatch-web/src/views/FindRepsView.vue — Manual-test bug (reported by Mark, flow find-reps, 2026-10-01): <note>. First write a failing test that reproduces this, then fix it; if the cause is not in this file, say so. VERIFY: \`cd billwatch-web && npm run test -- FindRepsView\`. (cat:bugfix; multifile:no; src:manual) [feat:billwatch-20261001-manual-2dbee142]`
   Tier T2 (T3 for Kotlin/Swift/GDScript/XML). VERIFY is picked from the tree (nearest `tests/test_<stem>*.py` else the tests dir; `npm run test -- <stem>` in the
   app dir with a package.json; the gut command for `.gd`; gradle for Android; `swift test`). Written with the `ovn_park_sweep.sh`
   pattern: `queue.sh hold` -> `git fetch` -> refuse unless the clone is on `overnight/feature` -> `reset --hard origin/overnight/feature`
   -> insert -> `git add OVERNIGHT_PROGRESS.md` (explicit path) -> commit as `shrike-fleet` -> push (rebase-retry) ->
   **`queue.sh release` in a `finally`**. On any failure the clone is reset to origin and the entry is kept as `pending-enqueue`
   (the sweep retries it).
7b. **Bug brief** (2026-10-02, `qa/bug_brief.README.md`): once the single item is enqueued the entry is marked `brief:pending` and `manual_notes_ingest.py brief --id <id>` is spawned
   detached (the sweep retries leftovers). It collects deterministic evidence (functions with exact line numbers, callers, existing tests and how they are written), asks the local Qwen
   (<= 4 calls) for a strict-JSON brief, validates EVERY field mechanically (quotes verbatim, one file per step, banned / > 120 KB files, real test-run VERIFYs, the test-first test is run
   on the current code), and replaces the single item by the ordered steps (one shared `[feat:]` tag, the test-first step fused with the first fix because a red test cannot land alone).
   Model dead / invalid / vacuous / item already taken => the single item stays exactly as enqueued.
8. **Auto-lane**: QA mode turns every dev lane off, so a queued bug would sit unworked. If `state/qa_mode.json` exists (mode qa) and
   `OVN_MANUAL_AUTOLANE != off`, `qa_mode.sh lane <repo>` enables that one lane and we record `lane_enabled_by_us`. A lane someone
   else already enabled is left alone.

### `sweep` (box, every 10 min)
Per repo with open entries: `git fetch`, read `OVERNIGHT_PROGRESS.md` (and `OVERNIGHT_DONE.md`) on `origin/overnight/feature`, find
every line carrying the entry's `[feat:...]` tag:

| line state | status |
|---|---|
| still `- [ ]`, not parked | `open` |
| `- [x]` | `fixed` ("fleet says landed, retest it") |
| `AUTO-SKIP` / `[CLAUDE]` / `HUMAN-ONLY` / `(retired-` | `needs-human` |
| `- [x] (already-satisfied ...)` | `needs-human` (the fleet claims there is nothing to fix; you saw a real bug, so that is not a fix) |
| line gone for > 1 h | `needs-human` (retired or removed) |

When a repo has no open manual items left, a lane we enabled is released with `qa_mode.sh unlane` (only while QA mode is still on, so
`qa_mode.sh off` is never undone by us). Safety valve: a lane we enabled is released after 24 h (`OVN_MANUAL_LANE_TTL_H`) regardless.

## Bugs first (2026-10-02 - decision from Mark: quality over new development)
A bug you logged by hand is worked RIGHT AWAY, ahead of every roadmap / refill / self-gen item, while Chickadee and xlite are being taken to release.
All switches default ON; `OVN_BUG_FIRST=off` restores the old behaviour everywhere (kill switch). With no manual bug in a repo nothing changes
(proved by the unchanged existing selection / item-guard / run_overnight / stage-runner tests plus identity checks in `test_bug_first_select.sh`).

| rule | where | detail |
|---|---|---|
| **One ordering** | `scripts/lib_item_select.sh` `ovn_bug_first_order` / `ovn_resolve_top_item` | EMERGENCY lines first (existing precedence), then manual-bug lines in file order, then everything else. Enforced where the loop *selects*: `ovn_resolve_top_item` (guard + record_outcome + scout-unworkable + best-of-N), the `Doable Next Steps` slice the scout is shown (a small file is also given as the ordered slice while a bug is open, never raw file order), the delete-hint / delete-executor peeks, the inline T3+ stage trigger, the stage runner's own picker (python-preference skipped for a bug). Insertion order is irrelevant (queue_refill appends at the end, the ingest inserts at the top, EMERGENCY goes above everything). A "bug line" = open `- [ ]` line with `[feat:<repo>-<date>-manual-<8 hex>[.rN]]` or `Manual-test bug (reported by Mark ... src:manual`; the steps of a decomposed brief share that one feat tag, so they all count. |
| **Lane focus** | same filter | while a repo has an open (not parked / escalated) manual bug its lane sees ONLY bug items (+ EMERGENCY). Parked/escalated bugs stop counting, so the lane returns to normal work. `OVN_BUG_FOCUS=off` keeps the order but also shows the rest after the bugs. A T2 bug leaves no T3+ item for the stage runner, so the cycle falls through to the scout flow that works the bug. |
| **Attempt cap** | `scripts/ovn_item_guard.sh` | a bug (or one step of its brief; a landing clears the counter) gets `OVN_BUG_ATTEMPT_CAP` (default **2**) failed attempts, counting best-of-N tries (`OVN_GUARD_ATTEMPTS`, best-of-N is capped at the same number for a bug) - not the generic 3-4, never the schema +2 budget. Every non-landing status counts except `skip*`/`held*`. Spend cap (`OVN_ITEM_TOKEN_CAP`, base, no schema multiplier) also escalates. |
| **Escalation, never AUTO-SKIP** | same | every still-open line of the bug becomes `[CLAUDE] [bug-escalated: <reason>]` (the loop ignores `[CLAUDE]`), one JSON line is appended to `state/bug_escalations.jsonl` (repo, note, item hash, feat, attempts, last status + failure, brief location = `state/bug_briefs/<feat>*` if one exists, else empty), and ONE relay note `Manual bug escalated: <repo>` (default priority => buffered by the notification policy, never urgent) goes out. JSONL line + note happen at most once per item hash. |
| **Every park path honours it** | `scripts/lib_bug_escalate.sh` (shared), `ovn_stage_runner.sh`, `ovn_stage_sweep.sh` | the guard is not the only thing that parks lines. Every manual bug is tier T3, so the staged runner sees it first: on a 0/n or partial run it counts ONE attempt itself (`state/item_fails/stage-<repo>.<hash>.bugcount`; the cron sweep path runs no guard) and escalates at the same cap through the same helper (tag + `bug_escalations.jsonl` + one relay note) - it never writes `[AUTO-SKIP staged ...]` on a bug. It journals `bug_attempt`, `run_overnight.sh` tags the status `bug-handled`, and the guard skips such a cycle (no double count, no billing to an unrelated roadmap item). The sweep's godot router (`escalate_godot`) exempts bug lines, so xlite `.gd` bugs reach the fleet. Without the helper lib everything falls back to the old generic caps. `OVN_BUG_FIRST=off` restores all old behaviour. |
| **Retest loop** | `manual_notes_ingest.py retest`, `scripts/qa-retest`, bridge | the fleet's green tests are not the end: a landed bug is `fixed (awaiting your retest)` until you say so. `scripts/qa-retest <repo> <flow> ok` closes it (status `closed`); `scripts/qa-retest <repo> <flow> still-broken "what you saw"` reopens it at the TOP of the queue with your note attached and a fresh attempt counter (new `[feat:...rN]` tag => new item hash; the item tells the fleet to read the earlier attempt and not repeat it). It works for `fixed`, `escalated` and `needs-human` bugs. A `still-broken` that matches no bug is filed as a normal new bug. |
| **Statuses** | `list` / `scripts/qa-status` | `open`, `pending-enqueue`, `fixed` (= awaiting your retest), `escalated` (fleet gave up, Claude session takes it), `needs-human`, `needs-triage`, `closed`. `qa-status` shows counts per status per repo (it asks the box over ssh, 6 s connect timeout, and caches the answer in `~/.qa_notes_bridge/status.json`; box unreachable => the cache, labelled with its age; `QA_STATUS_LIVE=off` => cache only; the bridge itself makes no extra ssh call) and, for one plan, what is waiting for a retest with the exact command to run. |

Retest mechanism (smallest thing that works): `qa-retest` appends an ordinary 6-column line to `qa/manual_logs/<repo>.txt`:
`date | other | <flow> | 0 | ok|bug | [retest:ok|still-broken HH:MM] note`. The bridge recognises the marker and calls `manual_notes_ingest.py retest`
(rc 0 applied / DUPLICATE, rc 2 permanent reject, rc 3 = unmatched still-broken -> filed as a new bug). An older bridge ignores the `ok` line and files
the `still-broken` one as a new bug, so nothing is lost. Deploy order: box (guard, lib, ingest, run_overnight.sh, stage runner) then Mac (bridge, qa-retest, qa-status).
Not changed on purpose: stage-internal per-step attempts (`OVN_STAGE_MAX_ATTEMPTS`, repair rounds) - the cap counts fleet cycles and best-of-N tries, so one staged cycle
can still spend its own internal retries on the bug; `ovn_stage_sweep.sh` (cron path) keeps its own pre-check, harmless because the runner it starts applies the order.
The ingest also defuses the words `blocked`, `human/` and `hard file ban` in a note (every selector drops lines containing them, which would hide the bug's own item).

## Benchmark (locator v2, measured 2026-10-01 - `qa/locator_eval.py`, set `qa/locator_eval_set.json`, raw results `qa/locator_eval_results_2026-10-01.json`)
100 cases from REAL fix commits of billwatch (28), gitlark (27), iptv_apps (45) on the box clones. A case = a fix commit whose
message describes a user-visible problem (judged by the local Qwen from the diff), a tester note drafted by Qwen then stripped of
identifiers / paths and rejected if it leaks a labelled file name (22 dropped), label = the non-test product files the commit
modified (files added by the commit are not labels). The locator runs against the PARENT commit (`git grep <sha>`, read only) with
the platform the log would carry. hit@N = any of the first N paths is a labelled file; "also look at" paths count (the item carries them).

| arm | hit@1 | hit@3 |
|---|---|---|
| v1 (as shipped before: deterministic, no platform, old filters) | 21% | 36% |
| v2det (platform + product-only, no model) | 45% | 67% |
| **v2 (agentic loop on weak / ambiguous results)** | **74%** | **89%** |
| v2all (agentic loop on every note) | 72% | 88% |
| v2np (v2 with NO platform given: infer, else triage) | 8% | 10% (77% of notes -> needs-triage) |

v2 by platform (hit@3): android 100% (n=23), web 93% (30), backend 83% (41), ios 80% (5, tiny sample). By repo: iptv_apps 93%,
gitlark 89%, billwatch 82%. Two independent v2 runs (model sampling variance): 89% and 91%; mean 2.0 model calls and ~8 s per note.
Caveats: the notes are LLM-drafted from the diff (they may carry slightly more detail than a human's), n=100 with several cases per
area, the platform is given (the v2np row shows what happens without it: the locator refuses to guess and triages), the label is
"files the fix touched" (a fix in a different layer than where the feature lives counts as a miss).
Failure classes of the misses: (1) backend siblings - router vs service vs model vs schema of the same feature, or the fix landed in a
shared module (`dependencies.py`, `main.py`, `bill_status.py`) that no note wording points at; (2) notes so generic they fit many features
("the assistant crashed", "view bill details got a server error"); (3) code outside the platform dirs (a VS Code extension under
`vscode-extension/`, no platform dir => unresolved); (4) one TV-paywall case where a high word-count score kept the model out (fixed by the
"strong evidence" rule, see step 5, and by excluding gradle build files).

## Install (integrator; nothing here is installed)
- Box: copy `qa/manual_notes_ingest.py` + `qa/manual_notes_cron.sh` (atomic `mv`), add the cron line
  `*/10 * * * * NTFY_SERVER=http://127.0.0.1:8099 $HOME/overnight-queue/qa/manual_notes_cron.sh >> $HOME/overnight-queue/logs/manual_notes.log 2>&1`,
  register `test_qa_manual_notes.py` in `run_all.sh`.
- Mac: `cp scripts/com.shrike.qa-notes-bridge.plist ~/Library/LaunchAgents/ && launchctl load ~/Library/LaunchAgents/com.shrike.qa-notes-bridge.plist`.
- Kill switches: `OVN_MANUAL_SWEEP=off` (cron), `OVN_MANUAL_MODEL=off`, `OVN_MANUAL_AUTOLANE=off`, `launchctl unload` (bridge).

## Known limits (honest)
- **Locating is heuristic.** A note with no findable word becomes `needs-triage`; a note with a *common* word may be placed in the
  wrong file (the item tells the 27B to say so if the cause is elsewhere, but it may still burn cycles there). Always put the exact
  label / function / file in the note.
- **Platform ambiguity.** The same label often exists on web, Android and iOS. Log the platform (`qa-log <repo> <platform> ...`). Without it
  the note is inferred from the flow id / words and otherwise `needs-triage` (77% of the benchmark notes) - the locator never guesses.
- **One primary file + up to 2 "Also look at" files per item.** A bug whose real cause is elsewhere will park; the item tells the 27B to say so.
- **27B landing rate** for weak languages is ~20-35% (see risk in `list`). `fixed` is the fleet's own verification, not yours.
- Not wired into `run_all.sh`, the crontab or launchd (integrator step). The bridge needs the box reachable over ssh; if it is not,
  notes simply wait in the log (nothing is lost, nothing is sent twice).
- The sweep reads `origin/overnight/feature` only; a fix that lands only on `claude/feature` shows as `open` until it reaches `overnight/feature` via reconcile.
