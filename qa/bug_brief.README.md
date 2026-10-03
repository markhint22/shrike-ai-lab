# Bug brief: research, plan and decompose a manual-test bug so the 27B can land it

**Why.** Mark's decision (2026-10-02): quality over new development; bugs he logs by hand (`qa/manual_logs/<repo>.txt`) go first, Chickadee
(`iptv_apps`) and xlite before anything else. Evidence that it matters: of 7 real Chickadee Android bugs the 27B fleet landed 1 in a day
(Kotlin / GDScript landing rate about 20-35%). `docs/qwen-capability/*` says why: whole-file context, multi-file steps, existence-only VERIFYs,
no test-first loop. A manual bug used to become **one** item ("first write a failing test, then fix it, if the cause is not in this file say
so"). The bug brief turns it into a short list of **single-file steps**, each naming the exact function and the exact change, each with a REAL
test run as its VERIFY, plus the root cause with verified evidence. The model proposes; **the harness verifies every field**.

**Standing rule honoured:** the pipeline never depends on Claude. The default path is Qwen + deterministic checks, and any model problem falls
back to today's behaviour (the single item stays exactly as the ingest enqueued it). A brief written by Claude or a human is an optional,
importable enhancement (`import-brief`, below).

## What happens to a new bug

```
qa-log ... bug "note"  ->  bridge  ->  manual_notes_ingest.py add          (unchanged: locate, enqueue ONE item at the top of Next Steps, right away)
                                          |  marks the entry brief:pending, spawns `manual_notes_ingest.py brief --id <id>` detached (never blocks ssh / the bridge)
                                          v
                              bug_brief.make_brief()   (minutes, outside the state lock; one at a time via state/bug_brief.lock)
                                1 RESEARCH   deterministic: git grep + function ranges, no model
                                2 PLAN       <= 4 model calls, strict JSON brief
                                3 VALIDATE   mechanical (see below); one repair call when a check fails
                                4 RED PROOF  the test-first step is RUN on the current code in a throwaway worktree
                                5 EMIT       ordered queue items sharing ONE [feat:<tag>]
                                          v
                              edit_progress(): hold -> fetch -> reset -> REPLACE the single item by the items -> commit (explicit path) -> push -> release
```

If anything fails (model dead / slow / invalid output / validation failure / vacuous test / item already taken / push race) the entry records
`brief.status = fallback|skipped` with the reason (`manual_notes_ingest.py list --json`, `state/bug_briefs/<feat>.json`, `logs/bug_brief.log`) and the
single item is untouched. The sweep (`*/10`) retries `pending` briefs (and takes over a `running` claim older than 30 min), so a missed spawn costs
at most one sweep interval. `OVN_BUG_BRIEF=off` turns the whole stage off (add does not mark anything, `brief` is a no-op).

Entries created before the stage was deployed carry no `brief` field and are left alone; `manual_notes_ingest.py brief --id <id> --force` briefs one of them.

On demand: `python3.12 qa/bug_brief.py brief --repo iptv_apps --note "..." --flow "..." --platform android [--path <located file>] [--apply]`
(prints the items; `--apply` edits the live clone through the ingest's atomic edit; `--progress-file F` applies to a local file instead), and
`python3.12 qa/manual_notes_ingest.py brief --id <entry id> [--force]` for an existing entry.

## 1. Research (deterministic, compact)

From the located file (+ up to 2 "also look at" files) and the tester's words (identifiers, quoted labels, adjacent-word phrases, plural stems
`countries` -> `country`): the **functions** whose body / name matches (3 best, short and specific ones win over long ones), quoted with **exact line
numbers**; for a long function only the signature plus windows around the matching lines; the state / data-model block (`data class XUiState(...)`,
GDScript top-level vars, pydantic / TS types); the **callers** (not the definition, not tests, not comments); the **existing tests** for the module and
**how they are written** (head of the best test: package / imports / setup, plus one test function); and the **test plan**: the exact path of a NEW test
file next to the existing tests and the exact command that runs it. A 227 KB god file (xlite `battle.gd`) is never loaded whole: only function
ranges reach the prompt (the whole evidence block is capped at 15 000 characters, far below the 65k context).

**Anchor.** A screen / composable / view cannot be unit-tested the way its view model, service or store can. When the locator's primary file is a UI
file and an "also look at" file is its testable logic (same language, not a test), the logic file anchors the research and the test plan (the UI file stays
in the evidence): the locator picked `StreamsListScreen.kt` for the countries-filter bug, the brief anchored on `StreamsViewModel.kt`.

| language | new test file | VERIFY (run command) |
|---|---|---|
| Kotlin | `<mirror of the source dir under src/test/java>/<Stem><Slug>Test.kt` (same package as the neighbouring test) | `cd <gradle root> && ./gradlew :app:<testGoogleTvDebugUnitTest> --tests "<package.Class>"` (the variant task: see below) |
| Python | `<root>/tests/test_<stem>_<slug>.py` | `cd <root> && python -m pytest tests/<file>.py -q` |
| TS / Vue | colocated `<stem>.<slug>.test.ts` | `cd <app> && npx vitest run <relative path>` |
| GDScript | the repo's GUT dir `test_<stem>_<slug>.gd` | `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://<path> -gexit` |

**GDScript emits SOURCE-ONLY fix items (2026-10-02 review fix).** The stage runner never picks a line that names a `tests/*.gd` file and its GODOT MODE forbids
authoring GUT files, so for `.gd` the test-first and guard steps are validated and (when proven red) stored in `state/bug_briefs/<feat>.json`, but only the fix steps
are queued: each is verified by `gdparse <file>`, names no test path, and the runner's own gate still runs the GUT suite. Test: the emitted items pass the runner's
exact `_doable` grep chain.

Swift, XML-only and other bugs have no usable test run: the stage falls back (the ingest already routes Swift away).

## 2. Plan (<= 4 model calls, same client pattern as the locator)

The stage uses the locator's `Budget` (hard call cap, wall deadline for the whole stage, circuit breaker: the first failed or hung call marks the model
dead and nothing waits on it again), the same local litellm (`LITELLM_BASE`, alias `OVN_MANUAL_MODEL`), `<think>` stripping and tolerant JSON parsing.
Calls: plan (1), at most one repair of the plan (2), the test author (3), at most one test repair (4). With the red proof off, up to 3 plan attempts.

### The brief schema (the same for the model, for Claude and for a human)

```jsonc
{
  "repo": "iptv_apps", "flow": "Home Page Categories", "date": "2026-10-02", "platform": "android",   // optional metadata
  "note": "the tester's words",                                                                       // optional
  "root_cause": {
    "hypothesis": "one paragraph, 40-900 chars, naming the cause",
    "evidence": [ {"file": "path/in/repo", "line": 41, "quote": "verbatim fragment of that line, 8+ chars"} ]   // 1-4; at least one in product code
  },
  "approach": "one or two sentences",                                                                 // optional
  "steps": [                                                                                          // 3-6, order: test_first, fix..., guard
    {"kind": "test_first", "file": "NEW test file", "function": "test name", "change": "what the test arranges, calls, asserts (12-420 chars, names identifiers)", "verify": "test run command"},
    {"kind": "fix",        "file": "ONE existing source file", "function": "exact function / method / property", "change": "the exact edit", "verify": "test run command"},
    {"kind": "guard",      "file": "test file (new or existing)", "function": "test name", "change": "...", "verify": "test run command"}
  ]
}
```

A `test_first` step may also carry `"reference_test": "<full source of the new test file>"`; with `import-brief --exec on` the harness runs it on the
current code (the stage stores the model's own proven test there).

## 3. Mechanical validation (the model is advisory)

| check | rejected when |
|---|---|
| evidence | file missing; quote shorter than 8 chars; quote **not found verbatim** in the file (hallucination); quote found but not within 5 lines of the stated line (found within 5: accepted and the line number is **corrected**); no evidence in product code |
| one file per step | `file` is a list, holds two paths, has `..`; the `change` text names another existing file of the repo |
| files | `fix` file missing, a test, not product code (`manual_locator.is_product_path`), outside the platform of the bug (client bugs may also edit `backend/`), not Kotlin / GDScript / Python / TypeScript |
| function | the named function / property is not defined or mentioned in the file |
| change | shorter than 12 / longer than 420 chars, a code block, or names no identifier or literal ("fix the bug properly") |
| hard-banned / oversize | any step file is on `.queue-hard-banned-files` (equality or prefix) or is larger than 120 KB (the `ovn_park_unworkable` rules; checked on the git tree). A located file that is itself unworkable stops the stage **before any model call** (the item parks as before) |
| VERIFY | not a real test run (`grep`, `ls`, `cat`, `test -e`, `python -c` are existence checks); fails the `card_lint` shell rules (allow-list, no redirects, no network, no `;` chains, no substitution); gradle without `--tests`, godot without `-gtest=`, unknown flags |
| exactness | the `change` hedges ("or similar", "e.g.", "such as", "probably", "might", "etc."): the 27B cannot act on a maybe |
| grounding | a fix `change` relies on a camelCase / snake_case identifier that exists nowhere in the repo (an invented helper) unless the change says "add a new function X" |
| no paper-over | a fix that hard-codes data / `DEFAULT_...` / special-cases, or quotes a literal the tester typed ('Qatar 2'): it must change the rule, not the example |
| structure | 3-6 steps; exactly one `test_first` (first) and one `guard` (last); at least one `fix`; test_first creates a NEW file at exactly the planned path in an existing test dir; the first fix's verify runs the test_first test |
| red proof | the test-first test PASSES on the current code (vacuous) -> plan rejected |

**What the harness does NOT prove.** The quoted lines exist; the *diagnosis* is the model's hypothesis (the item says so: "ROOT-CAUSE HYPOTHESIS ... not proven")
and the 27B is told to say so if the cause is elsewhere. A wrong locator pick still produces a well-formed brief about the wrong code.

**Red proof.** A second model call writes the new test file (it sees the function, the state class and an example test), the harness writes it into
a throwaway worktree of `origin/overnight/feature` and runs the step's VERIFY there (scrubbed env, no network, nice, hard timeout):
The model-written test is first scanned statically and **never executed** if it shells out, touches the network, deletes / writes files or reads obvious secrets
(`unsafe_test_code`; it is then `invalid`). `proven-red` (fails for a test-shaped reason: assertion), `vacuous` (passes: the plan is rejected after one repair), `invalid` (does not compile / import /
collect: **not** proof, the brief is still emitted but flagged "not executed by the harness"), `not-run` (infra: no tool, timeout). Proof needs POSITIVE evidence of a
failing test (pytest rc 1 + a failed count, a GUT junit failure, gradle `Class > test FAILED`, an assertion error): a non-zero exit alone is `not-run` ("the run failed without
a failing test": a gradle build that dies in 0.8 s was first reported as proven red in the trial and is now a regression test). Policy `OVN_BUG_BRIEF_EXEC=auto` runs every
handled language (measured on the box: a gradle unit-test run in a fresh worktree took 10 s, godot about 20 s, real pytest 2 s); hard timeout 600 s. A proven test is stored in
the brief JSON (`reference_test`), the failing assertion line goes into the item.

## 4. Emit

Items are written in the format the pipeline already parses, in order, at the position of the single item, all with the same `[feat:<tag>]`
(so `qa/manual_notes_ingest.py sweep`, `ovn_feature_watch` and the ledger keep working: the entry is `open` while any line is open, `fixed` when all
are `[x]`) and all carrying `Manual-test bug (reported by Mark, flow F, DATE)` (selection / ledger / attribution keep working; the policy builder's
priority tier keys on that phrase). Tier `T3` (as the ingest). Model text is defused (`clean_text`): no `VERIFY:`, `[CLAUDE]`, `AUTO-SKIP`,
`blocked`, `human/`, backticks, pipes, em dashes, html comments or `$(` can come out of a brief.

**Fused test-first.** A red test cannot land on its own: the NO-NEW-RED guard reverts it and the stage runner's decompose prompt says "NEVER a
failing-test-first step". So the `test_first` step is emitted **fused with the first `fix` step** into ONE item: the new test file (marked `(NEW)`, so
`ovn_retire_vague` keeps it) plus the one fix file, `multifile:yes`, `Also look at: <test file>`, VERIFY = the repro test now passing. The brief JSON
keeps them as separate steps. A brief with test_first + 2 fixes + guard becomes 3 items.

Example (first item of a brief; line breaks added here, the real item is one line):

```
- [ ] [T3] iptv-backend/app/services/channel_service.py — Manual-test bug (reported by Mark, flow Home Page Categories, 2026-10-02) [brief step 1 of 2]
  TEST-FIRST then FIX, land both in this one step (a red test alone cannot land). ROOT CAUSE: classify_channel_type() treats every channel whose name
  contains the word replay as a movie ... EVIDENCE: iptv-backend/app/services/channel_service.py:4 'if "replay" in lowered:'.
  (A) NEW test file iptv-backend/tests/test_channel_service_replay_live.py (NEW): NEW test: call classify_channel_type('00s Replay') and assert 'live'; ...
  Harness-verified: on today's code this test FAILS (AssertionError: assert 'movie' == 'live').
  (B) Then in iptv-backend/app/services/channel_service.py, function classify_channel_type: Delete the replay branch ... If the cause is not where the
  evidence points, say so. Also look at: iptv-backend/tests/test_channel_service_replay_live.py.
  VERIFY: `cd iptv-backend && python -m pytest tests/test_channel_service_replay_live.py -q`. (cat:bugfix; multifile:yes; src:manual; brief:1/2) [feat:iptv_apps-20261002-manual-1a2b3c4d]
```

Idempotent: `apply_to_text` replaces only an **open, unparked, un-briefed** line carrying the tag; a second run finds `brief:i/K` and does nothing; a line
the fleet already checked off, parked, or that left the queue is **skipped** (never inserted behind the fleet's back). The edit uses the ingest's atomic
`edit_progress` (hold -> fetch -> verify branch -> reset to origin -> edit -> `git add OVERNIGHT_PROGRESS.md` only -> commit as `shrike-fleet` -> push with
rebase retry -> release in a `finally`) under the same state lock.

## 5. import-brief: a brief from Claude or a human

```
python3.12 qa/bug_brief.py import-brief brief.json --repo iptv_apps --feat <tag of the existing manual item> [--date D --flow F] [--exec on] [--apply | --progress-file F | (print only)]
```

Same schema, the **same mechanical checks** (no model call; evidence quotes, one file per step, function exists, VERIFY lint, banned / oversize, step caps),
then the same emit and the same idempotent replace. `--feat` is the `[feat:...]` tag of the single item to replace (see `manual_notes_ingest.py list`); without
`--insert` an item that is no longer in the queue is not re-created. An imported test-first step may live anywhere in an existing test directory (no planned
path is imposed). Hand a Claude session the single item, the located file and this schema; it returns a `brief.json`.

### Worked example (`qa/bug_brief_example.json`, a Python bug; evidence must be REAL lines of the repo you import it into)

```json
{
  "repo": "iptv_apps", "flow": "Home Page Categories", "date": "2026-10-02", "platform": "backend",
  "note": "The 00s Replay channel was listed as movie instead of live.",
  "root_cause": {
    "hypothesis": "classify_channel_type() treats every channel whose name contains the word replay as a movie, so the live channel 00s Replay is listed as a movie and shows the download button instead of the record button.",
    "evidence": [ {"file": "iptv-backend/app/services/channel_service.py", "line": 4, "quote": "if \"replay\" in lowered:"} ]
  },
  "approach": "Remove the name-based movie rule; keep the group-based rule. One test reproduces the bug, one guards the neighbouring behaviour.",
  "steps": [
    {"kind": "test_first", "file": "iptv-backend/tests/test_channel_service_replay_live.py", "function": "test_replay_channel_is_live",
     "change": "NEW test file: call classify_channel_type('00s Replay') and assert it returns 'live'. It fails on today's code because the function returns 'movie'.",
     "verify": "cd iptv-backend && python -m pytest tests/test_channel_service_replay_live.py -q"},
    {"kind": "fix", "file": "iptv-backend/app/services/channel_service.py", "function": "classify_channel_type",
     "change": "Delete the `if \"replay\" in lowered: return \"movie\"` branch in classify_channel_type so a replay channel falls through to 'live'.",
     "verify": "cd iptv-backend && python -m pytest tests/test_channel_service_replay_live.py -q"},
    {"kind": "guard", "file": "iptv-backend/tests/test_channel_service_guard.py", "function": "test_news_still_live",
     "change": "NEW test file: classify_channel_type('CNN News') still returns 'live' and classify_channel_type('Movie Night', 'movies') still returns 'movie'.",
     "verify": "cd iptv-backend && python -m pytest tests/test_channel_service_guard.py -q"}
  ]
}
```

## Fallback matrix (never blocks the ingest, never fails open silently)

| situation | result |
|---|---|
| `OVN_BUG_BRIEF=off`, `--no-model`, `OVN_MANUAL_MODEL=off` | nothing marked, single item as today |
| located file hard-banned / > 120 KB / language not handled / missing | `fallback`, 0 model calls |
| model dead / hung / refused (first failed call opens the circuit breaker) | `fallback`, 1 call, bounded by `OVN_BUG_BRIEF_CALL_TIMEOUT` (150 s) and `OVN_BUG_BRIEF_BUDGET_S` (300 s) |
| invalid JSON / validation failure after the repair | `fallback` with the first errors in the reason |
| test-first test passes on the current code | `fallback` ("VACUOUS") |
| the fleet already took / parked the item, or it left the queue | `skipped` |
| hold / push race on the apply | stays `pending`, retried by the sweep (3 tries) |

## Files, env, install

| piece | where |
|---|---|
| `qa/bug_brief.py` | the stage + CLI (`brief`, `import-brief`) |
| `qa/manual_notes_ingest.py` | hook: `brief_wanted / spawn_brief / brief_run_pending / cmd_brief`, `edit_progress` (the old `enqueue` body, now shared), `sweep` pass, `brief` subcommand |
| `qa/bug_brief_example.json` | the worked example |
| `scripts/test/test_qa_bug_brief.py` | the tests (stub model, fake pytest runner, git fixtures, env -i) |
| `state/bug_briefs/<feat>.json`, `logs/bug_brief.log` | the full result of each run, spawned-process log |

Env: `OVN_BUG_BRIEF` (off), `OVN_BUG_BRIEF_SPAWN` (off = leave it to the sweep), `OVN_BUG_BRIEF_BUDGET_S`, `OVN_BUG_BRIEF_CALL_TIMEOUT`, `OVN_BUG_BRIEF_EXEC`
(auto|on|off), `OVN_BUG_BRIEF_EXEC_TIMEOUT`, `OVN_MANUAL_MODEL`, `LITELLM_BASE`, `LITELLM_MASTER_KEY`.

Install (integrator; nothing here is installed): copy `qa/bug_brief.py`, `qa/bug_brief_example.json` and the updated `qa/manual_notes_ingest.py` to the box (atomic `mv`; the
existing `manual_notes_cron.sh` sweep then runs pending briefs), register `test_qa_bug_brief.py` in `run_all.sh` (done in this branch).

## Real trial (2026-10-02, real local model on the box, read-only `git clone --shared` scratch clones of iptv_apps and xlite; nothing written to a live repo or backlog)

Each run: `qa/bug_brief.py brief ... --progress-file <local copy of OVERNIGHT_PROGRESS.md with the real single item>`. Locator picks vary run to run for the SAME note
(countries filter: `StreamsListScreen.kt` in 3 runs, `DiscoverScreen.kt` in 2); the table is what the brief did with what it was given.

| bug | stack | outcome | model calls | wall |
|---|---|---|---|---|
| xlite tech tree: `Weapon Upgrades` researchable before `Improved Ammo` (my own pick; `tech_manager.gd`) | GDScript, real GUT run | **ok, proven-red**: GUT failure `Should not be able to research Weapon Upgrades before Improved Ammo`; fix = one line in `research_tech` | 3 (1 plan repair for an `e.g.`) | 49 s |
| 00s Replay shown as movie (backend classifier `playlist.py`, explicit path) | Python, real pytest in the repo venv | **ok, proven-red** (`assert _detect_stream_type('00s Replay', group_title='Movies') == 'live'` fails on today's code, 2 s) | 3 | 59 s |
| Chickadee countries filter, Android (`StreamsViewModel.kt`, locator's `StreamsListScreen.kt` as also-file) | Kotlin, real gradle (`:app:testGoogleTvDebugUnitTest`) | ok, 4 valid briefs (3 with the red proof off); in the one run that executed the model's Kotlin test it did not compile -> `invalid`, flagged "not executed by the harness" (a trivial failing Kotlin test IS proven red in 10 s, so the machinery works; the 27B's Kotlin test is the weak link) | 1-3 | 25-70 s |
| Chickadee discover "+" does not refresh Home | Kotlin | **fallback to the single item** (3 + 2 attempts): the real fix needs a new cross-ViewModel refresh in 2 files; the model kept relying on an invented `refreshHomeStreams` / `channelAddedEvent` -> rejected by the grounding check | 3 + 2 | 60-170 s |
| 00s Replay download spinner / record button, Android (locator) | Kotlin + Python mixed | **fallback**: invented functions (`DvrRecordButton`, `isDvrEligible`), later a Python fix with a gradle verify (cross-language, now rejected with a clear message), once the first plan call timed out at 150 s (circuit breaker, 1 call) | 1-3 | 29-150 s |

Honest reading: the stage lands a validated, proven brief where the cause sits in ONE testable file (2 of 2 Python / GDScript trials; Kotlin valid but test unproven) and
falls back, as designed, where Qwen invents helpers, mixes layers, or the fix is genuinely multi-file. The diagnosis stays the model's hypothesis.

## Integration constraints found while building this (read before enabling)

0. **`./gradlew :app:test --tests ...` cannot work on a flavored Android module.** AGP's umbrella `test` task rejects `--tests` (`Unknown command-line option '--tests'`, measured on
   iptv-android). `scripts/ovn_gradle_flavor_guard.sh` rewrites `:app:testDebugUnitTest` into exactly that umbrella task, and existing queue items already carry
   `:app:test --tests "..."` VERIFYs (iptv_apps `OVERNIGHT_PROGRESS.md`), so those VERIFYs fail on the task name alone. The bug brief uses the concrete variant task
   (`:app:testGoogleTvDebugUnitTest`, read from `build.gradle.kts`) and its lint REJECTS the umbrella task with `--tests`. The guard (not mine to edit) should do the same.

1. **Red tests never land.** Hence the fused first item. The stage runner's decompose prompt still re-decomposes each item itself (for non-Godot items it asks
   for code + test in the same step, which matches the fused item).
2. **GODOT MODE in `ovn_stage_runner.sh` decompose is SOURCE ONLY** ("Do NOT create or modify any GUT/test .gd file", verify = `gdparse`, `_doable` drops lines naming
   `tests/*.gd`). FIXED 2026-10-02: for `.gd` only source fix items are emitted (see above). A harness-verified red test (stored as `reference_test`) could be applied by
   the harness instead of the 27B: not done here (the runner is not mine to edit).
3. **`ovn_item_hash` keys on the `[feat:]` tag**, so all items of one brief share ONE failure / no-op / token-cap streak. That is what the shared tag was asked for,
   but the per-item caps (fail cap, token cap) are then per BUG, not per step. The policy builder should know.
4. The brief replaces the single item minutes after it was enqueued; a cycle that already started on the single item may land it first, in which case the new items
   become `already-satisfied` no-ops (harmless) or the replace is skipped (item checked off).

## Known limits

- The planner is Qwen: briefs for Kotlin and GDScript will often fail validation (then the single item runs as today). The value is where it validates.
- Evidence comes from the located file(s); if the locator pointed at the wrong layer the brief says so only if the model notices.
- Kotlin red proof runs `./gradlew ... --offline --console=plain` in the throwaway worktree (needs the box's warm gradle cache and `ANDROID_HOME`); without them it is `not-run`.
- The regex function ranger has no parser: unusual formatting (one-line classes, nested generics in extension receivers) can cut a range short.
