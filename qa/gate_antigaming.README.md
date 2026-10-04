# gate_antigaming (S3) - anti-gaming diff gate

Deterministic, LLM-free diff gate. It looks at what a change did to the *oracle* (tests) and to *safety code* (error handling) and
reports `FAIL` / `FLAG` with `file:line` evidence. It reads git objects only (`git show`, `git diff`, `git ls-tree`, `git grep`); it
never checks out, executes, or modifies repo code, takes no locks, and writes nothing except the optional shadow log.

## Run

    python3 qa/gate_antigaming.py check --repo <name|path> --base <ref> --head <ref> [--no-record] [--enforce-exit]

- Works under Python 3.9+ (Mac `python3`) and `/usr/bin/python3.12` (box). Needs `git` on PATH.
- `--repo` is a name (resolved by `qa_common.repo_dir`: `$OVN_REPOS_DIR`, `$OVN_DIR/repos`, `~/LocalProjects`) or a directory.
- Prints exactly one JSON line (the `qa_common.verdict` dict). `details` holds `findings[]` (rule, sev, file, line, old_line, msg,
  snip), `counts`, `frozen`, `notes`, `files_in_diff`, `code_files`, `truncated`.
- Exit 0 always, except `mode==enforce and verdict==FAIL and --enforce-exit` => 1. Default mode is `shadow`.
- Env: `QA_ANTIGAMING_DEADLINE` (seconds, default 40) - internal budget. Findings found before the deadline are still reported; no
  findings + deadline hit => `UNVERIFIED`.

Replay (measure flag rate on history, read-only):

    OVN_REPOS_DIR=~/overnight-queue/repos python3 qa/qa_replay.py qa/gate_antigaming.py <repo> --days 30 --limit 2500

## Verdicts

| verdict | when |
|---|---|
| FAIL | high confidence: frozen-test edit (D), all effective assertions gone from a test that remains (E), an assertion turned into a tautology while the effective count dropped (A_ASSERT_NOOP), a newly added test that proves nothing (A_VACUOUS) |
| FLAG | anything uncertain: weakened/dropped assertions, deleted tests, new skips on existing tests, removed guards |
| PASS | EVERY code file in the diff analysed, nothing found |
| NA | empty diff, or no code files (docs/config only) and no frozen manifest hit |
| UNVERIFIED | bad ref, no clone, git missing/failing, crash (via `main_guard`), OR any part of the diff could not be analysed and nothing was found in the rest: more than 400 code files, deadline hit, a test/code file over 800 KB or unreadable, a test file that fails to parse. `details.unanalysed` lists why. A truncated run that DOES have findings keeps its FAIL/FLAG and notes UNANALYSED. The gate never says PASS for something it could not check. |

## Rules

| id | sev | meaning |
|---|---|---|
| E_ZERO_ASSERTS | FAIL | a test with effective assertions before has none now (not moved into a helper that gained asserts) |
| A_ASSERT_NOOP | FAIL | an assertion became `assert True` / `x or True` / `expect(true).toBe(true)` / `assertTrue(True)` and effective count fell |
| A_ASSERT_WEAKENED | FLAG | paired assertion lost strength: exact -> in/ordering -> shape (`is not None`, truthiness, `toBeDefined`, `assertTrue`), `pytest.raises(X)` -> `Exception` |
| A_ASSERT_DROPPED | FLAG | a test lost assertions and the file's total assertions fell |
| A_PARAM_CASES_DROPPED | FLAG | `pytest.mark.parametrize` case count fell |
| A_TEST_DELETED / A_TESTFILE_DELETED | FLAG | tests with assertions deleted, not found elsewhere, subject not removed |
| A_VACUOUS | FAIL | a NEWLY ADDED test whose ONLY assertions are tautologies (`assert True`, `assert 1 == 1`, `assert x or True`, `assert_true(true)`, Kotlin `assert(true)`) or that has no assertion and a placeholder body (`pass` / `...` / docstring only / empty block / says "placeholder"). 3 of 3 true positives in the 2026-10-03 shadow data (iptv `assert True`, xlite `test_placeholder`, closed-captions Kotlin `assert(true)`). A test with one real assertion plus a stray tautology stays the weaker FLAG below; a test that asserts through a helper is never judged vacuous. Shadow like every gate. |
| A_VACUOUS_ASSERT | FLAG | a new or edited test has an assertion that can never fail: `assert 1`, `assertTrue(True)`, `x or not x`, an assert inside `try/except AssertionError/Exception` that swallows it, `with pytest.raises(X): pass` |
| B_SKIP_ADDED | FLAG | skip/xfail/skipif/`it.skip`/`xit`/`describe.skip`/`.only`/`@Ignore`/`@Disabled`/`XCTSkip` added to an EXISTING test |
| B_COVERAGE_EXCLUDED | FLAG | `# pragma: no cover` / `istanbul ignore` / `c8 ignore` added to existing code |
| B_SUPPRESSION_ADDED | FLAG | `# noqa`, `# type: ignore`, `# nosec`, `# pylint: disable`, `eslint-disable`, `@ts-ignore`, `@Suppress`, `swiftlint:disable` appended to an existing line |
| C_ERRORHANDLING_REMOVED | FLAG | try/except (py AST, per function) or try/catch (ts/js/vue/kt/swift, guard-line signatures) removed in a NON-test file (incident shape: shrike-monitor `run_forever`, d45d66f) |
| C_VALIDATION_REMOVED | FLAG | `raise` statements removed from a non-test Python function |
| C_HANDLER_NARROWED | FLAG | `except Exception`/bare narrowed to a specific type |
| D_FROZEN_EDIT | FAIL | file listed in `state/qa_frozen_tests.json` edited, deleted or renamed. Manifest absent / repo absent => `details.frozen = "NA: ..."` |
| F_COVERAGE_LOWERED / F_TESTS_EXCLUDED | FLAG | `fail_under`/`--cov-fail-under`/`coverageThreshold` lowered, `--ignore`/`--deselect`/`norecursedirs`, `-k 'not ..'`, `-m 'not ..'`, `--maxfail`, `-p no:*`, `testpaths`, `--collect-only` added in test config (pytest.ini, tox.ini, setup.cfg, pyproject.toml, package.json) |

Languages: Python by `ast` (assertion units, per-function guards); ts/js/vue (vitest/jest/chai/ava), Kotlin (JUnit/kotlin.test/mockk),
GDScript (GUT) and Swift (XCTest) by a comment/string-masking scanner with bracket matching (python files with syntax errors and files
where brackets cannot be matched are skipped and listed in `details.notes`, never failed).

Assertion strength ranks: 0 tautology, 1 shape-only (`is not None`, truthiness, `toBeDefined`, `assertTrue`), 2 call-recorded,
3 partial (`in`, `>`, `toContain`, `assertGreater`), 4 exact (`==`, `toBe`, `assertEquals`). `assertEquals(true, x)` is treated as shape-only
so `assertEquals(false, x)` -> `assertFalse(x)` is not flagged.

## What is deliberately NOT flagged (legitimate refactors)

- assertions moved into a helper that gained at least as many assertions and is called by the test
- test renamed (same name elsewhere in the diff, or body >= 75% similar to an added test, or identical assertion list)
- duplicate test removed while a same-named / same-body / >= 90% similar copy remains
- tests deleted together with their subject (deleted module/def/class named in the test), a deleted test file whose subject file is deleted
- tests of a subject already undefined at base, or with no callers outside tests (dead code), and test files whose first-party imports do not resolve
- tests replaced: file lost tests but its effective assertion count did not fall and it gained tests (listed in `details.notes` as `offset-deletion`)
- guards delegated to a newly called/referenced helper that itself has try/except, or a diff whose net try/catch count did not fall (ts/kt/swift)
- markers on brand-new lines or in brand-new files (only EXISTING tests/code are flagged)

## Known limitations

- Heuristics, not proofs. A test deleted and replaced by differently shaped tests in another file is a FLAG (it cannot know the new tests cover the same thing). The `offset-deletion` exemption can mask "delete a strong test, add unrelated asserts in the same file".
- C rules are function-granular for Python and file-granular (guard-line signatures) elsewhere; a consolidating refactor (4 try/catch sites -> 1 shared helper) still FLAGs.
- Kotlin/Swift/GDScript/JS test discovery is regex+brace based; unusual DSLs (Spek, Kotest string specs, JS `test.each` tables, Playwright fixtures) are not understood, so their removals are invisible rather than mis-flagged.
- Dead-subject detection uses `git grep -w`; short common identifiers always look "referenced".
- `D_FROZEN_EDIT` only knows files named in the manifest; building/refreshing the manifest is not done by this gate.
- Commit messages are never trusted (agents write them), so "remove orphaned test" in a message does not exempt anything.
- Config rule is a regex over added lines of known config files: coverage thresholds and the deselection/narrowing flags listed above; other mechanisms (CI yaml, conftest hooks) are not seen.
- Tautology detection is syntactic: a vacuous assertion built from a helper (`assert always_true()`) is not seen.
- Python 3.9 (stock macOS /usr/bin/python3) is supported and was run.

## Re-measured after the fix round (box, python3.12, same window, 9,892 commits)

PASS 4029, FLAG 109, FAIL 2, NA 5724, UNVERIFIED 27 (0.27%, new: commits the gate could not fully analyse; before the fix these were PASS). New A_VACUOUS_ASSERT
flags: 5 (3 billwatch `expect(true).toBe(true)` placeholder tests = real, 1 swallowed `assert` inside `try/except Exception: pass` in iptv paywall tests = correct
flag of an intentional pattern, 1 useChromecast.test.ts not read). `foo() == foo()` is rank 1 (weakening) not vacuous because determinism tests
(`assert stable_hash("a") == stable_hash("a")`) are legitimate. Incident controls unchanged (d45d66f FLAG, 29ecdf3c0 FAIL, f254a8d4c FAIL).
The table below is the ORIGINAL pre-fix replay, kept for comparison.

## Measured (replay on the GPU box, origin/develop, last 30 days, every non-merge commit, 2026-10-01)

| repo | commits | NA | PASS | FLAG | FAIL |
|---|---|---|---|---|---|
| gitlark | 2500 | 1562 | 924 | 13 | 1 |
| billwatch | 2294 | 1307 | 960 | 27 | 0 |
| iptv_apps | 1876 | 1091 | 762 | 23 | 0 |
| shrike-monitor | 1326 | 739 | 566 | 20 | 1 |
| test-automation-agent | 1930 | 1039 | 868 | 23 | 0 |
| total | 9926 | 5738 | 4080 | 106 | 2 |

- Flagged commits: 108 = 1.1% of all commits (2.7% of the 4,188 commits that touched code). NA = no code files in the diff (queue/docs chores).
- Every flagged commit was read (finding + commit subject; diff for about a third). Classification by the builder: 23 real degradation
  (tests bent or gutted to pass, assertions removed/weakened, a feature stripped), 75 correct flag of an intentional change the diff alone cannot
  prove safe (staged "remove test X" items, tests of modules deleted in another commit, behaviour changes), 10 false positives
  (refactors the rules misread: guard moved into a helper/util/schema, duplicate block restored, migration squash) = 9.3% of flags.
- Incident replay: `shrike-monitor d45d66f` (run_forever loses its try/except) -> FLAG C_ERRORHANDLING_REMOVED at scheduler.py:338.
  Same repo `29ecdf3c0` (a staged step cut 399 lines of test_scheduler.py and left `test_heartbeat_two_cycles` assertion-free) -> FAIL E_ZERO_ASSERTS;
  gitlark `f254a8d4c` (test body replaced by a comment and `pass`) -> FAIL.
- Runtime per commit (5 replays in parallel on the box): p50 25-31 ms, p90 62-125 ms, max 5.1 s (very large commits). Python startup included.

## 2026-10-03 false-positive fixes (diagnosis F4: 5 of 8 shadow flags were false positives; replay with `qa_replay.py --gold`, rows F1-F6)

* `C_VALIDATION_REMOVED`: raises that disappeared from a function are also treated as delegated when the function gained a NEW FastAPI dependency
  (`Depends(x)` / `Security(x)` in the signature or `dependencies=[...]` in the decorator that the old function did not reference), e.g. inline 401/403 raises
  replaced by `Depends(require_admin)` (billwatch `d52bdaf9`). Previously only same-module helpers counted.
* `C_ERRORHANDLING_REMOVED`: a guard that was WIDENED is not a removed guard: some old try whose protected statements all persist in a new try now has a strictly
  wider handler (`except ValueError` -> `except (ValueError, TypeError)`), and no exception type the old function handled is lost (iptv `c4efb13d`). Honest limit: this
  cannot tell "widened" from "one guard widened and another deleted" - the count drop is attributed to the widening. It stays a FLAG-only, shadow rule.
* `A_ASSERT_WEAKENED`: a swapped assertion is only a weakening when the test's NET strength is lower (fewer effective assertions or a lower rank total); `pytest.raises`
  replaced by three exact dict asserts is not (shrike-monitor `bd7d0346`).
* `F_CLAIM_TEST_ONLY`: skipped when the subject names a touched test file (path, basename or stem >= 5 chars: the named file IS the test), or when the commit's diff of
  its test files touches no assertion-like line and no test definition (a helper/resource edit, xlite `8da3d53f` `dir.free()`). A product-fix claim whose diff rewrites an
  assertion still FLAGs (iptv `e590eef7`).
* Kotlin/Swift backticked identifiers (`` fun `it's a name`() ``) no longer open a char literal in the masker: the file used to be UNVERIFIED "could not be parsed".
  Kotlin `assert(true)` / `assert(x || true)` now rank 0 (tautology).

## 2026-10-04 audit rules (qa/ag_h13.py; all SHADOW; kill switch `OVN_QA_AG_H13=off`)

Driven by the 420-commit landing audit (ghost tests, dead helpers, flip-flops, vendored-code edits, live-file deletes). Config: `qa/test_collection.json` (what each repo's verify command collects), `qa/frozen_paths.json` (vendored paths).

| rule | sev | fires when |
|---|---|---|
| `D_DEAD_SYMBOL` | FLAG | a NEWLY ADDED public python `def`/`class` or GDScript `func`/`class_name` in non-test code whose name has no production referencer (only tests/docs/own definition). Excludes `_x`, dunder, `test_*`, decorated functions (routes/fixtures/tasks), model/schema/enum/exception classes, GDScript `_on_*`; a name found as a quoted string (`call("x")`, `connect(..., "x")`) is a reference; own-file refs inside another NEW dead symbol do not save it, a module-level statement does. |
| `E_TEST_NOT_COLLECTED` | FLAG | a newly added test file the verify command would not collect: iptv `test_*.py` outside `iptv-backend/tests/`; xlite `.gd` test outside `tests/`, in `test/`, `*_test.gd`, not `test_`-prefixed, not `extends GutTest` (subdirs of `tests/` count as collected unless `OVN_GUT_SUBDIRS=off`); other repos: nearest pytest `testpaths`. |
| `F_REVERT_OF_RECENT` | FLAG | >=80% of a file's changed lines are the exact inverse of one of the last 20 commits touching it AND that commit's own change is >=50% undone (a creation commit never counts). Also counts per file in `state/qa_revert_counter.json`; >=6 inverse commits in 24h writes ONE `alerts.log` warn per file/day (parks nothing). Bookkeeping files (md/uid/OVERNIGHT_*) ignored. |
| `D_FROZEN_EDIT` | FLAG (FAIL only if gate mode `antigaming_frozen` = enforce) | edit/delete/rename under a frozen path (xlite `addons/*`; every repo `vendor/*`, `third_party/*`). Review fix: it has its OWN mode switch (`qa/qa_enforce.sh antigaming_frozen enforce` or env `OVN_QA_ANTIGAMING_FROZEN`; `off` skips the rule) because a FAIL from the shared `antigaming` gate blocks the merge prefix once that gate is flipped to enforce; flipping `antigaming` alone leaves every new h13 rule non-blocking (all FLAG). Two keys: a vendored edit blocks a merge prefix only when BOTH `antigaming` and `antigaming_frozen` are enforce (`antigaming_frozen` alone only changes the severity inside a gate that qa_enforce_run does not consult). |
| `D_FROZEN_NEWFILE` | FLAG | a new file created under a frozen path. |
| `C_FILE_DELETED_LIVE` | FLAG | a deleted non-test file one of whose public symbols (not redefined elsewhere) is still referenced in code by a non-test file, or by a surviving test file. |
| `C_TEST_ORPHANED` | FLAG | a symbol removed from non-test code (and defined nowhere at head) that a surviving test still references in code (string literals do not count). |
| `A_MOCK_ONLY` | FLAG | a new/changed python test whose only assertions are `assert_called*`/`call_count`/`called` on a mock created in that test (MagicMock/Mock/AsyncMock/patch). Noisy by design: a DB-call-verification test of a real function is also caught. |
| `A_MIRROR_EXPECTED` | FLAG | a new/changed GUT assertion whose actual and expected values both call the same non-builtin function on the same input (directly or via a `var expected = f(x)`). |

Replay (qa_replay.py, last 150 develop commits, 2026-10-04): iptv_apps 18.7% of commits carry a new-rule flag (E_TEST_NOT_COLLECTED 13, F_REVERT_OF_RECENT 14, A_MOCK_ONLY 1), xlite 32.0% (D_DEAD_SYMBOL 29, F_REVERT_OF_RECENT 28, C_TEST_ORPHANED 15, E 4, C_FILE_DELETED_LIVE 2, D_FROZEN_NEWFILE 2). A 420-commit iptv window adds D_DEAD_SYMBOL 16. Precision: all 28 distinct D_DEAD_SYMBOL flags (16 iptv, 12 xlite) were checked against `git grep` at the flagged commit: every one is referenced only by tests/docs; F_REVERT flagged 26/26 damage_preview.gd commits and 10/18 engagement_tracking_service.py commits in the window. Known benign flags: a staged pipeline that lands a helper in step 0 and wires it in step 1 is flagged at step 0; `E_TEST_NOT_COLLECTED` on a stub test file that does not yet extend GutTest.

Related (not in this gate): `-ginclude_subdirs` on the three GUT command sites (`OVN_GUT_SUBDIRS=off` disables), `scripts/lib_new_tests.sh` explicit run of a cycle's new/changed tests in the stage runner (`OVN_RUN_NEW_TESTS=off` disables), `scripts/ovn_test_collect_canary.sh` (ghost-test canary, cron line in `scripts/cron.txt`, not installed), `proposals-2026-10-04/iptv-ovn-verify-collect-app-tests.patch` (opt-in `OVN_COLLECT_APP_TESTS=on` -> also `pytest app`; default OFF until the app/** cleanup lands).
