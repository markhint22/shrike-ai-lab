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
| FAIL | high confidence: frozen-test edit (D), all effective assertions gone from a test that remains (E), an assertion turned into a tautology while the effective count dropped (A_ASSERT_NOOP) |
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
