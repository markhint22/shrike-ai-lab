# gate_scanners (S5, key: `scanners`)

Baseline-aware deterministic scanners over the CHANGED files of a range. Shadow-first, never blocks on infra problems.

    python3 qa/gate_scanners.py check    --repo R --base REF --head REF [--tools a,b] [--baseline auto|stored|base|none]
                                         [--timeout S] [--no-record] [--enforce-exit]
    python3 qa/gate_scanners.py baseline --repo R --ref REF [--tools a,b] [--timeout S]
    python3 qa/gate_scanners.py findings --repo R --ref REF [--tools a,b]      # diagnostic: every finding of a full scan (redacted)

Prints exactly one JSON line (the qa_common verdict dict). Exit 0 always, except `OVN_QA_SCANNERS=enforce` + FAIL + `--enforce-exit`.
Run it with python3.12 on the box (default `python3` there is 3.14) or the Mac `python3`; stdlib only.

## What runs

| cell | scope | notes |
|---|---|---|
| ruff | changed `.py` | `--isolated` (ignores repo config), select `F,E9,PLE,B006,B015,B018,B02x,B032,S102,S301,S302,S307,S324,S501,S506,S602,S605,S608`; ignores cosmetic F401/F403/F405/F841/F811/F541. Security (`S*`) hits in test files dropped. |
| mypy | changed `.py` | per top-level directory (cwd = that dir so `app.x` resolves and duplicate-module clashes between sub-projects cannot abort), `--ignore-missing-imports --follow-imports=silent`. **Advisory by default** (see below). |
| bandit | changed `.py` | skips B310,B101,B311,B404,B603,B607,B105,B106,B107,B110,B112,B108,B104 (+B310, noisy on constant URLs); test files dropped. |
| semgrep | changed `.py/.js/.ts/...` | ONLY `qa/semgrep_rules.yml` (14 rules, local, `--metrics=off`, no registry, no network). |
| gitleaks | the commit range `merge-base(base,head)..head` (new commits only; a secret added then removed inside the range is still caught) | `--redact`; output is rule id + file:line only, the matched line is only hashed. |
| pip-audit | changed `requirements*.txt` | only exact `==` pins are audited (`--no-deps --disable-pip`); unpinned lines are counted in the cell note. Needs network. |
| npm-audit | changed `package.json` / `package-lock.json` | `npm audit --package-lock-only` in that dir; needs the lockfile and network. |

## No false confidence (review fixes)

* **Range** is `merge-base(base, head)..head`, and the base-ref scan runs at the merge-base: a develop that moved ahead of the branch
  does not get its own changes blamed on the branch. No merge-base -> UNVERIFIED.
* **Suppression is ignored**: ruff `--ignore-noqa`, bandit `--ignore-nosec`, semgrep `--disable-nosem`, gitleaks `--ignore-gitleaks-allow`
  with an explicit trusted `-c` (built-in rules only) and an empty `-i` ignore file; `.semgrepignore`, `.gitleaksignore`, `.gitleaks.toml`
  and `.bandit` are deleted from the throwaway worktrees. A change cannot silence the gate on itself. (Side effect: a NEW legitimate
  `# nosec` line now shows up as a finding; fix it or accept the FLAG.)
* **Paths** are read NUL-separated (`git diff -z`), so non-ASCII / odd names are scanned, not dropped.
* **Excluded dirs**: only unambiguously vendored dirs (`node_modules .venv venv site-packages .git __pycache__ Pods .gradle DerivedData .next htmlcov`)
  are skipped, at any depth. `env build dist vendor coverage` are real package names too: Python there IS scanned, only JS/TS (minified
  bundles) is skipped. `mocks`/`spec` are no longer treated as test dirs (`tests/ test/ __tests__/ e2e/ fixtures/ test_*.py *_test.py conftest.py` are).
* **Every skip is visible**: `details.skipped` (counts per reason), `details.unscannable` (up to 5 paths per reason), `details.test_findings_excluded`.
* **Cannot-check is never PASS/NA**: a changed `.py/.js/.ts` that is missing, over 1 MB, binary or unreadable -> UNVERIFIED (unless a real finding exists,
  which wins); all changed files in vendored dirs -> UNVERIFIED (not NA). NA is only for a truly empty range.
* A range with commits but no net diff (secret added then removed) still runs gitleaks.
* Messages never carry source string literals or token-like runs (mypy embeds `Literal['...']`): quoted strings -> `<str>`, 24+ char runs -> `<redacted>`.
* `--timeout abc|0|-5` -> UNVERIFIED "invalid --timeout" (not "gate crashed").

Tools are found via `QA_TOOL_<NAME>` env override, then `~/qa-venv/bin`, `~/qa-tools/bin`, then `PATH`.

## semgrep rules (`qa/semgrep_rules.yml`)

ERROR (blocking class): shell=True with non-literal cmd, os.system/popen non-literal, eval/exec non-literal, pickle/marshal/unsafe yaml.load,
`verify=False`, SQL built from f-string/format/%/concat, JS eval/new Function.
WARNING (FLAG): shell=True literal, hard-coded secret in a credential-named variable, FastAPI POST/PUT/PATCH/DELETE route with no
`Depends`/`Security`/`dependencies=` (router-level `APIRouter(dependencies=...)` is honoured; login/webhook/health-style routes exempt),
logging of credential-like values / headers / DB URL, bare/broad `except` that only `pass`/`continue`, mutable default args, JS innerHTML assignment.
All rules exclude test files. Each rule has a seeded positive and a benign look-alike in `scripts/test/test_qa_scanners.py`.

## Baseline

* `baseline` scans every tracked file at REF and stores a fingerprint multiset in `state/qa_baselines/scanners/<repo>.json`
  (atomic write; per-tool cell status recorded). Audit tools are never stored.
* Fingerprint = `sha1(tool | rule | file | whitespace-normalized text of the flagged line)` -> stable across line shifts.
  Counting is a multiset: copying an already-baselined bad line counts as 1 new finding.
* `check` reports only findings not in the baseline. `--baseline auto` (default) uses the stored baseline for a tool when that cell
  was OK, otherwise scans the same files at `--base` (rename-aware: renamed files are scanned at their old path and matched).
  `base` forces the base-ref scan (most precise, ~2x cost); `stored` never scans base; `none` counts everything.
* pip-audit / npm-audit ALWAYS use the base-ref scan: advisories appear over time, a stored baseline would call every newly
  published advisory "new".
* Re-baseline after each passing merge (or daily). A stale baseline only causes extra FLAGs on files touched since, never misses.

## Verdicts

* FAIL: new blocking-class finding: any provider-specific gitleaks rule hit (generic-api-key / curl-auth-header are FLAG only), semgrep ERROR, bandit HIGH (non-LOW confidence), ruff F821/F822/F823/E902/syntax error,
  mypy `[syntax]`, npm audit high/critical.
* FLAG: any other new finding.
* UNVERIFIED: no new findings but a non-advisory cell could not run (missing tool, timeout, no network, garbage output, base scan failed). Never PASS.
* NA: nothing to scan / gate off. PASS: scanned, nothing new.
* A missing tool never hides another tool's findings: the verdict is the worst finding, the unverified cell is listed in `details.cells`.
* `QA_SCANNERS_ADVISORY` (default `mypy`): new findings of these tools go to `details.advisory_new`, do not change the verdict, and their UNVERIFIED cell does not downgrade a PASS.

## Tests

    python3.12 scripts/test/test_qa_scanners.py        # box: 102 checks incl. real tools; Mac: real-tool checks print SKIP

Logic tests use stub tools through `QA_TOOL_*` so they run anywhere; audits are mocked (no network). The entry point is exercised
by absolute and relative path under `env -i` with a minimal PATH.

## Known limitations

* mypy is noisy on untyped/ORM-heavy code and its results depend on which other files are visible; hence advisory. Cold run is the slowest cell (10-25s).
* pip-audit only sees exact `==` pins (most repos here use `>=`); nothing is resolved. npm audit needs a lockfile next to the manifest.
* semgrep FastAPI-auth rule cannot see `include_router(..., dependencies=...)` in another file (FP) and treats `Depends(...)` anywhere in the route as auth.
* gitleaks scans commit diffs of the range only (secrets in tests/docs stay advisory; a real key in a test file is not blocking); a secret already in the base is the baseline's job. gitleaks hits in tests/docs (fake tokens by design) go to `details.advisory_new` and never move the verdict.
* Only Python (+ a few JS rules) are covered by the local ruleset; Swift/Kotlin/shell get gitleaks only.
* Line-text fingerprints change when the flagged line is edited (the finding then counts as new once).
* Orphaned grandchild processes after a tool timeout are not killed (qa_common.run kills only the direct child); worktrees and scratch dirs are cleaned (tested).
* mypy honours repo config and `# type: ignore` (advisory tool, so it cannot move the verdict anyway).

## 2026-10-03 additions (diagnosis F7)

* **Seeded-positive replay**: `python3 qa/gate_scanners.py selftest [--tools a,b]` builds a throwaway repo, commits a hardcoded secret (gitleaks), a vulnerable pin
  (`requests==2.19.0`, pip-audit; needs network) and a bandit B602 `shell=True` call on top of a clean base, runs the real `check` on each plus a benign change, and prints
  per-seed CAUGHT / MISSED / UNMEASURED with `recall` over the measurable seeds. A tool that cannot run leaves its seed UNMEASURED (never caught, never missed). Verdict:
  PASS (all measurable seeds caught, benign not flagged) / FLAG (recall gap) / UNVERIFIED (nothing measurable). Never recorded to `state/qa_shadow`. Secret-shaped seeds are
  assembled at run time so no secret literal is committed.
* **Original mypy messages**: `redact_msg(strings=True)` now masks only string literals (`Literal[...]`, single-quoted text, free-text double-quoted text) and keeps
  double-quoted identifiers/type names, so advisory output reads `Argument 1 to "make_token" has incompatible type "str"; expected "int"` instead of `<str>` everywhere.
  Token-like runs (>= 24 chars) are still redacted. Baseline fingerprints never used the message, so nothing shifts.
* **Paused repos are skipped** (NA "repo is paused"): `qa_common.paused_repos()` = env `QA_PAUSED_REPOS` (`none` = nothing) + `qa/qa_paused_repos.txt` (shrike-monitor,
  shrike-notify) + `state/qa_paused_repos.txt` + (outside QA mode only) repos whose aider_fix lanes in `tasks.json` are all disabled.
* Not done: weekly full-manifest `pip-audit`/`npm audit` (they still run only when a manifest is in the diff).
