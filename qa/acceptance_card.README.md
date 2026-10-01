# Gate S0 - acceptance card (`qa/acceptance_card.py`, `qa/card_lint.py`)

Qwen drafts an **acceptance card** for a backlog item: 3-7 checkable bullets, ONE `verify_cmd`, the files that change, a risk class
(A/B/C) and a `needs_human_review` flag. **Qwen's output is advisory text.** A deterministic linter (`card_lint.py`) and an execution
check decide whether the card is usable; the model never decides anything and its command is not run until the linter has proven it is
read-only and allow-listed.

Scope of the pilot: python and vitest unit/API items only. GDScript, Swift, Kotlin, Vue/TSX/CSS/HTML and non-code targets are excluded
explicitly (verdict `NA`, no model call). Audit items ("Confirm/Verify/Audit ...", "no change needed") are `NA` too.

## What it does, in order

1. **Scope check** (`card_lint.eligibility`, `classify_item`) -> `NA` for out-of-scope items. Costs no GPU.
2. **Context** (git only, at the base ref): target file head, sibling files, related tests, how pytest is run and how tests import.
3. **Draft** one JSON card via the local litellm (`127.0.0.1:4000`, model `qwen-dflash-27B`, urllib only, temperature 0.1, `max_tokens` 700, JSON
   mode, 90 s hard timeout, ONE request at a time, at most 2 requests per card: 1 retry on transport/parse failure; `--repair` instead uses the
   retry to feed lint errors back once). Non-loopback URLs are refused. Any model error -> `UNVERIFIED`.
4. **Lint** (pure, no model, ~0 ms). See the rule table.
5. **Execution check**: run `verify_cmd` in a detached worktree at the base ref (scrubbed env, nice/ionice, own process group killed on timeout,
   120 s default, proxies poisoned, no secrets). For every item kind it must FAIL before the change.
6. Optional `--head <ref>`: also run it at the head ref (it should pass after the change).

## Verdicts (shadow mode; exit 0 always)

| verdict | meaning |
|---|---|
| `PASS` | lint-clean AND the verify fails at the base ref for a legitimate reason (missing module/test file, assertion, import error) |
| `FAIL` | lint rejected the card, or the verify is itself broken (SyntaxError/NameError in the check), or it selects no tests for an item that adds none |
| `FLAG` | usable but suspicious: the verify **already passes** at base (vacuous, or the item is already done), lint flags, or it still fails at `--head` |
| `NA` | out of scope / audit item (no model call) |
| `UNVERIFIED` | model timeout/error/invalid JSON, repo or ref missing, exec infra problem (timeout, missing third-party dependency, no pytest in the env) |

`PASS` means "well-formed, non-vacuous, and able to detect not-done". It does **not** mean the card is a correct spec of the feature (see limitations).

## CLI

    python3 qa/acceptance_card.py check --repo <name> --base <ref> [--head <ref>] --item "<backlog line or 'path - description'>"
        [--card-json FILE]      skip the model, lint+exec a stored card (deterministic; what the tests use)
        [--no-exec] [--exec-timeout S] [--venv-bin DIR] [--repair] [--llm-url URL] [--model NAME] [--no-record] [--enforce-exit]
    python3 qa/acceptance_card.py pilot  --repo <name> --base <ref> --items-file F [--items-file F2] --out DIR [--limit 30] [--compare-existing] [--repair]
    python3 qa/acceptance_card.py relint --repo <name> --base <ref> --cards cards.jsonl --out DIR     # re-lint stored cards, no GPU
    python3 qa/card_lint.py --verify 'grep -q foo a.py' --item 'a.py - Add foo ...' [--repo-root DIR]  # lint a bare VERIFY command

Last stdout line is exactly one JSON verdict object (`qa_common.verdict`). Mode comes from `OVN_QA_ACCEPTANCE` / `state/qa_modes.json` (`acceptance`),
default `shadow`. Env: `LITELLM_BASE` (default `http://127.0.0.1:4000`), `OVN_MODEL` (default `qwen-dflash-27B`), `LITELLM_MASTER_KEY`
(sent as a bearer token, never printed), `QA_ACCEPTANCE_LLM_TIMEOUT` (seconds, test hook), `OVN_REPOS_DIR`/`OVN_DIR` as in `qa_common`.
Python: runs under the Mac `python3` and the box `/usr/bin/python3.12` (stdlib only). Test: `python3 scripts/test/test_qa_acceptance.py` (152 checks).

## Lint rules (`card_lint.py`; error = card rejected, flag = usable but suspicious)

- **Status swallowing** (the incident class): `|| echo|true|:|exit 0`, `; true`, trailing `; echo`, `exit 0`, `&`, trailing pipe into a non-asserting
  command without `set -o pipefail` (`| tail`, `| cat`, `jq` without `-e`), no assertion at all.
- **Unsafe / unrunnable**: allow-list of read-only commands (grep, test, python, pytest, vitest, diff, jq -e, alembic, ruff, mypy, read-only git, ...);
  rm/mv/curl/pip/npm install/docker/sudo/bash -c, file-writing redirects, sed -i, find -delete, `python -c` touching network/subprocess/writes,
  backticks, heredocs, compound shell (`if/for/while`), unparseable quoting, absolute or `..` paths, verify > 600 chars.
- **Cannot-fail checks**: `python -c` with invalid syntax (`;` followed by `try/class/def`), `assert True`/`or True`.
- **Existence-only**: `test -e`, `ls`, import-only/`print('OK')`, `py_compile`, `os.path.exists` (error, except removals verified by absence and
  export/re-export items where the import is the check); source-text-only checks (`grep`, `inspect.getsource`, `open().read()`) on behaviour
  items and on test-writing items (error); positive+negative grep on a mechanical edit (flag).
- **Direction**: removal items need a negative assertion; add/create items must not be verified by negative-only checks; replace/rename items need
  both a positive and a negative check (flag). Negation inside `python -c` (`assert not`, `not in`, `!=`, `is None`) counts.
- **Hallucinated references** (these catch what the model gets wrong most): path not at the base ref and not created by the item; `cd` target
  missing; `from pkg.mod import name` where the module is missing / the name is not defined there / the package needs a different cwd; pytest id
  `file::test_x` that does not exist and that the item does not add; `-k expr` selecting nothing; identifier-like string literals in the check that
  appear in neither the item nor the repo (flag); `files` entries that do not exist and are not created by the item; verify unrelated to the item's
  module (flag).
- **Bullets**: 3-7, each >= 12 chars; vague words (`works correctly/properly/as expected`) with no concrete observable are rejected; duplicates,
  off-topic and unspecific bullets are flagged.
- **Risk**: final class = max(model, deterministic floor from auth/billing/quota/migration/webhook/secret keywords and routers/models/services paths);
  class A and any `needs_human_review` stay with a human. The linter never lowers a class.

## Measured (test-automation-agent, python items, 2026-10-01; runs 3-4 looked uncontended on the box GPU)

Files: `qa/acceptance_pilot/*` (30 cards, no-repair and `--repair` runs, plus the history lint summary).

| metric (30 cards, no repair) | value |
|---|---|
| items scanned / excluded | 79 open items; 5 excluded (3 Vue, 1 no-change, 1 `.txt`); first 30 eligible used |
| model failures | 0 / 30 |
| lint pass rate (no lint error) | 21 / 30 = 70% (with `--repair`: 25 / 30 = 83%) |
| fails-before (verify fails at base for a legitimate reason) | 21 / 30 = 70% of all cards |
| verify passes before (vacuous or already done) | 6 / 30 = 20% (7 with repair) |
| verify itself broken (SyntaxError) | 2 / 30 |
| verdicts | PASS 11, FLAG 10, FAIL 9 (repair: PASS 13, FLAG 12, FAIL 5) |
| GPU seconds per card (server-side timings) | mean 4.8, p50 4.7, p90 6.1 (repair: mean 5.7, p90 8.7) |
| tokens per card | prompt ~1460, completion ~226 (repair: ~1960 / ~272) |
| wall per card incl. model | p50 5.3 s, p90 6.6 s; exec check p50 0.75 s, p90 2.6 s; lint ~0 ms |

The plan estimated 1.5-3 GPU-min per T3+/class-A card; measured is ~5 GPU-seconds. **Contention caveat:** once other builders started using Qwen
at the same time, one request took 100-230 s wall (server-side GPU time up to 52 s) and some hit the 90 s timeout -> `UNVERIFIED`. The gate
behaves correctly (never fails open/closed) but must not run while the coder lanes use the GPU.

Reading the first 20 cards (final code, all 20 read in full): 7 sensible and usable (#6, 11, 12, 13, 15, 16, 17); 6 sensible in intent but rejected
(#5 and #14 have broken Python syntax; #7, 9, 10, 20 are source-text-only checks); 3 vacuous (#4, 18, 19: the verify just runs an existing test file
that already passes); 2 wrong (#1 needs a test file nobody will write, #3 selects a test that does not exist); 1 plausible-but-uncertain target (#2);
1 overlong source-text hack (#8). 18 / 20 verdicts were right; the 2 misses: #6 got a false `FLAG` (`query_params` is a Starlette attribute the lint
cannot know) and #12 `PASS` is weak (it runs the whole shared test file that card #11 also creates, so it can pass without its own test). Of the
10 `FLAG`s in the 30: 8 real (4 vacuous existing-test-file, 2 items already done at base - the `max_concurrent_browsers` setting and the `llm_input_tokens`
columns already exist -, 1 wrong target, 1 plausible-target direction flag), 2 weak/false (#6, #23 trivial bullet flag).

**Existing VERIFY lines on the same 30 items** (comparison): 21 / 30 = 70% rejected by the same lint (7 reference a test file that does not exist yet,
7 are `pytest -k` selectors that match nothing, 4 grep-only, 2 `curl | jq`, 2 swallowing pipes, 1 `|| echo`, 1 wrong direction); 2 of 28 executed pass
before the change.

**History check** (lint only, every in-scope VERIFY in `OVERNIGHT_PROGRESS.md`, 548 commands, 501 on done items): 219 = 40% rejected
(`test-id-missing` 53, `path-missing` 49, `weak-existence` 39, `no-assertion` 26, `swallow-or-handler` 28, `existence-only` 29, `direction-mismatch` 20, ...).
The `test-id-missing`/`path-missing` hits are real: spot checks show the referenced test files never existed in git history (e.g. `test_github_ci.py`,
`test_auth_router.py`, `test_api.py`: 0 commits) - those items were credited with a VERIFY that never ran. Precision: three random samples of 40
rejections were read. Before the last fixes 31+4+5 / 31+4+5 (clear true positive / spec-consistent but debatable grep-only / false positive);
after the fixes (3rd sample) 33 clear true positives, 6 debatable (grep-only on a mechanical edit), 1 false positive (`grep -q X && exit 1 || exit 0`,
a working but non-canonical removal idiom). Fixes made from those readings: absence-only removals, import-as-check re-exports, `! a | b` pipeline
negation, quote-aware `$( )`, audit items -> `NA`, backtick-span VERIFY parsing.

## Known limitations

- **`PASS` is not "the card is right".** The lint cannot tell that a well-formed check asserts the wrong thing (e.g. card #10 in an earlier run
  asserted a `RateLimiter` class the item never mentions; only the literal-in-repo flag catches some of this). A human still samples class-A cards;
  Qwen can mirror its own plan.
- A `PASS` card whose verify runs a whole shared test file can pass without the item's own test (card #12).
- The exec check proves "fails now", not "passes after the change"; `--head` does that when a landed change exists (tested on a synthetic repo only).
- **No network namespace**: `unshare -rn` is not permitted for the box user. Network is blocked by (a) the allow-list, (b) poisoned proxy env,
  `PIP_NO_INDEX`, offline npm, (c) a scrubbed env. A python test that opens a raw socket to a public IP is not hardware-blocked.
- Tests run from the live-clone venv path (`backend/.venv/bin`, read-only use, `PYTHONDONTWRITEBYTECODE`); a repo with no venv gives `UNVERIFIED`.
  node/vitest exec is implemented (node_modules symlink, removed before worktree teardown) and unit-tested for the symlink only; no vitest card was
  executed end to end (the TAA open items in scope were all python).
- Two worktrees are created per `check` (lint root + exec); `qa_common.worktree` writes `.git/worktrees` metadata in the clone briefly (spec-mandated).
- GPU: the gate sends one request at a time but takes no lock (spec rule 4); the integrator must not run it while the coder lanes use Qwen.
- Item parsing targets the backlog/progress line format (`- [ ] [T3] path - description. VERIFY: cmd. (cat:x; multifile:y)`); roadmap feature-level
  entries (no file path) are not cards.
- Python-only static checks: JS/TS verifies get the shell/path/direction rules but no import/test-id resolution.
